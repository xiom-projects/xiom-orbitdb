// XIOM ORBITDB -- M1.1b A6 memory soak (chunked build + paged reopen).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Builds the DB in two phases so the measured steady state is the PAGED
// store, not the resident first-build arena:
//   phase 1: `FIRST` keys in a fresh resident handle -> checkpoint
//   reopen : the v2 snapshot loads lazily (paged)
//   phase 2: insert the rest in `CHUNK` blocks, checkpointing each
//            (dirty spill + incremental checkpoint + occasional GC)
// Then samples keys and reports node/cache/pager counters. Peak RSS is
// sampled externally (Get-Process / /usr/bin/time -v) -- XIOM has no RSS API.
//
// Env: ORBITDB_SOAK_PATH (orbitdb-soak.wal), ORBITDB_SOAK_KEYS (200000),
//      ORBITDB_SOAK_FIRST (20000), ORBITDB_SOAK_CHUNK (50000),
//      ORBITDB_SOAK_KEEP=1 (leave the files for inspection)
module orbitdb_probe_soak

use xiom.io;
use xiom.env;
use xiom.convert;
use xiom.db.engine;
use xiom.db.index.btree;

fn env_int(name: Str, fallback: Int) -> Int {
  let raw = env.var_or(name, "");
  if raw.len() == 0 { return fallback; }
  match io.parse_int(raw) {
    Ok(v) => { return v; }
    Err(_) => { return fallback; }
  }
}

fn remove_all(path: Str) {
  match io.remove_file(path) { Ok(_) => {} Err(_) => {} }
  match io.remove_file(path + ".snap") { Ok(_) => {} Err(_) => {} }
  match io.remove_file(path + ".snap.rw") { Ok(_) => {} Err(_) => {} }
}

pub fn main() -> Int {
  let path = env.var_or("ORBITDB_SOAK_PATH", "orbitdb-soak.wal");
  let want_keys = env_int("ORBITDB_SOAK_KEYS", 200000);
  var first = env_int("ORBITDB_SOAK_FIRST", 20000);
  let chunk = env_int("ORBITDB_SOAK_CHUNK", 50000);
  let keep = env.var_or("ORBITDB_SOAK_KEEP", "0") == "1";
  if first > want_keys { first = want_keys; }
  if first < 1 { first = 1; }
  remove_all(path);
  io.println("soak: start keys=" + convert.int_to_string(want_keys)
    + " first=" + convert.int_to_string(first)
    + " chunk=" + convert.int_to_string(chunk));

  var t0 = io.time_now();
  var db = db_file_open_cfg(path, 4, 2);
  let _ = db_file_set_durability(&mut db, 0);
  var i = 1;
  while i <= first {
    if !db_file_put(&mut db, i, i * 10) { return 1; }
    i = i + 1;
  }
  if db_file_checkpoint(&mut db) < 0 { return 2; }
  io.println("soak: phase1 keys=" + convert.int_to_string(first)
    + " size=" + convert.int_to_string(db_file_size(&db))
    + " nodes=" + convert.int_to_string(db.tree.store.count)
    + " ms=" + convert.int_to_string(io.time_now() - t0));

  // Reopen: v2 is lazily loaded, so phase 2 runs with the bounded pager.
  db = db_file_open(path, 4);
  let _ = db_file_set_durability(&mut db, 0);
  if !db.tree.store.paged { return 3; }
  io.println("soak: paged reopen nodes=" + convert.int_to_string(db.tree.store.count)
    + " cache=" + convert.int_to_string(db.tree.store.frames.len())
    + " blocks=" + convert.int_to_string(db.tree.store.bs.block_count));

  var done = first;
  while done < want_keys {
    var end = done + chunk;
    if end > want_keys { end = want_keys; }
    i = done + 1;
    while i <= end {
      if !db_file_put(&mut db, i, i * 10) { return 4; }
      i = i + 1;
    }
    io.println("soak: pre-ckpt keys=" + convert.int_to_string(end)
      + " count=" + convert.int_to_string(db.tree.store.count)
      + " blocks=" + convert.int_to_string(db.tree.store.bs.block_count)
      + " pins=" + convert.int_to_string(db.tree.store.pins.len())
      + " defer=" + convert.int_to_string(db_file_compaction_deferrals(&db)));
    if db_file_checkpoint(&mut db) < 0 { return 5; }
    io.println("soak: post-ckpt keys=" + convert.int_to_string(end)
      + " count=" + convert.int_to_string(db.tree.store.count)
      + " blocks=" + convert.int_to_string(db.tree.store.bs.block_count)
      + " gen=" + convert.int_to_string(db_file_snap_generation(&db)));
    done = end;
    let st = ns_pager_stats(&db.tree.store);
    io.println("soak: keys=" + convert.int_to_string(done)
      + " size=" + convert.int_to_string(db_file_size(&db))
      + " nodes=" + convert.int_to_string(db.tree.store.count)
      + " blocks=" + convert.int_to_string(db.tree.store.bs.block_count)
      + " gen=" + convert.int_to_string(db_file_snap_generation(&db))
      + " misses=" + convert.int_to_string(st[1])
      + " evict=" + convert.int_to_string(st[2])
      + " spills=" + convert.int_to_string(st[3])
      + " ms=" + convert.int_to_string(io.time_now() - t0));
  }

  // Deterministic sample verification (every 997th key).
  var checked = 0;
  i = 1;
  while i <= want_keys {
    if i % 997 == 1 {
      match db_file_get(&db, i) {
        Some(v) => { if v != i * 10 { return 6; } }
        None => { return 7; }
      }
      checked = checked + 1;
    }
    i = i + 1;
  }
  let st = ns_pager_stats(&db.tree.store);
  io.println("soak: done keys=" + convert.int_to_string(want_keys)
    + " size=" + convert.int_to_string(db_file_size(&db))
    + " verified=" + convert.int_to_string(checked)
    + " nodes=" + convert.int_to_string(db.tree.store.count)
    + " cache=" + convert.int_to_string(db.tree.store.frames.len())
    + " paged=" + convert.bool_to_string(db.tree.store.paged)
    + " hits=" + convert.int_to_string(st[0])
    + " misses=" + convert.int_to_string(st[1])
    + " evict=" + convert.int_to_string(st[2])
    + " spills=" + convert.int_to_string(st[3])
    + " corrupt=" + convert.int_to_string(st[4])
    + " ms=" + convert.int_to_string(io.time_now() - t0));
  if !keep {
    let _ = db_file_flush(&mut db);
    remove_all(path);
  }
  return 0;
}
