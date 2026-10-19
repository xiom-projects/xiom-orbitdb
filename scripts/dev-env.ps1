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
# As of 2026-10-19 (compiler v0.64.8 adoption):
#   compiler  v0.64.8  %LOCALAPPDATA%\xiom-0.64.8\bin\xiom.exe
#     (official v0.64.8 extract; xiom-0.64.8-windows-x64.zip sha256
#     c31d9c464a4f9489... SHA256SUMS-verified; xiom.exe sha256
#     ee3ee902307770a0... -- release 2026-10-19T17:49Z, run 39296778685.
#     The dated extraction is lane-local and additive; the canonical
#     %LOCALAPPDATA%\xiom.new belongs to the fleet and is left untouched.)
#   stdlib    the compiler-bundled RELEASE (v0.64.8, stdlib-v0.64.8 pin
#             tag 1271dd5; registry publish owner-approved). Owner directive
#             2026-10-17: ALWAYS use the latest RELEASED stdlib (that is
#             where requested fixes land) -- the lanes' checkout is
#             early-warning/WIP and is opt-in only: set XIOM_STDLIB
#             explicitly before dot-sourcing to run against
#             E:\xiom-lang\stdlib (never edit that tree).
#   packages  %LOCALAPPDATA%\xiom\packages (registry, signature-verified;
#             latest published versions -- btree 0.1.1 / wal 0.1.0 /
#             vectors 0.1.0 installed 2026-10-17)
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

$env:XIOM_COMPILER = Join-Path $env:LOCALAPPDATA "xiom-0.64.8\bin\xiom.exe"
# RELEASE stdlib by default (bundled in the v0.64.6 archive). An explicit
# XIOM_STDLIB inherited from the shell stays (opt-in early-warning runs
# against the stdlib lane checkout) -- this script never forces it.
# Stock runtime (v0.64.6 re-vendor carries wave 139): never inherit a stale
# lane-runtime override from the surrounding shell.
Remove-Item Env:XIOM_RUNTIME_DIR -ErrorAction SilentlyContinue

$missing = @()
if (-not (Test-Path -LiteralPath $env:XIOM_COMPILER)) { $missing += "XIOM_COMPILER ($env:XIOM_COMPILER)" }

if ($missing.Count -gt 0) {
    Write-Warning "dev-env: missing toolchain paths:"
    $missing | ForEach-Object { Write-Warning "  $_" }
    return
}

$ver = (& $env:XIOM_COMPILER --version 2>&1 | Select-Object -First 1)
Write-Host "dev-env: $ver"
Write-Host ("dev-env: XIOM_STDLIB = " + $(if ($env:XIOM_STDLIB) { $env:XIOM_STDLIB + " (OPT-IN checkout)" } else { "<unset -> bundled RELEASE stdlib v0.64.8>" }))
Write-Host "dev-env: XIOM_RUNTIME_DIR = <unset> (stock v0.64.8 runtime; override retired 2026-10-15)"
