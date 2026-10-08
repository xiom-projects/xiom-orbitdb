// XIOM ORBITDB -- durable WAL segment probe (critical primitive).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Bootstraps the Phase-2 seam (append-only WAL segment file) and is the
// subject of scripts/crash_test.ps1/.sh: the writer appends N text records,
// the harness hard-kills it, leaves a torn tail, then reopens and replays.
//
// Record format (one per line):  ts|op|key|value   (op: 1=insert)
// Torn or malformed tails are skipped on read (record healing).
//
// Env:
//   ORBITDB_WAL_FILE      path to the segment file (required)
//   ORBITDB_WAL_MODE      write | verify | append1        (default: verify)
//   ORBITDB_WAL_N         record count for write / verify (default: 20)
//   ORBITDB_WAL_LAST_KEY  optional: key to assert after replay
//   ORBITDB_WAL_LAST_VAL  optional: expected value for LAST_KEY
//
// Exit: 0 = mode succeeded, 1 = check failed, 2 = bad env/read error.

module orbitdb_probe_wal_file

use xiom.io;
use xiom.os.env;
use xiom.convert;
use xiom.convert.parse;
use xiom.string;
use xiom.string.split;
use xiom.string.trim;
use xiom.db.engine;

type Replay = {
  applied: Int;
  error: Int;
  tree: BTree;
}

// Torn-tail healing: if the segment does not end with a newline (crash
// mid-record), append one before the next record so the partial tail stays
// its own skipped line instead of merging with the new record.
fn heal_tail(path: Str) {
  let r = io.read_file(path);
  match r {
    Ok(content) => {
      if content != "" {
        if !str_ends_with(content, "\n") {
          let _ = io.append_line(path, "");
        }
      }
    }
    Err(_) => {}
  }
}

fn append_record(path: Str, ts: Int, op: Int, key: Int, value: Int) -> Bool {
  heal_tail(path);
  var line = convert.int_to_string(ts) + "|" + convert.int_to_string(op) + "|"
           + convert.int_to_string(key) + "|" + convert.int_to_string(value);
  let r = io.append_line(path, line);
  match r {
    Ok(_) => return true,
    Err(_) => return false,
  }
}

// Replay all well-formed records into a fresh tree. Malformed lines (torn
// tail) are skipped. error=1 on read failure.
fn replay_file(path: Str) -> Replay {
  let lines_r = io.read_file_lines(path);
  match lines_r {
    Err(_) => {
      var t = btree_new(4);
      return Replay{ applied: 0, error: 1, tree: t };
    }
    Ok(lines) => {
      // C-ORBIT-01 workaround: rebind the match-bound payload of a
      // cross-module generic Result through an explicitly typed local;
      // otherwise elements read as raw addresses (docs/repro/ok-method-receiver).
      let all: Vec[Str] = lines;
      var tree = btree_new(4);
      var applied = 0;
      var i = 0;
      while i < all.len() {
        // Trim CR/nl so CRLF-produced segments replay identically.
        let line = trim.str_trim(all[i]);
        if line != "" {
          let parts = split.str_split(line, "|");
          if parts.len() == 4 {
            match parse.parse_int(parts[2]) {
              Ok(k) => {
                match parse.parse_int(parts[3]) {
                  Ok(v) => {
                    btree_insert(&mut tree, k, v);
                    applied = applied + 1;
                  }
                  Err(_) => {}
                }
              }
              Err(_) => {}
            }
          }
        }
        i = i + 1;
      }
      return Replay{ applied: applied, error: 0, tree: tree };
    }
  }
}

fn run_write(path: Str, n: Int) -> Int {
  var i = 1;
  while i <= n {
    let ok = append_record(path, i, 1, i, i * 10);
    if !ok { io.println("writer: append failed"); return 1; }
    i = i + 1;
  }
  io.println("writer: wrote " + convert.int_to_string(n));
  // Hang until the harness hard-kills us (crash simulation). io.sleep is a
  // runtime call, so the loop cannot be optimized away.
  var alive = true;
  while alive {
    io.sleep(1000);
  }
  return 0;
}

fn run_verify(path: Str, n: Int) -> Int {
  let res = replay_file(path);
  if res.error != 0 { return 2; }
  io.println("verify: applied=" + convert.int_to_string(res.applied));
  if res.applied != n {
    io.println("verify: expected " + convert.int_to_string(n) + " got " + convert.int_to_string(res.applied));
    return 1;
  }
  let v1 = btree_search(&res.tree, 1);
  match v1 {
    None => { io.println("verify: key 1 missing"); return 1; }
    Some(x) => { if x != 10 { io.println("verify: key 1 wrong"); return 1; } }
  }
  // Optional last-record assertion.
  let lk = env.var_or("ORBITDB_WAL_LAST_KEY", "");
  if lk != "" {
    match parse.parse_int(lk) {
      Ok(k) => {
        match parse.parse_int(env.var_or("ORBITDB_WAL_LAST_VAL", "0")) {
          Ok(want) => {
            let got = btree_search(&res.tree, k);
            match got {
              None => { io.println("verify: last key missing"); return 1; }
              Some(v) => {
                if v != want { io.println("verify: last value wrong"); return 1; }
              }
            }
          }
          Err(_) => { return 2; }
        }
      }
      Err(_) => { return 2; }
    }
  }
  io.println("verify: OK n=" + convert.int_to_string(n));
  return 0;
}

fn main() -> Int {
  let path = env.var_or("ORBITDB_WAL_FILE", "");
  if path == "" {
    io.println("probe_wal_file: ORBITDB_WAL_FILE not set");
    return 2;
  }
  let mode = env.var_or("ORBITDB_WAL_MODE", "verify");
  var n = 20;
  match parse.parse_int(env.var_or("ORBITDB_WAL_N", "20")) {
    Ok(v) => { n = v; }
    Err(_) => { n = 20; }
  }

  if mode == "write" {
    return run_write(path, n);
  }
  if mode == "append1" {
    let ok = append_record(path, 9999, 1, 9999, 99990);
    if !ok { io.println("append1: failed"); return 1; }
    io.println("append1: OK");
    return 0;
  }
  return run_verify(path, n);
}
