// XIOM ORBITDB -- ORBITWIRE v1 dispatch: one StationActor owns the DBFile,
// sessions submit typed commands, the actor executes through the public
// engine API.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Single-writer actor (ST1 shape): the event-loop thread owns this actor and
// its DBFile; sessions never share the handle across threads. A transaction
// window is owned by exactly one session (`txn_owner`); other sessions see
// committed state and their writes are refused with TXN_ACTIVE. ST3 will
// move the actor behind a thread boundary without changing this message
// surface.
//
// Compiler note (C-ORBIT-14, v0.64.8): never bind a Vec with
// `let/var x = match ...`; declare + assign instead.
module xiom.station.dispatch

use xiom.db.engine;
use xiom.db.error;
use xiom.station.session;
use xiom.station.protocol;

pub type StationActor = {
  dbs: Vec[DBFile];
  txn_owner: Int;
  path: Str;
  order: Int;
  token: Str;
}

pub const STATION_VERSION: Str = "orbitdb-station/0.1.0";

pub fn actor_new() -> StationActor {
  return StationActor{ dbs: Vec[DBFile].new(), txn_owner: 0, path: "",
                       order: 4, token: "" };
}

pub fn actor_open(a: &mut StationActor, path: Str, order: Int, page_format: Int,
                  token: Str) -> Int {
  a.path = path;
  a.order = order;
  a.token = token;
  match db_file_open_locked_checked_cfg(path, order, page_format) {
    Ok(db) => {
      a.dbs.push(db);
      return CODE_OK;
    }
    Err(e) => {
      return db_error_code(e);
    }
  }
}

pub fn actor_close(a: &mut StationActor) {
  if a.dbs.len() == 0 { return; }
  if a.dbs[0].txn_active {
    let _ = db_file_txn_abort(&mut a.dbs[0]);
  }
  a.txn_owner = 0;
  db_file_close(&mut a.dbs[0]);
  a.dbs = Vec[DBFile].new();
  let _ = db_file_unlock(a.path);
}

pub fn actor_release_session(a: &mut StationActor, sid: Int) -> Bool {
  if a.txn_owner != sid { return false; }
  if a.dbs.len() > 0 {
    let _ = db_file_txn_abort(&mut a.dbs[0]);
  }
  a.txn_owner = 0;
  return true;
}

pub fn actor_ready(a: &StationActor) -> Bool {
  return a.dbs.len() > 0;
}

pub fn actor_last_lsn(a: &StationActor) -> Int {
  if a.dbs.len() == 0 { return 0; }
  return db_file_last_lsn(&a.dbs[0]);
}

pub fn actor_db_size(a: &StationActor) -> Int {
  if a.dbs.len() == 0 { return 0; }
  return db_file_size(&a.dbs[0]);
}

pub fn actor_auth_required(a: &StationActor) -> Bool {
  return a.token.len() > 0;
}

pub fn db_error_code(e: DbError) -> Int {
  match e {
    DbError.NotFound => { return CODE_NOT_FOUND; }
    DbError.DuplicateKey => { return CODE_DUPLICATE_KEY; }
    DbError.ConstraintViolation => { return CODE_CONSTRAINT; }
    DbError.SchemaMismatch => { return CODE_SCHEMA_MISMATCH; }
    DbError.StorageError => { return CODE_STORAGE; }
    DbError.Corruption => { return CODE_CORRUPTION; }
  }
}

fn engine_error(a: &StationActor) -> Int {
  if a.dbs.len() == 0 { return CODE_STORAGE; }
  if a.dbs[0].failed { return CODE_STORAGE; }
  if a.dbs[0].txn_active { return CODE_TXN_ACTIVE; }
  return CODE_STORAGE;
}

fn token_equal_bytes(data: &Vec[Int], token: &Str) -> Bool {
  if data.len() != token.len() { return false; }
  var diff = 0;
  var i = 0;
  while i < data.len() {
    diff = diff | ((data[i] & 0xFF) ^ (token.byte_at(i) & 0xFF));
    i = i + 1;
  }
  return diff == 0;
}

