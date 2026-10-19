// XIOM ORBITDB -- admin web client (owner-approved 2026-10-19).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A separate, localhost-only control plane for a single-node ORBITDB file.
// Phase 1 is READ-ONLY: status cards, key-range browser, point lookup. It
// source-composes the Satellite engine (../src) and the PULSE Beacon core
// (registry `xiom.pulse` 0.3.1) -- no native GUI dependency, works headless.
//
// IMPORTANT: the engine has no read-only open and no cross-process pin
// contract yet (M3 remainder). The admin OWNS its DB file while it runs; do
// not point it at a database currently opened by another process. The
// Station will replace this direct-open mode with an ORBITWIRE session.
//
// Run (repo root):  scripts/admin.ps1  (or scripts/admin.sh)
//   ORBITDB_ADMIN_DB   database path (default orbitdb-admin.wal)
//   PULSE_BIND         listener bind (default 127.0.0.1; keep localhost)
//   PULSE_PORT         listener port (runner default 8787)
//   ORBITDB_ADMIN_TOKEN optional shared token for /api/* requests
module orbitdb.admin

use xiom.io;
use xiom.env;
use xiom.convert;
use xiom.string;
use xiom.pulse.app;
use xiom.pulse.http;
use xiom.pulse.router;
use xiom.db.engine;
use xiom.db.index.btree;

const ROUTE_INDEX: Int = 1;
const ROUTE_STATUS: Int = 2;
const ROUTE_RANGE: Int = 3;
const ROUTE_GET: Int = 4;

// The PULSE handler is a non-capturing fn, so the engine handle lives in a
// one-element process-global (PULSE itself keeps its route table this way).
var g_dbs: Vec[DBFile] = Vec[DBFile].new();
var g_html: Str = "";
var g_token: Str = "";

fn json_escape(s: Str) -> Str {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    let b = s.byte_at(i);
    if b == 92u8 {
      out.push(92u8); out.push(92u8);
    } else if b == 34u8 {
      out.push(92u8); out.push(34u8);
    } else if b == 10u8 {
      out.push(92u8); out.push(110u8);
    } else if b == 13u8 {
      out.push(92u8); out.push(114u8);
    } else {
      out.push(b);
    }
    i = i + 1;
  }
  return Str::from_utf8(out);
}

// First decoded query value with this name ("" when absent).
fn qv(m: &PulseRoute, name: Str) -> Str {
  var i = 0;
  while i < m.query_names.len() {
    if m.query_names[i] == name { return m.query_values[i]; }
    i = i + 1;
  }
  return "";
}

fn qint(m: &PulseRoute, name: Str, fallback: Int) -> Int {
  let raw = qv(m, name);
  if raw.len() == 0 { return fallback; }
  match io.parse_int(raw) {
    Ok(v) => { return v; }
    Err(_) => { return fallback; }
  }
}

fn authorized(req: &PulseRequest, path: Str) -> Bool {
  if g_token.len() == 0 { return true; }
  if !string.str_starts_with(path, "/api/") { return true; }
  return http.header_get(req, "X-Admin-Token") == g_token;
}

fn file_size_or(path: Str, fallback: Int) -> Int {
  match io.file_size(path) {
    Some(n) => { return n; }
    None => { return fallback; }
  }
}

fn status_out() -> HandlerOut {
  let db = g_dbs[0];
  let st = ns_pager_stats(&db.tree.store);
  let body = "{"
    + "\"path\":\"" + json_escape(db.path) + "\","
    + "\"keys\":" + convert.int_to_string(db_file_size(&db)) + ","
    + "\"size\":" + convert.int_to_string(file_size_or(db.path, 0)) + ","
    + "\"order\":" + convert.int_to_string(db.order) + ","
    + "\"page_format\":" + convert.int_to_string(db.page_format) + ","
    + "\"durability\":" + convert.int_to_string(db.durability) + ","
    + "\"two_phase\":" + convert.bool_to_string(db.two_phase) + ","
    + "\"failed\":" + convert.bool_to_string(db.failed) + ","
    + "\"wal_bytes\":" + convert.int_to_string(db.wal_bytes) + ","
    + "\"last_lsn\":" + convert.int_to_string(db_file_last_lsn(&db)) + ","
    + "\"snap_generation\":" + convert.int_to_string(db_file_snap_generation(&db)) + ","
    + "\"pins\":" + convert.int_to_string(db.tree.store.pins.len()) + ","
    + "\"compaction_deferrals\":" + convert.int_to_string(db_file_compaction_deferrals(&db)) + ","
    + "\"paged\":" + convert.bool_to_string(db.tree.store.paged) + ","
    + "\"nodes\":" + convert.int_to_string(db.tree.store.count) + ","
    + "\"cache_capacity\":" + convert.int_to_string(db.tree.store.frames.len()) + ","
    + "\"block_count\":" + convert.int_to_string(db.tree.store.bs.block_count) + ","
    + "\"pager_hits\":" + convert.int_to_string(st[0]) + ","
    + "\"pager_misses\":" + convert.int_to_string(st[1]) + ","
    + "\"pager_evictions\":" + convert.int_to_string(st[2]) + ","
    + "\"pager_spills\":" + convert.int_to_string(st[3]) + ","
    + "\"pager_corrupt\":" + convert.int_to_string(st[4])
    + "}";
  return app.out_json(200, body);
}

