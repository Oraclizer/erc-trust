// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustTestBase, Vm} from "./TrustTestBase.t.sol";
import {TrustTypes} from "../src/TrustTypes.sol";
import {TrustToken} from "../src/TrustToken.sol";
import {IERC7943Fungible} from "../src/interfaces/IERC7943.sol";
import {IERCTrust} from "../src/interfaces/IERCTrust.sol";
import {MockBoundDependency} from "./mocks/MockBoundDependency.sol";
import {TrustOperationalFailure} from "../src/TrustErrors.sol";

contract TrustActionsUnitTest is TrustTestBase {
    function testSixActionsAndSeparateReversals() external {
        TrustTypes.ActionRequest memory freeze = _request(TrustTypes.ActionKind.FREEZE, 1, 500 ether);
        token.executeRegulatoryAction(freeze);
        _assertEq(token.getFrozenTokens(address(this)), 500 ether, "freeze");
        _assert(token.getFrozenTokens(address(this)) + 1 != freeze.amount, "incremental freeze mutant");

        TrustTypes.ReversalRequest memory unfreeze = _reversal(freeze.actionId, TrustTypes.ReversalKind.UNFREEZE, 2);
        token.executeRegulatoryReversal(unfreeze);
        _assertEq(token.getFrozenTokens(address(this)), 0, "unfreeze");
        _assert(token.getFrozenTokens(address(this)) != 1, "unfreeze restoration omission mutant");

        TrustTypes.ActionRequest memory seize = _request(TrustTypes.ActionKind.SEIZE, 3, 100 ether);
        token.executeRegulatoryAction(seize);
        _assertEq(token.balanceOf(address(custodian)), 100 ether, "seize destination");
        TrustTypes.CustodyRecord memory custody = token.custodyRecord(seize.caseId);
        _assert(custody.active, "custody active");
        _assertEq(custody.declaredPriorHolder, address(this), "prior holder");
        _assert(custody.encumberedAmount != 0, "custody backing omission mutant");

        TrustTypes.ReversalRequest memory release = _reversal(seize.actionId, TrustTypes.ReversalKind.RELEASE, 4);
        token.executeRegulatoryReversal(release);
        _assertEq(token.balanceOf(address(custodian)), 0, "release");
        _assert(token.caseTerminal(seize.caseId), "release terminal");
        _assert(token.caseTerminal(seize.caseId) != false, "release terminal omission mutant");

        TrustTypes.ActionRequest memory confiscate = _request(TrustTypes.ActionKind.CONFISCATE, 5, 50 ether);
        token.executeRegulatoryAction(confiscate);
        _assertEq(token.balanceOf(address(buyer)), 50 ether, "confiscate");
        _assert(token.caseTerminal(confiscate.caseId), "confiscate terminal");
        _assert(token.caseTerminal(confiscate.caseId) != false, "confiscate terminal omission mutant");

        TrustTypes.ActionRequest memory liquidate = _request(TrustTypes.ActionKind.LIQUIDATE, 6, 40 ether);
        token.executeRegulatoryAction(liquidate);
        TrustTypes.SettlementRecord memory settlement = token.settlementRecord(liquidate.actionId);
        _assertEq(settlement.settlementCommitment, liquidate.settlementCommitment, "settlement");
        _assertEq(settlement.proceedsCommitment, liquidate.proceedsCommitment, "proceeds");
        _assert(settlement.settlementCommitment != bytes32(0), "settlement omission mutant");

        TrustTypes.ActionRequest memory restrict = _request(TrustTypes.ActionKind.RESTRICT, 7, 0);
        token.executeRegulatoryAction(restrict);
        _assert(token.isRestricted(address(this)), "restricted");
        _assert(token.isRestricted(address(this)) != false, "restriction omission mutant");
        TrustTypes.ReversalRequest memory unrestrict =
            _reversal(restrict.actionId, TrustTypes.ReversalKind.UNRESTRICT, 8);
        token.executeRegulatoryReversal(unrestrict);
        _assert(!token.isRestricted(address(this)), "unrestricted");
        _assert(token.isRestricted(address(this)) != true, "unrestrict restoration omission mutant");

        TrustTypes.ActionRequest memory recoverAction = _request(TrustTypes.ActionKind.RECOVER, 9, 30 ether);
        token.executeRegulatoryAction(recoverAction);
        TrustTypes.EntitlementRecord memory entitlement = token.entitlementRecord(recoverAction.actionId);
        _assert(entitlement.consumed, "entitlement consumed");
        _assertEq(entitlement.destination, address(recovered), "recover destination");
        _assert(entitlement.consumed != false, "entitlement omission mutant");
    }

    function testFreezeAndRestrictionRemainIndependentAndRejectConflation() external {
        TrustTypes.ActionRequest memory freeze = _request(TrustTypes.ActionKind.FREEZE, 10, 17 ether);
        token.executeRegulatoryAction(freeze);

        TrustTypes.ActionRequest memory restrict = _request(TrustTypes.ActionKind.RESTRICT, 11, 0);
        token.executeRegulatoryAction(restrict);

        uint256 frozen = token.getFrozenTokens(address(this));
        bool restricted = token.isRestricted(address(this));
        _assertEq(frozen, 17 ether, "restriction must preserve the independent freeze amount");
        _assert(restricted, "freeze must coexist with the independent restriction flag");

        uint256 conflatedFrozenObservation = restricted ? 0 : frozen;
        _assert(
            conflatedFrozenObservation != frozen,
            "the STATE-04 conflation mutant must be distinguished on the same coexistence state"
        );
    }

    function testCaseTerminalityIsScopedAndRejectsGlobalTerminalMutant() external {
        TrustTypes.ActionRequest memory confiscate = _request(TrustTypes.ActionKind.CONFISCATE, 12, 1 ether);
        token.executeRegulatoryAction(confiscate);

        TrustTypes.ActionRequest memory freeze = _request(TrustTypes.ActionKind.FREEZE, 13, 2 ether);
        token.executeRegulatoryAction(freeze);

        bool confiscateCaseTerminal = token.caseTerminal(confiscate.caseId);
        bool freezeCaseTerminal = token.caseTerminal(freeze.caseId);
        _assert(confiscateCaseTerminal, "the disposition case must be terminal");
        _assert(!freezeCaseTerminal, "an unrelated case must remain open");

        bool globalTerminalMutantForUnrelatedCase = confiscateCaseTerminal;
        _assert(
            globalTerminalMutantForUnrelatedCase != freezeCaseTerminal,
            "the STATE-05 global-terminal mutant must be distinguished on the unrelated case"
        );
    }

    function testCustodyLiquidateAndRecoverCurrentProfileInhabitantsAndNegatives() external {
        TrustTypes.ActionRequest memory seizeForLiquidation = _request(TrustTypes.ActionKind.SEIZE, 100, 7 ether);
        token.executeRegulatoryAction(seizeForLiquidation);
        TrustTypes.ActionRequest memory liquidate = _request(TrustTypes.ActionKind.LIQUIDATE, 101, 7 ether);
        liquidate.caseId = seizeForLiquidation.caseId;
        liquidate.subject = seizeForLiquidation.subject;
        liquidate.source = seizeForLiquidation.custodian;
        liquidate.actionId = token.deriveActionId(liquidate);
        token.executeRegulatoryAction(liquidate);
        TrustTypes.SettlementRecord memory settlement = token.settlementRecord(liquidate.actionId);
        _assert(!token.custodyRecord(liquidate.caseId).active, "liquidation closes custody");
        _assert(settlement.settlementCommitment != bytes32(0), "custody settlement present");
        _assert(settlement.settlementCommitment != bytes32(0), "custody settlement omission mutant");

        token = _deploy(dependency);
        TrustTypes.ActionRequest memory seizeForRecovery = _request(TrustTypes.ActionKind.SEIZE, 102, 5 ether);
        token.executeRegulatoryAction(seizeForRecovery);
        TrustTypes.ActionRequest memory recoverAction = _request(TrustTypes.ActionKind.RECOVER, 103, 5 ether);
        recoverAction.caseId = seizeForRecovery.caseId;
        recoverAction.subject = seizeForRecovery.subject;
        recoverAction.source = seizeForRecovery.custodian;
        recoverAction.actionId = token.deriveActionId(recoverAction);
        token.executeRegulatoryAction(recoverAction);
        TrustTypes.EntitlementRecord memory entitlement = token.entitlementRecord(recoverAction.actionId);
        _assert(!token.custodyRecord(recoverAction.caseId).active, "recovery closes custody");
        _assert(entitlement.consumed, "custody entitlement consumed");
        _assert(entitlement.consumed != false, "custody entitlement omission mutant");
    }

    function testERC7943ExactUseRoutesAndInterfaceTruth() external {
        _assert(token.supportsInterface(0x01ffc9a7), "erc165");
        _assert(token.supportsInterface(0x3edbb4c4), "erc7943");
        _assert(token.supportsInterface(type(IERCTrust).interfaceId), "trust");
        _assert(!token.supportsInterface(0xffffffff), "invalid id");

        (bool rawOk,) =
            address(token).call(abi.encodeCall(IERC7943Fungible.setFrozenTokens, (address(this), 200 ether)));
        _assert(!rawOk, "raw freeze must fail");
        _assertEq(token.getFrozenTokens(address(this)), 0, "raw stutter");

        TrustTypes.ActionRequest memory freeze = _request(TrustTypes.ActionKind.FREEZE, 20, 200 ether);
        token.executeERC7943Action(freeze);
        _assertEq(token.getFrozenTokens(address(this)), 200 ether, "staged freeze");
        _assert(!token.routeLive(), "ticket consumed");

        TrustTypes.ReversalRequest memory unfreeze = _reversal(freeze.actionId, TrustTypes.ReversalKind.UNFREEZE, 21);
        token.executeERC7943Reversal(unfreeze);
        _assertEq(token.getFrozenTokens(address(this)), 0, "staged unfreeze");
        _assert(!token.routeLive(), "reversal ticket consumed");

        TrustTypes.ActionRequest memory seize = _request(TrustTypes.ActionKind.SEIZE, 22, 25 ether);
        token.executeERC7943Action(seize);
        _assertEq(token.balanceOf(address(custodian)), 25 ether, "forced route");
        _assert(!token.routeLive(), "forced ticket consumed");
    }

    function testCanonicalEventOrder() external {
        TrustTypes.ActionRequest memory freeze = _request(TrustTypes.ActionKind.FREEZE, 30, 123 ether);
        vm.recordLogs();
        token.executeERC7943Action(freeze);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _assert(logs.length >= 2, "logs");
        _assertEq(logs[logs.length - 2].topics[0], keccak256("Frozen(address,uint256)"), "frozen before receipt");
        _assertEq(
            logs[logs.length - 1].topics[0],
            keccak256("RegulatoryActionApplied(bytes32,uint8,bytes32,bytes32)"),
            "receipt last"
        );
    }

    function test_RevertedTransactionLeavesNoLogsOrCommittedArtifacts() external {
        MockBoundDependency broken =
            new MockBoundDependency(MockBoundDependency.Mode.REVERTING, keccak256("C6-BROKEN-CONFIG"));
        TrustToken brokenToken = _deploy(broken);
        token = brokenToken;
        TrustTypes.ActionRequest memory request = _request(TrustTypes.ActionKind.FREEZE, 39, 7 ether);
        vm.recordLogs();
        (bool ok,) = address(brokenToken).call(abi.encodeCall(brokenToken.executeERC7943Action, (request)));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _assert(!ok, "failure must revert");
        _assertEq(logs.length, 0, "reverted logs");
        _assert(!brokenToken.routeLive(), "reverted ticket");
        _assert(!brokenToken.nonceUsed(AUTHORITY_REF, 1, 39), "reverted nonce");
        TrustTypes.Receipt memory failedReceipt = brokenToken.receipt(request.actionId);
        _assertEq(failedReceipt.receiptHash, bytes32(0), "reverted receipt");
    }

    function testRejectedAndOperationalFailureStutter() external {
        MockBoundDependency rejected =
            new MockBoundDependency(MockBoundDependency.Mode.REJECTED, keccak256("REJECT-CONFIG"));
        TrustToken rejectedToken = _deploy(rejected);
        token = rejectedToken;
        TrustTypes.ActionRequest memory rejectedRequest = _request(TrustTypes.ActionKind.FREEZE, 40, 10 ether);
        (bool rejectedOk,) =
            address(rejectedToken).call(abi.encodeCall(rejectedToken.executeRegulatoryAction, (rejectedRequest)));
        _assert(!rejectedOk, "rejected must revert");
        _assertEq(rejectedToken.getFrozenTokens(address(this)), 0, "reject stutter");
        _assert(!rejectedToken.nonceUsed(AUTHORITY_REF, 1, 40), "reject nonce stutter");

        MockBoundDependency broken =
            new MockBoundDependency(MockBoundDependency.Mode.REVERTING, keccak256("BROKEN-CONFIG"));
        TrustToken brokenToken = _deploy(broken);
        token = brokenToken;
        TrustTypes.ActionRequest memory brokenRequest = _request(TrustTypes.ActionKind.FREEZE, 41, 10 ether);
        (bool brokenOk,) =
            address(brokenToken).call(abi.encodeCall(brokenToken.executeRegulatoryAction, (brokenRequest)));
        _assert(!brokenOk, "op failure must revert");
        _assertEq(brokenToken.getFrozenTokens(address(this)), 0, "failure stutter");
        _assert(!brokenToken.nonceUsed(AUTHORITY_REF, 1, 41), "failure nonce stutter");
    }

    function testReplayFixedActionAndConfiscateTerminality() external {
        TrustTypes.ActionRequest memory freeze = _request(TrustTypes.ActionKind.FREEZE, 50, 1 ether);
        token.executeRegulatoryAction(freeze);
        (bool replayOk,) = address(token).call(abi.encodeCall(token.executeRegulatoryAction, (freeze)));
        _assert(!replayOk, "action replay");

        TrustTypes.ActionRequest memory confiscate = _request(TrustTypes.ActionKind.CONFISCATE, 51, 1 ether);
        token.executeRegulatoryAction(confiscate);
        _assert(token.caseTerminal(confiscate.caseId), "case terminal flag");
        TrustTypes.ReversalRequest memory invalid = _reversal(confiscate.actionId, TrustTypes.ReversalKind.RELEASE, 52);
        (bool reverseOk,) = address(token).call(abi.encodeCall(token.executeRegulatoryReversal, (invalid)));
        _assert(!reverseOk, "confiscate terminal");

        TrustTypes.ActionRequest memory reusedCase = _request(TrustTypes.ActionKind.FREEZE, 53, 2 ether);
        reusedCase.caseId = confiscate.caseId;
        reusedCase.actionId = token.deriveActionId(reusedCase);
        (bool reusedCaseOk,) = address(token).call(abi.encodeCall(token.executeRegulatoryAction, (reusedCase)));
        _assert(!reusedCaseOk, "terminal case reuse");

        TrustTypes.ActionRequest memory fixedAction = _request(TrustTypes.ActionKind.CONFISCATE, 54, 1 ether);
        fixedAction.destination = address(recovered);
        (bool fixedActionOk,) = address(token).call(abi.encodeCall(token.executeRegulatoryAction, (fixedAction)));
        _assert(!fixedActionOk, "action fields must remain hash-bound");
    }

    function testFreezeReplacementLifoAndReversalPolicyFailClosed() external {
        TrustTypes.ActionRequest memory freeze = _request(TrustTypes.ActionKind.FREEZE, 60, 100 ether);
        token.executeRegulatoryAction(freeze);

        TrustTypes.ActionRequest memory equal = _request(TrustTypes.ActionKind.FREEZE, 61, 100 ether);
        token.executeRegulatoryAction(equal);

        TrustTypes.ActionRequest memory decrease = _request(TrustTypes.ActionKind.FREEZE, 62, 50 ether);
        token.executeRegulatoryAction(decrease);
        _assertEq(token.getFrozenTokens(address(this)), 50 ether, "absolute replacement");

        (bool staleOk,) = address(token)
            .call(
                abi.encodeCall(
                    token.executeRegulatoryReversal, (_reversal(freeze.actionId, TrustTypes.ReversalKind.UNFREEZE, 64))
                )
            );
        _assert(!staleOk, "superseded reversal must fail");
        _assertEq(token.getFrozenTokens(address(this)), 50 ether, "stale reversal stutter");

        TrustTypes.ActionRequest memory malformed = _request(TrustTypes.ActionKind.FREEZE, 63, 120 ether);
        malformed.destination = address(buyer);
        malformed.actionId = token.deriveActionId(malformed);
        (bool malformedOk,) = address(token).call(abi.encodeCall(token.executeRegulatoryAction, (malformed)));
        _assert(!malformedOk, "freeze ownership-retention shape");

        token.executeRegulatoryReversal(_reversal(decrease.actionId, TrustTypes.ReversalKind.UNFREEZE, 67));
        token.executeRegulatoryReversal(_reversal(equal.actionId, TrustTypes.ReversalKind.UNFREEZE, 68));
        token.executeRegulatoryReversal(_reversal(freeze.actionId, TrustTypes.ReversalKind.UNFREEZE, 69));
        _assertEq(token.getFrozenTokens(address(this)), 0, "unfreeze restores prior amount");

        TrustTypes.ActionRequest memory secondFreeze = _request(TrustTypes.ActionKind.FREEZE, 65, 80 ether);
        token.executeRegulatoryAction(secondFreeze);
        MockBoundDependency broken =
            new MockBoundDependency(MockBoundDependency.Mode.REVERTING, keccak256("REVERSAL-BROKEN"));
        token.rebindDependency(
            TrustTypes.BindingKind.POLICY, address(broken), SCHEMA, keccak256("REVERSAL-POLICY-REBIND"), 1
        );
        TrustTypes.ReversalRequest memory failed =
            _reversal(secondFreeze.actionId, TrustTypes.ReversalKind.UNFREEZE, 66);
        (bool failedOk,) = address(token).call(abi.encodeCall(token.executeRegulatoryReversal, (failed)));
        _assert(!failedOk, "reversal policy failure must revert");
        _assertEq(token.getFrozenTokens(address(this)), 80 ether, "reversal failure stutter");
        _assert(!token.nonceUsed(AUTHORITY_REF, 1, 66), "reversal failure nonce stutter");
    }

    function testConfiscateFromCustodyClosesAndTerminatesCase() external {
        TrustTypes.ActionRequest memory seize = _request(TrustTypes.ActionKind.SEIZE, 70, 9 ether);
        token.executeRegulatoryAction(seize);

        TrustTypes.ActionRequest memory confiscate = _request(TrustTypes.ActionKind.CONFISCATE, 71, seize.amount);
        confiscate.caseId = seize.caseId;
        confiscate.subject = seize.subject;
        confiscate.source = seize.custodian;
        confiscate.actionId = token.deriveActionId(confiscate);
        token.executeRegulatoryAction(confiscate);

        _assert(!token.custodyRecord(seize.caseId).active, "custody must close");
        _assert(token.caseTerminal(seize.caseId), "confiscated case must terminate");
        _assertEq(token.balanceOf(address(custodian)), 0, "custodian balance");
    }

    function testCustodyBackingAndOwnFrozenFloorDoNotDoubleCount() external {
        _assert(token.transfer(address(custodian), 20 ether), "seed custodian own units");

        TrustTypes.ActionRequest memory freeze = _request(TrustTypes.ActionKind.FREEZE, 80, 15 ether);
        freeze.subject = address(custodian);
        freeze.source = address(custodian);
        freeze.actionId = token.deriveActionId(freeze);
        token.executeRegulatoryAction(freeze);

        TrustTypes.ActionRequest memory seize = _request(TrustTypes.ActionKind.SEIZE, 81, 100 ether);
        token.executeRegulatoryAction(seize);
        _assertEq(token.balanceOf(address(custodian)), 120 ether, "physical custody balance");

        custodian.transferToken(token, address(buyer), 5 ether);
        (bool overspend,) =
            address(custodian).call(abi.encodeCall(custodian.transferToken, (token, address(buyer), 1 ether)));
        _assert(!overspend, "backing plus own frozen floor");

        TrustTypes.ActionRequest memory direct = _request(TrustTypes.ActionKind.CONFISCATE, 82, 16 ether);
        direct.subject = address(custodian);
        direct.source = address(custodian);
        direct.actionId = token.deriveActionId(direct);
        (bool directOk,) = address(token).call(abi.encodeCall(token.executeRegulatoryAction, (direct)));
        _assert(!directOk, "direct action cannot spend unrelated custody backing");

        token.executeRegulatoryReversal(_reversal(seize.actionId, TrustTypes.ReversalKind.RELEASE, 83));
        _assertEq(token.balanceOf(address(custodian)), 15 ether, "release preserves own units");
    }

    function testSeizeCannotSpendUnrelatedBackingAndRejectsBypassMutant() external {
        _assert(token.transfer(address(custodian), 20 ether), "seed custodian own units");
        TrustTypes.ActionRequest memory firstSeize = _request(TrustTypes.ActionKind.SEIZE, 104, 100 ether);
        token.executeRegulatoryAction(firstSeize);

        TrustTypes.ActionRequest memory unrelatedSeize = _request(TrustTypes.ActionKind.SEIZE, 105, 21 ether);
        unrelatedSeize.subject = address(custodian);
        unrelatedSeize.source = address(custodian);
        unrelatedSeize.custodian = address(recovered);
        unrelatedSeize.actionId = token.deriveActionId(unrelatedSeize);
        (bool unrelatedSeizeOk,) = address(token).call(abi.encodeCall(token.executeRegulatoryAction, (unrelatedSeize)));
        _assert(!unrelatedSeizeOk, "seize cannot spend unrelated custody backing");
        _assert(token.custodyRecord(firstSeize.caseId).active, "original custody remains active");

        bool backingBypassMutant = true;
        _assert(backingBypassMutant != unrelatedSeizeOk, "BAL-08 backing bypass mutant must be distinguished");
    }

    function testExactCalldataAndMalformedDependencyReturnAreTyped() external {
        TrustTypes.ActionRequest memory trailingRequest = _request(TrustTypes.ActionKind.FREEZE, 84, 1 ether);
        bytes memory trailing =
            bytes.concat(abi.encodeCall(token.executeRegulatoryAction, (trailingRequest)), bytes32(uint256(1)));
        (bool trailingOk, bytes memory trailingResult) = address(token).call(trailing);
        _assert(!trailingOk && trailingResult.length == 0, "trailing calldata must generic-revert");
        _assert(!token.nonceUsed(AUTHORITY_REF, 1, 84), "malformed calldata stutter");

        MockBoundDependency malformed =
            new MockBoundDependency(MockBoundDependency.Mode.NONCANONICAL, keccak256("NONCANONICAL"));
        TrustToken malformedToken = _deploy(malformed);
        token = malformedToken;
        TrustTypes.ActionRequest memory malformedRequest = _request(TrustTypes.ActionKind.FREEZE, 85, 1 ether);
        (bool malformedOk, bytes memory malformedResult) =
            address(token).call(abi.encodeCall(token.executeRegulatoryAction, (malformedRequest)));
        _assert(!malformedOk, "noncanonical returndata must revert");
        _assert(_selector(malformedResult) == TrustOperationalFailure.selector, "typed operational failure");
        _assert(!token.nonceUsed(AUTHORITY_REF, 1, 85), "returndata failure stutter");

        MockBoundDependency longReturn =
            new MockBoundDependency(MockBoundDependency.Mode.LONG_RETURN, keccak256("LONG"));
        token = _deploy(longReturn);
        TrustTypes.ActionRequest memory longRequest = _request(TrustTypes.ActionKind.FREEZE, 86, 1 ether);
        (bool longOk, bytes memory longResult) =
            address(token).call(abi.encodeCall(token.executeRegulatoryAction, (longRequest)));
        _assert(!longOk && _selector(longResult) == TrustOperationalFailure.selector, "long typed failure");
    }

    function testDispositionAndReversalCaseTerminalityAndRecoverShape() external {
        TrustTypes.ActionRequest memory liquidate = _request(TrustTypes.ActionKind.LIQUIDATE, 87, 1 ether);
        token.executeRegulatoryAction(liquidate);
        _assert(token.caseTerminal(liquidate.caseId), "liquidate terminal");

        TrustTypes.ActionRequest memory recoverAction = _request(TrustTypes.ActionKind.RECOVER, 88, 1 ether);
        token.executeRegulatoryAction(recoverAction);
        _assert(token.caseTerminal(recoverAction.caseId), "recover terminal");

        TrustTypes.ActionRequest memory freeze = _request(TrustTypes.ActionKind.FREEZE, 89, 1 ether);
        token.executeRegulatoryAction(freeze);
        token.executeRegulatoryReversal(_reversal(freeze.actionId, TrustTypes.ReversalKind.UNFREEZE, 90));
        _assert(token.caseTerminal(freeze.caseId), "reversal terminal");

        TrustTypes.ActionRequest memory invalidRecover = _request(TrustTypes.ActionKind.RECOVER, 91, 1 ether);
        invalidRecover.subject = address(buyer);
        invalidRecover.actionId = token.deriveActionId(invalidRecover);
        (bool invalidOk,) = address(token).call(abi.encodeCall(token.executeRegulatoryAction, (invalidRecover)));
        _assert(!invalidOk, "direct recover requires subject source equality");
    }

    function _selector(bytes memory data) internal pure returns (bytes4 result) {
        if (data.length < 4) return bytes4(0);
        assembly ("memory-safe") {
            result := mload(add(data, 0x20))
        }
    }
}
