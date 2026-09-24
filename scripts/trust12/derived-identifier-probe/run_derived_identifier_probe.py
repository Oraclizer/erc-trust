#!/usr/bin/env python3
"""Run the derived-identifier probe of the three profiles in an isolated build directory.

The probe checks that an identifier returned by deriveActionId or deriveReversalId cannot make a request
that is not in canonical form pass a typed command function: every malformed variant must revert without
touching an account other than the endpoint, without a log, and without a committed storage write, while
the canonical base request of each variant is accepted.

  run_derived_identifier_probe.py --product DIR --trex-artifacts DIR --workdir DIR --output DIR

The build directory must not exist; it holds a copy of the implementation, the tests, the vectors, the
Foundry configuration, and this probe, plus the pinned upstream token artifact the Hook profile needs.
The report is written to OUTPUT/derived-identifier-probe.json.
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

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tail-preparation"))
from tail_common import PreparationError, dump_json, keccak256, require, sha256_file  # noqa: E402

PROBE_DIRECTORY = "scripts/trust12/derived-identifier-probe"
COPIED = ("implementation/src", "implementation/test", "vectors", "foundry.toml", PROBE_DIRECTORY)
RESULT_EVENT = "DerivedIdentifierProbeResult(bytes4,uint8,uint16,uint256,bool,bool,bool,bytes4,uint256,uint256,uint256)"
SUMMARY_EVENT = "DerivedIdentifierProbeSummary(uint256,uint256,uint256,uint256)"
CASES = {0: "canonical-control", 1: "malformed-with-its-derived-identifier",
         2: "canonical-with-a-malformed-derived-identifier", 3: "trailing-bytes-with-derived-identifier"}
ENTRYPOINTS = {"0x2f4e0773": "executeRegulatoryAction", "0x2b892e8f": "executeRegulatoryReversal",
               "0x40a9c893": "executeERC7943Action", "0x1c711a94": "executeERC7943Reversal"}


def topic(signature: str) -> str:
    return "0x" + keccak256(signature.encode("ascii")).hex()


def prepare(product: Path, trex: Path, workdir: Path) -> None:
    require(not workdir.exists(), "the isolated build directory must not exist yet")
    for relative in COPIED:
        source, target = product / relative, workdir / relative
        if source.is_dir():
            shutil.copytree(source, target)
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
    target = workdir / "out/trust12/trex/out/Token.sol/Token.json"
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(trex / "Token.sol/Token.json", target)


def run_forge(workdir: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    environment = dict(os.environ, FOUNDRY_TEST=PROBE_DIRECTORY, FOUNDRY_DISABLE_CODE_SIZE_LIMIT="true")
    command = ["forge", "test", "-vv", "--json", "--match-path", f"{PROBE_DIRECTORY}/*DerivedIdentifierProbe.t.sol"]
    started = time.time()
    completed = subprocess.run(command, cwd=workdir, env=environment, capture_output=True, text=True)
    record = {"command": " ".join(command),
              "environment": {"FOUNDRY_TEST": PROBE_DIRECTORY, "FOUNDRY_DISABLE_CODE_SIZE_LIMIT": "true"},
              "exitCode": completed.returncode, "elapsedSeconds": round(time.time() - started, 1)}
    start = completed.stdout.find("{\n")
    if start < 0:
        start = completed.stdout.find('{"')
    require(start >= 0, "forge produced no JSON report: " + (completed.stdout + completed.stderr)[-3000:])
    try:
        return json.loads(completed.stdout[start:]), record
    except json.JSONDecodeError as error:
        raise PreparationError(f"forge report is not JSON ({error}): {completed.stdout[-3000:]}") from error


def decode(report: dict[str, Any]) -> tuple[dict[str, str], list[dict[str, Any]], list[dict[str, Any]]]:
    result_topic, summary_topic = topic(RESULT_EVENT), topic(SUMMARY_EVENT)
    statuses: dict[str, str] = {}
    results: list[dict[str, Any]] = []
    summaries: list[dict[str, Any]] = []
    for suite, content in report.items():
        for test, outcome in content["test_results"].items():
            name = f"{suite.split(':')[-1]}.{test}"
            statuses[name] = outcome["status"]
            for log in outcome.get("logs", []):
                topics = log.get("topics") or log.get("data", {}).get("topics", [])
                data = log.get("data")
                data = data.get("data") if isinstance(data, dict) else data
                if not topics:
                    continue
                words = bytes.fromhex(str(data).removeprefix("0x"))
                value = [int.from_bytes(words[32 * i:32 * i + 32], "big") for i in range(len(words) // 32)]
                if topics[0].lower() == result_topic:
                    entrypoint = "0x" + bytes.fromhex(topics[1].removeprefix("0x"))[:4].hex()
                    results.append({
                        "test": name,
                        "entrypoint": ENTRYPOINTS.get(entrypoint, entrypoint),
                        "case": CASES.get(value[0], str(value[0])),
                        "word": value[1],
                        "value": hex(value[2]),
                        "derivationReturned": bool(value[3]),
                        "derivationMatchesRawHash": bool(value[4]),
                        "accepted": bool(value[5]),
                        "revertSelector": "0x" + words[32 * 6:32 * 6 + 4].hex(),
                        "externalAccesses": value[7],
                        "logs": value[8],
                        "committedWrites": value[9],
                    })
                elif topics[0].lower() == summary_topic:
                    summaries.append({"test": name, "controls": value[0], "malformedCalls": value[1],
                                      "derivationsReturned": value[2], "violations": value[3]})
    return statuses, results, summaries


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--product", type=Path, required=True)
    parser.add_argument("--trex-artifacts", type=Path, required=True)
    parser.add_argument("--workdir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--keep-workdir", action="store_true")
    args = parser.parse_args(argv)
    product, workdir = args.product.resolve(), args.workdir.resolve()
    prepare(product, args.trex_artifacts.resolve(), workdir)
    try:
        report, run = run_forge(workdir)
    finally:
        if not args.keep_workdir:
            shutil.rmtree(workdir, ignore_errors=True)
    statuses, results, summaries = decode(report)
    malformed = [r for r in results if r["case"] != "canonical-control"]
    controls = [r for r in results if r["case"] == "canonical-control"]
    accepted_malformed = [r for r in malformed
                          if r["accepted"] and r["case"] != "canonical-with-a-malformed-derived-identifier"]
    traces = [r for r in malformed if not r["accepted"]
              and (r["externalAccesses"] or r["logs"] or r["committedWrites"])]
    passed = (run["exitCode"] == 0 and statuses and all(s == "Success" for s in statuses.values())
              and summaries and all(s["violations"] == 0 for s in summaries)
              and controls and all(c["accepted"] for c in controls) and not accepted_malformed and not traces)
    document = {
        "schema": "trust12-derived-identifier-probe-v1",
        "status": "PASS_DERIVED_IDENTIFIER_CANNOT_BYPASS_CANONICAL_FORM" if passed else "FAIL_DERIVED_IDENTIFIER_PROBE",
        "run": run,
        "probeSources": {path.name: sha256_file(path) for path in sorted((product / PROBE_DIRECTORY).glob("*"))
                         if path.is_file()},
        "tests": statuses,
        "summaries": summaries,
        "counts": {
            "controlsAccepted": sum(1 for c in controls if c["accepted"]),
            "malformedCalls": len(malformed),
            "malformedAccepted": len(accepted_malformed),
            "malformedWithTrace": len(traces),
            "derivationsReturnedForMalformedCalldata": sum(1 for r in malformed if r["derivationReturned"]),
            "byCase": {case: sum(1 for r in results if r["case"] == case) for case in CASES.values()},
        },
        "results": results,
        "nonclaim": ("Concrete executions of the listed base requests and their malformed variants on the test "
                     "fixtures of the three profiles; not a proof over all requests or all states."),
    }
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "derived-identifier-probe.json").write_text(dump_json(document), encoding="utf-8", newline="\n")
    print(json.dumps({"status": document["status"], "counts": document["counts"], "tests": statuses}, indent=2))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
