// Diagnostic: detect cycles/out-of-range children in a v2 tree after GC.
module orbitdb_diag_cycle

use xiom.io;
use xiom.convert;
use xiom.db.storage.block_store;
use xiom.db.index.btree;

pub fn main() -> Int {
  let bs = block_store_open("orbitdb-soak-smoke.wal.snap");
  io.println("hdr gen=" + convert.int_to_string(bs.header.committed_generation)
    + " root=" + convert.int_to_string(bs.header.root)
    + " count=" + convert.int_to_string(bs.header.node_count)
    + " blocks=" + convert.int_to_string(bs.block_count));
  var store = ns_new_paged(bs, bs.header.node_count, 64);
  var tree = BTree{ root: bs.header.root, order: bs.header.order, store: store };
  var seen = Vec[Bool].new();
  var i = 0;
  while i < ns_len(&tree.store) { seen.push(false); i = i + 1; }
  var stack = Vec[Int].new();
  stack.push(tree.root);
  var si = 0;
  var cycles = 0;
  var oob = 0;
  var edges = 0;
  while si < stack.len() {
    let idx = stack[si];
    si = si + 1;
    if idx < 0 || idx >= ns_len(&tree.store) {
      oob = oob + 1;
    } else if seen[idx] {
      cycles = cycles + 1;
    } else {
      seen[idx] = true;
      let node = ns_get(&tree.store, idx);
      var c = 0;
      while c < node.children.len() {
        edges = edges + 1;
        stack.push(node.children[c]);
        c = c + 1;
      }
    }
  }
  var reachable = 0;
  i = 0;
  while i < ns_len(&tree.store) {
    if seen[i] { reachable = reachable + 1; }
    i = i + 1;
  }
  io.println("walk: reachable=" + convert.int_to_string(reachable)
    + " count=" + convert.int_to_string(ns_len(&tree.store))
    + " edges=" + convert.int_to_string(edges)
    + " dup_visits(cycles)=" + convert.int_to_string(cycles)
    + " oob=" + convert.int_to_string(oob));
  let st = ns_pager_stats(&tree.store);
  io.println("hits=" + convert.int_to_string(st[0]) + " misses=" + convert.int_to_string(st[1])
    + " evict=" + convert.int_to_string(st[2]) + " spills=" + convert.int_to_string(st[3])
    + " corrupt=" + convert.int_to_string(st[4]));
  return 0;
}
