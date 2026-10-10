// XIOM ORBITDB -- deterministic seeded fuzz/property harness.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// No wall-clock, no OS entropy: every run over a fixed seed matrix is
// reproducible. Sections:
//   (a) tuple codec -- roundtrip + byte-flip mutations (decode must reject or
//       re-encode to the exact mutated buffer) + truncation rejection;
//   (b) WAL segment parser -- valid records interleaved with garbage lines and
//       an optional torn tail; replay must return exactly the valid records
//       with strictly increasing LSNs, and open() must heal before appending;
//   (c) page log parser -- latest-wins across CRC-valid versions; corrupted
//       checksums are skipped; garbage/torn lines never count;
//   (d) B-tree vs model -- random insert/update/delete/search/range/min/max
//       against a flat model, several orders and seeds;
//   (e) block codec v2 -- random page/header roundtrips + single-byte
//       mutations (decode must reject or reflect the mutation; it must never
//       decode back to the original view);
//   (f) block store vs model -- random put generations with probabilistic
//       commits, an open/compare after every commit and at the end (visible
//       set + latest payload per id must match the committed history);
//   (g) query + secondary index vs model -- random put/delete + random
//       conditions/order/limit/offset on a DBFile with an index installed;
//       results must equal a brute-force model and usable conditions must
//       plan as IndexValue.
//
// Env:
//   ORBITDB_FUZZ_DIR          scratch dir                     (default probe-logs)
//   ORBITDB_FUZZ_SEEDS        seed count                     (default 4)
//   ORBITDB_FUZZ_OPS          btree ops per seed             (default 4000)
//   ORBITDB_FUZZ_N            btree key space                (default 512)
//   ORBITDB_FUZZ_TUPLE_ITERS  tuple iterations per seed      (default 300)
//   ORBITDB_FUZZ_WAL_ITERS    WAL files per seed             (default 30)
//   ORBITDB_FUZZ_PAGE_ITERS   page logs per seed             (default 30)
//   ORBITDB_FUZZ_BLOCK_ITERS  block-codec iterations per seed (default 200)
//   ORBITDB_FUZZ_BLOCKSTORE_GENS  block-store generations per seed (default 12)
//   ORBITDB_FUZZ_QUERY_ITERS    query/index iterations per seed (default 150)
//
// Exit: 0 = green; non-zero = failing section + first violation (printed).

module orbitdb_probe_fuzz

use xiom.io;
use xiom.os.env;
use xiom.convert;
use xiom.convert.parse;
use xiom.db.engine;
use xiom.db.storage.page;
use xiom.db.storage.page_file;
use xiom.db.storage.block;
use xiom.db.storage.block_store;
use xiom.db.secondary_index;
use xiom.db.storage.tuple;
use xiom.db.wal_file;

fn rand_next(state: &mut Int) -> Int {
  *state = (*state * 1103515245 + 12345) % 2147483648;
  return *state;
}

// High-bit modulus: the LCG's low bits cycle with small periods, so a plain
// `% m` for non-power-of-two m can starve whole branches (e.g. action = 11
// never being selected) -- the fuzz must exercise every branch.
fn rand_mod(state: &mut Int, m: Int) -> Int {
  if m <= 1 { return 0; }
  return (rand_next(state) / 65536) % m;
}

fn value_of(key: Int) -> Int {
  return key * 7 + 1;
}

fn vec_eq(a: &Vec[Int], b: &Vec[Int]) -> Bool {
  if a.len() != b.len() { return false; }
  var i = 0;
  while i < a.len() {
    if a[i] != b[i] { return false; }
    i = i + 1;
  }
  return true;
}

fn parse_env_int(name: Str, fallback: Int) -> Int {
  var out = fallback;
  match parse.parse_int(env.var_or(name, convert.int_to_string(fallback))) {
    Ok(v) => { if v > 0 { out = v; } }
    Err(_) => {}
  }
  return out;
}

