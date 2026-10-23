#!/usr/bin/env pwsh
# ============================================================================
# XIOM ORBITDB -- Station crash harness (ST2).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Starts the hello-station, drives an ORBITWIRE writer to a deterministic
# point, HARD-KILLS the server (TerminateProcess), restarts on the same DB
# file (the M3 shard lock must be free; the WAL must replay), and verifies:
#
#   A uncommitted: BEGIN+PUT killed before COMMIT -> key absent on restart;
#                  then a post-recovery COMMIT, kill again, value present.
#   B committed:   auto-commit PUT killed after the WAL append -> value
#                  present on restart.
#
# The DBFile is never shared across threads: the server process owns it.
# Usage: scripts/station_crash_test.ps1 [-TimeoutSec 120] [-Keep]
# Exit:  0 = green, 1 = failed.
# ============================================================================
[CmdletBinding()]
param(
    [int]$TimeoutSec = 120,
    [switch]$Keep
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "dev-env.ps1") | Out-Null

$outDir = Join-Path $repoRoot "out"
if (-not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}
$stationExe = Join-Path $outDir "orbitdb-station.exe"
$clientExe = Join-Path $outDir "station-crash-client.exe"

# Reap leftovers from an interrupted run: a running station holds its exe,
# so the build would fail with "permission denied".
Get-Process -Name "orbitdb-station","station-crash-client" -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 300

& (Join-Path $PSScriptRoot "build.ps1") (Join-Path $repoRoot "station\src\hello_station.xi") -Out $stationExe 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host "station-crash: station build failed"; exit 1 }
$clientEntry = Join-Path $repoRoot "station\tests\station_crash_client.xi"
$clientBuild = Start-Process -FilePath $env:XIOM_COMPILER `
    -ArgumentList @("-o", $clientExe, $clientEntry) -Wait -PassThru -NoNewWindow
if ($clientBuild.ExitCode -ne 0) { Write-Host "station-crash: client build failed"; exit 1 }

$script:pass = 0
$script:fail = 0

function Check([bool]$ok, [string]$name) {
    if ($ok) {
        $script:pass++
        Write-Host "  [PASS] $name"
    } else {
        $script:fail++
        Write-Host "  [FAIL] $name"
    }
}

function Remove-Db([string]$db) {
    foreach ($suffix in @("", ".snap", ".snap.rw", ".lock")) {
        Remove-Item -LiteralPath ($db + $suffix) -ErrorAction SilentlyContinue
    }
}

function Wait-FileMatch([string]$path, [string]$pattern, [int]$seconds) {
    $deadline = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $path) {
            $text = Get-Content -LiteralPath $path -Raw -ErrorAction SilentlyContinue
            if ($text -and [regex]::IsMatch($text, $pattern)) { return $true }
        }
        Start-Sleep -Milliseconds 100
    }
    return $false
}

function Start-Station([string]$db, [int]$port, [string]$tag) {
    $log = Join-Path $outDir ("station-crash-{0}.log" -f $tag)
    $err = Join-Path $outDir ("station-crash-{0}.err" -f $tag)
    $portFile = Join-Path $outDir ("station-crash-{0}.port" -f $tag)
    Remove-Item -LiteralPath $log, $err, $portFile -ErrorAction SilentlyContinue
    $env:ORBITDB_STATION_DB = $db
    $env:ORBITDB_STATION_BIND = "127.0.0.1"
    $env:ORBITDB_STATION_PORT = "$port"
    $env:ORBITDB_STATION_ORDER = "4"
    $env:ORBITDB_STATION_PAGE_FORMAT = "2"
    $env:ORBITDB_STATION_TOKEN = ""
    $env:ORBITDB_STATION_PORT_FILE = $portFile
    Write-Host "  debug: start station $tag port=$port"
    $p = Start-Process -FilePath $stationExe -PassThru -NoNewWindow `
        -RedirectStandardOutput $log -RedirectStandardError $err
    Write-Host "  debug: station $tag pid=$($p.Id)"
    $actual = -1
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline) {
        if ($p.HasExited) { break }
        if (Test-Path -LiteralPath $portFile) {
            $raw = (Get-Content -LiteralPath $portFile -Raw -ErrorAction SilentlyContinue).Trim()
            if ($raw -match '^\d+$') { $actual = [int]$raw; break }
        }
        Start-Sleep -Milliseconds 50
    }
    Write-Host "  debug: station $tag actual port=$actual"
    return [pscustomobject]@{ Proc = $p; Port = $actual; Log = $log; Err = $err }
}

function Stop-Hard($p) {
    if ($null -eq $p) { return }
    try {
        $p.Refresh()
        if (-not $p.HasExited) {
            Stop-Process -Id $p.Id -Force
            $p.WaitForExit(10000) | Out-Null
        }
    } catch { }
}

