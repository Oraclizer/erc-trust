#!/usr/bin/env python3
"""Portable independent static reverse check for the final ART-05 product row."""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path


ROW = Path(__file__).resolve().parent
REPOSITORY = ROW.parents[3]
PROPERTY = "theory_source_and_import_closure_are_hash_bound"
POSITIVE_MODULE = "TRUST-ART-05-THEORY-IMPORT-CLOSURE-BINDING-SPEC"
CONTROL_MODULE = "TRUST-ART-05-GOVERNOR-MUTANT-CONTROL-SPEC"
CLAIM_ID = "2c601f4bddb5569250236d5782e3bd759d40fe11b1a1e0434c09b8d656247910"
CANONICAL_WORD = "0x000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266"
MUTANT_WORD = "0x000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92267"
SENDER_INTEGER = "1390849295786071768276380950238675083608645509734"
TOKEN_INTEGER = "1324161310598743833836268493538283093091898295570"

IMMUTABLE = {
    "claim.k": "0bb20986f4b391c31c14b5894653e16f4d71735c52d451b85b9c398349f0115c",
    "bundle.json": "d5262aeabd08ae98d3ca66bd759ea41296c495ac56c55015083a9d97a6e647c3",
    "bridge/row-bridge.json": "acc76c219547fb9b89b16f335b61eb617f7509b9d60139dcda1c80c5674cc264",
    "bridge/row-manifest.json": "e15cac79c0040d535f524523f7f31f78ef69c1d6cae723946318e861822828ce",
    "closure-graph.json": "f855e3107ba52abc9b1b2d8ffe0d7edfffdc4077f8ff27bc2399f3775455d5f0",
    "composition-graph.json": "c51d788a905991dfec3428cd7923b9963a77d79af3d57a1b1a9508da61b37bad",
    "dependency-graph.json": "32bac16a6fc4178273575eb9bfea6087b00802dfbc22a213b6254eba8a092bcf",
    "generated/mutant-runtime-bridge.k": "e382620261e599867e01da6f4916b3bb78af12bbae43ef287b7ee5b2b77cac00",
    "generated/mutant-runtime-verification.k": "e380844cea44b450c03fc3d0f345e22980801b96fe0270fa921c667a8e062bf9",
    "isabelle/ART_05_Theory_Import_Closure_Binding.thy": "fbe318e345e1854bfdc43f575a850cafe411e96ea9045e1849cfd839688b0dcd",
}
SUPPORTING = {
    "mutant-control-claim.k": "c20cad50be72e4ba418907b5c4b6401e944296856a52064e5f8356314caaecfe",
    "proof-prelude.k": "cdee82d1dfe927f7cee1925d0535d3a72cea1b96d88c58125eed78954f805f97",
    "isabelle/ROOT": "c2db706fc7c539e9730ab10fc0eaf089d628c20c3deb079ceb6a5bc8522c2755",
    "isabelle/run-closure.ps1": "c99962bc3a5313064bdf780ae428d75613a38ad797eececb3dc5cc248d6518ff",
}
PRODUCT_COPY_SET = [
    "bridge/row-bridge.json",
    "bridge/row-manifest.json",
    "bundle.json",
    "claim.k",
    "closure-graph.json",
    "composition-graph.json",
    "dependency-graph.json",
    "generate-row-artifacts.mjs",
    "generated/mutant-runtime-bridge.k",
    "generated/mutant-runtime-verification.k",
    "integration-manifest.json",
    "isabelle/ART_05_Theory_Import_Closure_Binding.thy",
    "isabelle/ROOT",
    "isabelle/run-closure.ps1",
    "mutant-control-claim.k",
    "proof-prelude.k",
    "README.md",
    "reverse-check.py",
    "semantic-bridge-certificate.json",
]


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def stable_hash(value: object) -> str:
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
    return sha256_bytes(encoded)


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def repository_path(value: str) -> Path:
    candidate = Path(value)
    require(not candidate.is_absolute() and ".." not in candidate.parts, f"unsafe repository path: {value}")
    result = (REPOSITORY / candidate).resolve()
    result.relative_to(REPOSITORY)
    return result


