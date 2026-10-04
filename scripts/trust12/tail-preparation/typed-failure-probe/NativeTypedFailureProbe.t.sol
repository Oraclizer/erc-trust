// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustKernelTypes} from "../../../../implementation/src/generated/IERCTrustKernel.sol";
import {TrustTestBase} from "../../../../implementation/test/TrustTestBase.t.sol";
import {MockBoundDependency} from "../../../../implementation/test/mocks/MockBoundDependency.sol";
import {TypedFailureProbeCore} from "./TypedFailureProbeCore.sol";

/// @notice Typed failure probe of the Native endpoint on the shared Native test fixture. Every command
///         consults the policy binding, so a denying policy binding produces TrustRejected and a
///         configuration drift of the bound policy produces TrustOperationalFailure. The probe runs the
///         kernel entrypoints and the exact-use route entrypoints.
contract NativeTypedFailureProbe is TrustTestBase, TypedFailureProbeCore {
    function testNativeTypedFailureProbe() external {
        _runProbe();
    }

    function _probeProfile() internal pure override returns (uint8) {
        return 1;
    }

    function _probeEndpoint() internal view override returns (address) {
        return address(token);
    }

    function _probeAuthorityRef() internal pure override returns (bytes32) {
        return AUTHORITY_REF;
    }

    function _probeDestination() internal view override returns (address) {
        return address(buyer);
    }

    function _probeConsultsOnTransferOnly() internal pure override returns (bool) {
        return false;
    }

    /// @dev The fixture contract is the governor of the token, so it may rebind the policy binding.
    function _breakAssessment(bool rejected, address) internal override {
        if (rejected) {
            MockBoundDependency denying =
                new MockBoundDependency(MockBoundDependency.Mode.REJECTED, keccak256("TYPED-FAILURE-PROBE-DENY"));
            token.rebindDependency(
                TrustKernelTypes.BindingKind.POLICY,
                address(denying),
                SCHEMA,
                keccak256("TYPED-FAILURE-PROBE-REBIND"),
                900_101
            );
        } else {
            dependency.setConfig(keccak256("TYPED-FAILURE-PROBE-DRIFT"));
        }
    }

    function _probeEntrypoints() internal pure override returns (Entrypoints[] memory pairs) {
        pairs = new Entrypoints[](2);
        pairs[0] = Entrypoints(ACTION_SELECTOR, REVERSAL_SELECTOR, 1, 2);
        pairs[1] = Entrypoints(ROUTE_ACTION_SELECTOR, ROUTE_REVERSAL_SELECTOR, 3, 4);
    }
}
