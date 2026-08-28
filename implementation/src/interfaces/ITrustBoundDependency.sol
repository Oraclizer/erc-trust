// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

/// @notice Read-only dependency boundary used by the Native reference profile.
interface ITrustBoundDependency {
    function configurationDigest() external view returns (bytes32);

    function assess(
        bytes32 commandHash,
        uint8 action,
        address subject,
        address destination,
        uint256 amount,
        bytes32 bindingHash,
        uint64 bindingEpoch
    ) external view returns (uint8 outcome, bytes32 commandEcho, bytes32 bindingEcho, bytes32 evidenceHash);
}
