// XIOM ORBITDB -- ORBITWIRE v1 frame codec (Station wire protocol).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure, dependency-free codec: length-prefixed, typed, checksummed frames.
// The full specification is station/docs/ORBITWIRE.md; docs/FORMATS.md
// section 7 carries the on-wire summary and versioning policy.
//
// Frame (all integers little-endian):
//   0   4  magic "OBW1" (0x4F 0x42 0x57 0x31)
//   4   1  version (1)
//   5   1  kind (1 = REQUEST, 2 = RESPONSE)
//   6   1  flags (0 in v1)
//   7   1  reserved (0)
//   8   4  header length (u32)
//   12  4  payload length (u32)
//   16  N  header (typed field list)
//   ..  M  payload (op-specific bytes)
//   ..  4  CRC32C over bytes [4, end-4) (u32)
//
// Header field list:
//   u16 field_count
//   repeat: u8 tag, u8 type, u16 value_len, value bytes
// Types: 0 = INT (8 bytes), 1 = BOOL (1 byte), 2 = TEXT (UTF-8 bytes),
//        3 = BYTES (opaque bytes). Unknown tags are ignored (forward
//        compatibility); unknown types, trailing bytes or a count above
//        MAX_FIELDS are protocol errors.
//
// Byte convention: Vec[Int] elements 0..255 (the engine's storage byte
// convention), converted to Vec[UInt8] only at the socket boundary.
module xiom.station.protocol

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

pub const PROTO_VERSION: Int = 1;

pub const KIND_REQUEST: Int = 1;
pub const KIND_RESPONSE: Int = 2;

pub const FRAME_MAGIC_0: Int = 0x4F;
pub const FRAME_MAGIC_1: Int = 0x42;
pub const FRAME_MAGIC_2: Int = 0x57;
pub const FRAME_MAGIC_3: Int = 0x31;

pub const FRAME_PREFIX_BYTES: Int = 16;
pub const FRAME_CRC_BYTES: Int = 4;

pub const FIELD_INT: Int = 0;
pub const FIELD_BOOL: Int = 1;
pub const FIELD_TEXT: Int = 2;
pub const FIELD_BYTES: Int = 3;

// Header tags (the v1 field dictionary).
pub const TAG_REQUEST_ID: Int = 1;
pub const TAG_OP: Int = 2;
pub const TAG_STATUS: Int = 3;
pub const TAG_CODE: Int = 4;
pub const TAG_PROTO_VERSION: Int = 5;
pub const TAG_SERVER_VERSION: Int = 6;
pub const TAG_CAPABILITIES: Int = 7;
pub const TAG_SESSION_ID: Int = 8;
pub const TAG_AUTH_REQUIRED: Int = 9;
pub const TAG_MAX_FRAME: Int = 10;
pub const TAG_MAX_PAYLOAD: Int = 11;
pub const TAG_MAX_QUEUE: Int = 12;
pub const TAG_TXN_OPEN: Int = 13;
pub const TAG_ROW_COUNT: Int = 14;
pub const TAG_MESSAGE: Int = 15;
pub const TAG_NONCE: Int = 16;
pub const TAG_METHOD: Int = 17;
pub const TAG_KEY: Int = 18;
pub const TAG_VALUE: Int = 19;
pub const TAG_ROW_KIND: Int = 20;
pub const TAG_LOW: Int = 21;
pub const TAG_HIGH: Int = 22;
pub const TAG_LIMIT: Int = 23;
pub const TAG_OFFSET: Int = 24;
pub const TAG_ORDER: Int = 25;
pub const TAG_HAS_BOUNDS: Int = 26;
pub const TAG_CONDITION: Int = 27;
pub const TAG_LAST_LSN: Int = 28;
pub const TAG_DB_SIZE: Int = 29;
pub const TAG_TOKEN: Int = 30;
pub const TAG_TRUNCATED: Int = 31;

