#!/usr/bin/env python3
"""Run the bounded word guard probe on an isolated copy of the product, unmodified or with one declared mutant.

The closure acceptance of each malformed condition asks that disabling the exact length guard or a bounded word
check turns a witness outside canonical form into an execution that is accepted or that emits a log, makes an
external call or changes state. The length guards are measured by the guard mutants of the malformed probe. This
runner measures the bounded word checks. It copies the product sources and both probe directories into an empty
isolated directory, applies the declared mutant there (none for the baseline), pins a changed Hook adapter in the
isolated factory, runs the word guard probe and the malformed probe with Foundry and records:

* every word guard witness (width, kind width and kind witnesses) and kind control of the three profiles, with the
  same recorder as the malformed probe;
* every catalogued recipe of the malformed probe, of which the dirty word recipes of the mutated kind are reported;
* the verdict: in the baseline every witness fails quietly and every control is accepted; under a mutant that is
  declared detectable every witness of the mutated kind deviates on every profile and every other witness still
  fails quietly; under a mutant that is declared equivalent every witness of the mutated kind still fails quietly
  with the declared typed failure.

It measures; it does not close a malformed branch. Run it on Linux or WSL with the pinned Foundry and the pinned
upstream token artifacts.

Usage:
  run_word_guard_probe.py --product DIR --trex-artifacts DIR --workdir DIR --output DIR (--baseline | --mutant ID)
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

import word_guard_mutation
from run_malformed_probe import (BASE_EVENT, CATALOG, OUTCOMES, PROBE_DIRECTORY, RESULT_EVENT, decode_results, evaluate,
                                 prepare, run_forge, topic)
from run_malformed_probe_v2 import repin_adapter
from tail_common import NONCLAIM, PreparationError, dump_json, load_json, require, sha256_file

MUTANTS = Path("evidence/trust12/runtime-link/tail-preparation/malformed-word-guard-mutants-v1.json")
WORD_PROBE_DIRECTORY = "scripts/trust12/tail-preparation/word-guard-probe"
RUNNERS = ("scripts/trust12/tail-preparation/run_malformed_probe.py",
           "scripts/trust12/tail-preparation/run_malformed_probe_v2.py",
           "scripts/trust12/tail-preparation/run_word_guard_probe.py",
           "scripts/trust12/tail-preparation/word_guard_mutation.py")
PROFILE_SUITES = {"Native": "NativeWordGuardProbe", "Partial": "PartialWordGuardProbe", "Hook": "HookWordGuardProbe"}
ENTRYPOINTS = {"Native": (1, 2, 3, 4), "Partial": (1, 2), "Hook": (1, 2)}
SHAPE = {1: "action", 2: "reversal", 3: "action", 4: "reversal"}
ENTRYPOINT_NAMES = {1: "executeRegulatoryAction", 2: "executeRegulatoryReversal", 3: "executeERC7943Action",
                    4: "executeERC7943Reversal"}
KIND_WORD = {"action": 2, "reversal": 3}
WITNESS_BASE, KIND_CONTROL_WORD, KIND_WIDTH_INDEX_OFFSET = 1000, 99, 50
GUARD_CLASSES = {"address": "dirty-address-word", "uint64": "dirty-uint64-word", "uint48": "dirty-uint48-word",
                 "ActionKind": "dirty-enum-word", "ReversalKind": "dirty-enum-word",
                 "ActionKindWord": "dirty-enum-word", "ReversalKindWord": "dirty-enum-word"}
ENUM_SHAPE = {"ActionKind": "action", "ReversalKind": "reversal"}
KIND_WIDTH_GUARD = {enum: name for name, enum in word_guard_mutation.KIND_WORD_GUARDS.items()}


def witness_table(catalog: dict[str, Any]) -> list[dict[str, Any]]:
    """Every witness and control the word guard probe records, derived from the catalog struct layout."""
    rows = []
    for profile, entrypoints in ENTRYPOINTS.items():
        for entrypoint in entrypoints:
            shape = catalog["shapes"][SHAPE[entrypoint]]
            for item in shape["words"]:
                guard = item["guard"]
                if guard is None:
                    continue
                kind = guard["kind"] if guard["kind"] != "enum" else guard["enum"]
                rows.append({"profile": profile, "entrypoint": entrypoint, "shape": SHAPE[entrypoint],
                             "index": WITNESS_BASE + 100 * entrypoint + int(item["word"]), "word": int(item["word"]),
                             "field": item["field"], "guard": kind, "class": GUARD_CLASSES[kind],
                             "role": "kind-witness" if guard["kind"] == "enum" else "width-witness"})
                if guard["kind"] == "enum":
                    width = KIND_WIDTH_GUARD[guard["enum"]]
                    rows.append({"profile": profile, "entrypoint": entrypoint, "shape": SHAPE[entrypoint],
                                 "index": WITNESS_BASE + 100 * entrypoint + KIND_WIDTH_INDEX_OFFSET + int(item["word"]),
                                 "word": int(item["word"]), "field": item["field"], "guard": width,
                                 "class": GUARD_CLASSES[width], "role": "kind-width-witness"})
            if SHAPE[entrypoint] == "action":
                rows.append({"profile": profile, "entrypoint": entrypoint, "shape": "action",
                             "index": WITNESS_BASE + 100 * entrypoint + KIND_CONTROL_WORD, "word": None, "field": None,
                             "guard": None, "class": "well-formed-control", "role": "kind-control"})
    return sorted(rows, key=lambda row: (row["profile"], row["index"]))


def mutant_definition(product: Path, mutants: Path, identifier: str) -> dict[str, Any]:
    rows = [row for row in word_guard_mutation.validate_mutant_list(product, load_json(mutants)) if row["id"] == identifier]
    require(len(rows) == 1, f"unknown mutant: {identifier}")
    return rows[0]


def touches_hook_adapter(mutant: dict[str, Any] | None) -> bool:
    """A kind mutant changes the shared types and so the Hook adapter; a width mutant changes it when it names Hook."""
    if mutant is None:
        return False
    return mutant["kind"] == "widen-enum" or "Hook" in mutant.get("profiles", [])


def run_word_probe(workdir: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    environment = dict(os.environ, FOUNDRY_TEST=WORD_PROBE_DIRECTORY, FOUNDRY_DISABLE_CODE_SIZE_LIMIT="true")
    command = ["forge", "test", "-vv", "--json", "--match-path", f"{WORD_PROBE_DIRECTORY}/*WordGuardProbe.t.sol",
               "--match-test", "testWordGuardProbe"]
    started = time.time()
    completed = subprocess.run(command, cwd=workdir, env=environment, capture_output=True, text=True)
    record = {"command": " ".join(command), "environment": {"FOUNDRY_TEST": WORD_PROBE_DIRECTORY,
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


def decode_witnesses(report: dict[str, Any]) -> tuple[dict[tuple[str, int], dict[str, Any]], list[dict[str, Any]], dict[str, str]]:
    result_topic, base_topic = topic(RESULT_EVENT), topic(BASE_EVENT)
    suites = {suite: profile for profile, suite in PROFILE_SUITES.items()}
    results, bases, statuses = {}, [], {}
    for suite, content in report.items():
        name = suite.split(":")[-1]
        require(name in suites, f"unexpected test suite: {name}")
        profile = suites[name]
        for test, outcome in content["test_results"].items():
            statuses[f"{name}.{test}"] = outcome["status"]
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
                    require((profile, index) not in results, f"witness recorded twice: {profile}/{index}")
                    results[(profile, index)] = {
                        "outcome": OUTCOMES.get(value[0], "unknown"),
                        "selector": "0x" + words[32:36].hex() if value[0] in (2, 3) else None,
                        "secondWord": value[2], "returnBytes": value[3], "externalAccesses": value[4],
                        "logs": value[5], "committedWrites": value[6]}
                elif topics[0].lower() == base_topic:
                    bases.append({"profile": profile, "entrypoint": int.from_bytes(words[0:32], "big"),
                                  "accepted": bool(int.from_bytes(words[32:64], "big"))})
    return results, bases, statuses


def expectation(row: dict[str, Any], mutant: dict[str, Any] | None) -> str:
    """CONFORMS, DEVIATES, EQUIVALENT or CONTROL for one witness under the declared mutant."""
    if row["role"] == "kind-control":
        return "CONTROL"
    if mutant is None:
        return "CONFORMS"
    if mutant["kind"] == "truncate-width":
        mutated = row["guard"] == mutant["guard"] and row["profile"] in mutant["profiles"]
    else:
        mutated = row["guard"] == mutant["enum"]
    if not mutated:
        return "CONFORMS"
    return "DEVIATES" if mutant["expectedVerdict"] == "DETECTED" else "EQUIVALENT"


def judge(row: dict[str, Any], observed: dict[str, Any] | None, expected: str, mutant: dict[str, Any] | None) -> bool:
    verdict = evaluate({"class": row["class"]}, observed)
    if observed is None:
        return False
    if expected == "CONTROL":
        return verdict["verdict"] == "CONTROL_DETECTED"
    if expected == "DEVIATES":
        return verdict["verdict"] == "DEVIATES"
    if expected == "EQUIVALENT":
        failure = mutant["equivalentFailure"]
        return (verdict["verdict"] == "CONFORMS" and verdict["typedFailure"] == failure["error"]
                and verdict["reason"] == failure["reason"])
    return verdict["verdict"] == "CONFORMS"


def catalog_rows(catalog: dict[str, Any], report: dict[str, Any], mutant: dict[str, Any] | None) -> dict[str, Any]:
    results, bases, statuses = decode_results(report)
    rows, summary = [], {}
    for index, recipe in enumerate(catalog["recipes"]):
        observed = results.get(index)
        verdict = evaluate(recipe, observed)
        key = f"{recipe['profile']}/{recipe['class']}/{verdict['verdict']}"
        summary[key] = summary.get(key, 0) + 1
        rows.append({"index": index, "id": recipe["id"], "profile": recipe["profile"], "entrypoint": recipe["entrypoint"],
                     "class": recipe["class"], "variant": recipe["variant"], "word": recipe["word"],
                     "observed": observed, **verdict})
    harness_ok = (all(status == "Success" for status in statuses.values()) and len(statuses) == 3
                  and all(base["accepted"] for base in bases) and len(results) == len(catalog["recipes"])
                  and all(row["verdict"] == "CONTROL_DETECTED" for row in rows if row["class"] == "well-formed-control")
                  and not any(row["verdict"] == "NOT_OBSERVED" for row in rows))
    if mutant is None:
        family = []
    elif mutant["kind"] == "truncate-width":
        words = {int(item["word"]) for shape in catalog["shapes"].values() for item in shape["words"]
                 if word_guard_mutation.guard_matches(item["guard"], mutant["guard"])}
        family = [row for row in rows if row["class"] == GUARD_CLASSES[mutant["guard"]] and row["word"] in words
                  and row["profile"] in mutant["profiles"]]
    else:
        names = {name for number, name in ENTRYPOINT_NAMES.items() if SHAPE[number] == ENUM_SHAPE[mutant["enum"]]}
        family = [row for row in rows if row["class"] == "dirty-enum-word" and row["entrypoint"] in names]
    return {"harnessOk": harness_ok, "suites": statuses, "bases": bases, "summary": dict(sorted(summary.items())),
            "familyRecipes": [{"id": row["id"], "verdict": row["verdict"], "outcome": (row["observed"] or {}).get("outcome"),
                               "typedFailure": row.get("typedFailure"), "reason": row.get("reason")} for row in family],
            "rows": rows}


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--product", type=Path, required=True)
    parser.add_argument("--trex-artifacts", type=Path, required=True)
    parser.add_argument("--workdir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    selection = parser.add_mutually_exclusive_group(required=True)
    selection.add_argument("--baseline", action="store_true")
    selection.add_argument("--mutant")
    parser.add_argument("--mutants", type=Path, help="mutant list; defaults to the product copy")
    parser.add_argument("--keep-workdir", action="store_true")
    args = parser.parse_args(argv)
    product = args.product.resolve()
    catalog = load_json(product / CATALOG)
    mutants = (args.mutants or product / MUTANTS).resolve()
    mutant = None if args.baseline else mutant_definition(product, mutants, args.mutant)
    require(mutant is None or bool(mutant.get("repinAdapterCreationHash")) == touches_hook_adapter(mutant),
            "the declared factory pin step differs from the files the mutant changes")
    require(not args.output.exists(), "probe output already exists")
    prepare(product, args.trex_artifacts, args.workdir)
    try:
        shutil.copytree(product / WORD_PROBE_DIRECTORY, args.workdir / WORD_PROBE_DIRECTORY)
        mutation = word_guard_mutation.apply(args.workdir, mutant, catalog) if mutant else {"files": []}
        if touches_hook_adapter(mutant):
            mutation["repin"] = repin_adapter(args.workdir)
        word_report, word_run = run_word_probe(args.workdir)
        catalog_report, catalog_run = run_forge(args.workdir)
    finally:
        if not args.keep_workdir:
            shutil.rmtree(args.workdir, ignore_errors=True)
    results, bases, statuses = decode_witnesses(word_report)
    table = witness_table(catalog)
    rows, correct = [], []
    for row in table:
        observed = results.get((row["profile"], row["index"]))
        expected = expectation(row, mutant)
        verdict = evaluate({"class": row["class"]}, observed)
        ok = judge(row, observed, expected, mutant)
        correct.append(ok)
        rows.append({**row, "expected": expected, "observed": observed, **verdict, "asExpected": ok})
    expected_bases = sorted((profile, entrypoint) for profile, entrypoints in ENTRYPOINTS.items() for entrypoint in entrypoints)
    harness_ok = (all(status == "Success" for status in statuses.values()) and len(statuses) == len(PROFILE_SUITES)
                  and sorted((base["profile"], base["entrypoint"]) for base in bases) == expected_bases
                  and all(base["accepted"] for base in bases)
                  and set(results) == {(row["profile"], row["index"]) for row in table})
    catalog_record = catalog_rows(catalog, catalog_report, mutant)
    harness_ok = harness_ok and catalog_record["harnessOk"]
    if not harness_ok:
        status = "PROBE_HARNESS_FAILED"
    elif not all(correct):
        status = "BASELINE_DIFFERS" if mutant is None else "MUTANT_DIFFERS_FROM_DECLARATION"
    elif mutant is None:
        status = "BASELINE_RECORDED"
    else:
        status = "MUTANT_DETECTED" if mutant["expectedVerdict"] == "DETECTED" else "MUTANT_EQUIVALENT_CONFIRMED"
    receipt = {
        "schema": "trust12-tail-preparation-word-guard-probe-receipt-v1",
        "status": status,
        "mutant": None if mutant is None else {key: mutant[key] for key in mutant if key != "rationale"},
        "mutation": mutation,
        "catalogSha256": sha256_file(product / CATALOG),
        "mutantListSha256": sha256_file(mutants),
        "probeSources": {path.name: sha256_file(path) for path in sorted((product / PROBE_DIRECTORY).glob("*.sol"))},
        "wordProbeSources": {path.name: sha256_file(path)
                             for path in sorted((product / WORD_PROBE_DIRECTORY).glob("*.sol"))},
        "runners": {path: sha256_file(product / path) for path in RUNNERS},
        "runs": {"wordGuardProbe": word_run, "malformedProbe": catalog_run},
        "suites": statuses,
        "bases": bases,
        "witnesses": rows,
        "catalog": {key: value for key, value in catalog_record.items() if key != "rows"},
        "catalogRows": catalog_record["rows"],
        "nonclaim": NONCLAIM + " The witnesses are concrete requests on one deployment per profile; a mutant record "
                               "shows what removing one kind of bounded word check changes on that deployment, not a "
                               "proof over all accepted executions.",
    }
    args.output.mkdir(parents=True, exist_ok=False)
    (args.output / "receipt.json").write_text(dump_json(receipt), encoding="utf-8", newline="\n")
    print(json.dumps({"status": status, "mutant": None if mutant is None else mutant["id"],
                      "witnessesAsExpected": sum(correct), "witnesses": len(correct),
                      "suites": statuses}, indent=2))
    return 0 if status in ("BASELINE_RECORDED", "MUTANT_DETECTED", "MUTANT_EQUIVALENT_CONFIRMED") else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except (PreparationError, word_guard_mutation.MutationError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
