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

/*
 * Current-profile financial-core rules for the pinned Native Full candidate.
 * Certora's official unresolved-call harness preserves the raw call context
 * and mode matrix. It does not assume approval, matching echoes, or external
 * truth.
 */

rule freeze_success_sets_absolute_target_and_consistent_receipt(
    env e,
    TrustTypes.ActionRequest request
) {
    harness.setMode(e, 0);
    require request.action == TrustTypes.ActionKind.FREEZE;
    require !token.routeLive(e);

    bytes32 returned = token.executeRegulatoryAction(e, request);
    TrustTypes.Receipt stored = token.receipt(e, request.actionId);

    assert token.getFrozenTokens(e, request.subject) == request.amount,
        "FREEZE must set the exact absolute target";
    assert stored.receiptHash == returned,
        "stored and returned receipt hashes must agree";
    assert token.nonceUsed(e, request.authorityRef, request.authorityEpoch, request.nonce),
        "successful FREEZE must consume its exact nonce";
    assert !token.routeLive(e),
        "direct Native FREEZE must not leave a route ticket";
    satisfy stored.receiptHash == returned;
}

rule nonincreasing_freeze_reverts_and_stutters(
    env e,
    TrustTypes.ActionRequest request
) {
    harness.setMode(e, 0);
    require request.action == TrustTypes.ActionKind.FREEZE;
    require request.amount <= token.getFrozenTokens(e, request.subject);
    storage initial = lastStorage;

    token.executeRegulatoryAction@withrevert(e, request);

    assert lastReverted,
        "equal or decreasing FREEZE must revert";
    assert lastStorage[token] == initial[token],
        "nonincreasing FREEZE must preserve complete token storage";
    assert !token.nonceUsed(e, request.authorityRef, request.authorityEpoch, request.nonce),
        "nonincreasing FREEZE must not consume authorization";
}

rule successful_action_consumes_once_and_replay_stutters(
    env e,
    TrustTypes.ActionRequest request
) {
    harness.setMode(e, 0);
    bytes32 returned = token.executeRegulatoryAction(e, request);
    require returned != to_bytes32(0);
    storage applied = lastStorage;

    token.executeRegulatoryAction@withrevert(e, request);

    assert lastReverted,
        "an already-applied action must not replay";
    assert lastStorage[token] == applied[token],
        "replay rejection must preserve the complete successful poststate";
    assert token.nonceUsed(e, request.authorityRef, request.authorityEpoch, request.nonce),
        "the successful nonce remains consumed exactly once";
}

rule structural_rejection_preserves_authorization_and_storage(
    env e,
    TrustTypes.ActionRequest request
) {
    require request.actionId == to_bytes32(0);
    storage initial = lastStorage;

    token.executeRegulatoryAction@withrevert(e, request);

    assert lastReverted,
        "a zero action ID must revert";
    assert lastStorage[token] == initial[token],
        "structural rejection must preserve complete token storage";
    assert !token.nonceUsed(e, request.authorityRef, request.authorityEpoch, request.nonce),
        "structural rejection must not consume authorization";
}

rule dependency_denial_reverts_and_stutters(
    env e,
    TrustTypes.ActionRequest request
) {
    harness.setMode(e, 1);
    storage initial = lastStorage;

    token.executeRegulatoryAction@withrevert(e, request);

    assert lastReverted,
        "canonical dependency denial must revert";
    assert lastStorage[token] == initial[token],
        "dependency denial must preserve complete token storage";
    assert !token.nonceUsed(e, request.authorityRef, request.authorityEpoch, request.nonce),
        "dependency denial must not consume authorization";
}

rule dependency_operational_matrix_reverts_and_stutters(
    env e,
    TrustTypes.ActionRequest request,
    uint8 dependencyMode
) {
    require dependencyMode >= 2 && dependencyMode <= 9;
    harness.setMode(e, dependencyMode);
    storage initial = lastStorage;

    token.executeRegulatoryAction@withrevert(e, request);

    assert lastReverted,
        "operational, revert, malformed, echo, and config modes must revert";
    assert lastStorage[token] == initial[token],
        "dependency operational matrix must preserve complete token storage";
    assert !token.nonceUsed(e, request.authorityRef, request.authorityEpoch, request.nonce),
        "dependency operational matrix must not consume authorization";
}

rule successful_action_receipt_and_supply_frame(
    env e,
    TrustTypes.ActionRequest request
) {
    harness.setMode(e, 0);
    uint256 supplyBefore = token.totalSupply(e);
    bytes32 returned = token.executeRegulatoryAction(e, request);
    TrustTypes.Receipt stored = token.receipt(e, request.actionId);

    assert token.totalSupply(e) == supplyBefore,
        "regulatory action must preserve total supply";
    assert stored.receiptHash == returned,
        "receipt storage and return value must agree";
    assert !token.routeLive(e),
        "successful action must leave no live route";
}
