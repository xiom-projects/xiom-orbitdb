// XIOM ORBITDB Station -- crash-harness client (ST2).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Speaks ORBITWIRE v1 to the hello-station so the crash harness can kill the
// server at a deterministic point and verify recovery on restart. Modes
// (env STATION_CRASH_MODE):
//   writer_uncommitted -- HELLO, BEGIN, PUT, print CRASH-READY, wait for EOF
//                         (the harness kills the server; the txn must be
//                         discarded on restart)
//   writer_committed   -- HELLO, auto-commit PUT, print CRASH-READY, wait EOF
//   verify_present     -- HELLO, GET key, expect the int value; print OK/FAIL
//   verify_absent      -- HELLO, GET key, expect NOT_FOUND; print OK/FAIL
//   commit             -- HELLO, auto-commit PUT; print CRASH-COMMIT OK/FAIL
//
// Env: ORBITDB_STATION_PORT (required), STATION_CRASH_KEY (default 1),
//      STATION_CRASH_VALUE (default 4242), STATION_CRASH_WAIT (default 60s).
module orbitdb_station_crash_client

use xiom.io;
use xiom.os.env;
use xiom.net.socket;
use xiom.station.protocol;
use xiom.station.session;

pub type C = {
  fd: Int;
  rx: Vec[Int];
  frame: WireFrame;
  code: Int;
  next_id: Int;
}

