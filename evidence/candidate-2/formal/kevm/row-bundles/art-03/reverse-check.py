#!/usr/bin/env python3
"""Independent static reverse check for the OPEN ART-03 row inputs."""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path


ROW_ROOT = Path(__file__).resolve().parent
REPOSITORY_ROOT = ROW_ROOT.parents[3]
BRIDGE_PATH = ROW_ROOT / "bridge" / "row-bridge.json"
MANIFEST_PATH = ROW_ROOT / "bridge" / "row-manifest.json"
DEPENDENCY_PATH = ROW_ROOT / "dependency-graph.json"
SKELETON_PATH = ROW_ROOT / "bundle.skeleton.json"
RUNNER_DESCRIPTOR_PATH = ROW_ROOT / "runner-descriptor.skeleton.json"
CLAIM_PATH = ROW_ROOT / "claim.k"
THEORY_PATH = ROW_ROOT / "isabelle" / "ART_03_Constructor_Resolved_Runtime_Binding.thy"
CANONICAL_BUNDLE_PATH = ROW_ROOT / "bundle.json"
OBLIGATION_INDEX_PATH = REPOSITORY_ROOT / "evidence" / "end-to-end-refinement" / "obligation-evidence-index.json"
THEOREM_OBLIGATIONS_PATH = REPOSITORY_ROOT / "evidence" / "end-to-end-refinement" / "theorem-obligations.md"
PROOF_LEDGER_PATH = REPOSITORY_ROOT / "evidence" / "end-to-end-refinement" / "proof-run-ledger.json"
COMPILER_OUTPUT_PATH = REPOSITORY_ROOT / "evidence" / "end-to-end-refinement" / "runtime-binding" / "native" / "standard-json-output.json"
FIXTURE_PATH = REPOSITORY_ROOT / "evidence" / "end-to-end-refinement" / "runtime-binding" / "resolved" / "fixture.json"
RESOLVED_RUNTIME_PATH = REPOSITORY_ROOT / "evidence" / "end-to-end-refinement" / "runtime-binding" / "resolved" / "native" / "TrustToken.hex"
CANONICAL_BRIDGE_PATH = REPOSITORY_ROOT / "formal" / "kevm" / "generated" / "trust-runtime-bridge.k"

REQUIRED_PROPERTY = "constructor_resolved_local_runtime_is_hash_bound"
EXPECTED_WORD = "0x" + "00" * 31 + "12"
MUTANT_WORD = "0x" + "00" * 31 + "13"
IMMUTABLE_START = 6970
IMMUTABLE_LENGTH = 32
MUTATION_BYTE_OFFSET = 7001


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def repo_path(path: Path) -> str:
    return path.resolve().relative_to(REPOSITORY_ROOT).as_posix()


def from_repo(value: str) -> Path:
    candidate = Path(value)
    require(not candidate.is_absolute() and ".." not in candidate.parts and not re.match(r"^[A-Za-z]:", value), f"unsafe repository path: {value}")
    resolved = (REPOSITORY_ROOT / candidate).resolve()
    resolved.relative_to(REPOSITORY_ROOT)
    return resolved


def verify_ref(reference: dict, label: str) -> Path:
    require(isinstance(reference, dict), f"{label} reference missing")
    path = from_repo(reference["path"])
    require(path.is_file(), f"{label} missing: {reference['path']}")
    require(sha256_bytes(path.read_bytes()) == reference["sha256"], f"{label} hash drift: {reference['path']}")
    return path


def read_runtime(path: Path) -> bytes:
    value = path.read_text(encoding="utf-8").strip().lower()
    require(re.fullmatch(r"0x[0-9a-f]+", value) is not None and len(value) % 2 == 0, f"invalid runtime hex: {path}")
    return bytes.fromhex(value[2:])


bridge = json.loads(BRIDGE_PATH.read_text(encoding="utf-8"))
manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
dependency = json.loads(DEPENDENCY_PATH.read_text(encoding="utf-8"))
skeleton = json.loads(SKELETON_PATH.read_text(encoding="utf-8"))
runner = json.loads(RUNNER_DESCRIPTOR_PATH.read_text(encoding="utf-8"))

