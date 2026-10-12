<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# C-ORBIT-10 repro: `xiom --check` exits 0 on the Linux build even when it reports errors

**Compiler:** v0.64.4.
**Windows:** shadow install `%LOCALAPPDATA%\xiom.new.0644\bin\xiom.exe`
(sha256 `44a41aea79891612edef7fd917a1a693c1ba0acbc1a698cf7edaefa5984e544f`,
== `xiom-0.64.4-windows-x64.zip`).
**WSL:** canonical `~/.local/share/xiom/bin/xiom` (sha256
`d0a43a5c216392916df4dc1febe860816ccf2f38475b4a41110e75d3f88aadc2`, ==
`xiom-0.64.4-linux-x64.tar.gz` `bin/xiom` -- official artifacts both).

**Found by:** the ORBITDB v0.64.4 verdict wave (2026-10-12): the phantom
bundle's `--check` verdicts came back with exit code 0 on WSL while the same
commands exit 1 on Windows.

## Files

- `probe_type.xi` -- a T001 type error (`undefined_symbol_repro`).
- `probe_syntax.xi` -- a P001 syntax error (missing `;` / closing structure).

## Commands and observed results (v0.64.4)

```
Windows: xiom.exe --check docs\repro\check-exit-code\probe_type.xi    -> rc 1
         xiom.exe --check docs\repro\check-exit-code\probe_syntax.xi  -> rc 1
         xiom.exe --check docs\repro\consumer-fn-hijack\mod_svc.xi    -> rc 0

WSL:     xiom --check docs/repro/check-exit-code/probe_type.xi        -> rc 0   (!)
         xiom --check docs/repro/check-exit-code/probe_syntax.xi      -> rc 0   (!)
         xiom --check docs/repro/consumer-fn-hijack/mod_svc.xi        -> rc 0
```

The Linux build still PRINTS the diagnostics (e.g. `error[P001]: 7:1:
expected ';', found` then `error: compilation failed` for `probe_syntax.xi`),
but the process exit status is 0 in every case, including clean failures.
The Windows build of the same release exits 1 whenever errors were reported.

## Impact

Any Linux/WSL automation that branches on `--check`'s exit code
false-passes: CI gates, release-check scripts, "is this tree green" loops.
A gating script `xiom --check f.xi || fail` never fails on Linux. The
Windows behavior (1 on reported errors, 0 on clean) is the reference the
gate wording assumes.

## Suggested fix

Propagate the error exit status on the `--check` path of the Linux build
(same status discipline as `xiom run`, which already returns nonzero program
exit codes on Linux). A release-check pass on the next archive should show
`rc 1` for both probe files on Windows AND WSL.

## Workaround (until fixed)

Gate on output text (`compilation failed` / `error[`) or run the check from
the Windows shadow install when the exit status must be authoritative.
