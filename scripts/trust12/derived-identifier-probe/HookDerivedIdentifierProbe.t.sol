// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustKernelTypes} from "../../../implementation/src/generated/IERCTrustKernel.sol";
import {ERC3643HookFactory} from "../../../implementation/src/profiles/ERC3643HookFactory.sol";
import {ERC3643HookAdapter} from "../../../implementation/src/profiles/ERC3643HookAdapter.sol";
import {DerivedIdentifierProbeCore} from "./DerivedIdentifierProbeCore.sol";

interface HookDerivedProbeArtifactVm {
    function getCode(string calldata artifact) external view returns (bytes memory);
}

/// @notice Derived-identifier probe of the Hook profile endpoint, deployed through the pinned factory
///         against the unmodified upstream token exactly as the upstream integration test deploys it.
/// @dev Needs the pinned upstream artifact at out/trust12/trex/out/Token.sol/Token.json.
contract HookDerivedIdentifierProbe is DerivedIdentifierProbeCore {
    bytes32 internal constant AUTHORITY_REF = keccak256("ERC3643-AUTHORITY");
    uint256 internal constant SUPPLY = 1_000_000 ether;
    address internal constant BUYER = address(0xb0b);

    ERC3643HookAdapter internal adapter;

    function setUp() public {
        HookDerivedProbeArtifactVm artifacts = HookDerivedProbeArtifactVm(address(PROBE_VM));
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
    }

    function _endpoint() internal view override returns (address) {
        return address(adapter);
    }

    function testHookActionsRejectDerivedIdentifiers() external {
        _probeAction(ACTION_SELECTOR, _action(TrustKernelTypes.ActionKind.FREEZE, 901, 1 ether));
        _probeAction(ACTION_SELECTOR, _action(TrustKernelTypes.ActionKind.RESTRICT, 902, 0));
        _probeAction(ACTION_SELECTOR, _action(TrustKernelTypes.ActionKind.SEIZE, 903, 10 ether));
        _probeAction(ACTION_SELECTOR, _action(TrustKernelTypes.ActionKind.CONFISCATE, 904, 5 ether));
        _probeAction(ACTION_SELECTOR, _action(TrustKernelTypes.ActionKind.LIQUIDATE, 905, 4 ether));
        _probeAction(ACTION_SELECTOR, _action(TrustKernelTypes.ActionKind.RECOVER, 906, 3 ether));
        _requireNoViolation();
    }

    function testHookReversalsRejectDerivedIdentifiers() external {
        TrustKernelTypes.ActionRequest memory freeze = _action(TrustKernelTypes.ActionKind.FREEZE, 921, 1 ether);
        adapter.executeRegulatoryAction(freeze);
        _probeReversal(REVERSAL_SELECTOR, _reversal(freeze.actionId, TrustKernelTypes.ReversalKind.UNFREEZE, 922));

        TrustKernelTypes.ActionRequest memory restrict = _action(TrustKernelTypes.ActionKind.RESTRICT, 923, 0);
        adapter.executeRegulatoryAction(restrict);
        _probeReversal(REVERSAL_SELECTOR, _reversal(restrict.actionId, TrustKernelTypes.ReversalKind.UNRESTRICT, 924));

        TrustKernelTypes.ActionRequest memory seize = _action(TrustKernelTypes.ActionKind.SEIZE, 925, 10 ether);
        adapter.executeRegulatoryAction(seize);
        _probeReversal(REVERSAL_SELECTOR, _reversal(seize.actionId, TrustKernelTypes.ReversalKind.RELEASE, 926));
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
