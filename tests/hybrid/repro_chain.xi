// Minimal repro: chained persist -> load -> recover -> persist -> load.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Expected: load2 records == recovered live points (recovery compacts to a
// self-contained checkpoint log; xiom-xvector docs section 3 says "a
// recovered engine is itself recoverable").
// Observed on xiom-xvector @ de1db14 (compiler v0.64.2): load2 records == 0,
// because the compacted log resumes LSNs after the source log while the
// loader requires the first record's LSN to be exactly 1.

module repro_chain

use xiom.io;
use xiom.convert;
use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.durability.wal;
use xiom.vector.durability.wal_file;
use xiom.vector.types.dense_vector;
use xiom.vector.types.metric;

fn main() -> Int {
  let f1 = "probe-logs/repro-chain-1.wal";
  let f2 = "probe-logs/repro-chain-2.wal";
  var eng = engine_new();
  create_collection(&mut eng, 4, DistanceMetric.Cosine);
  var v = Vector.new(4);
  v.set(0, 1.0);
  upsert(&mut eng, 1, v);
  var v2 = Vector.new(4);
  v2.set(1, 1.0);
  upsert(&mut eng, 2, v2);
  let p1 = wal_persist(&eng.wal, f1);
  var p1n: Int = 0;
  if p1 { p1n = 1; }
  io.println("persist1=" + convert.int_to_string(p1n));
  var w1 = wal_load(f1);
  io.println("load1 records=" + convert.int_to_string(w1.records.len()));
  var eng2 = engine_recover(&w1, 4, DistanceMetric.Cosine);
  io.println("recovered size=" + convert.int_to_string(engine_size(&eng2)));
  io.println("checkpointed log records=" + convert.int_to_string(eng2.wal.records.len()));
  io.println("checkpointed first lsn=" + convert.int_to_string(eng2.wal.records[0].lsn));
  let p2 = wal_persist(&eng2.wal, f2);
  var p2n: Int = 0;
  if p2 { p2n = 1; }
  io.println("persist2=" + convert.int_to_string(p2n));
  var w2 = wal_load(f2);
  io.println("load2 records=" + convert.int_to_string(w2.records.len()));
  var eng3 = engine_recover(&w2, 4, DistanceMetric.Cosine);
  io.println("recovered2 size=" + convert.int_to_string(engine_size(&eng3)));
  return 0;
}