for artifact in (bridge, manifest, skeleton, runner):
    require(artifact["obligationId"] == "ART-03", "row identity drift")
    require(artifact["status"] == "OPEN", "row status must remain OPEN")
    require(artifact["eligibleForDischarge"] is False, "static row cannot be dischargeable")
require(bridge["requiredProperty"] == REQUIRED_PROPERTY, "bridge requiredProperty drift")
require(manifest["requiredProperty"] == REQUIRED_PROPERTY, "manifest requiredProperty drift")
require(skeleton["requiredProperty"] == REQUIRED_PROPERTY, "skeleton requiredProperty drift")
completed_bundle = None
if CANONICAL_BUNDLE_PATH.exists():
    completed_bundle = json.loads(CANONICAL_BUNDLE_PATH.read_text(encoding="utf-8"))

index = json.loads(OBLIGATION_INDEX_PATH.read_text(encoding="utf-8"))
obligation = next(entry for entry in index["obligations"] if entry["obligationId"] == "ART-03")
require(obligation["requiredProperty"].replace("`", "") == REQUIRED_PROPERTY, "canonical index property drift")
require(obligation["statement"]["name"] == REQUIRED_PROPERTY, "canonical statement name drift")
require(obligation["status"]["classification"] == "OPEN" and obligation["status"]["discharged"] is False, "canonical row is no longer OPEN")
canonical_lock_placeholder = next(entry for entry in obligation["tcb"] if entry["tcbId"] == "TCB-LOCK")["exactIdentityRef"]
require(canonical_lock_placeholder["sha256"] == "e4fcabd40c8b18e3900050a590b6b80c687d4d115f61bc12439af6099e83434e", "canonical OPEN lock placeholder drift")
require(f"| ART-03 | `{REQUIRED_PROPERTY}` |" in THEOREM_OBLIGATIONS_PATH.read_text(encoding="utf-8"), "theorem inventory row drift")
verify_ref(bridge["canonicalObligation"]["index"], "canonical obligation index")
verify_ref(bridge["canonicalObligation"]["theoremInventory"], "theorem inventory")

expected_edges = [["ART-01", "ART-02"], ["ART-02", "ART-03"], ["ART-04", "ART-03"], ["ART-03", "ART-06"], ["ART-06", "ART-07"]]
require(dependency["selectedObligation"] == {"id": "ART-03", "property": REQUIRED_PROPERTY, "status": "OPEN"}, "selected dependency node drift")
require(dependency["edges"] == expected_edges, "dependency edges drift")
require(bridge["dependencies"]["directPrerequisites"] == ["ART-02", "ART-04"], "direct prerequisites drift")
require(bridge["dependencies"]["transitivePrerequisites"] == ["ART-01"], "transitive prerequisite drift")
require(bridge["dependencies"]["directConsumers"] == ["ART-06"], "direct consumer drift")
require(bridge["dependencies"]["transitiveConsumers"] == ["ART-07"], "transitive consumer drift")
verify_ref(bridge["dependencies"]["graph"], "dependency graph")

ledger = json.loads(PROOF_LEDGER_PATH.read_text(encoding="utf-8"))
for run_id in bridge["provenanceEvidence"]["passRuns"]:
    run = next(entry for entry in ledger["runs"] if entry["runId"] == run_id)
    require(run["status"] == "PASS" and "ART-03" in run["targetObligationIds"], f"provenance run drift: {run_id}")
verify_ref(bridge["provenanceEvidence"]["ledger"], "proof-run ledger")

tcb = bridge["tcb"]
require(tcb["classification"] == "OPEN_PLACEHOLDER_PENDING_COORDINATOR_BINDING", "TCB placeholder classification drift")
require(tcb["canonicalIndexPlaceholder"] == canonical_lock_placeholder, "row did not preserve the canonical OPEN placeholder identity")
actual_lock_path = verify_ref(tcb["actualCurrentLock"], "actual current dependency lock")
actual_lock_sha256 = sha256_bytes(actual_lock_path.read_bytes())
require(actual_lock_sha256 == "3134e7692086170f86b6dd42e7ebd0256c188da8db8cbd17241c3d2c8d315196", "actual current dependency lock drift")
runtime_binding_manifest_path = verify_ref(tcb["runtimeBindingManifest"], "runtime-binding manifest")
runtime_binding_manifest = json.loads(runtime_binding_manifest_path.read_text(encoding="utf-8"))
require(runtime_binding_manifest["sourceIdentity"]["dependencyLockSha256"] == actual_lock_sha256, "runtime-binding manifest lock identity drift")
require(tcb["runtimeBindingManifest"]["dependencyLockSha256"] == actual_lock_sha256, "row runtime-binding lock identity drift")
require(tcb["productDrift"] is False and tcb["staticBlocker"] is False, "OPEN placeholder was misclassified as drift or blocker")

