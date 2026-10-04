// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustKernelTypes} from "../../../../implementation/src/generated/IERCTrustKernel.sol";
import {MalformedProbeCore} from "../foundry/MalformedProbeCore.sol";
import {MalformedProbeRecipes} from "../foundry/MalformedProbeRecipes.sol";

/// @notice Witnesses of the bounded word checks of the typed entrypoints, for the bounded word guard mutants.
/// @dev A width witness is an accepted base request in which one address, uint64 or uint48 word also carries the
///      bit just above its declared width, with the identifier recomputed over the changed words: the unmodified
///      decoder rejects it, and a decoder that truncates the word to its width reads the base request again. A kind
///      width witness does the same for the kind word with the bit just above eight bits, recorded under the word
///      index plus 50. A kind witness is a transfer-shaped base request whose kind word holds the first value
///      outside the declared range; a kind control is the same base request unmodified. Every witness and control is
///      measured with the recorder of the malformed probe and recorded under index 1000 + 100 * entrypoint + word,
///      with word 99 for a kind control, so it can never be confused with a catalog recipe. The probe measures and
///      records; it does not judge, and it fails only when one of its own base requests is not accepted.
abstract contract WordGuardProbeCore is MalformedProbeCore {
    uint16 internal constant WITNESS_BASE = 1000;
    uint16 internal constant KIND_CONTROL_WORD = 99;
    uint256 internal constant KIND_ACTION_NONCE = 900_011;
    uint256 internal constant ACTION_CALLDATA_BYTES = 644;
    uint256 internal constant REVERSAL_CALLDATA_BYTES = 388;
    uint16 internal constant ACTION_KIND_WORD = 2;
    uint16 internal constant REVERSAL_KIND_WORD = 3;
    uint256 internal constant FIRST_ACTION_KIND_OUTSIDE = 6;
    uint256 internal constant FIRST_REVERSAL_KIND_OUTSIDE = 3;
    uint16 internal constant KIND_WIDTH_INDEX_OFFSET = 50;
    uint256 internal constant KIND_WORD_BITS = 8;

    /// @dev A transfer-shaped request of a valid kind that the endpoint accepts in its fresh state; it may prepare
    ///      the fixture, for example by verifying the identity of the destination.
    function _probeKindAction(uint256 nonce) internal virtual returns (TrustKernelTypes.ActionRequest memory);

    function _runWordGuardProbe(bool routes) internal {
        address endpoint = _probeEndpoint();
        bytes memory actionWords = abi.encode(_probeAction(ACTION_NONCE));
        _requireBase(endpoint, MalformedProbeRecipes.ACTION_SELECTOR, actionWords, 1);
        _runActionWidthWitnesses(endpoint, actionWords, 1);
        _runKindWidth(endpoint, actionWords, 1, ACTION_KIND_WORD, ACTION_CALLDATA_BYTES);
        if (routes) {
            _requireBase(endpoint, MalformedProbeRecipes.ROUTE_ACTION_SELECTOR, actionWords, 3);
            _runActionWidthWitnesses(endpoint, actionWords, 3);
            _runKindWidth(endpoint, actionWords, 3, ACTION_KIND_WORD, ACTION_CALLDATA_BYTES);
        }

        bytes memory kindWords = abi.encode(_probeKindAction(KIND_ACTION_NONCE));
        _runKind(endpoint, kindWords, 1, ACTION_KIND_WORD, FIRST_ACTION_KIND_OUTSIDE, ACTION_CALLDATA_BYTES, true);
        if (routes) {
            _runKind(endpoint, kindWords, 3, ACTION_KIND_WORD, FIRST_ACTION_KIND_OUTSIDE, ACTION_CALLDATA_BYTES, true);
        }

        TrustKernelTypes.ActionRequest memory reversed = _probeAction(REVERSED_ACTION_NONCE);
        (bool applied,) = endpoint.call(abi.encodeWithSelector(MalformedProbeRecipes.ACTION_SELECTOR, reversed));
        require(applied, "probe could not apply the action to reverse");
        bytes memory reversalWords = abi.encode(_probeReversal(reversed.actionId, REVERSAL_NONCE));
        _requireBase(endpoint, MalformedProbeRecipes.REVERSAL_SELECTOR, reversalWords, 2);
        _runReversalWidthWitnesses(endpoint, reversalWords, 2);
        _runKindWidth(endpoint, reversalWords, 2, REVERSAL_KIND_WORD, REVERSAL_CALLDATA_BYTES);
        _runKind(endpoint, reversalWords, 2, REVERSAL_KIND_WORD, FIRST_REVERSAL_KIND_OUTSIDE, REVERSAL_CALLDATA_BYTES, false);
        if (routes) {
            _requireBase(endpoint, MalformedProbeRecipes.ROUTE_REVERSAL_SELECTOR, reversalWords, 4);
            _runReversalWidthWitnesses(endpoint, reversalWords, 4);
            _runKindWidth(endpoint, reversalWords, 4, REVERSAL_KIND_WORD, REVERSAL_CALLDATA_BYTES);
            _runKind(
                endpoint, reversalWords, 4, REVERSAL_KIND_WORD, FIRST_REVERSAL_KIND_OUTSIDE, REVERSAL_CALLDATA_BYTES, false
            );
        }
    }

    /// @dev Address words 3 to 6, uint64 words 10 and 16 and uint48 words 18 and 19 of an action request.
    function _runActionWidthWitnesses(address endpoint, bytes memory baseWords, uint8 entrypoint) internal {
        for (uint16 word = 3; word <= 6; ++word) {
            _runWidth(endpoint, baseWords, entrypoint, word, 160, ACTION_CALLDATA_BYTES);
        }
        _runWidth(endpoint, baseWords, entrypoint, 10, 64, ACTION_CALLDATA_BYTES);
        _runWidth(endpoint, baseWords, entrypoint, 16, 64, ACTION_CALLDATA_BYTES);
        _runWidth(endpoint, baseWords, entrypoint, 18, 48, ACTION_CALLDATA_BYTES);
        _runWidth(endpoint, baseWords, entrypoint, 19, 48, ACTION_CALLDATA_BYTES);
    }

    /// @dev uint64 words 5 and 8 and uint48 words 10 and 11 of a reversal request.
    function _runReversalWidthWitnesses(address endpoint, bytes memory baseWords, uint8 entrypoint) internal {
        _runWidth(endpoint, baseWords, entrypoint, 5, 64, REVERSAL_CALLDATA_BYTES);
        _runWidth(endpoint, baseWords, entrypoint, 8, 64, REVERSAL_CALLDATA_BYTES);
        _runWidth(endpoint, baseWords, entrypoint, 10, 48, REVERSAL_CALLDATA_BYTES);
        _runWidth(endpoint, baseWords, entrypoint, 11, 48, REVERSAL_CALLDATA_BYTES);
    }

    function _runWidth(
        address endpoint,
        bytes memory baseWords,
        uint8 entrypoint,
        uint16 word,
        uint256 width,
        uint256 calldataBytes
    ) internal {
        uint256 value = _baseWord(baseWords, word) | (uint256(1) << width);
        _runOne(
            MalformedProbeRecipes.Recipe(
                _witnessIndex(entrypoint, word), entrypoint, KIND_WORD, word, value, calldataBytes, POLICY_RECOMPUTE
            ),
            endpoint,
            baseWords,
            _selectorOf(entrypoint)
        );
    }

    /// @dev The kind word of the accepted base request with the bit just above eight bits also set: the unmodified
    ///      decoder rejects it, and a decoder that truncates the kind word to eight bits reads the base request again.
    function _runKindWidth(address endpoint, bytes memory baseWords, uint8 entrypoint, uint16 word, uint256 calldataBytes)
        internal
    {
        uint256 value = _baseWord(baseWords, word) | (uint256(1) << KIND_WORD_BITS);
        _runOne(
            MalformedProbeRecipes.Recipe(
                _witnessIndex(entrypoint, word + KIND_WIDTH_INDEX_OFFSET),
                entrypoint,
                KIND_WORD,
                word,
                value,
                calldataBytes,
                POLICY_RECOMPUTE
            ),
            endpoint,
            baseWords,
            _selectorOf(entrypoint)
        );
    }

    /// @dev The control runs only for a transfer-shaped action base, whose acceptance the witness depends on.
    function _runKind(
        address endpoint,
        bytes memory baseWords,
        uint8 entrypoint,
        uint16 word,
        uint256 outside,
        uint256 calldataBytes,
        bool control
    ) internal {
        bytes4 selector = _selectorOf(entrypoint);
        if (control) {
            _runOne(
                MalformedProbeRecipes.Recipe(
                    _witnessIndex(entrypoint, KIND_CONTROL_WORD), entrypoint, KIND_CONTROL, 0, 0, calldataBytes, 0
                ),
                endpoint,
                baseWords,
                selector
            );
        }
        _runOne(
            MalformedProbeRecipes.Recipe(
                _witnessIndex(entrypoint, word), entrypoint, KIND_WORD, word, outside, calldataBytes, POLICY_RECOMPUTE
            ),
            endpoint,
            baseWords,
            selector
        );
    }

    function _witnessIndex(uint8 entrypoint, uint16 word) internal pure returns (uint16) {
        return WITNESS_BASE + 100 * uint16(entrypoint) + word;
    }

    function _baseWord(bytes memory words, uint256 index) internal pure returns (uint256 word) {
        require(words.length >= 32 * (index + 1), "probe word outside the request");
        assembly ("memory-safe") {
            word := mload(add(add(words, 0x20), mul(index, 0x20)))
        }
    }
}
