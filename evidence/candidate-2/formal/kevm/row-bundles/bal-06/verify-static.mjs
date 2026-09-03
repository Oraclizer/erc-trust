import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const bundleRoot = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(bundleRoot, "../../../..");
const positiveClaimPath = join(bundleRoot, "positive", "claim.k");
const negativeClaimPath = join(bundleRoot, "negative", "claim.k");
const bundlePath = join(bundleRoot, "bundle.json");
const theoryPath = join(bundleRoot, "isabelle", "BAL_06_Closure.thy");
const generatedTheoryPath = join(bundleRoot, "isabelle", "BAL_06_Bridge_Generated.thy");
const auditTheoryPath = join(bundleRoot, "isabelle", "BAL_06_Proof_Audit.thy");
const bridgePath = join(bundleRoot, "bridge", "row-bridge.json");
const rowManifestPath = join(bundleRoot, "bridge", "row-manifest.json");
const mutationPath = join(
  repositoryRoot,
  "evidence",
  "end-to-end-refinement",
  "row-bundles",
  "bal-06",
  "negative",
  "mutation.json",
);
const compilerOutputPath = join(
  repositoryRoot,
  "evidence",
  "end-to-end-refinement",
  "runtime-binding",
  "native",
  "standard-json-output.json",
);
const lockPath = join(repositoryRoot, "formal", "kevm", "dependencies.lock.json");

function bytes(path) {
  return readFileSync(path);
}

