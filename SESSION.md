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
**Updated:** 2026-10-12 (v0.64.4 adoption + verdict wave, doorbell session):
  pin moved to the v0.64.4 shadow (`xiom.new.0644`, Windows) + WSL canonical
  v0.64.4 (dev-env both shells). Release-check `compiler-compiler-v0.64.4`
  verdicts filed + pushed for all four orbitdb rows: `-2` still open (T001
  1756/1761/1766); `-1219` PART B fixed (m260) / PART A red (0x80000003);
  `-1659` still red (copy elem-assign writes through); `-1358` confirmed red
  on Linux = **C-ORBIT-10** (bundle `docs/repro/check-exit-code/`).
  Witnesses: **C-ORBIT-06 FIXED + CLOSED** (unresolved `use` = single hard
  T001 `unresolved import 'xiom.core.error'`; phantom silent-pass gone) and
  **C-ORBIT-07 FIXED + CLOSED** (`probe_fault_sync` workaround reverted to
  `arm`; witness `svc: private arm() ran`; probe green, 57 checks). Battery:
  seven bundles green; suite **159/159 x2 Win + x2 WSL**; fuzz + WAL crash
  both platforms; 2000-key soak OK. Watch on the bus: C-ORBIT-08 PART A,
  C-ORBIT-09, `-2`, C-ORBIT-10.
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
**Updated:** 2026-10-11 (M5 COMPLETE -- CLEAN HANDOFF, next session): the
  session landed, in order: user shell v0 (`apps/orbitdb_cli.xi` ->
  `out/orbitdb.exe` / `out/orbitdb-cli`; put/get/del/range/count/ckpt/bench/
  info/recover/kill + putrow/getrow/qrow); M5.2 schema layer
  (`schema_row`); M5.3 typed rows in the engine (parallel
  `BTreeNode.payloads`, WAL subtype-1 tagged records, node pages v2 with
  auto-detect, `db_file_put_typed`/`get_typed` + byte/budget enforcement,
  legacy v1-node-artifact load + migration verified); M5-S4 typed
  predicates (`tuple2_compare` total order + `db_file_query_typed`); plus
  C-ORBIT-07 (consumer fn hijack; `probe_arm` rename) and C-ORBIT-08
  (enum-in-tuple miscompile; fixed-array cast sign-extension) with verified
  bundles; and the hybrid-composition fix (tests/hybrid/xiom.toml deps
  mirror; WSL shared-home restore). **State at handoff: NO WIP** -- working
  tree CLEAN at `414746b`+docs; suite 152/152 x2 Win + WSL; fuzz (h)/(i)/
  (j)/(k) x2 both; fault probe 56 checks x2 both; hybrid probe x4 +
  crash x4 green across platforms today; readiness **73.5**; doorbell
  re-armed this session (18:00Z, 21:00Z...). Lane heads stdlib `b8eda7d` /
  xvector `ede0e20` / packages `263684d9` / relays `88c2343`. Next per
  task order: **M3 MVCC minimal subset** (snapshot pinning + savepoint
  slice per docs/REFERENCE-STUDY.md).
**Updated:** 2026-10-11 (M3.1 snapshot pins + savepoints, same session): the
  **M3 minimal subset LANDED**. Design `docs/MVCC.md` (pin = {root, lsn,
  generation}; copy-on-write writes while pinned via birth epochs +
  `cow_shadow`; compaction deferred while pinned + `compaction_deferred`;
  savepoints = txn-buffer markers + WAL window splice Abort+Begin+re-log).
  Engine: `DBSnapshot`, `db_file_snapshot_begin/end/get/get_typed/range/
  count`, `db_file_snapshot_pins`, `db_file_min_pinned_lsn`,
  `db_file_snap_generation`, `db_file_compaction_deferrals`,
  `db_file_txn_savepoint/_restore/_release/_active`; NodeStore
  births/pins/pin_clock. Found **C-ORBIT-09** (element assignment through a
  copied Vec handle aliases the SOURCE buffer -- the COW shadow corrupted
  pinned views until `node_deep_copy` rebuilt every vector; bundle
  `docs/repro/vec-copy-alias/`, bus `REL-20261011-1659-orbitdb`). Evidence:
  suite **159/159 x2 Win + WSL** (7 new tests), `probe_mvcc.xi` 36 checks
  GREEN x2 both, fuzz section (l) x2 both, db_crash 25/25 x2 both; readiness
  **D3 2/4 -> 75.5**. Docs: MVCC.md + ISOLATION rewrite + API/RUNBOOK/README/
  plan/checklist coupled.
**Updated:** 2026-10-13 (doorbell 15:00Z -- packages P2 delivered): packages
  moved our `REL-20261012-1945-orbitdb-3` to fixed with **both P2
  deliverables**: offline/vendored install design note (474e081e) + the
  generated **platform matrix v1** (`docs/PLATFORM-MATRIX.md`, pinned
  v0.64.4, 534 rows, generator + STATUS `platforms/runtime_deps` validation;
  undeclared-native backlog 36 flagged honestly). All six ORBITDB-consumed
  packages carry rows with conformance evidence (btree 0.1.1 23/23 @
  5be4adeb, wal 21/21, vectors 37/37, metrics, rate, http compile/undeclared
  -- flagged). **Verified + closed** on the bus. Airgap Flow B rides
  `-1549-packages-7` (tracked). Remaining production-relay items:
  compiler `1945-2` (08/09/10 in batches) + `1358`/`1956` acked. Relays head
  `2d7505c`.
