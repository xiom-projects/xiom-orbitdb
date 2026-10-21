// XIOM ORBITDB Station -- ORBITWIRE v1 loopback conformance suite.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// End-to-end loopback checks over the chosen transport (raw TCP on
// 127.0.0.1): HELLO/AUTH, PING, PUT/GET/RANGE/QUERY, BEGIN/COMMIT/ABORT,
// typed rows (all TValue kinds), payload limits, multi-session isolation,
// framing errors and CLOSE. The server and client share one thread: the test
// drives `server_step` explicitly, so the DBFile never leaves the actor.
//
// Summary line (consumed by scripts/station_suite.*):
//   XIOM Station Conformance [loopback]: P/T passed
module orbitdb_station_loopback_suite

use xiom.io;
use xiom.net.socket;
use xiom.db.engine;
use xiom.db.storage.tuple;
use xiom.station.protocol;
use xiom.station.session;
use xiom.station.server;

var g_pass: Int = 0;
var g_total: Int = 0;

fn check(ok: Bool, name: Str) {
  g_total = g_total + 1;
  if ok {
    g_pass = g_pass + 1;
    io.println("  [PASS] " + name);
  } else {
    io.println("  [FAIL] " + name);
  }
}

pub type LoopClient = {
  fd: Int;
  rx: Vec[Int];
  frame: WireFrame;
  code: Int;
  next_id: Int;
}

fn client_new(port: Int) -> LoopClient {
  var c = LoopClient{ fd: -1, rx: Vec[Int].new(), frame: session.empty_frame(),
                      code: 0, next_id: 0 };
  match socket_tcp() {
    Ok(fd) => { c.fd = fd; }
    Err(_) => {}
  }
  if c.fd < 0 { return c; }
  match socket_connect(c.fd, "127.0.0.1", port) {
    Ok(_) => {}
    Err(_) => {
      socket_close(c.fd);
      c.fd = -1;
      return c;
    }
  }
  let _ = socket_set_timeout(c.fd, 100);
  let _ = socket_set_nodelay(c.fd, true);
  return c;
}

fn client_send_frame(c: &mut LoopClient, frame: &Vec[Int]) -> Bool {
  if c.fd < 0 { return false; }
  var bytes = Vec[UInt8].new();
  var i = 0;
  while i < frame.len() {
    bytes.push((frame[i] & 0xFF) as UInt8);
    i = i + 1;
  }
  match socket_send_all(c.fd, &bytes) {
    Ok(_) => { return true; }
    Err(_) => { return false; }
  }
}

fn client_send_raw(c: &mut LoopClient, bytes: &Vec[Int]) -> Bool {
  if c.fd < 0 { return false; }
  var b = Vec[UInt8].new();
  var i = 0;
  while i < bytes.len() {
    b.push((bytes[i] & 0xFF) as UInt8);
    i = i + 1;
  }
  match socket_send_all(c.fd, &b) {
    Ok(_) => { return true; }
    Err(_) => { return false; }
  }
}

// 1 = frame ready, 0 = need more (timeout), -1 = EOF/protocol failure.
fn client_pull(c: &mut LoopClient) -> Int {
  var guard = 0;
  while guard < 8 {
    if c.rx.len() > 0 {
      let total = frame_peek_total(&c.rx, 0);
      if total > 0 {
        var f = session.empty_frame();
        match frame_decode(&c.rx, 0, total) {
          Ok(x) => { f = x; }
          Err(e) => {
            c.code = e;
            return -1;
          }
        }
        c.frame = f;
        var rest = Vec[Int].new();
        var i = total;
        while i < c.rx.len() {
          rest.push(c.rx[i]);
          i = i + 1;
        }
        c.rx = rest;
        return 1;
      }
      if total < 0 {
        c.code = CODE_PROTOCOL;
        return -1;
      }
    }
    var bytes = Vec[UInt8].new();
    var failed = false;
    match socket_recv(c.fd, 65536) {
      Ok(b) => { bytes = b; }
      Err(_) => { failed = true; }
    }
    if failed { return 0; }
    if bytes.len() == 0 { return -1; }
    var i = 0;
    while i < bytes.len() {
      c.rx.push((bytes[i] as Int) & 0xFF);
      i = i + 1;
    }
    guard = guard + 1;
  }
  return 0;
}

