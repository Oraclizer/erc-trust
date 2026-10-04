#!/usr/bin/env python3
"""Recompute the typed failure selector loads of the TRUST 1.2 profile runtimes from a recorded isolated build.

Version 1 (`code_identity.py`) records where each runtime loads the six typed failure selectors but keeps a recorded
scan when it is run without artifacts and never fails on a missing load. This tool closes both gaps for the typed
failure report binding:

* It reads the compiled runtimes only from the artifact directory it is given, the Foundry `out` directory of a build
  of the frozen sources made in an isolated copy. It never reuses a recorded scan.
* With `--build-record`, the record that the isolated build wrote, every scanned artifact must have the SHA-256 that
  the record lists, and the scan names the record by its SHA-256.
* It binds the build to the frozen identity before it scans: every runtime must equal its template exactly, its
  immutable references must equal the bridge artifact, its compiler settings must equal the bound standard JSON
  input, and every source the compiler metadata names must have the keccak256 of the bound source content.
* In closure mode every profile endpoint runtime must load each of the six typed failure selectors at least once, no
  typed failure selector may also be a function selector of that runtime, and the recorded scan of the code identity
  document must equal the recomputed scan offset by offset.

A load is a static compiled consumer: the runtime puts the four selector bytes on the stack as a PUSH4 immediate, a
left-aligned PUSH32 word, or a shorter immediate shifted into place. It does not show on which path a failure is raised
or which words follow the selector; the argument layout of each typed revert is measured by the typed failure probe on
the compiled runtime.

Usage:
  code_identity_v2.py --artifacts DIR [--build-record FILE] [--mode prepare|closure] [--compare-recorded FILE]
                      [--output FILE] [--report FILE]
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
from typing import Any

_TOOLS = os.environ.get("TRUST12_TAIL_TOOLS")
if _TOOLS:
    sys.path.insert(0, _TOOLS)

import code_identity as v1  # noqa: E402
from tail_common import (  # noqa: E402
    NONCLAIM, PROFILE_RUNTIMES, ROOT, PreparationError, dump_json, keccak256, load_json, require, sha256_bytes,
    sha256_file,
)

SCHEMA = "trust12-tail-preparation-code-identity-scan-v2"
BUILD_RECORD_SCHEMA = "trust12-tail-preparation-frozen-build-record-v1"
RECORDED = v1.DOCUMENT
ENDPOINTS = dict(v1.ENDPOINTS)
FORMS = ("push4", "push32LeftAligned", "shiftedPush")
SETTINGS = ("optimizer", "evmVersion", "viaIR")
METADATA_SETTINGS = ("bytecodeHash", "appendCBOR")


def bound_input(profile: str) -> dict[str, Any]:
    return load_json(ROOT / "evidence/runtime-binding-v3" / v1.BINDING[profile] / "standard-json-input.json")


def compiler_binding(artifact: dict[str, Any], bound: dict[str, Any], name: str) -> dict[str, Any]:
    """Tie one compiled artifact to the bound compiler settings and source contents."""
    metadata = artifact.get("metadata")
    require(isinstance(metadata, dict), f"{name}: compiler metadata missing from the artifact")
    identity = load_json(v1.RUNTIME_IDENTITY)["compiler"]
    version = metadata["compiler"]["version"]
    require(version.split("+", 1)[0] == identity["solc"], f"{name}: compiler {version} is not {identity['solc']}")
    settings = metadata["settings"]
    for key in SETTINGS:
        require(settings.get(key) == bound["settings"].get(key), f"{name}: compiler setting {key} differs from the bound input")
    for key in METADATA_SETTINGS:
        require(settings["metadata"].get(key) == bound["settings"]["metadata"].get(key),
                f"{name}: metadata setting {key} differs from the bound input")
    require(not settings.get("libraries"), f"{name}: linked libraries are not part of the bound build")
    sources = {}
    for path, record in sorted(metadata["sources"].items()):
        content = bound["sources"].get(path, {}).get("content")
        require(content is not None, f"{name}: compiled from a source outside the bound input: {path}")
        expected = "0x" + keccak256(content.encode("utf-8")).hex()
        require(record["keccak256"] == expected, f"{name}: source {path} differs from the bound input")
        sources[path] = expected
    return {"compiler": version, "settings": {key: settings.get(key) for key in SETTINGS},
            "metadata": {key: settings["metadata"].get(key) for key in METADATA_SETTINGS}, "sourceKeccak256": sources}


def artifact_path(entry: dict[str, Any]) -> str:
    return (Path(Path(entry["source"]).name) / f"{entry['contract']}.json").as_posix()


def scan_runtime(artifacts: Path, entry: dict[str, Any], failures: list[dict[str, Any]],
                 bound: dict[str, Any], recorded_build: dict[str, Any] | None) -> dict[str, Any]:
    name = entry["contract"]
    relative = artifact_path(entry)
    path = artifacts / relative
    require(path.is_file(), f"compiled artifact missing for {name}")
    if recorded_build is not None:
        require(recorded_build["artifacts"].get(relative) == sha256_file(path),
                f"{name}: the artifact is not the one the build record lists")
    artifact = load_json(path)
    runtime = bytes.fromhex(artifact["deployedBytecode"]["object"].removeprefix("0x"))
    template = entry["runtimeTemplate"]
    require(len(runtime) == template["bytes"] and sha256_bytes(runtime) == template["sha256"],
            f"{name}: the supplied runtime is not the frozen template")
    ranges = v1.merged_ranges(entry["immutableReferences"])
    require(v1.mask(runtime, ranges) == runtime, f"{name}: template carries non-zero bytes inside an immutable range")
    compiled_ranges = v1.merged_ranges([reference for references in
                                        artifact["deployedBytecode"].get("immutableReferences", {}).values()
                                        for reference in references])
    require(compiled_ranges == ranges, f"{name}: compiled immutable ranges differ from the bridge artifact")
    require(artifact.get("methodIdentifiers") == entry["methodIdentifiers"], f"{name}: method identifiers differ")
    functions = {int(value, 16) for value in entry["methodIdentifiers"].values()}
    loads, collisions = {}, []
    for failure in failures:
        value = int(failure["selector"], 16)
        if value in functions:
            collisions.append(failure["name"])
        loads[failure["name"]] = v1.selector_occurrences(runtime, value)
    return {
        "artifact": {"path": relative, "sha256": sha256_file(path)},
        "runtimeSha256": sha256_bytes(runtime),
        "runtimeBytes": len(runtime),
        "build": compiler_binding(artifact, bound, name),
        "typedFailureSelectorLoads": loads,
        "loadCounts": {failure: sum(len(loads[failure][form]) for form in FORMS) for failure in loads},
        "selectorCollisions": collisions,
    }


def endpoint_matrix(runtimes: dict[str, dict[str, Any]], failures: list[dict[str, Any]]) -> dict[str, Any]:
    matrix = {}
    for profile, endpoint in ENDPOINTS.items():
        counts = runtimes[endpoint]["loadCounts"]
        matrix[profile] = {"endpoint": endpoint, "loads": {item["name"]: counts[item["name"]] for item in failures},
                           "missing": sorted(item["name"] for item in failures if counts[item["name"]] < 1)}
    return matrix


def compare_recorded(recorded_path: Path, runtimes: dict[str, dict[str, Any]]) -> dict[str, Any]:
    recorded = load_json(recorded_path)["compiledScan"]
    require(recorded.get("status") == "RECOMPUTED", "the recorded code identity holds no compiled scan")
    differences = []
    for name, scan in runtimes.items():
        entry = recorded["runtimes"].get(name)
        if entry is None:
            differences.append(f"{name}: no recorded scan")
            continue
        if entry["runtimeSha256"] != scan["runtimeSha256"]:
            differences.append(f"{name}: recorded scan belongs to another runtime")
        if entry["typedFailureSelectorLoads"] != scan["typedFailureSelectorLoads"]:
            differences.append(f"{name}: recorded loads differ from the recomputed loads")
    extra = sorted(set(recorded["runtimes"]) - set(runtimes))
    differences += [f"{name}: recorded scan of an unknown runtime" for name in extra]
    return {"recorded": {"path": str(recorded_path.name), "sha256": sha256_file(recorded_path)},
            "equal": not differences, "differences": differences}


def load_build_record(path: Path) -> dict[str, Any]:
    record = load_json(path)
    require(record.get("schema") == BUILD_RECORD_SCHEMA, "frozen build record schema drift")
    require(record.get("exitCode") == 0, "the recorded isolated build did not succeed")
    require(isinstance(record.get("artifacts"), dict) and record["artifacts"], "the build record lists no artifact")
    return {**record, "sha256": sha256_file(path)}


def build(artifacts: Path, mode: str, recorded: Path | None, build_record: dict[str, Any] | None = None) -> dict[str, Any]:
    identity = v1.build(None)
    failures = identity["typedFailures"]
    runtimes = {}
    for profile in PROFILE_RUNTIMES:
        bound = bound_input(profile)
        for entry in v1.binding_artifacts(profile):
            runtimes[entry["contract"]] = scan_runtime(artifacts, entry, failures, bound, build_record)
    if build_record is not None:
        require(sorted(build_record["artifacts"]) == sorted(item["artifact"]["path"] for item in runtimes.values()),
                "the build record lists other artifacts than the profile runtimes")
    matrix = endpoint_matrix(runtimes, failures)
    comparison = compare_recorded(recorded, runtimes) if recorded is not None else None
    criteria = [
        {"id": "every-endpoint-loads-every-typed-failure-selector",
         "holds": all(not row["missing"] for row in matrix.values()),
         "detail": {profile: row["missing"] for profile, row in matrix.items() if row["missing"]}},
        {"id": "no-typed-failure-selector-is-a-function-selector",
         "holds": not any(scan["selectorCollisions"] for scan in runtimes.values()),
         "detail": {name: scan["selectorCollisions"] for name, scan in runtimes.items() if scan["selectorCollisions"]}},
        {"id": "recorded-loads-equal-the-recomputed-loads",
         "holds": comparison is not None and comparison["equal"],
         "detail": "no recorded document supplied" if comparison is None else comparison["differences"]},
    ]
    holds = all(item["holds"] for item in criteria)
    return {
        "schema": SCHEMA,
        "status": ("PASS_TYPED_FAILURE_LOADS_RECOMPUTED" if holds else "LOADS_RECOMPUTED_CRITERIA_OPEN"),
        "mode": mode,
        "artifactsDirectory": "supplied on the command line; paths below are relative to it",
        "buildRecord": None if build_record is None else {"sha256": build_record["sha256"],
                                                          "forgeVersion": build_record.get("forgeVersion")},
        "identity": {
            "runtimeIdentity": {"path": "evidence/trust12/runtime-identity.json", "sha256": sha256_file(v1.RUNTIME_IDENTITY)},
            "profileIdentityRoots": {profile: data["identityRootSha256"] for profile, data in identity["profiles"].items()},
        },
        "typedFailures": [{"name": item["name"], "selector": item["selector"]} for item in failures],
        "endpointLoads": matrix,
        "runtimes": runtimes,
        "recordedComparison": comparison,
        "criteria": criteria,
        "nonclaim": (NONCLAIM + " A load shows that the compiled runtime can produce the selector; it does not show "
                     "on which path a failure is raised or which argument words follow it."),
    }


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--artifacts", type=Path, required=True, help="Foundry out directory of the frozen build")
    parser.add_argument("--build-record", type=Path, help="record that the isolated build wrote")
    parser.add_argument("--mode", choices=("prepare", "closure"), default="prepare")
    parser.add_argument("--compare-recorded", type=Path, help="code identity document whose compiled scan must match")
    parser.add_argument("--output", type=Path, help="write the scan document here")
    parser.add_argument("--report", type=Path, help="write the verdict here, also when the closure check fails")
    args = parser.parse_args(argv)
    require(args.artifacts.is_dir(), "artifact directory missing")
    recorded = args.compare_recorded
    if args.mode == "closure" and recorded is None:
        recorded = RECORDED
    build_record = load_build_record(args.build_record) if args.build_record is not None else None
    document = build(args.artifacts, args.mode, recorded, build_record)
    verdict = {"status": document["status"], "mode": args.mode, "endpointLoads": document["endpointLoads"],
               "criteria": document["criteria"]}
    if args.report is not None:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(dump_json(verdict), encoding="utf-8", newline="\n")
    if args.output is not None:
        require(not args.output.exists(), "scan output already exists")
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(dump_json(document), encoding="utf-8", newline="\n")
    if args.mode == "closure" and document["status"] != "PASS_TYPED_FAILURE_LOADS_RECOMPUTED":
        failed = [item["id"] for item in document["criteria"] if not item["holds"]]
        raise PreparationError("typed failure loads do not close: " + ", ".join(failed))
    print(dump_json(verdict), end="")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except PreparationError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
