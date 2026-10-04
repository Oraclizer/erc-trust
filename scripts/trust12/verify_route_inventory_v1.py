#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Check the public record of the TRUST 1.2 route inventory and, with the private run records, recompute it.

Metadata mode, which the required gate runs, reads tracked files only. It checks that the record is the reviewed
one, rebuilds the route inventory in closure mode from the current product files with the disposition test results
and the probe rows that the record carries, and requires every public field of the record to follow from that build.
Saved mode additionally rehashes the private disposition test receipt, its forge report, the malformed probe receipt
and the stored inventory named through a private index, recomputes the test receipt from the forge report, rebuilds
the inventory from the private receipts and requires it to equal the stored one byte for byte. Neither mode reruns
Foundry.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import importlib
import inspect
import json
from pathlib import Path, PurePosixPath
import re
import sys

CHECKPOINT_PATH = "evidence/trust12/runtime-link/tail-preparation/route-inventory-checkpoint-v1.json"
VERIFIER_PATH = "scripts/trust12/verify_route_inventory_v1.py"
TOOL_DIRECTORY = "scripts/trust12/tail-preparation"
MODULES = {
    "route_inventory_v2": "scripts/trust12/tail-preparation/route_inventory_v2.py",
    "route_inventory": "scripts/trust12/tail-preparation/route_inventory.py",
    "tail_common": "scripts/trust12/tail-preparation/tail_common.py",
    "run_route_disposition_tests": "scripts/trust12/tail-preparation/run_route_disposition_tests.py",
}
ARTIFACT_KINDS = {"route-inventory": "inventory", "route-disposition-run": "test-run-receipt",
                  "route-disposition-report": "forge-report", "malformed-probe-receipt": "probe-receipt"}
COMMAND = ("python3 " + VERIFIER_PATH + " --product-root <product-root> "
           "--artifact-index <private-artifact-index.json>")
SCHEMA = "trust12-route-inventory-checkpoint-v1"
STATUS = "PASS_ROUTE_INVENTORY_CLOSED"
CRITERIA = ("hook-class-record-accepted", "every-selector-has-a-normative-class",
            "every-state-changing-route-outside-the-typed-commands-is-disposed",
            "unknown-selectors-revert-empty-on-every-endpoint")
STATES = ("IN_RUNTIME_LINK_DOMAIN", "OUTSIDE_NON_MUTATING", "OUTSIDE_DISPOSED", "OUTSIDE_DISPOSITION_OPEN",
          "OUTSIDE_REQUIRES_DISPOSITION")
SCOPE = ("The route inventory classifies every public and external entrypoint of the seven profile runtimes of TRUST "
         "1.2, 108 selectors read from the tracked compiled artifacts of the runtime binding: the Native and Partial "
         "runtimes by the route tables of the formal runtime bridge and the four Hook runtimes by the route class table "
         "of decision 14. Eight are the typed command entrypoints that the malformed input catalog lists, 80 are view "
         "or pure functions, and each of the other 20 has a disposition record that a closed obligation row or an "
         "accepted decision record of its own runtime justifies and that a passed test executes on its own runtime. No "
         "runtime declares a receive or fallback function, and the recorded malformed probe shows, for its "
         "unknown-selector request on each of the three endpoints, a revert with an empty payload and no log, external "
         "call or committed write.")
CLASS_BOUNDARY = ("A class names the role of an entrypoint. The inventory checks it against the ABI state mutability "
                  "of the compiled artifact and, for a Hook adapter or governor selector that also exists on the "
                  "Partial runtime, against the class of that counterpart. A view or pure function counts as "
                  "non-mutating because the compiler forbids state changes in it, which keeps the compiler a trusted "
                  "assumption (A-COMPILER). The pinned upstream ERC-3643 token of the Hook profile is a dependency and "
                  "is not classified; its behavior remains the assumption A-EXTERNAL.")
