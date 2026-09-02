using TrustTokenC3RouteHarness as harness;

rule erc7943_ticket_is_exact_use(
    env e,
    bytes32 commandId,
    bytes4 selector,
    bytes32 calldataHash,
    uint8 actionOrReversal,
    uint64 authorityEpoch,
    uint64 policyEpoch
) {
    require e.msg.sender == currentContract;
    bytes32 preparedWitness;
    bytes32 expectedWitness;
    bytes32 consumedWitness;
    bool liveAfter;
    preparedWitness, expectedWitness, consumedWitness, liveAfter = harness.c3PrepareConsumeWitness(
        e, commandId, selector, calldataHash, actionOrReversal, authorityEpoch, policyEpoch
    );
    storage consumed = lastStorage;

    harness.c3ConsumeOnly@withrevert(e, selector, calldataHash);

    assert preparedWitness == expectedWitness && consumedWitness == preparedWitness && !liveAfter,
        "the exact ticket must be observed once and deleted by its matching route";
    assert lastReverted,
        "the same route ticket must not be reusable";
    assert lastStorage[harness] == consumed[harness],
        "route reuse rejection must preserve the consumed poststate";
    satisfy preparedWitness == expectedWitness && consumedWitness == preparedWitness && !liveAfter;
}

rule set_frozen_route_matches_exact_command(
    env e,
    bytes32 commandId,
    address account,
    uint256 amount,
    uint8 actionOrReversal,
    uint64 authorityEpoch,
    uint64 policyEpoch
) {
    require e.msg.sender == currentContract;
    bytes32 preparedWitness;
    bytes32 expectedWitness;
    bytes32 consumedWitness;
    bool liveAfter;
    preparedWitness, expectedWitness, consumedWitness, liveAfter = harness.c3SetFrozenPrepareConsumeWitness(
        e, commandId, account, amount, actionOrReversal, authorityEpoch, policyEpoch
    );

    assert preparedWitness == expectedWitness && consumedWitness == preparedWitness && !liveAfter,
        "setFrozenTokens must consume the exact selector, calldata, binding, epochs, and command ticket";
    satisfy preparedWitness == expectedWitness && consumedWitness == preparedWitness && !liveAfter;
}

rule route_mismatch_and_inner_failure_roll_back_ticket_and_authorization(
    env e,
    bytes32 commandId,
    bytes4 preparedSelector,
    bytes32 preparedCalldataHash,
    bytes4 consumeSelector,
    bytes32 consumeCalldataHash,
    uint8 actionOrReversal,
    uint64 authorityEpoch,
    uint64 policyEpoch,
    TrustTypes.ActionRequest request,
    bytes32 digest,
    bool forceInnerFailure
) {
    require e.msg.sender == currentContract;
    require preparedSelector != consumeSelector || preparedCalldataHash != consumeCalldataHash;
    storage initial = lastStorage;

    harness.c3PrepareThenConsumeMismatch@withrevert(
        e,
        commandId,
        preparedSelector,
        preparedCalldataHash,
        consumeSelector,
        consumeCalldataHash,
        actionOrReversal,
        authorityEpoch,
        policyEpoch
    );
    bool mismatchReverted = lastReverted;
    storage mismatchPost = lastStorage;

    harness.c3AuthorizationRouteThenInnerFailure@withrevert(
        e, request, digest, preparedSelector, preparedCalldataHash, forceInnerFailure
    ) at initial;

    assert mismatchReverted,
        "selector or calldata mismatch must reject the prepared route";
    assert mismatchPost[harness] == initial[harness],
        "route mismatch must roll back the transient ticket";
    assert forceInnerFailure => lastReverted,
        "a selected inner route failure must revert the wrapper transaction";
    if (forceInnerFailure) {
        assert lastStorage[harness] == initial[harness],
            "inner route failure must roll back ticket and authorization writes";
    }
    satisfy !forceInnerFailure && !lastReverted;
}
