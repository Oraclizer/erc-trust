// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {ITrustBoundDependency, TrustKernelTypes} from "./generated/IERCTrustKernel.sol";
import {TrustNativeTypes} from "./TrustNativeTypes.sol";

/// @notice Read-only, fail-closed boundary between the native endpoint and its four bound dependencies.
/// @dev Reason codes follow reasonClasses: 100 to 103 for a completed denial, 200 to 204 for an
///      unavailable, changed, unreachable, malformed, or mismatched dependency.
library TrustDependencyBinding {
    uint256 internal constant STATICCALL_GAS = 100_000;
    uint16 internal constant REASON_DENIED_BASE = 100;
    uint16 internal constant REASON_CODE_MISMATCH = 200;
    uint16 internal constant REASON_CONFIGURATION_MISMATCH = 201;
    uint16 internal constant REASON_CALL_FAILED_OR_MALFORMED = 202;
    uint16 internal constant REASON_ECHO_MISMATCH = 203;
    uint16 internal constant REASON_REPORTED_FAILURE = 204;

    function codeId(address dependency) internal view returns (bytes32 result) {
        assembly ("memory-safe") {
            result := extcodehash(dependency)
        }
    }

    /// @dev hashes.bindingHash of the native profile.
    function compute(
        TrustKernelTypes.BindingKind kind,
        address dependency,
        bytes32 runtimeCodeId,
        bytes32 config,
        bytes32 schema,
        uint64 epoch
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(TrustKernelTypes.DOMAIN, uint8(kind), dependency, runtimeCodeId, config, schema, epoch)
        );
    }

    function readConfiguration(address dependency) internal view returns (bool ok, bytes32 config) {
        bytes memory input = abi.encodeCall(ITrustBoundDependency.configurationDigest, ());
        bytes memory output;
        (ok, output) = dependency.staticcall{gas: STATICCALL_GAS}(input);
        if (!ok || output.length != 32) return (false, bytes32(0));
        config = abi.decode(output, (bytes32));
    }

    /// @dev True while the bound dependency still has the bound runtime code and configuration.
    function live(TrustNativeTypes.Binding storage binding) internal view returns (bool) {
        if (binding.dependency == address(0) || codeId(binding.dependency) != binding.codeId) return false;
        (bool ok, bytes32 config) = readConfiguration(binding.dependency);
        return ok && config == binding.configurationDigest;
    }

    function assess(
        TrustNativeTypes.Binding storage binding,
        TrustKernelTypes.BindingKind kind,
        bytes32 commandHash,
        uint8 operation,
        address subject,
        address destination,
        uint256 amount
    ) internal view returns (TrustKernelTypes.AssessmentOutcome outcome, bytes32 evidenceHash, uint16 reason) {
        if (binding.dependency == address(0) || codeId(binding.dependency) != binding.codeId) {
            return (TrustKernelTypes.AssessmentOutcome.OPERATIONAL_FAILURE, bytes32(0), REASON_CODE_MISMATCH);
        }
        (bool configOk, bytes32 currentConfig) = readConfiguration(binding.dependency);
        if (!configOk || currentConfig != binding.configurationDigest) {
            return (TrustKernelTypes.AssessmentOutcome.OPERATIONAL_FAILURE, bytes32(0), REASON_CONFIGURATION_MISMATCH);
        }

        bytes memory input = abi.encodeCall(
            ITrustBoundDependency.assess,
            (commandHash, operation, subject, destination, amount, binding.bindingHash, binding.epoch)
        );
        (bool ok, bytes memory output) = binding.dependency.staticcall{gas: STATICCALL_GAS}(input);
        if (!ok || output.length != 128) {
            return (TrustKernelTypes.AssessmentOutcome.OPERATIONAL_FAILURE, bytes32(0), REASON_CALL_FAILED_OR_MALFORMED);
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
        if (rawWord > uint8(TrustKernelTypes.AssessmentOutcome.OPERATIONAL_FAILURE)) {
            return (TrustKernelTypes.AssessmentOutcome.OPERATIONAL_FAILURE, bytes32(0), REASON_CALL_FAILED_OR_MALFORMED);
        }
        if (commandEcho != commandHash || bindingEcho != binding.bindingHash) {
            return (TrustKernelTypes.AssessmentOutcome.OPERATIONAL_FAILURE, bytes32(0), REASON_ECHO_MISMATCH);
        }
        // rawWord was bounded above by the largest AssessmentOutcome value.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint8 raw = uint8(rawWord);
        if (raw == uint8(TrustKernelTypes.AssessmentOutcome.REJECTED)) {
            return (TrustKernelTypes.AssessmentOutcome.REJECTED, evidence, REASON_DENIED_BASE + uint16(uint8(kind)));
        }
        if (raw == uint8(TrustKernelTypes.AssessmentOutcome.OPERATIONAL_FAILURE)) {
            return (TrustKernelTypes.AssessmentOutcome.OPERATIONAL_FAILURE, evidence, REASON_REPORTED_FAILURE);
        }
        return (TrustKernelTypes.AssessmentOutcome.APPLICABLE, evidence, 0);
    }
}
