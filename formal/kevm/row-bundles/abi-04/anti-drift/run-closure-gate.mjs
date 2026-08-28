#!/usr/bin/env node
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const antiDir = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(antiDir, "../../../../..");
const outIndex = process.argv.indexOf("--out");
assert.ok(outIndex >= 0 && process.argv[outIndex + 1], "--out ABSOLUTE_FRESH_OUTPUT_ROOT is required");
const outputRoot = path.resolve(process.argv[outIndex + 1]);
assert.equal(fs.existsSync(outputRoot), false, `refusing existing output root: ${outputRoot}`);
const pythonIndex = process.argv.indexOf("--python");
const python = pythonIndex >= 0 ? process.argv[pythonIndex + 1] : process.env.ABI04_PYTHON ?? (process.platform === "win32" ? "python" : "python3");
const generationReceiptFromStdin = process.argv.includes("--generation-receipt-stdin");
const jsVerifier = path.join(antiDir, "verify-closure.mjs");
const pythonVerifier = path.join(antiDir, "verify_closure.py");
const policyPath = path.join(antiDir, "closure-policy.json");

const sha256 = (value) => crypto.createHash("sha256").update(value).digest("hex");
const fileSha256 = (value) => sha256(fs.readFileSync(value));
const stable = (value) => {
  if (Array.isArray(value)) return `[${value.map(stable).join(",")}]`;
  if (value && typeof value === "object") return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stable(value[key])}`).join(",")}}`;
  return JSON.stringify(value);
};
const readJson = (value) => JSON.parse(fs.readFileSync(value, "utf8"));
const writeJson = (value, content) => fs.writeFileSync(value, `${JSON.stringify(content, null, 2)}\n`, "utf8");
const isSha256 = (value) => typeof value === "string" && /^[0-9a-f]{64}$/.test(value);

