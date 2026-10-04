// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {ERC3643TrustAdapter} from "../../../../implementation/src/profiles/ERC3643TrustAdapter.sol";
import {ProfileGovernor} from "../../../../implementation/src/profiles/ProfileGovernor.sol";
import {ERC3643ProfileTypes} from "../../../../implementation/src/profiles/ERC3643ProfileTypes.sol";
import {MockERC3643Token} from "../../../../implementation/test/mocks/MockERC3643Token.sol";
import {
    MockERC3643IdentityRegistry,
    MockERC3643Compliance
} from "../../../../implementation/test/mocks/MockERC3643Dependencies.sol";
import {TypedFailureProbeCore} from "./TypedFailureProbeCore.sol";

interface IPartialTypedProbeToken {
    function setExclusiveAgent(address agent) external;
    function transferOwnership(address nextOwner) external;
}

/// @notice Typed failure probe of the Partial endpoint, deployed and sealed as the clean-room Partial
///         fixture and the Partial malformed probe deploy it. Only transfer commands consult the
///         Identity Registry and the Compliance policy, so the dependency cases use CONFISCATE and the
///         RELEASE of a SEIZE; an identity denial produces TrustRejected and a reverting registry
///         produces TrustOperationalFailure.
contract PartialTypedFailureProbe is TypedFailureProbeCore {
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
        IPartialTypedProbeToken(token).setExclusiveAgent(address(adapter));
        IPartialTypedProbeToken(token).transferOwnership(address(governor));
        governor.seal(address(adapter), new ERC3643ProfileTypes.ImportEntry[](0));
    }

    function testPartialTypedFailureProbe() external {
        _runProbe();
    }

    function _probeProfile() internal pure override returns (uint8) {
        return 2;
    }

    function _probeEndpoint() internal view override returns (address) {
        return address(adapter);
    }

    function _probeAuthorityRef() internal pure override returns (bytes32) {
        return AUTHORITY_REF;
    }

    function _probeDestination() internal pure override returns (address) {
        return BUYER;
    }

    function _probeConsultsOnTransferOnly() internal pure override returns (bool) {
        return true;
    }

    function _breakAssessment(bool rejected, address account) internal override {
        if (rejected) {
            identity.setVerified(account, false);
        } else {
            identity.setMode(MockERC3643IdentityRegistry.Mode.REVERT_CALL);
        }
    }

    function _probeEntrypoints() internal pure override returns (Entrypoints[] memory pairs) {
        pairs = new Entrypoints[](1);
        pairs[0] = Entrypoints(ACTION_SELECTOR, REVERSAL_SELECTOR, 1, 2);
    }
}
