#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Check the public record of the TRUST 1.2 certificate registry and, with the private registry, recompute it.

Metadata mode, which the required gate runs, reads tracked files only. It checks that the record is the reviewed
one; that the product files it names are the current files; that its certificate rows are exactly the twenty-seven
cells times two outcomes plus the requests outside canonical form of the current malformed catalog; that the
coverage counts follow from the rows and equal the reviewed counts; and that the runtime identity and the retained
assumptions follow from the current code identity document and the current registry tool. Saved mode additionally
rehashes the private registry and locator file named through a private index, rebuilds the registry in closure mode
from the private evidence with the current tool, requires the rebuilt registry to equal the stored one byte for
byte, and requires the public record to follow from it. Neither mode reruns a prover or a kernel session.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib
import inspect
import json
from pathlib import Path, PurePosixPath
import re
import sys

CHECKPOINT_PATH = "evidence/trust12/runtime-link/tail-preparation/certificate-registry-checkpoint-v1.json"
VERIFIER_PATH = "scripts/trust12/verify_certificate_registry_v1.py"
TOOL_DIRECTORY = "scripts/trust12/tail-preparation"
IDENTITY_PATHS = {
    "registryTool": "scripts/trust12/tail-preparation/certificate_registry_v2.py",
    "worldReader": "scripts/trust12/tail-preparation/kore_accounts.py",
    "registryHelpers": "scripts/trust12/tail-preparation/certificate_registry.py",
    "preparationCommon": "scripts/trust12/tail-preparation/tail_common.py",
    "registrySchema": "evidence/trust12/runtime-link/tail-preparation/certificate-registry-schema-v2.json",
    "codeIdentity": "evidence/trust12/runtime-link/tail-preparation/code-identity-v1.json",
    "malformedCatalog": "evidence/trust12/runtime-link/malformed/kevm-kore-checkpoint-v1.json",
    "exportReasonSource": "evidence/trust12/runtime-link/second-freeze-rejection-checkpoint-v1.json",
}
MODULES = {"certificate_registry_v2": "registryTool", "kore_accounts": "worldReader",
           "certificate_registry": "registryHelpers", "tail_common": "preparationCommon"}
ARTIFACT_KINDS = {"certificate-registry": "registry", "certificate-locators": "locators"}
COMMAND = ("python3 " + VERIFIER_PATH + " --product-root <product-root> --evidence <evidence-root> "
           "--artifact-index <private-artifact-index.json>")
PROFILES = ("Native", "Partial", "Hook")
OPERATIONS = ("FREEZE", "SEIZE", "CONFISCATE", "LIQUIDATE", "RESTRICT", "RECOVER", "UNFREEZE", "RELEASE", "UNRESTRICT")
CATALOG_PROFILES = {"native": "Native", "partial": "Partial", "hook": "Hook"}
CHECK_IDS = ("certificate-keys-unique", "certificates-distinct", "certificate-records-consistent",
             "cells-agree-with-ledger-and-kernels", "malformed-registered-as-catalogued", "executed-code-identity",
             "recorded-worlds-consumed")
SCOPE = ("The certificate registry of the TRUST 1.2 runtime link names one applied and one not-applied checked "
         "certificate for each of the twenty-seven profile and operation cells, and one checked certificate for each "
         "catalogued request outside canonical form of the three profiles (Native 16, Partial 13, Hook 13), 96 "
         "certificates in all. Every cell pair agrees with the closed status of its cell in the runtime-link obligation "
         "ledger and with the passing kernel results that the ledger cites for the cell, and the requests outside "
         "canonical form of each profile are exactly the catalogued ones. In every world recorded before the call of "
         "a certificate, the account that the recorded frame executes is the endpoint that the certificate's own "
         "records name and has the code of the endpoint template outside the immutable ranges, and the world holds "
         "exactly one account for each runtime of the executed runtime set of the profile.")
