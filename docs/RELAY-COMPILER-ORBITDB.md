# Relay: ORBITDB -> compiler lane (paste-ready)

**From:** ORBITDB lane (`E:\xiom-projects\xiom-orbitdb`, embedded database
engine). **Pin:** compiler v0.64.0, stdlib `a677338` (2026-10-08).

Hi compiler lane -- ORBITDB is a new consumer lane (formerly xiom-db). Full
details and repro bundles are in the lane repo:

- `docs/COMPILER-FINDINGS-ORBITDB.md` (findings + variant matrices)
- `docs/repro/ok-method-receiver/`, `docs/repro/option-vec-assign/`,
  `docs/repro/nested-field-mut/` (plus ruled-out controls)

Three open findings from building a real storage engine on v0.64.0:

1. **C-ORBIT-01 -- cross-module generic `Result` alias payload unresolved.**
   `pub type DbResult[T] = Result[T, DbError]` as a return type: the
   match-bound `Ok(payload)` loses its type at the consumer. Method calls
   drop the receiver (`'get_column' expects 2 argument(s), found 1`),
   zero-arg methods reach codegen as an unresolved symbol (C001), and
   codegen warns `unknown type 'DbResult' -- defaulting to i64`. App
   evidence: `io.read_file_lines` payload printed raw stack addresses until
   rebound; our 93-test suite had 4 T001 + a C001 from one `tuple_decode`
   call site. Workaround in production: `let d: Row = decoded;` before any
   access. NOTE: your lane commit `0c5337e0` (m216 alias resolution) may
   already cover this -- the repro bundles are ready for a re-test.
2. **C-ORBIT-02 -- `Vec[Option[T]]` element assignment poisons the slot.**
   After `v.push(None); v[0] = Some(x);` the element matches NEITHER `None`
   nor `Some(_)`; every match silently runs no arm, no diagnostic. Also for
   Some->Some, `Option[Str]`, None->None. `Vec[Int]`, enum vecs, and struct
   fields are fine. This broke our BufferPool in production.
3. **C-ORBIT-03 -- nested-field `&mut` method receivers mutate a copy.**
   `o.inner.bump()` and `eng.buffer_pool.put(page)` lose the write-back; the
   explicit `Inner.bump(&mut o.inner, ...)` and copy-mutate-writeback forms
   are correct. This broke `StorageEngine.cache_page`.

Impact framing: all three are silent-wrong-value defects on the path of any
collection/storage code; the database suite and crash probes are green only
because of in-repo workarounds. Also minor: a W004 false "unreachable match
arm" on a valid two-arm enum match (`docs/repro/option-vec-assign/probe2.xi`).

**Re-test recipe (next archive):** `scripts/run.ps1
docs/repro/ok-method-receiver/probe_import.xi` (expect no T001; variants
A/B/C broken -> green), `probe_only_i.xi`, `probe2.xi` in
option-vec-assign, `nested-field-mut/probe.xi` (A/C must be 1). Findings
flip to RESOLVED only when the bundles are green unchanged.

**New finding since the first message -- C-ORBIT-04 (enum variant collision,
hard compile failure):** with `xiom.db.txn.transaction`'s
`pub enum WALOp { Insert, Update, Delete }` and `xiom.db.wal_file`'s
`pub enum WALOpKind { Insert, Update, Delete, ... }` in one compilation
unit, unqualified `return Update;` inside `wal_op_from_code` lowered as the
txn module's `%struct.WALOp` while the function is declared `-> WALOpKind`:

```
error: clang failed with exit code 1
xiominput.ll:71073:25: error: '%tmp10' defined with type
    '%struct.WALOp = type { i64 }' but expected '%struct.WALOpKind = type { i64 }'
71073 |   ret %struct.WALOpKind %tmp10
```

The same module (wal_file) compiled and ran green for hours when the txn
module was NOT in the graph -- the collision only appears when both enums
are present. Variant *patterns* against the wrong structural twin would
compare equal i64 tags and silently take the wrong branch, so this is
high-priority even though clang caught the constructor case here.
Workaround verified in our build: module-qualify variants in constructors
AND patterns (`return WALOpKind.Update;`,
`match op { WALOpKind.Insert => ... }`) -- suite back to 104/104.
Full details + IR snippet in `docs/COMPILER-FINDINGS-ORBITDB.md`
(section C-ORBIT-04). Suggested fix: scope unqualified variant resolution to
the current module first (or intern variants by module+name+tag) and error
on real ambiguity.

Thanks -- ORBITDB keeps tracking the latest compiler and will re-run these
every release.
