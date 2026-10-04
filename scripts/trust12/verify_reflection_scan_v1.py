#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Check the public record of the reflection scan of the typed command paths and, with the stored scan, recompute it.

Metadata mode, which the required gate runs, reads tracked files only. It checks that the record is the reviewed one;
that the scan tool, the reviewed dispositions and the state and receipt crosswalk are the current files; that the
implementation sources, the ledger members that the scan reads, the compiler declarations and the quoted condition
are the current ones; that no implementation source holds an inline assembly storage write, which the scan does not
read; and that every classification, storage disposition, open item disposition and count of the record follows from
the current crosswalk, dispositions and ledgers. Saved mode additionally rehashes the stored
build information and the stored scan report named through a private index, runs the current scan tool on the stored
build information, requires the result to equal the stored report byte for byte and requires the public record to
follow from it. Neither mode runs the compiler or a prover.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import importlib.util
import json
from pathlib import Path, PurePosixPath
import re
import sys

CHECKPOINT_PATH = "evidence/trust12/runtime-link/tail-preparation/reflection-scan-checkpoint-v1.json"
VERIFIER_PATH = "scripts/trust12/verify_reflection_scan_v1.py"
IDENTITY_PATHS = {
    "scanTool": "scripts/trust12/tail-preparation/reflection_scan.py",
    "dispositions": "evidence/trust12/runtime-link/tail-preparation/reflection-dispositions-v1.json",
    "crosswalk": "evidence/trust12/runtime-link/tail-preparation/state-receipt-crosswalk-v1.json",
}
LEDGER_PATHS = {"central": "evidence/end-to-end-refinement/obligation-ledger-v3.json",
                "trust12": "evidence/trust12/obligation-ledger.json"}
LEDGER_READS = {"central": ["rows.id", "rows.finalSourceConsumers.path", "rows.finalSourceConsumers.snippet",
                            "assumptions.id"],
                "trust12": ["obligations.id"]}
CONDITIONS_PATH = "evidence/trust12/runtime-link/tail-preparation/tail-obligations-v1.json"
CONDITION_ID = "preservation-and-reflection"
FINDING_ID = "open-runtime-only-storage"
SOURCE_DIRECTORY = "implementation/src"
COMPILER_FILE = "foundry.toml"
COMPILER_SECTION = "[profile.default]"
COMPILER = {"solcVersion": "0.8.36", "evmVersion": "cancun", "viaIR": True, "optimizer": True, "optimizerRuns": 1,
            "declaredIn": COMPILER_FILE}
DECLARATIONS = ('solc_version = "0.8.36"', 'evm_version = "cancun"', "via_ir = true", "optimizer = true",
                "optimizer_runs = 1")
ARTIFACT_KINDS = {"build-info": "build-info", "reflection-scan-report": "report"}
COMMAND = ("python3 " + VERIFIER_PATH + " --product-root <product-root> "
           "--artifact-index <private-artifact-index.json>")
SCHEMA = "trust12-reflection-scan-checkpoint-v1"
STATUS = "PASS_REFLECTION_SCAN_ALL_CLASSIFIED"
SCAN_STATUS = "SCANNED_ALL_CLASSIFIED"
ENDPOINT_NAMES = ("TrustToken", "ERC3643TrustAdapter", "ERC3643HookAdapter")
TWIN_OWNER = {"ERC3643HookAdapter": "ERC3643TrustAdapter"}
VARIABLE_CLASSES = ("ABSTRACT_FIELD", "RUNTIME_ONLY", "RUNTIME_ONLY_BY_DISPOSITION")
GUARD_CLASSES = ("LEDGER_CONSUMER", "LEDGER_CONSUMER_BY_DISPOSITION", "RUNTIME_ONLY_BY_DISPOSITION")
GUARD_KINDS = ("revert", "require", "assert", "assembly-revert")
SCOPE = ("A machine scan of the stored solc build information of the exact product sources, its abstract syntax "
         "trees and compiled storage layouts, lists every state write and every guard that the typed command "
         "entrypoints of the Native endpoint, the Partial adapter and the Hook adapter reach without an external call, "
         "together with the exact-use route handlers of the Native endpoint and the balance callback of the Hook "
         "adapter that a typed command reaches through a call back into the endpoint: 59, 60 and 61 guards and 17, 12 "
         "and 12 written state variables. Every write is classified as an abstract field of the state and receipt "
         "crosswalk, as a runtime-only variable with the reason of the earlier central closure, or as a runtime-only "
         "variable with a reason in the reviewed dispositions. Every guard is classified as matched with a final source "
         "consumer snippet of a row of the central obligation ledger, as linked by a reviewed disposition to the ledger "
         "rows that the disposition names, or as a runtime-only guard with a reason in the reviewed dispositions. No "
         "write or guard is unclassified, no write goes through an unresolved storage reference, and the compiled "
         "storage layouts of the seven profile runtimes agree with the crosswalk. Each of the twelve storage variables "
         "that the crosswalk leaves without an abstract field or an earlier runtime-only reason has a reviewed reason "
         "and named ledger rows, and the functions that write it are exactly the functions that the scan finds.")
