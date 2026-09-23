// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustKernelTypes} from "../../../../implementation/src/generated/IERCTrustKernel.sol";
import {ERC3643TrustAdapter} from "../../../../implementation/src/profiles/ERC3643TrustAdapter.sol";
import {ProfileGovernor} from "../../../../implementation/src/profiles/ProfileGovernor.sol";
import {ERC3643ProfileTypes} from "../../../../implementation/src/profiles/ERC3643ProfileTypes.sol";
import {MockERC3643Token} from "../../../../implementation/test/mocks/MockERC3643Token.sol";
import {
    MockERC3643IdentityRegistry,
    MockERC3643Compliance
} from "../../../../implementation/test/mocks/MockERC3643Dependencies.sol";
import {MalformedProbeCore} from "./MalformedProbeCore.sol";
import {MalformedProbeRecipes} from "./MalformedProbeRecipes.sol";

interface IPartialProbeToken {
    function setExclusiveAgent(address agent) external;
    function transferOwnership(address nextOwner) external;
}

/// @notice Malformed probe of the Partial profile endpoint, deployed and sealed as the clean-room
///         Partial fixture does.
contract PartialMalformedProbe is MalformedProbeCore {
    bytes32 internal constant AUTHORITY_REF = keccak256("ERC3643-AUTHORITY");
    uint256 internal constant SUPPLY = 1_000_000 ether;

    MockERC3643IdentityRegistry internal identity;
    MockERC3643Compliance internal compliance;
    address internal token;
    ProfileGovernor internal governor;
    ERC3643TrustAdapter internal adapter;

    function setUp() public {
        identity = new MockERC3643IdentityRegistry();
        compliance = new MockERC3643Compliance();
        identity.setVerified(address(this), true);
        token = address(new MockERC3643Token(address(identity), address(compliance), SUPPLY));
        governor = new ProfileGovernor(token, address(identity), address(compliance), address(this), token.codehash);
        adapter = new ERC3643TrustAdapter(address(governor), address(this), AUTHORITY_REF);
        identity.setVerified(address(adapter), true);
        IPartialProbeToken(token).setExclusiveAgent(address(adapter));
        IPartialProbeToken(token).transferOwnership(address(governor));
        governor.seal(address(adapter), new ERC3643ProfileTypes.ImportEntry[](0));
    }

    function testPartialMalformedProbe() external {
        _runProbe(MalformedProbeRecipes.partialRecipes());
    }

    function _probeEndpoint() internal view override returns (address) {
        return address(adapter);
    }

    function _probeAction(uint256 nonce)
        internal
        view
        override
        returns (TrustKernelTypes.ActionRequest memory request)
    {
        (bytes32 root, uint64 epoch) = adapter.dependencyState();
        request = TrustKernelTypes.ActionRequest({
            domain: TrustKernelTypes.DOMAIN,
            actionId: bytes32(0),
            action: TrustKernelTypes.ActionKind.FREEZE,
            subject: address(this),
            source: address(this),
            destination: address(0),
            custodian: address(0),
            amount: PROBE_AMOUNT,
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
        request.actionId = adapter.deriveActionId(request);
    }

    function _probeReversal(bytes32 actionId, uint256 nonce)
        internal
        view
        override
        returns (TrustKernelTypes.ReversalRequest memory request)
    {
        (bytes32 root, uint64 epoch) = adapter.dependencyState();
        request = TrustKernelTypes.ReversalRequest({
            domain: TrustKernelTypes.DOMAIN,
            reversalId: bytes32(0),
            actionId: actionId,
            reversal: TrustKernelTypes.ReversalKind.UNFREEZE,
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
