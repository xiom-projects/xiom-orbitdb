#!/usr/bin/env pwsh
# ============================================================================
# XIOM ORBITDB file-backed DB crash/recovery test (WAL-before-ack).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Drives tests\probes\probe_db_file.xi (three crash scenarios per run):
#   A. WAL-only: writer puts N keys, hard-kill, torn tail, reopen recovers N,
#      heal + put one more -> N+1.
#   B. snapshot-only: writer puts N keys + checkpoint, hard-kill before any
#      tail write, torn tail, reopen recovers N from the snapshot alone.
#   C. snapshot + tail: writer checkpoints after N, appends Tail more keys,
#      hard-kill mid-tail, reopen recovers N+Tail (snapshot + tail replay).
#
# Usage: .\scripts\db_crash_test.ps1 [-Keys 20] [-Tail 3] [-TimeoutSec 90]
# Exit:  0 = green, 1 = failed.
# ============================================================================
[CmdletBinding()]
param(
    [int]$Keys = 20,
    [int]$Tail = 3,
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
Remove-Item -LiteralPath $walFile, "$walFile.snap" -Force -ErrorAction SilentlyContinue

$pass = 0; $fail = 0
function Check {
    param([string]$Name, [bool]$Ok)
    if ($Ok) { Write-Host "[PASS] $Name"; $script:pass++ }
    else { Write-Host "[FAIL] $Name"; $script:fail++ }
}

function Invoke-DbMode {
    param([string]$Mode, [int]$N, [string]$LastKey = "", [string]$LastVal = "", [string]$Path = "")
    if (-not $Path) { $Path = $walFile }
    $env:ORBITDB_DB_FILE = $Path
    $env:ORBITDB_DB_MODE = $Mode
    $env:ORBITDB_DB_N = "$N"
    if ($LastKey) { $env:ORBITDB_DB_LAST_KEY = $LastKey } else { Remove-Item Env:ORBITDB_DB_LAST_KEY -ErrorAction SilentlyContinue }
    if ($LastVal) { $env:ORBITDB_DB_LAST_VAL = $LastVal } else { Remove-Item Env:ORBITDB_DB_LAST_VAL -ErrorAction SilentlyContinue }
    & (Join-Path $PSScriptRoot "run.ps1") $probe -TimeoutSec 180 -Quiet | Out-Null
    return $LASTEXITCODE
}

function Start-Writer {
    param([string]$Mode, [int]$N, [int]$T, [string]$OutName, [string]$Path)
    $env:ORBITDB_DB_FILE = $Path
    $env:ORBITDB_DB_MODE = $Mode
    $env:ORBITDB_DB_N = "$N"
    $env:ORBITDB_DB_TAIL = "$T"
    $out = Join-Path $logDir "$OutName.out"
    $err = Join-Path $logDir "$OutName.err"
    return Start-Process -FilePath $env:XIOM_COMPILER -ArgumentList @("--run", $probe) `
        -WorkingDirectory $repoRoot -NoNewWindow -PassThru `
        -RedirectStandardOutput $out -RedirectStandardError $err
}

function Stop-Writer {
    param([System.Diagnostics.Process]$Writer)
    if (-not $Writer.HasExited) {
        try { & taskkill /T /F /PID $Writer.Id | Out-Null } catch { }
        $Writer.WaitForExit(10000) | Out-Null
    }
}

# Wait until the snapshot file exists and the WAL holds exactly ExpectedLines
# non-empty records (the writer hangs after that point). Returns the observed
# line count (-1 when the wait timed out or the writer exited early).
function Wait-ForCkptPoint {
    param([System.Diagnostics.Process]$Writer, [string]$Path, [string]$SnapPath,
          [int]$ExpectedLines, [int]$TimeoutSec)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $observed = -1
    while ((Get-Date) -lt $deadline) {
        if ((Test-Path -LiteralPath $SnapPath) -and (Test-Path -LiteralPath $Path)) {
            $observed = @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue |
                          Where-Object { $_ -ne "" }).Count
            if ($observed -eq $ExpectedLines) { break }
        }
        if ($Writer.HasExited) { break }
        Start-Sleep -Milliseconds 300
    }
    return $observed
}

