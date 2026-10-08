# Relay: ORBITDB -> stdlib lane (paste-ready)

**From:** ORBITDB lane (`E:\xiom-projects\xiom-orbitdb`, embedded database
engine: B-Tree, WAL, crash recovery). **Pin:** compiler v0.64.0, stdlib
`a677338` (2026-10-08). Full table: `docs/STDLIB-WISHLIST-ORBITDB.md`.

Hi stdlib lane -- ORBITDB bootstrapped a real durable-WAL probe this
session: append records -> hard kill -> torn tail -> reopen/replay -> heal,
GREEN on Windows and WSL, plus a 200-record soak
(`tests/probes/probe_wal_file.xi`, `scripts/crash_test.{ps1,sh}`). The WAL
wishlist rows, in priority order for a database:

1. **fsync/durability**: no `fsync`/`FlushFileBuffers`/`_commit` wrapper
   anywhere in the runtime -- WAL "durable" today means OS write-back. This
   is the row between ORBITDB and an honest Phase-2 durability claim
   (`docs/wal-and-recovery.md` states the limit). PULSE filed it first;
   ORBITDB re-confirms with a storage-engine use case.
2. **`io.read_file_lines` should normalize a trailing `\r`** (or document
   the requirement). On Windows-produced CRLF segments, `parse_int` gets
   `"10\r"`, records are silently dropped, replay count goes wrong
   (reproduced: applied=0 until every line went through `trim.str_trim`).
3. **Append with tail repair + flush**: `io.append_line_sync(path, line)`
   that ensures a newline boundary before writing and flushes. Every durable
   log consumer hand-rolls this (ORBITDB `heal_tail`, PULSE store); our
   crash test failed (`applied=3` vs 4) until tail repair landed.
4. **Truncate / checkpoint primitive**: `io.rename` exists, nothing
   truncates in place -> WAL checkpoint/segmentation has no primitive yet
   (ROADMAP Phase 2).
5. **Byte-level IO**: `io.read_bytes`/`write_bytes`/append-bytes. Phase 1
   needs a byte-packed page codec; today everything is `Str`-based, and
   `xiom.hash.crc.crc32c(&Vec[UInt8])` cannot be fed from disk without it.
6. **Tail check without reading the whole file**: `io.file_last_byte` /
   `ends_with_newline`; our heal currently reads the full segment per
   append (quadratic).

Positives to keep: `io.sleep(ms)` is load-bearing for killable hang loops
(an empty spin loop is optimized away), `io.append_line`/`read_file_lines`
are workable, `env.var_or` is the right probe seam, and `xiom.hash.crc.crc32c`
is ready for the Phase-1 page checksum the moment byte IO lands. Also: the
old `xiom.test` `TestCase` type is gone (`assert` returns `TestResult`) --
a doc note would help consumers; ORBITDB migrated its 93-test suite.

Happy to be the acceptance harness for rows 1-3: the crash test is a
ready-made consumer fixture for fsync + append-repair + replay.
