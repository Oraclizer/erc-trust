using TrustTokenC4RemainingHarness as harness;

rule restrict_sets_independent_overlay(env e, bytes32 actionId, address subject, bytes32 caseId, bool oldRestricted, bytes32 parentActionId, bytes32 parentEffectHash, uint64 parentGeneration, bytes32 digest, bytes32 evidence) {
    bytes32 actual; bytes32 expected;
    actual, expected = harness.c4RestrictWitness(e, actionId, subject, caseId, oldRestricted, parentActionId, parentEffectHash, parentGeneration, digest, evidence);
    assert actual == expected, "RESTRICT must set an independent overlay with exact provenance";
    satisfy actual == expected;
}

rule seize_preserves_beneficial_balance_and_creates_exact_custody(env e, bytes32 actionId, address source, address custodian, uint256 amount, bytes32 caseId, uint256 sourceBalance, uint256 custodianBalance, uint256 oldCustodyBacking, bytes32 digest, bytes32 evidence) {
    bytes32 actual; bytes32 expected;
    actual, expected = harness.c4SeizeWitness(e, actionId, source, custodian, amount, caseId, sourceBalance, custodianBalance, oldCustodyBacking, digest, evidence);
    assert actual == expected, "SEIZE must move exact physical balance and create exact custody and backing";
    satisfy actual == expected;
}

rule direct_disposition_is_terminal_and_confined(env e, bytes32 actionId, address source, address destination, uint256 amount, bytes32 caseId, uint256 sourceBalance, uint256 destinationBalance, bytes32 digest, bytes32 evidence) {
    bytes32 actual; bytes32 expected;
    actual, expected = harness.c4DirectDispositionWitness(e, actionId, source, destination, amount, caseId, sourceBalance, destinationBalance, digest, evidence);
    assert actual == expected, "direct disposition must move the exact amount and terminate only its case";
    satisfy actual == expected;
}

rule custody_disposition_consumes_exact_backing_once(env e, bytes32 actionId, bytes32 priorCustodyActionId, bytes32 priorParentActionId, address beneficialHolder, address custodian, address destination, uint256 amount, bytes32 caseId, uint256 custodianBalance, uint256 destinationBalance, uint256 oldCustodyBacking, bytes32 priorEffectHash, uint64 priorGeneration, bytes32 digest, bytes32 evidence) {
    bytes32 actual; bytes32 expected;
    actual, expected = harness.c4CustodyDispositionWitness(e, actionId, priorCustodyActionId, priorParentActionId, beneficialHolder, custodian, destination, amount, caseId, custodianBalance, destinationBalance, oldCustodyBacking, priorEffectHash, priorGeneration, digest, evidence);
    assert actual == expected, "custody disposition must consume exact backing once and terminate the case";
    satisfy actual == expected;
}
