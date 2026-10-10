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
**Updated:** 2026-10-09 (M4.1 session): key-range planner pushdown +
  `query_key_range`; app-build `--icon` helper (`assets/orbitdb.ico`); suite
  123/123 x2 Win + WSL; readiness 69.5.
**Updated:** 2026-10-10 (hybrid-integration session): XVECTOR's reply processed
  (`xiom-xvector/docs/ORBITDB-INTEGRATION.md`); `tests/hybrid/` consumer probe
  + `scripts/hybrid_crash_test.{ps1,sh}` (hard kill both stores -> reopen ->
  repair -> 100% join integrity; idempotent second verify) GREEN x2 Win + WSL;
  finding **XV-ORBITDB-01** filed (chained persist/load of a recovered engine
  goes empty; probe carries the re-LSN workaround); composition exposed and
  retired the dead `xiom.core.*` folds (**C-ORBIT-06** filed with repro);
  suite 123/123 x2 Win + WSL on the current stdlib.
**Updated:** 2026-10-10 (registry consumer pass, same session): `xiom.wal`
  0.1.0 (eco-v0.1.121) found on the registry + installed; `tests/pkg/`
  probe green x2 Win + WSL (18 checks incl. two-way interop with our
  reference reader and byte-level codec parity); `src/wal_file.xi` variants
  re-qualified for the cross-package twin; wishlist delta + RUNBOOK row;
  suite 123/123 x2 both platforms, WAL crash x2 both.
**Updated:** 2026-10-10 (M1.2 design, same session): byte-page format v2
  design published -- `docs/BYTE-PAGE-FORMAT-V2.md` + checklist
  `docs/checklists/byte-page-v2.md`: 4096-byte blocks, 40-byte header
  (magic/kind/reserved/generation/page_id/len/CRC32C as 8-byte LE slots),
  two header slots with
  generation-stamped commit, block store over a six-function byte-IO shim
  (O(file) fallbacks today), v1->v2 migration, KAT/corruption/fuzz matrix.
  **S1 (pure codec + KATs) is unblocked on v0.64.2; S2-S4 per the
  checklist.**
**Updated:** 2026-10-10 (M1.2 S1 landed, same session): `src/storage/block.xi`
  (pure byte-page v2 codec: 40-byte header with 8-byte LE slots, payload
  capacity 4056, CRC32C-in-header, strict decode, header-slot cross-check)
  + 4 suite tests (layout KAT, roundtrip/boundaries, corruption matrix,
  header slot) -- **suite 127/127 x2 Win + WSL**; API.md storage section
  documents the module. Next S1 item: fuzz extension; then S2 block store
  over the byte-IO shim.
**Updated:** 2026-10-10 (M1.2 S2 landed, same session): byte-IO shim
  (`src/storage/byte_io.xi`: read_at/write_at/append/file_size/truncate/sync,
  documented O(file) fallbacks, sync no-op) + block store
  (`src/storage/block_store.xi`: two generation-stamped header slots, scan
  directory, put/commit/compact, latest-wins) + probe
  (`tests/probes/probe_block_store.xi`, 26 checks incl. torn active slot
  fallback, both-slots recovery, compaction) + crash harness
  (`scripts/block_crash_test.{ps1,sh}`, four kill states) + fuzz section (f);
  **GREEN x2 Win + WSL** everywhere; suite 128/128 x2 both. S2 done ->
  next S3 (DBFile integration + default flip).
**Updated:** 2026-10-10 (relay archive cleanup): the seven pre-bus relay
  messages moved to `docs/relay-archive/` (README + keeper-doc index);
  SESSION rules/prompt and all cross-references now point at the bus or the
  keeper docs.
