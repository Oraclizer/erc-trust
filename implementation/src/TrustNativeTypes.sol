// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

/// @notice Implementation-only records of the native profile.
/// @dev None of these structs is a kernel hash preimage. The kernel wire format (requests, receipts,
///      records returned by the kernel views) lives in the generated kernel types.
library TrustNativeTypes {
    enum RouteKind {
        NONE,
        ACTION,
        REVERSAL
    }

    /// @dev Per-kind dependency binding of the native profile; bindingHash follows hashes.bindingHash.
    struct Binding {
        address dependency;
        bytes32 codeId;
        bytes32 configurationDigest;
        bytes32 schema;
        uint64 epoch;
        bytes32 bindingHash;
    }

    struct Authority {
        address account;
        uint64 epoch;
        bool active;
    }

    /// @dev Per-subject live head of an overlay family (FREEZE or RESTRICT).
    struct EffectHead {
        bytes32 actionId;
        bytes32 effectHash;
        uint64 generation;
    }

    /// @dev Per-action position in the owning case's amendment chain.
    struct EffectRecord {
        bytes32 parentActionId;
        bytes32 effectHash;
        uint64 generation;
    }

    /// @dev Per-case custody opened by SEIZE and closed by RELEASE or a custody disposition.
    struct CustodyRecord {
        address custodian;
        address declaredPriorHolder;
        uint256 encumberedAmount;
        bytes32 actionId;
        bool active;
    }

    /// @dev Request fields the action record does not retain but the exact-use ERC-7943 route needs
    ///      when the sensitive selector applies the prepared action inside the same transaction.
    struct PendingCommitments {
        bytes32 provenanceCommitment;
        bytes32 settlementCommitment;
        bytes32 proceedsCommitment;
        bytes32 entitlementCommitment;
    }

    /// @dev Validated reversal awaiting its exact-use ERC-7943 route application.
    struct PendingReversal {
        bytes32 actionId;
        bytes32 provenanceCommitment;
        bytes32 authorityRef;
        bytes32 assessmentEvidence;
        uint8 reversal;
    }

    /// @dev Same-transaction exact-use ticket for the sensitive ERC-7943 selectors.
    struct RouteTicket {
        bytes32 commandId;
        bytes32 calldataHash;
        bytes32 dependencyRoot;
        bytes4 selector;
        RouteKind routeKind;
        uint64 dependencyEpoch;
        bool live;
    }
}
