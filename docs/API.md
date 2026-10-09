# ORBITDB Public API Reference

> **Status:** current for the committed tree (compiler v0.64.1). Signatures are
> the `pub` surface of the compiled modules; `requires:` contracts are noted
> where they gate behavior. Error semantics: functions returning `DbResult[T]`
> (`Result[T, DbError]`) never panic; `Option[Int]` means absence, and
> `Bool`/`Int` returns encode success/failure (`-1` is the sentinel for
> "rejected" on `Int`-returning checkpoint calls).

Module map (compiled units): `xiom.db.engine` (B-tree, query, in-memory
engine, `DBFile` -- the consolidated engine), `xiom.db.wal_file` (durable WAL
segment), `xiom.db.storage.page` (page, checksum, buffer pool, storage
engine), `xiom.db.storage.page_file` (durable page file + page log),
`xiom.db.storage.tuple` (row codec, result set), `xiom.db.storage.free_space_map`,
`xiom.db.error`, `xiom.db.config`, `xiom.db.ids`, `xiom.db.contracts`,
`xiom.db.catalog.schema`, `xiom.db.catalog.schema_validator`,
`xiom.db.txn.transaction`.

---

## Durable file-backed database -- `DBFile` (`xiom.db.engine`)

`DBFile` is the durable facade: WAL-before-ack writes, snapshot + tail
recovery, incremental checkpoints, and single-active transactions. File
layout: `<path>` = WAL segment, `<path>.snap` = snapshot page log.

| Call | Returns | Semantics |
|------|---------|-----------|
| `db_file_open(path, order)` | `DBFile` | Open/create; load newest committed snapshot generation, replay WAL records with `lsn > checkpoint_lsn`, heal torn tails. |
| `db_file_put(db, key, value)` | `Bool` | Upsert; appends WAL first, then mutates the tree. `false` on WAL failure or while a transaction is active. |
| `db_file_delete(db, key)` | `Bool` | Delete; `false` when the key is absent, on WAL failure, or while a transaction is active. |
| `db_file_get(db, key)` | `Option[Int]` | Point lookup. |
| `db_file_range(db, low, high)` | `Vec[Int]` | Values for keys in `[low, high]` inclusive, in key order (`requires: low <= high`). |
| `db_file_query(db, query)` | `Vec[Int]` | Value-filter query; same semantics as `db_query` / `query_execute` (conditions filter VALUES). |
| `db_file_size(db)` | `Int` | Number of keys. |
| `db_file_last_lsn(db)` | `Int` | Highest WAL LSN assigned (0 = empty). |
| `db_file_flush(db)` | `Bool` | Durability seam (no-op until fsync lands); kept for API symmetry. |
| `db_file_checkpoint(db)` | `Int` | Commit a checkpoint; returns the anchor LSN, or `-1` (snapshot failure, or a transaction is active). |
| `db_file_maybe_checkpoint(db, limit)` | `Int` | Checkpoint when `limit` records accumulated (`requires: limit >= 1`); anchor LSN or `-1`. |
| `db_file_txn_active(db)` | `Bool` | Transaction open? |
| `db_file_txn_begin(db)` | `Bool` | Start a transaction (`false` if one is active). |
| `db_file_txn_put(db, key, value)` | `Bool` | Buffered upsert inside the transaction. |
| `db_file_txn_delete(db, key)` | `Bool` | Buffered (idempotent) delete inside the transaction. |
| `db_file_txn_commit(db)` | `Bool` | Append `CommitTxn`, then apply the buffered ops to the tree. |
| `db_file_txn_abort(db)` | `Bool` | Append `AbortTxn`; discard the buffer. |

Transaction limits: single active transaction per handle, no isolation/MVCC
(readers see committed state), no auto-retry. Checkpoint and auto-commit
writes are rejected mid-transaction. See `wal-and-recovery.md` for the crash
ordering and `FORMATS.md` for the record layout.

## B-tree index (`xiom.db.engine`)

`BTree = { root, order, nodes }` -- a flat node array; `BTreeNode = { keys,
values, children, is_leaf }`. Order must be `>= 3` (`valid_btree_order`).

