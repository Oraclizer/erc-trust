// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {IERCTrustKernel, TrustKernelTypes} from "../../../../implementation/src/generated/IERCTrustKernel.sol";

/// @dev Cheatcodes of the typed failure probe. The names follow the Foundry 1.x cheatcode ABI.
interface TypedFailureProbeVm {
    function snapshotState() external returns (uint256);
    function revertToState(uint256 snapshotId) external returns (bool);
    function prank(address sender) external;
    function mockCall(address callee, bytes calldata data, bytes calldata returnData) external;
    function mockCallRevert(address callee, bytes calldata data, bytes calldata revertData) external;
    function clearMockedCalls() external;
}

/// @notice Drives every typed failure of one profile endpoint through its typed entrypoints and records
///         the complete revert data of each case.
/// @dev The probe measures and records; it does not judge. For every case it records the entrypoint,
///      the sender, the identifier, authority reference and case of the request it sent, whether the
///      call succeeded and the complete return or revert data. The recorder reads each payload with
///      the fixed ABI reading of a typed failure report and checks the binding to the request and to
///      the sender. The probe itself fails only when a set-up command is not accepted, because the
///      measurement of that case would then be void. Every case runs from a fresh snapshot of the
///      deployed fixture and the snapshot is restored afterwards.
abstract contract TypedFailureProbeCore {
    TypedFailureProbeVm internal constant PROBE_VM =
        TypedFailureProbeVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    bytes4 internal constant ACTION_SELECTOR = 0x2f4e0773;
    bytes4 internal constant REVERSAL_SELECTOR = 0x2b892e8f;
    bytes4 internal constant ROUTE_ACTION_SELECTOR = 0x40a9c893;
    bytes4 internal constant ROUTE_REVERSAL_SELECTOR = 0x1c711a94;

    uint8 internal constant EXPECT_ACCEPTED = 0;
    uint8 internal constant EXPECT_INVALID_COMMAND = 1;
    uint8 internal constant EXPECT_REJECTED = 2;
    uint8 internal constant EXPECT_OPERATIONAL_FAILURE = 3;
    uint8 internal constant EXPECT_UNAUTHORIZED = 4;
    uint8 internal constant EXPECT_REPLAY = 5;
    uint8 internal constant EXPECT_TERMINAL = 6;

    uint8 internal constant CASES = 15;
    address internal constant STRANGER = address(0x5157);
    uint256 internal constant PROBE_AMOUNT = 1 ether;

    event TypedFailureProbeCode(uint8 indexed profile, address endpoint, bytes code);
    event TypedFailureProbeCase(
        uint16 indexed index,
        uint8 profile,
        uint8 entrypoint,
        uint8 expected,
        address sender,
        bytes32 commandId,
        bytes32 authorityRef,
        bytes32 caseId,
        bool ok,
        bytes returnData
    );

    /// @dev One pair of typed entrypoints. The codes follow the malformed catalog: 1 action,
    ///      2 reversal, 3 route action, 4 route reversal.
    struct Entrypoints {
        bytes4 action;
        bytes4 reversal;
        uint8 actionCode;
        uint8 reversalCode;
    }

    // ---------------------------------------------------------------------
    // Profile hooks
    // ---------------------------------------------------------------------

    /// @dev 1 Native, 2 Partial, 3 Hook.
    function _probeProfile() internal pure virtual returns (uint8);

    function _probeEndpoint() internal view virtual returns (address);

    function _probeAuthorityRef() internal pure virtual returns (bytes32);

    /// @dev A destination that the identity dependency of the profile admits.
    function _probeDestination() internal view virtual returns (address);

    /// @dev True when only transfer commands consult a dependency (the ERC-3643 profiles); false when
    ///      every command consults the policy binding (Native).
    function _probeConsultsOnTransferOnly() internal pure virtual returns (bool);

    /// @dev Make the next consulted dependency deny `account` (rejected) or fail operationally.
    function _breakAssessment(bool rejected, address account) internal virtual;

    /// @dev The typed entrypoint pairs of the endpoint; the Native endpoint also has the exact-use route.
    function _probeEntrypoints() internal pure virtual returns (Entrypoints[] memory);

    // ---------------------------------------------------------------------
    // Request builders
    // ---------------------------------------------------------------------

    function _tfAction(
        TrustKernelTypes.ActionKind kind,
        uint256 nonce,
        bytes32 caseId,
        address destination,
        address custodian
    ) internal view returns (TrustKernelTypes.ActionRequest memory request) {
        IERCTrustKernel endpoint = IERCTrustKernel(_probeEndpoint());
        (bytes32 root, uint64 epoch) = endpoint.dependencyState();
        request = TrustKernelTypes.ActionRequest({
            domain: TrustKernelTypes.DOMAIN,
            actionId: bytes32(0),
            action: kind,
            subject: address(this),
            source: address(this),
            destination: destination,
            custodian: custodian,
            amount: PROBE_AMOUNT,
            caseId: caseId,
            dependencyRoot: root,
            dependencyEpoch: epoch,
            provenanceCommitment: keccak256(abi.encode("TYPED-FAILURE-PROBE", nonce)),
            settlementCommitment: bytes32(0),
            proceedsCommitment: bytes32(0),
            entitlementCommitment: bytes32(0),
            authorityRef: _probeAuthorityRef(),
            authorityEpoch: 1,
            nonce: nonce,
            validAfter: 0,
            validBefore: type(uint48).max
        });
        request.actionId = endpoint.deriveActionId(request);
    }

    function _tfFreeze(uint256 nonce, bytes32 caseId) internal view returns (TrustKernelTypes.ActionRequest memory) {
        return _tfAction(TrustKernelTypes.ActionKind.FREEZE, nonce, caseId, address(0), address(0));
    }

    /// @dev The action whose assessment consults the dependency that `_breakAssessment` affects.
    function _tfConsultingAction(uint256 nonce) internal view returns (TrustKernelTypes.ActionRequest memory) {
        if (!_probeConsultsOnTransferOnly()) return _tfFreeze(nonce, _case(nonce));
        return _tfAction(TrustKernelTypes.ActionKind.CONFISCATE, nonce, _case(nonce), _probeDestination(), address(0));
    }

    /// @dev The action that the reversal-side dependency cases reverse, and its reversal kind.
    function _tfConsultingBase(uint256 nonce)
        internal
        view
        returns (TrustKernelTypes.ActionRequest memory request, TrustKernelTypes.ReversalKind reversal)
    {
        if (!_probeConsultsOnTransferOnly()) {
            return (_tfFreeze(nonce, _case(nonce)), TrustKernelTypes.ReversalKind.UNFREEZE);
        }
        address endpoint = _probeEndpoint();
        request = _tfAction(TrustKernelTypes.ActionKind.SEIZE, nonce, _case(nonce), endpoint, endpoint);
        reversal = TrustKernelTypes.ReversalKind.RELEASE;
    }

    function _tfReversal(bytes32 actionId, TrustKernelTypes.ReversalKind kind, uint256 nonce)
        internal
        view
        returns (TrustKernelTypes.ReversalRequest memory request)
    {
        IERCTrustKernel endpoint = IERCTrustKernel(_probeEndpoint());
        (bytes32 root, uint64 epoch) = endpoint.dependencyState();
        request = TrustKernelTypes.ReversalRequest({
            domain: TrustKernelTypes.DOMAIN,
            reversalId: bytes32(0),
            actionId: actionId,
            reversal: kind,
            dependencyRoot: root,
            dependencyEpoch: epoch,
            provenanceCommitment: keccak256(abi.encode("TYPED-FAILURE-PROBE-REVERSAL", nonce)),
            authorityRef: _probeAuthorityRef(),
            authorityEpoch: 1,
            nonce: nonce,
            validAfter: 0,
            validBefore: type(uint48).max
        });
        request.reversalId = endpoint.deriveReversalId(request);
    }

    function _case(uint256 nonce) internal pure returns (bytes32) {
        return keccak256(abi.encode("TYPED-FAILURE-PROBE-CASE", nonce));
    }

    // ---------------------------------------------------------------------
    // Calls
    // ---------------------------------------------------------------------

    function _applyAction(TrustKernelTypes.ActionRequest memory request) internal {
        (bool ok,) = _probeEndpoint().call(abi.encodeWithSelector(ACTION_SELECTOR, request));
        require(ok, "probe set-up action is not accepted");
    }

    function _applyReversal(TrustKernelTypes.ReversalRequest memory request) internal {
        (bool ok,) = _probeEndpoint().call(abi.encodeWithSelector(REVERSAL_SELECTOR, request));
        require(ok, "probe set-up reversal is not accepted");
    }

    function _sendAction(
        uint16 index,
        Entrypoints memory entry,
        uint8 expected,
        address sender,
        TrustKernelTypes.ActionRequest memory request
    ) internal {
        bytes memory data = abi.encodeWithSelector(entry.action, request);
        address endpoint = _probeEndpoint();
        if (sender != address(this)) PROBE_VM.prank(sender);
        (bool ok, bytes memory result) = endpoint.call(data);
        emit TypedFailureProbeCase(
            index,
            _probeProfile(),
            entry.actionCode,
            expected,
            sender,
            request.actionId,
            request.authorityRef,
            request.caseId,
            ok,
            result
        );
    }

    function _sendReversal(
        uint16 index,
        Entrypoints memory entry,
        uint8 expected,
        address sender,
        TrustKernelTypes.ReversalRequest memory request
    ) internal {
        bytes memory data = abi.encodeWithSelector(entry.reversal, request);
        address endpoint = _probeEndpoint();
        if (sender != address(this)) PROBE_VM.prank(sender);
        (bool ok, bytes memory result) = endpoint.call(data);
        emit TypedFailureProbeCase(
            index,
            _probeProfile(),
            entry.reversalCode,
            expected,
            sender,
            request.reversalId,
            request.authorityRef,
            bytes32(0),
            ok,
            result
        );
    }

    // ---------------------------------------------------------------------
    // Cases
    // ---------------------------------------------------------------------

    function _runProbe() internal {
        address endpoint = _probeEndpoint();
        emit TypedFailureProbeCode(_probeProfile(), endpoint, endpoint.code);
        Entrypoints[] memory pairs = _probeEntrypoints();
        for (uint256 p = 0; p < pairs.length; ++p) {
            for (uint8 n = 1; n <= CASES; ++n) {
                uint256 snapshot = PROBE_VM.snapshotState();
                _runCase(uint16(100 * (p + 1) + n), n, pairs[p]);
                PROBE_VM.clearMockedCalls();
                require(PROBE_VM.revertToState(snapshot), "probe could not restore its snapshot");
            }
        }
    }

    function _runCase(uint16 index, uint8 n, Entrypoints memory entry) internal {
        if (n == 1) {
            // TrustInvalidCommand on the action entrypoint: a validity window that has not started.
            TrustKernelTypes.ActionRequest memory request = _tfFreeze(1_001, _case(1_001));
            request.validAfter = uint48(block.timestamp + 1);
            request.actionId = IERCTrustKernel(_probeEndpoint()).deriveActionId(request);
            _sendAction(index, entry, EXPECT_INVALID_COMMAND, address(this), request);
        } else if (n == 2) {
            // TrustInvalidCommand on the reversal entrypoint: the referenced action was never applied.
            _sendReversal(
                index,
                entry,
                EXPECT_INVALID_COMMAND,
                address(this),
                _tfReversal(keccak256("TYPED-FAILURE-PROBE-UNKNOWN"), TrustKernelTypes.ReversalKind.UNFREEZE, 1_002)
            );
        } else if (n == 3) {
            // Control: the consulting action is accepted while its dependency answers normally.
            _sendAction(index, entry, EXPECT_ACCEPTED, address(this), _tfConsultingAction(1_003));
        } else if (n == 4) {
            _breakAssessment(true, _probeDestination());
            _sendAction(index, entry, EXPECT_REJECTED, address(this), _tfConsultingAction(1_004));
        } else if (n == 5) {
            _breakAssessment(false, _probeDestination());
            _sendAction(index, entry, EXPECT_OPERATIONAL_FAILURE, address(this), _tfConsultingAction(1_005));
        } else if (n <= 8) {
            // Control, TrustRejected and TrustOperationalFailure on the reversal entrypoint.
            (TrustKernelTypes.ActionRequest memory applied, TrustKernelTypes.ReversalKind kind) = _tfConsultingBase(1_006);
            _applyAction(applied);
            uint8 expected = EXPECT_ACCEPTED;
            if (n == 7) {
                _breakAssessment(true, address(this));
                expected = EXPECT_REJECTED;
            } else if (n == 8) {
                _breakAssessment(false, address(this));
                expected = EXPECT_OPERATIONAL_FAILURE;
            }
            // Reversal nonces stay apart from action nonces: the Native endpoint keeps one nonce space.
            _sendReversal(
                index, entry, expected, address(this), _tfReversal(applied.actionId, kind, 1_100 + uint256(n))
            );
        } else if (n == 9) {
            // TrustUnauthorized on the action entrypoint: a well-formed request from another account.
            _sendAction(index, entry, EXPECT_UNAUTHORIZED, STRANGER, _tfFreeze(1_009, _case(1_009)));
        } else if (n == 10) {
            TrustKernelTypes.ActionRequest memory applied = _tfFreeze(1_010, _case(1_010));
            _applyAction(applied);
            _sendReversal(
                index,
                entry,
                EXPECT_UNAUTHORIZED,
                STRANGER,
                _tfReversal(applied.actionId, TrustKernelTypes.ReversalKind.UNFREEZE, 1_011)
            );
        } else if (n == 11 || n == 12) {
            // TrustReplay: the same action again, and a new action that reuses the nonce.
            TrustKernelTypes.ActionRequest memory applied = _tfFreeze(1_012, _case(1_012));
            _applyAction(applied);
            _sendAction(
                index, entry, EXPECT_REPLAY, address(this), n == 11 ? applied : _tfFreeze(1_012, _case(1_013))
            );
        } else if (n == 13) {
            // TrustReplay: the same reversal again.
            TrustKernelTypes.ActionRequest memory applied = _tfFreeze(1_014, _case(1_014));
            _applyAction(applied);
            TrustKernelTypes.ReversalRequest memory reversal =
                _tfReversal(applied.actionId, TrustKernelTypes.ReversalKind.UNFREEZE, 1_015);
            _applyReversal(reversal);
            _sendReversal(index, entry, EXPECT_REPLAY, address(this), reversal);
        } else {
            // TrustTerminal: a new action in a closed case, and a second reversal in a closed case.
            bytes32 caseId = _case(1_016);
            TrustKernelTypes.ActionRequest memory applied = _tfFreeze(1_016, caseId);
            _applyAction(applied);
            _applyReversal(_tfReversal(applied.actionId, TrustKernelTypes.ReversalKind.UNFREEZE, 1_017));
            if (n == 14) {
                _sendAction(index, entry, EXPECT_TERMINAL, address(this), _tfFreeze(1_018, caseId));
            } else {
                _sendReversal(
                    index,
                    entry,
                    EXPECT_TERMINAL,
                    address(this),
                    _tfReversal(applied.actionId, TrustKernelTypes.ReversalKind.UNFREEZE, 1_019)
                );
            }
        }
    }
}
