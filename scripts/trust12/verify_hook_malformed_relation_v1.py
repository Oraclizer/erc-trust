#!/usr/bin/env python3
"""Rehash six saved stages for a fixed supplied Hook malformed relation."""
from __future__ import annotations

import argparse
import ast
import hashlib
import inspect
import json
import lzma
import re
import shutil
import sqlite3
import subprocess
from collections import Counter
from pathlib import Path, PurePosixPath, PureWindowsPath

STAGE_IDS = ("code-canary", "adapter-identity", "token-identity", "world-observations",
             "canonical-control", "recorded-relation")
SCOPE = ("The thirteen supplied Hook execution records satisfy the recorded malformed relation "
         "under the pinned abstraction model and conditional reader assumptions. The two supplied "
         "worlds and request records are fixed.")
MODEL_BOUNDARY = ("Existing keccak, storage layout, profile and environment assumptions are retained. "
                  "Conditional reader facts are audited; an unconditional concrete-table witness is not "
                  "claimed. Product model identity uses the existing eight-core-definition alias "
                  "checkpoint only; equivalence of the entire model is not claimed.")
REPRODUCTION_BOUNDARY = ("This verifier rehashes saved artifacts, native database source bytes and "
                         "message exports, and requires current bound source identities. The private "
                         "navigation index is not proof authority. This is neither a fresh kernel replay "
                         "nor a product completion statement.")
CLASSES = {"no-selector": 2, "unknown-selector": 1, "length": 3, "dirty-address-word": 1,
           "dirty-enum-word": 2, "dirty-uint64-word": 1, "dirty-uint48-word": 1,
           "nonzero-call-value": 1, "ordering-probe": 1}
CASES = ("empty-calldata", "three-byte-calldata", "unknown-selector", "action-one-byte-short",
         "action-one-byte-long", "action-dirty-address", "action-enum-out-of-range",
         "action-dirty-uint64", "action-dirty-uint48", "action-nonzero-value",
         "action-ordering-foreign-domain", "reversal-one-byte-short", "reversal-enum-out-of-range")
COVERAGE = {"registeredRequests": 13, "recordedPreWorlds": 2, "kernelStages": 6,
            "requestClassifications": CLASSES, "commandConsumers": 13,
            "conditionalReaderFacts": 5, "finalEvaluationOracleDependencies": 0,
            "canonicalControl": {"bytes": 644, "mutationIndex": 99, "from": 6, "to": 5,
                                 "canonicalGuardOnly": True}}
NONCLAIM_KEYS = {"operationalExecutionReceiver", "generalRuntimeLinks", "otherProfiles", "otherRequests",
                 "centralRefinementClosure", "fullTrustCompletion", "independentAssurance", "releaseOrDeployment"}
MODEL_PATH = "formal/isabelle/ERC_TRUST/TRUST_Out_Of_Spec_Refinement.thy"
CORE_ALIAS_PATH = "evidence/trust12/runtime-link/malformed/outofspec-v7-alias-core-equivalence-checkpoint-v1.json"
CORE_ALIAS_VERIFIER_PATH = "scripts/trust12/verify_outofspec_v7_alias_equiv_v1.py"
CORE_ALIAS_SCOPE = ("The current product v7 out-of-specification theory was rebuilt with only its theory "
                    "header renamed, and eight core v5/v7 definitions were proved equivalent in a "
                    "separate session with an oracle-dependency guard.")
HELPER_PATH = "scripts/trust12/verify_partial_malformed_relation_v1.py"
VERIFIER_PATH = "scripts/trust12/verify_hook_malformed_relation_v1.py"
CHECKPOINT_PATH = "evidence/trust12/runtime-link/malformed/hook-relation-checkpoint-v1.json"
COMMAND = ("python3 " + VERIFIER_PATH + " --base <evidence-root> --product-root <product-root> "
           "--checkpoint " + CHECKPOINT_PATH + " --artifact-index <local-artifact-index.json> --zstd <zstd-executable>")
PUBLIC_KEYS = {"schema", "status", "scope", "coverage", "modelBoundary", "productIdentity", "artifacts",
               "kernelStages", "oracleAudits", "rehashVerifier", "nonclaims", "reproductionBoundary"}