PATH_BOUNDARY = ("The scan follows internal calls, library calls and modifiers from the typed command entrypoints. The "
                 "entrypoints that a typed command reaches through a call back into the endpoint are declared in the "
                 "scan tool, not discovered by it: the two exact-use route handlers of the Native endpoint and the "
                 "balance callback of the Hook adapter. A state write is an assignment, an increment or decrement, a "
                 "delete, a push or a pop, followed through local storage pointers and storage parameters to the state "
                 "variable; no implementation source holds an inline assembly storage write. A guard is a revert "
                 "statement, a require or assert call, or an inline assembly block that reverts; checks that the "
                 "compiler generates, such as calldata decoding and checked arithmetic, are not source guards and are "
                 "not listed.")
CLASSIFICATION_BOUNDARY = ("The scan reads syntax trees and layouts; it does not execute the code. A classification "
                           "records which obligation or reason a write or guard is matched with: a guard matches a "
                           "consumer snippet when one text contains the other or when the snippet calls the function "
                           "that holds the guard, and a Hook adapter guard in a function whose source text equals the "
                           "Partial adapter function of the same name takes the classification of that Partial guard. "
                           "A classification does not prove that a guard is sound, that a listed reason is true or that "
                           "a named ledger row covers the guard. The fifteen Hook adapter columns that the crosswalk "
                           "derives from the Partial layout are compared writer by writer with the Partial adapter, and "
                           "the two Hook writers with their own source text have reviewed dispositions that pin both "
                           "texts by hash. The syntax trees and layouts come from a stored build of the exact sources "
                           "with the compiler settings that the product declares. The record binds that build by hash "
                           "and does not rerun the compiler: that the stored syntax trees and layouts are what the "
                           "pinned compiler produces for these sources is not rechecked, and the correctness of the "
                           "compiler remains the assumption A-COMPILER.")
REVERSAL_CHECK_BOUNDARY = ("Four of the reviewed guard dispositions classify the domain check and the derived "
                           "identifier check of a reversal request on the Native endpoint and on the Partial adapter, "
                           "and the Hook adapter takes both through its identical function text. The ledger rows they "
                           "name receive or state the rule that the check enforces: the kernel domain value with its "
                           "DOMAIN reason code, the IDENTIFIER reason code, the reversal identifier hash, the common "
                           "shape rules and the single use of reversal identifiers. The final source consumers and the "
                           "removal negatives of those rows name other statements, among them the matching checks of "
                           "an action request and the replay checks, and no removal negative targets a domain or "
                           "identifier check of a reversal request.")
CONDITION_BOUNDARY = ("This record is evidence for the two closure acceptance criteria of the preservation and "
                      "reflection condition that it quotes, and for the finding on runtime-only storage: it gives the "
                      "reason that the finding asks for each storage variable that no abstract field reads and that "
                      "the earlier central closure left without a runtime-only reason. The condition also states that "
                      "abstract allowed behavior is preserved by the final code; this record does not address that "
                      "part. The scan also checks the dispositions of the open items of the crosswalk, but the record "
                      "is not evidence for the state and receipt identity condition: the open item that waits for a "
                      "formal reader of storage into abstract fields stays open, and so does the finding that no such "
                      "reader exists.")
REPRODUCTION_BOUNDARY = ("Metadata mode reads tracked files only. It checks that this record is the reviewed one, that "
                         "the scan tool, the dispositions and the crosswalk are the current files, that the "
                         "implementation sources, the ledger members that the scan reads, the compiler declarations "
                         "and the quoted condition are the current ones, that no implementation source holds an inline "
                         "assembly storage write, and that every classification, disposition and count of this record "
                         "follows from the current crosswalk, dispositions and ledgers. Saved mode additionally "
                         "rehashes the stored build information and the stored scan report named through a private "
                         "index, runs the current scan tool on the stored build information and requires the result to "
                         "equal the stored report byte for byte and this record to follow from it. Neither mode runs "
                         "the compiler or a prover, and the record states no completion of the preservation and "
                         "reflection condition, the registered-scope central closure, any general runtime link, the "
                         "independent Assurance or TRUST 1.2.")