fn query_add_condition(q: &mut Query, op: Int, value: Int) -> Bool {
  if op == 0 { query_where(q, QueryOp.Eq, value); return true; }
  if op == 1 { query_where(q, QueryOp.Neq, value); return true; }
  if op == 2 { query_where(q, QueryOp.Lt, value); return true; }
  if op == 3 { query_where(q, QueryOp.Lte, value); return true; }
  if op == 4 { query_where(q, QueryOp.Gt, value); return true; }
  if op == 5 { query_where(q, QueryOp.Gte, value); return true; }
  return false;
}

fn hello_extra(a: &StationActor, s: &Session) -> Vec[WireField] {
  var fs = Vec[WireField].new();
  fs.push(wire_int(TAG_PROTO_VERSION, PROTO_VERSION));
  fs.push(wire_text(TAG_SERVER_VERSION, STATION_VERSION));
  fs.push(wire_int(TAG_SESSION_ID, s.id));
  fs.push(wire_bool(TAG_AUTH_REQUIRED, actor_auth_required(a)));
  fs.push(wire_int(TAG_CAPABILITIES,
                   CAP_TYPED_ROWS | CAP_TXN | CAP_QUERY | CAP_CHECKPOINT | CAP_AUTH));
  fs.push(wire_int(TAG_MAX_FRAME, MAX_FRAME_BYTES));
  fs.push(wire_int(TAG_MAX_PAYLOAD, MAX_PAYLOAD_BYTES));
  fs.push(wire_int(TAG_MAX_QUEUE, MAX_QUEUE_BYTES));
  fs.push(wire_int(TAG_LAST_LSN, actor_last_lsn(a)));
  fs.push(wire_int(TAG_DB_SIZE, actor_db_size(a)));
  return fs;
}

fn status_extra(a: &StationActor, s: &Session) -> Vec[WireField] {
  var fs = Vec[WireField].new();
  fs.push(wire_bool(TAG_TXN_OPEN, s.state == STATE_TXN));
  fs.push(wire_int(TAG_LAST_LSN, actor_last_lsn(a)));
  return fs;
}

fn require_key(s: &Session) -> Bool {
  return frame_has_int(&s.frame, TAG_KEY);
}

fn dispatch_hello(a: &mut StationActor, s: &mut Session, req_id: Int) -> Vec[Int] {
  let pv = frame_int(&s.frame, TAG_PROTO_VERSION, PROTO_VERSION);
  if pv != PROTO_VERSION {
    return err_frame(req_id, OP_HELLO, CODE_PROTOCOL,
                     "unsupported protocol version");
  }
  if actor_auth_required(a) {
    s.state = STATE_GREETED;
    s.authed = false;
  } else {
    s.state = STATE_READY;
    s.authed = true;
  }
  let extra = hello_extra(a, s);
  return ok_frame(req_id, OP_HELLO, &extra, &Vec[Int].new());
}

fn dispatch_auth(a: &mut StationActor, s: &mut Session, req_id: Int) -> Vec[Int] {
  if !actor_auth_required(a) {
    s.state = STATE_READY;
    s.authed = true;
    let extra = status_extra(a, s);
    return ok_frame(req_id, OP_AUTH, &extra, &Vec[Int].new());
  }
  let method = frame_int(&s.frame, TAG_METHOD, AUTH_TOKEN);
  if method != AUTH_TOKEN {
    return err_frame(req_id, OP_AUTH, CODE_PROTOCOL, "unsupported auth method");
  }
  let tok = frame_bytes(&s.frame, TAG_TOKEN);
  if token_equal_bytes(&tok, &a.token) {
    s.state = STATE_READY;
    s.authed = true;
    s.auth_failures = 0;
    let extra = status_extra(a, s);
    return ok_frame(req_id, OP_AUTH, &extra, &Vec[Int].new());
  }
  s.auth_failures = s.auth_failures + 1;
  if s.auth_failures >= MAX_AUTH_FAILURES {
    s.closing = true;
    return err_frame(req_id, OP_AUTH, CODE_AUTH_LOCKED,
                     "too many failed auth attempts");
  }
  return err_frame(req_id, OP_AUTH, CODE_AUTH_FAILED, "invalid token");
}

