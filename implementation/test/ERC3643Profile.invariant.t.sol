// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustKernelTypes} from "../src/generated/IERCTrustKernel.sol";
import {ERC3643TrustAdapter} from "../src/profiles/ERC3643TrustAdapter.sol";
import {ProfileGovernor} from "../src/profiles/ProfileGovernor.sol";
import {ERC3643ProfileTypes} from "../src/profiles/ERC3643ProfileTypes.sol";
import {MockERC3643TokenTrex} from "./mocks/MockERC3643TokenTrex.sol";
import {MockERC3643IdentityRegistry, MockERC3643Compliance} from "./mocks/MockERC3643Dependencies.sol";

/// @dev A second holder that can send tokens back to the handler, so that the campaign reaches balance
///      growth between two adapter touches.
contract ERC3643ProfileSink {
    MockERC3643TokenTrex internal immutable token;

    constructor(MockERC3643TokenTrex token_) {
        token = token_;
    }

    function sendBack(address to, uint256 amount) external {
        require(token.transfer(to, amount), "send back");
    }
}

/// @dev Owns the conformance unit as bootstrap authority, initial holder, and regulatory authority so that
///      the stateful campaign drives the adapter's state machine (freeze amendments, unfreeze, seizure,
///      release, custody confiscation), the ordinary ERC-3643 transfer surface in both directions, and
///      the permissionless resynchronisation together.
contract ERC3643ProfileHandler {
    bytes32 internal constant AUTHORITY_REF = keccak256("HANDLER-AUTHORITY");

    MockERC3643TokenTrex public immutable token;
    ProfileGovernor public immutable governor;
    ERC3643TrustAdapter public immutable adapter;
    ERC3643ProfileSink public immutable sink;

    bytes32 public freezeCase;
    bytes32[] internal freezeHeads;
    uint256[] internal priorTargets;
    uint256 public frozenTarget;
    /// @dev True while the handler's balance grew since the adapter last synchronised its frozen amount.
    bool public pendingInbound;

    bytes32 public custodyCase;
    bytes32 public custodyAction;
    uint256 public custodyAmount;

    uint256 internal nonce = 1;
    uint256 internal caseSerial;

    constructor(MockERC3643IdentityRegistry identity, MockERC3643Compliance compliance) {
        token = new MockERC3643TokenTrex(address(identity), address(compliance), 1_000_000 ether);
        governor = new ProfileGovernor(
            address(token), address(identity), address(compliance), address(this), address(token).codehash
        );
        adapter = new ERC3643TrustAdapter(address(governor), address(this), AUTHORITY_REF);
        sink = new ERC3643ProfileSink(token);
        identity.setVerified(address(this), true);
        identity.setVerified(address(adapter), true);
        identity.setVerified(address(sink), true);
        token.setExclusiveAgent(address(adapter));
        token.transferOwnership(address(governor));
        ERC3643ProfileTypes.ImportEntry[] memory none;
        governor.seal(address(adapter), none);
    }

    function liveFreezeHeads() external view returns (uint256) {
        return freezeHeads.length;
    }

    // ------------------------------------------------------------------
    // Ordinary surface in both directions
    // ------------------------------------------------------------------

    function transferBounded(uint96 rawAmount) external {
        uint256 balance = token.balanceOf(address(this));
        uint256 frozen = token.getFrozenTokens(address(this));
        uint256 unfrozen = frozen >= balance ? 0 : balance - frozen;
        uint256 amount = unfrozen == 0 ? 0 : uint256(rawAmount) % (unfrozen + 1);
        if (amount == 0) return;
        require(token.transfer(address(sink), amount), "transfer");
    }

    function inboundBounded(uint96 rawAmount) external {
        uint256 held = token.balanceOf(address(sink));
        if (held == 0 || token.isFrozen(address(this))) return;
        uint256 amount = (uint256(rawAmount) % held) + 1;
        sink.sendBack(address(this), amount);
        pendingInbound = true;
    }

    function resynchronise() external {
        adapter.resynchroniseFrozen(address(this));
        pendingInbound = false;
    }

    function rawAgentSelectors(uint96 rawAmount) external {
        (bool freezeOk,) =
            address(token).call(abi.encodeCall(token.freezePartialTokens, (address(this), uint256(rawAmount))));
        (bool transferOk,) = address(token)
            .call(abi.encodeCall(token.forcedTransfer, (address(this), address(sink), uint256(rawAmount))));
        (bool agentOk,) = address(token).call(abi.encodeCall(token.addAgent, (address(this))));
        require(!freezeOk && !transferOk && !agentOk, "raw upstream surface unexpectedly open");
    }

    // ------------------------------------------------------------------
    // Regulatory surface: the handler is the authority
    // ------------------------------------------------------------------

    function freezeRaise(uint96 rawAmount) external {
        if (freezeHeads.length == 0) freezeCase = keccak256(abi.encode("HANDLER-FREEZE", ++caseSerial));
        uint256 target = frozenTarget + (uint256(rawAmount) % 1_000 ether) + 1;
        bytes32 actionId = _build(
            TrustKernelTypes.ActionKind.FREEZE, freezeCase, address(this), address(this), address(0), address(0), target
        );
        freezeHeads.push(actionId);
        priorTargets.push(frozenTarget);
        frozenTarget = target;
        pendingInbound = false;
    }

    function unfreezeHead() external {
        if (freezeHeads.length == 0) return;
        bytes32 head = freezeHeads[freezeHeads.length - 1];
        freezeHeads.pop();
        frozenTarget = priorTargets[priorTargets.length - 1];
        priorTargets.pop();
        _reverse(head, TrustKernelTypes.ReversalKind.UNFREEZE);
        pendingInbound = false;
    }

    function seizeBounded(uint96 rawAmount) external {
        if (custodyAction != bytes32(0)) return;
        uint256 balance = token.balanceOf(address(this));
        if (balance == 0) return;
        uint256 amount = (uint256(rawAmount) % balance) + 1;
        custodyCase = keccak256(abi.encode("HANDLER-CUSTODY", ++caseSerial));
        custodyAction = _build(
            TrustKernelTypes.ActionKind.SEIZE,
            custodyCase,
            address(this),
            address(this),
            address(adapter),
            address(adapter),
            amount
        );
        custodyAmount = amount;
        pendingInbound = false;
    }

    function releaseCustody() external {
        if (custodyAction == bytes32(0)) return;
        bytes32 seizure = custodyAction;
        custodyAction = bytes32(0);
        custodyAmount = 0;
        _reverse(seizure, TrustKernelTypes.ReversalKind.RELEASE);
        pendingInbound = false;
    }

    function confiscateCustody() external {
        if (custodyAction == bytes32(0)) return;
        uint256 amount = custodyAmount;
        custodyAction = bytes32(0);
        custodyAmount = 0;
        _build(
            TrustKernelTypes.ActionKind.CONFISCATE,
            custodyCase,
            address(this),
            address(adapter),
            address(sink),
            address(0),
            amount
        );
    }

    function _build(
        TrustKernelTypes.ActionKind action,
        bytes32 caseId,
        address subject,
        address source,
        address destination,
        address custodian,
        uint256 amount
    ) internal returns (bytes32 actionId) {
        (bytes32 root, uint64 epoch) = adapter.dependencyState();
        TrustKernelTypes.ActionRequest memory request;
        request.domain = TrustKernelTypes.DOMAIN;
        request.action = action;
        request.subject = subject;
        request.source = source;
        request.destination = destination;
        request.custodian = custodian;
        request.amount = amount;
        request.caseId = caseId;
        request.dependencyRoot = root;
        request.dependencyEpoch = epoch;
        request.provenanceCommitment = keccak256(abi.encode("HANDLER-PROVENANCE", nonce));
        request.authorityRef = AUTHORITY_REF;
        request.authorityEpoch = 1;
        request.nonce = nonce++;
        request.validAfter = 0;
        request.validBefore = type(uint48).max;
        request.actionId = adapter.deriveActionId(request);
        actionId = request.actionId;
        adapter.executeRegulatoryAction(request);
    }

    function _reverse(bytes32 actionId, TrustKernelTypes.ReversalKind reversal) internal {
        (bytes32 root, uint64 epoch) = adapter.dependencyState();
        TrustKernelTypes.ReversalRequest memory request;
        request.domain = TrustKernelTypes.DOMAIN;
        request.actionId = actionId;
        request.reversal = reversal;
        request.dependencyRoot = root;
        request.dependencyEpoch = epoch;
        request.provenanceCommitment = keccak256(abi.encode("HANDLER-REVERSAL", nonce));
        request.authorityRef = AUTHORITY_REF;
        request.authorityEpoch = 1;
        request.nonce = nonce++;
        request.validAfter = 0;
        request.validBefore = type(uint48).max;
        request.reversalId = adapter.deriveReversalId(request);
        adapter.executeRegulatoryReversal(request);
    }
}

