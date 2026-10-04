#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Check the public record of the call frames of the registered requests outside canonical form.

Metadata mode, which the required gate runs, reads tracked files only. It checks that the record is the reviewed
one; that its rows are exactly the registered requests outside canonical form of the current malformed KEVM and
KORE checkpoint; that every row reports no call frame entered inside the command segment, a call frame entered by
the endpoint elsewhere in the same graph and an empty supplied call list; that the coverage follows from the rows;
that the stage source of each profile is the one the aligned gate checkpoint binds; and that the product files it
names are the current files. Saved mode additionally rehashes the private call trace report named through a
private index, rebuilds it from the private evidence with the current trace tool, requires the rebuilt report to
equal the stored one byte for byte and requires the public record to follow from it. Neither mode runs a prover, a
symbolic execution or a kernel session.
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

CHECKPOINT_PATH = "evidence/trust12/runtime-link/malformed/call-trace-checkpoint-v1.json"
VERIFIER_PATH = "scripts/trust12/verify_malformed_call_trace_v1.py"
TOOL_DIRECTORY = "scripts/trust12/tail-preparation"
IDENTITY_PATHS = {
    "traceTool": "scripts/trust12/tail-preparation/malformed_call_trace.py",
    "malformedKevmKoreCheckpoint": "evidence/trust12/runtime-link/malformed/kevm-kore-checkpoint-v1.json",
    "alignedGateCheckpoint": "evidence/trust12/runtime-link/malformed/aligned-gate-checkpoint-v1.json",
    "canonicalFormDecision": "spec/decisions/12-requests-outside-canonical-form.md",
}
ARTIFACT_KINDS = {"call-trace-report": "report"}
COMMAND = ("python3 " + VERIFIER_PATH + " --product-root <product-root> --evidence <evidence-root> "
           "--stage-index <aligned-gate-artifact-index.json> --artifact-index <private-artifact-index.json>")
PROFILES = ("Native", "Partial", "Hook")
CATALOG_PROFILES = {"native": "Native", "partial": "Partial", "hook": "Hook"}
STAGE_ROLES = {"Native": "native-aligned-source", "Partial": "partial-aligned-source", "Hook": "hook-aligned-source"}
SCHEMA = "trust12-malformed-call-trace-checkpoint-v1"
STATUS = "PASS_MALFORMED_SUPPLIED_CALL_LISTS_MATCH_PROOF_GRAPHS"
SCOPE = ("For each of the 42 registered requests outside canonical form (Native 16, Partial 13, Hook 13), the stored "
         "KEVM proof graph of its certificate enters no call frame between the command entry and the return to the "
         "calling frame: that segment is one chain of rewrite edges with no branch and no cover, every node of it "
         "before the return executes the endpoint at the call depth of the entry node, and the return node executes "
         "the caller one call depth higher up. The kernel stages that relate these requests to the model supply an "
         "empty external call list for each of them, and every external call list that those stage sources write is "
         "empty, so the supplied list equals the list read from the graph.")
GRAPH_BOUNDARY = ("The proof graphs record call frames as graph nodes. In every one of these graphs the calls that the "
                  "endpoint makes outside the command segment appear in the node inventory as nodes one call depth "
                  "deeper (24 in each Native graph, 6 in each Partial graph and 146 in each Hook graph); a call inside "
                  "the segment would appear in the same way. That the pinned K, KEVM and Kontrol tools build each graph "
                  "with a node at every call is part of the assumption A-KEVM-TOOLCHAIN. For every segment node and for "
                  "one call frame node of each graph, the call depth, the executing account and the caller are read from "
                  "the rehashed stored node file and compared with the node inventory, which the boundary record of the "
                  "certificate binds by hash; the graph is not re-executed.")
STAGE_BOUNDARY = ("The kernel stages still take the external call list as a supplied field, and they define the post "
                  "world and logs of each record as its recorded pre-call world and logs. This record checks the "
                  "supplied call list against the proof graph with a tool outside the kernel; the kernel derives neither "
                  "the call list nor the post world from an execution trace.")
REPRODUCTION_BOUNDARY = ("Metadata mode reads tracked files only and checks this record against the current product "
                         "files. Saved mode rehashes the private call trace report, rebuilds it with the current trace tool "
                         "from the stored proof graphs, node files, boundary records, node inventories and stage sources, "
                         "and requires the rebuilt report to equal the stored one byte for byte and this record to follow "
                         "from it. Neither mode runs a prover, a symbolic execution or a kernel session, and the record "
                         "states no completion of the malformed branch, the registered-scope central closure, any general "
                         "runtime link, the independent Assurance or TRUST 1.2.")
