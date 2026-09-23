// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustKernelTypes} from "../../../../implementation/src/generated/IERCTrustKernel.sol";
import {MalformedProbeRecipes} from "./MalformedProbeRecipes.sol";

/// @dev Cheatcodes of the probe. The structure layouts follow the Foundry 1.x cheatcode ABI.
interface MalformedProbeVm {
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
    function deal(address account, uint256 balance) external;
}

/// @notice Runs the malformed probe recipes of one profile against its deployed endpoint.
/// @dev The probe measures and records; it does not judge. For every recipe it records how the call
///      ended, which typed failure selector it returned, how many accounts other than the endpoint the
///      call touched, how many logs it emitted and how many storage writes survived. The recorder
///      script compares these observations with the expected malformed behavior. The probe fails only
///      when its own base requests are not accepted, because the measurement would then be void.
abstract contract MalformedProbeCore {
    MalformedProbeVm internal constant PROBE_VM =
        MalformedProbeVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint8 internal constant OUTCOME_UNTYPED_EMPTY_REVERT = 1;
    uint8 internal constant OUTCOME_TYPED_FAILURE = 2;
    uint8 internal constant OUTCOME_OTHER_REVERT = 3;
    uint8 internal constant OUTCOME_SUCCESS = 4;

    uint8 internal constant KIND_LENGTH = 1;
    uint8 internal constant KIND_WORD = 2;
    uint8 internal constant KIND_SELECTOR = 3;
    uint8 internal constant KIND_VALUE = 4;
    uint8 internal constant KIND_CONTROL = 5;
    uint8 internal constant POLICY_RECOMPUTE = 1;
    uint8 internal constant POLICY_STALE = 2;
    uint8 internal constant POLICY_FOREIGN_DOMAIN = 3;

    uint256 internal constant ACTION_NONCE = 900_001;
    uint256 internal constant REVERSED_ACTION_NONCE = 900_002;
    uint256 internal constant REVERSAL_NONCE = 900_003;
    uint256 internal constant PROBE_AMOUNT = 1 ether;

    event MalformedProbeBase(uint8 entrypoint, bool accepted, uint256 returnBytes);
    event MalformedProbeResult(
        uint16 indexed index,
        uint8 outcome,
        bytes4 selector,
        uint256 secondWord,
        uint256 returnBytes,
        uint256 externalAccesses,
        uint256 logs,
        uint256 committedWrites
    );

    function _probeEndpoint() internal view virtual returns (address);

    function _probeAction(uint256 nonce) internal view virtual returns (TrustKernelTypes.ActionRequest memory);

    function _probeReversal(bytes32 actionId, uint256 nonce)
        internal
        view
        virtual
        returns (TrustKernelTypes.ReversalRequest memory);

    function _runProbe(MalformedProbeRecipes.Recipe[] memory recipes) internal {
        address endpoint = _probeEndpoint();
        PROBE_VM.deal(address(this), 1 ether);
        bytes memory actionWords = abi.encode(_probeAction(ACTION_NONCE));
        _requireBase(endpoint, MalformedProbeRecipes.ACTION_SELECTOR, actionWords, 1);
        if (_hasEntrypoint(recipes, 3)) {
            _requireBase(endpoint, MalformedProbeRecipes.ROUTE_ACTION_SELECTOR, actionWords, 3);
        }
        for (uint256 i = 0; i < recipes.length; ++i) {
            uint8 entrypoint = recipes[i].entrypoint;
            if (entrypoint == 0 || entrypoint == 1 || entrypoint == 3) {
                _runOne(recipes[i], endpoint, actionWords, _selectorOf(entrypoint));
            }
        }

        TrustKernelTypes.ActionRequest memory reversed = _probeAction(REVERSED_ACTION_NONCE);
        (bool applied,) = endpoint.call(abi.encodeWithSelector(MalformedProbeRecipes.ACTION_SELECTOR, reversed));
        require(applied, "probe could not apply the action to reverse");
        bytes memory reversalWords = abi.encode(_probeReversal(reversed.actionId, REVERSAL_NONCE));
        _requireBase(endpoint, MalformedProbeRecipes.REVERSAL_SELECTOR, reversalWords, 2);
        if (_hasEntrypoint(recipes, 4)) {
            _requireBase(endpoint, MalformedProbeRecipes.ROUTE_REVERSAL_SELECTOR, reversalWords, 4);
        }
        for (uint256 i = 0; i < recipes.length; ++i) {
            uint8 entrypoint = recipes[i].entrypoint;
            if (entrypoint == 2 || entrypoint == 4) {
                _runOne(recipes[i], endpoint, reversalWords, _selectorOf(entrypoint));
            }
        }
    }

    function _runOne(
        MalformedProbeRecipes.Recipe memory recipe,
        address endpoint,
        bytes memory baseWords,
        bytes4 selector
    ) internal {
        bytes memory data = _probeCalldata(recipe, endpoint, baseWords, selector);
        uint256 value = recipe.kind == KIND_VALUE ? recipe.value : 0;
        uint256 snapshot = PROBE_VM.snapshotState();
        PROBE_VM.recordLogs();
        PROBE_VM.getRecordedLogs();
        PROBE_VM.startStateDiffRecording();
        (bool ok, bytes memory result) = endpoint.call{value: value}(data);
        MalformedProbeVm.AccountAccess[] memory accesses = PROBE_VM.stopAndReturnStateDiff();
        MalformedProbeVm.Log[] memory logs = PROBE_VM.getRecordedLogs();
        require(PROBE_VM.revertToState(snapshot), "probe could not restore its snapshot");
        _record(recipe.index, ok, result, endpoint, accesses, logs);
    }

    function _record(
        uint16 index,
        bool ok,
        bytes memory result,
        address endpoint,
        MalformedProbeVm.AccountAccess[] memory accesses,
        MalformedProbeVm.Log[] memory logs
    ) internal {
        uint256 external_;
        uint256 writes;
        for (uint256 i = 0; i < accesses.length; ++i) {
            if (accesses[i].account != endpoint) ++external_;
            for (uint256 j = 0; j < accesses[i].storageAccesses.length; ++j) {
                MalformedProbeVm.StorageAccess memory access = accesses[i].storageAccesses[j];
                if (access.isWrite && !access.reverted) ++writes;
            }
        }
        uint256 emitted;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter != address(this)) ++emitted;
        }
        bytes4 selector = _leadingSelector(result);
        uint8 outcome = ok
            ? OUTCOME_SUCCESS
            : result.length == 0
                ? OUTCOME_UNTYPED_EMPTY_REVERT
                : _isTypedFailure(selector) ? OUTCOME_TYPED_FAILURE : OUTCOME_OTHER_REVERT;
        emit MalformedProbeResult(
            index, outcome, selector, _wordAt(result, 1), result.length, external_, emitted, writes
        );
    }

    function _probeCalldata(
        MalformedProbeRecipes.Recipe memory recipe,
        address endpoint,
        bytes memory baseWords,
        bytes4 selector
    ) internal view returns (bytes memory data) {
        if (recipe.kind == KIND_SELECTOR) {
            return bytes.concat(bytes4(uint32(recipe.value)), baseWords);
        }
        if (recipe.kind == KIND_VALUE || recipe.kind == KIND_CONTROL) return bytes.concat(selector, baseWords);
        if (recipe.kind == KIND_LENGTH) {
            bytes memory full =
                bytes.concat(selector == bytes4(0) ? MalformedProbeRecipes.ACTION_SELECTOR : selector, baseWords);
            data = new bytes(recipe.calldataBytes);
            for (uint256 i = 0; i < data.length && i < full.length; ++i) {
                data[i] = full[i];
            }
            return data;
        }
        require(recipe.kind == KIND_WORD, "unknown probe kind");
        bytes memory words = bytes.concat(baseWords);
        _setWord(words, recipe.word, recipe.value);
        if (recipe.policy == POLICY_FOREIGN_DOMAIN) {
            _setWord(words, 0, uint256(TrustKernelTypes.DOMAIN) ^ 0xff);
        }
        if (recipe.policy != POLICY_STALE) {
            _setWord(words, 1, uint256(_identifier(endpoint, words)));
        }
        return bytes.concat(selector, words);
    }

    /// @dev hashes.actionId and hashes.reversalId: keccak256 over the domain, the endpoint, the chain and
    ///      the raw request words with the identifier word cleared.
    function _identifier(address endpoint, bytes memory words) internal view returns (bytes32) {
        bytes memory cleared = bytes.concat(words);
        _setWord(cleared, 1, 0);
        return keccak256(bytes.concat(abi.encode(TrustKernelTypes.DOMAIN, endpoint, block.chainid), cleared));
    }

    function _requireBase(address endpoint, bytes4 selector, bytes memory words, uint8 entrypoint) internal {
        uint256 snapshot = PROBE_VM.snapshotState();
        (bool ok, bytes memory result) = endpoint.call(bytes.concat(selector, words));
        require(PROBE_VM.revertToState(snapshot), "probe could not restore its snapshot");
        emit MalformedProbeBase(entrypoint, ok, result.length);
        require(ok, "probe base request is not accepted");
    }

    function _selectorOf(uint8 entrypoint) internal pure returns (bytes4) {
        if (entrypoint == 1) return MalformedProbeRecipes.ACTION_SELECTOR;
        if (entrypoint == 2) return MalformedProbeRecipes.REVERSAL_SELECTOR;
        if (entrypoint == 3) return MalformedProbeRecipes.ROUTE_ACTION_SELECTOR;
        if (entrypoint == 4) return MalformedProbeRecipes.ROUTE_REVERSAL_SELECTOR;
        return bytes4(0);
    }

    function _hasEntrypoint(MalformedProbeRecipes.Recipe[] memory recipes, uint8 entrypoint)
        internal
        pure
        returns (bool)
    {
        for (uint256 i = 0; i < recipes.length; ++i) {
            if (recipes[i].entrypoint == entrypoint) return true;
        }
        return false;
    }

    function _isTypedFailure(bytes4 selector) internal pure returns (bool) {
        return selector == 0x386ecc58 || selector == 0x72841b29 || selector == 0x8cf60b6f || selector == 0x996b6134
            || selector == 0xa6e257c3 || selector == 0xed623c13;
    }

    function _leadingSelector(bytes memory data) internal pure returns (bytes4 result) {
        if (data.length < 4) return bytes4(0);
        assembly ("memory-safe") {
            result := mload(add(data, 0x20))
        }
    }

    function _wordAt(bytes memory data, uint256 index) internal pure returns (uint256 word) {
        if (data.length < 4 + 32 * (index + 1)) return 0;
        assembly ("memory-safe") {
            word := mload(add(add(data, 0x24), mul(index, 0x20)))
        }
    }

    function _setWord(bytes memory words, uint256 index, uint256 value) internal pure {
        require(words.length >= 32 * (index + 1), "probe word outside the request");
        assembly ("memory-safe") {
            mstore(add(add(words, 0x20), mul(index, 0x20)), value)
        }
    }
}
