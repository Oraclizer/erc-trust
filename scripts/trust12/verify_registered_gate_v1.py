#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Check the public record of the kernel runs that instantiate the registered gate and, with the saved session
databases, recompute it.

Metadata mode, which the required gate runs, reads tracked files only. It checks that the record is the reviewed one,
that the quoted closure acceptance criteria are the current ones, that the certificate list is the list of the public
certificate registry record, that the session databases and sources that other public records also name carry the same
hashes there, that the product formal theories that the runs read are the current ones, and it recomputes every
criterion of the record from the quoted statements and the audit rows.

Saved mode additionally rehashes the private artifacts named through a private index: the completed kernel session
databases, the run results, input snapshots and build logs, and the private certificate registry. It reads every
theory source from the database that stored it, finds each quoted definition and theorem in those sources with the
same text and context, rereads the audit and checkpoint markers that the kernel printed, follows the parent heap of
every session, rehashes every input file that each run recorded, and requires the whole derived part of the record to
equal this record. Neither mode runs a prover.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import lzma
from pathlib import Path, PurePosixPath
import re
import sqlite3
import subprocess
import sys

CHECKPOINT_PATH = "evidence/trust12/runtime-link/tail-preparation/registered-gate-checkpoint-v1.json"
VERIFIER_PATH = "scripts/trust12/verify_registered_gate_v1.py"
CONDITIONS_PATH = "evidence/trust12/runtime-link/tail-preparation/tail-obligations-v1.json"
REGISTRY_RECORD = "evidence/trust12/runtime-link/tail-preparation/certificate-registry-checkpoint-v1.json"
ALIGNED_RECORD = "evidence/trust12/runtime-link/malformed/aligned-gate-checkpoint-v1.json"
READER_RECORD = "evidence/trust12/runtime-link/tail-preparation/storage-reader-checkpoint-v1.json"
ALIAS_RECORD = "evidence/trust12/runtime-link/malformed/outofspec-v7-alias-core-equivalence-checkpoint-v1.json"
CROSS_RECORDS = (REGISTRY_RECORD, ALIGNED_RECORD, READER_RECORD, ALIAS_RECORD)
COMMAND = ("python3 " + VERIFIER_PATH + " --product-root <product-root> "
           "--artifact-index <private-artifact-index.json>")
SCHEMA = "trust12-registered-gate-checkpoint-v1"
STATUS = "PASS_KERNEL_CHECKED_REGISTERED_GATE"
EXPECTED_EVIDENCE_DIGEST = '28a237d90bb4eacc56b65c1813f02ac8465932b19371ca483f2bcbd3dedb1733'

# The sessions of the record in kernel order. Each completed session is the parent of the next one; the anchor is the
# parent of the first session and is the database that the aligned gate record names as its Hook value stage.
SESSIONS = ("session-partial-worlds-1", "session-partial-worlds-2", "session-partial-worlds-3",
            "session-partial-worlds-4", "session-hook-worlds-1", "session-hook-worlds-2", "session-hook-worlds-3",
            "session-hook-worlds-4", "session-reader-cells", "session-gate-common", "session-partial-part",
            "session-hook-part", "session-adapter-canonical", "session-native-part", "session-gate-instance",
            "session-native-canonical")
ANCHOR = "session-anchor"
ANCHOR_SAME_AS = {"record": ALIGNED_RECORD, "artifact": "hook-value-database"}
# Ancestor sessions of the anchor whose stored sources hold the predicates that the gate is built from.
ANCESTORS = ("ancestor-partition-definitions", "ancestor-checker-definitions", "ancestor-cell-definitions")
DATABASES = (ANCHOR, *ANCESTORS, *SESSIONS)
FINAL_AUDIT_SESSIONS = ("session-reader-cells", "session-adapter-canonical", "session-native-canonical")
REGISTRY_LIST_SESSION = "session-gate-common"
PROFILES = ("Native", "Partial", "Hook")
FORWARD = ("FREEZE", "SEIZE", "CONFISCATE", "RECOVER", "RESTRICT", "LIQUIDATE")
REVERSE = ("UNFREEZE", "RELEASE", "UNRESTRICT")

# Statement roles: role -> (session that stores it, kind). The record names the declaration of each role; saved mode
# finds it with the quoted text in the sources that the session stored.
ROLES = {
    "acceptance-partition-predicate": ("ancestor-partition-definitions", "definition"),
    "checker-soundness-predicate": ("ancestor-checker-definitions", "definition"),
    "abi-checker": ("ancestor-checker-definitions", "definition"),
    "abi-checker-sound": ("ancestor-checker-definitions", "theorem"),
    "enforced-cell-predicate": ("ancestor-cell-definitions", "definition"),
    "registry-set": ("session-gate-common", "definition"),
    "registry-size": ("session-gate-common", "theorem"),
    "registry-distinct": ("session-gate-common", "theorem"),
    "gate-predicate": ("session-gate-common", "definition"),
    "malformed-branch-predicate": ("session-gate-common", "definition"),
    "registered-requests-predicate": ("session-gate-common", "definition"),
    "gate-from-parts": ("session-gate-common", "theorem"),
    "gate-gives-parts": ("session-gate-common", "theorem"),
    "gate-context": ("session-gate-instance", "locale"),
    "profile-manifests": ("session-gate-instance", "definition"),
    "profile-checkers": ("session-gate-instance", "definition"),
    "accepted-set": ("session-gate-instance", "definition"),
    "registered-requests": ("session-gate-instance", "definition"),
    "gate-instance": ("session-gate-instance", "theorem"),
    "certificate-removal": ("session-gate-instance", "theorem"),
    "accepted-set-is-image": ("session-gate-instance", "theorem"),
    "registered-certificates-accepted": ("session-gate-instance", "theorem"),
    "acceptance-partition": ("session-gate-instance", "theorem"),
    "registry-partition": ("session-gate-instance", "theorem"),
    "native-part": ("session-native-part", "theorem"),
    "partial-part": ("session-partial-part", "theorem"),
    "hook-part": ("session-hook-part", "theorem"),
    "native-part-removal": ("session-native-part", "theorem"),
    "partial-part-removal": ("session-partial-part", "theorem"),
    "hook-part-removal": ("session-hook-part", "theorem"),
    "native-code-pins": ("session-native-part", "theorem"),
    "partial-code-pins": ("session-partial-part", "theorem"),
    "hook-code-pins": ("session-hook-part", "theorem"),
    "native-pinned-runtime": ("session-native-canonical", "theorem"),
    "native-product-spec": ("session-native-canonical", "theorem"),
    "partial-product-spec": ("session-adapter-canonical", "theorem"),
    "hook-product-spec": ("session-adapter-canonical", "theorem"),
}
# The restated cell theorems and the restated enforced relations of the two registered executions of every Partial
# and Hook cell, from which the cell theorems are proved; the profile parts consume the execution relations.
RESTATED_SESSION = "session-reader-cells"
RESTATED_ROLES = {"restated-cell": 18, "restated-execution": 36}
RESTATED_CONSUMED = "restated-execution"
RESTATED_CONSUMERS = {"Partial": "session-partial-part", "Hook": "session-hook-part"}
CRITERIA = ("gate-instantiated-over-the-registered-image", "every-certificate-removal-breaks-the-instantiation",
            "partition-over-the-whole-registry", "applied-and-not-applied-witness-in-every-cell",
            "failure-checkers-sound", "malformed-branch-over-the-registered-requests",
            "accepted-executions-pin-profile-code", "cells-over-storage-reading-manifests",
            "hash-equations-remain-locale-assumptions", "no-oracle-and-no-skipped-proof",
            "cell-theorems-without-evaluation")
