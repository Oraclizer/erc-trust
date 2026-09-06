#!/usr/bin/env python3
"""Fail closed when the TRUST 1.2 development ledger or its curated receipts drift."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "evidence/trust12"


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf8"))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def main() -> None:
    runtime = read_json(EVIDENCE / "runtime-identity.json")
    symbolic = read_json(EVIDENCE / "symbolic-kontrol.json")
    ledger = read_json(EVIDENCE / "obligation-ledger.json")
    seal = read_json(EVIDENCE / "input-seal.json")
    check(runtime["status"] == "PASS", "runtime identity is not PASS")
    check(symbolic["status"] == "INCOMPLETE", "symbolic status must remain explicitly incomplete")
    check(ledger["status"] == "IN_PROGRESS", "ledger must remain in progress while mandatory rows are open")

    mutations = {}
    for path in sorted(EVIDENCE.glob("mutation-*.json")):
        receipt = read_json(path)
        mutation_id = receipt["mutation"]
        check(receipt["status"] == "KILLED", f"mutation is not KILLED: {mutation_id}")
        source = ROOT / receipt["sourcePath"]
        check(source.is_file(), f"mutation source missing: {source}")
        check(sha256(source) == receipt["originalSha256"], f"mutation source drift: {mutation_id}")
        mutations[mutation_id] = path.relative_to(ROOT).as_posix()
    check(
        set(mutations) == {"inbound", "initial", "receipt", "callback-auth", "hidden-agent", "factory-pin"},
        "mutation receipt set is incomplete",
    )

    rows = {row["id"]: row for row in ledger["obligations"]}
    check(len(rows) == len(ledger["obligations"]), "duplicate obligation id")
    mandatory = {row_id for row_id, row in rows.items() if row["status"] == "CURRENT-MANDATORY"}
    check(
        mandatory == set(ledger["centralClosure"]["currentMandatory"]),
        "central mandatory list differs from obligation statuses",
    )
    check(mandatory, "an incomplete central closure cannot have zero mandatory rows")
    for row in rows.values():
        check(row["status"] in {"CLOSED", "CURRENT-MANDATORY"}, f"unknown status: {row['id']}")
        if row["status"] == "CLOSED":
            check("Pending" not in row["positiveActivation"], f"closed row has pending positive: {row['id']}")
            check("Pending" not in row["consumerRemovalNegative"], f"closed row has pending negative: {row['id']}")

    check(seal["schema"] == "trust12-input-seal-v2", "unexpected input seal schema")
    sealed_paths = set()
    for entry in seal["files"]:
        path = ROOT / entry["path"]
        check(path.is_file(), f"sealed input missing: {entry['path']}")
        check(sha256(path) == entry["sha256"], f"sealed input drift: {entry['path']}")
        sealed_paths.add(entry["path"])
    check("evidence/trust12/obligation-ledger.json" in sealed_paths, "ledger is not input-sealed")
    print(
        json.dumps(
            {
                "status": "PASS",
                "ledger": ledger["status"],
                "centralClosure": ledger["centralClosure"]["status"],
                "mutations": sorted(mutations),
                "mandatory": sorted(mandatory),
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
