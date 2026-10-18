// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.db.index.btree

// Flat-array B-tree: node arena (`NodeStore`) with dirty tracking and M3
// snapshot pins (copy-on-write shadowing), plus the canonical structural
// operations (search/insert/delete/range/min/max/to_vec). Extracted
// move-only from engine.xi (R1 split, 2026-10-18).

// Snapshot pin (M3 minimal subset, docs/MVCC.md): a stable read view over
// the node arena. `root` indexes this handle's arena; `lsn` is the highest
// WAL LSN at capture; `generation` is the last committed snapshot generation
// (0 = none). Handle-local; live until `db_file_snapshot_end` or reopen.
pub type DBSnapshot = {
  id: Int;
  root: Int;
  lsn: Int;
  generation: Int;
}

// NodeStore: the node arena behind a B-tree. `dirty[i]` marks node i as
// changed since the last successful snapshot flush; checkpoints encode only
// dirty nodes (M1.1). M3 adds version bookkeeping: `births[i]` is the write
// epoch node i was created in and `pin_clock` counts pin creations; while
// pins exist, a node with `birth <= pin_clock` may be reachable from a pinned
// root and must be shadow-copied before any mutation (see `cow_shadow`).
// `compaction_deferred` counts checkpoint compactions skipped because a pin
// was live (docs/MVCC.md sec. 2.3). The store is fully resident for now --
// lazy load and a bounded cache arrive with the storage spine.
pub type NodeStore = {
  nodes: Vec[BTreeNode];
  dirty: Vec[Bool];
  births: Vec[Int];
  pins: Vec[DBSnapshot];
  pin_clock: Int;
  compaction_deferred: Int;
}

pub fn ns_len(store: &NodeStore) -> Int {
  return store.nodes.len();
}

// Read a node copy.
pub fn ns_get(store: &NodeStore, idx: Int) -> BTreeNode {
  return store.nodes[idx];
}

// Overwrite a node in place and mark it dirty. M3 discipline: the target MUST
// be writable for the current pin state -- i.e. it was produced by `ns_push`
// (which stamps `pin_clock + 1`) or by `cow_shadow` in the same operation.
pub fn ns_set(store: &mut NodeStore, idx: Int, node: BTreeNode) {
  store.nodes[idx] = node;
  store.dirty[idx] = true;
}

// Append a node (new nodes start dirty); returns its index. The birth epoch
// `pin_clock + 1` marks it mutable until a newer pin exists (M3).
pub fn ns_push(store: &mut NodeStore, node: BTreeNode) -> Int {
  store.nodes.push(node);
  store.dirty.push(true);
  store.births.push(store.pin_clock + 1);
  return store.nodes.len() - 1;
}

// Deep copy of a node that OWNS its storage. Struct/Vec assignment shares
// nested Vec buffers and element assignment through a copied handle writes
// through to the source buffer (C-ORBIT-09, docs/repro/vec-copy-alias/), so a
// shadow must rebuild every vector -- keys/values/children and each payload.
fn node_deep_copy(node: &BTreeNode) -> BTreeNode {
  var keys = Vec[Int].new();
  var values = Vec[Int].new();
  var children = Vec[Int].new();
  var payloads = Vec[Vec[Int]].new();
  var i = 0;
  while i < node.keys.len() {
    keys.push(node.keys[i]);
    values.push(node.values[i]);
    i = i + 1;
  }
  i = 0;
  while i < node.children.len() {
    children.push(node.children[i]);
    i = i + 1;
  }
  i = 0;
  while i < node.keys.len() {
    let src = node_payload(node, i);
    var p = Vec[Int].new();
    var k = 0;
    while k < src.len() {
      p.push(src[k]);
      k = k + 1;
    }
    payloads.push(p);
    i = i + 1;
  }
  return BTreeNode{ keys: keys, values: values, payloads: payloads,
                    children: children, is_leaf: node.is_leaf };
}

// M3 copy-on-write: return an index safe to MUTATE for `idx`. Identity while
// no snapshot is pinned (fast path) or when the node was born after the
// newest pin (`birth > pin_clock` -- it cannot be in any pinned view).
// Otherwise the node may be reachable from a pinned root: deep-copy it to a
// fresh slot and return the copy. The caller MUST store the result in the
// (already writable) parent's child pointer or in `tree.root`.
// docs/MVCC.md sec. 2.2.
fn cow_shadow(tree: &mut BTree, idx: Int) -> Int {
  if tree.store.pins.len() == 0 { return idx; }
  if idx < 0 { return idx; }
  if idx >= tree.store.nodes.len() { return idx; }
  if tree.store.births[idx] > tree.store.pin_clock { return idx; }
  let copy = node_deep_copy(&tree.store.nodes[idx]);
  return ns_push(&mut tree.store, copy);
}