| Call | Returns | Semantics |
|------|---------|-----------|
| `btree_new(order)` | `BTree` | Empty tree with a single leaf. |
| `btree_insert(tree, key, value)` | `Bool` | `true` iff the key was absent (upsert is caller's job). |
| `btree_delete(tree, key)` | `Bool` | `true` iff the key was present. |
| `btree_search(tree, key)` | `Option[Int]` | Point lookup. |
| `btree_range_query(tree, low, high)` | `Vec[Int]` | Values in key order (`requires: low <= high`). |
| `btree_min(tree)` / `btree_max(tree)` | `Option[Int]` | **Value** at the smallest/largest key (`None` when empty). |
| `btree_size(tree)` / `btree_to_vec(tree)` | `Int` / `Vec[Int]` | Key count / all values in key order. |

## In-memory engine and database (`xiom.db.engine`)

`Engine` = B-tree + in-memory WAL. `Database` = `Engine` + config + open flag;
the `Database` facade is separate from `DBFile` (durable) today.

| Area | Calls |
|------|-------|
| Engine | `engine_new(order)` / `engine_default()`; `engine_insert` / `engine_update` / `engine_delete` / `engine_get` / `engine_query` / `engine_range_query` / `engine_size` / `engine_wal_size`; `engine_recover()` (replay in-memory WAL); `engine_flush_wal()` (drop WAL after data is durable in RAM); `engine_truncate_wal(before_timestamp)`. |
| Database | `db_open(order)` / `db_open_with(config)`; `db_insert` / `db_update` / `db_delete` / `db_get` / `db_range` / `db_query` / `db_size` / `db_recover` / `db_close`; closed handles reject reads and writes. |
| In-memory WAL | `wal_new()` / `wal_append(entry)` / `wal_replay(tree)` / `wal_clear()` / `wal_truncate(before_timestamp)` / `wal_len()` / `wal_is_empty()` / `wal_entry_count(op_filter)`; `wal_entry_new(op, key, value, timestamp)`; `WALOpType` = `InsertOp` / `UpdateOp` / `DeleteOp`. |

## Query builder (`xiom.db.engine`)

`Query = { conditions, limit, offset }`; `QueryOp` = `Eq` / `Neq` / `Lt` /
`Lte` / `Gt` / `Gte`.

| Call | Semantics |
|------|-----------|
| `query_new()` | Empty query (no conditions, no limit/offset). |
| `query_where(q, op, value)` | Add an AND-ed condition on **values**. |
| `query_limit(q, limit)` | Truncate results (`requires: limit > 0`). |
| `query_offset(q, offset)` | Skip matches (`requires: offset >= 0`). |
| `query_execute(q, tree)` | Evaluate against a `BTree`: in-order scan, filter, offset, limit. |
| `query_condition_count` / `query_has_limit` / `query_has_offset` / `query_reset` | Introspection/reset. |
| `query_plan_full_scan()` / `plan_query(q, tree)` / `execute_plan(plan, q, tree)` | Planner scaffold (always full scan today). |

## Durable WAL segment (`xiom.db.wal_file`)

`WALFile = { path, next_lsn, heal_needed }`; `WALRecord = { lsn, op, key,
value, payload, timestamp }`; `WALOpKind` codes 1..10 (see `FORMATS.md`).

| Call | Returns | Semantics |
|------|---------|-----------|
| `wal_file_open(path)` | `WALFile` | Create/open; resume `next_lsn` from the last valid record; heal a torn tail once. |
| `wal_file_append(w, op, key, value)` / `wal_file_append_tagged(w, op, key, value, payload, timestamp)` | `Int` | Append; new LSN or `-1`. |
| `wal_file_flush(w)` | `Bool` | Durability seam (no-op until fsync). |
| `wal_file_replay(path)` | `Vec[WALRecord]` | Every well-formed record in file order; malformed/torn lines skipped. |
| `wal_file_len(path)` / `wal_file_last_lsn(path)` | `Int` | Record count / last valid LSN. |
| `wal_file_truncate(path, from_lsn)` | `Bool` | Keep records with `lsn >= from_lsn` (atomic rewrite; payloads preserved). |
| `wal_file_heal_tail(path)` | `Bool` | Terminate a torn trailing line. |
| `wal_file_next_lsn(w)` | `Int` | Next LSN to assign. |
| `wal_op_code` / `wal_op_from_code` / `wal_op_is_write` | `Int` / `WALOpKind` / `Bool` | Codec helpers (unknown codes map to `Insert` on decode). |

## Pages, checksum, buffer pool, storage engine (`xiom.db.storage.page`)

| Call | Returns | Semantics |
|------|---------|-----------|
| `Page.new(id, data, checksum)` | `Page` | `requires: data.len() <= 4096`. |
| `Page.is_valid()` | `Bool` | Stored checksum equals fresh CRC32C of `data`. |
| `page_compute_checksum(data)` | `Int` | CRC32C (Castagnoli); empty -> 0; KAT `0xE3069283` for `"123456789"`. |
| `BufferPool.new(capacity)` | `BufferPool` | `requires: capacity >= 1`. |
| `BufferPool.put(pool, page)` | `Bool` | Upsert; clock eviction; `false` when every frame is pinned (`rejects++`). |
| `BufferPool.get(pool, page_id)` | `Option[Page]` | Hit: `hits++` + reference bit; miss: `misses++`. |
| `BufferPool.pin_page` / `unpin_page` | `Bool` | Pinned frames are never evicted; `pin_count` reads the count. |
| `BufferPool.hit_ratio(pool)` | `Float64` | `hits / (hits + misses)` (0.0 when empty). |
| `StorageEngine.new(config)` | `StorageEngine` | Config + pool. |
| `StorageEngine.cache_page(eng, page)` | `Bool` | Cache (false when all pinned). |
| `StorageEngine.lookup_page(eng, page_id)` | `Option[Page]` | Lookup updating ref bits/stats. |

Statistics fields: `hits`, `misses`, `evictions`, `rejects`.

## Durable page file + page log (`xiom.db.storage.page_file`)

`PageFile = { path }`. Line format and versioning: `FORMATS.md`.

| Call | Returns | Semantics |
|------|---------|-----------|
| `page_file_open(path)` | `PageFile` | Handle. |
| `page_file_read(pf, id)` / `page_file_read_all(pf)` | `Option[Page]` / `Vec[Page]` | Valid pages by id / all valid pages in file order. |
| `page_file_write(pf, page)` | `Bool` | Upsert one page; unlisted pages survive; atomic rewrite. |
| `page_file_write_batch(pf, pages)` | `Bool` | Replace the whole page set; atomic rename. |
| `page_file_ids(pf)` / `page_file_count(pf)` | `Vec[Int]` / `Int` | Valid page ids / count. |
| `page_file_sync(pf)` | `Bool` | Durability seam. |
| `page_log_append(pf, page)` | `Bool` | Append one page version (O(1)). |
| `page_log_read_all(pf)` | `Vec[Page]` | Latest version per id (last valid occurrence wins). |
| `page_log_len(pf)` | `Int` | Raw well-formed entry count. |
| `page_log_heal_tail(pf)` | `Bool` | Terminate a torn trailing line. |

## Tuples (`xiom.db.storage.tuple`)

| Call | Returns | Semantics |
|------|---------|-----------|
| `Row.new(id, data)` / `Row.get_column(row, i)` / `Row.set_column(row, i, v)` / `Row.column_count(row)` | `Row` / `Option[Int]` / `Bool` / `Int` | Flat i64 row. |
| `tuple_encode_checked(row)` | `DbResult[Vec[Int]]` | Codec v1 bytes; `Err(ConstraintViolation)` above 255 fields. |
| `tuple_encode(row)` | `Vec[Int]` | Convenience; empty buffer when not encodable. |
| `tuple_decode(buf)` | `DbResult[Row]` | Strict: magic/version/count/length/type bytes; `Err(Corruption)` on any violation. |
| `tuple_encoded_len(row)` / `tuple_fits_page(row, page_size)` | `Int` / `Bool` | Size helpers. |
| `tuple_push_int_le(out, v)` / `tuple_read_int_le(buf, at)` | -- / `Int` | Shared LE i64 helpers (also used by the snapshot node codec). |
| `ResultSet.new(columns)` / `add_row` / `row_count` / `column_count` / `get_row` | -- | In-memory result materialization. |

## Free-space map (`xiom.db.storage.free_space_map`)

`free_space_map_new()`; `fsm_register_page(fsm, capacity)`; `fsm_record_used` /
`fsm_record_free` / `fsm_free_bytes` / `fsm_capacity_of`; `fsm_find_page(fsm,
needed)` (best-fit: tightest, then lowest id); `fsm_page_count` /
`fsm_total_free` / `fsm_validate`. `PageId` here is the FSM's slot id (see
`free_space_map.xi` header for the distinct `ids.PageId` bridge).

