---
title: Typed Regulatory Actions for Security Tokens
description: Typed regulatory actions, reversals, cases, dependency binding, outcomes, and recomputable receipts for fungible security tokens.
author: Jinwook Kim (@jay-oraclizer)
discussions-to: <to be added after the public discussion is opened>
status: Draft
type: Standards Track
category: ERC
created: 2026-09-02
requires: 20, 165, 7943, 8319
---

## Abstract

This proposal defines an ERC-165 discoverable kernel interface for fungible
security tokens that executes six typed regulatory actions and three explicit
reversals. A command binds its regulatory meaning, authority and authority
epoch, case, the current root of the endpoint's external dependencies,
provenance and action-specific commitments, replay protection, and a
validity period. Successful execution records one recomputable receipt after
the required token effects and emits it as the final event of the command.
Policy rejection and operational dependency failure are represented by
distinct errors and leave no persistent state change.

The kernel builds on ERC-20 and the fungible ERC-7943 interface. ERC-7943
provides neutral freeze and forced-transfer mechanics; this proposal adds the
typed action identity, case lifecycle, authorization, terminality,
dependency binding, and receipt semantics needed to distinguish legally
different uses of those mechanics. It neither confers regulatory authority
nor establishes the truth of any external legal, identity, policy,
settlement, proceeds, or entitlement claim.

## Motivation

Fungible security-token implementations commonly expose privileged mechanics
such as changing a frozen balance or forcing a transfer. Those mechanics do
not identify why the operation occurred. The same transfer primitive can be
used for custody seizure, permanent confiscation, liquidation, or recovery,
although those actions differ in reversibility, ownership effect, finality,
required evidence, and permitted follow-up operations.

Function names and ordinary token events are therefore insufficient for
interoperable monitoring. An indexer cannot reliably infer a regulatory action
from a generic privileged transfer. A relayer cannot determine whether an
authorization was already consumed or whether the policy it was prepared
under is still the current one. An auditor cannot distinguish a rejected
policy decision from an unavailable dependency. A downstream application
cannot recompute a regulatory receipt if each implementation chooses different
fields and ordering.

This proposal supplies a common execution layer for those distinctions. It
does not standardize jurisdiction-specific policy, identity systems, legal
evidence formats, or who may exercise regulatory power. Implementations bind
those external decisions while preserving a shared onchain command, case, and
receipt model.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT",
"SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and
"OPTIONAL" in this document are to be interpreted as described in RFC 2119
and RFC 8174.

### Scope and dependencies

A native conforming token MUST implement [ERC-20](./eip-20.md),
[ERC-165](./eip-165.md), and the fungible interface of
[ERC-7943](./eip-7943.md). The action meanings in this proposal depend on
[ERC-8319](./eip-8319.md). An implementation MUST NOT use an action name for
an operation whose reversibility, ownership effect, or finality conflicts with
the corresponding ERC-8319 meaning.

This version is limited to fungible tokens. Non-fungible and multi-token
profiles require separate interfaces and are outside this proposal.

The kernel defined here is version 2 of the wire format. Every constant,
identifier, and calldata layout below is normative; a machine-readable
rendering of the same definitions accompanies the reference implementation
and the conformance vectors.

### Types

The following Solidity declarations define the canonical ABI types. Enum
values are part of the ABI and MUST NOT be reordered. Struct fields encode,
hash, and appear in calldata in the order listed.

```solidity
library TrustKernelTypes {
    /// keccak256("ERC-TRUST/v2")
    bytes32 internal constant DOMAIN = 0xb5303e4083d2781d6c7d6a68d30b6354ebda11f0a2a037b946d87b3eec40b74e;
    uint8 internal constant STANDARD_VERSION = 2;
    /// keccak256("ERC-TRUST/v2/dependency-root")
    bytes32 internal constant DEPENDENCY_ROOT_TAG = 0x8dd0ff19b096a49997e6e0fa1eea2dee5d61291bb86d3d10640e517c9e6cbe18;
    /// keccak256("ERC-TRUST/v2/native-full")
    bytes32 internal constant PROFILE_NATIVE_FULL = 0x86ba25e1a29a74ad905fd84744be032fec9dc05645f58f7f1b7788dc60ae866b;
    /// keccak256("ERC-TRUST/v2/erc3643-verified-full")
    bytes32 internal constant PROFILE_ERC3643_VERIFIED_FULL = 0xad56e54f83cc255e391dd3838f7dc4befa1b0306b42d8ed7974588f27fec41ad;

    enum ActionKind { FREEZE, SEIZE, CONFISCATE, LIQUIDATE, RESTRICT, RECOVER }
    enum ReversalKind { UNFREEZE, RELEASE, UNRESTRICT }
    enum ReceiptKind { NONE, ACTION, REVERSAL }
    enum BindingKind { POLICY, IDENTITY, SETTLEMENT, ENTITLEMENT }
    enum AssessmentOutcome { APPLICABLE, REJECTED, OPERATIONAL_FAILURE }
    enum Lifecycle { NONE, PREPARED, APPLIED, REVERSED }
    enum ProfileKind { UNSUPPORTED, NATIVE_FULL, VERIFIED_FULL, PARTIAL }
    enum CasePhase { NONE, OPEN, TERMINAL }
    enum CaseFamily { NONE, FREEZE, RESTRICT, CUSTODY, DISPOSITION }

    /// Typed action command: 20 static words, 644 calldata bytes for a single-parameter call.
    struct ActionRequest {
        bytes32 domain;
        bytes32 actionId;
        ActionKind action;
        address subject;
        address source;
        address destination;
        address custodian;
        uint256 amount;
        bytes32 caseId;
        bytes32 dependencyRoot;
        uint64 dependencyEpoch;
        bytes32 provenanceCommitment;
        bytes32 settlementCommitment;
        bytes32 proceedsCommitment;
        bytes32 entitlementCommitment;
        bytes32 authorityRef;
        uint64 authorityEpoch;
        uint256 nonce;
        uint48 validAfter;
        uint48 validBefore;
    }

    /// Typed reversal command: 12 static words, 388 calldata bytes.
    struct ReversalRequest {
        bytes32 domain;
        bytes32 reversalId;
        bytes32 actionId;
        ReversalKind reversal;
        bytes32 dependencyRoot;
        uint64 dependencyEpoch;
        bytes32 provenanceCommitment;
        bytes32 authorityRef;
        uint64 authorityEpoch;
        uint256 nonce;
        uint48 validAfter;
        uint48 validBefore;
    }

    /// Stored and returned by receipt(commandId). Every field except receiptHash is a
    /// preimage input, in this order, prefixed by DOMAIN.
    struct Receipt {
        ReceiptKind receiptKind;
        bytes32 commandId;
        uint8 commandKind;
        bytes32 parentCommandId;
        address subject;
        address source;
        address destination;
        uint256 amount;
        bytes32 caseId;
        bytes32 authorityRef;
        bytes32 dependencyRoot;
        bytes32 provenanceCommitment;
        bytes32 assessmentEvidence;
        bytes32 preState;
        bytes32 postState;
        bytes32 externalCommitment;
        bytes32 receiptHash;
    }

    /// Returned by actionRecord(actionId). An implementation record, not a hash preimage.
    struct ActionRecord {
        ActionKind action;
        Lifecycle lifecycle;
        address subject;
        address source;
        address destination;
        address custodian;
        uint256 amount;
        uint256 priorAmount;
        bool priorFlag;
        bytes32 caseId;
        bytes32 authorityRef;
        uint64 authorityEpoch;
        uint64 dependencyEpoch;
        bytes32 commandHash;
        bytes32 evidenceHash;
        bytes32 receiptHash;
    }

    /// Returned by caseRecord(caseId).
    struct CaseRecord {
        CasePhase phase;
        CaseFamily family;
        bytes32 headActionId;
        uint64 generation;
    }

    /// Returned by trustProfile(). A declaration about the endpoint, not proof of conformance.
    struct ProfileDescriptor {
        bytes32 profileId;
        ProfileKind profileKind;
        uint8 standardVersion;
        uint256 actionMask;
        uint256 reversalMask;
        address underlyingToken;
        bytes32 manifestHash;
        bool full;
        bool proxySupported;
    }
}
```

