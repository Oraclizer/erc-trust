// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustToken} from "../src/TrustToken.sol";
import {TrustKernelTypes} from "../src/generated/IERCTrustKernel.sol";
import {MockBoundDependency} from "../test/mocks/MockBoundDependency.sol";

interface KontrolVm {
    function expectRevert() external;
    function load(address target, bytes32 slot) external view returns (bytes32);
}

/// @notice Independent KEVM cross-check inputs for the highest-risk native paths of kernel version 2.
/// @dev These are the proof inputs of the Kontrol lane. No result is bound to the successor runtime
///      until that lane records a receipt; see evidence/current-profile-release-index-v3.json.
contract TrustTokenKontrolTest {
    KontrolVm internal constant vm = KontrolVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    bytes32 internal constant DOMAIN = TrustKernelTypes.DOMAIN;
    bytes32 internal constant AUTHORITY_REF = keccak256("KONTROL-AUTHORITY");
    bytes32 internal constant SCHEMA = keccak256("KONTROL-SCHEMA");
    uint256 internal constant SUPPLY = 1_000_000 ether;
    uint256 internal constant ROUTE_TICKET_PACKED_SLOT = 27;
    address internal constant DESTINATION = address(0xbeef);

    function testKontrol_RawSensitiveSelectorsStayClosed() external {
        (TrustToken token,) = _deploy(MockBoundDependency.Mode.APPLICABLE);

        vm.expectRevert();
        token.setFrozenTokens(address(this), 1 ether);
        require(!_routeLive(token), "raw freeze left ticket");

        vm.expectRevert();
        token.forcedTransfer(address(this), DESTINATION, 1 ether);
        require(!_routeLive(token), "raw transfer left ticket");
        require(token.balanceOf(address(this)) == SUPPLY, "raw route moved balance");
    }

    function testKontrol_OperationalFailureStuttersProjection() external {
        (TrustToken token, MockBoundDependency dependency) = _deploy(MockBoundDependency.Mode.REVERTING);
        TrustKernelTypes.ActionRequest memory request = _request(token, TrustKernelTypes.ActionKind.FREEZE, 1, 7 ether);
        (bytes32 rootBefore, uint64 epochBefore) = token.dependencyState();
        uint256 balanceBefore = token.balanceOf(address(this));
        uint256 frozenBefore = token.getFrozenTokens(address(this));
        bytes32 configBefore = dependency.configurationDigest();

        vm.expectRevert();
        token.executeRegulatoryAction(request);

        (bytes32 rootAfter, uint64 epochAfter) = token.dependencyState();
        require(token.balanceOf(address(this)) == balanceBefore, "balance changed");
        require(token.getFrozenTokens(address(this)) == frozenBefore, "frozen changed");
        require(rootAfter == rootBefore && epochAfter == epochBefore, "dependency state changed");
        require(dependency.configurationDigest() == configBefore, "dependency changed");
        require(token.actionRecord(request.actionId).lifecycle == TrustKernelTypes.Lifecycle.NONE, "record changed");
        require(token.receipt(request.actionId).receiptHash == bytes32(0), "receipt changed");
        require(!_routeLive(token), "route persisted");
    }

    function testKontrol_NonincreasingFreezeStuttersProjection() external {
        (TrustToken token,) = _deploy(MockBoundDependency.Mode.APPLICABLE);
        TrustKernelTypes.ActionRequest memory initial = _request(token, TrustKernelTypes.ActionKind.FREEZE, 20, 10 ether);
        token.executeRegulatoryAction(initial);
        uint256 balanceBefore = token.balanceOf(address(this));

        TrustKernelTypes.ActionRequest memory equal = _request(token, TrustKernelTypes.ActionKind.FREEZE, 21, 10 ether);
        equal.caseId = initial.caseId;
        equal.actionId = token.deriveActionId(equal);
        vm.expectRevert();
        token.executeRegulatoryAction(equal);
        require(token.getFrozenTokens(address(this)) == 10 ether, "equal changed frozen target");
        require(token.balanceOf(address(this)) == balanceBefore, "equal changed balance");
        require(token.actionRecord(equal.actionId).lifecycle == TrustKernelTypes.Lifecycle.NONE, "equal record changed");
        require(token.receipt(equal.actionId).receiptHash == bytes32(0), "equal receipt changed");
        require(token.caseRecord(initial.caseId).headActionId == initial.actionId, "equal moved the head");
        require(!_routeLive(token), "equal route persisted");

        TrustKernelTypes.ActionRequest memory decrease = _request(token, TrustKernelTypes.ActionKind.FREEZE, 22, 5 ether);
        decrease.caseId = initial.caseId;
        decrease.actionId = token.deriveActionId(decrease);
        vm.expectRevert();
        token.executeRegulatoryAction(decrease);
        require(token.getFrozenTokens(address(this)) == 10 ether, "decrease changed frozen target");
        require(token.balanceOf(address(this)) == balanceBefore, "decrease changed balance");
        require(token.actionRecord(decrease.actionId).lifecycle == TrustKernelTypes.Lifecycle.NONE, "decrease record changed");
        require(token.receipt(decrease.actionId).receiptHash == bytes32(0), "decrease receipt changed");
        require(!_routeLive(token), "decrease route persisted");
    }

    function testKontrol_LiquidateExactDeltaReceiptAndFinalLog() external {
        (TrustToken token,) = _deploy(MockBoundDependency.Mode.APPLICABLE);
        TrustKernelTypes.ActionRequest memory request = _request(token, TrustKernelTypes.ActionKind.LIQUIDATE, 2, 9 ether);
        uint256 supplyBefore = token.totalSupply();
        uint256 sourceBefore = token.balanceOf(address(this));
        uint256 destinationBefore = token.balanceOf(DESTINATION);

        bytes32 returned = token.executeRegulatoryAction(request);
        TrustKernelTypes.ActionRecord memory record = token.actionRecord(request.actionId);
        TrustKernelTypes.Receipt memory actionReceipt = token.receipt(request.actionId);

        require(token.totalSupply() == supplyBefore, "supply");
        require(token.balanceOf(address(this)) + request.amount == sourceBefore, "source");
        require(token.balanceOf(DESTINATION) == destinationBefore + request.amount, "destination");
        require(record.lifecycle == TrustKernelTypes.Lifecycle.APPLIED, "lifecycle");
        require(record.receiptHash == returned && actionReceipt.receiptHash == returned, "receipt");
        require(actionReceipt.receiptKind == TrustKernelTypes.ReceiptKind.ACTION, "receipt kind");
        require(token.caseRecord(request.caseId).phase == TrustKernelTypes.CasePhase.TERMINAL, "disposition terminal");
        require(!_routeLive(token), "route");
        _assertFinalReceiptLogK(address(token), request, returned);
    }

    function _deploy(MockBoundDependency.Mode mode)
        internal
        returns (TrustToken token, MockBoundDependency dependency)
    {
        dependency = new MockBoundDependency(mode, keccak256("KONTROL-CONFIG"));
        token = new TrustToken(
            "ERC-TRUST",
            "TRUST",
            18,
            address(this),
            address(this),
            SUPPLY,
            AUTHORITY_REF,
            address(this),
            address(dependency),
            address(dependency),
            address(dependency),
            address(dependency),
            SCHEMA
        );
    }

    function _request(TrustToken token, TrustKernelTypes.ActionKind action, uint256 nonce, uint256 amount)
        internal
        view
        returns (TrustKernelTypes.ActionRequest memory request)
    {
        (bytes32 root, uint64 epoch) = token.dependencyState();
        request = TrustKernelTypes.ActionRequest({
            domain: DOMAIN,
            actionId: bytes32(0),
            action: action,
            subject: address(this),
            source: address(this),
            destination: action == TrustKernelTypes.ActionKind.LIQUIDATE ? DESTINATION : address(0),
            custodian: address(0),
            amount: amount,
            caseId: keccak256(abi.encode("KONTROL-CASE", nonce)),
            dependencyRoot: root,
            dependencyEpoch: epoch,
            provenanceCommitment: keccak256(abi.encode("KONTROL-PROVENANCE", nonce)),
            settlementCommitment: action == TrustKernelTypes.ActionKind.LIQUIDATE
                ? keccak256(abi.encode("KONTROL-SETTLEMENT", nonce))
                : bytes32(0),
            proceedsCommitment: action == TrustKernelTypes.ActionKind.LIQUIDATE
                ? keccak256(abi.encode("KONTROL-PROCEEDS", nonce))
                : bytes32(0),
            entitlementCommitment: bytes32(0),
            authorityRef: AUTHORITY_REF,
            authorityEpoch: 1,
            nonce: nonce,
            validAfter: 0,
            validBefore: type(uint48).max
        });
        request.actionId = token.deriveActionId(request);
    }

    function _routeLive(TrustToken token) internal view returns (bool) {
        return vm.load(address(token), bytes32(ROUTE_TICKET_PACKED_SLOT)) != bytes32(0);
    }

    /// @dev Implemented by erc-trust-log-assertions.k over KEVM's final log cell.
    function _assertFinalReceiptLogK(address emitter, TrustKernelTypes.ActionRequest memory request, bytes32 receiptHash)
        internal
    {
        bytes memory assertionCall = abi.encodeWithSelector(
            bytes4(keccak256("assertFinalReceiptLog(address,bytes32,bytes32,bytes32,bytes32,bytes32)")),
            emitter,
            keccak256("RegulatoryActionApplied(bytes32,uint8,bytes32,bytes32)"),
            request.actionId,
            bytes32(uint256(uint8(request.action))),
            request.caseId,
            receiptHash
        );
        (bool ignored,) = address(vm).call(assertionCall);
        ignored;
    }
}