**Updated:** 2026-10-16 (doorbell 21:00Z -- v0.64.6 RELEASED + re-verified):
v0.64.6 shipped (2026-10-16T20:33Z; release run 38962236697; stdlib pin
`stdlib-v0.64.6` `b81430ba`); the fleet swap already put the WSL canonical
at v0.64.6 and extracted the Windows archive
(`%LOCALAPPDATA%\xiom.new-20261016-233955`, sha `0ff5c5c4...`). **The
orbitdb re-verify action is DONE, x2 platforms:** C-ORBIT-12 FIXED (m336) --
`repro_enum_tuple_enum_error.xi` prints `repro C: sum=110`, rc 0 (was a
clang hard error); control n=8/custom=5/done; u8 regression 3x248; the
C-ORBIT-09 alias probes + C-ORBIT-11 `compose ok` also green on v0.64.6.
Item `REL-20261015-2022-orbitdb` verified + CLOSED; verdict row filed in
`release-checks/compiler-compiler-v0.64.6.md`. **Ops recurrence handled:**
the v0.64.6 swap clobbered the Windows shared registry home AGAIN
(`xiom.btree`/`wal` unresolved on BOTH pins) -- additive reinstall
(`xiom.btree@0.1.1`, `xiom.wal@0.1.0`, checksums verified) restored it; ops
FYI `REL-20261016-2120-orbitdb` (third occurrence of the class;
snapshot-before-swap is the standing ask). The lane pin (`dev-env.*`) is
STILL v0.64.5 -- the swap + adoption battery (suite x2, crash, probes; then
the C-ORBIT-12 workaround drop) is owner-coordinated and queued. Lane
heads: compiler v0.64.6 released (bus `2291513`), stdlib `6c96bbb` + tag
`stdlib-v0.64.6`, relays `9c0829f`; repro READMEs + COMPILER-FINDINGS carry
the v0.64.6 verdicts.
**Updated:** 2026-10-16 (doorbell + stdlib check, same-day continuation; perf
  re-measure still pending): the 3h relay doorbell is RE-CREATED
  (session-scoped; `0 */3 * * *`; first fire 15:00Z). Bus pulled:
  `6c3352d` -> doorbell pushed `a1a1e53`; our `REL-20261016-1223-orbitdb`
  (TCP_NODELAY heads-up) VERIFIED + CLOSED after the compile check below; the
  three fresh `to: all` packages notes reviewed -- codenames convention
  (Beacon/Satellite/mote vs Station/lattice; matches our two-tier docs;
  registry ids unchanged; codename stamped at the next version touch),
  xiom.http 0.1.7 rider (our hybrid dep mirror rides xvector's manifest
  move), xiom.pulse extraction claim -- none orbitdb-actionable, and
  `to: all` items are not lane-movable (the bus refuses; owner/all-lane
  only), so nothing to ack per protocol. **stdlib checkout Linux compile
  FIXED + VERIFIED:** the TCP_NODELAY WIP (`REL-20261016-1223-orbitdb`; the
  stdlib ack says resolved) is in at `a451349` (ancestor of `6c96bbb`); a
  WSL consumer compile on the checkout (`XIOM_STDLIB=/mnt/e/xiom-lang/stdlib`,
  stock v0.64.5 compiler, probe_crc32c) is GREEN 2026-10-16 --
  `BENCH_STOCK_STDLIB=1` is no longer REQUIRED (kept as the stock-baseline
  option; docs/BENCH-1.md + bench_cross.sh comment updated). **v0.64.6
  RELEASED 2026-10-16T20:33Z** (`REL-20261016-2034-compiler`, assets live,
  stdlib pin `b81430ba`; `release-checks/compiler-compiler-v0.64.6.md` open
  with OUR row: C-ORBIT-12 (`REL-20261015-2022-orbitdb`; **m336 = canonical
  tuple naming in every position** -- enum-in-tuple + inline from_utf8 --
  integrated, repro sum=110 + control green on the integrated build,
  **archive re-verify pending**). The release item names our lane's re-run
  explicitly: the enum-tuple repro + the silent-mode t3..t9 bisect. Re-run
  scope when adopted: suite x2 both FIRST, then the C-ORBIT-12 repro + the
  t3..t9 bisect + the 08A/09/11 regression bundles + row `-2`, then set
  the verdict row; if m336 closes the wide shape, retire the
  `DbResult[(TValue, Int)]` position workaround with suite+fuzz as the
  acceptance. **Adoption is owner-gated -- queued as the next session's
  FIRST item; no archive battery in the watch-only window.** **Perf
  re-measure STILL PENDING:** the host carried other-lane compiles the whole
  window (engine toolchain probes, compiler stdlib smokes, four `xiom.exe`
  workers; VS Code + docker/qemu); the WSL VM itself was idle (its
  /proc/loadavg read a phantom ~90 -- use ps/free, not loadavg). Wakeup
  armed to re-check quietness and run BENCH-1 R1-R3 + `probe_wal_ab` then;
  WSL rows after.
**Updated:** 2026-10-18 (C-ORBIT-12 residual FIX VERIFIED on main; drop
  staged): the compiler lane fixed the module-qualified position-tuple
  registration (`c6b3362ef`: on-demand `Tuple__*` registration in
  llvm_type_for) and staged the workaround drop on branch
  `fix/c-orbit-12-position-tuple` (`f779c23`: natural `(TValue, Int)` with
  absolute next offsets). **Independent verify (our lane): suite 160/160 x2
  with the position tuple on the main-tree RELEASE build**
  (`E:\xiom-lang\xiom\target\release\xiom.exe` + main stdlib
  `E:\xiom-lang\xiom\stdlib`) -- zero unknown-type warnings (previously
  154/160 + two `Tuple__TValue__Int` warnings). Item
  `REL-20261017-1154-orbitdb` moved fixed -> VERIFIED; it will be CLOSED
  when the fix rides a released archive. **The workaround stays on main**
  (lane pin = v0.64.7 without the fix); at the next release adoption:
  merge `f779c23`, suite x2 both, close the item. Branch left in place.
  Relays head checked; no other lane items.
**Updated:** 2026-10-20 (RAM-CAP DIRECTIVE IMPLEMENTED -- owner, all lanes):
  every app/soak/bench probe that can allocate without bound now runs
  through a capped wrapper. New `scripts/run_capped.ps1` and
  `scripts/run_capped.sh` (WorkingSet/VmRSS sampled every 500 ms; kill at
  `-MaxRAMGB`/`MAX_RAM_GB`, exit 137; optional timeout, exit 124; prints
  peak). The admin runner uses the cap (2 GB default:
  `scripts/admin.ps1 -MaxRAMGB`, `MAX_RAM_GB` in `admin.sh`). **Verified:**
  the m375 mem-read probe was killed at **1,052 MB / exit 137** with a 1 GB
  cap (no host pressure); seed-demo runs clean under the cap. RUNBOOK has
  the policy + usage. Do not run `probe_mem_read`/`probe_soak`/benches
  uncapped while other lanes are active.

**Updated:** 2026-10-20 (M3 SHARD LOCK LANDED -- file_lock integrated):
  the stdlib station asks are verified and **closed**
  (`REL-20261016-1128-orbitdb`: file_lock wave 152, TLS/ALPN server,
  KDF/CSPRNG, monotonic clock, TCP ergonomics). ORBITDB integration:
  **`db_file_open_locked_checked[_cfg]` + `db_file_unlock`/`db_file_is_locked`**
  -- an exclusive whole-file advisory lock on a dedicated `<path>.lock`
  sentinel (one lock per process, release-or-die, sentinel never deleted
  while held; the DB/WAL/snapshot are never locked because checkpoints
  rename the snapshot). Cross-process probe `tests/probes/probe_lock.xi`:
  parent holds -> child refused; release -> child acquires; child acquires
  and exits -> parent reacquires (**PASS Windows + WSL**). dbfile gained a
  locked-open test (25/25; suite **165**). The web admin now opens with the
  shard lock and fails fast on a second instance (verified: second exits 1;
  quit releases; next start serves). Cross-process pin contract documented
  in ISOLATION: external readers use snapshot copies; Station readers live
  in the owning engine actor. **G-START: M3 [x], threads [x], R1/R2 [x];
  only M1.1b A6 (m375) remains** before ST1.

**Updated:** 2026-10-20 (m375 MINIMAL REPRO PROVIDED): the compiler lane
  acked the A6 memory report as **m375** and asked for a minimal
  `io.read_at` repro. Added `tests/probes/probe_mem_read.xi` (64 MiB file,
  rotating 4 KiB reads, env-selectable `io.read_at` vs `byteio_read_at`):
  **100,000 x read_at -> 3,103 MB peak (~31 KB/read)**; **50,000 x
  byteio_read_at -> 3,127 MB (~62 KB/read)**; results exact, no frees until
  exit (WorkingSet sampled at 200 ms). Inline source + numbers relayed as
  `REL-20261020-1222-orbitdb` (compiler m375); pushed. The pager will adopt
  a direct byte-level page reader as the fallback if the runtime cannot
  reclaim. **A6/1M remains blocked on m375**; next is the BENCH-1 rerun at
  the v0.64.8 pin move.

**Updated:** 2026-10-21 (ST1 ORBITWIRE v1 LANDED -- hello-station GREEN):
  `station/` is a new source-composed project (`xiom.toml`: `../src` + `src`)
  with the frozen wire spec `station/docs/ORBITWIRE.md`, a pure typed frame
  codec (`protocol.xi`: "OBW1" magic, version/kind/flags, u32 header/payload
  lengths, typed field dictionary, CRC32C over `[4,end-4)`, row/value
  streams), session buffers + bounded outbound queue/backpressure
  (`session.xi`), the single-writer `StationActor` + session state machine
  (`dispatch.xi`: NEW/GREETED/READY/TXN/CLOSING/CLOSED; HELLO/AUTH/PING/
  BEGIN/PUT/GET/RANGE/QUERY/COMMIT/ABORT/CLOSE + additive DELETE/CHECKPOINT;
  `DbError` -> stable codes), and a single-threaded TCP poll loop
  (`server.xi` + `hello_station.xi`; 127.0.0.1:7767, `_PORT=0` -> first free
  17867+). **No DBFile across threads**; one txn window per shard with
  `txn_owner`; non-owner writes -> TXN_ACTIVE; disconnect/CLOSE aborts the
  owner's window. Auth = shared token (`ORBITDB_STATION_TOKEN`), 3-failure
  lockout. Limits: 1 MiB frame / 64 KiB header / 512 KiB payload / 4 MiB
  queue / 64 sessions / 500 default range (1000 max) / 5000 query / 10k txn
  ops. Tests: `station/tests/{protocol,session,loopback}_suite.xi` =
  33+28+108 = **169/169 x2 Win + x2 WSL** (`scripts/station_suite.*`; WSL
  via `wsl_ext4.sh`, which now copies `station/`). Loopback covers
  HELLO/AUTH/lockout, CRUD, RANGE, QUERY order/limit/offset, txn
  invisibility/isolation, typed rows with all TValue kinds + payload limit,
  framing LIMIT+close, CHECKPOINT, CLOSE. **Compiler findings filed:**
  C-ORBIT-14 `REL-20261021-1136-orbitdb` -- `let`/`var x = match` over a
  Result truncates a Vec silently (38-byte header -> 1; workaround
  declare-then-assign; repro `docs/repro/vec-match-binding/`); C-ORBIT-15
  `REL-20261021-1157-orbitdb` -- a UTF-8 BOM on a module whose declared path
  != file name breaks catalog discovery (silent unresolved import; repro
  `docs/repro/utf8-bom-module/`; save sources BOM-free). **Doorbell 12:00Z:**
  the compiler lane **fixed C-ORBIT-14 on main the same day (`478e06f8b`,
  m1136)** -- not in v0.64.8, so the workaround stays until the next archive;
  latest release still v0.64.8 (2026-10-19), `io.read_at_into` still not in a
  tag. **Doorbell 15:00Z:** C-ORBIT-15 (BOM catalog) also **fixed on compiler
  main `18415ede2`**; packages **acked** the ORBITWIRE interop co-run
  (`REL-20261021-1154-orbitdb`, queued behind publish cycles); still no new
  compiler/stdlib release. Both compiler workarounds stay on the v0.64.8 pin
  and are re-tested on the next archive. Docs: FORMATS 7 +
  lock-file row, REFERENCE-MATRIX 3.2 conversion + blocker ledger, two-tier
  checklist ST0/ST1, RUNBOOK 7, station README, readiness changelog (score
  unchanged 82.5 -- Station is a separate tier, ST1 is a spike). Interop
  co-run filed `REL-20261021-1154-orbitdb` (packages). Next: ST2 server core
  + crash harness; **ST1 did not touch `src/`**.

**Updated:** 2026-10-24 (v0.65.0 extracts READY -- acceptance next; pins
  unchanged): both official archives downloaded and **SHA256SUMS-verified**
  (Windows zip `ff4abb4a...`, Linux x64 `48a58dd7...`); extracted to
  **Windows `%LOCALAPPDATA%\xiom-0.65.0`** (exe sha `545f5699...`) and
  **WSL `~/.local/share/xiom-0.65.0`** (bin sha `30870486...`). Both
  `--version` = 0.65.0; bundled `lib/package.xi` = 0.65.0 and
  `lib/xiom/io/io.xi` has `read_at_into`. **dev-env pins intentionally
  remain v0.64.8** until the acceptance battery passes. Next: run the
  acceptance from these extracts (set `XIOM_COMPILER` to the new exe/bin;
  do not commit a pin bump until green).**Updated:** 2026-10-24 (v0.65.0 RELEASED -- acceptance is task 0; pins not
  bumped yet):
  **v0.65.0 is out** (compiler tag `f527d5a` on `a0dc452dc`, 11 assets +
  SHA256SUMS; stdlib-v0.65.0 `3eb9c05`; xiom-std 0.65.0 live; relay
  `REL-20261023-2346-compiler`). v0.64.9 remains withdrawn; **v0.64.8 is
  superseded** but the lane pins stay v0.64.8 until acceptance. Compiler
  lane reports full e2e 2646/2646 (4 ignored) on **both** debug and release,
  release parity x2, MCU QEMU, and the C07 runtime helper. **Do not bump
  `dev-env.*` yet.** First run the acceptance: archive version/checksums,
  1451/1550 + nested patterns, C-ORBIT-14/15 repros, m1157 BOM, m375
  `XIOM_FAST_EXIT=1` 1M A/B + A6 exact verify, full battery; then fill
  `release-checks/compiler-v0.65.0.md`, close the v0.64.9 hold rows, and
  bump the compiler/stdlib pins. Cross-lane note: bindings reports an
  owner-approved pause through the 04:00-13:00 Greek double-charge window
  (resume 10:05Z); confirm with the owner/compiler lane before adopting
  during it. Context-full wrap follows; next session starts at v0.65.0
  acceptance.

**Updated:** 2026-10-24 (v0.65.0 RELEASED -- production toolchain; lane under owner pause):
  compiler **v0.65.0** (tag `f527d5a` on `a0dc452dc`; 11 assets + SHA256SUMS
  re-verified; e2e 2646/2646 on BOTH debug and release; run 40041016248) +
  stdlib-v0.65.0 (`3eb9c05`, COMPILER_VERSION v0.64.8) + registry
  `xiom-std 0.65.0` (`c3629878...`) are LIVE; **v0.64.9 remains withdrawn,
  v0.64.8 is superseded**. **Owner-approved PAUSE**: all lanes paused through
  the 04:00-13:00 Greek double-charge window (bindings resumes 10:05Z) --
  adoption/re-verification is DEFERRED to the pause end. **Our resume tasks:**
  verify the v0.65.0 archive + SHA256SUMS, swap the pin with a versioned
  backup, re-run the full battery + hybrid, the m375 1M A/B with
  `XIOM_FAST_EXIT=1`, A6 exact verify, m1157 BOM regression, fill our row in
  `release-checks/compiler-compiler-v0.65.0.md`, close the remaining paired
  rows (`REL-20261020-1807-orbitdb-2`, `-2102`), and keep the stdlib pin in
  lockstep. Production slot stays v0.64.8 until the pause ends (no
  split-brain). Relays `3948877`.
**Updated:** 2026-10-24 (v0.65.0 RELEASED -- adoption is task 0 after the
  lane pause): compiler tag `v0.65.0` (`f527d5a`) on `a0dc452dc`, 11 assets
  + SHA256SUMS re-verified; stdlib-v0.65.0 (`3eb9c05`); xiom-std 0.65.0
  (sha `c3629878...`); e2e **2646/2646 on debug AND release compilers**.
  v0.64.9 remains withdrawn; v0.64.8 is superseded. Reporter duties: verify
  archive + SHA256SUMS, run 1451/true-1550/nested patterns, m1157 BOM,
  **m375 1M A/B with `XIOM_FAST_EXIT=1`** + A6 exact, C-ORBIT-14
  `via_let=3`; fill `release-checks/compiler-v0.65.0.md`; bump `dev-env.*`
  only after green. Lanes are paused through the 04:00-13:00 Greek
  double-charge window (resume ~10:05Z) -- confirm before starting; ST2/ST3
  can continue on v0.64.8 meanwhile. `NEXT-SESSION-PROMPT.md` task 0 carries
  the steps.
**Updated:** 2026-10-23 (SESSION WRAP -- context full; release hold, stdlib-
  v0.64.9 + read_at_into, 1M/hybrid green, ST2 crash harness):
  - **Toolchain:** compiler **v0.64.8 production** (Latest); **v0.64.9
    WITHDRAWN** (pre-release/audit only; nested enum patterns, m372/1550,
    m1511 port.args; v0.65.0 production gate). stdlib-v0.64.9 (`aa8b656`,
    archive sha `eab0b80d...`) is installed lane-local (Windows
    `%LOCALAPPDATA%\xiom-stdlib-0.64.9`, WSL
    `~/.local/share/xiom-stdlib-0.64.9`) and is the `dev-env.*` default
    (explicit `XIOM_STDLIB` wins); it pins compiler v0.64.8 and supplies
    `io.read_at_into`. `feat/read-at-into-open` merged (`27a8212`,
    `333dd3f`); stdlib relay `REL-20261021-1122-orbitdb-3` verified.
  - **Engine battery green on that pin:** suite **166/166 x2 Win + x2 WSL**;
    block crash **8/8 x2 both**; db crash **25/25 x2 Win**; fuzz 4 seeds;
    station **169/169 x2 Win**; io-primitives **30/30 x2**; mvcc **36/36
    x2**; hybrid **full 36/36 x2 both + crash 5/5 x2 both** (after the
    package-store restore installed `xiom.metrics` 0.2.0).
  - **A6 1M:** **PASS** -- exact **1,004-sample verify**, 32,260 nodes /
    32,341 blocks, **peak 2,451.2 MB** under the 4 GB cap (new best;
    previous 2,494.7 MB), engine 6.11 s; process wall **6,110 s** under
    sibling-lane load (quiet baseline 880 s; teardown-dominated, not a clean
    signal). 200k: 558.2 MB / 0.733 s engine / 733 s wall under load.
    `XIOM_FAST_EXIT` (m375) is **v0.65.0 acceptance input**; v0.64.9 is
    withdrawn.
  - **Station ST1:** ORBITWIRE v1 frozen (`station/docs/ORBITWIRE.md`);
    169/169 x2 both; runners `scripts/station*.{ps1,sh}`.
  - **Station ST2 crash harness:** `scripts/station_crash_test.{ps1,sh}` +
    `station/tests/station_crash_client.xi`; **11/11 x2 Win + x2 WSL**:
    uncommitted BEGIN+PUT discarded, auto-commit PUT replayed from WAL,
    post-recovery commit survives a second hard kill; M3 lock reacquired
    after `kill -9`; `ORBITDB_STATION_PORT_FILE` + listen-line flush.
    **No engine `src/` touched.** Remaining ST2: session-loop hardening +
    explicit graceful stop/SIGINT; then ST3.
  - **Compiler findings:** C-ORBIT-14 fixed on main `478e06f8b`; C-ORBIT-15
    (BOM catalog) fixed on main `18415ede2`; both postdate v0.64.8, so the
    declare-then-assign workaround and BOM-free sources stay until v0.65.0.
    Repro bundles `docs/repro/vec-match-binding/` and
    `docs/repro/utf8-bom-module/` are the re-test gate.
  - **Relays:** v0.64.9 hold `REL-20261022-1501-orbitdb` closed as
    **withdrawn (not green)**; hybrid block `REL-20261022-1750-orbitdb`
    verified; packages interop `REL-20261021-1154-orbitdb` acked; C-ORBIT-14
    `-1136`, C-ORBIT-15 `-1157`, stdlib `-3` (verified), m375 `-2`,
    packages 0.3.0 `-4`, all-lanes ops `-5`. v0.65.0 acceptance rows queued:
    1451/1550 + C-ORBIT-14/15 repros, m1157 BOM, m375 `XIOM_FAST_EXIT` 1M
    A/B.
  - **Git:** HEAD `cafb099` (ST2 crash harness); tree clean. Concurrent
    sessions have been committing in this worktree -- always check
    `git status`/`git log` before editing; do not clobber their SESSION
    entries.
  - **Next-session prompt:** [`NEXT-SESSION-PROMPT.md`](NEXT-SESSION-PROMPT.md)
    (the inline section 5 is now a pointer). Context-full wrap.

**Updated:** 2026-10-23 (ST2 station crash harness GREEN x2 both):
  `scripts/station_crash_test.{ps1,sh}` + `station/tests/station_crash_client.xi`
  hard-kill the hello-station at deterministic points and restart on the same
  DB file: uncommitted BEGIN+PUT is discarded, an auto-commit PUT replays from
  the WAL, and a post-recovery commit survives a second kill. **11 checks x2
  Windows + x2 WSL GREEN.** The M3 `.lock` left by `kill -9` is released by
  the OS and the restart reacquires it. Station adds
  `ORBITDB_STATION_PORT_FILE` (atomic bound-port file) and flushes the listen
  line before the loop; `wsl_ext4.sh` creates `out/` for relative DB paths.
  **No engine `src/` files touched.** ST2 remaining: session-loop hardening +
  explicit graceful stop/SIGINT, then ST3. Docs: RUNBOOK 7, station README,
  two-tier checklist.

**Updated:** 2026-10-23 (hybrid unblocked -- full + crash GREEN x2 both):
  The package-store reinstall (`202ee1f`; `xiom.metrics` 0.2.0 now present)
  removed the only hybrid block. Hybrid **full** probe: 36/36 checks GREEN
  x2 Windows + x2 WSL (ingest, crash-between, delete pipeline, repair, join
  integrity, top-k, edges, duplicate ids, dim mismatch/reset, persist,
  reopen, WAL prefix, torn tail); hybrid **crash**: 5/5 GREEN x2 Windows +
  x2 WSL (100% join integrity after repair; second verify idempotent).
  `REL-20261022-1750-orbitdb` verified. WSL needs `out/` for the relative DB
  paths (harness note: `mkdir -p out` before the probe; create it in the
  ext4 cache). No ORBITDB code change; the stdlib-v0.64.9 + read_at_into
  battery is now fully green except the quiet-host 1M wall. Cross-lane:
  btree/wal/vectors were reinstalled; `probe_compose_collision` C001
  `btree_insert/delete` unresolved is a package-composition finding for the
  split owner, not this lane.

**Updated:** 2026-10-22 (package-store reinstall + two consumer-path findings):
  the Windows package store was found short (pulse wipe notice
  `REL-20261022-2058-pulse`): our `xiom.btree 0.1.1` / `xiom.wal 0.1.0` /
  `xiom.vectors 0.1.0` were MISSING (pulse/website set intact). Reinstalled
  additively with the v0.64.8 pkg installer (also metrics 0.2.0 / rate
  0.2.0 / http 0.1.8 verified present). **Two findings for the split owner:**
  1. `tests/pkg/probe_compose_collision.xi` now FAILS C001: unresolved
  `db.engine.btree_insert` / `db.engine.btree_delete` at
  `@db.engine.core.db_file_apply_record` (v0.64.8 strict C001; previously a
  silent auto-stub). Main suite is green (166/166 x2), so this is a
  composition/resolver difference in the pkg manifest (source-roots
  `../../src` + registry xiom.btree dep) -- investigate; may be the
  registry `xiom.btree` module tree vs our `xiom.db.index.btree`.
  2. `tests/hybrid/probe_hybrid.xi` compile TIMED OUT at 300 s (exit 124;
  compiled binary produced). Likely host contention + the larger split
  tree -- rerun with TimeoutSec 600 before treating as a regression.
  State: parallel session has stdlib-v0.64.9 + read_at_into adopted, battery
  166/166 x2 both + 1M soak PASS (2,451.2 MB), compiler v0.64.9 still HOLD.
**Updated:** 2026-10-22 (stdlib-v0.64.9 + read_at_into branch ADOPTED; compiler
  archive still HOLD):
  - **Merged `feat/read-at-into-open`** (`27a8212`, 4 storage files:
    `io.read_at_into` v2 block-store scan, reused page buffer; branch retired
    from the queue). It compiles/runs against the stdlib release.
  - **stdlib-v0.64.9 adopted lane-local:** Windows
    `%LOCALAPPDATA%\xiom-stdlib-0.64.9`, WSL
    `~/.local/share/xiom-stdlib-0.64.9` (archive `xiom-std-0.64.9.tar.gz`
    sha256 `eab0b80d...`, verified); `dev-env.ps1/.sh` now default
    `XIOM_STDLIB` to it (an explicit env still wins). **Compiler stays
    v0.64.8**; the v0.64.9 compiler archive remains HOLD
    (`REL-20261022-1410/1414-stdlib`) -- no compiler pin bump.
  - **Functional battery green:** engine suite **166/166 x2 Win + 166/166 x2
    WSL**; block crash **8/8 x2 Win + 8/8 x2 WSL**; db crash **25/25 x2 Win**;
    fuzz 4 seeds; station **169/169 x2 Win**; `probe_block_store` 26/26;
    `probe_io_primitives` 30/30 x2; `probe_mvcc` 36/36 x2.
  - **Soak/perf (host-contended caveat):** 200k exact verify (201 samples),
    **558.2 MB peak**, engine 0.733 s; wall **733 s** while other lanes were
    compiling (quiet v0.64.8 baseline was 151 s), so this is not a clean
    perf number. **1M soak PASS on compiler v0.64.8 + stdlib-v0.64.9 +
    read_at_into branch:** 1,000,000 keys, exact **1,004-sample verify**,
    32,260 nodes / 32,341 blocks, **peak 2,451.2 MB** under the 4 GB cap
    (new best; previous 2,494.7 MB), engine work 6.11 s; process wall
    **6,110 s** under sibling-lane load (quiet baseline 880 s), so the
    teardown number is not a clean signal. `XIOM_FAST_EXIT` remains the
    m375 fix and is held with the v0.64.9 archive (now withdrawn; v0.65.0
    gate). Re-run the wall on a quiet host.
  - **v0.64.9 WITHDRAWN from adoption** (compiler lane, 18:30Z,
    `REL-20261022-1826-compiler`): production remains **v0.64.8**; the
    GitHub release is pre-release for audit; nested-pattern/m372/1550
    defects and m1511 port.args are v0.65.0 gate input. Keep the hold
    `REL-20261022-1501-orbitdb` open as acceptance input; **do not close
    v0.64.9 rows as green**. stdlib-v0.64.9 stays published (pins compiler
    v0.64.8) and is our lane-local enabler for `io.read_at_into`; it is not
    the production pin -- v0.65.0 will pin stdlib-v0.65.0.
  - **Hybrid full probe RED at compile:** the current xvector tree needs
    `xiom.metrics` 0.2.0, which is absent from `%LOCALAPPDATA%\xiom\packages`
    (only fontraster installed); 39 `metric_*` errors in
    `xiom.vector.{engine.core,observability.metrics}`. Filed
    `REL-20261022-1750-orbitdb` (xvector); not an ORBITDB regression (engine
    + station green). Hybrid crash is blocked by the same dependency.
  - Docs: BENCH-1 200k/1M caveat, dev-env pins, this entry. Next: hybrid
    after the xvector dependency, ST2; compiler archive re-test on the
    v0.65.0 gate.

**Updated:** 2026-10-22 (v0.64.9 COMPILER ARCHIVE HOLD -- do not adopt yet):
  The v0.64.9 compiler archives are **not green**. The stdlib lane reproduced
  two high-severity release-only failures on the official Windows/Linux
  archives (digests match the release): 1451/m372
  `p_nested_generic_ptr_read` prints 0/0, and the tuple-returning 1550
  `p_iter_enumerate_tuple` gives `em[1].0=0`; both pass on the debug build and
  both fixes are ancestors of the tag. `--release`/`--opt-level 0..3` flips
  the debug build to the same failures; the official default behaves like the
  failing mode. Blockers: `REL-20261022-1410-stdlib`,
  `REL-20261022-1414-stdlib` (stdlib -> compiler, open); the stdlib lane asks
  to hold the release announcement. ORBITDB **holds the compiler pin at
  v0.64.8** and re-tests on the fixed archive/patch. The stdlib **package**
  stdlib-v0.64.9 (`aa8b656`) is unaffected (it pins compiler v0.64.8) and
  contains `io.read_at_into` (9bad232), so `feat/read-at-into-open` can be
  verified on compiler v0.64.8 + stdlib-v0.64.9; the compiler archive hold is
  separate. Hold note filed to all: `REL-20261022-1501-orbitdb`. Queued m375
  `XIOM_FAST_EXIT=1` 1M A/B and m1157/C-ORBIT-14 re-tests wait for the fixed
  archive. **Update 18:30Z: v0.64.9 WITHDRAWN from adoption**
  (`REL-20261022-1826-compiler`); production remains v0.64.8; the hold stays
  open as v0.65.0 acceptance input (nested patterns, m372/1550, m1511
  port.args). Do not close v0.64.9 rows as green.

**Updated:** 2026-10-22 (v0.64.9 RELEASED -- orbitdb follow-ups; adoption
  queued): compiler v0.64.9 (tag `v0.64.9` on `2bcf58db5`; 11 assets;
  SHA256SUMS `51c45a61...`) + stdlib-v0.64.9 (`aa8b656`) + registry
  `xiom-std 0.64.9` (`6f0d3b15...`) are LIVE. **Our follow-up rows
  (v0.64.9 check): m375 1M A/B with `XIOM_FAST_EXIT=1`, A6 exact verify,
  m1157 BOM.** In this cut: m375 opt-in `XIOM_FAST_EXIT` (`b51ce6ec2`),
  2045 part 2 boxed Option/Result Str payloads, m1157 BOM catalog,
  m1731/m1703/m1326/m1520/1550/m365/m1511/m1531/XVC-C-22. **`io.read_at_into`
  IS in stdlib-v0.64.9 (`9bad232` is an ancestor) -- the A6 fallback can
  land at this adoption** (branch `feat/read-at-into-open`, `b3707b3`).
  **ADOPTION IS ON HOLD:** our lane (parallel session) filed
  `REL-20261022-1501-orbitdb` -- the OFFICIAL v0.64.9 archives fail the
  1451/m372 nested-generic-ptr-read and 1550 tuple-returning fixes in
  release-mode codegen (debug/main passes; `--release` reproduces). Stay on
  v0.64.8 until the compiler re-cuts/fixes. The read_at_into fallback is
  verified on branch `27a8212` (waits for a green v0.64.9+ archive). Also
  filed: hybrid probe blocked by the missing `xiom.metrics` package
  (parallel session).
**Updated:** 2026-10-21 (SESSION WRAP -- context window full; owner
  request): **A6 1M PASS / G-START GREEN.** 1M keys with
  `ORBITDB_PAGER_CAPACITY=65536` under the 4 GB cap: exact 1,004-sample
  verify, 32,260 nodes, peak 2,494.7 MB; 200k 607 MB/151 s. The earlier
  4,173 MB cap-kill was cache thrash (8,192 frames), not pure retention.
  Readiness 77.5 -> 82.5 (A 16->18, C 11->14; A5 row OK); G-START holds
  (M1.1b A6, M3 shard lock, threads, R1/R2) -> **ST1 conversion is
  unblocked**. **Also this session:** write-path fallback (byte-native page
  encode, reused node/WAL buffers, held append fd) fixed the v0.64.8 R2/R3
  write regression (R2 update 336->1,409; R3 1,786, beats v0.64.7); admin
  phase 1+2 + token-gated backup/restore (verified); WSL ext4 runner;
  `db_file_close` + fuzz per-seed isolation (held fd blocks delete on
  Windows); found a **module-level Vec.pop no-op** compiler bug (filed).
  **Open:** m375 exit-reclaim 880 s at 1M + default-cache thrash (wishlist
  filed); `feat/read-at-into-open` (b3707b3) waits for a stdlib release with
  `io.read_at_into`; P-rc power-loss matrix remains. **Relays filed at
  wrap:** global-pop BUG `REL-20261021-1122-orbitdb`, m375 wishlist `-2`,
  stdlib release `-3`, packages 0.3.0 `-4`, all-lanes ops INFO `-5`.
  **State:** main `b84c0da` + this docs commit; branch
  `feat/read-at-into-open` at `b3707b3`; relays pushed. Section 5 is
  refreshed for the next session.

**Updated:** 2026-10-21 (A6 1M SOAK PASS -- G-START GREEN): the earlier
  4,173 MB cap-kill was **cache thrash** once the tree outgrew the
  8,192-frame cache, not pure retention. With `ORBITDB_PAGER_CAPACITY=
  65536` (covers the 32,260-node tree) under the 4 GB cap: **1,000,000
  keys, exact 1,004-sample verify, 32,260 nodes / 32,341 blocks (~132 MB
  snapshot), peak 2,494.7 MB**; 200k is 607 MB/151 s. Process wall 880 s is
  the runtime exit-reclaim (m375 tracks it, not an A6 gate). **Readiness
  77.5 -> 82.5** (A 16->18, C 11->14, A5 row OK); **G-START GREEN** (M1.1b
  A6, M3 shard lock, threads, R1/R2) -> **ST1 protocol conversion is
  unblocked**. Suite 166/166 x2 both, crash 25/25 x2 both, probes x2,
  fuzz 4/4, hybrid 36 x2 both + crash 5/5 x2 both.

**Updated:** 2026-10-21 (admin backup/restore landed): `POST /api/backup`
  (token-gated) checkpoints, then atomically copies `<db>` ->
  `<db>.backup.wal` and `<db>.snap` -> `<db>.backup.snap` (temp+rename).
  **Verified end-to-end:** backup of a 40-key DB returned
  `anchor_lsn=42, snap_generation=2, wal_bytes=20, snap_bytes=172032`;
  copying the pair to `restore.wal`/`.snap` reopened with keys=40,
  `get(5)=50`, paged=true, gen 2. UI has a Backup button; README/RUNBOOK
  document restore (copy back while no handle is open). Admin remains
  localhost-only + token/CSRF discipline; it holds the M3 shard lock.

**Updated:** 2026-10-21 (A6 1M attempt -- cap-protected, blocked on m375):
  ran the 1M soak under the owner's 4 GB cap (order 64, 8192 cache). It was
  **killed at 4,173 MB / exit 137** with a 55.6 MB snapshot (~435k keys,
  ~9.6 KB/key at that point) -- superlinear vs the 200k result (607 MB,
  ~3 KB/key). The cap did its job (no host pressure); **1M and the A6
  memory row stay blocked on m375**. Write throughput remains fixed
  (BENCH section 4f); the read_at_into scan branch still waits for the
  stdlib release. Relay pull note: `git pull` in the relay repo errored
  ("Cannot fast-forward to multiple branches") while `fetch` + `merge
  --ff-only origin/main` worked; the doorbell uses that path.

**Updated:** 2026-10-21 (held-fd follow-up -- fuzz isolation + close API):
  the held append fd keeps the WAL open, so a test that reuses a FIXED DB
  path across fuzz seeds cannot delete it on Windows and silently reopens
  the previous seed's DB (this false-failed fuzz seed 1097 with a
  delete-presence mismatch). Fixes: fuzz DB paths are seed-specific; new
  **`db_file_close(db)`** releases the fd without invalidating the handle
  (next write reopens lazily); call it before deleting/renaming a DB file
  from the same process. Debug prints removed. **Fuzz 4/4 seeds green;
  suite 166/166 x2 Win + x2 WSL, crash 25/25 x2 both, probes x2 both,
  hybrid full 36 x2 both + crash 5/5 x2 both.** m375 remains for the
  memory/teardown plateau (200k soak 607 MB / 151 s); write throughput is
  restored engine-side (R2 update 336 -> 1,409; R3 1,786, beats v0.64.7).

