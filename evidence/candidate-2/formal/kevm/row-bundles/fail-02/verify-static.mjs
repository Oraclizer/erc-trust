#!/usr/bin/env node
// Reverse-checks the FAIL-02 static bundle without invoking any heavy tool.
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { keccakHex, keccakUtf8, selector, selfTestKeccak } from "./lib/keccak.mjs";

selfTestKeccak();

const rowDir = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(rowDir, "../../../..");
const bridgePath = path.join(rowDir, "bridge", "row-bridge.json");
const manifestPath = path.join(rowDir, "bridge", "row-manifest.json");
const positiveClaimPath = path.join(rowDir, "positive", "claim.k");
const negativeClaimPath = path.join(rowDir, "negative", "claim.k");
const kBridgePath = path.join(rowDir, "generated", "fail-02-row-bridge.k");
const theoremPath = path.join(rowDir, "isabelle", "FAIL_02_Dependency_Denial_Is_Typed_Rejection.thy");
const rootPath = path.join(rowDir, "isabelle", "ROOT");
const obligationIndexPath = path.join(repositoryRoot, "evidence", "end-to-end-refinement", "obligation-evidence-index.json");
const sha256 = (value) => crypto.createHash("sha256").update(value).digest("hex");
const fileSha256 = (value) => sha256(fs.readFileSync(value));
const readJson = (value) => JSON.parse(fs.readFileSync(value, "utf8"));
const resolveBinding = (binding) => path.join(repositoryRoot, ...binding.path.split("/"));
const checkBinding = (binding, label) => {
  const resolved = resolveBinding(binding);
  assert.ok(fs.existsSync(resolved), `${label}: bound file exists`);
  assert.equal(binding.sha256, fileSha256(resolved), `${label}: bound hash`);
};
const strip0x = (value) => value.replace(/^0x/, "").toLowerCase();
const word = (value) => {
  const raw = typeof value === "bigint" ? value.toString(16) : strip0x(value);
  return raw.padStart(64, "0");
};

const bridge = readJson(bridgePath);
const manifest = readJson(manifestPath);
const obligationIndex = readJson(obligationIndexPath);
const positive = fs.readFileSync(positiveClaimPath, "utf8");
const negative = fs.readFileSync(negativeClaimPath, "utf8");
const kBridge = fs.readFileSync(kBridgePath, "utf8");
const theorem = fs.readFileSync(theoremPath, "utf8");
const root = fs.readFileSync(rootPath, "utf8");

assert.equal(bridge.kind, "FAIL02_ROW_LOCAL_COMMON_BUNDLE_BRIDGE");
assert.equal(bridge.classification, "PASS_OPEN_STATIC_NOT_PROOF_EVIDENCE");
assert.equal(bridge.obligationId, "FAIL-02");
assert.equal(bridge.requiredProperty, "dependency_denial_is_typed_rejection");
assert.equal(bridge.canonicalRequiredPropertyLiteral, "`dependency_denial_is_typed_rejection`");
assert.equal(bridge.staticStatus, "PASS_OPEN_STATIC");
assert.equal(bridge.proofStatus, "NOT_RUN");
assert.equal(bridge.closureStatus, "OPEN");
assert.equal(bridge.eligibleForDischarge, false);
assert.equal(manifest.classification, "PASS_OPEN_STATIC");
assert.equal(manifest.proofStatus, "NOT_RUN");
assert.equal(manifest.closureStatus, "OPEN");
assert.equal(manifest.eligibleForDischarge, false);
assert.equal(manifest.bridge.sha256, fileSha256(bridgePath));

checkBinding(bridge.generator, "generator");
checkBinding(bridge.staticVerifier, "static verifier");
checkBinding(bridge.helper, "Keccak helper");
checkBinding(bridge.readme, "README");
for (const [label, binding] of Object.entries(bridge.canonicalRegistry)) {
  if (label !== "canonicalDependencyLockPlaceholder" && binding?.path && binding?.sha256) {
    checkBinding(binding, `canonicalRegistry.${label}`);
  }
}
for (const [label, binding] of Object.entries(bridge.sourceIdentity)) checkBinding(binding, `sourceIdentity.${label}`);
for (const [label, binding] of Object.entries(bridge.compilerIdentity)) {
  if (binding?.path) checkBinding(binding, `compilerIdentity.${label}`);
}
for (const [label, binding] of Object.entries(bridge.runtimeIdentity)) {
  if (binding?.path) checkBinding(binding, `runtimeIdentity.${label}`);
}
checkBinding(bridge.mutationPlan, "mutation plan");
checkBinding(bridge.mutationPlan.patch, "mutation patch");
checkBinding(bridge.mutationPlan.builder, "mutant builder");
checkBinding(bridge.generated.kMetadataBridge, "generated K bridge");
checkBinding(bridge.isabelle.theory, "Isabelle theory");
checkBinding(bridge.isabelle.root, "Isabelle ROOT");

