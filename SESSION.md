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
**Updated:** 2026-10-09 (buffer-pool session): clock (second-chance) frame
table + pinning semantics (C4); suite 117/117; page/WAL crash x2 + soak.
**Updated:** 2026-10-09 (H3+I3 session): deterministic fuzz harness
(`scripts/fuzz.{ps1,sh}`) + API/runbook/format reference docs; readiness 66.0.
**Updated:** 2026-10-09 (H2 session): `db_path_valid` + `db_file_open_checked`
input validation; suite 119/119; readiness 66.5.
**Updated:** 2026-10-09 (D3 session): stale-handle write guard + isolation
decision record (`docs/ISOLATION.md`); suite 120/120.
**Updated:** 2026-10-09 (v0.64.2 re-test session): all five C-ORBIT findings
RESOLVED; compiler workarounds dropped (`6f6c3ba`); suite 120/120 x2 Win +
WSL with the native forms; relay/wishlists swept.
**Updated:** 2026-10-09 (production plan + integrations): plan/checklist
(`93bc50f`), PULSE + XVECTOR handshakes (`0ef8572`); FFI asks confirmed
none (pure XIOM through Phase 2).
**Updated:** 2026-10-09 (M1.1 session): NodeStore dirty tracking + dirty-only
checkpoint flush; suite 121/121 x2 Win + WSL; all crash/fuzz/soak green.
**Project:** embedded database engine for XIOM -- B-Tree, WAL, query engine,
crash recovery; formerly `xiom-db` (renamed `xiom-orbitdb`).

## 0. STATE (2026-10-09)

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
  (suite 112)); transaction session `e2dce00` -> `a7a29e6` (`12405f5`
  durable transactions (suite 115), `4d6703c` txn crash scenarios D/E, wrap
  `a7a29e6`); buffer-pool session `a7a29e6` -> `5159b84` (`ade1199` clock
  buffer pool + pinning (suite 117), wrap `5159b84`); H3+I3 session
  `5159b84` -> `823c6bc` (`48f7101` fuzz harness + runners, `4f8f0b2`
  API/runbook/format docs, wrap `823c6bc`); H2 session `823c6bc` -> `2d37588`
  (`1ea7073` path/order validation (suite 119), wrap `2d37588`); D3 session
  `2d37588` -> `18b4818` (`10109e1` stale-handle guard + `docs/ISOLATION.md`
  (suite 120), wrap `18b4818`); v0.64.2 re-test session `18b4818` -> `ef872b0`
  (`6f6c3ba` compiler workarounds dropped (suite 120/120 x2 both),
  `00ed7dd` relay findings/wishlist sweep, wrap `ef872b0`); plan session
  `ef872b0` -> `93bc50f` (production plan + checklist, wrap `93bc50f`);
  integration session `93bc50f` -> `0ef8572` (PULSE/XVECTOR handshakes, wrap
  `0ef8572`); M1.1 session `0ef8572` -> HEAD (`5757c78` NodeStore dirty
  tracking (suite 121), then the wrap commit).
- **VERSION POLICY (owner): track the LATEST compiler / stdlib / packages.**
  Record exact versions + lane hashes here at every wrap.
  - compiler: **v0.64.2** (released 2026-10-09) -- Windows
    `%LOCALAPPDATA%\xiom.new\bin\xiom.exe`, WSL `~/.local/bin/xiom`;
    `XIOM_RUNTIME_DIR` retired. Re-tested today with **all five C-ORBIT
    workarounds reverted**: suites/crash/fuzz/soak green; **C-ORBIT-01..05
    RESOLVED** (m223/m224/m225/m226/m235). Rollback option if a v0.64.2
    regression appears: v0.64.1 (keep the finding notes in
    `docs/COMPILER-FINDINGS-ORBITDB.md`).
  - stdlib: `E:\xiom-lang\stdlib` @ `e7896ff` (2026-10-09; wave 97 + wishlist
    sweep + relay consumption; the linear-split/CR fixes are in the code
    state since `82ac2f3`) = `/mnt/e/xiom-lang/stdlib`. Two ORBITDB rows
    RESOLVED: `str_split`/`read_file_lines` are linear and a trailing CR is
    stripped per line (both citing our relay).
  - compiler lane @ `d9f146cb` (`v0.64.2-2-gd9f146cb`; v0.64.2 tag cut);
    packages lane @ `6bb40bb0` -- its wishlist ledger notes all three
    consumer lanes (PULSE/ORBITDB/XVECTOR) green on v0.64.2 and no new
    package asks.
  - `xiom doctor` shows 2 environment warnings (bundled stdlib older than
    compiler; stale second binary on PATH) -- lane noise: `scripts/dev-env.*`
    sets `XIOM_COMPILER`/`XIOM_STDLIB` explicitly.
