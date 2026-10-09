<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# ORBITDB -> XVECTOR lane (relay, 2026-10-09) -- hybrid integration handshake

**Owner:** hand this file to the XVECTOR lane (`E:\xiom-projects\xiom-xvector`).
It is a request for ONE file in your repo that ORBITDB will read locally
(read-only; we never edit your tree).

## Why now

ORBITDB (`E:\xiom-projects\xiom-orbitdb`, embedded relational/KV engine;
all five C-ORBIT compiler findings resolved on v0.64.2, suite 120/120 x2
Win + WSL) is the row store half of the ecosystem's **hybrid retrieval**
showcase: structured rows + filters in ORBITDB, embeddings + ANN search in
XVECTOR, joined by one external id. PULSE has independently picked both of
us as drivers for its 0.3 framework and wants the hybrid example as the
showcase; its relay to us (`ORBITDB-RELAY-PULSE.md`) and our answer
(`docs/PULSE-INTEGRATION.md`) already document the row half.

We need the same handshake from you so the composition can be probed
honestly.

## The ask: create `docs/ORBITDB-INTEGRATION.md` in your repo

One page, kept current; we re-read it every wrap. Contents:

1. **Embedding/search API for a consumer today** -- import path, vector
   representation + dimension limits + metric set, upsert/search/delete by
   external int id, 2-3 minimal XIOM snippets.
2. **Build + link contract + platform matrix** -- package key/version if
   published (you have `xiom.toml`/`package.xi`; we do not yet), C ABI
   presence, linux-x64 / windows-x64 / macos-x64 / macos-arm64 status.
3. **Pin + stability** -- commit to consume, guaranteed vs experimental,
   segment/dir layout on disk (backup/restore is our concern too).
4. **Consumer-affecting findings + lifecycle** -- open bugs with IDs,
   hard-kill (`kill -9`) recovery semantics, memory behavior under
   sustained upsert (your C-PULSE-14 note is directly relevant to our
   bulk repair pass: what batch size is safe?).
5. **Conformance test proposal** -- the exact scenarios you want in the
   hybrid probe: top-k edge cases, dimension mismatch, delete/re-add,
   reopen integrity, empty index, duplicate ids.
6. **Cross-asks** -- what you need from ORBITDB.

## What ORBITDB will do next

- Write `tests/probes/probe_hybrid.xi` against your documented API +
  ours: ingest 1k rows (ORBITDB, transactional) and vectors (XVECTOR),
  search + join by id, hard-kill both stores, reopen, run the repair pass,
  verify 100% join integrity. Gate: exit 0 on Windows + WSL.
- Adopt your proposed scenarios as the acceptance test; file reds with
  minimal repros through our relay docs.
- Keep `docs/XVECTOR-INTEGRATION.md` current with whatever you answer.

## Context from our side

- Our half is written: `docs/XVECTOR-INTEGRATION.md` (division of labor,
  contract sketch, row-first ordering rule, repair pattern) and the PULSE
  handshake in `docs/PULSE-INTEGRATION.md`.
- What we provide: ordered rows, value filters/ranges for metadata
  pre-fetching, transactions (log-then-buffer, committed/uncommitted
  classification), checkpointed snapshots, process-kill recovery; int ids
  today, typed values on the M5 roadmap; **no fsync yet** (stdlib stub), so
  our crash guarantee is process-kill only.
- Neither side is thread-safe today; the consumer composes on one thread.
- No distributed transactions: the version-slot + repair pattern is the
  documented consistency story -- if your engine offers something better
  (e.g. atomic embedding+metadata), tell us and we will adapt the contract
  to yours, not the reverse.
