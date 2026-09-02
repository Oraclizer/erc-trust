using TrustToken as token;

definition MAX_UINT256() returns uint256 =
    0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

/*
 * ERC-TRUST bounded reference-implementation rules.
 *
 * These rules are implementation evidence for the exact compiled candidate.
 * They do not prove external policy, identity, settlement, entitlement, legal,
 * deployment, proxy, or migration truth.
 */

rule invalid_erc165_identifier_is_false(env e) {
    assert !token.supportsInterface(e, to_bytes4(0xffffffff)),
        "ERC-165 invalid identifier must never be reported";
}

rule erc7943_view_matches_frozen_floor(
    env e,
    address from,
    address to,
    uint256 amount
) {
    uint256 balance = token.balanceOf(e, from);
    uint256 frozen = token.getFrozenTokens(e, from);
    bool send = token.canSend(e, from);
    bool receive = token.canReceive(e, to);
    bool allowed = token.canTransfer(e, from, to, amount);

    if (!send || !receive) {
        assert !allowed,
            "canTransfer must include endpoint restrictions";
    } else if (frozen >= balance) {
        assert allowed == (amount == 0),
            "fully or over-frozen accounts permit only zero";
    } else {
        assert allowed == (amount <= balance - frozen),
            "canTransfer must expose exactly the unfrozen floor";
    }
}

rule ordinary_transfer_exact_delta_and_frame(env e, address to, uint256 amount) {
    address from = e.msg.sender;
    uint256 fromBefore = token.balanceOf(e, from);
    uint256 toBefore = token.balanceOf(e, to);
    uint256 frozenBefore = token.getFrozenTokens(e, from);
    uint256 supplyBefore = token.totalSupply(e);
    require from != 0 && to != 0 && from != to;
    require token.canTransfer(e, from, to, amount);
    require toBefore <= MAX_UINT256() - amount;

    bool result = token.transfer(e, to, amount);
    require result;

    assert token.balanceOf(e, from) + amount == fromBefore,
        "ordinary transfer debits exactly amount";
    assert token.balanceOf(e, to) == toBefore + amount,
        "ordinary transfer credits exactly amount";
    assert token.getFrozenTokens(e, from) == frozenBefore,
        "ordinary transfer does not change frozen state";
    assert token.totalSupply(e) == supplyBefore,
        "ordinary transfer preserves supply";
}

rule ordinary_transfer_floor_failure_stutters(env e, address to, uint256 amount) {
    address from = e.msg.sender;
    require amount > 0;
    require !token.canTransfer(e, from, to, amount);
    storage initial = lastStorage;

    token.transfer@withrevert(e, to, amount);

    assert lastReverted,
        "ordinary transfer outside the ERC-7943 predicate must revert";
    assert lastStorage[token] == initial[token],
        "failed ordinary transfer must preserve complete token storage";
}

rule successful_action_is_terminal_and_supply_preserving(
    env e,
    TrustTypes.ActionRequest request
) {
    require !token.routeLive(e);
    uint256 supplyBefore = token.totalSupply(e);
    bytes32 receiptHash = token.executeRegulatoryAction(e, request);
    TrustTypes.Receipt receipt = token.receipt(e, request.actionId);

    assert receipt.receiptHash == receiptHash,
        "return value and receipt must agree";
    assert token.totalSupply(e) == supplyBefore,
        "all six regulatory actions preserve supply";
    assert !token.routeLive(e),
        "canonical action execution must not leave a live route ticket";
}

rule successful_reversal_is_terminal_and_supply_preserving(
    env e,
    TrustTypes.ReversalRequest request
) {
    require !token.routeLive(e);
    uint256 supplyBefore = token.totalSupply(e);
    bytes32 receiptHash = token.executeRegulatoryReversal(e, request);
    TrustTypes.ActionRecord original = token.actionRecord(e, request.actionId);
    TrustTypes.Receipt receipt = token.receipt(e, request.reversalId);

    assert original.lifecycle == TrustTypes.Lifecycle.REVERSED,
        "successful reversal must make its original terminal";
    assert receipt.receiptHash == receiptHash,
        "reversal return value and receipt must agree";
    assert token.totalSupply(e) == supplyBefore,
        "all supported reversals preserve supply";
    assert !token.routeLive(e),
        "canonical reversal execution must not leave a live route ticket";
}

rule structurally_invalid_action_reverts_and_stutters(
    env e,
    TrustTypes.ActionRequest request
) {
    require request.actionId == to_bytes32(0);
    storage initial = lastStorage;

    token.executeRegulatoryAction@withrevert(e, request);

    assert lastReverted,
        "a zero action identifier must revert";
    assert lastStorage[token] == initial[token],
        "structural rejection must preserve complete token storage";
}

rule all_external_mutators_are_classified(method f)
filtered {
    f -> f.contract == currentContract && !f.isView && !f.isPure
}
{
    bool classified =
        f.selector == sig:approve(address, uint256).selector
        || f.selector == sig:transfer(address, uint256).selector
        || f.selector == sig:transferFrom(address, address, uint256).selector
        || f.selector == 0x9da23539
        || f.selector == 0x7aab169b
        || f.selector == 0x9295b54c
        || f.selector == 0x75c28d96
        || f.selector == sig:setFrozenTokens(address, uint256).selector
        || f.selector == sig:forcedTransfer(address, address, uint256).selector
        || f.selector == sig:configureAuthority(bytes32, address, bool, bytes32, uint256).selector
        || f.selector == sig:configureDelegation(bytes32, address, uint256, bytes32, uint48, bytes32, uint256).selector
        || f.selector == 0xf60d7b6f;

    assert classified,
        "every external token mutator must be in the reviewed call graph";
}
