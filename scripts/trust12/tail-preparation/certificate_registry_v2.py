#!/usr/bin/env python3
"""Build and check the certificate registry, the acceptance partition coverage and the executed code of every certificate.

The 27-cell gate and the central condition that the accepted set of each profile is the image of checked
K/KEVM certificates need a finite registry: for every profile, operation and outcome branch, and for every
registered request outside canonical form, the checked certificate whose execution belongs to the accepted
set. Version 2 of the registry adds what version 1 could not record:

* every registered request outside canonical form is its own certificate, keyed by its recorded slug, and
  the registered slugs of each profile must equal the tracked malformed KEVM catalog;
* every certificate records the code it executed. For each world recorded before the call (a KEVM accounts
  cell in KORE text form) the tool reads the code of the account that the recorded frame executes and
  compares it with the runtime template of the profile endpoint under the exact matching rule of the code
  identity: same length and equal bytes outside the merged immutable ranges. The world must also hold
  exactly one account for each runtime of the executed set of the profile and no account of a runtime that
  only deployment uses;
* every recorded world is bound by hash to the records that consumed it, and every certificate needs at
  least one world that the input binding of a kernel session names. A world that only a KORE export record
  names is accepted only with a reason quoted from a tracked document and only when it yields the same
  executed code as a world of the same certificate that a kernel session consumed;
* acceptance is the verdict that the prover run recorded or, where no run recorded one, the verdict of the
  APRProof status rule on the stored proof graph, whose files must hash to the recorded proof and graph;
* closure mode fails unless every cell is bound, every malformed branch is covered and every check passes.
  An incomplete or unavailable result fails closure exactly like a failing one.

The locator file names, per certificate, where the evidence records it, which recorded worlds belong to it
and which records consumed them; it lives next to the evidence because the evidence layout is internal. The
tool never runs a prover and never closes a cell.

Usage:
  certificate_registry_v2.py build  --evidence DIR --locators FILE --output FILE [--mode MODE] [--product-root DIR]
  certificate_registry_v2.py verify --evidence DIR --locators FILE --registry FILE [--product-root DIR]

The product root defaults to this checkout; it supplies the code identity, the malformed catalog and the
tracked records that state the reason of a world named only by KORE exports.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

import kore_accounts
from certificate_registry import field, ledger_cells, pointer, slug_cell
from tail_common import (
    NONCLAIM, OPERATIONS, OUTPUT, PROFILES, ROOT, PreparationError, dump_json, load_json, require,
    require_schema, schema_errors, sha256_bytes, sha256_file,
)

SCHEMA = OUTPUT / "certificate-registry-schema-v2.json"
REGISTRY_SCHEMA_ID = "trust12-tail-preparation-certificate-registry-v2"
CODE_IDENTITY_PATH = "evidence/trust12/runtime-link/tail-preparation/code-identity-v1.json"
MALFORMED_CATALOG_PATH = "evidence/trust12/runtime-link/malformed/kevm-kore-checkpoint-v1.json"
CATALOG_PROFILES = {"native": "Native", "partial": "Partial", "hook": "Hook"}
KERNEL_STAGE_INPUT = "KERNEL_STAGE_INPUT"
KORE_EXPORT = "KORE_EXPORT"
SESSION_NAME = re.compile(r"[A-Z][A-Z0-9_]*")
RECORDED_FIELDS = "RECORDED_FIELDS"
STORED_PROOF_GRAPH = "STORED_PROOF_GRAPH"
KCFG_KEYS = frozenset({"next", "nodes", "edges", "merged_edges", "covers", "splits", "ndbranches", "aliases",
                       "vacuous", "stuck"})
SUCCESSOR_KEYS = ("edges", "merged_edges", "covers", "splits", "ndbranches")
PROOF_KEYS = frozenset({"id", "type", "init", "target", "terminal", "admitted", "circularity", "subproof_ids",
                        "node_refutations", "bounded"})

# Runtimes of the code identity that only a deployment uses. Every other runtime of a profile belongs to the
# executed set that each recorded world must hold exactly once.
DEPLOYMENT_ONLY_RUNTIMES = {
    "Hook": {
        "ERC3643HookFactory": (
            "Every recorded world is a state after the unit was created, and the certificate harness creates each "
            "unit by running the adapter creation code directly, so the factory, which in a product deployment "
            "hash-checks and runs that creation code, is neither deployed nor called in a recorded world."
        ),
    },
}
DEPLOYMENT_ASSUMPTION = "A-DEPLOYMENT"
RETAINED_ASSUMPTIONS = {
    "A-DEPLOYMENT": (
        "No deployed instance is bound. The registry identifies the code that the certificates executed, not the "
        "code of a deployment, and not whether a deployed unit was created through the factory or directly."
    ),
    "A-EXTERNAL": (
        "Only the profile runtimes are identified by code. The other accounts of a recorded world, the calling test "
        "harness and the dependency contracts such as the upstream ERC-3643 token and the identity registry and "
        "compliance contracts that are not profile runtimes, are not identified, and the behavior of the "
        "dependencies remains assumed."
    ),
}
MATCH_RULE = (
    "The executed code is the code cell of the account named by the recorded frame identifier, read from the "
    "recorded world. It matches the profile endpoint when it has the template length and its SHA-256 after "
    "zeroing the merged immutable ranges equals the template hash. A template carries zeros inside those ranges, "
    "so a match means equal bytes everywhere outside the immutable ranges."
)
RUNTIME_SET_RULE = (
    "The code identity of a certificate is the executed runtime set of its profile: every runtime of the code "
    "identity of the profile except the runtimes that only a deployment uses. Each recorded world must hold "
    "exactly one account whose code matches each runtime of that set under the same matching rule and no account "
    "whose code matches a runtime that only a deployment uses."
)
CONSUMER_RULE = (
    "A consumer is a record that names a recorded world by path and SHA-256. It is a kernel stage input when the "
    "record names exactly one kernel session and a KORE export when it names none. Every certificate needs at "
    "least one world that a kernel stage input names. A world that only KORE exports name needs a reason quoted "
    "from a tracked document and must yield the same executed code as a world of the same certificate that a "
    "kernel stage input names. The registry checks the recorded hashes; it does not replay the kernel sessions."
)
GRAPH_RULE = (
    "The stored proof graph is read as the prover wrote it. A leaf is a node without an outgoing edge, merged "
    "edge, cover, split or branch. A leaf is explorable when it is not terminal, stuck or vacuous; it is pending "
    "when it is explorable and not the target, refuted or bounded, and failing when it is not explorable and not "
    "the target, refuted, vacuous or bounded. A graph with a failing leaf fails, otherwise a graph with a pending "
    "leaf is pending, otherwise it passes. An admitted proof passes regardless, so acceptance also requires the "
    "proof not to be admitted and not to be a circularity."
)


# ---------------------------------------------------------------------------
# Evidence references
# ---------------------------------------------------------------------------

class Evidence:
    """Files of the evidence root. JSON documents are read and hashed once and every read path is recorded."""

    def __init__(self, root: Path) -> None:
        self.root = root
        self.cache: dict[str, tuple[Any, str]] = {}
        self.reads: set[str] = set()

    def path(self, relative: str) -> Path | None:
        """The file of a recorded relative path, or None. A name that a Linux tool wrote with a colon is stored
        with U+F03A on a Windows host, so both spellings are tried."""
        for candidate in dict.fromkeys((relative, relative.replace(":", "\uf03a"), relative.replace("\uf03a", ":"))):
            try:
                path = self.root / candidate
                if path.is_file():
                    self.reads.add(relative)
                    return path
            except OSError:
                continue
        return None

    def read(self, relative: str) -> bytes | None:
        path = self.path(relative)
        return None if path is None else path.read_bytes()

    def load(self, relative: str) -> tuple[Any, str]:
        if relative not in self.cache:
            data = self.read(relative)
            require(data is not None, f"evidence document missing: {relative}")
            self.cache[relative] = (json.loads(data.decode("utf-8-sig")), sha256_bytes(data))
        return self.cache[relative]

    def resolve(self, reference: dict[str, Any]) -> tuple[Any, dict[str, Any], Any]:
        document, digest = self.load(reference["path"])
        if "array" in reference:
            items = pointer(document, reference["array"])
            require(isinstance(items, list), f"not an array: {reference['path']}{reference['array']}")
            matches = [index for index, item in enumerate(items) if isinstance(item, dict)
                       and all(item.get(key) == expected for key, expected in reference["match"].items())]
            require(len(matches) == 1, f"search matched {len(matches)} entries in {reference['path']}{reference['array']}")
            location = f"{reference['array']}/{matches[0]}"
        else:
            location = reference["pointer"]
        value = pointer(document, location)
        if "field" in reference:
            value = field(value, reference["field"])
            location = location + "".join(f"/{part}" for part in reference["field"].split("."))
        return value, {"path": reference["path"], "pointer": location, "sha256": digest}, document


def same_place(recorded: str, relative: str) -> bool:
    """A recorded path names the located file when one is a path suffix of the other."""
    recorded = recorded.replace("\\", "/").replace("\uf03a", ":")
    relative = relative.replace("\\", "/").replace("\uf03a", ":")
    return recorded == relative or recorded.endswith("/" + relative) or relative.endswith("/" + recorded)


def kernel_record(evidence: Evidence, kernel: dict[str, Any]) -> dict[str, Any]:
    relative = f"{kernel['root']}/{kernel['run']}/result.json"
    record = {"root": kernel["root"], "run": kernel["run"], "theory": kernel["theory"],
              "ledgerResultSha256": kernel.get("resultSha256"), "problems": []}
    data = evidence.read(relative)
    if data is None:
        record["problems"].append("kernel result missing")
        return record
    status = json.loads(data.decode("utf-8-sig")).get("status", "")
    record.update({"resultSha256": sha256_bytes(data), "status": status})
    if record["resultSha256"] != kernel.get("resultSha256"):
        record["problems"].append("kernel result differs from the hash the ledger recorded")
    if not str(status).startswith("PASS_"):
        record["problems"].append("kernel result is not PASS")
    return record


# ---------------------------------------------------------------------------
# Code identity
# ---------------------------------------------------------------------------

def profile_identities(identity: dict[str, Any]) -> dict[str, dict[str, Any]]:
    profiles = {}
    for profile in PROFILES:
        record = identity["profiles"][profile]
        runtimes = {item["contract"]: dict(item) for item in record["runtimes"]}
        require(len(runtimes) == len(record["runtimes"]), f"{profile}: a runtime is listed twice")
        require(record["endpoint"] in runtimes, f"{profile}: the endpoint has no runtime template")
        deployment_only = DEPLOYMENT_ONLY_RUNTIMES.get(profile, {})
        require(set(deployment_only) <= set(runtimes) and record["endpoint"] not in deployment_only,
                f"{profile}: a deployment-only runtime is not a non-endpoint runtime of the code identity")
        profiles[profile] = {"profileIndex": record["profileIndex"], "endpoint": record["endpoint"],
                             "root": record["identityRootSha256"], "runtimes": runtimes,
                             "executed": [name for name in runtimes if name not in deployment_only],
                             "deploymentOnly": [name for name in runtimes if name in deployment_only]}
    return profiles


def masked(code: bytes, ranges: list[list[int]]) -> bytes | None:
    data = bytearray(code)
    for start, end in ranges:
        if end > len(data):
            return None
        data[start:end] = bytes(end - start)
    return bytes(data)


def template_match(code: bytes, runtime: dict[str, Any]) -> bool:
    template = runtime["runtimeTemplate"]
    if len(code) != template["bytes"]:
        return False
    view = masked(code, runtime["immutableRanges"])
    return view is not None and sha256_bytes(view) == template["sha256"]


def runtime_set(accounts: dict[int, kore_accounts.Account], identity: dict[str, Any]) -> tuple[dict[str, Any], list[str]]:
    ordered = sorted(accounts.values(), key=lambda item: item.account)
    matched = {contract: [str(account.account) for account in ordered
                          if account.code is not None and template_match(account.code, runtime)]
               for contract, runtime in identity["runtimes"].items()}
    identified = {account for accounts_of in matched.values() for account in accounts_of}
    problems = [f"the recorded world holds {len(matched[contract])} accounts with the {contract} template"
                for contract in identity["executed"] if len(matched[contract]) != 1]
    problems += [f"the deployment-only runtime {contract} appears in the recorded world"
                 for contract in identity["deploymentOnly"] if matched[contract]]
    record = {
        "executed": {contract: matched[contract] for contract in identity["executed"]},
        "deploymentOnly": {contract: matched[contract] for contract in identity["deploymentOnly"]},
        "unboundAccounts": sum(1 for account in ordered if account.code is not None
                               and str(account.account) not in identified),
        "symbolicAccounts": sum(1 for account in ordered if account.code is None),
    }
    return record, problems


# ---------------------------------------------------------------------------
# Stored proof graphs
# ---------------------------------------------------------------------------

def graph_verdict(proof: dict[str, Any], kcfg: dict[str, Any]) -> dict[str, Any]:
    """Status of a stored APRProof graph by the leaf rule; raises PreparationError when the graph is not readable."""
    require(PROOF_KEYS <= set(proof), "the proof record lacks a status field")
    require(set(kcfg) <= KCFG_KEYS, f"the graph carries an unknown part: {sorted(set(kcfg) - KCFG_KEYS)}")
    require(proof["subproof_ids"] == [], "the proof has subproofs, whose status this reader does not evaluate")
    require(not kcfg.get("aliases"), "the graph uses node aliases, which this reader does not resolve")
    nodes = [item if isinstance(item, int) else item.get("id") for item in kcfg["nodes"]]
    require(all(type(node) is int for node in nodes) and len(set(nodes)) == len(nodes), "graph node identifiers differ")
    known = set(nodes)
    outgoing = dict.fromkeys(nodes, 0)
    for key in SUCCESSOR_KEYS:
        for item in kcfg.get(key, []):
            require(isinstance(item, dict) and item.get("source") in known, f"a {key} entry names an unknown node")
            outgoing[item["source"]] += 1
    marks = {name: set(values) for name, values in (("terminal", proof["terminal"]), ("bounded", proof["bounded"]),
                                                    ("stuck", kcfg.get("stuck", [])), ("vacuous", kcfg.get("vacuous", [])))}
    refuted = {int(key) for key in proof["node_refutations"]}
    target = proof["target"]
    require(type(target) is int and target in known and type(proof["init"]) is int and proof["init"] in known
            and all(values <= known for values in marks.values()) and refuted <= known, "graph markers name unknown nodes")
    leaves = [node for node in nodes if outgoing[node] == 0]
    explorable = [node for node in leaves if node not in marks["terminal"] | marks["stuck"] | marks["vacuous"]]
    pending = [node for node in explorable if node != target and node not in refuted | marks["bounded"]]
    failing = [node for node in leaves if node not in explorable and node != target
               and node not in refuted | marks["vacuous"] | marks["bounded"]]
    verdict = "PASSED" if proof["admitted"] else "FAILED" if failing else "PENDING" if pending else "PASSED"
    return {"verdict": verdict, "nodes": len(nodes), "edges": len(kcfg.get("edges", [])),
            "covers": len(kcfg.get("covers", [])), "leaves": sorted(leaves), "terminal": sorted(marks["terminal"]),
            "target": target, "pendingNodes": sorted(pending), "failingNodes": sorted(failing),
            "fields": {"passed": verdict == "PASSED", "failed": verdict == "FAILED", "admitted": proof["admitted"],
                       "circularity": proof["circularity"], "pendingNodes": sorted(pending),
                       "failingNodes": sorted(failing)}}


def stored_proof(evidence: Evidence, spec: dict[str, Any], record: dict[str, Any]) -> tuple[dict[str, Any], list[str], list[str]]:
    """Acceptance fields recomputed from the stored proof graph, with failing and unavailable findings."""
    graph: dict[str, Any] = {"proof": {"path": spec["proof"], "sha256": None}, "kcfg": {"path": spec["kcfg"], "sha256": None}}
    proof_bytes, kcfg_bytes = evidence.read(spec["proof"]), evidence.read(spec["kcfg"])
    if proof_bytes is None or kcfg_bytes is None:
        return graph, [], ["stored proof or graph file missing"]
    graph["proof"]["sha256"], graph["kcfg"]["sha256"] = sha256_bytes(proof_bytes), sha256_bytes(kcfg_bytes)
    failing = []
    if graph["proof"]["sha256"] != record.get("proofSha256"):
        failing.append("stored proof file differs from the recorded proof hash")
    if graph["kcfg"]["sha256"] != record.get("kcfgSha256"):
        failing.append("stored graph file differs from the recorded graph hash")
    try:
        proof, kcfg = json.loads(proof_bytes.decode("utf-8")), json.loads(kcfg_bytes.decode("utf-8"))
        require(isinstance(proof, dict) and isinstance(kcfg, dict), "the proof or graph file is not an object")
        if proof.get("type") != "APRProof" or proof.get("id") != record.get("proofId"):
            failing.append("stored proof is not the recorded APRProof")
        graph.update(graph_verdict(proof, kcfg))
    except (PreparationError, ValueError, KeyError, TypeError, UnicodeDecodeError) as error:
        return graph, failing, [f"stored proof graph is not readable: {error}"]
    return graph, failing, []


# ---------------------------------------------------------------------------
# Certificates
# ---------------------------------------------------------------------------

def consumer_record(evidence: Evidence, reference: dict[str, Any], world: dict[str, Any], accounts: str) -> dict[str, Any]:
    value, source, document = evidence.resolve(reference)
    agrees = (world["accounts"]["sha256"] is not None and isinstance(value, dict)
              and value.get("sha256") == world["accounts"]["sha256"]
              and (not isinstance(value.get("path"), str) or same_place(value["path"], accounts)))
    sessions = [document.get(key) for key in ("session", "targetSession")
                if isinstance(document, dict) and key in document]
    entry: dict[str, Any] = {"kind": reference["kind"], "source": source, "agrees": agrees}
    if reference["kind"] == KERNEL_STAGE_INPUT:
        named = len(sessions) == 1 and isinstance(sessions[0], str) and SESSION_NAME.fullmatch(sessions[0]) is not None
        entry.update({"session": sessions[0] if named else None, "kindAgrees": named})
    else:
        schema = document.get("schema") if isinstance(document, dict) else None
        entry.update({"documentSchema": schema if isinstance(schema, str) else None, "kindAgrees": not sessions})
    return entry


def world_record(evidence: Evidence, spec: dict[str, Any], identity: dict[str, Any],
                 worlds: dict[str, Any]) -> dict[str, Any]:
    endpoint = identity["runtimes"][identity["endpoint"]]
    if spec["accounts"] not in worlds:
        data = evidence.read(spec["accounts"])
        if data is None:
            worlds[spec["accounts"]] = (None, None, "missing")
        else:
            try:
                worlds[spec["accounts"]] = (sha256_bytes(data), kore_accounts.accounts(data.decode("utf-8")), None)
            except (kore_accounts.KoreError, UnicodeDecodeError) as error:
                worlds[spec["accounts"]] = (sha256_bytes(data), None, str(error))
    digest, accounts, parse_error = worlds[spec["accounts"]]
    frame = evidence.read(spec["frame"])
    record: dict[str, Any] = {
        "role": spec["role"],
        "accounts": {"path": spec["accounts"], "sha256": digest},
        "frame": {"path": spec["frame"], "sha256": None if frame is None else sha256_bytes(frame)},
        "account": None, "status": "UNAVAILABLE", "consumers": [], "links": [], "kernelStageInputs": 0,
        "runtimeSet": None, "endpointRecordAgrees": None, "codeProblems": [], "problems": [],
    }
    for reference in spec.get("consumers", []):
        entry = consumer_record(evidence, reference, record, spec["accounts"])
        record["consumers"].append(entry)
        where = f"{entry['source']['path']}{entry['source']['pointer']}"
        if not entry["agrees"]:
            record["problems"].append(f"{spec['role']}: {where} records another world")
        if not entry["kindAgrees"]:
            record["problems"].append(f"{spec['role']}: {where} is not a {reference['kind']} record")
    record["kernelStageInputs"] = sum(1 for entry in record["consumers"]
                                      if entry["kind"] == KERNEL_STAGE_INPUT and entry["agrees"] and entry["kindAgrees"])
    for left_reference, right_reference in spec.get("links", []):
        left, left_source, _ = evidence.resolve(left_reference)
        right, right_source, _ = evidence.resolve(right_reference)
        record["links"].append({"left": left_source, "right": right_source, "agrees": left == right})
        if left != right:
            record["problems"].append(f"{spec['role']}: linked records disagree: {left_source['path']}{left_source['pointer']}")
    if digest is None or frame is None:
        record["problems"].append(f"{spec['role']}: recorded world or frame missing")
        return record
    if accounts is None:
        record["problems"].append(f"{spec['role']}: recorded world is not readable: {parse_error}")
        return record
    try:
        account_id = kore_accounts.frame_account(frame.decode("utf-8"))
    except (kore_accounts.KoreError, UnicodeDecodeError) as error:
        record["problems"].append(f"{spec['role']}: frame is not readable: {error}")
        return record
    record["account"] = str(account_id)
    code_problems = record["codeProblems"]
    if "endpointRecord" in spec:
        recorded, source, _ = evidence.resolve(spec["endpointRecord"])
        record["endpointRecordAgrees"] = str(recorded) == str(account_id)
        if not record["endpointRecordAgrees"]:
            code_problems.append(f"{spec['role']}: frame account differs from {source['path']}{source['pointer']}")
    record["runtimeSet"], set_problems = runtime_set(accounts, identity)
    code_problems += [f"{spec['role']}: {problem}" for problem in set_problems]
    account = accounts.get(account_id)
    if account is None or account.code is None:
        record["problems"] += code_problems + [f"{spec['role']}: the executing account " +
                                               ("is absent from the recorded world" if account is None else "has symbolic code")]
        return record
    code, ranges = account.code, endpoint["immutableRanges"]
    view = masked(code, ranges)
    if not template_match(code, endpoint):
        code_problems.append(f"{spec['role']}: executed code differs from the {identity['endpoint']} template "
                             "outside the immutable ranges")
    record.update({
        "executedCodeSha256": sha256_bytes(code),
        "executedCodeBytes": len(code),
        "status": "MISMATCH" if code_problems else "MATCH",
    })
    if view is not None:
        record["maskedCodeSha256"] = sha256_bytes(view)
        record["immutableValuesSha256"] = sha256_bytes(b"".join(code[start:end] for start, end in ranges))
    record["problems"] += code_problems
    return record


def export_only(product: Path, spec: dict[str, Any] | None, world: dict[str, Any],
                consumed_codes: set[Any]) -> dict[str, Any] | None:
    """Record the stated reason of a world that only KORE exports name and check it against its tracked source."""
    if spec is None:
        return None
    exported = any(entry["kind"] == KORE_EXPORT and entry["agrees"] and entry["kindAgrees"] for entry in world["consumers"])
    record: dict[str, Any] = {"reason": spec["reason"], "quote": spec["quote"],
                              "source": {"root": "PRODUCT", "path": spec["source"]["path"],
                                         "pointer": spec["source"]["pointer"], "sha256": None},
                              "applies": world["kernelStageInputs"] == 0 and exported,
                              "quoteFound": False, "sameExecutedCodeAsConsumedWorld": False}
    path = product / spec["source"]["path"]
    if path.is_file():
        record["source"]["sha256"] = sha256_file(path)
        try:
            text = pointer(load_json(path), spec["source"]["pointer"])
            record["quoteFound"] = isinstance(text, str) and spec["quote"] in text
        except (PreparationError, ValueError):
            record["quoteFound"] = False
    record["sameExecutedCodeAsConsumedWorld"] = (world.get("executedCodeSha256") is not None
                                                 and world.get("executedCodeSha256") in consumed_codes)
    return record


def execution_record(evidence: Evidence, spec: dict[str, Any], identity: dict[str, Any], product: Path,
                     worlds: dict[str, Any]) -> dict[str, Any]:
    endpoint = identity["runtimes"][identity["endpoint"]]
    records = [world_record(evidence, item, identity, worlds) for item in spec["preWorlds"]]
    consumed_codes = {item.get("executedCodeSha256") for item in records if item["kernelStageInputs"] > 0}
    for item, world_spec in zip(records, spec["preWorlds"]):
        declared = export_only(product, world_spec.get("exportOnly"), item, consumed_codes)
        if declared is not None:
            item["exportOnly"] = declared
    statuses = {item["status"] for item in records}
    status = ("MISMATCH" if "MISMATCH" in statuses else
              "UNAVAILABLE" if "UNAVAILABLE" in statuses or not records else "MATCH")
    codes = {item.get("executedCodeSha256") for item in records}
    return {
        "endpointContract": identity["endpoint"],
        "templateSha256": endpoint["runtimeTemplate"]["sha256"],
        "templateBytes": endpoint["runtimeTemplate"]["bytes"],
        "immutableRanges": endpoint["immutableRanges"],
        "status": status,
        "executedCodeSha256": codes.pop() if len(codes) == 1 and None not in codes else None,
        "kernelStageInputs": sum(item["kernelStageInputs"] for item in records),
        "preWorlds": records,
    }


def acceptance_record(evidence: Evidence, spec: dict[str, Any], raw: Any, source: dict[str, Any],
                      record: dict[str, Any]) -> tuple[dict[str, Any], list[str]]:
    acceptance = spec.get("acceptance")
    if not acceptance:
        return {"status": "NOT_RECORDED", "method": RECORDED_FIELDS, "fields": []}, []
    expected = acceptance["fields"]
    if "storedProof" in acceptance:
        graph, failing, unavailable = stored_proof(evidence, acceptance["storedProof"], record)
        result: dict[str, Any] = {"method": STORED_PROOF_GRAPH, "fields": sorted(expected), "graph": graph}
        if graph["proof"]["sha256"] is not None:
            result["source"] = {"path": acceptance["storedProof"]["proof"], "pointer": "", "sha256": graph["proof"]["sha256"]}
        if unavailable:
            result["status"] = "UNAVAILABLE"
            result["unavailable"] = unavailable
            return result, failing
        observed = graph["fields"]
    else:
        target, target_source = ((evidence.resolve(acceptance["source"])[:2]) if "source" in acceptance else (raw, source))
        observed = {name: _dotted(target, name) for name in expected}
        result = {"method": RECORDED_FIELDS, "fields": sorted(expected), "source": target_source}
        failing = []
    failing = failing + [f"acceptance field {name} does not hold" for name, value in expected.items()
                         if observed.get(name, _MISSING) != value]
    result["status"] = "FAILED" if failing else "CHECKED"
    return result, failing


def certificate_record(evidence: Evidence, profile: str, operation: str, spec: dict[str, Any],
                       identities: dict[str, dict[str, Any]], product: Path, worlds: dict[str, Any]) -> dict[str, Any]:
    raw, source, _ = evidence.resolve(spec["source"])
    fields = spec.get("fields", {})
    malformed = spec["outcome"] == "malformed"
    if malformed:
        require("slug" in spec, f"{profile}: a malformed certificate needs its slug")
        key = f"{profile}/MALFORMED/{spec['slug']}"
    else:
        key = f"{profile}/{operation}/{spec['outcome']}"
    record: dict[str, Any] = {"key": key, "profile": profile, "operation": operation, "outcome": spec["outcome"]}
    recorded_slug = raw.get("slug") if isinstance(raw, dict) else None
    if "slug" in spec or isinstance(recorded_slug, str):
        record["slug"] = spec.get("slug", recorded_slug)
    record.update({"form": spec["form"], "source": source, "problems": []})
    problems = record["problems"]
    if spec["form"] == "APR_PROOF":
        if "proofIdFromPath" in fields:
            text = str(field(raw, fields["proofIdFromPath"])).replace("\\", "/")
            marker = "/proofs/"
            require(marker in text and text.endswith("/proof.json"), f"{key}: proof path does not name a proof")
            record["proofId"] = text[text.rindex(marker) + len(marker):-len("/proof.json")]
        else:
            record["proofId"] = field(raw, fields["proofId"])
        record["proofSha256"] = field(raw, fields["proofSha256"])
        record["kcfgSha256"] = field(raw, fields["kcfgSha256"])
    else:
        record["boundary"] = field(raw, fields["boundary"])
        record["compoundIdentity"] = {name: field(evidence.resolve({"path": item["path"], "pointer": item["pointer"]})[0], name)
                                      for item in spec.get("identity", []) for name in item["fields"]}
    if isinstance(raw, dict):
        if malformed:
            if isinstance(recorded_slug, str) and recorded_slug != spec["slug"]:
                problems.append(f"recorded slug {recorded_slug} differs from the locator")
            if isinstance(raw.get("operation"), str) and raw["operation"] != "MALFORMED":
                problems.append(f"recorded operation {raw['operation']} is not MALFORMED")
        else:
            if isinstance(raw.get("outcome"), str):
                normalized = "applied" if raw["outcome"].lower() == "applied" else "not-applied"
                if normalized != spec["outcome"]:
                    problems.append(f"recorded outcome {raw['outcome']} differs from the locator")
            if isinstance(raw.get("operation"), str) and raw["operation"] != operation:
                problems.append(f"recorded operation {raw['operation']} differs from the locator")
            if isinstance(recorded_slug, str) and slug_cell(recorded_slug) != (operation, spec["outcome"]):
                problems.append(f"slug {recorded_slug} names another cell")
    record["acceptance"], failing = acceptance_record(evidence, spec, raw, source, record)
    problems += failing
    for corroboration in spec.get("corroborate", []):
        other, other_source, _ = evidence.resolve(corroboration["reference"])
        for name, dotted in corroboration["fields"].items():
            if record.get(name) != _dotted(other, dotted):
                problems.append(f"{name} disagrees with {other_source['path']}{other_source['pointer']}")
    record["execution"] = execution_record(evidence, spec["execution"], identities[profile], product, worlds)
    return record


def _dotted(value: Any, dotted: str) -> Any:
    current = value
    for part in dotted.split("."):
        if not isinstance(current, dict) or part not in current:
            return _MISSING
        current = current[part]
    return current


_MISSING = object()


# ---------------------------------------------------------------------------
# Registry
# ---------------------------------------------------------------------------

def check(identifier: str, failing: list[str], incomplete: list[str]) -> dict[str, Any]:
    status = "FAIL" if failing else "INCOMPLETE" if incomplete else "PASS"
    return {"id": identifier, "status": status, "detail": failing + incomplete}


def worst(statuses: list[str]) -> str:
    if not statuses:
        return "OPEN"
    for status in ("MISMATCH", "UNAVAILABLE"):
        if status in statuses:
            return status
    return "MATCH"


def consumer_findings(certificates: list[dict[str, Any]]) -> tuple[list[str], list[str]]:
    failing, incomplete = [], []
    for item in certificates:
        key = item["key"]
        for world in item["execution"]["preWorlds"]:
            role = world["role"]
            for entry in world["consumers"]:
                where = f"{entry['source']['path']}{entry['source']['pointer']}"
                if not entry["agrees"]:
                    failing.append(f"{key}: {role}: {where} records another world")
                if not entry["kindAgrees"]:
                    failing.append(f"{key}: {role}: {where} is not a {entry['kind']} record")
            for entry in world["links"]:
                if not entry["agrees"]:
                    failing.append(f"{key}: {role}: {entry['left']['path']}{entry['left']['pointer']} disagrees with "
                                   f"{entry['right']['path']}{entry['right']['pointer']}")
            declared = world.get("exportOnly")
            agreeing = [entry for entry in world["consumers"] if entry["agrees"] and entry["kindAgrees"]]
            if not agreeing:
                incomplete.append(f"{key}: {role} names no agreeing consumer")
            elif world["kernelStageInputs"] == 0 and declared is None:
                incomplete.append(f"{key}: {role} is named only by KORE exports and records no reason")
            if declared is not None:
                if not declared["applies"]:
                    failing.append(f"{key}: {role} declares a KORE-export-only reason but a kernel stage input names it")
                if not declared["quoteFound"]:
                    failing.append(f"{key}: {role}: the quoted reason is not in {declared['source']['path']}")
                if not declared["sameExecutedCodeAsConsumedWorld"]:
                    failing.append(f"{key}: {role} does not yield the executed code of a kernel-consumed world")
        if item["execution"]["kernelStageInputs"] == 0:
            incomplete.append(f"{key}: no recorded world of the certificate is named by a kernel stage input")
    return failing, incomplete


def build(evidence: Path, locators: dict[str, Any], mode: str, source: dict[str, Any] | None = None,
          product: Path = ROOT, reads: set[str] | None = None) -> dict[str, Any]:
    """Build the registry. `source` is the identity of the locator file; closure mode requires it."""
    schema = load_json(SCHEMA)
    errors = schema_errors(locators, schema["$defs"]["locators"], schema)
    require(not errors, "locator file violates its schema: " + "; ".join(errors[:10]))
    require(mode in {"dry-run", "closure"}, f"unknown mode {mode}")
    require(mode == "dry-run" or source is not None, "closure mode needs the identity of the locator file")
    store = Evidence(evidence)
    ledger, ledger_sha256 = store.load(locators["ledger"])
    identity_path, catalog_path = product / CODE_IDENTITY_PATH, product / MALFORMED_CATALOG_PATH
    identities = profile_identities(load_json(identity_path))
    catalog = load_json(catalog_path)
    catalogued = {CATALOG_PROFILES[item["profile"]]: sorted(item["slugs"]) for item in catalog["profiles"]}
    require(set(catalogued) == set(PROFILES), "the malformed catalog does not name the three profiles")
    cells = ledger_cells(ledger)
    worlds: dict[str, Any] = {}

    certificates, by_key, repeated = [], {}, []
    for cell in locators["cells"]:
        require((cell["profile"], cell["operation"]) in cells, f"locator names an undeclared cell: {cell['profile']}/{cell['operation']}")
        for spec in cell["certificates"]:
            require(spec["outcome"] != "malformed", "a cell certificate cannot be malformed")
            certificates.append(certificate_record(store, cell["profile"], cell["operation"], spec, identities, product, worlds))
    for branch in locators["malformed"]:
        for spec in branch["certificates"]:
            require(spec["outcome"] == "malformed", "a malformed branch certificate must have the malformed outcome")
            certificates.append(certificate_record(store, branch["profile"], "MALFORMED", spec, identities, product, worlds))
    for certificate in certificates:
        if certificate["key"] in by_key:
            repeated.append(certificate["key"])
        by_key[certificate["key"]] = certificate

    cell_records = []
    for profile in PROFILES:
        for operation in OPERATIONS:
            ledger_cell = cells[(profile, operation)]
            applied = by_key.get(f"{profile}/{operation}/applied")
            other = by_key.get(f"{profile}/{operation}/not-applied")
            kernels = [kernel_record(store, kernel) for kernel in ledger_cell["kernels"]] if applied or other else []
            problems = [problem for kernel in kernels for problem in kernel["problems"]]
            if applied and other and applied.get("kcfgSha256") and applied.get("kcfgSha256") == other.get("kcfgSha256"):
                problems.append("applied and not-applied certificates share one KCFG")
            if applied and other and applied["form"] == "COMPOUND_BOUNDARY" and applied.get("boundary") == other.get("boundary"):
                problems.append("applied and not-applied boundaries coincide")
            bound = bool(applied and other and kernels and not problems)
            if bound != (ledger_cell["status"] == "CLOSED"):
                problems.append(f"registry coverage {'BOUND' if bound else 'OPEN'} disagrees with ledger status {ledger_cell['status']}")
            cell_records.append({
                "profile": profile, "operation": operation,
                "profileIndex": identities[profile]["profileIndex"], "codeIdentityRootSha256": identities[profile]["root"],
                "ledgerStatus": ledger_cell["status"],
                "applied": applied["key"] if applied else None, "notApplied": other["key"] if other else None,
                "kernels": kernels,
                "executedCode": worst([item["execution"]["status"] for item in (applied, other) if item]),
                "coverage": "BOUND" if bound else "OPEN", "problems": problems,
            })

    malformed_records = []
    for profile in PROFILES:
        registered = [item for item in certificates if item["profile"] == profile and item["outcome"] == "malformed"]
        slugs = sorted(item["slug"] for item in registered)
        missing = sorted(set(catalogued[profile]) - set(slugs))
        unexpected = sorted(set(slugs) - set(catalogued[profile]))
        covered = bool(slugs) and not missing and not unexpected and len(slugs) == len(set(slugs))
        malformed_records.append({
            "profile": profile, "profileIndex": identities[profile]["profileIndex"],
            "catalogued": len(catalogued[profile]), "certificates": [item["key"] for item in registered],
            "missing": missing, "unexpected": unexpected,
            "executedCode": worst([item["execution"]["status"] for item in registered]),
            "coverage": "COVERED" if covered else "OPEN",
        })

    proofs = [item["proofId"] for item in certificates if item["form"] == "APR_PROOF"]
    kcfgs = [item["kcfgSha256"] for item in certificates if item["form"] == "APR_PROOF"]
    duplicates = sorted({value for value in proofs if proofs.count(value) > 1} | {value for value in kcfgs if kcfgs.count(value) > 1})
    consumed_failing, consumed_incomplete = consumer_findings(certificates)
    inconsistent = [f"{item['key']}: {problem}" for item in certificates for problem in item["problems"]]
    unaccepted = [f"{item['key']}: acceptance {item['acceptance']['status'].lower().replace('_', ' ')}"
                  for item in certificates if item["acceptance"]["status"] in {"NOT_RECORDED", "UNAVAILABLE"}]
    code_failing = [f"{item['key']}: {problem}" for item in certificates
                    for world in item["execution"]["preWorlds"] for problem in world["codeProblems"]]
    checks = [
        check("certificate-keys-unique", [f"repeated key {key}" for key in repeated], []),
        check("certificates-distinct", [f"shared proof or KCFG {value}" for value in duplicates], []),
        check("certificate-records-consistent", inconsistent, unaccepted),
        check("cells-agree-with-ledger-and-kernels",
              [f"{item['profile']}/{item['operation']}: {problem}" for item in cell_records for problem in item["problems"]], []),
        check("malformed-registered-as-catalogued",
              [f"{item['profile']}: unexpected {slug}" for item in malformed_records for slug in item["unexpected"]],
              [f"{item['profile']}: missing {slug}" for item in malformed_records for slug in item["missing"]]),
        check("executed-code-identity", code_failing,
              [f"{item['key']}: executed code UNAVAILABLE" for item in certificates if item["execution"]["status"] == "UNAVAILABLE"]),
        check("recorded-worlds-consumed", consumed_failing, consumed_incomplete),
    ]
    bound_cells = sum(1 for item in cell_records if item["coverage"] == "BOUND")
    complete = bound_cells == 27 and all(item["coverage"] == "COVERED" for item in malformed_records)
    failed = [item["id"] for item in checks if item["status"] == "FAIL"]
    unfinished = [item["id"] for item in checks if item["status"] == "INCOMPLETE"]
    if mode == "closure":
        require(complete, "closure mode needs every cell and every malformed branch")
        require(not failed and not unfinished, f"closure mode needs every check to pass: failing {failed}, incomplete {unfinished}")

    summaries = {}
    all_worlds = [world for item in certificates for world in item["execution"]["preWorlds"]]
    for profile in PROFILES:
        identity = identities[profile]
        mine = [item for item in certificates if item["profile"] == profile]
        worlds_of = [world for item in mine for world in item["execution"]["preWorlds"]]
        endpoint = identity["runtimes"][identity["endpoint"]]
        summaries[profile] = {
            "profileIndex": identity["profileIndex"], "endpoint": identity["endpoint"],
            "codeIdentityRootSha256": identity["root"],
            "endpointTemplate": {"sha256": endpoint["runtimeTemplate"]["sha256"], "bytes": endpoint["runtimeTemplate"]["bytes"],
                                 "immutableRanges": endpoint["immutableRanges"]},
            "executedRuntimes": {name: {"sha256": identity["runtimes"][name]["runtimeTemplate"]["sha256"],
                                        "bytes": identity["runtimes"][name]["runtimeTemplate"]["bytes"]}
                                 for name in identity["executed"]},
            "deploymentOnlyRuntimes": {name: {"sha256": identity["runtimes"][name]["runtimeTemplate"]["sha256"],
                                              "bytes": identity["runtimes"][name]["runtimeTemplate"]["bytes"],
                                              "accountsInRecordedWorlds": sum(len((world["runtimeSet"] or {}).get("deploymentOnly", {}).get(name, []))
                                                                              for world in worlds_of),
                                              "reason": DEPLOYMENT_ONLY_RUNTIMES[profile][name],
                                              "assumption": DEPLOYMENT_ASSUMPTION}
                                       for name in identity["deploymentOnly"]},
            "certificates": len(mine),
            "executedCodeMatches": sum(1 for item in mine if item["execution"]["status"] == "MATCH"),
            "recordedWorlds": len(worlds_of),
            "distinctExecutedCode": len({world["executedCodeSha256"] for world in worlds_of if "executedCodeSha256" in world}),
            "distinctImmutableValueSets": len({world["immutableValuesSha256"] for world in worlds_of if "immutableValuesSha256" in world}),
            "unboundAccountCounts": sorted({world["runtimeSet"]["unboundAccounts"] for world in worlds_of if world["runtimeSet"]}),
        }
    methods = {method: sum(1 for item in certificates if item["acceptance"]["method"] == method)
               for method in (RECORDED_FIELDS, STORED_PROOF_GRAPH)}
    registry = {
        "schema": REGISTRY_SCHEMA_ID,
        "status": ("FAIL_REGISTRY_INCONSISTENT" if failed else
                   "REGISTRY_COMPLETE_CANDIDATE" if complete and not unfinished else "DRY_RUN_INCOMPLETE"),
        "mode": mode,
        "inputs": {
            "ledger": {"root": "EVIDENCE", "path": locators["ledger"], "sha256": ledger_sha256},
            "codeIdentity": {"root": "PRODUCT", "path": CODE_IDENTITY_PATH, "sha256": sha256_file(identity_path)},
            "malformedCatalog": {"root": "PRODUCT", "path": MALFORMED_CATALOG_PATH, "sha256": sha256_file(catalog_path)},
            "locators": source,
        },
        "matchRule": MATCH_RULE,
        "runtimeSetRule": RUNTIME_SET_RULE,
        "consumerRule": CONSUMER_RULE,
        "graphRule": GRAPH_RULE,
        "profiles": summaries,
        "certificates": certificates,
        "cells": cell_records,
        "malformed": malformed_records,
        "partition": {
            "declaredCells": 27,
            "boundCells": bound_cells,
            "openCells": [f"{item['profile']}/{item['operation']}" for item in cell_records if item["coverage"] == "OPEN"],
            "malformedBranches": {item["profile"]: item["coverage"] for item in malformed_records},
            "registeredCertificates": len(certificates),
            "executedCodeMatches": sum(1 for item in certificates if item["execution"]["status"] == "MATCH"),
            "recordedWorlds": len(all_worlds),
            "worldsNamedByKernelStageInputs": sum(1 for world in all_worlds if world["kernelStageInputs"] > 0),
            "worldsNamedOnlyByKoreExports": sum(1 for world in all_worlds if world["kernelStageInputs"] == 0 and any(
                entry["kind"] == KORE_EXPORT and entry["agrees"] and entry["kindAgrees"] for entry in world["consumers"])),
            "acceptanceMethods": methods,
            "coverageComplete": complete,
            "meaning": (
                "Coverage says which cells have a registered applied and not-applied certificate pair agreeing with the "
                "ledger and a PASS kernel run, and which profiles have every catalogued request outside canonical form "
                "registered. Executed code says which certificates ran the executed runtime set of their profile. This "
                "is the finite data of the acceptance partition, not the partition theorem, which a kernel run over the "
                "whole registry must still prove."
            ),
        },
        "checks": checks,
        "retainedAssumptions": dict(RETAINED_ASSUMPTIONS),
        "nonclaim": NONCLAIM,
    }
    if reads is not None:
        reads.update(store.reads)
    return registry


def locator_identity(path: Path) -> dict[str, Any]:
    return {"sha256": sha256_file(path), "bytes": path.stat().st_size}


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    build_parser = commands.add_parser("build")
    build_parser.add_argument("--evidence", type=Path, required=True)
    build_parser.add_argument("--locators", type=Path, required=True)
    build_parser.add_argument("--output", type=Path, required=True)
    build_parser.add_argument("--mode", default="dry-run", choices=("dry-run", "closure"))
    build_parser.add_argument("--product-root", type=Path, default=ROOT)
    verify_parser = commands.add_parser("verify")
    verify_parser.add_argument("--evidence", type=Path, required=True)
    verify_parser.add_argument("--locators", type=Path, required=True)
    verify_parser.add_argument("--registry", type=Path, required=True)
    verify_parser.add_argument("--product-root", type=Path, default=ROOT)
    args = parser.parse_args(argv)
    locators = load_json(args.locators)
    source = locator_identity(args.locators)
    product = args.product_root.resolve()
    if args.command == "build":
        output = args.output.resolve()
        require(not output.exists(), "registry output already exists")
        require(not any(output.is_relative_to((root / part).resolve()) for root in {ROOT, product} for part in ("evidence", "scripts")),
                "the registry is private evidence and is never written into the tracked tree")
        registry = build(args.evidence, locators, args.mode, source, product)
        require_schema(registry, load_json(SCHEMA), "registry")
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(dump_json(registry), encoding="utf-8", newline="\n")
    else:
        recorded = load_json(args.registry)
        registry = build(args.evidence, locators, recorded["mode"], source, product)
        require(json.dumps(registry, sort_keys=True) == json.dumps(recorded, sort_keys=True),
                "registry recomputation differs from the recorded registry")
    print(json.dumps({"status": registry["status"], "boundCells": registry["partition"]["boundCells"],
                      "malformed": registry["partition"]["malformedBranches"],
                      "certificates": registry["partition"]["registeredCertificates"],
                      "executedCodeMatches": registry["partition"]["executedCodeMatches"],
                      "acceptanceMethods": registry["partition"]["acceptanceMethods"],
                      "checks": {item["id"]: item["status"] for item in registry["checks"]}}, indent=2))
    return 0 if not registry["status"].startswith("FAIL") else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except PreparationError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
