# ORBITDB Admin (web) -- phase 1

A separate, localhost-only control plane for a single-node ORBITDB file.
Browser UI served by the PULSE Beacon HTTP core (`xiom.pulse` 0.3.1); it
source-composes the Satellite engine (`../src`). No native GUI dependency,
no external assets -- it works headless and survives SSH/tunnel access.

> **Status:** phase 1 + token-gated writes (2026-10-19) -- engine status,
> key/value range browser, point lookup, put/delete/checkpoint behind
> `ORBITDB_ADMIN_TOKEN`. Owner-approved as the recommended admin shape
> (pgAdmin-style separate client; native SDL3+ImGui is a later optional
> client). The Station will reuse this UI over ORBITWIRE after ST1.

## Run

```powershell
# repo root, Windows
.\scripts\admin.ps1                         # orbitdb-admin.wal, 127.0.0.1:8787
.\scripts\admin.ps1 -Database data\app.wal -Port 9000
```

```bash
# WSL/Linux (lane toolchain)
scripts/admin.sh                            # orbitdb-admin.wal, 8787
DB=data/app.wal PORT=9000 scripts/admin.sh
```

Seed a demo database (40 keys, values key*10):

```powershell
$env:ORBITDB_ADMIN_DB='orbitdb-admin-demo.wal'
& (Join-Path $PWD 'out\seed-demo.exe')      # build: xiom -o out\seed-demo.exe admin\tests\seed_demo.xi
```

Open `http://127.0.0.1:8787/`.

## Endpoints (GET, read-only)

| Path | Meaning |
|---|---|
| `/` | dashboard (inline HTML/JS; no CDN) |
| `/api/status` | engine/file/pager status JSON |
| `/api/range?low=&high=&limit=` | `(key,value)` pairs in key order (limit 1..500) |
| `/api/get?key=` | point lookup |
| `POST /api/put?key=&value=` | upsert (token required) |
| `POST /api/delete?key=` | delete (token required) |
| `POST /api/checkpoint` | commit a checkpoint (token required) |
| `POST /api/backup` | checkpoint + copy `<db>.backup.wal` / `<db>.backup.snap` (token required) |

Stop the server with any request carrying `X-Pulse-Quit: 1` (PULSE's clean
shutdown seam), or Ctrl+C.

## Security / ownership

- Binds to `127.0.0.1` by default; keep it local. `ORBITDB_ADMIN_TOKEN`
  enables a shared-token check for `/api/*` (`X-Admin-Token: <token>`) and
  is REQUIRED for writes (without it they return 403).
- **The admin owns the database file while it runs** (enforced): it opens
  with `db_file_open_locked_checked` (M3 shard lock), so a second admin on
  the same DB fails fast; the lock is released when the process exits.
  There is still no read-only open; the Station mode (ORBITWIRE session)
  removes this limitation.
- Reads are GET-only. Writes require the token header (custom headers are
  not settable by cross-site forms, so the CSRF surface stays closed).
  Backups/metrics/sessions come after the Station protocol freeze.

## Layout

```
admin/
  xiom.toml          manifest (source-roots ../src + src; dep xiom.pulse 0.3.1)
  src/admin.xi       PULSE routes + engine reads (module orbitdb.admin)
  src/index.html     dashboard
  tests/seed_demo.xi demo data
```

The engine addition this needed: `db_file_range_pairs` (keys + values; the
existing `db_file_range` returns values only) in `src/index/btree.xi` +
`src/engine.xi`, with `dbfile` suite coverage.

## Backup / restore

`POST /api/backup` checkpoints, then atomically copies `<db>` to
`<db>.backup.wal` and `<db>.snap` to `<db>.backup.snap`. Restore while no
handle is open: copy the two backup files back to the original names
(`<db>` and `<db>.snap`). The admin owns the lock, so the pair is stable.
This is a local file-level backup, not a remote/restic integration.