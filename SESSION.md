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
**Updated:** 2026-10-11 (M2.1 first half -- COMPUTE CHECKPOINT, handoff): the
  durability API + fault injector are IN CODE and smoke-green (suite 134/134
  x1 Win, v0.64.3): `src/storage/fault.xi` (env-armed Nth-op injector:
  kill/partial/skip/syncfail; `fault_reset`; wired into `byte_io`),
  `src/storage/byte_io.xi` gates, and the engine's `durability` (0 normal /
  1 immediate default), `two_phase`, `failed` latch with
  `db_file_set_durability`/`_set_two_phase`/`_failed`,
  `db_file_commit_sync` on put/delete/txn-commit, 2PC WAL-flush before a
  checkpoint publishes, post-checkpoint WAL+snapshot flush, and latch checks
  on every writer. API.md rows added.
  **REMAINING (FIRST TASK NEXT SESSION):** (1) suite tests: durability API
  defaults/setters + a syncfail latch test using `env.set_var` +
  `fault_reset` (put -> false + `db_file_failed`; writers refuse; reopen
  recovers the record); (2) `tests/probes/probe_fault_sync.xi` scenarios:
  put-latch, checkpoint-2PC pre-sync failure (snapshot file size unchanged),
  partial-write page recovery on the block store; (3) suite/fuzz x2 + probe
  x2 Win + WSL; (4) RUNBOOK row + REFERENCE-STUDY action-1 status +
  readiness changelog; commit. Companion design: the reference study below
  (`docs/REFERENCE-STUDY.md`) is the rationale.
**Updated:** 2026-10-11 (M2.1 first half FINISHED, next session): durability
  API + fault injector are evidence-complete: 2 suite tests (durability
  defaults/setters + reopen reset; syncfail latch + reopen recovery) and
  `tests/probes/probe_fault_sync.xi` (49 checks: put/delete latch,
  checkpoint-2PC pre-sync failure with the snapshot file untouched + the WAL
  untruncated, block-store partial writes: torn append/update + torn header
  fallback). **Suite 136/136 x2 Win + WSL**; probe GREEN x2 both; fuzz OK x2
  both. Filed **C-ORBIT-07** (a consumer fn silently hijacks a module-private
  same-named call; the probe's `arm` was hijacked by `fault.xi`'s private
  `arm()`; renamed to `probe_arm`; bundle `docs/repro/consumer-fn-hijack/`,
  bus `REL-20261011-1124-orbitdb`). Docs: RUNBOOK probe/env rows + gotcha,
  REFERENCE-STUDY action-1 DONE, readiness changelog (71.5, no score change),
  API.md flush-row dedup. **Hybrid wrap guard RESOLVED (doorbell):** the 113
  T001s were OUR composition manifest missing xvector's package deps --
  `xiom.vectors` (their 2026-10-10 adoption; every consumer module imports
  it) plus rate/http; xvector diagnosed it precisely (their tree is green on
  v0.64.3; not a toolchain-axis issue); mirrored their `[dependencies]`
  block into `tests/hybrid/xiom.toml` (wal/metrics/rate/http/vectors) and
  probe_hybrid `full` is GREEN (36 checks) again. My INFO
  `REL-20261011-1127-orbitdb` verified+closed; xvector's reply
  `REL-20261011-1146` acked (reporter closes). Also adopted the ops hygiene
  rule `REL-20261011-1134-ops`: never delete/downgrade shared toolchain
  homes (this lane pins its own shadow install via dev-env); destructive
  tests need an isolated XIOM_HOME + a `to: all` announcement. WSL
  follow-up: the WSL shared home was still missing `xiom-vectors`/`xiom-wal`
  from the wipe (Windows had them -- the platform split); plain additive
  reinstall (`xiom pkg install ...@0.1.0`), then WSL probe + crash GREEN;
  ops FYI `REL-20261011-1229-orbitdb`. **Final hybrid evidence on the wrap
  tree: probe `full` x2 Win + x2 WSL (fresh paths -- `full` does not clean
  up; a same-path reuse on WSL tripped a contract), crash harness x2 Win +
  x2 WSL (5/5, idempotent); RUNBOOK gotcha added.** Next per task
  order: M5.1 typed values v2 (codec landed this session, evidence in
  progress).