PRIVATE_COORDINATES = re.compile(r"(?i)\bG[0-9]+\b|[A-Za-z]:[\\/]|\\\\[A-Za-z]")
SOURCE_PINS = {
    "code-canary": ("a30d7cd1c14a1845c30587f230a52c6b20c96be8127d62bfb5c492ef6b03859c", "10b0a0cabb2a3ced55a7cf9bc79db1e9bad9616be5d92f88339f0d0b5ee0185f", "ed6c61e6a0c26d7fa230ac5078d43a3ce26f50ce85122f6efe258f8337f9b4b3"),
    "adapter-identity": ("f9d597d7292f2f9962383bb1efa5964b3a85a1bd1900bcd0098fb454ac90eb58", "0321ee70f2b372242e16ac0ee0656e067e31a632d426eec90d6c3a9c12c40077", "bcef53563537ad6ed6959557e9416ff80d060f001abb31c9e5b7801f869750a8"),
    "token-identity": ("fa1e1e88421ba241f1443463f7c489c2abe73760f0b6cf4d0517c4bc78832ad3", "18942485923497c2fd8ca8c975b82ddb54fd0744cf116c9ae2a9f84d6df4b80e", "e6ca44ef1d6447bfbafae07eeb97776ddb24e84f5916707dcce08deae63f4e2c"),
    "world-observations": ("56f680a29ccc75338edd8762ecfd2e2db154709bcdf2231d07b0c8065a7b3d2b", "cdc6e853526f4b35980c57e1844b87cd0f9cffc675b3a1da43ea1f84083f83f2", "b42823675c69859e16b0e1e1b358ae7f6beee396498c3592fb1af05378d7a4d7"),
}
# Reviewed in-memory render identities; no completed result is inferred from them.
SOURCE_ONLY_PINS = {"canonical-control": "8ee2b0b5f009bed5ddce762f02b403b0405542b84e32b41af5cb573dbf0b24dc",
                    "recorded-relation": "46d664faa4fea715c9effa8e2405db0a77663b084b0e07cff0fefa47771e804f"}
EXTRA_PINS = {
    "pinned-malformed-model": "3e51be34f4d3bf1b4528309f2bfcacb0848c11a6f632487bf960ad19c82f8471",
    "original-fixed-relation": "24a2f69a8d521ba7af44fbc0cb7fdf492f283aed5fba035d46f174603a49f0c3",
    "fixed-record-inventory": "fe01d41ecd94e49770a23b81954193de358a553115d897ad4d2d16aaca2081ef",
    "conditional-common-reader": "62f80d0cacf6f49a0243ed5b35f1e579cefa4d6c8143381aceadb45282b8733b",
    "conditional-profile-reader": "10c78feb1bd77c097c7701a6777a39fbe913bf250ad86f874fda1e513f71a5de",
    "conditional-world-reader": "69350217421c416668ed45a13975e5d1462eea312489918f3c551cf476bd7821",
}
AUDITS = [{"id": sid, "database": sid + "-database", "countMarker": count + "=", "dependencies": 0,
           "passMarker": passed} for sid, count, passed in (
    ("code-canary", "HOOK_CODE_IDENTITY_CANARY_ORACLE_COUNT", "PASS_HOOK_CODE_IDENTITY_CANARY_ORACLE_ZERO"),
    ("adapter-identity", "HOOK_CODE_IDENTITY_ADAPTER_ORACLE_COUNT", "PASS_HOOK_CODE_IDENTITY_ADAPTER_ORACLE_ZERO"),
    ("token-identity", "HOOK_CODE_IDENTITY_TOKEN_ORACLE_COUNT", "PASS_HOOK_CODE_IDENTITY_TOKEN_ORACLE_ZERO"),
    ("world-observations", "HOOK_MALFORMED_WORLD_BRIDGE_ORACLE_COUNT", "PASS_HOOK_MALFORMED_WORLD_BRIDGE_ORACLE_ZERO"),
    ("canonical-control", "HOOK_MALFORMED_RELATION_CANARY_ORACLE_COUNT", "PASS_HOOK_MALFORMED_RELATION_CANARY_ORACLE_ZERO"),
    ("recorded-relation", "HOOK_MALFORMED_RELATION_BRANCH_ORACLE_COUNT", "PASS_HOOK_MALFORMED_RELATION_BRANCH_ORACLE_ZERO"),
)] + [{"id": "conditional-reader", "database": "code-canary-database",
        "countMarker": "HOOK_READER_CONDITIONAL_ORACLE_COUNT=", "dependencies": 0,
        "passMarker": "PASS_HOOK_READER_CONDITIONAL_ORACLE_ZERO"}]


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "Duplicate JSON key")
        result[key] = value
    return result


def read_json(path, object_required=True):
    def invalid(value):
        raise RuntimeError("Nonfinite JSON value")
    result = json.loads(Path(path).read_text(encoding="utf-8-sig"), object_pairs_hook=unique_object, parse_constant=invalid)
    require(not object_required or isinstance(result, dict), "JSON object required")
    return result


def same_json(left, right):
    return json.dumps(left, sort_keys=True, separators=(",", ":"), allow_nan=False) == json.dumps(right, sort_keys=True, separators=(",", ":"), allow_nan=False)


def relative_file(root, value, label):
    require(isinstance(value, str) and value and "\\" not in value and ":" not in value, "Invalid navigation: " + label)
    relative = PurePosixPath(value)
    require(not relative.is_absolute() and not PureWindowsPath(value).is_absolute() and ".." not in relative.parts
            and relative.as_posix() == value, "Navigation leaves bundle: " + label)
    path = (root / value).resolve()
    require(path.is_relative_to(root) and path.is_file(), "Absent artifact: " + label)
    return path


def file_identity(root, row, relative, label):
    require(set(row) == {"path", "bytes", "sha256"} and row["path"] == relative
            and type(row["bytes"]) is int and row["bytes"] > 0 and re.fullmatch(r"[0-9a-f]{64}", row["sha256"]), "Invalid product identity")
    path = relative_file(root, relative, label)
    require(path.stat().st_size == row["bytes"] and digest(path) == row["sha256"], "Product identity drift: " + label)
    return path