let generationReceipt = null;
if (generationReceiptFromStdin) {
  const input = fs.readFileSync(0, "utf8");
  assert.ok(input.trim(), "--generation-receipt-stdin requires JSON on stdin");
  generationReceipt = JSON.parse(input);
  assert.equal(generationReceipt.kind, "ABI04_DETERMINISTIC_DESCENDANT_GENERATION_RECEIPT");
  assert.equal(generationReceipt.obligationId, "ABI-04");
  assert.equal(generationReceipt.status, "PASS_BYTE_IDENTICAL_CLEAN_SECOND_CHECK");
  assert.equal(generationReceipt.preGenerationClosure.jsPythonAgreement, true);
  assert.equal(generationReceipt.impactAnalysis.status, "PASS_EXACT_MANAGED_OUTPUT_SET");
  assert.deepEqual(generationReceipt.impactAnalysis.unexpectedChangedPaths, []);
  const impact = generationReceipt.impactAnalysis;
  const exactStages = ["matrix", "dynamic-offset", "expected-graphs", "runner-pin", "orchestration", "dynamic-length", "symbolic-final", "aggregate", "finite-symbolic-bridge", "open-topology", "closure-manifest"];
  assert.deepEqual(impact.dependencyCluster.map((item) => item.stage), exactStages, "impact dependency cluster exact-set mismatch");
  assert.deepEqual(impact.preGenerationPlans.map((item) => item.stage), exactStages, "pre-generation plan exact-set mismatch");
  assert.deepEqual(impact.seedStages, impact.preGenerationPlans.filter((item) => item.requiresRegeneration).map((item) => item.stage), "impact seed/plan mismatch");
  assert.equal(new Set(impact.seedStages).size, impact.seedStages.length, "duplicate impact seed stage");
  const recomputedImpacted = new Set(impact.seedStages);
  let impactGrew = true;
  while (impactGrew) {
    impactGrew = false;
    for (const node of impact.dependencyCluster) {
      if (!recomputedImpacted.has(node.stage) && node.dependsOn.some((dependency) => recomputedImpacted.has(dependency))) {
        recomputedImpacted.add(node.stage);
        impactGrew = true;
      }
    }
  }
  const expectedImpactedStages = exactStages.filter((stage) => recomputedImpacted.has(stage));
  assert.deepEqual(impact.impactedStages, expectedImpactedStages, "impact stage closure mismatch");
  assert.deepEqual(impact.unimpactedStages, exactStages.filter((stage) => !recomputedImpacted.has(stage)), "unimpacted stage set mismatch");
  assert.deepEqual(impact.stageChanges.map((item) => item.stage), exactStages, "full static first-pass stage exact-set mismatch");
  assert.equal(generationReceipt.deterministicDescendantGeneration.status, "FULL_STATIC_PIPELINE_BYTE_IDENTICAL");
  assert.equal(generationReceipt.deterministicDescendantGeneration.scope, "FULL_STATIC_PIPELINE_SUPERSET_OF_DECLARED_IMPACT");
  assert.equal(generationReceipt.deterministicDescendantGeneration.passes, 2);
  assert.equal(generationReceipt.deterministicDescendantGeneration.pass1SnapshotSha256, generationReceipt.deterministicDescendantGeneration.pass2SnapshotSha256);
  assert.equal(generationReceipt.deterministicDescendantGeneration.pass2ChangedDescendants, 0);
  assert.deepEqual(generationReceipt.deterministicDescendantGeneration.secondPassStageChanges.map((item) => item.stage), exactStages, "full static second-pass stage exact-set mismatch");
  for (const stage of generationReceipt.deterministicDescendantGeneration.secondPassStageChanges) assert.deepEqual(stage.changedPaths, [], `second-pass stage changed bytes: ${stage.stage}`);
  assert.equal(generationReceipt.cleanSecondCheck.status, "PASS");
  assert.equal(generationReceipt.cleanSecondCheck.count, 11);
  assert.equal(generationReceipt.cleanSecondCheck.reverseCount, 8);
  assert.equal(generationReceipt.freshIsolatedReproduction.status, "PASS_TWO_FRESH_ISOLATED_ROOTS_BYTE_IDENTICAL");
  assert.equal(generationReceipt.freshIsolatedReproduction.builders.length, 2);
  assert.equal(generationReceipt.freshIsolatedReproduction.builders[0].snapshotSha256, generationReceipt.freshIsolatedReproduction.builders[1].snapshotSha256);
  assert.equal(generationReceipt.freshIsolatedReproduction.scratchRootsRemovedAfterPass, true);
  assert.equal(generationReceipt.freshIsolatedReproduction.independentBuilderClaim, false);
  assert.equal(generationReceipt.failClosedMutationRegression.status, "PASS_2_OF_2_EXPECTED_NONZERO");
  assert.equal(generationReceipt.failClosedMutationRegression.exactScenarioCount, 2);
  assert.equal(generationReceipt.failClosedMutationRegression.scenarios.every((item) => item.jsExitCode === 1 && item.pythonExitCode === 1), true);
  assert.equal(generationReceipt.failClosedMutationRegression.scratchRootsRemovedAfterPass, true);
  assert.equal(generationReceipt.proofExecuted, false);
  assert.equal(generationReceipt.proofCredit, false);
  assert.equal(generationReceipt.centralCredit, false);
  assert.equal(path.isAbsolute(generationReceipt.coordinator.path), false, "absolute generation coordinator path");
  assert.ok(isSha256(generationReceipt.coordinator.sha256), "invalid generation coordinator hash");
  const generationCoordinator = path.join(repositoryRoot, ...generationReceipt.coordinator.path.split("/"));
  assert.ok(fs.existsSync(generationCoordinator), "missing generation coordinator");
  assert.equal(fileSha256(generationCoordinator), generationReceipt.coordinator.sha256, "generation coordinator hash mismatch");
  const changed = generationReceipt.impactAnalysis.changedDescendantSet;
  assert.equal(new Set(changed).size, changed.length, "duplicate changed descendant path");
  assert.equal(sha256(stable(changed)), generationReceipt.impactAnalysis.changedDescendantSetSha256, "changed descendant set hash mismatch");
  const stages = generationReceipt.managedOutputExactSet.stages;
  const managedOutputs = stages.flatMap((stage) => stage.outputs);
  const managedPaths = managedOutputs.map((item) => item.path).sort();
  const expectedGenerationEdges = stages.flatMap((stage) => stage.outputs.map((output) => ({ relation: "deterministic-generator-output", stage: stage.stage, parent: stage.generator, child: output })));
  assert.equal(generationReceipt.managedOutputExactSet.count, managedOutputs.length);
  assert.equal(generationReceipt.managedOutputExactSet.uniqueCount, new Set(managedPaths).size);
  assert.equal(managedOutputs.length, new Set(managedPaths).size, "managed output has multiple generator owners");
  assert.equal(sha256(stable(managedPaths)), generationReceipt.managedOutputExactSet.pathsSha256, "managed output exact-set hash mismatch");
  assert.deepEqual(generationReceipt.managedOutputExactSet.edges, expectedGenerationEdges, "generator parent/output child edge exact-set mismatch");
  assert.equal(sha256(stable(expectedGenerationEdges)), generationReceipt.managedOutputExactSet.edgesRootSha256, "generator edge root mismatch");
  for (const stage of stages) {
    for (const descriptor of [stage.generator, ...stage.outputs]) {
      assert.equal(path.isAbsolute(descriptor.path), false, `${stage.stage}: absolute receipt path`);
      assert.ok(isSha256(descriptor.sha256), `${stage.stage}: invalid receipt hash`);
      const target = path.join(repositoryRoot, ...descriptor.path.split("/"));
      assert.ok(fs.existsSync(target), `${stage.stage}: missing receipt target ${descriptor.path}`);
      assert.equal(fileSha256(target), descriptor.sha256, `${stage.stage}: receipt target hash mismatch ${descriptor.path}`);
    }
    assert.equal(sha256(stable(stage.outputs)), stage.outputsRootSha256, `${stage.stage}: output-root hash mismatch`);
  }
  for (const changedPath of changed) assert.ok(managedPaths.includes(changedPath), `changed descendant outside managed exact set: ${changedPath}`);
}

