// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.db.engine


// ============================================================================
// XIOM-DB engine facade: DBFile + file-backed API. The B-tree, the in-memory
// query/WAL core, snapshot/pins and durable transactions live in sibling
// modules (re-exported here so `use xiom.db.engine` keeps the 0.2.x surface).
// ============================================================================

use xiom.io;
use xiom.db.wal_file;
use xiom.db.storage.page;
use xiom.db.storage.page_file;
use xiom.db.storage.block;
use xiom.db.storage.block_store;
use xiom.db.storage.byte_io;
use xiom.db.storage.tuple;
use xiom.db.error;
use xiom.db.contracts;
use xiom.db.secondary_index;
use xiom.db.catalog.schema;

pub use xiom.db.index.btree;
pub use xiom.db.engine.core;




// In-order walk collecting (key, payload) pairs of payload-bearing entries.
fn collect_typed_inorder(tree: &BTree, node_idx: Int,
                         keys: &mut Vec[Int], pays: &mut Vec[Vec[Int]]) {
  var node = tree.store.nodes[node_idx];
  if node.is_leaf {
    var i = 0;
    while i < node.keys.len() {
      let p = node_payload(&node, i);
      if p.len() > 0 {
        keys.push(node.keys[i]);
        pays.push(p);
      }
      i = i + 1;
    }
    return;
  }
  var i = 0;
  while i < node.keys.len() {
    if i < node.children.len() {
      collect_typed_inorder(tree, node.children[i], keys, pays);
    }
    let p = node_payload(&node, i);
    if p.len() > 0 {
      keys.push(node.keys[i]);
      pays.push(p);
    }
    i = i + 1;
  }
  if i < node.children.len() {
    collect_typed_inorder(tree, node.children[i], keys, pays);
  }
}

// Matching primary keys in key order (conditions ANDed; offset/limit apply
// to the matches). Plain int rows and undecodable payloads never match:
// typed predicates apply to typed rows.
pub fn db_file_query_typed(db: &DBFile, q: &TypedQuery) -> Vec[Int] {
  var keys = Vec[Int].new();
  var pays = Vec[Vec[Int]].new();
  collect_typed_inorder(&db.tree, db.tree.root, &mut keys, &mut pays);

  var hits = Vec[Int].new();
  var i = 0;
  while i < keys.len() {
    let p = pays[i];
    match tuple2_decode_row(&p) {
      Err(_) => {}
      Ok(row) => {
        let r: TypedRow = row;
        if typed_row_matches(&r, q.conditions) { hits.push(keys[i]); }
      }
    }
    i = i + 1;
  }

  var out = Vec[Int].new();
  var start = q.offset;
  var end = hits.len();
  if q.limit > 0 && start + q.limit < end {
    end = start + q.limit;
  }
  var k = start;
  while k < end {
    out.push(hits[k]);
    k = k + 1;
  }
  return out;
}

pub fn query_reset(q: &mut Query) {
  var empty = Vec[QueryCondition].new();
  q.conditions = empty;
  q.limit = 0;
  q.offset = 0;
  q.has_bounds = false;
  q.low = 0;
  q.high = 0;
  q.order = 0;
}

// Result ordering (M4.2): 0 = key ascending (default), 1 = value ascending,
// 2 = value descending. Ties keep key order; offset/limit apply after.
pub fn query_order(q: &mut Query, order: Int)
  requires: order == 0 || order == 1 || order == 2
{
  q.order = order;
}

pub fn query_order_kind(q: &Query) -> Int {
  return q.order;
}



// ============================================================================
// DATABASE API (from xiom.db.api.database)
// ============================================================================

pub type DatabaseConfig = {
  page_size: Int;
  buffer_pool_capacity: Int;
  wal_enabled: Bool;
  btree_order: Int;
}

pub type Database = {
  engine: Engine;
  open: Bool;
}

pub fn db_open(order: Int) -> Database
  requires: order >= 3
{
  var engine = engine_new(order);
  return Database{ engine: engine, open: true };
}

pub fn db_open_with(config: &DatabaseConfig) -> Database
  requires: config.btree_order >= 3
{
  var engine = engine_new(config.btree_order);
  return Database{ engine: engine, open: true };
}

pub fn db_insert(db: &mut Database, key: Int, value: Int) -> Bool {
  if !db.open { return false; }
  return engine_insert(&mut db.engine, key, value);
}

pub fn db_get(db: &Database, key: Int) -> Option[Int] {
  if !db.open { return None; }
  return engine_get(&db.engine, key);
}

pub fn db_update(db: &mut Database, key: Int, value: Int) -> Bool {
  if !db.open { return false; }
  return engine_update(&mut db.engine, key, value);
}

pub fn db_delete(db: &mut Database, key: Int) -> Bool {
  if !db.open { return false; }
  return engine_delete(&mut db.engine, key);
}

pub fn db_query(db: &Database, query: &Query) -> Vec[Int] {
  if !db.open { return Vec[Int].new(); }
  return engine_query(&db.engine, query);
}

pub fn db_range(db: &Database, low: Int, high: Int) -> Vec[Int]
  requires: low <= high
{
  if !db.open { return Vec[Int].new(); }
  return engine_range_query(&db.engine, low, high);
}

pub fn db_size(db: &Database) -> Int {
  if !db.open { return 0; }
  return engine_size(&db.engine);
}

pub fn db_recover(db: &mut Database) -> Bool {
  if !db.open { return false; }
  return engine_recover(&mut db.engine);
}

pub fn db_close(db: &mut Database) {
  if !db.open { return; }
  engine_flush_wal(&mut db.engine);
  db.open = false;
}

// ===========================================================================
// File-backed database facade (Phase 1/B4): WAL-before-ack on a real segment
// ===========================================================================

// A database whose log is the durable WAL segment (src/wal_file.xi). Every
// mutating call appends the record FIRST and only then applies it to the
// in-memory B-tree; `db_file_open` rebuilds the tree by replaying the segment
// (torn tail skipped). Data pages still rebuild from the log on open; the
// durable page file (storage/page_file.xi) takes over persistence next.
//
// Durability honesty (M2.1 second half, M1.2 S4 2026-10-13): `db_file_flush`
// is the wal_file flush seam and is now a REAL fsync (sync_io.sync_fd). With
// durability mode 1 (default) + two_phase, commits and checkpoint publishes
// are power-loss honest up to the synced seams. Until the next compiler pin
// re-vendors stdlib/runtime, run with XIOM_RUNTIME_DIR=<stdlib>/runtime
// (scripts/dev-env.* sets it).

// Transaction record codes (wal_file WALOpKind BeginTxn/CommitTxn/AbortTxn);
// Int codes keep replay dispatch aligned with `db_file_apply_record`.
const TXN_BEGIN_CODE: Int = 8;
const TXN_COMMIT_CODE: Int = 9;
const TXN_ABORT_CODE: Int = 10;

// One buffered transaction operation: code 2 = upsert (delete+insert, the
// same code the WAL uses for writes), code 3 = delete. `payload` carries the
// tagged WAL payload verbatim (empty for plain int ops); M5.3 buffer them so
// a typed record inside a txn window replays with its row bytes.
type TxOp = {
  code: Int;
  key: Int;
  value: Int;
  payload: Vec[Int];
}

pub type DBFile = {
  path: Str;
  order: Int;
  tree: BTree;
  wal: WALFile;
  records_since_ckpt: Int;
  txn_active: Bool;
  txn_ops: Vec[TxOp];
  wal_bytes: Int;
  page_format: Int;
  // Secondary indexes over VALUES (M4.2); handle-scoped, rebuilt on open via
  // `db_file_create_index`. Maintained by put/delete/txn-commit.
  indexes: Vec[SecondaryIndex];
  // Durability (M2.1): 0 = normal (ack without a flush; sync at
  // checkpoint only), 1 = immediate (REAL fsync at every commit ack since
  // M1.2 S4; stdlib wave 115). `two_phase` (immediate only) flushes the WAL
  // before a checkpoint publishes its snapshot. A failed flush latches
  // `failed`: writers refuse until the handle is reopened.
  durability: Int;
  two_phase: Bool;
  failed: Bool;
  // Last committed snapshot generation (0 = none), for `DBSnapshot`.
  snap_generation: Int;
  // M3 savepoint (single level): active marker + buffer length at capture.
  sp_active: Bool;
  sp_marker: Int;
  // Held append handle for the transaction window (BENCH-1 perf slice
  // 2026-10-16): one open per TRANSACTION instead of one per record; -1 when
  // no transaction holds it. Owned here, closed by commit/abort; a leaked fd
  // at process exit is harmless (segment appends are appended atomically).
  wal_fd: Int;
}