**Updated:** 2026-10-21 (WRITE-PATH FALLBACK LANDED -- bench restored):
  byte-native page encoding (`block_encode_page_into`, byte-identical KAT),
  reused node-page payload (`node_page_bytes_into`), **one held append fd
  per handle for auto-commit writes** (the txn-window shape; closed before
  WAL truncate/checkpoint, `wal_file_prepare` before open), and a
  per-WALFile scratch record buffer. **200k A6 soak: peak 895 -> 607 MB,
  teardown 151 s** (order 64, 8192 cache, RAM-capped 4 GB). **BENCH-1 §4f:
  the 4e write regression was per-op WAL open/close and is fixed** -- R2
  load 559 -> **1,489**, update 336 -> **1,409**, delete 1,079 -> 1,722;
  R3 load 667 -> **1,563**, update 785 -> **1,786**, delete 984 -> 1,910
  (R3 beats v0.64.7); R1 1,113/1,053/780. Suites (block/index/dbfile/
  pager/typed/wal_txn/engine_database), fault/MVCC/lock probes and the
  crash harness are green; m375 still owns the remaining memory/teardown
  plateau and the 1M soak.

**Updated:** 2026-10-21 (WSL ext4 runner landed): `scripts/wsl_ext4.sh`
  mirrors the lane into `~/.cache/orbitdb-lane` (fresh each run, xvector
  link) and executes a command there, avoiding the `/mnt/e` 9p stalls that
  false-RED the WSL battery. Verified: foundations 24/24 and the full suite
  **165/165 x2 on ext4**. RUNBOOK section added. Main tree clean; m375
  (compiler) remains the A6/1M blocker; `feat/read-at-into-open` waits for
  the stdlib release.

**Updated:** 2026-10-20 (m375 write-path isolation): added
  `tests/probes/probe_mem_write.xi` and measured the two write sides in
  isolation on the released pin (RAM-capped 2 GB): **200k B-tree inserts
  (order 64) peak 18.1 MB / 0.6 s**; **200k `wal_file_append_sync` peak
  202.8 MB / 46.5 s**. The 200k A6 soak (895 MB) is therefore dominated by
  **page encode/write buffers** (`block_encode_page` builds a 4096-int
  Vec[Int] + `bytes_to_u8` per dirty page; ~5.8k dirty pages on the run) and
  the runtime's Vec-drop retention -- not the B-tree, not the read scan
  (fixed on `feat/read-at-into-open`). m375 remains the root fix; the
  isolation is filed to the compiler lane.

**Updated:** 2026-10-20 (stdlib read_at_into FALLBACK MEASURED -- branch
  ready, not merged): implemented the staged plan on
  **`feat/read-at-into-open`** (`b3707b3`, based on `f2ad364`; main stays
  on the released pin because v0.64.8 lacks the API):
  `byteio_read_at_into` + byte-level block/header decoders, and
  `block_store_open` now scans with ONE reused `Vec[UInt8]` buffer (no
  per-block Vec/payload). Early-warning 200k soak (order 64, 8192 cache,
  `XIOM_STDLIB=E:\\xiom-lang\\stdlib`, RAM-capped 4 GB): **engine 153 ms,
  exact verify, peak 895 MB, teardown 153 s** vs 940 MB / 251 s before.
  The scan/read path is fixed, but the plateau is **write-path/COW
  (Vec-drop elaboration)** -> m375 remains the root fix. Merge the branch
  at the next stdlib release; reported to stdlib + compiler. Main tree
  clean at `f2ad364`.

**Updated:** 2026-10-20 (stdlib `read_at_into` acked; adoption STAGED):
  stdlib landed `io.read_at_into(path, offset, buf: &mut Vec[UInt8], len)`
  on main (commit `9bad232`) -- the m375/A6 caller-buffer page-reader
  fallback -- and notified us (`REL-20261020-1731-stdlib`, acked). The
  compiler also acked `REL-20261019-2206-orbitdb` as m375, root cause
  measured: **Vec drop elaboration (not the arena)**; `read_at_into` is
  their low-risk fallback. **Adoption is STAGED, not landed:** our policy
  pins the RELEASED stdlib (v0.64.8), which lacks the API, so switching the
  pager read path now would break the default build. Plan: (a) add
  `byteio_read_at_into` + switch `block_store_open`'s scan/header reads to
  a reused UInt8 buffer at the NEXT stdlib release; (b) early-warning
  validate the 200k A6 soak with `XIOM_STDLIB=E:\xiom-lang\stdlib` (checkout
  has it at `xiom/io/io.xi:1087`); (c) report measured RSS/teardown on the
  stdlib item. m375 (compiler) remains the root fix. State: tree clean at
  `eb7c12a`; no other lane items.
**Updated:** 2026-10-19 (NIGHTLY WRAP -- owner away, work stopped; tree
  clean at `159e7ae`): session results after the v0.64.8 adoption:
  **admin web UI phase 1+2** (`admin/`, Pulse 0.3.1: dashboard, status,
  range pairs, lookup, token-gated put/delete/checkpoint; runners
  `scripts/admin.ps1|sh`; smoke green; new `db_file_range_pairs` API),
  **ST0 threads decision** (engine-actor per shard; real-thread/mutex spike
  40k increments x2 both), and **A6 soak** (GC store-reset lifetime fix;
  15k green; 200k at order 64 + 8192 cache = 252 ms engine, exact verify,
  19.9 MB snapshot, but **940 MB peak RSS and ~251 s teardown**; order 4
  = 57.8 GB/600 s). A6/1M is **BLOCKED on per-op allocation retention**,
  filed `REL-20261019-2206-orbitdb` (pushed `561e713`) -- compiler/runtime
  reclaim is the next unblocker (probe `tests/probes/probe_soak.xi`).
  **Final battery after the GC fix: suite 164/164 x2 Win + x2 WSL (ext4),
  db_crash 25/25 x2 both, probes (mvcc/fault/io/threads) x2 both, fuzz
  both, hybrid full 36 x2 both + crash 5/5 x2 both.** WSL `/mnt/e` DrvFs
  still stalls in `p9_client_rpc` on large snapshot I/O -- run the WSL
  battery from an ext4 copy. The 3h doorbell is intentionally STOPPED for
  the night; re-create on resume. Next: runtime memory reclaim -> 1M soak
  + BENCH memory row; admin phase 3 (sessions/ORBITWIRE attach) after ST1;
  G-START still needs M3 `file_lock`/cross-process pins.

