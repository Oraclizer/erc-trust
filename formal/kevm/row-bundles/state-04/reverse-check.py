#!/usr/bin/env python3
"""Independent reverse check for the STATE-04 row bridge."""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path


HERE = Path(__file__).resolve().parent
REPOSITORY_ROOT = HERE.parents[3]


def data(path: Path) -> bytes:
    return path.read_bytes()


def text(path: Path) -> str:
    return data(path).decode("utf-8")


def sha256(path: Path) -> str:
    return hashlib.sha256(data(path)).hexdigest()


def repo_path(value: str) -> Path:
    return REPOSITORY_ROOT.joinpath(*value.split("/"))


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


positive_path = HERE / "positive" / "claim.k"
negative_path = HERE / "negative" / "claim.k"
bridge_path = HERE / "bridge" / "row-bridge.json"
manifest_path = HERE / "bridge" / "row-manifest.json"
closure_path = HERE / "isabelle" / "STATE_04_Closure.thy"
audit_path = HERE / "isabelle" / "STATE_04_Proof_Audit.thy"
mutation_path = REPOSITORY_ROOT / "evidence" / "end-to-end-refinement" / "row-bundles" / "state-04" / "negative" / "mutation.json"
compiler_output_path = REPOSITORY_ROOT / "evidence" / "end-to-end-refinement" / "runtime-binding" / "native" / "standard-json-output.json"
lock_path = REPOSITORY_ROOT / "formal" / "kevm" / "dependencies.lock.json"

positive = text(positive_path)
negative = text(negative_path)
require(positive == negative, "positive and negative claim bytes differ")
require(positive.startswith('requires "../../../trust-runtime-verification.k"\n'), "common-runner prelude drift")
require("PROGRAM ==K #trustTrustTokenRuntime()" in positive, "exact runtime binding missing")
require('<output> _ => #buf(32, FROZEN) </output>' in positive, "frozen output postcondition missing")
require("0 <Int FROZEN" in positive, "mutant-discriminating frozen premise missing")
require(positive.count("TOKEN_STORAGE") == 4, "named storage remainder count drift")
require(positive.count("in_keys(TOKEN_STORAGE)") == 2, "storage remainder exclusion count drift")
require(positive.count('#hashedLocation("Solidity", 5, SUBJECT_ID)') == 4, "frozen projection count drift")
require(positive.count('#hashedLocation("Solidity", 6, SUBJECT_ID)') == 4, "restriction projection count drift")
exact_calldata_prefix = 'b"\\x15\\x8b\\x1a\\x57\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00"'
require(positive.count(exact_calldata_prefix) == 2, "exact selector4 + zero12 calldata prefix count drift")
require(positive.count("#buf(20, SUBJECT_ID)") == 2, "exact 20-byte subject calldata payload count drift")
require("#abiCallData" not in positive, "helper-shaped ABI calldata remains")

bridge = json.loads(text(bridge_path))
manifest = json.loads(text(manifest_path))
mutation = json.loads(text(mutation_path))
compiler_output = json.loads(text(compiler_output_path))
lock = json.loads(text(lock_path))
require(bridge["obligationId"] == "STATE-04", "bridge obligation drift")
require(bridge["requiredProperty"] == "freeze_and_restriction_are_independent", "bridge property drift")
require(bridge["compilerBinding"]["methodSignature"] == "getFrozenTokens(address)", "getter signature drift")
require(bridge["compilerBinding"]["methodSelector"] == "0x158b1a57", "getter selector bridge drift")
require(bridge["compilerBinding"]["pinnedSolcVersion"] == lock["components"]["solc"]["version"], "solc version drift")
require(bridge["compilerBinding"]["pinnedSolcBinarySha256"] == lock["components"]["solc"]["binarySha256"], "solc binary drift")

