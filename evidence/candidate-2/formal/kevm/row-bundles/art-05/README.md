# ART-05 theory and import-closure binding

ART-05 checks `theory_source_and_import_closure_are_hash_bound` across the
repository-owned Isabelle source closure and one exact full-transaction runtime
observation.

The positive K claim calls `governor()` on the constructor-resolved TrustToken
runtime and requires the canonical address word ending in `0x66`. The semantic
mutant changes exactly byte 8553 in the imported runtime leaf to `0x67`. The
unchanged claim reaches a terminal counterexample, while the separate control
claim accepts the `0x67` word. This distinguishes the one-byte semantic change
without describing the negative graph as closed: it has one terminal node and
262 fail-fast pending branches.

The named Isabelle theorem binds 14 local theory sources, 13 local import edges,
one external import boundary, the closure root, the composition root, source
identities, and the exact runtime leaf. Its clean build and export reported zero
oracle dependencies.

## Portable product surface

The generator and reverse check enforce an exact allowlist for the formal row.
Pre-execution scaffolding, local proof output, and historical recovery metadata
are outside that allowlist. The replay-bound claim, completed bundle, bridge,
row manifest, theory, and graphs remain byte-for-byte fixed;
`generate-row-artifacts.mjs` rejects any hash drift.

The immutable bridge and row manifest are retained as proof-input snapshots.
Any preparation-era references inside those fixed snapshots are historical
metadata, not live product dependencies. The portable certificate points to the
canonical evidence interface instead:

- `evidence/end-to-end-refinement/row-bundles/art-05/replay.json`
- `evidence/end-to-end-refinement/row-bundles/art-05/artifacts/`

## Static verification

From the repository root:

```powershell
node formal/kevm/row-bundles/art-05/generate-row-artifacts.mjs
python3 formal/kevm/row-bundles/art-05/reverse-check.py
```

The generator verifies the immutable hashes, supporting proof inputs, exact
product allowlist, portable surface, certificate, and canonical evidence
targets. The independent reverse check reconstructs the theory/import closure,
composition root, source binding, exact runtime mutation, claim/control pair,
theorem tokens, and cross-file identities. Neither command starts KEVM,
Isabelle, or the Solidity compiler.

## Canonical integration

The row is a `DISCHARGED_CANDIDATE` after the static checks pass. It becomes an
official discharge only after the completed proof output is curated into the
canonical evidence paths, the independent evidence verifier passes, and the
repository binder updates the shared index and ledger.

This row does not claim correctness of solc or KEVM. It also does not expand the
theorem beyond the exact source, import, runtime, and replay identities recorded
in the fixed artifacts.