// Mark every node clean after a successful snapshot commit (or after a load).
pub fn ns_mark_clean(store: &mut NodeStore) {
  var i = 0;
  while i < store.dirty.len() {
    store.dirty[i] = false;
    i = i + 1;
  }
}

pub type BTree = {
  root: Int;
  order: Int;
  store: NodeStore;
}

pub type BTreeNode = {
  keys: Vec[Int];
  values: Vec[Int];
  // M5.3 typed rows: payload[i] belongs to entry i (parallel to keys/values;
  // empty = plain int entry). For typed rows `values[i]` mirrors the key (the
  // pk), matching the WAL record. See docs/TYPED-VALUES-STORAGE.md.
  payloads: Vec[Vec[Int]];
  children: Vec[Int];
  is_leaf: Bool;
}

fn new_leaf_node() -> BTreeNode {
  var keys = Vec[Int].new();
  var values = Vec[Int].new();
  var payloads = Vec[Vec[Int]].new();
  var children = Vec[Int].new();
  return BTreeNode{ keys: keys, values: values, payloads: payloads,
                    children: children, is_leaf: true };
}

fn new_internal_node() -> BTreeNode {
  var keys = Vec[Int].new();
  var values = Vec[Int].new();
  var payloads = Vec[Vec[Int]].new();
  var children = Vec[Int].new();
  return BTreeNode{ keys: keys, values: values, payloads: payloads,
                    children: children, is_leaf: false };
}

// Defensive parallel-read: a node built before/without payload bookkeeping
// yields the empty payload (plain int entry). Public for the snapshot codec
// and typed-row readers in sibling modules (R1 split).
pub fn node_payload(node: &BTreeNode, i: Int) -> Vec[Int] {
  if i < node.payloads.len() { return node.payloads[i]; }
  return Vec[Int].new();
}

pub fn btree_new(order: Int) -> BTree
  requires: order >= 3
{
  var nodes = Vec[BTreeNode].new();
  var dirty = Vec[Bool].new();
  var births = Vec[Int].new();
  var pins = Vec[DBSnapshot].new();
  var store = NodeStore{ nodes: nodes, dirty: dirty, births: births, pins: pins,
                         pin_clock: 0, compaction_deferred: 0 };
  let leaf = new_leaf_node();
  // The initial leaf must be persisted by the first checkpoint.
  let _ = ns_push(&mut store, leaf);
  return BTree{ root: 0, order: order, store: store };
}

pub fn btree_search(tree: &BTree, key: Int) -> Option[Int] {
  return search_node(tree, tree.root, key);
}

// M5.3: index-free walk that returns the entry's PAYLOAD (typed rows). None
// when the key is absent or the entry carries no payload -- plain int rows
// read through `btree_search`.
pub fn btree_search_payload(tree: &BTree, key: Int) -> Option[Vec[Int]] {
  return search_payload_node(tree, tree.root, key);
}

pub fn search_payload_node(tree: &BTree, node_idx: Int, key: Int) -> Option[Vec[Int]] {
  var node = tree.store.nodes[node_idx];
  var i = 0;
  while i < node.keys.len() {
    if key == node.keys[i] {
      if i < node.payloads.len() {
        let p = node.payloads[i];
        if p.len() > 0 { return Some(p); }
      }
      return None;
    }
    if key < node.keys[i] {
      if node.is_leaf { return None; }
      if i < node.children.len() {
        return search_payload_node(tree, node.children[i], key);
      }
      return None;
    }
    i = i + 1;
  }
  if node.is_leaf { return None; }
  if i < node.children.len() {
    return search_payload_node(tree, node.children[i], key);
  }
  return None;
}

pub fn search_node(tree: &BTree, node_idx: Int, key: Int) -> Option[Int] {
  var node = tree.store.nodes[node_idx];
  var i = 0;
  while i < node.keys.len() {
    if key == node.keys[i] {
      return Some(node.values[i]);
    }
    if key < node.keys[i] {
      if node.is_leaf { return None; }
      if i < node.children.len() {
        return search_node(tree, node.children[i], key);
      }
      return None;
    }
    i = i + 1;
  }
  if node.is_leaf { return None; }
  if i < node.children.len() {
    return search_node(tree, node.children[i], key);
  }
  return None;
}

