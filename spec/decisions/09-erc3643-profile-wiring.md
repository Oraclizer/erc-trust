# Decision 09: how the ERC-3643 Verified Full profile consumes the kernel machine source

Status: implemented for the profile adapter (`implementation/src/profiles/ERC3643TrustAdapter.sol`,
`implementation/src/profiles/ProfileGovernor.sol`). The formal mapping of the profile and the
runtime evidence for its bytecode follow in later changes.

## Decision

1. The adapter implements `IERCTrustKernel` from the same generated copy the native
   token consumes (`08-native-wiring.md`, item 1) and reports the kernel identifier
   `0x2b020308`. The kernel version 1 profile interface, its identifier `0xbcc2afa9`,
   the version 1 type library, the version 1 decision helpers, the standalone ERC-165
   file, and the version 1 error set are removed; no hand-written duplicate of a
   kernel type remains under `implementation/`.
2. The profile's dependencies are the sealed token runtime identity, the Identity
   Registry, and the Compliance contract. They feed the dependency root through the
   kernel formula with `POLICY` = Compliance, `IDENTITY` = Identity Registry, and
   zero for `SETTLEMENT` and `ENTITLEMENT`: the profile has no settlement or
   entitlement dependency, `LIQUIDATE` and `RECOVER` bind their commitments only,
   and the manifest of the profile says so here. Each per-kind binding uses the
   native `bindingHash` preimage with the dependency's runtime code hash at the
   seal, the sealed binding as the configuration digest, the profile identifier as
   the schema, and epoch 1. The sealed binding of the governor commits to the chain,
   the governor, the token, the expected token code hash, the adapter, both
   registries, and the import manifest hash, and is the `manifestHash` of the
   profile descriptor.
3. The reference governor seals exactly once and offers no reseal, Agent management,
   registry rebinding, or arbitrary-call surface, so the dependency epoch is 1 for
   the life of the conformance unit. A profile that offers a reseal MUST increment
   the epoch and change the root on every reseal, as the kernel requires.
4. Onboarding is a fresh zero-state seal or an exact import manifest, nothing else.
   The manifest lists every account that carries upstream frozen tokens or an
   address freeze at the seal, sorted by strictly increasing account, each entry
   declaring nonzero state; the empty manifest is the fresh zero-state declaration.
   The seal verifies every entry against the live upstream state and reverts with
   reason 303 on any difference, so a wrong manifest seals nothing. The adapter then
   owns the declared state: an imported frozen amount opens a `FREEZE` case and an
   imported address freeze opens a `RESTRICT` case, each with a synthetic applied
   head action that has no command hash and no receipt (`RegulatoryStateImported`
   names it). Declared legacy state is thereby reversible and amendable under the
   case transition table, and the kernel receipts of those later commands are
   ordinary receipts.
5. Every account a command acts on must carry exactly the upstream frozen amount and
   address freeze flag the adapter declared at the seal or applied itself; the
   adapter checks this before consuming the command and reverts with reason 304
   (`UPSTREAM_STATE_NOT_OWNED`, registered in class 300 next to the seal-time
   reason 303) otherwise. Upstream state it does not own is never overwritten and
   never silently adopted. After every forced transfer the adapter brings the
   frozen amount of both accounts back to their owned targets saturated at the
   current balance (an ERC-3643 forced transfer unfreezes automatically), verifies
   the post-state, and records the applied value.
   The owned target is materialised upstream only at the adapter's own touch
   points. An ordinary inbound transfer that raises an account's balance between
   two touches leaves the upstream frozen amount at the last applied value, so the
   growth is transferable until the next command that touches the account or a
   call to `resynchroniseFrozen(account)`, which any caller may make and which
   only ever raises the upstream frozen amount toward the owned target (it never
   unfreezes and it changes no owned state). The native token applies its stored
   target on every transfer; closing that window atomically on an ERC-3643 token
   would need a transfer hook inside the token or its Compliance, which this
   profile does not use.
6. Custody is confined to the adapter: `SEIZE` requires `custodian == destination ==
   adapter` (reason 6 otherwise), so seized tokens sit in the adapter's own
   upstream balance and the custody backing rule keeps other cases from spending
   them.
7. Assessment consults the Identity Registry for the destination and the Compliance
   policy for the transfer of every transfer command (`SEIZE`, `CONFISCATE`,
   `LIQUIDATE`, `RECOVER`, and `RELEASE`); `FREEZE`, `RESTRICT`, `UNFREEZE`, and
   `UNRESTRICT` consult nothing, because ERC-3643 freezes are Agent operations with
   no policy hook. A denial is `TrustRejected` with reason 101 (identity) or 100
   (policy); an unavailable, reverting, empty, oversized, or non-boolean response is
   `TrustOperationalFailure` with reason 402 or 403. `assessmentEvidence` is
   `keccak256(abi.encode(dependencyRoot, commandHash, consultedMask))` with bit 0 for
   the policy and bit 1 for the identity consultation.
8. Upstream execution is typed: a forced transfer that reverts or returns anything
   but a single true word is reason 400, a mismatch of either balance afterwards is
   reason 401, a freeze, unfreeze, or address-freeze call that reverts or returns
   data is 400, and a frozen amount or flag that does not match afterwards is 401.
   Upstream views are read with bounded static calls; a revert, a return of any
   length other than 32 bytes, or a flag word above 1 is reason 400.
