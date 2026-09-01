using TrustFreezeDirectionHarness as harness;

definition validFreezeShape(TrustTypes.ActionRequest request) returns bool =
    request.action == TrustTypes.ActionKind.FREEZE
    && request.subject != 0
    && request.source == request.subject
    && request.destination == 0
    && request.custodian == 0
    && request.caseId != to_bytes32(0)
    && request.scopeHash != to_bytes32(0)
    && request.provenanceCommitment != to_bytes32(0)
    && request.settlementCommitment == to_bytes32(0)
    && request.proceedsCommitment == to_bytes32(0)
    && request.entitlementCommitment == to_bytes32(0);

rule strict_increase_is_the_only_accepted_freeze_shape(
    env e,
    TrustTypes.ActionRequest request,
    uint256 currentTarget
) {
    require validFreezeShape(request);
    require request.amount > currentTarget;

    uint256 observed = harness.validateFreezeShapeWithSeed(e, request, currentTarget);

    assert observed == currentTarget,
        "the production shape guard must accept a strictly increasing target without changing the seeded target";
    satisfy observed == currentTarget;
}

rule nonincreasing_freeze_shape_reverts_and_restores_storage(
    env e,
    TrustTypes.ActionRequest request,
    uint256 currentTarget
) {
    require validFreezeShape(request);
    require request.amount <= currentTarget;
    storage initial = lastStorage;

    harness.validateFreezeShapeWithSeed@withrevert(e, request, currentTarget);

    assert lastReverted,
        "the production shape guard must reject an equal or decreasing FREEZE target";
    assert lastStorage[harness] == initial[harness],
        "a rejected nonincreasing FREEZE shape must restore the complete harness storage";
}
