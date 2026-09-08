// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustTokenKontrolTest} from "../TrustTokenKontrolTest.t.sol";
import {TrustToken} from "../../src/TrustToken.sol";
import {TrustKernelTypes} from "../../src/generated/IERCTrustKernel.sol";
import {MockBoundDependency} from "../../test/mocks/MockBoundDependency.sol";

interface DeferredSymbolicVm {
    function assume(bool condition) external;
    function randomUint() external returns (uint256);
    function expectRevert(bytes calldata revertData) external;
}

/// @notice Full positive nonincreasing uint256 domain introduced after concrete deployment.
/// @dev A proof input, not a completed proof or arbitrary-world correspondence result.
contract TrustTokenDeferredSymbolicKontrolTest is TrustTokenKontrolTest {
    // Kontrol uses this storage-field marker to retain TEST_CONFIG when summaries are included.
    bool public IS_TEST = true;

    function testKontrol_DeferredSymbolicNonincreasingFreeze() external {
        (TrustToken token,) = _deploy(MockBoundDependency.Mode.APPLICABLE);
        DeferredSymbolicVm symbolicVm = DeferredSymbolicVm(address(vm));
        uint256 first = symbolicVm.randomUint();
        uint256 second = symbolicVm.randomUint();
        symbolicVm.assume(first > 0 && second > 0 && second <= first);
        TrustKernelTypes.ActionRequest memory initial = _request(token, TrustKernelTypes.ActionKind.FREEZE, 20, first);
        token.executeRegulatoryAction(initial);
        uint256 expected = first > SUPPLY ? SUPPLY : first;
        require(token.getFrozenTokens(address(this)) == expected, "initial observed floor");
        TrustKernelTypes.ActionRequest memory next = _request(token, TrustKernelTypes.ActionKind.FREEZE, 21, second);
        next.caseId = initial.caseId;
        next.actionId = token.deriveActionId(next);
        symbolicVm.expectRevert(
            abi.encodeWithSignature("TrustInvalidCommand(bytes32,uint16)", next.actionId, uint16(12))
        );
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
