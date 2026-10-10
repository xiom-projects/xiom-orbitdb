// XIOM ORBITDB -- durable WAL segment (reference implementation).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The disk half of the future `xiom.wal` package (packages-lane decision
// 2026-10-08: xiom.wal ships standalone; durable's `src/wal/*` reconciles
// into it). This module keeps `xiom.durable.wal.wal_record`'s vocabulary
// (LSN, full op-kind set, tagged payload) and adds the crash-proven disk
// segment from `tests/probes/probe_wal_file.xi`:
//
//   * append heals a missing trailing newline first (a torn tail must not
//     merge with the next record);
//   * malformed / torn tail lines are skipped on replay (record healing);
//   * LSNs are strictly monotonic; `wal_file_open` resumes from the log.
//
// Durability honesty: `wal_file_flush` is a no-op until the runtime gains an
// fsync/FlushFileBuffers wrapper (STDLIB-WISHLIST-ORBITDB.md). "Durable"
// today means OS write-back + torn-tail healing, not power-loss durability.
//
// Codec v1 (one record per line, UTF-8 text):
//   lsn|op|key|value|timestamp[|p0,p1,...]
// op codes: 1 Insert, 2 Update, 3 Delete, 4 SegmentSeal, 5 ManifestUpdate,
//           6 Checkpoint, 7 SnapshotMarker.

module xiom.db.wal_file

use xiom.io;
use xiom.convert;
use xiom.convert.parse;
use xiom.string;
use xiom.string.split;
use xiom.string.trim;

pub enum WALOpKind {
  Insert,
  Update,
  Delete,
  SegmentSeal,
  ManifestUpdate,
  Checkpoint,
  SnapshotMarker,
  BeginTxn,
  CommitTxn,
  AbortTxn,
}

pub type WALRecord = {
  lsn: Int;
  op: WALOpKind;
  key: Int;
  value: Int;
  payload: Vec[Int];
  timestamp: Int;
}

pub type WALFile = {
  path: Str;
  next_lsn: Int;
  heal_needed: Bool;
}

pub fn wal_op_code(op: WALOpKind) -> Int {
  match op {
    WALOpKind.Insert => { return 1; }
    WALOpKind.Update => { return 2; }
    WALOpKind.Delete => { return 3; }
    WALOpKind.SegmentSeal => { return 4; }
    WALOpKind.ManifestUpdate => { return 5; }
    WALOpKind.Checkpoint => { return 6; }
    WALOpKind.SnapshotMarker => { return 7; }
    WALOpKind.BeginTxn => { return 8; }
    WALOpKind.CommitTxn => { return 9; }
    WALOpKind.AbortTxn => { return 10; }
  }
}

// C-ORBIT-04 (fixed in v0.64.2/m225 for same-catalog twins): variants stay
// qualified here because a same-named twin from ANOTHER package in the
// program (`xiom.wal`'s `WalOpKind` -- the registry extraction of this very
// module) resolves cross-package bare variants to the wrong enum on v0.64.2
// (see the xiom.wal consumer pass in docs/PACKAGE-WISHLIST-ORBITDB.md).
// History: COMPILER-FINDINGS-ORBITDB.md.
pub fn wal_op_from_code(code: Int) -> WALOpKind {
  if code == 2 { return WALOpKind.Update; }
  if code == 3 { return WALOpKind.Delete; }
  if code == 4 { return WALOpKind.SegmentSeal; }
  if code == 5 { return WALOpKind.ManifestUpdate; }
  if code == 6 { return WALOpKind.Checkpoint; }
  if code == 7 { return WALOpKind.SnapshotMarker; }
  if code == 8 { return WALOpKind.BeginTxn; }
  if code == 9 { return WALOpKind.CommitTxn; }
  if code == 10 { return WALOpKind.AbortTxn; }
  return WALOpKind.Insert;
}