contract ERC3643ProfileInvariantTest {
    MockERC3643IdentityRegistry internal identity;
    MockERC3643Compliance internal compliance;
    ERC3643ProfileHandler internal handler;
    MockERC3643TokenTrex internal token;
    ERC3643TrustAdapter internal adapter;
    address internal sink;
    address[] internal targets;

    function setUp() public {
        identity = new MockERC3643IdentityRegistry();
        compliance = new MockERC3643Compliance();
        handler = new ERC3643ProfileHandler(identity, compliance);
        token = handler.token();
        adapter = handler.adapter();
        sink = address(handler.sink());
        targets.push(address(handler));
    }

    function targetContracts() external view returns (address[] memory) {
        return targets;
    }

    function invariantSupplyConserved() external view {
        uint256 accounted =
            token.balanceOf(address(handler)) + token.balanceOf(sink) + token.balanceOf(address(adapter));
        require(accounted == token.totalSupply(), "supply conservation");
    }

    /// @dev The upstream frozen amount of an owned account never exceeds the owned target saturated at the
    ///      balance, always equals the amount the adapter recorded as applied, and equals the saturated
    ///      target itself whenever the balance did not grow since the adapter last touched the account.
    function invariantUpstreamFrozenTracksTheOwnedTarget() external view {
        uint256 balance = token.balanceOf(address(handler));
        uint256 target = handler.frozenTarget();
        uint256 saturated = target > balance ? balance : target;
        uint256 frozen = token.getFrozenTokens(address(handler));
        (uint256 ownedTarget, uint256 applied,) = adapter.ownedState(address(handler));
        require(ownedTarget == target, "owned target mirrors the handler");
        require(frozen == applied, "upstream frozen amount is exactly the applied amount");
        require(frozen <= saturated, "never frozen beyond the saturated target");
        if (!handler.pendingInbound()) require(frozen == saturated, "saturated target after every touch");
        require(token.getFrozenTokens(address(adapter)) == 0, "custodian never frozen");
        if (handler.liveFreezeHeads() == 0) {
            require(target == 0, "no live head means no target");
        } else {
            TrustKernelTypes.CaseRecord memory freezeCase = adapter.caseRecord(handler.freezeCase());
            require(freezeCase.phase == TrustKernelTypes.CasePhase.OPEN, "freeze case open while heads are live");
            require(freezeCase.family == TrustKernelTypes.CaseFamily.FREEZE, "freeze family");
        }
    }

    function invariantCustodyCaseMatchesTheHandler() external view {
        bytes32 custodyCase = handler.custodyCase();
        if (custodyCase == bytes32(0)) return;
        TrustKernelTypes.CaseRecord memory record = adapter.caseRecord(custodyCase);
        if (handler.custodyAction() != bytes32(0)) {
            require(record.phase == TrustKernelTypes.CasePhase.OPEN, "custody case open while seized");
            require(record.family == TrustKernelTypes.CaseFamily.CUSTODY, "custody family");
            require(record.headActionId == handler.custodyAction(), "custody head");
            require(token.balanceOf(address(adapter)) == handler.custodyAmount(), "adapter holds exactly the backing");
        } else {
            require(record.phase == TrustKernelTypes.CasePhase.TERMINAL, "custody case terminal after disposition");
            require(token.balanceOf(address(adapter)) == 0, "no stranded custody");
        }
    }

    function invariantSealedTopologyStaysLiveAndDescriptorStaysPartial() external view {
        TrustKernelTypes.ProfileDescriptor memory descriptor = adapter.trustProfile();
        require(descriptor.profileKind == TrustKernelTypes.ProfileKind.PARTIAL, "partial kind");
        require(!descriptor.full, "never full");
        require(adapter.sealedTopologyLive(), "sealed topology live");
        require(adapter.supportsInterface(0x2b020308), "kernel truth");
        require(!adapter.supportsInterface(0xffffffff), "invalid interface");
        require(token.isAgent(address(adapter)) && !token.isAgent(address(handler)), "exclusive agent");
    }
}
