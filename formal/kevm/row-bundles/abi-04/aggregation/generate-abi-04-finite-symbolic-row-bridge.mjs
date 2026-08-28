#!/usr/bin/env node
// Generates the worker-local ABI-04 finite+symbolic closure bridge.
// This is static evidence plumbing. It does not invoke KEVM or Isabelle.
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const aggregationDir = path.dirname(fileURLToPath(import.meta.url));
const rowDir = path.dirname(aggregationDir);
const repositoryRoot = path.resolve(rowDir, "../../../..");
const generatorPath = fileURLToPath(import.meta.url);
const reverseCheckPath = path.join(aggregationDir, "reverse-check-abi-04-finite-symbolic-row-bridge.mjs");
const matrixPath = path.join(rowDir, "case-matrix.json");
const legacyBridgePath = path.join(rowDir, "bridge", "row-bridge.json");
const legacyManifestPath = path.join(rowDir, "bridge", "row-manifest.json");
const aggregationContractPath = path.join(aggregationDir, "abi-04-aggregation-contract.json");
const symbolicContractPath = path.join(aggregationDir, "abi-04-symbolic-short-head-final-contract.json");
const symbolicIndexPath = path.join(aggregationDir, "abi-04-symbolic-short-head-final-claims-index.json");
const skeletonTheoryPath = path.join(rowDir, "isabelle", "ABI_04_Short_Head_Partition_Closure_Skeleton.thy");
const rootPath = path.join(rowDir, "isabelle", "ROOT");
const bridgePath = path.join(rowDir, "bridge", "finite-symbolic-row-bridge.json");
const kBridgePath = path.join(rowDir, "generated", "abi-04-finite-symbolic-row-bridge.k");
const generatedTheoryPath = path.join(rowDir, "isabelle", "ABI_04_Finite_Symbolic_Generated.thy");
const writeMode = process.argv.includes("--write");
const checkMode = process.argv.includes("--check");
const planMode = process.argv.includes("--plan");
assert.equal([writeMode, checkMode, planMode].filter(Boolean).length, 1, "use exactly one of --write, --check, or --plan");

const sha256 = (value) => crypto.createHash("sha256").update(value).digest("hex");
const fileSha256 = (value) => sha256(fs.readFileSync(value));
const readJson = (value) => JSON.parse(fs.readFileSync(value, "utf8"));
const posix = (value) => path.relative(repositoryRoot, value).split(path.sep).join("/");
const bindFile = (value) => ({ path: posix(value), sha256: fileSha256(value) });

const matrix = readJson(matrixPath);
const legacyBridge = readJson(legacyBridgePath);
const legacyManifest = readJson(legacyManifestPath);
const aggregationContract = readJson(aggregationContractPath);
const symbolicContract = readJson(symbolicContractPath);
const symbolicIndex = readJson(symbolicIndexPath);

assert.equal(matrix.obligationId, "ABI-04");
assert.equal(matrix.cases.length, 69);
assert.equal(matrix.endpoints.length, 6);
assert.equal(legacyManifest.proofStatus, "NOT_RUN");
assert.equal(aggregationContract.proofStatus, "NOT_RUN");
assert.equal(aggregationContract.closureStatus, "OPEN");
assert.equal(symbolicContract.classification, "STATIC_FINAL_SYMBOLIC_CONTRACT_NOT_DISCHARGE_EVIDENCE");
assert.equal(symbolicContract.proofStatus, "NOT_RUN");
assert.equal(symbolicIndex.kind, "ABI04_SYMBOLIC_SHORT_HEAD_FINAL_CLAIMS_INDEX");
assert.equal(symbolicIndex.claims.length, 12);

const actionEndpoints = matrix.endpoints.filter((endpoint) => endpoint.shape === "action");
const reversalEndpoints = matrix.endpoints.filter((endpoint) => endpoint.shape === "reversal");
assert.equal(actionEndpoints.length, 3);
assert.equal(reversalEndpoints.length, 3);
const symbolicMissingLengthCardinality = symbolicIndex.claims.reduce((sum, claim) => sum + claim.interval.cardinality, 0);
assert.equal(symbolicMissingLengthCardinality, 2868);
const expectedCombinedRoot = sha256(Buffer.from(JSON.stringify({
  finiteMatrixRootSha256: aggregationContract.caseSet.aggregationRootSha256,
  symbolicClaimsRootSha256: symbolicIndex.claimsRootSha256,
})));
assert.equal(aggregationContract.aggregationSemantics.combinedRequirementRootSha256, expectedCombinedRoot);
assert.equal(aggregationContract.aggregationSemantics.replayCount, 162);