fs.mkdirSync(outputRoot, { recursive: false });
const runs = [];
for (const runName of ["run-1", "run-2"]) {
  const runRoot = path.join(outputRoot, runName);
  const jsRoot = path.join(runRoot, "js");
  const pythonRoot = path.join(runRoot, "python");
  fs.mkdirSync(runRoot, { recursive: true });
  const js = spawnSync(process.execPath, [jsVerifier, "--out", jsRoot], { cwd: repositoryRoot, encoding: "utf8" });
  const py = spawnSync(python, [pythonVerifier, "--out", pythonRoot], { cwd: repositoryRoot, encoding: "utf8" });
  assert.notEqual(js.status, null, `JS verifier failed to start: ${js.error ?? js.stderr}`);
  assert.notEqual(py.status, null, `Python verifier failed to start: ${py.error ?? py.stderr}`);
  const jsVerdictPath = path.join(jsRoot, "js-verdict.json");
  const pythonVerdictPath = path.join(pythonRoot, "python-verdict.json");
  const jsDagPath = path.join(jsRoot, "dependency-closure.json");
  const pythonDagPath = path.join(pythonRoot, "dependency-closure.json");
  for (const required of [jsVerdictPath, pythonVerdictPath, jsDagPath, pythonDagPath]) assert.ok(fs.existsSync(required), `missing verifier output: ${required}`);
  const jsVerdict = readJson(jsVerdictPath);
  const pythonVerdict = readJson(pythonVerdictPath);
  const jsDag = readJson(jsDagPath);
  const pythonDag = readJson(pythonDagPath);
  assert.equal(jsVerdict.exitCode, js.status, `${runName}: JS declared/process exit mismatch`);
  assert.equal(pythonVerdict.exitCode, py.status, `${runName}: Python declared/process exit mismatch`);
  assert.equal(jsVerdict.closureHashSha256, pythonVerdict.closureHashSha256, `${runName}: closure hash disagreement`);
  assert.deepEqual(jsVerdict.counts, pythonVerdict.counts, `${runName}: count disagreement`);
  assert.deepEqual(jsVerdict.missing, pythonVerdict.missing, `${runName}: missing-set disagreement`);
  assert.deepEqual(jsVerdict.unexpected, pythonVerdict.unexpected, `${runName}: unexpected-set disagreement`);
  assert.deepEqual(jsVerdict.duplicate, pythonVerdict.duplicate, `${runName}: duplicate-set disagreement`);
  assert.deepEqual(jsVerdict.declaredActualMismatch, pythonVerdict.declaredActualMismatch, `${runName}: mismatch-set disagreement`);
  assert.deepEqual(jsVerdict.invalidatedDescendants, pythonVerdict.invalidatedDescendants, `${runName}: invalidation disagreement`);
  assert.equal(stable({ nodes: jsDag.nodes, edges: jsDag.edges }), stable({ nodes: pythonDag.nodes, edges: pythonDag.edges }), `${runName}: independently materialized DAG disagreement`);
  runs.push({
    runName,
    jsExitCode: js.status,
    pythonExitCode: py.status,
    closureHashSha256: jsVerdict.closureHashSha256,
    status: jsVerdict.status,
    counts: jsVerdict.counts,
    invalidatedDescendants: jsVerdict.invalidatedDescendants,
    failedExactSets: jsVerdict.failedExactSets,
    files: {
      jsDag: { path: path.relative(outputRoot, jsDagPath).split(path.sep).join("/"), sha256: fileSha256(jsDagPath) },
      jsVerdict: { path: path.relative(outputRoot, jsVerdictPath).split(path.sep).join("/"), sha256: fileSha256(jsVerdictPath) },
      pythonDag: { path: path.relative(outputRoot, pythonDagPath).split(path.sep).join("/"), sha256: fileSha256(pythonDagPath) },
      pythonVerdict: { path: path.relative(outputRoot, pythonVerdictPath).split(path.sep).join("/"), sha256: fileSha256(pythonVerdictPath) },
    },
    stdout: { js: js.stdout.trim(), python: py.stdout.trim() },
    stderr: { js: js.stderr.trim(), python: py.stderr.trim() },
  });
}