fn client_close(c: &mut LoopClient) {
  if c.fd >= 0 {
    socket_close(c.fd);
    c.fd = -1;
  }
  c.rx = Vec[Int].new();
}

fn req_frame(c: &mut LoopClient, op: Int, fields: &Vec[WireField],
             payload: &Vec[Int]) -> Vec[Int] {
  c.next_id = c.next_id + 1;
  var fs = Vec[WireField].new();
  fs.push(wire_int(TAG_REQUEST_ID, c.next_id));
  fs.push(wire_int(TAG_OP, op));
  var i = 0;
  while i < fields.len() {
    fs.push(fields[i]);
    i = i + 1;
  }
  var out = Vec[Int].new();
  match frame_encode(KIND_REQUEST, &fs, payload) {
    Ok(b) => { out = b; }
    Err(_) => {}
  }
  return out;
}

fn pump(srv: &mut StationServer, c: &mut LoopClient,
        frame: &Vec[Int]) -> Bool {
  if !client_send_frame(c, frame) { return false; }
  var guard = 0;
  while guard < 200 {
    let _ = server_step(srv, 10);
    let st = client_pull(c);
    if st == 1 { return true; }
    if st < 0 { return false; }
    guard = guard + 1;
  }
  return false;
}

fn resp_status(f: &WireFrame) -> Int {
  return session.frame_int(f, TAG_STATUS, -1);
}

fn resp_code(f: &WireFrame) -> Int {
  return session.frame_int(f, TAG_CODE, -1);
}

fn resp_int(f: &WireFrame, tag: Int) -> Int {
  return session.frame_int(f, tag, -999999999);
}

fn is_ok(f: &WireFrame, op: Int) -> Bool {
  return resp_status(f) == STATUS_OK && resp_int(f, TAG_OP) == op;
}

fn is_err(f: &WireFrame, op: Int, code: Int) -> Bool {
  return resp_status(f) == STATUS_ERROR && resp_int(f, TAG_OP) == op &&
         resp_code(f) == code;
}

fn decode_rows(payload: &Vec[Int]) -> Vec[WireRow] {
  var out = Vec[WireRow].new();
  match rows_decode(payload) {
    Ok(r) => { out = r; }
    Err(_) => {}
  }
  return out;
}

fn decode_values(payload: &Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  match values_decode(payload) {
    Ok(v) => { out = v; }
    Err(_) => {}
  }
  return out;
}

fn cleanup(path: Str) {
  let _ = io.remove_file(path);
  let _ = io.remove_file(path + ".snap");
  let _ = io.remove_file(path + ".lock");
}

// ---------------------------------------------------------------------------
// Request helpers
// ---------------------------------------------------------------------------

fn do_hello(srv: &mut StationServer, c: &mut LoopClient) -> Bool {
  var fs = Vec[WireField].new();
  fs.push(wire_int(TAG_PROTO_VERSION, PROTO_VERSION));
  var f = req_frame(c, OP_HELLO, &fs, &Vec[Int].new());
  return pump(srv, c, &f);
}

fn do_put(srv: &mut StationServer, c: &mut LoopClient, key: Int,
          value: Int) -> Bool {
  var fs = Vec[WireField].new();
  fs.push(wire_int(TAG_KEY, key));
  fs.push(wire_int(TAG_ROW_KIND, ROW_INT));
  fs.push(wire_int(TAG_VALUE, value));
  var f = req_frame(c, OP_PUT, &fs, &Vec[Int].new());
  return pump(srv, c, &f);
}

fn do_put_typed(srv: &mut StationServer, c: &mut LoopClient, key: Int,
                row: &Vec[Int]) -> Bool {
  var fs = Vec[WireField].new();
  fs.push(wire_int(TAG_KEY, key));
  fs.push(wire_int(TAG_ROW_KIND, ROW_TYPED));
  var f = req_frame(c, OP_PUT, &fs, row);
  return pump(srv, c, &f);
}

