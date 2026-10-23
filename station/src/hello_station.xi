// XIOM ORBITDB Station -- hello-station entry point (ORBITWIRE v1 loopback).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Run (repo root):  scripts/station.ps1   (or scripts/station.sh)
//   ORBITDB_STATION_DB            database path (default orbitdb-station.wal)
//   ORBITDB_STATION_BIND          bind address (default 127.0.0.1; loopback)
//   ORBITDB_STATION_PORT          port (default 7767; 0 -> first free 17867+)
//   ORBITDB_STATION_ORDER         B-tree order (default 4; typed row budget)
//   ORBITDB_STATION_PAGE_FORMAT   2 = v2 byte blocks (default)
//   ORBITDB_STATION_TOKEN         shared token; empty = AUTH not required
//
// The Station OWNS its database (db_file_open_locked_checked_cfg): a second
// station on the same file fails fast. The DBFile is only touched by this
// process's event-loop thread (single-writer actor).
module orbitdb_station_main

use xiom.io;
use xiom.os.env;
use xiom.convert.parse;
use xiom.station.protocol;
use xiom.station.server;

fn env_int(name: Str, fallback: Int) -> Int {
  match parse.parse_int(env.var_or(name, fallback.to_str())) {
    Ok(v) => { return v; }
    Err(_) => { return fallback; }
  }
}

pub fn main() -> Int {
  let db = env.var_or("ORBITDB_STATION_DB", "orbitdb-station.wal");
  let order = env_int("ORBITDB_STATION_ORDER", 4);
  let page_format = env_int("ORBITDB_STATION_PAGE_FORMAT", 2);
  let bind = env.var_or("ORBITDB_STATION_BIND", "127.0.0.1");
  let port = env_int("ORBITDB_STATION_PORT", 7767);
  let token = env.var_or("ORBITDB_STATION_TOKEN", "");

  var srv = server_new();
  let code = server_init(&mut srv, db, order, page_format, token, bind, port);
  if code != CODE_OK {
    io.println("orbitdb-station: open/listen failed (code " + code.to_str() + ")");
    return 1;
  }
  io.println("orbitdb-station: ORBITWIRE v" + PROTO_VERSION.to_str() +
             " listening on " + srv.host + ":" + srv.port.to_str() +
             " db=" + db);
  // Redirected stdout is block-buffered on Windows; flush the listen line
  // before entering the loop so harnesses can discover the bound port. An
  // optional port file gives service-discovery tools a race-free handle.
  io.flush_stdout();
  let port_file = env.var_or("ORBITDB_STATION_PORT_FILE", "");
  if port_file.len() > 0 {
    let _ = io.write_file(port_file, srv.port.to_str());
  }
  server_run(&mut srv);
  server_shutdown(&mut srv);
  return 0;
}
