using TrustTokenC6TransactionHarness as harness;

rule successful_transaction_commits_storage_return_receipt_and_final_event(
    env e,
    TrustTypes.ActionRequest request,
    bytes32 digest,
    bytes32 evidence
) {
    require e.msg.sender == currentContract;
    bytes32 actualWitness;
    bytes32 expectedWitness;
    actualWitness, expectedWitness = harness.c6FreezeSuccessWitness(e, request, digest, evidence);

    assert actualWitness == expectedWitness,
        "successful transaction must bind returned, stored, record, and recomputed receipt hashes after auth, route, and effect commit";
    satisfy actualWitness == expectedWitness;
}

rule failed_transaction_restores_storage_nonce_ticket_receipt_and_logs(
    env e,
    TrustTypes.ActionRequest request,
    bytes32 digest,
    bytes32 evidence,
    bool forcePostApplyFailure
) {
    require e.msg.sender == currentContract;
    storage initial = lastStorage;
    harness.c6FreezeTransactionMaybeFail@withrevert(e, request, digest, evidence, forcePostApplyFailure);

    assert forcePostApplyFailure => lastReverted,
        "a selected post-apply failure must revert the transaction shell";
    if (forcePostApplyFailure) {
        assert lastStorage[harness] == initial[harness],
            "failed transaction must restore storage, nonce, ticket, receipt, and effect state";
    }
    satisfy !forcePostApplyFailure && !lastReverted;
}
