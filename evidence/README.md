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
| `deterministic-build.json`, `foundry-results-v3.json`, `mutation-results.json`, `isabelle-results-v3.json`, `kontrol-results-v3.json` | Successor lane receipts, written from the committed tree by `scripts/check-deterministic-build.ps1`, `scripts/record-foundry-results-v3.mjs`, `scripts/run-mutations.ps1`, `scripts/record-isabelle-results-v3.mjs`, and `scripts/record-kontrol-results-v3.mjs`; a receipt is absent while its lane is pending in `current-profile-release-index-v3.json` |
| `end-to-end-refinement/` | The successor obligation ledger, its rendered summary and central closure record, and the regenerated runtime bridge schema and manifest (decision 10) |
| `runtime-binding-v3.json`, `runtime-binding-v3/` | The two-layer runtime binding of the three successor runtimes: artifact template identity and pinned-compiler replay with the exact compiler inputs (decision 11) |
| `independent-reproduction-v3.json` | The specification-only reproduction of the conformance vectors by an independent implementer, rerun and compared in continuous integration |
| `candidate-2/` | The candidate 2 receipts, proof inputs, and superseded formal artifacts, preserved byte for byte (see its own README) |
| `mutator-inventory.md`, `pilot-*`, `clean-room-provenance.md` | Mutation inventory, the byte-bound pilot, and the clean-room provenance record |
| `model-regression.json`, `isabelle-solidity-applicability.md` | Model-level regression and applicability notes |
| `public-release/` | Release identity records: supersession manifests, the proof-bound identifier allowlist, and terminal receipts |

To replay the binding checks locally, follow the quickstart in the top-level
README; `scripts/verify-release.mjs` and
`scripts/verify-current-profile-release-v3.mjs` read these files directly.
