#!/usr/bin/env bash
# ============================================================================
# XIOM ORBITDB -- run the lane from a local ext4 copy inside WSL.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# `/mnt/e` (DrvFs/9p) can stall in p9_client_rpc under the large-snapshot
# battery (D state), which false-REDs suites/crash/hybrid. This mirrors the
# lane sources into the WSL filesystem and runs the command there.
#
# Usage (from anywhere):
#   scripts/wsl_ext4.sh ./scripts/suite.sh
#   scripts/wsl_ext4.sh ./scripts/db_crash_test.sh
#   scripts/wsl_ext4.sh ./scripts/run.sh tests/suite/foundations.xi
#
# Env: ORBITDB_WSL_SRC (default /mnt/e/xiom-projects/xiom-orbitdb)
#      ORBITDB_WSL_CACHE (default ~/.cache/orbitdb-lane)
set -u

SRC="${ORBITDB_WSL_SRC:-/mnt/e/xiom-projects/xiom-orbitdb}"
DST="${ORBITDB_WSL_CACHE:-$HOME/.cache/orbitdb-lane}"
XVEC="${ORBITDB_XVECTOR_SRC:-/mnt/e/xiom-projects/xiom-xvector}"

if [ $# -lt 1 ]; then
  echo "usage: $0 <command...>   (runs in $DST)"
  exit 2
fi
if [ ! -d "$SRC/src" ]; then
  echo "wsl-ext4: missing lane source at $SRC"
  exit 1
fi

rm -rf "$DST"
mkdir -p "$DST"
cp -r "$SRC/src" "$SRC/tests" "$SRC/scripts" "$SRC/admin" "$SRC/docs" "$SRC/package.xi" "$DST/"
# Hybrid manifest: ../../../xiom-xvector from tests/hybrid -> ~/.cache/xiom-xvector
ln -sfn "$XVEC" "$HOME/.cache/xiom-xvector"

cd "$DST" || exit 1
"$@"