// (a) tuple codec fuzz -------------------------------------------------------
fn fuzz_tuple(seed: Int, iters: Int) -> Int {
  var state = seed;
  var it = 0;
  while it < iters {
    var row_id = rand_next(&mut state) % 2000003 - 1000000;
    var cols = rand_mod(&mut state, 6);
    var data = Vec[Int].new();
    var c = 0;
    while c < cols {
      data.push(rand_next(&mut state) % 4096 - 2048);
      c = c + 1;
    }
    var row = Row.new(row_id, data);

    let enc_r = tuple_encode_checked(&row);
    var enc = Vec[Int].new();
    match enc_r {
      Ok(p) => {
        let v: Vec[Int] = p;
        enc = v;
      }
      Err(_) => {
        io.println("fuzz tuple: encode rejected a valid row it=" + convert.int_to_string(it));
        return 1;
      }
    }

    let dec_r = tuple_decode(&enc);
    match dec_r {
      Ok(p) => {
        let back: Row = p;
        if back.id != row_id { io.println("fuzz tuple: id mismatch"); return 2; }
        if back.data.len() != cols { io.println("fuzz tuple: column count"); return 3; }
        var ci = 0;
        while ci < cols {
          if back.data[ci] != row.data[ci] { io.println("fuzz tuple: column value"); return 4; }
          ci = ci + 1;
        }
      }
      Err(_) => {
        io.println("fuzz tuple: decode rejected a valid encoding it=" + convert.int_to_string(it));
        return 5;
      }
    }

    // Byte-flip mutation: decode must reject, or produce a row whose
    // re-encoding reproduces the mutated buffer byte-for-byte (canonical v1).
    var mbuf = Vec[Int].new();
    var mi = 0;
    while mi < enc.len() {
      mbuf.push(enc[mi]);
      mi = mi + 1;
    }
    let pos = rand_mod(&mut state, mbuf.len());
    let delta = rand_mod(&mut state, 255) + 1;
    mbuf[pos] = (mbuf[pos] + delta) & 0xFF;
    let mr = tuple_decode(&mbuf);
    match mr {
      Ok(p) => {
        let mrow: Row = p;
        let re = tuple_encode(&mrow);
        if !vec_eq(&re, &mbuf) {
          io.println("fuzz tuple: mutated decode not canonical it=" + convert.int_to_string(it));
          return 6;
        }
      }
      Err(_) => {}
    }

    // Strict-prefix truncation must be rejected by the length gate.
    let cut = rand_next(&mut state) % enc.len();
    var trunc = Vec[Int].new();
    var ti = 0;
    while ti < cut {
      trunc.push(enc[ti]);
      ti = ti + 1;
    }
    let tr = tuple_decode(&trunc);
    match tr {
      Ok(_) => {
        io.println("fuzz tuple: truncated buffer accepted it=" + convert.int_to_string(it));
        return 7;
      }
      Err(_) => {}
    }

    it = it + 1;
  }
  return 0;
}

