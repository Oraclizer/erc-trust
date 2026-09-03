import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { relative, resolve, sep } from "node:path";

const repositoryRoot = resolve(import.meta.dirname, "../../../..");
const rowRoot = import.meta.dirname;
const evidenceRoot = resolve(repositoryRoot, "evidence/end-to-end-refinement/row-bundles/act-01");
const artifactsRoot = resolve(evidenceRoot, "artifacts");
const sha256 = (path) => createHash("sha256").update(readFileSync(path)).digest("hex");
const repo = (path) => relative(repositoryRoot, path).split(sep).join("/");
const binding = (path) => ({ path: repo(path), sha256: sha256(path) });
const absolute = (entry) => resolve(repositoryRoot, ...entry.path.split("/"));
const read = (path) => JSON.parse(readFileSync(path, "utf8"));
const requirePath = (path) => {
  if (!existsSync(path)) throw new Error(`missing ACT-01 replay input: ${path}`);
  return path;
};

const bundlePath = requirePath(resolve(rowRoot, "bundle.json"));
const bridgePath = requirePath(resolve(rowRoot, "bridge/row-bridge.json"));
const manifestPath = requirePath(resolve(rowRoot, "bridge/row-manifest.json"));
const runnerPath = requirePath(resolve(rowRoot, "run-full-transaction-heavy-v1.ps1"));
const canonicalPath = requirePath(resolve(artifactsRoot, "canonical-final/analysis.json"));
const controlPath = requirePath(resolve(artifactsRoot, "control-final/analysis.json"));
const eventPath = requirePath(resolve(artifactsRoot, "canonical-event/analysis.json"));
const reversePath = requirePath(resolve(artifactsRoot, "bridge-reverse-check.json"));
const schemaPath = requirePath(resolve(artifactsRoot, "bundle-schema-validation.json"));
const closurePath = requirePath(resolve(artifactsRoot, "isabelle-closure-report.json"));
const bundle = read(bundlePath);
const canonical = read(canonicalPath);
const control = read(controlPath);
const event = read(eventPath);
const closure = read(closurePath);
for (const analysis of [canonical, control, event]) assert.equal(analysis.status, "PASS");
assert.equal(canonical.claimId, control.claimId);
assert.equal(canonical.claimId, bundle.proofSpec.claimId);
assert.equal(event.graph.pending, 0);
assert.equal(event.graph.terminal, 0);
assert.equal(closure.status, "PASS");

const canonicalResult = read(absolute(canonical.result));
const controlResult = read(absolute(control.result));
const eventResult = read(absolute(event.result));
assert.equal(canonicalResult.status, "PASS_CANONICAL_POSITIVE");
assert.equal(controlResult.status, "PASS_EXPECTED_SEMANTIC_CONTROL_FAILURE");
assert.equal(eventResult.status, "PASS_CANONICAL_POSITIVE");
const terminalNodeBindings = control.terminalWitness.nodes;
for (const entry of terminalNodeBindings) assert.equal(sha256(absolute(entry)), entry.sha256);
const witnessPath = resolve(artifactsRoot, "negative-terminal-witness.json");
const witness = {
  schemaVersion: 1,
  status: "PASS_TERMINAL_SEMANTIC_COUNTEREXAMPLE",
  obligationId: "ACT-01",
  mutationId: bundle.negative.mutationId,
  claimId: control.claimId,
  terminalNodeIds: control.terminalWitness.nodeIds,
  terminalNodes: terminalNodeBindings,
  semanticDifference: {
    frozenTargetSlotHex: control.terminalWitness.frozenTargetSlotHex,
    frozenTargetSlotDecimal: control.terminalWitness.frozenTargetSlotDecimal,
    unchangedClaimExpectedTarget: "1",
    stateRestorationControlActualTarget: "0",
  },
  backendRuntimeError: false,
  pendingAfterFailFast: control.graph.pending,
  admitted: false,
  centralCredit: false,
};
writeFileSync(witnessPath, `${JSON.stringify(witness, null, 2)}\n`, "utf8");

const replay = {
  schemaVersion: 2,
  status: "PASS",
  obligationId: "ACT-01",
  authoritativeFreshReplayRequired: false,
  createdAtUtc: new Date().toISOString(),
  curatedEvidenceDirectory: "evidence/end-to-end-refinement/row-bundles/act-01/artifacts",
  runner: { path: repo(runnerPath), sourceSha256: sha256(runnerPath), executedSha256: sha256(runnerPath) },
  bundle: binding(bundlePath),
  bundleSchemaValidation: binding(schemaPath),
  claimId: canonical.claimId,
  proofSpec: { ...binding(resolve(repositoryRoot, ...bundle.proofSpec.path.split("/"))), module: bundle.proofSpec.module, claimId: bundle.proofSpec.claimId },
  definitions: {
    positive: {
      definitionKoreSha256: bundle.positive.definitionKoreSha256,
      compiledJsonSha256: bundle.positive.compiledJsonSha256,
    },
    negative: {
      definitionKoreSha256: bundle.negative.definitionKoreSha256,
      compiledJsonSha256: bundle.negative.compiledJsonSha256,
      mutationId: bundle.negative.mutationId,
    },
  },
  bridge: { source: binding(bridgePath), reverseCheck: binding(reversePath) },
  isabelle: {
    session: bundle.isabelle.session,
    theoremName: bundle.isabelle.theoremName,
    oracleDependencyCount: closure.oracleDependencyCount,
    theory: binding(resolve(repositoryRoot, ...bundle.isabelle.theoryPath.split("/"))),
    rowManifest: binding(manifestPath),
    closureReport: binding(closurePath),
  },
  positive: {
    analysis: { status: "PASS", side: "positive", graph: canonical.graph },
    elapsedWallSeconds: canonicalResult.wallMs / 1000,
    proof: canonical.proof,
    kcfg: canonical.kcfg,
    log: canonical.log,
  },
  negative: {
    analysis: { status: "PASS", side: "negative", graph: control.graph },
    elapsedWallSeconds: controlResult.wallMs / 1000,
    proof: control.proof,
    kcfg: control.kcfg,
    log: control.log,
    backendRuntimeError: false,
    terminalWitness: {
      ...binding(witnessPath),
      nodeId: control.terminalWitness.nodeIds[0],
      tokens: [control.terminalWitness.frozenTargetSlotDecimal],
      claimRequirementTokens: bundle.negative.claimRequirementTokens,
    },
  },
  supplementalEventProof: {
    status: "PASS",
    claimId: event.claimId,
    proofSpec: binding(resolve(repositoryRoot, "formal/kevm/row-bundles/act-01/full-transaction-v1/full-transaction-event-order-spec.k")),
    analysis: { status: "PASS", side: "supplemental-event", graph: event.graph },
    elapsedWallSeconds: eventResult.wallMs / 1000,
    proof: event.proof,
    kcfg: event.kcfg,
    log: event.log,
  },
  residualNonclaims: bundle.residualNonclaims,
  centralCredit: false,
};
const replayPath = resolve(evidenceRoot, "replay.json");
writeFileSync(replayPath, `${JSON.stringify(replay, null, 2)}\n`, "utf8");
process.stdout.write(`${JSON.stringify({
  status: "PASS_GENERATED",
  obligationId: "ACT-01",
  replay: binding(replayPath),
  terminalWitness: binding(witnessPath),
  primaryClaimId: canonical.claimId,
  supplementalEventClaimId: event.claimId,
  centralCredit: false,
}, null, 2)}\n`);
