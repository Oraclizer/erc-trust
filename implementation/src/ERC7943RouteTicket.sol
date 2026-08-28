// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustTypes} from "./TrustTypes.sol";

library ERC7943RouteTicket {
    function key(
        address endpoint,
        bytes4 selector,
        bytes32 calldataHash,
        bytes32 bindingHash,
        uint64 authorityEpoch,
        uint64 policyEpoch,
        bytes32 commandId
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                TrustTypes.DOMAIN, endpoint, selector, calldataHash, bindingHash, authorityEpoch, policyEpoch, commandId
            )
        );
    }
}
