#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Check the public record of the storage readers of the three profile manifests and, with the saved sources,
recompute it.

Metadata mode, which the required gate runs, reads tracked files only. It checks that the record is the reviewed one;
that the reader tool, the crosswalk, the quoted members of the public formal sources and the quoted condition are the
current ones; recomputes every read form from the reader clauses that the record quotes, and from those forms and the
current crosswalk every comparison row, both directions of the slot check, the sub-record member order, the generated
slot tables, the layout widths and the absent values; and checks the open item dispositions against the reviewed
dispositions. Saved mode additionally rehashes the completed kernel session databases and the stored build
information named through a private index, reads each reader source from the database that stored it, recomputes the
whole record from those sources and requires it to equal this record, including the recorded-world theorems, the cell
theorem statements and the struct member locations of the compiled layouts. Neither mode runs a prover or the
compiler.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path, PurePosixPath
import re
import sys

CHECKPOINT_PATH = "evidence/trust12/runtime-link/tail-preparation/storage-reader-checkpoint-v1.json"
VERIFIER_PATH = "scripts/trust12/verify_storage_reader_v1.py"
IDENTITY_PATHS = {"tool": "scripts/trust12/tail-preparation/storage_reader.py",
                  "crosswalk": "evidence/trust12/runtime-link/tail-preparation/state-receipt-crosswalk-v1.json"}
DISPOSITIONS_PATH = "evidence/trust12/runtime-link/tail-preparation/reflection-dispositions-v1.json"
CONDITIONS_PATH = "evidence/trust12/runtime-link/tail-preparation/tail-obligations-v1.json"
CONDITION_ID = "state-and-receipt-identity"
FINDING_ID = "no-formal-storage-reader"
# The closure evidence that the carry-over of the first open item names; this record is that evidence.
CARRY_CLOSURE = ("a kernel-checked reader per profile manifest that maps slots and mapping keys to abstract fields, "
                 "compared column by column with this crosswalk")
COMMAND = ("python3 " + VERIFIER_PATH + " --product-root <product-root> "
           "--artifact-index <private-artifact-index.json>")
SCHEMA = "trust12-storage-reader-checkpoint-v1"
STATUS = "PASS_STORAGE_READER_AGREES_WITH_CROSSWALK"
DATABASES = (["session-shared-reader", "session-hook-reader", "session-native-reader", "session-native-layout",
              "session-native-receipts", "session-native-alias-restrict", "session-native-alias-remaining",
              "session-native-freeze-bridge", "session-native-freeze-post", "session-native-forward",
              "session-native-liquidate", "session-native-restrict", "session-native-unfreeze",
              "session-native-release"]
             + [f"session-{profile}-worlds-{index}" for profile in ("partial", "hook") for index in range(1, 5)]
             + ["session-reader-cells"])
ARTIFACT_KINDS = {**{name: "session-database" for name in DATABASES}, "build-info": "build-info"}
ROLE_DATABASE = {"shared-reader": "session-shared-reader", "partial-profile": "session-shared-reader",
                 "partial-worlds-0": "session-shared-reader", "hook-profile": "session-hook-reader",
                 "hook-worlds-0": "session-hook-reader", "native-reader": "session-native-reader",
                 "native-layout": "session-native-layout", "native-receipts": "session-native-receipts",
                 "native-alias-restrict": "session-native-alias-restrict",
                 "native-alias-remaining": "session-native-alias-remaining",
                 "native-cell-freeze-bridge": "session-native-freeze-bridge",
                 "native-cell-freeze-post": "session-native-freeze-post", "native-cell-forward": "session-native-forward",
                 "native-cell-liquidate": "session-native-liquidate", "native-cell-restrict": "session-native-restrict",
                 "native-cell-unfreeze": "session-native-unfreeze", "native-cell-release": "session-native-release"}
for _profile in ("partial", "hook"):
    for _index in range(1, 5):
        ROLE_DATABASE[f"{_profile}-worlds-{_index}"] = f"session-{_profile}-worlds-{_index}"
    for _operation in ("freeze", "seize", "confiscate", "liquidate", "restrict", "recover", "unfreeze", "release",
                       "unrestrict"):
        ROLE_DATABASE[f"{_profile}-cell-{_operation}"] = "session-reader-cells"