**Updated:** 2026-10-11 (M5.1 codec, same session): typed values v2 at the
  codec layer -- `TValue` (null/int/float/text/blob) + tuple codec version 2
  in `src/storage/tuple.xi` (tagged fields, u32 lengths, strict
  whole-buffer decode, bit-exact f64 incl. NaN, byte-exact UTF-8 text); 4
  new suite tests (byte KAT; roundtrip all kinds; reject matrix incl.
  cross-version isolation; budget) -- suite **140/140**; fuzz section (h)
  over all kinds (encode/decode/per-kind model + visible-mutation rule);
  FORMATS 5A (typed value model + migration notes); API.md rows; plan item
  5 + M5 checklist updated (engine integration = the next slice). v1 stays
  frozen in both directions (version byte discriminates). Found while
  building it: v0.64.3 miscompiles a tuple CONTAINING AN ENUM
  (`Result[(TValue, Int)]` -- the `Tuple__TValue__Int` codegen warning;
  match arms silently skipped) and `[8]UInt8` element `as Int` casts
  sign-extend (0xF8 -> -8); worked around in our code (`DbResult[TValue]`
  + `tuple2_value_len` advance; `& 0xFF` mask) + filed as C-ORBIT-08 with a
  repro bundle (bus `REL-20261011-1219-orbitdb`;
  `docs/repro/enum-tuple-codegen/`). Evidence: suite **140/140 x2 Win +
  WSL**, fuzz (h) OK x2 both. Next: schema-driven storage (engine rows
  store/query typed values; the v1/v2 flip is a per-container decision like
  `page_format` 2).
