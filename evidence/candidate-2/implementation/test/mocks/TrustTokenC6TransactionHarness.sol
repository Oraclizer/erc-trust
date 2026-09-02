// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustToken} from "../../src/TrustToken.sol";
import {TrustTypes} from "../../src/TrustTypes.sol";
import {IERC7943Fungible} from "../../src/interfaces/IERC7943.sol";

/// @notice Verification-only C6 transaction shell over production auth, route, effect, and receipt functions.
contract TrustTokenC6TransactionHarness is TrustToken {
    error C6ForcedPostApplyFailure();

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

    function c6FreezeSuccessWitness(TrustTypes.ActionRequest calldata request, bytes32 digest, bytes32 evidence)
        external
        returns (bytes32 actualWitness, bytes32 expectedWitness)
    {
        bytes32 returnedReceipt = _c6FreezeTransaction(request, digest, evidence, false);
        TrustTypes.Receipt storage stored = _receipts[request.actionId];
        TrustTypes.ActionRecord storage record = _actions[request.actionId];
        bytes32 recomputed = keccak256(
            abi.encode(
                TrustTypes.DOMAIN,
                stored.commandId,
                stored.commandKind,
                stored.source,
                stored.destination,
                stored.amount,
                stored.caseId,
                stored.policyBinding,
                stored.provenanceCommitment,
                stored.preState,
                stored.postState,
                stored.externalCommitment
            )
        );
        actualWitness = keccak256(
            abi.encode(
                returnedReceipt,
                stored.receiptHash,
                record.receiptHash,
                recomputed,
                record.lifecycle,
                _usedCommandIds[request.actionId],
                _usedNonces[request.authorityRef][request.authorityEpoch][request.nonce],
                _routeTicket.live
            )
        );
        expectedWitness = keccak256(
            abi.encode(
                returnedReceipt,
                returnedReceipt,
                returnedReceipt,
                returnedReceipt,
                TrustTypes.Lifecycle.APPLIED,
                true,
                true,
                false
            )
        );
    }

    function c6FreezeTransactionMaybeFail(
        TrustTypes.ActionRequest calldata request,
        bytes32 digest,
        bytes32 evidence,
        bool forcePostApplyFailure
    ) external {
        _c6BoundedRollbackProbe(request, digest, evidence, forcePostApplyFailure);
    }

    function _c6FreezeTransaction(
        TrustTypes.ActionRequest calldata request,
        bytes32 digest,
        bytes32 evidence,
        bool forcePostApplyFailure
    ) private returns (bytes32 receiptHash) {
        if (request.action != TrustTypes.ActionKind.FREEZE) revert C6ForcedPostApplyFailure();
        _consumeActionAuthorization(request, digest);
        _actions[request.actionId].evidenceHash = evidence;
        bytes memory data = abi.encodeCall(IERC7943Fungible.setFrozenTokens, (request.subject, request.amount));
        _prepareRoute(
            request.actionId,
            IERC7943Fungible.setFrozenTokens.selector,
            keccak256(data),
            TrustTypes.RouteKind.ACTION,
            uint8(TrustTypes.ActionKind.FREEZE),
            request.authorityEpoch,
            request.policyEpoch
        );
        _consumeRoute(IERC7943Fungible.setFrozenTokens.selector, keccak256(data));
        TrustTypes.ActionRequest memory memoryRequest = request;
        receiptHash = _applyActionPrepared(memoryRequest, digest, evidence);
        if (forcePostApplyFailure) revert C6ForcedPostApplyFailure();
    }

    function _c6BoundedRollbackProbe(
        TrustTypes.ActionRequest calldata request,
        bytes32 digest,
        bytes32 evidence,
        bool forcePostApplyFailure
    ) private {
        if (request.action != TrustTypes.ActionKind.FREEZE) revert C6ForcedPostApplyFailure();
        _consumeActionAuthorization(request, digest);
        bytes memory data = abi.encodeCall(IERC7943Fungible.setFrozenTokens, (request.subject, request.amount));
        _prepareRoute(
            request.actionId,
            IERC7943Fungible.setFrozenTokens.selector,
            keccak256(data),
            TrustTypes.RouteKind.ACTION,
            uint8(TrustTypes.ActionKind.FREEZE),
            request.authorityEpoch,
            request.policyEpoch
        );
        _frozen[request.subject] = request.amount;
        _actions[request.actionId].evidenceHash = evidence;
        _actions[request.actionId].receiptHash = digest;
        _receipts[request.actionId].receiptHash = digest;
        emit Frozen(request.subject, request.amount);
        if (forcePostApplyFailure) revert C6ForcedPostApplyFailure();
    }
}
