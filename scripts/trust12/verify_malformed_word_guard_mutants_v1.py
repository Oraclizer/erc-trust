#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Check the public record of the bounded word guard mutants of the typed entrypoints against the current product.

Metadata mode, which the required gate runs, checks that the record is the reviewed one; that the catalog, the mutant
list, the probe runners, the mutation tool and the probe sources it names are the current product files; that each
recorded mutation is the rewrite that the current mutation tool computes from the current sources for the declared
mutant; that the recorded witnesses are exactly the witnesses of the mutated kind that the current probe defines; and
that each recorded outcome is the declared one: in the baseline every witness fails quietly and every kind control
is accepted, a detected mutant turns every witness of its kind into an execution that is accepted or that emits a
log, makes an external call or changes state, and an equivalent mutant leaves every witness of its kind failing
quietly with the declared typed failure. Saved mode additionally rehashes the private probe receipts that the record
summarizes and compares them with it. Neither mode reruns Foundry.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib
import inspect
import json
from pathlib import Path
import re
import sys

CHECKPOINT_PATH = "evidence/trust12/runtime-link/tail-preparation/malformed-word-guard-mutants-checkpoint-v1.json"
VERIFIER_PATH = "scripts/trust12/verify_malformed_word_guard_mutants_v1.py"
TOOL_DIRECTORY = "scripts/trust12/tail-preparation"
CATALOG = "evidence/trust12/runtime-link/tail-preparation/malformed-inputs-v1.json"
MUTANTS = "evidence/trust12/runtime-link/tail-preparation/malformed-word-guard-mutants-v1.json"
RUNNERS = ("scripts/trust12/tail-preparation/run_malformed_probe.py",
           "scripts/trust12/tail-preparation/run_malformed_probe_v2.py",
           "scripts/trust12/tail-preparation/run_word_guard_probe.py",
           "scripts/trust12/tail-preparation/word_guard_mutation.py")
PROBE_DIRECTORIES = ("scripts/trust12/tail-preparation/foundry", "scripts/trust12/tail-preparation/word-guard-probe")
FACTORY = "implementation/src/profiles/ERC3643HookFactory.sol"
MUTANT_IDS = ("ADDRESS-WIDTH", "UINT64-WIDTH", "UINT48-WIDTH", "ACTION-KIND-BOUND", "REVERSAL-KIND-BOUND",
              "ACTION-KIND-WIDTH", "REVERSAL-KIND-WIDTH")
BASELINE_ID = "BASELINE"
PROFILES = ("Native", "Partial", "Hook")
SCHEMA = "trust12-malformed-word-guard-mutants-checkpoint-v1"
STATUS = "PASS_MALFORMED_WORD_GUARD_MUTANTS_AS_DECLARED"
SCOPE = ("Each bounded word guard mutant weakens one kind of bounded word check of the typed entrypoints of the three "
         "profiles in an isolated copy of the product, and the word guard probe runs the same witnesses on the "
         "unmodified copy and on each mutant. In the unmodified copy every witness fails without an external call, a "
         "log or a committed storage write, and every kind control is accepted; in the same unmodified copy the "
         "malformed probe reruns every catalogued recipe on the frozen sources, every recipe outside canonical form "
         "fails quietly and every well-formed control is accepted with effects. Reading the address, uint64, uint48, "
         "action kind or reversal kind words truncated to their width instead of rejecting dirty high bits, or "
         "accepting every action kind word below 256, turns every witness of that kind on every profile into an "
         "execution that is accepted or that emits a log, makes an external call or changes state; the record lists "
         "the observed effects of each one. Accepting every reversal kind word below 256 leaves every reversal kind "
         "witness failing quietly with the typed reversal pairing failure, so the range part of that check is not the "
         "only check that rejects an out-of-range reversal kind. Under each mutant every witness of another kind "
         "still fails quietly.")
