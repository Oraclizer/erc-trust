using TrustFreezePilot as pilot;
using MockBoundPolicy as boundPolicy;

/*
 * Preserved pilot scope:
 * Native FREEZE -> staged ERC-7943 setFrozenTokens -> ordinary-transfer gate
 * -> canonical receipt. These rules do not claim full ERC-TRUST refinement.
 */

rule direct_and_staged_freeze_converge(
    env e,
    TrustFreezePilot.ActionRequest request,
    TrustFreezePilot.AuthorizationEnvelope authorization
) {
    storage initial = lastStorage;

    TrustFreezePilot.PreparedRoute initialPrepared =
        pilot.preparedRoute(e, authorization.authorizationId) at initial;
    require !initialPrepared.exists;
    bytes32 routeKey = pilot.prepareRegulatoryAction(e, request, authorization) at initial;
    pilot.setFrozenTokens(e, request.subject, request.amount);

    bytes32 stagedFingerprint = pilot.stateFingerprint(
        e,
        request.actionId,
        authorization.authorizationId,
        request.caseId,
        routeKey,
        request.subject,
        request.destination,
        request.nonce
    );
    TrustFreezePilot.ReceiptView stagedReceipt = pilot.actionReceipt(e, request.actionId);
    uint256 stagedFrozen = pilot.getFrozenTokens(e, request.subject);
    bytes32 stagedRoute = pilot.routeAuthorization(e, routeKey);

    bytes32 directReturn = pilot.executeRegulatoryAction(e, request, authorization) at initial;
    bytes32 directFingerprint = pilot.stateFingerprint(
        e,
        request.actionId,
        authorization.authorizationId,
        request.caseId,
        routeKey,
        request.subject,
        request.destination,
        request.nonce
    );
    TrustFreezePilot.ReceiptView directReceipt = pilot.actionReceipt(e, request.actionId);
    uint256 directFrozen = pilot.getFrozenTokens(e, request.subject);
    bytes32 directRoute = pilot.routeAuthorization(e, routeKey);

    assert directFingerprint == stagedFingerprint,
        "direct and staged FREEZE must converge on the active pilot state projection";
    assert directReturn == directReceipt.receiptHash,
        "direct execution must return its canonical receipt";
    assert directReceipt == stagedReceipt,
        "direct and staged FREEZE must project the same receipt";
    assert directFrozen == stagedFrozen && directFrozen == request.amount,
        "direct and staged FREEZE must set the same absolute frozen amount";
    assert directRoute == to_bytes32(0) && stagedRoute == to_bytes32(0),
        "both routes must end without a consumable ticket";
}

rule rejected_assessment_reverts_and_stutters(
    env e,
    TrustFreezePilot.ActionRequest request,
    TrustFreezePilot.AuthorizationEnvelope authorization
) {
    TrustFreezePilot.AssessmentResult assessment =
        pilot.assessRegulatoryAction(e, request, authorization);
    require assessment.outcome == TrustFreezePilot.AssessmentOutcome.REJECTED;

    storage initial = lastStorage;
    pilot.executeRegulatoryAction@withrevert(e, request, authorization);
    bool reverted = lastReverted;
    storage post = lastStorage;

    assert reverted, "a rejected assessment must not execute";
    assert post[pilot] == initial[pilot],
        "rejected execution must preserve the complete pilot storage";
}

rule operational_failure_reverts_and_stutters(
    env e,
    TrustFreezePilot.ActionRequest request,
    TrustFreezePilot.AuthorizationEnvelope authorization
) {
    /*
     * Select the deterministic code-identity failure before either low-level
     * policy call. Reading the linked double's live runtime-code hash avoids
     * assuming cross-call correlation for unresolved STATICCALL returndata.
     */
    bytes32 livePolicyCodeId = boundPolicy.runtimeCodeId(e);
    require pilot.policyCodeId(e) != livePolicyCodeId;

    storage initial = lastStorage;
    pilot.executeRegulatoryAction@withrevert(e, request, authorization);
    bool reverted = lastReverted;
    storage post = lastStorage;

    assert reverted, "an operational failure must not execute";
    assert post[pilot] == initial[pilot],
        "operational failure must preserve the complete pilot storage";
}

rule wrong_route_caller_preserves_target_ticket(
    env prepareEnv,
    env wrongEnv,
    TrustFreezePilot.ActionRequest request,
    TrustFreezePilot.AuthorizationEnvelope authorization
) {
    bytes32 routeKey = pilot.prepareRegulatoryAction(prepareEnv, request, authorization);
    TrustFreezePilot.PreparedRoute targetPrepared =
        pilot.preparedRoute(prepareEnv, authorization.authorizationId);
    require wrongEnv.msg.sender != authorization.actor;

    pilot.setFrozenTokens@withrevert(wrongEnv, request.subject, request.amount);

    assert pilot.routeAuthorization(prepareEnv, routeKey) == authorization.authorizationId,
        "a wrong caller must not consume the target route";
    assert pilot.preparedRoute(prepareEnv, authorization.authorizationId) == targetPrepared,
        "a wrong caller must not mutate the target prepared route";
}