def strip_comments(source):
    depth, cursor, pieces = 0, 0, []
    while cursor < len(source):
        pair = source[cursor:cursor + 2]
        if pair == "(*": depth += 1; cursor += 2; continue
        if pair == "*)" and depth: depth -= 1; cursor += 2; continue
        if not depth: pieces.append(source[cursor])
        cursor += 1
    require(depth == 0, "Unclosed source comment")
    return "".join(pieces)


def root_identity(path):
    text = strip_comments(path.read_text(encoding="utf-8-sig"))
    session = re.findall(r'(?m)^session\s+([A-Za-z][A-Za-z0-9_]*)(?:\s+in\s+"\.\")?\s*=\s*([A-Za-z][A-Za-z0-9_]*)\s*\+', text)
    theory = re.findall(r"(?m)^\s{4}([A-Za-z][A-Za-z0-9_]*)\s*$", text)
    extra = re.findall(r"(?m)^\s{2}sessions\s+([A-Za-z][A-Za-z0-9_]*)\s*$", text)
    require(len(session) == len(theory) == 1 and len(extra) <= 1, "Canonical single-primary-session ROOT required")
    return *session[0], theory[0], extra


def successful_result(result, label):
    target = result.get("target")
    require(isinstance(target, str) and re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", target)
            and result.get("schema") == "trust12-final-chain-stage-result-v1"
            and result.get("status") == "PASS_FINAL_CHAIN_STAGE_BUILT_" + target and result.get("dryRun") is False
            and type(result.get("exitCode")) is int and result["exitCode"] == 0 and result.get("inputsUnchanged") is True
            and result.get("changedInputPaths") == [] and result.get("expectedNewSessions") in (target, [target])
            and result.get("builtSessions") == result.get("finishedSessions") == [target]
            and result.get("dryRunWouldBuild") == result.get("failedSessions") == result.get("cancelledSessions") == []
            and result.get("missingArtifacts") == [] and result.get("runOutOfStore") is False
            and same_json(result.get("compactPolyReceipts"), {"count": 1, "valid": True})
            and len(result.get("sessions", [])) == 1 and result["sessions"][0].get("session") == target,
            "Incomplete or contradictory kernel result: " + label)
    return target


def live_rows(rows, checked, label):
    require(isinstance(rows, list) and rows, "Empty source manifest: " + label)
    seen = set()
    for row in rows:
        require(isinstance(row, dict) and set(row) in ({"path", "sha256"}, {"path", "bytes", "sha256"})
                and isinstance(row["path"], str) and re.fullmatch(r"[0-9a-f]{64}", row["sha256"]), "Invalid source identity row")
        path = Path(row["path"]).resolve()
        require(path not in seen and path.is_file(), "Duplicate or missing source path: " + label)
        require("bytes" not in row or (type(row["bytes"]) is int and path.stat().st_size == row["bytes"]), "Source byte size drift")
        require(path not in checked or checked[path] == row["sha256"], "Conflicting source identity")
        require(digest(path) == row["sha256"], "Current source identity drift: " + label)
        seen.add(path); checked[path] = row["sha256"]
    return seen


def bound_source_inputs(before, after, binding, source, root, binding_path, checked, label):
    require(same_json(before, after), "Saved snapshot order or values differ: " + label)
    paths = live_rows(before, checked, label)
    require({source.resolve(), root.resolve(), binding_path.resolve()} <= paths, "Snapshot does not bind actual stage files")
    bound = live_rows(binding.get("inputs"), checked, label + "-binding")
    # The actual snapshot binds the immutable binding file; its separate pins are rehashed above.
    return bound


def audit_messages(messages, audit):
    require("\x06error_message" not in messages, "Native PIDE error")
    start, end = r"(?<![A-Za-z0-9_.+-])", r"(?![A-Za-z0-9_.+-])"
    values = re.findall(start + re.escape(audit["countMarker"]) + r"([0-9]+)" + end, messages)
    passes = re.findall(start + re.escape(audit["passMarker"]) + end, messages)
    require(messages.count(audit["countMarker"]) == 1 and messages.count(audit["passMarker"]) == 1
            and values == ["0"] and len(passes) == 1, "Actual guarded oracle audit differs: " + audit["id"])


def heap_identity(heap, target):
    require(heap.is_file() and heap.stat().st_size > 45, "Saved heap has no complete payload/trailer")
    remaining = heap.stat().st_size - 45
    value = hashlib.sha1()
    with heap.open("rb") as handle:
        while remaining:
            block = handle.read(min(8 * 1024 * 1024, remaining))
            require(block, "Truncated heap payload")
            value.update(block); remaining -= len(block)
        trailer = handle.read()
    actual = value.hexdigest()
    require(trailer == b"SHA1:" + actual.encode("ascii"), "Heap payload/trailer identity differs")
    return actual