IDENTITY_BOUNDARY = ("The executed runtime set is the Native token; the Partial adapter and governor; and the Hook adapter, "
                     "governor and compliance module. A match means the same length and equal bytes outside the merged "
                     "immutable ranges, so immutable values are not compared with any deployment. The Hook factory appears "
                     "in no recorded world: every recorded world is a state after the unit was created, and the "
                     "certificate harness creates each unit by running the adapter creation code directly, so the factory, "
                     "which in a product deployment hash-checks and runs that creation code, is neither deployed nor "
                     "called. The factory is identified only by its template in the code identity; which instance is "
                     "deployed and whether it was created through the factory remain the assumption A-DEPLOYMENT. The "
                     "other accounts of a recorded world, the calling test harness and dependency contracts such as the "
                     "upstream ERC-3643 token and the identity registry and compliance contracts that are not profile "
                     "runtimes, are not identified by code, and the behavior of the dependencies remains the assumption "
                     "A-EXTERNAL.")
CONSUMER_BOUNDARY = ("Each recorded world is named, with the same SHA-256, by the records that consumed it, and every "
                     "certificate has a world that the input binding of a kernel session names: 108 of the 109 worlds, "
                     "across 25 kernel sessions. The remaining world, the entry world of the second FREEZE that the "
                     "Native endpoint rejects, is named only by its KORE export record: the kernel record of that call "
                     "takes the post-call world of the first FREEZE as the world before the call, and the export is a "
                     "snapshot inside the call, as the public second FREEZE rejection record states. That world yields "
                     "the same executed code as the consumed world of the same certificate. The registry compares the "
                     "hashes that these records hold; it does not replay the kernel sessions and does not check that a "
                     "consuming session precedes the kernel runs that the ledger cites.")
ACCEPTANCE_BOUNDARY = ("Acceptance of a certificate is read, not reproved. For 92 certificates it is the verdict that their "
                       "KEVM batch run recorded: passed, not failed, not admitted, not a circularity, with no pending and "
                       "no failing node, and the proof and graph hashes of the batch agree with the certificate's boundary "
                       "selection record. For the Native FREEZE pair it is the passing compound certificate record. The two "
                       "Native LIQUIDATE certificates have no batch verdict, so the registry rehashes their stored proof "
                       "and graph files against the proof and graph hashes of their extraction records and evaluates the "
                       "stored graph with the APRProof status rule: both pass, with the target as the only leaf and no "
                       "pending or failing node, and neither proof is admitted or a circularity.")
REPRODUCTION_BOUNDARY = ("Metadata mode reads tracked files only and checks this record against the current product files. "
                         "Saved mode rehashes the private registry and locator file, rebuilds the registry in closure mode "
                         "from the private evidence with the current tool, and requires the rebuilt registry to equal the "
                         "stored one byte for byte and this record to follow from it. Neither mode reruns a prover or a "
                         "kernel session. The registry is the finite data of the acceptance partition, not the partition "
                         "theorem, which a kernel run over the whole registry must still prove, and it states no completion "
                         "of the twenty-seven-cell gate, the registered-scope central closure, any general runtime link, "
                         "the independent Assurance or TRUST 1.2.")
COVERAGE = {
    "declaredCells": 27,
    "boundCells": 27,
    "certificates": {"Native": 34, "Partial": 31, "Hook": 31},
    "requestsOutsideCanonicalForm": {"Native": 16, "Partial": 13, "Hook": 13},
    "executedCodeMatches": 96,
    "recordedWorlds": 109,
    "worldsNamedByKernelStageInputs": 108,
    "worldsNamedOnlyByKoreExports": 1,
    "kernelSessionsNamingWorlds": 25,
    "acceptanceMethods": {"RECORDED_FIELDS": 94, "STORED_PROOF_GRAPH": 2},
    "checks": {identifier: "PASS" for identifier in CHECK_IDS},
}
COMPOUND_CERTIFICATES = ("Native/FREEZE/applied", "Native/FREEZE/not-applied")
STORED_GRAPH_CERTIFICATES = ("Native/LIQUIDATE/applied", "Native/LIQUIDATE/not-applied")
EXPORT_ONLY_CERTIFICATES = ("Native/FREEZE/not-applied",)
NONCLAIM_KEYS = ("partitionTheorem", "twentySevenCellGateInstantiation", "registeredCentralClosure",
                 "generalRuntimeLinks", "independentAssurance", "deploymentIdentity", "dependencyCode", "proverRerun",
                 "kernelSessionReplay", "fullTrustCompletion", "releaseOrDeployment")
