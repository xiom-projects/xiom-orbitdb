#!/usr/bin/env pwsh
# ============================================================================
# XIOM ORBITDB Station -- build and run the hello-station (ORBITWIRE v1).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage:
#   .\scripts\station.ps1                          # orbitdb-station.wal :7767
#   .\scripts\station.ps1 -Database data\app.wal -Port 9000
#   .\scripts\station.ps1 -Token s3cret            # require AUTH
#
# The Station OWNS its database while it runs (M3 shard lock). Do not point it
# at a DB currently opened by another process.
[CmdletBinding()]
param(
    [string]$Database = "orbitdb-station.wal",
    [int]$Port = 7767,
    [string]$Bind = "127.0.0.1",
    [int]$Order = 4,
    [int]$MaxRAMGB = 4,
    [string]$Token = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "dev-env.ps1")

$env:ORBITDB_STATION_DB = $Database
$env:ORBITDB_STATION_BIND = $Bind
$env:ORBITDB_STATION_PORT = "$Port"
$env:ORBITDB_STATION_ORDER = "$Order"
$env:ORBITDB_STATION_PAGE_FORMAT = "2"
$env:ORBITDB_STATION_TOKEN = $Token

$outDir = Join-Path $repoRoot "out"
if (-not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}
$exe = Join-Path $outDir "orbitdb-station.exe"
& (Join-Path $PSScriptRoot "build.ps1") (Join-Path $repoRoot "station\src\hello_station.xi") -Out $exe
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Push-Location $repoRoot
try {
    & (Join-Path $PSScriptRoot "run_capped.ps1") -FilePath $exe -MaxRAMGB $MaxRAMGB -Description "orbitdb-station"
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
