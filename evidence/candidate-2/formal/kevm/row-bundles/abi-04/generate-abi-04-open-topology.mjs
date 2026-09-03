#!/usr/bin/env node
// Deterministically materializes the complete ABI-04 OPEN topology before any
// fresh proof. It creates exact-set placeholders only and grants credit 0.
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const rowDir = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(rowDir, "../../../..");
const generatorPath = fileURLToPath(import.meta.url);
const reverseCheckPath = path.join(rowDir, "reverse-check-abi-04-open-topology.mjs");
const evidenceDir = path.join(repositoryRoot, "evidence", "end-to-end-refinement", "row-bundles", "abi-04");
const mode = process.argv.includes("--write") ? "write" : process.argv.includes("--check") ? "check" : process.argv.includes("--plan") ? "plan" : null;
assert.ok(mode, "use exactly one of --write, --check, or --plan");
assert.equal(["--write", "--check", "--plan"].filter((value) => process.argv.includes(value)).length, 1);

const sha256 = (value) => crypto.createHash("sha256").update(value).digest("hex");
const fileSha256 = (value) => sha256(fs.readFileSync(value));
const readJson = (value) => JSON.parse(fs.readFileSync(value, "utf8"));
const posix = (value) => path.relative(repositoryRoot, value).split(path.sep).join("/");
const bind = (value, extra = {}) => ({ path: posix(value), sha256: fileSha256(value), ...extra });
const render = (value) => `${JSON.stringify(value, null, 2)}\n`;
const fullRowDir = path.join(rowDir, "full-row-v1");
const fullRowGeneratorPath = path.join(fullRowDir, "generate-abi-04-full-row-orchestration-v1.mjs");
const fullRowIndexPath = path.join(fullRowDir, "full-row-replay-index-v1.json");
const fullRowContractPath = path.join(fullRowDir, "full-row-wave-contract-v1.json");
assert.ok(fs.existsSync(fullRowGeneratorPath), `missing full-row generator: ${fullRowGeneratorPath}`);
const fullRowGeneration = spawnSync(process.execPath, [fullRowGeneratorPath, `--${mode}`], { cwd: repositoryRoot, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
assert.notEqual(fullRowGeneration.status, null, "full-row generator failed to start");
assert.equal(fullRowGeneration.status, 0, `full-row generator failed: ${fullRowGeneration.stderr || fullRowGeneration.stdout}`);
const fullRowGenerationResult = JSON.parse(fullRowGeneration.stdout);
const fullRowPlan = mode === "plan" ? fullRowGenerationResult.changes : [];

const nonReplayGates = [
  { gateId: "ABI04-NR-DEPENDENCY-DAG-COMPLETE", invariant: "Machine-generated transitive SHA-256 DAG covers row bridge/manifest, mutation manifests, replay indexes, expected graphs, binders, aggregate bridge, Isabelle inputs, independent reports, and central row gate." },
  { gateId: "ABI04-NR-DEPENDENCY-JS-PASS", invariant: "JavaScript independently recomputes every node hash and declared parent-to-child edge." },
  { gateId: "ABI04-NR-DEPENDENCY-PYTHON-PASS", invariant: "Independent Python independently recomputes every node hash and declared parent-to-child edge." },
  { gateId: "ABI04-NR-DEPENDENCY-VERDICT-AGREEMENT", invariant: "JS and Python node, edge, anomaly, invalidation, and closure-root verdicts are identical." },
  { gateId: "ABI04-NR-DEPENDENCY-ANOMALY-EMPTY", invariant: "Missing, unexpected, duplicate, and declared/actual mismatch sets are all empty." },
  { gateId: "ABI04-NR-EXACT-NODE-MANIFEST", invariant: "A machine-generated frozen manifest declares the complete scoped node path and SHA-256 exact set; extra allowed-extension files fail closed." },
  { gateId: "ABI04-NR-FROZEN-EDGE-HASHES", invariant: "Every required topology edge is frozen with independently recorded parent and child SHA-256 values; runtime actual-to-actual pseudo declarations are prohibited." },
  { gateId: "ABI04-NR-REACHABLE-DESCENDANTS-VALID", invariant: "Every descendant reachable from a drifted input is invalidated until deterministically regenerated and rebound." },
  { gateId: "ABI04-NR-DETERMINISTIC-DOUBLE-GENERATION", invariant: "Until action-level impact completeness is proven, the full static pipeline is generated twice and both output trees are byte-identical." },
  { gateId: "ABI04-NR-CLEAN-SECOND-CHECK", invariant: "The second deterministic generator --check is clean." },
  { gateId: "ABI04-NR-FRESH-ISOLATED-REPRODUCTION", invariant: "Two fresh isolated roots rebuild every generator-owned output from the frozen inputs and are byte-identical to each other and canonical." },
  { gateId: "ABI04-NR-FAIL-CLOSED-MUTATION-REGRESSION", invariant: "Unexpected-node and changed-parent mutations both force nonzero JS/Python verdicts and invalidate every reachable descendant." },
  { gateId: "ABI04-NR-TOOLCHAIN-PREFLIGHT", invariant: "Pinned POSIX Node, Python, Bash, KEVM, K, kore-rpc, definitions, and closure verifier pass one proof-free preflight before any heavy replay." },
  { gateId: "ABI04-NR-INPUT-SNAPSHOT-INTEGRITY", invariant: "Every replay binds immutable claim, launcher, contract, definitions, mutation manifest, expected graph, toolchain, and provenance snapshots." },
  { gateId: "ABI04-NR-PREPOST-CLOSURE-EQUALITY", invariant: "The full dependency closure root before and after every proof is identical; otherwise the run is calibration-only credit zero." },
  { gateId: "ABI04-NR-S1-GRAPH-CONTRACT-EXACT-12", invariant: "The v4 runner and static reverse checker bind the exact 12 frozen S1 expected-graph files and hashes." },
  { gateId: "ABI04-NR-162-REPLAY-EXACT-SET", invariant: "The accepted replay ledger equals the exact 162-record set, with no missing, unexpected, or duplicate IDs." },
  { gateId: "ABI04-NR-UNCHANGED-CLAIM-MUTANT-IDENTITY", invariant: "Each negative uses the byte-identical positive claim source against only the declared selector-to-success mutant." },
  { gateId: "ABI04-NR-AGGREGATE-REVERSE-CHECK", invariant: "A regenerated aggregate contract and bridge pass a fail-closed reverse check over the exact claim/replay set." },
  { gateId: "ABI04-NR-ISABELLE-EVIDENCE-BINDING", invariant: "A named Isabelle result binds the regenerated exact aggregate inputs; arithmetic-only partition closure is insufficient." },
  { gateId: "ABI04-NR-ISABELLE-ZERO-ORACLE", invariant: "The authoritative Isabelle build succeeds serially with zero oracle dependencies and no banned source forms." },
  { gateId: "ABI04-NR-INDEPENDENT-REPLAY", invariant: "A repository-owned independent replay verifies all 162 accepted records and all named non-replay gates." },
  { gateId: "ABI04-NR-MATRIX-BINDER", invariant: "An ABI-04-specific matrix binder binds 81 claims and 162 records; the common one-pair binder is prohibited." },
  { gateId: "ABI04-NR-CENTRAL-ROW-GATE", invariant: "The central ABI-04 gate compares exact replay and non-replay gate IDs, hashes, and verdicts before registry/ledger credit." },
  { gateId: "ABI04-NR-ABI03-CROSS-CREDIT-ZERO", invariant: "The 12 offset/length envelope overlaps grant ABI-03 credit zero and remain ABI-04-local leaves." },
  { gateId: "ABI04-NR-CENTRAL-REGISTRY-REVERSE-CHECK", invariant: "Post-bind registry, ledger, generated surfaces, and release manifest pass repository reverse checks with ABI-04 exactly once." },
];
const nonReplayGateIds = nonReplayGates.map((item) => item.gateId);
assert.equal(nonReplayGates.length, 26);
assert.equal(new Set(nonReplayGateIds).size, 26);
const canonicalPositiveAcceptance = {
  resultClass: "BACKEND_COMPLETE_PASS",
  processExitCode: 0,
  launcherExitCode: 0,
  backendComplete: true,
  graph: { terminal: 0, stuck: 0, vacuous: 0, pending: 0, bounded: 0, admitted: false },
  integrity: "PASS",
  survivorCount: 0,
};
const unchangedClaimMutantNegativeAcceptance = {
  resultClass: "SEMANTIC_TERMINAL_COUNTEREXAMPLE",
  processExitCode: 1,
  launcherExitCode: 1,
  backendError: false,
  graph: { terminal: 1, stuck: 0, vacuous: 0, pending: 0, bounded: 0, admitted: false },
  terminalWitness: { statusCode: "EVMC_SUCCESS", outputHex: "0x" },
  integrity: "PASS",
  survivorCount: 0,
};

const matrixPath = path.join(rowDir, "case-matrix.json");
const mutationPath = path.join(rowDir, "mutation", "mutation-manifest.json");
const rowManifestPath = path.join(rowDir, "bridge", "row-manifest.json");
const aggregateBridgePath = path.join(rowDir, "bridge", "finite-symbolic-row-bridge.json");
const symbolicIndexPath = path.join(rowDir, "aggregation", "abi-04-symbolic-short-head-final-claims-index.json");
const offsetIndexPath = path.join(rowDir, "dynamic-offset-v1", "claims-index-v1.json");
const runnerPath = path.join(rowDir, "dynamic-offset-v1", "run-dynamic-offset-leaf-v4.sh");
const runnerReversePath = path.join(rowDir, "dynamic-offset-v1", "reverse-check-dynamic-offset-leaf-v4.mjs");
const closurePolicyPath = path.join(rowDir, "anti-drift", "closure-policy.json");
const freezeVerifierPath = path.join(rowDir, "anti-drift", "verify-freeze-receipt.py");
const generatedTheoryPath = path.join(rowDir, "isabelle", "ABI_04_Finite_Symbolic_Generated.thy");
const skeletonTheoryPath = path.join(rowDir, "isabelle", "ABI_04_Short_Head_Partition_Closure_Skeleton.thy");
const isabelleRootPath = path.join(rowDir, "isabelle", "ROOT");
const ledgerPath = path.join(evidenceDir, "exact-replay-ledger.json");
const independentPath = path.join(evidenceDir, "independent-replay-report.json");
const isabelleReportPath = path.join(evidenceDir, "isabelle-closure-report.json");
const matrixBinderPath = path.join(rowDir, "bridge", "abi-04-matrix-binder.json");
const centralGatePath = path.join(rowDir, "central-row-gate.json");

for (const required of [matrixPath, mutationPath, rowManifestPath, aggregateBridgePath, symbolicIndexPath, offsetIndexPath, runnerPath, runnerReversePath, closurePolicyPath, freezeVerifierPath, generatedTheoryPath, skeletonTheoryPath, isabelleRootPath, fullRowIndexPath, fullRowContractPath]) {
  assert.ok(fs.existsSync(required), `missing topology input: ${required}`);
}
const matrix = readJson(matrixPath);
const mutation = readJson(mutationPath);
const symbolicIndex = readJson(symbolicIndexPath);
const offsetIndex = readJson(offsetIndexPath);
const closurePolicy = readJson(closurePolicyPath);
const fullRowIndex = readJson(fullRowIndexPath);
const fullRowContract = readJson(fullRowContractPath);
assert.equal(fullRowIndex.kind, "ABI04_FULL_ROW_REPLAY_INDEX_V1");
assert.equal(fullRowContract.kind, "ABI04_FULL_ROW_WAVE_CONTRACT_V1");
assert.equal(fullRowContract.replayIndex.sha256, fileSha256(fullRowIndexPath));
assert.deepEqual(fullRowContract.exactSet, fullRowIndex.exactSet);
assert.equal(fullRowIndex.records.length, 162);
assert.deepEqual(closurePolicy.exactSets.nonReplayGates.expectedIds, nonReplayGateIds);
assert.equal(matrix.cases.length, 69);
assert.equal(new Set(matrix.cases.map((item) => item.caseId)).size, 69);
assert.equal(symbolicIndex.claims.length, 12);
assert.equal(new Set(symbolicIndex.claims.map((item) => item.semanticClaimId)).size, 12);
assert.equal(offsetIndex.claims.length, 6);
const mutationRuntimeById = new Map(mutation.runtimes.map((item) => [item.id, item]));
const mutationBinding = (endpointId, selector, canonicalRuntimeBytesSha256) => {
  const runtimeId = endpointId.startsWith("profile-") ? "ERC3643TrustAdapter" : "TrustToken";
  const runtime = mutationRuntimeById.get(runtimeId);
  assert.ok(runtime, `${endpointId}: mutation runtime`);
  assert.equal(runtime.canonicalSha256, canonicalRuntimeBytesSha256, `${endpointId}: canonical runtime/mutation binding`);
  const patch = runtime.patches.find((item) => item.selector === selector);
  assert.ok(patch, `${endpointId}: exact selector mutation patch ${selector}`);
  return {
    mutationId: mutation.mutationId,
    mutationKind: mutation.mutationKind,
    runtimeId,
    selector,
    canonicalRuntimeBytesSha256: runtime.canonicalSha256,
    mutatedRuntimeBytesSha256: runtime.mutatedSha256,
    appendedSuccessStubHex: runtime.appendedSuccessStubHex,
    patch,
    requiredObservation: { statusCode: "EVMC_SUCCESS", outputHex: "0x", contradiction: "The unchanged claim requires EVMC_REVERT." },
  };
};

const pairFiles = [];
const pairBindings = [];
for (const claim of offsetIndex.claims) {
  const positiveGraphPath = path.join(rowDir, "dynamic-offset-v1", "expected-graphs", `${claim.endpointId}-canonical-positive-v1.json`);
  const negativeGraphPath = path.join(rowDir, "dynamic-offset-v1", "expected-graphs", `${claim.endpointId}-mutant-negative-v1.json`);
  const claimPath = path.join(repositoryRoot, ...claim.claim.path.split("/"));
  for (const required of [positiveGraphPath, negativeGraphPath, claimPath]) assert.ok(fs.existsSync(required), `${claim.claimId}: missing binder input ${required}`);
  const positiveGraph = readJson(positiveGraphPath);
  const negativeGraph = readJson(negativeGraphPath);
  const pairMutation = mutationBinding(claim.endpointId, claim.selector, claim.runtimeBytesSha256);
  assert.equal(positiveGraph.claimId, claim.claimId);
  assert.equal(positiveGraph.side, "canonical-positive");
  assert.equal(positiveGraph.processExitCode, 0);
  assert.equal(positiveGraph.graph.pending, 0);
  assert.equal(positiveGraph.graph.admitted, false);
  assert.equal(negativeGraph.claimId, claim.claimId);
  assert.equal(negativeGraph.side, "mutant-negative");
  assert.equal(negativeGraph.processExitCode, 1);
  assert.equal(negativeGraph.graph.pending, 0);
  assert.equal(negativeGraph.graph.admitted, false);
  const binderPath = path.join(rowDir, "dynamic-offset-v1", "authoritative-pairs", `${claim.endpointId}-v1.json`);
  const binder = {
    schemaVersion: 1,
    kind: "ABI04_DYNAMIC_OFFSET_AUTHORITATIVE_PAIR_BINDER",
    obligationId: "ABI-04",
    stage: "S1",
    endpointId: claim.endpointId,
    claimId: claim.claimId,
    classification: "PRE_PROOF_OPEN_BINDER_NOT_EVIDENCE",
    sourceBinding: {
      generator: bind(generatorPath),
      topologyReverseCheck: bind(reverseCheckPath),
      claim: bind(claimPath, { claimId: claim.claimId, module: claim.module }),
      claimsIndex: bind(offsetIndexPath, { claimsRootSha256: offsetIndex.claimsRootSha256 }),
      runner: bind(runnerPath),
      runnerReverseCheck: bind(runnerReversePath),
      closurePolicy: bind(closurePolicyPath),
      closureFreezeVerifier: bind(freezeVerifierPath),
      canonicalExpectedGraph: bind(positiveGraphPath, { expectedProcessExitCode: 0 }),
      mutantExpectedGraph: bind(negativeGraphPath, { expectedProcessExitCode: 1 }),
    },
    exactPair: {
      canonicalPositive: { replayId: `${claim.claimId}::canonical-positive`, expectedProcessExitCode: 0, freshOutputRoot: null, resultStatus: "NOT_RUN" },
      unchangedClaimMutantNegative: { replayId: `${claim.claimId}::unchanged-claim-mutant-negative`, claimSourceUnchanged: true, unchangedClaimSha256: claim.claim.sha256, mutation: pairMutation, expectedProcessExitCode: 1, freshOutputRoot: null, resultStatus: "NOT_RUN" },
    },
    acceptance: { exactGraphs: true, incomplete: 0, admitted: false, integrity: "REQUIRED_PASS", survivorCount: 0, jsPythonClosureAgreement: true },
    proofStatus: "NOT_RUN",
    closureStatus: "OPEN",
    authoritative: false,
    proofCredit: false,
    centralCredit: false,
  };
  const binderText = render(binder);
  pairFiles.push({ path: binderPath, content: binderText });
  pairBindings.push({ endpointId: claim.endpointId, path: posix(binderPath), sha256: sha256(binderText) });
}
assert.equal(pairFiles.length, 6);

const records = fullRowIndex.records.map((record) => ({
  replayId: record.replayId,
  semanticClaimId: record.semanticClaimId,
  executionClaimId: record.executionClaimId,
  category: record.category,
  family: record.category === "finite" ? "FINITE" : "SYMBOLIC",
  caseId: record.category === "finite" ? record.semanticClaimId : undefined,
  symbolicClaimId: record.category === "symbolic" ? record.semanticClaimId : undefined,
  endpointId: record.endpointId,
  side: record.side,
  executionSide: record.executionSide,
  sourceFamily: record.sourceFamily,
  refinement: record.refinement,
  claimSourceUnchanged: record.side === "unchanged-claim-mutant-negative" ? true : undefined,
  claim: record.claim,
  claimSourceSha256: record.claim.sha256,
  strippedClaimSha256: record.strippedClaimSha256,
  calldataSha256: record.calldataSha256,
  interval: record.interval,
  canonicalRuntimeBytesSha256: record.canonicalRuntimeBytesSha256,
  executedRuntimeBytesSha256: record.executedRuntimeBytesSha256,
  mutation: record.mutation,
  terminalWitnessContract: record.terminalWitnessContract,
  expectedProcessExitCode: record.expectedProcessExitCode,
  acceptanceContract: record.side === "canonical-positive" ? canonicalPositiveAcceptance : unchangedClaimMutantNegativeAcceptance,
  resultStatus: "NOT_RUN",
  resultArtifact: null,
  accepted: false,
}));
assert.equal(records.filter((item) => item.category === "finite").length, 138);
assert.equal(records.filter((item) => item.category === "symbolic").length, 24);
assert.equal(records.length, 162);
assert.equal(new Set(records.map((item) => item.replayId)).size, 162);
for (const semanticId of [...matrix.cases.map((item) => item.caseId), ...symbolicIndex.claims.map((item) => item.semanticClaimId)]) {
  const positive = records.find((item) => item.replayId === `${semanticId}::canonical-positive`);
  const negative = records.find((item) => item.replayId === `${semanticId}::unchanged-claim-mutant-negative`);
  assert.ok(positive && negative, `${semanticId}: exact positive/negative pair`);
  assert.deepEqual(negative.claim, positive.claim, `${semanticId}: unchanged claim descriptor`);
  assert.equal(negative.claimSourceSha256, positive.claimSourceSha256, `${semanticId}: unchanged claim hash`);
  assert.equal(negative.canonicalRuntimeBytesSha256, positive.canonicalRuntimeBytesSha256, `${semanticId}: common canonical runtime`);
  assert.equal(negative.mutation.canonicalRuntimeBytesSha256, positive.canonicalRuntimeBytesSha256, `${semanticId}: mutation canonical runtime`);
  assert.notEqual(negative.executedRuntimeBytesSha256, positive.executedRuntimeBytesSha256, `${semanticId}: executable semantic mutant differs`);
}
const ledger = {
  schemaVersion: 1,
  kind: "ABI04_EXACT_REPLAY_LEDGER",
  obligationId: "ABI-04",
  classification: "PRE_PROOF_EXACT_SET_SKELETON_NOT_EVIDENCE",
  sourceBinding: {
    generator: bind(generatorPath),
    reverseCheck: bind(reverseCheckPath),
    caseMatrix: bind(matrixPath, { rootSha256: matrix.caseMatrixRootSha256 }),
    symbolicClaimsIndex: bind(symbolicIndexPath, { claimsRootSha256: symbolicIndex.claimsRootSha256 }),
    mutationManifest: bind(mutationPath, { mutationId: mutation.mutationId }),
    fullRowReplayIndex: bind(fullRowIndexPath, { records: 162, importedS1Records: 12, newlyExecutedRecords: 150 }),
    fullRowWaveContract: bind(fullRowContractPath),
    authoritativePairBinders: pairBindings,
  },
  exactSet: { finiteClaims: 69, symbolicClaims: 12, claims: 81, replaySides: 2, records: 162, duplicateReplayIds: 0 },
  records,
  acceptedRecords: 0,
  incompleteRecords: 162,
  replayStatus: "NOT_RUN",
  proofCredit: false,
  centralCredit: false,
};
const ledgerText = render(ledger);

const semanticClaimBindings = records.filter((item) => item.side === "canonical-positive").map((item) => ({
  semanticClaimId: item.semanticClaimId,
  executionClaimId: item.executionClaimId,
  category: item.category,
  endpointId: item.endpointId,
  sourceFamily: item.sourceFamily,
  refinement: item.refinement,
  claim: item.claim,
  strippedClaimSha256: item.strippedClaimSha256,
  canonicalReplayId: `${item.semanticClaimId}::canonical-positive`,
  unchangedClaimMutantNegativeReplayId: `${item.semanticClaimId}::unchanged-claim-mutant-negative`,
}));
assert.equal(semanticClaimBindings.length, 81);
assert.equal(new Set(semanticClaimBindings.map((item) => item.semanticClaimId)).size, 81);
const matrixBinder = {
  schemaVersion: 1,
  kind: "ABI04_MATRIX_EXACT_SET_BINDER",
  obligationId: "ABI-04",
  classification: "PRE_PROOF_OPEN_MATRIX_BINDER_NOT_EVIDENCE",
  sourceBinding: {
    generator: bind(generatorPath),
    reverseCheck: bind(reverseCheckPath),
    rowManifest: bind(rowManifestPath),
    finiteSymbolicBridge: bind(aggregateBridgePath),
    mutationManifest: bind(mutationPath, { mutationId: mutation.mutationId }),
    fullRowReplayIndex: bind(fullRowIndexPath, { records: 162, importedS1Records: 12, newlyExecutedRecords: 150 }),
    fullRowWaveContract: bind(fullRowContractPath),
    exactReplayLedger: { path: posix(ledgerPath), sha256: sha256(ledgerText), records: 162 },
  },
  exactSet: {
    finiteClaims: 69,
    symbolicClaims: 12,
    semanticClaims: 81,
    replayRecords: 162,
    duplicateSemanticClaimIds: 0,
    duplicateReplayIds: 0,
    semanticClaimIdsSha256: sha256(Buffer.from(JSON.stringify(semanticClaimBindings.map((item) => item.semanticClaimId)))),
    replayIdsSha256: sha256(Buffer.from(JSON.stringify(records.map((item) => item.replayId)))),
  },
  semanticClaimBindings,
  replayRecordIds: records.map((item) => item.replayId),
  unchangedClaimMutantRequired: true,
  singlePairFallbackAllowed: false,
  bindingStatus: "OPEN",
  proofStatus: "NOT_RUN",
  eligibleForDischarge: false,
  proofCredit: false,
  centralCredit: false,
};
const matrixBinderText = render(matrixBinder);

const independent = {
  schemaVersion: 1,
  kind: "ABI04_INDEPENDENT_REPLAY_REPORT",
  obligationId: "ABI-04",
  classification: "PRE_PROOF_OPEN_REPORT_NOT_EVIDENCE",
  sourceBinding: {
    generator: bind(generatorPath),
    reverseCheck: bind(reverseCheckPath),
    exactReplayLedger: { path: posix(ledgerPath), sha256: sha256(ledgerText), records: 162 },
    matrixExactSetBinder: { path: posix(matrixBinderPath), sha256: sha256(matrixBinderText), claims: 81, records: 162 },
    finiteSymbolicBridge: bind(aggregateBridgePath),
    fullRowReplayIndex: bind(fullRowIndexPath, { records: 162, importedS1Records: 12, newlyExecutedRecords: 150 }),
    fullRowWaveContract: bind(fullRowContractPath),
    closurePolicy: bind(closurePolicyPath),
  },
  exactReplaySetVerified: false,
  independentlyReplayedRecords: 0,
  expectedRecords: 162,
  expectedNonReplayGates: 26,
  verifiedNonReplayGates: 0,
  requiredNonReplayGateIds: nonReplayGateIds,
  jsPythonClosureAgreement: false,
  replayStatus: "NOT_RUN",
  proofCredit: false,
  centralCredit: false,
};
const independentText = render(independent);

const isabelleReport = {
  schemaVersion: 1,
  kind: "ABI04_ISABELLE_CLOSURE_REPORT",
  obligationId: "ABI-04",
  classification: "PRE_BUILD_OPEN_REPORT_NOT_EVIDENCE",
  sourceBinding: {
    generator: bind(generatorPath),
    reverseCheck: bind(reverseCheckPath),
    generatedTheory: bind(generatedTheoryPath),
    closureSkeletonTheory: bind(skeletonTheoryPath),
    sessionRoot: bind(isabelleRootPath),
    finiteSymbolicBridge: bind(aggregateBridgePath),
    fullRowReplayIndex: bind(fullRowIndexPath, { records: 162 }),
    fullRowWaveContract: bind(fullRowContractPath),
    exactReplayLedger: { path: posix(ledgerPath), sha256: sha256(ledgerText), records: 162 },
    matrixExactSetBinder: { path: posix(matrixBinderPath), sha256: sha256(matrixBinderText), claims: 81, records: 162 },
  },
  session: "ERC_TRUST_ABI_04_CANDIDATE",
  buildStatus: "NOT_RUN",
  admitted: false,
  oracleDependencies: "NOT_CHECKED",
  theoremCredit: false,
  centralCredit: false,
};
const isabelleReportText = render(isabelleReport);

const centralGate = {
  schemaVersion: 1,
  kind: "ABI04_CENTRAL_ROW_GATE",
  obligationId: "ABI-04",
  classification: "STRICT_ROW_DISCHARGE_GATE",
  sourceBinding: {
    generator: bind(generatorPath),
    reverseCheck: bind(reverseCheckPath),
    rowManifest: bind(rowManifestPath),
    finiteSymbolicBridge: bind(aggregateBridgePath),
    exactReplayLedger: { path: posix(ledgerPath), sha256: sha256(ledgerText), records: 162 },
    matrixExactSetBinder: { path: posix(matrixBinderPath), sha256: sha256(matrixBinderText), claims: 81, records: 162 },
    isabelleClosureReport: { path: posix(isabelleReportPath), sha256: sha256(isabelleReportText) },
    independentReplayReport: { path: posix(independentPath), sha256: sha256(independentText) },
    fullRowReplayIndex: bind(fullRowIndexPath, { records: 162, importedS1Records: 12, newlyExecutedRecords: 150 }),
    fullRowWaveContract: bind(fullRowContractPath),
    closurePolicy: bind(closurePolicyPath),
  },
  requiredExactSets: { finiteClaims: 69, symbolicClaims: 12, exactReplays: 162, matrixBinders: 1, authoritativePairs: 6, expectedGraphs: 12, nonReplayGates: 26 },
  requiredNonReplayGates: nonReplayGateIds,
  nonReplayGateRecords: nonReplayGates.map((item) => ({ ...item, status: "NOT_RUN", accepted: false, resultArtifact: null })),
  observed: { acceptedExactReplays: 0, incomplete: 162, admitted: false, integrity: "NOT_RUN", survivorCount: null, jsPythonClosureAgreement: false },
  rowStatus: "OPEN",
  eligibleForDischarge: false,
  proofCredit: false,
  centralCredit: false,
};

const files = [
  ...pairFiles,
  { path: ledgerPath, content: ledgerText },
  { path: matrixBinderPath, content: matrixBinderText },
  { path: independentPath, content: independentText },
  { path: isabelleReportPath, content: isabelleReportText },
  { path: centralGatePath, content: render(centralGate) },
];
assert.equal(files.length, 11);
const plan = [...fullRowPlan, ...files.map((item) => {
  const actual = fs.existsSync(item.path) ? fs.readFileSync(item.path, "utf8").replaceAll("\r\n", "\n") : null;
  return { path: posix(item.path), status: actual === item.content ? "UNCHANGED" : actual === null ? "MISSING" : "CHANGED", expectedSha256: sha256(item.content), actualSha256: actual === null ? null : sha256(actual) };
})];
if (mode === "write") {
  for (const item of files) {
    fs.mkdirSync(path.dirname(item.path), { recursive: true });
    fs.writeFileSync(item.path, item.content, "utf8");
  }
} else if (mode === "check") {
  assert.deepEqual(plan.filter((item) => item.status !== "UNCHANGED"), [], "OPEN topology descendants are stale");
}
console.log(JSON.stringify({
  status: mode === "write" ? "MATERIALIZED_OPEN_CREDIT_0" : mode === "check" ? "PASS_OPEN_CREDIT_0" : "PASS_OPEN_TOPOLOGY_PLAN",
  mode,
  files: files.length + 2,
  fullRowReplayIndex: { semanticClaims: 81, records: 162, importedS1Records: 12, newlyExecutedRecords: 150 },
  authoritativePairs: 6,
  expectedGraphs: 12,
  finiteClaims: 69,
  symbolicClaims: 12,
  exactReplayRecords: 162,
  matrixBinders: 1,
  nonReplayGates: 26,
  proofCredit: false,
  centralCredit: false,
  changes: mode === "plan" ? { changed: plan.filter((item) => item.status === "CHANGED").length, missing: plan.filter((item) => item.status === "MISSING").length, unchanged: plan.filter((item) => item.status === "UNCHANGED").length, files: plan } : undefined,
}, null, 2));
