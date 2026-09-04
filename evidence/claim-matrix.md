# Public claim matrix

> Status note: the first section describes the successor code on private `main`;
> the sections that follow it describe the shipped candidate `0.1.0-candidate.2`,
> whose receipts live under `evidence/candidate-2/`. The boundary of every claim is
> also stated, entry by entry, in `known-limitations.md`.

## Successor claims (kernel version 2, private main)

The successor code under `implementation/` is described by the lane index
`evidence/current-profile-release-index-v3.json` under `evidence/evidence-mode.json`.
Each claim below names the receipt that backs it and the qualifier it must carry.

| Claim | Required qualifier | Evidence |
| --- | --- | --- |
| "The native token and the ERC-3643 Partial profile adapter and governor implement kernel version 2 of the ERC-TRUST wire format within their documented scopes." | Name the commit and release manifest; say the ERC-3643 descriptor is `PARTIAL/full=false`; unaudited, not for production | `spec/erc-trust-kernel-v2.json`; `evidence/release-manifest.json`; `evidence/foundry-results-v3.json` (tests, fuzz, invariants); `vectors/conformance-v2.json` |
| "The ERC-3643 reference fails closed when a forced transfer changes either touched account's actual restriction flag, and its receipt observation binds actual restriction flags for subject, source, and destination." | Reference-runtime and fixture scope only; this does not prove manifest completeness or close the ordinary inbound-growth window | `implementation/src/profiles/ERC3643TrustAdapter.sol`; `implementation/test/ERC3643Profile.unit.t.sol`; `evidence/mutation-results.json` |
| "The Isabelle session models kernel version 2 and builds clean with no oracle dependency." | Say "abstract model"; the runtime link is an undischarged assumption | `evidence/isabelle-results-v3.json`; `formal/isabelle/ERC_TRUST/Proof_Audit.thy` |
| "Every load-bearing abstract condition the obligation ledger names is connected to the final code by a source consumer, a positive test, a declared negative detector, and a compiled or downstream consumer." | Say "mapped implementation evidence; end-to-end refinement incomplete"; a negative is a killed consumer-removal mutation when one source consumer can be removed, otherwise a bounded behavioral negative whose scope the ledger states; the enumeration is limited to conditions the review identified | `evidence/end-to-end-refinement/obligation-ledger-v3.json`, `obligation-ledger-summary-v3.json`, `central-closure-v3.json`; `evidence/mutation-results.json`; `evidence/kontrol-results-v3.json` |
| "The three runtime templates are byte-for-byte reproducible from the exact sources under the pinned compiler, and the compiled bytes agree with the pinned-compiler replay in ABI, storage layout, creation and runtime bytecode, method identifiers, and immutable references." | Reproducibility and semantic identity, not compiler correctness; no deployment identity | `evidence/deterministic-build.json` (schema v3, three subjects); `evidence/runtime-binding-v3.json` and `evidence/runtime-binding-v3/`; `scripts/verify-runtime-binding-v3.mjs --replay` |
| "An implementer who reads only the specification and the vectors reproduces every identifier, hash, calldata, and receipt hash of the conformance vectors." | Specification-only reproduction of the vectors; not a second implementation of the endpoints | `evidence/independent-reproduction-v3.json`; `scripts/independent-reproduction-v3.mjs` |
| "Every receipt that binds code identity (deterministic build, Foundry, mutation, Kontrol, runtime binding, and Certora when present) binds the current source root or runtime template, and a stale one is rejected; the Isabelle receipt binds the formal root, the independent reproduction binds the vectors, and the model regression record binds neither." | Receipts are bound to the identity of the artifact they are about, not to time | `scripts/verify-current-profile-release-v3.mjs`; `scripts/verify-runtime-binding-v3.mjs` (stale evidence rejection) |

Pending lanes at this change: `certora` and `certoraInputs` (the final input root and
four rule IDs are frozen, no source has been sent to the cloud prover, and transmission
requires separate approval), and nothing else. The evidence mode stays
`successor-development` until those lanes are recorded; release mode requires zero
pending lanes.

Forbidden for the successor, in addition to the list above: "end-to-end refinement
complete", "Native Full complete", "Verified Full complete", "implementation conforms
to the model", and any wording that presents the four Kontrol proofs as a proof of the
runtime link rather than bounded instances of it.

## Allowed exact claims (candidate 2)

| Claim | Required qualifier | Evidence |
| --- | --- | --- |
| `pilot conjunct VERIFIED` | Applies only to the preserved FREEZE pilot | `pilot/evidence/proof-report-v2.md` |
| “The ERC-TRUST abstract regulatory-action model has been mechanically verified in Isabelle/HOL within its declared semantic domain.” | Must retain “abstract,” “within,” and “declared semantic domain” | `formal/isabelle/ERC_TRUST/` and model-verification manifest |
| “The reference candidate passed the published bounded Foundry, Certora, Kontrol, deterministic-build, and mutation checks.” | Name the exact candidate commit and manifest; say unaudited/not for production | `evidence/verification-summary.md` and release manifest |
| “The native candidate implements the six typed actions and three separate reversals.” | Candidate/source scope only | implementation and tests |
| “Historical candidate 2 passed the then-named ERC-3643 Verified Full topology fixture tests.” | Historical wording only; the current reference is corrected to Partial and no arbitrary deployment or current Full claim follows | historical candidate 2 profile tests and current `docs/PROFILES.md` |

## Forbidden or unsupported claims

- `ERC-TRUST is formally verified`
- `implementation fully verified`
- `the Solidity implementation is proven correct`
- `end-to-end refinement is complete`
- `production-ready`
- `audited`
- `deployment verified`
- `proxy/migration verified`
- `all TRUST-REF discharged` without the candidate and bounded-evidence
  qualifier
- any assertion that a policy, identity, settlement, proceeds, entitlement,
  ownership, or legal response is true merely because its commitment was
  recorded

## Mandatory warning

README, draft, opening post, release notes, and package metadata must say:

> Unaudited. Not for production. No deployment, proxy, migration, or external
> legal/factual truth is verified.
