# Known limitations

This file lists what the successor code, its evidence, and its documents do
not establish, so that no reader has to infer the boundary from the absence
of a claim. Each entry names the artifact that owns it. The list is part of
the public claim surface: a claim that contradicts an entry here is
forbidden by `claim-matrix.md`.

> **Unaudited. Not for production.** No deployment, proxy, migration, or
> external legal or factual truth is verified.

## Formal evidence

| Limitation | Owner |
| --- | --- |
| No theorem states that the compiled runtime implements the abstract model. The locale assumption `runtime_link` in `formal/isabelle/ERC_TRUST/TRUST_End_To_End_Composition.thy` is not discharged; the two obligation ledger rows that name it stay open, and the closure record is conditional. The permitted wording is "mapped implementation evidence; end-to-end refinement incomplete". | `spec/decisions/10-refinement-closure.md`; `evidence/end-to-end-refinement/central-closure-v3.json` |
| The four Kontrol proofs rerun on the successor native runtime and the Foundry executions are bounded instances of that link, not a proof of it. The ERC-3643 adapter has no symbolic lane. | `evidence/kontrol-results-v3.json`; `FORMAL_VERIFICATION.md` |
| The Certora lanes of the successor are pending by decision: no successor source has been sent to the cloud prover, and the candidate 2 Certora results are historical evidence about different bytes. The evidence mode stays `successor-development` until those lanes are recorded. | `evidence/evidence-mode.json`; `evidence/current-profile-release-index-v3.json` |
| The obligation ledger enumerates the load-bearing abstract conditions by review. A condition the review did not name has no row, and the verifier cannot detect its absence. | `evidence/end-to-end-refinement/obligation-ledger-v3.json` |
| The mutation campaign establishes that each listed fault is detected by the named detector. It is detector evidence for the declared faults, not a completeness result. | `evidence/mutation-results.json`; `scripts/run-mutations.ps1` |
| The abstract model is verified within its declared semantic domain. Compiler correctness, EVM semantics, and the K-to-Isabelle correspondence of the composite decoder-guard result are trust seams, not proved objects. | `FORMAL_VERIFICATION.md` |
| The published research paper describes kernel version 1 (candidate 2). A revision for kernel version 2 is pending; until it appears, the repository, not the paper, describes the successor. | `README.md` |

## Runtime identity

| Limitation | Owner |
| --- | --- |
| The deterministic build and the two-layer runtime binding show that the exact sources reproduce the exact bytes under the pinned compiler and that the compiled bytes agree with a pinned-compiler replay in six semantic projections. They do not verify the compiler, a deployment, an address, a chain, or constructor inputs. | `spec/decisions/11-runtime-assurance.md`; `evidence/runtime-binding-v3.json` |
| Receipts that bind code identity are rejected when stale; the Isabelle receipt binds the formal root, the independent reproduction binds the vectors, and the model regression record binds neither. | `evidence/claim-matrix.md` |
| The independent specification-only reproduction covers the conformance vectors. It is not a second implementation of the endpoints and says nothing about their state transitions. | `evidence/independent-reproduction-v3.json` |

## Kernel and native profile

| Limitation | Owner |
| --- | --- |
| A receipt proves the onchain transition and the committed inputs. It does not prove that the authority had legal power or that any policy, identity, settlement, proceeds, entitlement, ownership, or legal assertion is true. | `spec/erc-trust-kernel-v2.json` (nonclaims) |
| The kernel has no delegation surface. A registered authority that is a contract carries its own access control, which the kernel does not inspect; a compromised authority can issue any command its epoch permits until it is rotated. | `spec/decisions/01-delegation-and-cancellation.md` |
| `block.timestamp` validity windows are subject to ordinary validator timestamp tolerance. | `docs/ERC-DRAFT.md` (Security Considerations) |
| `getFrozenTokens` reports the stored target saturated at the balance; the ordinary capacity of an account that carries custody backing is only available through `canTransfer`. | `spec/decisions/08-native-wiring.md` |
| Proxy and migration profiles are unsupported; both reference endpoints report `proxySupported = false`. | `docs/PROFILES.md` |

## ERC-3643 Verified Full profile

| Limitation | Owner |
| --- | --- |
| The token holds a frozen amount while the kernel holds a frozen target. Tokens received by an ordinary inbound transfer between two adapter touches stay transferable until the next touch or a call to `resynchroniseFrozen(account)`; closing that window atomically would need a transfer hook inside the token or its Compliance, which the profile does not use. | `spec/decisions/09-erc3643-profile-wiring.md` |
| The seal binds a declared token code identity to the live code. It does not audit the token; any claim about the token's behaviour comes from deployment evidence, not from the seal. | `spec/decisions/09-erc3643-profile-wiring.md` |
| Custody is confined to the adapter, so the Identity Registry must report the adapter as verified for seizures to execute. A deployment that needs another custodian requires a redesign of the custody backing rule and the Agent topology. | `spec/decisions/09-erc3643-profile-wiring.md` |
| The reference governor seals exactly once and offers no reseal, Agent management, registry rebinding, or authority rotation; a unit that needs any of these is a different profile with its own epoch increments and evidence. | `spec/decisions/09-erc3643-profile-wiring.md` |
| A token that unfreezes or moves tokens outside its Agent surface cannot satisfy the ownership precondition and is Partial or Unsupported. | `docs/PROFILES.md` |
| The profile suite runs against two clean-room fixtures. Compatibility with them is not evidence that an external ERC-3643 token satisfies the profile. | `docs/ARCHITECTURE.md` |

## Process

| Limitation | Owner |
| --- | --- |
| Continuous integration checks determinism, receipts, links, and the public surface; it does not run the mutation campaign, the Kontrol proofs, or a cloud prover. Those receipts are recorded from the committed tree by the tracked recorder scripts and are stale-checked, not re-executed, in CI. | `evidence/README.md` |
| The successor carries the working label `0.2.0-candidate.1`. No tag, release, audit, or production designation exists for it; the shipped candidate remains `0.1.0-candidate.2`. | `GOVERNANCE.md`; `SECURITY.md` |
