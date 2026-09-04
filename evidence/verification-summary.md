# ERC-TRUST verification summary

This summary states the exact checks behind the successor on private `main`
(kernel version 2, working label `0.2.0-candidate.1`) and keeps the
shipped candidate `0.1.0-candidate.2` as history. Every number below is a
measurement of the named bytes and nothing else.

Binding: the Git commit containing `evidence/release-manifest.json`, that
manifest's `sourceTree.root`, and the three runtime template hashes it records.
The source-tree hash canonicalizes every listed UTF-8 text file to LF before
hashing, so Windows and Unix checkouts bind to the same committed content.

Research companion: [arXiv:2608.29134](https://arxiv.org/abs/2608.29134). The
paper describes kernel version 1 (candidate 2); a revision for kernel version 2
is pending.

Disposition: **bounded checks PASS; two Certora lanes pending by decision;
unaudited and not for production**

> No deployment, proxy, migration, end-to-end refinement, or external
> legal/factual truth is verified. The permitted claim is "mapped
> implementation evidence; end-to-end refinement incomplete".

## Successor (kernel version 2)

The lane index `evidence/current-profile-release-index-v3.json`, written and
checked by `scripts/verify-current-profile-release-v3.mjs` under
`evidence/evidence-mode.json`, is the machine-readable form of this table.

| Lane | Exact result | Receipt |
| --- | --- | --- |
| Foundry | 89/89 tests PASS across seven suites; two fuzz properties at 256 runs; nine invariants at 256 runs and depth 500 (1,152,000 calls, zero reverts); `forge fmt --check`, `forge lint` (0 errors, eight intentional validity-window `block.timestamp` warnings), and `forge build --sizes` PASS | `foundry-results-v3.json` |
| Size | native runtime 20,043 bytes (EIP-170 margin 4,533); ERC-3643 adapter 19,218 (margin 5,358); profile governor 2,790 (margin 21,786) | `release-manifest.json`; `deterministic-build.json` |
| Determinism | two isolated clean builds of the three runtimes produced identical artifact, creation, and runtime hashes (schema v3) | `deterministic-build.json` |
| Runtime binding | three runtimes agree with the pinned-compiler (solc 0.8.36) replay in ABI, semantic storage layout, creation bytecode, runtime bytecode, method identifiers, and immutable references; stored compiler inputs kept; verifier self-mutation 18/18 killed; stale receipts rejected | `runtime-binding-v3.json`; `runtime-binding-v3/` |
| Mutation | 111/111 declared faults killed, 0 survived; each fault names its detector and, where it removes a load-bearing consumer, its obligation ledger row | `mutation-results.json` |
| Kontrol/KEVM | 4/4 proofs PASS on the successor native runtime (Kontrol 1.0.255, KEVM 1.0.678, CANCUN); no adapter symbolic lane | `kontrol-results-v3.json` |
| Isabelle/HOL | session `ERC_TRUST`, 22 theories, clean build in continuous integration with `record_proofs`; proof audit 409 explicit roots, 410 qualified facts, 0 oracle dependencies, 0 banned source forms | `isabelle-results-v3.json` |
| Obligation ledger | 72 rows: 68 CLOSED, 2 SUCCESSOR-MANDATORY (the runtime link), 2 NOT-APPLICABLE, 0 CURRENT-MANDATORY; closure CONDITIONAL; every anchor verified against the tree and the ledger rendered into the Isabelle session | `end-to-end-refinement/obligation-ledger-summary-v3.json`; `central-closure-v3.json` |
| Runtime bridge | regenerated from the compiled artifacts of the three runtimes; determinism checked in continuous integration | `end-to-end-refinement/runtime-bridge-v2/` |
| Independent reproduction | 23 vectors, 400 assertions reproduced by a program written from the machine source, the generated prose and ABI, and the vectors alone; rerun and compared in continuous integration | `independent-reproduction-v3.json` |
| Certora | PENDING by decision: no successor source has been sent to the cloud prover; the candidate 2 Certora results describe different bytes | `evidence-mode.json` |
| SDK | 13 source tests PASS plus a pack-install consumer smoke from the package root | continuous integration |

## Residual risks and non-claims

- No theorem states that the compiled runtime implements the abstract model;
  the runtime link is an undischarged locale assumption and the closure is
  conditional.
- The Kontrol proofs and Foundry executions are bounded instances of that
  link, not a proof of it; the adapter has no symbolic lane.
- The Certora lanes are pending; switching the evidence mode to release
  requires every lane to pass.
- This package has not received an independent security audit and is not a
  production recommendation.
- The ERC-3643 result is fixture-bound. A real deployment requires a new exact
  code identity, ownership, Agent, Identity Registry, Compliance, initial
  state, and complete mutator inventory review; the adapted frozen target has
  the inbound-growth window stated in `docs/PROFILES.md`.
- Dependency responses and recorded commitments do not establish legal,
  policy, identity, settlement, proceeds, entitlement, or ownership truth.
- Proxy, migration, deployed-address, chain, gas-economics, MEV, key
  management, and operational governance claims are outside this candidate.

The complete list, with the artifact that owns each entry, is
`known-limitations.md`.

## Shipped candidate `0.1.0-candidate.2` (history)

The receipts live under `candidate-2/`. These numbers measure candidate 2 and
are not measurements of the successor code.

| Layer | Exact result |
| --- | --- |
| Foundry | 31/31 tests PASS; two fuzz properties × 256 runs; three invariants × 256 runs × 500 calls = 384,000 calls |
| Size | `TrustToken` runtime 24,177 bytes; EIP-170 margin 399 bytes; initcode 27,683 bytes |
| Lint | 0 errors; six intentional validity-window `block.timestamp` warnings |
| Determinism | two isolated clean builds produced identical artifact, creation bytecode, and runtime bytecode |
| Mutation | 12/12 declared reference-candidate faults killed; 0 survived |
| Certora targeted | [run `2f7c362ce29d465e9fb8e3facb1320ad`](https://prover.certora.com/output/10491299/2f7c362ce29d465e9fb8e3facb1320ad): 2/2 production FREEZE-direction rules SUCCESS with advanced sanity |
| Certora exploratory | Full financial-core runs on 8.17.1 and 8.19.1 both UNKNOWN from provider internal error `4201170908`; no credit claimed |
| Kontrol/KEVM | 4/4 selected high-risk bytecode proofs PASS |
| Current profile | successor packages 7/7; Core 49/49; Supporting 24/24; optional backlog 0/6; no partial credit |
| Model regression | Isabelle closure/audit PASS; 18 TRUST rows and 35 foundation-model rows; independent reverse check PASS; 15/15 model mutations killed |
| Isabelle/Solidity applicability | Official AFP source inspected and clean session build PASS; **NOT APPLICABLE** to the security-critical reference-implementation kernel |
| Preserved pilot regression | current source/bytecode binding PASS and Foundry 13/13; Certora 13/13 and Kontrol 2/2 are historical provenance after public-label-only hash changes; 5/5 pilot mutations killed |
| SDK | 3/3 tests PASS; dry-run tarball contains only runtime declarations/code, README, license, and package metadata |

The deterministic candidate 2 `TrustToken` hashes are:

- artifact SHA-256:
  `a75570fa036ec10fa0896cdce03ff6cbdf7ad9c8d773a75f83e5468ae87bf78b`;
- creation-bytecode SHA-256:
  `fecca8fca7a3698d6cdab41a501789ecbf8bae21f6b28c562db565c78dbcfb28`;
- runtime-bytecode SHA-256:
  `aabc0bd11e517ba9b9b8dbd288bcee80ba29c58be7598708269d2ff79e7fcf9f`.

Machine-readable details are in `candidate-2/certora-financial-core-v2.json`,
`candidate-2/kontrol-results-v2.json`, `candidate-2/deterministic-build.json`,
`candidate-2/mutation-results.json`, `model-regression.json`, and
`pilot-regression.json`.

## Reproduction

Run the pinned Foundry, Kontrol, Isabelle, SDK, deterministic-build, mutation,
link, public-surface, and release-verification commands documented in
`FORMAL_VERIFICATION.md`, `README.md`, and `scripts/`. The release verifier
recomputes the manifest source root and the three runtime template hashes;
the lane verifier checks that every receipt binds the current identity.
