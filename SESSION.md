# XIOM ORBITDB -- Session Handoff

<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

**Written:** 2026-10-08 (end of the bootstrap+Phase-1 session), updated for a
clean handoff.
**Updated:** 2026-10-08 (checkpoint session): `db_file_checkpoint` +
snapshot recovery landed; suite 106/106 x2 Win + WSL; crash scenarios B/C.
**Project:** embedded database engine for XIOM -- B-Tree, WAL, query engine,
crash recovery; formerly `xiom-db` (renamed `xiom-orbitdb`).

## 0. STATE (2026-10-08)

- **Repo:** `E:\xiom-projects\xiom-orbitdb`. **PRIVATE**; no push/remote
  without owner approval. Identity `Lefteris Notas <lefterisnotas@gmail.com>`,
  conventional commits with DCO sign-off (`git commit -s`).
- **Commit ranges:** bootstrap+Phase-1 `f2dec60` -> `1faf145` (17 commits:
  `c7d4901` B-tree delete hardening, `59b67bd` `xiom.wal` reference,
  `7b2a206` CRC32C, `5dc6450` tuple codec v1, `0462820` FSM hardening,
  `2503eb4` page file, `32d71c3` DBFile, `cf5a64a` v0.64.1 re-test,
  `1faf145` benchmarks); checkpoint session `c3abe56` -> HEAD (`868cefe`
  storage primitives, `de826db` engine checkpoint (suite 104 -> 106),
  `f359707` crash-harness checkpoint scenarios, then the wrap commit).
- **VERSION POLICY (owner): track the LATEST compiler / stdlib / packages.**
  Record exact versions + lane hashes here at every wrap.
  - compiler: **v0.64.1** -- Windows `%LOCALAPPDATA%\xiom.new\bin\xiom.exe`,
    WSL `~/.local/bin/xiom`; `XIOM_RUNTIME_DIR` retired. Re-tested
    2026-10-08: **C-ORBIT-01..04 all still open**; lane regression clean;
    the false W004 warning from v0.64.0 is gone.
  - stdlib: `E:\xiom-lang\stdlib` @ `a677338` (2026-10-08) = `/mnt/e/xiom-lang/stdlib`.
  - compiler lane @ `0c5337e0`; packages lane @ `bb286506` (eco-v0.1.87).
  - `xiom doctor` shows 2 environment warnings (bundled stdlib older than
    compiler; stale second binary on PATH) -- lane noise: `scripts/dev-env.*`
    sets `XIOM_COMPILER`/`XIOM_STDLIB` explicitly.
- **Green evidence (exact commands; all GREEN x2 Windows + WSL unless noted):**
  - Suite: `scripts/run.ps1 tests/test_conformance.xi -TimeoutSec 300` ->
    **106/106, exit 0** (x2 Win + WSL). Composition: 93 base + 2 churn +
    CRC32C KAT + 3 tuple-codec + 2 FSM + 2 page-file + 3 db-file (roundtrip,
    checkpoint, checkpoint-churn).
  - Crash/recovery harnesses: `scripts/crash_test.ps1 -Events 20` (WAL; 200
    soak), `scripts/page_crash_test.ps1 -Pages 20`, `scripts/db_crash_test.ps1
    -Keys 20 -Tail 3` (three scenarios: WAL-only, snapshot-only,
    snapshot+tail; 200 soak). All: writer -> hard kill -> torn tail -> reopen
    -> verify -> heal -> verify +1. Checkpoint scenarios poll snapshot file +
    truncated WAL line count before killing (x2 Win + WSL).
  - Benchmarks: `scripts/bench.ps1 -N 10000` / `scripts/bench.sh` ->
    `probe-logs/bench-*.txt`. v0.64.1 N=10k: Win insert 1.25M/s, search
    3.3M/s, delete 1.67M/s, tuple 714k/s, WAL append 2.9k/s, replay 0.94k/s;
    WSL(native fs) append 26k/s, replay 1.97k/s. `bench.sh` writes scratch
    WAL to `/tmp` (DrvFs on `/mnt/e` skews append ~20x).
  - Model soaks: `probe_btree_churn.xi` (orders 4/5/6 x 20k ops + seed
    matrix), `probe_fsm.xi` (50k ops, 256 pages), `probe_crc32c.xi`,
    `probe_tuple_codec.xi`, `probe_page_file.xi`, `probe_wal_file.xi`,
    `probe_db_file.xi` (checkpoint soak: 2000 keys, checkpoint every 250 ->
    9 checkpoints, reopen + verify + post-recovery write; GREEN x2 Win + WSL,
    WSL scratch on /tmp).
