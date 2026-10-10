<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# XIOM ORBITDB -> compiler lane: findings (all RESOLVED on v0.64.2)

**Status 2026-10-09: C-ORBIT-01..05 are all RESOLVED on v0.64.2** -- see the
re-test section below; the workarounds are dropped in commit `6f6c3ba`
(`refactor: drop v0.64.2-fixed workarounds`). One scoping caveat remains for
C-ORBIT-04 in consumer modules (recorded under the re-test).

**Status 2026-10-10: C-ORBIT-06 filed (OPEN on v0.64.2)** -- phantom imports
and undeclared signature types are silently accepted; a same-named foreign
type in the program turns the same file into a hard T001, and bogus W004
"unreachable match arm" warnings misdirect the triage. Found by composing the
ORBITDB + XVECTOR source trees for the hybrid probe (bundle
`docs/repro/phantom-core-import/`). ORBITDB-side fix already applied (the
dead `db_error_from_core`/`database_config_from_core` folds retired); suite
123/123 x2 both platforms.

> **Bus (2026-10-10):** open items now live on `xiom-relays`. C-ORBIT-06 is
> `REL-20261010-1549-packages-4` (cross-filed by packages, cites our repro
> bundle); the standalone-check quirk is `REL-20261010-1550-orbitdb-2`. Below
> is closed history; open new bus items instead of editing this file.

**Status 2026-10-10 (v0.64.3 bump):** re-test green -- seven repro bundles
unchanged and matching the v0.64.2 matrix, suite 130/130 x2 Win + WSL,
WAL/db/block crash + fuzz + 2000-key soak green both platforms. C-ORBIT-06
with-twin still red on v0.64.3 (correction `REL-20261010-1802-orbitdb`);
row `-2` (standalone-check quirk) still open. No new findings.

**Relay:** hand this file to the compiler-lane session together with the
matching `docs/repro/<bundle>/` directories from the ORBITDB repo
(`E:\xiom-projects\xiom-orbitdb`). ORBITDB is a consumer lane; it does not
edit the compiler tree. Read-only compiler-source references below were
located while triaging and are evidence, not patches.

**Pins (updated 2026-10-09):**

| Component | Version / hash |
|---|---|
| compiler | **v0.64.2** (2026-10-09; installed in place, Windows `%LOCALAPPDATA%\xiom.new` + WSL) |
| compiler history | v0.64.0 (2026-10-08) -> v0.64.1 (same-day re-test) -> v0.64.2 (this re-test) |
| stdlib | `E:\xiom-lang\stdlib` @ `e7896ff` (2026-10-09; lane wave 97 + wishlist sweep + relay consumption) |
| compiler lane | `d9f146cb` (`v0.64.2-2-gd9f146cb`; the v0.64.2 tag is cut) |
| env | `XIOM_STDLIB=E:\xiom-lang\stdlib`; `XIOM_RUNTIME_DIR` retired (env-free, installed R65 layout) |

## Re-test v0.64.1 (2026-10-08) -- all four findings still open; lane green

| Finding | Bundle | v0.64.1 result |
|---|---|---|
| C-ORBIT-01 | `docs/repro/ok-method-receiver/probe_import.xi` | **OPEN** -- identical 4 T001 sites (lines 34/36/53/69): `'get_column' expects 2 argument(s), found 1` / `expected Row, found Int`; A/B/C still fail, D/E/F/G green |
| C-ORBIT-02 | `docs/repro/option-vec-assign/probe.xi` + `probe2.xi` | **OPEN** -- V1/V3/V6/V8/V9 still print nothing (no arm runs); V2/V4/V5/V7/V10 fine |
| C-ORBIT-03 | `docs/repro/nested-field-mut/probe.xi` | **OPEN** -- A=0 (lost), C=0 (lost); B=1, D=1 |
| C-ORBIT-04 | suite with the qualification workaround temporarily reverted | **OPEN** -- same clang failure: `'%tmp10' defined with type '%struct.WALOp' but expected '%struct.WALOpKind'` (IR line 71079) |

Positive on v0.64.1: the whole lane regressed clean -- conformance **104/104**,
WAL/page/DB crash tests GREEN, CRC32C/FSM/tuple/page-file probes unchanged.
The false `W004 unreachable match arm` seen on v0.64.0
(`docs/repro/option-vec-assign/probe2.xi`) was **not emitted** on v0.64.1 --
treat as fixed, keep watching.

