// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

// Errors the kernel does not define. The kernel errors (TrustRejected, TrustOperationalFailure,
// TrustUnauthorized, TrustReplay, TrustInvalidCommand, TrustTerminal) and the native route error
// (TrustRouteMismatch) are declared by the generated kernel interfaces and inherited from them.
error TrustReentrancy();
error TrustUnsupported(bytes4 selector);
error TrustZeroAddress();
error TrustInsufficientBalance(address account, uint256 balance, uint256 required);
error TrustInsufficientAllowance(address owner, address spender, uint256 allowance, uint256 required);