SCOPE = ("The runtime manifests that the Native cell theorems and the restated Partial and Hook cell theorems of the "
         "registered executions use define every abstract field by a reading of storage or by a profile constant, "
         "and this record compares those definitions with the state and receipt crosswalk. The Native manifests read "
         "the endpoint storage; the reader shared by the Partial and Hook profiles reads the adapter storage and the "
         "upstream token storage. For each of the nineteen abstract state fields and each crosswalk runtime, the "
         "account, base slot, mapping depth, key, word and value decoding of the reader agree with the crosswalk "
         "column: 49 storage columns agree slot for slot, among them the fifteen Hook adapter columns that the "
         "crosswalk derives from the Partial layout, no reader reads the 38 governor columns, five adapter columns "
         "are constants of the profile and three adapter columns are read from the upstream token. Every storage "
         "variable that the crosswalk binds for the endpoint or an adapter is read into exactly the abstract field "
         "that it names, no variable that the crosswalk lists without an abstract field is read into one, the struct "
         "readers read the members of the three crosswalk sub-records in the crosswalk order, and the slots agree "
         "with the generated slot tables.")
READER_BOUNDARY = ("The readers are definitions in Isabelle theories that completed kernel sessions stored: the Native "
                   "manifest and its two later generations, which replace only the layout predicate and then the "
                   "receipt projection, the manifest names that the Native cell theorems use, and the reader shared by "
                   "the two adapter profiles with the Partial and Hook profile constants and manifests. Selector lemmas "
                   "of the same theories state each projection one field at a time. A helper definition is interpreted "
                   "only when its text equals the text pinned in the reader tool. Mapping locations are computed by a "
                   "hash function that is a parameter of the reader, constrained by the recorded preimage equations of "
                   "each theorem context; that this function is Keccak-256 on those inputs is the retained assumption "
                   "A-KECCAK. The Native reader reads a mapping key only when the configuration footprint names the "
                   "key or its preimage, except the binding kinds, which it always reads; the adapter reader reads only "
                   "the holders, identifiers, nonce keys and entitlements of the registered certificates and every "
                   "binding kind. Any other key reads as the absent value.")
REPRESENTATION_BOUNDARY = ("Some readings are representation choices, not storage facts. The adapter profiles give "
                           "zero allowances and the single profile authority as constants, and the Partial profile "
                           "gives the minted supply of its test token as a constant. Balances, and for the Hook profile "
                           "the total supply, are read from the upstream token storage, which the crosswalk layouts do "
                           "not cover and whose behavior is the retained assumption A-EXTERNAL. The adapter binding "
                           "reports zero configuration, schema and epoch, which the adapter does not store. In the third "
                           "Native generation and in the adapter reader, a LIQUIDATE receipt is read only with a "
                           "matching pair certificate of the profile and then carries the pair commitment of the model; "
                           "the second Native generation, which the FREEZE cell theorems use, reads receipts without "
                           "that translation. The Native reader gives an absent custody record, authority or binding "
                           "exactly when the words that it names are zero or the key lies outside its scope; the adapter "
                           "reader does the same for custody records and bindings and gives an authority only at the "
                           "profile authority reference.")
CONDITION_BOUNDARY = ("This record is evidence for the three closure acceptance criteria of the state and receipt "
                      "identity condition that it quotes and for the finding that no formal storage reader exists: a "
                      "reader of each profile manifest maps slots and mapping keys to abstract fields and agrees with "
                      "the crosswalk; the reader of the Hook manifest reads every derived Hook column, and kernel "
                      "theorems state the reader values of all nineteen fields for each of the sixteen recorded worlds "
                      "of the Partial and the Hook profile; and the open item of the crosswalk that waited for a formal "
                      "reader is closed by this record, while the other eight open items keep their reviewed "
                      "dispositions. The agreement is between definitions. It does not show that a deployed runtime "
                      "holds these values in a general execution; the cell theorems state the correspondence for the "
                      "registered executions only. The Native cell theorems use three generations of the Native "
                      "manifest whose field projections agree except for the receipt translation, and the Partial and "
                      "Hook cell theorems over the reader manifests restate the registered cells; naming them in the "
                      "certificate registry, instantiating the Native cells over one common manifest and the gate over "
                      "the twenty-seven cells are not part of this record.")
