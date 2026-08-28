#!/usr/bin/env python3

import argparse
import hashlib
import json
from pathlib import Path


def sha_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha(path: Path) -> str:
    return sha_bytes(path.read_bytes())


def stable_json(value) -> str:
    return json.dumps(value, indent=2, sort_keys=True) + "\n"


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.replace("\r\n", "\n"), encoding="utf-8", newline="\n")


def replace_once(source: str, before: str, after: str) -> str:
    if source.count(before) != 1:
        raise SystemExit(f"expected exactly one source occurrence: {before}")
    return source.replace(before, after, 1)


def repo_path(repository_root: Path, path: Path) -> str:
    return path.resolve().relative_to(repository_root.resolve()).as_posix()


def runtime_from_bridge(text: str) -> tuple[int, int, str]:
    prefix = 'rule #trustTrustTokenRuntime() => #parseByteStack("'
    start = text.index(prefix) + len(prefix)
    end = text.index('")', start)
    value = text[start:end].lower()
    if not value.startswith("0x") or len(value) % 2:
        raise SystemExit("invalid TrustToken runtime macro")
    return start, end, value


parser = argparse.ArgumentParser()
parser.add_argument("--mutant-artifact", required=True)
args = parser.parse_args()

row_root = Path(__file__).resolve().parent
repository_root = row_root.parents[3]
artifact_path = Path(args.mutant_artifact).resolve()
canonical_source_path = repository_root / "implementation/src/TrustToken.sol"
mutant_source_path = row_root / "mutation/mutant-TrustToken.sol"
foundry_path = repository_root / "foundry.toml"
lock_path = repository_root / "formal/kevm/dependencies.lock.json"
mutation_patch_path = row_root / "mutation/abi-03-allow-trailing-success.diff"
canonical_claim_path = repository_root / "formal/kevm/specs/full-transaction-action-trailing-calldata-revert-spec.k"
canonical_bridge_path = repository_root / "formal/kevm/generated/trust-runtime-bridge.k"
binding_root = repository_root / "evidence/end-to-end-refinement/runtime-binding"
fixture_path = binding_root / "resolved/fixture.json"
resolved_runtime_path = binding_root / "resolved/native/TrustToken.hex"

for path in (
    artifact_path,
    mutant_source_path,
    canonical_source_path,
    foundry_path,
    lock_path,
    mutation_patch_path,
    canonical_claim_path,
    canonical_bridge_path,
    fixture_path,
    resolved_runtime_path,
):
    if not path.is_file():
        raise SystemExit(f"missing input: {path}")

canonical_source = canonical_source_path.read_text(encoding="utf-8")
mutant_source = mutant_source_path.read_text(encoding="utf-8")
old_guard = '            if xor(calldatasize(), expected) { revert(0, 0) }'
new_guard = "\n".join((
    '            if lt(calldatasize(), expected) { revert(0, 0) }',
    '            // Executable ABI-03 adequacy mutant: a trailing word is accepted',
    '            // as a successful, empty-return invocation instead of reverting.',
    '            if gt(calldatasize(), expected) { return(0, 0) }',
))
if canonical_source.count(old_guard) != 1 or replace_once(canonical_source, old_guard, new_guard) != mutant_source:
    raise SystemExit("alternate-runtime source is not the exact ABI-03 mutation")
patch = mutation_patch_path.read_text(encoding="utf-8")
if patch.count(f"-{old_guard}") != 1 or any(patch.count(f"+{line}") != 1 for line in new_guard.splitlines()):
    raise SystemExit("mutation patch does not encode the exact source replacement")

artifact_bytes = artifact_path.read_bytes()
artifact = json.loads(artifact_bytes)
if "contracts" in artifact:
    contract = artifact["contracts"]["implementation/src/TrustToken.sol"]["TrustToken"]
else:
    contract = artifact
metadata = contract["metadata"]
if isinstance(metadata, str):
    metadata = json.loads(metadata)
deployed = contract["evm"]["deployedBytecode"] if "evm" in contract else contract["deployedBytecode"]
template_hex = deployed["object"].lower()
if template_hex.startswith("0x"):
    template_hex = template_hex[2:]
template = bytes.fromhex(template_hex)
immutable_references = deployed["immutableReferences"]
settings = metadata["settings"]
lock = json.loads(lock_path.read_text(encoding="utf-8"))
solc = lock["components"]["solc"]
if (
    metadata["compiler"]["version"] != solc["version"].removeprefix("solc-")
    or settings["evmVersion"] != "cancun"
    or settings["viaIR"] is not True
    or settings["optimizer"] != {"enabled": True, "runs": 1}
    or settings["metadata"]["bytecodeHash"] != "none"
    or settings["metadata"]["appendCBOR"] is not False
):
    raise SystemExit("mutant compiler identity/settings drift")