**Updated:** 2026-10-19 (A6 SOAK: GC lifetime fix + scale memory finding):
  the A6 soak (`tests/probes/probe_soak.xi`, chunked build -> paged reopen
  -> chunked growth -> sample verify) exposed and fixed a **GC store-reset
  lifetime bug**: `ns_reset_paged` installed a local `BlockStore` into the
  longer-lived store; post-GC reads on the same handle hung (15k-key run
  CPU-bound, 61 MB snapshot valid). Replaced with `tree.store =
  ns_new_paged(fresh, count, capacity)`; 15k keys now **GREEN** (90 ms,
  exact verification, GC count 15,003 -> 14,991, blocks reset, tree walk
  14,991/14,991 reachable / 0 cycles / 0 OOB). **200k keys RED:** peak
  working set **~57.8 GB**, 600 s timeout at ~129k keys, snapshot 527 MB
  (one 4 KiB page per node). The pager cache/metadata are bounded, so the
  growth is per-I/O transient allocation (`read_at` -> Vec[UInt8] ->
  Vec[Int] 8x; `block_store_open` scans every block) -- filed
  `REL-20261019-2206-orbitdb` (pushed `561e713`). **Order 64 + an 8192
  cache (`ORBITDB_PAGER_CAPACITY`) makes 200k functionally GREEN** (252 ms,
  exact, 19.9 MB snapshot, 6,455 nodes) but peak RSS is **940 MB** and
  process teardown took **~251 s** -> per-op allocation retention; **A6
  not green / 1M blocked** until the runtime reclaim lands. BENCH-1
  section 7 carries the numbers.

