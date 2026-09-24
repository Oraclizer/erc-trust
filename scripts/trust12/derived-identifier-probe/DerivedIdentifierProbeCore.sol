// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustKernelTypes, IERCTrustKernel} from "../../../implementation/src/generated/IERCTrustKernel.sol";

/// @dev Cheatcodes of the probe. The structure layouts follow the Foundry 1.x cheatcode ABI.
interface DerivedIdentifierProbeVm {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    struct ChainInfo {
        uint256 forkId;
        uint256 chainId;
    }

    struct StorageAccess {
        address account;
        bytes32 slot;
        bool isWrite;
        bytes32 previousValue;
        bytes32 newValue;
        bool reverted;
    }

    struct AccountAccess {
        ChainInfo chainInfo;
        uint8 kind;
        address account;
        address accessor;
        bool initialized;
        uint256 oldBalance;
        uint256 newBalance;
        bytes deployedCode;
        uint256 value;
        bytes data;
        bool reverted;
        StorageAccess[] storageAccesses;
        uint64 depth;
        uint64 oldNonce;
        uint64 newNonce;
    }

    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory);
    function startStateDiffRecording() external;
    function stopAndReturnStateDiff() external returns (AccountAccess[] memory);
    function snapshotState() external returns (uint256);
    function revertToState(uint256 snapshotId) external returns (bool);
}

