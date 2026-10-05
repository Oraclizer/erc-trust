#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Check the registered central closure record of TRUST 1.2 and its positive, negative and compiled-consumer records.

The required gate runs this verifier with --metadata-only. The closure has no private artifacts, so metadata mode is
its only mode. It reads tracked files only and checks that the record is the reviewed one; that every cited record is
a current, passing checkpoint record whose verifier the required gate runs; that every acceptance criterion is quoted
from the current conditions list and every field named for it still holds the recorded value; that every recorded
finding is resolved with cited evidence; that every assumption that the policy, the central ledger or a cited record
retains is named; that the final inputs are the current runtimes, source inventory, ABI, formal root and conditions;
that the positive, negative and compiled-consumer records bind this record and name evidence for every condition; and
that the ledger row cites all four records. It runs no prover, compiler, kernel session or Foundry execution.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

CLOSURE_PATH = "evidence/trust12/registered-central-closure/closure-v1.json"
ROLE_PATHS = {"positive": "evidence/trust12/registered-central-closure/positive-v1.json",
              "negative": "evidence/trust12/registered-central-closure/negative-v1.json",
              "compiledConsumer": "evidence/trust12/registered-central-closure/compiled-consumer-v1.json"}
VERIFIER_PATH = "scripts/trust12/verify_registered_closure_v1.py"
LEDGER_PATH = "evidence/trust12/obligation-ledger.json"
CENTRAL_LEDGER_PATH = "evidence/end-to-end-refinement/obligation-ledger-v3.json"
CONDITIONS_PATH = "evidence/trust12/runtime-link/tail-preparation/tail-obligations-v1.json"
CONDITIONS_SHA256 = "3e6524fc20a951dab02e916f41980b8281a84338ec94b2dcf14f5a0e8a73a087"
REQUIRED_GATE_PATH = "scripts/verify-trust12-required.mjs"
REQUIRED_CONTROLS_PATH = "scripts/test-trust12-required.mjs"
RUNTIME_IDENTITY_PATH = "evidence/trust12/runtime-identity.json"
ABI_PATH = "spec/generated/kernel-v2-abi.json"
FORMAL_RESULTS_PATH = "evidence/isabelle-results-v3.json"
DECISION_PATH = "spec/decisions/13-trust12-completion-scope.md"
DISPOSITIONS_PATH = "evidence/trust12/runtime-link/tail-preparation/reflection-dispositions-v1.json"
ROW_ID = "REGISTERED-CENTRAL-CLOSURE"
ROW_STATUS = "PASS_REGISTERED_CENTRAL_CLOSURE"
ASSURANCE_ID = "independent-assurance"
GENERAL_IDS = ("RESEARCH-RUNTIME-LINK-NATIVE", "RESEARCH-RUNTIME-LINK-PARTIAL", "RESEARCH-RUNTIME-LINK-HOOK")
# The contracts of the three profile runtimes, in the profile order of the policy check.
PROFILE_CONTRACTS = ("TrustToken", "ERC3643TrustAdapter", "ProfileGovernor", "ERC3643HookAdapter",
                     "ERC3643HookGovernor", "ERC3643HookCompliance", "ERC3643HookFactory")
# Assumptions every registered closure names, as the policy check pins them.
BASE_ASSUMPTIONS = ("A-RUNTIME-LINK", "A-RUNTIME-LINK-SPEC", "A-COMPILER", "A-KECCAK", "A-DEPLOYMENT", "A-EXTERNAL",
                    "A-EVM", "A-LAYOUT", "A-MUTATION", "A-KEVM-TOOLCHAIN")
SCHEMA = "trust12-registered-central-closure-v1"
ROLE_SCHEMA = "trust12-registered-closure-evidence-v1"
STATUS = "PASS"
REPORT_STATUS = "PASS_REGISTERED_CLOSURE_CONSISTENT"
SCOPE = ("This record closes the registered-scope central closure of TRUST 1.2. For each condition of the reviewed "
         "conditions list other than the independent assurance, it cites passing checkpoint records that the required "
         "gate verifies and, for each acceptance criterion of that condition, names the fields of those records that "
         "show the criterion. It resolves the four recorded findings with cited evidence and names every assumption "
         "that remains. The registered executions are the registered certificates of the twenty-seven profile and "
         "operation cells and the registered requests outside canonical form of the Native, Partial and Hook profiles "
         "on their exact compiled runtimes.")
EXECUTION_BOUNDARY = ("The registered executions are not every declared execution. For every other execution the "
                      "runtime_link and runtime_link_spec locale assumptions remain undischarged, and the three "
                      "general runtime links stay deferred research. A probe, a mutant or a scan that a cited record "
                      "reports runs on the deployment or build that the record names, and a mutant copy is never a "
                      "run of the frozen build.")