SCOPE = (
    "Kernel runs instantiate the twenty-seven-cell gate of the runtime link over the three profiles with the accepted "
    "set of each profile defined as the image of its registered certificates. The certificate list of the gate is the "
    "list of the certificate registry, 96 certificates (Native 34, Partial 31, Hook 31): one applied and one "
    "not-applied certificate for each of the twenty-seven profile and operation cells and one certificate for each "
    "registered request outside canonical form (Native 16, Partial 13, Hook 13). The gate theorem states, for the "
    "storage-reading manifests of the three profiles, sound typed failure checkers, the acceptance partition, the "
    "bound and the enforced relation for every accepted execution of every cell with an applied and a not-applied "
    "witness in each cell, the aligned malformed branch of every profile, and the acceptance of every registered "
    "request outside canonical form. A second theorem states that removing any one of the 96 certificates from the "
    "registry makes the gate false, and a third that the accepted set partitions over the whole registry. Each "
    "profile part also states that every accepted execution runs the code that the profile manifest pins at the "
    "accounts of its footprint and that the accepted set refines the product specification. The Partial and Hook cells "
    "of the gate are built from the restated enforced relations of the applied and the not-applied registered "
    "execution of each cell over the storage-reading manifests of those profiles, the facts from which the eighteen "
    "restated cell theorems are proved. Kernel audits find no oracle and no skipped proof in any audited theorem of the "
    "three runs, among them the gate theorems and the restated cell theorems.")
GATE_BOUNDARY = (
    "The gate theorems are theorems of one locale that joins the hash contexts of the three profiles. Its assumptions "
    "are the recorded hash equations of every theorem context (a hash function parameter applied to each recorded "
    "preimage gives the recorded value, and every value is a 256-bit word), bounds of the recorded timestamp variables, "
    "and the equation of a word encoding parameter with the big-endian encoding; the gas limits are parameters. No "
    "kernel theorem instantiates this locale: the theorems hold for every hash function and valuation that satisfy the "
    "assumptions, and that the hash function is Keccak-256 on the recorded preimages is the retained assumption "
    "A-KECCAK. Each adapter profile also defines a table function that satisfies its recorded hash equations; that "
    "check uses evaluation, and no audited theorem of this record depends on it, because every such theorem is free of "
    "oracles while a theorem instantiated with the table function depends on the evaluation oracle. The five "
    "conditional reader facts of the Hook stages are facts of the same Hook hash context and are not separate "
    "assumptions here. The gate predicate joins predicates of the earlier gate stages: sound typed failure checkers, "
    "the partition of the accepted executions into requests outside canonical form and the cells of the nine "
    "operations, and for every cell the bound and the enforced relation of each accepted execution together with an "
    "applied execution and a rejected or operational execution. The enforced relation itself, with its typed rejection "
    "and dependency revert rules, is the relation of those stages and is not restated here.")
MODEL_BOUNDARY = (
    "The runs read one copy of the public formal theories. All of them equal the current product theories except two: "
    "the out-of-specification theory, whose eight core definitions the existing alias checkpoint proves equivalent to "
    "the current ones and whose read copy is the pinned model of the aligned gate record, and the generated obligation "
    "ledger theory, which was regenerated later and which this record does not compare. Each certificate of the gate "
    "denotes the execution that the earlier kernel stages define from the recorded worlds, requests and results of "
    "that certificate; the record binds the certificate list to the registry by key and order, and the certificate "
    "registry binds each certificate to the worlds that kernel stages consumed. Status, revert output and calldata of a "
    "registered request outside canonical form are received values bound to its record, and its gas limit and external "
    "call list are supplied, as the aligned gate record states.")
REGISTRY_BOUNDARY = (
    "The certificate list of the gate equals the list of the private certificate registry that the certificate "
    "registry record names, key for key and in its order, and the registry record keys the same 96 certificates. The "
    "registry record cites, as the kernel results of the Partial and Hook cells, the earlier cell theorems that rest on "
    "code evaluation; the gate takes those cells from the restated relations of the same registered executions "
    "instead, which hold over the storage-reading manifests and depend on no oracle. The registry record is unchanged "
    "by this record, so it still names the earlier stages until it is rebuilt. The Native cells of the gate move the "
    "enforced relations of the earlier Native stages to one manifest and one bridge without restating them.")
CONDITION_BOUNDARY = (
    "This record is evidence for the kernel-run criteria that it quotes from the conditions list. For the "
    "twenty-seven-cell architecture: a kernel run instantiates the gate with the accepted set defined as the image of "
    "the registered certificates, and removing any registered certificate breaks that instantiation; that the registry "
    "builds in closure mode is the certificate registry record. For the accepted set: the accepted set is defined in a "
    "kernel run as the image of the registered certificates and the partition theorem is proved over the whole "
    "registry; that the registry covers every cell and malformed branch and binds every certificate to its program "
    "identity is the certificate registry record, and this record shows only that the gate lists exactly the registry "
    "keys. For each malformed branch: a kernel run proves the malformed branch over the registered requests outside "
    "canonical form; their registration is the certificate registry record, and the guard mutants and the probe rerun "
    "are other records. For the enforced cell witnesses this "
    "record adds only the kernel half of the profile index: every accepted execution runs the code that the profile "
    "manifest pins at its footprint accounts, which are the endpoint and token accounts; that this code equals the "
    "registry code identity is a computation of the certificate registry and is not a kernel theorem, and the governor "
    "and compliance accounts are bound by the registry alone. For the conditions on preservation and on state and "
    "receipt identity this record supplies the relation of every registered execution, including the decoded calldata, "
    "receipt logs and returned receipt hash that the bridge reads, but none of their acceptance criteria.")
REPRODUCTION_BOUNDARY = (
    "Metadata mode reads tracked files only. It checks that this record is the reviewed one, that the quoted criteria "
    "are the current ones, that the certificate keys and the private registry hash are those of the certificate registry "
    "record, that the session databases and sources that the storage reader and aligned gate records also name carry "
    "the same hashes there, and that the formal theories marked current are the current product files, and it recomputes "
    "every criterion from the quoted statements and audit rows. Saved mode additionally rehashes the private artifacts "
    "named through a private index, reads every source from the session database that stored it, finds each quoted "
    "statement there with its context, rereads the kernel markers and audits, follows the parent heap of every session, "
    "rehashes every input file that each run recorded and requires the derived part of the record to equal this record. "
    "Neither mode runs a prover, and the record states no completion of the registered-scope central closure, any "
    "general runtime link, the independent Assurance or TRUST 1.2.")
EVIDENCE_FOR = (
    {"condition": "twenty-seven-cell-architecture", "supported": [2, 3],
     "clauses": ["The 27-cell gate holds for one accepted set per profile"]},
    {"condition": "accepted-set-is-certificate-image", "supported": [1, 3],
     "clauses": ["The accepted set of each profile is the image of a checked K/KEVM certificate decoder"]},
    {"condition": "malformed-native", "supported": [2], "clauses": []},
    {"condition": "malformed-partial", "supported": [2], "clauses": []},
    {"condition": "malformed-hook", "supported": [2], "clauses": []},
    {"condition": "enforced-cell-witnesses", "supported": [], "clauses": ["a profile index tied to a code identity"]},
    {"condition": "preservation-and-reflection", "supported": [],
     "clauses": ["Abstract allowed behavior is preserved by the final code"]},
    {"condition": "state-and-receipt-identity", "supported": [], "clauses": ["ABI, events and return data"]},
)
RETAINED_ASSUMPTIONS = {
    "A-KECCAK": ("The gate theorems hold in a locale whose hash function parameter satisfies the recorded preimage "
                 "equations of every theorem context; that this function is Keccak-256 on those preimages is assumed.")}
NONCLAIM_KEYS = ("assumptionSatisfiabilityInKernel", "keccakIdentity", "unregisteredExecutions", "generalRuntimeLinks",
                 "registryNamesRestatedCells", "codeIdentityInKernel", "governorAndComplianceCode",
                 "enforcedRelationRestated", "proverRerun", "registeredCentralClosure", "independentAssurance",
                 "fullTrustCompletion", "releaseOrDeployment")
PUBLIC_KEYS = {"schema", "status", "scope", "gateBoundary", "modelBoundary", "registryBoundary", "conditionBoundary",
               "reproductionBoundary", "evidenceFor", "criteria", "coverage", "registry", "statements", "audits",
               "modelIdentity", "kernelRuns", "kernelSessions", "artifacts", "retainedAssumptions", "rehashVerifier",
               "nonclaims"}
RUN_ROLES = (("result", "kernel-build-result"), ("inputs-before", "proof-input-snapshot"),
             ("inputs-after", "proof-input-snapshot"), ("build-log", "kernel-build-log"))