fn do_get(srv: &mut StationServer, c: &mut LoopClient, key: Int) -> Bool {
  var fs = Vec[WireField].new();
  fs.push(wire_int(TAG_KEY, key));
  var f = req_frame(c, OP_GET, &fs, &Vec[Int].new());
  return pump(srv, c, &f);
}

fn do_delete(srv: &mut StationServer, c: &mut LoopClient, key: Int) -> Bool {
  var fs = Vec[WireField].new();
  fs.push(wire_int(TAG_KEY, key));
  var f = req_frame(c, OP_DELETE, &fs, &Vec[Int].new());
  return pump(srv, c, &f);
}

fn do_range(srv: &mut StationServer, c: &mut LoopClient, low: Int, high: Int,
            limit: Int) -> Bool {
  var fs = Vec[WireField].new();
  fs.push(wire_int(TAG_LOW, low));
  fs.push(wire_int(TAG_HIGH, high));
  fs.push(wire_int(TAG_LIMIT, limit));
  var f = req_frame(c, OP_RANGE, &fs, &Vec[Int].new());
  return pump(srv, c, &f);
}

fn do_query(srv: &mut StationServer, c: &mut LoopClient,
            conds: &Vec[(Int, Int)], has_bounds: Bool, low: Int, high: Int,
            order: Int, limit: Int, offset: Int) -> Bool {
  var fs = Vec[WireField].new();
  var i = 0;
  while i < conds.len() {
    var op = 0;
    var val = 0;
    match conds[i] {
      (o, v) => {
        op = o;
        val = v;
      }
    }
    var d = condition_encode(op, val);
    fs.push(wire_bytes(TAG_CONDITION, &d));
    i = i + 1;
  }
  if has_bounds {
    fs.push(wire_bool(TAG_HAS_BOUNDS, true));
    fs.push(wire_int(TAG_LOW, low));
    fs.push(wire_int(TAG_HIGH, high));
  }
  fs.push(wire_int(TAG_ORDER, order));
  fs.push(wire_int(TAG_LIMIT, limit));
  fs.push(wire_int(TAG_OFFSET, offset));
  var f = req_frame(c, OP_QUERY, &fs, &Vec[Int].new());
  return pump(srv, c, &f);
}

// ---------------------------------------------------------------------------
// Test groups
// ---------------------------------------------------------------------------

fn test_crud(srv: &mut StationServer, c: &mut LoopClient) {
  check(do_put(srv, c, 1, 101), "PUT 1 roundtrip");
  check(is_ok(&c.frame, OP_PUT), "PUT 1 status OK");
  check(do_get(srv, c, 1), "GET 1 roundtrip");
  check(is_ok(&c.frame, OP_GET) && resp_int(&c.frame, TAG_ROW_KIND) == ROW_INT &&
        resp_int(&c.frame, TAG_VALUE) == 101, "GET 1 int row");
  check(do_get(srv, c, 999), "GET missing roundtrip");
  check(is_err(&c.frame, OP_GET, CODE_NOT_FOUND), "GET missing -> NOT_FOUND");
  check(do_delete(srv, c, 999), "DELETE missing roundtrip");
  check(is_err(&c.frame, OP_DELETE, CODE_NOT_FOUND),
        "DELETE missing -> NOT_FOUND");
  check(do_put(srv, c, 2, 102), "PUT 2 roundtrip");
  check(do_put(srv, c, 3, 103), "PUT 3 roundtrip");
  check(do_put(srv, c, 4, 104), "PUT 4 roundtrip");
  check(do_put(srv, c, 5, 105), "PUT 5 roundtrip");
  check(do_delete(srv, c, 4), "DELETE 4 roundtrip");
  check(is_ok(&c.frame, OP_DELETE), "DELETE 4 status OK");
  check(do_get(srv, c, 4), "GET 4 after delete roundtrip");
  check(is_err(&c.frame, OP_GET, CODE_NOT_FOUND), "deleted key absent");
}

