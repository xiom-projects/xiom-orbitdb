// XIOM ORBITDB -- isolate the write-path memory growth (m375 fallback work).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// MODE=wal   -> wal_file_append_sync N times (one open/close per append)
// MODE=btree -> btree_insert N times into an order-64 tree (no IO)
// Peak RSS is sampled externally (run through scripts/run_capped).
module orbitdb_probe_mem_write

use xiom.io;
use xiom.env;
use xiom.convert;
use xiom.db.wal_file;
use xiom.db.index.btree;

fn env_int(name: Str, fallback: Int) -> Int {
  let raw = env.var_or(name, "");
  if raw.len() == 0 { return fallback; }
  match io.parse_int(raw) { Ok(v) => { return v; } Err(_) => { return fallback; } }
}

pub fn main() -> Int {
  let mode = env.var_or("MEM_WRITE_MODE", "wal");
  let n = env_int("MEM_WRITE_N", 200000);
  io.println("mem-write: start mode=" + mode + " n=" + convert.int_to_string(n));
  if mode == "btree" {
    var t = btree_new(64);
    var i = 1;
    while i <= n {
      if !btree_insert(&mut t, i, i * 10) { return 1; }
      if i % 50000 == 0 {
        io.println("mem-write: btree " + convert.int_to_string(i)
          + " nodes=" + convert.int_to_string(ns_len(&t.store)));
      }
      i = i + 1;
    }
    io.println("mem-write: btree done nodes=" + convert.int_to_string(ns_len(&t.store)));
    return 0;
  }
  let path = env.var_or("MEM_WRITE_PATH", "orbitdb-mem-write.wal");
  let _ = io.remove_file(path);
  var w = wal_file_open(path);
  var i = 1;
  while i <= n {
    let lsn = wal_file_append_sync(&mut w, WALOpKind.Insert, i, i * 10, false);
    if lsn < 0 { return 2; }
    if i % 50000 == 0 {
      io.println("mem-write: wal " + convert.int_to_string(i)
        + " next_lsn=" + convert.int_to_string(w.next_lsn));
    }
    i = i + 1;
  }
  io.println("mem-write: wal done next_lsn=" + convert.int_to_string(w.next_lsn));
  let _ = io.remove_file(path);
  return 0;
}
