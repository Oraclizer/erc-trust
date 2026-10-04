#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Rehash the saved aligned-gate stages for the registered requests outside canonical form of three profiles."""
from __future__ import annotations

import argparse
import hashlib
import inspect
import json
import re
import shutil
import sqlite3
import subprocess
from pathlib import Path

from verify_hook_malformed_relation_v1 import (core_alias, digest, file_identity, heap_lineage, read_json,
                                               relative_file, require, root_identity, same_json, saved_source,
                                               strip_comments)

CHECKPOINT_PATH = "evidence/trust12/runtime-link/malformed/aligned-gate-checkpoint-v1.json"
VERIFIER_PATH = "scripts/trust12/verify_malformed_aligned_gate_v1.py"
HELPER_PATH = "scripts/trust12/verify_hook_malformed_relation_v1.py"
READER_PATH = "scripts/trust12/verify_partial_malformed_relation_v1.py"
MODEL_PATH = "formal/isabelle/ERC_TRUST/TRUST_Out_Of_Spec_Refinement.thy"
CORE_ALIAS_PATH = "evidence/trust12/runtime-link/malformed/outofspec-v7-alias-core-equivalence-checkpoint-v1.json"
CORE_ALIAS_VERIFIER_PATH = "scripts/trust12/verify_outofspec_v7_alias_equiv_v1.py"
DECISION_PATH = "spec/decisions/12-requests-outside-canonical-form.md"
RECORD_PATHS = {"nativeRecords": "evidence/trust12/runtime-link/malformed/native-relation-checkpoint-v1.json",
                "partialRecords": "evidence/trust12/runtime-link/malformed/partial-relation-checkpoint-v1.json",
                "hookRecords": "evidence/trust12/runtime-link/malformed/hook-relation-checkpoint-v1.json"}
IDENTITY_PATHS = {"malformedModel": MODEL_PATH, "coreAliasCheckpoint": CORE_ALIAS_PATH,
                  "coreAliasVerifier": CORE_ALIAS_VERIFIER_PATH, "messageReader": READER_PATH,
                  "verifierHelpers": HELPER_PATH, "decision": DECISION_PATH, **RECORD_PATHS}
COMMAND = ("python3 " + VERIFIER_PATH + " --base <evidence-root> --product-root <product-root> --checkpoint "
           + CHECKPOINT_PATH + " --artifact-index <local-artifact-index.json> --zstd <zstd-executable>")
SCOPE = ("The registered requests outside canonical form of the three profiles (Native 16, Partial 13, Hook 13) "
         "satisfy the aligned gate relation and the product relation alpha_transaction_spec. In the aligned gate "
         "relation a request whose value-reading product command does not decode is a full-state stutter with a "
         "returned malformed result whatever its revert data, as decision 12 specifies; a request that decodes keeps "
         "the original gate relation. The original gate relation, which requires an untyped malformed result, holds "
         "only for the requests with empty revert output that the bridge does not decode (Native 8, Partial 6, "
         "Hook 6). It admits no abstraction for the requests with a typed revert output (Native 7, Partial 6, "
         "Hook 6) or for the nonzero-value request of each profile, which the bridge decodes.")
CONTROL_BOUNDARY = ("Controls: a classifier that reads a typed output before the decoded command, and the recorded "
                    "reverted phase label, break the aligned gate relation and keep the product relation; a success "
                    "flag, one external call or one log breaks both relations.")
MODEL_BOUNDARY = ("Status, revert output and calldata are received values bound to the registered records. Each "
                  "record's post world and logs are defined as its recorded pre-call world and logs, as the recorded "
                  "call reverts; the stages do not derive them from an execution trace. The gas limit and the "
                  "external call list are supplied. The theorems hold for every bridge and checker "
                  "where stated and otherwise under the existing keccak, storage layout and profile assumptions; "
                  "the Hook stages retain five conditional reader facts. The Hook stages carry byte copies of the "
                  "aligned definitions and general theorems of the Native stage, whose identity is shown by "
                  "hashes only. Product model identity uses the existing eight-core-definition alias checkpoint.")