**Consumer impact in one line:** the conformance suite of a database engine
did not compile on v0.64.0 (218 type errors, then a codegen C001); after
working around the findings below it is **104/104 green on v0.64.1**
(Windows + WSL), and the crash/reopen WAL/page/DB probes are green on both.
These defects are on the critical path of any storage/collection code that
uses `Vec[Option[T]]` caches, cross-module `Result` aliases, nested-field
`&mut` methods, or same-named enum variants across modules.

## Re-test v0.64.2 (2026-10-09) -- all five findings RESOLVED

Compiler relay (archived): `docs/relay-archive/COMPILER-RELAY-2026-10-09-v0.64.2.md` (m223 alias
payloads, m224 nested-field receivers, m225 enum-variant module scope, m226
`Vec[Option/Result]` element assignment, m235 loop-body alloca, plus
m228/m231/m234/m239).

**Acceptance (relay ask): the C-ORBIT-04 qualification workaround REVERTED.**
`src/wal_file.xi` again constructs and matches unqualified variants
(`return Update;`, `match op { Insert => ... }`) and the suite compiles and
runs green -- m225 resolves variants to the declaring module.

**Workaround reverts verified by the full matrix (commit `6f6c3ba`):**

| Finding | Revert | Result |
|---|---|---|
| C-ORBIT-01 | typed rebinds removed in `src/wal_file.xi` replay + every `src/storage/page_file.xi` reader (`lines` used directly, matched `p` used directly) | green |
| C-ORBIT-02 | no app-side workaround remains (BufferPool uses parallel vectors by design); bundle unchanged | green |
| C-ORBIT-03 | `StorageEngine.cache_page/lookup_page` call `eng.buffer_pool.put/get(...)` directly (no copy-out/write-back) | green |
| C-ORBIT-04 | variants unqualified in `src/wal_file.xi`; engine keeps qualification (see caveat) | green |
| C-ORBIT-05 | `page_log_read_all` restored to the nested `Vec[Page]` dedup with `out.push(all[k])` | green |

**Repro bundles unchanged (Windows + WSL):**

| Bundle | v0.64.1 | v0.64.2 |
|---|---|---|
| nested-field-mut | A=0, C=0 (writes lost) | A=1 B=1 C=1 D=1 |
| option-vec-assign | V1/V3/V6/V8/V9 silent | V1..V5 SOME/OK; no silent slots |
| option-param / option-ref-write / ok-method-receiver | mix of reds per earlier matrix | all labelled OK (D2=NONE, bits=0 controls) |
| vec-option-match | Some arms dropped | A=5 B=5 C=9 D=7 (correct) |
| vec-push-nested | variant D aborts `0xC0000005` | A/B/C/D all ok |

**Lane regression on v0.64.2 with the workarounds reverted:** conformance
120/120 x2 Win + WSL, db_crash 25/25 x2, WAL crash 4/4 x2, page crash 4/4 x2,
fuzz `seeds=4 ops/seed=4000` OK, 2000-key policy soak OK (9 checkpoints).
Bench: `wal_replay` of 20k records 61.6 s -> 9.9 s (stdlib linear
`read_file_lines`; see the stdlib wishlist).

**Bonus verification:** deep container equality (m239) is live --
`Vec[Int] == Vec[Int]` and `Str == Str` compare by content on v0.64.2 (the
v0.64.2 release-notes "Known issues" line claiming pointer identity is
stale).

### v0.64.3 re-test (2026-10-10, bump procedure step 2)

Compiler v0.64.3 (Windows shadow `%LOCALAPPDATA%\xiom.new.0643`; WSL
canonical v0.64.3). All seven C-ORBIT bundles re-run **unchanged and
matching the v0.64.2 green matrix** (nested-field-mut A=1 B=1 C=1 D=1;
option-vec-assign no silent slots; option-param / option-ref-write /
ok-method-receiver all OK; vec-option-match A=5 B=5 C=9 D=7; vec-push-nested
A/B/C/D ok). Lane regression: **suite 130/130 x2 Win + WSL** (includes the
S2/S3 v2 tests), WAL crash 4/4 x2 Win + WSL, db_crash 25/25 Win, block crash
8/8 Win, fuzz OK Win + WSL, 2000-key soak OK Win + WSL (9 checkpoints).

