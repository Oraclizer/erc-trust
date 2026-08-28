// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustTypes} from "../src/TrustTypes.sol";
import {ERC3643TrustAdapter} from "../src/profiles/ERC3643TrustAdapter.sol";
import {ProfileGovernor} from "../src/profiles/ProfileGovernor.sol";
import {MockERC3643Token} from "./mocks/MockERC3643Token.sol";
import {MockERC3643IdentityRegistry, MockERC3643Compliance} from "./mocks/MockERC3643Dependencies.sol";
import {TrustOperationalFailure} from "../src/TrustErrors.sol";

contract ERC3643ProfileUnitTest {
    bytes32 internal constant DOMAIN = keccak256("ERC-TRUST/reference-v1");
    bytes32 internal constant AUTHORITY_REF = keccak256("ERC3643-AUTHORITY");
    uint256 internal constant SUPPLY = 1_000_000 ether;

    MockERC3643IdentityRegistry internal identity;
    MockERC3643Compliance internal compliance;
    MockERC3643Token internal token;
    ProfileGovernor internal governor;
    ERC3643TrustAdapter internal adapter;
    address internal custodian = address(0xc0570d1a);
    address internal buyer = address(0xb0b);
    address internal recovered = address(0xbeef);

    function setUp() public {
        identity = new MockERC3643IdentityRegistry();
        compliance = new MockERC3643Compliance();
        token = new MockERC3643Token(address(identity), address(compliance), SUPPLY);
        governor = new ProfileGovernor(
            address(token), address(identity), address(compliance), address(this), address(token).codehash
        );
        adapter = new ERC3643TrustAdapter(address(governor), address(this), AUTHORITY_REF, 1);
        token.setExclusiveAgent(address(adapter));
        token.transferOwnership(address(governor));
        governor.seal(address(adapter));

        identity.setVerified(address(this), true);
        identity.setVerified(address(adapter), true);
        identity.setVerified(buyer, true);
        identity.setVerified(recovered, true);
    }

    function testProfileSealAndDirectBypassClosure() external {
        (bytes32 profile, uint256 mask, bool proxySupported, bool full) = adapter.trustProfile();
        require(profile == keccak256("ERC-TRUST-ERC3643-VERIFIED-FULL-V1"), "profile");
        require(mask == 0x3f && !proxySupported && full, "capability");

        (bool direct,) = address(token).call(abi.encodeCall(token.forcedTransfer, (address(this), buyer, 1 ether)));
        require(!direct, "raw direct bypass");

        address[] memory from = new address[](1);
        address[] memory to = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        from[0] = address(this);
        to[0] = buyer;
        amounts[0] = 1 ether;
        (bool batch,) = address(token).call(abi.encodeCall(token.batchForcedTransfer, (from, to, amounts)));
        require(!batch, "batch bypass");
    }

    function testUnsealedOrNonExclusiveTopologyCannotReportOrExecuteFull() external {
        MockERC3643Token otherToken = new MockERC3643Token(address(identity), address(compliance), 100 ether);
        ProfileGovernor otherGovernor = new ProfileGovernor(
            address(otherToken), address(identity), address(compliance), address(this), address(otherToken).codehash
        );
        ERC3643TrustAdapter otherAdapter =
            new ERC3643TrustAdapter(address(otherGovernor), address(this), AUTHORITY_REF, 1);
        (,,, bool full) = otherAdapter.trustProfile();
        require(!full, "unsealed Full");

        TrustTypes.ActionRequest memory request = _request(TrustTypes.ActionKind.FREEZE, 99, 1 ether);
        request.policyCommitment = bytes32(0);
        request.actionId = otherAdapter.deriveActionId(request);
        (bool executed,) = address(otherAdapter).call(abi.encodeCall(otherAdapter.executeRegulatoryAction, (request)));
        require(!executed, "unsealed execute");
    }

    function testAllSixActionsAndReversals() external {
        TrustTypes.ActionRequest memory freeze = _request(TrustTypes.ActionKind.FREEZE, 1, 25 ether);
        adapter.executeRegulatoryAction(freeze);
        require(token.getFrozenTokens(address(this)) == 25 ether, "freeze");

        TrustTypes.ActionRequest memory equalFreeze = _request(TrustTypes.ActionKind.FREEZE, 90, 25 ether);
        adapter.executeRegulatoryAction(equalFreeze);

        TrustTypes.ActionRequest memory decreaseFreeze = _request(TrustTypes.ActionKind.FREEZE, 91, 10 ether);
        adapter.executeRegulatoryAction(decreaseFreeze);
        require(token.getFrozenTokens(address(this)) == 10 ether, "absolute replacement");

        (bool staleOk,) = address(adapter)
            .call(
                abi.encodeCall(
                    adapter.executeRegulatoryReversal, (_reversal(freeze.actionId, TrustTypes.ReversalKind.UNFREEZE, 2))
                )
            );
        require(!staleOk && token.getFrozenTokens(address(this)) == 10 ether, "stale reversal");
        adapter.executeRegulatoryReversal(_reversal(decreaseFreeze.actionId, TrustTypes.ReversalKind.UNFREEZE, 92));
        adapter.executeRegulatoryReversal(_reversal(equalFreeze.actionId, TrustTypes.ReversalKind.UNFREEZE, 93));
        adapter.executeRegulatoryReversal(_reversal(freeze.actionId, TrustTypes.ReversalKind.UNFREEZE, 94));
        require(token.getFrozenTokens(address(this)) == 0, "unfreeze");

        TrustTypes.ActionRequest memory restrict = _request(TrustTypes.ActionKind.RESTRICT, 3, 1);
        adapter.executeRegulatoryAction(restrict);
        require(token.isFrozen(address(this)), "restrict");
        adapter.executeRegulatoryReversal(_reversal(restrict.actionId, TrustTypes.ReversalKind.UNRESTRICT, 4));
        require(!token.isFrozen(address(this)), "unrestrict");

        TrustTypes.ActionRequest memory seize = _request(TrustTypes.ActionKind.SEIZE, 5, 11 ether);
        adapter.executeRegulatoryAction(seize);
        require(token.balanceOf(address(adapter)) == 11 ether, "seize");
        adapter.executeRegulatoryReversal(_reversal(seize.actionId, TrustTypes.ReversalKind.RELEASE, 6));
        require(token.balanceOf(address(adapter)) == 0, "release");

        adapter.executeRegulatoryAction(_request(TrustTypes.ActionKind.CONFISCATE, 7, 7 ether));
        adapter.executeRegulatoryAction(_request(TrustTypes.ActionKind.LIQUIDATE, 8, 5 ether));
        adapter.executeRegulatoryAction(_request(TrustTypes.ActionKind.RECOVER, 9, 3 ether));
        require(token.balanceOf(buyer) == 12 ether, "disposition");
        require(token.balanceOf(recovered) == 3 ether, "recover");
    }

    function testRejectedAndOperationalFailureFailClosedWithStutter() external {
        TrustTypes.ActionRequest memory rejected = _request(TrustTypes.ActionKind.CONFISCATE, 20, 4 ether);
        identity.setVerified(buyer, false);
        uint256 beforeBalance = token.balanceOf(address(this));
        (bool rejectedOk,) = address(adapter).call(abi.encodeCall(adapter.executeRegulatoryAction, (rejected)));
        require(!rejectedOk && token.balanceOf(address(this)) == beforeBalance, "rejected stutter");
        require(adapter.actionRecord(rejected.actionId).lifecycle == TrustTypes.Lifecycle.NONE, "rejected record");

        identity.setVerified(buyer, true);
        compliance.setMode(MockERC3643Compliance.Mode.MALFORMED);
        TrustTypes.ActionRequest memory failed = _request(TrustTypes.ActionKind.CONFISCATE, 21, 4 ether);
        (bool failedOk,) = address(adapter).call(abi.encodeCall(adapter.executeRegulatoryAction, (failed)));
        require(!failedOk && token.balanceOf(address(this)) == beforeBalance, "failure stutter");
        require(adapter.actionRecord(failed.actionId).lifecycle == TrustTypes.Lifecycle.NONE, "failure record");
    }

    function testReplayAndFixedActionNegative() external {
        TrustTypes.ActionRequest memory action = _request(TrustTypes.ActionKind.CONFISCATE, 30, 2 ether);
        adapter.executeRegulatoryAction(action);
        require(adapter.caseTerminal(action.caseId), "terminal case flag");
        (bool replay,) = address(adapter).call(abi.encodeCall(adapter.executeRegulatoryAction, (action)));
        require(!replay, "replay");

        TrustTypes.ActionRequest memory reusedCase = _request(TrustTypes.ActionKind.FREEZE, 31, 1 ether);
        reusedCase.caseId = action.caseId;
        reusedCase.actionId = adapter.deriveActionId(reusedCase);
        (bool reusedCaseOk,) = address(adapter).call(abi.encodeCall(adapter.executeRegulatoryAction, (reusedCase)));
        require(!reusedCaseOk, "terminal case reuse");

        TrustTypes.ActionRequest memory mutated = _request(TrustTypes.ActionKind.CONFISCATE, 32, 2 ether);
        mutated.destination = recovered;
        (bool fixedAction,) = address(adapter).call(abi.encodeCall(adapter.executeRegulatoryAction, (mutated)));
        require(!fixedAction, "fixed action");
    }

    function testConfiscateFromCustodyClosesAndTerminatesCase() external {
        TrustTypes.ActionRequest memory seize = _request(TrustTypes.ActionKind.SEIZE, 40, 6 ether);
        adapter.executeRegulatoryAction(seize);

        TrustTypes.ActionRequest memory confiscate = _request(TrustTypes.ActionKind.CONFISCATE, 41, seize.amount);
        confiscate.caseId = seize.caseId;
        confiscate.subject = seize.subject;
        confiscate.source = seize.custodian;
        confiscate.actionId = adapter.deriveActionId(confiscate);
        adapter.executeRegulatoryAction(confiscate);

        require(!adapter.custody(seize.caseId).active, "custody must close");
        require(adapter.caseTerminal(seize.caseId), "case terminal");
        require(token.balanceOf(address(adapter)) == 0, "custodian balance");
    }

    function testCustodyIsAdapterConfinedAndBackingCannotBeSpentByAnotherCase() external {
        TrustTypes.ActionRequest memory arbitrary = _request(TrustTypes.ActionKind.SEIZE, 50, 5 ether);
        arbitrary.destination = custodian;
        arbitrary.custodian = custodian;
        arbitrary.actionId = adapter.deriveActionId(arbitrary);
        (bool arbitraryOk,) = address(adapter).call(abi.encodeCall(adapter.executeRegulatoryAction, (arbitrary)));
        require(!arbitraryOk, "arbitrary custodian");

        TrustTypes.ActionRequest memory seize = _request(TrustTypes.ActionKind.SEIZE, 51, 5 ether);
        adapter.executeRegulatoryAction(seize);

        TrustTypes.ActionRequest memory direct = _request(TrustTypes.ActionKind.CONFISCATE, 52, 1 ether);
        direct.subject = address(adapter);
        direct.source = address(adapter);
        direct.actionId = adapter.deriveActionId(direct);
        (bool directOk,) = address(adapter).call(abi.encodeCall(adapter.executeRegulatoryAction, (direct)));
        require(!directOk, "unrelated backing spend");

        adapter.executeRegulatoryReversal(_reversal(seize.actionId, TrustTypes.ReversalKind.RELEASE, 53));
        require(token.balanceOf(address(adapter)) == 0, "release exact backing");
        require(adapter.caseTerminal(seize.caseId), "release terminal");
    }

    function testExactCalldataAndNoncanonicalProfileReturnAreTyped() external {
        TrustTypes.ActionRequest memory trailingRequest = _request(TrustTypes.ActionKind.FREEZE, 54, 1 ether);
        bytes memory trailing =
            bytes.concat(abi.encodeCall(adapter.executeRegulatoryAction, (trailingRequest)), bytes32(uint256(1)));
        (bool trailingOk, bytes memory trailingResult) = address(adapter).call(trailing);
        require(!trailingOk && trailingResult.length == 0, "profile trailing calldata");

        compliance.setMode(MockERC3643Compliance.Mode.NONCANONICAL);
        TrustTypes.ActionRequest memory malformed = _request(TrustTypes.ActionKind.CONFISCATE, 55, 1 ether);
        (bool malformedOk, bytes memory malformedResult) =
            address(adapter).call(abi.encodeCall(adapter.executeRegulatoryAction, (malformed)));
        require(!malformedOk, "profile noncanonical returndata");
        require(_selector(malformedResult) == TrustOperationalFailure.selector, "profile typed failure");
        require(adapter.actionRecord(malformed.actionId).lifecycle == TrustTypes.Lifecycle.NONE, "profile stutter");

        compliance.setMode(MockERC3643Compliance.Mode.ALLOW);
        identity.setMode(MockERC3643IdentityRegistry.Mode.LONG_RETURN);
        TrustTypes.ActionRequest memory longReturn = _request(TrustTypes.ActionKind.CONFISCATE, 56, 1 ether);
        (bool longOk, bytes memory longResult) =
            address(adapter).call(abi.encodeCall(adapter.executeRegulatoryAction, (longReturn)));
        require(!longOk && _selector(longResult) == TrustOperationalFailure.selector, "profile long typed failure");
    }

    function testProfileFreezeTargetIsUnboundedAndUnderlyingFloorSaturates() external {
        TrustTypes.ActionRequest memory freeze = _request(TrustTypes.ActionKind.FREEZE, 57, SUPPLY + 1 ether);
        adapter.executeRegulatoryAction(freeze);
        require(token.getFrozenTokens(address(this)) == SUPPLY, "underlying saturated floor");
        require(adapter.actionRecord(freeze.actionId).amount == SUPPLY + 1 ether, "unbounded target record");

        TrustTypes.ActionRequest memory seize = _request(TrustTypes.ActionKind.SEIZE, 58, 1 ether);
        adapter.executeRegulatoryAction(seize);
        require(token.getFrozenTokens(address(this)) == SUPPLY - 1 ether, "outbound resync");
        adapter.executeRegulatoryReversal(_reversal(seize.actionId, TrustTypes.ReversalKind.RELEASE, 59));
        require(token.getFrozenTokens(address(this)) == SUPPLY, "inbound resync");

        adapter.executeRegulatoryReversal(_reversal(freeze.actionId, TrustTypes.ReversalKind.UNFREEZE, 60));
        require(token.getFrozenTokens(address(this)) == 0, "prior target restore");
    }

    function _request(TrustTypes.ActionKind action, uint256 nonce, uint256 amount)
        internal
        view
        returns (TrustTypes.ActionRequest memory request)
    {
        address destination;
        address custodian_;
        bytes32 settlement;
        bytes32 proceeds;
        bytes32 entitlement;
        if (action == TrustTypes.ActionKind.SEIZE) {
            destination = address(adapter);
            custodian_ = address(adapter);
        } else if (action == TrustTypes.ActionKind.CONFISCATE || action == TrustTypes.ActionKind.LIQUIDATE) {
            destination = buyer;
        } else if (action == TrustTypes.ActionKind.RECOVER) {
            destination = recovered;
        }
        if (action == TrustTypes.ActionKind.LIQUIDATE) {
            settlement = keccak256(abi.encode("SETTLEMENT", nonce));
            proceeds = keccak256(abi.encode("PROCEEDS", nonce));
        }
        if (action == TrustTypes.ActionKind.RECOVER) {
            entitlement = keccak256(abi.encode("ENTITLEMENT", nonce));
        }

        request = TrustTypes.ActionRequest({
            domain: DOMAIN,
            actionId: bytes32(0),
            action: action,
            subject: address(this),
            source: address(this),
            destination: destination,
            custodian: custodian_,
            amount: amount,
            caseId: keccak256(abi.encode("PROFILE-CASE", nonce)),
            scopeHash: keccak256("PROFILE-SCOPE"),
            policyCommitment: governor.sealedBinding(),
            provenanceCommitment: keccak256(abi.encode("ORDER", nonce)),
            settlementCommitment: settlement,
            proceedsCommitment: proceeds,
            entitlementCommitment: entitlement,
            authorityRef: AUTHORITY_REF,
            authorityEpoch: 1,
            policyEpoch: 1,
            nonce: nonce,
            validAfter: 0,
            validBefore: type(uint48).max
        });
        request.actionId = adapter.deriveActionId(request);
    }

    function _reversal(bytes32 actionId, TrustTypes.ReversalKind reversal, uint256 nonce)
        internal
        view
        returns (TrustTypes.ReversalRequest memory request)
    {
        request = TrustTypes.ReversalRequest({
            domain: DOMAIN,
            reversalId: bytes32(0),
            actionId: actionId,
            reversal: reversal,
            authorityRef: AUTHORITY_REF,
            authorityEpoch: 1,
            nonce: nonce,
            validAfter: 0,
            validBefore: type(uint48).max
        });
        request.reversalId = adapter.deriveReversalId(request);
    }

    function _selector(bytes memory data) internal pure returns (bytes4 result) {
        if (data.length < 4) return bytes4(0);
        assembly ("memory-safe") {
            result := mload(add(data, 0x20))
        }
    }
}
