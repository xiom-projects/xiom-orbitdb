// XIOM ORBITDB admin -- seed a demo database for the smoke run.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
module orbitdb.admin.seed

use xiom.io;
use xiom.env;
use xiom.convert;
use xiom.db.engine;

pub fn main() -> Int {
  let path = env.var_or("ORBITDB_ADMIN_DB", "orbitdb-admin-demo.wal");
  match io.remove_file(path) { Ok(_) => {} Err(_) => {} }
  match io.remove_file(path + ".snap") { Ok(_) => {} Err(_) => {} }
  var db = db_file_open(path, 4);
  var i = 1;
  while i <= 40 {
    if !db_file_put(&mut db, i, i * 10) { return 1; }
    i = i + 1;
  }
  let gen = db_file_checkpoint(&mut db);
  if gen < 0 { return 2; }
  io.println("seeded 40 keys -> " + path + "  snapshot gen=" + convert.int_to_string(gen)
    + "  size=" + convert.int_to_string(db_file_size(&db)));
  return 0;
}
