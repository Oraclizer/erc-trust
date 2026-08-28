#!/usr/bin/env node
// Runs the exact six-pair/12-replay S1 wave only after a PASS closure freeze.
// This coordinator never grants ABI-04 central credit. Each leaf is accepted
// only after the existing JS analyzer and independent Python verifier agree.
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

const familyDir = path.dirname(fileURLToPath(import.meta.url));
const rowDir = path.dirname(familyDir);
const repositoryRoot = path.resolve(rowDir, "../../../..");
const runnerPath = path.join(familyDir, "run-dynamic-offset-leaf-v4.sh");
const analyzerPath = path.join(familyDir, "analyze-dynamic-offset-replay-v1.mjs");
const verifierPath = path.join(familyDir, "verify-dynamic-offset-replay-v1.py");
const replayIndexPath = path.join(familyDir, "remaining-leaves-replay-index-v2.json");
const waveContractPath = path.join(familyDir, "s1-dynamic-offset-wave-contract-v1.json");
const toolchainContractPath = path.join(familyDir, "s1-toolchain-contract-v1.json");
const closureVerifierPath = path.join(rowDir, "anti-drift", "verify-freeze-receipt.py");
const binderPath = path.join(familyDir, "bind-dynamic-offset-wave-v1.mjs");
const reversePath = path.join(familyDir, "reverse-check-dynamic-offset-wave-v1.mjs");
const selfPath = fileURLToPath(import.meta.url);

const readJson = (filePath) => JSON.parse(fs.readFileSync(filePath, "utf8"));
const sha256 = (value) => crypto.createHash("sha256").update(value).digest("hex");
const fileSha256 = (filePath) => sha256(fs.readFileSync(filePath));
const render = (value) => `${JSON.stringify(value, null, 2)}\n`;
const relative = (root, filePath) => path.relative(root, filePath).split(path.sep).join("/");
const safeName = (value) => {
  assert.match(value, /^[a-z0-9][a-z0-9-]*$/, `unsafe output component: ${value}`);
  return value;
};

function parseArgs() {
  const values = process.argv.slice(2);
  const mode = values.includes("--plan") ? "plan" : values.includes("--preflight") ? "preflight" : values.includes("--run") ? "run" : null;
  assert.ok(mode, "use exactly one of --plan, --preflight, or --run");
  assert.equal(["--plan", "--preflight", "--run"].filter((flag) => values.includes(flag)).length, 1);
  const option = (name, fallback = null) => {
    const index = values.indexOf(name);
    if (index === -1) return fallback;
    assert.ok(values[index + 1] && !values[index + 1].startsWith("--"), `missing ${name} value`);
    return values[index + 1];
  };
  const maxHeavy = Number(option("--max-heavy", "2"));
  assert.ok(Number.isInteger(maxHeavy) && maxHeavy >= 1 && maxHeavy <= 2, "--max-heavy must be 1 or 2");
  return {
    mode,
    outputRoot: option("--output-root"),
    closureRoot: option("--closure-freeze-root"),
    python: option("--python", "python3"),
    maxHeavy,
  };
}

function resolveRepositoryBinding(binding, label) {
  assert.equal(typeof binding?.path, "string", `${label}: path`);
  assert.match(binding.sha256, /^[0-9a-f]{64}$/, `${label}: sha256`);
  const resolved = path.resolve(repositoryRoot, ...binding.path.split("/"));
  const repositoryRelative = path.relative(repositoryRoot, resolved);
  assert.ok(repositoryRelative && repositoryRelative !== ".." && !repositoryRelative.startsWith(`..${path.sep}`) && !path.isAbsolute(repositoryRelative), `${label}: escaped repository`);
  assert.equal(fileSha256(resolved), binding.sha256, `${label}: current hash mismatch`);
  return resolved;
}