fn test_range(srv: &mut StationServer, c: &mut LoopClient) {
  check(do_range(srv, c, 1, 5, 2), "RANGE 1..5 limit 2 roundtrip");
  var rows = decode_rows(&c.frame.payload);
  check(is_ok(&c.frame, OP_RANGE) && rows.len() == 2, "RANGE limit 2 rows");
  check(rows.len() == 2 && rows[0].key == 1 && rows[0].value == 101 &&
        rows[1].key == 2 && rows[1].value == 102, "RANGE key order and values");
  check(session.frame_bool(&c.frame, TAG_TRUNCATED, false), "RANGE truncated flag");
  check(do_range(srv, c, 1, 3, 10), "RANGE 1..3 roundtrip");
  var rows3 = decode_rows(&c.frame.payload);
  check(rows3.len() == 3 && rows3[2].key == 3 && !session.frame_bool(&c.frame, TAG_TRUNCATED, true),
        "RANGE full window not truncated");
  check(do_range(srv, c, 9, 5, 10), "RANGE invalid bounds roundtrip");
  check(is_err(&c.frame, OP_RANGE, CODE_CONSTRAINT), "RANGE low>high rejected");
}

fn test_query(srv: &mut StationServer, c: &mut LoopClient) {
  var conds = Vec[(Int, Int)].new();
  conds.push((5, 101)); // Gte 101
  check(do_query(srv, c, &conds, true, 1, 5, 2, 2, 0), "QUERY desc limit roundtrip");
  var vals = decode_values(&c.frame.payload);
  check(is_ok(&c.frame, OP_QUERY), "QUERY status OK");
  check(vals.len() == 2 && vals[0] == 105 && vals[1] == 103,
        "QUERY ORDER desc + LIMIT");
  check(do_query(srv, c, &conds, true, 1, 5, 1, 2, 2), "QUERY offset roundtrip");
  var vals2 = decode_values(&c.frame.payload);
  check(vals2.len() == 2 && vals2[0] == 103 && vals2[1] == 105,
        "QUERY ORDER asc + OFFSET");
  var conds2 = Vec[(Int, Int)].new();
  conds2.push((0, 102)); // Eq 102
  check(do_query(srv, c, &conds2, true, 1, 5, 0, 0, 0), "QUERY eq roundtrip");
  var vals3 = decode_values(&c.frame.payload);
  check(vals3.len() == 1 && vals3[0] == 102, "QUERY Eq condition");
}

fn test_txn(srv: &mut StationServer, c: &mut LoopClient) {
  var begin = req_frame(c, OP_BEGIN, &Vec[WireField].new(), &Vec[Int].new());
  check(pump(srv, c, &begin), "BEGIN roundtrip");
  check(is_ok(&c.frame, OP_BEGIN) && session.frame_bool(&c.frame, TAG_TXN_OPEN, false),
        "BEGIN opens txn");
  check(do_put(srv, c, 10, 1000), "txn PUT roundtrip");
  check(is_ok(&c.frame, OP_PUT), "txn PUT status OK");
  check(do_get(srv, c, 10), "txn GET roundtrip");
  check(is_err(&c.frame, OP_GET, CODE_NOT_FOUND), "txn write invisible before commit");
  var commit = req_frame(c, OP_COMMIT, &Vec[WireField].new(), &Vec[Int].new());
  check(pump(srv, c, &commit), "COMMIT roundtrip");
  check(is_ok(&c.frame, OP_COMMIT) && !session.frame_bool(&c.frame, TAG_TXN_OPEN, true),
        "COMMIT closes txn");
  check(do_get(srv, c, 10), "GET after commit roundtrip");
  check(is_ok(&c.frame, OP_GET) && resp_int(&c.frame, TAG_VALUE) == 1000,
        "committed row visible");

  var begin2 = req_frame(c, OP_BEGIN, &Vec[WireField].new(), &Vec[Int].new());
  check(pump(srv, c, &begin2), "BEGIN 2 roundtrip");
  check(do_put(srv, c, 11, 1100), "txn2 PUT roundtrip");
  var abort = req_frame(c, OP_ABORT, &Vec[WireField].new(), &Vec[Int].new());
  check(pump(srv, c, &abort), "ABORT roundtrip");
  check(is_ok(&c.frame, OP_ABORT), "ABORT status OK");
  check(do_get(srv, c, 11), "GET after abort roundtrip");
  check(is_err(&c.frame, OP_GET, CODE_NOT_FOUND), "aborted row absent");

  var commit2 = req_frame(c, OP_COMMIT, &Vec[WireField].new(), &Vec[Int].new());
  check(pump(srv, c, &commit2), "COMMIT without txn roundtrip");
  check(is_err(&c.frame, OP_COMMIT, CODE_NO_TXN), "COMMIT without txn rejected");
}

