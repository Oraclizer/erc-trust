# Candidate 2 evidence (historical)

This directory preserves, byte for byte, the evidence files and proof inputs of
the shipped `0.1.0-candidate.2` reference candidate (tag `v0.1.0-candidate.2`).
Every receipt here binds the runtime, source, and formal identities of that
candidate only. None of it is evidence for the successor code under
`implementation/`, whose lane-by-lane status is
`evidence/current-profile-release-index-v3.json`.

## Layout

| Path | What it was in the candidate 2 tree |
| --- | --- |
| `current-profile-release-index-v1.json`, `current-profile-release-index-v2.json` | `evidence/current-profile-release-index-v1.json` and `-v2.json`: the candidate 1 and candidate 2 release indexes |
| `deterministic-build.json`, `foundry-results-v2.json`, `mutation-results.json` | the candidate 2 build, Foundry, and mutation receipts |
| `kontrol-results-v2.json`, `certora-financial-core-v2.json` | the candidate 2 Kontrol and targeted Certora receipts |
| `kontrol-results.json`, `certora-results.json`, `isabelle-results-v2.json` | the candidate 1 proof results carried by candidate 2 and the candidate 2 Isabelle build receipt |
| `end-to-end-refinement/` | `evidence/end-to-end-refinement/`: qualification receipts, row bundles, runtime binding, and bridge inputs |
| `implementation/certora/` | `implementation/certora/`: the version 1 Certora specifications, configurations, and harness |
| `implementation/kontrol/TrustTokenKontrolTest.t.sol` | the version 1 Kontrol test; `implementation/kontrol/erc-trust-log-assertions.k` is unchanged at its original path |
| `implementation/src/*Mutant.sol` | the five version 1 mutant contracts consumed by the Certora mutation lanes |
| `implementation/test/mocks/*Harness*.sol`, `implementation/test/PolicyBindingClassifier.unit.t.sol` | the version 1 verification harnesses and the classifier unit test |
| `defect-reproductions/` | Foundry reproductions of the candidate 2 defects that motivated kernel version 2 |
| `formal/isabelle/ERC_TRUST/` | the candidate 2 generated bridge theories, the C0 runtime occurrence and composition theories, the redundant-hypothesis theories, and the current-profile per-row theories (`TRUST_ACT_01`, `TRUST_M4_STATE_04`, `TRUST_M4_STATE_05`, the balance/reversal and contract boundary certificates); they were bound to the candidate 2 runtime template and are no longer in the `ERC_TRUST` session |
| `formal/kevm/` | the candidate 2 KEVM claim specifications, row bundles, reusable claims, runner scripts, runtime verification module, and generated bridges; the successor inputs are under `formal/kevm/` at the repository root |

Paths recorded inside these files are relative to the candidate 2 tree; add the
`evidence/candidate-2/` prefix to locate a file here. The historical verifiers
`scripts/verify-current-profile-release.mjs`,
`scripts/verify-current-profile-release-v2.mjs`,
`scripts/verify-runtime-binding.mjs`, and
`scripts/generate-pure-runtime-fixture.mjs` are kept unchanged for replay
against the candidate 2 tag; they are not run against the successor tree.

Unaudited. Not for production. Nothing in this directory is a claim about the
successor implementation.
