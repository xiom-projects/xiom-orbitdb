// XIOM ORBITDB -- byte-IO shim (M1.2 S2 seam).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The block store NEVER calls io.* for block IO directly; it goes through
// these six functions so the stdlib swap is a one-file change when the
// byte-IO/fsync rows land (bus items REL-20261010-1550-orbitdb-3/-4/-5/-6).
//
// Fallbacks today are correct but O(file) per call: the whole file is read,
// spliced and rewritten (io.read_file_bytes / io.write_file_bytes are
// byte-exact). Byte convention: Vec[Int] with elements 0..255 everywhere in
// the storage layer; the conversion to Vec[UInt8] happens only here.
//
// Design: docs/BYTE-PAGE-FORMAT-V2.md section 4.

module xiom.db.storage.byte_io

use xiom.io;
use xiom.db.storage.fault;

// Whole-file byte read as Vec[Int]; None on IO error or short read.
pub fn byteio_read_at(path: Str, offset: Int, len: Int) -> Option[Vec[Int]] {
  if offset < 0 || len < 0 { return None; }
  match io.read_file_bytes(path) {
    Ok(b) => {
      if offset + len > b.len() { return None; }
      var out = Vec[Int].new();
      var i = offset;
      while i < offset + len {
        out.push(b[i] as Int);
        i = i + 1;
      }
      return Some(out);
    }
    Err(_) => { return None; }
  }
}

// Whole-file splice-write at offset; extends with zero bytes past EOF.
// The fault gate (test-only, env-armed) can skip, shorten (torn write) or
// fail the operation before any IO.
pub fn byteio_write_at(path: Str, offset: Int, data: &Vec[Int]) -> Bool {
  if offset < 0 { return false; }
  let fa = fault_gate(0);
  if fa == 1 { return true; }
  if fa == 3 { return false; }
  if fa == 2 {
    var cut = Vec[Int].new();
    let t = fault_partial_tail(data.len());
    var c = 0;
    while c < t && c < data.len() {
      cut.push(data[c]);
      c = c + 1;
    }
    return byteio_write_at_impl(path, offset, &cut);
  }
  return byteio_write_at_impl(path, offset, data);
}

fn byteio_write_at_impl(path: Str, offset: Int, data: &Vec[Int]) -> Bool {
  var existing = Vec[UInt8].new();
  if io.file_exists(path) {
    match io.read_file_bytes(path) {
      Ok(b) => {
        var i = 0;
        while i < b.len() {
          existing.push(b[i]);
          i = i + 1;
        }
      }
      Err(_) => { return false; }
    }
  }
  while existing.len() < offset {
    existing.push(0);
  }
  var i = 0;
  while i < data.len() {
    let at = offset + i;
    let byte = (data[i] & 0xFF) as UInt8;
    if at < existing.len() {
      existing[at] = byte;
    } else {
      existing.push(byte);
    }
    i = i + 1;
  }
  match io.write_file_bytes(path, &existing) {
    Ok(_) => { return true; }
    Err(_) => { return false; }
  }
}

pub fn byteio_append(path: Str, data: &Vec[Int]) -> Bool {
  let size = byteio_file_size(path);
  if size < 0 { return false; }
  return byteio_write_at(path, size, data);
}

// File size in bytes; 0 when the file does not exist, -1 on IO error.
pub fn byteio_file_size(path: Str) -> Int {
  if !io.file_exists(path) { return 0; }
  match io.read_file_bytes(path) {
    Ok(b) => { return b.len(); }
    Err(_) => { return -1; }
  }
}

// ftruncate semantics: cut to len, or extend with zero bytes.
pub fn byteio_truncate(path: Str, len: Int) -> Bool {
  if len < 0 { return false; }
  let fa = fault_gate(0);
  if fa == 1 || fa == 2 { return true; }
  if fa == 3 { return false; }
  var existing = Vec[UInt8].new();
  if io.file_exists(path) {
    match io.read_file_bytes(path) {
      Ok(b) => {
        var i = 0;
        while i < b.len() {
          existing.push(b[i]);
          i = i + 1;
        }
      }
      Err(_) => { return false; }
    }
  }
  while existing.len() > len {
    existing.pop();
  }
  while existing.len() < len {
    existing.push(0);
  }
  match io.write_file_bytes(path, &existing) {
    Ok(_) => { return true; }
    Err(_) => { return false; }
  }
}

// Durability seam. Documented no-op until the stdlib fsync row lands
// (bus REL-20261010-1550-orbitdb-3): the store is process-crash safe today,
// not power-loss honest. The fault gate can make a sync fail (syncfail),
// which the engine maps to a latched failed handle.
pub fn byteio_sync(path: Str) -> Bool {
  let fa = fault_gate(1);
  if fa == 3 { return false; }
  return true;
}
