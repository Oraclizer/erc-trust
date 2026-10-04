// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {ERC3643HookFactory} from "../../../../implementation/src/profiles/ERC3643HookFactory.sol";
import {ERC3643HookAdapter} from "../../../../implementation/src/profiles/ERC3643HookAdapter.sol";
import {IERC3643IdentityRegistry} from "../../../../implementation/src/interfaces/IERC3643External.sol";
import {TypedFailureProbeCore} from "./TypedFailureProbeCore.sol";

interface HookTypedProbeArtifactVm {
    function getCode(string calldata artifact) external view returns (bytes memory);
}

/// @notice Typed failure probe of the Hook endpoint, deployed through the pinned factory against the
///         unmodified upstream token exactly as the upstream integration test deploys it. The fixed
///         membership registry has no setter, so the dependency cases replace its answer for one call:
///         a mocked denial produces TrustRejected and a mocked revert produces TrustOperationalFailure.
/// @dev Needs the pinned upstream artifact at out/trust12/trex/out/Token.sol/Token.json, which
///      scripts/prepare-trex-integration.py produces.
contract HookTypedFailureProbe is TypedFailureProbeCore {
    bytes32 internal constant AUTHORITY_REF = keccak256("ERC3643-AUTHORITY");
    uint256 internal constant SUPPLY = 1_000_000 ether;
    address internal constant BUYER = address(0xb0b);

    ERC3643HookAdapter internal adapter;
    address internal registry;

    function setUp() public {
        HookTypedProbeArtifactVm artifacts = HookTypedProbeArtifactVm(address(PROBE_VM));
        ERC3643HookFactory factory =
            new ERC3643HookFactory(artifacts.getCode("out/trust12/trex/out/Token.sol/Token.json"));
        address[] memory eligible = new address[](3);
        eligible[0] = BUYER;
        eligible[1] = address(0xbeef);
        eligible[2] = address(0x401d);
        (, address endpoint,) = factory.deploy(
            artifacts.getCode("ERC3643HookAdapter.sol:ERC3643HookAdapter"),
            address(this),
            AUTHORITY_REF,
            address(this),
            SUPPLY,
            eligible
        );
        adapter = ERC3643HookAdapter(endpoint);
        registry = adapter.profileGovernor().identityRegistry();
    }

    function testHookTypedFailureProbe() external {
        _runProbe();
    }

    function _probeProfile() internal pure override returns (uint8) {
        return 3;
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
            PROBE_VM.mockCall(
                registry, abi.encodeWithSelector(IERC3643IdentityRegistry.isVerified.selector, account), abi.encode(false)
            );
        } else {
            PROBE_VM.mockCallRevert(registry, abi.encodeWithSelector(IERC3643IdentityRegistry.isVerified.selector), "");
        }
    }

    function _probeEntrypoints() internal pure override returns (Entrypoints[] memory pairs) {
        pairs = new Entrypoints[](1);
        pairs[0] = Entrypoints(ACTION_SELECTOR, REVERSAL_SELECTOR, 1, 2);
    }
}
