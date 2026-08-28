// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {IERC7943FreezePilot, IBoundPolicy, TrustFreezePilot} from "../src/TrustFreezePilot.sol";
import {MockBoundPolicy} from "../src/MockBoundPolicy.sol";

interface KontrolVm {
    function expectRevert() external;
}

/// @notice Narrow KEVM proof harness for the preserved FREEZE vertical slice.
contract TrustFreezePilotKontrolTest {
    KontrolVm internal constant vm = KontrolVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    bytes32 internal constant AUTHORITY_REF = keccak256("ERC-TRUST/FREEZE-PILOT/AUTHORITY");
    address internal constant OTHER = address(0xBEEF);
    uint256 internal constant INITIAL_SUPPLY = 100 ether;

    /// @dev Proves the route transition and exact Frozen -> canonical-receipt log suffix.
    function testKontrol_StagedFreezeEventOrder() external {
        TrustFreezePilot token = _deploy(MockBoundPolicy.Mode.ALLOW);
        TrustFreezePilot.ActionRequest memory request = _request(token, 1, 55 ether);
        TrustFreezePilot.AuthorizationEnvelope memory authorization = _authorization(token, request, 1);

        bytes32 routeKey = token.prepareRegulatoryAction(request, authorization);
        (bytes32 preObservationHash, bytes32 postObservationHash, bytes32 previewReceipt) =
            token.previewPreparedReceipt(authorization.authorizationId);

        require(token.setFrozenTokens(address(this), request.amount), "set failed");
        _assertLastTwoLogsK(token, request, authorization, preObservationHash, postObservationHash, previewReceipt);
        _assertStagedPostState(token, request, authorization, routeKey, previewReceipt);
    }

    /// @dev Proves an unavailable bound policy reverts with no pilot-state or log change.
    function testKontrol_PolicyFailureStutters() external {
        TrustFreezePilot token = _deploy(MockBoundPolicy.Mode.REVERT_CALL);
        TrustFreezePilot.ActionRequest memory request = _request(token, 2, 10 ether);
        TrustFreezePilot.AuthorizationEnvelope memory authorization = _authorization(token, request, 2);
        bytes32 routeKey = _routeKey(token, request);
        bytes32 beforeState = _fingerprint(token, request, authorization, routeKey);

        vm.expectRevert();
        token.executeRegulatoryAction(request, authorization);

        bytes32 afterState = _fingerprint(token, request, authorization, routeKey);
        require(afterState == beforeState, "failure changed state");
        _assertOnlyConstructorTransferK(token);
    }

    /// @dev Implemented by erc-trust-log-assertions.k against KEVM's <log> cell.
    function _assertLastTwoLogsK(
        TrustFreezePilot token,
        TrustFreezePilot.ActionRequest memory request,
        TrustFreezePilot.AuthorizationEnvelope memory authorization,
        bytes32 preObservationHash,
        bytes32 postObservationHash,
        bytes32 previewReceipt
    ) internal {
        bytes memory assertionCall = abi.encodeWithSelector(
            bytes4(
                keccak256(
                    "assertLastTwoLogs(address,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32)"
                )
            ),
            address(token),
            keccak256("Frozen(address,uint256)"),
            bytes32(uint256(uint160(request.subject))),
            bytes32(request.amount),
            keccak256(
                "RegulatoryActionApplied(bytes32,bytes32,uint8,address,address,uint256,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32)"
            ),
            request.actionId,
            request.caseId,
            bytes32(uint256(TrustFreezePilot.ActionKind.FREEZE)),
            bytes32(uint256(uint160(request.source))),
            bytes32(uint256(uint160(request.destination))),
            bytes32(request.amount),
            authorization.authorizationId,
            authorization.authorityRef,
            request.policyBindingHash,
            request.provenanceHash,
            preObservationHash,
            postObservationHash,
            previewReceipt
        );
        (bool ignored,) = address(vm).call(assertionCall);
        ignored;
    }

    /// @dev Matches the complete KEVM log cell after the reverted policy call.
    function _assertOnlyConstructorTransferK(TrustFreezePilot token) internal {
        bytes memory assertionCall = abi.encodeWithSelector(
            bytes4(keccak256("assertOnlyConstructorTransfer(address,bytes32,bytes32,bytes32,bytes32)")),
            address(token),
            keccak256("Transfer(address,address,uint256)"),
            bytes32(0),
            bytes32(uint256(uint160(address(this)))),
            bytes32(INITIAL_SUPPLY)
        );
        (bool ignored,) = address(vm).call(assertionCall);
        ignored;
    }

    function _assertStagedPostState(
        TrustFreezePilot token,
        TrustFreezePilot.ActionRequest memory request,
        TrustFreezePilot.AuthorizationEnvelope memory authorization,
        bytes32 routeKey,
        bytes32 previewReceipt
    ) internal view {
        require(token.getFrozenTokens(address(this)) == request.amount, "wrong frozen amount");
        require(token.routeAuthorization(routeKey) == bytes32(0), "route remains");
        require(
            token.authorizationStatus(authorization.authorizationId) == TrustFreezePilot.AuthorizationStatus.CONSUMED,
            "authorization not consumed"
        );
        require(token.actionReceipt(request.actionId).receiptHash == previewReceipt, "receipt mismatch");
    }

    function _deploy(MockBoundPolicy.Mode mode) internal returns (TrustFreezePilot token) {
        MockBoundPolicy policy = new MockBoundPolicy(mode);
        token = new TrustFreezePilot(
            address(this), AUTHORITY_REF, IBoundPolicy(address(policy)), address(this), INITIAL_SUPPLY
        );
    }

    function _request(TrustFreezePilot token, uint256 seed, uint256 targetFrozenAmount)
        internal
        view
        returns (TrustFreezePilot.ActionRequest memory request)
    {
        request = TrustFreezePilot.ActionRequest({
            actionId: keccak256(abi.encode("KONTROL/ACTION", seed)),
            caseId: keccak256(abi.encode("KONTROL/CASE", seed)),
            action: TrustFreezePilot.ActionKind.FREEZE,
            subject: address(this),
            source: address(this),
            destination: address(0),
            amount: targetFrozenAmount,
            policyBindingHash: token.bindingHash(),
            provenanceHash: keccak256(abi.encode("KONTROL/PROVENANCE", seed)),
            actionDataHash: keccak256(abi.encode(targetFrozenAmount)),
            authorityEpoch: token.authorityEpoch(),
            policyEpoch: token.policyEpoch(),
            nonce: seed,
            validAfter: 0,
            deadline: type(uint48).max
        });
    }

    function _authorization(TrustFreezePilot token, TrustFreezePilot.ActionRequest memory request, uint256 seed)
        internal
        view
        returns (TrustFreezePilot.AuthorizationEnvelope memory authorization)
    {
        authorization = TrustFreezePilot.AuthorizationEnvelope({
            authorizationId: keccak256(abi.encode("KONTROL/AUTHORIZATION", seed)),
            authorityRef: AUTHORITY_REF,
            issuer: address(this),
            actor: address(this),
            delegationRef: keccak256(abi.encode("KONTROL/DELEGATION", seed)),
            proof: bytes("")
        });
        authorization.proof = abi.encode(token.authorizationProofDigest(token.commandDigest(request), authorization));
    }

    function _routeKey(TrustFreezePilot token, TrustFreezePilot.ActionRequest memory request)
        internal
        view
        returns (bytes32)
    {
        return token.computeRouteKey(
            address(this),
            IERC7943FreezePilot.setFrozenTokens.selector,
            keccak256(abi.encodeCall(IERC7943FreezePilot.setFrozenTokens, (request.subject, request.amount))),
            request.policyBindingHash,
            request.authorityEpoch,
            request.policyEpoch
        );
    }

    function _fingerprint(
        TrustFreezePilot token,
        TrustFreezePilot.ActionRequest memory request,
        TrustFreezePilot.AuthorizationEnvelope memory authorization,
        bytes32 routeKey
    ) internal view returns (bytes32) {
        return token.stateFingerprint(
            request.actionId,
            authorization.authorizationId,
            request.caseId,
            routeKey,
            request.subject,
            OTHER,
            request.nonce
        );
    }
}
