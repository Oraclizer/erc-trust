// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {IERCTrustKernel, TrustKernelTypes} from "../../../../implementation/src/generated/IERCTrustKernel.sol";
import {ERC3643HookFactory} from "../../../../implementation/src/profiles/ERC3643HookFactory.sol";
import {ERC3643HookAdapter} from "../../../../implementation/src/profiles/ERC3643HookAdapter.sol";
import {ERC3643HookGovernor} from "../../../../implementation/src/profiles/ERC3643HookGovernor.sol";
import {ERC3643HookCompliance} from "../../../../implementation/src/profiles/ERC3643HookCompliance.sol";
import {ERC3643ProfileTypes} from "../../../../implementation/src/profiles/ERC3643ProfileTypes.sol";

interface RouteDispositionVm {
    function getCode(string calldata artifact) external view returns (bytes memory);
    function prank(address sender) external;
    function mockCall(address callee, bytes calldata data, bytes calldata returnData) external;
    function clearMockedCalls() external;
    function expectCall(address callee, bytes calldata data) external;
    function record() external;
    function accesses(address target) external returns (bytes32[] memory readSlots, bytes32[] memory writeSlots);
}

interface IRouteDispositionToken {
    function transfer(address to, uint256 amount) external returns (bool);
    function getFrozenTokens(address who) external view returns (uint256);
    function compliance() external view returns (address);
}

