import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const bundleRoot = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(bundleRoot, "../../../..");

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

const positiveClaimPath = join(bundleRoot, "positive", "claim.k");
const negativeClaimPath = join(bundleRoot, "negative", "claim.k");
const bridgePath = join(bundleRoot, "bridge", "row-bridge.json");
const generatedTheoryPath = join(bundleRoot, "isabelle", "STATE_04_Bridge_Generated.thy");
const closureTheoryPath = join(bundleRoot, "isabelle", "STATE_04_Closure.thy");
const auditTheoryPath = join(bundleRoot, "isabelle", "STATE_04_Proof_Audit.thy");
const rowManifestPath = join(bundleRoot, "bridge", "row-manifest.json");
const mutationPlanPath = join(
  repositoryRoot,
  "evidence",
  "end-to-end-refinement",
  "row-bundles",
  "state-04",
  "negative",
  "mutation-plan.json",
);
const mutationPath = join(
  repositoryRoot,
  "evidence",
  "end-to-end-refinement",
  "row-bundles",
  "state-04",
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
const tokenSourcePath = join(repositoryRoot, "implementation", "src", "TrustToken.sol");
const fixturePath = join(
  repositoryRoot,
  "evidence",
  "end-to-end-refinement",
  "runtime-binding",
  "resolved",
  "fixture.json",
);

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
assert(
  executedClaim.includes("module TRUST-STATE-04-FREEZE-RESTRICTION-INDEPENDENT-SPEC"),
  "STATE-04 module missing",
);
assert(positiveClaim.includes("PROGRAM ==K #trustTrustTokenRuntime()"), "exact runtime binding missing");
assert(positiveClaim.includes('<output> _ => #buf(32, FROZEN) </output>'), "frozen getter postcondition missing");
const exactGetterCalldata =
  'b"\\x15\\x8b\\x1a\\x57\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00"';
assert((positiveClaim.match(new RegExp(exactGetterCalldata.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "g")) ?? []).length === 2, "exact selector4 + zero12 calldata prefix count drift");
assert((positiveClaim.match(/#buf\(20, SUBJECT_ID\)/g) ?? []).length === 2, "exact 20-byte subject calldata payload count drift");
assert(!positiveClaim.includes("#abiCallData"), "helper-shaped ABI calldata remains");
assert(!positiveClaim.includes("_:Map"), "anonymous storage remainder remains");
assert((positiveClaim.match(/TOKEN_STORAGE:Map/g) ?? []).length === 1, "pre-storage rest-map binding drift");
assert((positiveClaim.match(/^\s*TOKEN_STORAGE$/gm) ?? []).length === 1, "origStorage rest-map frame drift");
assert((positiveClaim.match(/in_keys\(TOKEN_STORAGE\)/g) ?? []).length === 2, "rest-map exclusion count drift");
assert((positiveClaim.match(/=\/=Int/g) ?? []).length === 3, "address/key nonalias count drift");
assert((positiveClaim.match(/#hashedLocation\("Solidity", 5, SUBJECT_ID\)/g) ?? []).length === 4, "frozen projection count drift");
assert((positiveClaim.match(/#hashedLocation\("Solidity", 6, SUBJECT_ID\)/g) ?? []).length === 4, "restriction projection count drift");
assert((positiveClaim.match(/^\s*#hashedLocation\("Solidity", 6, SUBJECT_ID\) \|-> 1$/gm) ?? []).length === 2, "canonical true word frame drift");
assert(positiveClaim.includes("0 <Int FROZEN"), "mutant-discriminating nonzero frozen precondition missing");

const compilerOutputBytes = bytes(compilerOutputPath);
assert(
  sha256(compilerOutputBytes) === "9697548b65ac0b4fdeff17deca78d9e11e49676dd0d78bd9d94907b24d5ac34e",
  "canonical compiler output drift",
);
const compilerOutput = JSON.parse(compilerOutputBytes);
const token = compilerOutput.contracts["implementation/src/TrustToken.sol"].TrustToken;
const layout = Object.fromEntries(token.storageLayout.storage.map((entry) => [entry.label, entry]));
assert(Number(layout._frozen.slot) === 5, "_frozen base slot drift");
assert(layout._frozen.type === "t_mapping(t_address,t_uint256)", "_frozen type drift");
assert(Number(layout._restricted.slot) === 6, "_restricted base slot drift");
assert(layout._restricted.type === "t_mapping(t_address,t_bool)", "_restricted type drift");
assert(token.evm.methodIdentifiers["getFrozenTokens(address)"] === "158b1a57", "getter selector drift");

const bridge = JSON.parse(text(bridgePath));
assert(bridge.obligationId === "STATE-04", "bridge row mismatch");
assert(bridge.requiredProperty === "freeze_and_restriction_are_independent", "bridge property mismatch");
assert(bridge.compilerBinding.canonicalOutputSha256 === sha256(compilerOutputBytes), "bridge compiler output identity drift");
assert(
  bridge.compilerBinding.canonicalStorageLayoutSha256 ===
    sha256(Buffer.from(JSON.stringify(token.storageLayout), "utf8")),
  "bridge storage-layout identity drift",
);
assert(bridge.compilerBinding.methodSelector === "0x158b1a57", "bridge selector mismatch");
assert(bridge.finiteStorageFootprint.symbolicKeys === 2, "bridge key count drift");
assert(bridge.finiteStorageFootprint.pairwiseNonaliasConditions === 1, "bridge nonalias count drift");
assert(bridge.finiteStorageFootprint.restMapVariable === "TOKEN_STORAGE", "bridge rest-map drift");
assert(bridge.finiteStorageFootprint.explicitKeyExclusionConditions === 2, "bridge exclusion count drift");
assert(bridge.finiteStorageFootprint.calldataByteLength === 36, "bridge calldata length drift");
assert(bridge.calldataEncoding.selector === "0x158b1a57", "calldata selector bridge drift");
assert(bridge.calldataEncoding.selectorBytes === 4, "calldata selector width drift");
assert(bridge.calldataEncoding.addressZeroPrefixBytes === 12, "calldata address zero-prefix width drift");
assert(bridge.calldataEncoding.subjectPayloadBytes === 20, "calldata subject payload width drift");
assert(bridge.calldataEncoding.totalBytes === 36, "calldata total width drift");
assert(bridge.calldataEncoding.sourceShape === "SELECTOR4_ZERO12_SUBJECT20", "calldata source shape drift");

const mutationPlan = JSON.parse(text(mutationPlanPath));
assert(mutationPlan.obligationId === "STATE-04", "mutation plan row mismatch");
assert(sha256(bytes(tokenSourcePath)) === mutationPlan.canonicalSource.sha256, "mutation source identity drift");
const canonicalSource = text(tokenSourcePath).replace(/\r\n/g, "\n");
assert(canonicalSource.split(mutationPlan.uniqueAnchor).length === 2, "mutation anchor is not unique");
assert(mutationPlan.replacement.includes("_restricted[account] ? 0 : _frozen[account]"), "mutation does not conflate overlays");
assert(mutationPlan.discriminatingPrecondition.restrictedStorageWord === 1, "mutation precondition bool word drift");
const mutation = JSON.parse(text(mutationPath));
const lock = JSON.parse(text(join(repositoryRoot, "formal", "kevm", "dependencies.lock.json")));
assert(mutation.obligationId === "STATE-04", "compiled mutation row mismatch");
assert(mutation.mutationId === mutationPlan.mutationId, "compiled mutation ID drift");
assert(mutation.compiler.version === lock.components.solc.version, "mutant solc version drift");
assert(mutation.compiler.binarySha256 === lock.components.solc.binarySha256, "mutant solc binary drift");
assert(mutation.source.canonicalSha256 === mutationPlan.canonicalSource.sha256, "compiled canonical source drift");
const mutantInputPath = repoPath(mutation.compiler.mutantInputPath);
const mutantOutputPath = repoPath(mutation.compiler.mutantOutputPath);
const mutantSourcePath = repoPath(mutation.source.mutantPath);
const mutantRuntimePath = repoPath(mutation.runtime.mutantResolvedPath);
const mutantBridgePath = repoPath(mutation.bridge.mutantPath);
const mutantVerificationPath = repoPath(mutation.bridge.verificationPath);
const mutantInputBytes = bytes(mutantInputPath);
const mutantOutputBytes = bytes(mutantOutputPath);
const mutantSourceBytes = bytes(mutantSourcePath);
const mutantRuntimeText = text(mutantRuntimePath).trim();
const mutantBridge = text(mutantBridgePath);
const mutantVerificationBytes = bytes(mutantVerificationPath);

assert(sha256(mutantInputBytes) === mutation.compiler.mutantInputSha256, "mutant compiler input identity drift");
assert(sha256(mutantOutputBytes) === mutation.compiler.mutantOutputSha256, "mutant compiler output identity drift");
assert(sha256(mutantSourceBytes) === mutation.source.mutantSha256, "mutant source identity drift");
assert(sha256(Buffer.from(mutantRuntimeText.slice(2), "hex")) === mutation.runtime.mutantResolvedSha256, "mutant runtime identity drift");
assert(sha256(Buffer.from(mutantBridge, "utf8")) === mutation.bridge.mutantSha256, "mutant runtime bridge identity drift");
assert(sha256(mutantVerificationBytes) === mutation.bridge.verificationSha256, "mutant verification module identity drift");

const mutantSource = mutantSourceBytes.toString("utf8");
assert((mutantSource.match(/_restricted\[account\] \? 0 : _frozen\[account\]; \/\/ STATE-04 semantic mutant/g) ?? []).length === 1, "compiled mutation is not unique");
assert(mutation.runtime.canonicalResolvedSha256 !== mutation.runtime.mutantResolvedSha256, "mutant runtime equals canonical runtime");
assert(mutation.runtime.mutantByteLength <= 24_576, "mutant exceeds EIP-170");

assert(/^0x[0-9a-f]+$/.test(mutantRuntimeText), "mutant runtime hex is malformed");
const mutantRuntimeBytes = Buffer.from(mutantRuntimeText.slice(2), "hex");
assert(mutantRuntimeBytes.length === mutation.runtime.mutantByteLength, "mutant runtime byte length drift");
const mutantOutput = JSON.parse(mutantOutputBytes);
const mutantToken = mutantOutput.contracts["implementation/src/TrustToken.sol"]?.TrustToken;
assert(mutantToken, "mutant compiler output is missing TrustToken");
assert(mutantToken.evm.methodIdentifiers["getFrozenTokens(address)"] === "158b1a57", "mutant getter selector drift");
const mutantLayout = Object.fromEntries(mutantToken.storageLayout.storage.map((entry) => [entry.label, entry]));
assert(Number(mutantLayout._frozen.slot) === 5, "mutant _frozen base slot drift");
assert(Number(mutantLayout._restricted.slot) === 6, "mutant _restricted base slot drift");

const fixture = JSON.parse(text(fixturePath));
const deployment = fixture.deployments.find((entry) => entry.label === "TrustToken");
assert(deployment, "TrustToken resolved-runtime fixture is missing");
const encodedImmutables = new Map(
  deployment.immutablePatch.declarations.map((entry) => [String(entry.astId), entry.encodedWord.slice(2)]),
);
const mutantTemplateHex = mutantToken.evm.deployedBytecode.object;
assert(/^[0-9a-f]+$/.test(mutantTemplateHex), "mutant compiler runtime template is malformed");
const reconstructedRuntime = Buffer.from(mutantTemplateHex, "hex");
const immutableReferences = mutantToken.evm.deployedBytecode.immutableReferences ?? {};
assert(Object.keys(immutableReferences).length === encodedImmutables.size, "mutant immutable reference count drift");
for (const [astId, locations] of Object.entries(immutableReferences)) {
  const word = Buffer.from(encodedImmutables.get(astId) ?? "", "hex");
  assert(word.length === 32, `mutant immutable identity drift: ${astId}`);
  for (const location of locations) {
    assert(location.length === 32, `mutant immutable width drift: ${astId}`);
    assert(location.start + location.length <= reconstructedRuntime.length, `mutant immutable range drift: ${astId}`);
    assert(
      reconstructedRuntime.subarray(location.start, location.start + location.length).every((byte) => byte === 0),
      `mutant immutable placeholder is nonzero: ${astId}`,
    );
    word.copy(reconstructedRuntime, location.start);
  }
}
assert(reconstructedRuntime.equals(mutantRuntimeBytes), "resolved mutant runtime does not match compiler output plus immutable patch");
assert(sha256(reconstructedRuntime) === mutation.runtime.mutantResolvedSha256, "reconstructed mutant runtime identity drift");

const runtimeRule = /rule #trustTrustTokenRuntime\(\) => #parseByteStack\("(0x[0-9a-f]+)"\)/g;
const runtimeMatches = [...mutantBridge.matchAll(runtimeRule)];
assert(runtimeMatches.length === 1, "mutant runtime bridge rule is not unique");
assert(runtimeMatches[0][1] === mutantRuntimeText, "mutant runtime bridge does not bind the resolved mutant runtime");
assert(bridge.mutation.manifestPath === "evidence/end-to-end-refinement/row-bundles/state-04/negative/mutation.json", "bridge mutation path drift");
assert(bridge.mutation.manifestSha256 === sha256(bytes(mutationPath)), "bridge mutation manifest hash drift");
assert(bridge.compilerBinding.pinnedSolcVersion === lock.components.solc.version, "bridge pinned solc version drift");
assert(bridge.compilerBinding.pinnedSolcBinarySha256 === lock.components.solc.binarySha256, "bridge pinned solc binary drift");

const generatedTheory = text(generatedTheoryPath);
const closureTheory = text(closureTheoryPath);
const auditTheory = text(auditTheoryPath);
const bannedSourcePattern = /^\s*(sorry|oops|axiomatization|oracle)\b|\bby\s+eval\b|\bnative_decide\b|\bskip_proof\b/gm;
for (const [name, source] of [["generated", generatedTheory], ["closure", closureTheory], ["audit", auditTheory]]) {
  assert(!bannedSourcePattern.test(source), `banned Isabelle source form found: ${name}`);
  bannedSourcePattern.lastIndex = 0;
}
assert(generatedTheory.includes("generated_state04_overlay_storage_projection_is_exact"), "generated projection theorem missing");
assert(generatedTheory.includes("generated_state04_runtime_observation_is_exact"), "generated observation theorem missing");
assert(closureTheory.includes("theorem state04_overlay_pair_is_retrieved_without_loss:"), "retrieve injectivity theorem missing");
assert(closureTheory.includes("theorem freeze_and_restriction_are_independent:"), "named closure theorem missing");
assert(closureTheory.includes("composite_overlay_has_no_foundation_projection"), "partial-foundation boundary missing");
assert(auditTheory.includes("Thm_Deps.all_oracles state04_roots"), "oracle audit missing");
const rowManifest = JSON.parse(text(rowManifestPath));
assert(rowManifest.obligationId === "STATE-04", "row manifest obligation drift");
assert(rowManifest.bridge.path === "formal/kevm/row-bundles/state-04/bridge/row-bridge.json", "row manifest bridge path drift");
assert(rowManifest.bridge.sha256 === sha256(bytes(bridgePath)), "row manifest bridge hash drift");
assert(rowManifest.proofSpec.path === "formal/kevm/row-bundles/state-04/positive/claim.k", "row manifest proof path drift");
assert(rowManifest.proofSpec.sha256 === sha256(bytes(positiveClaimPath)), "row manifest proof hash drift");
assert(rowManifest.theorem.name === "freeze_and_restriction_are_independent", "row manifest theorem name drift");
assert(rowManifest.theorem.sha256 === sha256(bytes(closureTheoryPath)), "row manifest theorem hash drift");
assert(rowManifest.proofAudit.sha256 === sha256(bytes(auditTheoryPath)), "row manifest proof audit hash drift");
for (const generated of rowManifest.generated) {
  assert(generated.sha256 === sha256(bytes(repoPath(generated.path))), `row manifest generated hash drift: ${generated.path}`);
}

console.log(JSON.stringify({
  schemaVersion: 1,
  obligationId: "STATE-04",
  status: "PASS_COMPILED_MUTANT_STATIC_PREPARATION_ONLY",
  positiveNegativeClaimByteIdentical: true,
  claimSha256: sha256(bytes(positiveClaimPath)),
  commonRunnerExecutedClaimSha256: sha256(Buffer.from(executedClaim, "utf8")),
  bridgeSha256: sha256(bytes(bridgePath)),
  mutationPlanSha256: sha256(bytes(mutationPlanPath)),
  mutationManifestSha256: sha256(bytes(mutationPath)),
  mutantCompilerInputSha256: sha256(mutantInputBytes),
  mutantCompilerOutputSha256: sha256(mutantOutputBytes),
  mutantRuntimeSha256: mutation.runtime.mutantResolvedSha256,
  mutantRuntimeBytes: mutation.runtime.mutantByteLength,
  mutantRuntimeBridgeSha256: sha256(Buffer.from(mutantBridge, "utf8")),
  mutantVerificationModuleSha256: sha256(mutantVerificationBytes),
  generatedTheorySha256: sha256(bytes(generatedTheoryPath)),
  closureTheorySha256: sha256(bytes(closureTheoryPath)),
  proofAuditTheorySha256: sha256(bytes(auditTheoryPath)),
  rowManifestSha256: sha256(bytes(rowManifestPath)),
  canonicalCompilerOutputSha256: sha256(compilerOutputBytes),
  sharedBal06Primitives: 8,
  rowSpecificPrimitives: 4,
  notEvaluatedByThisStaticVerifier: [
    "K parse/preflight evidence",
    "positive theorem-grade KEVM",
    "negative terminal semantic counterexample",
    "repository-owned independent replay",
    "coordinator registry and ledger binding"
  ],
  caveat: "This static verifier does not evaluate KEVM, replay, or coordinator bindings; those gates and STATE-04 discharge remain open.",
}, null, 2));