compiler_output = json.loads(COMPILER_OUTPUT_PATH.read_text(encoding="utf-8"))
contract = compiler_output["contracts"]["implementation/src/TrustToken.sol"]["TrustToken"]
require(contract["evm"]["methodIdentifiers"]["decimals()"] == "313ce567", "decimals selector drift")
require(contract["evm"]["deployedBytecode"]["immutableReferences"]["622"] == [{"length": 32, "start": 6970}], "compiler immutable reference drift")
template = bytes.fromhex(contract["evm"]["deployedBytecode"]["object"])
require(len(template) == bridge["compilerTemplate"]["byteLength"], "compiler template length drift")
require(sha256_bytes(template) == bridge["compilerTemplate"]["sha256"], "compiler template hash drift")
verify_ref(bridge["compilerTemplate"]["output"], "compiler output")
verify_ref(bridge["compilerTemplate"]["artifacts"], "compiler artifacts")
verify_ref(bridge["compilerTemplate"]["manifest"], "compiler manifest")

fixture = json.loads(FIXTURE_PATH.read_text(encoding="utf-8"))
deployment = next(entry for entry in fixture["deployments"] if entry["label"] == "TrustToken")
declaration = next(entry for entry in deployment["immutablePatch"]["declarations"] if entry["astId"] == 622)
require(declaration["name"] == "decimals" and declaration["canonicalType"] == "uint8" and declaration["value"] == "18", "fixture declaration drift")
require(declaration["encodedWord"] == EXPECTED_WORD, "fixture decimals word drift")
require(declaration["locations"] == [{"length": 32, "start": 6970}], "fixture decimals location drift")
require(deployment["immutablePatch"]["exactMatch"] is True, "fixture immutable patch is not exact")
require(deployment["immutablePatch"]["ethGetCodeSha256"] == deployment["immutablePatch"]["patchedSha256"] == deployment["runtime"]["sha256"], "fixture patch/getCode hashes differ")
verify_ref(bridge["constructorResolution"]["fixture"], "constructor fixture")

patched = bytearray(template)
for item in deployment["immutablePatch"]["declarations"]:
    word = bytes.fromhex(item["encodedWord"][2:])
    for location in item["locations"]:
        require(len(word) == location["length"], f"immutable word length drift: {item['name']}")
        patched[location["start"]: location["start"] + location["length"]] = word
resolved = read_runtime(RESOLVED_RUNTIME_PATH)
require(bytes(patched) == resolved, "compiler template plus fixture patch does not reconstruct resolved runtime")
require(resolved[IMMUTABLE_START:IMMUTABLE_START + IMMUTABLE_LENGTH].hex() == EXPECTED_WORD[2:], "resolved decimals word drift")
require(len(resolved) == bridge["constructorResolution"]["runtime"]["byteLength"], "resolved runtime length drift")
require(sha256_bytes(resolved) == bridge["constructorResolution"]["runtime"]["sha256"], "resolved runtime hash drift")

macro_prefix = 'rule #trustTrustTokenRuntime() => #parseByteStack("'
canonical_bridge = CANONICAL_BRIDGE_PATH.read_text(encoding="utf-8")
macro_start = canonical_bridge.find(macro_prefix)
require(macro_start >= 0, "canonical runtime macro missing")
runtime_start = macro_start + len(macro_prefix)
runtime_end = canonical_bridge.find('")', runtime_start)
require(bytes.fromhex(canonical_bridge[runtime_start:runtime_end][2:]) == resolved, "canonical K macro/runtime mismatch")
verify_ref(bridge["kRuntimeBinding"]["canonicalBridge"], "canonical runtime bridge")