**Updated:** 2026-10-11 (M5.2 schema layer, same session): schema-driven
  rows -- `schema_row` in `src/catalog/schema_row.xi`: ColumnType<->TValue
  mapping (Int / Float / Bool=0|1 / String / Bytes), nullability + arity +
  pk-is-VInt validation, `schema_row_key/encode/decode` with id/pk
  consistency (Corruption) and schema-drift taxonomy, consumer-safe error
  codes; `column_type_code` added to `schema` so consumers never
  pattern-match an imported enum (m225/C-ORBIT-07 hygiene). 4 suite tests
  (**144/144**) + fuzz section (i) (random schemas/rows vs model + every
  single-column violation must be rejected). The engine **persistence
  container decision** is written down: `docs/TYPED-VALUES-STORAGE.md`
  (chosen: entry payloads in the nodes; WAL rides the EXISTING
  tagged-payload records with subtype 1; snapshot node pages v3 with
  auto-detect; int users stay byte-identical). Next: M5.3 engine
  integration (`db_file_put_typed`/`get_typed`, replay, checkpoint v3,
  crash + fuzz per the doc's evidence ladder), then typed-column
  query/index.
**Updated:** 2026-10-11 (user shell v0, owner ask): `apps/orbitdb_cli.xi` --
  the executable face of the engine. Build: `scripts\build.ps1
  apps\orbitdb_cli.xi -Out out\orbitdb.exe` (icon embedded; WSL twin
  `scripts/build.sh apps/orbitdb_cli.xi out/orbitdb-cli`). REPL:
  put/get/del/range/count/ckpt/bench/info/recover/kill/help/quit; `kill`
  exits WITHOUT cleanup (crash simulation). Verified as a user flow on both
  platforms: graceful session + checkpoint + `recover`, kill -> restart WAL
  replay (rows recovered), bench 2000 -> ~1.1k ops/s. README gained a
  "Try it (interactive shell)" section; RUNBOOK gained the row (suite
  count fixed 127 -> 144). Typed-row commands ride M5.3. Stage answer for
  "proper user test": **NOW** for the int-keyed engine (this binary);
  typed rows after M5.3; embeddable + registry after M6 + the release
  gate.
**Updated:** 2026-10-11 (M5.3 typed rows in the engine, same session):
  the container contract is IMPLEMENTED. Tree: parallel
  `BTreeNode.payloads` (every split/merge/borrow/delete mirror, incl. the
  predecessor/successor substitution now carrying payloads via a
  `NodeEntry` struct -- no enum-in-tuple, C-ORBIT-08). WAL: typed writes
  use the existing tagged records (subtype 1 + row bytes; `value` mirrors
  the key); replay applies payloads (incl. crafted txn windows via TxOp
  payload buffering) and fails closed on unknown subtypes / non-byte
  elements. Snapshot: node page version 2 payload section (u64 LE framing;
  v1 pages decode with empty payloads). API: `db_file_put_typed`/
  `db_file_get_typed`/`db_file_typed_payload_max` (bytes 0..255 enforced,
  budget refused up front, non-transactional in S3). Evidence: suite
  **149/149** (5 new tests), fuzz (j) (per-op verification across
  checkpoints/reopens), fault scenario E (typed latch + payload recovery),
  **legacy artifacts verified** (pre-change v1-node-page snapshots load
  unchanged; 2994-row store + write + migration-on-write). CLI grew
  `putrow`/`getrow` (typed rows in the shell). **E4 awarded 2/2 ->
  readiness 73.5.** Remaining M5 work: typed-column query/index
  predicates (S4).
**Updated:** 2026-10-11 (M5-S4 typed predicates, same session): M5 is
  COMPLETE. `tuple2_compare` defines the typed total order (Null < numeric
  (Int/Float numeric; VInt(1) == VFloat(1.0)) < Text bytewise < Blob
  element-wise; NaN first + self-equal); `TypedQuery`/`TypedCond` +
  `db_file_query_typed` return matching pks in key order (conditions ANDed,
  `col = -1` = row id, int rows + undecodable payloads never match,
  offset/limit on matches). Evidence: 3 suite tests (**152/152**) + fuzz
  (k) vs an INDEPENDENT model (4 seeds x 150 iters; model values in natural
  domains, comparator re-implemented; per-op verification across
  checkpoints/reopens); CLI `qrow <col> <op> <literal>` verified on Windows
  + WSL. Docs: API rows, TYPED-VALUES-STORAGE landed-details, plan item 5
  marked complete. Typed secondary indexes are an optional follow-on (not
  required by the M5 gates). Readiness holds at 73.5 (extends the awarded
  E4 evidence).
**Updated:** 2026-10-11 (reference study, owner grant): cloned + studied
  bbolt (MIT), redb (MIT/Apache-2.0) and SQLite (public domain) under
  `E:\repos`; `docs/REFERENCE-STUDY.md` maps their load-bearing mechanisms
  (single-commit-marker discipline + checksum chains, two-slot headers,
  pending-frees by generation, snapshot/savepoint minimal subset, PASSIVE
  checkpoint backfill accounting, durability modes incl. 2PC, buffered-write
  fault injection) to our slices with adopt/adapt/avoid decisions and an
  ordered next-action list -- **M2.1 first half (durability API + `byte_io`
  fault injector, testable with the sync stub) leads**.
**Updated:** 2026-10-10 (doorbell 21:00Z): queue clear (packages-8 awaits
  their verification); compiler root-caused `REL-20261010-1802-orbitdb`
  (C-ORBIT-06 with-twin): the packages pass reproduces only in the
  bare-filename invocation (m255 checker fix `13115d64`, unpushed) --
  re-verify the phantom bundle on the NEXT compiler archive; twin half
  open on v0.64.3, phantom core ask queued for v0.64.4. Findings file
  updated; no other orbitdb items.
**Updated:** 2026-10-10 (M4.2, same session): secondary indexes + ORDER/LIMIT
  -- `src/secondary_index.xi` ((value, pk) entries; binary-search probes;
  stable pair sorts), maintained by put/update/delete/txn-commit; catalog
  `IndexDef` tie-in (`db_file_create_index_from_def`); planner `IndexValue`
  plan (first usable condition bounds the probe; key bounds keep precedence)
  + executor re-filtering conditions with order/offset/limit; `query_order`
  (key/value asc/desc, ties key-stable). **Suite 134/134 x2 Win + WSL**;
  fuzz section (g) query+index vs brute-force model x2 both. Readiness
  **E3 0 -> 1** (durable page-backed indexes stay with A5): 71.5.
**Updated:** 2026-10-10 (compiler v0.64.3 bump, same session): release check
  processed -- v0.64.3 released (pin `ab894b47`; release-check
  `compiler-compiler-v0.64.3`); Windows pin moved to the shadow install
  `xiom.new.0643` (dev-env.ps1), WSL canonical already 0.64.3 (dev-env.sh
  comment). Bump battery GREEN: seven C-ORBIT bundles unchanged and matching
  the v0.64.2 matrix; suite 130/130 x2 Win + WSL; WAL crash 4/4 x2; db_crash
  25/25; block crash 8/8; fuzz + 2000-key soak both platforms. Verdicts:
  release-check row `-2` filled (still open, same T001 class); C-ORBIT-06
  with-twin STILL red on v0.64.3 (packages' verdict contradicted) ->
  correction `REL-20261010-1802-orbitdb`; plain-phantom silent acceptance
  unchanged.
**Updated:** 2026-10-10 (M1.2 S3 integration, same session): the snapshot
  can be written as v2 byte blocks -- `db_file_open_cfg` /
  `db_file_open_checked_cfg` (`page_format` 1 default | 2), reads
  auto-detect by first byte, `snap_flush_v2` (dirty-only append + header
  commit; v1 file -> full rewrite = migration-on-write), `snap_compact`
  handles a v1 handle on a v2 file, `db_file_migrate_snapshot` (idempotent);
  suite **130/130 x2 Win + WSL**, **db_crash matrix 25/25 x2 both in v2
  mode**; default stays v1 -- the flip moves to S4 (single full checkpoint
  at N=2000 is minutes-scale on the O(file) shim). Docs: FORMATS pointer,
  API rows, RUNBOOK env line.
**Updated:** 2026-10-10 (bus verifications, same session): `REL-20261010-1550-orbitdb-10`
  (packages enum-variant qualification) verified+closed against the shipped
  source; `-11` (XV-ORBITDB-01) verified against xvector `3c36f34`
  (`repro_chain` GREEN, `load2=3`) and closed -- the `persist_recovered`
  workaround is REMOVED from the hybrid probe (plain `wal_persist`; full +
  crash GREEN x2 Win + WSL); `tests/hybrid/xiom.toml` now mirrors the
  sibling's `xiom.wal`/`xiom.metrics` registry deps (its tree grew them).
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
  - compiler: **v0.64.3** (released 2026-10-10, pin `ab894b47`; m243-m246,
    m248, m249+bridge, m252) -- Windows **shadow install**
    `%LOCALAPPDATA%\xiom.new.0643\bin\xiom.exe` (the canonical
    `xiom.new` stays v0.64.2 for the other lanes; swap is
    owner/ops-coordinated), WSL `~/.local/bin/xiom` (canonical, already
    0.64.3). Bump re-test 2026-10-10: seven C-ORBIT bundles unchanged/green,
    suite 130/130 x2 Win + WSL, WAL crash 4/4 x2, db_crash 25/25 Win, block
    crash 8/8 Win, fuzz + 2000-key soak OK both platforms; C-ORBIT-06
    with-twin still red on v0.64.3 (correction
    `REL-20261010-1802-orbitdb`), release-check row `-2` still open.
    Rollback option: v0.64.2 (`xiom.new`; findings file keeps the notes).
  - Lane heads at the 2026-10-11 M5.3 wrap: stdlib `4fbc226`,
    xvector `03a90bc`, packages `68569e9c`, relays `428a47f` (all moved
    during the day; re-check at the next wrap -- release rows on the bus are
    the contract).
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
    **136/136, exit 0** (x2 Win + WSL; v0.64.3 with **all C-ORBIT workarounds
    reverted**). Composition: 93 base + 2 churn +
    CRC32C KAT + 3 tuple-codec + 2 FSM + 2 page-file + 1 page-log + 15 db-file
    (roundtrip, checkpoint, churn, query/range, incremental, uncommitted
    generation, policy, compaction, txn commit, txn abort/guards, dangling
    txn, path validation, checked open, stale handle, dirty flush) + 2
    durability (API defaults/setters + reopen reset; syncfail latch + reopen
    recovery) + 2
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
  - Fault injection (new, M2.1 first half): `tests/probes/probe_fault_sync.xi`
    -- 49 checks (put/delete latch + reopen recovery; checkpoint-2PC
    pre-sync failure with the snapshot file untouched and the WAL
    untruncated; block-store torn page append/update + torn header-slot
    fallback) via the env-armed `ORBITDB_FAULT_*` layer
    (`src/storage/fault.xi`) wired into the `byte_io` gates; GREEN x2 Win +
    WSL. Consumer helpers must avoid same-named functions in imported
    modules (C-ORBIT-07: `arm` -> `probe_arm`; bundle
    `docs/repro/consumer-fn-hijack/`, bus `REL-20261011-1124-orbitdb`).
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
  - Durability API + fault injector (new, M2.1 first half -- evidence
    complete): DBFile `durability` (0 normal / 1 immediate default) +
    `two_phase` + `failed` latch (`db_file_set_durability`/`_set_two_phase`/
    `_durability`/`_two_phase`/`_failed`), ack-time `db_file_commit_sync` on
    put/delete/txn-commit, 2PC WAL-flush before a checkpoint publishes,
    post-checkpoint WAL+snapshot flush, latch checks on every writer;
    `src/storage/fault.xi` env-armed Nth-op injector (kill/partial/skip/
    syncfail, one fire per arming) wired into the `byte_io` gates. Evidence:
    2 suite tests + `probe_fault_sync.xi` (49 checks) x2 Win + WSL.
  - Typed values v2 (new, M5.1 codec): `TValue` (null/int/float/text/blob) +
    tuple codec version 2 in `src/storage/tuple.xi` (tagged fields, u32
    lengths, strict whole-buffer decode, bit-exact f64 incl. NaN, byte-exact
    UTF-8 text); v1 frozen (the version byte discriminates both ways);
    evidence: 4 suite tests + fuzz section (h) x2 Win + WSL; FORMATS 5A
    (typed value model + migration notes). Engine integration
    (schema-driven storage) is the next slice; two v0.64.3 codegen traps
    worked around in-tree (C-ORBIT-08: enum-in-tuple miscompile; fixed-array
    UInt8 cast sign-extension).
  - Schema-driven rows (new, M5.2): `src/catalog/schema_row.xi` -- kind
    mapping (Int/Float/Bool 0|1/String/Bytes), validation (arity,
    nullability, pk-is-VInt), key/encode/decode + id/pk consistency, error
    codes; evidence: 4 suite tests + fuzz section (i); the
    engine persistence contract (entry payloads, WAL subtype-1 tagged
    records, snapshot node pages v2) is `docs/TYPED-VALUES-STORAGE.md`
    (S3 LANDED).
  - Typed rows in the engine (new, M5.3): `BTreeNode.payloads` parallel
    vector (all tree moves mirrored); WAL tagged records subtype 1; node
    page version 2 payload section (both containers, v1 pages load with
    empty payloads); `db_file_put_typed`/`get_typed` +
    `db_file_typed_payload_max` (byte 0..255 + budget enforced;
    non-transactional in S3; typed writes drop stale int index entries).
    Evidence: 5 suite tests (149 total) + fuzz (j) + fault E + legacy
    artifact load/migration verification; CLI `putrow`/`getrow`.
  - User shell v0 (new, owner ask): `apps/orbitdb_cli.xi` -> `out/orbitdb.exe`
    (icon embedded) / `out/orbitdb-cli` (WSL); REPL
    put/get/del/range/count/ckpt/bench/info/recover/kill; `kill` -> restart
    WAL-replay recovery demo verified on both platforms; README "Try it" +
    RUNBOOK row. Typed-row commands ride M5.3.
  - Index-of-record: `docs/PRODUCTION-READINESS.md` **73.5/100 (~74%)**,
    per-area table + changelog + 100% checklist (v0.3-beta gate needs fsync +
    torn-page matrix + benchmarks at scale).
- **Known limitations / risks (read before touching storage):**
  - **No fsync**: process-crash safe only; never claim power-loss durability.
    The stdlib surface exists but is stubbed (`os/fs_ffi.fsync` +
    `os/sync_io.sync_fd` return Err); `wal_file_flush`/`page_file_sync` are
    the seams, `byteio_sync` is the block-store/snapshot seam, and the
    durability API + `ORBITDB_FAULT_*` injector are pinned so the swap is
    behavior-only (the env layer is test-only; never set in production).
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
  - Values are int-only today; secondary value index + ORDER/LIMIT are in
    (M4.2, handle-scoped/rebuild-on-open; durable index storage with A5);
    typed values pending (M5.1).
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
  - XV-ORBITDB-01 (XVECTOR side): **RESOLVED** -- fixed at xvector `3c36f34`;
    verified against their source and CLOSED 2026-10-10; the probe's
    `persist_recovered` workaround is REMOVED (plain `wal_persist`, full +
    crash GREEN x2 both). **Hybrid re-run 2026-10-11: GREEN again (36
    checks)** -- the earlier 113 T001s were our `tests/hybrid/xiom.toml`
    missing xvector's registry deps (`xiom.vectors` + rate/http; their
    tree is green on v0.64.3); deps mirrored from their manifest; keep that
    block in lockstep with theirs when either side moves.
  - Hybrid composition needs the sibling `xiom-xvector` checkout at
    `E:\xiom-projects\xiom-xvector` (relative paths in `tests/hybrid/xiom.toml`);
    the probe is source-level until both packages publish (M6/F4), so the
    composition tracks the sibling's WORKING TREE -- expect red while the
    sibling is mid-refactor.
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
  1. **M5.1 typed values v2** (type-tagged tuples; text at least).
  2. **M1.2 byte-page v2 -- design + S1 + S2 + S3 integration DONE**; next
     S4 (stdlib fixed-size IO + fsync swap, default flip + fresh bench,
     FORMATS "3v2" tables; **M2.1 second half rides here**), then M1.1b lazy
     load.
  3. Order-3 B-tree fix landed (upstream of `xiom.btree` SPEC 2.3) -- next
     `xiom.btree` release re-extracts; run the consumer pass then.
  4. **M2.1 first half DONE** (durability API + fault injector; suite 136 x2
     both + `probe_fault_sync` 49 checks x2 both); fsync wiring when the
     stdlib rows land; **M1.1b** lazy load once random-access page reads
     exist; MVCC per M3; keep readiness + keeper docs current; commit signed
     at every step.
  5. **Hybrid regression guard:** re-run `scripts/hybrid_crash_test.*` +
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
  `REL-20261010-1549-packages-4`) + **`REL-20261011-1124-orbitdb`
  (C-ORBIT-07, consumer fn hijacks a module-private same-named call; filed
  2026-10-11)** + **`REL-20261011-1219-orbitdb` (C-ORBIT-08, enum-in-tuple
  miscompile + fixed-array UInt8 cast sign-extension; filed 2026-10-11)**;
  stdlib `-3` fsync, `-4` append handle,
  `-5` truncate, `-6` byte-IO random access, `-7` append+repair, `-8` tail
  check; packages `-9` btree re-extract, `-10` variant qualification;
  xvector `-11` (XV-ORBITDB-01).