rule wrong_route_calldata_preserves_target_ticket(
    env e,
    TrustFreezePilot.ActionRequest request,
    TrustFreezePilot.AuthorizationEnvelope authorization,
    uint256 wrongAmount
) {
    bytes32 routeKey = pilot.prepareRegulatoryAction(e, request, authorization);
    TrustFreezePilot.PreparedRoute targetPrepared =
        pilot.preparedRoute(e, authorization.authorizationId);
    require wrongAmount != request.amount;

    pilot.setFrozenTokens@withrevert(e, request.subject, wrongAmount);

    assert pilot.routeAuthorization(e, routeKey) == authorization.authorizationId,
        "wrong calldata must not consume the target route";
    assert pilot.preparedRoute(e, authorization.authorizationId) == targetPrepared,
        "wrong calldata must not mutate the target prepared route";
}

rule cancelled_ticket_cannot_be_used(
    env prepareEnv,
    env cancelEnv,
    TrustFreezePilot.ActionRequest request,
    TrustFreezePilot.AuthorizationEnvelope authorization
) {
    bytes32 routeKey = pilot.prepareRegulatoryAction(prepareEnv, request, authorization);
    address governingAuthority = pilot.authority(cancelEnv);
    require cancelEnv.msg.sender == governingAuthority;
    pilot.cancelAuthorization(cancelEnv, authorization.authorizationId);

    assert pilot.routeAuthorization(cancelEnv, routeKey) == to_bytes32(0),
        "cancellation must delete the exact route";
    assert !pilot.preparedRoute(cancelEnv, authorization.authorizationId).exists,
        "cancellation must delete the prepared route";
    assert pilot.authorizationStatus(cancelEnv, authorization.authorizationId)
        == TrustFreezePilot.AuthorizationStatus.CANCELLED,
        "cancellation must mark the authorization cancelled";
    assert pilot.nonceStatus(
        cancelEnv,
        authorization.authorityRef,
        request.authorityEpoch,
        request.nonce
    ) == TrustFreezePilot.AuthorizationStatus.CANCELLED,
        "cancellation must mark the nonce cancelled";

    pilot.setFrozenTokens@withrevert(prepareEnv, request.subject, request.amount);
    assert lastReverted, "a cancelled route is no longer a ticket";
}

rule stale_binding_call_preserves_target_ticket(
    env prepareEnv,
    env governanceEnv,
    TrustFreezePilot.ActionRequest request,
    TrustFreezePilot.AuthorizationEnvelope authorization,
    bytes32 governanceAuthorizationId,
    uint256 governanceNonce
) {
    bytes32 routeKey = pilot.prepareRegulatoryAction(prepareEnv, request, authorization);
    TrustFreezePilot.PreparedRoute targetPrepared =
        pilot.preparedRoute(prepareEnv, authorization.authorizationId);
    address governingAuthority = pilot.authority(governanceEnv);
    require governanceEnv.msg.sender == governingAuthority;
    pilot.rebindPolicy(
        governanceEnv,
        boundPolicy,
        governanceAuthorizationId,
        governanceNonce
    );

    pilot.setFrozenTokens@withrevert(prepareEnv, request.subject, request.amount);

    assert pilot.routeAuthorization(governanceEnv, routeKey) == authorization.authorizationId,
        "a post-rebind call must not consume the stale target route";
    assert pilot.preparedRoute(governanceEnv, authorization.authorizationId) == targetPrepared,
        "a post-rebind call must not mutate the stale prepared route";
}

rule consumed_ticket_cannot_replay(
    env e,
    TrustFreezePilot.ActionRequest request,
    TrustFreezePilot.AuthorizationEnvelope authorization
) {
    bytes32 routeKey = pilot.prepareRegulatoryAction(e, request, authorization);
    pilot.setFrozenTokens(e, request.subject, request.amount);

    assert pilot.routeAuthorization(e, routeKey) == to_bytes32(0),
        "consumption must delete the exact route";
    assert !pilot.preparedRoute(e, authorization.authorizationId).exists,
        "consumption must delete the prepared route";
    assert pilot.authorizationStatus(e, authorization.authorizationId)
        == TrustFreezePilot.AuthorizationStatus.CONSUMED,
        "consumption must mark the authorization consumed";
    assert pilot.nonceStatus(
        e,
        authorization.authorityRef,
        request.authorityEpoch,
        request.nonce
    ) == TrustFreezePilot.AuthorizationStatus.CONSUMED,
        "consumption must mark the nonce consumed";

    pilot.setFrozenTokens@withrevert(e, request.subject, request.amount);
    bool reverted = lastReverted;
    assert reverted, "an exact-use route ticket must not replay";
}