COVERAGE = {
    "endpoints": {
        "TrustToken": {"entries": 4, "reentries": 2, "reachedFunctions": 47,
                       "writtenVariables": {"ABSTRACT_FIELD": 13, "RUNTIME_ONLY": 2, "RUNTIME_ONLY_BY_DISPOSITION": 2},
                       "guards": {"LEDGER_CONSUMER": 39, "LEDGER_CONSUMER_BY_DISPOSITION": 19,
                                  "RUNTIME_ONLY_BY_DISPOSITION": 1},
                       "unclassified": 0, "unresolvedWrites": 0},
        "ERC3643TrustAdapter": {"entries": 2, "reentries": 0, "reachedFunctions": 47,
                                "writtenVariables": {"ABSTRACT_FIELD": 11, "RUNTIME_ONLY": 1,
                                                     "RUNTIME_ONLY_BY_DISPOSITION": 0},
                                "guards": {"LEDGER_CONSUMER": 47, "LEDGER_CONSUMER_BY_DISPOSITION": 12,
                                           "RUNTIME_ONLY_BY_DISPOSITION": 1},
                                "unclassified": 0, "unresolvedWrites": 0},
        "ERC3643HookAdapter": {"entries": 2, "reentries": 1, "reachedFunctions": 48,
                               "writtenVariables": {"ABSTRACT_FIELD": 11, "RUNTIME_ONLY": 1,
                                                    "RUNTIME_ONLY_BY_DISPOSITION": 0},
                               "guards": {"LEDGER_CONSUMER": 47, "LEDGER_CONSUMER_BY_DISPOSITION": 13,
                                          "RUNTIME_ONLY_BY_DISPOSITION": 1},
                               "unclassified": 0, "unresolvedWrites": 0},
    },
    "compiledLayoutVariables": {"TrustToken": 26, "ERC3643TrustAdapter": 18, "ProfileGovernor": 4,
                                "ERC3643HookAdapter": 18, "ERC3643HookGovernor": 4, "ERC3643HookCompliance": 2,
                                "ERC3643HookFactory": 0},
    "storageDispositions": 12,
    "guardDispositions": 34,
    "hookDerivedColumns": 15,
    "hookColumnWritersWithOwnText": 2,
    "openItems": 9,
    "problems": 0,
    "reviewPending": 0,
}
NONCLAIM_KEYS = ("guardSoundness", "dispositionReasonTruth", "ledgerRowCoverage", "reversalCheckRemovalNegatives",
                 "compilerGeneratedChecks", "abstractBehaviorPreservation", "stateReceiptIdentity",
                 "formalStorageReader", "compilerRerun", "proverRerun", "registeredCentralClosure",
                 "generalRuntimeLinks", "independentAssurance", "fullTrustCompletion", "releaseOrDeployment")
EXPECTED_EVIDENCE_DIGEST = 'd91a26afe945929825453ae3c1ad2538f3b7d6050048cdb7555eb425a6892149'
PUBLIC_KEYS = {"schema", "status", "scope", "pathBoundary", "classificationBoundary", "reversalCheckBoundary",
               "conditionBoundary", "reproductionBoundary", "evidenceFor", "coverage", "compiler", "productIdentity",
               "implementationSources", "ledgerMembers", "artifacts", "rehashVerifier", "nonclaims",
               "storageDispositions", "openItems", "hookColumnWritersWithOwnText", "endpoints"}
VARIABLE_KEYS = {"label", "class", "column", "writers"}
GUARD_KEYS = {"function", "kind", "line", "guard", "class", "ledger", "rows", "sameBodyAs"}
STORAGE_KEYS = ("runtime", "label", "slot", "writtenBy", "assignedBy", "clearedBy", "ledger", "rows", "reason")
HEX64 = re.compile(r"[0-9a-f]{64}")
ASSEMBLY_STORAGE_WRITE = re.compile(r"\b[st]store\s*\(")
PRIVATE = re.compile(r"(?i)[A-Za-z]:[\\/]|/mnt/|/h[o]me/|\\\\|(?<![A-Za-z0-9])(?:G|M|FV|RL)[0-9]+(?![0-9])")
_TOOLS = {}


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read_json(path):
    value = json.loads(Path(path).read_text(encoding="utf-8"))
    require(isinstance(value, dict), "JSON object required")
    return value


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True, allow_nan=False).encode("utf-8")


def same_json(left, right):
    return canonical(left) == canonical(right)


def payload_digest(checkpoint):
    return hashlib.sha256(canonical({key: value for key, value in checkpoint.items() if key != "rehashVerifier"})).hexdigest()


def dump_report(report):
    """The bytes that the command line of the scan tool writes for a report."""
    return (json.dumps(report, indent=2) + "\n").encode("utf-8")


def privacy_boundary(checkpoint):
    encoded = json.dumps(checkpoint, ensure_ascii=False)
    require(encoded.isascii() and not PRIVATE.search(encoded), "Private or non-English metadata")


def file_identity(product, relative):
    path = (product / relative).resolve()
    require(path.is_file() and path.is_relative_to(product), "Missing product file: " + relative)
    return {"path": relative, "bytes": path.stat().st_size, "sha256": digest(path)}


def metadata_inputs(product):
    """Every product file that metadata mode reads, relative to the product root."""
    sources = sorted(path.relative_to(product).as_posix() for path in (product / SOURCE_DIRECTORY).rglob("*.sol")
                     if path.is_file())
    return sorted({VERIFIER_PATH, *IDENTITY_PATHS.values(), *LEDGER_PATHS.values(), CONDITIONS_PATH, COMPILER_FILE,
                   *sources})