COVERAGE = {
    "certificates": {"Native": 16, "Partial": 13, "Hook": 13},
    "segmentNodes": {"Native": 96, "Partial": 78, "Hook": 78},
    "framesEnteredInSegments": 0,
    "framesEnteredByEndpointOutsideSegments": {"Native": [24], "Partial": [6], "Hook": [146]},
    "suppliedEmptyCallLists": {"Native": 16, "Partial": 13, "Hook": 13},
    "stageExternalCallListsWritten": {"Native": 25, "Partial": 21, "Hook": 21},
}
NONCLAIM_KEYS = ("kernelDerivedCallList", "kernelDerivedPostWorld", "unregisteredRequests", "proverRerun",
                 "kernelSessionReplay", "malformedBranchClosure", "registeredCentralClosure", "generalRuntimeLinks",
                 "independentAssurance", "fullTrustCompletion", "releaseOrDeployment")
EXPECTED_EVIDENCE_DIGEST = '2e3efa812d955bf796437c376c623d199ee74ab82175ed2f1a9166e9a6348580'
PUBLIC_KEYS = {"schema", "status", "scope", "graphBoundary", "stageBoundary", "reproductionBoundary", "coverage",
               "stageSources", "productIdentity", "artifacts", "rehashVerifier", "nonclaims", "certificates"}
ROW_KEYS = {"key", "kcfgSha256", "endpointCallDepth", "segmentNodes", "framesEnteredInSegment",
            "framesEnteredByEndpointOutsideSegment", "suppliedCallList"}
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


def expected_keys(product):
    catalog = read_json(product / IDENTITY_PATHS["malformedKevmKoreCheckpoint"])
    slugs = {CATALOG_PROFILES[item["profile"]]: item["slugs"] for item in catalog["profiles"]}
    require(set(slugs) == set(PROFILES), "Malformed catalog profiles differ")
    keys = sorted(f"{profile}/MALFORMED/{slug}" for profile in PROFILES for slug in slugs[profile])
    require(len(keys) == len(set(keys)), "Expected request keys repeat")
    return keys


def expected_stage_sources(product):
    aligned = read_json(product / IDENTITY_PATHS["alignedGateCheckpoint"])
    artifacts = {row["id"]: row for row in aligned["artifacts"]}
    require(all(role in artifacts and artifacts[role]["kind"] == "isabelle-source" for role in STAGE_ROLES.values()),
            "Aligned gate checkpoint does not bind the stage sources")
    return {profile: {"role": role, "bytes": artifacts[role]["bytes"], "sha256": artifacts[role]["sha256"]}
            for profile, role in STAGE_ROLES.items()}


def check_rows(rows, product):
    require(isinstance(rows, list) and all(isinstance(row, dict) and set(row) == ROW_KEYS for row in rows),
            "Request row keys differ")
    require([row["key"] for row in rows] == expected_keys(product), "Request rows differ from the registered requests")
    for row in rows:
        key = row["key"]
        require(isinstance(row["kcfgSha256"], str) and HEX64.fullmatch(row["kcfgSha256"]) is not None,
                "Proof graph hash differs: " + key)
        require(row["endpointCallDepth"] == 1 and type(row["segmentNodes"]) is int and row["segmentNodes"] >= 2
                and row["framesEnteredInSegment"] == 0 and type(row["framesEnteredByEndpointOutsideSegment"]) is int
                and row["framesEnteredByEndpointOutsideSegment"] >= 1 and row["suppliedCallList"] == "EMPTY",
                "Request call frame row differs: " + key)
    graphs = [row["kcfgSha256"] for row in rows]
    require(len(set(graphs)) == len(graphs), "Two requests name one proof graph")

    def per_profile(function):
        return {profile: function([row for row in rows if row["key"].startswith(profile + "/")]) for profile in PROFILES}

    return {
        "certificates": per_profile(len),
        "segmentNodes": per_profile(lambda items: sum(row["segmentNodes"] for row in items)),
        "framesEnteredInSegments": sum(row["framesEnteredInSegment"] for row in rows),
        "framesEnteredByEndpointOutsideSegments": per_profile(
            lambda items: sorted({row["framesEnteredByEndpointOutsideSegment"] for row in items})),
        "suppliedEmptyCallLists": per_profile(lambda items: sum(1 for row in items if row["suppliedCallList"] == "EMPTY")),
    }


