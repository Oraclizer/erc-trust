// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {ITrustBoundDependency} from "./interfaces/ITrustBoundDependency.sol";
import {TrustTypes} from "./TrustTypes.sol";

library TrustPolicyBinding {
    uint256 internal constant STATICCALL_GAS = 100_000;

    function codeId(address dependency) internal view returns (bytes32 result) {
        assembly ("memory-safe") {
            result := extcodehash(dependency)
        }
    }

    function compute(
        TrustTypes.BindingKind kind,
        address dependency,
        bytes32 runtimeCodeId,
        bytes32 config,
        bytes32 schema,
        uint64 epoch
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(TrustTypes.DOMAIN, uint8(kind), dependency, runtimeCodeId, config, schema, epoch));
    }

    function readConfiguration(address dependency) internal view returns (bool ok, bytes32 config) {
        bytes memory input = abi.encodeCall(ITrustBoundDependency.configurationDigest, ());
        bytes memory output;
        (ok, output) = dependency.staticcall{gas: STATICCALL_GAS}(input);
        if (!ok || output.length != 32) return (false, bytes32(0));
        config = abi.decode(output, (bytes32));
    }

    function assess(
        TrustTypes.Binding storage binding,
        bytes32 commandHash,
        uint8 action,
        address subject,
        address destination,
        uint256 amount
    ) internal view returns (TrustTypes.AssessmentOutcome outcome, bytes32 evidenceHash, uint16 reason) {
        if (binding.dependency == address(0) || codeId(binding.dependency) != binding.codeId) {
            return (TrustTypes.AssessmentOutcome.OPERATIONAL_FAILURE, bytes32(0), 200);
        }
        (bool configOk, bytes32 currentConfig) = readConfiguration(binding.dependency);
        if (!configOk || currentConfig != binding.configurationDigest) {
            return (TrustTypes.AssessmentOutcome.OPERATIONAL_FAILURE, bytes32(0), 201);
        }

        bytes memory input = abi.encodeCall(
            ITrustBoundDependency.assess,
            (commandHash, action, subject, destination, amount, binding.bindingHash, binding.epoch)
        );
        (bool ok, bytes memory output) = binding.dependency.staticcall{gas: STATICCALL_GAS}(input);
        if (!ok || output.length != 128) {
            return (TrustTypes.AssessmentOutcome.OPERATIONAL_FAILURE, bytes32(0), 202);
        }
        uint256 rawWord;
        bytes32 commandEcho;
        bytes32 bindingEcho;
        bytes32 evidence;
        assembly ("memory-safe") {
            rawWord := mload(add(output, 0x20))
            commandEcho := mload(add(output, 0x40))
            bindingEcho := mload(add(output, 0x60))
            evidence := mload(add(output, 0x80))
        }
        if (
            rawWord > uint8(TrustTypes.AssessmentOutcome.OPERATIONAL_FAILURE) || commandEcho != commandHash
                || bindingEcho != binding.bindingHash
        ) {
            return (TrustTypes.AssessmentOutcome.OPERATIONAL_FAILURE, bytes32(0), 203);
        }
        // rawWord was bounded above by the largest AssessmentOutcome value.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint8 raw = uint8(rawWord);
        return (TrustTypes.AssessmentOutcome(raw), evidence, raw == 1 ? 100 : raw == 2 ? 204 : 0);
    }
}
