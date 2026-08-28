#!/usr/bin/env node
// Reverse-checks the FAIL-01 static bundle without invoking any heavy tool.
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const rowDir = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(rowDir, "../../../..");
const bridgePath = path.join(rowDir, "bridge", "row-bridge.json");
const manifestPath = path.join(rowDir, "bridge", "row-manifest.json");
const positiveClaimPath = path.join(rowDir, "positive", "claim.k");
const negativeClaimPath = path.join(rowDir, "negative", "claim.k");
const kBridgePath = path.join(rowDir, "generated", "fail-01-row-bridge.k");
const theoremPath = path.join(rowDir, "isabelle", "FAIL_01_Semantic_Rejection_Reverts_And_Stutters.thy");
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

const bridge = readJson(bridgePath);
const manifest = readJson(manifestPath);
const obligationIndex = readJson(obligationIndexPath);
const positive = fs.readFileSync(positiveClaimPath, "utf8");
const negative = fs.readFileSync(negativeClaimPath, "utf8");
const kBridge = fs.readFileSync(kBridgePath, "utf8");
const theorem = fs.readFileSync(theoremPath, "utf8");
const root = fs.readFileSync(rootPath, "utf8");

assert.equal(bridge.kind, "FAIL01_ROW_LOCAL_COMMON_BUNDLE_BRIDGE");
assert.equal(bridge.classification, "PASS_OPEN_STATIC_NOT_PROOF_EVIDENCE");
assert.equal(bridge.obligationId, "FAIL-01");
assert.equal(bridge.requiredProperty, "semantic_rejection_reverts_and_stutters");
assert.equal(bridge.canonicalRequiredPropertyLiteral, "`semantic_rejection_reverts_and_stutters`");
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
for (const [label, binding] of Object.entries(bridge.canonicalRegistry)) if (binding?.path) checkBinding(binding, `canonicalRegistry.${label}`);
for (const [label, binding] of Object.entries(bridge.sourceIdentity)) checkBinding(binding, `sourceIdentity.${label}`);
for (const [label, binding] of Object.entries(bridge.compilerIdentity)) if (binding?.path) checkBinding(binding, `compilerIdentity.${label}`);
for (const [label, binding] of Object.entries(bridge.runtimeIdentity)) if (binding?.path) checkBinding(binding, `runtimeIdentity.${label}`);
checkBinding(bridge.mutationPlan, "mutation plan");
checkBinding(bridge.mutationPlan.patch, "mutation patch");
checkBinding(bridge.mutationPlan.builder, "mutant builder");
checkBinding(bridge.generated.kMetadataBridge, "generated K bridge");
checkBinding(bridge.isabelle.theory, "Isabelle theory");
checkBinding(bridge.isabelle.root, "Isabelle ROOT");

const fail01 = obligationIndex.obligations.find((row) => row.obligationId === "FAIL-01");
assert.equal(fail01.requiredProperty, bridge.canonicalRequiredPropertyLiteral);
assert.equal(fail01.statement.name, bridge.requiredProperty);
assert.equal(fail01.status.classification, "OPEN");
assert.equal(fail01.status.discharged, false);
assert.equal(fail01.result.proofStatus, "OPEN");

assert.equal(positive, negative, "same claim bytes on positive and negative sides");
assert.equal(fileSha256(positiveClaimPath), bridge.positiveClaim.sha256);
assert.equal(fileSha256(negativeClaimPath), bridge.negativeClaim.sha256);
assert.equal(bridge.positiveClaim.sha256, bridge.negativeClaim.sha256);
assert.equal(bridge.negativeClaim.byteIdenticalToPositive, true);
assert.equal(positive.split("module TRUST-FAIL-01-TYPED-DOMAIN-REJECTION-STUTTER-SPEC").length - 1, 1);
assert.equal(positive.split("<statusCode> .StatusCode => EVMC_REVERT </statusCode>").length - 1, 1);
assert.equal(positive.split("<log> .List </log>").length - 1, 1);
assert.equal(positive.split("<storage> (29 |-> 0) TOKEN_STORAGE:Map </storage>").length - 1, 1);
assert.equal(positive.split("<origStorage> (29 |-> 0) TOKEN_STORAGE </origStorage>").length - 1, 1);
assert.equal(positive.split("notBool 29 in_keys(TOKEN_STORAGE)").length - 1, 1);
assert.equal(positive.split("<nonce> 0 => 1 </nonce>").length - 1, 1);