mutation = bridge["semanticMutation"]
require(mutation["declarationAstId"] == 622, "mutation AST id drift")
require(mutation["immutableRange"] == {"length": IMMUTABLE_LENGTH, "start": IMMUTABLE_START}, "mutation range drift")
require(mutation["byteOffset"] == MUTATION_BYTE_OFFSET, "mutation byte offset drift")
require(mutation["canonicalWord"] == EXPECTED_WORD and mutation["mutantWord"] == MUTANT_WORD, "mutation word drift")
mutant_bridge_path = verify_ref(mutation["mutantBridge"], "mutant runtime bridge")
verify_ref(mutation["mutantVerification"], "mutant verification")
mutant_bridge = mutant_bridge_path.read_text(encoding="utf-8")
mutant_start = mutant_bridge.find(macro_prefix) + len(macro_prefix)
mutant_end = mutant_bridge.find('")', mutant_start)
mutant = bytes.fromhex(mutant_bridge[mutant_start:mutant_end][2:])
require(len(mutant) == len(resolved), "mutant runtime length changed")
different = [index for index, pair in enumerate(zip(resolved, mutant, strict=True)) if pair[0] != pair[1]]
require(different == [MUTATION_BYTE_OFFSET], "mutant must differ at exactly byte 7001")
require(resolved[MUTATION_BYTE_OFFSET] == 0x12 and mutant[MUTATION_BYTE_OFFSET] == 0x13, "mutation byte is not 0x12 -> 0x13")
require(mutant[IMMUTABLE_START:IMMUTABLE_START + IMMUTABLE_LENGTH].hex() == MUTANT_WORD[2:], "mutant word is not uint8(19)")
require(sha256_bytes(mutant) == mutation["mutantRuntimeSha256"], "mutant runtime hash drift")

claim = CLAIM_PATH.read_text(encoding="utf-8")
for token in (
    "TRUST-ART-03-CONSTRUCTOR-RESOLVED-RUNTIME-BINDING-SPEC",
    '#trustTrustTokenRuntime()',
    '#parseByteStack("0x313ce567")',
    f'#parseByteStack("{EXPECTED_WORD}")',
    "EVMC_SUCCESS",
    "<storage> TOKEN_STORAGE:Map </storage>",
    "<origStorage> TOKEN_STORAGE </origStorage>",
    "<log> .List </log>",
):
    require(token in claim, f"claim boundary token missing: {token}")
require("@@" not in claim, "claim contains unresolved materialization ports")

theory = THEORY_PATH.read_text(encoding="utf-8")
for token in (
    f"theorem {REQUIRED_PROPERTY}:",
    bridge["constructorResolution"]["deterministicRootSha256"],
    bridge["constructorResolution"]["runtime"]["sha256"],
    mutation["mutantRuntimeSha256"],
    "art03_decimals_immutable_range = (6970, 32)",
):
    require(token in theory, f"Isabelle bridge token missing: {token}")
banned = re.compile(r"^\s*(sorry|oops|axiomatization|oracle)\b|\bby\s+eval\b|\bnative_decide\b|\bskip_proof\b", re.MULTILINE)
require(banned.search(theory) is None, "banned Isabelle source form present")

