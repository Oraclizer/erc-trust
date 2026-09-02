// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {ITrustBoundDependency} from "../../src/interfaces/ITrustBoundDependency.sol";

/// @notice Verification-only model for Certora unresolved low-level calls.
/// @dev The first seven slots and the contract name are fixed by Certora.
contract CertoraUnresolvedHarness {
    address public originalCallee;
    address public callersSender;
    address public executingAddr;
    uint256 public inSize;
    uint256 public outSize;
    uint256 public callValue;
    uint256 public callGas;

    uint8 public mode;

    uint8 internal constant MODE_APPLICABLE = 0;
    uint8 internal constant MODE_REJECTED = 1;
    uint8 internal constant MODE_OPERATIONAL = 2;
    uint8 internal constant MODE_ASSESS_REVERT = 3;
    uint8 internal constant MODE_ASSESS_32_BYTES = 4;
    uint8 internal constant MODE_ASSESS_160_BYTES = 5;
    uint8 internal constant MODE_WRONG_COMMAND_ECHO = 6;
    uint8 internal constant MODE_WRONG_BINDING_ECHO = 7;
    uint8 internal constant MODE_NONCANONICAL_OUTCOME = 8;
    uint8 internal constant MODE_CONFIGURATION_REVERT = 9;

    bytes32 internal constant MODELED_CONFIG = keccak256("ERC-TRUST/CERTORA-UNRESOLVED-CONFIG-v1");

    error HarnessModeOutOfRange(uint8 mode);
    error HarnessModeRevert(uint8 mode);
    error HarnessUnknownSelector(bytes4 selector);

    function setMode(uint8 nextMode) external {
        if (nextMode > MODE_CONFIGURATION_REVERT) revert HarnessModeOutOfRange(nextMode);
        mode = nextMode;
    }

    fallback() external payable {
        uint8 selectedMode = mode;
        bytes4 selector = msg.sig;

        if (selector == ITrustBoundDependency.configurationDigest.selector) {
            if (selectedMode == MODE_CONFIGURATION_REVERT) revert HarnessModeRevert(selectedMode);
            bytes memory configuration = abi.encode(MODELED_CONFIG);
            assembly ("memory-safe") {
                return(add(configuration, 0x20), mload(configuration))
            }
        }

        if (selector != ITrustBoundDependency.assess.selector) revert HarnessUnknownSelector(selector);
        if (selectedMode == MODE_ASSESS_REVERT) revert HarnessModeRevert(selectedMode);

        (
            bytes32 commandHash,
            uint8 action,
            address subject,
            address destination,
            uint256 amount,
            bytes32 bindingHash,
            uint64 bindingEpoch
        ) = abi.decode(msg.data[4:], (bytes32, uint8, address, address, uint256, bytes32, uint64));

        if (selectedMode == MODE_ASSESS_32_BYTES) {
            assembly ("memory-safe") {
                mstore(0, 0)
                return(0, 0x20)
            }
        }

        uint256 outcome = selectedMode == MODE_REJECTED
            ? 1
            : selectedMode == MODE_OPERATIONAL ? 2 : selectedMode == MODE_NONCANONICAL_OUTCOME ? 0x100 : 0;
        bytes32 commandEcho = selectedMode == MODE_WRONG_COMMAND_ECHO ? bytes32(uint256(commandHash) ^ 1) : commandHash;
        bytes32 bindingEcho = selectedMode == MODE_WRONG_BINDING_ECHO ? bytes32(uint256(bindingHash) ^ 1) : bindingHash;
        bytes32 evidenceHash =
            keccak256(abi.encode(MODELED_CONFIG, commandHash, action, subject, destination, amount, bindingEpoch));

        bytes memory returndata = selectedMode == MODE_ASSESS_160_BYTES
            ? abi.encode(outcome, commandEcho, bindingEcho, evidenceHash, bytes32(uint256(1)))
            : abi.encode(outcome, commandEcho, bindingEcho, evidenceHash);
        assembly ("memory-safe") {
            return(add(returndata, 0x20), mload(returndata))
        }
    }
}