// (b) WAL segment parser fuzz -------------------------------------------------
fn fuzz_wal(seed: Int, iters: Int, recs: Int, dir: Str) -> Int {
  var state = seed;
  var garbage = Vec[Str].new();
  garbage.push("garbage");
  garbage.push("1|2|3");
  garbage.push("|||");
  garbage.push("1|2|x|4|5");
  garbage.push("a|b|c|d|e");

  var it = 0;
  while it < iters {
    let path = dir + "/fuzz-wal-" + convert.int_to_string(seed) + "-"
      + convert.int_to_string(it) + ".wal";
    let _ = io.remove_file(path);
    var w = wal_file_open(path);
    var expected = 0;
    var j = 0;
    while j < recs {
      let action = rand_mod(&mut state, 7);
      if action == 0 {
        let lsn = wal_file_append(&mut w, WALOpKind.Insert, rand_next(&mut state) % 1000, 7);
        if lsn < 0 { io.println("fuzz wal: append failed"); return 1; }
        expected = expected + 1;
      } elif action == 1 {
        let lsn = wal_file_append(&mut w, WALOpKind.Update, rand_next(&mut state) % 1000, 8);
        if lsn < 0 { io.println("fuzz wal: append failed"); return 1; }
        expected = expected + 1;
      } elif action == 2 {
        let lsn = wal_file_append(&mut w, WALOpKind.Delete, rand_next(&mut state) % 1000, 9);
        if lsn < 0 { io.println("fuzz wal: append failed"); return 1; }
        expected = expected + 1;
      } elif action == 3 {
        var payload = Vec[Int].new();
        payload.push(rand_next(&mut state) % 100);
        payload.push(rand_next(&mut state) % 100);
        let lsn = wal_file_append_tagged(&mut w, WALOpKind.Checkpoint, 0, 0, payload, 0);
        if lsn < 0 { io.println("fuzz wal: append failed"); return 1; }
        expected = expected + 1;
      } elif action == 4 {
        let g = garbage[rand_mod(&mut state, garbage.len())];
        let app = io.append_line(path, g);
        match app { Ok(_) => {}, Err(_) => { io.println("fuzz wal: garbage append failed"); return 2; } }
      } elif action == 5 {
        // A valid begin/commit pair (no index effect) keeps the op mix broad.
        let lsn = wal_file_append(&mut w, WALOpKind.BeginTxn, 0, 0);
        if lsn < 0 { io.println("fuzz wal: append failed"); return 1; }
        expected = expected + 1;
      } else {
        let lsn = wal_file_append(&mut w, WALOpKind.CommitTxn, 0, 0);
        if lsn < 0 { io.println("fuzz wal: append failed"); return 1; }
        expected = expected + 1;
      }
      j = j + 1;
    }

    // Optional torn tail AFTER the last valid record: replay must skip it and
    // open() must heal it before the next append.
    if (rand_next(&mut state) % 2) == 0 {
      let app = io.append_file(path, "88|2|3|");
      match app { Ok(_) => {}, Err(_) => { io.println("fuzz wal: torn append failed"); return 2; } }
    }

    let got = wal_file_replay(path);
    if got.len() != expected {
      io.println("fuzz wal: replay count got=" + convert.int_to_string(got.len())
        + " want=" + convert.int_to_string(expected) + " it=" + convert.int_to_string(it));
      return 3;
    }
    var prev = 0;
    var ri = 0;
    while ri < got.len() {
      let rec = got[ri];
      if rec.lsn <= prev { io.println("fuzz wal: lsn not increasing"); return 4; }
      prev = rec.lsn;
      let code = wal_op_code(rec.op);
      if code < 1 || code > 10 { io.println("fuzz wal: op code out of range"); return 5; }
      ri = ri + 1;
    }

    var w2 = wal_file_open(path);
    let lsn2 = wal_file_append(&mut w2, WALOpKind.Insert, 42, 420);
    if lsn2 < 0 { io.println("fuzz wal: heal append failed"); return 6; }
    let got2 = wal_file_replay(path);
    if got2.len() != expected + 1 { io.println("fuzz wal: post-heal count"); return 7; }
    let last = got2[got2.len() - 1];
    if last.lsn != lsn2 { io.println("fuzz wal: post-heal last lsn"); return 8; }

    let _ = io.remove_file(path);
    it = it + 1;
  }
  return 0;
}

// (c) page log parser fuzz ----------------------------------------------------
fn fuzz_page(seed: Int, iters: Int, pages_per: Int, dir: Str) -> Int {
  var state = seed;
  var it = 0;
  while it < iters {
    let path = dir + "/fuzz-page-" + convert.int_to_string(seed) + "-"
      + convert.int_to_string(it) + ".tmp";
    let _ = io.remove_file(path);
    let pf = page_file_open(path);
    var ids = Vec[Int].new();
    var vers = Vec[Int].new();

    var j = 0;
    while j < pages_per {
      let id = rand_next(&mut state) % 8;
      let ver = rand_next(&mut state) % 64;
      var d = Vec[Int].new();
      d.push(id);
      d.push(ver);
      var cs = page_compute_checksum(&d);
      let corrupt = rand_mod(&mut state, 5) == 0;
      if corrupt { cs = cs + 1; }
      if !page_log_append(&pf, Page.new(id, d, cs)) {
        io.println("fuzz page: append failed");
        return 1;
      }
      // Model: only CRC-valid writes count, latest version per id wins.
      if !corrupt {
        var found = -1;
        var k = 0;
        while k < ids.len() {
          if ids[k] == id { found = k; }
          k = k + 1;
        }
        if found >= 0 {
          vers[found] = ver;
        } else {
          ids.push(id);
          vers.push(ver);
        }
      }
      j = j + 1;
    }

    let _ = io.append_line(path, "garbage");
    let _ = io.append_line(path, "1|2|3");
    if (rand_next(&mut state) % 2) == 0 {
      let _ = io.append_file(path, "7|2|");
    }

    let got = page_log_read_all(&pf);
    if got.len() != ids.len() {
      io.println("fuzz page: read_all count got=" + convert.int_to_string(got.len())
        + " want=" + convert.int_to_string(ids.len()) + " it=" + convert.int_to_string(it));
      return 2;
    }
    var q = 0;
    while q < ids.len() {
      var ok = false;
      var r = 0;
      while r < got.len() {
        let pg = got[r];
        if pg.id == ids[q] {
          if pg.data.len() == 2 {
            if pg.data[1] == vers[q] { ok = true; }
          }
        }
        r = r + 1;
      }
      if !ok {
        io.println("fuzz page: latest version mismatch id=" + convert.int_to_string(ids[q]));
        return 3;
      }
      q = q + 1;
    }

    if ids.len() > 0 {
      let single = page_file_read(&pf, ids[0]);
      match single {
        None => { io.println("fuzz page: point read missing"); return 4; }
        Some(p) => {
          let pg2: Page = p;
          if pg2.data.len() != 2 { io.println("fuzz page: point read shape"); return 5; }
        }
      }
    }

    let _ = io.remove_file(path);
    it = it + 1;
  }
  return 0;
}

