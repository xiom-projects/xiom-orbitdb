// XIOM ORBITDB -- m375 minimal repro: repeated random 4 KiB reads.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The pager's hot path is `read_at(4096)` -> decode; the A6 soak showed
// per-I/O retention. This isolates the read path from the B-tree:
//   MEM_READ_MODE=a -> io.read_at            (Vec[UInt8] per call)
//   MEM_READ_MODE=b -> byteio_read_at        (+ u8_to_bytes, Vec[Int] 8x)
// Peak RSS is sampled externally (XIOM has no RSS API).
module orbitdb_probe_mem_read

use xiom.io;
use xiom.env;
use xiom.convert;
use xiom.db.storage.byte_io;

fn env_int(name: Str, fallback: Int) -> Int {
  let raw = env.var_or(name, "");
  if raw.len() == 0 { return fallback; }
  match io.parse_int(raw) { Ok(v) => { return v; } Err(_) => { return fallback; } }
}

pub fn main() -> Int {
  let path = env.var_or("MEM_READ_PATH", "orbitdb-mem-read.bin");
  let mb = env_int("MEM_READ_FILE_MB", 64);
  let reads = env_int("MEM_READ_COUNT", 100000);
  let mode = env.var_or("MEM_READ_MODE", "a");
  let _ = io.remove_file(path);
  var blk = Vec[UInt8].new();
  var i = 0;
  while i < 4096 { blk.push(1u8); i = i + 1; }
  let blocks = (mb * 1024 * 1024) / 4096;
  i = 0;
  while i < blocks {
    match io.write_at(path, i * 4096, &blk) {
      Ok(_) => {}
      Err(_) => { io.println("mem-read: create failed"); return 1; }
    }
    i = i + 1;
  }
  io.println("mem-read: start mode=" + mode
    + " file_mb=" + convert.int_to_string(mb)
    + " reads=" + convert.int_to_string(reads));
  var sum = 0;
  var r = 0;
  while r < reads {
    let off = (r % blocks) * 4096;
    if mode == "b" {
      match byteio_read_at(path, off, 4096) {
        Some(d) => { sum = sum + d.len(); }
        None => { io.println("mem-read: byteio miss"); return 2; }
      }
    } else {
      match io.read_at(path, off, 4096) {
        Ok(d) => { sum = sum + d.len(); }
        Err(_) => { io.println("mem-read: read_at error"); return 3; }
      }
    }
    if r % 25000 == 0 {
      io.println("mem-read: at=" + convert.int_to_string(r)
        + " sum=" + convert.int_to_string(sum));
    }
    r = r + 1;
  }
  io.println("mem-read: done reads=" + convert.int_to_string(reads)
    + " sum=" + convert.int_to_string(sum));
  return 0;
}
