// Diagnostic: B-tree packing at scale (order 4, sequential keys).
module orbitdb_diag_pack

use xiom.io;
use xiom.convert;
use xiom.db.index.btree;

pub fn main() -> Int {
  var t = btree_new(4);
  var n = 1;
  while n <= 15000 {
    if !btree_insert(&mut t, n, n * 10) { io.println("insert fail at " + convert.int_to_string(n)); return 1; }
    n = n + 1;
  }
  io.println("pack: keys=" + convert.int_to_string(btree_size(&t))
    + " nodes=" + convert.int_to_string(ns_len(&t.store))
    + " root=" + convert.int_to_string(t.root)
    + " keys_per_node=" + convert.int_to_string(btree_size(&t) / ns_len(&t.store)));
  // Traverse the leaves via the range collector to confirm a sane structure.
  let vals = btree_range_query(&t, 1, 15000);
  io.println("pack: range_count=" + convert.int_to_string(vals.len()));
  return 0;
}
