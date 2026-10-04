#!/usr/bin/env python3
"""The fixed ABI reading of a typed failure report and its binding, as the runtime-link gate defines them.

`abi_failure_report` and `failure_report_binds` mirror the definitions of the same names in the gate
theory of the runtime link:

* the selector is the first four payload bytes in big-endian order;
* TrustInvalidCommand and TrustRejected are read only from exactly 68 bytes: word 0, and the reason
  from word 1;
* TrustOperationalFailure is read only from exactly 100 bytes: word 0, the reason from word 1 and the
  dependency reference from word 2;
* TrustUnauthorized is read only from exactly 68 bytes: words 0 and 1;
* TrustReplay and TrustTerminal are read only from exactly 36 bytes: word 0;
* every other payload has no report.

A report binds to the decoded command and the transaction sender when word 0 is the command
identifier and the reason is a registered reason code (TrustInvalidCommand, TrustRejected,
TrustOperationalFailure); when word 0 is the sender and word 1 the authority reference of the command
(TrustUnauthorized); when word 0 is the case of a forward command (TrustTerminal; a reversal is not
bound because its case is read from storage); and always for TrustReplay, whose key may be a hashed
nonce key. The selector constants and the reason code registry are read from the generated formal
runtime bridge, so the reading cannot drift from the formal constants.
"""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path
from typing import Any

_TOOLS = os.environ.get("TRUST12_TAIL_TOOLS")
if _TOOLS:
    sys.path.insert(0, _TOOLS)

from tail_common import ROOT, require  # noqa: E402

BRIDGE_THEORY = ROOT / "formal/isabelle/ERC_TRUST/TRUST_Runtime_Bridge_Generated.thy"
SELECTOR_CONSTANTS = {
    "TrustInvalidCommand": "trust_invalid_command_selector",
    "TrustRejected": "trust_rejected_selector",
    "TrustOperationalFailure": "trust_operational_failure_selector",
    "TrustUnauthorized": "trust_unauthorized_selector",
    "TrustReplay": "trust_replay_selector",
    "TrustTerminal": "trust_terminal_selector",
}
COMMAND_BOUND = ("TrustInvalidCommand", "TrustRejected", "TrustOperationalFailure")
EXACT_LENGTH = {"TrustInvalidCommand": 68, "TrustRejected": 68, "TrustOperationalFailure": 100,
                "TrustUnauthorized": 68, "TrustReplay": 36, "TrustTerminal": 36}


def formal_constants(text: str | None = None) -> dict[str, Any]:
    """Selector values and registered reason codes of the generated formal bridge."""
    text = BRIDGE_THEORY.read_text(encoding="utf-8") if text is None else text
    selectors = {}
    for name, constant in SELECTOR_CONSTANTS.items():
        match = re.search(rf'definition {constant} :: nat where\s+"{constant} = (\d+)"', text)
        require(match is not None, f"formal selector constant missing: {constant}")
        selectors[name] = int(match.group(1))
    block = re.search(r'"reason_code_registry =\s*\[(.*?)\]"', text, re.DOTALL)
    require(block is not None, "formal reason code registry missing")
    reasons = {int(value) for value in re.findall(r"\((\d+),\s*''[A-Z_]+''\)", block.group(1))}
    require(reasons, "formal reason code registry is empty")
    return {"selectors": selectors, "names": {value: name for name, value in selectors.items()}, "reasons": reasons}


def _word(payload: bytes, index: int) -> int:
    """rl_word_at: the big-endian value of the 32 bytes after the selector and `index` words."""
    return int.from_bytes(payload[4 + 32 * index:4 + 32 * index + 32], "big")


def abi_failure_report(payload: bytes, constants: dict[str, Any]) -> dict[str, Any] | None:
    if len(payload) < 4:
        return None
    value = int.from_bytes(payload[:4], "big")
    name = constants["names"].get(value)
    if name is None or len(payload) != EXACT_LENGTH[name]:
        return None
    if name in ("TrustInvalidCommand", "TrustRejected"):
        return {"selector": value, "name": name, "word0": _word(payload, 0), "word1": None, "reason": _word(payload, 1)}
    if name == "TrustOperationalFailure":
        return {"selector": value, "name": name, "word0": _word(payload, 0), "word1": _word(payload, 2),
                "reason": _word(payload, 1)}
    if name == "TrustUnauthorized":
        return {"selector": value, "name": name, "word0": _word(payload, 0), "word1": _word(payload, 1), "reason": None}
    return {"selector": value, "name": name, "word0": _word(payload, 0), "word1": None, "reason": None}


def failure_report_binds(report: dict[str, Any], command: dict[str, Any] | None, sender: int,
                         constants: dict[str, Any]) -> bool:
    """`command` holds kind ("forward" or "reverse"), commandId, authorityRef and, for a forward
    command, caseId, all as integers."""
    if command is None:
        return False
    name = constants["names"].get(report["selector"])
    if name in COMMAND_BOUND:
        return (report["word0"] == command["commandId"] and report["reason"] is not None
                and report["reason"] in constants["reasons"])
    if name == "TrustUnauthorized":
        return report["word0"] == sender and report["word1"] == command["authorityRef"]
    if name == "TrustTerminal":
        return report["word0"] == command["caseId"] if command["kind"] == "forward" else True
    return name == "TrustReplay"


def typed_failure_outcome(report: dict[str, Any], constants: dict[str, Any]) -> str:
    return "operational" if report["selector"] == constants["selectors"]["TrustOperationalFailure"] else "rejected"


def sensitivity_controls(payload: bytes, command: dict[str, Any], sender: int,
                         constants: dict[str, Any]) -> dict[str, bool]:
    """Mutations of an observed payload that the reading must not accept; True means detected."""
    report = abi_failure_report(payload, constants)
    require(report is not None, "sensitivity controls need a readable payload")
    detected = {
        "extraByte": abi_failure_report(payload + b"\x00", constants) is None,
        "missingByte": abi_failure_report(payload[:-1], constants) is None,
    }
    name = report["name"]
    if name in COMMAND_BOUND or name == "TrustUnauthorized" or (name == "TrustTerminal" and command["kind"] == "forward"):
        flipped = bytearray(payload)
        flipped[4 + 31] ^= 1
        tampered = abi_failure_report(bytes(flipped), constants)
        detected["word0"] = tampered is None or not failure_report_binds(tampered, command, sender, constants)
    if name in COMMAND_BOUND:
        unregistered = bytearray(payload)
        unregistered[4 + 32:4 + 64] = (0xFFFF).to_bytes(32, "big")
        tampered = abi_failure_report(bytes(unregistered), constants)
        detected["unregisteredReason"] = tampered is None or not failure_report_binds(tampered, command, sender, constants)
    if name == "TrustUnauthorized":
        flipped = bytearray(payload)
        flipped[4 + 63] ^= 1
        tampered = abi_failure_report(bytes(flipped), constants)
        detected["word1"] = tampered is None or not failure_report_binds(tampered, command, sender, constants)
    return detected
