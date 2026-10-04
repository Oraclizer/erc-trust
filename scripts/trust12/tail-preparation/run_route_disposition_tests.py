#!/usr/bin/env python3
"""Run the route disposition tests in an isolated build directory and record the result.

The tests under `scripts/trust12/tail-preparation/route-dispositions` execute, on the Native fixture and on a
Hook factory unit against the pinned upstream token, the state-changing routes outside the typed commands
whose dispositions no recorded test of the implementation suite executes. This runner copies the product
sources, the implementation tests that the route tests import and the route tests into an empty directory,
runs Foundry there and writes a receipt with the hash of every route test file, the source root of the
implementation sources and tests it compiled (computed as the recorded Foundry results compute it), the command,
the exit code and the status of every test. The forge JSON report is kept next to the receipt.

The route inventory (`route_inventory_v2.py build --disposition-run RECEIPT`) counts a cited route test as an
execution only when this receipt lists it as passed, records the hash of the current bytes of its file and records
the source root of the current implementation sources and tests. Run it on Linux or WSL with the pinned Foundry
and the pinned upstream token artifacts that scripts/prepare-trex-integration.py produces.

Usage:
  run_route_disposition_tests.py --product DIR --trex-artifacts DIR --workdir DIR --output DIR
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

from tail_common import PreparationError, dump_json, require, sha256_bytes, sha256_file

TEST_DIRECTORY = "scripts/trust12/tail-preparation/route-dispositions"
RUNNER = "scripts/trust12/tail-preparation/run_route_disposition_tests.py"
COPIED = ("implementation/src", "implementation/test", "vectors", "foundry.toml", TEST_DIRECTORY)
# The files of the source root of the recorded Foundry results (sha256-raw-files-case-sensitive-path-order-v1).
IMPLEMENTATION_DIRECTORIES = ("implementation/src", "implementation/test")
IMPLEMENTATION_FILES = ("foundry.toml",)
SCHEMA = "trust12-tail-preparation-route-disposition-run-v1"
PASSED = "ROUTE_DISPOSITION_TESTS_PASSED"
NONCLAIM = ("Concrete executions on one Native fixture and one Hook factory unit. A passed test executes the "
            "route with the chosen callers and inputs; it is not a proof over every caller, state or input, and it "
            "does not discharge the route-exhaustiveness condition by itself.")


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


def run_forge(workdir: Path) -> tuple[dict[str, Any], bytes, dict[str, Any]]:
    environment = dict(os.environ, FOUNDRY_TEST=TEST_DIRECTORY)
    command = ["forge", "test", "-vv", "--json", "--match-path", f"{TEST_DIRECTORY}/*.t.sol"]
    started = time.time()
    completed = subprocess.run(command, cwd=workdir, env=environment, capture_output=True, text=True)
    run = {"command": " ".join(command), "environment": {"FOUNDRY_TEST": TEST_DIRECTORY},
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


def declared_tests(product: Path) -> list[tuple[str, str]]:
    """Every (suite, test) pair the route test files declare, read from the source."""
    pairs = []
    for path in sorted((product / TEST_DIRECTORY).glob("*.t.sol")):
        text = path.read_text(encoding="utf-8")
        contracts = re.findall(r"^contract (\w+)", text, re.MULTILINE)
        require(len(contracts) == 1, f"{path.name}: a route test file declares exactly one contract")
        suite = f"{TEST_DIRECTORY}/{path.name}:{contracts[0]}"
        pairs += [(suite, f"{name}()") for name in re.findall(r"function (test\w+)\(\) external", text)]
    return sorted(pairs)


def implementation_root(product: Path) -> str:
    """Source root of the implementation sources and tests, computed as the recorded Foundry results compute it:
    SHA-256 over 'sha256  path<LF>' lines in case-sensitive path order."""
    paths = [item.relative_to(product).as_posix() for directory in IMPLEMENTATION_DIRECTORIES
             for item in (product / directory).rglob("*") if item.is_file() and "__pycache__" not in item.parts]
    paths = sorted(paths + list(IMPLEMENTATION_FILES))
    return sha256_bytes("".join(f"{sha256_file(product / path)}  {path}\n" for path in paths).encode("utf-8"))


def forge_version() -> str:
    completed = subprocess.run(["forge", "--version"], capture_output=True, text=True)
    require(completed.returncode == 0 and completed.stdout.strip(), "forge --version failed")
    return completed.stdout.strip().splitlines()[0]


def record(report: dict[str, Any], run: dict[str, Any], report_sha256: str, product: Path,
           version: str) -> dict[str, Any]:
    tests = sorted(({"suite": suite, "test": test, "status": outcome["status"]}
                    for suite, content in report.items() for test, outcome in content["test_results"].items()),
                   key=lambda item: (item["suite"], item["test"]))
    expected = declared_tests(product)
    observed = [(item["suite"], item["test"]) for item in tests]
    passed = run["exitCode"] == 0 and observed == expected and all(item["status"] == "Success" for item in tests)
    sources = {f"{TEST_DIRECTORY}/{path.name}": sha256_file(path)
               for path in sorted((product / TEST_DIRECTORY).glob("*.sol"))}
    return {
        "schema": SCHEMA,
        "status": PASSED if passed else "ROUTE_DISPOSITION_TESTS_FAILED",
        "sources": sources,
        "implementationRootSha256": implementation_root(product),
        "runner": {"path": RUNNER, "sha256": sha256_file(product / RUNNER)},
        "forgeVersion": version,
        "forgeReportSha256": report_sha256,
        "run": run,
        "declaredTests": len(expected),
        "tests": tests,
        "nonclaim": NONCLAIM,
    }


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--product", type=Path, required=True)
    parser.add_argument("--trex-artifacts", type=Path, required=True)
    parser.add_argument("--workdir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--keep-workdir", action="store_true")
    args = parser.parse_args(argv)
    product = args.product.resolve()
    require(not args.output.exists(), "test run output already exists")
    version = forge_version()
    prepare(product, args.trex_artifacts, args.workdir)
    try:
        report, report_bytes, run = run_forge(args.workdir)
    finally:
        if not args.keep_workdir:
            shutil.rmtree(args.workdir, ignore_errors=True)
    args.output.mkdir(parents=True, exist_ok=False)
    report_path = args.output / "forge-report.json"
    report_path.write_bytes(report_bytes)
    receipt = record(report, run, sha256_file(report_path), product, version)
    (args.output / "receipt.json").write_text(dump_json(receipt), encoding="utf-8", newline="\n")
    print(json.dumps({"status": receipt["status"], "tests": {f"{item['suite'].split(':')[-1]}.{item['test']}":
                                                              item["status"] for item in receipt["tests"]}}, indent=2))
    return 0 if receipt["status"] == PASSED else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except PreparationError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
