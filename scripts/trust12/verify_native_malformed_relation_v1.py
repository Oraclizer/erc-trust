#!/usr/bin/env python3
"""Rehash the bounded Native recorded malformed-request relation."""
from __future__ import annotations

import argparse
import hashlib
import inspect
import json
import re
import shutil
import sqlite3
import subprocess
from pathlib import Path, PurePosixPath, PureWindowsPath

STAGE_IDS = ("endpoint-identity", "recorded-request-relation")
NONCLAIM_KEYS = {"operationalExecutionReceiver", "generalRuntimeLinks", "otherProfiles",
                 "otherRequests", "centralRefinementClosure", "independentAssurance",
                 "releaseOrDeployment"}
SCOPE = ("Under the pinned abstraction model and existing Native assumptions, each of sixteen supplied "
         "malformed-request execution records has a Malformed abstraction. The two recorded worlds and "
         "requests are fixed; block time remains symbolic.")
MODEL_BOUNDARY = ("Evaluation-oracle-free describes the final theorem's evaluation dependencies. "
                  "Existing keccak, storage layout, Native profile and environment assumptions are retained. "
                  "Product model identity uses the existing eight-core-definition alias checkpoint only; "
                  "equivalence of the entire model is not claimed.")
REPRODUCTION_BOUNDARY = ("The public verifier rehashes a supplied evidence bundle and reads its Isabelle "
                         "message exports. The local navigation index maps stable artifact IDs to bundle "
                         "paths and is not proof authority. This checkpoint is not a fresh replay or a "
                         "product completion statement.")
COVERAGE = {"registeredRequests": 16, "recordedPreWorlds": 2, "kernelStages": 2,
            "requestClassifications": {"wrongLength": 7, "unknownSelector": 1,
                                       "dirtyWord": 7, "nonzeroValue": 1},
            "blockTime": "symbolic", "finalEvaluationOracleDependencies": 0}
MODEL_PATH = "formal/isabelle/ERC_TRUST/TRUST_Out_Of_Spec_Refinement.thy"
CORE_ALIAS_PATH = "evidence/trust12/runtime-link/malformed/outofspec-v7-alias-core-equivalence-checkpoint-v1.json"
CORE_ALIAS_VERIFIER_PATH = "scripts/trust12/verify_outofspec_v7_alias_equiv_v1.py"
CORE_ALIAS_SCOPE = ("The current product v7 out-of-specification theory was rebuilt with only its theory "
                    "header renamed, and eight core v5/v7 definitions were proved equivalent in a "
                    "separate session with an oracle-dependency guard.")
HELPER_PATH = "scripts/trust12/verify_partial_malformed_relation_v1.py"
VERIFIER_PATH = "scripts/trust12/verify_native_malformed_relation_v1.py"
CHECKPOINT_PATH = "evidence/trust12/runtime-link/malformed/native-relation-checkpoint-v1.json"
COMMAND = ("python3 " + VERIFIER_PATH + " --base <evidence-root> --product-root <product-root> "
           "--checkpoint " + CHECKPOINT_PATH + " --artifact-index <local-artifact-index.json> "
           "--zstd <zstd-executable>")
AUDITS = [
    {"id": "endpoint-identity", "database": "endpoint-identity-database",
     "countMarker": "NATIVE_MALFORMED_ENDPOINT_ALPHA_ORACLE_COUNT=", "dependencies": 0,
     "passMarker": "PASS_NATIVE_MALFORMED_ENDPOINT_STRUCTURE_ORACLE_ZERO"},
    {"id": "recorded-request-relation", "database": "recorded-request-relation-database",
     "countMarker": "NATIVE_RECORDED_MALFORMED_BRANCH_ORACLE_COUNT=", "dependencies": 0,
     "passMarker": "PASS_NATIVE_MALFORMED_COMMAND_PROJECTIONS_ORACLE_ZERO"},
]
PUBLIC_KEYS = {"schema", "status", "scope", "coverage", "modelBoundary", "productIdentity",
               "artifacts", "kernelStages", "oracleAudits", "rehashVerifier", "nonclaims",
               "reproductionBoundary"}
PRIVATE_COORDINATES = re.compile(r"(?i)\bG[0-9]+\b|[A-Za-z]:[\\/]")


def require(condition: object, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "Duplicate JSON object key")
        result[key] = value
    return result