- Report upstream through the xiom-relays bus (section 1) + SESSION rows;
  the owner handles human gates. Read other lanes' bus items before filing
  (reference their ids).
- **Toolchain hygiene (ops rule `REL-20261011-1134-ops`, 2026-10-11; full
  text `TOOLCHAIN_HYGIENE.md` in the bus repo):** never delete or downgrade
  the shared homes (`%LOCALAPPDATA%\xiom*`, WSL `~/.local/share/xiom`,
  `~/xiom`); treat dirs without this lane's name as read-only. This lane
  pins its own shadow compiler via `scripts/dev-env.ps1`; install/uninstall
  experiments must use an isolated `XIOM_HOME` + lane-local extraction and
  be announced with a `to: all` item. If a green battery suddenly shows
  unresolved-package T001s, stop, rerun once, and file to ops with
  timestamps if it recovers.
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
  C-ORBIT-07 filed 2026-10-11 as `REL-20261011-1124-orbitdb`;
  standalone-check quirk `REL-20261010-1550-orbitdb-2`; repro bundles under
  `docs/repro/`).
- `docs/XVECTOR-INTEGRATION.md` (hybrid contract; reply processed; section 7
  answers their cross-asks + XV-ORBITDB-01, bus `-11`).
- `docs/STDLIB-WISHLIST-ORBITDB.md` / `docs/PACKAGE-WISHLIST-ORBITDB.md`
  (resolved history + deltas; open rows on the bus `-3..-8` / `-9..-10`).
