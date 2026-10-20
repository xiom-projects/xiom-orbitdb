// XIOM ORBITDB -- M3 shard-lock probe: cross-process exclusive open.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Parent: acquires the engine shard lock, proves a second process is refused,
// releases, proves the child can acquire, then proves release-or-die (a child
// that acquires and exits without releasing frees the lock for the parent).
// Child: `--lock-child <db> try|exit-holding <result-file>` (same binary).
module orbitdb_probe_lock

use xiom.io;
use xiom.env;
use xiom.convert;
use xiom.db.engine;
use xiom.os.args;
use xiom.os.process;
use xiom.os.lock;

fn flag_index(a: &Vec[Str], flag: Str) -> Int {
  var i = 0;
  while i < a.len() {
    if a[i] == flag { return i; }
    i = i + 1;
  }
  return -1;
}

fn child_main() -> Int {
  let a = args.args_raw();
  let i = flag_index(&a, "--lock-child");
  if i < 0 || i + 3 >= a.len() { return 2; }
  let path = a[i + 1];
  let mode = a[i + 2];
  let res = a[i + 3];
  let lp = path + ".lock";
  if mode == "try" {
    match lock.file_lock_try(lp) {
      Ok(held) => {
        let _ = io.write_file(res, "acquired");
        lock.file_lock_release(held);
        return 0;
      }
      Err(m) => {
        if m == lock.LOCK_HELD_MSG {
          let _ = io.write_file(res, "held");
        } else {
          let _ = io.write_file(res, "error");
        }
        return 0;
      }
    }
  }
  if mode == "exit-holding" {
    match lock.file_lock_try(lp) {
      Ok(_held) => {
        // Deliberately no release: the OS drops it when this process exits.
        let _ = io.write_file(res, "acquired-exit");
        return 0;
      }
      Err(_) => {
        let _ = io.write_file(res, "error");
        return 0;
      }
    }
  }
  return 3;
}

fn run_child(exe: Str, db: Str, mode: Str, res: Str) -> Str {
  let _ = io.remove_file(res);
  var a = Vec[Str].new();
  a.push("--lock-child");
  a.push(db);
  a.push(mode);
  a.push(res);
  match process.spawn_command(exe, &a) {
    Ok(_) => {}
    Err(_) => { return "spawn-error"; }
  }
  match io.read_file(res) {
    Ok(s) => { return s; }
    Err(_) => { return "no-result"; }
  }
}

fn clean(path: Str) {
  match io.remove_file(path) { Ok(_) => {} Err(_) => {} }
  match io.remove_file(path + ".snap") { Ok(_) => {} Err(_) => {} }
  match io.remove_file(path + ".lock") { Ok(_) => {} Err(_) => {} }
}

pub fn main() -> Int {
  let a = args.args_raw();
  if flag_index(&a, "--lock-child") >= 0 { return child_main(); }

  let path = env.var_or("ORBITDB_LOCK_DB", "orbitdb-lock-test.wal");
  clean(path);
  let _ = io.remove_file("lock-child-1.txt");
  let _ = io.remove_file("lock-child-2.txt");
  let _ = io.remove_file("lock-child-3.txt");

  match db_file_open_locked_checked(path, 4) {
    Ok(db) => {
      var d = db;
      if !db_file_put(&mut d, 1, 10) { return 1; }
    }
    Err(_) => { io.println("lock: initial locked open failed"); return 2; }
  }
  let exe = match process.current_exe_path() {
    Some(p) => p,
    None => { io.println("lock: no exe path"); return 3; }
  };
  let r1 = run_child(exe, path, "try", "lock-child-1.txt");
  if r1 != "held" {
    io.println("lock: child should see HELD, got " + r1);
    return 4;
  }
  match db_file_open_locked_checked(path, 4) {
    Ok(_) => { io.println("lock: second in-process locked open succeeded"); return 5; }
    Err(_) => {}
  }
  if !db_file_unlock(path) {
    io.println("lock: release failed");
    return 6;
  }
  let r2 = run_child(exe, path, "try", "lock-child-2.txt");
  if r2 != "acquired" {
    io.println("lock: child should ACQUIRE after release, got " + r2);
    return 7;
  }
  let r3 = run_child(exe, path, "exit-holding", "lock-child-3.txt");
  if r3 != "acquired-exit" {
    io.println("lock: exit-holding child failed, got " + r3);
    return 8;
  }

  // The OS drops a dead process's lock when its handles close; allow a short
  // bounded window for the child teardown before declaring failure.
  var reopened = false;
  var tries = 0;
  while tries < 20 && !reopened {
    match db_file_open_locked_checked(path, 4) {
      Ok(db) => {
        let v = db_file_get(&db, 1);
        match v {
          Some(x) => { if x != 10 { io.println("lock: value mismatch"); return 9; } }
          None => { io.println("lock: key missing after child exit"); return 10; }
        }
        reopened = true;
      }
      Err(_) => {
        tries = tries + 1;
        if tries < 20 { process.sleep_ms(100); }
      }
    }
  }
  if !reopened {
    io.println("lock: parent refused after child exit (release-or-die broke; tries=20)");
    return 11;
  }
  let _ = db_file_unlock(path);
  clean(path);
  let _ = io.remove_file("lock-child-1.txt");
  let _ = io.remove_file("lock-child-2.txt");
  let _ = io.remove_file("lock-child-3.txt");
  io.println("lock: PASS (held -> refused; release -> child acquired; exit -> released)");
  return 0;
}
