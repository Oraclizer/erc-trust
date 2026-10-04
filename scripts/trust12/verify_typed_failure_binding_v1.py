#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Check the public record of the TRUST 1.2 typed failure binding and, with the private run records, recompute it.

Metadata mode, which the required gate runs, reads tracked files only. It checks that the record is the reviewed one
and that the product files it names are the current files; it re-reads every recorded payload of the typed failure
probe with the current fixed ABI reading and binding and requires every verdict and count of the record to follow;
it checks every mutant record against the current mutant list, sources and factory pin; and it compares the load
record with the code identity document, the runtime templates and the bound compiler inputs. Saved mode additionally
rehashes the private probe and mutant receipts, their forge reports, the record of the isolated build, the load scan
and the compiled artifacts named through a private index, recomputes every receipt from its forge report and the scan
from the compiled artifacts, and requires them to equal the stored ones byte for byte. Neither mode reruns Foundry or
the compiler.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib
import inspect
import json
from pathlib import Path, PurePosixPath
import re
import sys

CHECKPOINT_PATH = "evidence/trust12/runtime-link/tail-preparation/typed-failure-checkpoint-v1.json"
VERIFIER_PATH = "scripts/trust12/verify_typed_failure_binding_v1.py"
TOOL_DIRECTORY = "scripts/trust12/tail-preparation"
MODULES = {name: f"{TOOL_DIRECTORY}/{name}.py" for name in (
    "run_typed_failure_probe", "typed_failure_report", "code_identity_v2", "code_identity", "tail_common",
    "run_malformed_probe", "run_malformed_probe_v2")}
PROBE_DIRECTORY = "scripts/trust12/tail-preparation/typed-failure-probe"
IDENTITY_PATHS = {
    "probeRunner": f"{TOOL_DIRECTORY}/run_typed_failure_probe.py",
    "failureReading": f"{TOOL_DIRECTORY}/typed_failure_report.py",
    "loadScanner": f"{TOOL_DIRECTORY}/code_identity_v2.py",
    "codeIdentityTool": f"{TOOL_DIRECTORY}/code_identity.py",
    "preparationCommon": f"{TOOL_DIRECTORY}/tail_common.py",
    "malformedRunner": f"{TOOL_DIRECTORY}/run_malformed_probe.py",
    "mutationHelpers": f"{TOOL_DIRECTORY}/run_malformed_probe_v2.py",
    "probeCore": f"{PROBE_DIRECTORY}/TypedFailureProbeCore.sol",
    "nativeProbe": f"{PROBE_DIRECTORY}/NativeTypedFailureProbe.t.sol",
    "partialProbe": f"{PROBE_DIRECTORY}/PartialTypedFailureProbe.t.sol",
    "hookProbe": f"{PROBE_DIRECTORY}/HookTypedFailureProbe.t.sol",
    "mutantList": "evidence/trust12/runtime-link/tail-preparation/typed-failure-probe-mutants-v1.json",
    "codeIdentity": "evidence/trust12/runtime-link/tail-preparation/code-identity-v1.json",
    "runtimeIdentity": "evidence/trust12/runtime-identity.json",
    "formalBridge": "formal/isabelle/ERC_TRUST/TRUST_Runtime_Bridge_Generated.thy",
    "kernelAbi": "spec/generated/kernel-v2-abi.json",
    "nativeInput": "evidence/runtime-binding-v3/native/standard-json-input.json",
    "partialInput": "evidence/runtime-binding-v3/erc3643-partial/standard-json-input.json",
    "hookInput": "evidence/runtime-binding-v3/erc3643-hook/standard-json-input.json",
    "nativeArtifacts": "evidence/runtime-binding-v3/native/bridge-artifacts.json",
    "partialArtifacts": "evidence/runtime-binding-v3/erc3643-partial/bridge-artifacts.json",
    "hookArtifacts": "evidence/runtime-binding-v3/erc3643-hook/bridge-artifacts.json",
}
FACTORY = "implementation/src/profiles/ERC3643HookFactory.sol"
PIN = re.compile(r"bytes32 public constant ADAPTER_CREATION_HASH = 0x([0-9a-f]{64});")
MUTANT_IDS = ("HOOK-UNAUTHORIZED-AUTHORITY-WORD", "HOOK-TERMINAL-CASE-WORD", "PARTIAL-INVALID-COMMAND-ID-WORD",
              "NATIVE-OPERATIONAL-SELECTOR")