const kBridge = `// GENERATED ABI-04 finite+symbolic row-local metadata bridge. DO NOT EDIT.
requires "edsl.md"

module TRUST-ABI-04-FINITE-SYMBOLIC-ROW-BRIDGE
    imports EDSL
    syntax String ::= "#trustAbi04FiniteMatrixRootSha256" [macro]
    rule #trustAbi04FiniteMatrixRootSha256 => "${aggregationContract.caseSet.aggregationRootSha256}"
    syntax String ::= "#trustAbi04SymbolicClaimsRootSha256" [macro]
    rule #trustAbi04SymbolicClaimsRootSha256 => "${symbolicIndex.claimsRootSha256}"
    syntax String ::= "#trustAbi04CombinedRequirementRootSha256" [macro]
    rule #trustAbi04CombinedRequirementRootSha256 => "${expectedCombinedRoot}"
    syntax Int ::= "#trustAbi04FiniteClaimCount" [macro]
    rule #trustAbi04FiniteClaimCount => 69
    syntax Int ::= "#trustAbi04SymbolicClaimCount" [macro]
    rule #trustAbi04SymbolicClaimCount => 12
    syntax Int ::= "#trustAbi04RequiredReplayCount" [macro]
    rule #trustAbi04RequiredReplayCount => 162
    syntax Int ::= "#trustAbi04ActionEndpointCount" [macro]
    rule #trustAbi04ActionEndpointCount => 3
    syntax Int ::= "#trustAbi04ReversalEndpointCount" [macro]
    rule #trustAbi04ReversalEndpointCount => 3
    syntax Int ::= "#trustAbi04SymbolicMissingLengthCardinality" [macro]
    rule #trustAbi04SymbolicMissingLengthCardinality => 2868
    syntax Int ::= "#trustAbi04CompleteShortLengthCardinality" [macro]
    rule #trustAbi04CompleteShortLengthCardinality => 2880
    syntax String ::= "#trustAbi04ProofStatus" [macro]
    rule #trustAbi04ProofStatus => "NOT_RUN"
    syntax String ::= "#trustAbi04ClosureStatus" [macro]
    rule #trustAbi04ClosureStatus => "OPEN"
    syntax Int ::= "#trustAbi04EligibleForDischarge" [macro]
    rule #trustAbi04EligibleForDischarge => 0
    syntax Int ::= "#trustAbi04Abi03CoverageCredit" [macro]
    rule #trustAbi04Abi03CoverageCredit => 0
endmodule
`;

const generatedTheory = `theory ABI_04_Finite_Symbolic_Generated
  imports ABI_04_Generated
begin

text \\<open>Generated worker-local ABI-04 aggregation metadata. Not proof evidence.\\<close>

definition abi_04_finite_matrix_root_sha256 :: string where
  "abi_04_finite_matrix_root_sha256 = ''${aggregationContract.caseSet.aggregationRootSha256}''"
definition abi_04_symbolic_claims_root_sha256 :: string where
  "abi_04_symbolic_claims_root_sha256 = ''${symbolicIndex.claimsRootSha256}''"
definition abi_04_combined_requirement_root_sha256 :: string where
  "abi_04_combined_requirement_root_sha256 = ''${expectedCombinedRoot}''"
definition abi_04_finite_claim_count :: nat where "abi_04_finite_claim_count = 69"
definition abi_04_symbolic_claim_count :: nat where "abi_04_symbolic_claim_count = 12"
definition abi_04_required_replay_count :: nat where "abi_04_required_replay_count = 162"
definition abi_04_action_endpoint_count :: nat where "abi_04_action_endpoint_count = 3"
definition abi_04_reversal_endpoint_count :: nat where "abi_04_reversal_endpoint_count = 3"
definition abi_04_symbolic_missing_length_cardinality :: nat where
  "abi_04_symbolic_missing_length_cardinality = 2868"
definition abi_04_concrete_sentinel_length_cardinality :: nat where
  "abi_04_concrete_sentinel_length_cardinality = 12"
definition abi_04_complete_short_length_cardinality :: nat where
  "abi_04_complete_short_length_cardinality = 2880"
definition abi_04_proof_status :: string where "abi_04_proof_status = ''NOT_RUN''"
definition abi_04_closure_status :: string where "abi_04_closure_status = ''OPEN''"
definition abi_04_eligible_for_discharge :: bool where "abi_04_eligible_for_discharge = False"
definition abi_04_abi03_coverage_credit :: nat where "abi_04_abi03_coverage_credit = 0"

end
`;

