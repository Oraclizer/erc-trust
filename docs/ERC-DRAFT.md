# ERC-TRUST: Typed Regulatory Actions for Security Tokens

Status: pre-discussion draft; no ERC number assigned

Candidate: `0.1.0-candidate.2`
Assurance: unaudited, not for production

Research companion: [Mechanizing Typed Regulatory Actions for Security
Tokens: Semantics, Falsification, and Bounded EVM Evidence](https://arxiv.org/abs/2608.29134).
This draft is the normative proposal surface; the paper explains the formal
semantics and evidence boundary but does not replace the requirements below.

Standards relationship: ERC-TRUST is a conformance extension of the proposed
ERC-8319 (Regulatory Compliance Protocol). ERC-8319 is an open, not-yet-merged
Draft at ethereum/ERCs pull request 1848. The official ERC-TRUST proposal will
be submitted after ERC-8319 merges, with the intended preamble
`requires: 20, 165, 7943, 8319`.

## Abstract

This proposal defines a token-independent vocabulary and execution contract
for six typed regulatory actions: `FREEZE`, `SEIZE`, `CONFISCATE`,
`LIQUIDATE`, `RESTRICT`, and `RECOVER`. Each command binds authority, scope,
policy and provenance commitments, deployment domain, epochs, nonce, validity
window, and action-specific evidence. Successful execution produces one
canonical receipt after the token-level effects. Rejection and operational
failure are distinct and both revert.

The interface is intentionally separable from the reference implementation.
The native reference is immutable and uses versioned read-only dependency
bindings. ERC-7943 sensitive calls are available only through a
same-transaction exact-use ticket. An ERC-3643 deployment is a Full profile
only when a frozen runtime code hash and a one-way `ProfileGovernor` prove an
exclusive adapter Agent topology; otherwise it is Partial or Unsupported.

## Motivation

Existing token standards expose useful mechanics, but an operator also needs
to know what an action means, which authority and evidence it binds, whether
it may be replayed or reversed, and what can be independently recomputed from
the resulting receipt.

ERC-TRUST separates three questions:

1. **Meaning**: which typed regulatory action is requested?
2. **Mechanism**: which token or adapter transition implements it?
3. **Assurance**: which exact implementation properties have evidence?

This separation avoids treating a privileged transfer primitive as proof of
the legal, identity, settlement, or entitlement facts that motivated it.

## Specification

### Action taxonomy

| Value | Action | Required token effect | Action-specific record |
| ---: | --- | --- | --- |
| 0 | `FREEZE` | Set the subject's frozen amount | prior frozen amount |
| 1 | `SEIZE` | Move to declared custody | custodian, prior holder, encumbrance |
| 2 | `CONFISCATE` | Terminal privileged disposition | destination |
| 3 | `LIQUIDATE` | Privileged disposition | settlement and proceeds commitments |
| 4 | `RESTRICT` | Disable ordinary send/receive | prior restriction flag |
| 5 | `RECOVER` | One-time entitlement-bound disposition | entitlement and destination |

The reversal domain is separate: `UNFREEZE`, `RELEASE`, and `UNRESTRICT`.
`CONFISCATE` is terminal. `LIQUIDATE` and `RECOVER` do not acquire an implicit
reversal merely because a token transfer can technically be performed later.

### Assessment outcomes

An implementation MUST distinguish:

- `APPLICABLE`: all bound checks completed and permit execution;
- `REJECTED`: the checks completed and deny the command;
- `OPERATIONAL_FAILURE`: a required dependency was unavailable, malformed,
  stale, or inconsistent.

`REJECTED` and `OPERATIONAL_FAILURE` MUST revert and MUST NOT consume the
command identifier or nonce.

### Command binding

An action identifier MUST be derived from the ABI encoding of:

```text
DOMAIN, implementation address, chain id, ActionRequest(actionId = 0)
```

All remaining fields, including validity bounds and destination, remain in
the derivation. The command hash uses the completed request, including the
derived action identifier. A command identifier and the
`(authorityRef, authorityEpoch, nonce)` tuple are each exactly-once.

### Canonical receipt

After applying the action, the implementation MUST store and emit a receipt
binding:

```text
domain, command id, command kind, source, destination, amount, case id,
policy binding, provenance commitment, pre-state, post-state,
external commitment
```

The receipt event MUST be the last event emitted by the atomic action. Token
or compatibility events MUST precede it. A caller can recompute the receipt
hash from the public schema and vectors.

### External dependencies

Policy, identity, settlement, and entitlement dependencies MUST be read-only
during native execution and MUST be bound to:

- dependency address;
- runtime code hash;
- configuration digest;
- schema;
- monotonically versioned epoch.

Missing code, revert, malformed return data, wrong command echo, wrong binding
echo, or stale epoch MUST fail closed. These bindings prove what code and
configuration were consulted; they do not prove external legal or factual
truth.

### ERC-20 and ERC-165

The native reference implements ERC-20 and reports ERC-165 support for the
interfaces it actually implements. It MUST return `false` for the ERC-165
invalid identifier `0xffffffff`.

### ERC-7943 route

The fungible ERC-7943 interface identifier is `0x3edbb4c4`. Views MUST be
non-mutating and non-reverting. `canTransfer` MUST include endpoint permission
and the ordinary unfrozen balance.

Raw calls to `setFrozenTokens` and `forcedTransfer` MUST fail. An ERC-TRUST
wrapper MAY invoke them only after creating an in-memory/storage ticket bound
to caller, selector, calldata hash, policy binding, authority epoch, policy
epoch, and command identifier. The ticket MUST be consumed exactly once in
the same transaction and MUST NOT remain live after return or revert.

For the absolute frozen amount, a greater target is a `FREEZE` action or
freeze amendment, a lower target is an `UNFREEZE` reversal referencing the
original action, and an equal target is a no-state-change rejection.
`setFrozenTokens` MUST NOT relabel a decrease as `FREEZE`.

### ERC-3643 Verified profile

ERC-3643 identity and compliance responses are upstream inputs, not facts
proved by ERC-TRUST. A deployment MAY report the Verified Full profile only if:

1. the adapter is the token's exclusive Agent;
2. a `ProfileGovernor` is the token owner and exposes no arbitrary-call or
   Agent-management path after its one-way seal;
3. token runtime code hash, Identity Registry, Compliance, owner, and
   exclusive Agent match the sealed binding;
4. every privileged direct and batch token mutator is unreachable except
   through the adapter;
5. the adapter implements all six actions and the three declared reversals.

Failing any condition makes the deployment Partial or Unsupported. Merely
returning `isAgent(adapter) == true` is insufficient to prove exclusivity.

### Upgradeability and migration

The reference v1 is immutable. Proxy and migration profiles are Unsupported.
A proxy or migration profile requires a separate conformance and assurance
gate and MUST NOT inherit the native Full designation.

## Rationale

The action enum is smaller than the transition label set because reversal is
not a new regulatory action. Separate action-specific commitments prevent a
generic privileged transfer from silently standing in for custody,
settlement, proceeds, or entitlement semantics.

The ERC-7943 adapter uses an exact-use ticket rather than a standing privileged
role so that a sensitive selector cannot be reused outside the typed command.
The ERC-3643 route uses a separate state owner because upstream token
mutations are stateful and cannot satisfy the native read-only dependency
boundary.

## Security considerations

- Authority and dependency configuration are security-critical governance.
- Receipt commitments are not substitutes for the underlying evidence.
- A terminal `CONFISCATE` case cannot be reused, and any matched custody
  encumbrance must be closed atomically with the disposition.
- `block.timestamp` bounds are subject to normal validator timestamp
  tolerance.
- An ERC-3643 Full designation is invalid if another Agent, owner call,
  upgrade, batch path, or mutable code path can bypass the adapter.
- Runtime bytecode size and compiler settings are deployment constraints.
- The reference has not been audited and is not production-ready.

## Backwards compatibility

The standard does not change ERC-20. ERC-7943 compatibility is explicit.
ERC-3643 compatibility is deployment-profile-specific and does not claim that
all ERC-3643 deployments satisfy the Full topology.

## Reference implementation and evidence

- Solidity: `implementation/src/`
- Tests: `implementation/test/`
- Certora: `implementation/certora/`
- Kontrol: `implementation/kontrol/`
- Vectors: `vectors/conformance-v1.json`
- Receipt schema: `schemas/receipt.schema.json`
- Evidence entry: `evidence/verification-summary.md`

## Copyright

Copyright and related rights waived via [CC0](LICENSE-CC0.md).

The ERC-3643 declarations are clean-room interface signatures only; no GPL
implementation source is copied or adapted.