// Apply one buffered transaction op (see TxOp).
fn db_file_apply_txop(tree: &mut BTree, op: TxOp) {
  if op.code == 3 {
    let _ = btree_delete(tree, op.key);
    return;
  }
  let _ = btree_delete(tree, op.key);
  if op.payload.len() > 0 {
    if op.payload[0] != 1 { return; }
    var row = Vec[Int].new();
    var i = 1;
    while i < op.payload.len() {
      if op.payload[i] < 0 { return; }
      if op.payload[i] > 255 { return; }
      row.push(op.payload[i]);
      i = i + 1;
    }
    let _ = btree_insert_payload(tree, op.key, op.value, row);
    return;
  }
  let _ = btree_insert(tree, op.key, op.value);
}

// Open (or create) a file-backed database. Recovery: load the checkpoint
// snapshot when present, then replay ONLY records newer than its
// checkpoint_lsn; without a snapshot, replay the whole segment (Phase 1/B
// behavior). The torn tail is healed once by `wal_file_open`. **The v2
// byte-block container is the DEFAULT since M1.2 S4** (2026-10-13); v1
// (text page log) stays fully supported for reads (auto-detected on the
// on-disk format) and for writes via `db_file_open_cfg(path, order, 1)`.
// The handle's format decides how the next checkpoint writes, migrating a
// v1 file to v2 on its first write (migration-on-write).
pub fn db_file_open(path: Str, order: Int) -> DBFile {
  return db_file_open_cfg(path, order, 2);
}

pub fn db_file_open_cfg(path: Str, order: Int, page_format: Int) -> DBFile {
  var tree = btree_new(order);
  var snap_lsn = 0;
  var snap_gen = 0;
  let snap_path = path + ".snap";
  // Snapshot reads auto-detect the on-disk format: 'O' (0x4F) first byte =
  // v2 block store; anything else = v1 text page log (healed on open).
  let loaded = snap_load_auto(snap_path);
  match loaded {
    None => {}
    Some(s) => {
      let snap: Snapshot = s;
      tree = snap.tree;
      snap_lsn = snap.checkpoint_lsn;
      snap_gen = snap.generation;
    }
  }

  // Transaction-aware replay: writes between BeginTxn and CommitTxn are
  // buffered and applied only at the commit record; an unterminated trailing
  // transaction (crash before commit) is discarded -- committed/uncommitted
  // classification without a physical undo pass.
  let records = wal_file_replay(path);
  var pending = Vec[TxOp].new();
  var in_txn = false;
  var i = 0;
  while i < records.len() {
    let rec = records[i];
    if rec.lsn > snap_lsn {
      let code = wal_op_code(rec.op);
      if code == TXN_BEGIN_CODE {
        in_txn = true;
        pending = Vec[TxOp].new();
      } else if code == TXN_COMMIT_CODE {
        if in_txn {
          var p = 0;
          while p < pending.len() {
            let op = pending[p];
            db_file_apply_txop(&mut tree, op);
            p = p + 1;
          }
        }
        in_txn = false;
        pending = Vec[TxOp].new();
      } else if code == TXN_ABORT_CODE {
        in_txn = false;
        pending = Vec[TxOp].new();
      } else if code == 1 || code == 2 || code == 3 {
        if in_txn {
          pending.push(TxOp{ code: code, key: rec.key, value: rec.value,
                             payload: rec.payload });
        } else {
          db_file_apply_record(&mut tree, rec);
        }
      }
    }
    i = i + 1;
  }
  var wal = wal_file_open(path);
  if in_txn {
    // A dangling transaction window (crash before Commit/Abort) is finalized
    // with an explicit Abort record: without it, writes made after this open
    // would be replayed inside the stale window and silently discarded.
    let _ = wal_file_append(&mut wal, WALOpKind.AbortTxn, 0, 0);
  }
  var ops = Vec[TxOp].new();
  let wal_bytes = db_wal_size(path);
  var indexes = Vec[SecondaryIndex].new();
  return DBFile{ path: path, order: tree.order, tree: tree, wal: wal,
                 records_since_ckpt: 0, txn_active: false, txn_ops: ops,
                 wal_bytes: wal_bytes, page_format: page_format,
                 indexes: indexes, durability: 1, two_phase: false,
                 failed: false, snap_generation: snap_gen, sp_active: false,
                 sp_marker: 0, wal_fd: -1 };
}

// ---------------------------------------------------------------------------
// Input validation (H2): a path is a filename, not data -- reject empty,
// overlong, and line-terminator-carrying paths before creating a handle (the
// codecs are line-oriented, so CR/LF would corrupt diagnostics and tooling).
// ---------------------------------------------------------------------------

pub fn db_path_valid(path: Str) -> Bool {
  if str_len(path) == 0 { return false; }
  if str_len(path) > 4096 { return false; }
  if str_contains(path, "\n") { return false; }
  if str_contains(path, "\r") { return false; }
  return true;
}

// Validated open: Err(ConstraintViolation) for an invalid path or a btree
// order below 3; otherwise Ok with a handle from `db_file_open` (which is kept
// unchanged for existing callers).
pub fn db_file_open_checked(path: Str, order: Int) -> Result[DBFile, DbError] {
  if !db_path_valid(path) {
    return Err(DbError.ConstraintViolation);
  }
  if !valid_btree_order(order) {
    return Err(DbError.ConstraintViolation);
  }
  return Ok(db_file_open(path, order));
}

// Validated open with an explicit snapshot container format (1 = v1 text
// page log, 2 = v2 byte blocks). Reads always auto-detect the on-disk
// format; page_format only steers the next checkpoint's write.
pub fn db_file_open_checked_cfg(path: Str, order: Int, page_format: Int) -> Result[DBFile, DbError] {
  if !db_path_valid(path) {
    return Err(DbError.ConstraintViolation);
  }
  if !valid_btree_order(order) {
    return Err(DbError.ConstraintViolation);
  }
  if page_format != 1 && page_format != 2 {
    return Err(DbError.ConstraintViolation);
  }
  return Ok(db_file_open_cfg(path, order, page_format));
}


// Upsert with WAL-before-ack: append (Insert for new keys, Update for
// existing), then apply. Returns false when the log write fails.
pub fn db_file_put(db: &mut DBFile, key: Int, value: Int) -> Bool {
  // Auto-commit writes are rejected while a transaction is open.
  if db.txn_active { return false; }
  // Stale handle: another writer appended since our last write.
  if !db_file_guard(db) { return false; }
  // Latched after a failed flush/commit: refuse until reopen.
  if db.failed { return false; }
  // Qualified: this module imports wal_file but a program may also contain
  // txn's same-named WALOp variants; m225 scopes UNQUALIFIED resolution to the
  // declaring module, not to the importing consumer (see COMPILER-FINDINGS).
  var op = WALOpKind.Insert;
  var is_update = false;
  let existing = btree_search(&db.tree, key);
  match existing {
    None => {}
    Some(_) => {
      op = WALOpKind.Update;
      is_update = true;
    }
  }
  // Combined durable append (BENCH-1 perf slice 2026-10-16): ONE held
  // handle does write + (immediate mode) the gated sync, halving the
  // Windows open/close pairs per record. -1 write failure; -2 written but
  // sync failed -- the state updates below still run so the in-memory view
  // matches the old append-then-commit_sync ordering, and the handle latches
  // at the end.
  let lsn = wal_file_append_sync(&mut db.wal, op, key, value, db.durability == 1);
  if lsn == -1 { return false; }
  let sync_failed = lsn == -2;
  db.wal_bytes = db_wal_size(db.path);
  db.records_since_ckpt = db.records_since_ckpt + 1;
  if is_update { let _ = btree_delete(&mut db.tree, key); }
  let inserted = btree_insert(&mut db.tree, key, value);
  if inserted { db_file_note_value_change(db, key, existing, value, true); }
  if !inserted { return false; }
  if sync_failed { db.failed = true; return false; }
  return true;
}

