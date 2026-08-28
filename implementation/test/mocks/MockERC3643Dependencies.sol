// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

contract MockERC3643IdentityRegistry {
    enum Mode {
        ALLOW,
        REJECT,
        REVERT_CALL,
        MALFORMED,
        NONCANONICAL,
        LONG_RETURN
    }

    Mode public mode;
    mapping(address => bool) public verified;

    function setMode(Mode mode_) external {
        mode = mode_;
    }

    function setVerified(address account, bool value) external {
        verified[account] = value;
    }

    function isVerified(address account) external view returns (bool) {
        if (mode == Mode.REVERT_CALL) revert("identity unavailable");
        if (mode == Mode.MALFORMED) {
            assembly ("memory-safe") {
                return(0, 0)
            }
        }
        if (mode == Mode.NONCANONICAL || mode == Mode.LONG_RETURN) {
            uint256 length = mode == Mode.NONCANONICAL ? 32 : 64;
            assembly ("memory-safe") {
                mstore(0, 2)
                mstore(32, 1)
                return(0, length)
            }
        }
        return mode == Mode.ALLOW && verified[account];
    }
}

contract MockERC3643Compliance {
    enum Mode {
        ALLOW,
        REJECT,
        REVERT_CALL,
        MALFORMED,
        NONCANONICAL,
        LONG_RETURN
    }

    Mode public mode;

    function setMode(Mode mode_) external {
        mode = mode_;
    }

    function canTransfer(address, address, uint256) external view returns (bool) {
        if (mode == Mode.REVERT_CALL) revert("compliance unavailable");
        if (mode == Mode.MALFORMED) {
            assembly ("memory-safe") {
                return(0, 0)
            }
        }
        if (mode == Mode.NONCANONICAL || mode == Mode.LONG_RETURN) {
            uint256 length = mode == Mode.NONCANONICAL ? 32 : 64;
            assembly ("memory-safe") {
                mstore(0, 2)
                mstore(32, 1)
                return(0, length)
            }
        }
        return mode == Mode.ALLOW;
    }
}
