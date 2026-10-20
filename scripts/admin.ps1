#!/usr/bin/env pwsh
# ============================================================================
# XIOM ORBITDB admin web client -- build and run (localhost only).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage:
#   .\scripts\admin.ps1                          # orbitdb-admin.wal :8787
#   .\scripts\admin.ps1 -Database data\app.wal -Port 9000
#
# The admin OWNS its database file while it runs. Do not point it at a DB
# currently opened by another process (the engine has no read-only open /
# cross-process pin contract yet; that is the M3 remainder).
[CmdletBinding()]
param(
    [string]$Database = "orbitdb-admin.wal",
    [int]$Port = 8787,
    [int]$MaxRAMGB = 2
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "dev-env.ps1")

$env:PULSE_BIND = "127.0.0.1"
$env:PULSE_PORT = "$Port"
$env:ORBITDB_ADMIN_DB = $Database

$outDir = Join-Path $repoRoot "out"
if (-not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}
$exe = Join-Path $outDir "orbitdb-admin.exe"
& $env:XIOM_COMPILER -o $exe (Join-Path $repoRoot "admin\src\admin.xi")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Push-Location $repoRoot
try {
    & (Join-Path $PSScriptRoot "run_capped.ps1") -FilePath $exe -MaxRAMGB $MaxRAMGB -Description "orbitdb-admin"
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
