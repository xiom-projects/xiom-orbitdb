<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# XIOM ORBITDB -> stdlib lane: wishlist

**Relay:** hand this file to the stdlib-lane session. ORBITDB is a consumer
lane; it never edits `E:\xiom-lang\stdlib`. Evidence paths are from
`E:\xiom-projects\xiom-orbitdb` (app context) or exact stdlib `file:line` on
the pin below.

**Pin:** compiler v0.64.0, stdlib `a677338` (2026-10-08T12:27:20+03:00),
`XIOM_STDLIB=E:\xiom-lang\stdlib`, `XIOM_RUNTIME_DIR` retired (env-free).

**Context:** ORBITDB is a durable embedded database. It just bootstrapped a
real append-only WAL segment (text records today) with hard-kill crash
reopen, torn-tail healing and a 200-record soak -- all green on Windows and
WSL. The rows below are the stdlib gaps that stand between that probe and a
byte-level, power-loss-honest storage engine.

## Open items

| Need | Evidence (file:line or app path) | Workaround | Blocks |
|---|---|---|---|
| **Durable flush: `fsync`/`FlushFileBuffers`/`_commit` wrapper (`io.sync_file(path)` or fd-level sync).** No fsync anywhere in `runtime/*.c` (PULSE confirmed 2026-10-05; ORBITDB re-confirms: ORBITDB's "durable" WAL is OS write-back only). | ORBITDB `tests/probes/probe_wal_file.xi` + `scripts/crash_test.ps1/.sh`: correct vs simulated process kill, but power-loss tail loss is unmitigated; `docs/wal-and-recovery.md` states the honest limit. | torn-tail healing (`io.append_line` newline repair) + accept write-back; document honesty | Phase 2 durability claims; `db_close` checkpoint; "durable" in README/SPEC |
| **File truncate / atomic checkpoint primitive** (`io.truncate_file(path, size)` or fd-based). `io.rename` exists (`io.xi:399`, maps to `MoveFileExA` REPLACE per PULSE); nothing truncates in place. | ROADMAP Phase 2 "Checkpointing -- truncate WAL after a durable checkpoint"; ORBITDB WAL has no truncate story yet. | rewrite a fresh segment + `rename` (compaction pattern) | WAL checkpoint/segment recycling; bounded disk growth |
| **`io.read_file_lines` should normalize a trailing `\r`** (CRLF-produced files) or document the requirement. Today `str_split`/`parse_int` receive `"10\r"` and fail, silently dropping records. | ORBITDB `tests/probes/probe_wal_file.xi`: replay applied=0 until every line went through `trim.str_trim`; Windows `Set-Content` + `read_file_lines` reproduced it directly. | `trim.str_trim(line)` per line (probe does this) | any consumer parsing line files on Windows; silent record loss in replay |
| **Byte-level file IO: `io.read_bytes(path) -> Result[Vec[UInt8], IOError]` / `io.write_bytes` / append-bytes.** Today only `Str`-based `read_file`/`write_file`/`append_file` exist (`io.xi:213,240,265`). | ROADMAP Phase 1 byte-packed tuple codec + CRC32C page checksums; `storage/tuple.xi tuple_encode/decode` are `Vec[Int]` stand-ins. | keep `Vec[Int]` codec (non-portable, not byte-true) | real page format; `xiom.hash.crc.crc32c(&Vec[UInt8])` cannot be fed from disk |
| **Append with tail repair + flush: one call** (`io.append_line_sync(path, line)`), i.e. append a newline if the file does not end with one, then write the record. Every durable-log consumer hand-rolls this (ORBITDB `probe_wal_file.heal_tail`; PULSE store did the same). | ORBITDB crash test: appending after a torn tail without repair merges the new record onto the torn line (reproduced: `applied=3` instead of 4 until `heal_tail`); PULSE `crash_test` heal step | local `heal_tail` (read whole file to check last char -- O(n) per append!) | crash-safe appends without O(n) rescans; part of the fsync row |
| **Tail check without reading the whole file** (`io.file_last_byte` or `io.ends_with_newline(path)`). ORBITDB's heal reads the entire segment per append. `io.file_size` exists (`io.xi:973`) but no random access/seek. | ORBITDB `probe_wal_file.heal_tail` reads the full file per record; fine at 2.8 KB, quadratic at segment scale | read whole file (current) | O(1) healed appends; large WAL segments |

## Positive confirmations (please keep)

- **`io.sleep(ms)`** is load-bearing for crash-test hang loops: an empty
  spin loop (`while spin >= 0 { spin = spin + 1; }`) was optimized away in
  the writer and the process exited early; `io.sleep` keeps the process
  alive and killable (`tests/probes/probe_wal_file.xi run_write`).
- **`io.append_line` creates the file and appends newline-terminated
  records**; `io.read_file_lines` returns `Result[Vec[Str], IOError]` and
  includes a trailing empty line for a final newline -- handled by the
  skip-empty rule.
- **`xiom.os.env.var_or`** is exactly the right probe/script seam (PULSE
  pattern): all ORBITDB probe modes are env-driven.
- **`xiom.hash.crc.crc32c(data: &Vec[UInt8]) -> UInt32`** exists
  (`xiom/hash/crc.xi:107`) -- ready for the Phase 1 page checksum the moment
  byte IO or a byte codec lands. `storage/page.xi` currently uses an
  additive checksum.
- **String kit**: `str_split`, `str_trim`, `str_ends_with`, `parse_int`
  cover record codecs; the submodule-import pattern (`use xiom.string.split;`
  then `split.str_split`) is required but clean.
- **`xiom.test` API drift handled consumer-side:** `assert(cond, name)`
  returns `TestResult` (not the old `TestCase`); ORBITDB migrated the whole
  93-test suite. Consider a doc note in `xiom.test`.

## Notes for the stdlib lane's own coverage

- `probe_wal_file.xi` is a ready-made consumer fixture for the fsync and
  append-repair rows: it exercises write -> hard kill -> torn tail -> replay
  -> heal on both platforms (`scripts/crash_test.sh` runs in WSL).
- The `read_file_lines` CR row is invisible on LF-only Linux checkouts; it
  bit ORBITDB because the lane runs the same code on Windows first.