def public_summary(report):
    """The public part of the record that follows from a call trace report."""
    rows = [{"key": item["key"], "kcfgSha256": item["kcfgSha256"], "endpointCallDepth": item["endpointCallDepth"],
             "segmentNodes": len(item["segment"]), "framesEnteredInSegment": len(item["framesEnteredInSegment"]),
             "framesEnteredByEndpointOutsideSegment": item["framesEnteredByEndpointOutsideSegment"],
             "suppliedCallList": item["suppliedCallList"]} for item in report["certificates"]]
    profiles = report["profiles"]
    coverage = {
        "certificates": {profile: profiles[profile]["certificates"] for profile in PROFILES},
        "segmentNodes": {profile: profiles[profile]["segmentNodes"] for profile in PROFILES},
        "framesEnteredInSegments": sum(profiles[profile]["framesEnteredInSegments"] for profile in PROFILES),
        "framesEnteredByEndpointOutsideSegments": {profile: profiles[profile]["framesEnteredByEndpointOutsideSegments"]
                                                   for profile in PROFILES},
        "suppliedEmptyCallLists": {profile: profiles[profile]["suppliedEmptyCallLists"] for profile in PROFILES},
        "stageExternalCallListsWritten": {profile: profiles[profile]["stageExternalCallListsWritten"]
                                          for profile in PROFILES},
    }
    stages = {profile: {"role": profiles[profile]["stageRole"], "sha256": profiles[profile]["stageSourceSha256"]}
              for profile in PROFILES}
    return {"coverage": coverage, "certificates": rows, "stageSources": stages}


def build_checkpoint(summary, product, artifacts):
    """The record before its verifier identity is added; the writer pins its digest in this verifier."""
    expected = expected_stage_sources(product)
    require(all(summary["stageSources"][profile]["sha256"] == expected[profile]["sha256"]
                and summary["stageSources"][profile]["role"] == expected[profile]["role"] for profile in PROFILES),
            "Report stage sources differ from the aligned gate checkpoint")
    return {"schema": SCHEMA, "status": STATUS, "scope": SCOPE, "graphBoundary": GRAPH_BOUNDARY,
            "stageBoundary": STAGE_BOUNDARY, "reproductionBoundary": REPRODUCTION_BOUNDARY,
            "coverage": summary["coverage"], "stageSources": expected,
            "productIdentity": {key: file_identity(product, path) for key, path in IDENTITY_PATHS.items()},
            "artifacts": artifacts, "rehashVerifier": None,
            "nonclaims": {key: True for key in NONCLAIM_KEYS}, "certificates": summary["certificates"]}


def public_contract(checkpoint, product):
    require(set(checkpoint) == PUBLIC_KEYS and checkpoint["schema"] == SCHEMA and checkpoint["status"] == STATUS,
            "Checkpoint contract differs")
    privacy_boundary(checkpoint)
    require(payload_digest(checkpoint) == EXPECTED_EVIDENCE_DIGEST, "Reviewed evidence digest differs")
    require(checkpoint["scope"] == SCOPE and checkpoint["graphBoundary"] == GRAPH_BOUNDARY
            and checkpoint["stageBoundary"] == STAGE_BOUNDARY
            and checkpoint["reproductionBoundary"] == REPRODUCTION_BOUNDARY, "Public scope or boundary differs")
    require(checkpoint["nonclaims"] == {key: True for key in NONCLAIM_KEYS}, "All bounded nonclaims required")
    require(same_json(checkpoint["coverage"], COVERAGE), "Coverage differs from the reviewed counts")
    derived = check_rows(checkpoint["certificates"], product)
    require(all(same_json(checkpoint["coverage"][key], value) for key, value in derived.items()),
            "Coverage does not follow from the request rows")
    require(same_json(checkpoint["stageSources"], expected_stage_sources(product)),
            "Stage sources differ from the aligned gate checkpoint")
    require(checkpoint["productIdentity"] == {key: file_identity(product, path) for key, path in IDENTITY_PATHS.items()},
            "Product identity differs from the current files")
    verifier = checkpoint["rehashVerifier"]
    require(isinstance(verifier, dict) and set(verifier) == {"path", "bytes", "sha256", "command"}
            and verifier["command"] == COMMAND
            and {key: verifier[key] for key in ("path", "bytes", "sha256")} == file_identity(product, VERIFIER_PATH),
            "Current verifier differs")
    artifacts = checkpoint["artifacts"]
    require(isinstance(artifacts, list) and [row.get("id") for row in artifacts] == list(ARTIFACT_KINDS)
            and all(isinstance(row, dict) and set(row) == {"id", "kind", "bytes", "sha256"}
                    and row["kind"] == ARTIFACT_KINDS[row["id"]] and type(row["bytes"]) is int and row["bytes"] > 0
                    and isinstance(row["sha256"], str) and HEX64.fullmatch(row["sha256"]) is not None for row in artifacts),
            "Artifact inventory differs")


def load_tool(product):
    """The trace tool of the product tree, refusing a module loaded from anywhere else."""
    directory = (product / TOOL_DIRECTORY).resolve()
    sys.dont_write_bytecode = True
    if str(directory) not in sys.path:
        sys.path.insert(0, str(directory))
    tool = importlib.import_module("malformed_call_trace")
    require(Path(inspect.getfile(tool)).resolve() == (product / IDENTITY_PATHS["traceTool"]).resolve(),
            "Imported trace tool differs from the product file")
    return tool