fn dispatch_ping(a: &mut StationActor, s: &mut Session, req_id: Int) -> Vec[Int] {
  let nonce = frame_int(&s.frame, TAG_NONCE, 0);
  var fs = Vec[WireField].new();
  fs.push(wire_int(TAG_NONCE, nonce));
  fs.push(wire_bool(TAG_TXN_OPEN, s.state == STATE_TXN));
  fs.push(wire_int(TAG_LAST_LSN, actor_last_lsn(a)));
  return ok_frame(req_id, OP_PING, &fs, &Vec[Int].new());
}

fn dispatch_begin(a: &mut StationActor, s: &mut Session, req_id: Int) -> Vec[Int] {
  if s.state == STATE_TXN {
    return err_frame(req_id, OP_BEGIN, CODE_TXN_ACTIVE,
                     "a transaction is already open on this session");
  }
  if a.txn_owner != 0 {
    return err_frame(req_id, OP_BEGIN, CODE_TXN_ACTIVE,
                     "another session owns the write transaction");
  }
  if !actor_ready(a) {
    return err_frame(req_id, OP_BEGIN, CODE_STORAGE, "database not open");
  }
  if db_file_txn_begin(&mut a.dbs[0]) {
    a.txn_owner = s.id;
    s.state = STATE_TXN;
    s.txn_ops = 0;
    let extra = status_extra(a, s);
    return ok_frame(req_id, OP_BEGIN, &extra, &Vec[Int].new());
  }
  return err_frame(req_id, OP_BEGIN, engine_error(a), "BEGIN failed");
}

fn dispatch_put(a: &mut StationActor, s: &mut Session, req_id: Int) -> Vec[Int] {
  if !require_key(s) {
    return err_frame(req_id, OP_PUT, CODE_PROTOCOL, "missing key");
  }
  let key = frame_int(&s.frame, TAG_KEY, 0);
  let row_kind = frame_int(&s.frame, TAG_ROW_KIND, ROW_INT);
  let value = frame_int(&s.frame, TAG_VALUE, 0);
  if !actor_ready(a) {
    return err_frame(req_id, OP_PUT, CODE_STORAGE, "database not open");
  }
  if s.state == STATE_TXN {
    if a.txn_owner != s.id {
      return err_frame(req_id, OP_PUT, CODE_NO_TXN, "not the transaction owner");
    }
    if row_kind != ROW_INT {
      return err_frame(req_id, OP_PUT, CODE_UNSUPPORTED,
                       "typed rows are auto-commit in ORBITWIRE v1");
    }
    if s.txn_ops >= MAX_TXN_OPS {
      return err_frame(req_id, OP_PUT, CODE_LIMIT, "transaction op limit reached");
    }
    if db_file_txn_put(&mut a.dbs[0], key, value) {
      s.txn_ops = s.txn_ops + 1;
      var fs = Vec[WireField].new();
      fs.push(wire_int(TAG_KEY, key));
      fs.push(wire_int(TAG_LAST_LSN, actor_last_lsn(a)));
      return ok_frame(req_id, OP_PUT, &fs, &Vec[Int].new());
    }
    return err_frame(req_id, OP_PUT, engine_error(a), "transaction PUT failed");
  }
  if a.txn_owner != 0 {
    return err_frame(req_id, OP_PUT, CODE_TXN_ACTIVE,
                     "another session owns the write transaction");
  }
  if row_kind == ROW_TYPED {
    let max = db_file_typed_payload_max(a.order);
    if s.frame.payload.len() > max {
      return err_frame(req_id, OP_PUT, CODE_LIMIT,
                       "typed payload exceeds the row budget");
    }
    var pay = Vec[Int].new();
    var i = 0;
    while i < s.frame.payload.len() {
      let b = s.frame.payload[i] & 0xFF;
      if b != s.frame.payload[i] {
        return err_frame(req_id, OP_PUT, CODE_CONSTRAINT,
                         "typed payload bytes must be 0..255");
      }
      pay.push(b);
      i = i + 1;
    }
    if db_file_put_typed(&mut a.dbs[0], key, pay) {
      var fs = Vec[WireField].new();
      fs.push(wire_int(TAG_KEY, key));
      fs.push(wire_int(TAG_LAST_LSN, actor_last_lsn(a)));
      return ok_frame(req_id, OP_PUT, &fs, &Vec[Int].new());
    }
    return err_frame(req_id, OP_PUT, engine_error(a), "typed PUT failed");
  }
  if db_file_put(&mut a.dbs[0], key, value) {
    var fs = Vec[WireField].new();
    fs.push(wire_int(TAG_KEY, key));
    fs.push(wire_int(TAG_LAST_LSN, actor_last_lsn(a)));
    return ok_frame(req_id, OP_PUT, &fs, &Vec[Int].new());
  }
  return err_frame(req_id, OP_PUT, engine_error(a), "PUT failed");
}

