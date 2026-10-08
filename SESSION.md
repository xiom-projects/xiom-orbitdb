# XIOM ORBITDB -- Session Handoff

<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

**Written:** 2026-10-08 (end of the bootstrap+Phase-1 session), updated for a
clean handoff.
**Updated:** 2026-10-08 (checkpoint session): `db_file_checkpoint` +
snapshot recovery landed; suite 106/106 x2 Win + WSL; crash scenarios B/C.
**Updated:** 2026-10-08 (query session): `db_file_query`/`db_file_range` +
query-after-recovery crash checks; suite 107/107; db_crash 15/15 x2 Win + WSL.
**Updated:** 2026-10-08 (node-per-page session): incremental generation-
committed checkpoints + `maybe_checkpoint` policy + compaction test; suite
112/112; filed C-ORBIT-05 with a repro bundle.
**Updated:** 2026-10-08 (transaction session): durable `db_file_txn_*`
(begin/commit/abort, committed/uncommitted recovery); suite 115/115;
db_crash 25/25 with txn scenarios D/E.
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
  `1faf145` benchmarks); checkpoint session `c3abe56` -> `29813fd`
  (`868cefe` storage primitives, `de826db` engine checkpoint (suite
  104 -> 106), `f359707` crash-harness checkpoint scenarios, wrap
  `29813fd`); query session `29813fd` -> `f99a28b` (`06be90e` DBFile
  query/range (suite 107), `5ec8c79` qverify checks, wrap `f99a28b`);
  node-per-page session `f99a28b` -> `e2dce00` (`c2d1395` page log (suite
  108), `855a457` C-ORBIT-05-safe dedup + finding, `8732a42` incremental
  checkpoints + policy (suite 111), `a3d1f9b` wrap, `e2dce00` compaction
  (suite 112)); transaction session `e2dce00` -> HEAD (`12405f5` durable
  transactions (suite 115), `4d6703c` txn crash scenarios D/E, then the
  wrap commit).
- **VERSION POLICY (owner): track the LATEST compiler / stdlib / packages.**
  Record exact versions + lane hashes here at every wrap.
  - compiler: **v0.64.1** -- Windows `%LOCALAPPDATA%\xiom.new\bin\xiom.exe`,
    WSL `~/.local/bin/xiom`; `XIOM_RUNTIME_DIR` retired. Re-tested
    2026-10-08: **C-ORBIT-01..05 all still open**; lane regression clean;
    the false W004 warning from v0.64.0 is gone. The lane is mid "v0.64.2
    lane sweep" (`ba19be61`): **watch for the v0.64.2 archive and re-test
    all five bundles + suite before other work.**
  - stdlib: `E:\xiom-lang\stdlib` @ `82444e5` (2026-10-08) = `/mnt/e/xiom-lang/stdlib`.
  - compiler lane @ `99359c6e` (m234 "Vec element strides include LLVM
    alignment padding" -- **possibly the C-ORBIT-05 fix: re-test the repro
    unchanged on the next archive**); packages lane @ `c3b14019`
    (eco-v0.1.111).
  - `xiom doctor` shows 2 environment warnings (bundled stdlib older than
    compiler; stale second binary on PATH) -- lane noise: `scripts/dev-env.*`
    sets `XIOM_COMPILER`/`XIOM_STDLIB` explicitly.
- **Green evidence (exact commands; all GREEN x2 Windows + WSL unless noted):**
  - Suite: `scripts/run.ps1 tests/test_conformance.xi -TimeoutSec 300` ->
    **115/115, exit 0** (x2 Win + WSL). Composition: 93 base + 2 churn +
    CRC32C KAT + 3 tuple-codec + 2 FSM + 2 page-file + 1 page-log + 11 db-file
    (roundtrip, checkpoint, churn, query/range, incremental, uncommitted
    generation, policy, compaction, txn commit, txn abort/guards, dangling
    txn).
  - Crash/recovery harnesses: `scripts/crash_test.ps1 -Events 20` (WAL; 200
    soak), `scripts/page_crash_test.ps1 -Pages 20`, `scripts/db_crash_test.ps1
    -Keys 20 -Tail 3 -Tx 5` (five scenarios: WAL-only, snapshot-only,
    snapshot+tail, uncommitted txn, committed txn; 200 soak). All: writer ->
    hard kill -> torn tail -> reopen -> verify -> heal -> verify +1; each
    recovery is followed by `qverify` (key-range + value-filter queries on the
    recovered tree; 25 checks).
    Checkpoint scenarios poll snapshot file + truncated WAL line count before
    killing (x2 Win + WSL).
  - Benchmarks: `scripts/bench.ps1 -N 10000` / `scripts/bench.sh` ->
    `probe-logs/bench-*.txt`. v0.64.1 N=10k: Win insert 1.25M/s, search
    3.3M/s, delete 1.67M/s, tuple 714k/s, WAL append 2.9k/s, replay 0.94k/s;
    WSL(native fs) append 26k/s, replay 1.97k/s. `bench.sh` writes scratch
    WAL to `/tmp` (DrvFs on `/mnt/e` skews append ~20x).
  - Model soaks: `probe_btree_churn.xi` (orders 4/5/6 x 20k ops + seed
    matrix), `probe_fsm.xi` (50k ops, 256 pages), `probe_crc32c.xi`,
    `probe_tuple_codec.xi`, `probe_page_file.xi`, `probe_wal_file.xi`,
    `probe_db_file.xi` (policy soak: 2000 keys, `ORBITDB_DB_CKPT_EVERY=250`
    record limit -> 9 checkpoints, reopen + verify + post-recovery write;
    GREEN x2 Win + WSL, WSL scratch on /tmp).