// Max typed-row payload bytes for a btree order: the largest node page
// (order-1 entries, order children; 28-byte node header + 16 bytes per
// key/value + 8 bytes payload framing + the payload itself) must fit the
// smaller snapshot container budget (v2 block payload capacity). A
// `db_file_put_typed` above this is refused up front -- a checkpoint could
// otherwise fail only at snapshot time.
pub fn db_file_typed_payload_max(order: Int) -> Int {
  if order < 3 { return 0; }
  let keys = order - 1;
  let overhead = SNAP_NODE_HEADER_BYTES + 24 * keys + 8 * order;
  let room = block.block_payload_capacity() - overhead;
  if room <= 0 { return 0; }
  let per = room / keys;
  if per <= 0 { return 0; }
  return per;
}

// Typed-row upsert (M5.3): the payload is opaque row bytes (tuple codec v2
// rows or any caller encoding); the WAL record carries subtype 1 + the row
// bytes and its `value` mirrors the key (the pk). Same guards as
// `db_file_put`; typed writes are non-transactional in S3 (txn paths refuse
// while a transaction is active). Indexes hold int values only: any stale
// entry for the key is dropped, none is added (typed-column indexes = S4).
pub fn db_file_put_typed(db: &mut DBFile, key: Int, payload: Vec[Int]) -> Bool {
  if db.txn_active { return false; }
  if !db_file_guard(db) { return false; }
  if db.failed { return false; }
  if payload.len() > db_file_typed_payload_max(db.order) { return false; }
  // Payload bytes are 0..255 (the storage byte convention; the snapshot
  // codecs mask to a byte). Refuse anything else instead of losing bits.
  var v = 0;
  while v < payload.len() {
    if payload[v] < 0 { return false; }
    if payload[v] > 255 { return false; }
    v = v + 1;
  }
  var op = WALOpKind.Insert;
  var is_update = false;
  let existing = btree_search(&db.tree, key);
  match existing {
    None => {}
    Some(_) => {
      op = WALOpKind.Update;
      is_update = true;
    }
  }
  var tagged = Vec[Int].new();
  tagged.push(1); // subtype: typed row (tuple v2 bytes)
  var i = 0;
  while i < payload.len() {
    tagged.push(payload[i]);
    i = i + 1;
  }
  let lsn = wal_file_append_tagged_sync(&mut db.wal, op, key, key, tagged, 0, db.durability == 1);
  if lsn == -1 { return false; }
  let sync_failed = lsn == -2;
  db.wal_bytes = db_wal_size(db.path);
  db.records_since_ckpt = db.records_since_ckpt + 1;
  if is_update { let _ = btree_delete(&mut db.tree, key); }
  let inserted = btree_insert_payload(&mut db.tree, key, key, payload);
  if inserted { db_file_note_value_change(db, key, existing, 0, false); }
  if !inserted { return false; }
  if sync_failed { db.failed = true; return false; }
  return true;
}

pub fn db_file_delete(db: &mut DBFile, key: Int) -> Bool {
  // Auto-commit writes are rejected while a transaction is open.
  if db.txn_active { return false; }
  // Stale handle: another writer appended since our last write.
  if !db_file_guard(db) { return false; }
  if db.failed { return false; }
  let existing = btree_search(&db.tree, key);
  match existing {
    None => { return false; }
    Some(_) => {}
  }
  let lsn = wal_file_append_sync(&mut db.wal, WALOpKind.Delete, key, 0, db.durability == 1);
  if lsn == -1 { return false; }
  let sync_failed = lsn == -2;
  db.wal_bytes = db_wal_size(db.path);
  db.records_since_ckpt = db.records_since_ckpt + 1;
  let removed = btree_delete(&mut db.tree, key);
  if removed { db_file_note_value_change(db, key, existing, 0, false); }
  if !removed { return false; }
  if sync_failed { db.failed = true; return false; }
  return true;
}

pub fn db_file_get(db: &DBFile, key: Int) -> Option[Int] {
  return btree_search(&db.tree, key);
}

// M5.3: read a typed row's payload (None when the key is absent or the entry
// is a plain int row). Int rows keep reading through `db_file_get`.
pub fn db_file_get_typed(db: &DBFile, key: Int) -> Option[Vec[Int]] {
  return btree_search_payload(&db.tree, key);
}

// Key-range access on the live/recovered tree: values for keys in [low, high]
// inclusive, in key order. Mirrors `db_range`; same contract as
// `btree_range_query`.
pub fn db_file_range(db: &DBFile, low: Int, high: Int) -> Vec[Int]
  requires: low <= high
{
  return btree_range_query(&db.tree, low, high);
}

// Value-filter query on the live/recovered tree, planned and executed:
// conditions filter VALUES (not keys), key bounds (query_key_range) restrict
// the scanned key range first, a secondary index (M4.2) narrows value
// probes when present, `order` (default 0 = key ascending) sorts before
// `offset` skips matching values and `limit` truncates.
pub fn db_file_query(db: &DBFile, query: &Query) -> Vec[Int] {
  let plan = plan_query_with_index(query, &db.tree, db.indexes.len() > 0);
  if plan.kind == PlanKind.IndexValue && db.indexes.len() > 0 {
    let idx = db.indexes[0];
    return execute_index_value(&idx, &plan, query);
  }
  return execute_plan(&plan, query, &db.tree);
}

// ===========================================================================
// SECONDARY INDEXES (M4.2): value-ordered (value, pk) entries maintained by
// put/delete/txn-commit; handle-scoped, rebuilt on open. See
// src/secondary_index.xi for the structure.
// ===========================================================================


// Build a secondary index over the current tree; false for an empty name or
// a name already present.
pub fn db_file_create_index(db: &mut DBFile, name: Str) -> Bool {
  if str_len(name) == 0 { return false; }
  var i = 0;
  while i < db.indexes.len() {
    if db.indexes[i].name == name { return false; }
    i = i + 1;
  }
  var idx = secidx_new(name);
  var keys = Vec[Int].new();
  var vals = Vec[Int].new();
  btree_collect_pairs(&db.tree, db.tree.root, &mut keys, &mut vals);
  var j = 0;
  while j < keys.len() {
    secidx_add(&mut idx, vals[j], keys[j]);
    j = j + 1;
  }
  db.indexes.push(idx);
  return true;
}

pub fn db_file_drop_index(db: &mut DBFile, name: Str) -> Bool {
  var i = 0;
  while i < db.indexes.len() {
    if db.indexes[i].name == name {
      var j = i;
      while j < db.indexes.len() - 1 {
        db.indexes[j] = db.indexes[j + 1];
        j = j + 1;
      }
      db.indexes.pop();
      return true;
    }
    i = i + 1;
  }
  return false;
}

pub fn db_file_index_count(db: &DBFile) -> Int {
  return db.indexes.len();
}

pub fn db_file_index_name(db: &DBFile, at: Int) -> Str {
  if at < 0 || at >= db.indexes.len() { return ""; }
  return db.indexes[at].name;
}

// Direct probe for tests/tools: primary keys whose values fall in [lo, hi],
// in (value, pk) order.
pub fn db_file_index_range(db: &DBFile, name: Str, lo: Int, hi: Int) -> Vec[Int] {
  var i = 0;
  while i < db.indexes.len() {
    if db.indexes[i].name == name {
      let idx = db.indexes[i];
      return secidx_range_pks(&idx, lo, hi);
    }
    i = i + 1;
  }
  var empty = Vec[Int].new();
  return empty;
}

// Catalog tie-in: a flat-store index is over the value column (0) and
// non-unique; unique enforcement and multi-column indexes are later slices.
pub fn db_file_create_index_from_def(db: &mut DBFile, def: &IndexDef) -> Bool {
  if def.column != 0 { return false; }
  if def.unique { return false; }
  return db_file_create_index(db, def.name);
}

pub fn db_file_size(db: &DBFile) -> Int {
  return btree_size(&db.tree);
}

pub fn db_file_last_lsn(db: &DBFile) -> Int {
  return wal_file_next_lsn(&db.wal) - 1;
}

pub fn db_file_flush(db: &mut DBFile) -> Bool {
  if db.failed { return false; }
  let ok = byteio_sync(db.path);
  if !ok { db.failed = true; }
  return ok;
}

// --- durability API (M2.1 first half) --------------------------------------

// 0 = normal (ack without a flush), 1 = immediate (flush at every commit
// ack); invalid modes are rejected.
pub fn db_file_set_durability(db: &mut DBFile, mode: Int) -> Bool {
  if mode != 0 && mode != 1 { return false; }
  db.durability = mode;
  return true;
}

