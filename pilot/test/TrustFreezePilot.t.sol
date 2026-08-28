// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {IERC165, IERC7943FreezePilot, IBoundPolicy, TrustFreezePilot} from "../src/TrustFreezePilot.sol";
import {MockBoundPolicy} from "../src/MockBoundPolicy.sol";

interface Vm {
    function expectEmit(bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData, address emitter) external;
}

contract PilotCaller {
    function callSetFrozenTokens(TrustFreezePilot token, address account, uint256 amount) external returns (bool) {
        return token.setFrozenTokens(account, amount);
    }

    function callTransferFrom(TrustFreezePilot token, address from, address to, uint256 amount)
        external
        returns (bool)
    {
        return token.transferFrom(from, to, amount);
    }
}

contract TrustFreezePilotTest {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    bytes32 internal constant AUTHORITY_REF = keccak256("ERC-TRUST/FREEZE-PILOT/AUTHORITY");
    address internal constant RECIPIENT = address(0xBEEF);
    uint256 internal constant INITIAL_SUPPLY = 100 ether;

    event Frozen(address indexed account, uint256 amount);
    event RegulatoryActionApplied(
        bytes32 indexed actionId,
        bytes32 indexed caseId,
        TrustFreezePilot.ActionKind indexed action,
        address source,
        address destination,
        uint256 amount,
        bytes32 authorizationId,
        bytes32 authorityRef,
        bytes32 policyBindingHash,
        bytes32 provenanceHash,
        bytes32 preObservationHash,
        bytes32 postObservationHash,
        bytes32 receiptHash
    );

    function testDirectTypedFreezeConsumesAndReceipts() external {
        (TrustFreezePilot token,) = _deploy(MockBoundPolicy.Mode.ALLOW);
        TrustFreezePilot.ActionRequest memory request = _actionRequest(token, 1, 40 ether);
        TrustFreezePilot.AuthorizationEnvelope memory authorization = _authorization(token, request, 1);

        bytes32 receiptHash = token.executeRegulatoryAction(request, authorization);

        require(receiptHash != bytes32(0), "missing receipt");
        require(token.getFrozenTokens(address(this)) == 40 ether, "wrong frozen amount");
        require(
            token.authorizationStatus(authorization.authorizationId) == TrustFreezePilot.AuthorizationStatus.CONSUMED,
            "authorization not consumed"
        );
        require(
            token.nonceStatus(AUTHORITY_REF, 1, request.nonce) == TrustFreezePilot.AuthorizationStatus.CONSUMED,
            "nonce not consumed"
        );
        (TrustFreezePilot.AuthorizationStatus status, bytes32 digest, bytes32 storedReceipt) =
            token.actionRecord(request.actionId);
        require(status == TrustFreezePilot.AuthorizationStatus.CONSUMED, "action not consumed");
        require(digest == token.commandDigest(request), "wrong command");
        require(storedReceipt == receiptHash, "wrong action receipt");

        TrustFreezePilot.ReceiptView memory receipt = token.actionReceipt(request.actionId);
        require(receipt.receiptHash == receiptHash, "receipt projection");
        require(receipt.authorizationId == authorization.authorizationId, "authorization projection");
        require(receipt.policyBindingHash == token.bindingHash(), "binding projection");
    }

    function testStagedSetFrozenConsumesExactTicketAndOrdersLogs() external {
        (TrustFreezePilot token,) = _deploy(MockBoundPolicy.Mode.ALLOW);
        TrustFreezePilot.ActionRequest memory request = _actionRequest(token, 2, 55 ether);
        TrustFreezePilot.AuthorizationEnvelope memory authorization = _authorization(token, request, 2);

        bytes32 routeKey = token.prepareRegulatoryAction(request, authorization);
        require(routeKey == _routeKey(token, request), "route key is not canonical");
        require(token.routeAuthorization(routeKey) == authorization.authorizationId, "route not staged");
        require(
            token.authorizationStatus(authorization.authorizationId) == TrustFreezePilot.AuthorizationStatus.PREPARED,
            "authorization not prepared"
        );

        (bytes32 preObservationHash, bytes32 postObservationHash, bytes32 previewReceipt) =
            token.previewPreparedReceipt(authorization.authorizationId);

        vm.expectEmit(true, false, false, true, address(token));
        emit Frozen(address(this), request.amount);
        vm.expectEmit(true, true, true, true, address(token));
        emit RegulatoryActionApplied(
            request.actionId,
            request.caseId,
            TrustFreezePilot.ActionKind.FREEZE,
            request.source,
            request.destination,
            request.amount,
            authorization.authorizationId,
            authorization.authorityRef,
            request.policyBindingHash,
            request.provenanceHash,
            preObservationHash,
            postObservationHash,
            previewReceipt
        );
        token.setFrozenTokens(address(this), request.amount);

        require(token.routeAuthorization(routeKey) == bytes32(0), "route not consumed");
        require(
            token.authorizationStatus(authorization.authorizationId) == TrustFreezePilot.AuthorizationStatus.CONSUMED,
            "authorization not consumed"
        );

        TrustFreezePilot.ReceiptView memory receipt = token.actionReceipt(request.actionId);
        require(receipt.receiptHash != bytes32(0), "receipt missing");
        require(previewReceipt == receipt.receiptHash, "preview receipt mismatch");
    }

    function testRawNoTicketRevertsAndStutters() external {
        (TrustFreezePilot token,) = _deploy(MockBoundPolicy.Mode.ALLOW);
        TrustFreezePilot.ActionRequest memory request = _actionRequest(token, 3, 10 ether);
        TrustFreezePilot.AuthorizationEnvelope memory authorization = _authorization(token, request, 3);
        bytes32 routeKey = _routeKey(token, request);
        bytes32 beforeState = _fingerprint(token, request, authorization, routeKey);

        (bool ok, bytes memory result) =
            address(token).call(abi.encodeCall(IERC7943FreezePilot.setFrozenTokens, (address(this), request.amount)));

        require(!ok, "raw route succeeded");
        require(_selector(result) == TrustFreezePilot.TrustRejected.selector, "wrong raw-route error");
        require(_fingerprint(token, request, authorization, routeKey) == beforeState, "raw route changed state");
    }

    function testWrongCallerAndCalldataMismatchStutter() external {
        (TrustFreezePilot token,) = _deploy(MockBoundPolicy.Mode.ALLOW);
        TrustFreezePilot.ActionRequest memory request = _actionRequest(token, 4, 20 ether);
        TrustFreezePilot.AuthorizationEnvelope memory authorization = _authorization(token, request, 4);
        bytes32 routeKey = token.prepareRegulatoryAction(request, authorization);
        bytes32 beforeState = _fingerprint(token, request, authorization, routeKey);

        PilotCaller caller = new PilotCaller();
        (bool wrongCallerOk,) = address(caller)
            .call(abi.encodeCall(PilotCaller.callSetFrozenTokens, (token, address(this), request.amount)));
        require(!wrongCallerOk, "wrong caller succeeded");
        require(_fingerprint(token, request, authorization, routeKey) == beforeState, "wrong caller changed state");
        require(
            token.routeAuthorization(routeKey) == authorization.authorizationId, "wrong caller consumed target route"
        );

        (bool mismatchOk,) = address(token)
            .call(abi.encodeCall(IERC7943FreezePilot.setFrozenTokens, (address(this), request.amount + 1)));
        require(!mismatchOk, "mismatched calldata succeeded");
        require(
            _fingerprint(token, request, authorization, routeKey) == beforeState, "mismatched calldata changed state"
        );
        require(
            token.routeAuthorization(routeKey) == authorization.authorizationId, "wrong calldata consumed target route"
        );
        require(
            token.authorizationStatus(authorization.authorizationId) == TrustFreezePilot.AuthorizationStatus.PREPARED,
            "wrong route changed target authorization"
        );
    }

    function testReplayAndStaleBindingCannotConsumeTicket() external {
        (TrustFreezePilot token,) = _deploy(MockBoundPolicy.Mode.ALLOW);
        TrustFreezePilot.ActionRequest memory request = _actionRequest(token, 5, 25 ether);
        TrustFreezePilot.AuthorizationEnvelope memory authorization = _authorization(token, request, 5);
        bytes32 routeKey = token.prepareRegulatoryAction(request, authorization);
        token.setFrozenTokens(address(this), request.amount);
        bytes32 afterApply = _fingerprint(token, request, authorization, routeKey);

        require(token.routeAuthorization(routeKey) == bytes32(0), "consumed route remains");
        require(!token.preparedRoute(authorization.authorizationId).exists, "consumed prepared route remains");
        require(
            token.nonceStatus(authorization.authorityRef, request.authorityEpoch, request.nonce)
                == TrustFreezePilot.AuthorizationStatus.CONSUMED,
            "consumed nonce status missing"
        );

        (bool replayOk,) =
            address(token).call(abi.encodeCall(IERC7943FreezePilot.setFrozenTokens, (address(this), request.amount)));
        require(!replayOk, "replay succeeded");
        require(_fingerprint(token, request, authorization, routeKey) == afterApply, "replay changed state");

        (TrustFreezePilot staleToken,) = _deploy(MockBoundPolicy.Mode.ALLOW);
        TrustFreezePilot.ActionRequest memory staleRequest = _actionRequest(staleToken, 6, 30 ether);
        TrustFreezePilot.AuthorizationEnvelope memory staleAuthorization = _authorization(staleToken, staleRequest, 6);
        bytes32 staleRouteKey = staleToken.prepareRegulatoryAction(staleRequest, staleAuthorization);
        MockBoundPolicy replacement = new MockBoundPolicy(MockBoundPolicy.Mode.ALLOW);
        staleToken.rebindPolicy(IBoundPolicy(address(replacement)), keccak256("GOVERNANCE-6"), 600);
        bytes32 beforeStaleUse = _fingerprint(staleToken, staleRequest, staleAuthorization, staleRouteKey);

        require(
            staleToken.routeAuthorization(staleRouteKey) == staleAuthorization.authorizationId,
            "rebind consumed stale target route"
        );
        require(
            staleToken.preparedRoute(staleAuthorization.authorizationId).exists, "rebind deleted stale target route"
        );

        (bool staleOk,) = address(staleToken)
            .call(abi.encodeCall(IERC7943FreezePilot.setFrozenTokens, (address(this), staleRequest.amount)));
        require(!staleOk, "stale route succeeded");
        require(
            _fingerprint(staleToken, staleRequest, staleAuthorization, staleRouteKey) == beforeStaleUse,
            "stale route changed state"
        );
    }

    function testPolicyRejectAndFailuresStutter() external {
        _assertPolicyFailureStutters(MockBoundPolicy.Mode.REJECT, 7, TrustFreezePilot.TrustRejected.selector);
        _assertPolicyFailureStutters(
            MockBoundPolicy.Mode.REVERT_CALL, 8, TrustFreezePilot.TrustOperationalFailure.selector
        );
        _assertPolicyFailureStutters(
            MockBoundPolicy.Mode.MALFORMED, 9, TrustFreezePilot.TrustOperationalFailure.selector
        );
        _assertPolicyFailureStutters(
            MockBoundPolicy.Mode.WRONG_COMMAND, 10, TrustFreezePilot.TrustOperationalFailure.selector
        );
        _assertPolicyFailureStutters(
            MockBoundPolicy.Mode.WRONG_BINDING, 11, TrustFreezePilot.TrustOperationalFailure.selector
        );
        _assertPolicyFailureStutters(
            MockBoundPolicy.Mode.BAD_OUTCOME, 12, TrustFreezePilot.TrustOperationalFailure.selector
        );
    }

    function testOrdinaryTransferCannotSpendFrozenAmount() external {
        (TrustFreezePilot token,) = _deploy(MockBoundPolicy.Mode.ALLOW);
        TrustFreezePilot.ActionRequest memory request = _actionRequest(token, 13, 70 ether);
        TrustFreezePilot.AuthorizationEnvelope memory authorization = _authorization(token, request, 13);
        token.executeRegulatoryAction(request, authorization);

        require(!token.canTransfer(address(this), RECIPIENT, INITIAL_SUPPLY + 1), "over-balance query allowed");
        (bool tooMuchOk,) = address(token).call(abi.encodeCall(TrustFreezePilot.transfer, (RECIPIENT, 30 ether + 1)));
        require(!tooMuchOk, "spent frozen amount");
        require(token.balanceOf(address(this)) == INITIAL_SUPPLY, "failed transfer changed source");
        require(token.balanceOf(RECIPIENT) == 0, "failed transfer changed recipient");

        require(token.transfer(RECIPIENT, 30 ether), "available transfer");
        require(token.balanceOf(address(this)) == 70 ether, "wrong source balance");
        require(token.balanceOf(RECIPIENT) == 30 ether, "wrong recipient balance");
    }

    function testTransferFromUsesSameOrdinaryGate() external {
        (TrustFreezePilot token,) = _deploy(MockBoundPolicy.Mode.ALLOW);
        TrustFreezePilot.ActionRequest memory request = _actionRequest(token, 14, 80 ether);
        TrustFreezePilot.AuthorizationEnvelope memory authorization = _authorization(token, request, 14);
        token.executeRegulatoryAction(request, authorization);

        PilotCaller spender = new PilotCaller();
        token.approve(address(spender), 100 ether);
        (bool blocked,) = address(spender)
            .call(abi.encodeCall(PilotCaller.callTransferFrom, (token, address(this), RECIPIENT, 20 ether + 1)));
        require(!blocked, "transferFrom bypassed ordinary gate");
        require(token.allowance(address(this), address(spender)) == 100 ether, "failed transferFrom consumed allowance");

        require(spender.callTransferFrom(token, address(this), RECIPIENT, 20 ether), "available transferFrom failed");
    }

    function testOverFrozenBalanceRejectsPositiveTransferAndTransferFrom() external {
        (TrustFreezePilot token,) = _deploy(MockBoundPolicy.Mode.ALLOW);
        TrustFreezePilot.ActionRequest memory request = _actionRequest(token, 19, INITIAL_SUPPLY + 1);
        TrustFreezePilot.AuthorizationEnvelope memory authorization = _authorization(token, request, 19);
        token.executeRegulatoryAction(request, authorization);

        require(!token.canTransfer(address(this), RECIPIENT, 1), "over-frozen query allowed positive transfer");
        (bool transferOk,) = address(token).call(abi.encodeCall(TrustFreezePilot.transfer, (RECIPIENT, 1)));
        require(!transferOk, "over-frozen transfer succeeded");

        PilotCaller spender = new PilotCaller();
        token.approve(address(spender), 1);
        (bool transferFromOk,) =
            address(spender).call(abi.encodeCall(PilotCaller.callTransferFrom, (token, address(this), RECIPIENT, 1)));
        require(!transferFromOk, "over-frozen transferFrom succeeded");
        require(token.allowance(address(this), address(spender)) == 1, "failed transferFrom consumed allowance");
    }

    function testTypedUnfreezeUsesSeparateReversalReceipt() external {
        (TrustFreezePilot token,) = _deploy(MockBoundPolicy.Mode.ALLOW);
        TrustFreezePilot.ActionRequest memory request = _actionRequest(token, 15, 60 ether);
        TrustFreezePilot.AuthorizationEnvelope memory authorization = _authorization(token, request, 15);
        token.executeRegulatoryAction(request, authorization);

        TrustFreezePilot.ReversalRequest memory reversal = _reversalRequest(token, request.caseId, 16, 20 ether);
        TrustFreezePilot.AuthorizationEnvelope memory reversalAuthorization =
            _reversalAuthorization(token, reversal, 16);
        bytes32 receiptHash = token.executeRegulatoryReversal(reversal, reversalAuthorization);

        require(receiptHash != bytes32(0), "missing reversal receipt");
        require(token.getFrozenTokens(address(this)) == 40 ether, "wrong unfreeze result");
        TrustFreezePilot.ReceiptView memory receipt = token.actionReceipt(reversal.commandId);
        require(receipt.receiptHash == receiptHash, "reversal projection");
    }

    function testCancelRemovesPreparedRoute() external {
        (TrustFreezePilot token,) = _deploy(MockBoundPolicy.Mode.ALLOW);
        TrustFreezePilot.ActionRequest memory request = _actionRequest(token, 17, 10 ether);
        TrustFreezePilot.AuthorizationEnvelope memory authorization = _authorization(token, request, 17);
        bytes32 routeKey = token.prepareRegulatoryAction(request, authorization);
        token.cancelAuthorization(authorization.authorizationId);

        require(
            token.authorizationStatus(authorization.authorizationId) == TrustFreezePilot.AuthorizationStatus.CANCELLED,
            "authorization not cancelled"
        );
        require(token.routeAuthorization(routeKey) == bytes32(0), "cancelled route remains");
        require(!token.preparedRoute(authorization.authorizationId).exists, "cancelled prepared route remains");
        require(
            token.nonceStatus(authorization.authorityRef, request.authorityEpoch, request.nonce)
                == TrustFreezePilot.AuthorizationStatus.CANCELLED,
            "cancelled nonce status missing"
        );
        (bool ok,) =
            address(token).call(abi.encodeCall(IERC7943FreezePilot.setFrozenTokens, (address(this), request.amount)));
        require(!ok, "cancelled route consumed");
    }

    function testInterfaceBoundaryIsExplicit() external {
        (TrustFreezePilot token,) = _deploy(MockBoundPolicy.Mode.ALLOW);
        require(token.supportsInterface(type(IERC165).interfaceId), "missing ERC-165");
        require(token.supportsInterface(type(IERC7943FreezePilot).interfaceId), "missing pilot interface");
        require(!token.supportsInterface(0x3edbb4c4), "overclaims complete ERC-7943");
        (TrustFreezePilot.ProfileKind profile, uint256 actionMask, address underlyingToken, bytes32 manifestHash) =
            token.trustProfile();
        require(profile == TrustFreezePilot.ProfileKind.UNSUPPORTED, "overclaims Native Full");
        require(actionMask == 1, "wrong FREEZE mask");
        require(underlyingToken == address(0), "unexpected underlying");
        require(manifestHash == token.MANIFEST_HASH(), "wrong manifest");
    }

    function testFuzzOrdinaryGate(uint96 rawFrozen, uint96 rawAmount) external {
        uint256 frozen = uint256(rawFrozen) % (INITIAL_SUPPLY + 1);
        uint256 amount = uint256(rawAmount) % (INITIAL_SUPPLY + 1);
        if (frozen == 0) {
            frozen = 1;
        }

        (TrustFreezePilot token,) = _deploy(MockBoundPolicy.Mode.ALLOW);
        TrustFreezePilot.ActionRequest memory request = _actionRequest(token, 18, frozen);
        TrustFreezePilot.AuthorizationEnvelope memory authorization = _authorization(token, request, 18);
        token.executeRegulatoryAction(request, authorization);

        uint256 beforeSource = token.balanceOf(address(this));
        uint256 beforeRecipient = token.balanceOf(RECIPIENT);
        (bool ok,) = address(token).call(abi.encodeCall(TrustFreezePilot.transfer, (RECIPIENT, amount)));
        bool shouldSucceed = amount <= INITIAL_SUPPLY - frozen;
        require(ok == shouldSucceed, "gate verdict mismatch");
        if (!ok) {
            require(token.balanceOf(address(this)) == beforeSource, "failed fuzz transfer changed source");
            require(token.balanceOf(RECIPIENT) == beforeRecipient, "failed fuzz transfer changed recipient");
        }
    }

    function _deploy(MockBoundPolicy.Mode mode) internal returns (TrustFreezePilot token, MockBoundPolicy policy) {
        policy = new MockBoundPolicy(mode);
        token = new TrustFreezePilot(
            address(this), AUTHORITY_REF, IBoundPolicy(address(policy)), address(this), INITIAL_SUPPLY
        );
    }

    function _actionRequest(TrustFreezePilot token, uint256 seed, uint256 targetFrozenAmount)
        internal
        view
        returns (TrustFreezePilot.ActionRequest memory request)
    {
        request = TrustFreezePilot.ActionRequest({
            actionId: keccak256(abi.encode("ACTION", seed)),
            caseId: keccak256(abi.encode("CASE", seed)),
            action: TrustFreezePilot.ActionKind.FREEZE,
            subject: address(this),
            source: address(this),
            destination: address(0),
            amount: targetFrozenAmount,
            policyBindingHash: token.bindingHash(),
            provenanceHash: keccak256(abi.encode("PROVENANCE", seed)),
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
            authorizationId: keccak256(abi.encode("AUTHORIZATION", seed)),
            authorityRef: AUTHORITY_REF,
            issuer: address(this),
            actor: address(this),
            delegationRef: keccak256(abi.encode("DELEGATION", seed)),
            proof: bytes("")
        });
        bytes32 digest = token.commandDigest(request);
        authorization.proof = abi.encode(token.authorizationProofDigest(digest, authorization));
    }

    function _reversalRequest(TrustFreezePilot token, bytes32 caseId, uint256 seed, uint256 amount)
        internal
        view
        returns (TrustFreezePilot.ReversalRequest memory request)
    {
        request = TrustFreezePilot.ReversalRequest({
            commandId: keccak256(abi.encode("REVERSAL", seed)),
            caseId: caseId,
            reversal: TrustFreezePilot.ReversalKind.UNFREEZE,
            subject: address(this),
            amount: amount,
            policyBindingHash: token.bindingHash(),
            provenanceHash: keccak256(abi.encode("REVERSAL-PROVENANCE", seed)),
            authorityEpoch: token.authorityEpoch(),
            policyEpoch: token.policyEpoch(),
            nonce: seed,
            validAfter: 0,
            deadline: type(uint48).max
        });
    }

    function _reversalAuthorization(
        TrustFreezePilot token,
        TrustFreezePilot.ReversalRequest memory request,
        uint256 seed
    ) internal view returns (TrustFreezePilot.AuthorizationEnvelope memory authorization) {
        authorization = TrustFreezePilot.AuthorizationEnvelope({
                authorizationId: keccak256(abi.encode("REVERSAL-AUTHORIZATION", seed)),
                authorityRef: AUTHORITY_REF,
                issuer: address(this),
                actor: address(this),
                delegationRef: keccak256(abi.encode("REVERSAL-DELEGATION", seed)),
                proof: bytes("")
            });
        bytes32 digest = token.reversalCommandDigest(request);
        authorization.proof = abi.encode(token.authorizationProofDigest(digest, authorization));
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
            RECIPIENT,
            request.nonce
        );
    }

    function _assertPolicyFailureStutters(MockBoundPolicy.Mode mode, uint256 seed, bytes4 expectedError) internal {
        (TrustFreezePilot token,) = _deploy(mode);
        TrustFreezePilot.ActionRequest memory request = _actionRequest(token, seed, 10 ether);
        TrustFreezePilot.AuthorizationEnvelope memory authorization = _authorization(token, request, seed);
        bytes32 routeKey = _routeKey(token, request);
        bytes32 beforeState = _fingerprint(token, request, authorization, routeKey);

        bool ok;
        bytes memory result;
        try token.executeRegulatoryAction(request, authorization) returns (bytes32) {
            ok = true;
        } catch (bytes memory revertData) {
            result = revertData;
        }
        require(!ok, "policy failure applied");
        require(_selector(result) == expectedError, "wrong policy error");
        require(_fingerprint(token, request, authorization, routeKey) == beforeState, "policy failure changed state");
    }

    function _selector(bytes memory returndata) internal pure returns (bytes4 selector) {
        if (returndata.length < 4) {
            return bytes4(0);
        }
        assembly ("memory-safe") {
            selector := mload(add(returndata, 0x20))
        }
    }
}