def verify_reference(reference: dict, label: str) -> Path:
    path = repository_path(reference["path"])
    require(path.is_file(), f"{label} missing: {reference['path']}")
    require(sha256_bytes(path.read_bytes()) == reference["sha256"], f"{label} hash drift")
    return path


def read_runtime(path: Path) -> bytes:
    text = path.read_text(encoding="utf-8").strip().lower()
    require(re.fullmatch(r"0x[0-9a-f]+", text) is not None and len(text) % 2 == 0, "invalid runtime hex")
    return bytes.fromhex(text[2:])


for relative, expected in {**IMMUTABLE, **SUPPORTING}.items():
    path = ROW / relative
    require(path.is_file(), f"product file missing: {relative}")
    require(sha256_bytes(path.read_bytes()) == expected, f"immutable hash drift: {relative}")

bundle = read_json(ROW / "bundle.json")
bridge = read_json(ROW / "bridge" / "row-bridge.json")
row_manifest = read_json(ROW / "bridge" / "row-manifest.json")
closure = read_json(ROW / "closure-graph.json")
composition = read_json(ROW / "composition-graph.json")
dependency = read_json(ROW / "dependency-graph.json")
certificate = read_json(ROW / "semantic-bridge-certificate.json")
integration = read_json(ROW / "integration-manifest.json")
for relative in PRODUCT_COPY_SET:
    require((ROW / relative).is_file(), f"allowlisted product file missing: {relative}")

surface_paths = [
    ROW / "generate-row-artifacts.mjs",
    ROW / "integration-manifest.json",
    ROW / "reverse-check.py",
    ROW / "semantic-bridge-certificate.json",
    ROW / "README.md",
]
forbidden_markers = [
    re.compile("".join(("/mnt", "/c", "/tmp")), re.IGNORECASE),
    re.compile("".join((r"[A-Za-z]:", r"\\", "tmp")), re.IGNORECASE),
    re.compile("".join(("co", "ordinator")), re.IGNORECASE),
    re.compile("".join(("run", "ning")), re.IGNORECASE),
    re.compile("".join(("cell", r"(?:Id|[-_ ]id)")), re.IGNORECASE),
    re.compile(r"replay-[0-9]{3}", re.IGNORECASE),
]
for path in surface_paths:
    text = path.read_text(encoding="utf-8")
    require(not any(pattern.search(text) for pattern in forbidden_markers), f"non-portable execution reference: {path.name}")

for value in (bundle, bridge, row_manifest, certificate):
    require(value["obligationId"] == "ART-05", "obligation identity drift")
require(bundle["requiredProperty"] == bridge["requiredProperty"] == row_manifest["requiredProperty"] == PROPERTY, "property drift")
require(bundle["proofSpec"] == {
    "path": "formal/kevm/row-bundles/art-05/claim.k",
    "module": POSITIVE_MODULE,
    "claimId": CLAIM_ID,
    "sha256": IMMUTABLE["claim.k"],
}, "completed bundle claim identity drift")
require(bundle["bridge"]["sha256"] == IMMUTABLE["bridge/row-bridge.json"], "bundle bridge hash drift")
require(bundle["isabelle"]["sourceSha256"] == IMMUTABLE["isabelle/ART_05_Theory_Import_Closure_Binding.thy"], "bundle theory hash drift")
require(bundle["isabelle"]["rowManifestSha256"] == IMMUTABLE["bridge/row-manifest.json"], "bundle row-manifest hash drift")
require(bundle["positive"]["expectedGraph"] == certificate["canonicalEvidence"]["requiredReportFacts"]["positiveGraph"], "positive graph certificate drift")
require(bundle["negative"]["expectedGraph"] == certificate["canonicalEvidence"]["requiredReportFacts"]["negativeGraph"], "negative graph certificate drift")

require(dependency["selectedObligation"] == {"id": "ART-05", "property": PROPERTY, "status": "OPEN", "theoremName": PROPERTY}, "dependency subject drift")
require(dependency["edges"] == [["ART-01", "ART-05"], ["ART-02", "ART-05"], ["ART-03", "ART-05"], ["ART-04", "ART-05"], ["ART-05", "ART-06"], ["ART-05", "ART-07"]], "dependency edge drift")
require(bridge["dependencies"]["directPrerequisites"] == ["ART-01", "ART-02", "ART-03", "ART-04"], "prerequisite drift")
require(bridge["dependencies"]["directConsumers"] == ["ART-06", "ART-07"], "consumer drift")
require(bridge["dependencies"]["graph"]["sha256"] == IMMUTABLE["dependency-graph.json"], "bridge dependency hash drift")

