import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const row = dirname(fileURLToPath(import.meta.url));
const sha256 = (path) => createHash("sha256").update(readFileSync(path)).digest("hex");
const readJson = (path) => JSON.parse(readFileSync(path, "utf8"));

const immutableReplayBoundFiles = {
  "claim.k": "0bb20986f4b391c31c14b5894653e16f4d71735c52d451b85b9c398349f0115c",
  "bundle.json": "d5262aeabd08ae98d3ca66bd759ea41296c495ac56c55015083a9d97a6e647c3",
  "bridge/row-bridge.json": "acc76c219547fb9b89b16f335b61eb617f7509b9d60139dcda1c80c5674cc264",
  "bridge/row-manifest.json": "e15cac79c0040d535f524523f7f31f78ef69c1d6cae723946318e861822828ce",
  "closure-graph.json": "f855e3107ba52abc9b1b2d8ffe0d7edfffdc4077f8ff27bc2399f3775455d5f0",
  "composition-graph.json": "c51d788a905991dfec3428cd7923b9963a77d79af3d57a1b1a9508da61b37bad",
  "dependency-graph.json": "32bac16a6fc4178273575eb9bfea6087b00802dfbc22a213b6254eba8a092bcf",
  "generated/mutant-runtime-bridge.k": "e382620261e599867e01da6f4916b3bb78af12bbae43ef287b7ee5b2b77cac00",
  "generated/mutant-runtime-verification.k": "e380844cea44b450c03fc3d0f345e22980801b96fe0270fa921c667a8e062bf9",
  "isabelle/ART_05_Theory_Import_Closure_Binding.thy": "fbe318e345e1854bfdc43f575a850cafe411e96ea9045e1849cfd839688b0dcd"
};

const supportingProofInputs = {
  "mutant-control-claim.k": "c20cad50be72e4ba418907b5c4b6401e944296856a52064e5f8356314caaecfe",
  "proof-prelude.k": "cdee82d1dfe927f7cee1925d0535d3a72cea1b96d88c58125eed78954f805f97",
  "isabelle/ROOT": "c2db706fc7c539e9730ab10fc0eaf089d628c20c3deb079ceb6a5bc8522c2755",
  "isabelle/run-closure.ps1": "c99962bc3a5313064bdf780ae428d75613a38ad797eececb3dc5cc248d6518ff"
};

for (const [path, expected] of Object.entries({ ...immutableReplayBoundFiles, ...supportingProofInputs })) {
  const actual = sha256(resolve(row, path));
  if (actual !== expected) throw new Error(`${path} hash drift: ${actual}`);
}

const certificate = readJson(resolve(row, "semantic-bridge-certificate.json"));
const integration = readJson(resolve(row, "integration-manifest.json"));
const expectedProductCopySet = [
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
  "semantic-bridge-certificate.json"
];

if (JSON.stringify(integration.productCopySet) !== JSON.stringify(expectedProductCopySet)) {
  throw new Error("integration manifest product copy set drift");
}

for (const path of expectedProductCopySet) readFileSync(resolve(row, path));

const surfaceFiles = [
  "generate-row-artifacts.mjs",
  "integration-manifest.json",
  "reverse-check.py",
  "semantic-bridge-certificate.json",
  "README.md"
];
const forbiddenMarkers = [
  new RegExp(["/mnt", "/c", "/tmp"].join(""), "i"),
  new RegExp(["[A-Za-z]:", "\\\\", "tmp"].join(""), "i"),
  new RegExp(["co", "ordinator"].join(""), "i"),
  new RegExp(["run", "ning"].join(""), "i"),
  new RegExp(["cell", "(?:Id|[-_ ]id)"].join(""), "i"),
  /replay-[0-9]{3}/i
];
for (const path of surfaceFiles) {
  const text = readFileSync(resolve(row, path), "utf8");
  if (forbiddenMarkers.some((pattern) => pattern.test(text))) {
    throw new Error(`${path} contains a non-portable execution reference`);
  }
}

if (certificate.classification !== "DISCHARGED_CANDIDATE" || certificate.eligibleForDischarge !== true) {
  throw new Error("certificate classification drift");
}
if (certificate.canonicalEvidence.replay !== "evidence/end-to-end-refinement/row-bundles/art-05/replay.json") {
  throw new Error("canonical replay target drift");
}
if (integration.productRoot !== "formal/kevm/row-bundles/art-05"
    || integration.canonicalEvidence.replay !== certificate.canonicalEvidence.replay
    || integration.canonicalEvidence.artifactsDirectory !== certificate.canonicalEvidence.artifactsDirectory) {
  throw new Error("integration manifest canonical target drift");
}
if (integration.sharedMutationBoundary.manualSharedFileEditsAllowed !== false
    || integration.sharedMutationBoundary.globalVerifierRequiredAfterBindWrite !== true
    || JSON.stringify(integration.sharedMutationBoundary.binderMayWriteOnlyAfterDryRunPass) !== JSON.stringify([
      "evidence/end-to-end-refinement/obligation-evidence-index.json",
      "evidence/end-to-end-refinement/proof-run-ledger.json"
    ])) {
  throw new Error("integration manifest shared mutation boundary drift");
}

process.stdout.write(`${JSON.stringify({
  status: "PASS_FINAL_STATIC",
  classification: "DISCHARGED_CANDIDATE",
  eligibleForDischarge: true,
  obligationId: "ART-05",
  requiredProperty: "theory_source_and_import_closure_are_hash_bound",
  immutableReplayBoundFiles,
  supportingProofInputs,
  productCopySet: expectedProductCopySet,
  canonicalReplay: certificate.canonicalEvidence.replay,
  canonicalArtifacts: certificate.canonicalEvidence.artifactsDirectory
}, null, 2)}\n`);
