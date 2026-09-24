# Decision 12: requests outside canonical form

Status: kernel version 2 machine source (`hashes.encoding.canonicality`,
`interface.eventOrder`, `shapeRules.order`, `shapeRules.appliesTo`,
`domain.description`), 2026-09-24.

## Decision

1. The typed command functions are `executeRegulatoryAction` and
   `executeRegulatoryReversal` and, on an endpoint that implements
   `IERCTrustNativeRoute`, `executeERC7943Action` and `executeERC7943Reversal`.
   The obligation to reject a request that is not in canonical form applies to
   these functions.
2. A request is in canonical form when its calldata is the function selector
   followed by the canonical encoding of the request (exact length, no dirty
   high bits in address or narrow integer words, enum values inside the
   declared range) and the call carries zero value.
3. A typed command function rejects every other request as a full-state
   stutter that consumes nothing and in addition makes no external call: no
   state change, no event, no call to another account (for a proxy-fronted
   endpoint, the delegate call by which the proxy runs its implementation does
   not count).
4. The proposal specifies neither the revert data of that rejection nor which
   defect is detected first when a request has several.
5. A reentrant call is a call to a typed command function made while an
   earlier call to the same endpoint has not yet returned. An endpoint may
   reject it before any other check, with any revert data, as a full-state
   stutter.
6. Where a rule that names an error or a reason, including the validation
   order, governs a call to a typed command function, it applies only when the
   request is in canonical form and the call is not rejected as a reentrant
   call.
7. `deriveActionId` and `deriveReversalId` return `hashes.actionId` and
   `hashes.reversalId` when they are called with zero value and their calldata
   is their selector followed by the canonical encoding of the request; their
   result for any other call is not specified. An identifier they return does
   not relax the canonical-form requirement: a typed command function rejects
   a request that is not in canonical form whatever its identifier field
   holds.

## Why

Connecting the compiled runtime to the model found four places where the
previous text promised more than the reference implementation does. The
execute functions do not accept ether, so a call with value reverts in the
dispatcher before any kernel check, with empty revert data, while the text
required, for example, `TrustUnauthorized` from an unauthorized caller. Which
defect an implementation detects first depends on when each field is read, so
a fixed payload for a malformed request is not a property callers can rely on.
The identifier helpers hash the request words without validating them, and
decision 10 rejected a length-parity view for them, while the previous text
applied the rejection to every function. The endpoint's reentrancy guard runs
before validation, so a reentrant call is rejected before any rule that names
an error.

Requiring the observable safety property (no state change, no event, no
external call) and leaving the revert data open keeps the guarantee that
matters to integrators without constraining the implementation where no
caller can rely on the result.

## Alternatives considered

- Fix the revert data of every malformed request (for example, empty data).
  Rejected: implementations detect defects in different orders, and a typed
  error returned by an earlier check would violate it.
- Validate the request in the identifier helpers. Rejected: it adds bytecode
  to every endpoint for a helper whose output a typed command function
  re-derives and checks anyway, and decision 10 already rejected a
  length-parity view for the same reason.

## Consequences

The formal model adds the conformance relation `alpha_transaction_spec`
(`TRUST_Out_Of_Spec_Refinement.thy`), which keeps `alpha_transaction` for
requests in canonical form that the bridge decodes and relates every other
request to a full-state
stutter with unspecified revert data. The Test Cases section of the proposal
adds a row for a request outside canonical form that carries the identifier
the helper returns for it; `vectors/conformance-v2.json` is unchanged, because
its vectors carry canonical calldata only.

## Reopen when

- an execute function is made payable, which would change what canonical form
  requires of the call value;
- a caller or a standard needs a fixed revert payload for malformed requests;
- the identifier helpers are required to validate their input.
