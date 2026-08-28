# Architecture and trust boundaries

ERC-TRUST separates three questions that privileged token interfaces commonly
collapse: the regulatory meaning of a command, the mechanism that changes token
state, and the evidence supporting a claim about this implementation.

> [!WARNING]
> This document describes an unaudited reference candidate, not a verified
> deployment. It does not establish legal authority or the truth of any
> external input.

## System view

<div align="center">
  <img src="assets/architecture-action-flow.svg" alt="Four-stage flow from the command boundary through validation and bound inputs to the state transition, ending with the canonical receipt emitted last" width="900">
</div>

The request commits to authority, scope, epochs, validity, nonce, policy,
provenance, and action-specific evidence. A successful transition records a
receipt only after state mutation and required compatibility events complete.
Rejected or operationally unavailable assessments revert the transaction, so
authorization is not consumed on a failed command.

## Component ownership

| Component | Owns | Reads or calls | Must not be treated as |
| --- | --- | --- | --- |
| `TrustToken` | ERC-20 balances, freeze/restriction state, action lifecycle, custody, settlement, entitlement, tickets, receipts | Four bound read-only dependencies | A legal adjudicator or deployment |
| `TrustDecision` | Shape and action-specific decision logic | Request and dependency results | An external-fact oracle |
| `TrustPolicyBinding` | Runtime code hash, configuration, schema, epoch, and binding digest | Bound dependency metadata | A guarantee that dependency output is true |
| `ERC7943RouteTicket` | Exact-use route-key derivation and consumption | Current wrapper call | Standing authority for raw ERC-7943 calls |
| `ERC3643TrustAdapter` | TRUST action state, custody, terminal cases, receipts | Upstream token, Identity Registry, Compliance, sealed topology | Proof that an arbitrary ERC-3643 deployment is Full |
| `ProfileGovernor` | One-way topology seal | Token code hash, owner, registry, compliance, exclusive Agent | A general-purpose administrator |
| Operator SDK | Deterministic IDs, hashes, and calldata | Caller-provided request data | A signer, relayer, fact checker, or policy engine |

## Native Full v1

`TrustToken` is an immutable ERC-20, ERC-165, and ERC-7943 fungible
implementation. It is the sole owner of balances and regulatory state. The
candidate exposes no proxy, `delegatecall`, `selfdestruct`, public mint, or
public burn surface.

The four external dependencies are policy, identity, settlement, and
entitlement views. Each binding records the dependency address, runtime code
hash, configuration digest, schema, epoch, and resulting binding hash. Calls
are read-only and fail closed when code, schema, configuration, return data, or
availability does not match the request's bound assumptions.

### Native action path

<div align="center">
  <img src="assets/architecture-native-sequence.svg" alt="Sequence diagram of the native action path between the operator, TrustToken, a bound dependency, and the transition kernel, showing the applicable and the rejected branches" width="900">
</div>

The kernel enforces action-specific rules. `FREEZE` only increases a frozen
amount; a decrease requires a separately authorized `UNFREEZE` that rechecks
the current policy binding. `SEIZE` opens exact custody. `RELEASE` returns that
same encumbered amount to the declared prior holder and closes custody
atomically. A disposition must match the active custodian, prior holder, and
amount. `CONFISCATE` makes the case terminal. `LIQUIDATE` binds settlement and
proceeds commitments. `RECOVER` consumes an entitlement commitment once.

## ERC-7943 exact-use route

The sensitive `setFrozenTokens` and `forcedTransfer` selectors are self-call
targets, not public authority surfaces.

1. `executeERC7943Action` or `executeERC7943Reversal` validates and authorizes
   the complete typed command.
2. The wrapper consumes the authorization and creates one route ticket bound
   to command ID, selector, calldata hash, route kind, action or reversal,
   authority epoch, policy epoch, and current binding.
3. The token calls its own sensitive selector in the same transaction.
4. The selector consumes the ticket before applying the transition.
5. Reuse, altered calldata, direct external calls, and wrong selectors revert.

The ticket is not persisted as reusable authority. It exists only during the
validated wrapper path.

## ERC-3643 Verified Full v1

The adapter profile deliberately separates state ownership:

<div align="center">
  <img src="assets/architecture-erc3643-profile.svg" alt="Privileged control path, bound upstream inputs, and separated state ownership in the ERC-3643 Verified Full profile" width="900">
</div>

`ERC3643TrustAdapter` owns TRUST action records, custody state, terminal cases,
and receipts. The upstream token owns balances and token-level frozen state.
`ProfileGovernor` owns the token and seals the expected token runtime code
hash, token address, adapter address, Identity Registry, Compliance contract,
chain, and exclusive-Agent relationship.

After sealing, `ProfileGovernor` has no arbitrary-call or Agent-management
surface. Before every action, the adapter requires the topology to remain Full.
It treats Identity Registry and Compliance responses as fail-closed inputs,
invokes only the expected Agent mutator, and checks exact balance or frozen
postconditions before recording a receipt.

The repository's clean-room test double is only a conformance harness. It is
not an ERC-3643 implementation, and compatibility with it is not evidence that
an external token satisfies the Verified Full profile.

## Receipt and observation boundary

A receipt commits to the command, action or reversal kind, source,
destination, amount, case, policy binding, provenance, pre-state, post-state,
and the action-specific external commitment. It is recomputable from the
declared inputs and observations.

A receipt proves neither that:

- the authority had valid off-chain legal power;
- an identity, policy, settlement, proceeds, or entitlement assertion was
  factually correct;
- an external custodian performed an off-chain act;
- the caller secured keys or submitted the transaction correctly.

Those truths remain outside the software boundary.

## Deployment boundary

This repository includes no deployment manifest, address, chain claim, proxy,
migration procedure, or key-management design. Both reference profiles report
`proxySupported=false`; candidate v1 also treats migration support as false.

A deployment claim needs a separate manifest that binds the exact source tree,
compiler and optimizer settings, runtime bytecode, constructor inputs,
addresses, roles, dependency bindings and epochs, profile topology, chain, and
evidence manifest. Any mismatch downgrades the declaration rather than
inheriting this repository's Full label.

## Assurance boundary

The evidence package includes tests, bounded formal rules, selected bytecode
proofs, negative mutations, deterministic builds, claim matrices, and
provenance records. Their precise scope is in
[`FORMAL_VERIFICATION.md`](../FORMAL_VERIFICATION.md) and
[`evidence/verification-summary.md`](../evidence/verification-summary.md).

It does not establish a complete Isabelle-to-Solidity-to-EVM refinement
theorem, an independent audit, or production safety.