pub fn btree_insert(tree: &mut BTree, key: Int, value: Int) -> Bool {
  var empty = Vec[Int].new();
  return btree_insert_payload(tree, key, value, empty);
}

// M5.3: insert with a typed-row payload; `value` mirrors the key for typed
// rows (the WAL record does the same). Plain inserts pass an empty payload.
pub fn btree_insert_payload(tree: &mut BTree, key: Int, value: Int,
                            payload: Vec[Int]) -> Bool {
  var found = btree_search(tree, key);
  match found {
    Some(_) => return false,
    None => {}
  }
  var max_keys = tree.order - 1;
  if tree.store.nodes[tree.root].keys.len() >= max_keys {
    // split_root only READS the old root and pushes fresh halves, so a pinned
    // root can be split safely without a shadow copy.
    split_root(tree);
  } else {
    // M3: the root about to be mutated must be writable (may be pinned).
    tree.root = cow_shadow(tree, tree.root);
  }
  return insert_nonfull(tree, tree.root, key, value, payload);
}

fn split_root(tree: &mut BTree) {
  var old_root = tree.store.nodes[tree.root];
  var new_root = new_internal_node();
  var mid = old_root.keys.len() / 2;

  var left = new_leaf_node();
  if !old_root.is_leaf { left.is_leaf = false; }
  var right = new_leaf_node();
  if !old_root.is_leaf { right.is_leaf = false; }

  var i = 0;
  while i < mid {
    left.keys.push(old_root.keys[i]);
    left.values.push(old_root.values[i]);
    left.payloads.push(node_payload(&old_root, i));
    if !old_root.is_leaf && i <= mid && i < old_root.children.len() {
      left.children.push(old_root.children[i]);
    }
    i = i + 1;
  }
  if !old_root.is_leaf && mid < old_root.children.len() {
    left.children.push(old_root.children[mid]);
  }

  i = mid + 1;
  while i < old_root.keys.len() {
    right.keys.push(old_root.keys[i]);
    right.values.push(old_root.values[i]);
    right.payloads.push(node_payload(&old_root, i));
    if !old_root.is_leaf && i < old_root.children.len() {
      right.children.push(old_root.children[i]);
    }
    i = i + 1;
  }
  if !old_root.is_leaf && old_root.keys.len() < old_root.children.len() {
    right.children.push(old_root.children[old_root.keys.len()]);
  }

  var left_idx = ns_push(&mut tree.store, left);
  var right_idx = ns_push(&mut tree.store, right);

  new_root.keys.push(old_root.keys[mid]);
  new_root.values.push(old_root.values[mid]);
  new_root.payloads.push(node_payload(&old_root, mid));
  new_root.children.push(left_idx);
  new_root.children.push(right_idx);

  var root_idx = ns_push(&mut tree.store, new_root);
  tree.root = root_idx;
}

fn insert_nonfull(tree: &mut BTree, node_idx: Int, key: Int, value: Int,
                  payload: Vec[Int]) -> Bool {
  var node = tree.store.nodes[node_idx];
  var max_keys = tree.order - 1;

  if node.is_leaf {
    var pos = 0;
    while pos < node.keys.len() && node.keys[pos] < key {
      pos = pos + 1;
    }
    insert_at_pos(tree, node_idx, pos, key, value, payload);
    return true;
  }

  var pos = 0;
  while pos < node.keys.len() && node.keys[pos] < key {
    pos = pos + 1;
  }

  if pos < node.children.len() {
    var child_idx = node.children[pos];
    if tree.store.nodes[child_idx].keys.len() >= max_keys {
      split_child(tree, node_idx, pos);
      var up_node = tree.store.nodes[node_idx];
      if pos < up_node.keys.len() && up_node.keys[pos] < key {
        pos = pos + 1;
      }
    }
    var new_child_idx = tree.store.nodes[node_idx].children[pos];
    // M3: the descended child will be mutated; make it writable first and
    // persist the shadowed index into this (already writable) parent.
    var shadowed_child = cow_shadow(tree, new_child_idx);
    if shadowed_child != new_child_idx {
      var parent = tree.store.nodes[node_idx];
      parent.children[pos] = shadowed_child;
      ns_set(&mut tree.store, node_idx, parent);
      new_child_idx = shadowed_child;
    }
    return insert_nonfull(tree, new_child_idx, key, value, payload);
  }
  return false;
}