// True for record kinds that mutate an index (replay applies these).
pub fn wal_op_is_write(op: WALOpKind) -> Bool {
  match op {
    WALOpKind.Insert => { return true; }
    WALOpKind.Update => { return true; }
    WALOpKind.Delete => { return true; }
    WALOpKind.SegmentSeal => { return false; }
    WALOpKind.ManifestUpdate => { return false; }
    WALOpKind.Checkpoint => { return false; }
    WALOpKind.SnapshotMarker => { return false; }
    WALOpKind.BeginTxn => { return false; }
    WALOpKind.CommitTxn => { return false; }
    WALOpKind.AbortTxn => { return false; }
  }
}

// Torn-tail healing: if the segment does not end with a newline (crash
// mid-record), append one before the next record so the partial tail stays
// its own skipped line instead of merging with the new record.
pub fn wal_file_heal_tail(path: Str) -> Bool {
  let r = io.read_file(path);
  match r {
    Ok(content) => {
      if content == "" { return true; }
      if str_ends_with(content, "\n") { return true; }
      let wrote = io.append_line(path, "");
      match wrote {
        Ok(_) => { return true; }
        Err(_) => { return false; }
      }
    }
    Err(_) => { return true; } // missing file: nothing to heal
  }
}

fn wal_file_append_line(w: &mut WALFile, op: WALOpKind, key: Int, value: Int,
                        payload: &Vec[Int], timestamp: Int) -> Int {
  // Torn-tail heal only when the handle knows the previous write left one
  // (bench: unconditional heal read the whole segment per append -> 626 ops/s;
  // state-tracked heal removes the O(n) rescan).
  if w.heal_needed {
    let _ = wal_file_heal_tail(w.path);
    w.heal_needed = false;
  }
  var line = convert.int_to_string(w.next_lsn) + "|" + convert.int_to_string(wal_op_code(op))
           + "|" + convert.int_to_string(key) + "|" + convert.int_to_string(value)
           + "|" + convert.int_to_string(timestamp);
  if payload.len() > 0 {
    line = line + "|";
    var i = 0;
    while i < payload.len() {
      if i > 0 { line = line + ","; }
      line = line + convert.int_to_string(payload[i]);
      i = i + 1;
    }
  }
  let wrote = io.append_line(w.path, line);
  match wrote {
    Ok(_) => {
      let assigned = w.next_lsn;
      w.next_lsn = w.next_lsn + 1;
      return assigned;
    }
    Err(_) => { return -1; }
  }
}

// Append a record and return its LSN (-1 on write failure).
pub fn wal_file_append(w: &mut WALFile, op: WALOpKind, key: Int, value: Int) -> Int {
  var empty = Vec[Int].new();
  return wal_file_append_line(w, op, key, value, &empty, 0);
}

// Append with an explicit payload (tagged extension; payload[0] = subtype).
pub fn wal_file_append_tagged(w: &mut WALFile, op: WALOpKind, key: Int, value: Int,
                              payload: Vec[Int], timestamp: Int) -> Int {
  return wal_file_append_line(w, op, key, value, &payload, timestamp);
}

// Durability seam. No-op success until the runtime exposes fsync
// (STDLIB-WISHLIST-ORBITDB.md row 1); keep the call site in place so the
// swap is one line when it lands.
pub fn wal_file_flush(w: &mut WALFile) -> Bool {
  return true;
}

pub fn wal_file_next_lsn(w: &WALFile) -> Int {
  return w.next_lsn;
}

// Open (or create) a segment, resuming next_lsn from the last valid record.
// Any torn tail from a previous crash is healed here, once.
pub fn wal_file_open(path: Str) -> WALFile {
  var next = 1;
  let records = wal_file_replay(path);
  if records.len() > 0 {
    next = records[records.len() - 1].lsn + 1;
  }
  let _ = wal_file_heal_tail(path);
  return WALFile{ path: path, next_lsn: next, heal_needed: false };
}