**Updated:** 2026-10-19 (ST0 THREADS DECISION RECORDED + runtime spike): the
  Station concurrency decision is now explicit (docs/ISOLATION.md "Threads
  decision"): **one engine-actor thread per `DBFile`/shard; a handle never
  crosses threads**; scale-out is process-per-shard once M3 `file_lock` +
  cross-process pins land; thread-per-connection sharing one handle is
  deferred until in-engine synchronization + Send/Sync enforcement (m363).
  Rationale: read paths mutate the pager cache, pins/txn state are
  handle-local, and the stale-handle guard assumes one writer. Runtime
  evidence: new `tests/probes/probe_threads.xi` -- 4 real OS threads x
  10,000 mutex-guarded increments = 40,000 on **v0.64.8 Win + WSL**;
  `xiom.thread.spawn` + `xiom.sync.mutex` are usable. G-START checklist:
  threads decision [x]; remaining gates = M1.1b A6 soak + M3 file_lock.

**Updated:** 2026-10-19 (STATION ADMIN WEB UI -- phase 1 landed): the
  owner approved the Pulse web admin as the recommended admin shape (a
  separate client, pgAdmin-style; native SDL3+ImGui deferred -- imgui is
  headless-only today). New `admin/` app source-composes the Satellite
  engine (`../src`) + `xiom.pulse` 0.3.1: `admin/xiom.toml`,
  `admin/src/admin.xi`, `admin/src/index.html`, `admin/tests/seed_demo.xi`,
  `admin/README.md`. **Phase 1 + token-gated writes:** `/` dashboard, `/api/status`
  (file/engine/pager), `/api/range` key/value pairs, `/api/get`; POST
  `/api/put`/`/api/delete`/`/api/checkpoint` require `ORBITDB_ADMIN_TOKEN`
  (`X-Admin-Token`; reads are open on localhost unless a token is set).
  Localhost bind; clean shutdown via `X-Pulse-Quit`.
  New additive engine API **`db_file_range_pairs`** (the int range API
  returns values only) in `index/btree` + `engine.xi`, with dbfile suite
  coverage (24/24; suite total **164**). Runners `scripts/admin.ps1`
  (`-Database`; `-Db` collides with PowerShell's Debug alias) and
  `scripts/admin.sh`. Smoke: status/range/get/html 200 with exact JSON; token matrix
  (no token 401, token 200), put/get/delete/checkpoint exact, writes
  without the token 401, quit seam served (server exits). **Phase 1 owns the DB file**
  (no read-only open / cross-process pins yet -- M3 remainder); the Station
  will attach the same UI over ORBITWIRE at ST1. Reference rows added to
  REFERENCE-MATRIX 3.1; RUNBOOK admin section. Next: auth/session + query
  editor + write actions gated on the protocol, then optional native client.

**Updated:** 2026-10-19 (v0.64.8 verification DONE -- C-ORBIT-12/13 CLOSED):
  the released v0.64.8 archive (tag `4d040604b`; Windows zip `c31d9c46...`
  verified -> `%LOCALAPPDATA%\xiom-0.64.8` exe `ee3ee902...`; WSL
  `~/.local/share/xiom-0.64.8` bin `7c5b3482...`) fixes BOTH our compiler
  findings. **C-ORBIT-12 acceptance:** natural position tuple restored
  (cherry-pick of `f779c23` -> `0e92131`, comment conflict resolved), split
  suite **163/163 x2 Windows + 163/163 x2 WSL on a CLEAN HEAD worktree**,
  zero `Tuple__TValue__Int` warnings -- workaround retired; item CLOSED.
  **C-ORBIT-13:** `docs/repro/nested-mut-path/repro.xi` prints
  two-level/three-level/workaround all PASS (rc 1 by design = defect
  absent) on the archive; the pager's natural nested `&mut tree.store.bs`
  checkpoint is in the adopted tree -- verified + CLOSED. The v0.64.8 check
  row is filled (relays `6caa783`). **Ownership note:** the pin re-point
  (`dev-env.*` -> `xiom-0.64.8`) and the pager working-tree edits
  (snapshot/btree/repro) belong to the PARALLEL session (uncommitted at
  18:20Z) -- this session verified a clean HEAD in a separate worktree and
  did NOT touch those edits; the adoption commit is theirs to land.
  Pending after that: full battery re-run on the final tree
  (crash/probes/fuzz/hybrid) + BENCH rows at the pin move.
**Updated:** 2026-10-19 (M1.1b A5 LANDED -- deferred free + GC compaction,
  battery green): **A1-A5 complete.** Retire points: `cow_shadow`,
  `split_root`, `merge_children` (folded child + collapsed root), epoch =
  `pin_clock`, `live=false` but **dirty is NOT cleared** (a conservative
  retire must never suppress a flush). `ns_release_pending` runs at
  `db_file_snapshot_end` and after checkpoint commits; GC compaction in
  `v2_rewrite_all` (paged, no pins) BFS-walks the live root, remaps to dense
  ids, writes only reachable nodes, commits/renames, and `ns_reset_paged`.
  Reachability -- not the `live` hint -- decides what is dropped.
  **Three implementation traps found and fixed:** (1) skipping dead ids in
  the dirty scan lost data when a retire was conservative -- flushes now
  write every dirty id; (2) the C-ORBIT-13 workaround copied the BlockStore,
  so cache spills during the checkpoint bumped a different `block_count`
  and the two writers overwrote blocks once evictions occurred (new GC test
  exposed it) -- fixed with `ns_bs_put`/`ns_bs_commit`/`ns_bs_block_count`
  helpers on the REAL store; (3) `&mut db.tree.store` is a 3-level path and
  also copies -- `ns_release_pending` never ran (655 stale pending) until
  `btree_release_pending(&mut db.tree)`. **Evidence:** suite **163/163 x2
  Win + x2 WSL** (pager 3/3 incl. GC shrink + reopen), db_crash 25/25 x2
  both, probes x2 both, fuzz both, hybrid full 36 x2 both + crash 5/5 x2
  both. **Compiler:** v0.64.8 cut GO (`REL-20261019-1432-compiler-2`) --
  includes C-ORBIT-12/13; NO ACTION until the stdlib tag is live, then
  adopt, re-run the repros + suite, drop the C-ORBIT-12 tuple workaround and
  the C-ORBIT-13 helpers (keep the API shapes), and re-run the battery.
  **NEXT: A6 -- 1M-key memory soak + BENCH-1 memory row; then Station on
  G-START.**

**Updated:** 2026-10-19 (M1.1b A1-A4 LANDED -- v2 pager live, battery
  green): **`docs/checklists/m1-1b-pager.md` is the design of record.**
  A1: all node reads route through `ns_get`. A2: node page codec moved to
  `xiom.db.index.node_page`. A3: `NodeStore` gained a paged mode --
  `slots[id] -> frame`, 256-frame clock cache, per-frame dirty/ref bits,
  dirty-frame spill at `write_gen` (committed+1; own-writes-visible, a
  reopen ignores it), `ns_get` lazy-decodes on miss, `ns_push/ns_set` own
  growth; stats `[hits, misses, evictions, spills, corrupt, io]`. A4:
  `snap_load_v2` validates every page then discards it and builds the paged
  store; `snap_flush_v2` uses the store's OWNED `BlockStore` handle for
  spills + checkpoint (single `block_count`); `v2_rewrite_all` rebinds the
  pager after rename. v1 stays resident (auto-detect/migrate).
  **Two defects found and fixed:** (1) eviction left the victim's old id
  slot pointing at the reused frame -> wrong node at scale; the new pager
  suite (1200-key lazy/eviction + 1400-key spill/checkpoint) caught it.
  (2) **C-ORBIT-13**: `&mut` on a >=3-level nested field path silently
  copies Int/nested-struct state (Vec writes still leak) -- this made the
  paged checkpoint write at a stale `block_count` and drop the header
  update. Repro/README in `docs/repro/nested-mut-path/`, filed
  `REL-20261019-1209-orbitdb` (pushed, relays `4959cf1`); workaround =
  local copy + write-back in `snap_flush_v2`. **Evidence:** suite
  **162/162 x2 Win + x2 WSL** (new pager 2/2), db_crash 25/25 x2 both,
  probes mvcc/fault/io x2 both, fuzz both, hybrid full 36 x2 both + crash
  5/5 x2 both. Harness notes: run the crash/hybrid harnesses SEQUENTIALLY
  and never while another invocation is alive (a timed-out WSL hybrid run
  left a concurrent harness that false-REDded once; clean reruns 5/5 x2).
  The Windows host crashed once under the long suite (pagefile
  exhaustion); after the reboot the runs are green -- `wsl --shutdown`
  before Windows-heavy batteries. **NEXT: A5 deferred free / version GC +
  the 1M-key memory soak; then Station on G-START.**
**Updated:** 2026-10-18 (PAUSE -- owner away for the night, 19:45Z): the
  owner paused the session. The 3h relay doorbell cron is intentionally
  STOPPED (session-scoped) -- re-create on resume with `cron_create`
  `0 */3 * * *` (pull -> `view --lane orbitdb` -> process -> scoped
  commit/push). **State at pause:** R1 module split + R2 suite split DONE
  and committed; tree clean at `08d351c`; final-tree battery GREEN (suite
  160/160 x2 both via `scripts/suite.*`, db_crash 25/25 x2 both, probes x2
  both, fuzz both, hybrid probe full 36 x2 both + crash 5/5 x2 both).
  Lane heads: compiler v0.64.7, stdlib `stdlib-v0.64.7` (`1271dd5`),
  relays `4156410` (the last orbitdb item, `REL-20261018-1650`, was closed
  by the compiler lane -- fix `c6b3362ef`, not yet in a release).
  **Next on resume:** M1.1b pager (reference crawl first, REFERENCE-MATRIX
  1.1-1.3), then Station on G-START; the hardware power-loss matrix
  remains the other P-rc gate.
**Updated:** 2026-10-18 (R1+R2 SPLIT SESSION -- module split + suite split
  landed; battery green): **R1 module split DONE (owner directive).** The
  cycle-import spike GREEN with the correct struct syntax (`pub type X =
  { ... }`; multi-file `module` stays unsupported) -- cyclic modules AND
  `pub use` re-exports both work, so the facade shape is safe. Move-only
  split, one commit per step, suite 160/160 x2 Win+WSL after each:
  `src/index/btree.xi` (`xiom.db.index.btree`: B-tree, NodeStore, COW pin
  helpers), `src/engine/core.xi` (`xiom.db.engine.core`: in-memory
  WAL/Query/planner, legacy `Engine`, shared DBFile helpers),
  `src/engine/snapshot.xi` (`xiom.db.engine.snapshot`: v1/v2 checkpoint
  codec, compaction, pins), `src/engine/txn.xi` (`xiom.db.engine.txn`:
  `TxOp`, durable window, savepoints). `engine.xi` = `DBFile` + the
  file-backed public API + `Database` facade, 3462 -> **677 lines**; the
  four modules are re-exported with `pub use` so `use xiom.db.engine;` keeps
  the 0.2.x surface -- **zero consumer changes** (`git diff` over tests/apps
  empty; CLI builds unchanged). `package.xi` module list + ARCHITECTURE /
  SPEC / README / API / deep-dive docs realigned (deliberate
  engine<->engine.* cycle documented; tombstones noted). **R2 suite split
  DONE.** `tests/test_conformance.xi` (5988 lines) -> `tests/suite/`: 10
  area files (foundations 24, storage 21, wal_txn 13, schema_query 19,
  btree 10, engine_database 13, tuple_codec 14, typed_mvcc 15, dbfile 23,
  block_index 8) + `suite_common.xi` (pub helpers); summing x2 runners
  `scripts/suite.ps1` / `suite.sh` (per-file P/T, identical rounds, exit
  gate) -- **160/160 passed x2 across 10 files on BOTH platforms**; monolith
  retired. **Battery on the final tree:** suite 160/160 x2 both; db_crash
  **25/25 x2 Win + x2 WSL**; probes mvcc/fault/io x2 both; fuzz seeds=4
  both; hybrid probe full 36 checks x2 both + hybrid crash 5/5 x2 both.
  **Harness lesson:** the Windows and WSL crash harnesses share the fixed
  `probe-logs/crash-dbfile*.wal` paths -- never run them concurrently (the
  initial parallel run false-REDded; sequential runs are green). Doorbell
  processed: compiler `REL-20261018-1650` (closed by them -- two-module
  minimal reproduced C-ORBIT-12; fix `c6b3362ef`; our suite 160/160 on
  their branch `f779c23`; not in v0.64.7, workaround stays). Next: M1.1b
  pager (reference crawl first).
**Updated:** 2026-10-18 (SESSION WRAP -- context budget; v0.64.7 adopted,
  BENCH matrix complete, R1/R2 spike partial): **Landed today:** v0.64.7
  adopted on BOTH platforms (Windows official zip sha `16a436c4...` verified
  -> `xiom.new-20261018-1415` exe `592aa125...`; WSL lane-local tarball
  `153f0cc9...` -> `~/.local/share/xiom-0.64.7` bin `302d3192...`; shared
  canonical untouched); **full battery + hybrid guard GREEN** (suite 160/160
  x2 both, crash 25/25 x2, probes x2, fuzz; hybrid probe 36 + crash 5/5 x2
  both against xvector `72db35e`). **BENCH-1 absolute rows captured** (the
  last P-rc measurement; quiet-ish window, floor 43-45%, one UNKILLABLE
  stuck lld-link from 2026-10-17 burns a core): Windows load **947 / 1,552 /
  1,435** vs 611/885/1,136 = **+55% / +75% / +26%**; **A/B 5/5 median
  1.28x**; WSL R1 106 / R2 7,225 / R3 23,126 / R4 109 (DrvFs-fsync-bound);
  full matrix + raw logs in `docs/BENCH-1.md` section 4a. **C-ORBIT-12
  residual re-tested on v0.64.7: STILL RED** (154/160, same unknown-type
  warning; minimal repros green) -> `REL-20261018-1416-orbitdb-2`, rows
  updated, workaround stays. **Engine A09 v0 ack -> mapping reply filed**
  (`REL-20261018-1416-orbitdb`): open/put/get/del/typed/txn/savepoints/
  flush+durability map today; differences = explicit close, collections,
  CURSORS, stats, one-call backup; collections/cursors are 0.3 candidates.
  **R1/R2 spike (partial, context cut):** multi-file `module` NOT supported
  (W001; second file ignored) -> the split must use SEPARATE modules; the
  cycle spike hit P001 from wrong struct syntax -- next session must consult
  `xiom_xiom_cheatsheet` (structs) and redo it before choosing the split
  shape (cycle-capable: internals take `&mut DBFile` with public types in
  engine.xi; else one-way leaf split first). Satellite stays LIVE (0.2.1,
  eco-v0.1.196) + verified; xvector consumed it. Lane heads: compiler
  v0.64.7, stdlib `stdlib-v0.64.7` (`1271dd5`), relays `e043e71` (+ ours
  `6abdace`); tree clean at `52a70d7` + this wrap. Next: finish R1/R2 spike
  -> move-only split; then M1.1b pager (matrix rows ready); Station on
  G-START; power-loss matrix remains the other P-rc gate.
**Updated:** 2026-10-18 (v0.64.7 ADOPTED + full battery GREEN + BENCH-1 rows
  captured): lane pin re-pointed to v0.64.7 on BOTH platforms -- Windows
  official extract `%LOCALAPPDATA%\xiom.new-20261018-1415` (zip sha
  `16a436c4...`, SHA256SUMS-verified; exe sha `592aa125...`), WSL
  lane-local install `~/.local/share/xiom-0.64.7` (tarball sha
  `153f0cc9...`, bin sha `302d3192...`; the shared canonical stays v0.64.6
  for ops). Battery on the new pin: suite 160/160 x2 Windows + x2 WSL;
  db_crash 25/25 x2 (Win+WSL); probes mvcc/fault/io x2 both; fuzz seeds=4;
  hybrid guard re-run GREEN (probe 36 checks + crash 5/5 x2 both; xvector
  `72db35e`). **C-ORBIT-12 residual still RED on v0.64.7** (154/160 with
  the position tuple; same warning) -- workaround stays; residue evidence
  filed. **The absolute BENCH-1 rows are finally captured** (quiet-ish
  window: floor 43-45%, zero lane compiles; one UNKILLABLE stuck lld-link
  from 2026-10-17 burns ~1 core): R1 **947** (vs 611), R2 **1,552** (vs
  885), R3 **1,435** (vs 1136) ops/s load; docs/BENCH-1.md section 4a +
  raw logs `bench-cross-20261018-1831{18,233}` / `-183425.txt`; A/B 5/5
  pairs, median **1.28x**. Next: R1/R2 split -> M1.1b pager; Station on
  G-START. Lane heads: compiler v0.64.7, stdlib pin `stdlib-v0.64.7`
  (`1271dd5`), relays `e043e71` (+ our `6abdace`); tree clean.
**Updated:** 2026-10-18 (relay check + v0.64.7 re-verify):
  v0.64.7 shipped 2026-10-17T22:59Z (assets incl. linux-arm64; stdlib pin
  `stdlib-v0.64.7` tag `1271dd5`); downloaded the official windows-x64 zip
  (sha256 `16a436c4...`, verified vs SHA256SUMS) into a new ADDITIVE extract
  `%LOCALAPPDATA%\xiom.new-20261018-1415` (exe sha `592aa125...`); WSL
  canonical is still v0.64.6 and the lane pin is still v0.64.6 -- adoption
  (pin re-point + full battery both platforms) is the next task. **C-ORBIT-12
  residual re-tested: STILL RED on v0.64.7** -- minimal repros green, but
  the larger-program position-tuple acceptance is 154/160 with the SAME 6
  typed-value failures + the same twice-emitted `unknown type
  'Tuple__TValue__Int'` warning; control 160/160 with the workaround. Filed
  `REL-20261018-1416-orbitdb-2` (high) + updated the v0.64.7 check row;
  workaround stays (tuple.xi comment now records the v0.64.7 evidence).
  **Engine A09 v0 ack processed**: intended surface = open/close;
  collection put/get/del + batch; prefix/range scan WITH CURSORS; atomic
  batch; flush/sync + durability knob; stats/compaction; export/backup;
  bytes+typed wrappers. Mapping reply filed
  (`REL-20261018-1416-orbitdb`): open/put/get/del/typed/txn+savepoints/
  flush+durability map today; DIFFERENCES flagged -- no explicit close
  (flush+drop), no collections (key-prefix ranges today), NO cursors
  (materialized range only; M1.1b-adjacent), minimal stats, backup =
  checkpoint+copy recipe. They ack/flag early; collections/cursors are 0.3
  candidates. Bus `6abdace`; doorbell re-armed (3h). Remaining P-rc inputs:
  absolute BENCH rows + hardware power-loss matrix + M1.1b pager.
**Updated:** 2026-10-18 (PAUSE -- owner away for the night, 21:34Z): the
  owner paused the session. BOTH recurring watches are STOPPED: the
  perf quiet-window retry chain (the 21:32Z retry already fired into the
  pause; no further wakeups) AND the 3h doorbell cron (intentionally
  deleted -- re-create on resume: `cron_create` `0 */3 * * *`, pull ->
  `view --lane orbitdb` -> process -> scoped commit/push). **State at
  pause:** `xiom.orbitdb` 0.2.1 LIVE (eco-v0.1.196, sha `c8fc6548...`) +
  independently verified from the registry (isolated-home consumer smoke);
  xvector consumed it (their 11-check probe green) and our hybrid guard is
  GREEN on their settled tree `72db35e` (probe 36 checks, crash 5/5 x2
  both); announcements to engine/registry/xvector filed; v0.64.7 still
  BLOCKED upstream (stdlib m353 `.hash()` residual, dry-run 955/956).
  **Open items for resume:** absolute BENCH-1 R1-R3 on the v0.64.6 release
  pin (quiet host -- overnight may be the window, but we stay paused);
  engine A09 verb list + registry/engine replies; R1/R2 split -> M1.1b
  pager (reference rows ready) -> Station on G-START. Tree clean at
  `b337f30`; relays `9360c9d`.
**Updated:** 2026-10-17 (hybrid guard GREEN on xvector's settled tree --
  cross-lane proof of the published package): xvector consumed `xiom.orbitdb`
  0.2.1 (their `probe_package_orbitdb` 11 checks green x2 WSL + x1 Windows,
  commit `72db35e`) and declared their tree settled at compiler v0.64.6 +
  stdlib `7073a64`. Their tree consolidated `xiom.vector.types.*` into the
  published `xiom.vectors` package, so our hybrid harness was brought to
  lockstep: `tests/hybrid/xiom.toml` `xiom.http` 0.1.4 -> 0.1.8 (mirrors
  their manifest) and `probe_hybrid.xi` imports `xiom.vectors` (types
  package) instead of the removed `xiom.vector.types.dense_vector/metric`
  modules. **Guard results: `probe_hybrid` full GREEN (36 checks) Win x1 +
  WSL x2; `hybrid_crash_test` GREEN 5/5 Win x2 + WSL x1 (repair 13 rows,
  100% join integrity, verify #2 idempotent repaired=0; row store survives
  hard kill + torn tail).** TASK ORDER item 6 DONE; re-run at every wrap.
  Relays: reply item to xvector with the evidence.
**Updated:** 2026-10-17 (Satellite canary PUBLISHED + independently verified):
**xiom.orbitdb 0.2.1 is LIVE on the registry** -- eco-v0.1.196,
2026-10-17T14:18:14Z, sha256 `c8fc65485b7dbedc...`, signed + live-verified;
the packages lane carved read-only via `git archive 3bc2a61` (166 files,
primary id held, no fallback) and their verify on the carved layout was
suite 160/160 x2 + db_crash 25/25 + mvcc 36 + fault 56 + io 30 green; scope
LIVE eco-release 563, allowlist 561->564. **Our independent verify:**
installed from the registry into an ISOLATED XIOM_HOME and built+ran a
consumer smoke with a project-manifest dependency only (no source-roots):
in-memory facade + durable `db_file_*` WAL + checkpoint + reopen + typed
payload + range -> `consumer smoke: OK`, rc 0. Item
`REL-20261017-1245-orbitdb` verified + CLOSED; announcements filed: engine
(`REL-20261017-1504-orbitdb`: recipe + A09 verb-list request), registry
pilot (`-2`: pre-P-rc canary note), xvector (`-3`: hybrid-guard input).
**Doc nit found:** the published README still imports
`xiom.db.api.database` (merged into `xiom.db.engine`) -- fixed repo-side,
rides 0.2.2. Remaining P-rc: M1.1b pager, hardware power-loss matrix,
absolute BENCH-1 rows. Relays `1d08044`.
**Updated:** 2026-10-17 (Satellite CANARY frozen + filed to packages):
`package.xi` rewritten to the canonical published shape (the old manifest was
STALE: `xiom-db 0.2.0` with retired `xiom-core` / `xiom-std 0.1.0` deps) --
`xiom.orbitdb` v0.2.1, stage incubating, Satellite identity, 30 `xiom.db.*`
modules, zero registry deps (`xiom.std` platform only); validated with
`xiom pkg --root . lock` -> "xiom.orbitdb v0.2.1" (no lockfile needed);
frozen at commit `3bc2a61`. Coordination item
`REL-20261017-1245-orbitdb` filed to packages (pulse-style): candidate ids +
scope + P-rc/canary notes + carve-mechanic question (porter from the private
pin vs a git-archive export); their carve/validate/suite x2/ops-scope/
allowlist/batched publish/sha-verify follows, then we announce to engine
(A09 embedded lite tier) / registry pilot / xvector. Pre-P-rc canary note:
pager M1.1b, hardware power-loss matrix and absolute BENCH rows still
pending; all freeze gates green (suite 160/160 x2 both, crash 25/25 x2,
probes + fuzz on the RELEASED stdlib v0.64.6). Relays `a804b6a`.
**Updated:** 2026-10-17 (reference protocol recorded + v0.64.6 ADOPTION
  battery, with a corrected verdict): owner directive recorded as
  NON-NEGOTIABLE (commit `fbc009c`): the cloned battle-tested trees under
  E:\repos are the design source -- crawl -> `docs/REFERENCE-MATRIX.md`
  rows (seeded for M1.1b from sqlite/bbolt/redb, file:line verified) ->
  convert to XIOM -> blockers relay + re-test; no design from memory, no
  MVPs. Adoption: pin re-pointed (`dev-env.*` -> Windows
  `xiom.new-20261016-233955` sha `0ff5c5c4...`; WSL canonical sha
  `855bd7cc...`); battery GREEN -- suite 160/160 x2 Win + x2 WSL, db_crash
  25/25 x2 (Win + WSL), probes mvcc 36 / fault 56 / io 30 x2, fuzz seeds=4
  (orders 3/4/5); then RE-RUN on the RELEASED bundled stdlib v0.64.6 after
  the owner's freshness directive: suite 160/160 (Win x2 incl. quiet retry,
  WSL x1), db_crash 25/25, probes 3x, fuzz GREEN -- and `dev-env.*` now
  DEFAULTS to the release stdlib (checkout opt-in; it was diverged + dirty). **C-ORBIT-12 verdict CORRECTED:** the workaround-drop
  attempt (position tuple in tuple.xi) proves the LARGER-PROGRAM
  silent-mode shape is STILL RED on v0.64.6 (`unknown type
  'Tuple__TValue__Int' -- defaulting to i64`; 6 typed-value suite tests
  fail, 154/160); workaround RESTORED (160/160), residual filed
  `REL-20261017-1154-orbitdb` (high; v0.64.6 + v0.64.7 check rows
  corrected; relays `c260c07`). E001 `moved value 'bytes'` (4518:76/77) is
  OUR `src/storage/block.xi` and is a SPURIOUS report on a borrowed
  `&Vec[Int]` read path -- filed `REL-20261017-1223-orbitdb-2` (low);
  transient Windows compiler exits -1 under load (2/6 runs, rerun green)
  filed `REL-20261017-1223-orbitdb` (medium). **Absolute BENCH-1 rows still
  pending** (host carried lane compiles all morning -- gate never quiet;
  next quiet window / after the v0.64.7 wave). Lane heads: compiler v0.64.6
  released + v0.64.7 pre-cut; stdlib RELEASE 0.64.6 published (registry
  sha `7ba3b09a`, waves 155-171); relays `ea1e7b7`; registry latest:
  btree 0.1.1 / wal 0.1.0 / vectors 0.1.0 (installed), metrics+rate 0.2.0,
  http 0.1.8 (hybrid mirror).
**Updated:** 2026-10-17 (PAUSE -- owner away until tomorrow): the owner
  paused the session at 23:19Z. BOTH recurring watches are now STOPPED (a
  change from the entry below): the perf wakeup retry is cancelled (the
  absolute rows were already deferred to the v0.64.6 adoption battery) AND
  the 3h doorbell cron was intentionally deleted -- on resume, RE-CREATE it
  (`cron_create`, pull -> `view --lane orbitdb` -> process -> scoped
  commit/push) and start the adoption half of task-order item 1: dev-env.*
  re-point to v0.64.6 + suite x2 both + crash/probes + the C-ORBIT-12
  workaround-drop check + the perf rows. Tree clean at pause; our last
  relays push `e32c0e3`; nothing in flight anywhere.
**Updated:** 2026-10-17 (perf wakeup -- verified the parallel session's
  v0.64.6 work; wakeup chain ENDS): C-ORBIT-12 is **verified + CLOSED** on
  the released archive (repro `sum=110` x2 platforms + control + u8 +
  09/11 regressions green; item closed, check-file rows filed by the
  concurrent lane session). Fleet state: **WSL canonical = v0.64.6**;
  Windows archive extracted at `%LOCALAPPDATA%\xiom.new-20261016-233955`
  (`xiom.exe` sha256 `0ff5c5c471498d8c...`, reports v0.64.6; naming is
  DATE-SUFFIXED this time, not `xiom.new.0646`); the **lane pin
  (`scripts/dev-env.*`) is still v0.64.5** -- re-pointing + the adoption
  battery (suite x2, crash, probes, then the workaround-drop check + perf
  rows) is the owner session's remaining half of task-order item 1/2.
  Win home clobbered by the v0.64.6 swap AGAIN (3rd occurrence; btree/wal
  reinstalled additively; ops FYI `REL-20261016-2120-orbitdb` needs a
  reread as "snapshot-before-swap" is the standing ask). **Perf absolute
  rows: DEFERRED to the adoption battery on the v0.64.6 pin** (running
  them on 0645 now would be superseded immediately; the relative A/B
  1.26x median is already on record). **No further perf wakeups -- this
  chain ends; the doorbell cron remains the only recurring watch.**
**Updated:** 2026-10-16 (doorbell 21:00Z -- **v0.64.6 RELEASED**): relays
  `2291513`. `REL-20261016-2034-compiler` (to:all, high): v0.64.6 published
  20:33Z (run 38962236697 GREEN; stdlib pin `b81430ba`; **m336 canonical
  tuple naming in every position = the C-ORBIT-12 family fix**); the item
  names ORBITDB's re-run explicitly (enum-tuple repro + t3..t9 bisect).
  Our release-check row: m336 integrated, repro+control green on the
  integrated build, **archive re-verify pending**. Protocol note: to:all
  items cannot be acked by us (only the reporter lane/owner) -- the SESSION
  record + the verdict rows are our tracking. **Adoption queued FIRST for
  the next owner session** (owner-gated, v0.64.5 flow): shadow `xiom.new.
  0646` + WSL canonical, suite x2 both, then C-ORBIT-12 repro + t3..t9 +
  08A/09/11 bundles + row `-2`, then verdicts on `compiler-compiler-v0.64.6`
  (+ the 1945 family row); workaround retirement contingent on the wide
  shape passing. Also noted: the concurrent session's correction that WSL
  /proc/loadavg reads phantom (~90) -- check `ps`/`free` instead for the
  perf attempt #5 at 22:31Z.
**Updated:** 2026-10-16 (perf A/B under sustained load -- relative number
  landed): `probe_wal_ab.xi` 10 interleaved old-vs-new pairs (N=2000) at
  20:35Z (CPU ~90%, WSL load ~130): **median ratio 1.26x, mean 1.31x
  (min 1.04, max 1.79), 10/10 pairs favor the held-handle shape** -- the
  interleaved ratio is load-robust. Recorded in `docs/BENCH-1.md` finding
  1. Absolute BENCH-1 rows still await a quiet host (attempts #2-#4 all
  saw CPU >= 90% / WSL load 92-129; next check 22:29Z). v0.64.6 not
  released yet (compiler m344/m345 fix wave in flight). Relays `395bc40`,
  lane clean (all items acked).
**Updated:** 2026-10-16 (doorbell 18:00Z): relays `676a0c3`. One new
  orbitdb item processed: `REL-20261016-1724-website` -- site status pass --
  ACKED with: fsync-row precision (their correction overstates remaining
  work: commit-time hardening is DONE; the hardware power-loss matrix is
  the remaining step) + TWO-TIER COPY APPROVED (one word: 'until the TLS
  server binding lands'; shorter hub-card clause offered; a public-safe
  pre-alpha state row supplied). No newer archive; no release-check
  changes. Perf re-measure attempt #3 armed for 18:29Z.
**Updated:** 2026-10-16 (doorbell 15:00Z): relays `b649d94`. No new
  orbitdb-addressed items; no newer archive/release-check. One to:all
  recorded as ORBITDB-relevant: `REL-20261016-1446-packages` -- fleet
  codename convention (registry tier = Beacon/**Satellite**/mote;
  standalone = **Station**/lattice; registry ids unchanged); folded into
  `docs/TWO-TIER-ARCHITECTURE.md` section 1. (`-1304` xiom.http rider and
  `-1429` xiom.pulse extraction = noise for this lane.) 2h perf re-measure
  wakeup still armed (16:29Z).
**Updated:** 2026-10-16 (SESSION WRAP FOR HANDOFF -- context-budget; clean
  handoff): tree `b3fef97`; relays `e30cda1`. **Landed this session on top
  of the earlier v0.64.5 wave + two-tier plan:** (1) **BENCH-1**
  (`f6a212b`): cross-engine bench harness + first numbers (probe_ycsb.xi,
  bench/bbolt Go driver v1.4.3, bench_cross.{ps1,sh}, docs/BENCH-1.md;
  verify parity everywhere; Windows R1-R4 + WSL R1/R3 captured); finding:
  Windows writes syscall-bound not fsync-bound (611/s durable per-op vs
  16.6k/s WSL nosync). (2) **WAL held-handle perf slice** (`21ea76a`,
  docs `b3fef97`): append+sync ONE handle per record
  (`wal_file_append_sync`/`_tagged_sync`); txn window on ONE held fd
  (`db_file_txn_*`; checkpoint already refuses mid-txn); `byteio_*_fd`
  helpers (appends UNGATED -- fault arming counts unchanged); WAL
  byte-equivalence proven (negatives/zero/i64 extremes byte-identical);
  `probe_wal_ab.xi` A/B tool. Verification: Win suite 160/160 x2 +
  fault 56/56 x2 + io 30/30 x2 + crash 25/25 x2; WSL suite 160/160 x2 +
  probes GREEN x2 + crash 25/25 x2 (stock pin). **PERF RE-MEASURE PENDING:
  the shared host sat at CPU 100% during the window (A/B noise ~10x; first
  clean pair 1.6x new) -- run BENCH-1 R1-R3 + probe_wal_ab FIRST next
  session on a quiet host and update docs/BENCH-1.md findings 1/2.**
  Doorbells processed: packages-3 acked + fsync-caveat correction (durable
  no-op caveat stale post-waves-115/118); engine embedded-tier intent acked
  (package-shape confirmed); **packages-2 = STANDING REGISTRY PIPELINE for
  Satellite (owner directive 13:21Z): freeze -> coordination item (ids +
  scope + P-rc notes) -> their carve/validate/suite/ops-scope/allowlist/
  batched publish/verify; Station stays our standalone releases. Fresher:
  xiom.ssl LANDED (binding), xiom.otel LIVE (eco 0.1.188), brotli landed /
  zstd live.** stdlib checkout WIP likely fixed (`<netinet/tcp.h>` now
  present at `6c96bbb`; verify before dropping `BENCH_STOCK_STDLIB=1`).
  **SESSION-SCOPED state (dies with this session): the 2h perf wakeup and
  the 3h relay doorbell cron -- the next session MUST re-create the
  doorbell and run the re-measure itself.** Lane heads: orbitdb `b3fef97`,
  relays `e30cda1`, stdlib `6c96bbb`, compiler `c24a6dcc`, xvector
  `a94cb9b`, engine `0e662bf`, packages `4a69704b`.
**Updated:** 2026-10-16 (perf slice LANDED -- WAL held-handle writes,
task-order item 1): `wal_file_append_sync`/`_tagged_sync` (auto-commit: ONE
held handle per record incl. the durability fsync), `byteio_open_append`/
`append_fd`/`sync_fd`/`close_append` (ungated appends -- arming counts
unchanged by design; the sync seam gates exactly as before), and the
transaction window (`db_file_txn_begin/put/delete/commit/abort` +
savepoint splice) rides ONE held fd per transaction (lazy open, closed on
every exit path; checkpoints already refuse mid-txn so truncate/rename
never races the fd); `db_file_commit_sync` retired (dead). Verified on
Windows: suite **160/160 x2**; fault probe **56/56 x2**; io-primitives
**30/30 x2**; db_crash **25/25 x2**; WAL byte-equivalence probe (negatives/
zero/i64 extremes byte-identical to the old writer); new tracked A/B probe
`tests/probes/probe_wal_ab.xi` (interleaved old-vs-new). **Perf number
re-measurement PENDING a quiet host** (shared machine at CPU 100% during
the window: in-process A/B noise ~10x; first clean pair N=800 read 1.6x in
favor of the new shape). WSL battery DONE after the commit: suite 160/160
x2, probes (mvcc/fault/io) GREEN x2, db_crash 25/25 x2 -- stock pin
(`BENCH_STOCK_STDLIB=1`; stdlib checkout WIP). Next: BENCH-1 R1-R3 re-run
on a quiet host (scheduled wakeup; shared machine was at CPU 100%).
**Updated:** 2026-10-16 (BENCH-1 LANDED -- cross-engine bench harness +
first numbers): `docs/BENCH-1.md` + `tests/probes/probe_ycsb.xi` +
`scripts/bench_cross.{ps1,sh}` + `bench/bbolt` (Go driver, bbolt v1.4.3;
cross-built linux binary). ORBITDB vs SQLite 3.54.0 (pinned CLI both
platforms; `synchronous=FULL` rows) vs bbolt on identical deterministic
YCSB-ish phases (shared LCG, bitmap-distinct delete accounting) with per-row
verify parity (all engines report identical counts, both platforms).
Windows R1-R4 captured: **R1 durable per-op: ORBITDB 611/s, SQLite 1457/s,
bbolt 579/s; R4 (100-byte typed rows): 464 vs 1356 vs 489**; WSL R1
(fsync-depressed under load ~50) + R3: **ORBITDB 16.6k/s nosync --
FINDING: Windows writes are syscall-bound, not fsync-bound; group commit
amortizes only the sync, not the per-record appends; the held-handle byte_io
path is the fix -> task-order item 1 (perf slice).** SQLite CLI read/scan
numbers are driver-bound (documented, not comparable head-on). WSL runs
default to `BENCH_STOCK_STDLIB=1` (stock pin baseline) -- required while the
stdlib lane's checkout carries a Linux-compile WIP (TCP_NODELAY include;
heads-up filed `REL-20261016-1223-orbitdb`). WSL R2/R4 pending on a quieter
host.
**Updated:** 2026-10-16 (doorbell 12:00Z): relays `cb1f590`. One new
  orbitdb item processed: `REL-20261016-1150-packages-3` -- packages'
  point-by-point answer to the station wishlist (`-1128-orbitdb-2`) --
  ACKED with our read: **`xiom.ssl` build STARTED at bindings** (client +
  server contexts, cert/key/chain, ALPN, verify modes; first publish waits
  on the ops registry scope; station v1 stays trusted-network/local-only
  until then); **`xiom.postgres.wire` surface CONFIRMED reusable +
  documented** (module boundary commitment; we file the ST1 interop item at
  protocol freeze); **`xiom.durable` ST4 fit accepted** (local log leg:
  LSN single-writer, `wal_read_from` cursor, checkpoint-gated retention --
  plus our thin ship loop; caveat: durable's `wal_flush` is still an honest
  no-op, so the engine WAL remains the power-loss-honest path); otel gauges
  = scoped 0.2.0 for ST6; zstd already real (0.3.0), brotli in flight.
  Confirmations folded into `docs/checklists/two-tier.md` (ST1/ST4/ST6).
  No other new lane items; no newer archive.