// Ops. The required ST1 set is HELLO/AUTH/PING/BEGIN/PUT/GET/RANGE/QUERY/
// COMMIT/ABORT/CLOSE; DELETE and CHECKPOINT are additive v1 ops so the wire
// can express the whole public write surface (and admin phase 3).
pub const OP_HELLO: Int = 1;
pub const OP_AUTH: Int = 2;
pub const OP_PING: Int = 3;
pub const OP_BEGIN: Int = 4;
pub const OP_PUT: Int = 5;
pub const OP_GET: Int = 6;
pub const OP_RANGE: Int = 7;
pub const OP_QUERY: Int = 8;
pub const OP_COMMIT: Int = 9;
pub const OP_ABORT: Int = 10;
pub const OP_CLOSE: Int = 11;
pub const OP_DELETE: Int = 12;
pub const OP_CHECKPOINT: Int = 13;

// Status and error taxonomy (stable u16 codes; mapped from DbError).
pub const STATUS_OK: Int = 0;
pub const STATUS_ERROR: Int = 1;

pub const CODE_OK: Int = 0;
pub const CODE_PROTOCOL: Int = 1;
pub const CODE_AUTH_REQUIRED: Int = 2;
pub const CODE_AUTH_FAILED: Int = 3;
pub const CODE_NOT_FOUND: Int = 4;
pub const CODE_DUPLICATE_KEY: Int = 5;
pub const CODE_CONSTRAINT: Int = 6;
pub const CODE_SCHEMA_MISMATCH: Int = 7;
pub const CODE_STORAGE: Int = 8;
pub const CODE_CORRUPTION: Int = 9;
pub const CODE_LIMIT: Int = 10;
pub const CODE_TXN_ACTIVE: Int = 11;
pub const CODE_NO_TXN: Int = 12;
pub const CODE_STALE_HANDLE: Int = 13;
pub const CODE_CLOSED: Int = 14;
pub const CODE_INTERNAL: Int = 15;
pub const CODE_UNSUPPORTED: Int = 16;
pub const CODE_AUTH_LOCKED: Int = 17;

// Row kinds carried by GET/PUT/RANGE.
pub const ROW_INT: Int = 0;
pub const ROW_TYPED: Int = 1;
pub const ROW_ABSENT: Int = 255;

// v1 limits (advertised in HELLO; enforced by the codec and server).
pub const MAX_FRAME_BYTES: Int = 1048576;
pub const MAX_HEADER_BYTES: Int = 65536;
pub const MAX_PAYLOAD_BYTES: Int = 524288;
pub const MAX_FIELDS: Int = 64;
pub const MAX_QUEUE_BYTES: Int = 4194304;
pub const MAX_SESSIONS: Int = 64;
pub const MAX_AUTH_FAILURES: Int = 3;
pub const DEFAULT_RANGE_ROWS: Int = 500;
pub const MAX_RANGE_ROWS: Int = 1000;
pub const MAX_QUERY_ROWS: Int = 5000;
pub const MAX_WIRE_ROWS: Int = 4096;
pub const MAX_TXN_OPS: Int = 10000;

// Session states.
pub const STATE_NEW: Int = 0;
pub const STATE_GREETED: Int = 1;
pub const STATE_READY: Int = 2;
pub const STATE_TXN: Int = 3;
pub const STATE_CLOSING: Int = 4;
pub const STATE_CLOSED: Int = 5;

// AUTH methods.
pub const AUTH_NONE: Int = 0;
pub const AUTH_TOKEN: Int = 1;

// Capability bits advertised by HELLO.
pub const CAP_TYPED_ROWS: Int = 1;
pub const CAP_TXN: Int = 2;
pub const CAP_QUERY: Int = 4;
pub const CAP_CHECKPOINT: Int = 8;
pub const CAP_AUTH: Int = 16;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

pub type WireField = {
  tag: Int;
  kind: Int;
  i: Int;
  data: Vec[Int];
}

pub type WireFrame = {
  kind: Int;
  flags: Int;
  fields: Vec[WireField];
  payload: Vec[Int];
}

pub type WireRow = {
  kind: Int;
  key: Int;
  value: Int;
  data: Vec[Int];
}

// ---------------------------------------------------------------------------
// Small LE writers/readers (header sizes; 0 on out-of-range reads)
// ---------------------------------------------------------------------------

fn wire_push_u16(out: &mut Vec[Int], v: Int) {
  out.push(v & 0xFF);
  out.push((v >> 8) & 0xFF);
}

