// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustToken} from "../src/TrustToken.sol";
import {TrustTypes} from "../src/TrustTypes.sol";
import {MockBoundDependency} from "../test/mocks/MockBoundDependency.sol";

interface KontrolVm {
    function expectRevert() external;
}

/// @notice Independent KEVM cross-checks for the highest-risk native paths.
contract TrustTokenKontrolTest {
    KontrolVm internal constant vm = KontrolVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    bytes32 internal constant DOMAIN = keccak256("ERC-TRUST/reference-v1");
    bytes32 internal constant AUTHORITY_REF = keccak256("KONTROL-AUTHORITY");
    bytes32 internal constant SCHEMA = keccak256("KONTROL-SCHEMA");
    bytes32 internal constant SCOPE = keccak256("KONTROL-SCOPE");
    uint256 internal constant SUPPLY = 1_000_000 ether;
    address internal constant DESTINATION = address(0xbeef);

    function testKontrol_RawSensitiveSelectorsStayClosed() external {
        (TrustToken token,) = _deploy(MockBoundDependency.Mode.APPLICABLE);

        vm.expectRevert();
        token.setFrozenTokens(address(this), 1 ether);
        require(!token.routeLive(), "raw freeze left ticket");

        vm.expectRevert();
        token.forcedTransfer(address(this), DESTINATION, 1 ether);
        require(!token.routeLive(), "raw transfer left ticket");
        require(token.balanceOf(address(this)) == SUPPLY, "raw route moved balance");
    }

    function testKontrol_OperationalFailureStuttersProjection() external {
        (TrustToken token, MockBoundDependency dependency) = _deploy(MockBoundDependency.Mode.REVERTING);
        TrustTypes.ActionRequest memory request = _request(token, TrustTypes.ActionKind.FREEZE, 1, 7 ether);
        bytes32 bindingBefore = _binding(token);
        uint256 balanceBefore = token.balanceOf(address(this));
        uint256 frozenBefore = token.getFrozenTokens(address(this));
        bytes32 configBefore = dependency.configurationDigest();

        vm.expectRevert();
        token.executeRegulatoryAction(request);

        require(token.balanceOf(address(this)) == balanceBefore, "balance changed");
        require(token.getFrozenTokens(address(this)) == frozenBefore, "frozen changed");
        require(_binding(token) == bindingBefore, "binding changed");
        require(dependency.configurationDigest() == configBefore, "dependency changed");
        require(token.actionRecord(request.actionId).lifecycle == TrustTypes.Lifecycle.NONE, "record changed");
        require(!token.nonceUsed(AUTHORITY_REF, 1, request.nonce), "nonce consumed");
        require(!token.routeLive(), "route persisted");
    }

    function testKontrol_LiquidateExactDeltaReceiptAndFinalLog() external {
        (TrustToken token,) = _deploy(MockBoundDependency.Mode.APPLICABLE);
        TrustTypes.ActionRequest memory request = _request(token, TrustTypes.ActionKind.LIQUIDATE, 2, 9 ether);
        uint256 supplyBefore = token.totalSupply();
        uint256 sourceBefore = token.balanceOf(address(this));
        uint256 destinationBefore = token.balanceOf(DESTINATION);

        bytes32 returned = token.executeRegulatoryAction(request);
        TrustTypes.ActionRecord memory record = token.actionRecord(request.actionId);
        TrustTypes.Receipt memory actionReceipt = token.receipt(request.actionId);

        require(token.totalSupply() == supplyBefore, "supply");
        require(token.balanceOf(address(this)) + request.amount == sourceBefore, "source");
        require(token.balanceOf(DESTINATION) == destinationBefore + request.amount, "destination");
        require(record.lifecycle == TrustTypes.Lifecycle.APPLIED, "lifecycle");
        require(record.receiptHash == returned && actionReceipt.receiptHash == returned, "receipt");
        require(!token.routeLive(), "route");
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

    function _request(TrustToken token, TrustTypes.ActionKind action, uint256 nonce, uint256 amount)
        internal
        view
        returns (TrustTypes.ActionRequest memory request)
    {
        (, bytes32 binding, uint64 epoch) = token.getBindingState(TrustTypes.BindingKind.POLICY);
        request = TrustTypes.ActionRequest({
            domain: DOMAIN,
            actionId: bytes32(0),
            action: action,
            subject: address(this),
            source: address(this),
            destination: action == TrustTypes.ActionKind.LIQUIDATE ? DESTINATION : address(0),
            custodian: address(0),
            amount: amount,
            caseId: keccak256(abi.encode("KONTROL-CASE", nonce)),
            scopeHash: SCOPE,
            policyCommitment: binding,
            provenanceCommitment: keccak256(abi.encode("KONTROL-PROVENANCE", nonce)),
            settlementCommitment: action == TrustTypes.ActionKind.LIQUIDATE
                ? keccak256(abi.encode("KONTROL-SETTLEMENT", nonce))
                : bytes32(0),
            proceedsCommitment: action == TrustTypes.ActionKind.LIQUIDATE
                ? keccak256(abi.encode("KONTROL-PROCEEDS", nonce))
                : bytes32(0),
            entitlementCommitment: bytes32(0),
            authorityRef: AUTHORITY_REF,
            authorityEpoch: 1,
            policyEpoch: epoch,
            nonce: nonce,
            validAfter: 0,
            validBefore: type(uint48).max
        });
        request.actionId = token.deriveActionId(request);
    }

    function _binding(TrustToken token) internal view returns (bytes32 binding) {
        (, binding,) = token.getBindingState(TrustTypes.BindingKind.POLICY);
    }

    /// @dev Implemented by erc-trust-log-assertions.k over KEVM's final log cell.
    function _assertFinalReceiptLogK(
        address emitter,
        TrustTypes.ActionRequest memory request,
        bytes32 receiptHash
    ) internal {
        bytes memory assertionCall = abi.encodeWithSelector(
            bytes4(keccak256("assertFinalReceiptLog(address,bytes32,bytes32,bytes32,bytes32,bytes32)")),
            emitter,
            keccak256("RegulatoryActionApplied(bytes32,uint8,bytes32,bytes32)"),
            request.actionId,
            bytes32(uint256(request.action)),
            request.caseId,
            receiptHash
        );
        (bool ignored,) = address(vm).call(assertionCall);
        ignored;
    }
}
