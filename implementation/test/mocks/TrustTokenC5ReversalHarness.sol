// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;
import {TrustToken} from "../../src/TrustToken.sol";
import {TrustTypes} from "../../src/TrustTypes.sol";

contract TrustTokenC5ReversalHarness is TrustToken {
    error C5InvalidHarnessInput();
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
    )
        TrustToken(
            name_,
            symbol_,
            decimals_,
            governor_,
            initialHolder,
            initialSupply,
            authorityRef,
            initialAuthority,
            policy,
            identity,
            settlement,
            entitlement,
            schema
        )
    {}

    function c5UnfreezeWitness(
        bytes32 reversalId,
        bytes32 actionId,
        bytes32 parentActionId,
        address subject,
        uint256 amount,
        uint256 priorAmount,
        bytes32 caseId,
        bytes32 currentEffectHash,
        bytes32 parentEffectHash,
        uint64 currentGeneration,
        bytes32 digest
    ) external returns (bytes32 actualWitness, bytes32 expectedWitness) {
        if (actionId == bytes32(0) || parentActionId == actionId) revert C5InvalidHarnessInput();
        _c5SeedAppliedFreeze(
            actionId,
            parentActionId,
            subject,
            amount,
            priorAmount,
            caseId,
            currentEffectHash,
            parentEffectHash,
            currentGeneration,
            digest
        );
        bytes32 popEffectHash = _popEffect(digest, _effects[actionId], _freezeHeads[subject]);
        _frozen[subject] = priorAmount;
        _actions[actionId].lifecycle = TrustTypes.Lifecycle.REVERSED;
        _terminalCases[caseId] = true;
        TrustTypes.EffectHead storage head = _freezeHeads[subject];
        TrustTypes.ActionRecord storage original = _actions[actionId];
        uint64 nextGeneration = currentGeneration + 1;
        bytes32 expectedPopHash = keccak256(abi.encode(digest, nextGeneration, currentEffectHash));
        bytes32 expectedHeadHash = parentActionId == bytes32(0) ? bytes32(0) : parentEffectHash;
        actualWitness = keccak256(
            abi.encode(
                _frozen[subject],
                head.actionId,
                head.effectHash,
                head.generation,
                original.lifecycle,
                _terminalCases[caseId],
                popEffectHash,
                reversalId
            )
        );
        expectedWitness = keccak256(
            abi.encode(
                priorAmount,
                parentActionId,
                expectedHeadHash,
                nextGeneration,
                TrustTypes.Lifecycle.REVERSED,
                true,
                expectedPopHash,
                reversalId
            )
        );
    }

    function c5ValidateCurrentEffectMaybeStale(
        bytes32 reversalId,
        bytes32 actionId,
        bytes32 parentActionId,
        bytes32 staleHeadActionId,
        address subject,
        uint256 amount,
        uint256 priorAmount,
        bytes32 caseId,
        uint64 currentGeneration,
        bytes32 digest,
        bool stale
    ) external {
        if (actionId == bytes32(0) || parentActionId == actionId || (stale && staleHeadActionId == actionId)) revert C5InvalidHarnessInput();
        _actions[actionId] = TrustTypes.ActionRecord({
            action: TrustTypes.ActionKind.FREEZE,
            lifecycle: TrustTypes.Lifecycle.APPLIED,
            subject: subject,
            source: subject,
            destination: address(0),
            custodian: address(0),
            amount: amount,
            priorAmount: priorAmount,
            priorFlag: false,
            caseId: caseId,
            authorityRef: bytes32(0),
            authorityEpoch: 0,
            policyEpoch: 0,
            commandHash: digest,
            evidenceHash: bytes32(0),
            receiptHash: bytes32(0)
        });
        TrustTypes.EffectRecord storage effect = _effects[actionId];
        effect.parentActionId = parentActionId;
        effect.generation = currentGeneration;
        effect.effectHash = _effectHash(_actions[actionId], effect);
        if (parentActionId != bytes32(0)) {
            _actions[parentActionId].action = TrustTypes.ActionKind.FREEZE;
            _actions[parentActionId].lifecycle = TrustTypes.Lifecycle.APPLIED;
            _actions[parentActionId].subject = subject;
        }
        _freezeHeads[subject] = TrustTypes.EffectHead({
            actionId: stale ? staleHeadActionId : actionId, effectHash: effect.effectHash, generation: currentGeneration
        });
        _frozen[subject] = amount;
        _validateCurrentEffect(reversalId, actionId, TrustTypes.ReversalKind.UNFREEZE, _actions[actionId]);
    }

    function _c5SeedAppliedFreeze(
        bytes32 actionId,
        bytes32 parentActionId,
        address subject,
        uint256 amount,
        uint256 priorAmount,
        bytes32 caseId,
        bytes32 currentEffectHash,
        bytes32 parentEffectHash,
        uint64 currentGeneration,
        bytes32 digest
    ) private {
        _actions[actionId] = TrustTypes.ActionRecord({
            action: TrustTypes.ActionKind.FREEZE,
            lifecycle: TrustTypes.Lifecycle.APPLIED,
            subject: subject,
            source: subject,
            destination: address(0),
            custodian: address(0),
            amount: amount,
            priorAmount: priorAmount,
            priorFlag: false,
            caseId: caseId,
            authorityRef: bytes32(0),
            authorityEpoch: 0,
            policyEpoch: 0,
            commandHash: digest,
            evidenceHash: bytes32(0),
            receiptHash: bytes32(0)
        });
        _effects[actionId] = TrustTypes.EffectRecord({
            parentActionId: parentActionId, effectHash: currentEffectHash, generation: currentGeneration
        });
        if (parentActionId != bytes32(0)) _effects[parentActionId].effectHash = parentEffectHash;
        _freezeHeads[subject] =
            TrustTypes.EffectHead({actionId: actionId, effectHash: currentEffectHash, generation: currentGeneration});
        _frozen[subject] = amount;
        _terminalCases[caseId] = false;
    }
}