// Two-phase checkpoints flush the WAL before the snapshot publishes its
// header; only meaningful in immediate mode.
pub fn db_file_set_two_phase(db: &mut DBFile, enabled: Bool) -> Bool {
  if enabled && db.durability != 1 { return false; }
  db.two_phase = enabled;
  return true;
}

pub fn db_file_durability(db: &DBFile) -> Int { return db.durability; }

pub fn db_file_two_phase(db: &DBFile) -> Bool { return db.two_phase; }

pub fn db_file_failed(db: &DBFile) -> Bool { return db.failed; }

// (db_file_commit_sync was retired in the BENCH-1 perf slice 2026-10-16:
// auto-commit paths now sync inside `wal_file_append_sync` and the txn path
// syncs its held fd once at commit -- both through the same fault-gated
// byte_io sync seam, with the same latch-on-failure semantics.)

// ===========================================================================
// CHECKPOINT / SNAPSHOT (Phase 1/C): persist the B-tree node set into the
// durable page file; recovery loads the snapshot and replays only the tail.
// ===========================================================================
// Snapshot layout (append-only page log, storage/page_file.xi):
//   page 0                  header: root, order, node_count, lsn, generation
//   page g*STRIDE + i + 1   B-tree node i as of generation g
// A checkpoint appends new versions of ONLY the nodes that changed since the
// last committed generation, then appends the header page LAST: its generation
// commits the snapshot (every page of that generation is already in the log).
// Readers resolve, per node, the newest generation <= the committed header
// generation -- pages from an uncommitted later generation are ignored, so a
// crash mid-checkpoint leaves the previous snapshot fully valid. When the log
// grows past node_count + 64 entries, compaction rewrites one version of every
// page through page_file_write_batch (single atomic rename).
//
// Crash ordering (each step leaves a recoverable state):
//   1. node appends (generation g)       -> crash: g uncommitted, old header
//   2. header append (generation g)      -> snapshot committed at g
//   3. WAL anchor append + truncate      -> anchor kept, next_lsn resumes
//
// Durability honesty (M2.1 second half, M1.2 S4): the snapshot rides on
// byteio_sync/byteio_sync_dir (REAL fsync since stdlib waves 115/118): a
// checkpoint syncs the WAL (two_phase pre-sync), writes the generation,
// publishes the anchor, and syncs the file + directory -- power-loss honest
// up to those seams.

const SNAP_MAGIC: Int = 0x4F;       // 'O' -- snapshot page codec
const SNAP_VERSION: Int = 1;        // header page version (unchanged)
const SNAP_NODE_VERSION: Int = 2;   // node pages: + payload section (M5.3)
const SNAP_KIND_HEADER: Int = 0x48; // 'H'
const SNAP_KIND_NODE: Int = 0x4E;   // 'N'
const SNAP_HEADER_BYTES: Int = 44;
const SNAP_NODE_HEADER_BYTES: Int = 28;
const SNAP_PAGE_MAX_BYTES: Int = 4096;
// 2^32: page id = generation*STRIDE + node_idx + 1. The stride bounds a
// generation's node ids; ids never collide across generations, so older
// generations stay valid until a compaction rewrites the file atomically.
pub const SNAP_PAGE_STRIDE: Int = 4294967296;
// Compact once the raw log grows past node_count + this slack.
const SNAP_COMPACT_SLACK: Int = 64;

fn snap_page_id_for(gen: Int, node_idx: Int) -> Int {
  return gen * SNAP_PAGE_STRIDE + node_idx + 1;
}

type SnapshotMeta = {
  root: Int;
  order: Int;
  node_count: Int;
  checkpoint_lsn: Int;
  generation: Int;
}

type Snapshot = {
  tree: BTree;
  checkpoint_lsn: Int;
  generation: Int;
}

fn snap_header_page_bytes(root: Int, order: Int, node_count: Int,
                          checkpoint_lsn: Int, generation: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  out.push(SNAP_MAGIC);
  out.push(SNAP_VERSION);
  out.push(SNAP_KIND_HEADER);
  out.push(0);
  tuple_push_int_le(&mut out, root);
  tuple_push_int_le(&mut out, order);
  tuple_push_int_le(&mut out, node_count);
  tuple_push_int_le(&mut out, checkpoint_lsn);
  tuple_push_int_le(&mut out, generation);
  return out;
}

fn snap_node_page_bytes(node: &BTreeNode) -> Vec[Int] {
  var out = Vec[Int].new();
  out.push(SNAP_MAGIC);
  out.push(SNAP_NODE_VERSION);
  out.push(SNAP_KIND_NODE);
  var leaf = 0;
  if node.is_leaf { leaf = 1; }
  out.push(leaf);
  tuple_push_int_le(&mut out, node.keys.len());
  tuple_push_int_le(&mut out, node.children.len());
  tuple_push_int_le(&mut out, 0); // reserved
  var i = 0;
  while i < node.keys.len() {
    tuple_push_int_le(&mut out, node.keys[i]);
    i = i + 1;
  }
  i = 0;
  while i < node.values.len() {
    tuple_push_int_le(&mut out, node.values[i]);
    i = i + 1;
  }
  i = 0;
  while i < node.children.len() {
    tuple_push_int_le(&mut out, node.children[i]);
    i = i + 1;
  }
  // Payload section (node version 2): u64 LE count + per entry u64 LE length
  // + bytes (the node-page family's integer width). Parallel to keys; empty
  // = plain int entry.
  tuple_push_int_le(&mut out, node.keys.len());
  i = 0;
  while i < node.keys.len() {
    let p = node_payload(node, i);
    tuple_push_int_le(&mut out, p.len());
    var k = 0;
    while k < p.len() {
      out.push(p[k] & 0xFF);
      k = k + 1;
    }
    i = i + 1;
  }
  return out;
}

// Strict decode: magic/version/kind, exact length, sane flags and counts.
// Accepts node version 1 (legacy: no payload section -> empty payloads) and
// version 2 (payload section). Returns None on any violation -- a snapshot
// either restores whole or not.
fn snap_decode_node(data: &Vec[Int]) -> Option[BTreeNode] {
  if data.len() < SNAP_NODE_HEADER_BYTES { return None; }
  if data[0] != SNAP_MAGIC { return None; }
  let version = data[1];
  if version != SNAP_VERSION && version != SNAP_NODE_VERSION { return None; }
  if data[2] != SNAP_KIND_NODE { return None; }
  let key_count = tuple_read_int_le(data, 4);
  let child_count = tuple_read_int_le(data, 12);
  if key_count < 0 { return None; }
  if child_count < 0 { return None; }

  let base = SNAP_NODE_HEADER_BYTES + 16 * key_count + 8 * child_count;
  if version == SNAP_NODE_VERSION {
    if data.len() < base + 8 { return None; }
    let pcount = tuple_read_int_le(data, base);
    if pcount != key_count { return None; }
    var at = base + 8;
    var j = 0;
    while j < pcount {
      if at + 8 > data.len() { return None; }
      let plen = tuple_read_int_le(data, at);
      if plen < 0 { return None; }
      at = at + 8 + plen;
      if at > data.len() { return None; }
      j = j + 1;
    }
    if at != data.len() { return None; }
  } else {
    if data.len() != base { return None; }
  }

  var keys = Vec[Int].new();
  var values = Vec[Int].new();
  var children = Vec[Int].new();
  var at = SNAP_NODE_HEADER_BYTES;
  var i = 0;
  while i < key_count {
    keys.push(tuple_read_int_le(data, at));
    at = at + 8;
    i = i + 1;
  }
  i = 0;
  while i < key_count {
    values.push(tuple_read_int_le(data, at));
    at = at + 8;
    i = i + 1;
  }
  i = 0;
  while i < child_count {
    children.push(tuple_read_int_le(data, at));
    at = at + 8;
    i = i + 1;
  }

  var payloads = Vec[Vec[Int]].new();
  if version == SNAP_NODE_VERSION {
    var at2 = base + 8;
    var j2 = 0;
    while j2 < key_count {
      let plen2 = tuple_read_int_le(data, at2);
      at2 = at2 + 8;
      var p = Vec[Int].new();
      var k2 = 0;
      while k2 < plen2 {
        p.push(data[at2 + k2] & 0xFF);
        k2 = k2 + 1;
      }
      payloads.push(p);
      at2 = at2 + plen2;
      j2 = j2 + 1;
    }
  } else {
    var j3 = 0;
    while j3 < key_count {
      payloads.push(Vec[Int].new());
      j3 = j3 + 1;
    }
  }

  let leaf = data[3] == 1;
  if leaf && child_count != 0 { return None; }
  if !leaf && child_count == 0 { return None; }
  return Some(BTreeNode{ keys: keys, values: values, payloads: payloads,
                         children: children, is_leaf: leaf });
}