- **What exists (Phase 0 + most of Phase 1):**
  - In-memory: flat-array B-tree (churn-proven delete), query (value
    semantics, pinned in `docs/query-pipeline.md`), in-memory WAL/engine,
    `Database` facade.
  - Durable: `src/wal_file.xi` (durable segment, LSN resume, heal,
    truncate seam keeping payloads), `src/storage/page_file.xi` (CRC32C text
    page store, atomic rewrite + atomic batch install + read-all),
    `src/storage/tuple.xi` codec v1 (LE helpers exported), CRC32C, best-fit
    FSM, and **`DBFile`** in `src/engine.xi`: WAL-before-ack
    (`db_file_put/delete` append first), `db_file_open` replay recovery.
  - Checkpoint (new): `db_file_checkpoint` = node page codec snapshot
    (`<wal>.snap`, page 0 header + one page per node, LE i64) installed with
    one atomic rename, then a Checkpoint anchor record
    (`lsn|6|snapshot_lsn|root|0|generation,node_count,order`), then
    `wal_file_truncate` keeping `lsn >= anchor` (the anchor survives so
    `next_lsn` resumes). `db_file_open` loads the snapshot and replays only
    records with `lsn > checkpoint_lsn`; no snapshot -> full replay.
  - Index-of-record: `docs/PRODUCTION-READINESS.md` **56.5/100 (~57%)**,
    per-area table + changelog + 100% checklist.
- **Known limitations / risks (read before touching storage):**
  - **No fsync** (stdlib row 1): process-crash safe only; never claim
    power-loss durability. `wal_file_flush`/`page_file_sync` are the seams.
  - **WAL replay is quadratic** because stdlib `str_split` /
    `io.read_file_lines` is O(n^2) (filed; bench evidence). A checkpoint bounds
    the replayed tail, but snapshot load also reads the whole page file; keep
    inputs modest until fixed.
  - **Checkpointing exists but is manual and whole-file**: `db_file_checkpoint`
    rewrites the entire snapshot page set (text codec, O(nodes)); no policy or
    background cadence. Truncate keeps the Checkpoint anchor -- NEVER truncate
    to empty (next_lsn lives in the segment). Snapshot path is `<wal>.snap`.
  - `DBFile` has no query/range API yet (put/get/delete/size/flush/last_lsn
    only); engine `Database` is separate and still in-memory.
  - Node-per-page B-tree: the SNAPSHOT is node-per-page on the page file, but
    the live tree is still in-memory (rebuilt on open); pager integration
    externally blocked (`xiom.core.storage.pager` substrate / C-PULSE-02).
  - B-tree nodes are append-only (no free list); `btree_to_vec` is
    value-only.
- **Relay status:** all per-lane messages delivered (owner relays).
  `docs/COMPILER-FINDINGS-ORBITDB.md` + `docs/RELAY-COMPILER-ORBITDB.md`
  carry C-ORBIT-01..04 and the v0.64.1 re-test; `docs/STDLIB-WISHLIST-ORBITDB.md`
  + `docs/RELAY-STDLIB-ORBITDB.md` carry the fsync/byte-IO/CR gaps **and the
  new `str_split` quadratic + append-handle findings**; package docs carry
  the `xiom.wal`/`xiom.btree` decisions.
- **Next action (priority order):**
  1. **DBFile query/range API** (reuse `query_execute`/`btree_range_query` on
     `db.tree`) + a query-after-recovery crash phase.
  2. **Node-per-page B-tree** on the stable snapshot codec (pager substrate
     still externally blocked; the snapshot already gives page-per-node
     representation to build on).
  3. Re-test C-ORBIT bundles on the next archive; keep readiness + relay docs
     current; commit signed at every logical step.
  4. Checkpoint policy (cadence, bounded snapshot rewrite) once the pager /
     codec swap is decided.

## 1. Consumer-lane rules (non-negotiable)

- **Never edit** `E:\xiom-lang\stdlib`, `E:\xiom-lang\xiom`,
  `E:\xiom-packages\packages`. Record lane HEADs each wrap:
  `git -C <lane> log -1 --format="%h %cI %s"`.
