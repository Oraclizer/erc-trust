import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";

const repositoryRoot = resolve(import.meta.dirname, "../../../..");
const absolute = (path) => resolve(repositoryRoot, ...path.split("/"));
const sha256 = (path) => createHash("sha256").update(readFileSync(path)).digest("hex");
const read = (path) => JSON.parse(readFileSync(path, "utf8"));
const verifyBinding = (entry) => {
  const path = absolute(entry.path);
  assert.ok(existsSync(path), `missing bound artifact: ${entry.path}`);
  assert.equal(sha256(path), entry.sha256, `bound artifact drift: ${entry.path}`);
  return path;
};

const bundlePath = resolve(import.meta.dirname, "bundle.json");
const bridgePath = resolve(import.meta.dirname, "bridge/row-bridge.json");
const manifestPath = resolve(import.meta.dirname, "bridge/row-manifest.json");
const closurePath = resolve(repositoryRoot, "evidence/end-to-end-refinement/row-bundles/act-01/artifacts/isabelle-closure-report.json");
for (const path of [bundlePath, bridgePath, manifestPath, closurePath]) assert.ok(existsSync(path), `missing ACT-01 closure input: ${path}`);
const bundle = read(bundlePath);
const bridge = read(bridgePath);
const manifest = read(manifestPath);
const closure = read(closurePath);
assert.equal(bundle.obligationId, "ACT-01");
assert.equal(bridge.obligationId, "ACT-01");
assert.equal(manifest.obligationId, "ACT-01");
assert.equal(bundle.requiredProperty, "freeze_success_refines");
assert.equal(bundle.bridge.sha256, sha256(bridgePath));
assert.equal(bundle.isabelle.rowManifestSha256, sha256(manifestPath));
assert.equal(manifest.bridge.sha256, sha256(bridgePath));

for (const entry of [
  bridge.runtimeFreeze,
  bridge.stateCapture,
  bridge.primaryClaim,
  bridge.supplementalEventClaim,
  bridge.mutationAdequacy.patch,
  bridge.mutationAdequacy.controlBinding,
  bridge.proofEvidence.canonicalFinal,
  bridge.proofEvidence.controlFinal,
  bridge.proofEvidence.canonicalEvent,
  bridge.isabelle.theory,
  bridge.isabelle.generatedBridgeTheory,
  manifest.bridge,
  manifest.claimGeneration,
  manifest.runtimeFreeze,
  manifest.stateCapture,
  manifest.mutationPatch,
  manifest.theorem,
  manifest.generatedBridgeTheory,
  ...manifest.claims,
  ...manifest.analyses,
  ...manifest.tools,
]) verifyBinding(entry);

const canonical = read(verifyBinding(bridge.proofEvidence.canonicalFinal));
const control = read(verifyBinding(bridge.proofEvidence.controlFinal));
const event = read(verifyBinding(bridge.proofEvidence.canonicalEvent));
assert.equal(canonical.status, "PASS");
assert.equal(control.status, "PASS");
assert.equal(event.status, "PASS");
assert.equal(canonical.claimId, control.claimId);
assert.equal(canonical.claimId, bundle.proofSpec.claimId);
assert.equal(event.claimId, bridge.supplementalEventClaim.claimId);
assert.deepEqual(canonical.graph, bundle.positive.expectedGraph);
assert.deepEqual(control.graph, bundle.negative.expectedGraph);
assert.equal(canonical.graph.pending, 0);
assert.equal(canonical.graph.terminal, 0);
assert.equal(event.graph.pending, 0);
assert.equal(event.graph.terminal, 0);
assert.ok(control.graph.terminal >= 1);
assert.equal(control.terminalWitness.frozenTargetSlotHex, bridge.mutationAdequacy.frozenTargetSlotHex);
assert.equal(control.terminalWitness.actualControlTarget, "0");
assert.equal(control.terminalWitness.expectedTarget, "1");