REPRODUCTION_BOUNDARY = ("This verifier rehashes saved artifacts, native database source bytes and message exports "
                         "and requires the current bound inputs and product identities. The private navigation "
                         "index is not proof authority. This is not a fresh kernel replay and states no "
                         "completion of the registered-scope central closure, any general runtime link or TRUST 1.2.")
COVERAGE = {"registeredRequests": {"native": 16, "partial": 13, "hook": 13}, "kernelSessions": 6, "kernelRuns": 3,
            "alignedGateHolds": {"native": 16, "partial": 13, "hook": 13},
            "originalGateHolds": {"native": 8, "partial": 6, "hook": 6},
            "originalGateImpossibleTypedOutput": {"native": 7, "partial": 6, "hook": 6},
            "originalGateImpossibleDecodedNonzeroValue": {"native": 1, "partial": 1, "hook": 1},
            "explicitRoots": {"native-aligned": 354, "native-value": 7, "partial-aligned": 276, "partial-value": 8,
                              "hook-aligned": 303, "hook-value": 8}}
NONCLAIM_KEYS = {"generalRuntimeLinks", "twentySevenCellGateInstantiation", "registeredCentralClosure",
                 "unregisteredRequests", "fullTrustCompletion", "independentAssurance", "releaseOrDeployment"}
RUNS = (("native-aligned-run", "native-prior-build", ("native-aligned",)),
        ("native-value-partial-run", None, ("native-value", "partial-aligned", "partial-value")),
        ("hook-run", "hook-prior-build", ("hook-aligned", "hook-value")))
SESSIONS = tuple(sid for _, _, sids in RUNS for sid in sids)
PREPARATIONS = {"native-aligned": "native-preparation-check", "native-value": "native-preparation-check",
                "partial-aligned": "profile-preparation-check", "partial-value": "profile-preparation-check",
                "hook-aligned": "profile-preparation-check", "hook-value": "profile-preparation-check"}
REPARENTED = {"partial-aligned": "partial-aligned-prepared-root"}
EXPECTED_EVIDENCE_DIGEST = 'da0c3a441dbf11efc1c925dfbe906191e8f4996e7d33aa9e943541ee1da5c90a'
PUBLIC_KEYS = {"schema", "status", "scope", "controlBoundary", "modelBoundary", "coverage", "productIdentity",
               "artifacts", "kernelRuns", "kernelSessions", "rehashVerifier", "nonclaims", "reproductionBoundary"}
PRIVATE_COORDINATES = re.compile(r"(?i)\bG[0-9]+\b|_G[0-9]+_|[A-Za-z]:[\\/]|\\\\[A-Za-z]")
PASS_MARKER = re.compile(r"(?<![A-Za-z0-9_])PASS_[A-Z0-9_]+_ORACLE_ZERO_SKIP_FALSE(?![A-Za-z0-9_])")


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True, allow_nan=False).encode("utf-8")


def payload_digest(checkpoint):
    return hashlib.sha256(canonical({key: value for key, value in checkpoint.items() if key != "rehashVerifier"})).hexdigest()


def privacy_boundary(checkpoint):
    encoded = json.dumps(checkpoint, ensure_ascii=False)
    require(encoded.isascii() and not PRIVATE_COORDINATES.search(encoded), "Private or non-English metadata")


def public_contract(checkpoint):
    require(set(checkpoint) == PUBLIC_KEYS and checkpoint["schema"] == "trust12-malformed-aligned-gate-checkpoint-v1"
            and checkpoint["status"] == "PASS_KERNEL_CHECKED_REGISTERED_MALFORMED_ALIGNED_GATE", "Checkpoint contract differs")
    privacy_boundary(checkpoint)
    require(payload_digest(checkpoint) == EXPECTED_EVIDENCE_DIGEST, "Reviewed evidence digest differs")
    require(checkpoint["scope"] == SCOPE and checkpoint["controlBoundary"] == CONTROL_BOUNDARY
            and checkpoint["modelBoundary"] == MODEL_BOUNDARY and same_json(checkpoint["coverage"], COVERAGE)
            and checkpoint["reproductionBoundary"] == REPRODUCTION_BOUNDARY, "Public scope or privacy boundary differs")
    require(set(checkpoint["nonclaims"]) == NONCLAIM_KEYS and all(v is True for v in checkpoint["nonclaims"].values()),
            "All bounded nonclaims required")
    require([row.get("id") for row in checkpoint["kernelRuns"]] == [run for run, _, _ in RUNS]
            and [row.get("id") for row in checkpoint["kernelSessions"]] == list(SESSIONS), "Run or session order differs")