def heap_manifest(value, label):
    require(isinstance(value, str) and value and value.endswith("\n"), "Invalid native heap manifest: " + label)
    result = {}
    for line in value.splitlines():
        match = re.fullmatch(r"([0-9a-f]{40}) ([A-Za-z][A-Za-z0-9_]*)", line)
        require(match is not None and match.group(2) not in result, "Duplicate or invalid native heap identity")
        result[match.group(2)] = match.group(1)
    return result


def database_heap_info(database, target):
    with sqlite3.connect(database.resolve().as_uri() + "?mode=ro&immutable=1", uri=True) as connection:
        rows = connection.execute("select session_name,return_code,errors,input_heaps,output_heap from isabelle_session_info").fetchall()
    require(len(rows) == 1 and rows[0][:3] == (target, 0, None), "Native heap database is not completed")
    inputs = heap_manifest(rows[0][3], "input")
    outputs = heap_manifest(rows[0][4], "output")
    require(set(outputs) == {target}, "Native output heap target differs")
    return inputs, outputs[target]


def heap_lineage(database, heap, target, parent_database, parent_heap, parent):
    inputs, output = database_heap_info(database, target)
    _, parent_output = database_heap_info(parent_database, parent)
    require(output == heap_identity(heap, target), "Child saved heap differs from actual database output")
    require(inputs.get(parent) == parent_output == heap_identity(parent_heap, parent),
            "Primary parent input/database/payload/trailer identity differs")


def prior_parent_artifacts(binding_paths, parent_result, parent, checked):
    artifact = parent_result["sessions"][0]
    result = []
    for role, basename in (("heap", parent), ("database", parent + ".db")):
        matches = [path for path in binding_paths if path.name == basename]
        require(len(matches) == 1, "Primary reader saved artifact absent or ambiguous")
        path = matches[0]
        require(path.stat().st_size == artifact[role]["bytes"] and digest(path) == artifact[role]["sha256"]
                and checked[path] == artifact[role]["sha256"], "Actual prior-reader artifact differs")
        result.append(path)
    return result


def saved_source(database, target, source, decoder):
    with sqlite3.connect(database.resolve().as_uri() + "?mode=ro&immutable=1", uri=True) as connection:
        rows = connection.execute("select session_name,return_code,errors,output_heap from isabelle_session_info").fetchall()
        require(len(rows) == 1 and rows[0][:3] == (target, 0, None) and rows[0][3], "Native database is not completed")
        rows = connection.execute("select name,compressed,body from isabelle_sources").fetchall()
    matches = [(compressed, body) for name, compressed, body in rows
               if str(name).replace("\\", "/").endswith("/" + source.name) or name == source.name]
    require(len(matches) == 1, "Saved native source is absent or ambiguous")
    compressed, body = matches[0]; raw = bytes(body)
    if compressed:
        if raw.startswith(b"\xfd7zXZ\x00"): raw = lzma.decompress(raw)
        else:
            require(raw.startswith(b"\x28\xb5\x2f\xfd"), "Unknown saved source compression")
            raw = subprocess.run([decoder, "-d", "-q", "--stdout"], input=raw, check=True,
                                 capture_output=True, timeout=60).stdout
    require(raw == source.read_bytes(), "Old build database does not contain current exact source")


def record_definitions(text):
    return re.findall(r'(?ms)^definition (mbh_[a-z0-9_]+_(?:execution|abstraction)) ::.*?where\s*"([^"]+)"', text)


def theorem_statement(text, name):
    values = re.findall(r'(?ms)^(?:lemma|theorem) ' + re.escape(name) + r':\s*"([^"]+)"', text)
    require(len(values) == 1, "Unique exact theorem statement absent")
    return values[0]


def canonical_proof_inverse(raw, proof):
    """Verify the one reviewed consumer repair against the full frozen source.

    Reconstructing the old exact source needs no additional evidence artifact.
    The frozen source digest covers every declaration, proposition and comment.
    """
    require(type(raw) is bytes and isinstance(proof, dict), "Exact canonical source bytes and metadata required")
    require(proof.get("renderedBodyPreserved") is False
            and proof.get("renderedBodyPreservedAfterCanaryProofInverse") is True
            and proof.get("declarationsAndStatementsPreserved") is True
            and proof.get("canaryConsumerProofRepairOnly") is True
            and proof.get("fixedSourceDomainPreserved") is True,
            "Canonical one-proof inverse metadata differs")
    old_header = b"theory TRUST_Hook_Malformed_Relation_Canary_V4\n"
    new_header = b"theory TRUST_Hook_Malformed_Relation_Canary_V5\n"
    old_proof = b"  using hmr_enum_literal_noncanonical by (simp only: hmr_enum_calldata)"
    new_proof = b"  unfolding hmr_enum_calldata\n  by (rule hmr_enum_literal_noncanonical)"
    require(raw.count(new_header) == raw.count(new_proof) == 1
            and raw.count(old_header) == raw.count(old_proof) == 0,
            "Canonical header or single proof span absent or duplicated")
    span = rb'(?m)^lemma hmr_enum_rejected[:] "[^"\n]+"\n' + re.escape(new_proof) + rb"(?=\n)"
    require(len(re.findall(span, raw)) == 1, "Repair is not the exact enum-rejection consumer proof")
    restored = raw.replace(new_header, old_header, 1).replace(new_proof, old_proof, 1)
    require(hashlib.sha256(raw).hexdigest() == SOURCE_ONLY_PINS["canonical-control"]
            and hashlib.sha256(restored).hexdigest() == "a70fdcd81299ef76a81629ff2b53b27680a88733c175da5e33caba95b8f5b529",
            "Canonical exact proof/header inverse changes frozen source")


