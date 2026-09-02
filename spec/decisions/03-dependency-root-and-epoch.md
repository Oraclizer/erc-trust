# Decision 03: ordered dependency root and global dependency epoch

Status: frozen in kernel version 2 machine source (`hashes.dependencyRoot`,
`ActionRequest.dependencyRoot`, `ActionRequest.dependencyEpoch`,
`ReversalRequest.dependencyRoot`, `ReversalRequest.dependencyEpoch`).
Native endpoint wired (`implementation/src/TrustToken.sol`, see
`08-native-wiring.md`); ERC-3643 profile wiring pending.

## Decision

1. Every endpoint exposes `dependencyState()` returning a `dependencyRoot`
   and a `dependencyEpoch`.
2. The root is `keccak256(abi.encode(DOMAIN, DEPENDENCY_ROOT_TAG,
   policyBinding, identityBinding, settlementBinding, entitlementBinding))`,
   ordered by `BindingKind`. A profile that has no dependency of a given kind
   uses `bytes32(0)` in that slot and says so in its manifest.
3. The epoch starts at 1 and increments by exactly one on every rebind of any
   kind. Every rebind emits `TrustDependencyChanged` with the kind, the
   previous and current per-kind binding, the new root, and the new epoch.
4. Both the action request and the reversal request carry the root and the
   epoch. Validation rejects a command whose pair differs from the current
   pair (reason 5). The receipt binds the root the command was validated
   against.

## Why

Version 1 bound only the policy dependency into the request
(`policyCommitment`, `policyEpoch`). Rebinding the identity, settlement, or
entitlement dependency raised that dependency's own epoch but did not make
existing commands stale, so a command built under one identity registry could
execute after the registry was replaced. The draft text required stale
invalidation for all four kinds, and the reference implemented it for one.

A single root and a single epoch keep the request small (two words instead of
eight) while binding every dependency. The ordered, tagged preimage makes the
root domain separated: swapping two bindings or dropping the tag yields a
different root, so a mutant that computes the root without the tag or in a
different order is detectable.

Reversals also carry the pair. In version 1 a reversal was validated against
the live policy binding but its receipt hash did not bind that binding, so a
reader could not tell under which dependency state a reversal was evaluated.

## Alternatives considered

- Four separate `(binding, epoch)` pairs in the request. Rejected: six more
  words per request for no additional information once the root is ordered
  and tagged.
- Keep per-kind epochs only. Rejected: a per-kind epoch cannot express "the
  set of all bindings is the one I built this command against" in one
  comparison, and it does not bind the other three kinds.

## Consequences

- The abstract model's single policy epoch is generalized to a dependency
  epoch that any kind of rebind advances; the stale-policy theorems are
  re-established for the root rather than renamed.
- Negatives needed: identity, settlement, and entitlement rebind each making
  an earlier command stale; a root computed without the tag or in another
  order; the root comparison removed from validation.

## Reopen when

- A profile needs more than four dependency kinds; the root preimage then
  grows and the tag string must change.