DECODER_BOUNDARY = ("The product sources hold no statement that checks a bounded word. The compiler checks every read of "
                    "an address, uint64, uint48 or enum field of a request struct in calldata, including the copy of the "
                    "action request to memory, and a value that does not fit ends the call with empty revert data. A "
                    "width mutant replaces every such read of the fields of one width, in every function that takes the "
                    "request in calldata, by a read of the raw word truncated to the declared width, as a decoder that "
                    "masks instead of rejecting would; a kind width mutant does the same for the kind word with a width "
                    "of eight bits and keeps the checked conversion of the truncated value to the kind, which rejects a "
                    "value outside the declared kinds; a kind bound mutant declares 256 members for the kind, so that "
                    "only the eight-bit width of the kind word is checked. The other fields keep their compiler checks. "
                    "For the "
                    "Hook profile the isolated copy also pins the mutated adapter creation code in the factory, which "
                    "otherwise refuses to deploy a changed adapter; the published factory and its pin are unchanged.")
WITNESS_BOUNDARY = ("A width witness is an accepted base request of the probe deployment in which one address, uint64 or "
                    "uint48 word, or the kind word, also carries the bit just above its declared width, eight bits for a "
                    "kind, with the identifier recomputed over the changed words. A kind witness is a transfer-shaped accepted base request whose kind word holds "
                    "the first value outside the declared range, and a kind control is the same base request unmodified. "
                    "The witnesses are concrete requests on the deployments of the malformed probe, one per profile, "
                    "recorded with its recorder; they are neither the catalogued recipes nor the registered certificates.")
CATALOG_BOUNDARY = ("The catalogued dirty word recipes of the malformed probe set the whole word to a value whose low bits "
                    "are zero, and the record lists which of them deviate under each mutant. A recipe that a later kernel "
                    "rule rejects once its word is truncated, for example a zero subject or an epoch that does not match, "
                    "still fails quietly, so those recipes alone do not show which checks matter.")
EQUIVALENCE_BOUNDARY = ("For the reversal kind word the record shows, on the probe deployments, that removing the range "
                        "part of its check leaves a rule that rejects every observed reversal kind outside the declared "
                        "range; the "
                        "mutant list names the source lines of that rule, which the current sources contain. It is not "
                        "a proof over all requests and all states.")
NONCLAIMS = ("proofOverAllAcceptedExecutions", "registeredCertificates", "publishedRuntimeChange",
             "malformedBranchClosure", "registeredCentralClosure", "generalRuntimeLinks", "independentAssurance")
EXPECTED_EVIDENCE_DIGEST = 'a4feda0ddab331e462104e16585842a37ece3163ad264315b624066f5e296d55'
PUBLIC_KEYS = {"schema", "status", "scope", "decoderBoundary", "witnessBoundary", "catalogBoundary",
               "equivalenceBoundary", "product", "baseline", "mutants", "rehashVerifier", "nonclaims"}
BASELINE_KEYS = {"status", "witnesses", "quietFailures", "outcomes", "controls", "catalog", "forgeElapsedSeconds",
                 "receiptSha256"}
ROW_KEYS = {"id", "status", "kind", "target", "profiles", "fault", "expectedVerdict", "mutation", "repin",
            "familyWitnesses", "otherWitnesses", "controls", "catalogFamilyRecipes", "forgeElapsedSeconds",
            "receiptSha256"}
WITNESS_KEYS = {"profile", "entrypoint", "word", "field", "outcome", "typedFailure", "reason", "logs",
                "committedWrites", "externalAccesses"}
REPIN_KEYS = {"file", "beforePin", "afterPin", "reason"}
PIN = re.compile(r"bytes32 public constant ADAPTER_CREATION_HASH = 0x([0-9a-f]{64});")
HEX64 = re.compile(r"[0-9a-f]{64}")
PRIVATE = re.compile(r"(?i)[A-Za-z]:[\\/]|/mnt/|/h[o]me/|\\\\|(?<![A-Za-z0-9])(?:G|M|FV|RL)[0-9]+(?![0-9])")


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read_json(path):
    value = json.loads(Path(path).read_text(encoding="utf-8"))
    require(isinstance(value, dict), "JSON object required")
    return value


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True, allow_nan=False).encode("utf-8")


