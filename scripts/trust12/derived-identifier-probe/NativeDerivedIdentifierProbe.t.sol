// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustKernelTypes} from "../../../implementation/src/generated/IERCTrustKernel.sol";
import {TrustTestBase} from "../../../implementation/test/TrustTestBase.t.sol";
import {DerivedIdentifierProbeCore} from "./DerivedIdentifierProbeCore.sol";

/// @notice Derived-identifier probe of the Native profile on the shared Native test fixture: every action
///         kind, every reversal kind, and the exact-use ERC-7943 route.
contract NativeDerivedIdentifierProbe is TrustTestBase, DerivedIdentifierProbeCore {
    function _endpoint() internal view override returns (address) {
        return address(token);
    }

    function testNativeActionsRejectDerivedIdentifiers() external {
        _probeAction(ACTION_SELECTOR, _request(TrustKernelTypes.ActionKind.FREEZE, 701, 1 ether));
        _probeAction(ACTION_SELECTOR, _request(TrustKernelTypes.ActionKind.RESTRICT, 702, 0));
        _probeAction(ACTION_SELECTOR, _request(TrustKernelTypes.ActionKind.SEIZE, 703, 100 ether));
        _probeAction(ACTION_SELECTOR, _request(TrustKernelTypes.ActionKind.CONFISCATE, 704, 50 ether));
        _probeAction(ACTION_SELECTOR, _request(TrustKernelTypes.ActionKind.LIQUIDATE, 705, 40 ether));
        _probeAction(ACTION_SELECTOR, _request(TrustKernelTypes.ActionKind.RECOVER, 706, 30 ether));
        _requireNoViolation();
    }

    function testNativeRouteActionsRejectDerivedIdentifiers() external {
        _probeAction(ROUTE_ACTION_SELECTOR, _request(TrustKernelTypes.ActionKind.FREEZE, 711, 1 ether));
        _probeAction(ROUTE_ACTION_SELECTOR, _request(TrustKernelTypes.ActionKind.SEIZE, 713, 100 ether));
        _probeAction(ROUTE_ACTION_SELECTOR, _request(TrustKernelTypes.ActionKind.CONFISCATE, 714, 50 ether));
        _probeAction(ROUTE_ACTION_SELECTOR, _request(TrustKernelTypes.ActionKind.LIQUIDATE, 715, 40 ether));
        _probeAction(ROUTE_ACTION_SELECTOR, _request(TrustKernelTypes.ActionKind.RECOVER, 716, 30 ether));
        _requireNoViolation();
    }

    function testNativeReversalsRejectDerivedIdentifiers() external {
        TrustKernelTypes.ActionRequest memory freeze = _request(TrustKernelTypes.ActionKind.FREEZE, 721, 1 ether);
        token.executeRegulatoryAction(freeze);
        _probeReversal(REVERSAL_SELECTOR, _reversal(freeze.actionId, TrustKernelTypes.ReversalKind.UNFREEZE, 722));
        _probeReversal(ROUTE_REVERSAL_SELECTOR, _reversal(freeze.actionId, TrustKernelTypes.ReversalKind.UNFREEZE, 723));

        TrustKernelTypes.ActionRequest memory restrict = _request(TrustKernelTypes.ActionKind.RESTRICT, 724, 0);
        token.executeRegulatoryAction(restrict);
        _probeReversal(REVERSAL_SELECTOR, _reversal(restrict.actionId, TrustKernelTypes.ReversalKind.UNRESTRICT, 725));

        TrustKernelTypes.ActionRequest memory seize = _request(TrustKernelTypes.ActionKind.SEIZE, 726, 100 ether);
        token.executeRegulatoryAction(seize);
        _probeReversal(REVERSAL_SELECTOR, _reversal(seize.actionId, TrustKernelTypes.ReversalKind.RELEASE, 727));
        _requireNoViolation();
    }
}
