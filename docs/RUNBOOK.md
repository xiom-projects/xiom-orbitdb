# ORBITDB Operations Runbook

> How to build, test, soak, fuzz, benchmark, and recover ORBITDB on Windows and
> WSL. Every command exits non-zero on failure; treat a timeout (exit 124) and
> an empty run as red.

## 1. Environment

| Item | Windows | WSL (Ubuntu) |
|------|---------|--------------|
| Toolchain | `scripts\dev-env.ps1` (resolves `XIOM_COMPILER`) | `scripts/dev-env.sh` (`~/.local/bin/xiom`) |
| Compiler | v0.64.1 (`%LOCALAPPDATA%\xiom.new\bin\xiom.exe`) | v0.64.1 |
| Stdlib | `$env:XIOM_STDLIB` = `E:\xiom-lang\stdlib` | `/mnt/e/xiom-lang/stdlib` |
| Runner | `scripts\run.ps1 FILE -TimeoutSec N` | `scripts/run.sh FILE --timeout-sec N` |

WSL note: the default distro on this machine is `docker-desktop` (no bash);
always target Ubuntu explicitly:

```bash
wsl.exe -d Ubuntu bash -lc "cd /mnt/e/xiom-projects/xiom-orbitdb && scripts/run.sh tests/test_conformance.xi --timeout-sec 300"
```

Shell scripts and `.xi` files must stay LF; `.ps1` files are CRLF
(`.gitattributes` enforces this on commit).

## 2. Everyday commands

| Purpose | Command | Notes |
|---------|---------|-------|
| Conformance suite | `scripts/run.ps1 tests\test_conformance.xi -TimeoutSec 300` | 127 tests; expect `127/127` and exit 0. |
| WAL crash harness | `scripts\crash_test.ps1 -Events 20 -TimeoutSec 90` | writer -> hard kill -> torn tail -> reopen -> verify -> heal -> verify+1. |
| Page crash harness | `scripts\page_crash_test.ps1 -Pages 20 -TimeoutSec 120` | Use 120s: the writer's first compile can exceed 90s under load. |
| DB crash harness | `scripts\db_crash_test.ps1 -Keys 20 -Tail 3 -Tx 5 -TimeoutSec 90` | Five scenarios (WAL-only, snapshot-only, snapshot+tail, uncommitted txn, committed txn); 25 checks. Prefix `ORBITDB_DB_FORMAT=v2` (env) to run the whole matrix with v2 byte-block snapshots (same 25 checks; GREEN x2 both platforms). |
| Hybrid crash harness | `scripts\hybrid_crash_test.ps1 -Keys 1000 -TimeoutSec 240` | ORBITDB <-> XVECTOR: one writer drives both stores, hard kill, torn row tail, reopen + repair + 100% join integrity; second verify idempotent. Needs the sibling `xiom-xvector` checkout (source roots in `tests/hybrid/xiom.toml`). |
| Block crash harness | `scripts\block_crash_test.ps1 -Pages 60 -Batch 10 -TimeoutSec 240` | M1.2 S2: four kill states (pages2 / full2 / midheader / compacted) + torn tail + reopen + recovery append; 8 checks. Kill lands at quiescent states only (O(file) shim until S4). |
| Fuzz/property | `scripts\fuzz.ps1 -TimeoutSec 600` | Deterministic; see section 4. |
| Benchmarks | `scripts\bench.ps1 -N 10000` | Numbers summarized in the readiness doc G1 row (`docs/PRODUCTION-READINESS.md`). |
| App build (icon) | `scripts\build.ps1 <source.xi> [-Out out\orbitdb-app.exe]` | Compiles one source into an app binary and embeds `assets/orbitdb.ico` via `--icon` (verified on v0.64.2; `llvm-rc`). `scripts/build.sh` is the Linux/WSL twin (PE icons are Windows-only). |
| Soaks | probe `soak` mode, section 3 | 2000-key policy soak is the standard long path. |

Twin `.sh` scripts accept the kebab-case flags (`--events`, `--pages`,
`--keys`, `--tail`, `--tx`, `--timeout-sec`).

Exit-code semantics: `run.{ps1,sh}` returns the *program's* exit code (parsed
from the compiler's `exit code:` line); 124 = watchdog timeout (process tree
killed); harnesses print `GREEN`/`RED` and exit 0/1.

