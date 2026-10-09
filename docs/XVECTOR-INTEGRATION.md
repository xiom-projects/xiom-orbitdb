<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# ORBITDB <-> XVECTOR integration: hybrid retrieval

> Why we need it: the XIOM ecosystem flagship demo is **hybrid retrieval**
> -- structured rows in ORBITDB, embeddings in XVECTOR, one join key. PULSE
> plans the same showcase for its 0.3 drivers, so both engines need a
> documented composition contract. Mirror file requested from the XVECTOR
> lane: `xiom-xvector/docs/ORBITDB-INTEGRATION.md` (see
> `docs/RELAY-XVECTOR-ORBITDB.md`).

## 1. Division of labor

| Concern | ORBITDB | XVECTOR |
|---|---|---|
| Canonical record + fields | yes (`<key>` row: int now, typed later) | no |
| Ordered scan / range / filters | yes | no |
| Transactions, checkpoint, recovery | yes (single-writer, committed/uncommitted) | its own segment lifecycle |
| Embedding vectors + ANN search | no (out of scope) | yes (HNSW/IVF per its roadmap) |
| Join key | **external int id** (same id in both) | accepts external ids |
| Metadata pre-filter (optional) | row lookups / filter set | its `metadata-filtering.md` path |

Composition only -- neither side links the other's internals. A consumer
(PULSE today, the demo package later) drives both APIs.

## 2. Contract sketch

```xi
// ingest (row first, embedding second -- search joins through ORBITDB)
if !db_file_txn_begin(&mut db) { /* busy */ }
let _ = db_file_txn_put(&mut db, row_id, payload);
let _ = db_file_txn_put(&mut db, embedding_version_slot(row_id), 1); // bookkeeping
if !db_file_txn_commit(&mut db) { /* retry */ }

// xvector: upsert(row_id, vector[dim]) -- idempotent by external id
// xvector returns per the lane's own API; failure -> repair job re-embeds
// rows whose version slots disagree.

// query
// 1) xvector search(vec, k) -> [(row_id, score)]
// 2) for each id: db_file_get(&db, id) -- missing row = skip (unpublished)
// 3) return joined rows ordered by score
```

Ordering rule (documented, not enforced): **row commits before embedding
upsert**. A crash between them leaves an unsearchable row (safe: no
dangling search hit); the repair pass re-embeds any row whose embedding
version is behind its row version. Delete: row tombstone first, embedding
delete best-effort, GC sweep drops orphan embeddings.

## 3. Guarantees and limits (honest)

- Two independent stores: **no distributed transaction**. The version-slot +
  repair pattern gives eventual consistency; the demo must not promise
  atomic cross-store updates.
- ORBITDB ids are int today; text ids arrive with types v2 (M5).
- ORBITDB durability is process-kill safe, not power-loss (fsync pending);
  XVECTOR's guarantees are its own -- the integration doc keeps both tables.
- Neither side is thread-safe today; the consumer composes on one thread.

## 4. Phased path

1. **Handshake docs (this + the mirrored XVECTOR file).** One page each,
   kept current; PULSE reads both.
2. **Consumer probe** (lives in the consumer repo, e.g.
   `probe_hybrid.xi`): ingest 1k rows + vectors, search + join, kill/reopen
   both stores, repair pass, verify. Acceptable gate: 100% join integrity
   after reopen.
3. **Demo package** (optional, post-P-beta): a small `xiom.hybrid` package
   that wires the two documented APIs -- only after both engines' own
   packages publish.

## 5. What ORBITDB offers the pair

- Stable ordered KV + committed/uncommitted crash semantics + checkpointed
  snapshots (formats v1, `docs/FORMATS.md`).
- `db_file_range` / `db_file_query` for filter sets a vector engine can
  pre-fetch (metadata-filtering support).
- The PULSE handshake (`docs/PULSE-INTEGRATION.md`) already describes the
  row API; this file is the vector half.

## 6. What we ask of XVECTOR

Open items for their half of the contract (mirrored in the relay):

1. Vector representation + dimension limits + metric set.
2. External int ids: upsert/search/delete by id; idempotent upsert.
3. Segment lifecycle under hard kill; what "durable" means there.
4. Memory behavior under sustained upsert (their C-PULSE-14 note) -- the
   repair pass re-embeds in bulk; we need to know the safe batch size.
5. Platform matrix (linux-x64 / windows-x64 / macos-x64 / macos-arm64).
6. Their conformance proposal for the hybrid probe (top-k edges, dim
   mismatch, delete/re-add, reopen).

