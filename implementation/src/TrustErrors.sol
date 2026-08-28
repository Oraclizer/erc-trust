// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

error TrustRejected(bytes32 commandId, uint16 reason);
error TrustOperationalFailure(bytes32 commandId, uint16 reason, bytes32 dependencyRef);
error TrustUnauthorized(address caller, bytes32 authorityRef);
error TrustReplay(bytes32 key);
error TrustInvalidCommand(bytes32 commandId, uint16 reason);
error TrustRouteMismatch(bytes32 routeKey);
error TrustTerminal(bytes32 actionId);
error TrustReentrancy();
error TrustUnsupported(bytes4 selector);
error TrustZeroAddress();
error TrustInsufficientBalance(address account, uint256 balance, uint256 required);
error TrustInsufficientAllowance(address owner, address spender, uint256 allowance, uint256 required);
