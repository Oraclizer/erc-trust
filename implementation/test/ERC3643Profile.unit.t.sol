// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {Vm} from "./TrustTestBase.t.sol";
import {IERCTrustKernel, TrustKernelTypes} from "../src/generated/IERCTrustKernel.sol";
import {ERC3643TrustAdapter} from "../src/profiles/ERC3643TrustAdapter.sol";
import {ProfileGovernor} from "../src/profiles/ProfileGovernor.sol";
import {ERC3643ProfileTypes} from "../src/profiles/ERC3643ProfileTypes.sol";
import {MockERC3643Token} from "./mocks/MockERC3643Token.sol";
import {MockERC3643IdentityRegistry, MockERC3643Compliance} from "./mocks/MockERC3643Dependencies.sol";

/// @dev The fixture surface every conformance fixture offers the tests: the owner handshake and the views.
interface IFixtureToken {
    function setExclusiveAgent(address agent) external;
    function transferOwnership(address nextOwner) external;
    function balanceOf(address account) external view returns (uint256);
    function getFrozenTokens(address account) external view returns (uint256);
    function isFrozen(address account) external view returns (bool);
}

/// @dev Forwards arbitrary calldata from an address that is neither the authority nor the adapter.
contract RawCaller {
    function relay(address target, bytes calldata data) external returns (bool ok, bytes memory result) {
        (ok, result) = target.call(data);
    }
}

