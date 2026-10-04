#!/usr/bin/env python3
"""Enumerate, classify and dispose every public entrypoint of every TRUST 1.2 profile runtime.

Version 2 of the route inventory. Version 1 (`route_inventory.py`) stays unchanged; this tool adds:

* Normative classes for the four Hook runtimes. They come from the route class table of
  `spec/decisions/14-hook-route-classes.md`, which `render-classes` turns into
  `spec/generated/hook-route-classes-v1.json`. The formal runtime bridge keeps classifying the
  Native and Partial runtimes. The class of the identical selector on the Partial runtime a Hook
  runtime was derived from is reported next to the Hook class as a cross-check only; it is never
  used as the class.
* One disposition record for every state-changing route outside the typed commands, read from
  `evidence/trust12/runtime-link/tail-preparation/route-dispositions-v1.json`. Every reference of a
  record is checked against the tree: ledger rows and their status, quoted sentences of accepted
  decision records, statements inside tracked records, source lines with their exact occurrence
  counts, tests and their recorded results, and mutation receipts.
* A closure mode. It fails unless the Hook class record is accepted, every selector has a class
  and a disposition, no state-changing selector is unclassified, every disposition is justified by
  a CLOSED ledger row or an accepted decision record of its own runtime and executed on that
  runtime by a test that passed in a recorded run, with no recorded gap, and the recorded
  malformed probe shows an empty revert for a selector outside the dispatch list on every endpoint.

A test under `implementation/test` counts as executed when the recorded Foundry results of the
implementation suite list it as passed and bind the current implementation sources and tests. A
test under `scripts/trust12/tail-preparation/route-dispositions` counts as executed when a run of
`run_route_disposition_tests.py`, supplied to the build, lists it as passed, records the hash of the
current bytes of its file and compiled the current implementation sources and tests, which the run
records by the source root of the recorded Foundry results.

Commands:
  render-classes [--decision FILE] [--output FILE] [--check]
  build [--mode prepare|closure] [--decision FILE] [--classes FILE] [--dispositions FILE]
        [--malformed-receipt FILE] [--disposition-run FILE] [--output FILE] [--report FILE]

The tool never runs a prover or a compiler and writes only the files it is given.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Any

_TOOLS = os.environ.get("TRUST12_TAIL_TOOLS")
if _TOOLS:
    sys.path.insert(0, _TOOLS)

import route_inventory as v1  # noqa: E402
from tail_common import (  # noqa: E402
    OUTPUT, PROFILE_RUNTIMES, ROOT, PreparationError, canonical_text_sha256, dump_json, load_json, require,
    selector, sha256_bytes, sha256_file,
)

DECISION = ROOT / "spec/decisions/14-hook-route-classes.md"
CLASSES = ROOT / "spec/generated/hook-route-classes-v1.json"
DISPOSITIONS = OUTPUT / "route-dispositions-v1.json"
PROBE_SUMMARY = ROOT / "evidence/trust12/runtime-link/out-of-spec-probes-v1.json"
RECORDED_SUITE = ROOT / "evidence/foundry-results-v3.json"
ROUTE_TESTS = "scripts/trust12/tail-preparation/route-dispositions"
CLASSES_SCHEMA = "trust12-hook-route-classes-v1"
DISPOSITIONS_SCHEMA = "trust12-tail-preparation-route-dispositions-v1"
DOCUMENT_SCHEMA = "trust12-tail-preparation-route-inventory-v2"
RUN_SCHEMA = "trust12-tail-preparation-route-disposition-run-v1"
RUN_PASSED = "ROUTE_DISPOSITION_TESTS_PASSED"
NONCLAIM = (
    "Route inventory only. A closed inventory meets the acceptance criteria of the route-exhaustiveness "
    "condition for the tracked compiled artifacts and the recorded executions; a class names the role of an "
    "entrypoint and a disposition cites the evidence for it, and neither is a proof over every caller, state or "
    "input. It does not discharge the registered-scope central closure, any general runtime link or the "
    "independent Assurance, and it does not authorize a merge, a release or a deployment."
)

HOOK_RUNTIMES = PROFILE_RUNTIMES["Hook"]
COUNTERPART = dict(v1.LEGACY_OF)
FORMAL_TABLE_OF = dict(v1.THEORY_TABLES)
IN_DOMAIN = set(v1.IN_DOMAIN)
NON_MUTATING_ABI = {"view", "pure"}
PROFILE_OF = {contract: profile for profile, contracts in PROFILE_RUNTIMES.items() for contract in contracts}
ENDPOINTS = {"Native": "TrustToken", "Partial": "ERC3643TrustAdapter", "Hook": "ERC3643HookAdapter"}

# Mutability of the formal route classes. The datatype of the formal bridge must have exactly these
# constructors; a new constructor needs a decision about its mutability before the tool accepts it.
FORMAL_CLASS_MUTATES = {
    "Route_Kernel_Command": True, "Route_Kernel_View": False, "Route_Native_Exact_Use": True,
    "Route_ERC7943_Sensitive": True, "Route_ERC7943_View": False, "Route_ERC20_Mutator": True,
    "Route_ERC20_View": False, "Route_Governance": True, "Route_Immutable_View": False,
    "Route_Profile_Command": True, "Route_Profile_View": False, "Route_Seal_Command": True,
    "Route_Seal_View": False,
}
# A decision record is normative when its status line starts with one of these words.
ACCEPTED_STATUS = ("accepted", "implemented", "recorded", "frozen")

# Source files whose code a runtime executes. The Hook deployment library is internal and runs
# inside the endpoint constructor, so it belongs to the endpoint.
RUNTIME_FAMILY = {
    "TrustToken": ("implementation/src/TrustToken.sol",),
    "ERC3643TrustAdapter": ("implementation/src/profiles/ERC3643TrustAdapter.sol",),
    "ProfileGovernor": ("implementation/src/profiles/ProfileGovernor.sol",),
    "ERC3643HookAdapter": ("implementation/src/profiles/ERC3643HookAdapter.sol",
                           "implementation/src/profiles/ERC3643HookDeployment.sol"),
    "ERC3643HookGovernor": ("implementation/src/profiles/ERC3643HookGovernor.sol",),
    "ERC3643HookCompliance": ("implementation/src/profiles/ERC3643HookCompliance.sol",),
    "ERC3643HookFactory": ("implementation/src/profiles/ERC3643HookFactory.sol",),
}
# Contracts whose deployment in a test instantiates every runtime of the profile.
PROFILE_DEPLOYERS = {
    "Native": ("TrustToken",),
    "Partial": ("ERC3643TrustAdapter", "ProfileGovernor"),
    "Hook": ("ERC3643HookFactory", "ERC3643HookAdapter"),
}
CENTRAL_ENDPOINT_RUNTIMES = {
    "native": ("TrustToken",), "profileAdapter": ("ERC3643TrustAdapter",),
    "profileGovernor": ("ProfileGovernor",), "shared": ("TrustToken", "ERC3643TrustAdapter", "ProfileGovernor"),
}
DISPOSITION_KINDS = {
    "ORDINARY_TOKEN_OPERATION", "EXACT_USE_ROUTE", "GOVERNANCE_TRANSITION", "PROFILE_SYNCHRONISATION",
    "ONE_WAY_SEAL", "CONSTRUCTION_ONLY", "NEVER_SUCCEEDS", "BALANCE_CALLBACK", "COMPLIANCE_CALLBACK",
    "UNIT_CREATION",
}
COVERAGE = {"this runtime", "counterpart runtime", "abstract model"}
REFERENCE_TYPES = {"ledgerRow", "decision", "statement", "source", "test", "mutation"}
TEST_RUNS = {"recorded-foundry-suite", "route-disposition-run"}
# The tracked malformed probe summary hashes its inputs over these paths.
PROBE_INPUT_PATHS = ("implementation/src", "implementation/test", "vectors", "foundry.toml",
                     "scripts/trust12/tail-preparation/foundry", "scripts/trust12/derived-identifier-probe")
SKIPPED_PARTS = {"__pycache__"}
# The catalogued unknown-selector request of every endpoint: the generic dispatcher selector of the
# formal bridge followed by the calldata body of a FREEZE action request.
UNKNOWN_SELECTOR_BASE = "ACTION-FREEZE"
UNKNOWN_SELECTOR_BYTES = 644


# ---------------------------------------------------------------------------
# Paths and the files a build reads
# ---------------------------------------------------------------------------

def label(path: Path) -> str:
    """Product-relative path, or the bare file name for an input outside the product tree."""
    try:
        return path.resolve().relative_to(ROOT.resolve()).as_posix()
    except ValueError:
        return f"outside-product/{path.name}"


def product_file(relative_path: str) -> Path:
    require(isinstance(relative_path, str) and relative_path and not relative_path.startswith("/")
            and ":" not in relative_path and ".." not in Path(relative_path).parts,
            f"reference path leaves the product tree: {relative_path}")
    return ROOT / relative_path


class Reads:
    """Records every product file a build depends on, with its size and SHA-256."""

    def __init__(self) -> None:
        self.files: dict[str, dict[str, Any]] = {}

    def add(self, path: Path) -> Path:
        require(path.is_file(), f"missing input: {label(path)}")
        self.files[label(path)] = {"bytes": path.stat().st_size, "sha256": sha256_file(path)}
        return path

    def text(self, path: Path) -> str:
        return self.add(path).read_text(encoding="utf-8")

    def json(self, path: Path) -> Any:
        return load_json(self.add(path))

    def inventory(self) -> list[dict[str, Any]]:
        return [{"path": path, **item} for path, item in sorted(self.files.items())]


def tree_files(paths: tuple[str, ...]) -> list[str]:
    result = []
    for relative in paths:
        path = ROOT / relative
        if path.is_file():
            result.append(relative)
        elif path.is_dir():
            result += [item.relative_to(ROOT).as_posix() for item in path.rglob("*")
                       if item.is_file() and not SKIPPED_PARTS.intersection(item.parts)]
    return sorted(result)


def tab_root(paths: list[str]) -> str:
    """Root of the out-of-spec probe summary: SHA-256 over sorted 'path<TAB>sha256<LF>' lines."""
    return sha256_bytes("".join(sorted(f"{path}\t{sha256_file(ROOT / path)}\n" for path in paths)).encode("utf-8"))


def implementation_root() -> str:
    """Root of the recorded Foundry results: SHA-256 over 'sha256  path<LF>' lines in path order."""
    paths = sorted(tree_files(("implementation/src", "implementation/test")) + ["foundry.toml"])
    return sha256_bytes("".join(f"{sha256_file(ROOT / path)}  {path}\n" for path in paths).encode("utf-8"))


def canonical_sha256(value: Any) -> str:
    return sha256_bytes(json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode("utf-8"))


# ---------------------------------------------------------------------------
# Vocabulary and the Hook class record
# ---------------------------------------------------------------------------

def formal_vocabulary(theory: str) -> list[str]:
    match = re.search(r"datatype trust_route_class =\s*(.*?)\n\s*\n", theory, re.DOTALL)
    require(match is not None, "route class datatype missing from the formal bridge")
    constructors = [item.strip() for item in match.group(1).split("|")]
    require(all(re.fullmatch(r"Route_[A-Za-z0-9_]+", item) for item in constructors),
            "route class datatype has an unexpected constructor")
    require(set(constructors) == set(FORMAL_CLASS_MUTATES) and len(constructors) == len(FORMAL_CLASS_MUTATES),
            f"formal route classes differ from the declared mutability table: {sorted(set(constructors) ^ set(FORMAL_CLASS_MUTATES))}")
    return constructors


def generic_dispatcher_selector(theory: str) -> int:
    match = re.search(r'definition generic_dispatcher_input_selector :: nat where\s+'
                      r'"generic_dispatcher_input_selector = (\d+)"', theory)
    require(match is not None, "generic dispatcher input selector missing from the formal bridge")
    return int(match.group(1))


def _table(text: str, heading: str, header: list[str]) -> list[list[str]]:
    """Rows of the Markdown table that directly follows `heading`; every cell must be filled."""
    match = re.search(rf"^## {re.escape(heading)}\s*$", text, re.MULTILINE)
    require(match is not None, f"decision section missing: {heading}")
    lines = text[match.end():].lstrip("\n").splitlines()
    require(len(lines) >= 2, f"decision table missing: {heading}")
    cells = lambda line: [cell.strip() for cell in line.strip().strip("|").split("|")]  # noqa: E731
    require(cells(lines[0]) == header, f"decision table header drift: {heading}")
    require(all(re.fullmatch(r"-{3,}", cell) for cell in cells(lines[1])), f"decision table rule drift: {heading}")
    rows = []
    for line in lines[2:]:
        if not line.strip().startswith("|"):
            break
        row = cells(line)
        require(len(row) == len(header) and all(row), f"malformed decision table row: {line.strip()}")
        rows.append(row)
    require(rows, f"decision table is empty: {heading}")
    return rows


def _code(cell: str) -> str:
    match = re.fullmatch(r"`([^`]+)`", cell)
    require(match is not None, f"decision table cell is not one code span: {cell}")
    return match.group(1)


def status_line(text: str) -> str:
    status = re.search(r"^Status:\s*(\S[^\n]*)$", text, re.MULTILINE)
    require(status is not None, "decision status line missing")
    return status.group(1).strip()


def accepted(line: str) -> bool:
    return line.lower().startswith(ACCEPTED_STATUS)


def parse_decision(text: str) -> dict[str, Any]:
    line = status_line(text)
    spec_classes = []
    for name, mutating, definition in _table(text, "Spec classes", ["Class", "Mutating", "Definition"]):
        require(mutating in {"yes", "no"}, f"spec class mutability must be yes or no: {name}")
        spec_classes.append({"name": _code(name), "mutating": mutating == "yes", "definition": definition})
    rows = [{"runtime": _code(runtime), "signature": _code(signature), "selector": _code(value), "class": _code(klass)}
            for runtime, signature, value, klass in _table(text, "Route class table",
                                                           ["Runtime", "Signature", "Selector", "Class"])]
    return {"accepted": accepted(line), "statusLine": line, "specClasses": spec_classes, "rows": rows}


def render_classes(decision: Path, reads: Reads | None = None) -> dict[str, Any]:
    reads = reads or Reads()
    formal = formal_vocabulary(reads.text(v1.BRIDGE_THEORY))
    reads.add(decision)
    parsed = parse_decision(decision.read_text(encoding="utf-8"))
    names = [item["name"] for item in parsed["specClasses"]]
    require(len(set(names)) == len(names), "a spec class is declared twice")
    require(not set(names) & set(formal), f"a spec class shadows a formal class: {sorted(set(names) & set(formal))}")
    require(all(re.fullmatch(r"Route_[A-Za-z0-9_]+", name) for name in names), "spec class name format")
    vocabulary = set(formal) | set(names)
    runtimes: dict[str, list[dict[str, Any]]] = {name: [] for name in HOOK_RUNTIMES}
    for row in parsed["rows"]:
        require(row["runtime"] in runtimes, f"class table names a runtime outside the Hook profile: {row['runtime']}")
        value = selector(row["signature"])
        require(row["selector"] == f"0x{value:08x}", f"{row['runtime']}: selector does not match {row['signature']}")
        require(row["class"] in vocabulary, f"{row['runtime']}.{row['signature']}: class outside the vocabulary")
        runtimes[row["runtime"]].append({"signature": row["signature"], "selector": row["selector"], "class": row["class"]})
    for name, routes in runtimes.items():
        require(routes, f"class table has no row for {name}")
        require(len({route["selector"] for route in routes}) == len(routes), f"{name}: a selector repeats")
    return {
        "schema": CLASSES_SCHEMA,
        "status": "NORMATIVE" if parsed["accepted"] else "PROPOSED",
        "generatedFrom": {"path": label(decision), "canonicalSha256": canonical_text_sha256(decision),
                          "statusLine": parsed["statusLine"]},
        "formalVocabulary": {"source": label(v1.BRIDGE_THEORY), "datatype": "trust_route_class", "constructors": formal},
        "specClasses": parsed["specClasses"],
        "runtimes": [{"contract": name, "routes": sorted(runtimes[name], key=lambda item: item["selector"])}
                     for name in HOOK_RUNTIMES],
        "nonclaim": ("Generated from the route class table of the decision record. The classes say what role each "
                     "Hook entrypoint has; they do not discharge route exhaustiveness."),
    }


def load_classes(classes: Path, decision: Path, reads: Reads) -> dict[str, Any]:
    document = reads.json(classes)
    require(document.get("schema") == CLASSES_SCHEMA, "Hook class table schema drift")
    require(document == render_classes(decision, reads), "Hook class table is not the rendering of its decision record")
    return document


# ---------------------------------------------------------------------------
# Recorded executions
# ---------------------------------------------------------------------------

def probe_evidence(receipt_path: Path) -> dict[str, Any]:
    """The part of a malformed probe receipt that the inventory reads, with the hash of the whole receipt."""
    receipt = load_json(receipt_path)
    require(receipt.get("schema") == "trust12-tail-preparation-malformed-probe-receipt-v1",
            "malformed probe receipt schema drift")
    return {"sha256": sha256_file(receipt_path), "status": receipt.get("status"),
            "rows": [row for row in receipt["rows"] if row.get("class") == "unknown-selector"]}


def disposition_run(receipt_path: Path) -> dict[str, Any]:
    """The part of a disposition test run receipt that the inventory reads, with the hash of the receipt."""
    receipt = load_json(receipt_path)
    require(receipt.get("schema") == RUN_SCHEMA, "disposition test run receipt schema drift")
    return {"sha256": sha256_file(receipt_path), "status": receipt["status"], "forgeVersion": receipt["forgeVersion"],
            "implementationRootSha256": receipt["implementationRootSha256"], "sources": receipt["sources"],
            "tests": receipt["tests"]}


def declared_route_tests(reads: Reads) -> list[tuple[str, str]]:
    """Every (suite, test) pair the route test files declare, read from the current sources."""
    pairs = []
    for path in sorted((ROOT / ROUTE_TESTS).glob("*.t.sol")):
        text = reads.text(path)
        contracts = re.findall(r"^contract (\w+)", text, re.MULTILINE)
        require(len(contracts) == 1, f"{path.name}: a route test file declares exactly one contract")
        suite = f"{ROUTE_TESTS}/{path.name}:{contracts[0]}"
        pairs += [(suite, f"{name}()") for name in re.findall(r"function (test\w+)\(\) external", text)]
    return sorted(pairs)


class Executions:
    """Lazy reader of the recorded Foundry results and holder of the supplied disposition run."""

    def __init__(self, reads: Reads, run: dict[str, Any] | None) -> None:
        self.reads = reads
        self.run = run
        self._suite: dict[tuple[str, str], str] | None = None
        self.suiteCurrent = False
        self.runComplete = run is not None and run.get("status") == RUN_PASSED and sorted(
            (item["suite"], item["test"]) for item in run["tests"] if item["status"] == "Success"
        ) == declared_route_tests(reads) == sorted((item["suite"], item["test"]) for item in run["tests"])
        self.runCurrent = run is not None and run.get("implementationRootSha256") == implementation_root()

    def suite(self) -> dict[tuple[str, str], str]:
        if self._suite is None:
            recorded = self.reads.json(RECORDED_SUITE)
            require(recorded.get("sourceRootAlgorithm") == "sha256-raw-files-case-sensitive-path-order-v1",
                    "recorded Foundry results use another source root algorithm")
            self.suiteCurrent = recorded.get("status") == "PASS" and recorded.get("sourceRootSha256") == implementation_root()
            self._suite = {(item["suite"], item["test"]): item["status"] for item in recorded["testInventory"]}
        return self._suite

    def passed(self, run: str, suite: str, test: str, path: Path) -> tuple[bool, str | None]:
        """Whether the test passed in its recorded run, and the gap when it did not."""
        name = f"{test}()"
        if run == "recorded-foundry-suite":
            status = self.suite().get((suite, name))
            if not self.suiteCurrent:
                return False, "the recorded Foundry results do not bind the current implementation sources and tests"
            return status == "Success", None if status == "Success" else f"{suite} {name} did not pass in the recorded suite"
        if self.run is None:
            return False, "the disposition test run is not supplied"
        relative = label(path)
        if not self.runComplete:
            return False, "the disposition test run did not pass every declared route test"
        if not self.runCurrent:
            return False, "the disposition test run did not compile the current implementation sources and tests"
        if self.run["sources"].get(relative) != sha256_file(path):
            return False, f"the disposition test run executed other bytes of {relative}"
        status = next((item["status"] for item in self.run["tests"]
                       if item["suite"] == suite and item["test"] == name), None)
        return status == "Success", None if status == "Success" else f"{suite} {name} did not pass in the disposition run"


# ---------------------------------------------------------------------------
# References of the disposition records
# ---------------------------------------------------------------------------

class Ledgers:
    """Lazy reader of the obligation ledgers that disposition records cite."""

    def __init__(self) -> None:
        self._rows: dict[str, dict[str, dict[str, Any]]] = {}

    def row(self, ledger: str, row_id: str) -> dict[str, Any] | None:
        if ledger not in self._rows:
            document = load_json(product_file(ledger))
            rows = document.get("rows") or document.get("obligations")
            require(isinstance(rows, list), f"{ledger}: not an obligation ledger")
            self._rows[ledger] = {item["id"]: item for item in rows}
        return self._rows[ledger].get(row_id)


def ledger_row_runtimes(row: dict[str, Any]) -> tuple[str, ...]:
    """Runtimes a ledger row is about, from its endpoint field or its identifier."""
    if "endpoint" in row:
        return CENTRAL_ENDPOINT_RUNTIMES.get(row["endpoint"], ())
    identifier = row["id"]
    if identifier.startswith("HOOK-") or identifier == "RUNTIME-LINK-HOOK":
        return HOOK_RUNTIMES
    if identifier in {"RUNTIME-LINK-NATIVE", "NATIVE-SYMBOLIC-FREEZE"}:
        return PROFILE_RUNTIMES["Native"]
    if identifier == "RUNTIME-LINK-PARTIAL":
        return PROFILE_RUNTIMES["Partial"]
    return ()


def json_pointer(document: Any, pointer: str) -> Any:
    require(pointer.startswith("/"), f"JSON pointer must start with a slash: {pointer}")
    value = document
    for part in pointer[1:].split("/"):
        part = part.replace("~1", "/").replace("~0", "~")
        if isinstance(value, list):
            require(part.isdigit() and int(part) < len(value), f"JSON pointer does not resolve: {pointer}")
            value = value[int(part)]
        else:
            require(isinstance(value, dict) and part in value, f"JSON pointer does not resolve: {pointer}")
            value = value[part]
    return value


def deploys_profile(path: Path, text: str, runtime: str, reads: Reads) -> bool:
    """The test file, or a file it imports by a relative path, names a contract that deploys the profile."""
    deployers = (runtime,) + PROFILE_DEPLOYERS[PROFILE_OF[runtime]]
    texts = [text]
    for name in re.findall(r'import\s*\{[^}]*\}\s*from\s*"(\.{1,2}/[^"]+)";', text):
        imported = (path.parent / name).resolve()
        if imported.is_relative_to(ROOT.resolve()) and imported.is_file():
            texts.append(reads.text(imported))
    return any(name in body for body in texts for name in deployers)


def check_reference(item: dict[str, Any], runtime: str, ledgers: Ledgers, reads: Reads,
                    executions: Executions) -> dict[str, Any]:
    """Resolve one reference; return its verified form, or raise when it does not resolve."""
    kind = item.get("type")
    require(kind in REFERENCE_TYPES, f"{runtime}: unknown reference type {kind}")
    counterpart = COUNTERPART.get(runtime)
    if kind in {"ledgerRow", "decision", "statement"}:
        require(item.get("coverage") in COVERAGE, f"{runtime}: reference without a valid coverage: {item}")
    if kind == "ledgerRow":
        row = ledgers.row(item["ledger"], item["row"])
        require(row is not None, f"{runtime}: ledger row missing: {item['ledger']} {item['row']}")
        about = ledger_row_runtimes(row)
        if item["coverage"] == "this runtime":
            require(runtime in about, f"{runtime}: ledger row {item['row']} is not about this runtime")
        elif item["coverage"] == "counterpart runtime":
            require(counterpart is not None and counterpart in about,
                    f"{runtime}: ledger row {item['row']} is not about the counterpart runtime")
        else:
            require(not about, f"{runtime}: ledger row {item['row']} is about a runtime, not the abstract model")
        closed = row.get("status") == "CLOSED"
        return {**item, "status": row.get("status"), "rowSha256": canonical_sha256(row),
                "justifies": closed and item["coverage"] == "this runtime"}
    if kind == "decision":
        path = product_file(item["path"])
        require(path.resolve() != DECISION.resolve(), f"{runtime}: the class record cannot justify a disposition")
        text = reads.text(path)
        require(item["quote"] in text, f"{runtime}: quote not found in {item['path']}")
        subject = runtime if item["coverage"] == "this runtime" else counterpart
        names = (subject,) + RUNTIME_FAMILY.get(subject or "", ())
        mentions = subject is not None and any(name in text for name in names)
        require(item["coverage"] == "abstract model" or mentions,
                f"{runtime}: {item['path']} does not name the runtime its coverage claims")
        line = status_line(text)
        return {**item, "statusLine": line, "sha256": sha256_file(path),
                "justifies": item["coverage"] == "this runtime" and accepted(line)}
    if kind == "statement":
        path = product_file(item["path"])
        require(path.is_file(), f"{runtime}: record missing: {item['path']}")
        value = json_pointer(load_json(path), item["pointer"])
        require(isinstance(value, str) and item["quote"] in value,
                f"{runtime}: quote not found at {item['path']}{item['pointer']}")
        return {**item, "valueSha256": sha256_bytes(value.encode("utf-8")), "justifies": False}
    if kind == "source":
        path = product_file(item["path"])
        found = reads.text(path).count(item["snippet"])
        require(found == item["occurrences"],
                f"{runtime}: {item['path']} has {found} occurrences of a cited line, the record says {item['occurrences']}")
        return {**item, "sha256": sha256_file(path)}
    if kind == "test":
        require(set(item) == {"type", "runtime", "run", "suite", "test"}, f"{runtime}: test reference fields differ: {item}")
        require(item["runtime"] == runtime, f"{runtime}: test reference names another runtime")
        require(item["run"] in TEST_RUNS, f"{runtime}: unknown test run {item['run']}")
        file_part, _, contract = item["suite"].partition(":")
        require(contract and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", contract), f"{runtime}: suite without a contract")
        expected_prefix = "implementation/test/" if item["run"] == "recorded-foundry-suite" else ROUTE_TESTS + "/"
        require(file_part.startswith(expected_prefix) and file_part.endswith(".t.sol"),
                f"{runtime}: {file_part} is not a test file of the {item['run']}")
        path = product_file(file_part)
        text = reads.text(path)
        require(re.search(rf"\bcontract {re.escape(contract)}\b", text) is not None,
                f"{runtime}: test contract missing: {item['suite']}")
        require(re.search(rf"function {re.escape(item['test'])}\(", text) is not None,
                f"{runtime}: test function missing: {item['suite']} {item['test']}")
        require(deploys_profile(path, text, runtime, reads), f"{runtime}: {file_part} never deploys this profile")
        passed, gap = executions.passed(item["run"], item["suite"], item["test"], path)
        return {**item, "sha256": sha256_file(path), "executesThisRuntime": passed, "executionGap": gap}
    path = product_file(item["path"])
    receipt = reads.json(path)
    source = product_file(receipt["sourcePath"])
    require(receipt.get("status") == "KILLED", f"{runtime}: mutation not killed: {item['path']}")
    require(sha256_file(reads.add(source)) == receipt["originalSha256"], f"{runtime}: mutation receipt is stale: {item['path']}")
    return {**item, "sha256": sha256_file(path), "sourcePath": receipt["sourcePath"],
            "executesThisRuntime": receipt["sourcePath"] in RUNTIME_FAMILY[runtime]}


def check_record(record: dict[str, Any], routes: dict[str, dict[str, Any]], ledgers: Ledgers, reads: Reads,
                 executions: Executions) -> dict[str, Any]:
    require(set(record) <= {"route", "selector", "kind", "callers", "writes", "justification", "references",
                            "notes", "gaps"}, f"unexpected field in disposition {record.get('route')}")
    route = routes.get(record["route"])
    require(route is not None, f"disposition names no state-changing route outside the typed commands: {record['route']}")
    require(record["selector"] == route["selector"], f"{record['route']}: selector drift")
    require(record["kind"] in DISPOSITION_KINDS, f"{record['route']}: unknown disposition kind {record['kind']}")
    require(record["callers"] and record["writes"] and record["justification"], f"{record['route']}: incomplete record")
    runtime = record["route"].split(".", 1)[0]
    verified = [check_reference(item, runtime, ledgers, reads, executions) for item in record["references"]]
    justified = any(item.get("justifies") for item in verified)
    executed = any(item.get("executesThisRuntime") for item in verified)
    gaps = list(record.get("gaps", []))
    if not justified:
        gaps.append("machine check: no CLOSED ledger row or accepted decision record of this runtime justifies the disposition")
    if not executed:
        gaps.append("machine check: no execution of this route on its own runtime is recorded")
        gaps += [item["executionGap"] for item in verified if item.get("executionGap")]
    return {
        "route": record["route"], "selector": record["selector"], "kind": record["kind"],
        "justified": justified, "executedOnThisRuntime": executed,
        "gaps": sorted(set(gaps), key=gaps.index),
        "complete": justified and executed and not gaps,
        "references": verified,
    }


# ---------------------------------------------------------------------------
# Selectors that reach no function
# ---------------------------------------------------------------------------

UNMATCHED_RULE = (
    "No profile runtime declares a receive or fallback function, so the compiler dispatcher reverts a selector "
    "outside its list. The catalogued unknown-selector request of every endpoint must be the generic dispatcher "
    "selector of the formal bridge followed by the calldata body of a FREEZE action request, 644 bytes in all. The "
    "recorded malformed probe must show, for that request on every endpoint, a revert with an empty payload and no "
    "log, external call or committed write; its receipt must be the one the tracked probe summary binds, and the "
    "probe inputs of that summary must be the current files."
)


def unknown_selector_evidence(probe: dict[str, Any] | None, catalog: dict[str, Any], dispatcher: int,
                              runtimes: list[dict[str, Any]], reads: Reads) -> dict[str, Any]:
    summary = reads.json(PROBE_SUMMARY)
    expected = summary["malformedInput"]["receiptSha256"]
    inputs = summary["probeInputs"]
    require(list(inputs["paths"]) == list(PROBE_INPUT_PATHS), "probe input paths of the summary differ")
    current_root = tab_root(tree_files(PROBE_INPUT_PATHS))
    outside = all(f"0x{dispatcher:08x}" not in {route["selector"] for route in runtime["routes"]} for runtime in runtimes)
    base = {"rule": UNMATCHED_RULE, "dispatcherSelector": f"0x{dispatcher:08x}",
            "dispatcherSelectorOutsideEveryRuntime": outside, "expectedReceiptSha256": expected,
            "probeInputsRoot": {"recorded": inputs["rootSha256"], "current": current_root}}
    if probe is None:
        return {**base, "status": "RECEIPT_NOT_SUPPLIED", "profiles": {}}
    require(probe["sha256"] == expected, "malformed probe receipt is not the receipt the tracked probe summary binds")
    recipes = {item["id"]: item for item in catalog["recipes"] if item["class"] == "unknown-selector"}
    counted = summary["malformedInput"]["byProfileClassAndVerdict"]
    profiles = {}
    for profile in ENDPOINTS:
        rows = [row for row in probe["rows"] if row["profile"] == profile and row["class"] == "unknown-selector"]
        catalogued = sorted(key for key, item in recipes.items() if item["profile"] == profile)
        requests = bool(catalogued) and all(
            recipes[key].get("value") == f"0x{dispatcher:08x}" and recipes[key].get("base") == UNKNOWN_SELECTOR_BASE
            and recipes[key].get("calldataBytes") == UNKNOWN_SELECTOR_BYTES for key in catalogued)
        empty = [row for row in rows
                 if row["verdict"] == "CONFORMS" and row["observed"]["outcome"] == "untyped-empty-revert"
                 and row["observed"]["returnBytes"] == 0 and row["observed"]["logs"] == 0
                 and row["observed"]["committedWrites"] == 0 and row["observed"]["externalAccesses"] == 0]
        profiles[profile] = {
            "recipes": sorted(row["id"] for row in rows), "cataloguedRequestsHold": requests,
            "emptyReverts": len(empty),
            "holds": requests and bool(rows) and sorted(row["id"] for row in rows) == catalogued
            and len(empty) == len(rows) and counted.get(f"{profile}/unknown-selector/CONFORMS") == len(rows),
        }
    holds = (outside and inputs["rootSha256"] == current_root and probe.get("status") == "PROBE_RECORDED"
             and all(item["holds"] for item in profiles.values()))
    return {**base, "status": "VERIFIED" if holds else "FAILED", "receiptSha256": probe["sha256"], "profiles": profiles}


# ---------------------------------------------------------------------------
# Inventory
# ---------------------------------------------------------------------------

def build(mode: str, decision: Path = DECISION, classes_path: Path = CLASSES, dispositions_path: Path = DISPOSITIONS,
          probe: dict[str, Any] | None = None, run: dict[str, Any] | None = None) -> dict[str, Any]:
    require(mode in {"prepare", "closure"}, f"unknown mode {mode}")
    reads = Reads()
    for module in (Path(__file__), Path(v1.__file__), ROOT / "scripts/trust12/tail-preparation/tail_common.py",
                   ROOT / "scripts/trust12/tail-preparation/run_route_disposition_tests.py"):
        reads.add(module.resolve())
    theory = reads.text(v1.BRIDGE_THEORY)
    formal = formal_vocabulary(theory)
    tables = {contract: v1.theory_routes(theory, name) for contract, name in FORMAL_TABLE_OF.items()}
    classes = load_classes(classes_path, decision, reads)
    mutates = dict(FORMAL_CLASS_MUTATES)
    mutates.update({item["name"]: item["mutating"] for item in classes["specClasses"]})
    hook_table = {runtime["contract"]: {route["selector"]: route for route in runtime["routes"]}
                  for runtime in classes["runtimes"]}
    malformed = reads.json(v1.MALFORMED)
    for profile in PROFILE_RUNTIMES:
        reads.add(ROOT / "evidence/runtime-binding-v3" / v1.BINDING[profile] / "bridge-artifacts.json")

    runtimes, outside = [], {}
    for profile in PROFILE_RUNTIMES:
        for entry in v1.entries(profile):
            name = entry["contract"]
            table = tables.get(name)
            spec = hook_table.get(name)
            require(table is not None or spec is not None, f"{name}: no class source")
            compiled = v1.functions(entry)
            if table is not None:
                require({item["decimal"] for item in compiled} == set(table),
                        f"{name}: compiled selectors and the formal route table differ")
            else:
                require({item["selector"] for item in compiled} == set(spec),
                        f"{name}: compiled selectors and the Hook class table differ: "
                        f"{sorted({item['selector'] for item in compiled} ^ set(spec))}")
            routes = []
            for function in compiled:
                if table is not None:
                    route_class, source = table[function["decimal"]], "formal bridge route table"
                else:
                    row = spec[function["selector"]]
                    require(row["signature"] == function["signature"], f"{name}: signature drift at {function['selector']}")
                    route_class, source = row["class"], "Hook class table"
                mutable = function["stateMutability"] not in NON_MUTATING_ABI
                require(mutates[route_class] == mutable,
                        f"{name}.{function['signature']}: class {route_class} disagrees with ABI mutability "
                        f"{function['stateMutability']}")
                counterpart_class = None
                if name in COUNTERPART:
                    counterpart_class = tables[COUNTERPART[name]].get(function["decimal"])
                    require(counterpart_class is None or counterpart_class == route_class,
                            f"{name}.{function['signature']}: class differs from the counterpart class without a "
                            "recorded reason")
                if route_class in IN_DOMAIN:
                    disposition = "IN_RUNTIME_LINK_DOMAIN"
                elif not mutable:
                    disposition = "OUTSIDE_NON_MUTATING"
                else:
                    disposition = "OUTSIDE_REQUIRES_DISPOSITION"
                    outside[f"{name}.{function['signature']}"] = {"selector": function["selector"]}
                routes.append({**function, "routeClass": route_class, "classSource": source,
                               "counterpartClass": counterpart_class, "disposition": disposition})
            runtimes.append({"profile": profile, "contract": name, "routes": routes})

    for profile, data in malformed["profiles"].items():
        endpoint = next(runtime for runtime in runtimes if runtime["contract"] == data["endpoint"])
        domain = {route["selector"] for route in endpoint["routes"] if route["disposition"] == "IN_RUNTIME_LINK_DOMAIN"}
        typed = {item["selector"] for item in data["typedEntrypoints"]}
        require(domain == typed, f"{profile}: typed entrypoints of the malformed catalog and the route domain differ")
    for runtime in runtimes:
        if runtime["contract"] not in ENDPOINTS.values():
            require(not any(route["disposition"] == "IN_RUNTIME_LINK_DOMAIN" for route in runtime["routes"]),
                    f"{runtime['contract']}: a runtime other than the endpoint has a route in the runtime-link domain")

    dispositions = reads.json(dispositions_path)
    require(dispositions.get("schema") == DISPOSITIONS_SCHEMA, "disposition record schema drift")
    ledgers = Ledgers()
    executions = Executions(reads, run)
    records = [check_record(record, outside, ledgers, reads, executions) for record in dispositions["dispositions"]]
    named = [record["route"] for record in records]
    require(len(set(named)) == len(named), "a route has two disposition records")
    by_route = {record["route"]: record for record in records}
    for runtime in runtimes:
        for route in runtime["routes"]:
            record = by_route.get(f"{runtime['contract']}.{route['signature']}")
            if route["disposition"] == "OUTSIDE_REQUIRES_DISPOSITION" and record is not None:
                route["disposition"] = "OUTSIDE_DISPOSED" if record["complete"] else "OUTSIDE_DISPOSITION_OPEN"
                route["dispositionKind"] = record["kind"]
        runtime["summary"] = {state: sum(route["disposition"] == state for route in runtime["routes"]) for state in (
            "IN_RUNTIME_LINK_DOMAIN", "OUTSIDE_NON_MUTATING", "OUTSIDE_DISPOSED", "OUTSIDE_DISPOSITION_OPEN",
            "OUTSIDE_REQUIRES_DISPOSITION")}
        runtime["summary"]["selectors"] = len(runtime["routes"])

    unmatched = unknown_selector_evidence(probe, malformed, generic_dispatcher_selector(theory), runtimes, reads)
    all_routes = [(runtime["contract"], route) for runtime in runtimes for route in runtime["routes"]]
    criteria = [
        {"id": "hook-class-record-accepted", "holds": classes["status"] == "NORMATIVE",
         "detail": classes["generatedFrom"]["statusLine"]},
        {"id": "every-selector-has-a-normative-class", "holds": all(route["routeClass"] for _, route in all_routes),
         "detail": f"{len(all_routes)} selectors"},
        {"id": "every-state-changing-route-outside-the-typed-commands-is-disposed",
         "holds": all(route["disposition"] in {"IN_RUNTIME_LINK_DOMAIN", "OUTSIDE_NON_MUTATING", "OUTSIDE_DISPOSED"}
                      for _, route in all_routes),
         "detail": sorted(f"{contract}.{route['signature']}" for contract, route in all_routes
                          if route["disposition"] in {"OUTSIDE_DISPOSITION_OPEN", "OUTSIDE_REQUIRES_DISPOSITION"})},
        {"id": "unknown-selectors-revert-empty-on-every-endpoint", "holds": unmatched["status"] == "VERIFIED",
         "detail": unmatched["status"]},
    ]
    closed = all(item["holds"] for item in criteria)
    counts = {
        "runtimes": len(runtimes),
        "selectors": len(all_routes),
        "unclassifiedStateChanging": sum(not route["routeClass"] for _, route in all_routes),
        "stateChangingOutsideTheTypedCommands": len(outside),
        "dispositionRecords": len(records),
        "dispositionsComplete": sum(record["complete"] for record in records),
        "dispositionsOpen": sum(not record["complete"] for record in records),
    }
    return {
        "schema": DOCUMENT_SCHEMA,
        "status": "CLOSED_ROUTE_INVENTORY" if mode == "closure" and closed else "PREPARED_NOT_CLOSED",
        "mode": mode,
        "inputs": reads.inventory(),
        "recordedExecutions": {
            "implementationSuite": {"path": label(RECORDED_SUITE), "currentSourceRoot": executions.suiteCurrent},
            "dispositionRun": None if run is None else {"sha256": run["sha256"], "status": run["status"],
                                                        "currentImplementationRoot": executions.runCurrent},
        },
        "classSources": {
            "Native": "formal bridge route table native_routes",
            "Partial": "formal bridge route tables profile_adapter_routes and profile_governor_routes",
            "Hook": f"Hook class table, status {classes['status']}",
        },
        "vocabulary": {"formal": formal, "spec": [item["name"] for item in classes["specClasses"]]},
        "dispositionStates": {
            "IN_RUNTIME_LINK_DOMAIN": "typed command entrypoint; its executions are the domain of the cells and of the malformed branch",
            "OUTSIDE_NON_MUTATING": "view or pure function; the compiler forbids state changes in it (compiler correctness stays a trusted assumption)",
            "OUTSIDE_DISPOSED": "state-changing route outside the typed commands with a complete disposition record",
            "OUTSIDE_DISPOSITION_OPEN": "state-changing route outside the typed commands whose disposition record has a gap",
            "OUTSIDE_REQUIRES_DISPOSITION": "state-changing route outside the typed commands without a disposition record",
        },
        "runtimes": runtimes,
        "counts": counts,
        "dispositionRecords": records,
        "unmatchedSelectors": unmatched,
        "closure": {"criteria": criteria, "holds": closed},
        "nonclaim": NONCLAIM,
    }


def write_or_check(path: Path, document: dict[str, Any], check: bool) -> str:
    text = dump_json(document).encode("utf-8")
    if check:
        require(path.is_file() and path.read_bytes() == text, f"generated document drift: {label(path)}")
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(text)
    return sha256_bytes(text)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    render = commands.add_parser("render-classes")
    render.add_argument("--decision", type=Path, default=DECISION)
    render.add_argument("--output", type=Path, default=CLASSES)
    render.add_argument("--check", action="store_true")
    inventory = commands.add_parser("build")
    inventory.add_argument("--mode", choices=("prepare", "closure"), default="prepare")
    inventory.add_argument("--decision", type=Path, default=DECISION)
    inventory.add_argument("--classes", type=Path, default=CLASSES)
    inventory.add_argument("--dispositions", type=Path, default=DISPOSITIONS)
    inventory.add_argument("--malformed-receipt", type=Path)
    inventory.add_argument("--disposition-run", type=Path)
    inventory.add_argument("--output", type=Path, help="write the inventory here; it is written only when it closes")
    inventory.add_argument("--report", type=Path, help="write the closure verdict here, also when it fails")
    args = parser.parse_args(argv)
    if args.command == "render-classes":
        digest = write_or_check(args.output, render_classes(args.decision), args.check)
        print(dump_json({"status": "PASS_HOOK_CLASSES_" + ("CHECKED" if args.check else "WRITTEN"), "sha256": digest}), end="")
        return 0
    probe = probe_evidence(args.malformed_receipt) if args.malformed_receipt else None
    run = disposition_run(args.disposition_run) if args.disposition_run else None
    document = build(args.mode, args.decision, args.classes, args.dispositions, probe, run)
    verdict = {"status": document["status"], "mode": args.mode, "counts": document["counts"],
               "closure": document["closure"]}
    if args.report is not None:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(dump_json(verdict), encoding="utf-8", newline="\n")
    if args.mode == "closure" and not document["closure"]["holds"]:
        failed = [item["id"] for item in document["closure"]["criteria"] if not item["holds"]]
        raise PreparationError("route exhaustiveness does not close: " + ", ".join(failed))
    digest = None
    if args.output is not None:
        require(not args.output.exists(), "inventory output already exists")
        digest = write_or_check(args.output, document, False)
    print(dump_json({**verdict, "sha256": digest}), end="")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except PreparationError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
