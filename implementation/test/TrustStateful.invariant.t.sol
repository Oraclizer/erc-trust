// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustTestBase} from "./TrustTestBase.t.sol";
import {TrustToken} from "../src/TrustToken.sol";
import {TrustKernelTypes} from "../src/generated/IERCTrustKernel.sol";
import {MockBoundDependency} from "./mocks/MockBoundDependency.sol";

/// @dev Owns the token as governor, initial holder, and regulatory authority so that the stateful
///      campaign drives the kernel state machine (freeze amendments, unfreeze, seizure, release,
///      custody confiscation) and not only the ERC-20 surface.
contract TrustRegulatoryHandler {
    bytes32 internal constant AUTHORITY_REF = keccak256("HANDLER-AUTHORITY");

    TrustToken public immutable token;
    address public immutable sink;
    address public immutable custodian;

    bytes32 public freezeCase;
    bytes32[] internal freezeHeads;
    uint256[] internal priorTargets;
    uint256 public frozenTarget;

    bytes32 public custodyCase;
    bytes32 public custodyAction;
    uint256 public custodyAmount;

    uint256 internal nonce = 1;
    uint256 internal caseSerial;

    constructor(MockBoundDependency dependency, address sink_, address custodian_) {
        token = new TrustToken(
            "ERC-TRUST Reference",
            "TRUST",
            18,
            address(this),
            address(this),
            1_000_000 ether,
            AUTHORITY_REF,
            address(this),
            address(dependency),
            address(dependency),
            address(dependency),
            address(dependency),
            keccak256("SCHEMA-V2")
        );
        sink = sink_;
        custodian = custodian_;
    }

    function liveFreezeHeads() external view returns (uint256) {
        return freezeHeads.length;
    }

    // ------------------------------------------------------------------
    // Ordinary surface
    // ------------------------------------------------------------------

    function transferBounded(uint96 rawAmount) external {
        uint256 balance = token.balanceOf(address(this));
        uint256 frozen = token.getFrozenTokens(address(this));
        uint256 unfrozen = frozen >= balance ? 0 : balance - frozen;
        uint256 amount = unfrozen == 0 ? 0 : uint256(rawAmount) % (unfrozen + 1);
        require(token.transfer(sink, amount), "transfer");
    }

    function approveBounded(uint96 rawAmount) external {
        token.approve(sink, uint256(rawAmount));
    }

    function rawSensitiveSelectors(uint96 rawAmount) external {
        (bool freezeOk,) =
            address(token).call(abi.encodeCall(token.setFrozenTokens, (address(this), uint256(rawAmount))));
        (bool transferOk,) =
            address(token).call(abi.encodeCall(token.forcedTransfer, (address(this), sink, uint256(rawAmount))));
        require(!freezeOk && !transferOk, "raw sensitive route unexpectedly open");
    }

    // ------------------------------------------------------------------
    // Regulatory surface: the handler is the authority
    // ------------------------------------------------------------------

    /// @dev Opens a freeze case or amends the live head of the open one with a strictly higher target.
    function freezeRaise(uint96 rawAmount) external {
        if (freezeHeads.length == 0) freezeCase = keccak256(abi.encode("HANDLER-FREEZE", ++caseSerial));
        uint256 target = frozenTarget + (uint256(rawAmount) % 1_000 ether) + 1;
        bytes32 actionId = _build(
            TrustKernelTypes.ActionKind.FREEZE, freezeCase, address(this), address(this), address(0), address(0), target
        );
        freezeHeads.push(actionId);
        priorTargets.push(frozenTarget);
        frozenTarget = target;
    }

    /// @dev Reverses the live freeze head; the stored target returns to the value before that head.
    function unfreezeHead() external {
        if (freezeHeads.length == 0) return;
        bytes32 head = freezeHeads[freezeHeads.length - 1];
        freezeHeads.pop();
        frozenTarget = priorTargets[priorTargets.length - 1];
        priorTargets.pop();
        _reverse(head, TrustKernelTypes.ReversalKind.UNFREEZE);
    }

    /// @dev Seizes part of the handler balance into custody in a fresh case.
    function seizeBounded(uint96 rawAmount) external {
        if (custodyAction != bytes32(0)) return;
        uint256 balance = token.balanceOf(address(this));
        if (balance == 0) return;
        uint256 amount = (uint256(rawAmount) % balance) + 1;
        custodyCase = keccak256(abi.encode("HANDLER-CUSTODY", ++caseSerial));
        custodyAction = _build(
            TrustKernelTypes.ActionKind.SEIZE, custodyCase, address(this), address(this), custodian, custodian, amount
        );
        custodyAmount = amount;
    }

    /// @dev Returns the seized amount to the prior holder and closes the custody case.
    function releaseCustody() external {
        if (custodyAction == bytes32(0)) return;
        bytes32 seizure = custodyAction;
        custodyAction = bytes32(0);
        custodyAmount = 0;
        _reverse(seizure, TrustKernelTypes.ReversalKind.RELEASE);
    }

    /// @dev Disposes of the custody in the same case: the custodian is the source, the handler the prior holder.
    function confiscateCustody() external {
        if (custodyAction == bytes32(0)) return;
        uint256 amount = custodyAmount;
        custodyAction = bytes32(0);
        custodyAmount = 0;
        _build(TrustKernelTypes.ActionKind.CONFISCATE, custodyCase, address(this), custodian, sink, address(0), amount);
    }

    function _build(
        TrustKernelTypes.ActionKind action,
        bytes32 caseId,
        address subject,
        address source,
        address destination,
        address custodian_,
        uint256 amount
    ) internal returns (bytes32 actionId) {
        (bytes32 root, uint64 epoch) = token.dependencyState();
        TrustKernelTypes.ActionRequest memory request;
        request.domain = TrustKernelTypes.DOMAIN;
        request.action = action;
        request.subject = subject;
        request.source = source;
        request.destination = destination;
        request.custodian = custodian_;
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
        request.actionId = token.deriveActionId(request);
        actionId = request.actionId;
        token.executeRegulatoryAction(request);
    }

    function _reverse(bytes32 actionId, TrustKernelTypes.ReversalKind reversal) internal {
        (bytes32 root, uint64 epoch) = token.dependencyState();
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
        request.reversalId = token.deriveReversalId(request);
        token.executeRegulatoryReversal(request);
    }
}