## 3. Probes and env knobs

| Probe | Mode / env | What it does |
|-------|------------|--------------|
| `tests/probes/probe_db_file.xi` | `ORBITDB_DB_MODE=write/verify/put1/ckpt/qverify/txn/soak`; `ORBITDB_DB_FORMAT=v1/v2` | Durable DB driver used by the crash harnesses. `verify` checks keys/values; `qverify` checks range + filter queries; `ckpt` polls snapshot + truncated WAL; `txn` opens a transaction (`ORBITDB_DB_TXN_COUNT`, `ORBITDB_DB_TXN_COMMIT=0/1`). FORMAT steers the snapshot container for writes (reads auto-detect). |
| | `ORBITDB_DB_FILE`, `ORBITDB_DB_N`, `ORBITDB_DB_LAST_KEY`, `ORBITDB_DB_LAST_VAL` | Path, key count, optional post-recovery assertion. |
| | `ORBITDB_DB_CKPT_EVERY` | Soak mode: `db_file_maybe_checkpoint` record limit (default 250). |
| `tests/probes/probe_btree_churn.xi` | `ORBITDB_CHURN_ORDER/OPS/N/SEED` | B-tree churn vs model + structural validator. |
| `tests/probes/probe_fuzz.xi` | `ORBITDB_FUZZ_*` | Section 4. |
| `tests/probes/probe_wal_file.xi`, `probe_page_file.xi` | Mode envs per file header | Crash drivers for WAL/page harnesses. |
| `tests/hybrid/probe_hybrid.xi` | `ORBITDB_HYBRID_MODE=full/writer/verify` | ORBITDB <-> XVECTOR hybrid acceptance (source-level composition via `tests/hybrid/xiom.toml`). `full` = 36-check in-process run; `writer`/`verify` are driven by the hybrid crash harness. |
| | `ORBITDB_HYBRID_ROWS`, `ORBITDB_HYBRID_VEC`, `ORBITDB_HYBRID_N`, `ORBITDB_HYBRID_DIM`, `ORBITDB_HYBRID_SKIP`, `ORBITDB_HYBRID_LAG`, `ORBITDB_HYBRID_CHUNK`, `ORBITDB_HYBRID_Q`, `ORBITDB_HYBRID_K` | Row-store path, vector-WAL path and scale knobs (defaults 1000 / 8 / 10 / 3 / 200 / 8 / 20). |
| `tests/hybrid/repro_chain.xi` | paths are repo-relative | XV-ORBITDB-01 repro: chained persist -> load -> recover -> persist -> load (load2 loses the log; see `docs/XVECTOR-INTEGRATION.md` section 7). |
| `tests/pkg/probe_pkg_wal.xi` | `ORBITDB_PKG_WAL` (segment path, default `probe-logs/pkg-wal.log`) | First registry consumer pass: `xiom.wal` 0.1.0 conformance + two-way format interop with `src/wal_file.xi` (project `tests/pkg/xiom.toml`; needs the installed package). Syntax: `scripts/run.ps1 tests\pkg\probe_pkg_wal.xi -TimeoutSec 180`. |
| `tests/probes/probe_block_store.xi` | `ORBITDB_BLOCK_MODE=full/writer/verify`; `ORBITDB_BLOCK_DB`, `ORBITDB_BLOCK_N`, `ORBITDB_BLOCK_BATCH`, `ORBITDB_BLOCK_KILL_AT` | M1.2 S2 block store: `full` = 26-check functional battery; `writer`/`verify` drive `scripts/block_crash_test.*` (kill states pages2/full2/midheader/compacted). |

Standard soak (policy checkpoints every 250 records):

```powershell
$env:ORBITDB_DB_FILE = "probe-logs\soak.wal"; $env:ORBITDB_DB_MODE = "soak"
$env:ORBITDB_DB_N = "2000"; $env:ORBITDB_DB_CKPT_EVERY = "250"
scripts\run.ps1 tests\probes\probe_db_file.xi -TimeoutSec 600
```

Scratch files live in `probe-logs/` (gitignored). On WSL, point
`ORBITDB_DB_FILE` at `/tmp/...` to avoid DrvFs write overhead in benchmarks;
correctness soaks run fine on both.

## 4. Fuzz/property harness