DISPOSITION_BOUNDARY = ("A disposition record names the callers, the writes and the reason a route lies outside the "
                        "runtime-link relation, and cites ledger rows, quoted decision sentences, source lines with "
                        "their exact occurrence counts, tests and mutation receipts that the inventory checks against "
                        "the current files. A test counts as an execution only when it passed in a recorded run: the "
                        "recorded Foundry results of the implementation suite, which bind the current implementation "
                        "sources and tests, for the tests under implementation/test, and a run of the disposition tests "
                        "in an isolated copy, which binds the current route test files and the current implementation "
                        "sources and tests by their hashes, for the tests under "
                        "scripts/trust12/tail-preparation/route-dispositions. A test executes one deployment with "
                        "chosen callers and inputs; it is not a proof over every caller, state or input.")
UNMATCHED_BOUNDARY = ("The catalogued unknown-selector request of each endpoint is the selector 0xffffffff followed by "
                      "the calldata body of a FREEZE action request, 644 bytes in all, and the probe rows that this "
                      "record carries are the rows of those requests. The record binds the probe receipt by its SHA-256, "
                      "which the tracked out-of-spec probe summary also records, and the probe inputs of that summary "
                      "have the same root as the current files under its six paths. The selector 0xffffffff is a "
                      "function selector of none of the seven runtimes. Other selectors outside the dispatch lists, and "
                      "the governor, Compliance and factory runtimes, rely on the compiled dispatcher without a receive "
                      "or fallback function, not on a probe.")
REPRODUCTION_BOUNDARY = ("Metadata mode reads tracked files only: it rebuilds the inventory in closure mode from the "
                         "current files with the test results and the probe rows that this record carries, and requires "
                         "every public field of this record to follow from that build. Saved mode rehashes the private "
                         "disposition test receipt, its forge report, the private malformed probe receipt and the stored "
                         "inventory, recomputes the test receipt from the forge report, rebuilds the inventory from the "
                         "private receipts and requires it to equal the stored one byte for byte and this record to "
                         "follow from it. Neither mode reruns Foundry. The record states no completion of the "
                         "registered-scope central closure, any general runtime link, the independent Assurance or "
                         "TRUST 1.2.")
COVERAGE = {
    "runtimes": 7,
    "selectors": 108,
    "dispositionStates": {"IN_RUNTIME_LINK_DOMAIN": 8, "OUTSIDE_NON_MUTATING": 80, "OUTSIDE_DISPOSED": 20,
                          "OUTSIDE_DISPOSITION_OPEN": 0, "OUTSIDE_REQUIRES_DISPOSITION": 0},
    "dispositionRecords": 20,
    "dispositionsComplete": 20,
    "justifiedByClosedRow": 17,
    "justifiedOnlyByDecision": 3,
    "executedInRecordedSuite": 15,
    "executedInDispositionRun": 10,
    "dispositionRunTests": 8,
    "unknownSelectorEndpoints": 3,
}
NONCLAIM_KEYS = ("proofOverEveryCallerStateAndInput", "upstreamTokenClassification", "compilerDispatcher",
                 "foundryRerun", "registeredCentralClosure", "generalRuntimeLinks", "independentAssurance",
                 "fullTrustCompletion", "releaseOrDeployment")
EXPECTED_EVIDENCE_DIGEST = '5bacd56b0e4cc7b995dca5e62e88996929d12bdc8246d3330189f1f1248c34a9'
PUBLIC_KEYS = {"schema", "status", "scope", "classBoundary", "dispositionBoundary", "unmatchedBoundary",
               "reproductionBoundary", "coverage", "criteria", "routes", "dispositions", "unmatchedSelectors",
               "dispositionRun", "inputs", "artifacts", "rehashVerifier", "nonclaims"}
