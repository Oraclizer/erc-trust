#!/usr/bin/env python3

import hashlib
import json
import re
from pathlib import Path

row_root = Path(__file__).resolve().parent
repository_root = row_root.parents[3]
bridge_path = row_root / "bridge/row-bridge.json"
manifest_path = row_root / "bridge/row-manifest.json"
compiler_closure_path = row_root / "bridge/mutant-compiler-output.json"
claim_path = row_root / "claim.k"
theory_path = row_root / "isabelle/ABI_03_Trailing_Calldata_Reverts_And_Stutters.thy"
lock_path = repository_root / "formal/kevm/dependencies.lock.json"


def sha_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha(path: Path) -> str:
    return sha_bytes(path.read_bytes())


def absolute(repo_path: str) -> Path:
    return repository_root.joinpath(*repo_path.split("/"))


def runtime_from_bridge(path: Path) -> bytes:
    text = path.read_text(encoding="utf-8")
    prefix = 'rule #trustTrustTokenRuntime() => #parseByteStack("'
    if text.count(prefix) != 1:
        raise SystemExit(f"TrustToken runtime macro cardinality mismatch: {path}")
    start = text.index(prefix) + len(prefix)
    end = text.index('")', start)
    value = text[start:end].lower()
    if not value.startswith("0x") or len(value) % 2:
        raise SystemExit(f"invalid runtime macro: {path}")
    return bytes.fromhex(value[2:])


bridge = json.loads(bridge_path.read_text(encoding="utf-8"))
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
compiler = json.loads(compiler_closure_path.read_text(encoding="utf-8"))
lock = json.loads(lock_path.read_text(encoding="utf-8"))
if bridge["schemaVersion"] != 1 or bridge["obligationId"] != "ABI-03":
    raise SystemExit("ABI-03 row bridge identity mismatch")

canonical_source_path = repository_root / "implementation/src/TrustToken.sol"
mutation_path = absolute(bridge["alternateRuntimeAdequacyFixture"]["patchPath"])
canonical_source = canonical_source_path.read_text(encoding="utf-8")
old_guard = '            if xor(calldatasize(), expected) { revert(0, 0) }'
new_guard = "\n".join((
    '            if lt(calldatasize(), expected) { revert(0, 0) }',
    '            // Executable ABI-03 adequacy mutant: a trailing word is accepted',
    '            // as a successful, empty-return invocation instead of reverting.',
    '            if gt(calldatasize(), expected) { return(0, 0) }',
))
if canonical_source.count(old_guard) != 1:
    raise SystemExit("canonical ABI-03 guard drift")
mutant_source = canonical_source.replace(old_guard, new_guard, 1)
patch = mutation_path.read_text(encoding="utf-8")
if patch.count(f"-{old_guard}") != 1 or any(patch.count(f"+{line}") != 1 for line in new_guard.splitlines()):
    raise SystemExit("alternate-runtime patch content drift")
if sha(canonical_source_path) != compiler["canonicalSourceSha256"]:
    raise SystemExit("canonical source hash drift")
if sha_bytes(mutant_source.encode()) != compiler["mutantSourceSha256"]:
    raise SystemExit("reconstructed alternate source hash drift")
if sha(mutation_path) != compiler["mutationPatchSha256"]:
    raise SystemExit("mutation patch hash drift")
artifact_path = absolute(compiler["artifactInputPath"])
if sha(artifact_path) != compiler["artifactInputSha256"]:
    raise SystemExit("pinned alternate compiler output hash drift")

if (
    compiler["compilerVersion"] != lock["components"]["solc"]["version"]
    or compiler["compilerBinarySha256"] != lock["components"]["solc"]["binarySha256"]
    or compiler["settings"]["evmVersion"] != "cancun"
    or compiler["settings"]["viaIR"] is not True
    or compiler["settings"]["optimizer"] != {"enabled": True, "runs": 1}
    or compiler["settings"]["metadata"]["bytecodeHash"] != "none"
    or compiler["settings"]["metadata"]["appendCBOR"] is not False
):
    raise SystemExit("alternate compiler closure drift")
runtime_template = bytes.fromhex(compiler["runtimeTemplate"]["object"][2:])
if len(runtime_template) != compiler["runtimeTemplate"]["byteLength"] or sha_bytes(runtime_template) != compiler["runtimeTemplate"]["sha256"]:
    raise SystemExit("alternate runtime template hash/length drift")

fixture_path = absolute(bridge["compilerClosure"]["fixturePath"])
if sha(fixture_path) != bridge["compilerClosure"]["fixtureSha256"]:
    raise SystemExit("constructor fixture hash drift")
fixture = json.loads(fixture_path.read_text(encoding="utf-8"))
deployment = next(item for item in fixture["deployments"] if item["label"] == "TrustToken")
declarations = {str(item["astId"]): item for item in deployment["immutablePatch"]["declarations"]}
references = compiler["runtimeTemplate"]["immutableReferences"]
if set(references) != set(declarations):
    raise SystemExit("alternate immutable declaration IDs drift")