// (d) B-tree vs model fuzz ----------------------------------------------------
fn fuzz_btree(seed: Int, ops: Int, n: Int, order: Int) -> Int {
  var tree = btree_new(order);
  var present = Vec[Int].new();
  var values = Vec[Int].new();
  var i = 0;
  while i < n {
    present.push(0);
    values.push(0);
    i = i + 1;
  }

  var state = seed;
  var step = 0;
  while step < ops {
    let key = rand_next(&mut state) % n;
    let action = rand_mod(&mut state, 12);

    if action < 4 {
      let should = present[key] == 0;
      let got = btree_insert(&mut tree, key, value_of(key));
      if got != should { io.println("fuzz btree: insert mismatch step=" + convert.int_to_string(step)); return 1; }
      if should {
        present[key] = 1;
        values[key] = value_of(key);
      }
    } elif action < 7 {
      let should = present[key] == 1;
      let got = btree_delete(&mut tree, key);
      if got != should { io.println("fuzz btree: delete mismatch step=" + convert.int_to_string(step)); return 2; }
      if should { present[key] = 0; }
    } elif action < 9 {
      let got = btree_search(&tree, key);
      if present[key] == 1 {
        match got {
          None => { io.println("fuzz btree: search missing step=" + convert.int_to_string(step)); return 3; }
          Some(v) => {
            if v != values[key] { io.println("fuzz btree: search value step=" + convert.int_to_string(step)); return 4; }
          }
        }
      } else {
        match got {
          Some(_) => { io.println("fuzz btree: ghost step=" + convert.int_to_string(step)); return 5; }
          None => {}
        }
      }
    } elif action < 11 {
      var lo = rand_mod(&mut state, n);
      var hi = lo + rand_mod(&mut state, 40);
      if hi >= n { hi = n - 1; }
      let got = btree_range_query(&tree, lo, hi);
      var want = Vec[Int].new();
      var k = lo;
      while k <= hi {
        if present[k] == 1 { want.push(values[k]); }
        k = k + 1;
      }
      if got.len() != want.len() { io.println("fuzz btree: range len step=" + convert.int_to_string(step)); return 6; }
      var gi = 0;
      while gi < got.len() {
        if got[gi] != want[gi] { io.println("fuzz btree: range value step=" + convert.int_to_string(step)); return 7; }
        gi = gi + 1;
      }
    } else {
      let got_min = btree_min(&tree);
      let got_max = btree_max(&tree);
      var want_min = -1;
      var want_max = -1;
      var k2 = 0;
      while k2 < n {
        if present[k2] == 1 {
          if want_min < 0 { want_min = k2; }
          want_max = k2;
        }
        k2 = k2 + 1;
      }
      if want_min < 0 {
        match got_min { Some(_) => { io.println("fuzz btree: min on empty"); return 8; }, None => {} }
        match got_max { Some(_) => { io.println("fuzz btree: max on empty"); return 9; }, None => {} }
      } else {
        // btree_min/max return the VALUE at the extreme key.
        match got_min {
          None => { io.println("fuzz btree: min missing"); return 10; }
          Some(v) => { if v != value_of(want_min) { io.println("fuzz btree: min value"); return 11; } }
        }
        match got_max {
          None => { io.println("fuzz btree: max missing"); return 12; }
          Some(v) => { if v != value_of(want_max) { io.println("fuzz btree: max value"); return 13; } }
        }
      }
    }
    step = step + 1;
  }

  // Final: size, in-order content, min/max against the model.
  var expected = 0;
  var k3 = 0;
  while k3 < n {
    if present[k3] == 1 { expected = expected + 1; }
    k3 = k3 + 1;
  }
  if btree_size(&tree) != expected { io.println("fuzz btree: final size"); return 14; }
  let vals = btree_to_vec(&tree);
  if vals.len() != expected { io.println("fuzz btree: final vec len"); return 15; }
  var vi = 0;
  var k4 = 0;
  while k4 < n {
    if present[k4] == 1 {
      if vals[vi] != values[k4] { io.println("fuzz btree: final order key=" + convert.int_to_string(k4)); return 16; }
      vi = vi + 1;
    }
    k4 = k4 + 1;
  }
  if expected == 0 {
    match btree_min(&tree) { Some(_) => { io.println("fuzz btree: final min on empty"); return 17; }, None => {} }
  } else {
    var want_min2 = -1;
    var want_max2 = -1;
    var k5 = 0;
    while k5 < n {
      if present[k5] == 1 {
        if want_min2 < 0 { want_min2 = k5; }
        want_max2 = k5;
      }
      k5 = k5 + 1;
    }
    match btree_min(&tree) {
      None => { io.println("fuzz btree: final min missing"); return 18; }
      Some(v) => { if v != value_of(want_min2) { io.println("fuzz btree: final min"); return 19; } }
    }
    match btree_max(&tree) {
      None => { io.println("fuzz btree: final max missing"); return 20; }
      Some(v) => { if v != value_of(want_max2) { io.println("fuzz btree: final max"); return 21; } }
    }
  }
  return 0;
}