fn range_out(m: &PulseRoute) -> HandlerOut {
  let db = g_dbs[0];
  var low = qint(m, "low", 0);
  var high = qint(m, "high", 1000);
  var limit = qint(m, "limit", 100);
  if high < low { high = low; }
  if limit < 1 { limit = 1; }
  if limit > 500 { limit = 500; }
  let pairs = db_file_range_pairs(&db, low, high);
  var body = "{\"low\":" + convert.int_to_string(low)
    + ",\"high\":" + convert.int_to_string(high)
    + ",\"total\":" + convert.int_to_string(pairs.len())
    + ",\"keys\":[";
  var vals = "],\"values\":[";
  var i = 0;
  var n = 0;
  while i < pairs.len() && n < limit {
    let p = pairs[i];
    if n > 0 { body = body + ","; vals = vals + ","; }
    body = body + convert.int_to_string(p.0);
    vals = vals + convert.int_to_string(p.1);
    n = n + 1;
    i = i + 1;
  }
  body = body + vals + "]}";
  return app.out_json(200, body);
}
fn get_out(m: &PulseRoute) -> HandlerOut {
  let db = g_dbs[0];
  let key = qint(m, "key", 0);
  match db_file_get(&db, key) {
    Some(v) => {
      return app.out_json(200, "{\"key\":" + convert.int_to_string(key)
        + ",\"found\":true,\"value\":" + convert.int_to_string(v) + "}");
    }
    None => {
      return app.out_json(200, "{\"key\":" + convert.int_to_string(key)
        + ",\"found\":false}");
    }
  }
}

fn not_found(msg: Str) -> HandlerOut {
  return app.out_json(404, "{\"error\":\"" + json_escape(msg) + "\"}");
}

fn unauthorized() -> HandlerOut {
  return app.out_json(401, "{\"error\":\"unauthorized\"}");
}

fn handler(req: &PulseRequest, m: &PulseRoute, _body: Str) -> HandlerOut {
  let target = router.split_target(req.target);
  let path = target.0;
  if !authorized(req, path) { return unauthorized(); }
  if m.route_id == ROUTE_INDEX { return app.out_html(200, g_html); }
  if m.route_id == ROUTE_STATUS { return status_out(); }
  if m.route_id == ROUTE_RANGE { return range_out(m); }
  if m.route_id == ROUTE_GET { return get_out(m); }
  return not_found("route");
}

pub fn main() -> Int {
  let path = env.var_or("ORBITDB_ADMIN_DB", "orbitdb-admin.wal");
  g_token = env.var_or("ORBITDB_ADMIN_TOKEN", "");
  match io.read_file("admin/src/index.html") {
    Ok(s) => { g_html = s; }
    Err(_) => { g_html = "<!doctype html><h1>ORBITDB Admin</h1><p>admin/src/index.html is missing; run from the repo root.</p>"; }
  }
  g_dbs.push(db_file_open(path, 4));
  let _ = app.register("GET", "/");
  let _ = app.register("GET", "/api/status");
  let _ = app.register("GET", "/api/range");
  let _ = app.register("GET", "/api/get");
  let bind = env.var_or("PULSE_BIND", "127.0.0.1");
  let port = env.var_or("PULSE_PORT", "8080");
  io.println("orbitdb-admin: http://" + bind + ":" + port + "  db=" + path);
  return app.serve(handler);
}