REPRODUCTION_BOUNDARY = ("Metadata mode reads tracked files only. It checks that this record is the reviewed one, that "
                         "the reader tool, the crosswalk, the quoted members of the public formal sources and the "
                         "quoted condition are the current ones, recomputes every read form from the reader clauses "
                         "that this record quotes and every comparison row, both directions of the slot check, the "
                         "sub-record order, the slot tables, the layout widths and the absent values from those forms "
                         "and the current crosswalk, and checks the open item dispositions against the reviewed "
                         "dispositions. Saved mode additionally rehashes the completed kernel session databases and the "
                         "stored build information named through a private index, reads each reader source from the "
                         "database that stored it, recomputes the whole record from those sources and requires it to "
                         "equal this record, including the recorded-world theorems, the cell theorem statements and the "
                         "struct member locations of the compiled layouts. Neither mode runs a prover or the compiler, "
                         "and the record states no completion of the registered-scope central closure, any general "
                         "runtime link, the independent Assurance or TRUST 1.2.")
COVERAGE = {
    "profiles": 3, "stateFields": 19, "comparisonRows": 95,
    "verdicts": {"AGREES": 49, "AGREES_CONSTANT": 5, "AGREES_NOT_READ": 38, "AGREES_UPSTREAM_TOKEN": 3},
    "derivedHookColumns": {"total": 15, "agreeing": 15},
    "reverseRuntimes": 5, "subRecords": 3, "generatedTableRows": 34, "layoutWidthRows": 42, "structReaders": 9,
    "readerClauses": 49, "readerSources": 43, "sessionDatabases": 23,
    "recordedWorlds": {"partial": {"worlds": 16, "fieldFacts": 304}, "hook": {"worlds": 16, "fieldFacts": 304}},
    "cellTheorems": {"partial": 9, "hook": 9, "native": 10}, "memberLayoutRows": 24,
    "openItems": {"closedByThisRecord": 1, "reviewedDispositions": 8}, "mismatches": 0}
NONCLAIM_KEYS = ("generalExecutionValues", "keccakInversion", "keysOutsideScope", "upstreamTokenBehavior",
                 "registryConsumers", "nativeCommonManifest", "twentySevenCellGate", "proverRerun", "compilerRerun",
                 "registeredCentralClosure", "generalRuntimeLinks", "independentAssurance", "fullTrustCompletion",
                 "releaseOrDeployment")
EXPECTED_EVIDENCE_DIGEST = 'b912a8aef7313b173f512bf56f06ff35f68c9369d5cd2e4b34a275a6907ce635'
PUBLIC_KEYS = {"schema", "status", "scope", "readerBoundary", "representationBoundary", "conditionBoundary",
               "reproductionBoundary", "evidenceFor", "coverage", "productIdentity", "formalMembers", "readerSources",
               "readerClauses", "readerForms", "comparison", "absentValues", "openItems", "layoutWords",
               "recordedWorlds", "cellStatements", "memberLayouts", "artifacts", "rehashVerifier", "nonclaims"}
HEX64 = re.compile(r"[0-9a-f]{64}")
PRIVATE = re.compile(r"(?i)[A-Za-z]:[\\/]|/mnt/|/h[o]me/|\\\\|(?<![A-Za-z0-9])(?:G|M|FV|RL)[0-9]+(?![0-9])")
_TOOLS = {}


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


def plain(value):
    """The value as JSON reads it back (integer keys become strings)."""
    return json.loads(json.dumps(value))


def payload_digest(checkpoint):
    return hashlib.sha256(canonical({key: value for key, value in checkpoint.items() if key != "rehashVerifier"})).hexdigest()


