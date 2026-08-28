// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustTokenC4CustodyAccountingOmissionMutant} from "../../src/TrustTokenC4CustodyAccountingOmissionMutant.sol";
import {TrustTypes} from "../../src/TrustTypes.sol";

/// @notice Verification-only C4 seam for the non-FREEZE forward-effect claims.
contract TrustTokenC4RemainingHarness is TrustTokenC4CustodyAccountingOmissionMutant {
    error C4InvalidHarnessInput();

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
        TrustTokenC4CustodyAccountingOmissionMutant(
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

    function c4RestrictWitness(
        bytes32 actionId,
        address subject,
        bytes32 caseId,
        bool oldRestricted,
        bytes32 parentActionId,
        bytes32 parentEffectHash,
        uint64 parentGeneration,
        bytes32 digest,
        bytes32 evidence
    ) external returns (bytes32 actualWitness, bytes32 expectedWitness) {
        TrustTypes.ActionRequest memory request = _c4Request(
            actionId, TrustTypes.ActionKind.RESTRICT, subject, subject, address(0), address(0), 0, caseId
        );
        _c4SeedRecord(request, digest, evidence);
        _restricted[subject] = oldRestricted;
        _restrictionHeads[subject] = TrustTypes.EffectHead({
            actionId: parentActionId, effectHash: parentEffectHash, generation: parentGeneration
        });
        _applyActionPrepared(request, digest, evidence);
        TrustTypes.ActionRecord storage record = _actions[actionId];
        TrustTypes.EffectRecord storage effect = _effects[actionId];
        TrustTypes.EffectHead storage head = _restrictionHeads[subject];
        bytes32 expectedEffectHash =
            keccak256(abi.encode(digest, parentActionId, parentGeneration + 1, uint256(0), oldRestricted ? 1 : 0));
        actualWitness = keccak256(
            abi.encode(
                _restricted[subject],
                record.priorFlag,
                record.lifecycle,
                effect.parentActionId,
                effect.generation,
                effect.effectHash,
                head.actionId,
                head.generation,
                head.effectHash
            )
        );
        expectedWitness = keccak256(
            abi.encode(
                true,
                oldRestricted,
                TrustTypes.Lifecycle.APPLIED,
                parentActionId,
                parentGeneration + 1,
                expectedEffectHash,
                actionId,
                parentGeneration + 1,
                expectedEffectHash
            )
        );
    }

    function c4SeizeWitness(
        bytes32 actionId,
        address source,
        address custodian,
        uint256 amount,
        bytes32 caseId,
        uint256 sourceBalance,
        uint256 custodianBalance,
        uint256 oldCustodyBacking,
        bytes32 digest,
        bytes32 evidence
    ) external returns (bytes32 actualWitness, bytes32 expectedWitness) {
        if (source == address(0) || custodian == address(0) || source == custodian || amount > sourceBalance) {
            revert C4InvalidHarnessInput();
        }
        TrustTypes.ActionRequest memory request =
            _c4Request(actionId, TrustTypes.ActionKind.SEIZE, source, source, custodian, custodian, amount, caseId);
        _c4SeedRecord(request, digest, evidence);
        _balances[source] = sourceBalance;
        _balances[custodian] = custodianBalance;
        _custodyBacking[source] = 0;
        _custodyBacking[custodian] = oldCustodyBacking;
        delete _custody[caseId];
        _applyActionPrepared(request, digest, evidence);
        TrustTypes.CustodyRecord storage custody = _custody[caseId];
        TrustTypes.EffectRecord storage effect = _effects[actionId];
        bytes32 expectedEffectHash = keccak256(abi.encode(digest, bytes32(0), uint64(1), uint256(0), uint256(0)));
        actualWitness = keccak256(
            abi.encode(
                _balances[source],
                _balances[custodian],
                _custodyBacking[custodian],
                custody.custodian,
                custody.declaredPriorHolder,
                custody.encumberedAmount,
                custody.actionId,
                custody.parentActionId,
                custody.effectHash,
                custody.generation,
                custody.active,
                effect.effectHash,
                _actions[actionId].lifecycle
            )
        );
        expectedWitness = keccak256(
            abi.encode(
                sourceBalance - amount,
                custodianBalance + amount,
                oldCustodyBacking + amount,
                custodian,
                source,
                amount,
                actionId,
                bytes32(0),
                expectedEffectHash,
                uint64(1),
                true,
                expectedEffectHash,
                TrustTypes.Lifecycle.APPLIED
            )
        );
    }

    function c4DirectDispositionWitness(
        bytes32 actionId,
        address source,
        address destination,
        uint256 amount,
        bytes32 caseId,
        uint256 sourceBalance,
        uint256 destinationBalance,
        bytes32 digest,
        bytes32 evidence
    ) external returns (bytes32 actualWitness, bytes32 expectedWitness) {
        if (source == address(0) || destination == address(0) || source == destination || amount > sourceBalance) {
            revert C4InvalidHarnessInput();
        }
        TrustTypes.ActionRequest memory request = _c4Request(
            actionId, TrustTypes.ActionKind.CONFISCATE, source, source, destination, address(0), amount, caseId
        );
        _c4SeedRecord(request, digest, evidence);
        _balances[source] = sourceBalance;
        _balances[destination] = destinationBalance;
        _custodyBacking[source] = 0;
        delete _custody[caseId];
        _terminalCases[caseId] = false;
        _applyActionPrepared(request, digest, evidence);
        actualWitness = keccak256(
            abi.encode(
                _balances[source],
                _balances[destination],
                _terminalCases[caseId],
                _actions[actionId].lifecycle,
                _custody[caseId].active
            )
        );
        expectedWitness = keccak256(
            abi.encode(sourceBalance - amount, destinationBalance + amount, true, TrustTypes.Lifecycle.APPLIED, false)
        );
    }

    function c4CustodyDispositionWitness(
        bytes32 actionId,
        bytes32 priorCustodyActionId,
        bytes32 priorParentActionId,
        address beneficialHolder,
        address custodian,
        address destination,
        uint256 amount,
        bytes32 caseId,
        uint256 custodianBalance,
        uint256 destinationBalance,
        uint256 oldCustodyBacking,
        bytes32 priorEffectHash,
        uint64 priorGeneration,
        bytes32 digest,
        bytes32 evidence
    ) external returns (bytes32 actualWitness, bytes32 expectedWitness) {
        if (
            beneficialHolder == address(0) || custodian == address(0) || destination == address(0)
                || custodian == destination || amount > custodianBalance || amount > oldCustodyBacking
                || priorCustodyActionId == bytes32(0)
        ) revert C4InvalidHarnessInput();
        TrustTypes.ActionRequest memory request = _c4Request(
            actionId,
            TrustTypes.ActionKind.CONFISCATE,
            beneficialHolder,
            custodian,
            destination,
            address(0),
            amount,
            caseId
        );
        _c4SeedRecord(request, digest, evidence);
        _balances[custodian] = custodianBalance;
        _balances[destination] = destinationBalance;
        _custodyBacking[custodian] = oldCustodyBacking;
        _effects[priorCustodyActionId].effectHash = priorEffectHash;
        _custody[caseId] = TrustTypes.CustodyRecord({
            custodian: custodian,
            declaredPriorHolder: beneficialHolder,
            encumberedAmount: amount,
            actionId: priorCustodyActionId,
            parentActionId: priorParentActionId,
            effectHash: priorEffectHash,
            generation: priorGeneration,
            active: true
        });
        _terminalCases[caseId] = false;
        _applyActionPrepared(request, digest, evidence);
        TrustTypes.CustodyRecord storage custody = _custody[caseId];
        actualWitness = keccak256(
            abi.encode(
                _balances[custodian],
                _balances[destination],
                _custodyBacking[custodian],
                custody.active,
                custody.encumberedAmount,
                _terminalCases[caseId],
                _actions[actionId].lifecycle
            )
        );
        expectedWitness = keccak256(
            abi.encode(
                custodianBalance - amount,
                destinationBalance + amount,
                oldCustodyBacking - amount,
                false,
                uint256(0),
                true,
                TrustTypes.Lifecycle.APPLIED
            )
        );
    }

    function _c4SeedRecord(TrustTypes.ActionRequest memory request, bytes32 digest, bytes32 evidence) private {
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
            evidenceHash: evidence,
            receiptHash: bytes32(0)
        });
    }

    function _c4Request(
        bytes32 actionId,
        TrustTypes.ActionKind action,
        address subject,
        address source,
        address destination,
        address custodian,
        uint256 amount,
        bytes32 caseId
    ) private pure returns (TrustTypes.ActionRequest memory request) {
        request = TrustTypes.ActionRequest({
            domain: TrustTypes.DOMAIN,
            actionId: actionId,
            action: action,
            subject: subject,
            source: source,
            destination: destination,
            custodian: custodian,
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
}
