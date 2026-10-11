# Typed values in storage -- the container decision (M5.2 -> M5.3)

Status: decision + S1/S2 landed 2026-10-11 (M5.1 codec, M5.2 schema layer).
S3 (engine persistence) is the next slice; this document is its contract.
Copyright (c) 2026 Eleftherios Notas and The XIOM Authors.
SPDX-License-Identifier: MIT OR Apache-2.0

## Why this is a decision

M5.1 landed the typed value model and the tuple codec v2 (`TValue`,
`tuple2_*`, FORMATS 5A); M5.2 landed the schema layer (`schema_row`: kind
mapping, validation, encode/decode, id/pk consistency). Neither persists
anything: the engine (`DBFile`) stores Int keys and Int values today, and
"store typed rows" changes the value container in three places at once --
the B-tree node, the WAL record, and the snapshot page. The constraints:

1. **Keys stay Int.** Ordered scans, planner bounds, `query_key_range`, and
   the secondary index `(value, pk)` all assume ordered int keys; the typed
   model applies to VALUES only.
2. **Crash-safety rules unchanged.** WAL-before-ack, torn-tail WAL healing,
   torn-page/torn-block tolerance, generation-committed snapshots,
   single-writer (docs/ISOLATION.md).
3. **Old artifacts keep loading.** v1 snapshot pages and plain WAL records
   must decode without rewrite.
4. **House memory style.** Parallel vectors over `Vec[Option]` element
   writes in hot structures (m226 fixed the language bug; the pattern stays
   out of the tree).
5. **The engine stays value-agnostic.** Payloads are opaque `Vec[Int]`
   bytes; `schema_row` composes above (`validate -> encode -> put_typed`).

## Options considered

| Option | Shape | Verdict |
|--------|-------|---------|
| **A. Entry payloads in the nodes** | `BTreeNode` gains a parallel `payloads: Vec[Vec[Int]]`; empty = none. Snapshot node page v3 adds a payload section; WAL rides the existing tagged-payload records. | **CHOSEN** |
| B. Side payload store | Keep Int->Int tree; value = ordinal into a separate payload log. | Rejected: orphan payloads on overwrite/delete need the deferred-free/GC class (M1.1b) and add crash windows between tree and log; A is strictly simpler on consistency. |
| C. Per-table row trees | A second tree per table keyed by pk with payload values. | Rejected: same surgery as A, duplicated structures; table scoping belongs to the catalog layer later. |

Option A makes the payload part of the record: there is no state that can
outlive its row, no reclamation problem, and replay/snapshot carry it the
same way they carry the int value today.

## Chosen shapes (normative)

**In-memory (S3):** `BTreeNode.payloads: Vec[Vec[Int]]` parallel to
`keys`/`values`; for typed rows `values[i]` mirrors the pk (same int as the
WAL key). Tree search/compare paths touch keys only; insert/update/delete
carry the payload alongside. Int-only users see empty payloads (zero
format change for them).

**WAL (S3, container unchanged):** typed writes use the EXISTING tagged
extension -- `wal_file_append_tagged(w, op, key, value, payload, ts)` with
`payload[0] = 1` (subtype: tuple v2 row) and `payload[1..]` = the encoded
row bytes (FORMATS 5A). Plain int records carry no payload, byte-identical
to today. Replay classifies by payload presence + subtype; malformed
payloads are dropped exactly like malformed records (crash tests compare
counts, not content).

Example record (typed put):

```
7|1|42|42|0|1,219,2,6,1,42,0,0,0,0,0,0,0,3,2,0,0,0,104,105,...
 ^lsn ^op ^key ^value ^ts ^subtype=1 ^tuple v2 row bytes
```

**Snapshot (S3):** node page version 3 -- the existing sections (FORMATS
section 4) plus a payload section: `u32 payload_count` then per entry
`u32 length` + bytes. Version 2 pages decode with empty payloads (no
rewrite, `page_format` 2 auto-detect already handles the container level).

**API (S3):** `db_file_put_typed(db, key, payload)`,
`db_file_get_typed(db, key) -> Option[Vec[Int]]`; delete/checkpoint/replay
unchanged in shape. `schema_row` composes: `schema_row_key` ->
`schema_row_encode` -> `put_typed`. Query filters stay int-based; typed
column predicates and typed secondary indexes are S4 (they compare decoded
values, so they build on S3, not beside it).

## Evidence ladder for S3 (definition of done)

1. Engine: payloads survive insert/update/delete/search, checkpoint
   (v3 pages), reopen (snapshot + WAL replay), and the v1/v2 readers still
   load old artifacts (suite tests).
2. Crash: fault-injector scenarios (`probe_fault_sync`): typed put with a
   failing ack sync latches + reopens with the payload recovered; torn
   page/header fallback keeps payloads consistent with values.
3. Fuzz: random typed rows through `db_file_put_typed` vs a model
   (search/range/delete/reopen), plus byte-mutation of v3 node pages.
4. Zero regressions for int users: the existing suite (144 tests) stays
   green; snapshot v3 auto-detect is additive.