- `docs/PULSE-INTEGRATION.md` (PULSE contract) and
  `docs/PRODUCTION-READINESS.md` (scoreboard -- recompute + changelog line
  every wrap).
- `docs/REFERENCE-STUDY.md` -- owner-granted reference sandbox (`E:\repos`:
  bbolt MIT / redb MIT-Apache / sqlite public domain); production-pattern ->
  adopt/adapt/avoid map per slice + ordered next actions.
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

TOOLCHAIN (latest-tracking): compiler v0.64.3 Windows shadow install
(%LOCALAPPDATA%\xiom.new.0643) + WSL canonical ~/.local/bin/xiom (v0.64.3;
dev-env pins both); stdlib
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
WATCH each session: any newer COMPILER archive (re-test the repro
bundles -- now incl. `docs/repro/consumer-fn-hijack/` for C-ORBIT-07 --
plus the suite first; re-verify the phantom bundle on the first archive
containing m255 -- REL-20261010-1802-orbitdb). **Compiler batch plan
`REL-20261011-1342-compiler` (2026-10-11, to: all) names OUR witnesses:**
batch 1 resolver/isolation (items 1052+1124; gate: module-local precedence,
module-private isolation, ambiguity diagnostics, m225 regression set)
expects `docs/repro/consumer-fn-hijack/` to print `svc: private arm() ran`
on BOTH import orders; batch 3 phantom imports (1802+2124) expects the
`docs/repro/phantom-core-import/` symptom to vanish. Keep the workarounds
(`probe_arm`, type declarations) until each batch lands, then re-verify
from the bundle READMEs and report on the bus. PULSE's `probe_pkg_orbitdb`
results, and the stdlib rows on the bus (-3..-8 acked). (XVECTOR's
XV-ORBITDB-01 fix was verified and closed 2026-10-10; re-run the hybrid
probe when their pin moves.) **Doorbell: scheduled cron tasks are
SESSION-scoped -- a fresh session MUST re-create the 3h `cron_create`
xiom-relays doorbell (pull, `view --lane orbitdb`, process, verify release
rows, docs+commit).**

