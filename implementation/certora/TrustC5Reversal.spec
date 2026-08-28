using TrustTokenC5ReversalHarness as harness;

rule current_effect_head_reversal_restores_prior_state(env e, bytes32 reversalId, bytes32 actionId, bytes32 parentActionId, address subject, uint256 amount, uint256 priorAmount, bytes32 caseId, bytes32 currentEffectHash, bytes32 parentEffectHash, uint64 currentGeneration, bytes32 digest) {
    bytes32 actual; bytes32 expected;
    actual, expected = harness.c5UnfreezeWitness(e, reversalId, actionId, parentActionId, subject, amount, priorAmount, caseId, currentEffectHash, parentEffectHash, currentGeneration, digest);
    assert actual == expected, "current effect head reversal must pop to its exact parent and restore prior state";
    satisfy actual == expected;
}

rule stale_aba_duplicate_out_of_order_reversal_stutters(env e, bytes32 reversalId, bytes32 actionId, bytes32 parentActionId, bytes32 staleHeadActionId, address subject, uint256 amount, uint256 priorAmount, bytes32 caseId, uint64 currentGeneration, bytes32 digest, bool stale) {
    require staleHeadActionId != actionId;
    storage initial = lastStorage;
    harness.c5ValidateCurrentEffectMaybeStale@withrevert(e, reversalId, actionId, parentActionId, staleHeadActionId, subject, amount, priorAmount, caseId, currentGeneration, digest, stale);
    assert stale => lastReverted, "stale or out-of-order effect head must reject reversal";
    if (stale) {
        assert lastStorage[harness] == initial[harness], "stale reversal must preserve the whole prestate";
    }
    satisfy !stale && !lastReverted;
}
