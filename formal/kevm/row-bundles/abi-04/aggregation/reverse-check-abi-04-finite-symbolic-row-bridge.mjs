#!/usr/bin/env node
// Static reverse check for the ABI-04 finite+symbolic row bridge.
// It validates source binding and theorem scope, not KEVM or Isabelle success.
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const aggregationDir = path.dirname(fileURLToPath(import.meta.url));
const rowDir = path.dirname(aggregationDir);
const repositoryRoot = path.resolve(rowDir, "../../../..");
const bridgePath = path.join(rowDir, "bridge", "finite-symbolic-row-bridge.json");
const matrixPath = path.join(rowDir, "case-matrix.json");
const aggregationContractPath = path.join(aggregationDir, "abi-04-aggregation-contract.json");
const symbolicContractPath = path.join(aggregationDir, "abi-04-symbolic-short-head-final-contract.json");
const symbolicIndexPath = path.join(aggregationDir, "abi-04-symbolic-short-head-final-claims-index.json");
const kBridgePath = path.join(rowDir, "generated", "abi-04-finite-symbolic-row-bridge.k");
const generatedTheoryPath = path.join(rowDir, "isabelle", "ABI_04_Finite_Symbolic_Generated.thy");
const skeletonTheoryPath = path.join(rowDir, "isabelle", "ABI_04_Short_Head_Partition_Closure_Skeleton.thy");
const rootPath = path.join(rowDir, "isabelle", "ROOT");

const sha256 = (value) => crypto.createHash("sha256").update(value).digest("hex");
const fileSha256 = (value) => sha256(fs.readFileSync(value));
const readJson = (value) => JSON.parse(fs.readFileSync(value, "utf8"));
const resolveBoundPath = (binding) => path.join(repositoryRoot, ...binding.path.split("/"));
const checkBinding = (binding, label) => {
  const resolved = resolveBoundPath(binding);
  assert.ok(fs.existsSync(resolved), `${label}: bound file exists`);
  assert.equal(binding.sha256, fileSha256(resolved), `${label}: bound hash`);
};

const bridge = readJson(bridgePath);
const matrix = readJson(matrixPath);
const aggregationContract = readJson(aggregationContractPath);
const symbolicContract = readJson(symbolicContractPath);
const symbolicIndex = readJson(symbolicIndexPath);
const kBridge = fs.readFileSync(kBridgePath, "utf8");
const generatedTheory = fs.readFileSync(generatedTheoryPath, "utf8");
const skeletonTheory = fs.readFileSync(skeletonTheoryPath, "utf8");
const root = fs.readFileSync(rootPath, "utf8");

assert.equal(bridge.kind, "ABI04_WORKER_LOCAL_FINITE_SYMBOLIC_ROW_BRIDGE");
assert.equal(bridge.classification, "GENERATED_STATIC_CLOSURE_SKELETON_NOT_PROOF_EVIDENCE");
assert.equal(bridge.obligationId, "ABI-04");
assert.equal(bridge.proofStatus, "NOT_RUN");
assert.equal(bridge.closureStatus, "OPEN");
assert.equal(bridge.eligibleForDischarge, false);
checkBinding(bridge.generator, "generator");
checkBinding(bridge.reverseCheck, "reverse check");
for (const [label, binding] of Object.entries(bridge.sourceBinding)) checkBinding(binding, label);
for (const [label, binding] of Object.entries(bridge.generated)) checkBinding(binding, label);

assert.equal(matrix.cases.length, 69);
assert.equal(matrix.endpoints.length, 6);
assert.deepEqual(matrix.endpoints.filter((endpoint) => endpoint.shape === "action").map((endpoint) => endpoint.id), bridge.endpointPartition.action.endpointIds);
assert.deepEqual(matrix.endpoints.filter((endpoint) => endpoint.shape === "reversal").map((endpoint) => endpoint.id), bridge.endpointPartition.reversal.endpointIds);
assert.equal(bridge.endpointPartition.action.count, 3);
assert.equal(bridge.endpointPartition.reversal.count, 3);
assert.deepEqual(bridge.endpointPartition.action.sentinelTailBytes, [0, 640]);
assert.deepEqual(bridge.endpointPartition.action.symbolicIntervals, [[1, 639], [641, 671]]);
assert.deepEqual(bridge.endpointPartition.reversal.sentinelTailBytes, [0, 256]);
assert.deepEqual(bridge.endpointPartition.reversal.symbolicIntervals, [[1, 255], [257, 287]]);
assert.equal(bridge.endpointPartition.action.symbolicMissingCardinalityPerEndpoint, 670);
assert.equal(bridge.endpointPartition.reversal.symbolicMissingCardinalityPerEndpoint, 286);
assert.equal(bridge.endpointPartition.exactSymbolicMissingLengthCardinality, 3 * 670 + 3 * 286);
assert.equal(bridge.endpointPartition.concreteSentinelLengthCardinality, 12);
assert.equal(bridge.endpointPartition.completeSelectorPrefixedShortLengthCardinality, 2880);
assert.equal(bridge.endpointPartition.arithmeticStatus, "NAMED_ISABELLE_SOURCE_PREPARED_BUILD_NOT_RUN");