**Updated:** 2026-10-16 (station dependency wishlists filed): to clear the
  road ahead of G-START, the Station's cross-lane dependencies are on the
  bus: `REL-20261016-1128-orbitdb` (stdlib: **`file_lock` -- hard gate for
  the M3 remainder/G-START**; TLS + ALPN server side; TCP session
  ergonomics -- NODELAY/half-close/timeouts/multi-listener accept; CSPRNG +
  password KDF; monotonic clock) and `REL-20261016-1128-orbitdb-2`
  (packages: TLS binding folded with PULSE's ask; `xiom.postgres` wire-codec
  kept reusable for ST1 interop + optional ST8 facade; `xiom.durable` fit
  check for ST4; OTLP gauges; real zstd/brotli; + the early heads-up that
  Satellite publication will open a coordination item). Both reference the
  pulse-5 lane asks to avoid duplication; the architecture doc's risk
  section cross-links them. Doorbell handles the acks.
**Updated:** 2026-10-16 (owner directive addendum -- release coordination):
  **Satellite publication** = when the tier is ready to publish on the
  registry, ORBITDB opens a relay item to the **packages lane** for
  publishing coordination (packaging assist: scope/recipe/canary; ops owns
  the allowlist gate). **Station releases** = GitHub Actions pipeline, set
  up by **ops** (this lane provides the build/test/soak contracts + the
  pinned-toolchain recipe; registry involvement limited to a future station
  client package). Recorded in `docs/TWO-TIER-ARCHITECTURE.md` sections 5-6,
  the two-tier checklist release-engineering section, PRODUCTION-PLAN
  section 15, and the task-order hygiene line below.
**Updated:** 2026-10-16 (owner directive -- two-tier plan commissioned): the
  product line is formally planned: **orbitdb-satellite** (embedded; today's
  engine under a product label -- package/module names unchanged, no rename)
  + **orbitdb-station** (PostgreSQL-class server tier, same repo under
  `station/`, consuming the engine as a library, never a fork). Artifacts:
  `docs/TWO-TIER-ARCHITECTURE.md` (vision/naming, repo layout, mermaid
  target architecture, ST0-ST7 milestones with exit criteria, risks),
  `docs/checklists/two-tier.md` (gated step-by-step; **G-START = M1.1b +
  M3 remainder + R1/R2 split + threads decision**), PRODUCTION-PLAN section
  15 (plan-of-record pointer; 1.0 non-goals line updated). Station work does
  NOT start before G-START; the embedded release path outranks it. Substrate
  fits: WAL = ordered oplog (log shipping), generation checkpoints + v2
  blocks + migration = snapshot bootstrap/transfer, hybrid composition =
  build shape now / registry package later; **ORBITWIRE v1** protocol
  planned with `xiom.postgres` as the interop reference; PG-wire facade =
  optional post-ST7 evaluation only.
**Updated:** 2026-10-16 (doorbell 11:00Z): relays `f221fd3`. No new
  orbitdb-addressed items; `REL-20261015-2202-pulse-5` (to:all, PULSE
  top-tier directive) reviewed -- the asks went to stdlib/compiler/packages/
  ops, nothing ORBITDB-actionable, no reply required. **Release-check
  `compiler-compiler-v0.64.5` appeared (cut 2026-10-15T21:03Z) and now
  carries verdicts for BOTH orbitdb rows: `1945-orbitdb-2` VERIFIED+CLOSED
  (08A/08B/09/10/row-2 all settled on the official artifacts x2 platforms;
  DONE criterion met -- bundle READMEs flipped), `2022-orbitdb`
  (C-ORBIT-12) STILL RED with the reduced repro + int-error control.** When
  a fix lands, re-run `docs/repro/enum-tuple-codegen/repro_enum_tuple_enum_error.xi`
  + the 08A/09/11 regression bundles at the next archive. (Hygiene note: the
  shared relays clone had concurrent writers -- our release-check cell edits
  rode the playground lane's scoped commit `3b52e59`; content verified on
  origin, no re-commit needed.)
**Updated:** 2026-10-16 (station wishlist reply processed): packages
  answered `REL-20261016-1128-orbitdb` (+`-1128-orbitdb-2`)
  point-by-point (`REL-20261016-1150-packages-3`, acked): **xiom.ssl build
  STARTED at bindings** (client+server, ALPN; publish waits on the ops
  scope -- our station v1 trusted-network/local-only decision stands until
  then); **xiom.postgres wire codec CONFIRMED reusable as-is** (commitment:
  module boundary + SPEC stay current; we file the ST1-freeze interop item
  -- loopback + read-only fixtures); **ST4 log-shipping**: plan the LOCAL
  leg on xiom.durable per their guarantees sheet (single-writer LSN logs,
  read-from-LSN cursor, checkpoint-gated retention, typed errors) with the
  ship loop ours; **carve-out raised: their "fsync no-op" caveat is STALE
  at the stdlib level** (waves 115/118 landed, consumer-verified on
  v0.64.5) -- if `xiom.wal`/`xiom.durable` 0.1.0's `wal_flush` still
  resolves to the old stub, ST4 needs a package re-release with the real
  flush or the station on the engine WAL (real fsync at commit acks); asked
  which. OTLP rides the ops scope; zstd real / brotli in flight; satellite
  publication coordinated at P-rc. Relays head `011cda0`.
**Updated:** 2026-10-16 (v0.64.5 re-verification wave COMPLETE -- clean
  handoff): everything the 2026-10-15 wrap queued is LANDED and green on the
  STOCK v0.64.5 pin (tree `0911516`; the entry below's "FIRST task" list is
  DONE). **Battery x2 both platforms:** suite **160/160 x2 Win + x2 WSL**;
  db_crash **25/25 x3 Win + x2 WSL** (harness fixed -- below); probes mvcc
  36 / fault-sync 56 / io-primitives 30 checks ALL GREEN x2 both; fuzz x2
  both (seeds=4 ops/seed=4000); soak 2000 keys / 9 checkpoints OK x2 both;
  bench fresh under shared-machine load (Win
  wal_append 1.7k/s, WSL 33.8k/s; insert 513k/333k; replay 109k/4.3k);
  registry consumer probes x2 platforms: btree digest
  `850,244,294,903,48,601,650,780,133,311` IDENTICAL package/engine/Win/WSL,
  wal 18 checks. **Bundle verdicts (official artifacts, x2 platforms):
  C-ORBIT-08A FIXED (m305; `n=8`/`custom=5` -- the old README expected-line
  was miscomputed), 08B fixed + masks RETIRED, C-ORBIT-09 FIXED (m302;
  residual caveats stay -- `node_deep_copy` remains the ownership
  guarantee), C-ORBIT-11 FIXED (m298; `compose ok` on the stock pin),
  row `-2` FIXED (m304; `src/engine.xi --check` rc 0), C-ORBIT-10 RETRACTED
  (rc=1 BOTH platforms; the rc=0 artifact was the `xiom-dbg` DAP adapter --
  the WSL side of the original matrix ran the wrong binary).** NEW:
  **C-ORBIT-12** filed (`REL-20261015-2022-orbitdb`): `Result[(Enum, Int),
  Enum]` still emits two names for one tuple struct (clang hard error; or
  i64-default + silent misdecode in larger programs); minimal repro in the
  bundle; the `DbResult[TValue]` position workaround STAYS. **Bus:** 4
  verdicts verified (1219/1659/1956/-2), `1358` verified + closed
  (retraction), C-ORBIT-12 + ops note (`REL-20261015-2023-orbitdb`: the
  fleet swap reset the Windows registry home to 11 packages; btree/wal/
  vectors reinstalled ADDITIVELY, WSL home untouched) -- pushed `c4e9d74`.
  **Harness hardening (`0911516`):** crash polls read with delete-sharing
  (plain `Get-Content` raced the writer's temp+rename truncate and false-RED
  with `observed=28/30`; the truncate is best-effort by design -- recovery
  gates on the snapshot `checkpoint_lsn`); put1 retries once with `[WARN]`;
  `*.tmp` scratch ignored; RUNBOOK updated (env table v0.64.5, 160 tests,
  NEW gotchas). **Hybrid DEFERRED:** xvector's tree (HEAD `99f879f` + WIP)
  moved `xiom.vector.types.*` -- probe full fails `unresolved import
  'xiom.vector.types.dense_vector'`; theirs to settle; last green = their
  `200cbc7`; re-run at the next wrap. Next session: BENCH-1 -> R1/R2 ->
  M1.1b (TASK ORDER below). Lane heads: orbitdb `0911516`, relays `d8e99c4`,
  stdlib `ab9cd07`, compiler `d4fdd7e7`, xvector `99f879f` (+WIP), engine
  `9493099`, packages `34da39ed`.
