// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustToken} from "../../src/TrustToken.sol";
import {TrustTypes} from "../../src/TrustTypes.sol";

/// @notice Verification-only C1 seam over the production authorization functions.
/// @dev The harness adds no assumption about policy approval or external truth.
contract TrustTokenC1AuthorizationHarness is TrustToken {
    error C1ForcedOperationalFailure();

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

    function c1ValidateOnly(TrustTypes.ActionRequest calldata request) external view returns (bytes32 digest) {
        return _validateAndAuthorizeAction(request, msg.sender);
    }

    function c1ValidateAndConsumeEpochWitness(TrustTypes.ActionRequest calldata request)
        external
        returns (bytes32 digest, uint64 authorityEpochBefore, uint64 policyEpochBefore)
    {
        return _c1ValidateAndConsume(request, msg.sender);
    }

    function c1ValidateAndConsume(TrustTypes.ActionRequest calldata request) external returns (bytes32 digest) {
        (digest,,) = _c1ValidateAndConsume(request, msg.sender);
    }

    function c1ValidateAndConsumeReplayWitness(TrustTypes.ActionRequest calldata request)
        external
        returns (uint8 witness)
    {
        if (_usedCommandIds[request.actionId]) witness |= 1;
        if (_usedNonces[request.authorityRef][request.authorityEpoch][request.nonce]) witness |= 2;
        _c1ValidateAndConsume(request, msg.sender);
        if (_usedCommandIds[request.actionId]) witness |= 4;
        if (_usedNonces[request.authorityRef][request.authorityEpoch][request.nonce]) witness |= 8;
    }

    function c1RecordBindingWitness(bytes32 actionId) external view returns (bytes32) {
        TrustTypes.ActionRecord storage record = _actions[actionId];
        return keccak256(
            abi.encode(actionId, record.authorityRef, record.authorityEpoch, record.policyEpoch, record.commandHash)
        );
    }

    function c1ExpectedRecordBindingWitness(TrustTypes.ActionRequest calldata request, bytes32 digest)
        external
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(request.actionId, request.authorityRef, request.authorityEpoch, request.policyEpoch, digest)
        );
    }

    function _c1ValidateAndConsume(TrustTypes.ActionRequest calldata request, address caller)
        private
        returns (bytes32 digest, uint64 authorityEpochBefore, uint64 policyEpochBefore)
    {
        digest = _validateAndAuthorizeAction(request, caller);
        authorityEpochBefore = _authorities[request.authorityRef].epoch;
        policyEpochBefore = _bindings[TrustTypes.BindingKind.POLICY].epoch;
        // MUTATION: authorization consumption omitted.
    }

    function c1ValidateThenOperationalFailure(TrustTypes.ActionRequest calldata request) external view {
        _validateAndAuthorizeAction(request, msg.sender);
        revert C1ForcedOperationalFailure();
    }

    function c1CommandUsed(bytes32 commandId) external view returns (bool) {
        return _usedCommandIds[commandId];
    }

    function c1AuthorityEpoch(bytes32 authorityRef) external view returns (uint64) {
        return _authorities[authorityRef].epoch;
    }

    function c1PolicyEpoch() external view returns (uint64) {
        return _bindings[TrustTypes.BindingKind.POLICY].epoch;
    }

    function c1RecordCommandHash(bytes32 actionId) external view returns (bytes32) {
        return _actions[actionId].commandHash;
    }

    function c1RecordAuthorityRef(bytes32 actionId) external view returns (bytes32) {
        return _actions[actionId].authorityRef;
    }

    function c1RecordAuthorityEpoch(bytes32 actionId) external view returns (uint64) {
        return _actions[actionId].authorityEpoch;
    }

    function c1RecordPolicyEpoch(bytes32 actionId) external view returns (uint64) {
        return _actions[actionId].policyEpoch;
    }
}