fn parse_payload(s: Str) -> Vec[Int] {
  var out = Vec[Int].new();
  let parts = split.str_split(s, ",");
  var i = 0;
  while i < parts.len() {
    match parse.parse_int(trim.str_trim(parts[i])) {
      Ok(v) => { out.push(v); }
      Err(_) => {}
    }
    i = i + 1;
  }
  return out;
}

// Replay every well-formed record in file order. Torn/malformed lines
// (including a partial tail) are skipped; no diagnostics from this layer --
// callers compare counts (see scripts/crash_test.*).
pub fn wal_file_replay(path: Str) -> Vec[WALRecord] {
  var out = Vec[WALRecord].new();
  let lines_r = io.read_file_lines(path);
  match lines_r {
    Err(_) => { return out; }
    Ok(lines) => {
      var i = 0;
      while i < lines.len() {
        let line = trim.str_trim(lines[i]);
        if line != "" {
          let parts = split.str_split(line, "|");
          if parts.len() >= 5 {
            var lsn = 0;
            var op_code = 0;
            var key = 0;
            var value = 0;
            var ts = 0;
            var ok = true;
            match parse.parse_int(parts[0]) {
              Ok(v) => { lsn = v; }
              Err(_) => { ok = false; }
            }
            match parse.parse_int(parts[1]) {
              Ok(v) => { op_code = v; }
              Err(_) => { ok = false; }
            }
            match parse.parse_int(parts[2]) {
              Ok(v) => { key = v; }
              Err(_) => { ok = false; }
            }
            match parse.parse_int(parts[3]) {
              Ok(v) => { value = v; }
              Err(_) => { ok = false; }
            }
            match parse.parse_int(parts[4]) {
              Ok(v) => { ts = v; }
              Err(_) => { ok = false; }
            }
            if ok {
              var payload = Vec[Int].new();
              if parts.len() >= 6 { payload = parse_payload(parts[5]); }
              out.push(WALRecord{
                lsn: lsn, op: wal_op_from_code(op_code), key: key, value: value,
                payload: payload, timestamp: ts,
              });
            }
          }
        }
        i = i + 1;
      }
      return out;
    }
  }
}

pub fn wal_file_len(path: Str) -> Int {
  return wal_file_replay(path).len();
}

pub fn wal_file_last_lsn(path: Str) -> Int {
  let records = wal_file_replay(path);
  if records.len() == 0 { return 0; }
  return records[records.len() - 1].lsn;
}

// Checkpoint/truncate seam: rewrite the segment keeping every record with
// lsn >= from_lsn. Uses temp + rename so a crash mid-rewrite never destroys
// the old segment (io.rename maps to MoveFileEx REPLACE_EXISTING / rename(2)).
pub fn wal_file_truncate(path: Str, from_lsn: Int) -> Bool {
  let records = wal_file_replay(path);
  var tmp = path + ".tmp";
  let removed = io.remove_file(tmp);
  // best-effort remove (ignore result)
  var body = "";
  var i = 0;
  while i < records.len() {
    let rec = records[i];
    if rec.lsn >= from_lsn {
      body = body + convert.int_to_string(rec.lsn) + "|" + convert.int_to_string(wal_op_code(rec.op))
           + "|" + convert.int_to_string(rec.key) + "|" + convert.int_to_string(rec.value)
           + "|" + convert.int_to_string(rec.timestamp);
      // Payload must survive the rewrite (the Checkpoint record kept by a
      // checkpoint truncation carries [generation, node_count, order]; dropping
      // it would silently mutate a kept record).
      if rec.payload.len() > 0 {
        body = body + "|";
        var j = 0;
        while j < rec.payload.len() {
          if j > 0 { body = body + ","; }
          body = body + convert.int_to_string(rec.payload[j]);
          j = j + 1;
        }
      }
      body = body + "\n";
    }
    i = i + 1;
  }
  let wrote = io.write_file(tmp, body);
  match wrote {
    Ok(_) => {}
    Err(_) => { return false; }
  }
  let moved = io.rename(tmp, path);
  match moved {
    Ok(_) => { return true; }
    Err(_) => { return false; }
  }
}