resolved = bytearray(runtime_template)
observed_locations = []
for ast_id, locations in references.items():
    declaration = declarations[ast_id]
    word = bytes.fromhex(declaration["encodedWord"][2:])
    for location in locations:
        start, length = location["start"], location["length"]
        if length != len(word) or start + length > len(resolved):
            raise SystemExit("alternate immutable patch range invalid")
        resolved[start:start + length] = word
        observed_locations.append({
            "astId": int(ast_id),
            "name": declaration["name"],
            "start": start,
            "length": length,
            "encodedWordSha256": sha_bytes(word),
        })
if sorted(observed_locations, key=lambda item: item["start"]) != bridge["compilerClosure"]["immutablePatchLocations"]:
    raise SystemExit("recorded alternate immutable patch locations drift")

canonical_runtime = runtime_from_bridge(absolute(bridge["canonicalRuntime"]["bridgePath"]))
alternate_runtime = runtime_from_bridge(absolute(bridge["alternateRuntimeAdequacyFixture"]["bridgePath"]))
if canonical_runtime == alternate_runtime:
    raise SystemExit("alternate runtime does not distinguish ABI-03")
if (
    len(canonical_runtime) != bridge["canonicalRuntime"]["runtimeByteLength"]
    or sha_bytes(canonical_runtime) != bridge["canonicalRuntime"]["runtimeSha256"]
    or len(alternate_runtime) != bridge["alternateRuntimeAdequacyFixture"]["runtimeByteLength"]
    or sha_bytes(alternate_runtime) != bridge["alternateRuntimeAdequacyFixture"]["runtimeSha256"]
    or alternate_runtime != bytes(resolved)
):
    raise SystemExit("canonical/alternate runtime bridge reconstruction mismatch")

verification_path = absolute(bridge["alternateRuntimeAdequacyFixture"]["verificationPath"])
verification = verification_path.read_text(encoding="utf-8")
for token in ('requires "mutant-runtime-bridge.k"', "module TRUST-RUNTIME-VERIFICATION", "imports TRUST-RUNTIME-BRIDGE", "imports ETHEREUM-SIMULATION"):
    if verification.count(token) != 1:
        raise SystemExit(f"alternate verification source token mismatch: {token}")

claim = claim_path.read_text(encoding="utf-8")
calldata = re.findall(r'#parseByteStack\("(0x[0-9a-f]+)"\)', claim)
required_claim_tokens = (
    'requires "../../trust-runtime-verification.k"',
    "module TRUST-ABI-03-TRAILING-IDLE-COMBINED-SPEC",
    "<static> false </static>",
    "<storage> (29 |-> 0) TOKEN_STORAGE:Map </storage>",
    "<origStorage> (29 |-> 0) TOKEN_STORAGE </origStorage>",
    "requires notBool 29 in_keys(TOKEN_STORAGE)",
    "<output> .Bytes </output>",
    "<statusCode> .StatusCode => EVMC_REVERT </statusCode>",
)
if any(claim.count(token) != 1 for token in required_claim_tokens):
    raise SystemExit("unchanged combined claim token/cardinality drift")
if len(calldata) != 1 or not calldata[0].startswith("0x9da23539") or (len(calldata[0]) - 2) // 2 != 708:
    raise SystemExit("ABI-03 708-byte witness drift")
if sha(claim_path) != bridge["positiveClaim"]["sha256"]:
    raise SystemExit("ABI-03 claim hash drift")

theory = theory_path.read_text(encoding="utf-8")
for token in (
    "theorem abi_03_trailing_calldata_reverts_and_stutters:",
    bridge["positiveClaim"]["claimId"],
    bridge["canonicalRuntime"]["runtimeSha256"],
    bridge["alternateRuntimeAdequacyFixture"]["runtimeSha256"],
    "action_calldata_length = 676",
    "abi_03_witness_calldata_length = action_calldata_length + abi_03_trailing_word_length",
):
    if token not in theory:
        raise SystemExit(f"Isabelle bridge token missing: {token}")
for banned in ("sorry", "oops", "admit", "axiomatization", "by eval", "native_decide", "skip_proof"):
    if re.search(r"\b" + re.escape(banned) + r"\b", theory, flags=re.IGNORECASE):
        raise SystemExit(f"banned Isabelle token: {banned}")

if manifest["obligationId"] != "ABI-03" or manifest["proofSpec"]["claimId"] != bridge["positiveClaim"]["claimId"]:
    raise SystemExit("row manifest identity drift")
for entry in (
    manifest["bridge"],
    manifest["compilerClosure"],
    manifest["mutationPatch"],
    manifest["proofSpec"],
    manifest["theorem"],
    *manifest["generated"],
):
    path = absolute(entry["path"])
    if sha(path) != entry["sha256"]:
        raise SystemExit(f"row manifest hash drift: {path}")

print(json.dumps({
    "status": "PASS",
    "obligationId": "ABI-03",
    "claimSha256": sha(claim_path),
    "canonicalRuntimeSha256": sha_bytes(canonical_runtime),
    "alternateRuntimeSha256": sha_bytes(alternate_runtime),
    "alternateRuntimeByteLength": len(alternate_runtime),
    "bridgeSha256": sha(bridge_path),
    "theorySha256": sha(theory_path),
    "rowManifestSha256": sha(manifest_path),
}, indent=2))