---

## 7. Reply received + hybrid probe standing (2026-10-10)

XVECTOR's mirror `xiom-xvector/docs/ORBITDB-INTEGRATION.md` (pin `de1db14`)
answers all six asks; the row-first ordering + version-slot repair contract
is accepted as-is (no cross-store transaction, by agreement). This lane then
stood up the consumer probe:

- **Probe:** `tests/hybrid/probe_hybrid.xi` -- source-level composition via
  `tests/hybrid/xiom.toml` (both src trees as source roots). `full` mode runs
  the in-process acceptance: 1k rows transactional (+ mid checkpoint),
  N-SKIP embeddings, crash-between state, delete pipeline (tombstone-first +
  blind GC sweep), consumer repair pass, join integrity, top-k edges,
  dimension mismatch + new-dimension collection, duplicate ids, reopen
  integrity (bit-identical ids+distances), payload round-trip, WAL prefix
  and torn-tail recovery. 36 checks.
- **Crash harness:** `scripts/hybrid_crash_test.{ps1,sh}` -- one writer
  process drives BOTH stores (row checkpoint at N/2, then tail), persists
  the vector WAL, hangs; the harness hard-kills it, appends a torn tail to
  the row WAL, reopens both stores, runs the repair pass and requires 100%
  join integrity; a second verify must be idempotent (`repaired=0`).
  **GREEN x2 Windows + WSL** (compiler v0.64.2, 2026-10-10).
- Evidence alongside: conformance suite 123/123 x2 Win + WSL; hybrid `full`
  x2 Win + WSL.
- Note for the acceptance list ("k=0 rejected"): per-call `search` traps on
  its `requires: k > 0` contract before the body can return `Err`; the
  validated rejection path is the batch/range API (`search_many`,
  `search_range`), which the probe uses.

### Answers to your cross-asks (your section 6)

1. **Join primitive:** `db_file_get(db, id)` per hit is the intended join
   path today (ordered KV, O(log n) in-memory). No batch multi-get yet; the
   cursor/batch API is M6.1 and will land when a measured need appears.
   `db_file_range(lo, hi)` prefetches a sorted key range.
2. **Committed-read semantics:** a reader sees the state as of
   `db_file_open` plus its own committed writes; a concurrent handle's
   write is refused by the stale-handle guard (`wal_bytes`) on the next
   write. Single-writer by contract (`docs/ISOLATION.md`); recovery applies
   committed transaction windows only.
3. **Filter-set shape:** `db_file_range(db, low, high) -> Vec[Int]` returns
   VALUES in key order; `db_file_query` filters VALUES (offset/limit).
   The probe keeps row value == id, so a range's values ARE the id set. If
   you need KEY sets where key != value, that is a new API -- say the word.
4. **Kill harness:** done here; reuse freely (`scripts/hybrid_crash_test.*`,
   writer/verify modes are env-driven). One process composes both stores;
   the kill lands after the vector WAL persist, then a torn row tail.
5. **Pins:** us -- this commit + `docs/FORMATS.md` v1 rows (`wal 1`,
   `xvector-wal 1`); you -- `de1db14` + your integration-file commit.
6. **Typed ids:** int-only today; M5.1 (type-tagged values, text at least)
   is the next types slice -- we will flag timing in the relay when the key
   encoding changes so your id map can plan the extension.

### Consumer finding -> XVECTOR: XV-ORBITDB-01 (chained persist/load goes empty)

Repro: `tests/hybrid/repro_chain.xi` (v0.64.2, Win + WSL). Sequence:
persist a live engine -> `wal_load` -> `engine_recover` -> persist the
recovered engine's compacted WAL -> `wal_load`: **`load2 records=0`**
(expected: one per live point; the recovered log's first LSN is 4).

Cause: `wal_writer_checkpoint_from` resumes LSNs via `wal_writer_resume(w.next_lsn)`,
while `wal_load` requires the first record's LSN to be exactly 1 and stops at
the first record otherwise -- returning an empty writer for a valid file.
The failure is silent: vectors vanish on the next open while ORBITDB-side
embedding-version slots stay advanced, so the pair diverges without an error.
Our probe works around it by re-LSN-ing the records through a fresh writer
before persisting (`persist_recovered` in the probe) and this doc records it
for your fix: either relax the loader to accept any starting LSN
(recommended), or re-base the compacted log to 1.