fn split_child(tree: &mut BTree, parent_idx: Int, child_pos: Int) {
  var child_idx = tree.store.nodes[parent_idx].children[child_pos];
  // M3: the child is truncated and re-written below; shadow it first and fix
  // the (already writable) parent so both halves are fresh.
  var shadowed_child = cow_shadow(tree, child_idx);
  if shadowed_child != child_idx {
    var p = tree.store.nodes[parent_idx];
    p.children[child_pos] = shadowed_child;
    ns_set(&mut tree.store, parent_idx, p);
    child_idx = shadowed_child;
  }
  var child = tree.store.nodes[child_idx];
  var mid = child.keys.len() / 2;

  var new_child = new_leaf_node();
  if !child.is_leaf { new_child.is_leaf = false; }

  var i = mid + 1;
  while i < child.keys.len() {
    new_child.keys.push(child.keys[i]);
    new_child.values.push(child.values[i]);
    new_child.payloads.push(node_payload(&child, i));
    if !child.is_leaf && i < child.children.len() {
      new_child.children.push(child.children[i]);
    }
    i = i + 1;
  }
  if !child.is_leaf && child.keys.len() < child.children.len() {
    new_child.children.push(child.children[child.keys.len()]);
  }

  var new_child_idx = ns_push(&mut tree.store, new_child);

  var mid_key = child.keys[mid];
  var mid_val = child.values[mid];
  var mid_payload = node_payload(&child, mid);

  while child.keys.len() > mid {
    child.keys.pop();
    child.values.pop();
    child.payloads.pop();
  }
  if !child.is_leaf {
    while child.children.len() > mid + 1 {
      child.children.pop();
    }
  }

  ns_set(&mut tree.store, child_idx, child);
  ns_set(&mut tree.store, new_child_idx, new_child);

  insert_at_pos(tree, parent_idx, child_pos, mid_key, mid_val, mid_payload);

  // Insert the new sibling pointer at child_pos+1. The parent's child list
  // must be SHIFTED right first: a plain index assignment past the end is a
  // silent no-op, which orphaned the new sibling and corrupted the tree at
  // the first internal split (product defect found by probe_core_diag:
  // insert failed from key 8, size=6 of 100).
  var parent = tree.store.nodes[parent_idx];
  parent.children.push(0);
  var j = parent.children.len() - 1;
  while j > child_pos + 1 {
    parent.children[j] = parent.children[j - 1];
    j = j - 1;
  }
  parent.children[child_pos + 1] = new_child_idx;
  ns_set(&mut tree.store, parent_idx, parent);
}

fn insert_at_pos(tree: &mut BTree, node_idx: Int, pos: Int, key: Int, value: Int,
                 payload: Vec[Int]) {
  var node = tree.store.nodes[node_idx];
  node.keys.push(0);
  node.values.push(0);
  node.payloads.push(Vec[Int].new());
  var i = node.keys.len() - 1;
  while i > pos {
    node.keys[i] = node.keys[i - 1];
    node.values[i] = node.values[i - 1];
    node.payloads[i] = node.payloads[i - 1];
    i = i - 1;
  }
  node.keys[pos] = key;
  node.values[pos] = value;
  node.payloads[pos] = payload;
  ns_set(&mut tree.store, node_idx, node);
}

pub fn btree_delete(tree: &mut BTree, key: Int) -> Bool {
  var found = btree_search(tree, key);
  match found {
    None => return false,
    Some(_) => {}
  }
  // M3: only a found key mutates the tree, so the root is shadowed here (a
  // no-op delete must not copy anything).
  tree.root = cow_shadow(tree, tree.root);
  return delete_from_node(tree, tree.root, key);
}

