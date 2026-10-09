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
