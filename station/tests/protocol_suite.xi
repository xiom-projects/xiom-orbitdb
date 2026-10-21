// XIOM ORBITDB Station -- ORBITWIRE v1 protocol conformance suite.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure codec checks: frame KAT, CRC parity with the engine page checksum,
// typed fields, row/value streams, limits and corruption rejection. Network
// behavior lives in loopback_suite.xi.
//
// NOTE (C-ORBIT-14, v0.64.8): never bind a Vec with `let/var x = match ...`
// -- the initializer form corrupts the Vec length. All decode helpers below
// declare + assign instead.
//
// Summary line (consumed by scripts/station_suite.*):
//   XIOM Station Conformance [protocol]: P/T passed
module orbitdb_station_protocol_suite

use xiom.io;
use xiom.db.storage.page;
use xiom.station.protocol;

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

fn empty_frame() -> WireFrame {
  return WireFrame{ kind: 0, flags: 0, fields: Vec[WireField].new(),
                    payload: Vec[Int].new() };
}

fn enc_frame(kind: Int, fs: &Vec[WireField], p: &Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  match frame_encode(kind, fs, p) {
    Ok(b) => { out = b; }
    Err(_) => {}
  }
  return out;
}

fn dec_frame(buf: &Vec[Int]) -> WireFrame {
  var f = empty_frame();
  let total = frame_peek_total(buf, 0);
  if total <= 0 { return f; }
  match frame_decode(buf, 0, total) {
    Ok(x) => { f = x; }
    Err(_) => {}
  }
  return f;
}

fn enc_rows(rows: &Vec[WireRow]) -> Vec[Int] {
  var out = Vec[Int].new();
  match rows_encode(rows) {
    Ok(b) => { out = b; }
    Err(_) => {}
  }
  return out;
}

fn dec_rows(p: &Vec[Int]) -> Vec[WireRow] {
  var out = Vec[WireRow].new();
  match rows_decode(p) {
    Ok(r) => { out = r; }
    Err(_) => {}
  }
  return out;
}

fn enc_values(vals: &Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  match values_encode(vals) {
    Ok(b) => { out = b; }
    Err(_) => {}
  }
  return out;
}

fn dec_values(p: &Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  match values_decode(p) {
    Ok(v) => { out = v; }
    Err(_) => {}
  }
  return out;
}

fn got_bytes(fs: &Vec[WireField], tag: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  match wire_get_bytes(fs, tag) {
    Some(b) => { out = b; }
    None => {}
  }
  return out;
}

fn field_int(fs: &Vec[WireField], tag: Int, want: Int) -> Bool {
  match wire_get_int(fs, tag) {
    None => { return false; }
    Some(v) => { return v == want; }
  }
}

fn field_bool(fs: &Vec[WireField], tag: Int, want: Bool) -> Bool {
  match wire_get_bool(fs, tag) {
    None => { return false; }
    Some(v) => { return v == want; }
  }
}

fn field_text(fs: &Vec[WireField], tag: Int, want: Str) -> Bool {
  match wire_get_text(fs, tag) {
    None => { return false; }
    Some(v) => { return v == want; }
  }
}

fn decode_ok(buf: &Vec[Int]) -> Bool {
  let total = frame_peek_total(buf, 0);
  if total <= 0 { return false; }
  match frame_decode(buf, 0, total) {
    Ok(_) => { return true; }
    Err(_) => { return false; }
  }
}

fn encode_is_limit(fields: &Vec[WireField]) -> Bool {
  match frame_encode(KIND_REQUEST, fields, &Vec[Int].new()) {
    Ok(_) => { return false; }
    Err(e) => { return e == CODE_LIMIT; }
  }
}

fn rows_are_bad(p: &Vec[Int]) -> Bool {
  match rows_decode(p) {
    Ok(_) => { return false; }
    Err(_) => { return true; }
  }
}

fn values_are_bad(p: &Vec[Int]) -> Bool {
  match values_decode(p) {
    Ok(_) => { return false; }
    Err(_) => { return true; }
  }
}