def payload_digest(checkpoint):
    return hashlib.sha256(canonical({key: value for key, value in checkpoint.items() if key != "rehashVerifier"})).hexdigest()


def privacy_boundary(checkpoint):
    encoded = json.dumps(checkpoint, ensure_ascii=False)
    require(encoded.isascii() and not PRIVATE.search(encoded), "Private or non-English metadata")


def identity(product, relative):
    path = (product / relative).resolve()
    require(path.is_file() and path.is_relative_to(product), "Missing product file: " + relative)
    return {"path": relative, "sha256": digest(path)}


def expected_product(product):
    return {"catalog": identity(product, CATALOG), "mutantList": identity(product, MUTANTS),
            "runners": [identity(product, path) for path in RUNNERS],
            "probeSources": [identity(product, f"{directory}/{path.name}") for directory in PROBE_DIRECTORIES
                             for path in sorted((product / directory).glob("*.sol"))]}


def load_tools(product):
    """The mutation tool and the probe runner of the product tree, refusing modules loaded from anywhere else."""
    directory = (product / TOOL_DIRECTORY).resolve()
    sys.dont_write_bytecode = True
    if str(directory) not in sys.path:
        sys.path.insert(0, str(directory))
    mutation = importlib.import_module("word_guard_mutation")
    runner = importlib.import_module("run_word_guard_probe")
    for module, relative in ((mutation, RUNNERS[3]), (runner, RUNNERS[2])):
        require(Path(inspect.getfile(module)).resolve() == (product / relative).resolve(),
                "Imported probe module differs from the product file: " + relative)
    return mutation, runner


def count(value):
    return type(value) is int and value >= 0


def expected_catalog_baseline(catalog):
    """The malformed probe outcome of the unmodified copy that the baseline must record: every catalogued recipe
    outside canonical form fails quietly and every well-formed control is accepted with effects."""
    counts = {}
    for recipe in catalog["recipes"]:
        verdict = "CONTROL_DETECTED" if recipe["class"] == "well-formed-control" else "CONFORMS"
        key = f'{recipe["profile"]}/{recipe["class"]}/{verdict}'
        counts[key] = counts.get(key, 0) + 1
    return {"recipes": len(catalog["recipes"]), "summary": dict(sorted(counts.items()))}


def witness_record(row):
    observed = row["observed"] or {}
    return {"profile": row["profile"], "entrypoint": row["entrypoint"], "word": row["word"], "field": row["field"],
            "outcome": observed.get("outcome"), "typedFailure": row.get("typedFailure"), "reason": row.get("reason"),
            "logs": observed.get("logs"), "committedWrites": observed.get("committedWrites"),
            "externalAccesses": observed.get("externalAccesses")}


def check_witness(item, expected):
    require(isinstance(item, dict) and set(item) == WITNESS_KEYS and all(count(item[key]) for key in
                                                                         ("logs", "committedWrites", "externalAccesses")),
            "Witness record differs")
    quiet = item["outcome"] != "success" and item["logs"] == item["committedWrites"] == item["externalAccesses"] == 0
    if expected == "DEVIATES":
        require(not quiet, "A witness of a detected mutant fails quietly")
    elif expected == "EQUIVALENT":
        require(quiet, "A witness of an equivalent mutant does not fail quietly")
    else:
        require(quiet, "A witness fails noisily")