const finalClaim = readFileSync(verifyBinding(bridge.primaryClaim), "utf8");
const eventClaim = readFileSync(verifyBinding(bridge.supplementalEventClaim), "utf8");
for (const token of [
  "module TRUST-ACT-01-FULL-TRANSACTION-FINALIZATION-SPEC",
  "<k> loadTx(",
  "<statusCode> .StatusCode => EVMC_SUCCESS </statusCode>",
  "<nonce> 0 => 1 </nonce>",
  `#lookup(?FINAL_STORAGE, ${bridge.mutationAdequacy.frozenTargetSlotDecimal}) ==Int 1`,
  "#lookup(TOKEN_STORAGE, 29) ==Int 0",
]) assert.ok(finalClaim.includes(token), `final claim semantic token missing: ${token}`);
for (const token of [
  "module TRUST-ACT-01-FULL-TRANSACTION-EVENT-ORDER-SPEC",
  "#halt ~> #finishTx ~> #finalizeTx(false",
  "<statusCode> .StatusCode => EVMC_SUCCESS </statusCode>",
  "<nonce> 0 => 1 </nonce>",
  "ListItem({",
  "#lookup(TOKEN_STORAGE, 29) ==Int 0",
]) assert.ok(eventClaim.includes(token), `event claim semantic token missing: ${token}`);
assert.equal((eventClaim.match(/ListItem\(\{/g) ?? []).length, 2, "event claim must bind exactly two committed logs");

const controlBinding = read(verifyBinding(bridge.mutationAdequacy.controlBinding));
const canonicalSourcePath = absolute(controlBinding.canonical.sourcePath);
const canonicalSource = readFileSync(canonicalSourcePath, "utf8");
const before = "            _applyActionPrepared(request, record.commandHash, record.evidenceHash);\n            return true;";
const after = "            _applyActionPrepared(request, record.commandHash, record.evidenceHash);\n            _frozen[account] = record.priorAmount; // ACT-01 distinguishing control\n            return true;";
assert.equal(canonicalSource.split(before).length - 1, 1, "canonical mutation anchor cardinality drift");
const reconstructedControl = canonicalSource.replace(before, after);
assert.equal(createHash("sha256").update(reconstructedControl).digest("hex"), controlBinding.control.sourceSha256);
const patchText = readFileSync(verifyBinding(bridge.mutationAdequacy.patch), "utf8");
assert.ok(patchText.includes("+            _frozen[account] = record.priorAmount; // ACT-01 distinguishing control"));
assert.notEqual(bridge.exactRuntime.canonicalRuntimeSha256, bridge.exactRuntime.controlRuntimeSha256);

const theoryText = readFileSync(verifyBinding(bridge.isabelle.theory), "utf8");
assert.ok(theoryText.includes("theorem act01_full_successful_transaction_refines:"));
for (const banned of bundle.isabelle.bannedTokens) {
  const pattern = new RegExp(`\\b${banned.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b`, "i");
  assert.equal(pattern.test(theoryText), false, `banned Isabelle source token: ${banned}`);
}
assert.equal(closure.status, "PASS");
assert.equal(closure.session, "ACT_01_Row");
assert.equal(closure.theoremName, "act01_full_successful_transaction_refines");
assert.equal(closure.oracleDependencyCount, 0);
assert.equal(closure.bannedSourceForms, 0);
assert.equal(closure.theorySha256, sha256(verifyBinding(bridge.isabelle.theory)));
assert.equal(closure.rowManifestSha256, sha256(manifestPath));

const report = {
  status: "PASS",
  obligationId: "ACT-01",
  primaryClaimId: canonical.claimId,
  supplementalEventClaimId: event.claimId,
  canonicalGraph: canonical.graph,
  controlGraph: control.graph,
  eventGraph: event.graph,
  oracleDependencyCount: 0,
  centralCredit: false,
};
const serialized = `${JSON.stringify(report, null, 2)}\n`;
const reportIndex = process.argv.indexOf("--report");
if (reportIndex >= 0) {
  if (!process.argv[reportIndex + 1]) throw new Error("--report requires a path");
  writeFileSync(resolve(process.argv[reportIndex + 1]), serialized, "utf8");
}
process.stdout.write(serialized);
