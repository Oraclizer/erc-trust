#!/usr/bin/env python3
"""Read the call frames of the registered requests outside canonical form from their stored proof graphs.

The kernel stages that relate the registered requests outside canonical form to the model take the external call
list of each request as a supplied field. This tool checks that supplied value against the stored KEVM proof graph
of the request's certificate. For every certificate it:

* finds the certificate in the batch result that the malformed KEVM and KORE checkpoint names, and requires a
  passed, not admitted proof with no pending or failing node;
* reads the command boundary record of the certificate and requires it to name the same proof and graph;
* follows the stored graph from the command entry node to the node where control returns to the calling frame,
  and requires that segment to be a single chain of rewrite edges with no branch and no cover;
* rehashes every stored node file of the segment, reads the call depth, the executing account and the caller of
  the current frame from each one, and requires every node before the return to execute the endpoint at the call
  depth of the entry node and the return node to execute the caller one depth higher up;
* requires the node inventory of the graph to agree with those values and to show, outside the segment, call
  frames that the endpoint enters one depth deeper, and rehashes and reads one such node: the graph records call
  frames as nodes, so a call inside the segment would appear there;
* requires the record of the request in the kernel stage source to supply the empty external call list, and every
  external call list that the stage source writes to be empty.

It reads stored files only. It never runs a prover, a symbolic execution or a kernel session, and it does not
derive the call list inside the kernel.

Usage:
  malformed_call_trace.py --product-root DIR --evidence DIR --stage-index FILE --out FILE
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path, PurePosixPath
from typing import Any

KEVM_CHECKPOINT = "evidence/trust12/runtime-link/malformed/kevm-kore-checkpoint-v1.json"
ALIGNED_CHECKPOINT = "evidence/trust12/runtime-link/malformed/aligned-gate-checkpoint-v1.json"
SCHEMA = "trust12-malformed-call-trace-report-v1"
STATUS = "PASS_MALFORMED_CALL_TRACE_MATCHES_SUPPLIED_LISTS"
PROFILES = {"native": "Native", "partial": "Partial", "hook": "Hook"}
STAGE_ROLES = {"Native": "native-aligned-source", "Partial": "partial-aligned-source", "Hook": "hook-aligned-source"}
BOUNDARY_STATUS = "PASS_NATIVE_COMMAND_BOUNDARY_SELECTED"
FIELD = "transaction_external_calls"
EMPTY_LIST = FIELD + " = []"
FIELD_VALUE = re.compile(re.escape(FIELD) + r"\s*=\s*([^,\n\\]*)")
NEXT_ITEM = re.compile(r"^(?:definition|lemma|theorem|corollary|fun|abbreviation|context|end|locale|section|text)\b",
                       re.MULTILINE)
NONCLAIM = ("The call frames are read from stored proof graphs and node files; no prover, symbolic execution or "
            "kernel session is run, and the kernel still takes the external call list as a supplied field.")


class TraceError(RuntimeError):
    """A fail-closed check of the call trace did not hold."""


def require(condition: object, message: str) -> None:
    if not condition:
        raise TraceError(message)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def dump_json(value: Any) -> str:
    return json.dumps(value, indent=2) + "\n"


class Evidence:
    """The evidence root, which records every file it hands out so that a control can copy exactly those files."""

    def __init__(self, root: Path, reads: set[str] | None = None) -> None:
        self.root = root.resolve()
        self.reads = reads

    def file(self, path: Path, label: str) -> Path:
        path = path.resolve()
        require(path.is_relative_to(self.root) and path.is_file(), f"{label}: missing evidence file")
        if self.reads is not None:
            self.reads.add(path.relative_to(self.root).as_posix())
        return path

    def relative(self, relative: str, label: str) -> Path:
        require(isinstance(relative, str) and relative and not PurePosixPath(relative).is_absolute()
                and ".." not in PurePosixPath(relative).parts and ":" not in relative, f"{label}: path is not relative")
        return self.file(self.root / relative, label)

    def bound(self, record: dict[str, Any], label: str) -> Path:
        require(isinstance(record, dict) and record.get("root") == "EVIDENCE", f"{label}: not an evidence pointer")
        path = self.relative(record["path"], label)
        require(path.stat().st_size == record["bytes"] and sha256_file(path) == record["sha256"], f"{label}: drift")
        return path


def proof_folder(certificate_dir: Path, label: str) -> Path:
    folders = [item for item in (certificate_dir / "proofs").iterdir() if item.is_dir()]
    require(len(folders) == 1, f"{label}: expected one stored proof folder, found {len(folders)}")
    return folders[0]


def _label(term: Any) -> str | None:
    if isinstance(term, dict) and term.get("node") == "KApply":
        label = term.get("label")
        return label if isinstance(label, str) else (label or {}).get("name")
    return None


def _child(term: Any, label: str) -> Any:
    matches = [arg for arg in term.get("args", []) if _label(arg) == label]
    require(len(matches) == 1, f"configuration cell {label} is not unique")
    return matches[0]


def _int_token(cell: Any, label: str) -> int:
    args = cell.get("args", [])
    require(len(args) == 1 and isinstance(args[0], dict) and args[0].get("node") == "KToken"
            and str(args[0].get("token", "")).isdecimal(), f"{label} is not a concrete integer")
    return int(args[0]["token"])


def current_frame(node_file: Path) -> dict[str, int]:
    """Call depth, executing account and caller of the current frame of a stored graph node.

    The current frame is the call state directly under the EVM cell; the frames saved on the call stack hold the
    same cell names and are not read."""
    document = read_json(node_file)
    term = document.get("cterm", document)["config"]
    require(_label(term) == "<generatedTop>", "configuration root is not the generated top cell")
    for label in ("<foundry>", "<kevm>", "<ethereum>", "<evm>"):
        term = _child(term, label)
    state = _child(term, "<callState>")
    return {"callDepth": _int_token(_child(state, "<callDepth>"), "call depth"),
            "account": _int_token(_child(state, "<id>"), "account"),
            "caller": _int_token(_child(state, "<caller>"), "caller")}


def segment_path(graph: dict[str, Any], entry: int, target: int) -> list[int]:
    """The node chain from entry to target over plain rewrite edges, refusing branches, covers and cycles."""
    edges: dict[int, dict[str, Any]] = {}
    for edge in graph.get("edges", []):
        source = int(edge["source"])
        require(source not in edges, f"node {source} has two rewrite edges")
        edges[source] = edge
    branching = ({int(item["source"]) for item in graph.get("splits", [])}
                 | {int(item["source"]) for item in graph.get("ndbranches", [])}
                 | {int(item["source"]) for item in graph.get("covers", [])})
    path, node = [entry], entry
    while node != target:
        require(node not in branching, f"node {node} branches or is covered inside the segment")
        edge = edges.get(node)
        require(edge is not None, f"no rewrite edge leaves node {node}")
        node = int(edge["target"])
        require(node not in path, "the segment has a cycle")
        path.append(node)
    return path


def stage_records(source: str) -> dict[str, Any]:
    """Every external call list the stage source writes, and the body of each execution definition."""
    values = [match.group(1).strip() for match in FIELD_VALUE.finditer(source)]
    bodies: dict[str, str] = {}
    for match in re.finditer(r"^definition (\w+)_execution ::", source, re.MULTILINE):
        following = NEXT_ITEM.search(source, match.end())
        bodies[match.group(1)] = source[match.start():following.start() if following else len(source)]
    return {"values": values, "bodies": bodies}


def record_body(records: dict[str, Any], slug: str, label: str) -> str:
    suffix = "_" + slug.replace("-", "_")
    names = [name for name in records["bodies"] if re.fullmatch(r"[a-z]+[0-9]*" + re.escape(suffix), name)]
    require(len(names) == 1, f"{label}: the stage source has no unique execution record for the request")
    return records["bodies"][names[0]]


def trace_certificate(store: Evidence, batch_dir: Path, certificate: dict[str, Any], profile: str) -> dict[str, Any]:
    slug = certificate["slug"]
    label = f"{profile}/{slug}"
    require(certificate.get("passed") is True and certificate.get("failed") is False
            and certificate.get("admitted") is False and certificate.get("circularity") is False
            and not certificate.get("pendingNodes") and not certificate.get("failingNodes")
            and certificate.get("outcome") == "rejected", f"{label}: certificate is not a passed rejection")
    directory = batch_dir / "certificates" / slug
    proof = proof_folder(directory, label)
    proof_json = store.file(proof / "proof.json", label)
    graph_json = store.file(proof / "kcfg" / "kcfg.json", label)
    require(sha256_file(proof_json) == certificate["proofJson"]["sha256"]
            and sha256_file(graph_json) == certificate["kcfg"]["sha256"], f"{label}: stored proof or graph drift")
    boundary_file = store.file(directory / "profile-boundary-selection-v2.json", label)
    inventory_file = store.file(directory / "profile-call-nodes-all.json", label)
    boundary = read_json(boundary_file)
    require(boundary.get("status") == BOUNDARY_STATUS and boundary["proof"]["id"] == certificate["proofId"]
            and boundary["proof"]["proofJsonSha256"] == certificate["proofJson"]["sha256"]
            and boundary["proof"]["kcfgSha256"] == certificate["kcfg"]["sha256"]
            and boundary["callNodes"]["sha256"] == sha256_file(inventory_file)
            and boundary.get("expectedOutcome") == "revert", f"{label}: boundary record does not name this proof")
    endpoint, caller = int(boundary["endpoint"]), int(boundary["caller"])
    entry, post, restored = int(boundary["entryNode"]), int(boundary["postNode"]), int(boundary["restoredNode"])
    graph = read_json(graph_json)
    # A stored graph lists its node identifiers and keeps every node in its own file.
    graph_nodes = {int(node["id"]) if isinstance(node, dict) else int(node) for node in graph["nodes"]}
    require(len(graph_nodes) == len(graph["nodes"]), f"{label}: the graph lists a node twice")
    path = segment_path(graph, entry, restored)
    require(path == [int(node) for node in boundary["pathPrefixThroughRestore"]] and post in path[:-1],
            f"{label}: the graph segment differs from the boundary record")
    inventory = read_json(inventory_file)
    rows = {int(row["node"]): row for row in inventory["rows"]}
    require(len(rows) == len(inventory["rows"]) and set(rows) == graph_nodes,
            f"{label}: the node inventory does not cover the graph exactly")
    node_dir = proof / "kcfg" / "nodes"
    frames = []
    for node in path:
        node_file = store.file(node_dir / f"{node}.json", label)
        require(sha256_file(node_file) == rows[node]["fileSha256"], f"{label}: stored node {node} differs from the inventory")
        frame = current_frame(node_file)
        require(frame == {"callDepth": rows[node]["callDepth"], "account": rows[node]["id"],
                          "caller": rows[node]["caller"]}, f"{label}: inventory row {node} differs from its node file")
        frames.append({"node": node, **frame, "fileSha256": rows[node]["fileSha256"]})
    depth = frames[0]["callDepth"]
    inside = frames[:-1]
    require(depth >= 1 and all(item["callDepth"] == depth and item["account"] == endpoint and item["caller"] == caller
                               for item in inside), f"{label}: a segment node leaves the endpoint frame")
    require(frames[-1]["callDepth"] == depth - 1 and frames[-1]["account"] == caller,
            f"{label}: the segment does not return to the calling frame")
    entered = [item["node"] for item in inside if item["callDepth"] > depth]
    require(not entered, f"{label}: the segment enters a call frame")
    witnesses = sorted(node for node, row in rows.items()
                       if node not in path and isinstance(row.get("callDepth"), int) and row["callDepth"] == depth + 1
                       and row.get("caller") == endpoint)
    require(witnesses, f"{label}: the graph records no call frame entered by the endpoint")
    witness_file = store.file(node_dir / f"{witnesses[0]}.json", label)
    require(sha256_file(witness_file) == rows[witnesses[0]]["fileSha256"], f"{label}: witness node differs from the inventory")
    witness = current_frame(witness_file)
    require(witness["callDepth"] == depth + 1 and witness["caller"] == endpoint and witness["account"] != endpoint,
            f"{label}: witness node is not a call frame entered by the endpoint")
    return {
        "key": f"{profile}/MALFORMED/{slug}",
        "slug": slug,
        "proofId": certificate["proofId"],
        "proofJsonSha256": certificate["proofJson"]["sha256"],
        "kcfgSha256": certificate["kcfg"]["sha256"],
        "boundarySha256": sha256_file(boundary_file),
        "inventorySha256": boundary["callNodes"]["sha256"],
        "endpoint": endpoint,
        "caller": caller,
        "endpointCallDepth": depth,
        "segment": frames,
        "framesEnteredInSegment": entered,
        "graphNodes": len(graph_nodes),
        "framesEnteredByEndpointOutsideSegment": len(witnesses),
        "witnessNode": {"node": witnesses[0], **witness, "fileSha256": rows[witnesses[0]]["fileSha256"]},
    }


def build(product: Path, evidence: Path, stage_index: Path, reads: set[str] | None = None) -> dict[str, Any]:
    product = product.resolve()
    store = Evidence(evidence, reads)
    index_file = store.file(stage_index, "stage index")
    kevm_path, aligned_path = product / KEVM_CHECKPOINT, product / ALIGNED_CHECKPOINT
    kevm, aligned = read_json(kevm_path), read_json(aligned_path)
    require(kevm.get("status") == "PASS_MALFORMED_KEVM_KORE_FULL42", "malformed KEVM and KORE checkpoint status")
    require(str(aligned.get("status", "")).startswith("PASS_"), "aligned gate checkpoint status")
    artifacts = {item["id"]: item for item in aligned["artifacts"]}
    index = read_json(index_file)
    profiles: dict[str, Any] = {}
    certificates: list[dict[str, Any]] = []
    for entry in kevm["profiles"]:
        profile = PROFILES[entry["profile"]]
        result_path = store.bound(entry["kevmResult"], f"{profile} batch result")
        result = read_json(result_path)
        rows = {row["slug"]: row for row in result["certificates"]}
        require(len(rows) == len(result["certificates"]) == entry["registeredCertificates"]
                and sorted(rows) == sorted(entry["slugs"]), f"{profile}: certificate set differs from the checkpoint")
        role = STAGE_ROLES[profile]
        stage_path = store.relative(index[role], role)
        require(stage_path.stat().st_size == artifacts[role]["bytes"] and sha256_file(stage_path) == artifacts[role]["sha256"],
                f"{profile}: stage source differs from the aligned gate checkpoint")
        records = stage_records(stage_path.read_text(encoding="utf-8"))
        require(records["values"] and all(value == "[]" for value in records["values"]),
                f"{profile}: the stage source writes an external call list that is not empty")
        traced = []
        for slug in entry["slugs"]:
            item = trace_certificate(store, result_path.parent, rows[slug], profile)
            body = record_body(records, slug, f"{profile}/{slug}")
            require(body.count(EMPTY_LIST) == 1 and len(FIELD_VALUE.findall(body)) == 1,
                    f"{profile}/{slug}: the stage record does not supply the empty external call list")
            item["suppliedCallList"] = "EMPTY"
            traced.append(item)
        certificates += traced
        profiles[profile] = {
            "certificates": len(traced),
            "segmentNodes": sum(len(item["segment"]) for item in traced),
            "framesEnteredInSegments": sum(len(item["framesEnteredInSegment"]) for item in traced),
            "framesEnteredByEndpointOutsideSegments": sorted({item["framesEnteredByEndpointOutsideSegment"]
                                                              for item in traced}),
            "suppliedEmptyCallLists": sum(1 for item in traced if item["suppliedCallList"] == "EMPTY"),
            "stageRole": role,
            "stageSourceSha256": artifacts[role]["sha256"],
            "stageExternalCallListsWritten": len(records["values"]),
            "batchResultSha256": entry["kevmResult"]["sha256"],
        }
    return {
        "schema": SCHEMA,
        "status": STATUS,
        "inputs": {"kevmKoreCheckpoint": {"path": KEVM_CHECKPOINT, "sha256": sha256_file(kevm_path)},
                   "alignedGateCheckpoint": {"path": ALIGNED_CHECKPOINT, "sha256": sha256_file(aligned_path)},
                   "stageIndexSha256": sha256_file(index_file)},
        "profiles": profiles,
        "certificates": sorted(certificates, key=lambda item: item["key"]),
        "nonclaim": NONCLAIM,
    }


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--product-root", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--stage-index", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args(argv)
    report = build(args.product_root, args.evidence, args.stage_index)
    with args.out.open("x", encoding="utf-8", newline="\n") as handle:
        handle.write(dump_json(report))
    print(json.dumps({"status": report["status"], "profiles": report["profiles"]}, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except (TraceError, OSError, ValueError, KeyError, TypeError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