def public_contract(checkpoint, product):
    require(set(checkpoint) == PUBLIC_KEYS and checkpoint["schema"] == SCHEMA and checkpoint["status"] == STATUS,
            "Checkpoint contract differs")
    privacy_boundary(checkpoint)
    require(payload_digest(checkpoint) == EXPECTED_EVIDENCE_DIGEST, "Reviewed evidence digest differs")
    require(checkpoint["scope"] == SCOPE and checkpoint["decoderBoundary"] == DECODER_BOUNDARY
            and checkpoint["witnessBoundary"] == WITNESS_BOUNDARY and checkpoint["catalogBoundary"] == CATALOG_BOUNDARY
            and checkpoint["equivalenceBoundary"] == EQUIVALENCE_BOUNDARY, "Scope or boundary differs")
    require(checkpoint["nonclaims"] == {key: True for key in NONCLAIMS}, "All bounded nonclaims required")
    require(checkpoint["product"] == expected_product(product), "Probe inputs differ from the current product")
    verifier = checkpoint["rehashVerifier"]
    require(isinstance(verifier, dict) and set(verifier) == {"path", "sha256"} and verifier["path"] == VERIFIER_PATH
            and verifier["sha256"] == digest(product / VERIFIER_PATH), "Current verifier differs")
    mutation, runner = load_tools(product)
    catalog = read_json(product / CATALOG)
    declared = {row["id"]: row for row in mutation.validate_mutant_list(product, read_json(product / MUTANTS))}
    require(tuple(declared) == MUTANT_IDS, "Declared mutant list differs")
    table = runner.witness_table(catalog)
    witnesses = [row for row in table if row["role"] != "kind-control"]
    controls = [row for row in table if row["role"] == "kind-control"]
    baseline = checkpoint["baseline"]
    require(isinstance(baseline, dict) and set(baseline) == BASELINE_KEYS and baseline["status"] == "BASELINE_RECORDED"
            and baseline["witnesses"] == {profile: sum(1 for row in witnesses if row["profile"] == profile)
                                          for profile in PROFILES}
            and baseline["quietFailures"] == len(witnesses)
            and isinstance(baseline["outcomes"], dict) and sum(baseline["outcomes"].values()) == len(witnesses)
            and "success" not in baseline["outcomes"]
            and baseline["controls"] == {"count": len(controls), "accepted": len(controls)},
            "Baseline record differs")
    require(baseline["catalog"] == expected_catalog_baseline(catalog),
            "Baseline catalog record differs: every catalogued recipe outside canonical form must fail quietly and "
            "every well-formed control must be detected")
    pins = PIN.findall((product / FACTORY).read_text(encoding="utf-8"))
    require(len(pins) == 1, "Factory adapter pin not found exactly once")
    rows = checkpoint["mutants"]
    require(isinstance(rows, list) and [row.get("id") for row in rows] == list(MUTANT_IDS), "Mutant inventory differs")
    catalog_ids = {recipe["id"]: recipe for recipe in catalog["recipes"]}
    for row in rows:
        source = declared[row["id"]]
        require(set(row) == ROW_KEYS, "Mutant record keys differ: " + row["id"])
        target = source["guard"] if source["kind"] == "truncate-width" else source["enum"]
        status = "MUTANT_DETECTED" if source["expectedVerdict"] == "DETECTED" else "MUTANT_EQUIVALENT_CONFIRMED"
        require(row["status"] == status and row["kind"] == source["kind"] and row["target"] == target
                and row["profiles"] == source.get("profiles", list(PROFILES)) and row["fault"] == source["fault"]
                and row["expectedVerdict"] == source["expectedVerdict"], "Mutant record differs: " + row["id"])
        require(row["mutation"] == mutation.expected_rewrite(product, source, catalog),
                "Mutation is not the declared rewrite of the current sources: " + row["id"])
        repin = row["repin"]
        require(isinstance(repin, dict) and set(repin) == REPIN_KEYS and repin["file"] == FACTORY
                and repin["beforePin"] == "0x" + pins[0] and re.fullmatch(r"0x[0-9a-f]{64}", repin["afterPin"])
                and repin["afterPin"] != repin["beforePin"]
                and repin["reason"] == "pin the mutated adapter creation code in the isolated copy only",
                "Factory pin record differs: " + row["id"])
        family = [item for item in witnesses if runner.expectation(item, source) in ("DEVIATES", "EQUIVALENT")]
        expected = "DEVIATES" if source["expectedVerdict"] == "DETECTED" else "EQUIVALENT"
        recorded = row["familyWitnesses"]
        require(isinstance(recorded, list)
                and [(item.get("profile"), item.get("entrypoint"), item.get("word"), item.get("field")) for item in recorded]
                == [(item["profile"], item["entrypoint"], item["word"], item["field"]) for item in family],
                "Recorded witnesses differ from the witnesses of the mutated kind: " + row["id"])
        for item in recorded:
            check_witness(item, expected)
            if expected == "EQUIVALENT":
                require(item["typedFailure"] == source["equivalentFailure"]["error"]
                        and item["reason"] == source["equivalentFailure"]["reason"],
                        "Equivalent witness failure differs: " + row["id"])
        require(row["otherWitnesses"] == {"count": len(witnesses) - len(family), "quiet": len(witnesses) - len(family)},
                "Other witnesses are not all quiet: " + row["id"])
        require(row["controls"] == {"count": len(controls), "accepted": len(controls)}, "Controls differ: " + row["id"])
        recipes = row["catalogFamilyRecipes"]
        require(isinstance(recipes, dict) and set(recipes) == {"deviating", "quiet"}
                and all(isinstance(recipes[key], list) for key in recipes)
                and not set(recipes["deviating"]) & set(recipes["quiet"]), "Catalog recipe record differs: " + row["id"])
        for identifier in recipes["deviating"] + recipes["quiet"]:
            recipe = catalog_ids.get(identifier)
            require(recipe is not None and recipe["class"] == runner.GUARD_CLASSES[target],
                    "Catalog recipe is not a dirty word recipe of the mutated kind: " + str(identifier))
        elapsed = row["forgeElapsedSeconds"]
        require(isinstance(elapsed, dict) and set(elapsed) == {"wordGuardProbe", "malformedProbe"}
                and all(type(value) in (int, float) and value > 0 for value in elapsed.values())
                and isinstance(row["receiptSha256"], str) and HEX64.fullmatch(row["receiptSha256"]),
                "Run record differs: " + row["id"])
    elapsed = baseline["forgeElapsedSeconds"]
    require(isinstance(elapsed, dict) and set(elapsed) == {"wordGuardProbe", "malformedProbe"}
            and all(type(value) in (int, float) and value > 0 for value in elapsed.values())
            and HEX64.fullmatch(str(baseline["receiptSha256"])), "Baseline run record differs")
    return {row["id"]: row for row in rows}


