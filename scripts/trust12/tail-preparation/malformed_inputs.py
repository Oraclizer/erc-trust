#!/usr/bin/env python3
"""Build the malformed input catalog of the three TRUST 1.2 runtime profiles.

A request to a typed command function is in canonical form only when the selector is a typed
command selector, every bounded word of the fixed-length tuple is canonical (the calldata length
is exact, the enum word is below its bound, and every address, uint64 and uint48 word fits its
width) and the call carries zero value. Any other request sent to a profile endpoint has no typed
command, so an execution of it belongs to the out-of-specification branch (decision 12): it must
fail without an external call, without a log and without a net state change. Its revert data is
not specified; it can be empty, a typed failure or any other data.

The catalog is derived from three sources that must agree: the kernel schema, the generated
kernel ABI and the generated runtime bridge constants that the formal model imports. It lists
the symbolic malformed classes and a finite set of concrete probe recipes. A recipe is a
mutation of a well-formed request that the probe harness builds in its own deployment, because
the command identifier binds the endpoint address and the chain.

Ordering probes combine one non-canonical word with a defect that a kernel rule would report as a
typed failure (a foreign domain or a stale identifier). The model still classifies such a request
as outside canonical form. Decision 12 leaves open which defect is detected first, so a typed
failure there conforms as long as the call fails without an external call, a log or a state change;
the probe records which check ran first.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Any

from tail_common import (
    NONCLAIM, OUTPUT, PROFILES, ROOT, PreparationError, abi_signature, dump_json, file_reference,
    load_json, require, selector, write_or_check,
)

DOCUMENT = OUTPUT / "malformed-inputs-v1.json"
GENERATED_PROBE_TABLE = ROOT / "scripts/trust12/tail-preparation/foundry/MalformedProbeRecipes.sol"
KERNEL_SCHEMA = ROOT / "spec/erc-trust-kernel-v2.json"
KERNEL_ABI = ROOT / "spec/generated/kernel-v2-abi.json"
BRIDGE_THEORY = ROOT / "formal/isabelle/ERC_TRUST/TRUST_Runtime_Bridge_Generated.thy"
KERNEL_INTERFACE = ROOT / "implementation/src/generated/IERCTrustKernel.sol"

SHAPES = {
    "action": {"struct": "ActionRequest", "kernelFunction": "executeRegulatoryAction", "prefix": "action"},
    "reversal": {"struct": "ReversalRequest", "kernelFunction": "executeRegulatoryReversal", "prefix": "reversal"},
}
# Typed command entrypoints of each profile endpoint. The route inventory checks these against the
# compiled ABI of every endpoint.
ENDPOINT_ENTRYPOINTS = {
    "Native": {
        "executeRegulatoryAction": "action",
        "executeRegulatoryReversal": "reversal",
        "executeERC7943Action": "action",
        "executeERC7943Reversal": "reversal",
    },
    "Partial": {"executeRegulatoryAction": "action", "executeRegulatoryReversal": "reversal"},
    "Hook": {"executeRegulatoryAction": "action", "executeRegulatoryReversal": "reversal"},
}
ENDPOINTS = {"Native": "TrustToken", "Partial": "ERC3643TrustAdapter", "Hook": "ERC3643HookAdapter"}
WIDTHS = {"address": 160, "uint64": 64, "uint48": 48}
GENERIC_DISPATCHER_SELECTOR = 0xFFFFFFFF

# Probe kinds, shared with the generated Solidity table.
KIND_LENGTH, KIND_WORD, KIND_SELECTOR, KIND_VALUE, KIND_CONTROL = 1, 2, 3, 4, 5
POLICY_RECOMPUTE, POLICY_STALE, POLICY_FOREIGN_DOMAIN = 1, 2, 3
PROFILE_CODES = {"Native": 1, "Partial": 2, "Hook": 3}
ENTRYPOINT_CODES = {
    "executeRegulatoryAction": 1, "executeRegulatoryReversal": 2,
    "executeERC7943Action": 3, "executeERC7943Reversal": 4, "none": 0,
}


def theory_constant(text: str, name: str) -> str:
    match = re.search(rf'definition {re.escape(name)} :: "?[^"\n]+"?\s+where\s+"{re.escape(name)} =\s*(.+?)"',
                      text, re.DOTALL)
    if match is None:
        match = re.search(rf'definition {re.escape(name)} :: \S+ where "{re.escape(name)} = (.+?)"', text)
    require(match is not None, f"bridge constant missing: {name}")
    return match.group(1).strip()


def theory_number(text: str, name: str) -> int:
    value = theory_constant(text, name)
    require(re.fullmatch(r"\d+", value) is not None, f"bridge constant is not a number: {name}")
    return int(value)


def theory_name_set(text: str, name: str) -> list[int]:
    value = theory_constant(text, name)
    require(value.startswith("{") and value.endswith("}"), f"bridge constant is not a set: {name}")
    return sorted(theory_number(text, item.strip()) for item in value[1:-1].split(",") if item.strip())


def theory_list(text: str, name: str) -> list[Any]:
    value = theory_constant(text, name)
    require(value.startswith("[") and value.endswith("]"), f"bridge constant is not a list: {name}")
    inner = value[1:-1].strip()
    if not inner:
        return []
    if inner.startswith("("):
        return [[int(first), int(second)] for first, second in re.findall(r"\((\d+),\s*(\d+)\)", inner)]
    return [int(item) for item in re.findall(r"\d+", inner)]


def shape_from_sources(name: str, schema: dict[str, Any], abi: dict[str, Any], theory: str) -> dict[str, Any]:
    spec = SHAPES[name]
    fields = schema["structs"][spec["struct"]]["fields"]
    entry = next((item for item in abi["abi"] if item["type"] == "function" and item["name"] == spec["kernelFunction"]), None)
    require(entry is not None and len(entry["inputs"]) == 1, f"kernel ABI lacks {spec['kernelFunction']}")
    components = entry["inputs"][0]["components"]
    require(len(components) == len(fields), f"kernel ABI and schema disagree on {spec['struct']}")
    words, guards = [], {"enum": [], "address": [], "uint64": [], "uint48": []}
    for index, (component, field) in enumerate(zip(components, fields)):
        require(component["name"] == field["name"] and component["type"] == field["type"],
                f"{spec['struct']}.{field['name']} drifts between the kernel ABI and schema")
        guard = None
        if field.get("enum"):
            bound = len(schema["enums"][field["enum"]]["values"])
            guards["enum"].append([index, bound])
            guard = {"kind": "enum", "bound": bound, "enum": field["enum"]}
        elif field["type"] in WIDTHS:
            guards[field["type"]].append(index)
            guard = {"kind": field["type"], "width": WIDTHS[field["type"]]}
        else:
            require(field["type"] in {"bytes32", "uint256"}, f"unsupported static field type {field['type']}")
        words.append({"word": index, "field": field["name"], "type": field["type"], "guard": guard})
    count = len(components)
    length = 4 + 32 * count
    prefix = spec["prefix"]
    require(abi["calldataLengths"][spec["struct"]] == length, f"kernel ABI calldata length drift: {spec['struct']}")
    require(theory_number(theory, f"{prefix}_calldata_length") == length, f"bridge length drift: {prefix}")
    require(theory_number(theory, f"{prefix}_word_count") == count, f"bridge word count drift: {prefix}")
    require(theory_list(theory, f"{prefix}_enum_words") == guards["enum"], f"bridge enum guard drift: {prefix}")
    for width in ("address", "uint64", "uint48"):
        require(theory_list(theory, f"{prefix}_{width}_words") == guards[width], f"bridge {width} guard drift: {prefix}")
    signature = abi_signature(entry)
    kernel_selector = selector(signature)
    require(abi["selectors"][signature] == f"0x{kernel_selector:08x}", f"kernel ABI selector drift: {signature}")
    return {
        "struct": spec["struct"],
        "wordCount": count,
        "calldataLength": length,
        "tupleSignature": signature[len(spec["kernelFunction"]):],
        "words": words,
        "guards": guards,
    }


def entrypoint_selectors(shapes: dict[str, Any], theory: str, interface: str) -> dict[str, int]:
    result = {}
    for function, shape in {"executeRegulatoryAction": "action", "executeRegulatoryReversal": "reversal",
                            "executeERC7943Action": "action", "executeERC7943Reversal": "reversal"}.items():
        require(re.search(rf"function {function}\(TrustKernelTypes\.{shapes[shape]['struct']} calldata request\)",
                          interface) is not None, f"kernel interface lacks {function}")
        result[function] = selector(function + shapes[shape]["tupleSignature"])
    require(result["executeRegulatoryAction"] == theory_number(theory, "action_entrypoint_selector"), "action selector drift")
    require(result["executeRegulatoryReversal"] == theory_number(theory, "reversal_entrypoint_selector"), "reversal selector drift")
    require(result["executeERC7943Action"] == theory_number(theory, "native_route_action_selector"), "route selector drift")
    require(result["executeERC7943Reversal"] == theory_number(theory, "native_route_reversal_selector"), "route selector drift")
    require(theory_number(theory, "generic_dispatcher_input_selector") == GENERIC_DISPATCHER_SELECTOR, "dispatcher selector drift")
    return result


def dirty_values(guard: dict[str, Any]) -> list[tuple[str, int]]:
    if guard["kind"] == "enum":
        return [("first-out-of-range", guard["bound"]), ("uint8-maximum", 255), ("above-uint8", 256)]
    width = guard["width"]
    return [("lowest-dirty-bit", 1 << width), ("highest-bit", 1 << 255)]


def recipes_for(profile: str, entrypoint: str, shape_name: str, shape: dict[str, Any], lengths: dict[str, int]) -> list[dict[str, Any]]:
    recipes = []
    base = "ACTION-FREEZE" if shape_name == "action" else "REVERSAL-UNFREEZE"
    length = shape["calldataLength"]
    other = lengths["reversal" if shape_name == "action" else "action"]
    for label, total in (("selector-only", 4), ("one-word-short", length - 32), ("one-byte-short", length - 1),
                         ("one-byte-long", length + 1), ("one-word-long", length + 32), ("other-shape-length", other)):
        recipes.append({"class": "length", "variant": label, "calldataBytes": total, "word": None, "value": None,
                        "identifier": "recomputed", "domain": "kernel"})
    for word in shape["words"]:
        guard = word["guard"]
        if guard is None:
            continue
        values = dirty_values(guard)
        for label, value in values:
            recipes.append({"class": f"dirty-{guard['kind']}-word", "variant": label, "calldataBytes": length,
                            "word": word["word"], "value": hex(value), "identifier": "recomputed", "domain": "kernel"})
        label, value = values[0]
        for policy in ("stale", "recomputed"):
            recipes.append({"class": "ordering-probe", "variant": f"{guard['kind']}-word-with-{'stale-identifier' if policy == 'stale' else 'foreign-domain'}",
                            "calldataBytes": length, "word": word["word"], "value": hex(value),
                            "identifier": policy, "domain": "kernel" if policy == "stale" else "foreign"})
    recipes.append({"class": "nonzero-call-value", "variant": "one-wei", "calldataBytes": length, "word": None,
                    "value": hex(1), "identifier": "recomputed", "domain": "kernel"})
    recipes.append({"class": "well-formed-control", "variant": "unmodified-base", "calldataBytes": length,
                    "word": None, "value": None, "identifier": "recomputed", "domain": "kernel"})
    for recipe in recipes:
        recipe.update({"profile": profile, "entrypoint": entrypoint, "shape": shape_name, "base": base})
    return recipes


def build() -> tuple[dict[str, Any], str]:
    schema, abi = load_json(KERNEL_SCHEMA), load_json(KERNEL_ABI)
    theory = BRIDGE_THEORY.read_text(encoding="utf-8")
    interface = KERNEL_INTERFACE.read_text(encoding="utf-8")
    shapes = {name: shape_from_sources(name, schema, abi, theory) for name in SHAPES}
    selectors = entrypoint_selectors(shapes, theory, interface)
    lengths = {name: shape["calldataLength"] for name, shape in shapes.items()}
    typed_failure_selectors = theory_name_set(theory, "typed_failure_selectors")
    require(typed_failure_selectors == sorted(
        selector(abi_signature(item)) for item in abi["abi"] if item["type"] == "error"),
        "typed failure selectors of the bridge and the kernel ABI differ")
    recipes: list[dict[str, Any]] = []
    for profile in PROFILES:
        recipes.append({"class": "no-selector", "variant": "empty", "calldataBytes": 0, "word": None, "value": None,
                        "identifier": "none", "domain": "none", "profile": profile, "entrypoint": "none", "shape": None, "base": None})
        recipes.append({"class": "no-selector", "variant": "three-bytes", "calldataBytes": 3, "word": None, "value": None,
                        "identifier": "none", "domain": "none", "profile": profile, "entrypoint": "none", "shape": None, "base": None})
        recipes.append({"class": "unknown-selector", "variant": "generic-dispatcher-input", "calldataBytes": lengths["action"],
                        "word": None, "value": hex(GENERIC_DISPATCHER_SELECTOR), "identifier": "none", "domain": "kernel",
                        "profile": profile, "entrypoint": "none", "shape": "action", "base": "ACTION-FREEZE"})
        for entrypoint, shape_name in ENDPOINT_ENTRYPOINTS[profile].items():
            recipes += recipes_for(profile, entrypoint, shape_name, shapes[shape_name], lengths)
    for index, recipe in enumerate(recipes):
        recipe["id"] = f"{recipe['profile'].lower()}-{index:03d}"
    ordered = [{key: recipe[key] for key in ("id", "profile", "entrypoint", "shape", "base", "class", "variant",
                                             "calldataBytes", "word", "value", "identifier", "domain")}
               for recipe in recipes]
    document = {
        "schema": "trust12-tail-preparation-malformed-inputs-v1",
        "status": "PREPARED_NOT_CLOSED",
        "sources": [file_reference(path) for path in (KERNEL_SCHEMA, KERNEL_ABI, BRIDGE_THEORY, KERNEL_INTERFACE)],
        "profiles": {
            profile: {
                "endpoint": ENDPOINTS[profile],
                "typedEntrypoints": [{"function": name, "shape": shape, "selector": f"0x{selectors[name]:08x}"}
                                     for name, shape in ENDPOINT_ENTRYPOINTS[profile].items()],
            }
            for profile in PROFILES
        },
        "shapes": shapes,
        "decoderRule": (
            "A request to a typed entrypoint is in canonical form exactly when its selector is a typed entrypoint of "
            "the endpoint, its length equals the calldata length of that selector's shape, every enum word is below "
            "its bound, every address, uint64 and uint48 word fits its width, and the call carries zero value "
            "(decision 12). Identifier, domain, authority and time are kernel rules over a canonical request and "
            "never take it out of canonical form."
        ),
        "symbolicClasses": [
            {"class": "no-selector", "definition": "calldata shorter than four bytes"},
            {"class": "unknown-selector", "definition": "the first four bytes are not a selector of the endpoint"},
            {"class": "length", "definition": "a typed entrypoint selector with a calldata length other than the shape length"},
            {"class": "dirty-enum-word", "definition": "canonical length and an enum word at or above its bound"},
            {"class": "dirty-address-word", "definition": "canonical length and an address word at or above 2^160"},
            {"class": "dirty-uint64-word", "definition": "canonical length and a uint64 word at or above 2^64"},
            {"class": "dirty-uint48-word", "definition": "canonical length and a uint48 word at or above 2^48"},
            {"class": "nonzero-call-value", "definition": "canonical calldata of a typed entrypoint sent with a nonzero call value"},
        ],
        "probeControls": [
            {
                "class": "well-formed-control",
                "definition": "the unmodified base request of a typed entrypoint",
                "whyItIsProbed": (
                    "The control runs through the same recorder as every recipe and must be observed as a success "
                    "with at least one log and one committed storage write. A recorder that could not see an effect "
                    "would fail this control, so a quiet malformed observation is not an artifact of the recorder."
                ),
            }
        ],
        "expectedBehavior": {
            "outcome": "the call fails; it never succeeds",
            "returnedPayload": ("not specified (decision 12): empty data, one of the typed failures, or other data; "
                                "the probe records which one it observes"),
            "typedFailureSelectors": [f"0x{value:08x}" for value in typed_failure_selectors],
            "externalCalls": 0,
            "logs": 0,
            "netStateChange": "none; storage writes made before the revert, such as the reentrancy guard, are reverted",
        },
        "orderingProbeRationale": (
            "An ordering probe keeps one non-canonical word and adds a defect that a kernel rule reports as a typed "
            "failure. The request is outside canonical form regardless, and decision 12 leaves open which defect is "
            "detected first, so a typed failure conforms as long as the call fails without an external call, a log or "
            "a state change. A typed failure here records that a kernel rule reads the request before every bounded "
            "word is validated."
        ),
        "recipePolicies": {
            "identifier": {
                "recomputed": "the identifier word is recomputed over the mutated words, so only the malformed defect remains",
                "stale": "the identifier of the unmutated request is kept",
                "none": "no request is built",
            },
            "domain": {
                "kernel": "the kernel domain constant",
                "foreign": "the kernel domain with its last byte changed",
                "none": "no request is built",
            },
        },
        "recipes": ordered,
        "counts": {
            "recipes": len(ordered),
            "byProfile": {profile: sum(1 for recipe in ordered if recipe["profile"] == profile) for profile in PROFILES},
            "orderingProbes": sum(1 for recipe in ordered if recipe["class"] == "ordering-probe"),
        },
        "nonclaim": NONCLAIM,
    }
    return document, probe_table(ordered, selectors)


def probe_table(recipes: list[dict[str, Any]], selectors: dict[str, int]) -> str:
    functions = []
    for profile in PROFILES:
        rows = []
        for index, recipe in enumerate(recipes):
            if recipe["profile"] != profile:
                continue
            if recipe["class"] in {"no-selector", "length"}:
                kind = KIND_LENGTH
            elif recipe["class"] == "unknown-selector":
                kind = KIND_SELECTOR
            elif recipe["class"] == "nonzero-call-value":
                kind = KIND_VALUE
            elif recipe["class"] == "well-formed-control":
                kind = KIND_CONTROL
            else:
                kind = KIND_WORD
            policy = {"recomputed": POLICY_RECOMPUTE, "stale": POLICY_STALE, "none": 0}[recipe["identifier"]]
            if recipe["domain"] == "foreign":
                policy = POLICY_FOREIGN_DOMAIN
            value = int(recipe["value"], 16) if recipe["value"] else 0
            # Powers of two are written as shifts: a 41-digit hexadecimal literal reads as an address
            # to the compiler, and long decimals exceed the formatter's line width.
            literal = f"1 << {value.bit_length() - 1}" if value >= 256 and value & (value - 1) == 0 else str(value)
            rows.append(
                f"        r[{len(rows)}] = Recipe({index}, {ENTRYPOINT_CODES[recipe['entrypoint']]}, {kind}, "
                f"{recipe['word'] if recipe['word'] is not None else 0}, {literal}, "
                f"{recipe['calldataBytes']}, {policy});"
            )
        functions.append(
            f"    function {profile.lower()}Recipes() internal pure returns (Recipe[] memory r) {{\n"
            f"        r = new Recipe[]({len(rows)});\n" + "\n".join(rows) + "\n    }"
        )
    body = "\n\n".join(functions)
    return f"""// SPDX-License-Identifier: BSD-3-Clause
