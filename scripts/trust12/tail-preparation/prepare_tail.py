#!/usr/bin/env python3
"""Generate, check and return the TRUST 1.2 tail preparation.

Commands:
  generate [--artifacts DIR]   write every generated document and validate the obligation list
  check [--artifacts DIR]      verify that every generated document is byte-identical to a fresh build
  mapping --evidence DIR --mapping FILE --output FILE
                               verify a private map from the prepared conditions to the rows of the
                               runtime-link obligation ledger and record the verification
  manifest --baseline FILE --evidence DIR --evidence-prefix NAME --checks FILE
                               write the process return manifest over every prepared output

Without `--artifacts`, the code identity check keeps its recorded compiled scan and only confirms
that the scan belongs to the tracked runtime templates.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

import code_identity
import malformed_inputs
import route_inventory
import state_receipt_crosswalk
from tail_common import (
    NONCLAIM, OUTPUT, PROFILES, ROOT, PreparationError, canonical_text_sha256, dump_json, load_json, require,
    sha256_file, write_or_check,
)

OBLIGATIONS = OUTPUT / "tail-obligations-v1.json"
MANIFEST = OUTPUT / "preparation-manifest-v1.json"
PRODUCT_PREFIXES = ("evidence/trust12/runtime-link/tail-preparation/", "scripts/trust12/tail-preparation/")
GROUP_SIZES = {"gate": 3, "malformed": 3, "central": 4, "assurance": 1}
SCHEMA_DOCUMENTS = ("assurance-input-seal-schema-v1.json", "certificate-registry-schema-v1.json")
MANIFEST_EXCLUDED_PARTS = {"__pycache__"}


def validate_obligations(document: dict[str, Any] | None = None) -> dict[str, Any]:
    document = load_json(OBLIGATIONS) if document is None else document
    require(document.get("schema") == "trust12-tail-preparation-obligations-v1", "obligation list schema drift")
    require(document.get("status") == "PREPARED_NOT_CLOSED", "obligation list claims more than preparation")
    require(document.get("nonclaim") == NONCLAIM, "obligation list non-claim drift")
    conditions = document["conditions"]
    ids = [condition["id"] for condition in conditions]
    require(len(ids) == len(set(ids)), "obligation ids repeat")
    for group, size in GROUP_SIZES.items():
        require(sum(condition["group"] == group for condition in conditions) == size, f"{group} conditions are not {size}")
    require(sorted(condition.get("profile") for condition in conditions if condition["group"] == "malformed") == sorted(PROFILES),
            "the malformed conditions do not cover the three profiles once each")
    findings = {finding["id"] for finding in document["findings"]}
    referenced = set()
    for condition in conditions:
        require(set(condition) >= {"id", "group", "condition", "preparedSupport", "closureAcceptance", "blockingFindings"},
                f"{condition['id']}: incomplete condition")
        require(condition["closureAcceptance"], f"{condition['id']}: no acceptance criterion")
        for support in condition["preparedSupport"]:
            path = ROOT / support["artifact"]
            require(support["artifact"].startswith(PRODUCT_PREFIXES) and path.is_file(),
                    f"{condition['id']}: prepared support is not a prepared artifact: {support['artifact']}")
        for finding in condition["blockingFindings"]:
            require(finding in findings, f"{condition['id']}: unknown finding {finding}")
            referenced.add(finding)
    require(referenced == findings, f"findings without a condition: {sorted(findings - referenced)}")
    return {"conditions": len(conditions), "findings": len(findings)}


def validate_schemas() -> None:
    for name in SCHEMA_DOCUMENTS:
        schema = load_json(OUTPUT / name)
        require(schema.get("$schema", "").endswith("2020-12/schema") and "$id" in schema, f"{name}: not a schema document")


def generate(check: bool, artifacts: Path | None) -> dict[str, Any]:
    results = {}
    document, table = malformed_inputs.build()
    results["malformedInputs"] = write_or_check(malformed_inputs.DOCUMENT, dump_json(document), check)
    results["malformedProbeTable"] = write_or_check(malformed_inputs.GENERATED_PROBE_TABLE, table, check)
    if artifacts is None and code_identity.DOCUMENT.is_file():
        identity = code_identity.build_with_recorded_scan()
    else:
        identity = code_identity.build(artifacts)
    results["codeIdentity"] = write_or_check(code_identity.DOCUMENT, dump_json(identity), check)
    results["routeInventory"] = write_or_check(route_inventory.DOCUMENT, dump_json(route_inventory.build()), check)
    results["stateReceiptCrosswalk"] = write_or_check(
        state_receipt_crosswalk.DOCUMENT, dump_json(state_receipt_crosswalk.build()), check)
    results["obligations"] = validate_obligations()
    validate_schemas()
    return results


def verify_mapping(evidence: Path, mapping_path: Path) -> dict[str, Any]:
    mapping = load_json(mapping_path)
    require(mapping.get("schema") == "trust12-tail-preparation-ledger-row-map-v1", "row map schema drift")
    ledger_path = evidence / mapping["ledger"]
    ledger = load_json(ledger_path)
    rows = {row["id"]: row for row in ledger["rows"]}
    conditions = {condition["id"] for condition in load_json(OBLIGATIONS)["conditions"]}
    mapped = mapping["conditions"]
    require(set(mapped) == conditions, "the row map and the prepared conditions differ")
    require(len(set(mapped.values())) == len(mapped), "two conditions map to one ledger row")
    for condition, row_id in mapped.items():
        require(row_id in rows, f"{condition}: ledger row missing: {row_id}")
        require(not row_id.startswith("cell/"), f"{condition}: a tail condition cannot be a cell row")
    tail = {row_id for row_id, row in rows.items() if not row_id.startswith("cell/") and row["status"] != "CLOSED"}
    require(tail == set(mapped.values()), "the open non-cell ledger rows and the mapped rows differ")
    cells = [row for row_id, row in rows.items() if row_id.startswith("cell/")]
    require(len(cells) == 27, "the ledger does not declare 27 cells")
    return {
        "schema": "trust12-tail-preparation-ledger-row-map-check-v1",
        "status": "PASS_ROW_MAP_MATCHES_OPEN_TAIL_ROWS",
        "ledger": {"path": mapping["ledger"], "sha256": sha256_file(ledger_path)},
        "rowMap": {"sha256": sha256_file(mapping_path)},
        "conditions": {condition: {"row": row_id, "status": rows[row_id]["status"],
                                   "missingEvidenceKinds": rows[row_id].get("missingEvidenceKinds", [])}
                       for condition, row_id in sorted(mapped.items())},
        "cells": {"declared": len(cells), "closed": sum(row["status"] == "CLOSED" for row in cells)},
        "nonclaim": NONCLAIM,
    }


def product_outputs() -> list[dict[str, Any]]:
    outputs = []
    for prefix in PRODUCT_PREFIXES:
        for path in sorted((ROOT / prefix).rglob("*")):
            relative_path = path.relative_to(ROOT).as_posix()
            if not path.is_file() or MANIFEST_EXCLUDED_PARTS.intersection(path.parts) or path == MANIFEST:
                continue
            outputs.append({"root": "PROCESS_WORKTREE", "path": relative_path, "bytes": path.stat().st_size,
                            "sha256": sha256_file(path)})
    return outputs


def evidence_outputs(evidence: Path, prefix: str) -> list[dict[str, Any]]:
    base = evidence / prefix
    require(base.is_dir(), f"evidence output directory missing: {prefix}")
    return [{"root": "EVIDENCE", "path": path.relative_to(evidence).as_posix(), "bytes": path.stat().st_size,
             "sha256": sha256_file(path)}
            for path in sorted(base.rglob("*")) if path.is_file()]


def integration_accounting(outputs: list[dict[str, Any]]) -> dict[str, Any]:
    """Accounting the integration owner regenerates after merging; the process may not write it."""
    added = [item for item in outputs if item["root"] == "PROCESS_WORKTREE"]
    canonical_bytes = sum(len((ROOT / item["path"]).read_text(encoding="utf-8").replace("\r\n", "\n").encode("utf-8"))
                          for item in added)
    protected = sorted(item["path"] for item in added if item["path"].startswith("scripts/"))
    return {
        "publicTreeAccounting": {
            "file": "evidence/public-release/diet-manifest-v2.json",
            "trackedFilesAddedByThisProcess": len(added) + 1,
            "canonicalBytesAddedExcludingTheReturnManifest": canonical_bytes,
            "note": "The return manifest itself is also added; the integration owner recomputes the summary counts "
                    "over the merged tree with the same formulas as scripts/verify-public-release-tree.mjs.",
        },
        "releaseManifest": {
            "file": "evidence/release-manifest.json",
            "protectedFilesAdded": {path: canonical_text_sha256(ROOT / path) for path in protected},
            "regenerate": "forge build && node scripts/generate-release-manifest.mjs",
        },
        "reason": "Both documents account for the whole tracked tree. This process may write only its two "
                  "preparation directories, so the checks that compare them with the tree fail on the process "
                  "branch until the integration owner regenerates them once for all merged processes.",
    }


def manifest(baseline: Path, evidence: Path, prefix: str, checks: Path) -> dict[str, Any]:
    validate_obligations()
    outputs = product_outputs() + evidence_outputs(evidence, prefix)
    check_record = load_json(checks)
    require(check_record.get("status") == "PASS", "the recorded preparation checks did not pass")
    document = {
        "schema": "trust12-runtime-link-process-result-v1",
        "processId": "RL-20-TAIL-PREP",
        "status": "PASS_RL20_TAIL_PREP_READY_FOR_INTEGRATION",
        "baselineManifestSha256": sha256_file(baseline),
        "gitActions": ["commit", "push", "draft-pr"],
        "preparedConditions": [condition["id"] for condition in load_json(OBLIGATIONS)["conditions"]],
        "findings": [finding["id"] for finding in load_json(OBLIGATIONS)["findings"]],
        "checks": check_record["checks"],
        "integrationAccounting": integration_accounting(outputs),
        "outputs": outputs,
        "nonclaim": NONCLAIM,
    }
    MANIFEST.write_text(dump_json(document), encoding="utf-8", newline="\n")
    return document


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("generate", "check"):
        command = commands.add_parser(name)
        command.add_argument("--artifacts", type=Path)
    mapping_parser = commands.add_parser("mapping")
    mapping_parser.add_argument("--evidence", type=Path, required=True)
    mapping_parser.add_argument("--mapping", type=Path, required=True)
    mapping_parser.add_argument("--output", type=Path, required=True)
    manifest_parser = commands.add_parser("manifest")
    manifest_parser.add_argument("--baseline", type=Path, required=True)
    manifest_parser.add_argument("--evidence", type=Path, required=True)
    manifest_parser.add_argument("--evidence-prefix", required=True)
    manifest_parser.add_argument("--checks", type=Path, required=True)
    args = parser.parse_args(argv)
    if args.command in {"generate", "check"}:
        result = generate(args.command == "check", args.artifacts)
        print(dump_json({"status": f"PASS_TAIL_PREPARATION_{args.command.upper()}", "documents": result}), end="")
    elif args.command == "mapping":
        result = verify_mapping(args.evidence, args.mapping)
        require(not args.output.exists(), "row map check output already exists")
        args.output.write_text(dump_json(result), encoding="utf-8", newline="\n")
        print(dump_json({"status": result["status"], "conditions": len(result["conditions"])}), end="")
    else:
        result = manifest(args.baseline, args.evidence, args.evidence_prefix, args.checks)
        print(dump_json({"status": result["status"], "outputs": len(result["outputs"])}), end="")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except (PreparationError, subprocess.CalledProcessError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
