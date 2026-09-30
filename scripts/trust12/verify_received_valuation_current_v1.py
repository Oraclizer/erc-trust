#!/usr/bin/env python3
"""Rehash the supplied two-integer received valuation and conditional consumer."""
from __future__ import annotations

import argparse
import hashlib
import json
import lzma
import re
import shutil
import sqlite3
import subprocess
from pathlib import Path, PurePosixPath, PureWindowsPath

VERIFIER_PATH = "scripts/trust12/verify_received_valuation_current_v1.py"
CHECKPOINT_PATH = "evidence/trust12/runtime-link/native-received-valuation-checkpoint-v1.json"
INDEX_NAME = "native-received-valuation-artifact-index-v1.json"
SCHEMA = "trust12-native-received-valuation-checkpoint-v1"
STATUS = "PASS_SAVED_CONDITIONAL_RECEIVED_VALUATION_CURRENT_CHECKPOINT"
SCOPE = ("The supplied checked substitution of two Int variables is decoded to amount 1 and "
         "timestamp 1700000000, with zero for other names, and consumed by the existing supplied "
         "Native FREEZE transaction bound under its original twenty-three premises and the same "
         "explicit natural-number gas parameter. Missing bindings, wrong sorts and a typed invalid "
         "decimal are rejected; removing the time consumer violates that transaction bound.")
BOUNDARY = ("The two current product formal source files have the same byte identities as the "
            "recorded consumer inputs. This checkpoint establishes no new Solidity, ABI, compiled "
            "runtime or whole-model equivalence. Existing model, profile, hash and environment "
            "assumptions remain conditional.")
REPRODUCTION = ("This checker rehashes saved native artifacts, exact database source bytes, guarded "
                "message exports, heap lineage and the union of current input bindings and unchanged "
                "run snapshots. The private artifact index only locates files. This is not a fresh "
                "kernel replay, independent Assurance, full TRUST completion or release evidence.")
NONCLAIMS = ("originalSource", "fullNamespaceSubstitution", "originalConditions", "fullGroundness",
             "definedness", "functionalness", "producerImage", "originalExecutionLaw",
             "generalRuntimeLinks", "otherProfiles", "centralRefinementClosure",
             "independentAssurance", "fullTrustCompletion", "releaseOrDeployment")
FALSE_CREDITS = ("wholeSourceCredit", "definednessCredit", "functionalnessCredit",
                 "producerImageCredit", "originalExecutionLawCredit", "generalCredit",
                 "centralCredit", "independentAssuranceCredit")
STAGES = ("status-gate", "received-method", "current-consumer")
ROLES = {"source": "isabelle-source", "root": "isabelle-session-root",
         "binding": "proof-input-binding", "result": "kernel-build-result",
         "inputs-before": "proof-input-snapshot", "inputs-after": "proof-input-snapshot",
         "audit": "saved-kernel-audit", "heap": "saved-kernel-heap", "database": "isabelle-database"}
PINS = {
    "status-gate": ("dfc4615d92367d2ec066445fa8da94f5fcd26eeca22822f3f7f16dd94d4e7d0b",
                    "94427bb54c6dd89213785d51a2bed1efdf450b9cf5d300aaaa5e30558647b79c",
                    "8f919a2a7c9e467c55267c83b23066d408b1886e3be90b2bd371ec1489a1bb15"),
    "received-method": ("f0149873936adb21714260b4fe132c3a410fddec77d2ec197d57143785c12f69",
                        "28949b5740dcdf32ffca426b5dc755d4e5d26cad88cd7f9681a353dc1722a909",
                        "6a2e0f4bdc0de34c546c31b6ead8c7750f1cba0bc10d19972ff2a2f13cfa80ae"),
    "current-consumer": ("5992a4b2e4e8a787a5af654228251099350ca4e8cb9982741bdc7fb782a3f963",
                         "d8d1a39019952864f2e808a21d038dfa64c617a40deba11b65916358f2ef24b6",
                         "b08266d91567d994f8c6b112e8792a5fd90e61ece3a016cea5f69652d71c35d6")}
PRODUCTS = {
    "retrieveModel": ("formal/isabelle/ERC_TRUST/TRUST_Retrieve_Relation.thy", 15893,
                      "5fe73a17b58d636ca2f489a02e42a442309f8f42f99cb99e72de678090475587"),
    "transactionModel": ("formal/isabelle/ERC_TRUST/TRUST_Transaction_Refinement.thy", 78470,
                         "b49b9d7a71455e547bf5185fcd66195597b185bbb5d50441b281e37eabf60149")}
METHOD_ROOTS = ["rv_environment_checked", "rv_source_typed", "rv_normal_checked", "rv_small_result_ground",
                "rv_normal_decoded(1)", "rv_normal_decoded(2)", "rv_normal_received", "rv_missing_rejected",
                "rv_wrong_sort_rejected", "rv_bad_decimal_is_typed", "rv_bad_decimal_rejected",
                "rv_received_has_checked_binding", "rv_amount", "rv_time", "rv_default", "rv_removed_time",
                "rv_removal_preserves_amount"]
CURRENT_ROOTS = METHOD_ROOTS + ["rv_decimal_correspondence", "rv_current_positive", "rv_current_missing",
                "rv_current_wrong_sort", "rv_manifest_observation_same", "rv_current_first_freeze_bound",
                "rv_received_current_g37_bound", "rv_current_removal_positive",
                "rv_time_consumer_removal_rejected_by_current_bound"]
STATUS_ROOTS = ["nse_declaration_lex", "nse_declaration_parse_eof", "nse_old_sort_table_preserved",
               "nse_extended_environment_checked", "nse_positive_type_fact_reused", "nse_revert_type_extended",
               "nse_missing_constructor_has_no_type", "nse_receive_has_actual_parsed_status_type",
               "nse_missing_constructor_rejected", "nse_typegate_removal_violates_actual_status_type_law",
               "nse_actual_typegate_first_freeze_bound", "nsr_received_first_freeze_bound"]
ROOTS = dict(zip(STAGES, (STATUS_ROOTS, METHOD_ROOTS, CURRENT_ROOTS)))
MARKERS = {"status-gate": ("NATIVE_STATUS_TYPEGATE_ORACLE_COUNT", "PASS_NATIVE_STATUS_TYPEGATE_ORACLE_ZERO_SKIP_FALSE"),
           "received-method": ("RECEIVED_VALUATION_ORACLE_COUNT", "PASS_RECEIVED_VALUATION_METHOD_ORACLE_ZERO_SKIP_FALSE"),
           "current-consumer": ("RECEIVED_VALUATION_ORACLE_COUNT", "PASS_RECEIVED_VALUATION_CURRENT_ORACLE_ZERO_SKIP_FALSE")}
COVERAGE = {"suppliedVariables": 2, "amount": "1", "timestamp": "1700000000", "otherNamesDefault": "0",
            "originalPremises": 23, "observationCongruences": 333, "guardedRootCounts": [12, 17, 26],
            "explicitGasSignatures": 3, "sameGasUses": 16, "kernelStages": 3,
            "controls": ["normal-received", "missing-binding", "wrong-sort", "typed-invalid-decimal",
                         "time-consumer-removal"], "evaluationOracleDependencies": 0}
COMMAND = ("python3 " + VERIFIER_PATH + " --base <evidence-root> --product-root <product-root> "
           "--checkpoint " + CHECKPOINT_PATH + " --artifact-index <evidence-root>/" + INDEX_NAME +
           " --zstd <zstd-executable>")