// (e) block codec v2 fuzz ----------------------------------------------------
// Round-trips random page blocks and header slots against a model, then
// applies single-byte mutations: decode must reject, or reflect the mutation
// (the kind byte lives outside the payload CRC, so a flip to another valid
// kind may decode -- it must never decode to the ORIGINAL view).
fn fuzz_block(seed: Int, iters: Int) -> Int {
  var state = seed + 555;
  var it = 0;
  while it < iters {
    let gen = rand_next(&mut state) % 1000000;
    let pid = rand_next(&mut state) % 100000;
    let len = rand_mod(&mut state, block_payload_capacity() + 1);
    var payload = Vec[Int].new();
    var i = 0;
    while i < len {
      payload.push(rand_next(&mut state) % 256);
      i = i + 1;
    }
    let b = block_encode_page(gen, pid, &payload);
    if b.len() != block_size() { return 1; }
    match block_decode_page(&b) {
      Some(p) => {
        if p.generation != gen || p.page_id != pid || !vec_eq(&p.payload, &payload) { return 2; }
      }
      None => { return 3; }
    }
    let h = BlockHeader{
      root: rand_next(&mut state) % 100000,
      order: 3 + rand_mod(&mut state, 8),
      node_count: rand_next(&mut state) % 100000,
      checkpoint_lsn: rand_next(&mut state) % 1000000,
      committed_generation: rand_next(&mut state) % 100000,
      block_count: rand_next(&mut state) % 100000,
      next_page_id: rand_next(&mut state) % 100000,
    };
    let hb = block_encode_header(&h);
    match block_decode_header(&hb) {
      Some(h2) => {
        if h2.root != h.root || h2.order != h.order || h2.node_count != h.node_count { return 4; }
        if h2.checkpoint_lsn != h.checkpoint_lsn { return 4; }
        if h2.committed_generation != h.committed_generation { return 4; }
        if h2.block_count != h.block_count || h2.next_page_id != h.next_page_id { return 4; }
      }
      None => { return 5; }
    }
    var m = 0;
    while m < 6 {
      let idx = rand_next(&mut state) % block_size();
      var t = Vec[Int].new();
      var j = 0;
      while j < block_size() {
        t.push(b[j]);
        j = j + 1;
      }
      t[idx] = (t[idx] + 1 + rand_mod(&mut state, 255)) % 256;
      match block_decode(&t) {
        Some(v) => {
          if v.kind == 0x50 && v.generation == gen && v.page_id == pid && v.payload.len() == len {
            if idx != 5 { return 6; }
          }
        }
        None => {}
      }
      m = m + 1;
    }
    it = it + 1;
  }
  return 0;
}