- **Green evidence (exact commands; all GREEN x2 Windows + WSL unless noted):**
  - Suite: `scripts/run.ps1 tests/test_conformance.xi -TimeoutSec 300` ->
    **121/121, exit 0** (x2 Win + WSL; v0.64.2 with **all C-ORBIT workarounds
    reverted**). Composition: 93 base + 2 churn +
    CRC32C KAT + 3 tuple-codec + 2 FSM + 2 page-file + 1 page-log + 15 db-file
    (roundtrip, checkpoint, churn, query/range, incremental, uncommitted
    generation, policy, compaction, txn commit, txn abort/guards, dangling
    txn, path validation, checked open, stale handle, dirty flush) + 2
    buffer-pool (clock order, pinning/reject).
  - Crash/recovery harnesses: `scripts/crash_test.ps1 -Events 20` (WAL; 200
    soak), `scripts/page_crash_test.ps1 -Pages 20`, `scripts/db_crash_test.ps1
    -Keys 20 -Tail 3 -Tx 5` (five scenarios: WAL-only, snapshot-only,
    snapshot+tail, uncommitted txn, committed txn; 200 soak). All: writer ->
    hard kill -> torn tail -> reopen -> verify -> heal -> verify +1; each
    recovery is followed by `qverify` (key-range + value-filter queries on the
    recovered tree; 25 checks).
    Checkpoint scenarios poll snapshot file + truncated WAL line count before
    killing (x2 Win + WSL).
  - Fuzz/property: `scripts/fuzz.ps1` / `fuzz.sh` (deterministic LCG seeds) ->
    `fuzz: OK seeds=4 ops/seed=4000 n=512`, x2 Win + WSL; sections cover the
    tuple codec, WAL parser, page log and B-tree vs model.
  - Benchmarks: `scripts/bench.ps1 -N 20000` (v0.64.2): btree insert 1.25M/s,
    search 3.3M/s, delete 1.67M/s, tuple 1.11M/s, WAL append 3.5k/s, WAL
    replay 2.0k/s -- **20k-record replay now ~9.9 s (was 61.6 s on v0.64.1;
    stdlib `read_file_lines` is linear)**. WSL(native fs) append ~26k/s.
    `bench.sh` writes scratch WAL to `/tmp` (DrvFs on `/mnt/e` skews append
    ~20x).
  - Model soaks: `probe_btree_churn.xi` (orders 4/5/6 x 20k ops + seed
    matrix), `probe_fsm.xi` (50k ops, 256 pages), `probe_crc32c.xi`,
    `probe_tuple_codec.xi`, `probe_page_file.xi`, `probe_wal_file.xi`,
    `probe_db_file.xi` (policy soak: 2000 keys, `ORBITDB_DB_CKPT_EVERY=250`
    record limit -> 9 checkpoints, reopen + verify + post-recovery write;
    GREEN x2 Win + WSL, WSL scratch on /tmp).