EXPECTED_EVIDENCE_DIGEST = 'e7ae3fe2b0d23426c8cd22bbfa04687b4c49b54d4862e4430c469a9b71d93a4d'
PUBLIC_KEYS = {"schema", "status", "scope", "identityBoundary", "consumerBoundary", "acceptanceBoundary",
               "reproductionBoundary", "coverage", "runtimeIdentity", "retainedAssumptions", "productIdentity",
               "artifacts", "rehashVerifier", "nonclaims", "certificates"}
ROW_KEYS = {"key", "form", "acceptance", "worlds", "kernelStageInputs", "exportOnlyWorlds", "executedCode",
            "executedCodeSha256"}
SCHEMA = "trust12-certificate-registry-checkpoint-v1"
STATUS = "PASS_CERTIFICATE_REGISTRY_COVERAGE_AND_EXECUTED_CODE"
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


def same_json(left, right):
    return canonical(left) == canonical(right)


def payload_digest(checkpoint):
    return hashlib.sha256(canonical({key: value for key, value in checkpoint.items() if key != "rehashVerifier"})).hexdigest()


def privacy_boundary(checkpoint):
    encoded = json.dumps(checkpoint, ensure_ascii=False)
    require(encoded.isascii() and not PRIVATE.search(encoded), "Private or non-English metadata")


def file_identity(product, relative):
    path = (product / relative).resolve()
    require(path.is_file() and path.is_relative_to(product), "Missing product file: " + relative)
    return {"path": relative, "bytes": path.stat().st_size, "sha256": digest(path)}


def load_tool(product):
    """The registry tool of the product tree, with its readers, refusing modules loaded from anywhere else."""
    directory = (product / TOOL_DIRECTORY).resolve()
    sys.dont_write_bytecode = True
    if str(directory) not in sys.path:
        sys.path.insert(0, str(directory))
    tool = importlib.import_module("certificate_registry_v2")
    for name, key in MODULES.items():
        module = sys.modules.get(name)
        require(module is not None and Path(inspect.getfile(module)).resolve() == (product / IDENTITY_PATHS[key]).resolve(),
                "Imported registry module differs from the product file: " + name)
    return tool


def expected_keys(product):
    catalog = read_json(product / IDENTITY_PATHS["malformedCatalog"])
    slugs = {CATALOG_PROFILES[item["profile"]]: item["slugs"] for item in catalog["profiles"]}
    require(set(slugs) == set(PROFILES), "Malformed catalog profiles differ")
    keys = [f"{profile}/{operation}/{outcome}" for profile in PROFILES for operation in OPERATIONS
            for outcome in ("applied", "not-applied")]
    keys += [f"{profile}/MALFORMED/{slug}" for profile in PROFILES for slug in slugs[profile]]
    require(len(keys) == len(set(keys)), "Expected certificate keys repeat")
    return sorted(keys)


def expected_runtime_identity(product, tool):
    identity = read_json(product / IDENTITY_PATHS["codeIdentity"])
    result = {}
    for profile in PROFILES:
        record = identity["profiles"][profile]
        deployment_only = tool.DEPLOYMENT_ONLY_RUNTIMES.get(profile, {})
        result[profile] = {
            "profileIndex": record["profileIndex"], "endpoint": record["endpoint"],
            "codeIdentityRootSha256": record["identityRootSha256"],
            "executed": {item["contract"]: {"templateSha256": item["runtimeTemplate"]["sha256"],
                                            "bytes": item["runtimeTemplate"]["bytes"]}
                         for item in record["runtimes"] if item["contract"] not in deployment_only},
            "deploymentOnly": {item["contract"]: {"templateSha256": item["runtimeTemplate"]["sha256"],
                                                  "bytes": item["runtimeTemplate"]["bytes"],
                                                  "accountsInRecordedWorlds": 0,
                                                  "reason": deployment_only[item["contract"]]}
                               for item in record["runtimes"] if item["contract"] in deployment_only},
        }
    return result


