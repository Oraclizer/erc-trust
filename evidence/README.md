# Evidence

This directory holds the machine-checkable evidence that backs the claims in
the top-level README and `FORMAL_VERIFICATION.md`. Every file here is either
an input a verifier consumes or a summary that points at one.

Start with:

- [`claim-matrix.md`](claim-matrix.md): which claim is backed by which
  artifact, tool, and command.
- [`verification-summary.md`](verification-summary.md): the candidate 2 results
  across the Foundry, Certora, Kontrol, KEVM, and Isabelle lanes; the successor is
  tracked lane by lane in `current-profile-release-index-v3.json`.
- [`trust-ref-matrix.md`](trust-ref-matrix.md): how the reference maps onto
  the specification surface.

Contents:

| Path | What it is |
| --- | --- |
| `release-manifest.json` | Hash binding over the protected release inputs; regenerated and diff-checked in CI |
| `evidence-mode.json` | Whether pending evidence lanes are acceptable (successor development) or not (release) |
| `current-profile-release-index-v3.json` | Lane-by-lane evidence index of the successor code, written and checked by `scripts/verify-current-profile-release-v3.mjs` |
| `deterministic-build.json`, `mutation-results.json` | Successor deterministic build and consumer-removal mutation receipts |
| `candidate-2/` | The candidate 2 receipts and proof inputs, preserved byte for byte (see its own README) |
| `mutator-inventory.md`, `pilot-*`, `clean-room-provenance.md` | Mutation inventory, the byte-bound pilot, and the clean-room provenance record |
| `model-regression.json`, `isabelle-solidity-applicability.md` | Model-level regression and applicability notes |
| `public-release/` | Release identity records: supersession manifests, the proof-bound identifier allowlist, and terminal receipts |

To replay the binding checks locally, follow the quickstart in the top-level
README; `scripts/verify-release.mjs` and
`scripts/verify-current-profile-release-v3.mjs` read these files directly.