CURRENT STATE: v0.64.3 pin (Windows shadow `xiom.new.0643` via dev-env;
WSL canonical `~/.local/bin/xiom`; the Windows canonical `xiom.new` stays
v0.64.2 for the fleet -- swap is owner/ops-coordinated); all C-ORBIT compiler
workarounds REVERTED and the suite is green on the native forms --
conformance 152/152 x2 Win + WSL (see
the findings file for the one consumer-qualification caveat); db_crash five
scenarios (WAL-only, snapshot-only, snapshot+tail, uncommitted txn discarded,
committed txn recovered) x2 Win + WSL, each recovery followed by qverify
(range + value-filter queries; 25 checks); hybrid ORBITDB <-> XVECTOR probe
`tests/hybrid/probe_hybrid.xi` (36 checks: join integrity, brute-force
top-k, delete pipeline, reopen bit-equality, prefix/torn tail) +
`scripts/hybrid_crash_test.{ps1,sh}` (hard-kill both stores -> repair ->
100% join integrity, idempotent) x2 Win + WSL; C-ORBIT-06: twin half still
red on v0.64.3 via the documented invocation (invocation-dependent --
bare-filename checker bug fixed on compiler main by m255, unpushed;
re-verify the phantom bundle on the next archive), phantom acceptance
queued for v0.64.4; standalone `--check` quirk = bus row -2 (acked, still
open); C-ORBIT-07 filed 2026-10-11 (a consumer fn silently hijacks a
module-private same-named call; bundle `docs/repro/consumer-fn-hijack/`,
bus `REL-20261011-1124-orbitdb`; workaround: distinct helper names);
C-ORBIT-08 filed 2026-10-11 (enum-in-tuple miscompiles -- crash or skipped
match arms; fixed-size `[N]UInt8` element `as Int` sign-extends;
workarounds in `tuple.xi`; bundle `docs/repro/enum-tuple-codegen/`, bus
`REL-20261011-1219-orbitdb`);
XV-ORBITDB-01 FIXED (xvector `3c36f34`), verified against their
source and CLOSED -- the `persist_recovered` workaround is REMOVED; fuzz/property harness
`scripts/fuzz.{ps1,sh}` (seeds=4 ops/seed=4000) x2 Win + WSL; policy soak
2000 keys / 9 checkpoints x2 Win + WSL; 20k-record WAL replay ~9.9 s (linear
stdlib); bench harness live; app build `scripts/build.ps1` embeds
assets/orbitdb.ico (--icon verified); readiness
73.5/100 (docs/PRODUCTION-READINESS.md -- recompute + changelog every wrap);
reference docs docs/API.md + docs/RUNBOOK.md + docs/FORMATS.md +
docs/ISOLATION.md + docs/REFERENCE-STUDY.md; production plan
docs/PRODUCTION-PLAN.md +
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
query_key_range, point/range plans (M4.1); byte-page format v2 S1+S2+S3
(codec `src/storage/block.xi`; shim `byte_io.xi`; store
`src/storage/block_store.xi` with 26-check probe + 4-state crash harness +
fuzz; v2 snapshot container behind `page_format` 2 with auto-detect +
migration, db_crash v2 x2 both; design `docs/BYTE-PAGE-FORMAT-V2.md`);
secondary value index + ORDER/LIMIT (M4.2: `src/secondary_index.xi` +
`IndexValue` plan; suite 134 x2 both); B-tree order-3
empty-chain fix (predecessor/successor, fill_child, min/max; suite
regression + fuzz orders 3/4/5); durability API + fault injector (M2.1
first half DONE -- evidence: 2 suite tests + `tests/probes/probe_fault_sync.xi`,
49 checks, x2 Win + WSL; see the top Updated entry); typed values v2 --
M5.1 codec + M5.2 schema layer + **M5.3 ENGINE PERSISTENCE DONE 2026-10-11**
(`TValue`/`tuple2_*`; `schema_row`; `BTreeNode.payloads` through tree moves;
WAL tagged subtype-1 records; node pages v2 with auto-detect; 
`db_file_put_typed`/`get_typed` + budget + byte validation; legacy v1-node
artifacts load unchanged; 5 suite tests + fuzz (h)/(i)/(j) + fault E; CLI
`putrow`/`getrow`/`qrow`); **M5-S4 typed predicates DONE** (`tuple2_compare`
total order + `TypedQuery`/`db_file_query_typed` + fuzz (k) vs an
independent model; CLI `qrow`; typed secondary indexes are an optional
follow-on)). Known
limits: no fsync
(process-crash safe only; the durability API
+ env fault injector are pinned so the swap is behavior-only); replay is linear now but file IO is O(n) per read
(no random access); checkpoint encodes only dirty nodes (M1.1) but the tree
stays fully resident (lazy load/bounded cache need random-access page reads);
transactions single-active, no MVCC (single-writer model in
docs/ISOLATION.md); buffer pool in-memory only (pager seam C3 pending);
fuzz runs per wrap (CI cadence awaits F3).

