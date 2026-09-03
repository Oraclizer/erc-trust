#!/usr/bin/env python3
import hashlib
import json
import sys
from pathlib import Path

row_root = Path(__file__).resolve().parent
repository_root = row_root.parents[3]
bridge_path = row_root / "bridge" / "row-bridge.json"
manifest_path = row_root / "bridge" / "row-manifest.json"
bridge = json.loads(bridge_path.read_text(encoding="utf-8"))
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))


def sha_bytes(value):
    return hashlib.sha256(value).hexdigest()


def absolute(repo_path):
    return repository_root.joinpath(*repo_path.split("/"))


def read_hex(path):
    value = path.read_text(encoding="utf-8").strip().lower()
    if not value.startswith("0x") or len(value) % 2:
        raise SystemExit(f"invalid hex file: {path}")
    return bytes.fromhex(value[2:])


for section, path_key, hash_key in (
    ("compilerOutput", "path", "fileSha256"),
    ("compilerArtifacts", "path", "fileSha256"),
):
    path = absolute(bridge[section][path_key])
    if sha_bytes(path.read_bytes()) != bridge[section][hash_key]:
        raise SystemExit(f"source hash drift: {path}")

binding_manifest_path = absolute(bridge["compilerBinding"]["manifestPath"])
if sha_bytes(binding_manifest_path.read_bytes()) != bridge["compilerBinding"]["manifestSha256"]:
    raise SystemExit("compiler binding manifest hash drift")
binding_manifest = json.loads(binding_manifest_path.read_text(encoding="utf-8"))
if binding_manifest["deterministicRootSha256"] != bridge["compilerBinding"]["deterministicRootSha256"]:
    raise SystemExit("compiler binding root drift")

fixture_path = absolute(bridge["constructorResolution"]["fixturePath"])
if sha_bytes(fixture_path.read_bytes()) != bridge["constructorResolution"]["fixtureSha256"]:
    raise SystemExit("fixture hash drift")

compiler_output = json.loads(absolute(bridge["compilerOutput"]["path"]).read_text(encoding="utf-8"))
source, contract = bridge["compilerOutput"]["subject"].rsplit(":", 1)
deployed = compiler_output["contracts"][source][contract]["evm"]["deployedBytecode"]
template = bytes.fromhex(deployed["object"])
if len(template) != bridge["compilerOutput"]["templateByteLength"]:
    raise SystemExit("template length drift")
if sha_bytes(template) != bridge["compilerOutput"]["templateSha256"]:
    raise SystemExit("template hash drift")
if deployed["immutableReferences"] != bridge["compilerOutput"]["immutableReferences"]:
    raise SystemExit("immutable reference drift")

fixture = json.loads(fixture_path.read_text(encoding="utf-8"))
if fixture["deterministicRootSha256"] != bridge["constructorResolution"]["deterministicRootSha256"]:
    raise SystemExit("constructor fixture root drift")
deployment = next(value for value in fixture["deployments"] if value["label"] == "TrustToken")
patched = bytearray(template)
for declaration in deployment["immutablePatch"]["declarations"]:
    word = bytes.fromhex(declaration["encodedWord"][2:])
    for location in declaration["locations"]:
        patched[location["start"]:location["start"] + location["length"]] = word
resolved_path = absolute(bridge["constructorResolution"]["resolvedRuntimePath"])
resolved = read_hex(resolved_path)
if bytes(patched) != resolved:
    raise SystemExit("immutable patch reconstruction mismatch")
if sha_bytes(resolved) != bridge["constructorResolution"]["resolvedRuntimeSha256"]:
    raise SystemExit("resolved runtime hash drift")

canonical_bridge_path = absolute(bridge["kRuntimeBinding"]["canonicalBridgePath"])
canonical_bridge = canonical_bridge_path.read_text(encoding="utf-8")
if sha_bytes(canonical_bridge_path.read_bytes()) != bridge["kRuntimeBinding"]["canonicalBridgeSha256"]:
    raise SystemExit("canonical K bridge hash drift")
prefix = 'rule #trustTrustTokenRuntime() => #parseByteStack("'
start = canonical_bridge.index(prefix) + len(prefix)
end = canonical_bridge.index('")', start)
macro_runtime = bytes.fromhex(canonical_bridge[start:end][2:])
if macro_runtime != resolved:
    raise SystemExit("K macro runtime mismatch")

mutation = bridge["semanticMutation"]
mutant = bytearray(resolved)
offset = mutation["byteOffset"]
if mutant[offset] != int(mutation["canonicalOpcode"], 16):
    raise SystemExit("canonical mutation opcode drift")
mutant[offset] = int(mutation["mutantOpcode"], 16)
if sha_bytes(mutant) != mutation["mutantRuntimeSha256"]:
    raise SystemExit("mutant runtime hash drift")
mutant_bridge_path = absolute(mutation["mutantBridgePath"])
if sha_bytes(mutant_bridge_path.read_bytes()) != mutation["mutantBridgeSha256"]:
    raise SystemExit("mutant bridge hash drift")
mutant_bridge = mutant_bridge_path.read_text(encoding="utf-8")
start = mutant_bridge.index(prefix) + len(prefix)
end = mutant_bridge.index('")', start)
if bytes.fromhex(mutant_bridge[start:end][2:]) != bytes(mutant):
    raise SystemExit("mutant K macro runtime mismatch")

theory_path = row_root / "isabelle" / "ART_02_Compiler_Output_Runtime_Binding.thy"
theory = theory_path.read_text(encoding="utf-8")
for token in (
    "theorem compiler_output_runtime_bytes_are_hash_bound:",
    bridge["constructorResolution"]["resolvedRuntimeSha256"],
    bridge["semanticMutation"]["mutantRuntimeSha256"],
    str(bridge["semanticMutation"]["byteOffset"]),
):
    if token not in theory:
        raise SystemExit(f"theory bridge token missing: {token}")
lower = theory.lower()
for banned in ("sorry", "oops", "admit", "axiomatization", "skip_proof"):
    if banned in lower:
        raise SystemExit(f"banned theory token: {banned}")

if sha_bytes(bridge_path.read_bytes()) != manifest["bridge"]["sha256"]:
    raise SystemExit("row manifest bridge hash drift")
if sha_bytes(theory_path.read_bytes()) != manifest["theorem"]["sha256"]:
    raise SystemExit("row manifest theorem source hash drift")
if manifest["theorem"]["name"] != "compiler_output_runtime_bytes_are_hash_bound":
    raise SystemExit("row manifest theorem name drift")
claim_path = absolute(manifest["proofSpec"]["path"])
if sha_bytes(claim_path.read_bytes()) != manifest["proofSpec"]["sha256"]:
    raise SystemExit("row manifest claim hash drift")
for generated in manifest["generated"]:
    path = absolute(generated["path"])
    if sha_bytes(path.read_bytes()) != generated["sha256"]:
        raise SystemExit(f"row manifest generated hash drift: {path}")

print(json.dumps({
    "status": "PASS",
    "obligationId": bridge["obligationId"],
    "templateSha256": bridge["compilerOutput"]["templateSha256"],
    "resolvedRuntimeSha256": bridge["constructorResolution"]["resolvedRuntimeSha256"],
    "mutantRuntimeSha256": mutation["mutantRuntimeSha256"],
    "mutationByteOffset": offset,
    "semanticMutation": mutation["expectedSemanticDifference"],
}, indent=2))
