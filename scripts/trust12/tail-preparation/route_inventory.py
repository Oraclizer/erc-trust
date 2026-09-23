#!/usr/bin/env python3
"""Enumerate and classify every public entrypoint of every TRUST 1.2 profile runtime.

Route exhaustiveness asks that every public, external, inherited, governance and profile
entrypoint belong to an abstract operation or to an explicit path outside the runtime-link
relation. This tool enumerates the selectors of the seven profile runtimes from the tracked
bridge artifacts of the runtime binding, recomputes every selector from the ABI, compares the
Native and Partial sets with the route tables that the formal runtime bridge fixes, and records a
disposition per selector:

* IN_RUNTIME_LINK_DOMAIN: a typed command entrypoint; its executions are the domain of the 27 cells
  and of the malformed branch.
* OUTSIDE_NON_MUTATING: a view or pure function; the compiler forbids state changes in it.
* OUTSIDE_REQUIRES_DISPOSITION: a state-changing entrypoint that is not a typed command; the central
  closure has to show why it cannot change regulated state, or bring it into the model.
* UNCLASSIFIED: no normative route class exists yet. A proposed class is recorded only when an
  identical selector is classified on the corresponding legacy runtime, and it is marked as proposed.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Any

from tail_common import (
    NONCLAIM, OUTPUT, PROFILE_RUNTIMES, ROOT, PreparationError, abi_signature, dump_json, file_reference,
    load_json, require, selector, write_or_check,
)

DOCUMENT = OUTPUT / "route-inventory-v1.json"
BRIDGE_THEORY = ROOT / "formal/isabelle/ERC_TRUST/TRUST_Runtime_Bridge_Generated.thy"
MALFORMED = OUTPUT / "malformed-inputs-v1.json"
BINDING = {"Native": "native", "Partial": "erc3643-partial", "Hook": "erc3643-hook"}
THEORY_TABLES = {"TrustToken": "native_routes", "ERC3643TrustAdapter": "profile_adapter_routes",
                 "ProfileGovernor": "profile_governor_routes"}
# A Hook runtime inherits a proposal only from the legacy runtime it was derived from.
LEGACY_OF = {"ERC3643HookAdapter": "ERC3643TrustAdapter", "ERC3643HookGovernor": "ProfileGovernor"}
IN_DOMAIN = {"Route_Kernel_Command", "Route_Native_Exact_Use"}
NON_MUTATING = {"view", "pure"}


def theory_routes(text: str, name: str) -> dict[int, str]:
    match = re.search(rf'definition {name} :: "\(nat \\<times> trust_route_class\) list" where\s+"{name} =\s*\[(.*?)\]"',
                      text, re.DOTALL)
    require(match is not None, f"route table missing from the formal bridge: {name}")
    pairs = re.findall(r"\((\d+),\s*(Route_[A-Za-z0-9_]+)\)", match.group(1))
    require(pairs, f"route table is empty: {name}")
    routes = {int(value): route for value, route in pairs}
    require(len(routes) == len(pairs), f"route table repeats a selector: {name}")
    return routes


def entries(profile: str) -> list[dict[str, Any]]:
    path = ROOT / "evidence/runtime-binding-v3" / BINDING[profile] / "bridge-artifacts.json"
    items = load_json(path)
    require([item["contract"] for item in items] == list(PROFILE_RUNTIMES[profile]), f"{profile}: runtime set drift")
    return items


def functions(entry: dict[str, Any]) -> list[dict[str, Any]]:
    name = entry["contract"]
    require(not any(item["type"] in {"receive", "fallback"} for item in entry["abi"]),
            f"{name}: a receive or fallback function exists and must be classified")
    result = []
    for item in (item for item in entry["abi"] if item["type"] == "function"):
        signature = abi_signature(item)
        value = selector(signature)
        compiled = entry["methodIdentifiers"].get(signature)
        require(compiled is not None and int(compiled, 16) == value, f"{name}: selector drift for {signature}")
        result.append({"signature": signature, "selector": f"0x{value:08x}", "decimal": value,
                       "stateMutability": item["stateMutability"]})
    require(len(result) == len(entry["methodIdentifiers"]), f"{name}: method identifier set drift")
    require(len({item["decimal"] for item in result}) == len(result), f"{name}: selector collision")
    return sorted(result, key=lambda item: item["decimal"])


def disposition(route_class: str | None, mutability: str) -> str:
    if route_class in IN_DOMAIN:
        return "IN_RUNTIME_LINK_DOMAIN"
    if mutability in NON_MUTATING:
        return "OUTSIDE_NON_MUTATING"
    if route_class is None:
        return "UNCLASSIFIED"
    return "OUTSIDE_REQUIRES_DISPOSITION"


def build() -> dict[str, Any]:
    theory = BRIDGE_THEORY.read_text(encoding="utf-8")
    tables = {contract: theory_routes(theory, name) for contract, name in THEORY_TABLES.items()}
    malformed = load_json(MALFORMED)
    runtimes, classified_by_contract = [], {}
    for profile in PROFILE_RUNTIMES:
        for entry in entries(profile):
            name = entry["contract"]
            table = tables.get(name)
            routes = []
            for function in functions(entry):
                route_class, basis, proposed = None, "no normative route class", None
                if table is not None:
                    route_class = table.get(function["decimal"])
                    require(route_class is not None, f"{name}: selector {function['selector']} missing from the formal route table")
                    basis = "formal runtime bridge route table"
                elif name in LEGACY_OF and function["decimal"] in tables[LEGACY_OF[name]]:
                    proposed = tables[LEGACY_OF[name]][function["decimal"]]
                    basis = f"proposed from the identical selector of {LEGACY_OF[name]}; not reviewed"
                routes.append({**function, "routeClass": route_class, "proposedClass": proposed, "basis": basis,
                               "disposition": disposition(route_class, function["stateMutability"]),
                               "inRuntimeLinkDomainIfAccepted": (route_class or proposed) in IN_DOMAIN})
            if table is not None:
                require({route["decimal"] for route in routes} == set(table),
                        f"{name}: compiled selectors and the formal route table differ")
            classified_by_contract[name] = routes
            runtimes.append({"profile": profile, "contract": name, "routes": routes, "summary": {
                "selectors": len(routes),
                "inRuntimeLinkDomain": sum(route["disposition"] == "IN_RUNTIME_LINK_DOMAIN" for route in routes),
                "outsideNonMutating": sum(route["disposition"] == "OUTSIDE_NON_MUTATING" for route in routes),
                "outsideRequiresDisposition": sum(route["disposition"] == "OUTSIDE_REQUIRES_DISPOSITION" for route in routes),
                "unclassified": sum(route["disposition"] == "UNCLASSIFIED" for route in routes),
            }})
    for profile, data in malformed["profiles"].items():
        endpoint_routes = classified_by_contract[data["endpoint"]]
        typed = {entry["selector"] for entry in data["typedEntrypoints"]}
        domain = {route["selector"] for route in endpoint_routes if route["inRuntimeLinkDomainIfAccepted"]}
        require(typed == domain, f"{profile}: typed entrypoints of the malformed catalog and the route domain differ")
    unclassified = [f"{runtime['contract']}.{route['signature']}" for runtime in runtimes for route in runtime["routes"]
                    if route["disposition"] == "UNCLASSIFIED"]
    requires = [f"{runtime['contract']}.{route['signature']}" for runtime in runtimes for route in runtime["routes"]
                if route["disposition"] == "OUTSIDE_REQUIRES_DISPOSITION"]
    return {
        "schema": "trust12-tail-preparation-route-inventory-v1",
        "status": "PREPARED_NOT_CLOSED",
        "sources": [file_reference(BRIDGE_THEORY), file_reference(MALFORMED)] + [
            file_reference(ROOT / "evidence/runtime-binding-v3" / BINDING[profile] / "bridge-artifacts.json")
            for profile in PROFILE_RUNTIMES],
        "dispositions": {
            "IN_RUNTIME_LINK_DOMAIN": "typed command entrypoint; its executions are the domain of the cells and of the malformed branch",
            "OUTSIDE_NON_MUTATING": "view or pure function; the compiler forbids state changes in it (compiler correctness stays a trusted assumption)",
            "OUTSIDE_REQUIRES_DISPOSITION": "state-changing entrypoint outside the typed commands; the central closure must justify or model it",
            "UNCLASSIFIED": "state-changing entrypoint without a normative route class",
        },
        "unmatchedSelectors": (
            "A selector outside a runtime's list reaches no function: none of the seven runtimes declares a receive "
            "or fallback function, so the compiler dispatcher reverts it with an empty payload. The malformed probe "
            "measures this path on the three endpoints with the generic dispatcher input selector."
        ),
        "runtimes": runtimes,
        "counts": {
            "runtimes": len(runtimes),
            "selectors": sum(len(runtime["routes"]) for runtime in runtimes),
            "unclassifiedStateChanging": len(unclassified),
            "stateChangingOutsideTheTypedCommands": len(requires),
        },
        "openItems": [
            "Hook runtimes have no normative route class. Classes inherited from the legacy Partial runtimes are "
            "proposals only, and the Hook-only entrypoints (the balance-change callback of the adapter, the fresh seal "
            "of the governor and every entrypoint of the compliance module and the factory) need new classes.",
            "The pinned upstream ERC-3643 token of the Hook profile is a dependency, not one of these runtimes; its "
            "entrypoints are not enumerated here, although the adapter is its only agent.",
            "Every state-changing entrypoint outside the typed commands needs a disposition in the central closure: "
            "ERC-20 and ERC-7943 mutators, governance, seal and profile synchronisation routes.",
        ],
        "unclassifiedStateChanging": unclassified,
        "stateChangingOutsideTheTypedCommands": requires,
        "nonclaim": NONCLAIM,
    }


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    document = build()
    write_or_check(DOCUMENT, dump_json(document), args.check)
    print(dump_json({"status": "PASS_ROUTE_INVENTORY_" + ("CHECKED" if args.check else "WRITTEN"),
                     "counts": document["counts"]}), end="")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except PreparationError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