fn wire_push_u32(out: &mut Vec[Int], v: Int) {
  out.push(v & 0xFF);
  out.push((v >> 8) & 0xFF);
  out.push((v >> 16) & 0xFF);
  out.push((v >> 24) & 0xFF);
}

fn wire_push_i64(out: &mut Vec[Int], v: Int) {
  var k = 0;
  while k < 8 {
    out.push((v >> (8 * k)) & 0xFF);
    k = k + 1;
  }
}

fn wire_read_u16(buf: &Vec[Int], at: Int) -> Int {
  if at < 0 { return 0; }
  if at + 2 > buf.len() { return 0; }
  return (buf[at] & 0xFF) | ((buf[at + 1] & 0xFF) << 8);
}

fn wire_read_u32(buf: &Vec[Int], at: Int) -> Int {
  if at < 0 { return 0; }
  if at + 4 > buf.len() { return 0; }
  return (buf[at] & 0xFF) | ((buf[at + 1] & 0xFF) << 8) |
         ((buf[at + 2] & 0xFF) << 16) | ((buf[at + 3] & 0xFF) << 24);
}

// i64 LE without leaving the signed 64-bit range (same shape as the engine's
// tuple_read_int_le, local so the wire codec stays engine-independent).
pub fn wire_read_i64(buf: &Vec[Int], at: Int) -> Int {
  if at < 0 { return 0; }
  if at + 8 > buf.len() { return 0; }
  let top = buf[at + 7] & 0xFF;
  let sign = (top & 0x80) == 0x80;
  var v = top & 0x7F;
  var k = 6;
  while k >= 0 {
    v = (v << 8) | (buf[at + k] & 0xFF);
    k = k - 1;
  }
  if sign {
    return -(9223372036854775807 - v) - 1;
  }
  return v;
}

// CRC32C/Castagnoli over byte elements [from, to) -- FORMATS.md section 1.
// Local (no engine import) so the wire codec is a pure stdlib-free unit; the
// conformance suite cross-checks parity with the engine's page checksum.
pub fn wire_crc32c_range(buf: &Vec[Int], from: Int, to: Int) -> Int {
  if from < 0 { return 0; }
  if to > buf.len() { return 0; }
  var crc = 0xFFFFFFFF;
  var i = from;
  while i < to {
    crc = crc ^ (buf[i] & 0xFF);
    var k = 0;
    while k < 8 {
      if (crc & 1) == 1 {
        crc = (crc >> 1) ^ 0x82F63B78;
      } else {
        crc = crc >> 1;
      }
      k = k + 1;
    }
    i = i + 1;
  }
  return crc ^ 0xFFFFFFFF;
}

// ---------------------------------------------------------------------------
// Field constructors and accessors
// ---------------------------------------------------------------------------

pub fn wire_int(tag: Int, v: Int) -> WireField {
  return WireField{ tag: tag, kind: FIELD_INT, i: v, data: Vec[Int].new() };
}

pub fn wire_bool(tag: Int, v: Bool) -> WireField {
  var iv = 0;
  if v { iv = 1; }
  return WireField{ tag: tag, kind: FIELD_BOOL, i: iv, data: Vec[Int].new() };
}

pub fn wire_text(tag: Int, s: Str) -> WireField {
  var data = Vec[Int].new();
  var i = 0;
  while i < s.len() {
    data.push(s.byte_at(i) & 0xFF);
    i = i + 1;
  }
  return WireField{ tag: tag, kind: FIELD_TEXT, i: 0, data: data };
}

pub fn wire_bytes(tag: Int, data: &Vec[Int]) -> WireField {
  var out = Vec[Int].new();
  var i = 0;
  while i < data.len() {
    out.push(data[i] & 0xFF);
    i = i + 1;
  }
  return WireField{ tag: tag, kind: FIELD_BYTES, i: 0, data: out };
}

fn wire_bytes_to_str(data: &Vec[Int]) -> Str {
  var bytes = Vec[UInt8].new();
  var i = 0;
  while i < data.len() {
    bytes.push((data[i] & 0xFF) as UInt8);
    i = i + 1;
  }
  return Str::from_utf8(bytes);
}

