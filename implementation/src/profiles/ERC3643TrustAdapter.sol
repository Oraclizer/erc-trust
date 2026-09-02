// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {IERCTrustKernel, TrustKernelTypes} from "../generated/IERCTrustKernel.sol";
import {
    IERC3643TokenView,
    IERC3643TokenMutator,
    IERC3643IdentityRegistry,
    IERC3643Compliance
} from "../interfaces/IERC3643External.sol";
import {ERC3643ProfileTypes} from "./ERC3643ProfileTypes.sol";
import {ProfileGovernor} from "./ProfileGovernor.sol";
import {TrustReentrancy, TrustZeroAddress} from "../TrustErrors.sol";

/// @notice Profile-specific surface of the ERC-3643 Verified Full endpoint. Its ERC-165 identifier is
///         separate from the kernel identifier; the kernel interface is unchanged.
interface IERC3643VerifiedProfile {
    /// @dev Emitted when the upstream frozen amount of an owned account is brought back to its owned
    ///      target saturated at the current balance outside a command.
    event FrozenTargetResynchronised(address indexed account, uint256 frozenTarget, uint256 appliedFrozen);

    /// @notice The adapter-owned upstream state of an account: the absolute frozen target, the upstream
    ///         frozen amount the adapter last verified, and the address freeze flag.
    function ownedState(address account)
        external
        view
        returns (uint256 frozenTarget, uint256 appliedFrozen, bool restricted);

    /// @notice Brings the upstream frozen amount of an owned account to its owned target saturated at the
    ///         current balance. Callable by anyone: it changes no owned state, requires the live sealed
    ///         topology and the ownership precondition, and only ever raises the upstream frozen amount.
    function resynchroniseFrozen(address account) external returns (uint256 appliedFrozen);
}