fn snap_decode_header(data: &Vec[Int]) -> Option[SnapshotMeta] {
  if data.len() < SNAP_HEADER_BYTES { return None; }
  if data[0] != SNAP_MAGIC { return None; }
  if data[1] != SNAP_VERSION { return None; }
  if data[2] != SNAP_KIND_HEADER { return None; }
  return Some(SnapshotMeta{
    root: tuple_read_int_le(data, 4),
    order: tuple_read_int_le(data, 12),
    node_count: tuple_read_int_le(data, 20),
    checkpoint_lsn: tuple_read_int_le(data, 28),
    generation: tuple_read_int_le(data, 36),
  });
}

// Header selection: a committed checkpoint appends its header page LAST, so
// among valid header pages (id 0) the highest generation is the active one.
fn snap_read_meta(pages: &Vec[Page]) -> Option[SnapshotMeta] {
  var best = SnapshotMeta{ root: 0, order: 3, node_count: 0, checkpoint_lsn: 0, generation: -1 };
  var found = false;
  var i = 0;
  while i < pages.len() {
    let pg = pages[i];
    if pg.id == 0 {
      let dec = snap_decode_header(&pg.data);
      match dec {
        None => {}
        Some(m) => {
          let mm: SnapshotMeta = m;
          if mm.generation > best.generation {
            best = mm;
            found = true;
          }
        }
      }
    }
    i = i + 1;
  }
  if !found { return None; }
  return Some(best);
}

// One committed page per node: the newest generation <= active_gen. Returns
// None when any node has no committed page (the snapshot is then unusable).
fn snap_resolve_pages(pages: &Vec[Page], node_count: Int,
                       active_gen: Int) -> Option[Vec[Page]] {
  var best_gen = Vec[Int].new();
  var best = Vec[Page].new();
  var i = 0;
  while i < node_count {
    var empty = Vec[Int].new();
    best_gen.push(-1);
    best.push(Page.new(0, empty, 0));
    i = i + 1;
  }

  var p = 0;
  while p < pages.len() {
    let pg = pages[p];
    if pg.id > 0 {
      let zero = pg.id - 1;
      let idx = zero % SNAP_PAGE_STRIDE;
      let gen = zero / SNAP_PAGE_STRIDE;
      if idx < node_count && gen <= active_gen {
        if gen > best_gen[idx] {
          best_gen[idx] = gen;
          best[idx] = pg;
        }
      }
    }
    p = p + 1;
  }

  i = 0;
  while i < node_count {
    if best_gen[i] < 0 { return None; }
    i = i + 1;
  }
  return Some(best);
}

// Atomic compaction: one page per node + the header at generation `gen`,
// installed through page_file_write_batch (single rename). Used when the log
// has grown past node_count + slack.
fn snap_compact(path: Str, tree: &mut BTree, checkpoint_lsn: Int, gen: Int) -> Bool {
  var pages = Vec[Page].new();
  var i = 0;
  while i < tree.store.nodes.len() {
    let node = tree.store.nodes[i];
    let data = snap_node_page_bytes(&node);
    if data.len() > SNAP_PAGE_MAX_BYTES { return false; }
    pages.push(Page.new(snap_page_id_for(gen, i), data, page_compute_checksum(&data)));
    i = i + 1;
  }
  let hdr = snap_header_page_bytes(tree.root, tree.order, tree.store.nodes.len(),
                                   checkpoint_lsn, gen);
  if hdr.len() > SNAP_PAGE_MAX_BYTES { return false; }
  pages.push(Page.new(0, hdr, page_compute_checksum(&hdr)));
  let pf = page_file_open(path);
  let wrote = page_file_write_batch(&pf, pages);
  if wrote { ns_mark_clean(&mut tree.store); }
  return wrote;
}

// Commit a checkpoint incrementally: append new versions of only the DIRTY
// nodes (tracked by the NodeStore), then append the header page (id 0,
// generation = prior + 1) LAST as the commit point. Forces a full write when
// there is no valid prior snapshot or when pages of an uncommitted crashed
// generation linger (they must never become the only version of a node).
// Returns the committed generation, or -1 when nothing was committed; the
// previous snapshot stays valid in every failure mode. `allow_compact` is
// false while a snapshot pin is live (M3): the compaction branch is deferred
// (counted) and the incremental append continues.
fn snap_flush(path: Str, tree: &mut BTree, checkpoint_lsn: Int, allow_compact: Bool) -> Int {
  let pf = page_file_open(path);
  let pages = page_log_read_all(&pf);
  let meta_found = snap_read_meta(&pages);
  var prior_gen = 0;
  var have_prior = false;
  match meta_found {
    None => {}
    Some(m) => {
      let mm: SnapshotMeta = m;
      prior_gen = mm.generation;
      have_prior = true;
    }
  }

  var has_uncommitted = false;
  var q = 0;
  while q < pages.len() {
    let pg2 = pages[q];
    if pg2.id > 0 {
      let z = pg2.id - 1;
      let g2 = z / SNAP_PAGE_STRIDE;
      if g2 == prior_gen + 1 { has_uncommitted = true; }
    }
    q = q + 1;
  }
  let write_all = !have_prior || has_uncommitted;

  let gen = prior_gen + 1;
  let entries = page_log_len(&pf);
  if entries > tree.store.nodes.len() + SNAP_COMPACT_SLACK {
    if !allow_compact {
      // M3: compaction would rewrite one version per node, dropping the older
      // generations a live pin may still need. Defer; the next checkpoint
      // after the pin is released compacts.
      tree.store.compaction_deferred = tree.store.compaction_deferred + 1;
    } else {
      if snap_compact(path, tree, checkpoint_lsn, gen) { return gen; }
      return -1;
    }
  }

  var i = 0;
  while i < tree.store.nodes.len() {
    var should_write = write_all;
    if !should_write { should_write = tree.store.dirty[i]; }
    if should_write {
      let node = tree.store.nodes[i];
      let data = snap_node_page_bytes(&node);
      if data.len() > SNAP_PAGE_MAX_BYTES { return -1; }
      let pg = Page.new(snap_page_id_for(gen, i), data, page_compute_checksum(&data));
      if !page_log_append(&pf, pg) { return -1; }
    }
    i = i + 1;
  }

  let hdr = snap_header_page_bytes(tree.root, tree.order, tree.store.nodes.len(),
                                   checkpoint_lsn, gen);
  if hdr.len() > SNAP_PAGE_MAX_BYTES { return -1; }
  let hp = Page.new(0, hdr, page_compute_checksum(&hdr));
  if page_log_append(&pf, hp) {
    ns_mark_clean(&mut tree.store);
    return gen;
  }
  return -1;
}

// Load a snapshot; None when absent or invalid at ANY level (page checksum,
// header, node codec, node count, child-pointer range). The caller then
// falls back to full WAL replay.
fn snap_load(path: Str) -> Option[Snapshot] {
  let pf = page_file_open(path);
  let pages = page_log_read_all(&pf);
  let meta_found = snap_read_meta(&pages);
  var meta = SnapshotMeta{ root: 0, order: 3, node_count: 0, checkpoint_lsn: 0, generation: -1 };
  match meta_found {
    None => { return None; }
    Some(m) => {
      let mm: SnapshotMeta = m;
      meta = mm;
    }
  }
  if meta.order < 3 { return None; }
  if meta.node_count < 1 { return None; }
  if meta.node_count >= SNAP_PAGE_STRIDE { return None; }
  if meta.root < 0 { return None; }
  if meta.root >= meta.node_count { return None; }

  let resolved = snap_resolve_pages(&pages, meta.node_count, meta.generation);
  var best = Vec[Page].new();
  match resolved {
    None => { return None; }
    Some(v) => {
      let vv: Vec[Page] = v;
      best = vv;
    }
  }

  var nodes = Vec[BTreeNode].new();
  var i = 0;
  while i < meta.node_count {
    let pg = best[i];
    let dec = snap_decode_node(&pg.data);
    match dec {
      None => { return None; }
      Some(n) => {
        let nd: BTreeNode = n;
        nodes.push(nd);
      }
    }
    i = i + 1;
  }

  // Child pointers must address loaded nodes: a CRC-valid but semantically
  // corrupt snapshot must not reach search/traverse as a dangling pointer.
  var j = 0;
  while j < nodes.len() {
    let nd = nodes[j];
    var c = 0;
    while c < nd.children.len() {
      if nd.children[c] < 0 { return None; }
      if nd.children[c] >= meta.node_count { return None; }
      c = c + 1;
    }
    j = j + 1;
  }

  // Loaded nodes are clean: their pages are already committed.
  var dirty = Vec[Bool].new();
  var births = Vec[Int].new();
  var di = 0;
  while di < nodes.len() {
    dirty.push(false);
    births.push(0);
    di = di + 1;
  }
  var pins = Vec[DBSnapshot].new();
  var store = NodeStore{ nodes: nodes, dirty: dirty, births: births, pins: pins,
                         pin_clock: 0, compaction_deferred: 0 };
  var tree = BTree{ root: meta.root, order: meta.order, store: store };
  return Some(Snapshot{ tree: tree, checkpoint_lsn: meta.checkpoint_lsn, generation: meta.generation });
}

