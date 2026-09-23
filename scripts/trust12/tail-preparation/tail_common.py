#!/usr/bin/env python3
"""Shared helpers of the TRUST 1.2 tail preparation tools.

The tools in this directory prepare the evidence inputs of the last open runtime-link
conditions (malformed input, certificate registry and partition, code identity, route,
state and receipt crosswalks, and the independent Assurance input seal). They never run a
prover, never write outside their own output directories, and never mark a condition
closed. Every generated document carries an explicit non-claim.
"""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from typing import Any, Iterable

ROOT = Path(__file__).resolve().parents[3]
TOOLS = Path(__file__).resolve().parent
OUTPUT = ROOT / "evidence" / "trust12" / "runtime-link" / "tail-preparation"
SCHEMA_PREFIX = "trust12-tail-preparation"
PREPARATION_STATUS = "PREPARED_NOT_CLOSED"
NONCLAIM = (
    "Preparation only. This document describes inputs, checks and acceptance criteria for "
    "conditions that remain open. It does not discharge a runtime-link cell, the malformed "
    "branch, the acceptance partition, the central refinement closure or the independent "
    "Assurance, and it does not authorize a merge, a release or a deployment."
)

PROFILES = ("Native", "Partial", "Hook")
FORWARD_OPERATIONS = ("FREEZE", "SEIZE", "CONFISCATE", "LIQUIDATE", "RESTRICT", "RECOVER")
REVERSAL_OPERATIONS = ("UNFREEZE", "RELEASE", "UNRESTRICT")
OPERATIONS = FORWARD_OPERATIONS + REVERSAL_OPERATIONS
OUTCOME_BRANCHES = ("applied", "not-applied")

# Runtime contracts that make up each profile. The upstream ERC-3643 token of the Partial
# and Hook profiles is an external dependency and is identified separately.
PROFILE_RUNTIMES = {
    "Native": ("TrustToken",),
    "Partial": ("ERC3643TrustAdapter", "ProfileGovernor"),
    "Hook": ("ERC3643HookAdapter", "ERC3643HookGovernor", "ERC3643HookCompliance", "ERC3643HookFactory"),
}
RUNTIME_SOURCES = {
    "TrustToken": "implementation/src/TrustToken.sol",
    "ERC3643TrustAdapter": "implementation/src/profiles/ERC3643TrustAdapter.sol",
    "ProfileGovernor": "implementation/src/profiles/ProfileGovernor.sol",
    "ERC3643HookAdapter": "implementation/src/profiles/ERC3643HookAdapter.sol",
    "ERC3643HookGovernor": "implementation/src/profiles/ERC3643HookGovernor.sol",
    "ERC3643HookCompliance": "implementation/src/profiles/ERC3643HookCompliance.sol",
    "ERC3643HookFactory": "implementation/src/profiles/ERC3643HookFactory.sol",
}


class PreparationError(RuntimeError):
    """A fail-closed preparation check did not hold."""


def require(condition: object, message: str) -> None:
    if not condition:
        raise PreparationError(message)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def canonical_text_sha256(path: Path) -> str:
    """Hash text with LF line endings, as the release manifest of the repository does."""
    return sha256_bytes(path.read_text(encoding="utf-8").replace("\r\n", "\n").replace("\r", "\n").encode("utf-8"))


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def dump_json(value: Any) -> str:
    return json.dumps(value, indent=2) + "\n"


def relative(path: Path, root: Path = ROOT) -> str:
    return path.resolve().relative_to(root.resolve()).as_posix()


def file_reference(path: Path, root: Path = ROOT) -> dict[str, Any]:
    require(path.is_file(), f"missing input: {path.name}")
    return {"path": relative(path, root), "bytes": path.stat().st_size, "sha256": sha256_file(path)}