`subject` identifies the regulatory subject. `source` identifies the account
whose balance is debited by a transfer action. `destination` identifies the
account credited by a disposition. `custodian` is used only by `SEIZE`.
`caseId` names the case the command belongs to; a case groups one regulatory
matter's actions, its live effect, its custody, and its terminality.

`dependencyRoot` and `dependencyEpoch` bind the command to the endpoint's
current external dependencies (see "Dependency root and epoch"). Commitment
fields bind external records without asserting that those records are true.
A conforming implementation MUST document the encoding and hash function used
to produce each commitment.

`Lifecycle.PREPARED` is reserved for implementations that stage a command
before applying it; the kernel defines no onchain cancellation, so no
lifecycle value for a cancelled command exists.

### Interface

```solidity
interface IERCTrustKernel is IERC165 {
    event RegulatoryActionApplied(bytes32 indexed actionId, uint8 indexed action, bytes32 indexed caseId, bytes32 receiptHash);
    event RegulatoryReversalApplied(bytes32 indexed reversalId, uint8 indexed reversal, bytes32 indexed actionId, bytes32 receiptHash);
    event TrustDependencyChanged(uint8 indexed kind, bytes32 indexed previousBinding, bytes32 indexed currentBinding, bytes32 dependencyRoot, uint64 dependencyEpoch);
    event TrustAuthorityChanged(bytes32 indexed authorityRef, address indexed account, uint64 epoch, bool active);

    error TrustRejected(bytes32 commandId, uint16 reason);
    error TrustOperationalFailure(bytes32 commandId, uint16 reason, bytes32 dependencyRef);
    error TrustUnauthorized(address caller, bytes32 authorityRef);
    error TrustReplay(bytes32 key);
    error TrustInvalidCommand(bytes32 commandId, uint16 reason);
    error TrustTerminal(bytes32 caseId);

    function executeRegulatoryAction(TrustKernelTypes.ActionRequest calldata request) external returns (bytes32 receiptHash);
    function executeRegulatoryReversal(TrustKernelTypes.ReversalRequest calldata request) external returns (bytes32 receiptHash);
    function deriveActionId(TrustKernelTypes.ActionRequest calldata request) external view returns (bytes32 actionId);
    function deriveReversalId(TrustKernelTypes.ReversalRequest calldata request) external view returns (bytes32 reversalId);
    function actionRecord(bytes32 actionId) external view returns (TrustKernelTypes.ActionRecord memory record);
    function receipt(bytes32 commandId) external view returns (TrustKernelTypes.Receipt memory record);
    function caseRecord(bytes32 caseId) external view returns (TrustKernelTypes.CaseRecord memory record);
    function dependencyState() external view returns (bytes32 dependencyRoot, uint64 dependencyEpoch);
    function trustProfile() external view returns (TrustKernelTypes.ProfileDescriptor memory descriptor);
}
```

The ERC-165 identifier of `IERCTrustKernel` is the exclusive OR of the
selectors of the nine functions above, excluding the inherited
`supportsInterface` selector: `0x2b020308`. A contract claiming conformance
MUST return `true` from `supportsInterface(0x2b020308)`. It MUST return
`false` for `0xffffffff` and for every interface it does not implement
completely.

Two profile interfaces accompany the kernel and are identified separately:

```solidity
/// Native profile only: same-transaction exact-use route for the sensitive ERC-7943 selectors.
interface IERCTrustNativeRoute {
    error TrustRouteMismatch(bytes32 routeKey);
    function executeERC7943Action(TrustKernelTypes.ActionRequest calldata request) external returns (bytes32 receiptHash);
    function executeERC7943Reversal(TrustKernelTypes.ReversalRequest calldata request) external returns (bytes32 receiptHash);
}

/// Native profile dependency boundary. Read-only.
interface ITrustBoundDependency {
    function configurationDigest() external view returns (bytes32 digest);
    function assess(bytes32 commandHash, uint8 operation, address subject, address destination, uint256 amount, bytes32 bindingHash, uint64 bindingEpoch) external view returns (uint8 outcome, bytes32 evidence, bytes32 commandEcho, bytes32 bindingEcho);
}
```

