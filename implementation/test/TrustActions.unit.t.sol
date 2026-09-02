// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustTestBase, Vm} from "./TrustTestBase.t.sol";
import {TrustToken} from "../src/TrustToken.sol";
import {IERCTrustKernel, IERCTrustNativeRoute, TrustKernelTypes} from "../src/generated/IERCTrustKernel.sol";
import {IERC7943Fungible} from "../src/interfaces/IERC7943.sol";
import {MockBoundDependency} from "./mocks/MockBoundDependency.sol";

contract TrustActionsUnitTest is TrustTestBase {
    bytes32 internal constant ACTION_APPLIED_TOPIC =
        keccak256("RegulatoryActionApplied(bytes32,uint8,bytes32,bytes32)");
    bytes32 internal constant REVERSAL_APPLIED_TOPIC =
        keccak256("RegulatoryReversalApplied(bytes32,uint8,bytes32,bytes32)");
    bytes32 internal constant DEPENDENCY_CHANGED_TOPIC =
        keccak256("TrustDependencyChanged(uint8,bytes32,bytes32,bytes32,uint64)");

    // ------------------------------------------------------------------
    // Six actions, three reversals, receipts, and case records
    // ------------------------------------------------------------------

    function testSixActionsAndThreeReversalsWithReceipts() external {
        TrustKernelTypes.ActionRequest memory freeze = _request(TrustKernelTypes.ActionKind.FREEZE, 1, 500 ether);
        _checkActionReceipt(freeze, token.executeRegulatoryAction(freeze));
        _assertEq(token.getFrozenTokens(address(this)), 500 ether, "freeze");
        _checkCase(
            freeze.caseId, TrustKernelTypes.CasePhase.OPEN, TrustKernelTypes.CaseFamily.FREEZE, freeze.actionId, 1
        );

        TrustKernelTypes.ReversalRequest memory unfreeze =
            _reversal(freeze.actionId, TrustKernelTypes.ReversalKind.UNFREEZE, 2);
        _checkReversalReceipt(unfreeze, token.executeRegulatoryReversal(unfreeze), address(this), address(this));
        _assertEq(token.getFrozenTokens(address(this)), 0, "unfreeze");
        _checkCase(
            freeze.caseId, TrustKernelTypes.CasePhase.TERMINAL, TrustKernelTypes.CaseFamily.FREEZE, bytes32(0), 2
        );
        _assert(
            token.actionRecord(freeze.actionId).lifecycle == TrustKernelTypes.Lifecycle.REVERSED, "reversed lifecycle"
        );

        TrustKernelTypes.ActionRequest memory seize = _request(TrustKernelTypes.ActionKind.SEIZE, 3, 100 ether);
        _checkActionReceipt(seize, token.executeRegulatoryAction(seize));
        _assertEq(token.balanceOf(address(custodian)), 100 ether, "seize destination");
        _checkCase(
            seize.caseId, TrustKernelTypes.CasePhase.OPEN, TrustKernelTypes.CaseFamily.CUSTODY, seize.actionId, 1
        );

        TrustKernelTypes.ReversalRequest memory release =
            _reversal(seize.actionId, TrustKernelTypes.ReversalKind.RELEASE, 4);
        _checkReversalReceipt(release, token.executeRegulatoryReversal(release), address(custodian), address(this));
        _assertEq(token.balanceOf(address(custodian)), 0, "release");
        _checkCase(
            seize.caseId, TrustKernelTypes.CasePhase.TERMINAL, TrustKernelTypes.CaseFamily.CUSTODY, bytes32(0), 2
        );

        TrustKernelTypes.ActionRequest memory confiscate = _request(TrustKernelTypes.ActionKind.CONFISCATE, 5, 50 ether);
        _checkActionReceipt(confiscate, token.executeRegulatoryAction(confiscate));
        _assertEq(token.balanceOf(address(buyer)), 50 ether, "confiscate");
        _checkCase(
            confiscate.caseId,
            TrustKernelTypes.CasePhase.TERMINAL,
            TrustKernelTypes.CaseFamily.DISPOSITION,
            bytes32(0),
            1
        );

        TrustKernelTypes.ActionRequest memory liquidate = _request(TrustKernelTypes.ActionKind.LIQUIDATE, 6, 40 ether);
        _checkActionReceipt(liquidate, token.executeRegulatoryAction(liquidate));
        _assertEq(
            token.receipt(liquidate.actionId).externalCommitment,
            keccak256(abi.encode(liquidate.settlementCommitment, liquidate.proceedsCommitment)),
            "liquidate external commitment"
        );
        _assertEq(token.balanceOf(address(buyer)), 90 ether, "liquidate proceeds destination");

        TrustKernelTypes.ActionRequest memory restrict = _request(TrustKernelTypes.ActionKind.RESTRICT, 7, 0);
        _checkActionReceipt(restrict, token.executeRegulatoryAction(restrict));
        _assert(!token.canSend(address(this)) && !token.canReceive(address(this)), "restricted");
        _checkCase(
            restrict.caseId, TrustKernelTypes.CasePhase.OPEN, TrustKernelTypes.CaseFamily.RESTRICT, restrict.actionId, 1
        );

        TrustKernelTypes.ReversalRequest memory unrestrict =
            _reversal(restrict.actionId, TrustKernelTypes.ReversalKind.UNRESTRICT, 8);
        _checkReversalReceipt(unrestrict, token.executeRegulatoryReversal(unrestrict), address(this), address(this));
        _assert(token.canSend(address(this)), "unrestricted");
        _checkCase(
            restrict.caseId, TrustKernelTypes.CasePhase.TERMINAL, TrustKernelTypes.CaseFamily.RESTRICT, bytes32(0), 2
        );

        TrustKernelTypes.ActionRequest memory recoverAction = _request(TrustKernelTypes.ActionKind.RECOVER, 9, 30 ether);
        _checkActionReceipt(recoverAction, token.executeRegulatoryAction(recoverAction));
        _assertEq(token.balanceOf(address(recovered)), 30 ether, "recover destination");
        _assertEq(
            token.receipt(recoverAction.actionId).externalCommitment,
            recoverAction.entitlementCommitment,
            "recover external commitment"
        );

        TrustKernelTypes.ActionRequest memory reusedEntitlement =
            _request(TrustKernelTypes.ActionKind.RECOVER, 10, 1 ether);
        reusedEntitlement.entitlementCommitment = recoverAction.entitlementCommitment;
        reusedEntitlement.actionId = token.deriveActionId(reusedEntitlement);
        _expectInvalid(
            abi.encodeCall(token.executeRegulatoryAction, (reusedEntitlement)), 9, "entitlement consumed once"
        );
    }

    function testReceiptBindsCanonicalCommandHashEvidenceAndFinalEvent() external {
        TrustKernelTypes.ActionRequest memory freeze = _request(TrustKernelTypes.ActionKind.FREEZE, 11, 7 ether);
        vm.recordLogs();
        bytes32 returned = token.executeRegulatoryAction(freeze);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        Vm.Log memory last = logs[logs.length - 1];
        _assertEq(last.topics[0], ACTION_APPLIED_TOPIC, "final action event");
        _assertEq(last.topics[1], freeze.actionId, "event actionId");
        _assertEq(last.topics[2], bytes32(uint256(uint8(freeze.action))), "event action kind");
        _assertEq(last.topics[3], freeze.caseId, "event caseId");
        _assertEq(abi.decode(last.data, (bytes32)), returned, "event receipt hash");

        TrustKernelTypes.ActionRecord memory record = token.actionRecord(freeze.actionId);
        _assertEq(
            record.commandHash, _recomputeCommandHash(address(token), freeze), "raw calldata hash equals ABI encoding"
        );
        TrustKernelTypes.Receipt memory r = token.receipt(freeze.actionId);
        _assertEq(
            r.assessmentEvidence, keccak256(abi.encode(keccak256("CONFIG-V1"), record.commandHash)), "policy evidence"
        );
        _assertEq(record.evidenceHash, r.assessmentEvidence, "record evidence equals receipt evidence");
        _assertEq(r.subject, address(this), "receipt subject");
        _assertEq(r.authorityRef, AUTHORITY_REF, "receipt authority");
        _assertEq(r.dependencyRoot, freeze.dependencyRoot, "receipt root");
        _assertEq(r.provenanceCommitment, freeze.provenanceCommitment, "receipt provenance");
        _assertEq(r.parentCommandId, bytes32(0), "action has no parent");
        _assert(r.receiptKind == TrustKernelTypes.ReceiptKind.ACTION, "action receipt kind");

        TrustKernelTypes.ReversalRequest memory unfreeze =
            _reversal(freeze.actionId, TrustKernelTypes.ReversalKind.UNFREEZE, 12);
        vm.recordLogs();
        bytes32 reversalReceipt = token.executeRegulatoryReversal(unfreeze);
        logs = vm.getRecordedLogs();
        last = logs[logs.length - 1];
        _assertEq(last.topics[0], REVERSAL_APPLIED_TOPIC, "final reversal event");
        _assertEq(last.topics[1], unfreeze.reversalId, "event reversalId");
        _assertEq(last.topics[2], bytes32(uint256(uint8(unfreeze.reversal))), "event reversal kind");
        _assertEq(last.topics[3], freeze.actionId, "event parent actionId");
        _assertEq(abi.decode(last.data, (bytes32)), reversalReceipt, "event reversal receipt hash");
        TrustKernelTypes.Receipt memory rr = token.receipt(unfreeze.reversalId);
        _assert(rr.receiptKind == TrustKernelTypes.ReceiptKind.REVERSAL, "reversal receipt kind");
        _assertEq(rr.parentCommandId, freeze.actionId, "reversal parent");
        _assertEq(rr.provenanceCommitment, unfreeze.provenanceCommitment, "reversal provenance");
        _assertEq(rr.externalCommitment, bytes32(0), "reversal external commitment is zero");
        _assertEq(rr.amount, freeze.amount, "reversal amount");

        // Domain separation between the two receipt kinds: the same fields under the other tag differ.
        TrustKernelTypes.Receipt memory retagged = rr;
        retagged.receiptKind = TrustKernelTypes.ReceiptKind.ACTION;
        _assert(_recomputeReceiptHash(retagged) != reversalReceipt, "receipt kind tag separates domains");
    }

    // ------------------------------------------------------------------
    // Dependency root, epoch, and stale-command rejection
    // ------------------------------------------------------------------

    function testDependencyRootFormulaAndInitialEvents() external {
        vm.recordLogs();
        TrustToken fresh = _deploy(dependency);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32[4] memory bindings;
        (bytes32 root, uint64 epoch) = fresh.dependencyState();
        uint256 seen;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter != address(fresh) || logs[i].topics[0] != DEPENDENCY_CHANGED_TOPIC) continue;
            uint256 kind = uint256(logs[i].topics[1]);
            _assertEq(logs[i].topics[2], bytes32(0), "initial previous binding");
            bindings[kind] = logs[i].topics[3];
            (bytes32 eventRoot, uint64 eventEpoch) = abi.decode(logs[i].data, (bytes32, uint64));
            _assertEq(eventRoot, root, "initial event root");
            _assertEq(eventEpoch, 1, "initial event epoch");
            seen += 1;
        }
        _assertEq(seen, 4, "four initial binding events");
        _assertEq(epoch, 1, "initial epoch");
        _assertEq(
            root, _recomputeDependencyRoot(bindings[0], bindings[1], bindings[2], bindings[3]), "ordered tagged root"
        );
        for (uint8 kind = 0; kind < 4; ++kind) {
            bytes32 expected = keccak256(
                abi.encode(
                    DOMAIN,
                    kind,
                    address(dependency),
                    address(dependency).codehash,
                    keccak256("CONFIG-V1"),
                    SCHEMA,
                    uint64(1)
                )
            );
            _assertEq(bindings[kind], expected, "binding hash formula");
        }
        _assertEq(fresh.trustProfile().manifestHash, root, "manifest hash is the dependency root");
    }

    function testEveryDependencyRebindMakesEarlierCommandsStale() external {
        for (uint8 kind = 0; kind < 4; ++kind) {
            (bytes32 rootBefore, uint64 epochBefore) = token.dependencyState();
            TrustKernelTypes.ActionRequest memory stale =
                _request(TrustKernelTypes.ActionKind.CONFISCATE, 20 + kind, 1 ether);
            MockBoundDependency replacement =
                new MockBoundDependency(MockBoundDependency.Mode.APPLICABLE, keccak256(abi.encode("CONFIG", kind)));
            vm.recordLogs();
            token.rebindDependency(
                TrustKernelTypes.BindingKind(kind),
                address(replacement),
                SCHEMA,
                keccak256(abi.encode("GOVERNANCE", kind)),
                uint256(kind) + 1
            );
            Vm.Log[] memory logs = vm.getRecordedLogs();
            Vm.Log memory changed = logs[logs.length - 1];
            (bytes32 rootAfter, uint64 epochAfter) = token.dependencyState();
            _assertEq(changed.topics[0], DEPENDENCY_CHANGED_TOPIC, "rebind event");
            _assertEq(uint256(changed.topics[1]), kind, "event kind");
            (bytes32 eventRoot, uint64 eventEpoch) = abi.decode(changed.data, (bytes32, uint64));
            _assertEq(eventRoot, rootAfter, "event root");
            _assertEq(eventEpoch, epochAfter, "event epoch");
            _assertEq(epochAfter, epochBefore + 1, "epoch increments by exactly one");
            _assert(rootAfter != rootBefore, "root changes on every rebind");
            _assertEq(
                changed.topics[3],
                keccak256(
                    abi.encode(
                        DOMAIN,
                        kind,
                        address(replacement),
                        address(replacement).codehash,
                        keccak256(abi.encode("CONFIG", kind)),
                        SCHEMA,
                        uint64(2)
                    )
                ),
                "new per-kind binding"
            );

            _expectInvalid(abi.encodeCall(token.executeRegulatoryAction, (stale)), 5, "stale root and epoch");
            TrustKernelTypes.ActionRequest memory fresh =
                _request(TrustKernelTypes.ActionKind.CONFISCATE, 30 + kind, 1 ether);
            token.executeRegulatoryAction(fresh);
            _assertEq(token.receipt(fresh.actionId).dependencyRoot, rootAfter, "receipt binds the new root");
        }
    }

    function testRootAndEpochAreCheckedIndependently() external {
        TrustKernelTypes.ActionRequest memory wrongRoot = _request(TrustKernelTypes.ActionKind.FREEZE, 40, 1 ether);
        wrongRoot.dependencyRoot = bytes32(uint256(wrongRoot.dependencyRoot) ^ 1);
        wrongRoot.actionId = token.deriveActionId(wrongRoot);
        _expectInvalid(abi.encodeCall(token.executeRegulatoryAction, (wrongRoot)), 5, "wrong root with current epoch");

        TrustKernelTypes.ActionRequest memory wrongEpoch = _request(TrustKernelTypes.ActionKind.FREEZE, 41, 1 ether);
        wrongEpoch.dependencyEpoch = 2;
        wrongEpoch.actionId = token.deriveActionId(wrongEpoch);
        _expectInvalid(abi.encodeCall(token.executeRegulatoryAction, (wrongEpoch)), 5, "wrong epoch with current root");

        TrustKernelTypes.ActionRequest memory freeze = _request(TrustKernelTypes.ActionKind.FREEZE, 42, 1 ether);
        token.executeRegulatoryAction(freeze);
        TrustKernelTypes.ReversalRequest memory staleReversal =
            _reversal(freeze.actionId, TrustKernelTypes.ReversalKind.UNFREEZE, 43);
        staleReversal.dependencyRoot = bytes32(uint256(staleReversal.dependencyRoot) ^ 1);
        staleReversal.reversalId = token.deriveReversalId(staleReversal);
        _expectInvalid(abi.encodeCall(token.executeRegulatoryReversal, (staleReversal)), 5, "reversal checks the root");
    }

    // ------------------------------------------------------------------
    // Replay, nonce, authority
    // ------------------------------------------------------------------

    function testReplayNonceAndAuthorityRotation() external {
        TrustKernelTypes.ActionRequest memory freeze = _request(TrustKernelTypes.ActionKind.FREEZE, 50, 1 ether);
        token.executeRegulatoryAction(freeze);
        (bool ok, bytes memory result) = _call(abi.encodeCall(token.executeRegulatoryAction, (freeze)));
        _assert(!ok && _selector(result) == IERCTrustKernel.TrustReplay.selector, "action replay");
        _assertEq(_wordAt(result, 0), freeze.actionId, "replay key is the actionId");

        TrustKernelTypes.ActionRequest memory sameNonce = _request(TrustKernelTypes.ActionKind.CONFISCATE, 50, 1 ether);
        (ok, result) = _call(abi.encodeCall(token.executeRegulatoryAction, (sameNonce)));
        _assert(!ok && _selector(result) == IERCTrustKernel.TrustReplay.selector, "nonce replay");
        _assertEq(
            _wordAt(result, 0),
            keccak256(abi.encode(DOMAIN, AUTHORITY_REF, uint64(1), uint256(50))),
            "replay key is the nonce key"
        );

        TrustKernelTypes.ActionRequest memory malformed = _request(TrustKernelTypes.ActionKind.CONFISCATE, 51, 1 ether);
        malformed.custodian = address(buyer);
        malformed.actionId = token.deriveActionId(malformed);
        _expectInvalid(abi.encodeCall(token.executeRegulatoryAction, (malformed)), 6, "rejected shape");
        token.executeRegulatoryAction(_request(TrustKernelTypes.ActionKind.CONFISCATE, 51, 1 ether));

        (ok, result) = address(custodian)
            .call(
                abi.encodeCall(
                    custodian.executeAction, (token, _request(TrustKernelTypes.ActionKind.CONFISCATE, 52, 1 ether))
                )
            );
        _assert(!ok && _selector(result) == IERCTrustKernel.TrustUnauthorized.selector, "caller must be the authority");

        TrustKernelTypes.ActionRequest memory beforeRotation =
            _request(TrustKernelTypes.ActionKind.CONFISCATE, 53, 1 ether);
        token.configureAuthority(AUTHORITY_REF, address(this), true, keccak256("ROTATE"), 1);
        _expectInvalid(abi.encodeCall(token.executeRegulatoryAction, (beforeRotation)), 4, "authority epoch rotated");
        TrustKernelTypes.ActionRequest memory afterRotation =
            _request(TrustKernelTypes.ActionKind.CONFISCATE, 53, 1 ether);
        afterRotation.authorityEpoch = 2;
        afterRotation.actionId = token.deriveActionId(afterRotation);
        token.executeRegulatoryAction(afterRotation);

        token.configureAuthority(AUTHORITY_REF, address(this), false, keccak256("DEACTIVATE"), 2);
        TrustKernelTypes.ActionRequest memory inactive = _request(TrustKernelTypes.ActionKind.CONFISCATE, 54, 1 ether);
        inactive.authorityEpoch = 3;
        inactive.actionId = token.deriveActionId(inactive);
        _expectSelector(
            abi.encodeCall(token.executeRegulatoryAction, (inactive)),
            IERCTrustKernel.TrustUnauthorized.selector,
            "inactive authority"
        );
    }

    // ------------------------------------------------------------------
    // Case transition table
    // ------------------------------------------------------------------

    /// @dev The candidate 2 defect: a direct CONFISCATE against an open FREEZE case made the case terminal
    ///      and the UNFREEZE still passed. Kernel version 2 rejects the disposition (CT-14) and rejects every
    ///      command on a terminal case (CT-15).
    function testDispositionOnOpenOverlayCaseIsRejectedAndTerminalCasesRejectReversals() external {
        TrustKernelTypes.ActionRequest memory freeze = _request(TrustKernelTypes.ActionKind.FREEZE, 60, 5 ether);
        token.executeRegulatoryAction(freeze);
        TrustKernelTypes.ActionRequest memory confiscate = _request(TrustKernelTypes.ActionKind.CONFISCATE, 61, 1 ether);
        confiscate.caseId = freeze.caseId;
        confiscate.actionId = token.deriveActionId(confiscate);
        _expectInvalid(
            abi.encodeCall(token.executeRegulatoryAction, (confiscate)), 10, "CT-14 disposition on open overlay case"
        );
        _assertEq(token.getFrozenTokens(address(this)), 5 ether, "overlay intact");
        _checkCase(
            freeze.caseId, TrustKernelTypes.CasePhase.OPEN, TrustKernelTypes.CaseFamily.FREEZE, freeze.actionId, 1
        );

        TrustKernelTypes.ReversalRequest memory unfreeze =
            _reversal(freeze.actionId, TrustKernelTypes.ReversalKind.UNFREEZE, 62);
        token.executeRegulatoryReversal(unfreeze);
        TrustKernelTypes.ReversalRequest memory again =
            _reversal(freeze.actionId, TrustKernelTypes.ReversalKind.UNFREEZE, 63);
        _expectTerminal(
            abi.encodeCall(token.executeRegulatoryReversal, (again)), freeze.caseId, "CT-15 reversal on terminal case"
        );
        TrustKernelTypes.ActionRequest memory reopen = _request(TrustKernelTypes.ActionKind.FREEZE, 64, 9 ether);
        reopen.caseId = freeze.caseId;
        reopen.actionId = token.deriveActionId(reopen);
        _expectTerminal(
            abi.encodeCall(token.executeRegulatoryAction, (reopen)), freeze.caseId, "CT-15 action on terminal case"
        );

        TrustKernelTypes.ActionRequest memory seize = _request(TrustKernelTypes.ActionKind.SEIZE, 65, 9 ether);
        token.executeRegulatoryAction(seize);
        TrustKernelTypes.ActionRequest memory disposition =
            _custodyDisposition(TrustKernelTypes.ActionKind.CONFISCATE, seize, 66);
        token.executeRegulatoryAction(disposition);
        _checkCase(
            seize.caseId, TrustKernelTypes.CasePhase.TERMINAL, TrustKernelTypes.CaseFamily.CUSTODY, bytes32(0), 2
        );
        _assert(
            token.actionRecord(seize.actionId).lifecycle == TrustKernelTypes.Lifecycle.APPLIED, "seize stays applied"
        );
        TrustKernelTypes.ReversalRequest memory release =
            _reversal(seize.actionId, TrustKernelTypes.ReversalKind.RELEASE, 67);
        _expectTerminal(
            abi.encodeCall(token.executeRegulatoryReversal, (release)),
            seize.caseId,
            "terminal guard before custody check"
        );
        _assertEq(token.balanceOf(address(custodian)), 0, "no release after disposition");
    }

    function testOverlayCaseConflictsAndFamilies() external {
        _assert(token.transfer(address(buyer), 5 ether), "seed buyer");
        TrustKernelTypes.ActionRequest memory freezeX = _request(TrustKernelTypes.ActionKind.FREEZE, 70, 10 ether);
        token.executeRegulatoryAction(freezeX);

        TrustKernelTypes.ActionRequest memory freezeY = _request(TrustKernelTypes.ActionKind.FREEZE, 71, 20 ether);
        _expectInvalid(
            abi.encodeCall(token.executeRegulatoryAction, (freezeY)), 10, "CT-3 second freeze case on one subject"
        );

        TrustKernelTypes.ActionRequest memory restrictInX = _request(TrustKernelTypes.ActionKind.RESTRICT, 72, 0);
        restrictInX.caseId = freezeX.caseId;
        restrictInX.actionId = token.deriveActionId(restrictInX);
        _expectInvalid(
            abi.encodeCall(token.executeRegulatoryAction, (restrictInX)), 10, "CT-14 non-family command in freeze case"
        );

        TrustKernelTypes.ActionRequest memory seizeInX = _request(TrustKernelTypes.ActionKind.SEIZE, 73, 1 ether);
        seizeInX.caseId = freezeX.caseId;
        seizeInX.actionId = token.deriveActionId(seizeInX);
        _expectInvalid(abi.encodeCall(token.executeRegulatoryAction, (seizeInX)), 10, "CT-14 seize in freeze case");

        TrustKernelTypes.ActionRequest memory restrictZ = _request(TrustKernelTypes.ActionKind.RESTRICT, 74, 0);
        token.executeRegulatoryAction(restrictZ);
        _assertEq(token.getFrozenTokens(address(this)), 10 ether, "freeze and restriction coexist across cases");
        _assert(!token.canSend(address(this)), "restriction live");

        TrustKernelTypes.ActionRequest memory restrictW = _request(TrustKernelTypes.ActionKind.RESTRICT, 75, 0);
        _expectInvalid(
            abi.encodeCall(token.executeRegulatoryAction, (restrictW)), 10, "CT-7 second restrict case on one subject"
        );

        TrustKernelTypes.ActionRequest memory restrictAgainZ = _request(TrustKernelTypes.ActionKind.RESTRICT, 76, 0);
        restrictAgainZ.caseId = restrictZ.caseId;
        restrictAgainZ.actionId = token.deriveActionId(restrictAgainZ);
        _expectInvalid(abi.encodeCall(token.executeRegulatoryAction, (restrictAgainZ)), 13, "CT-6 no state change");

        TrustKernelTypes.ActionRequest memory freezeInZ = _request(TrustKernelTypes.ActionKind.FREEZE, 77, 30 ether);
        freezeInZ.caseId = restrictZ.caseId;
        freezeInZ.actionId = token.deriveActionId(freezeInZ);
        _expectInvalid(abi.encodeCall(token.executeRegulatoryAction, (freezeInZ)), 10, "CT-14 freeze in restrict case");

        // A different subject may open its own FREEZE case; heads are per subject.
        TrustKernelTypes.ActionRequest memory freezeBuyer = _request(TrustKernelTypes.ActionKind.FREEZE, 78, 2 ether);
        freezeBuyer.subject = address(buyer);
        freezeBuyer.source = address(buyer);
        freezeBuyer.actionId = token.deriveActionId(freezeBuyer);
        token.executeRegulatoryAction(freezeBuyer);
        _assertEq(token.getFrozenTokens(address(buyer)), 2 ether, "independent subject");
    }

    function testFreezeAmendmentChainReopensAfterPop() external {
        TrustKernelTypes.ActionRequest memory first = _request(TrustKernelTypes.ActionKind.FREEZE, 80, 10 ether);
        token.executeRegulatoryAction(first);
        TrustKernelTypes.ActionRequest memory second = _request(TrustKernelTypes.ActionKind.FREEZE, 81, 20 ether);
        second.caseId = first.caseId;
        second.actionId = token.deriveActionId(second);
        token.executeRegulatoryAction(second);
        _assertEq(token.getFrozenTokens(address(this)), 20 ether, "CT-2 amendment raises the target");
        _checkCase(
            first.caseId, TrustKernelTypes.CasePhase.OPEN, TrustKernelTypes.CaseFamily.FREEZE, second.actionId, 2
        );
        _assertEq(token.actionRecord(second.actionId).priorAmount, 10 ether, "amendment records the prior target");

        TrustKernelTypes.ActionRequest memory lower = _request(TrustKernelTypes.ActionKind.FREEZE, 82, 15 ether);
        lower.caseId = first.caseId;
        lower.actionId = token.deriveActionId(lower);
        _expectInvalid(abi.encodeCall(token.executeRegulatoryAction, (lower)), 12, "amendment must strictly raise");
        TrustKernelTypes.ActionRequest memory equal = _request(TrustKernelTypes.ActionKind.FREEZE, 83, 20 ether);
        equal.caseId = first.caseId;
        equal.actionId = token.deriveActionId(equal);
        _expectInvalid(abi.encodeCall(token.executeRegulatoryAction, (equal)), 12, "equal target rejected");

        TrustKernelTypes.ReversalRequest memory staleHead =
            _reversal(first.actionId, TrustKernelTypes.ReversalKind.UNFREEZE, 84);
        _expectInvalid(abi.encodeCall(token.executeRegulatoryReversal, (staleHead)), 11, "only the live head reverses");

        token.executeRegulatoryReversal(_reversal(second.actionId, TrustKernelTypes.ReversalKind.UNFREEZE, 85));
        _assertEq(token.getFrozenTokens(address(this)), 10 ether, "pop restores the parent target");
        _checkCase(first.caseId, TrustKernelTypes.CasePhase.OPEN, TrustKernelTypes.CaseFamily.FREEZE, first.actionId, 3);
        TrustKernelTypes.ReversalRequest memory twice =
            _reversal(second.actionId, TrustKernelTypes.ReversalKind.UNFREEZE, 86);
        _expectInvalid(abi.encodeCall(token.executeRegulatoryReversal, (twice)), 11, "reversed action is not the head");

        token.executeRegulatoryReversal(_reversal(first.actionId, TrustKernelTypes.ReversalKind.UNFREEZE, 87));
        _assertEq(token.getFrozenTokens(address(this)), 0, "chain fully popped");
        _checkCase(first.caseId, TrustKernelTypes.CasePhase.TERMINAL, TrustKernelTypes.CaseFamily.FREEZE, bytes32(0), 4);
        TrustKernelTypes.ActionRequest memory next = _request(TrustKernelTypes.ActionKind.FREEZE, 88, 1 ether);
        token.executeRegulatoryAction(next);
        _assertEq(token.getFrozenTokens(address(this)), 1 ether, "a new case opens after the chain closed");
    }

    function testCustodyLifecycleAndDispositions() external {
        TrustKernelTypes.ActionRequest memory seize = _request(TrustKernelTypes.ActionKind.SEIZE, 90, 100 ether);
        token.executeRegulatoryAction(seize);
        TrustKernelTypes.ActionRequest memory secondSeize = _request(TrustKernelTypes.ActionKind.SEIZE, 91, 1 ether);
        secondSeize.caseId = seize.caseId;
        secondSeize.actionId = token.deriveActionId(secondSeize);
        _expectInvalid(
            abi.encodeCall(token.executeRegulatoryAction, (secondSeize)), 8, "CT-10 second seize in custody case"
        );

        TrustKernelTypes.ActionRequest memory wrongAmount =
            _custodyDisposition(TrustKernelTypes.ActionKind.CONFISCATE, seize, 92);
        wrongAmount.amount = 99 ether;
        wrongAmount.actionId = token.deriveActionId(wrongAmount);
        _expectInvalid(
            abi.encodeCall(token.executeRegulatoryAction, (wrongAmount)), 8, "CT-12 partial custody disposition"
        );
        TrustKernelTypes.ActionRequest memory wrongSource =
            _custodyDisposition(TrustKernelTypes.ActionKind.CONFISCATE, seize, 93);
        wrongSource.source = address(this);
        wrongSource.actionId = token.deriveActionId(wrongSource);
        _expectInvalid(
            abi.encodeCall(token.executeRegulatoryAction, (wrongSource)), 8, "CT-12 source must be the custodian"
        );

        token.executeRegulatoryReversal(_reversal(seize.actionId, TrustKernelTypes.ReversalKind.RELEASE, 94));
        _assertEq(token.balanceOf(address(custodian)), 0, "CT-11 release returns the encumbered amount");
        _checkCase(
            seize.caseId, TrustKernelTypes.CasePhase.TERMINAL, TrustKernelTypes.CaseFamily.CUSTODY, bytes32(0), 2
        );

        TrustKernelTypes.ActionRequest memory seizeForLiquidation =
            _request(TrustKernelTypes.ActionKind.SEIZE, 95, 7 ether);
        token.executeRegulatoryAction(seizeForLiquidation);
        TrustKernelTypes.ActionRequest memory liquidate =
            _custodyDisposition(TrustKernelTypes.ActionKind.LIQUIDATE, seizeForLiquidation, 96);
        _checkActionReceipt(liquidate, token.executeRegulatoryAction(liquidate));
        _assertEq(token.balanceOf(address(buyer)), 7 ether, "liquidation proceeds destination");
        _checkCase(
            seizeForLiquidation.caseId,
            TrustKernelTypes.CasePhase.TERMINAL,
            TrustKernelTypes.CaseFamily.CUSTODY,
            bytes32(0),
            2
        );

        TrustKernelTypes.ActionRequest memory seizeForRecovery =
            _request(TrustKernelTypes.ActionKind.SEIZE, 97, 5 ether);
        token.executeRegulatoryAction(seizeForRecovery);
        TrustKernelTypes.ActionRequest memory recoverAction =
            _custodyDisposition(TrustKernelTypes.ActionKind.RECOVER, seizeForRecovery, 98);
        _checkActionReceipt(recoverAction, token.executeRegulatoryAction(recoverAction));
        _assertEq(token.balanceOf(address(recovered)), 5 ether, "recovery destination");
        _assertEq(token.balanceOf(address(custodian)), 0, "custody fully consumed");
    }

    function testDirectDispositionsAndShapeRules() external {
        TrustKernelTypes.ActionRequest memory liquidate = _request(TrustKernelTypes.ActionKind.LIQUIDATE, 100, 1 ether);
        token.executeRegulatoryAction(liquidate);
        _checkCase(
            liquidate.caseId,
            TrustKernelTypes.CasePhase.TERMINAL,
            TrustKernelTypes.CaseFamily.DISPOSITION,
            bytes32(0),
            1
        );

        TrustKernelTypes.ActionRequest memory wrongSubject = _request(TrustKernelTypes.ActionKind.RECOVER, 101, 1 ether);
        wrongSubject.subject = address(buyer);
        wrongSubject.actionId = token.deriveActionId(wrongSubject);
        _expectInvalid(
            abi.encodeCall(token.executeRegulatoryAction, (wrongSubject)), 6, "CT-13 direct requires source == subject"
        );

        TrustKernelTypes.ActionRequest memory noSettlement =
            _request(TrustKernelTypes.ActionKind.LIQUIDATE, 102, 1 ether);
        noSettlement.settlementCommitment = bytes32(0);
        noSettlement.actionId = token.deriveActionId(noSettlement);
        _expectInvalid(abi.encodeCall(token.executeRegulatoryAction, (noSettlement)), 6, "liquidate needs settlement");

        TrustKernelTypes.ActionRequest memory strayCommitment =
            _request(TrustKernelTypes.ActionKind.CONFISCATE, 103, 1 ether);
        strayCommitment.settlementCommitment = keccak256("stray");
        strayCommitment.actionId = token.deriveActionId(strayCommitment);
        _expectInvalid(
            abi.encodeCall(token.executeRegulatoryAction, (strayCommitment)), 6, "unused commitment must be zero"
        );

        TrustKernelTypes.ActionRequest memory freezeWithDestination =
            _request(TrustKernelTypes.ActionKind.FREEZE, 104, 1 ether);
        freezeWithDestination.destination = address(buyer);
        freezeWithDestination.actionId = token.deriveActionId(freezeWithDestination);
        _expectInvalid(
            abi.encodeCall(token.executeRegulatoryAction, (freezeWithDestination)), 6, "freeze retains ownership"
        );

        TrustKernelTypes.ActionRequest memory restrictWithAmount =
            _request(TrustKernelTypes.ActionKind.RESTRICT, 105, 1);
        _expectInvalid(
            abi.encodeCall(token.executeRegulatoryAction, (restrictWithAmount)), 6, "restrict amount must be zero"
        );

        TrustKernelTypes.ActionRequest memory seizeNoCustodian =
            _request(TrustKernelTypes.ActionKind.SEIZE, 106, 1 ether);
        seizeNoCustodian.custodian = address(0);
        seizeNoCustodian.actionId = token.deriveActionId(seizeNoCustodian);
        _expectInvalid(abi.encodeCall(token.executeRegulatoryAction, (seizeNoCustodian)), 6, "seize needs a custodian");

        TrustKernelTypes.ActionRequest memory wrongDomain = _request(TrustKernelTypes.ActionKind.FREEZE, 107, 1 ether);
        wrongDomain.domain = keccak256("ERC-TRUST/reference-v1");
        wrongDomain.actionId = token.deriveActionId(wrongDomain);
        _expectInvalid(abi.encodeCall(token.executeRegulatoryAction, (wrongDomain)), 1, "domain");

        TrustKernelTypes.ActionRequest memory wrongId = _request(TrustKernelTypes.ActionKind.FREEZE, 108, 1 ether);
        wrongId.actionId = bytes32(uint256(wrongId.actionId) ^ 1);
        _expectInvalid(abi.encodeCall(token.executeRegulatoryAction, (wrongId)), 2, "identifier");

        TrustKernelTypes.ActionRequest memory expired = _request(TrustKernelTypes.ActionKind.FREEZE, 109, 1 ether);
        expired.validBefore = 0;
        expired.actionId = token.deriveActionId(expired);
        _expectInvalid(abi.encodeCall(token.executeRegulatoryAction, (expired)), 3, "validity window");

        TrustKernelTypes.ActionRequest memory noProvenance = _request(TrustKernelTypes.ActionKind.FREEZE, 110, 1 ether);
        noProvenance.provenanceCommitment = bytes32(0);
        noProvenance.actionId = token.deriveActionId(noProvenance);
        _expectInvalid(abi.encodeCall(token.executeRegulatoryAction, (noProvenance)), 6, "provenance required");

        TrustKernelTypes.ActionRequest memory freeze = _request(TrustKernelTypes.ActionKind.FREEZE, 111, 1 ether);
        token.executeRegulatoryAction(freeze);
        TrustKernelTypes.ReversalRequest memory mispaired =
            _reversal(freeze.actionId, TrustKernelTypes.ReversalKind.RELEASE, 112);
        _expectInvalid(abi.encodeCall(token.executeRegulatoryReversal, (mispaired)), 7, "reversal pairing");
        TrustKernelTypes.ReversalRequest memory noReversalProvenance =
            _reversal(freeze.actionId, TrustKernelTypes.ReversalKind.UNFREEZE, 113);
        noReversalProvenance.provenanceCommitment = bytes32(0);
        noReversalProvenance.reversalId = token.deriveReversalId(noReversalProvenance);
        _expectInvalid(
            abi.encodeCall(token.executeRegulatoryReversal, (noReversalProvenance)), 6, "reversal provenance required"
        );
        TrustKernelTypes.ReversalRequest memory unknownAction =
            _reversal(keccak256("nope"), TrustKernelTypes.ReversalKind.UNFREEZE, 114);
        _expectInvalid(abi.encodeCall(token.executeRegulatoryReversal, (unknownAction)), 11, "unknown action");
    }

    // ------------------------------------------------------------------
    // ERC-7943 exact-use route
    // ------------------------------------------------------------------

    function testERC7943ExactUseRoutesAndRawClosure() external {
        _expectSelector(
            abi.encodeCall(IERC7943Fungible.setFrozenTokens, (address(this), 200 ether)),
            IERCTrustNativeRoute.TrustRouteMismatch.selector,
            "raw freeze"
        );
        _expectSelector(
            abi.encodeCall(IERC7943Fungible.forcedTransfer, (address(this), address(buyer), 1 ether)),
            IERCTrustNativeRoute.TrustRouteMismatch.selector,
            "raw forced transfer"
        );
        (bool actorOk,) = address(custodian).call(abi.encodeCall(custodian.rawFreeze, (token, address(this), 1 ether)));
        _assert(!actorOk, "raw freeze through another contract");
        _assertEq(token.getFrozenTokens(address(this)), 0, "raw stutter");

        TrustKernelTypes.ActionRequest memory freeze = _request(TrustKernelTypes.ActionKind.FREEZE, 120, 200 ether);
        bytes32 routed = token.executeERC7943Action(freeze);
        _assertEq(token.getFrozenTokens(address(this)), 200 ether, "staged freeze");
        _assert(!_routeLive(), "ticket consumed");
        _checkActionReceipt(freeze, routed);
        _assertEq(
            token.receipt(freeze.actionId).provenanceCommitment, freeze.provenanceCommitment, "route keeps commitments"
        );

        TrustKernelTypes.ReversalRequest memory unfreeze =
            _reversal(freeze.actionId, TrustKernelTypes.ReversalKind.UNFREEZE, 121);
        bytes32 routedReversal = token.executeERC7943Reversal(unfreeze);
        _assertEq(token.getFrozenTokens(address(this)), 0, "staged unfreeze");
        _assert(!_routeLive(), "reversal ticket consumed");
        _checkReversalReceipt(unfreeze, routedReversal, address(this), address(this));

        TrustKernelTypes.ActionRequest memory seize = _request(TrustKernelTypes.ActionKind.SEIZE, 122, 25 ether);
        _checkActionReceipt(seize, token.executeERC7943Action(seize));
        _assertEq(token.balanceOf(address(custodian)), 25 ether, "forced route");
        _assert(!_routeLive(), "forced ticket consumed");

        TrustKernelTypes.ActionRequest memory restrict = _request(TrustKernelTypes.ActionKind.RESTRICT, 123, 0);
        _expectInvalid(abi.encodeCall(token.executeERC7943Action, (restrict)), 6, "restrict has no sensitive selector");
        TrustKernelTypes.ReversalRequest memory release =
            _reversal(seize.actionId, TrustKernelTypes.ReversalKind.RELEASE, 124);
        _expectInvalid(abi.encodeCall(token.executeERC7943Reversal, (release)), 7, "release has no sensitive selector");
    }

    function testCanonicalEventOrderAndRevertedTransactionsLeaveNothing() external {
        TrustKernelTypes.ActionRequest memory freeze = _request(TrustKernelTypes.ActionKind.FREEZE, 130, 123 ether);
        vm.recordLogs();
        token.executeERC7943Action(freeze);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _assert(logs.length >= 2, "logs");
        _assertEq(logs[logs.length - 2].topics[0], keccak256("Frozen(address,uint256)"), "frozen before receipt");
        _assertEq(logs[logs.length - 1].topics[0], ACTION_APPLIED_TOPIC, "receipt last");

        MockBoundDependency broken = new MockBoundDependency(MockBoundDependency.Mode.REVERTING, keccak256("BROKEN"));
        token = _deploy(broken);
        TrustKernelTypes.ActionRequest memory request = _request(TrustKernelTypes.ActionKind.FREEZE, 131, 7 ether);
        vm.recordLogs();
        (bool ok, bytes memory result) = _call(abi.encodeCall(token.executeERC7943Action, (request)));
        logs = vm.getRecordedLogs();
        _assert(!ok && _selector(result) == IERCTrustKernel.TrustOperationalFailure.selector, "failure must revert");
        _assertEq(logs.length, 0, "reverted logs");
        _assert(!_routeLive(), "reverted ticket");
        _assertEq(token.receipt(request.actionId).receiptHash, bytes32(0), "reverted receipt");
        _assert(token.actionRecord(request.actionId).lifecycle == TrustKernelTypes.Lifecycle.NONE, "reverted record");
    }

    // ------------------------------------------------------------------
    // Outcome classes and reason registry
    // ------------------------------------------------------------------

    function testAssessmentOutcomesAndReasonClasses() external {
        MockBoundDependency applicable = dependency;
        MockBoundDependency rejected = new MockBoundDependency(MockBoundDependency.Mode.REJECTED, keccak256("REJECT"));

        token = _deployMixed(rejected, applicable, applicable, applicable);
        _expectRejected(
            abi.encodeCall(token.executeRegulatoryAction, (_request(TrustKernelTypes.ActionKind.FREEZE, 140, 1 ether))),
            100,
            "policy denied"
        );
        token = _deployMixed(applicable, rejected, applicable, applicable);
        token.executeRegulatoryAction(_request(TrustKernelTypes.ActionKind.FREEZE, 141, 1 ether));
        _expectRejected(
            abi.encodeCall(
                token.executeRegulatoryAction, (_request(TrustKernelTypes.ActionKind.CONFISCATE, 142, 1 ether))
            ),
            101,
            "identity denied"
        );
        token = _deployMixed(applicable, applicable, rejected, applicable);
        _expectRejected(
            abi.encodeCall(
                token.executeRegulatoryAction, (_request(TrustKernelTypes.ActionKind.LIQUIDATE, 143, 1 ether))
            ),
            102,
            "settlement denied"
        );
        token = _deployMixed(applicable, applicable, applicable, rejected);
        _expectRejected(
            abi.encodeCall(
                token.executeRegulatoryAction, (_request(TrustKernelTypes.ActionKind.RECOVER, 144, 1 ether))
            ),
            103,
            "entitlement denied"
        );
        _assertEq(token.getFrozenTokens(address(this)), 0, "rejection stutter");

        _expectOperationalFailure(MockBoundDependency.Mode.REVERTING, 202, "dependency revert");
        _expectOperationalFailure(MockBoundDependency.Mode.MALFORMED, 202, "short return");
        _expectOperationalFailure(MockBoundDependency.Mode.LONG_RETURN, 202, "long return");
        _expectOperationalFailure(MockBoundDependency.Mode.WRONG_ECHO, 203, "command echo mismatch");
        _expectOperationalFailure(MockBoundDependency.Mode.NONCANONICAL, 203, "outcome word above two");
        _expectOperationalFailure(MockBoundDependency.Mode.OPERATIONAL_FAILURE, 204, "dependency reported failure");

        token = _deploy(dependency);
        _assert(token.trustProfile().full, "full while bindings hold");
        dependency.setConfig(keccak256("DRIFT"));
        _assert(!token.trustProfile().full, "configuration drift clears full");
        (bool ok, bytes memory result) = _call(
            abi.encodeCall(token.executeRegulatoryAction, (_request(TrustKernelTypes.ActionKind.FREEZE, 145, 1 ether)))
        );
        _assert(!ok && _selector(result) == IERCTrustKernel.TrustOperationalFailure.selector, "drift fails closed");
        _assertEq(_reasonOf(result), 201, "configuration mismatch");
        (bytes32 root,) = token.dependencyState();
        root;
        dependency.setConfig(keccak256("CONFIG-V1"));
        _assert(token.trustProfile().full, "full restored with the bound configuration");
    }

    function testReversalAssessmentFailsClosedAfterPolicyRebind() external {
        TrustKernelTypes.ActionRequest memory freeze = _request(TrustKernelTypes.ActionKind.FREEZE, 147, 80 ether);
        token.executeRegulatoryAction(freeze);
        MockBoundDependency broken =
            new MockBoundDependency(MockBoundDependency.Mode.REVERTING, keccak256("REVERSAL-BROKEN"));
        token.rebindDependency(
            TrustKernelTypes.BindingKind.POLICY, address(broken), SCHEMA, keccak256("REVERSAL-POLICY-REBIND"), 7
        );
        TrustKernelTypes.ReversalRequest memory failed =
            _reversal(freeze.actionId, TrustKernelTypes.ReversalKind.UNFREEZE, 148);
        (bool ok, bytes memory result) = _call(abi.encodeCall(token.executeRegulatoryReversal, (failed)));
        _assert(!ok && _selector(result) == IERCTrustKernel.TrustOperationalFailure.selector, "reversal policy failure");
        _assertEq(_reasonOf(result), 202, "dependency call failed");
        _assertEq(token.getFrozenTokens(address(this)), 80 ether, "reversal failure stutter");
        _assert(token.actionRecord(freeze.actionId).lifecycle == TrustKernelTypes.Lifecycle.APPLIED, "still applied");

        token.rebindDependency(
            TrustKernelTypes.BindingKind.POLICY, address(dependency), SCHEMA, keccak256("REVERSAL-POLICY-RESTORE"), 8
        );
        token.executeRegulatoryReversal(_reversal(freeze.actionId, TrustKernelTypes.ReversalKind.UNFREEZE, 148));
        _assertEq(token.getFrozenTokens(address(this)), 0, "reversal succeeds under the restored policy");
    }

    function testTrustProfileDescriptorAndInterfaceIdentifiers() external view {
        TrustKernelTypes.ProfileDescriptor memory descriptor = token.trustProfile();
        _assertEq(descriptor.profileId, keccak256("ERC-TRUST/v2/native-full"), "profile id");
        _assert(descriptor.profileKind == TrustKernelTypes.ProfileKind.NATIVE_FULL, "profile kind");
        _assertEq(descriptor.standardVersion, 2, "standard version");
        _assertEq(descriptor.actionMask, 0x3f, "action mask");
        _assertEq(descriptor.reversalMask, 0x07, "reversal mask");
        _assertEq(descriptor.underlyingToken, address(0), "native endpoint has no underlying token");
        (bytes32 root, uint64 epoch) = token.dependencyState();
        _assertEq(descriptor.manifestHash, root, "manifest hash");
        _assertEq(epoch, 1, "epoch");
        _assert(descriptor.full && !descriptor.proxySupported, "flags");

        _assert(token.supportsInterface(0x01ffc9a7), "erc165");
        _assert(token.supportsInterface(0x3edbb4c4), "erc7943");
        _assert(token.supportsInterface(0x2b020308), "kernel identifier literal");
        _assert(token.supportsInterface(type(IERCTrustKernel).interfaceId), "kernel identifier");
        _assert(token.supportsInterface(0x5cd8d207), "native route identifier literal");
        _assert(token.supportsInterface(type(IERCTrustNativeRoute).interfaceId), "native route identifier");
        _assert(!token.supportsInterface(0xffffffff), "invalid id");
        _assert(!token.supportsInterface(0x15e0c235), "kernel version 1 identifier is gone");
    }

    // ------------------------------------------------------------------
    // Canonical calldata
    // ------------------------------------------------------------------

    function testNonCanonicalCalldataIsRejected() external {
        TrustKernelTypes.ActionRequest memory request = _request(TrustKernelTypes.ActionKind.FREEZE, 150, 1 ether);
        bytes memory trailing =
            bytes.concat(abi.encodeCall(token.executeRegulatoryAction, (request)), bytes32(uint256(1)));
        (bool trailingOk, bytes memory trailingResult) = _call(trailing);
        _assert(!trailingOk && trailingResult.length == 0, "trailing calldata must generic-revert");

        // Dirty high bits in the dependencyEpoch word, with the identifier derived over the dirty bytes so
        // that only the canonical-encoding check can reject the command.
        bytes memory dirty = abi.encodeCall(token.executeRegulatoryAction, (request));
        dirty[4 + 32 * 10] = 0x01;
        bytes32 dirtyId = _rawActionId(dirty);
        for (uint256 i = 0; i < 32; ++i) {
            dirty[4 + 32 + i] = dirtyId[i];
        }
        (bool dirtyOk,) = _call(dirty);
        _assert(!dirtyOk, "dirty narrow-integer word rejected");
        _assertEq(token.getFrozenTokens(address(this)), 0, "dirty stutter");

        bytes memory outOfRange = abi.encodeCall(token.executeRegulatoryAction, (request));
        outOfRange[4 + 32 * 2 + 31] = 0x06;
        bytes32 outOfRangeId = _rawActionId(outOfRange);
        for (uint256 i = 0; i < 32; ++i) {
            outOfRange[4 + 32 + i] = outOfRangeId[i];
        }
        (bool rangeOk,) = _call(outOfRange);
        _assert(!rangeOk, "enum out of range rejected");

        token.executeRegulatoryAction(request);
    }

    // ------------------------------------------------------------------
    // Balances, custody backing, and overlay saturation
    // ------------------------------------------------------------------

    function testCustodyBackingAndOwnFrozenFloorDoNotDoubleCount() external {
        _assert(token.transfer(address(custodian), 20 ether), "seed custodian own units");
        TrustKernelTypes.ActionRequest memory freeze = _request(TrustKernelTypes.ActionKind.FREEZE, 160, 15 ether);
        freeze.subject = address(custodian);
        freeze.source = address(custodian);
        freeze.actionId = token.deriveActionId(freeze);
        token.executeRegulatoryAction(freeze);

        TrustKernelTypes.ActionRequest memory seize = _request(TrustKernelTypes.ActionKind.SEIZE, 161, 100 ether);
        token.executeRegulatoryAction(seize);
        _assertEq(token.balanceOf(address(custodian)), 120 ether, "physical custody balance");

        custodian.transferToken(token, address(buyer), 5 ether);
        (bool overspend,) =
            address(custodian).call(abi.encodeCall(custodian.transferToken, (token, address(buyer), 1 ether)));
        _assert(!overspend, "backing plus own frozen floor");

        TrustKernelTypes.ActionRequest memory direct = _request(TrustKernelTypes.ActionKind.CONFISCATE, 162, 16 ether);
        direct.subject = address(custodian);
        direct.source = address(custodian);
        direct.actionId = token.deriveActionId(direct);
        _expectInvalid(
            abi.encodeCall(token.executeRegulatoryAction, (direct)), 8, "direct action cannot spend custody backing"
        );

        TrustKernelTypes.ActionRequest memory unrelatedSeize =
            _request(TrustKernelTypes.ActionKind.SEIZE, 163, 21 ether);
        unrelatedSeize.subject = address(custodian);
        unrelatedSeize.source = address(custodian);
        unrelatedSeize.custodian = address(recovered);
        unrelatedSeize.destination = address(recovered);
        unrelatedSeize.actionId = token.deriveActionId(unrelatedSeize);
        _expectInvalid(
            abi.encodeCall(token.executeRegulatoryAction, (unrelatedSeize)), 8, "seize cannot spend unrelated backing"
        );

        token.executeRegulatoryReversal(_reversal(seize.actionId, TrustKernelTypes.ReversalKind.RELEASE, 164));
        _assertEq(token.balanceOf(address(custodian)), 15 ether, "release preserves own units");
    }

    function testOverlayTargetSaturatesAfterCrossCaseDisposition() external {
        _assert(token.transfer(address(custodian), 50 ether), "seed subject");
        TrustKernelTypes.ActionRequest memory freeze = _request(TrustKernelTypes.ActionKind.FREEZE, 170, 40 ether);
        freeze.subject = address(custodian);
        freeze.source = address(custodian);
        freeze.actionId = token.deriveActionId(freeze);
        token.executeRegulatoryAction(freeze);

        TrustKernelTypes.ActionRequest memory confiscate =
            _request(TrustKernelTypes.ActionKind.CONFISCATE, 171, 30 ether);
        confiscate.subject = address(custodian);
        confiscate.source = address(custodian);
        confiscate.actionId = token.deriveActionId(confiscate);
        token.executeRegulatoryAction(confiscate);
        _assertEq(token.balanceOf(address(custodian)), 20 ether, "disposition in another case moves frozen units");
        _assertEq(token.getFrozenTokens(address(custodian)), 20 ether, "observed target saturates at the balance");
        _assert(!token.canTransfer(address(custodian), address(buyer), 1), "nothing ordinary remains");
        _checkCase(
            freeze.caseId, TrustKernelTypes.CasePhase.OPEN, TrustKernelTypes.CaseFamily.FREEZE, freeze.actionId, 1
        );

        TrustKernelTypes.ActionRequest memory raise = _request(TrustKernelTypes.ActionKind.FREEZE, 172, 45 ether);
        raise.subject = address(custodian);
        raise.source = address(custodian);
        raise.caseId = freeze.caseId;
        raise.actionId = token.deriveActionId(raise);
        token.executeRegulatoryAction(raise);
        _assertEq(token.actionRecord(raise.actionId).priorAmount, 40 ether, "amendment compares stored targets");

        token.executeRegulatoryReversal(_reversal(raise.actionId, TrustKernelTypes.ReversalKind.UNFREEZE, 173));
        token.executeRegulatoryReversal(_reversal(freeze.actionId, TrustKernelTypes.ReversalKind.UNFREEZE, 174));
        _assertEq(token.getFrozenTokens(address(custodian)), 0, "overlay cleared by its own case");
        _assert(token.canTransfer(address(custodian), address(buyer), 20 ether), "ordinary transfer restored");
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    function _checkActionReceipt(TrustKernelTypes.ActionRequest memory request, bytes32 returned) internal view {
        TrustKernelTypes.Receipt memory r = token.receipt(request.actionId);
        _assertEq(r.receiptHash, returned, "returned hash equals stored hash");
        _assertEq(_recomputeReceiptHash(r), returned, "indexer recomputation");
        _assert(r.receiptKind == TrustKernelTypes.ReceiptKind.ACTION, "action kind tag");
        _assertEq(r.commandId, request.actionId, "receipt command id");
        _assertEq(uint256(r.commandKind), uint256(uint8(request.action)), "receipt command kind");
        _assertEq(r.caseId, request.caseId, "receipt case");
        _assertEq(r.destination, request.destination, "receipt destination");
        TrustKernelTypes.ActionRecord memory record = token.actionRecord(request.actionId);
        _assertEq(record.receiptHash, returned, "record receipt hash");
        _assert(record.lifecycle == TrustKernelTypes.Lifecycle.APPLIED, "applied lifecycle");
        _assertEq(record.commandHash, _recomputeCommandHash(address(token), request), "record command hash");
    }

    function _checkReversalReceipt(
        TrustKernelTypes.ReversalRequest memory request,
        bytes32 returned,
        address source,
        address destination
    ) internal view {
        TrustKernelTypes.Receipt memory r = token.receipt(request.reversalId);
        _assertEq(r.receiptHash, returned, "reversal returned hash equals stored hash");
        _assertEq(_recomputeReceiptHash(r), returned, "reversal indexer recomputation");
        _assert(r.receiptKind == TrustKernelTypes.ReceiptKind.REVERSAL, "reversal kind tag");
        _assertEq(r.commandId, request.reversalId, "reversal command id");
        _assertEq(uint256(r.commandKind), uint256(uint8(request.reversal)), "reversal command kind");
        _assertEq(r.parentCommandId, request.actionId, "reversal parent");
        _assertEq(r.source, source, "reversal source");
        _assertEq(r.destination, destination, "reversal destination");
        _assertEq(r.externalCommitment, bytes32(0), "reversal external commitment");
    }

    function _checkCase(
        bytes32 caseId,
        TrustKernelTypes.CasePhase phase,
        TrustKernelTypes.CaseFamily family,
        bytes32 head,
        uint64 generation
    ) internal view {
        TrustKernelTypes.CaseRecord memory record = token.caseRecord(caseId);
        _assert(record.phase == phase, "case phase");
        _assert(record.family == family, "case family");
        _assertEq(record.headActionId, head, "case head");
        _assertEq(record.generation, generation, "case generation");
    }

    function _expectTerminal(bytes memory data, bytes32 caseId, string memory message) internal {
        (bool ok, bytes memory result) = _call(data);
        require(!ok, message);
        require(_selector(result) == IERCTrustKernel.TrustTerminal.selector, message);
        require(_wordAt(result, 0) == caseId, message);
    }

    function _expectRejected(bytes memory data, uint16 reason, string memory message) internal {
        (bool ok, bytes memory result) = _call(data);
        require(!ok, message);
        require(_selector(result) == IERCTrustKernel.TrustRejected.selector, message);
        require(_reasonOf(result) == reason, message);
    }

    function _expectOperationalFailure(MockBoundDependency.Mode mode, uint16 reason, string memory message) internal {
        MockBoundDependency broken = new MockBoundDependency(mode, keccak256(abi.encode("MODE", mode)));
        token = _deploy(broken);
        (bool ok, bytes memory result) = _call(
            abi.encodeCall(token.executeRegulatoryAction, (_request(TrustKernelTypes.ActionKind.FREEZE, 146, 1 ether)))
        );
        require(!ok, message);
        require(_selector(result) == IERCTrustKernel.TrustOperationalFailure.selector, message);
        require(_reasonOf(result) == reason, message);
        require(_wordAt(result, 2) != bytes32(0), "dependency reference carried");
        require(token.getFrozenTokens(address(this)) == 0, message);
    }

    function _deployMixed(
        MockBoundDependency policy,
        MockBoundDependency identity,
        MockBoundDependency settlement,
        MockBoundDependency entitlement
    ) internal returns (TrustToken deployed) {
        deployed = new TrustToken(
            "ERC-TRUST Reference",
            "TRUST",
            18,
            address(this),
            address(this),
            INITIAL_SUPPLY,
            AUTHORITY_REF,
            address(this),
            address(policy),
            address(identity),
            address(settlement),
            address(entitlement),
            SCHEMA
        );
    }

    /// @dev hashes.actionId recomputed over raw calldata words, mirroring the endpoint's calldatacopy.
    function _rawActionId(bytes memory data) internal view returns (bytes32) {
        bytes memory words = new bytes(640);
        for (uint256 i = 0; i < 640; ++i) {
            words[i] = data[4 + i];
        }
        for (uint256 i = 32; i < 64; ++i) {
            words[i] = 0;
        }
        return keccak256(bytes.concat(abi.encode(DOMAIN, address(token), block.chainid), words));
    }

    function _wordAt(bytes memory data, uint256 index) internal pure returns (bytes32 word) {
        require(data.length >= 4 + 32 * (index + 1), "short payload");
        assembly ("memory-safe") {
            word := mload(add(add(data, 0x24), mul(index, 0x20)))
        }
    }
}