// (f) block store vs model ---------------------------------------------------
// Model: append history of (id, payload, generation); the reopened view must
// show exactly the distinct ids whose latest history entry has gen <= the
// committed generation, with that entry's payload.
fn bs_compare(path: Str, hid: &Vec[Int], hpay: &Vec[Int], hgen: &Vec[Int], committed: Int) -> Bool {
  var mitems = Vec[Int].new();
  var mvals = Vec[Int].new();
  var i = 0;
  while i < hid.len() {
    if hgen[i] <= committed {
      var at = -1;
      var j = 0;
      while j < mitems.len() {
        if mitems[j] == hid[i] { at = j; }
        j = j + 1;
      }
      if at < 0 {
        mitems.push(hid[i]);
        mvals.push(hpay[i]);
      } else {
        mvals[at] = hpay[i];
      }
    }
    i = i + 1;
  }
  var bs = block_store_open(path);
  if block_store_count(&bs) != mitems.len() { return false; }
  var k = 0;
  while k < mitems.len() {
    match block_store_read(&bs, mitems[k]) {
      Some(pg) => {
        if pg.payload.len() != 1 || pg.payload[0] != mvals[k] { return false; }
      }
      None => { return false; }
    }
    k = k + 1;
  }
  return true;
}

fn fuzz_blockstore(seed: Int, gens: Int, dir: Str) -> Int {
  let path = dir + "/fuzz-block-store.bv2";
  match io.remove_file(path) { Ok(_) => {} Err(_) => {} }
  match io.remove_file(path + ".tmp") { Ok(_) => {} Err(_) => {} }
  var state = seed + 999;
  var hid = Vec[Int].new();
  var hpay = Vec[Int].new();
  var hgen = Vec[Int].new();
  var committed: Int = 0;
  var bs = block_store_open(path);
  var g: Int = 1;
  while g <= gens {
    let puts = 1 + rand_mod(&mut state, 5);
    var p: Int = 0;
    while p < puts {
      let id = rand_mod(&mut state, 12);
      let pay = 10 + rand_mod(&mut state, 200);
      var pv = Vec[Int].new();
      pv.push(pay);
      if block_store_put(&mut bs, g, id, &pv) < 0 { return 1; }
      hid.push(id);
      hpay.push(pay);
      hgen.push(g);
      p = p + 1;
    }
    if rand_mod(&mut state, 10) < 8 {
      var h = BlockHeader{
        root: 1,
        order: 4,
        node_count: 0,
        checkpoint_lsn: g,
        committed_generation: g,
        block_count: 0,
        next_page_id: 64,
      };
      if !block_store_commit(&mut bs, &h) { return 1; }
      committed = g;
      if !bs_compare(path, &hid, &hpay, &hgen, committed) { return 2; }
    }
    g = g + 1;
  }
  if !bs_compare(path, &hid, &hpay, &hgen, committed) { return 3; }
  return 0;
}

// (g) query + secondary index vs model ---------------------------------------
fn model_insert(keys: &mut Vec[Int], vals: &mut Vec[Int], key: Int, val: Int) {
  var pos = 0;
  while pos < keys.len() && keys[pos] < key {
    pos = pos + 1;
  }
  if pos < keys.len() && keys[pos] == key {
    vals[pos] = val;
    return;
  }
  keys.push(0);
  vals.push(0);
  var i = keys.len() - 1;
  while i > pos {
    keys[i] = keys[i - 1];
    vals[i] = vals[i - 1];
    i = i - 1;
  }
  keys[pos] = key;
  vals[pos] = val;
}