def expected_kinds():
    kinds = {"native-prior-build": "kernel-build-result", "hook-prior-build": "kernel-build-result",
             "native-parent-heap": "saved-kernel-heap", "native-parent-database": "isabelle-database",
             "hook-parent-heap": "saved-kernel-heap", "hook-parent-database": "isabelle-database",
             "native-preparation-check": "generator-static-check", "profile-preparation-check": "generator-static-check",
             "partial-aligned-prepared-root": "isabelle-session-root", "pinned-malformed-model": "isabelle-source",
             "hook-prior-root": "isabelle-session-root"}
    for run, _, _ in RUNS:
        for role, kind in (("result", "kernel-build-result"), ("inputs-before", "proof-input-snapshot"),
                           ("inputs-after", "proof-input-snapshot"), ("build-log", "kernel-build-log")):
            kinds[run + "-" + role] = kind
    for sid in SESSIONS:
        for role, kind in (("source", "isabelle-source"), ("root", "isabelle-session-root"),
                           ("heap", "saved-kernel-heap"), ("database", "isabelle-database")):
            kinds[sid + "-" + role] = kind
    return kinds


def run_result(result, targets, label):
    require(result.get("schema") == "trust12-final-chain-stage-result-v1" and result.get("dryRun") is False
            and result.get("status") == "PASS_FINAL_CHAIN_STAGE_BUILT_" + targets[-1]
            and result.get("target") == targets[-1] and type(result.get("exitCode")) is int and result["exitCode"] == 0
            and result.get("inputsUnchanged") is True and result.get("changedInputPaths") == []
            and result.get("expectedNewSessions") in (targets, targets[0] if len(targets) == 1 else None)
            and result.get("builtSessions") == result.get("finishedSessions") == targets
            and result.get("dryRunWouldBuild") == result.get("failedSessions") == result.get("cancelledSessions") == []
            and result.get("missingArtifacts") == [] and result.get("runOutOfStore") is False
            and same_json(result.get("compactPolyReceipts"), {"count": len(targets), "valid": True})
            and [row.get("session") for row in result.get("sessions", [])] == targets,
            "Incomplete or contradictory kernel run: " + label)


def prior_result(result, label):
    target = result.get("target")
    require(isinstance(target, str) and result.get("schema") == "trust12-final-chain-stage-result-v1"
            and result.get("status") == "PASS_FINAL_CHAIN_STAGE_BUILT_" + target and result.get("dryRun") is False
            and result.get("exitCode") == 0 and result.get("inputsUnchanged") is True
            and result.get("builtSessions") == result.get("finishedSessions") == [target]
            and len(result.get("sessions", [])) == 1 and result["sessions"][0].get("session") == target,
            "Prior kernel result differs: " + label)
    return target


def live_inputs(before, after, required, checked, label):
    require(isinstance(before, list) and before and same_json(before, after), "Saved snapshot differs: " + label)
    seen = set()
    for row in before:
        require(isinstance(row, dict) and set(row) == {"path", "sha256"} and isinstance(row["path"], str)
                and re.fullmatch(r"[0-9a-f]{64}", row["sha256"]), "Invalid input row: " + label)
        if row["path"] == "<run-local-catalog>":
            continue
        path = Path(row["path"]).resolve()
        require(path not in seen and path.is_file(), "Duplicate or missing input: " + label)
        require(path not in checked or checked[path] == row["sha256"], "Conflicting input identity: " + label)
        require(digest(path) == row["sha256"], "Current input drift: " + label)
        seen.add(path); checked[path] = row["sha256"]
    require(all(path.resolve() in seen for path in required), "Snapshot does not bind the stage files: " + label)


