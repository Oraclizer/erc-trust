// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {IERC165} from "../interfaces/IERC165.sol";
import {IERCTrustProfile} from "../interfaces/IERCTrustProfile.sol";
import {
    IERC3643TokenView,
    IERC3643TokenMutator,
    IERC3643IdentityRegistry,
    IERC3643Compliance
} from "../interfaces/IERC3643External.sol";
import {TrustTypes} from "../TrustTypes.sol";
import {TrustDecision} from "../TrustDecision.sol";
import {ProfileGovernor} from "./ProfileGovernor.sol";
import {
    TrustRejected,
    TrustOperationalFailure,
    TrustUnauthorized,
    TrustReplay,
    TrustInvalidCommand,
    TrustTerminal,
    TrustReentrancy,
    TrustZeroAddress
} from "../TrustErrors.sol";

/// @notice ERC-TRUST six-action adapter for a sealed ERC-3643 conformance unit.
/// @dev Unauthenticated, unsealed, malformed, and drifted upstream paths fail closed.
contract ERC3643TrustAdapter is IERCTrustProfile {
    bytes32 internal constant DOMAIN = keccak256("ERC-TRUST/reference-v1");
    bytes32 internal constant PROFILE = keccak256("ERC-TRUST-ERC3643-VERIFIED-FULL-V1");
    uint16 internal constant REASON_DOMAIN = 401;
    uint16 internal constant REASON_ID = 402;
    uint16 internal constant REASON_TIME = 403;
    uint16 internal constant REASON_AUTHORITY = 404;
    uint16 internal constant REASON_SHAPE = 405;
    uint16 internal constant REASON_TOPOLOGY = 406;
    uint16 internal constant REASON_IDENTITY = 407;
    uint16 internal constant REASON_COMPLIANCE = 408;
    uint16 internal constant REASON_UPSTREAM = 409;
    uint16 internal constant REASON_CUSTODY = 410;
    uint16 internal constant REASON_ENTITLEMENT = 411;
    uint256 internal constant ACTION_CALLDATA_LENGTH = 676;
    uint256 internal constant REVERSAL_CALLDATA_LENGTH = 292;

    address public immutable token;
    address public immutable authority;
    bytes32 public immutable authorityRef;
    uint64 public immutable authorityEpoch;
    ProfileGovernor public immutable profileGovernor;
    IERC3643TokenView internal immutable _tokenView;

    uint256 private _entered;
    mapping(bytes32 => TrustTypes.ActionRecord) private _actions;
    mapping(bytes32 => TrustTypes.EffectRecord) private _effects;
    mapping(bytes32 => TrustTypes.Receipt) private _receipts;
    mapping(bytes32 => bool) private _usedIds;
    mapping(bytes32 => bool) private _usedNonces;
    mapping(bytes32 => bool) private _consumedEntitlements;
    mapping(bytes32 => TrustTypes.CustodyRecord) private _custody;
    mapping(address => uint256) private _frozenTargets;
    mapping(address => TrustTypes.EffectHead) private _freezeHeads;
    mapping(address => TrustTypes.EffectHead) private _restrictionHeads;
    mapping(address => uint256) private _custodyBacking;
    mapping(bytes32 => bool) private _terminalCases;

    modifier nonReentrant() {
        if (_entered != 0) revert TrustReentrancy();
        _entered = 1;
        _;
        _entered = 0;
    }

    constructor(address profileGovernor_, address authority_, bytes32 authorityRef_, uint64 authorityEpoch_) {
        if (
            profileGovernor_ == address(0) || authority_ == address(0) || authorityRef_ == bytes32(0)
                || authorityEpoch_ == 0
        ) {
            revert TrustZeroAddress();
        }
        profileGovernor = ProfileGovernor(profileGovernor_);
        token = ProfileGovernor(profileGovernor_).token();
        _tokenView = IERC3643TokenView(token);
        authority = authority_;
        authorityRef = authorityRef_;
        authorityEpoch = authorityEpoch_;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId != 0xffffffff
            && (interfaceId == type(IERC165).interfaceId || interfaceId == type(IERCTrustProfile).interfaceId);
    }

    function trustProfile()
        external
        view
        returns (bytes32 profile, uint256 supportedActionMask, bool proxySupported, bool full)
    {
        return (PROFILE, 0x3f, false, profileGovernor.isFull(address(this)));
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

    function custody(bytes32 caseId) external view returns (TrustTypes.CustodyRecord memory) {
        return _custody[caseId];
    }

    function deriveActionId(TrustTypes.ActionRequest calldata request) public view returns (bytes32) {
        TrustTypes.ActionRequest memory normalized = request;
        normalized.actionId = bytes32(0);
        return keccak256(abi.encode(DOMAIN, address(this), block.chainid, normalized));
    }

    function deriveReversalId(TrustTypes.ReversalRequest calldata request) public view returns (bytes32) {
        TrustTypes.ReversalRequest memory normalized = request;
        normalized.reversalId = bytes32(0);
        return keccak256(abi.encode(DOMAIN, address(this), block.chainid, normalized));
    }

    function executeRegulatoryAction(TrustTypes.ActionRequest calldata request)
        external
        nonReentrant
        returns (bytes32 receiptHash)
    {
        _requireCalldataLength(ACTION_CALLDATA_LENGTH);
        _validateAction(request);
        bytes32 nonceKey = TrustDecision.nonceKey(request.authorityRef, request.authorityEpoch, request.nonce);
        _consume(request.actionId, nonceKey);

        address destination = request.action == TrustTypes.ActionKind.SEIZE ? request.custodian : request.destination;
        bytes32 preState = _observation(request.subject, request.source, destination, request.caseId);
        TrustTypes.ActionRecord storage record = _actions[request.actionId];
        record.action = request.action;
        record.lifecycle = TrustTypes.Lifecycle.PREPARED;
        record.subject = request.subject;
        record.source = request.source;
        record.destination = request.destination;
        record.custodian = request.custodian;
        record.amount = request.amount;
        record.caseId = request.caseId;
        record.authorityRef = request.authorityRef;
        record.authorityEpoch = request.authorityEpoch;
        record.policyEpoch = request.policyEpoch;
        record.commandHash = request.actionId;
        record.evidenceHash = keccak256(
            abi.encode(
                profileGovernor.sealedBinding(),
                request.policyCommitment,
                request.provenanceCommitment,
                request.settlementCommitment,
                request.proceedsCommitment,
                request.entitlementCommitment
            )
        );

        if (request.action == TrustTypes.ActionKind.FREEZE) {
            record.priorAmount = _frozenTargets[request.subject];
            _pushEffect(request.actionId, record, _freezeHeads[request.subject]);
            _frozenTargets[request.subject] = request.amount;
            _setFrozenAmount(request.actionId, request.subject, request.amount);
        } else if (request.action == TrustTypes.ActionKind.RESTRICT) {
            record.priorFlag = _tokenView.isFrozen(request.subject);
            _pushEffect(request.actionId, record, _restrictionHeads[request.subject]);
            _callVoid(request.actionId, abi.encodeCall(IERC3643TokenMutator.setAddressFrozen, (request.subject, true)));
            if (!_tokenView.isFrozen(request.subject)) _upstreamFailure(request.actionId);
        } else {
            if (request.action == TrustTypes.ActionKind.SEIZE) {
                if (_custody[request.caseId].active) {
                    revert TrustInvalidCommand(request.actionId, REASON_CUSTODY);
                }
                _requireUnbacked(request.source, request.amount, request.actionId);
            } else {
                bool consumedCustody = _consumeMatchingCustody(request);
                if (!consumedCustody) _requireUnbacked(request.source, request.amount, request.actionId);
                if (
                    request.action == TrustTypes.ActionKind.RECOVER
                        && _consumedEntitlements[request.entitlementCommitment]
                ) {
                    revert TrustInvalidCommand(request.actionId, REASON_ENTITLEMENT);
                }
            }
            _assessTransfer(request.actionId, request.source, destination, request.amount);
            _forcedTransfer(request.actionId, request.source, destination, request.amount);
            if (request.action == TrustTypes.ActionKind.SEIZE) {
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
            } else {
                _terminalCases[request.caseId] = true;
                if (request.action == TrustTypes.ActionKind.RECOVER) {
                    _consumedEntitlements[request.entitlementCommitment] = true;
                }
            }
        }

        record.lifecycle = TrustTypes.Lifecycle.APPLIED;
        bytes32 postState = _observation(request.subject, request.source, destination, request.caseId);
        bytes32 externalCommitment = request.action == TrustTypes.ActionKind.LIQUIDATE
            ? keccak256(abi.encode(request.settlementCommitment, request.proceedsCommitment))
            : request.action == TrustTypes.ActionKind.RECOVER ? request.entitlementCommitment : bytes32(0);
        receiptHash = keccak256(
            abi.encode(
                DOMAIN,
                request.actionId,
                uint8(request.action),
                request.source,
                destination,
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
            destination: destination,
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
        emit RegulatoryActionApplied(request.actionId, request.action, request.caseId, receiptHash);
    }

    function executeRegulatoryReversal(TrustTypes.ReversalRequest calldata request)
        external
        nonReentrant
        returns (bytes32 receiptHash)
    {
        _requireCalldataLength(REVERSAL_CALLDATA_LENGTH);
        _validateReversal(request);
        bytes32 nonceKey = TrustDecision.nonceKey(request.authorityRef, request.authorityEpoch, request.nonce);
        _consume(request.reversalId, nonceKey);

        TrustTypes.ActionRecord storage original = _actions[request.actionId];
        TrustTypes.EffectRecord storage originalEffect = _effects[request.actionId];
        bytes32 preState = _observation(
            original.subject,
            original.source,
            original.action == TrustTypes.ActionKind.SEIZE ? original.custodian : original.destination,
            original.caseId
        );
        address destination;
        bytes32 popEffectHash;
        if (request.reversal == TrustTypes.ReversalKind.UNFREEZE) {
            destination = original.subject;
            popEffectHash = _popEffect(request.reversalId, originalEffect, _freezeHeads[original.subject]);
            _frozenTargets[original.subject] = original.priorAmount;
            _setFrozenAmount(request.reversalId, original.subject, original.priorAmount);
        } else if (request.reversal == TrustTypes.ReversalKind.UNRESTRICT) {
            destination = original.subject;
            popEffectHash = _popEffect(request.reversalId, originalEffect, _restrictionHeads[original.subject]);
            _callVoid(
                request.reversalId,
                abi.encodeCall(IERC3643TokenMutator.setAddressFrozen, (original.subject, original.priorFlag))
            );
            if (_tokenView.isFrozen(original.subject) != original.priorFlag) {
                _upstreamFailure(request.reversalId);
            }
        } else {
            TrustTypes.CustodyRecord storage held = _custody[original.caseId];
            if (
                !held.active || held.custodian != original.custodian || held.declaredPriorHolder != original.source
                    || held.encumberedAmount != original.amount
            ) {
                revert TrustInvalidCommand(request.reversalId, REASON_CUSTODY);
            }
            destination = held.declaredPriorHolder;
            uint64 nextGeneration = held.generation + 1;
            popEffectHash = _popHash(request.reversalId, nextGeneration, originalEffect.effectHash);
            _custodyBacking[held.custodian] -= original.amount;
            _assessTransfer(request.reversalId, held.custodian, destination, original.amount);
            _forcedTransfer(request.reversalId, held.custodian, destination, original.amount);
            held.active = false;
            held.encumberedAmount = 0;
            held.actionId = originalEffect.parentActionId;
            held.effectHash = originalEffect.parentActionId == bytes32(0)
                ? bytes32(0)
                : _effects[originalEffect.parentActionId].effectHash;
            held.generation = nextGeneration;
        }

        original.lifecycle = TrustTypes.Lifecycle.REVERSED;
        _terminalCases[original.caseId] = true;
        bytes32 postState = _observation(original.subject, original.source, destination, original.caseId);
        receiptHash = keccak256(
            abi.encode(
                DOMAIN,
                request.reversalId,
                uint8(request.reversal),
                request.actionId,
                original.source,
                destination,
                original.amount,
                original.caseId,
                preState,
                postState,
                request.reversalId,
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
            policyBinding: profileGovernor.sealedBinding(),
            provenanceCommitment: bytes32(0),
            preState: preState,
            postState: postState,
            externalCommitment: popEffectHash,
            receiptHash: receiptHash
        });
        emit RegulatoryReversalApplied(request.reversalId, request.reversal, request.actionId, receiptHash);
    }

    function _validateAction(TrustTypes.ActionRequest calldata request) internal view {
        _validateCommon(
            request.domain,
            request.actionId,
            deriveActionId(request),
            request.authorityRef,
            request.authorityEpoch,
            request.validAfter,
            request.validBefore
        );
        if (request.policyCommitment != profileGovernor.sealedBinding() || request.policyEpoch != 1) {
            revert TrustInvalidCommand(request.actionId, REASON_TOPOLOGY);
        }
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
            _validateUnusedCommitments(request);
            return;
        }
        if (request.action == TrustTypes.ActionKind.RESTRICT) {
            if (
                request.source != request.subject || request.destination != address(0)
                    || request.custodian != address(0)
            ) {
                revert TrustInvalidCommand(request.actionId, REASON_SHAPE);
            }
            _validateUnusedCommitments(request);
            return;
        }
        address destination = request.action == TrustTypes.ActionKind.SEIZE ? request.custodian : request.destination;
        if (
            request.source == address(0) || destination == address(0) || request.source == destination
                || request.amount == 0
                || (request.action == TrustTypes.ActionKind.SEIZE && request.subject != request.source)
                || (request.action == TrustTypes.ActionKind.SEIZE
                    && (request.destination != address(this) || request.custodian != address(this)))
        ) {
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
        _validateUnusedCommitments(request);
    }

    function _validateUnusedCommitments(TrustTypes.ActionRequest calldata request) internal pure {
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

    function _validateReversal(TrustTypes.ReversalRequest calldata request) internal view {
        _validateCommon(
            request.domain,
            request.reversalId,
            deriveReversalId(request),
            request.authorityRef,
            request.authorityEpoch,
            request.validAfter,
            request.validBefore
        );
        TrustTypes.ActionRecord storage original = _actions[request.actionId];
        if (original.lifecycle != TrustTypes.Lifecycle.APPLIED) revert TrustTerminal(request.actionId);
        if (!TrustDecision.reversalMatches(original.action, request.reversal)) {
            revert TrustInvalidCommand(request.reversalId, REASON_SHAPE);
        }
        _validateCurrentEffect(request.reversalId, request.actionId, request.reversal, original);
    }

    function _validateCommon(
        bytes32 domain,
        bytes32 id,
        bytes32 derived,
        bytes32 requestAuthorityRef,
        uint64 requestAuthorityEpoch,
        uint48 validAfter,
        uint48 validBefore
    ) internal view {
        if (!profileGovernor.isFull(address(this))) {
            revert TrustOperationalFailure(id, REASON_TOPOLOGY, bytes32(uint256(uint160(token))));
        }
        if (msg.sender != authority) revert TrustUnauthorized(msg.sender, requestAuthorityRef);
        if (domain != DOMAIN) revert TrustInvalidCommand(id, REASON_DOMAIN);
        if (id == bytes32(0) || id != derived) revert TrustInvalidCommand(id, REASON_ID);
        if (requestAuthorityRef != authorityRef || requestAuthorityEpoch != authorityEpoch) {
            revert TrustInvalidCommand(id, REASON_AUTHORITY);
        }
        if (block.timestamp < validAfter || block.timestamp > validBefore || validAfter > validBefore) {
            revert TrustInvalidCommand(id, REASON_TIME);
        }
    }

    function _consume(bytes32 id, bytes32 nonceKey) internal {
        if (_usedIds[id] || _usedNonces[nonceKey]) revert TrustReplay(id);
        _usedIds[id] = true;
        _usedNonces[nonceKey] = true;
    }

    function _assessTransfer(bytes32 id, address from, address to, uint256 amount) internal view {
        (bool identityOk, bytes memory identityResult) =
            profileGovernor.identityRegistry().staticcall(abi.encodeCall(IERC3643IdentityRegistry.isVerified, (to)));
        uint256 identityWord = _boolWord(identityResult);
        if (!identityOk || identityWord > 1) {
            revert TrustOperationalFailure(
                id, REASON_IDENTITY, bytes32(uint256(uint160(profileGovernor.identityRegistry())))
            );
        }
        if (identityWord == 0) revert TrustRejected(id, REASON_IDENTITY);

        (bool complianceOk, bytes memory complianceResult) =
            profileGovernor.compliance().staticcall(abi.encodeCall(IERC3643Compliance.canTransfer, (from, to, amount)));
        uint256 complianceWord = _boolWord(complianceResult);
        if (!complianceOk || complianceWord > 1) {
            revert TrustOperationalFailure(
                id, REASON_COMPLIANCE, bytes32(uint256(uint160(profileGovernor.compliance())))
            );
        }
        if (complianceWord == 0) revert TrustRejected(id, REASON_COMPLIANCE);
    }

    function _forcedTransfer(bytes32 id, address from, address to, uint256 amount) internal {
        uint256 beforeFrom = _tokenView.balanceOf(from);
        uint256 beforeTo = _tokenView.balanceOf(to);
        (bool ok, bytes memory result) =
            token.call(abi.encodeCall(IERC3643TokenMutator.forcedTransfer, (from, to, amount)));
        if (!ok || _boolWord(result) != 1) _upstreamFailure(id);
        if (
            beforeFrom < amount || _tokenView.balanceOf(from) != beforeFrom - amount
                || _tokenView.balanceOf(to) != beforeTo + amount
        ) {
            _upstreamFailure(id);
        }
        _setFrozenAmount(id, from, _frozenTargets[from]);
        _setFrozenAmount(id, to, _frozenTargets[to]);
    }

    function _setFrozenAmount(bytes32 id, address account, uint256 target) internal {
        uint256 balance = _tokenView.balanceOf(account);
        if (target > balance) target = balance;
        uint256 current = _tokenView.getFrozenTokens(account);
        if (target > current) {
            _callVoid(id, abi.encodeCall(IERC3643TokenMutator.freezePartialTokens, (account, target - current)));
        } else if (current > target) {
            _callVoid(id, abi.encodeCall(IERC3643TokenMutator.unfreezePartialTokens, (account, current - target)));
        }
        if (_tokenView.getFrozenTokens(account) != target) _upstreamFailure(id);
    }

    function _consumeMatchingCustody(TrustTypes.ActionRequest calldata request) internal returns (bool consumed) {
        TrustTypes.CustodyRecord storage existing = _custody[request.caseId];
        if (!existing.active) return false;
        if (
            existing.custodian != request.source || existing.declaredPriorHolder != request.subject
                || existing.encumberedAmount != request.amount || existing.actionId == bytes32(0)
                || existing.effectHash != _effects[existing.actionId].effectHash
                || _custodyBacking[existing.custodian] < existing.encumberedAmount
        ) {
            revert TrustInvalidCommand(request.actionId, REASON_CUSTODY);
        }
        uint64 nextGeneration = existing.generation + 1;
        existing.effectHash = _popHash(request.actionId, nextGeneration, existing.effectHash);
        _custodyBacking[existing.custodian] -= existing.encumberedAmount;
        existing.active = false;
        existing.encumberedAmount = 0;
        existing.actionId = existing.parentActionId;
        existing.generation = nextGeneration;
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
            revert TrustInvalidCommand(reversalId, REASON_SHAPE);
        }
        if (effect.parentActionId != bytes32(0)) {
            TrustTypes.ActionRecord storage parent = _actions[effect.parentActionId];
            if (
                parent.lifecycle != TrustTypes.Lifecycle.APPLIED || parent.action != original.action
                    || parent.subject != original.subject
            ) {
                revert TrustInvalidCommand(reversalId, REASON_SHAPE);
            }
        }
        if (reversal == TrustTypes.ReversalKind.UNFREEZE) {
            TrustTypes.EffectHead storage head = _freezeHeads[original.subject];
            if (
                head.actionId != actionId || head.effectHash != effect.effectHash || head.generation < effect.generation
                    || _frozenTargets[original.subject] != original.amount
            ) {
                revert TrustInvalidCommand(reversalId, REASON_SHAPE);
            }
        } else if (reversal == TrustTypes.ReversalKind.UNRESTRICT) {
            TrustTypes.EffectHead storage head = _restrictionHeads[original.subject];
            if (
                head.actionId != actionId || head.effectHash != effect.effectHash || head.generation < effect.generation
                    || !_tokenView.isFrozen(original.subject)
            ) {
                revert TrustInvalidCommand(reversalId, REASON_SHAPE);
            }
        } else {
            TrustTypes.CustodyRecord storage held = _custody[original.caseId];
            if (
                !held.active || held.actionId != actionId || held.effectHash != effect.effectHash
                    || held.generation < effect.generation || held.custodian != original.custodian
                    || held.declaredPriorHolder != original.source || held.encumberedAmount != original.amount
                    || _custodyBacking[held.custodian] < held.encumberedAmount
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
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                record.commandHash, effect.parentActionId, effect.generation, record.priorAmount, record.priorFlag
            )
        );
    }

    function _popHash(bytes32 transitionHash, uint64 generation, bytes32 priorEffectHash)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(transitionHash, generation, priorEffectHash));
    }

    function _requireUnbacked(address account, uint256 amount, bytes32 commandId) internal view {
        uint256 balance = _tokenView.balanceOf(account);
        uint256 backing = _custodyBacking[account];
        if (balance < backing || amount > balance - backing) {
            revert TrustInvalidCommand(commandId, REASON_CUSTODY);
        }
    }

    function _boolWord(bytes memory result) internal pure returns (uint256 word) {
        if (result.length != 32) return 2;
        assembly ("memory-safe") {
            word := mload(add(result, 0x20))
        }
    }

    function _requireCalldataLength(uint256 expected) internal pure {
        assembly ("memory-safe") {
            if xor(calldatasize(), expected) { revert(0, 0) }
        }
    }

    function _callVoid(bytes32 id, bytes memory data) internal {
        (bool ok, bytes memory result) = token.call(data);
        if (!ok || result.length != 0) _upstreamFailure(id);
    }

    function _upstreamFailure(bytes32 id) internal view {
        revert TrustOperationalFailure(id, REASON_UPSTREAM, bytes32(uint256(uint160(token))));
    }

    function _observation(address subject, address source, address destination, bytes32 caseId)
        internal
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                token,
                _tokenView.balanceOf(subject),
                _frozenTargets[subject],
                _tokenView.getFrozenTokens(subject),
                _tokenView.isFrozen(subject),
                _tokenView.balanceOf(source),
                _custodyBacking[source],
                _tokenView.balanceOf(destination),
                _custodyBacking[destination],
                _custody[caseId],
                _freezeHeads[subject],
                _restrictionHeads[subject],
                _terminalCases[caseId],
                profileGovernor.sealedBinding()
            )
        );
    }
}
