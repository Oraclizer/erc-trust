# Evidence

This directory holds the machine-checkable evidence that backs the claims in
the top-level README and `FORMAL_VERIFICATION.md`. Every file here is either
an input a verifier consumes or a summary that points at one.

Start with:

- [`claim-matrix.md`](claim-matrix.md): which claim is backed by which
  artifact, tool, and command.
- [`verification-summary.md`](verification-summary.md): the current results
  across the Foundry, Certora, Kontrol, KEVM, and Isabelle lanes.
- [`trust-ref-matrix.md`](trust-ref-matrix.md): how the reference maps onto
  the specification surface.

Contents:

| Path | What it is |
| --- | --- |
| `release-manifest.json` | Hash binding over the protected release inputs; regenerated and diff-checked in CI |
| `current-profile-release-index-v1.json` | Index of the current verification profile consumed by `scripts/verify-current-profile-release.mjs` |
| `certora-results.json`, `kontrol-results.json` | Recorded results from the Certora and Kontrol lanes |
| `mutation-results.json`, `mutator-inventory.md`, `pilot-*` | Mutation campaigns and their classified outcomes |
| `deterministic-build.json`, `clean-room-provenance.md` | Deterministic build inputs and the clean-room provenance record |
| `model-regression.json`, `isabelle-solidity-applicability.md` | Model-level regression and applicability notes |
| `end-to-end-refinement/` | Qualification receipts and row bundles for the current refinement profile (see its own README) |
| `public-release/` | Release identity records: supersession manifests, the proof-bound identifier allowlist, and terminal receipts |

To replay the binding checks locally, follow the quickstart in the top-level
README; `scripts/verify-release.mjs` and
`scripts/verify-current-profile-release.mjs` read these files directly.
