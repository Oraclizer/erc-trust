#!/usr/bin/env python3
"""Build and check the certificate registry and the acceptance partition coverage of the runtime link.

The central condition that the accepted set of each profile is the image of checked K/KEVM
certificates needs a finite registry: for every profile, operation and outcome branch, the
checked certificates whose executions make up the accepted set, bound to the kernel run that
consumed them and to the code identity of the profile. The 27-cell gate additionally needs the
malformed branch of each profile and an acceptance partition in which every accepted execution
has exactly one cell or the malformed branch.

This tool assembles that registry from a locator file. The locator file names, per cell, where
the evidence records each certificate; it lives next to the evidence because the evidence
layout is internal. The tool reads the obligation ledger for the kernel run of each cell and
the tracked code identity document for the program templates. It never closes a cell: it reports
coverage, distinctness, hash agreement, ledger agreement and program identity, and in closure
mode it fails unless every cell and every malformed branch is covered.

Usage:
  certificate_registry.py build  --evidence DIR --locators FILE --output FILE [--artifacts DIR] [--mode MODE]
  certificate_registry.py verify --evidence DIR --registry FILE [--artifacts DIR]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

from tail_common import (
    NONCLAIM, OPERATIONS, OUTPUT, PROFILES, PreparationError, dump_json, load_json, require,
    require_schema, schema_errors, sha256_bytes, sha256_file,
)

SCHEMA = OUTPUT / "certificate-registry-schema-v1.json"
CODE_IDENTITY = OUTPUT / "code-identity-v1.json"
BRANCHES = ("applied", "not-applied")
ENDPOINTS = {"Native": "TrustToken", "Partial": "ERC3643TrustAdapter", "Hook": "ERC3643HookAdapter"}


def pointer(value: Any, path: str) -> Any:
    """RFC 6901 JSON pointer lookup."""
    if path == "":
        return value
    require(path.startswith("/"), f"bad JSON pointer: {path}")
    current = value
    for raw in path[1:].split("/"):
        token = raw.replace("~1", "/").replace("~0", "~")
        if isinstance(current, list):
            require(token.isdigit() and int(token) < len(current), f"JSON pointer index missing: {path}")
            current = current[int(token)]
        else:
            require(isinstance(current, dict) and token in current, f"JSON pointer field missing: {path}")
            current = current[token]
    return current


def field(value: dict[str, Any], dotted: str) -> Any:
    current: Any = value
    for part in dotted.split("."):
        require(isinstance(current, dict) and part in current, f"certificate field missing: {dotted}")
        current = current[part]
    return current


def locate(evidence: Path, source: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    path = evidence / source["path"]
    require(path.is_file(), f"certificate source missing: {source['path']}")
    document = load_json(path)
    if "array" in source:
        items = pointer(document, source["array"])
        matches = [index for index, item in enumerate(items)
                   if all(item.get(key) == expected for key, expected in source["match"].items())]
        require(len(matches) == 1, f"certificate search matched {len(matches)} entries in {source['path']}")
        location = f"{source['array']}/{matches[0]}"
    else:
        location = source["pointer"]
    return pointer(document, location), {"path": source["path"], "pointer": location, "sha256": sha256_file(path)}


def slug_cell(slug: str) -> tuple[str, str]:
    parts = slug.lower().split("-")
    return parts[0].upper(), "applied" if parts[-1] == "applied" else "not-applied"


def extract(evidence: Path, cell: dict[str, Any], spec: dict[str, Any], check_cell: bool = True) -> dict[str, Any]:
    raw, source = locate(evidence, spec["source"])
    fields = spec.get("fields", {})
    certificate: dict[str, Any] = {
        "key": f"{cell['profile']}/{cell['operation']}/{spec['outcome']}",
        "profile": cell["profile"],
        "operation": cell["operation"],
        "outcome": spec["outcome"],
        "form": spec["form"],
        "source": source,
        "problems": [],
    }
    if spec["form"] == "APR_PROOF":
        if "proofIdFromPath" in fields:
            match = re.search(r"/proofs/(.+)/proof\.json$", str(field(raw, fields["proofIdFromPath"])).replace("\\", "/"))
            require(match is not None, f"{certificate['key']}: proof path does not name a proof")
            certificate["proofId"] = match.group(1)
        else:
            certificate["proofId"] = field(raw, fields["proofId"])
        certificate["proofSha256"] = field(raw, fields["proofSha256"])
        certificate["kcfgSha256"] = field(raw, fields["kcfgSha256"])
    else:
        certificate["boundary"] = field(raw, fields["boundary"])
        certificate["compoundIdentity"] = {name: field(pointer(load_json(evidence / item["path"]), item["pointer"]), name)
                                           for item in spec.get("identity", []) for name in item["fields"]}
    recorded_outcome = raw.get("outcome") if isinstance(raw, dict) and check_cell else None
    if isinstance(recorded_outcome, str):
        normalized = "applied" if recorded_outcome.lower() == "applied" else "not-applied"
        if normalized != spec["outcome"]:
            certificate["problems"].append(f"recorded outcome {recorded_outcome} differs from the locator")
    if check_cell and isinstance(raw, dict) and isinstance(raw.get("operation"), str) and raw["operation"] != cell["operation"]:
        certificate["problems"].append(f"recorded operation {raw['operation']} differs from the locator")
    if check_cell and isinstance(raw, dict) and isinstance(raw.get("slug"), str):
        operation, outcome = slug_cell(raw["slug"])
        if (operation, outcome) != (cell["operation"], spec["outcome"]):
            certificate["problems"].append(f"slug {raw['slug']} names another cell")
    for corroboration in spec.get("corroborate", []):
        other, other_source = locate(evidence, corroboration)
        for name, dotted in corroboration["fields"].items():
            if certificate.get(name) != field(other, dotted):
                certificate["problems"].append(f"{name} disagrees with {other_source['path']}{other_source['pointer']}")
    return certificate


def ledger_cells(ledger: dict[str, Any]) -> dict[str, dict[str, Any]]:
    cells = {}
    for row in ledger["rows"]:
        if not row["id"].startswith("cell/"):
            continue
        _, profile, operation = row["id"].split("/")
        kernels, seen = [], set()
        for items in row["evidence"].values():
            for item in items:
                if item.get("kind") == "kernel" and (item["root"], item["run"]) not in seen:
                    seen.add((item["root"], item["run"]))
                    kernels.append(item)
        cells[(profile, operation)] = {"row": row["id"], "status": row["status"],
                                       "kernels": sorted(kernels, key=lambda item: (item["root"], item["run"]))}
    require(len(cells) == 27, f"the ledger declares {len(cells)} cells instead of 27")
    return cells


def kernel_record(evidence: Path, kernel: dict[str, Any]) -> dict[str, Any]:
    path = evidence / kernel["root"] / kernel["run"] / "result.json"
    record = {"root": kernel["root"], "run": kernel["run"], "theory": kernel["theory"],
              "ledgerResultSha256": kernel.get("resultSha256"), "problems": []}
    if not path.is_file():
        record["problems"].append("kernel result missing")
        return record
    actual = sha256_file(path)
    status = load_json(path).get("status", "")
    record.update({"resultSha256": actual, "status": status})
    if actual != kernel.get("resultSha256"):
        record["problems"].append("kernel result differs from the hash the ledger recorded")
    if not str(status).startswith("PASS_"):
        record["problems"].append("kernel result is not PASS")
    return record


def program_record(evidence: Path, spec: dict[str, Any], identity: dict[str, Any], artifacts: Path | None) -> dict[str, Any]:
    raw, source = locate(evidence, spec["source"])
    fields = spec["fields"]
    template = field(raw, fields["template"])
    actual = field(raw, fields["actual"]) if "actual" in fields else pointer(load_json(evidence / spec["actualSource"]["path"]), spec["actualSource"]["pointer"])
    ranges = [{"start": int(item["start"]), "length": int(item["length"]), "value": item[fields["rangeValue"]]}
              for item in field(raw, fields["ranges"])]
    runtimes = {item["contract"]: item for item in identity["profiles"][spec["profile"]]["runtimes"]}
    record = {"profile": spec["profile"], "contract": spec["contract"], "source": source,
              "templateSha256": template, "actualSha256": actual, "immutableRangeCount": len(ranges), "problems": []}
    expected = runtimes.get(spec["contract"])
    if expected is None or expected["runtimeTemplate"]["sha256"] != template:
        record["problems"].append("template differs from the tracked code identity")
    if artifacts is None:
        record["reconstruction"] = "NOT_RECOMPUTED"
        return record
    artifact = load_json(artifacts / f"{spec['contract']}.sol" / f"{spec['contract']}.json")
    code = bytearray(bytes.fromhex(artifact["deployedBytecode"]["object"].removeprefix("0x")))
    if sha256_bytes(bytes(code)) != template:
        record["problems"].append("compiled template differs from the recorded template")
    covered = set()
    for item in ranges:
        value = bytes.fromhex(item["value"])
        if len(value) != item["length"]:
            record["problems"].append("immutable value length differs from its range")
            continue
        code[item["start"]:item["start"] + item["length"]] = value
        covered.update(range(item["start"], item["start"] + item["length"]))
    reference_ranges = expected["immutableRanges"] if expected else []
    declared = {offset for start, end in reference_ranges for offset in range(start, end)}
    if covered != declared:
        record["problems"].append("patched ranges differ from the immutable ranges of the code identity")
    rebuilt = sha256_bytes(bytes(code))
    record["reconstruction"] = "MATCH" if rebuilt == actual else "MISMATCH"
    if rebuilt != actual:
        record["problems"].append("template plus immutable values does not reproduce the executed code")
    return record


def build(evidence: Path, locators: dict[str, Any], artifacts: Path | None, mode: str) -> dict[str, Any]:
    schema = load_json(SCHEMA)
    errors = schema_errors({key: value for key, value in locators.items() if key != "_source"},
                           schema["$defs"]["locators"], schema)
    require(not errors, "locator file violates its schema: " + "; ".join(errors[:10]))
    require(mode in {"dry-run", "closure"}, f"unknown mode {mode}")
    ledger_path = evidence / locators["ledger"]
    ledger = load_json(ledger_path)
    identity = load_json(CODE_IDENTITY)
    cells = ledger_cells(ledger)
    certificates, cell_records = [], []
    for cell in locators["cells"]:
        require((cell["profile"], cell["operation"]) in cells, f"locator names an undeclared cell: {cell}")
        certificates += [extract(evidence, cell, spec) for spec in cell["certificates"]]
    by_key = {}
    for certificate in certificates:
        require(certificate["key"] not in by_key, f"certificate key repeated: {certificate['key']}")
        by_key[certificate["key"]] = certificate
    for profile in PROFILES:
        for operation in OPERATIONS:
            ledger_cell = cells[(profile, operation)]
            applied = by_key.get(f"{profile}/{operation}/applied")
            other = by_key.get(f"{profile}/{operation}/not-applied")
            kernels = [kernel_record(evidence, kernel) for kernel in ledger_cell["kernels"]] if applied or other else []
            problems = [problem for kernel in kernels for problem in kernel["problems"]]
            if applied and other and applied.get("kcfgSha256") and applied.get("kcfgSha256") == other.get("kcfgSha256"):
                problems.append("applied and not-applied certificates share one KCFG")
            if applied and other and applied["form"] == "COMPOUND_BOUNDARY" and applied.get("boundary") == other.get("boundary"):
                problems.append("applied and not-applied boundaries coincide")
            bound = bool(applied and other and kernels and not problems)
            cell_records.append({
                "profile": profile,
                "operation": operation,
                "ledgerStatus": ledger_cell["status"],
                "applied": applied["key"] if applied else None,
                "notApplied": other["key"] if other else None,
                "kernels": kernels,
                "coverage": "BOUND" if bound else "OPEN",
                "problems": problems,
            })
            if bound != (ledger_cell["status"] == "CLOSED"):
                cell_records[-1]["problems"].append(
                    f"registry coverage {'BOUND' if bound else 'OPEN'} disagrees with ledger status {ledger_cell['status']}")
    programs = [program_record(evidence, spec, identity, artifacts) for spec in locators.get("programs", [])]
    malformed = [{"profile": profile, "certificates": [], "coverage": "OPEN"} for profile in PROFILES]
    for entry in locators.get("malformed", []):
        target = next(item for item in malformed if item["profile"] == entry["profile"])
        for spec in entry["certificates"]:
            record = extract(evidence, {"profile": entry["profile"], "operation": "MALFORMED"}, spec, check_cell=False)
            require(record["key"] not in by_key, f"certificate key repeated: {record['key']}")
            by_key[record["key"]] = record
            certificates.append(record)
            target["certificates"].append(record["key"])
        target["coverage"] = "CANDIDATE" if target["certificates"] else "OPEN"
    proof_ids = [item["proofId"] for item in certificates if item["form"] == "APR_PROOF"]
    duplicates = sorted({value for value in proof_ids if proof_ids.count(value) > 1})
    checks = [
        {"id": "certificate-keys-unique", "status": "PASS"},
        {"id": "apr-proofs-distinct", "status": "FAIL" if duplicates else "PASS", "detail": duplicates},
        {"id": "certificate-records-consistent",
         "status": "FAIL" if any(item["problems"] for item in certificates) else "PASS",
         "detail": [f"{item['key']}: {problem}" for item in certificates for problem in item["problems"]]},
        {"id": "cells-agree-with-ledger-and-kernels",
         "status": "FAIL" if any(item["problems"] for item in cell_records) else "PASS",
         "detail": [f"{item['profile']}/{item['operation']}: {problem}" for item in cell_records for problem in item["problems"]]},
        {"id": "program-identity",
         "status": ("FAIL" if any(item["problems"] for item in programs) else
                    "PASS" if programs and all(item["reconstruction"] == "MATCH" for item in programs) else "INCOMPLETE"),
         "detail": [f"{item['profile']}/{item['contract']}: {problem}" for item in programs for problem in item["problems"]]},
    ]
    bound_cells = sum(1 for item in cell_records if item["coverage"] == "BOUND")
    complete = bound_cells == 27 and all(item["coverage"] != "OPEN" for item in malformed)
    failed = [check["id"] for check in checks if check["status"] == "FAIL"]
    if mode == "closure":
        require(complete, "closure mode needs every cell and every malformed branch")
        require(not failed, f"closure mode found failing checks: {failed}")
    return {
        "schema": "trust12-tail-preparation-certificate-registry-v1",
        "status": ("FAIL_REGISTRY_INCONSISTENT" if failed else
                   "COVERAGE_COMPLETE_CANDIDATE" if complete else "DRY_RUN_PARTIAL_COVERAGE"),
        "mode": mode,
        "inputs": {
            "ledger": {"root": "EVIDENCE", "path": locators["ledger"], "sha256": sha256_file(ledger_path)},
            "codeIdentity": {"root": "PRODUCT", "path": "evidence/trust12/runtime-link/tail-preparation/code-identity-v1.json",
                             "sha256": sha256_file(CODE_IDENTITY)},
            "locators": locators.get("_source"),
        },
        "certificates": certificates,
        "cells": cell_records,
        "malformed": malformed,
        "programs": programs,
        "partition": {
            "declaredCells": 27,
            "boundCells": bound_cells,
            "openCells": [f"{item['profile']}/{item['operation']}" for item in cell_records if item["coverage"] == "OPEN"],
            "malformedBranches": {item["profile"]: item["coverage"] for item in malformed},
            "coverageComplete": complete,
            "meaning": (
                "Coverage says which cells have a registered applied and not-applied certificate pair agreeing with "
                "the ledger and a PASS kernel run. It is the finite data for the acceptance partition, not the partition "
                "theorem, which a kernel run over the whole registry must still prove."
            ),
        },
        "checks": checks,
        "nonclaim": NONCLAIM,
    }


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    build_parser = commands.add_parser("build")
    build_parser.add_argument("--evidence", type=Path, required=True)
    build_parser.add_argument("--locators", type=Path, required=True)
    build_parser.add_argument("--output", type=Path, required=True)
    build_parser.add_argument("--artifacts", type=Path)
    build_parser.add_argument("--mode", default="dry-run", choices=("dry-run", "closure"))
    verify_parser = commands.add_parser("verify")
    verify_parser.add_argument("--evidence", type=Path, required=True)
    verify_parser.add_argument("--registry", type=Path, required=True)
    verify_parser.add_argument("--locators", type=Path, required=True)
    verify_parser.add_argument("--artifacts", type=Path)
    args = parser.parse_args(argv)
    locators = load_json(args.locators)
    locators["_source"] = {"root": "EVIDENCE", "path": args.locators.resolve().relative_to(args.evidence.resolve()).as_posix(),
                           "sha256": sha256_file(args.locators)}
    if args.command == "build":
        registry = build(args.evidence, locators, args.artifacts, args.mode)
        require_schema(registry, load_json(SCHEMA), "registry")
        require(not args.output.exists(), "registry output already exists")
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(dump_json(registry), encoding="utf-8", newline="\n")
    else:
        recorded = load_json(args.registry)
        registry = build(args.evidence, locators, args.artifacts, recorded["mode"])
        require(json.dumps(registry, sort_keys=True) == json.dumps(recorded, sort_keys=True),
                "registry recomputation differs from the recorded registry")
    print(json.dumps({"status": registry["status"], "boundCells": registry["partition"]["boundCells"],
                      "certificates": len(registry["certificates"]),
                      "checks": {check["id"]: check["status"] for check in registry["checks"]}}, indent=2))
    return 0 if not registry["status"].startswith("FAIL") else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except PreparationError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
