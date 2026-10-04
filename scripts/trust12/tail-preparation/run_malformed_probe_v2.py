#!/usr/bin/env python3
"""Run the malformed probe on a copy of the product with one guard mutation applied, and record it.

The first version measures the unmodified product. This version applies one declared mutation to the
isolated copy before the build: it removes an exact calldata length guard of one profile endpoint. The
closure acceptance of each malformed condition asks that disabling such a guard turns a witness outside
canonical form into an execution that is accepted or that emits a log, makes an external call or changes
state. A mutant is detected when, for every endpoint it affects, at least one length recipe of that
endpoint deviates from the quiet failure that decision 12 requires. It measures; it does not close a
malformed branch. Run it on Linux or WSL with the pinned Foundry and the pinned upstream token artifacts.

Usage:
  run_malformed_probe_v2.py --product DIR --trex-artifacts DIR --workdir DIR --output DIR --mutant ID
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

from run_malformed_probe import (CATALOG, PROBE_DIRECTORY, decode_results, evaluate, prepare, run_forge)
from tail_common import NONCLAIM, PreparationError, dump_json, keccak256, load_json, require, sha256_file

MUTANTS = Path("evidence/trust12/runtime-link/tail-preparation/malformed-probe-mutants-v1.json")
RUNNERS = ("scripts/trust12/tail-preparation/run_malformed_probe.py",
           "scripts/trust12/tail-preparation/run_malformed_probe_v2.py")
CAMPAIGN = Path("scripts/mutation-campaign-v1.json")


def mutant_definition(product: Path, identifier: str, mutants: Path) -> dict[str, Any]:
    declared = load_json(mutants)
    require(declared.get("schema") == "trust12-malformed-probe-mutants-v1", "mutant list schema drift")
    rows = [row for row in declared["mutants"] if row["id"] == identifier]
    require(len(rows) == 1, f"unknown or repeated mutant: {identifier}")
    row = dict(rows[0])
    if "campaignId" in row:
        campaign = load_json(product / CAMPAIGN)["definitions"]
        matches = [item for item in campaign if item["id"] == row["campaignId"]]
        require(len(matches) == 1, f"campaign mutation missing: {row['campaignId']}")
        for key in ("file", "old", "new", "expectedOccurrences"):
            row[key] = matches[0][key]
    for key in ("profile", "entrypoints", "file", "old", "new", "expectedOccurrences"):
        require(key in row, f"mutant {identifier} lacks {key}")
    return row


def apply_mutation(workdir: Path, mutant: dict[str, Any]) -> dict[str, Any]:
    target = workdir / mutant["file"]
    require(target.is_file(), f"mutated file missing: {mutant['file']}")
    before = target.read_text(encoding="utf-8")
    require(before.count(mutant["old"]) == mutant["expectedOccurrences"],
            f"mutation anchor count differs: {mutant['id']}")
    after = before.replace(mutant["old"], mutant["new"])
    target.write_text(after, encoding="utf-8", newline="\n")
    return {"file": mutant["file"], "occurrences": mutant["expectedOccurrences"],
            "beforeSha256": sha256_file_text(before), "afterSha256": sha256_file_text(after)}


def sha256_file_text(text: str) -> str:
    import hashlib
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


FACTORY = "implementation/src/profiles/ERC3643HookFactory.sol"
ADAPTER_ARTIFACT = "out/ERC3643HookAdapter.sol/ERC3643HookAdapter.json"
PIN = re.compile(r"bytes32 public constant ADAPTER_CREATION_HASH = 0x([0-9a-f]{64});")


def repin_adapter(workdir: Path) -> dict[str, Any]:
    """The Hook factory accepts only the pinned adapter creation code. A mutated adapter needs the pin of its own
    creation code in the isolated copy, so that the probe measures the removed guard and not the factory pin."""
    environment = dict(os.environ, FOUNDRY_TEST=PROBE_DIRECTORY, FOUNDRY_DISABLE_CODE_SIZE_LIMIT="true")
    built = subprocess.run(["forge", "build"], cwd=workdir, env=environment, capture_output=True, text=True)
    require(built.returncode == 0, "mutated build failed: " + (built.stdout + built.stderr)[-2000:])
    creation = bytes.fromhex(load_json(workdir / ADAPTER_ARTIFACT)["bytecode"]["object"].removeprefix("0x"))
    target = workdir / FACTORY
    text = target.read_text(encoding="utf-8")
    pins = PIN.findall(text)
    require(len(pins) == 1, "factory adapter pin not found exactly once")
    new_pin = keccak256(creation).hex()
    target.write_text(PIN.sub(f"bytes32 public constant ADAPTER_CREATION_HASH = 0x{new_pin};", text),
                      encoding="utf-8", newline="\n")
    return {"file": FACTORY, "beforePin": "0x" + pins[0], "afterPin": "0x" + new_pin,
            "reason": "pin the mutated adapter creation code in the isolated copy only"}


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--product", type=Path, required=True)
    parser.add_argument("--trex-artifacts", type=Path, required=True)
    parser.add_argument("--workdir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--mutant", required=True)
    parser.add_argument("--mutants", type=Path, help="mutant list; defaults to the product copy")
    parser.add_argument("--keep-workdir", action="store_true")
    args = parser.parse_args(argv)
    product = args.product.resolve()
    catalog = load_json(product / CATALOG)
    mutants = (args.mutants or product / MUTANTS).resolve()
    mutant = mutant_definition(product, args.mutant, mutants)
    require(not args.output.exists(), "probe output already exists")
    prepare(product, args.trex_artifacts, args.workdir)
    try:
        mutation = apply_mutation(args.workdir, mutant)
        if mutant.get("repinAdapterCreationHash"):
            mutation["repin"] = repin_adapter(args.workdir)
        report, run = run_forge(args.workdir)
    finally:
        if not args.keep_workdir:
            shutil.rmtree(args.workdir, ignore_errors=True)
    results, bases, statuses = decode_results(report)
    rows = []
    for index, recipe in enumerate(catalog["recipes"]):
        observed = results.get(index)
        rows.append({"index": index, "id": recipe["id"], "profile": recipe["profile"],
                     "entrypoint": recipe["entrypoint"], "class": recipe["class"], "variant": recipe["variant"],
                     "observed": observed, **evaluate(recipe, observed)})
    affected = {entrypoint: [row for row in rows if row["profile"] == mutant["profile"]
                             and row["entrypoint"] == entrypoint and row["class"] == "length"]
                for entrypoint in mutant["entrypoints"]}
    require(all(affected.values()), "a mutated endpoint has no length recipe")
    deviating = {entrypoint: [row["id"] for row in items if row["verdict"] == "DEVIATES"]
                 for entrypoint, items in affected.items()}
    harness_ok = (all(status == "Success" for status in statuses.values()) and len(statuses) == 3
                  and all(base["accepted"] for base in bases) and len(results) == len(catalog["recipes"])
                  and all(row["verdict"] == "CONTROL_DETECTED" for row in rows if row["class"] == "well-formed-control")
                  and not any(row["verdict"] == "NOT_OBSERVED" for row in rows))
    detected = harness_ok and all(deviating.values())
    receipt = {
        "schema": "trust12-tail-preparation-malformed-probe-mutant-receipt-v1",
        "status": "MUTANT_DETECTED" if detected else ("MUTANT_SURVIVED" if harness_ok else "PROBE_HARNESS_FAILED"),
        "mutant": {key: mutant[key] for key in ("id", "profile", "entrypoints", "fault") if key in mutant},
        "mutation": mutation,
        "catalogSha256": sha256_file(product / CATALOG),
        "mutantListSha256": sha256_file(mutants),
        "probeSources": {path.name: sha256_file(path) for path in sorted((product / PROBE_DIRECTORY).glob("*.sol"))},
        "runners": {path: sha256_file(product / path) for path in RUNNERS},
        "run": run,
        "suites": statuses,
        "bases": bases,
        "deviatingLengthRecipes": deviating,
        "affectedRows": [row for items in affected.values() for row in items],
        "nonclaim": NONCLAIM + " A detected mutant shows that removing this guard is observable on the probe "
                               "deployment; it is not a proof over all accepted executions.",
    }
    args.output.mkdir(parents=True, exist_ok=False)
    (args.output / "receipt.json").write_text(dump_json(receipt), encoding="utf-8", newline="\n")
    print(json.dumps({"status": receipt["status"], "mutant": mutant["id"], "deviating": deviating,
                      "suites": statuses}, indent=2))
    return 0 if detected else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except PreparationError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