C-ORBIT-06 on v0.64.3: `probe_alone.xi` unchanged (silent pass + 2x W004);
`probe_with_twin.xi` **still fails T001 30:5** -- the release-check row
`REL-20261010-1549-packages-4` verdict ("twin gone; probe passes") is not
reproducible from the committed bundle; correction filed as
`REL-20261010-1802-orbitdb`. **RESOLVED as invocation-dependent (compiler,
18:45Z):** the packages pass reproduces only in the bare-filename form
(`cd docs/repro/phantom-core-import; xiom --check probe_with_twin.xi`) -- a
bare filename's empty parent was indexed as the source dir, so the file's
own directory never reached the catalog (sibling module unresolved). Fixed
on compiler main by **m255** (`13115d64`, unpushed as of 2026-10-10);
**re-verify the bundle on the next archive**. The twin half stays open on
v0.64.3 via the documented path invocation; the phantom-acceptance core ask
is queued for v0.64.4. Release-check row `REL-20261010-1550-orbitdb-2`
(standalone `--check` quirk): **still open** on v0.64.3 (same T001 class at
1206/1211/1216). No C-ORBIT regressions; no new findings.

### Residual caveat -- C-ORBIT-04 scope (consumer modules)

Unqualified resolution now binds to the module that DECLARES the enum. In a
consumer module that imports one enum while the program also contains a
structurally identical enum from another import (our suite imports both
`wal_file.WALOpKind` and `txn.WALOp`), an unqualified variant still resolves
to the wrong twin: `wal_file_append(&mut w, Insert, ...)` in the suite
lowered against txn's `WALOp` -> `T001 expected WALOpKind, found WALOp`
(no ambiguity diagnostic). ORBITDB therefore keeps qualification in consumer
modules (`src/engine.xi`, the suite) and files this follow-up request:
scope unqualified resolution to the importing module's import set and/or
emit an ambiguity error.

## Open findings (all RESOLVED on v0.64.2 -- kept as history)

The rows below describe the v0.64.1 state and the workarounds that were
applied then; every one is resolved on v0.64.2 (see the re-test above).

