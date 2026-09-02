// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustTypes} from "../../src/TrustTypes.sol";

/// @notice Verification-only classifier for the Native dependency boundary.
/// @dev Exact EVM STATICCALL and raw returndata extraction remain KEVM-owned.
contract TrustPolicyBindingHarness {
    struct Observation {
        bool dependencyPresent;
        bool codeMatches;
        bool configurationCallOk;
        uint256 configurationReturnLength;
        bytes32 returnedConfiguration;
        bytes32 expectedConfiguration;
        bool assessmentCallOk;
        uint256 assessmentReturnLength;
        uint256 rawOutcomeWord;
        bytes32 commandEcho;
        bytes32 expectedCommand;
        bytes32 bindingEcho;
        bytes32 expectedBinding;
        bytes32 evidenceHash;
    }

    function classifyOutcome(Observation calldata observation) external pure returns (uint8) {
        if (!observation.dependencyPresent || !observation.codeMatches) return 2;
        if (
            !observation.configurationCallOk || observation.configurationReturnLength != 32
                || observation.returnedConfiguration != observation.expectedConfiguration
        ) return 2;
        if (!observation.assessmentCallOk || observation.assessmentReturnLength != 128) return 2;
        if (
            observation.rawOutcomeWord > 2 || observation.commandEcho != observation.expectedCommand
                || observation.bindingEcho != observation.expectedBinding
        ) return 2;
        return uint8(observation.rawOutcomeWord);
    }

    /// @dev Codes: applicable=1000, rejected=1100, operational/no-evidence=2200..2203,
    /// operational/evidence-preserved=3204.
    function classifyCode(Observation calldata observation) external pure returns (uint256) {
        if (!observation.dependencyPresent || !observation.codeMatches) return 2200;
        if (
            !observation.configurationCallOk || observation.configurationReturnLength != 32
                || observation.returnedConfiguration != observation.expectedConfiguration
        ) return 2201;
        if (!observation.assessmentCallOk || observation.assessmentReturnLength != 128) return 2202;
        if (observation.rawOutcomeWord > 2 || observation.commandEcho != observation.expectedCommand) return 2203;
        if (observation.rawOutcomeWord == 0) return 1000;
        if (observation.rawOutcomeWord == 1) return 1100;
        return 3204;
    }

    function classifyEvidence(Observation calldata observation) external pure returns (bytes32) {
        if (!observation.dependencyPresent || !observation.codeMatches) return bytes32(0);
        if (
            !observation.configurationCallOk || observation.configurationReturnLength != 32
                || observation.returnedConfiguration != observation.expectedConfiguration
        ) return bytes32(0);
        if (!observation.assessmentCallOk || observation.assessmentReturnLength != 128) return bytes32(0);
        if (
            observation.rawOutcomeWord > 2 || observation.commandEcho != observation.expectedCommand
                || observation.bindingEcho != observation.expectedBinding
        ) return bytes32(0);
        return observation.evidenceHash;
    }

    function classifyReason(Observation calldata observation) external pure returns (uint16) {
        if (!observation.dependencyPresent || !observation.codeMatches) {
            return 200;
        }
        if (
            !observation.configurationCallOk || observation.configurationReturnLength != 32
                || observation.returnedConfiguration != observation.expectedConfiguration
        ) {
            return 201;
        }
        if (!observation.assessmentCallOk || observation.assessmentReturnLength != 128) {
            return 202;
        }
        if (
            observation.rawOutcomeWord > uint8(TrustTypes.AssessmentOutcome.OPERATIONAL_FAILURE)
                || observation.commandEcho != observation.expectedCommand
                || observation.bindingEcho != observation.expectedBinding
        ) {
            return 203;
        }
        if (observation.rawOutcomeWord == uint8(TrustTypes.AssessmentOutcome.APPLICABLE)) {
            return 0;
        }
        if (observation.rawOutcomeWord == uint8(TrustTypes.AssessmentOutcome.REJECTED)) {
            return 100;
        }
        return 204;
    }
}
