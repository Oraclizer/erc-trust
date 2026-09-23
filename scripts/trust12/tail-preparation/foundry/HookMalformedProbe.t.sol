// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustKernelTypes} from "../../../../implementation/src/generated/IERCTrustKernel.sol";
import {ERC3643HookFactory} from "../../../../implementation/src/profiles/ERC3643HookFactory.sol";
import {ERC3643HookAdapter} from "../../../../implementation/src/profiles/ERC3643HookAdapter.sol";
import {MalformedProbeCore} from "./MalformedProbeCore.sol";
import {MalformedProbeRecipes} from "./MalformedProbeRecipes.sol";

interface HookProbeArtifactVm {
    function getCode(string calldata artifact) external view returns (bytes memory);
}

/// @notice Malformed probe of the Hook profile endpoint, deployed through the pinned factory against
///         the unmodified upstream token exactly as the upstream integration test deploys it.
/// @dev Needs the pinned upstream artifact at out/trust12/trex/out/Token.sol/Token.json, which
///      scripts/prepare-trex-integration.py produces.
contract HookMalformedProbe is MalformedProbeCore {
    bytes32 internal constant AUTHORITY_REF = keccak256("ERC3643-AUTHORITY");
    uint256 internal constant SUPPLY = 1_000_000 ether;

    ERC3643HookAdapter internal adapter;

    function setUp() public {
        HookProbeArtifactVm artifacts = HookProbeArtifactVm(address(PROBE_VM));
        ERC3643HookFactory factory =
            new ERC3643HookFactory(artifacts.getCode("out/trust12/trex/out/Token.sol/Token.json"));
        address[] memory eligible = new address[](3);
        eligible[0] = address(0xb0b);
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
    }

    function testHookMalformedProbe() external {
        _runProbe(MalformedProbeRecipes.hookRecipes());
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