def canonical_control(source, original, binding):
    expected = theorem_statement(original, "mbh_action_enum_out_of_range_calldata")
    field, literal = expected.split(" = ", 1)
    actual_field, actual_literal = theorem_statement(source, "hmr_enum_calldata").split(" = ", 1)
    values = ast.literal_eval(literal); actual_values = ast.literal_eval(actual_literal)
    require(isinstance(values, list) and len(values) == 644 and all(type(v) is int and 0 <= v < 256 for v in values)
            and isinstance(actual_values, list) and all(type(v) is int for v in actual_values)
            and values[99] == 6 and actual_field == field and actual_values == values,
            "Canonical control is not the exact original recorded bytes")
    require(binding["coverage"]["recordedField"] == field, "Control metadata names different original input")
    expected_statements = {
        "hmr_enum_literal_noncanonical": r"\<not> kernel_canonical_calldata " + actual_literal,
        "hmr_enum_rejected": r"\<not> kernel_canonical_calldata " + field,
        "hmr_mutant_length": "length hmr_enum_mutant = 644",
        "hmr_mutant_selector": "calldata_selector hmr_enum_mutant = 793642867",
        "hmr_mutant_canonical": "kernel_canonical_calldata hmr_enum_mutant",
    }
    for name, statement in expected_statements.items(): require(theorem_statement(source, name) == statement, "Control theorem weakened")
    mutation = re.findall(r'definition hmr_enum_mutant\b.*?where\s*"([^"]+)"', source, re.S)
    require(mutation == ["hmr_enum_mutant = " + field + "[99 := 5]"], "Original byte-99 six-to-five mutation differs")
    roots = re.findall(r"val command_roots = \[(.*?)\];", source, re.S)
    require(len(roots) == 1 and re.findall(r"@\{thm ([^}]+)\}", roots[0]) == ["hmr_enum_calldata", *expected_statements], "Canonical actual root family differs")


def source_family(source, original, spec, binding):
    source, original = strip_comments(source), strip_comments(original)
    certs = [row for row in spec["certificates"] if row["profile"] == "hook"]
    require(tuple(row["slug"] for row in certs) == CASES and dict(Counter(row["malformedClass"] for row in certs)) == CLASSES,
            "Original fixed record/class inventory differs")
    names = ["mbh_" + name.replace("-", "_") for name in CASES]
    require(len(record_definitions(source)) == 26 and record_definitions(source) == record_definitions(original), "Execution/abstraction records changed")
    for suffix, word in (("execution", "definition"), ("abstraction", "definition"), ("no_command", "theorem"), ("spec", "theorem"), ("exists", "lemma")):
        actual = re.findall(r"(?m)^" + word + r" (mbh_[a-z0-9_]+)_" + suffix + r"\b", source)
        require(actual == names, "Fixed theorem family order/coverage differs: " + suffix)
        if suffix in ("no_command", "spec", "exists"):
            for name in names: require(theorem_statement(source, name + "_" + suffix) == theorem_statement(original, name + "_" + suffix), "Original relation proposition weakened")
    accepted = re.findall(r'definition mbh_accepts\b.*?where\s*"([^"]+)"', source, re.S)
    old_accepted = re.findall(r'definition mbh_accepts\b.*?where\s*"([^"]+)"', original, re.S)
    require(len(accepted) == 1 and accepted == old_accepted and re.findall(r"execution = (mbh_[a-z0-9_]+)_execution vv", accepted[0]) == names, "Fixed accepted-record partition differs")
    statement = lambda text: re.findall(r"theorem mbh_branch" + r":\s*(.*?)\nproof -", text, re.S)
    require(len(statement(source)) == 1 and statement(source) == statement(original)
            and source.count("context psr_hook_keccak\nbegin") == 1, "Conditional final statement changed")
    roots = re.findall(r"val command_roots = \[(.*?)\];", source, re.S)
    require(len(roots) == 1 and re.findall(r"@\{thm ([^}]+)\}", roots[0]) == [name + "_no_command" for name in names]
            and 'Proof_Context.get_thm @{context} "psr_hook_keccak.mbh_branch"' in source
            and "val roots = final :: command_roots;" in source and "Thm_Deps.has_skip_proof roots" in source,
            "Actual thirteen command/final root guard differs")
    coverage = binding["coverage"]
    require(coverage["cases"] == [name.replace("-", "_") for name in CASES] and same_json(coverage["classInventory"], CLASSES)
            and coverage["commandConsumers"] == 13 and coverage["suppliedRecordsPreserved"] == 26
            and coverage["finalConsumer"] == binding["currentConsumer"] == "psr_hook_keccak.mbh_branch"
            and coverage["fixedRecordRelationOnly"] is True, "Binding relation coverage differs")