def load_tool(product):
    """The scan tool of the product tree, loaded from that file and from nowhere else."""
    path = (product / IDENTITY_PATHS["scanTool"]).resolve()
    require(path.is_file() and path.is_relative_to(product), "Missing scan tool")
    key = str(path)
    if key not in _TOOLS:
        sys.dont_write_bytecode = True
        name = "trust12_reflection_scan_" + hashlib.sha256(key.encode("utf-8")).hexdigest()[:16]
        spec = importlib.util.spec_from_file_location(name, path)
        module = importlib.util.module_from_spec(spec)
        sys.modules[name] = module
        spec.loader.exec_module(module)
        _TOOLS[key] = module
    tool = _TOOLS[key]
    require(Path(tool.__file__).resolve() == path, "Loaded scan tool differs from the product file")
    return tool


def tool_constants(tool):
    """The scan reads the files this verifier binds and scans the endpoints this record lists."""
    require(tool.CROSSWALK == IDENTITY_PATHS["crosswalk"] and tool.DISPOSITIONS == IDENTITY_PATHS["dispositions"]
            and tool.LEDGERS == LEDGER_PATHS and tuple(tool.ENDPOINTS) == ENDPOINT_NAMES and tool.TWIN == TWIN_OWNER
            and len(tool.RUNTIMES) == len(COVERAGE["compiledLayoutVariables"])
            and set(tool.RUNTIMES) == set(COVERAGE["compiledLayoutVariables"]), "Scan tool constants differ")


def implementation_sources(product):
    """Every Solidity source under the implementation source directory, ordered by its POSIX path."""
    files = sorted(path.relative_to(product).as_posix() for path in (product / SOURCE_DIRECTORY).rglob("*.sol")
                   if path.is_file())
    return [file_identity(product, relative) for relative in files]


def assembly_storage_writes(product):
    """Implementation sources whose text names an inline assembly storage write, which the scan does not read."""
    return [row["path"] for row in implementation_sources(product)
            if ASSEMBLY_STORAGE_WRITE.search((product / row["path"]).read_text(encoding="utf-8"))]


def consumer_paths(tool):
    return sorted({tool.RUNTIMES[TWIN_OWNER.get(name, name)] for name in ENDPOINT_NAMES})


def ledger_members(product, tool):
    """The members of both ledgers that the scan reads, bound by a digest of their canonical form."""
    central = read_json(product / LEDGER_PATHS["central"])
    profile = read_json(product / LEDGER_PATHS["trust12"])
    paths = consumer_paths(tool)
    members = {
        "central": {"rows": sorted(row["id"] for row in central["rows"]),
                    "consumers": sorted([row["id"], consumer["path"], consumer["snippet"]] for row in central["rows"]
                                        for consumer in row["finalSourceConsumers"] if consumer.get("path") in paths),
                    "assumptions": sorted(item["id"] for item in central["assumptions"])},
        "trust12": {"obligations": sorted(row["id"] for row in profile["obligations"])},
    }
    return {name: {"path": LEDGER_PATHS[name], "reads": LEDGER_READS[name],
                   "sha256": hashlib.sha256(canonical(members[name])).hexdigest()} for name in LEDGER_PATHS}


def ledger_ids(product):
    central = read_json(product / LEDGER_PATHS["central"])
    profile = read_json(product / LEDGER_PATHS["trust12"])
    return {"central": {row["id"] for row in central["rows"]},
            "trust12": {row["id"] for row in profile["obligations"]}}


def compiler_declarations(product):
    """The compiler declarations of the default profile, which must each appear there exactly once."""
    section, lines = None, []
    for raw in (product / COMPILER_FILE).read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line.startswith("["):
            section = line
        elif section == COMPILER_SECTION:
            lines.append(line)
    require(all(lines.count(item) == 1 for item in DECLARATIONS), "Compiler declaration differs from the product")
    return dict(COMPILER)


def evidence_for(product):
    """The acceptance criteria and the finding of the conditions list that this record is evidence for."""
    conditions = read_json(product / CONDITIONS_PATH)
    matches = [item for item in conditions["conditions"] if item["id"] == CONDITION_ID]
    findings = [item for item in conditions["findings"] if item["id"] == FINDING_ID]
    require(len(matches) == 1 and len(findings) == 1 and FINDING_ID in matches[0]["blockingFindings"],
            "Condition text differs from the current conditions list")
    return {"condition": CONDITION_ID, "closureAcceptance": matches[0]["closureAcceptance"],
            "finding": {"id": FINDING_ID, "decisionNeeded": findings[0]["decisionNeeded"]}}


def storage_rows(dispositions, written_by):
    return [{"runtime": item["runtime"], "label": item["label"], "slot": item["slot"],
             "writtenBy": written_by(item), "assignedBy": item["assignedBy"], "clearedBy": item["clearedBy"],
             "ledger": item["ledger"], "rows": item["rows"], "reason": item["reason"]}
            for item in dispositions["storage"]]