/// @notice Checks that an identifier returned by deriveActionId or deriveReversalId cannot make a
///         request that is not in canonical form pass a typed command function.
/// @dev For every accepted base request the probe builds three kinds of malformed call:
///      (1) one address, uint64, uint48, or enum word made non-canonical, carrying the identifier the
///          endpoint's own derivation function returns for that same calldata;
///      (2) the canonical request carrying the identifier derived from such a non-canonical calldata;
///      (3) the canonical request followed by extra bytes, carrying the identifier derived from that
///          longer calldata.
///      A call passes the check only when it reverts, touches no account other than the endpoint, emits
///      no log, and leaves no committed storage write. The base request itself must be accepted, so that
///      a rejection of a malformed variant is not explained by the state of the fixture.
abstract contract DerivedIdentifierProbeCore {
    DerivedIdentifierProbeVm internal constant PROBE_VM =
        DerivedIdentifierProbeVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    bytes4 internal constant ACTION_SELECTOR = 0x2f4e0773;
    bytes4 internal constant REVERSAL_SELECTOR = 0x2b892e8f;
    bytes4 internal constant ROUTE_ACTION_SELECTOR = 0x40a9c893;
    bytes4 internal constant ROUTE_REVERSAL_SELECTOR = 0x1c711a94;

    uint8 internal constant CASE_CONTROL = 0;
    uint8 internal constant CASE_DIRTY_DERIVED = 1;
    uint8 internal constant CASE_TRANSPLANT = 2;
    uint8 internal constant CASE_TRAILING_DERIVED = 3;

    uint8 internal constant WORD_ENUM = 1;
    uint8 internal constant WORD_ADDRESS = 2;
    uint8 internal constant WORD_UINT64 = 3;
    uint8 internal constant WORD_UINT48 = 4;

    struct Measurement {
        bool accepted;
        bytes4 revertSelector;
        uint256 returnBytes;
        uint256 externalAccesses;
        uint256 logs;
        uint256 committedWrites;
    }

    event DerivedIdentifierProbeResult(
        bytes4 indexed entrypoint,
        uint8 probeCase,
        uint16 word,
        uint256 value,
        bool derivationReturned,
        bool derivationMatchesRawHash,
        bool accepted,
        bytes4 revertSelector,
        uint256 externalAccesses,
        uint256 logs,
        uint256 committedWrites
    );
    event DerivedIdentifierProbeSummary(
        uint256 controls, uint256 malformedCalls, uint256 derivationsReturned, uint256 violations
    );

    uint256 internal controls;
    uint256 internal malformedCalls;
    uint256 internal derivationsReturned;
    uint256 internal violations;

    function _endpoint() internal view virtual returns (address);

    function _probeAction(bytes4 entrypoint, TrustKernelTypes.ActionRequest memory request) internal {
        uint16[9] memory words = [uint16(2), 3, 4, 5, 6, 10, 16, 18, 19];
        uint8[9] memory types = [
            WORD_ENUM,
            WORD_ADDRESS,
            WORD_ADDRESS,
            WORD_ADDRESS,
            WORD_ADDRESS,
            WORD_UINT64,
            WORD_UINT64,
            WORD_UINT48,
            WORD_UINT48
        ];
        bytes memory canonical = abi.encode(request);
        _probeBase(entrypoint, IERCTrustKernel.deriveActionId.selector, canonical);
        for (uint256 i = 0; i < words.length; ++i) {
            _probeWord(entrypoint, IERCTrustKernel.deriveActionId.selector, canonical, words[i], types[i], 6);
        }
        _probeTrailing(entrypoint, IERCTrustKernel.deriveActionId.selector, canonical);
    }

    function _probeReversal(bytes4 entrypoint, TrustKernelTypes.ReversalRequest memory request) internal {
        uint16[5] memory words = [uint16(3), 5, 8, 10, 11];
        uint8[5] memory types = [WORD_ENUM, WORD_UINT64, WORD_UINT64, WORD_UINT48, WORD_UINT48];
        bytes memory canonical = abi.encode(request);
        _probeBase(entrypoint, IERCTrustKernel.deriveReversalId.selector, canonical);
        for (uint256 i = 0; i < words.length; ++i) {
            _probeWord(entrypoint, IERCTrustKernel.deriveReversalId.selector, canonical, words[i], types[i], 3);
        }
        _probeTrailing(entrypoint, IERCTrustKernel.deriveReversalId.selector, canonical);
    }

    function _requireNoViolation() internal {
        emit DerivedIdentifierProbeSummary(controls, malformedCalls, derivationsReturned, violations);
        require(violations == 0, "a malformed request passed or left a trace");
        require(controls > 0 && malformedCalls > 0, "the probe measured nothing");
    }

    function _probeBase(bytes4 entrypoint, bytes4 deriveSelector, bytes memory canonical) private {
        (bool returned, bytes32 derived) = _derive(deriveSelector, canonical);
        require(returned && derived == bytes32(_word(canonical, 1)), "base identifier is not the derivation");
        Measurement memory m = _measure(bytes.concat(entrypoint, canonical));
        _emit(entrypoint, CASE_CONTROL, 1, uint256(derived), returned, true, m);
        require(m.accepted, "base request is not accepted");
        ++controls;
    }

    function _probeWord(
        bytes4 entrypoint,
        bytes4 deriveSelector,
        bytes memory canonical,
        uint16 word,
        uint8 wordType,
        uint256 enumCount
    ) private {
        uint256 original = _word(canonical, word);
        uint256[] memory values = _dirtyValues(wordType, original, enumCount);
        for (uint256 i = 0; i < values.length; ++i) {
            bytes memory malformed = bytes.concat(canonical);
            _setWord(malformed, word, values[i]);
            (bool returned, bytes32 derived) = _derive(deriveSelector, malformed);
            bytes32 raw = _rawIdentifier(malformed);
            bytes32 identifier = returned ? derived : raw;
            if (returned) ++derivationsReturned;

            _setWord(malformed, 1, uint256(identifier));
            Measurement memory m = _measure(bytes.concat(entrypoint, malformed));
            _emit(entrypoint, CASE_DIRTY_DERIVED, word, values[i], returned, derived == raw, m);
            _judge(m, true);

            bytes memory transplant = bytes.concat(canonical);
            _setWord(transplant, 1, uint256(identifier));
            Measurement memory t = _measure(bytes.concat(entrypoint, transplant));
            _emit(entrypoint, CASE_TRANSPLANT, word, values[i], returned, derived == raw, t);
            // The transplant is the canonical request itself only when the derivation of the malformed
            // calldata equals the canonical identifier; otherwise it must be rejected like any mismatch.
            _judge(t, identifier != bytes32(_word(canonical, 1)));
        }
    }

    function _probeTrailing(bytes4 entrypoint, bytes4 deriveSelector, bytes memory canonical) private {
        uint256[2] memory extras = [uint256(1), 32];
        for (uint256 i = 0; i < extras.length; ++i) {
            bytes memory tail = new bytes(extras[i]);
            (bool returned, bytes32 derived) = _derive(deriveSelector, bytes.concat(canonical, tail));
            if (returned) ++derivationsReturned;
            bytes memory words = bytes.concat(canonical);
            if (returned) _setWord(words, 1, uint256(derived));
            Measurement memory m = _measure(bytes.concat(entrypoint, words, tail));
            _emit(entrypoint, CASE_TRAILING_DERIVED, 0, extras[i], returned, derived == _rawIdentifier(canonical), m);
            _judge(m, true);
        }
    }

    function _judge(Measurement memory m, bool mustReject) private {
        ++malformedCalls;
        bool trace = m.externalAccesses != 0 || m.logs != 0 || m.committedWrites != 0;
        if ((mustReject && m.accepted) || (!m.accepted && trace)) ++violations;
    }

    function _dirtyValues(uint8 wordType, uint256 original, uint256 enumCount)
        private
        pure
        returns (uint256[] memory values)
    {
        if (wordType == WORD_ENUM) {
            values = new uint256[](3);
            values[0] = enumCount;
            values[1] = 255;
            values[2] = original | (uint256(1) << 8);
        } else {
            uint256 width = wordType == WORD_ADDRESS ? 160 : wordType == WORD_UINT64 ? 64 : 48;
            values = new uint256[](2);
            values[0] = original | (uint256(1) << width);
            values[1] = original | (uint256(1) << 255);
        }
    }

    function _measure(bytes memory data) private returns (Measurement memory m) {
        address endpoint = _endpoint();
        uint256 snapshot = PROBE_VM.snapshotState();
        PROBE_VM.recordLogs();
        PROBE_VM.getRecordedLogs();
        PROBE_VM.startStateDiffRecording();
        (bool ok, bytes memory result) = endpoint.call(data);
        DerivedIdentifierProbeVm.AccountAccess[] memory accesses = PROBE_VM.stopAndReturnStateDiff();
        DerivedIdentifierProbeVm.Log[] memory logs = PROBE_VM.getRecordedLogs();
        require(PROBE_VM.revertToState(snapshot), "probe could not restore its snapshot");
        m.accepted = ok;
        m.returnBytes = result.length;
        if (!ok && result.length >= 4) m.revertSelector = bytes4(_leadingWord(result));
        for (uint256 i = 0; i < accesses.length; ++i) {
            if (accesses[i].account != endpoint) ++m.externalAccesses;
            for (uint256 j = 0; j < accesses[i].storageAccesses.length; ++j) {
                if (accesses[i].storageAccesses[j].isWrite && !accesses[i].storageAccesses[j].reverted) {
                    ++m.committedWrites;
                }
            }
        }
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter != address(this)) ++m.logs;
        }
    }

    function _emit(
        bytes4 entrypoint,
        uint8 probeCase,
        uint16 word,
        uint256 value,
        bool returned,
        bool matchesRaw,
        Measurement memory m
    ) private {
        emit DerivedIdentifierProbeResult(
            entrypoint,
            probeCase,
            word,
            value,
            returned,
            matchesRaw,
            m.accepted,
            m.revertSelector,
            m.externalAccesses,
            m.logs,
            m.committedWrites
        );
    }

    function _derive(bytes4 selector, bytes memory tail) private view returns (bool returned, bytes32 identifier) {
        (bool ok, bytes memory output) = _endpoint().staticcall(bytes.concat(selector, tail));
        if (ok && output.length == 32) {
            returned = true;
            identifier = abi.decode(output, (bytes32));
        }
    }

    /// @dev hashes.actionId and hashes.reversalId over the raw request words with the identifier cleared.
    function _rawIdentifier(bytes memory words) private view returns (bytes32) {
        bytes memory cleared = bytes.concat(words);
        _setWord(cleared, 1, 0);
        return keccak256(bytes.concat(abi.encode(TrustKernelTypes.DOMAIN, _endpoint(), block.chainid), cleared));
    }

    function _word(bytes memory words, uint256 index) private pure returns (uint256 value) {
        require(words.length >= 32 * (index + 1), "probe word outside the request");
        assembly ("memory-safe") {
            value := mload(add(add(words, 0x20), mul(index, 0x20)))
        }
    }

    function _setWord(bytes memory words, uint256 index, uint256 value) private pure {
        require(words.length >= 32 * (index + 1), "probe word outside the request");
        assembly ("memory-safe") {
            mstore(add(add(words, 0x20), mul(index, 0x20)), value)
        }
    }

    function _leadingWord(bytes memory data) private pure returns (bytes32 word) {
        assembly ("memory-safe") {
            word := mload(add(data, 0x20))
        }
    }
}
