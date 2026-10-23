#!/usr/bin/env bash
# ============================================================================
# XIOM ORBITDB -- Station crash harness (ST2), Linux/WSL twin.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Mirrors scripts/station_crash_test.ps1: start hello-station, drive an
# ORBITWIRE writer to a deterministic point, kill -9 the server, restart on
# the same DB (M3 lock must be free; WAL must replay), verify.
#    A uncommitted: BEGIN+PUT killed before COMMIT -> absent after restart;
#      then a post-recovery commit, kill, verify present.
#    B committed:   auto-commit PUT killed -> present after restart.
#
# Usage: scripts/station_crash_test.sh [--timeout-sec S] [--keep]
# Exit:  0 = green, 1 = failed.
# ============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=dev-env.sh
. "$SCRIPT_DIR/dev-env.sh" >/dev/null

TIMEOUT_SEC=120
KEEP=0
while [ $# -gt 0 ]; do
  case "$1" in
    --timeout-sec) TIMEOUT_SEC=${2:?missing value}; shift 2 ;;
    --keep) KEEP=1; shift ;;
    -h|--help) printf 'Usage: scripts/station_crash_test.sh [--timeout-sec S] [--keep]\n'; exit 0 ;;
    *) printf 'unknown flag: %s\n' "$1" >&2; exit 2 ;;
  esac
done

OUT="$REPO_ROOT/out"
mkdir -p "$OUT"
STATION="$OUT/orbitdb-station"
CLIENT="$OUT/station-crash-client"
PASS=0
FAIL=0
ST_PID=""
C_PID=""

check() {
  if [ "$1" -eq 0 ]; then
    PASS=$((PASS + 1)); printf '  [PASS] %s\n' "$2"
  else
    FAIL=$((FAIL + 1)); printf '  [FAIL] %s\n' "$2"
  fi
}

cleanup() {
  [ -n "$C_PID" ] && kill -9 "$C_PID" 2>/dev/null
  [ -n "$ST_PID" ] && kill -9 "$ST_PID" 2>/dev/null
  wait 2>/dev/null
}
trap cleanup EXIT

rm -rf "$OUT"/station-crash-*.log "$OUT"/station-crash-*.err \
       "$OUT"/station-crash-*.port "$OUT"/station-client-*.log \
       "$OUT"/station-client-*.err 2>/dev/null
pkill -f "$STATION" 2>/dev/null || true
pkill -f "$CLIENT" 2>/dev/null || true
sleep 0.2

"$XIOM_COMPILER" -o "$STATION" "$REPO_ROOT/station/src/hello_station.xi" || exit 1
"$XIOM_COMPILER" -o "$CLIENT" "$REPO_ROOT/station/tests/station_crash_client.xi" || exit 1

# Start the station; sets ACTUAL_PORT. Returns 0 when the port file appears.
start_station() {
  local db=$1 requested=$2 tag=$3
  local log="$OUT/station-crash-$tag.log"
  local err="$OUT/station-crash-$tag.err"
  local portf="$OUT/station-crash-$tag.port"
  rm -f "$log" "$err" "$portf"
  ORBITDB_STATION_DB="$db" \
  ORBITDB_STATION_BIND="127.0.0.1" \
  ORBITDB_STATION_PORT="$requested" \
  ORBITDB_STATION_ORDER="4" \
  ORBITDB_STATION_PAGE_FORMAT="2" \
  ORBITDB_STATION_TOKEN="" \
  ORBITDB_STATION_PORT_FILE="$portf" \
    "$STATION" >"$log" 2>"$err" &
  ST_PID=$!
  local i=0
  while [ "$i" -lt 300 ]; do
    if [ -f "$portf" ]; then
      ACTUAL_PORT=$(cat "$portf")
      return 0
    fi
    if ! kill -0 "$ST_PID" 2>/dev/null; then return 1; fi
    sleep 0.1
    i=$((i + 1))
  done
  return 1
}

start_client() {
  local mode=$1 port=$2 key=$3 value=$4 tag=$5
  local log="$OUT/station-client-$tag.log"
  local err="$OUT/station-client-$tag.err"
  rm -f "$log" "$err"
  ORBITDB_STATION_PORT="$port" \
  STATION_CRASH_MODE="$mode" \
  STATION_CRASH_KEY="$key" \
  STATION_CRASH_VALUE="$value" \
  STATION_CRASH_WAIT="$TIMEOUT_SEC" \
    "$CLIENT" >"$log" 2>"$err" &
  C_PID=$!
  CLIENT_LOG="$log"
}

wait_file() {
  local file=$1 pattern=$2 secs=$3 i=0
  while [ "$i" -lt $((secs * 10)) ]; do
    if [ -f "$file" ] && grep -q "$pattern" "$file" 2>/dev/null; then return 0; fi
    sleep 0.1
    i=$((i + 1))
  done
  return 1
}

wait_client() {
  local pid=$1 secs=$2 i=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$i" -ge $((secs * 10)) ]; then
      kill -9 "$pid" 2>/dev/null
      return 1
    fi
    sleep 0.1
    i=$((i + 1))
  done
  return 0
}

