#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Check the public record of the length-guard mutants of the malformed probe against the current product.

Metadata mode, which the required gate runs, checks that the record is the reviewed one; that the catalog, the
probe sources, the mutant list, the probe runners and the baseline probe record it names are the current product
files; that each recorded mutation is the declared guard removal applied to the current product source; that
each recorded effect is a catalogued length recipe of the mutated endpoint; and, for the Hook profile, that the
recorded factory pin before the change is the current pin. Saved mode additionally rehashes the private probe
receipts that the record summarizes and compares them with it. Neither mode reruns Foundry.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re

CHECKPOINT_PATH = "evidence/trust12/runtime-link/tail-preparation/malformed-guard-mutants-checkpoint-v1.json"
VERIFIER_PATH = "scripts/trust12/verify_malformed_guard_mutants_v1.py"
CATALOG = "evidence/trust12/runtime-link/tail-preparation/malformed-inputs-v1.json"
MUTANTS = "evidence/trust12/runtime-link/tail-preparation/malformed-probe-mutants-v1.json"
BASELINE = "evidence/trust12/runtime-link/out-of-spec-probes-v1.json"
CAMPAIGN = "scripts/mutation-campaign-v1.json"
FACTORY = "implementation/src/profiles/ERC3643HookFactory.sol"
RUNNERS = ("scripts/trust12/tail-preparation/run_malformed_probe.py",
           "scripts/trust12/tail-preparation/run_malformed_probe_v2.py")
PROBE_DIRECTORY = "scripts/trust12/tail-preparation/foundry"
MUTANT_IDS = ("NATIVE-ACTION-LENGTH", "NATIVE-REVERSAL-LENGTH", "PARTIAL-ACTION-LENGTH",
              "PARTIAL-REVERSAL-LENGTH", "HOOK-ACTION-LENGTH", "HOOK-REVERSAL-LENGTH")
SCOPE = ("Removing one exact calldata length guard, in an isolated copy of the product, turns the probe's requests "
         "longer than canonical form into executions that succeed with logs, committed storage writes and external "
         "accesses on the malformed probe deployment, for every mutated endpoint of the three profiles; each Native "
         "mutant removes the guard of one operation on both of its routes. The unmodified product fails the same "
         "probe requests quietly, as the baseline probe record states. The probe requests are catalogued recipes on "
         "a Foundry deployment, not the registered certificates. For the Hook profile the isolated copy also pins "
         "the mutated adapter creation code in the factory, which otherwise refuses to deploy a changed adapter; the "
         "published factory and its pin are unchanged.")
NONCLAIMS = ("proofOverAllAcceptedExecutions", "boundedWordGuards", "publishedRuntimeChange",
             "registeredCentralClosure", "generalRuntimeLinks", "independentAssurance")
EXPECTED_EVIDENCE_DIGEST = '16c7d291ad6dc28bd49553a13ba28e998019f63a808e15035b7c48890ce6543c'
PUBLIC_KEYS = {"schema", "status", "scope", "product", "mutants", "rehashVerifier", "nonclaims"}
ROW_KEYS = {"id", "status", "profile", "entrypoints", "fault", "mutation", "deviatingLengthRecipes", "effects",
            "forgeElapsedSeconds", "receiptSha256"}
