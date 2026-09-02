# Decision 01: delegation and cancellation are removed from the kernel

Status: frozen in kernel version 2 machine source. Native endpoint wired (`implementation/src/TrustToken.sol`, see
`08-native-wiring.md`); ERC-3643 profile wiring pending.

## Decision

1. The kernel has no delegation surface. The caller of an action or reversal
   MUST be the account currently registered for the request's `authorityRef`.
   That account MAY be a contract. The `scopeHash` request field of version 1
   and the `configureDelegation` mutator, its event, its storage, and its
   authorizer library are removed.
2. The kernel has no cancellation surface. The `Lifecycle.CANCELLED` value of
   version 1 is removed. Invalidating unconsumed commands is done by rotating
   the authority epoch or by rebinding a dependency; both are observable
   through existing events.
3. The standard text may say that an implementation MAY offer delegation as a
   profile extension. If it does, the delegation check MUST be recomputed by
   the contract from the complete command preimage, so that a delegated caller
   cannot change subject, amount, case, destination, or commitments under a
   scope that was approved for different values.

## Why

In the shipped version 1 candidate the delegation check compared only an
action mask, a validity time, and a caller-supplied opaque `scopeHash`
(`implementation/src/LegacyRouteAuthorizer.sol`). The contract never
recomputed that hash from the subject, amount, or case, so a delegate holding
an approved `scopeHash` could submit a command for a different subject or
amount. That is weaker than the abstract model, whose authorization compares
every payload field.

No consumer of the delegation surface exists. The tests, the SDK, the Kontrol
inputs, and the conformance vectors never call `configureDelegation`; the only
reference is a selector listed in a call-graph inventory rule. A contract
that needs to submit commands, such as a registry or a governance contract,
can be registered directly as the authority account; the authority model does
not require the submitter to be an externally owned account. The already
shipped ERC-3643 adapter profile uses exactly that model: a single immutable
authority account, no delegation.

Cancellation in the abstract model applies to authorizations that exist on
chain before execution. This kernel has no such object: a command is
validated, assessed, consumed, and applied in one transaction, and the only
party able to submit it is the authority account itself. There is nothing to
cancel that the authority could not simply decline to submit. Keeping an
unused `CANCELLED` lifecycle value in the ABI would advertise a path that no
code implements.

Removing both surfaces also recovers runtime size that the mandatory repairs
need. An internal compile canary against the version 1 source, which is not a
published artifact, measured the delegation removal alone at roughly 685
bytes of runtime; the implementation change publishes the exact measured
sizes.

## Alternatives considered

- Keep delegation and recompute the scope from subject, amount, and case. This
  is the sound version of the version 1 feature, but it adds a second
  authorization path with no consumer and no test, and it would keep the
  abstract per-authorization delegate as a mandatory mapping obligation.
- Keep a nonce-level cancellation function. The same internal canary put the
  naive form at roughly 289 bytes. With no signature scheme and no delegate,
  the function would protect against no one.

## Consequences

- The abstract model's delegation and cancellation commands and the theorems
  about them remain valid statements about the model. In the refinement
  ledger they are classified as abstract-only with no current consumer, not as
  discharged implementation evidence.
- The version 2 `ActionRequest` has 20 fields (version 1 had 21) and the
  action calldata length is 644 bytes.

## Reopen when

- A first-party or third-party integrator needs an executor that is not the
  authority account and cannot be registered as one.
- A signature-based authorization profile is standardized; that profile must
  then define its own cancellation observable.