**Updated:** 2026-10-15 (SESSION WRAP -- CLEAN HANDOFF, next session):
  tree clean at `7e860ed` (plus this wrap commit). **v0.64.5 is TAGGED**
  (`refs/tags/v0.64.5` -> `84f761c5`; compiler head d4fdd7e7 "v0.64.5
  RELEASED block (tag/run/assets)"; stdlib ea1c312 "v0.64.5 released and
  pinned"). **v0.64.5 ADOPTED by the owner (`275547e`, 2026-10-15): dev-env
  pins the official artifacts (Win shadow `xiom.new.0645` sha 02f08578...;
  WSL canonical c4aa877a...) and the `XIOM_RUNTIME_DIR` override is
  DROPPED** (re-vendored stdlib wave 139; stock pin authoritative again).
  **C-ORBIT-08B verified fixed (m260; 248x3) -- masks retired in
  `tuple2_push_f64_le` + `byte_io u8_to_bytes`; suite 160/160 x2 Win + x2
  WSL already green on the stock pin.** C-ORBIT-08A position workaround
  STAYS; dropping it surfaced **C-ORBIT-12** (`Result[(Enum, Int), Enum]`
  emits two names for one tuple struct -- minimal repro committed to the
  enum-tuple bundle). The fresh session's FIRST task is now the remaining
  re-verification battery: db_crash x2 both + probes (mvcc/fault/io-
  primitives) x2 both + fuzz both + bench refresh; re-run the repro bundles
  (C-ORBIT-08A, 09, 10, row -2) vs `release-notes/v0.64.5.md`; fill the
  release-check rows / bus transitions; then BENCH-1/R1-R2/M1.1b.
  **State at this wrap:** M1.2 S4 + M2.1 second half LANDED 2026-10-13 (real
  byte-IO + fsync + rename durability; v2 byte container DEFAULT: `7e860ed`
  tree; suite 160/160 x2 Win+WSL; db_crash 25/25 x2 both on the swapped
  primitives; fault/mvcc/io-primitives probes GREEN; fuzz both; bench Win
  wal_append 2.1k/s, WSL 36.8k/s; harness hardening = per-invocation `-o`
  binaries everywhere). Readiness **77.5** (B 18/20). Lane heads at this
  wrap: stdlib `ea1c312` (v0.64.5 released+pinned), xvector `1311e7b`,
  packages `f2429d82`, engine `0ae9afd`, compiler `d4fdd7e7` (v0.64.5
  released), relays `a7a321c`. **Bus:** orbitdb queue clear (packages-8
  reporter-close pending; stdlib notices acked; registry pilot acked with
  the P-rc recipe ask; engine A09 = SQLite-class lane, responded +
  S03 status corrected; binary-safety guard recorded from
  `REL-20261014-1427-engine`). **Owner directives queued after the
  re-verify:** BENCH-1 (embedded cross-engine bench vs SQLite/bbolt;
  `db-benchmarks` methodology clone at `E:\repos\db-benchmarks`) then R1/R2
  refactor pass (multi-file-module spike -> move-only engine split; suite
  split + summing runner) then M1.1b pager. Hybrid: live xvector tree was
  mid-restructure at `24aa093`; last green composition = their HEAD
  `200cbc7` (probe full x2 both); re-run when their tree builds.
**Updated:** 2026-10-14 (doorbell 18:00Z): **v0.64.5 GO** --
`REL-20261014-1739-compiler` (owner-authorized): compiler pushes the
  release wave (m318/m319/m321 engine-wave fixers), stdlib freezes a sha
  carrying **wave 139** (thread trampoline fix; thread acceptance already
  GREEN: dbg131s/dbgworker 5/5 runs x2 binaries), tag `stdlib-v0.64.5`,
  re-vendor, full gate, tag `v0.64.5`. Consequences for ORBITDB on the
  archive: (1) the re-vendored stdlib carries waves >=139 >> 115/117/118, so
  **drop the `XIOM_RUNTIME_DIR=<stdlib>/runtime` override in dev-env** and
  re-run the battery on the stock pin; (2) re-run the repro bundles +
  suite -- check the release notes for any m-fixes covering C-ORBIT-08
  (enum-tuple/U8 cast), C-ORBIT-09 (Vec copy alias), C-ORBIT-10 (Linux
  --check exit), C-ORBIT-11 (same-named types co-composition) and drop
  `probe_arm`-class workarounds per verified bundle; (3) threads now exist
  in the runtime (engine C02/S01 moving) -- not our slice, but the future
  multi-thread story unblocks. Queue otherwise clear (no new
  orbitdb-addressed items). Relays head `af92693`. **21:00Z update: the
  release-wave PUSH is up (`xiom-lang/xiom` main `1e4a444e`, 90 commits
  from `91860f11`); stdlib pin prep completed (release-notes/v0.64.5.md,
  `db2fbe8`) -- only the tag signal + re-vendor + gate remain before the
  v0.64.5 archive.** **00:00Z (Oct 15) update: v0.64.5 is HELD** -- the
  dry-run candidate failed two deterministic release-gate smokes
  (`Cell[Int8]` set/get readback garbage; `aes_encrypt_gcm` tuple lengths
  read 0xFFFFFFFF then AV; 5/5 vs 5/5-green on v0.64.4; stdlib tag not cut
  -- `REL-20261014-2123-stdlib` to compiler, suspect batches m314-m319).
  Neither touches ORBITDB (no Cell / no crypto use); the re-verification
  cycle waits for the NEXT candidate archive; our WATCH note stands.
**Updated:** 2026-10-14 (doorbell 15:00Z + binary-safety guard): queue clear
  (no new orbitdb-addressed items). One adjacent finding scanned for
  exposure: **`REL-20261014-1427-engine`** (to stdlib, acked) --
  `copy_file` / `read_file`+`write_file` are NOT binary-safe (truncate at
  the first NUL; their SDL3.dll copy became 3 bytes). ORBITDB check:
  **zero `copy_file` usage repo-wide**; every `read_file`/`write_file` call
  is on TEXT bodies (v1 page log, WAL rewrite) by design. Guard added to
  RUNBOOK (never text-path copy `.snap`; use OS copy or byte loops for
  backups) ahead of any future `backup` CLI. Relays head `b74b49c`.
**Updated:** 2026-10-13 (bus, engine ledger follow-through): full pass over
  all 38 ledger rows -- **only A09 names orbitdb** (response
  `REL-20261013-1950-orbitdb`); **S03 rides our sibling items**, so a status
  correction went to the engine (`REL-20261013-1952-orbitdb`: fsync/
  fsync_dir/append/append_line_sync/truncate/read_exact/read_at/write_at/
  file_lock all landed waves 115/117/118 + adopted by us in S4; only
  **mmap/msync** (xvector's existing P-ask) and the f32 bitcast (compiler
  batch) remain; plus a **C01 data point**: our soak/fuzz show no unbounded
  growth beyond the by-design arena, the dbg125r runaway was stdlib string
  builders -- not the Vec-drop reclaim path). All other rows belong to
  packages/bindings/compiler/stdlib/ops and are the ENGINE's to file
  per-lane (its stated rule). Nothing outstanding addressed to orbitdb.
  Relays head `3ba097d`.
**Updated:** 2026-10-13 (bus, engine ask ledger): the engine filed a 38-row
  ask ledger (`REL-20261013-1948-engine`; `docs/PACKAGE-ASKS.md` @ 2918676,
  sections A/B/C/S/O). No orbitdb section, but **A09 = "SQLite-class local
  DB for registry/cache services (orbitdb synergy, optional, contract-bound)"
  is ours** -- responded with the by-function surface + gates
  (`REL-20261013-1950-orbitdb`: open/typed rows/queries/durability/
  checkpoint/backup recipe; gates = pager M1.1b, power-loss matrix, first
  release; the engine files the concrete verb list when its wave arrives,
  or we align with the registry pilot adapter). S03 note:
  fsync/append/truncate/read_exact/file_lock all landed (waves 115/117/118);
  only **mmap/msync** + the f32 bitcast remain stubs -- our M1.1b pager uses
  `read_at`/`write_at`, so S03 does not gate us. stdlib wave-130
  builder-pass re-run acked (`REL-20261013-1903-stdlib`). Relays head
  `2f01739`.
**Updated:** 2026-10-13 (bus): registry opened a **pilot gate**
  (`REL-20261013-1707-registry-2`): once ORBITDB is production-grade they
  will back their 2.14.2 social/platform layer with ORBITDB as a store
  backend (first a read-model/audit replica; registry scale ~330 packages /
  ~384 artifacts today). We acked with the S4 progress: their "crash
  matrices on the swapped primitives" gate is DONE (S4 evidence), the
  "format freeze" gate has its FORMATS 3v2 tables + v2 default, durable-IO
  bundle closed. **Their remaining gates = ours: pager M1.1b, hardware
  power-loss matrix, C-ORBIT-11/-10 upstream, first release. ASK at P-rc:
  file to:registry the release tag + single-writer embedding recipe
  (open/lock via file_lock, WAL-before-ack, checkpoint, backup/restore).**
  stdlib acked our dbg125r incident (`REL-20261013-1545-orbitdb` -> closed):
  the leak was their deliberate wave-125 measurement; owned + fixed in wave
  126 (`a139f23`, string escape family) with a capped re-run announced
  (`REL-20261013-1638-stdlib` -> acked). Relays head `abd2ef3`.
**Updated:** 2026-10-13 (M1.2 S4 + M2.1 second half LANDED -- the
  byte-IO/fsync swap): `byte_io` rides the real primitives
  (`io.read_at/write_at/append_file_bytes/file_size/truncate_file`, REAL
  `sync_io.sync_fd`, new `byteio_sync_dir` via `fsync_dir`; fault gates
  unchanged); `wal_file_flush`/`page_file_sync` real; O(1) tail healing
  (`file_last_byte` + `append_line_sync`); rename durability at every
  publish (WAL truncate, page write/batch, block-store compact: temp sync +
  dir sync); **v2 byte container is now the DEFAULT** for `db_file_open`
  (v1 via `db_file_open_cfg(...,1)`, reads auto-detect, migration-on-write;
  new 160th suite test locks the flip). dev-env sets
  `XIOM_RUNTIME_DIR=<stdlib>/runtime` (remove at the re-vendor pin).
  Evidence: suite **160/160 x2 Win + x2 WSL**, db_crash **25/25 x2 both**,
  probe_mvcc + fault probe GREEN, fuzz OK both, fresh bench (Win
  wal_append 2.1k/s, insert 370k/s; WSL wal_append 36.8k/s, insert 769k/s
  -- fsync-honest). **Harness hardening en route:** a WSL DrvFs ETXTBSY race
  (shared `a.out` between quickly-killed/sequenced runs) produced a false
  RED; every runner and all seven crash-harness pairs now compile to a
  UNIQUE `-o` binary (RUNBOOK gotcha). Readiness **B 16.0 -> 18.0 = 75.5 ->
  77.5** (power-loss matrix on real hardware still open). Host incident
  noted: stdlib's `out/dbg125r.exe` ran away to ~26 GB and thrashed the box
  mid-run; stopped at the owner's flag (bus `REL-20261013-1545-orbitdb`;
  owner told stdlib directly). `db-benchmarks` cloned to
  `E:\repos\db-benchmarks` (methodology reference; client-server league --
  the embedded cross-engine bench vs SQLite/bbolt is the follow-on).
**Updated:** 2026-10-13 (doorbell 03:00Z -- stdlib bundle COMPLETE): stdlib
  wave 118 (`a0631eb`) landed **P4 real advisory locking**
  (`file_lock/file_unlock/file_try_lock` via fcntl/LockFileEx; the member
  row `packages-6` moved fixed in their lane). Bundle state per stdlib:
  **P1/P2/P3 + P4 + P5 all landed**; only the f32 bitcast pair remains
  (compiler-blocked Float32, tracked via xvector-6). Our production bundle
  ask `REL-20261012-1945-orbitdb` verified + closed with the delivered-scope
  evidence. `REL-20261010-1550-packages-8` (their order-3 repro) is
  `verified` by the reporter (order-3 churn 20k/4096 GREEN on v0.64.4;
  reporter-only close pending -- we do not move it). Next slices unchanged:
  **M1.2 S4** (byte-IO/fsync/append_line_sync swap + v2 default flip +
  bench + FORMATS 3v2), then **M3-proper multi-process is now unblocked**
  (P4 locks + lockfile design in docs/ISOLATION.md/D3), then M1.1b pager.
  Relays head `909351e`.
**Updated:** 2026-10-13 (doorbell 00:00Z -- P5 rows closed): stdlib wave 117
  (`260bb44`) landed the P5 pairs: `io.append_line_sync` (torn-tail repair +
  append + fsync in one call), `io.file_last_byte` (O(1)) /
  `io.ends_with_newline`, plus `remove_dir` + fd `truncate_fd` (packages-5 /
  xvector-5 rows). Our rows `-7`/`-8` verified + closed with
  `probe_io_primitives.xi` section E (24 checks total, GREEN x2 Win + x2
  WSL on the lane runtime). **All eight of our stdlib IO rows (`-3..-8`)
  are now verified + closed.** Remaining in the stdlib bundle: **P4 real
  advisory `file_lock`** and the f32 bitcast pair (xvector); compiler acked
  C-ORBIT-10 + C-ORBIT-11 (batch-tracked). Next slice unchanged: **M1.2 S4**
  (byte-IO/fsync/append_line_sync swap + v2 default flip + bench + FORMATS
  3v2), then M1.1b. Relays head `4357f3a`.
**Updated:** 2026-10-12 (doorbell 21:00Z -- STDLIB DURABILITY UNLOCK): stdlib
  wave 115 (`c65acb5`) landed **P1 real fsync (`sync_io.sync_fd` /
  `io.fsync`), P2 byte random-access + held append handle + truncate
  (`io.read_at/write_at/append_file_bytes/truncate_file`,
  `sync_io.open_append/write_all/close_fd`), P3 `sync_io.fsync_dir`** on the
  lane runtime; our rows `-3..-6` moved fixed -> **verified + closed** with
  the new `tests/probes/probe_io_primitives.xi` (14 checks, **GREEN x2 Win +
  x2 WSL**, run with `XIOM_RUNTIME_DIR=<stdlib>/runtime` on v0.64.4 --
  re-vendor pin pending; XIOM_STDLIB already points at the lane). Remaining:
  P4 real `file_lock` (multi-process) + P5 leftovers (`append_line_sync`,
  tail check, f32 bitcast); `-7/-8` stay acked. **M1.2 S4 (byte-IO/fsync
  swap + v2 default flip + fresh bench + FORMATS 3v2) and the M2.1 second
  half are now unblocked-with-override = the next actionable slice**, then
  M1.1b (pager over read_at/write_at). Packages answered our P2 offline/
  vendored ask (`REL-20261012-2039-packages`, design note
  `docs/OFFLINE-INSTALL-DESIGN.md`; acked; flows B/C pending on
  `-1549-packages-7` + `-1548-bindings-11`). New to:all production relays
  from xvector/pulse/engine (owner-requested motion; no orbitdb action).
  Relays head `1cfd6a2`.