def summary_from_receipt(receipt, runner, source):
    """The public part of a mutant row or of the baseline that follows from one receipt."""
    rows = receipt["witnesses"]
    witnesses = [row for row in rows if row["role"] != "kind-control"]
    controls = [row for row in rows if row["role"] == "kind-control"]
    accepted = sum(1 for row in controls if row["verdict"] == "CONTROL_DETECTED")
    elapsed = {"wordGuardProbe": receipt["runs"]["wordGuardProbe"]["elapsedSeconds"],
               "malformedProbe": receipt["runs"]["malformedProbe"]["elapsedSeconds"]}
    if source is None:
        outcomes = {}
        for row in witnesses:
            outcome = (row["observed"] or {}).get("outcome")
            outcomes[outcome] = outcomes.get(outcome, 0) + 1
        summary = receipt["catalog"]["summary"]
        return {"status": receipt["status"], "witnesses": {profile: sum(1 for row in witnesses if row["profile"] == profile)
                                                           for profile in PROFILES},
                "quietFailures": sum(1 for row in witnesses if row["verdict"] == "CONFORMS"),
                "outcomes": dict(sorted(outcomes.items())), "controls": {"count": len(controls), "accepted": accepted},
                "catalog": {"recipes": sum(summary.values()), "summary": dict(sorted(summary.items()))},
                "forgeElapsedSeconds": elapsed}
    family = [row for row in witnesses if row["expected"] in ("DEVIATES", "EQUIVALENT")]
    others = [row for row in witnesses if row["expected"] == "CONFORMS"]
    recipes = receipt["catalog"]["familyRecipes"]
    return {"status": receipt["status"], "kind": source["kind"],
            "target": source["guard"] if source["kind"] == "truncate-width" else source["enum"],
            "profiles": source.get("profiles", list(PROFILES)), "fault": source["fault"],
            "expectedVerdict": source["expectedVerdict"],
            "mutation": {"files": receipt["mutation"]["files"]}, "repin": receipt["mutation"]["repin"],
            "familyWitnesses": [witness_record(row) for row in family],
            "otherWitnesses": {"count": len(others), "quiet": sum(1 for row in others if row["verdict"] == "CONFORMS")},
            "controls": {"count": len(controls), "accepted": accepted},
            "catalogFamilyRecipes": {"deviating": [item["id"] for item in recipes if item["verdict"] == "DEVIATES"],
                                     "quiet": [item["id"] for item in recipes if item["verdict"] == "CONFORMS"]},
            "forgeElapsedSeconds": elapsed}


