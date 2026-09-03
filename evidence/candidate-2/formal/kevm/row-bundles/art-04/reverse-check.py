#!/usr/bin/env python3
"""Independent static reverse check for the OPEN ART-04 row inputs."""

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
RUNNER_PATH = ROW_ROOT / "runner-descriptor.skeleton.json"
CLAIM_PATH = ROW_ROOT / "claim.k"
THEORY_PATH = ROW_ROOT / "isabelle" / "ART_04_Artifact_Surface_Binding.thy"
CANONICAL_BUNDLE_PATH = ROW_ROOT / "bundle.json"
OBLIGATION_INDEX_PATH = REPOSITORY_ROOT / "evidence" / "end-to-end-refinement" / "obligation-evidence-index.json"
COMPILER_OUTPUT_PATH = REPOSITORY_ROOT / "evidence" / "end-to-end-refinement" / "runtime-binding" / "native" / "standard-json-output.json"
COMPILER_ARTIFACTS_PATH = REPOSITORY_ROOT / "evidence" / "end-to-end-refinement" / "runtime-binding" / "native" / "bridge-artifacts.json"
RUNTIME_PATH = REPOSITORY_ROOT / "evidence" / "end-to-end-refinement" / "runtime-binding" / "resolved" / "native" / "TrustToken.hex"
CANONICAL_BRIDGE_PATH = REPOSITORY_ROOT / "formal" / "kevm" / "generated" / "trust-runtime-bridge.k"
REQUIRED_PROPERTY = "storage_layout_abi_ast_and_immutable_references_are_hash_bound"
PLACEHOLDER_SHA = "e4fcabd40c8b18e3900050a590b6b80c687d4d115f61bc12439af6099e83434e"
CURRENT_LOCK_SHA = "3134e7692086170f86b6dd42e7ebd0256c188da8db8cbd17241c3d2c8d315196"
CANONICAL_WORD = "0x" + "00" * 31 + "2a"
MUTANT_WORD = "0x" + "00" * 31 + "63"

def sha(value: bytes) -> str: return hashlib.sha256(value).hexdigest()
def require(condition: bool, message: str) -> None:
    if not condition: raise RuntimeError(message)
def canonical_hash(value) -> str:
    return sha(json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode())
def repo_path(path: Path) -> str: return path.resolve().relative_to(REPOSITORY_ROOT).as_posix()
def from_repo(value: str) -> Path:
    candidate = Path(value)
    require(not candidate.is_absolute() and ".." not in candidate.parts and not re.match(r"^[A-Za-z]:", value), f"unsafe path: {value}")
    resolved = (REPOSITORY_ROOT / candidate).resolve(); resolved.relative_to(REPOSITORY_ROOT); return resolved
def verify_ref(reference: dict, label: str) -> Path:
    path = from_repo(reference["path"])
    require(path.is_file() and sha(path.read_bytes()) == reference["sha256"], f"{label} hash drift")
    return path
def runtime_bytes(path: Path) -> bytes:
    value = path.read_text(encoding="utf-8").strip().lower()
    require(re.fullmatch(r"0x[0-9a-f]+", value) is not None and len(value) % 2 == 0, "invalid runtime hex")
    return bytes.fromhex(value[2:])

bridge = json.loads(BRIDGE_PATH.read_text(encoding="utf-8"))
manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
skeleton = json.loads(SKELETON_PATH.read_text(encoding="utf-8"))
runner = json.loads(RUNNER_PATH.read_text(encoding="utf-8"))
dependency = json.loads(DEPENDENCY_PATH.read_text(encoding="utf-8"))
for item in (bridge, manifest, skeleton, runner):
    require(item["obligationId"] == "ART-04" and item["status"] == "OPEN", "row identity/status drift")
    require(item["eligibleForDischarge"] is False, "static row became dischargeable")
require(bridge["requiredProperty"] == manifest["requiredProperty"] == skeleton["requiredProperty"] == REQUIRED_PROPERTY, "requiredProperty drift")
require(skeleton["proofStatus"] == manifest["proofStatus"] == runner["proofStatus"] == "PASS_OPEN_STATIC", "static result classification drift")
completed_bundle = None
if CANONICAL_BUNDLE_PATH.exists():
    completed_bundle = json.loads(CANONICAL_BUNDLE_PATH.read_text(encoding="utf-8"))

