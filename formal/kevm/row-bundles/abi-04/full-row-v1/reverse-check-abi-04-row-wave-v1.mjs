#!/usr/bin/env node
// Independent post-wave exact-set reconstruction for S1-imported 12 plus the
// 150 row-wide replays. This checker writes only when --report is explicit.
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const familyDir = path.dirname(fileURLToPath(import.meta.url));
const rowDir = path.dirname(familyDir);
const repositoryRoot = path.resolve(rowDir, "../../../..");
const indexPath = path.join(familyDir, "full-row-replay-index-v1.json");
const contractPath = path.join(familyDir, "full-row-wave-contract-v1.json");
const analyzerPath = path.join(familyDir, "analyze-abi-04-replay-v1.mjs");
const verifierPath = path.join(familyDir, "verify_abi_04_replay_v1.py");
const freezeVerifierPath = path.join(rowDir, "anti-drift", "verify-freeze-receipt.py");
const sha256 = (value) => crypto.createHash("sha256").update(value).digest("hex");
const fileSha256 = (filePath) => sha256(fs.readFileSync(filePath));
const readJson = (filePath) => JSON.parse(fs.readFileSync(filePath, "utf8"));
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
  assert.ok(newline > 0 && source.subarray(0, newline).toString("utf8").startsWith("requires "));
  return sha256(source.subarray(newline + 1));
};

function parseArgs(argv) {
  const result = { waveRoot: null, s1Root: null, closureRoot: null, python: "/usr/bin/python3.14", report: null };
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === "--wave-root") result.waveRoot = argv[++i];
    else if (argv[i] === "--s1-wave-root") result.s1Root = argv[++i];
    else if (argv[i] === "--closure-freeze-root") result.closureRoot = argv[++i];
    else if (argv[i] === "--python") result.python = argv[++i];
    else if (argv[i] === "--report") result.report = argv[++i];
    else throw new Error(`unknown argument: ${argv[i]}`);
  }
  assert.ok(result.waveRoot && result.s1Root && result.closureRoot, "--wave-root, --s1-wave-root, and --closure-freeze-root are required");
  assert.ok(path.isAbsolute(result.waveRoot) && path.isAbsolute(result.s1Root) && path.isAbsolute(result.closureRoot), "all roots must be absolute");
  return result;
}

