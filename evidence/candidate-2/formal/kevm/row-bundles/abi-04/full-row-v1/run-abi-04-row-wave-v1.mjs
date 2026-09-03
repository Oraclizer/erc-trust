#!/usr/bin/env node
// Coordinates the exact ABI-04 row replay set: imports the six frozen S1 v1
// pairs through an explicit baseCaseId mapping and executes the remaining 150
// records with at most two heavy proof processes.
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { spawn, spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const familyDir = path.dirname(fileURLToPath(import.meta.url));
const rowDir = path.dirname(familyDir);
const repositoryRoot = path.resolve(rowDir, "../../../..");
const coordinatorPath = fileURLToPath(import.meta.url);
const generatorPath = path.join(familyDir, "generate-abi-04-full-row-orchestration-v1.mjs");
const indexPath = path.join(familyDir, "full-row-replay-index-v1.json");
const contractPath = path.join(familyDir, "full-row-wave-contract-v1.json");
const runnerPath = path.join(familyDir, "run-abi-04-replay-v1.mjs");
const analyzerPath = path.join(familyDir, "analyze-abi-04-replay-v1.mjs");
const verifierPath = path.join(familyDir, "verify_abi_04_replay_v1.py");
const reversePath = path.join(familyDir, "reverse-check-abi-04-row-wave-v1.mjs");
const freezeVerifierPath = path.join(rowDir, "anti-drift", "verify-freeze-receipt.py");
const sha256 = (value) => crypto.createHash("sha256").update(value).digest("hex");
const fileSha256 = (filePath) => sha256(fs.readFileSync(filePath));
const readJson = (filePath) => JSON.parse(fs.readFileSync(filePath, "utf8"));
const writeJson = (filePath, value) => fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
const repositoryBound = (relativePath, label) => {
  assert.equal(path.isAbsolute(relativePath), false, `${label}: expected repository-relative path`);
  const resolved = path.resolve(repositoryRoot, ...relativePath.split("/"));
  assert.ok(resolved.startsWith(`${repositoryRoot}${path.sep}`), `${label}: repository path escape`);
  return resolved;
};
const artifactBound = (root, relativePath, label) => {
  assert.equal(path.isAbsolute(relativePath), false, `${label}: expected artifact-relative path`);
  const resolvedRoot = path.resolve(root);
  const resolved = path.resolve(resolvedRoot, ...relativePath.split("/"));
  assert.ok(resolved.startsWith(`${resolvedRoot}${path.sep}`), `${label}: artifact path escape`);
  return resolved;
};
const existingContained = (root, candidate, label, expectedType) => {
  const lexicalRoot = path.resolve(root);
  const lexicalTarget = path.isAbsolute(candidate) ? path.resolve(candidate) : path.resolve(lexicalRoot, ...candidate.split("/"));
  assert.ok(lexicalTarget.startsWith(`${lexicalRoot}${path.sep}`), `${label}: artifact path escape`);
  assert.ok(fs.existsSync(lexicalTarget), `${label}: missing artifact`);
  const realRoot = fs.realpathSync(lexicalRoot);
  const realTarget = fs.realpathSync(lexicalTarget);
  assert.ok(realTarget.startsWith(`${realRoot}${path.sep}`), `${label}: artifact symlink escape`);
  const stat = fs.statSync(realTarget);
  assert.equal(expectedType === "file" ? stat.isFile() : stat.isDirectory(), true, `${label}: unexpected artifact type`);
  return lexicalTarget;
};
const existingContainedFile = (root, candidate, label) => existingContained(root, candidate, label, "file");
const existingContainedDirectory = (root, candidate, label) => existingContained(root, candidate, label, "directory");
const assertRawBinding = (outputRoot, binding, expectedPath, label) => {
  assert.equal(typeof binding?.path, "string", `${label}: missing path`);
  assert.match(binding?.sha256 ?? "", /^[0-9a-f]{64}$/, `${label}: invalid SHA-256`);
  assert.equal(path.isAbsolute(binding.path), true, `${label}: raw artifact path must be absolute`);
  const actualPath = existingContainedFile(outputRoot, binding.path, label);
  assert.equal(path.resolve(actualPath), path.resolve(expectedPath), `${label}: unexpected raw artifact path`);
  assert.equal(fileSha256(actualPath), binding.sha256, `${label}: raw artifact hash drift`);
};
const verifyRawBindings = (outputRoot, report, label, snapshotName) => {
  assert.match(report.proofId ?? "", /^[0-9a-f]{64}$/, `${label}: invalid proof ID`);
  const proofRoot = path.join(outputRoot, "save", report.proofId);
  assertRawBinding(outputRoot, report.proof, path.join(proofRoot, "proof.json"), `${label}/proof`);
  assertRawBinding(outputRoot, report.kcfg, path.join(proofRoot, "kcfg", "kcfg.json"), `${label}/kcfg`);
  assertRawBinding(outputRoot, report.log, path.join(outputRoot, "prove.log"), `${label}/log`);
  assertRawBinding(outputRoot, report.snapshotManifest, path.join(outputRoot, "input-snapshot", snapshotName), `${label}/snapshot-manifest`);
  assert.equal(Array.isArray(report.terminalWitnesses), true, `${label}: terminal witnesses must be an array`);
  assert.equal(report.terminalWitnesses.length, report.graph.terminal, `${label}: terminal witness exact-set mismatch`);
  assert.equal(new Set(report.terminalWitnesses.map((item) => item.nodeId)).size, report.terminalWitnesses.length, `${label}: duplicate terminal witness`);
  for (const witness of report.terminalWitnesses) {
    assert.ok(Number.isSafeInteger(witness.nodeId) && witness.nodeId > 0, `${label}: invalid terminal node ID`);
    assertRawBinding(outputRoot, witness, path.join(proofRoot, "kcfg", "nodes", `${witness.nodeId}.json`), `${label}/terminal/${witness.nodeId}`);
  }
  return {
    proof: report.proof.sha256, kcfg: report.kcfg.sha256, log: report.log.sha256,
    snapshotManifest: report.snapshotManifest.sha256,
    terminalWitnesses: report.terminalWitnesses.map((item) => ({ nodeId: item.nodeId, sha256: item.sha256 })),
  };
};
const s1Comparable = (value) => ({ ...value, expectedGraphContract: { sha256: value.expectedGraphContract.sha256 } });
const strippedClaimSha256 = (claimPath) => {
  const source = fs.readFileSync(claimPath);
  const newline = source.indexOf(10);
  assert.ok(newline > 0 && source.subarray(0, newline).toString("utf8").startsWith("requires "), `claim prelude missing: ${claimPath}`);
  return sha256(source.subarray(newline + 1));
};
const verifySourceBindings = (value, label = "sourceBinding") => {
  if (Array.isArray(value)) return value.forEach((item, index) => verifySourceBindings(item, `${label}/${index}`));
  if (!value || typeof value !== "object") return;
  if (typeof value.path === "string" && typeof value.sha256 === "string") {
    assert.match(value.sha256, /^[0-9a-f]{64}$/, `${label}: SHA-256 format`);
    const target = repositoryBound(value.path, label);
    assert.ok(fs.existsSync(target), `${label}: missing bound file`);
    assert.equal(fileSha256(target), value.sha256, `${label}: bound hash drift`);
  }
  for (const [key, child] of Object.entries(value)) verifySourceBindings(child, `${label}/${key}`);
};

function parseArgs(argv) {
  const args = { mode: null, outputRoot: null, closureRoot: null, s1Root: null, python: "/usr/bin/python3.14", maxHeavy: 2 };
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === "--run" || argv[i] === "--plan") args.mode = argv[i].slice(2);
    else if (argv[i] === "--output-root") args.outputRoot = argv[++i];
    else if (argv[i] === "--closure-freeze-root") args.closureRoot = argv[++i];
    else if (argv[i] === "--s1-wave-root") args.s1Root = argv[++i];
    else if (argv[i] === "--python") args.python = argv[++i];
    else if (argv[i] === "--max-heavy") args.maxHeavy = Number.parseInt(argv[++i], 10);
    else throw new Error(`unknown argument: ${argv[i]}`);
  }
  assert.ok(["run", "plan"].includes(args.mode), "use --run or --plan");
  for (const [name, value] of [["output root", args.outputRoot], ["closure freeze root", args.closureRoot], ["S1 wave root", args.s1Root]]) assert.ok(value, `missing ${name}`);
  assert.ok(path.isAbsolute(args.outputRoot) && path.isAbsolute(args.closureRoot) && path.isAbsolute(args.s1Root), "all roots must be absolute");
  assert.ok([1, 2].includes(args.maxHeavy), "max-heavy must be 1 or 2");
  return args;
}