- Report upstream only through the relay docs + SESSION rows; the owner
  relays. Read PULSE's relay docs before filing (reference their IDs).
- Packages only from the registry; never vendor. Extraction candidates go to
  `docs/PACKAGE-WISHLIST-ORBITDB.md`.

## 2. Pin discipline that bites (v0.64.1)

Base rules:
- Initialize every local at declaration; every **struct literal lists every
  field** (C-PULSE-06). No module-scope cross-package constructors
  (C-PULSE-07).
- No `.to_str()` on module-`const` receivers (C-PULSE-05); use
  `convert.int_to_string`. Explicit `*p` for every `&mut Int` read
  (C-PULSE-04).
- Parenthesize bitwise & additive mixes; no overloading; cross-module helpers
  need `pub`; submodule functions need submodule imports
  (`use xiom.string.split;` -> `split.str_split`; `xiom.convert.parse` ->
  `parse.parse_int`).

**C-ORBIT workarounds (keep until the compiler lane fixes them):**
- **C-ORBIT-01:** rebind a match-bound payload of a cross-module generic
  `Result` through an explicitly typed local before any access:
  `let d: Row = decoded;` (applies to `io.read_file_lines`, `tuple_decode`,
  `tuple_encode_checked`, `db_file_*`, ...). Explicit receiver form
  `Row.get_column(&decoded, 0)` also works but raw-binding zero-arg calls
  still hit codegen C001.
- **C-ORBIT-02:** never index-assign an `Option` into a `Vec[Option[T]]`
  element; rebuild the Vec and assign it (`BufferPool.put` pattern).
- **C-ORBIT-03:** never call a `&mut` method on a nested field receiver;
  copy out, mutate, write back (`StorageEngine.cache_page` pattern).