EVIDENCE_BOUNDARY = ("Each cited record keeps its own scope and non-claims, and this record does not extend them. A "
                     "criterion is shown by the fields named for it; where those fields show it only under a stated "
                     "limit, the limit is recorded with the criterion. A clause of a condition beyond its acceptance "
                     "criteria is shown by the fields named for that clause or is described in the note of the "
                     "condition. This record does not replay kernel sessions, prover runs or Foundry executions; the "
                     "saved-mode verifier of each cited record and the fresh independent assurance do.")
ASSUMPTION_BOUNDARY = ("The retained assumptions are the open assumptions of the central end-to-end ledger, the "
                       "toolchain assumption under which K, KEVM and Kontrol with its backend are trusted to produce "
                       "the registered certificates, and every assumption that a cited record retains. This record "
                       "neither proves nor tests a retained assumption.")
REPRODUCTION_BOUNDARY = ("The public verifier reads tracked files only. It checks that this record is the reviewed "
                         "one; that every cited record is current, passes and has a verifier that the required gate "
                         "runs; that every acceptance criterion is quoted from the current conditions list and every "
                         "named field still holds its recorded value; that every recorded finding is resolved with "
                         "cited evidence; that the reviewed dispositions carry no open item of the state and receipt "
                         "crosswalk to a later gate; that every retained assumption of the policy, the central ledger "
                         "and the cited records is named; that the final inputs are the current runtimes, sources, ABI, "
                         "formal root and conditions; and that the positive, negative and compiled-consumer records and "
                         "the ledger row bind this record. It runs no prover, compiler, kernel session or Foundry "
                         "execution.")
ASSURANCE = {"condition": ASSURANCE_ID, "status": "OPEN",
             "detail": ("A fresh assessor who took no part in Building reproduces this closure on inputs frozen by a "
                        "final input seal. Until a PASS verdict is recorded next to that seal, TRUST 1.2 completion is "
                        "not claimed.")}
NONCLAIM_KEYS = ("independentAssurance", "trust12Completion", "generalRuntimeLinks", "unregisteredExecutions",
                 "fullRefinement", "kernelReplay", "compilerCorrectness", "deploymentIdentity", "releaseOrDeployment")
ROLE_STATEMENTS = {
    "positive": ("For every condition that the closure discharges, the cited records show the premise and its "
                 "consumer executing on the final target: the registered certificates and the probes run the exact "
                 "compiled runtimes, and the kernel results and scans are about the final sources."),
    "negative": ("For every condition that the closure discharges, a cited control removes, weakens or substitutes "
                 "the consumer that the condition names, or removes a registered certificate, and the stated claim "
                 "then fails. The kind of each control is recorded; a probe mutant runs on an isolated copy and is "
                 "never a run of the frozen build."),
    "compiledConsumer": ("For every condition that the closure discharges, the cited records show that the compiled "
                         "runtime or a downstream product consumer consumes the condition: the runtimes that the "
                         "certificates and probes execute equal the templates of the runtime identity, and the scans "
                         "read compiled artifacts and layouts."),
}
ROLE_STATUS = {"positive": "PASS", "negative": "KILLED", "compiledConsumer": "PASS"}
ROLE_KINDS = {
    "positive": {"KERNEL_RESULT", "PROBE_EXECUTION", "TEST_EXECUTION", "SOURCE_SCAN", "REGISTRY_RECORD",
                 "READER_COMPARISON"},
    "negative": {"KILLED_MUTANT", "KERNEL_REMOVAL", "KERNEL_CONTROL", "LEDGER_ROW_NEGATIVE", "RECORD_CONTROL"},
    "compiledConsumer": {"COMPILED_RUNTIME_SCAN", "EXECUTED_CODE_IDENTITY", "COMPILED_LAYOUT", "KERNEL_CODE_PIN",
                         "PROOF_GRAPH"},
}
ROLE_NONCLAIM_KEYS = ("unregisteredExecutions", "generalRuntimeLinks", "independentAssurance", "trust12Completion")
ASSUMPTION_SOURCES = {"central-ledger", "decision", "record", "closure"}
FINDING_KINDS = {"RESOLVED", "NONCLAIM"}
# Dispositions of an open item of the state and receipt crosswalk that carry the item to a later gate.
CARRIED_KINDS = ("AWAITS_FORMAL_READER", "NEEDS_DECISION")
EXPECTED_EVIDENCE_DIGEST = '5f2d01ef6782f6daba7fdeb7a1a7595e5cc819784a10ad103655ec73b7c9bc8e'
PUBLIC_KEYS = {"schema", "status", "scope", "executionBoundary", "evidenceBoundary", "assumptionBoundary",
               "reproductionBoundary", "conditionsSource", "finalInputs", "dischargedConditions", "conditionEvidence",
               "acceptance", "conditionSupport", "conditionNotes", "findingDispositions", "retainedAssumptions",
               "assumptionStatements", "assumptionScope", "generalRuntimeLinkDischarged", "assurance", "nonclaims"}
