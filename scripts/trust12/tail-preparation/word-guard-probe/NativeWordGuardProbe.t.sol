// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustKernelTypes} from "../../../../implementation/src/generated/IERCTrustKernel.sol";
import {NativeMalformedProbe} from "../foundry/NativeMalformedProbe.t.sol";
import {WordGuardProbeCore} from "./WordGuardProbeCore.sol";

/// @notice Bounded word guard witnesses of the Native profile endpoint on the fixture of the Native malformed probe,
///         on both the regulatory and the ERC-7943 routes.
contract NativeWordGuardProbe is NativeMalformedProbe, WordGuardProbeCore {
    function testWordGuardProbe() external {
        _runWordGuardProbe(true);
    }

    /// @dev A disposition of the probe's own balance to the fixture buyer in a fresh case.
    function _probeKindAction(uint256 nonce) internal view override returns (TrustKernelTypes.ActionRequest memory) {
        return _request(TrustKernelTypes.ActionKind.CONFISCATE, nonce, PROBE_AMOUNT);
    }
}