pub fn wire_get_field(fields: &Vec[WireField], tag: Int) -> Option[WireField] {
  var i = 0;
  while i < fields.len() {
    let f = fields[i];
    if f.tag == tag { return Some(f); }
    i = i + 1;
  }
  return None;
}

pub fn wire_get_int(fields: &Vec[WireField], tag: Int) -> Option[Int] {
  match wire_get_field(fields, tag) {
    None => { return None; }
    Some(f) => {
      if f.kind == FIELD_INT { return Some(f.i); }
      if f.kind == FIELD_BOOL { return Some(f.i); }
      return None;
    }
  }
}

pub fn wire_get_bool(fields: &Vec[WireField], tag: Int) -> Option[Bool] {
  match wire_get_int(fields, tag) {
    None => { return None; }
    Some(v) => { return Some(v != 0); }
  }
}

pub fn wire_get_bytes(fields: &Vec[WireField], tag: Int) -> Option[Vec[Int]] {
  match wire_get_field(fields, tag) {
    None => { return None; }
    Some(f) => {
      if f.kind == FIELD_BYTES { return Some(f.data); }
      if f.kind == FIELD_TEXT { return Some(f.data); }
      return None;
    }
  }
}

pub fn wire_get_text(fields: &Vec[WireField], tag: Int) -> Option[Str] {
  match wire_get_field(fields, tag) {
    None => { return None; }
    Some(f) => {
      if f.kind != FIELD_TEXT && f.kind != FIELD_BYTES { return None; }
      return Some(wire_bytes_to_str(&f.data));
    }
  }
}

pub fn wire_get_all_bytes(fields: &Vec[WireField], tag: Int) -> Vec[Vec[Int]] {
  var out = Vec[Vec[Int]].new();
  var i = 0;
  while i < fields.len() {
    let f = fields[i];
    if f.tag == tag && f.kind == FIELD_BYTES {
      out.push(f.data);
    }
    i = i + 1;
  }
  return out;
}

pub fn wire_has_int(fields: &Vec[WireField], tag: Int) -> Bool {
  match wire_get_int(fields, tag) {
    None => { return false; }
    Some(_) => { return true; }
  }
}

// ---------------------------------------------------------------------------
// Header + frame encode
// ---------------------------------------------------------------------------

pub fn wire_header_encode(fields: &Vec[WireField]) -> Result[Vec[Int], Int] {
  if fields.len() > MAX_FIELDS { return Err(CODE_LIMIT); }
  var out = Vec[Int].new();
  wire_push_u16(&mut out, fields.len());
  var i = 0;
  while i < fields.len() {
    let f = fields[i];
    var vlen = 0;
    if f.kind == FIELD_INT {
      vlen = 8;
    } else if f.kind == FIELD_BOOL {
      vlen = 1;
    } else if f.kind == FIELD_TEXT || f.kind == FIELD_BYTES {
      vlen = f.data.len();
    } else {
      return Err(CODE_PROTOCOL);
    }
    if vlen > 65535 { return Err(CODE_LIMIT); }
    out.push(f.tag & 0xFF);
    out.push(f.kind & 0xFF);
    wire_push_u16(&mut out, vlen);
    if f.kind == FIELD_INT {
      wire_push_i64(&mut out, f.i);
    } else if f.kind == FIELD_BOOL {
      if f.i != 0 { out.push(1); } else { out.push(0); }
    } else {
      var k = 0;
      while k < f.data.len() {
        out.push(f.data[k] & 0xFF);
        k = k + 1;
      }
    }
    if out.len() > MAX_HEADER_BYTES { return Err(CODE_LIMIT); }
    i = i + 1;
  }
  return Ok(out);
}


