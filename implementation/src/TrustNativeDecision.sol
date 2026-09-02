// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustKernelTypes} from "./generated/IERCTrustKernel.sol";

/// @notice Pure kernel-version-2 helpers of the native profile.
library TrustNativeDecision {
    /// @dev hashes.nonceKey.
    function nonceKey(bytes32 authorityRef, uint64 authorityEpoch, uint256 nonce) internal pure returns (bytes32) {
        return keccak256(abi.encode(TrustKernelTypes.DOMAIN, authorityRef, authorityEpoch, nonce));
    }

    /// @dev hashes.dependencyRoot: ordered by BindingKind and tagged.
    function dependencyRoot(bytes32 policy, bytes32 identity, bytes32 settlement, bytes32 entitlement)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                TrustKernelTypes.DOMAIN, TrustKernelTypes.DEPENDENCY_ROOT_TAG, policy, identity, settlement, entitlement
            )
        );
    }

    /// @dev shapeRules.reversal.pairing.
    function reversalMatches(TrustKernelTypes.ActionKind action, TrustKernelTypes.ReversalKind reversal)
        internal
        pure
        returns (bool)
    {
        return (action == TrustKernelTypes.ActionKind.FREEZE && reversal == TrustKernelTypes.ReversalKind.UNFREEZE)
            || (action == TrustKernelTypes.ActionKind.SEIZE && reversal == TrustKernelTypes.ReversalKind.RELEASE)
            || (action == TrustKernelTypes.ActionKind.RESTRICT && reversal == TrustKernelTypes.ReversalKind.UNRESTRICT);
    }

    function isForcedTransferAction(TrustKernelTypes.ActionKind action) internal pure returns (bool) {
        return action != TrustKernelTypes.ActionKind.FREEZE && action != TrustKernelTypes.ActionKind.RESTRICT;
    }
}
