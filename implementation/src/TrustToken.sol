// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {IERC20} from "./interfaces/IERC20.sol";
import {IERC7943Fungible} from "./interfaces/IERC7943.sol";
import {IERCTrustKernel, IERCTrustNativeRoute, TrustKernelTypes} from "./generated/IERCTrustKernel.sol";
import {TrustNativeTypes} from "./TrustNativeTypes.sol";
import {TrustNativeDecision} from "./TrustNativeDecision.sol";
import {TrustStorage} from "./TrustStorage.sol";
import {TrustDependencyBinding} from "./TrustDependencyBinding.sol";
import {ERC7943RouteTicket} from "./ERC7943RouteTicket.sol";
import {
    TrustReentrancy,
    TrustUnsupported,
    TrustZeroAddress,
    TrustInsufficientBalance,
    TrustInsufficientAllowance
} from "./TrustErrors.sol";

/// @notice Immutable, unaudited ERC-TRUST native reference candidate implementing kernel version 2.
/// @dev No proxy, delegatecall, selfdestruct, public mint, or public burn surface exists. The kernel
///      types and interfaces are consumed from the generated copy of the normative machine source.
contract TrustToken is TrustStorage, IERC20, IERC7943Fungible, IERCTrustKernel, IERCTrustNativeRoute {
    using TrustDependencyBinding for TrustNativeTypes.Binding;

    bytes4 internal constant ERC165_INTERFACE_ID = 0x01ffc9a7;
    bytes4 internal constant ERC7943_FUNGIBLE_INTERFACE_ID = 0x3edbb4c4;
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
    uint16 internal constant REASON_DEPENDENCY_UNAVAILABLE_AT_BIND = 205;
    uint8 internal constant REVERSAL_OPERATION_TAG = 0x80;
    uint256 internal constant ACTION_CALLDATA_LENGTH = 644;
    uint256 internal constant REVERSAL_CALLDATA_LENGTH = 388;
    uint256 internal constant NATIVE_ACTION_MASK = 0x3f;
    uint256 internal constant NATIVE_REVERSAL_MASK = 0x07;

    modifier nonReentrant() {
        if (_entered != 0) revert TrustReentrancy();
        _entered = 1;
        _;
        _entered = 0;
    }

    modifier onlyGovernor() {
        if (msg.sender != governor) revert TrustUnauthorized(msg.sender, bytes32(0));
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address governor_,
        address initialHolder,
        uint256 initialSupply,
        bytes32 authorityRef,
        address initialAuthority,
        address policy,
        address identity,
        address settlement,
        address entitlement,
        bytes32 schema
    ) {
        if (governor_ == address(0) || initialHolder == address(0) || initialAuthority == address(0)) {
            revert TrustZeroAddress();
        }
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
        governor = governor_;
        _authorities[authorityRef] = TrustNativeTypes.Authority({account: initialAuthority, epoch: 1, active: true});
        emit TrustAuthorityChanged(authorityRef, initialAuthority, 1, true);

        _bind(TrustKernelTypes.BindingKind.POLICY, policy, schema, 1, bytes32(0));
        _bind(TrustKernelTypes.BindingKind.IDENTITY, identity, schema, 1, bytes32(0));
        _bind(TrustKernelTypes.BindingKind.SETTLEMENT, settlement, schema, 1, bytes32(0));
        _bind(TrustKernelTypes.BindingKind.ENTITLEMENT, entitlement, schema, 1, bytes32(0));
        _dependencyEpoch = 1;
        _dependencyRoot = _computeDependencyRoot();
        for (uint8 kind = 0; kind < 4; ++kind) {
            emit TrustDependencyChanged(
                kind, bytes32(0), _bindings[TrustKernelTypes.BindingKind(kind)].bindingHash, _dependencyRoot, 1
            );
        }

        _totalSupply = initialSupply;
        _balances[initialHolder] = initialSupply;
        emit Transfer(address(0), initialHolder, initialSupply);
    }

    // ---------------------------------------------------------------------
    // ERC-165 / ERC-20 / ERC-7943 views
    // ---------------------------------------------------------------------

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId != 0xffffffff
            && (interfaceId == ERC165_INTERFACE_ID
                || interfaceId == ERC7943_FUNGIBLE_INTERFACE_ID
                || interfaceId == type(IERCTrustKernel).interfaceId
                || interfaceId == type(IERCTrustNativeRoute).interfaceId);
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 value) external returns (bool) {
        if (spender == address(0)) revert TrustZeroAddress();
        _allowances[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external nonReentrant returns (bool) {
        _ordinaryTransfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external nonReentrant returns (bool) {
        uint256 current = _allowances[from][msg.sender];
        if (current < value) revert TrustInsufficientAllowance(from, msg.sender, current, value);
        if (current != type(uint256).max) {
            _allowances[from][msg.sender] = current - value;
            emit Approval(from, msg.sender, current - value);
        }
        _ordinaryTransfer(from, to, value);
        return true;
    }

    function canSend(address account) public view returns (bool) {
        return account != address(0) && !_restricted[account];
    }

    function canReceive(address account) public view returns (bool) {
        return account != address(0) && !_restricted[account];
    }

    /// @dev The stored absolute target may exceed the balance after a disposition in another case;
    ///      the observed frozen amount saturates at the current balance.
    function getFrozenTokens(address account) external view returns (uint256) {
        uint256 frozen = _frozen[account];
        uint256 balance = _balances[account];
        return frozen > balance ? balance : frozen;
    }

    function canTransfer(address from, address to, uint256 amount) public view returns (bool) {
        if (!canSend(from) || !canReceive(to)) return false;
        return amount <= _ordinaryAvailable(from);
    }

    // ---------------------------------------------------------------------
    // Kernel views
    // ---------------------------------------------------------------------

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

    /// @dev `full` is computed from the live dependency topology on every call, never stored.
    function trustProfile() external view returns (TrustKernelTypes.ProfileDescriptor memory descriptor) {
        bool full = true;
        for (uint8 kind = 0; kind < 4; ++kind) {
            if (!_bindings[TrustKernelTypes.BindingKind(kind)].live()) {
                full = false;
                break;
            }
        }
        descriptor = TrustKernelTypes.ProfileDescriptor({
            profileId: TrustKernelTypes.PROFILE_NATIVE_FULL,
            profileKind: TrustKernelTypes.ProfileKind.NATIVE_FULL,
            standardVersion: TrustKernelTypes.STANDARD_VERSION,
            actionMask: NATIVE_ACTION_MASK,
            reversalMask: NATIVE_REVERSAL_MASK,
            underlyingToken: address(0),
            manifestHash: _dependencyRoot,
            full: full,
            proxySupported: false
        });
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
        bytes32 evidence = _assessOrRevert(request, digest);
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
        bytes32 evidence = _assessReversalOrRevert(request, digest);
        _consumeReversalAuthorization(request);
        return _applyReversalPrepared(request.reversalId, _pendingReversalOf(request, evidence));
    }

    /// @notice Same-transaction exact-use route for the sensitive ERC-7943 selectors.
    function executeERC7943Action(TrustKernelTypes.ActionRequest calldata request)
        external
        nonReentrant
        returns (bytes32 receiptHash)
    {
        _requireCalldataLength(ACTION_CALLDATA_LENGTH);
        bytes32 digest = _validateAndAuthorizeAction(request, msg.sender);
        if (request.action == TrustKernelTypes.ActionKind.RESTRICT) {
            revert TrustInvalidCommand(request.actionId, REASON_SHAPE);
        }
        bytes32 evidence = _assessOrRevert(request, digest);
        _consumeActionAuthorization(request, digest, evidence);
        _pendingCommitments[request.actionId] = TrustNativeTypes.PendingCommitments({
            provenanceCommitment: request.provenanceCommitment,
            settlementCommitment: request.settlementCommitment,
            proceedsCommitment: request.proceedsCommitment,
            entitlementCommitment: request.entitlementCommitment
        });

        bytes memory data;
        bytes4 selector;
        if (request.action == TrustKernelTypes.ActionKind.FREEZE) {
            data = abi.encodeCall(IERC7943Fungible.setFrozenTokens, (request.subject, request.amount));
            selector = IERC7943Fungible.setFrozenTokens.selector;
        } else {
            data =
                abi.encodeCall(IERC7943Fungible.forcedTransfer, (request.source, request.destination, request.amount));
            selector = IERC7943Fungible.forcedTransfer.selector;
        }
        _prepareRoute(request.actionId, selector, keccak256(data), TrustNativeTypes.RouteKind.ACTION);
        (bool ok, bytes memory result) = address(this).call(data);
        if (!ok) _bubble(result);
        return _receipts[request.actionId].receiptHash;
    }

    function executeERC7943Reversal(TrustKernelTypes.ReversalRequest calldata request)
        external
        nonReentrant
        returns (bytes32 receiptHash)
    {
        _requireCalldataLength(REVERSAL_CALLDATA_LENGTH);
        bytes32 digest = _validateAndAuthorizeReversal(request, msg.sender);
        if (request.reversal != TrustKernelTypes.ReversalKind.UNFREEZE) {
            revert TrustInvalidCommand(request.reversalId, REASON_REVERSAL_PAIRING);
        }
        bytes32 evidence = _assessReversalOrRevert(request, digest);
        _consumeReversalAuthorization(request);
        _pendingReversals[request.reversalId] = _pendingReversalOf(request, evidence);
        TrustKernelTypes.ActionRecord storage original = _actions[request.actionId];
        bytes memory data = abi.encodeCall(IERC7943Fungible.setFrozenTokens, (original.subject, original.priorAmount));
        _prepareRoute(
            request.reversalId,
            IERC7943Fungible.setFrozenTokens.selector,
            keccak256(data),
            TrustNativeTypes.RouteKind.REVERSAL
        );
        (bool ok, bytes memory result) = address(this).call(data);
        if (!ok) _bubble(result);
        return _receipts[request.reversalId].receiptHash;
    }

    /// @dev Raw calls always fail: a ticket can only exist during an executing wrapper call.
    function setFrozenTokens(address account, uint256 amount) external returns (bool result) {
        TrustNativeTypes.RouteTicket memory ticket =
            _consumeRoute(IERC7943Fungible.setFrozenTokens.selector, keccak256(msg.data));
        if (ticket.routeKind == TrustNativeTypes.RouteKind.ACTION) {
            TrustKernelTypes.ActionRecord storage record = _actions[ticket.commandId];
            if (
                record.action != TrustKernelTypes.ActionKind.FREEZE || record.subject != account
                    || record.amount != amount
            ) {
                revert TrustRouteMismatch(_routeId());
            }
            _applyActionPrepared(_requestFromRecord(ticket.commandId, record));
            return true;
        }
        if (ticket.routeKind == TrustNativeTypes.RouteKind.REVERSAL) {
            TrustNativeTypes.PendingReversal memory pending = _pendingReversals[ticket.commandId];
            TrustKernelTypes.ActionRecord storage original = _actions[pending.actionId];
            if (original.subject != account || original.priorAmount != amount) {
                revert TrustRouteMismatch(_routeId());
            }
            delete _pendingReversals[ticket.commandId];
            _applyReversalPrepared(ticket.commandId, pending);
            return true;
        }
        revert TrustRouteMismatch(_routeId());
    }

    function forcedTransfer(address from, address to, uint256 amount) external returns (bool result) {
        TrustNativeTypes.RouteTicket memory ticket =
            _consumeRoute(IERC7943Fungible.forcedTransfer.selector, keccak256(msg.data));
        if (ticket.routeKind != TrustNativeTypes.RouteKind.ACTION) revert TrustRouteMismatch(_routeId());
        TrustKernelTypes.ActionRecord storage record = _actions[ticket.commandId];
        if (
            !TrustNativeDecision.isForcedTransferAction(record.action) || record.source != from
                || record.destination != to || record.amount != amount
        ) {
            revert TrustRouteMismatch(_routeId());
        }
        _applyActionPrepared(_requestFromRecord(ticket.commandId, record));
        return true;
    }

    // ---------------------------------------------------------------------
    // Governance and versioned dependency bindings
    // ---------------------------------------------------------------------

    function configureAuthority(
        bytes32 authorityRef,
        address account,
        bool active,
        bytes32 governanceAuthorizationId,
        uint256 governanceNonce
    ) external onlyGovernor {
        _consumeGovernance(governanceAuthorizationId, governanceNonce);
        if (account == address(0)) revert TrustZeroAddress();
        TrustNativeTypes.Authority storage authorityConfig = _authorities[authorityRef];
        authorityConfig.epoch += 1;
        authorityConfig.account = account;
        authorityConfig.active = active;
        emit TrustAuthorityChanged(authorityRef, account, authorityConfig.epoch, active);
    }

    /// @dev Every rebind of any kind advances the global dependency epoch by exactly one and
    ///      recomputes the ordered dependency root, so commands built under the previous root are stale.
    function rebindDependency(
        TrustKernelTypes.BindingKind kind,
        address dependency,
        bytes32 schema,
        bytes32 governanceAuthorizationId,
        uint256 governanceNonce
    ) external onlyGovernor {
        _consumeGovernance(governanceAuthorizationId, governanceNonce);
        TrustNativeTypes.Binding storage bindingConfig = _bindings[kind];
        bytes32 previous = bindingConfig.bindingHash;
        _bind(kind, dependency, schema, bindingConfig.epoch + 1, governanceAuthorizationId);
        _dependencyEpoch += 1;
        _dependencyRoot = _computeDependencyRoot();
        emit TrustDependencyChanged(uint8(kind), previous, bindingConfig.bindingHash, _dependencyRoot, _dependencyEpoch);
    }

    // ---------------------------------------------------------------------
    // Validation and assessment
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
        if (!TrustNativeDecision.reversalMatches(original.action, request.reversal)) {
            revert TrustInvalidCommand(request.reversalId, REASON_REVERSAL_PAIRING);
        }
        _validateCurrentEffect(request.reversalId, request.actionId, request.reversal, original);
        digest = _reversalHash(request, false);
    }

    function _requireAuthority(bytes32 commandId, bytes32 authorityRef, uint64 authorityEpoch, address caller)
        internal
        view
    {
        TrustNativeTypes.Authority storage authority_ = _authorities[authorityRef];
        if (authority_.epoch != authorityEpoch) revert TrustInvalidCommand(commandId, REASON_AUTHORITY_EPOCH);
        if (!authority_.active || caller != authority_.account) revert TrustUnauthorized(caller, authorityRef);
    }

    function _requireFreshNonce(bytes32 authorityRef, uint64 authorityEpoch, uint256 nonce) internal view {
        if (_usedNonces[authorityRef][authorityEpoch][nonce]) {
            revert TrustReplay(TrustNativeDecision.nonceKey(authorityRef, authorityEpoch, nonce));
        }
    }

    /// @dev Per-action field rules and the case transition table. Reason codes follow shapeRules.
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
            if (request.amount <= _frozen[request.subject]) {
                revert TrustInvalidCommand(request.actionId, REASON_FREEZE_DIRECTION);
            }
        } else if (action == TrustKernelTypes.ActionKind.RESTRICT) {
            if (
                request.source != request.subject || request.destination != address(0)
                    || request.custodian != address(0) || request.amount != 0
            ) {
                revert TrustInvalidCommand(request.actionId, REASON_SHAPE);
            }
            TrustNativeTypes.EffectHead storage head = _restrictionHeads[request.subject];
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
                    request.subject != request.source || request.custodian == address(0)
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
        TrustNativeTypes.EffectHead storage head
    ) internal view {
        if (head.actionId == bytes32(0)) {
            if (caseState.phase != TrustKernelTypes.CasePhase.NONE) {
                revert TrustInvalidCommand(actionId, REASON_CASE_CONFLICT);
            }
        } else if (caseState.headActionId != head.actionId) {
            revert TrustInvalidCommand(actionId, REASON_CASE_CONFLICT);
        }
    }

    function _assessOrRevert(TrustKernelTypes.ActionRequest calldata request, bytes32 digest)
        internal
        view
        returns (bytes32 evidence)
    {
        uint8 operation = uint8(request.action);
        evidence = _assessBinding(
            request.actionId,
            TrustKernelTypes.BindingKind.POLICY,
            digest,
            operation,
            request.subject,
            request.destination,
            request.amount
        );
        if (request.destination != address(0)) {
            evidence = _chainEvidence(
                evidence,
                _assessBinding(
                    request.actionId,
                    TrustKernelTypes.BindingKind.IDENTITY,
                    digest,
                    operation,
                    request.subject,
                    request.destination,
                    request.amount
                )
            );
        }
        if (request.action == TrustKernelTypes.ActionKind.LIQUIDATE) {
            evidence = _chainEvidence(
                evidence,
                _assessBinding(
                    request.actionId,
                    TrustKernelTypes.BindingKind.SETTLEMENT,
                    digest,
                    operation,
                    request.subject,
                    request.destination,
                    request.amount
                )
            );
        }
        if (request.action == TrustKernelTypes.ActionKind.RECOVER) {
            evidence = _chainEvidence(
                evidence,
                _assessBinding(
                    request.actionId,
                    TrustKernelTypes.BindingKind.ENTITLEMENT,
                    digest,
                    operation,
                    request.subject,
                    request.destination,
                    request.amount
                )
            );
        }
    }

    function _assessReversalOrRevert(TrustKernelTypes.ReversalRequest calldata request, bytes32 digest)
        internal
        view
        returns (bytes32 evidence)
    {
        TrustKernelTypes.ActionRecord storage original = _actions[request.actionId];
        address destination =
            request.reversal == TrustKernelTypes.ReversalKind.RELEASE ? original.source : original.subject;
        evidence = _assessBinding(
            request.reversalId,
            TrustKernelTypes.BindingKind.POLICY,
            digest,
            REVERSAL_OPERATION_TAG | uint8(request.reversal),
            original.subject,
            destination,
            original.amount
        );
    }

    function _assessBinding(
        bytes32 commandId,
        TrustKernelTypes.BindingKind kind,
        bytes32 digest,
        uint8 operation,
        address subject,
        address destination,
        uint256 amount
    ) internal view returns (bytes32 evidence) {
        TrustNativeTypes.Binding storage binding = _bindings[kind];
        (TrustKernelTypes.AssessmentOutcome outcome, bytes32 reported, uint16 reason) =
            binding.assess(kind, digest, operation, subject, destination, amount);
        if (outcome == TrustKernelTypes.AssessmentOutcome.REJECTED) revert TrustRejected(commandId, reason);
        if (outcome == TrustKernelTypes.AssessmentOutcome.OPERATIONAL_FAILURE) {
            revert TrustOperationalFailure(commandId, reason, binding.bindingHash);
        }
        evidence = reported;
    }

    function _chainEvidence(bytes32 accumulated, bytes32 next) internal pure returns (bytes32) {
        return keccak256(abi.encode(accumulated, next));
    }

    // ---------------------------------------------------------------------
    // State transitions and receipts
    // ---------------------------------------------------------------------

    function _consumeActionAuthorization(
        TrustKernelTypes.ActionRequest calldata request,
        bytes32 digest,
        bytes32 evidence
    ) internal {
        _usedNonces[request.authorityRef][request.authorityEpoch][request.nonce] = true;
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

    function _consumeReversalAuthorization(TrustKernelTypes.ReversalRequest calldata request) internal {
        _usedNonces[request.authorityRef][request.authorityEpoch][request.nonce] = true;
    }

    function _pendingReversalOf(TrustKernelTypes.ReversalRequest calldata request, bytes32 evidence)
        internal
        pure
        returns (TrustNativeTypes.PendingReversal memory)
    {
        return TrustNativeTypes.PendingReversal({
            actionId: request.actionId,
            provenanceCommitment: request.provenanceCommitment,
            authorityRef: request.authorityRef,
            assessmentEvidence: evidence,
            reversal: uint8(request.reversal)
        });
    }

    function _applyActionPrepared(TrustKernelTypes.ActionRequest memory request)
        internal
        returns (bytes32 receiptHash)
    {
        TrustKernelTypes.ActionRecord storage record = _actions[request.actionId];
        if (record.lifecycle != TrustKernelTypes.Lifecycle.PREPARED) revert TrustReplay(request.actionId);
        TrustKernelTypes.CaseRecord storage caseState = _cases[request.caseId];
        bytes32 preState = _observation(request.subject, request.source, request.destination, request.caseId);

        if (request.action == TrustKernelTypes.ActionKind.FREEZE) {
            record.priorAmount = _frozen[request.subject];
            _pushEffect(request.actionId, record, _freezeHeads[request.subject]);
            _frozen[request.subject] = request.amount;
            emit Frozen(request.subject, request.amount);
            _openOverlay(caseState, TrustKernelTypes.CaseFamily.FREEZE, request.actionId);
        } else if (request.action == TrustKernelTypes.ActionKind.RESTRICT) {
            record.priorFlag = _restricted[request.subject];
            _pushEffect(request.actionId, record, _restrictionHeads[request.subject]);
            _restricted[request.subject] = true;
            _openOverlay(caseState, TrustKernelTypes.CaseFamily.RESTRICT, request.actionId);
        } else if (request.action == TrustKernelTypes.ActionKind.SEIZE) {
            _requireUnbacked(request.source, request.amount, request.actionId);
            _move(request.source, request.custodian, request.amount);
            _custody[request.caseId] = TrustNativeTypes.CustodyRecord({
                custodian: request.custodian,
                declaredPriorHolder: request.source,
                encumberedAmount: request.amount,
                actionId: request.actionId,
                active: true
            });
            _custodyBacking[request.custodian] += request.amount;
            emit ForcedTransfer(request.source, request.custodian, request.amount);
            caseState.phase = TrustKernelTypes.CasePhase.OPEN;
            caseState.family = TrustKernelTypes.CaseFamily.CUSTODY;
            caseState.headActionId = request.actionId;
        } else {
            bool consumedCustody = _consumeMatchingCustody(request);
            if (!consumedCustody) _requireUnbacked(request.source, request.amount, request.actionId);
            _move(request.source, request.destination, request.amount);
            if (request.action == TrustKernelTypes.ActionKind.RECOVER) {
                _consumedEntitlements[request.entitlementCommitment] = true;
            }
            emit ForcedTransfer(request.source, request.destination, request.amount);
            if (!consumedCustody) caseState.family = TrustKernelTypes.CaseFamily.DISPOSITION;
            caseState.phase = TrustKernelTypes.CasePhase.TERMINAL;
            caseState.headActionId = bytes32(0);
        }
        caseState.generation += 1;

        record.lifecycle = TrustKernelTypes.Lifecycle.APPLIED;
        bytes32 postState = _observation(request.subject, request.source, request.destination, request.caseId);
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
        delete _pendingCommitments[request.actionId];
        emit RegulatoryActionApplied(request.actionId, uint8(request.action), request.caseId, receiptHash);
    }

    function _applyReversalPrepared(bytes32 reversalId, TrustNativeTypes.PendingReversal memory pending)
        internal
        returns (bytes32 receiptHash)
    {
        TrustKernelTypes.ActionRecord storage original = _actions[pending.actionId];
        if (original.lifecycle != TrustKernelTypes.Lifecycle.APPLIED) revert TrustReplay(reversalId);
        TrustKernelTypes.CaseRecord storage caseState = _cases[original.caseId];
        bytes32 preState = _observation(original.subject, original.source, original.destination, original.caseId);
        address source;
        address destination;

        if (pending.reversal == uint8(TrustKernelTypes.ReversalKind.UNFREEZE)) {
            bytes32 parent = _popEffect(_effects[pending.actionId], _freezeHeads[original.subject]);
            _frozen[original.subject] = original.priorAmount;
            source = original.subject;
            destination = original.subject;
            emit Frozen(original.subject, original.priorAmount);
            if (parent != bytes32(0)) {
                caseState.headActionId = parent;
            } else {
                _closeCase(caseState);
            }
        } else if (pending.reversal == uint8(TrustKernelTypes.ReversalKind.UNRESTRICT)) {
            _popEffect(_effects[pending.actionId], _restrictionHeads[original.subject]);
            _restricted[original.subject] = original.priorFlag;
            source = original.subject;
            destination = original.subject;
            _closeCase(caseState);
        } else {
            TrustNativeTypes.CustodyRecord storage custody = _custody[original.caseId];
            _custodyBacking[custody.custodian] -= original.amount;
            custody.active = false;
            custody.encumberedAmount = 0;
            source = custody.custodian;
            destination = custody.declaredPriorHolder;
            _move(source, destination, original.amount);
            emit ForcedTransfer(source, destination, original.amount);
            _closeCase(caseState);
        }
        caseState.generation += 1;

        original.lifecycle = TrustKernelTypes.Lifecycle.REVERSED;
        bytes32 postState = _observation(original.subject, original.source, original.destination, original.caseId);
        receiptHash = _storeReceipt(
            TrustKernelTypes.Receipt({
                receiptKind: TrustKernelTypes.ReceiptKind.REVERSAL,
                commandId: reversalId,
                commandKind: pending.reversal,
                parentCommandId: pending.actionId,
                subject: original.subject,
                source: source,
                destination: destination,
                amount: original.amount,
                caseId: original.caseId,
                authorityRef: pending.authorityRef,
                dependencyRoot: _dependencyRoot,
                provenanceCommitment: pending.provenanceCommitment,
                assessmentEvidence: pending.assessmentEvidence,
                preState: preState,
                postState: postState,
                externalCommitment: bytes32(0),
                receiptHash: bytes32(0)
            })
        );
        emit RegulatoryReversalApplied(reversalId, pending.reversal, pending.actionId, receiptHash);
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

    // ---------------------------------------------------------------------
    // Internal helpers
    // ---------------------------------------------------------------------

    function _ordinaryTransfer(address from, address to, uint256 amount) internal {
        if (from == address(0) || to == address(0)) revert TrustZeroAddress();
        uint256 balance = _balances[from];
        if (balance < amount) revert TrustInsufficientBalance(from, balance, amount);
        if (!canSend(from)) revert ERC7943CannotSend(from);
        if (!canReceive(to)) revert ERC7943CannotReceive(to);
        uint256 available = _ordinaryAvailable(from);
        if (amount > available) revert ERC7943InsufficientUnfrozenBalance(from, amount, available);
        _move(from, to, amount);
    }

    function _ordinaryAvailable(address account) internal view returns (uint256) {
        uint256 balance = _balances[account];
        uint256 backing = _custodyBacking[account];
        if (backing >= balance) return 0;
        uint256 ownPhysical = balance - backing;
        uint256 frozen = _frozen[account];
        return frozen >= ownPhysical ? 0 : ownPhysical - frozen;
    }

    function _move(address from, address to, uint256 amount) internal {
        if (from == address(0) || to == address(0)) revert TrustZeroAddress();
        uint256 balance = _balances[from];
        if (balance < amount) revert TrustInsufficientBalance(from, balance, amount);
        unchecked {
            _balances[from] = balance - amount;
            _balances[to] += amount;
        }
        emit Transfer(from, to, amount);
    }

    function _prepareRoute(
        bytes32 commandId,
        bytes4 selector,
        bytes32 calldataHash,
        TrustNativeTypes.RouteKind routeKind
    ) internal {
        _routeTicket = TrustNativeTypes.RouteTicket({
            commandId: commandId,
            calldataHash: calldataHash,
            dependencyRoot: _dependencyRoot,
            selector: selector,
            routeKind: routeKind,
            dependencyEpoch: _dependencyEpoch,
            live: true
        });
    }

    function _consumeRoute(bytes4 selector, bytes32 calldataHash)
        internal
        returns (TrustNativeTypes.RouteTicket memory ticket)
    {
        ticket = _routeTicket;
        if (
            msg.sender != address(this) || !ticket.live || ticket.selector != selector
                || ticket.calldataHash != calldataHash || ticket.dependencyRoot != _dependencyRoot
                || ticket.dependencyEpoch != _dependencyEpoch
        ) {
            revert TrustRouteMismatch(_routeId());
        }
        delete _routeTicket;
    }

    /// @dev Identifier of the sensitive call being rejected; computed only on failure and never stored.
    function _routeId() internal view returns (bytes32) {
        return ERC7943RouteTicket.key(address(this), msg.sig, keccak256(msg.data));
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

    function _requestFromRecord(bytes32 actionId, TrustKernelTypes.ActionRecord storage record)
        internal
        view
        returns (TrustKernelTypes.ActionRequest memory request)
    {
        TrustNativeTypes.PendingCommitments storage pending = _pendingCommitments[actionId];
        request = TrustKernelTypes.ActionRequest({
            domain: TrustKernelTypes.DOMAIN,
            actionId: actionId,
            action: record.action,
            subject: record.subject,
            source: record.source,
            destination: record.destination,
            custodian: record.custodian,
            amount: record.amount,
            caseId: record.caseId,
            dependencyRoot: _dependencyRoot,
            dependencyEpoch: record.dependencyEpoch,
            provenanceCommitment: pending.provenanceCommitment,
            settlementCommitment: pending.settlementCommitment,
            proceedsCommitment: pending.proceedsCommitment,
            entitlementCommitment: pending.entitlementCommitment,
            authorityRef: record.authorityRef,
            authorityEpoch: record.authorityEpoch,
            nonce: 0,
            validAfter: 0,
            validBefore: type(uint48).max
        });
    }

    /// @dev Profile-defined observation preimage documented with the runtime identity: supply, the
    ///      subject's balance, frozen target, and restriction flag, the source's and destination's
    ///      balance and custody backing, the case's custody record, the subject's overlay heads, and
    ///      the case record.
    function _observation(address subject, address source, address destination, bytes32 caseId)
        internal
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                _totalSupply,
                subject,
                _balances[subject],
                _frozen[subject],
                _restricted[subject],
                source,
                _balances[source],
                _custodyBacking[source],
                destination,
                _balances[destination],
                _custodyBacking[destination],
                _custody[caseId],
                _freezeHeads[subject],
                _restrictionHeads[subject],
                _cases[caseId]
            )
        );
    }

    function _consumeMatchingCustody(TrustKernelTypes.ActionRequest memory request) internal returns (bool consumed) {
        TrustNativeTypes.CustodyRecord storage custody = _custody[request.caseId];
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

    function _validateCurrentEffect(
        bytes32 reversalId,
        bytes32 actionId,
        TrustKernelTypes.ReversalKind reversal,
        TrustKernelTypes.ActionRecord storage original
    ) internal view {
        if (reversal == TrustKernelTypes.ReversalKind.RELEASE) {
            TrustNativeTypes.CustodyRecord storage custody = _custody[original.caseId];
            if (
                !custody.active || custody.actionId != actionId || custody.custodian != original.custodian
                    || custody.declaredPriorHolder != original.source || custody.encumberedAmount != original.amount
                    || _custodyBacking[custody.custodian] < custody.encumberedAmount
            ) {
                revert TrustInvalidCommand(reversalId, REASON_CUSTODY);
            }
            return;
        }
        TrustNativeTypes.EffectRecord storage effect = _effects[actionId];
        if (effect.generation == 0 || effect.effectHash != _effectHash(original, effect)) {
            revert TrustInvalidCommand(reversalId, REASON_CURRENT_EFFECT);
        }
        TrustNativeTypes.EffectHead storage head = reversal == TrustKernelTypes.ReversalKind.UNFREEZE
            ? _freezeHeads[original.subject]
            : _restrictionHeads[original.subject];
        bool stateMatches = reversal == TrustKernelTypes.ReversalKind.UNFREEZE
            ? _frozen[original.subject] == original.amount
            : _restricted[original.subject];
        if (head.actionId != actionId || head.effectHash != effect.effectHash || !stateMatches) {
            revert TrustInvalidCommand(reversalId, REASON_CURRENT_EFFECT);
        }
    }

    function _pushEffect(
        bytes32 actionId,
        TrustKernelTypes.ActionRecord storage record,
        TrustNativeTypes.EffectHead storage head
    ) internal {
        TrustNativeTypes.EffectRecord storage effect = _effects[actionId];
        effect.parentActionId = head.actionId;
        effect.generation = head.generation + 1;
        effect.effectHash = _effectHash(record, effect);
        head.actionId = actionId;
        head.effectHash = effect.effectHash;
        head.generation = effect.generation;
    }

    /// @dev Pops the subject's live head back to the reversed action's parent and returns that parent.
    function _popEffect(TrustNativeTypes.EffectRecord storage originalEffect, TrustNativeTypes.EffectHead storage head)
        internal
        returns (bytes32 parent)
    {
        parent = originalEffect.parentActionId;
        head.actionId = parent;
        head.effectHash = parent == bytes32(0) ? bytes32(0) : _effects[parent].effectHash;
        head.generation += 1;
    }

    function _effectHash(TrustKernelTypes.ActionRecord storage record, TrustNativeTypes.EffectRecord storage effect)
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

    function _requireUnbacked(address account, uint256 amount, bytes32 commandId) internal view {
        uint256 balance = _balances[account];
        uint256 backing = _custodyBacking[account];
        if (balance < backing || amount > balance - backing) {
            revert TrustInvalidCommand(commandId, REASON_CUSTODY);
        }
    }

    function _requireCalldataLength(uint256 expected) internal pure {
        assembly ("memory-safe") {
            if xor(calldatasize(), expected) { revert(0, 0) }
        }
    }

    function _consumeGovernance(bytes32 authorizationId, uint256 nonce) internal {
        bytes32 key = keccak256(abi.encode(TrustKernelTypes.DOMAIN, "GOVERNANCE", governor, nonce));
        if (authorizationId == bytes32(0) || _usedGovernanceIds[authorizationId] || _usedGovernanceIds[key]) {
            revert TrustReplay(authorizationId);
        }
        _usedGovernanceIds[authorizationId] = true;
        _usedGovernanceIds[key] = true;
    }

    function _bind(
        TrustKernelTypes.BindingKind kind,
        address dependency,
        bytes32 schema,
        uint64 epoch,
        bytes32 commandId
    ) internal {
        if (dependency == address(0)) revert TrustZeroAddress();
        (bool ok, bytes32 config) = TrustDependencyBinding.readConfiguration(dependency);
        bytes32 code = TrustDependencyBinding.codeId(dependency);
        if (!ok || code == bytes32(0)) {
            revert TrustOperationalFailure(
                commandId, REASON_DEPENDENCY_UNAVAILABLE_AT_BIND, bytes32(uint256(uint160(dependency)))
            );
        }
        _bindings[kind] = TrustNativeTypes.Binding({
            dependency: dependency,
            codeId: code,
            configurationDigest: config,
            schema: schema,
            epoch: epoch,
            bindingHash: TrustDependencyBinding.compute(kind, dependency, code, config, schema, epoch)
        });
    }

    function _computeDependencyRoot() internal view returns (bytes32) {
        return TrustNativeDecision.dependencyRoot(
            _bindings[TrustKernelTypes.BindingKind.POLICY].bindingHash,
            _bindings[TrustKernelTypes.BindingKind.IDENTITY].bindingHash,
            _bindings[TrustKernelTypes.BindingKind.SETTLEMENT].bindingHash,
            _bindings[TrustKernelTypes.BindingKind.ENTITLEMENT].bindingHash
        );
    }

    function _bubble(bytes memory result) internal pure {
        if (result.length == 0) revert TrustUnsupported(msg.sig);
        assembly ("memory-safe") {
            revert(add(result, 32), mload(result))
        }
    }
}
