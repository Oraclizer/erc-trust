#!/usr/bin/env python3
"""Independent stdlib-only ABI-04 strict transitive closure verifier."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from collections import Counter, defaultdict, deque
from pathlib import Path
from typing import Any


ANTI_DIR = Path(__file__).resolve().parent
REPOSITORY_ROOT = ANTI_DIR.parents[4]
POLICY_PATH = ANTI_DIR / "closure-policy.json"


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(value: Path) -> str:
    return sha256_bytes(value.read_bytes())


def stable(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def stable_sha(value: Any) -> str:
    return sha256_bytes(stable(value).encode("utf-8"))


def relative(value: Path) -> str:
    return value.resolve().relative_to(REPOSITORY_ROOT).as_posix()


def absolute(value: str) -> Path:
    return REPOSITORY_ROOT.joinpath(*value.split("/"))


def is_sha256(value: Any) -> bool:
    if not isinstance(value, str) or len(value) != 64:
        return False
    return all(character in "0123456789abcdefABCDEF" for character in value)


def assert_acyclic_policy(policy: dict[str, Any]) -> None:
    adjacency: dict[str, set[str]] = defaultdict(set)
    for node in policy["requiredNodes"]:
        adjacency.setdefault(node["path"], set())
        for dependency in node["dependsOn"]:
            adjacency[dependency].add(node["path"])
    states: dict[str, int] = {}

    def visit(node: str, stack: list[str]) -> None:
        state = states.get(node, 0)
        if state == 1:
            raise ValueError(f"closure policy dependency cycle: {' -> '.join([*stack, node])}")
        if state == 2:
            return
        states[node] = 1
        for child in sorted(adjacency.get(node, ())):
            visit(child, [*stack, node])
        states[node] = 2

    for node in sorted(adjacency):
        visit(node, [])


def json_pointer(parts: list[Any]) -> str:
    return "/" + "/".join(str(part).replace("~", "~0").replace("/", "~1") for part in parts)


def declarations(value: Any, parts: list[Any] | None = None, output: list[dict[str, Any]] | None = None) -> list[dict[str, Any]]:
    if parts is None:
        parts = []
    if output is None:
        output = []
    if isinstance(value, list):
        for index, item in enumerate(value):
            declarations(item, [*parts, index], output)
        return output
    if not isinstance(value, dict):
        return output
    if isinstance(value.get("path"), str):
        for hash_key in ("sha256", "fileSha256", "sourceSha256", "artifactSha256", "declaredSha256"):
            if is_sha256(value.get(hash_key)):
                output.append({
                    "declaredPath": value["path"],
                    "declaredSha256": value[hash_key].lower(),
                    "pointer": json_pointer([*parts, f"path+{hash_key}"]),
                    "kind": "path-hash",
                })
                break
    for key, child in value.items():
        if isinstance(child, str) and key.endswith("Path"):
            stem = key[:-4]
            for hash_key in (f"{stem}Sha256", f"{stem}FileSha256", f"{stem}SourceSha256"):
                if is_sha256(value.get(hash_key)):
                    output.append({
                        "declaredPath": child,
                        "declaredSha256": value[hash_key].lower(),
                        "pointer": json_pointer([*parts, f"{key}+{hash_key}"]),
                        "kind": "named-path-hash",
                    })
                    break
        declarations(child, [*parts, key], output)
    return output


def get_pointer(value: Any, pointer: str) -> Any:
    current = value
    for token in pointer.split("/")[1:]:
        token = token.replace("~1", "/").replace("~0", "~")
        current = current.get(token) if isinstance(current, dict) else None
    return current


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path)
    parser.add_argument("--full", action="store_true")
    args = parser.parse_args()
    policy = json.loads(POLICY_PATH.read_text(encoding="utf-8"))
    assert_acyclic_policy(policy)
    manifest_path = absolute(policy["closureManifest"]["path"])
    allowed_extensions = set(policy["allowedFileExtensions"])

    def excluded(path_value: str) -> bool:
        return any(path_value.startswith(prefix) for prefix in policy["excludedPrefixes"])

    discovered: list[str] = []
    unexpected: list[dict[str, Any]] = []
    for scope_root in policy["scopeRoots"]:
        root = absolute(scope_root)
        if not root.exists():
            continue
        for file_path in sorted((item for item in root.rglob("*") if item.is_file()), key=lambda item: item.as_posix()):
            relative_path = relative(file_path)
            if excluded(relative_path):
                continue
            if file_path.suffix not in allowed_extensions and file_path.name != "ROOT":
                unexpected.append({"kind": "UNEXPECTED_FILE_TYPE", "path": relative_path})
                continue
            discovered.append(relative_path)

    missing: list[dict[str, Any]] = []
    duplicate: list[dict[str, Any]] = []
    mismatches: list[dict[str, Any]] = []
    manifest: dict[str, Any] | None = None
    if not manifest_path.exists():
        missing.append({"kind": "MISSING_CLOSURE_MANIFEST", "path": policy["closureManifest"]["path"]})
    else:
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            if manifest.get("kind") != "ABI04_FROZEN_EXACT_CLOSURE_MANIFEST" or manifest.get("schemaVersion") != 2:
                raise ValueError("closure manifest kind/schema")
            if manifest.get("selfPath") != policy["closureManifest"]["path"]:
                raise ValueError("closure manifest self path")
            if not isinstance(manifest.get("nodeRecords"), list) or not isinstance(manifest.get("topologyEdges"), list):
                raise ValueError("closure manifest records/edges")
            if not all(isinstance(item.get("path"), str) and is_sha256(item.get("sha256")) for item in manifest["nodeRecords"]):
                raise ValueError("closure manifest node record schema")
            if manifest.get("nodeSetSha256") != stable_sha(manifest["nodeRecords"]):
                raise ValueError("closure manifest node-set root")
            if manifest.get("topologyEdgeSetSha256") != stable_sha(manifest["topologyEdges"]):
                raise ValueError("closure manifest topology-edge root")
            if manifest.get("exactTopologyEdgeCount") != len(manifest["topologyEdges"]):
                raise ValueError("closure manifest topology-edge count")
        except Exception as error:
            mismatches.append({"kind": "CLOSURE_MANIFEST_PARSE_OR_SCHEMA_ERROR", "consumer": policy["closureManifest"]["path"], "seedPath": policy["closureManifest"]["path"], "detail": str(error)})
            manifest = None

    manifest_records = [] if manifest is None else manifest["nodeRecords"]
    manifest_path_counts = Counter(item.get("path") for item in manifest_records)
    duplicate.extend({"kind": "DUPLICATE_MANIFEST_NODE_PATH", "path": record_path, "count": count_value} for record_path, count_value in manifest_path_counts.items() if count_value > 1)
    expected_node_paths = {item.get("path") for item in manifest_records} | {policy["closureManifest"]["path"]}
    discovered_node_paths = set(discovered)
    if manifest is not None:
        if manifest.get("exactNodeCount") != len(expected_node_paths):
            mismatches.append({"kind": "CLOSURE_MANIFEST_NODE_COUNT_MISMATCH", "consumer": policy["closureManifest"]["path"], "seedPath": policy["closureManifest"]["path"]})
        missing.extend({"kind": "MISSING_EXACT_NODE", "path": item} for item in sorted(expected_node_paths - discovered_node_paths))
        unexpected.extend({"kind": "UNEXPECTED_EXACT_NODE", "path": item} for item in sorted(discovered_node_paths - expected_node_paths))

    required_by_path = {item["path"]: item for item in policy["requiredNodes"]}
    for expected_path in expected_node_paths:
        required_by_path.setdefault(expected_path, {"id": f"manifest-node:{expected_path}", "category": "frozen-exact-node", "path": expected_path, "dependsOn": []})
    for set_name in ("expectedGraphs", "authoritativeBinders"):
        spec = policy["exactSets"][set_name]
        for name in spec["expectedNames"]:
            relative_path = f'{spec["directory"]}/{name}'
            required_by_path.setdefault(relative_path, {
                "id": f"{set_name}:{name}",
                "category": "expected-graph" if set_name == "expectedGraphs" else "authoritative-binder",
                "path": relative_path,
                "dependsOn": [],
            })

    def category(relative_path: str) -> str:
        required = next((item for item in policy["requiredNodes"] if item["path"] == relative_path), None)
        if required:
            return required["category"]
        if "/expected-graphs/" in relative_path:
            return "expected-graph"
        if "/authoritative-pairs/" in relative_path:
            return "authoritative-binder"
        if "/claims/" in relative_path or "/symbolic-claims" in relative_path:
            return "claim-source"
        if "/isabelle/" in relative_path or relative_path.endswith("/ROOT"):
            return "isabelle-input"
        if Path(relative_path).suffix in {".mjs", ".py", ".sh"}:
            return "tool-source"
        if relative_path.startswith("evidence/"):
            return "evidence"
        return "product-source"

    nodes: list[dict[str, Any]] = []
    for relative_path in sorted(set(discovered) | set(required_by_path)):
        file_path = absolute(relative_path)
        nodes.append({
            "id": f"file:{relative_path}",
            "path": relative_path,
            "category": category(relative_path),
            "required": relative_path in required_by_path,
            "exists": file_path.exists(),
            "actualSha256": sha256_file(file_path) if file_path.exists() else None,
        })
    node_by_path = {item["path"]: item for item in nodes}
    missing.extend({"kind": "MISSING_REQUIRED_NODE", "path": item["path"]} for item in nodes if item["required"] and not item["exists"])
    edges: list[dict[str, Any]] = []

    for node in [item for item in nodes if item["exists"] and item["path"].endswith(".json") and item["path"] != policy["closureManifest"]["path"]]:
        try:
            source_json = json.loads(absolute(node["path"]).read_text(encoding="utf-8"))
        except Exception as error:  # fail-closed parse surface
            mismatches.append({"kind": "JSON_PARSE_ERROR", "consumer": node["path"], "detail": str(error)})
            continue
        for declaration in declarations(source_json):
            declared_path = declaration["declaredPath"]
            if os.path.isabs(declared_path) or declared_path.startswith("/"):
                unexpected.append({"kind": "ABSOLUTE_DECLARED_PATH", "consumer": node["path"], "pointer": declaration["pointer"], "path": declared_path})
                continue
            dependency_path = declared_path.replace("\\", "/")
            dependency_file = absolute(dependency_path)
            actual_sha256 = sha256_file(dependency_file) if dependency_file.exists() else None
            status = "MISSING" if actual_sha256 is None else "PASS" if actual_sha256 == declaration["declaredSha256"] else "MISMATCH"
            edges.append({
                "dependency": f"file:{dependency_path}",
                "consumer": node["id"],
                "declarationSource": node["path"],
                "declarationPointer": declaration["pointer"],
                "declarationKind": declaration["kind"],
                "declaredSha256": declaration["declaredSha256"],
                "actualSha256": actual_sha256,
                "status": status,
            })
            if dependency_path not in node_by_path:
                dependency_node = {
                    "id": f"file:{dependency_path}",
                    "path": dependency_path,
                    "category": "declared-dependency",
                    "required": True,
                    "exists": dependency_file.exists(),
                    "actualSha256": actual_sha256,
                }
                nodes.append(dependency_node)
                node_by_path[dependency_path] = dependency_node
                if not dependency_node["exists"]:
                    missing.append({"kind": "MISSING_DECLARED_DEPENDENCY", "path": dependency_path, "consumer": node["path"], "pointer": declaration["pointer"]})
            if status != "PASS":
                mismatches.append({
                    "kind": "DECLARED_DEPENDENCY_MISSING" if status == "MISSING" else "DECLARED_ACTUAL_MISMATCH",
                    "dependency": dependency_path,
                    "consumer": node["path"],
                    "seedPath": dependency_path,
                    "pointer": declaration["pointer"],
                    "declaredSha256": declaration["declaredSha256"],
                    "actualSha256": actual_sha256,
                })

    for index, record in enumerate(manifest_records):
        actual_sha256 = node_by_path.get(record.get("path"), {}).get("actualSha256")
        status = "MISSING" if actual_sha256 is None else "PASS" if actual_sha256 == record.get("sha256") else "MISMATCH"
        edges.append({
            "dependency": f'file:{record.get("path")}',
            "consumer": f'file:{policy["closureManifest"]["path"]}',
            "declarationSource": policy["closureManifest"]["path"],
            "declarationPointer": f"/nodeRecords/{index}",
            "declarationKind": "frozen-exact-node-hash",
            "declaredSha256": record.get("sha256"),
            "actualSha256": actual_sha256,
            "status": status,
        })
        if status != "PASS":
            mismatches.append({
                "kind": "FROZEN_NODE_MISSING" if status == "MISSING" else "FROZEN_NODE_HASH_MISMATCH",
                "dependency": record.get("path"),
                "consumer": policy["closureManifest"]["path"],
                "seedPath": record.get("path"),
                "pointer": f"/nodeRecords/{index}",
                "declaredSha256": record.get("sha256"),
                "actualSha256": actual_sha256,
            })

    policy_topology_keys = sorted(f'{parent_path}\0{required["path"]}' for required in policy["requiredNodes"] for parent_path in required["dependsOn"])
    manifest_topology_keys = sorted(f'{item.get("parent", {}).get("path")}\0{item.get("child", {}).get("path")}' for item in ([] if manifest is None else manifest["topologyEdges"]))
    missing.extend({"kind": "MISSING_FROZEN_TOPOLOGY_EDGE", "path": policy["closureManifest"]["path"], "edge": item} for item in policy_topology_keys if item not in manifest_topology_keys)
    unexpected.extend({"kind": "UNEXPECTED_FROZEN_TOPOLOGY_EDGE", "path": policy["closureManifest"]["path"], "edge": item} for item in manifest_topology_keys if item not in policy_topology_keys)
    if len(set(manifest_topology_keys)) != len(manifest_topology_keys):
        duplicate.append({"kind": "DUPLICATE_FROZEN_TOPOLOGY_EDGE", "path": policy["closureManifest"]["path"]})
    for index, topology in enumerate([] if manifest is None else manifest["topologyEdges"]):
        parent_path = topology.get("parent", {}).get("path")
        child_path = topology.get("child", {}).get("path")
        parent_actual = node_by_path.get(parent_path, {}).get("actualSha256")
        child_actual = node_by_path.get(child_path, {}).get("actualSha256")
        parent_pass = parent_actual is not None and parent_actual == topology.get("parent", {}).get("sha256")
        child_pass = child_actual is not None and child_actual == topology.get("child", {}).get("sha256")
        edges.append({
            "dependency": f"file:{parent_path}",
            "consumer": f"file:{child_path}",
            "declarationSource": policy["closureManifest"]["path"],
            "declarationPointer": f"/topologyEdges/{index}",
            "declarationKind": "frozen-parent-child-hash",
            "declaredSha256": topology.get("parent", {}).get("sha256"),
            "actualSha256": parent_actual,
            "declaredConsumerSha256": topology.get("child", {}).get("sha256"),
            "actualConsumerSha256": child_actual,
            "status": "PASS" if parent_pass and child_pass else "MISMATCH",
        })
        if not parent_pass:
            mismatches.append({"kind": "FROZEN_EDGE_PARENT_MISSING" if parent_actual is None else "FROZEN_EDGE_PARENT_HASH_MISMATCH", "dependency": parent_path, "consumer": child_path, "seedPath": parent_path, "pointer": f"/topologyEdges/{index}/parent", "declaredSha256": topology.get("parent", {}).get("sha256"), "actualSha256": parent_actual})
        if not child_pass:
            mismatches.append({"kind": "FROZEN_EDGE_CHILD_MISSING" if child_actual is None else "FROZEN_EDGE_CHILD_HASH_MISMATCH", "dependency": parent_path, "consumer": child_path, "seedPath": child_path, "pointer": f"/topologyEdges/{index}/child", "declaredSha256": topology.get("child", {}).get("sha256"), "actualSha256": child_actual})

    exact_set_verdicts: dict[str, Any] = {}
    for set_name in ("finiteClaims", "symbolicClaims", "exactReplayRecords", "nonReplayGates"):
        spec = policy["exactSets"][set_name]
        source_path = absolute(spec["source"])
        ids: list[str] = []
        if source_path.exists():
            source = json.loads(source_path.read_text(encoding="utf-8"))
            records = get_pointer(source, spec["arrayPointer"])
            if isinstance(records, list):
                ids = [record.get(spec["idField"], record.get(spec.get("fallbackIdField", ""))) for record in records]
                ids = [item for item in ids if isinstance(item, str)]
        counts = Counter(ids)
        actual_unique_ids = sorted(counts)
        expected_ids = sorted(spec["expectedIds"]) if isinstance(spec.get("expectedIds"), list) else None
        absent = [] if expected_ids is None else [item for item in expected_ids if item not in counts]
        expected_id_set = None if expected_ids is None else set(expected_ids)
        extra = [] if expected_id_set is None else [item for item in actual_unique_ids if item not in expected_id_set]
        duplicate_ids = sorted(item for item, count_value in counts.items() if count_value > 1)
        duplicate.extend({"kind": "DUPLICATE_EXACT_SET_ID", "set": set_name, "id": item} for item in duplicate_ids)
        missing.extend({"kind": "MISSING_EXACT_SET_ID", "set": set_name, "id": item, "path": spec["source"]} for item in absent)
        unexpected.extend({"kind": "UNEXPECTED_EXACT_SET_ID", "set": set_name, "id": item, "path": spec["source"]} for item in extra)
        exact_set_verdicts[set_name] = {
            "source": spec["source"],
            "expectedCount": spec["expectedCount"],
            "actualCount": len(ids),
            "uniqueCount": len(counts),
            "idsSha256": stable_sha(actual_unique_ids),
            "expectedIdsSha256": None if expected_ids is None else stable_sha(expected_ids),
            "missing": absent,
            "unexpected": extra,
            "duplicateIds": duplicate_ids,
            "status": "PASS" if len(ids) == spec["expectedCount"] and len(counts) == spec["expectedCount"] and not absent and not extra else "FAIL",
        }

    for set_name in ("expectedGraphs", "authoritativeBinders"):
        spec = policy["exactSets"][set_name]
        directory = absolute(spec["directory"])
        actual_names = sorted(item.name for item in directory.iterdir() if item.is_file() and item.suffix == ".json") if directory.exists() else []
        expected_names = sorted(spec["expectedNames"])
        absent = [name for name in expected_names if name not in actual_names]
        extra = [name for name in actual_names if name not in expected_names]
        missing.extend({"kind": "MISSING_EXACT_SET_FILE", "set": set_name, "path": f'{spec["directory"]}/{name}'} for name in absent)
        unexpected.extend({"kind": "UNEXPECTED_EXACT_SET_FILE", "set": set_name, "path": f'{spec["directory"]}/{name}'} for name in extra)
        exact_set_verdicts[set_name] = {
            "directory": spec["directory"],
            "expectedCount": spec["expectedCount"],
            "actualCount": len(actual_names),
            "expectedNamesSha256": stable_sha(expected_names),
            "actualNamesSha256": stable_sha(actual_names),
            "missing": absent,
            "unexpected": extra,
            "status": "PASS" if not absent and not extra and len(actual_names) == spec["expectedCount"] else "FAIL",
        }

    if exact_set_verdicts["finiteClaims"]["status"] == "PASS" and exact_set_verdicts["symbolicClaims"]["status"] == "PASS":
        finite = json.loads(absolute(policy["exactSets"]["finiteClaims"]["source"]).read_text(encoding="utf-8"))
        symbolic = json.loads(absolute(policy["exactSets"]["symbolicClaims"]["source"]).read_text(encoding="utf-8"))
        semantic_ids = sorted(
            [item["caseId"] for item in get_pointer(finite, policy["exactSets"]["finiteClaims"]["arrayPointer"])]
            + [item.get("semanticClaimId", item.get("claimId")) for item in get_pointer(symbolic, policy["exactSets"]["symbolicClaims"]["arrayPointer"])]
        )
        expected_replay_ids = sorted(side_id for semantic_id in semantic_ids for side_id in (f"{semantic_id}::canonical-positive", f"{semantic_id}::unchanged-claim-mutant-negative"))
        exact_set_verdicts["expectedReplayIds"] = {"count": len(expected_replay_ids), "sha256": stable_sha(expected_replay_ids), "status": "PASS" if len(expected_replay_ids) == 162 else "FAIL"}
        ledger_path = absolute(policy["exactSets"]["exactReplayRecords"]["source"])
        if ledger_path.exists():
            ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
            actual_replay_ids = sorted(item["replayId"] for item in get_pointer(ledger, policy["exactSets"]["exactReplayRecords"]["arrayPointer"]))
            exact_set_verdicts["exactReplayRecords"]["missing"] = [item for item in expected_replay_ids if item not in actual_replay_ids]
            exact_set_verdicts["exactReplayRecords"]["unexpected"] = [item for item in actual_replay_ids if item not in expected_replay_ids]
            missing.extend({"kind": "MISSING_EXACT_SET_ID", "set": "exactReplayRecords", "id": item, "path": policy["exactSets"]["exactReplayRecords"]["source"]} for item in exact_set_verdicts["exactReplayRecords"]["missing"])
            unexpected.extend({"kind": "UNEXPECTED_EXACT_SET_ID", "set": "exactReplayRecords", "id": item, "path": policy["exactSets"]["exactReplayRecords"]["source"]} for item in exact_set_verdicts["exactReplayRecords"]["unexpected"])
            if exact_set_verdicts["exactReplayRecords"]["missing"] or exact_set_verdicts["exactReplayRecords"]["unexpected"]:
                exact_set_verdicts["exactReplayRecords"]["status"] = "FAIL"

    edge_counts = Counter(f'{edge["dependency"]}\0{edge["consumer"]}\0{edge["declarationSource"]}\0{edge["declarationPointer"]}' for edge in edges)
    duplicate.extend({"kind": "DUPLICATE_DECLARATION_EDGE", "key": key, "count": count_value} for key, count_value in edge_counts.items() if count_value > 1)
    nodes.sort(key=lambda item: item["id"])
    edges.sort(key=stable)
    closure_material = {"nodes": nodes, "edges": edges}
    closure_hash = stable_sha(closure_material)

    adjacency: dict[str, set[str]] = defaultdict(set)
    for edge in edges:
        adjacency[edge["dependency"]].add(edge["consumer"])
    seeds: set[str] = {f'file:{item["path"]}' for item in missing}
    for item in unexpected:
        if item.get("consumer"):
            seeds.add(f'file:{item["consumer"]}')
        elif item.get("path") and not os.path.isabs(item["path"]):
            seeds.add(f'file:{item["path"]}')
    for item in mismatches:
        seed_path = item.get("seedPath", item.get("consumer"))
        if seed_path:
            seeds.add(seed_path if seed_path.startswith("file:") else f"file:{seed_path}")
    for verdict in exact_set_verdicts.values():
        if isinstance(verdict, dict) and verdict.get("status") == "FAIL" and verdict.get("source"):
            seeds.add(f'file:{verdict["source"]}')
    invalidated = set(seeds)
    queue = deque(sorted(seeds))
    while queue:
        current = queue.popleft()
        for consumer in sorted(adjacency.get(current, ())):
            if consumer not in invalidated:
                invalidated.add(consumer)
                queue.append(consumer)

    failed_exact_sets = [name for name, value in exact_set_verdicts.items() if isinstance(value, dict) and value.get("status") == "FAIL"]
    failed = bool(missing or unexpected or duplicate or mismatches or failed_exact_sets)
    dag = {
        "schemaVersion": 1,
        "kind": "ABI04_STRICT_TRANSITIVE_HASH_DAG",
        "obligationId": "ABI-04",
        "closureHashSha256": closure_hash,
        "nodes": nodes,
        "edges": edges,
        "exactSets": exact_set_verdicts,
    }
    verdict = {
        "schemaVersion": 1,
        "kind": "ABI04_PYTHON_STRICT_CLOSURE_VERDICT",
        "implementation": "independent-python-stdlib",
        "status": "FAIL_CLOSED_INVALIDATED" if failed else "PASS",
        "exitCode": 1 if failed else 0,
        "closureHashSha256": closure_hash,
        "counts": {"nodes": len(nodes), "edges": len(edges), "missing": len(missing), "unexpected": len(unexpected), "duplicate": len(duplicate), "declaredActualMismatch": len(mismatches), "invalidated": len(invalidated)},
        "missing": missing,
        "unexpected": unexpected,
        "duplicate": duplicate,
        "declaredActualMismatch": mismatches,
        "failedExactSets": failed_exact_sets,
        "invalidationSeeds": sorted(seeds),
        "invalidatedDescendants": sorted(invalidated),
        "policy": {"path": relative(POLICY_PATH), "sha256": sha256_file(POLICY_PATH)},
        "prohibitions": policy["failurePolicy"],
        "nonclaims": ["This verdict grants no proof or discharge credit.", "PASS is necessary but insufficient for ABI-04 central discharge."],
    }
    if args.out:
        args.out.mkdir(parents=True, exist_ok=True)
        (args.out / "dependency-closure.json").write_text(json.dumps(dag, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        (args.out / "python-verdict.json").write_text(json.dumps(verdict, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    summary = verdict if args.full else {"status": verdict["status"], "exitCode": verdict["exitCode"], "closureHashSha256": closure_hash, "counts": verdict["counts"], "failedExactSets": failed_exact_sets}
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return verdict["exitCode"]


if __name__ == "__main__":
    raise SystemExit(main())
