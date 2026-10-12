<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# C-ORBIT-11 repro: same-named types across modules break consumers at codegen (unresolved method on the WRONG declaration)

**Compiler:** v0.64.4 (Windows shadow sha256 `44a41aea...`, WSL linux sha256
`d0a43a5c...` -- official artifacts).
**Found by:** the xiom.btree 0.1.1 two-way consumer pass (2026-10-12).
Importing BOTH `xiom.btree` (registry package) and ORBITDB's
`xiom.db.engine` in one program fails at codegen:

```
error[C001]: codegen: unresolved function symbol(s) called but never defined
or declared: 'xiom.btree.BTreeNode.pop' (returns i64, first call at IR line
15440, from @db.engine.split_child), 'xiom.btree.BTreeNode.push' (returns
i64, first call at IR line 16318, from @db.engine.insert_at_pos). These calls
previously received a silent zero/default auto-stub; fix the call resolution
(or provide the missing function) instead.
```

Both modules declare same-named types (`BTreeNode`, `NodeStore`, `BTree`).
Inside `@db.engine.split_child` the compiler resolves the engine's own
`child.payloads.pop()` / `node.payloads.push()` -- a field that exists only
on the ENGINE's `BTreeNode`, not on the package's -- against the FOREIGN
`xiom.btree.BTreeNode` declaration. m267 turned the former silent stub into a
hard C001 (correct to refuse), but the trigger is only the name collision:
there is no unresolved function in either module when compiled alone.

## Files

- `../../tests/pkg/probe_compose_collision.xi` -- the REAL repro (needs the
  registry dep + our src root via `tests/pkg/xiom.toml`):
  `scripts\run.ps1 tests\pkg\probe_compose_collision.xi -TimeoutSec 180`
  -> C001 above, rc 1. Expected when fixed: compiles, prints `compose ok`.
- `main.xi` + `mod_a.xi` + `mod_b.xi` -- attempted MINIMAL pair (two modules
  each declaring `Box2`, one with a Vec-of-itself element inference doing a
  field-method call). **Does NOT reproduce on v0.64.4** (compiles, prints
  `a.xs.len=1 b.ys.len=1 a.kid.xs.len=1`) -- kept as negative evidence: the
  trigger needs the package/multi-type-triad composition, not merely two
  same-named structs.

## Impact

- Consumer programs cannot compose a registry package and a source module
  whose public type names overlap (`BTreeNode`/`NodeStore`/`BTree` here).
  ORBITDB split its xiom.btree consumer pass into two programs with a shared
  digest label to work around it.
- Related open finding: `REL-20261010-1709-xvector` (two same-named struct
  types across modules shadow each other's layout -- still red on v0.64.3)
  and the C-ORBIT-04/m225 consumer-scope family.

## Workaround (applied)

Do not co-import modules with colliding type names in one program; verify
package behavior in a package-only program and interop via external digests
(ORBITDB's `probe_pkg_btree.xi` + `probe_pkg_btree_engine.xi` pattern).

## Suggested fix

Resolve field/method access against the module-LOCAL type definition (or the
importing alias), not a first-wins bare name; when a field is genuinely
missing, emit a clean "no field on <Type>" diagnostic instead of an
unresolved-symbol C001 naming a foreign type.