| Date | Finding | Evidence | Workaround in ORBITDB | Impact |
|---|---|---|---|---|
| 2026-10-08 | **C-ORBIT-01: a cross-module generic type alias in return position (`pub type DbResult[T] = Result[T, DbError]`) is not resolved at the consumer.** A match-bound `Ok(payload)` loses its type: method calls drop the receiver (`'get_column' expects 2 argument(s), found 1` / `expected Row, found Int`), zero-arg methods on the raw binding reach codegen as an unresolved symbol (`C001 'column_count'`), and codegen warns `unknown type 'DbResult' -- defaulting to i64` (10x per suite run). | `docs/repro/ok-method-receiver/probe_import.xi` (A/B/C broken, D/E/F/G green); `probe_rebind.xi` (H broken at codegen, I green); `probe_only_i.xi` green. App: conformance suite 4 T001 -> C001 -> green after rebind; `probe_wal_file.xi` read_file_lines payload printed raw addresses until rebind. | rebind the payload through an explicitly typed local before any access: `let d: Row = decoded;` (probe_only_i), or call the explicit receiver form `Row.get_column(&decoded, 0)` | silent wrong values / no-arg methods emit garbage symbols; breaks every consumer of aliased cross-module `Result` returns (stdlib `io.read_file_lines`, packages) |
| 2026-10-08 | **C-ORBIT-02: assigning an Option into a `Vec[Option[T]]` element poisons the slot.** After `v.push(None); v[0] = Some(x);` (or any Option-to-slot write: Some->Some, Option[Str], None->None) the element matches NEITHER `None` NOR `Some(_)`; every `match` over it silently runs no arm and execution falls through. No diagnostic. `Vec[Int]` writes, enum-vector writes and struct-field Option writes are all fine. | `docs/repro/option-vec-assign/probe.xi` (V1/V3 silent, V2/V4/V5 green); `probe2.xi` (V6 Some->Some silent, V8 Option[Str] silent, V9 None->None silent, V7 enum fine, V10 untouched slot fine). App: BufferPool.put corruption -> `buffer_pool` + `storage_engine` suite failures; `tests/probes/probe_write_drop2.xi`. | never index-assign an Option into a Vec element; rebuild the Vec and assign the Vec (`src/storage/page.xi BufferPool.put`); struct fields are safe | silent wrong behavior + broken exhaustiveness in caches/pools/option-vectors; would corrupt any `Vec[Option[T]]` structure |
| 2026-10-08 | **C-ORBIT-03: a method call whose receiver is a nested field mutates a temporary copy.** `o.inner.bump()` inside a method, and `eng.buffer_pool.put(page)` anywhere, execute on a copy; the `&mut` write-back is lost. Explicit `Inner.bump(&mut o.inner)` and copy-mutate-writeback work. No diagnostic. | `docs/repro/nested-field-mut/probe.xi`: A=0 (lost), C=0 (lost), B=1, D=1 (green). App: `StorageEngine.cache_page` -> `storage_engine: cache/lookup` suite failure; `src/storage/page.xi`. | copy the field to a local, mutate, write it back (`var bp = eng.buffer_pool; bp.put(page); eng.buffer_pool = bp;`); or use the explicit receiver form with `&mut` on the field | silent data loss for every nested-field mutation, including struct-of-struct state machines and adapters |
| 2026-10-08 | **C-ORBIT-04: unqualified enum-variant construction resolves against ANOTHER module's structurally identical enum.** With `xiom.db.txn.transaction`'s `pub enum WALOp { Insert, Update, Delete }` and `xiom.db.wal_file`'s `pub enum WALOpKind { Insert, Update, Delete, ... }` in one compilation unit, `return Update;` inside `wal_op_from_code` lowered as txn's `%struct.WALOp` while the function is declared `-> WALOpKind`; clang rejects the module. Variant patterns may silently compare equal tags instead of failing. | Hard failure with IR evidence (below); suite build broke only when engine imported wal_file AND the suite imported the txn module. | module-qualify variants everywhere (`return WALOpKind.Update;`, `match op { WALOpKind.Insert => ... }`) -- verified compiling and green | hard build failure today; potential silent wrong-enum construction/matching for any two enums sharing variant names (very common: Insert/Update/Delete) |
| 2026-10-08 | **C-ORBIT-05: a nested loop over a `Vec` of structs with Vec fields (`Vec[Page]`) aborts with an access violation when the outer loop also pushes elements into another `Vec[Page]`.** No diagnostic; the process dies with `0xC0000005` (stdout buffered, prints lost). Each ingredient alone is green: the same nested loop over `Vec[Int]`, a single push loop over `Vec[Page]`, and the nested loop over `Vec[Page]` with no push. Observed at n=418; minimum not bisected. | `docs/repro/vec-push-nested/probe.xi` (A/B/C green, D aborts before its print; the marker file names the last variant); app context: `page_log_read_all` dedup aborted on a 418-entry snapshot log, so the policy soak crashed at reopen at N>=400 | rewrite the dedup as an Int-only keep-set pass (nested loop over `Vec[Int]`) + a single non-nested push pass (`src/storage/page_file.xi`); keep struct copies out of nested loops that push | process abort (access violation) in collection code that dedups/filters struct-with-Vec vectors -- looks like memory corruption, no diagnostic |

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

## C-ORBIT-04 -- details

- **Symptom (exact):**
  ```
  error: clang failed with exit code 1
  xiominput.ll:71079:25: error: '%tmp10' defined with type
      '%struct.WALOp = type { i64 }' but expected '%struct.WALOpKind = type { i64 }'
  71079 |   ret %struct.WALOpKind %tmp10
  ```
  (line 71073 on v0.64.0, 71079 on v0.64.1; still reproducible on v0.64.1)
  The body just above constructs `%struct.WALOp` (`alloca %struct.WALOp` ...
  `store i64 1, ...` `load %struct.WALOp`) inside
  `define %struct.WALOpKind @db.wal_file.wal_op_from_code(i64)`.
- **Trigger:** a compilation unit containing both modules (engine now
  `use xiom.db.wal_file;` and the conformance suite imports
  `xiom.db.txn.transaction`). `probe_wal_file.xi` alone compiled and ran
  green for hours -- the collision only appears when both enums are in the
  graph and variant resolution picks the first-registered enum with that
  variant name.
- **Minimal repro sketch (two modules):**
  ```
  // a.xi
  module example.a
  pub enum AKind { Insert, Update }
  pub fn a_make() -> AKind { return Update; }     // lowered as ...?
  // b.xi
  module example.b
  pub enum BKind { Insert, Update, Delete }
  pub fn b_make() -> BKind { return Update; }
  ```
  Compile both plus a caller; expect one function to construct the other
  module's enum (`--emit-ir`, look for the `%struct.` name in `ret`).
