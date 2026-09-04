// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustToken} from "../src/TrustToken.sol";
import {IERCTrustKernel, IERCTrustNativeRoute, TrustKernelTypes} from "../src/generated/IERCTrustKernel.sol";
import {IERC7943Fungible} from "../src/interfaces/IERC7943.sol";
import {MockBoundDependency} from "./mocks/MockBoundDependency.sol";
import {Actor} from "./mocks/Actor.sol";

interface Vm {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory);
    function load(address target, bytes32 slot) external view returns (bytes32);
    function etch(address target, bytes calldata code) external;
    function prank(address sender) external;
    function chainId(uint256 id) external;
    function readFile(string calldata path) external view returns (string memory);
    function parseJsonBytes32(string calldata json, string calldata key) external pure returns (bytes32);
    function parseJsonUint(string calldata json, string calldata key) external pure returns (uint256);
    function parseJsonAddress(string calldata json, string calldata key) external pure returns (address);
    function parseJsonBytes(string calldata json, string calldata key) external pure returns (bytes memory);
    function parseJsonString(string calldata json, string calldata key) external pure returns (string memory);
    function keyExistsJson(string calldata json, string calldata key) external view returns (bool);
    function toString(uint256 value) external pure returns (string memory);
}

abstract contract TrustTestBase {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    bytes32 internal constant DOMAIN = TrustKernelTypes.DOMAIN;
    bytes32 internal constant AUTHORITY_REF = keccak256("AUTHORITY");
    bytes32 internal constant SCHEMA = keccak256("SCHEMA-V2");
    bytes32 internal constant PROVENANCE = keccak256("ORDER-1");
    uint256 internal constant INITIAL_SUPPLY = 1_000_000 ether;
    /// @dev Storage slot of the packed tail of `_routeTicket` (selector, kind, epoch, live). The
    ///      whole ticket is deleted after use, so a nonzero word means a live ticket. Verified against
    ///      `forge inspect TrustToken storage-layout`.
    uint256 internal constant ROUTE_TICKET_PACKED_SLOT = 27;

    TrustToken internal token;
    MockBoundDependency internal dependency;
    Actor internal custodian;
    Actor internal buyer;
    Actor internal recovered;

    function setUp() public virtual {
        dependency = new MockBoundDependency(MockBoundDependency.Mode.APPLICABLE, keccak256("CONFIG-V1"));
        custodian = new Actor();
        buyer = new Actor();
        recovered = new Actor();
        token = _deploy(dependency);
    }

    function _deploy(MockBoundDependency dependency_) internal returns (TrustToken deployed) {
        deployed = new TrustToken(
            "ERC-TRUST Reference",
            "TRUST",
            18,
            address(this),
            address(this),
            INITIAL_SUPPLY,
            AUTHORITY_REF,
            address(this),
            address(dependency_),
            address(dependency_),
            address(dependency_),
            address(dependency_),
            SCHEMA
        );
    }

    function _request(TrustKernelTypes.ActionKind action, uint256 nonce, uint256 amount)
        internal
        view
        returns (TrustKernelTypes.ActionRequest memory request)
    {
        (bytes32 root, uint64 epoch) = token.dependencyState();
        request = TrustKernelTypes.ActionRequest({
            domain: DOMAIN,
            actionId: bytes32(0),
            action: action,
            subject: address(this),
            source: address(this),
            destination: address(0),
            custodian: address(0),
            amount: amount,
            caseId: keccak256(abi.encode("CASE", nonce)),
            dependencyRoot: root,
            dependencyEpoch: epoch,
            provenanceCommitment: keccak256(abi.encode(PROVENANCE, nonce)),
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
            request.destination = address(custodian);
            request.custodian = address(custodian);
        } else if (action == TrustKernelTypes.ActionKind.CONFISCATE) {
            request.destination = address(buyer);
        } else if (action == TrustKernelTypes.ActionKind.LIQUIDATE) {
            request.destination = address(buyer);
            request.settlementCommitment = keccak256(abi.encode("SETTLEMENT", nonce));
            request.proceedsCommitment = keccak256(abi.encode("PROCEEDS", nonce));
        } else if (action == TrustKernelTypes.ActionKind.RECOVER) {
            request.destination = address(recovered);
            request.entitlementCommitment = keccak256(abi.encode("ENTITLEMENT", nonce));
        }
        request.actionId = token.deriveActionId(request);
    }

    function _reversal(bytes32 actionId, TrustKernelTypes.ReversalKind reversal, uint256 nonce)
        internal
        view
        returns (TrustKernelTypes.ReversalRequest memory request)
    {
        (bytes32 root, uint64 epoch) = token.dependencyState();
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
        request.reversalId = token.deriveReversalId(request);
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
        request.actionId = token.deriveActionId(request);
    }

    // ------------------------------------------------------------------
    // Indexer-style recomputation
    // ------------------------------------------------------------------

    /// @dev hashes.receiptHash recomputed from stored fields with the ABI coder, as an indexer would.
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

    /// @dev hashes.commandHash recomputed with the ABI coder over the completed request.
    function _recomputeCommandHash(address endpoint, TrustKernelTypes.ActionRequest memory request)
        internal
        view
        returns (bytes32)
    {
        return keccak256(abi.encode(DOMAIN, endpoint, block.chainid, request));
    }

    function _recomputeDependencyRoot(bytes32 policy, bytes32 identity, bytes32 settlement, bytes32 entitlement)
        internal
        pure
        returns (bytes32)
    {
        return
            keccak256(
                abi.encode(DOMAIN, TrustKernelTypes.DEPENDENCY_ROOT_TAG, policy, identity, settlement, entitlement)
            );
    }

    // ------------------------------------------------------------------
    // Revert inspection
    // ------------------------------------------------------------------

    function _call(bytes memory data) internal returns (bool ok, bytes memory result) {
        (ok, result) = address(token).call(data);
    }

    function _selector(bytes memory data) internal pure returns (bytes4 result) {
        if (data.length < 4) return bytes4(0);
        assembly ("memory-safe") {
            result := mload(add(data, 0x20))
        }
    }

    /// @dev Decodes the reason of TrustInvalidCommand(bytes32,uint16) or TrustRejected(bytes32,uint16).
    function _reasonOf(bytes memory data) internal pure returns (uint16 reason) {
        require(data.length >= 4 + 64, "no reason payload");
        assembly ("memory-safe") {
            reason := mload(add(data, 0x44))
        }
    }

    function _expectInvalid(bytes memory data, uint16 reason, string memory message) internal {
        (bool ok, bytes memory result) = _call(data);
        require(!ok, message);
        require(_selector(result) == IERCTrustKernel.TrustInvalidCommand.selector, message);
        require(_reasonOf(result) == reason, message);
    }

    function _expectSelector(bytes memory data, bytes4 selector, string memory message) internal {
        (bool ok, bytes memory result) = _call(data);
        require(!ok, message);
        require(_selector(result) == selector, message);
    }

    function _routeLive() internal view returns (bool) {
        return vm.load(address(token), bytes32(ROUTE_TICKET_PACKED_SLOT)) != bytes32(0);
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