/// @notice Behaviour shared by every ERC-3643 conformance fixture. Each concrete fixture test runs the
///         whole suite against its own underlying token.
abstract contract ERC3643ProfileTestBase {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    bytes32 internal constant DOMAIN = TrustKernelTypes.DOMAIN;
    bytes32 internal constant AUTHORITY_REF = keccak256("ERC3643-AUTHORITY");
    bytes32 internal constant PROFILE_ID = keccak256("ERC-TRUST/v2/erc3643-verified-full");
    bytes32 internal constant SEAL_DOMAIN = keccak256("ERC-TRUST/v2/erc3643-verified-full/seal");
    bytes32 internal constant IMPORT_TAG = keccak256("ERC-TRUST/v2/erc3643-verified-full/import");
    bytes32 internal constant ACTION_APPLIED_TOPIC =
        keccak256("RegulatoryActionApplied(bytes32,uint8,bytes32,bytes32)");
    bytes32 internal constant REVERSAL_APPLIED_TOPIC =
        keccak256("RegulatoryReversalApplied(bytes32,uint8,bytes32,bytes32)");
    bytes32 internal constant DEPENDENCY_CHANGED_TOPIC =
        keccak256("TrustDependencyChanged(uint8,bytes32,bytes32,bytes32,uint64)");
    bytes32 internal constant AUTHORITY_CHANGED_TOPIC = keccak256("TrustAuthorityChanged(bytes32,address,uint64,bool)");
    bytes32 internal constant STATE_IMPORTED_TOPIC =
        keccak256("RegulatoryStateImported(bytes32,bytes32,address,uint8,uint256,bool)");
    uint256 internal constant SUPPLY = 1_000_000 ether;

    MockERC3643IdentityRegistry internal identity;
    MockERC3643Compliance internal compliance;
    address internal token;
    ProfileGovernor internal governor;
    ERC3643TrustAdapter internal adapter;
    RawCaller internal stranger;
    address internal buyer = address(0xb0b);
    address internal recovered = address(0xbeef);
    address internal holder = address(0x401d);
    ERC3643ProfileTypes.ImportEntry[] internal noEntries;

    /// @dev Deploys the fixture token with this contract as owner and initial holder.
    function _newToken(uint256 supply) internal virtual returns (address);
    /// @dev Creates legacy upstream state for `account` before the seal, through the fixture's own means.
    function _seedLegacy(address account, uint256 balance, uint256 frozenAmount, bool restricted) internal virtual;

    function setUp() public virtual {
        identity = new MockERC3643IdentityRegistry();
        compliance = new MockERC3643Compliance();
        stranger = new RawCaller();
        identity.setVerified(address(this), true);
        identity.setVerified(buyer, true);
        identity.setVerified(recovered, true);
        identity.setVerified(holder, true);
        _freshUnit();
        _seal(noEntries);
    }

    // ------------------------------------------------------------------
    // Descriptor, bindings, activation
    // ------------------------------------------------------------------

    function testDescriptorDependencyStateAndInterfaceIdentifiers() external view {
        TrustKernelTypes.ProfileDescriptor memory descriptor = adapter.trustProfile();
        _assertEq(descriptor.profileId, PROFILE_ID, "profile id");
        _assertEq(descriptor.profileId, TrustKernelTypes.PROFILE_ERC3643_VERIFIED_FULL, "profile id constant");
        _assert(descriptor.profileKind == TrustKernelTypes.ProfileKind.VERIFIED_FULL, "profile kind");
        _assertEq(descriptor.standardVersion, 2, "standard version");
        _assertEq(descriptor.actionMask, 0x3f, "action mask");
        _assertEq(descriptor.reversalMask, 0x07, "reversal mask");
        _assertEq(descriptor.underlyingToken, token, "underlying token");
        _assertEq(descriptor.manifestHash, governor.sealedBinding(), "manifest hash is the sealed binding");
        _assert(descriptor.full && !descriptor.proxySupported, "flags");

        bytes32 manifestHash = keccak256(abi.encode(noEntries));
        _assertEq(governor.importManifestHash(), manifestHash, "empty manifest hash");
        _assertEq(governor.sealedBinding(), _sealedBinding(manifestHash), "sealed binding formula");
        (bytes32 root, uint64 epoch) = adapter.dependencyState();
        _assertEq(epoch, 1, "seal epoch");
        _assertEq(
            root, _expectedRoot(governor.sealedBinding()), "ordered tagged root with zero settlement and entitlement"
        );

        _assert(adapter.supportsInterface(0x01ffc9a7), "erc165");
        _assert(adapter.supportsInterface(0x2b020308), "kernel identifier literal");
        _assert(adapter.supportsInterface(type(IERCTrustKernel).interfaceId), "kernel identifier");
        _assert(!adapter.supportsInterface(0xffffffff), "invalid id");
        _assert(!adapter.supportsInterface(0xbcc2afa9), "kernel version 1 profile identifier is gone");
        _assert(!adapter.supportsInterface(0x5cd8d207), "native route identifier is not claimed");
    }

    function testActivationEmitsBindingsAuthorityAndImportCount() external {
        vm.recordLogs();
        _freshUnit();
        _seal(noEntries);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (bytes32 root, uint64 epoch) = adapter.dependencyState();
        bytes32 binding = governor.sealedBinding();
        uint256 dependencyEvents;
        bool authorityEvent;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter != address(adapter)) continue;
            if (logs[i].topics[0] == DEPENDENCY_CHANGED_TOPIC) {
                uint256 kind = uint256(logs[i].topics[1]);
                _assertEq(logs[i].topics[2], bytes32(0), "previous binding");
                _assertEq(logs[i].topics[3], _expectedBinding(kind, binding), "per-kind binding formula");
                (bytes32 eventRoot, uint64 eventEpoch) = abi.decode(logs[i].data, (bytes32, uint64));
                _assertEq(eventRoot, root, "event root");
                _assertEq(eventEpoch, epoch, "event epoch");
                dependencyEvents += 1;
            } else if (logs[i].topics[0] == AUTHORITY_CHANGED_TOPIC) {
                _assertEq(logs[i].topics[1], AUTHORITY_REF, "authority ref");
                _assertEq(address(uint160(uint256(logs[i].topics[2]))), address(this), "authority account");
                (uint64 authorityEpoch, bool active) = abi.decode(logs[i].data, (uint64, bool));
                _assert(authorityEpoch == 1 && active, "authority epoch one and active");
                authorityEvent = true;
            }
        }
        _assertEq(dependencyEvents, 4, "four binding events, two of them zero");
        _assert(authorityEvent, "authority declared at construction");
    }

    // ------------------------------------------------------------------
    // Six actions, three reversals, receipts
    // ------------------------------------------------------------------

    function testAllSixActionsAndReversals() external {
        TrustKernelTypes.ActionRequest memory freeze = _request(TrustKernelTypes.ActionKind.FREEZE, 1, 25 ether);
        _checkActionReceipt(freeze, adapter.executeRegulatoryAction(freeze));
        _assertEq(_frozen(address(this)), 25 ether, "freeze");
        _checkCase(
            freeze.caseId, TrustKernelTypes.CasePhase.OPEN, TrustKernelTypes.CaseFamily.FREEZE, freeze.actionId, 1
        );

        TrustKernelTypes.ActionRequest memory equalFreeze = _request(TrustKernelTypes.ActionKind.FREEZE, 90, 25 ether);
        equalFreeze.caseId = freeze.caseId;
        equalFreeze.actionId = adapter.deriveActionId(equalFreeze);
        _expectInvalid(abi.encodeCall(adapter.executeRegulatoryAction, (equalFreeze)), 12, "equal freeze must reject");
        _assertEq(_frozen(address(this)), 25 ether, "equal freeze stutter");
        _assert(adapter.actionRecord(equalFreeze.actionId).lifecycle == TrustKernelTypes.Lifecycle.NONE, "equal record");

        TrustKernelTypes.ActionRequest memory decrease = _request(TrustKernelTypes.ActionKind.FREEZE, 91, 10 ether);
        decrease.caseId = freeze.caseId;
        decrease.actionId = adapter.deriveActionId(decrease);
        _expectInvalid(abi.encodeCall(adapter.executeRegulatoryAction, (decrease)), 12, "decrease must use reversal");

        TrustKernelTypes.ActionRequest memory increase = _request(TrustKernelTypes.ActionKind.FREEZE, 92, 40 ether);
        increase.caseId = freeze.caseId;
        increase.actionId = adapter.deriveActionId(increase);
        _checkActionReceipt(increase, adapter.executeRegulatoryAction(increase));
        _assertEq(_frozen(address(this)), 40 ether, "strict increase");
        _assertEq(adapter.actionRecord(increase.actionId).priorAmount, 25 ether, "amendment prior target");

        TrustKernelTypes.ReversalRequest memory stale =
            _reversal(freeze.actionId, TrustKernelTypes.ReversalKind.UNFREEZE, 2);
        _expectInvalid(abi.encodeCall(adapter.executeRegulatoryReversal, (stale)), 11, "only the live head reverses");
        TrustKernelTypes.ReversalRequest memory popAmendment =
            _reversal(increase.actionId, TrustKernelTypes.ReversalKind.UNFREEZE, 93);
        _checkReversalReceipt(
            popAmendment, adapter.executeRegulatoryReversal(popAmendment), address(this), address(this)
        );
        _assertEq(_frozen(address(this)), 25 ether, "pop restores the prior target");
        _checkCase(
            freeze.caseId, TrustKernelTypes.CasePhase.OPEN, TrustKernelTypes.CaseFamily.FREEZE, freeze.actionId, 3
        );
        TrustKernelTypes.ReversalRequest memory unfreeze =
            _reversal(freeze.actionId, TrustKernelTypes.ReversalKind.UNFREEZE, 94);
        _checkReversalReceipt(unfreeze, adapter.executeRegulatoryReversal(unfreeze), address(this), address(this));
        _assertEq(_frozen(address(this)), 0, "unfreeze");
        _checkCase(
            freeze.caseId, TrustKernelTypes.CasePhase.TERMINAL, TrustKernelTypes.CaseFamily.FREEZE, bytes32(0), 4
        );

        TrustKernelTypes.ActionRequest memory restrict = _request(TrustKernelTypes.ActionKind.RESTRICT, 3, 0);
        _checkActionReceipt(restrict, adapter.executeRegulatoryAction(restrict));
        _assert(_restricted(address(this)), "restrict");
        TrustKernelTypes.ReversalRequest memory unrestrict =
            _reversal(restrict.actionId, TrustKernelTypes.ReversalKind.UNRESTRICT, 4);
        _checkReversalReceipt(unrestrict, adapter.executeRegulatoryReversal(unrestrict), address(this), address(this));
        _assert(!_restricted(address(this)), "unrestrict");
        _checkCase(
            restrict.caseId, TrustKernelTypes.CasePhase.TERMINAL, TrustKernelTypes.CaseFamily.RESTRICT, bytes32(0), 2
        );

        TrustKernelTypes.ActionRequest memory seize = _request(TrustKernelTypes.ActionKind.SEIZE, 5, 11 ether);
        _checkActionReceipt(seize, adapter.executeRegulatoryAction(seize));
        _assertEq(_balance(address(adapter)), 11 ether, "seize");
        _checkCase(
            seize.caseId, TrustKernelTypes.CasePhase.OPEN, TrustKernelTypes.CaseFamily.CUSTODY, seize.actionId, 1
        );
        TrustKernelTypes.ReversalRequest memory release =
            _reversal(seize.actionId, TrustKernelTypes.ReversalKind.RELEASE, 6);
        _checkReversalReceipt(release, adapter.executeRegulatoryReversal(release), address(adapter), address(this));
        _assertEq(_balance(address(adapter)), 0, "release");
        _checkCase(
            seize.caseId, TrustKernelTypes.CasePhase.TERMINAL, TrustKernelTypes.CaseFamily.CUSTODY, bytes32(0), 2
        );

        TrustKernelTypes.ActionRequest memory confiscate = _request(TrustKernelTypes.ActionKind.CONFISCATE, 7, 7 ether);
        _checkActionReceipt(confiscate, adapter.executeRegulatoryAction(confiscate));
        _checkCase(
            confiscate.caseId,
            TrustKernelTypes.CasePhase.TERMINAL,
            TrustKernelTypes.CaseFamily.DISPOSITION,
            bytes32(0),
            1
        );
        TrustKernelTypes.ActionRequest memory liquidate = _request(TrustKernelTypes.ActionKind.LIQUIDATE, 8, 5 ether);
        _checkActionReceipt(liquidate, adapter.executeRegulatoryAction(liquidate));
        _assertEq(
            adapter.receipt(liquidate.actionId).externalCommitment,
            keccak256(abi.encode(liquidate.settlementCommitment, liquidate.proceedsCommitment)),
            "liquidate external commitment"
        );
        TrustKernelTypes.ActionRequest memory recoverAction = _request(TrustKernelTypes.ActionKind.RECOVER, 9, 3 ether);
        _checkActionReceipt(recoverAction, adapter.executeRegulatoryAction(recoverAction));
        _assertEq(
            adapter.receipt(recoverAction.actionId).externalCommitment,
            recoverAction.entitlementCommitment,
            "recover external commitment"
        );
        _assertEq(_balance(buyer), 12 ether, "disposition");
        _assertEq(_balance(recovered), 3 ether, "recover");

        TrustKernelTypes.ActionRequest memory reusedEntitlement =
            _request(TrustKernelTypes.ActionKind.RECOVER, 10, 1 ether);
        reusedEntitlement.entitlementCommitment = recoverAction.entitlementCommitment;
        reusedEntitlement.actionId = adapter.deriveActionId(reusedEntitlement);
        _expectInvalid(
            abi.encodeCall(adapter.executeRegulatoryAction, (reusedEntitlement)), 9, "entitlement consumed once"
        );
    }

    function testReceiptBindsEvidenceAuthorityRootAndFinalEvent() external {
        TrustKernelTypes.ActionRequest memory freeze = _request(TrustKernelTypes.ActionKind.FREEZE, 11, 7 ether);
        vm.recordLogs();
        bytes32 returned = adapter.executeRegulatoryAction(freeze);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        Vm.Log memory last = logs[logs.length - 1];
        _assertEq(last.emitter, address(adapter), "adapter emits the final event");
        _assertEq(last.topics[0], ACTION_APPLIED_TOPIC, "final action event");
        _assertEq(last.topics[1], freeze.actionId, "event actionId");
        _assertEq(last.topics[2], bytes32(uint256(uint8(freeze.action))), "event action kind");
        _assertEq(last.topics[3], freeze.caseId, "event caseId");
        _assertEq(abi.decode(last.data, (bytes32)), returned, "event receipt hash");

        TrustKernelTypes.ActionRecord memory record = adapter.actionRecord(freeze.actionId);
        _assertEq(record.commandHash, _recomputeCommandHash(freeze), "raw calldata hash equals ABI encoding");
        TrustKernelTypes.Receipt memory r = adapter.receipt(freeze.actionId);
        (bytes32 root,) = adapter.dependencyState();
        _assertEq(
            r.assessmentEvidence, keccak256(abi.encode(root, record.commandHash, uint8(0))), "overlay consults nothing"
        );
        _assertEq(record.evidenceHash, r.assessmentEvidence, "record evidence equals receipt evidence");
        _assertEq(r.subject, address(this), "receipt subject");
        _assertEq(r.authorityRef, AUTHORITY_REF, "receipt authority");
        _assertEq(r.dependencyRoot, root, "receipt root");
        _assertEq(r.provenanceCommitment, freeze.provenanceCommitment, "receipt provenance");
        _assertEq(r.parentCommandId, bytes32(0), "action has no parent");

        TrustKernelTypes.ActionRequest memory confiscate = _request(TrustKernelTypes.ActionKind.CONFISCATE, 12, 2 ether);
        adapter.executeRegulatoryAction(confiscate);
        _assertEq(
            adapter.receipt(confiscate.actionId).assessmentEvidence,
            keccak256(abi.encode(root, _recomputeCommandHash(confiscate), uint8(3))),
            "transfer consults identity and compliance"
        );

        TrustKernelTypes.ReversalRequest memory unfreeze =
            _reversal(freeze.actionId, TrustKernelTypes.ReversalKind.UNFREEZE, 13);
        vm.recordLogs();
        bytes32 reversalReceipt = adapter.executeRegulatoryReversal(unfreeze);
        logs = vm.getRecordedLogs();
        last = logs[logs.length - 1];
        _assertEq(last.topics[0], REVERSAL_APPLIED_TOPIC, "final reversal event");
        _assertEq(last.topics[1], unfreeze.reversalId, "event reversalId");
        _assertEq(last.topics[3], freeze.actionId, "event parent actionId");
        _assertEq(abi.decode(last.data, (bytes32)), reversalReceipt, "event reversal receipt hash");
        TrustKernelTypes.Receipt memory rr = adapter.receipt(unfreeze.reversalId);
        _assert(rr.receiptKind == TrustKernelTypes.ReceiptKind.REVERSAL, "reversal receipt kind");
        _assertEq(rr.parentCommandId, freeze.actionId, "reversal parent");
        _assertEq(rr.provenanceCommitment, unfreeze.provenanceCommitment, "reversal provenance");
        _assertEq(rr.externalCommitment, bytes32(0), "reversal external commitment is zero");
        TrustKernelTypes.Receipt memory retagged = rr;
        retagged.receiptKind = TrustKernelTypes.ReceiptKind.ACTION;
        _assert(_recomputeReceiptHash(retagged) != reversalReceipt, "receipt kind tag separates domains");
    }

    // ------------------------------------------------------------------
    // Seal, topology, dependency drift, and bypass closure
    // ------------------------------------------------------------------

    function testProfileSealAndDirectBypassClosure() external {
        _assert(adapter.trustProfile().full, "full");
        (bool direct,) = token.call(abi.encodeCall(MockERC3643Token.forcedTransfer, (address(this), buyer, 1 ether)));
        _assert(!direct, "raw direct bypass");
        address[] memory from = new address[](1);
        address[] memory to = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        from[0] = address(this);
        to[0] = buyer;
        amounts[0] = 1 ether;
        (bool batch,) = token.call(abi.encodeCall(MockERC3643Token.batchForcedTransfer, (from, to, amounts)));
        _assert(!batch, "batch bypass");
        (bool freeze,) = token.call(abi.encodeCall(MockERC3643Token.freezePartialTokens, (address(this), 1 ether)));
        _assert(!freeze, "raw freeze bypass");
        (bool restrict,) = token.call(abi.encodeCall(MockERC3643Token.setAddressFrozen, (address(this), true)));
        _assert(!restrict, "raw address freeze bypass");
        (bool relayed,) =
            stranger.relay(token, abi.encodeCall(MockERC3643Token.forcedTransfer, (address(this), buyer, 1 ether)));
        _assert(!relayed, "stranger bypass");
        (bool viaGovernor,) =
            address(governor).call(abi.encodeCall(MockERC3643Token.forcedTransfer, (address(this), buyer, 1 ether)));
        _assert(!viaGovernor, "governor has no forwarding surface");
        (bool ownerSurface,) = token.call(abi.encodeCall(MockERC3643Token.transferOwnership, (address(this))));
        _assert(!ownerSurface, "owner surface is inert");
        _assertEq(_balance(buyer), 0, "no bypass moved anything");
        _assertEq(_frozen(address(this)), 0, "no bypass froze anything");
    }

    function testUnsealedAdapterIsNotFullAndCannotExecute() external {
        _freshUnit();
        TrustKernelTypes.ProfileDescriptor memory descriptor = adapter.trustProfile();
        _assert(!descriptor.full, "unsealed is not full");
        _assertEq(descriptor.manifestHash, bytes32(0), "no sealed binding");
        (bytes32 root, uint64 epoch) = adapter.dependencyState();
        _assert(root == bytes32(0) && epoch == 0, "no dependency state before the seal");
        TrustKernelTypes.ActionRequest memory request = _request(TrustKernelTypes.ActionKind.FREEZE, 20, 1 ether);
        _expectOperationalFailure(abi.encodeCall(adapter.executeRegulatoryAction, (request)), 300, "unsealed execute");
        request.dependencyRoot = keccak256("some root");
        request.actionId = adapter.deriveActionId(request);
        _expectInvalid(abi.encodeCall(adapter.executeRegulatoryAction, (request)), 5, "root is checked before topology");
        _assert(adapter.actionRecord(request.actionId).lifecycle == TrustKernelTypes.Lifecycle.NONE, "no record");
    }

    function testSealIsOneWayAndManifestMustBeCanonical() external {
        (bool again, bytes memory result) =
            address(governor).call(abi.encodeCall(governor.seal, (address(adapter), noEntries)));
        _assert(!again && _selector(result) == IERCTrustKernel.TrustOperationalFailure.selector, "reseal");
        _assertEq(_reasonOf(result), 301, "seal invalid");

        _freshUnit();
        ERC3643ProfileTypes.ImportEntry[] memory unsorted = new ERC3643ProfileTypes.ImportEntry[](2);
        unsorted[0] = ERC3643ProfileTypes.ImportEntry(holder, 1 ether, false);
        unsorted[1] = ERC3643ProfileTypes.ImportEntry(buyer, 1 ether, false);
        IFixtureToken(token).setExclusiveAgent(address(adapter));
        IFixtureToken(token).transferOwnership(address(governor));
        (bool sorted, bytes memory sortedResult) =
            address(governor).call(abi.encodeCall(governor.seal, (address(adapter), unsorted)));
        _assert(!sorted && _reasonOf(sortedResult) == 301, "manifest must be strictly increasing");
        ERC3643ProfileTypes.ImportEntry[] memory empty = new ERC3643ProfileTypes.ImportEntry[](1);
        empty[0] = ERC3643ProfileTypes.ImportEntry(holder, 0, false);
        (bool zero, bytes memory zeroResult) =
            address(governor).call(abi.encodeCall(governor.seal, (address(adapter), empty)));
        _assert(!zero && _reasonOf(zeroResult) == 301, "manifest entries declare nonzero state");
        (bool wrongCaller,) =
            stranger.relay(address(governor), abi.encodeCall(governor.seal, (address(adapter), noEntries)));
        _assert(!wrongCaller, "only the bootstrap authority seals");
        _assert(!governor.topologySealed() && !adapter.trustProfile().full, "nothing sealed");

        ERC3643TrustAdapter other = new ERC3643TrustAdapter(address(governor), address(this), AUTHORITY_REF);
        (bool mismatch, bytes memory mismatchResult) =
            address(governor).call(abi.encodeCall(governor.seal, (address(other), noEntries)));
        _assert(!mismatch && _reasonOf(mismatchResult) == 302, "adapter that is not the exclusive agent");
        governor.seal(address(adapter), noEntries);
        _assert(adapter.trustProfile().full, "sealed after the failed attempts");
    }

    function testTopologyDriftFailsClosedAndClearsFull() external {
        TrustKernelTypes.ActionRequest memory request = _request(TrustKernelTypes.ActionKind.FREEZE, 21, 1 ether);
        vm.etch(token, address(compliance).code);
        _assert(!adapter.trustProfile().full, "token code drift clears full");
        _expectOperationalFailure(abi.encodeCall(adapter.executeRegulatoryAction, (request)), 300, "drifted token");
        _assert(!governor.isFull(address(adapter)), "governor reports the drift");
    }

    function testDependencyCodeDriftFailsClosed() external {
        TrustKernelTypes.ActionRequest memory transferRequest =
            _request(TrustKernelTypes.ActionKind.CONFISCATE, 22, 1 ether);
        TrustKernelTypes.ActionRequest memory overlay = _request(TrustKernelTypes.ActionKind.FREEZE, 23, 1 ether);
        bytes memory identityCode = address(identity).code;
        bytes32 identityBinding = _expectedBinding(1, governor.sealedBinding());
        bytes32 sealedRoot = _expectedRoot(governor.sealedBinding());
        vm.etch(address(identity), address(compliance).code);
        _assert(!adapter.trustProfile().full, "identity registry code drift clears full");
        (bool ok, bytes memory result) = _call(abi.encodeCall(adapter.executeRegulatoryAction, (transferRequest)));
        _assert(!ok && _selector(result) == IERCTrustKernel.TrustOperationalFailure.selector, "drifted identity");
        _assertEq(_reasonOf(result), 200, "dependency code mismatch");
        _assertEq(_wordAt(result, 2), identityBinding, "identity binding reference is the sealed binding");
        _expectOperationalFailure(
            abi.encodeCall(adapter.executeRegulatoryAction, (overlay)), 200, "overlay also fails closed"
        );
        vm.etch(address(identity), identityCode);
        _assert(adapter.trustProfile().full, "restored code restores full");

        vm.etch(address(compliance), identityCode);
        _assert(!adapter.trustProfile().full, "compliance code drift clears full");
        _expectOperationalFailure(
            abi.encodeCall(adapter.executeRegulatoryAction, (transferRequest)), 200, "drifted compliance"
        );
        (bytes32 root, uint64 epoch) = adapter.dependencyState();
        _assert(root == sealedRoot && epoch == 1, "root and epoch are the sealed ones");
    }

    function testRejectedAndOperationalFailureFailClosedWithStutter() external {
        uint256 before = _balance(address(this));
        identity.setVerified(buyer, false);
        _expectRejected(
            abi.encodeCall(
                adapter.executeRegulatoryAction, (_request(TrustKernelTypes.ActionKind.CONFISCATE, 30, 4 ether))
            ),
            101,
            "identity denied"
        );
        identity.setVerified(buyer, true);
        compliance.setMode(MockERC3643Compliance.Mode.REJECT);
        _expectRejected(
            abi.encodeCall(
                adapter.executeRegulatoryAction, (_request(TrustKernelTypes.ActionKind.CONFISCATE, 31, 4 ether))
            ),
            100,
            "policy denied"
        );
        compliance.setMode(MockERC3643Compliance.Mode.ALLOW);

        _expectDependencyFailure(true, MockERC3643IdentityRegistry.Mode.REVERT_CALL, 402, "identity revert");
        _expectDependencyFailure(true, MockERC3643IdentityRegistry.Mode.MALFORMED, 402, "identity empty");
        _expectDependencyFailure(true, MockERC3643IdentityRegistry.Mode.NONCANONICAL, 402, "identity word above one");
        _expectDependencyFailure(true, MockERC3643IdentityRegistry.Mode.LONG_RETURN, 402, "identity long return");
        identity.setMode(MockERC3643IdentityRegistry.Mode.ALLOW);
        _expectDependencyFailure(false, MockERC3643IdentityRegistry.Mode.REVERT_CALL, 403, "compliance revert");
        _expectDependencyFailure(false, MockERC3643IdentityRegistry.Mode.MALFORMED, 403, "compliance empty");
        _expectDependencyFailure(false, MockERC3643IdentityRegistry.Mode.NONCANONICAL, 403, "compliance word above one");
        _expectDependencyFailure(false, MockERC3643IdentityRegistry.Mode.LONG_RETURN, 403, "compliance long return");
        compliance.setMode(MockERC3643Compliance.Mode.ALLOW);

        _assertEq(_balance(address(this)), before, "stutter");
        _assertEq(_balance(buyer), 0, "nothing moved");
        adapter.executeRegulatoryAction(_request(TrustKernelTypes.ActionKind.CONFISCATE, 32, 4 ether));
        _assertEq(_balance(buyer), 4 ether, "restored dependencies admit the command");
    }

    // ------------------------------------------------------------------
    // Existing upstream state: fresh zero-state seal or exact import manifest
    // ------------------------------------------------------------------

    function testUndeclaredUpstreamStateFailsClosed() external {
        _freshUnit();
        _seedLegacy(holder, 100 ether, 10 ether, true);
        _seal(noEntries);
        _assert(adapter.trustProfile().full, "fresh zero-state declaration seals");

        TrustKernelTypes.ActionRequest memory freeze = _request(TrustKernelTypes.ActionKind.FREEZE, 40, 50 ether);
        freeze.subject = holder;
        freeze.source = holder;
        freeze.actionId = adapter.deriveActionId(freeze);
        (bool ok, bytes memory result) = _call(abi.encodeCall(adapter.executeRegulatoryAction, (freeze)));
        _assert(!ok && _selector(result) == IERCTrustKernel.TrustOperationalFailure.selector, "undeclared state");
        _assertEq(_reasonOf(result), 303, "import manifest mismatch");
        _assertEq(address(uint160(uint256(_wordAt(result, 2)))), holder, "account reference");
        _assertEq(_frozen(holder), 10 ether, "legacy freeze is never overwritten");
        _assert(_restricted(holder), "legacy restriction is never overwritten");
        _assert(adapter.actionRecord(freeze.actionId).lifecycle == TrustKernelTypes.Lifecycle.NONE, "no record");

        TrustKernelTypes.ActionRequest memory toHolder = _request(TrustKernelTypes.ActionKind.CONFISCATE, 41, 1 ether);
        toHolder.destination = holder;
        toHolder.actionId = adapter.deriveActionId(toHolder);
        _expectOperationalFailure(
            abi.encodeCall(adapter.executeRegulatoryAction, (toHolder)), 303, "undeclared destination"
        );
        _assertEq(_balance(holder), 100 ether, "destination untouched");

        TrustKernelTypes.ActionRequest memory clean = _request(TrustKernelTypes.ActionKind.FREEZE, 42, 1 ether);
        adapter.executeRegulatoryAction(clean);
        _assertEq(_frozen(address(this)), 1 ether, "accounts with zero upstream state are owned");
    }

    function testExactImportManifestOpensReversibleCases() external {
        _freshUnit();
        _seedLegacy(holder, 100 ether, 10 ether, true);
        ERC3643ProfileTypes.ImportEntry[] memory manifest = new ERC3643ProfileTypes.ImportEntry[](1);
        manifest[0] = ERC3643ProfileTypes.ImportEntry(holder, 10 ether, true);
        vm.recordLogs();
        _seal(manifest);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 manifestHash = keccak256(abi.encode(manifest));
        _assertEq(governor.importManifestHash(), manifestHash, "manifest hash");
        _assertEq(governor.sealedBinding(), _sealedBinding(manifestHash), "binding commits to the manifest");
        _assert(adapter.trustProfile().full, "import seals full");

        bytes32 freezeCase = _importCaseId(manifestHash, holder, TrustKernelTypes.CaseFamily.FREEZE);
        bytes32 freezeHead = _importActionId(freezeCase);
        bytes32 restrictCase = _importCaseId(manifestHash, holder, TrustKernelTypes.CaseFamily.RESTRICT);
        bytes32 restrictHead = _importActionId(restrictCase);
        uint256 imported;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter != address(adapter) || logs[i].topics[0] != STATE_IMPORTED_TOPIC) continue;
            _assert(logs[i].topics[1] == freezeCase || logs[i].topics[1] == restrictCase, "imported case id");
            _assertEq(address(uint160(uint256(logs[i].topics[3]))), holder, "imported subject");
            imported += 1;
        }
        _assertEq(imported, 2, "one imported case per declared family");
        _checkCase(freezeCase, TrustKernelTypes.CasePhase.OPEN, TrustKernelTypes.CaseFamily.FREEZE, freezeHead, 1);
        _checkCase(restrictCase, TrustKernelTypes.CasePhase.OPEN, TrustKernelTypes.CaseFamily.RESTRICT, restrictHead, 1);
        TrustKernelTypes.ActionRecord memory synthetic = adapter.actionRecord(freezeHead);
        _assert(synthetic.lifecycle == TrustKernelTypes.Lifecycle.APPLIED, "imported head is applied");
        _assertEq(synthetic.amount, 10 ether, "imported target");
        _assertEq(synthetic.subject, holder, "imported subject");
        _assert(
            synthetic.commandHash == bytes32(0) && synthetic.receiptHash == bytes32(0), "imported head has no command"
        );
        _assertEq(adapter.receipt(freezeHead).receiptHash, bytes32(0), "imported head has no receipt");

        // A FREEZE in a fresh case is a cross-case conflict; the imported case admits the amendment.
        TrustKernelTypes.ActionRequest memory conflict = _request(TrustKernelTypes.ActionKind.FREEZE, 50, 15 ether);
        conflict.subject = holder;
        conflict.source = holder;
        conflict.actionId = adapter.deriveActionId(conflict);
        _expectInvalid(
            abi.encodeCall(adapter.executeRegulatoryAction, (conflict)), 10, "imported head owns the subject"
        );
        TrustKernelTypes.ActionRequest memory raise = _request(TrustKernelTypes.ActionKind.FREEZE, 51, 15 ether);
        raise.subject = holder;
        raise.source = holder;
        raise.caseId = freezeCase;
        raise.actionId = adapter.deriveActionId(raise);
        _checkActionReceipt(raise, adapter.executeRegulatoryAction(raise));
        _assertEq(_frozen(holder), 15 ether, "amendment raises the imported target");
        _assertEq(adapter.actionRecord(raise.actionId).priorAmount, 10 ether, "imported target is the prior");
        adapter.executeRegulatoryReversal(_reversal(raise.actionId, TrustKernelTypes.ReversalKind.UNFREEZE, 52));
        _assertEq(_frozen(holder), 10 ether, "pop restores the imported target");
        _checkCase(freezeCase, TrustKernelTypes.CasePhase.OPEN, TrustKernelTypes.CaseFamily.FREEZE, freezeHead, 3);
        TrustKernelTypes.ReversalRequest memory clear =
            _reversal(freezeHead, TrustKernelTypes.ReversalKind.UNFREEZE, 53);
        _checkReversalReceipt(clear, adapter.executeRegulatoryReversal(clear), holder, holder);
        _assertEq(_frozen(holder), 0, "imported freeze lifted by a typed reversal");
        _checkCase(freezeCase, TrustKernelTypes.CasePhase.TERMINAL, TrustKernelTypes.CaseFamily.FREEZE, bytes32(0), 4);

        TrustKernelTypes.ReversalRequest memory unrestrict =
            _reversal(restrictHead, TrustKernelTypes.ReversalKind.UNRESTRICT, 54);
        _checkReversalReceipt(unrestrict, adapter.executeRegulatoryReversal(unrestrict), holder, holder);
        _assert(!_restricted(holder), "imported restriction lifted by a typed reversal");
        _checkCase(
            restrictCase, TrustKernelTypes.CasePhase.TERMINAL, TrustKernelTypes.CaseFamily.RESTRICT, bytes32(0), 2
        );

        TrustKernelTypes.ActionRequest memory fresh = _request(TrustKernelTypes.ActionKind.FREEZE, 55, 3 ether);
        fresh.subject = holder;
        fresh.source = holder;
        fresh.actionId = adapter.deriveActionId(fresh);
        adapter.executeRegulatoryAction(fresh);
        _assertEq(_frozen(holder), 3 ether, "a new case opens after the imported chain closed");
    }

    function testImportManifestMustMatchUpstreamExactly() external {
        _freshUnit();
        _seedLegacy(holder, 100 ether, 10 ether, false);
        IFixtureToken(token).setExclusiveAgent(address(adapter));
        IFixtureToken(token).transferOwnership(address(governor));
        ERC3643ProfileTypes.ImportEntry[] memory wrongAmount = new ERC3643ProfileTypes.ImportEntry[](1);
        wrongAmount[0] = ERC3643ProfileTypes.ImportEntry(holder, 9 ether, false);
        (bool ok, bytes memory result) =
            address(governor).call(abi.encodeCall(governor.seal, (address(adapter), wrongAmount)));
        _assert(!ok && _selector(result) == IERCTrustKernel.TrustOperationalFailure.selector, "wrong amount");
        _assertEq(_reasonOf(result), 303, "import manifest mismatch");
        _assertEq(address(uint160(uint256(_wordAt(result, 2)))), holder, "account reference");
        ERC3643ProfileTypes.ImportEntry[] memory wrongFlag = new ERC3643ProfileTypes.ImportEntry[](1);
        wrongFlag[0] = ERC3643ProfileTypes.ImportEntry(holder, 10 ether, true);
        (ok, result) = address(governor).call(abi.encodeCall(governor.seal, (address(adapter), wrongFlag)));
        _assert(!ok && _reasonOf(result) == 303, "wrong flag");
        ERC3643ProfileTypes.ImportEntry[] memory undeclaredAccount = new ERC3643ProfileTypes.ImportEntry[](1);
        undeclaredAccount[0] = ERC3643ProfileTypes.ImportEntry(buyer, 1 ether, false);
        (ok, result) = address(governor).call(abi.encodeCall(governor.seal, (address(adapter), undeclaredAccount)));
        _assert(!ok && _reasonOf(result) == 303, "declared state the token does not have");
        _assert(!governor.topologySealed(), "a rejected manifest seals nothing");
        _assert(!adapter.trustProfile().full, "adapter stays unsealed");
        (bytes32 root, uint64 epoch) = adapter.dependencyState();
        _assert(root == bytes32(0) && epoch == 0, "no bindings after a rejected seal");

        ERC3643ProfileTypes.ImportEntry[] memory exact = new ERC3643ProfileTypes.ImportEntry[](1);
        exact[0] = ERC3643ProfileTypes.ImportEntry(holder, 10 ether, false);
        governor.seal(address(adapter), exact);
        _assert(adapter.trustProfile().full, "exact manifest seals");
        (bool relayed,) = stranger.relay(address(adapter), abi.encodeCall(adapter.activateSeal, (exact)));
        _assert(!relayed, "activation is governor-only");
    }

    // ------------------------------------------------------------------
    // Replay, nonce, authority, shape, and the case table
    // ------------------------------------------------------------------

    function testReplayNonceAndAuthority() external {
        TrustKernelTypes.ActionRequest memory freeze = _request(TrustKernelTypes.ActionKind.FREEZE, 60, 1 ether);
        adapter.executeRegulatoryAction(freeze);
        (bool ok, bytes memory result) = _call(abi.encodeCall(adapter.executeRegulatoryAction, (freeze)));
        _assert(!ok && _selector(result) == IERCTrustKernel.TrustReplay.selector, "action replay");
        _assertEq(_wordAt(result, 0), freeze.actionId, "replay key is the actionId");

        TrustKernelTypes.ActionRequest memory sameNonce = _request(TrustKernelTypes.ActionKind.CONFISCATE, 60, 1 ether);
        (ok, result) = _call(abi.encodeCall(adapter.executeRegulatoryAction, (sameNonce)));
        _assert(!ok && _selector(result) == IERCTrustKernel.TrustReplay.selector, "nonce replay");
        _assertEq(
            _wordAt(result, 0),
            keccak256(abi.encode(DOMAIN, AUTHORITY_REF, uint64(1), uint256(60))),
            "replay key is the nonce key"
        );

        (ok, result) = stranger.relay(
            address(adapter),
            abi.encodeCall(
                adapter.executeRegulatoryAction, (_request(TrustKernelTypes.ActionKind.CONFISCATE, 61, 1 ether))
            )
        );
        _assert(!ok && _selector(result) == IERCTrustKernel.TrustUnauthorized.selector, "caller must be the authority");

        TrustKernelTypes.ActionRequest memory wrongEpoch = _request(TrustKernelTypes.ActionKind.CONFISCATE, 62, 1 ether);
        wrongEpoch.authorityEpoch = 2;
        wrongEpoch.actionId = adapter.deriveActionId(wrongEpoch);
        _expectInvalid(abi.encodeCall(adapter.executeRegulatoryAction, (wrongEpoch)), 4, "authority epoch");
        TrustKernelTypes.ActionRequest memory wrongRef = _request(TrustKernelTypes.ActionKind.CONFISCATE, 63, 1 ether);
        wrongRef.authorityRef = keccak256("OTHER");
        wrongRef.actionId = adapter.deriveActionId(wrongRef);
        _expectInvalid(
            abi.encodeCall(adapter.executeRegulatoryAction, (wrongRef)), 4, "unknown authority has epoch zero"
        );
        wrongRef.authorityEpoch = 0;
        wrongRef.actionId = adapter.deriveActionId(wrongRef);
        _expectSelector(
            abi.encodeCall(adapter.executeRegulatoryAction, (wrongRef)),
            IERCTrustKernel.TrustUnauthorized.selector,
            "unknown authority is unauthorized"
        );

        TrustKernelTypes.ReversalRequest memory unfreeze =
            _reversal(freeze.actionId, TrustKernelTypes.ReversalKind.UNFREEZE, 64);
        adapter.executeRegulatoryReversal(unfreeze);
        (ok, result) = _call(abi.encodeCall(adapter.executeRegulatoryReversal, (unfreeze)));
        _assert(!ok && _selector(result) == IERCTrustKernel.TrustReplay.selector, "reversal replay");
    }

    function testRootAndEpochAreCheckedIndependently() external {
        TrustKernelTypes.ActionRequest memory wrongRoot = _request(TrustKernelTypes.ActionKind.FREEZE, 65, 1 ether);
        wrongRoot.dependencyRoot = bytes32(uint256(wrongRoot.dependencyRoot) ^ 1);
        wrongRoot.actionId = adapter.deriveActionId(wrongRoot);
        _expectInvalid(abi.encodeCall(adapter.executeRegulatoryAction, (wrongRoot)), 5, "wrong root with current epoch");
        TrustKernelTypes.ActionRequest memory wrongEpoch = _request(TrustKernelTypes.ActionKind.FREEZE, 66, 1 ether);
        wrongEpoch.dependencyEpoch = 2;
        wrongEpoch.actionId = adapter.deriveActionId(wrongEpoch);
        _expectInvalid(
            abi.encodeCall(adapter.executeRegulatoryAction, (wrongEpoch)), 5, "wrong epoch with current root"
        );
        TrustKernelTypes.ActionRequest memory freeze = _request(TrustKernelTypes.ActionKind.FREEZE, 67, 1 ether);
        adapter.executeRegulatoryAction(freeze);
        TrustKernelTypes.ReversalRequest memory staleReversal =
            _reversal(freeze.actionId, TrustKernelTypes.ReversalKind.UNFREEZE, 68);
        staleReversal.dependencyRoot = bytes32(uint256(staleReversal.dependencyRoot) ^ 1);
        staleReversal.reversalId = adapter.deriveReversalId(staleReversal);
        _expectInvalid(
            abi.encodeCall(adapter.executeRegulatoryReversal, (staleReversal)), 5, "reversal checks the root"
        );
    }

    function testDispositionOnOpenOverlayCaseIsRejectedAndTerminalCasesRejectReversals() external {
        TrustKernelTypes.ActionRequest memory freeze = _request(TrustKernelTypes.ActionKind.FREEZE, 70, 5 ether);
        adapter.executeRegulatoryAction(freeze);
        TrustKernelTypes.ActionRequest memory confiscate = _request(TrustKernelTypes.ActionKind.CONFISCATE, 71, 1 ether);
        confiscate.caseId = freeze.caseId;
        confiscate.actionId = adapter.deriveActionId(confiscate);
        _expectInvalid(
            abi.encodeCall(adapter.executeRegulatoryAction, (confiscate)), 10, "CT-14 disposition on open overlay case"
        );
        _assertEq(_frozen(address(this)), 5 ether, "overlay intact");

        adapter.executeRegulatoryReversal(_reversal(freeze.actionId, TrustKernelTypes.ReversalKind.UNFREEZE, 72));
        TrustKernelTypes.ReversalRequest memory again =
            _reversal(freeze.actionId, TrustKernelTypes.ReversalKind.UNFREEZE, 73);
        _expectTerminal(
            abi.encodeCall(adapter.executeRegulatoryReversal, (again)), freeze.caseId, "CT-15 reversal on terminal case"
        );
        TrustKernelTypes.ActionRequest memory reopen = _request(TrustKernelTypes.ActionKind.FREEZE, 74, 9 ether);
        reopen.caseId = freeze.caseId;
        reopen.actionId = adapter.deriveActionId(reopen);
        _expectTerminal(
            abi.encodeCall(adapter.executeRegulatoryAction, (reopen)), freeze.caseId, "CT-15 action on terminal case"
        );

        TrustKernelTypes.ActionRequest memory seize = _request(TrustKernelTypes.ActionKind.SEIZE, 75, 9 ether);
        adapter.executeRegulatoryAction(seize);
        TrustKernelTypes.ActionRequest memory disposition =
            _custodyDisposition(TrustKernelTypes.ActionKind.CONFISCATE, seize, 76);
        _checkActionReceipt(disposition, adapter.executeRegulatoryAction(disposition));
        _checkCase(
            seize.caseId, TrustKernelTypes.CasePhase.TERMINAL, TrustKernelTypes.CaseFamily.CUSTODY, bytes32(0), 2
        );
        _assert(
            adapter.actionRecord(seize.actionId).lifecycle == TrustKernelTypes.Lifecycle.APPLIED, "seize stays applied"
        );
        TrustKernelTypes.ReversalRequest memory release =
            _reversal(seize.actionId, TrustKernelTypes.ReversalKind.RELEASE, 77);
        _expectTerminal(
            abi.encodeCall(adapter.executeRegulatoryReversal, (release)),
            seize.caseId,
            "terminal guard before custody check"
        );
        _assertEq(_balance(address(adapter)), 0, "no release after disposition");
        _assertEq(_balance(buyer), 9 ether, "custody disposition delivered");
    }

    function testOverlayCaseConflictsAndFamilies() external {
        TrustKernelTypes.ActionRequest memory freezeX = _request(TrustKernelTypes.ActionKind.FREEZE, 80, 10 ether);
        adapter.executeRegulatoryAction(freezeX);
        TrustKernelTypes.ActionRequest memory freezeY = _request(TrustKernelTypes.ActionKind.FREEZE, 81, 20 ether);
        _expectInvalid(
            abi.encodeCall(adapter.executeRegulatoryAction, (freezeY)), 10, "CT-3 second freeze case on one subject"
        );
        TrustKernelTypes.ActionRequest memory restrictInX = _request(TrustKernelTypes.ActionKind.RESTRICT, 82, 0);
        restrictInX.caseId = freezeX.caseId;
        restrictInX.actionId = adapter.deriveActionId(restrictInX);
        _expectInvalid(
            abi.encodeCall(adapter.executeRegulatoryAction, (restrictInX)),
            10,
            "CT-14 non-family command in freeze case"
        );
        TrustKernelTypes.ActionRequest memory seizeInX = _request(TrustKernelTypes.ActionKind.SEIZE, 83, 1 ether);
        seizeInX.caseId = freezeX.caseId;
        seizeInX.actionId = adapter.deriveActionId(seizeInX);
        _expectInvalid(abi.encodeCall(adapter.executeRegulatoryAction, (seizeInX)), 10, "CT-14 seize in freeze case");

        TrustKernelTypes.ActionRequest memory restrictZ = _request(TrustKernelTypes.ActionKind.RESTRICT, 84, 0);
        adapter.executeRegulatoryAction(restrictZ);
        _assertEq(_frozen(address(this)), 10 ether, "freeze and restriction coexist across cases");
        _assert(_restricted(address(this)), "restriction live");
        TrustKernelTypes.ActionRequest memory restrictW = _request(TrustKernelTypes.ActionKind.RESTRICT, 85, 0);
        _expectInvalid(
            abi.encodeCall(adapter.executeRegulatoryAction, (restrictW)), 10, "CT-7 second restrict case on one subject"
        );
        TrustKernelTypes.ActionRequest memory restrictAgainZ = _request(TrustKernelTypes.ActionKind.RESTRICT, 86, 0);
        restrictAgainZ.caseId = restrictZ.caseId;
        restrictAgainZ.actionId = adapter.deriveActionId(restrictAgainZ);
        _expectInvalid(abi.encodeCall(adapter.executeRegulatoryAction, (restrictAgainZ)), 13, "CT-6 no state change");
        TrustKernelTypes.ActionRequest memory freezeInZ = _request(TrustKernelTypes.ActionKind.FREEZE, 87, 30 ether);
        freezeInZ.caseId = restrictZ.caseId;
        freezeInZ.actionId = adapter.deriveActionId(freezeInZ);
        _expectInvalid(
            abi.encodeCall(adapter.executeRegulatoryAction, (freezeInZ)), 10, "CT-14 freeze in restrict case"
        );

        TrustKernelTypes.ActionRequest memory seize = _request(TrustKernelTypes.ActionKind.SEIZE, 88, 2 ether);
        adapter.executeRegulatoryAction(seize);
        TrustKernelTypes.ActionRequest memory freezeInCustody =
            _request(TrustKernelTypes.ActionKind.FREEZE, 89, 30 ether);
        freezeInCustody.subject = buyer;
        freezeInCustody.source = buyer;
        freezeInCustody.caseId = seize.caseId;
        freezeInCustody.actionId = adapter.deriveActionId(freezeInCustody);
        _expectInvalid(
            abi.encodeCall(adapter.executeRegulatoryAction, (freezeInCustody)), 10, "CT-16 overlay in custody case"
        );
    }

    function testCustodyLifecycleAndConfinement() external {
        TrustKernelTypes.ActionRequest memory arbitrary = _request(TrustKernelTypes.ActionKind.SEIZE, 100, 5 ether);
        arbitrary.destination = buyer;
        arbitrary.custodian = buyer;
        arbitrary.actionId = adapter.deriveActionId(arbitrary);
        _expectInvalid(
            abi.encodeCall(adapter.executeRegulatoryAction, (arbitrary)), 6, "custody is confined to the adapter"
        );

        TrustKernelTypes.ActionRequest memory seize = _request(TrustKernelTypes.ActionKind.SEIZE, 101, 100 ether);
        adapter.executeRegulatoryAction(seize);
        TrustKernelTypes.ActionRequest memory secondSeize = _request(TrustKernelTypes.ActionKind.SEIZE, 102, 1 ether);
        secondSeize.caseId = seize.caseId;
        secondSeize.actionId = adapter.deriveActionId(secondSeize);
        _expectInvalid(
            abi.encodeCall(adapter.executeRegulatoryAction, (secondSeize)), 8, "CT-10 second seize in custody case"
        );
        TrustKernelTypes.ActionRequest memory wrongAmount =
            _custodyDisposition(TrustKernelTypes.ActionKind.CONFISCATE, seize, 103);
        wrongAmount.amount = 99 ether;
        wrongAmount.actionId = adapter.deriveActionId(wrongAmount);
        _expectInvalid(
            abi.encodeCall(adapter.executeRegulatoryAction, (wrongAmount)), 8, "CT-12 partial custody disposition"
        );
        TrustKernelTypes.ActionRequest memory direct = _request(TrustKernelTypes.ActionKind.CONFISCATE, 104, 1 ether);
        direct.subject = address(adapter);
        direct.source = address(adapter);
        direct.actionId = adapter.deriveActionId(direct);
        _expectInvalid(
            abi.encodeCall(adapter.executeRegulatoryAction, (direct)), 8, "backing cannot be spent by another case"
        );

        adapter.executeRegulatoryReversal(_reversal(seize.actionId, TrustKernelTypes.ReversalKind.RELEASE, 105));
        _assertEq(_balance(address(adapter)), 0, "CT-11 release returns the encumbered amount");
        _checkCase(
            seize.caseId, TrustKernelTypes.CasePhase.TERMINAL, TrustKernelTypes.CaseFamily.CUSTODY, bytes32(0), 2
        );

        TrustKernelTypes.ActionRequest memory seizeForLiquidation =
            _request(TrustKernelTypes.ActionKind.SEIZE, 106, 7 ether);
        adapter.executeRegulatoryAction(seizeForLiquidation);
        TrustKernelTypes.ActionRequest memory liquidate =
            _custodyDisposition(TrustKernelTypes.ActionKind.LIQUIDATE, seizeForLiquidation, 107);
        _checkActionReceipt(liquidate, adapter.executeRegulatoryAction(liquidate));
        _assertEq(_balance(buyer), 7 ether, "liquidation proceeds destination");
        TrustKernelTypes.ActionRequest memory seizeForRecovery =
            _request(TrustKernelTypes.ActionKind.SEIZE, 108, 5 ether);
        adapter.executeRegulatoryAction(seizeForRecovery);
        TrustKernelTypes.ActionRequest memory recoverAction =
            _custodyDisposition(TrustKernelTypes.ActionKind.RECOVER, seizeForRecovery, 109);
        _checkActionReceipt(recoverAction, adapter.executeRegulatoryAction(recoverAction));
        _assertEq(_balance(recovered), 5 ether, "recovery destination");
        _assertEq(_balance(address(adapter)), 0, "custody fully consumed");
    }

    function testDirectDispositionsAndShapeRules() external {
        TrustKernelTypes.ActionRequest memory wrongSubject = _request(TrustKernelTypes.ActionKind.RECOVER, 110, 1 ether);
        wrongSubject.subject = buyer;
        wrongSubject.actionId = adapter.deriveActionId(wrongSubject);
        _expectInvalid(
            abi.encodeCall(adapter.executeRegulatoryAction, (wrongSubject)),
            6,
            "CT-13 direct requires source == subject"
        );
        TrustKernelTypes.ActionRequest memory noSettlement =
            _request(TrustKernelTypes.ActionKind.LIQUIDATE, 111, 1 ether);
        noSettlement.settlementCommitment = bytes32(0);
        noSettlement.actionId = adapter.deriveActionId(noSettlement);
        _expectInvalid(abi.encodeCall(adapter.executeRegulatoryAction, (noSettlement)), 6, "liquidate needs settlement");
        TrustKernelTypes.ActionRequest memory stray = _request(TrustKernelTypes.ActionKind.CONFISCATE, 112, 1 ether);
        stray.settlementCommitment = keccak256("stray");
        stray.actionId = adapter.deriveActionId(stray);
        _expectInvalid(abi.encodeCall(adapter.executeRegulatoryAction, (stray)), 6, "unused commitment must be zero");
        TrustKernelTypes.ActionRequest memory freezeWithDestination =
            _request(TrustKernelTypes.ActionKind.FREEZE, 113, 1 ether);
        freezeWithDestination.destination = buyer;
        freezeWithDestination.actionId = adapter.deriveActionId(freezeWithDestination);
        _expectInvalid(
            abi.encodeCall(adapter.executeRegulatoryAction, (freezeWithDestination)), 6, "freeze retains ownership"
        );
        TrustKernelTypes.ActionRequest memory restrictWithAmount =
            _request(TrustKernelTypes.ActionKind.RESTRICT, 114, 1);
        _expectInvalid(
            abi.encodeCall(adapter.executeRegulatoryAction, (restrictWithAmount)), 6, "restrict amount must be zero"
        );
        TrustKernelTypes.ActionRequest memory wrongDomain = _request(TrustKernelTypes.ActionKind.FREEZE, 115, 1 ether);
        wrongDomain.domain = keccak256("ERC-TRUST/reference-v1");
        wrongDomain.actionId = adapter.deriveActionId(wrongDomain);
        _expectInvalid(abi.encodeCall(adapter.executeRegulatoryAction, (wrongDomain)), 1, "domain");
        TrustKernelTypes.ActionRequest memory wrongId = _request(TrustKernelTypes.ActionKind.FREEZE, 116, 1 ether);
        wrongId.actionId = bytes32(uint256(wrongId.actionId) ^ 1);
        _expectInvalid(abi.encodeCall(adapter.executeRegulatoryAction, (wrongId)), 2, "identifier");
        TrustKernelTypes.ActionRequest memory expired = _request(TrustKernelTypes.ActionKind.FREEZE, 117, 1 ether);
        expired.validBefore = 0;
        expired.actionId = adapter.deriveActionId(expired);
        _expectInvalid(abi.encodeCall(adapter.executeRegulatoryAction, (expired)), 3, "validity window");
        TrustKernelTypes.ActionRequest memory noProvenance = _request(TrustKernelTypes.ActionKind.FREEZE, 118, 1 ether);
        noProvenance.provenanceCommitment = bytes32(0);
        noProvenance.actionId = adapter.deriveActionId(noProvenance);
        _expectInvalid(abi.encodeCall(adapter.executeRegulatoryAction, (noProvenance)), 6, "provenance required");

        TrustKernelTypes.ActionRequest memory freeze = _request(TrustKernelTypes.ActionKind.FREEZE, 119, 1 ether);
        adapter.executeRegulatoryAction(freeze);
        TrustKernelTypes.ReversalRequest memory mispaired =
            _reversal(freeze.actionId, TrustKernelTypes.ReversalKind.RELEASE, 120);
        _expectInvalid(abi.encodeCall(adapter.executeRegulatoryReversal, (mispaired)), 7, "reversal pairing");
        TrustKernelTypes.ReversalRequest memory noReversalProvenance =
            _reversal(freeze.actionId, TrustKernelTypes.ReversalKind.UNFREEZE, 121);
        noReversalProvenance.provenanceCommitment = bytes32(0);
        noReversalProvenance.reversalId = adapter.deriveReversalId(noReversalProvenance);
        _expectInvalid(
            abi.encodeCall(adapter.executeRegulatoryReversal, (noReversalProvenance)), 6, "reversal provenance required"
        );
        TrustKernelTypes.ReversalRequest memory unknownAction =
            _reversal(keccak256("nope"), TrustKernelTypes.ReversalKind.UNFREEZE, 122);
        _expectInvalid(abi.encodeCall(adapter.executeRegulatoryReversal, (unknownAction)), 11, "unknown action");
    }

    // ------------------------------------------------------------------
    // Canonical calldata, event order, and saturation
    // ------------------------------------------------------------------

    function testNonCanonicalCalldataIsRejected() external {
        TrustKernelTypes.ActionRequest memory request = _request(TrustKernelTypes.ActionKind.FREEZE, 130, 1 ether);
        _expectGenericRevert(
            bytes.concat(abi.encodeCall(adapter.executeRegulatoryAction, (request)), bytes32(uint256(1))),
            "trailing action calldata must generic-revert"
        );
        _expectDirtyWordRejected(request, 10, "dirty uint64 word rejected");
        _expectDirtyWordRejected(request, 3, "dirty address word rejected");
        _expectDirtyWordRejected(request, 19, "dirty uint48 word rejected");
        _assertEq(_frozen(address(this)), 0, "dirty stutter");

        TrustKernelTypes.ActionRequest memory confiscate =
            _request(TrustKernelTypes.ActionKind.CONFISCATE, 131, 1 ether);
        bytes memory outOfRange = abi.encodeCall(adapter.executeRegulatoryAction, (confiscate));
        outOfRange[4 + 32 * 2 + 31] = 0x06;
        bytes32 outOfRangeId = _rawActionId(outOfRange);
        for (uint256 i = 0; i < 32; ++i) {
            outOfRange[4 + 32 + i] = outOfRangeId[i];
        }
        _expectGenericRevert(outOfRange, "enum out of range is rejected by decoding, not by a kernel rule");
        adapter.executeRegulatoryAction(confiscate);

        adapter.executeRegulatoryAction(request);
        TrustKernelTypes.ReversalRequest memory unfreeze =
            _reversal(request.actionId, TrustKernelTypes.ReversalKind.UNFREEZE, 132);
        _expectGenericRevert(
            bytes.concat(abi.encodeCall(adapter.executeRegulatoryReversal, (unfreeze)), bytes32(uint256(1))),
            "trailing reversal calldata must generic-revert"
        );
        _assertEq(_frozen(address(this)), 1 ether, "reversal stutter");
        adapter.executeRegulatoryReversal(unfreeze);
    }

    function testCanonicalEventOrderAndRevertedTransactionsLeaveNothing() external {
        TrustKernelTypes.ActionRequest memory freeze = _request(TrustKernelTypes.ActionKind.FREEZE, 140, 123 ether);
        vm.recordLogs();
        adapter.executeRegulatoryAction(freeze);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _assert(logs.length >= 2, "logs");
        _assertEq(logs[logs.length - 2].emitter, token, "upstream effect event precedes the receipt");
        _assertEq(logs[logs.length - 2].topics[0], keccak256("TokensFrozen(address,uint256)"), "frozen before receipt");
        _assertEq(logs[logs.length - 1].topics[0], ACTION_APPLIED_TOPIC, "receipt last");

        compliance.setMode(MockERC3643Compliance.Mode.REVERT_CALL);
        TrustKernelTypes.ActionRequest memory request = _request(TrustKernelTypes.ActionKind.CONFISCATE, 141, 7 ether);
        vm.recordLogs();
        (bool ok, bytes memory result) = _call(abi.encodeCall(adapter.executeRegulatoryAction, (request)));
        logs = vm.getRecordedLogs();
        _assert(!ok && _selector(result) == IERCTrustKernel.TrustOperationalFailure.selector, "failure must revert");
        _assertEq(logs.length, 0, "reverted logs");
        _assertEq(adapter.receipt(request.actionId).receiptHash, bytes32(0), "reverted receipt");
        _assert(adapter.actionRecord(request.actionId).lifecycle == TrustKernelTypes.Lifecycle.NONE, "reverted record");
        compliance.setMode(MockERC3643Compliance.Mode.ALLOW);
    }

    function testProfileFreezeTargetIsUnboundedAndUpstreamFloorSaturates() external {
        TrustKernelTypes.ActionRequest memory freeze =
            _request(TrustKernelTypes.ActionKind.FREEZE, 150, SUPPLY + 1 ether);
        adapter.executeRegulatoryAction(freeze);
        _assertEq(_frozen(address(this)), SUPPLY, "upstream saturated floor");
        _assertEq(adapter.actionRecord(freeze.actionId).amount, SUPPLY + 1 ether, "unbounded target record");
        TrustKernelTypes.ActionRequest memory seize = _request(TrustKernelTypes.ActionKind.SEIZE, 151, 1 ether);
        adapter.executeRegulatoryAction(seize);
        _assertEq(_frozen(address(this)), SUPPLY - 1 ether, "outbound resynchronisation");
        _assertEq(_frozen(address(adapter)), 0, "custodian holds no frozen target");
        adapter.executeRegulatoryReversal(_reversal(seize.actionId, TrustKernelTypes.ReversalKind.RELEASE, 152));
        _assertEq(_frozen(address(this)), SUPPLY, "inbound resynchronisation");
        adapter.executeRegulatoryReversal(_reversal(freeze.actionId, TrustKernelTypes.ReversalKind.UNFREEZE, 153));
        _assertEq(_frozen(address(this)), 0, "prior target restore");
    }

    function testKernelVectorsReproduceOnTheAdapterRuntime() external {
        string memory json = vm.readFile("vectors/conformance-v2.json");
        address endpoint = vm.parseJsonAddress(json, ".fixture.endpoint");
        vm.etch(endpoint, address(adapter).code);
        vm.chainId(vm.parseJsonUint(json, ".fixture.chainId"));
        ERC3643TrustAdapter fixture = ERC3643TrustAdapter(endpoint);
        bytes memory identifier = vm.parseJsonBytes(json, ".constants.kernelInterfaceId");
        _assertEq(identifier.length, 4, "interface identifier width");
        // The width was asserted above, so the conversion cannot truncate.
        // forge-lint: disable-next-line(unsafe-typecast)
        _assert(fixture.supportsInterface(bytes4(identifier)), "adapter reports the kernel identifier");
        for (uint256 i = 0; i < 7; ++i) {
            string memory base = string.concat(".actions[", vm.toString(i), "]");
            TrustKernelTypes.ActionRequest memory request = _actionAt(json, string.concat(base, ".request"));
            _assertEq(
                fixture.deriveActionId(request), vm.parseJsonBytes32(json, string.concat(base, ".actionId")), "actionId"
            );
        }
        for (uint256 i = 0; i < 3; ++i) {
            string memory base = string.concat(".reversals[", vm.toString(i), "]");
            TrustKernelTypes.ReversalRequest memory request = _reversalAt(json, string.concat(base, ".request"));
            _assertEq(
                fixture.deriveReversalId(request),
                vm.parseJsonBytes32(json, string.concat(base, ".reversalId")),
                "reversalId"
            );
        }
    }

    // ------------------------------------------------------------------
    // Fixture and request helpers
    // ------------------------------------------------------------------

    function _freshUnit() internal {
        token = _newToken(SUPPLY);
        governor = new ProfileGovernor(token, address(identity), address(compliance), address(this), token.codehash);
        adapter = new ERC3643TrustAdapter(address(governor), address(this), AUTHORITY_REF);
        identity.setVerified(address(adapter), true);
    }

    function _seal(ERC3643ProfileTypes.ImportEntry[] memory entries) internal {
        IFixtureToken(token).setExclusiveAgent(address(adapter));
        IFixtureToken(token).transferOwnership(address(governor));
        governor.seal(address(adapter), entries);
    }

    function _balance(address account) internal view returns (uint256) {
        return IFixtureToken(token).balanceOf(account);
    }

    function _frozen(address account) internal view returns (uint256) {
        return IFixtureToken(token).getFrozenTokens(account);
    }

    function _restricted(address account) internal view returns (bool) {
        return IFixtureToken(token).isFrozen(account);
    }

    function _request(TrustKernelTypes.ActionKind action, uint256 nonce, uint256 amount)
        internal
        view
        returns (TrustKernelTypes.ActionRequest memory request)
    {
        (bytes32 root, uint64 epoch) = adapter.dependencyState();
        request = TrustKernelTypes.ActionRequest({
            domain: DOMAIN,
            actionId: bytes32(0),
            action: action,
            subject: address(this),
            source: address(this),
            destination: address(0),
            custodian: address(0),
            amount: amount,
            caseId: keccak256(abi.encode("PROFILE-CASE", nonce)),
            dependencyRoot: root,
            dependencyEpoch: epoch,
            provenanceCommitment: keccak256(abi.encode("ORDER", nonce)),
            settlementCommitment: bytes32(0),
            proceedsCommitment: bytes32(0),
            entitlementCommitment: bytes32(0),
            authorityRef: AUTHORITY_REF,
            authorityEpoch: 1,
            nonce: nonce,
            validAfter: 0,
            validBefore: type(uint48).max
        });
        if (action == TrustKernelTypes.ActionKind.SEIZE) {
            request.destination = address(adapter);
            request.custodian = address(adapter);
        } else if (action == TrustKernelTypes.ActionKind.CONFISCATE) {
            request.destination = buyer;
        } else if (action == TrustKernelTypes.ActionKind.LIQUIDATE) {
            request.destination = buyer;
            request.settlementCommitment = keccak256(abi.encode("SETTLEMENT", nonce));
            request.proceedsCommitment = keccak256(abi.encode("PROCEEDS", nonce));
        } else if (action == TrustKernelTypes.ActionKind.RECOVER) {
            request.destination = recovered;
            request.entitlementCommitment = keccak256(abi.encode("ENTITLEMENT", nonce));
        }
        request.actionId = adapter.deriveActionId(request);
    }

    function _reversal(bytes32 actionId, TrustKernelTypes.ReversalKind reversal, uint256 nonce)
        internal
        view
        returns (TrustKernelTypes.ReversalRequest memory request)
    {
        (bytes32 root, uint64 epoch) = adapter.dependencyState();
        request = TrustKernelTypes.ReversalRequest({
            domain: DOMAIN,
            reversalId: bytes32(0),
            actionId: actionId,
            reversal: reversal,
            dependencyRoot: root,
            dependencyEpoch: epoch,
            provenanceCommitment: keccak256(abi.encode("REVERSAL-ORDER", nonce)),
            authorityRef: AUTHORITY_REF,
            authorityEpoch: 1,
            nonce: nonce,
            validAfter: 0,
            validBefore: type(uint48).max
        });
        request.reversalId = adapter.deriveReversalId(request);
    }

    /// @dev Custody disposition of `seize` in the same case: source is the custodian, subject the prior holder.
    function _custodyDisposition(
        TrustKernelTypes.ActionKind action,
        TrustKernelTypes.ActionRequest memory seize,
        uint256 nonce
    ) internal view returns (TrustKernelTypes.ActionRequest memory request) {
        request = _request(action, nonce, seize.amount);
        request.caseId = seize.caseId;
        request.subject = seize.subject;
        request.source = seize.custodian;
        request.actionId = adapter.deriveActionId(request);
    }

    function _sealedBinding(bytes32 manifestHash) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                SEAL_DOMAIN,
                block.chainid,
                address(governor),
                token,
                token.codehash,
                address(adapter),
                address(identity),
                address(compliance),
                manifestHash
            )
        );
    }

    function _expectedBinding(uint256 kind, bytes32 binding) internal view returns (bytes32) {
        if (kind >= 2) return bytes32(0);
        address dependency = kind == 0 ? address(compliance) : address(identity);
        return keccak256(abi.encode(DOMAIN, kind, dependency, dependency.codehash, binding, PROFILE_ID, uint64(1)));
    }

    function _expectedRoot(bytes32 binding) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                DOMAIN,
                TrustKernelTypes.DEPENDENCY_ROOT_TAG,
                _expectedBinding(0, binding),
                _expectedBinding(1, binding),
                bytes32(0),
                bytes32(0)
            )
        );
    }

    function _importCaseId(bytes32 manifestHash, address account, TrustKernelTypes.CaseFamily family)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(DOMAIN, IMPORT_TAG, manifestHash, account, uint8(family)));
    }

    function _importActionId(bytes32 caseId) internal pure returns (bytes32) {
        return keccak256(abi.encode(DOMAIN, IMPORT_TAG, caseId));
    }

    // ------------------------------------------------------------------
    // Indexer-style recomputation
    // ------------------------------------------------------------------

    function _recomputeReceiptHash(TrustKernelTypes.Receipt memory r) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                DOMAIN,
                uint8(r.receiptKind),
                r.commandId,
                r.commandKind,
                r.parentCommandId,
                r.subject,
                r.source,
                r.destination,
                r.amount,
                r.caseId,
                r.authorityRef,
                r.dependencyRoot,
                r.provenanceCommitment,
                r.assessmentEvidence,
                r.preState,
                r.postState,
                r.externalCommitment
            )
        );
    }

    function _recomputeCommandHash(TrustKernelTypes.ActionRequest memory request) internal view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN, address(adapter), block.chainid, request));
    }

    function _checkActionReceipt(TrustKernelTypes.ActionRequest memory request, bytes32 returned) internal view {
        TrustKernelTypes.Receipt memory r = adapter.receipt(request.actionId);
        _assertEq(r.receiptHash, returned, "returned hash equals stored hash");
        _assertEq(_recomputeReceiptHash(r), returned, "indexer recomputation");
        _assert(r.receiptKind == TrustKernelTypes.ReceiptKind.ACTION, "action kind tag");
        _assertEq(r.commandId, request.actionId, "receipt command id");
        _assertEq(uint256(r.commandKind), uint256(uint8(request.action)), "receipt command kind");
        _assertEq(r.caseId, request.caseId, "receipt case");
        _assertEq(r.destination, request.destination, "receipt destination");
        _assertEq(r.authorityRef, AUTHORITY_REF, "receipt authority");
        TrustKernelTypes.ActionRecord memory record = adapter.actionRecord(request.actionId);
        _assertEq(record.receiptHash, returned, "record receipt hash");
        _assert(record.lifecycle == TrustKernelTypes.Lifecycle.APPLIED, "applied lifecycle");
        _assertEq(record.commandHash, _recomputeCommandHash(request), "record command hash");
    }

    function _checkReversalReceipt(
        TrustKernelTypes.ReversalRequest memory request,
        bytes32 returned,
        address source,
        address destination
    ) internal view {
        TrustKernelTypes.Receipt memory r = adapter.receipt(request.reversalId);
        _assertEq(r.receiptHash, returned, "reversal returned hash equals stored hash");
        _assertEq(_recomputeReceiptHash(r), returned, "reversal indexer recomputation");
        _assert(r.receiptKind == TrustKernelTypes.ReceiptKind.REVERSAL, "reversal kind tag");
        _assertEq(r.commandId, request.reversalId, "reversal command id");
        _assertEq(uint256(r.commandKind), uint256(uint8(request.reversal)), "reversal command kind");
        _assertEq(r.parentCommandId, request.actionId, "reversal parent");
        _assertEq(r.source, source, "reversal source");
        _assertEq(r.destination, destination, "reversal destination");
        _assertEq(r.externalCommitment, bytes32(0), "reversal external commitment");
        _assert(
            adapter.actionRecord(request.actionId).lifecycle == TrustKernelTypes.Lifecycle.REVERSED,
            "reversed lifecycle"
        );
    }

    function _checkCase(
        bytes32 caseId,
        TrustKernelTypes.CasePhase phase,
        TrustKernelTypes.CaseFamily family,
        bytes32 head,
        uint64 generation
    ) internal view {
        TrustKernelTypes.CaseRecord memory record = adapter.caseRecord(caseId);
        _assert(record.phase == phase, "case phase");
        _assert(record.family == family, "case family");
        _assertEq(record.headActionId, head, "case head");
        _assertEq(record.generation, generation, "case generation");
    }

    function _actionAt(string memory json, string memory base)
        internal
        pure
        returns (TrustKernelTypes.ActionRequest memory request)
    {
        request.domain = vm.parseJsonBytes32(json, string.concat(base, ".domain"));
        request.actionId = vm.parseJsonBytes32(json, string.concat(base, ".actionId"));
        request.action = TrustKernelTypes.ActionKind(uint8(vm.parseJsonUint(json, string.concat(base, ".action"))));
        request.subject = vm.parseJsonAddress(json, string.concat(base, ".subject"));
        request.source = vm.parseJsonAddress(json, string.concat(base, ".source"));
        request.destination = vm.parseJsonAddress(json, string.concat(base, ".destination"));
        request.custodian = vm.parseJsonAddress(json, string.concat(base, ".custodian"));
        request.amount = vm.parseJsonUint(json, string.concat(base, ".amount"));
        request.caseId = vm.parseJsonBytes32(json, string.concat(base, ".caseId"));
        request.dependencyRoot = vm.parseJsonBytes32(json, string.concat(base, ".dependencyRoot"));
        request.dependencyEpoch = uint64(vm.parseJsonUint(json, string.concat(base, ".dependencyEpoch")));
        request.provenanceCommitment = vm.parseJsonBytes32(json, string.concat(base, ".provenanceCommitment"));
        request.settlementCommitment = vm.parseJsonBytes32(json, string.concat(base, ".settlementCommitment"));
        request.proceedsCommitment = vm.parseJsonBytes32(json, string.concat(base, ".proceedsCommitment"));
        request.entitlementCommitment = vm.parseJsonBytes32(json, string.concat(base, ".entitlementCommitment"));
        request.authorityRef = vm.parseJsonBytes32(json, string.concat(base, ".authorityRef"));
        request.authorityEpoch = uint64(vm.parseJsonUint(json, string.concat(base, ".authorityEpoch")));
        request.nonce = vm.parseJsonUint(json, string.concat(base, ".nonce"));
        request.validAfter = uint48(vm.parseJsonUint(json, string.concat(base, ".validAfter")));
        request.validBefore = uint48(vm.parseJsonUint(json, string.concat(base, ".validBefore")));
    }

    function _reversalAt(string memory json, string memory base)
        internal
        pure
        returns (TrustKernelTypes.ReversalRequest memory request)
    {
        request.domain = vm.parseJsonBytes32(json, string.concat(base, ".domain"));
        request.reversalId = vm.parseJsonBytes32(json, string.concat(base, ".reversalId"));
        request.actionId = vm.parseJsonBytes32(json, string.concat(base, ".actionId"));
        request.reversal =
            TrustKernelTypes.ReversalKind(uint8(vm.parseJsonUint(json, string.concat(base, ".reversal"))));
        request.dependencyRoot = vm.parseJsonBytes32(json, string.concat(base, ".dependencyRoot"));
        request.dependencyEpoch = uint64(vm.parseJsonUint(json, string.concat(base, ".dependencyEpoch")));
        request.provenanceCommitment = vm.parseJsonBytes32(json, string.concat(base, ".provenanceCommitment"));
        request.authorityRef = vm.parseJsonBytes32(json, string.concat(base, ".authorityRef"));
        request.authorityEpoch = uint64(vm.parseJsonUint(json, string.concat(base, ".authorityEpoch")));
        request.nonce = vm.parseJsonUint(json, string.concat(base, ".nonce"));
        request.validAfter = uint48(vm.parseJsonUint(json, string.concat(base, ".validAfter")));
        request.validBefore = uint48(vm.parseJsonUint(json, string.concat(base, ".validBefore")));
    }

    // ------------------------------------------------------------------
    // Revert inspection
    // ------------------------------------------------------------------

    function _call(bytes memory data) internal returns (bool ok, bytes memory result) {
        (ok, result) = address(adapter).call(data);
    }

    function _selector(bytes memory data) internal pure returns (bytes4 result) {
        if (data.length < 4) return bytes4(0);
        assembly ("memory-safe") {
            result := mload(add(data, 0x20))
        }
    }

    function _reasonOf(bytes memory data) internal pure returns (uint16 reason) {
        require(data.length >= 4 + 64, "no reason payload");
        assembly ("memory-safe") {
            reason := mload(add(data, 0x44))
        }
    }

    function _wordAt(bytes memory data, uint256 index) internal pure returns (bytes32 word) {
        require(data.length >= 4 + 32 * (index + 1), "short payload");
        assembly ("memory-safe") {
            word := mload(add(add(data, 0x24), mul(index, 0x20)))
        }
    }

    function _expectInvalid(bytes memory data, uint16 reason, string memory message) internal {
        (bool ok, bytes memory result) = _call(data);
        require(!ok, message);
        require(_selector(result) == IERCTrustKernel.TrustInvalidCommand.selector, message);
        require(_reasonOf(result) == reason, message);
    }

    function _expectRejected(bytes memory data, uint16 reason, string memory message) internal {
        (bool ok, bytes memory result) = _call(data);
        require(!ok, message);
        require(_selector(result) == IERCTrustKernel.TrustRejected.selector, message);
        require(_reasonOf(result) == reason, message);
    }

    function _expectOperationalFailure(bytes memory data, uint16 reason, string memory message) internal {
        (bool ok, bytes memory result) = _call(data);
        require(!ok, message);
        require(_selector(result) == IERCTrustKernel.TrustOperationalFailure.selector, message);
        require(_reasonOf(result) == reason, message);
        require(_wordAt(result, 2) != bytes32(0), "dependency reference carried");
    }

    function _expectTerminal(bytes memory data, bytes32 caseId, string memory message) internal {
        (bool ok, bytes memory result) = _call(data);
        require(!ok, message);
        require(_selector(result) == IERCTrustKernel.TrustTerminal.selector, message);
        require(_wordAt(result, 0) == caseId, message);
    }

    function _expectSelector(bytes memory data, bytes4 selector, string memory message) internal {
        (bool ok, bytes memory result) = _call(data);
        require(!ok, message);
        require(_selector(result) == selector, message);
    }

    function _expectGenericRevert(bytes memory data, string memory message) internal {
        (bool ok, bytes memory result) = _call(data);
        _assert(!ok && result.length == 0, message);
    }

    function _expectDependencyFailure(
        bool identityLane,
        MockERC3643IdentityRegistry.Mode mode,
        uint16 reason,
        string memory message
    ) internal {
        if (identityLane) identity.setMode(mode);
        else compliance.setMode(MockERC3643Compliance.Mode(uint8(mode)));
        TrustKernelTypes.ActionRequest memory request = _request(TrustKernelTypes.ActionKind.CONFISCATE, 33, 4 ether);
        (bool ok, bytes memory result) = _call(abi.encodeCall(adapter.executeRegulatoryAction, (request)));
        require(!ok, message);
        require(_selector(result) == IERCTrustKernel.TrustOperationalFailure.selector, message);
        require(_reasonOf(result) == reason, message);
        address expected = identityLane ? address(identity) : address(compliance);
        require(address(uint160(uint256(_wordAt(result, 2)))) == expected, "dependency reference");
        require(adapter.actionRecord(request.actionId).lifecycle == TrustKernelTypes.Lifecycle.NONE, message);
    }

    function _expectDirtyWordRejected(
        TrustKernelTypes.ActionRequest memory request,
        uint256 word,
        string memory message
    ) internal {
        bytes memory dirty = abi.encodeCall(adapter.executeRegulatoryAction, (request));
        dirty[4 + 32 * word] = 0x01;
        bytes32 dirtyId = _rawActionId(dirty);
        for (uint256 i = 0; i < 32; ++i) {
            dirty[4 + 32 + i] = dirtyId[i];
        }
        _expectGenericRevert(dirty, message);
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
        return keccak256(bytes.concat(abi.encode(DOMAIN, address(adapter), block.chainid), words));
    }

    function _assert(bool condition, string memory message) internal pure {
        require(condition, message);
    }

    function _assertEq(uint256 left, uint256 right, string memory message) internal pure {
        require(left == right, message);
    }

    function _assertEq(bytes32 left, bytes32 right, string memory message) internal pure {
        require(left == right, message);
    }

    function _assertEq(address left, address right, string memory message) internal pure {
        require(left == right, message);
    }
}

