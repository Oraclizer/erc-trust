#!/usr/bin/env node
// Regression-tests the strict closure gate in disposable repository copies.
// It proves that an unexpected allowed-extension file and a changed parent
// both fail nonzero, agree across JS/Python, and invalidate descendants.
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const antiDir = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(antiDir, "../../../../..");
const args = process.argv.slice(2);
const valueAfter = (flag) => {
  const index = args.indexOf(flag);
  return index >= 0 ? args[index + 1] : null;
};
const outputRoot = path.resolve(valueAfter("--out") ?? "");
const python = valueAfter("--python") ?? (process.platform === "win32" ? "python" : "python3");
assert.ok(valueAfter("--out") && path.isAbsolute(valueAfter("--out")), "--out ABSOLUTE_FRESH_ROOT is required");
assert.equal(fs.existsSync(outputRoot), false, `refusing existing output root: ${outputRoot}`);

const sha256 = (value) => crypto.createHash("sha256").update(value).digest("hex");
const stable = (value) => {
  if (Array.isArray(value)) return `[${value.map(stable).join(",")}]`;
  if (value && typeof value === "object") return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stable(value[key])}`).join(",")}}`;
  return JSON.stringify(value);
};
const scenarios = [
  {
    id: "unexpected-allowed-extension",
    mutate: (root) => {
      const target = path.join(root, "formal", "kevm", "row-bundles", "abi-04", "unexpected-stale-regression.json");
      fs.writeFileSync(target, "{}\n", { encoding: "utf8", flag: "wx" });
    },
    require: (js) => assert.ok(js.unexpected.some((item) => item.kind === "UNEXPECTED_EXACT_NODE"), "unexpected exact node was not rejected"),
  },
  {
    id: "changed-parent-invalidates-descendants",
    mutate: (root) => {
      const target = path.join(root, "formal", "kevm", "row-bundles", "abi-04", "case-matrix.json");
      fs.appendFileSync(target, "\n", "utf8");
    },
    require: (js) => {
      assert.ok(js.declaredActualMismatch.some((item) => item.seedPath === "formal/kevm/row-bundles/abi-04/case-matrix.json"), "changed parent mismatch absent");
      assert.ok(js.invalidatedDescendants.includes("file:formal/kevm/row-bundles/abi-04/bridge/row-bridge.json"), "row bridge was not invalidated");
      assert.ok(js.invalidatedDescendants.includes("file:formal/kevm/row-bundles/abi-04/central-row-gate.json"), "central row gate was not invalidated");
    },
  },
];

fs.mkdirSync(outputRoot, { recursive: false });
const results = [];
for (const scenario of scenarios) {
  const scratchRoot = path.join(outputRoot, `${scenario.id}-repository`);
  fs.cpSync(repositoryRoot, scratchRoot, {
    recursive: true,
    filter: (source) => {
      const repositoryPath = path.relative(repositoryRoot, source);
      if (!repositoryPath) return true;
      return !new Set([".git", "out", "sdk"]).has(repositoryPath.split(path.sep)[0]);
    },
  });
  scenario.mutate(scratchRoot);
  const scratchAnti = path.join(scratchRoot, "formal", "kevm", "row-bundles", "abi-04", "anti-drift");
  const js = spawnSync(process.execPath, [path.join(scratchAnti, "verify-closure.mjs"), "--full"], { cwd: scratchRoot, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  const py = spawnSync(python, [path.join(scratchAnti, "verify_closure.py"), "--full"], { cwd: scratchRoot, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  assert.notEqual(js.status, null, `${scenario.id}: JS failed to start`);
  assert.notEqual(py.status, null, `${scenario.id}: Python failed to start`);
  assert.equal(js.status, 1, `${scenario.id}: JS did not fail closed`);
  assert.equal(py.status, 1, `${scenario.id}: Python did not fail closed`);
  const jsVerdict = JSON.parse(js.stdout);
  const pythonVerdict = JSON.parse(py.stdout);
  for (const key of ["closureHashSha256", "counts", "missing", "unexpected", "duplicate", "declaredActualMismatch", "failedExactSets", "invalidationSeeds", "invalidatedDescendants"]) assert.deepEqual(jsVerdict[key], pythonVerdict[key], `${scenario.id}: JS/Python disagreement: ${key}`);
  scenario.require(jsVerdict);
  const receipt = {
    id: scenario.id,
    status: "PASS_EXPECTED_NONZERO_FAIL_CLOSED",
    jsExitCode: js.status,
    pythonExitCode: py.status,
    closureHashSha256: jsVerdict.closureHashSha256,
    counts: jsVerdict.counts,
    invalidationSeeds: jsVerdict.invalidationSeeds,
    invalidatedDescendants: jsVerdict.invalidatedDescendants,
  };
  fs.writeFileSync(path.join(outputRoot, `${scenario.id}.json`), `${JSON.stringify(receipt, null, 2)}\n`, "utf8");
  results.push(receipt);
  fs.rmSync(scratchRoot, { recursive: true });
}

const result = {
  schemaVersion: 1,
  kind: "ABI04_CLOSURE_FAIL_CLOSED_MUTATION_REGRESSION",
  obligationId: "ABI-04",
  status: "PASS_2_OF_2_EXPECTED_NONZERO",
  exactScenarioCount: results.length,
  scenarios: results,
  scenariosSha256: sha256(stable(results)),
  scratchRootsRemovedAfterPass: true,
  proofExecuted: false,
  proofCredit: false,
  centralCredit: false,
};
fs.writeFileSync(path.join(outputRoot, "worker-result.json"), `${JSON.stringify(result, null, 2)}\n`, "utf8");
console.log(JSON.stringify({ status: result.status, exactScenarioCount: result.exactScenarioCount, scenariosSha256: result.scenariosSha256, workerResult: path.join(outputRoot, "worker-result.json") }, null, 2));