function run(command, commandArgs, options = {}) {
  const result = spawnSync(command, commandArgs, { cwd: repositoryRoot, encoding: "utf8", maxBuffer: 128 * 1024 * 1024, ...options });
  assert.notEqual(result.status, null, `failed to start: ${command}`);
  return result;
}

function runJson(command, commandArgs, label, accepted = [0]) {
  const result = run(command, commandArgs);
  assert.ok(accepted.includes(result.status), `${label} failed (${result.status}): ${result.stderr || result.stdout}`);
  return JSON.parse(result.stdout);
}

function walkFiles(directory) {
  const result = [];
  const visit = (current) => {
    for (const entry of fs.readdirSync(current, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
      const target = path.join(current, entry.name);
      if (entry.isDirectory()) visit(target); else if (entry.isFile()) result.push(target);
    }
  };
  visit(directory);
  return result;
}
const treeManifest = (directory) => walkFiles(directory).map((filePath) => ({ path: path.relative(directory, filePath).split(path.sep).join("/"), sha256: fileSha256(filePath), bytes: fs.statSync(filePath).size }));
const core = (value) => ({ status: value.status, replayId: value.replayId, semanticClaimId: value.semanticClaimId, executionClaimId: value.executionClaimId, side: value.side, executionSide: value.executionSide, proofId: value.proofId, processExitCode: value.processExitCode, launcherExitCode: value.launcherExitCode, graph: value.graph, inputIntegrityStatus: value.inputIntegrityStatus, ownedSessionSurvivorCount: value.ownedSessionSurvivorCount, claimSourceSha256: value.claimSourceSha256, strippedClaimSha256: value.strippedClaimSha256, definitionKoreSha256: value.definitionKoreSha256, compiledJsonSha256: value.compiledJsonSha256, terminalWitnessObservation: value.terminalWitnessObservation, closureFreezeUnchanged: value.closureFreezeUnchanged });
const sleep = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));

