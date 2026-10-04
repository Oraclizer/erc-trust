// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustKernelTypes} from "../../../../implementation/src/generated/IERCTrustKernel.sol";
import {HookMalformedProbe} from "../foundry/HookMalformedProbe.t.sol";
import {WordGuardProbeCore} from "./WordGuardProbeCore.sol";

/// @notice Bounded word guard witnesses of the Hook profile endpoint on the factory deployment of the Hook malformed
///         probe against the pinned upstream token.
contract HookWordGuardProbe is HookMalformedProbe, WordGuardProbeCore {
    /// @dev An eligible identity of the probe deployment, as in the upstream integration test.
    address internal constant BUYER = address(0xb0b);

    function testWordGuardProbe() external {
        _runWordGuardProbe(false);
    }

    /// @dev A disposition of the probe's own upstream balance to the eligible buyer in a fresh case.
    function _probeKindAction(uint256 nonce)
        internal
        view
        override
        returns (TrustKernelTypes.ActionRequest memory request)
    {
        (bytes32 root, uint64 epoch) = adapter.dependencyState();
        request = TrustKernelTypes.ActionRequest({
            domain: TrustKernelTypes.DOMAIN,
            actionId: bytes32(0),
            action: TrustKernelTypes.ActionKind.CONFISCATE,
            subject: address(this),
            source: address(this),
            destination: BUYER,
            custodian: address(0),
            amount: PROBE_AMOUNT,
            caseId: keccak256(abi.encode("PROFILE-CASE", nonce)),
            dependencyRoot: root,
            dependencyEpoch: epoch,
            provenanceCommitment: keccak256(abi.encode("ORDER", nonce)),
            settlementCommitment: bytes32(0),
            proceedsCommitment: bytes32(0),
            entitlementCommitment: bytes32(0),
            authorityRef: AUTHORITY_REF,
            authorityEpoch: 1,
            nonce: nonce,
            validAfter: 0,
            validBefore: type(uint48).max
        });
        request.actionId = adapter.deriveActionId(request);
    }
}