/// @notice Kernel version 2 endpoint of the ERC-3643 Verified Full profile: the only TRUST endpoint and
///         the exclusive enforcement Agent of one sealed ERC-3643 conformance unit.
/// @dev The adapter owns the regulatory state (cases, effect heads, custody, frozen targets, address
///      freeze flags) and the receipts; the underlying token only executes. Every upstream state the
///      adapter acts on must be state it declared at the seal or applied itself; anything else, and
///      every unauthenticated, unsealed, malformed, or drifted path, fails closed.
contract ERC3643TrustAdapter is IERCTrustKernel, IERC3643VerifiedProfile {
    bytes4 internal constant ERC165_INTERFACE_ID = 0x01ffc9a7;
    uint16 internal constant REASON_DOMAIN = 1;
    uint16 internal constant REASON_IDENTIFIER = 2;
    uint16 internal constant REASON_TIME = 3;
    uint16 internal constant REASON_AUTHORITY_EPOCH = 4;
    uint16 internal constant REASON_DEPENDENCY_BINDING = 5;
    uint16 internal constant REASON_SHAPE = 6;
    uint16 internal constant REASON_REVERSAL_PAIRING = 7;
    uint16 internal constant REASON_CUSTODY = 8;
    uint16 internal constant REASON_ENTITLEMENT = 9;
    uint16 internal constant REASON_CASE_CONFLICT = 10;
    uint16 internal constant REASON_CURRENT_EFFECT = 11;
    uint16 internal constant REASON_FREEZE_DIRECTION = 12;
    uint16 internal constant REASON_NO_STATE_CHANGE = 13;
    uint16 internal constant REASON_POLICY_DENIED = 100;
    uint16 internal constant REASON_IDENTITY_DENIED = 101;
    uint16 internal constant REASON_DEPENDENCY_CODE_MISMATCH = 200;
    uint16 internal constant REASON_DEPENDENCY_UNAVAILABLE_AT_BIND = 205;
    uint16 internal constant REASON_TOPOLOGY_NOT_FULL = 300;
    uint16 internal constant REASON_SEAL_INVALID = 301;
    uint16 internal constant REASON_IMPORT_MANIFEST_MISMATCH = 303;
    uint16 internal constant REASON_UPSTREAM_STATE_NOT_OWNED = 304;
    uint16 internal constant REASON_UPSTREAM_CALL_FAILED = 400;
    uint16 internal constant REASON_UPSTREAM_POSTSTATE_MISMATCH = 401;
    uint16 internal constant REASON_IDENTITY_REGISTRY_UNAVAILABLE = 402;
    uint16 internal constant REASON_COMPLIANCE_UNAVAILABLE = 403;
    uint8 internal constant CONSULTED_POLICY = 1;
    uint8 internal constant CONSULTED_IDENTITY = 2;
    uint64 internal constant AUTHORITY_EPOCH = 1;
    uint64 internal constant SEAL_EPOCH = 1;
    uint256 internal constant ACTION_CALLDATA_LENGTH = 644;
    uint256 internal constant REVERSAL_CALLDATA_LENGTH = 388;
    uint256 internal constant PROFILE_ACTION_MASK = 0x3f;
    uint256 internal constant PROFILE_REVERSAL_MASK = 0x07;
    uint256 internal constant UPSTREAM_VIEW_GAS = 200_000;
    /// @dev keccak256("ERC-TRUST/v2/erc3643-verified-full/import")
    bytes32 internal constant IMPORT_TAG = keccak256("ERC-TRUST/v2/erc3643-verified-full/import");

    address public immutable token;
    ProfileGovernor public immutable profileGovernor;
    address public immutable authority;
    bytes32 public immutable authorityRef;

    uint256 private _entered;
    bool private _sealed;
    bytes32 private _sealedBinding;
    bytes32 private _importManifestHash;
    bytes32 private _dependencyRoot;
    uint64 private _dependencyEpoch;
    mapping(TrustKernelTypes.BindingKind => ERC3643ProfileTypes.DependencyBinding) private _bindings;

    mapping(bytes32 => TrustKernelTypes.ActionRecord) private _actions;
    mapping(bytes32 => ERC3643ProfileTypes.EffectRecord) private _effects;
    mapping(bytes32 => TrustKernelTypes.Receipt) private _receipts;
    mapping(bytes32 => TrustKernelTypes.CaseRecord) private _cases;
    mapping(bytes32 => ERC3643ProfileTypes.CustodyRecord) private _custody;
    mapping(bytes32 => bool) private _usedNonces;
    mapping(bytes32 => bool) private _consumedEntitlements;
    mapping(address => ERC3643ProfileTypes.OwnedState) private _owned;
    mapping(address => ERC3643ProfileTypes.EffectHead) private _freezeHeads;
    mapping(address => ERC3643ProfileTypes.EffectHead) private _restrictionHeads;
    mapping(address => uint256) private _custodyBacking;

    event ProfileActivated(bytes32 indexed binding, bytes32 indexed importManifestHash, uint256 importedEntries);
    /// @dev An imported entry opens a case whose live head is a synthetic applied action with no command
    ///      and no receipt; the declared legacy state becomes reversible under the kernel rules.
    event RegulatoryStateImported(
        bytes32 indexed caseId,
        bytes32 indexed actionId,
        address indexed subject,
        uint8 family,
        uint256 frozenAmount,
        bool restricted
    );

    modifier nonReentrant() {
        if (_entered != 0) revert TrustReentrancy();
        _entered = 1;
        _;
        _entered = 0;
    }

    constructor(address profileGovernor_, address authority_, bytes32 authorityRef_) {
        if (profileGovernor_ == address(0) || authority_ == address(0) || authorityRef_ == bytes32(0)) {
            revert TrustZeroAddress();
        }
        profileGovernor = ProfileGovernor(profileGovernor_);
        token = ProfileGovernor(profileGovernor_).token();
        authority = authority_;
        authorityRef = authorityRef_;
        emit TrustAuthorityChanged(authorityRef_, authority_, AUTHORITY_EPOCH, true);
    }

    // ---------------------------------------------------------------------
    // Seal activation
    // ---------------------------------------------------------------------

    /// @notice Called once by the governor inside its seal: binds the dependencies, fixes the dependency
    ///         root and epoch, and imports the declared upstream state after verifying every entry.
    /// @dev The canonical form of the manifest (ordering, nonzero entries) is enforced by the governor;
    ///      the adapter only recomputes the manifest hash it was sealed with.
    function activateSeal(ERC3643ProfileTypes.ImportEntry[] calldata entries) external {
        if (msg.sender != address(profileGovernor)) revert TrustUnauthorized(msg.sender, bytes32(0));
        if (_sealed || !profileGovernor.topologySealed() || profileGovernor.exclusiveAdapter() != address(this)) {
            revert TrustOperationalFailure(bytes32(0), REASON_SEAL_INVALID, _tokenRef());
        }
        bytes32 binding = profileGovernor.sealedBinding();
        bytes32 manifestHash = profileGovernor.importManifestHash();
        if (manifestHash != keccak256(abi.encode(entries))) {
            revert TrustOperationalFailure(bytes32(0), REASON_IMPORT_MANIFEST_MISMATCH, _tokenRef());
        }
        _sealed = true;
        _sealedBinding = binding;
        _importManifestHash = manifestHash;
        _bind(TrustKernelTypes.BindingKind.POLICY, profileGovernor.compliance(), binding);
        _bind(TrustKernelTypes.BindingKind.IDENTITY, profileGovernor.identityRegistry(), binding);
        _dependencyEpoch = SEAL_EPOCH;
        _dependencyRoot = _computeDependencyRoot();
        for (uint8 kind = 0; kind < 4; ++kind) {
            emit TrustDependencyChanged(
                kind, bytes32(0), _bindings[TrustKernelTypes.BindingKind(kind)].bindingHash, _dependencyRoot, SEAL_EPOCH
            );
        }
        for (uint256 i = 0; i < entries.length; ++i) {
            _importEntry(entries[i], manifestHash);
        }
        emit ProfileActivated(binding, manifestHash, entries.length);
    }

    // ---------------------------------------------------------------------
    // ERC-165 and kernel views
    // ---------------------------------------------------------------------

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId != 0xffffffff
            && (interfaceId == ERC165_INTERFACE_ID
                || interfaceId == type(IERCTrustKernel).interfaceId
                || interfaceId == type(IERC3643VerifiedProfile).interfaceId);
    }

    function deriveActionId(TrustKernelTypes.ActionRequest calldata request) external view returns (bytes32) {
        return _actionHash(request, true);
    }

    function deriveReversalId(TrustKernelTypes.ReversalRequest calldata request) external view returns (bytes32) {
        return _reversalHash(request, true);
    }

    function actionRecord(bytes32 actionId) external view returns (TrustKernelTypes.ActionRecord memory) {
        return _actions[actionId];
    }

    function receipt(bytes32 commandId) external view returns (TrustKernelTypes.Receipt memory) {
        return _receipts[commandId];
    }

    function caseRecord(bytes32 caseId) external view returns (TrustKernelTypes.CaseRecord memory) {
        return _cases[caseId];
    }

    function dependencyState() external view returns (bytes32 dependencyRoot, uint64 dependencyEpoch) {
        return (_dependencyRoot, _dependencyEpoch);
    }

    /// @dev `full` is computed from the live sealed topology and the bound dependency code on every call.
    function trustProfile() external view returns (TrustKernelTypes.ProfileDescriptor memory descriptor) {
        descriptor = TrustKernelTypes.ProfileDescriptor({
            profileId: TrustKernelTypes.PROFILE_ERC3643_VERIFIED_FULL,
            profileKind: TrustKernelTypes.ProfileKind.VERIFIED_FULL,
            standardVersion: TrustKernelTypes.STANDARD_VERSION,
            actionMask: PROFILE_ACTION_MASK,
            reversalMask: PROFILE_REVERSAL_MASK,
            underlyingToken: token,
            manifestHash: _sealedBinding,
            full: _topologyFull(),
            proxySupported: false
        });
    }

    // ---------------------------------------------------------------------
    // Profile surface
    // ---------------------------------------------------------------------

    function ownedState(address account)
        external
        view
        returns (uint256 frozenTarget, uint256 appliedFrozen, bool restricted)
    {
        ERC3643ProfileTypes.OwnedState storage owned = _owned[account];
        return (owned.frozenTarget, owned.appliedFrozen, owned.restricted);
    }

    /// @dev The owned target is materialised upstream at the adapter's touch points only; balance growth
    ///      between two touches leaves the upstream frozen amount at the last applied value until this
    ///      call or the next command. The synchronisation is the one every command performs.
    function resynchroniseFrozen(address account) external nonReentrant returns (uint256 appliedFrozen) {
        _requireLiveTopology(bytes32(0));
        _requireOwnedUpstreamState(bytes32(0), account);
        _syncFrozen(bytes32(0), account);
        ERC3643ProfileTypes.OwnedState storage owned = _owned[account];
        emit FrozenTargetResynchronised(account, owned.frozenTarget, owned.appliedFrozen);
        return owned.appliedFrozen;
    }

    // ---------------------------------------------------------------------
    // Canonical typed entrypoints
    // ---------------------------------------------------------------------

    function executeRegulatoryAction(TrustKernelTypes.ActionRequest calldata request)
        external
        nonReentrant
        returns (bytes32 receiptHash)
    {
        _requireCalldataLength(ACTION_CALLDATA_LENGTH);
        bytes32 digest = _validateAndAuthorizeAction(request, msg.sender);
        _requireLiveTopology(request.actionId);
        bytes32 evidence = _assessAction(request, digest);
        _requireOwnedUpstreamState(request.actionId, request.subject);
        if (request.action == TrustKernelTypes.ActionKind.SEIZE) {
            _requireOwnedUpstreamState(request.actionId, request.custodian);
        } else if (request.destination != address(0)) {
            if (request.source != request.subject) _requireOwnedUpstreamState(request.actionId, request.source);
            _requireOwnedUpstreamState(request.actionId, request.destination);
        }
        _consumeActionAuthorization(request, digest, evidence);
        TrustKernelTypes.ActionRequest memory copy = request;
        return _applyActionPrepared(copy);
    }

    function executeRegulatoryReversal(TrustKernelTypes.ReversalRequest calldata request)
        external
        nonReentrant
        returns (bytes32 receiptHash)
    {
        _requireCalldataLength(REVERSAL_CALLDATA_LENGTH);
        bytes32 digest = _validateAndAuthorizeReversal(request, msg.sender);
        _requireLiveTopology(request.reversalId);
        bytes32 evidence = _assessReversal(request, digest);
        TrustKernelTypes.ActionRecord storage original = _actions[request.actionId];
        if (request.reversal == TrustKernelTypes.ReversalKind.RELEASE) {
            _requireOwnedUpstreamState(request.reversalId, original.custodian);
            _requireOwnedUpstreamState(request.reversalId, original.source);
        } else {
            _requireOwnedUpstreamState(request.reversalId, original.subject);
        }
        _usedNonces[_nonceKey(request.authorityRef, request.authorityEpoch, request.nonce)] = true;
        return _applyReversalPrepared(request, evidence);
    }

    // ---------------------------------------------------------------------
    // Validation
    // ---------------------------------------------------------------------

    function _validateAndAuthorizeAction(TrustKernelTypes.ActionRequest calldata request, address caller)
        internal
        view
        returns (bytes32 digest)
    {
        if (request.domain != TrustKernelTypes.DOMAIN) revert TrustInvalidCommand(request.actionId, REASON_DOMAIN);
        if (request.actionId == bytes32(0) || request.actionId != _actionHash(request, true)) {
            revert TrustInvalidCommand(request.actionId, REASON_IDENTIFIER);
        }
        if (_actions[request.actionId].lifecycle != TrustKernelTypes.Lifecycle.NONE) {
            revert TrustReplay(request.actionId);
        }
        if (block.timestamp < request.validAfter || request.validBefore == 0 || block.timestamp > request.validBefore) {
            revert TrustInvalidCommand(request.actionId, REASON_TIME);
        }
        _requireAuthority(request.actionId, request.authorityRef, request.authorityEpoch, caller);
        if (request.dependencyRoot != _dependencyRoot || request.dependencyEpoch != _dependencyEpoch) {
            revert TrustInvalidCommand(request.actionId, REASON_DEPENDENCY_BINDING);
        }
        _requireFreshNonce(request.authorityRef, request.authorityEpoch, request.nonce);
        _validateActionShape(request);
        digest = _actionHash(request, false);
    }

    function _validateAndAuthorizeReversal(TrustKernelTypes.ReversalRequest calldata request, address caller)
        internal
        view
        returns (bytes32 digest)
    {
        if (request.domain != TrustKernelTypes.DOMAIN) {
            revert TrustInvalidCommand(request.reversalId, REASON_DOMAIN);
        }
        if (request.reversalId == bytes32(0) || request.reversalId != _reversalHash(request, true)) {
            revert TrustInvalidCommand(request.reversalId, REASON_IDENTIFIER);
        }
        if (_receipts[request.reversalId].receiptKind != TrustKernelTypes.ReceiptKind.NONE) {
            revert TrustReplay(request.reversalId);
        }
        if (block.timestamp < request.validAfter || request.validBefore == 0 || block.timestamp > request.validBefore) {
            revert TrustInvalidCommand(request.reversalId, REASON_TIME);
        }
        _requireAuthority(request.reversalId, request.authorityRef, request.authorityEpoch, caller);
        if (request.dependencyRoot != _dependencyRoot || request.dependencyEpoch != _dependencyEpoch) {
            revert TrustInvalidCommand(request.reversalId, REASON_DEPENDENCY_BINDING);
        }
        _requireFreshNonce(request.authorityRef, request.authorityEpoch, request.nonce);
        if (request.provenanceCommitment == bytes32(0)) revert TrustInvalidCommand(request.reversalId, REASON_SHAPE);
        TrustKernelTypes.ActionRecord storage original = _actions[request.actionId];
        if (_cases[original.caseId].phase == TrustKernelTypes.CasePhase.TERMINAL) {
            revert TrustTerminal(original.caseId);
        }
        if (original.lifecycle != TrustKernelTypes.Lifecycle.APPLIED) {
            revert TrustInvalidCommand(request.reversalId, REASON_CURRENT_EFFECT);
        }
        if (!_reversalMatches(original.action, request.reversal)) {
            revert TrustInvalidCommand(request.reversalId, REASON_REVERSAL_PAIRING);
        }
        _validateCurrentEffect(request.reversalId, request.actionId, request.reversal, original);
        digest = _reversalHash(request, false);
    }

    /// @dev The profile has one immutable authority at epoch 1; an unknown reference has epoch 0.
    function _requireAuthority(bytes32 commandId, bytes32 requestedRef, uint64 requestedEpoch, address caller)
        internal
        view
    {
        uint64 currentEpoch = requestedRef == authorityRef ? AUTHORITY_EPOCH : 0;
        if (requestedEpoch != currentEpoch) revert TrustInvalidCommand(commandId, REASON_AUTHORITY_EPOCH);
        if (requestedRef != authorityRef || caller != authority) revert TrustUnauthorized(caller, requestedRef);
    }

    function _requireFreshNonce(bytes32 requestedRef, uint64 requestedEpoch, uint256 nonce) internal view {
        bytes32 key = _nonceKey(requestedRef, requestedEpoch, nonce);
        if (_usedNonces[key]) revert TrustReplay(key);
    }

    /// @dev Per-action field rules and the case transition table. Reason codes follow shapeRules. The
    ///      profile additionally confines custody to the adapter itself.
    function _validateActionShape(TrustKernelTypes.ActionRequest calldata request) internal view {
        if (request.subject == address(0) || request.caseId == bytes32(0) || request.provenanceCommitment == bytes32(0))
        {
            revert TrustInvalidCommand(request.actionId, REASON_SHAPE);
        }
        TrustKernelTypes.CaseRecord storage caseState = _cases[request.caseId];
        if (caseState.phase == TrustKernelTypes.CasePhase.TERMINAL) revert TrustTerminal(request.caseId);
        TrustKernelTypes.ActionKind action = request.action;

        if (action == TrustKernelTypes.ActionKind.FREEZE) {
            if (
                request.source != request.subject || request.destination != address(0)
                    || request.custodian != address(0)
            ) {
                revert TrustInvalidCommand(request.actionId, REASON_SHAPE);
            }
            _requireOverlayAdmissible(request.actionId, caseState, _freezeHeads[request.subject]);
            if (request.amount <= _owned[request.subject].frozenTarget) {
                revert TrustInvalidCommand(request.actionId, REASON_FREEZE_DIRECTION);
            }
        } else if (action == TrustKernelTypes.ActionKind.RESTRICT) {
            if (
                request.source != request.subject || request.destination != address(0)
                    || request.custodian != address(0) || request.amount != 0
            ) {
                revert TrustInvalidCommand(request.actionId, REASON_SHAPE);
            }
            ERC3643ProfileTypes.EffectHead storage head = _restrictionHeads[request.subject];
            if (head.actionId != bytes32(0) && caseState.headActionId == head.actionId) {
                revert TrustInvalidCommand(request.actionId, REASON_NO_STATE_CHANGE);
            }
            _requireOverlayAdmissible(request.actionId, caseState, head);
        } else {
            if (
                request.source == address(0) || request.destination == address(0)
                    || request.source == request.destination || request.amount == 0
            ) {
                revert TrustInvalidCommand(request.actionId, REASON_SHAPE);
            }
            if (action == TrustKernelTypes.ActionKind.SEIZE) {
                if (
                    request.subject != request.source || request.custodian != address(this)
                        || request.destination != request.custodian
                ) {
                    revert TrustInvalidCommand(request.actionId, REASON_SHAPE);
                }
                if (caseState.phase == TrustKernelTypes.CasePhase.OPEN) {
                    revert TrustInvalidCommand(
                        request.actionId,
                        caseState.family == TrustKernelTypes.CaseFamily.CUSTODY ? REASON_CUSTODY : REASON_CASE_CONFLICT
                    );
                }
            } else {
                if (request.custodian != address(0)) revert TrustInvalidCommand(request.actionId, REASON_SHAPE);
                if (caseState.phase == TrustKernelTypes.CasePhase.OPEN) {
                    if (caseState.family != TrustKernelTypes.CaseFamily.CUSTODY) {
                        revert TrustInvalidCommand(request.actionId, REASON_CASE_CONFLICT);
                    }
                } else if (request.subject != request.source) {
                    revert TrustInvalidCommand(request.actionId, REASON_SHAPE);
                }
            }
        }

        if (action == TrustKernelTypes.ActionKind.LIQUIDATE) {
            if (request.settlementCommitment == bytes32(0) || request.proceedsCommitment == bytes32(0)) {
                revert TrustInvalidCommand(request.actionId, REASON_SHAPE);
            }
        } else if (request.settlementCommitment != bytes32(0) || request.proceedsCommitment != bytes32(0)) {
            revert TrustInvalidCommand(request.actionId, REASON_SHAPE);
        }
        if (action == TrustKernelTypes.ActionKind.RECOVER) {
            if (request.entitlementCommitment == bytes32(0)) {
                revert TrustInvalidCommand(request.actionId, REASON_SHAPE);
            }
            if (_consumedEntitlements[request.entitlementCommitment]) {
                revert TrustInvalidCommand(request.actionId, REASON_ENTITLEMENT);
            }
        } else if (request.entitlementCommitment != bytes32(0)) {
            revert TrustInvalidCommand(request.actionId, REASON_SHAPE);
        }
    }

    /// @dev Overlay families: a subject has one live head per family across all cases. Opening
    ///      requires a fresh case; an amendment requires the subject's live head to be this case's head.
    function _requireOverlayAdmissible(
        bytes32 actionId,
        TrustKernelTypes.CaseRecord storage caseState,
        ERC3643ProfileTypes.EffectHead storage head
    ) internal view {
        if (head.actionId == bytes32(0)) {
            if (caseState.phase != TrustKernelTypes.CasePhase.NONE) {
                revert TrustInvalidCommand(actionId, REASON_CASE_CONFLICT);
            }
        } else if (caseState.headActionId != head.actionId) {
            revert TrustInvalidCommand(actionId, REASON_CASE_CONFLICT);
        }
    }

    function _validateCurrentEffect(
        bytes32 reversalId,
        bytes32 actionId,
        TrustKernelTypes.ReversalKind reversal,
        TrustKernelTypes.ActionRecord storage original
    ) internal view {
        if (reversal == TrustKernelTypes.ReversalKind.RELEASE) {
            ERC3643ProfileTypes.CustodyRecord storage custody = _custody[original.caseId];
            if (
                !custody.active || custody.actionId != actionId || custody.custodian != original.custodian
                    || custody.declaredPriorHolder != original.source || custody.encumberedAmount != original.amount
                    || _custodyBacking[custody.custodian] < custody.encumberedAmount
            ) {
                revert TrustInvalidCommand(reversalId, REASON_CUSTODY);
            }
            return;
        }
        ERC3643ProfileTypes.EffectRecord storage effect = _effects[actionId];
        if (effect.generation == 0 || effect.effectHash != _effectHash(original, effect)) {
            revert TrustInvalidCommand(reversalId, REASON_CURRENT_EFFECT);
        }
        ERC3643ProfileTypes.EffectHead storage head = reversal == TrustKernelTypes.ReversalKind.UNFREEZE
            ? _freezeHeads[original.subject]
            : _restrictionHeads[original.subject];
        bool stateMatches = reversal == TrustKernelTypes.ReversalKind.UNFREEZE
            ? _owned[original.subject].frozenTarget == original.amount
            : _owned[original.subject].restricted;
        if (head.actionId != actionId || head.effectHash != effect.effectHash || !stateMatches) {
            revert TrustInvalidCommand(reversalId, REASON_CURRENT_EFFECT);
        }
    }

    // ---------------------------------------------------------------------
    // Topology, dependency assessment, and upstream state ownership
    // ---------------------------------------------------------------------

    function _topologyFull() internal view returns (bool) {
        return _sealed && profileGovernor.isFull(address(this)) && _bindingLive(TrustKernelTypes.BindingKind.POLICY)
            && _bindingLive(TrustKernelTypes.BindingKind.IDENTITY);
    }

    /// @dev Class 300 when the sealed topology no longer holds, class 200 when a bound dependency's
    ///      runtime code changed.
    function _requireLiveTopology(bytes32 commandId) internal view {
        if (!_sealed || !profileGovernor.isFull(address(this))) {
            revert TrustOperationalFailure(commandId, REASON_TOPOLOGY_NOT_FULL, _tokenRef());
        }
        if (!_bindingLive(TrustKernelTypes.BindingKind.POLICY)) {
            revert TrustOperationalFailure(
                commandId, REASON_DEPENDENCY_CODE_MISMATCH, _bindings[TrustKernelTypes.BindingKind.POLICY].bindingHash
            );
        }
        if (!_bindingLive(TrustKernelTypes.BindingKind.IDENTITY)) {
            revert TrustOperationalFailure(
                commandId, REASON_DEPENDENCY_CODE_MISMATCH, _bindings[TrustKernelTypes.BindingKind.IDENTITY].bindingHash
            );
        }
    }

    /// @dev Profile-defined assessment evidence: the dependency root, the command digest, and the mask
    ///      of dependencies consulted (bit 0 the Compliance policy, bit 1 the Identity Registry).
    ///      Transfer commands consult both for their destination; overlay commands consult none.
    function _assessAction(TrustKernelTypes.ActionRequest calldata request, bytes32 digest)
        internal
        view
        returns (bytes32 evidence)
    {
        uint8 consulted;
        if (request.destination != address(0)) {
            _assessIdentity(request.actionId, request.destination);
            _assessCompliance(request.actionId, request.source, request.destination, request.amount);
            consulted = CONSULTED_POLICY | CONSULTED_IDENTITY;
        }
        evidence = keccak256(abi.encode(_dependencyRoot, digest, consulted));
    }

    function _assessReversal(TrustKernelTypes.ReversalRequest calldata request, bytes32 digest)
        internal
        view
        returns (bytes32 evidence)
    {
        uint8 consulted;
        if (request.reversal == TrustKernelTypes.ReversalKind.RELEASE) {
            TrustKernelTypes.ActionRecord storage original = _actions[request.actionId];
            _assessIdentity(request.reversalId, original.source);
            _assessCompliance(request.reversalId, original.custodian, original.source, original.amount);
            consulted = CONSULTED_POLICY | CONSULTED_IDENTITY;
        }
        evidence = keccak256(abi.encode(_dependencyRoot, digest, consulted));
    }

    function _assessIdentity(bytes32 commandId, address account) internal view {
        address registry = _bindings[TrustKernelTypes.BindingKind.IDENTITY].dependency;
        (bool ok, uint256 word) = _staticWord(registry, abi.encodeCall(IERC3643IdentityRegistry.isVerified, (account)));
        if (!ok || word > 1) {
            revert TrustOperationalFailure(commandId, REASON_IDENTITY_REGISTRY_UNAVAILABLE, _addressRef(registry));
        }
        if (word == 0) revert TrustRejected(commandId, REASON_IDENTITY_DENIED);
    }

    function _assessCompliance(bytes32 commandId, address from, address to, uint256 amount) internal view {
        address policy = _bindings[TrustKernelTypes.BindingKind.POLICY].dependency;
        (bool ok, uint256 word) =
            _staticWord(policy, abi.encodeCall(IERC3643Compliance.canTransfer, (from, to, amount)));
        if (!ok || word > 1) {
            revert TrustOperationalFailure(commandId, REASON_COMPLIANCE_UNAVAILABLE, _addressRef(policy));
        }
        if (word == 0) revert TrustRejected(commandId, REASON_POLICY_DENIED);
    }

    /// @dev The upstream frozen amount and address freeze flag of an account the adapter is about to act
    ///      on must be exactly the state the adapter declared at the seal or applied itself.
    function _requireOwnedUpstreamState(bytes32 commandId, address account) internal view {
        ERC3643ProfileTypes.OwnedState storage owned = _owned[account];
        if (
            _upstreamFrozen(commandId, account) != owned.appliedFrozen
                || _upstreamRestricted(commandId, account) != owned.restricted
        ) {
            revert TrustOperationalFailure(commandId, REASON_UPSTREAM_STATE_NOT_OWNED, _addressRef(account));
        }
    }

    // ---------------------------------------------------------------------
    // State transitions and receipts
    // ---------------------------------------------------------------------

    function _consumeActionAuthorization(
        TrustKernelTypes.ActionRequest calldata request,
        bytes32 digest,
        bytes32 evidence
    ) internal {
        _usedNonces[_nonceKey(request.authorityRef, request.authorityEpoch, request.nonce)] = true;
        _actions[request.actionId] = TrustKernelTypes.ActionRecord({
            action: request.action,
            lifecycle: TrustKernelTypes.Lifecycle.PREPARED,
            subject: request.subject,
            source: request.source,
            destination: request.destination,
            custodian: request.custodian,
            amount: request.amount,
            priorAmount: 0,
            priorFlag: false,
            caseId: request.caseId,
            authorityRef: request.authorityRef,
            authorityEpoch: request.authorityEpoch,
            dependencyEpoch: request.dependencyEpoch,
            commandHash: digest,
            evidenceHash: evidence,
            receiptHash: bytes32(0)
        });
    }

    function _applyActionPrepared(TrustKernelTypes.ActionRequest memory request)
        internal
        returns (bytes32 receiptHash)
    {
        TrustKernelTypes.ActionRecord storage record = _actions[request.actionId];
        if (record.lifecycle != TrustKernelTypes.Lifecycle.PREPARED) revert TrustReplay(request.actionId);
        TrustKernelTypes.CaseRecord storage caseState = _cases[request.caseId];
        bytes32 preState =
            _observation(request.actionId, request.subject, request.source, request.destination, request.caseId);

        if (request.action == TrustKernelTypes.ActionKind.FREEZE) {
            ERC3643ProfileTypes.OwnedState storage owned = _owned[request.subject];
            record.priorAmount = owned.frozenTarget;
            _pushEffect(request.actionId, record, _freezeHeads[request.subject]);
            owned.frozenTarget = request.amount;
            _syncFrozen(request.actionId, request.subject);
            _openOverlay(caseState, TrustKernelTypes.CaseFamily.FREEZE, request.actionId);
        } else if (request.action == TrustKernelTypes.ActionKind.RESTRICT) {
            record.priorFlag = _owned[request.subject].restricted;
            _pushEffect(request.actionId, record, _restrictionHeads[request.subject]);
            _setRestricted(request.actionId, request.subject, true);
            _openOverlay(caseState, TrustKernelTypes.CaseFamily.RESTRICT, request.actionId);
        } else if (request.action == TrustKernelTypes.ActionKind.SEIZE) {
            _requireUnbacked(request.actionId, request.source, request.amount);
            _forcedTransfer(request.actionId, request.source, request.custodian, request.amount);
            _custody[request.caseId] = ERC3643ProfileTypes.CustodyRecord({
                custodian: request.custodian,
                declaredPriorHolder: request.source,
                encumberedAmount: request.amount,
                actionId: request.actionId,
                active: true
            });
            _custodyBacking[request.custodian] += request.amount;
            caseState.phase = TrustKernelTypes.CasePhase.OPEN;
            caseState.family = TrustKernelTypes.CaseFamily.CUSTODY;
            caseState.headActionId = request.actionId;
        } else {
            bool consumedCustody = _consumeMatchingCustody(request);
            if (!consumedCustody) _requireUnbacked(request.actionId, request.source, request.amount);
            _forcedTransfer(request.actionId, request.source, request.destination, request.amount);
            if (request.action == TrustKernelTypes.ActionKind.RECOVER) {
                _consumedEntitlements[request.entitlementCommitment] = true;
            }
            if (!consumedCustody) caseState.family = TrustKernelTypes.CaseFamily.DISPOSITION;
            caseState.phase = TrustKernelTypes.CasePhase.TERMINAL;
            caseState.headActionId = bytes32(0);
        }
        caseState.generation += 1;

        record.lifecycle = TrustKernelTypes.Lifecycle.APPLIED;
        bytes32 postState =
            _observation(request.actionId, request.subject, request.source, request.destination, request.caseId);
        bytes32 externalCommitment = request.action == TrustKernelTypes.ActionKind.LIQUIDATE
            ? keccak256(abi.encode(request.settlementCommitment, request.proceedsCommitment))
            : request.action == TrustKernelTypes.ActionKind.RECOVER ? request.entitlementCommitment : bytes32(0);
        receiptHash = _storeReceipt(
            TrustKernelTypes.Receipt({
                receiptKind: TrustKernelTypes.ReceiptKind.ACTION,
                commandId: request.actionId,
                commandKind: uint8(request.action),
                parentCommandId: bytes32(0),
                subject: request.subject,
                source: request.source,
                destination: request.destination,
                amount: request.amount,
                caseId: request.caseId,
                authorityRef: request.authorityRef,
                dependencyRoot: request.dependencyRoot,
                provenanceCommitment: request.provenanceCommitment,
                assessmentEvidence: record.evidenceHash,
                preState: preState,
                postState: postState,
                externalCommitment: externalCommitment,
                receiptHash: bytes32(0)
            })
        );
        record.receiptHash = receiptHash;
        emit RegulatoryActionApplied(request.actionId, uint8(request.action), request.caseId, receiptHash);
    }

    function _applyReversalPrepared(TrustKernelTypes.ReversalRequest calldata request, bytes32 evidence)
        internal
        returns (bytes32 receiptHash)
    {
        TrustKernelTypes.ActionRecord storage original = _actions[request.actionId];
        TrustKernelTypes.CaseRecord storage caseState = _cases[original.caseId];
        bytes32 preState =
            _observation(request.reversalId, original.subject, original.source, original.destination, original.caseId);
        address source;
        address destination;

        if (request.reversal == TrustKernelTypes.ReversalKind.UNFREEZE) {
            bytes32 parent = _popEffect(_effects[request.actionId], _freezeHeads[original.subject]);
            _owned[original.subject].frozenTarget = original.priorAmount;
            _syncFrozen(request.reversalId, original.subject);
            source = original.subject;
            destination = original.subject;
            if (parent != bytes32(0)) {
                caseState.headActionId = parent;
            } else {
                _closeCase(caseState);
            }
        } else if (request.reversal == TrustKernelTypes.ReversalKind.UNRESTRICT) {
            _popEffect(_effects[request.actionId], _restrictionHeads[original.subject]);
            _setRestricted(request.reversalId, original.subject, original.priorFlag);
            source = original.subject;
            destination = original.subject;
            _closeCase(caseState);
        } else {
            ERC3643ProfileTypes.CustodyRecord storage custody = _custody[original.caseId];
            _custodyBacking[custody.custodian] -= original.amount;
            custody.active = false;
            custody.encumberedAmount = 0;
            source = custody.custodian;
            destination = custody.declaredPriorHolder;
            _forcedTransfer(request.reversalId, source, destination, original.amount);
            _closeCase(caseState);
        }
        caseState.generation += 1;

        original.lifecycle = TrustKernelTypes.Lifecycle.REVERSED;
        bytes32 postState =
            _observation(request.reversalId, original.subject, original.source, original.destination, original.caseId);
        receiptHash = _storeReceipt(
            TrustKernelTypes.Receipt({
                receiptKind: TrustKernelTypes.ReceiptKind.REVERSAL,
                commandId: request.reversalId,
                commandKind: uint8(request.reversal),
                parentCommandId: request.actionId,
                subject: original.subject,
                source: source,
                destination: destination,
                amount: original.amount,
                caseId: original.caseId,
                authorityRef: request.authorityRef,
                dependencyRoot: request.dependencyRoot,
                provenanceCommitment: request.provenanceCommitment,
                assessmentEvidence: evidence,
                preState: preState,
                postState: postState,
                externalCommitment: bytes32(0),
                receiptHash: bytes32(0)
            })
        );
        emit RegulatoryReversalApplied(request.reversalId, uint8(request.reversal), request.actionId, receiptHash);
    }

    /// @dev hashes.receiptHash: keccak256 of the domain followed by every receipt field except
    ///      receiptHash, in schema order. The memory struct holds those sixteen fields as sixteen
    ///      consecutive words, which is exactly their canonical ABI encoding.
    function _storeReceipt(TrustKernelTypes.Receipt memory record) internal returns (bytes32 receiptHash) {
        bytes32 domain = TrustKernelTypes.DOMAIN;
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(ptr, domain)
            mcopy(add(ptr, 0x20), record, 0x200)
            receiptHash := keccak256(ptr, 0x220)
        }
        record.receiptHash = receiptHash;
        _receipts[record.commandId] = record;
    }

    function _openOverlay(
        TrustKernelTypes.CaseRecord storage caseState,
        TrustKernelTypes.CaseFamily family,
        bytes32 actionId
    ) internal {
        if (caseState.phase == TrustKernelTypes.CasePhase.NONE) {
            caseState.phase = TrustKernelTypes.CasePhase.OPEN;
            caseState.family = family;
        }
        caseState.headActionId = actionId;
    }

    function _closeCase(TrustKernelTypes.CaseRecord storage caseState) internal {
        caseState.phase = TrustKernelTypes.CasePhase.TERMINAL;
        caseState.headActionId = bytes32(0);
    }

    function _consumeMatchingCustody(TrustKernelTypes.ActionRequest memory request) internal returns (bool consumed) {
        ERC3643ProfileTypes.CustodyRecord storage custody = _custody[request.caseId];
        if (!custody.active) return false;
        if (
            custody.custodian != request.source || custody.encumberedAmount != request.amount
                || custody.declaredPriorHolder != request.subject
                || _custodyBacking[custody.custodian] < custody.encumberedAmount
        ) {
            revert TrustInvalidCommand(request.actionId, REASON_CUSTODY);
        }
        _custodyBacking[custody.custodian] -= custody.encumberedAmount;
        custody.active = false;
        custody.encumberedAmount = 0;
        return true;
    }

    function _pushEffect(
        bytes32 actionId,
        TrustKernelTypes.ActionRecord storage record,
        ERC3643ProfileTypes.EffectHead storage head
    ) internal {
        ERC3643ProfileTypes.EffectRecord storage effect = _effects[actionId];
        effect.parentActionId = head.actionId;
        effect.generation = head.generation + 1;
        effect.effectHash = _effectHash(record, effect);
        head.actionId = actionId;
        head.effectHash = effect.effectHash;
        head.generation = effect.generation;
    }

    /// @dev Pops the subject's live head back to the reversed action's parent and returns that parent.
    function _popEffect(
        ERC3643ProfileTypes.EffectRecord storage originalEffect,
        ERC3643ProfileTypes.EffectHead storage head
    ) internal returns (bytes32 parent) {
        parent = originalEffect.parentActionId;
        head.actionId = parent;
        head.effectHash = parent == bytes32(0) ? bytes32(0) : _effects[parent].effectHash;
        head.generation += 1;
    }

    function _effectHash(TrustKernelTypes.ActionRecord storage record, ERC3643ProfileTypes.EffectRecord storage effect)
        internal
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                record.commandHash, effect.parentActionId, effect.generation, record.priorAmount, record.priorFlag
            )
        );
    }

    // ---------------------------------------------------------------------
    // Import of declared upstream state
    // ---------------------------------------------------------------------

    /// @dev Verifies one manifest entry against the live upstream state, takes ownership of it, and opens
    ///      one imported case per declared family.
    function _importEntry(ERC3643ProfileTypes.ImportEntry calldata entry, bytes32 manifestHash) internal {
        if (
            _upstreamFrozen(bytes32(0), entry.account) != entry.frozenAmount
                || _upstreamRestricted(bytes32(0), entry.account) != entry.restricted
        ) {
            revert TrustOperationalFailure(bytes32(0), REASON_IMPORT_MANIFEST_MISMATCH, _addressRef(entry.account));
        }
        ERC3643ProfileTypes.OwnedState storage owned = _owned[entry.account];
        owned.frozenTarget = entry.frozenAmount;
        owned.appliedFrozen = entry.frozenAmount;
        owned.restricted = entry.restricted;
        if (entry.frozenAmount != 0) {
            _openImportedCase(
                entry, manifestHash, TrustKernelTypes.CaseFamily.FREEZE, TrustKernelTypes.ActionKind.FREEZE
            );
        }
        if (entry.restricted) {
            _openImportedCase(
                entry, manifestHash, TrustKernelTypes.CaseFamily.RESTRICT, TrustKernelTypes.ActionKind.RESTRICT
            );
        }
    }

    function _openImportedCase(
        ERC3643ProfileTypes.ImportEntry calldata entry,
        bytes32 manifestHash,
        TrustKernelTypes.CaseFamily family,
        TrustKernelTypes.ActionKind action
    ) internal {
        bytes32 caseId = keccak256(
            abi.encode(TrustKernelTypes.DOMAIN, IMPORT_TAG, manifestHash, entry.account, uint8(family))
        );
        bytes32 actionId = keccak256(abi.encode(TrustKernelTypes.DOMAIN, IMPORT_TAG, caseId));
        TrustKernelTypes.ActionRecord storage record = _actions[actionId];
        record.action = action;
        record.lifecycle = TrustKernelTypes.Lifecycle.APPLIED;
        record.subject = entry.account;
        record.source = entry.account;
        record.amount = family == TrustKernelTypes.CaseFamily.FREEZE ? entry.frozenAmount : 0;
        record.caseId = caseId;
        record.dependencyEpoch = SEAL_EPOCH;
        _pushEffect(
            actionId,
            record,
            family == TrustKernelTypes.CaseFamily.FREEZE
                ? _freezeHeads[entry.account]
                : _restrictionHeads[entry.account]
        );
        TrustKernelTypes.CaseRecord storage caseState = _cases[caseId];
        _openOverlay(caseState, family, actionId);
        caseState.generation += 1;
        emit RegulatoryStateImported(caseId, actionId, entry.account, uint8(family), record.amount, entry.restricted);
    }

    // ---------------------------------------------------------------------
    // Upstream execution with exact post-state verification
    // ---------------------------------------------------------------------

    /// @dev Moves `amount` through the Agent forced transfer and verifies both balances, then brings
    ///      the frozen amount of both accounts back to their owned targets.
    function _forcedTransfer(bytes32 commandId, address from, address to, uint256 amount) internal {
        uint256 beforeFrom = _upstreamBalance(commandId, from);
        uint256 beforeTo = _upstreamBalance(commandId, to);
        (bool ok, bytes memory result) =
            token.call(abi.encodeCall(IERC3643TokenMutator.forcedTransfer, (from, to, amount)));
        if (!ok || result.length != 32 || abi.decode(result, (uint256)) != 1) {
            revert TrustOperationalFailure(commandId, REASON_UPSTREAM_CALL_FAILED, _tokenRef());
        }
        if (
            beforeFrom < amount || _upstreamBalance(commandId, from) != beforeFrom - amount
                || _upstreamBalance(commandId, to) != beforeTo + amount
        ) {
            revert TrustOperationalFailure(commandId, REASON_UPSTREAM_POSTSTATE_MISMATCH, _tokenRef());
        }
        _syncFrozen(commandId, from);
        _syncFrozen(commandId, to);
    }

    /// @dev Brings the upstream frozen amount of `account` to its owned target saturated at the current
    ///      balance, verifies it, and records the applied value.
    function _syncFrozen(bytes32 commandId, address account) internal {
        ERC3643ProfileTypes.OwnedState storage owned = _owned[account];
        uint256 balance = _upstreamBalance(commandId, account);
        uint256 expected = owned.frozenTarget > balance ? balance : owned.frozenTarget;
        uint256 current = _upstreamFrozen(commandId, account);
        if (expected > current) {
            _callVoid(
                commandId, abi.encodeCall(IERC3643TokenMutator.freezePartialTokens, (account, expected - current))
            );
        } else if (current > expected) {
            _callVoid(
                commandId, abi.encodeCall(IERC3643TokenMutator.unfreezePartialTokens, (account, current - expected))
            );
        }
        if (_upstreamFrozen(commandId, account) != expected) {
            revert TrustOperationalFailure(commandId, REASON_UPSTREAM_POSTSTATE_MISMATCH, _tokenRef());
        }
        owned.appliedFrozen = expected;
    }

    function _setRestricted(bytes32 commandId, address account, bool flag) internal {
        _owned[account].restricted = flag;
        _callVoid(commandId, abi.encodeCall(IERC3643TokenMutator.setAddressFrozen, (account, flag)));
        if (_upstreamRestricted(commandId, account) != flag) {
            revert TrustOperationalFailure(commandId, REASON_UPSTREAM_POSTSTATE_MISMATCH, _tokenRef());
        }
    }

    function _callVoid(bytes32 commandId, bytes memory data) internal {
        (bool ok, bytes memory result) = token.call(data);
        if (!ok || result.length != 0) {
            revert TrustOperationalFailure(commandId, REASON_UPSTREAM_CALL_FAILED, _tokenRef());
        }
    }

    function _requireUnbacked(bytes32 commandId, address account, uint256 amount) internal view {
        uint256 balance = _upstreamBalance(commandId, account);
        uint256 backing = _custodyBacking[account];
        if (balance < backing || amount > balance - backing) revert TrustInvalidCommand(commandId, REASON_CUSTODY);
    }

    // ---------------------------------------------------------------------
    // Typed upstream reads
    // ---------------------------------------------------------------------

    function _upstreamBalance(bytes32 commandId, address account) internal view returns (uint256) {
        return _upstreamWord(commandId, abi.encodeCall(IERC3643TokenView.balanceOf, (account)), type(uint256).max);
    }

    function _upstreamFrozen(bytes32 commandId, address account) internal view returns (uint256) {
        return _upstreamWord(commandId, abi.encodeCall(IERC3643TokenView.getFrozenTokens, (account)), type(uint256).max);
    }

    function _upstreamRestricted(bytes32 commandId, address account) internal view returns (bool) {
        return _upstreamWord(commandId, abi.encodeCall(IERC3643TokenView.isFrozen, (account)), 1) == 1;
    }

    /// @dev A revert, a return of any length other than 32 bytes, or a word above `maxValue` is an
    ///      upstream call failure (reason 400).
    function _upstreamWord(bytes32 commandId, bytes memory data, uint256 maxValue)
        internal
        view
        returns (uint256 word)
    {
        (bool ok, uint256 value) = _staticWord(token, data);
        if (!ok || value > maxValue) {
            revert TrustOperationalFailure(commandId, REASON_UPSTREAM_CALL_FAILED, _tokenRef());
        }
        word = value;
    }

    function _staticWord(address target, bytes memory data) internal view returns (bool ok, uint256 word) {
        bytes memory result;
        (ok, result) = target.staticcall{gas: UPSTREAM_VIEW_GAS}(data);
        if (!ok || result.length != 32) return (false, 0);
        word = abi.decode(result, (uint256));
    }

    // ---------------------------------------------------------------------
    // Bindings, hashes, and observation
    // ---------------------------------------------------------------------

    /// @dev Profile binding: the native bindingHash preimage with the sealed binding as the configuration
    ///      digest, the profile identifier as the schema, and the seal epoch.
    function _bind(TrustKernelTypes.BindingKind kind, address dependency, bytes32 sealedBinding) internal {
        bytes32 code = dependency.codehash;
        if (dependency == address(0) || code == bytes32(0)) {
            revert TrustOperationalFailure(bytes32(0), REASON_DEPENDENCY_UNAVAILABLE_AT_BIND, _addressRef(dependency));
        }
        _bindings[kind] = ERC3643ProfileTypes.DependencyBinding({
            dependency: dependency,
            codeId: code,
            bindingHash: keccak256(
                abi.encode(
                    TrustKernelTypes.DOMAIN,
                    uint8(kind),
                    dependency,
                    code,
                    sealedBinding,
                    TrustKernelTypes.PROFILE_ERC3643_VERIFIED_FULL,
                    SEAL_EPOCH
                )
            )
        });
    }

    function _bindingLive(TrustKernelTypes.BindingKind kind) internal view returns (bool) {
        ERC3643ProfileTypes.DependencyBinding storage binding = _bindings[kind];
        return binding.dependency != address(0) && binding.dependency.codehash == binding.codeId;
    }

    /// @dev hashes.dependencyRoot: ordered by BindingKind and tagged. The profile has no settlement or
    ///      entitlement dependency, so those slots are zero.
    function _computeDependencyRoot() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                TrustKernelTypes.DOMAIN,
                TrustKernelTypes.DEPENDENCY_ROOT_TAG,
                _bindings[TrustKernelTypes.BindingKind.POLICY].bindingHash,
                _bindings[TrustKernelTypes.BindingKind.IDENTITY].bindingHash,
                bytes32(0),
                bytes32(0)
            )
        );
    }

    /// @dev hashes.nonceKey.
    function _nonceKey(bytes32 ref, uint64 epoch, uint256 nonce) internal pure returns (bytes32) {
        return keccak256(abi.encode(TrustKernelTypes.DOMAIN, ref, epoch, nonce));
    }

    /// @dev shapeRules.reversal.pairing.
    function _reversalMatches(TrustKernelTypes.ActionKind action, TrustKernelTypes.ReversalKind reversal)
        internal
        pure
        returns (bool)
    {
        return (action == TrustKernelTypes.ActionKind.FREEZE && reversal == TrustKernelTypes.ReversalKind.UNFREEZE)
            || (action == TrustKernelTypes.ActionKind.SEIZE && reversal == TrustKernelTypes.ReversalKind.RELEASE)
            || (action == TrustKernelTypes.ActionKind.RESTRICT && reversal == TrustKernelTypes.ReversalKind.UNRESTRICT);
    }

    /// @dev hashes.actionId (clearId) and hashes.commandHash over the raw calldata words, which equal
    ///      the canonical encoding because every accepted request is canonical.
    function _actionHash(TrustKernelTypes.ActionRequest calldata request, bool clearId)
        internal
        view
        returns (bytes32 result)
    {
        bytes32 domain = TrustKernelTypes.DOMAIN;
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(ptr, domain)
            mstore(add(ptr, 0x20), address())
            mstore(add(ptr, 0x40), chainid())
            calldatacopy(add(ptr, 0x60), request, 0x280)
            if clearId { mstore(add(ptr, 0x80), 0) }
            result := keccak256(ptr, 0x2e0)
        }
    }

    function _reversalHash(TrustKernelTypes.ReversalRequest calldata request, bool clearId)
        internal
        view
        returns (bytes32 result)
    {
        bytes32 domain = TrustKernelTypes.DOMAIN;
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(ptr, domain)
            mstore(add(ptr, 0x20), address())
            mstore(add(ptr, 0x40), chainid())
            calldatacopy(add(ptr, 0x60), request, 0x180)
            if clearId { mstore(add(ptr, 0x80), 0) }
            result := keccak256(ptr, 0x1e0)
        }
    }

    /// @dev Profile-defined observation preimage documented with the runtime identity: the token, the
    ///      subject's balance, owned frozen target, upstream frozen amount, and owned restriction flag,
    ///      the source's and destination's balance and custody backing, the case's custody record, the
    ///      subject's overlay heads, the case record, and the sealed binding.
    function _observation(bytes32 commandId, address subject, address source, address destination, bytes32 caseId)
        internal
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                token,
                subject,
                _upstreamBalance(commandId, subject),
                _owned[subject].frozenTarget,
                _upstreamFrozen(commandId, subject),
                _owned[subject].restricted,
                source,
                _upstreamBalance(commandId, source),
                _custodyBacking[source],
                destination,
                destination == address(0) ? 0 : _upstreamBalance(commandId, destination),
                _custodyBacking[destination],
                _custody[caseId],
                _freezeHeads[subject],
                _restrictionHeads[subject],
                _cases[caseId],
                _sealedBinding
            )
        );
    }

    function _requireCalldataLength(uint256 expected) internal pure {
        assembly ("memory-safe") {
            if xor(calldatasize(), expected) { revert(0, 0) }
        }
    }

    function _tokenRef() internal view returns (bytes32) {
        return bytes32(uint256(uint160(token)));
    }

    function _addressRef(address account) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(account)));
    }
}
