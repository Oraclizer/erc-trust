#!/usr/bin/env python3
"""Rehash the 42-certificate malformed KORE AST/EVAL kernel checkpoint.

Use --base for the separately archived TRUST 1.2 evidence root. This verifies
the recorded input and saved Isabelle artifacts, not the out-of-specification
transaction relation or a general runtime link.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

SESSION = "TRUST12_MALFORMED_CELLS_EVAL_G73"
BUILD_STATUS = f"PASS_FINAL_CHAIN_STAGE_BUILT_{SESSION}"
PLATFORM = "polyml-5.9.2_x86_64_32-windows"


def require(value: object, message: str) -> None:
    if not value:
        raise RuntimeError(message)


def read(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    require(isinstance(value, dict), f"JSON object required: {path}")
    return value


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rebase(raw: str, base: Path) -> Path:
    normalized = raw.replace("\\", "/")
    marker = "/out/trust12/"
    require(normalized.count(marker) == 1, f"not a TRUST 1.2 evidence path: {raw}")
    path = base / normalized.split(marker, 1)[1]
    require(path.resolve().is_relative_to(base.resolve()), f"pointer escaped evidence root: {raw}")
    return path


def check_record(record: dict, path: Path, label: str) -> None:
    require(path.is_file(), f"{label}: missing {path}")
    require(path.stat().st_size == record["bytes"], f"{label}: byte count drift")
    require(digest(path) == record["sha256"], f"{label}: SHA-256 drift")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", type=Path, required=True)
    args = parser.parse_args()
    base = args.base.resolve()
    spec_dir = base / "malformed-cells-full42-v1"
    theory_dir = base / "malformed-cells-g73-v1"
    run_dir = base / "final-chain-v2" / "runs" / "malformed-cells-g73-build-v1"
    spec = read(spec_dir / "spec-binding.json")
    bundle = read(spec_dir / "bundle-spec.json")
    generated = read(theory_dir / "input-binding.json")
    built = read(run_dir / "result.json")
    parent_path = base / "final-chain-v2" / "runs" / "hook-remaining-b-v4" / "result.json"
    parent = read(parent_path)

    require(spec["status"] == "PREPARED_MALFORMED_CELLS_G73_NOT_KERNEL_CHECKED"
            and spec["subset"] is False, "S1 spec not the full catalog")
    require(len(spec["certificates"]) == 42 and spec["roleUses"] == 420
            and spec["cellCount"] == 70, "S1 spec coverage drift")
    require({p: sum(c["profile"] == p for c in spec["certificates"])
             for p in ("native", "partial", "hook")} == {"native": 16, "partial": 13, "hook": 13},
            "S1 profile coverage drift")
    require(digest(spec_dir / "bundle-spec.json") == spec["bundleSpecSha256"], "bundle spec drift")
    require(len(bundle["cells"]) == 70 and bundle["parentSession"] == generated["parentSession"],
            "bundle cells or parent drift")
    require(parent["status"] == "PASS_HOOK_BATCH_BUILT" and parent["exitCode"] == 0,
            "parent Hook batch not PASS")
    require(digest(parent_path) == spec["parent"]["sha256"] == generated["parentResult"]["sha256"],
            "S1 parent binding drift")
    require(generated["status"] == "PREPARED" and generated["session"] == SESSION
            and generated["compactRoot"] is True and generated["runtimeLinkDischarged"] is False,
            "generated S1 claim or session drift")
    require(len(generated["cells"]) == 70 and len(generated["theories"]) == 218
            and len(generated["generated"]) == 219, "generated S1 coverage drift")
    require(all(row["pykRoundtripByteExact"] is True for row in generated["cells"]),
            "a KORE cell lost its pyk roundtrip")
    require(len({row["prefix"] for row in generated["cells"]}) == 70, "duplicate cell prefix")
    for row in generated["cells"]:
        record = row["kore"]
        check_record(record, rebase(record["path"], base), f"KORE cell {row['prefix']}")
    for record in generated["generated"]:
        path = (theory_dir / record["path"]).resolve()
        require(path.is_relative_to(theory_dir.resolve()), "generated path escaped S1 theory folder")
        check_record(record, path, f"generated {record['path']}")
        if path.suffix == ".thy":
            text = path.read_text(encoding="utf-8")
            require(not any(token in text for token in ("sorry", "oops", "admit", "by eval")),
                    f"proof escape or evaluation oracle in {record['path']}")

    require(built["status"] == BUILD_STATUS and built["exitCode"] == 0
            and built["target"] == SESSION and built["dryRun"] is False,
            "S1 Isabelle build not PASS")
    require(built["builtSessions"] == built["finishedSessions"] == [SESSION]
            and built["failedSessions"] == built["cancelledSessions"] == []
            and built["inputsUnchanged"] is True and built["changedInputPaths"] == [],
            "S1 actual session set or inputs drift")
    require(built["compactPolyReceipts"]["valid"] is True
            and built["compactPolyReceipts"]["count"] == 1, "compact Poly receipt invalid")
    require(len(built["sessions"]) == 1 and built["sessions"][0]["session"] == SESSION,
            "S1 artifact session drift")
    heap_root = base / "final-chain-v2" / "store" / "heaps" / PLATFORM
    for key, path in (("heap", heap_root / SESSION),
                      ("database", heap_root / "log" / f"{SESSION}.db")):
        record = built["sessions"][0][key]
        check_record(record, path, key)
        require(record["sha256"] == built["reusedTarget"][f"{key}Sha256"],
                f"{key}: result cross-check drift")

    print(json.dumps({"status": "PASS_MALFORMED_AST_EVAL_G73_REHASHED",
                      "certificates": 42, "roleUses": 420, "cells": 70,
                      "theories": 218, "generatedFiles": 219,
                      "kernelSessions": built["finishedSessions"],
                      "heapSha256": built["sessions"][0]["heap"]["sha256"],
                      "databaseSha256": built["sessions"][0]["database"]["sha256"]}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
