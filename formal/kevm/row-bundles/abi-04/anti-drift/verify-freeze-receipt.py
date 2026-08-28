#!/usr/bin/env python3
"""Verify an external ABI-04 closure-freeze receipt without mutating it."""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import sys
from typing import Any


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def stable_sha(value: Any) -> str:
    encoded = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def is_sha256(value: Any) -> bool:
    return isinstance(value, str) and len(value) == 64 and all(character in "0123456789abcdef" for character in value)


def read_json(path: pathlib.Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def require(condition: bool, message: str, failures: list[str]) -> None:
    if not condition:
        failures.append(message)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=pathlib.Path)
    parser.add_argument("--require-pass", action="store_true")
    parser.add_argument("--repository-root", type=pathlib.Path)
    args = parser.parse_args()
    root = args.root.resolve()
    failures: list[str] = []
    result_path = root / "worker-result.json"
    require(root.is_dir(), f"missing freeze root: {root}", failures)
    require(result_path.is_file(), f"missing worker-result.json: {result_path}", failures)
    if failures:
        print(json.dumps({"status": "FAIL", "failures": failures}, indent=2))
        return 1

    result = read_json(result_path)
    require(result.get("kind") == "ABI04_STRICT_ANTI_DRIFT_WORKER_RESULT", "wrong result kind", failures)
    require(result.get("obligationId") == "ABI-04", "wrong obligation id", failures)
    require(result.get("jsPythonAgreement") is True, "JS/Python agreement absent", failures)
    require(result.get("deterministicDoubleGeneration", {}).get("status") == "BYTE_IDENTICAL", "double generation is not byte-identical", failures)
    require(result.get("failedExactSets") == [], "failed exact sets are nonempty", failures)
    require(result.get("invalidatedDescendantSet") == [], "invalidated descendant set is nonempty", failures)
    require(result.get("prohibitions") == {
        "warningOnly": False,
        "manualHashEdit": False,
        "staleCacheOverride": False,
        "singlePairFallback": False,
    }, "prohibition contract mismatch", failures)
    require(result.get("proofCredit") is False, "freeze receipt must not claim proof credit", failures)
    require(result.get("centralCredit") is False, "freeze receipt must not claim central credit", failures)

    generation = result.get("generationReceipt")
    require(isinstance(generation, dict), "deterministic descendant generation receipt absent", failures)
    if isinstance(generation, dict):
        require(generation.get("kind") == "ABI04_DETERMINISTIC_DESCENDANT_GENERATION_RECEIPT", "wrong generation receipt kind", failures)
        require(generation.get("obligationId") == "ABI-04", "wrong generation receipt obligation", failures)
        require(generation.get("status") == "PASS_BYTE_IDENTICAL_CLEAN_SECOND_CHECK", "generation receipt status is not PASS", failures)
        require(stable_sha(generation) == result.get("generationReceiptSha256"), "generation receipt hash mismatch", failures)
        require(isinstance(generation.get("coordinator", {}).get("path"), str), "generation coordinator path absent", failures)
        require(is_sha256(generation.get("coordinator", {}).get("sha256")), "generation coordinator hash absent", failures)
        require(generation.get("preGenerationClosure", {}).get("jsPythonAgreement") is True, "pre-generation JS/Python agreement absent", failures)
        impact = generation.get("impactAnalysis", {})
        changed_descendants = impact.get("changedDescendantSet", [])
        exact_stages = ["matrix", "dynamic-offset", "expected-graphs", "runner-pin", "orchestration", "dynamic-length", "symbolic-final", "aggregate", "finite-symbolic-bridge", "open-topology", "closure-manifest"]
        require(impact.get("status") == "PASS_EXACT_MANAGED_OUTPUT_SET", "impact analysis status is not PASS", failures)
        require(impact.get("unexpectedChangedPaths") == [], "generation changed paths outside the managed exact set", failures)
        dependency_cluster = impact.get("dependencyCluster", [])
        require([item.get("stage") for item in dependency_cluster] == exact_stages, "impact dependency cluster exact-set mismatch", failures)
        pre_generation_plans = impact.get("preGenerationPlans", [])
        require([item.get("stage") for item in pre_generation_plans] == exact_stages, "pre-generation plan exact-set mismatch", failures)
        seed_stages = impact.get("seedStages", [])
        require(seed_stages == [item.get("stage") for item in pre_generation_plans if item.get("requiresRegeneration") is True], "impact seed/plan mismatch", failures)
        require(len(seed_stages) == len(set(seed_stages)), "duplicate impact seed stage", failures)
        recomputed_impacted = set(seed_stages)
        impact_grew = True
        while impact_grew:
            impact_grew = False
            for node in dependency_cluster:
                if node.get("stage") not in recomputed_impacted and any(dependency in recomputed_impacted for dependency in node.get("dependsOn", [])):
                    recomputed_impacted.add(node.get("stage"))
                    impact_grew = True
        expected_impacted_stages = [stage for stage in exact_stages if stage in recomputed_impacted]
        require(impact.get("impactedStages") == expected_impacted_stages, "impact stage closure mismatch", failures)
        require(impact.get("unimpactedStages") == [stage for stage in exact_stages if stage not in recomputed_impacted], "unimpacted stage set mismatch", failures)
        require([item.get("stage") for item in impact.get("stageChanges", [])] == exact_stages, "full static first generation stage exact-set mismatch", failures)
        require(len(changed_descendants) == len(set(changed_descendants)), "duplicate changed descendant path", failures)
        require(stable_sha(changed_descendants) == impact.get("changedDescendantSetSha256"), "changed descendant set hash mismatch", failures)
        deterministic = generation.get("deterministicDescendantGeneration", {})
        require(deterministic.get("status") == "FULL_STATIC_PIPELINE_BYTE_IDENTICAL", "full static generation is not byte-identical", failures)
        require(deterministic.get("scope") == "FULL_STATIC_PIPELINE_SUPERSET_OF_DECLARED_IMPACT", "full static generation scope mismatch", failures)
        require(deterministic.get("passes") == 2, "descendant generation did not run twice", failures)
        require(deterministic.get("pass1SnapshotSha256") == deterministic.get("pass2SnapshotSha256"), "generation snapshots differ", failures)
        require(deterministic.get("pass2ChangedDescendants") == 0, "second generation changed descendants", failures)
        require([item.get("stage") for item in deterministic.get("secondPassStageChanges", [])] == exact_stages, "full static second generation stage exact set mismatch", failures)
        for stage in deterministic.get("secondPassStageChanges", []):
            require(stage.get("changedPaths") == [], f"second generation changed stage {stage.get('stage')}", failures)
        clean = generation.get("cleanSecondCheck", {})
        require(clean.get("status") == "PASS", "clean second check is not PASS", failures)
        require(clean.get("count") == 11 and len(clean.get("checks", [])) == 11, "clean generator check exact set mismatch", failures)
        require(clean.get("reverseCount") == 8 and len(clean.get("reverseChecks", [])) == 8, "reverse-check exact set mismatch", failures)
        require(generation.get("proofExecuted") is False, "generation receipt claims proof execution", failures)
        require(generation.get("proofCredit") is False, "generation receipt claims proof credit", failures)
        require(generation.get("centralCredit") is False, "generation receipt claims central credit", failures)
        managed = generation.get("managedOutputExactSet", {})
        stages = managed.get("stages", [])
        require(len(stages) == 11, "managed generator stage exact set mismatch", failures)
        fresh = generation.get("freshIsolatedReproduction", {})
        require(fresh.get("status") == "PASS_TWO_FRESH_ISOLATED_ROOTS_BYTE_IDENTICAL", "fresh isolated reproduction is not PASS", failures)
        require(len(fresh.get("builders", [])) == 2, "fresh isolated builder exact set mismatch", failures)
        if len(fresh.get("builders", [])) == 2:
            require(fresh["builders"][0].get("snapshotSha256") == fresh["builders"][1].get("snapshotSha256"), "fresh isolated builders disagree", failures)
        require(fresh.get("scratchRootsRemovedAfterPass") is True, "fresh isolated scratch cleanup not recorded", failures)
        require(fresh.get("independentBuilderClaim") is False, "fresh isolated run must not claim independent builder", failures)
        negative = generation.get("failClosedMutationRegression", {})
        require(negative.get("status") == "PASS_2_OF_2_EXPECTED_NONZERO", "fail-closed mutation regression is not PASS", failures)
        require(negative.get("exactScenarioCount") == 2, "fail-closed mutation scenario exact set mismatch", failures)
        require(all(item.get("jsExitCode") == 1 and item.get("pythonExitCode") == 1 for item in negative.get("scenarios", [])), "fail-closed mutation did not produce paired nonzero exits", failures)
        require(negative.get("scratchRootsRemovedAfterPass") is True, "fail-closed mutation scratch cleanup not recorded", failures)
        managed_outputs = [output for stage in stages for output in stage.get("outputs", [])]
        managed_paths = sorted(output.get("path") for output in managed_outputs if isinstance(output.get("path"), str))
        expected_generation_edges = [
            {"relation": "deterministic-generator-output", "stage": stage.get("stage"), "parent": stage.get("generator"), "child": output}
            for stage in stages
            for output in stage.get("outputs", [])
        ]
        require(managed.get("count") == len(managed_outputs), "managed output count mismatch", failures)
        require(managed.get("uniqueCount") == len(set(managed_paths)) == len(managed_outputs), "managed output ownership is not unique", failures)
        require(stable_sha(managed_paths) == managed.get("pathsSha256"), "managed output exact-set hash mismatch", failures)
        require(managed.get("edges") == expected_generation_edges, "generator parent/output child edge exact-set mismatch", failures)
        require(stable_sha(expected_generation_edges) == managed.get("edgesRootSha256"), "generator edge root mismatch", failures)
        require(all(path in set(managed_paths) for path in changed_descendants), "changed descendant is outside managed output exact set", failures)

    counts = result.get("counts", {})
    for key in ("missing", "unexpected", "duplicate", "declaredActualMismatch", "invalidated"):
        require(counts.get(key) == 0, f"nonzero {key}: {counts.get(key)!r}", failures)
    if args.require_pass:
        require(result.get("status") == "PASS", f"freeze status is {result.get('status')!r}", failures)
        require(result.get("exitCode") == 0, f"freeze exit code is {result.get('exitCode')!r}", failures)

    runs = result.get("runs", [])
    require(len(runs) == 2, f"expected two deterministic runs, found {len(runs)}", failures)
    closure_hashes: list[str] = []
    run_file_hashes: list[dict[str, str]] = []
    for run_index, run in enumerate(runs, start=1):
        label = f"run-{run_index}"
        require(run.get("runName") == label, f"{label}: run name mismatch", failures)
        require(run.get("jsExitCode") == 0, f"{label}: JS exit is not zero", failures)
        require(run.get("pythonExitCode") == 0, f"{label}: Python exit is not zero", failures)
        require(run.get("status") == "PASS", f"{label}: status is not PASS", failures)
        require(run.get("invalidatedDescendants") == [], f"{label}: invalidated descendants are nonempty", failures)
        require(run.get("failedExactSets") == [], f"{label}: failed exact sets are nonempty", failures)
        require(run.get("counts") == counts, f"{label}: count disagreement", failures)
        closure_hashes.append(run.get("closureHashSha256"))
        actual_run_hashes: dict[str, str] = {}
        for name in ("jsDag", "jsVerdict", "pythonDag", "pythonVerdict"):
            descriptor = run.get("files", {}).get(name, {})
            relative = descriptor.get("path")
            expected_hash = descriptor.get("sha256")
            require(isinstance(relative, str) and relative != "", f"{label}/{name}: missing path", failures)
            if not isinstance(relative, str) or relative == "":
                continue
            target = (root / pathlib.PurePosixPath(relative)).resolve()
            require(root == target or root in target.parents, f"{label}/{name}: path escapes root", failures)
            require(target.is_file(), f"{label}/{name}: missing file {target}", failures)
            if target.is_file():
                actual_hash = sha256(target)
                actual_run_hashes[name] = actual_hash
                require(actual_hash == expected_hash, f"{label}/{name}: hash mismatch", failures)
        run_file_hashes.append(actual_run_hashes)

    if len(closure_hashes) == 2:
        require(closure_hashes[0] == closure_hashes[1] == result.get("closureHashSha256"), "closure hash disagreement", failures)
    if len(run_file_hashes) == 2:
        require(run_file_hashes[0] == run_file_hashes[1], "deterministic run files are not byte-identical", failures)

    repository_nodes_verified = 0
    generation_nodes_verified = 0
    if args.repository_root is not None and len(runs) == 2:
        repository_root = args.repository_root.resolve()
        require(repository_root.is_dir(), f"missing repository root: {repository_root}", failures)
        dag_descriptor = runs[0].get("files", {}).get("jsDag", {})
        dag_path = (root / pathlib.PurePosixPath(dag_descriptor.get("path", ""))).resolve()
        if repository_root.is_dir() and dag_path.is_file():
            dag = read_json(dag_path)
            nodes = dag.get("nodes", [])
            node_paths = {node.get("path") for node in nodes if isinstance(node.get("path"), str)}
            policy_descriptor = result.get("source", {}).get("policy", {})
            policy_path = (repository_root / pathlib.PurePosixPath(policy_descriptor.get("path", ""))).resolve()
            require(policy_path.is_file(), f"missing closure policy: {policy_path}", failures)
            if policy_path.is_file():
                require(sha256(policy_path) == policy_descriptor.get("sha256"), "closure policy hash mismatch", failures)
                policy = read_json(policy_path)
                allowed = set(policy.get("allowedFileExtensions", []))
                excluded = tuple(policy.get("excludedPrefixes", []))
                current_scope: set[str] = set()
                for scope in policy.get("scopeRoots", []):
                    scope_root = repository_root / pathlib.PurePosixPath(scope)
                    if not scope_root.exists():
                        continue
                    for target in scope_root.rglob("*"):
                        if not target.is_file() or (target.suffix not in allowed and target.name != "ROOT"):
                            continue
                        relative = target.relative_to(repository_root).as_posix()
                        if any(relative.startswith(prefix) for prefix in excluded):
                            continue
                        current_scope.add(relative)
                dag_scope = {item for item in node_paths if any(item == scope or item.startswith(f"{scope}/") for scope in policy.get("scopeRoots", [])) and not any(item.startswith(prefix) for prefix in excluded)}
                require(current_scope == dag_scope, f"repository scope exact-set mismatch: missing={sorted(dag_scope - current_scope)}, unexpected={sorted(current_scope - dag_scope)}", failures)
            for node in nodes:
                relative = node.get("path")
                if not isinstance(relative, str) or relative == "":
                    continue
                target = (repository_root / pathlib.PurePosixPath(relative)).resolve()
                require(repository_root == target or repository_root in target.parents, f"DAG node escapes repository: {relative}", failures)
                expected_exists = node.get("exists") is True
                require(target.is_file() == expected_exists, f"DAG node existence mismatch: {relative}", failures)
                if expected_exists and target.is_file():
                    require(sha256(target) == node.get("actualSha256"), f"DAG node hash mismatch: {relative}", failures)
                    repository_nodes_verified += 1

            if isinstance(generation, dict):
                coordinator = generation.get("coordinator", {})
                coordinator_relative = coordinator.get("path")
                if isinstance(coordinator_relative, str) and coordinator_relative != "":
                    coordinator_target = (repository_root / pathlib.PurePosixPath(coordinator_relative)).resolve()
                    require(repository_root == coordinator_target or repository_root in coordinator_target.parents, "generation coordinator escapes repository", failures)
                    require(coordinator_target.is_file(), "generation coordinator is missing", failures)
                    if coordinator_target.is_file():
                        require(sha256(coordinator_target) == coordinator.get("sha256"), "generation coordinator hash mismatch", failures)
                        generation_nodes_verified += 1
                for stage in generation.get("managedOutputExactSet", {}).get("stages", []):
                    descriptors = [stage.get("generator", {})] + stage.get("outputs", [])
                    for descriptor in descriptors:
                        relative = descriptor.get("path")
                        expected_hash = descriptor.get("sha256")
                        require(isinstance(relative, str) and relative != "", f"{stage.get('stage')}: missing generation path", failures)
                        require(is_sha256(expected_hash), f"{stage.get('stage')}: invalid generation hash", failures)
                        if not isinstance(relative, str) or relative == "":
                            continue
                        target = (repository_root / pathlib.PurePosixPath(relative)).resolve()
                        require(repository_root == target or repository_root in target.parents, f"generation path escapes repository: {relative}", failures)
                        require(target.is_file(), f"missing generated node: {relative}", failures)
                        if target.is_file():
                            require(sha256(target) == expected_hash, f"generated node hash mismatch: {relative}", failures)
                            generation_nodes_verified += 1
                    require(stable_sha(stage.get("outputs", [])) == stage.get("outputsRootSha256"), f"{stage.get('stage')}: generated output root mismatch", failures)

    status = "PASS" if not failures else "FAIL"
    print(json.dumps({
        "status": status,
        "freezeRoot": str(root),
        "workerResultSha256": sha256(result_path),
        "closureHashSha256": result.get("closureHashSha256"),
        "counts": counts,
        "repositoryNodesVerified": repository_nodes_verified,
        "generationNodesVerified": generation_nodes_verified,
        "failures": failures,
    }, indent=2))
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
