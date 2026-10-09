# Isolation & Multi-Handle Model

> **Decision record (D3):** ORBITDB is **single-writer** today. A handle that
> has fallen behind another writer refuses its writes; readers see the state
> from their open time. MVCC is deferred to Phase 3 with explicit
> prerequisites (below). This file is the reference for the multi-handle
> rules enforced by `db_file_open` plus the stale-handle guard.

## Current model

1. **Single writer.** A database path (`<path>` + `<path>.snap`) must have at
   most one *writing* handle at a time -- in one process or several.
2. **Stale-write refusal (optimistic guard, no lock file).** Every `DBFile`
   records the WAL segment size at its last own write (`wal_bytes`). Each
   write path -- `db_file_put` / `db_file_delete`, all `db_file_txn_*`, and
   `db_file_checkpoint` -- first checks `io.file_size(path) == wal_bytes` and
   refuses (`false` / `-1`) on a mismatch. The first writer wins; the other
   handle must `db_file_open` again before writing. Crash-safe by
   construction: there is no persistent lock that a hard kill could leave
   behind. Read-only use of a stale handle is safe and sees the state from
   its open time; only writes are refused.
3. **Open-time consistency.** `db_file_open` loads the newest committed
   snapshot generation and replays the WAL tail, so a handle's tree is a
   consistent image of the database at open (plus its own later writes).
4. **Transactions (D2).** One active transaction per handle; operations are
   logged as they happen but applied only at commit; a crash before commit
   discards them; a dangling window is finalized with an Abort record on
   open. No cross-transaction isolation is needed while writers are
   serialized.

## What this is not

- Not MVCC: no version chains, no snapshot timestamps per key, no
  transaction-id visibility rules, no version garbage collection.
- Not a lock: nothing stops a second process from opening the same path; the
  guard only prevents *interleaved writes* from corrupting the segment once
  the sizes diverge. Any external append is detected on the next write.

## MVCC (deferred -- Phase 3)

Prerequisites before version-aware reads are meaningful:

1. A pager with pinned/evictable pages (C3, external substrate): version
   chains need page-level indirection.
2. Transaction ids persisted in pages (or a visibility map), commit
   timestamps, and reader snapshots.
3. Version GC integrated with checkpoints: the snapshot writer must drop dead
   versions.
4. A concurrency story (threads or multi-process with OS-level locking),
   which the platform does not provide today.

Until then, correctness comes from serializing writers; a reader that needs a
frozen view opens its own handle (open-time snapshot) and does not write.

## Detectable vs undetectable (tests)

`tests/test_conformance.xi` (`db_file: stale handle refuses writes +
checkpoint`) pins the behavior: two handles -> the second's `put`, `delete`,
`txn_begin` and `checkpoint` are refused after the first writes; a fresh open
works; the established writer continues; the final reopen sees exactly the
surviving keys. Undetectable by design: a read-only stale handle (safe), and
two handles that never interleave writes.