HEX64 = re.compile(r"[0-9a-f]{64}")
RUN_ID = re.compile(r"[a-z][a-z0-9-]{2,40}-run")
PRIVATE = re.compile(r"(?i)[A-Za-z]:[\\/]|/mnt/|/h[o]me/|/U[s]ers/|\\\\|~/|\bG[1-9][0-9]*\b|\b(?:FV|RL)-?[0-9]+\b")
PROCESS_LABEL = re.compile(r"(?<![A-Za-z0-9_])E-?[0-9][a-c]?(?![A-Za-z0-9_])")
PROSE_KEYS = ("scope", "gateBoundary", "modelBoundary", "registryBoundary", "conditionBoundary", "reproductionBoundary")
PASS_MARKER = re.compile(r"PASS_[A-Z0-9_]+_ORACLE_ZERO_SKIP_FALSE")
WRITELN = re.compile("\x06writeln_message(?:\x06[^\x05]*)*\x05([^\x05]*)\x05")
FORBIDDEN = re.compile(r"\b(?:sorry|oops|admit|axiomatization|axioms|native_decide|eval|code_simp|normalization|nbe|"
                       r"interpretation|global_interpretation|sublocale|interpret|quick_and_dirty)\b|(?m:^\s*oracle\b)")
PROOF_START = re.compile(r"(?:by|proof|using|unfolding|apply|including|supply)\b")


class CheckError(RuntimeError):
    pass


def require(condition, message):
    if not condition:
        raise CheckError(message)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def read_json(path):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, "Duplicate JSON key")
            result[key] = value
        return result
    value = json.loads(Path(path).read_text(encoding="utf-8-sig"), object_pairs_hook=unique)
    require(isinstance(value, (dict, list)), "JSON value required")
    return value


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True, allow_nan=False).encode("utf-8")


def same_json(left, right):
    return canonical(left) == canonical(right)


def payload_digest(checkpoint):
    return sha256(canonical({key: value for key, value in checkpoint.items() if key != "rehashVerifier"}))


def collapse(text):
    """Statement text on one line, with every Isabelle symbol written without its leading backslash."""
    result = " ".join(text.split()).replace("\\<", "<")
    require("\\" not in result, "Statement text holds a backslash")
    return result


def unquote(text):
    """A statement that is one quoted term, without its quotes; a structured statement as it is."""
    return text[1:-1] if len(text) >= 2 and text[0] == text[-1] == '"' and text.count('"') == 2 else text


def file_identity(product, relative):
    path = (product / relative).resolve()
    require(path.is_file() and path.is_relative_to(product), "Missing product file: " + relative)
    return {"path": relative, "bytes": path.stat().st_size, "sha256": digest(path)}