index = json.loads(OBLIGATION_INDEX_PATH.read_text(encoding="utf-8"))
obligation = next(item for item in index["obligations"] if item["obligationId"] == "ART-04")
require(obligation["requiredProperty"].replace("`", "") == REQUIRED_PROPERTY and obligation["statement"]["name"] == REQUIRED_PROPERTY, "canonical property drift")
placeholder = next(item for item in obligation["tcb"] if item["tcbId"] == "TCB-LOCK")["exactIdentityRef"]
require(placeholder["sha256"] == PLACEHOLDER_SHA, "canonical OPEN placeholder drift")
tcb = bridge["tcb"]
require(tcb["classification"] == "OPEN_PLACEHOLDER_PENDING_COORDINATOR_BINDING", "TCB classification drift")
require(tcb["canonicalIndexPlaceholder"] == placeholder and tcb["productDrift"] is False and tcb["staticBlocker"] is False, "placeholder misclassified")
actual_lock = verify_ref(tcb["actualCurrentLock"], "actual lock")
require(sha(actual_lock.read_bytes()) == CURRENT_LOCK_SHA, "current lock drift")
binding_manifest_path = verify_ref(tcb["runtimeBindingManifest"], "runtime binding manifest")
binding_manifest = json.loads(binding_manifest_path.read_text(encoding="utf-8"))
require(binding_manifest["sourceIdentity"]["dependencyLockSha256"] == CURRENT_LOCK_SHA == tcb["runtimeBindingManifest"]["dependencyLockSha256"], "runtime binding lock identity drift")

require(bridge["dependencies"]["directPrerequisites"] == ["ART-01", "ART-02"], "direct prerequisite drift")
require(bridge["dependencies"]["directConsumers"] == ["ART-03", "ART-06"], "direct consumer drift")
expected_edges = [["ART-01", "ART-04"], ["ART-02", "ART-04"], ["ART-04", "ART-03"], ["ART-04", "ART-06"], ["ART-03", "ART-07"], ["ART-06", "ART-07"]]
require(dependency["edges"] == expected_edges, "dependency graph drift")
verify_ref(bridge["dependencies"]["graph"], "dependency graph")

output = json.loads(COMPILER_OUTPUT_PATH.read_text(encoding="utf-8"))
artifacts = json.loads(COMPILER_ARTIFACTS_PATH.read_text(encoding="utf-8"))
contract = output["contracts"]["implementation/src/TrustToken.sol"]["TrustToken"]
artifact = next(item for item in artifacts if item["contract"] == "TrustToken")
require(artifact["abi"] == contract["abi"] and artifact["storageLayout"] == contract["storageLayout"], "bridge artifact surface differs from compiler output")
require(artifact["runtimeTemplate"]["immutableReferences"] == contract["evm"]["deployedBytecode"]["immutableReferences"], "immutable reference surface differs")
storage_ast = output["sources"]["implementation/src/TrustStorage.sol"]["ast"]
section_hashes = bridge["compilerArtifactSurface"]["sectionHashes"]
expected_hashes = {
    "abiCanonicalJsonSha256": canonical_hash(contract["abi"]),
    "storageLayoutCanonicalJsonSha256": canonical_hash(contract["storageLayout"]),
    "trustStorageAstCanonicalJsonSha256": canonical_hash(storage_ast),
    "immutableReferencesCanonicalJsonSha256": canonical_hash(contract["evm"]["deployedBytecode"]["immutableReferences"]),
    "methodIdentifiersCanonicalJsonSha256": canonical_hash(contract["evm"]["methodIdentifiers"]),
}
require(section_hashes == expected_hashes, "canonical artifact section hash drift")
require(contract["evm"]["methodIdentifiers"]["totalSupply()"] == "18160ddd", "totalSupply selector drift")
abi = next(item for item in contract["abi"] if item.get("type") == "function" and item.get("name") == "totalSupply")
require(abi["inputs"] == [] and abi["outputs"][0]["type"] == "uint256" and abi["stateMutability"] == "view", "totalSupply ABI drift")
layout = next(item for item in contract["storageLayout"]["storage"] if item["astId"] == 624)
require(layout == {"astId": 624, "contract": "implementation/src/TrustToken.sol:TrustToken", "label": "_totalSupply", "offset": 0, "slot": "2", "type": "t_uint256"}, "totalSupply layout drift")
storage_contract = next(item for item in storage_ast["nodes"] if item.get("nodeType") == "ContractDefinition" and item.get("name") == "TrustStorage")
declaration = next(item for item in storage_contract["nodes"] if item.get("id") == 624)
require(declaration["name"] == "_totalSupply" and declaration["typeDescriptions"]["typeString"] == "uint256" and declaration["stateVariable"] is True, "totalSupply AST drift")
require(contract["evm"]["deployedBytecode"]["immutableReferences"] == {"622": [{"length": 32, "start": 6970}], "626": [{"length": 32, "start": 517}, {"length": 32, "start": 1580}, {"length": 32, "start": 8522}, {"length": 32, "start": 19822}]}, "immutable references drift")
verify_ref(bridge["compilerArtifactSurface"]["standardJsonOutput"], "standard JSON output")
verify_ref(bridge["compilerArtifactSurface"]["bridgeArtifacts"], "bridge artifacts")