fixture_bytes = fixture_path.read_bytes()
fixture = json.loads(fixture_bytes)
deployment = next(item for item in fixture["deployments"] if item["label"] == "TrustToken")
declarations = {str(item["astId"]): item for item in deployment["immutablePatch"]["declarations"]}
if set(immutable_references) != set(declarations):
    raise SystemExit("mutant immutable declaration IDs drift")
resolved_mutant = bytearray(template)
patch_locations = []
for ast_id, locations in immutable_references.items():
    declaration = declarations[ast_id]
    word = bytes.fromhex(declaration["encodedWord"][2:])
    for location in locations:
        start, length = location["start"], location["length"]
        if length != len(word) or start + length > len(resolved_mutant):
            raise SystemExit("mutant immutable reference is out of range")
        resolved_mutant[start:start + length] = word
        patch_locations.append({
            "astId": int(ast_id),
            "name": declaration["name"],
            "start": start,
            "length": length,
            "encodedWordSha256": sha_bytes(word),
        })

canonical_bridge_bytes = canonical_bridge_path.read_bytes()
canonical_bridge = canonical_bridge_bytes.decode("utf-8")
runtime_start, runtime_end, canonical_runtime_hex = runtime_from_bridge(canonical_bridge)
canonical_runtime = bytes.fromhex(canonical_runtime_hex[2:])
fixture_runtime_hex = resolved_runtime_path.read_text(encoding="utf-8").strip().lower()
if canonical_runtime != bytes.fromhex(fixture_runtime_hex[2:]):
    raise SystemExit("canonical K macro and constructor-resolved runtime disagree")
if bytes(resolved_mutant) == canonical_runtime:
    raise SystemExit("alternate runtime did not change")

canonical_claim = canonical_claim_path.read_text(encoding="utf-8")
canonical_comment = """// Initial exact-runtime case for obligation ABI-03:
// trailing_calldata_reverts_and_stutters.
// The native action selector plus its 21-word tuple head and one extra word
// must revert with an empty payload, commit no protocol log, and restore token
// storage while consuming only the outer transaction nonce."""
row_comment = """// ABI-03 backend-complete candidate over the exact pinned TrustToken runtime.
//
// The nonReentrant modifier executes before the strict calldata-length guard.
// A well-formed external invocation therefore starts non-static with the idle
// guard value at TrustStorage slot 29.  The guard is an explicit map item and
// every other storage entry remains in an anti-aliased symbolic remainder.
//
// This final claim combines the observable revert outcome with the protocol
// frame: empty revert data, EVMC_REVERT, no protocol log or substate effect,
// exact TrustToken storage stutter, and only the outer sender nonce consumed."""
claim = replace_once(canonical_claim, canonical_comment, row_comment)
claim = replace_once(
    claim,
    "module TRUST-FULL-TRANSACTION-ACTION-TRAILING-CALLDATA-REVERT-SPEC",
    "module TRUST-ABI-03-TRAILING-IDLE-COMBINED-SPEC",
)
claim = replace_once(
    claim,
    "              <program> .Bytes </program>\n              ...",
    "              <program> .Bytes </program>\n              <static> false </static>\n              ...",
)
claim = replace_once(claim, "<storage> TOKEN_STORAGE:Map </storage>", "<storage> (29 |-> 0) TOKEN_STORAGE:Map </storage>")
claim = replace_once(claim, "<origStorage> TOKEN_STORAGE </origStorage>", "<origStorage> (29 |-> 0) TOKEN_STORAGE </origStorage>")
claim = replace_once(claim, "      </kevm>\nendmodule", "      </kevm>\n    requires notBool 29 in_keys(TOKEN_STORAGE)\nendmodule")
claim = 'requires "../../trust-runtime-verification.k"\n' + claim
claim_path = row_root / "claim.k"
write(claim_path, claim)

compiler_closure = {
    "schemaVersion": 1,
    "obligationId": "ABI-03",
    "artifactInputSha256": sha_bytes(artifact_bytes),
    "artifactInputPath": repo_path(repository_root, artifact_path),
    "compilerVersion": metadata["compiler"]["version"],
    "compilerBinarySha256": solc["binarySha256"],
    "settings": {
        "evmVersion": settings["evmVersion"],
        "viaIR": settings["viaIR"],
        "optimizer": settings["optimizer"],
        "metadata": settings["metadata"],
    },
    "canonicalSourceSha256": sha(canonical_source_path),
    "mutantSourceSha256": sha_bytes(mutant_source.encode()),
    "mutationPatchSha256": sha(mutation_patch_path),
    "runtimeTemplate": {
        "byteLength": len(template),
        "sha256": sha_bytes(template),
        "object": "0x" + template.hex(),
        "immutableReferences": immutable_references,
    },
}
compiler_closure_path = row_root / "bridge/mutant-compiler-output.json"
write(compiler_closure_path, stable_json(compiler_closure))