PROBE_ROW_KEYS = ("id", "profile", "class", "verdict")
OBSERVED_KEYS = ("outcome", "returnBytes", "logs", "committedWrites", "externalAccesses")
HEX64 = re.compile(r"[0-9a-f]{64}")
PRIVATE = re.compile(r"(?i)[A-Za-z]:[\\/]|/mnt/|/h[o]me/|\\\\|(?<![A-Za-z0-9])(?:G|M|FV|RL)[0-9]+(?![0-9])")


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


def privacy_boundary(checkpoint):
    encoded = json.dumps(checkpoint, ensure_ascii=False)
    require(encoded.isascii() and not PRIVATE.search(encoded), "Private or non-English metadata")


def file_identity(product, relative):
    path = (product / relative).resolve()
    require(path.is_file() and path.is_relative_to(product), "Missing product file: " + relative)
    return {"path": relative, "bytes": path.stat().st_size, "sha256": digest(path)}


def load_tool(product):
    """The route inventory of the product tree, with its readers, refusing modules loaded from anywhere else."""
    directory = (product / TOOL_DIRECTORY).resolve()
    sys.dont_write_bytecode = True
    if str(directory) not in sys.path:
        sys.path.insert(0, str(directory))
    tool = importlib.import_module("route_inventory_v2")
    runner = importlib.import_module("run_route_disposition_tests")
    for name, relative in MODULES.items():
        module = sys.modules.get(name)
        require(module is not None and Path(inspect.getfile(module)).resolve() == (product / relative).resolve(),
                "Imported inventory module differs from the product file: " + name)
    return tool, runner


def probe_row(row):
    return {**{key: row[key] for key in PROBE_ROW_KEYS}, "observed": {key: row["observed"][key] for key in OBSERVED_KEYS}}


def probe_from_record(checkpoint):
    """The probe evidence the record carries, in the form the inventory reads."""
    unmatched = checkpoint["unmatchedSelectors"]
    artifact = next(item for item in checkpoint["artifacts"] if item["id"] == "malformed-probe-receipt")
    return {"sha256": artifact["sha256"], "status": unmatched["receiptStatus"], "rows": unmatched["rows"]}


def run_from_record(checkpoint):
    """The disposition test run the record carries, in the form the inventory reads."""
    run = checkpoint["dispositionRun"]
    artifact = next(item for item in checkpoint["artifacts"] if item["id"] == "route-disposition-run")
    return {"sha256": artifact["sha256"], "status": run["status"], "forgeVersion": run["forgeVersion"],
            "implementationRootSha256": run["implementationRootSha256"], "sources": run["sources"],
            "tests": run["tests"]}


def derive_coverage(inventory, run):
    states = Counter(route["disposition"] for runtime in inventory["runtimes"] for route in runtime["routes"])
    records = inventory["dispositionRecords"]

    def justified_by(record, kind):
        return any(item.get("justifies") and item["type"] == kind for item in record["references"])

    def executed_in(record, run_kind):
        return any(item["type"] == "test" and item["run"] == run_kind and item["executesThisRuntime"]
                   for item in record["references"])

    return {
        "runtimes": len(inventory["runtimes"]),
        "selectors": sum(len(runtime["routes"]) for runtime in inventory["runtimes"]),
        "dispositionStates": {state: states.get(state, 0) for state in STATES},
        "dispositionRecords": len(records),
        "dispositionsComplete": sum(1 for record in records if record["complete"]),
        "justifiedByClosedRow": sum(1 for record in records if justified_by(record, "ledgerRow")),
        "justifiedOnlyByDecision": sum(1 for record in records
                                       if justified_by(record, "decision") and not justified_by(record, "ledgerRow")),
        "executedInRecordedSuite": sum(1 for record in records if executed_in(record, "recorded-foundry-suite")),
        "executedInDispositionRun": sum(1 for record in records if executed_in(record, "route-disposition-run")),
        "dispositionRunTests": len(run["tests"]),
        "unknownSelectorEndpoints": sum(1 for item in inventory["unmatchedSelectors"]["profiles"].values() if item["holds"]),
    }


