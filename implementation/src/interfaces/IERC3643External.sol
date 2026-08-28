// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

/// @notice Clean-room declarations for the narrow ERC-3643 surface used by the verified profile.
/// @dev This file contains signatures only; it is not derived from GPL implementation source.
interface IERC3643TokenView {
    function owner() external view returns (address);
    function isAgent(address account) external view returns (bool);
    function identityRegistry() external view returns (address);
    function compliance() external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function getFrozenTokens(address account) external view returns (uint256);
    function isFrozen(address account) external view returns (bool);
}

interface IERC3643TokenMutator {
    function forcedTransfer(address from, address to, uint256 amount) external returns (bool);
    function setAddressFrozen(address account, bool frozen) external;
    function freezePartialTokens(address account, uint256 amount) external;
    function unfreezePartialTokens(address account, uint256 amount) external;
}

interface IERC3643IdentityRegistry {
    function isVerified(address account) external view returns (bool);
}

interface IERC3643Compliance {
    function canTransfer(address from, address to, uint256 amount) external view returns (bool);
}

/// @notice Required extension for an ERC-TRUST ERC-3643 Full conformance unit.
/// @dev A deployment is not Full merely because these views return expected values. The token
///      runtime code hash must also match the audited code hash sealed by ProfileGovernor.
interface IERC3643ExclusiveTopology {
    function exclusiveAgent() external view returns (address);
}