TASK ORDER (highest value first; full plan docs/PRODUCTION-PLAN.md sec. 13):
1. **M5 COMPLETE 2026-10-11** (codec -> schema -> engine persistence ->
   typed predicates; suite 152 x2 both + fuzz (h)/(i)/(j)/(k) + fault E;
   `docs/TYPED-VALUES-STORAGE.md` landed; readiness 73.5; CLI
   putrow/getrow/qrow). Optional follow-on: typed secondary indexes.
   Next actionable: **M3 MVCC minimal subset** (snapshot pinning +
   savepoint slice per docs/REFERENCE-STUDY.md) -- self-contained, no
   stdlib dependency; while watching the stdlib rows (M1.2 S4) and the
   `xiom.btree` re-extract (bus -9) to slot in when they land.
2. M1.2 S4 when the stdlib rows land (byte-IO/fsync swap -- bus -3..-8
   acked; v2 default flip + fresh bench + FORMATS 3v2 tables; M2.1 second
   half rides here), then M1.1b (pager: deterministic deferred-free
   allocator per docs/REFERENCE-STUDY.md).
3. When the fixed `xiom.btree` is re-extracted (order-3; bus -9 acked), run
   our two-way consumer pass.
4. M3 MVCC minimal subset (snapshot pinning + savepoint slice) per the
   reference study; keep the hybrid harness green at every wrap (and when
   the XVECTOR pin moves); keep SESSION.md STATE, the bus items and
   PRODUCTION-READINESS updated at every wrap; commit signed per step.

DISCIPLINE (v0.64.3; C-ORBIT workarounds DROPPED -- see COMPILER-FINDINGS):
- Never keep an unresolvable `use` or an undeclared type (C-ORBIT-06): it
  type-checks standalone with bogus W004s, then hard-fails once any module in
  the program declares a same-named type.
- Consumer modules: module-qualify enum variants when a same-named enum is
  anywhere in the program (m225 consumer-scope caveat; no ambiguity error).
- Consumer modules: keep helper names distinct from functions inside
  imported modules (C-ORBIT-07): an unqualified call to a module's PRIVATE
  same-named helper silently binds to the consumer's function (missing args
  arrive as empty values; no diagnostic; symptom is often a bogus contract
  panic inside a stdlib module).
- Never put an enum in a tuple (C-ORBIT-08A: `Result[(Enum, Int)]`
  miscompiles -- crash or silently skipped match arms; return the enum alone
  and pass positions separately). Mask fixed-size array byte reads
  (C-ORBIT-08B: `[N]UInt8` element `as Int` sign-extends; use
  `(b[i] as Int) & 0xFF`; `Vec[UInt8]` casts are correct).
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
