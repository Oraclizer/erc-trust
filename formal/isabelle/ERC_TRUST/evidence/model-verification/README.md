# ERC-TRUST abstract-model evidence entry

This directory keeps the human-owned claim matrix and the scripts that
reproduce the abstract-model proof closure, reverse enumeration, and negative-mutation
checks.

Tracked source:

- `model-claim-matrix.md`
- `generate-manifest.ps1`
- `reverse-check-manifest.mjs`
- `run-negative-mutations.ps1`
- `run-trust-closure.ps1`

The scripts write generated material to `out/`. That path is intentionally
ignored: timestamped build logs, Isabelle exports, kernel tables, mutation
workspaces, and intermediate manifests are reproducible artifacts rather than
canonical source.

The pinned closure hashes and the sealed private raw-run archive hash are
recorded in the immutable repository-root `formal-dependencies.lock.json`.
The current public foundation successor is separately recorded in
`formal-dependencies-public-v1.lock.json`; it does not replace the historical
closure record. The release PDF and its manifest remain under `../../release/`.

The archived result records an abstract-model pass. It does not establish
Solidity refinement, bytecode or deployment correctness, legal or off-chain
truth, implementation correspondence, or production readiness.