function verifyHistoricalS1(s1Root, index, python) {
  const known = index.importPolicy.knownAuthoritativeS1;
  assert.ok(known, "missing known authoritative S1 anchor");
  assert.equal(path.resolve(s1Root), path.resolve(known.absoluteRoot), "S1 root differs from precommitted authoritative root");
  const workerPath = path.join(s1Root, "worker-result.json");
  const replayPath = path.join(s1Root, "wave-replay-result-v1.json");
  const authoritativePath = path.join(s1Root, "authoritative-wave-result-v1.json");
  const reversePathInRoot = path.join(s1Root, "wave-reverse-check-v1.json");
  for (const required of [workerPath, replayPath, authoritativePath, reversePathInRoot]) assert.ok(fs.existsSync(required), `missing S1 artifact: ${required}`);
  const worker = readJson(workerPath);
  const replay = readJson(replayPath);
  const authoritative = readJson(authoritativePath);
  const reverse = readJson(reversePathInRoot);
  assert.equal(fileSha256(workerPath), known.workerResultSha256, "S1 worker hash differs from precommit");
  assert.equal(fileSha256(replayPath), known.replayResultSha256, "S1 replay hash differs from precommit");
  assert.equal(fileSha256(authoritativePath), known.authoritativeResultSha256, "S1 authoritative result hash differs from precommit");
  assert.equal(fileSha256(reversePathInRoot), known.independentReverseSha256, "S1 reverse hash differs from precommit");
  assert.equal(worker.status, "PASS_S1_6_OF_6_STRICT_ROW_STILL_OPEN");
  assert.equal(worker.exactPairs, 6); assert.equal(worker.exactReplays, 12);
  assert.equal(worker.proofCredit, true); assert.equal(worker.centralCredit, false);
  assert.equal(fileSha256(replayPath), worker.replayResult.sha256);
  assert.equal(fileSha256(authoritativePath), worker.authoritativeWaveResult.sha256);
  assert.equal(fileSha256(reversePathInRoot), worker.reverseCheck.sha256);
  assert.equal(reverse.status, "PASS_S1_6_OF_6_EXACT_REPLAY_AND_BINDER_SET_ROW_OPEN");
  assert.equal(replay.replays.length, 12);
  assert.deepEqual(replay.closureBefore, replay.closureAfter);
  const historicalFreezeRoot = replay.closureFreezeRoot;
  assert.equal(path.resolve(historicalFreezeRoot), path.resolve(known.historicalFreeze.absoluteRoot), "historical S1 freeze root differs from precommit");
  const historicalClosure = runJson(python, [freezeVerifierPath, "--root", historicalFreezeRoot, "--require-pass"], "historical S1 freeze verification");
  assert.equal(historicalClosure.status, "PASS");
  assert.equal(historicalClosure.workerResultSha256, replay.closureBefore.workerResultSha256);
  assert.equal(historicalClosure.closureHashSha256, replay.closureBefore.closureHashSha256);
  assert.equal(historicalClosure.workerResultSha256, known.historicalFreeze.workerResultSha256);
  assert.equal(historicalClosure.closureHashSha256, known.historicalFreeze.closureHashSha256);
  const byId = new Map(replay.replays.map((item) => [item.replayId, item]));
  const imported = [];
  for (let ordinal = 0; ordinal < index.records.length; ordinal += 1) {
    const target = index.records[ordinal];
    if (target.sourceFamily !== "DYNAMIC_OFFSET_V1_REFINEMENT") continue;
    const suffix = target.executionSide === "canonical-positive" ? "canonical-positive" : "unchanged-claim-mutant-negative";
    const sourceReplayId = `${target.executionClaimId}::${suffix}`;
    const source = byId.get(sourceReplayId);
    assert.ok(source, `missing mapped S1 replay: ${sourceReplayId}`);
    const claimPath = repositoryBound(target.claim.path, `${target.replayId}/current-claim`);
    assert.equal(fileSha256(claimPath), target.claim.sha256, `${target.replayId}: current claim hash drift`);
    assert.equal(strippedClaimSha256(claimPath), target.strippedClaimSha256, `${target.replayId}: current stripped claim hash drift`);
    assert.equal(source.outputRoot, path.posix.join("replays", `${String(source.ordinal).padStart(3, "0")}-${target.endpointId}`, source.runnerSide));
    const leafRoot = existingContainedDirectory(s1Root, source.outputRoot, `${sourceReplayId}/output-root`);
    assert.equal(source.analysisJs.path, path.posix.join(source.outputRoot, "analysis-js.json"));
    assert.equal(source.analysisPython.path, path.posix.join(source.outputRoot, "analysis-python.json"));
    const jsPath = existingContainedFile(s1Root, source.analysisJs.path, `${sourceReplayId}/analysis-js`);
    const pyPath = existingContainedFile(s1Root, source.analysisPython.path, `${sourceReplayId}/analysis-python`);
    assert.equal(fileSha256(jsPath), source.analysisJs.sha256);
    assert.equal(fileSha256(pyPath), source.analysisPython.sha256);
    const js = readJson(jsPath); const py = readJson(pyPath);
    assert.equal(js.status, "PASS"); assert.equal(py.status, "PASS");
    assert.equal(js.claimId, target.executionClaimId); assert.equal(py.claimId, target.executionClaimId);
    assert.equal(js.sourceClaimSha256, target.claim.sha256);
    assert.equal(py.analysisSha256, fileSha256(jsPath));
    assert.equal(py.expectedGraphContractSha256, js.expectedGraphContract.sha256);
    assert.ok(py.verifiedSnapshotFiles > 0);
    assert.deepEqual(js.graph, py.graph); assert.equal(js.inputIntegrityStatus, "PASS");
    assert.equal(js.ownedSessionSurvivorCount, 0);
    const snapshotAnalyzer = existingContainedFile(leafRoot, path.posix.join("input-snapshot", "analyze-dynamic-offset-replay-v1.mjs"), `${sourceReplayId}/snapshot-analyzer`);
    const snapshotVerifier = existingContainedFile(leafRoot, path.posix.join("input-snapshot", "verify-dynamic-offset-replay-v1.py"), `${sourceReplayId}/snapshot-verifier`);
    const snapshotExpected = existingContainedFile(leafRoot, path.posix.join("input-snapshot", "expected-graph-contract.json"), `${sourceReplayId}/snapshot-expected`);
    assert.equal(fileSha256(snapshotAnalyzer), js.analysisToolSha256);
    assert.equal(fileSha256(snapshotVerifier), js.independentVerifierSha256);
    assert.equal(fileSha256(snapshotExpected), source.expectedGraphSha256);
    assert.equal(fileSha256(snapshotExpected), js.expectedGraphContract.sha256);
    assert.equal(js.expectedGraphContract.path, source.expectedGraphPath);
    const freshJs = runJson(process.execPath, [snapshotAnalyzer, leafRoot, snapshotExpected], `${sourceReplayId}: S1 raw JavaScript reanalysis`);
    assert.equal(freshJs.expectedGraphContract.path, snapshotExpected);
    assert.deepEqual(s1Comparable(freshJs), s1Comparable(js), `${sourceReplayId}: S1 stored/fresh JavaScript analysis mismatch`);
    const freshPy = runJson(python, [snapshotVerifier, "--output-root", leafRoot, "--expected", snapshotExpected, "--analysis", jsPath], `${sourceReplayId}: S1 raw Python reanalysis`);
    assert.deepEqual(freshPy, py, `${sourceReplayId}: S1 stored/fresh Python analysis mismatch`);
    const rawStored = verifyRawBindings(leafRoot, js, `${sourceReplayId}/stored-js`, "snapshot-files.sha256");
    const rawFresh = verifyRawBindings(leafRoot, freshJs, `${sourceReplayId}/fresh-js`, "snapshot-files.sha256");
    assert.deepEqual(rawFresh, rawStored, `${sourceReplayId}: S1 raw evidence binding mismatch`);
    imported.push({
      ordinal: ordinal + 1, replayId: target.replayId, semanticClaimId: target.semanticClaimId,
      executionClaimId: target.executionClaimId, provenance: "IMPORTED_S1_EXACT_GRAPH", sourceReplayId,
      status: "PASS", outputRoot: source.outputRoot,
      analysisJs: { path: source.analysisJs.path, sha256: source.analysisJs.sha256 },
      analysisPython: { path: source.analysisPython.path, sha256: source.analysisPython.sha256 },
      proofId: js.proofId, graph: js.graph, rawEvidence: rawStored,
    });
  }
  assert.equal(imported.length, 12);
  return {
    records: imported, worker: { path: workerPath, sha256: fileSha256(workerPath) },
    replay: { path: replayPath, sha256: fileSha256(replayPath) }, authoritative: { path: authoritativePath, sha256: fileSha256(authoritativePath) },
    reverse: { path: reversePathInRoot, sha256: fileSha256(reversePathInRoot), status: reverse.status },
    historicalFreeze: { root: historicalFreezeRoot, workerResultSha256: historicalClosure.workerResultSha256, closureHashSha256: historicalClosure.closureHashSha256 }, currentClaimHashesVerified: 12,
  };
}

