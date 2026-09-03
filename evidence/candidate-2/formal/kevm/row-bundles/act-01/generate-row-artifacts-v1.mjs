import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { relative, resolve, sep } from "node:path";

const repositoryRoot = resolve(import.meta.dirname, "../../../..");
const rowRoot = import.meta.dirname;
const evidenceRoot = resolve(repositoryRoot, "evidence/end-to-end-refinement/row-bundles/act-01");
const sha256 = (path) => createHash("sha256").update(readFileSync(path)).digest("hex");
const repo = (path) => relative(repositoryRoot, path).split(sep).join("/");
const binding = (path) => ({ path: repo(path), sha256: sha256(path) });
const read = (path) => JSON.parse(readFileSync(path, "utf8"));
const write = (path, value) => writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`, "utf8");
const required = (path) => {
  if (!existsSync(path)) throw new Error(`missing ACT-01 generation input: ${path}`);
  return path;
};

const canonicalAnalysisPath = required(resolve(evidenceRoot, "artifacts/canonical-final/analysis.json"));
const controlAnalysisPath = required(resolve(evidenceRoot, "artifacts/control-final/analysis.json"));
const eventAnalysisPath = required(resolve(evidenceRoot, "artifacts/canonical-event/analysis.json"));
const finalClaimPath = required(resolve(rowRoot, "full-transaction-v1/full-transaction-finalization-spec.k"));
const eventClaimPath = required(resolve(rowRoot, "full-transaction-v1/full-transaction-event-order-spec.k"));
const claimManifestPath = required(resolve(rowRoot, "full-transaction-v1/manifest.json"));
const stateCapturePath = required(resolve(evidenceRoot, "full-transaction-state-capture-v1.json"));
const runtimeFreezePath = required(resolve(repositoryRoot, "evidence/end-to-end-refinement/m4-runtime-freeze-v1.json"));
const controlBindingPath = required(resolve(rowRoot, "current-control-binding.json"));
const mutationPatchPath = required(resolve(rowRoot, "negative/mutant-source.patch"));
const theoryPath = required(resolve(rowRoot, "isabelle/ACT_01_Full_Transaction.thy"));
const bridgeTheoryPath = required(resolve(rowRoot, "isabelle/ACT_01_Bridge_Generated.thy"));
const closureRunnerPath = required(resolve(rowRoot, "isabelle/run-closure.ps1"));
const heavyRunnerPath = required(resolve(rowRoot, "run-full-transaction-heavy-v1.ps1"));
const analyzerPath = required(resolve(rowRoot, "analyze-full-transaction-heavy-v1.mjs"));
const curatorPath = required(resolve(rowRoot, "curate-full-transaction-heavy-v1.mjs"));

const canonical = read(canonicalAnalysisPath);
const control = read(controlAnalysisPath);
const event = read(eventAnalysisPath);
for (const [analysis, lane] of [[canonical, "canonical-final"], [control, "control-final"], [event, "canonical-event"]]) {
  assert.equal(analysis.status, "PASS");
  assert.equal(analysis.obligationId, "ACT-01");
  assert.equal(analysis.lane, lane);
  assert.equal(analysis.centralCredit, false);
  assert.equal(analysis.graph.admitted, false);
  assert.equal(analysis.graph.stuck, 0);
  assert.equal(analysis.graph.vacuous, 0);
}
assert.equal(canonical.claimId, control.claimId, "unchanged final claim ID differs across definitions");
assert.equal(canonical.graph.pending, 0);
assert.equal(canonical.graph.terminal, 0);
assert.equal(event.graph.pending, 0);
assert.equal(event.graph.terminal, 0);
assert.ok(control.graph.terminal >= 1);

const claimManifest = read(claimManifestPath);
const stateCapture = read(stateCapturePath);
const runtimeFreeze = read(runtimeFreezePath);
const controlBinding = read(controlBindingPath);
assert.equal(claimManifest.claims[0].sha256, sha256(finalClaimPath));
assert.equal(claimManifest.claims[1].sha256, sha256(eventClaimPath));
assert.equal(stateCapture.status, "PASS_FULL_TRANSACTION_FEASIBILITY_NO_CREDIT");
assert.equal(stateCapture.canonical.observation.frozenTarget, "1");
assert.equal(stateCapture.control.observation.frozenTarget, "0");
assert.equal(runtimeFreeze.status, "FROZEN_FOR_DOWNSTREAM_PROOF_INPUTS_AFTER_FEASIBILITY_NO_ROW_CREDIT");
assert.equal(controlBinding.control.runtimeSha256, "bebc8d68c0f4f363126c9b6070dbcdafd09cd906f426ee1f7f7bdc8a7aa6f801");

const frozenTargetSlotHex = control.terminalWitness.frozenTargetSlotHex;
const frozenTargetSlotDecimal = control.terminalWitness.frozenTargetSlotDecimal;
const finalModule = "TRUST-ACT-01-FULL-TRANSACTION-FINALIZATION-SPEC";
const eventModule = "TRUST-ACT-01-FULL-TRANSACTION-EVENT-ORDER-SPEC";
const bridge = {
  schemaVersion: 1,
  obligationId: "ACT-01",
  requiredProperty: "freeze_success_refines",
  runtimeFreeze: binding(runtimeFreezePath),
  stateCapture: {
    ...binding(stateCapturePath),
    status: stateCapture.status,
    canonicalFrozenTarget: stateCapture.canonical.observation.frozenTarget,
    controlFrozenTarget: stateCapture.control.observation.frozenTarget,
    canonicalReceiptHash: stateCapture.canonical.callReceiptHash,
    canonicalCommittedLogTopics: stateCapture.canonical.committedLogTopics,
    canonicalSenderNonceDelta: Number(stateCapture.canonical.senderNonceAfter) - Number(stateCapture.canonical.senderNonceBefore),
  },
  primaryClaim: {
    ...binding(finalClaimPath),
    module: finalModule,
    claimId: canonical.claimId,
    semantics: "Full outer transaction finalization, exact return receipt hash, EVMC_SUCCESS, sender nonce increment, and named zero-to-nonzero storage frame including the absolute frozen target.",
  },
  supplementalEventClaim: {
    ...binding(eventClaimPath),
    module: eventModule,
    claimId: event.claimId,
    semantics: "Pre-finalization committed log list is exactly Frozen followed by RegulatoryActionApplied while the same return, nonce, and storage frame hold.",
  },
  exactRuntime: {
    canonicalRuntimeSha256: runtimeFreeze.runtimes.native.runtimeBytesSha256,
    controlRuntimeSha256: controlBinding.control.runtimeSha256,
    canonicalDefinitionKoreSha256: canonical.resultDefinitionKoreSha256 ?? "bac21e3e90990c4c060bf77ecfe161a70d18900c631dcea5a37343765e6b3e33",
    controlDefinitionKoreSha256: "13dd630fbe5142b2da26a4597ffb13648e627eafc2074e4da8ec24a9555c3c15",
    schedule: "CANCUN",
    workers: 1,
    booster: false,
  },
  mutationAdequacy: {
    mutationId: "ACT-01-RESTORE-PRIOR-TARGET-BEFORE-SUCCESS-RETURN",
    kind: "EXECUTABLE_SEMANTIC_MUTANT",
    patch: binding(mutationPatchPath),
    controlBinding: binding(controlBindingPath),
    unchangedClaimId: control.claimId,
    terminalWitness: control.terminalWitness,
    frozenTargetSlotHex,
    frozenTargetSlotDecimal,
    expectedTarget: "1",
    actualControlTarget: "0",
  },
  proofEvidence: {
    canonicalFinal: binding(canonicalAnalysisPath),
    controlFinal: binding(controlAnalysisPath),
    canonicalEvent: binding(eventAnalysisPath),
  },
  isabelle: {
    theorem: "act01_full_successful_transaction_refines",
    theory: binding(theoryPath),
    generatedBridgeTheory: binding(bridgeTheoryPath),
    session: "ACT_01_Row",
    buildStatus: "SOURCE_READY_REQUIRES_HASH_BOUND_CLOSURE",
  },
  claimBoundary: [
    "The exact-runtime proofs are local to the pinned constructor-resolved native TrustToken runtime and the pinned executable state-restoration control.",
    "The state-capture feasibility receipt is a claim-generation witness only; proof credit comes from the closed K graphs and named Isabelle theorem.",
    "This bridge discharges ACT-01 only and does not claim live deployment identity, compiler correctness, profile-runtime coverage, or any other central row.",
  ],
};
const bridgePath = resolve(rowRoot, "bridge/row-bridge.json");
write(bridgePath, bridge);

const manifest = {
  schemaVersion: 1,
  obligationId: "ACT-01",
  bridge: binding(bridgePath),
  claims: [binding(finalClaimPath), binding(eventClaimPath)],
  claimGeneration: binding(claimManifestPath),
  runtimeFreeze: binding(runtimeFreezePath),
  stateCapture: binding(stateCapturePath),
  analyses: [binding(canonicalAnalysisPath), binding(controlAnalysisPath), binding(eventAnalysisPath)],
  mutationPatch: binding(mutationPatchPath),
  theorem: { ...binding(theoryPath), session: "ACT_01_Row", name: "act01_full_successful_transaction_refines" },
  generatedBridgeTheory: binding(bridgeTheoryPath),
  tools: [binding(heavyRunnerPath), binding(analyzerPath), binding(curatorPath), binding(closureRunnerPath)],
};
const manifestPath = resolve(rowRoot, "bridge/row-manifest.json");
write(manifestPath, manifest);

const forbidden = ["Runtime error", "Proof crashed", "timed out", "timeout", "canceled", "cancelled", "SMT solver error", "BackendError"];
const bundle = {
  schemaVersion: 1,
  obligationId: "ACT-01",
  requiredProperty: "freeze_success_refines",
  proofSpec: { path: repo(finalClaimPath), module: finalModule, claimId: canonical.claimId, sha256: sha256(finalClaimPath) },
  positive: {
    definitionKoreSha256: "bac21e3e90990c4c060bf77ecfe161a70d18900c631dcea5a37343765e6b3e33",
    compiledJsonSha256: "5ba6257f64024f7eff4ec99c569db9f9477fd5d2a625f44ed04e091fdf795a50",
    expectedExitCode: 0,
    expectedGraph: canonical.graph,
    witnessTokens: ["EVMC_SUCCESS", frozenTargetSlotDecimal],
    forbiddenLogTokens: forbidden,
  },
  negative: {
    definitionKoreSha256: "13dd630fbe5142b2da26a4597ffb13648e627eafc2074e4da8ec24a9555c3c15",
    compiledJsonSha256: "4990f62629f98d07676eedf9d4aefcb2ce4ddffaaafac8675147fb470cdde67c",
    expectedExitCode: 1,
    expectedGraph: control.graph,
    witnessTokens: [frozenTargetSlotDecimal],
    claimRequirementTokens: ["<statusCode> .StatusCode => EVMC_SUCCESS </statusCode>", `#lookup(?FINAL_STORAGE, ${frozenTargetSlotDecimal}) ==Int 1`],
    forbiddenLogTokens: forbidden,
    mutationId: "ACT-01-RESTORE-PRIOR-TARGET-BEFORE-SUCCESS-RETURN",
    mutationKind: "EXECUTABLE_SEMANTIC_MUTANT",
  },
  bridge: { path: repo(bridgePath), sha256: sha256(bridgePath), reverseCheck: "formal/kevm/row-bundles/act-01/reverse-check-v1.mjs" },
  isabelle: {
    theoryPath: repo(theoryPath),
    theoremName: "act01_full_successful_transaction_refines",
    sourceSha256: sha256(theoryPath),
    session: "ACT_01_Row",
    rowManifestPath: repo(manifestPath),
    rowManifestSha256: sha256(manifestPath),
    bannedTokens: ["sorry", "oops", "axiomatization", "by eval", "native_decide", "skip_proof"],
  },
  residualNonclaims: bridge.claimBoundary,
};
const bundlePath = resolve(rowRoot, "bundle.json");
write(bundlePath, bundle);
process.stdout.write(`${JSON.stringify({
  status: "PASS_GENERATED",
  obligationId: "ACT-01",
  bridge: binding(bridgePath),
  manifest: binding(manifestPath),
  bundle: binding(bundlePath),
  primaryClaimId: canonical.claimId,
  supplementalEventClaimId: event.claimId,
  centralCredit: false,
}, null, 2)}\n`);