assert.equal(runs[0].closureHashSha256, runs[1].closureHashSha256, "closure changed across deterministic runs");
assert.deepEqual(runs[0].counts, runs[1].counts, "counts changed across deterministic runs");
assert.deepEqual(runs[0].invalidatedDescendants, runs[1].invalidatedDescendants, "invalidation changed across deterministic runs");
for (const implementation of ["jsDag", "jsVerdict", "pythonDag", "pythonVerdict"]) {
  assert.equal(runs[0].files[implementation].sha256, runs[1].files[implementation].sha256, `${implementation} is not byte-identical across runs`);
}

const pass = runs.every((run) => run.jsExitCode === 0 && run.pythonExitCode === 0 && run.status === "PASS");
const workerResult = {
  schemaVersion: 1,
  kind: "ABI04_STRICT_ANTI_DRIFT_WORKER_RESULT",
  obligationId: "ABI-04",
  status: pass ? "PASS" : "FAIL_CLOSED_INVALIDATED",
  exitCode: pass ? 0 : 1,
  outputRoot,
  source: {
    repositoryRoot,
    policy: { path: path.relative(repositoryRoot, policyPath).split(path.sep).join("/"), sha256: fileSha256(policyPath) },
    jsVerifier: { path: path.relative(repositoryRoot, jsVerifier).split(path.sep).join("/"), sha256: fileSha256(jsVerifier) },
    pythonVerifier: { path: path.relative(repositoryRoot, pythonVerifier).split(path.sep).join("/"), sha256: fileSha256(pythonVerifier) },
    coordinator: { path: path.relative(repositoryRoot, fileURLToPath(import.meta.url)).split(path.sep).join("/"), sha256: fileSha256(fileURLToPath(import.meta.url)) },
  },
  closureHashSha256: runs[0].closureHashSha256,
  jsPythonAgreement: true,
  deterministicDoubleGeneration: {
    status: "BYTE_IDENTICAL",
    runs: runs.map(({ runName, files }) => ({ runName, files })),
  },
  generationReceipt,
  generationReceiptSha256: generationReceipt === null ? null : sha256(stable(generationReceipt)),
  counts: runs[0].counts,
  invalidatedDescendantSet: runs[0].invalidatedDescendants,
  failedExactSets: runs[0].failedExactSets,
  runs,
  prohibitions: {
    warningOnly: false,
    manualHashEdit: false,
    staleCacheOverride: false,
    singlePairFallback: false,
  },
  proofCredit: false,
  centralCredit: false,
};
const workerResultPath = path.join(outputRoot, "worker-result.json");
writeJson(workerResultPath, workerResult);
console.log(JSON.stringify({ status: workerResult.status, exitCode: workerResult.exitCode, closureHashSha256: workerResult.closureHashSha256, jsPythonAgreement: workerResult.jsPythonAgreement, deterministicDoubleGeneration: workerResult.deterministicDoubleGeneration.status, counts: workerResult.counts, workerResult: workerResultPath }, null, 2));
process.exitCode = workerResult.exitCode;
