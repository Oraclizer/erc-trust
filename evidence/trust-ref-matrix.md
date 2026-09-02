# TRUST-REF evidence matrix

> Status note: this document describes the shipped candidate `0.1.0-candidate.2`.
> On the successor branch the receipts it cites live under `evidence/candidate-2/`,
> and the lane-by-lane status of the successor code is
> `evidence/current-profile-release-index-v3.json` under
> `evidence/evidence-mode.json`. This document is rewritten in the documentation
> change that closes the successor; until then its numbers are candidate 2 history,
> not measurements of the successor code.

Candidate: `0.1.0-candidate.2`

Scope: bounded native reference plus the sealed ERC-3643 conformance fixture
Status vocabulary: PASS means the cited, exact candidate obligation passed;
it is not a production or external-truth claim.

| Row | Owner | Obligation | Positive evidence | Negative evidence | Status |
| --- | --- | --- | --- | --- | --- |
| 01a | Native storage owner | storage layout, retrieve projection, exact frames and non-aliasing | `forge inspect TrustToken storage-layout`; unit action/reversal deltas; Certora storage rules | rejected/operational/full-storage stutter; replay stutter | PASS |
| 01b | ABI owner | selector and enum fidelity; encode/decode round trip | `forge inspect TrustToken methods`; SDK tests; `vectors/conformance-v1.json` | fixed-destination vector and MUT-05 | PASS |
| 01c | Transition owner | forward simulation of six applied actions and exact deltas | `testSixActionsAndSeparateReversals`; action fuzz; Certora applied rules | equal/decreasing FREEZE rejection, action-specific malformed shapes, custody disposition, and case-terminal reuse tests | PASS |
| 01d | Failure owner | Rejected versus OperationalFailure and full-state stutter | `testRejectedAndOperationalFailureStutter`; Certora structural stutter | reverting/malformed/wrong-echo doubles; MUT-04 | PASS |
| 01e | Receipt owner | event/error surface, token effect before final canonical receipt, recomputation | `testCanonicalEventOrder`; SDK receipt test; receipt schema | MUT-03 | PASS |
| 01f | Transfer owner | ordinary/enforcement relation, permission and unfrozen rules | freeze fuzz; 384,000-call invariant campaign; Certora transfer rules | over-frozen vectors and MUT-01 | PASS |
| 01g | Build owner | deterministic compiler settings, no proxy/delegatecall/selfdestruct, runtime binding | `foundry.toml`; `release-manifest.json`; public-surface scanner | forbidden-opcode/source inventory and EIP-170 gate | PASS |
| 02a | Compatibility owner | official ERC-7943 selectors and fungible interface identifier | `IERC7943.sol`; `0x3edbb4c4` interface test and vectors | invalid ERC-165 identifier test | PASS |
| 02b | ERC-7943 state owner | nonreverting views, absolute frozen semantics, ordinary-transfer differential | unit/fuzz/invariant tests | over-balance increase, equal-target rejection, decrease-through-reversal only, and frozen-floor failures | PASS |
| 02c | Route owner | exact-use typed context simulates one canonical step | `executeERC7943*`; exact caller/selector/calldata/binding/epoch ticket | raw-call failures, route invariant, MUT-02 | PASS |
| 02d | ERC-3643 profile owner | role/topology, identity/compliance, retrieve relation, malformed fail-closed | `ProfileGovernor`; `ERC3643ProfileUnitTest` | direct/batch bypass, rejection and malformed stutter | PASS (fixture-bound) |
| 02e | Authorization owner | action and nonce single consumption; fixed-action and calldata binding | action/reversal ID derivation and replay tests | replay test; fixed-field test; MUT-05 and MUT-06 | PASS |
| 02f | Surface owner | complete mutator inventory and common-kernel no-bypass | `forge inspect ... methods`; Certora inventory rule | raw native selectors; ERC-3643 direct/batch paths; MUT-07 | PASS |
| 02g | Profile owner | profile manifest; proxy and migration decision | `docs/PROFILES.md`; `release-manifest.json` | `proxySupported=false`; no delegatecall/proxy surface | PASS (no deployment claimed) |

## Boundary notes

- 02d does not prove an arbitrary ERC-3643 deployment or the truth of Identity
  Registry and Compliance responses. Full requires a separately reviewed
  runtime code hash and complete mutator proof.
- 02g does not verify a deployed address. The candidate is source/build-bound.
- Isabelle evidence proves the abstract model only within its declared
  semantic domain. The matrix above is implementation evidence and does not
  retroactively enlarge the abstract-model evidence.
- The official Isabelle/Solidity AFP framework was evaluated and clean-built,
  but its reference-candidate disposition is **NOT APPLICABLE**. Translating the available
  non-stateful helpers would not cover the security-critical transition,
  external-call, revert-stutter, or event-order behavior. This matrix therefore
  makes no Isabelle/Solidity implementation-verification claim.
