#!/usr/bin/env bash
# ============================================================================
# XIOM ORBITDB Station -- build and run the hello-station (ORBITWIRE v1).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage:
#   scripts/station.sh                       # orbitdb-station.wal :7767
#   DB=data/app.wal PORT=9000 scripts/station.sh
#   TOKEN=s3cret scripts/station.sh          # require AUTH
#
# The Station OWNS its database while it runs (M3 shard lock).
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/dev-env.sh" >/dev/null

DB_PATH="${DB:-orbitdb-station.wal}"
PORT_NUM="${PORT:-7767}"
BIND_ADDR="${BIND:-127.0.0.1}"
ORDER_NUM="${ORDER:-4}"
MAX_RAM_GB="${MAX_RAM_GB:-4}"
TOKEN_VALUE="${TOKEN:-}"

export ORBITDB_STATION_DB="$DB_PATH"
export ORBITDB_STATION_BIND="$BIND_ADDR"
export ORBITDB_STATION_PORT="$PORT_NUM"
export ORBITDB_STATION_ORDER="$ORDER_NUM"
export ORBITDB_STATION_PAGE_FORMAT="2"
export ORBITDB_STATION_TOKEN="$TOKEN_VALUE"

mkdir -p "$REPO_ROOT/out"
BIN="$REPO_ROOT/out/orbitdb-station"
"$XIOM_COMPILER" -o "$BIN" "$REPO_ROOT/station/src/hello_station.xi" || exit 1

cd "$REPO_ROOT" || exit 1
"$BIN" &
pid=$!
peak=0
start=$(date +%s)
while kill -0 "$pid" 2>/dev/null; do
  rss=$(awk '/VmRSS/{print $2}' /proc/$pid/status 2>/dev/null)
  if [ -n "$rss" ]; then
    if [ "$rss" -gt $((MAX_RAM_GB * 1024 * 1024)) ]; then
      echo "RAM-CAP [orbitdb-station]: killed at $((rss / 1024)) MB (cap ${MAX_RAM_GB} GB)"
      kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; exit 137
    fi
    [ "$rss" -gt "$peak" ] && peak=$rss
  fi
  sleep 0.5
done
wait "$pid"; rc=$?
echo "RAM-CAP [orbitdb-station]: exit=$rc peak=$((peak / 1024)) MB (cap ${MAX_RAM_GB} GB)"
exit $rc