- **Impact:** clang catches the return mismatch here, but a variant
  *pattern* against the wrong structural twin would compare equal i64 tags
  and silently take the wrong branch. Treat as high-priority.
- **Workaround (verified clean, 104/104 suite):** module-qualify every
  variant in constructors and patterns in the affected module
  (`src/wal_file.xi`), e.g. `return WALOpKind.Update;` and
  `match op { WALOpKind.Insert => ... }` -- both forms compile and behave.
- **Suggested fix:** unqualified variant resolution must be scoped to the
  current module's declarations first (and error on genuine ambiguity),
  the same way type names are; or intern enum variants by
  (module, name, tag) instead of name only.

## C-ORBIT-05 -- details

- **Symptom (exact):** exit code `0xC0000005` (access violation) with no
  diagnostic and no output (stdout buffering swallows prints).
- **Repro:** `docs/repro/vec-push-nested/probe.xi`, n=418:

  | Variant | Shape | v0.64.1 |
  |---|---|---|
  | A | nested loop over `Vec[Int]`, push ints | ok |
  | B | single loop over `Vec[Page]`, push pages | ok |
  | C | nested loop over `Vec[Page]`, counter only (no push) | ok |
  | D | nested loop over `Vec[Page]` + push `all[k]` into another `Vec[Page]` | **ABORT** |

- **App-context evidence:** `page_log_read_all` (page-log dedup) aborted on a
  418-entry (58 KB) snapshot log; a standalone diagnostic probe crashed on the
  first `page_log_read_all` call after reading the file, while the identical
  algorithm over `Vec[Int]` was green. Policy soaks with N >= 400 aborted on
  reopen until the dedup was rewritten.
- **Workaround (verified):** compute the keep-set over a parallel `Vec[Int]`
  of ids (nested loop over ints), then select pages in a single non-nested
  pass; see `src/storage/page_file.xi` `page_log_read_all`.
- **Suggested direction:** `--emit-ir` diff of D vs C around the element copy
  (struct containing Vec fields) inside the nested loop; the copy appears to
  clobber a loop/allocator register at larger iteration counts.

## C-ORBIT-06 -- phantom import silently accepted; foreign twin turns it hard (OPEN, filed 2026-10-10)

- **Bundle:** `docs/repro/phantom-core-import/` (`probe_alone.xi`,
  `probe_with_twin.xi`, `twin.xi`, README with exact outputs).
- **Symptom A (silent):** a `use` of a module that exists nowhere
  (`xiom.core.error`) plus an undeclared type in a signature (`&CoreError`)
  type-checks green -- with two misleading `W004 unreachable match arm`
  warnings (29:5, 30:5) pointing at match arms instead of the import.
- **Symptom B (hard):** with any reachable module declaring a same-named
  type (`twin.CoreError`; the composite used `xiom.vector.core.shim`'s inline
  `CoreError`), the very same file fails:
  `error[T001]: 30:5: match pattern 'Corruption' belongs to 'DbError', not
  'CoreError'` -- the scrutinee name binds across modules while the bare
  pattern resolves to the same-module enum; no ambiguity diagnostic.
- **Impact:** a consumer lane can ship code that cannot type-check in any
  multi-package composition, while every standalone build is green. The
  ORBITDB `xiom.db.error` fold was silently dead for months this way.
- **Workaround (applied):** never keep a `use`/type that does not resolve;
  removed the dead folds + phantom imports (`2026-10-10`); the composite
  hybrid probe builds and passes.
- **Suggested fix:** error on unresolvable `use` (or undeclared types in
  signatures/field access); prefer the scrutinee's enum for bare pattern
  variants over the same-module enum when both exist, with an ambiguity
  diagnostic.

## Bump procedure used by this lane

1. Update `scripts/dev-env.ps1/.sh` pins (compiler path/version only; stdlib
   path is fixed to the lane checkout).
2. Re-run: `scripts/run.ps1 tests/test_conformance.xi` (x2),
   `scripts/crash_test.ps1 -Events 20` (x2) and the 200-record soak,
   `.sh` twins from WSL, then the repro bundles.
3. A finding flips to RESOLVED only when its probe bundle is green
   unchanged; record the result in this file and SESSION.md.
4. Then run the relay-acceptance pass: revert the app-side workaround on a
   branch, re-run suite x2 + crash x2 + fuzz + soak on both platforms, and
   merge only if green (v0.64.2 did this in commit `6f6c3ba`). A finding
   whose revert regresses keeps its workaround and stays open.
