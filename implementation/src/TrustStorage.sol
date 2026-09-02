// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustKernelTypes} from "./generated/IERCTrustKernel.sol";
import {TrustNativeTypes} from "./TrustNativeTypes.sol";

abstract contract TrustStorage {
    string public name;
    string public symbol;
    uint8 public immutable decimals;
    uint256 internal _totalSupply;
    address public immutable governor;

    mapping(address => uint256) internal _balances;
    mapping(address => mapping(address => uint256)) internal _allowances;
    mapping(address => uint256) internal _frozen;
    mapping(address => bool) internal _restricted;
    mapping(address => uint256) internal _custodyBacking;
    mapping(address => TrustNativeTypes.EffectHead) internal _freezeHeads;
    mapping(address => TrustNativeTypes.EffectHead) internal _restrictionHeads;

    mapping(bytes32 => TrustNativeTypes.Authority) internal _authorities;
    mapping(bytes32 => mapping(uint64 => mapping(uint256 => bool))) internal _usedNonces;
    mapping(bytes32 => bool) internal _usedGovernanceIds;

    mapping(bytes32 => TrustKernelTypes.ActionRecord) internal _actions;
    mapping(bytes32 => TrustNativeTypes.EffectRecord) internal _effects;
    mapping(bytes32 => TrustKernelTypes.Receipt) internal _receipts;
    mapping(bytes32 => TrustKernelTypes.CaseRecord) internal _cases;
    mapping(bytes32 => TrustNativeTypes.CustodyRecord) internal _custody;
    mapping(bytes32 => bool) internal _consumedEntitlements;
    mapping(bytes32 => TrustNativeTypes.PendingCommitments) internal _pendingCommitments;
    mapping(bytes32 => TrustNativeTypes.PendingReversal) internal _pendingReversals;

    mapping(TrustKernelTypes.BindingKind => TrustNativeTypes.Binding) internal _bindings;
    bytes32 internal _dependencyRoot;
    uint64 internal _dependencyEpoch;
    TrustNativeTypes.RouteTicket internal _routeTicket;
    uint256 internal _entered;
}
