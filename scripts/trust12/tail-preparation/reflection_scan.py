#!/usr/bin/env python3
"""Scan the final sources and compiled layouts for every state write and every guard on the typed command paths.

The preservation and reflection condition asks that every guard and every state write on the typed command paths
be the consumer of an obligation or a listed runtime-only item with a reason, and that this reflection list be
produced by a machine scan of the final sources and compiled layouts rather than by review alone. This tool reads
the solc build information (abstract syntax trees and storage layouts) of a build of the exact product tree and:

* requires every implementation source of the build to be byte-identical to the current product source;
* compares the compiled storage layout of each of the seven profile runtimes with the state and receipt crosswalk:
  every compiled variable must be a storage reference of the crosswalk with the same slot, offset and type, and
  every storage reference of the crosswalk must be compiled;
* follows, from the typed command entrypoints of each endpoint, every internal and library call and every modifier,
  plus the entrypoints that a typed command reaches through an external call back into the endpoint (the exact-use
  route handlers of the Native endpoint and the balance callback of the Hook adapter);
* lists every state write on those paths (assignment, increment, decrement, delete, push and pop), following local
  storage pointers to the state variable they point into and storage parameters to the argument of every call site;
* lists every guard on those paths: every revert statement with the condition that leads to it, every require and
  assert, and every inline assembly block that reverts;
* lists, for every external or public function and the constructor of each runtime, the state variables it can
  write, and for every state variable the functions whose bodies write it;
* classifies every written state variable with the crosswalk (an abstract field or a runtime-only reason of the
  earlier central closure) or a storage disposition, and every guard with the final source consumer snippets of the
  central obligation ledger or a guard disposition. A Hook adapter guard inside a function whose source text is
  identical to the Partial adapter function of the same name takes the classification of that Partial guard; any
  other Hook guard needs its own disposition;
* checks the dispositions: every storage variable that the crosswalk leaves open has one, and the functions it
  names as writers are exactly the functions whose bodies write the variable; every ledger row and assumption that a
  disposition names exists; every guard disposition matches a scanned guard; every open item of the crosswalk has a
  disposition with the same text, and an item carried to a later gate names its receiving gate, owner, closure
  evidence and reopen condition;
* reviews the Hook adapter columns that the crosswalk derives from the Partial layout: for every such column, the
  functions whose bodies write it in the Hook adapter are compared with the Partial adapter functions of the same
  name, and every Hook writer with its own source text needs a disposition that pins the reviewed texts by hash.

It reports what it cannot classify instead of guessing. It reads stored files only and never runs the compiler.

Usage:
  reflection_scan.py --build-info FILE [FILE ...] --out FILE [--product-root DIR]
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Iterator

SCHEMA = "trust12-tail-preparation-reflection-scan-v1"
RUNTIMES = {
    "TrustToken": "implementation/src/TrustToken.sol",
    "ERC3643TrustAdapter": "implementation/src/profiles/ERC3643TrustAdapter.sol",
    "ProfileGovernor": "implementation/src/profiles/ProfileGovernor.sol",
    "ERC3643HookAdapter": "implementation/src/profiles/ERC3643HookAdapter.sol",
    "ERC3643HookGovernor": "implementation/src/profiles/ERC3643HookGovernor.sol",
    "ERC3643HookCompliance": "implementation/src/profiles/ERC3643HookCompliance.sol",
    "ERC3643HookFactory": "implementation/src/profiles/ERC3643HookFactory.sol",
}
ENDPOINTS = {
    "TrustToken": {
        "entries": ["executeRegulatoryAction", "executeRegulatoryReversal", "executeERC7943Action",
                    "executeERC7943Reversal"],
        "reentries": {"setFrozenTokens": "the exact-use route handler that executeERC7943Action and "
                                         "executeERC7943Reversal call on the endpoint itself",
                      "forcedTransfer": "the exact-use route handler that executeERC7943Action calls on the endpoint "
                                        "itself"},
    },
    "ERC3643TrustAdapter": {"entries": ["executeRegulatoryAction", "executeRegulatoryReversal"], "reentries": {}},
    "ERC3643HookAdapter": {
        "entries": ["executeRegulatoryAction", "executeRegulatoryReversal"],
        "reentries": {"onTokenBalanceChanged": "the balance callback that the bound Compliance module calls on the "
                                               "endpoint when a forced transfer of a typed command moves a balance"},
    },
}
TWIN = {"ERC3643HookAdapter": "ERC3643TrustAdapter"}
CROSSWALK = "evidence/trust12/runtime-link/tail-preparation/state-receipt-crosswalk-v1.json"
DISPOSITIONS = "evidence/trust12/runtime-link/tail-preparation/reflection-dispositions-v1.json"
LEDGERS = {"central": "evidence/end-to-end-refinement/obligation-ledger-v3.json",
           "trust12": "evidence/trust12/obligation-ledger.json"}
DERIVED = "DERIVED_BY_LAYOUT_IDENTITY"
OPEN = "OPEN"
# Open item dispositions; True marks an item carried to a later gate, which must name where and how it closes.
OPEN_ITEM_KINDS = {"AWAITS_FORMAL_READER": True, "NEEDS_DECISION": True, "RESOLVED_BY_SCAN": False,
                   "RESOLVED_BY_SOURCE": False, "RESOLVED_BY_FORMAL_READER": False, "NONCLAIM": False,
                   "ASSUMPTION": False, "RUNTIME_ONLY": False}
CARRY_FIELDS = ("receivingGate", "owner", "closureEvidence", "reopen")
REVIEWED = "REVIEWED"
NONCLAIM = ("A syntax scan of the final sources and a comparison of the compiled layouts. It lists writes and guards "
            "and matches them with recorded reasons, consumer snippets and dispositions; it does not prove that a "
            "guard is sound, that a listed reason is true or that a named ledger row covers the guard, and it does not "
            "discharge the preservation and reflection condition or the state and receipt identity condition.")


class ScanError(RuntimeError):
    """A fail-closed check of the reflection scan did not hold."""


def require(condition: object, message: str) -> None:
    if not condition:
        raise ScanError(message)


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def walk(node: Any) -> Iterator[dict[str, Any]]:
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from walk(value)
    elif isinstance(node, list):
        for item in node:
            yield from walk(item)


def one_line(text: str) -> str:
    return " ".join(text.split())


def normalized(text: str) -> str:
    return one_line(text).rstrip(";").strip()


def snippet_core(text: str) -> str:
    """A consumer snippet without the block punctuation of the line it was cut from: a leading closing brace, a
    leading else, a trailing opening brace and a trailing semicolon."""
    core = re.sub(r"^\}\s*(?:else\s*)?", "", normalized(text))
    return re.sub(r"\{$", "", core).strip()


@dataclass
class Build:
    nodes: dict[int, dict[str, Any]] = field(default_factory=dict)
    sources: dict[int, tuple[str, str]] = field(default_factory=dict)
    parents: dict[int, int] = field(default_factory=dict)
    layouts: dict[str, Any] = field(default_factory=dict)
    stale: set[str] = field(default_factory=set)
    file: str = ""

    def text(self, node: dict[str, Any]) -> str:
        start, length, index = (int(value) for value in node["src"].split(":"))
        return self.sources[index][1].encode("utf-8")[start:start + length].decode("utf-8")

    def line(self, node: dict[str, Any]) -> int:
        start, _, index = (int(value) for value in node["src"].split(":"))
        return self.sources[index][1].encode("utf-8")[:start].count(b"\n") + 1

    def path(self, node: dict[str, Any]) -> str:
        return self.sources[int(node["src"].split(":")[2])][0]


def load_builds(paths: list[Path], product: Path, relaxed: bool = False) -> dict[str, Build]:
    """One AST index per build-info file, keyed by the runtimes it compiles.

    By default every implementation source of every build must be byte-identical to the current product source. The
    relaxed mode, for dry runs on an older build only, takes a runtime from a build in which its own source is current
    and later requires every source that a scan reads to be current; it records the other differing sources."""
    builds: dict[str, Build] = {}
    for path in paths:
        data = json.loads(path.read_text(encoding="utf-8"))
        build = Build(file=hashlib.sha256(path.read_bytes()).hexdigest())
        for name, source in data["output"]["sources"].items():
            content = data["input"]["sources"][name]["content"]
            if name.startswith("implementation/src/"):
                if sha256_text(content) != sha256_text((product / name).read_text(encoding="utf-8")):
                    require(relaxed, f"build source differs from the product: {name}")
                    build.stale.add(name)
            build.sources[int(source["id"])] = (name, content)
            stack: list[tuple[Any, int | None]] = [(source["ast"], None)]
            while stack:
                node, parent = stack.pop()
                if isinstance(node, dict):
                    if "id" in node and "nodeType" in node:
                        build.nodes[node["id"]] = node
                        if parent is not None:
                            build.parents[node["id"]] = parent
                        parent = node["id"]
                    stack.extend((value, parent) for value in node.values())
                elif isinstance(node, list):
                    stack.extend((item, parent) for item in node)
        for name, source in RUNTIMES.items():
            output = data["output"].get("contracts", {}).get(source, {}).get(name)
            if output is not None:
                build.layouts[name] = output.get("storageLayout")
        for node in build.nodes.values():
            name = node.get("name")
            if (node["nodeType"] == "ContractDefinition" and name in RUNTIMES and name not in builds
                    and RUNTIMES[name] not in build.stale):
                builds[name] = build
    require(set(builds) == set(RUNTIMES), "the builds do not compile every runtime: " + str(sorted(builds)))
    return builds


def contract(build: Build, name: str) -> dict[str, Any]:
    found = [node for node in build.nodes.values() if node["nodeType"] == "ContractDefinition" and node["name"] == name]
    require(len(found) == 1, f"contract not unique: {name}")
    return found[0]


def implementation(build: Build, name: str, function: str | None) -> dict[str, Any] | None:
    """The implemented function or modifier of that name that a call in the runtime resolves to: the most derived
    definition with a body, else the only library function of that name. None when absent or overloaded."""
    for identifier in contract(build, name)["linearizedBaseContracts"]:
        found = [item for item in build.nodes[identifier]["nodes"]
                 if item["nodeType"] in ("FunctionDefinition", "ModifierDefinition")
                 and item.get("name") == function and item.get("body") is not None]
        if found:
            return found[0] if len(found) == 1 else None
    found = [item for node in build.nodes.values()
             if node["nodeType"] == "ContractDefinition" and node.get("contractKind") == "library"
             for item in node["nodes"] if item["nodeType"] == "FunctionDefinition"
             and item.get("name") == function and item.get("body") is not None]
    return found[0] if len(found) == 1 else None


def function_text(build: Build, name: str, function: str | None) -> str | None:
    definition = implementation(build, name, function)
    return None if definition is None else build.text(definition)


def root_declaration(build: Build, expression: dict[str, Any] | None) -> dict[str, Any] | None:
    while expression is not None:
        kind = expression.get("nodeType")
        if kind == "IndexAccess":
            expression = expression.get("baseExpression")
        elif kind == "MemberAccess":
            expression = expression.get("expression")
        elif kind == "Identifier":
            return build.nodes.get(expression.get("referencedDeclaration"))
        else:
            return None
    return None


@dataclass
class Trace:
    reached: dict[int, list[str]] = field(default_factory=dict)
    writes: list[dict[str, Any]] = field(default_factory=list)
    guards: list[dict[str, Any]] = field(default_factory=list)
    unresolved: list[dict[str, Any]] = field(default_factory=list)


def members(build: Build, name: str) -> tuple[dict[int, dict[str, Any]], dict[int, dict[str, Any]]]:
    definition = contract(build, name)
    bases = [build.nodes[identifier] for identifier in definition["linearizedBaseContracts"]]
    state = {item["id"]: item for base in bases for item in base["nodes"]
             if item["nodeType"] == "VariableDeclaration" and item.get("stateVariable")
             and not item.get("constant") and item.get("mutability") not in ("immutable", "constant")}
    callables = {item["id"]: item for base in bases for item in base["nodes"]
                 if item["nodeType"] in ("FunctionDefinition", "ModifierDefinition")}
    return state, callables


def trace(build: Build, name: str, starts: list[int]) -> Trace:
    """Every function, modifier, write and guard that the given functions of one runtime reach without an external call."""
    state, _ = members(build, name)
    result = Trace()
    queue = [(identifier, [build.nodes[identifier].get("name") or build.nodes[identifier].get("kind")])
             for identifier in starts]
    while queue:
        identifier, trail = queue.pop(0)
        if identifier in result.reached:
            continue
        result.reached[identifier] = trail
        function = build.nodes[identifier]
        for modifier in function.get("modifiers", []) or []:
            target = (modifier.get("modifierName") or {}).get("referencedDeclaration")
            if target in build.nodes and build.nodes[target]["nodeType"] == "ModifierDefinition":
                queue.append((target, trail + [build.nodes[target]["name"]]))
        for node in walk(function.get("body")):
            if node.get("nodeType") != "FunctionCall" or node.get("kind") != "functionCall":
                continue
            expression = node.get("expression") or {}
            target = build.nodes.get(expression.get("referencedDeclaration"))
            if target is None or target["nodeType"] != "FunctionDefinition" or target.get("body") is None:
                continue
            on_contract = (expression.get("nodeType") == "MemberAccess" and (expression.get("expression") or {})
                           .get("typeDescriptions", {}).get("typeString", "").startswith("contract "))
            if target.get("visibility") != "external" and not on_contract:
                queue.append((target["id"], trail + [target.get("name") or target.get("kind")]))
    pointers: dict[int, int | None] = {}
    parameter_writes: dict[int, set[int]] = {}
    for identifier in result.reached:
        for node in walk(build.nodes[identifier].get("body")):
            if node.get("nodeType") == "VariableDeclarationStatement":
                origin = root_declaration(build, node.get("initialValue")) if node.get("initialValue") else None
                for declaration in node.get("declarations") or []:
                    if declaration and declaration.get("storageLocation") == "storage":
                        pointers[declaration["id"]] = None if origin is None else origin["id"]
    for identifier in result.reached:
        function = build.nodes[identifier]
        for node in walk(function.get("body")):
            targets, kind = [], None
            if node.get("nodeType") == "Assignment":
                targets, kind = [node["leftHandSide"]], "assignment"
            elif node.get("nodeType") == "UnaryOperation" and node.get("operator") in ("++", "--", "delete"):
                targets, kind = [node["subExpression"]], "delete" if node["operator"] == "delete" else "increment"
            elif (node.get("nodeType") == "FunctionCall" and (node.get("expression") or {}).get("nodeType") == "MemberAccess"
                  and node["expression"].get("memberName") in ("push", "pop")
                  and "storage" in (node["expression"].get("expression") or {}).get("typeDescriptions", {})
                  .get("typeString", "")):
                targets, kind = [node["expression"]["expression"]], node["expression"]["memberName"]
            for target in targets:
                components = target.get("components") if target.get("nodeType") == "TupleExpression" else [target]
                for component in components or []:
                    declaration = None if component is None else root_declaration(build, component)
                    if declaration is None:
                        continue
                    variable = resolve_storage(declaration, state, pointers)
                    if variable == "PARAMETER":
                        parameter_writes.setdefault(identifier, set()).add(declaration["id"])
                    elif variable is None:
                        if declaration.get("storageLocation") == "storage" or declaration["id"] in pointers:
                            result.unresolved.append({"function": function.get("name"), "line": build.line(node),
                                                      "text": one_line(build.text(node))})
                    else:
                        result.writes.append({"variable": state[variable]["name"], "function": function.get("name"),
                                              "kind": kind, "line": build.line(node), "text": one_line(build.text(node))})
    for identifier in result.reached:
        function = build.nodes[identifier]
        for node in walk(function.get("body")):
            if node.get("nodeType") != "FunctionCall" or node.get("kind") != "functionCall":
                continue
            expression = node.get("expression") or {}
            callee = build.nodes.get(expression.get("referencedDeclaration"))
            if callee is None or not parameter_writes.get(callee["id"]):
                continue
            parameters = [item["id"] for item in (callee.get("parameters") or {}).get("parameters", [])]
            arguments = list(node.get("arguments") or [])
            if expression.get("nodeType") == "MemberAccess" and len(arguments) == len(parameters) - 1:
                arguments = [expression["expression"]] + arguments
            for parameter, argument in zip(parameters, arguments):
                if parameter not in parameter_writes[callee["id"]]:
                    continue
                declaration = root_declaration(build, argument)
                variable = None if declaration is None else resolve_storage(declaration, state, pointers)
                if variable in (None, "PARAMETER"):
                    result.unresolved.append({"function": function.get("name"), "line": build.line(node),
                                              "text": one_line(build.text(node))})
                else:
                    result.writes.append({"variable": state[variable]["name"], "function": function.get("name"),
                                          "kind": "through " + str(callee.get("name")), "line": build.line(node),
                                          "text": one_line(build.text(node))})
    for identifier in result.reached:
        function = build.nodes[identifier]
        for node in walk(function.get("body")):
            kind = node.get("nodeType")
            if kind == "RevertStatement":
                result.guards.append(guard_record(build, node, function, "revert"))
            elif (kind == "FunctionCall" and (node.get("expression") or {}).get("nodeType") == "Identifier"
                  and node["expression"].get("name") in ("require", "assert")):
                result.guards.append(guard_record(build, node, function, node["expression"]["name"]))
            elif kind == "InlineAssembly" and any(item.get("nodeType") == "YulFunctionCall"
                                                  and (item.get("functionName") or {}).get("name") == "revert"
                                                  for item in walk(node.get("AST"))):
                result.guards.append(guard_record(build, node, function, "assembly-revert"))
    result.guards.sort(key=lambda item: (item["line"], item["function"] or ""))
    result.writes.sort(key=lambda item: (item["line"], item["variable"]))
    return result


def resolve_storage(declaration: dict[str, Any], state: dict[int, dict[str, Any]],
                    pointers: dict[int, int | None]) -> int | str | None:
    if declaration["id"] in state:
        return declaration["id"]
    if declaration["id"] in pointers:
        return pointers[declaration["id"]] if pointers[declaration["id"]] in state else None
    if declaration.get("storageLocation") == "storage" and not declaration.get("stateVariable"):
        return "PARAMETER"
    return None


def guard_record(build: Build, node: dict[str, Any], function: dict[str, Any], kind: str) -> dict[str, Any]:
    """The guard and the statement that holds it: the if statement whose branch reverts, or the guard itself."""
    statement, parent, hops = node, build.parents.get(node["id"]), 0
    while parent is not None and hops < 4:
        candidate = build.nodes[parent]
        if candidate["nodeType"] == "IfStatement":
            statement = candidate
            break
        if candidate["nodeType"] in ("FunctionDefinition", "ModifierDefinition", "ForStatement", "WhileStatement"):
            break
        parent, hops = build.parents.get(parent), hops + 1
    return {"function": function.get("name"), "kind": kind, "line": build.line(node),
            "guard": one_line(build.text(node)), "statement": normalized(build.text(statement))}


def entry_ids(build: Build, name: str, functions: list[str]) -> list[int]:
    _, callables = members(build, name)
    found = []
    for entry in functions:
        matches = [item for item in callables.values() if item["nodeType"] == "FunctionDefinition"
                   and item.get("name") == entry and item.get("body") and item.get("visibility") in ("external", "public")]
        require(len(matches) == 1, f"{name}: entrypoint not unique: {entry}")
        found.append(matches[0]["id"])
    return found


def callable_ids(build: Build, name: str) -> list[tuple[str, int]]:
    """Every external or public function and the constructor of a runtime that has a body, in source order."""
    _, callables = members(build, name)
    result = []
    for item in sorted(callables.values(), key=lambda value: (build.path(value), build.line(value))):
        if item["nodeType"] != "FunctionDefinition" or item.get("body") is None:
            continue
        if item.get("kind") != "constructor" and item.get("visibility") not in ("external", "public"):
            continue
        result.append((item.get("name") or item.get("kind"), item["id"]))
    return result


def writers(build: Build, name: str) -> dict[str, list[str]]:
    """For every external or public function and the constructor of a runtime, the state variables it can write."""
    return {label: sorted({write["variable"] for write in trace(build, name, [identifier]).writes})
            for label, identifier in callable_ids(build, name)}


def write_sites(build: Build, name: str) -> list[dict[str, Any]]:
    """Every state write that an external or public function or the constructor of a runtime can reach, with the
    function or modifier whose body holds it."""
    return trace(build, name, [identifier for _, identifier in callable_ids(build, name)]).writes


def crosswalk_storage(crosswalk: dict[str, Any], name: str) -> dict[str, set[tuple[int, int, str]]]:
    """The storage references of one runtime in the crosswalk: abstract field columns and storage without one."""
    references: dict[str, set[tuple[int, int, str]]] = {}
    for row in crosswalk["stateFields"]:
        storage = (row["runtimes"].get(name) or {}).get("storage")
        if storage:
            references.setdefault(storage["label"], set()).add(
                (int(storage["slot"]), int(storage["offset"]), storage["type"]))
    for row in crosswalk["storageWithoutAbstractField"].get(name, []):
        references.setdefault(row["label"], set()).add((int(row["slot"]), int(row["offset"]), row["type"]))
    return references


def layout_problems(crosswalk: dict[str, Any], layouts: dict[str, Any],
                    declared: dict[str, set[str]]) -> tuple[list[str], dict[str, int]]:
    """Compare the compiled storage layout of every runtime with the storage references of the crosswalk and with
    the state variables that the syntax tree declares. A runtime that declares no state variable may have no layout
    in the build information."""
    problems, counts = [], {}
    for name in RUNTIMES:
        layout = layouts.get(name)
        if layout is None and not declared.get(name) and not crosswalk_storage(crosswalk, name):
            counts[name] = 0
            continue
        if not layout or "storage" not in layout:
            problems.append(f"{name}: the build holds no storage layout")
            continue
        if {item["label"] for item in layout["storage"]} != declared.get(name, set()):
            problems.append(f"{name}: the compiled layout and the declared state variables differ")
        compiled: dict[str, tuple[int, int, str]] = {}
        for item in layout["storage"]:
            if item["label"] in compiled:
                problems.append(f"{name}.{item['label']}: compiled twice")
            compiled[item["label"]] = (int(item["slot"]), int(item["offset"]),
                                       layout.get("types", {}).get(item["type"], {}).get("label", item["type"]))
        references = crosswalk_storage(crosswalk, name)
        for label, entries in sorted(references.items()):
            for entry in sorted(entries):
                if compiled.get(label) != entry:
                    problems.append(f"{name}.{label}: the crosswalk gives {entry}, the build {compiled.get(label)}")
        for label in sorted(set(compiled) - set(references)):
            problems.append(f"{name}.{label}: compiled, but the crosswalk does not list it")
        counts[name] = len(compiled)
    return problems, counts


def classify(crosswalk: dict[str, Any], dispositions: dict[str, Any], ledger: dict[str, Any], name: str,
             scan: Trace, same_text: Callable[[str, str, str | None], bool]) -> dict[str, Any]:
    abstract = {}
    for row in crosswalk["stateFields"]:
        column = row["runtimes"].get(name)
        if column and column.get("storage"):
            abstract[column["storage"]["label"]] = {"status": column["status"], "abstract": row["abstract"]}
    runtime_only = {row["label"]: row for row in crosswalk["storageWithoutAbstractField"].get(name, [])}
    disposed = {row["label"]: row for row in dispositions.get("storage", []) if row["runtime"] == name}
    variables: dict[str, Any] = {}
    for write in scan.writes:
        label = write["variable"]
        if label in abstract:
            verdict = {"class": "ABSTRACT_FIELD", "detail": abstract[label]["abstract"],
                       "column": abstract[label]["status"]}
        elif label in runtime_only and runtime_only[label]["status"] != OPEN:
            verdict = {"class": "RUNTIME_ONLY", "detail": runtime_only[label]["reflection"]}
        elif label in disposed:
            verdict = {"class": "RUNTIME_ONLY_BY_DISPOSITION", "detail": disposed[label]["reason"]}
        else:
            verdict = {"class": "UNCLASSIFIED", "detail": None}
        entry = variables.setdefault(label, {**verdict, "sites": []})
        entry["sites"].append({key: write[key] for key in ("function", "kind", "line", "text")})
    owner = TWIN.get(name, name)
    snippets = [(row["id"], snippet_core(consumer["snippet"])) for row in ledger["rows"]
                for consumer in row["finalSourceConsumers"] if consumer.get("path") == RUNTIMES[owner]]
    snippets = [(row, snippet) for row, snippet in snippets if len(snippet) >= 12]
    cited_functions: dict[str, set[str]] = {}
    for row, snippet in snippets:
        match = re.fullmatch(r"(_\w+)\(.*\)", snippet)
        if match:
            cited_functions.setdefault(match.group(1), set()).add(row)
    reviewed = {}
    for row in dispositions.get("guards", []):
        reviewed.setdefault((row["runtime"], row["function"], normalized(row["statement"])), row)
    twin = TWIN.get(name)
    guards, used = [], set()
    for guard in scan.guards:
        statement = guard["statement"]
        same_body = twin if twin and same_text(name, twin, guard["function"]) else None
        if twin and same_body is None:
            rows, keys = set(), [(name, guard["function"], statement)]
        else:
            rows = {row for row, snippet in snippets if snippet in statement or statement in snippet}
            rows |= cited_functions.get(guard["function"], set())
            keys = [(owner, guard["function"], statement), (name, guard["function"], statement)]
        key = next((item for item in keys if item in reviewed), None)
        disposition = None if key is None else reviewed[key]
        if rows:
            verdict = {"class": "LEDGER_CONSUMER", "rows": sorted(rows)}
        elif disposition is not None and disposition.get("rows"):
            verdict = {"class": "LEDGER_CONSUMER_BY_DISPOSITION", "rows": sorted(disposition["rows"]),
                       "ledger": disposition.get("ledger", "central")}
            used.add(key)
        elif disposition is not None and disposition.get("runtimeOnly"):
            verdict = {"class": "RUNTIME_ONLY_BY_DISPOSITION", "rows": [], "reason": disposition["runtimeOnly"]}
            used.add(key)
        else:
            verdict = {"class": "UNCLASSIFIED", "rows": []}
        guards.append({**guard, "sameBodyAs": same_body, **verdict})
    return {"variables": variables, "guards": guards, "used": used}


def row_problems(item: dict[str, Any], rows: dict[str, set[str]], where: str) -> list[str]:
    ledger = item.get("ledger", "central")
    if ledger not in rows:
        return [f"{where}: unknown ledger {ledger}"]
    return [f"{where}: no row {row} in the {ledger} ledger" for row in item.get("rows", []) if row not in rows[ledger]]


def hook_review(crosswalk: dict[str, Any], sites: dict[str, list[dict[str, Any]]], dispositions: dict[str, Any],
                text: Callable[[str, str | None], str | None]) -> tuple[list[dict[str, Any]], list[str]]:
    """Compare the writers of every Hook column that the crosswalk derives from the Partial layout with the Partial
    writers of the same name, and check the dispositions of the Hook writers that have their own source text."""
    columns, problems, needed = [], [], {}
    for hook, partial in TWIN.items():
        for row in crosswalk["stateFields"]:
            column = row["runtimes"].get(hook) or {}
            if column.get("status") != DERIVED:
                continue
            storage = column["storage"]
            twin_storage = (row["runtimes"].get(partial) or {}).get("storage") or {}
            same_layout = all(storage.get(key) == twin_storage.get(key) for key in ("label", "slot", "offset", "type"))
            if not same_layout:
                problems.append(f"{hook}.{storage['label']}: derived column without the same Partial storage reference")
            label = storage["label"]
            hook_writers = sorted({site["function"] for site in sites[hook] if site["variable"] == label})
            partial_writers = sorted({site["function"] for site in sites[partial] if site["variable"] == label})
            own = []
            for function in hook_writers:
                hook_text = text(hook, function)
                if hook_text is None or hook_text != text(partial, function):
                    own.append(function)
                    needed.setdefault((hook, function), set()).add(label)
            columns.append({"abstract": row["abstract"], "label": label, "sameLayoutAsPartial": same_layout,
                            "hookWriters": hook_writers, "partialWriters": partial_writers,
                            "writersWithOwnText": own})
    reviewed: dict[tuple[str, str], dict[str, Any]] = {}
    for item in dispositions.get("hookColumnWriters", []):
        key = (item["runtime"], item["function"])
        if key in reviewed:
            problems.append(f"Hook column writer disposition repeated: {key[1]}")
        reviewed[key] = item
    for key, labels in sorted(needed.items()):
        item = reviewed.get(key)
        if item is None:
            problems.append(f"{key[0]}.{key[1]} writes {sorted(labels)} with its own source text and has no disposition")
            continue
        if set(item.get("labels", [])) != labels:
            problems.append(f"{key[0]}.{key[1]}: the disposition names {sorted(item.get('labels', []))}, "
                            f"the scan finds {sorted(labels)}")
        current = text(key[0], key[1])
        if current is None or item.get("textSha256") != sha256_text(current):
            problems.append(f"{key[0]}.{key[1]}: the reviewed source text changed")
        partial_function = item.get("partialFunction")
        partial_text = None if partial_function is None else text(TWIN[key[0]], partial_function)
        if (partial_function is None) != (item.get("partialTextSha256") is None) or (
                partial_function is not None and (partial_text is None
                                                  or item.get("partialTextSha256") != sha256_text(partial_text))):
            problems.append(f"{key[0]}.{key[1]}: the reviewed Partial counterpart changed")
        if not item.get("difference") or not item.get("reason"):
            problems.append(f"{key[0]}.{key[1]}: the disposition gives no difference or reason")
    for key in sorted(set(reviewed) - set(needed)):
        problems.append(f"Hook column writer disposition matches no Hook writer with its own text: {key[1]}")
    return columns, problems


def disposition_problems(crosswalk: dict[str, Any], dispositions: dict[str, Any], rows: dict[str, set[str]],
                         assumptions: set[str], sites: dict[str, list[dict[str, Any]]],
                         used: set[tuple[str, str, str]], hook_problems: list[str]) -> list[str]:
    problems = []
    open_rows = {(name, row["label"]): row for name, items in crosswalk["storageWithoutAbstractField"].items()
                 for row in items if row["status"] == OPEN}
    seen = set()
    for item in dispositions.get("storage", []):
        key = (item["runtime"], item["label"])
        where = f"storage {key[0]}.{key[1]}"
        if key in seen:
            problems.append(f"{where}: disposition repeated")
            continue
        seen.add(key)
        row = open_rows.get(key)
        if row is None:
            problems.append(f"{where}: the crosswalk does not leave this variable open")
            continue
        if item.get("slot") != row["slot"]:
            problems.append(f"{where}: slot {item.get('slot')} but the crosswalk gives {row['slot']}")
        if not item.get("reason"):
            problems.append(f"{where}: no reason")
        assigned, cleared = set(item.get("assignedBy", [])), set(item.get("clearedBy", []))
        found = [site for site in sites.get(key[0], []) if site["variable"] == key[1]]
        actual = {site["function"] for site in found}
        if actual != assigned | cleared:
            problems.append(f"{where}: written by {sorted(actual)}, the disposition names {sorted(assigned | cleared)}")
        for site in found:
            if site["function"] in cleared - assigned and site["kind"] != "delete":
                problems.append(f"{where}: {site['function']} is named as clearing it but writes {site['text']}")
            if site["function"] in assigned - cleared and site["kind"] == "delete":
                problems.append(f"{where}: {site['function']} is named as assigning it but deletes it")
        problems += row_problems(item, rows, where)
    for key in sorted(set(open_rows) - seen):
        problems.append(f"storage {key[0]}.{key[1]}: open in the crosswalk and without a disposition")
    for item in dispositions.get("guards", []):
        key = (item["runtime"], item["function"], normalized(item["statement"]))
        where = f"guard {key[0]}.{key[1]}: {key[2][:90]}"
        if key not in used:
            problems.append(f"{where}: the disposition matches no unclassified scanned guard")
        if item.get("rows"):
            problems += row_problems(item, rows, where)
        elif not item.get("runtimeOnly"):
            problems.append(f"{where}: neither ledger rows nor a runtime-only reason")
    texts, items = crosswalk["openItems"], dispositions.get("openItems", [])
    if len(items) != len(texts):
        problems.append(f"{len(texts)} open items in the crosswalk, {len(items)} dispositions")
    by_index = {item.get("index"): item for item in items}
    for index, text in enumerate(texts):
        item = by_index.get(index)
        where = f"open item {index}"
        if item is None:
            problems.append(f"{where}: no disposition")
            continue
        if item.get("text") != text:
            problems.append(f"{where}: the disposition quotes another text than the crosswalk")
        kind = item.get("disposition")
        if kind not in OPEN_ITEM_KINDS:
            problems.append(f"{where}: unknown disposition {kind}")
            continue
        if not item.get("detail"):
            problems.append(f"{where}: no detail")
        if OPEN_ITEM_KINDS[kind]:
            missing = [name for name in CARRY_FIELDS if not (item.get("carryOver") or {}).get(name)]
            if missing:
                problems.append(f"{where}: carried without {', '.join(missing)}")
        if kind == "ASSUMPTION" and item.get("assumption") not in assumptions:
            problems.append(f"{where}: no assumption {item.get('assumption')} in the central ledger")
        if kind == "RESOLVED_BY_SCAN" and hook_problems:
            problems.append(f"{where}: resolved by the scan, but the Hook column review has open problems")
    return problems


def review_pending(dispositions: dict[str, Any]) -> int:
    count = 0 if dispositions.get("status") == REVIEWED else 1
    for section in ("storage", "guards", "hookColumnWriters", "openItems"):
        count += sum(1 for item in dispositions.get(section, []) if item.get("review"))
    return count


def build_report(product: Path, paths: list[Path], relaxed: bool = False) -> dict[str, Any]:
    builds = load_builds(paths, product, relaxed)
    crosswalk = load(product / CROSSWALK)
    path = product / DISPOSITIONS
    dispositions = load(path) if path.is_file() else {}
    central = load(product / LEDGERS["central"])
    profile = load(product / LEDGERS["trust12"])
    rows = {"central": {row["id"] for row in central["rows"]},
            "trust12": {row["id"] for row in profile["obligations"]}}
    assumptions = {item["id"] for item in central["assumptions"]}

    def text(name: str, function: str | None) -> str | None:
        return function_text(builds[name], name, function)

    def same_text(name: str, twin: str, function: str | None) -> bool:
        own = text(name, function)
        return own is not None and own == text(twin, function)

    declared = {name: {item["name"] for item in members(builds[name], name)[0].values()} for name in RUNTIMES}
    problems, layout_counts = layout_problems(crosswalk, {name: builds[name].layouts.get(name) for name in RUNTIMES},
                                              declared)
    endpoints, used = {}, set()
    for name, spec in ENDPOINTS.items():
        build = builds[name]
        scan = trace(build, name, entry_ids(build, name, spec["entries"] + list(spec["reentries"])))
        read = {build.path(build.nodes[identifier]) for identifier in scan.reached}
        require(not read & build.stale, f"{name}: the scan reads sources that differ from the product: "
                + str(sorted(read & build.stale)))
        classified = classify(crosswalk, dispositions, central, name, scan, same_text)
        used |= classified["used"]
        reached = sorted({build.nodes[identifier].get("name") or build.nodes[identifier].get("kind")
                          for identifier in scan.reached})
        guards = classified["guards"]
        counts = {
            "reachedFunctions": len(reached),
            "writtenVariables": len(classified["variables"]),
            "unclassifiedVariables": sorted(label for label, item in classified["variables"].items()
                                            if item["class"] == "UNCLASSIFIED"),
            "guards": len(guards),
            "guardClasses": {kind: sum(1 for item in guards if item["class"] == kind)
                             for kind in ("LEDGER_CONSUMER", "LEDGER_CONSUMER_BY_DISPOSITION",
                                          "RUNTIME_ONLY_BY_DISPOSITION", "UNCLASSIFIED")},
            "unresolvedWrites": len(scan.unresolved),
        }
        problems += [f"{name}: unclassified write of {label}" for label in counts["unclassifiedVariables"]]
        problems += [f"{name}.{item['function']} line {item['line']}: unclassified guard {item['statement'][:90]}"
                     for item in guards if item["class"] == "UNCLASSIFIED"]
        problems += [f"{name}.{item['function']} line {item['line']}: write through an unresolved storage reference"
                     for item in scan.unresolved]
        endpoints[name] = {"source": RUNTIMES[name], "entries": spec["entries"], "reentries": spec["reentries"],
                           "reachedFunctions": reached, "variables": classified["variables"], "guards": guards,
                           "unresolvedWrites": scan.unresolved, "counts": counts}
    sites, runtime_writers, written_by = {}, {}, {}
    for name in RUNTIMES:
        build = builds[name]
        require(RUNTIMES[name] not in build.stale, f"{name}: runtime source differs from the product")
        sites[name] = write_sites(build, name)
        runtime_writers[name] = writers(build, name)
        written_by[name] = {label: sorted({site["function"] for site in sites[name] if site["variable"] == label})
                            for label in sorted({site["variable"] for site in sites[name]})}
    columns, hook_problems = hook_review(crosswalk, sites, dispositions, text)
    problems += hook_problems
    problems += disposition_problems(crosswalk, dispositions, rows, assumptions, sites, used, hook_problems)
    pending = review_pending(dispositions)
    classification = ("SCANNED_WITH_OPEN_ITEMS" if problems else
                      "SCANNED_CLASSIFIED_PENDING_REVIEW" if pending else "SCANNED_ALL_CLASSIFIED")
    return {"schema": SCHEMA,
            "status": "SCANNED_DRY_RUN_RELAXED" if relaxed else classification,
            "classification": classification,
            "buildInfoSha256": sorted({builds[name].file for name in RUNTIMES}),
            "staleSourcesOutsideTheScan": sorted({item for name in RUNTIMES for item in builds[name].stale}),
            "dispositions": {"present": bool(dispositions), "status": dispositions.get("status"),
                             "sha256": hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None,
                             "reviewPending": pending},
            "compiledLayoutVariables": layout_counts,
            "endpoints": endpoints, "hookColumns": columns, "writtenBy": written_by,
            "runtimeWriters": runtime_writers, "problems": problems, "nonclaim": NONCLAIM}


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--product-root", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--build-info", type=Path, nargs="+", required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--relaxed-dry-run", action="store_true",
                        help="accept an older build whose differing sources the scan does not read; never for evidence")
    args = parser.parse_args(argv)
    report = build_report(args.product_root.resolve(), args.build_info, args.relaxed_dry_run)
    with args.out.open("x", encoding="utf-8", newline="\n") as handle:
        handle.write(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"status": report["status"], "classification": report["classification"],
                      "reviewPending": report["dispositions"]["reviewPending"],
                      "compiledLayoutVariables": report["compiledLayoutVariables"],
                      "endpoints": {name: item["counts"] for name, item in report["endpoints"].items()},
                      "problems": report["problems"][:40], "problemCount": len(report["problems"])}, indent=2))
    return 1 if report["problems"] else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except (ScanError, OSError, ValueError, KeyError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
