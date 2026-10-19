// XIOM ORBITDB -- threads-decision spike: real OS threads + mutex serialization.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Evidence for the ST0 threads decision (docs/ISOLATION.md): the runtime's
// xiom.thread.spawn creates REAL threads and xiom.sync.mutex serializes the
// shared counter across them. This does NOT make a DBFile thread-safe; it
// proves the primitives the Station's engine-actor model builds on.
//
// NOTE: `xiom.thread.spawn` is imported LAST (its module name collides with
// the exported `spawn` fn; keep-first module-name rule, BUG 25 #9).
module orbitdb_probe_threads

use xiom.io;
use xiom.convert;
use xiom.sync.mutex;
use xiom.thread.spawn;

const THREADS: Int = 4;
const PER_THREAD: Int = 10000;

var g_count: Int = 0;
var g_mutex: SyncMutex = mutex_new();

fn worker() {
  var i = 0;
  while i < PER_THREAD {
    mutex_lock(&mut g_mutex);
    g_count = g_count + 1;
    mutex_unlock(&mut g_mutex);
    i = i + 1;
  }
}

pub fn main() -> Int {
  var t1 = spawn(worker);
  var t2 = spawn(worker);
  var t3 = spawn(worker);
  var t4 = spawn(worker);
  let _ = join(t1);
  let _ = join(t2);
  let _ = join(t3);
  let _ = join(t4);
  let expected = THREADS * PER_THREAD;
  io.println("threads: count=" + convert.int_to_string(g_count)
    + " expected=" + convert.int_to_string(expected));
  if g_count == expected {
    io.println("threads: PASS (real threads + mutex)");
    return 0;
  }
  io.println("threads: FAIL");
  return 1;
}
