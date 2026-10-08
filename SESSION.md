# XIOM ORBITDB -- Session Handoff

<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

**Written:** 2026-10-08, by the ORBITDB lane (bootstrap completed; B-tree
delete hardened after the packages-lane relay).
**Project:** embedded database engine for XIOM -- layered architecture:
B-Tree index, WAL, query engine, crash recovery; formerly `xiom-db`
(renamed `xiom-orbitdb`).

## 0. STATE (2026-10-08 -- bootstrap + B-tree churn hardening; WAL crash-probe green)

- **Repo:** `E:\xiom-projects\xiom-orbitdb`. Stays **PRIVATE**; no push /
  remote without owner approval. Commits this session: `f2dec60` (engine
  fixes + suite migration, 93/93), `bc5ef2a` (scripts, WAL crash probe,
  repro bundles), `8ea9bef`/`1988f8b` (line endings, comment), `54472d5` +
  `0e02f4a` (relay docs + per-lane messages), `c7d4901` (B-tree delete
  hardening, churn-proven; suite 95/95). Identity used: `Lefteris Notas
  <lefterisnotas@gmail.com>` (repo history); conventional commits with DCO
  sign-off (`git commit -s`).
- **VERSION POLICY (owner decision): track the LATEST compiler / stdlib /
  packages** -- this lane hardens the ecosystem by real-world use. Record
  exact versions and lane hashes here at every wrap.
  - compiler: **v0.64.1** on Windows (`%LOCALAPPDATA%\xiom.new\bin\xiom.exe`)
    and in WSL (`~/.local/bin/xiom`); `XIOM_RUNTIME_DIR` retired. Re-tested
    2026-10-08: C-ORBIT-01..04 **all still open** (bundles + suite with the
    qualification workaround reverted), lane regression clean (104/104,
    WAL/page/DB crash tests GREEN); the false W004 warning from v0.64.0 was
    not emitted.
  - stdlib: `E:\xiom-lang\stdlib` @ **`a677338`** (2026-10-08T12:27:20+03:00,
    "docs: refresh handoff snapshot 20") = `/mnt/e/xiom-lang/stdlib` in WSL.
  - compiler lane @ `0c5337e0` (2026-10-08, "fix(codegen): m216 alias Vec
    elements resolve + lazy builtin probe (C-PULSE-11)") -- likely touches
    C-ORBIT-01; re-test on the next archive.
  - packages lane @ `bb286506` (batch #38, eco-v0.1.87) + relay exchange:
    `xiom.wal` ships **standalone** (3 users, one format), shaped from this
    lane's crash-probe evidence; `xiom.btree` name held, extraction gate =
    our churn soak (**now MET**); `xiom.durable` (in-repo, unpublished) has
    `src/wal/*` + `src/txn/*` to reconcile into `xiom.wal`; C-PULSE-10
    `xiom.kv` gate is Linux-only. ORBITDB has no registry deps yet
    (zero-dep Phase 0) and no `xiom.toml`.
  - `xiom doctor` has 2 environment warnings (bundled stdlib v0.63.1 vs
    compiler v0.64.0; a stale second xiom binary on PATH) -- lane noise only:
    `scripts/dev-env.*` always sets `XIOM_COMPILER`/`XIOM_STDLIB` explicitly.
- **Green evidence this session:**
  - `scripts/run.ps1` + `scripts/run.sh` (watchdog + exit-code gate);
    dev-env twins; hello probe x2 Windows + WSL.
  - **Conformance suite: 104/104 passed, exit 0** (93 + 2 churn + CRC32C KAT
    + 3 tuple-codec + 2 FSM + 2 page-file + 1 db-file tests) -- x2 Windows + WSL.
  - **Engine on the disk WAL (B4):** `DBFile` facade in `src/engine.xi` --
    `db_file_put/delete` append to the durable segment FIRST (Insert for new
    keys, Update for upserts, Delete) and only then apply to the in-memory
    tree; `db_file_open` recovers by replaying the segment (torn tail
    skipped); `db_file_flush` is the fsync seam. Acceptance:
    `tests/probes/probe_db_file.xi` + `scripts/db_crash_test.{ps1,sh}`
    (writer 20 keys -> hard kill -> torn tail -> recover 20 -> put 9999 ->
    recover 21): GREEN x2 Windows + WSL, plus a 200-key soak. Suite locks
    put/update/delete-reopen replay.
  - **Compiler finding C-ORBIT-04 filed:** unqualified enum-variant
    construction in `wal_file` resolved against `xiom.db.txn`'s
    structurally identical `WALOp` enum once both modules entered one
    compilation unit (clang IR type mismatch). Workaround (module-qualified
    variants in constructors and patterns) applied and verified; details +
    IR evidence in `docs/COMPILER-FINDINGS-ORBITDB.md`.
  - **Readiness score: 54.5/100** (`docs/PRODUCTION-READINESS.md`; B4 done,
    changelog updated).
  - **Free-space map hardened:** `storage/free_space_map.xi` now does
    best-fit placement (tightest page, lowest id on ties), `record_used`
    over-use/negative clamping with false returns, `record_free` with
    capacity clamp, `fsm_validate` invariants; model-soaked by
    `tests/probes/probe_fsm.xi` (use/release/find vs a flat model, validate
    every 500 ops): 20k ops x2 + 50k-op soak (256 pages, ~2s), GREEN
    Windows + WSL; suite locks best-fit/clamps.
  - **Production-readiness tracking added:** `docs/PRODUCTION-READINESS.md`
    -- weighted scoreboard (current 43.5/100, pre-alpha), per-area item
    points, phase gates to v1.0, and the explicit 100% checklist.
  - **Byte-packed tuple codec v1 landed:** `storage/tuple.xi` records are
    `magic 0xDB | version 1 | field_count | (type 0x01 + i64 LE)*` with exact
    length/type validation on decode, `tuple_fits_page` budget, and
    `tuple_encode_checked` for the >255-field refusal; locked by
    `tests/probes/probe_tuple_codec.xi` (KAT byte-exact, extremes incl. i64
    bounds, rejection matrix; x2 Windows + WSL) and suite tests. The C-ORBIT-01
    repro bundle still runs unchanged.
  - **CRC32C page checksum landed:** `page_compute_checksum` is now bitwise
    Castagnoli (`0xE3069283` KAT; empty -> 0), locked by
    `tests/probes/probe_crc32c.xi` (x2 Windows + WSL) and a suite test;
    `Page.is_valid` uses it. Swap to `xiom.hash.crc.crc32c` when the byte
    pack + Vec[UInt8] conversion land.
  - **WAL crash/reopen: GREEN x2 on Windows + x1 in WSL** (re-verified after
    the B-tree change, and again on the `src/wal_file.xi` module): writer 20
    records -> hard kill -> torn tail -> replay 20 -> heal append -> 21;
    **200-record soak** GREEN (3,081 B segment, module path). Truncate seam
    smoke: keep lsn >= 15 -> replay 7 (torn line removed).
  - **`xiom.wal` reference landed:** `src/wal_file.xi` -- durable-shaped
    `WALRecord`/`WALOpKind`/lsn, open/append/flush/replay/truncate/heal,
    text codec v1 (`lsn|op|key|value|timestamp[|payload_csv]`); acceptance =
    `tests/probes/probe_wal_file.xi` + crash harness.
  - **B-tree churn soak: GREEN** -- `tests/probes/probe_btree_churn.xi`
    (randomized insert/delete/search vs a reference model + structural
    validator): orders 4/5/6 x 20,000 ops at keyspace 4096 (~3-4s each),
    seed matrix 4/5/6 x {2026, 777}, plus the in-suite 400-op order-4/5
    regressions.
  - Diagnostics: `tests/probes/probe_core_diag.xi` (B-tree 100/100 after
    fix), `probe_write_drop{,2}.xi` (write-path isolation).
- **Product defects found & fixed (Phase 0 hardening):**
  - B-tree `split_child` overwrote `children[child_pos+1]` past the end
    (silent no-op) instead of shifting the parent child list -> first
    internal split corrupted the tree (insert failed from key 8; size 6/100).
    Fixed in `src/engine.xi`; `probe_core_diag` now 100/100.
  - `BufferPool.put` / `StorageEngine.cache_page` worked around two v0.64.0
    compiler defects (see C-ORBIT-02/03) in `src/storage/page.xi`.
  - **B-tree delete hardened (churn-proven, 2026-10-08):** three defects
    fixed -- (a) `fill_child` returned a child *position* where
    `delete_from_node` expected a *node index* (after a merge it descended an
    unrelated node; churn repro op=148: delete of an existing key returned
    false), (b) `min_keys = (order-2)/2` is the true floor for this split
    scheme (the old `(order+1)/2-1` left odd-order nodes under-filled),
    (c) `borrow_from_left` pushed a placeholder child onto leaves. The churn
    soak is the regression gate; extraction of `xiom.btree` is now unblocked
    from our side (packages lane gate = this soak, MET).
  - **Remaining index debt (honest):** node storage is append-only (no free
    list / node reuse); `btree_to_vec` is O(n) value-only (no key iteration
    API yet); planner-key semantics still open (Phase 3 decision).
  - `tests/test_conformance.xi` migrated to the current stdlib test API
    (`assert -> TestResult`, free-function query/db calls) + C-ORBIT-01
    rebind workaround; query tests now assert the documented **value**
    semantics (pinned in `docs/query-pipeline.md`).
- **Relay documents created (owner relays; keep updated every wrap):**
  - `docs/COMPILER-FINDINGS-ORBITDB.md` -- **C-ORBIT-01** (cross-module
    generic `Result` alias payload unresolved: receiver dropped, C001
    unresolved symbol, "DbResult defaulting to i64"), **C-ORBIT-02**
    (`Vec[Option[T]]` element assignment poisons the slot -- matches no
    arm), **C-ORBIT-03** (nested-field `&mut` method receivers mutate a
    copy), plus a W004 note. Repro bundles under `docs/repro/`.
  - `docs/STDLIB-WISHLIST-ORBITDB.md` -- fsync/durability, truncate/
    checkpoint, `read_file_lines` CR normalization, byte-level IO,
    append-with-tail-repair; positive confirmations (`io.sleep` is
    load-bearing, `crc32c` exists for Phase 1).
  - `docs/PACKAGE-WISHLIST-ORBITDB.md` -- extraction candidates
    `xiom.btree`/`xiom.wal`, `xiom.db` publish note, `xiom.kv` watch, plus
    the packages-lane delta (standalone `xiom.wal`, btree gate met).
  - `docs/RELAY-INTRO-ORBITDB.md` + per-lane paste-ready messages
    `docs/RELAY-{COMPILER,STDLIB,PACKAGES}-ORBITDB.md` + the packages-lane
    response `docs/RELAY-PACKAGES-RESPONSE-ORBITDB.md` (WAL API proposal:
    durable's LSN/record shape + our disk segment/heal/replay/crash harness).
- **Owner asks done this session:** wishlist docs (above), `images/` folder
  created for the project icon (drop e.g. `images/orbitdb-icon.png`);
  `.gitignore` extended (VS Code workspace/`.vscode`, `.kilo/`, probe logs,
  build artifacts, CRLF rules in `.gitattributes`); scripts in both `.ps1`
  and `.sh`.
- **Next action:** (1) `xiom.wal` reconciliation -- reference disk layer is
  landed (`src/wal_file.xi`); when packages moves `xiom.durable`'s
  `src/wal/*` under `xiom.wal`, port this codec/heal/replay + the crash
  probe as the package acceptance test, keep durable's record shape, and
  add per-record checksums when stdlib byte IO lands. (2) Phase 1 durable
  pages: **CRC32C, tuple codec v1, free-space map and the durable page file
  are done in-repo; the engine now runs WAL-before-ack on the disk segment
  (`DBFile`)**; remaining -- node-per-page B-tree (page-file seam + FSM now
  exist), checkpoint policy wired to `wal_file_truncate`, real pager
  integration (externally blocked: `xiom.core.storage.pager` substrate /
  registry source-roots, C-PULSE-02).   (3) Re-run
  conformance + crash probes on the next compiler archive (watch
  C-ORBIT-01..04; re-tested on v0.64.1 -- all four still open, m216 did not
  cover C-ORBIT-01). Add `xiom.toml`
  + CI only when the repo goes public (owner gate; ops has the mechanics per
  the PULSE ops relay). No VPS/DNS action requested.
  (4) Keep `docs/PRODUCTION-READINESS.md` recomputed at every wrap (score +
  changelog line + evidence links).

## 1. Consumer-lane rules (non-negotiable)

- **Never edit** `E:\xiom-lang\stdlib`, `E:\xiom-lang\xiom`,
  `E:\xiom-packages\packages`. Record their HEAD hashes each wrap:
  `git -C <lane> log -1 --format="%h %cI %s"`.
- Report upstream only through the relay docs + SESSION rows; the owner
  relays to the stdlib/packages/compiler lanes. Read the PULSE lane's relay
  docs before filing anything new (do not rediscover), and reference its
  IDs where a finding matches (e.g. C-PULSE-11 ~ C-ORBIT-01 family).
- Consume packages from the registry only; never vendor a package copy.
  Reusable primitives this lane grows should be **proposed as packages** in
  the package wishlist.

## 2. Pin discipline that bites (v0.64.0)

- Initialize every local at declaration (`var x: T = <default>;`); every
  **struct literal must list every field** (C-PULSE-06).
- Never init module-scope variables with cross-package constructor calls
  (C-PULSE-07). Keep package aggregates caller-owned.
- Never call `.to_str()` on a module-`const` receiver (C-PULSE-05; aborts on
  v0.64.0) -- use `convert.int_to_string`.
- Explicit `*p` for every `&mut Int` read (C-PULSE-04).
- **New this session (C-ORBIT workarounds; keep until the compiler fixes):**
  - Rebind a match-bound payload of a cross-module generic `Result` through
    an explicitly typed local before any access:
    `let d: Row = decoded;` (C-ORBIT-01). Applies to `io.read_file_lines`,
    `tuple_decode`, and any aliased package return.
  - Never index-assign an `Option` into a `Vec[Option[T]]` element; rebuild
    the Vec and assign the Vec (C-ORBIT-02).
  - Never call a `&mut` method on a nested field receiver; copy out, mutate,
    write back (C-ORBIT-03).
- Types are `Vec[T]` / `Result[T, Err]`; after every write run the byte-level
  grep for `Vec<|Result<|Option<`.
- Parenthesize every bitwise & additive mix; `fn`, `as`, `use` reserved; no
  overloading; cross-module helpers need `pub`; submodule functions need
  submodule imports (`xiom.string.split.str_split`, `xiom.convert.parse.parse_int`).
- Durability reality check: the runtime has **no fsync/FlushFileBuffers
  wrapper** -- "durable" appends are OS write-back today; claim torn-tail
  healing only, never power-loss durability. `io.append_line` does not add a
  boundary newline before a torn tail -- `heal_tail` (probe_wal_file) does.
- Keep a `-TimeoutSec` watchdog on every run/suite and gate on exit code;
  run every green suite x2; soak anything long-running. Start long-running
  processes with output redirected to **files** (never an undrained pipe),
  and hang loops need a side-effecting call (`io.sleep`) -- an empty spin
  loop is optimized away.

## 3. Known ecosystem status (2026-10-08)

- Compiler: v0.64.0; C-PULSE-01/read-hijack, runtime-link, crypto-link
  resolved; C-PULSE-02 (registry source-roots) still open; C-PULSE-04/05/06/
  07 still open (PULSE ledger). ORBITDB adds C-ORBIT-01/02/03.
- Stdlib: latest lane checkout `a677338`; io/sleep/string/env all usable;
  fsync/byte-IO/truncate gaps filed in ORBITDB's wishlist.
- Registry: `xiom.http` 0.1.1, `xiom.jwt` 0.2.0, `xiom.rate` 0.2.0,
  `xiom.metrics` 0.2.0, `xiom.router` 0.1.0, `xiom.http.middleware` 0.1.0,
  `xiom.session` 0.1.0, `xiom.static` 0.1.0, `xiom.kv` 0.1.0 (PULSE ledger;
  `xiom.kv` has the known-red C-PULSE-10 gate).

## 4. Paste prompt for the next ORBITDB session

```
You are the ORBITDB session for E:\xiom-projects\xiom-orbitdb -- the
embedded XIOM database engine (B-Tree, WAL, query engine, crash recovery).
Read SESSION.md first, then README/SPEC/ARCHITECTURE/ROADMAP/AUDIT and
docs/ (relay docs included). Consumer lane: never edit E:\xiom-lang\stdlib,
E:\xiom-lang\xiom, E:\xiom-packages\packages. Repo stays PRIVATE; no pushes
without owner approval. Identity "Lefteris Notas <lefterisnotas@gmail.com>";
conventional commits, DCO -s.

Toolchain: latest-tracking -- compiler v0.64.0 (Windows + WSL), stdlib
E:\xiom-lang\stdlib, XIOM_RUNTIME_DIR retired. Dot-source
scripts\dev-env.ps1 (or scripts/dev-env.sh). Run everything through
scripts\run.ps1 / run.sh (watchdog + exit-code gate).

State (2026-10-08): bootstrap complete; conformance 93/93 x2 Windows + WSL;
WAL crash/reopen GREEN x2 + 200-record soak. Compiler findings C-ORBIT-01/02/
03 open with repro bundles (docs/repro/) and in-repo workarounds; re-test
them on the next compiler archive (C-ORBIT-01 may be fixed by 0c5337e0).

TASK ORDER:
1. Phase 1: durable pages -- byte-level codec (stdlib byte-IO is the filed
   dependency; until then keep Vec[Int] honest), CRC32C via
   xiom.hash.crc.crc32c, free-space map hardening, node-per-page B-tree.
2. Harden B-tree delete/underflow (odd-order min-key invariant debt) with a
   churn soak; add delete-heavy probes.
3. Keep SESSION.md STATE + the three relay docs + RELAY-INTRO updated at
   every wrap; commit signed (DCO -s) at every logical step.

Discipline: every struct literal lists every field; rebind match-bound
cross-module Result payloads through an annotated local (C-ORBIT-01); never
index-assign an Option into a Vec[Option[T]] element (C-ORBIT-02); no &mut
method calls on nested field receivers (C-ORBIT-03); no const-receiver
.to_str(); explicit *p for &mut Int; probes in-repo; suites x2; outputs to
files, never inherited pipes; hang loops need io.sleep.
```