pub fn frame_encode(kind: Int, fields: &Vec<WireField>,
                    payload: &Vec<Int>) -> Result[Vec[Int], Int] {
  if kind != KIND_REQUEST && kind != KIND_RESPONSE { return Err(CODE_PROTOCOL); }
  if payload.len() > MAX_PAYLOAD_BYTES { return Err(CODE_LIMIT); }
  var header = Vec[Int].new();
  match wire_header_encode(fields) {
    Ok(h) => { header = h; }
    Err(e) => { return Err(e); }
  }
  if header.len() > MAX_HEADER_BYTES { return Err(CODE_LIMIT); }
  let total = FRAME_PREFIX_BYTES + header.len() + payload.len() + FRAME_CRC_BYTES;
  if total > MAX_FRAME_BYTES { return Err(CODE_LIMIT); }

  var out = Vec[Int].new();
  out.push(FRAME_MAGIC_0);
  out.push(FRAME_MAGIC_1);
  out.push(FRAME_MAGIC_2);
  out.push(FRAME_MAGIC_3);
  out.push(PROTO_VERSION);
  out.push(kind);
  out.push(0); // flags
  out.push(0); // reserved
  wire_push_u32(&mut out, header.len());
  wire_push_u32(&mut out, payload.len());
  var i = 0;
  while i < header.len() {
    out.push(header[i] & 0xFF);
    i = i + 1;
  }
  i = 0;
  while i < payload.len() {
    out.push(payload[i] & 0xFF);
    i = i + 1;
  }
  let crc = wire_crc32c_range(&out, 4, out.len());
  wire_push_u32(&mut out, crc);
  if out.len() != total { return Err(CODE_INTERNAL); }
  return Ok(out);
}

// ---------------------------------------------------------------------------
// Header + frame decode
// ---------------------------------------------------------------------------

// 0 = need more bytes; -1 = bad magic; -2 = bad version; -3 = bad limits;
// -4 = bad flags/reserved; otherwise the total frame length in bytes.
pub fn frame_peek_total(buf: &Vec[Int], at: Int) -> Int {
  if at < 0 { return -1; }
  if at + FRAME_PREFIX_BYTES > buf.len() { return 0; }
  if (buf[at] & 0xFF) != FRAME_MAGIC_0 { return -1; }
  if (buf[at + 1] & 0xFF) != FRAME_MAGIC_1 { return -1; }
  if (buf[at + 2] & 0xFF) != FRAME_MAGIC_2 { return -1; }
  if (buf[at + 3] & 0xFF) != FRAME_MAGIC_3 { return -1; }
  if (buf[at + 4] & 0xFF) != PROTO_VERSION { return -2; }
  if (buf[at + 6] & 0xFF) != 0 { return -4; }
  if (buf[at + 7] & 0xFF) != 0 { return -4; }
  let hlen = wire_read_u32(buf, at + 8);
  let plen = wire_read_u32(buf, at + 12);
  if hlen > MAX_HEADER_BYTES { return -3; }
  if plen > MAX_PAYLOAD_BYTES { return -3; }
  let total = FRAME_PREFIX_BYTES + hlen + plen + FRAME_CRC_BYTES;
  if total > MAX_FRAME_BYTES { return -3; }
  if at + total > buf.len() { return 0; }
  return total;
}

fn wire_header_decode(buf: &Vec[Int], at: Int,
                      hlen: Int) -> Result[Vec[WireField], Int] {
  var fields = Vec[WireField].new();
  if hlen < 2 { return Err(CODE_PROTOCOL); }
  let end = at + hlen;
  let count = wire_read_u16(buf, at);
  if count > MAX_FIELDS { return Err(CODE_LIMIT); }
  var p = at + 2;
  var i = 0;
  while i < count {
    if p + 4 > end { return Err(CODE_PROTOCOL); }
    let tag = buf[p] & 0xFF;
    let kind = buf[p + 1] & 0xFF;
    let vlen = wire_read_u16(buf, p + 2);
    p = p + 4;
    if p + vlen > end { return Err(CODE_PROTOCOL); }
    var f = WireField{ tag: tag, kind: kind, i: 0, data: Vec[Int].new() };
    if kind == FIELD_INT {
      if vlen != 8 { return Err(CODE_PROTOCOL); }
      f.i = wire_read_i64(buf, p);
    } else if kind == FIELD_BOOL {
      if vlen != 1 { return Err(CODE_PROTOCOL); }
      f.i = buf[p] & 0xFF;
    } else if kind == FIELD_TEXT || kind == FIELD_BYTES {
      var k = 0;
      while k < vlen {
        f.data.push(buf[p + k] & 0xFF);
        k = k + 1;
      }
    } else {
      return Err(CODE_PROTOCOL);
    }
    fields.push(f);
    p = p + vlen;
    i = i + 1;
  }
  if p != end { return Err(CODE_PROTOCOL); }
  return Ok(fields);
}

