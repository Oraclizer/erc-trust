#!/usr/bin/env node
// Independent static reverse check for the complete pre-proof ABI-04 OPEN
// topology. It executes no backend and grants no proof or central credit.
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const rowDir = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(rowDir, "../../../..");
const evidenceDir = path.join(repositoryRoot, "evidence", "end-to-end-refinement", "row-bundles", "abi-04");
const readJson = (value) => JSON.parse(fs.readFileSync(value, "utf8"));
const sha256 = (value) => crypto.createHash("sha256").update(value).digest("hex");
const fileSha256 = (value) => sha256(fs.readFileSync(value));
const resolveBound = (binding) => {
  assert.equal(path.isAbsolute(binding.path), false, "repository binding must be relative");
  const resolved = path.resolve(repositoryRoot, ...binding.path.split("/"));
  assert.ok(resolved.startsWith(`${repositoryRoot}${path.sep}`), `repository binding escapes root: ${binding.path}`);
  return resolved;
};
const checkBindings = (value, label = "sourceBinding") => {
  if (Array.isArray(value)) return value.forEach((item, index) => checkBindings(item, `${label}/${index}`));
  if (!value || typeof value !== "object") return;
  if (typeof value.path === "string" && typeof value.sha256 === "string" && /^[0-9a-f]{64}$/.test(value.sha256)) {
    assert.equal(path.isAbsolute(value.path), false, `${label}: repository-relative binding`);
    const target = resolveBound(value);
    assert.ok(fs.existsSync(target), `${label}: bound file exists`);
    assert.equal(fileSha256(target), value.sha256, `${label}: bound hash`);
  }
  for (const [key, child] of Object.entries(value)) checkBindings(child, `${label}/${key}`);
};

