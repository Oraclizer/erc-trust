// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustTestBase} from "./TrustTestBase.t.sol";
import {IERCTrustKernel, TrustKernelTypes} from "../src/generated/IERCTrustKernel.sol";

contract TrustActionsFuzzTest is TrustTestBase {
    function testFuzzFreezeAbsoluteAndOrdinaryFloor(uint96 rawFrozen, uint96 rawTransfer) external {
        uint256 frozen = uint256(rawFrozen) + 1;
        uint256 amount = uint256(rawTransfer);
        TrustKernelTypes.ActionRequest memory request = _request(TrustKernelTypes.ActionKind.FREEZE, 100, frozen);
        token.executeRegulatoryAction(request);

        uint256 balance = token.balanceOf(address(this));
        uint256 observedFrozen = frozen > balance ? balance : frozen;
        _assertEq(token.getFrozenTokens(address(this)), observedFrozen, "absolute freeze saturates at balance");
        uint256 unfrozen = frozen >= balance ? 0 : balance - frozen;
        (bool ok,) = address(token).call(abi.encodeCall(token.transfer, (address(buyer), amount)));
        _assert(ok == (amount <= unfrozen), "ordinary frozen floor");
    }

    function testFuzzForcedActionsPreserveSupply(uint8 rawAction, uint96 rawAmount) external {
        uint8 selector = uint8(rawAction % 4) + uint8(TrustKernelTypes.ActionKind.SEIZE);
        if (selector > uint8(TrustKernelTypes.ActionKind.RECOVER)) {
            selector = uint8(TrustKernelTypes.ActionKind.RECOVER);
        }
        TrustKernelTypes.ActionKind action = TrustKernelTypes.ActionKind(selector);
        if (action == TrustKernelTypes.ActionKind.RESTRICT) action = TrustKernelTypes.ActionKind.RECOVER;
        uint256 amount = (uint256(rawAmount) % (INITIAL_SUPPLY / 4)) + 1;
        TrustKernelTypes.ActionRequest memory request = _request(action, 101, amount);
        uint256 beforeSupply = token.totalSupply();
        token.executeRegulatoryAction(request);
        _assertEq(token.totalSupply(), beforeSupply, "supply frame");

        TrustKernelTypes.ActionRequest memory sameNonce = _request(TrustKernelTypes.ActionKind.FREEZE, 101, 1 ether);
        sameNonce.caseId = keccak256("OTHER-CASE");
        sameNonce.actionId = token.deriveActionId(sameNonce);
        (bool replayOk, bytes memory result) = _call(abi.encodeCall(token.executeRegulatoryAction, (sameNonce)));
        _assert(!replayOk && _selector(result) == IERCTrustKernel.TrustReplay.selector, "nonce consumed");
    }
}
