// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustKernelTypes} from "../../../../implementation/src/generated/IERCTrustKernel.sol";
import {TrustTestBase} from "../../../../implementation/test/TrustTestBase.t.sol";
import {MalformedProbeCore} from "./MalformedProbeCore.sol";
import {MalformedProbeRecipes} from "./MalformedProbeRecipes.sol";

/// @notice Malformed probe of the Native profile endpoint on the shared Native test fixture.
contract NativeMalformedProbe is TrustTestBase, MalformedProbeCore {
    function testNativeMalformedProbe() external {
        _runProbe(MalformedProbeRecipes.nativeRecipes());
    }

    function _probeEndpoint() internal view override returns (address) {
        return address(token);
    }

    function _probeAction(uint256 nonce) internal view override returns (TrustKernelTypes.ActionRequest memory) {
        return _request(TrustKernelTypes.ActionKind.FREEZE, nonce, PROBE_AMOUNT);
    }

    function _probeReversal(bytes32 actionId, uint256 nonce)
        internal
        view
        override
        returns (TrustKernelTypes.ReversalRequest memory)
    {
        return _reversal(actionId, TrustKernelTypes.ReversalKind.UNFREEZE, nonce);
    }
}