token = compiler_output["contracts"]["implementation/src/TrustToken.sol"]["TrustToken"]
layout = {entry["label"]: int(entry["slot"]) for entry in token["storageLayout"]["storage"]}
require(layout.get("_frozen") == 5, "canonical _frozen slot drift")
require(layout.get("_restricted") == 6, "canonical _restricted slot drift")
require(token["evm"]["methodIdentifiers"].get("getFrozenTokens(address)") == "158b1a57", "canonical getter selector drift")
require(bridge["finiteStorageFootprint"]["symbolicKeys"] == 2, "finite storage key count drift")
require(bridge["finiteStorageFootprint"]["pairwiseNonaliasConditions"] == 1, "key nonalias count drift")
require(bridge["finiteStorageFootprint"]["explicitKeyExclusionConditions"] == 2, "rest-map exclusion count drift")
require(bridge["finiteStorageFootprint"]["calldataByteLength"] == 36, "calldata length drift")
require(bridge["calldataEncoding"] == {
    "selector": "0x158b1a57",
    "selectorBytes": 4,
    "addressZeroPrefixBytes": 12,
    "subjectPayloadBytes": 20,
    "totalBytes": 36,
    "sourceShape": "SELECTOR4_ZERO12_SUBJECT20",
}, "exact calldata encoding bridge drift")

require(mutation["obligationId"] == "STATE-04", "mutation obligation drift")
require(mutation["mutationId"] == "STATE-04-CONFLATE-FROZEN-WITH-RESTRICTION", "mutation identity drift")
require(mutation["runtime"]["canonicalResolvedSha256"] == "3697706d4948c34fada47e049d32ad3e1866cf24ded6328f0c209d858614a86d", "canonical runtime drift")
require(mutation["runtime"]["mutantResolvedSha256"] != mutation["runtime"]["canonicalResolvedSha256"], "mutant runtime equals canonical runtime")
mutant_runtime_path = repo_path(mutation["runtime"]["mutantResolvedPath"])
runtime_hex = text(mutant_runtime_path).strip()
require(runtime_hex.startswith("0x") and re.fullmatch(r"0x[0-9a-f]+", runtime_hex) is not None, "mutant runtime encoding drift")
require(hashlib.sha256(bytes.fromhex(runtime_hex[2:])).hexdigest() == mutation["runtime"]["mutantResolvedSha256"], "mutant runtime hash drift")
mutant_bridge_path = repo_path(mutation["bridge"]["mutantPath"])
require(sha256(mutant_bridge_path) == mutation["bridge"]["mutantSha256"], "mutant bridge hash drift")
require(runtime_hex in text(mutant_bridge_path), "mutant bridge does not contain exact runtime")

require(manifest["obligationId"] == "STATE-04", "row manifest obligation drift")
require(manifest["bridge"]["path"] == "formal/kevm/row-bundles/state-04/bridge/row-bridge.json", "row manifest bridge path drift")
require(manifest["bridge"]["sha256"] == sha256(bridge_path), "row manifest bridge hash drift")
require(manifest["proofSpec"]["path"] == "formal/kevm/row-bundles/state-04/positive/claim.k", "row manifest claim path drift")
require(manifest["proofSpec"]["sha256"] == sha256(positive_path), "row manifest claim hash drift")
for generated in manifest["generated"]:
    require(generated["sha256"] == sha256(repo_path(generated["path"])), f"generated artifact hash drift: {generated['path']}")
require(manifest["theorem"]["name"] == "freeze_and_restriction_are_independent", "named theorem drift")
require(manifest["theorem"]["sha256"] == sha256(closure_path), "closure theorem hash drift")
require(manifest["proofAudit"]["sha256"] == sha256(audit_path), "proof audit hash drift")

closure = text(closure_path)
audit = text(audit_path)
require("theorem freeze_and_restriction_are_independent:" in closure, "named closure theorem missing")
require("composite_overlay_has_no_foundation_projection" in closure, "foundation boundary missing")
require("Thm_Deps.all_oracles state04_roots" in audit, "oracle audit missing")
banned = re.compile(r"^\s*(sorry|oops|axiomatization|oracle)\b|\bby\s+eval\b|\bnative_decide\b|\bskip_proof\b", re.MULTILINE)
require(banned.search(closure) is None and banned.search(audit) is None, "banned Isabelle proof form found")

print(json.dumps({
    "schemaVersion": 1,
    "obligationId": "STATE-04",
    "status": "PASS",
    "claimSha256": sha256(positive_path),
    "bridgeSha256": sha256(bridge_path),
    "rowManifestSha256": sha256(manifest_path),
    "mutationManifestSha256": sha256(mutation_path),
    "mutantRuntimeSha256": mutation["runtime"]["mutantResolvedSha256"],
    "theoremSha256": sha256(closure_path),
    "boundary": "Independent static reverse check only; dynamic KEVM and replay remain separate gates.",
}, indent=2, sort_keys=True))