`scripts\fuzz.ps1` (mirrors `scripts/fuzz.sh`) runs `probe_fuzz.xi`:
deterministic LCG seeds, no wall-clock, four sections -- tuple codec
roundtrip + byte-flip mutations + truncation, WAL parser (valid records +
garbage + torn tails + heal-and-append), page-log parser (latest-wins, CRC
rejection, garbage/torn), and B-tree vs model over multiple orders and seeds.

```powershell
scripts\fuzz.ps1 -TimeoutSec 600
# knobs: ORBITDB_FUZZ_SEEDS, ORBITDB_FUZZ_OPS, ORBITDB_FUZZ_N,
#        ORBITDB_FUZZ_TUPLE_ITERS, ORBITDB_FUZZ_WAL_ITERS, ORBITDB_FUZZ_PAGE_ITERS,
#        ORBITDB_FUZZ_DIR
```

Expected tail: `fuzz: OK seeds=4 ops/seed=4000 n=512` and exit 0. Failure
output names the section, seed and the first violated property. Continuous CI
cadence is gated on F3 (CI matrix); until then run it at every wrap on both
platforms.

## 5. Database files and recovery

A durable DB with WAL path `<path>` owns:

```
<path>        WAL segment  (lsn|op|key|value|timestamp[|payload])
<path>.snap   snapshot page log (header page 0 + node pages)
```

- `db_file_open` recovers by loading the newest committed snapshot generation
  and replaying only WAL records with `lsn > checkpoint_lsn`; without a
  snapshot it replays the whole segment.
- Torn tails on either file are healed on open / before append; never
  hand-edit these files.
- **Never truncate the WAL to empty**: the LSN counter lives in the retained
  Checkpoint anchor record.
- Checkpoint: `db_file_checkpoint` appends changed node pages, commits with
  the header page, then anchors and truncates the WAL. Rejected while a
  transaction is active.
- Transactions: ops are logged immediately but applied only at commit; a
  crash before commit discards them; a dangling window is finalized with an
  explicit Abort record on the next open.
- Stale handles: once another handle has written, this handle's writes are
  refused (`false` / `-1` for checkpoint). Reopen to become the writer again;
  there is no lock file to clear (see `docs/ISOLATION.md`).

Verify a recovered database with the probe modes:

```powershell
$env:ORBITDB_DB_FILE = "path\to\db.wal"; $env:ORBITDB_DB_MODE = "verify"
$env:ORBITDB_DB_N = "<expected key count>"
scripts\run.ps1 tests\probes\probe_db_file.xi -TimeoutSec 180
```

## 6. Gotchas

- `-Quiet` on `run.ps1` suppresses program output; use it only when the exit
  code is all you need.
- `read_file_lines` / `str_split` are **linear** since stdlib wave 96/97 (they
  were quadratic on v0.64.1); 20k-record WAL replay is ~9.9 s. `-N 20000`
  remains the bench reference.
- Hang loops need a side-effecting call (`io.sleep`); empty spin loops are
  optimized away.
- Harness flake: a single page-crash `observed=2`-style start miss under load
  is environmental; re-run with `-TimeoutSec 120` and confirm with a clean x2.
- WSL memory/contention: other lanes (PULSE/XVECTOR) share the WSL VM. Before
  chained WSL harness runs check `ps aux --sort=-rss | head` and `free -m`,
  run at most ONE heavy harness per command, and pause/retry if the VM is
  busy. The VM restarted twice under load on 2026-10-09 -- treat a restart as
  a reason to check, not to hammer.
- Identity/commits: conventional commits with DCO sign-off
  (`git commit -s`, `Lefteris Notas <lefterisnotas@gmail.com>`).

## 7. Where to read next

- `ARCHITECTURE.md` -- module tree and ownership.
- `docs/API.md` -- public API reference (this tree).
- `docs/FORMATS.md` -- versioned on-disk formats.
- `docs/wal-and-recovery.md`, `docs/storage-layout.md`,
  `docs/query-pipeline.md` -- subsystem deep-dives.
- `docs/PRODUCTION-READINESS.md` -- scoreboard, changelog, checklist.
- `docs/XVECTOR-INTEGRATION.md` -- the hybrid contract, cross-ask answers,
  the standing probe/harness evidence and finding XV-ORBITDB-01.
- `SESSION.md` -- current state and next actions.