def open_item_rows(dispositions):
    return [{"index": item["index"], "disposition": item["disposition"]}
            for item in sorted(dispositions["openItems"], key=lambda item: item["index"])]


def ledger_of(guard):
    if guard["class"] == "LEDGER_CONSUMER":
        return "central"
    if guard["class"] == "LEDGER_CONSUMER_BY_DISPOSITION":
        return guard.get("ledger", "central")
    return None


def public_summary(report, dispositions):
    """The public part of the record that follows from a scan report and the dispositions it checked."""
    endpoints, endpoint_coverage = {}, {}
    for name in ENDPOINT_NAMES:
        item = report["endpoints"][name]
        variables = [{"label": label, "class": value["class"], "column": value.get("column"),
                      "writers": sorted({site["function"] for site in value["sites"]})}
                     for label, value in sorted(item["variables"].items())]
        guards = [{"function": guard["function"], "kind": guard["kind"], "line": guard["line"], "guard": guard["guard"],
                   "class": guard["class"], "ledger": ledger_of(guard), "rows": sorted(guard["rows"]),
                   "sameBodyAs": guard["sameBodyAs"]} for guard in item["guards"]]
        endpoints[name] = {"entries": list(item["entries"]), "reentries": sorted(item["reentries"]),
                           "variables": variables, "guards": guards}
        variable_classes = Counter(value["class"] for value in item["variables"].values())
        endpoint_coverage[name] = {
            "entries": len(item["entries"]), "reentries": len(item["reentries"]),
            "reachedFunctions": item["counts"]["reachedFunctions"],
            "writtenVariables": {kind: variable_classes.get(kind, 0) for kind in VARIABLE_CLASSES},
            "guards": {kind: item["counts"]["guardClasses"][kind] for kind in GUARD_CLASSES},
            "unclassified": len(item["counts"]["unclassifiedVariables"]) + item["counts"]["guardClasses"]["UNCLASSIFIED"],
            "unresolvedWrites": item["counts"]["unresolvedWrites"]}
    own_text = sorted({function for column in report["hookColumns"] for function in column["writersWithOwnText"]})
    coverage = {"endpoints": endpoint_coverage, "compiledLayoutVariables": report["compiledLayoutVariables"],
                "storageDispositions": len(dispositions["storage"]), "guardDispositions": len(dispositions["guards"]),
                "hookDerivedColumns": len(report["hookColumns"]), "hookColumnWritersWithOwnText": len(own_text),
                "openItems": len(dispositions["openItems"]), "problems": len(report["problems"]),
                "reviewPending": report["dispositions"]["reviewPending"]}
    storage = storage_rows(dispositions, lambda item: report["writtenBy"][item["runtime"]][item["label"]])
    return {"coverage": coverage, "endpoints": endpoints, "storageDispositions": storage,
            "openItems": open_item_rows(dispositions), "hookColumnWritersWithOwnText": own_text}


def build_checkpoint(summary, product, artifacts):
    """The record before its verifier identity is added; the writer pins its digest in this verifier."""
    tool = load_tool(product)
    return {"schema": SCHEMA, "status": STATUS, "scope": SCOPE, "pathBoundary": PATH_BOUNDARY,
            "classificationBoundary": CLASSIFICATION_BOUNDARY,
            "reversalCheckBoundary": REVERSAL_CHECK_BOUNDARY, "conditionBoundary": CONDITION_BOUNDARY,
            "reproductionBoundary": REPRODUCTION_BOUNDARY, "evidenceFor": evidence_for(product),
            "coverage": summary["coverage"], "compiler": compiler_declarations(product),
            "productIdentity": {key: file_identity(product, path) for key, path in IDENTITY_PATHS.items()},
            "implementationSources": implementation_sources(product), "ledgerMembers": ledger_members(product, tool),
            "artifacts": artifacts, "rehashVerifier": None, "nonclaims": {key: True for key in NONCLAIM_KEYS},
            "storageDispositions": summary["storageDispositions"], "openItems": summary["openItems"],
            "hookColumnWritersWithOwnText": summary["hookColumnWritersWithOwnText"], "endpoints": summary["endpoints"]}


def check_artifacts(artifacts):
    require(isinstance(artifacts, list) and [row.get("id") for row in artifacts] == list(ARTIFACT_KINDS)
            and all(isinstance(row, dict) and set(row) == {"id", "kind", "bytes", "sha256"}
                    and row["kind"] == ARTIFACT_KINDS[row["id"]] and type(row["bytes"]) is int and row["bytes"] > 0
                    and isinstance(row["sha256"], str) and HEX64.fullmatch(row["sha256"]) is not None for row in artifacts)
            and len({row["sha256"] for row in artifacts}) == len(artifacts), "Artifact inventory differs")


def sorted_names(value):
    return isinstance(value, list) and all(isinstance(item, str) and item for item in value) and value == sorted(set(value))


