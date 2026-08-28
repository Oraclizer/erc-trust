#!/usr/bin/env node
// Root-only deterministic ABI-04 product materializer. It runs the impacted
// generator DAG twice, compares the complete scoped byte set, runs clean
// --check/reverse gates, and finally emits a dual JS/Python closure audit.
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const rowDir = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(rowDir, "../../../..");
const args = process.argv.slice(2);
const writeMode = args.includes("--write");
const planMode = args.includes("--plan");
assert.equal([writeMode, planMode].filter(Boolean).length, 1, "use exactly one of --write or --plan");
const valueAfter = (flag) => {
  const index = args.indexOf(flag);
  return index >= 0 ? args[index + 1] : null;
};
const auditRoot = valueAfter("--audit-out");
const python = valueAfter("--python") ?? process.env.ABI04_PYTHON ?? (process.platform === "win32" ? "python" : "python3");
if (writeMode) {
  assert.ok(auditRoot, "--audit-out ABSOLUTE_FRESH_OUTPUT_ROOT is required with --write");
  assert.equal(path.isAbsolute(auditRoot), true, "audit output root must be absolute");
  assert.equal(fs.existsSync(auditRoot), false, `refusing existing audit output root: ${auditRoot}`);
}

const scripts = {
  matrix: path.join(rowDir, "generate-abi-04-matrix.mjs"),
  offset: path.join(rowDir, "dynamic-offset-v1", "generate-dynamic-offset-family-v1.mjs"),
  graphRebind: path.join(rowDir, "dynamic-offset-v1", "generate-expected-graphs-after-path-normalization.mjs"),
  runnerPin: path.join(rowDir, "dynamic-offset-v1", "pin-dynamic-offset-runner-v4.mjs"),
  orchestration: path.join(rowDir, "dynamic-offset-v1", "generate-dynamic-offset-orchestration-v2.mjs"),
  length: path.join(rowDir, "dynamic-length-v1", "generate-dynamic-length-family-v1.mjs"),
  symbolic: path.join(rowDir, "aggregation", "generate-abi-04-symbolic-short-head-final.mjs"),
  aggregate: path.join(rowDir, "aggregation", "generate-abi-04-aggregation.mjs"),
  bridge: path.join(rowDir, "aggregation", "generate-abi-04-finite-symbolic-row-bridge.mjs"),
  topology: path.join(rowDir, "generate-abi-04-open-topology.mjs"),
  closureManifest: path.join(rowDir, "anti-drift", "generate-closure-manifest.mjs"),
};
const reverseChecks = [
  path.join(rowDir, "reverse-check.mjs"),
  path.join(rowDir, "dynamic-offset-v1", "reverse-check-dynamic-offset-family-v1.mjs"),
  path.join(rowDir, "dynamic-offset-v1", "reverse-check-dynamic-offset-leaf-v4.mjs"),
  path.join(rowDir, "dynamic-length-v1", "reverse-check-dynamic-length-family-v1.mjs"),
  path.join(rowDir, "aggregation", "reverse-check-abi-04-symbolic-short-head-final.mjs"),
  path.join(rowDir, "aggregation", "reverse-check-abi-04-aggregation.mjs"),
  path.join(rowDir, "aggregation", "reverse-check-abi-04-finite-symbolic-row-bridge.mjs"),
  path.join(rowDir, "reverse-check-abi-04-open-topology.mjs"),
];
const failClosedMutationTest = path.join(rowDir, "anti-drift", "test-closure-fail-closed.mjs");
for (const target of [...Object.values(scripts), ...reverseChecks, failClosedMutationTest]) assert.ok(fs.existsSync(target), `missing pipeline source: ${target}`);