function validateFrozenPlan() {
  const replay = readJson(replayIndexPath);
  const wave = readJson(waveContractPath);
  assert.equal(replay.kind, "ABI04_DYNAMIC_OFFSET_EXACT_REPLAY_INDEX");
  assert.equal(replay.exactClaimCount, 6);
  assert.equal(replay.exactReplayCount, 12);
  assert.equal(replay.claims.length, 6);
  assert.equal(wave.contractId, "ABI04-DYNAMIC-OFFSET-S1-WAVE-V1");
  assert.equal(wave.exactReplayCount, 12);
  assert.equal(wave.centralBindingAllowed, false);
  assert.equal(wave.executionPolicy.maxConcurrentHeavyProofs, 2);
  assert.equal(wave.sourceBinding.replayIndex.sha256, fileSha256(replayIndexPath));
  assert.deepEqual(wave.expectedGraphSet, replay.expectedGraphSet, "wave/replay expected-graph set drift");
  assert.deepEqual(wave.leaves.map(({ claimId }) => claimId), replay.claims.map(({ claimId }) => claimId), "wave/replay claim order drift");

  const requiredBindings = {
    runner: runnerPath,
    waveCoordinator: selfPath,
    analysisTool: analyzerPath,
    independentVerifier: verifierPath,
    pairBinder: binderPath,
    waveReverseCheck: reversePath,
    closureFreezeVerifier: closureVerifierPath,
    toolchainContract: toolchainContractPath,
  };
  for (const [name, expectedPath] of Object.entries(requiredBindings)) {
    const binding = replay.sourceBinding[name];
    assert.equal(resolveRepositoryBinding(binding, name), expectedPath, `${name}: path mismatch`);
  }

  const graphSet = replay.expectedGraphSet.graphs;
  assert.equal(replay.expectedGraphSet.exactCount, 12);
  assert.equal(graphSet.length, 12);
  assert.equal(new Set(graphSet.map(({ claimId, side }) => `${claimId}::${side}`)).size, 12);
  const jobs = [];
  for (const [claimIndex, claim] of replay.claims.entries()) {
    safeName(claim.endpointId);
    assert.equal(claim.canonicalPositive.replayId, `${claim.claimId}::canonical-positive`);
    assert.equal(claim.canonicalPositive.runnerSide, "canonical-positive");
    assert.equal(claim.unchangedClaimMutantNegative.replayId, `${claim.claimId}::unchanged-claim-mutant-negative`);
    assert.equal(claim.unchangedClaimMutantNegative.runnerSide, "mutant-negative");
    assert.equal(claim.unchangedClaimMutantNegative.claimSourceUnchanged, true);
    for (const [field, exactSide] of [["canonicalPositive", "canonical-positive"], ["unchangedClaimMutantNegative", "mutant-negative"]]) {
      const side = claim[field];
      const expectedPath = resolveRepositoryBinding(side.expectedGraph, `${claim.claimId}::${exactSide}: expected graph`);
      const graph = readJson(expectedPath);
      const graphBinding = graphSet.find((item) => item.claimId === claim.claimId && item.side === exactSide);
      assert.ok(graphBinding, `${claim.claimId}::${exactSide}: graph-set binding`);
      assert.equal(graphBinding.path, side.expectedGraph.path);
      assert.equal(graphBinding.sha256, side.expectedGraph.sha256);
      assert.equal(graph.claimId, claim.claimId);
      assert.equal(graph.side, exactSide);
      assert.equal(graph.processExitCode, exactSide === "canonical-positive" ? 0 : 1);
      assert.equal(graph.launcherExitCode, exactSide === "canonical-positive" ? 0 : 1);
      assert.deepEqual(graph.graph, side.expectedGraph.graph);
      assert.equal(graph.graph.pending, 0);
      assert.equal(graph.graph.admitted, false);
      jobs.push({
        ordinal: jobs.length + 1,
        claimOrdinal: claimIndex + 1,
        claimId: claim.claimId,
        endpointId: claim.endpointId,
        selector: claim.selector,
        replayId: side.replayId,
        runnerSide: side.runnerSide,
        exactSide,
        expectedExitCode: graph.processExitCode,
        expectedGraphPath: expectedPath,
        expectedGraphRepositoryPath: side.expectedGraph.path,
        expectedGraphSha256: side.expectedGraph.sha256,
      });
    }
  }
  assert.equal(jobs.length, 12);
  assert.equal(new Set(jobs.map(({ replayId }) => replayId)).size, 12);
  return { replay, wave, jobs };
}