def check_variables(name, rows, crosswalk, dispositions):
    """Every written variable row has the class that the current crosswalk and dispositions give its label."""
    require(isinstance(rows, list) and all(isinstance(row, dict) and set(row) == VARIABLE_KEYS for row in rows)
            and [row["label"] for row in rows] == sorted({row["label"] for row in rows}), "Variable rows differ: " + name)
    abstract = {}
    for field in crosswalk["stateFields"]:
        column = field["runtimes"].get(name)
        if column and column.get("storage"):
            abstract[column["storage"]["label"]] = column["status"]
    runtime_only = {row["label"]: row["status"] for row in crosswalk["storageWithoutAbstractField"].get(name, [])}
    disposed = {row["label"] for row in dispositions["storage"] if row["runtime"] == name}
    for row in rows:
        label = row["label"]
        if label in abstract:
            expected = ("ABSTRACT_FIELD", abstract[label])
        elif label in runtime_only and runtime_only[label] != "OPEN":
            expected = ("RUNTIME_ONLY", None)
        elif label in disposed:
            expected = ("RUNTIME_ONLY_BY_DISPOSITION", None)
        else:
            expected = ("UNCLASSIFIED", None)
        require((row["class"], row["column"]) == expected and row["class"] in VARIABLE_CLASSES
                and row["writers"] and sorted_names(row["writers"]), f"Variable row differs: {name}.{label}")


def check_guards(name, rows, dispositions, ids):
    """Every guard row names existing rows and, when a disposition classifies it, a matching reviewed disposition."""
    require(isinstance(rows, list) and all(isinstance(row, dict) and set(row) == GUARD_KEYS for row in rows),
            "Guard rows differ: " + name)
    reviewed = {}
    for item in dispositions["guards"]:
        reviewed.setdefault((item["runtime"], item["function"]), []).append(item)
    for row in rows:
        where = f"Guard row differs: {name} line {row.get('line')}"
        require(row["kind"] in GUARD_KINDS and type(row["line"]) is int and row["line"] > 0
                and isinstance(row["function"], str) and row["function"] and isinstance(row["guard"], str)
                and row["guard"] and row["class"] in GUARD_CLASSES and sorted_names(row["rows"])
                and (row["sameBodyAs"] is None or row["sameBodyAs"] == TWIN_OWNER.get(name)), where)
        candidates = list(reviewed.get((name, row["function"]), []))
        if row["sameBodyAs"]:
            candidates += reviewed.get((row["sameBodyAs"], row["function"]), [])
        if row["class"] == "LEDGER_CONSUMER":
            require(row["ledger"] == "central" and row["rows"] and set(row["rows"]) <= ids["central"], where)
        elif row["class"] == "LEDGER_CONSUMER_BY_DISPOSITION":
            require(row["ledger"] in ids and row["rows"] and set(row["rows"]) <= ids[row["ledger"]]
                    and any(item.get("rows") and sorted(item["rows"]) == row["rows"]
                            and item.get("ledger", "central") == row["ledger"] for item in candidates), where)
        else:
            require(row["ledger"] is None and row["rows"] == [] and any(item.get("runtimeOnly") for item in candidates),
                    where)


def follows_from_rows(checkpoint, tool):
    """The counts of the record that its rows determine."""
    coverage = checkpoint["coverage"]
    for name in ENDPOINT_NAMES:
        endpoint = checkpoint["endpoints"][name]
        expected = coverage["endpoints"][name]
        spec = tool.ENDPOINTS[name]
        require(endpoint["entries"] == spec["entries"] and endpoint["reentries"] == sorted(spec["reentries"])
                and expected["entries"] == len(endpoint["entries"]) and expected["reentries"] == len(endpoint["reentries"]),
                "Endpoint entries differ: " + name)
        variables = Counter(row["class"] for row in endpoint["variables"])
        guards = Counter(row["class"] for row in endpoint["guards"])
        require(expected["writtenVariables"] == {kind: variables.get(kind, 0) for kind in VARIABLE_CLASSES}
                and expected["guards"] == {kind: guards.get(kind, 0) for kind in GUARD_CLASSES}
                and expected["unclassified"] == 0, "Coverage does not follow from the rows: " + name)
    require(coverage["storageDispositions"] == len(checkpoint["storageDispositions"])
            and coverage["openItems"] == len(checkpoint["openItems"])
            and coverage["hookColumnWritersWithOwnText"] == len(checkpoint["hookColumnWritersWithOwnText"]),
            "Coverage does not follow from the rows")