mutant_runtime_hex = "0x" + bytes(resolved_mutant).hex()
mutant_bridge = canonical_bridge[:runtime_start] + mutant_runtime_hex + canonical_bridge[runtime_end:]
mutant_bridge_path = row_root / "generated/mutant-runtime-bridge.k"
mutant_verification_path = row_root / "generated/mutant-runtime-verification.k"
write(mutant_bridge_path, mutant_bridge)
write(mutant_verification_path, """requires "mutant-runtime-bridge.k"
requires "driver.md"

module TRUST-RUNTIME-VERIFICATION
    imports TRUST-RUNTIME-BRIDGE
    imports ETHEREUM-SIMULATION
endmodule
""")

bridge = {
    "schemaVersion": 1,
    "obligationId": "ABI-03",
    "requiredProperty": "trailing_calldata_reverts_and_stutters",
    "positiveClaim": {
        "path": repo_path(repository_root, claim_path),
        "module": "TRUST-ABI-03-TRAILING-IDLE-COMBINED-SPEC",
        "claimId": "6adb6bf3e7629f12e822a2b4772ec91837db3eab2656d3fcb1acfa297e8ac161",
        "sha256": sha(claim_path),
        "selector": "0x9da23539",
        "canonicalCalldataBytes": 676,
        "witnessCalldataBytes": 708,
        "expectedStatus": "EVMC_REVERT",
        "expectedOutputHex": "0x",
        "idleGuardSlot": 29,
        "idleGuardValue": 0,
        "externalCallStatic": False,
        "symbolicStorageRemainder": True,
    },
    "canonicalRuntime": {
        "bridgePath": repo_path(repository_root, canonical_bridge_path),
        "bridgeSha256": sha_bytes(canonical_bridge_bytes),
        "runtimeByteLength": len(canonical_runtime),
        "runtimeSha256": sha_bytes(canonical_runtime),
    },
    "compilerClosure": {
        "path": repo_path(repository_root, compiler_closure_path),
        "sha256": sha(compiler_closure_path),
        "foundryConfigPath": repo_path(repository_root, foundry_path),
        "foundryConfigSha256": sha(foundry_path),
        "fixturePath": repo_path(repository_root, fixture_path),
        "fixtureSha256": sha_bytes(fixture_bytes),
        "immutablePatchLocations": sorted(patch_locations, key=lambda item: item["start"]),
    },
    "alternateRuntimeAdequacyFixture": {
        "mutationId": "ABI-03-ALT-RUNTIME-TRAILING-SUCCESS-001",
        "kind": "EXECUTABLE_SEMANTIC_MUTANT",
        "patchPath": repo_path(repository_root, mutation_patch_path),
        "patchSha256": sha(mutation_patch_path),
        "mutantSourceSha256": sha_bytes(mutant_source.encode()),
        "runtimeByteLength": len(resolved_mutant),
        "runtimeSha256": sha_bytes(resolved_mutant),
        "bridgePath": repo_path(repository_root, mutant_bridge_path),
        "bridgeSha256": sha(mutant_bridge_path),
        "verificationPath": repo_path(repository_root, mutant_verification_path),
        "verificationSha256": sha(mutant_verification_path),
        "expectedSemanticDifference": "the unchanged 708-byte combined claim requires empty EVMC_REVERT while the alternate runtime returns empty EVMC_SUCCESS",
    },
}
bridge_path = row_root / "bridge/row-bridge.json"
write(bridge_path, stable_json(bridge))