const fail02 = obligationIndex.obligations.find((row) => row.obligationId === "FAIL-02");
assert.equal(fail02.requiredProperty, bridge.canonicalRequiredPropertyLiteral);
assert.equal(fail02.statement.name, bridge.requiredProperty);
assert.equal(fail02.status.classification, "OPEN");
assert.equal(fail02.status.discharged, false);
assert.equal(fail02.result.proofStatus, "OPEN");
assert.equal(
  fail02.tcb[0].exactIdentityRef.sha256,
  "e4fcabd40c8b18e3900050a590b6b80c687d4d115f61bc12439af6099e83434e",
);
assert.equal(
  bridge.canonicalRegistry.actualDependencyLock.sha256,
  "3134e7692086170f86b6dd42e7ebd0256c188da8db8cbd17241c3d2c8d315196",
);
assert.notEqual(fail02.tcb[0].exactIdentityRef.sha256, bridge.canonicalRegistry.actualDependencyLock.sha256);
assert.equal(bridge.canonicalRegistry.bindingStatus, "OPEN_PLACEHOLDER_PENDING_BINDING");

assert.equal(positive, negative, "same claim bytes on positive and negative sides");
assert.equal(fileSha256(positiveClaimPath), bridge.positiveClaim.sha256);
assert.equal(fileSha256(negativeClaimPath), bridge.negativeClaim.sha256);
assert.equal(bridge.positiveClaim.sha256, bridge.negativeClaim.sha256);
assert.equal(bridge.negativeClaim.byteIdenticalToPositive, true);
assert.equal(positive.split("module TRUST-FAIL-02-DEPENDENCY-DENIAL-TYPED-REJECTION-SPEC").length - 1, 1);
assert.equal(positive.split("<statusCode> .StatusCode => EVMC_REVERT </statusCode>").length - 1, 1);
assert.equal(positive.split("<log> .List </log>").length - 1, 1);
assert.equal(positive.split("<nonce> 0 => 1 </nonce>").length - 1, 1);
assert.equal(positive.split("<timestamp> 1 </timestamp>").length - 1, 1);
assert.equal(positive.split("#trustTrustTokenRuntime()").length - 1, 1);

