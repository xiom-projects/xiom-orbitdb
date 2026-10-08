<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# XIOM ORBITDB -> compiler lane: findings (pin v0.64.0)

**Relay:** hand this file to the compiler-lane session together with the
matching `docs/repro/<bundle>/` directories from the ORBITDB repo
(`E:\xiom-projects\xiom-orbitdb`). ORBITDB is a consumer lane; it does not
edit the compiler tree. Read-only compiler-source references below were
located while triaging and are evidence, not patches.

**Pin this file was produced on (2026-10-08):**

| Component | Version / hash |
|---|---|
| compiler | v0.64.0 (`%LOCALAPPDATA%\xiom.new\bin\xiom.exe`; Linux WSL same release) |
| stdlib | `E:\xiom-lang\stdlib` @ `a677338` (2026-10-08) |
| compiler lane | `0c5337e0` (2026-10-08; m216 alias fix + lazy builtin probe -- likely touches C-ORBIT-01, re-test on next archive) |
| env | `XIOM_STDLIB=E:\xiom-lang\stdlib`; `XIOM_RUNTIME_DIR` retired (env-free, installed R65 layout) |

**Consumer impact in one line:** the 93-test conformance suite of a
database engine did not compile on v0.64.0 (218 type errors, then a codegen
C001); after working around the findings below it is **93/93 green x2**, and
the crash/reopen WAL probe is green on Windows + WSL. These defects are on
the critical path of any storage/collection code that uses `Vec[Option[T]]`
caches, cross-module `Result` aliases, or nested-field `&mut` methods.

## Open findings

| Date | Finding | Evidence | Workaround in ORBITDB | Impact |
|---|---|---|---|---|
| 2026-10-08 | **C-ORBIT-01: a cross-module generic type alias in return position (`pub type DbResult[T] = Result[T, DbError]`) is not resolved at the consumer.** A match-bound `Ok(payload)` loses its type: method calls drop the receiver (`'get_column' expects 2 argument(s), found 1` / `expected Row, found Int`), zero-arg methods on the raw binding reach codegen as an unresolved symbol (`C001 'column_count'`), and codegen warns `unknown type 'DbResult' -- defaulting to i64` (10x per suite run). | `docs/repro/ok-method-receiver/probe_import.xi` (A/B/C broken, D/E/F/G green); `probe_rebind.xi` (H broken at codegen, I green); `probe_only_i.xi` green. App: conformance suite 4 T001 -> C001 -> green after rebind; `probe_wal_file.xi` read_file_lines payload printed raw addresses until rebind. | rebind the payload through an explicitly typed local before any access: `let d: Row = decoded;` (probe_only_i), or call the explicit receiver form `Row.get_column(&decoded, 0)` | silent wrong values / no-arg methods emit garbage symbols; breaks every consumer of aliased cross-module `Result` returns (stdlib `io.read_file_lines`, packages) |
| 2026-10-08 | **C-ORBIT-02: assigning an Option into a `Vec[Option[T]]` element poisons the slot.** After `v.push(None); v[0] = Some(x);` (or any Option-to-slot write: Some->Some, Option[Str], None->None) the element matches NEITHER `None` NOR `Some(_)`; every `match` over it silently runs no arm and execution falls through. No diagnostic. `Vec[Int]` writes, enum-vector writes and struct-field Option writes are all fine. | `docs/repro/option-vec-assign/probe.xi` (V1/V3 silent, V2/V4/V5 green); `probe2.xi` (V6 Some->Some silent, V8 Option[Str] silent, V9 None->None silent, V7 enum fine, V10 untouched slot fine). App: BufferPool.put corruption -> `buffer_pool` + `storage_engine` suite failures; `tests/probes/probe_write_drop2.xi`. | never index-assign an Option into a Vec element; rebuild the Vec and assign the Vec (`src/storage/page.xi BufferPool.put`); struct fields are safe | silent wrong behavior + broken exhaustiveness in caches/pools/option-vectors; would corrupt any `Vec[Option[T]]` structure |
| 2026-10-08 | **C-ORBIT-03: a method call whose receiver is a nested field mutates a temporary copy.** `o.inner.bump()` inside a method, and `eng.buffer_pool.put(page)` anywhere, execute on a copy; the `&mut` write-back is lost. Explicit `Inner.bump(&mut o.inner)` and copy-mutate-writeback work. No diagnostic. | `docs/repro/nested-field-mut/probe.xi`: A=0 (lost), C=0 (lost), B=1, D=1 (green). App: `StorageEngine.cache_page` -> `storage_engine: cache/lookup` suite failure; `src/storage/page.xi`. | copy the field to a local, mutate, write it back (`var bp = eng.buffer_pool; bp.put(page); eng.buffer_pool = bp;`); or use the explicit receiver form with `&mut` on the field | silent data loss for every nested-field mutation, including struct-of-struct state machines and adapters |

### Secondary observations (no repro bundle needed)

- `warning[W004]: unreachable match arm` is emitted for a valid two-arm enum
  match where the second arm runs correctly at runtime
  (`docs/repro/option-vec-assign/probe2.xi` line 39, enum `E{A,B}`: `B`
  printed despite the warning). Cosmetic today; do not trust W004 for
  single-variant-looking enums until checked.