**Updated:** 2026-10-10 (relay bus onboarding): joined `xiom-relays`; 11
  open cross-lane items migrated as separate items (ids in section 1);
  SESSION rules updated (pull at session start/before finishing; never edit
  another lane's item); doorbell cron every 3h; C-ORBIT-06 already
  cross-filed by packages.
**Updated:** 2026-10-10 (package relay + order-3 fix, same session): relay
  from the packages lane (xiom.wal + `xiom.btree` 0.1.0 registry-live; no
  FFI asks) processed; fixed the upstream **order-3 B-tree defect** the
  extraction flagged (SPEC 2.3): keyless pass-through chains broke
  predecessor/successor (OOB `keys[-1]`), `fill_child` (OOB merge) and
  min/max (empty terminal leaf -> None); suite regression added (their
  reproducer order 3 / keyspace 16 / seed 777), fuzz rotation now orders
  3/4/5 -- **suite 128/128 x2 Win + WSL, fuzz x2 both, churn order 3 @
  20k/4096 GREEN (remaining 1353)**; wishlist delta carries the fix +
  re-extraction request.
**Project:** embedded database engine for XIOM -- B-Tree, WAL, query engine,
crash recovery; formerly `xiom-db` (renamed `xiom-orbitdb`).

## 0. STATE (2026-10-10)

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
  `0ef8572`); M1.1 session `0ef8572` -> `caf5706` (`5757c78` NodeStore dirty
  tracking (suite 121), wrap `caf5706`); M4.1 session `caf5706` -> `164c971`
  (`4e69822` key-range planner pushdown (suite 123), `35757c8` app-build
  icon + WSL guardrails, wrap `164c971`); hybrid-integration session
  `164c971` -> wrap `d9ef464` (`68c7637` retire dead xiom-core folds +
  C-ORBIT-06 repro, `150c7fd` hybrid probe + cross-store crash harness +
  XV-ORBITDB-01, wrap `d9ef464`).
- **VERSION POLICY (owner): track the LATEST compiler / stdlib / packages.**
  Record exact versions + lane hashes here at every wrap.
  - compiler: **v0.64.2** (released 2026-10-09) -- Windows
    `%LOCALAPPDATA%\xiom.new\bin\xiom.exe`, WSL `~/.local/bin/xiom`;
    `XIOM_RUNTIME_DIR` retired. Re-tested today with **all five C-ORBIT
    workarounds reverted**: suites/crash/fuzz/soak green; **C-ORBIT-01..05
    RESOLVED** (m223/m224/m225/m226/m235). Rollback option if a v0.64.2
    regression appears: v0.64.1 (keep the finding notes in
    `docs/COMPILER-FINDINGS-ORBITDB.md`).
  - stdlib: `E:\xiom-lang\stdlib` @ `7e513f9` (2026-10-10; handoff snapshot
    25) = `/mnt/e/xiom-lang/stdlib`. **stdlib-v0.64.3 RELEASED + registry
    live** (stdlib lane version, built with compiler v0.64.2; sha256
    `775496c0...`; the compiler stays v0.64.2 -- our pin is unchanged). Two
    ORBITDB rows RESOLVED earlier: `str_split`/`read_file_lines` are linear
    and a trailing CR is stripped per line (both citing our relay).
  - compiler lane @ `da7798da` (m252 catalog-body check cache; post-v0.64.2
    tag work continues); packages lane @ `47202b72` (xiom.durable port wrap;
    152/152 x2).
  - `xiom doctor` shows 2 environment warnings (bundled stdlib older than
    compiler; stale second binary on PATH) -- lane noise: `scripts/dev-env.*`
    sets `XIOM_COMPILER`/`XIOM_STDLIB` explicitly.