const bridge = {
  schemaVersion: 1,
  kind: "ABI04_WORKER_LOCAL_FINITE_SYMBOLIC_ROW_BRIDGE",
  classification: "GENERATED_STATIC_CLOSURE_SKELETON_NOT_PROOF_EVIDENCE",
  obligationId: "ABI-04",
  proofStatus: "NOT_RUN",
  closureStatus: "OPEN",
  eligibleForDischarge: false,
  generator: bindFile(generatorPath),
  reverseCheck: bindFile(reverseCheckPath),
  sourceBinding: {
    caseMatrix: { ...bindFile(matrixPath), rootSha256: matrix.caseMatrixRootSha256 },
    legacyFiniteBridge: { ...bindFile(legacyBridgePath), claimsRootSha256: legacyBridge.claimsRootSha256 },
    legacyFiniteManifest: bindFile(legacyManifestPath),
    aggregationContract: { ...bindFile(aggregationContractPath), finiteMatrixRootSha256: aggregationContract.caseSet.aggregationRootSha256, combinedRequirementRootSha256: expectedCombinedRoot },
    symbolicContract: { ...bindFile(symbolicContractPath), classification: symbolicContract.classification, proofStatus: symbolicContract.proofStatus },
    symbolicClaimsIndex: { ...bindFile(symbolicIndexPath), claimsRootSha256: symbolicIndex.claimsRootSha256 },
    closureSkeletonTheory: { ...bindFile(skeletonTheoryPath), theorem: "abi_04_short_head_partition_closure_skeleton" },
    isabelleRoot: bindFile(rootPath),
  },
  generated: {
    kMetadataBridge: { path: posix(kBridgePath), sha256: sha256(kBridge) },
    isabelleMetadataTheory: { path: posix(generatedTheoryPath), sha256: sha256(generatedTheory) },
  },
  endpointPartition: {
    action: { count: 3, endpointIds: actionEndpoints.map((endpoint) => endpoint.id), canonicalTailBytes: 672, sentinelTailBytes: [0, 640], symbolicIntervals: [[1, 639], [641, 671]], symbolicMissingCardinalityPerEndpoint: 670 },
    reversal: { count: 3, endpointIds: reversalEndpoints.map((endpoint) => endpoint.id), canonicalTailBytes: 288, sentinelTailBytes: [0, 256], symbolicIntervals: [[1, 255], [257, 287]], symbolicMissingCardinalityPerEndpoint: 286 },
    exactSymbolicMissingLengthCardinality: 2868,
    concreteSentinelLengthCardinality: 12,
    completeSelectorPrefixedShortLengthCardinality: 2880,
    arithmeticStatus: "NAMED_ISABELLE_SOURCE_PREPARED_BUILD_NOT_RUN",
  },
  aggregation: {
    operator: "CONJUNCTIVE_FINITE_MATRIX_AND_SYMBOLIC_SHORT_HEAD_FAMILIES",
    finiteClaims: 69,
    symbolicClaims: 12,
    canonicalPositiveReplays: 81,
    executableMutantNegativeReplays: 81,
    requiredReplayCount: 162,
    finiteMatrixRootSha256: aggregationContract.caseSet.aggregationRootSha256,
    symbolicClaimsRootSha256: symbolicIndex.claimsRootSha256,
    combinedRequirementRootSha256: expectedCombinedRoot,
    replayStatus: "NOT_RUN",
  },
  isabelle: {
    session: "ERC_TRUST_ABI_04_CANDIDATE",
    generatedTheory: "ABI_04_Finite_Symbolic_Generated",
    closureSkeletonTheory: "ABI_04_Short_Head_Partition_Closure_Skeleton",
    namedTheorem: "abi_04_short_head_partition_closure_skeleton",
    theoremScope: "FINITE_AND_INTERVAL_ARITHMETIC_ONLY",
    buildStatus: "NOT_RUN",
    backendReplayFactsImported: false,
    dischargeTheoremClaimed: false,
  },
  compositionBoundary: {
    shortHead: "For each endpoint, two concrete sentinels plus two symbolic intervals form an exact disjoint partition of selector-prefixed subcanonical tail lengths.",
    offsetAndLength: "The 6 offset and 6 length impostors remain ABI-04 finite leaves and grant no ABI-03 credit.",
    highBits: "The 45 high-bit and invalid-enum leaves remain endpoint-and-field-local finite obligations.",
    endpoints: "All six endpoint partitions remain conjunctive; equal selectors do not transfer runtime proof credit.",
    abi03CoverageCredit: 0,
  },
  coordinatorApplicationScope: {
    candidatePathOnly: true,
    sharedRegistryUpdated: false,
    sharedLedgerUpdated: false,
    sharedGeneratedRuntimeBridgeUpdated: false,
    releaseManifestUpdated: false,
    mayBindAfter: ["Isabelle session succeeds without oracle dependencies", "all 81 canonical positives are backend-complete PASS", "all 81 unchanged-claim mutant negatives have semantic terminal counterexamples", "all remaining ABI-04 coordinator gates pass"],
    prohibitedInference: ["Static reverse-check is proof", "The arithmetic theorem proves any KEVM replay", "ABI-04 offset/length leaves discharge ABI-03", "Timeout, cancellation, bounded enumeration, or exit code alone closes a replay"],
  },
};