fn main() -> Int {
  io.println("XIOM Station Conformance [protocol]");

  // -- frame KAT: exact layout and CRC coverage ---------------------------
  var kfields = Vec[WireField].new();
  kfields.push(wire_int(TAG_REQUEST_ID, 7));
  kfields.push(wire_int(TAG_OP, OP_PING));
  kfields.push(wire_int(TAG_NONCE, 42));
  var kpayload = Vec[Int].new();
  kpayload.push(1);
  kpayload.push(2);
  kpayload.push(3);
  var kenc = enc_frame(KIND_REQUEST, &kfields, &kpayload);
  check(kenc.len() == 61, "KAT: encoded length 61");
  check(kenc.len() == 61 && kenc[0] == 0x4F && kenc[1] == 0x42 &&
        kenc[2] == 0x57 && kenc[3] == 0x31, "KAT: magic OBW1");
  check(kenc.len() == 61 && kenc[4] == 1 && kenc[5] == KIND_REQUEST &&
        kenc[6] == 0 && kenc[7] == 0, "KAT: version/kind/flags");
  check(kenc.len() == 61 && kenc[8] == 38 && kenc[9] == 0 &&
        kenc[10] == 0 && kenc[11] == 0, "KAT: header length 38");
  check(kenc.len() == 61 && kenc[12] == 3 && kenc[13] == 0,
        "KAT: payload length 3");
  check(frame_peek_total(&kenc, 0) == 61, "KAT: peek total 61");
  var kdec = dec_frame(&kenc);
  check(kdec.kind == KIND_REQUEST, "KAT: decoded kind");
  check(kdec.fields.len() == 3, "KAT: decoded field count");
  check(field_int(&kdec.fields, TAG_REQUEST_ID, 7), "KAT: request id");
  check(field_int(&kdec.fields, TAG_OP, OP_PING), "KAT: op");
  check(field_int(&kdec.fields, TAG_NONCE, 42), "KAT: nonce");
  check(kdec.payload.len() == 3 && kdec.payload[0] == 1 &&
        kdec.payload[2] == 3, "KAT: payload bytes");

  // -- CRC parity with the engine page checksum --------------------------
  var crc_in = Vec[Int].new();
  var ci = 0;
  while ci < 97 {
    crc_in.push((ci * 37 + 11) % 256);
    ci = ci + 1;
  }
  check(wire_crc32c_range(&crc_in, 0, crc_in.len()) ==
        page_compute_checksum(&crc_in),
        "CRC32C parity with engine page checksum");
  check(wire_crc32c_range(&crc_in, 3, 90) ==
        wire_crc32c_range(&crc_in, 3, 90),
        "CRC32C range deterministic");

  // -- typed field roundtrip --------------------------------------------
  var tfields = Vec[WireField].new();
  tfields.push(wire_int(TAG_KEY, -5));
  tfields.push(wire_bool(TAG_AUTH_REQUIRED, true));
  tfields.push(wire_bool(TAG_HAS_BOUNDS, false));
  tfields.push(wire_text(TAG_MESSAGE, "hello wire"));
  var raw = Vec[Int].new();
  raw.push(0);
  raw.push(255);
  raw.push(128);
  raw.push(7);
  tfields.push(wire_bytes(TAG_TOKEN, &raw));
  var no_payload = Vec[Int].new();
  var tenc = enc_frame(KIND_RESPONSE, &tfields, &no_payload);
  var tdec = dec_frame(&tenc);
  check(field_int(&tdec.fields, TAG_KEY, -5), "field: negative int");
  check(field_bool(&tdec.fields, TAG_AUTH_REQUIRED, true), "field: bool true");
  check(field_bool(&tdec.fields, TAG_HAS_BOUNDS, false), "field: bool false");
  check(field_text(&tdec.fields, TAG_MESSAGE, "hello wire"),
        "field: text roundtrip");
  var got_raw = got_bytes(&tdec.fields, TAG_TOKEN);
  check(got_raw.len() == 4 && got_raw[0] == 0 && got_raw[1] == 255 &&
        got_raw[2] == 128 && got_raw[3] == 7, "field: opaque bytes");

  // -- corruption and limit rejection ------------------------------------
  var bad = Vec[Int].new();
  var bi = 0;
  while bi < kenc.len() {
    bad.push(kenc[bi]);
    bi = bi + 1;
  }
  bad[0] = 0x58;
  check(frame_peek_total(&bad, 0) == -1, "reject: bad magic");
  bad[0] = 0x4F;
  bad[4] = 9;
  check(frame_peek_total(&bad, 0) == -2, "reject: bad version");
  bad[4] = 1;
  bad[20] = (bad[20] + 1) % 256;
  check(!decode_ok(&bad), "reject: corrupted body/CRC");
  var shortbuf = Vec[Int].new();
  shortbuf.push(0x4F);
  shortbuf.push(0x42);
  shortbuf.push(0x57);
  check(frame_peek_total(&shortbuf, 0) == 0, "need-more: short prefix");
  var over = Vec[Int].new();
  over.push(0x4F);
  over.push(0x42);
  over.push(0x57);
  over.push(0x31);
  over.push(1);
  over.push(KIND_REQUEST);
  over.push(0);
  over.push(0);
  over.push(1); // hlen = 0x00010001 = 65537 > MAX_HEADER_BYTES
  over.push(0);
  over.push(1);
  over.push(0);
  over.push(0);
  over.push(0);
  over.push(0);
  over.push(0);
  check(frame_peek_total(&over, 0) == -3, "reject: oversized header limit");

  var many = Vec[WireField].new();
  var mi = 0;
  while mi <= MAX_FIELDS {
    many.push(wire_int(TAG_NONCE, mi));
    mi = mi + 1;
  }
  check(encode_is_limit(&many), "reject: too many fields");

  // -- conditions --------------------------------------------------------
  var cenc = condition_encode(4, 1234567890123);
  var cop = -1;
  var cval = 0;
  match condition_decode(&cenc) {
    None => {}
    Some(c) => {
      match c {
        (op, value) => {
          cop = op;
          cval = value;
        }
      }
    }
  }
  check(cop == 4 && cval == 1234567890123, "condition: op + i64");
  var cbadt = Vec[Int].new();
  cbadt.push(9);
  cbadt.push(0);
  cbadt.push(0);
  var cbok = true;
  match condition_decode(&cbadt) {
    None => {}
    Some(_) => { cbok = false; }
  }
  check(cbok, "condition: rejects unknown op");

  // -- row streams: int + typed, exact roundtrip -------------------------
  var rows = Vec[WireRow].new();
  rows.push(WireRow{ kind: ROW_INT, key: 2, value: 20, data: Vec[Int].new() });
  var rowdata = Vec[Int].new();
  rowdata.push(1);
  rowdata.push(2);
  rowdata.push(250);
  rowdata.push(0);
  rows.push(WireRow{ kind: ROW_TYPED, key: 9, value: 9, data: rowdata });
  var renc = enc_rows(&rows);
  var rdec = dec_rows(&renc);
  check(rdec.len() == 2, "rows: count");
  check(rdec.len() == 2 && rdec[0].kind == ROW_INT && rdec[0].key == 2 &&
        rdec[0].value == 20, "rows: int row");
  check(rdec.len() == 2 && rdec[1].kind == ROW_TYPED && rdec[1].key == 9 &&
        rdec[1].data.len() == 4 && rdec[1].data[2] == 250,
        "rows: typed row bytes");
  var rt = Vec[Int].new();
  rt.push(1);
  rt.push(0);
  rt.push(0);
  check(rows_are_bad(&rt), "rows: reject truncated payload");

  // -- value streams (QUERY) --------------------------------------------
  var vals = Vec[Int].new();
  vals.push(-7);
  vals.push(0);
  vals.push(9223372036854775807);
  var venc = enc_values(&vals);
  var vdec = dec_values(&venc);
  check(vdec.len() == 3 && vdec[0] == -7 && vdec[1] == 0 &&
        vdec[2] == 9223372036854775807, "values: i64 extremes");
  var vshort = Vec[Int].new();
  vshort.push(2);
  vshort.push(0);
  vshort.push(0);
  vshort.push(0);
  check(values_are_bad(&vshort), "values: reject short count");

  io.println("XIOM Station Conformance [protocol]: " +
             g_pass.to_str() + "/" + g_total.to_str() + " passed");
  if g_pass == g_total { return 0; }
  return 1;
}