- **What exists (Phase 0 + most of Phase 1):**
  - In-memory: flat-array B-tree (churn-proven delete), query (value
    semantics, pinned in `docs/query-pipeline.md`), clock buffer-pool with
    pinning (C4), in-memory WAL/engine, `Database` facade.
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
  - Fuzz/property (new): `tests/probes/probe_fuzz.xi` + `scripts/fuzz.{ps1,sh}`
    (deterministic seeds; tuple codec mutations, WAL garbage/torn/heal,
    page-log latest-wins/CRC, B-tree vs model).
  - Reference docs (new): `docs/API.md` (pub surfaces + contracts),
    `docs/RUNBOOK.md` (commands/recovery/gotchas), `docs/FORMATS.md`
    (versioned v1 formats + version policy); linked from README.
  - Production plan (new): `docs/PRODUCTION-PLAN.md` (mission, architecture
    target, workstreams M1-M8, gates P-alpha -> 1.0, benchmark targets,
    release signal) + `docs/checklists/production-release.md`; linked from
    README/ROADMAP/readiness. The owner sets up the public release when the
    release signal fires, and the owner's benchmark suite becomes the
    release gate.
  - Validation (new): `db_path_valid` (non-empty, <= 4096 chars, no CR/LF)
    and `db_file_open_checked(path, order) -> Result[DBFile, DbError]`
    (`Err(ConstraintViolation)` on bad path or order < 3); `db_file_open`
    unchanged for existing callers.
  - Multi-handle guard + isolation record (new): every write path
    (`put`/`delete`/`txn_*`/`checkpoint`) refuses when the WAL segment changed
    since this handle's last own write (`wal_bytes` size guard; no lock
    files); `docs/ISOLATION.md` records the single-writer decision and the
    deferred-MVCC prerequisites.
  - NodeStore (new, M1.1): the B-tree arena tracks dirty nodes -- every
    mutation goes through `ns_set`/`ns_push` -- and `db_file_checkpoint`
    encodes ONLY dirty nodes (full write forced when no prior snapshot or an
    uncommitted crashed generation lingers), clearing flags on commit; the
    suite pins a bounded delta for a one-key update. Lazy load + a bounded
    clock cache are the next slice.
  - Index-of-record: `docs/PRODUCTION-READINESS.md` **66.5/100 (~67%)**,
    per-area table + changelog + 100% checklist (v0.3-beta gate needs fsync +
    torn-page matrix + benchmarks at scale).
- **Known limitations / risks (read before touching storage):**
  - **No fsync**: process-crash safe only; never claim power-loss durability.
    The stdlib surface exists but is stubbed (`os/fs_ffi.fsync` +
    `os/sync_io.sync_fd` return Err); `wal_file_flush`/`page_file_sync` are
    the seams.
  - **WAL replay is linear now** (stdlib `str_split`/`read_file_lines` fixed,
    wave 96/97): 20k records replay in ~9.9 s (was 61.6 s). Remaining cost is
    per-record parsing; checkpoints still bound the replayed tail.
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
  - Buffer pool: the clock replacer + pinning (C4) are in-memory only; the
    pager substrate (C3) is still pending, so pinning is not yet exercised by
    a durable consumer (DBFile keeps nodes resident).
  - Fuzz/property runs per wrap; continuous CI cadence is gated on F3 (CI
    matrix). Probe env parsing falls back to defaults on malformed values
    (only the required DB path errors out).
  - Multi-handle safety is optimistic: the `wal_bytes` stale-write guard
    refuses lagging writers but is not a lock (external appends are detected
    only on the next write); no MVCC -- see `docs/ISOLATION.md`.
  - B-tree nodes are append-only (no free list); `btree_to_vec` is
    value-only.
- **Relay status:** all per-lane messages delivered (owner relays).
  `docs/COMPILER-FINDINGS-ORBITDB.md` + `docs/RELAY-COMPILER-ORBITDB.md`
  now record **C-ORBIT-01..05 RESOLVED on v0.64.2** (m223/m224/m225/m226/
  m235; one consumer-scope caveat on m225) plus the incoming relay
  `docs/COMPILER-RELAY-2026-10-09-v0.64.2.md`. Stdlib wishlist: the
  `str_split`/`read_file_lines` quadratic **and** the CR-strip row are
  RESOLVED (both citing our relay); fsync (stubs), append-handle, truncate,
  byte-IO, tail-check remain open. Package docs carry the `xiom.wal`/
  `xiom.btree` decisions.
  Consumer handshakes (new): PULSE (`docs/PULSE-INTEGRATION.md`, answering
  `xiom-pulse/docs/ORBITDB-RELAY-PULSE.md`) -- PULSE builds
  `probe_pkg_orbitdb` and uses us as its 0.3 embedded/relational driver
  (`open/exec/query/tx`); XVECTOR (`docs/XVECTOR-INTEGRATION.md` +
  `docs/RELAY-XVECTOR-ORBITDB.md`) -- asks for
  `xiom-xvector/docs/ORBITDB-INTEGRATION.md`, then the hybrid row+vector
  join probe.
