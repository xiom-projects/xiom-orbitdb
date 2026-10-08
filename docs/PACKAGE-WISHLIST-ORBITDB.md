<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# XIOM ORBITDB -> packages lane: wishlist + consumer notes

**Relay:** hand this file to the packages-lane session. ORBITDB consumes
packages from the registry only (never vendored, never edited). Evidence
paths are from `E:\xiom-projects\xiom-orbitdb`.

**Pin:** compiler v0.64.0, stdlib `a677338`, registry
`https://registry.xiom-lang.org`.

**Context:** ORBITDB (formerly xiom-db) is the embedded database engine --
B-Tree, WAL, query engine, crash recovery. Phase 0 is in-memory and
zero-dependency; this session made it compile and pass its own conformance
suite on v0.64.0 (93/93) and bootstrapped a durable WAL segment probe with
hard-kill crash/reopen (green Windows + WSL, 200-record soak). The wishlist
below is about extracting the durable primitives into reusable packages as
they harden.

## Proposed packages (ORBITDB needs / will grow)

| Proposed name | Purpose | Why not stdlib | Deps | Evidence from ORBITDB |
|---|---|---|---|---|
| `xiom.btree` | Ordered in-memory index: flat-array B-tree with `insert/search/delete/range_query/min/max/size/to_vec` (the borrow-checker-safe representation used by ORBITDB). | data-structure package domain; the API will grow (cursors, bulk load, secondary-index helpers) and ORBITDB will iterate on delete invariants | xiom.std | `src/engine.xi` B-tree section; this session fixed a real split bug (child-pointer shift) found by `tests/probes/probe_core_diag.xi` (100 inserts, order 5). Extraction is honest only after delete/underflow invariants for odd orders are fixed (see ROADMAP Phase 1). |
| `xiom.wal` | Append-only durable log: text record codec, replay into an index, torn-tail healing, segment truncate/checkpoint seam. | storage policy + file format; stdlib should stay zero-dep core. PULSE asked for an embedded store (`xiom.kv`); a shared WAL is its crash-safety engine. | xiom.std (fsync pending stdlib row) | `tests/probes/probe_wal_file.xi` + `scripts/crash_test.{ps1,sh}`: write N -> hard kill -> torn tail -> replay N -> heal N+1, GREEN x2 Windows + WSL; 200-record soak (2,881 B segment). |
| `xiom.db` (this engine; eventual publish) | Embedded database: the layered engine (B-Tree + WAL + query + recovery) behind the `xiom.db.*` module surface. | n/a -- this is the product, not a utility | xiom.std, later `xiom.btree`/`xiom.wal` if extracted | ORBITDB repo; renamed from xiom-db (2026-10). Final package name + publish timing are the owner's call; no rush -- and per owner direction the VPS/CI/public-release stays parked until greenlit. |

## Consumer notes / registry watch

- **`xiom.kv` 0.1.0** is published and available. ORBITDB is not consuming
  it in Phase 0 (the engine is the product), but the WAL/compaction design
  work will compare against it. The known-red gate from the PULSE lane
  (`kv_get` corruption, C-PULSE-10 in PULSE's compiler findings) is tracked
  there; ORBITDB will record a consumer probe if/when it adopts.
- **No consumer pass on registry packages yet** from ORBITDB: no
  consumer-visible package defects to report this session. The first
  consumer probe will follow the PULSE pattern
  (`tests/probes/probe_pkg_*.xi`) and this doc will carry its own rows.
- **C FFI/bindings worktree:** ORBITDB targets pure XIOM (no FFI) through
  Phase 2; no bindings request. If that changes (e.g. mmap), it will be
  filed here first.
- **Toolchain note for consumers:** on v0.64.0, registry package adoption
  still needs `xiom.toml` `source-roots` (C-PULSE-02, PULSE's compiler
  findings) -- ORBITDB has no `xiom.toml` yet and no registry deps, so it
  is unaffected so far.

## Suggested order

1. `xiom.btree` extraction after the delete/underflow invariant work
   (ORBITDB Phase 1) -- the flat-array representation is proven against
   the borrow checker and now against a real split bug.
2. `xiom.wal` extraction when stdlib lands fsync + append-tail-repair
   (ORBITDB Phase 2) -- the crash harness is the acceptance test.
3. `xiom.db` publish when Phase 1-2 make durability honest (owner gate).

## Delta 2026-10-08 (packages-lane answers + ORBITDB response)

- **`xiom.btree`: name held; extraction gate = ORBITDB churn soak -- MET.**
  Evidence: `tests/probes/probe_btree_churn.xi` randomized
  insert/delete/search vs a reference model + structural validator, green at
  orders 4/5/6 x 20,000 ops (keyspace 4096) plus a seed matrix, and two
  in-suite churn regressions (**95/95 x2**). One contract to carry:
  `min_keys = (order-2)/2` for this split scheme. Churn probe = acceptance
  test.
- **`xiom.wal`: ships standalone (3 users, one format), API shaped from
  ORBITDB crash-probe evidence.** ORBITDB's response
  (`docs/RELAY-PACKAGES-RESPONSE-ORBITDB.md`) proposes: keep
  `xiom.durable`'s `WalOpKind` / `WalRecord { lsn, op, key, value,
  payload, timestamp }` vocabulary, add the disk segment layer
  (`wal_open/append/flush/replay/truncate/close`), torn-tail heal + the
  crash harness as the acceptance test; `payload[0]` = subtype tag for
  xvector/xiom.db extension.
- **`xiom.durable` reconciliation:** `xiom.wal` becomes the single WAL home;
  durable keeps `src/txn/*` and consumes it. ORBITDB will land the disk layer
  against durable's record shape (reference implementation in
  `src/wal_file.xi` + `probe_wal_file` acceptance).
- **`xiom.kv` watch unchanged:** C-PULSE-10 is Linux-only; the fsync row is
  filed in the stdlib wishlist.
