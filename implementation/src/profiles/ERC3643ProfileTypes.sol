// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

/// @notice Implementation-only records of the ERC-3643 Verified Full profile.
/// @dev None of these structs is a kernel hash preimage. The kernel wire format (requests, receipts,
///      records returned by the kernel views) lives in the generated kernel types.
library ERC3643ProfileTypes {
    /// @dev One declared entry of the exact import manifest: the upstream frozen amount and address
    ///      freeze flag an account carries at the seal. Entries are sorted by strictly increasing
    ///      account and every entry declares nonzero state; an empty manifest is the fresh zero-state
    ///      declaration.
    struct ImportEntry {
        address account;
        uint256 frozenAmount;
        bool restricted;
    }

    /// @dev Per-kind dependency binding of the profile, captured at the seal. bindingHash follows the
    ///      native bindingHash preimage with the sealed binding as the configuration digest and the
    ///      profile identifier as the schema.
    struct DependencyBinding {
        address dependency;
        bytes32 codeId;
        bytes32 bindingHash;
    }

    /// @dev Adapter-owned upstream state of one account: the absolute frozen target, the frozen
    ///      amount the adapter last verified upstream, and the address freeze flag.
    struct OwnedState {
        uint256 frozenTarget;
        uint256 appliedFrozen;
        bool restricted;
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
}