function hashTree(root) {
  const records = [];
  const visit = (current) => {
    for (const entry of fs.readdirSync(current, { withFileTypes: true }).sort((a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0)) {
      const target = path.join(current, entry.name);
      assert.equal(entry.isSymbolicLink(), false, `closure freeze contains symlink: ${target}`);
      if (entry.isDirectory()) visit(target);
      else if (entry.isFile()) records.push({ path: relative(root, target), sha256: fileSha256(target) });
      else assert.fail(`unsupported closure freeze entry: ${target}`);
    }
  };
  visit(root);
  assert.ok(records.length > 0, "empty closure freeze root");
  return { files: records, rootSha256: sha256(Buffer.from(JSON.stringify(records))) };
}

const activeGroups = new Set();
let canceledSignal = null;
function terminateActive(signal = "SIGTERM") {
  for (const pid of activeGroups) {
    try { process.kill(-pid, signal); } catch (error) { if (error.code !== "ESRCH") throw error; }
  }
}
function terminateWithEscalation(signal = "SIGTERM") {
  terminateActive(signal);
  const escalation = setTimeout(() => terminateActive("SIGKILL"), 31_000);
  escalation.unref();
}
for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"]) {
  process.on(signal, () => {
    canceledSignal = signal;
    terminateWithEscalation(signal === "SIGINT" ? "SIGINT" : "SIGTERM");
  });
}

function spawnCaptured(command, args, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { cwd: options.cwd ?? repositoryRoot, env: process.env, detached: options.detached ?? false, stdio: ["ignore", "pipe", "pipe"] });
    if (options.detached) activeGroups.add(child.pid);
    const stdout = [];
    const stderr = [];
    child.stdout.on("data", (chunk) => stdout.push(chunk));
    child.stderr.on("data", (chunk) => stderr.push(chunk));
    child.on("error", reject);
    child.on("close", (code, signal) => {
      if (options.detached) activeGroups.delete(child.pid);
      resolve({ code, signal, stdout: Buffer.concat(stdout).toString("utf8"), stderr: Buffer.concat(stderr).toString("utf8") });
    });
  });
}

async function requireClosurePass(python, closureRoot, reportPath) {
  const result = await spawnCaptured(python, [closureVerifierPath, "--root", closureRoot, "--repository-root", repositoryRoot, "--require-pass"], { detached: true });
  if (reportPath) {
    fs.writeFileSync(reportPath, result.stdout, { encoding: "utf8", flag: "wx" });
    if (result.stderr) fs.writeFileSync(`${reportPath}.stderr.txt`, result.stderr, { encoding: "utf8", flag: "wx" });
  }
  assert.equal(result.signal, null, "closure verifier signaled");
  assert.equal(result.code, 0, `closure verifier failed: ${result.stderr}`);
  const report = JSON.parse(result.stdout);
  assert.equal(report.status, "PASS");
  assert.match(report.workerResultSha256, /^[0-9a-f]{64}$/);
  assert.match(report.closureHashSha256, /^[0-9a-f]{64}$/);
  for (const key of ["missing", "unexpected", "duplicate", "declaredActualMismatch", "invalidated"]) assert.equal(report.counts[key], 0, `closure verifier reported nonzero ${key}`);
  return report;
}