/// @notice Executes, on the Hook runtimes of a factory unit, the state-changing routes outside the typed
///         commands whose dispositions rest on construction-only, never-succeeding or forwarding behavior: the
///         seal activation of the endpoint, the fresh seal of the governor, the setup steps and callbacks of the
///         Compliance module, and the permissionless resynchronisation with its ownership guard.
/// @dev Integration against unmodified Tokeny T-REX 4.1.3; run scripts/prepare-trex-integration.py first. The
///      tests are run in an isolated copy by scripts/trust12/tail-preparation/run_route_disposition_tests.py.
contract HookRouteDispositionsTest {
    RouteDispositionVm internal constant vm = RouteDispositionVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    bytes32 internal constant AUTHORITY_REF = keccak256("ERC3643-AUTHORITY");
    uint256 internal constant SUPPLY = 1_000_000 ether;
    address internal holder = address(0x401d);

    ERC3643HookAdapter internal adapter;
    ERC3643HookGovernor internal governor;
    ERC3643HookCompliance internal hook;
    address internal token;

    function setUp() public {
        ERC3643HookFactory factory = new ERC3643HookFactory(vm.getCode("out/trust12/trex/out/Token.sol/Token.json"));
        address[] memory eligible = new address[](3);
        eligible[0] = address(0xb0b);
        eligible[1] = address(0xbeef);
        eligible[2] = holder;
        address endpoint;
        address owner;
        (token, endpoint, owner) = factory.deploy(
            vm.getCode("ERC3643HookAdapter.sol:ERC3643HookAdapter"), address(this), AUTHORITY_REF, address(this), SUPPLY,
            eligible
        );
        adapter = ERC3643HookAdapter(endpoint);
        governor = ERC3643HookGovernor(owner);
        hook = ERC3643HookCompliance(IRouteDispositionToken(token).compliance());
    }

    /// @dev The caller check admits only the governor, and even the governor finds the seal already set.
    function testHookActivateSealNeverSucceeds() external {
        ERC3643ProfileTypes.ImportEntry[] memory none = new ERC3643ProfileTypes.ImportEntry[](0);
        (bool ok, bytes memory reason) = address(adapter).call(abi.encodeCall(adapter.activateSeal, (none)));
        require(!ok && _selector(reason) == IERCTrustKernel.TrustUnauthorized.selector, "activation by a stranger");
        vm.prank(address(governor));
        (ok, reason) = address(adapter).call(abi.encodeCall(adapter.activateSeal, (none)));
        require(!ok && _selector(reason) == IERCTrustKernel.TrustOperationalFailure.selector, "activation by the governor");
        require(_word(reason, 1) == 301, "seal invalid reason");
        require(adapter.trustProfile().full, "unit stays sealed");
    }

    /// @dev Every construction-only step reverts for every caller after construction, including the caller
    ///      that performed it during construction.
    function testHookConstructionOnlyRoutesRevertAfterConstruction() external {
        (bool ok, bytes memory reason) = address(governor).call(abi.encodeCall(governor.sealFresh, ()));
        require(!ok && _selector(reason) == IERCTrustKernel.TrustUnauthorized.selector, "fresh seal by a stranger");
        vm.prank(address(adapter));
        (ok, reason) = address(governor).call(abi.encodeCall(governor.sealFresh, ()));
        require(!ok && _isError(reason, "invalid fresh topology"), "fresh seal repeated");
        vm.prank(address(adapter));
        (ok, reason) = address(hook).call(abi.encodeCall(hook.activate, (address(adapter))));
        require(!ok && _isError(reason, "invalid activation"), "activation repeated");
        (ok, reason) = address(hook).call(abi.encodeCall(hook.activate, (address(this))));
        require(!ok && _isError(reason, "invalid activation"), "activation by a stranger");
        vm.prank(token);
        (ok, reason) = address(hook).call(abi.encodeCall(hook.bindToken, (token)));
        require(!ok && _isError(reason, "invalid binding"), "binding repeated");
        (ok, reason) = address(hook).call(abi.encodeCall(hook.bindToken, (token)));
        require(!ok && _isError(reason, "invalid binding"), "binding by a stranger");
        require(hook.endpoint() == address(adapter) && hook.bound() && adapter.sealedTopologyLive(), "topology unchanged");
    }

    /// @dev A Compliance callback from any account other than the token reverts.
    function testHookComplianceCallbacksAcceptOnlyTheToken() external {
        bytes[3] memory calls = [
            abi.encodeCall(hook.created, (holder, 1)),
            abi.encodeCall(hook.transferred, (address(this), holder, 1)),
            abi.encodeCall(hook.destroyed, (holder, 1))
        ];
        for (uint256 i = 0; i < calls.length; ++i) {
            (bool ok, bytes memory reason) = address(hook).call(calls[i]);
            require(!ok && _isError(reason, "only token"), "callback by a stranger");
        }
    }

    /// @dev After activation the mint and burn callbacks only forward the touched account to the balance
    ///      callback, which leaves the owned target and the materialised floor unchanged, and the Compliance
    ///      module writes none of its own storage.
    function testHookMintAndBurnCallbacksOnlyForward() external {
        require(IRouteDispositionToken(token).transfer(holder, 100 ether), "funding");
        _freezeHolder(80 ether);
        (uint256 targetBefore, uint256 appliedBefore,) = adapter.ownedState(holder);
        vm.record();
        vm.expectCall(address(adapter), abi.encodeCall(adapter.onTokenBalanceChanged, (address(0), holder)));
        vm.prank(token);
        hook.created(holder, 0);
        vm.expectCall(address(adapter), abi.encodeCall(adapter.onTokenBalanceChanged, (holder, address(0))));
        vm.prank(token);
        hook.destroyed(holder, 0);
        (, bytes32[] memory complianceWrites) = vm.accesses(address(hook));
        require(complianceWrites.length == 0, "the Compliance module wrote its own storage");
        (uint256 targetAfter, uint256 appliedAfter,) = adapter.ownedState(holder);
        require(targetAfter == targetBefore && appliedAfter == appliedBefore, "owned state changed");
        require(IRouteDispositionToken(token).getFrozenTokens(holder) == 80 ether, "floor changed");
    }

    /// @dev The permissionless resynchronisation is idempotent while the floor is live and fails closed when
    ///      the upstream frozen amount is not the one the endpoint applied.
    function testHookResynchronisationIsIdempotentAndOwnershipGuarded() external {
        require(IRouteDispositionToken(token).transfer(holder, 100 ether), "funding");
        _freezeHolder(80 ether);
        require(adapter.resynchroniseFrozen(holder) == 80 ether, "idempotent resynchronisation");
        vm.mockCall(token, abi.encodeWithSignature("getFrozenTokens(address)", holder), abi.encode(uint256(79 ether)));
        (bool ok, bytes memory reason) = address(adapter).call(abi.encodeCall(adapter.resynchroniseFrozen, (holder)));
        vm.clearMockedCalls();
        require(!ok && _selector(reason) == IERCTrustKernel.TrustOperationalFailure.selector, "unowned state accepted");
        require(_word(reason, 1) == 304, "upstream state not owned");
    }

    function _freezeHolder(uint256 amount) internal {
        (bytes32 root, uint64 epoch) = adapter.dependencyState();
        TrustKernelTypes.ActionRequest memory request = TrustKernelTypes.ActionRequest({
            domain: TrustKernelTypes.DOMAIN,
            actionId: bytes32(0),
            action: TrustKernelTypes.ActionKind.FREEZE,
            subject: holder,
            source: holder,
            destination: address(0),
            custodian: address(0),
            amount: amount,
            caseId: keccak256("ROUTE-DISPOSITION-CASE"),
            dependencyRoot: root,
            dependencyEpoch: epoch,
            provenanceCommitment: keccak256("ROUTE-DISPOSITION-ORDER"),
            settlementCommitment: bytes32(0),
            proceedsCommitment: bytes32(0),
            entitlementCommitment: bytes32(0),
            authorityRef: AUTHORITY_REF,
            authorityEpoch: 1,
            nonce: 700_001,
            validAfter: 0,
            validBefore: type(uint48).max
        });
        request.actionId = adapter.deriveActionId(request);
        adapter.executeRegulatoryAction(request);
    }

    function _selector(bytes memory data) internal pure returns (bytes4 result) {
        if (data.length < 4) return bytes4(0);
        assembly ("memory-safe") {
            result := mload(add(data, 0x20))
        }
    }

    function _word(bytes memory data, uint256 index) internal pure returns (uint256 word) {
        require(data.length >= 4 + 32 * (index + 1), "short revert data");
        assembly ("memory-safe") {
            word := mload(add(add(data, 0x24), mul(index, 0x20)))
        }
    }

    function _isError(bytes memory data, string memory message) internal pure returns (bool) {
        return keccak256(data) == keccak256(abi.encodeWithSignature("Error(string)", message));
    }
}