def privacy_boundary(checkpoint):
    encoded = json.dumps(checkpoint, ensure_ascii=False)
    require(encoded.isascii() and not PRIVATE.search(encoded), "Private or non-English metadata")


def file_identity(product, relative):
    path = (product / relative).resolve()
    require(path.is_file() and path.is_relative_to(product), "Missing product file: " + relative)
    return {"path": relative, "bytes": path.stat().st_size, "sha256": digest(path)}


def metadata_inputs(product):
    """Every product file that metadata mode reads, relative to the product root (the record itself aside)."""
    tool = load_tool(product)
    return sorted({VERIFIER_PATH, *IDENTITY_PATHS.values(), DISPOSITIONS_PATH, CONDITIONS_PATH, *tool.FORMAL.values()})


def load_tool(product):
    """The reader tool of the product tree, loaded from that file and from nowhere else."""
    path = (product / IDENTITY_PATHS["tool"]).resolve()
    require(path.is_file() and path.is_relative_to(product), "Missing reader tool")
    key = str(path)
    if key not in _TOOLS:
        sys.dont_write_bytecode = True
        name = "trust12_storage_reader_" + hashlib.sha256(key.encode("utf-8")).hexdigest()[:16]
        spec = importlib.util.spec_from_file_location(name, path)
        module = importlib.util.module_from_spec(spec)
        sys.modules[name] = module
        spec.loader.exec_module(module)
        _TOOLS[key] = module
    tool = _TOOLS[key]
    require(Path(tool.__file__).resolve() == path, "Loaded reader tool differs from the product file")
    return tool


def tool_constants(tool):
    require(tool.CROSSWALK == IDENTITY_PATHS["crosswalk"] and tool.DISPOSITIONS == DISPOSITIONS_PATH
            and sorted(tool.SOURCE_ROLES) == sorted(ROLE_DATABASE)
            and len(tool.CLAUSES) == COVERAGE["readerClauses"] and len(tool.STRUCT_READERS) == COVERAGE["structReaders"],
            "Reader tool constants differ")


def public_texts(product, tool):
    return {name: (product / path).read_text(encoding="utf-8") for name, path in tool.FORMAL.items()}


def formal_members(product, tool):
    """The members of the public formal sources that the comparison reads, bound by a digest of their form."""
    public = tool.public_members(public_texts(product, tool))
    return {"paths": dict(tool.FORMAL), "reads": ["stateFields", "subRecords", "projection", "tables"],
            "sha256": hashlib.sha256(canonical(public)).hexdigest()}, public


def evidence_for(product):
    conditions = read_json(product / CONDITIONS_PATH)
    matches = [item for item in conditions["conditions"] if item["id"] == CONDITION_ID]
    findings = [item for item in conditions["findings"] if item["id"] == FINDING_ID]
    require(len(matches) == 1 and len(findings) == 1 and FINDING_ID in matches[0]["blockingFindings"],
            "Condition text differs from the current conditions list")
    return {"condition": CONDITION_ID, "closureAcceptance": matches[0]["closureAcceptance"],
            "finding": {"id": FINDING_ID, "decisionNeeded": findings[0]["decisionNeeded"]}}


def open_item_rows(product, crosswalk):
    """The first open item is closed by this record; the others keep the reviewed dispositions."""
    dispositions = read_json(product / DISPOSITIONS_PATH)
    texts = crosswalk["openItems"]
    items = {item["index"]: item for item in dispositions["openItems"]}
    require(dispositions.get("status") == "REVIEWED" and sorted(items) == list(range(len(texts)))
            and all(items[index]["text"] == texts[index] for index in items), "Open item dispositions differ")
    first = items[0]
    awaiting = (first["disposition"] == "AWAITS_FORMAL_READER"
                and (first.get("carryOver") or {}).get("closureEvidence") == CARRY_CLOSURE)
    resolved = first["disposition"] == "RESOLVED_BY_FORMAL_READER" and first.get("record") == CHECKPOINT_PATH
    require(awaiting or resolved, "The first open item does not wait for or name this record")
    rows = [{"index": 0, "disposition": "CLOSED_BY_THIS_RECORD"}]
    for index in range(1, len(texts)):
        require(items[index]["disposition"] not in ("AWAITS_FORMAL_READER", "NEEDS_DECISION"),
                "An open item other than the first is still carried")
        rows.append({"index": index, "disposition": items[index]["disposition"]})
    return rows