const calldataMatch = positive.match(/<data> #parseByteStack\("(0x[0-9a-f]+)"\) <\/data>/);
assert.ok(calldataMatch, "exact calldata literal");
const calldata = calldataMatch[1];
assert.equal((calldata.length - 2) / 2, 676);
assert.equal(calldata.slice(0, 10), "0x9da23539");
assert.equal(calldata.slice(10), "00".repeat(672), "canonical zero tuple");
assert.equal(sha256(Buffer.from(calldata.slice(2), "hex")), bridge.positiveClaim.calldataSha256);

const outputMatch = positive.match(/<output> \.Bytes => #parseByteStack\("(0x[0-9a-f]+)"\) <\/output>/);
assert.ok(outputMatch, "typed error literal");
const output = outputMatch[1];
assert.equal((output.length - 2) / 2, 68);
assert.equal(output.slice(0, 10), "0xed623c13");
assert.equal(output.slice(10, 74), "00".repeat(32), "actionId zero");
assert.equal(output.slice(74), "00".repeat(31) + "01", "REASON_DOMAIN=1");
assert.equal(output, bridge.positiveClaim.typedError.outputHex);
assert.equal(sha256(Buffer.from(output.slice(2), "hex")), bridge.positiveClaim.typedError.outputSha256);
assert.equal(bridge.positiveClaim.typedError.canonicalAbiBound, true);
const compilerOutput = readJson(resolveBinding(bridge.compilerIdentity.nativeStandardJsonOutput));
const trustTokenAbi = compilerOutput.contracts?.["implementation/src/TrustToken.sol"]?.TrustToken?.abi;
const typedErrorAbi = trustTokenAbi?.find((entry) => entry.type === "error" && entry.name === "TrustInvalidCommand");
assert.deepEqual(typedErrorAbi?.inputs?.map((input) => input.type), ["bytes32", "uint16"]);

assert.equal(bridge.runtimeIdentity.resolvedRuntime.runtimeBytes, 24142);
assert.equal(bridge.runtimeIdentity.resolvedRuntime.runtimeBytesSha256, "3697706d4948c34fada47e049d32ad3e1866cf24ded6328f0c209d858614a86d");
const runtimeHex = fs.readFileSync(resolveBinding(bridge.runtimeIdentity.resolvedRuntime), "utf8").trim();
assert.equal(runtimeHex.split("ed623c13").length - 1, bridge.positiveClaim.typedError.runtimeSelectorOccurrences);
assert.equal(bridge.positiveClaim.typedError.runtimeSelectorOccurrences, 24);
assert.equal(bridge.compilerIdentity.version, "0.8.36+commit.8a079791");
assert.equal(bridge.compilerIdentity.binarySha256, "c8d35afdddc3cd2743ee88b8f25e0fecd16e2bdd5f2120f37e52cd9cc45ae0e6");
assert.equal(bridge.compilerIdentity.settingsSha256, "35c8223126038db5084bc48704b464ede69ba1648976d8c8d40582c7182d8e0b");
assert.equal(bridge.compilerIdentity.mutantCompileStatus, "NOT_RUN");

const patch = fs.readFileSync(resolveBinding(bridge.mutationPlan.patch), "utf8");
assert.equal(patch.split("if (request.domain != TrustTypes.DOMAIN) return bytes32(0);").length - 1, 1);
assert.match(patch, /executeRegulatoryAction/);
const builder = fs.readFileSync(resolveBinding(bridge.mutationPlan.builder), "utf8");
assert.equal(builder.split("if (request.domain != TrustTypes.DOMAIN) return bytes32(0);").length - 1, 1);
assert.match(builder, /resolvePinnedSolc/);
assert.match(builder, /--standard-json/);
const canonicalStandardInput = readJson(resolveBinding(bridge.compilerIdentity.nativeStandardJsonInput));
const canonicalTokenSource = canonicalStandardInput.sources?.["implementation/src/TrustToken.sol"]?.content;
const mutationAnchor = [
  "    function executeRegulatoryAction(TrustTypes.ActionRequest calldata request)",
  "        external",
  "        nonReentrant",
  "        returns (bytes32 receiptHash)",
  "    {",
  "        _requireCalldataLength(ACTION_CALLDATA_LENGTH);",
  "        bytes32 digest = _validateAndAuthorizeAction(request, msg.sender);",
].join("\n");
assert.equal(canonicalTokenSource.split(mutationAnchor).length - 1, 1, "unique mutant anchor in canonical compiler input");
assert.ok(!fs.existsSync(path.join(rowDir, "bridge", "mutant-compiler")), "mutant compiler output absent in static wave");
assert.ok(!fs.existsSync(path.join(rowDir, "mutation", "mutant-TrustToken.sol")), "mutant source output absent in static wave");

for (const [macro, expected] of [
  ["#trustFail01Selector", "2644653369"],
  ["#trustFail01TypedErrorSelector", "3982638099"],
  ["#trustFail01CalldataBytes", "676"],
  ["#trustFail01TypedErrorBytes", "68"],
  ["#trustFail01EligibleForDischarge", "0"],
]) assert.equal(kBridge.split(`rule ${macro} => ${expected}`).length - 1, 1, `${macro}: K binding`);
assert.ok(kBridge.includes(`rule #trustFail01ClaimSha256 => "${bridge.positiveClaim.sha256}"`));
assert.ok(kBridge.includes(`rule #trustFail01RuntimeSha256 => "${bridge.runtimeIdentity.resolvedRuntime.runtimeBytesSha256}"`));
assert.ok(kBridge.includes(`rule #trustFail01ProofStatus => "NOT_RUN"`));
assert.ok(kBridge.includes(`rule #trustFail01ClosureStatus => "OPEN"`));

assert.equal(bridge.isabelle.namedTheorem, "fail_01_semantic_rejection_reverts_and_stutters");
assert.equal(bridge.isabelle.buildStatus, "NOT_RUN");
assert.equal(bridge.isabelle.oracleAuditStatus, "NOT_RUN");
assert.ok(theorem.includes(`theorem ${bridge.isabelle.namedTheorem}:`));
assert.ok(theorem.includes("transaction_result execution = TRUST_Return_Rejection payload"));
assert.ok(theorem.includes("runtime_rejection_stutters"));
assert.ok(theorem.includes("theorem fail_01_static_gate_remains_open:"));
assert.doesNotMatch(theorem, /\b(sorry|oops|axiomatization|oracle)\b/i);
assert.doesNotMatch(theorem, /status=PASS|eligible_for_discharge = True/);
assert.ok(root.includes("session ERC_TRUST_FAIL_01_SKELETON = ERC_TRUST +"));

assert.match(bridge.distinctionFromFail05.fail01, /Known executeRegulatoryAction selector/);
assert.match(bridge.distinctionFromFail05.fail05, /Unknown 0xffffffff selector/);
assert.equal(bridge.distinctionFromFail05.noCreditTransfer, true);
assert.deepEqual(bridge.acceptance.prohibited, ["TIMEOUT", "CANCELLED", "DRY_RUN", "BOUNDED_EXECUTION", "BACKEND_ERROR", "SOLVER_UNKNOWN", "EXIT_CODE_ONLY", "MUTANT_COMPILE_FAILURE"]);
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
  typedErrorSelector: bridge.positiveClaim.typedError.selector,
  mutantCompileStatus: bridge.mutationPlan.compileStatus,
  isabelleBuildStatus: bridge.isabelle.buildStatus,
}, null, 2));