- `unknown type 'DbResult' -- defaulting to i64` belongs to C-ORBIT-01; if
  alias resolution is fixed generically, the warning should disappear with
  it.

## C-ORBIT-01 -- details

- **Where (read-only inspection):** `crates/xiom-check/src/lib.rs`
  `value_member_resolves` (~4485) requires `lookup_local` to know the
  receiver's type; for an unresolved match-bound payload it returns false,
  `check_module_call` is attempted on the value-rooted path, and the
  method path then classifies the receiver oddly (`is_static_call` ~7688),
  producing the wrong expected arity (`~7770`). Codegen additionally warns
  the alias is unknown and emits an unresolved symbol for a zero-arg method
  invoked on the raw binding.
- **Repro matrix (v0.64.0):**

  | Variant | Shape | Result |
  |---|---|---|
  | A | match-bound payload from `tuple_decode` (alias result) + `decoded.column_count()`/`get_column(0)` | **T001** |
  | B | same, plain rebind `let d = decoded;` | **T001** |
  | C | explicit `let r: DbResult[Row] = ...` annotation | **T001** |
  | D | direct `let row = Row.new(...)` + 1-arg method | ok |
  | E | direct + zero-arg method first | ok |
  | F | direct + explicit `let row: Row` annotation | ok |
  | G | explicit receiver `Row.get_column(&row, 0)` | ok |
  | H | match-bound + explicit receiver, but zero-arg method on the raw binding | **C001 codegen** |
  | I | match-bound + annotated rebind `let d: Row = decoded;` then all access via `d` | **ok (workaround)** |

- **App-context evidence (strongest):** `io.read_file_lines` returns
  `Result[Vec[Str], IOError]`; in `tests/probes/probe_wal_file.xi` the
  match-bound `Ok(lines)` printed `lines[i]` as raw stack addresses
  (`dbg line=[2380695695584]`) until the payload was rebound through
  `let all: Vec[Str] = lines;`. This is stdlib IO funneling through the
  same defect -- every consumer of `read_file_lines` is affected.
- **Suggested direction:** make the alias transparent to the checker and
  codegen (expand `pub type X[T] = ...` at use sites, or teach
  `lookup_local`/`value_member_resolves` about payloads bound from aliased
  cross-module returns); the compiler-lane commit `0c5337e0` (m216 alias
  resolution) may already cover the Vec-element case -- re-run
  `probe_import.xi` and `probe_only_i.xi` on the next archive.

## C-ORBIT-02 -- details

- **Repro:** `docs/repro/option-vec-assign/probe.xi`:

  | Variant | Shape | v0.64.0 |
  |---|---|---|
  | V1 | `Vec[Option[Int]]`: push(None); `v[0] = Some(44)`; match | **no arm runs** |
  | V2 | push(Some(44)); match | SOME |
  | V3 | local `Some(55)` assigned into a None slot | **no arm runs** |
  | V4 | struct field `s.o = Some(66)` | SOME |
  | V5 | `Vec[Int]`: push(0); `n[0] = 77` | OK |

  `probe2.xi`: V6 Some->Some silent; V7 `Vec[E]` A->B fine;
  V8 `Vec[Option[Str]]` None->Some silent; V9 None->None silent;
  V10 untouched sibling slot fine.
- **App-context evidence:** `src/storage/page.xi BufferPool.put` did
  `pool.pages[idx] = Some(page)`; `bp.misses` incremented but `bp.get(id)`
  returned None and the slot inspected as None/would-not-match
  (`tests/probes/probe_core_diag.xi`). Buffer-pool + storage-engine suite
  tests failed until the rebuild workaround.
- **Suggested direction:** the element-write lowering for enum payloads
  (drop-old + write-new path) appears to lose the discriminant for
  `Option` payloads; an `--emit-ir` diff of V1 vs V2 should show it.

## C-ORBIT-03 -- details

- **Repro:** `docs/repro/nested-field-mut/probe.xi`:

  | Variant | Shape | v0.64.0 |
  |---|---|---|
  | A | `o.inner.bump()` inside `Outer.bump` | 0 (lost) |
  | B | `Inner.bump(&mut o.inner)` explicit | 1 |
  | C | `c.inner.bump()` from `main` | 0 (lost) |
  | D | copy field -> mutate -> write back | 1 |

- **App-context evidence:** `StorageEngine.cache_page` called
  `eng.buffer_pool.put(page)`; the pool never saw the page
  (`storage_engine: cache/lookup` suite failure) until the copy-writeback.
- **Suggested direction:** auto-ref through field projections in method
  receivers (pass `&mut <projection>`, not a value copy), or at minimum
  emit a diagnostic when a `&mut` method is invoked on a projection.

## Bump procedure used by this lane

1. Update `scripts/dev-env.ps1/.sh` pins (compiler path/version only; stdlib
   path is fixed to the lane checkout).
2. Re-run: `scripts/run.ps1 tests/test_conformance.xi` (x2),
   `scripts/crash_test.ps1 -Events 20` (x2) and the 200-record soak,
   `.sh` twins from WSL, then the repro bundles.
3. A finding flips to RESOLVED only when its probe bundle is green
   unchanged; record the result in this file and SESSION.md.