fn model_delete(keys: &mut Vec[Int], vals: &mut Vec[Int], key: Int) -> Bool {
  var pos = 0;
  while pos < keys.len() && keys[pos] < key {
    pos = pos + 1;
  }
  if pos >= keys.len() || keys[pos] != key { return false; }
  var i = pos;
  while i < keys.len() - 1 {
    keys[i] = keys[i + 1];
    vals[i] = vals[i + 1];
    i = i + 1;
  }
  keys.pop();
  vals.pop();
  return true;
}

fn model_match(v: Int, op: Int, target: Int) -> Bool {
  if op == 0 { return v == target; }
  if op == 1 { return v != target; }
  if op == 2 { return v < target; }
  if op == 3 { return v <= target; }
  if op == 4 { return v > target; }
  return v >= target;
}

fn model_query(keys: &Vec[Int], vals: &Vec[Int], ops: &Vec[Int], cvals: &Vec[Int],
               order: Int, offset: Int, limit: Int) -> Vec[Int] {
  var mvals = Vec[Int].new();
  var mpos = Vec[Int].new();
  var i = 0;
  while i < vals.len() {
    var ok = true;
    var c = 0;
    while c < ops.len() {
      if !model_match(vals[i], ops[c], cvals[c]) { ok = false; }
      c = c + 1;
    }
    if ok {
      mvals.push(vals[i]);
      mpos.push(i);
    }
    i = i + 1;
  }
  if order == 1 || order == 2 {
    secidx_sort_pairs(&mut mvals, &mut mpos, order == 2);
  }
  var out = Vec[Int].new();
  var start = offset;
  var end = mvals.len();
  if limit > 0 && start + limit < end {
    end = start + limit;
  }
  var k = start;
  while k < end {
    out.push(mvals[k]);
    k = k + 1;
  }
  return out;
}

fn query_where_int(q: &mut Query, op: Int, v: Int) {
  if op == 0 {
    query_where(q, QueryOp.Eq, v);
  } elif op == 1 {
    query_where(q, QueryOp.Neq, v);
  } elif op == 2 {
    query_where(q, QueryOp.Lt, v);
  } elif op == 3 {
    query_where(q, QueryOp.Lte, v);
  } elif op == 4 {
    query_where(q, QueryOp.Gt, v);
  } else {
    query_where(q, QueryOp.Gte, v);
  }
}

fn fuzz_query(seed: Int, iters: Int, dir: Str) -> Int {
  let path = dir + "/fuzz-query.wal";
  match io.remove_file(path) { Ok(_) => {} Err(_) => {} }
  match io.remove_file(path + ".snap") { Ok(_) => {} Err(_) => {} }
  var state = seed + 7777;
  var db = db_file_open(path, 4);
  var keys = Vec[Int].new();
  var vals = Vec[Int].new();

  var s = 0;
  while s < 30 {
    let k = rand_mod(&mut state, 50);
    let v = rand_mod(&mut state, 40);
    if !db_file_put(&mut db, k, v) { return 1; }
    model_insert(&mut keys, &mut vals, k, v);
    s = s + 1;
  }
  if !db_file_create_index(&mut db, "by_value") { return 1; }

  var it = 0;
  while it < iters {
    let action = rand_mod(&mut state, 10);
    if action < 5 {
      let k = rand_mod(&mut state, 50);
      let v = rand_mod(&mut state, 40);
      if !db_file_put(&mut db, k, v) { return 1; }
      model_insert(&mut keys, &mut vals, k, v);
    } elif action < 7 {
      let k = rand_mod(&mut state, 50);
      let ok = db_file_delete(&mut db, k);
      let mok = model_delete(&mut keys, &mut vals, k);
      if ok != mok { return 2; }
    } else {
      let ncond = rand_mod(&mut state, 3);
      var ops = Vec[Int].new();
      var cvals = Vec[Int].new();
      var q = query_new();
      var c = 0;
      while c < ncond {
        let op = rand_mod(&mut state, 6);
        let v = rand_mod(&mut state, 40);
        ops.push(op);
        cvals.push(v);
        query_where_int(&mut q, op, v);
        c = c + 1;
      }
      let order = rand_mod(&mut state, 3);
      if order != 0 { query_order(&mut q, order); }
      let offs = rand_mod(&mut state, 4);
      if offs > 0 { query_offset(&mut q, offs); }
      let lim = rand_mod(&mut state, 5);
      if lim > 0 { query_limit(&mut q, lim); }

      let got = db_file_query(&db, &q);
      let want = model_query(&keys, &vals, &ops, &cvals, order, offs, lim);
      if !vec_eq(&got, &want) { return 3; }

      var usable = false;
      var ci = 0;
      while ci < ops.len() {
        if ops[ci] != 1 { usable = true; }
        ci = ci + 1;
      }
      if usable {
        let plan = plan_query_with_index(&q, &db.tree, true);
        if plan.kind != PlanKind.IndexValue { return 4; }
      }
    }
    it = it + 1;
  }
  return 0;
}

