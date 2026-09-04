// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {ERC3643TrustAdapter} from "../src/profiles/ERC3643TrustAdapter.sol";

/// @notice Verification-only seam over the production ERC-3643 Partial adapter.
/// @dev The inherited descriptor is the production implementation. The exposed pure helpers are the
///      same consumers used by the production forced-transfer and receipt-observation paths.
contract ERC3643PartialHarness is ERC3643TrustAdapter {
    constructor(address profileGovernor_, address authority_, bytes32 authorityRef_)
        ERC3643TrustAdapter(profileGovernor_, authority_, authorityRef_)
    {}

    function restrictionMatchesExternal(bool actual, bool owned) external pure returns (bool) {
        return _restrictionMatches(actual, owned);
    }

    function subjectObservationHashExternal(
        uint256 balance,
        uint256 frozenTarget,
        uint256 actualFrozen,
        bool ownedRestricted,
        bool actualRestricted
    ) external pure returns (bytes32) {
        return _subjectObservationHash(balance, frozenTarget, actualFrozen, ownedRestricted, actualRestricted);
    }

    function roleObservationHashExternal(uint256 balance, bool actualRestricted, uint256 custodyBacking)
        external
        pure
        returns (bytes32)
    {
        return _roleObservationHash(balance, actualRestricted, custodyBacking);
    }
}