const expectedNonReplayGates = [
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
const expectedNonReplayGateIds = expectedNonReplayGates.map((item) => item.gateId);
assert.equal(expectedNonReplayGates.length, 26);
assert.equal(new Set(expectedNonReplayGateIds).size, 26);
const expectedPositiveAcceptance = {
  resultClass: "BACKEND_COMPLETE_PASS",
  processExitCode: 0,
  launcherExitCode: 0,
  backendComplete: true,
  graph: { terminal: 0, stuck: 0, vacuous: 0, pending: 0, bounded: 0, admitted: false },
  integrity: "PASS",
  survivorCount: 0,
};
const expectedNegativeAcceptance = {
  resultClass: "SEMANTIC_TERMINAL_COUNTEREXAMPLE",
  processExitCode: 1,
  launcherExitCode: 1,
  backendError: false,
  graph: { terminal: 1, stuck: 0, vacuous: 0, pending: 0, bounded: 0, admitted: false },
  terminalWitness: { statusCode: "EVMC_SUCCESS", outputHex: "0x" },
  integrity: "PASS",
  survivorCount: 0,
};

const matrix = readJson(path.join(rowDir, "case-matrix.json"));
const mutation = readJson(path.join(rowDir, "mutation", "mutation-manifest.json"));
const symbolicIndex = readJson(path.join(rowDir, "aggregation", "abi-04-symbolic-short-head-final-claims-index.json"));
const offsetIndex = readJson(path.join(rowDir, "dynamic-offset-v1", "claims-index-v1.json"));
const policy = readJson(path.join(rowDir, "anti-drift", "closure-policy.json"));
const mutationRuntimeById = new Map(mutation.runtimes.map((item) => [item.id, item]));
const exactMutation = (endpointId, selector, canonicalRuntimeBytesSha256) => {
  const runtimeId = endpointId.startsWith("profile-") ? "ERC3643TrustAdapter" : "TrustToken";
  const runtime = mutationRuntimeById.get(runtimeId);
  assert.ok(runtime, `${endpointId}: mutation runtime`);
  assert.equal(runtime.canonicalSha256, canonicalRuntimeBytesSha256, `${endpointId}: canonical runtime/mutation binding`);
  const patch = runtime.patches.find((item) => item.selector === selector);
  assert.ok(patch, `${endpointId}: exact mutation selector ${selector}`);
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
const binderDir = path.join(rowDir, "dynamic-offset-v1", "authoritative-pairs");
const expectedBinderNames = policy.exactSets.authoritativeBinders.expectedNames;
const actualBinderNames = fs.readdirSync(binderDir).filter((value) => value.endsWith(".json")).sort();
assert.deepEqual(actualBinderNames, [...expectedBinderNames].sort());
assert.equal(actualBinderNames.length, 6);

const binders = actualBinderNames.map((name) => readJson(path.join(binderDir, name)));
for (const binder of binders) {
  const claim = offsetIndex.claims.find((item) => item.claimId === binder.claimId);
  assert.ok(claim, `${binder.claimId}: exact indexed claim`);
  assert.equal(binder.kind, "ABI04_DYNAMIC_OFFSET_AUTHORITATIVE_PAIR_BINDER");
  assert.equal(binder.obligationId, "ABI-04");
  assert.equal(binder.stage, "S1");
  assert.equal(binder.endpointId, claim.endpointId);
  assert.equal(binder.classification, "PRE_PROOF_OPEN_BINDER_NOT_EVIDENCE");
  checkBindings(binder.sourceBinding, `${binder.claimId}/sourceBinding`);
  assert.equal(binder.sourceBinding.claim.sha256, claim.claim.sha256);
  assert.equal(binder.sourceBinding.claim.claimId, claim.claimId);
  assert.equal(binder.sourceBinding.claimsIndex.claimsRootSha256, offsetIndex.claimsRootSha256);
  assert.equal(binder.sourceBinding.topologyReverseCheck.sha256, fileSha256(path.join(rowDir, "reverse-check-abi-04-open-topology.mjs")));
  assert.equal(binder.sourceBinding.runnerReverseCheck.sha256, fileSha256(path.join(rowDir, "dynamic-offset-v1", "reverse-check-dynamic-offset-leaf-v4.mjs")));
  const positiveGraph = readJson(resolveBound(binder.sourceBinding.canonicalExpectedGraph));
  const negativeGraph = readJson(resolveBound(binder.sourceBinding.mutantExpectedGraph));
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
  assert.deepEqual(binder.exactPair.canonicalPositive, { replayId: `${claim.claimId}::canonical-positive`, expectedProcessExitCode: 0, freshOutputRoot: null, resultStatus: "NOT_RUN" });
  assert.deepEqual(binder.exactPair.unchangedClaimMutantNegative, { replayId: `${claim.claimId}::unchanged-claim-mutant-negative`, claimSourceUnchanged: true, unchangedClaimSha256: claim.claim.sha256, mutation: exactMutation(claim.endpointId, claim.selector, claim.runtimeBytesSha256), expectedProcessExitCode: 1, freshOutputRoot: null, resultStatus: "NOT_RUN" });
  assert.deepEqual(binder.acceptance, { exactGraphs: true, incomplete: 0, admitted: false, integrity: "REQUIRED_PASS", survivorCount: 0, jsPythonClosureAgreement: true });
  assert.equal(binder.proofStatus, "NOT_RUN");
  assert.equal(binder.closureStatus, "OPEN");
  assert.equal(binder.authoritative, false);
  assert.equal(binder.proofCredit, false);
  assert.equal(binder.centralCredit, false);
}

const ledgerPath = path.join(evidenceDir, "exact-replay-ledger.json");
const independentPath = path.join(evidenceDir, "independent-replay-report.json");
const isabelleReportPath = path.join(evidenceDir, "isabelle-closure-report.json");
const matrixBinderPath = path.join(rowDir, "bridge", "abi-04-matrix-binder.json");
const centralPath = path.join(rowDir, "central-row-gate.json");
const fullRowIndexPath = path.join(rowDir, "full-row-v1", "full-row-replay-index-v1.json");
const fullRowContractPath = path.join(rowDir, "full-row-v1", "full-row-wave-contract-v1.json");
const ledger = readJson(ledgerPath);
const matrixBinder = readJson(matrixBinderPath);
const independent = readJson(independentPath);
const isabelleReport = readJson(isabelleReportPath);
const central = readJson(centralPath);
const fullRowIndex = readJson(fullRowIndexPath);
const fullRowContract = readJson(fullRowContractPath);
assert.equal(fullRowIndex.kind, "ABI04_FULL_ROW_REPLAY_INDEX_V1");
assert.deepEqual(fullRowIndex.exactSet, { finiteClaims: 69, symbolicClaims: 12, semanticClaims: 81, replaySides: 2, records: 162, s1ImportedRecords: 12, newlyExecutedRecords: 150 });
assert.equal(fullRowIndex.records.length, 162);
assert.equal(new Set(fullRowIndex.records.map((item) => item.replayId)).size, 162);
assert.equal(fullRowIndex.records.filter((item) => item.sourceFamily === "DYNAMIC_OFFSET_V1_REFINEMENT").length, 12);
assert.equal(fullRowIndex.records.filter((item) => item.sourceFamily === "DYNAMIC_LENGTH_V1_REFINEMENT").length, 12);
assert.equal(fullRowContract.kind, "ABI04_FULL_ROW_WAVE_CONTRACT_V1");
assert.equal(fullRowContract.replayIndex.sha256, fileSha256(fullRowIndexPath));
assert.equal(fullRowContract.exactSet.records, 162);
assert.deepEqual(fullRowContract.exactSet, fullRowIndex.exactSet);
const expectedLedgerRecords = fullRowIndex.records.map((record) => ({
  replayId: record.replayId,
  semanticClaimId: record.semanticClaimId,
  executionClaimId: record.executionClaimId,
  category: record.category,
  family: record.category === "finite" ? "FINITE" : "SYMBOLIC",
  ...(record.category === "finite" ? { caseId: record.semanticClaimId } : { symbolicClaimId: record.semanticClaimId }),
  endpointId: record.endpointId,
  side: record.side,
  executionSide: record.executionSide,
  sourceFamily: record.sourceFamily,
  refinement: record.refinement,
  ...(record.side === "unchanged-claim-mutant-negative" ? { claimSourceUnchanged: true } : {}),
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
  acceptanceContract: record.side === "canonical-positive" ? expectedPositiveAcceptance : expectedNegativeAcceptance,
  resultStatus: "NOT_RUN",
  resultArtifact: null,
  accepted: false,
}));

assert.equal(ledger.kind, "ABI04_EXACT_REPLAY_LEDGER");
assert.equal(ledger.classification, "PRE_PROOF_EXACT_SET_SKELETON_NOT_EVIDENCE");
checkBindings(ledger.sourceBinding, "ledger/sourceBinding");
checkBindings(ledger.records, "ledger/records");
assert.deepEqual(ledger.exactSet, { finiteClaims: 69, symbolicClaims: 12, claims: 81, replaySides: 2, records: 162, duplicateReplayIds: 0 });
assert.equal(ledger.records.length, 162);
assert.deepEqual(ledger.records, expectedLedgerRecords, "ledger/full-row executable identity mismatch");
assert.equal(ledger.sourceBinding.fullRowReplayIndex.sha256, fileSha256(fullRowIndexPath));
assert.equal(ledger.sourceBinding.fullRowWaveContract.sha256, fileSha256(fullRowContractPath));
const semanticIds = [...matrix.cases.map((item) => item.caseId), ...symbolicIndex.claims.map((item) => item.semanticClaimId)];
const expectedReplayIdsOrdered = fullRowIndex.records.map((item) => item.replayId);
const expectedReplayIds = [...expectedReplayIdsOrdered].sort();
const actualReplayIds = ledger.records.map((item) => item.replayId).sort();
assert.deepEqual(actualReplayIds, expectedReplayIds);
assert.equal(new Set(actualReplayIds).size, 162);
for (const record of ledger.records) {
  assert.ok(["FINITE", "SYMBOLIC"].includes(record.family));
  assert.equal(record.category, record.family === "FINITE" ? "finite" : "symbolic");
  assert.ok(semanticIds.includes(record.semanticClaimId));
  const executable = fullRowIndex.records.find((item) => item.replayId === record.replayId);
  assert.ok(executable, `${record.replayId}: executable record`);
  assert.equal(record.executionClaimId, executable.executionClaimId);
  assert.equal(record.sourceFamily, executable.sourceFamily);
  assert.deepEqual(record.refinement, executable.refinement);
  assert.equal(record.strippedClaimSha256, executable.strippedClaimSha256);
  assert.ok(record.replayId.startsWith(`${record.semanticClaimId}::`));
  assert.ok(["canonical-positive", "unchanged-claim-mutant-negative"].includes(record.side));
  assert.equal(record.expectedProcessExitCode, record.side === "canonical-positive" ? 0 : 1);
  assert.deepEqual(record.acceptanceContract, record.side === "canonical-positive" ? expectedPositiveAcceptance : expectedNegativeAcceptance);
  if (record.side === "unchanged-claim-mutant-negative") assert.equal(record.claimSourceUnchanged, true);
  assert.equal(record.resultStatus, "NOT_RUN");
  assert.equal(record.resultArtifact, null);
  assert.equal(record.accepted, false);
}
for (const semanticId of semanticIds) {
  const positive = ledger.records.find((item) => item.replayId === `${semanticId}::canonical-positive`);
  const negative = ledger.records.find((item) => item.replayId === `${semanticId}::unchanged-claim-mutant-negative`);
  assert.ok(positive && negative, `${semanticId}: exact replay pair`);
  assert.deepEqual(negative.claim, positive.claim, `${semanticId}: byte-identical claim descriptor`);
  assert.equal(positive.claimSourceSha256, positive.claim.sha256, `${semanticId}: positive claim source hash`);
  assert.equal(negative.claimSourceSha256, positive.claimSourceSha256, `${semanticId}: unchanged negative claim source hash`);
  assert.equal(negative.canonicalRuntimeBytesSha256, positive.canonicalRuntimeBytesSha256, `${semanticId}: shared canonical runtime`);
  assert.equal(positive.executedRuntimeBytesSha256, positive.canonicalRuntimeBytesSha256, `${semanticId}: positive executes canonical runtime`);
  assert.equal(positive.mutation, null, `${semanticId}: positive has no mutation`);
  const sourceClaim = positive.family === "FINITE"
    ? matrix.cases.find((item) => item.caseId === semanticId)
    : symbolicIndex.claims.find((item) => item.semanticClaimId === semanticId);
  assert.ok(sourceClaim, `${semanticId}: source claim`);
  const endpoint = matrix.endpoints.find((item) => item.id === positive.endpointId);
  assert.ok(endpoint, `${semanticId}: endpoint`);
  const selector = positive.family === "FINITE" ? endpoint.selector : sourceClaim.selector;
  const expectedMutation = exactMutation(positive.endpointId, selector, positive.canonicalRuntimeBytesSha256);
  assert.deepEqual(negative.mutation, expectedMutation, `${semanticId}: exact selector-to-success mutation`);
  assert.equal(negative.executedRuntimeBytesSha256, expectedMutation.mutatedRuntimeBytesSha256, `${semanticId}: negative executes exact mutant runtime`);
  assert.notEqual(negative.executedRuntimeBytesSha256, positive.executedRuntimeBytesSha256, `${semanticId}: executable semantic mutant differs`);
}
assert.equal(ledger.acceptedRecords, 0);
assert.equal(ledger.incompleteRecords, 162);
assert.equal(ledger.replayStatus, "NOT_RUN");
assert.equal(ledger.proofCredit, false);
assert.equal(ledger.centralCredit, false);

assert.equal(matrixBinder.kind, "ABI04_MATRIX_EXACT_SET_BINDER");
assert.equal(matrixBinder.classification, "PRE_PROOF_OPEN_MATRIX_BINDER_NOT_EVIDENCE");
checkBindings(matrixBinder.sourceBinding, "matrixBinder/sourceBinding");
checkBindings(matrixBinder.semanticClaimBindings, "matrixBinder/semanticClaimBindings");
const expectedSemanticClaimBindings = fullRowIndex.records.filter((item) => item.side === "canonical-positive").map((item) => ({
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
assert.deepEqual(matrixBinder.semanticClaimBindings, expectedSemanticClaimBindings);
assert.deepEqual(matrixBinder.replayRecordIds, ledger.records.map((item) => item.replayId));
assert.equal(matrixBinder.sourceBinding.fullRowReplayIndex.sha256, fileSha256(fullRowIndexPath));
assert.equal(matrixBinder.sourceBinding.fullRowWaveContract.sha256, fileSha256(fullRowContractPath));
assert.deepEqual(matrixBinder.exactSet, {
  finiteClaims: 69,
  symbolicClaims: 12,
  semanticClaims: 81,
  replayRecords: 162,
  duplicateSemanticClaimIds: 0,
  duplicateReplayIds: 0,
  semanticClaimIdsSha256: sha256(Buffer.from(JSON.stringify(expectedSemanticClaimBindings.map((item) => item.semanticClaimId)))),
  replayIdsSha256: sha256(Buffer.from(JSON.stringify(expectedReplayIdsOrdered))),
});
assert.equal(matrixBinder.unchangedClaimMutantRequired, true);
assert.equal(matrixBinder.singlePairFallbackAllowed, false);
assert.equal(matrixBinder.bindingStatus, "OPEN");
assert.equal(matrixBinder.proofStatus, "NOT_RUN");
assert.equal(matrixBinder.eligibleForDischarge, false);
assert.equal(matrixBinder.proofCredit, false);
assert.equal(matrixBinder.centralCredit, false);

assert.equal(independent.kind, "ABI04_INDEPENDENT_REPLAY_REPORT");
assert.equal(independent.classification, "PRE_PROOF_OPEN_REPORT_NOT_EVIDENCE");
checkBindings(independent.sourceBinding, "independent/sourceBinding");
assert.equal(independent.exactReplaySetVerified, false);
assert.equal(independent.independentlyReplayedRecords, 0);
assert.equal(independent.expectedRecords, 162);
assert.equal(independent.expectedNonReplayGates, 26);
assert.equal(independent.verifiedNonReplayGates, 0);
assert.deepEqual(independent.requiredNonReplayGateIds, expectedNonReplayGateIds);
assert.equal(independent.jsPythonClosureAgreement, false);
assert.equal(independent.replayStatus, "NOT_RUN");
assert.equal(independent.proofCredit, false);
assert.equal(independent.centralCredit, false);
assert.equal(independent.sourceBinding.fullRowReplayIndex.sha256, fileSha256(fullRowIndexPath));
assert.equal(independent.sourceBinding.fullRowWaveContract.sha256, fileSha256(fullRowContractPath));

assert.equal(isabelleReport.kind, "ABI04_ISABELLE_CLOSURE_REPORT");
assert.equal(isabelleReport.classification, "PRE_BUILD_OPEN_REPORT_NOT_EVIDENCE");
checkBindings(isabelleReport.sourceBinding, "isabelle/sourceBinding");
assert.equal(isabelleReport.session, "ERC_TRUST_ABI_04_CANDIDATE");
assert.equal(isabelleReport.buildStatus, "NOT_RUN");
assert.equal(isabelleReport.admitted, false);
assert.equal(isabelleReport.theoremCredit, false);
assert.equal(isabelleReport.centralCredit, false);
assert.equal(isabelleReport.sourceBinding.fullRowReplayIndex.sha256, fileSha256(fullRowIndexPath));
assert.equal(isabelleReport.sourceBinding.fullRowWaveContract.sha256, fileSha256(fullRowContractPath));

assert.equal(central.kind, "ABI04_CENTRAL_ROW_GATE");
assert.equal(central.classification, "STRICT_ROW_DISCHARGE_GATE");
checkBindings(central.sourceBinding, "central/sourceBinding");
assert.deepEqual(central.requiredExactSets, { finiteClaims: 69, symbolicClaims: 12, exactReplays: 162, matrixBinders: 1, authoritativePairs: 6, expectedGraphs: 12, nonReplayGates: 26 });
assert.deepEqual(central.requiredNonReplayGates, expectedNonReplayGateIds);
assert.deepEqual(policy.exactSets.nonReplayGates.expectedIds, expectedNonReplayGateIds);
assert.equal(central.nonReplayGateRecords.length, 26);
assert.equal(new Set(central.nonReplayGateRecords.map((item) => item.gateId)).size, 26);
assert.deepEqual(central.nonReplayGateRecords.map(({ gateId, invariant }) => ({ gateId, invariant })), expectedNonReplayGates);
for (const gate of central.nonReplayGateRecords) {
  assert.equal(gate.status, "NOT_RUN");
  assert.equal(gate.accepted, false);
  assert.equal(gate.resultArtifact, null);
}
assert.deepEqual(central.observed, { acceptedExactReplays: 0, incomplete: 162, admitted: false, integrity: "NOT_RUN", survivorCount: null, jsPythonClosureAgreement: false });
assert.equal(central.rowStatus, "OPEN");
assert.equal(central.eligibleForDischarge, false);
assert.equal(central.proofCredit, false);
assert.equal(central.centralCredit, false);
assert.equal(central.sourceBinding.fullRowReplayIndex.sha256, fileSha256(fullRowIndexPath));
assert.equal(central.sourceBinding.fullRowWaveContract.sha256, fileSha256(fullRowContractPath));

console.log(JSON.stringify({
  status: "PASS_OPEN_TOPOLOGY_STATIC",
  obligationId: "ABI-04",
  finiteClaims: 69,
  symbolicClaims: 12,
  exactReplayRecords: 162,
  matrixBinders: 1,
  nonReplayGates: 26,
  authoritativePairPlaceholders: 6,
  expectedGraphs: 12,
  rowStatus: central.rowStatus,
  proofCredit: false,
  centralCredit: false,
}, null, 2));