def check_dispositions(checkpoint, crosswalk, dispositions, ids):
    """The storage, open item and Hook writer rows follow from the current dispositions and crosswalk."""
    require(dispositions.get("status") == "REVIEWED" and len(dispositions["guards"]) == checkpoint["coverage"]["guardDispositions"],
            "Dispositions are not the reviewed ones")
    expected = storage_rows(dispositions, lambda item: sorted(set(item["assignedBy"]) | set(item["clearedBy"])))
    require(isinstance(checkpoint["storageDispositions"], list)
            and all(isinstance(row, dict) and set(row) == set(STORAGE_KEYS) for row in checkpoint["storageDispositions"])
            and same_json(checkpoint["storageDispositions"], expected), "Storage disposition rows differ")
    open_storage = {(name, row["label"], row["slot"]) for name, items in crosswalk["storageWithoutAbstractField"].items()
                    for row in items if row["status"] == "OPEN"}
    require({(row["runtime"], row["label"], row["slot"]) for row in expected} == open_storage
            and len(expected) == len(open_storage), "Storage disposition rows differ from the open crosswalk storage")
    for row in expected:
        require(row["reason"] and row["writtenBy"] and row["ledger"] in ids and row["rows"]
                and set(row["rows"]) <= ids[row["ledger"]], "Storage disposition rows differ: " + row["label"])
    texts = crosswalk["openItems"]
    require(same_json(checkpoint["openItems"], open_item_rows(dispositions))
            and [row["index"] for row in checkpoint["openItems"]] == list(range(len(texts)))
            and all(item["text"] == texts[item["index"]] for item in dispositions["openItems"]),
            "Open item dispositions differ")
    require(checkpoint["hookColumnWritersWithOwnText"] == sorted(item["function"] for item in dispositions["hookColumnWriters"]),
            "Hook writer dispositions differ")


def public_contract(checkpoint, product):
    product = product.resolve()
    require(set(checkpoint) == PUBLIC_KEYS and checkpoint["schema"] == SCHEMA and checkpoint["status"] == STATUS,
            "Checkpoint contract differs")
    privacy_boundary(checkpoint)
    require(payload_digest(checkpoint) == EXPECTED_EVIDENCE_DIGEST, "Reviewed evidence digest differs")
    require(checkpoint["scope"] == SCOPE and checkpoint["pathBoundary"] == PATH_BOUNDARY
            and checkpoint["classificationBoundary"] == CLASSIFICATION_BOUNDARY
            and checkpoint["reversalCheckBoundary"] == REVERSAL_CHECK_BOUNDARY
            and checkpoint["conditionBoundary"] == CONDITION_BOUNDARY
            and checkpoint["reproductionBoundary"] == REPRODUCTION_BOUNDARY, "Public scope or boundary differs")
    require(checkpoint["nonclaims"] == {key: True for key in NONCLAIM_KEYS}, "All bounded nonclaims required")
    require(same_json(checkpoint["coverage"], COVERAGE), "Coverage differs from the reviewed counts")
    check_artifacts(checkpoint["artifacts"])
    verifier = checkpoint["rehashVerifier"]
    require(isinstance(verifier, dict) and set(verifier) == {"path", "bytes", "sha256", "command"}
            and verifier["command"] == COMMAND
            and {key: verifier[key] for key in ("path", "bytes", "sha256")} == file_identity(product, VERIFIER_PATH),
            "Current verifier differs")
    require(checkpoint["productIdentity"] == {key: file_identity(product, path) for key, path in IDENTITY_PATHS.items()},
            "Product identity differs from the current files")
    tool = load_tool(product)
    tool_constants(tool)
    require(checkpoint["implementationSources"] == implementation_sources(product),
            "Implementation sources differ from the current sources")
    require(not assembly_storage_writes(product), "An implementation source holds an inline assembly storage write")
    require(checkpoint["ledgerMembers"] == ledger_members(product, tool), "Ledger members differ from the current ledgers")
    require(checkpoint["compiler"] == compiler_declarations(product), "Compiler record differs")
    require(checkpoint["evidenceFor"] == evidence_for(product), "Condition text differs from the current conditions list")
    crosswalk = read_json(product / IDENTITY_PATHS["crosswalk"])
    dispositions = read_json(product / IDENTITY_PATHS["dispositions"])
    ids = ledger_ids(product)
    endpoints = checkpoint["endpoints"]
    require(isinstance(endpoints, dict) and list(endpoints) == list(ENDPOINT_NAMES)
            and all(isinstance(item, dict) and set(item) == {"entries", "reentries", "variables", "guards"}
                    for item in endpoints.values()), "Endpoint rows differ")
    for name in ENDPOINT_NAMES:
        check_variables(name, endpoints[name]["variables"], crosswalk, dispositions)
        check_guards(name, endpoints[name]["guards"], dispositions, ids)
    follows_from_rows(checkpoint, tool)
    check_dispositions(checkpoint, crosswalk, dispositions, ids)
    return tool


def private_file(base, relative, label):
    require(isinstance(relative, str) and relative and not PurePosixPath(relative).is_absolute()
            and ".." not in PurePosixPath(relative).parts and ":" not in relative, "Private index path differs: " + label)
    path = (base / relative).resolve()
    require(path.is_relative_to(base) and path.is_file(), "Private artifact missing: " + label)
    return path