// --- v2 snapshot container (byte blocks; M1.2 S3) --------------------------
// The node payload codec is unchanged (`snap_node_page_bytes`); only the
// container changes: node index = block page_id, snapshot generation = block
// generation, and the block store's header slot carries the meta (root,
// order, node_count, checkpoint_lsn). Reads auto-detect by first byte.

fn snap_format_v2(path: Str) -> Bool {
  match byteio_read_at(path, 0, 1) {
    Some(b) => {
      if b.len() == 1 && b[0] == 0x4F { return true; }
      return false;
    }
    None => { return false; }
  }
}

fn snap_load_auto(path: Str) -> Option[Snapshot] {
  if snap_format_v2(path) { return snap_load_v2(path); }
  let pf = page_file_open(path);
  let _ = page_log_heal_tail(&pf);
  return snap_load(path);
}

// Read a v2 snapshot through the block store: the committed header carries
// the meta, one committed block per node index carries the node payload.
// Same strictness as v1: any gap/codec/range violation is None.
fn snap_load_v2(path: Str) -> Option[Snapshot] {
  let bs = block_store_open(path);
  if !bs.committed { return None; }
  let node_count = bs.header.node_count;
  let order = bs.header.order;
  let root = bs.header.root;
  if order < 3 { return None; }
  if node_count < 1 { return None; }
  if node_count >= SNAP_PAGE_STRIDE { return None; }
  if root < 0 { return None; }
  if root >= node_count { return None; }

  var nodes = Vec[BTreeNode].new();
  var i = 0;
  while i < node_count {
    match block_store_read(&bs, i) {
      Some(p) => {
        match snap_decode_node(&p.payload) {
          Some(nd) => { nodes.push(nd); }
          None => { return None; }
        }
      }
      None => { return None; }
    }
    i = i + 1;
  }

  var j = 0;
  while j < nodes.len() {
    let nd = nodes[j];
    var c = 0;
    while c < nd.children.len() {
      if nd.children[c] < 0 { return None; }
      if nd.children[c] >= node_count { return None; }
      c = c + 1;
    }
    j = j + 1;
  }

  var dirty = Vec[Bool].new();
  var births = Vec[Int].new();
  var di = 0;
  while di < nodes.len() {
    dirty.push(false);
    births.push(0);
    di = di + 1;
  }
  var pins = Vec[DBSnapshot].new();
  var store = NodeStore{ nodes: nodes, dirty: dirty, births: births, pins: pins,
                         pin_clock: 0, compaction_deferred: 0 };
  var tree = BTree{ root: root, order: order, store: store };
  return Some(Snapshot{ tree: tree, checkpoint_lsn: bs.header.checkpoint_lsn,
                        generation: bs.header.committed_generation });
}

// Full v2 write from the TREE (all nodes + header commit) into a temp file,
// then one atomic rename. Used for migration (v1 -> v2), format flips, and
// compaction. The original file is untouched until the rename succeeds.
fn v2_rewrite_all(path: Str, tree: &mut BTree, gen: Int, checkpoint_lsn: Int) -> Bool {
  let tmp = path + ".rw";
  match io.remove_file(tmp) { Ok(_) => {} Err(_) => {} }
  var bs = block_store_open(tmp);
  var i = 0;
  while i < tree.store.nodes.len() {
    let node = tree.store.nodes[i];
    let data = snap_node_page_bytes(&node);
    if block_store_put(&mut bs, gen, i, &data) < 0 { return false; }
    i = i + 1;
  }
  let h = BlockHeader{
    root: tree.root,
    order: tree.order,
    node_count: tree.store.nodes.len(),
    checkpoint_lsn: checkpoint_lsn,
    committed_generation: gen,
    block_count: bs.block_count,
    next_page_id: 0,
  };
  if !block_store_commit(&mut bs, &h) { return false; }
  match io.rename(tmp, path) {
    Ok(_) => {}
    Err(_) => { return false; }
  }
  return true;
}

// v2 incremental flush: append new versions of only the DIRTY nodes at
// gen = committed + 1, then commit the header slot. A v1 (or absent) file is
// rewritten whole (migration-on-write). Crashed partial generations are
// overwritten by the same-gen rewrites on the next attempt, so they can
// never become the only version of a node. `allow_compact` is false while a
// snapshot pin is live (M3): the block-count rewrite (compaction) is deferred
// (counted) and the incremental append continues. Returns the committed
// generation, or -1 (the previous snapshot stays valid in every failure
// mode).
fn snap_flush_v2(path: Str, tree: &mut BTree, checkpoint_lsn: Int, allow_compact: Bool) -> Int {
  let is_v2 = snap_format_v2(path);
  if !is_v2 {
    let gen = 1;
    if v2_rewrite_all(path, tree, gen, checkpoint_lsn) {
      ns_mark_clean(&mut tree.store);
      return gen;
    }
    return -1;
  }

  var bs = block_store_open(path);
  var prior_gen = 0;
  var have_prior = false;
  if bs.committed {
    prior_gen = bs.header.committed_generation;
    have_prior = true;
  }
  let gen = prior_gen + 1;

  if !have_prior || bs.block_count > tree.store.nodes.len() + SNAP_COMPACT_SLACK {
    if have_prior && !allow_compact {
      // M3: the whole-file rewrite drops older block generations a live pin
      // may still need. Defer; append incrementally instead.
      tree.store.compaction_deferred = tree.store.compaction_deferred + 1;
    } else {
      if v2_rewrite_all(path, tree, gen, checkpoint_lsn) {
        ns_mark_clean(&mut tree.store);
        return gen;
      }
      return -1;
    }
  }

  var i = 0;
  while i < tree.store.nodes.len() {
    if tree.store.dirty[i] {
      let node = tree.store.nodes[i];
      let data = snap_node_page_bytes(&node);
      if block_store_put(&mut bs, gen, i, &data) < 0 { return -1; }
    }
    i = i + 1;
  }
  let h = BlockHeader{
    root: tree.root,
    order: tree.order,
    node_count: tree.store.nodes.len(),
    checkpoint_lsn: checkpoint_lsn,
    committed_generation: gen,
    block_count: bs.block_count,
    next_page_id: 0,
  };
  if !block_store_commit(&mut bs, &h) { return -1; }
  ns_mark_clean(&mut tree.store);
  return gen;
}

// Migrate an existing v1 text snapshot to v2 in place (idempotent; absent
// or already-v2 snapshots are a no-op success). Reads through the same
// auto-detect loader, writes a fresh v2 store via temp+rename.
pub fn db_file_migrate_snapshot(path: Str) -> Bool {
  let snap_path = path + ".snap";
  if snap_format_v2(snap_path) { return true; }
  match snap_load(snap_path) {
    None => { return true; }
    Some(s) => {
      let snap: Snapshot = s;
      var tree = snap.tree;
      return v2_rewrite_all(snap_path, &mut tree, snap.generation + 1, snap.checkpoint_lsn);
    }
  }
}

