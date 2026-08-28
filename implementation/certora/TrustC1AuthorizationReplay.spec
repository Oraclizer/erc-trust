using TrustTokenC1AuthorizationHarness as harness;

/*
 * C1 isolates the production authorization and once-consumption functions.
 * C2 owns dependency classification; C6 owns whole-transaction rollback.
 */

rule authority_and_delegation_match_exact_command(
    env e,
    TrustTypes.ActionRequest request
) {
    bytes32 digest = harness.c1ValidateAndConsume(e, request);
    bytes32 recordWitness = harness.c1RecordBindingWitness(e, request.actionId);
    bytes32 expectedWitness = harness.c1ExpectedRecordBindingWitness(e, request, digest);

    assert recordWitness == expectedWitness,
        "the consumed action record must bind the exact command, authority, authority epoch, and policy epoch";
    satisfy recordWitness == expectedWitness;
}

rule authority_policy_epochs_are_current(
    env e,
    TrustTypes.ActionRequest request
) {
    bytes32 digest;
    uint64 authorityEpochBefore;
    uint64 policyEpochBefore;
    digest, authorityEpochBefore, policyEpochBefore = harness.c1ValidateAndConsumeEpochWitness(e, request);

    assert authorityEpochBefore == request.authorityEpoch,
        "a successful command must match the authority epoch read from its prestate";
    assert policyEpochBefore == request.policyEpoch,
        "a successful command must match the policy epoch read from its prestate";
    satisfy digest != to_bytes32(0);
}

rule command_id_and_nonce_consumed_once_on_success(
    env e,
    TrustTypes.ActionRequest request
) {
    uint8 transitionWitness = harness.c1ValidateAndConsumeReplayWitness(e, request);
    storage applied = lastStorage;

    harness.c1ValidateAndConsume@withrevert(e, request);

    assert transitionWitness == 12 && lastReverted,
        "successful authorization must consume both replay keys and the same command must not replay";
    assert lastStorage[harness] == applied[harness],
        "replay rejection must preserve the successful poststate";
    satisfy transitionWitness == 12;
}

rule structural_rejection_preserves_authorization(
    env e,
    TrustTypes.ActionRequest request
) {
    require request.actionId == to_bytes32(0);
    storage initial = lastStorage;
    bool commandUsedBefore = harness.c1CommandUsed(e, request.actionId);
    bool nonceUsedBefore = harness.nonceUsed(e, request.authorityRef, request.authorityEpoch, request.nonce);

    harness.c1ValidateAndConsume@withrevert(e, request);

    assert lastReverted,
        "a structurally invalid command must revert";
    assert lastStorage[harness] == initial[harness],
        "structural rejection must preserve authorization storage";
    assert harness.c1CommandUsed(e, request.actionId) == commandUsedBefore
            && harness.nonceUsed(e, request.authorityRef, request.authorityEpoch, request.nonce) == nonceUsedBefore,
        "structural rejection must preserve both replay keys";
}

rule operational_failure_before_consumption_preserves_authorization(
    env e,
    TrustTypes.ActionRequest request
) {
    bytes32 digest = harness.c1ValidateOnly(e, request);
    storage initial = lastStorage;
    bool commandUsedBefore = harness.c1CommandUsed(e, request.actionId);
    bool nonceUsedBefore = harness.nonceUsed(e, request.authorityRef, request.authorityEpoch, request.nonce);

    harness.c1ValidateThenOperationalFailure@withrevert(e, request);

    assert lastReverted,
        "an operational failure before consumption must revert";
    assert lastStorage[harness] == initial[harness],
        "operational failure before consumption must preserve authorization storage";
    assert harness.c1CommandUsed(e, request.actionId) == commandUsedBefore
            && harness.nonceUsed(e, request.authorityRef, request.authorityEpoch, request.nonce) == nonceUsedBefore,
        "operational failure before consumption must preserve both replay keys";
    satisfy digest != to_bytes32(0);
}