fn main() -> Int {
  let dir = env.var_or("ORBITDB_FUZZ_DIR", "probe-logs");
  let seeds = parse_env_int("ORBITDB_FUZZ_SEEDS", 4);
  let ops = parse_env_int("ORBITDB_FUZZ_OPS", 4000);
  let n = parse_env_int("ORBITDB_FUZZ_N", 512);
  let tuple_iters = parse_env_int("ORBITDB_FUZZ_TUPLE_ITERS", 300);
  let wal_iters = parse_env_int("ORBITDB_FUZZ_WAL_ITERS", 30);
  let page_iters = parse_env_int("ORBITDB_FUZZ_PAGE_ITERS", 30);
  let block_iters = parse_env_int("ORBITDB_FUZZ_BLOCK_ITERS", 200);
  let blockstore_gens = parse_env_int("ORBITDB_FUZZ_BLOCKSTORE_GENS", 12);
  let query_iters = parse_env_int("ORBITDB_FUZZ_QUERY_ITERS", 150);

  var s = 0;
  while s < seeds {
    let seed = 1000 + s * 97;

    let rc_t = fuzz_tuple(seed, tuple_iters);
    if rc_t != 0 {
      io.println("fuzz: tuple FAILED seed=" + convert.int_to_string(seed) + " rc=" + convert.int_to_string(rc_t));
      return 10 + rc_t;
    }
    let rc_w = fuzz_wal(seed, wal_iters, 40, dir);
    if rc_w != 0 {
      io.println("fuzz: wal FAILED seed=" + convert.int_to_string(seed) + " rc=" + convert.int_to_string(rc_w));
      return 30 + rc_w;
    }
    let rc_p = fuzz_page(seed, page_iters, 30, dir);
    if rc_p != 0 {
      io.println("fuzz: page FAILED seed=" + convert.int_to_string(seed) + " rc=" + convert.int_to_string(rc_p));
      return 50 + rc_p;
    }
    let rc_blk = fuzz_block(seed, block_iters);
    if rc_blk != 0 {
      io.println("fuzz: block FAILED seed=" + convert.int_to_string(seed) + " rc=" + convert.int_to_string(rc_blk));
      return 90 + rc_blk;
    }
    let rc_bs = fuzz_blockstore(seed, blockstore_gens, dir);
    if rc_bs != 0 {
      io.println("fuzz: blockstore FAILED seed=" + convert.int_to_string(seed) + " rc=" + convert.int_to_string(rc_bs));
      return 110 + rc_bs;
    }
    let rc_q = fuzz_query(seed, query_iters, dir);
    if rc_q != 0 {
      io.println("fuzz: query FAILED seed=" + convert.int_to_string(seed) + " rc=" + convert.int_to_string(rc_q));
      return 130 + rc_q;
    }
    let order = 3 + (s % 3);
    let rc_b = fuzz_btree(seed, ops, n, order);
    if rc_b != 0 {
      io.println("fuzz: btree FAILED seed=" + convert.int_to_string(seed) + " order=" + convert.int_to_string(order) + " rc=" + convert.int_to_string(rc_b));
      return 70 + rc_b;
    }
    io.println("fuzz: seed=" + convert.int_to_string(seed) + " order=" + convert.int_to_string(order) + " OK");
    s = s + 1;
  }
  io.println("fuzz: OK seeds=" + convert.int_to_string(seeds) + " ops/seed=" + convert.int_to_string(ops)
    + " n=" + convert.int_to_string(n));
  return 0;
}