function Start-Client([string]$mode, [int]$port, [int]$key, [int]$value,
                      [string]$tag, [int]$waitSec = 60) {
    $log = Join-Path $outDir ("station-client-{0}.log" -f $tag)
    $err = Join-Path $outDir ("station-client-{0}.err" -f $tag)
    Remove-Item -LiteralPath $log, $err -ErrorAction SilentlyContinue
    $env:ORBITDB_STATION_PORT = "$port"
    $env:STATION_CRASH_MODE = $mode
    $env:STATION_CRASH_KEY = "$key"
    $env:STATION_CRASH_VALUE = "$value"
    $env:STATION_CRASH_WAIT = "$waitSec"
    Write-Host "  debug: start client $tag mode=$mode port=$port"
    $p = Start-Process -FilePath $clientExe -PassThru -NoNewWindow `
        -RedirectStandardOutput $log -RedirectStandardError $err
    Write-Host "  debug: client $tag pid=$($p.Id)"
    return [pscustomobject]@{ Proc = $p; Log = $log; Err = $err }
}

function Wait-ClientExit($c, [int]$seconds) {
    $deadline = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $deadline) {
        $c.Proc.Refresh()
        if ($c.Proc.HasExited) { return $c.Proc.ExitCode }
        Start-Sleep -Milliseconds 100
    }
    Stop-Hard $c.Proc
    return -1
}

function Read-Log($c) {
    if (Test-Path -LiteralPath $c.Log) {
        return (Get-Content -LiteralPath $c.Log -Raw -ErrorAction SilentlyContinue)
    }
    return ""
}

function Run-Client([string]$mode, [int]$port, [int]$key, [int]$value,
                    [string]$tag) {
    $c = Start-Client $mode $port $key $value $tag
    $rc = Wait-ClientExit $c 60
    $text = Read-Log $c
    return [pscustomobject]@{ Exit = $rc; Text = $text }
}

function Expect-Ok($r, [string]$token, [string]$name) {
    # A successful client prints the OK token exactly once; the Process
    # ExitCode is unreliable here (Start-Process -PassThru can leave it null
    # even after HasExited), so the protocol token is the gate.
    $ok = ($r.Text -match [regex]::Escape($token))
    Check $ok $name
    if (-not $ok) { Write-Host ("    client output={0}" -f ($r.Text.Trim())) }
}

function Stop-Client($c) {
    if ($null -eq $c) { return }
    # The writer's job was to hold the txn until the server was killed; its
    # socket/EOF state is irrelevant to recovery, so reap it immediately.
    Stop-Hard $c.Proc
}

Write-Host "station-crash: case A (uncommitted txn discarded, then commit/recover)"
$dbA = Join-Path $outDir "station-crash-a.wal"
Remove-Db $dbA
$srv = Start-Station $dbA 17990 "a1"
Check ($srv.Port -gt 0) "station A started (port $($srv.Port))"
if ($srv.Port -gt 0) {
    $w = Start-Client "writer_uncommitted" $srv.Port 7001 4242 "a-writer"
    $ready = Wait-FileMatch $w.Log "CRASH-READY" 30
    Check $ready "writer reached BEGIN+PUT"
    Stop-Hard $srv.Proc
    Stop-Client $w
    $srv2 = Start-Station $dbA 17990 "a2"
    Check ($srv2.Port -gt 0) "station A restarted after hard kill (port $($srv2.Port))"
    if ($srv2.Port -gt 0) {
        $v = Run-Client "verify_absent" $srv2.Port 7001 4242 "a-verify-absent"
        Expect-Ok $v "CRASH-VERIFY OK" "uncommitted txn discarded on restart"
        $c = Run-Client "commit" $srv2.Port 7001 4242 "a-commit"
        Expect-Ok $c "CRASH-COMMIT OK" "post-recovery commit"
        Stop-Hard $srv2.Proc
        $srv3 = Start-Station $dbA 17990 "a3"
        Check ($srv3.Port -gt 0) "station A restarted after committed kill (port $($srv3.Port))"
        if ($srv3.Port -gt 0) {
            $v2 = Run-Client "verify_present" $srv3.Port 7001 4242 "a-verify-present"
            Expect-Ok $v2 "CRASH-VERIFY OK" "committed value survived the second kill"
            Stop-Hard $srv3.Proc
        }
    }
}

Write-Host "station-crash: case B (committed write survives a hard kill)"
$dbB = Join-Path $outDir "station-crash-b.wal"
Remove-Db $dbB
$srvB = Start-Station $dbB 17991 "b1"
Check ($srvB.Port -gt 0) "station B started (port $($srvB.Port))"
if ($srvB.Port -gt 0) {
    $wB = Start-Client "writer_committed" $srvB.Port 7002 5151 "b-writer"
    $readyB = Wait-FileMatch $wB.Log "CRASH-READY" 30
    Check $readyB "committed writer reached READY"
    Stop-Hard $srvB.Proc
    Stop-Client $wB
    $srvB2 = Start-Station $dbB 17991 "b2"
    Check ($srvB2.Port -gt 0) "station B restarted after hard kill (port $($srvB2.Port))"
    if ($srvB2.Port -gt 0) {
        $vB = Run-Client "verify_present" $srvB2.Port 7002 5151 "b-verify"
        Expect-Ok $vB "CRASH-VERIFY OK" "committed value present after restart"
        Stop-Hard $srvB2.Proc
    }
}

# No process may still hold the DB files before cleanup.
Get-Process -Name "orbitdb-station","station-crash-client" -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
if (-not $Keep) {
    Remove-Db $dbA
    Remove-Db $dbB
}

Write-Host ("station-crash: pass={0} fail={1}" -f $script:pass, $script:fail)
if ($script:fail -ne 0) {
    Write-Host "station-crash: RED"
    exit 1
}
Write-Host "station-crash: GREEN"
exit 0