async function requireToolchainPreflight(args, frozen, outputRoot, closureRoot) {
  assert.notEqual(process.platform, "win32", "toolchain preflight must run in the pinned POSIX/WSL environment");
  const contract = readJson(toolchainContractPath);
  assert.equal(contract.kind, "ABI04_S1_PINNED_POSIX_TOOLCHAIN_CONTRACT");
  assert.equal(contract.status, "FROZEN_PROOF_FREE_CREDIT_0");
  assert.equal(path.isAbsolute(process.execPath), true, "Node executable must be absolute");
  assert.equal(fs.existsSync(process.execPath), true, "Node executable missing");
  assert.equal(process.execPath, contract.toolchain.node.executable, "Node executable pin mismatch");
  assert.equal(process.version, contract.toolchain.node.version, "Node version pin mismatch");
  assert.equal(fileSha256(process.execPath), contract.toolchain.node.sha256, "Node binary hash mismatch");
  const pythonProbeSource = [
    "import hashlib,json,os,sys",
    "import jsonschema",
    "exe=os.path.realpath(sys.executable)",
    "print(json.dumps({'executable':exe,'version':sys.version.split()[0],'sha256':hashlib.sha256(open(exe,'rb').read()).hexdigest(),'jsonschema':jsonschema.__file__}))",
  ].join(";");
  const pythonProbe = await spawnCaptured(args.python, ["-c", pythonProbeSource], { detached: true });
  assert.equal(pythonProbe.signal, null, "Python preflight signaled");
  assert.equal(pythonProbe.code, 0, `Python/jsonschema preflight failed: ${pythonProbe.stderr}`);
  const python = JSON.parse(pythonProbe.stdout);
  assert.equal(path.isAbsolute(python.executable), true, "Python executable must be absolute");
  assert.match(python.sha256, /^[0-9a-f]{64}$/);
  assert.equal(python.executable, contract.toolchain.python.executable, "Python executable pin mismatch");
  assert.equal(python.version, contract.toolchain.python.version, "Python version pin mismatch");
  assert.equal(python.sha256, contract.toolchain.python.sha256, "Python binary hash mismatch");
  assert.equal(python.jsonschema, contract.toolchain.python.jsonschema, "Python jsonschema pin mismatch");
  const bashProbe = await spawnCaptured(contract.toolchain.bash.executable, ["--version"], { detached: true });
  assert.equal(bashProbe.signal, null, "Bash preflight signaled");
  assert.equal(bashProbe.code, 0, `Bash preflight failed: ${bashProbe.stderr}`);
  assert.equal(bashProbe.stdout.split("\n")[0], contract.toolchain.bash.versionPrefix, "Bash version pin mismatch");
  assert.equal(fileSha256(contract.toolchain.bash.executable), contract.toolchain.bash.sha256, "Bash binary hash mismatch");
  for (const descriptor of [contract.toolchain.kevm, contract.toolchain.kprove, contract.toolchain.koreRpc, contract.toolchain.nodeArchive, contract.toolchain.nodeChecksums]) {
    const target = descriptor.executable ?? descriptor.absoluteFile;
    assert.equal(path.isAbsolute(target), true, `toolchain contract target must be absolute: ${target}`);
    assert.equal(fs.existsSync(target), true, `toolchain contract target missing: ${target}`);
    assert.equal(fileSha256(target), descriptor.sha256, `toolchain contract target hash mismatch: ${target}`);
  }
  const closure = await requireClosurePass(args.python, closureRoot, null);
  const leafPrintChecks = [];
  for (const job of frozen.jobs) {
    const prospectiveLeaf = path.join(outputRoot, "preflight-only", `${String(job.ordinal).padStart(3, "0")}-${job.endpointId}`, job.runnerSide);
    const printed = await spawnCaptured("bash", [runnerPath, "--print-command", job.claimId, job.runnerSide, prospectiveLeaf, closureRoot], { detached: true });
    assert.equal(printed.signal, null, `${job.replayId}: print-command preflight signaled`);
    assert.equal(printed.code, 0, `${job.replayId}: print-command preflight failed: ${printed.stderr}`);
    assert.match(printed.stdout, /expected_exit_code=[01]/, `${job.replayId}: missing expected exit in preflight`);
    leafPrintChecks.push({ replayId: job.replayId, status: "PASS_PINNED_COMMAND", stdoutSha256: sha256(Buffer.from(printed.stdout)) });
  }
  return {
    schemaVersion: 1,
    kind: "ABI04_S1_PROOF_FREE_TOOLCHAIN_PREFLIGHT",
    obligationId: "ABI-04",
    status: "PASS_NO_HEAVY_PROOF_EXECUTED",
    contract: { path: relative(repositoryRoot, toolchainContractPath), sha256: fileSha256(toolchainContractPath) },
    node: { executable: process.execPath, version: process.version, sha256: fileSha256(process.execPath) },
    python,
    bash: { versionLine: bashProbe.stdout.split("\n")[0] },
    closure: { status: closure.status, closureHashSha256: closure.closureHashSha256, workerResultSha256: closure.workerResultSha256 },
    exactReplayPrintChecks: leafPrintChecks,
    exactReplayCount: leafPrintChecks.length,
    maxConcurrentHeavyProofs: args.maxHeavy,
    proofFreeToolchainPreflightRequired: true,
    proofExecuted: false,
    proofCredit: false,
    centralCredit: false,
  };
}