fn client_new(port: Int) -> C {
  var c = C{ fd: -1, rx: Vec[Int].new(), frame: session.empty_frame(),
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

fn send_frame(c: &mut C, frame: &Vec[Int]) -> Bool {
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

// 1 = frame ready, 0 = timeout/need more, -1 = EOF/protocol failure.
fn pull(c: &mut C) -> Int {
  var guard = 0;
  while guard < 4 {
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

fn request(c: &mut C, op: Int, fields: &Vec[WireField],
           payload: &Vec[Int]) -> Bool {
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
  if !send_frame(c, &out) { return false; }
  var guard = 0;
  while guard < 200 {
    let st = pull(c);
    if st == 1 { return true; }
    if st < 0 { return false; }
    guard = guard + 1;
  }
  return false;
}

fn hello(c: &mut C) -> Bool {
  var fs = Vec[WireField].new();
  fs.push(wire_int(TAG_PROTO_VERSION, PROTO_VERSION));
  if !request(c, OP_HELLO, &fs, &Vec[Int].new()) { return false; }
  return session.frame_int(&c.frame, TAG_STATUS, -1) == STATUS_OK;
}

fn put(c: &mut C, key: Int, value: Int) -> Bool {
  var fs = Vec[WireField].new();
  fs.push(wire_int(TAG_KEY, key));
  fs.push(wire_int(TAG_ROW_KIND, ROW_INT));
  fs.push(wire_int(TAG_VALUE, value));
  if !request(c, OP_PUT, &fs, &Vec[Int].new()) { return false; }
  return session.frame_int(&c.frame, TAG_STATUS, -1) == STATUS_OK;
}

fn begin(c: &mut C) -> Bool {
  if !request(c, OP_BEGIN, &Vec[WireField].new(), &Vec[Int].new()) {
    return false;
  }
  return session.frame_int(&c.frame, TAG_STATUS, -1) == STATUS_OK;
}

fn get_int(c: &mut C, key: Int) -> Bool {
  var fs = Vec[WireField].new();
  fs.push(wire_int(TAG_KEY, key));
  return request(c, OP_GET, &fs, &Vec[Int].new());
}

fn wait_eof(c: &mut C, seconds: Int) {
  let deadline = io.time_now() + seconds * 1000;
  while io.time_now() < deadline {
    var bytes = Vec[UInt8].new();
    match socket_recv(c.fd, 65536) {
      Ok(b) => {
        if b.len() == 0 {
          io.println("CRASH-EOF");
          return;
        }
        var i = 0;
        while i < b.len() {
          c.rx.push((b[i] as Int) & 0xFF);
          i = i + 1;
        }
      }
      Err(_) => {}
    }
  }
  io.println("CRASH-EOF-TIMEOUT");
}

fn main() -> Int {
  let mode = env.var_or("STATION_CRASH_MODE", "");
  let port_raw = env.var_or("ORBITDB_STATION_PORT", "");
  let key = env.var_or("STATION_CRASH_KEY", "1");
  let value_raw = env.var_or("STATION_CRASH_VALUE", "4242");
  let wait_raw = env.var_or("STATION_CRASH_WAIT", "60");
  var port = 0;
  var key_n = 1;
  var value = 4242;
  var wait_s = 60;
  match io.parse_int(port_raw) { Ok(v) => { port = v; } Err(_) => {} }
  match io.parse_int(key) { Ok(v) => { key_n = v; } Err(_) => {} }
  match io.parse_int(value_raw) { Ok(v) => { value = v; } Err(_) => {} }
  match io.parse_int(wait_raw) { Ok(v) => { wait_s = v; } Err(_) => {} }
  if port <= 0 {
    io.println("CRASH-ENV-FAIL port");
    return 2;
  }

  var c = client_new(port);
  if c.fd < 0 {
    io.println("CRASH-CONNECT-FAIL");
    return 2;
  }
  if !hello(&mut c) {
    io.println("CRASH-HELLO-FAIL");
    return 3;
  }

  if mode == "writer_uncommitted" {
    if !begin(&mut c) {
      io.println("CRASH-BEGIN-FAIL");
      return 4;
    }
    if !put(&mut c, key_n, value) {
      io.println("CRASH-PUT-FAIL");
      return 4;
    }
    io.println("CRASH-READY");
    io.flush_stdout();
    wait_eof(&mut c, wait_s);
    return 0;
  }
  if mode == "writer_committed" {
    if !put(&mut c, key_n, value) {
      io.println("CRASH-PUT-FAIL");
      return 4;
    }
    io.println("CRASH-READY");
    io.flush_stdout();
    wait_eof(&mut c, wait_s);
    return 0;
  }
  if mode == "commit" {
    if !put(&mut c, key_n, value) {
      io.println("CRASH-COMMIT FAIL put");
      return 5;
    }
    io.println("CRASH-COMMIT OK");
    return 0;
  }
  if mode == "verify_present" {
    if !get_int(&mut c, key_n) {
      io.println("CRASH-VERIFY FAIL request");
      return 5;
    }
    let status = session.frame_int(&c.frame, TAG_STATUS, -1);
    let kind = session.frame_int(&c.frame, TAG_ROW_KIND, -1);
    let got = session.frame_int(&c.frame, TAG_VALUE, -999999999);
    if status == STATUS_OK && kind == ROW_INT && got == value {
      io.println("CRASH-VERIFY OK present key=" + key_n.to_str() +
                 " value=" + got.to_str());
      return 0;
    }
    io.println("CRASH-VERIFY FAIL present status=" + status.to_str() +
               " kind=" + kind.to_str() + " value=" + got.to_str());
    return 5;
  }
  if mode == "verify_absent" {
    if !get_int(&mut c, key_n) {
      io.println("CRASH-VERIFY FAIL request");
      return 5;
    }
    let status = session.frame_int(&c.frame, TAG_STATUS, -1);
    let code = session.frame_int(&c.frame, TAG_CODE, -1);
    if status == STATUS_ERROR && code == CODE_NOT_FOUND {
      io.println("CRASH-VERIFY OK absent key=" + key_n.to_str());
      return 0;
    }
    io.println("CRASH-VERIFY FAIL absent status=" + status.to_str() +
               " code=" + code.to_str());
    return 5;
  }
  io.println("CRASH-ENV-FAIL mode=" + mode);
  return 2;
}
