#!/usr/bin/env pwsh
# ============================================================================
# XIOM ORBITDB file-backed DB crash/recovery test (WAL-before-ack).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Drives tests\probes\probe_db_file.xi:
#   1. writer puts N keys through DBFile (append-then-apply), then hangs;
#   2. hard-kill the writer process tree once N records are on disk;
#   3. append a torn tail (no newline) -- crash mid-record;
#   4. reopen: replay the segment, recover exactly N keys (torn skipped);
#   5. put one more key (tail healed) and recover N+1.
#
# Usage: .\scripts\db_crash_test.ps1 [-Keys 20] [-TimeoutSec 90]
# Exit:  0 = green, 1 = failed.
# ============================================================================
[CmdletBinding()]
param(
    [int]$Keys = 20,
    [int]$TimeoutSec = 90
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $repoRoot "probe-logs"
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }

if (-not $env:XIOM_COMPILER -or -not (Test-Path -LiteralPath $env:XIOM_COMPILER)) {
    . (Join-Path $PSScriptRoot "dev-env.ps1")
    if (-not $env:XIOM_COMPILER) { throw "XIOM_COMPILER not resolved" }
}

$probe = Join-Path $repoRoot "tests\probes\probe_db_file.xi"
$walFile = Join-Path $logDir "crash-dbfile.wal"
if (Test-Path -LiteralPath $walFile) { Remove-Item -LiteralPath $walFile -Force }

$pass = 0; $fail = 0
function Check {
    param([string]$Name, [bool]$Ok)
    if ($Ok) { Write-Host "[PASS] $Name"; $script:pass++ }
    else { Write-Host "[FAIL] $Name"; $script:fail++ }
}

function Invoke-DbMode {
    param([string]$Mode, [int]$N, [string]$LastKey = "", [string]$LastVal = "")
    $env:ORBITDB_DB_FILE = $walFile
    $env:ORBITDB_DB_MODE = $Mode
    $env:ORBITDB_DB_N = "$N"
    if ($LastKey) { $env:ORBITDB_DB_LAST_KEY = $LastKey } else { Remove-Item Env:ORBITDB_DB_LAST_KEY -ErrorAction SilentlyContinue }
    if ($LastVal) { $env:ORBITDB_DB_LAST_VAL = $LastVal } else { Remove-Item Env:ORBITDB_DB_LAST_VAL -ErrorAction SilentlyContinue }
    & (Join-Path $PSScriptRoot "run.ps1") $probe -TimeoutSec 180 -Quiet | Out-Null
    return $LASTEXITCODE
}

# --- phase 1: writer puts Keys records, then hangs --------------------------
$env:ORBITDB_DB_FILE = $walFile
$env:ORBITDB_DB_MODE = "write"
$env:ORBITDB_DB_N = "$Keys"
$writerOut = Join-Path $logDir "dbfile-writer.out"
$writerErr = Join-Path $logDir "dbfile-writer.err"
$writer = Start-Process -FilePath $env:XIOM_COMPILER -ArgumentList @("--run", $probe) `
    -WorkingDirectory $repoRoot -NoNewWindow -PassThru `
    -RedirectStandardOutput $writerOut -RedirectStandardError $writerErr

$deadline = (Get-Date).AddSeconds($TimeoutSec)
$observed = 0
while ((Get-Date) -lt $deadline) {
    if (Test-Path -LiteralPath $walFile) {
        $observed = @(Get-Content -LiteralPath $walFile -ErrorAction SilentlyContinue).Count
        if ($observed -ge $Keys) { break }
    }
    if ($writer.HasExited) { break }
    Start-Sleep -Milliseconds 300
}
Check "writer put $Keys keys (observed=$observed)" ($observed -ge $Keys)

# --- phase 2: hard-kill + torn tail ----------------------------------------
if (-not $writer.HasExited) {
    try { & taskkill /T /F /PID $writer.Id | Out-Null } catch { }
    $writer.WaitForExit(10000) | Out-Null
}
Add-Content -LiteralPath $walFile -Value "torn|" -NoNewline
Write-Host ("crash: killed writer, segment={0} bytes, torn tail appended" -f (Get-Item -LiteralPath $walFile).Length)

# --- phase 3: reopen, replay must recover exactly Keys keys ----------------
$rc = Invoke-DbMode -Mode "verify" -N $Keys
Check "reopen recovers $Keys keys (WAL replay, torn skipped)" ($rc -eq 0)

# --- phase 4: heal + put one more key --------------------------------------
$rc = Invoke-DbMode -Mode "put1" -N $Keys
Check "put after torn tail heals (put1 exit 0)" ($rc -eq 0)

# --- phase 5: N+1 and last-key integrity ------------------------------------
$rc = Invoke-DbMode -Mode "verify" -N ($Keys + 1) -LastKey "9999" -LastVal "99990"
Check "reopen recovers $($Keys + 1) keys incl. healed put" ($rc -eq 0)

Write-Host ("crash: pass={0} fail={1}" -f $pass, $fail)
if ($fail -eq 0) { Write-Host "db-crash: GREEN"; exit 0 }
Write-Host "db-crash: RED"
exit 1
