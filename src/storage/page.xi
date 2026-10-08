// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.db.storage.page
use xiom.db.config;

// Low-level buffered-storage primitives. A `Page` is a fixed-capacity byte
// block guarded by a checksum; the `BufferPool` is a direct-mapped page cache;
// the `StorageEngine` binds a configuration to a pool. This layer is currently
// in-memory: pages live in the pool's slots, not on disk. Phase 1 replaces the
// direct-mapped pool and hand-rolled checksum with the xiom-core pager/replacer.

pub type Page = {
  id: Int;
  data: Vec[Int];
  checksum: Int;
} derive[Clone]

pub fn Page.new(id: Int, data: Vec[Int], checksum: Int) -> Page
  requires: data.len() <= 4096
{
  return Page{ id: id, data: data, checksum: checksum };
}

// A page is valid iff its stored checksum matches a fresh checksum of its data.
// This is the on-read integrity gate that surfaces torn or corrupted pages.
pub fn Page.is_valid() -> Bool {
  return checksum == page_checksum(data);
}

// Additive rolling checksum over the page bytes. Cheap and order-independent;
// Phase 1 upgrades this to CRC32C for stronger torn-write detection.
fn page_checksum(data: &Vec[Int]) -> Int {
  var sum: Int = 0;
  var i = 0;
  while i < data.len() {
    sum = sum + data[i];
    i = i + 1;
  }
  return sum;
}

// Compute the canonical checksum for a byte buffer. Exposed so writers can seal
// a page before caching it.
pub fn page_compute_checksum(data: &Vec[Int]) -> Int {
  return page_checksum(data);
}

pub type BufferPool = {
  pages: Vec[Option[Page]];
  capacity: Int;
  hits: Int;
  misses: Int;
}

pub fn BufferPool.new(capacity: Int) -> BufferPool
  requires: capacity >= 1
{
  var pages = Vec[Option[Page]].new();
  var i = 0;
  while i < capacity {
    pages.push(None);
    i = i + 1;
  }
  return BufferPool{ pages: pages, capacity: capacity, hits: 0, misses: 0 };
}

pub fn BufferPool.put(pool: &mut BufferPool, page: Page) {
  var idx = page_id_index(page.id, pool.capacity);
  var current = pool.pages[idx];
  match current {
    None => { pool.misses = pool.misses + 1; }
    Some(_) => { pool.hits = pool.hits + 1; }
  }
  // C-ORBIT-02 workaround: assigning an Option into a Vec[Option[T]] element
  // poisons the slot on v0.64.0 -- the value then matches NEITHER `None` nor
  // `Some(_)` and every match over it silently runs no arm (repro:
  // docs/repro/option-vec-assign/). Rebuild the slot instead of assigning.
  // Revisit when the compiler fix lands; Phase 1 replaces this pool with the
  // xiom-core pager regardless.
  var rebuilt = Vec[Option[Page]].new();
  var i = 0;
  while i < pool.pages.len() {
    if i == idx {
      rebuilt.push(Some(page));
    } else {
      rebuilt.push(pool.pages[i]);
    }
    i = i + 1;
  }
  pool.pages = rebuilt;
}

// Direct-mapped slot selection: page id modulo capacity. O(1) but collision
// prone; Phase 1 introduces an associative frame table + clock replacer.
fn page_id_index(id: Int, capacity: Int) -> Int {
  return id % capacity;
}

pub fn BufferPool.get(pool: &BufferPool, page_id: Int) -> Option[Page] {
  var idx = page_id_index(page_id, pool.capacity);
  var entry = pool.pages[idx];
  match entry {
    None => None,
    Some(p) => {
      if p.id == page_id {
        Some(p)
      } else {
        None
      }
    }
  }
}

pub fn BufferPool.hit_ratio(pool: &BufferPool) -> Float64 {
  var total = pool.hits + pool.misses;
  if total == 0 { return 0.0; }
  return (pool.hits as Float64) / (total as Float64);
}

pub type StorageEngine = {
  config: DatabaseConfig;
  buffer_pool: BufferPool;
}

pub fn StorageEngine.new(config: DatabaseConfig) -> StorageEngine {
  var bp = BufferPool.new(config.buffer_pool_capacity);
  return StorageEngine{ config: config, buffer_pool: bp };
}

pub fn StorageEngine.cache_page(eng: &mut StorageEngine, page: Page) {
  // C-ORBIT-04 workaround: a method call on a nested field receiver
  // (eng.buffer_pool.put(page)) mutates a temporary copy on v0.64.0; copy
  // the field out, mutate it, and write it back. Repro:
  // docs/repro/nested-field-mut/probe.xi (A/C lose the write, B/D keep it).
  var bp = eng.buffer_pool;
  bp.put(page);
  eng.buffer_pool = bp;
}

pub fn StorageEngine.lookup_page(eng: &StorageEngine, page_id: Int) -> Option[Page] {
  // Read-only nested receiver: bind to a local first (same class).
  var bp = eng.buffer_pool;
  return bp.get(page_id);
}
