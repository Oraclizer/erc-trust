#!/usr/bin/env python3
"""Independent static reverse check for the SEP-04 row skeleton.

This checker deliberately reports STATIC_SKELETON_PASS, never proof PASS.  The
common row runner can invoke it with python3 once a schema-valid bundle exists.
"""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path


ROW_ROOT = Path(__file__).resolve().parent
REPOSITORY_ROOT = ROW_ROOT.parents[3]
BRIDGE_PATH = ROW_ROOT / "bridge" / "row-bridge.json"
MANIFEST_PATH = ROW_ROOT / "bridge" / "row-manifest.json"
SKELETON_PATH = ROW_ROOT / "bundle.skeleton.json"
COMPOSITION_PATH = ROW_ROOT / "composition-graph.json"
DEPENDENCY_PATH = ROW_ROOT / "dependency-graph.json"
RUNNER_PATH = ROW_ROOT / "runner-descriptor.skeleton.json"
TEMPLATE_PATH = ROW_ROOT / "claim-template.k.in"
PARSE_HELPER_PATH = ROW_ROOT / "parse-claims.py"
MATERIALIZED_BUNDLE_PATH = ROW_ROOT / "bundle.json"
MATERIALIZED_CLAIM_PATH = ROW_ROOT / "claim.k"
MUTANT_CONTROL_CLAIM_PATH = ROW_ROOT / "mutant-control-claim.k"
EVIDENCE_ROOT = REPOSITORY_ROOT / "evidence" / "end-to-end-refinement"
OBLIGATION_INDEX_PATH = EVIDENCE_ROOT / "obligation-evidence-index.json"
INVENTORY_PATH = EVIDENCE_ROOT / "theorem-obligations.md"
RUNTIME_SCHEMA_PATH = EVIDENCE_ROOT / "runtime-bridge" / "schema.json"
LOCK_PATH = REPOSITORY_ROOT / "formal" / "kevm" / "dependencies.lock.json"
RESOLVED_RUNTIME_PATH = (
    REPOSITORY_ROOT
    / "evidence"
    / "end-to-end-refinement"
    / "runtime-binding"
    / "resolved"
    / "native"
    / "TrustToken.hex"
)
CANONICAL_BRIDGE_PATH = REPOSITORY_ROOT / "formal" / "kevm" / "generated" / "trust-runtime-bridge.k"
GENERATED_ISABELLE_BRIDGE_PATH = (
    REPOSITORY_ROOT / "formal" / "isabelle" / "ERC_TRUST" / "TRUST_Runtime_Bridge_Generated.thy"
)
INTERFACE_PATH = REPOSITORY_ROOT / "implementation" / "src" / "interfaces" / "IERCTrust.sol"
TOKEN_SOURCE_PATH = REPOSITORY_ROOT / "implementation" / "src" / "TrustToken.sol"
TRANSACTION_THEORY_PATH = (
    REPOSITORY_ROOT / "formal" / "isabelle" / "ERC_TRUST" / "TRUST_Transaction_Refinement.thy"
)
OBLIGATION_ID = "SEP-04"
REQUIRED_PROPERTY = "`receipt_preimage_matches_storage_return_and_final_event`"
THEOREM_NAME = "receipt_preimage_matches_storage_return_and_final_event"
POSITIVE_MODULE = "TRUST-SEP-04-RECEIPT-PREIMAGE-STORAGE-RETURN-FINAL-EVENT-SPEC"
CONTROL_MODULE = "TRUST-SEP-04-MUTANT-EVENT-TOPIC-CONTROL-SPEC"
PLACEHOLDER_SHA256 = "e4fcabd40c8b18e3900050a590b6b80c687d4d115f61bc12439af6099e83434e"
LOCK_SHA256 = "3134e7692086170f86b6dd42e7ebd0256c188da8db8cbd17241c3d2c8d315196"
CANONICAL_TOPIC = "aadd5db99c0c1f57ce6f82b109958a00899fc4cea03e70fdae7741b9e7050091"
MUTANT_TOPIC = "ab" + CANONICAL_TOPIC[2:]
CLAIM_TEMPLATE_TEXT = TEMPLATE_PATH.read_text(encoding="utf-8")
DECLARED_PORTS = sorted(set(re.findall(r"@@([A-Z0-9_]+)@@", CLAIM_TEMPLATE_TEXT)))


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def canonical(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()


def source_block(path: Path, start_token: str, end_token: str) -> bytes:
    text = path.read_text(encoding="utf-8")
    start = text.find(start_token)
    end = text.find(end_token, start + len(start_token))
    require(start >= 0 and end >= 0, f"source block drift: {start_token}")
    return text[start:end].encode()


def check_safe_json_numbers(value: object, path: str = "$") -> None:
    if isinstance(value, bool) or value is None or isinstance(value, str):
        return
    if isinstance(value, int):
        require(abs(value) <= 2**53 - 1, f"unsafe JSON integer at {path}")
        return
    if isinstance(value, float):
        raise RuntimeError(f"floating JSON number at {path}")
    if isinstance(value, list):
        for index, item in enumerate(value):
            check_safe_json_numbers(item, f"{path}[{index}]")
        return
    if isinstance(value, dict):
        for key, item in value.items():
            check_safe_json_numbers(item, f"{path}.{key}")
        return
    raise RuntimeError(f"unexpected JSON value at {path}")


def repo_path(path: Path) -> str:
    return path.resolve().relative_to(REPOSITORY_ROOT).as_posix()


def from_repo(path: str) -> Path:
    candidate = Path(path)
    if candidate.is_absolute() or ".." in candidate.parts or re.match(r"^[A-Za-z]:", path):
        raise RuntimeError(f"unsafe repository path: {path}")
    resolved = (REPOSITORY_ROOT / candidate).resolve()
    resolved.relative_to(REPOSITORY_ROOT)
    return resolved


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def verify_hash(reference: dict[str, str], label: str) -> None:
    path = from_repo(reference["path"])
    require(path.is_file(), f"{label} missing: {reference['path']}")
    require(sha256_bytes(path.read_bytes()) == reference["sha256"], f"{label} hash mismatch: {reference['path']}")


bridge = json.loads(BRIDGE_PATH.read_text(encoding="utf-8"))
manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
skeleton = json.loads(SKELETON_PATH.read_text(encoding="utf-8"))
composition = json.loads(COMPOSITION_PATH.read_text(encoding="utf-8"))
dependency = json.loads(DEPENDENCY_PATH.read_text(encoding="utf-8"))
runner = json.loads(RUNNER_PATH.read_text(encoding="utf-8"))
surfaces = (bridge, manifest, skeleton, composition, runner)
require({surface["obligationId"] for surface in surfaces} == {OBLIGATION_ID}, "row identity drift")
require({surface["requiredProperty"] for surface in surfaces} == {REQUIRED_PROPERTY}, "canonical requiredProperty drift")
require({surface["theoremName"] for surface in surfaces} == {THEOREM_NAME}, "theorem name drift")
require({bridge["status"], manifest["status"], skeleton["status"]} == {"OPEN"}, "row status drift")
require({bridge["proofStatus"], manifest["proofStatus"], skeleton["proofStatus"], runner["proofStatus"]} ==
        {"PASS_OPEN_STATIC_V2"}, "v2 proof status drift")
require(not bridge["eligibleForDischarge"] and not manifest["eligibleForDischarge"] and not skeleton["eligibleForDischarge"], "skeleton must be ineligible for discharge")
obligation_index = json.loads(OBLIGATION_INDEX_PATH.read_text(encoding="utf-8"))
obligation = next(item for item in obligation_index["obligations"] if item["obligationId"] == OBLIGATION_ID)
require(obligation["requiredProperty"] == REQUIRED_PROPERTY and obligation["statement"]["name"] == THEOREM_NAME,
        "canonical obligation drift")
require(obligation["status"]["classification"] == "OPEN" and obligation["status"]["discharged"] is False,
        "canonical OPEN status drift")
require("| SEP-04 | `receipt_preimage_matches_storage_return_and_final_event` |" in
        INVENTORY_PATH.read_text(encoding="utf-8"), "inventory drift")
placeholder = next(item["exactIdentityRef"] for item in obligation["tcb"] if item["tcbId"] == "TCB-LOCK")
require(placeholder["sha256"] == PLACEHOLDER_SHA256, "canonical lock placeholder drift")
require(sha256_bytes(LOCK_PATH.read_bytes()) == LOCK_SHA256, "actual dependency lock drift")
require(MATERIALIZED_CLAIM_PATH.is_file(), "fixture-backed claim.k has not been materialized")
require(MUTANT_CONTROL_CLAIM_PATH.is_file(), "mutant executable-control claim missing")
require(not MATERIALIZED_BUNDLE_PATH.exists(), "bundle.json is reserved for fresh proof facts; use bundle.skeleton.json before replay")
materialized = MATERIALIZED_CLAIM_PATH.is_file()
if materialized:
    require(skeleton["proofSpec"]["materializedPath"] == repo_path(MATERIALIZED_CLAIM_PATH), "materialized claim path drift")
    require(skeleton["proofSpec"]["sha256"] == sha256_bytes(MATERIALIZED_CLAIM_PATH.read_bytes()), "materialized claim hash drift")
    require("@@" not in MATERIALIZED_CLAIM_PATH.read_text(encoding="utf-8"), "unclosed materialization port in claim.k")

    # A materialized claim is only meaningful when it is tied to a concrete
    # transaction capture.  Keep these checks deliberately independent from K:
    # they re-read the fixture and require the three externally observable
    # receipt copies to be byte-for-byte identical before a later KEVM replay
    # is even allowed to consume the claim.
    fixture_reference = manifest.get("fixture")
    require(isinstance(fixture_reference, dict), "materialized fixture reference missing")
    require(set(fixture_reference) == {"path", "sha256"}, "fixture reference shape drift")
    fixture_path = from_repo(fixture_reference["path"])
    require(fixture_path.is_file(), f"materialized fixture missing: {fixture_reference['path']}")
    fixture_bytes = fixture_path.read_bytes()
    require(sha256_bytes(fixture_bytes) == fixture_reference["sha256"], "materialized fixture hash drift")
    fixture = json.loads(fixture_bytes)
    check_safe_json_numbers(fixture)
    require(fixture.get("obligationId") == "SEP-04", "fixture row identity drift")
    require(fixture.get("status") == "OPEN", "fixture must remain OPEN pending KEVM replay")
    require(fixture.get("eligibleForDischarge") is False, "fixture cannot make the row dischargeable")

    port_values = fixture.get("ports")
    require(isinstance(port_values, dict), "fixture ports missing")
    require(sorted(port_values) == DECLARED_PORTS, "fixture port list drift")
    for name, value in port_values.items():
        require(isinstance(value, str) and value.strip() and "@@" not in value, f"fixture port is not closed: {name}")
    expected_claim = CLAIM_TEMPLATE_TEXT
    for name in DECLARED_PORTS:
        expected_claim = expected_claim.replace(f"@@{name}@@", port_values[name])
    require(
        MATERIALIZED_CLAIM_PATH.read_text(encoding="utf-8") == expected_claim,
        "materialized claim is not the exact fixture-port substitution of claim-template.k.in",
    )
    canonical_topic_decimal = str(int(CANONICAL_TOPIC, 16))
    mutant_topic_decimal = str(int(MUTANT_TOPIC, 16))
    require(int(canonical_topic_decimal) > 2**53 - 1 and int(mutant_topic_decimal) > 2**53 - 1,
            "event topics do not exercise BigInt boundary")
    require(expected_claim.count(canonical_topic_decimal) == 1,
            "positive claim must contain canonical topic decimal exactly once")
    expected_control = (
        expected_claim
        .replace('requires "../../trust-runtime-verification.k"',
                 'requires "generated/mutant-runtime-verification.k"')
        .replace(POSITIVE_MODULE, CONTROL_MODULE)
        .replace(canonical_topic_decimal, mutant_topic_decimal)
    )
    require(MUTANT_CONTROL_CLAIM_PATH.read_text(encoding="utf-8") == expected_control,
            "mutant control is not the exact topic-only fixture rematerialization")
    require(expected_control.count(mutant_topic_decimal) == 1 and canonical_topic_decimal not in expected_control,
            "mutant control topic decimal drift")

    require(skeleton["proofSpec"].get("claimId") is None, "claim ID must remain null before compilation")
    for side in ("positive", "negative"):
        require(skeleton[side].get("definitionKoreSha256") is None, f"{side} definition hash was fabricated")
        require(skeleton[side].get("compiledJsonSha256") is None, f"{side} compiled hash was fabricated")
        require(skeleton[side].get("graph") is None, f"{side} graph was fabricated")
    require(skeleton["mutantExecutableControl"]["claimId"] is None and
            skeleton["mutantExecutableControl"]["graph"] is None,
            "mutant executable-control proof was fabricated")
    proof_inputs = skeleton.get("proofInputs")
    require(isinstance(proof_inputs, dict), "materialized proof inputs missing")
    for name in (
        "claim", "claimTemplate", "mutantExecutableControlClaim", "positiveVerification",
        "negativeVerification", "negativeRuntimeBridge", "parseOnlyHelper",
    ):
        reference = proof_inputs.get(name)
        require(isinstance(reference, dict), f"proof input missing: {name}")
        verify_hash(reference, f"proof input {name}")

    observations = fixture.get("observations")
    require(isinstance(observations, dict), "fixture observations missing")
    receipt_hash = observations.get("receiptHash")
    require(isinstance(receipt_hash, str) and re.fullmatch(r"0x[0-9a-f]{64}", receipt_hash), "fixture receipt hash is invalid")
    return_payload = observations.get("returnPayloadHex")
    require(return_payload == receipt_hash, "successful return payload is not the receipt hash")
    require(observations.get("actionRecordReceiptHash") == receipt_hash, "action record receipt hash differs")
    require(observations.get("receiptRecordReceiptHash") == receipt_hash, "receipt record receipt hash differs")

    complete_logs = observations.get("completeLogs")
    require(isinstance(complete_logs, list) and complete_logs, "fixture must contain its complete nonempty log list")
    final_log = complete_logs[-1]
    require(isinstance(final_log, dict), "fixture final log is invalid")
    require(final_log.get("emitter") == observations.get("finalLogEmitter"), "final log emitter drift")
    require(final_log.get("data") == receipt_hash, "final log data is not the receipt hash")
    topics = final_log.get("topics")
    require(isinstance(topics, list) and len(topics) == 4, "final receipt log topic arity drift")
    require(topics[0] == bridge["abiEventBinding"]["topic0"], "final receipt log topic0 is not canonical")
    require(topics == observations.get("finalLogTopics"), "final receipt log topics drift")

    storage_observations = fixture.get("storageObservations")
    require(isinstance(storage_observations, dict), "fixture storage observations missing")
    require(storage_observations.get("actionRecordReceiptHash") == receipt_hash, "storage action receipt differs")
    require(storage_observations.get("receiptRecordReceiptHash") == receipt_hash, "storage receipt differs")
    require(isinstance(storage_observations.get("actionRecordReceiptSlot"), str), "action-record slot missing")
    require(isinstance(storage_observations.get("receiptRecordReceiptSlot"), str), "receipt-record slot missing")

runtime_hex = RESOLVED_RUNTIME_PATH.read_text(encoding="utf-8").strip().lower()
require(re.fullmatch(r"0x[0-9a-f]+", runtime_hex) is not None and len(runtime_hex) % 2 == 0, "invalid resolved runtime hex")
runtime_bytes = bytes.fromhex(runtime_hex[2:])
require(sha256_bytes(runtime_bytes) == bridge["runtimeBinding"]["runtimeSha256"], "resolved runtime hash mismatch")
require(len(runtime_bytes) == bridge["runtimeBinding"]["runtimeByteLength"], "resolved runtime length mismatch")
topic_hex_offset = runtime_hex[2:].find(CANONICAL_TOPIC)
require(topic_hex_offset >= 0 and runtime_hex[2:].find(CANONICAL_TOPIC, topic_hex_offset + 1) < 0, "canonical event topic is not unique")
topic_byte_offset = topic_hex_offset // 2
require(topic_byte_offset == bridge["semanticMutation"]["byteOffset"], "mutation offset mismatch")
require(runtime_bytes[topic_byte_offset - 1] == 0x7F and bridge["semanticMutation"]["operandInstruction"] == "PUSH32", "event topic is not a PUSH32 immediate")
require(bridge["abiEventBinding"]["signature"] == "RegulatoryActionApplied(bytes32,uint8,bytes32,bytes32)", "event signature drift")
require(bridge["abiEventBinding"]["topic0"] == "0x" + CANONICAL_TOPIC, "canonical topic bridge drift")
abi_shape = ",".join(f"{item['type']}:{str(item['indexed']).lower()}" for item in bridge["abiEventBinding"]["inputs"])
require(abi_shape == "bytes32:true,uint8:true,bytes32:true,bytes32:false", "event ABI shape drift")

macro_prefix = 'rule #trustTrustTokenRuntime() => #parseByteStack("'
canonical_bridge = CANONICAL_BRIDGE_PATH.read_text(encoding="utf-8")
macro_start = canonical_bridge.find(macro_prefix)
require(macro_start >= 0, "canonical runtime macro missing")
runtime_start = macro_start + len(macro_prefix)
runtime_end = canonical_bridge.find('")', runtime_start)
require(canonical_bridge[runtime_start:runtime_end].lower() == runtime_hex, "canonical K macro/runtime mismatch")

mutant_bridge_path = from_repo(bridge["semanticMutation"]["mutantBridgePath"])
mutant_bridge = mutant_bridge_path.read_text(encoding="utf-8")
mutant_macro_start = mutant_bridge.find(macro_prefix)
require(mutant_macro_start >= 0, "mutant runtime macro missing")
mutant_runtime_start = mutant_macro_start + len(macro_prefix)
mutant_runtime_end = mutant_bridge.find('")', mutant_runtime_start)
mutant_runtime_hex = mutant_bridge[mutant_runtime_start:mutant_runtime_end].lower()
mutant_bytes = bytes.fromhex(mutant_runtime_hex[2:])
require(len(mutant_bytes) == len(runtime_bytes), "mutant runtime length changed")
different = [index for index, pair in enumerate(zip(runtime_bytes, mutant_bytes, strict=True)) if pair[0] != pair[1]]
require(different == [topic_byte_offset], "mutant must differ at exactly the event-topic byte")
require(bridge["semanticMutation"]["exactByteDifferenceCount"] == 1, "bridge mutation difference count drift")
require(runtime_bytes[topic_byte_offset] == 0xAA and mutant_bytes[topic_byte_offset] == 0xAB, "mutant byte is not 0xaa -> 0xab")
require(MUTANT_TOPIC in mutant_runtime_hex and CANONICAL_TOPIC not in mutant_runtime_hex, "mutant topic replacement drift")
require(sha256_bytes(mutant_bytes) == bridge["semanticMutation"]["mutantRuntimeSha256"], "mutant runtime hash mismatch")
require(sha256_bytes(mutant_bridge_path.read_bytes()) == bridge["semanticMutation"]["mutantBridgeSha256"], "mutant bridge hash mismatch")
mutant_verification_path = from_repo(bridge["semanticMutation"]["mutantVerificationPath"])
require(sha256_bytes(mutant_verification_path.read_bytes()) == bridge["semanticMutation"]["mutantVerificationSha256"], "mutant verification hash mismatch")
require(bridge["semanticMutation"]["mutantControlModule"] == CONTROL_MODULE, "mutant control module drift")
require(bridge["semanticMutation"]["mutantControlClaimPath"] == repo_path(MUTANT_CONTROL_CLAIM_PATH),
        "mutant control path drift")
require(bridge["semanticMutation"]["mutantControlClaimSha256"] ==
        sha256_bytes(MUTANT_CONTROL_CLAIM_PATH.read_bytes()), "mutant control hash drift")

runtime_schema_sha256 = sha256_bytes(RUNTIME_SCHEMA_PATH.read_bytes())
require(f'rule #trustBridgeSchemaSha256 => "{runtime_schema_sha256}"' in canonical_bridge,
        "K runtime schema binding drift")
require(f"runtime_bridge_schema_sha256 = ''{runtime_schema_sha256}''" in
        GENERATED_ISABELLE_BRIDGE_PATH.read_text(encoding="utf-8"),
        "Isabelle runtime schema binding drift")
source_blocks = {
    "regulatoryActionEventDeclarationSha256": sha256_bytes(source_block(
        INTERFACE_PATH, "event RegulatoryActionApplied(", "event RegulatoryReversalApplied(")),
    "actionReceiptStorageReturnEventSha256": sha256_bytes(source_block(
        TOKEN_SOURCE_PATH, "function _applyActionPrepared(", "function _applyReversal(")),
    "transactionBridgeRecordSha256": sha256_bytes(source_block(
        TRANSACTION_THEORY_PATH, "record trust_transaction_bridge =", "record trust_transaction_abstraction =")),
    "canonicalReceiptTraceSha256": sha256_bytes(source_block(
        TRANSACTION_THEORY_PATH, "definition canonical_receipt_trace ::", "definition alpha_transaction ::")),
    "finalCanonicalReceiptEventTheoremSha256": sha256_bytes(source_block(
        TRANSACTION_THEORY_PATH,
        "theorem success_has_final_canonical_receipt_event:",
        "theorem committed_history_excludes_failure_receipts:")),
}
require(composition["canonicalSources"]["sourceBlocks"] == source_blocks, "composition source-block hashes drift")
require(bridge["sourceBlocks"] == source_blocks, "bridge source-block hashes drift")

root_payload = dict(composition)
composition_root = root_payload.pop("compositionRootSha256")
root_payload.pop("claimBoundary")
require(sha256_bytes(canonical(root_payload)) == composition_root, "composition root drift")
require(bridge["composition"]["rootSha256"] == composition_root, "bridge composition root drift")
require(skeleton["composition"]["rootSha256"] == composition_root, "skeleton composition root drift")
require(composition["exactTransactionFixture"]["exactThreeWayEquality"] is True,
        "three-way receipt equality is not fixed")
require(composition["claims"]["positive"]["module"] == POSITIVE_MODULE and
        composition["claims"]["positive"]["expectedExitCode"] == 0,
        "positive claim boundary drift")
require(composition["claims"]["unchangedNegativeDetector"]["module"] == POSITIVE_MODULE and
        composition["claims"]["unchangedNegativeDetector"]["expectedExitCode"] == 1,
        "unchanged negative detector drift")
require(composition["claims"]["mutantExecutableControl"]["module"] == CONTROL_MODULE and
        composition["claims"]["mutantExecutableControl"]["expectedExitCode"] == 0,
        "mutant control boundary drift")
require(composition["mutation"]["exactByteDifferenceCount"] == 1 and
        composition["mutation"]["byteOffset"] == topic_byte_offset,
        "composition mutation drift")

expected_integer_ports = {
    name: port_values[name]
    for name in (
        "BLOCK_GAS_LIMIT_INT", "BLOCK_NUMBER_INT", "SENDER_INT",
        "SENDER_NONCE_BEFORE_INT", "TIMESTAMP_INT", "TOKEN_ADDRESS_INT", "TX_GAS_LIMIT_INT",
    )
}
for name, text in expected_integer_ports.items():
    require(re.fullmatch(r"0|[1-9][0-9]*", text) is not None and str(int(text)) == text,
            f"integer port round-trip drift: {name}")
expected_bigint = bridge["bigIntBoundary"]
require(expected_bigint == composition["bigIntBoundary"] == skeleton["bigIntBoundary"],
        "BigInt boundary surface drift")
require(expected_bigint["integerPorts"] == expected_integer_ports, "BigInt integer ports drift")
require(expected_bigint["canonicalTopicDecimal"] == str(int(CANONICAL_TOPIC, 16)) and
        expected_bigint["mutantTopicDecimal"] == str(int(MUTANT_TOPIC, 16)) and
        expected_bigint["topicDecimalsRoundTrip"] is True,
        "BigInt topic boundary drift")
require(expected_bigint["numberMaxSafeInteger"] == str(2**53 - 1) and
        all(int(expected_bigint["integerPorts"][name]) > 2**53 - 1
            for name in expected_bigint["largeIntegerPorts"]),
        "BigInt maximum-safe boundary drift")

require(dependency["selectedObligation"] == {
    "id": OBLIGATION_ID,
    "property": REQUIRED_PROPERTY,
    "theoremName": THEOREM_NAME,
    "status": "OPEN",
}, "dependency selected row drift")
node_ids = [node["id"] for node in dependency["nodes"]]
require(len(node_ids) == len(set(node_ids)) and node_ids.count(OBLIGATION_ID) == 1,
        "dependency node identity drift")
require(all(left in node_ids and right in node_ids for left, right in dependency["edges"]),
        "dependency edge endpoint missing")
require(["SEP-04", "ART-07"] in dependency["edges"], "ART-07 consumer edge missing")
require(not any(right.startswith("SEP-") and right != OBLIGATION_ID
                for left, right in dependency["edges"] if left == OBLIGATION_ID),
        "SEP-04 claim boundary merged with another SEP row")

for support in bridge["supportingCrossChecks"]:
    verify_hash(support, f"supporting cross-check {support['role']}")
verify_hash(manifest["bridge"], "row bridge")
verify_hash(manifest["theorem"], "Isabelle theory")
verify_hash(manifest["proofTemplate"], "claim template")
for generated in manifest["generated"]:
    verify_hash(generated, "generated artifact")
verify_hash(manifest["dependencyGraph"], "dependency graph")
verify_hash(manifest["compositionGraph"], "composition graph")
verify_hash(manifest["skeletonBundle"], "skeleton bundle")
verify_hash(manifest["mutantExecutableControl"], "mutant executable-control claim")
verify_hash(manifest["runnerDescriptor"], "runner descriptor")

require(DECLARED_PORTS == bridge["materialization"]["requiredPorts"], "claim-template port list drift")
require(len(DECLARED_PORTS) >= 12, "claim template does not expose enough transaction ports")
theory = from_repo(manifest["theorem"]["path"]).read_text(encoding="utf-8")
require("theorem receipt_preimage_matches_storage_return_and_final_event:" in theory, "named theorem missing")
require("bridge_return_receipt_hash bridge payload" in theory, "return receipt relation missing")
require("last (transaction_raw_logs execution) = bridge_receipt_log bridge receipt" in theory, "final log relation missing")
require("expected_success_state abstraction = Some (abstraction_post_state abstraction)" in theory, "post-state relation missing")
banned = re.compile(r"^\s*(sorry|oops|axiomatization|oracle)\b|\bby\s+eval\b|\bnative_decide\b|\bskip_proof\b", re.MULTILINE)
require(banned.search(theory) is None, "banned Isabelle source form present")
for token in (
    composition_root,
    source_blocks["actionReceiptStorageReturnEventSha256"],
    source_blocks["canonicalReceiptTraceSha256"],
    bridge["bigIntBoundary"]["canonicalTopicDecimal"],
    bridge["bigIntBoundary"]["mutantTopicDecimal"],
):
    require(token in theory, f"Isabelle v2 binding token missing: {token}")
require(all(value is None for value in manifest["proofFacts"].values()),
        "worker must not record manifest proof facts")
require(all(value is None for value in runner["proofFacts"].values()),
        "worker must not record runner proof facts")
require(bridge["semanticBridge"]["status"] == "NOT_RUN" and
        bridge["semanticBridge"]["certificate"] is None,
        "semantic bridge certificate was fabricated")
require(skeleton["bridge"]["semanticCertificate"] is None, "skeleton semantic certificate was fabricated")
require(skeleton["replay"] == {
    "proofRoot": None, "report": None, "stateRoot": None,
    "status": "NOT_RUN", "traceRoot": None,
}, "skeleton replay facts were fabricated")
require(runner["mutantExecutableControlCommandTemplate"][:2] ==
        ["bash", "formal/kevm/row-bundles/bootstrap-row-proof.sh"],
        "mutant control command drift")
require(runner["authoritativeCommandTemplate"][:2] ==
        ["bash", "formal/kevm/row-bundles/run-row-bundle.sh"],
        "authoritative replay command drift")
for parse_role in ("positive", "control"):
    parse_command = runner["parseOnlyCommandTemplates"][parse_role]
    require(parse_command[1] == "formal/kevm/row-bundles/sep-04/parse-claims.py" and
            parse_command[-2:] == ["--role", parse_role],
            f"{parse_role} parse-only command drift")
require(len(runner["independentReplayPlan"]) == 7, "independent replay plan drift")
require("KEVM_FULL_PROVE" in skeleton["prohibitedUntilHeavySlotsAvailable"] and
        "ISABELLE_BUILD" in skeleton["prohibitedUntilHeavySlotsAvailable"],
        "heavy-slot prohibition drift")
require("K_PARSE_ONLY" not in skeleton["prohibitedUntilHeavySlotsAvailable"],
        "parse-only was incorrectly prohibited")

print(json.dumps({
    "status": "PASS_OPEN_STATIC_V2",
    "mode": "EXECUTABLE_BACKEND_READY_V2",
    "proofStatus": "NOT_RUN",
    "eligibleForDischarge": False,
    "obligationId": OBLIGATION_ID,
    "requiredProperty": REQUIRED_PROPERTY,
    "theoremName": THEOREM_NAME,
    "runtimeSha256": bridge["runtimeBinding"]["runtimeSha256"],
    "eventTopicByteOffset": topic_byte_offset,
    "mutantRuntimeSha256": bridge["semanticMutation"]["mutantRuntimeSha256"],
    "compositionRootSha256": composition_root,
    "positiveModule": POSITIVE_MODULE,
    "mutantControlModule": CONTROL_MODULE,
    "claimSha256": sha256_bytes(MATERIALIZED_CLAIM_PATH.read_bytes()),
    "mutantControlClaimSha256": sha256_bytes(MUTANT_CONTROL_CLAIM_PATH.read_bytes()),
    "bigIntBoundary": expected_bigint,
    "bridge": repo_path(BRIDGE_PATH),
    "bridgeSha256": sha256_bytes(BRIDGE_PATH.read_bytes()),
    "rowManifest": repo_path(MANIFEST_PATH),
    "rowManifestSha256": sha256_bytes(MANIFEST_PATH.read_bytes()),
    "runnerDescriptor": repo_path(RUNNER_PATH),
    "runnerDescriptorSha256": sha256_bytes(RUNNER_PATH.read_bytes()),
    "requiredPorts": DECLARED_PORTS,
    "remainingBlockers": skeleton["blockers"],
}, indent=2))
