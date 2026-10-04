// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustKernelTypes} from "../../../../implementation/src/generated/IERCTrustKernel.sol";
import {IERC7943Fungible} from "../../../../implementation/src/interfaces/IERC7943.sol";
import {TrustZeroAddress} from "../../../../implementation/src/TrustErrors.sol";
import {TrustTestBase, Vm} from "../../../../implementation/test/TrustTestBase.t.sol";

interface AllowanceRouteVm {
    function record() external;
    function accesses(address target) external returns (bytes32[] memory readSlots, bytes32[] memory writeSlots);
}

/// @notice Executes the allowance routes of the Native endpoint on the shared Native test fixture: approve writes
///         only the allowance of the caller, also when the caller is restricted, and transferFrom spends the
///         allowance and runs the ordinary transfer with its restriction and frozen-floor checks.
/// @dev The tests are run in an isolated copy by scripts/trust12/tail-preparation/run_route_disposition_tests.py.
contract NativeAllowanceRoutesTest is TrustTestBase {
    AllowanceRouteVm internal constant ROUTE_VM =
        AllowanceRouteVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    /// @dev Storage slot of `_allowances` in the storage layout of the runtime binding (`native.allowances` of the
    ///      formal runtime bridge).
    uint256 internal constant ALLOWANCES_SLOT = 4;
    bytes32 internal constant APPROVAL_TOPIC = keccak256("Approval(address,address,uint256)");

    function testApproveWritesOnlyTheAllowance() external {
        token.executeRegulatoryAction(_request(TrustKernelTypes.ActionKind.RESTRICT, 9_101, 0));
        uint256 balance = token.balanceOf(address(this));
        uint256 frozen = token.getFrozenTokens(address(this));
        uint256 supply = token.totalSupply();
        vm.recordLogs();
        ROUTE_VM.record();
        require(token.approve(address(buyer), 7 ether), "approve by a restricted owner");
        (, bytes32[] memory writes) = ROUTE_VM.accesses(address(token));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 slot = keccak256(abi.encode(address(buyer), keccak256(abi.encode(address(this), ALLOWANCES_SLOT))));
        _assert(writes.length > 0, "the allowance is written");
        for (uint256 i = 0; i < writes.length; ++i) {
            _assertEq(writes[i], slot, "approve writes only the allowance slot");
        }
        _assert(
            logs.length == 1 && logs[0].emitter == address(token) && logs[0].topics[0] == APPROVAL_TOPIC,
            "approve emits one Approval event"
        );
        _assertEq(token.allowance(address(this), address(buyer)), 7 ether, "allowance set");
        _assertEq(token.balanceOf(address(this)), balance, "balance unchanged");
        _assertEq(token.getFrozenTokens(address(this)), frozen, "frozen amount unchanged");
        _assertEq(token.totalSupply(), supply, "supply unchanged");
        _assert(!token.canSend(address(this)), "restriction unchanged");
        (bool ok, bytes memory reason) = address(token).call(abi.encodeCall(token.approve, (address(0), 1)));
        _assert(!ok && _selector(reason) == TrustZeroAddress.selector, "zero spender rejected");
    }

    function testTransferFromSpendsAllowanceAndRespectsRestriction() external {
        require(token.approve(address(buyer), 10 ether), "approve");
        vm.prank(address(buyer));
        require(token.transferFrom(address(this), address(recovered), 4 ether), "transferFrom");
        _assertEq(token.allowance(address(this), address(buyer)), 6 ether, "allowance spent");
        _assertEq(token.balanceOf(address(recovered)), 4 ether, "exact amount moved");

        TrustKernelTypes.ActionRequest memory restrict = _request(TrustKernelTypes.ActionKind.RESTRICT, 9_001, 0);
        token.executeRegulatoryAction(restrict);
        vm.prank(address(buyer));
        (bool ok, bytes memory reason) =
            address(token).call(abi.encodeCall(token.transferFrom, (address(this), address(recovered), 1 ether)));
        _assert(
            !ok && _selector(reason) == IERC7943Fungible.ERC7943CannotSend.selector, "restricted source must not send"
        );
        _assertEq(token.allowance(address(this), address(buyer)), 6 ether, "allowance kept on failure");
        _assertEq(token.balanceOf(address(recovered)), 4 ether, "failure moves nothing");
    }

    function testTransferFromKeepsTheMaximumAllowanceAndTheFrozenFloor() external {
        require(token.approve(address(buyer), type(uint256).max), "approve");
        token.executeRegulatoryAction(_request(TrustKernelTypes.ActionKind.FREEZE, 9_201, INITIAL_SUPPLY - 5 ether));
        vm.prank(address(buyer));
        require(token.transferFrom(address(this), address(recovered), 5 ether), "transferFrom of the unfrozen amount");
        _assertEq(token.allowance(address(this), address(buyer)), type(uint256).max, "maximum allowance kept");
        _assertEq(token.balanceOf(address(recovered)), 5 ether, "exact amount moved");
        vm.prank(address(buyer));
        (bool ok, bytes memory reason) =
            address(token).call(abi.encodeCall(token.transferFrom, (address(this), address(recovered), 1)));
        _assert(
            !ok && _selector(reason) == IERC7943Fungible.ERC7943InsufficientUnfrozenBalance.selector,
            "the frozen floor holds"
        );
        _assertEq(token.balanceOf(address(recovered)), 5 ether, "failure moves nothing");
    }
}
