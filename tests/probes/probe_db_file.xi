// XIOM ORBITDB -- file-backed database probe (WAL-before-ack + recovery).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Acceptance for the DBFile facade in src/engine.xi, driven by
// scripts/db_crash_test.ps1/.sh: writer puts N keys through the durable WAL,
// the harness hard-kills it, leaves a torn tail, then reopens (replay) and
// verifies the recovered state, then upserts one more key.
//
// Env:
//   ORBITDB_DB_FILE      WAL segment path (required)
//   ORBITDB_DB_MODE      write | verify | put1          (default: verify)
//   ORBITDB_DB_N         key count for write / verify   (default: 20)
//   ORBITDB_DB_LAST_KEY  optional: key to assert after recovery
//   ORBITDB_DB_LAST_VAL  optional: expected value for LAST_KEY
//
// Exit: 0 = succeeded, 1 = check failed, 2 = bad env.

module orbitdb_probe_db_file

use xiom.io;
use xiom.os.env;
use xiom.convert;
use xiom.convert.parse;
use xiom.db.engine;

fn run_write(path: Str, n: Int) -> Int {
  var db = db_file_open(path, 4);
  var i = 1;
  while i <= n {
    if !db_file_put(&mut db, i, i * 10) {
      io.println("writer: put failed at " + convert.int_to_string(i));
      return 1;
    }
    i = i + 1;
  }
  let flushed = db_file_flush(&mut db);
  if !flushed { io.println("writer: flush failed"); return 1; }
  io.println("writer: put " + convert.int_to_string(n));
  // Hang until the harness hard-kills us (crash simulation).
  var alive = true;
  while alive {
    io.sleep(1000);
  }
  return 0;
}

fn run_verify(path: Str, n: Int) -> Int {
  var db = db_file_open(path, 4);
  let size = db_file_size(&db);
  io.println("verify: recovered=" + convert.int_to_string(size) + " lsn=" + convert.int_to_string(db_file_last_lsn(&db)));
  if size != n {
    io.println("verify: expected " + convert.int_to_string(n) + " got " + convert.int_to_string(size));
    return 1;
  }
  let v1 = db_file_get(&db, 1);
  match v1 {
    None => { io.println("verify: key 1 missing"); return 1; }
    Some(x) => { if x != 10 { io.println("verify: key 1 wrong"); return 1; } }
  }
  let lk = env.var_or("ORBITDB_DB_LAST_KEY", "");
  if lk == "" {
    // Sequential phase (keys 1..N): the Nth key must be N*10.
    let vn = db_file_get(&db, n);
    match vn {
      None => { io.println("verify: key N missing"); return 1; }
      Some(x) => { if x != n * 10 { io.println("verify: key N wrong"); return 1; } }
    }
  }
  if lk != "" {
    match parse.parse_int(lk) {
      Ok(k) => {
        match parse.parse_int(env.var_or("ORBITDB_DB_LAST_VAL", "0")) {
          Ok(want) => {
            let got = db_file_get(&db, k);
            match got {
              None => { io.println("verify: last key missing"); return 1; }
              Some(v) => { if v != want { io.println("verify: last value wrong"); return 1; } }
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
  let path = env.var_or("ORBITDB_DB_FILE", "");
  if path == "" {
    io.println("probe_db_file: ORBITDB_DB_FILE not set");
    return 2;
  }
  let mode = env.var_or("ORBITDB_DB_MODE", "verify");
  var n = 20;
  match parse.parse_int(env.var_or("ORBITDB_DB_N", "20")) {
    Ok(v) => { n = v; }
    Err(_) => { n = 20; }
  }

  if mode == "write" {
    return run_write(path, n);
  }
  if mode == "put1" {
    var db = db_file_open(path, 4);
    if !db_file_put(&mut db, 9999, 99990) {
      io.println("put1: failed");
      return 1;
    }
    let flushed = db_file_flush(&mut db);
    if !flushed { io.println("put1: flush failed"); return 1; }
    io.println("put1: OK");
    return 0;
  }
  return run_verify(path, n);
}
