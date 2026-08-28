using TrustTokenC4FreezeHarness as harness;

rule freeze_sets_absolute_target_and_effect_provenance(
    env e,
    bytes32 actionId,
    address subject,
    uint256 amount,
    bytes32 caseId,
    uint256 oldFrozen,
    bytes32 parentActionId,
    bytes32 parentEffectHash,
    uint64 parentGeneration,
    bytes32 digest,
    bytes32 evidence
) {
    bytes32 actualWitness;
    bytes32 expectedWitness;
    actualWitness, expectedWitness = harness.c4FreezeApplyWitness(
        e,
        actionId,
        subject,
        amount,
        caseId,
        oldFrozen,
        parentActionId,
        parentEffectHash,
        parentGeneration,
        digest,
        evidence
    );

    assert actualWitness == expectedWitness,
        "FREEZE must set the absolute target and preserve exact parent, generation, and effect provenance";
    satisfy actualWitness == expectedWitness;
}

rule freeze_precondition_failure_stutters(
    env e,
    bytes32 actionId,
    address subject,
    uint256 amount,
    bytes32 caseId,
    uint256 oldFrozen,
    bytes32 parentActionId,
    bytes32 parentEffectHash,
    uint64 parentGeneration,
    bytes32 digest,
    bytes32 evidence,
    bool makePrepared
) {
    storage initial = lastStorage;
    harness.c4FreezeApplyWithLifecycle@withrevert(
        e,
        actionId,
        subject,
        amount,
        caseId,
        oldFrozen,
        parentActionId,
        parentEffectHash,
        parentGeneration,
        digest,
        evidence,
        makePrepared
    );

    assert !makePrepared => lastReverted,
        "FREEZE must reject a non-PREPARED action record";
    if (!makePrepared) {
        assert lastStorage[harness] == initial[harness],
            "FREEZE precondition failure must preserve the whole prestate";
    }
    satisfy makePrepared && !lastReverted;
}