def audit_messages(messages, roots, label):
    require("\x06error_message" not in messages, "Native PIDE error: " + label)
    counts = re.findall(r"(?<![A-Za-z0-9_])ROOT_COUNT=([0-9]+)(?![0-9])", messages)
    require(counts == [str(roots)] and len(PASS_MARKER.findall(messages)) == 1, "Guarded oracle audit differs: " + label)


def verify_checkpoint(checkpoint, index, base, product, zstd):
    base, product = base.resolve(), product.resolve()
    public_contract(checkpoint)
    identity = checkpoint["productIdentity"]
    require(set(identity) == set(IDENTITY_PATHS), "Product identity inventory differs")
    products = {key: file_identity(product, identity[key], value, key) for key, value in IDENTITY_PATHS.items()}
    verifier = checkpoint["rehashVerifier"]
    require(set(verifier) == {"path", "bytes", "sha256", "command"} and verifier["command"] == COMMAND, "Public command differs")
    verifier_file = file_identity(product, {key: verifier[key] for key in ("path", "bytes", "sha256")}, VERIFIER_PATH, "verifier")
    require(Path(__file__).resolve() == verifier_file, "Executing verifier identity differs")
    kinds = expected_kinds()
    records = checkpoint["artifacts"]
    by_id = {row["id"]: row for row in records}
    require(isinstance(records, list) and len(records) == len(by_id) == len(kinds)
            and set(by_id) == set(kinds) == set(index), "Artifact inventory or duplicates differ")
    files, checked = {}, {}
    for aid, row in by_id.items():
        require(set(row) == {"id", "kind", "bytes", "sha256"} and row["kind"] == kinds[aid]
                and type(row["bytes"]) is int and row["bytes"] > 0 and re.fullmatch(r"[0-9a-f]{64}", row["sha256"]),
                "Artifact identity differs: " + aid)
        path = relative_file(base, index[aid], aid)
        require(path.stat().st_size == row["bytes"] and digest(path) == row["sha256"], "Artifact drift: " + aid)
        files[aid] = path; checked[path] = row["sha256"]
    require(len(set(files.values())) == len(files), "Multiple artifact IDs share a path")
    core_alias(read_json(products["coreAliasCheckpoint"]), identity, by_id["pinned-malformed-model"])
    decoder = shutil.which(zstd) if not Path(zstd).is_file() else str(Path(zstd).resolve())
    require(decoder is not None, "Existing decompressor required")
    from verify_partial_malformed_relation_v1 import database_messages
    require(Path(inspect.getfile(database_messages)).resolve() == products["messageReader"], "Imported message reader differs")
    require(Path(inspect.getfile(saved_source)).resolve() == products["verifierHelpers"], "Imported helpers differ")
    runs = {row["id"]: row for row in checkpoint["kernelRuns"]}
    sessions = {row["id"]: row for row in checkpoint["kernelSessions"]}
    preparations = {key: read_json(files[key]) for key in ("native-preparation-check", "profile-preparation-check")}
    require(preparations["native-preparation-check"].get("status") == preparations["profile-preparation-check"].get("status")
            == "DRAFT_NOT_KERNEL_CHECKED", "Generator static check differs")
    parents = {}
    for prefix in ("native", "hook"):
        prior = read_json(files[prefix + "-prior-build"])
        target = prior_result(prior, prefix)
        for role, field in (("heap", "heap"), ("database", "database")):
            require(prior["sessions"][0][field] == {key: by_id[prefix + "-parent-" + role][key] for key in ("bytes", "sha256")},
                    "Prior parent artifact differs: " + prefix)
        parents[prefix] = (target, files[prefix + "-parent-heap"], files[prefix + "-parent-database"])
    hook_root_target, _, _, hook_extra = root_identity(files["hook-prior-root"])
    require(hook_root_target == parents["hook"][0] and len(hook_extra) == 1 and hook_extra[0] != hook_root_target,
            "Prior Hook ROOT differs")
    previous = None
    for run_id, prior_id, sids in RUNS:
        run = runs[run_id]
        require(run == {"id": run_id, "result": run_id + "-result", "inputsBefore": run_id + "-inputs-before",
                        "inputsAfter": run_id + "-inputs-after", "buildLog": run_id + "-build-log",
                        "priorResult": prior_id, "sessions": list(sids)}, "Run linkage differs: " + run_id)
        result = read_json(files[run_id + "-result"])
        targets = [row.get("session") for row in result.get("sessions", [])]
        run_result(result, targets, run_id)
        require(len(targets) == len(sids), "Run session count differs: " + run_id)
        log = files[run_id + "-build-log"].read_text(encoding="utf-8", errors="strict")
        require(re.findall(r"(?m)^Building (\S+) \.\.\.", log) == targets
                and re.findall(r"(?m)^Finished (\S+) \(", log) == targets, "Actual launch set differs: " + run_id)
        required = []
        if prior_id is not None:
            parent, parent_heap, parent_database = parents[prior_id.split("-")[0]]
        else:
            parent, parent_heap, parent_database = previous
        for sid, target in zip(sids, targets):
            session = sessions[sid]
            require(session == {"id": sid, "run": run_id, "source": sid + "-source", "root": sid + "-root",
                                "heap": sid + "-heap", "database": sid + "-database",
                                "explicitRoots": COVERAGE["explicitRoots"][sid]}, "Session linkage differs: " + sid)
            root_target, root_parent, theory, extra = root_identity(files[sid + "-root"])
            require(root_target == target and root_parent == parent, "ROOT target or parent differs: " + sid)
            source_path = files[sid + "-source"]
            source = strip_comments(source_path.read_text(encoding="utf-8-sig"))
            # The Hook stages register exactly the one additional session of their saved parent; others register none.
            require(extra == hook_extra if sid.startswith("hook") else extra == [],
                    "Additional import registration differs: " + sid)
            require(re.search(r"(?m)^theory " + re.escape(theory) + r"\s*$", source)
                    and not re.search(r"\b(?:sorry|oops|admit|axiomatization|native_decide)\b|\bby\s+eval\b|(?m:^\s*oracle\s+)", source),
                    "Source identity or proof escape differs: " + sid)
            static = json.dumps(preparations[PREPARATIONS[sid]])
            require(by_id[sid + "-source"]["sha256"] in static, "Source is not the generator output: " + sid)
            if sid in REPARENTED:
                prepared = files[REPARENTED[sid]].read_text(encoding="utf-8")
                require(by_id[REPARENTED[sid]]["sha256"] in static, "Prepared ROOT is not the generator output: " + sid)
                actual = files[sid + "-root"].read_text(encoding="utf-8")
                prepared_lines, actual_lines = prepared.splitlines(), actual.splitlines()
                require(len(prepared_lines) == len(actual_lines) and prepared_lines[1:] == actual_lines[1:]
                        and re.sub(r"= [A-Z0-9_]+ \+$", "", prepared_lines[0]) == re.sub(r"= [A-Z0-9_]+ \+$", "", actual_lines[0]),
                        "Reparented ROOT changes more than its parent: " + sid)
            else:
                require(by_id[sid + "-root"]["sha256"] in static, "ROOT is not the generator output: " + sid)
            artifact = next(row for row in result["sessions"] if row["session"] == target)
            for role in ("heap", "database"):
                require(artifact[role] == {key: by_id[sid + "-" + role][key] for key in ("bytes", "sha256")},
                        "Saved artifact differs: " + sid)
            heap_lineage(files[sid + "-database"], files[sid + "-heap"], target, parent_database, parent_heap, parent)
            saved_source(files[sid + "-database"], target, source_path, decoder)
            audit_messages(database_messages(files[sid + "-database"], decoder), COVERAGE["explicitRoots"][sid], sid)
            required += [source_path, files[sid + "-root"]]
            parent, parent_heap, parent_database = target, files[sid + "-heap"], files[sid + "-database"]
        live_inputs(read_json(files[run_id + "-inputs-before"], False), read_json(files[run_id + "-inputs-after"], False),
                    required, checked, run_id)
        previous = (parent, parent_heap, parent_database)
    for path, expected in checked.items():
        require(digest(path) == expected, "Evidence changed while checked")
    for key, path in products.items():
        require(digest(path) == identity[key]["sha256"], "Product identity changed while checked")
    require(digest(verifier_file) == verifier["sha256"], "Verifier changed while checked")
    return {"schema": "trust12-malformed-aligned-gate-rehash-v1", "status": "PASS_REGISTERED_MALFORMED_ALIGNED_GATE_REHASHED",
            "registeredRequests": COVERAGE["registeredRequests"], "kernelSessionsRehashed": len(SESSIONS),
            "kernelRunsRehashed": len(RUNS), "artifactsRehashed": len(files), "currentInputsRehashed": len(checked),
            "oracleDependencies": {sid: 0 for sid in SESSIONS}, "generalRuntimeLinksDischarged": False,
            "registeredCentralClosureDischarged": False, "fullTrustCompleted": False,
            "independentAssuranceCompleted": False, "nonclaim": REPRODUCTION_BOUNDARY}