RUNTIMES = {"TrustToken": "TrustToken.sol", "ERC3643TrustAdapter": "ERC3643TrustAdapter.sol",
            "ProfileGovernor": "ProfileGovernor.sol", "ERC3643HookAdapter": "ERC3643HookAdapter.sol",
            "ERC3643HookGovernor": "ERC3643HookGovernor.sol", "ERC3643HookCompliance": "ERC3643HookCompliance.sol",
            "ERC3643HookFactory": "ERC3643HookFactory.sol"}
ENDPOINTS = {"Native": "TrustToken", "Partial": "ERC3643TrustAdapter", "Hook": "ERC3643HookAdapter"}
FAILURES = ("TrustInvalidCommand", "TrustRejected", "TrustOperationalFailure", "TrustUnauthorized", "TrustReplay",
            "TrustTerminal")
# The fifteen cases of the probe core: expected failure (None for an accepted control) and action or reversal side.
CASES = {1: ("TrustInvalidCommand", "action"), 2: ("TrustInvalidCommand", "reversal"), 3: (None, "action"),
         4: ("TrustRejected", "action"), 5: ("TrustOperationalFailure", "action"), 6: (None, "reversal"),
         7: ("TrustRejected", "reversal"), 8: ("TrustOperationalFailure", "reversal"),
         9: ("TrustUnauthorized", "action"), 10: ("TrustUnauthorized", "reversal"), 11: ("TrustReplay", "action"),
         12: ("TrustReplay", "action"), 13: ("TrustReplay", "reversal"), 14: ("TrustTerminal", "action"),
         15: ("TrustTerminal", "reversal")}
PAIRS = {"Native": ((1, 2), (3, 4)), "Partial": ((1, 2),), "Hook": ((1, 2),)}
ARTIFACT_IDS = (("probe-receipt", "probe-receipt"), ("probe-forge-report", "forge-report"),
                *((f"mutant-{identifier}-receipt", "mutant-receipt") for identifier in MUTANT_IDS),
                *((f"mutant-{identifier}-forge-report", "forge-report") for identifier in MUTANT_IDS),
                ("frozen-build-record", "build-record"), ("load-scan", "load-scan"),
                *((f"compiled-{name}", "compiled-artifact") for name in RUNTIMES))
ARTIFACT_KINDS = dict(ARTIFACT_IDS)
COMMAND = ("python3 " + VERIFIER_PATH + " --product-root <product-root> "
           "--artifact-index <private-artifact-index.json>")
SCHEMA = "trust12-typed-failure-binding-checkpoint-v1"
STATUS = "PASS_TYPED_FAILURE_LAYOUT_AND_LOADS"
SCOPE = ("The typed failure probe deployed each of the three profile endpoints once, the Native endpoint on the shared "
         "Native test fixture, the Partial endpoint as the sealed clean-room deployment and the Hook endpoint through the "
         "pinned factory against the pinned upstream token, and each emitted endpoint runtime has the code identity of "
         "its profile template. On each endpoint it drove all six typed failures through an action and a reversal "
         "entrypoint, on the kernel entrypoints of the three endpoints and also on the two exact-use route entrypoints "
         "of the Native endpoint: 52 typed failure cases and 8 accepted controls. Every typed failure case reverted with "
         "the expected selector and a payload of the exact length that the fixed ABI reading of the runtime-link gate "
         "accepts for that selector, and its report binds to the request and the sender as the gate defines. A build of "
         "the frozen sources in an isolated copy produced every profile runtime equal to its template, and each endpoint "
         "runtime loads each of the six typed failure selectors at least once.")
