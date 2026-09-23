#!/usr/bin/env python3
"""Tie each TRUST 1.2 runtime profile to the exact code identity of its runtimes.

The enforced cell predicate requires the profile index of a runtime-link cell to name a code
identity, and the typed failure report binding needs a compiled consumer of the six typed
failures. This tool prepares both inputs from tracked, continuously verified sources:

* the per-profile bridge artifacts of the runtime binding (runtime template hash and size,
  creation hash, immutable references, ABI and method identifiers),
* the runtime identity record of TRUST 1.2 and the runtime bridge constants of the formal model,
* the source identities that the bridge artifacts were compiled from.

A deployed runtime matches a template exactly when both have the same length and agree on every
byte outside the immutable references; the template carries zeros there. With `--artifacts`, the
tool also rereads the compiled runtimes, confirms their hashes against the templates, and records
where the runtime code loads each typed failure selector (a PUSH4 immediate or a left-aligned
PUSH32 word). A load is a static compiled consumer of the failure; it does not show on which
path the failure is raised.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Any

from tail_common import (
    NONCLAIM, OUTPUT, PROFILE_RUNTIMES, ROOT, RUNTIME_SOURCES, PreparationError, abi_signature,
    dump_json, file_reference, load_json, require, selector, sha256_bytes, sha256_file, write_or_check,
)

DOCUMENT = OUTPUT / "code-identity-v1.json"
BINDING = {"Native": "native", "Partial": "erc3643-partial", "Hook": "erc3643-hook"}
ENDPOINTS = {"Native": "TrustToken", "Partial": "ERC3643TrustAdapter", "Hook": "ERC3643HookAdapter"}
RUNTIME_IDENTITY = ROOT / "evidence/trust12/runtime-identity.json"
BRIDGE_THEORY = ROOT / "formal/isabelle/ERC_TRUST/TRUST_Runtime_Bridge_Generated.thy"
KERNEL_ABI = ROOT / "spec/generated/kernel-v2-abi.json"
THEORY_TEMPLATES = {
    "TrustToken": ("native_runtime_template_sha256", "native_runtime_bytes"),
    "ERC3643TrustAdapter": ("profile_adapter_runtime_sha256", "profile_adapter_runtime_bytes"),
    "ProfileGovernor": ("profile_governor_runtime_sha256", "profile_governor_runtime_bytes"),
}
# Words of a typed failure payload after the selector and what the 27-cell gate binds them to.
REPORT_BINDING = {
    "TrustInvalidCommand": ["the identifier of the decoded command", "a registered reason code"],
    "TrustRejected": ["the identifier of the decoded command", "a registered reason code"],
    "TrustOperationalFailure": ["the identifier of the decoded command", "a registered reason code",
                                "the dependency reference (not bound by the gate)"],
    "TrustUnauthorized": ["the transaction sender", "the authority reference of the decoded command"],
    "TrustReplay": ["the command identifier or a hashed nonce key (not bound by the gate)"],
    "TrustTerminal": ["a case identifier (not bound by the gate)"],
}


def binding_artifacts(profile: str) -> list[dict[str, Any]]:
    path = ROOT / "evidence/runtime-binding-v3" / BINDING[profile] / "bridge-artifacts.json"
    entries = load_json(path)
    names = [entry["contract"] for entry in entries]
    require(names == list(PROFILE_RUNTIMES[profile]), f"{profile}: bridge artifact set drift: {names}")
    return entries


def source_identities(profile: str) -> list[dict[str, Any]]:
    path = ROOT / "evidence/runtime-binding-v3" / BINDING[profile] / "source-identities.json"
    records = load_json(path)
    for record in records:
        current = ROOT / record["path"]
        require(current.is_file(), f"{profile}: bridge source missing: {record['path']}")
        require(sha256_file(current) == record["sha256"], f"{profile}: bridge artifacts are stale for {record['path']}")
    return records


def merged_ranges(references: list[dict[str, Any]]) -> list[list[int]]:
    ranges = sorted((int(item["start"]), int(item["start"]) + int(item["length"])) for item in references)
    merged: list[list[int]] = []
    for start, end in ranges:
        if merged and start <= merged[-1][1]:
            merged[-1][1] = max(merged[-1][1], end)
        else:
            merged.append([start, end])
    return merged


def mask(code: bytes, ranges: list[list[int]]) -> bytes:
    data = bytearray(code)
    for start, end in ranges:
        require(end <= len(data), "immutable reference outside the code")
        data[start:end] = bytes(end - start)
    return bytes(data)


def matches_template(deployed: bytes, template: bytes, ranges: list[list[int]]) -> bool:
    """Exact code identity: same length and equal bytes outside the immutable references."""
    return len(deployed) == len(template) and mask(deployed, ranges) == mask(template, ranges)


def instructions(code: bytes) -> list[tuple[int, int, int | None]]:
    """Linear decoding into (offset, opcode, immediate) triples."""
    decoded, offset = [], 0
    while offset < len(code):
        opcode = code[offset]
        if 0x60 <= opcode <= 0x7F:
            width = opcode - 0x5F
            decoded.append((offset, opcode, int.from_bytes(code[offset + 1:offset + 1 + width], "big")))
            offset += 1 + width
        else:
            decoded.append((offset, opcode, None))
            offset += 1
    return decoded


def selector_occurrences(code: bytes, value: int) -> dict[str, list[int]]:
    """Offsets where the runtime loads a four-byte selector.

    The size-optimizing compiler loads a selector in one of three forms: a PUSH4 immediate, a
    PUSH32 word with the selector in its leading bytes, or a shorter immediate followed by
    PUSH1 shift and SHL when the selector ends in zero bits. Each form is counted separately.
    """
    found: dict[str, list[int]] = {"push4": [], "push32LeftAligned": [], "shiftedPush": []}
    aligned = value << 224
    decoded = instructions(code)
    for index, (offset, opcode, immediate) in enumerate(decoded):
        if immediate is None:
            continue
        width = opcode - 0x5F
        if width == 4 and immediate == value:
            found["push4"].append(offset)
        elif width == 32 and immediate == aligned:
            found["push32LeftAligned"].append(offset)
        elif index + 2 < len(decoded):
            _, shift_opcode, shift = decoded[index + 1]
            _, operation, _ = decoded[index + 2]
            if shift_opcode == 0x60 and operation == 0x1B and ((immediate << shift) & ((1 << 256) - 1)) == aligned:
                found["shiftedPush"].append(offset)
    return found


def theory_value(text: str, name: str) -> str:
    match = re.search(rf'definition {re.escape(name)} :: \S+ where\s+"{re.escape(name)} = (.+?)"', text, re.DOTALL)
    require(match is not None, f"bridge constant missing: {name}")
    return match.group(1).strip().strip("'")


def typed_failures() -> list[dict[str, Any]]:
    abi = load_json(KERNEL_ABI)
    failures = []
    for entry in (item for item in abi["abi"] if item["type"] == "error"):
        signature = abi_signature(entry)
        require(entry["name"] in REPORT_BINDING, f"unexpected kernel error {entry['name']}")
        failures.append({
            "name": entry["name"],
            "signature": signature,
            "selector": f"0x{selector(signature):08x}",
            "words": [{"word": index, "name": item["name"], "type": item["type"], "binding": binding}
                      for index, (item, binding) in enumerate(zip(entry["inputs"], REPORT_BINDING[entry["name"]]))],
        })
    require(len(failures) == 6 and {item["name"] for item in failures} == set(REPORT_BINDING), "typed failure set drift")
    return sorted(failures, key=lambda item: item["selector"])


def build(artifacts: Path | None) -> dict[str, Any]:
    identity = load_json(RUNTIME_IDENTITY)
    require(identity["status"] == "PASS", "TRUST 1.2 runtime identity is not PASS")
    theory = BRIDGE_THEORY.read_text(encoding="utf-8")
    failures = typed_failures()
    failure_signatures = {item["signature"] for item in failures}
    profiles, compiled = {}, {}
    for profile in PROFILE_RUNTIMES:
        sources = source_identities(profile)
        runtimes = []
        for entry in binding_artifacts(profile):
            name = entry["contract"]
            require(entry["source"] == RUNTIME_SOURCES[name], f"{name}: source path drift")
            template = entry["runtimeTemplate"]
            recorded = identity["runtimes"][name]
            require(template["sha256"] == recorded["runtimeSha256"] and template["bytes"] == recorded["runtimeBytes"],
                    f"{name}: bridge template and runtime identity differ")
            require(entry["creationBytecode"]["bytes"] == recorded["creationBytes"], f"{name}: creation size drift")
            if name in THEORY_TEMPLATES:
                sha_name, bytes_name = THEORY_TEMPLATES[name]
                require(theory_value(theory, sha_name) == template["sha256"], f"{name}: formal bridge template drift")
                require(int(theory_value(theory, bytes_name)) == template["bytes"], f"{name}: formal bridge size drift")
            ranges = merged_ranges(entry["immutableReferences"])
            errors = sorted(abi_signature(item) for item in entry["abi"] if item["type"] == "error")
            runtimes.append({
                "contract": name,
                "source": entry["source"],
                "runtimeTemplate": {"sha256": template["sha256"], "bytes": template["bytes"]},
                "creationBytecode": entry["creationBytecode"],
                "immutableRanges": ranges,
                "immutableReferenceCount": len(entry["immutableReferences"]),
                "methodIdentifierCount": len(entry["methodIdentifiers"]),
                "declaresEveryTypedFailure": failure_signatures <= set(errors),
                "otherErrors": sorted(set(errors) - failure_signatures),
            })
            if artifacts is not None:
                compiled[name] = compiled_facts(artifacts, entry, ranges, failures)
        require(any(item["contract"] == ENDPOINTS[profile] and item["declaresEveryTypedFailure"] for item in runtimes),
                f"{profile}: the endpoint does not declare every typed failure")
        profiles[profile] = {
            "profileIndex": {"Native": "Runtime_Native", "Partial": "Runtime_Partial", "Hook": "Runtime_Hook"}[profile],
            "endpoint": ENDPOINTS[profile],
            "runtimes": runtimes,
            "sourceIdentities": sources,
            "identityRootSha256": sha256_bytes("".join(
                f"{item['contract']} {item['runtimeTemplate']['sha256']} {item['runtimeTemplate']['bytes']} "
                f"{','.join(f'{start}-{end}' for start, end in item['immutableRanges'])}\n"
                for item in runtimes).encode("utf-8")),
        }
    document = {
        "schema": "trust12-tail-preparation-code-identity-v1",
        "status": "PREPARED_NOT_CLOSED",
        "sources": [file_reference(path) for path in (RUNTIME_IDENTITY, BRIDGE_THEORY, KERNEL_ABI)] + [
            file_reference(ROOT / "evidence/runtime-binding-v3" / BINDING[profile] / name)
            for profile in PROFILE_RUNTIMES for name in ("bridge-artifacts.json", "source-identities.json")
        ],
        "matchingRule": (
            "A deployed runtime has the code identity of a template exactly when both have the same length and "
            "every byte outside the merged immutable ranges is equal. Templates carry zeros inside those ranges, "
            "so the template hash is also the hash of the masked deployed runtime."
        ),
        "profiles": profiles,
        "typedFailures": failures,
        "compiledScan": {
            "status": "RECOMPUTED" if artifacts is not None else "NOT_RECOMPUTED",
            "runtimes": compiled,
        },
        "openItems": [
            "The formal runtime bridge constants name the Native and Partial runtimes only; the Hook runtimes are "
            "bound by the runtime binding and the TRUST 1.2 runtime identity, not by a formal bridge constant.",
            "No certificate of a runtime-link cell records its program bytes in this document; the certificate "
            "registry binds each certificate to one of these identities.",
        ],
        "nonclaim": NONCLAIM,
    }
    return document


def compiled_facts(artifacts: Path, entry: dict[str, Any], ranges: list[list[int]],
                   failures: list[dict[str, Any]]) -> dict[str, Any]:
    name = entry["contract"]
    path = artifacts / f"{Path(entry['source']).name}" / f"{name}.json"
    require(path.is_file(), f"compiled artifact missing for {name}")
    artifact = load_json(path)
    runtime = bytes.fromhex(artifact["deployedBytecode"]["object"].removeprefix("0x"))
    require(sha256_bytes(runtime) == entry["runtimeTemplate"]["sha256"], f"{name}: compiled runtime differs from the template")
    require(mask(runtime, ranges) == runtime, f"{name}: template carries non-zero bytes inside an immutable range")
    compiled_ranges = merged_ranges([reference for references in
                                     artifact["deployedBytecode"].get("immutableReferences", {}).values()
                                     for reference in references])
    require(compiled_ranges == ranges, f"{name}: compiled immutable ranges differ from the bridge artifact")
    return {
        "runtimeSha256": sha256_bytes(runtime),
        "typedFailureSelectorLoads": {
            item["name"]: selector_occurrences(runtime, int(item["selector"], 16)) for item in failures
        },
    }


def build_with_recorded_scan() -> dict[str, Any]:
    """Rebuild from tracked sources only, keeping the recorded compiled scan.

    The scan must still belong to the tracked runtime templates; rescanning needs the artifacts.
    """
    document = build(None)
    document["compiledScan"] = load_json(DOCUMENT)["compiledScan"]
    for profile in document["profiles"].values():
        for runtime in profile["runtimes"]:
            scan = document["compiledScan"]["runtimes"].get(runtime["contract"])
            require(scan is None or scan["runtimeSha256"] == runtime["runtimeTemplate"]["sha256"],
                    f"{runtime['contract']}: recorded scan belongs to another runtime")
    return document


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--artifacts", type=Path, help="compiled artifact directory (forge out) to rescan")
    parser.add_argument("--check", action="store_true", help="verify the tracked document instead of writing it")
    args = parser.parse_args(argv)
    document = build_with_recorded_scan() if args.check and args.artifacts is None else build(args.artifacts)
    write_or_check(DOCUMENT, dump_json(document), args.check)
    print(dump_json({"status": "PASS_CODE_IDENTITY_" + ("CHECKED" if args.check else "WRITTEN"),
                     "compiledScan": document["compiledScan"]["status"],
                     "runtimes": sum(len(item["runtimes"]) for item in document["profiles"].values())}), end="")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except PreparationError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