// Decode a complete frame whose total length `total` came from
// frame_peek_total. Verifies the CRC and the header, never the op semantics.
pub fn frame_decode(buf: &Vec[Int], at: Int, total: Int) -> Result[WireFrame, Int] {
  if at < 0 { return Err(CODE_PROTOCOL); }
  if total < FRAME_PREFIX_BYTES + FRAME_CRC_BYTES { return Err(CODE_PROTOCOL); }
  if at + total > buf.len() { return Err(CODE_PROTOCOL); }
  let crc_stored = wire_read_u32(buf, at + total - FRAME_CRC_BYTES);
  let crc_calc = wire_crc32c_range(buf, at + 4, at + total - FRAME_CRC_BYTES);
  if crc_stored != crc_calc { return Err(CODE_PROTOCOL); }
  let kind = buf[at + 5] & 0xFF;
  if kind != KIND_REQUEST && kind != KIND_RESPONSE { return Err(CODE_PROTOCOL); }
  let flags = buf[at + 6] & 0xFF;
  let hlen = wire_read_u32(buf, at + 8);
  let plen = wire_read_u32(buf, at + 12);
  if at + FRAME_PREFIX_BYTES + hlen + plen + FRAME_CRC_BYTES != at + total {
    return Err(CODE_PROTOCOL);
  }
  var fields = Vec[WireField].new();
  match wire_header_decode(buf, at + FRAME_PREFIX_BYTES, hlen) {
    Ok(f) => { fields = f; }
    Err(e) => { return Err(e); }
  }
  var payload = Vec[Int].new();
  var p = at + FRAME_PREFIX_BYTES + hlen;
  var k = 0;
  while k < plen {
    payload.push(buf[p + k] & 0xFF);
    k = k + 1;
  }
  return Ok(WireFrame{ kind: kind, flags: flags, fields: fields,
                       payload: payload });
}

// ---------------------------------------------------------------------------
// Row streams and query value streams (payload codecs)
// ---------------------------------------------------------------------------

pub fn rows_encode(rows: &Vec[WireRow]) -> Result[Vec[Int], Int] {
  if rows.len() > MAX_WIRE_ROWS { return Err(CODE_LIMIT); }
  var out = Vec[Int].new();
  wire_push_u32(&mut out, rows.len());
  var i = 0;
  while i < rows.len() {
    let r = rows[i];
    if r.kind != ROW_INT && r.kind != ROW_TYPED { return Err(CODE_PROTOCOL); }
    out.push(r.kind);
    wire_push_i64(&mut out, r.key);
    if r.kind == ROW_INT {
      wire_push_u32(&mut out, 8);
      wire_push_i64(&mut out, r.value);
    } else {
      if r.data.len() > MAX_PAYLOAD_BYTES { return Err(CODE_LIMIT); }
      wire_push_u32(&mut out, r.data.len());
      var k = 0;
      while k < r.data.len() {
        out.push(r.data[k] & 0xFF);
        k = k + 1;
      }
    }
    if out.len() > MAX_PAYLOAD_BYTES { return Err(CODE_LIMIT); }
    i = i + 1;
  }
  return Ok(out);
}

pub fn rows_decode(payload: &Vec[Int]) -> Result[Vec[WireRow], Int] {
  if payload.len() < 4 { return Err(CODE_PROTOCOL); }
  let count = wire_read_u32(payload, 0);
  if count > MAX_WIRE_ROWS { return Err(CODE_LIMIT); }
  var rows = Vec[WireRow].new();
  var p = 4;
  var i = 0;
  while i < count {
    if p + 9 > payload.len() { return Err(CODE_PROTOCOL); }
    let kind = payload[p] & 0xFF;
    let key = wire_read_i64(payload, p + 1);
    let vlen = wire_read_u32(payload, p + 9);
    p = p + 13;
    if p + vlen > payload.len() { return Err(CODE_PROTOCOL); }
    var r = WireRow{ kind: kind, key: key, value: 0, data: Vec[Int].new() };
    if kind == ROW_INT {
      if vlen != 8 { return Err(CODE_PROTOCOL); }
      r.value = wire_read_i64(payload, p);
    } else if kind == ROW_TYPED {
      var k = 0;
      while k < vlen {
        r.data.push(payload[p + k] & 0xFF);
        k = k + 1;
      }
    } else {
      return Err(CODE_PROTOCOL);
    }
    rows.push(r);
    p = p + vlen;
    i = i + 1;
  }
  if p != payload.len() { return Err(CODE_PROTOCOL); }
  return Ok(rows);
}

