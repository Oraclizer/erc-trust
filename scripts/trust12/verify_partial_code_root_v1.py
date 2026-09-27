#!/usr/bin/env python3
"""Rehash the bounded Partial recorded-runtime code identity proof chain.

The checked equality is for the first Partial FREEZE entry account-code
observation. It does not establish an operational runtime-to-model relation.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path


PLATFORM = "polyml-5.9.2_x86_64_32-windows"
ROOT_SESSION = "TRUST12_PARTIAL_CODE_ROOT_G91_V1"
ROOT_THEOREM = "partial_recorded_code_identity"
STAGES = (
    ("partial-first-immutable-word-g76-v1", "partial-first-immutable-word-g76-build", "TRUST12_PARTIAL_FIRST_IMMUTABLE_WORD_G76_V1"),
    ("partial-fill-segment-method-g77-v1", "partial-fill-segment-method-g77-build", "TRUST12_PARTIAL_FIRST_FILL_SEGMENT_G77_V1"),
    ("partial-filled-word32-g78-v1", "partial-filled-word32-g78-build", "TRUST12_PARTIAL_FILLED_WORD32_G78_V1"),
    ("partial-leaf-unfilled-method-g79-v1", "partial-leaf-unfilled-method-g79-build", "TRUST12_PARTIAL_LEAF_UNFILLED_METHOD_G79_V1"),
    ("partial-code-leaf96-g80-v1", "partial-code-leaf96-g80-build", "TRUST12_PARTIAL_CODE_LEAF96_G80_V1"),
    ("partial-unaffected-leaf-g81-v1", "partial-unaffected-leaf-g81-build", "TRUST12_PARTIAL_UNAFFECTED_LEAF_G81_V1"),
    ("partial-unaffected-batch01-g82-v1", "partial-unaffected-batch01-g82-build", "TRUST12_PARTIAL_UNAFFECTED_BATCH01_G82_V1"),
    ("partial-unaffected-batch02-g83-v1", "partial-unaffected-batch02-g83-build", "TRUST12_PARTIAL_UNAFFECTED_BATCH02_G83_V1"),
    ("partial-crosschunk-method-g84-v1", "partial-crosschunk-method-g84-build", "TRUST12_PARTIAL_CROSSCHUNK_METHOD_G84_V1"),
    ("partial-crosschunk-batch-g85-v1", "partial-crosschunk-batch-g85-build", "TRUST12_PARTIAL_CROSSCHUNK_BATCH_G85_V1"),
    ("partial-twofill-leaf-g86-v1", "partial-twofill-leaf-g86-memory-build", "TRUST12_PARTIAL_TWOFILL_LEAF_G86_V1"),
    ("partial-touched-batch01-g87-v1", "partial-touched-batch01-g87-build", "TRUST12_PARTIAL_TOUCHED_BATCH01_G87_V1"),
    ("partial-touched-batch02-g88-v2", "partial-touched-batch02-g88-v2-build", "TRUST12_PARTIAL_TOUCHED_BATCH02_G88_V2"),
    ("partial-touched-batch03-g89-v2", "partial-touched-batch03-g89-v2-build", "TRUST12_PARTIAL_TOUCHED_BATCH03_G89_V2"),
    ("partial-touched-crosschunk-g90-v2", "partial-touched-crosschunk-g90-v2-build", "TRUST12_PARTIAL_TOUCHED_CROSSCHUNK_G90_V2"),
    ("partial-code-root-g91-v1", "partial-code-root-g91-build", ROOT_SESSION),
)


def require(condition: object, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    require(isinstance(value, dict), f"JSON object required: {path}")
    return value


def check(path: Path, expected_sha: str, label: str, expected_bytes: int | None = None) -> None:
    require(path.is_file(), f"{label}: missing {path}")
    require(digest(path) == expected_sha, f"{label}: SHA-256 drift")
    if expected_bytes is not None:
        require(path.stat().st_size == expected_bytes, f"{label}: byte length drift")


def check_artifact(path: Path, item: dict, label: str) -> None:
    check(path, item["sha256"], label, item["bytes"])


def check_record(item: dict, base: Path, product: Path, label: str) -> None:
    root = {"EVIDENCE": base, "PRODUCT": product}.get(item["root"])
    require(root is not None, f"{label}: unsupported root")
    path = (root / item["path"]).resolve()
    require(path.is_relative_to(root), f"{label}: path outside root")
    check_artifact(path, item, label)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", type=Path, required=True, help="local out/trust12 evidence root")
    parser.add_argument("--product-root", type=Path, required=True)
    parser.add_argument("--checkpoint", type=Path, help="optional public checkpoint to rehash")
    args = parser.parse_args()
    base, product = args.base.resolve(), args.product_root.resolve()
    require((product / "evidence/trust12/release-notes.md").is_file(), "product root identity missing")
    plan_path = base / "partial-code-leaf-plan-v1.json"
    plan = read(plan_path)
    require(plan["schema"] == "trust12-partial-runtime-code-leaf-plan-v1"
            and plan["root"] == "aa_bytes_0656"
            and plan["runtimeBytes"] == 19480 and plan["leafCount"] == 203
            and plan["touchedLeaves"] == 27 and plan["changedLeaves"] == 24,
            "Partial recorded code partition drift")
    require(len(plan["leaves"]) == 203
            and all(item["recordedSha256"] == item["expectedSha256"] for item in plan["leaves"]),
            "recorded leaf host comparison drift")
    ast = base / "profile-partial-freeze-accounts-g66-v1"
    reader = base / "reader-rollout-v6/partial-freeze-pilot/base"
    for path, key in ((ast / "TRUST_Native_PARTIAL_FREEZE_APPLIED_ENTRY_ACCOUNTS_Ast_Data_00.thy", "astData"),
                      (ast / "TRUST_Native_PARTIAL_FREEZE_APPLIED_ENTRY_ACCOUNTS_Eval_G66.thy", "evalTheory"),
                      (reader / "TRUST_Partial_Profile_Reader.thy", "profileReader")):
        item = plan["source"][key]
        require(Path(item["path"]).name == path.name, f"{key}: source filename drift")
        check_artifact(path, item, key)

    canary_path = base / "partial-slice-join-method-v8-canary-runs/JoinRun08/result.json"
    canary = read(canary_path)
    require(canary["schema"] == "trust12-partial-slice-join-method-canary-v8"
            and canary["status"] == "PASS_PARTIAL_SLICE_JOIN_METHOD_ORACLE_ZERO"
            and canary["inputsUnchanged"] is True and canary["exitCode"] == 0,
            "binary join method canary not PASS")
    for item, path in ((canary["heap"], Path(canary["heap"]["path"])),
                       (canary["database"], Path(canary["database"]["path"]))):
        check_artifact(path, item, "binary join canary artifact")

    heaps = base / "final-chain-v2/store/heaps" / PLATFORM
    checked = []
    prior_session = None
    for folder, run, session in STAGES:
        source_dir = base / folder
        binding = read(source_dir / "input-binding.json")
        root_file = source_dir / "ROOT"
        theories = list(source_dir.glob("*.thy"))
        require(len(theories) == 1, f"{session}: one theory source required")
        theory_file = theories[0]
        require(binding["session"] == session, f"{session}: input session drift")
        if prior_session is not None:
            require(binding["parent"] == prior_session, f"{session}: parent chain drift")
        check(theory_file, binding["theorySha256"], f"{session} theory")
        check(root_file, binding["rootSha256"], f"{session} ROOT")
        source_text = theory_file.read_text(encoding="utf-8")
        require("Thm_Deps.all_oracles roots" in source_text,
                f"{session}: oracle-dependency guard missing")
        require(not re.search(r"\b(sorry|oops|admit)\b|\bby eval\b", source_text),
                f"{session}: proof escape in source")
        result_path = base / "final-chain-v2/runs" / run / "result.json"
        result = read(result_path)
        require(result["status"] == f"PASS_FINAL_CHAIN_STAGE_BUILT_{session}"
                and result["target"] == session and result["dryRun"] is False
                and result["exitCode"] == 0 and result["inputsUnchanged"] is True
                and result["changedInputPaths"] == []
                and result["builtSessions"] == result["finishedSessions"] == [session]
                and result["failedSessions"] == result["cancelledSessions"] == []
                and result["compactPolyReceipts"]["valid"] is True,
                f"{session}: kernel build result drift")
        require(len(result["sessions"]) == 1 and result["sessions"][0]["session"] == session,
                f"{session}: one stored artifact pair required")
        artifact = result["sessions"][0]
        check_artifact(heaps / session, artifact["heap"], f"{session} heap")
        check_artifact(heaps / "log" / f"{session}.db", artifact["database"], f"{session} database")
        checked.append({"session": session, "theorySha256": digest(theory_file),
                        "resultSha256": digest(result_path),
                        "heapSha256": artifact["heap"]["sha256"],
                        "databaseSha256": artifact["database"]["sha256"]})
        prior_session = session

    root_dir = base / "partial-code-root-g91-v1"
    root_binding = read(root_dir / "input-binding.json")
    root_source = root_dir / "TRUST_Partial_Code_Root_G91_V1.thy"
    root_text = root_source.read_text(encoding="utf-8")
    require(root_binding["leafCount"] == 203 and root_binding["nodeCount"] == 202
            and root_binding["runtimeBytes"] == 19480
            and root_binding["leafPlanSha256"] == digest(plan_path)
            and root_binding["canaryResultSha256"] == digest(canary_path),
            "whole-code root binding drift")
    require(len(root_binding["proofSources"]) == 11, "eleven proof source bindings required")
    known_sources = {item["theorySha256"] for item in checked}
    for item in root_binding["proofSources"]:
        require(item["sha256"] in known_sources, "root proof source hash outside checked chain")
    require(len(re.findall(r"(?m)^lemma partial_ast_slice_aa_bytes_", root_text)) == 203
            and len(re.findall(r"(?m)^theorem partial_ast_slice_aa_bytes_", root_text)) == 202
            and len(re.findall(rf"(?m)^theorem {ROOT_THEOREM}:", root_text)) == 1
            and "PASS_PARTIAL_CODE_ROOT_ORACLE_ZERO" in root_text,
            "full recorded code theorem or oracle guard drift")
    checkpoint_sha = None
    if args.checkpoint is not None:
        checkpoint_path = args.checkpoint.resolve()
        require(checkpoint_path.is_relative_to(product), "checkpoint outside product root")
        checkpoint = read(checkpoint_path)
        require(checkpoint["schema"] == "trust12-partial-recorded-code-root-checkpoint-v1"
                and checkpoint["status"] == "PASS_KERNEL_CHECKED_PARTIAL_RECORDED_CODE_ROOT_V1"
                and checkpoint["coverage"]["recordedRuntimeBytes"] == 19480
                and checkpoint["coverage"]["recordedLeaves"] == 203
                and checkpoint["coverage"]["binaryNodes"] == 202
                and checkpoint["coverage"]["kernelSessions"] == len(STAGES)
                and checkpoint["coverage"]["ancestorSessionsRebuiltInFinalStage"] == 0
                and checkpoint["source"]["recordedRuntimeSha256"] == plan["runtimeSha256"]
                and checkpoint["source"]["compilerTemplateSha256"] == plan["templateSha256"]
                and checkpoint["kernelBuild"]["rootTheorem"] == ROOT_THEOREM
                and checkpoint["kernelBuild"]["rootOracleDependencies"] == 0
                and checkpoint["kernelBuild"]["inputsUnchanged"] is True,
                "public checkpoint scope or counts drift")
        require(checkpoint["source"]["leafPlan"]["path"] == "partial-code-leaf-plan-v1.json"
                and checkpoint["source"]["rootBinding"]["path"]
                == "partial-code-root-g91-v1/input-binding.json"
                and checkpoint["kernelBuild"]["rootDryRun"]["path"]
                == "final-chain-v2/runs/partial-code-root-g91-dryrun/result.json"
                and checkpoint["hostAudit"]["report"]["path"]
                == "partial-code-root-host-audit-v1.json"
                and checkpoint["hostAudit"]["verifier"]["path"]
                == "scripts/trust12/verify_partial_code_root_v1.py",
                "public checkpoint fixed path drift")
        for label, item in (("leaf plan", checkpoint["source"]["leafPlan"]),
                            ("root binding", checkpoint["source"]["rootBinding"]),
                            ("binary method", checkpoint["kernelBuild"]["binaryJoinMethodCanary"]),
                            ("root dry-run", checkpoint["kernelBuild"]["rootDryRun"]),
                            ("host audit", checkpoint["hostAudit"]["report"]),
                            ("public verifier", checkpoint["hostAudit"]["verifier"])):
            check_record(item, base, product, label)
        source_records = checkpoint["source"]["proofStages"]
        build_records = checkpoint["kernelBuild"]["sessions"]
        require(len(source_records) == len(build_records) == len(STAGES),
                "public checkpoint stage count drift")
        for (folder, run, session), source_record, build_record in zip(STAGES, source_records, build_records):
            require(source_record["session"] == build_record["session"] == session
                    and source_record["binding"]["path"] == f"{folder}/input-binding.json"
                    and source_record["sessionRoot"]["path"] == f"{folder}/ROOT"
                    and source_record["theory"]["path"].startswith(f"{folder}/")
                    and build_record["result"]["path"] == f"final-chain-v2/runs/{run}/result.json"
                    and build_record["heap"]["path"] == f"final-chain-v2/store/heaps/{PLATFORM}/{session}"
                    and build_record["database"]["path"]
                    == f"final-chain-v2/store/heaps/{PLATFORM}/log/{session}.db",
                    f"{session}: public checkpoint source/artifact mapping drift")
            for label, item in (("binding", source_record["binding"]),
                                ("session ROOT", source_record["sessionRoot"]),
                                ("theory", source_record["theory"]),
                                ("result", build_record["result"]),
                                ("heap", build_record["heap"]),
                                ("database", build_record["database"])):
                check_record(item, base, product, f"{session} {label}")
        require(checkpoint["hostAudit"]["status"] == "PASS_PARTIAL_RECORDED_CODE_ROOT_REHASHED"
                and read(base / checkpoint["hostAudit"]["report"]["path"])["status"]
                == "PASS_PARTIAL_RECORDED_CODE_ROOT_REHASHED",
                "public checkpoint host audit drift")
        checkpoint_sha = digest(checkpoint_path)

    report = {
        "status": "PASS_PARTIAL_RECORDED_CODE_ROOT_REHASHED",
        "runtimeBytes": 19480,
        "recordedRuntimeSha256": plan["runtimeSha256"],
        "compilerTemplateSha256": plan["templateSha256"],
        "recordedLeaves": 203,
        "binaryNodes": 202,
        "kernelSessions": len(checked),
        "rootSession": ROOT_SESSION,
        "rootTheorySha256": digest(root_source),
        "rootHeapSha256": checked[-1]["heapSha256"],
        "rootDatabaseSha256": checked[-1]["databaseSha256"],
        "nonclaim": "One recorded Partial adapter code observation and its constructed compiler-template/immutable-fill equality. No S2 operational receiver, general runtime link, Hook code identity, central closure, independent Assurance, release or deployment is established.",
    }
    if checkpoint_sha is not None:
        report["checkpointSha256"] = checkpoint_sha
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
