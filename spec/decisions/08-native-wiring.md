# Decision 08: how the native endpoint consumes the kernel machine source

Status: implemented for the native token (`implementation/src/TrustToken.sol`).
The ERC-3643 profile adapter still implements kernel version 1 and is wired in
the profile change.

## Decision

1. The generator writes a second, byte-identical copy of the Solidity rendering
   to `implementation/src/generated/IERCTrustKernel.sol`, and its check mode
   rejects any drift between `spec/generated/IERCTrustKernel.sol` and that copy.
   The native token imports the kernel types, the kernel interface, the native
   route interface, the dependency interface, and the ERC-165 interface only
   from the generated copy. No hand-written duplicate of a kernel type exists
   under `implementation/`.
2. The kernel errors are inherited from `IERCTrustKernel` and
   `IERCTrustNativeRoute`; `implementation/src/TrustErrors.sol` keeps only the
   errors the kernel does not define (reentrancy, unsupported selector, zero
   address, insufficient balance and allowance) plus the version 1 set the
   adapter still uses.
3. Native-only records live in `implementation/src/TrustNativeTypes.sol`
   (bindings, authorities, overlay heads and effect records, custody, pending
   route data, the route ticket) and the pure helpers in
   `implementation/src/TrustNativeDecision.sol`. The version 1 type library
   `implementation/src/TrustTypes.sol` and `implementation/src/TrustDecision.sol`
   remain solely for the adapter until the profile change.
4. Every public view of the native token is either an ERC-20 view, an ERC-7943
   view, a kernel view, or a governance write. The version 1 convenience getters
   (`commandHash`, `reversalHash`, `routeLive`, `nonceUsed`, `isRestricted`,
   `getAuthorityState`, `getBindingState`, `caseTerminal`, and the custody,
   settlement, and entitlement record getters) are removed. Tests observe
   restriction through `canSend`, replay through the typed `TrustReplay` error,
   the route ticket through a storage read, and custody through balances and
   `caseRecord`.
5. Settlement and entitlement are not stored as separate records. The receipt
   binds them through `externalCommitment` (decision 04), the action record keeps
   the command hash and assessment evidence, and one-time entitlement
   consumption is tracked by commitment. Custody keeps a per-case record because
   `RELEASE` and custody dispositions consume it; the version 1 custody effect
   chain is dropped because a case holds at most one custody (`CT-10`).
6. The exact-use ERC-7943 route keeps the version 1 shape: the wrapper
   validates, assesses, and consumes, then self-calls the sensitive selector,
   which consumes the ticket and applies the prepared command. The ticket stores
   the command identifier, the selector, the calldata hash, and the dependency
   root and epoch current at preparation; consumption compares every stored
   field against the sensitive call and the current dependency state, and the
   sensitive selector additionally compares the prepared record against its
   arguments. `TrustRouteMismatch` carries an identifier of the rejected call
   (domain, endpoint, selector, calldata hash) that is computed only on failure
   and never stored; no stored key is part of the enforcement. The commitments
   the action record does not retain are held in `PendingCommitments` only for
   the route path and deleted on apply.
7. The receipt hash is computed over the domain followed by the sixteen
   non-hash fields of the memory struct, which are laid out as sixteen
   consecutive words and therefore equal the canonical ABI encoding of
   decision 04. The tests recompute every stored receipt with the ABI coder.
8. Profile-defined preimages of the native token: `assessmentEvidence` is the
   policy evidence, chained by `keccak256(abi.encode(previous, next))` with the
   identity evidence when a destination is present, the settlement evidence for
   `LIQUIDATE`, and the entitlement evidence for `RECOVER`; a reversal binds the
   policy evidence of its own assessment. `preState` and `postState` commit to
   the total supply, the subject's balance, stored frozen target, and restriction
   flag, the source's and destination's balance and custody backing, the case's
   custody record, the subject's overlay heads, and the case record.
9. `getFrozenTokens` saturates the stored target at the current balance
   (decision 02, cross-case rule); `FREEZE` amendments and `UNFREEZE`
   restoration operate on the stored target. Ordinary transfer capacity first
   subtracts custody backing from the balance and then applies the stored frozen
   target to the remainder, floored at zero; `getFrozenTokens` reports only the
   saturated target, so an integrator that needs the ordinary capacity of a
   custodian account must use `canTransfer`, not `balance - getFrozenTokens`.
10. Validation order for actions and reversals alike: domain, identifier,
    replay of the command identifier, validity window, authority epoch and
    account, dependency root and epoch, nonce freshness, then the shape rules
    and the state-dependent rules (case phase, lifecycle, pairing, live head).
    A replayed or stale command is therefore reported before any
    state-dependent rule.

## Why

Copying the generated file keeps `forge build`, the Certora and Kontrol tools,
and the release manifest inside the `implementation/` root that they already
treat as the compilation unit, while the generator check makes the copy
incapable of drifting from the machine source. A remapping to `spec/generated`
would have moved a normative input outside the tool roots and outside the
mutation source root.

Removing the convenience getters and the separate settlement and entitlement
records recovers the runtime budget that the larger receipt, the case records,
the dependency root, and the live profile descriptor need: the native runtime
went from 24,177 bytes with a 399-byte margin to 20,474 bytes with a 4,102-byte
margin under the same pinned compiler settings (measured by `forge build --sizes`
during the implementation change; the exact final number is the one recorded in
`evidence/deterministic-build.json`).

## Consequences

- The candidate 2 proof inputs and receipts move byte-for-byte to
  `evidence/candidate-2/`; the successor lanes start from
  `evidence/current-profile-release-index-v3.json` under
  `evidence/evidence-mode.json`.
- The refinement ledger must map the abstract settlement and entitlement records
  onto the action record plus receipt projection rather than onto dedicated
  storage.

## Reopen when

- A profile needs a dedicated on-chain settlement or entitlement record view;
  it must then be added as a profile interface with its own identifier, never as
  a kernel function.
- The generated copy and the specification copy are ever allowed to differ.
