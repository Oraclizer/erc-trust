// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustKernelTypes} from "../../../implementation/src/generated/IERCTrustKernel.sol";
import {ERC3643TrustAdapter} from "../../../implementation/src/profiles/ERC3643TrustAdapter.sol";
import {ProfileGovernor} from "../../../implementation/src/profiles/ProfileGovernor.sol";
import {ERC3643ProfileTypes} from "../../../implementation/src/profiles/ERC3643ProfileTypes.sol";
import {MockERC3643Token} from "../../../implementation/test/mocks/MockERC3643Token.sol";
import {
    MockERC3643IdentityRegistry,
    MockERC3643Compliance
} from "../../../implementation/test/mocks/MockERC3643Dependencies.sol";
import {DerivedIdentifierProbeCore} from "./DerivedIdentifierProbeCore.sol";

interface IPartialDerivedProbeToken {
    function setExclusiveAgent(address agent) external;
    function transferOwnership(address nextOwner) external;
}

/// @notice Derived-identifier probe of the Partial profile endpoint, deployed and sealed as the
///         clean-room Partial fixture does, with one verified buyer for the transfer actions.
contract PartialDerivedIdentifierProbe is DerivedIdentifierProbeCore {
    bytes32 internal constant AUTHORITY_REF = keccak256("ERC3643-AUTHORITY");
    uint256 internal constant SUPPLY = 1_000_000 ether;
    address internal constant BUYER = address(0xb0b);

    MockERC3643IdentityRegistry internal identity;
    MockERC3643Compliance internal compliance;
    address internal token;
    ProfileGovernor internal governor;
    ERC3643TrustAdapter internal adapter;

    function setUp() public {
        identity = new MockERC3643IdentityRegistry();
        compliance = new MockERC3643Compliance();
        identity.setVerified(address(this), true);
        identity.setVerified(BUYER, true);
        token = address(new MockERC3643Token(address(identity), address(compliance), SUPPLY));
        governor = new ProfileGovernor(token, address(identity), address(compliance), address(this), token.codehash);
        adapter = new ERC3643TrustAdapter(address(governor), address(this), AUTHORITY_REF);
        identity.setVerified(address(adapter), true);
        IPartialDerivedProbeToken(token).setExclusiveAgent(address(adapter));
        IPartialDerivedProbeToken(token).transferOwnership(address(governor));
        governor.seal(address(adapter), new ERC3643ProfileTypes.ImportEntry[](0));
    }

    function _endpoint() internal view override returns (address) {
        return address(adapter);
    }

    function testPartialActionsRejectDerivedIdentifiers() external {
        _probeAction(ACTION_SELECTOR, _action(TrustKernelTypes.ActionKind.FREEZE, 801, 1 ether));
        _probeAction(ACTION_SELECTOR, _action(TrustKernelTypes.ActionKind.RESTRICT, 802, 0));
        _probeAction(ACTION_SELECTOR, _action(TrustKernelTypes.ActionKind.SEIZE, 803, 10 ether));
        _probeAction(ACTION_SELECTOR, _action(TrustKernelTypes.ActionKind.CONFISCATE, 804, 5 ether));
        _probeAction(ACTION_SELECTOR, _action(TrustKernelTypes.ActionKind.LIQUIDATE, 805, 4 ether));
        _probeAction(ACTION_SELECTOR, _action(TrustKernelTypes.ActionKind.RECOVER, 806, 3 ether));
        _requireNoViolation();
    }

    function testPartialReversalsRejectDerivedIdentifiers() external {
        TrustKernelTypes.ActionRequest memory freeze = _action(TrustKernelTypes.ActionKind.FREEZE, 821, 1 ether);
        adapter.executeRegulatoryAction(freeze);
        _probeReversal(REVERSAL_SELECTOR, _reversal(freeze.actionId, TrustKernelTypes.ReversalKind.UNFREEZE, 822));

        TrustKernelTypes.ActionRequest memory restrict = _action(TrustKernelTypes.ActionKind.RESTRICT, 823, 0);
        adapter.executeRegulatoryAction(restrict);
        _probeReversal(REVERSAL_SELECTOR, _reversal(restrict.actionId, TrustKernelTypes.ReversalKind.UNRESTRICT, 824));

        TrustKernelTypes.ActionRequest memory seize = _action(TrustKernelTypes.ActionKind.SEIZE, 825, 10 ether);
        adapter.executeRegulatoryAction(seize);
        _probeReversal(REVERSAL_SELECTOR, _reversal(seize.actionId, TrustKernelTypes.ReversalKind.RELEASE, 826));
        _requireNoViolation();
    }

    function _action(TrustKernelTypes.ActionKind kind, uint256 nonce, uint256 amount)
        internal
        view
        returns (TrustKernelTypes.ActionRequest memory request)
    {
        (bytes32 root, uint64 epoch) = adapter.dependencyState();
        request = TrustKernelTypes.ActionRequest({
            domain: TrustKernelTypes.DOMAIN,
            actionId: bytes32(0),
            action: kind,
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
        if (kind == TrustKernelTypes.ActionKind.SEIZE) {
            request.destination = address(adapter);
            request.custodian = address(adapter);
        } else if (kind == TrustKernelTypes.ActionKind.CONFISCATE) {
            request.destination = BUYER;
        } else if (kind == TrustKernelTypes.ActionKind.LIQUIDATE) {
            request.destination = BUYER;
            request.settlementCommitment = keccak256(abi.encode("SETTLEMENT", nonce));
            request.proceedsCommitment = keccak256(abi.encode("PROCEEDS", nonce));
        } else if (kind == TrustKernelTypes.ActionKind.RECOVER) {
            request.destination = BUYER;
            request.entitlementCommitment = keccak256(abi.encode("ENTITLEMENT", nonce));
        }
        request.actionId = adapter.deriveActionId(request);
    }

    function _reversal(bytes32 actionId, TrustKernelTypes.ReversalKind kind, uint256 nonce)
        internal
        view
        returns (TrustKernelTypes.ReversalRequest memory request)
    {
        (bytes32 root, uint64 epoch) = adapter.dependencyState();
        request = TrustKernelTypes.ReversalRequest({
            domain: TrustKernelTypes.DOMAIN,
            reversalId: bytes32(0),
            actionId: actionId,
            reversal: kind,
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
}
