using TrustToken as token;
using CertoraUnresolvedHarness as harness;

methods {
    function harness.originalCallee() external returns (address) envfree;
    function harness.callersSender() external returns (address) envfree;
    function harness.executingAddr() external returns (address) envfree;
    function harness.inSize() external returns (uint256) envfree;
    function harness.outSize() external returns (uint256) envfree;
    function harness.callValue() external returns (uint256) envfree;
    function harness.callGas() external returns (uint256) envfree;
}

rule unresolved_staticcall_captures_context_and_allows_canonical_success(
    env e,
    TrustTypes.ActionRequest request
) {
    harness.setMode(e, 0);
    require request.action == TrustTypes.ActionKind.FREEZE;

    bytes32 returned = token.executeRegulatoryAction(e, request);

    assert harness.originalCallee() != 0,
        "unresolved dependency target must be captured";
    assert harness.executingAddr() != 0,
        "STATICCALL executing address must be captured";
    assert harness.inSize() == 228,
        "the final assessment STATICCALL must preserve its exact calldata length";
    assert harness.callValue() == 0,
        "the redirected STATICCALL must preserve zero call value";
    assert token.getFrozenTokens(e, request.subject) == request.amount,
        "canonical harness response must reach the exact FREEZE effect";
    satisfy returned != to_bytes32(0);
}

rule unresolved_staticcall_denial_reverts_and_stutters(
    env e,
    TrustTypes.ActionRequest request
) {
    harness.setMode(e, 1);
    storage initial = lastStorage;

    token.executeRegulatoryAction@withrevert(e, request);

    assert lastReverted,
        "canonical denial must revert";
    assert lastStorage[token] == initial[token],
        "canonical denial must preserve token storage";
    assert !token.nonceUsed(e, request.authorityRef, request.authorityEpoch, request.nonce),
        "canonical denial must not consume authorization";
}

rule unresolved_staticcall_operational_matrix_reverts_and_stutters(
    env e,
    TrustTypes.ActionRequest request,
    uint8 dependencyMode
) {
    require dependencyMode >= 2 && dependencyMode <= 9;
    harness.setMode(e, dependencyMode);
    storage initial = lastStorage;

    token.executeRegulatoryAction@withrevert(e, request);

    assert lastReverted,
        "revert, 32-byte, 160-byte, wrong echo, noncanonical outcome, and config failure modes must revert";
    assert lastStorage[token] == initial[token],
        "all operational modes must preserve token storage";
    assert !token.nonceUsed(e, request.authorityRef, request.authorityEpoch, request.nonce),
        "all operational modes must preserve authorization";
}
