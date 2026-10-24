# Paste prompt -- next ORBITDB session (2026-10-23 wrap)

Copy the block below into the next session.

```
You are the ORBITDB session for E:\xiom-projects\xiom-orbitdb -- embedded XIOM
database engine (Satellite = registry tier, Station = server tier). Read
SESSION.md first (the top Updated entry = the 2026-10-23 SESSION WRAP), then
README/SPEC/ARCHITECTURE and docs/ (REFERENCE-MATRIX, BENCH-1, TWO-TIER,
PRODUCTION-READINESS, RUNBOOK, checklists/m1-1b-pager, checklists/two-tier).
Consumer lane: never edit E:\xiom-lang\stdlib, E:\xiom-lang\xiom,
E:\xiom-packages\packages. Repo PRIVATE; no code pushes without owner
approval. Identity "Lefteris Notas <lefterisnotas@gmail.com>"; conventional
commits + -s; docs coupled in the same commit. This worktree has had
concurrent sessions: always run `git status` and `git log --oneline -3`
before editing and never clobber another lane's SESSION entry.

RELAYS: E:\xiom-lang\xiom-relays. `git pull --ff-only` errors "Cannot
fast-forward to multiple branches" -> use
`git fetch origin && git merge --ff-only origin/main`, then
`python tools/relay.py view --lane orbitdb` and process items to this lane;
never edit another lane's item (file a new one). Re-create the 3h doorbell
cron (session-scoped) if this is a fresh session.

TOOLCHAIN (2026-10-23):
- Compiler **v0.64.8 is production** (Latest; Windows
  %LOCALAPPDATA%\xiom-0.64.8\bin\xiom.exe exe sha `ee3ee902...`; WSL
  ~/.local/share/xiom-0.64.8/bin/xiom bin `7c5b3482...`).
- **v0.64.9 is WITHDRAWN from adoption** (`REL-20261022-1826-compiler`):
  GitHub marks it pre-release/audit only; nested enum patterns, m372/1550
  and m1511 port.args are the v0.65.0 gate (P0 correctness / release-compiler
  parity, then P1 hardening + P2 MCU). Do not adopt/deploy it. The v0.64.9
  acceptance rows stay as v0.65.0 input; our hold -1501 is closed as
  withdrawn (not green).
- **v0.65.0 is RELEASED (2026-10-23T23:45Z) and is the production target**
  (tag `f527d5a` on `a0dc452dc`; 11 assets + SHA256SUMS; stdlib-v0.65.0
  `3eb9c05`; xiom-std 0.65.0). v0.64.8 is superseded but the lane pins stay
  v0.64.8 **until the acceptance below is green**. Compiler lane: full e2e
  2646/2646 on debug+release, release parity x2, MCU QEMU, C07 runtime
  helper. Relay `REL-20261023-2346-compiler`.
- **stdlib-v0.64.9 is adopted lane-locally** (`aa8b656`; archive
  `xiom-std-0.64.9.tar.gz` sha256 `eab0b80d0019479c17fee091a70ebee4d001ae018eb8e291c08db157c358c269`):
  Windows %LOCALAPPDATA%\xiom-stdlib-0.64.9, WSL
  ~/.local/share/xiom-stdlib-0.64.9; `scripts/dev-env.*` sets `XIOM_STDLIB`
  to it unless an explicit value is inherited. It pins compiler v0.64.8 and
  supplies `io.read_at_into`; v0.65.0 will pin stdlib-v0.65.0.
- `feat/read-at-into-open` is merged (`27a8212`; adoption commit `333dd3f`):
  v2 block-store scan uses `io.read_at_into` into a reused page buffer.
- FRESHNESS: at start and after any pin move run the battery (suite x2 both,
  crash x2 both, probes x2 both, fuzz, hybrid x2 both) and relay reds.
- **v0.65.0 acceptance is the next action** (the archive is out): verify
  version/checksums, run 1451/1550 + our repros, 1M A/B with
  `XIOM_FAST_EXIT=1`, A6 exact verify, m1157 BOM, C-ORBIT-14 `via_let=3`,
  then fill `release-checks/compiler-v0.65.0.md`, close the hold rows, and
  bump the compiler/stdlib pins. Cross-lane advisory: bindings reports an
  owner-approved pause through the 04:00-13:00 Greek double-charge window
  (resume 10:05Z); confirm with the owner/compiler lane before adopting
  during it.

STATE (2026-10-23 wrap): **A6 1M PASS / G-START GREEN / ST1 ORBITWIRE GREEN /
stdlib-v0.64.9 + read_at_into adopted / ST2 crash harness GREEN.**
- 1M on v0.64.8 + stdlib-v0.64.9 + read_at_into: exact 1,004-sample verify,
  32,260 nodes, **peak 2,451.2 MB** under 4 GB (new best; prev 2,494.7),
  engine 6.11 s, wall 6,110 s under sibling-lane load (quiet baseline
  880 s). 200k: 558.2 MB / 0.733 s engine / 733 s wall under load.
- Functional battery: suite 166/166 x2 Win + x2 WSL; block crash 8/8 x2
  both; db crash 25/25 x2 Win; fuzz; station 169/169 x2 Win; io-primitives
  30/30 x2; mvcc 36/36 x2; hybrid full 36/36 x2 both + crash 5/5 x2 both
  (after the package-store restore installed xiom.metrics 0.2.0).
- ST1: `station/` ORBITWIRE v1 frozen (`station/docs/ORBITWIRE.md`),
  protocol 33/session 28/loopback 108 = 169 checks x2 both.
- ST2: crash harness `scripts/station_crash_test.{ps1,sh}` +
  `station/tests/station_crash_client.xi` = 11/11 x2 both (uncommitted
  BEGIN+PUT discarded, committed WAL replay, second-kill durability; M3
  lock reacquired after kill -9; `ORBITDB_STATION_PORT_FILE` + listen-line
  flush). **No engine src/ touched.** Remaining: session-loop hardening +
  explicit graceful stop/SIGINT, then ST3.
- Admin phase 1+2 + backup/restore in `admin/` (Pulse 0.3.1). M3 shard lock
  + threads decision done.
- Readiness 82.5 (A5 OK; Station is a separate tier; no Satellite score
  change for Station work).
- m375: exit teardown remains; `XIOM_FAST_EXIT` is v0.65.0 acceptance
  input. C-ORBIT-14 fixed on main `478e06f8b`; C-ORBIT-15 (BOM catalog)
  fixed on main `18415ede2`; both postdate v0.64.8, so keep
  declare-then-assign and BOM-free sources until v0.65.0. Repro bundles:
  docs/repro/vec-match-binding/, docs/repro/utf8-bom-module/.
- Relays: C-ORBIT-14 `-1136` (fixed), C-ORBIT-15 `-1157` (fixed), stdlib
  `-3` (verified), hybrid block `-1750` (verified), packages interop `-1154`
  (acked), m375 `-2`, packages 0.3.0 `-4`, all-lanes ops `-5`.

TASK ORDER (item 0 first):
0. **v0.65.0 compiler acceptance -- the archive is OUT (2026-10-23T23:45Z).**
   Release: tag `v0.65.0` (`f527d5a`) on `a0dc452dc`; 11 assets +
   SHA256SUMS re-verified; stdlib-v0.65.0 (`3eb9c05`); xiom-std 0.65.0
   (sha `c3629878...`); e2e 2646/2646 on debug AND release compilers.
   Do not adopt v0.64.9. Verify the v0.65.0 archive + SHA256SUMS; run
   p_nested_generic_ptr_read, p_iter_enumerate_tuple,
   docs/repro/vec-match-binding, docs/repro/utf8-bom-module on the new
   archive; then full battery + 1M A/B with XIOM_FAST_EXIT=1 + A6 exact
   verify + m1157 + C-ORBIT-14 via_let=3; fill
   release-checks/compiler-v0.65.0.md and close the holds; only then bump
   dev-env.*. ST2/ST3 may proceed on v0.64.8 while the acceptance runs.
1. **ST2 Station single-node server core (remaining):** session-loop
   hardening + explicit graceful stop/SIGINT (check stdlib signal support;
   if absent, add a stop flag/control path or document the limitation),
   then close the ST2 gate. Crash harness and RUNBOOK 7 are done. Do not
   share a DBFile across threads. ST3 follows.
2. **Quiet-host 1M wall:** rerun the 1M soak on a quiet host to separate the
   m375 teardown (6,110 s under load vs 880 s baseline) from the engine
   work; record in BENCH-1. Peak/exact-verify already pass.
3. **m375:** `XIOM_FAST_EXIT` A/B at 1M is part of v0.65.0 acceptance; update
   the wishlist/relays after the archive.
4. **Station ST3+:** reader snapshots via engine pins, mixed reader/writer
   harness, replication/sharding/ops (ST4-ST7); admin phase 3 attaches over
   ORBITWIRE after ST2/ST3. Package 0.3.0 candidate is filed to packages
   (hold publish for owner approval + final battery).
5. **Satellite P-rc:** hardware power-loss matrix (owner/hardware), then
   release notes + the 0.3.0 publish; README/SPEC tier label.
6. Hygiene: RAM-cap every app/soak (scripts/run_capped.*, 4 GB default,
   admin 2 GB); WSL battery via scripts/wsl_ext4.sh (it creates out/ and
   copies station/); never run crash/hybrid concurrently; call
   db_file_close before deleting/renaming a DB file (held fd); set
   ORBITDB_PAGER_CAPACITY for large DBs (default 256); use fresh paths for
   the hybrid full probe; relay fetch+merge.

KNOWN API ADDITIONS:
- Engine: db_file_open_locked_checked[_cfg]/db_file_unlock/
  db_file_is_locked, db_file_range_pairs, db_file_close, admin /api/backup.
- Station: station/src/{protocol,session,dispatch,server}.xi +
  hello_station.xi; frozen spec station/docs/ORBITWIRE.md; runners
  scripts/station*.{ps1,sh}; station suites 169 checks x2 both.
- ST2: scripts/station_crash_test.{ps1,sh};
  station/tests/station_crash_client.xi; ORBITDB_STATION_PORT_FILE (atomic
  bound-port file); listen line is flushed before the loop.
- stdlib: io.read_at_into is available via the adopted stdlib-v0.64.9.

EVIDENCE COMMANDS:
  .\scripts\suite.ps1                         # 166/166 x2 Win
  .\scripts\block_crash_test.ps1 -Pages 60 -Batch 10
  .\scripts\db_crash_test.ps1 -Keys 20 -Tail 3 -Tx 5
  .\scripts\fuzz.ps1 -TimeoutSec 600
  .\scripts\station_suite.ps1                 # 169/169 x2 Win
  .\scripts\station_crash_test.ps1            # 11/11 x2 Win
  scripts/wsl_ext4.sh ./scripts/suite.sh      # WSL x2
  scripts/wsl_ext4.sh bash ./scripts/station_crash_test.sh
  hybrid full/crash: scripts/hybrid_crash_test.ps1; probe_hybrid.xi with
  ORBITDB_HYBRID_ROWS/VEC (WSL needs XIOM_HOME=~/.xvector-home and out/).

GOTCHAS:
- v0.64.8 has C-ORBIT-14 (Vec bound from a match/Result truncates) and
  C-ORBIT-15 (UTF-8 BOM hides a module from catalog discovery). Keep the
  declare-then-assign workaround and BOM-free sources; both fixes postdate
  the pin.
- The Station owns its DB (M3 lock); kill -9 leaves the advisory .lock, the
  OS releases it and the restart reacquires it (crash harness validates).
- WSL hybrid needs out/ (wsl_ext4 creates it) and the xvector package home
  (~/.xvector-home) for xiom.metrics.
- Console stdout is block-buffered when redirected; station/client tests use
  flush_stdout and the port file.
```