# ----------------------------------------------------------------------------------------------------------------
# Certificate keys
# ----------------------------------------------------------------------------------------------------------------
def certificate_key(item):
    """The registry key of one item of the kernel registry list: a cell (profile, direction, operation, side) or a
    registered request outside canonical form (profile, request class)."""
    parts = item.split(":")
    require(len(parts) in (3, 5) and all(re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", part) for part in parts),
            "Kernel registry item differs: " + item)
    profile = parts[1].split("_", 1)[-1]
    require(parts[1].count("_") == 1 and profile in PROFILES, "Kernel registry profile differs: " + item)
    if len(parts) == 3:
        request = parts[2].split("_", 1)
        require(len(request) == 2, "Kernel registry request class differs: " + item)
        return parts[0], profile + "/MALFORMED/" + request[1].lower().replace("_", "-")
    direction, operation, side = parts[2], parts[3].split("_", 1), parts[4]
    require(len(operation) == 2, "Kernel registry operation differs: " + item)
    name = operation[1].upper()
    require((direction.endswith("_Forward") and name in FORWARD) or (direction.endswith("_Reverse") and name in REVERSE),
            "Kernel registry direction differs: " + item)
    outcome = "not-applied" if side.endswith("_Not_Applied") else "applied" if side.endswith("_Applied") else None
    require(outcome is not None, "Kernel registry side differs: " + item)
    return parts[0], profile + "/" + name + "/" + outcome


def keys_from_registry_list(line):
    match = re.fullmatch(r"[A-Z][A-Z0-9_]*_REGISTRY_LIST count=([0-9]+) items=(\S*)", line)
    require(match is not None, "Kernel registry list differs")
    items = match.group(2).split(";") if match.group(2) else []
    require(len(items) == int(match.group(1)), "Kernel registry list count differs")
    pairs = [certificate_key(item) for item in items]
    constructors = {kind for kind, key in pairs if "/MALFORMED/" not in key}, \
        {kind for kind, key in pairs if "/MALFORMED/" in key}
    require(all(len(kinds) == 1 for kinds in constructors) and constructors[0] != constructors[1],
            "Kernel registry constructors differ")
    keys = [key for _, key in pairs]
    require(len(set(keys)) == len(keys), "Kernel registry list repeats a certificate")
    return keys


def key_coverage(keys):
    """Counts that follow from the certificate keys."""
    cells = {}
    for key in keys:
        profile, operation, outcome = key.split("/")
        if operation != "MALFORMED":
            cells.setdefault((profile, operation), set()).add(outcome)
    return {"registeredCertificates": {p: sum(1 for k in keys if k.startswith(p + "/")) for p in PROFILES},
            "certificateRemovals": {p: sum(1 for k in keys if k.startswith(p + "/")) for p in PROFILES},
            "cells": len(cells),
            "cellWitnesses": {"applied": sum(1 for s in cells.values() if "applied" in s),
                              "notApplied": sum(1 for s in cells.values() if "not-applied" in s)},
            "malformedRequests": {p: sum(1 for k in keys if k.startswith(p + "/MALFORMED/")) for p in PROFILES}}


# ----------------------------------------------------------------------------------------------------------------
# Session databases
# ----------------------------------------------------------------------------------------------------------------
def decompress(raw, decoder=None):
    if raw.startswith(b"\xfd7zXZ\x00"):
        return lzma.decompress(raw)
    require(raw.startswith(b"\x28\xb5\x2f\xfd"), "Unknown stored compression")
    try:
        from compression import zstd  # Python 3.14 and later
        return zstd.decompress(raw)
    except ImportError:
        require(decoder is not None, "A zstd decompressor is required")
        return subprocess.run([decoder, "-d", "-q", "--stdout"], input=raw, check=True, capture_output=True,
                              timeout=120).stdout


def query(path, sql):
    connection = sqlite3.connect(Path(path).resolve().as_uri() + "?mode=ro&immutable=1", uri=True)
    try:
        return connection.execute(sql).fetchall()
    finally:
        connection.close()


def heap_lines(value, label):
    require(isinstance(value, str) and value.strip(), "Heap list missing: " + label)
    rows = []
    for line in value.splitlines():
        match = re.fullmatch(r"([0-9a-f]{40}) ([A-Za-z][A-Za-z0-9_]*)", line)
        require(match is not None, "Heap line differs: " + label)
        rows.append((match.group(1), match.group(2)))
    return rows


def session_database(path, decoder=None):
    """A completed session database: its name, parent heaps, output heap, stored sources and printed messages."""
    rows = query(path, "select session_name, return_code, errors, input_heaps, output_heap from isabelle_session_info")
    require(len(rows) == 1 and rows[0][1] == 0 and rows[0][2] is None, "Session database is not a completed session")
    name, _, _, inputs, output = rows[0]
    outputs = heap_lines(output, "output")
    require(len(outputs) == 1 and outputs[0][1] == name, "Output heap differs from the session")
    sources = []
    for source_name, source_digest, compressed, body in query(path, "select name, digest, compressed, body "
                                                                     "from isabelle_sources"):
        data = decompress(bytes(body), decoder) if compressed else bytes(body)
        require(hashlib.sha1(data).hexdigest() == source_digest, "Stored source differs from its digest")
        sources.append({"name": str(source_name), "data": data, "sha256": sha256(data), "bytes": len(data)})
    messages = {}
    for theory, compressed, body in query(path, "select theory_name, compressed, body from isabelle_exports "
                                                "where name = 'PIDE/messages'"):
        text = (decompress(bytes(body), decoder) if compressed else bytes(body)).decode("utf-8")
        messages[str(theory)] = {"bodies": WRITELN.findall(text), "error": "\x06error_message" in text}
    return {"name": name, "inputs": heap_lines(inputs, "input"), "output": outputs[0], "sources": sources,
            "messages": messages}


def strip_comments(source):
    """The source with every (possibly nested) comment blanked, line structure kept."""
    pieces, cursor = [], 0
    while True:
        start = source.find("(*", cursor)
        if start < 0:
            pieces.append(source[cursor:])
            return "".join(pieces)
        pieces.append(source[cursor:start])
        depth, position = 1, start + 2
        while depth:
            opening, closing = source.find("(*", position), source.find("*)", position)
            require(closing >= 0, "Unclosed source comment")
            if 0 <= opening < closing:
                depth, position = depth + 1, opening + 2
            else:
                depth, position = depth - 1, closing + 2
        pieces.append(re.sub(r"[^\n]", " ", source[start:position]))
        cursor = position


_PARSED = {}


def parsed(source):
    """Code text, lines, theory name, line contexts and declaration heads of a stored source, by its hash."""
    key = source["sha256"]
    if key not in _PARSED:
        text = code_text(source["data"].decode("utf-8"))
        lines = text.split("\n")
        heads = {}
        for index, line in enumerate(lines):
            match = re.match(r"(?:theorem|lemma|corollary|definition|locale|primrec|fun|abbreviation)\s+"
                             r"([A-Za-z][A-Za-z0-9_']*)(?=[\s:]|$)", line)
            if match:
                heads.setdefault(match.group(1), []).append(index)
        _PARSED[key] = {"text": text, "lines": lines, "theory": theory_name(text), "contexts": contexts(lines),
                        "heads": heads}
    return _PARSED[key]


def code_text(source):
    """Source text without comments and prose blocks, line structure kept."""
    text = strip_comments(source)
    return re.sub(r"(?s)\b(?:text|txt|section|subsection|subsubsection|chapter|paragraph)\s*\\<open>.*?\\<close>",
                  lambda match: re.sub(r"[^\n]", " ", match.group(0)), text)


def theory_name(text):
    match = re.search(r"(?m)^theory\s+([A-Za-z][A-Za-z0-9_]*)\s*$", text)
    require(match is not None, "Theory header missing")
    return match.group(1)


def contexts(lines):
    """The locale context of every line: context NAME followed by begin opens, a column-zero end closes."""
    stack, result, previous = [], [], None
    for line in lines:
        stripped = line.strip()
        result.append(stack[-1] if stack else None)
        if stripped == "begin" and previous is not None and re.fullmatch(r"context\s+[A-Za-z][A-Za-z0-9_]*", previous):
            stack.append(previous.split()[1])
        elif line.rstrip() == "end" and stack:
            stack.pop()
        if stripped:
            previous = stripped
    return result


def declarations(lines, base, indices):
    """Every declaration of BASE at the given line indices of a source: (kind, line index, statement text)."""
    found = []
    for index in indices:
        line = lines[index]
        match = re.match(r"(theorem|lemma|corollary|definition|locale|primrec|fun|abbreviation)\s+"
                         + re.escape(base) + r"(?=[\s:]|$)", line)
        require(match is not None, "Declaration head differs: " + base)
        kind = {"lemma": "theorem", "corollary": "theorem"}.get(match.group(1), match.group(1))
        if kind == "theorem":
            body = [line[match.end():].lstrip()[1:] if line[match.end():].lstrip().startswith(":") else
                    line[match.end():]]
            for following in lines[index + 1:]:
                if PROOF_START.match(following.strip()) or not following.strip():
                    break
                body.append(following)
            found.append((kind, index, unquote(collapse("\n".join(body)))))
        elif kind == "definition":
            rest = "\n".join(lines[index:index + 400])
            where = re.search(r"\bwhere\s*\"((?:[^\"\\]|\\.)*)\"", rest, re.S)
            require(where is not None, "Definition body missing: " + base)
            found.append((kind, index, collapse(where.group(1))))
        elif kind == "locale":
            expression = line[match.end():].strip()
            require(expression.startswith("="), "Locale expression missing: " + base)
            found.append((kind, index, collapse(expression[1:])))
        else:
            found.append((kind, index, None))
    return found


def locate(statement, sources):
    """Find the declaration of a quoted statement in the stored sources: exactly one declaration of its base name,
    of its kind, in the theory or locale context that its qualified name names, with the quoted text."""
    qualifier, _, base = statement["name"].rpartition(".")
    require(qualifier and base, "Statement name is not qualified: " + statement["name"])
    hits = []
    for source in sources:
        info = parsed(source)
        if base not in info["heads"]:
            continue
        for kind, index, body in declarations(info["lines"], base, info["heads"][base]):
            hits.append((kind, body, info["theory"], info["contexts"][index]))
    require(len(hits) == 1, "Statement is not declared exactly once: " + statement["name"])
    kind, body, theory, context = hits[0]
    require(kind == statement["kind"], "Statement kind differs: " + statement["name"])
    require(qualifier in (theory, context) and (context is None or qualifier == context),
            "Statement context differs: " + statement["name"])
    return body


def static_problems(sources):
    problems = []
    for source in sources:
        match = FORBIDDEN.search(parsed(source)["text"])
        if match:
            problems.append(source["sha256"][:12] + ": " + match.group(0).strip())
    return problems


def marker_problems(bodies):
    problems = []
    rules = (("oracles", "0"), ("cell_oracles", "0"), ("missing", "0"), ("joined", "true"), ("still_active", "0"),
             ("different", "0"), ("skip", "false"))
    for body in bodies:
        if "FAILED_JOIN" in body:
            problems.append("failed join: " + body[:80])
        for key, value in rules:
            for found in re.findall(r"(?<![A-Za-z0-9_])" + key + r"=(\S*)", body):
                if found != value:
                    problems.append(key + "=" + found + ": " + body[:80])
    return problems


def audit_counts(bodies):
    rows = []
    for body in bodies:
        match = re.search(r"(?<![A-Za-z0-9_])ROOT_COUNT=([0-9]+)(?: NAME_COUNT=([0-9]+))?", body)
        if match:
            rows.append({"rootCount": int(match.group(1)),
                         "nameCount": int(match.group(2)) if match.group(2) else None})
    return sorted(rows, key=lambda row: (row["rootCount"], row["nameCount"] or 0))


def ml_string_lists(text):
    return [re.findall(r'"([^"\\]*)"', body) for body in re.findall(r"(?s)\bval\s+[A-Za-z0-9_']+\s*=\s*\[(.*?)\];",
                                                                       text)]


# ----------------------------------------------------------------------------------------------------------------
# Derivation from the private artifacts (saved mode and writer)
# ----------------------------------------------------------------------------------------------------------------
def suffix_key(stored_name):
    """The stored source name without its home prefix, matched against recorded input paths."""
    name = stored_name.replace("\\", "/")
    return name[1:] if name.startswith("~/") else name


def normalized(path):
    return path.replace("\\", "/")


def check_run_result(result, names, databases, label):
    require(isinstance(result, dict) and result.get("schema") == "trust12-final-chain-stage-result-v1"
            and result.get("dryRun") is False and type(result.get("exitCode")) is int and result["exitCode"] == 0
            and result.get("target") == names[-1] and result.get("status") == "PASS_FINAL_CHAIN_STAGE_BUILT_" + names[-1]
            and result.get("inputsUnchanged") is True and result.get("changedInputPaths") == []
            and result.get("expectedNewSessions") == result.get("builtSessions") == result.get("finishedSessions") == names
            and result.get("failedSessions") == result.get("cancelledSessions") == result.get("dryRunWouldBuild") == []
            and result.get("missingArtifacts") == [] and result.get("runOutOfStore") is False
            and same_json(result.get("compactPolyReceipts"), {"count": len(names), "valid": True})
            and [row.get("session") for row in result.get("sessions", [])] == names,
            "Kernel run result is not a complete passing run: " + label)
    for row, database in zip(result["sessions"], databases):
        require(row.get("database") == {"bytes": database["bytes"], "sha256": database["sha256"]},
                "Run result names another session database: " + label)


def check_build_log(data, names, label):
    text = data.decode("utf-8", errors="replace")
    require(re.findall(r"(?m)^Building (\S+) \.\.\.", text) == names
            and re.findall(r"(?m)^Finished (\S+) \(", text) == names, "Build log launch set differs: " + label)


def check_inputs(before, after, stored, checked, label):
    require(isinstance(before, list) and before and same_json(before, after), "Input snapshot changed: " + label)
    rows = []
    for row in before:
        require(isinstance(row, dict) and set(row) == {"path", "sha256"} and isinstance(row["path"], str)
                and HEX64.fullmatch(str(row["sha256"])), "Input snapshot row differs: " + label)
        if row["path"] == "<run-local-catalog>":
            continue
        path = Path(row["path"]).resolve()
        require(path not in checked or checked[path] == row["sha256"], "Conflicting input identity: " + label)
        if path not in checked:
            require(path.is_file() and digest(path) == row["sha256"], "Current input drift: " + label)
            checked[path] = row["sha256"]
        rows.append((normalized(row["path"]), row["sha256"]))
    for source in stored:
        key = suffix_key(source["name"])
        matches = [sha for path, sha in rows if path.endswith(key)]
        require(len(matches) == 1 and matches[0] == source["sha256"], "Input snapshot does not bind a stored source: "
                + label)
    return rows


def model_rows(rows):
    found = {}
    for path, sha in rows:
        if "/formal/isabelle/" in path:
            tail = "formal/isabelle/" + path.split("/formal/isabelle/", 1)[1]
            require(tail not in found, "Two formal copies read by one run")
            found[tail] = sha
    return found


def derive(checkpoint, files, product, decoder=None, checked=None):
    """Everything that the record derives from the private artifacts, for the plan that the record states."""
    checked = {} if checked is None else checked
    databases = {}
    for name in DATABASES:
        databases[name] = session_database(files[name], decoder)
        databases[name]["sha256"] = digest(files[name])
        databases[name]["bytes"] = files[name].stat().st_size
    anchor = databases[ANCHOR]
    for ancestor in ANCESTORS:
        require(databases[ancestor]["output"] in anchor["inputs"], "Definition session is not an ancestor: " + ancestor)
    parent = anchor
    for name in SESSIONS:
        require(databases[name]["inputs"][-1] == parent["output"] and databases[name]["inputs"].count(parent["output"]) == 1,
                "Parent heap differs: " + name)
        parent = databases[name]
    sessions_rows, all_sources, problems, formal = [], [], [], None
    run_of = {alias: run["id"] for run in checkpoint["kernelRuns"] for alias in run["sessions"]}
    for run in checkpoint["kernelRuns"]:
        names = [databases[alias]["name"] for alias in run["sessions"]]
        check_run_result(read_json(files[run["id"] + "-result"]), names, [databases[a] for a in run["sessions"]],
                         run["id"])
        check_build_log(files[run["id"] + "-build-log"].read_bytes(), names, run["id"])
        stored = [source for alias in run["sessions"] for source in databases[alias]["sources"]]
        rows = check_inputs(read_json(files[run["id"] + "-inputs-before"]), read_json(files[run["id"] + "-inputs-after"]),
                            stored, checked, run["id"])
        found = model_rows(rows)
        require(formal is None or found == formal, "Runs read different formal theories")
        formal = found
    for alias in SESSIONS:
        database = databases[alias]
        bodies = [body for theory in sorted(database["messages"]) for body in database["messages"][theory]["bodies"]]
        require(not any(item["error"] for item in database["messages"].values()), "Error message in " + alias)
        problems += [alias + ": " + item for item in marker_problems(bodies)]
        row = {"id": alias, "run": run_of[alias], "database": alias,
               "sources": sorted(({"sha256": s["sha256"], "bytes": s["bytes"]} for s in database["sources"]),
                                 key=lambda s: s["sha256"]),
               "passMarkers": sum(1 for body in bodies if PASS_MARKER.fullmatch(body)),
               "audits": audit_counts(bodies)}
        sessions_rows.append(row)
        all_sources += database["sources"]
    problems += static_problems(all_sources)
    require(not problems, "Kernel markers or sources differ: " + "; ".join(problems[:4]))
    # The kernel registry list and the private registry.
    lists = [body for theory in database_bodies(databases[REGISTRY_LIST_SESSION])
             for body in theory if re.match(r"[A-Z][A-Z0-9_]*_REGISTRY_LIST ", body)]
    require(len(lists) == 1, "Kernel registry list is not printed once")
    keys = keys_from_registry_list(lists[0])
    registry = read_json(files["certificate-registry"])
    require([item.get("key") for item in registry.get("certificates", [])] == keys,
            "Private registry differs from the kernel registry list")
    registry_row = {"id": "certificate-registry", "sha256": digest(files["certificate-registry"]),
                    "bytes": files["certificate-registry"].stat().st_size, "keys": keys}
    # Statements in the stored sources.
    statements = []
    for statement in checkpoint["statements"]:
        sources = databases[statement["session"]]["sources"]
        body = locate(statement, sources)
        statements.append({**statement, "text": body if statement["text"] is not None else None})
    for profile, alias in RESTATED_CONSUMERS.items():
        text = "\n".join(source["data"].decode("utf-8") for source in databases[alias]["sources"])
        for statement in checkpoint["statements"]:
            if statement["role"] == RESTATED_CONSUMED and statement["profile"] == profile:
                require(re.search(r"(?<![A-Za-z0-9_.])" + re.escape(statement["name"].rpartition(".")[2])
                                  + r"(?![A-Za-z0-9_])", text) is not None,
                        "Profile part does not consume a restated execution relation: " + statement["name"])
    # Final audits.
    audits, audited = [], set()
    for row in checkpoint["audits"]:
        database = databases[row["session"]]
        source = [s for s in database["sources"] if s["sha256"] == row["source"]]
        require(len(source) == 1, "Audit source missing: " + row["session"])
        info = parsed(source[0])
        theory = info["theory"]
        exports = [item for key, item in database["messages"].items() if key.endswith("." + theory)]
        require(len(exports) == 1, "Audit messages missing: " + row["session"])
        bodies = exports[0]["bodies"]
        require(bodies.count(row["line"]) == 1 and sum(1 for b in bodies if PASS_MARKER.fullmatch(b)) == 1,
                "Final audit markers differ: " + row["session"])
        counts = re.match(r"ROOT_COUNT=([0-9]+) NAME_COUNT=([0-9]+)(?: |$)", row["line"])
        require(counts is not None, "Final audit line differs: " + row["session"])
        lists_of = [items for items in ml_string_lists(info["text"]) if len(items) == int(counts.group(2))]
        require(len(lists_of) == 1 and len(set(lists_of[0])) == len(lists_of[0]), "Final audit list differs: "
                + row["session"])
        audited |= set(lists_of[0])
        audits.append({"session": row["session"], "source": row["source"], "line": row["line"],
                       "names": len(lists_of[0])})
    for statement in checkpoint["statements"]:
        if statement["kind"] == "theorem" and not statement["session"].startswith("ancestor-"):
            require(statement["name"] in audited, "Theorem outside every final audit: " + statement["name"])
    # Formal theories read by the runs.
    same, pinned = [], []
    for tail, sha in sorted(formal.items()):
        current = (product / tail).resolve()
        row = {"path": tail, "sha256": sha}
        if current.is_file() and digest(current) == sha:
            same.append(file_identity(product, tail))
        else:
            pinned.append(row)
    model = {"sameAsProduct": same, "pinnedOnly": pinned}
    return {"databases": databases, "kernelSessions": sessions_rows, "registry": registry_row,
            "statements": statements, "audits": audits, "modelIdentity": model, "sources": all_sources}


def database_bodies(database):
    return [database["messages"][theory]["bodies"] for theory in sorted(database["messages"])]


# ----------------------------------------------------------------------------------------------------------------
# Public checks
# ----------------------------------------------------------------------------------------------------------------
def roles_of(checkpoint):
    return {item["role"]: item for item in checkpoint["statements"] if item["role"] not in RESTATED_ROLES}


def restated(checkpoint, role):
    return [item for item in checkpoint["statements"] if item["role"] == role]


def base(item):
    return item["name"].rpartition(".")[2]


def criteria_from(checkpoint):
    """Every criterion, recomputed from the quoted statements, the audit rows and the certificate keys."""
    roles = roles_of(checkpoint)
    text = {role: item["text"] or "" for role, item in roles.items()}
    keys = checkpoint["registry"]["keys"]
    accepted, registry_set = base(roles["accepted-set"]), base(roles["registry-set"])
    image = "(" + accepted + " " + registry_set + ")"
    gate, gate_context = base(roles["gate-predicate"]), base(roles["gate-context"])
    audits = {row["session"]: row for row in checkpoint["audits"]}
    cells, executions = restated(checkpoint, "restated-cell"), restated(checkpoint, RESTATED_CONSUMED)
    manifests = re.findall(r"Runtime_(Native|Partial|Hook) <Rightarrow> (.+?)(?= \||\)$)", text["profile-manifests"])
    reader = reader_manifests_of(checkpoint)
    in_gate_context = all(roles[r]["name"].startswith(gate_context + ".")
                          for r in ("gate-instance", "certificate-removal", "acceptance-partition", "registry-partition"))
    result = {
        "gate-instantiated-over-the-registered-image":
            text["gate-instance"].startswith(gate + " ") and image in text["gate-instance"]
            and text["accepted-set"].startswith(accepted + " registry profile execution <longleftrightarrow>")
            and "<exists>certificate <in> registry." in text["accepted-set"]
            and text["accepted-set-is-image"].startswith(accepted + " " + registry_set + " profile execution")
            and text["registry-set"] .startswith(registry_set + " = set "),
        "every-certificate-removal-breaks-the-instantiation":
            text["certificate-removal"].startswith("<forall>certificate <in> " + registry_set + ". <not> " + gate)
            and "(" + accepted + " (" + registry_set + " - {certificate}))" in text["certificate-removal"]
            and text["registry-size"].endswith("= " + str(len(keys))) and text["registry-distinct"].startswith("distinct "),
        "partition-over-the-whole-registry":
            text["acceptance-partition"].startswith(base(roles["acceptance-partition-predicate"]) + " " + image + " ")
            and text["registry-partition"].startswith("<forall>certificate <in> " + registry_set + "."),
        "applied-and-not-applied-witness-in-every-cell":
            base(roles["enforced-cell-predicate"]) + " manifests" in text["gate-predicate"]
            and "<forall>operation <in> set all_runtime_operations." in text["gate-predicate"]
            and "= TRUST_Abstract_Applied) <and>" in text["enforced-cell-predicate"]
            and "= TRUST_Abstract_Rejected <or>" in text["enforced-cell-predicate"],
        "failure-checkers-sound":
            base(roles["checker-soundness-predicate"]) + " (failure_checkers profile)" in text["gate-predicate"]
            and text["profile-checkers"].endswith("= " + base(roles["abi-checker"]))
            and text["abi-checker-sound"] == base(roles["checker-soundness-predicate"]) + " " + base(roles["abi-checker"]),
        "malformed-branch-over-the-registered-requests":
            base(roles["malformed-branch-predicate"]) + " manifests" in text["gate-predicate"]
            and base(roles["registered-requests-predicate"]) + " registered" in text["gate-predicate"]
            and "TRUST_Abstract_Malformed" in text["malformed-branch-predicate"]
            and registry_set in text["registered-requests"]
            and all(v > 0 for v in key_coverage(keys)["malformedRequests"].values()),
        "accepted-executions-pin-profile-code":
            all("account_code_at (transaction_pre execution)" in text[role] for role in
                ("native-code-pins", "partial-code-pins", "hook-code-pins", "native-pinned-runtime")),
        "cells-over-storage-reading-manifests":
            sorted(profile for profile, _ in manifests) == sorted(PROFILES)
            and all(term in reader.get(profile, ()) for profile, term in manifests)
            and all(term in text[profile.lower() + "-part"] for profile, term in manifests),
        "hash-equations-remain-locale-assumptions":
            in_gate_context and text["gate-context"].count(" + ") == 2,
        "no-oracle-and-no-skipped-proof":
            sorted(audits) == sorted(FINAL_AUDIT_SESSIONS) and all(row["names"] > 0 for row in audits.values())
            and checkpoint["coverage"].get("oracleDependencies") == 0,
        "cell-theorems-without-evaluation":
            len(cells) == RESTATED_ROLES["restated-cell"] and len(executions) == RESTATED_ROLES[RESTATED_CONSUMED]
            and RESTATED_SESSION in audits
            and "CELL_THEOREMS=" + str(len(cells)) in audits[RESTATED_SESSION]["line"]
            and " cell_oracles=0 " in audits[RESTATED_SESSION]["line"] + " "
            and " oracles=0 " in audits[RESTATED_SESSION]["line"] + " ",
    }
    return {key: "PASS" if result[key] else "FAIL" for key in CRITERIA}


def reader_manifests_of(checkpoint):
    """The manifest terms that the storage reader record compares, by profile (filled by public_contract)."""
    return checkpoint.get("_readerManifests", {})


def coverage_of(checkpoint):
    keys = checkpoint["registry"]["keys"]
    audit = {row["session"]: row for row in checkpoint["audits"]}
    pairs = re.search(r"same_statement_pairs=([0-9]+)", audit.get(RESTATED_SESSION, {}).get("line", ""))
    return {**key_coverage(keys), "restatedCellTheorems": len(restated(checkpoint, "restated-cell")),
            "restatedExecutionRelations": len(restated(checkpoint, RESTATED_CONSUMED)),
            "sameStatementPairs": int(pairs.group(1)) if pairs else None,
            "kernelRuns": len(checkpoint["kernelRuns"]), "kernelSessions": len(checkpoint["kernelSessions"]),
            "auditedNames": sum(row["names"] for row in checkpoint["audits"]), "oracleDependencies": 0}


def expected_artifacts(checkpoint):
    kinds = {name: "session-database" for name in DATABASES}
    for run in checkpoint["kernelRuns"]:
        for role, kind in RUN_ROLES:
            kinds[run["id"] + "-" + role] = kind
    kinds["certificate-registry"] = "registry"
    return kinds


def cross_records(product):
    records = {}
    for relative in CROSS_RECORDS:
        records[relative] = read_json(product / relative)
    return records


def artifact_of(record, identifier):
    rows = [row for row in record.get("artifacts", []) if row.get("id") == identifier]
    require(len(rows) == 1, "Cross record artifact missing: " + identifier)
    return rows[0]


def check_cross_records(checkpoint, product):
    records = cross_records(product)
    by_id = {row["id"]: row for row in checkpoint["artifacts"]}
    anchor = artifact_of(records[ANCHOR_SAME_AS["record"]], ANCHOR_SAME_AS["artifact"])
    require(by_id[ANCHOR]["sha256"] == anchor["sha256"] and by_id[ANCHOR]["bytes"] == anchor["bytes"],
            "Anchor database differs from the aligned gate record")
    reader = records[READER_RECORD]
    shared = [row for row in reader.get("artifacts", []) if row.get("id") in by_id]
    require(len(shared) >= 9 and all(by_id[row["id"]]["sha256"] == row["sha256"] and by_id[row["id"]]["bytes"]
                                     == row["bytes"] for row in shared), "Shared session databases differ")
    for session in checkpoint["kernelSessions"]:
        for source in session["sources"]:
            if "sameAs" in source:
                other = artifact_of(records[source["sameAs"]["record"]], source["sameAs"]["artifact"])
                require(other["sha256"] == source["sha256"] and other["bytes"] == source["bytes"],
                        "Shared source differs: " + source["sameAs"]["artifact"])
    for row in checkpoint["modelIdentity"]["pinnedOnly"]:
        if row.get("sameAs"):
            other = artifact_of(records[row["sameAs"]["record"]], row["sameAs"]["artifact"])
            require(other["sha256"] == row["sha256"], "Pinned formal theory differs: " + row["path"])
    registry = records[REGISTRY_RECORD]
    private = artifact_of(registry, "certificate-registry")
    require(checkpoint["registry"]["sha256"] == private["sha256"] and checkpoint["registry"]["bytes"] == private["bytes"],
            "Certificate registry hash differs from the registry record")
    require(sorted(item["key"] for item in registry.get("certificates", [])) == sorted(checkpoint["registry"]["keys"]),
            "Certificate keys differ from the registry record")
    manifests = {}
    cells = reader.get("cellStatements", {})
    for profile in PROFILES:
        values = cells.get(profile.lower(), {}).values()
        terms = set()
        for value in values:
            terms |= {item["manifest"] for item in value} if isinstance(value, list) else {value}
        manifests[profile] = sorted(terms)
    return manifests


def evidence_for(product):
    conditions = {item["id"]: item for item in read_json(product / CONDITIONS_PATH)["conditions"]}
    rows = []
    for entry in EVIDENCE_FOR:
        condition = conditions.get(entry["condition"])
        require(condition is not None and all(clause in condition["condition"] for clause in entry["clauses"])
                and all(1 <= index <= len(condition["closureAcceptance"]) for index in entry["supported"]),
                "Condition differs from the current conditions list: " + entry["condition"])
        rows.append({"condition": entry["condition"], "closureAcceptance": condition["closureAcceptance"],
                     "supported": list(entry["supported"]), "clauses": list(entry["clauses"])})
    return rows


def check_shape(checkpoint):
    require(isinstance(checkpoint, dict) and set(checkpoint) == PUBLIC_KEYS and checkpoint["schema"] == SCHEMA
            and checkpoint["status"] == STATUS, "Checkpoint contract differs")
    runs = checkpoint["kernelRuns"]
    require(isinstance(runs, list) and runs and all(isinstance(run, dict) and set(run) == {"id", "result", "inputsBefore",
                                                    "inputsAfter", "buildLog", "sessions"} for run in runs),
            "Kernel run rows differ")
    order = [alias for run in runs for alias in run["sessions"]]
    require(order == list(SESSIONS) and len({run["id"] for run in runs}) == len(runs)
            and all(RUN_ID.fullmatch(run["id"]) and run["sessions"] and run["result"] == run["id"] + "-result"
                    and run["inputsBefore"] == run["id"] + "-inputs-before"
                    and run["inputsAfter"] == run["id"] + "-inputs-after" and run["buildLog"] == run["id"] + "-build-log"
                    for run in runs), "Kernel runs do not cover the sessions in order")
    sessions = checkpoint["kernelSessions"]
    require([row.get("id") for row in sessions] == list(SESSIONS)
            and all(set(row) == {"id", "run", "database", "sources", "passMarkers", "audits"} and row["database"] == row["id"]
                    for row in sessions), "Kernel session rows differ")
    run_of = {alias: run["id"] for run in runs for alias in run["sessions"]}
    for row in sessions:
        require(row["run"] == run_of[row["id"]] and isinstance(row["sources"], list) and row["sources"]
                and all(set(s) - {"sameAs"} == {"sha256", "bytes"} and HEX64.fullmatch(s["sha256"])
                        and type(s["bytes"]) is int and s["bytes"] > 0 for s in row["sources"])
                and type(row["passMarkers"]) is int and isinstance(row["audits"], list), "Kernel session row differs: "
                + row["id"])
    kinds = expected_artifacts(checkpoint)
    artifacts = checkpoint["artifacts"]
    require(isinstance(artifacts, list) and [row.get("id") for row in artifacts] == list(kinds)
            and all(set(row) == {"id", "kind", "bytes", "sha256"} and row["kind"] == kinds[row["id"]]
                    and type(row["bytes"]) is int and row["bytes"] > 0 and HEX64.fullmatch(str(row["sha256"]))
                    for row in artifacts), "Artifact inventory differs")
    statements = checkpoint["statements"]
    require(isinstance(statements, list) and all(isinstance(item, dict) for item in statements), "Statements differ")
    roles = [item.get("role") for item in statements if item.get("role") not in RESTATED_ROLES]
    require(roles == list(ROLES), "Statement roles differ")
    for item in statements:
        if item["role"] in RESTATED_ROLES:
            require(set(item) == {"role", "session", "kind", "name", "text", "profile"} and item["session"] == RESTATED_SESSION
                    and item["kind"] == "theorem" and item["text"] is None and item["profile"] in RESTATED_CONSUMERS,
                    "Restated row differs")
        else:
            session, kind = ROLES[item["role"]]
            require(set(item) == {"role", "session", "kind", "name", "text"} and item["session"] == session
                    and item["kind"] == kind and isinstance(item["text"], str) and item["text"].strip(),
                    "Statement row differs: " + item["role"])
        require(isinstance(item["name"], str) and re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*\.[A-Za-z][A-Za-z0-9_']*",
                                                                item["name"]), "Statement name differs")
    for role, count in RESTATED_ROLES.items():
        names = [item["name"] for item in statements if item["role"] == role]
        require(len(names) == count and len(set(names)) == count, "Restated rows differ: " + role)
    require([item["role"] for item in statements] == list(ROLES) + [role for role, count in RESTATED_ROLES.items()
                                                                     for _ in range(count)], "Statement order differs")
    audits = checkpoint["audits"]
    require(isinstance(audits, list) and [row.get("session") for row in audits] == list(FINAL_AUDIT_SESSIONS)
            and all(set(row) == {"session", "source", "line", "names"} and HEX64.fullmatch(str(row["source"]))
                    and type(row["names"]) is int and row["names"] > 0 for row in audits), "Final audit rows differ")
    registry = checkpoint["registry"]
    require(isinstance(registry, dict) and set(registry) == {"id", "sha256", "bytes", "keys"}
            and registry["id"] == "certificate-registry" and HEX64.fullmatch(str(registry["sha256"]))
            and isinstance(registry["keys"], list) and len(set(registry["keys"])) == len(registry["keys"]),
            "Registry row differs")
    by_id = {row["id"]: row for row in artifacts}
    require(by_id["certificate-registry"]["sha256"] == registry["sha256"]
            and by_id["certificate-registry"]["bytes"] == registry["bytes"], "Registry artifact differs")
    model = checkpoint["modelIdentity"]
    require(isinstance(model, dict) and set(model) == {"sameAsProduct", "pinnedOnly"}, "Model identity differs")


def privacy_boundary(checkpoint):
    encoded = json.dumps(checkpoint, ensure_ascii=False)
    found = PRIVATE.search(encoded)
    require(encoded.isascii() and chr(0x2014) not in encoded and not found,
            "Private or non-English metadata" + (": " + found.group(0) if found else ""))
    require(not any(PROCESS_LABEL.search(checkpoint[key]) for key in PROSE_KEYS), "Internal process label in prose")


def public_contract(checkpoint, product):
    product = product.resolve()
    check_shape(checkpoint)
    privacy_boundary(checkpoint)
    require(payload_digest(checkpoint) == EXPECTED_EVIDENCE_DIGEST, "Reviewed evidence digest differs")
    require(checkpoint["scope"] == SCOPE and checkpoint["gateBoundary"] == GATE_BOUNDARY
            and checkpoint["modelBoundary"] == MODEL_BOUNDARY and checkpoint["registryBoundary"] == REGISTRY_BOUNDARY
            and checkpoint["conditionBoundary"] == CONDITION_BOUNDARY
            and checkpoint["reproductionBoundary"] == REPRODUCTION_BOUNDARY, "Public scope or boundary differs")
    require(checkpoint["nonclaims"] == {key: True for key in NONCLAIM_KEYS}, "All bounded nonclaims required")
    require(checkpoint["retainedAssumptions"] == RETAINED_ASSUMPTIONS, "Retained assumptions differ")
    verifier = checkpoint["rehashVerifier"]
    require(isinstance(verifier, dict) and set(verifier) == {"path", "bytes", "sha256", "command"}
            and verifier["command"] == COMMAND
            and {key: verifier[key] for key in ("path", "bytes", "sha256")} == file_identity(product, VERIFIER_PATH),
            "Current verifier differs")
    require(checkpoint["evidenceFor"] == evidence_for(product), "Quoted criteria differ from the conditions list")
    for row in checkpoint["modelIdentity"]["sameAsProduct"]:
        require(set(row) == {"path", "bytes", "sha256"} and row == file_identity(product, row["path"]),
                "Formal theory differs from the current product file: " + row["path"])
    for row in checkpoint["modelIdentity"]["pinnedOnly"]:
        require(set(row) - {"sameAs"} == {"path", "sha256"} and HEX64.fullmatch(row["sha256"])
                and (product / row["path"]).is_file() and digest(product / row["path"]) != row["sha256"],
                "Pinned formal theory row differs: " + row["path"])
    require(len(checkpoint["modelIdentity"]["sameAsProduct"]) > 0, "Formal theories missing")
    manifests = check_cross_records(checkpoint, product)
    probe = dict(checkpoint, _readerManifests=manifests)
    require(same_json(coverage_of(checkpoint), checkpoint["coverage"]), "Coverage does not follow from the rows")
    require(checkpoint["criteria"] == criteria_from(probe) and set(checkpoint["criteria"].values()) == {"PASS"},
            "Criteria do not follow from the quoted statements")
    return manifests


def private_file(base, relative, label):
    require(isinstance(relative, str) and relative and not PurePosixPath(relative).is_absolute()
            and ".." not in PurePosixPath(relative).parts and ":" not in relative and "\\" not in relative,
            "Private index path differs: " + label)
    path = (base / relative).resolve()
    require(path.is_relative_to(base) and path.is_file(), "Private artifact missing: " + label)
    return path


def private_files(checkpoint, index_path):
    index = read_json(index_path)
    kinds = expected_artifacts(checkpoint)
    require(isinstance(index, dict) and set(index) == set(kinds), "Private index roles differ")
    base_dir = index_path.parent.resolve()
    files = {}
    for row in checkpoint["artifacts"]:
        path = private_file(base_dir, index[row["id"]], row["id"])
        require(path.stat().st_size == row["bytes"] and digest(path) == row["sha256"], "Private artifact drift: " + row["id"])
        files[row["id"]] = path
    require(len(set(files.values())) == len(files), "Two artifacts share a file")
    return files


def derived_part(checkpoint, derived):
    """The derived members of the record, as the record holds them."""
    sessions = []
    for row in derived["kernelSessions"]:
        stated = {item["sha256"]: item for item in next(s for s in checkpoint["kernelSessions"]
                                                        if s["id"] == row["id"])["sources"]}
        sources = [{**source, **({"sameAs": stated[source["sha256"]]["sameAs"]}
                                 if source["sha256"] in stated and "sameAs" in stated[source["sha256"]] else {})}
                   for source in row["sources"]]
        sessions.append({**row, "sources": sources})
    pinned = []
    stated_pinned = {row["path"]: row for row in checkpoint["modelIdentity"]["pinnedOnly"]}
    for row in derived["modelIdentity"]["pinnedOnly"]:
        extra = stated_pinned.get(row["path"], {})
        pinned.append({**row, **({"sameAs": extra["sameAs"]} if "sameAs" in extra else {})})
    return {"registry": derived["registry"], "statements": derived["statements"], "audits": derived["audits"],
            "modelIdentity": {"sameAsProduct": derived["modelIdentity"]["sameAsProduct"], "pinnedOnly": pinned},
            "kernelSessions": sessions}


def verify_checkpoint(checkpoint, index_path, product, decoder=None):
    product, index_path = product.resolve(), index_path.resolve()
    manifests = public_contract(checkpoint, product)
    verifier_file = (product / VERIFIER_PATH).resolve()
    require(Path(__file__).resolve() == verifier_file, "Executing verifier identity differs")
    files = private_files(checkpoint, index_path)
    checked = {}
    derived = derive(checkpoint, files, product, decoder, checked)
    expected = derived_part(checkpoint, derived)
    for key, value in expected.items():
        require(same_json(checkpoint[key], value), "Public record differs from the saved artifacts: " + key)
    probe = dict(checkpoint, _readerManifests=manifests)
    require(criteria_from(probe) == {key: "PASS" for key in CRITERIA}, "Criteria do not hold for the saved sources")
    for row in checkpoint["artifacts"]:
        require(digest(files[row["id"]]) == row["sha256"], "Private artifact changed while checked: " + row["id"])
    require(digest(verifier_file) == checkpoint["rehashVerifier"]["sha256"], "Verifier changed while checked")
    return {"schema": "trust12-registered-gate-rehash-v1", "status": "PASS_REGISTERED_GATE_RECOMPUTED",
            "criteria": checkpoint["criteria"], "coverage": checkpoint["coverage"],
            "sessionDatabases": len(DATABASES), "kernelRuns": len(checkpoint["kernelRuns"]),
            "storedSources": len(derived["sources"]), "currentInputsRehashed": len(checked), "proverRerun": False,
            "registeredCentralClosureDischarged": False, "nonclaim": REPRODUCTION_BOUNDARY}


def build_checkpoint(plan, files, product, decoder=None):
    """The record before its verifier identity is added; the writer pins its digest in this verifier.

    PLAN holds the kernel runs, the statement rows with their names (text None for a restated cell, any string
    otherwise), the final audit rows (session, source hash, marker line), the sources shared with other public records
    and the pinned formal theories that other public records name."""
    artifacts = [{"id": identifier, "kind": kind, "bytes": files[identifier].stat().st_size,
                  "sha256": digest(files[identifier])} for identifier, kind in expected_artifacts(plan).items()]
    skeleton = {"kernelRuns": plan["kernelRuns"], "statements": plan["statements"], "audits": plan["audits"],
                "kernelSessions": [{"id": alias, "sources": [dict(item) for item in plan["sameAs"].get(alias, [])]}
                                   for alias in SESSIONS],
                "modelIdentity": {"pinnedOnly": plan["pinnedSameAs"]}}
    derived = derive(skeleton, files, product, decoder)
    part = derived_part(skeleton, derived)
    checkpoint = {"schema": SCHEMA, "status": STATUS, "scope": SCOPE, "gateBoundary": GATE_BOUNDARY,
                  "modelBoundary": MODEL_BOUNDARY, "registryBoundary": REGISTRY_BOUNDARY,
                  "conditionBoundary": CONDITION_BOUNDARY, "reproductionBoundary": REPRODUCTION_BOUNDARY,
                  "evidenceFor": evidence_for(product), "criteria": None, "coverage": None,
                  "registry": part["registry"], "statements": part["statements"], "audits": part["audits"],
                  "modelIdentity": part["modelIdentity"], "kernelRuns": plan["kernelRuns"],
                  "kernelSessions": part["kernelSessions"], "artifacts": artifacts,
                  "retainedAssumptions": dict(RETAINED_ASSUMPTIONS), "rehashVerifier": None,
                  "nonclaims": {key: True for key in NONCLAIM_KEYS}}
    checkpoint["coverage"] = coverage_of(checkpoint)
    manifests = check_cross_records(checkpoint, product)
    checkpoint["criteria"] = criteria_from(dict(checkpoint, _readerManifests=manifests))
    return checkpoint


def metadata_only(checkpoint, product):
    public_contract(checkpoint, product.resolve())
    return {"status": "PASS_PUBLIC_METADATA_ONLY", "criteria": checkpoint["criteria"],
            "savedArtifactsVerified": False, "proverRerun": False, "nonclaims": sorted(NONCLAIM_KEYS)}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--product-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--checkpoint", type=Path)
    parser.add_argument("--metadata-only", action="store_true")
    parser.add_argument("--artifact-index", type=Path)
    parser.add_argument("--zstd", help="zstd executable, needed only without the standard library module")
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    sys.dont_write_bytecode = True
    product = args.product_root.resolve()
    checkpoint_path = (args.checkpoint or product / CHECKPOINT_PATH).resolve()
    require(checkpoint_path == (product / CHECKPOINT_PATH).resolve(), "Unexpected checkpoint location")
    checkpoint = read_json(checkpoint_path)
    if args.metadata_only:
        require(args.artifact_index is None, "Metadata mode reads no private file")
        report = metadata_only(checkpoint, product)
    else:
        require(args.artifact_index is not None, "Saved mode requires the private index")
        report = verify_checkpoint(checkpoint, args.artifact_index, product, args.zstd)
    if args.out:
        with args.out.open("x", encoding="utf-8", newline="\n") as handle:
            handle.write(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, OSError, ValueError, KeyError, TypeError, AttributeError, IndexError, StopIteration,
            sqlite3.Error, subprocess.CalledProcessError) as error:
        raise SystemExit(f"FAIL: {error}")