def saved_receipts(checkpoint, rows, receipts, product):
    _, runner = load_tools(product)
    declared = {row["id"]: row for row in read_json(product / MUTANTS)["mutants"]}
    expected_sources = {item["path"].rsplit("/", 1)[1]: item["sha256"] for item in checkpoint["product"]["probeSources"]
                        if item["path"].startswith(PROBE_DIRECTORIES[0] + "/")}
    expected_word_sources = {item["path"].rsplit("/", 1)[1]: item["sha256"] for item in checkpoint["product"]["probeSources"]
                             if item["path"].startswith(PROBE_DIRECTORIES[1] + "/")}
    runners = {item["path"]: item["sha256"] for item in checkpoint["product"]["runners"]}
    for identifier in (BASELINE_ID,) + MUTANT_IDS:
        receipt_path = receipts / identifier / "receipt.json"
        recorded = checkpoint["baseline"] if identifier == BASELINE_ID else rows[identifier]
        require(receipt_path.is_file() and digest(receipt_path) == recorded["receiptSha256"],
                "Saved receipt differs: " + identifier)
        receipt = read_json(receipt_path)
        require(receipt["catalogSha256"] == checkpoint["product"]["catalog"]["sha256"]
                and receipt["mutantListSha256"] == checkpoint["product"]["mutantList"]["sha256"]
                and receipt["probeSources"] == expected_sources and receipt["wordProbeSources"] == expected_word_sources
                and receipt["runners"] == runners, "Saved receipt inputs differ: " + identifier)
        source = None if identifier == BASELINE_ID else declared[identifier]
        summary = summary_from_receipt(receipt, runner, source)
        public = {key: value for key, value in recorded.items() if key != "receiptSha256" and key != "id"}
        require(canonical(summary) == canonical(public), "Saved receipt content differs: " + identifier)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--product-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--metadata-only", action="store_true")
    parser.add_argument("--receipts", type=Path, help="directory holding BASELINE/receipt.json and <MUTANT>/receipt.json")
    args = parser.parse_args()
    product = args.product_root.resolve()
    checkpoint = read_json(product / CHECKPOINT_PATH)
    rows = public_contract(checkpoint, product)
    if args.metadata_only:
        require(args.receipts is None, "Metadata mode reads no receipts")
        report = {"status": "PASS_PUBLIC_METADATA_ONLY", "mutants": len(rows), "foundryRerun": False}
    else:
        require(args.receipts is not None, "Saved mode requires the receipts directory")
        saved_receipts(checkpoint, rows, args.receipts.resolve(), product)
        report = {"status": "PASS_SAVED_WORD_GUARD_MUTANT_RECEIPTS_REHASHED", "mutants": len(rows), "foundryRerun": False}
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, OSError, ValueError, KeyError, TypeError, AttributeError) as error:
        raise SystemExit(f"FAIL: {error}")