fn test_typed(srv: &mut StationServer, c: &mut LoopClient) {
  var vals = Vec[TValue].new();
  vals.push(TValue.VNull);
  vals.push(TValue.VInt(-7));
  vals.push(TValue.VFloat(1.5));
  vals.push(TValue.VText("hello typed"));
  var blob = Vec[Int].new();
  blob.push(0);
  blob.push(255);
  blob.push(42);
  vals.push(TValue.VBlob(blob));
  var row = Vec[Int].new();
  match tuple2_encode_row_checked(42, &vals) {
    Ok(b) => { row = b; }
    Err(_) => {}
  }
  check(row.len() > 0, "typed row encoded (all TValue kinds)");
  check(do_put_typed(srv, c, 42, &row), "PUT typed roundtrip");
  check(is_ok(&c.frame, OP_PUT), "PUT typed status OK");
  check(do_get(srv, c, 42), "GET typed roundtrip");
  check(is_ok(&c.frame, OP_GET) && resp_int(&c.frame, TAG_ROW_KIND) == ROW_TYPED,
        "GET typed row kind");
  var got = c.frame.payload;
  check(got.len() == row.len(), "typed payload length");
  var same = got.len() == row.len();
  var i = 0;
  while i < got.len() && same {
    if got[i] != row[i] { same = false; }
    i = i + 1;
  }
  check(same, "typed payload byte-exact");
  var decoded_ok = false;
  match tuple2_decode_row(&got) {
    Ok(r) => { decoded_ok = r.values.len() == 5; }
    Err(_) => {}
  }
  check(decoded_ok, "typed payload decodes to 5 values");

  // RANGE must expose the typed row as a typed row, not as its mirrored int.
  check(do_range(srv, c, 40, 45, 10), "RANGE typed window roundtrip");
  var rows = decode_rows(&c.frame.payload);
  check(rows.len() == 1 && rows[0].kind == ROW_TYPED && rows[0].key == 42,
        "RANGE includes typed row kind");

  // Payload budget: one byte over the order-4 row limit is refused.
  let max = db_file_typed_payload_max(4);
  var too_big = Vec[Int].new();
  var j = 0;
  while j <= max {
    too_big.push(7);
    j = j + 1;
  }
  check(do_put_typed(srv, c, 43, &too_big), "PUT oversized typed roundtrip");
  check(is_err(&c.frame, OP_PUT, CODE_LIMIT), "oversized typed -> LIMIT");
}

fn test_multi_session(srv: &mut StationServer, c: &mut LoopClient) {
  var b = client_new(srv.port);
  check(b.fd >= 0, "second client connects");
  check(do_hello(srv, &mut b), "second client HELLO");

  var begin = req_frame(c, OP_BEGIN, &Vec[WireField].new(), &Vec[Int].new());
  check(pump(srv, c, &begin), "session A BEGIN");
  check(is_ok(&c.frame, OP_BEGIN), "session A owns txn");
  check(do_put(srv, c, 20, 2000), "session A txn PUT");
  check(is_ok(&c.frame, OP_PUT), "session A txn PUT OK");

  check(do_get(srv, &mut b, 20), "session B GET uncommitted");
  check(is_err(&b.frame, OP_GET, CODE_NOT_FOUND),
        "session B cannot see uncommitted write");

  var b_begin = req_frame(&mut b, OP_BEGIN, &Vec[WireField].new(), &Vec[Int].new());
  check(pump(srv, &mut b, &b_begin), "session B BEGIN roundtrip");
  check(is_err(&b.frame, OP_BEGIN, CODE_TXN_ACTIVE),
        "second BEGIN refused while txn active");

  check(do_put(srv, &mut b, 21, 2100), "session B auto-commit during txn");
  check(is_err(&b.frame, OP_PUT, CODE_TXN_ACTIVE),
        "auto-commit refused while another txn is open");

  var commit = req_frame(c, OP_COMMIT, &Vec[WireField].new(), &Vec[Int].new());
  check(pump(srv, c, &commit), "session A COMMIT");
  check(is_ok(&c.frame, OP_COMMIT), "session A commit OK");
  check(do_get(srv, &mut b, 20), "session B GET after commit");
  check(is_ok(&b.frame, OP_GET) && resp_int(&b.frame, TAG_VALUE) == 2000,
        "session B sees committed value");

  client_close(&mut b);
}