fn dispatch_get(a: &mut StationActor, s: &mut Session, req_id: Int) -> Vec[Int] {
  if !require_key(s) {
    return err_frame(req_id, OP_GET, CODE_PROTOCOL, "missing key");
  }
  let key = frame_int(&s.frame, TAG_KEY, 0);
  if !actor_ready(a) {
    return err_frame(req_id, OP_GET, CODE_STORAGE, "database not open");
  }
  var typed = Vec[Int].new();
  var has_typed = false;
  match db_file_get_typed(&a.dbs[0], key) {
    None => {}
    Some(p) => {
      typed = p;
      has_typed = true;
    }
  }
  if has_typed {
    var fs = Vec[WireField].new();
    fs.push(wire_int(TAG_ROW_KIND, ROW_TYPED));
    fs.push(wire_int(TAG_KEY, key));
    return ok_frame(req_id, OP_GET, &fs, &typed);
  }
  var found = false;
  var value = 0;
  match db_file_get(&a.dbs[0], key) {
    None => {}
    Some(v) => {
      value = v;
      found = true;
    }
  }
  if !found {
    return err_frame(req_id, OP_GET, CODE_NOT_FOUND, "key not found");
  }
  var fs = Vec[WireField].new();
  fs.push(wire_int(TAG_ROW_KIND, ROW_INT));
  fs.push(wire_int(TAG_KEY, key));
  fs.push(wire_int(TAG_VALUE, value));
  return ok_frame(req_id, OP_GET, &fs, &Vec[Int].new());
}

fn dispatch_delete(a: &mut StationActor, s: &mut Session, req_id: Int) -> Vec[Int] {
  if !require_key(s) {
    return err_frame(req_id, OP_DELETE, CODE_PROTOCOL, "missing key");
  }
  let key = frame_int(&s.frame, TAG_KEY, 0);
  if !actor_ready(a) {
    return err_frame(req_id, OP_DELETE, CODE_STORAGE, "database not open");
  }
  if s.state == STATE_TXN {
    if a.txn_owner != s.id {
      return err_frame(req_id, OP_DELETE, CODE_NO_TXN,
                       "not the transaction owner");
    }
    if s.txn_ops >= MAX_TXN_OPS {
      return err_frame(req_id, OP_DELETE, CODE_LIMIT,
                       "transaction op limit reached");
    }
    if db_file_txn_delete(&mut a.dbs[0], key) {
      s.txn_ops = s.txn_ops + 1;
      let extra = status_extra(a, s);
      return ok_frame(req_id, OP_DELETE, &extra, &Vec[Int].new());
    }
    return err_frame(req_id, OP_DELETE, engine_error(a), "transaction DELETE failed");
  }
  if a.txn_owner != 0 {
    return err_frame(req_id, OP_DELETE, CODE_TXN_ACTIVE,
                     "another session owns the write transaction");
  }
  if db_file_delete(&mut a.dbs[0], key) {
    var fs = Vec[WireField].new();
    fs.push(wire_int(TAG_KEY, key));
    fs.push(wire_int(TAG_LAST_LSN, actor_last_lsn(a)));
    return ok_frame(req_id, OP_DELETE, &fs, &Vec[Int].new());
  }
  if a.dbs[0].failed {
    return err_frame(req_id, OP_DELETE, CODE_STORAGE, "handle is latched");
  }
  var absent = false;
  match db_file_get(&a.dbs[0], key) {
    None => { absent = true; }
    Some(_) => {}
  }
  if absent {
    return err_frame(req_id, OP_DELETE, CODE_NOT_FOUND, "key not found");
  }
  return err_frame(req_id, OP_DELETE, engine_error(a), "DELETE failed");
}

