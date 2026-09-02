// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustKernelTypes} from "./generated/IERCTrustKernel.sol";

/// @notice Identifier of a sensitive ERC-7943 call, carried by TrustRouteMismatch when the exact-use
///         ticket does not admit the call. The ticket itself is enforced field by field, not by this key.
library ERC7943RouteTicket {
    function key(address endpoint, bytes4 selector, bytes32 calldataHash) internal pure returns (bytes32) {
        return keccak256(abi.encode(TrustKernelTypes.DOMAIN, endpoint, selector, calldataHash));
    }
}