fn test_framing(srv: &mut StationServer) {
  var c = client_new(srv.port);
  check(c.fd >= 0, "framing client connects");
  // A 16-byte prefix with hlen = 65537 exceeds MAX_HEADER_BYTES.
  var bad = Vec[Int].new();
  bad.push(0x4F);
  bad.push(0x42);
  bad.push(0x57);
  bad.push(0x31);
  bad.push(1);
  bad.push(KIND_REQUEST);
  bad.push(0);
  bad.push(0);
  bad.push(1);
  bad.push(0);
  bad.push(1);
  bad.push(0);
  bad.push(0);
  bad.push(0);
  bad.push(0);
  bad.push(0);
  check(client_send_raw(&mut c, &bad), "framing client sends bad prefix");
  var got = false;
  var guard = 0;
  while guard < 100 {
    let _ = server_step(srv, 10);
    let st = client_pull(&mut c);
    if st == 1 {
      got = true;
      break;
    }
    if st < 0 { break; }
    guard = guard + 1;
  }
  check(got && is_err(&c.frame, 0, CODE_LIMIT),
        "oversized frame -> LIMIT error then close");
  client_close(&mut c);
}

fn test_auth() {
  let _ = io.create_dir_all("out");
  let auth_db = "out/station-auth.wal";
  cleanup(auth_db);
  var srv = server_new();
  let init_code = server_init(&mut srv, auth_db, 4, 2, "s3cret",
                              "127.0.0.1", 17967);
  check(init_code == CODE_OK, "auth server: open + listen");
  if init_code != CODE_OK { return; }

  var c = client_new(srv.port);
  check(c.fd >= 0, "auth client connects");
  check(do_hello(&mut srv, &mut c), "auth HELLO roundtrip");
  check(is_ok(&c.frame, OP_HELLO) &&
        session.frame_bool(&c.frame, TAG_AUTH_REQUIRED, false),
        "auth HELLO advertises AUTH required");

  check(do_get(&mut srv, &mut c, 1), "pre-auth GET roundtrip");
  check(is_err(&c.frame, OP_GET, CODE_AUTH_REQUIRED),
        "pre-auth data op -> AUTH_REQUIRED");

  var ws = Vec[WireField].new();
  ws.push(wire_int(TAG_METHOD, AUTH_TOKEN));
  var wrong = Vec[Int].new();
  wrong.push(0x78);
  wrong.push(0x78);
  ws.push(wire_bytes(TAG_TOKEN, &wrong));
  var af = req_frame(&mut c, OP_AUTH, &ws, &Vec[Int].new());
  check(pump(&mut srv, &mut c, &af), "AUTH wrong roundtrip");
  check(is_err(&c.frame, OP_AUTH, CODE_AUTH_FAILED), "wrong token -> AUTH_FAILED");

  var good = Vec[Int].new();
  good.push(0x73);
  good.push(0x33);
  good.push(0x63);
  good.push(0x72);
  good.push(0x65);
  good.push(0x74);
  var gs = Vec[WireField].new();
  gs.push(wire_int(TAG_METHOD, AUTH_TOKEN));
  gs.push(wire_bytes(TAG_TOKEN, &good));
  var gf = req_frame(&mut c, OP_AUTH, &gs, &Vec[Int].new());
  check(pump(&mut srv, &mut c, &gf), "AUTH good roundtrip");
  check(is_ok(&c.frame, OP_AUTH), "correct token -> ready");

  var ping = req_frame(&mut c, OP_PING, &Vec[WireField].new(), &Vec[Int].new());
  check(pump(&mut srv, &mut c, &ping), "post-auth PING roundtrip");
  check(is_ok(&c.frame, OP_PING), "post-auth PING OK");
  client_close(&mut c);

  // Lockout: three failed attempts on a fresh session.
  var d = client_new(srv.port);
  check(d.fd >= 0, "lockout client connects");
  check(do_hello(&mut srv, &mut d), "lockout HELLO");
  var attempt = 0;
  var last_code = -1;
  while attempt < MAX_AUTH_FAILURES {
    var fs = Vec[WireField].new();
    fs.push(wire_int(TAG_METHOD, AUTH_TOKEN));
    var bad = Vec[Int].new();
    bad.push(0x62);
    bad.push(0x61);
    bad.push(0x64);
    fs.push(wire_bytes(TAG_TOKEN, &bad));
    var f = req_frame(&mut d, OP_AUTH, &fs, &Vec[Int].new());
    if !pump(&mut srv, &mut d, &f) { break; }
    last_code = resp_code(&d.frame);
    attempt = attempt + 1;
  }
  check(attempt == MAX_AUTH_FAILURES && last_code == CODE_AUTH_LOCKED,
        "three failures -> AUTH_LOCKED");
  client_close(&mut d);
  server_shutdown(&mut srv);
  cleanup(auth_db);
}