def core_alias(checkpoint, identity, pinned_record):
    require(checkpoint["schema"] == "trust12-outofspec-v7-alias-core-equivalence-checkpoint-v1"
            and checkpoint["scope"] == CORE_ALIAS_SCOPE and isinstance(checkpoint["status"], str)
            and checkpoint["status"].startswith("PASS_KERNEL_CHECKED_OUTOFSPEC_V5_V7_CORE_EQUIV_")
            and same_json(checkpoint["coverage"], {"aliasSessions": 2, "coreEquivalences": 8, "ancestorSessionsRebuilt": 0})
            and checkpoint["kernelBuild"]["inputsUnchanged"] is True and type(checkpoint["kernelBuild"]["failedSessions"]) is int
            and checkpoint["kernelBuild"]["failedSessions"] == 0 and checkpoint["hostAudit"]["status"] == "PASS_OUTOFSPEC_V5_V7_CORE_EQUIV_REHASHED", "Eight-core alias scope differs")
    require(checkpoint["source"]["productV7Theory"] == {"root": "PRODUCT", **identity["malformedModel"]}
            and checkpoint["hostAudit"]["verifier"] == {"root": "PRODUCT", **identity["coreAliasVerifier"]}
            and checkpoint["source"]["immutableV5Pin"]["root"] == "EVIDENCE"
            and all(checkpoint["source"]["immutableV5Pin"][key] == pinned_record[key] for key in ("bytes", "sha256")), "Current/pinned model alias identities differ")


def frozen_source_identity(by_id):
    for aid, expected in EXTRA_PINS.items(): require(by_id[aid]["sha256"] == expected, "Frozen supplied source differs")
    for sid, values in SOURCE_PINS.items():
        require(tuple(by_id[sid + suffix]["sha256"] for suffix in ("-source", "-root", "-binding")) == values, "Frozen expected source/root/binding differs")
    for sid, expected in SOURCE_ONLY_PINS.items(): require(by_id[sid + "-source"]["sha256"] == expected, "Reviewed rendered source differs")


def public_contract(checkpoint):
    require(set(checkpoint) == PUBLIC_KEYS and checkpoint["schema"] == "trust12-hook-malformed-relation-checkpoint-v1"
            and checkpoint["status"] == "PASS_KERNEL_CHECKED_REGISTERED_HOOK_MALFORMED_RELATION", "Checkpoint contract differs")
    require(not PRIVATE_COORDINATES.search(json.dumps(checkpoint)) and checkpoint["scope"] == SCOPE
            and same_json(checkpoint["coverage"], COVERAGE) and checkpoint["modelBoundary"] == MODEL_BOUNDARY
            and checkpoint["reproductionBoundary"] == REPRODUCTION_BOUNDARY, "Public scope/privacy boundary differs")
    require(set(checkpoint["nonclaims"]) == NONCLAIM_KEYS and all(v is True for v in checkpoint["nonclaims"].values()), "All bounded nonclaims required")
    require(isinstance(checkpoint["kernelStages"], list)
            and [row.get("id") for row in checkpoint["kernelStages"]] == list(STAGE_IDS), "Six-stage order differs")
    require(same_json(checkpoint["oracleAudits"], AUDITS), "Oracle audit inventory differs")