pub fn values_encode(values: &Vec[Int]) -> Result[Vec[Int], Int] {
  if values.len() > MAX_QUERY_ROWS { return Err(CODE_LIMIT); }
  var out = Vec[Int].new();
  wire_push_u32(&mut out, values.len());
  var i = 0;
  while i < values.len() {
    wire_push_i64(&mut out, values[i]);
    i = i + 1;
  }
  return Ok(out);
}

pub fn values_decode(payload: &Vec[Int]) -> Result[Vec[Int], Int] {
  if payload.len() < 4 { return Err(CODE_PROTOCOL); }
  let count = wire_read_u32(payload, 0);
  if count > MAX_QUERY_ROWS { return Err(CODE_LIMIT); }
  if payload.len() != 4 + 8 * count { return Err(CODE_PROTOCOL); }
  var out = Vec[Int].new();
  var i = 0;
  while i < count {
    out.push(wire_read_i64(payload, 4 + 8 * i));
    i = i + 1;
  }
  return Ok(out);
}

// One QUERY condition: op byte + i64 LE value.
pub fn condition_encode(op: Int, value: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  out.push(op & 0xFF);
  wire_push_i64(&mut out, value);
  return out;
}

pub fn condition_decode(data: &Vec[Int]) -> Option[(Int, Int)] {
  if data.len() != 9 { return None; }
  let op = data[0] & 0xFF;
  if op > 5 { return None; }
  let value = wire_read_i64(data, 1);
  return Some((op, value));
}

// ---------------------------------------------------------------------------
// Diagnostics
// ---------------------------------------------------------------------------

pub fn code_name(code: Int) -> Str {
  if code == CODE_OK { return "ok"; }
  if code == CODE_PROTOCOL { return "protocol"; }
  if code == CODE_AUTH_REQUIRED { return "auth-required"; }
  if code == CODE_AUTH_FAILED { return "auth-failed"; }
  if code == CODE_NOT_FOUND { return "not-found"; }
  if code == CODE_DUPLICATE_KEY { return "duplicate-key"; }
  if code == CODE_CONSTRAINT { return "constraint-violation"; }
  if code == CODE_SCHEMA_MISMATCH { return "schema-mismatch"; }
  if code == CODE_STORAGE { return "storage-error"; }
  if code == CODE_CORRUPTION { return "corruption"; }
  if code == CODE_LIMIT { return "limit-exceeded"; }
  if code == CODE_TXN_ACTIVE { return "txn-active"; }
  if code == CODE_NO_TXN { return "no-txn"; }
  if code == CODE_STALE_HANDLE { return "stale-handle"; }
  if code == CODE_CLOSED { return "closed"; }
  if code == CODE_UNSUPPORTED { return "unsupported"; }
  if code == CODE_AUTH_LOCKED { return "auth-locked"; }
  return "internal";
}

pub fn op_name(op: Int) -> Str {
  if op == OP_HELLO { return "HELLO"; }
  if op == OP_AUTH { return "AUTH"; }
  if op == OP_PING { return "PING"; }
  if op == OP_BEGIN { return "BEGIN"; }
  if op == OP_PUT { return "PUT"; }
  if op == OP_GET { return "GET"; }
  if op == OP_RANGE { return "RANGE"; }
  if op == OP_QUERY { return "QUERY"; }
  if op == OP_COMMIT { return "COMMIT"; }
  if op == OP_ABORT { return "ABORT"; }
  if op == OP_CLOSE { return "CLOSE"; }
  if op == OP_DELETE { return "DELETE"; }
  if op == OP_CHECKPOINT { return "CHECKPOINT"; }
  return "UNKNOWN";
}