def recompute_public(checkpoint, product, tool):
    """Every part of the record that follows from the quoted clauses, the embedded layout words and tracked files."""
    members, public = formal_members(product, tool)
    require(checkpoint["formalMembers"] == members, "Formal members differ from the current formal sources")
    forms = tool.reader_forms(checkpoint["readerClauses"], public)
    require(forms["problems"] == [], "Reader clauses do not give the pinned readers: " + "; ".join(forms["problems"][:3]))
    forms = plain({key: value for key, value in forms.items() if key != "problems"})
    require(same_json(checkpoint["readerForms"], forms), "Recomputed read forms differ from the record")
    crosswalk = read_json(product / IDENTITY_PATHS["crosswalk"])
    compared = tool.comparison(crosswalk, forms, public, checkpoint["layoutWords"])
    require(compared["mismatches"] == [], "Readers disagree with the crosswalk: " + "; ".join(compared["mismatches"][:3]))
    compared = plain({key: value for key, value in compared.items() if key != "mismatches"})
    require(same_json(checkpoint["comparison"], compared), "Recomputed comparison differs from the record")
    require(same_json(checkpoint["absentValues"], plain(tool.absent_values(forms))), "Absent values differ")
    require(same_json(checkpoint["openItems"], open_item_rows(product, crosswalk)), "Open item rows differ")
    return compared


def coverage_of(checkpoint, compared):
    """The counts of the record, computed from its rows."""
    cells = checkpoint["cellStatements"]
    return {"profiles": len(checkpoint["readerForms"]["profiles"]),
            "stateFields": len(checkpoint["readerForms"]["profiles"]["native"]),
            "comparisonRows": len(compared["rows"]), "verdicts": compared["verdicts"],
            "derivedHookColumns": compared["derivedHookColumns"], "reverseRuntimes": len(compared["reverse"]),
            "subRecords": len(compared["subRecords"]), "generatedTableRows": len(compared["generatedTables"]),
            "layoutWidthRows": len(compared["layoutWidths"]), "structReaders": len(checkpoint["readerForms"]["structs"]),
            "readerClauses": len(checkpoint["readerClauses"]), "readerSources": len(checkpoint["readerSources"]),
            "sessionDatabases": len({row["database"] for row in checkpoint["readerSources"].values()}),
            "recordedWorlds": checkpoint["recordedWorlds"],
            "cellTheorems": {"partial": sum(1 for name in cells["partial"].values() if name),
                             "hook": sum(1 for name in cells["hook"].values() if name),
                             "native": sum(len(items) for items in cells["native"].values())},
            "memberLayoutRows": len(checkpoint["memberLayouts"]),
            "openItems": {"closedByThisRecord": sum(1 for row in checkpoint["openItems"]
                                                    if row["disposition"] == "CLOSED_BY_THIS_RECORD"),
                          "reviewedDispositions": sum(1 for row in checkpoint["openItems"]
                                                      if row["disposition"] != "CLOSED_BY_THIS_RECORD")},
            "mismatches": 0}


def check_sources(sources):
    require(isinstance(sources, dict) and sorted(sources) == sorted(ROLE_DATABASE)
            and all(isinstance(row, dict) and set(row) == {"database", "sha256", "bytes"}
                    and row["database"] == ROLE_DATABASE[role] and HEX64.fullmatch(str(row["sha256"]))
                    and type(row["bytes"]) is int and row["bytes"] > 0 for role, row in sources.items())
            and len({row["sha256"] for row in sources.values()}) == len(sources), "Reader sources differ")