def verify_checkpoint(checkpoint, index, base, product, zstd):
    base, product = base.resolve(), product.resolve()
    public_contract(checkpoint)
    identity = checkpoint["productIdentity"]
    require(set(identity) == {"malformedModel", "coreAliasCheckpoint", "coreAliasVerifier", "messageReader"}, "Product identity inventory differs")
    identity_paths = {"malformedModel": MODEL_PATH, "coreAliasCheckpoint": CORE_ALIAS_PATH,
                      "coreAliasVerifier": CORE_ALIAS_VERIFIER_PATH, "messageReader": HELPER_PATH}
    products = {key: file_identity(product, identity[key], value, key) for key, value in identity_paths.items()}
    verifier = checkpoint["rehashVerifier"]
    require(set(verifier) == {"path", "bytes", "sha256", "command"} and verifier["command"] == COMMAND, "Public command differs")
    verifier_file = file_identity(product, {key: verifier[key] for key in ("path", "bytes", "sha256")}, VERIFIER_PATH, "verifier")
    require(Path(__file__).resolve() == verifier_file, "Executing verifier identity differs")
    stages, records = checkpoint["kernelStages"], checkpoint["artifacts"]
    require(isinstance(stages, list) and [row.get("id") for row in stages] == list(STAGE_IDS) and isinstance(records, list), "Six-stage order differs")
    kinds = {"prior-reader-build": "kernel-build-result", **{key: "isabelle-source" for key in EXTRA_PINS}}
    kinds["fixed-record-inventory"] = "record-inventory"
    previous = "prior-reader-build"
    for stage in stages:
        sid = stage["id"]
        links = {"id": sid, "source": sid + "-source", "sessionRoot": sid + "-root", "binding": sid + "-binding",
                 "result": sid + "-build", "inputsBefore": sid + "-inputs-before", "inputsAfter": sid + "-inputs-after",
                 "heap": sid + "-heap", "database": sid + "-database", "parentResult": previous}
        require(stage == links, "Stage linkage differs")
        for field, kind in (("source", "isabelle-source"), ("sessionRoot", "isabelle-session-root"), ("binding", "proof-input-binding"),
                            ("result", "kernel-build-result"), ("inputsBefore", "proof-input-snapshot"), ("inputsAfter", "proof-input-snapshot"),
                            ("heap", "saved-kernel-heap"), ("database", "isabelle-database")): kinds[links[field]] = kind
        previous = links["result"]
    by_id = {row["id"]: row for row in records}
    require(len(records) == len(by_id) == len(kinds) == 55 and set(by_id) == set(kinds) == set(index), "Artifact inventory or duplicates differ")
    files, checked = {}, {}
    for aid, row in by_id.items():
        require(set(row) == {"id", "kind", "bytes", "sha256"} and row["kind"] == kinds[aid]
                and type(row["bytes"]) is int and row["bytes"] > 0 and re.fullmatch(r"[0-9a-f]{64}", row["sha256"]), "Artifact identity differs")
        path = relative_file(base, index[aid], aid)
        require(path.stat().st_size == row["bytes"] and digest(path) == row["sha256"], "Artifact drift: " + aid)
        files[aid] = path; checked[path] = row["sha256"]
    require(len(set(files.values())) == len(files), "Multiple artifact IDs share a path")
    frozen_source_identity(by_id)
    core_alias(read_json(products["coreAliasCheckpoint"]), identity, by_id["pinned-malformed-model"])
    decoder = shutil.which(zstd) if not Path(zstd).is_file() else str(Path(zstd).resolve())
    require(decoder is not None, "Existing decompressor required")
    from verify_partial_malformed_relation_v1 import database_messages
    require(Path(inspect.getfile(database_messages)).resolve() == products["messageReader"], "Imported message reader differs")
    prior_result = read_json(files["prior-reader-build"])
    prior = successful_result(prior_result, "prior-reader")
    bindings = []; decoder_bound = False
    for position, stage in enumerate(stages):
        sid = stage["id"]; result = read_json(files[stage["result"]]); target = successful_result(result, sid)
        root_target, parent, theory, extra = root_identity(files[stage["sessionRoot"]])
        require(root_target == target and parent == prior, "Primary ROOT/result chain differs")
        source_path = files[stage["source"]]; source = strip_comments(source_path.read_text(encoding="utf-8-sig"))
        require(re.search(r"(?m)^theory " + re.escape(theory) + r"\s*$", source)
                and not re.search(r"\b(?:sorry|oops|admit|axiomatization|native_decide)\b|\bby\s+eval\b|(?m:^\s*oracle\s+)", source), "Source identity or proof escape differs")
        binding_path = files[stage["binding"]]; binding = read_json(binding_path)
        require(binding["status"] == "PREPARED_NOT_KERNEL_CHECKED" and binding["session"] == target and binding["parent"] == parent
                and binding["theorySha256"] == by_id[stage["source"]]["sha256"] and binding["rootSha256"] == by_id[stage["sessionRoot"]]["sha256"]
                and binding["parentResultSha256"] == by_id[stage["parentResult"]]["sha256"], "Source/parent binding differs")
        require("theory" not in binding or binding["theory"] == theory, "Binding theory name differs")
        before, after = (read_json(files[stage[key]], False) for key in ("inputsBefore", "inputsAfter"))
        paths = bound_source_inputs(before, after, binding, source_path, files[stage["sessionRoot"]], binding_path, checked, sid)
        decoder_pins = [p for p in paths if p.name.lower() in ("zstd", "zstd.exe")]
        if decoder_pins:
            require(all(digest(Path(decoder)) == checked[p] for p in decoder_pins), "Decompressor differs from actual bound utility")
            decoder_bound = True
        require(decoder_bound, "No actual saved decompressor identity")
        require(files[stage["parentResult"]] in paths, "Binding omits actual primary parent result")
        if position >= 3:
            additional = binding["additionalImportSession"] if position == 3 else binding["importClosure"]["session"]
            require(extra == [additional] and extra[0] != parent and ('"' + extra[0] + '.') in source, "Additional import registration differs")
            for field in ("kernelChecked", "operationalReceptionDischarged", "generalRuntimeLinkDischarged", "centralClosureDischarged", "independentAssuranceCompleted"):
                require(binding.get(field) is False, "Prepared relation scope credit changed")
            require(binding.get("newTrustedComponents") == [], "Prepared relation trusted boundary changed")
            if position == 3: require(binding["importRepairBodyPreserved"] is True, "World repair body changed")
            else:
                closure = binding["importClosure"]
                require(extra == [bindings[3]["additionalImportSession"]]
                        and (position == 4 or binding["frozenV2Proof"]["renderedBodyPreserved"] is True)
                        and binding["frozenV2Proof"]["declarationsAndStatementsPreserved"] is True
                        and closure["closureTheoryCount"] == (180 if position == 4 else 218)
                        and len(closure["closureTheories"]) == len(set(closure["closureTheories"])) == closure["closureTheoryCount"]
                        and closure["allCurrentSourcesBoundToSuccessfulParentSnapshot"] is True and closure["kernelChecked"] is False,
                        "Frozen relation repair/import closure differs")
                require(set(closure["closureTheories"]) <= {p.stem for p in paths if p.suffix == ".thy"}, "Import closure sources absent from current binding")
                if position == 4: canonical_proof_inverse(source_path.read_bytes(), binding["frozenV2Proof"])
            roots = [p for p in paths if p.name == "ROOT" and re.search(r"(?m)^session\s+" + re.escape(extra[0]) + r"\b", p.read_text(encoding="utf-8-sig"))]
            require(len(roots) == 1, "Additional import has no unique bound ROOT")
        else: require(extra == [], "Unexpected additional session")
        expected_schema = "trust12-hook-code-identity-input-v1" if position < 3 else ("trust12-hook-malformed-world-bridge-input-v1" if position == 3 else "trust12-hook-malformed-relation-input-v1")
        require(binding["schema"] == expected_schema, "Stage binding family differs")
        if position < 3: require(binding["mode"] == ("canary", "adapter", "token")[position], "Code stage mode differs")
        if position == 4: require(binding["mode"] == "canary" and same_json(binding["coverage"], {"recordedBytes": 644, "recordedField": binding["coverage"]["recordedField"], "mutationIndex": 99, "before": 6, "after": 5, "canonicalGuardControlOnly": True}), "Canonical control coverage differs")
        if position == 4: canonical_control(source, files["original-fixed-relation"].read_text(encoding="utf-8-sig"), binding)
        if position == 5: require(binding["mode"] == "branch", "Final relation mode differs")
        artifact = result["sessions"][0]
        for field in ("heap", "database"):
            require(artifact[field] == {key: by_id[stage[field]][key] for key in ("bytes", "sha256")}, "Actual saved artifact differs")
        if position == 0:
            parent_heap, parent_database = prior_parent_artifacts(paths, prior_result, parent, checked)
        else:
            parent_heap = files[stages[position - 1]["heap"]]
            parent_database = files[stages[position - 1]["database"]]
        heap_lineage(files[stage["database"]], files[stage["heap"]], target, parent_database, parent_heap, parent)
        saved_source(files[stage["database"]], target, source_path, decoder)
        bindings.append(binding); prior = target
    relation = bindings[-1]
    require(relation["modelCoordinates"]["actualNativeCoreSha256"] == by_id["pinned-malformed-model"]["sha256"]
            and relation["modelCoordinates"]["currentPublicCoreSha256"] == identity["malformedModel"]["sha256"]
            and relation["modelCoordinates"]["existingCoreAliasCheckpointSha256"] == identity["coreAliasCheckpoint"]["sha256"]
            and relation["modelCoordinates"]["coreEquivalences"] == 8 and relation["modelCoordinates"]["wholeModelEquivalence"] is False, "Final model alias boundary differs")
    source_family(files[stages[-1]["source"]].read_text(encoding="utf-8-sig"), files["original-fixed-relation"].read_text(encoding="utf-8-sig"), read_json(files["fixed-record-inventory"]), relation)
    for audit in AUDITS: audit_messages(database_messages(files[audit["database"]], decoder), audit)
    for path, expected in checked.items(): require(digest(path) == expected, "Evidence changed while checked")
    for key, path in products.items(): require(digest(path) == identity[key]["sha256"], "Product identity changed while checked")
    require(digest(verifier_file) == verifier["sha256"], "Verifier changed while checked")
    return {"schema": "trust12-hook-malformed-relation-rehash-v1", "status": "PASS_REGISTERED_HOOK_MALFORMED_RELATION_REHASHED",
            "registeredRequests": 13, "recordedPreWorlds": 2, "kernelBuildsRehashed": 6, "artifactsRehashed": 55,
            "currentInputsRehashed": len(checked), "evaluationOracleDependencies": {audit["id"]: 0 for audit in AUDITS},
            "operationalExecutionReceiverDischarged": False, "generalRuntimeLinksDischarged": False,
            "centralRefinementClosureDischarged": False, "fullTrustCompleted": False, "independentAssuranceCompleted": False,
            "nonclaim": REPRODUCTION_BOUNDARY}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("base", "product-root", "checkpoint", "artifact-index"): parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--zstd", default="zstd"); parser.add_argument("--out", type=Path)
    args = parser.parse_args(); product = args.product_root.resolve()
    require(args.checkpoint.resolve() == (product / CHECKPOINT_PATH).resolve(), "Unexpected checkpoint location")
    report = verify_checkpoint(read_json(args.checkpoint), read_json(args.artifact_index), args.base, product, args.zstd)
    if args.out:
        with args.out.open("x", encoding="utf-8", newline="\n") as handle: handle.write(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2)); return 0


if __name__ == "__main__":
    try: raise SystemExit(main())
    except (RuntimeError, OSError, ValueError, KeyError, TypeError, ImportError, sqlite3.Error, subprocess.CalledProcessError) as error:
        raise SystemExit(f"FAIL: {error}")