9. `preState` and `postState` commit to the token, the subject's balance, owned
   frozen target, upstream frozen amount, and owned restriction flag, the source's
   and destination's balance and custody backing, the case's custody record, the
   subject's overlay heads, the case record, and the sealed binding.
10. The adapter has one immutable authority at epoch 1 and no authority rotation or
    governance write. `TrustAuthorityChanged` is emitted at construction and the
    four `TrustDependencyChanged` events (two of them with a zero binding) at the
    seal, so an indexer sees the same activation shape as for the native token.
11. Validation order, case transition table, replay detection, custody accounting,
    effect chains, and the receipt preimage are the native ones (`08-native-wiring.md`,
    items 5 to 10), with the topology check (reason 300 when the sealed topology no
    longer holds, reason 200 when a bound dependency's runtime code changed) placed
    where the native token assesses its dependencies: after the command is
    validated and before anything is consumed.
12. The profile surface `IERC3643VerifiedProfile` (its own ERC-165 identifier, not
    part of the kernel identifier, as decision 06 item 5 provides) exposes
    `ownedState(account)`, the owned frozen target, the applied upstream frozen
    amount, and the owned restriction flag, so that an indexer or keeper can see
    when a resynchronisation is due, and `resynchroniseFrozen(account)`, which
    requires the live topology and the ownership precondition of item 5 and then
    performs the same synchronisation a command would perform.

## Assumptions and deployment preconditions

- `expectedTokenCodeId` is declared by the deployer of the governor; the seal binds
  the declared value to the live token code and never audits the code itself. Any
  claim about the token's behaviour comes from the deployment evidence, not from
  the seal.
- The adapter is the custody destination of every `SEIZE`, so the Identity
  Registry must report the adapter as verified for the unit to execute seizures.
- The canonical form of the import manifest is enforced by the governor; the
  adapter recomputes the manifest hash only. The conformance unit is the governor
  together with its adapter, never the adapter alone.
- The underlying token moves or unfreezes tokens only through its Agent surface
  and the adapter is its only Agent; a token that changes frozen state through
  another role cannot satisfy the ownership precondition.

## Why

The shipped version 1 adapter implemented a different interface than the native
token, hashed a different receipt preimage, and started every subject's frozen
target at zero: its first forced transfer resynchronised the upstream frozen amount
to that zero target and silently overwrote whatever the token had frozen before the
seal. It also read the address freeze flag live from the token, so a flag set
before the seal was reported as a prior state the adapter had never owned.

Kernel version 2 requires one interface, one command format, one receipt format,
and one discovery shape for both profiles, and the profile description requires
that any initial state other than a declared one be Partial or Unsupported. The
exact import manifest turns the initial state into a verified declaration, the
ownership check turns every later touch of upstream state into a verified
precondition, and the imported cases make declared legacy state reversible by the
same typed commands that govern everything else.

Confining custody to the adapter keeps seized tokens under the only Agent the
token has. Any other custodian would need its own Agent power to release them.

## Alternatives considered

- Adopt upstream state on first touch as an implicit baseline. Rejected: that is
  the version 1 behaviour with a different sign, still silent, still unverified.
- Import declared state as a baseline without a case. Rejected: a baseline with no
  live head could never be lifted, because `UNFREEZE` restores the prior target and
  `FREEZE` only raises it.
- Give the governor a reseal or rebinding surface with epoch increments. Rejected
  for the reference: it would reopen the Agent and registry topology that the seal
  exists to freeze, and no consumer needs it. The kernel rule for reseals stays
  normative for profiles that offer one.
- Consult the Compliance policy for overlay commands too. Rejected: ERC-3643 freezes
  have no policy hook and `canTransfer` has no meaning for them; the evidence mask
  records that nothing was consulted.

## Consequences

- The adapter runtime is measured by `forge build --sizes` in continuous
  integration; its runtime identity is not yet bound by the deterministic-build
  receipt or the release manifest, which record the native token only. The
  runtime assurance change binds both endpoints.
- An absolute frozen target above the current balance is enforced by the
  underlying token only up to the balance at the adapter's last touch (item 5).
  This is a property of adapting a frozen amount to a frozen target, not a
  defect of one implementation, and it is stated in the profile's limitations.
- The refinement ledger must map the abstract initial state onto the import
  manifest and the imported cases, and the abstract authorization onto the single
  immutable authority.
- The kernel vectors reproduce on the adapter runtime placed at the fixture
  endpoint, since identifiers depend only on the endpoint address, the chain, and
  the request.

## Reopen when

- An integrator needs a reseal, a registry rebinding, or an authority rotation on
  a sealed unit; that profile must then define its epoch increments and its
  evidence reopening.
- A deployment needs a custodian other than the adapter; the custody backing rule
  and the Agent topology must then be redesigned together.
- An upstream token unfreezes or moves tokens outside its Agent surface (for
  example on recovery or on burn by another role); such a token cannot satisfy the
  ownership precondition and is Partial or Unsupported.