async function runLeaf(job, context) {
  assert.equal(canceledSignal, null, `wave canceled by ${canceledSignal}`);
  const leafRoot = path.join(context.outputRoot, "replays", `${String(job.ordinal).padStart(3, "0")}-${safeName(job.endpointId)}`, job.runnerSide);
  assert.equal(fs.existsSync(leafRoot), false, `stale replay root: ${leafRoot}`);
  fs.mkdirSync(path.dirname(leafRoot), { recursive: true });
  const runner = await spawnCaptured("bash", [runnerPath, job.claimId, job.runnerSide, leafRoot, context.closureRoot], { detached: true });
  fs.writeFileSync(path.join(leafRoot, "wave-runner-stdout.txt"), runner.stdout, "utf8");
  fs.writeFileSync(path.join(leafRoot, "wave-runner-stderr.txt"), runner.stderr, "utf8");
  assert.equal(runner.signal, null, `${job.replayId}: runner signal`);
  assert.equal(runner.code, job.expectedExitCode, `${job.replayId}: runner exit`);
  assert.equal(canceledSignal, null, `wave canceled by ${canceledSignal}`);

  const analysisPath = path.join(leafRoot, "analysis-js.json");
  const analysis = await spawnCaptured(process.execPath, [analyzerPath, leafRoot, job.expectedGraphPath, analysisPath], { detached: true });
  fs.writeFileSync(path.join(leafRoot, "analysis-js.stderr.txt"), analysis.stderr, "utf8");
  assert.equal(analysis.signal, null, `${job.replayId}: JS analyzer signal`);
  assert.equal(analysis.code, 0, `${job.replayId}: JS analyzer failed: ${analysis.stderr}`);
  assert.equal(readJson(analysisPath).status, "PASS");

  const independentPath = path.join(leafRoot, "analysis-python.json");
  const independent = await spawnCaptured(context.python, [verifierPath, "--output-root", leafRoot, "--expected", job.expectedGraphPath, "--analysis", analysisPath, "--report", independentPath], { detached: true });
  fs.writeFileSync(path.join(leafRoot, "analysis-python.stderr.txt"), independent.stderr, "utf8");
  assert.equal(independent.signal, null, `${job.replayId}: Python verifier signal`);
  assert.equal(independent.code, 0, `${job.replayId}: Python verifier failed: ${independent.stderr}`);
  assert.equal(readJson(independentPath).status, "PASS");

  return {
    ...job,
    outputRoot: relative(context.outputRoot, leafRoot),
    runnerExitCode: runner.code,
    analysisJs: { path: relative(context.outputRoot, analysisPath), sha256: fileSha256(analysisPath), status: "PASS" },
    analysisPython: { path: relative(context.outputRoot, independentPath), sha256: fileSha256(independentPath), status: "PASS" },
    status: "PASS_EXACT_GRAPH_JS_PYTHON",
    proofCreditBoundary: "LEAF_REPLAY_ONLY_NOT_CENTRAL_DISCHARGE",
  };
}

async function runPool(jobs, context) {
  const results = new Array(jobs.length);
  let cursor = 0;
  let failure = null;
  const worker = async () => {
    while (!failure && !canceledSignal && cursor < jobs.length) {
      const index = cursor++;
      try { results[index] = await runLeaf(jobs[index], context); }
      catch (error) {
        if (!failure) {
          failure = error;
          terminateWithEscalation();
        }
      }
    }
  };
  await Promise.all(Array.from({ length: context.maxHeavy }, () => worker()));
  if (!failure && canceledSignal) failure = new Error(`wave canceled by ${canceledSignal}`);
  if (failure) throw failure;
  assert.deepEqual(results.map(({ replayId }) => replayId), jobs.map(({ replayId }) => replayId));
  const replayDirectory = path.join(context.outputRoot, "replays");
  const expectedParents = jobs.map((job) => `${String(job.ordinal).padStart(3, "0")}-${job.endpointId}`).sort();
  const actualParents = fs.readdirSync(replayDirectory, { withFileTypes: true });
  assert.ok(actualParents.every((entry) => entry.isDirectory()), "unexpected non-directory in replay root");
  assert.deepEqual(actualParents.map(({ name }) => name).sort(), expectedParents, "replay output-root exact set mismatch");
  for (const job of jobs) {
    const parent = path.join(replayDirectory, `${String(job.ordinal).padStart(3, "0")}-${job.endpointId}`);
    const children = fs.readdirSync(parent, { withFileTypes: true });
    assert.deepEqual(children.map(({ name }) => name), [job.runnerSide], `${job.replayId}: output side exact set`);
    assert.equal(children[0].isDirectory(), true, `${job.replayId}: output side must be a directory`);
  }
  return results;
}