- **What exists (Phase 0 + most of Phase 1):**
  - In-memory: flat-array B-tree (churn-proven delete), query (value
    semantics, pinned in `docs/query-pipeline.md`), in-memory WAL/engine,
    `Database` facade.
  - Durable: `src/wal_file.xi` (durable segment, LSN resume, heal,
    truncate seam keeping payloads), `src/storage/page_file.xi` (CRC32C text
    page store + append-only page log: atomic rewrite, batch install,
    read-all, append/latest-wins/heal-tail),
    `src/storage/tuple.xi` codec v1 (LE helpers exported), CRC32C, best-fit
    FSM, and **`DBFile`** in `src/engine.xi`: WAL-before-ack
    (`db_file_put/delete` append first), `db_file_open` replay recovery.
  - Checkpoint (updated): `db_file_checkpoint` = INCREMENTAL
    generation-committed snapshot (`<wal>.snap` page log; page id =
    generation*2^32 + node_idx + 1): only changed nodes are appended, the
    header page (id 0, highest generation) commits, uncommitted newer pages
    are ignored on load, and compaction rewrites one version per page when
    the log passes node_count + 64. Then a Checkpoint anchor record
    (`lsn|6|snapshot_lsn|root|0|generation,node_count,order`) and
    `wal_file_truncate` keeping `lsn >= anchor` (anchor survives, `next_lsn`
    resumes). `db_file_open` loads the newest committed generation and
    replays only records with `lsn > checkpoint_lsn`; no snapshot -> full
    replay. `db_file_maybe_checkpoint(db, limit)` checkpoints once `limit`
    records accumulate (counter resets per checkpoint).
  - Queries (new): `db_file_range(low, high)` (key range, values in key order)
    and `db_file_query(query)` (value filter with offset/limit) on the
    live/recovered tree; semantics match `db_range`/`db_query` (pinned in
    `docs/query-pipeline.md`).
  - Transactions (new): `db_file_txn_begin/put/delete/commit/abort/active` --
    ops are logged as they happen (WAL-before-ack) but applied only at commit;
    abort discards; recovery applies committed windows and drops unterminated
    ones, finalizing a dangling window with an Abort record; checkpoint and
    auto-commit writes are rejected while a transaction is active.
  - Index-of-record: `docs/PRODUCTION-READINESS.md` **61.0/100 (~61%)**,
    per-area table + changelog + 100% checklist (v0.3-beta gate needs fsync +
    torn-page matrix + benchmarks at scale).
- **Known limitations / risks (read before touching storage):**
  - **No fsync** (stdlib row 1): process-crash safe only; never claim
    power-loss durability. `wal_file_flush`/`page_file_sync` are the seams.
  - **WAL replay is quadratic** because stdlib `str_split` /
    `io.read_file_lines` is O(n^2) (filed; bench evidence). A checkpoint bounds
    the replayed tail, but snapshot load also reads the whole page file; keep
    inputs modest until fixed.
  - **Checkpointing is incremental but still O(nodes) per call**: each
    checkpoint encodes + byte-compares every resident node (the diff) and
    reads the whole page log twice; the tree stays fully resident in memory.
    Truncate keeps the Checkpoint anchor -- NEVER truncate to empty (next_lsn
    lives in the segment). Snapshot path is `<wal>.snap`; dedup on load is
    quadratic in log entries (bounded by compaction).
  - `DBFile` (put/get/delete/size/flush/last_lsn/checkpoint/range/query/txn)
    and the in-memory `Database` facade are still separate; `DBFile`
    transactions are single-active with no isolation/MVCC (readers see
    committed state only).
  - Node-per-page B-tree: durable node pages with incremental
    generation-committed flush are done (see Checkpoint above), but the live
    tree is still fully resident (rebuilt on open); paged/evicting access
    needs the pager seam (`xiom.core.storage.pager` / C-PULSE-02).
  - B-tree nodes are append-only (no free list); `btree_to_vec` is
    value-only.
