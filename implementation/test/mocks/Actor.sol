// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustToken} from "../../src/TrustToken.sol";
import {TrustTypes} from "../../src/TrustTypes.sol";

contract Actor {
    function transferToken(TrustToken token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }

    function executeAction(TrustToken token, TrustTypes.ActionRequest calldata request) external returns (bytes32) {
        return token.executeRegulatoryAction(request);
    }

    function rawFreeze(TrustToken token, address account, uint256 amount) external returns (bool) {
        return token.setFrozenTokens(account, amount);
    }

    function rawForcedTransfer(TrustToken token, address from, address to, uint256 amount) external returns (bool) {
        return token.forcedTransfer(from, to, amount);
    }
}