def check_artifacts(artifacts):
    require(isinstance(artifacts, list) and [row.get("id") for row in artifacts] == list(ARTIFACT_KINDS)
            and all(isinstance(row, dict) and set(row) == {"id", "kind", "bytes", "sha256"}
                    and row["kind"] == ARTIFACT_KINDS[row["id"]] and type(row["bytes"]) is int and row["bytes"] > 0
                    and isinstance(row["sha256"], str) and HEX64.fullmatch(row["sha256"]) is not None for row in artifacts)
            and len({row["sha256"] for row in artifacts}) == len(artifacts), "Artifact inventory differs")


def build_checkpoint(report, product, artifacts, sources):
    """The record before its verifier identity is added; the writer pins its digest in this verifier."""
    tool = load_tool(product)
    members, _ = formal_members(product, tool)
    crosswalk = read_json(product / IDENTITY_PATHS["crosswalk"])
    forms = plain({key: value for key, value in report["forms"].items() if key != "problems"})
    compared = plain({key: value for key, value in report["comparison"].items() if key != "mismatches"})
    checkpoint = {"schema": SCHEMA, "status": STATUS, "scope": SCOPE, "readerBoundary": READER_BOUNDARY,
                  "representationBoundary": REPRESENTATION_BOUNDARY, "conditionBoundary": CONDITION_BOUNDARY,
                  "reproductionBoundary": REPRODUCTION_BOUNDARY, "evidenceFor": evidence_for(product),
                  "coverage": None,
                  "productIdentity": {key: file_identity(product, path) for key, path in IDENTITY_PATHS.items()},
                  "formalMembers": members, "readerSources": sources, "readerClauses": report["clauses"],
                  "readerForms": forms, "comparison": compared, "absentValues": plain(report["absentValues"]),
                  "openItems": open_item_rows(product, crosswalk), "layoutWords": plain(report["layoutWords"]),
                  "recordedWorlds": plain(report["recordedWorlds"]), "cellStatements": plain(report["cells"]),
                  "memberLayouts": plain(report["memberLayouts"]), "artifacts": artifacts, "rehashVerifier": None,
                  "nonclaims": {key: True for key in NONCLAIM_KEYS}}
    checkpoint["coverage"] = coverage_of(checkpoint, compared)
    return checkpoint


def public_contract(checkpoint, product):
    product = product.resolve()
    require(set(checkpoint) == PUBLIC_KEYS and checkpoint["schema"] == SCHEMA and checkpoint["status"] == STATUS,
            "Checkpoint contract differs")
    privacy_boundary(checkpoint)
    require(payload_digest(checkpoint) == EXPECTED_EVIDENCE_DIGEST, "Reviewed evidence digest differs")
    require(checkpoint["scope"] == SCOPE and checkpoint["readerBoundary"] == READER_BOUNDARY
            and checkpoint["representationBoundary"] == REPRESENTATION_BOUNDARY
            and checkpoint["conditionBoundary"] == CONDITION_BOUNDARY
            and checkpoint["reproductionBoundary"] == REPRODUCTION_BOUNDARY, "Public scope or boundary differs")
    require(checkpoint["nonclaims"] == {key: True for key in NONCLAIM_KEYS}, "All bounded nonclaims required")
    require(same_json(checkpoint["coverage"], COVERAGE), "Coverage differs from the reviewed counts")
    check_artifacts(checkpoint["artifacts"])
    check_sources(checkpoint["readerSources"])
    verifier = checkpoint["rehashVerifier"]
    require(isinstance(verifier, dict) and set(verifier) == {"path", "bytes", "sha256", "command"}
            and verifier["command"] == COMMAND
            and {key: verifier[key] for key in ("path", "bytes", "sha256")} == file_identity(product, VERIFIER_PATH),
            "Current verifier differs")
    require(checkpoint["productIdentity"] == {key: file_identity(product, path) for key, path in IDENTITY_PATHS.items()},
            "Product identity differs from the current files")
    tool = load_tool(product)
    tool_constants(tool)
    require(checkpoint["evidenceFor"] == evidence_for(product), "Condition text differs from the current conditions list")
    compared = recompute_public(checkpoint, product, tool)
    require(same_json(coverage_of(checkpoint, compared), checkpoint["coverage"]), "Coverage does not follow from the rows")
    require(all(row["verdict"] == "AGREES" for row in checkpoint["memberLayouts"]), "Member layout rows differ")
    return tool