ROLE_KEYS = {"schema", "role", "status", "closureSha256", "statement", "conditions", "nonclaims"}
FINAL_INPUT_KEYS = {"runtimeSha256ByContract", "sourceInventorySha256", "abiSha256", "formalRootSha256",
                    "conditionSha256", "conditionsSha256"}
HEX64 = re.compile(r"[0-9a-f]{64}")
PRIVATE = re.compile(r"(?i)[A-Za-z]:[\\/]|/mnt/|/h[o]me/|/U[s]ers/|\\\\|(?<![A-Za-z0-9])(?:G|M|FV|RL)[0-9]+(?![0-9])")
FILTER = re.compile(r"\[([A-Za-z][A-Za-z0-9_]*)=([^\]]+)\]")
CONTROL_NAME = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*")
DASHES = (chr(0x2013), chr(0x2014))
ERRORS = (RuntimeError, ValueError, KeyError, TypeError, OSError, IndexError, AttributeError)


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True, allow_nan=False).encode("utf-8")


def same_json(left, right):
    return canonical(left) == canonical(right)


def js_encoded(value):
    """The bytes that the policy check hashes: sorted keys, two-space indentation and a final line feed."""
    return (json.dumps(value, sort_keys=True, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def payload_digest(closure):
    return hashlib.sha256(canonical(closure)).hexdigest()


def normalized(text):
    return " ".join(str(text).split())


def has_fixture(value):
    if isinstance(value, dict):
        return "fixtureOnly" in value or any(has_fixture(item) for item in value.values())
    if isinstance(value, list):
        return any(has_fixture(item) for item in value)
    return False


def privacy_boundary(value, label):
    encoded = json.dumps(value, ensure_ascii=False)
    require(encoded.isascii() and not PRIVATE.search(encoded) and not any(dash in encoded for dash in DASHES),
            "Private or non-English metadata: " + label)


def product_file(product, relative, label):
    require(isinstance(relative, str) and relative and not relative.startswith("/") and ".." not in relative.split("/")
            and "\\" not in relative and ":" not in relative, "Product path differs: " + label)
    path = (product / relative).resolve()
    require(path.is_relative_to(product) and path.is_file(), "Missing product file: " + relative)
    return path


def resolve(document, pointer, label):
    """A JSON pointer whose segments may end with a [key=value] filter that selects the one list item with that value.

    A segment such as mutants[id=X] first reads the member mutants and then selects its item whose id is X; the
    escapes ~1 and ~0 stand for / and ~ as in RFC 6901.
    """
    require(isinstance(pointer, str) and pointer.startswith("/") and len(pointer) > 1, "Pointer form differs: " + label)
    value = document
    for raw in pointer[1:].split("/"):
        segment = raw.replace("~1", "/").replace("~0", "~")
        selector = FILTER.search(segment)
        key = segment[:selector.start()] if selector and selector.end() == len(segment) else segment
        if key or not selector:
            if isinstance(value, list):
                require(key.isdigit() and int(key) < len(value), "Pointer index differs: " + label)
                value = value[int(key)]
            else:
                require(isinstance(value, dict) and key in value, "Named field is missing: " + label)
                value = value[key]
        if selector and selector.end() == len(segment):
            require(isinstance(value, list), "Pointer filter needs a list: " + label)
            hits = [item for item in value if isinstance(item, dict) and str(item.get(selector[1])) == selector[2]]
            require(len(hits) == 1, "Pointer filter does not select one item: " + label)
            value = hits[0]
    return value


def check_support(product, support, allowed_paths, label, documents):
    """Every named field of a cited record still holds the recorded value."""
    require(isinstance(support, list) and support, "No named field: " + label)
    used = set()
    for item in support:
        require(isinstance(item, dict) and set(item) == {"path", "pointer", "expected"}, "Named field form differs: " + label)
        require(item["path"] in allowed_paths, "Named field is not in the cited evidence: " + label + ": " + item["path"])
        if item["path"] not in documents:
            documents[item["path"]] = read_json(product_file(product, item["path"], label))
        value = resolve(documents[item["path"]], item["pointer"], label + ": " + item["pointer"])
        require(same_json(value, item["expected"]), "Named field differs: " + label + ": " + item["path"] + item["pointer"])
        used.add(item["path"])
    return used


def cited_record(product, item, gate_text, label, documents):
    """The evidence contract of the policy check: a passing checkpoint record whose verifier the required gate runs."""
    require(isinstance(item, dict) and set(item) == {"path", "sha256"} and isinstance(item["path"], str)
            and HEX64.fullmatch(str(item["sha256"])), "Cited evidence form differs: " + label)
    require(item["path"].startswith("evidence/") and item["path"].endswith(".json") and ".." not in item["path"],
            "Cited evidence is not a checkpoint record in the evidence tree: " + label)
    path = product_file(product, item["path"], label)
    require(digest(path) == item["sha256"], "Cited evidence differs from the current file: " + item["path"])
    record = documents.setdefault(item["path"], read_json(path))
    require(not has_fixture(record), "Cited evidence carries a fixture marker: " + item["path"])
    require(isinstance(record.get("status"), str) and record["status"].startswith("PASS"),
            "Cited evidence is not a passing record: " + item["path"])
    verifier = record.get("rehashVerifier")
    require(isinstance(verifier, dict) and isinstance(verifier.get("path"), str)
            and verifier["path"].startswith("scripts/trust12/") and verifier["path"] in gate_text,
            "Cited evidence has no verifier that the required gate runs: " + item["path"])
    require(digest(product_file(product, verifier["path"], label)) == verifier.get("sha256"),
            "Cited evidence verifier differs from the current file: " + item["path"])
    return record


def runtime_consistency(record, runtimes, label):
    """Runtimes that a cited record names are the runtimes of the runtime identity."""
    identity = record.get("runtimeIdentity")
    if isinstance(identity, dict):
        for profile in identity.values():
            if not isinstance(profile, dict):
                continue
            for group in ("executed", "deploymentOnly"):
                for name, entry in (profile.get(group) or {}).items():
                    require(isinstance(entry, dict) and runtimes.get(name) == entry.get("templateSha256"),
                            "Cited runtime differs from the runtime identity: " + label + ": " + name)
    loads = record.get("loads")
    if isinstance(loads, dict) and isinstance(loads.get("runtimes"), dict):
        for name, entry in loads["runtimes"].items():
            require(isinstance(entry, dict) and runtimes.get(name) == entry.get("runtimeSha256"),
                    "Cited runtime differs from the runtime identity: " + label + ": " + name)


def final_inputs(product, row):
    """The final inputs of the policy check, recomputed independently of its JavaScript implementation."""
    runtime_identity = read_json(product_file(product, RUNTIME_IDENTITY_PATH, "runtime identity"))
    for item in runtime_identity["sourceInputs"]:
        require(digest(product_file(product, item["path"], "source input")) == item["sha256"],
                "Runtime source differs from the runtime identity: " + item["path"])
    runtimes = {name: runtime_identity["runtimes"][name]["runtimeSha256"] for name in PROFILE_CONTRACTS}
    require(all(HEX64.fullmatch(str(value)) for value in runtimes.values()), "Runtime identity missing")
    return {"runtimeSha256ByContract": runtimes,
            "sourceInventorySha256": hashlib.sha256(js_encoded(runtime_identity["sourceInputs"])).hexdigest(),
            "abiSha256": digest(product_file(product, ABI_PATH, "kernel ABI")),
            "formalRootSha256": read_json(product_file(product, FORMAL_RESULTS_PATH, "formal results"))
            ["formalSource"]["rootSha256"],
            "conditionSha256": hashlib.sha256(row["abstractCondition"].encode("utf-8")).hexdigest(),
            "conditionsSha256": CONDITIONS_SHA256}


def public_contract(closure):
    """The record contract that needs no product file."""
    require(isinstance(closure, dict) and set(closure) == PUBLIC_KEYS and closure.get("schema") == SCHEMA
            and closure.get("status") == STATUS, "Closure contract differs")
    privacy_boundary(closure, "closure")
    require(not has_fixture(closure), "Closure carries a fixture marker")
    require(payload_digest(closure) == EXPECTED_EVIDENCE_DIGEST, "Reviewed evidence digest differs")
    require(closure["scope"] == SCOPE and closure["executionBoundary"] == EXECUTION_BOUNDARY
            and closure["evidenceBoundary"] == EVIDENCE_BOUNDARY and closure["assumptionBoundary"] == ASSUMPTION_BOUNDARY
            and closure["reproductionBoundary"] == REPRODUCTION_BOUNDARY, "Public scope or boundary differs")
    require(closure["assurance"] == ASSURANCE, "The closure claims the independent assurance")
    require(set(closure["nonclaims"]) == set(NONCLAIM_KEYS) and all(value is True for value in closure["nonclaims"].values()),
            "All bounded nonclaims required")
    require(closure["generalRuntimeLinkDischarged"] in (True, False), "General runtime link flag differs")
    for key in ("conditionEvidence", "acceptance", "conditionSupport", "conditionNotes", "findingDispositions",
                "assumptionStatements", "assumptionScope", "finalInputs", "conditionsSource"):
        require(isinstance(closure[key], dict), "Closure member is not an object: " + key)
    require(isinstance(closure["dischargedConditions"], list) and isinstance(closure["retainedAssumptions"], list),
            "Closure list member differs")


def condition_contract(closure, product, conditions, gate_text, documents):
    """Discharged conditions, cited evidence, quoted acceptance criteria and the fields named for each."""
    source = closure["conditionsSource"]
    require(source == {"path": CONDITIONS_PATH, "sha256": CONDITIONS_SHA256}
            and digest(product_file(product, CONDITIONS_PATH, "conditions")) == CONDITIONS_SHA256,
            "Conditions source differs from the reviewed list")
    discharged = [item["id"] for item in conditions["conditions"] if item["id"] != ASSURANCE_ID]
    require(closure["dischargedConditions"] == discharged, "Discharged conditions differ from the conditions list")
    for key in ("conditionEvidence", "acceptance", "conditionSupport", "conditionNotes"):
        require(list(closure[key]) == discharged, "Condition keys differ: " + key)
    criteria = named = 0
    cited = {}
    for condition in conditions["conditions"]:
        cid = condition["id"]
        if cid == ASSURANCE_ID:
            continue
        evidence = closure["conditionEvidence"][cid]
        require(isinstance(evidence, list) and evidence, "Condition has no cited evidence: " + cid)
        paths = [item.get("path") if isinstance(item, dict) else None for item in evidence]
        require(len(set(paths)) == len(paths), "Cited evidence repeats: " + cid)
        for item in evidence:
            cited[item["path"]] = cited_record(product, item, gate_text, cid, documents)
        entries = closure["acceptance"][cid]
        require(isinstance(entries, list) and [entry.get("criterion") if isinstance(entry, dict) else None
                                                 for entry in entries] == condition["closureAcceptance"],
                "Acceptance criteria differ from the conditions list: " + cid)
        used = set()
        for index, entry in enumerate(entries):
            require(set(entry) == {"criterion", "support", "limits"} and isinstance(entry["limits"], str),
                    "Acceptance entry form differs: " + cid)
            used |= check_support(product, entry["support"], set(paths), f"{cid} criterion {index + 1}", documents)
            named += len(entry["support"])
            criteria += 1
        clauses = closure["conditionSupport"][cid]
        require(isinstance(clauses, list), "Condition clause list differs: " + cid)
        for entry in clauses:
            require(isinstance(entry, dict) and set(entry) == {"clause", "support"} and isinstance(entry["clause"], str)
                    and len(entry["clause"]) >= 12 and normalized(entry["clause"]) in normalized(condition["condition"]),
                    "Condition clause is not quoted from the condition: " + cid)
            used |= check_support(product, entry["support"], set(paths), cid + " clause", documents)
            named += len(entry["support"])
        require(used == set(paths), "Cited evidence is named by no criterion or clause: " + cid)
        require(isinstance(closure["conditionNotes"][cid], str), "Condition note differs: " + cid)
    for path, record in cited.items():
        claimed = record.get("evidenceFor")
        if isinstance(claimed, dict) and "condition" in claimed:
            target = claimed["condition"]
            require(target in discharged and path in [item["path"] for item in closure["conditionEvidence"][target]],
                    "A cited record declares a condition it is not cited for: " + path)
            quoted = next(item for item in conditions["conditions"] if item["id"] == target)["closureAcceptance"]
            require(all(sentence in quoted for sentence in claimed.get("closureAcceptance", [])),
                    "A cited record quotes acceptance criteria that differ: " + path)
    return discharged, cited, criteria, named


def finding_contract(closure, product, conditions, discharged, gate_text, documents):
    findings = {item["id"]: item for item in conditions["findings"]}
    dispositions = closure["findingDispositions"]
    require(list(dispositions) == list(findings), "Finding dispositions differ from the conditions list")
    blocking = {finding for item in conditions["conditions"] if item["id"] in discharged
                for finding in item.get("blockingFindings", [])}
    resolved = 0
    for fid, disposition in dispositions.items():
        require(isinstance(disposition, dict) and set(disposition) == {"kind", "detail", "decisionNeeded", "evidence",
                                                                       "support"}
                and disposition["kind"] in FINDING_KINDS and isinstance(disposition["detail"], str)
                and disposition["detail"].strip(), "Finding disposition is incomplete: " + fid)
        require(disposition["decisionNeeded"] == findings[fid]["decisionNeeded"], "Finding text differs: " + fid)
        if fid in blocking:
            require(disposition["kind"] == "RESOLVED", "A finding that blocks a discharged condition must be resolved: " + fid)
        if disposition["kind"] == "RESOLVED":
            require(isinstance(disposition["evidence"], list) and disposition["evidence"],
                    "Resolved finding has no cited evidence: " + fid)
            paths = [item.get("path") if isinstance(item, dict) else None for item in disposition["evidence"]]
            require(len(set(paths)) == len(paths), "Finding evidence repeats: " + fid)
            for item in disposition["evidence"]:
                cited_record(product, item, gate_text, fid, documents)
            used = check_support(product, disposition["support"], set(paths), fid, documents)
            require(used == set(paths), "Finding evidence is named by no field: " + fid)
            resolved += 1
        else:
            require(disposition["evidence"] == [] and disposition["support"] == [], "Non-claim finding cites evidence: " + fid)
    return resolved


def open_item_contract(product):
    """Every open item of the state and receipt crosswalk is resolved or turned into a non-claim: the reviewed
    dispositions carry no item to a later gate."""
    record = read_json(product_file(product, DISPOSITIONS_PATH, "dispositions"))
    items = record.get("openItems")
    require(record.get("status") == "REVIEWED" and isinstance(items, list) and items
            and all(isinstance(item, dict) and isinstance(item.get("disposition"), str) and item["disposition"].strip()
                    and item["disposition"] not in CARRIED_KINDS and "carryOver" not in item for item in items),
            "An open item of the crosswalk is still carried to a later gate")
    return len(items)


def assumption_contract(closure, product, central, cited):
    retained = closure["retainedAssumptions"]
    require(all(isinstance(item, str) and item.strip() for item in retained) and len(set(retained)) == len(retained),
            "Retained assumptions differ")
    central_items = {item["id"]: item for item in central["assumptions"]}
    required = list(BASE_ASSUMPTIONS) + [item["id"] for item in central["assumptions"] if item["status"] != "DISCHARGED"]
    for path, record in cited.items():
        held = record.get("retainedAssumptions")
        if isinstance(held, dict):
            required += list(held)
    missing = sorted(set(required) - set(retained))
    require(not missing, "Retained assumptions differ: missing " + ", ".join(missing))
    statements = closure["assumptionStatements"]
    require(list(statements) == retained, "Assumption statements differ from the retained assumptions")
    decision = normalized(product_file(product, DECISION_PATH, "decision").read_text(encoding="utf-8"))
    for aid, entry in statements.items():
        require(isinstance(entry, dict) and set(entry) == {"source", "path", "statement"}
                and entry["source"] in ASSUMPTION_SOURCES and isinstance(entry["statement"], str)
                and entry["statement"].strip(), "Assumption statement form differs: " + aid)
        if entry["source"] == "central-ledger":
            require(entry["path"] == CENTRAL_LEDGER_PATH and aid in central_items
                    and central_items[aid]["statement"] == entry["statement"]
                    and central_items[aid]["status"] != "DISCHARGED", "Central assumption statement differs: " + aid)
        elif entry["source"] == "decision":
            require(entry["path"] == DECISION_PATH and normalized(entry["statement"]) in decision,
                    "Decision assumption statement differs: " + aid)
        elif entry["source"] == "record":
            held = cited.get(entry["path"], {}).get("retainedAssumptions")
            require(isinstance(held, dict) and held.get(aid) == entry["statement"], "Record assumption statement differs: " + aid)
        else:
            require(entry["path"] == CLOSURE_PATH and aid not in central_items, "Closure assumption source differs: " + aid)
    return retained


def assumption_scope_contract(closure, product, cited, documents):
    """How the cited kernel evidence uses a retained assumption, shown by named fields of cited records."""
    scope = closure["assumptionScope"]
    require(set(scope) <= set(closure["retainedAssumptions"]), "Assumption scope names an assumption that is not retained")
    named = 0
    for aid, entry in scope.items():
        require(isinstance(entry, dict) and set(entry) == {"statement", "support"} and isinstance(entry["statement"], str)
                and entry["statement"].strip(), "Assumption scope form differs: " + aid)
        check_support(product, entry["support"], set(cited), "assumption scope " + aid, documents)
        named += len(entry["support"])
    return named


def role_contract(role, record, closure_sha256, discharged, product, documents, runtimes):
    require(isinstance(record, dict) and set(record) == ROLE_KEYS and record["schema"] == ROLE_SCHEMA
            and record["role"] == role and record["status"] == ROLE_STATUS[role], "Role record contract differs: " + role)
    privacy_boundary(record, role)
    require(not has_fixture(record), "Role record carries a fixture marker: " + role)
    require(record["closureSha256"] == closure_sha256, "Role record does not bind the closure: " + role)
    require(record["statement"] == ROLE_STATEMENTS[role], "Role statement differs: " + role)
    require(set(record["nonclaims"]) == set(ROLE_NONCLAIM_KEYS) and all(v is True for v in record["nonclaims"].values()),
            "All bounded role nonclaims required: " + role)
    require(isinstance(record["conditions"], dict) and list(record["conditions"]) == discharged,
            "Role record does not cover every discharged condition: " + role)
    entries = 0
    for cid, items in record["conditions"].items():
        require(isinstance(items, list) and items, "Role record has no evidence for a condition: " + role + ": " + cid)
        for item in items:
            if isinstance(item, dict) and "controls" in item:
                control_entry(role, cid, item, product)
                entries += 1
                continue
            require(isinstance(item, dict) and set(item) == {"path", "sha256", "kind", "support", "detail"}
                    and item["kind"] in ROLE_KINDS[role] and isinstance(item["detail"], str) and item["detail"].strip(),
                    "Role entry form differs: " + role + ": " + cid)
            require(isinstance(item["path"], str) and item["path"].startswith("evidence/")
                    and item["path"].endswith(".json"), "Role evidence is not an evidence record: " + str(item["path"]))
            path = product_file(product, item["path"], role)
            require(HEX64.fullmatch(str(item["sha256"])) and digest(path) == item["sha256"],
                    "Role evidence differs from the current file: " + item["path"])
            document = documents.setdefault(item["path"], read_json(path))
            require(not has_fixture(document), "Role evidence carries a fixture marker: " + item["path"])
            runtime_consistency(document, runtimes, item["path"])
            fields = item["support"]
            require(isinstance(fields, list) and fields and all(isinstance(field, dict) and set(field) == {"pointer", "expected"}
                                                                for field in fields),
                    "Role entry fields differ: " + role + ": " + cid)
            check_support(product, [{"path": item["path"], **field} for field in fields], {item["path"]},
                          role + ": " + cid, documents)
            entries += 1
    return entries


def control_entry(role, cid, item, product):
    """A negative that names public controls of a cited record: the script holds each named control and the required
    controls run the script, so a rejected substitution of the consumer fails the required gate."""
    require(role == "negative" and set(item) == {"path", "sha256", "kind", "controls", "detail"}
            and item["kind"] == "RECORD_CONTROL" and isinstance(item["detail"], str) and item["detail"].strip(),
            "Role control entry form differs: " + cid)
    path = item["path"]
    require(isinstance(path, str) and path.startswith("scripts/") and path.endswith(".py"),
            "Role control entry is not a public control script: " + str(path))
    script = product_file(product, path, "control script")
    require(HEX64.fullmatch(str(item["sha256"])) and digest(script) == item["sha256"],
            "Role control script differs from the current file: " + path)
    names = item["controls"]
    require(isinstance(names, list) and names and len(set(names)) == len(names)
            and all(isinstance(name, str) and CONTROL_NAME.fullmatch(name) for name in names),
            "Role control names differ: " + cid)
    text = script.read_text(encoding="utf-8")
    for name in names:
        require(text.count("rejected('" + name + "'") + text.count("product_change('" + name + "'") == 1,
                "Role control is not in the control script: " + name)
    required = product_file(product, REQUIRED_CONTROLS_PATH, "required controls").read_text(encoding="utf-8")
    require("resolve(root, '" + path + "')" in required, "The required controls do not run the control script: " + path)


def ledger_contract(product, closure_ref, role_refs):
    ledger = read_json(product_file(product, LEDGER_PATH, "ledger"))
    rows = {row["id"]: row for row in ledger["obligations"]}
    row = rows.get(ROW_ID)
    require(isinstance(row, dict) and row.get("status") == "CLOSED" and row.get("proofCompleted") is True,
            "The ledger row is not closed")
    references = {"closure": closure_ref, **role_refs}
    require(row.get("registeredClosureEvidence") == {"status": ROW_STATUS, "references": references},
            "The ledger row does not cite the four records")
    for key, role in (("positiveActivation", "positive"), ("consumerRemovalNegative", "negative"),
                      ("compiledConsumer", "compiledConsumer")):
        require(isinstance(row.get(key), str) and ROLE_PATHS[role] in row[key], "The ledger row text does not name " + role)
    return row, rows


def cited_paths(closure):
    """The checkpoint records that the closure cites for its conditions and findings, in first-citation order."""
    paths = []
    for items in list(closure.get("conditionEvidence", {}).values()) + [
            disposition.get("evidence", []) for disposition in closure.get("findingDispositions", {}).values()]:
        for item in items:
            if isinstance(item, dict) and item.get("path") not in paths:
                paths.append(item.get("path"))
    return paths


def metadata_inputs(product):
    """Every product file that this verifier reads, relative to the product root."""
    product = product.resolve()
    closure = read_json(product / CLOSURE_PATH)
    paths = {CLOSURE_PATH, VERIFIER_PATH, LEDGER_PATH, CENTRAL_LEDGER_PATH, CONDITIONS_PATH, REQUIRED_GATE_PATH,
             REQUIRED_CONTROLS_PATH, RUNTIME_IDENTITY_PATH, ABI_PATH, FORMAL_RESULTS_PATH, DECISION_PATH,
             DISPOSITIONS_PATH, *ROLE_PATHS.values()}
    paths |= {item["path"] for item in read_json(product / RUNTIME_IDENTITY_PATH)["sourceInputs"]}
    for path in cited_paths(closure):
        paths |= {path, read_json(product / path)["rehashVerifier"]["path"]}
    for role_path in ROLE_PATHS.values():
        paths |= {item["path"] for items in read_json(product / role_path)["conditions"].values() for item in items}
    return sorted(paths)


def verify(product):
    product = product.resolve()
    closure_path = product_file(product, CLOSURE_PATH, "closure")
    return verify_record(read_json(closure_path), product, digest(closure_path))


def verify_record(closure, product, closure_sha256):
    """All checks on a closure record whose file has the given digest; the controls pass an edited record."""
    product = product.resolve()
    public_contract(closure)
    closure_ref = {"path": CLOSURE_PATH, "sha256": closure_sha256}
    role_refs = {role: {"path": path, "sha256": digest(product_file(product, path, role))} for role, path in ROLE_PATHS.items()}
    row, rows = ledger_contract(product, closure_ref, role_refs)
    gate_text = product_file(product, REQUIRED_GATE_PATH, "required gate").read_text(encoding="utf-8")
    conditions = read_json(product_file(product, CONDITIONS_PATH, "conditions"))
    central = read_json(product_file(product, CENTRAL_LEDGER_PATH, "central ledger"))
    documents = {}
    discharged, cited, criteria, named = condition_contract(closure, product, conditions, gate_text, documents)
    resolved = finding_contract(closure, product, conditions, discharged, gate_text, documents)
    open_items = open_item_contract(product)
    for path in [item["path"] for disposition in closure["findingDispositions"].values() for item in disposition["evidence"]]:
        cited.setdefault(path, documents[path])
    retained = assumption_contract(closure, product, central, cited)
    named += assumption_scope_contract(closure, product, cited, documents)
    expected_inputs = final_inputs(product, row)
    require(set(closure["finalInputs"]) == FINAL_INPUT_KEYS and same_json(closure["finalInputs"], expected_inputs),
            "Final inputs differ from the current runtimes, sources, ABI, formal root or conditions")
    runtimes = expected_inputs["runtimeSha256ByContract"]
    for path, record in cited.items():
        runtime_consistency(record, runtimes, path)
    require(closure["generalRuntimeLinkDischarged"] == all(rows[item]["status"] == "CLOSED" for item in GENERAL_IDS),
            "General runtime link flag differs from the ledger")
    entries = {}
    for role, path in ROLE_PATHS.items():
        record = read_json(product_file(product, path, role))
        entries[role] = role_contract(role, record, closure_ref["sha256"], discharged, product, documents, runtimes)
    return {"status": REPORT_STATUS, "conditions": len(discharged), "citedRecords": len(cited),
            "acceptanceCriteria": criteria, "namedFields": named, "findingsResolved": resolved,
            "crosswalkOpenItemsSettled": open_items,
            "retainedAssumptions": retained, "roleEntries": entries, "closureSha256": closure_ref["sha256"],
            "proverRuns": 0, "nonclaim": ("Accounting of cited evidence only; no kernel session, prover, compiler or "
                                          "Foundry execution was rerun, and the independent assurance is open.")}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--product-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--metadata-only", action="store_true")
    args = parser.parse_args()
    require(args.metadata_only, "The registered closure has no saved mode; run with --metadata-only")
    print(json.dumps(verify(args.product_root), indent=2))
    return 0


if __name__ == "__main__":
    sys.dont_write_bytecode = True
    try:
        raise SystemExit(main())
    except ERRORS as error:
        raise SystemExit(f"FAIL: {error}")