function text(path) {
  return bytes(path).toString("utf8");
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function repoPath(path) {
  return join(repositoryRoot, ...path.split("/"));
}

const positiveClaim = text(positiveClaimPath);
const negativeClaim = text(negativeClaimPath);
assert(positiveClaim === negativeClaim, "positive and negative claim sources differ");
const normalizedClaim = positiveClaim.replace(/\r\n/g, "\n");
const firstNewline = normalizedClaim.indexOf("\n");
assert(firstNewline >= 0, "claim has no requires prelude line");
assert(
  normalizedClaim.slice(0, firstNewline) === 'requires "../../../trust-runtime-verification.k"',
  "common-runner requires prelude drift",
);
const executedClaim = normalizedClaim.slice(firstNewline + 1);
assert(executedClaim.includes("module TRUST-BAL-06-ORDINARY-TRANSFER-PRESERVES-FLOOR-SPEC"), "stripped claim module missing");
assert(!positiveClaim.includes(".IntList"), "scalar slot helper remains in claim");
assert((positiveClaim.match(/^\s*29 \|-> 0$/gm) ?? []).length === 2, "slot 29 idle frame is not exact");
assert((positiveClaim.match(/=\/=Int/g) ?? []).length === 51, "address/key nonalias condition count drift");
assert((positiveClaim.match(/=\/=Int 29/g) ?? []).length === 9, "slot 29 nonalias condition count drift");
assert(positiveClaim.includes("PROGRAM ==K #trustTrustTokenRuntime()"), "exact runtime program binding missing");
assert(
  (positiveClaim.match(/b"\\xa9\\x05\\x9c\\xbb(?:\\x00){12}"/g) ?? []).length === 2,
  "literal transfer selector and address zero-prefix binding drift",
);
assert((positiveClaim.match(/#buf\(20, DESTINATION_ID\)/g) ?? []).length === 2, "20-byte destination encoding drift");
assert((positiveClaim.match(/#buf\(32, AMOUNT\)/g) ?? []).length === 2, "32-byte amount encoding drift");
assert(positiveClaim.includes(") ==Int 68"), "exact transfer calldata length binding missing");
assert(!positiveClaim.includes("_:Map"), "anonymous storage remainder remains in claim");
assert((positiveClaim.match(/TOKEN_STORAGE:Map/g) ?? []).length === 1, "named pre-storage rest-map binding drift");
assert((positiveClaim.match(/^\s*TOKEN_STORAGE$/gm) ?? []).length === 1, "named origStorage rest-map frame drift");
assert((positiveClaim.match(/in_keys\(TOKEN_STORAGE\)/g) ?? []).length === 10, "rest-map key exclusion count drift");
for (const token of [
  '#hashedLocation("Solidity", 3, SOURCE_ID)',
  '#hashedLocation("Solidity", 3, DESTINATION_ID)',
  '#hashedLocation("Solidity", 3, OTHER_ID)',
  '#hashedLocation("Solidity", 5, SOURCE_ID)',
  '#hashedLocation("Solidity", 5, DESTINATION_ID)',
  '#hashedLocation("Solidity", 7, SOURCE_ID)',
  '#hashedLocation("Solidity", 7, DESTINATION_ID)',
]) {
  assert(positiveClaim.includes(token), `runtime projection missing: ${token}`);
}
for (const frame of ["FROZEN", "DESTINATION_FROZEN", "BACKING", "DESTINATION_BACKING", "OTHER_BALANCE"]) {
  assert((positiveClaim.match(new RegExp(`\\|-> ${frame}\\b`, "g")) ?? []).length === 2, `frame drift: ${frame}`);
}

const compilerOutput = JSON.parse(text(compilerOutputPath));
const token = compilerOutput.contracts["implementation/src/TrustToken.sol"].TrustToken;
const layout = Object.fromEntries(token.storageLayout.storage.map((entry) => [entry.label, Number(entry.slot)]));
for (const [label, slot] of Object.entries({
  _balances: 3,
  _frozen: 5,
  _restricted: 6,
  _custodyBacking: 7,
  _entered: 29,
})) {
  assert(layout[label] === slot, `canonical storage layout drift: ${label}:${layout[label]}`);
}
assert(token.evm.methodIdentifiers["transfer(address,uint256)"] === "a9059cbb", "canonical transfer selector drift");

const lock = JSON.parse(text(lockPath));
const mutation = JSON.parse(text(mutationPath));
assert(mutation.compiler.version === lock.components.solc.version, "mutant solc version drift");
assert(mutation.compiler.binarySha256 === lock.components.solc.binarySha256, "mutant solc binary drift");
assert(mutation.runtime.canonicalResolvedSha256 === "3697706d4948c34fada47e049d32ad3e1866cf24ded6328f0c209d858614a86d", "canonical runtime drift");
assert(mutation.runtime.mutantResolvedSha256 === "110486b3be40f444234fb8ebea43c1269fac8459905d6de32487982c8d152995", "mutant runtime drift");
assert(mutation.runtime.canonicalResolvedSha256 !== mutation.runtime.mutantResolvedSha256, "mutant runtime equals canonical runtime");
assert(mutation.runtime.mutantByteLength <= 24_576, "mutant exceeds EIP-170");
const mutantSource = text(join(repositoryRoot, ...mutation.source.mutantPath.split("/")));
assert((mutantSource.match(/_custodyBacking\[from\] = 0; \/\/ BAL-06 semantic mutant/g) ?? []).length === 1, "mutation is not unique");

const bridge = JSON.parse(text(bridgePath));
assert(bridge.obligationId === "BAL-06", "bridge row mismatch");
assert(bridge.compilerBinding.methodSelector === "0xa9059cbb", "bridge selector mismatch");
assert(bridge.finiteStorageFootprint.symbolicKeys === 10, "finite footprint size drift");
assert(bridge.finiteStorageFootprint.pairwiseNonaliasConditions === 45, "finite key nonalias count drift");
assert(bridge.finiteStorageFootprint.restMapVariable === "TOKEN_STORAGE", "rest-map variable bridge drift");
assert(bridge.finiteStorageFootprint.explicitKeyExclusionConditions === 10, "rest-map exclusion bridge drift");
assert(bridge.finiteStorageFootprint.calldataByteLength === 68, "calldata length bridge drift");
assert(bridge.finiteStorageFootprint.scalarSlot29Normalization === "LITERAL_STORAGE_KEY_29", "slot 29 bridge drift");
assert(bridge.calldataEncoding.selector === "0xa9059cbb", "calldata selector bridge drift");
assert(bridge.calldataEncoding.selectorBytes === 4, "calldata selector width drift");
assert(bridge.calldataEncoding.addressZeroPrefixBytes === 12, "address zero-prefix width drift");
assert(bridge.calldataEncoding.destinationPayloadBytes === 20, "destination payload width drift");
assert(bridge.calldataEncoding.amountPayloadBytes === 32, "amount payload width drift");
assert(bridge.calldataEncoding.totalBytes === 68, "calldata total width drift");
assert(bridge.calldataEncoding.sourceShape === "SELECTOR4_ZERO12_DESTINATION20_AMOUNT32", "calldata source shape drift");

const rowManifest = JSON.parse(text(rowManifestPath));
assert(rowManifest.obligationId === "BAL-06", "row manifest obligation drift");
assert(rowManifest.bridge.path === "formal/kevm/row-bundles/bal-06/bridge/row-bridge.json", "row manifest bridge path drift");
assert(sha256(bytes(bridgePath)) === rowManifest.bridge.sha256, "row manifest bridge hash drift");
assert(rowManifest.proofSpec.module === "TRUST-BAL-06-ORDINARY-TRANSFER-PRESERVES-FLOOR-SPEC", "row manifest module drift");
assert(sha256(bytes(repoPath(rowManifest.proofSpec.path))) === rowManifest.proofSpec.sha256, "row manifest proof source drift");
for (const generated of rowManifest.generated) {
  assert(sha256(bytes(repoPath(generated.path))) === generated.sha256, `row manifest generated artifact drift: ${generated.path}`);
}

const theory = text(theoryPath);
const generatedTheory = text(generatedTheoryPath);
const auditTheory = text(auditTheoryPath);
assert(rowManifest.theorem.name === "ordinary_transfer_preserves_backing_and_own_frozen_floor", "row manifest theorem name drift");
assert(rowManifest.theorem.session === "BAL_06_Row", "row manifest Isabelle session drift");
assert(sha256(bytes(repoPath(rowManifest.theorem.path))) === rowManifest.theorem.sha256, "row manifest theorem source drift");
assert(sha256(bytes(repoPath(rowManifest.proofAudit.path))) === rowManifest.proofAudit.sha256, "row manifest proof-audit source drift");

const pendingBundle = JSON.parse(text(bundlePath));
assert(pendingBundle.proofSpec.path === "formal/kevm/row-bundles/bal-06/positive/claim.k", "pending bundle proof path drift");
assert(pendingBundle.proofSpec.sha256 === sha256(bytes(positiveClaimPath)), "pending bundle proof hash drift");
assert(pendingBundle.bridge.reverseCheck === "formal/kevm/row-bundles/bal-06/verify-static.mjs", "pending bundle reverse-check path drift");
assert(pendingBundle.isabelle.sourceSha256 === sha256(bytes(theoryPath)), "pending bundle theorem hash drift");
assert(pendingBundle.isabelle.session === "BAL_06_Row", "pending bundle session drift");
assert(pendingBundle.isabelle.rowManifestSha256 === sha256(bytes(rowManifestPath)), "pending bundle manifest hash drift");
assert(theory.includes("theorem ordinary_transfer_preserves_backing_and_own_frozen_floor:"), "named closure theorem missing");
assert(theory.includes("bal06_retrieves view' st' source destination other"), "runtime-to-abstract retrieve closure missing");
const bannedSourcePattern = /^\s*(sorry|oops|axiomatization|oracle)\b|\bby\s+eval\b|\bnative_decide\b|\bskip_proof\b/gm;
for (const [name, source] of [["generated", generatedTheory], ["closure", theory], ["audit", auditTheory]]) {
  assert(!bannedSourcePattern.test(source), `banned Isabelle source form found: ${name}`);
  bannedSourcePattern.lastIndex = 0;
}
assert(generatedTheory.includes("generated_bal06_storage_projection_is_exact"), "generated storage bridge theorem missing");
assert(generatedTheory.includes("generated_bal06_runtime_frame_is_exact"), "generated runtime frame theorem missing");
assert(generatedTheory.includes("bal06_rest_map_key_exclusion_count = 10"), "generated rest-map exclusion bridge missing");
assert(generatedTheory.includes("bal06_calldata_byte_length = 68"), "generated calldata length bridge missing");
assert(generatedTheory.includes("bal06_address_zero_prefix_bytes = 12"), "generated address zero-prefix bridge missing");
assert(generatedTheory.includes("bal06_destination_payload_bytes = 20"), "generated destination width bridge missing");
assert(generatedTheory.includes("bal06_amount_payload_bytes = 32"), "generated amount width bridge missing");
assert(auditTheory.includes("Thm_Deps.all_oracles bal06_roots"), "oracle dependency audit missing");
for (const statement of [
  "custody_backing st' destination = custody_backing st destination",
  "frozen_targets st' destination = frozen_targets st destination",
  "physical_balances st' other = physical_balances st other",
]) {
  assert(theory.includes(statement), `Isabelle frame statement missing: ${statement}`);
}

console.log(JSON.stringify({
  schemaVersion: 1,
  obligationId: "BAL-06",
  status: "PASS",
  claimSourcesIdentical: true,
  positiveClaimSha256: sha256(bytes(positiveClaimPath)),
  negativeClaimSha256: sha256(bytes(negativeClaimPath)),
  commonRunnerExecutedClaimSha256: sha256(Buffer.from(executedClaim, "utf8")),
  theorySha256: sha256(bytes(theoryPath)),
  generatedTheorySha256: sha256(bytes(generatedTheoryPath)),
  proofAuditTheorySha256: sha256(bytes(auditTheoryPath)),
  bridgeSha256: sha256(bytes(bridgePath)),
  rowManifestSha256: sha256(bytes(rowManifestPath)),
  mutationManifestSha256: sha256(bytes(mutationPath)),
  canonicalCompilerOutputSha256: sha256(bytes(compilerOutputPath)),
  scalarSlot29: 29,
  symbolicStorageKeys: 10,
  keyNonaliasConditions: 45,
  restMapKeyExclusionConditions: 10,
  calldataByteLength: 68,
  addressZeroPrefixBytes: 12,
  destinationPayloadBytes: 20,
  amountPayloadBytes: 32,
  commonRunnerStaticCompatibility: "PASS_PENDING_KEVM_DYNAMIC_FIELDS",
  caveat: "Static gate only. KEVM parse/proofs, Isabelle build, replay, and coordinator registry binding remain required.",
}, null, 2));
