#!/usr/bin/env python3
"""Independent verifier for one S1 ABI-04 dynamic-offset replay report."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path


FORBIDDEN = (
    "Runtime error",
    "Proof crashed",
    "timed out",
    "timeout",
    "canceled",
    "cancelled",
    "SMT solver error",
    "BackendError",
)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="strict").replace("\r\n", "\n")


def integer(path: Path) -> int:
    return int(text(path).strip())


def count_collection(value: object) -> int:
    return len(value) if isinstance(value, (list, dict)) else 0


def apply_label(value: object) -> str | None:
    if not isinstance(value, dict):
        return None
    label = value.get("label")
    return label.get("name") if isinstance(label, dict) else None


def find_applies(value: object, label: str) -> list[dict]:
    matches: list[dict] = []

    def walk(item: object) -> None:
        if isinstance(item, list):
            for child in item:
                walk(child)
        elif isinstance(item, dict):
            if apply_label(item) == label:
                matches.append(item)
            for child in item.values():
                walk(child)

    walk(value)
    return matches


def direct_child_apply(value: dict, label: str) -> dict | None:
    return next((item for item in value.get("args", []) if apply_label(item) == label), None)


def cell_value(cell: dict | None, label: str) -> dict:
    if not isinstance(cell, dict) or len(cell.get("args", [])) != 1:
        raise SystemExit(f"missing or malformed {label} cell")
    value = cell["args"][0]
    if not isinstance(value, dict):
        raise SystemExit(f"malformed {label} cell value")
    return value


def token_value(value: dict, label: str) -> str:
    if value.get("node") != "KToken" or not isinstance(value.get("token"), str):
        raise SystemExit(f"{label} is not a KToken")
    return value["token"]


def single_cell(root: dict, label: str) -> dict:
    cells = find_applies(root, label)
    if len(cells) != 1:
        raise SystemExit(f"expected one {label} cell, found {len(cells)}")
    return cells[0]


def pending_count(proof: dict, log: str) -> int:
    if "pending" in proof:
        return count_collection(proof["pending"])
    match = re.search(r"\((\d+)\s+pending\s+and\s+\d+\s+failing\)", log, re.I)
    if match:
        return int(match.group(1))
    if f"PROOF PASSED: {proof['id']}" in log:
        return 0
    raise SystemExit("independent verifier cannot determine pending count")


def contained(root: Path, candidate: Path) -> Path:
    value = candidate.resolve()
    value.relative_to(root.resolve())
    return value


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--expected", type=Path, required=True)
    parser.add_argument("--analysis", type=Path, required=True)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()

    root = args.output_root.resolve()
    expected_path = args.expected.resolve()
    analysis_path = args.analysis.resolve()
    expected = json.loads(text(expected_path))
    analysis = json.loads(text(analysis_path))
    snapshot = root / "input-snapshot"

    if analysis["status"] != "PASS" or analysis["proofCreditBoundary"] != "LEAF_REPLAY_ONLY_NOT_CENTRAL_DISCHARGE":
        raise SystemExit("analysis status or proof-credit boundary mismatch")
    for key in ("claimId", "side", "sourceClaimSha256", "strippedClaimSha256"):
        if analysis[key] != expected[key]:
            raise SystemExit(f"analysis/expected mismatch: {key}")
    if analysis["proofId"] != expected["proofId"]:
        raise SystemExit("analysis/expected proof ID mismatch")
    if sha256(expected_path) != analysis["expectedGraphContract"]["sha256"]:
        raise SystemExit("expected graph contract SHA-256 mismatch")

    if text(root / "claim-id.txt").strip() != expected["claimId"]:
        raise SystemExit("claim ID record mismatch")
    if text(root / "replay-side.txt").strip() != expected["side"]:
        raise SystemExit("side record mismatch")
    if integer(root / "expected-exit-code.txt") != expected["processExitCode"]:
        raise SystemExit("expected exit record mismatch")
    if integer(root / "proof-exit-code.txt") != expected["processExitCode"]:
        raise SystemExit("proof exit mismatch")
    if integer(root / "exit-code.txt") != expected["launcherExitCode"]:
        raise SystemExit("launcher exit mismatch")
    if text(root / "run-classification.txt").strip() != expected["runClassification"]:
        raise SystemExit("run classification mismatch")
    if text(root / "input-integrity-status.txt").strip() != "PASS":
        raise SystemExit("input integrity did not pass")
    if integer(root / "post-run-owned-session-survivor-count.txt") != 0:
        raise SystemExit("owned proof session has survivors")
    if integer(root / "elapsed-seconds.txt") < 0:
        raise SystemExit("negative elapsed time")
    child_pid = integer(root / "child-pid.txt")
    if integer(root / "child-sid.txt") != child_pid or integer(root / "child-pgid.txt") != child_pid:
        raise SystemExit("child PID/SID/PGID ownership mismatch")

    manifest = snapshot / "snapshot-files.sha256"
    if text(root / "snapshot-manifest.sha256").strip() != sha256(manifest):
        raise SystemExit("snapshot manifest digest mismatch")
    snapshot_paths: set[str] = set()
    for line in text(manifest).splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})\s+[ *](.+)", line)
        if not match:
            raise SystemExit(f"invalid snapshot manifest line: {line}")
        relative = match.group(2).removeprefix("./")
        if relative in snapshot_paths:
            raise SystemExit(f"duplicate snapshot path: {relative}")
        snapshot_paths.add(relative)
        candidate = contained(snapshot, snapshot / relative)
        if sha256(candidate) != match.group(1):
            raise SystemExit(f"snapshot hash mismatch: {relative}")

    execution = json.loads(text(snapshot / "execution-manifest.json"))
    prior_pair_binders = execution.get("priorAuthoritativePairBinders", [])
    if prior_pair_binders != []:
        raise SystemExit("prior authoritative pair binders are forbidden for the S1 wave")
    if execution.get("priorAuthoritativePairBindersIncluded") is not False:
        raise SystemExit("execution manifest prior binder flag drift")
    before = text(root / "live-input-hashes-before.sha256")
    after = text(root / "live-input-hashes-after.sha256")
    if before != after:
        raise SystemExit("live inputs changed during replay")
    live_lines = before.splitlines()
    if len(live_lines) != 7:
        raise SystemExit("live input hash cardinality mismatch")
    live_hashes = []
    for line in live_lines:
        match = re.fullmatch(r"([0-9a-f]{64})\s+(.+)", line)
        if not match:
            raise SystemExit(f"invalid live input hash line: {line}")
        live_hashes.append(match.group(1))
    first_live_hash = live_hashes[0]
    if sha256(snapshot / "launcher.sh") != first_live_hash or analysis["runnerSha256"] != first_live_hash:
        raise SystemExit("executed launcher identity mismatch")
    if live_hashes[1] != expected["sourceClaimSha256"] or sha256(snapshot / "claim-source.k") != expected["sourceClaimSha256"]:
        raise SystemExit("source claim snapshot mismatch")
    if sha256(snapshot / "analyze-dynamic-offset-replay-v1.mjs") != live_hashes[2] or analysis["analysisToolSha256"] != live_hashes[2]:
        raise SystemExit("analysis tool snapshot mismatch")
    if sha256(snapshot / "verify-dynamic-offset-replay-v1.py") != live_hashes[3] or analysis["independentVerifierSha256"] != live_hashes[3]:
        raise SystemExit("independent verifier snapshot mismatch")
    if sha256(snapshot / "verify-freeze-receipt.py") != live_hashes[4]:
        raise SystemExit("closure freeze verifier snapshot mismatch")
    if sha256(root / "claim.k") != expected["strippedClaimSha256"]:
        raise SystemExit("stripped claim mismatch")

    wave = json.loads(text(snapshot / "s1-dynamic-offset-wave-contract-v1.json"))
    snapshot_expected = snapshot / "expected-graph-contract.json"
    if sha256(snapshot_expected) != sha256(expected_path):
        raise SystemExit("pre-run expected graph snapshot hash mismatch")
    if json.loads(text(snapshot_expected)) != expected:
        raise SystemExit("pre-run expected graph snapshot content mismatch")
    if execution["claimId"] != expected["claimId"] or execution["side"] != expected["side"]:
        raise SystemExit("execution manifest replay identity mismatch")
    if execution.get("expectedGraphSha256") != sha256(expected_path):
        raise SystemExit("execution manifest expected graph hash mismatch")
    if execution.get("analysisToolSha256") != live_hashes[2] or execution.get("independentVerifierSha256") != live_hashes[3]:
        raise SystemExit("execution manifest verification tool hash mismatch")
    if execution.get("definitionKoreSha256") != live_hashes[5] or execution.get("compiledJsonSha256") != live_hashes[6]:
        raise SystemExit("execution manifest definition hash mismatch")
    if execution["kevmSemanticsTag"] != "v1.0.921" or execution["kevmSemanticsCommit"] != "d4bf484a5dfe1e38d729a30434cd6f41e3590fb2":
        raise SystemExit("KEVM semantics identity mismatch")
    if wave["centralBindingAllowed"] is not False or wave["exactReplayCount"] != 12:
        raise SystemExit("S1 wave boundary mismatch")

    save = root / "save"
    proof_roots = sorted(item for item in save.iterdir() if item.is_dir() and re.fullmatch(r"[0-9a-f]{64}", item.name))
    if [item.name for item in proof_roots] != [expected["proofId"]]:
        raise SystemExit("proof ID exact-set mismatch")
    proof_root = proof_roots[0]
    proof_path = proof_root / "proof.json"
    kcfg_path = proof_root / "kcfg" / "kcfg.json"
    nodes_root = proof_root / "kcfg" / "nodes"
    log_path = root / "prove.log"
    proof = json.loads(text(proof_path))
    kcfg = json.loads(text(kcfg_path))
    log = text(log_path)
    if proof["id"] != expected["proofId"] or proof.get("admitted") is not False:
        raise SystemExit("proof identity or admitted flag mismatch")
    lower_log = log.lower()
    for token in FORBIDDEN:
        if token.lower() in lower_log:
            raise SystemExit(f"forbidden log token: {token}")
    if expected["statusMarker"] not in log:
        raise SystemExit("proof status marker mismatch")

    graph = {
        "nodes": count_collection(kcfg.get("nodes")),
        "edges": count_collection(kcfg.get("edges")),
        "covers": count_collection(kcfg.get("covers")),
        "terminal": count_collection(proof.get("terminal")),
        "stuck": count_collection(kcfg.get("stuck")),
        "vacuous": count_collection(kcfg.get("vacuous")),
        "pending": pending_count(proof, log),
        "bounded": count_collection(kcfg.get("bounded")),
        "admitted": proof.get("admitted"),
    }
    if graph != expected["graph"] or graph != analysis["graph"]:
        raise SystemExit("independently recomputed graph mismatch")
    if graph["pending"] or graph["stuck"] or graph["vacuous"] or graph["bounded"]:
        raise SystemExit("incomplete, stuck, vacuous, or bounded graph")
    if expected["side"] == "canonical-positive" and graph["terminal"] != 0:
        raise SystemExit("canonical proof has a terminal branch")
    if expected["side"] == "mutant-negative" and graph["terminal"] != 1:
        raise SystemExit("mutant proof does not have exactly one terminal witness")

    terminal_node_ids = [int(node_id) for node_id in proof.get("terminal", [])]
    if terminal_node_ids != expected.get("terminalNodeIds", terminal_node_ids):
        raise SystemExit("terminal node ID exact-set mismatch")
    terminal_paths = [nodes_root / f"{node_id}.json" for node_id in terminal_node_ids]
    terminal_corpus = "".join(text(path) for path in terminal_paths)
    for token in expected.get("terminalWitnessTokens", []):
        if token not in terminal_corpus:
            raise SystemExit(f"missing terminal witness token: {token}")

    terminal_witness_observation = None
    if expected["side"] == "mutant-negative":
        witness = expected.get("terminalWitness")
        if not isinstance(witness, dict) or len(terminal_paths) != 1:
            raise SystemExit("missing structural terminal witness contract")
        terminal = json.loads(text(terminal_paths[0]))
        output = cell_value(single_cell(terminal, "<output>"), "<output>")
        status = cell_value(single_cell(terminal, "<statusCode>"), "<statusCode>")
        log_cell = cell_value(single_cell(terminal, "<log>"), "<log>")
        tx_pending = cell_value(single_cell(terminal, "<txPending>"), "<txPending>")
        if token_value(output, "<output>") != witness["outputToken"]:
            raise SystemExit("terminal output token mismatch")
        if apply_label(status) != witness["statusLabel"]:
            raise SystemExit("terminal status mismatch")
        if apply_label(log_cell) != witness["logLabel"]:
            raise SystemExit("terminal log mismatch")
        if apply_label(tx_pending) != witness["txPendingLabel"]:
            raise SystemExit("terminal txPending mismatch")

        accounts = find_applies(terminal, "<account>")

        def account_by_id(account_id: str) -> dict | None:
            for account in accounts:
                id_cell = direct_child_apply(account, "<acctID>")
                if id_cell and token_value(cell_value(id_cell, "<acctID>"), "<acctID>") == account_id:
                    return account
            return None

        endpoint = account_by_id(witness["endpointAccountId"])
        sender = account_by_id(witness["senderAccountId"])
        if endpoint is None or sender is None:
            raise SystemExit("terminal endpoint or sender account missing")
        endpoint_storage = cell_value(direct_child_apply(endpoint, "<storage>"), "<storage>")
        endpoint_orig_storage = cell_value(direct_child_apply(endpoint, "<origStorage>"), "<origStorage>")
        if endpoint_storage != endpoint_orig_storage:
            raise SystemExit("endpoint storage/original-storage did not stutter")
        endpoint_nonce = token_value(cell_value(direct_child_apply(endpoint, "<nonce>"), "<nonce>"), "endpoint nonce")
        sender_nonce = token_value(cell_value(direct_child_apply(sender, "<nonce>"), "<nonce>"), "sender nonce")
        if endpoint_nonce != witness["endpointNonce"] or sender_nonce != witness["senderNonce"]:
            raise SystemExit("terminal nonce mismatch")
        terminal_witness_observation = {
            "nodeId": terminal_node_ids[0],
            "outputToken": token_value(output, "<output>"),
            "statusLabel": apply_label(status),
            "logLabel": apply_label(log_cell),
            "txPendingLabel": apply_label(tx_pending),
            "endpointAccountId": witness["endpointAccountId"],
            "endpointNonce": endpoint_nonce,
            "endpointStorageEqualsOriginal": True,
            "senderAccountId": witness["senderAccountId"],
            "senderNonce": sender_nonce,
        }
        if analysis.get("terminalWitnessObservation") != terminal_witness_observation:
            raise SystemExit("analysis structural terminal witness mismatch")

    artifact_checks = {
        "proof": proof_path,
        "kcfg": kcfg_path,
        "log": log_path,
        "snapshotManifest": manifest,
    }
    for key, artifact_path in artifact_checks.items():
        if contained(root, Path(analysis[key]["path"])) != artifact_path.resolve():
            raise SystemExit(f"analysis artifact path mismatch: {key}")
        if analysis[key]["sha256"] != sha256(artifact_path):
            raise SystemExit(f"analysis artifact digest mismatch: {key}")

    result = {
        "schemaVersion": 1,
        "status": "PASS",
        "obligationId": "ABI-04",
        "stage": "S1",
        "claimId": expected["claimId"],
        "proofId": expected["proofId"],
        "side": expected["side"],
        "graph": graph,
        "terminalWitnessObservation": terminal_witness_observation,
        "analysisSha256": sha256(analysis_path),
        "expectedGraphContractSha256": sha256(expected_path),
        "verifiedSnapshotFiles": len(snapshot_paths),
        "proofCreditBoundary": "LEAF_REPLAY_ONLY_NOT_CENTRAL_DISCHARGE",
    }
    serialized = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if args.report:
        args.report.resolve().write_text(serialized, encoding="utf-8", newline="\n")
    print(serialized, end="")


if __name__ == "__main__":
    main()