fn delete_from_node(tree: &mut BTree, node_idx: Int, key: Int) -> Bool {
  var node = tree.store.nodes[node_idx];
  // Split scheme: a full node has order-1 keys and splits into halves that
  // differ by one, so the true floor is (order-2)/2 (same as the old formula
  // for even orders, one lower for odd orders -- the old value left order-5
  // nodes permanently under-filled after a split).
  var min_keys = (tree.order - 2) / 2;

  var idx = 0;
  while idx < node.keys.len() && node.keys[idx] < key {
    idx = idx + 1;
  }

  if idx < node.keys.len() && node.keys[idx] == key {
    if node.is_leaf {
      remove_from_leaf(tree, node_idx, idx);
      return true;
    }
    remove_from_internal(tree, node_idx, idx, min_keys);
    return true;
  }

  if node.is_leaf { return false; }

  if idx >= node.children.len() { return false; }
  var child_idx = node.children[idx];

  if tree.store.nodes[child_idx].keys.len() <= min_keys {
    // fill_child returns the NODE INDEX of the (possibly relocated) target
    // child: a merge at child_pos-1 shifts it left. Recursing with the old
    // position instead descended an unrelated node (churn repro op=148).
    // M3: fill_child shadows the child (and any sibling it touches) itself.
    child_idx = fill_child(tree, node_idx, idx, min_keys);
  } else {
    // M3: the descent will mutate this child; shadow it and fix this
    // (already writable) parent.
    var shadowed_child = cow_shadow(tree, child_idx);
    if shadowed_child != child_idx {
      var parent = tree.store.nodes[node_idx];
      parent.children[idx] = shadowed_child;
      ns_set(&mut tree.store, node_idx, parent);
      child_idx = shadowed_child;
    }
  }

  return delete_from_node(tree, child_idx, key);
}

fn remove_from_leaf(tree: &mut BTree, node_idx: Int, pos: Int) {
  var node = tree.store.nodes[node_idx];
  var i = pos;
  while i < node.keys.len() - 1 {
    node.keys[i] = node.keys[i + 1];
    node.values[i] = node.values[i + 1];
    node.payloads[i] = node.payloads[i + 1];
    i = i + 1;
  }
  node.keys.pop();
  node.values.pop();
  node.payloads.pop();
  ns_set(&mut tree.store, node_idx, node);
}

fn remove_from_internal(tree: &mut BTree, node_idx: Int, pos: Int, min_keys: Int) {
  var node = tree.store.nodes[node_idx];
  var key = node.keys[pos];
  var left_child_idx = node.children[pos];
  var right_child_idx = node.children[pos + 1];

  // Predecessor/successor substitution only when the donor subtree can spare
  // a key (the old guard); the Option covers degenerate empty chains inside
  // the donor (order 3), falling through to the merge when neither side can
  // donate. The donor entry's payload moves up with its key/value. M3: the
  // donor read above sees identical content in the shadow copy, so the
  // predecessor is computed BEFORE the donor is shadowed for the delete
  // descent.
  if tree.store.nodes[left_child_idx].keys.len() > min_keys {
    match get_predecessor(tree, left_child_idx) {
      Some(pred) => {
        node.keys[pos] = pred.key;
        node.values[pos] = pred.value;
        node.payloads[pos] = pred.payload;
        var shadowed_left = cow_shadow(tree, left_child_idx);
        if shadowed_left != left_child_idx {
          node.children[pos] = shadowed_left;
          left_child_idx = shadowed_left;
        }
        ns_set(&mut tree.store, node_idx, node);
        delete_from_node(tree, left_child_idx, pred.key);
        return;
      }
      None => {}
    }
  }

  if tree.store.nodes[right_child_idx].keys.len() > min_keys {
    match get_successor(tree, right_child_idx) {
      Some(succ) => {
        node.keys[pos] = succ.key;
        node.values[pos] = succ.value;
        node.payloads[pos] = succ.payload;
        var shadowed_right = cow_shadow(tree, right_child_idx);
        if shadowed_right != right_child_idx {
          node.children[pos + 1] = shadowed_right;
          right_child_idx = shadowed_right;
        }
        ns_set(&mut tree.store, node_idx, node);
        delete_from_node(tree, right_child_idx, succ.key);
        return;
      }
      None => {}
    }
  }

  // Both donors are at the floor: merge the two children around the
  // separator. Safe here because this node holds at least the separator key
  // (the caller only reaches this with a key at `pos`). M3: merge_children
  // shadows the surviving (left) child and returns its fresh index.
  let merged_idx = merge_children(tree, node_idx, pos);
  delete_from_node(tree, merged_idx, key);
}

// True when the subtree rooted at node_idx holds at least one key. Keyless
// chains appear only when min_keys == 0; walking them repeatedly is fine at
// this scale (depth-bounded, and merges keep the tree shallow).
fn subtree_has_key(tree: &BTree, node_idx: Int) -> Bool {
  let node = tree.store.nodes[node_idx];
  if node.keys.len() > 0 { return true; }
  if node.is_leaf { return false; }
  var i = 0;
  while i < node.children.len() {
    if subtree_has_key(tree, node.children[i]) { return true; }
    i = i + 1;
  }
  return false;
}

