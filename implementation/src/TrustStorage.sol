// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustTypes} from "./TrustTypes.sol";

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
    mapping(address => TrustTypes.EffectHead) internal _freezeHeads;
    mapping(address => TrustTypes.EffectHead) internal _restrictionHeads;

    mapping(bytes32 => TrustTypes.Authority) internal _authorities;
    mapping(bytes32 => mapping(address => TrustTypes.Delegation)) internal _delegations;
    mapping(bytes32 => mapping(uint64 => mapping(uint256 => bool))) internal _usedNonces;
    mapping(bytes32 => bool) internal _usedCommandIds;
    mapping(bytes32 => bool) internal _usedGovernanceIds;

    mapping(bytes32 => TrustTypes.ActionRecord) internal _actions;
    mapping(bytes32 => TrustTypes.EffectRecord) internal _effects;
    mapping(bytes32 => TrustTypes.Receipt) internal _receipts;
    mapping(bytes32 => TrustTypes.CustodyRecord) internal _custody;
    mapping(bytes32 => TrustTypes.SettlementRecord) internal _settlements;
    mapping(bytes32 => TrustTypes.EntitlementRecord) internal _entitlements;
    mapping(bytes32 => bool) internal _consumedEntitlements;
    mapping(bytes32 => bool) internal _terminalCases;

    mapping(TrustTypes.BindingKind => TrustTypes.Binding) internal _bindings;
    TrustTypes.RouteTicket internal _routeTicket;
    uint256 internal _entered;
}