def public_summary(registry):
    """The public part of the record that follows from a registry."""
    rows = sorted(({"key": item["key"], "form": item["form"], "acceptance": item["acceptance"]["method"],
                    "worlds": len(item["execution"]["preWorlds"]),
                    "kernelStageInputs": item["execution"]["kernelStageInputs"],
                    "exportOnlyWorlds": sum(1 for world in item["execution"]["preWorlds"] if "exportOnly" in world),
                    "executedCode": item["execution"]["status"],
                    "executedCodeSha256": item["execution"]["executedCodeSha256"]}
                   for item in registry["certificates"]), key=lambda row: row["key"])
    partition = registry["partition"]
    sessions = {entry["session"] for item in registry["certificates"] for world in item["execution"]["preWorlds"]
                for entry in world["consumers"]
                if entry["kind"] == "KERNEL_STAGE_INPUT" and entry["agrees"] and entry["kindAgrees"]}
    coverage = {
        "declaredCells": partition["declaredCells"], "boundCells": partition["boundCells"],
        "certificates": {profile: registry["profiles"][profile]["certificates"] for profile in PROFILES},
        "requestsOutsideCanonicalForm": {item["profile"]: len(item["certificates"]) for item in registry["malformed"]},
        "executedCodeMatches": partition["executedCodeMatches"], "recordedWorlds": partition["recordedWorlds"],
        "worldsNamedByKernelStageInputs": partition["worldsNamedByKernelStageInputs"],
        "worldsNamedOnlyByKoreExports": partition["worldsNamedOnlyByKoreExports"],
        "kernelSessionsNamingWorlds": len(sessions),
        "acceptanceMethods": partition["acceptanceMethods"],
        "checks": {item["id"]: item["status"] for item in registry["checks"]},
    }
    runtime = {profile: {"profileIndex": summary["profileIndex"], "endpoint": summary["endpoint"],
                         "codeIdentityRootSha256": summary["codeIdentityRootSha256"],
                         "executed": {name: {"templateSha256": item["sha256"], "bytes": item["bytes"]}
                                      for name, item in summary["executedRuntimes"].items()},
                         "deploymentOnly": {name: {"templateSha256": item["sha256"], "bytes": item["bytes"],
                                                   "accountsInRecordedWorlds": item["accountsInRecordedWorlds"],
                                                   "reason": item["reason"]}
                                            for name, item in summary["deploymentOnlyRuntimes"].items()}}
               for profile, summary in registry["profiles"].items()}
    return {"coverage": coverage, "certificates": rows, "runtimeIdentity": runtime,
            "retainedAssumptions": registry["retainedAssumptions"]}


def build_checkpoint(summary, product, artifacts):
    """The record before its verifier identity is added; the writer pins its digest in this verifier."""
    return {"schema": SCHEMA, "status": STATUS, "scope": SCOPE, "identityBoundary": IDENTITY_BOUNDARY,
            "consumerBoundary": CONSUMER_BOUNDARY, "acceptanceBoundary": ACCEPTANCE_BOUNDARY,
            "reproductionBoundary": REPRODUCTION_BOUNDARY, "coverage": summary["coverage"],
            "runtimeIdentity": summary["runtimeIdentity"], "retainedAssumptions": summary["retainedAssumptions"],
            "productIdentity": {key: file_identity(product, path) for key, path in IDENTITY_PATHS.items()},
            "artifacts": artifacts, "rehashVerifier": None,
            "nonclaims": {key: True for key in NONCLAIM_KEYS}, "certificates": summary["certificates"]}


def check_rows(rows, product):
    require(isinstance(rows, list) and all(isinstance(row, dict) and set(row) == ROW_KEYS for row in rows),
            "Certificate row keys differ")
    require([row["key"] for row in rows] == expected_keys(product), "Certificate rows differ from the cells and the catalog")
    for row in rows:
        key = row["key"]
        require(row["form"] == ("COMPOUND_BOUNDARY" if key in COMPOUND_CERTIFICATES else "APR_PROOF")
                and row["acceptance"] == ("STORED_PROOF_GRAPH" if key in STORED_GRAPH_CERTIFICATES else "RECORDED_FIELDS"),
                "Certificate form or acceptance method differs: " + key)
        require(type(row["worlds"]) is int and row["worlds"] >= 1 and type(row["kernelStageInputs"]) is int
                and row["kernelStageInputs"] >= 1 and type(row["exportOnlyWorlds"]) is int
                and row["exportOnlyWorlds"] == (1 if key in EXPORT_ONLY_CERTIFICATES else 0)
                and row["exportOnlyWorlds"] < row["worlds"], "Certificate world binding differs: " + key)
        require(row["executedCode"] == "MATCH" and isinstance(row["executedCodeSha256"], str)
                and HEX64.fullmatch(row["executedCodeSha256"]) is not None, "Certificate executed code differs: " + key)
    worlds = sum(row["worlds"] for row in rows)
    exported = sum(row["exportOnlyWorlds"] for row in rows)
    return {
        "certificates": {profile: sum(1 for row in rows if row["key"].startswith(profile + "/")) for profile in PROFILES},
        "requestsOutsideCanonicalForm": {profile: sum(1 for row in rows if row["key"].startswith(profile + "/MALFORMED/"))
                                         for profile in PROFILES},
        "executedCodeMatches": sum(1 for row in rows if row["executedCode"] == "MATCH"),
        "recordedWorlds": worlds, "worldsNamedByKernelStageInputs": worlds - exported,
        "worldsNamedOnlyByKoreExports": exported,
        "acceptanceMethods": {method: sum(1 for row in rows if row["acceptance"] == method)
                              for method in ("RECORDED_FIELDS", "STORED_PROOF_GRAPH")},
    }


