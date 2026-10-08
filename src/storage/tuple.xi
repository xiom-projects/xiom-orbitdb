// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.db.storage.tuple

// Local error type for tuple encoding -- mirrors xiom.db.error.DbError.
enum DbError {
  NotFound,
  DuplicateKey,
  ConstraintViolation,
  SchemaMismatch,
  StorageError,
  Corruption,
}

pub type DbResult[T] = Result[T, DbError];

// Row / tuple representation and the columnar `ResultSet` container. A `Row` is
// an integer-valued record addressed by a monotonic id. The codec is
// byte-packed v1 (all buffer elements are byte values 0..255):
//
//   0: magic 0xDB    1: version 0x01    2: field_count (1..255)
//   then field_count fields, each: type 0x01 (i64) + 8 bytes little-endian
//   (field 0 is the row id, fields 1.. are the columns)
//
// Minimum encoded size is 12 bytes. The buffer stays `Vec[Int]` until the
// stdlib byte-IO / Vec[UInt8] conversion gap closes (STDLIB-WISHLIST row 5);
// it is byte-true today so CRC32C and on-disk page budgets apply directly.

pub type Row = {
  id: Int;
  data: Vec[Int];
}

pub fn Row.new(id: Int, data: Vec[Int]) -> Row {
  return Row{ id: id, data: data };
}

pub fn Row.get_column(row: &Row, index: Int) -> Option[Int] {
  if index < 0 { return None; }
  if index >= row.data.len() { return None; }
  return Some(row.data[index]);
}

pub fn Row.set_column(row: &mut Row, index: Int, value: Int) -> Bool {
  if index < 0 { return false; }
  if index >= row.data.len() { return false; }
  row.data[index] = value;
  return true;
}

pub fn Row.column_count(row: &Row) -> Int {
  return row.data.len();
}

// --- Tuple codec v1 (byte-packed) ---

pub const TUPLE_MAGIC: Int = 0xDB;
pub const TUPLE_VERSION: Int = 1;
pub const TUPLE_MAX_FIELDS: Int = 255;

// Exported for the snapshot node-page codec in the engine (one LE layout for
// every on-disk codec); keep the byte order in lockstep with TUPLE_VERSION.
pub fn tuple_push_int_le(out: &mut Vec[Int], v: Int) {
  var k = 0;
  while k < 8 {
    out.push((v >> (8 * k)) & 0xFF);
    k = k + 1;
  }
}

// Reconstruct an i64 from 8 little-endian bytes without ever leaving the
// signed 64-bit range (top byte first, seven magnitude bits before the low
// seven bytes; sign applied last). Exported with `tuple_push_int_le`.
pub fn tuple_read_int_le(buf: &Vec[Int], at: Int) -> Int {
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

pub fn tuple_encoded_len(row: &Row) -> Int {
  return 3 + 9 * (row.data.len() + 1);
}

// True when the row's v1 encoding fits the given page payload budget.
pub fn tuple_fits_page(row: &Row, page_size: Int) -> Bool {
  if page_size < 0 { return false; }
  return tuple_encoded_len(row) <= page_size;
}

// Direct byte builder: caller must have validated the field count. Each
// field emits a type byte (0x01 = i64) followed by 8 little-endian bytes.
fn tuple_encode_bytes(row: &Row) -> Vec[Int] {
  var out = Vec[Int].new();
  out.push(TUPLE_MAGIC);
  out.push(TUPLE_VERSION);
  out.push(row.data.len() + 1);
  out.push(0x01);
  tuple_push_int_le(&mut out, row.id);
  var i = 0;
  while i < row.data.len() {
    out.push(0x01);
    tuple_push_int_le(&mut out, row.data[i]);
    i = i + 1;
  }
  return out;
}

// Checked encode: Err(ConstraintViolation) when the row exceeds 255 fields
// (a v1 field_count byte cannot represent it).
pub fn tuple_encode_checked(row: &Row) -> DbResult[Vec[Int]] {
  if row.data.len() + 1 > TUPLE_MAX_FIELDS {
    return Err(DbError.ConstraintViolation);
  }
  return Ok(tuple_encode_bytes(row));
}

// Convenience encode for callers that cannot fail. Returns an EMPTY buffer
// when the row is not encodable (empty is never a valid v1 record: minimum
// size 12); use `tuple_encode_checked` to distinguish the reason. Kept for
// signature compatibility with the C-ORBIT-01 repro bundles.
pub fn tuple_encode(row: &Row) -> Vec[Int] {
  if row.data.len() + 1 > TUPLE_MAX_FIELDS {
    var empty = Vec[Int].new();
    return empty;
  }
  return tuple_encode_bytes(row);
}

// Decode a v1 buffer produced by `tuple_encode_checked`. Validates magic,
// version, field count, exact length and every field type; any violation is
// Err(Corruption) -- no partial rows.
pub fn tuple_decode(buf: &Vec[Int]) -> DbResult[Row] {
  if buf.len() < 12 {
    return Err(DbError.Corruption);
  }
  if buf[0] != TUPLE_MAGIC {
    return Err(DbError.Corruption);
  }
  if buf[1] != TUPLE_VERSION {
    return Err(DbError.Corruption);
  }
  let count = buf[2];
  if count < 1 {
    return Err(DbError.Corruption);
  }
  if buf.len() != 3 + 9 * count {
    return Err(DbError.Corruption);
  }

  var at = 3;
  var i = 0;
  while i < count {
    if buf[at] != 0x01 {
      return Err(DbError.Corruption);
    }
    at = at + 9;
    i = i + 1;
  }

  let id = tuple_read_int_le(buf, 4);
  var data = Vec[Int].new();
  var j = 1;
  while j < count {
    data.push(tuple_read_int_le(buf, 4 + 9 * j));
    j = j + 1;
  }
  return Ok(Row{ id: id, data: data });
}

pub type ResultSet = {
  columns: Vec[Str];
  rows: Vec[Row];
}

pub fn ResultSet.new(columns: Vec[Str]) -> ResultSet {
  var rows = Vec[Row].new();
  return ResultSet{ columns: columns, rows: rows };
}

pub fn ResultSet.add_row(rs: &mut ResultSet, row: Row) {
  rs.rows.push(row);
}

pub fn ResultSet.row_count(rs: &ResultSet) -> Int {
  return rs.rows.len();
}

pub fn ResultSet.column_count(rs: &ResultSet) -> Int {
  return rs.columns.len();
}

pub fn ResultSet.get_row(rs: &ResultSet, index: Int) -> Option[Row] {
  if index < 0 { return None; }
  if index >= rs.rows.len() { return None; }
  var r = rs.rows[index];
  return Some(r);
}