- **Green evidence (exact commands; all GREEN x2 Windows + WSL unless noted):**
  - Suite: `scripts/run.ps1 tests/test_conformance.xi -TimeoutSec 300` ->
    **123/123, exit 0** (x2 Win + WSL; v0.64.2 with **all C-ORBIT workarounds
    reverted**). Composition: 93 base + 2 churn +
    CRC32C KAT + 3 tuple-codec + 2 FSM + 2 page-file + 1 page-log + 15 db-file
    (roundtrip, checkpoint, churn, query/range, incremental, uncommitted
    generation, policy, compaction, txn commit, txn abort/guards, dangling
    txn, path validation, checked open, stale handle, dirty flush) + 2
    buffer-pool (clock order, pinning/reject) + 2 planner (plan kinds,
    200-case property vs brute force).
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
  - Hybrid (new): `scripts/hybrid_crash_test.{ps1,sh}` -- one writer drives
    BOTH stores (ORBITDB rows + XVECTOR vectors), hard kill, torn row tail,
    reopen -> repair -> 100% join integrity; second verify idempotent
    (`repaired=0`). GREEN x2 Win + WSL. `tests/hybrid/probe_hybrid.xi`
    `full` mode: 36 checks (join integrity, brute-force exact top-k equality,
    delete pipeline, reopen bit-equality, WAL prefix + torn tail) x2 Win +
    WSL. `tests/hybrid/repro_chain.xi` is the XV-ORBITDB-01 evidence run.
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
  - Planner (new, M4.1): `query_key_range(q, low, high)` additive key bounds;
    plan kinds PointLookup/IndexRange/FullScan with bounds-aware
    `estimated_rows`; `execute_plan` scans `btree_range_query` then applies
    value conditions/offset/limit; `db_file_query` is planned; pinned by a
    200-case seeded property test vs brute force.
  - Production plan (new): `docs/PRODUCTION-PLAN.md` (mission, architecture
    target, workstreams M1-M8, gates P-alpha -> 1.0, benchmark targets,
    release signal) + `docs/checklists/production-release.md`; linked from
    README/ROADMAP/readiness. The owner sets up the public release when the
    release signal fires, and the owner's benchmark suite becomes the
    release gate.
  - App build (new): `scripts/build.ps1` compiles a source into an app binary
    and embeds `assets/orbitdb.ico` via `--icon` (verified on v0.64.2 with
    llvm-rc); `scripts/build.sh` is the no-icon Linux/WSL twin. M6 checklist
    line ticked.
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
  - Hybrid integration (new): `tests/hybrid/` -- source-level composition
    (`tests/hybrid/xiom.toml` source roots: our `src` + `xiom-xvector/src`),
    `probe_hybrid.xi` (full/writer/verify: rowver/embver version slots,
    deterministic embeddings, consumer repair pass, join + brute-force
    checks, delete pipeline, reopen bit-equality, WAL prefix + torn tail) and
    `scripts/hybrid_crash_test.{ps1,sh}`. XVECTOR's reply processed; cross-ask
    answers + finding XV-ORBITDB-01 in `docs/XVECTOR-INTEGRATION.md` section 7
    (+ the owner-relay response, archived:
    `docs/relay-archive/RELAY-XVECTOR-ORBITDB.md`).
  - Foundation cleanup (new): the dead `xiom.core.error` fold
    (`db_error_from_core`) and `xiom.core.config` projection
    (`database_config_from_core`) are RETIRED -- phantom imports the checker
    silently tolerated; composition exposed them, C-ORBIT-06 filed with
    `docs/repro/phantom-core-import/`; SPEC/ARCHITECTURE/API/error-catalog
    coupled.
  - Index-of-record: `docs/PRODUCTION-READINESS.md` **69.5/100 (~70%)**,
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
  - **Checkpointing is incremental and dirty-only** (M1.1): unchanged nodes
    are skipped via NodeStore flags; the dirty set is encoded once per
    checkpoint and the page log is read twice per call. The tree stays fully
    resident: lazy load + a bounded node cache (M1.1b) are deferred until the
    stdlib exposes random-access page reads (byte IO/seek) -- with the text
    page codec every lazy miss would rescan the whole page file (O(n^2)).
    Truncate keeps the Checkpoint anchor -- NEVER truncate to empty (next_lsn
    lives in the segment). Snapshot path is `<wal>.snap`; dedup on load is
    quadratic in log entries (bounded by compaction).
  - `DBFile` (put/get/delete/size/flush/last_lsn/checkpoint/range/query/txn)
    and the in-memory `Database` facade are still separate; `DBFile`
    transactions are single-active with no isolation/MVCC (readers see
    committed state only).
  - Values are int-only today; secondary indexes and ORDER/LIMIT execution
    are pending (M4.2), typed values pending (M5.1).
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
  - XV-ORBITDB-01 (XVECTOR side): chained persist/load is LOSSY -- a
    recovered engine's compacted WAL resumes LSNs while `wal_load` requires
    the first LSN to be 1, so re-persisting reloads EMPTY (vectors vanish
    while row-side version slots stay advanced). The hybrid probe works
    around it in `persist_recovered` (re-LSN through a fresh writer); drop
    the workaround once XVECTOR relaxes the loader (relay sent).
  - Hybrid composition needs the sibling `xiom-xvector` checkout at
    `E:\xiom-projects\xiom-xvector` (relative paths in `tests/hybrid/xiom.toml`);
    the probe is source-level until both packages publish (M6/F4).
  - Multi-handle safety is optimistic: the `wal_bytes` stale-write guard
    refuses lagging writers but is not a lock (external appends are detected
    only on the next write); no MVCC -- see `docs/ISOLATION.md`.
  - B-tree nodes are append-only (no free list); `btree_to_vec` is
    value-only.