if completed_bundle is not None:
    require(completed_bundle["schemaVersion"] == 1, "completed bundle schema drift")
    require(completed_bundle["obligationId"] == "ART-03", "completed bundle row identity drift")
    require(completed_bundle["requiredProperty"] == REQUIRED_PROPERTY, "completed bundle property drift")
    require(completed_bundle["proofSpec"] == {
        "path": repo_path(CLAIM_PATH),
        "module": "TRUST-ART-03-CONSTRUCTOR-RESOLVED-RUNTIME-BINDING-SPEC",
        "claimId": "d129ca69ab655f58e27dcdddad68ab23d6e4b2a3281c03305e3ff7fe1508cf97",
        "sha256": sha256_bytes(CLAIM_PATH.read_bytes()),
    }, "completed bundle proof-spec drift")
    require(completed_bundle["bridge"] == {
        "path": repo_path(BRIDGE_PATH),
        "sha256": sha256_bytes(BRIDGE_PATH.read_bytes()),
        "reverseCheck": repo_path(Path(__file__)),
    }, "completed bundle bridge drift")
    require(completed_bundle["isabelle"]["theoryPath"] == repo_path(THEORY_PATH), "completed bundle theory path drift")
    require(completed_bundle["isabelle"]["sourceSha256"] == sha256_bytes(THEORY_PATH.read_bytes()), "completed bundle theory hash drift")
    require(completed_bundle["isabelle"]["theoremName"] == REQUIRED_PROPERTY, "completed bundle theorem drift")
    require(completed_bundle["isabelle"]["session"] == "ERC_TRUST_ART_03", "completed bundle Isabelle session drift")
    require(completed_bundle["isabelle"]["rowManifestPath"] == repo_path(MANIFEST_PATH), "completed bundle manifest path drift")
    require(completed_bundle["isabelle"]["rowManifestSha256"] == sha256_bytes(MANIFEST_PATH.read_bytes()), "completed bundle manifest hash drift")
    require(completed_bundle["positive"]["expectedExitCode"] == 0, "completed bundle positive exit drift")
    require(completed_bundle["positive"]["expectedGraph"] == {
        "nodes": 4, "edges": 2, "covers": 1, "terminal": 0,
        "stuck": 0, "vacuous": 0, "pending": 0, "admitted": False,
    }, "completed bundle positive graph drift")
    require(completed_bundle["negative"]["expectedExitCode"] == 1, "completed bundle negative exit drift")
    require(completed_bundle["negative"]["expectedGraph"] == {
        "nodes": 401, "edges": 32, "covers": 0, "terminal": 1,
        "stuck": 0, "vacuous": 0, "pending": 262, "admitted": False,
    }, "completed bundle negative graph drift")
    require(completed_bundle["negative"]["mutationId"] == "ART-03-MUT-DECIMALS-IMMUTABLE-001", "completed bundle mutation drift")
    require(completed_bundle["negative"]["mutationKind"] == "EXECUTABLE_SEMANTIC_MUTANT", "completed bundle mutation kind drift")
    require(completed_bundle["negative"]["claimRequirementTokens"] == [f'#parseByteStack("{EXPECTED_WORD}")'], "completed bundle unchanged requirement drift")
    expected_positive_word = 'b\\"' + "\\\\x00" * 31 + "\\\\x12" + '\\"'
    expected_negative_word = 'b\\"' + "\\\\x00" * 31 + "\\\\x13" + '\\"'
    require(expected_positive_word in completed_bundle["positive"]["witnessTokens"], "completed bundle positive word witness missing")
    require(expected_negative_word in completed_bundle["negative"]["witnessTokens"], "completed bundle negative word witness missing")

require(skeleton["proofSpec"]["claimId"] is None, "claim ID was fabricated")
for side in ("positive", "negative"):
    require(skeleton[side]["definitionKoreSha256"] is None, f"{side} definition hash was fabricated")
    require(skeleton[side]["compiledJsonSha256"] is None, f"{side} compiled hash was fabricated")
    require(skeleton[side]["graph"] is None, f"{side} graph was fabricated")
require(skeleton["isabelle"]["buildStatus"] == "NOT_RUN_IN_WORKER" and skeleton["isabelle"]["closureReport"] is None, "Isabelle result was fabricated")
require(skeleton["replay"] == {"proofRoot": None, "report": None, "status": "NOT_RUN", "traceRoot": None}, "replay result was fabricated")
require(skeleton["tcbBinding"] == {
    "actualCurrentLock": tcb["actualCurrentLock"],
    "blocker": False,
    "canonicalPlaceholderSha256": canonical_lock_placeholder["sha256"],
    "classification": "OPEN_PLACEHOLDER_PENDING_COORDINATOR_BINDING",
    "productDrift": False,
    "runtimeBindingManifestDependencyLockSha256": actual_lock_sha256,
}, "skeleton TCB binding classification drift")
require(not any("reconcil" in blocker.lower() or "tcb" in blocker.lower() or "lock" in blocker.lower() for blocker in skeleton["blockers"]), "OPEN TCB placeholder leaked into proof blockers")
for reference in skeleton["proofInputs"].values():
    verify_ref(reference, "proof input")