LAYOUT_BOUNDARY = ("The gate binds the command identifier and a registered reason for the invalid-command, rejection "
                   "and operational-failure selectors, the sender and the authority reference for the unauthorized "
                   "selector, and the case of a forward command for the terminal selector; the replay selector and the "
                   "terminal selector of a reversal bind by selector and length only, and the third word of an "
                   "operational failure is not bound. For every bound case the reading rejects the payload with one "
                   "byte more or one byte less, and where the gate binds a word or a reason, a changed word or an "
                   "unregistered reason makes the binding fail. The probe executes at least one revert site of every "
                   "typed failure on every entrypoint pair of every endpoint, not every revert site; every typed failure "
                   "has only static parameters, so the compiler encodes the same length at every site of the same "
                   "error (A-COMPILER).")
NEGATIVE_BOUNDARY = ("Four declared mutants each change one revert site in an isolated copy: a dropped authority word and "
                     "a dropped case word of the Hook endpoint, a dropped command identifier of the Partial endpoint, "
                     "and the rejection selector in place of the operational failure of the Native endpoint. In each "
                     "mutant run every named case stops binding. A mutated Hook copy also pins its own adapter creation "
                     "code in its factory. The mutated copies have other runtimes and are never runs of the frozen "
                     "build.")
LOAD_BOUNDARY = ("A load means that the runtime puts the four selector bytes on the stack in one of three compiled "
                 "forms; it shows that the runtime can produce the selector, not on which path. Each scanned runtime "
                 "equals its template, its immutable ranges and method identifiers equal the bound bridge artifact, its "
                 "compiler settings equal the bound standard JSON input and every source it names has the bound "
                 "content; no typed failure selector is a function selector, and the recorded loads of the code "
                 "identity equal the recomputed ones offset by offset.")
REPRODUCTION_BOUNDARY = ("Metadata mode reads tracked files only: it re-reads every recorded payload with the current "
                         "reading and binding, requires every verdict, count and mutant record of this record to follow, "
                         "and compares the load record with the code identity and the bound inputs. Saved mode rehashes "
                         "the private probe, mutant, build and scan records and the seven compiled artifacts, recomputes "
                         "every probe and mutant receipt from its forge report and the scan from the compiled artifacts, "
                         "and requires them to equal the stored ones byte for byte. Neither mode reruns Foundry or the "
                         "compiler. The record states no completion of the registered-scope central closure, any general "
                         "runtime link, the independent Assurance or TRUST 1.2.")
COVERAGE = {
    "cases": {"Native": 30, "Partial": 15, "Hook": 15},
    "typedFailureCases": 52,
    "boundCases": 52,
    "acceptedControls": 8,
    "sensitivityControlsDetected": 172,
    "endpointsMatchingTemplates": 3,
    "mutantsDetected": 4,
    "runtimesScanned": 7,
    "endpointLoads": {
        "Native": {"TrustInvalidCommand": 29, "TrustOperationalFailure": 4, "TrustRejected": 3, "TrustReplay": 5,
                   "TrustTerminal": 1, "TrustUnauthorized": 3},
        "Partial": {"TrustInvalidCommand": 25, "TrustOperationalFailure": 22, "TrustRejected": 2, "TrustReplay": 2,
                    "TrustTerminal": 2, "TrustUnauthorized": 2},
        "Hook": {"TrustInvalidCommand": 25, "TrustOperationalFailure": 22, "TrustRejected": 2, "TrustReplay": 2,
                 "TrustTerminal": 2, "TrustUnauthorized": 3},
    },
}
LOAD_CRITERIA = ("every-endpoint-loads-every-typed-failure-selector", "no-typed-failure-selector-is-a-function-selector",
                 "recorded-loads-equal-the-recomputed-loads")
NONCLAIM_KEYS = ("proofOverEveryAcceptedExecution", "everyRevertSiteExecuted", "unboundWords", "foundryRerun",
                 "compilerRerun", "registeredCentralClosure", "generalRuntimeLinks", "independentAssurance",
                 "fullTrustCompletion", "releaseOrDeployment")