- **Relay status:** cross-lane coordination runs on the **xiom-relays bus**
  (section 1; all open items migrated 2026-10-10, ids listed there; first
  inbound processed the same day: packages' order-3 bug acked+fixed). Keeper
  docs: `docs/COMPILER-FINDINGS-ORBITDB.md` records **C-ORBIT-01..05
  RESOLVED on v0.64.2** (m223/m224/m225/m226/m235; one consumer-scope caveat
  on m225). Pre-bus relay messages are archived under `docs/relay-archive/`
  (historical only). Stdlib wishlist: the
  `str_split`/`read_file_lines` quadratic **and** the CR-strip row are
  RESOLVED (both citing our relay); fsync (stubs), append-handle, truncate,
  byte-IO, tail-check remain open. Package docs carry the `xiom.wal`/
  `xiom.btree` decisions.
  Consumer handshakes (new): PULSE (`docs/PULSE-INTEGRATION.md`, answering
  `xiom-pulse/docs/ORBITDB-RELAY-PULSE.md`) -- PULSE builds
  `probe_pkg_orbitdb` and uses us as its 0.3 embedded/relational driver
  (`open/exec/query/tx`); XVECTOR (`docs/XVECTOR-INTEGRATION.md`; reply
  archived) -- reply RECEIVED and processed
  (`xiom-xvector/docs/ORBITDB-INTEGRATION.md`, pin `de1db14`); the hybrid
  probe + crash harness stand and are green (our section 7 answers their
  cross-asks); finding **XV-ORBITDB-01** relayed back to them (chained
  persist/load goes empty; the probe carries a documented re-LSN
  workaround). New compiler finding **C-ORBIT-06** filed (phantom imports
  silently accepted; C-ORBIT-01..05 stay RESOLVED).
- **Next action (priority order, per `docs/PRODUCTION-PLAN.md` section 13):**
  1. **M1.2 byte-page format v2 -- design + S1 + S2 DONE**; next S3
     (`DatabaseConfig.page_format` v1/v2, v1->v2 migration, DBFile
     integration behind the flag, full matrix, default flip), then S4
     (stdlib fixed-size IO + fsync swap).
  2. Order-3 B-tree fix landed (upstream of `xiom.btree` SPEC 2.3) -- next
     `xiom.btree` release re-extracts; run the consumer pass then.
  3. **M4.2 secondary indexes** (catalog `IndexDef`, index-vs-model fuzz) +
     ORDER/LIMIT execution.
  4. **M5.1 typed values v2** (type-tagged tuples; text at least).
  5. **M2.1 fsync wiring** when stdlib lands; **M1.1b** lazy load once
     random-access page reads exist; MVCC per M3; keep readiness + keeper
     docs current; commit signed at every step.
  6. **Hybrid regression guard:** re-run `scripts/hybrid_crash_test.*` +
     probe `full` x2 both platforms at every wrap, and whenever the XVECTOR
     pin moves; drop the `persist_recovered` workaround once XV-ORBITDB-01
     is fixed upstream.

## 1. Consumer-lane rules (non-negotiable)

- **Never edit** `E:\xiom-lang\stdlib`, `E:\xiom-lang\xiom`,
  `E:\xiom-packages\packages`. Record lane HEADs each wrap:
  `git -C <lane> log -1 --format="%h %cI %s"`.
- **Coordination bus (2026-10-10):** all cross-lane messages go through the
  private `xiom-relays` repo at `E:\xiom-lang\xiom-relays` (README + PROTOCOL
  there; `tools/relay.py`, stdlib-only Python). **Pull at session start and
  before finishing any task**: `git -C E:\xiom-lang\xiom-relays pull --ff-only`
  then `python tools/relay.py view --lane orbitdb`, and process items
  addressed to this lane (ack -> fix -> verify per protocol). **Never edit
  another lane's item; open a new item instead.** Doorbell: a recurring
  session check every 3h (cron) pulls the bus, processes the orbitdb queue
  and updates statuses.
- **Our open bus items (migrated 2026-10-10):** owner ack
  `REL-20261010-1550-orbitdb`; compiler `REL-20261010-1550-orbitdb-2`
  (standalone-check quirk; C-ORBIT-06 itself is packages' cross-file
  `REL-20261010-1549-packages-4`); stdlib `-3` fsync, `-4` append handle,
  `-5` truncate, `-6` byte-IO random access, `-7` append+repair, `-8` tail
  check; packages `-9` btree re-extract, `-10` variant qualification;
  xvector `-11` (XV-ORBITDB-01).
- Report upstream through the xiom-relays bus (section 1) + SESSION rows;
  the owner handles human gates. Read other lanes' bus items before filing
  (reference their ids).
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
- WSL guardrail (2026-10-09 memory incident): the WSL VM is shared with other
  lanes (PULSE was compiling/running in it; the VM restarted twice under
  load). Before chained WSL harness runs check `ps aux --sort=-rss | head`
  and `free -m`; run at most ONE heavy harness per command; pause and retry
  when another lane is active. No runaway process from this lane was found
  (checked Windows + WSL: only the interrupted runs' writers, cleared by the
  restarts).

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
- **Expected external inputs (check at the start of every session):**
  - `xiom-xvector/docs/ORBITDB-INTEGRATION.md` (or a newer xvector pin) --
    PROCESSED 2026-10-10: the hybrid probe stands (green x2); next, watch
    for their XV-ORBITDB-01 fix (chained persist/load) and re-run the probe
    when the xvector pin moves.
  - `xiom-pulse` `probe_pkg_orbitdb` and/or an updated
    `ORBITDB-RELAY-PULSE.md` -- PULSE's probe results; treat as acceptance,
    fix reds with minimal repros through the relay.
  - A newer COMPILER archive (v0.64.3+): run the full bump procedure
    (`docs/COMPILER-FINDINGS-ORBITDB.md`) -- seven repro bundles unchanged +
    suite x2 + crash/fuzz/soak -- BEFORE other work. (stdlib-v0.64.3 is the
    stdlib lane's release, built with compiler v0.64.2: no compiler bump;
    the shared stdlib checkout moving is re-verified by suite x2 at wrap.)
  - The owner's benchmark-suite contract: build the ORBITDB adapter when it
    lands (`docs/PRODUCTION-PLAN.md` section 10).

## 4. Relay documents (bus is live; keep keeper docs current every wrap)

- `docs/COMPILER-FINDINGS-ORBITDB.md` (evidence ledger; C-ORBIT-01..05
  RESOLVED; C-ORBIT-06 on the bus as `REL-20261010-1549-packages-4`;
  standalone-check quirk `REL-20261010-1550-orbitdb-2`; repro bundles under
  `docs/repro/`).
- `docs/XVECTOR-INTEGRATION.md` (hybrid contract; reply processed; section 7
  answers their cross-asks + XV-ORBITDB-01, bus `-11`).
- `docs/STDLIB-WISHLIST-ORBITDB.md` / `docs/PACKAGE-WISHLIST-ORBITDB.md`
  (resolved history + deltas; open rows on the bus `-3..-8` / `-9..-10`).
- `docs/PULSE-INTEGRATION.md` (PULSE contract) and
  `docs/PRODUCTION-READINESS.md` (scoreboard -- recompute + changelog line
  every wrap).
- `docs/relay-archive/` -- pre-bus relay messages (historical only; live
  coordination is the bus).

## 5. Paste prompt for the next ORBITDB session

```
You are the ORBITDB session for E:\xiom-projects\xiom-orbitdb -- the
embedded XIOM database engine (B-Tree, WAL, query engine, crash recovery;
formerly xiom-db). Read SESSION.md first, then README/SPEC/ARCHITECTURE/
ROADMAP/AUDIT and docs/ (keeper docs + PRODUCTION-READINESS included; read
docs/PRODUCTION-PLAN.md for the strategy, workstreams and slice order).
Consumer lane: never edit E:\xiom-lang\stdlib, E:\xiom-lang\xiom,
E:\xiom-packages\packages. Repo PRIVATE; no pushes without owner approval.
Identity "Lefteris Notas <lefterisnotas@gmail.com>"; conventional commits,
DCO sign-off (git commit -s). Cross-lane coordination: the xiom-relays bus
(E:\xiom-lang\xiom-relays) -- git pull --ff-only at session start and before
finishing any task, then python tools/relay.py view --lane orbitdb and
process items to this lane; never edit another lane's item (open a new one);
owner relays human gates.

TOOLCHAIN (latest-tracking): compiler v0.64.2 Windows + WSL; stdlib
E:\xiom-lang\stdlib; XIOM_RUNTIME_DIR retired. Dot-source scripts\dev-env.ps1
(or scripts/dev-env.sh); run everything via scripts\run.ps1 / run.sh with a
-TimeoutSec watchdog and exit-code gate. Native .sh twins must stay LF.
WSL: the default distro is docker-desktop (no bash) -- run via
`wsl.exe -d Ubuntu bash -lc '...'`; the VM is shared with other lanes --
check `ps`/`free` and run at most ONE heavy harness per command.
Evidence rules: green suites x2, crash harnesses x2, soak long paths, keep
probe-logs out of commits (gitignored).
Release signal: when the production plan's gates pass (P-rc), tell the owner
explicitly "ORBITDB is ready for public release" -- the owner then sets up
the public repo/CI/registry and adds ORBITDB to the benchmark suite.
WATCH each session: XVECTOR's next pin / fix for XV-ORBITDB-01 (the hybrid
probe stands; re-run it when their pin moves), PULSE's `probe_pkg_orbitdb`
results, and any newer COMPILER archive (re-test the seven repro bundles +
suite first). (XVECTOR's integration reply was processed 2026-10-10.)

CURRENT STATE: v0.64.2 pin; all C-ORBIT compiler workarounds REVERTED and the
suite is green on the native forms -- conformance 128/128 x2 Win + WSL (see
the findings file for the one consumer-qualification caveat); db_crash five
scenarios (WAL-only, snapshot-only, snapshot+tail, uncommitted txn discarded,
committed txn recovered) x2 Win + WSL, each recovery followed by qverify
(range + value-filter queries; 25 checks); hybrid ORBITDB <-> XVECTOR probe
`tests/hybrid/probe_hybrid.xi` (36 checks: join integrity, brute-force
top-k, delete pipeline, reopen bit-equality, prefix/torn tail) +
`scripts/hybrid_crash_test.{ps1,sh}` (hard-kill both stores -> repair ->
100% join integrity, idempotent) x2 Win + WSL; C-ORBIT-06 OPEN (phantom
imports -- never keep an unresolvable `use`); XV-ORBITDB-01 OPEN on the
XVECTOR side (chained persist/load goes empty; the probe works around it in
`persist_recovered`); fuzz/property harness
`scripts/fuzz.{ps1,sh}` (seeds=4 ops/seed=4000) x2 Win + WSL; policy soak
2000 keys / 9 checkpoints x2 Win + WSL; 20k-record WAL replay ~9.9 s (linear
stdlib); bench harness live; app build `scripts/build.ps1` embeds
assets/orbitdb.ico (--icon verified); readiness
69.5/100 (docs/PRODUCTION-READINESS.md -- recompute + changelog every wrap);
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
dirty-only checkpoint flush (M1.1); key-range planner pushdown +
query_key_range, point/range plans (M4.1); byte-page format v2 S1+S2
(codec `src/storage/block.xi`; shim `byte_io.xi`; store
`src/storage/block_store.xi` with 26-check probe + 4-state crash harness +
fuzz; design `docs/BYTE-PAGE-FORMAT-V2.md`); B-tree order-3
empty-chain fix (predecessor/successor, fill_child, min/max; suite
regression + fuzz orders 3/4/5)). Known limits: no fsync
(process-crash safe only); replay is linear now but file IO is O(n) per read
(no random access); checkpoint encodes only dirty nodes (M1.1) but the tree
stays fully resident (lazy load/bounded cache need random-access page reads);
transactions single-active, no MVCC (single-writer model in
docs/ISOLATION.md); buffer pool in-memory only (pager seam C3 pending);
fuzz runs per wrap (CI cadence awaits F3).

TASK ORDER (highest value first; full plan docs/PRODUCTION-PLAN.md sec. 13):
1. M1.2 byte-page format v2: design + S1 + S2 DONE (block codec, byte-IO
   shim, block store, probe, crash harness, fuzz -- all x2 both platforms);
   next S3 (DBFile integration behind DatabaseConfig.page_format + v1->v2
   migration + default flip), S4 (stdlib byte IO + fsync swap).
2. Order-3 B-tree fix is upstream; when the fixed `xiom.btree` package
   releases, re-extract is theirs -- run our two-way consumer pass then.
3. M4.2 secondary indexes (catalog IndexDef) + ORDER/LIMIT execution.
4. M5.1 typed values v2 (type-tagged tuples; text at least).
5. M2.1 fsync wiring when stdlib lands; M1.1b lazy load once random-access
   page reads exist; MVCC per M3; keep the hybrid harness green at every
   wrap (and when the XVECTOR pin moves); keep SESSION.md STATE, the bus
   items and PRODUCTION-READINESS updated at every wrap; commit signed per
   step.

DISCIPLINE (v0.64.2; C-ORBIT workarounds DROPPED -- see COMPILER-FINDINGS):
- Never keep an unresolvable `use` or an undeclared type (C-ORBIT-06): it
  type-checks standalone with bogus W004s, then hard-fails once any module in
  the program declares a same-named type.
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
