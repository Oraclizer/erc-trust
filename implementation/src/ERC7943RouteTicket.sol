// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustKernelTypes} from "./generated/IERCTrustKernel.sol";

/// @notice Key of the same-transaction exact-use ticket that gates the sensitive ERC-7943 selectors.
library ERC7943RouteTicket {
    function key(
        address endpoint,
        bytes4 selector,
        bytes32 calldataHash,
        bytes32 dependencyRoot,
        uint64 dependencyEpoch,
        bytes32 commandId
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                TrustKernelTypes.DOMAIN, endpoint, selector, calldataHash, dependencyRoot, dependencyEpoch, commandId
            )
        );
    }
}
