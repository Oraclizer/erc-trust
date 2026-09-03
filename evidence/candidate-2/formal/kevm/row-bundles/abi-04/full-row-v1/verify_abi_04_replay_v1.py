#!/usr/bin/env python3
"""Independent stdlib-only structural verifier for one ABI-04 row replay."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

FORBIDDEN_LOG_TOKENS = (
    "runtime error", "proof crashed", "timed out", "timeout", "canceled",
    "cancelled", "smt solver error", "backenderror",
)
REPOSITORY_ROOT = Path(__file__).resolve().parents[5]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8").replace("\r\n", "\n")


def read_json(path: Path) -> Any:
    return json.loads(read_text(path))


def read_int(path: Path) -> int:
    return int(read_text(path).strip())


def repository_bound(relative: str, label: str) -> Path:
    candidate = Path(relative)
    if candidate.is_absolute():
        raise SystemExit(f"{label}: expected repository-relative path")
    resolved = REPOSITORY_ROOT.joinpath(*relative.split("/")).resolve()
    if REPOSITORY_ROOT not in resolved.parents:
        raise SystemExit(f"{label}: repository path escape")
    return resolved


def count_collection(value: Any) -> int:
    if isinstance(value, (list, dict)):
        return len(value)
    return 0


def apply_label(value: Any) -> str | None:
    if not isinstance(value, dict):
        return None
    label = value.get("label")
    return label.get("name") if isinstance(label, dict) else None


def find_applies(value: Any, label: str, matches: list[dict[str, Any]] | None = None) -> list[dict[str, Any]]:
    if matches is None:
        matches = []
    if isinstance(value, list):
        for item in value:
            find_applies(item, label, matches)
    elif isinstance(value, dict):
        if apply_label(value) == label:
            matches.append(value)
        for item in value.values():
            find_applies(item, label, matches)
    return matches


def direct_child_apply(value: dict[str, Any], label: str) -> dict[str, Any] | None:
    for item in value.get("args", []):
        if apply_label(item) == label:
            return item
    return None


def cell_value(cell: dict[str, Any] | None, label: str) -> Any:
    if not isinstance(cell, dict) or len(cell.get("args", [])) != 1:
        raise SystemExit(f"missing or malformed {label} cell")
    return cell["args"][0]


def single_cell(root: Any, label: str) -> dict[str, Any]:
    cells = find_applies(root, label)
    if len(cells) != 1:
        raise SystemExit(f"expected one {label} cell, found {len(cells)}")
    return cells[0]


def token_value(value: Any, label: str) -> str:
    if not isinstance(value, dict) or value.get("node") != "KToken" or not isinstance(value.get("token"), str):
        raise SystemExit(f"{label} is not a KToken")
    return value["token"]


def pending_count(proof: dict[str, Any], log_text: str) -> int:
    if "pending" in proof:
        return count_collection(proof["pending"])
    import re
    match = re.search(r"\((\d+)\s+pending\s+and\s+\d+\s+failing\)", log_text, re.I)
    if match:
        return int(match.group(1))
    if f"PROOF PASSED: {proof['id']}" in log_text:
        return 0
    raise SystemExit("proof serialization has no pending set and log has no pending summary")


def verify_snapshot(snapshot_root: Path) -> tuple[Path, list[dict[str, str]]]:
    manifest_path = snapshot_root / "snapshot-files.json"
    entries = read_json(manifest_path)
    if not isinstance(entries, list) or not entries:
        raise SystemExit("empty snapshot manifest")
    paths = [item.get("path") for item in entries]
    if len(set(paths)) != len(paths):
        raise SystemExit("duplicate snapshot path")
    root = snapshot_root.resolve()
    for item in entries:
        relative = item["path"]
        target = snapshot_root.joinpath(*relative.split("/")).resolve()
        if root not in target.parents:
            raise SystemExit(f"snapshot path escape: {relative}")
        if sha256(target) != item["sha256"]:
            raise SystemExit(f"snapshot mismatch: {relative}")
    return manifest_path, entries


def terminal_observation(terminal: Any, witness: dict[str, str]) -> dict[str, Any]:
    output = cell_value(single_cell(terminal, "<output>"), "<output>")
    status = cell_value(single_cell(terminal, "<statusCode>"), "<statusCode>")
    log = cell_value(single_cell(terminal, "<log>"), "<log>")
    tx_pending = cell_value(single_cell(terminal, "<txPending>"), "<txPending>")
    if token_value(output, "<output>") != witness["outputToken"]:
        raise SystemExit("terminal output mismatch")
    if apply_label(status) != witness["statusLabel"] or apply_label(log) != witness["logLabel"] or apply_label(tx_pending) != witness["txPendingLabel"]:
        raise SystemExit("terminal status/log/txPending mismatch")
    accounts = find_applies(terminal, "<account>")

    def account_by_id(account_id: str) -> dict[str, Any] | None:
        for account in accounts:
            id_cell = direct_child_apply(account, "<acctID>")
            if id_cell and token_value(cell_value(id_cell, "<acctID>"), "<acctID>") == account_id:
                return account
        return None

    endpoint = account_by_id(witness["endpointAccountId"])
    sender = account_by_id(witness["senderAccountId"])
    if endpoint is None or sender is None:
        raise SystemExit("terminal account witness missing")
    storage = cell_value(direct_child_apply(endpoint, "<storage>"), "<storage>")
    original_storage = cell_value(direct_child_apply(endpoint, "<origStorage>"), "<origStorage>")
    if storage != original_storage:
        raise SystemExit("endpoint storage did not stutter")
    endpoint_nonce = token_value(cell_value(direct_child_apply(endpoint, "<nonce>"), "<nonce>"), "endpoint nonce")
    sender_nonce = token_value(cell_value(direct_child_apply(sender, "<nonce>"), "<nonce>"), "sender nonce")
    if endpoint_nonce != witness["endpointNonce"] or sender_nonce != witness["senderNonce"]:
        raise SystemExit("terminal nonce mismatch")
    return {
        "outputToken": token_value(output, "<output>"),
        "statusLabel": apply_label(status),
        "logLabel": apply_label(log),
        "txPendingLabel": apply_label(tx_pending),
        "endpointAccountId": witness["endpointAccountId"],
        "endpointNonce": endpoint_nonce,
        "endpointStorageEqualsOriginal": True,
        "senderAccountId": witness["senderAccountId"],
        "senderNonce": sender_nonce,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("output_root", type=Path)
    parser.add_argument("index", type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    output_root = args.output_root.resolve()
    index_path = args.index.resolve()
    index = read_json(index_path)
    if index.get("kind") != "ABI04_FULL_ROW_REPLAY_INDEX_V1":
        raise SystemExit("wrong replay index kind")
    replay_id = read_text(output_root / "replay-id.txt").strip()
    matches = [item for item in index["records"] if item["replayId"] == replay_id]
    if len(matches) != 1:
        raise SystemExit(f"replay absent or duplicate in exact index: {replay_id}")
    record = matches[0]
    snapshot_root = output_root / "input-snapshot"
    if read_text(output_root / "semantic-claim-id.txt").strip() != record["semanticClaimId"]:
        raise SystemExit("semantic claim mismatch")
    if read_text(output_root / "execution-side.txt").strip() != record["executionSide"]:
        raise SystemExit("execution side mismatch")
    for name in ("expected-exit-code.txt", "proof-exit-code.txt", "exit-code.txt"):
        if read_int(output_root / name) != record["expectedProcessExitCode"]:
            raise SystemExit(f"exit mismatch: {name}")
    if read_text(output_root / "input-integrity-status.txt").strip() != "PASS":
        raise SystemExit("input integrity failed")
    if read_int(output_root / "post-run-owned-session-survivor-count.txt") != 0:
        raise SystemExit("owned process survivor")
    manifest_path, snapshot_entries = verify_snapshot(snapshot_root)
    if sha256(manifest_path) != read_text(output_root / "snapshot-manifest.sha256").strip():
        raise SystemExit("snapshot manifest hash mismatch")
    if sha256(snapshot_root / "claim-source.k") != record["claim"]["sha256"]:
        raise SystemExit("claim source hash mismatch")
    if sha256(output_root / "claim.k") != record["strippedClaimSha256"]:
        raise SystemExit("stripped claim hash mismatch")
    if read_json(snapshot_root / "record.json") != record or read_json(snapshot_root / "full-row-replay-index-v1.json") != index:
        raise SystemExit("snapshotted record/index mismatch")
    execution = read_json(snapshot_root / "execution-manifest.json")
    pre_closure = read_json(output_root / "pre-proof-closure-verification.json")
    closure_files_before = read_json(output_root / "closure-freeze-files-before.json")
    if not isinstance(closure_files_before, list) or not closure_files_before:
        raise SystemExit("empty closure freeze manifest")
    expected_snapshot_paths = sorted([
        "run-abi-04-replay-v1.mjs", "claim-source.k", "analyze-abi-04-replay-v1.mjs",
        "verify_abi_04_replay_v1.py", "verify-freeze-receipt.py", "full-row-replay-index-v1.json",
        "s1-toolchain-contract-v1.json", "record.json", "execution-manifest.json",
        *[f"closure-freeze/{item['path']}" for item in closure_files_before],
    ])
    if sorted(item["path"] for item in snapshot_entries) != expected_snapshot_paths:
        raise SystemExit("snapshot exact path set mismatch")
    snapshot_by_path = {item["path"]: item for item in snapshot_entries}
    expected_static_hashes = {
        "run-abi-04-replay-v1.mjs": index["sourceBinding"]["tools"]["runner"]["sha256"],
        "claim-source.k": record["claim"]["sha256"],
        "analyze-abi-04-replay-v1.mjs": index["sourceBinding"]["tools"]["javascriptAnalyzer"]["sha256"],
        "verify_abi_04_replay_v1.py": index["sourceBinding"]["tools"]["pythonVerifier"]["sha256"],
        "verify-freeze-receipt.py": index["sourceBinding"]["tools"]["freezeVerifier"]["sha256"],
        "full-row-replay-index-v1.json": sha256(index_path),
        "s1-toolchain-contract-v1.json": index["sourceBinding"]["toolchainContract"]["sha256"],
    }
    for relative, expected in expected_static_hashes.items():
        if snapshot_by_path.get(relative, {}).get("sha256") != expected:
            raise SystemExit(f"snapshot bound hash mismatch: {relative}")
    for item in closure_files_before:
        if snapshot_by_path.get(f"closure-freeze/{item['path']}", {}).get("sha256") != item["sha256"]:
            raise SystemExit(f"snapshot closure hash mismatch: {item['path']}")
    before = read_json(output_root / "live-input-hashes-before.json")
    after = read_json(output_root / "live-input-hashes-after.json")
    if before != after:
        raise SystemExit("live input hashes changed during replay")
    definition = index["definitions"]["canonicalPositive" if record["executionSide"] == "canonical-positive" else "mutantNegative"]
    child_pid = read_int(output_root / "child-pid.txt")
    child_sid = read_int(output_root / "child-sid.txt")
    child_pgid = read_int(output_root / "child-pgid.txt")
    launcher_pgid = read_int(output_root / "launcher-pgid.txt")
    if child_pid != child_sid or child_pid != child_pgid or child_pgid == launcher_pgid:
        raise SystemExit("child session identity mismatch")
    birth_receipt = read_json(output_root / "child-birth-receipt.json")
    session_receipt = read_json(output_root / "child-session-receipt.json")
    if birth_receipt != {
        "schemaVersion": 1, "kind": "ABI04_PROOF_CHILD_BIRTH_RECEIPT_V1", "pid": child_pid,
        "bootId": birth_receipt.get("bootId"), "startTimeTicks": birth_receipt.get("startTimeTicks"),
    }:
        raise SystemExit("child birth receipt exact schema mismatch")
    import re
    if not re.fullmatch(r"[0-9a-f-]{36}", birth_receipt["bootId"]) or not re.fullmatch(r"[0-9]+", birth_receipt["startTimeTicks"]):
        raise SystemExit("child birth receipt value mismatch")
    if birth_receipt["bootId"] != read_text(Path("/proc/sys/kernel/random/boot_id")).strip():
        raise SystemExit("Linux boot ID changed")
    if session_receipt != {
        "schemaVersion": 1, "kind": "ABI04_PROOF_CHILD_SESSION_RECEIPT_V1", "pid": child_pid,
        "sid": child_sid, "pgid": child_pgid, "launcherPgid": launcher_pgid,
        "bootId": birth_receipt["bootId"], "startTimeTicks": birth_receipt["startTimeTicks"],
    }:
        raise SystemExit("child session receipt exact schema mismatch")
    expected_live_inputs = [
        {"role": "runner", "path": str(repository_bound(index["sourceBinding"]["tools"]["runner"]["path"], "runner")), "sha256": index["sourceBinding"]["tools"]["runner"]["sha256"]},
        {"role": "claim", "path": str(repository_bound(record["claim"]["path"], "claim")), "sha256": record["claim"]["sha256"]},
        {"role": "javascript-analyzer", "path": str(repository_bound(index["sourceBinding"]["tools"]["javascriptAnalyzer"]["path"], "javascript-analyzer")), "sha256": index["sourceBinding"]["tools"]["javascriptAnalyzer"]["sha256"]},
        {"role": "python-verifier", "path": str(repository_bound(index["sourceBinding"]["tools"]["pythonVerifier"]["path"], "python-verifier")), "sha256": index["sourceBinding"]["tools"]["pythonVerifier"]["sha256"]},
        {"role": "freeze-verifier", "path": str(repository_bound(index["sourceBinding"]["tools"]["freezeVerifier"]["path"], "freeze-verifier")), "sha256": index["sourceBinding"]["tools"]["freezeVerifier"]["sha256"]},
        {"role": "replay-index", "path": str(index_path), "sha256": sha256(index_path)},
        {"role": "definition.kore", "path": str(Path(definition["absoluteRoot"]) / "definition.kore"), "sha256": definition["definitionKoreSha256"]},
        {"role": "compiled.json", "path": str(Path(definition["absoluteRoot"]) / "compiled.json"), "sha256": definition["compiledJsonSha256"]},
        {"role": "closure-worker-result", "path": str(Path(execution["closureFreezeRoot"]) / "worker-result.json"), "sha256": pre_closure["workerResultSha256"]},
        {"role": "node-executable", "path": index["toolchain"]["node"]["executable"], "sha256": index["toolchain"]["node"]["sha256"]},
        {"role": "python-executable", "path": index["toolchain"]["python"]["executable"], "sha256": index["toolchain"]["python"]["sha256"]},
        {"role": "bash-executable", "path": index["toolchain"]["bash"]["executable"], "sha256": index["toolchain"]["bash"]["sha256"]},
        {"role": "kevm-executable", "path": index["toolchain"]["kevm"]["executable"], "sha256": index["toolchain"]["kevm"]["sha256"]},
        {"role": "kprove-executable", "path": index["toolchain"]["kprove"]["executable"], "sha256": index["toolchain"]["kprove"]["sha256"]},
        {"role": "kore-rpc-executable", "path": index["toolchain"]["koreRpc"]["executable"], "sha256": index["toolchain"]["koreRpc"]["sha256"]},
        {"role": "setsid-executable", "path": index["toolchain"]["setsid"]["executable"], "sha256": index["toolchain"]["setsid"]["sha256"]},
        {"role": "timeout-executable", "path": index["toolchain"]["timeout"]["executable"], "sha256": index["toolchain"]["timeout"]["sha256"]},
        {"role": "ps-executable", "path": index["toolchain"]["ps"]["executable"], "sha256": index["toolchain"]["ps"]["sha256"]},
    ]
    if before != expected_live_inputs:
        raise SystemExit("live input exact ordered role/path/hash mismatch")
    if execution["replayId"] != replay_id or execution["claimSourceSha256"] != record["claim"]["sha256"] or execution["strippedClaimSha256"] != record["strippedClaimSha256"]:
        raise SystemExit("execution manifest claim binding mismatch")
    if execution["definitionKoreSha256"] != before[6]["sha256"] or execution["compiledJsonSha256"] != before[7]["sha256"] or execution["closureFreezeWorkerResultSha256"] != before[8]["sha256"]:
        raise SystemExit("execution manifest live binding mismatch")
    expected_command = [
        index["toolchain"]["setsid"]["executable"], "--wait", index["toolchain"]["timeout"]["executable"],
        "--signal=TERM", "--kill-after=30s", "7200", index["toolchain"]["kevm"]["executable"], "prove",
        str(output_root / "claim.k"), "--definition", definition["absoluteRoot"], "--spec-module", record["module"],
        "--save-directory", str(output_root / "save"), "--temp-directory", str(output_root / "temp"),
        "--kore-rpc-command", index["toolchain"]["koreRpc"]["executable"], "--no-use-booster", "--workers", "1",
        "--force-sequential", "--max-depth", "1",
    ]
    if execution["command"] != expected_command or read_json(output_root / "invocation.json") != expected_command:
        raise SystemExit("execution invocation command mismatch")
    if pre_closure.get("status") != "PASS" or read_json(output_root / "post-proof-closure-verification.json").get("status") != "PASS":
        raise SystemExit("closure verification failed")
    if read_json(output_root / "closure-freeze-files-before.json") != read_json(output_root / "closure-freeze-files-after.json"):
        raise SystemExit("closure freeze changed")

    save_root = output_root / "save"
    proof_ids = [item.name for item in save_root.iterdir() if item.is_dir() and len(item.name) == 64 and all(c in "0123456789abcdef" for c in item.name)]
    if len(proof_ids) != 1:
        raise SystemExit("proof ID exact-set mismatch")
    proof_id = proof_ids[0]
    proof_root = save_root / proof_id
    proof_path = proof_root / "proof.json"
    kcfg_path = proof_root / "kcfg" / "kcfg.json"
    nodes_root = proof_root / "kcfg" / "nodes"
    log_path = output_root / "prove.log"
    proof = read_json(proof_path)
    kcfg = read_json(kcfg_path)
    log_text = read_text(log_path)
    if proof.get("id") != proof_id or proof.get("admitted") is not False:
        raise SystemExit("proof identity/admitted mismatch")
    lower_log = log_text.lower()
    for token in FORBIDDEN_LOG_TOKENS:
        if token in lower_log:
            raise SystemExit(f"forbidden log token: {token}")
    marker = f"PROOF PASSED: {proof_id}" if record["executionSide"] == "canonical-positive" else f"PROOF FAILED: {proof_id}"
    if marker not in log_text:
        raise SystemExit(f"missing proof status marker: {marker}")
    graph = {
        "nodes": count_collection(kcfg.get("nodes")),
        "edges": count_collection(kcfg.get("edges")),
        "covers": count_collection(kcfg.get("covers")),
        "terminal": count_collection(proof.get("terminal")),
        "stuck": count_collection(kcfg.get("stuck")),
        "vacuous": count_collection(kcfg.get("vacuous")),
        "pending": pending_count(proof, log_text),
        "bounded": count_collection(kcfg.get("bounded")),
        "admitted": proof.get("admitted"),
    }
    if graph["nodes"] < 1 or graph["edges"] < 0 or graph["covers"] < 0 or graph["terminal"] > graph["nodes"]:
        raise SystemExit("invalid KCFG structural cardinality")
    if index["acceptancePolicy"].get("topologyCardinalityNotClaimed") != ["nodes", "edges", "covers"] or index["acceptancePolicy"].get("structuralCardinalityChecksRequired") is not True:
        raise SystemExit("generic acceptance-class contract mismatch")
    observed_contract = {key: graph[key] for key in ("terminal", "stuck", "vacuous", "pending", "bounded", "admitted")}
    if observed_contract != record["acceptanceContract"]["graph"]:
        raise SystemExit(f"graph acceptance mismatch: {observed_contract}")
    terminal_ids = [int(value) for value in proof.get("terminal", [])]
    terminal_nodes = []
    for node_id in terminal_ids:
        node_path = nodes_root / f"{node_id}.json"
        terminal_nodes.append({"nodeId": node_id, "path": node_path, "sha256": sha256(node_path), "json": read_json(node_path)})
    witness_observation = None
    if record["executionSide"] == "canonical-positive":
        if terminal_nodes:
            raise SystemExit("positive has terminal failure node")
    else:
        if len(terminal_nodes) != 1:
            raise SystemExit("mutant must have exactly one terminal failure node")
        witness_observation = {"nodeId": terminal_nodes[0]["nodeId"], **terminal_observation(terminal_nodes[0]["json"], record["terminalWitnessContract"])}
    report = {
        "schemaVersion": 1,
        "kind": "ABI04_FULL_ROW_REPLAY_PYTHON_ANALYSIS_V1",
        "status": "PASS",
        "obligationId": "ABI-04",
        "replayId": replay_id,
        "semanticClaimId": record["semanticClaimId"],
        "executionClaimId": record["executionClaimId"],
        "side": record["side"],
        "executionSide": record["executionSide"],
        "proofId": proof_id,
        "processExitCode": record["expectedProcessExitCode"],
        "launcherExitCode": record["expectedProcessExitCode"],
        "graph": graph,
        "elapsedSeconds": read_int(output_root / "elapsed-seconds.txt"),
        "inputIntegrityStatus": "PASS",
        "ownedSessionSurvivorCount": 0,
        "claimSourceSha256": record["claim"]["sha256"],
        "strippedClaimSha256": record["strippedClaimSha256"],
        "definitionKoreSha256": execution["definitionKoreSha256"],
        "compiledJsonSha256": execution["compiledJsonSha256"],
        "proof": {"path": str(proof_path), "sha256": sha256(proof_path)},
        "kcfg": {"path": str(kcfg_path), "sha256": sha256(kcfg_path)},
        "log": {"path": str(log_path), "sha256": sha256(log_path)},
        "snapshotManifest": {"path": str(manifest_path), "sha256": sha256(manifest_path)},
        "terminalWitnesses": [{"nodeId": item["nodeId"], "path": str(item["path"]), "sha256": item["sha256"]} for item in terminal_nodes],
        "terminalWitnessObservation": witness_observation,
        "closureFreezeUnchanged": True,
        "proofCreditBoundary": "ONE_EXACT_REPLAY_ONLY_NOT_AGGREGATE_OR_CENTRAL",
    }
    serialized = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.report:
        with args.report.open("x", encoding="utf-8", newline="\n") as handle:
            handle.write(serialized)
    print(serialized, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