async function spawnCapture(command, args, cwd) {
  return await new Promise((resolve, reject) => {
    const child = spawn(command, args, { cwd, stdio: ["ignore", "pipe", "pipe"] });
    const stdout = []; const stderr = [];
    child.stdout.on("data", (chunk) => stdout.push(chunk)); child.stderr.on("data", (chunk) => stderr.push(chunk));
    child.once("error", reject); child.once("exit", (code, signal) => resolve({ child, code, signal, stdout: Buffer.concat(stdout).toString("utf8"), stderr: Buffer.concat(stderr).toString("utf8") }));
  });
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const generationCheck = run(process.execPath, [generatorPath, "--check"]);
  assert.equal(generationCheck.status, 0, `full-row generated model is stale: ${generationCheck.stderr || generationCheck.stdout}`);
  const index = readJson(indexPath);
  const contract = readJson(contractPath);
  assert.equal(index.kind, "ABI04_FULL_ROW_REPLAY_INDEX_V1");
  assert.equal(contract.kind, "ABI04_FULL_ROW_WAVE_CONTRACT_V1");
  assert.equal(index.records.length, 162);
  assert.equal(new Set(index.records.map((item) => item.replayId)).size, 162);
  assert.equal(index.recordsRootSha256, sha256(Buffer.from(JSON.stringify(index.records))), "record root mismatch");
  assert.equal(contract.replayIndex.sha256, fileSha256(indexPath), "contract/index hash mismatch");
  assert.equal(contract.replayIndex.semanticClaimsRootSha256, index.semanticClaimsRootSha256);
  assert.equal(contract.replayIndex.recordsRootSha256, index.recordsRootSha256);
  assert.deepEqual(contract.sourceBinding, index.sourceBinding, "contract/index source binding mismatch");
  assert.deepEqual(contract.exactSet, index.exactSet, "contract/index exact set mismatch");
  assert.deepEqual(contract.executionPolicy, index.executionPolicy, "contract/index execution policy mismatch");
  assert.deepEqual(contract.importPolicy, index.importPolicy, "contract/index import policy mismatch");
  assert.deepEqual(contract.acceptancePolicy, index.acceptancePolicy, "contract/index acceptance policy mismatch");
  assert.equal(contract.requiredFinalStatus, "PASS_162_OF_162_REPLAY_SET_ROW_OPEN_PENDING_ATTESTATION");
  assert.equal(process.execPath, index.toolchain.node.executable, "wave coordinator must run under pinned POSIX Node");
  assert.equal(args.python, index.toolchain.python.executable, "wave Python differs from pinned contract");
  for (const key of ["node", "python", "bash", "kevm", "kprove", "koreRpc", "setsid", "timeout", "ps"]) {
    const item = index.toolchain[key];
    assert.ok(item && path.posix.isAbsolute(item.executable), `${key}: missing absolute executable`);
    assert.equal(fileSha256(item.executable), item.sha256, `${key}: executable hash drift`);
  }
  verifySourceBindings(index.sourceBinding);
  for (const record of index.records) {
    assert.match(record.semanticClaimId, /^ABI04-[a-z0-9-]+$/);
    assert.match(record.executionClaimId, /^ABI04-[a-z0-9-]+$/);
    assert.match(record.replayId, /^ABI04-[a-z0-9-]+::(?:canonical-positive|unchanged-claim-mutant-negative)$/);
    const claimPath = repositoryBound(record.claim.path, `${record.replayId}/claim`);
    assert.equal(fileSha256(claimPath), record.claim.sha256, `${record.replayId}: live claim hash drift`);
    assert.equal(strippedClaimSha256(claimPath), record.strippedClaimSha256, `${record.replayId}: stripped claim hash drift`);
  }
  assert.equal(index.sourceBinding.tools.waveCoordinator.sha256, fileSha256(coordinatorPath));
  assert.equal(index.sourceBinding.tools.runner.sha256, fileSha256(runnerPath));
  assert.equal(index.sourceBinding.tools.javascriptAnalyzer.sha256, fileSha256(analyzerPath));
  assert.equal(index.sourceBinding.tools.pythonVerifier.sha256, fileSha256(verifierPath));
  assert.equal(index.sourceBinding.tools.reverseCheck.sha256, fileSha256(reversePath));
  const currentClosure = runJson(args.python, [freezeVerifierPath, "--root", args.closureRoot, "--repository-root", repositoryRoot, "--require-pass"], "current closure freeze verification");
  assert.equal(currentClosure.status, "PASS");
  const s1 = verifyHistoricalS1(args.s1Root, index, args.python);
  const jobs = index.records.map((record, ordinal) => ({ record, ordinal: ordinal + 1 })).filter(({ record }) => record.sourceFamily !== "DYNAMIC_OFFSET_V1_REFINEMENT");
  assert.equal(jobs.length, 150);
  if (args.mode === "plan") {
    const commands = [];
    for (const job of jobs) {
      const prospectiveRelative = path.posix.join("replays", `${String(job.ordinal).padStart(3, "0")}-${job.record.semanticClaimId.replace(/^ABI04-/, "")}`, job.record.executionSide);
      const prospective = artifactBound(args.outputRoot, prospectiveRelative, `${job.record.replayId}/prospective-output-root`);
      const result = run(process.execPath, [runnerPath, "--print-command", "--replay-id", job.record.replayId, "--output-root", prospective, "--closure-freeze-root", args.closureRoot, "--python", args.python, "--preverified-closure-worker-sha256", currentClosure.workerResultSha256, "--preverified-closure-hash-sha256", currentClosure.closureHashSha256]);
      assert.equal(result.status, 0, `print command failed for ${job.record.replayId}: ${result.stderr}`);
      const printed = JSON.parse(result.stdout);
      assert.equal(printed.status, "PASS_NO_HEAVY_PROOF_EXECUTED");
      assert.equal(printed.replayId, job.record.replayId);
      commands.push({ ordinal: job.ordinal, replayId: job.record.replayId, commandSha256: sha256(Buffer.from(JSON.stringify(printed.command))) });
    }
    process.stdout.write(`${JSON.stringify({ schemaVersion: 1, kind: "ABI04_FULL_ROW_WAVE_PREFLIGHT_V1", status: "PASS_NO_HEAVY_PROOF_EXECUTED", exactRecords: 162, importedS1Records: 12, exactPrintCommands: 150, maxConcurrentHeavyProofs: args.maxHeavy, replayIndexSha256: fileSha256(indexPath), waveContractSha256: fileSha256(contractPath), currentClosure, historicalS1: { workerResultSha256: s1.worker.sha256, replayResultSha256: s1.replay.sha256, reverseStatus: s1.reverse.status, closureHashSha256: s1.historicalFreeze.closureHashSha256 }, commandsRootSha256: sha256(Buffer.from(JSON.stringify(commands))), proofExecuted: false, proofCredit: false, centralCredit: false }, null, 2)}\n`);
    return;
  }
  assert.equal(fs.existsSync(args.outputRoot), false, `refusing existing wave root: ${args.outputRoot}`);
  fs.mkdirSync(path.join(args.outputRoot, "replays"), { recursive: true });
  fs.copyFileSync(indexPath, path.join(args.outputRoot, "full-row-replay-index-v1.json"));
  fs.copyFileSync(contractPath, path.join(args.outputRoot, "full-row-wave-contract-v1.json"));
  writeJson(path.join(args.outputRoot, "closure-freeze-files-before.json"), treeManifest(args.closureRoot));
  writeJson(path.join(args.outputRoot, "wave-preconditions.json"), { currentClosure, historicalS1: s1, maxHeavy: args.maxHeavy, startedAtUtc: new Date().toISOString(), proofCredit: false, centralCredit: false });

  let next = 0;
  let firstFailure = null;
  const active = new Set();
  const completed = [];
  const pendingOutputs = new Map();
  const coordinatorIdentityResult = run(index.toolchain.ps.executable, ["-o", "pid=,ppid=,sid=,pgid=,stat=,comm=", "-p", String(process.pid)]);
  assert.equal(coordinatorIdentityResult.status, 0, "failed to capture coordinator process identity");
  const coordinatorIdentityColumns = coordinatorIdentityResult.stdout.trim().split(/\s+/);
  assert.ok(coordinatorIdentityColumns.length >= 6, "malformed coordinator process identity");
  const coordinatorPgid = Number(coordinatorIdentityColumns[3]);
  assert.ok(Number.isSafeInteger(coordinatorPgid) && coordinatorPgid > 0, "invalid coordinator PGID");
  const readPositiveInteger = (filePath, label) => {
    const text = fs.readFileSync(filePath, "utf8").trim();
    assert.match(text, /^[1-9][0-9]*$/, `${label}: invalid positive integer`);
    const value = Number(text);
    assert.ok(Number.isSafeInteger(value), `${label}: integer out of range`);
    return value;
  };
  const processStartTimeTicks = (pid) => {
    const stat = fs.readFileSync(`/proc/${pid}/stat`, "utf8").trim();
    const close = stat.lastIndexOf(")");
    assert.ok(close > 0, `malformed /proc/${pid}/stat`);
    const fieldsFromState = stat.slice(close + 1).trim().split(/\s+/);
    const startTimeTicks = fieldsFromState[19];
    assert.match(startTimeTicks ?? "", /^[0-9]+$/, `missing process start time for PID ${pid}`);
    return startTimeTicks;
  };
  const ownedRows = (sid, pgid) => {
    const result = run(index.toolchain.ps.executable, ["-eo", "pid=,ppid=,sid=,pgid=,stat=,comm="]);
    assert.equal(result.status, 0, "proof-session ps audit failed");
    return result.stdout.trim().split("\n").filter(Boolean).map((line) => {
      const columns = line.trim().split(/\s+/);
      assert.ok(columns.length >= 6, `malformed ps row: ${line}`);
      return { raw: line, pid: Number(columns[0]), ppid: Number(columns[1]), sid: Number(columns[2]), pgid: Number(columns[3]), stat: columns[4], comm: columns.slice(5).join(" ") };
    }).filter((row) => row.pid === sid || row.sid === sid || row.pgid === pgid);
  };
  const auditOwnedProofSessions = async () => {
    const errors = [];
    const currentBootId = fs.readFileSync("/proc/sys/kernel/random/boot_id", "utf8").trim();
    for (const [replayId, outputRoot] of pendingOutputs) {
      try {
        if (!fs.existsSync(outputRoot)) continue;
        const birthPath = path.join(outputRoot, "child-birth-receipt.json");
        const pidPath = path.join(outputRoot, "child-pid.txt");
        if (!fs.existsSync(birthPath) && !fs.existsSync(pidPath)) continue;
        const birth = fs.existsSync(birthPath) ? readJson(birthPath) : null;
        const childPid = birth?.pid ?? readPositiveInteger(pidPath, `${replayId}/child-pid`);
        assert.ok(Number.isSafeInteger(childPid) && childPid > 0, `${replayId}: invalid child PID`);
        if (birth) {
          assert.equal(birth.kind, "ABI04_PROOF_CHILD_BIRTH_RECEIPT_V1", `${replayId}: invalid birth receipt kind`);
          assert.equal(birth.bootId, currentBootId, `${replayId}: Linux boot ID changed`);
          assert.match(birth.startTimeTicks ?? "", /^[0-9]+$/, `${replayId}: invalid birth start time`);
          if (fs.existsSync(`/proc/${childPid}/stat`)) assert.equal(processStartTimeTicks(childPid), birth.startTimeTicks, `${replayId}: child PID was reused`);
        }
        if (fs.existsSync(pidPath)) assert.equal(readPositiveInteger(pidPath, `${replayId}/child-pid`), childPid);
        const receiptPath = path.join(outputRoot, "child-session-receipt.json");
        const receipt = fs.existsSync(receiptPath) ? readJson(receiptPath) : null;
        let sid = childPid;
        let pgid = childPid;
        if (receipt) {
          assert.equal(receipt.kind, "ABI04_PROOF_CHILD_SESSION_RECEIPT_V1", `${replayId}: invalid session receipt kind`);
          assert.equal(receipt.pid, childPid); assert.equal(receipt.sid, childPid); assert.equal(receipt.pgid, childPid);
          assert.notEqual(receipt.launcherPgid, receipt.pgid); assert.equal(receipt.bootId, currentBootId);
          if (birth) assert.equal(receipt.startTimeTicks, birth.startTimeTicks);
          sid = receipt.sid; pgid = receipt.pgid;
        }
        const sidPath = path.join(outputRoot, "child-sid.txt");
        const pgidPath = path.join(outputRoot, "child-pgid.txt");
        if (fs.existsSync(sidPath)) assert.equal(readPositiveInteger(sidPath, `${replayId}/child-sid`), sid);
        if (fs.existsSync(pgidPath)) assert.equal(readPositiveInteger(pgidPath, `${replayId}/child-pgid`), pgid);
        let rows = ownedRows(sid, pgid);
        const groups = [...new Set(rows.map((row) => row.pgid))].filter((value) => value > 0 && value !== coordinatorPgid);
        for (const group of groups) try { process.kill(-group, "SIGKILL"); } catch (error) { if (error?.code !== "ESRCH") throw error; }
        for (const row of rows) if (row.pid !== process.pid) try { process.kill(row.pid, "SIGKILL"); } catch (error) { if (error?.code !== "ESRCH") throw error; }
        for (let i = 0; i < 150; i += 1) {
          rows = ownedRows(sid, pgid);
          if (rows.length === 0) break;
          await sleep(100);
        }
        assert.deepEqual(ownedRows(sid, pgid), [], `${replayId}: owned proof session survived final SIGKILL`);
      } catch (error) {
        errors.push(`${replayId}: ${error.message}`);
      }
    }
    assert.deepEqual(errors, [], `proof-session cleanup audit failures:\n${errors.join("\n")}`);
  };
  const childAlive = (child) => child.exitCode === null && child.signalCode === null;
  const waitChild = (child) => childAlive(child) ? new Promise((resolve) => {
    child.once("exit", resolve);
    child.once("error", resolve);
  }) : Promise.resolve();
  let terminationPromise = null;
  const terminateActive = () => {
    if (terminationPromise) return terminationPromise;
    terminationPromise = (async () => {
      let targets = [...active].filter(childAlive);
      for (const child of targets) try { child.kill("SIGTERM"); } catch {}
      await Promise.race([Promise.all(targets.map(waitChild)), sleep(75_000)]);
      targets = [...active].filter(childAlive);
      for (const child of targets) try { child.kill("SIGKILL"); } catch {}
      await Promise.race([Promise.all(targets.map(waitChild)), sleep(15_000)]);
      await auditOwnedProofSessions();
      assert.equal([...active].filter(childAlive).length, 0, "runner processes survived TERM/KILL escalation");
    })();
    return terminationPromise;
  };
  for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"]) process.once(signal, async () => {
    if (!firstFailure) firstFailure = new Error(`wave interrupted by ${signal}`);
    await terminateActive();
    process.exit(signal === "SIGINT" ? 130 : signal === "SIGHUP" ? 129 : 143);
  });
  async function execute(job) {
    const relativeRoot = path.posix.join("replays", `${String(job.ordinal).padStart(3, "0")}-${job.record.semanticClaimId.replace(/^ABI04-/, "")}`, job.record.executionSide);
    const outputRoot = artifactBound(args.outputRoot, relativeRoot, `${job.record.replayId}/output-root`);
    pendingOutputs.set(job.record.replayId, outputRoot);
    const invocation = [runnerPath, "--run", "--replay-id", job.record.replayId, "--output-root", outputRoot, "--closure-freeze-root", args.closureRoot, "--python", args.python];
    const executionPromise = new Promise((resolve, reject) => {
      const child = spawn(process.execPath, invocation, { cwd: repositoryRoot, stdio: ["ignore", "pipe", "pipe"] });
      active.add(child);
      const stdout = []; const stderr = [];
      child.stdout.on("data", (chunk) => stdout.push(chunk)); child.stderr.on("data", (chunk) => stderr.push(chunk));
      child.once("error", (error) => { active.delete(child); reject(error); });
      child.once("exit", (code, signal) => { active.delete(child); resolve({ code, signal, stdout: Buffer.concat(stdout).toString("utf8"), stderr: Buffer.concat(stderr).toString("utf8") }); });
    });
    const execution = await executionPromise;
    if (fs.existsSync(outputRoot)) {
      fs.writeFileSync(path.join(outputRoot, "launcher-stdout.txt"), execution.stdout, "utf8");
      fs.writeFileSync(path.join(outputRoot, "launcher-stderr.txt"), execution.stderr, "utf8");
    }
    assert.equal(execution.signal, null, `${job.record.replayId}: runner signal ${execution.signal}`);
    assert.equal(execution.code, job.record.expectedProcessExitCode, `${job.record.replayId}: runner exit ${execution.code}\n${execution.stderr}`);
    const jsResult = await spawnCapture(process.execPath, [analyzerPath, outputRoot, indexPath], repositoryRoot);
    assert.equal(jsResult.code, 0, `${job.record.replayId}: JS analysis failed: ${jsResult.stderr || jsResult.stdout}`);
    const js = JSON.parse(jsResult.stdout);
    const jsPath = path.join(outputRoot, "analysis-js.json");
    writeJson(jsPath, js);
    const pyResult = await spawnCapture(args.python, [verifierPath, outputRoot, indexPath], repositoryRoot);
    assert.equal(pyResult.code, 0, `${job.record.replayId}: Python verification failed: ${pyResult.stderr || pyResult.stdout}`);
    const py = JSON.parse(pyResult.stdout);
    const pyPath = path.join(outputRoot, "analysis-python.json");
    writeJson(pyPath, py);
    assert.deepEqual(core(js), core(py), `${job.record.replayId}: JS/Python disagreement`);
    const rawJs = verifyRawBindings(outputRoot, js, `${job.record.replayId}/js`, "snapshot-files.json");
    const rawPy = verifyRawBindings(outputRoot, py, `${job.record.replayId}/python`, "snapshot-files.json");
    assert.deepEqual(rawJs, rawPy, `${job.record.replayId}: JS/Python raw evidence disagreement`);
    const leaf = {
      ordinal: job.ordinal, replayId: job.record.replayId, semanticClaimId: job.record.semanticClaimId,
      executionClaimId: job.record.executionClaimId, provenance: "FULL_ROW_V1_NEW_EXECUTION", status: "PASS",
      outputRoot: relativeRoot, runnerExitCode: execution.code, proofId: js.proofId, graph: js.graph,
      analysisJs: { path: path.posix.join(relativeRoot, "analysis-js.json"), sha256: fileSha256(jsPath) },
      analysisPython: { path: path.posix.join(relativeRoot, "analysis-python.json"), sha256: fileSha256(pyPath) }, rawEvidence: rawJs,
    };
    writeJson(path.join(outputRoot, "leaf-result.json"), leaf);
    completed.push(leaf);
    pendingOutputs.delete(job.record.replayId);
  }
  async function worker() {
    while (!firstFailure) {
      const indexNumber = next++;
      if (indexNumber >= jobs.length) return;
      try { await execute(jobs[indexNumber]); }
      catch (error) { if (!firstFailure) firstFailure = error; await terminateActive(); return; }
    }
  }
  await Promise.all(Array.from({ length: args.maxHeavy }, () => worker()));
  if (firstFailure) { await terminateActive(); throw firstFailure; }
  assert.equal(completed.length, 150);
  const importedById = new Map(s1.records.map((item) => [item.replayId, item]));
  const completedById = new Map(completed.map((item) => [item.replayId, item]));
  const records = index.records.map((record) => importedById.get(record.replayId) ?? completedById.get(record.replayId));
  assert.ok(records.every(Boolean), "missing exact row replay result");
  writeJson(path.join(args.outputRoot, "closure-freeze-files-after.json"), treeManifest(args.closureRoot));
  assert.deepEqual(readJson(path.join(args.outputRoot, "closure-freeze-files-after.json")), readJson(path.join(args.outputRoot, "closure-freeze-files-before.json")), "closure freeze changed during wave");
  const postClosure = runJson(args.python, [freezeVerifierPath, "--root", args.closureRoot, "--repository-root", repositoryRoot, "--require-pass"], "post-wave current closure verification");
  assert.deepEqual(postClosure, currentClosure, "pre/post current closure verdict changed");
  const result = {
    schemaVersion: 1, kind: "ABI04_FULL_ROW_WAVE_RESULT_V1", status: "PASS_162_OF_162_REPLAY_SET_ROW_OPEN_PENDING_ATTESTATION",
    obligationId: "ABI-04", exactRecords: 162, importedS1Records: 12, newlyExecutedRecords: 150,
    maxConcurrentHeavyProofs: args.maxHeavy, s1WaveRoot: path.resolve(args.s1Root), closureFreezeRoot: path.resolve(args.closureRoot),
    replayIndex: { path: indexPath, sha256: fileSha256(indexPath), recordsRootSha256: index.recordsRootSha256 },
    waveContract: { path: contractPath, sha256: fileSha256(contractPath) },
    s1WorkerResult: { path: s1.worker.path, sha256: s1.worker.sha256 }, s1ReplayResult: { path: s1.replay.path, sha256: s1.replay.sha256 },
    s1ImportTransition: { historicalFreeze: s1.historicalFreeze, currentFreeze: { root: args.closureRoot, workerResultSha256: currentClosure.workerResultSha256, closureHashSha256: currentClosure.closureHashSha256 }, directClaimHashesCurrent: s1.currentClaimHashesVerified === 12, verifiedCurrentClaimRecords: s1.currentClaimHashesVerified, centralCredit: false },
    closureFreeze: { workerResultSha256: currentClosure.workerResultSha256, closureHashSha256: currentClosure.closureHashSha256, counts: currentClosure.counts },
    records, proofCredit: true, proofCreditBoundary: "ABI04_EXACT_REPLAY_SET_ONLY",
    rowDisposition: "OPEN_PENDING_AGGREGATE_ISABELLE_INDEPENDENT_CENTRAL", centralCredit: false,
  };
  const resultPath = path.join(args.outputRoot, "row-wave-result-v1.json");
  writeJson(resultPath, result);
  const reverseReportPath = path.join(args.outputRoot, "row-wave-reverse-check-v1.json");
  const reverse = runJson(process.execPath, [reversePath, "--wave-root", args.outputRoot, "--s1-wave-root", args.s1Root, "--closure-freeze-root", args.closureRoot, "--python", args.python, "--report", reverseReportPath], "full-row independent reverse");
  assert.equal(reverse.status, "PASS_162_OF_162_REPLAY_SET_ROW_OPEN_PENDING_ATTESTATION");
  const workerResult = {
    schemaVersion: 1, kind: "ABI04_FULL_ROW_WAVE_WORKER_RESULT_V1", status: "PASS_162_OF_162_REPLAY_SET_ROW_OPEN_PENDING_ATTESTATION",
    obligationId: "ABI-04", exactRecords: 162, importedS1Records: 12, newlyExecutedRecords: 150,
    replayIndex: result.replayIndex, waveContract: result.waveContract,
    rowWaveResult: { path: "row-wave-result-v1.json", sha256: fileSha256(resultPath) },
    reverseCheck: { path: "row-wave-reverse-check-v1.json", sha256: fileSha256(reverseReportPath), status: reverse.status },
    closureFreeze: result.closureFreeze, jsPythonAgreement: true, proofCredit: true,
    proofCreditBoundary: "ABI04_EXACT_REPLAY_SET_ONLY", rowDisposition: result.rowDisposition, centralCredit: false,
  };
  writeJson(path.join(args.outputRoot, "worker-result.json"), workerResult);
  process.stdout.write(`${JSON.stringify(workerResult, null, 2)}\n`);
}

main().catch((error) => { process.stderr.write(`${error.stack || error.message}\n`); process.exitCode = 1; });
