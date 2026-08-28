// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

library TrustTypes {
    bytes32 internal constant DOMAIN = keccak256("ERC-TRUST/reference-v1");
    uint32 internal constant VERSION = 1;

    enum ActionKind {
        FREEZE,
        SEIZE,
        CONFISCATE,
        LIQUIDATE,
        RESTRICT,
        RECOVER
    }

    enum ReversalKind {
        UNFREEZE,
        RELEASE,
        UNRESTRICT
    }

    enum AssessmentOutcome {
        APPLICABLE,
        REJECTED,
        OPERATIONAL_FAILURE
    }

    enum Lifecycle {
        NONE,
        PREPARED,
        APPLIED,
        CANCELLED,
        REVERSED
    }

    enum BindingKind {
        POLICY,
        IDENTITY,
        SETTLEMENT,
        ENTITLEMENT
    }

    enum RouteKind {
        NONE,
        ACTION,
        REVERSAL
    }

    struct ActionRequest {
        bytes32 domain;
        bytes32 actionId;
        ActionKind action;
        address subject;
        address source;
        address destination;
        address custodian;
        uint256 amount;
        bytes32 caseId;
        bytes32 scopeHash;
        bytes32 policyCommitment;
        bytes32 provenanceCommitment;
        bytes32 settlementCommitment;
        bytes32 proceedsCommitment;
        bytes32 entitlementCommitment;
        bytes32 authorityRef;
        uint64 authorityEpoch;
        uint64 policyEpoch;
        uint256 nonce;
        uint48 validAfter;
        uint48 validBefore;
    }

    struct ReversalRequest {
        bytes32 domain;
        bytes32 reversalId;
        bytes32 actionId;
        ReversalKind reversal;
        bytes32 authorityRef;
        uint64 authorityEpoch;
        uint256 nonce;
        uint48 validAfter;
        uint48 validBefore;
    }

    struct ActionRecord {
        ActionKind action;
        Lifecycle lifecycle;
        address subject;
        address source;
        address destination;
        address custodian;
        uint256 amount;
        uint256 priorAmount;
        bool priorFlag;
        bytes32 caseId;
        bytes32 authorityRef;
        uint64 authorityEpoch;
        uint64 policyEpoch;
        bytes32 commandHash;
        bytes32 evidenceHash;
        bytes32 receiptHash;
    }

    struct Receipt {
        bytes32 commandId;
        uint8 commandKind;
        address source;
        address destination;
        uint256 amount;
        bytes32 caseId;
        bytes32 policyBinding;
        bytes32 provenanceCommitment;
        bytes32 preState;
        bytes32 postState;
        bytes32 externalCommitment;
        bytes32 receiptHash;
    }

    struct CustodyRecord {
        address custodian;
        address declaredPriorHolder;
        uint256 encumberedAmount;
        bytes32 actionId;
        bytes32 parentActionId;
        bytes32 effectHash;
        uint64 generation;
        bool active;
    }

    struct EffectHead {
        bytes32 actionId;
        bytes32 effectHash;
        uint64 generation;
    }

    struct EffectRecord {
        bytes32 parentActionId;
        bytes32 effectHash;
        uint64 generation;
    }

    struct SettlementRecord {
        address destination;
        uint256 amount;
        bytes32 settlementCommitment;
        bytes32 proceedsCommitment;
        bytes32 evidenceHash;
        bool consumedCustody;
    }

    struct EntitlementRecord {
        address destination;
        uint256 amount;
        bytes32 entitlementCommitment;
        bytes32 evidenceHash;
        bool consumed;
    }

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

    struct Delegation {
        uint256 actionMask;
        bytes32 scopeHash;
        uint48 validUntil;
        uint64 authorityEpoch;
    }

    struct RouteTicket {
        bytes32 commandId;
        bytes32 routeKey;
        bytes32 calldataHash;
        bytes32 bindingHash;
        bytes4 selector;
        RouteKind routeKind;
        uint8 actionOrReversal;
        uint64 authorityEpoch;
        uint64 policyEpoch;
        bool live;
    }
}
