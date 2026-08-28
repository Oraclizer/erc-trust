# ERC-TRUST semantic alignment decision

Status: approved design boundary; implementation and proof pending

Baseline: `b3cf2ccc385f4afa1a4a9e1d645d568a698d67e3`

This decision defines the refinement target for the native ERC-TRUST
reference and the sealed ERC-3643 profile fixture. It does not change the
claim boundary for legal, identity, policy, settlement, entitlement, or
ownership truth. It does not bind a deployed address, chain, live dependency,
or operating environment.

## 1. Refinement architecture

The refinement chain has two separately proved links:

1. the concrete TRUST transaction semantics refines the compositional
   abstract TRUST transition through a retrieve relation; and
2. the pinned compiled EVM runtime implements the concrete TRUST transaction
   semantics.

The composed theorem may be called end-to-end refinement only when both links
cover all six actions, all three reversals, every declared failure class, the
external-call contracts, complete protocol storage frames, and committed log
order. A source-level helper proof, a selected runtime path, or a standalone
executable model is not the composed theorem.

Deployment-address, chain, live-code, and live-topology binding remain outside
this package.

## 2. Compositional abstract state

The refinement target separates:

- the ERC-20 physical ledger;
- an absolute frozen target and a restriction flag for each subject;
- case-scoped lifecycle and terminality;
- action and reversal lifecycle;
- custody, declared prior holder, and custody backing;
- authority-reference-specific authority, delegation, and epoch state;
- consumed `(authorityRef, authorityEpoch, nonce)` keys;
- binding-kind-specific dependency identity and policy epoch; and
- current receipt commitments.

Freeze and restriction are independent overlays and may coexist. A subject is
not made globally terminal by a disposition in one case. Irreversible
disposition and successful reversal close the affected case, while unrelated
cases remain framed.

The pre-existing single-mode foundation model remains a compatibility
projection over states that satisfy an explicit `foundation_coherent`
predicate. It is not used to erase composite overlays, multiple cases, or
partial-balance dispositions.

## 3. Concrete configuration and retrieve relation

A concrete configuration contains:

- the EVM world and pinned endpoint runtime;
- the native or sealed-profile topology;
- transaction sender, value, time, chain context, and raw calldata;
- an execution phase;
- relevant external-call inputs and returndata;
- the current committed log sequence; and
- a finite footprint of addresses, cases, commands, authorities, bindings,
  and storage keys with a completeness predicate.

Execution phases are `Idle`, `Dispatch`, `Authorized`, `Assessed`,
`EffectsApplied`, `Returned`, and `Reverted`.

The retrieve relation is partial on arbitrary EVM worlds and total on
configurations satisfying the pinned-runtime, storage-layout, footprint,
nonalias, topology, and state-invariant premises. A failed premise yields no
abstract state; it is not hidden behind a default value.

Current-state abstraction, single-transaction execution refinement, and
committed historical trace refinement are distinct relations:

- current-state abstraction reads only current persistent state and exact
  runtime/layout metadata;
- transaction refinement additionally reads the current transaction frame,
  raw calldata, calls, result, and committed logs;
- historical trace refinement takes an explicit committed-history witness and
  validates it against stored hashes and logs.

Historical calldata is never injected into current-state abstraction as a
hidden oracle. Without the explicit history witness, historical receipt
preimage reconstruction is a nonclaim.

## 4. Physical, beneficial, and custody-backed units

For a finite complete custody footprint:

```text
custodyBacking(a) =
  sum of active custody amounts whose custodian is a

beneficialBalance(a) =
  physicalBalance(a)
  + active custody amounts whose declared prior holder is a
  - custodyBacking(a)
```

The base invariant is:

```text
physicalBalance(a) >= custodyBacking(a)
```

Custody backing secures a third party's declared beneficial entitlement.
The custodian's own frozen target applies only to physical units remaining
after custody backing:

```text
ownPhysical(a) =
  physicalBalance(a) - custodyBacking(a)

ownFrozenFloor(a) =
  min(frozenTarget(a), ownPhysical(a))

requiredFloor(a) =
  custodyBacking(a) + ownFrozenFloor(a)

ordinaryAvailable(a) =
  physicalBalance(a) - requiredFloor(a)
```

This is an additive, non-double-counting rule. One physical token unit cannot
simultaneously discharge a third party's custody backing and the custodian's
own frozen obligation. The absolute frozen target remains unbounded by the
current balance; saturation affects only the currently enforceable floor.