session_root = REPOSITORY / "formal" / "isabelle" / "ERC_TRUST" / "ROOT"
isabelle_root = session_root.parent
root_text = session_root.read_text(encoding="utf-8")
session_match = re.search(r"session\s+ERC_TRUST\s*=\s*([^\s+]+)\s*\+", root_text)
theory_match = re.search(r"\btheories\s+([\s\S]*?)\s+document_files\b", root_text)
require(session_match is not None and theory_match is not None, "ERC_TRUST ROOT parse failure")
theory_names = theory_match.group(1).strip().split()
require(len(theory_names) == len(set(theory_names)) == 14, "theory inventory drift")
sources: list[dict] = []
edges: list[list[str]] = []
external: list[dict] = []
for name in theory_names:
    path = isabelle_root / f"{name}.thy"
    text = path.read_text(encoding="utf-8")
    declaration = re.search(r"^theory\s+([^\s]+)", text, re.MULTILINE)
    begin = re.search(r"^begin\s*$", text, re.MULTILINE)
    require(declaration is not None and begin is not None and declaration.group(1) == name, f"theory declaration drift: {name}")
    header = text[declaration.start():begin.start()]
    imports_match = re.search(r"^\s*imports\s+([\s\S]*)", header, re.MULTILINE)
    imports = imports_match.group(1).replace('"', "").split() if imports_match else []
    require(bool(imports), f"theory import missing: {name}")
    sources.append({"path": path.resolve().relative_to(REPOSITORY).as_posix(), "sha256": sha256_bytes(path.read_bytes()), "theory": name})
    for imported in imports:
        if imported in theory_names:
            edges.append([imported, name])
        else:
            external.append({"importedBy": name, "theory": imported})
sources.sort(key=lambda value: value["theory"])
edges.sort(key=lambda value: json.dumps(value))
external.sort(key=lambda value: json.dumps(value, sort_keys=True))
closure_material = {
    "schemaVersion": 1,
    "session": "ERC_TRUST",
    "parentSession": session_match.group(1),
    "sessionRoot": {"path": session_root.resolve().relative_to(REPOSITORY).as_posix(), "sha256": sha256_bytes(session_root.read_bytes())},
    "theorySources": sources,
    "localImportEdges": edges,
    "externalImports": external,
    "externalBoundaryLock": {"path": "formal/kevm/dependencies.lock.json", "sha256": "3134e7692086170f86b6dd42e7ebd0256c188da8db8cbd17241c3d2c8d315196"},
}
closure_root = stable_hash(closure_material)
require({key: closure[key] for key in closure_material} == closure_material, "closure graph material drift")
require(closure["closureRootSha256"] == closure_root == bridge["theoryClosure"]["closureRootSha256"], "closure root drift")
require(len(edges) == 13 and external == [{"importedBy": "Regulatory_Execution_Semantics", "theory": "Cross_Domain_State_Preservation.Regulatory_Action_Composition"}], "import closure drift")

