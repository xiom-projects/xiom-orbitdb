# XIOM ORBITDB dev environment -- dot-source in every terminal:
#   . .\scripts\dev-env.ps1
#
# VERSION POLICY (owner decision, inherited from PULSE): ORBITDB tracks the
# LATEST compiler / stdlib / packages to harden the ecosystem by real-world
# use. There is no fixed pin; record the exact versions and lane hashes in
# SESSION.md at every wrap. If a latest-version regression breaks the fleet,
# file the finding, note the last known-good version in SESSION.md as a
# ROLLBACK OPTION, and keep moving on other slices.
#
# As of 2026-10-12 (compiler v0.64.4 release):
#   compiler  v0.64.4  %LOCALAPPDATA%\xiom.new.0644\bin\xiom.exe
#     (shadow install of the v0.64.4 release, sha256 44a41aea... verified
#     against SHA256SUMS; the canonical %LOCALAPPDATA%\xiom.new is still
#     v0.64.2 and is left untouched -- other lanes share it. Canonical swap
#     is owner/ops-coordinated; this lane pins explicitly.)
#   stdlib    E:\xiom-lang\stdlib (stdlib-lane checkout = latest lane work)
#   packages  %LOCALAPPDATA%\xiom\packages (registry, signature-verified)
#
# XIOM_RUNTIME_DIR is RETIRED on v0.64.0: release R65 makes the installed
# compiler link lib\runtime and lib\xiom without overrides.
#
# PATH warning: a stale staging dir (xiom.new-<date>) shadows xiom.new in
# PATH -- always set XIOM_COMPILER explicitly instead of relying on `xiom`.
#
# xiom doctor note: it warns when the BUNDLED stdlib (installed lib/) is
# older than the compiler, and about the stale second binary on PATH. Both
# are environment noise for this lane: XIOM_STDLIB points at the lane
# checkout, which is the authority for builds here.

$ErrorActionPreference = "Stop"

$env:XIOM_COMPILER = Join-Path $env:LOCALAPPDATA "xiom.new.0644\bin\xiom.exe"
$env:XIOM_STDLIB   = "E:\xiom-lang\stdlib"
Remove-Item Env:XIOM_RUNTIME_DIR -ErrorAction SilentlyContinue   # retired

$missing = @()
if (-not (Test-Path -LiteralPath $env:XIOM_COMPILER)) { $missing += "XIOM_COMPILER ($env:XIOM_COMPILER)" }
if (-not (Test-Path -LiteralPath $env:XIOM_STDLIB))   { $missing += "XIOM_STDLIB   ($env:XIOM_STDLIB)" }

if ($missing.Count -gt 0) {
    Write-Warning "dev-env: missing toolchain paths:"
    $missing | ForEach-Object { Write-Warning "  $_" }
    return
}

$ver = (& $env:XIOM_COMPILER --version 2>&1 | Select-Object -First 1)
Write-Host "dev-env: $ver"
Write-Host "dev-env: XIOM_STDLIB = $env:XIOM_STDLIB"
Write-Host "dev-env: XIOM_RUNTIME_DIR retired (v0.64.0 R65 install-layout fix)"
