// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustTokenC3RouteDeletionMutant} from "../../src/TrustTokenC3RouteDeletionMutant.sol";
import {TrustTypes} from "../../src/TrustTypes.sol";
import {ERC7943RouteTicket} from "../../src/ERC7943RouteTicket.sol";
import {IERC7943Fungible} from "../../src/interfaces/IERC7943.sol";

/// @notice Verification-only C3 seam over the production exact-use route functions.
contract TrustTokenC3RouteHarness is TrustTokenC3RouteDeletionMutant {
    error C3ForcedInnerFailure();

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address governor_,
        address initialHolder,
        uint256 initialSupply,
        bytes32 authorityRef,
        address initialAuthority,
        address policy,
        address identity,
        address settlement,
        address entitlement,
        bytes32 schema
    )
        TrustTokenC3RouteDeletionMutant(
            name_,
            symbol_,
            decimals_,
            governor_,
            initialHolder,
            initialSupply,
            authorityRef,
            initialAuthority,
            policy,
            identity,
            settlement,
            entitlement,
            schema
        )
    {}

    function c3PrepareConsumeWitness(
        bytes32 commandId,
        bytes4 selector,
        bytes32 calldataHash,
        uint8 actionOrReversal,
        uint64 authorityEpoch,
        uint64 policyEpoch
    ) external returns (bytes32 preparedWitness, bytes32 expectedWitness, bytes32 consumedWitness, bool liveAfter) {
        _prepareRoute(
            commandId,
            selector,
            calldataHash,
            TrustTypes.RouteKind.ACTION,
            actionOrReversal,
            authorityEpoch,
            policyEpoch
        );
        TrustTypes.RouteTicket memory prepared = _routeTicket;
        preparedWitness = _c3TicketWitness(prepared);
        expectedWitness = _c3ExpectedTicketWitness(
            commandId, selector, calldataHash, prepared.bindingHash, actionOrReversal, authorityEpoch, policyEpoch
        );
        TrustTypes.RouteTicket memory consumed = _consumeRoute(selector, calldataHash);
        consumedWitness = _c3TicketWitness(consumed);
        liveAfter = _routeTicket.live;
    }

    function c3SetFrozenPrepareConsumeWitness(
        bytes32 commandId,
        address account,
        uint256 amount,
        uint8 actionOrReversal,
        uint64 authorityEpoch,
        uint64 policyEpoch
    ) external returns (bytes32 preparedWitness, bytes32 expectedWitness, bytes32 consumedWitness, bool liveAfter) {
        bytes memory data = abi.encodeCall(IERC7943Fungible.setFrozenTokens, (account, amount));
        bytes4 selector = IERC7943Fungible.setFrozenTokens.selector;
        bytes32 calldataHash = keccak256(data);
        _prepareRoute(
            commandId,
            selector,
            calldataHash,
            TrustTypes.RouteKind.ACTION,
            actionOrReversal,
            authorityEpoch,
            policyEpoch
        );
        TrustTypes.RouteTicket memory prepared = _routeTicket;
        preparedWitness = _c3TicketWitness(prepared);
        expectedWitness = _c3ExpectedTicketWitness(
            commandId, selector, calldataHash, prepared.bindingHash, actionOrReversal, authorityEpoch, policyEpoch
        );
        TrustTypes.RouteTicket memory consumed = _consumeRoute(selector, calldataHash);
        consumedWitness = _c3TicketWitness(consumed);
        liveAfter = _routeTicket.live;
    }

    function c3ConsumeOnly(bytes4 selector, bytes32 calldataHash) external returns (bytes32 consumedWitness) {
        consumedWitness = _c3TicketWitness(_consumeRoute(selector, calldataHash));
    }

    function c3PrepareThenConsumeMismatch(
        bytes32 commandId,
        bytes4 preparedSelector,
        bytes32 preparedCalldataHash,
        bytes4 consumeSelector,
        bytes32 consumeCalldataHash,
        uint8 actionOrReversal,
        uint64 authorityEpoch,
        uint64 policyEpoch
    ) external {
        _prepareRoute(
            commandId,
            preparedSelector,
            preparedCalldataHash,
            TrustTypes.RouteKind.ACTION,
            actionOrReversal,
            authorityEpoch,
            policyEpoch
        );
        _consumeRoute(consumeSelector, consumeCalldataHash);
    }

    function c3AuthorizationRouteThenInnerFailure(
        TrustTypes.ActionRequest calldata request,
        bytes32 digest,
        bytes4 selector,
        bytes32 calldataHash,
        bool forceInnerFailure
    ) external {
        _consumeActionAuthorization(request, digest);
        _prepareRoute(
            request.actionId,
            selector,
            calldataHash,
            TrustTypes.RouteKind.ACTION,
            uint8(request.action),
            request.authorityEpoch,
            request.policyEpoch
        );
        if (forceInnerFailure) revert C3ForcedInnerFailure();
    }

    function _c3ExpectedTicketWitness(
        bytes32 commandId,
        bytes4 selector,
        bytes32 calldataHash,
        bytes32 bindingHash,
        uint8 actionOrReversal,
        uint64 authorityEpoch,
        uint64 policyEpoch
    ) private view returns (bytes32) {
        return keccak256(
            abi.encode(
                commandId,
                ERC7943RouteTicket.key(
                    address(this), selector, calldataHash, bindingHash, authorityEpoch, policyEpoch, commandId
                ),
                calldataHash,
                bindingHash,
                selector,
                TrustTypes.RouteKind.ACTION,
                actionOrReversal,
                authorityEpoch,
                policyEpoch,
                true
            )
        );
    }

    function _c3TicketWitness(TrustTypes.RouteTicket memory ticket) private pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ticket.commandId,
                ticket.routeKey,
                ticket.calldataHash,
                ticket.bindingHash,
                ticket.selector,
                ticket.routeKind,
                ticket.actionOrReversal,
                ticket.authorityEpoch,
                ticket.policyEpoch,
                ticket.live
            )
        );
    }
}
