// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustToken} from "../src/TrustToken.sol";
import {TrustTypes} from "../src/TrustTypes.sol";

/// @notice Verification-only seam over the production FREEZE shape guard.
/// @dev Seed writes are part of the same transaction and therefore roll back
///      when the production validator rejects a nonincreasing target.
contract TrustFreezeDirectionHarness is TrustToken {
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address governor_,
        address initialHolder,
        uint256 initialSupply,
        bytes32 authorityRef,
        address initialAuthority,
        address policy,
        address identity,
        address settlement,
        address entitlement,
        bytes32 schema
    )
        TrustToken(
            name_,
            symbol_,
            decimals_,
            governor_,
            initialHolder,
            initialSupply,
            authorityRef,
            initialAuthority,
            policy,
            identity,
            settlement,
            entitlement,
            schema
        )
    {}

    function validateFreezeShapeWithSeed(TrustTypes.ActionRequest calldata request, uint256 currentTarget)
        external
        returns (uint256 observedTarget)
    {
        _frozen[request.subject] = currentTarget;
        _terminalCases[request.caseId] = false;
        _validateActionShape(request);
        observedTarget = _frozen[request.subject];
    }
}