runtime_path = repository_path(bridge["runtimeLeaf"]["path"])
require(sha256_bytes(runtime_path.read_bytes()) == bridge["runtimeLeaf"]["textFileSha256"], "runtime text hash drift")
canonical_runtime = read_runtime(runtime_path)
require(sha256_bytes(canonical_runtime) == bridge["runtimeLeaf"]["byteSha256"], "runtime byte hash drift")
canonical_k_path = verify_reference(bridge["runtimeLeaf"]["canonicalKBridge"], "canonical K bridge")
canonical_k = canonical_k_path.read_text(encoding="utf-8")
prefix = 'rule #trustTrustTokenRuntime() => #parseByteStack("'
start = canonical_k.index(prefix) + len(prefix)
end = canonical_k.index('")', start)
require(bytes.fromhex(canonical_k[start:end][2:]) == canonical_runtime, "canonical K runtime leaf drift")
mutation = bridge["semanticMutation"]
mutant_path = verify_reference(mutation["mutantBridge"], "mutant K bridge")
verify_reference(mutation["mutantVerification"], "mutant K verification")
mutant_text = mutant_path.read_text(encoding="utf-8")
mutant_start = mutant_text.index(prefix) + len(prefix)
mutant_end = mutant_text.index('")', mutant_start)
mutant_runtime = bytes.fromhex(mutant_text[mutant_start:mutant_end][2:])
differences = [index for index, pair in enumerate(zip(canonical_runtime, mutant_runtime, strict=True)) if pair[0] != pair[1]]
require(differences == [8553] and canonical_runtime[8553] == 0x66 and mutant_runtime[8553] == 0x67, "runtime mutation drift")
require(sha256_bytes(mutant_runtime) == mutation["mutantRuntimeSha256"], "mutant runtime hash drift")

boundary = bridge["addressWordBoundary"]
require(boundary["allFixtureJsonNumbersSafe"] is True and boundary["addressAndWordRoundTrip"] is True, "address-word audit drift")
require(boundary["integerTerms"]["SENDER_INT"] == SENDER_INTEGER == boundary["integerTerms"]["GOVERNOR_ADDRESS_INT"], "sender/governor integer drift")
require(boundary["integerTerms"]["TOKEN_ADDRESS_INT"] == TOKEN_INTEGER, "token integer drift")
require(f"0x{int(SENDER_INTEGER):064x}" == CANONICAL_WORD and f"0x{int(boundary['mutantGovernorAddress'], 16):064x}" == MUTANT_WORD, "address-word round trip drift")

source_binding = bridge["sourceBinding"]
storage_path = verify_reference(source_binding["trustStorage"], "TrustStorage source")
token_path = verify_reference(source_binding["trustToken"], "TrustToken source")
declaration = re.findall(r"^\s*address public immutable governor;\s*$", storage_path.read_text(encoding="utf-8"), re.MULTILINE)
assignment = re.findall(r"^\s*governor = governor_;\s*$", token_path.read_text(encoding="utf-8"), re.MULTILINE)
require(len(declaration) == len(assignment) == 1, "governor source block multiplicity drift")
require(source_binding["sourceBlocks"] == {
    "governorDeclarationSha256": sha256_bytes(declaration[0].strip().encode()),
    "governorAssignmentSha256": sha256_bytes(assignment[0].strip().encode()),
}, "governor source-block hash drift")

composition_root = stable_hash({key: value for key, value in composition.items() if key != "compositionRootSha256"})
require(composition["compositionRootSha256"] == composition_root == bridge["claimComposition"]["compositionRootSha256"], "composition root drift")
require(composition["theoryClosure"]["closureRootSha256"] == closure_root, "composition closure drift")
require(composition["sourceBinding"] == source_binding and composition["addressWordBoundary"] == boundary, "composition source/boundary drift")
require(composition["runtimeLeaf"] == {
    "byteOffset": 8553,
    "canonicalByte": "0x66",
    "canonicalRuntimeSha256": sha256_bytes(canonical_runtime),
    "exactByteDifferenceCount": 1,
    "mutantByte": "0x67",
    "mutantRuntimeSha256": sha256_bytes(mutant_runtime),
}, "composition runtime leaf drift")

claim_text = (ROW / "claim.k").read_text(encoding="utf-8")
prelude_text = (ROW / "proof-prelude.k").read_text(encoding="utf-8")
require(claim_text.startswith('requires "proof-prelude.k"\n') and re.search(r"^\s*module\b", prelude_text, re.MULTILINE) is None, "proof prelude drift")
for token in (POSITIVE_MODULE, f"loadTx({SENDER_INTEGER}) => #finalizeBlock", f"<acctID> {TOKEN_INTEGER} </acctID>", '#parseByteStack("0x0c340a24")', f'#parseByteStack("{CANONICAL_WORD}")', "EVMC_SUCCESS", "#trustTrustTokenRuntime()"):
    require(token in claim_text, f"claim token missing: {token}")
