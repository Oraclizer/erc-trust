#!/usr/bin/env python3
"""Recheck the bounded v5/v7 out-of-specification equivalence checkpoint.

The v7 theory is rechecked under a one-header alias in the existing final
chain. This verifier does not establish an operational runtime link.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path


PARENT_SESSION = "TRUST12_MALFORMED_CELLS_EVAL_G73"
ALIAS_SESSION = "TRUST12_OUTOFSPEC_V7_ALIAS_G75"
BRIDGE_SESSION = "TRUST12_OUTOFSPEC_V5_V7_EQUIV_G76_V2"
SESSIONS = [ALIAS_SESSION, BRIDGE_SESSION]
PLATFORM = "polyml-5.9.2_x86_64_32-windows"
OLD_HEADER = "theory TRUST_Out_Of_Spec_Refinement\n"
NEW_HEADER = "theory TRUST_Out_Of_Spec_Refinement_V7_Alias\n"
CLAIMS = [
    "bytes_nat_same", "selector_same", "words_same", "canonical_same",
    "request_same", "transaction_command_same", "stutter_same",
    "alpha_transaction_spec_same",
]


def require(condition: object, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def read(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    require(isinstance(value, dict), f"JSON object required: {path}")
    return value


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check_hash(path: Path, expected: str, label: str) -> None:
    require(path.is_file(), f"{label}: missing {path}")
    require(digest(path) == expected, f"{label}: SHA-256 drift")


def check_artifact(path: Path, record: dict, label: str) -> None:
    check_hash(path, record["sha256"], label)
    require(path.stat().st_size == record["bytes"], f"{label}: byte length drift")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", type=Path, required=True, help="local out/trust12 evidence root")
    parser.add_argument("--product-root", type=Path, required=True)
    args = parser.parse_args()
    base, product = args.base.resolve(), args.product_root.resolve()
    alias_dir = base / "outofspec-v7-alias-g75-v1"
    bridge_dir = base / "outofspec-v7-bridge-g76-v2"
    alias_binding_path = alias_dir / "input-binding.json"
    bridge_binding_path = bridge_dir / "input-binding.json"
    alias, bridge = read(alias_binding_path), read(bridge_binding_path)
    source_path = product / "formal/isabelle/ERC_TRUST/TRUST_Out_Of_Spec_Refinement.thy"
    old_path = base / "final-chain-v2/pinned-inputs/product-outofspec-v2/formal/isabelle/ERC_TRUST/TRUST_Out_Of_Spec_Refinement.thy"
    g73_path = base / "final-chain-v2/runs/malformed-cells-g73-build-v1/result.json"
    first_path = base / "final-chain-v2/runs/outofspec-v7-alias-bridge-g76-build-v1/result.json"
    dry_path = base / "final-chain-v2/runs/outofspec-v7-bridge-g76-v2-dryrun/result.json"
    build_path = base / "final-chain-v2/runs/outofspec-v7-bridge-g76-v2-build/result.json"
    g73, first, dry, built = read(g73_path), read(first_path), read(dry_path), read(build_path)

    require(g73["status"] == f"PASS_FINAL_CHAIN_STAGE_BUILT_{PARENT_SESSION}" and g73["exitCode"] == 0,
            "parent session has no completed build")
    require(alias["status"] == "PREPARED_ALIAS_NOT_KERNEL_CHECKED" and alias["session"] == ALIAS_SESSION
            and alias["parent"] == PARENT_SESSION, "alias binding drift")
    require(bridge["status"] == "PREPARED_BRIDGE_REPAIR_NOT_KERNEL_CHECKED"
            and bridge["session"] == BRIDGE_SESSION and bridge["parent"] == ALIAS_SESSION
            and bridge["claims"] == CLAIMS, "bridge binding drift")
    check_hash(g73_path, alias["parentResult"]["sha256"], "parent session result")
    check_artifact(source_path, alias["productSource"], "current product v7 source")
    check_hash(old_path, bridge["oldTheorySha256"], "immutable v5 pin")
    check_hash(alias_binding_path, bridge["aliasBindingSha256"], "alias input binding")
    check_hash(first_path, bridge["failedV1ResultSha256"], "preserved first build result")
    canary_path = base / "outofspec-case-method-canary-runs/CaseRun01/result.json"
    check_hash(canary_path, bridge["caseMethodCanaryResultSha256"], "case-method canary")
    canary = read(canary_path)
    require(canary["status"] == "PASS_OUTOFSPEC_CASE_METHOD_ORACLE_ZERO"
            and canary["inputsUnchanged"] is True, "case-method canary drift")
    alias_path = alias_dir / alias["alias"]["file"]
    check_artifact(alias_path, alias["alias"], "v7 alias theory")
    check_hash(alias_dir / "ROOT", alias["rootSha256"], "v7 alias ROOT")
    source = source_path.read_text(encoding="utf-8")
    require(source.count(OLD_HEADER) == 1, "product theory header drift")
    require(alias_path.read_text(encoding="utf-8") == source.replace(OLD_HEADER, NEW_HEADER),
            "alias differs from product v7 beyond the theory header")
    bridge_path = bridge_dir / "TRUST_Out_Of_Spec_V5_V7_Bridge.thy"
    check_hash(bridge_path, bridge["theorySha256"], "core equivalence theory")
    check_hash(bridge_dir / "ROOT", bridge["rootSha256"], "core equivalence ROOT")
    bridge_text = bridge_path.read_text(encoding="utf-8")
    require(all(re.search(rf"\b(?:lemma|theorem) {name}:", bridge_text) for name in CLAIMS),
            "an equivalence statement is absent")
    require("Thm_Deps.all_oracles roots" in bridge_text
            and "PASS_OUTOFSPEC_V5_V7_ALIAS_EQUIV_ORACLE_ZERO" in bridge_text,
            "oracle dependency guard absent")
    require(not re.search(r"\b(sorry|oops|admit)\b", bridge_text), "proof escape in bridge")

    require(first["status"] == "INCOMPLETE_FINAL_CHAIN_STAGE_TRUST12_OUTOFSPEC_V5_V7_EQUIV_G76"
            and first["finishedSessions"] == [ALIAS_SESSION] and first["inputsUnchanged"] is True
            and len(first["sessions"]) == 1 and first["sessions"][0]["session"] == ALIAS_SESSION,
            "saved alias build provenance drift")
    require(dry["status"] == "PASS_DRY_RUN_COMPLETED" and dry["dryRun"] is True
            and dry["target"] == BRIDGE_SESSION and dry["dryRunWouldBuild"] == [BRIDGE_SESSION]
            and dry["builtSessions"] == dry["finishedSessions"] == []
            and dry["inputsUnchanged"] is True, "one-session repair dry-run drift")
    require(built["status"] == f"PASS_FINAL_CHAIN_STAGE_BUILT_{BRIDGE_SESSION}"
            and built["target"] == BRIDGE_SESSION and built["dryRun"] is False and built["exitCode"] == 0,
            "v7 alias/equivalence build not PASS")
    require(built["expectedNewSessions"] == BRIDGE_SESSION
            and built["builtSessions"] == built["finishedSessions"] == [BRIDGE_SESSION]
            and built["failedSessions"] == built["cancelledSessions"] == []
            and built["inputsUnchanged"] is True and built["changedInputPaths"] == []
            and built["compactPolyReceipts"]["valid"] is True,
            "actual session set or input integrity drift")
    require(len(built["sessions"]) == 1
            and [item["session"] for item in built["sessions"]] == [BRIDGE_SESSION],
            "built artifact session set drift")
    heap_root = base / "final-chain-v2/store/heaps" / PLATFORM
    artifacts = [first["sessions"][0], built["sessions"][0]]
    for item in artifacts:
        session = item["session"]
        check_artifact(heap_root / session, item["heap"], f"{session} heap")
        check_artifact(heap_root / "log" / f"{session}.db", item["database"], f"{session} database")
    print(json.dumps({
        "status": "PASS_OUTOFSPEC_V5_V7_CORE_EQUIV_REHASHED",
        "sessions": SESSIONS,
        "coreEquivalences": len(CLAIMS),
        "productV7Sha256": digest(source_path),
        "aliasTheorySha256": digest(alias_path),
        "bridgeTheorySha256": digest(bridge_path),
        "heapsSha256": [item["heap"]["sha256"] for item in artifacts],
        "nonclaim": "Exact source rehash and two completed Isabelle sessions. The operational K-to-Isabelle receiver, all S2 malformed relations, general runtime links and independent Assurance remain separate.",
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