def check_build(build, checkpoint):
    """The stored build compiled exactly the recorded sources with the recorded compiler settings."""
    settings = (build.get("input") or {}).get("settings") or {}
    optimizer = settings.get("optimizer") or {}
    require(build.get("solcVersion") == COMPILER["solcVersion"] and settings.get("evmVersion") == COMPILER["evmVersion"]
            and settings.get("viaIR") is COMPILER["viaIR"] and optimizer.get("enabled") is COMPILER["optimizer"]
            and optimizer.get("runs") == COMPILER["optimizerRuns"], "Build compiler differs from the record")
    sources = (build.get("input") or {}).get("sources") or {}
    built = [{"path": path, "bytes": len(sources[path]["content"].encode("utf-8")),
              "sha256": hashlib.sha256(sources[path]["content"].encode("utf-8")).hexdigest()} for path in sorted(sources)]
    require(built == checkpoint["implementationSources"], "Build sources differ from the record")


def verify_checkpoint(checkpoint, index_path, product):
    product, index_path = product.resolve(), index_path.resolve()
    tool = public_contract(checkpoint, product)
    verifier_file = (product / VERIFIER_PATH).resolve()
    require(Path(__file__).resolve() == verifier_file, "Executing verifier identity differs")
    index = read_json(index_path)
    require(set(index) == set(ARTIFACT_KINDS), "Private index roles differ")
    base = index_path.parent
    files = {}
    for row in checkpoint["artifacts"]:
        path = private_file(base, index[row["id"]], row["id"])
        require(path.stat().st_size == row["bytes"] and digest(path) == row["sha256"], "Private artifact drift: " + row["id"])
        files[row["id"]] = path
    check_build(read_json(files["build-info"]), checkpoint)
    stored_bytes = files["reflection-scan-report"].read_bytes()
    stored = json.loads(stored_bytes.decode("utf-8"))
    require(isinstance(stored, dict) and stored.get("schema") == tool.SCHEMA and stored.get("status") == SCAN_STATUS
            and stored.get("classification") == SCAN_STATUS and stored.get("problems") == []
            and isinstance(stored.get("dispositions"), dict) and stored["dispositions"].get("status") == tool.REVIEWED
            and stored["dispositions"].get("reviewPending") == 0, "Stored report contract differs")
    require(stored.get("buildInfoSha256") == [checkpoint["artifacts"][0]["sha256"]],
            "Stored report names another build information")
    require(stored["dispositions"].get("sha256") == checkpoint["productIdentity"]["dispositions"]["sha256"],
            "Stored report names other dispositions")
    rebuilt = tool.build_report(product, [files["build-info"]])
    require(dump_report(rebuilt) == stored_bytes, "Scan recomputation differs from the stored report")
    summary = public_summary(rebuilt, read_json(product / IDENTITY_PATHS["dispositions"]))
    for key, value in summary.items():
        require(same_json(checkpoint[key], value), "Public record differs from the recomputed report: " + key)
    for row in checkpoint["artifacts"]:
        require(digest(files[row["id"]]) == row["sha256"], "Private artifact changed while checked: " + row["id"])
    for key, path in IDENTITY_PATHS.items():
        require(digest(product / path) == checkpoint["productIdentity"][key]["sha256"],
                "Product identity changed while checked: " + key)
    require(digest(verifier_file) == checkpoint["rehashVerifier"]["sha256"], "Verifier changed while checked")
    counts = {name: rebuilt["endpoints"][name]["counts"]["guards"] for name in ENDPOINT_NAMES}
    return {"schema": "trust12-reflection-scan-rehash-v1", "status": "PASS_REFLECTION_SCAN_RECOMPUTED",
            "guards": counts, "classification": rebuilt["classification"], "compilerRerun": False,
            "proverRerun": False, "preservationAndReflectionDischarged": False, "nonclaim": REPRODUCTION_BOUNDARY}


def metadata_only(checkpoint, product):
    public_contract(checkpoint, product.resolve())
    return {"status": "PASS_PUBLIC_METADATA_ONLY", "savedArtifactsVerified": False, "scanRerun": False,
            "nonclaims": sorted(NONCLAIM_KEYS)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--product-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--checkpoint", type=Path)
    parser.add_argument("--metadata-only", action="store_true")
    parser.add_argument("--artifact-index", type=Path)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    sys.dont_write_bytecode = True
    product = args.product_root.resolve()
    checkpoint_path = (args.checkpoint or product / CHECKPOINT_PATH).resolve()
    require(checkpoint_path == (product / CHECKPOINT_PATH).resolve(), "Unexpected checkpoint location")
    checkpoint = read_json(checkpoint_path)
    if args.metadata_only:
        require(args.artifact_index is None, "Metadata mode reads no private file")
        report = metadata_only(checkpoint, product)
    else:
        require(args.artifact_index is not None, "Saved mode requires the private index")
        report = verify_checkpoint(checkpoint, args.artifact_index, product)
    if args.out:
        with args.out.open("x", encoding="utf-8", newline="\n") as handle:
            handle.write(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, OSError, ValueError, KeyError, TypeError, AttributeError, ImportError, IndexError) as error:
        raise SystemExit(f"FAIL: {error}")
