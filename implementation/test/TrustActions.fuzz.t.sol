// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustTestBase} from "./TrustTestBase.t.sol";
import {TrustTypes} from "../src/TrustTypes.sol";

contract TrustActionsFuzzTest is TrustTestBase {
    function testFuzzFreezeAbsoluteAndOrdinaryFloor(uint96 rawFrozen, uint96 rawTransfer) external {
        uint256 frozen = uint256(rawFrozen) + 1;
        uint256 amount = uint256(rawTransfer);
        TrustTypes.ActionRequest memory request = _request(TrustTypes.ActionKind.FREEZE, 100, frozen);
        token.executeRegulatoryAction(request);
        _assertEq(token.getFrozenTokens(address(this)), frozen, "absolute freeze");

        uint256 balance = token.balanceOf(address(this));
        uint256 unfrozen = frozen >= balance ? 0 : balance - frozen;
        (bool ok,) = address(token).call(abi.encodeCall(token.transfer, (address(buyer), amount)));
        _assert(ok == (amount <= unfrozen), "ordinary frozen floor");
    }

    function testFuzzForcedActionsPreserveSupply(uint8 rawAction, uint96 rawAmount) external {
        uint8 selector = uint8(rawAction % 4) + uint8(TrustTypes.ActionKind.SEIZE);
        if (selector > uint8(TrustTypes.ActionKind.RECOVER)) selector = uint8(TrustTypes.ActionKind.RECOVER);
        TrustTypes.ActionKind action = TrustTypes.ActionKind(selector);
        if (action == TrustTypes.ActionKind.RESTRICT) action = TrustTypes.ActionKind.RECOVER;
        uint256 amount = (uint256(rawAmount) % (INITIAL_SUPPLY / 4)) + 1;
        TrustTypes.ActionRequest memory request = _request(action, 101, amount);
        uint256 beforeSupply = token.totalSupply();
        token.executeRegulatoryAction(request);
        _assertEq(token.totalSupply(), beforeSupply, "supply frame");
        _assert(token.nonceUsed(AUTHORITY_REF, 1, 101), "nonce consumed");
    }
}