def public_summary(inventory, probe, run):
    """The public part of the record that follows from an inventory and the two recorded runs."""
    routes = [{"runtime": runtime["contract"], "signature": route["signature"], "selector": route["selector"],
               "class": route["routeClass"], "classSource": route["classSource"], "disposition": route["disposition"],
               "kind": route.get("dispositionKind")}
              for runtime in inventory["runtimes"] for route in runtime["routes"]]
    dispositions = [{"route": record["route"], "kind": record["kind"],
                     "justifiedBy": sorted(item.get("row") or item.get("path") for item in record["references"]
                                           if item.get("justifies")),
                     "executedBy": [{"run": item["run"], "suite": item["suite"], "test": item["test"]}
                                    for item in record["references"]
                                    if item["type"] == "test" and item["executesThisRuntime"]]}
                    for record in inventory["dispositionRecords"]]
    unmatched = inventory["unmatchedSelectors"]
    return {
        "coverage": derive_coverage(inventory, run),
        "criteria": {item["id"]: "PASS" if item["holds"] else "FAIL" for item in inventory["closure"]["criteria"]},
        "routes": routes,
        "dispositions": dispositions,
        "unmatchedSelectors": {"dispatcherSelector": unmatched["dispatcherSelector"],
                               "probeInputsRoot": unmatched["probeInputsRoot"]["current"],
                               "receiptStatus": probe["status"],
                               "rows": [probe_row(row) for row in sorted(probe["rows"], key=lambda row: row["id"])]},
        "dispositionRun": {"status": run["status"], "forgeVersion": run["forgeVersion"],
                           "implementationRootSha256": run["implementationRootSha256"], "sources": run["sources"],
                           "tests": run["tests"]},
        "inputs": inventory["inputs"],
    }


def build_checkpoint(summary, artifacts):
    """The record before its verifier identity is added; the writer pins its digest in this verifier."""
    return {"schema": SCHEMA, "status": STATUS, "scope": SCOPE, "classBoundary": CLASS_BOUNDARY,
            "dispositionBoundary": DISPOSITION_BOUNDARY, "unmatchedBoundary": UNMATCHED_BOUNDARY,
            "reproductionBoundary": REPRODUCTION_BOUNDARY, **summary, "artifacts": artifacts, "rehashVerifier": None,
            "nonclaims": {key: True for key in NONCLAIM_KEYS}}


def check_artifacts(artifacts):
    require(isinstance(artifacts, list) and [row.get("id") for row in artifacts] == list(ARTIFACT_KINDS)
            and all(isinstance(row, dict) and set(row) == {"id", "kind", "bytes", "sha256"}
                    and row["kind"] == ARTIFACT_KINDS[row["id"]] and type(row["bytes"]) is int and row["bytes"] > 0
                    and isinstance(row["sha256"], str) and HEX64.fullmatch(row["sha256"]) is not None for row in artifacts),
            "Artifact inventory differs")


