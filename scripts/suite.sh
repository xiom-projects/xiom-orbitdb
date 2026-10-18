#!/usr/bin/env bash
# ============================================================================
# XIOM ORBITDB conformance-suite runner -- sums the split suite (R2).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage:
#   scripts/suite.sh                 # every tests/suite/*.xi, run twice
#   scripts/suite.sh --timeout-sec 600
#
# Each suite file is a standalone program returning its failure count and
# printing `XIOM DB Conformance [<area>]: P/T passed`. This runner executes
# every file TWICE (the suite x2 rule), requires identical P/T in both rounds
# and zero failures, then sums the per-area counts. Exit 0 = green, 1 = red.
# ============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SUITE_DIR="$REPO_ROOT/tests/suite"
RUNNER="$SCRIPT_DIR/run.sh"

TIMEOUT=300
if [ $# -gt 0 ]; then
  case "$1" in
    --timeout-sec) TIMEOUT=${2:?missing value} ;;
    *) echo "suite: unknown argument: $1"; exit 1 ;;
  esac
fi

if [ ! -d "$SUITE_DIR" ]; then
  echo "suite: missing $SUITE_DIR"
  exit 1
fi

sum_pass=0
sum_total=0
bad=0
count=0

for f in $(ls "$SUITE_DIR"/*.xi | grep -v '/suite_common.xi$'); do
  count=$((count + 1))
  r1_pass=-1; r1_total=-1; r1_exit=-1
  r2_pass=-1; r2_total=-1; r2_exit=-1
  for round in 1 2; do
    out="$("$RUNNER" "$f" --timeout-sec "$TIMEOUT" 2>&1)"
    rc=$?
    line="$(printf '%s\n' "$out" | sed -n 's/.*XIOM DB Conformance \[\([a-z_]*\)\]: *\([0-9]*\)\/\([0-9]*\) passed.*/\2 \3/p' | tail -1)"
    if [ -z "$line" ]; then
      echo "suite: $(basename "$f") round $round: NO SUMMARY (exit $rc)"
      printf '%s\n' "$out" | grep -m1 '^error' || true
      bad=$((bad + 1))
      break
    fi
    set -- $line
    if [ "$round" -eq 1 ]; then
      r1_pass=$1; r1_total=$2; r1_exit=$rc
    else
      r2_pass=$1; r2_total=$2; r2_exit=$rc
    fi
  done

  if [ "$r1_pass" -lt 0 ] || [ "$r2_pass" -lt 0 ]; then
    continue
  fi
  if [ "$r1_pass" -eq "$r2_pass" ] && [ "$r1_total" -eq "$r2_total" ] &&
     [ "$r1_exit" -eq 0 ] && [ "$r2_exit" -eq 0 ] &&
     [ "$r1_pass" -eq "$r1_total" ]; then
    printf 'suite: %-18s %s/%s x2\n' "$(basename "$f" .xi)" "$r1_pass" "$r1_total"
    sum_pass=$((sum_pass + r1_pass))
    sum_total=$((sum_total + r1_total))
  else
    printf 'suite: %-18s RED (r1 %s/%s exit %s; r2 %s/%s exit %s)\n' \
      "$(basename "$f" .xi)" "$r1_pass" "$r1_total" "$r1_exit" "$r2_pass" "$r2_total" "$r2_exit"
    bad=$((bad + 1))
  fi
done

echo "suite: $sum_pass/$sum_total passed x2 across $count files"
if [ "$bad" -ne 0 ]; then
  echo "suite: RED"
  exit 1
fi
echo "suite: GREEN"
exit 0
