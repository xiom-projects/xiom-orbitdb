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
# As of 2026-10-17 (compiler v0.64.6 adoption):
#   compiler  v0.64.6  %LOCALAPPDATA%\xiom.new-20261016-233955\bin\xiom.exe
#     (official v0.64.6 extract; xiom.exe sha256 0ff5c5c471498d8c... --
#     release run 38962236697; the extraction dir is DATE-SUFFIXED this
#     time and is the owner/ops artifact -- left as-is. The canonical
#     %LOCALAPPDATA%\xiom.new belongs to the fleet and is left untouched;
#     canonical swaps are owner/ops-coordinated, this lane pins explicitly.)
#   stdlib    E:\xiom-lang\stdlib (stdlib-lane checkout = latest lane work)
#   packages  %LOCALAPPDATA%\xiom\packages (registry, signature-verified)
#
# XIOM_RUNTIME_DIR: the 2026-10-13 lane-runtime override (M1.2 S4: waves
# 115/117/118 durability/byte-IO primitives) is DROPPED as of 2026-10-15:
# the v0.64.6 archive re-vendors stdlib/runtime carrying wave 139 (>> 115),
# so the stock pin is the authoritative runtime again. The script actively
# unsets any stale XIOM_RUNTIME_DIR inherited from the shell environment.
#
# PATH warning: a stale staging dir (xiom.new-<date>) shadows xiom.new in
# PATH -- always set XIOM_COMPILER explicitly instead of relying on `xiom`.
#
# xiom doctor note: it warns when the BUNDLED stdlib (installed lib/) is
# older than the compiler, and about the stale second binary on PATH. Both
# are environment noise for this lane: XIOM_STDLIB points at the lane
# checkout, which is the authority for builds here.

$ErrorActionPreference = "Stop"

$env:XIOM_COMPILER = Join-Path $env:LOCALAPPDATA "xiom.new-20261016-233955\bin\xiom.exe"
$env:XIOM_STDLIB   = "E:\xiom-lang\stdlib"
# Stock runtime (v0.64.5 re-vendor carries wave 139): never inherit a stale
# lane-runtime override from the surrounding shell.
Remove-Item Env:XIOM_RUNTIME_DIR -ErrorAction SilentlyContinue

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
Write-Host "dev-env: XIOM_RUNTIME_DIR = <unset> (stock v0.64.6 runtime; override retired 2026-10-15)"
