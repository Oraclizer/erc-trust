// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {IERC3643TokenView, IERC3643ExclusiveTopology} from "../interfaces/IERC3643External.sol";
import {TrustOperationalFailure, TrustUnauthorized, TrustInvalidCommand, TrustZeroAddress} from "../TrustErrors.sol";

/// @notice One-way topology seal for the ERC-3643 Verified Full profile.
/// @dev After sealing, this contract intentionally exposes no token administration or arbitrary-call surface.
contract ProfileGovernor {
    bytes32 internal constant PROFILE_DOMAIN = keccak256("ERC-TRUST/ERC3643-PROFILE-V1");

    address public immutable token;
    address public immutable identityRegistry;
    address public immutable compliance;
    address public immutable bootstrapAuthority;
    bytes32 public immutable expectedTokenCodeId;

    address public exclusiveAdapter;
    bytes32 public sealedBinding;
    bool public topologySealed;

    event ProfileSealed(address indexed adapter, bytes32 indexed tokenCodeId, bytes32 indexed binding);

    constructor(
        address token_,
        address identityRegistry_,
        address compliance_,
        address bootstrapAuthority_,
        bytes32 expectedTokenCodeId_
    ) {
        if (
            token_ == address(0) || identityRegistry_ == address(0) || compliance_ == address(0)
                || bootstrapAuthority_ == address(0) || expectedTokenCodeId_ == bytes32(0)
        ) {
            revert TrustZeroAddress();
        }
        token = token_;
        identityRegistry = identityRegistry_;
        compliance = compliance_;
        bootstrapAuthority = bootstrapAuthority_;
        expectedTokenCodeId = expectedTokenCodeId_;
    }

    function seal(address adapter) external returns (bytes32 binding) {
        if (msg.sender != bootstrapAuthority) revert TrustUnauthorized(msg.sender, bytes32(0));
        if (topologySealed || adapter == address(0)) revert TrustInvalidCommand(bytes32(0), 301);
        if (!_topologyMatches(adapter)) {
            revert TrustOperationalFailure(bytes32(0), 302, bytes32(uint256(uint160(token))));
        }

        binding = keccak256(
            abi.encode(
                PROFILE_DOMAIN,
                block.chainid,
                address(this),
                token,
                expectedTokenCodeId,
                adapter,
                identityRegistry,
                compliance
            )
        );
        exclusiveAdapter = adapter;
        sealedBinding = binding;
        topologySealed = true;
        emit ProfileSealed(adapter, expectedTokenCodeId, binding);
    }

    function isFull(address adapter) public view returns (bool) {
        return topologySealed && adapter == exclusiveAdapter && _topologyMatches(adapter)
            && sealedBinding
                == keccak256(
                abi.encode(
                PROFILE_DOMAIN,
                block.chainid,
                address(this),
                token,
                expectedTokenCodeId,
                adapter,
                identityRegistry,
                compliance
            )
            );
    }

    function _topologyMatches(address adapter) internal view returns (bool) {
        if (token.codehash != expectedTokenCodeId) return false;
        try IERC3643TokenView(token).owner() returns (address value) {
            if (value != address(this)) return false;
        } catch {
            return false;
        }
        try IERC3643TokenView(token).identityRegistry() returns (address value) {
            if (value != identityRegistry) return false;
        } catch {
            return false;
        }
        try IERC3643TokenView(token).compliance() returns (address value) {
            if (value != compliance) return false;
        } catch {
            return false;
        }
        try IERC3643TokenView(token).isAgent(adapter) returns (bool value) {
            if (!value) return false;
        } catch {
            return false;
        }
        try IERC3643ExclusiveTopology(token).exclusiveAgent() returns (address value) {
            return value == adapter;
        } catch {
            return false;
        }
    }
}