/// @notice The whole profile suite against the clean-room fixture whose forced transfer does not unfreeze,
///         plus the typed upstream failure modes only that fixture can switch on.
contract ERC3643ProfileUnitTest is ERC3643ProfileTestBase {
    function _newToken(uint256 supply) internal override returns (address) {
        return address(new MockERC3643Token(address(identity), address(compliance), supply));
    }

    function _seedLegacy(address account, uint256 balance, uint256 frozenAmount, bool restricted) internal override {
        MockERC3643Token(token).seedLegacyState(account, balance, frozenAmount, restricted);
    }

    function testUpstreamFailureModesAreTyped() external {
        MockERC3643Token fixture = MockERC3643Token(token);
        uint256 before = _balance(address(this));

        fixture.setMode(MockERC3643Token.Mode.TRANSFER_RETURNS_FALSE);
        _expectUpstream(
            _request(TrustKernelTypes.ActionKind.CONFISCATE, 160, 1 ether), 400, "forced transfer returns false"
        );
        fixture.setMode(MockERC3643Token.Mode.TRANSFER_NO_EFFECT);
        _expectUpstream(
            _request(TrustKernelTypes.ActionKind.CONFISCATE, 161, 1 ether), 401, "forced transfer without effect"
        );
        fixture.setMode(MockERC3643Token.Mode.FREEZE_NO_EFFECT);
        _expectUpstream(_request(TrustKernelTypes.ActionKind.FREEZE, 162, 1 ether), 401, "freeze without effect");
        fixture.setMode(MockERC3643Token.Mode.RESTRICT_NO_EFFECT);
        _expectUpstream(_request(TrustKernelTypes.ActionKind.RESTRICT, 163, 0), 401, "address freeze without effect");
        fixture.setMode(MockERC3643Token.Mode.FROZEN_VIEW_REVERTS);
        _expectUpstream(_request(TrustKernelTypes.ActionKind.FREEZE, 164, 1 ether), 400, "frozen view reverts");
        fixture.setMode(MockERC3643Token.Mode.FROZEN_VIEW_LONG);
        _expectUpstream(
            _request(TrustKernelTypes.ActionKind.FREEZE, 165, 1 ether), 400, "frozen view returns two words"
        );
        fixture.setMode(MockERC3643Token.Mode.NORMAL);

        _assertEq(_balance(address(this)), before, "upstream failures stutter");
        _assertEq(_balance(buyer), 0, "nothing moved");
        _assertEq(_frozen(address(this)), 0, "nothing frozen");
        _assert(!_restricted(address(this)), "nothing restricted");
        adapter.executeRegulatoryAction(_request(TrustKernelTypes.ActionKind.CONFISCATE, 166, 1 ether));
        _assertEq(_balance(buyer), 1 ether, "restored upstream admits the command");
    }

    function _expectUpstream(TrustKernelTypes.ActionRequest memory request, uint16 reason, string memory message)
        internal
    {
        (bool ok, bytes memory result) = _call(abi.encodeCall(adapter.executeRegulatoryAction, (request)));
        require(!ok, message);
        require(_selector(result) == IERCTrustKernel.TrustOperationalFailure.selector, message);
        require(_reasonOf(result) == reason, message);
        require(address(uint160(uint256(_wordAt(result, 2)))) == token, "token reference");
        require(adapter.actionRecord(request.actionId).lifecycle == TrustKernelTypes.Lifecycle.NONE, message);
        require(adapter.receipt(request.actionId).receiptHash == bytes32(0), message);
    }
}
