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

export PULSE_BIND="${PULSE_BIND:-127.0.0.1}"
export PULSE_PORT="$PORT_NUM"
export ORBITDB_ADMIN_DB="$DB_PATH"

mkdir -p "$REPO_ROOT/out"
BIN="$REPO_ROOT/out/orbitdb-admin"
"$XIOM_COMPILER" -o "$BIN" "$REPO_ROOT/admin/src/admin.xi" || exit 1

cd "$REPO_ROOT" || exit 1
exec "$BIN"