assert.equal(symbolicIndex.claims.length, 12);
assert.equal(symbolicIndex.claims.reduce((sum, claim) => sum + claim.interval.cardinality, 0), 2868);
assert.equal(symbolicContract.sourceBinding.claimsIndex.claimsRootSha256, symbolicIndex.claimsRootSha256);
assert.equal(aggregationContract.caseSet.leafCount, 69);
assert.equal(aggregationContract.aggregationSemantics.replayCount, 162);
const expectedCombinedRoot = sha256(Buffer.from(JSON.stringify({
  finiteMatrixRootSha256: aggregationContract.caseSet.aggregationRootSha256,
  symbolicClaimsRootSha256: symbolicIndex.claimsRootSha256,
})));
assert.equal(bridge.aggregation.combinedRequirementRootSha256, expectedCombinedRoot);
assert.equal(bridge.aggregation.finiteMatrixRootSha256, aggregationContract.caseSet.aggregationRootSha256);
assert.equal(bridge.aggregation.symbolicClaimsRootSha256, symbolicIndex.claimsRootSha256);
assert.equal(bridge.aggregation.finiteClaims, 69);
assert.equal(bridge.aggregation.symbolicClaims, 12);
assert.equal(bridge.aggregation.canonicalPositiveReplays, 81);
assert.equal(bridge.aggregation.executableMutantNegativeReplays, 81);
assert.equal(bridge.aggregation.requiredReplayCount, 162);
assert.equal(bridge.aggregation.replayStatus, "NOT_RUN");

for (const [macro, value] of [
  ["#trustAbi04FiniteClaimCount", "69"],
  ["#trustAbi04SymbolicClaimCount", "12"],
  ["#trustAbi04RequiredReplayCount", "162"],
  ["#trustAbi04ActionEndpointCount", "3"],
  ["#trustAbi04ReversalEndpointCount", "3"],
  ["#trustAbi04SymbolicMissingLengthCardinality", "2868"],
  ["#trustAbi04CompleteShortLengthCardinality", "2880"],
  ["#trustAbi04EligibleForDischarge", "0"],
  ["#trustAbi04Abi03CoverageCredit", "0"],
]) {
  assert.equal(kBridge.split(`rule ${macro} => ${value}`).length - 1, 1, `${macro}: one exact K binding`);
}
assert.equal(kBridge.split(`rule #trustAbi04ProofStatus => "NOT_RUN"`).length - 1, 1);
assert.equal(kBridge.split(`rule #trustAbi04ClosureStatus => "OPEN"`).length - 1, 1);
assert.equal(kBridge.split(expectedCombinedRoot).length - 1, 1, "combined root in K bridge");

for (const fragment of [
  "definition abi_04_finite_claim_count :: nat where \"abi_04_finite_claim_count = 69\"",
  "definition abi_04_symbolic_claim_count :: nat where \"abi_04_symbolic_claim_count = 12\"",
  "definition abi_04_required_replay_count :: nat where \"abi_04_required_replay_count = 162\"",
  "definition abi_04_proof_status :: string where \"abi_04_proof_status = ''NOT_RUN''\"",
  "definition abi_04_closure_status :: string where \"abi_04_closure_status = ''OPEN''\"",
  "definition abi_04_eligible_for_discharge :: bool where \"abi_04_eligible_for_discharge = False\"",
  "definition abi_04_abi03_coverage_credit :: nat where \"abi_04_abi03_coverage_credit = 0\"",
]) assert.ok(generatedTheory.includes(fragment), `generated Isabelle binding: ${fragment}`);

