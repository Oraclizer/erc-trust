// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustToken} from "../src/TrustToken.sol";
import {TrustTypes} from "../src/TrustTypes.sol";
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
}

abstract contract TrustTestBase {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    bytes32 internal constant DOMAIN = keccak256("ERC-TRUST/reference-v1");
    bytes32 internal constant AUTHORITY_REF = keccak256("AUTHORITY");
    bytes32 internal constant SCHEMA = keccak256("SCHEMA-V1");
    bytes32 internal constant SCOPE = keccak256("GLOBAL-SCOPE");
    bytes32 internal constant PROVENANCE = keccak256("ORDER-1");
    uint256 internal constant INITIAL_SUPPLY = 1_000_000 ether;

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

    function _request(TrustTypes.ActionKind action, uint256 nonce, uint256 amount)
        internal
        view
        returns (TrustTypes.ActionRequest memory request)
    {
        (, bytes32 policyBinding, uint64 policyEpoch) = token.getBindingState(TrustTypes.BindingKind.POLICY);
        request = TrustTypes.ActionRequest({
            domain: DOMAIN,
            actionId: bytes32(0),
            action: action,
            subject: address(this),
            source: address(this),
            destination: address(0),
            custodian: address(0),
            amount: amount,
            caseId: keccak256(abi.encode("CASE", nonce)),
            scopeHash: SCOPE,
            policyCommitment: policyBinding,
            provenanceCommitment: keccak256(abi.encode(PROVENANCE, nonce)),
            settlementCommitment: bytes32(0),
            proceedsCommitment: bytes32(0),
            entitlementCommitment: bytes32(0),
            authorityRef: AUTHORITY_REF,
            authorityEpoch: 1,
            policyEpoch: policyEpoch,
            nonce: nonce,
            validAfter: 0,
            validBefore: type(uint48).max
        });

        if (action == TrustTypes.ActionKind.SEIZE) {
            request.destination = address(custodian);
            request.custodian = address(custodian);
        } else if (action == TrustTypes.ActionKind.CONFISCATE) {
            request.destination = address(buyer);
        } else if (action == TrustTypes.ActionKind.LIQUIDATE) {
            request.destination = address(buyer);
            request.settlementCommitment = keccak256(abi.encode("SETTLEMENT", nonce));
            request.proceedsCommitment = keccak256(abi.encode("PROCEEDS", nonce));
        } else if (action == TrustTypes.ActionKind.RECOVER) {
            request.destination = address(recovered);
            request.entitlementCommitment = keccak256(abi.encode("ENTITLEMENT", nonce));
        }
        request.actionId = token.deriveActionId(request);
    }

    function _reversal(bytes32 actionId, TrustTypes.ReversalKind reversal, uint256 nonce)
        internal
        view
        returns (TrustTypes.ReversalRequest memory request)
    {
        request = TrustTypes.ReversalRequest({
            domain: DOMAIN,
            reversalId: bytes32(0),
            actionId: actionId,
            reversal: reversal,
            authorityRef: AUTHORITY_REF,
            authorityEpoch: 1,
            nonce: nonce,
            validAfter: 0,
            validBefore: type(uint48).max
        });
        request.reversalId = token.deriveReversalId(request);
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