def public_contract(checkpoint, product):
    require(set(checkpoint) == PUBLIC_KEYS and checkpoint["schema"] == SCHEMA and checkpoint["status"] == STATUS,
            "Checkpoint contract differs")
    privacy_boundary(checkpoint)
    require(payload_digest(checkpoint) == EXPECTED_EVIDENCE_DIGEST, "Reviewed evidence digest differs")
    require(checkpoint["scope"] == SCOPE and checkpoint["identityBoundary"] == IDENTITY_BOUNDARY
            and checkpoint["consumerBoundary"] == CONSUMER_BOUNDARY and checkpoint["acceptanceBoundary"] == ACCEPTANCE_BOUNDARY
            and checkpoint["reproductionBoundary"] == REPRODUCTION_BOUNDARY, "Public scope or boundary differs")
    require(checkpoint["nonclaims"] == {key: True for key in NONCLAIM_KEYS}, "All bounded nonclaims required")
    require(same_json(checkpoint["coverage"], COVERAGE), "Coverage differs from the reviewed counts")
    derived = check_rows(checkpoint["certificates"], product)
    require(all(same_json(checkpoint["coverage"][key], value) for key, value in derived.items()),
            "Coverage does not follow from the certificate rows")
    require(checkpoint["productIdentity"] == {key: file_identity(product, path) for key, path in IDENTITY_PATHS.items()},
            "Product identity differs from the current files")
    verifier = checkpoint["rehashVerifier"]
    require(isinstance(verifier, dict) and set(verifier) == {"path", "bytes", "sha256", "command"}
            and verifier["command"] == COMMAND
            and {key: verifier[key] for key in ("path", "bytes", "sha256")} == file_identity(product, VERIFIER_PATH),
            "Current verifier differs")
    artifacts = checkpoint["artifacts"]
    require(isinstance(artifacts, list) and [row.get("id") for row in artifacts] == list(ARTIFACT_KINDS)
            and all(isinstance(row, dict) and set(row) == {"id", "kind", "bytes", "sha256"}
                    and row["kind"] == ARTIFACT_KINDS[row["id"]] and type(row["bytes"]) is int and row["bytes"] > 0
                    and isinstance(row["sha256"], str) and HEX64.fullmatch(row["sha256"]) is not None for row in artifacts),
            "Artifact inventory differs")
    tool = load_tool(product)
    require(same_json(checkpoint["runtimeIdentity"], expected_runtime_identity(product, tool)),
            "Runtime identity differs from the current code identity and registry tool")
    require(checkpoint["retainedAssumptions"] == tool.RETAINED_ASSUMPTIONS, "Retained assumptions differ from the registry tool")
    return tool


def private_file(base, relative, label):
    require(isinstance(relative, str) and relative and not PurePosixPath(relative).is_absolute()
            and ".." not in PurePosixPath(relative).parts and ":" not in relative, "Private index path differs: " + label)
    path = (base / relative).resolve()
    require(path.is_relative_to(base) and path.is_file(), "Private artifact missing: " + label)
    return path