def read_json(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8-sig"), object_pairs_hook=unique_object)
    require(isinstance(value, dict), "JSON object required")
    return value


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def same_json(actual: object, expected: object) -> bool:
    return json.dumps(actual, sort_keys=True, separators=(",", ":")) == json.dumps(
        expected, sort_keys=True, separators=(",", ":"))


def relative_file(root: Path, value: object, label: str) -> Path:
    require(isinstance(value, str) and value and "\\" not in value and ":" not in value,
            "Invalid relative navigation: " + label)
    relative = PurePosixPath(value)
    require(not relative.is_absolute() and not PureWindowsPath(value).is_absolute()
            and ".." not in relative.parts and relative.as_posix() == value,
            "Navigation leaves its root: " + label)
    path = (root / value).resolve()
    require(path.is_relative_to(root) and path.is_file(), "Artifact is absent: " + label)
    return path


def root_identity(path: Path) -> tuple[str, str, str]:
    text = path.read_text(encoding="utf-8-sig")
    matches = re.findall(r'(?m)^session\s+([A-Za-z][A-Za-z0-9_]*)'
                         r'(?:\s+in\s+"\.\")?\s*=\s*([A-Za-z][A-Za-z0-9_]*)\s*\+', text)
    theories = re.findall(r"(?m)^\s{4}([A-Za-z][A-Za-z0-9_]*)\s*$", text)
    require(len(matches) == len(theories) == 1, "Canonical session ROOT must name one theory")
    return matches[0][0], matches[0][1], theories[0]


def successful_result(result: dict, label: str) -> str:
    target = result.get("target")
    require(isinstance(target, str) and re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", target)
            and result.get("status") == "PASS_FINAL_CHAIN_STAGE_BUILT_" + target
            and result.get("dryRun") is False and type(result.get("exitCode")) is int
            and result.get("exitCode") == 0
            and result.get("inputsUnchanged") is True
            and result.get("changedInputPaths") == []
            and (result.get("expectedNewSessions") == target
                 or result.get("expectedNewSessions") == [target])
            and result.get("builtSessions") == result.get("finishedSessions") == [target]
            and result.get("failedSessions") == result.get("cancelledSessions") == []
            and result.get("missingArtifacts") == [] and result.get("runOutOfStore") is False
            and same_json(result.get("compactPolyReceipts"), {"count": 1, "valid": True}),
            "Kernel result is incomplete: " + label)
    require(len(result.get("sessions", [])) == 1 and result["sessions"][0].get("session") == target,
            "Kernel artifact session differs: " + label)
    return target


def bound_source_inputs(before: dict | list, after: dict | list,
                        source: Path, root: Path, binding: Path, label: str) -> None:
    require(isinstance(before, list) and before and same_json(before, after),
            "Build input snapshots differ: " + label)
    identities = {}
    for row in before:
        require(set(row) == {"path", "sha256"} and isinstance(row["path"], str)
                and re.fullmatch(r"[0-9a-f]{64}", row["sha256"]),
                "Build input identity differs: " + label)
        path = row["path"].replace("\\", "/")
        require(path not in identities or identities[path] == row["sha256"],
                "Conflicting build input identity: " + label)
        identities[path] = row["sha256"]
    matches = [path for path in identities if path.endswith("/" + source.name)]
    require(len(matches) == 1, "Built source identity is not unique: " + label)
    directory = matches[0].rsplit("/", 1)[0]
    for file in (source, root, binding):
        require(identities.get(directory + "/" + file.name) == digest(file),
                "Saved build does not bind current source/ROOT/binding: " + label)


def source_family(source: str, relation: dict) -> None:
    depth, pieces, cursor = 0, [], 0
    while cursor < len(source):
        pair = source[cursor:cursor + 2]
        if pair == "(*":
            depth += 1; cursor += 2; continue
        if pair == "*)" and depth:
            depth -= 1; cursor += 2; continue
        if not depth:
            pieces.append(source[cursor])
        cursor += 1
    require(depth == 0, "Unclosed source comment")
    text = "".join(pieces)
    supplied = re.findall(r'(?ms)^definition ([A-Za-z][A-Za-z0-9_]*)_supplied_accepts\b.*?where\s*"([^"]+)"', text)
    require(len(supplied) == 1, "Unique supplied execution set absent")
    prefix, accepted = supplied[0]
    expected = [prefix + "_" + row["slug"].replace("-", "_") for row in relation["cases"]]
    actual = re.findall(r"\b([A-Za-z][A-Za-z0-9_]*)_execution vv\b", accepted)
    require(actual == expected and len(set(actual)) == 16, "Binding/source accepted set differs")
    for suffix, keyword in (("execution", "definition"), ("abstraction", "definition"),
                            ("no_command", "theorem"), ("spec", "theorem"), ("exists", "lemma")):
        names = re.findall(r"(?m)^" + keyword + r" (" + re.escape(prefix) + r"_[A-Za-z0-9_]+)_" + suffix + r"\b", text)
        require(names == expected, "Binding/source theorem family differs: " + suffix)
    for row, name in zip(relation["cases"], expected):
        equation = re.findall(r'(?ms)^definition ' + re.escape(name) + r'_execution\b.*?where\s*"([^"]+)"', text)
        require(len(equation) == 1 and re.search(r"transaction_pre = [A-Za-z0-9_]+_" + re.escape(row["world"]) + r"_configuration\b", equation[0]),
                "Binding/source world differs")
    root = prefix + "_branch"
    declaration = re.findall(r"(?m)^theorem " + re.escape(root) + r":", text)
    require(len(declaration) == 1 and '"nr_forward_hash_context.' + root + '"' in text
            and "Thm_Deps.all_oracles [root]" in text,
            "Final supplied relation or actual oracle lookup absent")


def file_identity(root: Path, record: dict, expected_path: str, label: str) -> Path:
    require(set(record) == {"path", "bytes", "sha256"} and record["path"] == expected_path
            and type(record["bytes"]) is int and record["bytes"] > 0
            and re.fullmatch(r"[0-9a-f]{64}", record["sha256"]),
            "Product identity record differs: " + label)
    file = relative_file(root, record["path"], label)
    require(file.stat().st_size == record["bytes"] and digest(file) == record["sha256"],
            "Product identity differs: " + label)
    return file


def verify_checkpoint(checkpoint: dict, index: dict, base: Path, product: Path, zstd: str) -> dict:
    base, product = base.resolve(), product.resolve()
    require(set(checkpoint) == PUBLIC_KEYS
            and checkpoint["schema"] == "trust12-native-malformed-relation-checkpoint-v1"
            and checkpoint["status"] == "PASS_KERNEL_CHECKED_REGISTERED_NATIVE_MALFORMED_RELATION",
            "Checkpoint schema, fields or status differ")
    # Every public text field is fixed below; there is no free attribution field.
    require(not PRIVATE_COORDINATES.search(json.dumps(checkpoint)), "Private coordinates in checkpoint")
    require(checkpoint["scope"] == SCOPE and same_json(checkpoint["coverage"], COVERAGE)
            and checkpoint["modelBoundary"] == MODEL_BOUNDARY
            and checkpoint["reproductionBoundary"] == REPRODUCTION_BOUNDARY,
            "Bounded claim or reproduction boundary differs")
    require(set(checkpoint["nonclaims"]) == NONCLAIM_KEYS
            and all(value is True for value in checkpoint["nonclaims"].values()),
            "All seven bounded nonclaims are required")
    identity = checkpoint["productIdentity"]
    require(set(identity) == {"malformedModel", "coreAliasCheckpoint", "coreAliasVerifier",
                              "messageReader"}, "Product identity inventory differs")
    model_file = file_identity(product, identity["malformedModel"], MODEL_PATH, "malformed-model")
    equivalence_file = file_identity(product, identity["coreAliasCheckpoint"],
                                    CORE_ALIAS_PATH, "core-alias-checkpoint")
    file_identity(product, identity["coreAliasVerifier"], CORE_ALIAS_VERIFIER_PATH,
                  "core-alias-verifier")
    helper_file = file_identity(product, identity["messageReader"], HELPER_PATH, "message-reader")
    verifier = checkpoint["rehashVerifier"]
    require(set(verifier) == {"path", "bytes", "sha256", "command"} and verifier["command"] == COMMAND,
            "Verifier reproduction command differs")
    verifier_file = file_identity(product, {key: verifier[key] for key in ("path", "bytes", "sha256")},
                                  VERIFIER_PATH, "public-verifier")
    require(Path(__file__).resolve() == verifier_file and digest(Path(__file__)) == verifier["sha256"],
            "Executing verifier differs from checkpoint identity")
    records, stages = checkpoint["artifacts"], checkpoint["kernelStages"]
    require(isinstance(records, list) and isinstance(stages, list)
            and [row.get("id") for row in stages] == list(STAGE_IDS), "Kernel stage inventory differs")
    expected = {row["id"]: row for row in records}
    kinds = {"prior-recorded-relation-build": "kernel-build-result",
             "pinned-malformed-abstraction-model": "isabelle-model-source"}
    previous = "prior-recorded-relation-build"
    for stage in stages:
        sid = stage["id"]
        links = {"id": sid, "source": sid + "-source", "sessionRoot": sid + "-root",
                 "binding": sid + "-binding", "result": sid + "-build", "heap": sid + "-heap",
                 "database": sid + "-database", "inputsBefore": sid + "-inputs-before",
                 "inputsAfter": sid + "-inputs-after", "parentResult": previous}
        require(stage == links, "Stage or parent linkage differs: " + sid)
        for field, kind in (("source", "isabelle-source"), ("sessionRoot", "isabelle-session-root"),
                            ("binding", "proof-input-binding"), ("result", "kernel-build-result"),
                            ("heap", "saved-kernel-heap"), ("database", "isabelle-database"),
                            ("inputsBefore", "proof-input-snapshot"), ("inputsAfter", "proof-input-snapshot")):
            kinds[links[field]] = kind
        previous = links["result"]
    require(len(records) == len(expected) == len(kinds) == 18 and set(expected) == set(kinds)
            and set(index) == set(expected), "Artifact inventory or duplicate IDs differ")
    files = {}
    for aid, row in expected.items():
        require(set(row) == {"id", "kind", "bytes", "sha256"}
                and re.fullmatch(r"[a-z0-9-]+", aid) and row["kind"] == kinds[aid]
                and type(row["bytes"]) is int and row["bytes"] > 0
                and re.fullmatch(r"[0-9a-f]{64}", row["sha256"]), "Malformed artifact identity: " + aid)
        file = relative_file(base, index[aid], aid)
        require(file.stat().st_size == row["bytes"] and digest(file) == row["sha256"],
                "Artifact integrity differs: " + aid)
        files[aid] = file
    require(len(set(files.values())) == len(files), "Multiple artifact IDs share one navigation path")
    equivalence = read_json(equivalence_file)
    require(equivalence["schema"] == "trust12-outofspec-v7-alias-core-equivalence-checkpoint-v1"
            and equivalence["scope"] == CORE_ALIAS_SCOPE
            and isinstance(equivalence["status"], str)
            and equivalence["status"].startswith("PASS_KERNEL_CHECKED_OUTOFSPEC_V5_V7_CORE_EQUIV_")
            and same_json(equivalence["coverage"], {"aliasSessions": 2, "coreEquivalences": 8,
                                                   "ancestorSessionsRebuilt": 0})
            and equivalence["kernelBuild"]["inputsUnchanged"] is True
            and type(equivalence["kernelBuild"]["failedSessions"]) is int
            and equivalence["kernelBuild"]["failedSessions"] == 0
            and equivalence["hostAudit"]["status"] == "PASS_OUTOFSPEC_V5_V7_CORE_EQUIV_REHASHED",
            "Existing model equivalence checkpoint boundary differs")
    current_model = equivalence["source"]["productV7Theory"]
    pinned_model = equivalence["source"]["immutableV5Pin"]
    equivalent_verifier = equivalence["hostAudit"]["verifier"]
    require(current_model == {"root": "PRODUCT", **identity["malformedModel"]}
            and pinned_model["root"] == "EVIDENCE"
            and pinned_model["bytes"] == expected["pinned-malformed-abstraction-model"]["bytes"]
            and pinned_model["sha256"] == expected["pinned-malformed-abstraction-model"]["sha256"]
            and equivalent_verifier == {"root": "PRODUCT", **identity["coreAliasVerifier"]},
            "Current product and immutable model equivalence identities differ")
    prior_target = successful_result(read_json(files["prior-recorded-relation-build"]), "prior-recorded-relation")
    bindings = []
    for stage in stages:
        sid = stage["id"]
        result = read_json(files[stage["result"]])
        target = successful_result(result, sid)
        root_target, root_parent, root_theory = root_identity(files[stage["sessionRoot"]])
        require(root_target == target and root_parent == prior_target, "ROOT/result parent chain differs: " + sid)
        source = files[stage["source"]].read_text(encoding="utf-8-sig")
        require(len(re.findall(r"(?m)^theory\s+" + re.escape(root_theory) + r"\b", source)) == 1,
                "Theory/ROOT identity differs: " + sid)
        artifact = result["sessions"][0]
        for field in ("heap", "database"):
            require(artifact[field] == {"bytes": expected[stage[field]]["bytes"],
                                        "sha256": expected[stage[field]]["sha256"]},
                    "Saved kernel artifact identity differs: " + sid)
        binding = read_json(files[stage["binding"]])
        before = json.loads(files[stage["inputsBefore"]].read_text(encoding="utf-8-sig"), object_pairs_hook=unique_object)
        after = json.loads(files[stage["inputsAfter"]].read_text(encoding="utf-8-sig"), object_pairs_hook=unique_object)
        bound_source_inputs(before, after, files[stage["source"]], files[stage["sessionRoot"]],
                            files[stage["binding"]], sid)
        require(binding["session"] == target and binding["parent"] == root_parent
                and binding["theorySha256"] == expected[stage["source"]]["sha256"]
                and binding["rootSha256"] == expected[stage["sessionRoot"]]["sha256"]
                and binding["parentResultSha256"] == expected[stage["parentResult"]]["sha256"],
                "Source/result or parent binding differs: " + sid)
        if "theory" in binding:
            require(binding["theory"] == root_theory, "Binding theory name differs: " + sid)
        bindings.append(binding)
        prior_target = target
    endpoint, relation = bindings
    require(endpoint["schema"] == "trust12-native-malformed-endpoint-bridge-input-v1"
            and relation["schema"] == "trust12-native-malformed-branch-input-v1"
            and len(endpoint["cases"]) == 2, "Native binding scope differs")
    worlds = [row["prefix"] for row in endpoint["cases"]]
    require(len(set(worlds)) == 2 and len(relation["cases"]) == 16
            and len({row["slug"] for row in relation["cases"]}) == 16
            and {row["world"] for row in relation["cases"]} == set(worlds)
            and same_json(relation["classCounts"], {"length": 7, "selector": 1, "word": 7, "value": 1}),
            "Native supplied request/world inventory differs")
    actual_classes = {name: sum(row["kind"] == name for row in relation["cases"])
                      for name in ("length", "selector", "word", "value")}
    require(actual_classes == relation["classCounts"], "Request classifications differ from supplied records")
    source_family(files[stages[-1]["source"]].read_text(encoding="utf-8-sig"), relation)
    require(same_json(checkpoint["oracleAudits"], AUDITS), "Unknown, duplicate or altered oracle audit")
    from verify_partial_malformed_relation_v1 import database_messages
    require(Path(inspect.getfile(database_messages)).resolve() == helper_file,
            "Imported database reader differs from product identity")
    decoder = shutil.which(zstd) if not Path(zstd).is_file() else zstd
    require(decoder is not None, "A Zstandard executable is required for message audits")
    counts = {}
    for audit in AUDITS:
        messages = database_messages(files[audit["database"]], decoder)
        values = re.findall(r"(?<![A-Za-z0-9_])" + re.escape(audit["countMarker"])
                            + r"([0-9]+)(?=$|[\x05\x06\s<])", messages)
        passes = re.findall(r"(?<![A-Za-z0-9_])" + re.escape(audit["passMarker"])
                            + r"(?=$|[\x05\x06\s<])", messages)
        require(values == ["0"] and len(passes) == 1,
                "Actual message audit differs: " + audit["id"])
        counts[audit["id"]] = 0
    return {"schema": "trust12-native-malformed-relation-rehash-v1",
            "status": "PASS_REGISTERED_NATIVE_MALFORMED_RELATION_REHASHED",
            "registeredRequests": 16, "recordedPreWorlds": 2, "kernelBuildsRehashed": 2,
            "artifactsRehashed": 18, "evaluationOracleDependencies": counts,
            "operationalExecutionReceiverDischarged": False, "generalRuntimeLinksDischarged": False,
            "centralRefinementClosureDischarged": False, "independentAssuranceCompleted": False,
            "nonclaim": "Rehashes the named saved artifacts and their message exports; no fresh kernel replay, "
                        "operational execution reception, general conformance or product completion is established."}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", type=Path, required=True)
    parser.add_argument("--product-root", type=Path, required=True)
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--artifact-index", type=Path, required=True)
    parser.add_argument("--zstd", default="zstd")
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    product = args.product_root.resolve()
    require(args.checkpoint.resolve() == (product / CHECKPOINT_PATH).resolve(), "Unexpected checkpoint location")
    report = verify_checkpoint(read_json(args.checkpoint), read_json(args.artifact_index),
                               args.base, product, args.zstd)
    if args.out:
        require(not args.out.exists(), "Fresh verification report required")
        args.out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, OSError, KeyError, ValueError, TypeError, sqlite3.Error,
            subprocess.CalledProcessError, ImportError) as error:
        raise SystemExit(f"FAIL: {error}")