def public_contract(checkpoint, product):
    require(set(checkpoint) == PUBLIC_KEYS and checkpoint["schema"] == SCHEMA and checkpoint["status"] == STATUS,
            "Checkpoint contract differs")
    privacy_boundary(checkpoint)
    require(payload_digest(checkpoint) == EXPECTED_EVIDENCE_DIGEST, "Reviewed evidence digest differs")
    require(checkpoint["scope"] == SCOPE and checkpoint["classBoundary"] == CLASS_BOUNDARY
            and checkpoint["dispositionBoundary"] == DISPOSITION_BOUNDARY
            and checkpoint["unmatchedBoundary"] == UNMATCHED_BOUNDARY
            and checkpoint["reproductionBoundary"] == REPRODUCTION_BOUNDARY, "Public scope or boundary differs")
    require(checkpoint["nonclaims"] == {key: True for key in NONCLAIM_KEYS}, "All bounded nonclaims required")
    require(same_json(checkpoint["coverage"], COVERAGE), "Coverage differs from the reviewed counts")
    require(checkpoint["criteria"] == {identifier: "PASS" for identifier in CRITERIA}, "A closure criterion is not PASS")
    check_artifacts(checkpoint["artifacts"])
    verifier = checkpoint["rehashVerifier"]
    require(isinstance(verifier, dict) and set(verifier) == {"path", "bytes", "sha256", "command"}
            and verifier["command"] == COMMAND
            and {key: verifier[key] for key in ("path", "bytes", "sha256")} == file_identity(product, VERIFIER_PATH),
            "Current verifier differs")
    for row in checkpoint["unmatchedSelectors"]["rows"]:
        require(isinstance(row, dict) and set(row) == set(PROBE_ROW_KEYS) | {"observed"}
                and set(row["observed"]) == set(OBSERVED_KEYS), "Probe row keys differ")
    tool, runner = load_tool(product)
    probe, run = probe_from_record(checkpoint), run_from_record(checkpoint)
    inventory = tool.build("closure", probe=probe, run=run)
    require(inventory["status"] == "CLOSED_ROUTE_INVENTORY", "The inventory does not close on the current files")
    summary = public_summary(inventory, probe, run)
    for key, value in summary.items():
        require(same_json(checkpoint[key], value), "Public record differs from the rebuilt inventory: " + key)
    return tool, runner


def private_file(base, relative, label):
    require(isinstance(relative, str) and relative and not PurePosixPath(relative).is_absolute()
            and ".." not in PurePosixPath(relative).parts and ":" not in relative, "Private index path differs: " + label)
    path = (base / relative).resolve()
    require(path.is_relative_to(base) and path.is_file(), "Private artifact missing: " + label)
    return path


def verify_checkpoint(checkpoint, index_path, product):
    product, index_path = product.resolve(), index_path.resolve()
    tool, runner = public_contract(checkpoint, product)
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
    receipt_bytes = files["route-disposition-run"].read_bytes()
    receipt = json.loads(receipt_bytes.decode("utf-8"))
    require(receipt.get("forgeReportSha256") == digest(files["route-disposition-report"]),
            "Disposition test receipt names another forge report")
    report = read_json(files["route-disposition-report"])
    recomputed = runner.record(report, receipt["run"], receipt["forgeReportSha256"], product, receipt["forgeVersion"])
    require(tool.dump_json(recomputed).encode("utf-8") == receipt_bytes,
            "Disposition test receipt does not follow from its forge report")
    probe = tool.probe_evidence(files["malformed-probe-receipt"])
    run = tool.disposition_run(files["route-disposition-run"])
    rebuilt = tool.build("closure", probe=probe, run=run)
    require(tool.dump_json(rebuilt).encode("utf-8") == files["route-inventory"].read_bytes(),
            "Inventory recomputation differs from the stored inventory")
    summary = public_summary(rebuilt, probe, run)
    for key, value in summary.items():
        require(same_json(checkpoint[key], value), "Public record differs from the recomputed inventory: " + key)
    for row in checkpoint["artifacts"]:
        require(digest(files[row["id"]]) == row["sha256"], "Private artifact changed while checked: " + row["id"])
    require(digest(verifier_file) == checkpoint["rehashVerifier"]["sha256"], "Verifier changed while checked")
    return {"schema": "trust12-route-inventory-rehash-v1", "status": "PASS_ROUTE_INVENTORY_RECOMPUTED",
            "selectors": rebuilt["counts"]["selectors"], "dispositions": rebuilt["counts"]["dispositionRecords"],
            "foundryRerun": False, "registeredCentralClosureDischarged": False, "nonclaim": REPRODUCTION_BOUNDARY}


def metadata_only(checkpoint, product):
    public_contract(checkpoint, product.resolve())
    return {"status": "PASS_PUBLIC_METADATA_ONLY", "inventoryRebuilt": True, "savedArtifactsVerified": False,
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
