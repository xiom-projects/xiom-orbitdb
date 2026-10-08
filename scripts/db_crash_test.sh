#!/usr/bin/env bash
# ============================================================================
# XIOM ORBITDB file-backed DB crash/recovery test (WAL-before-ack).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Mirrors scripts/db_crash_test.ps1:
#   1. writer puts N keys through DBFile (append-then-apply), then hangs;
#   2. hard-kill the writer process GROUP once N records are on disk;
#   3. append a torn tail (no newline) -- crash mid-record;
#   4. reopen: replay the segment, recover exactly N keys (torn skipped);
#   5. put one more key (tail healed) and recover N+1.
#
# Usage: scripts/db_crash_test.sh [--keys N] [--timeout-sec S]
# Exit:  0 = green, 1 = failed.
# ============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=dev-env.sh
. "$SCRIPT_DIR/dev-env.sh"

KEYS=20
TIMEOUT_SEC=90
while [ $# -gt 0 ]; do
  case "$1" in
    --keys) KEYS=${2:?missing value}; shift 2 ;;
    --timeout-sec) TIMEOUT_SEC=${2:?missing value}; shift 2 ;;
    -h|--help) printf 'Usage: db_crash_test.sh [--keys N] [--timeout-sec S]\n'; exit 0 ;;
    *) printf 'unknown flag: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [ -z "${XIOM_COMPILER:-}" ] || [ ! -x "${XIOM_COMPILER}" ]; then
  printf 'db-crash: XIOM_COMPILER not resolved; source scripts/dev-env.sh\n' >&2
  exit 2
fi

PROBE="$REPO_ROOT/tests/probes/probe_db_file.xi"
LOG_DIR="$REPO_ROOT/probe-logs"
mkdir -p "$LOG_DIR"
WAL_FILE="$LOG_DIR/crash-dbfile.wal"
rm -f "$WAL_FILE"

PASS=0
FAIL=0
check() {
  if [ "$2" -eq 0 ]; then printf '[PASS] %s\n' "$1"; PASS=$((PASS + 1));
  else printf '[FAIL] %s\n' "$1"; FAIL=$((FAIL + 1)); fi
}

invoke_mode() { # mode n [last_key last_val]
  local mode=$1 n=$2 last_key=${3:-} last_val=${4:-}
  export ORBITDB_DB_FILE="$WAL_FILE"
  export ORBITDB_DB_MODE="$mode"
  export ORBITDB_DB_N="$n"
  if [ -n "$last_key" ]; then export ORBITDB_DB_LAST_KEY="$last_key"; else unset ORBITDB_DB_LAST_KEY; fi
  if [ -n "$last_val" ]; then export ORBITDB_DB_LAST_VAL="$last_val"; else unset ORBITDB_DB_LAST_VAL; fi
  "$SCRIPT_DIR/run.sh" "$PROBE" --timeout-sec 180 --quiet
  return $?
}

# --- phase 1: writer puts KEYS records, then hangs --------------------------
export ORBITDB_DB_FILE="$WAL_FILE"
export ORBITDB_DB_MODE="write"
export ORBITDB_DB_N="$KEYS"
setsid "$XIOM_COMPILER" --run "$PROBE" >"$LOG_DIR/dbfile-writer.out" 2>&1 &
WRITER_PID=$!

DEADLINE=$(( $(date +%s) + TIMEOUT_SEC ))
OBSERVED=0
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  if [ -f "$WAL_FILE" ]; then
    OBSERVED=$(grep -c '|' "$WAL_FILE" 2>/dev/null || true)
    [ -n "$OBSERVED" ] || OBSERVED=0
    [ "$OBSERVED" -ge "$KEYS" ] && break
  fi
  if ! kill -0 "$WRITER_PID" 2>/dev/null && [ ! -f "$WAL_FILE" ]; then break; fi
  sleep 0.3
done
check "writer put $KEYS keys (observed=$OBSERVED)" "$([ "$OBSERVED" -ge "$KEYS" ] && echo 0 || echo 1)"

# --- phase 2: hard-kill the group + torn tail ------------------------------
kill -9 -"$WRITER_PID" 2>/dev/null || kill -9 "$WRITER_PID" 2>/dev/null
wait "$WRITER_PID" 2>/dev/null || true
printf 'torn|' >> "$WAL_FILE"
printf 'crash: killed writer, segment=%s bytes, torn tail appended\n' "$(wc -c < "$WAL_FILE")"

# --- phase 3: reopen, replay must recover exactly KEYS keys ----------------
invoke_mode verify "$KEYS" >/dev/null 2>&1
check "reopen recovers $KEYS keys (WAL replay, torn skipped)" "$?"

# --- phase 4: heal + put one more key --------------------------------------
invoke_mode put1 "$KEYS" >/dev/null 2>&1
check "put after torn tail heals (put1 exit 0)" "$?"

# --- phase 5: N+1 and last-key integrity ------------------------------------
invoke_mode verify "$((KEYS + 1))" "9999" "99990" >/dev/null 2>&1
check "reopen recovers $((KEYS + 1)) keys incl. healed put" "$?"

printf 'crash: pass=%s fail=%s\n' "$PASS" "$FAIL"
if [ "$FAIL" -eq 0 ]; then printf 'db-crash: GREEN\n'; exit 0; fi
printf 'db-crash: RED\n'
exit 1
