<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Checklist -- byte-page format v2 (M1.2)

> Companion to `docs/BYTE-PAGE-FORMAT-V2.md` (the frozen design). Convention:
> `[x]` done with committed evidence; `[~]` in progress/blocked with a named
> dependency; `[ ]` not started. Every code slice keeps the full evidence
> matrix: suite x2 + affected crash harness x2 + fuzz, Windows + WSL.

## S1 -- pure codec (unblocked today)

- [ ] `src/storage/block.xi`: `block_encode_page/decode_page`,
      `block_encode_header/decode_header`, `block_kind_is_free`
- [ ] Strict decode: length 4096, magic/version/kind, `len <= 4064`, CRC32C,
      zero padding; every failure is `None` (no partial blocks)
- [ ] KATs (hex literal tables) in the suite: one page block, one header slot
- [ ] Boundary matrix: `len` 0 / 1 / 4064 accepted, 4065 rejected
- [ ] Corruption matrix: flip a byte in each header field, payload, padding
- [ ] Fuzz extension: random page sets encode->decode round-trip vs model
- [ ] Evidence: suite x2 Win + WSL (codec tests only, no IO change)

## S2 -- block store over the shim

- [ ] `src/storage/byte_io.xi`: the six shim functions (O(file) fallbacks,
      documented; no `io.*` block IO anywhere else)
- [ ] `src/storage/block_store.xi`: create/open/read/write_batch/append/
      commit (inactive header slot last) / compact (temp+rename)
- [ ] Page directory rebuilt at open (scan valid blocks, latest generation
      per page_id)
- [ ] Probe mirroring `probe_page_file.xi`: append / latest-wins / read_all /
      compaction / ids
- [ ] Crash harness: hard-kill after page blocks / after inactive header /
      mid-header-slot; torn tail; torn header slot; uncommitted generation
      ignored; compaction crash; x2 Win + WSL
- [ ] Fuzz: block store vs model (random pages, kills at named states)

## S3 -- DBFile integration + default flip

- [ ] `DatabaseConfig.page_format` (`"v1" | "v2"`, default `"v1"`)
- [ ] `page_file_v2_migrate(v1, v2)` (idempotent) + auto-detect at open
- [ ] `tuple_fits_page` consults store capacity (v1 4096 / v2 4064)
- [ ] Full matrix with v2: suite x2, page/db crash x2, fuzz, 2000-key soak
- [ ] Flip the default to v2; re-run the full matrix; FORMATS.md "3v2"
      section + API.md + RUNBOOK updated in the same commit

## S4 -- stdlib byte IO + fsync swap

- [ ] Swap the shim to real `read_at`/`write_at`/`append_file_bytes`/
      `truncate`/`fsync` when the stdlib rows land (STDLIB-WISHLIST rows 1/4/5)
- [ ] Re-run the S2/S3 matrix; record before/after bench numbers (G1)
- [ ] Unblocks: M1.1b lazy node load, C3 pager seam, M2.1 fault injection
