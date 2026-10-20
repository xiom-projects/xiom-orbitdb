#!/usr/bin/env bash
# ============================================================================
# XIOM ORBITDB admin web client -- build and run (localhost only).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage:
#   scripts/admin.sh                       # orbitdb-admin.wal :8787
#   DB=data/app.wal PORT=9000 scripts/admin.sh
#
# The admin OWNS its database file while it runs. Do not point it at a DB
# currently opened by another process (no read-only open/cross-process pins
# yet; that is the M3 remainder).
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/dev-env.sh" >/dev/null

DB_PATH="${DB:-orbitdb-admin.wal}"
PORT_NUM="${PORT:-8787}"
MAX_RAM_GB="${MAX_RAM_GB:-2}"

export PULSE_BIND="${PULSE_BIND:-127.0.0.1}"
export PULSE_PORT="$PORT_NUM"
export ORBITDB_ADMIN_DB="$DB_PATH"

mkdir -p "$REPO_ROOT/out"
BIN="$REPO_ROOT/out/orbitdb-admin"
"$XIOM_COMPILER" -o "$BIN" "$REPO_ROOT/admin/src/admin.xi" || exit 1

cd "$REPO_ROOT" || exit 1
"$BIN" &
pid=$!
peak=0
start=$(date +%s)
while kill -0 "$pid" 2>/dev/null; do
  rss=$(awk '/VmRSS/{print $2}' /proc/$pid/status 2>/dev/null)
  if [ -n "$rss" ]; then
    if [ "$rss" -gt $((MAX_RAM_GB * 1024 * 1024)) ]; then
      echo "RAM-CAP [orbitdb-admin]: killed at $((rss / 1024)) MB (cap ${MAX_RAM_GB} GB)"
      kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; exit 137
    fi
    [ "$rss" -gt "$peak" ] && peak=$rss
  fi
  sleep 0.5
done
wait "$pid"; rc=$?
echo "RAM-CAP [orbitdb-admin]: exit=$rc peak=$((peak / 1024)) MB (cap ${MAX_RAM_GB} GB)"
exit $rc