// One tree entry located by a donor walk: key/value/payload travel together.
type NodeEntry = {
  key: Int;
  value: Int;
  payload: Vec[Int];
}

// In-order predecessor (max) of the subtree at node_idx, or None when the
// subtree is empty. The rightmost path may pass through keyless nodes: when
// the rightmost subtree is empty the predecessor is this node's own last
// key; an empty leaf has none. (The old rightmost-only descent read
// `keys[-1]` on an empty leaf and materialized out-of-bounds garbage -- the
// order-3 defect in xiom.btree SPEC 2.3.)
fn get_predecessor(tree: &BTree, node_idx: Int) -> Option[NodeEntry] {
  var cur = node_idx;
  var guard = 0;
  while guard < 64 {
    guard = guard + 1;
    let node = tree.store.nodes[cur];
    if node.is_leaf {
      if node.keys.len() == 0 { return None; }
      let last = node.keys.len() - 1;
      return Some(NodeEntry{ key: node.keys[last], value: node.values[last],
                             payload: node_payload(&node, last) });
    }
    let last_child = node.children[node.children.len() - 1];
    if subtree_has_key(tree, last_child) {
      cur = last_child;
    } else {
      if node.keys.len() == 0 { return None; }
      let last = node.keys.len() - 1;
      return Some(NodeEntry{ key: node.keys[last], value: node.values[last],
                             payload: node_payload(&node, last) });
    }
  }
  return None;
}

fn get_successor(tree: &BTree, node_idx: Int) -> Option[NodeEntry] {
  var cur = node_idx;
  var guard = 0;
  while guard < 64 {
    guard = guard + 1;
    let node = tree.store.nodes[cur];
    if node.is_leaf {
      if node.keys.len() == 0 { return None; }
      return Some(NodeEntry{ key: node.keys[0], value: node.values[0],
                             payload: node_payload(&node, 0) });
    }
    let first_child = node.children[0];
    if subtree_has_key(tree, first_child) {
      cur = first_child;
    } else {
      if node.keys.len() == 0 { return None; }
      return Some(NodeEntry{ key: node.keys[0], value: node.values[0],
                             payload: node_payload(&node, 0) });
    }
  }
  return None;
}

// Merge children[pos] + separator + children[pos+1] into the left child.
// M3: the left child is shadowed first (the right child is absorbed verbatim
// and stays untouched for pinned views; it becomes live-garbage). Returns the
// fresh index of the merged child so callers can descend into it.
fn merge_children(tree: &mut BTree, parent_idx: Int, pos: Int) -> Int {
  var parent = tree.store.nodes[parent_idx];
  var left_idx = parent.children[pos];
  var shadowed_left = cow_shadow(tree, left_idx);
  if shadowed_left != left_idx {
    parent.children[pos] = shadowed_left;
    left_idx = shadowed_left;
  }
  var right_idx = parent.children[pos + 1];

  var left = tree.store.nodes[left_idx];
  var right = tree.store.nodes[right_idx];

  left.keys.push(parent.keys[pos]);
  left.values.push(parent.values[pos]);
  left.payloads.push(node_payload(&parent, pos));

  var i = 0;
  while i < right.keys.len() {
    left.keys.push(right.keys[i]);
    left.values.push(right.values[i]);
    left.payloads.push(node_payload(&right, i));
    i = i + 1;
  }

  i = 0;
  while i < right.children.len() {
    left.children.push(right.children[i]);
    i = i + 1;
  }

  ns_set(&mut tree.store, left_idx, left);

  i = pos;
  while i < parent.keys.len() - 1 {
    parent.keys[i] = parent.keys[i + 1];
    parent.values[i] = parent.values[i + 1];
    parent.payloads[i] = parent.payloads[i + 1];
    i = i + 1;
  }
  parent.keys.pop();
  parent.values.pop();
  parent.payloads.pop();

  i = pos + 1;
  while i < parent.children.len() - 1 {
    parent.children[i] = parent.children[i + 1];
    i = i + 1;
  }
  parent.children.pop();

  ns_set(&mut tree.store, parent_idx, parent);

  if parent.keys.len() == 0 && parent_idx == tree.root {
    tree.root = left_idx;
  }
  return left_idx;
}