assert.equal(bridge.isabelle.namedTheorem, "abi_04_short_head_partition_closure_skeleton");
assert.equal(bridge.isabelle.theoremScope, "FINITE_AND_INTERVAL_ARITHMETIC_ONLY");
assert.equal(bridge.isabelle.buildStatus, "NOT_RUN");
assert.equal(bridge.isabelle.backendReplayFactsImported, false);
assert.equal(bridge.isabelle.dischargeTheoremClaimed, false);
assert.ok(skeletonTheory.includes(`theorem ${bridge.isabelle.namedTheorem}:`), "named closure skeleton theorem");
const namedTheoremStart = skeletonTheory.indexOf(`theorem ${bridge.isabelle.namedTheorem}:`);
const gateTheoremStart = skeletonTheory.indexOf("theorem abi_04_closure_gate_remains_open:");
assert.ok(namedTheoremStart >= 0 && gateTheoremStart > namedTheoremStart, "named theorem source boundary");
const namedTheoremSource = skeletonTheory.slice(namedTheoremStart, gateTheoremStart);
for (const interval of ["{1..639}", "{641..671}", "{1..255}", "{257..287}", "{0..<672}", "{0..<288}"]) {
  assert.ok(skeletonTheory.includes(interval), `Isabelle interval ${interval}`);
}
for (const exactNamedFact of [
  "abi_04_action_short_head_upper = {0..<672}",
  "abi_04_reversal_short_head_upper = {0..<288}",
  "abi_04_action_short_head_sentinels ∩ abi_04_action_short_head_lower = {}",
  "abi_04_reversal_short_head_lower ∩ abi_04_reversal_short_head_upper = {}",
  "abi_04_symbolic_missing_length_cardinality",
  "abi_04_complete_short_length_cardinality",
]) assert.ok(namedTheoremSource.includes(exactNamedFact), `named theorem exact partition fact: ${exactNamedFact}`);
assert.ok(skeletonTheory.includes("abi_04_action_short_head_partition_disjoint"));
assert.ok(skeletonTheory.includes("abi_04_reversal_short_head_partition_disjoint"));
assert.ok(skeletonTheory.includes("theorem abi_04_closure_gate_remains_open:"));
assert.doesNotMatch(skeletonTheory, /\b(sorry|oops|axiomatization|oracle)\b/i);
assert.doesNotMatch(skeletonTheory, /status=PASS|backendComplete\s*=\s*true|eligible_for_discharge\s*=\s*True/);
assert.doesNotMatch(skeletonTheory, /<(open|close|union|inter|and|not)>/);
assert.ok(generatedTheory.includes("\\<open>") && generatedTheory.includes("\\<close>"), "escaped Isabelle text delimiters");
assert.doesNotMatch(generatedTheory, /(?<!\\)<(open|close)>/);
assert.ok(root.includes("ABI_04_Finite_Symbolic_Generated"));
assert.ok(root.includes("ABI_04_Short_Head_Partition_Closure_Skeleton"));

assert.equal(bridge.compositionBoundary.abi03CoverageCredit, 0);
assert.match(bridge.compositionBoundary.offsetAndLength, /no ABI-03 credit/);
assert.equal(bridge.coordinatorApplicationScope.sharedRegistryUpdated, false);
assert.equal(bridge.coordinatorApplicationScope.sharedLedgerUpdated, false);
assert.equal(bridge.coordinatorApplicationScope.sharedGeneratedRuntimeBridgeUpdated, false);
assert.equal(bridge.coordinatorApplicationScope.releaseManifestUpdated, false);
assert.ok(bridge.coordinatorApplicationScope.prohibitedInference.some((value) => /Timeout, cancellation, bounded enumeration/.test(value)));

console.log(JSON.stringify({
  status: "STATIC_FINITE_SYMBOLIC_ROW_BRIDGE_REVERSE_CHECK_ONLY",
  proofStatus: bridge.proofStatus,
  closureStatus: bridge.closureStatus,
  eligibleForDischarge: bridge.eligibleForDischarge,
  endpointPartition: { action: 3, reversal: 3 },
  finiteClaims: bridge.aggregation.finiteClaims,
  symbolicClaims: bridge.aggregation.symbolicClaims,
  replayRequirements: bridge.aggregation.requiredReplayCount,
  symbolicMissingLengthCardinality: bridge.endpointPartition.exactSymbolicMissingLengthCardinality,
  combinedRequirementRootSha256: bridge.aggregation.combinedRequirementRootSha256,
  isabelleBuildStatus: bridge.isabelle.buildStatus,
}, null, 2));