def write_or_check(path: Path, text: str, check: bool) -> str:
    """Write a generated document, or verify that the tracked copy is byte-identical."""
    encoded = text.encode("utf-8")
    if check:
        require(path.is_file(), f"generated document missing: {relative(path)}")
        require(path.read_bytes() == encoded, f"generated document drift: {relative(path)}")
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(encoded)
    return sha256_bytes(encoded)


def unique(values: Iterable[Any]) -> bool:
    items = list(values)
    return len(items) == len(set(items))


def tree_root(records: Iterable[dict[str, Any]]) -> str:
    """Order-independent root of file records, in the `sha256  path` line form used by the repository."""
    lines = sorted(f"{record['sha256']}  {record.get('root', '')}:{record['path']}\n" for record in records)
    return sha256_bytes("".join(lines).encode("utf-8"))


# ---------------------------------------------------------------------------
# JSON Schema subset validator
# ---------------------------------------------------------------------------
# The schemas in the output directory are the single description of the prepared document
# formats. This validator implements the subset of JSON Schema 2020-12 that those schemas use,
# so that the contract and the fail-closed checks cannot drift apart.

_SUPPORTED_KEYWORDS = {
    "$schema", "$id", "$defs", "$ref", "title", "description", "type", "properties", "required",
    "additionalProperties", "items", "minItems", "maxItems", "uniqueItems", "enum", "const",
    "pattern", "minimum", "maximum", "minLength", "oneOf",
}
_TYPES = {
    "object": dict, "array": list, "string": str, "boolean": bool, "null": type(None),
}


def _is_type(value: Any, name: str) -> bool:
    if name == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if name == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    return isinstance(value, _TYPES[name])


def schema_errors(value: Any, schema: dict[str, Any], root: dict[str, Any] | None = None,
                  where: str = "$") -> list[str]:
    root = schema if root is None else root
    unknown = set(schema) - _SUPPORTED_KEYWORDS
    if unknown:
        return [f"{where}: unsupported schema keyword {sorted(unknown)}"]
    if "$ref" in schema:
        reference = schema["$ref"]
        if not reference.startswith("#/$defs/"):
            return [f"{where}: unsupported reference {reference}"]
        return schema_errors(value, root["$defs"][reference[len("#/$defs/"):]], root, where)
    errors: list[str] = []
    if "oneOf" in schema:
        matches = [option for option in schema["oneOf"] if not schema_errors(value, option, root, where)]
        if len(matches) != 1:
            errors.append(f"{where}: matches {len(matches)} of the oneOf alternatives")
    if "type" in schema:
        names = schema["type"] if isinstance(schema["type"], list) else [schema["type"]]
        if not any(_is_type(value, name) for name in names):
            return errors + [f"{where}: expected {'/'.join(names)}"]
    if "const" in schema and value != schema["const"]:
        errors.append(f"{where}: expected constant {schema['const']!r}")
    if "enum" in schema and value not in schema["enum"]:
        errors.append(f"{where}: {value!r} is not an allowed value")
    if isinstance(value, str):
        if "pattern" in schema and re.search(schema["pattern"], value) is None:
            errors.append(f"{where}: does not match {schema['pattern']}")
        if "minLength" in schema and len(value) < schema["minLength"]:
            errors.append(f"{where}: shorter than {schema['minLength']}")
    if _is_type(value, "number"):
        if "minimum" in schema and value < schema["minimum"]:
            errors.append(f"{where}: below {schema['minimum']}")
        if "maximum" in schema and value > schema["maximum"]:
            errors.append(f"{where}: above {schema['maximum']}")
    if isinstance(value, list):
        if "minItems" in schema and len(value) < schema["minItems"]:
            errors.append(f"{where}: fewer than {schema['minItems']} items")
        if "maxItems" in schema and len(value) > schema["maxItems"]:
            errors.append(f"{where}: more than {schema['maxItems']} items")
        if schema.get("uniqueItems") and not unique(json.dumps(item, sort_keys=True) for item in value):
            errors.append(f"{where}: items are not unique")
        if "items" in schema:
            for index, item in enumerate(value):
                errors += schema_errors(item, schema["items"], root, f"{where}[{index}]")
    if isinstance(value, dict):
        for key in schema.get("required", []):
            if key not in value:
                errors.append(f"{where}: missing {key}")
        properties = schema.get("properties", {})
        for key, item in value.items():
            if key in properties:
                errors += schema_errors(item, properties[key], root, f"{where}.{key}")
            elif schema.get("additionalProperties") is False:
                errors.append(f"{where}: unexpected property {key}")
            elif isinstance(schema.get("additionalProperties"), dict):
                errors += schema_errors(item, schema["additionalProperties"], root, f"{where}.{key}")
    return errors


