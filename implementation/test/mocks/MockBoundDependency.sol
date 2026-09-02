// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {ITrustBoundDependency} from "../../src/generated/IERCTrustKernel.sol";

contract MockBoundDependency is ITrustBoundDependency {
    enum Mode {
        APPLICABLE,
        REJECTED,
        OPERATIONAL_FAILURE,
        REVERTING,
        MALFORMED,
        WRONG_ECHO,
        NONCANONICAL,
        LONG_RETURN
    }

    Mode public immutable mode;
    bytes32 public config;

    constructor(Mode mode_, bytes32 config_) {
        mode = mode_;
        config = config_;
    }

    /// @dev Test-only configuration drift; the bound endpoint must observe it as a dependency mismatch.
    function setConfig(bytes32 config_) external {
        config = config_;
    }

    function configurationDigest() external view returns (bytes32) {
        return config;
    }

    function assess(bytes32 commandHash, uint8, address, address, uint256, bytes32 bindingHash, uint64)
        external
        view
        returns (uint8 outcome, bytes32 commandEcho, bytes32 bindingEcho, bytes32 evidenceHash)
    {
        if (mode == Mode.REVERTING) revert("dependency failure");
        if (mode == Mode.MALFORMED) {
            assembly ("memory-safe") {
                mstore(0, 1)
                return(0, 32)
            }
        }
        if (mode == Mode.WRONG_ECHO) {
            return (0, bytes32(uint256(commandHash) ^ 1), bindingHash, keccak256("wrong"));
        }
        if (mode == Mode.NONCANONICAL || mode == Mode.LONG_RETURN) {
            uint256 length = mode == Mode.NONCANONICAL ? 128 : 160;
            assembly ("memory-safe") {
                mstore(0, 0x100)
                mstore(32, commandHash)
                mstore(64, bindingHash)
                mstore(96, 1)
                mstore(128, 2)
                return(0, length)
            }
        }
        return (uint8(mode), commandHash, bindingHash, keccak256(abi.encode(config, commandHash)));
    }
}
