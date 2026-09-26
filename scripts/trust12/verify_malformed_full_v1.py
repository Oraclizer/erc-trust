#!/usr/bin/env python3
"""Independently recheck the frozen 42 malformed KEVM/KORE certificates.

This is a host-side integrity audit. It does not establish the Isabelle
out-of-specification branch or the K-to-Isabelle operational link.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


PROFILES = {
    "native": ("native-malformed-kevm-full-v1", 16),
    "partial": ("profile-partial-malformed-kevm-full-v1", 13),
    "hook": ("profile-hook-malformed-kevm-full-v1", 13),
}
MATERIAL_STATUS = "PASS_MALFORMED_KEVM_BOUNDARIES_AND_KORE"


def require(condition: object, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def read_json(path: Path) -> dict:
    result = json.loads(path.read_text(encoding="utf-8"))
    require(isinstance(result, dict), f"JSON object required: {path}")
    return result


def local_path(raw: str, base: Path) -> Path:
    """Rebase a frozen absolute producer path onto a supplied evidence root."""
    normalized = raw.replace("\\", "/")
    marker = "/out/trust12/"
    require(normalized.count(marker) == 1, f"not a TRUST 1.2 evidence pointer: {raw}")
    return base / normalized.split(marker, 1)[1]


def check_record(record: dict, label: str, root: Path, base: Path) -> None:
    path = local_path(record["path"], base)
    require(path.resolve().is_relative_to(root.resolve()), f"{label}: pointer left frozen batch")
    require(path.is_file(), f"{label}: missing {path}")
    payload = path.read_bytes()
    require(len(payload) == record["bytes"], f"{label}: byte length changed")
    require(hashlib.sha256(payload).hexdigest() == record["sha256"], f"{label}: SHA-256 changed")


def check_profile(base: Path, profile: str, folder: str, count: int) -> dict:
    root = base / folder
    result = read_json(root / "result.json")
    material = read_json(root / "materialization-v2-result.json")
    source = read_json(root / "inputs" / "certificates.json")
    require(result["status"] == f"PASS_{profile.upper()}_MALFORMED_KEVM_V1", f"{profile}: KEVM status")
    require(result["sharedCompilationOnly"] is True and result["separateProofIds"] is True,
            f"{profile}: build/proof independence flags")
    require(result["expectedCertificateCount"] == count, f"{profile}: expected count")
    require(material["schema"] == "trust12-malformed-kevm-boundary-materialization-v2"
            and material["status"] == MATERIAL_STATUS, f"{profile}: materialization status")
    require(material["profile"].lower().removeprefix("erc3643-") == profile,
            f"{profile}: materialized profile")
    require(source["profile"].lower().removeprefix("erc3643-") == profile,
            f"{profile}: catalog profile")
    require(source["expectedCount"] == count, f"{profile}: catalog count")
    rows, mrows, srows = result["certificates"], material["certificates"], source["certificates"]
    require(len(rows) == len(mrows) == len(srows) == count, f"{profile}: row count")
    slugs = [row["slug"] for row in rows]
    proof_ids = [row["proofId"] for row in rows]
    require(len(set(slugs)) == len(set(proof_ids)) == count, f"{profile}: duplicate slug or proof ID")
    require(set(slugs) == {row["slug"] for row in mrows} == {row["slug"] for row in srows},
            f"{profile}: catalog/result slug mismatch")
    require({row["proofId"] for row in mrows} == set(proof_ids), f"{profile}: materialized proof ID mismatch")
    source_by_slug = {row["slug"]: row for row in srows}
    material_by_slug = {row["slug"]: row for row in mrows}
    check_record(result["certificateSpec"], f"{profile}: frozen catalog", root, base)
    check_record(material["certificateSpec"], f"{profile}: materialized catalog", root, base)
    check_record(material["batch"], f"{profile}: materialized batch", root, base)
    for row in rows:
        label = f"{profile}/{row['slug']}"
        source_row = source_by_slug[row["slug"]]
        material_row = material_by_slug[row["slug"]]
        for key in ("test", "malformedClass", "entrypoint", "boundary"):
            require(row[key] == source_row[key], f"{label}: frozen catalog {key} mismatch")
        for key in ("malformedClass", "entrypoint"):
            require(material_row[key] == source_row[key], f"{label}: materialized {key} mismatch")
        require(material_row["proofId"] == row["proofId"]
                and material_row["boundaryShape"] == source_row["boundary"],
                f"{label}: materialized proof or request boundary mismatch")
        require(row["passed"] is True and row["failed"] is False and not row["pendingNodes"]
                and not row["failingNodes"] and row["admitted"] is False and row["circularity"] is False,
                f"{label}: proof is not closed")
        require(row["proofType"] == "APRProof", f"{label}: proof type")
        for key in ("proofJson", "kcfg"):
            check_record(row[key], f"{label}/{key}", root, base)
    for row in mrows:
        label = f"{profile}/{row['slug']}"
        for key in ("boundary", "snapshotResult", "precallResult", "koreResult"):
            check_record(row[key], f"{label}/{key}", root, base)
        require(row["valueTransferBeforeEntry"]["transfer"] in (0, 1),
                f"{label}: unexpected pre-entry transfer")
        precall = read_json(local_path(row["precallResult"]["path"], base))
        require(precall["restoredAccountsEqualPrecallAccounts"] is True
                and precall["restoredLogEqualPrecallLog"] is True,
                f"{label}: restored state or log changed")
        require(precall["transfer"] == row["valueTransferBeforeEntry"],
                f"{label}: transfer summary mismatch")
        for key in ("accounts", "resultlog"):
            check_record(precall["precall"]["written"][key], f"{label}/precall/{key}", root, base)
    return {"profile": profile, "certificates": count, "proofIds": len(set(proof_ids)),
            "materializationPointers": 6 * count, "proofPointers": 2 * count}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", type=Path, required=True)
    parser.add_argument("--profiles", nargs="+", choices=tuple(PROFILES), default=list(PROFILES),
                        help="profiles to audit; the default requires all three")
    args = parser.parse_args()
    require(len(set(args.profiles)) == len(args.profiles), "duplicate profile")
    reports = [check_profile(args.base, profile, folder, count)
               for profile in args.profiles for folder, count in [PROFILES[profile]]]
    full = set(args.profiles) == set(PROFILES)
    print(json.dumps({"status": ("PASS_HOST_REHASH_MALFORMED_FULL42" if full else
                                  "PASS_HOST_REHASH_MALFORMED_SUBSET"),
                      "certificates": sum(report["certificates"] for report in reports),
                      "profiles": reports}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