expected_tools = ["run-row-bundle.sh", "validate-bundle.py", "analyze-row-proof.mjs", "curate-row-output.py", "verify-curated-evidence.py"]
require([Path(item["path"]).name for item in runner["repositoryOwnedTools"]] == expected_tools, "repository-owned runner tool set drift")
for item in runner["repositoryOwnedTools"]:
    verify_ref(item, "repository-owned runner tool")
require(runner["proofFacts"] == {"claimId": None, "isabelleBuild": None, "negativeDefinitionHashes": None, "negativeGraph": None, "positiveDefinitionHashes": None, "positiveGraph": None, "replay": None}, "runner descriptor fabricated proof facts")
require(runner["tcbBinding"] == {"actualCurrentLock": tcb["actualCurrentLock"], "blocker": False, "classification": "OPEN_PLACEHOLDER_PENDING_COORDINATOR_BINDING"}, "runner TCB classification drift")
require(runner["definitionCompileCommandTemplates"]["positive"][0:3] == ["kevm", "kompile-spec", "formal/kevm/trust-runtime-verification.k"], "positive definition command drift")
require(runner["definitionCompileCommandTemplates"]["negative"][0:3] == ["kevm", "kompile-spec", "formal/kevm/row-bundles/art-03/generated/mutant-runtime-verification.k"], "negative definition command drift")
require(runner["isabelleClosureCommandTemplate"][0:3] == ["powershell", "-File", "formal/kevm/row-bundles/art-03/isabelle/run-closure.ps1"], "Isabelle closure command drift")
require(runner["completedBundleValidationCommandTemplate"] == ["python3", "formal/kevm/row-bundles/validate-bundle.py", "<completed-art-03-bundle.json>"], "completed bundle validation command drift")
require(runner["authoritativeCommandTemplate"][0:2] == ["bash", "formal/kevm/row-bundles/run-row-bundle.sh"], "authoritative runner command drift")
require(runner["authoritativeCommandTemplate"][-1] == "--no-use-booster", "authoritative runner must disable Booster")

verify_ref(manifest["bridge"], "row bridge")
verify_ref(manifest["dependencyGraph"], "manifest dependency graph")
verify_ref(manifest["proofSpec"], "manifest proof spec")
for item in manifest["generated"]:
    verify_ref(item, "generated artifact")
verify_ref(manifest["theorem"], "manifest theorem")
verify_ref(manifest["skeletonBundle"], "manifest skeleton bundle")
verify_ref(manifest["runnerDescriptor"], "manifest runner descriptor")
require(manifest["proofFacts"] == {"claimId": None, "isabelleClosure": None, "negativeGraph": None, "positiveGraph": None, "replay": None}, "manifest fabricated proof facts")
require(manifest["tcbBinding"] == {
    "actualCurrentLock": tcb["actualCurrentLock"],
    "blocker": False,
    "canonicalPlaceholderSha256": canonical_lock_placeholder["sha256"],
    "classification": "OPEN_PLACEHOLDER_PENDING_COORDINATOR_BINDING",
    "productDrift": False,
}, "manifest TCB classification drift")

print(json.dumps({
    "status": "STATIC_ROW_INPUTS_PASS_OPEN",
    "proofStatus": "NOT_RUN",
    "eligibleForDischarge": False,
    "obligationId": "ART-03",
    "requiredProperty": REQUIRED_PROPERTY,
    "tcbBindingClassification": "OPEN_PLACEHOLDER_PENDING_COORDINATOR_BINDING",
    "actualCurrentLockSha256": actual_lock_sha256,
    "directPrerequisites": bridge["dependencies"]["directPrerequisites"],
    "resolvedRuntimeSha256": sha256_bytes(resolved),
    "immutableRange": {"start": IMMUTABLE_START, "length": IMMUTABLE_LENGTH},
    "mutationByteOffset": MUTATION_BYTE_OFFSET,
    "mutantRuntimeSha256": sha256_bytes(mutant),
    "bridge": repo_path(BRIDGE_PATH),
    "bridgeSha256": sha256_bytes(BRIDGE_PATH.read_bytes()),
    "rowManifest": repo_path(MANIFEST_PATH),
    "rowManifestSha256": sha256_bytes(MANIFEST_PATH.read_bytes()),
    "remainingBlockers": skeleton["blockers"],
}, indent=2))
