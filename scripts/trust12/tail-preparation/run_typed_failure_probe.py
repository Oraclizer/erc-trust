#!/usr/bin/env python3
"""Run the typed failure probe of the three profiles in an isolated build directory and record it.

The probe compiles the product sources with the probe harness of `scripts/trust12/tail-preparation/typed-failure-probe`
in a copy of the product tree, runs the three profile probes with Foundry, decodes the event of every case and judges
it here:

* the emitted endpoint code must have the code identity of its profile template (equal length and equal bytes
  outside the immutable ranges);
* every control case must be accepted;
* every other case must revert with the expected typed failure, the fixed ABI reading of the payload must produce a
  report, and the report must bind to the request the probe sent and to its sender;
* every bound payload must fail the reading or the binding once it is lengthened, shortened or has a bound word or
  the reason changed, so that the binding check is not vacuous;
* every profile must bind all six typed failures on an action entrypoint and on a reversal entrypoint.

It measures one deployment per profile; it does not prove the binding for every accepted execution. Run it on Linux
or WSL with the pinned Foundry and the pinned upstream token artifacts that scripts/prepare-trex-integration.py
produces. The forge JSON report is kept next to the receipt, and the receipt follows from it with `record`.

With `--mutant ID` the run applies one declared mutant of
`evidence/trust12/runtime-link/tail-preparation/typed-failure-probe-mutants-v1.json` to the isolated copy first and
passes only when every case the mutant names is no longer bound.

Usage:
  run_typed_failure_probe.py --product DIR --trex-artifacts DIR --workdir DIR --output DIR [--mutant ID]
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

_TOOLS = os.environ.get("TRUST12_TAIL_TOOLS")
if _TOOLS:
    sys.path.insert(0, _TOOLS)

import code_identity  # noqa: E402
from run_malformed_probe import topic  # noqa: E402
from run_malformed_probe_v2 import apply_mutation  # noqa: E402
from tail_common import (  # noqa: E402
    NONCLAIM, PreparationError, ROOT, dump_json, keccak256, load_json, require, sha256_bytes, sha256_file,
)
from typed_failure_report import (  # noqa: E402
    abi_failure_report, failure_report_binds, formal_constants, sensitivity_controls, typed_failure_outcome,
)

PROBE_DIRECTORY = "scripts/trust12/tail-preparation/typed-failure-probe"
COPIED = ("implementation/src", "implementation/test", "vectors", "foundry.toml", PROBE_DIRECTORY)
MUTANTS = "evidence/trust12/runtime-link/tail-preparation/typed-failure-probe-mutants-v1.json"
MUTANTS_SCHEMA = "trust12-typed-failure-probe-mutants-v1"
RECEIPT_SCHEMA = "trust12-tail-preparation-typed-failure-probe-receipt-v1"
CASE_EVENT = "TypedFailureProbeCase(uint16,uint8,uint8,uint8,address,bytes32,bytes32,bytes32,bool,bytes)"
CODE_EVENT = "TypedFailureProbeCode(uint8,address,bytes)"
PROFILES = {1: "Native", 2: "Partial", 3: "Hook"}
EXPECTED = {0: None, 1: "TrustInvalidCommand", 2: "TrustRejected", 3: "TrustOperationalFailure",
            4: "TrustUnauthorized", 5: "TrustReplay", 6: "TrustTerminal"}
ACTION_ENTRYPOINTS, REVERSAL_ENTRYPOINTS = {1, 3}, {2, 4}
FACTORY = "implementation/src/profiles/ERC3643HookFactory.sol"
ADAPTER_ARTIFACT = "out/ERC3643HookAdapter.sol/ERC3643HookAdapter.json"
PIN = re.compile(r"bytes32 public constant ADAPTER_CREATION_HASH = 0x([0-9a-f]{64});")


def _words(data: bytes) -> list[int]:
    return [int.from_bytes(data[i:i + 32], "big") for i in range(0, len(data) - len(data) % 32, 32)]


def _dynamic_bytes(data: bytes, offset: int) -> bytes:
    length = int.from_bytes(data[offset:offset + 32], "big")
    return data[offset + 32:offset + 32 + length]


def decode_events(report: dict[str, Any]) -> tuple[list[dict[str, Any]], dict[str, bytes], dict[str, str]]:
    case_topic, code_topic = topic(CASE_EVENT), topic(CODE_EVENT)
    cases, codes, statuses = [], {}, {}
    for suite, content in report.items():
        for test, outcome in content["test_results"].items():
            statuses[f"{suite.split(':')[-1]}.{test}"] = outcome["status"]
            for log in outcome.get("logs", []):
                topics = log.get("topics") or log.get("data", {}).get("topics", [])
                data = log.get("data")
                data = data.get("data") if isinstance(data, dict) else data
                if not topics:
                    continue
                raw = bytes.fromhex(str(data).removeprefix("0x"))
                if topics[0].lower() == case_topic:
                    words = _words(raw)
                    cases.append({
                        "index": int(topics[1], 16),
                        "profile": PROFILES.get(words[0], "unknown"),
                        "entrypoint": words[1],
                        "expected": EXPECTED.get(words[2], "unknown"),
                        "sender": words[3],
                        "commandId": words[4],
                        "authorityRef": words[5],
                        "caseId": words[6],
                        "ok": bool(words[7]),
                        "returnData": _dynamic_bytes(raw, words[8]),
                    })
                elif topics[0].lower() == code_topic:
                    words = _words(raw)
                    codes[PROFILES.get(int(topics[1], 16), "unknown")] = _dynamic_bytes(raw, words[1])
    return cases, codes, statuses


def code_identity_of(codes: dict[str, bytes]) -> dict[str, Any]:
    """Match each emitted endpoint code with its profile template by the exact matching rule."""
    document = load_json(code_identity.DOCUMENT)
    result = {}
    for profile, data in document["profiles"].items():
        endpoint = next(item for item in data["runtimes"] if item["contract"] == data["endpoint"])
        code = codes.get(profile)
        if code is None:
            result[profile] = {"endpoint": data["endpoint"], "matches": False, "reason": "no code event"}
            continue
        same_length = len(code) == endpoint["runtimeTemplate"]["bytes"]
        masked = code_identity.mask(code, endpoint["immutableRanges"]) if same_length else b""
        matches = same_length and sha256_bytes(masked) == endpoint["runtimeTemplate"]["sha256"]
        result[profile] = {"endpoint": data["endpoint"], "matches": matches, "codeBytes": len(code)}
    return result


def evaluate(case: dict[str, Any], constants: dict[str, Any]) -> dict[str, Any]:
    expected = case["expected"]
    if expected is None:
        return {"verdict": "CONTROL_ACCEPTED" if case["ok"] else "CONTROL_FAILED"}
    if case["ok"]:
        return {"verdict": "UNEXPECTED_SUCCESS"}
    report = abi_failure_report(case["returnData"], constants)
    if report is None:
        return {"verdict": "NO_REPORT", "returnBytes": len(case["returnData"])}
    if report["name"] != expected:
        return {"verdict": "OTHER_TYPED_FAILURE", "observed": report["name"], "returnBytes": len(case["returnData"])}
    forward = case["entrypoint"] in ACTION_ENTRYPOINTS
    command = {"kind": "forward" if forward else "reverse", "commandId": case["commandId"],
               "authorityRef": case["authorityRef"], "caseId": case["caseId"]}
    bound = failure_report_binds(report, command, case["sender"], constants)
    controls = sensitivity_controls(case["returnData"], command, case["sender"], constants)
    return {
        "verdict": "BOUND" if bound and all(controls.values()) else ("CONTROL_NOT_DETECTED" if bound else "NOT_BOUND"),
        "outcome": typed_failure_outcome(report, constants),
        "reason": report["reason"],
        "returnBytes": len(case["returnData"]),
        "controls": controls,
    }


def coverage(rows: list[dict[str, Any]]) -> dict[str, Any]:
    names = [name for name in EXPECTED.values() if name]
    result = {}
    for profile in PROFILES.values():
        bound = [row for row in rows if row["profile"] == profile and row["verdict"] == "BOUND"]
        result[profile] = {
            name: {"action": any(row["expected"] == name and row["entrypoint"] in ACTION_ENTRYPOINTS for row in bound),
                   "reversal": any(row["expected"] == name and row["entrypoint"] in REVERSAL_ENTRYPOINTS for row in bound)}
            for name in names
        }
    return result


def mutant_definition(mutants: Path, identifier: str) -> dict[str, Any]:
    declared = load_json(mutants)
    require(declared.get("schema") == MUTANTS_SCHEMA, "mutant list schema drift")
    rows = [row for row in declared["mutants"] if row["id"] == identifier]
    require(len(rows) == 1, f"unknown or repeated mutant: {identifier}")
    return rows[0]


def mutant_verdict(rows: list[dict[str, Any]], mutant: dict[str, Any]) -> dict[str, Any]:
    affected = [row for row in rows if row["profile"] == mutant["profile"] and row["index"] in mutant["cases"]]
    missing = sorted(set(mutant["cases"]) - {row["index"] for row in affected})
    detected = not missing and all(row["verdict"] not in {"BOUND", "CONTROL_ACCEPTED"} for row in affected)
    return {"id": mutant["id"], "cases": {str(row["index"]): row["verdict"] for row in affected},
            "missingCases": missing, "detected": detected}


def probe_sources(product: Path) -> dict[str, str]:
    return {path.name: sha256_file(path) for path in sorted((product / PROBE_DIRECTORY).glob("*.sol"))}


def record(report: dict[str, Any], run: dict[str, Any], forge_version: str, report_sha256: str,
           mutant: dict[str, Any] | None = None, product: Path = ROOT) -> dict[str, Any]:
    """The receipt of one probe run; a pure function of the forge report, the run metadata and the product files."""
    constants = formal_constants()
    cases, codes, statuses = decode_events(report)
    rows = []
    for case in sorted(cases, key=lambda item: (item["profile"], item["index"])):
        rows.append({
            "index": case["index"], "profile": case["profile"], "entrypoint": case["entrypoint"],
            "expected": case["expected"], "sender": f"0x{case['sender']:040x}",
            "commandId": f"0x{case['commandId']:064x}", "authorityRef": f"0x{case['authorityRef']:064x}",
            "caseId": f"0x{case['caseId']:064x}", "ok": case["ok"], "returnData": "0x" + case["returnData"].hex(),
            **evaluate(case, constants),
        })
    identity = code_identity_of(codes)
    covered = coverage(rows)
    # A mutated endpoint has another runtime by construction; its code identity is recorded, not required.
    harness_ok = (run.get("exitCode") == 0 and len(statuses) == 3
                  and all(status == "Success" for status in statuses.values())
                  and all(item["matches"] for profile, item in identity.items()
                          if mutant is None or profile != mutant["profile"])
                  and all(row["verdict"] == "CONTROL_ACCEPTED" for row in rows if row["expected"] is None))
    all_bound = all(row["verdict"] in {"BOUND", "CONTROL_ACCEPTED"} for row in rows) and all(
        flags["action"] and flags["reversal"] for profile in covered.values() for flags in profile.values())
    verdict = mutant_verdict(rows, mutant) if mutant is not None else None
    if not harness_ok:
        status = "PROBE_HARNESS_FAILED"
    elif verdict is not None:
        status = "MUTANT_DETECTED" if verdict["detected"] else "MUTANT_SURVIVED"
    else:
        status = "PROBE_RECORDED_ALL_BOUND" if all_bound else "PROBE_BINDING_FAILED"
    summary: dict[str, int] = {}
    for row in rows:
        key = f"{row['profile']}/{row['expected'] or 'control'}/{row['verdict']}"
        summary[key] = summary.get(key, 0) + 1
    return {
        "schema": RECEIPT_SCHEMA,
        "status": status,
        "probeSources": probe_sources(product),
        "forgeVersion": forge_version,
        "forgeReportSha256": report_sha256,
        "run": run,
        "mutant": verdict,
        "suites": statuses,
        "codeIdentity": identity,
        "coverage": covered,
        "summary": dict(sorted(summary.items())),
        "rows": rows,
        "nonclaim": NONCLAIM + (" The probe is a concrete measurement on one deployment per profile and at least one "
                                "revert site per typed failure and entrypoint, not a proof over every accepted "
                                "execution or every revert site."),
    }


def prepare(product: Path, trex: Path, workdir: Path) -> None:
    require(not workdir.exists(), "the isolated build directory must not exist yet")
    for relative in COPIED:
        source = product / relative
        target = workdir / relative
        if source.is_dir():
            shutil.copytree(source, target, ignore=shutil.ignore_patterns("__pycache__"))
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
    target = workdir / "out/trust12/trex/out/Token.sol/Token.json"
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(trex / "Token.sol/Token.json", target)


def environment() -> dict[str, str]:
    return dict(os.environ, FOUNDRY_TEST=PROBE_DIRECTORY, FOUNDRY_DISABLE_CODE_SIZE_LIMIT="true")


def repin_adapter(workdir: Path) -> dict[str, Any]:
    """The Hook factory accepts only the pinned adapter creation code. A mutated adapter needs the pin of its own
    creation code in the isolated copy, so that the probe measures the changed revert site and not the factory pin."""
    built = subprocess.run(["forge", "build"], cwd=workdir, env=environment(), capture_output=True, text=True)
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


def forge_version() -> str:
    completed = subprocess.run(["forge", "--version"], capture_output=True, text=True)
    require(completed.returncode == 0 and completed.stdout.strip(), "forge --version failed")
    return completed.stdout.strip().splitlines()[0]


def run_forge(workdir: Path) -> tuple[dict[str, Any], bytes, dict[str, Any]]:
    command = ["forge", "test", "-vv", "--json", "--match-path", f"{PROBE_DIRECTORY}/*TypedFailureProbe.t.sol"]
    started = time.time()
    completed = subprocess.run(command, cwd=workdir, env=environment(), capture_output=True, text=True)
    run = {"command": " ".join(command),
           "environment": {"FOUNDRY_TEST": PROBE_DIRECTORY, "FOUNDRY_DISABLE_CODE_SIZE_LIMIT": "true"},
           "exitCode": completed.returncode, "elapsedSeconds": round(time.time() - started, 1)}
    start = completed.stdout.find("{\n")
    if start < 0:
        start = completed.stdout.find('{"')
    require(start >= 0, "forge produced no JSON report: " + (completed.stdout + completed.stderr)[-3000:])
    text = completed.stdout[start:]
    try:
        return json.loads(text), text.encode("utf-8"), run
    except json.JSONDecodeError as error:
        raise PreparationError(f"forge report is not JSON ({error})") from error


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--product", type=Path, required=True)
    parser.add_argument("--trex-artifacts", type=Path, required=True)
    parser.add_argument("--workdir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--mutant", help="apply one declared mutant to the isolated copy before the run")
    parser.add_argument("--keep-workdir", action="store_true")
    args = parser.parse_args(argv)
    product = args.product.resolve()
    require(not args.output.exists(), "probe output already exists")
    mutant = mutant_definition(product / MUTANTS, args.mutant) if args.mutant is not None else None
    version = forge_version()
    prepare(product, args.trex_artifacts, args.workdir)
    try:
        mutation = None
        if mutant is not None:
            mutation = apply_mutation(args.workdir, mutant)
            if mutant.get("repinAdapterCreationHash"):
                mutation["repin"] = repin_adapter(args.workdir)
        report, report_bytes, run = run_forge(args.workdir)
        if mutation is not None:
            run["mutation"] = mutation
    finally:
        if not args.keep_workdir:
            shutil.rmtree(args.workdir, ignore_errors=True)
    args.output.mkdir(parents=True, exist_ok=False)
    report_path = args.output / "forge-report.json"
    report_path.write_bytes(report_bytes)
    receipt = record(report, run, version, sha256_file(report_path), mutant, product)
    (args.output / "receipt.json").write_text(dump_json(receipt), encoding="utf-8", newline="\n")
    print(json.dumps({"status": receipt["status"], "summary": receipt["summary"]}, indent=2))
    passed = "MUTANT_DETECTED" if mutant is not None else "PROBE_RECORDED_ALL_BOUND"
    return 0 if receipt["status"] == passed else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except PreparationError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