Their identifiers are computed by the same rule: `0x5cd8d207` for
`IERCTrustNativeRoute` and `0xb2306fd2` for `ITrustBoundDependency`.

Every typed command function MUST accept only calldata of the exact canonical
length (644 bytes for an action, 388 bytes for a reversal) and MUST reject a
request whose enum, address, `uint64`, or `uint48` fields carry bits outside
their declared width. A rejected shell of this kind reverts without a typed
error and without any state change.

### Domain and identifiers

`DOMAIN` is `keccak256("ERC-TRUST/v2")`. Every hash defined by this proposal
is `keccak256` of the ABI encoding (`abi.encode`) of the listed items in
order. A struct encodes as the static tuple of its fields in the order
declared above; every item occupies one 32-byte word, addresses and narrow
integers are left-padded with zero bytes, and enums are their `uint8` value.

| Identifier | Preimage, in order |
| --- | --- |
| `actionId` | `DOMAIN`, endpoint address, chain id, `ActionRequest` with `actionId = 0` |
| `commandHash` | `DOMAIN`, endpoint address, chain id, the completed `ActionRequest` |
| `reversalId` | `DOMAIN`, endpoint address, chain id, `ReversalRequest` with `reversalId = 0` |
| `reversalHash` | `DOMAIN`, endpoint address, chain id, the completed `ReversalRequest` |
| `nonceKey` | `DOMAIN`, `authorityRef`, `authorityEpoch`, `nonce` |
| `receiptHash` | `DOMAIN`, then the first sixteen fields of `Receipt` in declared order |

The `actionId` field of a request MUST equal the derived value; the same
holds for `reversalId`. `deriveActionId` and `deriveReversalId` MUST return
exactly these derivations for any well-formed request, so a caller can
complete a request offchain and confirm it against the endpoint. Because the
endpoint address and the chain id are part of every preimage, a request
built for one endpoint is invalid on every other endpoint.

`commandHash` and `reversalHash` are the digests an endpoint passes to its
bound dependencies and stores in the action record. They differ from the
identifiers only in that the identifier field is filled.

### Authorization, epochs, and replay

`authorityRef` names an authority; the endpoint maintains, for each
reference, the account currently registered for it and an authority epoch
that increases on every rotation. The caller of a typed command MUST be the
account currently registered for the request's `authorityRef`; otherwise the
endpoint MUST revert with `TrustUnauthorized`. The request's
`authorityEpoch` MUST equal the current epoch of that authority (reason 4).
Every change of the registered account or of the epoch MUST emit
`TrustAuthorityChanged`. The kernel defines no delegation surface: whoever is
registered is the authority, and a registered account MAY be a contract that
implements any delegation or multi-signature policy the deployment wants.

Two replay keys exist. A command identifier is exactly-once: a request whose
`actionId` or `reversalId` was already applied MUST revert with
`TrustReplay(commandId)`. The tuple `(authorityRef, authorityEpoch, nonce)`
is exactly-once: reusing it MUST revert with `TrustReplay(nonceKey)`. A
rejected or failed command consumes neither key.

`validAfter` and `validBefore` bound the command by `block.timestamp`;
`validBefore` MUST be nonzero and the window MUST contain the current
timestamp (reason 3).

### Validation order and shape rules

An endpoint MUST validate a request in the following order and MUST report
the first failure it meets, so a request with several defects reports the
earliest one.

1. `domain == DOMAIN` (`TrustInvalidCommand`, reason 1).
2. The identifier equals its derivation (reason 2).
3. The command identifier was not already applied (`TrustReplay`).
4. The validity window (reason 3).
5. The authority epoch (reason 4) and the registered account
   (`TrustUnauthorized`).
6. `dependencyRoot` and `dependencyEpoch` equal the endpoint's current pair
   (reason 5).
7. The nonce tuple was not already consumed (`TrustReplay`).
8. The field rules of the command (reason 6 unless a rule names its own
   code).
9. The state-dependent rules: case phase (`TrustTerminal`), reversal pairing
   (reason 7), custody (reason 8), entitlement consumption (reason 9), case
   conflict (reason 10), current effect (reason 11), freeze direction
   (reason 12), and no state change (reason 13).

A replayed or stale command is therefore reported before any rule that
depends on case or effect state. Assessment of the bound dependencies happens
after validation and before any state is consumed.

The field rules are:

| Command | Rule |
| --- | --- |
| every action | `provenanceCommitment != 0`, `subject != 0`, `caseId != 0` |
| `FREEZE` | `source == subject`; `destination == 0`; `custodian == 0`; `amount` strictly greater than the subject's current absolute frozen target (reason 12 otherwise); settlement, proceeds, and entitlement commitments zero |
| `RESTRICT` | `source == subject`; `destination == 0`; `custodian == 0`; `amount == 0`; the three commitments zero |
| `SEIZE` | `source == subject`; `custodian != 0`; `destination == custodian`; `amount > 0` and available without consuming custody backing of another case (reason 8); the three commitments zero |
| `CONFISCATE` | `source != 0`; `destination != 0` and `destination != source`; `custodian == 0`; `amount > 0`; on the direct path `source == subject` and the amount available without consuming custody backing of another case (reason 8); on the custody disposition path `source == custodian`, `subject` equal to the declared prior holder, and `amount` equal to the encumbered amount; the three commitments zero |
| `LIQUIDATE` | as `CONFISCATE`, except `settlementCommitment != 0` and `proceedsCommitment != 0` |
| `RECOVER` | as `CONFISCATE`, except `entitlementCommitment != 0` (reason 6 when zero) and not previously consumed by an applied `RECOVER` (reason 9) |
| every reversal | `provenanceCommitment != 0`; the reversal kind pairs with the referenced action (`UNFREEZE` with an applied `FREEZE`, `RELEASE` with an applied `SEIZE`, `UNRESTRICT` with an applied `RESTRICT`; reason 7); the referenced action is the subject's live head for its overlay family, or the case's active custody for `RELEASE` (reason 11, or reason 8 when the custody record does not match) |

A rule that names a field applies only to requests that have that field. An
implementation MAY add reason codes inside a class but MUST NOT reuse a
listed code with a different meaning.

