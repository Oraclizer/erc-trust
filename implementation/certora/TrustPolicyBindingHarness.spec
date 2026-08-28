using TrustPolicyBindingHarness as harness;

rule classifier_code_matches_complete_partition(
    env e,
    TrustPolicyBindingHarness.Observation observation
) {
    uint256 actualCode = harness.classifyCode(e, observation);
    bool correct = false;

    if (!observation.dependencyPresent || !observation.codeMatches) {
        correct = actualCode == 2200;
    } else if (
        !observation.configurationCallOk
            || observation.configurationReturnLength != 32
            || observation.returnedConfiguration != observation.expectedConfiguration
    ) {
        correct = actualCode == 2201;
    } else if (!observation.assessmentCallOk || observation.assessmentReturnLength != 128) {
        correct = actualCode == 2202;
    } else if (
        observation.rawOutcomeWord > 2
            || observation.commandEcho != observation.expectedCommand
            || observation.bindingEcho != observation.expectedBinding
    ) {
        correct = actualCode == 2203;
    } else if (observation.rawOutcomeWord == 0) {
        correct = actualCode == 1000;
    } else if (observation.rawOutcomeWord == 1) {
        correct = actualCode == 1100;
    } else {
        correct = actualCode == 3204;
    }

    assert correct, "classifier code must match the complete 200 through 204 partition";
}

rule classifier_evidence_matches_partition(
    env e,
    TrustPolicyBindingHarness.Observation observation
) {
    bytes32 actualEvidence = harness.classifyEvidence(e, observation);
    bool clearsEvidence =
        !observation.dependencyPresent
            || !observation.codeMatches
            || !observation.configurationCallOk
            || observation.configurationReturnLength != 32
            || observation.returnedConfiguration != observation.expectedConfiguration
            || !observation.assessmentCallOk
            || observation.assessmentReturnLength != 128
            || observation.rawOutcomeWord > 2
            || observation.commandEcho != observation.expectedCommand
            || observation.bindingEcho != observation.expectedBinding;

    bool correct = clearsEvidence
        ? actualEvidence == to_bytes32(0)
        : actualEvidence == observation.evidenceHash;
    assert correct, "classifier evidence must clear on malformed inputs and preserve canonical evidence";
}

rule applicable_inhabitant(env e, TrustPolicyBindingHarness.Observation observation) {
    satisfy harness.classifyCode(e, observation) == 1000;
}

rule denial_inhabitant(env e, TrustPolicyBindingHarness.Observation observation) {
    satisfy harness.classifyCode(e, observation) == 1100;
}

rule reason_200_inhabitant(env e, TrustPolicyBindingHarness.Observation observation) {
    satisfy harness.classifyCode(e, observation) == 2200;
}

rule reason_201_inhabitant(env e, TrustPolicyBindingHarness.Observation observation) {
    satisfy harness.classifyCode(e, observation) == 2201;
}

rule reason_202_inhabitant(env e, TrustPolicyBindingHarness.Observation observation) {
    satisfy harness.classifyCode(e, observation) == 2202;
}

rule reason_203_inhabitant(env e, TrustPolicyBindingHarness.Observation observation) {
    satisfy harness.classifyCode(e, observation) == 2203;
}

rule reason_204_inhabitant(env e, TrustPolicyBindingHarness.Observation observation) {
    satisfy harness.classifyCode(e, observation) == 3204;
}
