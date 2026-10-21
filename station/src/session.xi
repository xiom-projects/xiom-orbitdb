// XIOM ORBITDB -- ORBITWIRE v1 session: ingress/egress buffers, frame pull,
// bounded outbound queue and the per-connection state slot.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// One session object owns its fd and buffers. The Station event loop is
// single-threaded for ST1, so a Session is never shared across threads; the
// DBFile lives in the StationActor and is only touched by the loop thread.
//
// Compiler note (C-ORBIT-14, v0.64.8): never bind a Vec with
// `let/var x = match ...`; declare + assign instead. Every decode below
// follows that rule.
module xiom.station.session

use xiom.net.socket;
use xiom.station.protocol;

pub type Session = {
  id: Int;
  fd: Int;
  state: Int;
  authed: Bool;
  auth_failures: Int;
  peer: Str;
  rx: Vec[Int];
  out: Vec[UInt8];
  out_at: Int;
  max_queue: Int;
  txn_ops: Int;
  closing: Bool;
  // Last frame pulled from rx (valid when the pull returns 1).
  frame: WireFrame;
  pull_code: Int;
}

pub fn empty_frame() -> WireFrame {
  return WireFrame{ kind: 0, flags: 0, fields: Vec[WireField].new(),
                    payload: Vec[Int].new() };
}

pub fn session_new(id: Int, fd: Int, max_queue: Int) -> Session {
  return Session{ id: id, fd: fd, state: STATE_NEW, authed: false,
                  auth_failures: 0, peer: "", rx: Vec[Int].new(),
                  out: Vec[UInt8].new(), out_at: 0, max_queue: max_queue,
                  txn_ops: 0, closing: false, frame: empty_frame(),
                  pull_code: 0 };
}

// Append received bytes. False means the ingress buffer would exceed the
// hard cap (an incomplete frame above the wire limit): the caller closes.
pub fn session_feed(s: &mut Session, bytes: &Vec[UInt8]) -> Bool {
  if s.rx.len() + bytes.len() > MAX_FRAME_BYTES + 65536 { return false; }
  var i = 0;
  while i < bytes.len() {
    s.rx.push((bytes[i] as Int) & 0xFF);
    i = i + 1;
  }
  return true;
}

// Pull one complete frame into s.frame. 0 = need more bytes, 1 = frame ready,
// -1 = fatal framing error (s.pull_code carries the wire code).
pub fn session_pull(s: &mut Session) -> Int {
  if s.rx.len() == 0 { return 0; }
  let total = frame_peek_total(&s.rx, 0);
  if total == 0 { return 0; }
  if total < 0 {
    if total == -3 { s.pull_code = CODE_LIMIT; } else { s.pull_code = CODE_PROTOCOL; }
    return -1;
  }
  var f = empty_frame();
  match frame_decode(&s.rx, 0, total) {
    Ok(x) => { f = x; }
    Err(e) => {
      s.pull_code = e;
      return -1;
    }
  }
  s.frame = f;
  var rest = Vec[Int].new();
  var i = total;
  while i < s.rx.len() {
    rest.push(s.rx[i]);
    i = i + 1;
  }
  s.rx = rest;
  return 1;
}

pub fn session_out_len(s: &Session) -> Int {
  return s.out.len() - s.out_at;
}

pub fn session_can_read(s: &Session) -> Bool {
  return session_out_len(s) < s.max_queue;
}

fn session_compact_out(s: &mut Session) {
  if s.out_at <= 0 { return; }
  var rest = Vec[UInt8].new();
  var i = s.out_at;
  while i < s.out.len() {
    rest.push(s.out[i]);
    i = i + 1;
  }
  s.out = rest;
  s.out_at = 0;
}

// Queue a fully encoded response. False = the bounded outbound queue would
// overflow; the caller stops reading this session (backpressure) and retries
// the queue after a flush, or closes a misbehaving client.
pub fn session_queue(s: &mut Session, frame: &Vec[Int]) -> Bool {
  if frame.len() == 0 { return false; }
  session_compact_out(s);
  if s.out.len() + frame.len() > s.max_queue { return false; }
  var i = 0;
  while i < frame.len() {
    s.out.push((frame[i] & 0xFF) as UInt8);
    i = i + 1;
  }
  return true;
}