function runJson(command, args, label) {
  const result = spawnSync(command, args, { cwd: repositoryRoot, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  assert.notEqual(result.status, null, `${label} did not start`);
  assert.equal(result.status, 0, `${label} failed: ${result.stderr || result.stdout}`);
  return JSON.parse(result.stdout);
}

const core = (value) => ({
  status: value.status, replayId: value.replayId, semanticClaimId: value.semanticClaimId,
  executionClaimId: value.executionClaimId, side: value.side, executionSide: value.executionSide,
  proofId: value.proofId, processExitCode: value.processExitCode, launcherExitCode: value.launcherExitCode,
  graph: value.graph, inputIntegrityStatus: value.inputIntegrityStatus,
  ownedSessionSurvivorCount: value.ownedSessionSurvivorCount, claimSourceSha256: value.claimSourceSha256,
  strippedClaimSha256: value.strippedClaimSha256, definitionKoreSha256: value.definitionKoreSha256,
  compiledJsonSha256: value.compiledJsonSha256, terminalWitnessObservation: value.terminalWitnessObservation,
  closureFreezeUnchanged: value.closureFreezeUnchanged,
});

function main() {
  const args = parseArgs(process.argv.slice(2));
  const waveRoot = path.resolve(args.waveRoot);
  const s1Root = path.resolve(args.s1Root);
  const requestedClosureRoot = path.resolve(args.closureRoot);
  const index = readJson(indexPath);
  const contract = readJson(contractPath);
  const resultPath = path.join(waveRoot, "row-wave-result-v1.json");
  const result = readJson(resultPath);
  assert.equal(index.kind, "ABI04_FULL_ROW_REPLAY_INDEX_V1");
  assert.equal(contract.kind, "ABI04_FULL_ROW_WAVE_CONTRACT_V1");
  assert.equal(index.recordsRootSha256, sha256(Buffer.from(JSON.stringify(index.records))));
  assert.equal(contract.replayIndex.sha256, fileSha256(indexPath));
  assert.equal(contract.replayIndex.semanticClaimsRootSha256, index.semanticClaimsRootSha256);
  assert.equal(contract.replayIndex.recordsRootSha256, index.recordsRootSha256);
  assert.deepEqual(contract.sourceBinding, index.sourceBinding);
  assert.deepEqual(contract.exactSet, index.exactSet);
  assert.deepEqual(contract.executionPolicy, index.executionPolicy);
  assert.deepEqual(contract.importPolicy, index.importPolicy);
  assert.deepEqual(contract.acceptancePolicy, index.acceptancePolicy);
  assert.equal(process.execPath, index.toolchain.node.executable, "reverse must run under pinned POSIX Node");
  assert.equal(args.python, index.toolchain.python.executable, "reverse Python differs from pinned contract");
  for (const key of ["node", "python", "bash", "kevm", "kprove", "koreRpc", "setsid", "timeout", "ps"]) {
    const item = index.toolchain[key];
    assert.ok(item && path.posix.isAbsolute(item.executable), `${key}: missing absolute executable`);
    assert.equal(fileSha256(item.executable), item.sha256, `${key}: executable hash drift`);
  }
  assert.equal(fileSha256(analyzerPath), index.sourceBinding.tools.javascriptAnalyzer.sha256);
  assert.equal(fileSha256(verifierPath), index.sourceBinding.tools.pythonVerifier.sha256);
  assert.equal(result.kind, "ABI04_FULL_ROW_WAVE_RESULT_V1");
  assert.equal(result.schemaVersion, 1);
  assert.equal(result.obligationId, "ABI-04");
  assert.equal(result.status, "PASS_162_OF_162_REPLAY_SET_ROW_OPEN_PENDING_ATTESTATION");
  assert.equal(result.replayIndex.sha256, fileSha256(indexPath));
  assert.equal(result.waveContract.sha256, fileSha256(contractPath));
  assert.equal(result.s1WaveRoot, s1Root);
  assert.equal(result.exactRecords, 162);
  assert.equal(result.importedS1Records, 12);
  assert.equal(result.newlyExecutedRecords, 150);
  assert.ok([1, 2].includes(result.maxConcurrentHeavyProofs));
  assert.ok(result.maxConcurrentHeavyProofs <= contract.executionPolicy.maxConcurrentHeavyProofs);
  assert.equal(path.resolve(result.replayIndex.path), path.resolve(indexPath));
  assert.equal(result.replayIndex.recordsRootSha256, index.recordsRootSha256);
  assert.equal(path.resolve(result.waveContract.path), path.resolve(contractPath));
  assert.equal(path.resolve(result.closureFreezeRoot), requestedClosureRoot);
  assert.equal(result.proofCredit, true);
  assert.equal(result.proofCreditBoundary, "ABI04_EXACT_REPLAY_SET_ONLY");
  assert.equal(result.rowDisposition, "OPEN_PENDING_AGGREGATE_ISABELLE_INDEPENDENT_CENTRAL");
  assert.equal(result.centralCredit, false);
  assert.equal(result.records.length, 162);
  assert.deepEqual(result.records.map((item) => item.replayId), index.records.map((item) => item.replayId));
  assert.equal(new Set(result.records.map((item) => item.replayId)).size, 162);
  const s1WorkerPath = path.join(s1Root, "worker-result.json");
  const knownS1 = index.importPolicy.knownAuthoritativeS1;
  assert.equal(s1Root, path.resolve(knownS1.absoluteRoot), "S1 root differs from precommit");
  const s1StoredReversePath = path.join(s1Root, "wave-reverse-check-v1.json");
  const s1Worker = readJson(s1WorkerPath);
  const s1Reverse = readJson(s1StoredReversePath);
  assert.equal(fileSha256(s1WorkerPath), knownS1.workerResultSha256);
  assert.equal(fileSha256(s1StoredReversePath), knownS1.independentReverseSha256);
  assert.equal(s1Worker.status, "PASS_S1_6_OF_6_STRICT_ROW_STILL_OPEN");
  assert.equal(s1Worker.reverseCheck.sha256, fileSha256(s1StoredReversePath));
  assert.equal(s1Reverse.status, "PASS_S1_6_OF_6_EXACT_REPLAY_AND_BINDER_SET_ROW_OPEN");
  const s1ReplayResultPath = path.join(s1Root, "wave-replay-result-v1.json");
  const s1ReplayResult = readJson(s1ReplayResultPath);
  assert.equal(fileSha256(s1ReplayResultPath), knownS1.replayResultSha256);
  const s1AuthoritativeResultPath = path.join(s1Root, "authoritative-wave-result-v1.json");
  assert.equal(fileSha256(s1AuthoritativeResultPath), knownS1.authoritativeResultSha256);
  assert.equal(fileSha256(s1ReplayResultPath), result.s1ReplayResult.sha256);
  assert.equal(path.resolve(result.s1WorkerResult.path), path.resolve(s1WorkerPath));
  assert.equal(path.resolve(result.s1ReplayResult.path), path.resolve(s1ReplayResultPath));
  assert.equal(result.s1WorkerResult.sha256, knownS1.workerResultSha256);
  assert.equal(result.s1ReplayResult.sha256, knownS1.replayResultSha256);
  assert.equal(result.s1ImportTransition.directClaimHashesCurrent, true);
  assert.equal(result.s1ImportTransition.verifiedCurrentClaimRecords, 12);
  assert.equal(result.s1ImportTransition.centralCredit, false);
  assert.equal(path.resolve(result.s1ImportTransition.historicalFreeze.root), path.resolve(knownS1.historicalFreeze.absoluteRoot));
  assert.equal(result.s1ImportTransition.historicalFreeze.workerResultSha256, knownS1.historicalFreeze.workerResultSha256);
  assert.equal(result.s1ImportTransition.historicalFreeze.closureHashSha256, knownS1.historicalFreeze.closureHashSha256);
  assert.equal(path.resolve(result.s1ImportTransition.currentFreeze.root), requestedClosureRoot);
  assert.equal(result.s1ImportTransition.currentFreeze.workerResultSha256, result.closureFreeze.workerResultSha256);
  assert.equal(result.s1ImportTransition.currentFreeze.closureHashSha256, result.closureFreeze.closureHashSha256);
  assert.equal(s1ReplayResult.replays.length, 12);
  assert.deepEqual(s1ReplayResult.closureBefore, s1ReplayResult.closureAfter);
  assert.equal(path.resolve(s1ReplayResult.closureFreezeRoot), path.resolve(knownS1.historicalFreeze.absoluteRoot));
  const historicalS1Closure = runJson(args.python, [freezeVerifierPath, "--root", s1ReplayResult.closureFreezeRoot, "--require-pass"], "historical S1 freeze verification");
  assert.equal(historicalS1Closure.status, "PASS");
  assert.equal(historicalS1Closure.workerResultSha256, s1ReplayResult.closureBefore.workerResultSha256);
  assert.equal(historicalS1Closure.closureHashSha256, s1ReplayResult.closureBefore.closureHashSha256);
  assert.equal(historicalS1Closure.workerResultSha256, knownS1.historicalFreeze.workerResultSha256);
  assert.equal(historicalS1Closure.closureHashSha256, knownS1.historicalFreeze.closureHashSha256);
  const s1ById = new Map(s1ReplayResult.replays.map((item) => [item.replayId, item]));
  let imported = 0;
  let executed = 0;
  const rawEvidenceRecords = [];
  for (let ordinal = 0; ordinal < index.records.length; ordinal += 1) {
    const expected = index.records[ordinal];
    const observed = result.records[ordinal];
    assert.equal(observed.ordinal, ordinal + 1);
    assert.equal(observed.replayId, expected.replayId);
    assert.equal(observed.semanticClaimId, expected.semanticClaimId);
    assert.equal(observed.executionClaimId, expected.executionClaimId);
    assert.equal(observed.status, "PASS");
    const currentClaimPath = repositoryBound(expected.claim.path, `${expected.replayId}/claim`);
    assert.equal(fileSha256(currentClaimPath), expected.claim.sha256, `${expected.replayId}: current claim hash drift`);
    assert.equal(strippedClaimSha256(currentClaimPath), expected.strippedClaimSha256, `${expected.replayId}: current stripped claim hash drift`);
    if (observed.provenance === "IMPORTED_S1_EXACT_GRAPH") {
      imported += 1;
      assert.equal(expected.sourceFamily, "DYNAMIC_OFFSET_V1_REFINEMENT");
      const suffix = expected.executionSide === "canonical-positive" ? "canonical-positive" : "unchanged-claim-mutant-negative";
      const sourceReplayId = `${expected.executionClaimId}::${suffix}`;
      assert.equal(observed.sourceReplayId, sourceReplayId);
      const source = s1ById.get(sourceReplayId);
      assert.ok(source, `missing S1 replay: ${sourceReplayId}`);
      assert.equal(observed.outputRoot, source.outputRoot);
      const leafRoot = existingContainedDirectory(s1Root, source.outputRoot, `${sourceReplayId}/output-root`);
      assert.equal(source.analysisJs.path, path.posix.join(source.outputRoot, "analysis-js.json"));
      assert.equal(source.analysisPython.path, path.posix.join(source.outputRoot, "analysis-python.json"));
      assert.deepEqual(observed.analysisJs, { path: source.analysisJs.path, sha256: source.analysisJs.sha256 });
      assert.deepEqual(observed.analysisPython, { path: source.analysisPython.path, sha256: source.analysisPython.sha256 });
      const jsPath = existingContainedFile(s1Root, source.analysisJs.path, `${sourceReplayId}/analysis-js`);
      const pyPath = existingContainedFile(s1Root, source.analysisPython.path, `${sourceReplayId}/analysis-python`);
      assert.equal(fileSha256(jsPath), observed.analysisJs.sha256);
      assert.equal(fileSha256(pyPath), observed.analysisPython.sha256);
      const js = readJson(jsPath);
      const py = readJson(pyPath);
      assert.equal(js.status, "PASS"); assert.equal(py.status, "PASS");
      assert.equal(js.claimId, expected.executionClaimId); assert.equal(py.claimId, expected.executionClaimId);
      assert.equal(js.sourceClaimSha256, expected.claim.sha256);
      assert.equal(py.analysisSha256, fileSha256(jsPath));
      assert.equal(py.expectedGraphContractSha256, js.expectedGraphContract.sha256);
      assert.ok(py.verifiedSnapshotFiles > 0);
      assert.deepEqual(js.graph, py.graph);
      assert.equal(js.inputIntegrityStatus, "PASS");
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
      const freshPy = runJson(args.python, [snapshotVerifier, "--output-root", leafRoot, "--expected", snapshotExpected, "--analysis", jsPath], `${sourceReplayId}: S1 raw Python reanalysis`);
      assert.deepEqual(freshPy, py, `${sourceReplayId}: S1 stored/fresh Python analysis mismatch`);
      const rawStored = verifyRawBindings(leafRoot, js, `${sourceReplayId}/stored-js`, "snapshot-files.sha256");
      const rawFresh = verifyRawBindings(leafRoot, freshJs, `${sourceReplayId}/fresh-js`, "snapshot-files.sha256");
      assert.deepEqual(rawFresh, rawStored, `${sourceReplayId}: S1 raw evidence binding mismatch`);
      assert.deepEqual(observed.rawEvidence, rawStored, `${sourceReplayId}: imported raw evidence result binding mismatch`);
      assert.equal(observed.proofId, freshJs.proofId, `${sourceReplayId}: imported proof ID mismatch`);
      assert.deepEqual(observed.graph, freshJs.graph, `${sourceReplayId}: imported graph mismatch`);
      rawEvidenceRecords.push({ replayId: expected.replayId, ...rawStored });
    } else {
      executed += 1;
      assert.equal(observed.provenance, "FULL_ROW_V1_NEW_EXECUTION");
      const expectedRelativeRoot = path.posix.join("replays", `${String(ordinal + 1).padStart(3, "0")}-${expected.semanticClaimId.replace(/^ABI04-/, "")}`, expected.executionSide);
      assert.equal(observed.outputRoot, expectedRelativeRoot);
      const outputRoot = existingContainedDirectory(waveRoot, observed.outputRoot, `${expected.replayId}/output-root`);
      const jsPath = existingContainedFile(outputRoot, "analysis-js.json", `${expected.replayId}/analysis-js`);
      const pyPath = existingContainedFile(outputRoot, "analysis-python.json", `${expected.replayId}/analysis-python`);
      assert.deepEqual(observed.analysisJs, { path: path.posix.join(observed.outputRoot, "analysis-js.json"), sha256: fileSha256(jsPath) });
      assert.deepEqual(observed.analysisPython, { path: path.posix.join(observed.outputRoot, "analysis-python.json"), sha256: fileSha256(pyPath) });
      assert.equal(fileSha256(jsPath), observed.analysisJs.sha256);
      assert.equal(fileSha256(pyPath), observed.analysisPython.sha256);
      const js = readJson(jsPath);
      const py = readJson(pyPath);
      const freshJs = runJson(process.execPath, [analyzerPath, outputRoot, indexPath], `${expected.replayId}: raw JavaScript reanalysis`);
      const freshPy = runJson(args.python, [verifierPath, outputRoot, indexPath], `${expected.replayId}: raw Python reanalysis`);
      assert.deepEqual(freshJs, js, `${expected.replayId}: stored/fresh JavaScript analysis mismatch`);
      assert.deepEqual(freshPy, py, `${expected.replayId}: stored/fresh Python analysis mismatch`);
      assert.deepEqual(core(js), core(py), `${expected.replayId}: JS/Python disagreement`);
      const rawJs = verifyRawBindings(outputRoot, freshJs, `${expected.replayId}/fresh-js`, "snapshot-files.json");
      const rawPy = verifyRawBindings(outputRoot, freshPy, `${expected.replayId}/fresh-python`, "snapshot-files.json");
      assert.deepEqual(rawJs, rawPy, `${expected.replayId}: JS/Python raw evidence disagreement`);
      assert.deepEqual(observed.rawEvidence, rawJs, `${expected.replayId}: row result raw evidence binding mismatch`);
      assert.equal(observed.proofId, freshJs.proofId, `${expected.replayId}: row result proof ID mismatch`);
      assert.deepEqual(observed.graph, freshJs.graph, `${expected.replayId}: row result graph mismatch`);
      assert.equal(observed.runnerExitCode, freshJs.launcherExitCode, `${expected.replayId}: row result runner exit mismatch`);
      const leafResultPath = existingContainedFile(outputRoot, "leaf-result.json", `${expected.replayId}/leaf-result`);
      assert.deepEqual(readJson(leafResultPath), observed, `${expected.replayId}: leaf/row result mismatch`);
      rawEvidenceRecords.push({ replayId: expected.replayId, ...rawJs });
      assert.equal(js.replayId, expected.replayId);
      assert.equal(js.claimSourceSha256, expected.claim.sha256);
      assert.equal(js.strippedClaimSha256, expected.strippedClaimSha256);
      assert.equal(js.processExitCode, expected.expectedProcessExitCode);
      assert.equal(js.graph.terminal, expected.acceptanceContract.graph.terminal);
      assert.equal(js.graph.pending, 0); assert.equal(js.graph.stuck, 0); assert.equal(js.graph.vacuous, 0); assert.equal(js.graph.bounded, 0); assert.equal(js.graph.admitted, false);
      assert.equal(js.inputIntegrityStatus, "PASS"); assert.equal(js.ownedSessionSurvivorCount, 0);
    }
  }
  assert.equal(imported, 12);
  assert.equal(executed, 150);
  assert.equal(rawEvidenceRecords.length, 162);
  assert.deepEqual(readJson(path.join(waveRoot, "closure-freeze-files-before.json")), readJson(path.join(waveRoot, "closure-freeze-files-after.json")), "wave closure freeze changed");
  const closure = runJson(args.python, [freezeVerifierPath, "--root", requestedClosureRoot, "--repository-root", repositoryRoot, "--require-pass"], "post-wave closure freeze verification");
  assert.equal(closure.status, "PASS");
  assert.equal(closure.workerResultSha256, result.closureFreeze.workerResultSha256);
  assert.equal(closure.closureHashSha256, result.closureFreeze.closureHashSha256);
  assert.deepEqual(closure.counts, result.closureFreeze.counts);
  const verdict = {
    schemaVersion: 1, kind: "ABI04_FULL_ROW_WAVE_INDEPENDENT_REVERSE_V1",
    status: "PASS_162_OF_162_REPLAY_SET_ROW_OPEN_PENDING_ATTESTATION", obligationId: "ABI-04",
    exactRecords: 162, importedS1Records: imported, newlyExecutedRecords: executed,
    replayIdsRootSha256: sha256(Buffer.from(JSON.stringify(index.records.map((item) => item.replayId)))),
    recordsRootSha256: index.recordsRootSha256, resultSha256: fileSha256(resultPath),
    replayIndexSha256: fileSha256(indexPath), waveContractSha256: fileSha256(contractPath),
    s1ReplayResultSha256: fileSha256(s1ReplayResultPath), s1StoredIndependentReverseSha256: fileSha256(s1StoredReversePath),
    s1IndependentReverseStatus: s1Reverse.status, historicalS1ClosureHashSha256: historicalS1Closure.closureHashSha256,
    rawEvidenceReanalyzedRecords: 162, genericRawReanalyzed: 150, s1SnapshotRawReanalyzed: 12,
    rawEvidenceRootSha256: sha256(Buffer.from(JSON.stringify(rawEvidenceRecords))),
    closureFreezeUnchanged: true, closureHashSha256: closure.closureHashSha256,
    jsPythonAgreement: true, proofCredit: true, proofCreditBoundary: "ABI04_EXACT_REPLAY_SET_ONLY",
    rowDisposition: "OPEN_PENDING_AGGREGATE_ISABELLE_INDEPENDENT_CENTRAL", centralCredit: false,
  };
  const serialized = `${JSON.stringify(verdict, null, 2)}\n`;
  if (args.report) {
    const reportPath = path.resolve(args.report);
    assert.ok(reportPath.startsWith(`${waveRoot}${path.sep}`), "report path must be inside wave root");
    const reportParent = path.dirname(reportPath);
    assert.ok(fs.existsSync(reportParent) && fs.statSync(reportParent).isDirectory(), "report parent must exist");
    assert.ok(fs.realpathSync(reportParent).startsWith(`${fs.realpathSync(waveRoot)}${path.sep}`) || fs.realpathSync(reportParent) === fs.realpathSync(waveRoot), "report parent symlink escape");
    fs.writeFileSync(reportPath, serialized, { encoding: "utf8", flag: "wx" });
  }
  process.stdout.write(serialized);
}

main();
