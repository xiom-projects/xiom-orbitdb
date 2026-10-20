#!/usr/bin/env pwsh
# ============================================================================
# XIOM ORBITDB -- RAM-capped process runner (owner directive 2026-10-20).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Starts an app/probe binary and kills it when its working set exceeds
# -MaxRAMGB (default 4 GB) or -TimeoutSec elapses (0 = no timeout). The
# m375 class of per-I/O retention can balloon to tens of GB and hard-crash
# the host, so memory-sensitive apps (admin, soak, bench probes) MUST run
# through this wrapper.
#
# Usage:
#   .\scripts\run_capped.ps1 -FilePath .\out\orbitdb-soak.exe -MaxRAMGB 4
#   .\scripts\run_capped.ps1 -FilePath .\out\probe_mem_read.exe -Arguments @() -MaxRAMGB 2 -TimeoutSec 120
#
# Exit: the child's exit code; 137 = RAM cap hit (killed); 124 = timeout.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$FilePath,
    [string[]]$Arguments = @(),
    [int]$MaxRAMGB = 4,
    [int]$TimeoutSec = 0,
    [string]$Description = ""
)

$ErrorActionPreference = "Stop"
if ($MaxRAMGB -lt 1) { throw "MaxRAMGB must be >= 1" }
$capBytes = [int64]$MaxRAMGB * 1GB
$label = if ($Description) { $Description } else { Split-Path -Leaf $FilePath }

if ($Arguments.Count -gt 0) {
    $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments -PassThru -NoNewWindow
} else {
    $p = Start-Process -FilePath $FilePath -PassThru -NoNewWindow
}
$peak = 0
$start = Get-Date
while (-not $p.HasExited) {
    try {
        $p.Refresh()
        if ($p.WorkingSet64 -gt $peak) { $peak = $p.WorkingSet64 }
        if ($p.WorkingSet64 -gt $capBytes) {
            Stop-Process -Id $p.Id -Force
            $p.WaitForExit()
            Write-Host ("RAM-CAP [{0}]: killed at {1:N1} MB (cap {2} GB)" -f `
                $label, ($p.WorkingSet64 / 1MB), $MaxRAMGB)
            exit 137
        }
    } catch { }
    if ($TimeoutSec -gt 0 -and (((Get-Date) - $start).TotalSeconds -gt $TimeoutSec)) {
        Stop-Process -Id $p.Id -Force
        $p.WaitForExit()
        Write-Host ("RAM-CAP [{0}]: timeout after {1}s (peak {2:N1} MB)" -f `
            $label, $TimeoutSec, ($peak / 1MB))
        exit 124
    }
    Start-Sleep -Milliseconds 500
}
$p.WaitForExit()
$elapsed = [math]::Round(((Get-Date) - $start).TotalSeconds, 1)
Write-Host ("RAM-CAP [{0}]: exit={1} elapsed={2}s peak={3:N1} MB (cap {4} GB)" -f `
    $label, $p.ExitCode, $elapsed, ($peak / 1MB), $MaxRAMGB)
exit $p.ExitCode
