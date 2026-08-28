# Public claim matrix

## Allowed exact claims

| Claim | Required qualifier | Evidence |
| --- | --- | --- |
| `pilot conjunct VERIFIED` | Applies only to the preserved FREEZE pilot | `pilot/evidence/proof-report-v2.md` |
| “The ERC-TRUST abstract regulatory-action model has been mechanically verified in Isabelle/HOL within its declared semantic domain.” | Must retain “abstract,” “within,” and “declared semantic domain” | `formal/isabelle/ERC_TRUST/` and model-verification manifest |
| “The reference candidate passed the published bounded Foundry, Certora, Kontrol, deterministic-build, and mutation checks.” | Name the exact candidate commit and manifest; say unaudited/not for production | `evidence/verification-summary.md` and release manifest |
| “The native candidate implements the six typed actions and three separate reversals.” | Candidate/source scope only | implementation and tests |
| “The ERC-3643 conformance fixture passes the Verified Full topology tests.” | Fixture-bound; not a claim about arbitrary deployments | profile tests and profile documentation |

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