resolved = runtime_bytes(RUNTIME_PATH)
require(sha(resolved) == bridge["resolvedRuntime"]["byteSha256"], "resolved runtime hash drift")
canonical_bridge = CANONICAL_BRIDGE_PATH.read_text(encoding="utf-8")
prefix = 'rule #trustTrustTokenRuntime() => #parseByteStack("'
start = canonical_bridge.index(prefix) + len(prefix); end = canonical_bridge.index('")', start)
require(bytes.fromhex(canonical_bridge[start:end][2:]) == resolved, "canonical K macro/runtime mismatch")
verify_ref(bridge["resolvedRuntime"]["canonicalKBridge"], "canonical K bridge")

mutation = bridge["semanticMutation"]
require(mutation["getterByteOffset"] == 8339 and mutation["byteOffset"] == 8340, "getter mutation offset drift")
require(mutation["canonicalSlot"] == 2 and mutation["mutantSlot"] == 3, "slot mutation drift")
mutant_bridge_path = verify_ref(mutation["mutantBridge"], "mutant bridge")
verify_ref(mutation["mutantVerification"], "mutant verification")
mutant_bridge = mutant_bridge_path.read_text(encoding="utf-8")
mstart = mutant_bridge.index(prefix) + len(prefix); mend = mutant_bridge.index('")', mstart)
mutant = bytes.fromhex(mutant_bridge[mstart:mend][2:])
different = [index for index, pair in enumerate(zip(resolved, mutant, strict=True)) if pair[0] != pair[1]]
require(different == [8340] and resolved[8340] == 2 and mutant[8340] == 3, "mutant is not exact slot 2 -> slot 3 byte")
require(sha(mutant) == mutation["mutantRuntimeSha256"], "mutant runtime hash drift")

claim = CLAIM_PATH.read_text(encoding="utf-8")
for token in ("TRUST-ART-04-ARTIFACT-SURFACE-BINDING-SPEC", '#parseByteStack("0x18160ddd")', f'#parseByteStack("{CANONICAL_WORD}")', "<storage> 2 |-> 42 3 |-> 99 </storage>", "<origStorage> 2 |-> 42 3 |-> 99 </origStorage>", "EVMC_SUCCESS"):
    require(token in claim, f"claim token missing: {token}")

theory = THEORY_PATH.read_text(encoding="utf-8")
for token in (f"theorem {REQUIRED_PROPERTY}:", *expected_hashes.values(), "art04_total_supply_slot = 2", "art04_mutation_byte_offset = 8340"):
    require(token in theory, f"theory token missing: {token}")
require(re.search(r"^\s*(sorry|oops|axiomatization|oracle)\b|\bby\s+eval\b|\bnative_decide\b|\bskip_proof\b", theory, re.MULTILINE) is None, "banned Isabelle form")

