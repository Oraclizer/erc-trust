// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustTestBase} from "./TrustTestBase.t.sol";
import {TrustToken} from "../src/TrustToken.sol";
import {IERCTrustKernel, TrustKernelTypes} from "../src/generated/IERCTrustKernel.sol";

/// @notice The native endpoint reproduces every identifier, calldata encoding, and receipt hash of the
///         generated conformance vectors when its runtime is placed at the fixture endpoint and chain.
contract TrustKernelVectorsTest is TrustTestBase {
    string internal json;
    address internal endpoint;
    uint256 internal chainId;
    TrustToken internal fixture;

    function setUp() public override {
        super.setUp();
        json = vm.readFile("vectors/conformance-v2.json");
        endpoint = vm.parseJsonAddress(json, ".fixture.endpoint");
        chainId = vm.parseJsonUint(json, ".fixture.chainId");
        vm.etch(endpoint, address(token).code);
        vm.chainId(chainId);
        fixture = TrustToken(endpoint);
    }

    function testConstantsMatchTheCompiledKernel() external view {
        _assertEq(vm.parseJsonBytes32(json, ".constants.domain"), TrustKernelTypes.DOMAIN, "domain");
        _assertEq(
            vm.parseJsonBytes32(json, ".constants.dependencyRootTag"), TrustKernelTypes.DEPENDENCY_ROOT_TAG, "tag"
        );
        bytes memory identifier = vm.parseJsonBytes(json, ".constants.kernelInterfaceId");
        _assertEq(identifier.length, 4, "interface identifier width");
        // The width was asserted above, so the conversion cannot truncate.
        // forge-lint: disable-next-line(unsafe-typecast)
        _assert(bytes4(identifier) == type(IERCTrustKernel).interfaceId, "interface identifier");
        _assertEq(vm.parseJsonUint(json, ".constants.actionCalldataLength"), 644, "action calldata length");
        _assertEq(vm.parseJsonUint(json, ".constants.reversalCalldataLength"), 388, "reversal calldata length");
        _assertEq(
            vm.parseJsonBytes32(json, ".fixture.nonceKeyExample.nonceKey"),
            keccak256(
                abi.encode(
                    TrustKernelTypes.DOMAIN,
                    vm.parseJsonBytes32(json, ".fixture.nonceKeyExample.authorityRef"),
                    uint64(vm.parseJsonUint(json, ".fixture.nonceKeyExample.authorityEpoch")),
                    vm.parseJsonUint(json, ".fixture.nonceKeyExample.nonce")
                )
            ),
            "nonce key"
        );
    }

    function testFixtureBindingsAndDependencyRoot() external view {
        string[4] memory kinds = ["policy", "identity", "settlement", "entitlement"];
        bytes32[4] memory bindings;
        for (uint8 kind = 0; kind < 4; ++kind) {
            string memory base = string.concat(".fixture.dependencies.", kinds[kind]);
            bytes32 expected = keccak256(
                abi.encode(
                    TrustKernelTypes.DOMAIN,
                    kind,
                    vm.parseJsonAddress(json, string.concat(base, ".dependency")),
                    vm.parseJsonBytes32(json, string.concat(base, ".runtimeCodeId")),
                    vm.parseJsonBytes32(json, string.concat(base, ".configurationDigest")),
                    vm.parseJsonBytes32(json, string.concat(base, ".schema")),
                    uint64(vm.parseJsonUint(json, string.concat(base, ".epoch")))
                )
            );
            bindings[kind] = vm.parseJsonBytes32(json, string.concat(".fixture.bindingHashes.", kinds[kind]));
            _assertEq(bindings[kind], expected, "binding hash");
        }
        _assertEq(
            vm.parseJsonBytes32(json, ".fixture.dependencyRoot"),
            _recomputeDependencyRoot(bindings[0], bindings[1], bindings[2], bindings[3]),
            "dependency root"
        );
    }

    function testActionVectorsReproduce() external view {
        for (uint256 i = 0; i < 7; ++i) {
            string memory base = string.concat(".actions[", vm.toString(i), "]");
            TrustKernelTypes.ActionRequest memory request = _actionAt(string.concat(base, ".request"));
            _assertEq(
                fixture.deriveActionId(request), vm.parseJsonBytes32(json, string.concat(base, ".actionId")), "actionId"
            );
            _assertEq(
                keccak256(abi.encode(TrustKernelTypes.DOMAIN, endpoint, chainId, request)),
                vm.parseJsonBytes32(json, string.concat(base, ".commandHash")),
                "commandHash"
            );
            bytes memory calldataBytes = vm.parseJsonBytes(json, string.concat(base, ".calldata"));
            _assertEq(
                keccak256(abi.encodeCall(IERCTrustKernel.executeRegulatoryAction, (request))),
                keccak256(calldataBytes),
                "calldata"
            );
            _assertEq(calldataBytes.length, 644, "calldata length");
            _assertEq(
                _recomputeReceiptHash(_receiptAt(string.concat(base, ".receiptInput"))),
                vm.parseJsonBytes32(json, string.concat(base, ".receiptHash")),
                "receiptHash"
            );
        }
    }

    function testReversalVectorsReproduce() external view {
        for (uint256 i = 0; i < 3; ++i) {
            string memory base = string.concat(".reversals[", vm.toString(i), "]");
            TrustKernelTypes.ReversalRequest memory request = _reversalAt(string.concat(base, ".request"));
            _assertEq(
                fixture.deriveReversalId(request),
                vm.parseJsonBytes32(json, string.concat(base, ".reversalId")),
                "reversalId"
            );
            _assertEq(
                keccak256(abi.encode(TrustKernelTypes.DOMAIN, endpoint, chainId, request)),
                vm.parseJsonBytes32(json, string.concat(base, ".reversalHash")),
                "reversalHash"
            );
            bytes memory calldataBytes = vm.parseJsonBytes(json, string.concat(base, ".calldata"));
            _assertEq(
                keccak256(abi.encodeCall(IERCTrustKernel.executeRegulatoryReversal, (request))),
                keccak256(calldataBytes),
                "reversal calldata"
            );
            _assertEq(calldataBytes.length, 388, "reversal calldata length");
            _assertEq(
                _recomputeReceiptHash(_receiptAt(string.concat(base, ".receiptInput"))),
                vm.parseJsonBytes32(json, string.concat(base, ".receiptHash")),
                "reversal receiptHash"
            );
        }
    }

    function testFieldBindingNegativeVectors() external view {
        uint256 index = type(uint256).max;
        for (uint256 i = 0; i < 16; ++i) {
            string memory base = string.concat(".negative[", vm.toString(i), "]");
            if (!vm.keyExistsJson(json, base)) break;
            if (vm.keyExistsJson(json, string.concat(base, ".mutatedDerivedActionIds"))) {
                index = i;
                break;
            }
        }
        _assert(index != type(uint256).max, "field-binding vector present");
        string memory negative = string.concat(".negative[", vm.toString(index), "]");
        _assert(
            keccak256(bytes(vm.parseJsonString(json, string.concat(negative, ".base"))))
                == keccak256(bytes(vm.parseJsonString(json, ".actions[0].id"))),
            "mutations are relative to the first action vector"
        );
        bytes32 baseId = vm.parseJsonBytes32(json, ".actions[0].actionId");
        uint256 count;
        for (uint256 k = 0; k < 32; ++k) {
            string memory entry = string.concat(negative, ".mutatedDerivedActionIds[", vm.toString(k), "]");
            if (!vm.keyExistsJson(json, entry)) break;
            // A fresh copy per entry: memory structs are reference types, so mutating a shared base would accumulate.
            TrustKernelTypes.ActionRequest memory mutated = _mutate(_actionAt(".actions[0].request"), entry);
            _assertEq(
                fixture.deriveActionId(mutated),
                vm.parseJsonBytes32(json, string.concat(entry, ".derivedActionId")),
                "mutated identifier"
            );
            _assert(fixture.deriveActionId(mutated) != baseId, "every bound field changes the identifier");
            count += 1;
        }
        _assertEq(count, 19, "one mutation per bound field");
    }

    function _mutate(TrustKernelTypes.ActionRequest memory base, string memory entry)
        internal
        view
        returns (TrustKernelTypes.ActionRequest memory mutated)
    {
        mutated = base;
        bytes32 field = keccak256(bytes(vm.parseJsonString(json, string.concat(entry, ".field"))));
        string memory key = string.concat(entry, ".mutatedValue");
        if (field == keccak256("domain")) {
            mutated.domain = vm.parseJsonBytes32(json, key);
        } else if (field == keccak256("action")) {
            mutated.action = TrustKernelTypes.ActionKind(uint8(vm.parseJsonUint(json, key)));
        } else if (field == keccak256("subject")) {
            mutated.subject = vm.parseJsonAddress(json, key);
        } else if (field == keccak256("source")) {
            mutated.source = vm.parseJsonAddress(json, key);
        } else if (field == keccak256("destination")) {
            mutated.destination = vm.parseJsonAddress(json, key);
        } else if (field == keccak256("custodian")) {
            mutated.custodian = vm.parseJsonAddress(json, key);
        } else if (field == keccak256("amount")) {
            mutated.amount = vm.parseJsonUint(json, key);
        } else if (field == keccak256("caseId")) {
            mutated.caseId = vm.parseJsonBytes32(json, key);
        } else if (field == keccak256("dependencyRoot")) {
            mutated.dependencyRoot = vm.parseJsonBytes32(json, key);
        } else if (field == keccak256("dependencyEpoch")) {
            mutated.dependencyEpoch = uint64(vm.parseJsonUint(json, key));
        } else if (field == keccak256("provenanceCommitment")) {
            mutated.provenanceCommitment = vm.parseJsonBytes32(json, key);
        } else if (field == keccak256("settlementCommitment")) {
            mutated.settlementCommitment = vm.parseJsonBytes32(json, key);
        } else if (field == keccak256("proceedsCommitment")) {
            mutated.proceedsCommitment = vm.parseJsonBytes32(json, key);
        } else if (field == keccak256("entitlementCommitment")) {
            mutated.entitlementCommitment = vm.parseJsonBytes32(json, key);
        } else if (field == keccak256("authorityRef")) {
            mutated.authorityRef = vm.parseJsonBytes32(json, key);
        } else if (field == keccak256("authorityEpoch")) {
            mutated.authorityEpoch = uint64(vm.parseJsonUint(json, key));
        } else if (field == keccak256("nonce")) {
            mutated.nonce = vm.parseJsonUint(json, key);
        } else if (field == keccak256("validAfter")) {
            mutated.validAfter = uint48(vm.parseJsonUint(json, key));
        } else if (field == keccak256("validBefore")) {
            mutated.validBefore = uint48(vm.parseJsonUint(json, key));
        } else {
            revert("unknown mutated field");
        }
        mutated.actionId = bytes32(0);
    }

    function _actionAt(string memory base) internal view returns (TrustKernelTypes.ActionRequest memory request) {
        request.domain = _b32(base, ".domain");
        request.actionId = _b32(base, ".actionId");
        request.action = TrustKernelTypes.ActionKind(uint8(_u(base, ".action")));
        request.subject = _a(base, ".subject");
        request.source = _a(base, ".source");
        request.destination = _a(base, ".destination");
        request.custodian = _a(base, ".custodian");
        request.amount = _u(base, ".amount");
        request.caseId = _b32(base, ".caseId");
        request.dependencyRoot = _b32(base, ".dependencyRoot");
        request.dependencyEpoch = uint64(_u(base, ".dependencyEpoch"));
        request.provenanceCommitment = _b32(base, ".provenanceCommitment");
        request.settlementCommitment = _b32(base, ".settlementCommitment");
        request.proceedsCommitment = _b32(base, ".proceedsCommitment");
        request.entitlementCommitment = _b32(base, ".entitlementCommitment");
        request.authorityRef = _b32(base, ".authorityRef");
        request.authorityEpoch = uint64(_u(base, ".authorityEpoch"));
        request.nonce = _u(base, ".nonce");
        request.validAfter = uint48(_u(base, ".validAfter"));
        request.validBefore = uint48(_u(base, ".validBefore"));
    }

    function _reversalAt(string memory base) internal view returns (TrustKernelTypes.ReversalRequest memory request) {
        request.domain = _b32(base, ".domain");
        request.reversalId = _b32(base, ".reversalId");
        request.actionId = _b32(base, ".actionId");
        request.reversal = TrustKernelTypes.ReversalKind(uint8(_u(base, ".reversal")));
        request.dependencyRoot = _b32(base, ".dependencyRoot");
        request.dependencyEpoch = uint64(_u(base, ".dependencyEpoch"));
        request.provenanceCommitment = _b32(base, ".provenanceCommitment");
        request.authorityRef = _b32(base, ".authorityRef");
        request.authorityEpoch = uint64(_u(base, ".authorityEpoch"));
        request.nonce = _u(base, ".nonce");
        request.validAfter = uint48(_u(base, ".validAfter"));
        request.validBefore = uint48(_u(base, ".validBefore"));
    }

    function _receiptAt(string memory base) internal view returns (TrustKernelTypes.Receipt memory r) {
        r.receiptKind = TrustKernelTypes.ReceiptKind(uint8(_u(base, ".receiptKind")));
        r.commandId = _b32(base, ".commandId");
        r.commandKind = uint8(_u(base, ".commandKind"));
        r.parentCommandId = _b32(base, ".parentCommandId");
        r.subject = _a(base, ".subject");
        r.source = _a(base, ".source");
        r.destination = _a(base, ".destination");
        r.amount = _u(base, ".amount");
        r.caseId = _b32(base, ".caseId");
        r.authorityRef = _b32(base, ".authorityRef");
        r.dependencyRoot = _b32(base, ".dependencyRoot");
        r.provenanceCommitment = _b32(base, ".provenanceCommitment");
        r.assessmentEvidence = _b32(base, ".assessmentEvidence");
        r.preState = _b32(base, ".preState");
        r.postState = _b32(base, ".postState");
        r.externalCommitment = _b32(base, ".externalCommitment");
    }

    function _b32(string memory base, string memory key) internal view returns (bytes32) {
        return vm.parseJsonBytes32(json, string.concat(base, key));
    }

    function _u(string memory base, string memory key) internal view returns (uint256) {
        return vm.parseJsonUint(json, string.concat(base, key));
    }

    function _a(string memory base, string memory key) internal view returns (address) {
        return vm.parseJsonAddress(json, string.concat(base, key));
    }
}