fn fill_child(tree: &mut BTree, parent_idx: Int, child_pos: Int, min_keys: Int) -> Int {
  var parent = tree.store.nodes[parent_idx];

  // A keyless parent is a pass-through node (only possible when min_keys ==
  // 0, i.e. order 3): there is no sibling arrangement to borrow from and no
  // key to merge down; merging would read `children[pos + 1]` past the end.
  // Descending straight through is correct -- the child keeps its own count.
  // M3: the pass-through child is descended into, so it must be writable.
  if parent.keys.len() == 0 {
    var through_idx = parent.children[child_pos];
    var shadowed_through = cow_shadow(tree, through_idx);
    if shadowed_through != through_idx {
      var pp = tree.store.nodes[parent_idx];
      pp.children[child_pos] = shadowed_through;
      ns_set(&mut tree.store, parent_idx, pp);
      through_idx = shadowed_through;
    }
    return through_idx;
  }

  if child_pos > 0 {
    var left_sib_idx = parent.children[child_pos - 1];
    if tree.store.nodes[left_sib_idx].keys.len() > min_keys {
      borrow_from_left(tree, parent_idx, child_pos);
      return tree.store.nodes[parent_idx].children[child_pos];
    }
  }

  if child_pos < parent.children.len() - 1 {
    var right_sib_idx = parent.children[child_pos + 1];
    if tree.store.nodes[right_sib_idx].keys.len() > min_keys {
      borrow_from_right(tree, parent_idx, child_pos);
      return tree.store.nodes[parent_idx].children[child_pos];
    }
  }

  if child_pos > 0 {
    let _ = merge_children(tree, parent_idx, child_pos - 1);
    return tree.store.nodes[parent_idx].children[child_pos - 1];
  }
  let _ = merge_children(tree, parent_idx, child_pos);
  return tree.store.nodes[parent_idx].children[child_pos];
}

fn borrow_from_left(tree: &mut BTree, parent_idx: Int, child_pos: Int) {
  var parent = tree.store.nodes[parent_idx];
  var child_idx = parent.children[child_pos];
  var left_idx = parent.children[child_pos - 1];
  // M3: both participants are re-written below; shadow them and fix the
  // (already writable) parent local, which is ns_set at the end.
  var shadowed_child = cow_shadow(tree, child_idx);
  if shadowed_child != child_idx {
    parent.children[child_pos] = shadowed_child;
    child_idx = shadowed_child;
  }
  var shadowed_left = cow_shadow(tree, left_idx);
  if shadowed_left != left_idx {
    parent.children[child_pos - 1] = shadowed_left;
    left_idx = shadowed_left;
  }
  var child = tree.store.nodes[child_idx];
  var left = tree.store.nodes[left_idx];
  var left_last = left.keys.len() - 1;

  child.keys.push(0);
  child.values.push(0);
  child.payloads.push(Vec[Int].new());

  var i = child.keys.len() - 1;
  while i > 0 {
    child.keys[i] = child.keys[i - 1];
    child.values[i] = child.values[i - 1];
    child.payloads[i] = child.payloads[i - 1];
    i = i - 1;
  }
  child.keys[0] = parent.keys[child_pos - 1];
  child.values[0] = parent.values[child_pos - 1];
  child.payloads[0] = node_payload(&parent, child_pos - 1);

  if left.children.len() > 0 {
    // Internal nodes only: carry the sibling's last child pointer across.
    // (The old code pushed the placeholder even for leaf children, leaving
    // a spurious child index on every leaf borrow.)
    child.children.push(0);
    i = child.children.len() - 1;
    while i > 0 {
      child.children[i] = child.children[i - 1];
      i = i - 1;
    }
    child.children[0] = left.children[left.children.len() - 1];
    left.children.pop();
  }

  parent.keys[child_pos - 1] = left.keys[left_last];
  parent.values[child_pos - 1] = left.values[left_last];
  parent.payloads[child_pos - 1] = node_payload(&left, left_last);
  left.keys.pop();
  left.values.pop();
  left.payloads.pop();

  ns_set(&mut tree.store, parent_idx, parent);
  ns_set(&mut tree.store, child_idx, child);
  ns_set(&mut tree.store, left_idx, left);
}

