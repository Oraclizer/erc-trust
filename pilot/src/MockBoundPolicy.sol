// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

/// @notice Immutable policy double used only by the ERC-TRUST FREEZE pilot.
/// @dev Each failure mode is deployed as a distinct runtime-code identity.
contract MockBoundPolicy {
    enum Mode {
        ALLOW,
        REJECT,
        REVERT_CALL,
        MALFORMED,
        WRONG_COMMAND,
        WRONG_BINDING,
        BAD_OUTCOME
    }

    uint16 internal constant REASON_POLICY_DENIED = 6;
    uint16 internal constant REASON_POLICY_FAILURE = 100;

    Mode public immutable mode;
    bytes32 public immutable configurationDigest;

    constructor(Mode mode_) {
        mode = mode_;
        configurationDigest = keccak256(abi.encode("ERC-TRUST/FREEZE-PILOT/POLICY", mode_));
    }

    function runtimeCodeId() external view returns (bytes32) {
        return address(this).codehash;
    }

    function assess(bytes32 commandDigest, address, uint256, bytes32 bindingHash, uint64)
        external
        view
        returns (
            uint8 outcome,
            uint16 reason,
            bytes32 dependencyRef,
            bytes32 echoedCommandDigest,
            bytes32 echoedBindingHash
        )
    {
        if (mode == Mode.REVERT_CALL) {
            revert("MOCK_POLICY_UNAVAILABLE");
        }

        if (mode == Mode.MALFORMED) {
            assembly ("memory-safe") {
                mstore(0x00, 0x01)
                return(0x00, 0x1f)
            }
        }

        if (mode == Mode.REJECT) {
            return (1, REASON_POLICY_DENIED, bytes32(0), commandDigest, bindingHash);
        }

        if (mode == Mode.WRONG_COMMAND) {
            return (0, 0, bytes32(0), bytes32(uint256(commandDigest) ^ 1), bindingHash);
        }

        if (mode == Mode.WRONG_BINDING) {
            return (0, 0, bytes32(0), commandDigest, bytes32(uint256(bindingHash) ^ 1));
        }

        if (mode == Mode.BAD_OUTCOME) {
            return (type(uint8).max, REASON_POLICY_FAILURE, bytes32(0), commandDigest, bindingHash);
        }

        return (0, 0, bytes32(0), commandDigest, bindingHash);
    }
}