- **Next action (priority order, per `docs/PRODUCTION-PLAN.md` section 13):**
  1. **M1.1b lazy load + bounded node cache** (finish plan slice 1): load
     nodes on demand from snapshot pages; clock cache with write-back reusing
     C4 semantics; keep the public API surface stable.
  2. **M4.1 planner pushdown** (key-range/point + cost estimate).
  3. **M1.2 byte-page format v2 design** now; implement when the stdlib
     byte-IO row lands.
  4. **M2.1 fsync wiring** when the stdlib row lands; MVCC design per M3;
     keep readiness + relay docs current; commit signed at every step.

## 1. Consumer-lane rules (non-negotiable)

- **Never edit** `E:\xiom-lang\stdlib`, `E:\xiom-lang\xiom`,
  `E:\xiom-packages\packages`. Record lane HEADs each wrap:
  `git -C <lane> log -1 --format="%h %cI %s"`.
- Report upstream only through the relay docs + SESSION rows; the owner
  relays. Read PULSE's relay docs before filing (reference their IDs).
- Packages only from the registry; never vendor. Extraction candidates go to
  `docs/PACKAGE-WISHLIST-ORBITDB.md`.

## 2. Pin discipline that bites (v0.64.2: compiler workarounds dropped)

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

**v0.64.2 status: the C-ORBIT workarounds are DROPPED** (commit `6f6c3ba`;
findings RESOLVED, see `docs/COMPILER-FINDINGS-ORBITDB.md`). Rules that
remain -- now design rules, not workarounds:
- Never index-assign an `Option` into a `Vec[Option[T]]` element; use
  parallel vectors or rebuild (`BufferPool` design). m226 fixed the language
  bug, but the parallel-vector frame table is the better hot-cache shape.