async function main() {
  const args = parseArgs();
  const frozen = validateFrozenPlan();
  const plan = {
    status: "PASS_EXACT_12_REPLAY_PLAN_NO_PROOF_EXECUTED",
    exactPairs: 6,
    exactReplays: 12,
    maxConcurrentHeavyProofs: args.maxHeavy,
    proofFreeToolchainPreflightRequired: true,
    replayIds: frozen.jobs.map(({ replayId }) => replayId),
    proofCredit: false,
    centralCredit: false,
  };
  if (args.mode === "plan") {
    process.stdout.write(render(plan));
    return;
  }

  assert.ok(args.outputRoot && path.isAbsolute(args.outputRoot), "--output-root must be absolute");
  assert.ok(args.closureRoot && path.isAbsolute(args.closureRoot), "--closure-freeze-root must be absolute");
  assert.notEqual(process.platform, "win32", "wave execution must run in the pinned POSIX/WSL environment");
  const outputRoot = path.resolve(args.outputRoot);
  const closureRoot = path.resolve(args.closureRoot);
  const outputParent = path.dirname(outputRoot);
  assert.equal(fs.statSync(outputParent).isDirectory(), true, "wave output parent must already exist");
  assert.equal(fs.realpathSync(outputParent), outputParent, "wave output parent must not traverse a symlink");
  assert.equal(fs.realpathSync(repositoryRoot), repositoryRoot, "repository root must not traverse a symlink");
  assert.equal(fs.realpathSync(closureRoot), closureRoot, "closure freeze root must not traverse a symlink");
  const overlaps = (left, right) => {
    const rel = path.relative(left, right);
    return rel === "" || (!rel.startsWith(`..${path.sep}`) && rel !== ".." && !path.isAbsolute(rel));
  };
  assert.equal(overlaps(repositoryRoot, outputRoot) || overlaps(outputRoot, repositoryRoot), false, "wave root must not overlap repository root");
  assert.equal(overlaps(closureRoot, outputRoot) || overlaps(outputRoot, closureRoot), false, "wave root must not overlap closure freeze root");
  for (const definition of Object.values(frozen.replay.definitions)) {
    const definitionRoot = path.resolve(definition.root);
    assert.equal(overlaps(definitionRoot, outputRoot) || overlaps(outputRoot, definitionRoot), false, `wave root must not overlap definition root: ${definition.root}`);
  }
  assert.equal(fs.existsSync(outputRoot), false, `refusing existing wave root: ${outputRoot}`);
  assert.equal(fs.statSync(closureRoot).isDirectory(), true, "closure freeze root must be a directory");
  const toolchainPreflight = await requireToolchainPreflight(args, frozen, outputRoot, closureRoot);
  fs.mkdirSync(outputRoot, { recursive: false });
  const toolchainPreflightPath = path.join(outputRoot, "toolchain-preflight.json");
  fs.writeFileSync(toolchainPreflightPath, render(toolchainPreflight), { encoding: "utf8", flag: "wx" });
  if (args.mode === "preflight") {
    const preflightResult = {
      ...toolchainPreflight,
      kind: "ABI04_DYNAMIC_OFFSET_S1_PREFLIGHT_WORKER_RESULT",
      outputRoot,
      receipt: { path: "toolchain-preflight.json", sha256: fileSha256(toolchainPreflightPath) },
    };
    fs.writeFileSync(path.join(outputRoot, "worker-result.json"), render(preflightResult), { encoding: "utf8", flag: "wx" });
    process.stdout.write(render({ status: preflightResult.status, exactReplayCount: preflightResult.exactReplayCount, outputRoot, proofExecuted: false, proofCredit: false, centralCredit: false }));
    return;
  }

  const baseResult = {
    schemaVersion: 1,
    kind: "ABI04_DYNAMIC_OFFSET_S1_WAVE_WORKER_RESULT",
    obligationId: "ABI-04",
    stage: "S1",
    status: "RUNNING_CREDIT_0",
    exactPairs: 6,
    exactReplays: 12,
    maxConcurrentHeavyProofs: args.maxHeavy,
    closureFreezeRoot: closureRoot,
    closureFreezeVerifier: { path: relative(repositoryRoot, closureVerifierPath), sha256: fileSha256(closureVerifierPath) },
    replayIndex: { path: relative(repositoryRoot, replayIndexPath), sha256: fileSha256(replayIndexPath) },
    waveContract: { path: relative(repositoryRoot, waveContractPath), sha256: fileSha256(waveContractPath) },
    waveCoordinator: { path: relative(repositoryRoot, selfPath), sha256: fileSha256(selfPath) },
    toolchainPreflight: { path: "toolchain-preflight.json", sha256: fileSha256(toolchainPreflightPath), status: toolchainPreflight.status },
    proofCredit: false,
    centralCredit: false,
  };

  try {
    const beforeReportPath = path.join(outputRoot, "closure-verification-before.json");
    const beforeClosureVerdict = await requireClosurePass(args.python, closureRoot, beforeReportPath);
    assert.equal(canceledSignal, null, `wave canceled by ${canceledSignal}`);
    const closureBefore = hashTree(closureRoot);
    fs.writeFileSync(path.join(outputRoot, "closure-files-before.json"), render(closureBefore), { encoding: "utf8", flag: "wx" });

    const replayResults = await runPool(frozen.jobs, { outputRoot, closureRoot, python: args.python, maxHeavy: args.maxHeavy });
    assert.equal(canceledSignal, null, `wave canceled by ${canceledSignal}`);

    const afterReportPath = path.join(outputRoot, "closure-verification-after.json");
    const afterClosureVerdict = await requireClosurePass(args.python, closureRoot, afterReportPath);
    const closureAfter = hashTree(closureRoot);
    fs.writeFileSync(path.join(outputRoot, "closure-files-after.json"), render(closureAfter), { encoding: "utf8", flag: "wx" });
    assert.deepEqual(closureAfter, closureBefore, "closure freeze changed during wave");
    assert.equal(afterClosureVerdict.closureHashSha256, beforeClosureVerdict.closureHashSha256, "closure DAG hash changed during wave");
    assert.equal(afterClosureVerdict.workerResultSha256, beforeClosureVerdict.workerResultSha256, "closure worker-result changed during wave");
    assert.deepEqual(afterClosureVerdict.counts, beforeClosureVerdict.counts, "closure anomaly counts changed during wave");
    assert.equal(canceledSignal, null, `wave canceled by ${canceledSignal}`);

    const replayResult = {
      ...baseResult,
      kind: "ABI04_DYNAMIC_OFFSET_S1_EXACT_REPLAY_RESULT",
      status: "PASS_12_OF_12_EXACT_REPLAY_JS_PYTHON_CREDIT_BOUNDARY_S1_ONLY",
      closureBefore: {
        reportSha256: fileSha256(beforeReportPath),
        workerResultSha256: beforeClosureVerdict.workerResultSha256,
        closureHashSha256: beforeClosureVerdict.closureHashSha256,
        counts: beforeClosureVerdict.counts,
        repositoryNodesVerified: beforeClosureVerdict.repositoryNodesVerified,
        generationNodesVerified: beforeClosureVerdict.generationNodesVerified,
        filesRootSha256: closureBefore.rootSha256,
        exactFiles: closureBefore.files.length,
        jsPythonClosureAgreement: true,
      },
      closureAfter: {
        reportSha256: fileSha256(afterReportPath),
        workerResultSha256: afterClosureVerdict.workerResultSha256,
        closureHashSha256: afterClosureVerdict.closureHashSha256,
        counts: afterClosureVerdict.counts,
        repositoryNodesVerified: afterClosureVerdict.repositoryNodesVerified,
        generationNodesVerified: afterClosureVerdict.generationNodesVerified,
        filesRootSha256: closureAfter.rootSha256,
        exactFiles: closureAfter.files.length,
        jsPythonClosureAgreement: true,
      },
      replayIds: replayResults.map(({ replayId }) => replayId),
      replays: replayResults,
      proofCreditBoundary: "S1_PAIR_BINDING_ALLOWED_CENTRAL_DISCHARGE_FORBIDDEN",
    };
    const replayResultPath = path.join(outputRoot, "wave-replay-result-v1.json");
    fs.writeFileSync(replayResultPath, render(replayResult), { encoding: "utf8", flag: "wx" });

    const binding = await spawnCaptured(process.execPath, [binderPath, "--write", "--wave-root", outputRoot, "--python", args.python], { detached: true });
    fs.writeFileSync(path.join(outputRoot, "pair-binder-generation.stdout.json"), binding.stdout, { encoding: "utf8", flag: "wx" });
    fs.writeFileSync(path.join(outputRoot, "pair-binder-generation.stderr.txt"), binding.stderr, { encoding: "utf8", flag: "wx" });
    assert.equal(binding.code, 0, `pair binder generation failed: ${binding.stderr}`);
    assert.equal(canceledSignal, null, `wave canceled by ${canceledSignal}`);

    const reverseReportPath = path.join(outputRoot, "wave-reverse-check-v1.json");
    const reverse = await spawnCaptured(process.execPath, [reversePath, "--wave-root", outputRoot, "--python", args.python, "--report", reverseReportPath], { detached: true });
    fs.writeFileSync(path.join(outputRoot, "wave-reverse-check.stdout.json"), reverse.stdout, { encoding: "utf8", flag: "wx" });
    fs.writeFileSync(path.join(outputRoot, "wave-reverse-check.stderr.txt"), reverse.stderr, { encoding: "utf8", flag: "wx" });
    assert.equal(reverse.code, 0, `wave reverse check failed: ${reverse.stderr}`);
    assert.equal(canceledSignal, null, `wave canceled by ${canceledSignal}`);

    const authoritativePath = path.join(outputRoot, "authoritative-wave-result-v1.json");
    const authoritative = readJson(authoritativePath);
    assert.equal(authoritative.status, "PASS_S1_6_OF_6_PAIR_CREDIT_ROW_OPEN");
    const finalResult = {
      ...baseResult,
      status: "PASS_S1_6_OF_6_STRICT_ROW_STILL_OPEN",
      replayResult: { path: relative(outputRoot, replayResultPath), sha256: fileSha256(replayResultPath) },
      authoritativeWaveResult: { path: relative(outputRoot, authoritativePath), sha256: fileSha256(authoritativePath) },
      reverseCheck: { path: relative(outputRoot, reverseReportPath), sha256: fileSha256(reverseReportPath), status: "PASS" },
      exactReplayIds: replayResults.map(({ replayId }) => replayId),
      exactPairBinders: authoritative.pairBinders,
      closureFreeze: {
        closureHashSha256: beforeClosureVerdict.closureHashSha256,
        workerResultSha256: beforeClosureVerdict.workerResultSha256,
        counts: beforeClosureVerdict.counts,
        filesRootSha256: closureBefore.rootSha256,
        jsPythonClosureAgreement: true,
        prePostUnchanged: true,
      },
      proofCredit: true,
      proofCreditBoundary: "S1_DYNAMIC_OFFSET_6_OF_6_ONLY",
      rowDisposition: "OPEN_PENDING_DYNAMIC_LENGTH_HIGH_BITS_SYMBOLIC_162_AGGREGATE_ISABELLE_INDEPENDENT",
      centralCredit: false,
    };
    fs.writeFileSync(path.join(outputRoot, "worker-result.json"), render(finalResult), { encoding: "utf8", flag: "wx" });
    process.stdout.write(render(finalResult));
  } catch (error) {
    terminateWithEscalation();
    const failed = {
      ...baseResult,
      status: "FAIL_CREDIT_0",
      error: String(error?.stack ?? error),
      canceledSignal,
      invalidatedDescendants: ["wave-replay-result-v1.json", "pair-binders/*", "authoritative-wave-result-v1.json", "wave-reverse-check-v1.json"],
      proofCredit: false,
      centralCredit: false,
    };
    const failedPath = path.join(outputRoot, "worker-result.json");
    if (!fs.existsSync(failedPath)) fs.writeFileSync(failedPath, render(failed), { encoding: "utf8", flag: "wx" });
    throw error;
  }
}

await main();
