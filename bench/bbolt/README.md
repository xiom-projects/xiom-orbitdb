<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# bench/bbolt -- BENCH-1 cross-engine driver (bbolt side)

Mirrors `tests/probes/probe_ycsb.xi` (orbitdb) and the generated SQLite
phase scripts: same deterministic op stream, same phases, same output lines.

## Build

```
cd bench/bbolt
go build -o bin\bbolt-bench.exe .
$env:GOOS="linux"; $env:GOARCH="amd64"; go build -o bin\bbolt-bench-linux-amd64 .
```

## Run

```
bin\bbolt-bench.exe -file <path> -n 50000 -valsize 8 -sync=true -batch 1 -phase all
```

Flags: `-file` (required), `-n` (default 50000, keys 0..n-1), `-valsize`
8|100 (default 8), `-sync=true|false` (default true; false = `NoSync`;
Go bool flags require the `=` form), `-batch` ops per commit group
(default 1), `-phase` all|load|read|update|scan|delete, `-seed`
(default 12345), `-scans` (default n/100, length 100), `-deletes`
(default n/10).

## Determinism (shared across engines)

- LCG stream: `state = (state*1103515245 + 12345) % 2147483648`; op key =
  `state % n`; scan start = `state % (n-100)`.
- Load inserts keys 0..n-1 in order (all engines).
- Read/update/scan/delete each start their own fresh stream at the seed.
- Values: `-valsize 8` = big-endian `key*7+1`; `-valsize 100` =
  zero-padded 8-digit key + 92 `x` (ASCII, 100 bytes).
- scan/delete phases run only with `-valsize 8` (typed-row parity: point
  ops only for the 100-byte matrix -- see docs/BENCH-1.md).

## Output (parsed by scripts/bench_cross.{ps1,sh})

```
ycsb bbolt <phase> n=<ops> ms=<ms> ops_s=<ops*1000/ms>
ycsb bbolt verify count=<count> ok=<0|1>
ycsb bbolt done ok=<0|1> v=8|100 batch=<b> sync=<0|1>
```

Exit 0 on success (verify ok), 1 on error or verify mismatch.