const renderedBridge = JSON.stringify(bridge, null, 2) + "\n";
const outputs = [
  { path: bridgePath, content: renderedBridge },
  { path: kBridgePath, content: kBridge },
  { path: generatedTheoryPath, content: generatedTheory },
];
const plan = outputs.map((item) => {
  const actual = fs.existsSync(item.path) ? fs.readFileSync(item.path, "utf8").replaceAll("\r\n", "\n") : null;
  return { path: posix(item.path), status: actual === item.content ? "UNCHANGED" : actual === null ? "MISSING" : "CHANGED", actualSha256: actual === null ? null : sha256(actual), expectedSha256: sha256(item.content) };
});
if (checkMode) {
  assert.deepEqual(readJson(bridgePath), bridge, "finite+symbolic row bridge is stale");
  assert.equal(fs.readFileSync(kBridgePath, "utf8"), kBridge, "generated K metadata bridge is stale");
  assert.equal(fs.readFileSync(generatedTheoryPath, "utf8"), generatedTheory, "generated Isabelle metadata theory is stale");
  console.log(JSON.stringify({ status: "STATIC_FINITE_SYMBOLIC_ROW_BRIDGE_CURRENT", proofStatus: bridge.proofStatus, closureStatus: bridge.closureStatus, eligibleForDischarge: bridge.eligibleForDischarge, finiteClaims: 69, symbolicClaims: 12, replayRequirements: 162, combinedRequirementRootSha256: expectedCombinedRoot }, null, 2));
} else if (planMode) {
  console.log(JSON.stringify({ status: "PASS_GENERATION_PLAN", files: outputs.length, changes: plan, proofCredit: false, centralCredit: false }, null, 2));
} else {
  fs.writeFileSync(bridgePath, renderedBridge, "utf8");
  fs.writeFileSync(kBridgePath, kBridge, "utf8");
  fs.writeFileSync(generatedTheoryPath, generatedTheory, "utf8");
  console.log(JSON.stringify({ status: "GENERATED_STATIC_FINITE_SYMBOLIC_ROW_BRIDGE", proofStatus: bridge.proofStatus, closureStatus: bridge.closureStatus, eligibleForDischarge: bridge.eligibleForDischarge, output: posix(bridgePath) }, null, 2));
}