rule transfer_respects_frozen_floor(env e, address to, uint256 amount) {
    address from = e.msg.sender;
    uint256 fromBalance = pilot.balanceOf(e, from);
    uint256 frozen = pilot.getFrozenTokens(e, from);
    require amount > 0;
    if (frozen < fromBalance) {
        require amount > fromBalance - frozen;
    }
    storage initial = lastStorage;

    pilot.transfer@withrevert(e, to, amount);
    bool reverted = lastReverted;
    storage post = lastStorage;

    assert reverted, "ordinary transfer must not spend the frozen floor";
    assert post[pilot] == initial[pilot],
        "a rejected ordinary transfer must preserve complete pilot storage";
}

rule can_transfer_query_matches_balance_and_frozen_floor(
    env e,
    address from,
    address to,
    uint256 amount
) {
    uint256 balance = pilot.balanceOf(e, from);
    uint256 frozen = pilot.getFrozenTokens(e, from);
    bool allowed = pilot.canTransfer(e, from, to, amount);

    if (from == 0 || to == 0 || amount > balance) {
        assert !allowed,
            "canTransfer must reject zero endpoints and over-balance amounts";
    } else if (frozen >= balance) {
        assert allowed == (amount == 0),
            "a fully frozen balance permits only a zero-amount transfer";
    } else {
        assert allowed == (amount <= balance - frozen),
            "canTransfer must expose exactly the unfrozen balance";
    }
}

rule successful_transfer_frame(env e, address to, uint256 amount) {
    address from = e.msg.sender;
    uint256 fromBefore = pilot.balanceOf(e, from);
    uint256 toBefore = pilot.balanceOf(e, to);
    uint256 frozenBefore = pilot.getFrozenTokens(e, from);
    uint256 supplyBefore = pilot.totalSupply(e);
    require from != 0 && to != 0 && to != from;
    require frozenBefore <= fromBefore;
    require amount <= fromBefore - frozenBefore;

    bool result = pilot.transfer(e, to, amount);
    require result;
    uint256 fromAfter = pilot.balanceOf(e, from);
    uint256 toAfter = pilot.balanceOf(e, to);
    uint256 frozenAfter = pilot.getFrozenTokens(e, from);
    uint256 supplyAfter = pilot.totalSupply(e);

    assert fromAfter + amount == fromBefore,
        "successful transfer must debit exactly amount";
    assert toAfter == toBefore + amount,
        "successful transfer must credit exactly amount";
    assert frozenAfter == frozenBefore,
        "ordinary transfer must not mutate frozen state";
    assert supplyAfter == supplyBefore,
        "ordinary transfer must preserve total supply";
}

rule transfer_from_respects_frozen_floor(
    env e,
    address from,
    address to,
    uint256 amount
) {
    uint256 fromBalance = pilot.balanceOf(e, from);
    uint256 frozen = pilot.getFrozenTokens(e, from);
    require amount > 0;
    if (frozen < fromBalance) {
        require amount > fromBalance - frozen;
    }
    storage initial = lastStorage;

    pilot.transferFrom@withrevert(e, from, to, amount);
    bool reverted = lastReverted;
    storage post = lastStorage;

    assert reverted, "transferFrom must not spend the frozen floor";
    assert post[pilot] == initial[pilot],
        "a rejected transferFrom must preserve complete pilot storage";
}

rule all_external_mutators_are_classified(method f)
filtered {
    f -> f.contract == currentContract && !f.isView && !f.isPure
}
{
    bool classified = false;
    if (f.selector == sig:approve(address, uint256).selector) {
        classified = true;
    }
    if (f.selector == sig:transfer(address, uint256).selector) {
        classified = true;
    }
    if (f.selector == sig:transferFrom(address, address, uint256).selector) {
        classified = true;
    }
    if (f.selector == 0x1841f9e8) {
        classified = true;
    }
    if (f.selector == 0x757310d7) {
        classified = true;
    }
    if (f.selector == 0xa4af941e) {
        classified = true;
    }
    if (f.selector == sig:setFrozenTokens(address, uint256).selector) {
        classified = true;
    }
    if (f.selector == sig:cancelAuthorization(bytes32).selector) {
        classified = true;
    }
    if (f.selector == sig:rebindPolicy(address, bytes32, uint256).selector) {
        classified = true;
    }
    assert classified,
        "every external mutator must belong to the declared pilot call graph";
}
