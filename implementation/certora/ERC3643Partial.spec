using ERC3643PartialHarness as harness;

rule descriptor_is_always_partial_and_never_full(env e) {
    TrustKernelTypes.ProfileDescriptor descriptor = harness.trustProfile(e);

    assert descriptor.profileId ==
        0xa57a63d1a6def0dfce48359b5a32ef71ae339ac73fcb1cf8d123c03b7ada1fe6,
        "the current adapter must report the ERC-3643 Partial identifier";
    assert descriptor.profileKind == 3,
        "the current adapter must report ProfileKind.PARTIAL";
    assert !descriptor.full,
        "sealed-topology liveness must never elevate the current adapter to Full";
}

rule restriction_match_is_exact(env e, bool actual, bool owned) {
    bool matches = harness.restrictionMatchesExternal(e, actual, owned);
    assert matches <=> actual == owned,
        "the production restriction predicate must accept exactly equal actual and owned flags";
}

rule subject_observation_binds_actual_restriction(
    env e,
    uint256 balance,
    uint256 frozenTarget,
    uint256 actualFrozen,
    bool ownedRestricted
) {
    bytes32 clearHash = harness.subjectObservationHashExternal(
        e, balance, frozenTarget, actualFrozen, ownedRestricted, false
    );
    bytes32 restrictedHash = harness.subjectObservationHashExternal(
        e, balance, frozenTarget, actualFrozen, ownedRestricted, true
    );
    assert clearHash != restrictedHash,
        "the subject observation must consume the actual upstream restriction flag";
}

rule role_observation_binds_actual_restriction(
    env e,
    uint256 balance,
    uint256 custodyBacking
) {
    bytes32 clearHash = harness.roleObservationHashExternal(e, balance, false, custodyBacking);
    bytes32 restrictedHash = harness.roleObservationHashExternal(e, balance, true, custodyBacking);
    assert clearHash != restrictedHash,
        "source and destination role observations must consume the actual upstream restriction flag";
}