def metadata_only(checkpoint, product):
    public_contract(checkpoint)
    identity = checkpoint["productIdentity"]
    require(set(identity) == set(IDENTITY_PATHS), "Product identity inventory differs")
    for key, value in IDENTITY_PATHS.items():
        file_identity(product, identity[key], value, key)
    verifier = checkpoint["rehashVerifier"]
    require(set(verifier) == {"path", "bytes", "sha256", "command"} and verifier["command"] == COMMAND, "Public command differs")
    file_identity(product, {key: verifier[key] for key in ("path", "bytes", "sha256")}, VERIFIER_PATH, "verifier")
    kinds = expected_kinds()
    require(len(checkpoint["artifacts"]) == len(kinds) and {row["id"] for row in checkpoint["artifacts"]} == set(kinds),
            "Artifact inventory differs")
    for row in checkpoint["artifacts"]:
        require(set(row) == {"id", "kind", "bytes", "sha256"} and row["kind"] == kinds[row["id"]]
                and type(row["bytes"]) is int and row["bytes"] > 0 and re.fullmatch(r"[0-9a-f]{64}", row["sha256"]),
                "Artifact identity differs: " + row["id"])
    return {"status": "PASS_PUBLIC_METADATA_ONLY", "savedArtifactsVerified": False, "freshKernelReplay": False,
            "nonclaims": sorted(NONCLAIM_KEYS)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--product-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--checkpoint", type=Path)
    parser.add_argument("--metadata-only", action="store_true")
    parser.add_argument("--base", type=Path)
    parser.add_argument("--artifact-index", type=Path)
    parser.add_argument("--zstd", default="zstd")
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    product = args.product_root.resolve()
    checkpoint_path = (args.checkpoint or product / CHECKPOINT_PATH).resolve()
    require(checkpoint_path == (product / CHECKPOINT_PATH).resolve(), "Unexpected checkpoint location")
    checkpoint = read_json(checkpoint_path)
    if args.metadata_only:
        require(args.base is None and args.artifact_index is None, "Metadata mode cannot verify saved artifacts")
        report = metadata_only(checkpoint, product)
    else:
        require(args.base is not None and args.artifact_index is not None, "Saved verification requires base and index")
        report = verify_checkpoint(checkpoint, read_json(args.artifact_index), args.base, product, args.zstd)
    if args.out:
        with args.out.open("x", encoding="utf-8", newline="\n") as handle:
            handle.write(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, OSError, ValueError, KeyError, TypeError, ImportError, sqlite3.Error,
            subprocess.CalledProcessError, StopIteration) as error:
        raise SystemExit(f"FAIL: {error}")