fn dispatch_range(a: &mut StationActor, s: &mut Session, req_id: Int) -> Vec[Int] {
  if !frame_has_int(&s.frame, TAG_LOW) || !frame_has_int(&s.frame, TAG_HIGH) {
    return err_frame(req_id, OP_RANGE, CODE_PROTOCOL, "missing low/high");
  }
  let low = frame_int(&s.frame, TAG_LOW, 0);
  let high = frame_int(&s.frame, TAG_HIGH, 0);
  if low > high {
    return err_frame(req_id, OP_RANGE, CODE_CONSTRAINT, "low must be <= high");
  }
  var limit = frame_int(&s.frame, TAG_LIMIT, DEFAULT_RANGE_ROWS);
  if limit <= 0 { limit = DEFAULT_RANGE_ROWS; }
  if limit > MAX_RANGE_ROWS {
    return err_frame(req_id, OP_RANGE, CODE_LIMIT,
                     "range limit exceeds the wire maximum");
  }
  if high - low > 10000 {
    return err_frame(req_id, OP_RANGE, CODE_LIMIT,
                     "range span exceeds 10000 keys; narrow it");
  }
  if !actor_ready(a) {
    return err_frame(req_id, OP_RANGE, CODE_STORAGE, "database not open");
  }
  let pairs = db_file_range_pairs(&a.dbs[0], low, high);
  var rows = Vec[WireRow].new();
  var i = 0;
  while i < pairs.len() && rows.len() < limit {
    var pk = 0;
    var pv = 0;
    match pairs[i] {
      (k, v) => {
        pk = k;
        pv = v;
      }
    }
    var typed = Vec[Int].new();
    var has_typed = false;
    match db_file_get_typed(&a.dbs[0], pk) {
      None => {}
      Some(p) => {
        typed = p;
        has_typed = true;
      }
    }
    if has_typed {
      rows.push(WireRow{ kind: ROW_TYPED, key: pk, value: pk, data: typed });
    } else {
      rows.push(WireRow{ kind: ROW_INT, key: pk, value: pv,
                         data: Vec[Int].new() });
    }
    i = i + 1;
  }
  let truncated = pairs.len() > rows.len();
  var payload = Vec[Int].new();
  var enc_code = CODE_OK;
  match rows_encode(&rows) {
    Ok(b) => { payload = b; }
    Err(e) => { enc_code = e; }
  }
  if enc_code != CODE_OK {
    return err_frame(req_id, OP_RANGE, enc_code, "range result encode failed");
  }
  var fs = Vec[WireField].new();
  fs.push(wire_int(TAG_ROW_COUNT, rows.len()));
  fs.push(wire_bool(TAG_TRUNCATED, truncated));
  return ok_frame(req_id, OP_RANGE, &fs, &payload);
}

