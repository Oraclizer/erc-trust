# Decision 04: one receipt preimage for actions and reversals

Status: frozen in kernel version 2 machine source (`structs.Receipt`,
`hashes.receiptHash`). Native endpoint wired (`implementation/src/TrustToken.sol`, see
`08-native-wiring.md`); ERC-3643 profile wiring pending.

## Decision

1. Action and reversal receipts share one struct and one preimage:
   `DOMAIN` followed by every `Receipt` field except `receiptHash`, in the
   field order of the schema (17 words). The first field is `receiptKind`
   (`ACTION = 1`, `REVERSAL = 2`); zero is reserved.
2. `commandKind` holds the `ActionKind` value for actions and the
   `ReversalKind` value for reversals. `parentCommandId` is zero for actions
   and the reversed `actionId` for reversals.
3. The receipt binds `subject`, `source`, `destination`, `amount`, `caseId`,
   `authorityRef`, `dependencyRoot`, `provenanceCommitment`,
   `assessmentEvidence`, `preState`, `postState`, and `externalCommitment`.
4. `receiptHash` MUST equal the execute return value, the stored
   `Receipt.receiptHash`, and the `receiptHash` argument of the final applied
   event. `receipt(commandId)` is part of the kernel interface, so a reader
   who has the command identifier can fetch every preimage input from the
   endpoint and recompute the hash without the transaction calldata.
5. `preState`, `postState`, and `assessmentEvidence` are opaque commitments in
   the kernel. Each profile MUST document their preimages together with its
   runtime identity. Recomputing a receipt hash never requires those
   preimages; it requires only the stored field values.
6. The reversal-specific effect-chain value of version 1 (`popEffectHash`) is
   not part of the kernel receipt. `externalCommitment` is zero for every
   reversal.

## Why

Version 1 had two different 12-word preimages that shared the same prefix
shape, stored both action kinds and reversal kinds in one `commandKind` byte
(so `FREEZE` and `UNFREEZE` were both 0), and left `policyBinding` out of the
reversal preimage. The reversal preimage also contained the reversal command
hash, which was never stored, so a reversal receipt could not be recomputed
from the endpoint's state. The native token and the ERC-3643 adapter filled
that slot with different values, so the same logical reversal produced two
different hashes in the two profiles.

A reader of a receipt needs to know which authority issued the command, and
the version 1 preimage did not bind that reference. Version 2 binds
`authorityRef` directly.

One preimage with a nonzero kind tag gives indexers one parser, gives the two
profiles one formula, and makes the domain separation between the two receipt
kinds a stated property rather than an accident of field widths.

The effect-chain value is dropped from the kernel because its preimage was
implementation specific and differed between the two profiles. The reversed
action, the case, and the pre and post observations already identify which
effect was removed.

## Alternatives considered

- Keep two preimages and only add a tag. Rejected: it keeps two parsers and
  two profile-specific slots.
- Put the transaction-level calldata (nonce, epochs, validity window) into
  the receipt. Rejected: `commandId` already binds the whole request; the
  receipt adds what the request does not contain.
- Standardize the observation preimage. Rejected: the observed state depends
  on the profile's state model, and recomputation does not need it.

## Consequences

- `Receipt` has 17 fields (version 1 had 12). The native runtime size budget
  for the larger receipt is tracked and measured in the implementation change;
  an internal compile canary against the version 1 source, which is not a
  published artifact, put the receipt tag alone at roughly 189 bytes.
- The SDK receipt helper covers reversals; version 1 had no reversal helper
  and no reversal vector.

## Reopen when

- A profile needs a receipt field that is not derivable from the stored
  receipt; it must then extend the struct with a new kernel version rather
  than reinterpret an existing field.