- **Relay status:** all per-lane messages delivered (owner relays).
  `docs/COMPILER-FINDINGS-ORBITDB.md` + `docs/RELAY-COMPILER-ORBITDB.md`
  carry C-ORBIT-01..05 (05 = new: nested `Vec[Struct-with-Vec]` + push
  aborts v0.64.1) and the v0.64.1 re-test; `docs/STDLIB-WISHLIST-ORBITDB.md`
  + `docs/RELAY-STDLIB-ORBITDB.md` carry the fsync/byte-IO/CR gaps **and the
  new `str_split` quadratic + append-handle findings**; package docs carry
  the `xiom.wal`/`xiom.btree` decisions.
- **Next action (priority order):**
  1. **Re-test on the next compiler archive** (lane fix `99359c6e` m234 may
     address C-ORBIT-05): all five C-ORBIT bundles + `docs/repro/vec-push-
     nested/probe.xi` unchanged + full suite; update findings/relay docs
     before other work.
  2. **Node-per-page paged access** (bounded cache/eviction) on the durable
     node pages -- the remaining A5 gap; still tied to the pager seam.
  3. **Isolation story** (D3): decide MVCC vs single-writer locking; short of
     that, transaction ergonomics (multi-handle safety, txn-aware checkpoint
     policy).
  4. Checkpoint diff cost (dirty tracking through the tree instead of the
     full encode/compare scan) once the store seam is touched; keep
     readiness + relay docs current; commit signed at every logical step.

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
- **C-ORBIT-05:** never copy `Vec` elements of structs that own Vec fields
  (`Vec[Page]`) inside a nested loop that also pushes into a `Vec` -- v0.64.1
  aborts (access violation, no diagnostic). Workaround: keep-set over a
  parallel `Vec[Int]` + one non-nested push pass (`page_log_read_all`);
  repro `docs/repro/vec-push-nested/probe.xi`.

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
- Harness flake: `page_crash_test`'s writer can exceed the default 90s start
  window under heavy load (compile + many chained runs). Re-run with
  `-TimeoutSec 120`; a single `observed=2`-style start miss is environmental,
  not a code fail -- confirm with a clean x2.

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

CURRENT STATE: conformance 115/115 x2 Win + WSL; WAL/page crash x2 both;
db_crash five scenarios (WAL-only, snapshot-only, snapshot+tail, uncommitted
txn discarded, committed txn recovered) x2 Win + WSL, each recovery followed
by qverify (range + value-filter queries; 25 checks); policy soak 2000 keys /
9 checkpoints x2 Win + WSL; bench harness live; readiness 61.0/100
(docs/PRODUCTION-READINESS.md -- recompute + changelog every wrap). Durable
pieces: src/wal_file.xi (segment + Begin/Commit/Abort txn records, LSN
resume, heal-state, truncate seam keeping payloads), src/storage/page_file.xi
(CRC32C text page store + append-only page log: append/latest-wins/compact),
src/storage/tuple.xi codec v1 (LE helpers exported), CRC32C, best-fit FSM,
DBFile in src/engine.xi (WAL-before-ack + replay recovery + incremental
generation-committed checkpoint + db_file_maybe_checkpoint policy + durable
transactions: db_file_txn_*, committed/uncommitted classification,
dangling-window abort on open; db_file_range + db_file_query). Known limits:
no fsync (process-crash safe only); replay/O(n^2) line IO (filed); checkpoint
diff scans all resident nodes; transactions single-active, no isolation/MVCC;
live tree still resident (pager seam pending).

TASK ORDER (highest value first):
1. Watch for the next compiler archive (lane fix m234 `99359c6e` may address
   C-ORBIT-05): re-test all five C-ORBIT bundles (incl.
   docs/repro/vec-push-nested/) unchanged + full suite; update findings/relay
   docs before other work.
2. Node-per-page paged access (bounded cache/eviction) -- remaining A5 gap,
   tied to the pager seam.
3. Isolation story (D3): MVCC vs single-writer locking decision.
4. Checkpoint dirty-tracking diff; keep SESSION.md STATE, relay docs and
   PRODUCTION-READINESS updated at every wrap; commit signed per step.

DISCIPLINE (v0.64.1 workarounds, all still needed):
- Rebind cross-module generic Result payloads through an annotated local
  (let d: Row = decoded;) -- C-ORBIT-01.
- Never index-assign Option into Vec[Option[T]]; rebuild the Vec -- C-ORBIT-02.
- No &mut methods on nested-field receivers; copy-mutate-writeback -- C-ORBIT-03.
- Module-qualify enum variants in constructors AND patterns when variant
  names repeat across modules -- C-ORBIT-04.
- Never copy Vec elements of structs with Vec fields in a nested loop that
  also pushes into a Vec -- v0.64.1 aborts (C-ORBIT-05); use an Int keep-set
  + a single non-nested push pass.
- Struct literals list every field; init locals at declaration; no
  const-receiver .to_str(); explicit *p for &mut Int; trim every read line;
  hang loops need io.sleep; keep read_file_lines inputs small (quadratic).
Commits: conventional + `-s`; docs coupled to code in the same commit;
record lane HEAD hashes in SESSION.md at every wrap.
```
