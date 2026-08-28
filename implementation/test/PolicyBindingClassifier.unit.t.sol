// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustPolicyBindingHarness} from "./mocks/TrustPolicyBindingHarness.sol";

contract PolicyBindingClassifierUnitTest {
    TrustPolicyBindingHarness internal harness;

    function setUp() public {
        harness = new TrustPolicyBindingHarness();
    }

    function testCanonicalOutcomePartitionAndEvidence() external view {
        TrustPolicyBindingHarness.Observation memory observation = _canonicalObservation(0);
        assert(harness.classifyCode(observation) == 1000);
        assert(harness.classifyReason(observation) == 0);
        assert(harness.classifyEvidence(observation) == observation.evidenceHash);

        observation.rawOutcomeWord = 1;
        assert(harness.classifyCode(observation) == 1100);
        assert(harness.classifyReason(observation) == 100);

        observation.rawOutcomeWord = 2;
        assert(harness.classifyCode(observation) == 3204);
        assert(harness.classifyReason(observation) == 204);
    }

    function testMalformedObservationsFailClosed() external view {
        TrustPolicyBindingHarness.Observation memory observation = _canonicalObservation(0);

        observation.dependencyPresent = false;
        _assertOperationalFailure(observation, 2200, 200);

        observation = _canonicalObservation(0);
        observation.configurationReturnLength = 31;
        _assertOperationalFailure(observation, 2201, 201);

        observation = _canonicalObservation(0);
        observation.assessmentReturnLength = 32;
        _assertOperationalFailure(observation, 2202, 202);

        observation = _canonicalObservation(3);
        _assertOperationalFailure(observation, 2203, 203);

        observation = _canonicalObservation(0);
        observation.bindingEcho = bytes32(uint256(observation.expectedBinding) ^ 1);
        _assertOperationalFailure(observation, 2203, 203);
    }

    function _canonicalObservation(uint256 outcome)
        internal
        pure
        returns (TrustPolicyBindingHarness.Observation memory observation)
    {
        bytes32 configuration = keccak256("CONFIGURATION");
        bytes32 command = keccak256("COMMAND");
        bytes32 binding = keccak256("BINDING");
        observation = TrustPolicyBindingHarness.Observation({
            dependencyPresent: true,
            codeMatches: true,
            configurationCallOk: true,
            configurationReturnLength: 32,
            returnedConfiguration: configuration,
            expectedConfiguration: configuration,
            assessmentCallOk: true,
            assessmentReturnLength: 128,
            rawOutcomeWord: outcome,
            commandEcho: command,
            expectedCommand: command,
            bindingEcho: binding,
            expectedBinding: binding,
            evidenceHash: keccak256("EVIDENCE")
        });
    }

    function _assertOperationalFailure(
        TrustPolicyBindingHarness.Observation memory observation,
        uint256 expectedCode,
        uint16 expectedReason
    ) internal view {
        assert(harness.classifyCode(observation) == expectedCode);
        assert(harness.classifyReason(observation) == expectedReason);
        assert(harness.classifyEvidence(observation) == bytes32(0));
    }
}
