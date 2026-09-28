#!/usr/bin/env python3
"""Rehash a supplied evidence bundle for the registered Partial malformed relation."""
from __future__ import annotations

import argparse
import hashlib
import json
import lzma
import re
import shutil
import sqlite3
import subprocess
from pathlib import Path


STAGE_IDS = (
    "adapter-recorded-code", "token-code-identity", "token-recorded-code", "code-field-consumer",
    "storage-entry-identities", "storage-entry-consumer", "abi-projection-canary",
    "request-rejection-projections", "final-recorded-relation",
)
NONCLAIM_KEYS = {
    "operationalExecutionReceiver", "generalRuntimeLinks", "otherProfiles", "otherRequests",
    "centralRefinementClosure", "independentAssurance", "releaseOrDeployment",
}


def require(condition: object, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def read_json(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    require(isinstance(value, dict), f"JSON object required: {path.name}")
    return value


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def database_messages(path: Path, zstd: str) -> str:
    connection = sqlite3.connect(f"file:{path.as_posix()}?mode=ro", uri=True)
    try:
        rows = connection.execute("select compressed, body from isabelle_exports where name = 'PIDE/messages'").fetchall()
    finally:
        connection.close()
    require(rows, "Isabelle message export is absent")
    messages = []
    for compressed, body in rows:
        data = bytes(body)
        if compressed and data.startswith(b"\x28\xb5\x2f\xfd"):
            data = subprocess.run([zstd, "-d", "-q", "--stdout"], input=data,
                                  check=True, capture_output=True).stdout
        elif compressed and data.startswith(b"\xfd7zXZ\x00"):
            data = lzma.decompress(data)
        elif compressed:
            raise RuntimeError("Unsupported Isabelle message compression")
        messages.append(data.decode("utf-8", errors="strict"))
    return "\n".join(messages)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", type=Path, required=True, help="Root of the supplied evidence bundle")
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--product-root", type=Path, required=True)
    parser.add_argument("--artifact-index", type=Path, required=True,
                        help="Local navigation JSON: artifact IDs mapped to relative paths under --base")
    parser.add_argument("--zstd", default="zstd", help="Zstandard executable used to read Isabelle messages")
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    base = args.base.resolve()
    product = args.product_root.resolve()
    require(args.checkpoint.resolve().is_relative_to(product), "Checkpoint is outside the product root")
    checkpoint = read_json(args.checkpoint)
    index = read_json(args.artifact_index)
    require(checkpoint["schema"] == "trust12-partial-malformed-relation-checkpoint-v1"
            and checkpoint["status"] == "PASS_KERNEL_CHECKED_REGISTERED_PARTIAL_MALFORMED_RELATION",
            "Checkpoint schema or status differs")
    coverage = checkpoint["coverage"]
    require(coverage == {"registeredRequests": 13, "recordedPreWorlds": 2, "kernelStages": 9,
                         "commandRejectionProjections": {"wrongLength": 5, "unknownSelector": 1, "dirtyWord": 6},
                         "finalOracleDependencies": 0},
            "Declared registered relation coverage differs")
    require(set(checkpoint["nonclaims"]) == NONCLAIM_KEYS
            and all(value is True for value in checkpoint["nonclaims"].values()),
            "The bounded checkpoint must preserve its nonclaims")
    prior = checkpoint["priorCodeIdentityCheckpoint"]
    prior_path = (product / prior["path"]).resolve()
    verifier_record = checkpoint["rehashVerifier"]
    verifier_path = (product / verifier_record["path"]).resolve()
    require(prior_path.is_relative_to(product) and verifier_path.is_relative_to(product)
            and prior_path.stat().st_size == prior["bytes"] and digest(prior_path) == prior["sha256"]
            and verifier_path.stat().st_size == verifier_record["bytes"]
            and digest(verifier_path) == verifier_record["sha256"]
            and digest(Path(__file__)) == verifier_record["sha256"],
            "Prior code checkpoint or public verifier identity differs")
    records = checkpoint["artifacts"]
    require(isinstance(records, list) and records, "Artifact records are absent")
    expected = {record["id"]: record for record in records}
    stages = checkpoint["kernelStages"]
    require([stage["id"] for stage in stages] == list(STAGE_IDS), "Kernel stage inventory differs")
    required_artifacts = {"prior-code-root-build", "historical-oracle-diagnostic", "pinned-malformed-abstraction-model"}
    previous = "prior-code-root-build"
    for stage in stages:
        stage_id = stage["id"]
        links = {"id": stage_id, "source": stage_id + "-source", "sessionRoot": stage_id + "-root",
                 "binding": stage_id + "-binding", "result": stage_id + "-build",
                 "heap": stage_id + "-heap", "database": stage_id + "-database", "parentResult": previous}
        require(stage == links, f"Kernel stage linkage differs: {stage_id}")
        required_artifacts.update(links[key] for key in ("source", "sessionRoot", "binding", "result", "heap", "database"))
        previous = stage["result"]
    require(set(expected) == required_artifacts and len(records) == 57,
            "Artifact inventory differs from the kernel stage contract")
    require(len(expected) == len(records) and set(index) == set(expected),
            "Artifact navigation must exactly cover the checkpoint")
    files = {}
    for artifact_id, record in expected.items():
        require(re.fullmatch(r"[a-z0-9-]+", artifact_id) is not None
                and re.fullmatch(r"[0-9a-f]{64}", record["sha256"]) is not None
                and isinstance(record["bytes"], int) and record["bytes"] > 0,
                "Artifact identity is malformed")
        relative = Path(index[artifact_id])
        require(not relative.is_absolute() and ".." not in relative.parts,
                f"Navigation leaves the evidence root: {artifact_id}")
        path = (base / relative).resolve()
        require(path.is_relative_to(base) and path.is_file(), f"Artifact is absent: {artifact_id}")
        require(path.stat().st_size == record["bytes"] and digest(path) == record["sha256"],
                f"Artifact integrity differs: {artifact_id}")
        files[artifact_id] = path
    for stage in stages:
        result = read_json(files[stage["result"]])
        target = result["target"]
        require(result["status"] == "PASS_FINAL_CHAIN_STAGE_BUILT_" + target
                and result["dryRun"] is False and result["exitCode"] == 0
                and result["inputsUnchanged"] is True
                and result["builtSessions"] == result["finishedSessions"] == [target]
                and not result["failedSessions"] and not result["cancelledSessions"]
                and not result["missingArtifacts"]
                and result["compactPolyReceipts"]["valid"] is True,
                f"Kernel result is incomplete: {stage['id']}")
        require(len(result["sessions"]) == 1 and result["sessions"][0]["session"] == target,
                f"Kernel artifact session differs: {stage['id']}")
        artifact = result["sessions"][0]
        require(artifact["heap"]["sha256"] == expected[stage["heap"]]["sha256"]
                and artifact["database"]["sha256"] == expected[stage["database"]]["sha256"],
                f"Kernel artifact binding differs: {stage['id']}")
        binding = read_json(files[stage["binding"]])
        require(binding["session"] == target
                and binding["theorySha256"] == expected[stage["source"]]["sha256"]
                and binding["rootSha256"] == expected[stage["sessionRoot"]]["sha256"],
                f"Proof source binding differs: {stage['id']}")
        parent_result = read_json(files[stage["parentResult"]])
        require(binding["parent"] == parent_result["target"]
                and binding["parentResultSha256"] == expected[stage["parentResult"]]["sha256"],
                f"Parent result binding differs: {stage['id']}")
    zstd = shutil.which(args.zstd) if not Path(args.zstd).is_file() else args.zstd
    require(zstd is not None, "A Zstandard executable is required for Isabelle message audits")
    counts = {}
    for check in checkpoint["oracleAudits"]:
        message = database_messages(files[check["database"]], zstd)
        values = re.findall(re.escape(check["countMarker"]) + r"([0-9]+)", message)
        require(values == [str(check["dependencies"])], f"Oracle audit differs: {check['id']}")
        if check.get("passMarker"):
            require(check["passMarker"] in message, f"Oracle pass marker is absent: {check['id']}")
        counts[check["id"]] = int(values[0])
    require(counts == {"historical-baseline": 32, "code-field-consumer": 28,
                      "storage-entry-consumer": 24, "final-recorded-relation": 0},
            "Oracle progression differs")
    report = {"schema": "trust12-partial-malformed-relation-rehash-v1",
              "status": "PASS_REGISTERED_PARTIAL_MALFORMED_RELATION_REHASHED",
              "registeredRequests": 13, "kernelBuildsRehashed": len(stages),
              "artifactsRehashed": len(records), "oracleDependencies": counts,
              "operationalExecutionReceiverDischarged": False,
              "generalRuntimeLinksDischarged": False, "independentAssuranceCompleted": False,
              "nonclaim": "Rehashes the named successful local build artifacts and their Isabelle oracle messages; this is not a fresh kernel replay or end-to-end refinement."}
    if args.out:
        args.out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, OSError, KeyError, ValueError, sqlite3.Error, subprocess.CalledProcessError) as error:
        raise SystemExit(f"FAIL: {error}")