control_text = (ROW / "mutant-control-claim.k").read_text(encoding="utf-8")
expected_control = claim_text.replace(f"module {POSITIVE_MODULE}", f"module {CONTROL_MODULE}").replace(CANONICAL_WORD, MUTANT_WORD)
require(control_text == expected_control and CANONICAL_WORD not in control_text, "mutant control materialization drift")

theory_path = ROW / "isabelle" / "ART_05_Theory_Import_Closure_Binding.thy"
theory_text = theory_path.read_text(encoding="utf-8")
for token in (f"theorem {PROPERTY}:", closure_root, composition_root, sha256_bytes(canonical_runtime), sha256_bytes(mutant_runtime), "oracle_dependency_count=0"):
    require(token in theory_text, f"theory binding token missing: {token}")
require(re.search(r"^\s*(sorry|oops|axiomatization|oracle)\b|\bby\s+eval\b|\bnative_decide\b|\bskip_proof\b", theory_text, re.MULTILINE) is None, "banned proof source form")

require(row_manifest["bridge"]["sha256"] == IMMUTABLE["bridge/row-bridge.json"], "row-manifest bridge hash drift")
require(row_manifest["closureGraph"]["sha256"] == IMMUTABLE["closure-graph.json"], "row-manifest closure hash drift")
require(row_manifest["compositionGraph"]["sha256"] == IMMUTABLE["composition-graph.json"], "row-manifest composition hash drift")
require(row_manifest["dependencyGraph"]["sha256"] == IMMUTABLE["dependency-graph.json"], "row-manifest dependency hash drift")
require(row_manifest["theorem"]["sha256"] == IMMUTABLE["isabelle/ART_05_Theory_Import_Closure_Binding.thy"], "row-manifest theory hash drift")
require(row_manifest["proofSpec"]["sha256"] == IMMUTABLE["claim.k"], "row-manifest claim hash drift")

canonical_replay = "evidence/end-to-end-refinement/row-bundles/art-05/replay.json"
canonical_artifacts = "evidence/end-to-end-refinement/row-bundles/art-05/artifacts"
require(certificate["status"] == "PASS" and certificate["classification"] == "DISCHARGED_CANDIDATE" and certificate["eligibleForDischarge"] is True, "certificate status drift")
require(certificate["canonicalEvidence"]["replay"] == canonical_replay, "canonical replay interface drift")
require(certificate["canonicalEvidence"]["artifactsDirectory"] == canonical_artifacts, "canonical artifact interface drift")
require(certificate["immutableReplayBoundFiles"]["claim"]["sha256"] == IMMUTABLE["claim.k"], "certificate claim hash drift")
require(certificate["immutableReplayBoundFiles"]["bundle"]["sha256"] == IMMUTABLE["bundle.json"], "certificate bundle hash drift")
require(certificate["immutableReplayBoundFiles"]["bridge"]["sha256"] == IMMUTABLE["bridge/row-bridge.json"], "certificate bridge hash drift")
require(certificate["immutableReplayBoundFiles"]["rowManifest"]["sha256"] == IMMUTABLE["bridge/row-manifest.json"], "certificate row-manifest hash drift")
require(certificate["immutableReplayBoundFiles"]["theory"]["sha256"] == IMMUTABLE["isabelle/ART_05_Theory_Import_Closure_Binding.thy"], "certificate theory hash drift")

require(integration["schemaVersion"] == 2 and integration["obligationId"] == "ART-05", "integration manifest identity drift")
require(integration["requiredProperty"] == PROPERTY and integration["status"] == "READY_FOR_CANONICAL_COPY_AND_BIND", "integration manifest status drift")
require(integration["workerOnlyCopyContract"] is True and integration["copiedToProduct"] is False, "integration manifest mutation-state drift")
require(integration["productRoot"] == "formal/kevm/row-bundles/art-05", "integration manifest product root drift")
require(integration["productCopySet"] == PRODUCT_COPY_SET, "integration manifest product copy set drift")
for relative in integration["productCopySet"]:
    copy_path = Path(relative)
    require(not copy_path.is_absolute() and ".." not in copy_path.parts, f"unsafe product copy path: {relative}")