An enforcement transfer may bypass the source's own frozen floor when its
typed action permits that exception, but it may not consume custody backing
belonging to another case.

## 5. Exact action quantities and path split

Every successful action moves or sets exactly the canonical command amount.
No successful outcome may perform only part of the authorized command.

Partial confiscation means only that the canonical command amount may be less
than the subject's total balance. It does not mean partial execution of that
command.

CONFISCATE, LIQUIDATE, and RECOVER have two disjoint paths:

- direct: no active custody for the case, `source = subject`, and the exact
  command amount is available without consuming unrelated custody backing;
- custody disposition: the current custody head, custodian, declared prior
  holder, case, and amount all match, and the entire active custody record is
  consumed atomically.

Case terminality is written only after the exact command effect and all
required external guarantees succeed.

For the sealed ERC-3643 fixture, SEIZE custody is confined to the adapter
itself unless a separately bound immutable custody-vault profile is specified
and verified. An arbitrary externally controlled custodian is not a full
custody guarantee.

## 6. Absolute freeze and provenance-safe reversal

FREEZE replaces the absolute frozen target. It is neither a delta nor a
balance-bounded increment. Each successful FREEZE records:

- the prior absolute target;
- the new absolute target;
- the parent effect action ID;
- a monotonic effect generation;
- the current effect head action ID; and
- an effect hash binding the endpoint, subject, action ID, parent action ID,
  generation, prior target, and new target.

Reversible freeze and restriction overlays use explicit LIFO provenance.
Custody uses the same head, generation, parent, and effect-hash discipline per
case.

A reversal is permitted only when:

- the referenced original action is applied and not already reversed;
- the current effect head action ID identifies that action as the top reversible
  effect;
- the stored generation and effect hash validate the head relation;
- the parent/predecessor relation is valid; and
- action-specific current state and custody fields match.

Value equality alone is never sufficient. A successful reversal pops the
effect head to its predecessor, advances the monotonic generation, records a
new effect hash for the pop, consumes its own command ID and nonce, and marks
the original action reversed.

Superseded, ABA, duplicate, and out-of-order reversals must fail with
persistent-state and committed-log stutter.

## 7. ABI and failure taxonomy

The canonical input is the exact selector plus the exact static tuple
encoding. Trailing bytes are malformed. Short input, invalid enum or high
bits, and invalid offset or length encodings are malformed and must revert
without persistent protocol state or committed logs.

Generic Solidity dispatcher or decoder reverts are classified as malformed
input, not as typed TRUST operational failures.

Untrusted dependency return data uses strict word decoding:

- canonical semantic denial maps to `TrustRejected`;
- dependency revert maps to `TrustOperationalFailure`;
- short, long, noncanonical, or echo-mismatched return data maps to
  `TrustOperationalFailure`; and
- all rejected, operational-failure, and malformed-input paths preserve the
  declared persistent observation and commit no logs.

## 8. Event and receipt observation

The committed native success traces are:

- FREEZE: `Frozen`, then `RegulatoryActionApplied`;
- RESTRICT: `RegulatoryActionApplied`;
- SEIZE, CONFISCATE, LIQUIDATE, and RECOVER: `Transfer`,
  `ForcedTransfer`, then `RegulatoryActionApplied`;
- UNFREEZE: `Frozen`, then `RegulatoryReversalApplied`;
- UNRESTRICT: `RegulatoryReversalApplied`; and
- RELEASE: `Transfer`, `ForcedTransfer`, then
  `RegulatoryReversalApplied`.

The canonical regulatory receipt event is final. The sealed profile relation
also includes the exact bound underlying-token event prefix. A reverted
transaction commits no effect or receipt log.

## 9. Runtime and deployment boundary

The strongest runtime subject in this package is a pinned compiled artifact:

```text
abstract TRUST transition
  -> concrete TRUST configuration/retrieve relation
  -> pinned compiled EVM runtime execution
```

Constructor-resolved local runtime bytes and their expected code hashes may be
bound as artifacts. Actual deployed runtime, address, chain, live dependency
code/configuration, and operational topology require separate
deployment-bound assurance.

## 10. Hard stops

Implementation and proof must stop rather than weaken this decision when:

- LIFO provenance does not close ABA or out-of-order reversal;
- additive custody/freeze non-double-counting cannot be maintained;
- dependency licensing prevents the selected runtime-semantics path;
- EIP-170 size cannot be recovered by semantics-preserving optimization; or
- the exact runtime theorem requires an admitted, oracle, or trusted shortcut.
