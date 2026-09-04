// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {ERC3643ProfileTestBase} from "./ERC3643Profile.unit.t.sol";
import {TrustKernelTypes} from "../src/generated/IERCTrustKernel.sol";
import {MockERC3643TokenTrex} from "./mocks/MockERC3643TokenTrex.sol";

/// @notice The whole profile suite against the independent second fixture, which unfreezes on forced
///         transfers and keeps the complete ERC-3643 owner and Agent surface, plus the behaviour only that
///         surface can show: automatic unfreezing, ordinary-transfer floors, and the all-mutator inventory.
contract ERC3643ProfileTrexFixtureTest is ERC3643ProfileTestBase {
    function _newToken(uint256 supply) internal override returns (address) {
        return address(new MockERC3643TokenTrex(address(identity), address(compliance), supply));
    }

    function _seedLegacy(address account, uint256 balance, uint256 frozenAmount, bool restricted) internal override {
        MockERC3643TokenTrex fixture = MockERC3643TokenTrex(token);
        fixture.forcedTransfer(address(this), account, balance);
        if (frozenAmount != 0) fixture.freezePartialTokens(account, frozenAmount);
        if (restricted) fixture.setAddressFrozen(account, true);
    }

    function testForcedTransferAutoUnfreezeIsResynchronised() external {
        MockERC3643TokenTrex fixture = MockERC3643TokenTrex(token);
        _assert(fixture.transfer(holder, 100 ether), "seed holder");
        TrustKernelTypes.ActionRequest memory freeze = _request(TrustKernelTypes.ActionKind.FREEZE, 200, 100 ether);
        freeze.subject = holder;
        freeze.source = holder;
        freeze.actionId = adapter.deriveActionId(freeze);
        adapter.executeRegulatoryAction(freeze);
        _assertEq(_frozen(holder), 100 ether, "whole balance frozen");

        TrustKernelTypes.ActionRequest memory seize = _request(TrustKernelTypes.ActionKind.SEIZE, 201, 30 ether);
        seize.subject = holder;
        seize.source = holder;
        seize.actionId = adapter.deriveActionId(seize);
        adapter.executeRegulatoryAction(seize);
        _assertEq(_balance(holder), 70 ether, "seized");
        _assertEq(_frozen(holder), 70 ether, "upstream unfroze automatically and the target saturates at the balance");
        _assertEq(_balance(address(adapter)), 30 ether, "custody");

        TrustKernelTypes.ActionRequest memory clean = _request(TrustKernelTypes.ActionKind.FREEZE, 202, 1 ether);
        adapter.executeRegulatoryAction(clean);
        _assertEq(_frozen(address(this)), 1 ether, "the automatic unfreeze is owned state, not drift");

        adapter.executeRegulatoryReversal(_reversal(seize.actionId, TrustKernelTypes.ReversalKind.RELEASE, 203));
        _assertEq(_balance(holder), 100 ether, "released");
        _assertEq(_frozen(holder), 100 ether, "inbound resynchronisation restores the target");
        adapter.executeRegulatoryReversal(_reversal(freeze.actionId, TrustKernelTypes.ReversalKind.UNFREEZE, 204));
        _assertEq(_frozen(holder), 0, "unfrozen");
    }

    /// @dev Balance growth between two adapter touches stays transferable until a touch or a
    ///      resynchronisation; the resynchronisation is permissionless and only ever freezes more.
    function testInboundGrowthIsRefrozenByPermissionlessResynchronisation() external {
        MockERC3643TokenTrex fixture = MockERC3643TokenTrex(token);
        _assert(fixture.transfer(holder, 100 ether), "seed holder");
        TrustKernelTypes.ActionRequest memory freeze = _request(TrustKernelTypes.ActionKind.FREEZE, 220, 100 ether);
        freeze.subject = holder;
        freeze.source = holder;
        freeze.actionId = adapter.deriveActionId(freeze);
        adapter.executeRegulatoryAction(freeze);
        TrustKernelTypes.ActionRequest memory seize = _request(TrustKernelTypes.ActionKind.SEIZE, 221, 30 ether);
        seize.subject = holder;
        seize.source = holder;
        seize.actionId = adapter.deriveActionId(seize);
        adapter.executeRegulatoryAction(seize);
        _assertEq(_frozen(holder), 70 ether, "target saturated at the balance after the seizure");

        _assert(fixture.transfer(holder, 30 ether), "inbound growth from another holder");
        _assertEq(_balance(holder), 100 ether, "balance grew");
        _assertEq(_frozen(holder), 70 ether, "the growth is not frozen until the next touch");
        (uint256 target, uint256 applied, bool restricted) = adapter.ownedState(holder);
        _assert(target == 100 ether && applied == 70 ether && !restricted, "owned state shows the gap");
        _assert(!adapter.trustProfile().full, "inbound growth remains a partial-profile limitation");
        _assert(adapter.sealedTopologyLive(), "the narrower sealed topology remains live");

        vm.prank(holder);
        _assert(fixture.transfer(buyer, 30 ether), "the unfrozen inbound growth is transferable before a touch");
        _assertEq(_balance(holder), 70 ether, "the bounded inbound window is exercised");
        _assertEq(_frozen(holder), 70 ether, "the original saturated target remains applied");
        _assert(fixture.transfer(holder, 30 ether), "a second inbound growth recreates the gap");

        (bool ok, bytes memory result) =
            stranger.relay(address(adapter), abi.encodeCall(adapter.resynchroniseFrozen, (holder)));
        _assert(ok, "anyone may resynchronise");
        _assertEq(abi.decode(result, (uint256)), 100 ether, "returns the applied amount");
        _assertEq(_frozen(holder), 100 ether, "growth refrozen up to the owned target");
        (, applied,) = adapter.ownedState(holder);
        _assertEq(applied, 100 ether, "applied amount recorded");
        _assertEq(adapter.resynchroniseFrozen(holder), 100 ether, "idempotent once synchronised");
        _assertEq(adapter.resynchroniseFrozen(buyer), 0, "an account without owned state is a no-op");
        _assertEq(_frozen(holder), 100 ether, "resynchronisation never unfreezes");
        _assert(!adapter.trustProfile().full && adapter.sealedTopologyLive(), "resync never elevates conformance");

        adapter.executeRegulatoryReversal(_reversal(seize.actionId, TrustKernelTypes.ReversalKind.RELEASE, 222));
        _assertEq(_balance(holder), 130 ether, "released on top of the growth");
        _assertEq(_frozen(holder), 100 ether, "the release touch keeps the target");
        adapter.executeRegulatoryReversal(_reversal(freeze.actionId, TrustKernelTypes.ReversalKind.UNFREEZE, 223));
        _assertEq(_frozen(holder), 0, "unfrozen");
    }

    function testOrdinaryTransfersRespectAdapterOwnedState() external {
        MockERC3643TokenTrex fixture = MockERC3643TokenTrex(token);
        TrustKernelTypes.ActionRequest memory freeze =
            _request(TrustKernelTypes.ActionKind.FREEZE, 210, SUPPLY - 1 ether);
        adapter.executeRegulatoryAction(freeze);
        _assert(fixture.transfer(buyer, 1 ether), "the unfrozen remainder moves");
        (bool over,) = token.call(abi.encodeCall(fixture.transfer, (buyer, 1)));
        _assert(!over, "frozen tokens do not move");

        TrustKernelTypes.ActionRequest memory restrict = _request(TrustKernelTypes.ActionKind.RESTRICT, 211, 0);
        adapter.executeRegulatoryAction(restrict);
        adapter.executeRegulatoryReversal(_reversal(freeze.actionId, TrustKernelTypes.ReversalKind.UNFREEZE, 212));
        (bool frozenAddress,) = token.call(abi.encodeCall(fixture.transfer, (buyer, 1)));
        _assert(!frozenAddress, "a restricted address does not send");
        adapter.executeRegulatoryReversal(_reversal(restrict.actionId, TrustKernelTypes.ReversalKind.UNRESTRICT, 213));
        _assert(fixture.transfer(buyer, 1), "lifted restriction sends again");
    }

    function testEveryUpstreamMutatorIsClosedToNonAdapters() external {
        MockERC3643TokenTrex fixture = MockERC3643TokenTrex(token);
        address[] memory one = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        bool[] memory flags = new bool[](1);
        one[0] = address(this);
        amounts[0] = 1 ether;
        flags[0] = true;
        bytes[] memory mutators = new bytes[](19);
        mutators[0] = abi.encodeCall(fixture.forcedTransfer, (address(this), buyer, 1 ether));
        mutators[1] = abi.encodeCall(fixture.batchForcedTransfer, (one, one, amounts));
        mutators[2] = abi.encodeCall(fixture.mint, (buyer, 1 ether));
        mutators[3] = abi.encodeCall(fixture.burn, (address(this), 1 ether));
        mutators[4] = abi.encodeCall(fixture.recoveryAddress, (address(this), buyer, buyer));
        mutators[5] = abi.encodeCall(fixture.freezePartialTokens, (address(this), 1 ether));
        mutators[6] = abi.encodeCall(fixture.unfreezePartialTokens, (address(this), 1 ether));
        mutators[7] = abi.encodeCall(fixture.batchFreezePartialTokens, (one, amounts));
        mutators[8] = abi.encodeCall(fixture.batchUnfreezePartialTokens, (one, amounts));
        mutators[9] = abi.encodeCall(fixture.setAddressFrozen, (address(this), true));
        mutators[10] = abi.encodeCall(fixture.batchSetAddressFrozen, (one, flags));
        mutators[11] = abi.encodeCall(fixture.pause, ());
        mutators[12] = abi.encodeCall(fixture.unpause, ());
        mutators[13] = abi.encodeCall(fixture.addAgent, (address(this)));
        mutators[14] = abi.encodeCall(fixture.removeAgent, (address(adapter)));
        mutators[15] = abi.encodeCall(fixture.setExclusiveAgent, (address(this)));
        mutators[16] = abi.encodeCall(fixture.setIdentityRegistry, (address(this)));
        mutators[17] = abi.encodeCall(fixture.setCompliance, (address(this)));
        mutators[18] = abi.encodeCall(fixture.transferOwnership, (address(this)));
        for (uint256 i = 0; i < mutators.length; ++i) {
            (bool fromFormerOwner,) = token.call(mutators[i]);
            _assert(!fromFormerOwner, "former owner and historical agent is closed");
            (bool fromStranger,) = stranger.relay(token, mutators[i]);
            _assert(!fromStranger, "stranger is closed");
            (bool viaGovernor,) = address(governor).call(mutators[i]);
            _assert(!viaGovernor, "governor forwards nothing");
        }
        _assert(fixture.isAgent(address(adapter)) && !fixture.isAgent(address(this)), "the adapter is the only agent");
        _assertEq(fixture.owner(), address(governor), "the governor stays the owner");
        _assertEq(_balance(buyer), 0, "no mutator moved anything");
        _assert(
            !fixture.paused() && _frozen(address(this)) == 0 && !_restricted(address(this)), "no mutator changed state"
        );
        _assert(!adapter.trustProfile().full, "reference stays partial");
        _assert(adapter.sealedTopologyLive(), "sealed topology stays live");
    }
}
