#!/usr/bin/env python3
import argparse
import datetime
import hashlib
import json
import shutil
from pathlib import Path


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repository-root", type=Path, required=True)
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--isabelle-report", type=Path, required=True)
    parser.add_argument("--output-directory", type=Path, required=True)
    parser.add_argument("--curated-evidence-directory", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--executed-runner-sha256")
    parser.add_argument(
        "--status",
        choices=("PASS", "WORKER_REPLAY_CANDIDATE"),
        default="PASS",
    )
    args = parser.parse_args()

    root = args.repository_root.resolve()
    bundle_path = args.bundle.resolve()
    isabelle_path = args.isabelle_report.resolve()
    output = args.output_directory.resolve()
    curated = args.curated_evidence_directory.resolve()
    report_path = args.report.resolve()
    curated.relative_to(root)
    report_path.relative_to(root)
    curated.mkdir(parents=True, exist_ok=True)
    report_path.parent.mkdir(parents=True, exist_ok=True)

    bundle = json.loads(bundle_path.read_text(encoding="utf-8"))
    claim_id = bundle["proofSpec"]["claimId"]
    positive_root = output / "positive-save" / claim_id
    negative_root = output / "negative-save" / claim_id
    positive_proof = positive_root / "proof.json"
    positive_kcfg = positive_root / "kcfg" / "kcfg.json"
    negative_proof = negative_root / "proof.json"
    negative_kcfg = negative_root / "kcfg" / "kcfg.json"
    negative_proof_value = json.loads(negative_proof.read_text(encoding="utf-8"))
    terminal_nodes = [int(node) for node in negative_proof_value.get("terminal", [])]
    if len(terminal_nodes) != 1:
        raise SystemExit("expected exactly one negative terminal semantic counterexample")
    terminal_node = terminal_nodes[0]
    negative_terminal = negative_root / "kcfg" / "nodes" / f"{terminal_node}.json"
    terminal_text = negative_terminal.read_text(encoding="utf-8")
    for token in bundle["negative"]["witnessTokens"]:
        if token not in terminal_text:
            raise SystemExit(f"negative terminal node is missing witness token: {token}")

    sources = {
        "positiveProof": positive_proof,
        "positiveKcfg": positive_kcfg,
        "positiveLog": output / "positive.log",
        "positiveAnalysis": output / "positive-analysis.json",
        "negativeProof": negative_proof,
        "negativeKcfg": negative_kcfg,
        "negativeLog": output / "negative.log",
        "negativeAnalysis": output / "negative-analysis.json",
        "negativeTerminalNode": negative_terminal,
        "bridgeReverseCheck": output / "bridge-reverse-check.json",
        "bundleSchemaValidation": output / "bundle-schema-validation.json",
        "isabelleClosureReport": isabelle_path,
    }
    destinations = {
        key: curated / {
            "positiveProof": "positive-proof.json",
            "positiveKcfg": "positive-kcfg.json",
            "positiveLog": "positive.log",
            "positiveAnalysis": "positive-analysis.json",
            "negativeProof": "negative-proof.json",
            "negativeKcfg": "negative-kcfg.json",
            "negativeLog": "negative.log",
            "negativeAnalysis": "negative-analysis.json",
            "negativeTerminalNode": f"negative-terminal-node-{terminal_node}.json",
            "bridgeReverseCheck": "bridge-reverse-check.json",
            "bundleSchemaValidation": "bundle-schema-validation.json",
            "isabelleClosureReport": "isabelle-closure-report.json",
        }[key]
        for key in sources
    }
    for key, source in sources.items():
        if not source.is_file():
            raise SystemExit(f"missing replay artifact for curation: {source}")
        shutil.copyfile(source, destinations[key])

    def repo(path: Path) -> str:
        return path.resolve().relative_to(root).as_posix()

    def artifact(path: Path) -> dict[str, str]:
        return {"path": repo(path), "sha256": sha256(path)}

    runner_path = root / "formal" / "kevm" / "row-bundles" / "run-row-bundle.sh"
    runner_source_sha = sha256(runner_path)
    executed_runner_sha = args.executed_runner_sha256 or runner_source_sha
    isabelle = json.loads(isabelle_path.read_text(encoding="utf-8"))
    positive_analysis = json.loads(destinations["positiveAnalysis"].read_text(encoding="utf-8"))
    negative_analysis = json.loads(destinations["negativeAnalysis"].read_text(encoding="utf-8"))
    authoritative_fresh_replay_required = args.status != "PASS" or executed_runner_sha != runner_source_sha
    residual = list(bundle["residualNonclaims"])
    if not authoritative_fresh_replay_required:
        exhausted_prerequisite = (
            "Canonical discharge still requires a fresh repository-owned authoritative replay "
            "and shared registry integration by the coordinator."
        )
        residual = [item for item in residual if item != exhausted_prerequisite]
    if authoritative_fresh_replay_required:
        residual.append(
            "Canonical integration must run the improved repository-owned runner fresh; this post-processed worker replay is not authoritative discharge evidence."
        )

    value = {
        "schemaVersion": 2,
        "obligationId": bundle["obligationId"],
        "status": args.status,
        "authoritativeFreshReplayRequired": authoritative_fresh_replay_required,
        "createdAtUtc": datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "claimId": claim_id,
        "runner": {
            "path": repo(runner_path),
            "sourceSha256": runner_source_sha,
            "executedSha256": executed_runner_sha,
        },
        "bundle": artifact(bundle_path),
        "proofSpec": bundle["proofSpec"],
        "definitions": {
            "positive": {
                "definitionKoreSha256": bundle["positive"]["definitionKoreSha256"],
                "compiledJsonSha256": bundle["positive"]["compiledJsonSha256"],
            },
            "negative": {
                "definitionKoreSha256": bundle["negative"]["definitionKoreSha256"],
                "compiledJsonSha256": bundle["negative"]["compiledJsonSha256"],
                "mutationId": bundle["negative"]["mutationId"],
            },
        },
        "bridge": {
            "source": {"path": bundle["bridge"]["path"], "sha256": bundle["bridge"]["sha256"]},
            "reverseCheck": artifact(destinations["bridgeReverseCheck"]),
        },
        "isabelle": {
            "session": bundle["isabelle"]["session"],
            "theoremName": bundle["isabelle"]["theoremName"],
            "theory": {"path": bundle["isabelle"]["theoryPath"], "sha256": bundle["isabelle"]["sourceSha256"]},
            "rowManifest": {"path": bundle["isabelle"]["rowManifestPath"], "sha256": bundle["isabelle"]["rowManifestSha256"]},
            "closureReport": artifact(destinations["isabelleClosureReport"]),
            "oracleDependencyCount": isabelle["oracleDependencyCount"],
        },
        "positive": {
            "analysis": positive_analysis,
            "elapsedWallSeconds": int((output / "positive-elapsed-seconds.txt").read_text()),
            "proof": artifact(destinations["positiveProof"]),
            "kcfg": artifact(destinations["positiveKcfg"]),
            "log": artifact(destinations["positiveLog"]),
        },
        "negative": {
            "analysis": negative_analysis,
            "elapsedWallSeconds": int((output / "negative-elapsed-seconds.txt").read_text()),
            "proof": artifact(destinations["negativeProof"]),
            "kcfg": artifact(destinations["negativeKcfg"]),
            "log": artifact(destinations["negativeLog"]),
            "terminalWitness": {
                **artifact(destinations["negativeTerminalNode"]),
                "nodeId": terminal_node,
                "tokens": bundle["negative"]["witnessTokens"],
                "claimRequirementTokens": bundle["negative"]["claimRequirementTokens"],
            },
            "backendRuntimeError": False,
        },
        "curatedEvidenceDirectory": repo(curated),
        "bundleSchemaValidation": artifact(destinations["bundleSchemaValidation"]),
        "residualNonclaims": residual,
    }
    report_path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({
        "status": value["status"],
        "obligationId": value["obligationId"],
        "claimId": claim_id,
        "report": repo(report_path),
        "reportSha256": sha256(report_path),
        "authoritativeFreshReplayRequired": authoritative_fresh_replay_required,
    }, indent=2))


if __name__ == "__main__":
    main()