## Errors, config, ids, contracts

- `DbError` = `NotFound` / `DuplicateKey` / `ConstraintViolation` / `IOError` /
  `Corruption` / `StorageError`; `to_string`, `is_retryable` (only
  `StorageError`).
- `DatabaseConfig` = `{ page_size, buffer_pool_capacity, wal_enabled,
  btree_order }`; `DatabaseConfig.default()` (4096/64/true/4);
  `database_config_validate`; `database_config_from_core`.
- `ids`: `RowId` / `TableId` / `PageId` newtypes with `row_id`,
  `row_id_value`, `row_id_eq`, `row_id_next`, `table_id`, `table_id_value`,
  `table_id_eq`, `row_id_to_page_id`.
- `contracts`: `valid_btree_order`, `valid_key`, `sorted_keys`,
  `valid_range`, `non_decreasing`.
- `txn`: the in-memory `Transaction` state machine (`new`, `add_op`,
  `commit`, `abort`, `is_active`) used by the facade path; the durable
  transaction path is `db_file_txn_*` above.

## Compiler pin

The public API is compiled with **v0.64.1** and the C-ORBIT workarounds
documented in `COMPILER-FINDINGS-ORBITDB.md` (qualified enum variants, no
`Vec[Option]` element writes, copy-mutate-writeback for nested receivers,
Int-only keep-set for struct-vector dedup). Re-test the repro bundles before
bumping the toolchain.
