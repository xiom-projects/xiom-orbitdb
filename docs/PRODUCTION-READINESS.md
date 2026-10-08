<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# ORBITDB -- Production-Readiness Tracking

> Single source of truth for "how close to production grade". ROADMAP.md is the
> phase plan; THIS file is the scoreboard. Every score change must cite
> evidence that exists in the repo (suite/probe/soak/crash harness) and be
> committed in the same change that earns it.

## Honesty rules

1. **No green without evidence.** An item scores only when implemented AND
   proven: conformance test or probe run x2 (Windows + WSL), a soak for
   long-running paths, or the crash harness for durability paths. Scaffolds
   and in-memory stand-ins score 0 unless the row says otherwise.
2. **No silent failures.** Anything that can corrupt or drop data must fail
   loudly or refuse (`tuple_encode_checked`, strict decode, checksum verify).
3. **Durability claims are literal.** "Durable" today = OS write-back +
   torn-tail healing; power-loss durability requires fsync (stdlib row) and
   is scored at 0 until then.
4. **Scores are weighted areas; sub-item points are additive.** Partial work
   can take partial points only where the row defines a fraction.
5. **Recompute on every wrap.** Add a dated line to the scoreboard changelog.

## Current scoreboard -- 2026-10-08

| Area | Weight | Earned | Status summary |
|---|---|---|---|
| A. Correctness & data structures | 20 | 16.0 | B-tree churn-proven; tuple codec v1 KAT-locked; FSM best-fit model-soaked; node-per-page pending |
| B. Durability & crash safety | 20 | 16.0 | Disk WAL segment + page file + engine WAL-before-ack + checkpoint/snapshot crash-proven; fsync still pending |
| C. Storage engine (pages/pager) | 15 | 8.0 | Codec + checksum + FSM + durable page file done; pager substrate/replacement policy pending |
| D. Transactions & isolation | 10 | 1.0 | State machine only; no MVCC, no crash-safe redo/undo |
| E. Query & schema | 10 | 3.0 | Value-filter query + DBFile range/query bindings done; planner scaffold; no secondary indexes/typed values |
| F. Operations & tooling | 10 | 4.0 | ps1/sh runners, crash harness, probes; no CI/packaging/version stamp |
| G. Performance & limits | 5 | 2.5 | Benchmarks published (v0.64.1); replay constrained by the filed stdlib `str_split` quadratic; memory/scale policy pending |
| H. Security & integrity | 5 | 2.0 | Checksums + validation; no fuzz, no encryption, no supply-chain pinning |
| I. Documentation & evidence | 5 | 4.0 | Full doc set + relay docs + repro bundles; public API reference pending |
| **Total** | **100** | **56.5** | **~57% -- pre-alpha, durable log + pages, benchmarks live** |

Scoreboard changelog:
- 2026-10-08: bootstrap complete (suite migrated, engine defects fixed, WAL
  crash harness, B-tree delete churn-proven, CRC32C, tuple codec v1): 39.5.
- 2026-10-08: free-space map hardened (best-fit + clamping + invariants,
  50k-op model soak) and locked in the suite: 43.5.
- 2026-10-08: durable page file v1 (CRC32C verify, atomic rewrite, crash
  harness x2 Win + WSL) -> C2 5 pts; page-level torn detection credited
  partially -> B6 2/4: 50.5.
- 2026-10-08: engine on the disk WAL -- `DBFile` WAL-before-ack +
  replay recovery, `db_crash_test` x2 Win + WSL + 200-key soak -> B4 4 pts
  (also surfaced and worked around compiler finding C-ORBIT-04): 54.5.
- 2026-10-08: benchmark harness (`bench.{ps1,sh}`) + numbers -> G1 2 pts;
  the bench caught the stdlib `str_split`/`read_file_lines` quadratic (filed)
  and drove the WAL append heal-state fix (626 -> 2,946 ops/s Windows,
  26k ops/s WSL native fs): 56.5.
- 2026-10-08: checkpoint/snapshot landed -- node page codec (B-tree -> page
  file), atomic snapshot install, Checkpoint anchor + keep-anchor truncate,
  `db_file_open` = snapshot + tail replay; suite 106/106 x2 Win + WSL,
  `db_crash_test` checkpoint scenarios (snapshot-only + snapshot/tail) x2 Win
  + WSL, 2000-key soak (9 checkpoints). B2 evidence upgraded smoke ->
  crash-proven (no score change; B2 was already credited at 2/2): 56.5.
- 2026-10-08: DBFile query/range API -- `db_file_query`/`db_file_range` mirror
  `db_query`/`db_range` (value semantics, key-range) on the recovered tree;
  `qverify` query-after-recovery checks in all three crash scenarios; suite
  107/107 x2 Win + WSL, db_crash 15/15 x2 Win + WSL. E1 evidence upgraded
  (no score change; E1 already credited): 56.5.