def verify_checkpoint(checkpoint, index_path, evidence, product):
    product, evidence, index_path = product.resolve(), evidence.resolve(), index_path.resolve()
    tool = public_contract(checkpoint, product)
    verifier_file = (product / VERIFIER_PATH).resolve()
    require(Path(__file__).resolve() == verifier_file, "Executing verifier identity differs")
    index = read_json(index_path)
    require(set(index) == set(ARTIFACT_KINDS), "Private index roles differ")
    base = index_path.parent
    files = {}
    for row in checkpoint["artifacts"]:
        path = private_file(base, index[row["id"]], row["id"])
        require(path.stat().st_size == row["bytes"] and digest(path) == row["sha256"], "Private artifact drift: " + row["id"])
        files[row["id"]] = path
    stored_bytes = files["certificate-registry"].read_bytes()
    stored = json.loads(stored_bytes.decode("utf-8"))
    require(stored.get("mode") == "closure" and stored.get("status") == "REGISTRY_COMPLETE_CANDIDATE",
            "Stored registry is not a closure-mode registry")
    locators = read_json(files["certificate-locators"])
    rebuilt = tool.build(evidence, locators, "closure", tool.locator_identity(files["certificate-locators"]), product)
    require(tool.dump_json(rebuilt).encode("utf-8") == stored_bytes, "Registry recomputation differs from the stored registry")
    summary = public_summary(rebuilt)
    require(all(same_json(checkpoint[key], value) for key, value in summary.items()),
            "Public record differs from the recomputed registry")
    identity = checkpoint["productIdentity"]
    require(rebuilt["inputs"]["codeIdentity"]["sha256"] == identity["codeIdentity"]["sha256"]
            and rebuilt["inputs"]["malformedCatalog"]["sha256"] == identity["malformedCatalog"]["sha256"],
            "Registry inputs differ from the product identity")
    reasons = [world["exportOnly"]["source"] for item in rebuilt["certificates"]
               for world in item["execution"]["preWorlds"] if "exportOnly" in world]
    require(reasons and all(source["path"] == identity["exportReasonSource"]["path"]
                            and source["sha256"] == identity["exportReasonSource"]["sha256"] for source in reasons),
            "Export reason source differs from the product identity")
    for row in checkpoint["artifacts"]:
        require(digest(files[row["id"]]) == row["sha256"], "Private artifact changed while checked: " + row["id"])
    for key, path in IDENTITY_PATHS.items():
        require(digest(product / path) == identity[key]["sha256"], "Product identity changed while checked: " + key)
    require(digest(verifier_file) == checkpoint["rehashVerifier"]["sha256"], "Verifier changed while checked")
    return {"schema": "trust12-certificate-registry-rehash-v1", "status": "PASS_CERTIFICATE_REGISTRY_RECOMPUTED",
            "certificates": len(rebuilt["certificates"]), "boundCells": rebuilt["partition"]["boundCells"],
            "recordedWorlds": rebuilt["partition"]["recordedWorlds"], "proverRerun": False,
            "kernelSessionReplay": False, "registeredCentralClosureDischarged": False, "nonclaim": REPRODUCTION_BOUNDARY}


def metadata_only(checkpoint, product):
    public_contract(checkpoint, product.resolve())
    return {"status": "PASS_PUBLIC_METADATA_ONLY", "savedArtifactsVerified": False, "registryRecomputed": False,
            "nonclaims": sorted(NONCLAIM_KEYS)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--product-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--checkpoint", type=Path)
    parser.add_argument("--metadata-only", action="store_true")
    parser.add_argument("--evidence", type=Path)
    parser.add_argument("--artifact-index", type=Path)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    sys.dont_write_bytecode = True
    product = args.product_root.resolve()
    checkpoint_path = (args.checkpoint or product / CHECKPOINT_PATH).resolve()
    require(checkpoint_path == (product / CHECKPOINT_PATH).resolve(), "Unexpected checkpoint location")
    checkpoint = read_json(checkpoint_path)
    if args.metadata_only:
        require(args.evidence is None and args.artifact_index is None, "Metadata mode reads no private file")
        report = metadata_only(checkpoint, product)
    else:
        require(args.evidence is not None and args.artifact_index is not None, "Saved mode requires the evidence root and the index")
        report = verify_checkpoint(checkpoint, args.artifact_index, args.evidence, product)
    if args.out:
        with args.out.open("x", encoding="utf-8", newline="\n") as handle:
            handle.write(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, OSError, ValueError, KeyError, TypeError, AttributeError, ImportError) as error:
        raise SystemExit(f"FAIL: {error}")
