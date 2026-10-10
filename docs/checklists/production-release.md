<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Checklist -- ORBITDB production release track

> Companion to `docs/PRODUCTION-PLAN.md`. Check items as evidence lands; the
> scoreboard (`docs/PRODUCTION-READINESS.md`) records the numbers.
> Convention: `[x]` done with committed evidence; `[~]` in progress/blocked
> with a named dependency; `[ ]` not started.

## M1 -- Storage spine

- [x] NodeStore behind the B-tree (get/put + page identity + dirty tracking)
- [x] Checkpoint flushes only dirty nodes (bounded-delta test in suite)
- [ ] Lazy node load (no whole-snapshot residency requirement)
- [ ] Bounded node cache with clock eviction + write-back (C4 semantics)
- [ ] 1M-key soak with memory plateau (needs stdlib byte IO for speed)
- [x] Byte-packed page format v2 design (generation-stamped pages) --
      `docs/BYTE-PAGE-FORMAT-V2.md`, slices in `docs/checklists/byte-page-v2.md`
- [ ] Page format v2 codec + KATs -- S1 is unblocked (pure codec, no IO);
      store slices S2-S4 run against the byte-IO shim until the stdlib rows land

## M2 -- Recovery & durability

- [ ] Real fsync wired into `wal_file_flush` / `page_file_sync` (blocked: stdlib fsync stub)
- [ ] Group commit (one fsync per commit group)
- [ ] Fault injection at the fsync seam (power-loss simulator)
- [ ] Kill-at-every-step matrix (extend crash harnesses to byte/page v2)
- [ ] Checkpoint policy: age/size thresholds + pause budget

## M3 -- Concurrency / MVCC

- [ ] In-process reader/writer coordination (node pinning)
- [ ] Multi-process advisory locks (blocked: stdlib file_lock stub)
- [ ] MVCC design doc (version chains, txids, visibility, GC)
- [ ] MVCC implementation + snapshot tests
- [ ] Version GC tied to checkpoint compaction

## M4 -- Query & indexes

- [x] Semantics decision recorded: additive `query_key_range` (key range -> value conditions -> offset -> limit)
- [x] Planner: key-range pushdown + point lookup + cost estimate
- [x] Executor uses index paths; results equal brute-force model (200-case seeded property)
- [ ] Secondary indexes (catalog-driven) + fuzz vs model
- [ ] ORDER/LIMIT execution

## M5 -- Types & codecs

- [ ] Typed value model (int/float/text/blob) documented
- [ ] Tuple v2 codec + fuzz round-trip over all types
- [ ] Schema-driven storage; migration notes in FORMATS.md

## M6 -- API & bindings

- [x] App build helper embeds `assets/orbitdb.ico` (`--icon`, verified on v0.64.2)
- [ ] Cursor API + prepared statements
- [ ] Stable error taxonomy (`docs/API.md`)
- [ ] C-ABI surface + binding package spike
- [ ] Binding smoke tests in CI

## M7 -- Performance & memory

- [ ] Benchmark workloads defined (YCSB-like, TPC-B-ish, recovery time)
- [ ] Local bench baseline at 1M keys
- [ ] Owner benchmark harness adapter
- [ ] Published numbers + regression gate (>10% blocks)

## M8 -- Security & release engineering

- [ ] Fuzz budget in CI (continuous cadence, F3)
- [ ] Fault-injection suite green (power-loss)
- [ ] Threat notes (file-access attacker model)
- [ ] Format compatibility matrix + migration policy
- [ ] Docs complete: API/RUNBOOK/FORMATS/ISOLATION + readiness
- [ ] **Release signal sent to owner: "ORBITDB is ready for public release."**

## Owner actions (after the signal)

- [ ] Public repo + CI matrix (PULSE pattern)
- [ ] Registry publish (`xiom.db`, `xiom.wal`, `xiom.btree`)
- [ ] Add ORBITDB to the owner benchmark suite; share harness contract
- [ ] Pin/rollback policy when lanes move