fn borrow_from_right(tree: &mut BTree, parent_idx: Int, child_pos: Int) {
  var parent = tree.store.nodes[parent_idx];
  var child_idx = parent.children[child_pos];
  var right_idx = parent.children[child_pos + 1];
  // M3: both participants are re-written below; shadow them and fix the
  // (already writable) parent local, which is ns_set at the end.
  var shadowed_child = cow_shadow(tree, child_idx);
  if shadowed_child != child_idx {
    parent.children[child_pos] = shadowed_child;
    child_idx = shadowed_child;
  }
  var shadowed_right = cow_shadow(tree, right_idx);
  if shadowed_right != right_idx {
    parent.children[child_pos + 1] = shadowed_right;
    right_idx = shadowed_right;
  }
  var child = tree.store.nodes[child_idx];
  var right = tree.store.nodes[right_idx];

  child.keys.push(parent.keys[child_pos]);
  child.values.push(parent.values[child_pos]);
  child.payloads.push(node_payload(&parent, child_pos));

  if right.children.len() > 0 {
    child.children.push(right.children[0]);
  }

  parent.keys[child_pos] = right.keys[0];
  parent.values[child_pos] = right.values[0];
  parent.payloads[child_pos] = node_payload(&right, 0);

  var i = 0;
  while i < right.keys.len() - 1 {
    right.keys[i] = right.keys[i + 1];
    right.values[i] = right.values[i + 1];
    right.payloads[i] = right.payloads[i + 1];
    i = i + 1;
  }
  right.keys.pop();
  right.values.pop();
  right.payloads.pop();

  if right.children.len() > 0 {
    i = 0;
    while i < right.children.len() - 1 {
      right.children[i] = right.children[i + 1];
      i = i + 1;
    }
    right.children.pop();
  }

  ns_set(&mut tree.store, parent_idx, parent);
  ns_set(&mut tree.store, child_idx, child);
  ns_set(&mut tree.store, right_idx, right);
}

pub fn btree_range_query(tree: &BTree, low: Int, high: Int) -> Vec[Int]
  requires: low <= high
{
  var results = Vec[Int].new();
  collect_range(tree, tree.root, low, high, results);
  return results;
}

pub fn collect_range(tree: &BTree, node_idx: Int, low: Int, high: Int, results: &mut Vec[Int]) {
  var node = tree.store.nodes[node_idx];
  if node.is_leaf {
    var i = 0;
    while i < node.keys.len() {
      if node.keys[i] >= low && node.keys[i] <= high {
        results.push(node.values[i]);
      }
      i = i + 1;
    }
    return;
  }

  var i = 0;
  while i < node.keys.len() && node.keys[i] < low {
    i = i + 1;
  }

  if i < node.children.len() {
    collect_range(tree, node.children[i], low, high, results);
  }

  while i < node.keys.len() && node.keys[i] <= high {
    results.push(node.values[i]);
    i = i + 1;
    if i < node.children.len() {
      collect_range(tree, node.children[i], low, high, results);
    }
  }
}

pub fn btree_size(tree: &BTree) -> Int {
  return count_keys(tree, tree.root);
}

pub fn count_keys(tree: &BTree, node_idx: Int) -> Int {
  var node = tree.store.nodes[node_idx];
  var total = node.keys.len();
  if !node.is_leaf {
    var i = 0;
    while i < node.children.len() {
      total = total + count_keys(tree, node.children[i]);
      i = i + 1;
    }
  }
  return total;
}

pub fn btree_min(tree: &BTree) -> Option[Int] {
  // Subtree min: the leftmost in-order key. Empty pass-through chains (order
  // 3) can end the leftmost path in an empty node while the min key sits at an
  // internal node -- get_successor handles both, and the old leftmost-only
  // descent returned None whenever the terminal leaf was empty.
  match get_successor(tree, tree.root) {
    Some(p) => { return Some(p.value); }
    None => { return None; }
  }
}

pub fn btree_max(tree: &BTree) -> Option[Int] {
  // See btree_min: the rightmost path can end in an empty node (order 3);
  // get_predecessor falls back to the owning internal node's last key.
  match get_predecessor(tree, tree.root) {
    Some(p) => { return Some(p.value); }
    None => { return None; }
  }
}

pub fn btree_to_vec(tree: &BTree) -> Vec[Int] {
  var results = Vec[Int].new();
  traverse_inorder(tree, tree.root, results);
  return results;
}

fn traverse_inorder(tree: &BTree, node_idx: Int, results: &mut Vec[Int]) {
  var node = tree.store.nodes[node_idx];
  if node.is_leaf {
    var i = 0;
    while i < node.keys.len() {
      results.push(node.values[i]);
      i = i + 1;
    }
    return;
  }
  var i = 0;
  while i < node.keys.len() {
    if i < node.children.len() {
      traverse_inorder(tree, node.children[i], results);
    }
    results.push(node.values[i]);
    i = i + 1;
  }
  if i < node.children.len() {
    traverse_inorder(tree, node.children[i], results);
  }
}