### Outcomes and full-state stutter

Assessment of a validated command has exactly one of three outcomes:

- `APPLICABLE`: every bound check completed and permits execution;
- `REJECTED`: the checks completed and deny the command; the endpoint MUST
  revert with `TrustRejected` and a reason in class 100;
- `OPERATIONAL_FAILURE`: a required dependency or upstream call was
  unavailable, malformed, stale, or inconsistent; the endpoint MUST revert
  with `TrustOperationalFailure` and a reason in class 200, 300, or 400.

Every revert defined by this proposal, including validation failures,
`TrustTerminal`, and `TrustReplay`, is a *full-state stutter*: the call
leaves every observable state of the endpoint exactly as it was before the
call. No command identifier or nonce is consumed, no case, action, or
receipt record is written, no token balance, frozen amount, or restriction
flag changes, and no log is emitted. A reader who observes an applied event
therefore knows that every earlier check of that command passed.

The reason classes are:

| Class | Range | Error | Listed codes |
| ---: | --- | --- | --- |
| 1 | 1 to 99 | `TrustInvalidCommand` | 1 domain, 2 identifier, 3 time, 4 authority epoch, 5 dependency binding, 6 shape, 7 reversal pairing, 8 custody, 9 entitlement, 10 case conflict, 11 current effect, 12 freeze direction, 13 no state change |
| 100 | 100 to 199 | `TrustRejected` | 100 policy denied, 101 identity denied, 102 settlement denied, 103 entitlement denied |
| 200 | 200 to 299 | `TrustOperationalFailure` | 200 dependency code mismatch, 201 dependency configuration mismatch, 202 dependency call failed or malformed, 203 dependency echo mismatch, 204 dependency reported failure, 205 dependency unavailable at bind |
| 300 | 300 to 399 | `TrustOperationalFailure` | 300 topology not full, 301 seal invalid, 302 topology mismatch at seal, 303 import manifest mismatch, 304 upstream state not owned |
| 400 | 400 to 499 | `TrustOperationalFailure` | 400 upstream call failed, 401 upstream post-state mismatch, 402 identity registry unavailable, 403 compliance unavailable |

### Actions, cases, and transitions

A case is opened by its first applied command and is bound to that command's
family for its whole life. Four families exist:

| Family | Opening commands | Kind | Reversal | Dispositions inside the case |
| --- | --- | --- | --- | --- |
| `FREEZE` | `FREEZE` | overlay | `UNFREEZE` | none |
| `RESTRICT` | `RESTRICT` | overlay | `UNRESTRICT` | none |
| `CUSTODY` | `SEIZE` | custody | `RELEASE` | `CONFISCATE`, `LIQUIDATE`, `RECOVER` |
| `DISPOSITION` | `CONFISCATE`, `LIQUIDATE`, `RECOVER` | terminal | none | none |

An overlay is a live effect on a subject that a later reversal removes. A
subject has at most one live head per overlay family across all cases; the
head is the most recently applied overlay action that is still in force, and
each amendment records its parent so that reversals pop in order. A custody
case holds at most one custody record. A disposition is terminal.

The required token effects are:

| Action | Effect |
| --- | --- |
| `FREEZE` | set the subject's absolute frozen target to `amount`; the prior target is recorded |
| `RESTRICT` | disable the subject's ordinary sends and receives; the prior flag is recorded |
| `SEIZE` | move `amount` from the subject to the custodian and open a custody record naming the custodian, the subject as declared prior holder, and the encumbered amount |
| `CONFISCATE` | move `amount` from `source` to `destination`; terminal |
| `LIQUIDATE` | as `CONFISCATE`, binding settlement and proceeds commitments; terminal |
| `RECOVER` | as `CONFISCATE`, binding an entitlement commitment that is consumed exactly once; terminal |

Tokens held under a custody record are *custody backing* of the custodian's
balance: the custodian cannot spend them by ordinary transfer, and no other
case may consume them (reason 8). The custody disposition path of a
disposition consumes the whole record of its own case.

The case transition table is normative. `OPEN(F)` is an open case of family
`F`; `TERMINAL` is a case that accepts no further command.

| Rule | From | Command | Guard | To | Effect or reason |
| --- | --- | --- | --- | --- | --- |
| CT-1 | `NONE` | `FREEZE` | subject has no live `FREEZE` head | `OPEN(FREEZE)` | push effect head (no parent) |
| CT-2 | `OPEN(FREEZE)` | `FREEZE` | the subject's live `FREEZE` head belongs to this case and `amount` exceeds the current target (reason 12 otherwise) | `OPEN(FREEZE)` | push amendment head (parent = previous head) |
| CT-3 | `NONE`, or `OPEN` of another case | `FREEZE` | the subject's live `FREEZE` head belongs to a different open case | reject | reason 10 |
| CT-4 | `OPEN(FREEZE)` | `UNFREEZE` of the head | the referenced action is the live head (reason 11 otherwise) | `OPEN(FREEZE)` if the popped head has a parent in this case, else `TERMINAL` | restore the prior target, pop the head |
| CT-5 | `NONE` | `RESTRICT` | subject has no live `RESTRICT` head | `OPEN(RESTRICT)` | push effect head |
| CT-6 | `OPEN(RESTRICT)` | `RESTRICT` | | reject | reason 13 |
| CT-7 | `NONE`, or `OPEN` of another case | `RESTRICT` | the subject's live `RESTRICT` head belongs to a different open case | reject | reason 10 |
| CT-8 | `OPEN(RESTRICT)` | `UNRESTRICT` of the head | the referenced action is the live head (reason 11 otherwise) | `TERMINAL` | restore the prior flag, pop the head |
| CT-9 | `NONE` | `SEIZE` | | `OPEN(CUSTODY)` | open the custody record |
| CT-10 | `OPEN(CUSTODY)` | `SEIZE` | | reject | reason 8 |
| CT-11 | `OPEN(CUSTODY)` | `RELEASE` | the referenced `SEIZE` is the case's active custody (reason 11, or 8) | `TERMINAL` | return the encumbered amount to the declared prior holder, close custody |
| CT-12 | `OPEN(CUSTODY)` | `CONFISCATE`, `LIQUIDATE`, or `RECOVER` (custody disposition) | `source == custodian`, `subject` is the declared prior holder, `amount` equals the encumbered amount (reason 8 otherwise) | `TERMINAL` | consume the whole custody record |
| CT-13 | `NONE` | `CONFISCATE`, `LIQUIDATE`, or `RECOVER` (direct) | `source == subject` and the case has no prior command | `TERMINAL` | move the amount |
| CT-14 | `OPEN(FREEZE)` or `OPEN(RESTRICT)` | any command of another family | | reject | reason 10 |
| CT-15 | `TERMINAL` | any action or reversal | | reject | `TrustTerminal` |
| CT-16 | `OPEN(CUSTODY)` | `FREEZE` or `RESTRICT` | | reject | reason 10 |

