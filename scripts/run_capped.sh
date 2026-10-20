#!/usr/bin/env bash
# ============================================================================
# XIOM ORBITDB -- RAM-capped process runner (owner directive 2026-10-20).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage: MAX_RAM_GB=4 TIMEOUT_SEC=300 scripts/run_capped.sh <binary> [args...]
# Kills the child at the cap (exit 137) or timeout (124); prints peak RSS.
set -u

if [ $# -lt 1 ]; then
  echo "usage: MAX_RAM_GB=4 $0 <binary> [args...]"
  exit 2
fi
MAX_RAM_GB="${MAX_RAM_GB:-4}"
TIMEOUT_SEC="${TIMEOUT_SEC:-0}"
cap_kb=$((MAX_RAM_GB * 1024 * 1024))

"$@" &
pid=$!
peak=0
start=$(date +%s)
while kill -0 "$pid" 2>/dev/null; do
  rss=$(awk '/VmRSS/{print $2}' /proc/$pid/status 2>/dev/null)
  if [ -n "$rss" ]; then
    if [ "$rss" -gt "$cap_kb" ]; then
      echo "RAM-CAP [$1]: killed at $((rss / 1024)) MB (cap ${MAX_RAM_GB} GB)"
      kill -9 "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      exit 137
    fi
    [ "$rss" -gt "$peak" ] && peak=$rss
  fi
  if [ "$TIMEOUT_SEC" -gt 0 ] && [ $(( $(date +%s) - start )) -gt "$TIMEOUT_SEC" ]; then
    echo "RAM-CAP [$1]: timeout after ${TIMEOUT_SEC}s (peak $((peak / 1024)) MB)"
    kill -9 "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    exit 124
  fi
  sleep 0.5
done
wait "$pid"
rc=$?
echo "RAM-CAP [$1]: exit=$rc peak=$((peak / 1024)) MB (cap ${MAX_RAM_GB} GB)"
exit $rc