require(integration["immutableReplayBoundFiles"] == IMMUTABLE, "integration manifest immutable hash inventory drift")
require(integration["canonicalEvidence"]["replay"] == canonical_replay, "integration manifest canonical replay drift")
require(integration["canonicalEvidence"]["artifactsDirectory"] == canonical_artifacts, "integration manifest canonical artifacts drift")
require(integration["canonicalEvidence"]["requiredReportFacts"] == {
    "status": "PASS",
    "authoritativeFreshReplayRequired": False,
    "obligationId": "ART-05",
    "claimId": CLAIM_ID,
    "runnerSourceAndExecutedSha256": "1ab935de0dd7b40bb108955b60c232f6fa3afdeea62e6eb380a2fe26a0a3dcc1",
}, "integration manifest expected replay facts drift")
require(integration["commands"] == {
    "generate": ["node", "formal/kevm/row-bundles/art-05/generate-row-artifacts.mjs"],
    "reverseCheck": ["python3", "formal/kevm/row-bundles/art-05/reverse-check.py"],
    "curateTemplate": [
        "python3",
        "formal/kevm/row-bundles/curate-row-output.py",
        "--repository-root",
        ".",
        "--bundle",
        "formal/kevm/row-bundles/art-05/bundle.json",
        "--isabelle-report",
        "<verified-isabelle-closure-report>",
        "--output-directory",
        "<completed-proof-output>",
        "--curated-evidence-directory",
        canonical_artifacts,
        "--report",
        canonical_replay,
        "--executed-runner-sha256",
        "1ab935de0dd7b40bb108955b60c232f6fa3afdeea62e6eb380a2fe26a0a3dcc1",
    ],
    "verifyCurated": [
        "python3",
        "formal/kevm/row-bundles/verify-curated-evidence.py",
        "--repository-root",
        ".",
        "--report",
        canonical_replay,
    ],
    "bindDryRun": ["node", "scripts/bind-row-discharge.mjs", "ART-05", canonical_replay],
    "bindWrite": ["node", "scripts/bind-row-discharge.mjs", "ART-05", canonical_replay, "--write"],
    "globalVerify": ["node", "scripts/verify-end-to-end-evidence.mjs"],
}, "integration manifest canonical command drift")
require(integration["sharedMutationBoundary"] == {
    "manualSharedFileEditsAllowed": False,
    "binderMayWriteOnlyAfterDryRunPass": [
        "evidence/end-to-end-refinement/obligation-evidence-index.json",
        "evidence/end-to-end-refinement/proof-run-ledger.json",
    ],
    "globalVerifierRequiredAfterBindWrite": True,
}, "integration manifest shared mutation boundary drift")

required_report_facts = certificate["canonicalEvidence"]["requiredReportFacts"]
require(required_report_facts["status"] == "PASS" and required_report_facts["authoritativeFreshReplayRequired"] is False, "expected replay status drift")
require(required_report_facts["runnerSourceAndExecutedSha256"] == "1ab935de0dd7b40bb108955b60c232f6fa3afdeea62e6eb380a2fe26a0a3dcc1", "expected runner identity drift")
require(required_report_facts["positiveGraph"] == bundle["positive"]["expectedGraph"], "expected positive replay graph drift")
require(required_report_facts["negativeGraph"] == bundle["negative"]["expectedGraph"], "expected negative replay graph drift")

print(json.dumps({
    "status": "PASS_FINAL_STATIC",
    "classification": "DISCHARGED_CANDIDATE",
    "eligibleForDischarge": True,
    "obligationId": "ART-05",
    "requiredProperty": PROPERTY,
    "claimId": CLAIM_ID,
    "closureRootSha256": closure_root,
    "compositionRootSha256": composition_root,
    "theoryCount": len(sources),
    "localImportEdgeCount": len(edges),
    "externalImportCount": len(external),
    "runtimeSha256": sha256_bytes(canonical_runtime),
    "mutantRuntimeSha256": sha256_bytes(mutant_runtime),
    "mutationByteOffset": 8553,
    "immutableReplayBoundFiles": IMMUTABLE,
    "productCopySet": PRODUCT_COPY_SET,
    "canonicalReplay": canonical_replay,
    "canonicalArtifacts": canonical_artifacts,
}, indent=2))
