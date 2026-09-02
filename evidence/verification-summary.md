# ERC-TRUST reference-candidate verification summary

> Status note: this document describes the shipped candidate `0.1.0-candidate.2`.
> On the successor branch the receipts it cites live under `evidence/candidate-2/`,
> and the lane-by-lane status of the successor code is
> `evidence/current-profile-release-index-v3.json` under
> `evidence/evidence-mode.json`. This document is rewritten in the documentation
> change that closes the successor; until then its numbers are candidate 2 history,
> not measurements of the successor code.

Candidate: `0.1.0-candidate.2`

Binding: the Git commit containing `evidence/release-manifest.json` and that
manifest's `sourceTree.root`

Research companion: [arXiv:2608.29134](https://arxiv.org/abs/2608.29134).
The paper explains the semantics and evidence boundary; this summary and the
release manifest own the exact candidate measurements.

The source-tree hash canonicalizes every listed UTF-8 text file to LF before
hashing, so Windows and Unix checkouts bind to the same committed content.
Disposition: **bounded checks PASS; unaudited and not for production**

> No deployment, proxy, migration, end-to-end refinement, or external
> legal/factual truth is verified.

## Risk-removal disposition

The reference-candidate refinement closed the following implementation-level failure modes:

- `FREEZE` accepts only a strictly increasing absolute target; decreases use a
  separately authorized `UNFREEZE`;
- direct reversals re-evaluate the current policy binding and fail closed;
- `CONFISCATE` terminates its case and the same case cannot be reused;
- custody disposition must match custodian, declared prior holder, and amount,
  and closes the custody record atomically;
- raw ERC-7943 and ERC-3643 mutation paths remain closed;
- action, authority, epoch, scope, provenance, nonce, and action-specific
  shapes are bound and malformed commands stutter by reverting;
- the unnecessary no-op governance route was removed.

These controls are supported by positive tests and by a 12-fault negative
mutation campaign; this is detector evidence, not a completeness proof or
security audit.

## Exact checks

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
| SDK | 3/3 tests PASS; dry-run tarball contains only runtime declarations/code, README, license, and package metadata; high-severity audit reports no known vulnerabilities |

The deterministic `TrustToken` hashes are:

- artifact SHA-256:
  `a75570fa036ec10fa0896cdce03ff6cbdf7ad9c8d773a75f83e5468ae87bf78b`;
- creation-bytecode SHA-256:
  `fecca8fca7a3698d6cdab41a501789ecbf8bae21f6b28c562db565c78dbcfb28`;
- runtime-bytecode SHA-256:
  `aabc0bd11e517ba9b9b8dbd288bcee80ba29c58be7598708269d2ff79e7fcf9f`.

Machine-readable details are in
`evidence/candidate-2/certora-financial-core-v2.json`,
`evidence/candidate-2/kontrol-results-v2.json`,
`evidence/candidate-2/deterministic-build.json`,
`evidence/candidate-2/mutation-results.json`, `evidence/model-regression.json`, and
`evidence/pilot-regression.json`.

## Residual risks and non-claims

- The 399-byte EIP-170 margin remains narrow. Compiler settings are part
  of the candidate binding, and no additional native feature should be merged
  without repeating the size and all proof gates.
- This package has not received an independent security audit and is not a
  production recommendation.
- Certora and Kontrol results are bounded to their published rules and exact
  harnesses; there is no machine-checked Isabelle-to-EVM refinement theorem.
- The official Isabelle/Solidity framework was evaluated and built, but it was
  not used as reference-candidate proof. No claim that the Solidity source was verified in
  Isabelle/Solidity is permitted. See
  `evidence/isabelle-solidity-applicability.md`.
- The ERC-3643 result is fixture-bound. A real deployment requires a new exact
  runtime code-hash, ownership, Agent, Identity Registry, Compliance, and
  complete mutator inventory review.
- Dependency responses and recorded commitments do not establish legal,
  policy, identity, settlement, proceeds, entitlement, or ownership truth.
- Proxy, migration, deployed-address, chain, gas-economics, MEV, key
  management, and operational governance claims are outside this candidate.

## Reproduction

Run the pinned Foundry, Certora, Kontrol, Isabelle, SDK, deterministic-build,
mutation, link, public-surface, and release-verification commands documented in
`FORMAL_VERIFICATION.md`, `README.md`, and `scripts/`. The release verifier
recomputes the manifest source root and exact `TrustToken` bytecode hashes.