## A. Correctness & data structures (20)

| # | Item | Pts | Status | Evidence / gate |
|---|---|---|---|---|
| A1 | B-tree insert/search/delete/range/min/max/to_vec | 4 | OK | suite + `probe_core_diag` |
| A2 | B-tree delete borrow/merge invariants (all key counts valid, uniform leaf depth) | 4 | OK | `probe_btree_churn` structural validator; 20k ops x orders 4/5/6 + seed matrix |
| A3 | Byte-packed tuple codec with strict decode + budget | 4 | OK | `probe_tuple_codec` KAT/extremes/rejects; suite 99/99 |
| A4 | Free-space map hardening (best-fit, invariants, model soak) | 4 | OK | `probe_fsm` (use/release/find vs model, invariant checks, 50k ops x 256 pages) + suite best-fit/clamp tests |
| A5 | Node-per-page B-tree | 4 | -- | needs A4 + pager seam |
| | *Partial credit:* CRC32C integrity aids A3/A5 | +0 | -- | counted in B |

## B. Durability & crash safety (20)

| # | Item | Pts | Status | Evidence / gate |
|---|---|---|---|---|
| B1 | Append-only WAL segment: append, replay, torn-tail heal, LSN resume | 4 | OK | `probe_wal_file` + `scripts/crash_test.{ps1,sh}` x2 Win + WSL; 200-record soak |
| B2 | WAL checkpoint/truncate seam | 2 | OK | `db_file_checkpoint`: node page codec snapshot + atomic install + Checkpoint anchor + `wal_file_truncate` keep >= anchor (payload preserved); `db_file_open` snapshot + tail replay; suite checkpoint tests; `db_crash_test.{ps1,sh}` scenarios B/C x2 Win + WSL; 2000-key soak |
| B3 | CRC32C page integrity (KAT-locked) | 2 | OK | `probe_crc32c` x2 + suite KAT |
| B4 | Engine wired to the disk WAL (WAL-before-ack on real files) | 4 | OK | `DBFile` facade: `db_file_put/delete` append then apply; `db_file_open` replays; `db_crash_test.{ps1,sh}` GREEN x2 Win + WSL + 200-key soak; suite roundtrip |
| B5 | fsync/durable flush on commit (`wal_file_flush` is honest no-op) | 4 | 0 | blocked: stdlib fsync row (STDLIB-WISHLIST-ORBITDB.md #1) |
| B6 | Torn-page detection on read + crash matrix (page-level) | 4 | 2 | checksum reject + `page_crash_test.{ps1,sh}` GREEN x2 Win + WSL; power-loss leg still blocked on fsync |
| | *Partial:* B1+B2+B3 = 8/20, B6 = 2/4 | | | |

## C. Storage engine (pages/pager) (15)

| # | Item | Pts | Status | Evidence / gate |
|---|---|---|---|---|
| C1 | Page type + CRC32C + in-memory buffer pool | 3 | OK | suite page/buffer_pool tests (with C-ORBIT-02/04 workarounds) |
| C2 | Durable page file (page read/write/verify on disk) | 5 | OK | `probe_page_file` + `scripts/page_crash_test.{ps1,sh}` x2 Win + WSL (kill -> torn -> verify N -> upsert -> N+1); suite roundtrip/corruption tests |
| C3 | Pager integration (`xiom.core.storage.pager` substrate) | 4 | 0 | externally blocked: registry source-roots (C-PULSE-02) / substrate availability |
| C4 | Buffer-pool replacement policy + pinning semantics | 3 | -- | direct-mapped placeholder today |

## D. Transactions & isolation (10)

| # | Item | Pts | Status | Evidence / gate |
|---|---|---|---|---|
| D1 | Txn state machine (active/committed/aborted, op list) | 2 | OK (state only) | suite txn tests |
| D2 | Crash-safe redo/undo with committed/uncommitted classification | 4 | -- | needs WAL engine wiring (B4) |
| D3 | MVCC snapshots / version-aware reads | 4 | -- | Phase 3 design |

## E. Query & schema (10)

| # | Item | Pts | Status | Evidence / gate |
|---|---|---|---|---|
| E1 | Query engine: AND filter, offset, limit, deterministic order | 3 | OK | suite query/db_query/db_file tests; **value semantics pinned** in docs/query-pipeline.md; `db_file_range`/`db_file_query` on recovered trees; `qverify` in every `db_crash_test` scenario x2 Win + WSL |
| E2 | Index-aware planner (key-range pushdown, point lookup, cost) | 3 | -- | requires the semantics extension decision (docs/query-pipeline.md note) |
| E3 | Secondary indexes driven by catalog `IndexDef` | 2 | -- | needs A5 |
| E4 | Typed values + column constraints (beyond Int) | 2 | -- | codec v1 carries type byte 0x01; more types later |

## F. Operations & tooling (10)

| # | Item | Pts | Status | Evidence / gate |
|---|---|---|---|---|
| F1 | ps1 + sh twins: dev-env, watchdog runner | 2 | OK | both platforms green |
| F2 | Crash/reopen + soak harness | 2 | OK | `crash_test.{ps1,sh}`, 200/20k soaks |
| F3 | CI matrix (Windows/Linux; pinned toolchain from dl); org SHA-pinning | 2 | -- | owner gate: public repo (ops has the mechanics) |
| F4 | Packaging: `xiom.wal`/`xiom.btree` extraction, `xiom.db` publish, build-info/version stamp | 3 | 1 | `xiom.wal` reference landed; gates met again on btree; no registry publication yet |
| F5 | Release engineering: signed tags, notes, artifacts, checksums | 1 | -- | owner gate |

## G. Performance & limits (5)

| # | Item | Pts | Status | Evidence / gate |
|---|---|---|---|---|
| G1 | Benchmarks (insert/search/delete/range; WAL append/replay throughput) | 2 | OK | `scripts/bench.{ps1,sh}` + `probe_bench`; v0.64.1 N=10k: Win btree_insert 1.25M/s, search 3.3M/s, delete 1.67M/s, tuple 714k/s, WAL append 2.9k/s, replay 0.94k/s; WSL native-fs append 26k/s; replay constrained by the filed `str_split` quadratic (44.7 s per 5 MB) |
| G2 | Memory bounds (page budget, WAL segment size policy, cache) | 2 | 0.5 | tuple budget exists; segment/cache policy pending |
| G3 | Scale soak (1M+ keys, long WAL) | 1 | -- | |

## H. Security & integrity (5)

| # | Item | Pts | Status | Evidence / gate |
|---|---|---|---|---|
| H1 | Integrity: checksums on pages, strict decode, no partial rows | 2 | OK | CRC32C + codec KATs |
| H2 | Input validation (paths, sizes, field counts) | 1 | 0.5 | budget/refusals exist; path/env validation partial |
| H3 | Fuzz/property testing (codec, WAL parser, B-tree vs model at scale) | 1 | -- | churn model is property-based but not fuzzed continuously |
| H4 | Supply chain: package signature verification, pinned toolchain | 1 | 0.5 | dev-env pins versions; registry adoption not started |

## I. Documentation & evidence (5)

| # | Item | Pts | Status | Evidence / gate |
|---|---|---|---|---|
| I1 | README/SPEC/ARCHITECTURE/ROADMAP/AUDIT + docs/ set | 2 | OK | current + honest |
| I2 | Relay docs (compiler findings, stdlib/package wishlists, per-lane messages) | 2 | OK | kept current every wrap |
| I3 | Public API reference / runbooks / format spec versioning | 1 | -- | codec v1 documented; no external API doc yet |

## Phase gates (mapping to ROADMAP.md)

| Gate | Meaning | Blocking score |
|---|---|---|
| **v0.1 pre-alpha** | In-memory core correct + crash-proven WAL segment (current) | 39.5 |
| **v0.2 alpha** | A4/A5 done + C2 (durable page file) + B4 (engine on disk WAL) | ~60 |
| **v0.3 beta** | B5 fsync + B6 torn-page matrix + D2 redo/undo + G benchmarks | ~80 |
| **v1.0 production** | All areas >= 90%; CI + packaging + release engineering + fuzz in place; no area below 4/5 of its weight | 100 |

## What 100% specifically requires (checklist)

- [ ] Every data path proven by suite x2 + a soak; every durability path by
      the crash harness on Windows AND WSL.
- [ ] fsync wired (stdlib row) and power-loss matrix run.
- [x] Engine on disk: WAL-before-ack, recovery from real files, checkpoint.
- [ ] Durable page file + pager + replacement policy; torn-page detection.
- [ ] Redo/undo with committed/uncommitted classification; MVCC story decided.
- [ ] Benchmarks with published numbers and no unbounded memory growth.
- [ ] CI matrix green on Windows/Linux with pinned toolchain and SHA-pinned
      actions; release artifacts + SHA256SUMS; build-info/version stamp.
- [ ] Fuzz harness on codec/WAL parser; B-tree model soak at 1M+ ops.
- [ ] Public API reference, format/versioning doc, ops runbook.
- [ ] All relay findings either fixed upstream (verified by re-test) or
      documented as accepted limitations.
