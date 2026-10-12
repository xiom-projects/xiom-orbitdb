// XIOM ORBITDB -- stdlib wave-115 durability/byte-IO verification probe.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Verifies the primitives behind our fixed stdlib rows on the lane runtime
// (wave 115, stdlib c65acb5; run with XIOM_RUNTIME_DIR=<stdlib>/runtime until
// the next compiler pin re-vendors it):
//   orbitdb-3 real fsync            -> sync_io.sync_fd + io.fsync
//   orbitdb-4 held append handle    -> sync_io.open_append/write_all/close_fd
//   orbitdb-5 truncate primitive    -> io.truncate_file
//   orbitdb-6 byte random access    -> io.read_at / io.write_at / io.append_file_bytes
//   P3 rename durability            -> sync_io.fsync_dir
//
// Env: ORBITDB_IO_PRIM_DIR (default probe-logs). Exit: 0 = all checks, 1 = failed.

module orbitdb_probe_io_primitives

use xiom.io;
use xiom.os.env;
use xiom.os.sync_io;
use xiom.convert;

fn check(ok: Bool, name: Str, fails: Int) -> Int {
  if ok { io.println("  [PASS] " + name); return fails; }
  io.println("  [FAIL] " + name);
  return fails + 1;
}

fn bytes2(a: UInt8, b: UInt8) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(a);
  v.push(b);
  return v;
}

fn main() -> Int {
  let dir = env.var_or("ORBITDB_IO_PRIM_DIR", "probe-logs");
  let path = dir + "/io-prim.bin";
  let tmp = dir + "/io-prim.tmp";
  let _ = io.remove_file(path);
  let _ = io.remove_file(tmp);
  var fails: Int = 0;

  // A. held append handle + sync_fd (rows -3, -4).
  let a1 = sync_io.open_append(path);
  match a1 {
    Err(_) => { fails = check(false, "open_append returns a handle", fails); }
    Ok(fd) => {
      fails = check(true, "open_append returns a handle", fails);
      let payload = bytes2(97 as UInt8, 98 as UInt8);
      let w1 = sync_io.write_all(fd, &payload);
      fails = check(w1.is_ok, "write_all via the held handle", fails);
      let s1 = sync_io.sync_fd(fd);
      fails = check(s1.is_ok, "sync_fd (real fsync) returns Ok", fails);
      let c1 = sync_io.close_fd(fd);
      fails = check(c1.is_ok, "close_fd returns Ok", fails);
    }
  }
  match io.file_size(path) {
    None => { fails = check(false, "file_size after handle close", fails); }
    Some(sz) => { fails = check(sz == 2, "file_size == 2 after handle close", fails); }
  }

  // B. append_file_bytes + read_at + write_at (row -6).
  let ap = io.append_file_bytes(path, &bytes2(99 as UInt8, 100 as UInt8));
  fails = check(ap.is_ok, "append_file_bytes returns Ok", fails);
  let r1 = io.read_at(path, 0, 4);
  match r1 {
    Err(_) => { fails = check(false, "read_at(0,4) returns Ok", fails); }
    Ok(b) => {
      var ok = b.len() == 4;
      if ok { ok = b[0] == (97 as UInt8); }
      if ok { ok = b[1] == (98 as UInt8); }
      if ok { ok = b[2] == (99 as UInt8); }
      if ok { ok = b[3] == (100 as UInt8); }
      fails = check(ok, "read_at(0,4) == a,b,c,d", fails);
    }
  }
  let w2 = io.write_at(path, 1, &bytes2(88 as UInt8, 89 as UInt8));
  fails = check(w2.is_ok, "write_at(1,[X,Y]) returns Ok", fails);
  let r2 = io.read_at(path, 0, 4);
  match r2 {
    Err(_) => { fails = check(false, "read_at after write_at", fails); }
    Ok(b) => {
      var ok = b.len() == 4;
      if ok { ok = b[0] == (97 as UInt8); }
      if ok { ok = b[1] == (88 as UInt8); }
      if ok { ok = b[2] == (89 as UInt8); }
      if ok { ok = b[3] == (100 as UInt8); }
      fails = check(ok, "write_at overwrote the middle two bytes", fails);
    }
  }

  // C. truncate_file (row -5).
  let tr = io.truncate_file(path, 3);
  fails = check(tr.is_ok, "truncate_file(3) returns Ok", fails);
  match io.file_size(path) {
    None => { fails = check(false, "file_size after truncate", fails); }
    Some(sz) => { fails = check(sz == 3, "file_size == 3 after truncate", fails); }
  }
  let r3 = io.read_at(path, 0, 3);
  match r3 {
    Err(_) => { fails = check(false, "read_at(0,3) after truncate", fails); }
    Ok(b) => {
      var ok = b.len() == 3;
      if ok { ok = b[2] == (89 as UInt8); }
      fails = check(ok, "truncate kept the first three bytes", fails);
    }
  }

  // D. fsync_dir (P3, rename durability).
  let fd_tmp = sync_io.open_append(tmp);
  match fd_tmp {
    Err(_) => { fails = check(false, "open_append on tmp", fails); }
    Ok(fd) => {
      let p = bytes2(49 as UInt8, 50 as UInt8);
      let _ = sync_io.write_all(fd, &p);
      let _ = sync_io.sync_fd(fd);
      let _ = sync_io.close_fd(fd);
    }
  }
  let d = sync_io.fsync_dir(dir);
  fails = check(d.is_ok, "fsync_dir returns Ok", fails);
  let rm1 = io.remove_file(path);
  let rm2 = io.remove_file(tmp);
  fails = check(rm1.is_ok && rm2.is_ok, "cleanup removes both fixtures", fails);

  if fails == 0 { io.println("io-primitives: GREEN"); return 0; }
  io.println("io-primitives: RED fails=" + convert.int_to_string(fails));
  return 1;
}
