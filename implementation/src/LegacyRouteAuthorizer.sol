// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustTypes} from "./TrustTypes.sol";
import {TrustDecision} from "./TrustDecision.sol";

library LegacyRouteAuthorizer {
    function authorized(
        TrustTypes.Authority storage authority,
        TrustTypes.Delegation storage delegation,
        address caller,
        TrustTypes.ActionKind action,
        bytes32 scopeHash,
        uint48 nowTime
    ) internal view returns (bool) {
        if (!authority.active) return false;
        if (caller == authority.account) return true;
        return delegation.authorityEpoch == authority.epoch && delegation.validUntil >= nowTime
            && delegation.scopeHash == scopeHash && (delegation.actionMask & TrustDecision.actionMask(action)) != 0;
    }
}
