# ORBITDB Station -- ORBITWIRE v1 server (ST1 spike)

> **Status:** ST1 protocol spike GREEN (2026-10-21): ORBITWIRE v1 is frozen,
> the hello-station runs over loopback TCP, and the loopback conformance
> suite is **169/169 x2 on Windows + x2 on WSL**. ST2 (single-node server
> core, crash-safe restart) is next. The Station never forks the engine: it
> source-composes `../src` and calls the public `db_file_*` API.

The Station is the server tier of the ORBITDB two-tier line (Satellite =
embedded engine/registry package; Station = separate server program). It
speaks **ORBITWIRE**, a typed binary frame protocol -- not HTTP (the admin
HTTP plane stays on PULSE).

## Layout

```
station/
  xiom.toml              project manifest (source-roots ../src + src)
  src/
    protocol.xi          ORBITWIRE v1 codec (frames, typed fields, row/value streams, CRC32C)
    session.xi           session buffers, frame pull, bounded outbound queue, responses
    dispatch.xi          StationActor (one DBFile) + session state machine + engine calls
    server.xi            TCP poll loop, accept/read/flush, backpressure, shutdown
    hello_station.xi     entry point
  tests/
    protocol_suite.xi    33 pure codec checks (KAT, CRC parity, limits, corruption)
    session_suite.xi     28 partial/pipelined ingress + queue/backpressure checks
    loopback_suite.xi    108 end-to-end checks over loopback TCP
  docs/
    ORBITWIRE.md         the v1 wire specification (frozen)
```

## Build and run

```powershell
# repo root, Windows
.\scripts\station.ps1                         # orbitdb-station.wal, 127.0.0.1:7767
.\scripts\station.ps1 -Database data\app.wal -Port 9000
.\scripts\station.ps1 -Token s3cret           # require AUTH
```

```bash
# WSL/Linux
scripts/station.sh                            # 127.0.0.1:7767
DB=data/app.wal PORT=9000 scripts/station.sh
TOKEN=s3cret scripts/station.sh
```

The process owns the database: `db_file_open_locked_checked_cfg` takes the M3
shard lock, so a second Station on the same file fails fast. Stop it with
Ctrl+C (the engine's WAL is durable; the advisory lock is released by exit).
Run it under a RAM cap (`scripts/station.ps1` defaults to 4 GB); for large
databases set `ORBITDB_PAGER_CAPACITY` (default 256).

Env knobs:

| Variable | Default | Meaning |
|---|---|---|
| `ORBITDB_STATION_DB` | `orbitdb-station.wal` | WAL/snapshot base path |
| `ORBITDB_STATION_BIND` | `127.0.0.1` | bind address (keep loopback) |
| `ORBITDB_STATION_PORT` | `7767` | port; `0` -> first free `17867+` |
| `ORBITDB_STATION_ORDER` | `4` | B-tree order (typed row budget) |
| `ORBITDB_STATION_PAGE_FORMAT` | `2` | v2 byte blocks |
| `ORBITDB_STATION_TOKEN` | empty | shared token; empty = AUTH not required |
| `ORBITDB_STATION_PORT_FILE` | empty | optional path to write the actual bound port atomically (harness/service discovery) |

## Test

```powershell
.\scripts\station_suite.ps1          # every station/tests/*_suite.xi, x2
.\scripts\station_crash_test.ps1     # hard-kill/restart recovery, 11 checks
```

```bash
scripts/station_suite.sh             # WSL
scripts/wsl_ext4.sh ./scripts/station_suite.sh   # ext4 copy (9p workaround)
scripts/wsl_ext4.sh bash ./scripts/station_crash_test.sh
```

The runner executes each suite twice and requires identical pass/total with
zero failures. Current evidence: **169/169 x2 Windows + 169/169 x2 WSL**;
crash harness **11/11 x2 Windows + x2 WSL** (uncommitted txn discarded,
committed WAL replay, post-recovery commit survives a second kill).

## Protocol in one paragraph

A frame is `magic "OBW1" | version | kind | flags | reserved | header_len |
payload_len | typed header | payload | CRC32C`. The header is a typed field
list (INT/BOOL/TEXT/BYTES). Ops: HELLO, AUTH, PING, BEGIN, PUT, GET, RANGE,
QUERY, COMMIT, ABORT, CLOSE, DELETE, CHECKPOINT. The session state machine is
`NEW -> GREETED -> READY <-> TXN -> CLOSING -> CLOSED`. `QUERY` carries plan
intent (conditions/bounds/order/limit/offset), never SQL. Full tables, limits
and error taxonomy: [`docs/ORBITWIRE.md`](docs/ORBITWIRE.md).

## Threading and the engine

The ST1 event loop is **single-threaded**: the `StationServer` owns a
`StationActor`, which owns exactly one `DBFile`. Sessions submit commands;
they never hold the handle, and a `DBFile` is never shared across threads.
This is the single-writer shape the engine requires (the WAL append is the
serialization point). ST3 moves the actor behind a dedicated thread/message
queue with reader snapshots, without changing the wire.

One transaction window exists per shard; the owning session is tracked by
`txn_owner`. Other sessions read committed state and their writes return
`TXN_ACTIVE`. On disconnect/CLOSE the owner's window is aborted.

## ST1 exit status and next

- [x] wire spec frozen (`docs/ORBITWIRE.md`)
- [x] op set + state machine + error taxonomy + limits/backpressure
- [x] hello-station over loopback TCP composing the engine through the actor
- [x] conformance suites x2 both platforms (169 checks)
- [x] ST2 crash harness: `scripts/station_crash_test.{ps1,sh}` +
      `station/tests/station_crash_client.xi` (hard kill -> restart -> replay
      -> ORBITWIRE verify; 11 checks x2 both)
- [ ] ST2 remaining: session-loop hardening, graceful stop, crash-safe
      single-node core hardening (ST2 gate)
- [ ] ST3: reader snapshots + thread-per-connection vs process-per-shard
      decision, mixed reader/writer harness
- [ ] ST4+: replication, sharding, ops (TLS/users), admin attach over
      ORBITWIRE (phase 3)

Known v1 limits: loopback/no TLS, QUERY returns values (RANGE is keyed),
typed rows are auto-commit only, one txn per shard, no PREPARE/FETCH, no
session resume. See ORBITWIRE section 14.
