// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustTokenKontrolTest} from "../TrustTokenKontrolTest.t.sol";
import {TrustToken} from "../../src/TrustToken.sol";
import {TrustKernelTypes} from "../../src/generated/IERCTrustKernel.sol";
import {MockBoundDependency} from "../../test/mocks/MockBoundDependency.sol";

interface SymbolicAssumptionsVm {
    function assume(bool condition) external;
}

/// @notice Two arbitrary positive targets with second <= first, including targets above supply.
/// @dev Constructor state and dependency mode remain fixed. This is not arbitrary-storage refinement.
contract TrustTokenSymbolicKontrolTest is TrustTokenKontrolTest {
    function testKontrol_SymbolicNonincreasingFreeze(uint256 first, uint256 second) external {
        SymbolicAssumptionsVm(address(vm)).assume(first > 0 && second > 0 && second <= first);
        (TrustToken token,) = _deploy(MockBoundDependency.Mode.APPLICABLE);
        TrustKernelTypes.ActionRequest memory initial = _request(token, TrustKernelTypes.ActionKind.FREEZE, 20, first);
        token.executeRegulatoryAction(initial);
        uint256 expected = first > SUPPLY ? SUPPLY : first;
        require(token.getFrozenTokens(address(this)) == expected, "initial observed floor");
        TrustKernelTypes.ActionRequest memory next = _request(token, TrustKernelTypes.ActionKind.FREEZE, 21, second);
        next.caseId = initial.caseId;
        next.actionId = token.deriveActionId(next);
        vm.expectRevert();
        token.executeRegulatoryAction(next);
        require(token.getFrozenTokens(address(this)) == expected, "rejection changed frozen floor");
        require(token.balanceOf(address(this)) == SUPPLY, "rejection changed balance");
        require(token.totalSupply() == SUPPLY, "rejection changed supply");
        require(
            token.actionRecord(next.actionId).lifecycle == TrustKernelTypes.Lifecycle.NONE, "rejection wrote action"
        );
        require(token.receipt(next.actionId).receiptHash == bytes32(0), "rejection wrote receipt");
        require(token.caseRecord(initial.caseId).headActionId == initial.actionId, "rejection moved head");
        require(!_routeLive(token), "rejection left route");
    }
}
