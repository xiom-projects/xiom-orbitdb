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

Thanks -- ORBITDB keeps tracking the latest compiler and will re-run these
every release.