CURRENT_RUNNER_SHA256 = "310c516cb4b24b5aed94c0ac69d301ef19597e95d31edabf26bb42966d6f7a9d"
RETRY_PROVENANCE = {
    "v7ResultSha256": "caaf5898bd6950d34fa8b97820847ceefb07b87d234fd8ca481d7d138192cf6f",
    "v7DatabaseSha256": "bd6546b630b8a018c26e74735dd51e20a5068f9498eed752e447889c406ce66b",
    "v7SnapshotSha256": "248e20d36d01f050a3e18ac1c7126b62f6c6f12364b4f6f0068649b7326a8925",
    "v7LoadExpressionSha256": "3d1bad24db44d00560bbff2da3152494eac36d650872e88f81c6fd2e012810e6",
    "v7FirstAttemptKernelCredit": False,

    "firstAttemptStatus": "INCOMPLETE_NATIVE_ATTEMPT",
    "reportedError": "Timeout",
    "resourceObservation": "low-free-memory-observed",
    "sourceChanged": False,
    "firstAttemptKernelCredit": False,
    "resultSha256": "c599d723e2415dbb4222d5cd156afd2e2416113288de9b773546f869a8c8ae44",
    "databaseSha256": "18764da4ba32e4ac986cd9e5530bcb91021c3d48df9352bbbe17f3c35c7af8cd",
    "errorsSha256": "70594d932950a164e0d820060410af4ea1d127b7221f577d2dcfc22c2d8ff1df",
    "retry1AttemptStatus": "INCOMPLETE_NATIVE_ATTEMPT",
    "retry1ReportedError": "Timeout",
    "retry1SourceChanged": False,
    "retry1KernelCredit": False,
    "retry1ResultSha256": "ec30015c1797ef44fedfce9c08d02968ff7ed4086f4c79899ec835186c5b8272",
    "retry1DatabaseSha256": "c30e08ac97e7372c193002fb193d69faa53601fd11e8a94dac3088d8ffe17807",
    "retry1ErrorsSha256": "70594d932950a164e0d820060410af4ea1d127b7221f577d2dcfc22c2d8ff1df",
}
FIRST_ATTEMPT = "final-chain-v2/runs/native-received-valuation-current-v6-build"
SECOND_ATTEMPT = "final-chain-v2/runs/native-received-valuation-current-v6-build-retry1"
V6_SOURCE_PINS = ("1e6487c740a02a476221428e7bccf5f36bd31e2b77ae379e9a17fac0ab208095",
                  "4a05d9cd8cc4da5508d90122b76756f8d25a69c633394c5fcc53c63a828d866a",
                  "246d2606c7b74c48fac784d80c752c4aac04e45ea2cd4ebbf4344c0c33207fa8")


def verify_first_attempt(base):
    directory = base / FIRST_ATTEMPT
    target = "TRUST12_NATIVE_RECEIVED_VALUATION_CURRENT_V6"
    paths = {"result": directory / "result.json",
             "database": directory / ("failed-" + target + ".db"),
             "errors": directory / ("failed-" + target + "-errors.txt")}
    for role, path in paths.items():
        require(path.is_file() and digest(path) == RETRY_PROVENANCE[role + "Sha256"],
                "First attempt's saved noncredit evidence differs")
    before, after = directory / "inputs-before.json", directory / "inputs-after.json"
    require(before.is_file() and after.is_file()
            and digest(before) == digest(after) == "831253a843bbc3f70393121a77b138c2aa0cb3d54f7b863d111b794ce4e79ec4",
            "First attempt's immutable input snapshots differ")
    rows = read_json(before, False)
    original_source = base / "native-received-valuation-current-v6"
    expected_inputs = ((original_source / "TRUST_Native_Received_Valuation_Current_V6.thy", V6_SOURCE_PINS[0]),
                       (original_source / "ROOT", V6_SOURCE_PINS[1]),
                       (original_source / "input-binding.json", V6_SOURCE_PINS[2]))
    require(isinstance(rows, list) and rows, "First attempt snapshot has no inputs")
    for path, expected in expected_inputs:
        matches = [row for row in rows if Path(row["path"]).resolve() == path.resolve()]
        require(len(matches) == 1 and matches[0].get("sha256") == expected,
                "First attempt was not bound to the identical V6 source/ROOT/binding")
    result = read_json(paths["result"])
    require(result.get("schema") == "trust12-final-chain-stage-result-v1"
            and result.get("status") == "INCOMPLETE_FINAL_CHAIN_STAGE_" + target
            and result.get("stage") == "native-received-valuation-current-v6-build"
            and result.get("target") == target and result.get("dryRun") is False
            and type(result.get("exitCode")) is int and result["exitCode"] == 142
            and result.get("inputsUnchanged") is True and result.get("changedInputPaths") == []
            and result.get("builtSessions") == result.get("failedSessions") == [target]
            and all(result.get(key) == [] for key in
                    ("finishedSessions", "cancelledSessions", "dryRunWouldBuild", "sessions", "missingArtifacts"))
            and result.get("runOutOfStore") is False and result.get("mlTimeoutSeconds") == 120
            and result.get("timeoutBuild") is True
            and result.get("mlOptions") == "--minheap 400 --maxheap 2048 --gcthreads 2"
            and result.get("javaMaxHeapGB") == 2
            and type(result.get("minFreePhysicalBytes")) is int
            and 0 < result["minFreePhysicalBytes"] < 32 * 1024 * 1024,
            "First native attempt cannot carry completed kernel credit")
    require(paths["errors"].read_bytes() == b"Timeout",
            "First attempt's recorded timeout differs")
    with sqlite3.connect(paths["database"].resolve().as_uri() + "?mode=ro&immutable=1", uri=True) as connection:
        rows = connection.execute("select session_name,return_code,errors,output_heap from isabelle_session_info").fetchall()
    require(len(rows) == 1 and rows[0][0] == target and rows[0][1] == 142
            and isinstance(rows[0][2], bytes) and rows[0][2] and not rows[0][3],
            "First native database has no completed output heap")
    return paths


def verify_retry1_failure(base):
    directory = base / SECOND_ATTEMPT
    target = "TRUST12_NATIVE_RECEIVED_VALUATION_CURRENT_V6"
    paths = {"result": directory / "result.json",
             "database": directory / ("failed-" + target + ".db"),
             "errors": directory / ("failed-" + target + "-errors.txt")}
    for role, path in paths.items():
        require(path.is_file() and digest(path) == RETRY_PROVENANCE["retry1" + role.capitalize() + "Sha256"],
                "Retry1's saved noncredit evidence differs")
    before, after = directory / "inputs-before.json", directory / "inputs-after.json"
    require(before.is_file() and after.is_file()
            and digest(before) == digest(after) == "dc2f24178b88fdce2f2525d2d711f7d51de3ab8edb376316111b178b72b1cfa1",
            "Retry1's immutable input snapshots differ")
    rows = read_json(before, False)
    original_source = base / "native-received-valuation-current-v6"
    expected = ((original_source / "TRUST_Native_Received_Valuation_Current_V6.thy", V6_SOURCE_PINS[0]),
                (original_source / "ROOT", V6_SOURCE_PINS[1]),
                (original_source / "input-binding.json", V6_SOURCE_PINS[2]))
    require(isinstance(rows, list) and rows, "Retry1 snapshot has no inputs")
    for path, sha256 in expected:
        matches = [row for row in rows if Path(row["path"]).resolve() == path.resolve()]
        require(len(matches) == 1 and matches[0].get("sha256") == sha256,
                "Retry1 was not bound to the same frozen V6 source/ROOT/binding")
    result = read_json(paths["result"])
    require(result.get("schema") == "trust12-final-chain-stage-result-v1"
            and result.get("status") == "INCOMPLETE_FINAL_CHAIN_STAGE_" + target
            and result.get("stage") == "native-received-valuation-current-v6-build-retry1"
            and result.get("target") == target and result.get("dryRun") is False
            and type(result.get("exitCode")) is int and result["exitCode"] == 142
            and result.get("inputsUnchanged") is True and result.get("changedInputPaths") == []
            and result.get("builtSessions") == result.get("failedSessions") == [target]
            and all(result.get(key) == [] for key in
                    ("finishedSessions", "cancelledSessions", "dryRunWouldBuild", "sessions", "missingArtifacts"))
            and result.get("runOutOfStore") is False and result.get("mlTimeoutSeconds") == 120
            and result.get("timeoutBuild") is True
            and result.get("mlOptions") == "--minheap 400 --maxheap 2048 --gcthreads 2"
            and result.get("javaMaxHeapGB") == 2
            and type(result.get("minFreePhysicalBytes")) is int
            and result["minFreePhysicalBytes"] == 2370469888,
            "Retry1 native attempt cannot carry completed kernel credit")
    require(paths["errors"].read_bytes() == b"Timeout", "Retry1's timeout receipt differs")
    with sqlite3.connect(paths["database"].resolve().as_uri() + "?mode=ro&immutable=1", uri=True) as connection:
        db_rows = connection.execute("select session_name,return_code,errors,output_heap from isabelle_session_info").fetchall()
    require(len(db_rows) == 1 and db_rows[0][0] == target and db_rows[0][1] == 142
            and isinstance(db_rows[0][2], bytes) and db_rows[0][2] and not db_rows[0][3],
            "Retry1 native database has no completed output heap")
    return paths


PUBLIC_KEYS = {"schema", "status", "scope", "coverage", "identityBoundary", "reproductionBoundary",
               "productIdentity", "artifacts", "kernelStages", "claims", "rehashVerifier", "retryProvenance"}
PRIVATE = re.compile(r"(?i)\bG[0-9]+\b|[A-Za-z]:[\\/]|\\\\[A-Za-z]|/(?:Users|home|mnt|tmp)/|\b(?:Codex|Claude|Anthropic|ChatGPT)\b")