- **C-ORBIT-04:** module-qualify enum variants in constructors **and**
  patterns when another module in the graph has same-named variants
  (`WALOpKind.Insert` vs txn's `WALOp.Insert`); unqualified constructors
  lower against the wrong enum -> clang IR type mismatch.

Ops rules:
- Every run through `scripts/run.{ps1,sh}` with a `-TimeoutSec` watchdog and
  exit-code gate; green suites x2; long-running paths soaked. `-Quiet`
  suppresses program output (use only when the exit code is all you need).
- Long-running processes: redirected output to **files**; hang loops need a
  side-effecting call (`io.sleep`) -- empty spin loops are optimized away.
- Watchdog/CRLF gotchas: probes' verify phases where N is a *count* must
  skip key-N checks when a LAST_* env is set; `trim.str_trim` every line
  (CRLF); `heal_tail` semantics live in the `WALFile` handle now
  (`heal_needed`) -- do not re-add a per-append rescan.
- Benchmarks: `read_file_lines`/`str_split` are quadratic -- keep bench N
  modest (10k) and file sizes small until the stdlib fix lands.

## 3. Known ecosystem status (2026-10-08, v0.64.1)

- Compiler: C-PULSE-02 (registry source-roots) open; C-PULSE-04/05/06/07
  open; ORBITDB adds **C-ORBIT-01..04** (all reproduce on v0.64.1).
- Stdlib: `str_split`/`read_file_lines` quadratic (new, filed); fsync,
  byte-IO, truncate, append-handle rows open.
- Packages: `xiom.wal` standalone decision; `xiom.btree` gate MET; registry
  carry `xiom.kv` 0.1.0 with the C-PULSE-10 Linux-only gate. ORBITDB still
  zero-dep and has no `xiom.toml` (add with CI only when going public).

## 4. Relay documents (owner relays; keep current every wrap)

- `docs/COMPILER-FINDINGS-ORBITDB.md` + `docs/RELAY-COMPILER-ORBITDB.md`
  (C-ORBIT-01..04, v0.64.1 re-test, repro bundles `docs/repro/`).
- `docs/STDLIB-WISHLIST-ORBITDB.md` + `docs/RELAY-STDLIB-ORBITDB.md`.
- `docs/PACKAGE-WISHLIST-ORBITDB.md` + `docs/RELAY-PACKAGES-ORBITDB.md` +
  `docs/RELAY-PACKAGES-RESPONSE-ORBITDB.md` (xiom.wal API proposal).
- `docs/RELAY-INTRO-ORBITDB.md` (one-pager), `docs/PRODUCTION-READINESS.md`
  (scoreboard -- recompute + changelog line every wrap).

## 5. Paste prompt for the next ORBITDB session

```
You are the ORBITDB session for E:\xiom-projects\xiom-orbitdb -- the
embedded XIOM database engine (B-Tree, WAL, query engine, crash recovery;
formerly xiom-db). Read SESSION.md first, then README/SPEC/ARCHITECTURE/
ROADMAP/AUDIT and docs/ (relay docs + PRODUCTION-READINESS included).
Consumer lane: never edit E:\xiom-lang\stdlib, E:\xiom-lang\xiom,
E:\xiom-packages\packages. Repo PRIVATE; no pushes without owner approval.
Identity "Lefteris Notas <lefterisnotas@gmail.com>"; conventional commits,
DCO sign-off (git commit -s). Owner relays upstream messages.

TOOLCHAIN (latest-tracking): compiler v0.64.1 Windows + WSL; stdlib
E:\xiom-lang\stdlib; XIOM_RUNTIME_DIR retired. Dot-source scripts\dev-env.ps1
(or scripts/dev-env.sh); run everything via scripts\run.ps1 / run.sh with a
-TimeoutSec watchdog and exit-code gate. Native .sh twins must stay LF.
WSL: the default distro is docker-desktop (no bash) -- run via
`wsl.exe -d Ubuntu bash -lc '...'`.
Evidence rules: green suites x2, crash harnesses x2, soak long paths, keep
probe-logs out of commits (gitignored).

CURRENT STATE: conformance 106/106 x2 Win + WSL; WAL/page crash x2 Win;
db_crash three scenarios (WAL-only, snapshot-only, snapshot+tail) x2 Win +
WSL; checkpoint soak 2000 keys / 9 checkpoints x2 Win + WSL; bench harness
live; readiness 56.5/100 (docs/PRODUCTION-READINESS.md -- recompute +
changelog every wrap). Durable pieces: src/wal_file.xi (segment, LSN resume,
heal-state, truncate seam keeping payloads), src/storage/page_file.xi
(CRC32C text page store, atomic rewrite + batch install + read-all),
src/storage/tuple.xi codec v1 (LE helpers exported), CRC32C, best-fit FSM,
DBFile in src/engine.xi (WAL-before-ack + replay recovery + checkpoint:
node page codec snapshot at <wal>.snap, Checkpoint anchor, keep-anchor
truncate, open = snapshot + tail replay). Known limits: no fsync
(process-crash safe only); replay/O(n^2) line IO (filed); checkpoint is
manual + whole-snapshot rewrite; DBFile has no query/range API yet; live
tree still in-memory (snapshot codec is node-per-page).

TASK ORDER (highest value first):
1. DBFile query/range API (reuse query_execute / btree_range_query on
   db.tree) + a query-after-recovery crash phase.
2. Node-per-page B-tree on the stable snapshot codec (pager substrate still
   externally blocked / C-PULSE-02; the snapshot already gives page-per-node
   representation to build on).
3. Re-test docs/repro bundles + suite on the next compiler archive (watch
   C-ORBIT-01..04; all still open on v0.64.1); update findings + relay docs.
4. Checkpoint policy (cadence, bounded snapshot rewrite) once the pager /
   codec swap is decided; keep SESSION.md STATE, relay docs and
   PRODUCTION-READINESS updated at every wrap; commit signed at every
   logical step.

DISCIPLINE (v0.64.1 workarounds, all still needed):
- Rebind cross-module generic Result payloads through an annotated local
  (let d: Row = decoded;) -- C-ORBIT-01.
- Never index-assign Option into Vec[Option[T]]; rebuild the Vec -- C-ORBIT-02.
- No &mut methods on nested-field receivers; copy-mutate-writeback -- C-ORBIT-03.
- Module-qualify enum variants in constructors AND patterns when variant
  names repeat across modules -- C-ORBIT-04.
- Struct literals list every field; init locals at declaration; no
  const-receiver .to_str(); explicit *p for &mut Int; trim every read line;
  hang loops need io.sleep; keep read_file_lines inputs small (quadratic).
Commits: conventional + `-s`; docs coupled to code in the same commit;
record lane HEAD hashes in SESSION.md at every wrap.
```