# --- scenario A / phase 1: writer puts Keys records, then hangs -------------
$writer = Start-Writer -Mode "write" -N $Keys -T 0 -OutName "dbfile-writer" -Path $walFile

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
Stop-Writer -Writer $writer
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

# --- scenario B: checkpoint, kill before any tail (snapshot-only recovery) --
$ckptWal = Join-Path $logDir "crash-dbfile-ckpt.wal"
$ckptSnap = "$ckptWal.snap"
Remove-Item -LiteralPath $ckptWal, $ckptSnap -Force -ErrorAction SilentlyContinue
$writer = Start-Writer -Mode "ckpt" -N $Keys -T 0 -OutName "dbfile-writer-ckpt" -Path $ckptWal
$observed = Wait-ForCkptPoint -Writer $writer -Path $ckptWal -SnapPath $ckptSnap `
    -ExpectedLines 1 -TimeoutSec $TimeoutSec
Check "ckpt writer reached snapshot-only point (observed=$observed)" ($observed -eq 1)
Stop-Writer -Writer $writer
Add-Content -LiteralPath $ckptWal -Value "torn|" -NoNewline

$rc = Invoke-DbMode -Mode "verify" -N $Keys -Path $ckptWal
Check "ckpt reopen recovers $Keys keys from snapshot alone (torn ignored)" ($rc -eq 0)
$rc = Invoke-DbMode -Mode "put1" -N $Keys -Path $ckptWal
Check "ckpt put after snapshot recovery heals tail (put1 exit 0)" ($rc -eq 0)
$rc = Invoke-DbMode -Mode "verify" -N ($Keys + 1) -LastKey "9999" -LastVal "99990" -Path $ckptWal
Check "ckpt reopen recovers $($Keys + 1) keys incl. healed put" ($rc -eq 0)

# --- scenario C: checkpoint + tail, kill mid-tail (snapshot + tail replay) --
$tailWal = Join-Path $logDir "crash-dbfile-tail.wal"
$tailSnap = "$tailWal.snap"
Remove-Item -LiteralPath $tailWal, $tailSnap -Force -ErrorAction SilentlyContinue
$writer = Start-Writer -Mode "ckpt" -N $Keys -T $Tail -OutName "dbfile-writer-tail" -Path $tailWal
$observed = Wait-ForCkptPoint -Writer $writer -Path $tailWal -SnapPath $tailSnap `
    -ExpectedLines (1 + $Tail) -TimeoutSec $TimeoutSec
Check "ckpt+tail writer wrote snapshot + $Tail tail keys (observed=$observed)" ($observed -eq (1 + $Tail))
Stop-Writer -Writer $writer
Add-Content -LiteralPath $tailWal -Value "torn|" -NoNewline

$rc = Invoke-DbMode -Mode "verify" -N ($Keys + $Tail) -Path $tailWal
Check "ckpt+tail reopen recovers $($Keys + $Tail) keys (snapshot + tail replay)" ($rc -eq 0)
$rc = Invoke-DbMode -Mode "put1" -N ($Keys + $Tail) -Path $tailWal
Check "ckpt+tail put after recovery heals tail (put1 exit 0)" ($rc -eq 0)
$rc = Invoke-DbMode -Mode "verify" -N ($Keys + $Tail + 1) -LastKey "9999" -LastVal "99990" -Path $tailWal
Check "ckpt+tail reopen recovers $($Keys + $Tail + 1) keys incl. healed put" ($rc -eq 0)

Write-Host ("crash: pass={0} fail={1}" -f $pass, $fail)
if ($fail -eq 0) { Write-Host "db-crash: GREEN"; exit 0 }
Write-Host "db-crash: RED"
exit 1
