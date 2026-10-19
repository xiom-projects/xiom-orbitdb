// Diagnostic: dump a small B-tree's node layout (order 4, sequential keys).
module orbitdb_diag_pack2

use xiom.io;
use xiom.env;
use xiom.convert;
use xiom.db.index.btree;

fn env_int(name: Str, fallback: Int) -> Int {
  let raw = env.var_or(name, "");
  if raw.len() == 0 { return fallback; }
  match io.parse_int(raw) { Ok(v) => { return v; } Err(_) => { return fallback; } }
}

pub fn main() -> Int {
  let want = env_int("PACK_N", 30);
  var t = btree_new(4);
  var n = 1;
  while n <= want {
    if !btree_insert(&mut t, n, n * 10) { return 1; }
    n = n + 1;
  }
  io.println("pack2: keys=" + convert.int_to_string(btree_size(&t))
    + " nodes=" + convert.int_to_string(ns_len(&t.store))
    + " root=" + convert.int_to_string(t.root));
  var ids = Vec[Int].new();
  var depth = Vec[Int].new();
  ids.push(t.root);
  depth.push(0);
  var si = 0;
  while si < ids.len() && si < 60 {
    let idx = ids[si];
    let d = depth[si];
    si = si + 1;
    let node = ns_get(&t.store, idx);
    var line = "  d" + convert.int_to_string(d) + " n" + convert.int_to_string(idx)
      + " leaf=" + convert.bool_to_string(node.is_leaf) + " keys=[";
    var k = 0;
    while k < node.keys.len() {
      line = line + convert.int_to_string(node.keys[k]) + ",";
      k = k + 1;
    }
    line = line + "] ch=[";
    k = 0;
    while k < node.children.len() {
      line = line + convert.int_to_string(node.children[k]) + ",";
      k = k + 1;
    }
    io.println(line + "]");
    k = 0;
    while k < node.children.len() {
      ids.push(node.children[k]);
      depth.push(d + 1);
      k = k + 1;
    }
  }
  return 0;
}
