// XIOM ORBITDB Station -- ORBITWIRE v1 session/backpressure suite.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure session behavior: partial ingress frames, pipelined frames, CRC/frame
// rejection, the bounded outbound queue (backpressure gate) and response
// builders. The transport loop lives in loopback_suite.xi.
//
// Summary line (consumed by scripts/station_suite.*):
//   XIOM Station Conformance [session]: P/T passed
module orbitdb_station_session_suite

use xiom.io;
use xiom.station.protocol;
use xiom.station.session;

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

fn encode(kind: Int, fs: &Vec[WireField], p: &Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  match frame_encode(kind, fs, p) {
    Ok(b) => { out = b; }
    Err(_) => {}
  }
  return out;
}

fn as_u8(frame: &Vec[Int]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < frame.len() {
    out.push((frame[i] & 0xFF) as UInt8);
    i = i + 1;
  }
  return out;
}

fn slice_u8(frame: &Vec[Int], from: Int, to: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = from;
  while i < to {
    out.push((frame[i] & 0xFF) as UInt8);
    i = i + 1;
  }
  return out;
}

fn main() -> Int {
  io.println("XIOM Station Conformance [session]");

  // -- partial ingress: a frame delivered in two chunks -------------------
  var fs = Vec[WireField].new();
  fs.push(wire_int(TAG_REQUEST_ID, 5));
  fs.push(wire_int(TAG_OP, OP_PING));
  var p = Vec[Int].new();
  p.push(1);
  p.push(2);
  p.push(3);
  var frame = encode(KIND_REQUEST, &fs, &p);
  check(frame.len() == 49, "session: fixture frame length");
  var half = frame.len() / 2;
  var s = session_new(1, -1, 4096);
  var first = slice_u8(&frame, 0, half);
  var second = slice_u8(&frame, half, frame.len());
  check(session_feed(&mut s, &first), "feed: first half accepted");
  check(session_pull(&mut s) == 0, "pull: incomplete frame needs more");
  check(session_feed(&mut s, &second), "feed: second half accepted");
  check(session_pull(&mut s) == 1, "pull: complete frame");
  check(s.frame.fields.len() == 2 &&
        session.frame_int(&s.frame, TAG_REQUEST_ID, 0) == 5,
        "pull: decoded request id");
  check(s.frame.payload.len() == 3 && s.frame.payload[2] == 3,
        "pull: decoded payload");
  check(s.rx.len() == 0, "pull: consumed bytes removed");
  check(session_pull(&mut s) == 0, "pull: no extra frame");

  // -- pipelined frames in one feed ---------------------------------------
  var two = Vec[Int].new();
  var i = 0;
  while i < frame.len() {
    two.push(frame[i]);
    i = i + 1;
  }
  i = 0;
  while i < frame.len() {
    two.push(frame[i]);
    i = i + 1;
  }
  var two_u8 = as_u8(&two);
  check(session_feed(&mut s, &two_u8), "feed: pipelined frames accepted");
  let p1 = session_pull(&mut s);
  let p2 = session_pull(&mut s);
  let p3 = session_pull(&mut s);
  check(p1 == 1 && p2 == 1 && p3 == 0, "pull: both pipelined frames");

  // -- bad CRC is a fatal framing error ----------------------------------
  var bad = Vec[Int].new();
  i = 0;
  while i < frame.len() {
    bad.push(frame[i]);
    i = i + 1;
  }
  bad[20] = (bad[20] + 1) % 256;
  var bad_u8 = as_u8(&bad);
  var s2 = session_new(2, -1, 4096);
  check(session_feed(&mut s2, &bad_u8), "feed: corrupt frame accepted");
  check(session_pull(&mut s2) == -1 && s2.pull_code == CODE_PROTOCOL,
        "pull: bad CRC -> PROTOCOL");

  // -- oversized header prefix is a LIMIT error --------------------------
  var over = Vec[Int].new();
  over.push(0x4F);
  over.push(0x42);
  over.push(0x57);
  over.push(0x31);
  over.push(1);
  over.push(KIND_REQUEST);
  over.push(0);
  over.push(0);
  over.push(1);
  over.push(0);
  over.push(1);
  over.push(0);
  over.push(0);
  over.push(0);
  over.push(0);
  over.push(0);
  var over_u8 = as_u8(&over);
  var s3 = session_new(3, -1, 4096);
  check(session_feed(&mut s3, &over_u8), "feed: oversized prefix accepted");
  check(session_pull(&mut s3) == -1 && s3.pull_code == CODE_LIMIT,
        "pull: oversized header -> LIMIT");

  // -- bounded outbound queue (backpressure) -----------------------------
  var s4 = session_new(4, -1, 64);
  var a40 = Vec[Int].new();
  i = 0;
  while i < 40 {
    a40.push(i);
    i = i + 1;
  }
  var b40 = Vec[Int].new();
  i = 0;
  while i < 40 {
    b40.push(i + 40);
    i = i + 1;
  }
  var c24 = Vec[Int].new();
  i = 0;
  while i < 24 {
    c24.push(i + 80);
    i = i + 1;
  }
  check(session_queue(&s4, &a40), "queue: 40/64 accepted");
  check(session_out_len(&s4) == 40, "queue: pending 40");
  check(session_can_read(&s4), "queue: can read under budget");
  check(!session_queue(&s4, &b40), "queue: 80/64 refused");
  check(session_out_len(&s4) == 40, "queue: refused frame not buffered");
  check(session_queue(&s4, &c24), "queue: exactly 64/64 accepted");
  check(!session_can_read(&s4), "queue: reads paused at budget");
  check(!session_queue(&s4, &Vec[Int].new()), "queue: empty frame refused");

  // -- response builders -------------------------------------------------
  var extra = Vec[WireField].new();
  extra.push(wire_int(TAG_NONCE, 123));
  var okf = ok_frame(7, OP_PING, &extra, &Vec[Int].new());
  var okd = session.empty_frame();
  let okt = frame_peek_total(&okf, 0);
  match frame_decode(&okf, 0, okt) {
    Ok(x) => { okd = x; }
    Err(_) => {}
  }
  check(okd.kind == KIND_RESPONSE && okd.payload.len() == 0,
        "response: ok frame kind");
  check(session.frame_int(&okd, TAG_STATUS, -1) == STATUS_OK &&
        session.frame_int(&okd, TAG_REQUEST_ID, 0) == 7 &&
        session.frame_int(&okd, TAG_OP, 0) == OP_PING &&
        session.frame_int(&okd, TAG_NONCE, 0) == 123,
        "response: ok fields");

  var errf = err_frame(8, OP_GET, CODE_NOT_FOUND, "key not found");
  var errd = session.empty_frame();
  let errt = frame_peek_total(&errf, 0);
  match frame_decode(&errf, 0, errt) {
    Ok(x) => { errd = x; }
    Err(_) => {}
  }
  check(session.frame_int(&errd, TAG_STATUS, -1) == STATUS_ERROR &&
        session.frame_int(&errd, TAG_CODE, 0) == CODE_NOT_FOUND,
        "response: error status + code");
  check(session.frame_text(&errd, TAG_MESSAGE, "") == "key not found",
        "response: error message");

  // -- close clears buffers ---------------------------------------------
  session_close(&s4);
  check(s4.state == STATE_CLOSED && s4.fd == -1 &&
        s4.out.len() == 0 && s4.rx.len() == 0, "close: state and buffers");

  io.println("XIOM Station Conformance [session]: " +
             g_pass.to_str() + "/" + g_total.to_str() + " passed");
  if g_pass == g_total { return 0; }
  return 1;
}