if completed_bundle is not None:
    require(completed_bundle["schemaVersion"] == 1, "completed bundle schema drift")
    require(completed_bundle["obligationId"] == "ART-04", "completed bundle row identity drift")
    require(completed_bundle["requiredProperty"] == REQUIRED_PROPERTY, "completed bundle property drift")
    require(completed_bundle["proofSpec"] == {
        "path": repo_path(CLAIM_PATH),
        "module": "TRUST-ART-04-ARTIFACT-SURFACE-BINDING-SPEC",
        "claimId": "a25f7c63d606435315d9aa99f67a45e93f0283150707f853e9d7bcc14be82d74",
        "sha256": sha(CLAIM_PATH.read_bytes()),
    }, "completed bundle proof-spec drift")
    require(completed_bundle["bridge"] == {
        "path": repo_path(BRIDGE_PATH),
        "sha256": sha(BRIDGE_PATH.read_bytes()),
        "reverseCheck": repo_path(Path(__file__)),
    }, "completed bundle bridge drift")
    require(completed_bundle["isabelle"]["theoryPath"] == repo_path(THEORY_PATH), "completed bundle theory path drift")
    require(completed_bundle["isabelle"]["sourceSha256"] == sha(THEORY_PATH.read_bytes()), "completed bundle theory hash drift")
    require(completed_bundle["isabelle"]["theoremName"] == REQUIRED_PROPERTY, "completed bundle theorem drift")
    require(completed_bundle["isabelle"]["session"] == "ERC_TRUST_ART_04", "completed bundle Isabelle session drift")
    require(completed_bundle["isabelle"]["rowManifestPath"] == repo_path(MANIFEST_PATH), "completed bundle manifest path drift")
    require(completed_bundle["isabelle"]["rowManifestSha256"] == sha(MANIFEST_PATH.read_bytes()), "completed bundle manifest hash drift")
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
    require(completed_bundle["negative"]["mutationId"] == "ART-04-MUT-TOTAL-SUPPLY-SLOT-001", "completed bundle mutation drift")
    require(completed_bundle["negative"]["mutationKind"] == "EXECUTABLE_SEMANTIC_MUTANT", "completed bundle mutation kind drift")
    require(completed_bundle["negative"]["claimRequirementTokens"] == [f'#parseByteStack("{CANONICAL_WORD}")'], "completed bundle unchanged requirement drift")
    expected_positive_word = 'b\\"' + "\\\\x00" * 31 + "*" + '\\"'
    expected_negative_word = 'b\\"' + "\\\\x00" * 31 + "c" + '\\"'
    require(expected_positive_word in completed_bundle["positive"]["witnessTokens"], "completed bundle positive word witness missing")
    require(expected_negative_word in completed_bundle["negative"]["witnessTokens"], "completed bundle negative word witness missing")

require(skeleton["proofSpec"]["claimId"] is None, "fabricated claim ID")
for side in ("positive", "negative"):
    require(skeleton[side]["definitionKoreSha256"] is None and skeleton[side]["compiledJsonSha256"] is None and skeleton[side]["graph"] is None, f"fabricated {side} proof facts")
require(skeleton["isabelle"]["buildStatus"] == "NOT_RUN_IN_WORKER" and skeleton["isabelle"]["closureReport"] is None, "fabricated Isabelle facts")
require(skeleton["replay"]["status"] == "NOT_RUN" and skeleton["replay"]["report"] is None, "fabricated replay facts")
require(skeleton["prohibitedUntilHeavyProofsComplete"] == ["KEVM", "K_DRY_RUN", "ISABELLE_BUILD", "SOLC_COMPILE"], "heavy-command prohibition drift")
require(skeleton["tcbBinding"]["classification"] == "OPEN_PLACEHOLDER_PENDING_COORDINATOR_BINDING" and skeleton["tcbBinding"]["blocker"] is False, "skeleton TCB drift")
require(len(skeleton["blockers"]) == 4 and not any("lock" in value.lower() or "tcb" in value.lower() for value in skeleton["blockers"]), "TCB placeholder leaked into blockers")

for reference in manifest["generated"]: verify_ref(reference, "generated artifact")
for key in ("bridge", "dependencyGraph", "proofSpec", "theorem", "skeletonBundle", "runnerDescriptor"): verify_ref(manifest[key], f"manifest {key}")
require(all(value is None for value in manifest["proofFacts"].values()), "manifest fabricated proof facts")
require(all(value is None for value in runner["proofFacts"].values()), "runner fabricated proof facts")
for reference in runner["repositoryOwnedTools"]: verify_ref(reference, "repository-owned runner")
verify_ref(runner["inputs"]["isabelleClosureScript"], "Isabelle closure script")
require(runner["isabelleClosureCommandTemplate"][0:3] == ["powershell", "-File", "formal/kevm/row-bundles/art-04/isabelle/run-closure.ps1"], "Isabelle closure command drift")
require(runner["authoritativeCommandTemplate"][-1] == "--no-use-booster", "runner must disable Booster")

print(json.dumps({
    "status": "PASS_OPEN_STATIC", "proofStatus": "NOT_RUN", "eligibleForDischarge": False,
    "obligationId": "ART-04", "requiredProperty": REQUIRED_PROPERTY,
    "tcbBindingClassification": "OPEN_PLACEHOLDER_PENDING_COORDINATOR_BINDING", "actualCurrentLockSha256": CURRENT_LOCK_SHA,
    "sectionHashes": expected_hashes, "directPrerequisites": bridge["dependencies"]["directPrerequisites"],
    "resolvedRuntimeSha256": sha(resolved), "mutationByteOffset": 8340, "mutantRuntimeSha256": sha(mutant),
    "bridgeSha256": sha(BRIDGE_PATH.read_bytes()), "rowManifestSha256": sha(MANIFEST_PATH.read_bytes()),
    "remainingBlockers": skeleton["blockers"],
}, indent=2))
