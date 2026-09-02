// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustTestBase} from "./TrustTestBase.t.sol";
import {TrustToken} from "../src/TrustToken.sol";

contract TrustOrdinaryHandler {
    TrustToken public immutable token;
    address public immutable sink;

    constructor(TrustToken token_, address sink_) {
        token = token_;
        sink = sink_;
    }

    function transferBounded(uint96 rawAmount) external {
        uint256 balance = token.balanceOf(address(this));
        uint256 frozen = token.getFrozenTokens(address(this));
        uint256 unfrozen = frozen >= balance ? 0 : balance - frozen;
        uint256 amount = unfrozen == 0 ? 0 : uint256(rawAmount) % (unfrozen + 1);
        require(token.transfer(sink, amount), "transfer");
    }

    function approveBounded(uint96 rawAmount) external {
        token.approve(sink, uint256(rawAmount));
    }

    function rawSensitiveSelectors(uint96 rawAmount) external {
        (bool freezeOk,) =
            address(token).call(abi.encodeCall(token.setFrozenTokens, (address(this), uint256(rawAmount))));
        (bool transferOk,) =
            address(token).call(abi.encodeCall(token.forcedTransfer, (address(this), sink, uint256(rawAmount))));
        require(!freezeOk && !transferOk, "raw sensitive route unexpectedly open");
    }
}

contract TrustStatefulInvariantTest is TrustTestBase {
    TrustOrdinaryHandler internal handler;
    address[] internal targets;

    function setUp() public override {
        super.setUp();
        handler = new TrustOrdinaryHandler(token, address(buyer));
        require(token.transfer(address(handler), 10_000 ether), "seed");
        targets.push(address(handler));
    }

    function targetContracts() external view returns (address[] memory) {
        return targets;
    }

    function invariantSupplyConserved() external view {
        uint256 accounted =
            token.balanceOf(address(this)) + token.balanceOf(address(handler)) + token.balanceOf(address(buyer));
        _assertEq(accounted, token.totalSupply(), "supply conservation");
    }

    function invariantNoPersistentRouteTicket() external view {
        _assert(!_routeLive(), "ephemeral route");
    }

    function invariantInterfaceTruth() external view {
        _assert(token.supportsInterface(0x3edbb4c4), "erc7943 truth");
        _assert(token.supportsInterface(0x2b020308), "kernel truth");
        _assert(!token.supportsInterface(0xffffffff), "invalid interface");
    }
}