contract TrustStatefulInvariantTest is TrustTestBase {
    TrustRegulatoryHandler internal handler;
    address internal sink = address(0xA11CE);
    address internal keeper = address(0xC0DE);
    address[] internal targets;

    function setUp() public override {
        super.setUp();
        handler = new TrustRegulatoryHandler(dependency, sink, keeper);
        token = handler.token();
        targets.push(address(handler));
    }

    function targetContracts() external view returns (address[] memory) {
        return targets;
    }

    function invariantSupplyConserved() external view {
        uint256 accounted = token.balanceOf(address(handler)) + token.balanceOf(sink) + token.balanceOf(keeper);
        _assertEq(accounted, token.totalSupply(), "supply conservation");
    }

    function invariantNoPersistentRouteTicket() external view {
        _assert(!_routeLive(), "ephemeral route");
    }

    function invariantFrozenTargetTracksTheLiveHead() external view {
        uint256 balance = token.balanceOf(address(handler));
        uint256 target = handler.frozenTarget();
        _assertEq(token.getFrozenTokens(address(handler)), target > balance ? balance : target, "saturated target");
        if (handler.liveFreezeHeads() == 0) {
            _assertEq(target, 0, "no live head means no target");
        } else {
            TrustKernelTypes.CaseRecord memory freezeCase = token.caseRecord(handler.freezeCase());
            _assert(freezeCase.phase == TrustKernelTypes.CasePhase.OPEN, "freeze case open while heads are live");
            _assert(freezeCase.family == TrustKernelTypes.CaseFamily.FREEZE, "freeze family");
        }
    }

    function invariantCustodyCaseMatchesTheHandler() external view {
        bytes32 custodyCase = handler.custodyCase();
        if (custodyCase == bytes32(0)) return;
        TrustKernelTypes.CaseRecord memory record = token.caseRecord(custodyCase);
        if (handler.custodyAction() != bytes32(0)) {
            _assert(record.phase == TrustKernelTypes.CasePhase.OPEN, "custody case open while seized");
            _assert(record.family == TrustKernelTypes.CaseFamily.CUSTODY, "custody family");
            _assertEq(record.headActionId, handler.custodyAction(), "custody head");
            _assert(token.balanceOf(keeper) >= handler.custodyAmount(), "custodian holds the backing");
            _assert(!token.canTransfer(keeper, sink, handler.custodyAmount()), "backing is not transferable");
        } else {
            _assert(record.phase == TrustKernelTypes.CasePhase.TERMINAL, "custody case terminal after disposition");
        }
    }

    function invariantInterfaceTruth() external view {
        _assert(token.supportsInterface(0x3edbb4c4), "erc7943 truth");
        _assert(token.supportsInterface(0x2b020308), "kernel truth");
        _assert(!token.supportsInterface(0xffffffff), "invalid interface");
    }
}
