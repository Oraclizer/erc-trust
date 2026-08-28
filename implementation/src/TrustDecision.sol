// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustTypes} from "./TrustTypes.sol";

library TrustDecision {
    function nonceKey(bytes32 authorityRef, uint64 authorityEpoch, uint256 nonce) internal pure returns (bytes32) {
        return keccak256(abi.encode(TrustTypes.DOMAIN, authorityRef, authorityEpoch, nonce));
    }

    function actionMask(TrustTypes.ActionKind action) internal pure returns (uint256) {
        return uint256(1) << uint8(action);
    }

    function reversalMatches(TrustTypes.ActionKind action, TrustTypes.ReversalKind reversal)
        internal
        pure
        returns (bool)
    {
        return (action == TrustTypes.ActionKind.FREEZE && reversal == TrustTypes.ReversalKind.UNFREEZE)
            || (action == TrustTypes.ActionKind.SEIZE && reversal == TrustTypes.ReversalKind.RELEASE)
            || (action == TrustTypes.ActionKind.RESTRICT && reversal == TrustTypes.ReversalKind.UNRESTRICT);
    }

    function isForcedTransferAction(TrustTypes.ActionKind action) internal pure returns (bool) {
        return action == TrustTypes.ActionKind.SEIZE || action == TrustTypes.ActionKind.CONFISCATE
            || action == TrustTypes.ActionKind.LIQUIDATE || action == TrustTypes.ActionKind.RECOVER;
    }
}
