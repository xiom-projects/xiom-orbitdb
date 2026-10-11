<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# C-ORBIT-09 repro: element assignment through a copied Vec handle writes through to the source

**Compiler:** v0.64.3 (Windows shadow `%LOCALAPPDATA%\xiom.new.0643\bin\xiom.exe`;
WSL `~/.local/bin/xiom`).
**Found by:** the ORBITDB M3 snapshot-pin slice (`docs/MVCC.md`), 2026-10-11.
The copy-on-write shadow copy of a B-tree node was built with plain struct/Vec
assignment; the "copy" kept sharing `keys`/`values`/`children` buffers with the
pinned original, and the in-place `keys[i] = keys[i+1]` shifts of an update
mutated the pinned view. The suite caught it deterministically (snapshot reads
returned post-write values); the fix deep-copies every vector in
`node_deep_copy` (src/engine.xi).

## Files

- `probe_alias.xi` -- the failing shape: a flat Vec and a Vec-of-Vec "arena"
  (the engine shape) where element assignment through an extracted handle
  mutates the source element.
- `probe_clean.xi` -- control: a manually rebuilt copy owns its storage, so
  element assignment on it leaves the source untouched (the ORBITDB
  workaround).

## Commands and observed results (v0.64.3, Windows + WSL identical output)

```
scripts\run.ps1 docs\repro\vec-copy-alias\probe_alias.xi
  flat elem-assign: src[0]=99 copy[0]=99      # copy[0]=99 ALSO changed src[0]
  flat push: src.len=2 copy.len=3             # push DID copy-on-write
  arena elem-assign: src[0]=99 copy[0]=99     # write-through via a live arena handle
  arena pop: src.len=2 store-copy.len=2 local.len=1   # pop DID copy-on-write
  exit code: 0                                 # no error, no warning

scripts\run.ps1 docs\repro\vec-copy-alias\probe_clean.xi
  owned elem-assign: src[0]=1 copy[0]=99       # correct
  exit code: 0
```

## Mechanism

Vec handles are reference-like: assigning a Vec (or a struct containing Vecs)
shares the underlying buffer instead of deep-copying it. `push`/`pop` detect
the sharing and copy-on-write correctly, but **element assignment
(`v[i] = x`, including through a handle extracted from a containing Vec or
struct) writes into the shared buffer without the copy check**. The source
and the copy silently observe each other's element writes from then on.

Two live handles is all it takes -- no use-after-move is involved in the flat
or arena shapes above (both compile without diagnostics).

## Impact

Any code that (a) copies a container by assignment expecting value semantics
and (b) mutates elements in place will silently alias. For ORBITDB this
directly broke snapshot isolation (MVCC pins): the pinned node versions were
mutated through the shadow's element writes. The same trap applies to any
"clone-then-modify" pattern in the ecosystem (PULSE caches, XVECTOR buffers).

## Workaround (applied)

Build "copies" that own their storage explicitly: fresh vectors + push loops
(each nested vector rebuilt too). ORBITDB's `node_deep_copy` is the reference
helper; the snapshot/pin suites are green on v0.64.3 with it (platform
evidence recorded in SESSION.md at the wrap).

## Suggested fix

Route element assignment through the same copy-on-write check as push/pop
(copy the buffer when it is shared), or make Vec assignment deep-copy by
default. A compile-time diagnostic for the shared-handle case would also
prevent the silent-aliasing class.