EXPECTED_EVIDENCE_DIGEST = '8bc094016226e40b4d6673b5568f33e95acfb146a60770654f747ef38dc9ee0c'
PUBLIC_KEYS = {"schema", "status", "scope", "layoutBoundary", "negativeBoundary", "loadBoundary",
               "reproductionBoundary", "coverage", "probe", "mutants", "loads", "productIdentity", "artifacts",
               "rehashVerifier", "nonclaims"}
ROW_KEYS = {"index", "profile", "entrypoint", "expected", "sender", "commandId", "authorityRef", "caseId", "ok",
            "returnData", "verdict", "outcome", "reason", "returnBytes", "controls"}
HEX64 = re.compile(r"[0-9a-f]{64}")
PRIVATE = re.compile(r"(?i)[A-Za-z]:[\\/]|/mnt/|/h[o]me/|\\\\|(?<![A-Za-z0-9])(?:G|M|FV|RL)[0-9]+(?![0-9])")


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def text_digest(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


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


def privacy_boundary(checkpoint):
    encoded = json.dumps(checkpoint, ensure_ascii=False)
    require(encoded.isascii() and not PRIVATE.search(encoded), "Private or non-English metadata")


def file_identity(product, relative):
    path = (product / relative).resolve()
    require(path.is_file() and path.is_relative_to(product), "Missing product file: " + relative)
    return {"path": relative, "bytes": path.stat().st_size, "sha256": digest(path)}


def load_tools(product):
    """The probe runner, the reading and the load scanner of the product tree, refusing modules from elsewhere."""
    directory = (product / TOOL_DIRECTORY).resolve()
    sys.dont_write_bytecode = True
    if str(directory) not in sys.path:
        sys.path.insert(0, str(directory))
    runner = importlib.import_module("run_typed_failure_probe")
    reading = importlib.import_module("typed_failure_report")
    scanner = importlib.import_module("code_identity_v2")
    for name, relative in MODULES.items():
        module = sys.modules.get(name)
        require(module is not None and Path(inspect.getfile(module)).resolve() == (product / relative).resolve(),
                "Imported probe module differs from the product file: " + name)
    return runner, reading, scanner


def expected_cases():
    """(profile, index) to (expected failure, entrypoint code) of every case the probe core runs."""
    table = {}
    for profile, pairs in PAIRS.items():
        for position, (action, reversal) in enumerate(pairs, start=1):
            for number, (failure, side) in CASES.items():
                table[(profile, 100 * position + number)] = (failure, action if side == "action" else reversal)
    return table


def case_of(row):
    return {"index": row["index"], "profile": row["profile"], "entrypoint": row["entrypoint"],
            "expected": row["expected"], "sender": int(row["sender"], 16), "commandId": int(row["commandId"], 16),
            "authorityRef": int(row["authorityRef"], 16), "caseId": int(row["caseId"], 16), "ok": row["ok"],
            "returnData": bytes.fromhex(row["returnData"].removeprefix("0x"))}


def probe_coverage(rows):
    typed = [row for row in rows if row["expected"] is not None]
    return {
        "cases": {profile: sum(1 for row in rows if row["profile"] == profile) for profile in ENDPOINTS},
        "typedFailureCases": len(typed),
        "boundCases": sum(1 for row in typed if row["verdict"] == "BOUND"),
        "acceptedControls": sum(1 for row in rows if row["verdict"] == "CONTROL_ACCEPTED"),
        "sensitivityControlsDetected": sum(sum(1 for flag in row.get("controls", {}).values() if flag) for row in typed),
    }


def public_summary(probe, mutants, scan, build_record):
    """The public part of the record that follows from the receipts, the scan and the build record."""
    rows = probe["rows"]
    first = next(iter(scan["runtimes"].values()))["build"]
    loads = {
        "forgeVersion": build_record.get("forgeVersion"),
        "build": {key: value for key, value in first.items() if key != "sourceKeccak256"},
        "runtimes": {name: {"runtimeSha256": item["runtimeSha256"], "runtimeBytes": item["runtimeBytes"],
                            "artifactSha256": item["artifact"]["sha256"], "loadCounts": item["loadCounts"],
                            "typedFailureSelectorLoads": item["typedFailureSelectorLoads"],
                            "sourceKeccak256": item["build"]["sourceKeccak256"]}
                     for name, item in scan["runtimes"].items()},
        "endpointLoads": {profile: row["loads"] for profile, row in scan["endpointLoads"].items()},
        "criteria": {item["id"]: "PASS" if item["holds"] else "FAIL" for item in scan["criteria"]},
    }
    coverage = {**probe_coverage(rows),
                "endpointsMatchingTemplates": sum(1 for item in probe["codeIdentity"].values() if item["matches"]),
                "mutantsDetected": sum(1 for item in mutants if item["status"] == "MUTANT_DETECTED"),
                "runtimesScanned": len(scan["runtimes"]),
                "endpointLoads": loads["endpointLoads"]}
    return {
        "coverage": coverage,
        "probe": {"status": probe["status"], "forgeVersion": probe["forgeVersion"], "suites": probe["suites"],
                  "codeIdentity": probe["codeIdentity"], "rows": rows},
        "mutants": [{"id": item["mutant"]["id"], "status": item["status"], "cases": item["mutant"]["cases"],
                     "missingCases": item["mutant"]["missingCases"], "mutation": item["run"]["mutation"]}
                    for item in mutants],
        "loads": loads,
    }


def build_checkpoint(summary, product, artifacts):
    """The record before its verifier identity is added; the writer pins its digest in this verifier."""
    return {"schema": SCHEMA, "status": STATUS, "scope": SCOPE, "layoutBoundary": LAYOUT_BOUNDARY,
            "negativeBoundary": NEGATIVE_BOUNDARY, "loadBoundary": LOAD_BOUNDARY,
            "reproductionBoundary": REPRODUCTION_BOUNDARY, **summary,
            "productIdentity": {key: file_identity(product, path) for key, path in IDENTITY_PATHS.items()},
            "artifacts": artifacts, "rehashVerifier": None, "nonclaims": {key: True for key in NONCLAIM_KEYS}}


def check_probe(probe, runner, reading):
    require(probe["status"] == "PROBE_RECORDED_ALL_BOUND", "Probe status differs")
    require(probe["suites"] == {f"{profile}TypedFailureProbe.test{profile}TypedFailureProbe()": "Success"
                                for profile in ENDPOINTS}, "Probe suites differ")
    require(set(probe["codeIdentity"]) == set(ENDPOINTS) and all(
        item["endpoint"] == ENDPOINTS[profile] and item["matches"] is True for profile, item in probe["codeIdentity"].items()),
        "Probe endpoint code identity differs")
    rows = probe["rows"]
    table = expected_cases()
    require(isinstance(rows, list) and sorted((row["profile"], row["index"]) for row in rows) == sorted(table)
            and len(rows) == len(table), "Probe cases differ from the probe core")
    constants = reading.formal_constants()
    for row in rows:
        require(set(row) <= ROW_KEYS and table[(row["profile"], row["index"])] == (row["expected"], row["entrypoint"]),
                "Probe case differs: " + str(row.get("index")))
        evaluated = runner.evaluate(case_of(row), constants)
        require(all(row.get(key) == value for key, value in evaluated.items()) and set(row) - {
            "index", "profile", "entrypoint", "expected", "sender", "commandId", "authorityRef", "caseId", "ok",
            "returnData"} == set(evaluated), "Probe verdict does not follow from the recorded payload: " + str(row["index"]))
        require(row["verdict"] in {"BOUND", "CONTROL_ACCEPTED"}, "Probe case is not bound: " + str(row["index"]))
    covered = runner.coverage(rows)
    require(all(flags["action"] and flags["reversal"] for profile in covered.values() for flags in profile.values()),
            "A typed failure is not bound on an action and a reversal entrypoint")


def check_mutants(mutants, product):
    declared = {row["id"]: row for row in read_json(product / IDENTITY_PATHS["mutantList"])["mutants"]}
    require(list(declared) == list(MUTANT_IDS) and [item.get("id") for item in mutants] == list(MUTANT_IDS),
            "Mutant inventory differs")
    pins = PIN.findall((product / FACTORY).read_text(encoding="utf-8"))
    require(len(pins) == 1, "Factory adapter pin not found exactly once")
    for item in mutants:
        source = declared[item["id"]]
        require(set(item) == {"id", "status", "cases", "missingCases", "mutation"} and item["status"] == "MUTANT_DETECTED"
                and item["missingCases"] == [] and sorted(item["cases"]) == sorted(str(case) for case in source["cases"])
                and all(verdict not in {"BOUND", "CONTROL_ACCEPTED"} for verdict in item["cases"].values()),
                "Mutant record differs: " + item["id"])
        text = (product / source["file"]).read_text(encoding="utf-8")
        mutation = item["mutation"]
        expected = {"file": source["file"], "occurrences": source["expectedOccurrences"], "beforeSha256": text_digest(text),
                    "afterSha256": text_digest(text.replace(source["old"], source["new"]))}
        require(text.count(source["old"]) == source["expectedOccurrences"]
                and {key: mutation.get(key) for key in expected} == expected,
                "Mutation is not the declared change of the current source: " + item["id"])
        if source.get("repinAdapterCreationHash"):
            repin = mutation.get("repin")
            require(isinstance(repin, dict) and set(repin) == {"file", "beforePin", "afterPin", "reason"}
                    and repin["file"] == FACTORY and repin["beforePin"] == "0x" + pins[0]
                    and re.fullmatch(r"0x[0-9a-f]{64}", str(repin["afterPin"])) and repin["afterPin"] != repin["beforePin"],
                    "Factory pin record differs: " + item["id"])
            require(set(mutation) == set(expected) | {"repin"}, "Mutation record keys differ: " + item["id"])
        else:
            require(set(mutation) == set(expected), "Mutation record keys differ: " + item["id"])


def check_loads(loads, product, scanner):
    identity = read_json(product / IDENTITY_PATHS["codeIdentity"])
    recorded = identity["compiledScan"]
    require(recorded["status"] == "RECOMPUTED", "The code identity holds no compiled scan")
    templates = {item["contract"]: item["runtimeTemplate"] for profile in identity["profiles"].values()
                 for item in profile["runtimes"]}
    require(set(loads["runtimes"]) == set(RUNTIMES) == set(templates), "Scanned runtime set differs")
    forms = scanner.FORMS
    for name, item in loads["runtimes"].items():
        require(item["runtimeSha256"] == templates[name]["sha256"] and item["runtimeBytes"] == templates[name]["bytes"]
                and item["runtimeSha256"] == recorded["runtimes"][name]["runtimeSha256"],
                "Scanned runtime is not the template: " + name)
        require(item["typedFailureSelectorLoads"] == recorded["runtimes"][name]["typedFailureSelectorLoads"],
                "Recorded loads differ from the code identity: " + name)
        require(item["loadCounts"] == {failure: sum(len(offsets[form]) for form in forms)
                                       for failure, offsets in item["typedFailureSelectorLoads"].items()},
                "Load counts do not follow from the loads: " + name)
        require(isinstance(item["artifactSha256"], str) and HEX64.fullmatch(item["artifactSha256"]) is not None,
                "Artifact hash differs: " + name)
    require(loads["endpointLoads"] == {profile: loads["runtimes"][endpoint]["loadCounts"]
                                       for profile, endpoint in ENDPOINTS.items()}
            and all(count >= 1 for row in loads["endpointLoads"].values() for count in row.values()),
            "Endpoint loads differ")
    require(loads["criteria"] == {identifier: "PASS" for identifier in LOAD_CRITERIA}, "A load criterion is not PASS")
    solc = read_json(product / IDENTITY_PATHS["runtimeIdentity"])["compiler"]["solc"]
    build = loads["build"]
    require(str(build["compiler"]).split("+", 1)[0] == solc, "Compiler version differs from the runtime identity")
    for key in ("nativeInput", "partialInput", "hookInput"):
        bound = read_json(product / IDENTITY_PATHS[key])["settings"]
        require(build["settings"] == {name: bound.get(name) for name in scanner.SETTINGS}
                and build["metadata"] == {name: bound["metadata"].get(name) for name in scanner.METADATA_SETTINGS},
                "Compiler settings differ from the bound input: " + key)


def check_artifacts(artifacts):
    require(isinstance(artifacts, list) and [row.get("id") for row in artifacts] == list(ARTIFACT_KINDS)
            and all(isinstance(row, dict) and set(row) == {"id", "kind", "bytes", "sha256"}
                    and row["kind"] == ARTIFACT_KINDS[row["id"]] and type(row["bytes"]) is int and row["bytes"] > 0
                    and isinstance(row["sha256"], str) and HEX64.fullmatch(row["sha256"]) is not None for row in artifacts),
            "Artifact inventory differs")
    hashes = {row["id"]: row["sha256"] for row in artifacts}
    return hashes


def public_contract(checkpoint, product):
    require(set(checkpoint) == PUBLIC_KEYS and checkpoint["schema"] == SCHEMA and checkpoint["status"] == STATUS,
            "Checkpoint contract differs")
    privacy_boundary(checkpoint)
    require(payload_digest(checkpoint) == EXPECTED_EVIDENCE_DIGEST, "Reviewed evidence digest differs")
    require(checkpoint["scope"] == SCOPE and checkpoint["layoutBoundary"] == LAYOUT_BOUNDARY
            and checkpoint["negativeBoundary"] == NEGATIVE_BOUNDARY and checkpoint["loadBoundary"] == LOAD_BOUNDARY
            and checkpoint["reproductionBoundary"] == REPRODUCTION_BOUNDARY, "Public scope or boundary differs")
    require(checkpoint["nonclaims"] == {key: True for key in NONCLAIM_KEYS}, "All bounded nonclaims required")
    require(same_json(checkpoint["coverage"], COVERAGE), "Coverage differs from the reviewed counts")
    require(checkpoint["productIdentity"] == {key: file_identity(product, path) for key, path in IDENTITY_PATHS.items()},
            "Product identity differs from the current files")
    hashes = check_artifacts(checkpoint["artifacts"])
    for name, item in checkpoint["loads"]["runtimes"].items():
        require(item["artifactSha256"] == hashes.get(f"compiled-{name}"), "Scanned artifact is not the private one: " + name)
    verifier = checkpoint["rehashVerifier"]
    require(isinstance(verifier, dict) and set(verifier) == {"path", "bytes", "sha256", "command"}
            and verifier["command"] == COMMAND
            and {key: verifier[key] for key in ("path", "bytes", "sha256")} == file_identity(product, VERIFIER_PATH),
            "Current verifier differs")
    runner, reading, scanner = load_tools(product)
    require(checkpoint["probe"]["status"] == "PROBE_RECORDED_ALL_BOUND", "Probe status differs")
    check_probe(checkpoint["probe"], runner, reading)
    check_mutants(checkpoint["mutants"], product)
    check_loads(checkpoint["loads"], product, scanner)
    derived = {**probe_coverage(checkpoint["probe"]["rows"]),
               "endpointsMatchingTemplates": sum(1 for item in checkpoint["probe"]["codeIdentity"].values() if item["matches"]),
               "mutantsDetected": sum(1 for item in checkpoint["mutants"] if item["status"] == "MUTANT_DETECTED"),
               "runtimesScanned": len(checkpoint["loads"]["runtimes"]),
               "endpointLoads": checkpoint["loads"]["endpointLoads"]}
    require(same_json(derived, checkpoint["coverage"]), "Coverage does not follow from the record")
    return runner, reading, scanner


def private_file(base, relative, label):
    require(isinstance(relative, str) and relative and not PurePosixPath(relative).is_absolute()
            and ".." not in PurePosixPath(relative).parts and ":" not in relative, "Private index path differs: " + label)
    path = (base / relative).resolve()
    require(path.is_relative_to(base) and path.is_file(), "Private artifact missing: " + label)
    return path


def recomputed_receipt(runner, files, role, product, mutant):
    receipt_bytes = files[f"{role}-receipt" if role != "probe" else "probe-receipt"].read_bytes()
    receipt = json.loads(receipt_bytes.decode("utf-8"))
    report_path = files[f"{role}-forge-report" if role != "probe" else "probe-forge-report"]
    require(receipt.get("forgeReportSha256") == digest(report_path), "Receipt names another forge report: " + role)
    report = read_json(report_path)
    recomputed = runner.record(report, receipt["run"], receipt["forgeVersion"], receipt["forgeReportSha256"], mutant, product)
    require(runner.dump_json(recomputed).encode("utf-8") == receipt_bytes, "Receipt does not follow from its forge report: " + role)
    return receipt


def verify_checkpoint(checkpoint, index_path, product):
    product, index_path = product.resolve(), index_path.resolve()
    runner, reading, scanner = public_contract(checkpoint, product)
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
    probe = recomputed_receipt(runner, files, "probe", product, None)
    mutant_list = product / IDENTITY_PATHS["mutantList"]
    mutants = [recomputed_receipt(runner, files, f"mutant-{identifier}", product,
                                  runner.mutant_definition(mutant_list, identifier)) for identifier in MUTANT_IDS]
    artifacts_dirs = {files[f"compiled-{name}"].parent.parent for name in RUNTIMES}
    require(len(artifacts_dirs) == 1 and all(files[f"compiled-{name}"].relative_to(next(iter(artifacts_dirs))).as_posix()
                                            == f"{source}/{name}.json" for name, source in RUNTIMES.items()),
            "Compiled artifacts are not one Foundry output directory")
    build_record = scanner.load_build_record(files["frozen-build-record"])
    scan = scanner.build(next(iter(artifacts_dirs)), "closure", product / IDENTITY_PATHS["codeIdentity"], build_record)
    require(scanner.dump_json(scan).encode("utf-8") == files["load-scan"].read_bytes(),
            "Load scan recomputation differs from the stored scan")
    summary = public_summary(probe, mutants, scan, build_record)
    for key, value in summary.items():
        require(same_json(checkpoint[key], value), "Public record differs from the recomputed records: " + key)
    for row in checkpoint["artifacts"]:
        require(digest(files[row["id"]]) == row["sha256"], "Private artifact changed while checked: " + row["id"])
    for key, path in IDENTITY_PATHS.items():
        require(digest(product / path) == checkpoint["productIdentity"][key]["sha256"],
                "Product identity changed while checked: " + key)
    require(digest(verifier_file) == checkpoint["rehashVerifier"]["sha256"], "Verifier changed while checked")
    return {"schema": "trust12-typed-failure-binding-rehash-v1", "status": "PASS_TYPED_FAILURE_RECORDS_RECOMPUTED",
            "cases": len(probe["rows"]), "mutants": len(mutants), "runtimesScanned": len(scan["runtimes"]),
            "foundryRerun": False, "compilerRerun": False, "registeredCentralClosureDischarged": False,
            "nonclaim": REPRODUCTION_BOUNDARY}


def metadata_only(checkpoint, product):
    public_contract(checkpoint, product.resolve())
    return {"status": "PASS_PUBLIC_METADATA_ONLY", "payloadsReread": True, "savedArtifactsVerified": False,
            "foundryRerun": False, "nonclaims": sorted(NONCLAIM_KEYS)}


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
    except (RuntimeError, OSError, ValueError, KeyError, TypeError, AttributeError, ImportError) as error:
        raise SystemExit(f"FAIL: {error}")