fn main() -> Int {
  io.println("XIOM Station Conformance [loopback]");
  let _ = io.create_dir_all("out");
  let db_path = "out/station-loopback.wal";
  cleanup(db_path);

  var srv = server_new();
  let init_code = server_init(&mut srv, db_path, 4, 2, "", "127.0.0.1", 17867);
  check(init_code == CODE_OK, "server: open + listen");
  if init_code != CODE_OK {
    io.println("  server init code=" + init_code.to_str());
    return 1;
  }

  var c = client_new(srv.port);
  check(c.fd >= 0, "client: connect");

  check(do_hello(&mut srv, &mut c), "HELLO roundtrip");
  check(is_ok(&c.frame, OP_HELLO), "HELLO status OK");
  check(resp_int(&c.frame, TAG_PROTO_VERSION) == PROTO_VERSION,
        "HELLO protocol version");
  check(resp_int(&c.frame, TAG_SESSION_ID) > 0, "HELLO session id");
  check(!session.frame_bool(&c.frame, TAG_AUTH_REQUIRED, true),
        "HELLO auth not required");

  var ping_fs = Vec[WireField].new();
  ping_fs.push(wire_int(TAG_NONCE, 99));
  var ping = req_frame(&mut c, OP_PING, &ping_fs, &Vec[Int].new());
  check(pump(&mut srv, &mut c, &ping), "PING roundtrip");
  check(is_ok(&c.frame, OP_PING) && resp_int(&c.frame, TAG_NONCE) == 99,
        "PING nonce echo");

  test_crud(&mut srv, &mut c);
  test_range(&mut srv, &mut c);
  test_query(&mut srv, &mut c);
  test_txn(&mut srv, &mut c);
  test_typed(&mut srv, &mut c);
  test_multi_session(&mut srv, &mut c);

  var ck = req_frame(&mut c, OP_CHECKPOINT, &Vec[WireField].new(), &Vec[Int].new());
  check(pump(&mut srv, &mut c, &ck), "CHECKPOINT roundtrip");
  check(is_ok(&c.frame, OP_CHECKPOINT) && resp_int(&c.frame, TAG_LAST_LSN) > 0,
        "CHECKPOINT anchor LSN");

  test_framing(&mut srv);

  var close = req_frame(&mut c, OP_CLOSE, &Vec[WireField].new(), &Vec[Int].new());
  check(pump(&mut srv, &mut c, &close), "CLOSE roundtrip");
  check(is_ok(&c.frame, OP_CLOSE), "CLOSE status OK");
  client_close(&mut c);

  server_shutdown(&mut srv);
  cleanup(db_path);

  test_auth();

  io.println("XIOM Station Conformance [loopback]: " +
             g_pass.to_str() + "/" + g_total.to_str() + " passed");
  if g_pass == g_total { return 0; }
  return 1;
}