def private_file(base, relative, label):
    require(isinstance(relative, str) and relative and not PurePosixPath(relative).is_absolute()
            and ".." not in PurePosixPath(relative).parts and ":" not in relative, "Private index path differs: " + label)
    path = (base / relative).resolve()
    require(path.is_relative_to(base) and path.is_file(), "Private artifact missing: " + label)
    return path


def verify_checkpoint(checkpoint, index_path, evidence, stage_index, product):
    product, evidence = product.resolve(), evidence.resolve()
    index_path, stage_index = index_path.resolve(), stage_index.resolve()
    public_contract(checkpoint, product)
    tool = load_tool(product)
    verifier_file = (product / VERIFIER_PATH).resolve()
    require(Path(__file__).resolve() == verifier_file, "Executing verifier identity differs")
    index = read_json(index_path)
    require(set(index) == set(ARTIFACT_KINDS), "Private index roles differ")
    base = index_path.parent
    row = checkpoint["artifacts"][0]
    report_path = private_file(base, index[row["id"]], row["id"])
    require(report_path.stat().st_size == row["bytes"] and digest(report_path) == row["sha256"],
            "Private artifact drift: " + row["id"])
    stored_bytes = report_path.read_bytes()
    stored = json.loads(stored_bytes.decode("utf-8"))
    require(stored.get("schema") == tool.SCHEMA and stored.get("status") == tool.STATUS, "Stored report contract differs")
    rebuilt = tool.build(product, evidence, stage_index)
    require(tool.dump_json(rebuilt).encode("utf-8") == stored_bytes, "Call trace recomputation differs from the stored report")
    summary = public_summary(rebuilt)
    require(same_json(checkpoint["coverage"], summary["coverage"]) and same_json(checkpoint["certificates"], summary["certificates"])
            and all(checkpoint["stageSources"][profile]["sha256"] == summary["stageSources"][profile]["sha256"]
                    for profile in PROFILES), "Public record differs from the recomputed report")
    identity = checkpoint["productIdentity"]
    require(rebuilt["inputs"]["kevmKoreCheckpoint"]["sha256"] == identity["malformedKevmKoreCheckpoint"]["sha256"]
            and rebuilt["inputs"]["alignedGateCheckpoint"]["sha256"] == identity["alignedGateCheckpoint"]["sha256"],
            "Report inputs differ from the product identity")
    require(digest(report_path) == row["sha256"], "Private artifact changed while checked")
    for key, path in IDENTITY_PATHS.items():
        require(digest(product / path) == identity[key]["sha256"], "Product identity changed while checked: " + key)
    require(digest(verifier_file) == checkpoint["rehashVerifier"]["sha256"], "Verifier changed while checked")
    return {"schema": "trust12-malformed-call-trace-rehash-v1", "status": "PASS_MALFORMED_CALL_TRACE_RECOMPUTED",
            "certificates": len(rebuilt["certificates"]), "proverRerun": False, "kernelSessionReplay": False,
            "malformedBranchDischarged": False, "nonclaim": REPRODUCTION_BOUNDARY}


def metadata_only(checkpoint, product):
    public_contract(checkpoint, product.resolve())
    return {"status": "PASS_PUBLIC_METADATA_ONLY", "savedArtifactsVerified": False, "reportRecomputed": False,
            "nonclaims": sorted(NONCLAIM_KEYS)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--product-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--checkpoint", type=Path)
    parser.add_argument("--metadata-only", action="store_true")
    parser.add_argument("--evidence", type=Path)
    parser.add_argument("--stage-index", type=Path)
    parser.add_argument("--artifact-index", type=Path)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    sys.dont_write_bytecode = True
    product = args.product_root.resolve()
    checkpoint_path = (args.checkpoint or product / CHECKPOINT_PATH).resolve()
    require(checkpoint_path == (product / CHECKPOINT_PATH).resolve(), "Unexpected checkpoint location")
    checkpoint = read_json(checkpoint_path)
    if args.metadata_only:
        require(args.evidence is None and args.stage_index is None and args.artifact_index is None,
                "Metadata mode reads no private file")
        report = metadata_only(checkpoint, product)
    else:
        require(args.evidence is not None and args.stage_index is not None and args.artifact_index is not None,
                "Saved mode requires the evidence root, the stage index and the private index")
        report = verify_checkpoint(checkpoint, args.artifact_index, args.evidence, args.stage_index, product)
    if args.out:
        with args.out.open("x", encoding="utf-8", newline="\n") as handle:
            handle.write(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, OSError, ValueError, KeyError, TypeError, AttributeError) as error:
        raise SystemExit(f"FAIL: {error}")