// Checkpoint: commit an incremental snapshot of the current tree (only the
// nodes that changed since the last committed generation are appended; the
// header page commits the generation), append the Checkpoint anchor record,
// then truncate the segment to keep the anchor and everything after it.
// Returns the anchor LSN, or -1 when the snapshot could not be committed (the
// WAL is untouched in that case).
pub fn db_file_checkpoint(db: &mut DBFile) -> Int {
  // A pending transaction's records must not be truncated: truncation keeps
  // records >= the anchor, and the checkpoint_lsn gate would skip a later
  // commit record's ops. Reject while a transaction is active.
  if db.txn_active { return -1; }
  // A stale handle must not snapshot its older tree over a newer WAL.
  if !db_file_guard(db) { return -1; }
  if db.failed { return -1; }
  let snap_path = db.path + ".snap";
  let snap_lsn = wal_file_next_lsn(&db.wal) - 1;
  // Two-phase (immediate mode): the WAL must be durable BEFORE the snapshot
  // publishes its header, so a crash can never leave a snapshot that runs
  // ahead of the log (docs/REFERENCE-STUDY.md; redb 2PC).
  if db.durability == 1 && db.two_phase {
    if !byteio_sync(db.path) {
      db.failed = true;
      return -1;
    }
  }
  var gen = -1;
  // M3: while a snapshot pin is live the compaction branch defers (counted);
  // incremental appends, the anchor and the WAL truncate are unaffected.
  let allow_compact = db.tree.store.pins.len() == 0;
  if db.page_format == 2 {
    gen = snap_flush_v2(snap_path, &mut db.tree, snap_lsn, allow_compact);
  } else if snap_format_v2(snap_path) {
    // Handle writes v1 while the file is v2: rewrite whole via the batch
    // path (single rename), keeping the format on-disk authoritative. That
    // rewrite is compaction-class: defer the checkpoint while pinned.
    if !allow_compact {
      db.tree.store.compaction_deferred = db.tree.store.compaction_deferred + 1;
      return -1;
    }
    var pgen = 0;
    let bs = block_store_open(snap_path);
    if bs.committed { pgen = bs.header.committed_generation; }
    if snap_compact(snap_path, &mut db.tree, snap_lsn, pgen + 1) { gen = pgen + 1; }
  } else {
    let pf = page_file_open(snap_path);
    // A torn trailing append must not merge with this checkpoint's entries.
    let _ = page_log_heal_tail(&pf);
    gen = snap_flush(snap_path, &mut db.tree, snap_lsn, allow_compact);
  }
  if gen < 0 { return -1; }
  db.snap_generation = gen;

  var payload = Vec[Int].new();
  payload.push(gen);
  payload.push(db.tree.store.nodes.len());
  payload.push(db.tree.order);
  let anchor = wal_file_append_tagged(&mut db.wal, WALOpKind.Checkpoint,
                                      snap_lsn, db.tree.root, payload, 0);
  if anchor < 0 { return -1; }

  // Best-effort compaction: keeping lsn >= anchor retains the anchor itself,
  // so next_lsn still resumes correctly. A failed truncate leaves older
  // records that `db_file_open` skips via the snapshot's checkpoint_lsn gate.
  let _ = wal_file_truncate(db.path, anchor);
  db.wal_bytes = db_wal_size(db.path);
  db.records_since_ckpt = 0;
  // Post-commit flush (immediate mode): a failure latches the handle; the
  // checkpoint itself may still have committed (the caller can inspect
  // db_file_failed). WAL first, then the snapshot.
  if db.durability == 1 {
    if !byteio_sync(db.path) {
      db.failed = true;
      return -1;
    }
    if !byteio_sync(snap_path) {
      db.failed = true;
      return -1;
    }
  }
  return anchor;
}

// Policy hook: checkpoint when at least `limit` records were logged since the
// last checkpoint. Returns the anchor LSN when a checkpoint ran, or -1 when
// the threshold is not reached (or the checkpoint failed).
pub fn db_file_maybe_checkpoint(db: &mut DBFile, limit: Int) -> Int
  requires: limit >= 1
{
  if db.records_since_ckpt < limit { return -1; }
  return db_file_checkpoint(db);
}

// ===========================================================================
// DURABLE TRANSACTIONS (D2): single-active-transaction API. Operations are
// logged as they happen (WAL-before-ack) but applied to the tree only at
// commit; abort -- or a crash before the commit record -- discards them.
// Recovery classifies committed vs uncommitted at the Begin/Commit records
// (see db_file_open), so no physical undo pass is needed.
// ===========================================================================

pub fn db_file_txn_active(db: &DBFile) -> Bool {
  return db.txn_active;
}

// Lazy held append handle for the transaction window (BENCH-1 perf slice
// 2026-10-16): opened on first use, reused by every txn append, closed by
// commit/abort. One open/close pair per TRANSACTION instead of one per
// record (docs/BENCH-1.md finding #1). WAL appends stay ungated; the sync
// seam still fires the kind-1 gate exactly once per durable commit.
fn db_txn_fd(db: &mut DBFile) -> Int {
  if db.wal_fd >= 0 { return db.wal_fd; }
  match byteio_open_append(db.path) {
    None => { return -1; }
    Some(fd) => {
      db.wal_fd = fd;
      return fd;
    }
  }
}

// Close the held transaction handle (if any). Best-effort; the fd owner is
// the handle itself, so commit/abort must call this on every exit path.
fn db_txn_close_fd(db: &mut DBFile) {
  if db.wal_fd >= 0 {
    let _ = byteio_close_append(db.wal_fd);
    db.wal_fd = -1;
  }
}

pub fn db_file_txn_begin(db: &mut DBFile) -> Bool {
  if db.txn_active { return false; }
  if !db_file_guard(db) { return false; }
  if db.failed { return false; }
  let fd = db_txn_fd(db);
  if fd < 0 { return false; }
  let lsn = wal_file_append_fd(&mut db.wal, fd, WALOpKind.BeginTxn, 0, 0);
  if lsn < 0 {
    db_txn_close_fd(db);
    return false;
  }
  db.wal_bytes = db_wal_size(db.path);
  db.records_since_ckpt = db.records_since_ckpt + 1;
  db.txn_active = true;
  db.txn_ops = Vec[TxOp].new();
  db.sp_active = false;
  db.sp_marker = 0;
  return true;
}

// Buffered upsert (applied as delete+insert on commit/replay; idempotent).
pub fn db_file_txn_put(db: &mut DBFile, key: Int, value: Int) -> Bool {
  if !db.txn_active { return false; }
  if !db_file_guard(db) { return false; }
  if db.failed { return false; }
  let fd = db_txn_fd(db);
  if fd < 0 { return false; }
  let lsn = wal_file_append_fd(&mut db.wal, fd, WALOpKind.Update, key, value);
  if lsn < 0 { return false; }
  db.wal_bytes = db_wal_size(db.path);
  db.records_since_ckpt = db.records_since_ckpt + 1;
  db.txn_ops.push(TxOp{ code: 2, key: key, value: value,
                        payload: Vec[Int].new() });
  return true;
}

// Buffered delete (idempotent: deleting a missing key is a no-op on apply).
pub fn db_file_txn_delete(db: &mut DBFile, key: Int) -> Bool {
  if !db.txn_active { return false; }
  if !db_file_guard(db) { return false; }
  if db.failed { return false; }
  let fd = db_txn_fd(db);
  if fd < 0 { return false; }
  let lsn = wal_file_append_fd(&mut db.wal, fd, WALOpKind.Delete, key, 0);
  if lsn < 0 { return false; }
  db.wal_bytes = db_wal_size(db.path);
  db.records_since_ckpt = db.records_since_ckpt + 1;
  db.txn_ops.push(TxOp{ code: 3, key: key, value: 0,
                        payload: Vec[Int].new() });
  return true;
}

// Commit: append the CommitTxn record FIRST (durability), then apply the
// buffered ops to the in-memory tree. The whole window (Begin + ops +
// Commit) rides ONE held handle; immediate mode fsyncs it once, through the
// same gated sync seam as before, and a failed sync latches the handle.
pub fn db_file_txn_commit(db: &mut DBFile) -> Bool {
  if !db.txn_active { return false; }
  if !db_file_guard(db) { return false; }
  if db.failed { return false; }
  let fd = db_txn_fd(db);
  if fd < 0 { return false; }
  let lsn = wal_file_append_fd(&mut db.wal, fd, WALOpKind.CommitTxn, 0, 0);
  if lsn < 0 { return false; }
  db.wal_bytes = db_wal_size(db.path);
  db.records_since_ckpt = db.records_since_ckpt + 1;
  var k = 0;
  while k < db.txn_ops.len() {
    let op = db.txn_ops[k];
    let old = btree_search(&db.tree, op.key);
    db_file_apply_txop(&mut db.tree, op);
    if op.code == 3 {
      db_file_note_value_change(db, op.key, old, 0, false);
    } else {
      db_file_note_value_change(db, op.key, old, op.value, true);
    }
    k = k + 1;
  }
  db.txn_active = false;
  db.txn_ops = Vec[TxOp].new();
  db.sp_active = false;
  db.sp_marker = 0;
  var sync_failed = false;
  if db.durability == 1 {
    if !byteio_sync_fd(fd) { sync_failed = true; }
  }
  db_txn_close_fd(db);
  if sync_failed { db.failed = true; return false; }
  return true;
}

