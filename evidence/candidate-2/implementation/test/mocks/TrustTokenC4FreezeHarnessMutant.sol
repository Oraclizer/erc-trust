// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustTokenC4FreezeIncrementMutant} from "../../src/TrustTokenC4FreezeIncrementMutant.sol";
import {TrustTypes} from "../../src/TrustTypes.sol";

/// @notice Verification-only C4 FREEZE seam over the production action-application function.
contract TrustTokenC4FreezeHarness is TrustTokenC4FreezeIncrementMutant {
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
        TrustTokenC4FreezeIncrementMutant(
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

    function c4FreezeApplyWitness(
        bytes32 actionId,
        address subject,
        uint256 amount,
        bytes32 caseId,
        uint256 oldFrozen,
        bytes32 parentActionId,
        bytes32 parentEffectHash,
        uint64 parentGeneration,
        bytes32 digest,
        bytes32 evidence
    ) external returns (bytes32 actualWitness, bytes32 expectedWitness) {
        TrustTypes.ActionRequest memory request = _c4SeedFreeze(
            actionId,
            subject,
            amount,
            caseId,
            oldFrozen,
            parentActionId,
            parentEffectHash,
            parentGeneration,
            TrustTypes.Lifecycle.PREPARED,
            digest,
            evidence
        );
        _applyActionPrepared(request, digest, evidence);
        bytes32 expectedEffectHash =
            keccak256(abi.encode(digest, parentActionId, parentGeneration + 1, oldFrozen, uint256(0)));
        actualWitness = _c4FreezeWitness(actionId, subject);
        expectedWitness = keccak256(
            abi.encode(
                amount,
                oldFrozen,
                TrustTypes.Lifecycle.APPLIED,
                digest,
                evidence,
                parentActionId,
                parentGeneration + 1,
                expectedEffectHash,
                actionId,
                parentGeneration + 1,
                expectedEffectHash
            )
        );
    }

    function c4FreezeApplyWithLifecycle(
        bytes32 actionId,
        address subject,
        uint256 amount,
        bytes32 caseId,
        uint256 oldFrozen,
        bytes32 parentActionId,
        bytes32 parentEffectHash,
        uint64 parentGeneration,
        bytes32 digest,
        bytes32 evidence,
        bool makePrepared
    ) external {
        TrustTypes.ActionRequest memory request = _c4SeedFreeze(
            actionId,
            subject,
            amount,
            caseId,
            oldFrozen,
            parentActionId,
            parentEffectHash,
            parentGeneration,
            makePrepared ? TrustTypes.Lifecycle.PREPARED : TrustTypes.Lifecycle.NONE,
            digest,
            evidence
        );
        _applyActionPrepared(request, digest, evidence);
    }

    function _c4SeedFreeze(
        bytes32 actionId,
        address subject,
        uint256 amount,
        bytes32 caseId,
        uint256 oldFrozen,
        bytes32 parentActionId,
        bytes32 parentEffectHash,
        uint64 parentGeneration,
        TrustTypes.Lifecycle lifecycle,
        bytes32 digest,
        bytes32 evidence
    ) private returns (TrustTypes.ActionRequest memory request) {
        _frozen[subject] = oldFrozen;
        _freezeHeads[subject] = TrustTypes.EffectHead({
            actionId: parentActionId, effectHash: parentEffectHash, generation: parentGeneration
        });
        _actions[actionId] = TrustTypes.ActionRecord({
            action: TrustTypes.ActionKind.FREEZE,
            lifecycle: lifecycle,
            subject: subject,
            source: subject,
            destination: address(0),
            custodian: address(0),
            amount: amount,
            priorAmount: 0,
            priorFlag: false,
            caseId: caseId,
            authorityRef: bytes32(0),
            authorityEpoch: 0,
            policyEpoch: 0,
            commandHash: digest,
            evidenceHash: evidence,
            receiptHash: bytes32(0)
        });
        request = TrustTypes.ActionRequest({
            domain: TrustTypes.DOMAIN,
            actionId: actionId,
            action: TrustTypes.ActionKind.FREEZE,
            subject: subject,
            source: subject,
            destination: address(0),
            custodian: address(0),
            amount: amount,
            caseId: caseId,
            scopeHash: bytes32(uint256(1)),
            policyCommitment: bytes32(uint256(2)),
            provenanceCommitment: bytes32(uint256(3)),
            settlementCommitment: bytes32(0),
            proceedsCommitment: bytes32(0),
            entitlementCommitment: bytes32(0),
            authorityRef: bytes32(0),
            authorityEpoch: 0,
            policyEpoch: 0,
            nonce: 0,
            validAfter: 0,
            validBefore: type(uint48).max
        });
    }

    function _c4FreezeWitness(bytes32 actionId, address subject) private view returns (bytes32) {
        TrustTypes.ActionRecord storage record = _actions[actionId];
        TrustTypes.EffectRecord storage effect = _effects[actionId];
        TrustTypes.EffectHead storage head = _freezeHeads[subject];
        return keccak256(
            abi.encode(
                _frozen[subject],
                record.priorAmount,
                record.lifecycle,
                record.commandHash,
                record.evidenceHash,
                effect.parentActionId,
                effect.generation,
                effect.effectHash,
                head.actionId,
                head.generation,
                head.effectHash
            )
        );
    }
}