const pipeline = [
  ["matrix", scripts.matrix],
  ["dynamic-offset", scripts.offset],
  ["expected-graphs", scripts.graphRebind],
  ["runner-pin", scripts.runnerPin],
  ["orchestration", scripts.orchestration],
  ["dynamic-length", scripts.length],
  ["symbolic-final", scripts.symbolic],
  ["aggregate", scripts.aggregate],
  ["finite-symbolic-bridge", scripts.bridge],
  ["open-topology", scripts.topology],
  ["closure-manifest", scripts.closureManifest],
];
const dependencyCluster = [
  { stage: "matrix", dependsOn: [] },
  { stage: "dynamic-offset", dependsOn: ["matrix"] },
  { stage: "expected-graphs", dependsOn: ["dynamic-offset"] },
  { stage: "runner-pin", dependsOn: ["dynamic-offset", "expected-graphs"] },
  { stage: "orchestration", dependsOn: ["matrix", "dynamic-offset", "expected-graphs", "runner-pin"] },
  { stage: "dynamic-length", dependsOn: ["matrix", "dynamic-offset"] },
  { stage: "symbolic-final", dependsOn: ["matrix"] },
  { stage: "aggregate", dependsOn: ["matrix", "symbolic-final"] },
  { stage: "finite-symbolic-bridge", dependsOn: ["matrix", "dynamic-length", "aggregate"] },
  { stage: "open-topology", dependsOn: ["matrix", "orchestration", "dynamic-length", "symbolic-final", "aggregate", "finite-symbolic-bridge"] },
  { stage: "closure-manifest", dependsOn: ["matrix", "dynamic-offset", "expected-graphs", "runner-pin", "orchestration", "dynamic-length", "symbolic-final", "aggregate", "finite-symbolic-bridge", "open-topology"] },
];
assert.deepEqual(dependencyCluster.map((item) => item.stage), pipeline.map(([name]) => name), "dependency cluster/pipeline order mismatch");
const computeImpact = () => {
  const preGenerationPlans = pipeline.map(([stage, script]) => {
    const result = spawnSync(process.execPath, [script, "--plan"], { cwd: repositoryRoot, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
    assert.notEqual(result.status, null, `pre-generation plan failed to start: ${stage}`);
    let parsed = null;
    if (result.status === 0) parsed = JSON.parse(result.stdout);
    const changes = parsed?.changes;
    const requiresRegeneration = Boolean(result.status !== 0
      || parsed?.change === "CHANGED" || parsed?.change === "MISSING"
      || (Array.isArray(changes) && changes.some((item) => item.status !== "UNCHANGED"))
      || (changes && !Array.isArray(changes) && ((changes.changed ?? 0) > 0 || (changes.missing ?? 0) > 0)));
    assert.equal(typeof requiresRegeneration, "boolean", `${stage}: requiresRegeneration must be boolean`);
    return { stage, exitCode: result.status, status: parsed?.status ?? "NONZERO_BLOCKED_BY_CURRENT_UPSTREAM_STATE", requiresRegeneration };
  });
  const seedStages = preGenerationPlans.filter((item) => item.requiresRegeneration).map((item) => item.stage);
  const impactedStageSet = new Set(seedStages);
  let grew = true;
  while (grew) {
    grew = false;
    for (const node of dependencyCluster) {
      if (!impactedStageSet.has(node.stage) && node.dependsOn.some((dependency) => impactedStageSet.has(dependency))) {
        impactedStageSet.add(node.stage);
        grew = true;
      }
    }
  }
  const impactedStages = dependencyCluster.map((item) => item.stage).filter((stage) => impactedStageSet.has(stage));
  const unimpactedStages = dependencyCluster.map((item) => item.stage).filter((stage) => !impactedStageSet.has(stage));
  return { preGenerationPlans, seedStages, impactedStages, unimpactedStages };
};
if (planMode) {
  const impact = computeImpact();
  console.log(JSON.stringify({
    status: "WRITE_APPROVAL_REQUIRED",
    pipeline: pipeline.map(([name, script]) => ({ name, script: path.relative(repositoryRoot, script).split(path.sep).join("/") })),
    passes: 2,
    cleanChecks: pipeline.length,
    reverseChecks: reverseChecks.map((script) => path.relative(repositoryRoot, script).split(path.sep).join("/")),
    impactAnalysis: { dependencyCluster, ...impact },
    finalGate: "dual JS/Python full dependency closure",
    proofExecuted: false,
  }, null, 2));
  process.exit(0);
}

const run = (command, commandArgs, label, options = {}) => {
  const result = spawnSync(command, commandArgs, { cwd: repositoryRoot, encoding: "utf8", maxBuffer: 64 * 1024 * 1024, input: options.input });
  assert.notEqual(result.status, null, `${label}: failed to start: ${result.error ?? result.stderr}`);
  if (result.status !== 0) {
    process.stderr.write(result.stdout ?? "");
    process.stderr.write(result.stderr ?? "");
  }
  assert.equal(result.status, 0, `${label}: nonzero exit ${result.status}`);
  return { label, status: result.status, stdout: result.stdout.trim(), stderr: result.stderr.trim() };
};
const allowed = new Set([".json", ".k", ".md", ".mjs", ".patch", ".py", ".sh", ".thy"]);
const sha256 = (value) => crypto.createHash("sha256").update(value).digest("hex");
const fileSha256 = (value) => sha256(fs.readFileSync(value));
const stable = (value) => {
  if (Array.isArray(value)) return `[${value.map(stable).join(",")}]`;
  if (value && typeof value === "object") return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stable(value[key])}`).join(",")}}`;
  return JSON.stringify(value);
};
const scopeSnapshot = (root = repositoryRoot) => {
  const records = [];
  const roots = [path.join(root, "formal", "kevm", "row-bundles", "abi-04"), path.join(root, "evidence", "end-to-end-refinement", "row-bundles", "abi-04")];
  const excluded = `${path.join(root, "formal", "kevm", "row-bundles", "abi-04", "anti-drift", "generated")}${path.sep}`;
  const visit = (directory) => {
    if (!fs.existsSync(directory)) return;
    for (const entry of fs.readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0)) {
      const target = path.join(directory, entry.name);
      if (entry.isDirectory()) visit(target);
      else if (entry.isFile() && (allowed.has(path.extname(entry.name)) || entry.name === "ROOT") && !target.startsWith(excluded)) records.push({ path: path.relative(root, target).split(path.sep).join("/"), sha256: sha256(fs.readFileSync(target)) });
    }
  };
  for (const scopeRoot of roots) visit(scopeRoot);
  return records.sort((a, b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0);
};
const snapshotSha256 = (snapshot) => sha256(Buffer.from(JSON.stringify(snapshot)));
const snapshotDelta = (before, after) => {
  const beforeByPath = new Map(before.map((item) => [item.path, item.sha256]));
  const afterByPath = new Map(after.map((item) => [item.path, item.sha256]));
  const added = [...afterByPath.keys()].filter((item) => !beforeByPath.has(item)).sort();
  const removed = [...beforeByPath.keys()].filter((item) => !afterByPath.has(item)).sort();
  const changed = [...afterByPath.keys()].filter((item) => beforeByPath.has(item) && beforeByPath.get(item) !== afterByPath.get(item)).sort();
  return { added, removed, changed, changedPaths: [...added, ...changed].sort() };
};

const { preGenerationPlans, seedStages, impactedStages, unimpactedStages } = computeImpact();
// ABI-04 static materialization is cheap relative to proof. Until action-level
// read tracing proves the impact graph complete, execute the full static
// pipeline. Impact analysis remains evidence only and never suppresses a stage.
const executionPipeline = pipeline;

const jsVerifier = path.join(rowDir, "anti-drift", "verify-closure.mjs");
const pythonVerifier = path.join(rowDir, "anti-drift", "verify_closure.py");
const captureClosureVerdict = (command, commandArgs, label) => {
  const result = spawnSync(command, commandArgs, { cwd: repositoryRoot, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  assert.notEqual(result.status, null, `${label}: failed to start: ${result.error ?? result.stderr}`);
  let verdict;
  try { verdict = JSON.parse(result.stdout); } catch (error) { throw new Error(`${label}: invalid JSON verdict: ${error.message}\n${result.stdout}\n${result.stderr}`); }
  assert.equal(verdict.exitCode, result.status, `${label}: declared/process exit mismatch`);
  return verdict;
};
const preflightJs = captureClosureVerdict(process.execPath, [jsVerifier, "--full"], "preflight/js-closure");
const preflightPython = captureClosureVerdict(python, [pythonVerifier, "--full"], "preflight/python-closure");
for (const key of ["closureHashSha256", "counts", "missing", "unexpected", "duplicate", "declaredActualMismatch", "failedExactSets", "invalidationSeeds", "invalidatedDescendants", "prohibitions"]) {
  assert.deepEqual(preflightJs[key], preflightPython[key], `preflight JS/Python disagreement: ${key}`);
}
const preGenerationClosure = {
  status: preflightJs.status,
  closureHashSha256: preflightJs.closureHashSha256,
  jsPythonAgreement: true,
  jsExitCode: preflightJs.exitCode,
  pythonExitCode: preflightPython.exitCode,
  counts: preflightJs.counts,
  failedExactSets: preflightJs.failedExactSets,
  invalidationSeeds: preflightJs.invalidationSeeds,
  invalidatedDescendantSet: preflightJs.invalidatedDescendants,
};

const preGenerationSnapshot = scopeSnapshot();
const materializationRuns = [];
const snapshots = [];
for (const pass of [1, 2]) {
  const results = [];
  const stageChanges = [];
  let priorStageSnapshot = scopeSnapshot();
  for (const [name, script] of executionPipeline) {
    const result = run(process.execPath, [script, "--write"], `pass-${pass}/${name}`);
    const stageSnapshot = scopeSnapshot();
    const delta = snapshotDelta(priorStageSnapshot, stageSnapshot);
    assert.deepEqual(delta.removed, [], `pass-${pass}/${name}: generator removed scoped files`);
    results.push(result);
    stageChanges.push({ stage: name, changedPaths: delta.changedPaths, changedPathsSha256: sha256(Buffer.from(JSON.stringify(delta.changedPaths))) });
    priorStageSnapshot = stageSnapshot;
  }
  const snapshot = priorStageSnapshot;
  materializationRuns.push({ pass, results, stageChanges });
  snapshots.push(snapshot);
}
assert.deepEqual(snapshots[1], snapshots[0], "second deterministic generation is not byte-identical");
for (const stage of materializationRuns[1].stageChanges) assert.deepEqual(stage.changedPaths, [], `second generation changed bytes at stage ${stage.stage}`);
const managedPlanRuns = pipeline.map(([name, script]) => ({ name, script, result: run(process.execPath, [script, "--plan"], `managed-output-plan/${name}`) }));
const planEntries = (name, parsed) => {
  if (["matrix", "dynamic-offset", "dynamic-length", "symbolic-final", "open-topology"].includes(name)) return parsed.changes.files;
  if (["expected-graphs", "orchestration", "finite-symbolic-bridge"].includes(name)) return parsed.changes;
  if (name === "runner-pin") return [{ path: path.relative(repositoryRoot, path.join(rowDir, "dynamic-offset-v1", "run-dynamic-offset-leaf-v4.sh")).split(path.sep).join("/"), status: parsed.change, actualSha256: parsed.actualSha256, expectedSha256: parsed.expectedSha256 }];
  if (name === "aggregate") return [{ path: parsed.output, status: parsed.change, actualSha256: parsed.actualSha256, expectedSha256: parsed.expectedSha256 }];
  if (name === "closure-manifest") return [{ path: parsed.path, status: parsed.change, actualSha256: parsed.actualSha256, expectedSha256: parsed.expectedSha256 }];
  throw new Error(`unknown managed-output plan: ${name}`);
};
const managedStages = managedPlanRuns.map(({ name, script, result }) => {
  const parsed = JSON.parse(result.stdout);
  const entries = planEntries(name, parsed);
  assert.ok(Array.isArray(entries) && entries.length > 0, `${name}: empty managed-output set`);
  const outputs = entries.map((entry) => {
    assert.equal(entry.status, "UNCHANGED", `${name}: managed output is not clean: ${entry.path}`);
    assert.equal(path.isAbsolute(entry.path), false, `${name}: managed output path must be repository-relative`);
    const target = path.join(repositoryRoot, ...entry.path.split("/"));
    assert.ok(fs.existsSync(target), `${name}: missing managed output: ${entry.path}`);
    const actualSha256 = fileSha256(target);
    if (entry.expectedSha256) assert.equal(entry.expectedSha256, actualSha256, `${name}: expected/actual managed output hash mismatch: ${entry.path}`);
    if (entry.actualSha256) assert.equal(entry.actualSha256, actualSha256, `${name}: plan/actual managed output hash mismatch: ${entry.path}`);
    return { path: entry.path, sha256: actualSha256 };
  });
  assert.equal(new Set(outputs.map((item) => item.path)).size, outputs.length, `${name}: duplicate managed output path`);
  return {
    stage: name,
    generator: { path: path.relative(repositoryRoot, script).split(path.sep).join("/"), sha256: fileSha256(script) },
    outputs,
    outputsRootSha256: sha256(Buffer.from(JSON.stringify(outputs))),
  };
});
const managedOutputs = managedStages.flatMap((stage) => stage.outputs);
assert.equal(new Set(managedOutputs.map((item) => item.path)).size, managedOutputs.length, "managed output has multiple generator owners");
const managedOutputPaths = managedOutputs.map((item) => item.path).sort();
const generationEdges = managedStages.flatMap((stage) => stage.outputs.map((output) => ({
  relation: "deterministic-generator-output",
  stage: stage.stage,
  parent: stage.generator,
  child: output,
})));
assert.equal(generationEdges.length, managedOutputs.length);
const firstPassChangedPaths = [...new Set(materializationRuns[0].stageChanges.flatMap((stage) => stage.changedPaths))].sort();
const finalGenerationDelta = snapshotDelta(preGenerationSnapshot, snapshots[0]);
assert.deepEqual(finalGenerationDelta.removed, [], "deterministic generation removed scoped files");
assert.deepEqual(firstPassChangedPaths, finalGenerationDelta.changedPaths, "first-pass stage impact differs from final changed descendant set");
const unexpectedChangedPaths = finalGenerationDelta.changedPaths.filter((item) => !managedOutputPaths.includes(item));
assert.deepEqual(unexpectedChangedPaths, [], "generator changed files outside its exact managed-output set");

const checks = pipeline.map(([name, script]) => run(process.execPath, [script, "--check"], `check/${name}`));
const reverse = reverseChecks.map((script) => run(process.execPath, [script], `reverse/${path.basename(script)}`));

const preservedFrozenInputStages = new Set(["expected-graphs", "runner-pin"]);
const rebuildableOutputPaths = managedStages
  .filter((stage) => !preservedFrozenInputStages.has(stage.stage))
  .flatMap((stage) => stage.outputs.map((output) => output.path))
  .sort();
assert.equal(new Set(rebuildableOutputPaths).size, rebuildableOutputPaths.length, "duplicate rebuildable output path");

const overlaps = (left, right) => {
  const relation = path.relative(left, right);
  return relation === "" || (!relation.startsWith(`..${path.sep}`) && relation !== ".." && !path.isAbsolute(relation));
};
const isolatedRoots = [path.resolve(`${auditRoot}.isolated-a`), path.resolve(`${auditRoot}.isolated-b`)];
for (const isolatedRoot of isolatedRoots) {
  assert.equal(fs.existsSync(isolatedRoot), false, `refusing existing isolated root: ${isolatedRoot}`);
  assert.equal(overlaps(repositoryRoot, isolatedRoot) || overlaps(isolatedRoot, repositoryRoot), false, "isolated root overlaps repository");
}
fs.mkdirSync(path.dirname(auditRoot), { recursive: true });
const canonicalCleanSnapshot = scopeSnapshot();
const isolatedBuilds = [];
for (const [index, isolatedRoot] of isolatedRoots.entries()) {
  const excludedTopLevel = new Set([".git", "out", "sdk"]);
  fs.cpSync(repositoryRoot, isolatedRoot, {
    recursive: true,
    filter: (source) => {
      const relativeSource = path.relative(repositoryRoot, source);
      if (!relativeSource) return true;
      return !excludedTopLevel.has(relativeSource.split(path.sep)[0]);
    },
  });
  for (const outputPath of rebuildableOutputPaths) {
    const target = path.join(isolatedRoot, ...outputPath.split("/"));
    if (fs.existsSync(target)) {
      assert.equal(fs.statSync(target).isFile(), true, `rebuildable output is not a file: ${outputPath}`);
      fs.rmSync(target);
    }
  }
  const isolatedRuns = [];
  for (const [stage, canonicalScript] of pipeline) {
    const script = path.join(isolatedRoot, path.relative(repositoryRoot, canonicalScript));
    const result = spawnSync(process.execPath, [script, "--write"], { cwd: isolatedRoot, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
    assert.notEqual(result.status, null, `isolated-${index + 1}/${stage}: failed to start`);
    assert.equal(result.status, 0, `isolated-${index + 1}/${stage}: nonzero\n${result.stdout}\n${result.stderr}`);
    isolatedRuns.push(stage);
  }
  for (const [stage, canonicalScript] of pipeline) {
    const script = path.join(isolatedRoot, path.relative(repositoryRoot, canonicalScript));
    const result = spawnSync(process.execPath, [script, "--check"], { cwd: isolatedRoot, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
    assert.equal(result.status, 0, `isolated-${index + 1}/check/${stage}: nonzero\n${result.stdout}\n${result.stderr}`);
  }
  for (const canonicalScript of reverseChecks) {
    const script = path.join(isolatedRoot, path.relative(repositoryRoot, canonicalScript));
    const result = spawnSync(process.execPath, [script], { cwd: isolatedRoot, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
    assert.equal(result.status, 0, `isolated-${index + 1}/reverse/${path.basename(script)}: nonzero\n${result.stdout}\n${result.stderr}`);
  }
  const snapshot = scopeSnapshot(isolatedRoot);
  assert.deepEqual(snapshot, canonicalCleanSnapshot, `isolated-${index + 1}: clean materialization differs from canonical`);
  isolatedBuilds.push({
    builder: `fresh-isolated-${index + 1}`,
    status: "PASS_BYTE_IDENTICAL_TO_CANONICAL",
    repositoryInputsCopied: true,
    rebuildableOutputsRemovedBeforeBuild: rebuildableOutputPaths.length,
    preservedFrozenInputStages: [...preservedFrozenInputStages].sort(),
    executedStages: isolatedRuns,
    snapshotFileCount: snapshot.length,
    snapshotSha256: snapshotSha256(snapshot),
  });
}
assert.equal(isolatedBuilds[0].snapshotSha256, isolatedBuilds[1].snapshotSha256, "fresh isolated builders disagree");
for (const isolatedRoot of isolatedRoots) fs.rmSync(isolatedRoot, { recursive: true });
const freshIsolatedReproduction = {
  status: "PASS_TWO_FRESH_ISOLATED_ROOTS_BYTE_IDENTICAL",
  builders: isolatedBuilds,
  rebuildableOutputCount: rebuildableOutputPaths.length,
  rebuildableOutputPathsSha256: sha256(stable(rebuildableOutputPaths)),
  preservedFrozenInputStages: [...preservedFrozenInputStages].sort(),
  scratchRootsRemovedAfterPass: true,
  independentBuilderClaim: false,
};
const negativeTestRoot = path.resolve(`${auditRoot}.negative-tests`);
assert.equal(fs.existsSync(negativeTestRoot), false, `refusing existing negative-test root: ${negativeTestRoot}`);
assert.equal(overlaps(repositoryRoot, negativeTestRoot) || overlaps(negativeTestRoot, repositoryRoot), false, "negative-test root overlaps repository");
const negativeTestRun = run(process.execPath, [failClosedMutationTest, "--out", negativeTestRoot, "--python", python], "fail-closed-mutation-regression");
const negativeTestResultPath = path.join(negativeTestRoot, "worker-result.json");
const negativeTestResult = JSON.parse(fs.readFileSync(negativeTestResultPath, "utf8"));
assert.equal(negativeTestResult.status, "PASS_2_OF_2_EXPECTED_NONZERO");
assert.equal(negativeTestResult.exactScenarioCount, 2);
assert.equal(negativeTestResult.scratchRootsRemovedAfterPass, true);
assert.equal(negativeTestResult.proofExecuted, false);
const failClosedMutationRegression = {
  ...negativeTestResult,
  outputRoot: negativeTestRoot,
  workerResultSha256: fileSha256(negativeTestResultPath),
  stdoutSha256: sha256(Buffer.from(negativeTestRun.stdout)),
};

const generationReceipt = {
  schemaVersion: 1,
  kind: "ABI04_DETERMINISTIC_DESCENDANT_GENERATION_RECEIPT",
  obligationId: "ABI-04",
  status: "PASS_BYTE_IDENTICAL_CLEAN_SECOND_CHECK",
  coordinator: { path: path.relative(repositoryRoot, fileURLToPath(import.meta.url)).split(path.sep).join("/"), sha256: fileSha256(fileURLToPath(import.meta.url)) },
  preGenerationClosure,
  managedOutputExactSet: {
    count: managedOutputs.length,
    uniqueCount: new Set(managedOutputPaths).size,
    pathsSha256: sha256(stable(managedOutputPaths)),
    stages: managedStages,
    edges: generationEdges,
    edgesRootSha256: sha256(stable(generationEdges)),
  },
  impactAnalysis: {
    status: "PASS_EXACT_MANAGED_OUTPUT_SET",
    dependencyCluster,
    preGenerationPlans,
    seedStages,
    impactedStages,
    unimpactedStages,
    changedDescendantSet: finalGenerationDelta.changedPaths,
    changedDescendantSetSha256: sha256(stable(finalGenerationDelta.changedPaths)),
    unexpectedChangedPaths,
    stageChanges: materializationRuns[0].stageChanges,
  },
  deterministicDescendantGeneration: {
    status: "FULL_STATIC_PIPELINE_BYTE_IDENTICAL",
    scope: "FULL_STATIC_PIPELINE_SUPERSET_OF_DECLARED_IMPACT",
    passes: 2,
    preGenerationSnapshotSha256: snapshotSha256(preGenerationSnapshot),
    pass1SnapshotSha256: snapshotSha256(snapshots[0]),
    pass2SnapshotSha256: snapshotSha256(snapshots[1]),
    pass1ChangedDescendants: finalGenerationDelta.changedPaths.length,
    pass2ChangedDescendants: 0,
    secondPassStageChanges: materializationRuns[1].stageChanges,
  },
  cleanSecondCheck: {
    status: "PASS",
    checks: checks.map((item) => item.label),
    count: checks.length,
    reverseChecks: reverse.map((item) => item.label),
    reverseCount: reverse.length,
  },
  freshIsolatedReproduction,
  failClosedMutationRegression,
  proofExecuted: false,
  proofCredit: false,
  centralCredit: false,
};

fs.mkdirSync(path.dirname(auditRoot), { recursive: true });
const closureCoordinator = path.join(rowDir, "anti-drift", "run-closure-gate.mjs");
const closure = run(process.execPath, [closureCoordinator, "--out", auditRoot, "--python", python, "--generation-receipt-stdin"], "dual-closure-gate", { input: JSON.stringify(generationReceipt) });
const workerResultPath = path.join(auditRoot, "worker-result.json");
const workerResult = JSON.parse(fs.readFileSync(workerResultPath, "utf8"));
assert.equal(workerResult.status, "PASS");
assert.equal(workerResult.exitCode, 0);
assert.equal(workerResult.jsPythonAgreement, true);
assert.equal(workerResult.deterministicDoubleGeneration.status, "BYTE_IDENTICAL");
assert.equal(workerResult.generationReceipt.kind, "ABI04_DETERMINISTIC_DESCENDANT_GENERATION_RECEIPT");
assert.equal(workerResult.generationReceipt.status, "PASS_BYTE_IDENTICAL_CLEAN_SECOND_CHECK");
assert.equal(workerResult.generationReceipt.deterministicDescendantGeneration.status, "FULL_STATIC_PIPELINE_BYTE_IDENTICAL");
assert.equal(workerResult.generationReceipt.freshIsolatedReproduction.status, "PASS_TWO_FRESH_ISOLATED_ROOTS_BYTE_IDENTICAL");
assert.equal(workerResult.generationReceipt.failClosedMutationRegression.status, "PASS_2_OF_2_EXPECTED_NONZERO");
assert.equal(workerResult.generationReceipt.cleanSecondCheck.status, "PASS");
for (const key of ["missing", "unexpected", "duplicate", "declaredActualMismatch", "invalidated"]) assert.equal(workerResult.counts[key], 0, `closure count ${key}`);
assert.deepEqual(workerResult.invalidatedDescendantSet, []);
assert.deepEqual(workerResult.failedExactSets, []);

console.log(JSON.stringify({
  status: "PASS_CORRECTED_OPEN_PRODUCT_GENERATION",
  materializationPasses: 2,
  byteIdenticalScopeFiles: snapshots[0].length,
  managedOutputs: managedOutputs.length,
  impactedStages,
  changedDescendants: finalGenerationDelta.changedPaths.length,
  changedDescendantSetSha256: generationReceipt.impactAnalysis.changedDescendantSetSha256,
  cleanChecks: checks.length,
  reverseChecks: reverse.length,
  freshIsolatedReproduction: freshIsolatedReproduction.status,
  failClosedMutationRegression: failClosedMutationRegression.status,
  closureHashSha256: workerResult.closureHashSha256,
  jsPythonAgreement: workerResult.jsPythonAgreement,
  closureCounts: workerResult.counts,
  workerResult: workerResultPath,
  proofExecuted: false,
  proofCredit: false,
  centralCredit: false,
}, null, 2));