const calldataMatch = positive.match(/<data> #parseByteStack\("(0x[0-9a-f]+)"\) <\/data>/);
assert.ok(calldataMatch, "exact calldata literal");
const calldata = calldataMatch[1];
assert.equal((calldata.length - 2) / 2, 676);
assert.equal(calldata.slice(0, 10), selector(
  "executeRegulatoryAction((bytes32,bytes32,uint8,address,address,address,address,uint256,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,uint64,uint64,uint256,uint48,uint48))",
));
assert.equal(sha256(Buffer.from(strip0x(calldata), "hex")), bridge.positiveClaim.calldataSha256);
assert.equal(`0x${calldata.slice(10 + 64, 10 + 128)}`, bridge.positiveClaim.request.actionId);

const domain = keccakUtf8("ERC-TRUST/reference-v1");
const token = "0xe7f1725e7734ce288f8367e1bb143e90bb3f0512";
const requestHex = calldata.slice(10);
const zeroIdRequest = requestHex.slice(0, 64) + "0".repeat(64) + requestHex.slice(128);
const actionId = keccakHex(Buffer.from(word(domain) + word(token) + word(31337n) + zeroIdRequest, "hex"));
assert.equal(actionId, bridge.positiveClaim.request.actionId);
const commandHash = keccakHex(Buffer.from(word(domain) + word(token) + word(31337n) + requestHex, "hex"));
assert.equal(commandHash, bridge.positiveClaim.request.commandHash);

const outputMatch = positive.match(/<output> \.Bytes => #parseByteStack\("(0x[0-9a-f]+)"\) <\/output>/);
assert.ok(outputMatch, "typed rejection literal");
const output = outputMatch[1];
assert.equal((output.length - 2) / 2, 68);
assert.equal(output.slice(0, 10), selector("TrustRejected(bytes32,uint16)"));
assert.equal(`0x${output.slice(10, 74)}`, actionId);
assert.equal(output.slice(74), word(100n));
assert.equal(output, bridge.positiveClaim.typedError.outputHex);
assert.equal(sha256(Buffer.from(strip0x(output), "hex")), bridge.positiveClaim.typedError.outputSha256);

const compilerOutput = readJson(resolveBinding(bridge.compilerIdentity.nativeStandardJsonOutput));
const contract = compilerOutput.contracts?.["implementation/src/TrustToken.sol"]?.TrustToken;
const rejectedAbi = contract.abi.find((entry) => entry.type === "error" && entry.name === "TrustRejected");
const operationalAbi = contract.abi.find((entry) => entry.type === "error" && entry.name === "TrustOperationalFailure");
assert.deepEqual(rejectedAbi.inputs.map((input) => input.type), ["bytes32", "uint16"]);
assert.deepEqual(operationalAbi.inputs.map((input) => input.type), ["bytes32", "uint16", "bytes32"]);
const layout = Object.fromEntries(contract.storageLayout.storage.map((entry) => [entry.label, entry.slot]));
assert.deepEqual({ authorities: layout._authorities, bindings: layout._bindings, entered: layout._entered }, {
  authorities: "10", bindings: "23", entered: "29",
});

const dependencyCodeMatch = positive.match(/<acctID> 57005 <\/acctID>[\s\S]*?<code> #parseByteStack\("(0x[0-9a-f]+)"\) <\/code>/);
assert.ok(dependencyCodeMatch, "exact dependency runtime literal");
const dependencyRuntime = dependencyCodeMatch[1];
assert.equal(dependencyRuntime, bridge.dependencyWitness.runtimeHex);
assert.equal((dependencyRuntime.length - 2) / 2, 130);
assert.equal(keccakHex(Buffer.from(strip0x(dependencyRuntime), "hex")), bridge.dependencyWitness.codeIdKeccak256);
assert.equal(selector("configurationDigest()"), bridge.dependencyWitness.configurationSelector);
assert.equal(
  selector("assess(bytes32,uint8,address,address,uint256,bytes32,uint64)"),
  bridge.dependencyWitness.assessmentSelector,
);
assert.equal(bridge.dependencyWitness.assessmentOutcome, "REJECTED");
assert.equal(bridge.dependencyWitness.assessmentReasonDerivedByTrustToken, 100);

const authoritySlot = BigInt(keccakHex(Buffer.from(word(bridge.positiveClaim.request.authorityRef) + word(10n), "hex")));
const bindingSlot = BigInt(keccakHex(Buffer.from(word(0n) + word(23n), "hex")));
assert.equal(authoritySlot.toString(), bridge.positiveClaim.storageFixture.authoritySlot);
assert.equal(bindingSlot.toString(), bridge.positiveClaim.storageFixture.policyBindingSlot);
for (const key of [29n, authoritySlot, bindingSlot, bindingSlot + 1n, bindingSlot + 2n, bindingSlot + 3n, bindingSlot + 4n, bindingSlot + 5n]) {
  assert.equal(positive.split(`notBool ${key} in_keys(TOKEN_STORAGE)`).length - 1, 1, `fixed storage key ${key}`);
}
assert.equal(bridge.positiveClaim.storageFixture.fixedEntryCount, 8);

assert.equal(bridge.runtimeIdentity.resolvedRuntime.runtimeBytes, 24142);
assert.equal(bridge.runtimeIdentity.resolvedRuntime.runtimeBytesSha256, "3697706d4948c34fada47e049d32ad3e1866cf24ded6328f0c209d858614a86d");
const runtimeHex = fs.readFileSync(resolveBinding(bridge.runtimeIdentity.resolvedRuntime), "utf8").trim();
assert.equal(runtimeHex.split(strip0x(selector("TrustRejected(bytes32,uint16)"))).length - 1, 1);
assert.equal(bridge.compilerIdentity.version, "0.8.36+commit.8a079791");
assert.equal(bridge.compilerIdentity.binarySha256, "c8d35afdddc3cd2743ee88b8f25e0fecd16e2bdd5f2120f37e52cd9cc45ae0e6");
assert.equal(bridge.compilerIdentity.settingsSha256, "35c8223126038db5084bc48704b464ede69ba1648976d8c8d40582c7182d8e0b");
assert.equal(bridge.compilerIdentity.mutantCompileStatus, "NOT_RUN");

const patch = fs.readFileSync(resolveBinding(bridge.mutationPlan.patch), "utf8");
assert.equal(patch.split("revert TrustOperationalFailure(commandId, reason, dependency);").length - 1, 2);
assert.match(patch, /_requireApplicable/);
const plan = readJson(resolveBinding(bridge.mutationPlan));
assert.equal(plan.status, "NOT_RUN");
assert.equal(plan.compilerRecipe.compileStatus, "NOT_RUN");
assert.equal(plan.compilerRecipe.compilerOutput, null);
assert.equal(plan.compilerRecipe.resolvedRuntime, null);
assert.equal(plan.semanticDistinction.canonical.outputHex, output);
assert.equal(plan.semanticDistinction.mutant.outputHex, bridge.negativeClaim.expectedMutantObservation.outputHex);
const builder = fs.readFileSync(resolveBinding(bridge.mutationPlan.builder), "utf8");
assert.equal(builder.split("misclassify dependency denial as operational failure").length - 1, 1);
assert.match(builder, /resolvePinnedSolc/);
assert.match(builder, /--standard-json/);
const canonicalInput = readJson(resolveBinding(bridge.compilerIdentity.nativeStandardJsonInput));
assert.equal(canonicalInput.sources["implementation/src/TrustToken.sol"].content.split(plan.uniqueAnchor).length - 1, 1);
assert.ok(!fs.existsSync(path.join(rowDir, "bridge", "mutant-compiler")), "mutant compiler output absent");
assert.ok(!fs.existsSync(path.join(rowDir, "mutation", "mutant-TrustToken.sol")), "mutant source output absent");

for (const [macro, expected] of [
  ["#trustFail02ActionSelector", BigInt(selector("executeRegulatoryAction((bytes32,bytes32,uint8,address,address,address,address,uint256,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,uint64,uint64,uint256,uint48,uint48))")).toString()],
  ["#trustFail02RejectedSelector", BigInt(selector("TrustRejected(bytes32,uint16)")).toString()],
  ["#trustFail02OperationalSelector", BigInt(selector("TrustOperationalFailure(bytes32,uint16,bytes32)")).toString()],
  ["#trustFail02CalldataBytes", "676"],
  ["#trustFail02TypedErrorBytes", "68"],
  ["#trustFail02EligibleForDischarge", "0"],
]) assert.equal(kBridge.split(`rule ${macro} => ${expected}`).length - 1, 1, `${macro}: K binding`);
assert.ok(kBridge.includes(`rule #trustFail02ClaimSha256 => "${bridge.positiveClaim.sha256}"`));
assert.ok(kBridge.includes(`rule #trustFail02DependencyCodeId => "${bridge.dependencyWitness.codeIdKeccak256}"`));
assert.ok(kBridge.includes(`rule #trustFail02ProofStatus => "NOT_RUN"`));
assert.ok(kBridge.includes(`rule #trustFail02ClosureStatus => "OPEN"`));

assert.equal(bridge.isabelle.namedTheorem, "fail_02_dependency_denial_is_typed_rejection");
assert.equal(bridge.isabelle.buildStatus, "NOT_RUN");
assert.equal(bridge.isabelle.oracleAuditStatus, "NOT_RUN");
assert.ok(theorem.includes(`theorem ${bridge.isabelle.namedTheorem}:`));
assert.ok(theorem.includes("evm_bytes_selector payload = Some trust_rejected_selector"));
assert.ok(theorem.includes("typed_failure_payload payload"));
assert.ok(theorem.includes("runtime_rejection_stutters"));
assert.ok(theorem.includes("theorem fail_02_static_gate_remains_open:"));
assert.doesNotMatch(theorem, /\b(sorry|oops|axiomatization|oracle)\b/i);
assert.doesNotMatch(theorem, /status=PASS|eligible_for_discharge = True/);
assert.ok(root.includes("session ERC_TRUST_FAIL_02_SKELETON = ERC_TRUST +"));

assert.match(bridge.distinction.fail02, /dependency STATICCALL/);
assert.match(bridge.distinction.fail01, /Invalid domain/);
assert.match(bridge.distinction.fail05, /Unknown selector/);
assert.equal(bridge.distinction.noCreditTransfer, true);
assert.equal(bridge.residualScope.nativeExactRuntimeWitnessOnly, true);
assert.equal(bridge.residualScope.erc3643ProfileSubjectStillOpen, true);
assert.equal(bridge.residualScope.universalAllDependencyDenialsStillOpen, true);
assert.equal(bridge.coordinatorScope.sharedRegistryUpdated, false);
assert.equal(bridge.coordinatorScope.sharedLedgerUpdated, false);
assert.equal(bridge.coordinatorScope.sharedGeneratedRuntimeBridgeUpdated, false);
assert.equal(bridge.coordinatorScope.sharedManifestUpdated, false);

console.log(JSON.stringify({
  status: "PASS_OPEN_STATIC",
  obligationId: bridge.obligationId,
  requiredProperty: bridge.requiredProperty,
  proofStatus: bridge.proofStatus,
  closureStatus: bridge.closureStatus,
  eligibleForDischarge: bridge.eligibleForDischarge,
  claimSha256: bridge.positiveClaim.sha256,
  runtimeBytesSha256: bridge.runtimeIdentity.resolvedRuntime.runtimeBytesSha256,
  dependencyCodeId: bridge.dependencyWitness.codeIdKeccak256,
  typedErrorSelector: bridge.positiveClaim.typedError.selector,
  canonicalLockBindingStatus: bridge.canonicalRegistry.bindingStatus,
  mutantCompileStatus: bridge.mutationPlan.compileStatus,
  isabelleBuildStatus: bridge.isabelle.buildStatus,
}, null, 2));