fn dispatch_query(a: &mut StationActor, s: &mut Session, req_id: Int) -> Vec[Int] {
  if !actor_ready(a) {
    return err_frame(req_id, OP_QUERY, CODE_STORAGE, "database not open");
  }
  var q = query_new();
  let conds = wire_get_all_bytes(&s.frame.fields, TAG_CONDITION);
  var ci = 0;
  while ci < conds.len() {
    var bad = false;
    var op = 0;
    var val = 0;
    match condition_decode(&conds[ci]) {
      None => { bad = true; }
      Some(c) => {
        match c {
          (o, v) => {
            op = o;
            val = v;
          }
        }
      }
    }
    if bad {
      return err_frame(req_id, OP_QUERY, CODE_PROTOCOL, "invalid condition");
    }
    if !query_add_condition(&mut q, op, val) {
      return err_frame(req_id, OP_QUERY, CODE_PROTOCOL, "unknown condition op");
    }
    ci = ci + 1;
  }
  if frame_bool(&s.frame, TAG_HAS_BOUNDS, false) {
    if !frame_has_int(&s.frame, TAG_LOW) || !frame_has_int(&s.frame, TAG_HIGH) {
      return err_frame(req_id, OP_QUERY, CODE_PROTOCOL,
                       "bounds require low/high");
    }
    let low = frame_int(&s.frame, TAG_LOW, 0);
    let high = frame_int(&s.frame, TAG_HIGH, 0);
    if low > high {
      return err_frame(req_id, OP_QUERY, CODE_CONSTRAINT,
                       "low must be <= high");
    }
    query_key_range(&mut q, low, high);
  }
  let order = frame_int(&s.frame, TAG_ORDER, 0);
  if order < 0 || order > 2 {
    return err_frame(req_id, OP_QUERY, CODE_CONSTRAINT, "order must be 0..2");
  }
  q.order = order;
  let limit = frame_int(&s.frame, TAG_LIMIT, 0);
  if limit < 0 {
    return err_frame(req_id, OP_QUERY, CODE_CONSTRAINT, "limit must be >= 0");
  }
  if limit > 0 { query_limit(&mut q, limit); }
  let offset = frame_int(&s.frame, TAG_OFFSET, 0);
  if offset < 0 {
    return err_frame(req_id, OP_QUERY, CODE_CONSTRAINT, "offset must be >= 0");
  }
  if offset > 0 { query_offset(&mut q, offset); }
  let results = db_file_query(&a.dbs[0], &q);
  if results.len() > MAX_QUERY_ROWS {
    return err_frame(req_id, OP_QUERY, CODE_LIMIT,
                     "query result exceeds the wire maximum");
  }
  var payload = Vec[Int].new();
  var enc_code = CODE_OK;
  match values_encode(&results) {
    Ok(b) => { payload = b; }
    Err(e) => { enc_code = e; }
  }
  if enc_code != CODE_OK {
    return err_frame(req_id, OP_QUERY, enc_code, "query result encode failed");
  }
  var fs = Vec[WireField].new();
  fs.push(wire_int(TAG_ROW_COUNT, results.len()));
  return ok_frame(req_id, OP_QUERY, &fs, &payload);
}

fn dispatch_commit(a: &mut StationActor, s: &mut Session, req_id: Int) -> Vec[Int] {
  if s.state != STATE_TXN || a.txn_owner != s.id {
    return err_frame(req_id, OP_COMMIT, CODE_NO_TXN,
                     "no transaction owned by this session");
  }
  if db_file_txn_commit(&mut a.dbs[0]) {
    a.txn_owner = 0;
    s.state = STATE_READY;
    s.txn_ops = 0;
    let extra = status_extra(a, s);
    return ok_frame(req_id, OP_COMMIT, &extra, &Vec[Int].new());
  }
  return err_frame(req_id, OP_COMMIT, engine_error(a), "COMMIT failed");
}

fn dispatch_abort(a: &mut StationActor, s: &mut Session, req_id: Int) -> Vec[Int] {
  if s.state != STATE_TXN || a.txn_owner != s.id {
    return err_frame(req_id, OP_ABORT, CODE_NO_TXN,
                     "no transaction owned by this session");
  }
  if db_file_txn_abort(&mut a.dbs[0]) {
    a.txn_owner = 0;
    s.state = STATE_READY;
    s.txn_ops = 0;
    let extra = status_extra(a, s);
    return ok_frame(req_id, OP_ABORT, &extra, &Vec[Int].new());
  }
  return err_frame(req_id, OP_ABORT, engine_error(a), "ABORT failed");
}