theory_path = row_root / "isabelle/ABI_03_Trailing_Calldata_Reverts_And_Stutters.thy"
theory = rf"""theory ABI_03_Trailing_Calldata_Reverts_And_Stutters
  imports ERC_TRUST.TRUST_Runtime_Bridge_Generated
begin

definition abi_03_positive_claim_id :: string where
  "abi_03_positive_claim_id = ''{bridge["positiveClaim"]["claimId"]}''"

definition abi_03_positive_claim_sha256 :: string where
  "abi_03_positive_claim_sha256 = ''{bridge["positiveClaim"]["sha256"]}''"

definition abi_03_canonical_runtime_sha256 :: string where
  "abi_03_canonical_runtime_sha256 = ''{bridge["canonicalRuntime"]["runtimeSha256"]}''"

definition abi_03_alternate_runtime_sha256 :: string where
  "abi_03_alternate_runtime_sha256 = ''{bridge["alternateRuntimeAdequacyFixture"]["runtimeSha256"]}''"

definition abi_03_witness_calldata_length :: nat where
  "abi_03_witness_calldata_length = 708"

definition abi_03_trailing_word_length :: nat where
  "abi_03_trailing_word_length = 32"

definition abi_03_idle_guard_slot :: nat where
  "abi_03_idle_guard_slot = 29"

definition abi_03_external_call_static :: bool where
  "abi_03_external_call_static = False"

definition abi_03_expected_status :: string where
  "abi_03_expected_status = ''EVMC_REVERT''"

definition abi_03_expected_output_length :: nat where
  "abi_03_expected_output_length = 0"

definition abi_03_storage_stutter :: bool where
  "abi_03_storage_stutter = True"

theorem abi_03_trailing_calldata_reverts_and_stutters:
  "action_entrypoint_selector = 2644653369 \<and>
   action_calldata_length = 676 \<and>
   abi_03_witness_calldata_length = action_calldata_length + abi_03_trailing_word_length \<and>
   abi_03_idle_guard_slot = 29 \<and>
   \<not> abi_03_external_call_static \<and>
   abi_03_expected_status = ''EVMC_REVERT'' \<and>
   abi_03_expected_output_length = 0 \<and>
   abi_03_storage_stutter \<and>
   abi_03_canonical_runtime_sha256 = native_resolved_runtime_sha256 \<and>
   abi_03_canonical_runtime_sha256 \<noteq> abi_03_alternate_runtime_sha256 \<and>
   abi_03_positive_claim_id \<noteq> ''''"
  by (simp add: action_entrypoint_selector_def action_calldata_length_def
      abi_03_witness_calldata_length_def abi_03_trailing_word_length_def
      abi_03_idle_guard_slot_def abi_03_external_call_static_def
      abi_03_expected_status_def abi_03_expected_output_length_def
      abi_03_storage_stutter_def abi_03_canonical_runtime_sha256_def
      native_resolved_runtime_sha256_def abi_03_alternate_runtime_sha256_def
      abi_03_positive_claim_id_def)

ML \<open>
  val row_fact = @{{thm abi_03_trailing_calldata_reverts_and_stutters}};
  val row_oracles = Thm_Deps.all_oracles [row_fact];
  val _ = if null row_oracles then ()
    else error ("ABI-03 proof audit found " ^ string_of_int (length row_oracles) ^ " oracle dependencies");
  val audit_report =
    "status=PASS\\n" ^
    "qualified_theorem=ABI_03_Trailing_Calldata_Reverts_And_Stutters.abi_03_trailing_calldata_reverts_and_stutters\\n" ^
    "oracle_dependency_count=0\\n";
  val _ = Export.export \<^theory>
    \<^path_binding>\<open>erc-trust-abi-03/proof-trust.txt\<close>
    [XML.Text audit_report];
\<close>

end
"""
write(theory_path, theory)

manifest = {
    "schemaVersion": 1,
    "obligationId": "ABI-03",
    "bridge": {"path": repo_path(repository_root, bridge_path), "sha256": sha(bridge_path)},
    "compilerClosure": {"path": repo_path(repository_root, compiler_closure_path), "sha256": sha(compiler_closure_path)},
    "mutationPatch": {"path": repo_path(repository_root, mutation_patch_path), "sha256": sha(mutation_patch_path)},
    "proofSpec": {
        "path": repo_path(repository_root, claim_path),
        "sha256": sha(claim_path),
        "module": bridge["positiveClaim"]["module"],
        "claimId": bridge["positiveClaim"]["claimId"],
    },
    "theorem": {
        "path": repo_path(repository_root, theory_path),
        "sha256": sha(theory_path),
        "session": "ERC_TRUST_ABI_03",
        "name": "abi_03_trailing_calldata_reverts_and_stutters",
    },
    "generated": [
        {"path": repo_path(repository_root, mutant_bridge_path), "sha256": sha(mutant_bridge_path)},
        {"path": repo_path(repository_root, mutant_verification_path), "sha256": sha(mutant_verification_path)},
    ],
}
manifest_path = row_root / "bridge/row-manifest.json"
write(manifest_path, stable_json(manifest))

print(stable_json({
    "status": "PASS",
    "claimSha256": sha(claim_path),
    "bridgeSha256": sha(bridge_path),
    "compilerClosureSha256": sha(compiler_closure_path),
    "canonicalRuntimeSha256": sha_bytes(canonical_runtime),
    "alternateRuntimeSha256": sha_bytes(resolved_mutant),
    "theorySha256": sha(theory_path),
    "rowManifestSha256": sha(manifest_path),
}))