- Module-qualify enum variants in CONSUMER modules when a same-named enum is
  anywhere in the program (`WALOpKind.Insert` vs txn's `WALOp.Insert`):
  m225 fixed declaring-module resolution, but cross-import ambiguity in
  consumers still resolves to the wrong twin with no diagnostic.
- Deep container equality is live (m239): `==` compares `Vec`/`Str` content;
  legacy `vec_eq` helpers may be retired opportunistically.

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
- Benchmarks: `read_file_lines`/`str_split` are linear now (v0.64.2);
  `-N 20000` is the current reference (replay ~9.9 s).
- Harness flake: `page_crash_test`'s writer can exceed the default 90s start
  window under heavy load (compile + many chained runs). Re-run with
  `-TimeoutSec 120`; a single `observed=2`-style start miss is environmental,
  not a code fail -- confirm with a clean x2.

## 3. Known ecosystem status (2026-10-09, v0.64.2)

- Compiler: **C-ORBIT-01..05 RESOLVED** on v0.64.2 (workarounds dropped);
  one follow-up requested -- cross-import enum ambiguity in consumer modules
  still resolves to the wrong twin (no diagnostic). C-PULSE-02 (registry
  source-roots) and C-PULSE-04/05/06/07 remain on the PULSE lane; m239 deep
  container equality is live (verified).
- Stdlib: linear `str_split`/`read_file_lines` + trailing-CR stripping landed
  (RESOLVED, both citing our relay); real fsync is still a stub; append
  handle, truncate, byte-IO, tail-check open.
- Packages: `xiom.wal` gate not met (stdlib fsync still open); `xiom.btree`
  gate MET + fuzz coverage; registry carries `xiom.kv` 0.1.0 with the
  C-PULSE-10 Linux-only gate. ORBITDB still zero-dep and has no `xiom.toml`
  (add with CI only when going public).

## 4. Relay documents (owner relays; keep current every wrap)

- `docs/COMPILER-FINDINGS-ORBITDB.md` + `docs/RELAY-COMPILER-ORBITDB.md`
  (C-ORBIT-01..05 RESOLVED on v0.64.2; historical v0.64.0/0.64.1 sections;
  repro bundles `docs/repro/`; incoming relay
  `docs/COMPILER-RELAY-2026-10-09-v0.64.2.md`).
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

TOOLCHAIN (latest-tracking): compiler v0.64.2 Windows + WSL; stdlib
E:\xiom-lang\stdlib; XIOM_RUNTIME_DIR retired. Dot-source scripts\dev-env.ps1
(or scripts/dev-env.sh); run everything via scripts\run.ps1 / run.sh with a
-TimeoutSec watchdog and exit-code gate. Native .sh twins must stay LF.
WSL: the default distro is docker-desktop (no bash) -- run via
`wsl.exe -d Ubuntu bash -lc '...'`.
Evidence rules: green suites x2, crash harnesses x2, soak long paths, keep
probe-logs out of commits (gitignored).

CURRENT STATE: v0.64.2 pin; all C-ORBIT compiler workarounds REVERTED and the
suite is green on the native forms -- conformance 120/120 x2 Win + WSL (see
the findings file for the one consumer-qualification caveat); db_crash five
scenarios (WAL-only, snapshot-only, snapshot+tail, uncommitted txn discarded,
committed txn recovered) x2 Win + WSL, each recovery followed by qverify
(range + value-filter queries; 25 checks); fuzz/property harness
`scripts/fuzz.{ps1,sh}` (seeds=4 ops/seed=4000) x2 Win + WSL; policy soak
2000 keys / 9 checkpoints x2 Win + WSL; 20k-record WAL replay ~9.9 s (linear
stdlib); bench harness live; readiness
66.5/100 (docs/PRODUCTION-READINESS.md -- recompute + changelog every wrap);
reference docs docs/API.md + docs/RUNBOOK.md + docs/FORMATS.md +
docs/ISOLATION.md; production plan docs/PRODUCTION-PLAN.md +
docs/checklists/production-release.md (M1-M8, gates P-alpha -> 1.0, release
signal). Durable pieces: src/wal_file.xi (segment +
Begin/Commit/Abort txn records, LSN resume, heal-state, truncate seam keeping
payloads), src/storage/page_file.xi (CRC32C text page store + append-only
page log: append/latest-wins/compact), src/storage/tuple.xi codec v1 (LE
helpers exported), CRC32C, best-fit FSM, clock buffer-pool + pinning in
src/storage/page.xi (C4), DBFile in src/engine.xi (WAL-before-ack + replay
recovery + incremental generation-committed checkpoint +
db_file_maybe_checkpoint policy + durable transactions: db_file_txn_*,
committed/uncommitted classification, dangling-window abort on open;
db_file_range + db_file_query; db_path_valid + db_file_open_checked
validation; wal_bytes stale-handle write guard; NodeStore dirty tracking =
dirty-only checkpoint flush (M1.1)). Known limits: no fsync
(process-crash safe only); replay/O(n^2) line IO (filed); checkpoint diff
scans all resident nodes; transactions single-active, no MVCC (single-writer
model in docs/ISOLATION.md); buffer pool in-memory only and live tree still
resident (pager seam C3 pending); fuzz runs per wrap (CI cadence awaits F3).

TASK ORDER (highest value first; full plan docs/PRODUCTION-PLAN.md sec. 13):
1. M1.1b lazy load + bounded node cache (finish slice 1): on-demand loads
   from snapshot pages, clock cache with write-back; evidence x2 both
   platforms.
2. M4.1 planner pushdown (key-range/point + cost).
3. M1.2 byte-page format v2 design; implement when stdlib byte IO lands.
4. M2.1 fsync wiring when stdlib lands; MVCC design per M3; keep SESSION.md
   STATE, relay docs and PRODUCTION-READINESS updated at every wrap; commit
   signed per step.

DISCIPLINE (v0.64.2; C-ORBIT workarounds DROPPED -- see COMPILER-FINDINGS):
- Consumer modules: module-qualify enum variants when a same-named enum is
  anywhere in the program (m225 consumer-scope caveat; no ambiguity error).
- Prefer parallel vectors over Vec[Option] element writes for hot caches
  (design choice; m226 fixed the language bug).
- Deep equality works (m239): Vec/Str == compare by content; hand-written
  vec_eq helpers may be retired opportunistically.
- Struct literals list every field; init locals at declaration; no
  const-receiver .to_str(); explicit *p for &mut Int; trim every read line;
  hang loops need io.sleep.
Commits: conventional + `-s`; docs coupled to code in the same commit;
record lane HEAD hashes in SESSION.md at every wrap.
```