fn dispatch_close(a: &mut StationActor, s: &mut Session, req_id: Int) -> Vec[Int] {
  if s.state == STATE_TXN && a.txn_owner == s.id {
    let _ = db_file_txn_abort(&mut a.dbs[0]);
    a.txn_owner = 0;
    s.txn_ops = 0;
  }
  s.state = STATE_CLOSING;
  s.closing = true;
  var fs = Vec[WireField].new();
  fs.push(wire_bool(TAG_TXN_OPEN, false));
  return ok_frame(req_id, OP_CLOSE, &fs, &Vec[Int].new());
}

fn dispatch_checkpoint(a: &mut StationActor, s: &mut Session, req_id: Int) -> Vec[Int] {
  if s.state == STATE_TXN || a.txn_owner != 0 {
    return err_frame(req_id, OP_CHECKPOINT, CODE_TXN_ACTIVE,
                     "checkpoint is refused while a transaction is open");
  }
  if !actor_ready(a) {
    return err_frame(req_id, OP_CHECKPOINT, CODE_STORAGE, "database not open");
  }
  let anchor = db_file_checkpoint(&mut a.dbs[0]);
  if anchor < 0 {
    return err_frame(req_id, OP_CHECKPOINT, CODE_STORAGE, "checkpoint failed");
  }
  var fs = Vec[WireField].new();
  fs.push(wire_int(TAG_LAST_LSN, anchor));
  return ok_frame(req_id, OP_CHECKPOINT, &fs, &Vec[Int].new());
}

// The single dispatch entry point. Returns a fully encoded RESPONSE frame.
pub fn dispatch(a: &mut StationActor, s: &mut Session) -> Vec[Int] {
  let req_id = frame_int(&s.frame, TAG_REQUEST_ID, 0);
  let op = frame_int(&s.frame, TAG_OP, 0);
  if s.frame.kind != KIND_REQUEST {
    return err_frame(req_id, op, CODE_PROTOCOL, "expected a REQUEST frame");
  }
  if s.state == STATE_CLOSED || s.state == STATE_CLOSING {
    return err_frame(req_id, op, CODE_CLOSED, "session is closing");
  }
  if s.state == STATE_NEW {
    if op != OP_HELLO {
      return err_frame(req_id, op, CODE_PROTOCOL, "HELLO required");
    }
    return dispatch_hello(a, s, req_id);
  }
  if s.state == STATE_GREETED {
    if op == OP_AUTH { return dispatch_auth(a, s, req_id); }
    if op == OP_CLOSE { return dispatch_close(a, s, req_id); }
    return err_frame(req_id, op, CODE_AUTH_REQUIRED, "AUTH required");
  }
  // READY or TXN.
  if op == OP_HELLO {
    return err_frame(req_id, op, CODE_PROTOCOL, "HELLO already completed");
  }
  if op == OP_AUTH {
    return err_frame(req_id, op, CODE_PROTOCOL, "already authenticated");
  }
  if op == OP_PING { return dispatch_ping(a, s, req_id); }
  if op == OP_BEGIN { return dispatch_begin(a, s, req_id); }
  if op == OP_PUT { return dispatch_put(a, s, req_id); }
  if op == OP_GET { return dispatch_get(a, s, req_id); }
  if op == OP_DELETE { return dispatch_delete(a, s, req_id); }
  if op == OP_RANGE { return dispatch_range(a, s, req_id); }
  if op == OP_QUERY { return dispatch_query(a, s, req_id); }
  if op == OP_COMMIT { return dispatch_commit(a, s, req_id); }
  if op == OP_ABORT { return dispatch_abort(a, s, req_id); }
  if op == OP_CLOSE { return dispatch_close(a, s, req_id); }
  if op == OP_CHECKPOINT { return dispatch_checkpoint(a, s, req_id); }
  return err_frame(req_id, op, CODE_UNSUPPORTED, "unsupported op");
}