EFFECT_KEYS = {"recipe", "variant", "outcome", "logs", "committedWrites", "externalAccesses"}
REPIN_KEYS = {"file", "beforePin", "afterPin", "reason"}
PIN = re.compile(r"bytes32 public constant ADAPTER_CREATION_HASH = 0x([0-9a-f]{64});")
HEX64 = re.compile(r"[0-9a-f]{64}")
PRIVATE = re.compile(r"(?i)[A-Za-z]:[\\/]|/mnt/|\\\\|\bG[0-9]+\b")


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def text_digest(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


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


def count(value):
    return type(value) is int and value > 0


def identity(product, relative):
    path = (product / relative).resolve()
    require(path.is_file() and path.is_relative_to(product), "Missing product file: " + relative)
    return {"path": relative, "sha256": digest(path)}


def definition(product, declared):
    row = dict(declared)
    if "campaignId" in row:
        matches = [item for item in read_json(product / CAMPAIGN)["definitions"] if item["id"] == row["campaignId"]]
        require(len(matches) == 1, "Campaign mutation differs: " + row["id"])
        for key in ("file", "old", "new", "expectedOccurrences"):
            row[key] = matches[0][key]
    return row


def check_row(row, source, product, catalog, pin):
    identifier = row.get("id")
    require(set(row) == ROW_KEYS | ({"repin"} if source.get("repinAdapterCreationHash") else set()),
            "Mutant record keys differ: " + str(identifier))
    require(row["status"] == "MUTANT_DETECTED" and row["profile"] == source["profile"]
            and row["entrypoints"] == source["entrypoints"] and row["fault"] == source["fault"],
            "Mutant record differs: " + identifier)
    text = (product / source["file"]).read_text(encoding="utf-8")
    require(text.count(source["old"]) == source["expectedOccurrences"]
            and row["mutation"] == {"file": source["file"], "occurrences": source["expectedOccurrences"],
                                    "beforeSha256": text_digest(text),
                                    "afterSha256": text_digest(text.replace(source["old"], source["new"]))},
            "Mutation is not the declared guard removal on the current source: " + identifier)
    deviating = row["deviatingLengthRecipes"]
    require(isinstance(deviating, dict) and list(deviating) == list(source["entrypoints"]),
            "Deviating endpoints differ: " + identifier)
    recipes = []
    for entrypoint, ids in deviating.items():
        require(isinstance(ids, list) and ids and len(set(ids)) == len(ids), "Deviating recipes differ: " + identifier)
        for recipe in ids:
            known = catalog.get(recipe)
            require(known is not None and known["profile"] == row["profile"] and known["entrypoint"] == entrypoint
                    and known["class"] == "length", "Deviating recipe is not a length recipe of the endpoint: "
                    + str(recipe))
            recipes.append(recipe)
    effects = row["effects"]
    require(isinstance(effects, list) and [effect.get("recipe") for effect in effects] == recipes,
            "Effects differ from the deviating recipes: " + identifier)
    for effect in effects:
        require(set(effect) == EFFECT_KEYS and effect["variant"] == catalog[effect["recipe"]]["variant"]
                and effect["outcome"] == "success" and count(effect["logs"]) and count(effect["committedWrites"])
                and count(effect["externalAccesses"]), "Effect differs: " + str(effect.get("recipe")))
    elapsed = row["forgeElapsedSeconds"]
    require(type(elapsed) in (int, float) and elapsed > 0 and isinstance(row["receiptSha256"], str)
            and HEX64.fullmatch(row["receiptSha256"]), "Run record differs: " + identifier)
    if "repin" in row:
        repin = row["repin"]
        require(isinstance(repin, dict) and set(repin) == REPIN_KEYS and repin["file"] == FACTORY
                and repin["beforePin"] == "0x" + pin and isinstance(repin["afterPin"], str)
                and re.fullmatch(r"0x[0-9a-f]{64}", repin["afterPin"]) and repin["afterPin"] != repin["beforePin"],
                "Factory pin record differs: " + identifier)


def public_contract(checkpoint, product):
    require(set(checkpoint) == PUBLIC_KEYS and checkpoint["schema"] == "trust12-malformed-guard-mutants-checkpoint-v1"
            and checkpoint["status"] == "PASS_MALFORMED_GUARD_MUTANTS_DETECTED", "Checkpoint contract differs")
    privacy_boundary(checkpoint)
    require(payload_digest(checkpoint) == EXPECTED_EVIDENCE_DIGEST, "Reviewed evidence digest differs")
    require(checkpoint["scope"] == SCOPE and checkpoint["nonclaims"] == {key: True for key in NONCLAIMS},
            "Scope or bounded nonclaims differ")
    expected = {"catalog": identity(product, CATALOG), "mutantList": identity(product, MUTANTS),
                "baselineProbe": identity(product, BASELINE),
                "runners": [identity(product, path) for path in RUNNERS],
                "probeSources": [identity(product, f"{PROBE_DIRECTORY}/{path.name}")
                                 for path in sorted((product / PROBE_DIRECTORY).glob("*.sol"))]}
    require(checkpoint["product"] == expected, "Probe inputs differ from the current product")
    verifier = checkpoint["rehashVerifier"]
    require(set(verifier) == {"path", "sha256"} and verifier["path"] == VERIFIER_PATH
            and verifier["sha256"] == digest(product / VERIFIER_PATH), "Current verifier differs")
    mutants = checkpoint["mutants"]
    require(isinstance(mutants, list) and [row.get("id") for row in mutants] == list(MUTANT_IDS),
            "Mutant inventory differs")
    declared = {row["id"]: row for row in read_json(product / MUTANTS)["mutants"]}
    require(set(declared) == set(MUTANT_IDS), "Declared mutant list differs")
    catalog = {recipe["id"]: recipe for recipe in read_json(product / CATALOG)["recipes"]}
    pins = PIN.findall((product / FACTORY).read_text(encoding="utf-8"))
    require(len(pins) == 1, "Factory adapter pin not found exactly once")
    for row in mutants:
        check_row(row, definition(product, declared[row["id"]]), product, catalog, pins[0])
    return {row["id"]: row for row in mutants}


def saved_receipts(checkpoint, rows, receipts):
    probes = {Path(item["path"]).name: item["sha256"] for item in checkpoint["product"]["probeSources"]}
    runners = {item["path"]: item["sha256"] for item in checkpoint["product"]["runners"]}
    for identifier, row in rows.items():
        receipt = receipts / identifier / "receipt.json"
        require(receipt.is_file() and digest(receipt) == row["receiptSha256"], "Saved receipt differs: " + identifier)
        data = read_json(receipt)
        mutation = {key: value for key, value in data["mutation"].items() if key != "repin"}
        affected = {item["id"]: item for item in data["affectedRows"]}
        require(data["status"] == "MUTANT_DETECTED" and data["deviatingLengthRecipes"] == row["deviatingLengthRecipes"]
                and data["catalogSha256"] == checkpoint["product"]["catalog"]["sha256"]
                and data["mutantListSha256"] == checkpoint["product"]["mutantList"]["sha256"]
                and data["probeSources"] == probes and data["runners"] == runners and mutation == row["mutation"]
                and data["mutation"].get("repin") == row.get("repin")
                and data["run"]["elapsedSeconds"] == row["forgeElapsedSeconds"]
                and all(affected[effect["recipe"]]["verdict"] == "DEVIATES"
                        and affected[effect["recipe"]]["observed"]["outcome"] == effect["outcome"]
                        and affected[effect["recipe"]]["observed"]["logs"] == effect["logs"]
                        and affected[effect["recipe"]]["observed"]["committedWrites"] == effect["committedWrites"]
                        and affected[effect["recipe"]]["observed"]["externalAccesses"] == effect["externalAccesses"]
                        for effect in row["effects"]),
                "Saved receipt content differs: " + identifier)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--product-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--metadata-only", action="store_true")
    parser.add_argument("--receipts", type=Path, help="directory holding <MUTANT>/receipt.json")
    args = parser.parse_args()
    product = args.product_root.resolve()
    checkpoint = read_json(product / CHECKPOINT_PATH)
    rows = public_contract(checkpoint, product)
    if args.metadata_only:
        require(args.receipts is None, "Metadata mode reads no receipts")
        report = {"status": "PASS_PUBLIC_METADATA_ONLY", "mutants": len(rows), "foundryRerun": False}
    else:
        require(args.receipts is not None, "Saved mode requires the receipts directory")
        saved_receipts(checkpoint, rows, args.receipts)
        report = {"status": "PASS_SAVED_GUARD_MUTANT_RECEIPTS_REHASHED", "mutants": len(rows), "foundryRerun": False}
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, OSError, ValueError, KeyError, TypeError, AttributeError) as error:
        raise SystemExit(f"FAIL: {error}")