def private_file(base, relative, label):
    require(isinstance(relative, str) and relative and not PurePosixPath(relative).is_absolute()
            and ".." not in PurePosixPath(relative).parts and ":" not in relative, "Private index path differs: " + label)
    path = (base / relative).resolve()
    require(path.is_relative_to(base) and path.is_file(), "Private artifact missing: " + label)
    return path


def check_build(build, product):
    """The stored build compiled exactly the current implementation sources."""
    sources = (build.get("input") or {}).get("sources") or {}
    current = sorted(path.relative_to(product).as_posix() for path in (product / "implementation/src").rglob("*.sol")
                     if path.is_file())
    require(sorted(sources) == current and all(sources[path]["content"].encode("utf-8") == (product / path).read_bytes()
                                               for path in current), "Build sources differ from the current sources")


def verify_checkpoint(checkpoint, index_path, product, decoder=None):
    product, index_path = product.resolve(), index_path.resolve()
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
    stored = {}
    for name in DATABASES:
        try:
            stored[name] = tool.database_sources(files[name], decoder)
        except tool.SourceError as error:
            raise RuntimeError(f"Session database {name}: {error}")
    sources = {}
    for role, row in checkpoint["readerSources"].items():
        data = stored[row["database"]].get(row["sha256"])
        require(data is not None and len(data) == row["bytes"], "Saved source absent from its session database: " + role)
        sources[role] = data.decode("utf-8")
    build = read_json(files["build-info"])
    check_build(build, product)
    crosswalk = read_json(product / IDENTITY_PATHS["crosswalk"])
    _, public = formal_members(product, tool)
    report = tool.build_report(sources, crosswalk, public, build)
    require(report["status"] == "AGREES" and report["problems"] == [],
            "Recomputation from the saved sources disagrees: " + "; ".join(report["problems"][:3]))
    require(same_json(checkpoint["readerClauses"], report["clauses"]), "Reader clauses differ from the saved sources")
    for key, value in (("readerForms", {k: v for k, v in report["forms"].items() if k != "problems"}),
                       ("layoutWords", report["layoutWords"]), ("recordedWorlds", report["recordedWorlds"]),
                       ("cellStatements", report["cells"]), ("memberLayouts", report["memberLayouts"]),
                       ("absentValues", report["absentValues"]),
                       ("comparison", {k: v for k, v in report["comparison"].items() if k != "mismatches"})):
        require(same_json(checkpoint[key], plain(value)), "Public record differs from the saved sources: " + key)
    for row in checkpoint["artifacts"]:
        require(digest(files[row["id"]]) == row["sha256"], "Private artifact changed while checked: " + row["id"])
    for key, path in IDENTITY_PATHS.items():
        require(digest(product / path) == checkpoint["productIdentity"][key]["sha256"],
                "Product identity changed while checked: " + key)
    require(digest(verifier_file) == checkpoint["rehashVerifier"]["sha256"], "Verifier changed while checked")
    return {"schema": "trust12-storage-reader-rehash-v1", "status": "PASS_STORAGE_READER_RECOMPUTED",
            "verdicts": checkpoint["comparison"]["verdicts"], "recordedWorlds": checkpoint["recordedWorlds"],
            "compilerRerun": False, "proverRerun": False, "stateAndReceiptIdentityDischarged": False,
            "nonclaim": REPRODUCTION_BOUNDARY}


def metadata_only(checkpoint, product):
    public_contract(checkpoint, product.resolve())
    return {"status": "PASS_PUBLIC_METADATA_ONLY", "savedArtifactsVerified": False, "sourcesReread": False,
            "nonclaims": sorted(NONCLAIM_KEYS)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
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
    except (RuntimeError, OSError, ValueError, KeyError, TypeError, AttributeError, ImportError, IndexError) as error:
        raise SystemExit(f"FAIL: {error}")