def verify_original_v7_failure(base, decoder):
    """Preserve the completed proof body's failed storage attempt as noncredit."""
    base = Path(base).resolve()
    run = base / "final-chain-v2/runs/native-received-valuation-current-v7-build"
    pins = {"result.json": RETRY_PROVENANCE["v7ResultSha256"],
            "failed-TRUST12_NATIVE_RECEIVED_VALUATION_CURRENT_V7.db": RETRY_PROVENANCE["v7DatabaseSha256"],
            "failed-TRUST12_NATIVE_RECEIVED_VALUATION_CURRENT_V7-errors.txt": RETRY_PROVENANCE["errorsSha256"],
            "inputs-before.json": RETRY_PROVENANCE["v7SnapshotSha256"],
            "inputs-after.json": RETRY_PROVENANCE["v7SnapshotSha256"],
            "compact-poly-receipts/trust12-load-hierarchy.2La11E.ML": RETRY_PROVENANCE["v7LoadExpressionSha256"]}
    files = {name: run / name for name in pins}
    for name, path in files.items():
        require(path.resolve().is_relative_to(base) and path.is_file() and digest(path) == pins[name],
                "Original V7 failure evidence changed")
    target, theory = "TRUST12_NATIVE_RECEIVED_VALUATION_CURRENT_V7", "TRUST_Native_Received_Valuation_Current_V7"
    result = read_json(files["result.json"])
    require(result.get("status") == "INCOMPLETE_FINAL_CHAIN_STAGE_" + target
            and result.get("exitCode") == 142 and result.get("inputsUnchanged") is True
            and result.get("builtSessions") == result.get("failedSessions") == [target]
            and result.get("finishedSessions") == result.get("sessions") == []
            and result.get("reusedTarget") is None and result.get("mlTimeoutSeconds") == 120
            and result.get("compactPolyReceipts") == {"count": 0, "valid": True},
            "Original V7 failed storage cannot earn saved credit")
    database = files["failed-" + target + ".db"]
    source = base / "native-received-valuation-current-v7" / (theory + ".thy")
    with sqlite3.connect(database.resolve().as_uri() + "?mode=ro&immutable=1", uri=True) as connection:
        info = connection.execute("select session_name,return_code,output_heap from isabelle_session_info").fetchall()
        require(info == [(target, 142, "")], "Original V7 database failure differs")
        rows = connection.execute("select session_name,name,digest,compressed,body from isabelle_sources").fetchall()
    matches = [r for r in rows if str(r[1]).replace("\\", "/").endswith("/" + source.name) or r[1] == source.name]
    require(len(matches) == 1 and matches[0][0] == target, "Original V7 failed source owner differs")
    row = matches[0]; raw = decompress(bytes(row[4]), row[3], decoder)
    require(raw == source.read_bytes() and hashlib.sha256(raw).hexdigest() == PINS["current-consumer"][0]
            and row[2] == hashlib.sha1(raw).hexdigest(), "Original V7 failed source changed")
    messages = database_messages(database, decoder, target, theory)
    count, passed = MARKERS["current-consumer"]
    require(messages.count(count + "=0") == messages.count(passed) == 1
            and "\x06error_message" not in messages, "Original V7 proof guard differs")
    require(files["compact-poly-receipts/trust12-load-hierarchy.2La11E.ML"].stat().st_size == 75527,
            "Original V7 hierarchy expression size differs")
    return set(files.values())


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(path):
    value = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(8 * 1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


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


def relative_file(base, value):
    require(isinstance(value, str) and value and "\\" not in value and ":" not in value, "Invalid artifact navigation")
    relative = PurePosixPath(value)
    require(not relative.is_absolute() and not PureWindowsPath(value).is_absolute() and ".." not in relative.parts
            and relative.as_posix() == value, "Artifact navigation leaves base")
    path = (base / value).resolve()
    require(path.is_relative_to(base) and path.is_file(), "Missing artifact")
    return path


def strip_comments(source):
    depth, cursor, result = 0, 0, []
    while cursor < len(source):
        pair = source[cursor:cursor + 2]
        if pair == "(*": depth += 1; cursor += 2; continue
        if pair == "*)" and depth: depth -= 1; cursor += 2; continue
        if not depth: result.append(source[cursor])
        cursor += 1
    require(depth == 0, "Unclosed source comment")
    return "".join(result)


def root_identity(text):
    text = strip_comments(text)
    match = re.fullmatch(r'\s*session\s+(\w+)(?:\s+in\s+"\.")?\s*=\s*(\w+)\s*\+\s*options\s*\[[^\]]+\]\s*theories\s+(\w+)\s*', text)
    require(match is not None, "Exact one-session one-theory ROOT required")
    return match.groups()


def zero(value):
    return type(value) is int and value == 0


def successful_result(result, target, method=False):
    if method:
        require(result.get("schema") == "trust12-received-valuation-result-v1"
                and result.get("status") == "PASS_RECEIVED_VALUATION_METHOD_BUILD" and result.get("session") == target
                and result.get("stage") == "method" and result.get("mode") == "build"
                and result.get("builtSessions") == result.get("finishedSessions") == [target]
                and type(result.get("newSessions")) is int and result.get("newSessions") == 1 and zero(result.get("ancestorSessions"))
                and result.get("plannedSessions") == [] and result.get("heapMiB") == 1024
                and result.get("mlTimeoutSeconds") == 30 and result.get("timeoutBuild") is True
                and result.get("threads") == 1 and result.get("quickAndDirty") is False
                and result.get("skipProofs") is False and result.get("recordProofs") is True
                and result.get("systemHeaps") is False, "Method build contract differs")
    else:
        require(result.get("schema") == "trust12-final-chain-stage-result-v1"
                and result.get("status") == "PASS_FINAL_CHAIN_STAGE_BUILT_" + target and result.get("target") == target
                and result.get("dryRun") is False and result.get("expectedNewSessions") in (target, [target])
                and result.get("builtSessions") == result.get("finishedSessions") == [target]
                and all(result.get(key) == [] for key in ("changedInputPaths", "failedSessions", "cancelledSessions", "dryRunWouldBuild", "missingArtifacts"))
                and result.get("runOutOfStore") is False and same_json(result.get("compactPolyReceipts"), {"count": 1, "valid": True})
                and len(result.get("sessions", [])) == 1 and result["sessions"][0].get("session") == target,
                "Final-chain build contract differs")
    require(zero(result.get("exitCode")) and result.get("inputsUnchanged") is True, "Build is incomplete or inputs changed")


def compact_poly_receipt(receipt_dir, policy_sha256):
    """Recheck the one actual completed wrapper receipt; a summary is insufficient."""
    receipt_dir = Path(receipt_dir).resolve()
    require(receipt_dir.is_dir(), "Actual Compact Poly receipt directory is absent")
    files = sorted(receipt_dir.glob("*.json"))
    require(len(files) == 1, "Exactly one actual Compact Poly receipt required")
    path = files[0]
    require(path.is_file() and path.resolve().parent == receipt_dir,
            "Actual Compact Poly receipt leaves its directory")
    value = read_json(path)
    keys = {"schema", "status", "policySha256", "polyExecutable", "originalArgCount",
            "replacementIndexZeroBased", "forwardedArgCount", "maxStdioTarget",
            "expressionBytes", "expressionSha256", "fileBytes", "fileSha256",
            "hashesEqual", "polyExitCode"}
    require(set(value) == keys and value["schema"] == "trust12-compact-poly-hierarchy-receipt-v1"
            and value["status"] == "PASS_COMPACT_POLY_HIERARCHY"
            and value["policySha256"] == policy_sha256
            and isinstance(value["polyExecutable"], str)
            and value["polyExecutable"].endswith("/Isabelle2025-2/contrib/polyml-5.9.2-2/x86_64_32-windows/poly.exe")
            and all(type(value[k]) is int for k in ("originalArgCount", "replacementIndexZeroBased",
                "forwardedArgCount", "maxStdioTarget", "expressionBytes", "fileBytes", "polyExitCode"))
            and value["originalArgCount"] > 1
            and 0 <= value["replacementIndexZeroBased"] < value["originalArgCount"] - 1
            and value["forwardedArgCount"] == value["originalArgCount"] + 2
            and value["maxStdioTarget"] == 2048 and value["polyExitCode"] == 0
            and value["hashesEqual"] is True
            and value["expressionBytes"] == value["fileBytes"] > 0
            and isinstance(value["expressionSha256"], str)
            and re.fullmatch(r"[0-9a-f]{64}", value["expressionSha256"])
            and value["expressionSha256"] == value["fileSha256"],
            "Actual Compact Poly receipt is invalid")
    return {"count": 1, "valid": True, "file": path.name, "bytes": path.stat().st_size,
            "sha256": digest(path), "receipt": value}


def live_rows(rows, checked):
    require(isinstance(rows, list) and rows, "Empty bound input manifest")
    paths = set()
    for row in rows:
        require(isinstance(row, dict) and set(row) in ({"path", "sha256"}, {"path", "bytes", "sha256"})
                and isinstance(row["path"], str) and re.fullmatch(r"[0-9a-f]{64}", row["sha256"]), "Invalid bound input")
        path = Path(row["path"]).resolve()
        require(path not in paths and path.is_file(), "Duplicate or absent bound input")
        require("bytes" not in row or (type(row["bytes"]) is int and path.stat().st_size == row["bytes"]), "Input size drift")
        require(path not in checked or checked[path] == row["sha256"], "Conflicting bound input")
        require(digest(path) == row["sha256"], "Current input drift")
        paths.add(path); checked[path] = row["sha256"]
    return paths


def database_heap_info(database, target):
    with sqlite3.connect(database.resolve().as_uri() + "?mode=ro&immutable=1", uri=True) as connection:
        rows = connection.execute("select session_name,return_code,errors,input_heaps,output_heap from isabelle_session_info").fetchall()
    require(len(rows) == 1 and rows[0][:3] == (target, 0, None), "Database is not the completed exact session")
    def manifest(text):
        require(isinstance(text, str) and text.endswith("\n"), "Invalid native heap manifest")
        result = {}
        for line in text.splitlines():
            match = re.fullmatch(r"([0-9a-f]{40}) ([A-Za-z][A-Za-z0-9_]*)", line)
            require(match is not None and match[2] not in result, "Invalid or duplicate native heap")
            result[match[2]] = match[1]
        return result
    inputs, outputs = manifest(rows[0][3]), manifest(rows[0][4])
    require(set(outputs) == {target}, "Wrong native output heap")
    return inputs, outputs[target]


def heap_identity(heap):
    require(heap.is_file() and heap.stat().st_size > 45, "Incomplete saved heap")
    remaining, value = heap.stat().st_size - 45, hashlib.sha1()
    with heap.open("rb") as handle:
        while remaining:
            block = handle.read(min(8 * 1024 * 1024, remaining))
            require(block, "Truncated heap payload")
            value.update(block); remaining -= len(block)
        trailer = handle.read()
    require(trailer == b"SHA1:" + value.hexdigest().encode("ascii"), "Heap payload/trailer differs")
    return value.hexdigest()


def decompress(raw, compressed, decoder):
    if not compressed: return raw
    if raw.startswith(b"\xfd7zXZ\x00"): return lzma.decompress(raw)
    require(raw.startswith(b"\x28\xb5\x2f\xfd"), "Unknown saved compression")
    return subprocess.run([decoder, "-d", "-q", "--stdout"], input=raw, check=True,
                          capture_output=True, timeout=60).stdout


def saved_source(database, target, source, decoder):
    with sqlite3.connect(database.resolve().as_uri() + "?mode=ro&immutable=1", uri=True) as connection:
        rows = connection.execute("select session_name,return_code,errors,output_heap from isabelle_session_info").fetchall()
        require(len(rows) == 1 and rows[0][:3] == (target, 0, None) and rows[0][3], "Native database is incomplete")
        rows = connection.execute("select session_name,name,digest,compressed,body from isabelle_sources").fetchall()
    matches = [(owner, sha1, compressed, body) for owner, name, sha1, compressed, body in rows
               if str(name).replace("\\", "/").endswith("/" + source.name) or name == source.name]
    require(len(matches) == 1, "Saved source is absent or ambiguous")
    owner, sha1, compressed, body = matches[0]
    require(owner == target, "Stored source owner differs from target session")
    require(decompress(bytes(body), compressed, decoder) == source.read_bytes(), "Stored source is not current byte-exact source")
    require(sha1 == hashlib.sha1(source.read_bytes()).hexdigest(), "Stored source digest differs")


def database_messages(database, decoder, target, theory):
    with sqlite3.connect(database.resolve().as_uri() + "?mode=ro&immutable=1", uri=True) as connection:
        rows = connection.execute("select session_name,theory_name,compressed,body from isabelle_exports where name='PIDE/messages'").fetchall()
    require(len(rows) == 1, "Exactly one native message export required")
    require(rows[0][0] == target, "PIDE message owner differs from target session")
    require(rows[0][1] == target + "." + theory, "PIDE message theory differs from registered source")
    return decompress(bytes(rows[0][3]), rows[0][2], decoder).decode("utf-8", errors="strict")


def reviewed_proof_repair_literals(producer_path):
    import ast
    producer_path = Path(producer_path).resolve()
    require(producer_path.name == "prepare_native_received_valuation_current_v6.py"
            and digest(producer_path) == "2090561cf4b953c3660d8fb10950afe662598a7e0da2bda06e7f616cd21d927a",
            "Reviewed V6 proof producer differs")
    tree = ast.parse(producer_path.read_text(encoding="utf-8-sig"))
    assignments = {}
    for node in tree.body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            require(node.targets[0].id not in assignments, "Duplicate producer assignment")
            assignments[node.targets[0].id] = node.value
    expected = ("STORAGE_OLD", "STORAGE_NEW", "COMMAND_HASH_OLD", "COMMAND_HASH_NEW",
                "EVIDENCE_OLD", "EVIDENCE_NEW", "TIME_OLD", "TIME_NEW")
    require("RAW_FACTS" in assignments and "PROOF_REPAIRS" in assignments
            and all(name in assignments for name in expected), "Four reviewed proof repairs are absent")
    facts = ast.literal_eval(assignments["RAW_FACTS"])
    values = {name: ast.literal_eval(assignments[name]) for name in expected}
    requires = (("STORAGE_OLD", "STORAGE_NEW"), ("COMMAND_HASH_OLD", "COMMAND_HASH_NEW"),
                ("EVIDENCE_OLD", "EVIDENCE_NEW"), ("TIME_OLD", "TIME_NEW"))
    literal_pairs = assignments["PROOF_REPAIRS"]
    require(isinstance(literal_pairs, ast.Tuple) and len(literal_pairs.elts) == 4
            and all(isinstance(pair, ast.Tuple) and len(pair.elts) == 2
                    and all(isinstance(item, ast.Name) for item in pair.elts) for pair in literal_pairs.elts)
            and tuple(tuple(item.id for item in pair.elts) for pair in literal_pairs.elts) == requires,
            "Producer repair order or four sites differ")
    require(isinstance(facts, tuple) and len(facts) == 2 and all(isinstance(item, str) for item in facts)
            and all(isinstance(value, str) and value for value in values.values()),
            "Producer raw definitions or proof bodies differ")
    return list(facts), [(values[left], values[right]) for left, right in requires]


def raw_parent_definition_inverse(source, producer_path):
    facts, repairs = reviewed_proof_repair_literals(producer_path)
    require(source.count("theory TRUST_Native_Received_Valuation_Current_V6\n") == 1,
            "Exact V6 source header required")
    old = source.replace("theory TRUST_Native_Received_Valuation_Current_V6\n",
                         "theory TRUST_Native_Received_Valuation_Current_V5\n", 1)
    for before, after in reversed(repairs):
        require(old.count(after) == 1, "Four exact V6 consumer proof sites required")
        old = old.replace(after, before, 1)
    inserted = "pw_expected_runtime_code_def " + " ".join(facts) + " qi_0014 qi_0001)"
    require(old.count(inserted) == 1 and all(old.count(name) == 1 for name in facts),
            "Two exact parent raw definitions required")
    old = old.replace(inserted, "pw_expected_runtime_code_def qi_0014 qi_0001)", 1)
    require(hashlib.sha256(old.encode("utf-8")).hexdigest() ==
            "820769d470d5d2122a33ed51aba4017480fe1c24cf10460f603081d0cc598e7c",
            "Five-site proof inverse differs from exact failed V5 source")
    return old, facts


def v7_source_inverse(source, producer_path):
    import ast
    producer = Path(producer_path).resolve()
    require(producer.name == "prepare_native_received_valuation_current_v7.py"
            and digest(producer) == "6e2dc8c179fe7ec19dca1a2536205d2b42fe6d7f422c100bfdbfda2258955fad",
            "Reviewed V7 checked-receiver proof producer differs")
    tree = ast.parse(producer.read_text(encoding="utf-8-sig"))
    assignments = {node.targets[0].id: node.value for node in tree.body
                   if isinstance(node, ast.Assign) and len(node.targets) == 1
                   and isinstance(node.targets[0], ast.Name)}
    require(all(name in assignments for name in ("OLD_LEMMA", "STATEMENT", "NEXT_LEMMA")),
            "V7 producer's one old checked-receiver lemma is absent")
    old_lemma, statement, following = (ast.literal_eval(assignments[key])
                                       for key in ("OLD_LEMMA", "STATEMENT", "NEXT_LEMMA"))
    require(source.count("theory TRUST_Native_Received_Valuation_Current_V7\n") == 1
            and source.count(statement) == source.count(following) == 1,
            "V7 source header or the single checked-receiver theorem differs")
    start = source.index(statement)
    end = source.index(following, start)
    block = source[start:end]
    proof = block[len(statement):]
    require(proof.strip() and proof.strip() != "by code_simp"
            and not re.search(r"\b(?:sorry|oops|admit|axiomatization|native_decide)\b|\bby\s+eval\b|(?m:^\s*oracle\s+)", proof),
            "V7 checked-receiver body has an unreviewed proof escape")
    restored = source.replace("theory TRUST_Native_Received_Valuation_Current_V7\n",
                              "theory TRUST_Native_Received_Valuation_Current_V6\n", 1)
    restored = restored.replace(block, old_lemma, 1)
    require(hashlib.sha256(restored.encode("utf-8")).hexdigest() == V6_SOURCE_PINS[0],
            "V7 changes more than one proof body and the theory header")
    return restored, hashlib.sha256(proof.encode("utf-8")).hexdigest()


def root_v6_inverse(root):
    require(root.count("TRUST12_NATIVE_RECEIVED_VALUATION_CURRENT_V7") == 1
            and root.count("TRUST_Native_Received_Valuation_Current_V7") == 1,
            "Exact V7 ROOT child identity required")
    old = root.replace("TRUST12_NATIVE_RECEIVED_VALUATION_CURRENT_V7",
                       "TRUST12_NATIVE_RECEIVED_VALUATION_CURRENT_V6", 1)
    old = old.replace("TRUST_Native_Received_Valuation_Current_V7",
                      "TRUST_Native_Received_Valuation_Current_V6", 1)
    require(hashlib.sha256(old.encode("utf-8")).hexdigest() == V6_SOURCE_PINS[1],
            "V7 ROOT changes the frozen parent/options")
    return old


def root_v5_inverse(root):
    require(root.count("TRUST12_NATIVE_RECEIVED_VALUATION_CURRENT_V6") == 1
            and root.count("TRUST_Native_Received_Valuation_Current_V6") == 1,
            "Exact V6 ROOT child identity required")
    old = root.replace("TRUST12_NATIVE_RECEIVED_VALUATION_CURRENT_V6",
                       "TRUST12_NATIVE_RECEIVED_VALUATION_CURRENT_V5", 1)
    old = old.replace("TRUST_Native_Received_Valuation_Current_V6",
                      "TRUST_Native_Received_Valuation_Current_V5", 1)
    require(hashlib.sha256(old.encode("utf-8")).hexdigest() ==
            "40d59f40507e5906c90bfd4a3e3c6b7468122a03f9e7a35e2e4663f8a8d95556",
            "V6 ROOT changes the frozen parent/options")
    return old


def congruence_attribute_inverse(source):
    internal = re.compile(r"\b(rv_cong_qav_[0-9]{4})\[where left_values=left_values and right_values=right_values, OF (WORD|TIME)\]")
    require(source.count("theory TRUST_Native_Received_Valuation_Current_V5\n") == 1
            and len(internal.findall(source)) == 419
            and not re.search(r"\brv_cong_qav_[0-9]{4}\[OF (?:WORD|TIME)\]", source),
            "Explicit local congruence proof attributes differ")
    restored = source.replace("theory TRUST_Native_Received_Valuation_Current_V5\n",
                              "theory TRUST_Native_Received_Valuation_Current_V4\n", 1)
    restored = internal.sub(lambda match: match[1] + "[OF " + match[2] + "]", restored)
    for name in ("rv_cong_qav_0518", "rv_cong_qav_0560"):
        bound = name + '[where left_values="rv_valuation 1 1700000000" and right_values=ci_variable_value, OF rv_only_needed_names(2)]'
        require(restored.count(bound) == 1, "Explicit final observation values differ")
        restored = restored.replace(bound, name + "[OF rv_only_needed_names(2)]", 1)
    require(hashlib.sha256(restored.encode("utf-8")).hexdigest() ==
            "bdfdf8f1eb8e812abc170de785aee8dbb30426296a62c8a8bdfb955fb9ce6902",
            "Proof attribute inverse changes the exact original body, statements or domain")
    return restored


def guarded_source(source, stage, producer_path=None, ancestor_producer_path=None):
    clean = strip_comments(source)
    roots = re.findall(r"val (?:nse_)?roots = \[(.*?)\];", clean, re.S)
    require(len(roots) == 1 and re.findall(r"@\{thm ([^}]+)\}", roots[0]) == ROOTS[stage], "Guarded root order/count changed")
    require(not re.search(r"\b(?:sorry|oops|admit|axiomatization|native_decide)\b|\bby\s+eval\b|(?m:^\s*oracle\s+)", clean)
            and "Thm_Deps.all_oracles" in clean and "Thm_Deps.has_skip_proof" in clean
            and "null " in clean and "andalso not " in clean, "Proof dependency guard or trust boundary changed")
    for name in ROOTS[stage]:
        # The status guard deliberately includes a fact inherited from its
        # primary parent; it is audited through the saved native dependency guard.
        if name != "nsr_received_first_freeze_bound":
            require(re.search(r"(?m)^(?:lemma|theorem) " + re.escape(name.split("(")[0]) + r"\b", clean), "Guard names an absent theorem")
    if stage == "current-consumer":
        counts = {"rv_execution": 8, "rv_receive_current": 5, "rv_receive_current_without_time": 3}
        require(producer_path is not None, "Reviewed V6 producer required for five-site source inverse")
        require(producer_path is not None and ancestor_producer_path is not None, "Both reviewed V7/V6 producers required")
        v6_source, _ = v7_source_inverse(source, producer_path)
        v5_source, _ = raw_parent_definition_inverse(v6_source, ancestor_producer_path)
        v4_source = congruence_attribute_inverse(v5_source)
        restored = v4_source.replace("theory TRUST_Native_Received_Valuation_Current_V4\n",
                                  "theory TRUST_Native_Received_Valuation_Current_V3\n", 1)
        for name, count in counts.items():
            phrase = name + " keccak word_bytes freeze_gas"
            require(restored.count(phrase) == count and not re.search(r"\b" + name + r" keccak word_bytes(?! freeze_gas)", restored), "Gas use differs")
            restored = restored.replace(phrase, name + " keccak word_bytes")
            pattern = re.compile(r'(?ms)^definition ' + name + r' :: "(.*?)" where')
            matches = list(pattern.finditer(restored)); require(len(matches) == 1, "Missing explicit gas signature")
            match = matches[0]
            old = (r'(kore_bytes \<Rightarrow> nat) \<Rightarrow> trust_transaction_execution' if name == "rv_execution"
                   else r'kore_substitution \<Rightarrow> trust_transaction_execution option')
            inserted = r'nat \<Rightarrow> ' + old
            require(match[1].count(inserted) == 1, "Natural gas argument position differs")
            restored = restored[:match.start()] + match[0].replace(inserted, old, 1) + restored[match.end():]
        require(hashlib.sha256(restored.encode("utf-8")).hexdigest() == "9c41faf1dc31d5069a73f079acfe8bee453b03865823b05ff90883ceacddf069",
                "Gas repair inverse changes original body, premises or propositions")
        require(len(re.findall(r"(?m)^lemma rv_cong_qav_", clean)) == 333, "Observation congruence inventory differs")
        premise_blocks = re.findall(r"(?ms)^context\n(.*?)^begin\n", clean)
        require(len(premise_blocks) == 1 and len(re.findall(r'(?:assumes|and)\s+(?:K_[A-Za-z0-9]+|WB_buf):', premise_blocks[0])) == 23,
                "Original conditional premises differ")


def audit_contract(audit, stage, records, messages, target):
    expected = {"status-gate": ("trust12-native-status-typegate-saved-audit-v1", "PASS_SAVED_CONCRETE_STATUS_TYPE_GATE_AUDITED"),
                "received-method": ("trust12-received-valuation-method-audit-v3", "PASS_SAVED_RECEIVED_VALUATION_METHOD_AUDITED"),
                "current-consumer": ("trust12-received-valuation-current-audit-v1", "PASS_SAVED_RECEIVED_VALUATION_CURRENT_V7_AUDITED")}[stage]
    require((audit.get("schema"), audit.get("status")) == expected and zero(audit.get("oracleDependencies"))
            and audit.get("skipProofs") is False and audit.get("pideMessagesSha256") == hashlib.sha256(messages.encode()).hexdigest(), "Saved audit/message identity differs")
    for field, role in (("resultSha256", "result"), ("sourceSha256", "source"), ("rootSha256", "root"), ("bindingSha256", "binding")):
        require(audit.get(field) == records[stage + "-" + role]["sha256"], "Saved audit input hash differs")
    count, passed = MARKERS[stage]
    start, end = r"(?<![A-Za-z0-9_.+-])", r"(?![A-Za-z0-9_.+-])"
    require("\x06error_message" not in messages and messages.count(count + "=") == messages.count(passed) == 1
            and re.findall(start + re.escape(count) + r"=([0-9]+)" + end, messages) == ["0"]
            and len(re.findall(start + re.escape(passed) + end, messages)) == 1, "Actual native dependency guard differs")
    if stage == "status-gate":
        require(audit.get("target") == target and audit.get("sessionErrors") == [] and len(audit.get("retainedPremises", [])) == 23
                and audit.get("inferenceGateConsumed") is True and audit.get("newTrustedComponents") == []
                and all(audit.get(key) is False for key in ("operationalKReceiverDischarged", "generalRuntimeLinkDischarged", "centralClosureDischarged", "independentAssuranceCompleted", "freshKernelReplay")), "Status audit scope changed")
    elif stage == "received-method":
        require(audit.get("rootCount") == 17 and audit.get("currentBindingPins") == 38
                and audit.get("currentSnapshotUniqueRows") == 123 and zero(audit.get("databaseReturnCode"))
                and audit.get("databaseErrors") is None and audit.get("storedSourceByteExact") is True
                and audit.get("currentG37Credit") is False and all(audit.get(k) is False for k in FALSE_CREDITS), "Method audit scope changed")
    else:
        require(audit.get("target") == target and audit.get("roots") == CURRENT_ROOTS and audit.get("originalPremisesCount") == 23
                and audit.get("selectedCongruences") == 333 and audit.get("storedSourceByteExact") is True
                and audit.get("primaryParentLineageMatches") is True and audit.get("snapshotsUnchanged") is True
                and audit.get("existingMethodIndependentEvidence") is True
                and audit.get("explicitCongruenceInstantiations") == 421
                and audit.get("parentRawDefinitionsExpanded") == 2
                and same_json(audit.get("retryProvenance"), RETRY_PROVENANCE)
                and audit.get("freshKernelReplay") is False
                and audit.get("diagnosticMethodNativeParent") is False
                and all(audit.get(k) is False for k in ("originalSource", "general", "central", "independentAssurance")), "Current audit scope changed")
        for field, role in (("heapSha256", "heap"), ("databaseSha256", "database"), ("inputsBeforeSha256", "inputs-before"), ("inputsAfterSha256", "inputs-after")):
            require(audit.get(field) == records[stage + "-" + role]["sha256"], "Current saved audit artifact differs")
        require(audit.get("runnerSha256") == CURRENT_RUNNER_SHA256, "Current runner audit differs")
        require(same_json(audit.get("executionProfile"), {"sourceTimeoutSeconds": 120, "timeoutScale": 5, "effectiveMlTimeoutSeconds": 600}),
                "Current saved execution profile differs")


def public_contract(checkpoint):
    require(set(checkpoint) == PUBLIC_KEYS and checkpoint["schema"] == SCHEMA and checkpoint["status"] == STATUS
            and checkpoint["scope"] == SCOPE and same_json(checkpoint["coverage"], COVERAGE)
            and checkpoint["identityBoundary"] == BOUNDARY and checkpoint["reproductionBoundary"] == REPRODUCTION
            and same_json(checkpoint["retryProvenance"], RETRY_PROVENANCE),
            "Public checkpoint scope or schema differs")
    encoded = json.dumps(checkpoint, ensure_ascii=False)
    require(encoded.isascii() and not PRIVATE.search(encoded), "Private data or non-English public metadata")
    require(set(checkpoint["claims"]) == set(NONCLAIMS) and all(v is False for v in checkpoint["claims"].values()), "Stronger claims must remain false")
    require([s.get("id") for s in checkpoint["kernelStages"]] == list(STAGES), "Stage order differs")


def verify_checkpoint(checkpoint, index, base, product, zstd):
    base, product = Path(base).resolve(), Path(product).resolve()
    public_contract(checkpoint)
    require(re.fullmatch(r"[0-9a-f]{64}", CURRENT_RUNNER_SHA256),
            "Reviewed current runner identity remains unconfirmed")
    verify_first_attempt(base)
    verify_retry1_failure(base)
    require(all(isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value)
                for value in PINS["current-consumer"]),
            "Reviewed current source/ROOT/binding pins require actual native success")
    expected_ids = {stage + "-" + role: kind for stage in STAGES for role, kind in ROLES.items()}
    rows = checkpoint["artifacts"]
    require(isinstance(rows, list) and len(rows) == len(expected_ids) == 27, "Artifact count differs")
    records = {r["id"]: r for r in rows}
    require(set(records) == set(index) == set(expected_ids) and len(records) == len(rows), "Artifact IDs are duplicate or incomplete")
    files, checked = {}, {}
    for aid, row in records.items():
        require(set(row) == {"id", "kind", "bytes", "sha256"} and row["kind"] == expected_ids[aid]
                and type(row["bytes"]) is int and row["bytes"] > 0 and re.fullmatch(r"[0-9a-f]{64}", row["sha256"]), "Artifact record differs")
        path = relative_file(base, index[aid])
        require(path.stat().st_size == row["bytes"] and digest(path) == row["sha256"], "Artifact drift")
        files[aid] = path; checked[path] = row["sha256"]
    require(len(set(files.values())) == len(files), "Artifact navigation aliases distinct IDs")
    require(set(checkpoint["productIdentity"]) == set(PRODUCTS), "Product identity inventory differs")
    product_files = []
    for key, (relative, size, sha) in PRODUCTS.items():
        require(checkpoint["productIdentity"][key] == {"path": relative, "bytes": size, "sha256": sha}, "Product identity scope differs")
        path = relative_file(product, relative)
        require(path.stat().st_size == size and digest(path) == sha, "Current product source differs")
        checked[path] = sha; product_files.append(path)
    verifier = checkpoint["rehashVerifier"]
    require(set(verifier) == {"path", "bytes", "sha256", "command"} and verifier["path"] == VERIFIER_PATH
            and verifier["command"] == COMMAND and type(verifier["bytes"]) is int and verifier["bytes"] > 0
            and re.fullmatch(r"[0-9a-f]{64}", verifier["sha256"]), "Verifier contract differs")
    verifier_file = relative_file(product, VERIFIER_PATH)
    require(Path(__file__).resolve() == verifier_file and verifier_file.stat().st_size == verifier["bytes"]
            and digest(verifier_file) == verifier["sha256"], "Executing checker identity differs")
    checked[verifier_file] = verifier["sha256"]
    decoder = str(Path(zstd).resolve()) if Path(zstd).is_file() else shutil.which(zstd)
    require(decoder is not None, "Existing Zstandard decoder required")
    for path in verify_original_v7_failure(base, decoder):
        checked[path] = digest(path)
    bindings, stage_paths, targets = {}, {}, {}
    for stage in STAGES:
        f = {role: files[stage + "-" + role] for role in ROLES}
        require(tuple(records[stage + "-" + role]["sha256"] for role in ("source", "root", "binding")) == PINS[stage],
                "Reviewed source, ROOT or binding changed")
        if stage == "current-consumer":
            root_v5_inverse(root_v6_inverse(f["root"].read_text(encoding="utf-8-sig")))
        source = f["source"].read_text(encoding="utf-8-sig")
        target, parent, theory = root_identity(f["root"].read_text(encoding="utf-8-sig"))
        require(re.search(r"(?m)^theory " + re.escape(theory) + r"\s*$", source) is not None, "ROOT/source theory differs")
        result, binding = read_json(f["result"]), read_json(f["binding"])
        producers = [Path(row["path"]).resolve() for row in binding.get("inputs", [])
                     if Path(row["path"]).name == "prepare_native_received_valuation_current_v7.py"]
        ancestors = [Path(row["path"]).resolve() for row in binding.get("inputs", [])
                     if Path(row["path"]).name == "prepare_native_received_valuation_current_v6.py"]
        require(stage != "current-consumer" or (len(producers) == len(ancestors) == 1),
                "Current V7 producer or frozen V6 producer is absent or ambiguous")
        guarded_source(source, stage, producers[0] if stage == "current-consumer" else None,
                       ancestors[0] if stage == "current-consumer" else None)
        successful_result(result, target, stage == "received-method")
        before, after = (read_json(f[key], False) for key in ("inputs-before", "inputs-after"))
        require(same_json(before, after), "Actual run snapshots differ")
        paths = live_rows(before, checked) | live_rows(binding.get("inputs"), checked)
        require({f["source"], f["root"], f["binding"]} <= paths, "Run snapshots omit actual stage source")
        decoder_paths = [p for p in paths if p.name.lower() in ("zstd", "zstd.exe")]
        require(decoder_paths and all(digest(Path(decoder)) == checked[p] for p in decoder_paths), "Decoder differs from actual bound tool")
        if stage == "status-gate":
            require(binding.get("schema") == "trust12-native-status-typegate-canary-input-v1"
                    and binding.get("parentSession") == parent and binding.get("theorySha256") == PINS[stage][0]
                    and binding.get("rootSha256") == PINS[stage][1] and binding.get("newTrustedComponents") == [], "Status binding differs")
        else:
            require(binding.get("schema") == "trust12-received-valuation-input-v1"
                    and binding.get("status") == "PREPARED_NOT_KERNEL_CHECKED" and binding.get("stage") == ("method" if stage == "received-method" else "current")
                    and binding.get("session") == target and binding.get("theory") == theory
                    and binding.get("metadata", {}).get("parent") == parent
                    and binding.get("sourceSha256") == PINS[stage][0]
                    and binding.get("rootSha256") == PINS[stage][1] and binding["metadata"].get("roots") == ROOTS[stage]
                    and all(binding.get(k) is False for k in FALSE_CREDITS), "Received valuation binding differs")
            require(binding["metadata"]["fixture"] == {"syntheticTwoIntAnd": True, "sourceNames": ["Var'Ques'WORD", "VarTIMESTAMP'Unds'CELL"],
                                                      "normalValues": [1, 1700000000], "defaultForOtherNames": 0}, "Two-variable fixture changed")
        require(binding.get("session") == target and binding.get("kernelChecked") is False, "Prepared binding identity or credit changed")
        artifact = result if stage == "received-method" else result["sessions"][0]
        for role in ("heap", "database"):
            require(artifact[role]["sha256"] == records[stage + "-" + role]["sha256"]
                    and (stage == "received-method" or artifact[role]["bytes"] == records[stage + "-" + role]["bytes"]), "Build saved artifact differs")
        parent_heap = [p for p in paths if p.name == parent]
        parent_db = [p for p in paths if p.name == parent + ".db"]
        require(len(parent_heap) == len(parent_db) == 1, "Bound actual primary parent is absent or ambiguous")
        inputs, output = database_heap_info(f["database"], target)
        _, parent_output = database_heap_info(parent_db[0], parent)
        require(output == heap_identity(f["heap"]) and inputs.get(parent) == parent_output == heap_identity(parent_heap[0]), "Actual primary parent lineage differs")
        parent_roots = []
        for path in paths:
            if path.name == "ROOT":
                text = strip_comments(path.read_text(encoding="utf-8-sig"))
                if re.search(r"(?m)^session\s+" + re.escape(parent) + r"\b", text):
                    parent_roots.append(text)
        require(len(parent_roots) == 1, "Bound primary parent ROOT is absent or ambiguous")
        registered_theories = re.search(r"\btheories\s+([A-Za-z][A-Za-z0-9_]*(?:\s+[A-Za-z][A-Za-z0-9_]*)*)\s*$", parent_roots[0])
        require(registered_theories is not None, "Primary parent theory registration absent")
        parent_theories = registered_theories[1].split()
        for name in parent_theories:
            parent_sources = [p for p in paths if p.name == name + ".thy"]
            require(len(parent_sources) == 1, "Bound primary parent source is absent or ambiguous")
            saved_source(parent_db[0], parent, parent_sources[0], decoder)
        saved_source(f["database"], target, f["source"], decoder)
        messages = database_messages(f["database"], decoder, target, theory)
        audit = read_json(f["audit"]); audit_contract(audit, stage, records, messages, target)
        if stage == "current-consumer":
            require(audit.get("outputHeapIdentity") == output
                    and audit.get("primaryParentHeapIdentity") == parent_output
                    and audit.get("currentSnapshotUniqueRows") == len(before)
                    and audit.get("currentUnionUniqueRows") == len(paths),
                    "Current audit native heap/snapshot identity differs")
        expected_stage = {"id": stage, "guardedRoots": len(ROOTS[stage]), "oracleDependencies": 0,
                          "skipProofs": False, "storedSourceByteExact": True,
                          "outputHeapIdentity": output, "primaryParentHeapIdentity": parent_output,
                          "primaryParentHeapSha256": checked[parent_heap[0]], "primaryParentDatabaseSha256": checked[parent_db[0]],
                          "primaryParentRole": "status-gate" if stage == "current-consumer" else "saved-ancestor",
                          "role": "independent-method-evidence" if stage == "received-method" else "native-consumer-lineage"}
        require(same_json(checkpoint["kernelStages"][STAGES.index(stage)], expected_stage), "Public stage lineage metadata differs")
        bindings[stage], stage_paths[stage], targets[stage] = binding, paths, (target, parent)
        if stage == "received-method":
            require(result.get("sourceSha256") == PINS[stage][0] and result.get("rootSha256") == PINS[stage][1]
                    and result.get("bindingSha256") == PINS[stage][2]
                    and result.get("inputsBeforeSha256") == records[stage + "-inputs-before"]["sha256"]
                    and result.get("inputsAfterSha256") == records[stage + "-inputs-after"]["sha256"]
                    and result.get("parentHeapSha256") == checked[parent_heap[0]] and result.get("parentDatabaseSha256") == checked[parent_db[0]], "Method result binding differs")
        if stage == "current-consumer":
            policies = [p for p in paths if p.name == "poly_compact_hierarchy_policy_v3.sh"]
            require(len(policies) == 1, "Bound Compact Poly policy absent or ambiguous")
            receipt_dir = base / "final-chain-v2/runs/native-received-valuation-current-v7-save-v1-build/compact-poly-receipts"
            require(receipt_dir.resolve().is_relative_to(base), "Compact Poly receipts leave evidence base")
            actual_receipt = compact_poly_receipt(receipt_dir, checked[policies[0]])
            require(actual_receipt["receipt"]["expressionSha256"] == RETRY_PROVENANCE["v7LoadExpressionSha256"]
                    and actual_receipt["receipt"]["expressionBytes"] == 75527,
                    "Current actual hierarchy expression differs from frozen V7")
            require(same_json(audit.get("compactPolyReceipts"), actual_receipt),
                    "Current Compact Poly receipt differs from saved audit")
            checked[receipt_dir / actual_receipt["file"]] = actual_receipt["sha256"]
            runners = [p for p in paths if p.name == "run_native_received_valuation_current_v7_saved_v1.ps1"]
            require(len(runners) == 1 and checked[runners[0]] == audit["runnerSha256"], "Actual bound current runner differs from saved audit")
            require(result.get("mlTimeoutSeconds") == 600 and result.get("sourceTimeoutSeconds") == 120
                    and result.get("timeoutScale") == 5 and result.get("timeoutBuild") is True
                    and result.get("originalV7FailureKernelCredit") is False
                    and result.get("planReuseBoundary") == "Original V7 DR on unchanged proof inputs; build-only timeout_scale=5 is a distinct execution profile"
                    and result.get("mlOptions") == "--minheap 400 --maxheap 2048 --gcthreads 2"
                    and result.get("javaMaxHeapGB") == 2
                    and result.get("stage") == "native-received-valuation-current-v7-save-v1-build"
                    and binding.get("inputManifestCount") == len(binding["inputs"]) == 293
                    and binding.get("reusedCurrentV6InputCount") == 277, "Current source or execution profile changed")
    current = bindings["current-consumer"]; paths = stage_paths["current-consumer"]
    require(targets["current-consumer"][1] == targets["status-gate"][0]
            and targets["received-method"][0] != targets["current-consumer"][1]
            and current["parents"]["currentParent"]["resultSha256"] == records["status-gate-result"]["sha256"]
            and current["parents"]["methodCompleted"]["resultSha256"] == records["received-method-result"]["sha256"], "Independent method/primary lineage conflated")
    require({files["status-gate-" + role] for role in ("source", "root", "binding", "result", "heap", "database")} <= paths
            and {files["received-method-" + role] for role in ("source", "root", "binding", "result", "heap", "database")} <= paths
            and set(product_files) <= paths, "Current binding does not consume exact parent/evidence/product identities")
    producer = [p for p in paths if p.name == "prepare_native_received_valuation_current_v6.py"]
    successor = [p for p in paths if p.name == "prepare_native_received_valuation_current_v7.py"]
    require(len(producer) == len(successor) == 1
            and checked[producer[0]] == current["frozenCurrentV6HelperSha256"] ==
            "2090561cf4b953c3660d8fb10950afe662598a7e0da2bda06e7f616cd21d927a"
            and checked[successor[0]] == current["generatorSha256"] ==
            "6e2dc8c179fe7ec19dca1a2536205d2b42fe6d7f422c100bfdbfda2258955fad",
            "Reviewed V7 producer or frozen V6 producer is absent from actual bound inputs")
    repair = current["metadata"].get("parentRawDefinitionRepair")
    source_text = files["current-consumer-source"].read_text(encoding="utf-8-sig")
    v6_source, proof_sha = v7_source_inverse(source_text, successor[0])
    _, names = raw_parent_definition_inverse(v6_source, producer[0])
    require(isinstance(repair, dict)
            and repair.get("oldSourceSha256") == "820769d470d5d2122a33ed51aba4017480fe1c24cf10460f603081d0cc598e7c"
            and repair.get("oldRootSha256") == "40d59f40507e5906c90bfd4a3e3c6b7468122a03f9e7a35e2e4663f8a8d95556"
            and repair.get("qualifiedParentDefinitionNames") == names
            and repair.get("changedProofLocations") == 5 and repair.get("addedPremises") == 0
            and repair.get("theoremStatementsPreserved") is True and repair.get("proofBodyInverseByteExact") is True
            and repair.get("semanticDomainChanged") is False and repair.get("editorCandidateMatchedAtPreparation") is True
            and repair.get("pideValidationClaimedByPreparer") is False and repair.get("kernelChecked") is False
            and current.get("frozenCurrentV5BindingSha256") == "2ce0093b5d1ab22080d985c32e3d39b331eacef0159df51df3e93635156e2c65"
            and current.get("reusedCurrentV5InputCount") == 262
            and current.get("inputManifestCount") == len(current["inputs"]) == 293,
            "V6 proof repair provenance or source-only credit differs")
    producer_names, producer_repairs = reviewed_proof_repair_literals(producer[0])
    require(producer_names == names and len(producer_repairs) == 4,
            "V6 source does not use the reviewed producer's five exact proof sites")
    current_repair = current["metadata"].get("checkedReceiverProofRepair")
    require(isinstance(current_repair, dict)
            and current_repair.get("oldSourceSha256") == V6_SOURCE_PINS[0]
            and current_repair.get("oldRootSha256") == V6_SOURCE_PINS[1]
            and current_repair.get("proofSite") == "rv_normal_checked"
            and current_repair.get("newProofBodySha256") == proof_sha
            and current_repair.get("editedProofLocations") == 1
            and current_repair.get("theoremStatementPreserved") is True
            and current_repair.get("proofBodyInverseByteExact") is True
            and current_repair.get("semanticDomainChanged") is False
            and current_repair.get("editorCandidateMatchedAtPreparation") is True
            and current_repair.get("editorCandidateSha256") == PINS["current-consumer"][0]
            and current_repair.get("pideValidationClaimedByPreparer") is False
            and current_repair.get("kernelChecked") is False
            and current.get("frozenCurrentV6BindingSha256") == V6_SOURCE_PINS[2]
            and current.get("reusedCurrentV6InputCount") == 277,
            "One-site V7 receiver repair or source-only credit differs")
    failed_attempts = current.get("failedCurrentV6Attempts")
    require(isinstance(failed_attempts, dict)
            and failed_attempts.get("bothNoncredit") is True
            and failed_attempts.get("sourceAndRootUnchanged") is True,
            "Both V6 failures must remain noncredit provenance")
    for key, result_sha, database_sha, snapshot_sha, free_bytes in (
        ("initial", RETRY_PROVENANCE["resultSha256"], RETRY_PROVENANCE["databaseSha256"],
         "831253a843bbc3f70393121a77b138c2aa0cb3d54f7b863d111b794ce4e79ec4", 16859136),
        ("retry1", RETRY_PROVENANCE["retry1ResultSha256"], RETRY_PROVENANCE["retry1DatabaseSha256"],
         "dc2f24178b88fdce2f2525d2d711f7d51de3ab8edb376316111b178b72b1cfa1", 2370469888)):
        item = failed_attempts.get(key)
        require(isinstance(item, dict) and item.get("status") ==
                "INCOMPLETE_FINAL_CHAIN_STAGE_TRUST12_NATIVE_RECEIVED_VALUATION_CURRENT_V6"
                and item.get("resultSha256") == result_sha
                and item.get("databaseSha256") == database_sha
                and item.get("errorsSha256") == RETRY_PROVENANCE["errorsSha256"]
                and item.get("inputSnapshotSha256") == snapshot_sha
                and item.get("inputRows") == 3924
                and item.get("minFreePhysicalBytesObserved") == free_bytes
                and item.get("timeout") is True
                and item.get("storedSourceCredit") is False
                and item.get("kernelCredit") is False,
                "An incomplete V6 native attempt was promoted or reidentified")
    failure = current.get("failedCurrentV5")
    require(isinstance(failure, dict) and failure.get("resultSha256") ==
            "1b7b99178cb0ec7db7da4bc600af7d0db7b0d392263fafbf206dce4e65d0a019"
            and failure.get("databaseSha256") == "70be6bf73bf0d30dc79fc738820823cd03f67f58afe7780f5017d47aa50bdc3a"
            and failure.get("fullErrorsSha256") == "d02acc10e169de14c6c9b7a01ed7476f7c46643ef4a9c0374ac1e0103f2e292e"
            and failure.get("sourceSha256") == "820769d470d5d2122a33ed51aba4017480fe1c24cf10460f603081d0cc598e7c"
            and failure.get("bindingSha256") == current["frozenCurrentV5BindingSha256"]
            and failure.get("inputRows") == 3909 and failure.get("bindingInputs") == 262
            and failure.get("storedSourceByteExact") is True and failure.get("kernelCredit") is False,
            "Frozen V5 failure cannot be promoted into a V6 result")
    diagnostic = current.get("diagnosticMethodEvidence")
    require(isinstance(diagnostic, dict) and diagnostic.get("status") == "PASS_SAVED_EXPLICIT_FUNCTION_INSTANTIATION_METHOD"
            and diagnostic.get("diagnosticEvidenceOnly") is True and diagnostic.get("nativeParent") is False
            and diagnostic.get("currentConsumerCredit") is False and diagnostic.get("storedSourceByteExact") is True
            and diagnostic.get("skipProofs") is False and zero(diagnostic.get("oracleDependencies"))
            and diagnostic.get("inputRowsCurrentlyRehashed") == 10,
            "Diagnostic method evidence cannot become a native parent or current credit")
    require(current["metadata"]["g37"]["originalG37Premises"] == 23 and current["metadata"]["g37"]["selectedCongruences"] == 333
            and current["metadata"]["wholeValuationEqualityRequired"] is False and current["metadata"]["wholeWorldEqualityRequired"] is False,
            "Observation-only conditional scope changed")
    for path, expected in checked.items():
        require(digest(path) == expected, "Inputs changed during verification")
    return {"schema": "trust12-native-received-valuation-rehash-v1", "status": "PASS_SAVED_CONDITIONAL_RECEIVED_VALUATION_REHASHED",
            "artifactsRehashed": 27, "kernelStagesRehashed": 3, "currentInputsRehashed": len(checked),
            "guardedRootCounts": [12, 17, 26], "oracleDependencies": 0, "claims": {key: False for key in NONCLAIMS},
            "reproductionBoundary": REPRODUCTION}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("base", "product-root", "checkpoint", "artifact-index"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--zstd", default="zstd"); parser.add_argument("--out", type=Path)
    args = parser.parse_args(); base, product = args.base.resolve(), args.product_root.resolve()
    require(args.checkpoint.resolve() == (product / CHECKPOINT_PATH).resolve(), "Unexpected public checkpoint location")
    require(args.artifact_index.resolve().parent == base and args.artifact_index.name == INDEX_NAME, "Private index must be one file directly under base")
    report = verify_checkpoint(read_json(args.checkpoint), read_json(args.artifact_index), base, product, args.zstd)
    if args.out:
        with args.out.open("x", encoding="utf-8", newline="\n") as handle:
            handle.write(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2)); return 0


if __name__ == "__main__":
    try: raise SystemExit(main())
    except (RuntimeError, OSError, ValueError, KeyError, TypeError, sqlite3.Error, subprocess.SubprocessError):
        raise SystemExit("FAIL_RECEIVED_VALUATION_CHECKPOINT: evidence rejected")