// GENERATED by scripts/trust12/tail-preparation/malformed_inputs.py from the malformed input catalog. DO NOT EDIT.
pragma solidity 0.8.36;

/// @notice Concrete malformed probe recipes of the three profiles.
/// @dev index is the position of the recipe in the malformed input catalog. entrypoint 1 action,
///      2 reversal, 3 route action, 4 route reversal, 0 none. kind 1 length, 2 word, 3 selector,
///      4 call value, 5 well-formed control. policy 1 recomputed identifier, 2 stale identifier,
///      3 foreign domain with a recomputed identifier, 0 no request.
library MalformedProbeRecipes {{
    struct Recipe {{
        uint16 index;
        uint8 entrypoint;
        uint8 kind;
        uint16 word;
        uint256 value;
        uint256 calldataBytes;
        uint8 policy;
    }}

    uint256 internal constant COUNT = {len(recipes)};
    bytes4 internal constant ACTION_SELECTOR = 0x{selectors['executeRegulatoryAction']:08x};
    bytes4 internal constant REVERSAL_SELECTOR = 0x{selectors['executeRegulatoryReversal']:08x};
    bytes4 internal constant ROUTE_ACTION_SELECTOR = 0x{selectors['executeERC7943Action']:08x};
    bytes4 internal constant ROUTE_REVERSAL_SELECTOR = 0x{selectors['executeERC7943Reversal']:08x};

{body}
}}
"""


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="verify the tracked copies instead of writing them")
    args = parser.parse_args(argv)
    document, table = build()
    write_or_check(DOCUMENT, dump_json(document), args.check)
    write_or_check(GENERATED_PROBE_TABLE, table, args.check)
    print(dump_json({"status": "PASS_MALFORMED_CATALOG_" + ("CHECKED" if args.check else "WRITTEN"),
                     "counts": document["counts"]}), end="")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except PreparationError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
