#!/usr/bin/env node
// Deterministically resolves the ABI-04 aggregate from the 69 finite leaves and
// 12 symbolic short-head interval claims.
// It is evidence plumbing only: no KEVM/Isabelle process is invoked.
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
const aggregationDir = path.dirname(fileURLToPath(import.meta.url));
const rowDir = path.dirname(aggregationDir);
const repositoryRoot = path.resolve(rowDir, "../../../..");
const checkOnly = process.argv.includes("--check");
const writeMode = process.argv.includes("--write");
const planOnly = process.argv.includes("--plan");
assert.equal([checkOnly, writeMode, planOnly].filter(Boolean).length, 1, "use exactly one of --write, --check, or --plan");
const sha256 = (value) => crypto.createHash("sha256").update(value).digest("hex");
const fileSha256 = (value) => sha256(fs.readFileSync(value));
const readJson = (value) => JSON.parse(fs.readFileSync(value, "utf8"));
const posix = (value) => path.relative(repositoryRoot, value).split(path.sep).join("/");
const matrixPath = path.join(rowDir, "case-matrix.json");
const rowBridgePath = path.join(rowDir, "bridge", "row-bridge.json");
const rowManifestPath = path.join(rowDir, "bridge", "row-manifest.json");
const mutationPath = path.join(rowDir, "mutation", "mutation-manifest.json");
const symbolicContractPath = path.join(aggregationDir, "abi-04-symbolic-short-head-final-contract.json");
const symbolicIndexPath = path.join(aggregationDir, "abi-04-symbolic-short-head-final-claims-index.json");
const outputPath = path.join(aggregationDir, "abi-04-aggregation-contract.json");
const matrix = readJson(matrixPath);
const rowBridge = readJson(rowBridgePath);
const symbolicContract = readJson(symbolicContractPath);
const symbolicIndex = readJson(symbolicIndexPath);
assert.equal(matrix.obligationId, "ABI-04");
assert.equal(matrix.cases.length, 69);
assert.equal(new Set(matrix.cases.map((item) => item.caseId)).size, 69);
assert.equal(symbolicContract.kind, "ABI04_SYMBOLIC_SHORT_HEAD_FINAL_CONTRACT");
assert.equal(symbolicContract.classification, "STATIC_FINAL_SYMBOLIC_CONTRACT_NOT_DISCHARGE_EVIDENCE");
assert.equal(symbolicContract.proofStatus, "NOT_RUN");
assert.equal(symbolicIndex.kind, "ABI04_SYMBOLIC_SHORT_HEAD_FINAL_CLAIMS_INDEX");
assert.equal(symbolicIndex.claims.length, 12);
const coverageByClass = {
  short_head: { obligationFacet: "short_head_reverts_and_stutters", scope: "concrete_sentinel_only", universalConclusion: false },
  offset: { obligationFacet: "noncanonical_dynamic_offset_envelope_reverts_and_stutters", scope: "concrete_overlength_impostor_only", universalConclusion: false, overlap: ["ABI-03"] },
  length: { obligationFacet: "noncanonical_dynamic_length_envelope_reverts_and_stutters", scope: "concrete_overlength_impostor_only", universalConclusion: false, overlap: ["ABI-03"] },
  high_bits: { obligationFacet: "field_local_noncanonical_word_reverts_and_stutters", scope: "one_endpoint_one_field_one_malformed_value", universalConclusion: false },
};
const resolvedLeaves = matrix.cases.map((item) => ({
  caseId: item.caseId, endpointId: item.endpointId, claimSha256: item.claim.sha256,
  calldataSha256: item.calldataSha256, malformedClass: item.malformedClass,
  canonicalReplayId: `${item.caseId}::canonical-positive`, mutantReplayId: `${item.caseId}::unchanged-claim-mutant-negative`,
}));
const aggregationRootSha256 = sha256(Buffer.from(JSON.stringify(resolvedLeaves)));
const combinedRequirementRootSha256 = sha256(Buffer.from(JSON.stringify({
  finiteMatrixRootSha256: aggregationRootSha256,
  symbolicClaimsRootSha256: symbolicIndex.claimsRootSha256,
})));
const universalCoverageGaps = matrix.endpoints.map((endpoint) => {
  const witnessedShortLengths = matrix.cases.filter((item) => item.endpointId === endpoint.id && item.malformedClass === "short_head").map((item) => item.calldataBytes).sort((a, b) => a - b);
  const unprovedShortLengthRanges = endpoint.shape === "action" ? [{ fromInclusive: 5, toInclusive: 643 }, { fromInclusive: 645, toInclusive: 675 }] : [{ fromInclusive: 5, toInclusive: 259 }, { fromInclusive: 261, toInclusive: 291 }];
  const symbolicClaims = symbolicIndex.claims.filter((claim) => claim.endpointId === endpoint.id);
  const unprovedConcreteLengths = unprovedShortLengthRanges.reduce((n, r) => n + r.toInclusive - r.fromInclusive + 1, 0);
  assert.equal(symbolicClaims.length, 2, `${endpoint.id}: symbolic interval partition`);
  assert.equal(symbolicClaims.reduce((sum, claim) => sum + claim.interval.cardinality, 0), unprovedConcreteLengths, `${endpoint.id}: symbolic cardinality`);
  return {
    endpointId: endpoint.id,
    canonicalCalldataBytes: endpoint.canonicalCalldataBytes,
    witnessedShortLengths,
    formerlyMissingShortLengthRanges: unprovedShortLengthRanges,
    formerlyMissingConcreteLengths: unprovedConcreteLengths,
    claimDesignGapStatus: "CLOSED_BY_BOUND_SYMBOLIC_INTERVAL_CLAIMS",
    proofCoverageStatus: "NOT_RUN",
    symbolicClaimIds: symbolicClaims.map((claim) => claim.semanticClaimId),
    symbolicIntervals: symbolicClaims.map((claim) => claim.interval),
    requiredForUniversalClosure: "Backend-complete canonical PASS and same-claim executable-mutant semantic counterexample for both bound symbolic interval claims. Static claim design alone does not close ABI-04.",
  };
});
const contract = {
  schemaVersion: 1, kind: "ABI04_WORKER_LOCAL_MATRIX_AGGREGATION_CONTRACT", classification: "STATIC_AGGREGATION_CONTRACT_NOT_PROOF_EVIDENCE", obligationId: "ABI-04", requiredProperty: matrix.requiredProperty, proofStatus: "NOT_RUN", closureStatus: "OPEN",
  nonClaims: ["This contract is not a PASS, DISCHARGED, or backend-complete result.", "Claim-design closure for the universal selector-prefixed short-head partition is not proof closure.", "The 69 concrete leaves alone do not imply universal malformed-calldata coverage.", "ABI-04 offset and length envelopes do not add independent ABI-03 trailing-calldata coverage.", "Bounded enumeration, timeout, or cancellation cannot satisfy a symbolic replay requirement."],
  sourceBinding: { caseMatrix: { path: posix(matrixPath), sha256: fileSha256(matrixPath), rootSha256: matrix.caseMatrixRootSha256 }, rowBridge: { path: posix(rowBridgePath), sha256: fileSha256(rowBridgePath) }, rowManifest: { path: posix(rowManifestPath), sha256: fileSha256(rowManifestPath) }, mutationManifest: { path: posix(mutationPath), sha256: fileSha256(mutationPath) }, claimsRootSha256: rowBridge.claimsRootSha256, symbolicShortHeadContract: { path: posix(symbolicContractPath), sha256: fileSha256(symbolicContractPath), classification: symbolicContract.classification, proofStatus: symbolicContract.proofStatus }, symbolicClaimsIndex: { path: posix(symbolicIndexPath), sha256: fileSha256(symbolicIndexPath), claimsRootSha256: symbolicIndex.claimsRootSha256 } },
  caseSet: { resolver: "generate-abi-04-aggregation.mjs resolves every case-matrix.json cases[] entry in array order", leafCount: resolvedLeaves.length, aggregationRootSha256, exactLeafBinding: ["caseId", "endpointId", "claim.path", "claim.sha256", "module", "calldataSha256", "expected", "endpoint runtimeBytesSha256", "selector", "malformedClass", "subtype", "fieldIndex", "fieldType", "fieldValueHex"], coverageByClass, canonicalPositive: { suffix: "::canonical-positive", requiredTerminalResult: "BACKEND_COMPLETE_PASS", prohibitedResults: ["TIMEOUT", "CANCELLED", "BACKEND_ERROR", "PENDING", "STUCK", "VACUOUS", "ADMITTED"] }, executableMutantNegative: { suffix: "::unchanged-claim-mutant-negative", unchangedClaimRequired: true, exactMutationBindingRequired: ["mutationId", "runtimeId", "selector", "canonicalRuntimeBytesSha256", "mutatedRuntimeBytesSha256", "appendedSuccessStubHex", "patch"], definition: "generated/mutant-runtime-verification.k", requiredTerminalResult: "SEMANTIC_COUNTEREXAMPLE", requiredObservation: "same unchanged positive claim reaches EVMC_SUCCESS at the retargeted selector stub, contradicting its EVMC_REVERT target", prohibitedResults: ["TIMEOUT", "CANCELLED", "BACKEND_ERROR", "PENDING", "STUCK", "VACUOUS", "ADMITTED", "PASS"] } },
  aggregationSemantics: { operator: "CONJUNCTIVE_FINITE_MATRIX_AND_SYMBOLIC_SHORT_HEAD_FAMILIES", finiteReplayCount: resolvedLeaves.length * 2, symbolicReplayCount: symbolicIndex.claims.length * 2, replayCount: resolvedLeaves.length * 2 + symbolicIndex.claims.length * 2, finiteMatrixRootSha256: aggregationRootSha256, symbolicClaimsRootSha256: symbolicIndex.claimsRootSha256, combinedRequirementRootSha256, successCondition: "Every finite and symbolic canonical-positive claim is backend-complete PASS and every identical executable-mutant negative has a semantic terminal counterexample. Any missing, duplicate, mismatched, or prohibited replay leaves the aggregate OPEN.", permittedConclusionIfSatisfied: "The six endpoint-bound selector-prefixed short-head partitions are universally proved, and all other explicitly enumerated ABI-04 matrix leaves have the specified bounded replay evidence.", forbiddenConclusion: "Universal malformed-ABI rejection beyond the stated partitions, an ABI-03 trailing-calldata result, or discharge before all non-replay ABI-04 gates are satisfied." },
  graphContract: { graphKind: "CONJUNCTIVE_EVIDENCE_DAG", rootNodeId: "ABI-04::finite-and-symbolic-aggregate", rootPrerequisites: ["matrix-source-binding", "symbolic-family-source-binding", "all-69-canonical-positive-replays", "all-69-unchanged-claim-mutant-negative-replays", "all-12-symbolic-canonical-positive-replays", "all-12-symbolic-unchanged-claim-mutant-negative-replays"], nodeInterface: { nodeId: "<caseId>::canonical-positive | <caseId>::unchanged-claim-mutant-negative | <symbolicClaimId>::canonical-positive | <symbolicClaimId>::unchanged-claim-mutant-negative", mutantNegativeMeaning: "The claim source and postcondition are byte-identical to the positive side; only the exact declared selector-to-success runtime patch differs.", mustBind: ["caseId or symbolicClaimId", "claim.path", "claim.sha256", "module", "concrete calldataSha256 or symbolic interval", "canonical runtime hash", "executed runtime hash", "exact mutation descriptor or null", "acceptance contract", "definition identity", "command line", "result artifact hash"], canonicalPositiveAcceptance: ["status=PASS", "backendComplete=true", "terminalBranches=0", "pendingLeaves=0", "stuckNodes=0", "vacuousNodes=0", "admitted=false", "integrity=PASS", "survivors=0"], mutantNegativeAcceptance: ["status=SEMANTIC_COUNTEREXAMPLE", "terminalWitness=true", "observedStatus=EVMC_SUCCESS", "observedOutputHex=0x", "pending/stuck/vacuous/bounded=0", "admitted=false", "integrity=PASS", "survivors=0", "no timeout/cancellation/backend error"], replayIsolation: "One process per (claim identity, side); force sequential; no booster; unique save/temp/log directory; do not reuse a proof cache as a result artifact." }, replayLedgerInterface: { requiredRecordKeys: ["replayId", "caseId or symbolicClaimId", "side", "claim", "claimSourceSha256", "calldataSha256 or symbolic interval", "canonicalRuntimeBytesSha256", "executedRuntimeBytesSha256", "mutation", "acceptanceContract", "definitionSha256", "command", "resultStatus", "resultArtifactPath", "resultArtifactSha256"], exactSetRule: "The ledger must contain exactly one accepted record for every required replayId and no replayId may stand in for another leaf or symbolic family." } },
  universalCoverageGaps,
  overlapBoundary: { abi03: { affectedCaseCount: matrix.cases.filter((item) => ["offset", "length"].includes(item.malformedClass)).length, caseIds: matrix.cases.filter((item) => ["offset", "length"].includes(item.malformedClass)).map((item) => item.caseId), rule: "These 12 dynamic-envelope impostors are ABI-04 metadata only. They must be marked overlapWith ABI-03 and must not increment ABI-03 coverage or satisfy an ABI-03 graph node." } },
};
const rendered = JSON.stringify(contract, null, 2) + "\n";
const actual = fs.existsSync(outputPath) ? fs.readFileSync(outputPath, "utf8").replaceAll("\r\n", "\n") : null;
if (writeMode) { fs.writeFileSync(outputPath, rendered, "utf8"); console.log(JSON.stringify({ status: "GENERATED_STATIC_CONTRACT", proofStatus: contract.proofStatus, aggregationRootSha256, output: posix(outputPath), leaves: resolvedLeaves.length }, null, 2)); }
else if (planOnly) { console.log(JSON.stringify({ status: "PASS_GENERATION_PLAN", output: posix(outputPath), change: actual === rendered ? "UNCHANGED" : actual === null ? "MISSING" : "CHANGED", expectedSha256: sha256(rendered), actualSha256: actual === null ? null : sha256(actual), proofCredit: false, centralCredit: false }, null, 2)); }
else { assert.deepEqual(readJson(outputPath), contract, "aggregation contract is stale; regenerate it"); console.log(JSON.stringify({ status: "STATIC_CONTRACT_CURRENT", proofStatus: contract.proofStatus, aggregationRootSha256, leaves: resolvedLeaves.length }, null, 2)); }