Two cross-case rules follow from the table. A disposition in one case does
not clear an overlay owned by another case: the overlay remains live, and the
frozen target it imposes saturates at the current balance when observed. And
custody records are per case, so several custody cases MAY encumber the same
source, each with its own backing.

`caseRecord(caseId)` returns the phase, the family, the head action of an
open overlay case, and a generation counter that advances with every command
applied to the case. The case record does not state how a terminal custody
case ended; whether it was closed by `RELEASE` or by a disposition is read
from the receipts and action records of the case.

### Reversals

A reversal references an applied action by `actionId` and MUST satisfy the
pairing and current-effect rules above. Its effects are:

| Reversal | Effect |
| --- | --- |
| `UNFREEZE` | restore the subject's frozen target to the value recorded before the referenced `FREEZE`, and pop that head; the case stays open while an earlier head of the same case remains |
| `UNRESTRICT` | restore the restriction flag recorded before the referenced `RESTRICT`, pop that head, and close the case |
| `RELEASE` | move the encumbered amount from the custodian back to the declared prior holder and close the custody record and the case |

An applied action's lifecycle becomes `REVERSED`; a reversed action cannot be
reversed again, and a reversal identifier is exactly-once like any command.
`LIQUIDATE`, `CONFISCATE`, and `RECOVER` have no reversal: a later transfer
that happens to return tokens is an ordinary transfer or a new action, never
an implicit reversal.

### Receipts

After applying a command, and after every required ERC-20 and ERC-7943 effect
event, the endpoint MUST store a `Receipt` under the command identifier and
emit the applied event as the final log of the command. `receiptHash` MUST
equal the return value of the execute function, the stored
`Receipt.receiptHash`, and the `receiptHash` argument of the applied event.

The two receipt kinds share one preimage and are domain separated by
`receiptKind` (`ACTION = 1`, `REVERSAL = 2`; zero is reserved). Recomputing
a receipt hash needs only the stored fields, which `receipt(commandId)`
returns; it never needs transaction calldata or the profile-defined
preimages of the opaque commitments.

For an action receipt, `commandKind` is the `ActionKind` value,
`parentCommandId` is zero, and `subject`, `source`, `destination`, `amount`,
`caseId`, `authorityRef`, `dependencyRoot`, and `provenanceCommitment` are
copied from the request. `externalCommitment` is
`keccak256(abi.encode(settlementCommitment, proceedsCommitment))` for
`LIQUIDATE`, the `entitlementCommitment` for `RECOVER`, and zero otherwise.

For a reversal receipt, `commandKind` is the `ReversalKind` value and
`parentCommandId` is the reversed `actionId`. `subject`, `amount`, and
`caseId` are those of the reversed action's record. `authorityRef` and
`provenanceCommitment` are those of the reversal request, and
`dependencyRoot` is the root the reversal was validated against. `source`
and `destination` are both the subject for `UNFREEZE` and `UNRESTRICT`; for
`RELEASE`, `source` is the custodian and `destination` is the declared prior
holder. `externalCommitment` is zero for every reversal.

`assessmentEvidence`, `preState`, and `postState` are opaque in the kernel.
Each profile MUST document their preimages together with its runtime
identity; the two reference profiles do so in their decision records.
`preState` and `postState` are taken from the same observation function
immediately before and after the effects of the command.

### Dependency root and epoch

`dependencyState()` returns the endpoint's current `dependencyRoot` and
`dependencyEpoch`. The root is `keccak256(abi.encode(DOMAIN,
DEPENDENCY_ROOT_TAG, policyBinding, identityBinding, settlementBinding,
entitlementBinding))`, ordered by `BindingKind`. A profile that has no
dependency of a given kind uses `bytes32(0)` in that slot and MUST say so in
its manifest.