run_client() {
  local mode=$1 port=$2 key=$3 value=$4 tag=$5
  start_client "$mode" "$port" "$key" "$value" "$tag"
  wait_client "$C_PID" "$TIMEOUT_SEC"
  local rc=$?
  wait "$C_PID" 2>/dev/null
  C_PID=""
  return $rc
}

have_ok() {
  grep -q "$1" "$CLIENT_LOG" 2>/dev/null
}

remove_db() {
  rm -f "$1" "$1.snap" "$1.snap.rw" "$1.lock"
}

print_fail() {
  printf '    client output: %s\n' "$(tr '\n' ' ' < "$CLIENT_LOG" 2>/dev/null)"
}

printf 'station-crash: case A (uncommitted txn discarded, then commit/recover)\n'
DB_A="$OUT/station-crash-a.wal"
remove_db "$DB_A"
if start_station "$DB_A" 17990 a1; then
  check 0 "station A started (port $ACTUAL_PORT)"
  start_client writer_uncommitted "$ACTUAL_PORT" 7001 4242 a-writer
  if wait_file "$CLIENT_LOG" "CRASH-READY" 30; then
    check 0 "writer reached BEGIN+PUT"
    kill -9 "$ST_PID" 2>/dev/null
    wait "$ST_PID" 2>/dev/null
    ST_PID=""
    kill -9 "$C_PID" 2>/dev/null
    wait "$C_PID" 2>/dev/null
    C_PID=""
    if start_station "$DB_A" 17990 a2; then
      check 0 "station A restarted after hard kill (port $ACTUAL_PORT)"
      if run_client verify_absent "$ACTUAL_PORT" 7001 4242 a-verify-absent && have_ok "CRASH-VERIFY OK"; then
        check 0 "uncommitted txn discarded on restart"
      else
        check 1 "uncommitted txn discarded on restart"; print_fail
      fi
      if run_client commit "$ACTUAL_PORT" 7001 4242 a-commit && have_ok "CRASH-COMMIT OK"; then
        check 0 "post-recovery commit"
      else
        check 1 "post-recovery commit"; print_fail
      fi
      kill -9 "$ST_PID" 2>/dev/null
      wait "$ST_PID" 2>/dev/null
      ST_PID=""
      if start_station "$DB_A" 17990 a3; then
        check 0 "station A restarted after committed kill (port $ACTUAL_PORT)"
        if run_client verify_present "$ACTUAL_PORT" 7001 4242 a-verify-present && have_ok "CRASH-VERIFY OK"; then
          check 0 "committed value survived the second kill"
        else
          check 1 "committed value survived the second kill"; print_fail
        fi
        kill -9 "$ST_PID" 2>/dev/null
        wait "$ST_PID" 2>/dev/null
        ST_PID=""
      else
        check 1 "station A restarted after committed kill"
      fi
    else
      check 1 "station A restarted after hard kill"
    fi
  else
    check 1 "writer reached BEGIN+PUT"
    kill -9 "$C_PID" 2>/dev/null
    C_PID=""
  fi
else
  check 1 "station A started"
fi

printf 'station-crash: case B (committed write survives a hard kill)\n'
DB_B="$OUT/station-crash-b.wal"
remove_db "$DB_B"
if start_station "$DB_B" 17991 b1; then
  check 0 "station B started (port $ACTUAL_PORT)"
  start_client writer_committed "$ACTUAL_PORT" 7002 5151 b-writer
  if wait_file "$CLIENT_LOG" "CRASH-READY" 30; then
    check 0 "committed writer reached READY"
    kill -9 "$ST_PID" 2>/dev/null
    wait "$ST_PID" 2>/dev/null
    ST_PID=""
    kill -9 "$C_PID" 2>/dev/null
    wait "$C_PID" 2>/dev/null
    C_PID=""
    if start_station "$DB_B" 17991 b2; then
      check 0 "station B restarted after hard kill (port $ACTUAL_PORT)"
      if run_client verify_present "$ACTUAL_PORT" 7002 5151 b-verify && have_ok "CRASH-VERIFY OK"; then
        check 0 "committed value present after restart"
      else
        check 1 "committed value present after restart"; print_fail
      fi
      kill -9 "$ST_PID" 2>/dev/null
      wait "$ST_PID" 2>/dev/null
      ST_PID=""
    else
      check 1 "station B restarted after hard kill"
    fi
  else
    check 1 "committed writer reached READY"
    kill -9 "$C_PID" 2>/dev/null
    C_PID=""
  fi
else
  check 1 "station B started"
fi

cleanup
if [ "$KEEP" -eq 0 ]; then
  remove_db "$DB_A"
  remove_db "$DB_B"
fi

printf 'station-crash: pass=%s fail=%s\n' "$PASS" "$FAIL"
if [ "$FAIL" -ne 0 ]; then
  printf 'station-crash: RED\n'
  exit 1
fi
printf 'station-crash: GREEN\n'
exit 0