// Abort: append the AbortTxn marker (audit trail) and discard the buffer.
pub fn db_file_txn_abort(db: &mut DBFile) -> Bool {
  if !db.txn_active { return false; }
  if !db_file_guard(db) { return false; }
  if db.failed { return false; }
  let fd = db_txn_fd(db);
  if fd < 0 { return false; }
  let lsn = wal_file_append_fd(&mut db.wal, fd, WALOpKind.AbortTxn, 0, 0);
  if lsn < 0 { return false; }
  db.wal_bytes = db_wal_size(db.path);
  db.records_since_ckpt = db.records_since_ckpt + 1;
  db.txn_active = false;
  db.txn_ops = Vec[TxOp].new();
  db.sp_active = false;
  db.sp_marker = 0;
  db_txn_close_fd(db);
  return true;
}

// ===========================================================================
// M3 MINIMAL SUBSET: SNAPSHOT PINS + SAVEPOINTS (docs/MVCC.md)
// ===========================================================================
// A snapshot pin captures {root, lsn, generation} and makes it stable: while
// pins exist, every write path copy-on-writes the nodes it touches
// (`cow_shadow`), so a pinned root keeps reading the exact state at capture.
// No per-page version chains: old versions stay in the arena reachable only
// from pins. Pins are handle-local; a reopen starts with none.
// Savepoints are txn-scoped rollback markers: restore trims the buffered ops
// and splices the WAL window (Abort + Begin + re-log of the kept ops) so
// replay reconstructs exactly the surviving set after any crash.

fn db_file_pin_index(db: &DBFile, id: Int) -> Int {
  var i = 0;
  while i < db.tree.store.pins.len() {
    if db.tree.store.pins[i].id == id { return i; }
    i = i + 1;
  }
  return -1;
}

// Capture the current committed state as a stable read view (id 0 would mean
// failure; ids are monotone and never reused). Buffered transaction ops are
// NOT visible in the pinned view (read-committed).
pub fn db_file_snapshot_begin(db: &mut DBFile) -> DBSnapshot {
  db.tree.store.pin_clock = db.tree.store.pin_clock + 1;
  var pin = DBSnapshot{ id: db.tree.store.pin_clock, root: db.tree.root,
                        lsn: wal_file_next_lsn(&db.wal) - 1,
                        generation: db.snap_generation };
  db.tree.store.pins.push(pin);
  return pin;
}

// Release a pin (false for an unknown id). Writes may then mutate its
// versions in place again; the arena keeps the old nodes as garbage until the
// M1.1b free list exists.
pub fn db_file_snapshot_end(db: &mut DBFile, id: Int) -> Bool {
  let at = db_file_pin_index(db, id);
  if at < 0 { return false; }
  var i = at;
  while i < db.tree.store.pins.len() - 1 {
    db.tree.store.pins[i] = db.tree.store.pins[i + 1];
    i = i + 1;
  }
  db.tree.store.pins.pop();
  return true;
}

pub fn db_file_snapshot_pins(db: &DBFile) -> Int {
  return db.tree.store.pins.len();
}

// Oldest pinned WAL LSN, or -1 when none. Deferred-free hook for the M1.1b
// pager: once a free list exists, pages are allocatable only below this LSN.
pub fn db_file_min_pinned_lsn(db: &DBFile) -> Int {
  if db.tree.store.pins.len() == 0 { return -1; }
  var best = db.tree.store.pins[0].lsn;
  var i = 1;
  while i < db.tree.store.pins.len() {
    if db.tree.store.pins[i].lsn < best { best = db.tree.store.pins[i].lsn; }
    i = i + 1;
  }
  return best;
}

// Snapshot reads: exactly the state at `db_file_snapshot_begin`. None /
// empty / -1 for an id that is not a live pin.
pub fn db_file_snapshot_get(db: &DBFile, id: Int, key: Int) -> Option[Int] {
  let at = db_file_pin_index(db, id);
  if at < 0 { return None; }
  return search_node(&db.tree, db.tree.store.pins[at].root, key);
}

pub fn db_file_snapshot_get_typed(db: &DBFile, id: Int, key: Int) -> Option[Vec[Int]] {
  let at = db_file_pin_index(db, id);
  if at < 0 { return None; }
  return search_payload_node(&db.tree, db.tree.store.pins[at].root, key);
}

pub fn db_file_snapshot_range(db: &DBFile, id: Int, low: Int, high: Int) -> Vec[Int] {
  var results = Vec[Int].new();
  let at = db_file_pin_index(db, id);
  if at < 0 { return results; }
  if low > high { return results; }
  collect_range(&db.tree, db.tree.store.pins[at].root, low, high, &mut results);
  return results;
}

pub fn db_file_snapshot_count(db: &DBFile, id: Int) -> Int {
  let at = db_file_pin_index(db, id);
  if at < 0 { return -1; }
  return count_keys(&db.tree, db.tree.store.pins[at].root);
}

// Last committed snapshot generation for this handle (0 = none), set on open
// and after every committed checkpoint.
pub fn db_file_snap_generation(db: &DBFile) -> Int {
  return db.snap_generation;
}

// Checkpoints that would have compacted but were deferred because a snapshot
// pin was live.
pub fn db_file_compaction_deferrals(db: &DBFile) -> Int {
  return db.tree.store.compaction_deferred;
}

// --- savepoints (txn-scoped) ----------------------------------------------

pub fn db_file_txn_savepoint_active(db: &DBFile) -> Bool {
  return db.sp_active;
}

// Record a rollback marker at the current buffer length (single level; false
// without an active transaction or when a savepoint is already active).
pub fn db_file_txn_savepoint(db: &mut DBFile) -> Bool {
  if !db.txn_active { return false; }
  if db.sp_active { return false; }
  if !db_file_guard(db) { return false; }
  if db.failed { return false; }
  db.sp_marker = db.txn_ops.len();
  db.sp_active = true;
  return true;
}

// Restore to the savepoint: trim the buffered ops, then splice the WAL window
// so recovery agrees with the buffer -- AbortTxn closes the current window
// (replay discards it), BeginTxn opens a fresh one, and the kept ops are
// re-logged verbatim. The savepoint stays active (SQL ROLLBACK TO SAVEPOINT
// semantics); commit/abort release it.
pub fn db_file_txn_savepoint_restore(db: &mut DBFile) -> Bool {
  if !db.txn_active { return false; }
  if !db.sp_active { return false; }
  if !db_file_guard(db) { return false; }
  if db.failed { return false; }
  while db.txn_ops.len() > db.sp_marker {
    db.txn_ops.pop();
  }
  let fd = db_txn_fd(db);
  if fd < 0 { return false; }
  var lsn = wal_file_append_fd(&mut db.wal, fd, WALOpKind.AbortTxn, 0, 0);
  if lsn < 0 { return false; }
  lsn = wal_file_append_fd(&mut db.wal, fd, WALOpKind.BeginTxn, 0, 0);
  if lsn < 0 { return false; }
  var appended = 2;
  var i = 0;
  while i < db.txn_ops.len() {
    let op = db.txn_ops[i];
    if op.code == 3 {
      lsn = wal_file_append_fd(&mut db.wal, fd, WALOpKind.Delete, op.key, 0);
    } else {
      lsn = wal_file_append_fd(&mut db.wal, fd, WALOpKind.Update, op.key, op.value);
    }
    if lsn < 0 { return false; }
    appended = appended + 1;
    i = i + 1;
  }
  db.wal_bytes = db_wal_size(db.path);
  db.records_since_ckpt = db.records_since_ckpt + appended;
  return true;
}

// Drop the savepoint marker (false without an active transaction/marker).
pub fn db_file_txn_savepoint_release(db: &mut DBFile) -> Bool {
  if !db.txn_active { return false; }
  if !db.sp_active { return false; }
  db.sp_active = false;
  db.sp_marker = 0;
  return true;
}