# ERC-TRUST reference-candidate verification summary

Candidate: `0.1.0-candidate.1`

Binding: the Git commit containing `evidence/release-manifest.json` and that
manifest's `sourceTree.root`

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

These controls are supported by positive tests and by an 11-fault negative
mutation campaign; this is detector evidence, not a completeness proof or
security audit.

## Exact checks

| Layer | Exact result |
| --- | --- |
| Foundry | 31/31 tests PASS; two fuzz properties × 256 runs; three invariants × 256 runs × 500 calls = 384,000 calls |
| Size | `TrustToken` runtime 24,377 bytes; EIP-170 margin 199 bytes; initcode 27,883 bytes |
| Lint | 0 errors; six intentional validity-window `block.timestamp` warnings |
| Determinism | two isolated clean builds produced identical artifact, creation bytecode, and runtime bytecode |
| Mutation | 11/11 declared reference-candidate faults killed; 0 survived |
| Certora core | [run `3c1a8855237a4fdea3d068b0128dcc53`](https://prover.certora.com/output/10491299/3c1a8855237a4fdea3d068b0128dcc53): 7/7 top-level rules SUCCESS |
| Certora inventory | [run `8c8fa40539fb42d1bdf86c95f64a8c26`](https://prover.certora.com/output/10491299/8c8fa40539fb42d1bdf86c95f64a8c26): 12/12 external mutator instances classified |
| Kontrol/KEVM | 3/3 selected high-risk bytecode proofs PASS |
| Model regression | Isabelle closure/audit PASS; 18 TRUST rows and 35 foundation-model rows; independent reverse check PASS; 15/15 model mutations killed |
| Isabelle/Solidity applicability | Official AFP source inspected and clean session build PASS; **NOT APPLICABLE** to the security-critical reference-implementation kernel |
| Preserved pilot regression | current source/bytecode binding PASS and Foundry 13/13; Certora 13/13 and Kontrol 2/2 are historical provenance after public-label-only hash changes; 5/5 pilot mutations killed |
| SDK | 3/3 tests PASS; dry-run tarball contains only runtime declarations/code, README, license, and package metadata; high-severity audit reports no known vulnerabilities |

The deterministic `TrustToken` hashes are:

- artifact SHA-256:
  `4c0760656fb6fa712186abab3b06480bd1aff597570a64cb77733deb9ca5b46c`;
- creation-bytecode SHA-256:
  `bfa82a9144c7ad1dfe60603d335bbba0cb22716c3d667d28026e9a9b26d1bac7`;
- runtime-bytecode SHA-256:
  `857a179f5088bbb5d4ac0c016e6ec3eda8bc1759e96b0e861f75fe1c70dbb127`.

Machine-readable details are in `evidence/certora-results.json`,
`evidence/kontrol-results.json`, `evidence/deterministic-build.json`,
`evidence/mutation-results.json`, `evidence/model-regression.json`, and
`evidence/pilot-regression.json`.

## Residual risks and non-claims

- The 199-byte EIP-170 margin is critically narrow. Compiler settings are part
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