// Flush as much of the queue as the socket accepts. Returns the remaining
// pending bytes, or -1 on a socket error (the caller closes).
pub fn session_flush(s: &mut Session) -> Int {
  let pending = session_out_len(s);
  if pending <= 0 {
    if s.out.len() > 0 {
      s.out = Vec[UInt8].new();
      s.out_at = 0;
    }
    return 0;
  }
  if s.fd < 0 { return -1; }
  var chunk = Vec[UInt8].new();
  var i = s.out_at;
  while i < s.out.len() {
    chunk.push(s.out[i]);
    i = i + 1;
  }
  var sent = 0;
  var failed = false;
  match socket_send(s.fd, &chunk) {
    Ok(n) => { sent = n; }
    Err(_) => { failed = true; }
  }
  if failed { return -1; }
  if sent > 0 {
    s.out_at = s.out_at + sent;
    if s.out_at >= s.out.len() {
      s.out = Vec[UInt8].new();
      s.out_at = 0;
    }
  }
  return session_out_len(s);
}

pub fn session_close(s: &mut Session) {
  if s.fd >= 0 {
    socket_close(s.fd);
    s.fd = -1;
  }
  s.state = STATE_CLOSED;
  s.rx = Vec[Int].new();
  s.out = Vec[UInt8].new();
  s.out_at = 0;
  s.frame = empty_frame();
}

// ---------------------------------------------------------------------------
// Response builders
// ---------------------------------------------------------------------------

pub fn ok_frame(req_id: Int, op: Int, extra: &Vec[WireField],
                payload: &Vec[Int]) -> Vec[Int] {
  return response_frame(req_id, op, STATUS_OK, CODE_OK, "", extra, payload);
}

pub fn err_frame(req_id: Int, op: Int, code: Int, message: Str) -> Vec[Int] {
  return response_frame(req_id, op, STATUS_ERROR, code, message,
                        &Vec[WireField].new(), &Vec[Int].new());
}

pub fn response_frame(req_id: Int, op: Int, status: Int, code: Int,
                      message: Str, extra: &Vec[WireField],
                      payload: &Vec[Int]) -> Vec[Int] {
  var fs = Vec[WireField].new();
  fs.push(wire_int(TAG_REQUEST_ID, req_id));
  fs.push(wire_int(TAG_OP, op));
  fs.push(wire_int(TAG_STATUS, status));
  if status != STATUS_OK {
    fs.push(wire_int(TAG_CODE, code));
    fs.push(wire_text(TAG_MESSAGE, message));
  }
  var i = 0;
  while i < extra.len() {
    fs.push(extra[i]);
    i = i + 1;
  }
  var out = Vec[Int].new();
  match frame_encode(KIND_RESPONSE, &fs, payload) {
    Ok(b) => { out = b; }
    Err(_) => {}
  }
  return out;
}

// ---------------------------------------------------------------------------
// Small field readers (missing/wrong-type -> fallback)
// ---------------------------------------------------------------------------

pub fn frame_int(f: &WireFrame, tag: Int, fallback: Int) -> Int {
  match wire_get_int(&f.fields, tag) {
    None => { return fallback; }
    Some(v) => { return v; }
  }
}

pub fn frame_bool(f: &WireFrame, tag: Int, fallback: Bool) -> Bool {
  match wire_get_bool(&f.fields, tag) {
    None => { return fallback; }
    Some(v) => { return v; }
  }
}

pub fn frame_has_int(f: &WireFrame, tag: Int) -> Bool {
  return wire_has_int(&f.fields, tag);
}

pub fn frame_text(f: &WireFrame, tag: Int, fallback: Str) -> Str {
  match wire_get_text(&f.fields, tag) {
    None => { return fallback; }
    Some(v) => { return v; }
  }
}

pub fn frame_bytes(f: &WireFrame, tag: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  match wire_get_bytes(&f.fields, tag) {
    None => {}
    Some(b) => { out = b; }
  }
  return out;
}
