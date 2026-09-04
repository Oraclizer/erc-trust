// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {IERCTrustKernel} from "../generated/IERCTrustKernel.sol";
import {IERC3643TokenView, IERC3643ExclusiveTopology} from "../interfaces/IERC3643External.sol";
import {ERC3643ProfileTypes} from "./ERC3643ProfileTypes.sol";
import {TrustZeroAddress} from "../TrustErrors.sol";

/// @notice The adapter side of the seal handshake: the governor activates the adapter it seals.
interface IERC3643SealActivation {
    function activateSeal(ERC3643ProfileTypes.ImportEntry[] calldata entries) external;
}

/// @notice One-way topology seal of the ERC-3643 Partial reference profile.
/// @dev The governor is the inert owner of the underlying token: after the seal it exposes no token
///      administration, Agent management, registry rebinding, or arbitrary-call surface, so the sealed
///      topology can only drift through the token itself, and the adapter observes that drift.
contract ProfileGovernor {
    /// @dev keccak256("ERC-TRUST/v2/erc3643-partial/seal")
    bytes32 internal constant SEAL_DOMAIN = keccak256("ERC-TRUST/v2/erc3643-partial/seal");
    uint16 internal constant REASON_SEAL_INVALID = 301;
    uint16 internal constant REASON_TOPOLOGY_MISMATCH_AT_SEAL = 302;

    address public immutable token;
    address public immutable identityRegistry;
    address public immutable compliance;
    address public immutable bootstrapAuthority;
    bytes32 public immutable expectedTokenCodeId;

    address public exclusiveAdapter;
    bytes32 public sealedBinding;
    bytes32 public importManifestHash;
    bool public topologySealed;

    event ProfileSealed(
        address indexed adapter,
        bytes32 indexed tokenCodeId,
        bytes32 indexed binding,
        bytes32 importManifestHash,
        uint256 importedEntries
    );

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

    /// @notice Seals the topology once, commits the exact import manifest, and activates the adapter.
    /// @dev The whole seal reverts when the topology does not match, when the manifest is not canonical,
    ///      or when the adapter cannot verify an entry against the live upstream state.
    function seal(address adapter, ERC3643ProfileTypes.ImportEntry[] calldata entries)
        external
        returns (bytes32 binding)
    {
        if (msg.sender != bootstrapAuthority) revert IERCTrustKernel.TrustUnauthorized(msg.sender, bytes32(0));
        if (topologySealed || adapter == address(0)) {
            revert IERCTrustKernel.TrustOperationalFailure(bytes32(0), REASON_SEAL_INVALID, _tokenRef());
        }
        if (!_topologyMatches(adapter)) {
            revert IERCTrustKernel.TrustOperationalFailure(bytes32(0), REASON_TOPOLOGY_MISMATCH_AT_SEAL, _tokenRef());
        }
        bytes32 manifestHash = manifestHashOf(entries);
        binding = _binding(adapter, manifestHash);
        exclusiveAdapter = adapter;
        sealedBinding = binding;
        importManifestHash = manifestHash;
        topologySealed = true;
        emit ProfileSealed(adapter, expectedTokenCodeId, binding, manifestHash, entries.length);
        IERC3643SealActivation(adapter).activateSeal(entries);
    }

    /// @notice Canonical hash of the declared import entries; reverts when an entry is not canonical.
    /// @dev Canonical: accounts strictly increasing, no zero account, every entry declares nonzero state.
    ///      This checks included entries only and does not prove that no upstream state was omitted.
    function manifestHashOf(ERC3643ProfileTypes.ImportEntry[] calldata entries) public view returns (bytes32) {
        address previous;
        for (uint256 i = 0; i < entries.length; ++i) {
            ERC3643ProfileTypes.ImportEntry calldata entry = entries[i];
            if (
                entry.account == address(0) || entry.account <= previous
                    || (entry.frozenAmount == 0 && !entry.restricted)
            ) {
                revert IERCTrustKernel.TrustOperationalFailure(bytes32(0), REASON_SEAL_INVALID, _tokenRef());
            }
            previous = entry.account;
        }
        return keccak256(abi.encode(entries));
    }

    /// @notice True only while the sealed topology holds for the sealed adapter.
    /// @dev This is an operational liveness predicate, not a Full conformance classification.
    function sealedTopologyLive(address adapter) public view returns (bool) {
        return topologySealed && adapter == exclusiveAdapter && _topologyMatches(adapter)
            && sealedBinding == _binding(adapter, importManifestHash);
    }

    function _binding(address adapter, bytes32 manifestHash) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                SEAL_DOMAIN,
                block.chainid,
                address(this),
                token,
                expectedTokenCodeId,
                adapter,
                identityRegistry,
                compliance,
                manifestHash
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

    function _tokenRef() internal view returns (bytes32) {
        return bytes32(uint256(uint160(token)));
    }
}