def require_schema(value: Any, schema: dict[str, Any], label: str) -> None:
    errors = schema_errors(value, schema)
    require(not errors, f"{label} violates its schema: " + "; ".join(errors[:10]))


# ---------------------------------------------------------------------------
# Keccak-256 (the Ethereum variant, padding 0x01, not the NIST SHA3 padding 0x06)
# ---------------------------------------------------------------------------

_ROUND_CONSTANTS = (
    0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
    0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
    0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
    0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
    0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
    0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
)
_ROTATIONS = (
    (0, 36, 3, 41, 18),
    (1, 44, 10, 45, 2),
    (62, 6, 43, 15, 61),
    (28, 55, 25, 21, 56),
    (27, 20, 39, 8, 14),
)
_MASK = (1 << 64) - 1


def _rotate(value: int, shift: int) -> int:
    return ((value << shift) | (value >> (64 - shift))) & _MASK if shift else value


def _permute(state: list[list[int]]) -> None:
    for constant in _ROUND_CONSTANTS:
        columns = [state[x][0] ^ state[x][1] ^ state[x][2] ^ state[x][3] ^ state[x][4] for x in range(5)]
        for x in range(5):
            delta = columns[(x - 1) % 5] ^ _rotate(columns[(x + 1) % 5], 1)
            for y in range(5):
                state[x][y] ^= delta
        moved = [[0] * 5 for _ in range(5)]
        for x in range(5):
            for y in range(5):
                moved[y][(2 * x + 3 * y) % 5] = _rotate(state[x][y], _ROTATIONS[x][y])
        for x in range(5):
            for y in range(5):
                state[x][y] = moved[x][y] ^ ((~moved[(x + 1) % 5][y]) & moved[(x + 2) % 5][y])
        state[0][0] ^= constant


def keccak256(data: bytes) -> bytes:
    rate = 136
    padded = bytearray(data)
    padded.append(0x01)
    while len(padded) % rate:
        padded.append(0)
    padded[-1] |= 0x80
    state = [[0] * 5 for _ in range(5)]
    for offset in range(0, len(padded), rate):
        block = padded[offset:offset + rate]
        for index in range(rate // 8):
            x, y = index % 5, index // 5
            state[x][y] ^= int.from_bytes(block[8 * index:8 * index + 8], "little")
        _permute(state)
    output = bytearray()
    for index in range(4):
        x, y = index % 5, index // 5
        output += state[x][y].to_bytes(8, "little")
    return bytes(output)


def selector(signature: str) -> int:
    return int.from_bytes(keccak256(signature.encode("ascii"))[:4], "big")


def canonical_type(entry: dict[str, Any]) -> str:
    """ABI canonical type of one input, expanding tuples recursively."""
    kind = entry["type"]
    if kind.startswith("tuple"):
        inner = ",".join(canonical_type(component) for component in entry["components"])
        return f"({inner}){kind[len('tuple'):]}"
    return kind


def abi_signature(entry: dict[str, Any]) -> str:
    return f"{entry['name']}({','.join(canonical_type(item) for item in entry.get('inputs', []))})"


# The implementation must match the published Keccak test vectors before any selector is used.
require(
    keccak256(b"").hex() == "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470",
    "keccak256 self-test failed",
)
require(selector("transfer(address,uint256)") == 0xA9059CBB, "selector self-test failed")