**Updated:** 2026-10-12 (v0.64.4 verdict wave + production relay, same
  session): v0.64.4 LIVE (tag on `df493530`; release run 38256358845 green).
  Shadow install created + checksum/signature verified
  (`%LOCALAPPDATA%\xiom.new.0644`, sha256 44a41aea...); dev-env.ps1/.sh pins
  updated (WSL canonical already 0.64.4, sha256 d0a43a5c...).
  **Battery on the official artifacts:** suite **159/159 x2 Win + WSL**,
  db_crash **25/25 x2 both**, fuzz OK Win + WSL, fault probe (with the
  C-ORBIT-07 `probe_arm` workaround REVERTED -- original collision shape)
  GREEN x2 Win + WSL, repro-bundle matrix re-run (all expected rc), btree
  consumer probes Green x2 both. **Verdicts:** C-ORBIT-06/07 VERIFIED FIXED
  + closed (`REL-20261010-1802-orbitdb`, `REL-20261011-1124-orbitdb`;
  release-check rows filled incl. the packages-4 corroboration); C-ORBIT-08
  (enum-tuple rc 0x80000005-class) + C-ORBIT-09 still open; row
  `REL-20261010-1550-orbitdb-2` still open (T001 at 1756/1761/1766/1771).
  **New findings:** C-ORBIT-10 (Linux `--check` exits 0 even for syntax
  errors; bundle `docs/repro/check-exit-code/`, bus
  `REL-20261012-1358-orbitdb`); C-ORBIT-11 (same-named types across modules:
  xiom.btree + xiom.db.engine cannot co-compose, hard C001 on the wrong
  declaration; bundle `docs/repro/same-named-struct-compose/`, bus
  `REL-20261012-1956-orbitdb`). **xiom.btree 0.1.1 two-way consumer pass
  GREEN** (`REL-20261010-1550-orbitdb-9` verified + closed):
  `tests/pkg/probe_pkg_btree.xi` + `probe_pkg_btree_engine.xi` share the
  identical digest `850,244,294,903,48,601,650,780,133,311` (same stream,
  both platforms; insert-refuses-existing contract modelled). **Production-
  requirements relay posted per lane:** stdlib `REL-20261012-1945-orbitdb`
  (fsync/byte-IO/rename-durability/locks bundle + sequencing ask), compiler
  `-2` (08/09/10 + threads/perf roadmap), packages `-3` (offline/vendored
  installs, xiom.os parity, registry hygiene). **Hybrid:** the LIVE xvector
  tree is again mid-restructure at `24aa093` (missing `xiom.vector.types.*`
  modules -> 156 T001s) so the live re-run stays deferred; last green
  composition = their HEAD `200cbc7` (probe full x2 both).
**Updated:** 2026-10-12 (doorbell 00:00Z): v0.64.4 is PINNED --
`REL-20261011-1731-compiler` updates 4+5: m275 `4c42fc0a` fixed the
stdlib-2045 wave regression (pushed); stdlib tagged `stdlib-v0.64.4` =
`3df0843` (corpus 954/954, probes 288/288, modules 509/509); compiler
`STDLIB_VERSION` pinned + release notes + gate record; origin/main =
`df493530`. **Last step is owner-gated: tag `v0.64.4` on `df493530` ->
release run -> assets.** No archive on this machine yet (no
`xiom.new.0644`/candidate install; `releases/` has only v0.62.0): nothing
testable -- workarounds stay; verify hijack (both import orders) + phantom
bundle when the archive appears. Orbitdb queue otherwise clear; tree was
clean at `b2a88e3` this cycle.
**Updated:** 2026-10-11 (doorbell 21:00Z): `REL-20261011-1731-compiler`
update 3 -- the v0.64.4 stack was PUSHED (owner-authorized): origin/main
`677d65a7 -> 87c6ca3c` (m254-m274; m272-m274 are Gate-A/bindings fixes, no
open regressions known). stdlib is cleared to dispatch the **v0.64.4
dry-run archive** (witness/revert/battery/tag sequence); the compiler pin
follows the `stdlib-v0.64.4` tag. Still no archive to test: workarounds
stay; verification plan unchanged (hijack both import orders + phantom
bundle on landing). Orbitdb queue otherwise clear.
**Updated:** 2026-10-11 (doorbell 18:00Z): compiler posted
  `REL-20261011-1731-compiler` -- the six-batch v0.64.4 program is COMPLETE
  (m261-m271) and the stack is staged for the archive push. Fixes target our
  **C-ORBIT-07** (m261/m262 `677d65a7`; bus item `REL-20261011-1124-orbitdb`
  now `fixed`) and the **C-ORBIT-06 phantom gate** (m266/m267 `0b1c6374`;
  rows 1802 + packages-4). No archive yet: **workarounds stay** (`probe_arm`,
  phantom type declarations); on landing re-run the two bundles (hijack:
  BOTH import orders; expect `svc: private arm() ran`) and only then file
  verified/closed. Queue otherwise clear (packages-8 still awaiting their
  verify); findings ledger + paste-prompt WATCH updated; nothing pushed to
  the bus by us this cycle.
**Updated:** 2026-10-11 (M3.1 wrap -- CLEAN HANDOFF, next session): tree
  clean at the M3.1 wrap commit; lane heads at this wrap: stdlib `7e82225`
  (v0.64.3 sweep verdicts -- docs-only move; suite re-verified on it) /
  xvector `200cbc7` / packages `7ab0d82f` / relays `d45eccf` (two orbitdb
  pushes this wrap: C-ORBIT-09 + the xvector tree note); compiler lane
  `c86e2f2d` -- m268/m269 on main, no new
  archive yet, WATCH armed. Bus: orbitdb queue clear (packages-8 stays
  `fixed` awaiting THEIR verification; compiler batch plan open, no fix
  batches landed); C-ORBIT-09 filed + pushed. Next per task order: **M1.2 S4
  when the stdlib byte-IO/fsync rows land** (bus -3..-8 acked), else M1.1b
  pager groundwork (deterministic deferred-free allocator; the M3 pins feed
  its min-pinned-LSN hook). **Hybrid re-run at their moved pin:** the LIVE
  xvector working tree is mid-refactor and fails to compose
  (`xiom.vector.engine` 172 undefined `engine_memory_estimate`), so the
  probe `full` was re-run against an extracted copy of their HEAD commit
  `200cbc7` (throwaway composition under `probe-logs/xvec-head/`, their repo
  untouched): **FULL GREEN x2 Win + x2 WSL**; courtesy note
  `REL-20261011-1716-orbitdb` filed; the crash-harness half + live-tree
  re-run are deferred until their tree builds.
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
  - compiler: **v0.64.4** (released 2026-10-12, pin `df493530`; stdlib tag
    `3df0843`; six batches m254-m273) -- Windows **shadow install**
    `%LOCALAPPDATA%\xiom.new.0644\bin\xiom.exe` (sha256 `44a41aea...`;
    canonical `xiom.new` stays v0.64.2 for the other lanes; swap is
    owner/ops-coordinated), WSL canonical v0.64.4 (`d0a43a5c...`). Bump
    re-test 2026-10-12: seven bundles green, suite **159/159 x2 Win + x2
    WSL**, fuzz + WAL crash both platforms, 2000-key soak OK; witnesses
    C-ORBIT-06 + C-ORBIT-07 fixed/closed; remaining reds on the bus:
    C-ORBIT-08 PART A, C-ORBIT-09, `-2`, C-ORBIT-10. Rollback option:
    v0.64.3 (`xiom.new.0643`; findings file keeps the notes).
  - Lane heads at the 2026-10-11 M5 handoff: stdlib `b8eda7d`,
    xvector `ede0e20`, packages `263684d9`, relays `88c2343` (all moving
    fast today; re-check at the next wrap -- release rows on the bus are the
    contract).
  - Lane heads at the 2026-10-11 M3.1 wrap: stdlib `7e82225` (v0.64.3
    sweep verdicts, docs-only; suite re-verified on it), xvector `200cbc7`,
    packages `7ab0d82f`, relays `d45eccf` (two orbitdb pushes this wrap:
    C-ORBIT-09 + the xvector tree note);
    compiler lane `c86e2f2d` (m268/m269 on main, no archive yet).
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
    **159/159, exit 0** (x2 Win + WSL; v0.64.3 with **all C-ORBIT workarounds
    reverted**). Composition: 93 base + 2 churn +
    CRC32C KAT + 3 tuple-codec + 2 FSM + 2 page-file + 1 page-log + 15 db-file
    (roundtrip, checkpoint, churn, query/range, incremental, uncommitted
    generation, policy, compaction, txn commit, txn abort/guards, dangling
    txn, path validation, checked open, stale handle, dirty flush) + 2
    durability (API defaults/setters + reopen reset; syncfail latch + reopen
    recovery) + 2
    buffer-pool (clock order, pinning/reject) + 2 planner (plan kinds,
    200-case property vs brute force) + 4 tuple v2 (KAT, roundtrip incl.
    UTF-8/NaN, rejects, budget) + 4 schema_row (kinds, roundtrip, rejects,
     bool/empty) + 5 db typed (roundtrip, v1/v2 checkpoints, budget/guards,
     crafted txn window) + 1 tuple2_compare + 2 typed query (ops, persistence)
     + 7 M3 (snapshot isolation, order-3 COW churn vs models, checkpoint
     stability, savepoint basic/guards/crash windows, typed pins).
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
    tuple codec, WAL parser, page log, B-tree vs model, typed rows/queries
    and snapshot pins/savepoints (l).
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
  - Snapshot pins + savepoints (new, M3.1): `tests/probes/probe_mvcc.xi` --
    36 checks (three interleaved pins over 600 churn ops + two checkpoints
    vs per-pin models; forced compaction deferral with 81 checkpoints and a
    post-release log shrink; savepoint matrix C1-C5 across reopen crashes;
    typed payload pins); GREEN x2 Win + WSL. Found **C-ORBIT-09** en route
    (copied Vec handles alias on element assignment; `node_deep_copy` fix;
    bundle `docs/repro/vec-copy-alias/`, bus `REL-20261011-1659-orbitdb`;
    the design + landed results live in `docs/MVCC.md`).
  - Hybrid (new): `scripts/hybrid_crash_test.{ps1,sh}` -- one writer drives
    BOTH stores (ORBITDB rows + XVECTOR vectors), hard kill, torn row tail,
    reopen -> repair -> 100% join integrity; second verify idempotent
    (`repaired=0`). GREEN x2 Win + WSL. `tests/hybrid/probe_hybrid.xi`
    `full` mode: 36 checks (join integrity, brute-force exact top-k equality,
    delete pipeline, reopen bit-equality, WAL prefix + torn tail) x2 Win +
    WSL. `tests/hybrid/repro_chain.xi` is the XV-ORBITDB-01 evidence run.
    **M3.1 wrap re-run** (their pin moved to `200cbc7`): the LIVE sibling
    tree is mid-refactor (does not compile: `engine.xi:172` undefined
    `engine_memory_estimate`), so `full` was re-run x2 Win + x2 WSL against
    an extracted copy of their HEAD commit (throwaway composition under
    `probe-logs/xvec-head/`, their repo untouched) -- **FULL GREEN**; the
    crash-harness half is deferred until their tree builds (note
    `REL-20261011-1716-orbitdb`).
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
  - Snapshot pins + savepoints (new, M3.1): `DBSnapshot` pins over the node
    arena + copy-on-write writes while pinned (`cow_shadow` with
    `node_deep_copy` -- C-ORBIT-09), snapshot reads
    (`db_file_snapshot_get/_typed/_range/_count`), compaction deferral
    (`db_file_compaction_deferrals`), `db_file_min_pinned_lsn` deferred-free
    hook, txn savepoints (buffer trim + WAL window splice); design + limits
    in `docs/MVCC.md`.
  - Index-of-record: `docs/PRODUCTION-READINESS.md` **75.5/100 (~76%)**,
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
    only on the next write). The M3 minimal subset landed (in-process
    snapshot pins + savepoints, `docs/MVCC.md`); cross-process MVCC, lazy
    pager reads and version GC remain -- see `docs/ISOLATION.md`.
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
  workaround). Compiler findings on v0.64.3, all OPEN: **C-ORBIT-06**
  (phantom imports; packages' cross-file item), **C-ORBIT-07** (consumer fn
  hijacks a module-private same-named call; bus `REL-20261011-1124-orbitdb`),
  **C-ORBIT-08** (enum-in-tuple miscompile + `[N]UInt8` cast sign-extension;
  bus `REL-20261011-1219-orbitdb`), **C-ORBIT-09** (element assignment
  through a copied Vec handle aliases the source; bus
  `REL-20261011-1659-orbitdb`); C-ORBIT-01..05 stay RESOLVED on v0.64.2.
- **Next action (priority order, per `docs/PRODUCTION-PLAN.md` section 13):**
  1. **M5 typed values END-TO-END COMPLETE 2026-10-11** (codec -> schema ->
     engine persistence -> typed predicates; suite 152 -> 159 x2 both; CLI
     putrow/getrow/qrow). Optional follow-on: typed secondary indexes.
  2. **M3 minimal subset DONE 2026-10-11** (snapshot pins + savepoints; suite
     159 x2 both + `probe_mvcc` 36 checks x2 both + fuzz (l) x2 both;
     `docs/MVCC.md`). Remaining M3: multi-process locks (stdlib `file_lock`),
     pager-backed lazy reads (M1.1b), version GC.
  3. **M1.2 byte-page v2 -- design + S1 + S2 + S3 integration DONE**; next
     S4 (stdlib fixed-size IO + fsync swap, default flip + fresh bench,
     FORMATS "3v2" tables; **M2.1 second half rides here**), then M1.1b lazy
     load.
  4. Order-3 B-tree fix landed (upstream of `xiom.btree` SPEC 2.3) -- next
     `xiom.btree` release re-extracts; run the consumer pass then.
  5. **M2.1 first half DONE** (durability API + fault injector; suite x2 both
     + `probe_fault_sync` 56 checks x2 both); fsync wiring when the stdlib
     rows land; **M1.1b** lazy load once random-access page reads exist (the
     M3 pins already feed its `db_file_min_pinned_lsn` deferred-free hook);
     keep readiness + keeper docs current; commit signed at every step.
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
  `REL-20261010-1549-packages-4`) + **`REL-20261011-1124-orbitdb`
  (C-ORBIT-07, consumer fn hijacks a module-private same-named call; filed
  2026-10-11)** + **`REL-20261011-1219-orbitdb` (C-ORBIT-08, enum-in-tuple
  miscompile + fixed-array UInt8 cast sign-extension; filed 2026-10-11)**;
  stdlib `-3` fsync, `-4` append handle,
  `-5` truncate, `-6` byte-IO random access, `-7` append+repair, `-8` tail
  check; packages `-9` btree re-extract, `-10` variant qualification;
  xvector `-11` (XV-ORBITDB-01). **2026-10-12 wave:** C-ORBIT-06/07 closed
  on v0.64.4 (verdicts in the top Updated entry); btree `-9` pass verified
  + closed; new: C-ORBIT-10 `REL-20261012-1358-orbitdb`, C-ORBIT-11
  `REL-20261012-1956-orbitdb`; production-requirements P2 asks
  `REL-20261012-1945-orbitdb` (stdlib), `-2` (compiler), `-3` (packages) --
  **packages answered `-3`: `REL-20261012-2039-packages` (offline/vendored
  install design note `docs/OFFLINE-INSTALL-DESIGN.md` on packages main
  `474e081e`; flows A online-pinned TODAY / B offline mirror / C vendored;
  blockers `-1549-packages-7` + `-1548-bindings-11`; interim guidance =
  exact pins + trust pin + recorded sha256s, airgap pending flow B) --
  orbitdb ACKED it on the bus 2026-10-12 (adopting the interim guidance for
  deployment docs; no consumer changes until B/C land).**
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
- **Reference-driven development (owner directive 2026-10-17,
  NON-NEGOTIABLE):** the cloned battle-tested projects under `E:\repos` are
  the design source -- engine slices from sqlite/bbolt/redb/db-benchmarks;
  Station slices from h11/fastify/gin/knex/bullmq. Every slice starts with a
  real crawl (file:line + symbols) recorded in `docs/REFERENCE-MATRIX.md`
  with an adopt/adapt/avoid decision, then converts the mechanic to XIOM;
  never design from memory, never settle for an MVP. Missing stdlib/packages
  capability or a compiler defect -> relay item (wishlist/bug) + documented
  fallback + re-test on the next release/package publish. Extend the matrix
  on every crawl; re-crawl rows older than the slice.
- **Freshness + feedback loop (owner directive 2026-10-17,
  NON-NEGOTIABLE):** every session starts with a relay pull + lane view,
  then the LATEST released compiler/stdlib/packages (the compiler-bundled
  stdlib by default; the stdlib lane checkout is opt-in early-warning only;
  never edit it). After any version move, re-run the battery (suite x2
  both, crash, probes, fuzz) and report reds back through the bus -- the
  lanes fix on request and we re-test on the next release/publish.

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

The current, self-contained paste prompt is in
[`NEXT-SESSION-PROMPT.md`](NEXT-SESSION-PROMPT.md) (written at the 2026-10-23
context-full wrap). The previous inline block is superseded; use the file as
the single source for the next kickoff.