The epoch starts at 1 and increments by exactly one on every rebind of any
kind; every rebind recomputes the root and MUST emit
`TrustDependencyChanged` with the kind, the previous and current per-kind
binding, the new root, and the new epoch. A per-kind binding MAY carry its
own version counter (the native profile's `bindingHash` does), but that
counter is internal to the binding: commands carry only the endpoint's root
and global epoch, and a change of any binding makes every command built
under the previous pair stale (reason 5). The receipt binds the root the
command was validated against, so a reader can tell under which set of
dependencies an action or reversal was evaluated.

The native profile binds each dependency by `bindingHash =
keccak256(abi.encode(DOMAIN, kind, dependency, runtimeCodeId,
configurationDigest, schema, epoch))`, which commits to the dependency's
address, runtime code, configuration digest, schema, and per-kind epoch.
Other profiles define their own per-kind binding but MUST feed the root the
same way.

### Bound dependencies

A native endpoint consults its dependencies only through
`ITrustBoundDependency`, read-only, during execution. `operation` is the
`ActionKind` value for actions and `0x80 | ReversalKind` for reversals. The
endpoint MUST classify a revert, a return of any length other than 128
bytes, an outcome word above 2, a command echo that differs from the digest
it passed, or a binding echo that differs from the current binding as
`OPERATIONAL_FAILURE`. Missing code at the bound address, a runtime code that
differs from the bound `runtimeCodeId`, or a configuration digest that
differs from the bound value are likewise operational failures (class 200).

These bindings prove which code and configuration were consulted under which
epoch. They do not prove that any external legal, identity, policy,
settlement, proceeds, or entitlement claim is true.

### Profiles

`trustProfile()` returns a `ProfileDescriptor`: the profile identifier, the
profile kind, the standard version (2), the masks of implemented actions and
reversals, the underlying token (zero for a native token), a manifest hash,
whether the endpoint is *full*, and whether it is a proxy. The descriptor is
a declaration about the endpoint, not proof of conformance. `full` MUST be
computed from the live topology and dependency state and MUST NOT be a
stored constant. A profile MAY add interfaces with their own ERC-165
identifiers; those identifiers are never part of the kernel identifier.

#### Native Full

| Property | Value |
| --- | --- |
| `profileId` | `keccak256("ERC-TRUST/v2/native-full")` |
| `profileKind` | `NATIVE_FULL` |
| endpoint | the token itself |
| `underlyingToken` | zero |
| `actionMask`, `reversalMask` | `0x3f`, `0x07` |
| dependencies | four read-only `ITrustBoundDependency` bindings, one per `BindingKind`; assessment and execution use the same current binding |
| route | `IERCTrustNativeRoute`; raw `setFrozenTokens` and `forcedTransfer` calls fail |
| authority | the account currently registered for `authorityRef`, which MAY be a contract |
| `manifestHash` | the current `dependencyRoot` |

#### ERC-3643 Verified Full

ERC-3643 identity and compliance responses are upstream inputs, not facts
proved by this proposal. The conformance unit is a governor together with an
adapter; the adapter is the endpoint and the token is `underlyingToken`.

| Property | Value |
| --- | --- |
| `profileId` | `keccak256("ERC-TRUST/v2/erc3643-verified-full")` |
| `profileKind` | `VERIFIED_FULL` |
| dependencies | the sealed token runtime identity, the Identity Registry (`IDENTITY`), and the Compliance contract (`POLICY`); `SETTLEMENT` and `ENTITLEMENT` are zero, so `LIQUIDATE` and `RECOVER` bind their commitments only |
| `full` | computed live from the sealed topology |
| `manifestHash` | the sealed binding |

A deployment MAY report this profile only while all of the following hold:

1. the adapter is the token's exclusive Agent;
2. the governor is the token owner and, after its one-way seal, exposes no
   arbitrary-call, Agent-management, or registry-rebinding path;
3. the token runtime code, Identity Registry, Compliance, owner, and
   exclusive Agent match the sealed binding (reason 300 when they no longer
   do, reason 200 when a bound dependency's runtime code changed);
4. every privileged direct and batch token mutator is unreachable except
   through the adapter;
5. the adapter implements all six actions and all three reversals.

Onboarding is a fresh zero-state seal or an exact import manifest, nothing
else. The manifest lists every account that carries an upstream frozen amount
or an address freeze at the seal, sorted by strictly increasing account, each
entry declaring nonzero state; the empty manifest is the fresh declaration.
The seal MUST verify every entry against the live upstream state and revert
with reason 303 on any difference. Declared state is then *owned* by the
adapter: an imported frozen amount opens a `FREEZE` case and an imported
address freeze opens a `RESTRICT` case, each with a synthetic applied head
that has no command hash and no receipt, so that declared legacy state is
reversible and amendable under the transition table. Any other initial state
makes the deployment Partial or Unsupported.

Before consuming a command, the adapter MUST check that every account the
command acts on carries exactly the upstream frozen amount and address freeze
flag that the adapter declared at the seal or applied itself, and MUST revert
with reason 304 otherwise. Upstream state the adapter does not own is never
overwritten and never silently adopted. Custody is confined to the adapter:
`SEIZE` requires the custodian and the destination to be the adapter itself.

Because an ERC-3643 forced transfer unfreezes the moved tokens and the token
holds a frozen *amount* while the kernel holds a frozen *target*, the adapter
materialises the owned target upstream only at its own touch points: after
every forced transfer it restores both accounts to their owned targets
saturated at the current balance and verifies the post-state (reason 401 on
mismatch). An ordinary inbound transfer between two touches leaves the
upstream frozen amount at the last applied value, so the growth is
transferable until the next command that touches the account or a call to
the profile's `resynchroniseFrozen(account)`, which any caller MAY make and
which only raises the upstream frozen amount toward the owned target. This
window is a property of adapting a frozen amount to a frozen target and MUST
be stated in the profile's limitations.

If a reseal or rebinding surface exists, every reseal MUST increment the
dependency epoch and change the root. The reference governor seals exactly
once, so its epoch is 1 for the life of the unit.

### ERC-20 and ERC-165

A native endpoint implements ERC-20 and reports ERC-165 support for the
interfaces it implements completely, including `0x2b020308` and the fungible
ERC-7943 identifier `0x3edbb4c4`. It MUST return `false` for `0xffffffff`.

### ERC-7943 route

ERC-7943 views MUST be non-mutating and non-reverting. `canTransfer` MUST
account for endpoint permission, custody backing, and the frozen target;
`getFrozenTokens` reports the stored target saturated at the current
balance, so an integrator that needs a custodian's ordinary capacity uses
`canTransfer` rather than `balance - getFrozenTokens`.

Raw calls to `setFrozenTokens` and `forcedTransfer` MUST fail. The native
route (`IERCTrustNativeRoute`) validates, assesses, and consumes a typed
command, then invokes the sensitive selector in the same transaction under an
exact-use ticket that records the command identifier, the selector, the
calldata hash, and the dependency root and epoch current at preparation.
Consumption MUST compare every recorded field against the sensitive call and
the current dependency state, the sensitive selector MUST compare the
prepared record against its arguments, and the ticket MUST be consumed
exactly once and MUST NOT remain live after return or revert.
`TrustRouteMismatch` identifies a rejected call by the domain, endpoint,
selector, and calldata hash; that identifier is computed only on failure and
is not stored.

For the absolute frozen amount, a greater target is a `FREEZE` action or
amendment, a lower target is an `UNFREEZE` reversal referencing the
original action, and an equal target is a no-state-change rejection.
`setFrozenTokens` MUST NOT relabel a decrease as `FREEZE`.

### Upgradeability and migration

The reference endpoints are immutable and report `proxySupported = false`.
Proxy and migration profiles are Unsupported in this version; a profile that
supports them requires its own conformance and assurance gate and MUST NOT
inherit either Full designation.

## Rationale

**One command format, one receipt.** Earlier drafts gave actions and
reversals different preimages, stored action and reversal kinds in one byte,
and let two profiles fill an unstored slot with different values, so the same
logical reversal hashed differently on each. A single seventeen-word receipt
with a nonzero kind tag gives indexers one parser and both profiles one
formula, and every preimage input is readable from the endpoint.

**A root and a global epoch instead of four pairs.** Binding only the policy
dependency let a command built under one identity registry execute after the
registry was replaced. Two words in the request bind all four dependencies,
the tagged and ordered preimage makes the root domain separated, and any
rebind makes earlier commands stale in one comparison.

**Cases with an explicit transition table.** Function names do not say which
regulatory matter an effect belongs to or whether it can still be lifted. A
case ties an action to its live effect, its custody, and its terminality; the
table fixes what a second command in the same case means, what a command from
another family means, and when a case can never be reused.

**No delegation and no cancellation in the kernel.** Delegation is a policy
of the authority account, which MAY be a contract; putting a registry in the
kernel would standardize one such policy. Cancellation would need a second
consumable state for an unapplied command; the validity window and the
exactly-once keys already bound a prepared command's life.

**Reason classes.** Distinguishing a completed denial from an unavailable
dependency is the difference between a policy decision and an outage. The
classes make that distinction machine-readable without fixing an
implementation's full code list.

**Exact-use route rather than a standing role.** A sensitive ERC-7943
selector reachable through a role can be reused outside a typed command.
The ticket ties one selector call to one command in one transaction.

**A separate state owner for ERC-3643.** Upstream token mutations are
stateful and cannot satisfy the native read-only dependency boundary, so the
profile uses a sealed governor and an adapter that owns the state it touches.
Adopting upstream state on first touch, the behaviour of an earlier adapter,
was rejected because it silently overwrote what the token had frozen before
the seal.

**Interface and observable behaviour only.** The normative surface is the
kernel interface, the wire format, and the observable behaviour above. It
does not mandate a proxy, a governance product, an identity registry, a
policy language, or a storage layout. An immutable token with read-only
bound dependencies and a sealed adapter over an existing token are two
reference architectures, not requirements for every profile.

**Related work.** [ERC-1450](./eip-1450.md) specifies an operational token
controlled by a registered transfer agent, including regulated transfers,
issuance, redemption, requests, fees, brokers, account controls, and
controller transfers. This proposal neither replaces that suite nor infers a
regulatory action from its function names or generic operator data.
[ERC-3643](./eip-3643.md) specifies an ERC-20 compatible permissioned token
suite with identity, compliance, agent, freeze, forced-transfer, and recovery
mechanisms; those mechanisms can serve as an adapter target, and the Verified
Full profile above states the conditions under which they do. They do not by
themselves provide the command, case, reversal, receipt, and dependency
binding semantics defined here. [ERC-7943](./eip-7943.md) provides the
neutral freeze and forced-transfer mechanics this proposal builds on.
[ERC-8319](./eip-8319.md) defines regulatory action meanings without an
onchain interface; this proposal supplies an execution and observation
interface for those meanings.

## Backwards Compatibility

The proposal is additive with respect to ERC-20 and ERC-7943: it changes no
selector, event, storage, or transfer semantics of either, and a native
conforming token implements the kernel interface alongside them. ERC-3643
compatibility is profile-specific and does not claim that every ERC-3643
deployment satisfies the Full topology.

An existing ERC-20, ERC-7943, ERC-1450, or ERC-3643 deployment does not
become conformant because it exposes similar privileged operations. It can
remain unchanged and be described as legacy untyped enforcement, or it can be
placed behind a profile adapter whose onboarding, ownership, and bypass
assumptions are stated as above. Applications unaware of this interface can
keep using the underlying token surfaces; applications that rely on typed
action identity or receipts MUST first check ERC-165 support for
`0x2b020308` and read `trustProfile()`.

Kernel version 2 is not wire compatible with the earlier candidate of this
proposal: the domain string, the request layouts, the receipt preimage, and
the interface identifier all differ, so a version 1 command or receipt is
invalid under version 2 and cannot be confused with one. The earlier
candidate remains available as a historical baseline.

## Test Cases

The conformance vectors accompany the machine-readable kernel definition.
They fix the identifiers, command hashes, binding hash, dependency root,
receipt hashes of both kinds, interface identifiers, and calldata lengths of
one fixture for all six actions and three reversals, and the following
negative cases. An implementation following the Specification section MUST
produce the listed result.

| Case | Input or mutation | Expected result |
| --- | --- | --- |
| Domain binding | change only the chain id or the endpoint address | a different identifier |
| Field binding | change one request field after deriving `actionId` | `TrustInvalidCommand` reason 2, except the `domain` field, which reason 1 rejects first; every mutation yields a different derived identifier |
| Wrong domain | any value other than `DOMAIN` | `TrustInvalidCommand` reason 1 |
| Non-canonical calldata | wrong length, dirty high bits, or an enum out of range | plain revert without a typed error and with no state change |
| Stale dependency | any dependency rebound after the request was built | `TrustInvalidCommand` reason 5 |
| Replay | submit an applied command again, or reuse its nonce under the same authority epoch | `TrustReplay` and full-state stutter |
| Freeze direction | a target not greater than the current one | `TrustInvalidCommand` reason 12; a decrease needs an `UNFREEZE` of the head |
| Case conflict | `FREEZE` or `RESTRICT` while the subject's live head belongs to another open case, or a disposition against an open overlay case | `TrustInvalidCommand` reason 10 and full-state stutter |
| Custody | a second `SEIZE` in a custody case, or a disposition or `RELEASE` that does not match the custody record | `TrustInvalidCommand` reason 8 |
| Terminal case | any action or reversal against a `TERMINAL` case | `TrustTerminal` and full-state stutter |
| Policy denial | a bound dependency answers `REJECTED` | `TrustRejected` and no key consumed |
| Dependency failure | a bound dependency reverts, returns malformed data, or echoes the wrong command or binding | `TrustOperationalFailure` and no key consumed |
| Receipt kind | recompute a `REVERSAL` receipt with `receiptKind = ACTION` | a different `receiptHash` |
| Receipt consistency | any applied command | the return value, the stored `receiptHash`, and the applied event's `receiptHash` are equal |
| Raw sensitive selector | call `setFrozenTokens` or `forcedTransfer` without a live ticket | revert |
| Interface honesty | `supportsInterface(0xffffffff)` or an interface the endpoint does not implement completely | `false` |

An independent implementation written from the kernel definition and the
vectors alone reproduces every entry; its program and receipt accompany the
reference implementation.

## Reference Implementation

A native token, an ERC-3643 adapter with its governor, and a TypeScript SDK
accompany this proposal together with the machine-readable kernel definition
from which the Solidity interface, the ABI, the SDK types, and the vectors are
generated. Those materials are non-normative; passing their tests or proof
harnesses does not establish conformance of another implementation or of any
deployment.

The abstract model of the kernel is mechanically verified in Isabelle/HOL,
and every load-bearing condition of that model that the accompanying
obligation ledger names is connected to the final code by a source consumer,
a positive test, a killed consumer-removal mutation, and a compiled consumer.
That connection is mapped implementation evidence; it is not an end-to-end
refinement proof, and the assumption under which the compiled runtime is
abstracted to the model is stated as an unproved locale assumption. The three
runtime templates are byte-for-byte reproducible and agree with a
pinned-compiler replay in six semantic projections. The reference is
unaudited and not for production; it contains no verified deployment, proxy,
migration, address, chain, signer, or key-management claim, and no external
legal or factual truth is verified.

## Security Considerations

### Authority does not establish legal power

The endpoint verifies that the caller is the account registered for
`authorityRef` at the current epoch. It cannot determine whether that
authority has valid legal power in a jurisdiction or case. Deployers must
define how an authority is created, reviewed, rotated, and revoked; a
compromised authority account can issue any command its epoch permits until
it is rotated. A registered authority that is a contract inherits that
contract's own access control, which the kernel does not inspect.

### Replay and cross-domain reuse

Every identifier binds the domain, the endpoint address, the chain id, and
the complete request, and every command carries the current dependency root
and epoch. Omitting any of these from a derivation would allow replay across
deployments or after a governance change. Implementations MUST reject reused
command identifiers and nonce tuples and MUST report stale commands before
any state-dependent rule.

### Raw privileged bypass

If the same authority can reach `forcedTransfer`, `setFrozenTokens`, mint,
burn, batch, recovery, owner, agent, proxy, or migration routes outside the
typed kernel, receipts do not describe the complete regulatory state. Full
conformance requires a complete privileged-mutator inventory and the closure
of every untyped bypass; the exact-use ticket closes the two sensitive
ERC-7943 selectors of the native profile, and the sealed governor closes the
Agent surface of the ERC-3643 profile.

### Reentrancy and partial writes

External calls introduce reentrancy and denial-of-service risk. Native
dependencies are read-only and bound to code and configuration. An adapter
that mutates an upstream token must use reentrancy protection, validate exact
return data and post-state, and revert the whole transaction on mismatch. No
applied event or receipt may survive a failed call.

### Dependency substitution and stale configuration

An address alone does not identify dependency behaviour. Upgradeable code,
registry changes, mutable configuration, or schema changes can alter an
assessment without changing the calling interface. Binding the code, the
configuration digest, the schema, and the epoch, and folding every binding
into one root that every command must carry, makes such changes detectable;
it does not make the dependency trustworthy. A rebind invalidates every
command prepared under the previous root.

### Terminal and irreversible actions

`CONFISCATE`, `LIQUIDATE`, and `RECOVER` are terminal. A malformed case,
destination, custody record, settlement premise, or entitlement can cause an
irreversible disposition. Implementations SHOULD require stronger
authorization and review for terminal actions than for reversible ones.

### Custody accounting

`SEIZE` separates token custody from a declared prior holder. An
implementation that treats the current balance holder as legal title can
misstate ownership. Custody backing MUST remain exactly backed and
unspendable by ordinary transfers, and `RELEASE` MUST consume the same active
custody record; a disposition of custody consumes the whole record.

### Frozen targets over an adapted token

Under the ERC-3643 profile the token holds a frozen amount while the kernel
holds a frozen target, so tokens received between two touches of an account
are transferable until the next touch or a resynchronisation. A deployment
that cannot accept that window needs a transfer hook inside the token or its
Compliance, which the profile does not use. The seal binds a declared token
code identifier to the live code; it does not audit the code, and an
ERC-3643 Full designation is invalid if another Agent, an owner call, an
upgrade, a batch path, or a mutable code path can bypass the adapter.

### Receipt limitations and privacy

A receipt and its commitments can reveal that a person, address, asset, or
case is subject to regulatory action. Deployers must assess confidentiality,
tipping-off, and personal-data obligations before placing identifiers or
evidence on a public chain; hashing low-entropy or identifying data may not
provide effective confidentiality. The receipt proves only the onchain
transition and the committed inputs. It is not a legal opinion, security
audit, settlement confirmation, identity proof, or ownership determination.

### Timestamps

`block.timestamp` bounds are subject to ordinary validator timestamp
tolerance; a validity window narrower than that tolerance is unreliable.

### Upgrade, proxy, and migration risk

The interface does not make an implementation immutable. An upgrade can
change authorization, transitions, event ordering, or receipt computation
while the address stays constant. A proxy or migration profile must bind its
implementation and governance, reconcile the complete case, action, and
replay state, invalidate or reauthorize pending commands, and reassess
conformance after every change. The reference endpoints report
`proxySupported = false`.

### Deployment and audit boundary

Conformance of source code does not establish the identity or safety of a
deployment. A deployment claim must bind the source, compiler settings,
creation and runtime bytecode, constructor inputs, addresses, roles, external
dependencies, chain, and current configuration; runtime bytecode size and
compiler settings are deployment constraints that the reference binds in its
release manifest. Independent audit and key management remain outside this
interface. The reference has not been audited and is not production-ready.

## Copyright

Copyright and related rights waived via [CC0](LICENSE-CC0.md).

The ERC-3643 declarations are clean-room interface signatures only; no GPL
implementation source is copied or adapted.
