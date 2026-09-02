// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {IERC20} from "./interfaces/IERC20.sol";
import {IERC165} from "./interfaces/IERC165.sol";
import {IERC7943Fungible} from "./interfaces/IERC7943.sol";
import {IERCTrust} from "./interfaces/IERCTrust.sol";
import {TrustTypes} from "./TrustTypes.sol";
import {TrustStorage} from "./TrustStorage.sol";
import {TrustDecision} from "./TrustDecision.sol";
import {TrustPolicyBinding} from "./TrustPolicyBinding.sol";
import {ERC7943RouteTicket} from "./ERC7943RouteTicket.sol";
import {LegacyRouteAuthorizer} from "./LegacyRouteAuthorizer.sol";
import {
    TrustRejected,
    TrustOperationalFailure,
    TrustUnauthorized,
    TrustReplay,
    TrustInvalidCommand,
    TrustRouteMismatch,
    TrustTerminal,
    TrustReentrancy,
    TrustUnsupported,
    TrustZeroAddress,
    TrustInsufficientBalance,
    TrustInsufficientAllowance
} from "./TrustErrors.sol";

/// @notice Immutable, unaudited ERC-TRUST Native Full reference candidate.
/// @dev No proxy, delegatecall, selfdestruct, public mint, or public burn surface exists.
contract TrustTokenC3RouteDeletionMutant is TrustStorage, IERC20, IERC7943Fungible, IERCTrust {
    using TrustPolicyBinding for TrustTypes.Binding;

    bytes4 internal constant ERC165_INTERFACE_ID = 0x01ffc9a7;
    bytes4 internal constant ERC7943_FUNGIBLE_INTERFACE_ID = 0x3edbb4c4;
    uint16 internal constant REASON_DOMAIN = 1;
    uint16 internal constant REASON_ID = 2;
    uint16 internal constant REASON_TIME = 3;
    uint16 internal constant REASON_EPOCH = 4;
    uint16 internal constant REASON_BINDING = 5;
    uint16 internal constant REASON_SHAPE = 6;
    uint16 internal constant REASON_REVERSAL = 7;
    uint16 internal constant REASON_CUSTODY = 8;
    uint16 internal constant REASON_ENTITLEMENT = 9;
    uint8 internal constant REVERSAL_OPERATION_TAG = 0x80;
    uint256 internal constant ACTION_CALLDATA_LENGTH = 676;
    uint256 internal constant REVERSAL_CALLDATA_LENGTH = 292;

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
        _authorities[authorityRef] = TrustTypes.Authority({account: initialAuthority, epoch: 1, active: true});
        emit TrustAuthorityChanged(authorityRef, initialAuthority, 1, true);

        _bindInitial(TrustTypes.BindingKind.POLICY, policy, schema);
        _bindInitial(TrustTypes.BindingKind.IDENTITY, identity, schema);
        _bindInitial(TrustTypes.BindingKind.SETTLEMENT, settlement, schema);
        _bindInitial(TrustTypes.BindingKind.ENTITLEMENT, entitlement, schema);

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
                || interfaceId == type(IERCTrust).interfaceId);
    }

    function trustProfile() external pure returns (bytes32 profile, uint256 supportedActionMask, bool proxySupported) {
        return (keccak256("ERC-TRUST-NATIVE-FULL-V1"), 0x3f, false);
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

    function getFrozenTokens(address account) external view returns (uint256) {
        return _frozen[account];
    }

    function canTransfer(address from, address to, uint256 amount) public view returns (bool) {
        if (!canSend(from) || !canReceive(to)) return false;
        return amount <= _ordinaryAvailable(from);
    }

    // ---------------------------------------------------------------------
    // Canonical typed entrypoints
    // ---------------------------------------------------------------------

    function executeRegulatoryAction(TrustTypes.ActionRequest calldata request)
        external
        nonReentrant
        returns (bytes32 receiptHash)
    {
        _requireCalldataLength(ACTION_CALLDATA_LENGTH);
        bytes32 digest = _validateAndAuthorizeAction(request, msg.sender);
        bytes32 evidence = _assessOrRevert(request, digest);
        _consumeActionAuthorization(request, digest);
        return _applyAction(request, digest, evidence);
    }

    function executeRegulatoryReversal(TrustTypes.ReversalRequest calldata request)
        external
        nonReentrant
        returns (bytes32 receiptHash)
    {
        _requireCalldataLength(REVERSAL_CALLDATA_LENGTH);
        bytes32 digest = _validateAndAuthorizeReversal(request, msg.sender);
        _assessReversalOrRevert(request, digest);
        _consumeReversalAuthorization(request, digest);
        return _applyReversal(request, digest);
    }

    /// @notice Same-transaction exact-use adapter for ERC-7943 sensitive selectors.
    function executeERC7943Action(TrustTypes.ActionRequest calldata request)
        external
        nonReentrant
        returns (bytes32 receiptHash)
    {
        _requireCalldataLength(ACTION_CALLDATA_LENGTH);
        bytes32 digest = _validateAndAuthorizeAction(request, msg.sender);
        bool forced = TrustDecision.isForcedTransferAction(request.action);
        if (!forced && request.action != TrustTypes.ActionKind.FREEZE) {
            revert TrustInvalidCommand(request.actionId, REASON_SHAPE);
        }
        bytes32 evidence = _assessOrRevert(request, digest);
        _consumeActionAuthorization(request, digest);
        _actions[request.actionId].lifecycle = TrustTypes.Lifecycle.PREPARED;
        _actions[request.actionId].evidenceHash = evidence;

        if (request.action == TrustTypes.ActionKind.FREEZE) {
            bytes memory data = abi.encodeCall(IERC7943Fungible.setFrozenTokens, (request.subject, request.amount));
            _prepareRoute(
                request.actionId,
                IERC7943Fungible.setFrozenTokens.selector,
                keccak256(data),
                TrustTypes.RouteKind.ACTION,
                uint8(request.action),
                request.authorityEpoch,
                request.policyEpoch
            );
            (bool ok, bytes memory result) = address(this).call(data);
            if (!ok) _bubble(result);
        } else {
            address target = request.action == TrustTypes.ActionKind.SEIZE ? request.custodian : request.destination;
            bytes memory data =
                abi.encodeCall(IERC7943Fungible.forcedTransfer, (request.source, target, request.amount));
            _prepareRoute(
                request.actionId,
                IERC7943Fungible.forcedTransfer.selector,
                keccak256(data),
                TrustTypes.RouteKind.ACTION,
                uint8(request.action),
                request.authorityEpoch,
                request.policyEpoch
            );
            (bool ok, bytes memory result) = address(this).call(data);
            if (!ok) _bubble(result);
        }
        return _receipts[request.actionId].receiptHash;
    }

    function executeERC7943Reversal(TrustTypes.ReversalRequest calldata request)
        external
        nonReentrant
        returns (bytes32 receiptHash)
    {
        _requireCalldataLength(REVERSAL_CALLDATA_LENGTH);
        bytes32 digest = _validateAndAuthorizeReversal(request, msg.sender);
        TrustTypes.ActionRecord storage original = _actions[request.actionId];
        if (request.reversal != TrustTypes.ReversalKind.UNFREEZE) {
            revert TrustInvalidCommand(request.reversalId, REASON_REVERSAL);
        }
        _assessReversalOrRevert(request, digest);
        _consumeReversalAuthorization(request, digest);
        bytes memory data = abi.encodeCall(IERC7943Fungible.setFrozenTokens, (original.subject, original.priorAmount));
        _prepareRoute(
            request.reversalId,
            IERC7943Fungible.setFrozenTokens.selector,
            keccak256(data),
            TrustTypes.RouteKind.REVERSAL,
            uint8(request.reversal),
            request.authorityEpoch,
            original.policyEpoch
        );
        (bool ok, bytes memory result) = address(this).call(data);
        if (!ok) _bubble(result);
        return _receipts[request.reversalId].receiptHash;
    }

    /// @dev Raw calls always fail: a ticket can only exist during an executing wrapper call.
    function setFrozenTokens(address account, uint256 amount) external returns (bool result) {
        bytes32 dataHash = keccak256(msg.data);
        TrustTypes.RouteTicket memory ticket = _consumeRoute(IERC7943Fungible.setFrozenTokens.selector, dataHash);
        if (ticket.routeKind == TrustTypes.RouteKind.ACTION) {
            TrustTypes.ActionRecord storage record = _actions[ticket.commandId];
            if (record.action != TrustTypes.ActionKind.FREEZE || record.subject != account || record.amount != amount) {
                revert TrustRouteMismatch(ticket.routeKey);
            }
            TrustTypes.ActionRequest memory request = _requestFromRecord(ticket.commandId, record);
            _applyActionPrepared(request, record.commandHash, record.evidenceHash);
            return true;
        }
        if (ticket.routeKind == TrustTypes.RouteKind.REVERSAL) {
            TrustTypes.ReversalRequest memory request = _pendingReversal(ticket.commandId);
            TrustTypes.ActionRecord storage original = _actions[request.actionId];
            if (original.subject != account || original.priorAmount != amount) {
                revert TrustRouteMismatch(ticket.routeKey);
            }
            _applyReversalPrepared(request, request.domain);
            return true;
        }
        revert TrustRouteMismatch(ticket.routeKey);
    }

    function forcedTransfer(address from, address to, uint256 amount) external returns (bool result) {
        TrustTypes.RouteTicket memory ticket =
            _consumeRoute(IERC7943Fungible.forcedTransfer.selector, keccak256(msg.data));
        if (ticket.routeKind != TrustTypes.RouteKind.ACTION) revert TrustRouteMismatch(ticket.routeKey);
        TrustTypes.ActionRecord storage record = _actions[ticket.commandId];
        address expected = record.action == TrustTypes.ActionKind.SEIZE ? record.custodian : record.destination;
        if (
            !TrustDecision.isForcedTransferAction(record.action) || record.source != from || expected != to
                || record.amount != amount
        ) {
            revert TrustRouteMismatch(ticket.routeKey);
        }
        TrustTypes.ActionRequest memory request = _requestFromRecord(ticket.commandId, record);
        _applyActionPrepared(request, record.commandHash, record.evidenceHash);
        return true;
    }

    // ---------------------------------------------------------------------
    // Governance and versioned bindings
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
        TrustTypes.Authority storage authorityConfig = _authorities[authorityRef];
        authorityConfig.epoch += 1;
        authorityConfig.account = account;
        authorityConfig.active = active;
        emit TrustAuthorityChanged(authorityRef, account, authorityConfig.epoch, active);
    }

    function configureDelegation(
        bytes32 authorityRef,
        address delegate,
        uint256 actionMask,
        bytes32 scopeHash,
        uint48 validUntil,
        bytes32 authorizationId,
        uint256 nonce
    ) external {
        TrustTypes.Authority storage authorityConfig = _authorities[authorityRef];
        if (!authorityConfig.active || msg.sender != authorityConfig.account) {
            revert TrustUnauthorized(msg.sender, authorityRef);
        }
        if (authorizationId == bytes32(0)) revert TrustInvalidCommand(authorizationId, REASON_ID);
        bytes32 nonceKey = TrustDecision.nonceKey(authorityRef, authorityConfig.epoch, nonce);
        if (_usedNonces[authorityRef][authorityConfig.epoch][nonce]) revert TrustReplay(nonceKey);
        if (_usedCommandIds[authorizationId]) revert TrustReplay(authorizationId);
        _usedNonces[authorityRef][authorityConfig.epoch][nonce] = true;
        _usedCommandIds[authorizationId] = true;
        _delegations[authorityRef][delegate] = TrustTypes.Delegation({
            actionMask: actionMask, scopeHash: scopeHash, validUntil: validUntil, authorityEpoch: authorityConfig.epoch
        });
        emit TrustDelegationChanged(authorityRef, delegate, actionMask, scopeHash, validUntil);
    }

    function rebindDependency(
        TrustTypes.BindingKind kind,
        address dependency,
        bytes32 schema,
        bytes32 governanceAuthorizationId,
        uint256 governanceNonce
    ) external onlyGovernor {
        _consumeGovernance(governanceAuthorizationId, governanceNonce);
        if (dependency == address(0)) revert TrustZeroAddress();
        (bool ok, bytes32 config) = TrustPolicyBinding.readConfiguration(dependency);
        bytes32 code = TrustPolicyBinding.codeId(dependency);
        if (!ok || code == bytes32(0)) {
            revert TrustOperationalFailure(governanceAuthorizationId, 205, bytes32(uint256(uint160(dependency))));
        }
        TrustTypes.Binding storage bindingConfig = _bindings[kind];
        bytes32 previous = bindingConfig.bindingHash;
        uint64 nextEpoch = bindingConfig.epoch + 1;
        bytes32 next = TrustPolicyBinding.compute(kind, dependency, code, config, schema, nextEpoch);
        bindingConfig.dependency = dependency;
        bindingConfig.codeId = code;
        bindingConfig.configurationDigest = config;
        bindingConfig.schema = schema;
        bindingConfig.epoch = nextEpoch;
        bindingConfig.bindingHash = next;
        emit TrustBindingChanged(kind, previous, next, nextEpoch);
    }

    // ---------------------------------------------------------------------
    // Public evidence views
    // ---------------------------------------------------------------------

    function deriveActionId(TrustTypes.ActionRequest calldata request) public view returns (bytes32) {
        return _actionHash(request, true);
    }

    function deriveReversalId(TrustTypes.ReversalRequest calldata request) public view returns (bytes32) {
        return _reversalHash(request, true);
    }

    function commandHash(TrustTypes.ActionRequest calldata request) public view returns (bytes32) {
        return _actionHash(request, false);
    }

    function reversalHash(TrustTypes.ReversalRequest calldata request) public view returns (bytes32) {
        return _reversalHash(request, false);
    }

    function actionRecord(bytes32 actionId) external view returns (TrustTypes.ActionRecord memory) {
        return _actions[actionId];
    }

    function receipt(bytes32 commandId) external view returns (TrustTypes.Receipt memory) {
        return _receipts[commandId];
    }

    function caseTerminal(bytes32 caseId) external view returns (bool) {
        return _terminalCases[caseId];
    }

    function custodyRecord(bytes32 caseId) external view returns (TrustTypes.CustodyRecord memory) {
        return _custody[caseId];
    }

    function settlementRecord(bytes32 actionId) external view returns (TrustTypes.SettlementRecord memory) {
        return _settlements[actionId];
    }

    function entitlementRecord(bytes32 actionId) external view returns (TrustTypes.EntitlementRecord memory) {
        return _entitlements[actionId];
    }

    function getAuthorityState(bytes32 authorityRef)
        external
        view
        returns (address account, uint64 epoch, bool active)
    {
        TrustTypes.Authority storage authority_ = _authorities[authorityRef];
        return (authority_.account, authority_.epoch, authority_.active);
    }

    function getBindingState(TrustTypes.BindingKind kind)
        external
        view
        returns (address dependency, bytes32 bindingHash, uint64 epoch)
    {
        TrustTypes.Binding storage binding_ = _bindings[kind];
        return (binding_.dependency, binding_.bindingHash, binding_.epoch);
    }

    function isRestricted(address account) external view returns (bool) {
        return _restricted[account];
    }

    function nonceUsed(bytes32 authorityRef, uint64 authorityEpoch, uint256 nonce) external view returns (bool) {
        return _usedNonces[authorityRef][authorityEpoch][nonce];
    }

    function routeLive() external view returns (bool) {
        return _routeTicket.live;
    }

    // ---------------------------------------------------------------------
    // Validation and assessment
    // ---------------------------------------------------------------------

    function _validateAndAuthorizeAction(TrustTypes.ActionRequest calldata request, address caller)
        internal
        view
        returns (bytes32 digest)
    {
        if (request.domain != TrustTypes.DOMAIN) revert TrustInvalidCommand(request.actionId, REASON_DOMAIN);
        if (request.actionId == bytes32(0) || request.actionId != _actionHash(request, true)) {
            revert TrustInvalidCommand(request.actionId, REASON_ID);
        }
        if (block.timestamp < request.validAfter || request.validBefore == 0 || block.timestamp > request.validBefore) {
            revert TrustInvalidCommand(request.actionId, REASON_TIME);
        }
        TrustTypes.Authority storage authority_ = _authorities[request.authorityRef];
        if (authority_.epoch != request.authorityEpoch) revert TrustInvalidCommand(request.actionId, REASON_EPOCH);
        TrustTypes.Delegation storage delegation = _delegations[request.authorityRef][caller];
        if (!LegacyRouteAuthorizer.authorized(
                authority_, delegation, caller, request.action, request.scopeHash, uint48(block.timestamp)
            )) {
            revert TrustUnauthorized(caller, request.authorityRef);
        }
        TrustTypes.Binding storage policy = _bindings[TrustTypes.BindingKind.POLICY];
        if (request.policyEpoch != policy.epoch || request.policyCommitment != policy.bindingHash) {
            revert TrustInvalidCommand(request.actionId, REASON_BINDING);
        }
        _validateActionShape(request);
        if (_usedCommandIds[request.actionId]) revert TrustReplay(request.actionId);
        if (_usedNonces[request.authorityRef][request.authorityEpoch][request.nonce]) {
            revert TrustReplay(TrustDecision.nonceKey(request.authorityRef, request.authorityEpoch, request.nonce));
        }
        digest = commandHash(request);
    }

    function _validateAndAuthorizeReversal(TrustTypes.ReversalRequest calldata request, address caller)
        internal
        view
        returns (bytes32 digest)
    {
        if (request.domain != TrustTypes.DOMAIN) revert TrustInvalidCommand(request.reversalId, REASON_DOMAIN);
        if (request.reversalId == bytes32(0) || request.reversalId != deriveReversalId(request)) {
            revert TrustInvalidCommand(request.reversalId, REASON_ID);
        }
        if (block.timestamp < request.validAfter || request.validBefore == 0 || block.timestamp > request.validBefore) {
            revert TrustInvalidCommand(request.reversalId, REASON_TIME);
        }
        TrustTypes.ActionRecord storage original = _actions[request.actionId];
        if (original.lifecycle != TrustTypes.Lifecycle.APPLIED) revert TrustTerminal(request.actionId);
        if (!TrustDecision.reversalMatches(original.action, request.reversal)) {
            revert TrustInvalidCommand(request.reversalId, REASON_REVERSAL);
        }
        _validateCurrentEffect(request.reversalId, request.actionId, request.reversal, original);
        TrustTypes.Authority storage authority_ = _authorities[request.authorityRef];
        if (!authority_.active || authority_.epoch != request.authorityEpoch || caller != authority_.account) {
            revert TrustUnauthorized(caller, request.authorityRef);
        }
        if (_usedCommandIds[request.reversalId]) revert TrustReplay(request.reversalId);
        if (_usedNonces[request.authorityRef][request.authorityEpoch][request.nonce]) {
            revert TrustReplay(TrustDecision.nonceKey(request.authorityRef, request.authorityEpoch, request.nonce));
        }
        digest = _reversalHash(request, false);
    }

    function _validateActionShape(TrustTypes.ActionRequest calldata request) internal view {
        if (
            request.subject == address(0) || request.caseId == bytes32(0) || request.scopeHash == bytes32(0)
                || request.provenanceCommitment == bytes32(0) || _terminalCases[request.caseId]
        ) {
            revert TrustInvalidCommand(request.actionId, REASON_SHAPE);
        }
        if (request.action == TrustTypes.ActionKind.FREEZE) {
            if (
                request.source != request.subject || request.destination != address(0)
                    || request.custodian != address(0)
            ) {
                revert TrustInvalidCommand(request.actionId, REASON_SHAPE);
            }
        } else if (request.action == TrustTypes.ActionKind.RESTRICT) {
            if (
                request.source != request.subject || request.destination != address(0)
                    || request.custodian != address(0)
            ) {
                revert TrustInvalidCommand(request.actionId, REASON_SHAPE);
            }
        }
        if (
            request.action == TrustTypes.ActionKind.SEIZE || request.action == TrustTypes.ActionKind.CONFISCATE
                || request.action == TrustTypes.ActionKind.LIQUIDATE || request.action == TrustTypes.ActionKind.RECOVER
        ) {
            if (
                request.source == address(0) || request.destination == address(0)
                    || request.source == request.destination || request.amount == 0
            ) {
                revert TrustInvalidCommand(request.actionId, REASON_SHAPE);
            }
        }
        if (request.action == TrustTypes.ActionKind.SEIZE && request.subject != request.source) {
            revert TrustInvalidCommand(request.actionId, REASON_SHAPE);
        }
        if (
            (request.action == TrustTypes.ActionKind.CONFISCATE
                    || request.action == TrustTypes.ActionKind.LIQUIDATE
                    || request.action == TrustTypes.ActionKind.RECOVER) && !_custody[request.caseId].active
                && request.subject != request.source
        ) {
            revert TrustInvalidCommand(request.actionId, REASON_SHAPE);
        }
        if (
            request.action == TrustTypes.ActionKind.SEIZE
                && (request.custodian == address(0) || request.destination != request.custodian)
        ) {
            revert TrustInvalidCommand(request.actionId, REASON_SHAPE);
        }
        if (
            request.action == TrustTypes.ActionKind.LIQUIDATE
                && (request.settlementCommitment == bytes32(0) || request.proceedsCommitment == bytes32(0))
        ) {
            revert TrustInvalidCommand(request.actionId, REASON_SHAPE);
        }
        if (request.action == TrustTypes.ActionKind.RECOVER && request.entitlementCommitment == bytes32(0)) {
            revert TrustInvalidCommand(request.actionId, REASON_SHAPE);
        }
        if (request.action != TrustTypes.ActionKind.SEIZE && request.custodian != address(0)) {
            revert TrustInvalidCommand(request.actionId, REASON_SHAPE);
        }
        if (
            request.action != TrustTypes.ActionKind.LIQUIDATE
                && (request.settlementCommitment != bytes32(0) || request.proceedsCommitment != bytes32(0))
        ) {
            revert TrustInvalidCommand(request.actionId, REASON_SHAPE);
        }
        if (request.action != TrustTypes.ActionKind.RECOVER && request.entitlementCommitment != bytes32(0)) {
            revert TrustInvalidCommand(request.actionId, REASON_SHAPE);
        }
    }

    function _assessOrRevert(TrustTypes.ActionRequest calldata request, bytes32 digest)
        internal
        view
        returns (bytes32 evidence)
    {
        address effectiveDestination =
            request.action == TrustTypes.ActionKind.SEIZE ? request.custodian : request.destination;
        (TrustTypes.AssessmentOutcome outcome, bytes32 policyEvidence, uint16 reason) = _bindings[TrustTypes.BindingKind
            .POLICY].assess(digest, uint8(request.action), request.subject, effectiveDestination, request.amount);
        _requireApplicable(request.actionId, outcome, reason, _bindings[TrustTypes.BindingKind.POLICY].bindingHash);
        evidence = policyEvidence;

        if (effectiveDestination != address(0)) {
            (outcome, policyEvidence, reason) = _bindings[TrustTypes.BindingKind
                .IDENTITY].assess(digest, uint8(request.action), request.subject, effectiveDestination, request.amount);
            _requireApplicable(
                request.actionId, outcome, reason, _bindings[TrustTypes.BindingKind.IDENTITY].bindingHash
            );
            evidence = keccak256(abi.encode(evidence, policyEvidence));
        }
        if (request.action == TrustTypes.ActionKind.LIQUIDATE) {
            (outcome, policyEvidence, reason) = _bindings[TrustTypes.BindingKind
                .SETTLEMENT].assess(digest, uint8(request.action), request.subject, request.destination, request.amount);
            _requireApplicable(
                request.actionId, outcome, reason, _bindings[TrustTypes.BindingKind.SETTLEMENT].bindingHash
            );
            evidence = keccak256(abi.encode(evidence, policyEvidence));
        }
        if (request.action == TrustTypes.ActionKind.RECOVER) {
            (outcome, policyEvidence, reason) = _bindings[TrustTypes.BindingKind
                .ENTITLEMENT].assess(
                digest, uint8(request.action), request.subject, request.destination, request.amount
            );
            _requireApplicable(
                request.actionId, outcome, reason, _bindings[TrustTypes.BindingKind.ENTITLEMENT].bindingHash
            );
            evidence = keccak256(abi.encode(evidence, policyEvidence));
        }
    }

    function _assessReversalOrRevert(TrustTypes.ReversalRequest calldata request, bytes32 digest) internal view {
        TrustTypes.ActionRecord storage original = _actions[request.actionId];
        address destination = request.reversal == TrustTypes.ReversalKind.RELEASE ? original.source : original.subject;
        (TrustTypes.AssessmentOutcome outcome,, uint16 reason) = _bindings[TrustTypes.BindingKind
            .POLICY].assess(
            digest, REVERSAL_OPERATION_TAG | uint8(request.reversal), original.subject, destination, original.amount
        );
        _requireApplicable(request.reversalId, outcome, reason, _bindings[TrustTypes.BindingKind.POLICY].bindingHash);
    }

    function _requireApplicable(
        bytes32 commandId,
        TrustTypes.AssessmentOutcome outcome,
        uint16 reason,
        bytes32 dependency
    ) internal pure {
        if (outcome == TrustTypes.AssessmentOutcome.REJECTED) revert TrustRejected(commandId, reason);
        if (outcome == TrustTypes.AssessmentOutcome.OPERATIONAL_FAILURE) {
            revert TrustOperationalFailure(commandId, reason, dependency);
        }
    }

    // ---------------------------------------------------------------------
    // State transitions and receipts
    // ---------------------------------------------------------------------

    function _consumeActionAuthorization(TrustTypes.ActionRequest calldata request, bytes32 digest) internal {
        _usedCommandIds[request.actionId] = true;
        _usedNonces[request.authorityRef][request.authorityEpoch][request.nonce] = true;
        _actions[request.actionId] = TrustTypes.ActionRecord({
            action: request.action,
            lifecycle: TrustTypes.Lifecycle.PREPARED,
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
            policyEpoch: request.policyEpoch,
            commandHash: digest,
            evidenceHash: bytes32(0),
            receiptHash: bytes32(0)
        });
        _pendingCommitments[request.actionId] = PendingCommitments({
            scopeHash: request.scopeHash,
            provenanceCommitment: request.provenanceCommitment,
            settlementCommitment: request.settlementCommitment,
            proceedsCommitment: request.proceedsCommitment,
            entitlementCommitment: request.entitlementCommitment
        });
    }

    function _consumeReversalAuthorization(TrustTypes.ReversalRequest calldata request, bytes32 digest) internal {
        _usedCommandIds[request.reversalId] = true;
        _usedNonces[request.authorityRef][request.authorityEpoch][request.nonce] = true;
        _pendingReversals[request.reversalId] = request;
        _pendingReversals[request.reversalId].domain = digest;
    }

    mapping(bytes32 => TrustTypes.ReversalRequest) private _pendingReversals;

    function _applyAction(TrustTypes.ActionRequest calldata request, bytes32 digest, bytes32 evidence)
        internal
        returns (bytes32)
    {
        TrustTypes.ActionRequest memory copy = request;
        return _applyActionPrepared(copy, digest, evidence);
    }

    function _applyActionPrepared(TrustTypes.ActionRequest memory request, bytes32 digest, bytes32 evidence)
        internal
        returns (bytes32 receiptHash)
    {
        TrustTypes.ActionRecord storage record = _actions[request.actionId];
        if (record.lifecycle != TrustTypes.Lifecycle.PREPARED) revert TrustTerminal(request.actionId);
        bytes32 preState = _observation(request.subject, request.source, request.destination, request.caseId);

        if (request.action == TrustTypes.ActionKind.FREEZE) {
            record.priorAmount = _frozen[request.subject];
            _pushEffect(request.actionId, record, _freezeHeads[request.subject]);
            _frozen[request.subject] = request.amount;
            emit Frozen(request.subject, request.amount);
        } else if (request.action == TrustTypes.ActionKind.RESTRICT) {
            record.priorFlag = _restricted[request.subject];
            _pushEffect(request.actionId, record, _restrictionHeads[request.subject]);
            _restricted[request.subject] = true;
        } else if (request.action == TrustTypes.ActionKind.SEIZE) {
            _requireNoCustody(request.caseId);
            _requireUnbacked(request.source, request.amount, request.actionId);
            _move(request.source, request.custodian, request.amount);
            TrustTypes.CustodyRecord storage priorCustody = _custody[request.caseId];
            TrustTypes.EffectRecord storage effect = _effects[request.actionId];
            effect.parentActionId = priorCustody.actionId;
            effect.generation = priorCustody.generation + 1;
            effect.effectHash = _effectHash(record, effect);
            _custody[request.caseId] = TrustTypes.CustodyRecord({
                custodian: request.custodian,
                declaredPriorHolder: request.source,
                encumberedAmount: request.amount,
                actionId: request.actionId,
                parentActionId: effect.parentActionId,
                effectHash: effect.effectHash,
                generation: effect.generation,
                active: true
            });
            _custodyBacking[request.custodian] += request.amount;
            emit ForcedTransfer(request.source, request.custodian, request.amount);
        } else {
            bool consumedCustody = _consumeMatchingCustody(request);
            if (!consumedCustody) _requireUnbacked(request.source, request.amount, request.actionId);
            if (request.action == TrustTypes.ActionKind.RECOVER && _consumedEntitlements[request.entitlementCommitment])
            {
                revert TrustInvalidCommand(request.actionId, REASON_ENTITLEMENT);
            }
            _move(request.source, request.destination, request.amount);
            _terminalCases[request.caseId] = true;
            if (request.action == TrustTypes.ActionKind.LIQUIDATE) {
                _settlements[request.actionId] = TrustTypes.SettlementRecord({
                    destination: request.destination,
                    amount: request.amount,
                    settlementCommitment: request.settlementCommitment,
                    proceedsCommitment: request.proceedsCommitment,
                    evidenceHash: evidence,
                    consumedCustody: consumedCustody
                });
            } else if (request.action == TrustTypes.ActionKind.RECOVER) {
                _consumedEntitlements[request.entitlementCommitment] = true;
                _entitlements[request.actionId] = TrustTypes.EntitlementRecord({
                    destination: request.destination,
                    amount: request.amount,
                    entitlementCommitment: request.entitlementCommitment,
                    evidenceHash: evidence,
                    consumed: true
                });
            }
            emit ForcedTransfer(request.source, request.destination, request.amount);
        }

        record.lifecycle = TrustTypes.Lifecycle.APPLIED;
        record.commandHash = digest;
        record.evidenceHash = evidence;
        bytes32 postState = _observation(request.subject, request.source, request.destination, request.caseId);
        bytes32 externalCommitment = request.action == TrustTypes.ActionKind.LIQUIDATE
            ? keccak256(abi.encode(request.settlementCommitment, request.proceedsCommitment))
            : request.action == TrustTypes.ActionKind.RECOVER ? request.entitlementCommitment : bytes32(0);
        receiptHash = keccak256(
            abi.encode(
                TrustTypes.DOMAIN,
                request.actionId,
                uint8(request.action),
                request.source,
                request.destination,
                request.amount,
                request.caseId,
                request.policyCommitment,
                request.provenanceCommitment,
                preState,
                postState,
                externalCommitment
            )
        );
        _receipts[request.actionId] = TrustTypes.Receipt({
            commandId: request.actionId,
            commandKind: uint8(request.action),
            source: request.source,
            destination: request.destination,
            amount: request.amount,
            caseId: request.caseId,
            policyBinding: request.policyCommitment,
            provenanceCommitment: request.provenanceCommitment,
            preState: preState,
            postState: postState,
            externalCommitment: externalCommitment,
            receiptHash: receiptHash
        });
        record.receiptHash = receiptHash;
        delete _pendingCommitments[request.actionId];
        emit RegulatoryActionApplied(request.actionId, request.action, request.caseId, receiptHash);
    }

    function _applyReversal(TrustTypes.ReversalRequest calldata request, bytes32 digest) internal returns (bytes32) {
        TrustTypes.ReversalRequest memory copy = request;
        return _applyReversalPrepared(copy, digest);
    }

    function _applyReversalPrepared(TrustTypes.ReversalRequest memory request, bytes32 digest)
        internal
        returns (bytes32 receiptHash)
    {
        TrustTypes.ActionRecord storage original = _actions[request.actionId];
        TrustTypes.EffectRecord storage originalEffect = _effects[request.actionId];
        if (original.lifecycle != TrustTypes.Lifecycle.APPLIED) revert TrustTerminal(request.actionId);
        bytes32 preState = _observation(original.subject, original.source, original.destination, original.caseId);
        address destination;
        bytes32 popEffectHash;

        if (request.reversal == TrustTypes.ReversalKind.UNFREEZE) {
            popEffectHash = _popEffect(digest, originalEffect, _freezeHeads[original.subject]);
            _frozen[original.subject] = original.priorAmount;
            destination = original.subject;
            emit Frozen(original.subject, original.priorAmount);
        } else if (request.reversal == TrustTypes.ReversalKind.UNRESTRICT) {
            popEffectHash = _popEffect(digest, originalEffect, _restrictionHeads[original.subject]);
            _restricted[original.subject] = original.priorFlag;
            destination = original.subject;
        } else {
            TrustTypes.CustodyRecord storage custody = _custody[original.caseId];
            uint64 nextGeneration = custody.generation + 1;
            popEffectHash = _popHash(digest, nextGeneration, originalEffect.effectHash);
            _custodyBacking[custody.custodian] -= original.amount;
            custody.active = false;
            custody.encumberedAmount = 0;
            custody.actionId = originalEffect.parentActionId;
            custody.effectHash = originalEffect.parentActionId == bytes32(0)
                ? bytes32(0)
                : _effects[originalEffect.parentActionId].effectHash;
            custody.generation = nextGeneration;
            destination = custody.declaredPriorHolder;
            _move(custody.custodian, destination, original.amount);
            emit ForcedTransfer(custody.custodian, destination, original.amount);
        }

        original.lifecycle = TrustTypes.Lifecycle.REVERSED;
        _terminalCases[original.caseId] = true;
        bytes32 postState = _observation(original.subject, original.source, destination, original.caseId);
        receiptHash = keccak256(
            abi.encode(
                TrustTypes.DOMAIN,
                request.reversalId,
                uint8(request.reversal),
                request.actionId,
                original.source,
                destination,
                original.amount,
                original.caseId,
                preState,
                postState,
                digest,
                popEffectHash
            )
        );
        _receipts[request.reversalId] = TrustTypes.Receipt({
            commandId: request.reversalId,
            commandKind: uint8(request.reversal),
            source: original.source,
            destination: destination,
            amount: original.amount,
            caseId: original.caseId,
            policyBinding: _bindings[TrustTypes.BindingKind.POLICY].bindingHash,
            provenanceCommitment: bytes32(0),
            preState: preState,
            postState: postState,
            externalCommitment: popEffectHash,
            receiptHash: receiptHash
        });
        delete _pendingReversals[request.reversalId];
        emit RegulatoryReversalApplied(request.reversalId, request.reversal, request.actionId, receiptHash);
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
        TrustTypes.RouteKind routeKind,
        uint8 actionOrReversal,
        uint64 authorityEpoch,
        uint64 policyEpoch
    ) internal {
        TrustTypes.Binding storage policy = _bindings[TrustTypes.BindingKind.POLICY];
        bytes32 key = ERC7943RouteTicket.key(
            address(this), selector, calldataHash, policy.bindingHash, authorityEpoch, policyEpoch, commandId
        );
        _routeTicket = TrustTypes.RouteTicket({
            commandId: commandId,
            routeKey: key,
            calldataHash: calldataHash,
            bindingHash: policy.bindingHash,
            selector: selector,
            routeKind: routeKind,
            actionOrReversal: actionOrReversal,
            authorityEpoch: authorityEpoch,
            policyEpoch: policyEpoch,
            live: true
        });
    }

    function _consumeRoute(bytes4 selector, bytes32 calldataHash)
        internal
        returns (TrustTypes.RouteTicket memory ticket)
    {
        ticket = _routeTicket;
        if (
            msg.sender != address(this) || !ticket.live || ticket.selector != selector
                || ticket.calldataHash != calldataHash
                || ticket.bindingHash != _bindings[TrustTypes.BindingKind.POLICY].bindingHash
                || ticket.policyEpoch != _bindings[TrustTypes.BindingKind.POLICY].epoch
        ) {
            revert TrustRouteMismatch(ticket.routeKey);
        }
        bytes32 expected = ERC7943RouteTicket.key(
            address(this),
            selector,
            calldataHash,
            ticket.bindingHash,
            ticket.authorityEpoch,
            ticket.policyEpoch,
            ticket.commandId
        );
        if (expected != ticket.routeKey) revert TrustRouteMismatch(ticket.routeKey);
        // MUTATION: route ticket deletion omitted.
    }

    function _actionHash(TrustTypes.ActionRequest calldata request, bool clearId)
        internal
        view
        returns (bytes32 result)
    {
        bytes32 domain = TrustTypes.DOMAIN;
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(ptr, domain)
            mstore(add(ptr, 0x20), address())
            mstore(add(ptr, 0x40), chainid())
            calldatacopy(add(ptr, 0x60), request, 0x2a0)
            if clearId { mstore(add(ptr, 0x80), 0) }
            result := keccak256(ptr, 0x300)
        }
    }

    function _reversalHash(TrustTypes.ReversalRequest calldata request, bool clearId)
        internal
        view
        returns (bytes32 result)
    {
        bytes32 domain = TrustTypes.DOMAIN;
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(ptr, domain)
            mstore(add(ptr, 0x20), address())
            mstore(add(ptr, 0x40), chainid())
            calldatacopy(add(ptr, 0x60), request, 0x120)
            if clearId { mstore(add(ptr, 0x80), 0) }
            result := keccak256(ptr, 0x180)
        }
    }

    function _requestFromRecord(bytes32 actionId, TrustTypes.ActionRecord storage record)
        internal
        view
        returns (TrustTypes.ActionRequest memory request)
    {
        TrustTypes.Receipt storage existing = _receipts[actionId];
        request = TrustTypes.ActionRequest({
            domain: TrustTypes.DOMAIN,
            actionId: actionId,
            action: record.action,
            subject: record.subject,
            source: record.source,
            destination: record.destination,
            custodian: record.custodian,
            amount: record.amount,
            caseId: record.caseId,
            scopeHash: bytes32(0),
            policyCommitment: _bindings[TrustTypes.BindingKind.POLICY].bindingHash,
            provenanceCommitment: existing.provenanceCommitment,
            settlementCommitment: bytes32(0),
            proceedsCommitment: bytes32(0),
            entitlementCommitment: bytes32(0),
            authorityRef: record.authorityRef,
            authorityEpoch: record.authorityEpoch,
            policyEpoch: record.policyEpoch,
            nonce: 0,
            validAfter: 0,
            validBefore: type(uint48).max
        });
        PendingCommitments storage pending = _pendingCommitments[actionId];
        request.scopeHash = pending.scopeHash;
        request.provenanceCommitment = pending.provenanceCommitment;
        request.settlementCommitment = pending.settlementCommitment;
        request.proceedsCommitment = pending.proceedsCommitment;
        request.entitlementCommitment = pending.entitlementCommitment;
    }

    struct PendingCommitments {
        bytes32 scopeHash;
        bytes32 provenanceCommitment;
        bytes32 settlementCommitment;
        bytes32 proceedsCommitment;
        bytes32 entitlementCommitment;
    }

    mapping(bytes32 => PendingCommitments) private _pendingCommitments;

    function _pendingReversal(bytes32 reversalId) internal view returns (TrustTypes.ReversalRequest memory) {
        return _pendingReversals[reversalId];
    }

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
                _terminalCases[caseId]
            )
        );
    }

    function _requireNoCustody(bytes32 caseId) internal view {
        if (caseId == bytes32(0) || _custody[caseId].active) {
            revert TrustInvalidCommand(caseId, REASON_CUSTODY);
        }
    }

    function _consumeMatchingCustody(TrustTypes.ActionRequest memory request) internal returns (bool consumed) {
        TrustTypes.CustodyRecord storage custody = _custody[request.caseId];
        if (!custody.active) return false;
        if (
            custody.custodian != request.source || custody.encumberedAmount != request.amount
                || custody.declaredPriorHolder != request.subject || custody.actionId == bytes32(0)
                || custody.effectHash != _effects[custody.actionId].effectHash
                || _custodyBacking[custody.custodian] < custody.encumberedAmount
        ) {
            revert TrustInvalidCommand(request.actionId, REASON_CUSTODY);
        }
        uint64 nextGeneration = custody.generation + 1;
        custody.effectHash = _popHash(_actions[request.actionId].commandHash, nextGeneration, custody.effectHash);
        _custodyBacking[custody.custodian] -= custody.encumberedAmount;
        custody.active = false;
        custody.encumberedAmount = 0;
        custody.actionId = custody.parentActionId;
        custody.generation = nextGeneration;
        return true;
    }

    function _validateCurrentEffect(
        bytes32 reversalId,
        bytes32 actionId,
        TrustTypes.ReversalKind reversal,
        TrustTypes.ActionRecord storage original
    ) internal view {
        TrustTypes.EffectRecord storage effect = _effects[actionId];
        if (effect.generation == 0 || effect.effectHash != _effectHash(original, effect)) {
            revert TrustInvalidCommand(reversalId, REASON_REVERSAL);
        }
        if (effect.parentActionId != bytes32(0)) {
            TrustTypes.ActionRecord storage parent = _actions[effect.parentActionId];
            if (
                parent.lifecycle != TrustTypes.Lifecycle.APPLIED || parent.action != original.action
                    || parent.subject != original.subject
            ) {
                revert TrustInvalidCommand(reversalId, REASON_REVERSAL);
            }
        }
        if (reversal == TrustTypes.ReversalKind.UNFREEZE) {
            TrustTypes.EffectHead storage head = _freezeHeads[original.subject];
            if (
                head.actionId != actionId || head.effectHash != effect.effectHash || head.generation < effect.generation
                    || _frozen[original.subject] != original.amount
            ) {
                revert TrustInvalidCommand(reversalId, REASON_REVERSAL);
            }
        } else if (reversal == TrustTypes.ReversalKind.UNRESTRICT) {
            TrustTypes.EffectHead storage head = _restrictionHeads[original.subject];
            if (
                head.actionId != actionId || head.effectHash != effect.effectHash || head.generation < effect.generation
                    || !_restricted[original.subject]
            ) {
                revert TrustInvalidCommand(reversalId, REASON_REVERSAL);
            }
        } else {
            TrustTypes.CustodyRecord storage custody = _custody[original.caseId];
            if (
                !custody.active || custody.actionId != actionId || custody.effectHash != effect.effectHash
                    || custody.generation < effect.generation || custody.custodian != original.custodian
                    || custody.declaredPriorHolder != original.source || custody.encumberedAmount != original.amount
                    || _custodyBacking[custody.custodian] < custody.encumberedAmount
            ) {
                revert TrustInvalidCommand(reversalId, REASON_CUSTODY);
            }
        }
    }

    function _pushEffect(bytes32 actionId, TrustTypes.ActionRecord storage record, TrustTypes.EffectHead storage head)
        internal
    {
        TrustTypes.EffectRecord storage effect = _effects[actionId];
        effect.parentActionId = head.actionId;
        effect.generation = head.generation + 1;
        effect.effectHash = _effectHash(record, effect);
        head.actionId = actionId;
        head.effectHash = effect.effectHash;
        head.generation = effect.generation;
    }

    function _popEffect(
        bytes32 transitionHash,
        TrustTypes.EffectRecord storage originalEffect,
        TrustTypes.EffectHead storage head
    ) internal returns (bytes32 popEffectHash) {
        uint64 nextGeneration = head.generation + 1;
        popEffectHash = _popHash(transitionHash, nextGeneration, originalEffect.effectHash);
        head.actionId = originalEffect.parentActionId;
        head.effectHash = originalEffect.parentActionId == bytes32(0)
            ? bytes32(0)
            : _effects[originalEffect.parentActionId].effectHash;
        head.generation = nextGeneration;
    }

    function _effectHash(TrustTypes.ActionRecord storage record, TrustTypes.EffectRecord storage effect)
        internal
        view
        returns (bytes32 result)
    {
        bytes32 commandDigest = record.commandHash;
        bytes32 parent = effect.parentActionId;
        uint256 generation = effect.generation;
        uint256 priorAmount = record.priorAmount;
        uint256 priorFlag = record.priorFlag ? 1 : 0;
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(ptr, commandDigest)
            mstore(add(ptr, 0x20), parent)
            mstore(add(ptr, 0x40), generation)
            mstore(add(ptr, 0x60), priorAmount)
            mstore(add(ptr, 0x80), priorFlag)
            result := keccak256(ptr, 0xa0)
        }
    }

    function _popHash(bytes32 transitionHash, uint64 generation, bytes32 priorEffectHash)
        internal
        pure
        returns (bytes32 result)
    {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(ptr, transitionHash)
            mstore(add(ptr, 0x20), generation)
            mstore(add(ptr, 0x40), priorEffectHash)
            result := keccak256(ptr, 0x60)
        }
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
        bytes32 key = keccak256(abi.encode(TrustTypes.DOMAIN, "GOVERNANCE", governor, nonce));
        if (authorizationId == bytes32(0) || _usedGovernanceIds[authorizationId] || _usedGovernanceIds[key]) {
            revert TrustReplay(authorizationId);
        }
        _usedGovernanceIds[authorizationId] = true;
        _usedGovernanceIds[key] = true;
    }

    function _bindInitial(TrustTypes.BindingKind kind, address dependency, bytes32 schema) internal {
        if (dependency == address(0)) revert TrustZeroAddress();
        (bool ok, bytes32 config) = TrustPolicyBinding.readConfiguration(dependency);
        bytes32 code = TrustPolicyBinding.codeId(dependency);
        if (!ok || code == bytes32(0)) {
            revert TrustOperationalFailure(bytes32(0), 205, bytes32(uint256(uint160(dependency))));
        }
        bytes32 bindingHash = TrustPolicyBinding.compute(kind, dependency, code, config, schema, 1);
        _bindings[kind] = TrustTypes.Binding({
            dependency: dependency,
            codeId: code,
            configurationDigest: config,
            schema: schema,
            epoch: 1,
            bindingHash: bindingHash
        });
        emit TrustBindingChanged(kind, bytes32(0), bindingHash, 1);
    }

    function _bubble(bytes memory result) internal pure {
        if (result.length == 0) revert TrustUnsupported(msg.sig);
        assembly ("memory-safe") {
            revert(add(result, 32), mload(result))
        }
    }
}
