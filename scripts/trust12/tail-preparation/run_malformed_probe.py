#!/usr/bin/env python3
"""Run the malformed probe of the three profiles in an isolated build directory and record it.

The probe compiles the product sources with the probe harness in a copy of the product tree, runs
the three profile probes with Foundry, decodes the events that record each recipe and compares
every observation with the expected behavior of the malformed input catalog. A request outside
canonical form conforms when the call fails without an external account access, a log or a
committed storage write, whatever its revert data (decision 12). It measures; it does not close a
malformed branch. Run it on Linux or WSL with the pinned Foundry and the pinned
upstream token artifacts that scripts/prepare-trex-integration.py produces.

Usage:
  run_malformed_probe.py --product DIR --trex-artifacts DIR --workdir DIR --output DIR
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

from tail_common import NONCLAIM, PreparationError, dump_json, keccak256, load_json, require, sha256_file

CATALOG = Path("evidence/trust12/runtime-link/tail-preparation/malformed-inputs-v1.json")
PROBE_DIRECTORY = "scripts/trust12/tail-preparation/foundry"
RESULT_EVENT = "MalformedProbeResult(uint16,uint8,bytes4,uint256,uint256,uint256,uint256,uint256)"
BASE_EVENT = "MalformedProbeBase(uint8,bool,uint256)"
OUTCOMES = {1: "untyped-empty-revert", 2: "typed-failure", 3: "other-revert", 4: "success"}
MALFORMED_CLASSES = {"no-selector", "unknown-selector", "length", "dirty-enum-word", "dirty-address-word",
                     "dirty-uint64-word", "dirty-uint48-word", "nonzero-call-value"}
TYPED_FAILURE_NAMES = {
    "0x386ecc58": "TrustOperationalFailure", "0x72841b29": "TrustReplay", "0x8cf60b6f": "TrustRejected",
    "0x996b6134": "TrustUnauthorized", "0xa6e257c3": "TrustTerminal", "0xed623c13": "TrustInvalidCommand",
}
COPIED = ("implementation/src", "implementation/test", "vectors", "foundry.toml", PROBE_DIRECTORY)


def topic(signature: str) -> str:
    return "0x" + keccak256(signature.encode("ascii")).hex()


def prepare(product: Path, trex: Path, workdir: Path) -> None:
    require(not workdir.exists(), "the isolated build directory must not exist yet")
    for relative in COPIED:
        source = product / relative
        target = workdir / relative
        if source.is_dir():
            shutil.copytree(source, target)
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
    for name in ("Token.sol/Token.json",):
        target = workdir / "out/trust12/trex/out" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(trex / name, target)


def run_forge(workdir: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    environment = dict(os.environ, FOUNDRY_TEST=PROBE_DIRECTORY, FOUNDRY_DISABLE_CODE_SIZE_LIMIT="true")
    # The JSON report carries the emitted logs of a test only from verbosity two on.
    command = ["forge", "test", "-vv", "--json", "--match-path", f"{PROBE_DIRECTORY}/*MalformedProbe.t.sol"]
    started = time.time()
    completed = subprocess.run(command, cwd=workdir, env=environment, capture_output=True, text=True)
    record = {"command": " ".join(command), "environment": {"FOUNDRY_TEST": PROBE_DIRECTORY,
                                                            "FOUNDRY_DISABLE_CODE_SIZE_LIMIT": "true"},
              "exitCode": completed.returncode, "elapsedSeconds": round(time.time() - started, 1)}
    start = completed.stdout.find("{\n")
    if start < 0:
        start = completed.stdout.find('{"')
    require(start >= 0, "forge produced no JSON report: " + (completed.stdout + completed.stderr)[-3000:])
    try:
        return json.loads(completed.stdout[start:]), record
    except json.JSONDecodeError as error:
        raise PreparationError(f"forge report is not JSON ({error}): {completed.stdout[-3000:]}") from error


def decode_results(report: dict[str, Any]) -> tuple[dict[int, dict[str, Any]], list[dict[str, Any]], dict[str, str]]:
    result_topic, base_topic = topic(RESULT_EVENT), topic(BASE_EVENT)
    results, bases, statuses = {}, [], {}
    for suite, content in report.items():
        for test, outcome in content["test_results"].items():
            statuses[f"{suite.split(':')[-1]}.{test}"] = outcome["status"]
            for log in outcome.get("logs", []):
                topics = log.get("topics") or log.get("data", {}).get("topics", [])
                data = log.get("data")
                data = data.get("data") if isinstance(data, dict) else data
                if not topics:
                    continue
                words = bytes.fromhex(str(data).removeprefix("0x"))
                if topics[0].lower() == result_topic:
                    index = int(topics[1], 16)
                    value = [int.from_bytes(words[32 * i:32 * i + 32], "big") for i in range(7)]
                    results[index] = {
                        "outcome": OUTCOMES.get(value[0], "unknown"),
                        "selector": "0x" + words[32:36].hex() if value[0] in (2, 3) else None,
                        "secondWord": value[2],
                        "returnBytes": value[3],
                        "externalAccesses": value[4],
                        "logs": value[5],
                        "committedWrites": value[6],
                    }
                elif topics[0].lower() == base_topic:
                    bases.append({"suite": suite.split(":")[-1], "entrypoint": int.from_bytes(words[0:32], "big"),
                                  "accepted": bool(int.from_bytes(words[32:64], "big"))})
    return results, bases, statuses


def evaluate(recipe: dict[str, Any], observed: dict[str, Any] | None) -> dict[str, Any]:
    if observed is None:
        return {"verdict": "NOT_OBSERVED"}
    quiet = observed["externalAccesses"] == 0 and observed["logs"] == 0 and observed["committedWrites"] == 0
    failed_quietly = observed["outcome"] != "success" and quiet
    if recipe["class"] in MALFORMED_CLASSES or recipe["class"] == "ordering-probe":
        verdict = "CONFORMS" if failed_quietly else "DEVIATES"
    elif recipe["class"] == "well-formed-control":
        detected = observed["outcome"] == "success" and observed["logs"] > 0 and observed["committedWrites"] > 0
        verdict = "CONTROL_DETECTED" if detected else "CONTROL_FAILED"
    else:
        verdict = "UNKNOWN_CLASS"
    name = TYPED_FAILURE_NAMES.get(observed["selector"] or "")
    return {"verdict": verdict, "typedFailure": name,
            "reason": observed["secondWord"] if name in {"TrustInvalidCommand", "TrustRejected", "TrustOperationalFailure"} else None}


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--product", type=Path, required=True)
    parser.add_argument("--trex-artifacts", type=Path, required=True)
    parser.add_argument("--workdir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--keep-workdir", action="store_true")
    args = parser.parse_args(argv)
    product = args.product.resolve()
    catalog = load_json(product / CATALOG)
    require(not args.output.exists(), "probe output already exists")
    prepare(product, args.trex_artifacts, args.workdir)
    try:
        report, run = run_forge(args.workdir)
    finally:
        if not args.keep_workdir:
            shutil.rmtree(args.workdir, ignore_errors=True)
    results, bases, statuses = decode_results(report)
    rows = []
    for index, recipe in enumerate(catalog["recipes"]):
        observed = results.get(index)
        rows.append({"index": index, "id": recipe["id"], "profile": recipe["profile"], "entrypoint": recipe["entrypoint"],
                     "class": recipe["class"], "variant": recipe["variant"], "word": recipe["word"],
                     "observed": observed, **evaluate(recipe, observed)})
    summary: dict[str, Any] = {}
    for row in rows:
        key = f"{row['profile']}/{row['class']}/{row['verdict']}"
        summary[key] = summary.get(key, 0) + 1
    harness_ok = (all(status == "Success" for status in statuses.values()) and len(statuses) == 3
                  and all(base["accepted"] for base in bases)
                  and all(row["verdict"] == "CONTROL_DETECTED" for row in rows if row["class"] == "well-formed-control")
                  and not any(row["verdict"] == "NOT_OBSERVED" for row in rows))
    receipt = {
        "schema": "trust12-tail-preparation-malformed-probe-receipt-v1",
        "status": "PROBE_RECORDED" if harness_ok and len(results) == len(catalog["recipes"]) else "PROBE_HARNESS_FAILED",
        "catalogSha256": sha256_file(product / CATALOG),
        "probeSources": {path.name: sha256_file(path) for path in sorted((product / PROBE_DIRECTORY).glob("*.sol"))},
        "run": run,
        "suites": statuses,
        "bases": bases,
        "observedRecipes": len(results),
        "declaredRecipes": len(catalog["recipes"]),
        "summary": dict(sorted(summary.items())),
        "rows": rows,
        "nonclaim": NONCLAIM + " The probe is a concrete measurement on one deployment per profile, not a proof "
                               "over all accepted executions.",
    }
    args.output.mkdir(parents=True, exist_ok=False)
    (args.output / "receipt.json").write_text(dump_json(receipt), encoding="utf-8", newline="\n")
    print(json.dumps({"status": receipt["status"], "observedRecipes": len(results), "suites": statuses,
                      "summary": receipt["summary"]}, indent=2))
    return 0 if receipt["status"] == "PROBE_RECORDED" else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except PreparationError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
