// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {IERC3643TokenView} from "../interfaces/IERC3643External.sol";
import {IERCTrustKernel} from "../generated/IERCTrustKernel.sol";
import {TrustZeroAddress} from "../TrustErrors.sol";
import {ERC3643HookCompliance} from "./ERC3643HookCompliance.sol";
import {ERC3643ProfileTypes} from "./ERC3643ProfileTypes.sol";

interface IHookTokenPause {
    function paused() external view returns (bool);
}

/// @notice Inert token owner created by the constructing endpoint.
/// @dev It has no token administration, Agent management, registry rebinding, or arbitrary-call surface.
contract ERC3643HookGovernor {
    bytes32 internal constant SEAL_DOMAIN = keccak256("ERC-TRUST/v2/erc3643-verified-full/seal");

    address public immutable token;
    address public immutable identityRegistry;
    address public immutable compliance;
    address public immutable bootstrapAuthority;
    bytes32 public immutable expectedTokenCodeId;
    bytes32 public immutable expectedComplianceCodeId;
    bytes32 public immutable expectedRegistryCodeId;

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

    constructor(address token_, address registry_, address compliance_, bytes32 tokenCodeId_) {
        if (token_ == address(0) || registry_ == address(0) || compliance_ == address(0) || tokenCodeId_ == bytes32(0)) revert TrustZeroAddress();
        token = token_;
        identityRegistry = registry_;
        compliance = compliance_;
        bootstrapAuthority = msg.sender;
        expectedTokenCodeId = tokenCodeId_;
        expectedComplianceCodeId = compliance_.codehash;
        expectedRegistryCodeId = registry_.codehash;
    }

    /// @notice Seals the empty regulatory state while the endpoint is still constructing.
    function sealFresh() external returns (bytes32 binding) {
        address adapter = bootstrapAuthority;
        if (msg.sender != adapter) revert IERCTrustKernel.TrustUnauthorized(msg.sender, bytes32(0));
        require(!topologySealed && _topologyMatches(adapter), "invalid fresh topology");
        ERC3643ProfileTypes.ImportEntry[] memory empty = new ERC3643ProfileTypes.ImportEntry[](0);
        importManifestHash = keccak256(abi.encode(empty));
        binding = _binding(adapter, importManifestHash);
        exclusiveAdapter = adapter;
        sealedBinding = binding;
        topologySealed = true;
        emit ProfileSealed(adapter, expectedTokenCodeId, binding, importManifestHash, 0);
    }

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
        if (
            adapter != bootstrapAuthority || token.codehash != expectedTokenCodeId
                || compliance.codehash != expectedComplianceCodeId
                || identityRegistry.codehash != expectedRegistryCodeId
        ) return false;
        IERC3643TokenView upstream = IERC3643TokenView(token);
        if (
            upstream.owner() != address(this) || upstream.identityRegistry() != identityRegistry
                || upstream.compliance() != compliance || !upstream.isAgent(adapter) || IHookTokenPause(token).paused()
        ) return false;
        ERC3643HookCompliance hook = ERC3643HookCompliance(compliance);
        return hook.factory() == adapter && hook.token() == token && hook.endpoint() == adapter && hook.bound();
    }
}
