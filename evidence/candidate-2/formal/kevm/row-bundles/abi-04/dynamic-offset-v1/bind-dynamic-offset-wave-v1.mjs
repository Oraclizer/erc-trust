#!/usr/bin/env node
// Deterministically binds six authoritative S1 pairs from a completed fresh
// 12-replay wave. These binders grant S1 pair credit only; ABI-04 remains OPEN.
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const familyDir = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(familyDir, "../../../../..");
const replayIndexPath = path.join(familyDir, "remaining-leaves-replay-index-v2.json");
const waveContractPath = path.join(familyDir, "s1-dynamic-offset-wave-contract-v1.json");
const analyzerPath = path.join(familyDir, "analyze-dynamic-offset-replay-v1.mjs");
const verifierPath = path.join(familyDir, "verify-dynamic-offset-replay-v1.py");
const closureVerifierPath = path.join(familyDir, "..", "anti-drift", "verify-freeze-receipt.py");
const selfPath = fileURLToPath(import.meta.url);
const sha256 = (value) => crypto.createHash("sha256").update(value).digest("hex");
const fileSha256 = (filePath) => sha256(fs.readFileSync(filePath));
const readJson = (filePath) => JSON.parse(fs.readFileSync(filePath, "utf8"));
const render = (value) => `${JSON.stringify(value, null, 2)}\n`;
const waveRelative = (root, filePath) => path.relative(root, filePath).split(path.sep).join("/");

function hashTree(root) {
  const files = [];
  const visit = (current) => {
    for (const entry of fs.readdirSync(current, { withFileTypes: true }).sort((a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0)) {
      const target = path.join(current, entry.name);
      assert.equal(entry.isSymbolicLink(), false, `closure freeze contains symlink: ${target}`);
      if (entry.isDirectory()) visit(target);
      else if (entry.isFile()) files.push({ path: path.relative(root, target).split(path.sep).join("/"), sha256: fileSha256(target) });
      else assert.fail(`unsupported closure freeze entry: ${target}`);
    }
  };
  visit(root);
  return { files, rootSha256: sha256(Buffer.from(JSON.stringify(files))) };
}

function args() {
  const values = process.argv.slice(2);
  const mode = values.includes("--write") ? "write" : values.includes("--check") ? "check" : null;
  assert.ok(mode, "use exactly one of --write or --check");
  assert.equal(["--write", "--check"].filter((flag) => values.includes(flag)).length, 1);
  const rootIndex = values.indexOf("--wave-root");
  assert.ok(rootIndex >= 0 && values[rootIndex + 1], "--wave-root is required");
  const waveRoot = path.resolve(values[rootIndex + 1]);
  assert.equal(path.isAbsolute(values[rootIndex + 1]), true, "wave root must be absolute");
  assert.equal(fs.statSync(waveRoot).isDirectory(), true, "wave root must exist");
  assert.equal(fs.realpathSync(waveRoot), waveRoot, "wave root must not traverse a symlink");
  const pythonIndex = values.indexOf("--python");
  const python = pythonIndex < 0 ? "python3" : values[pythonIndex + 1];
  assert.ok(python, "--python value is required");
  return { mode, waveRoot, python };
}

function contained(root, relativePath) {
  assert.equal(typeof relativePath, "string");
  assert.equal(path.isAbsolute(relativePath), false, `expected wave-relative path: ${relativePath}`);
  const value = path.resolve(root, ...relativePath.split("/"));
  const rel = path.relative(root, value);
  assert.ok(rel && rel !== ".." && !rel.startsWith(`..${path.sep}`), `path escapes wave root: ${relativePath}`);
  return value;
}

function requireArtifact(root, binding, label) {
  assert.match(binding.sha256, /^[0-9a-f]{64}$/, `${label}: sha256`);
  const artifact = contained(root, binding.path);
  assert.equal(fileSha256(artifact), binding.sha256, `${label}: digest`);
  return { path: artifact, json: readJson(artifact) };
}

function runJson(command, arguments_, label) {
  const result = spawnSync(command, arguments_, { cwd: repositoryRoot, encoding: "utf8", maxBuffer: 32 * 1024 * 1024 });
  assert.equal(result.error, undefined, `${label}: spawn error`);
  assert.equal(result.signal, null, `${label}: signal`);
  assert.equal(result.status, 0, `${label}: ${result.stderr}`);
  return JSON.parse(result.stdout);
}

function writeOrCheck(mode, filePath, content) {
  if (mode === "write") {
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    fs.writeFileSync(filePath, content, { encoding: "utf8", flag: "wx" });
  } else {
    assert.equal(fs.readFileSync(filePath, "utf8").replaceAll("\r\n", "\n"), content, `stale binder: ${filePath}`);
  }
}

function validateReplay(record, expected, waveRoot, python) {
  assert.equal(record.claimId, expected.claimId);
  assert.equal(record.endpointId, expected.endpointId);
  assert.equal(record.selector, expected.selector);
  assert.equal(record.replayId, expected.replayId);
  assert.equal(record.runnerSide, expected.runnerSide);
  assert.equal(record.expectedGraphSha256, expected.expectedGraph.sha256);
  assert.equal(record.runnerExitCode, expected.expectedProcessExitCode);
  assert.equal(record.status, "PASS_EXACT_GRAPH_JS_PYTHON");
  assert.equal(record.proofCreditBoundary, "LEAF_REPLAY_ONLY_NOT_CENTRAL_DISCHARGE");
  const js = requireArtifact(waveRoot, record.analysisJs, `${record.replayId}: JS analysis`);
  const py = requireArtifact(waveRoot, record.analysisPython, `${record.replayId}: Python analysis`);
  assert.equal(js.json.status, "PASS");
  assert.equal(py.json.status, "PASS");
  for (const report of [js.json, py.json]) {
    assert.equal(report.claimId, record.claimId);
    assert.equal(report.side, record.runnerSide);
    assert.deepEqual(report.graph, expected.expectedGraph.graph);
    assert.equal(report.proofCreditBoundary, "LEAF_REPLAY_ONLY_NOT_CENTRAL_DISCHARGE");
  }
  assert.equal(js.json.processExitCode, expected.expectedProcessExitCode);
  assert.equal(js.json.launcherExitCode, expected.expectedProcessExitCode);
  assert.equal(js.json.inputIntegrityStatus, "PASS");
  assert.equal(js.json.ownedSessionSurvivorCount, 0);
  assert.equal(py.json.expectedGraphContractSha256, expected.expectedGraph.sha256);
  assert.equal(py.json.analysisSha256, record.analysisJs.sha256);
  assert.equal(js.json.sourceClaimSha256, expected.sourceClaimSha256);
  assert.equal(js.json.strippedClaimSha256, expected.strippedClaimSha256);
  const leafRoot = contained(waveRoot, record.outputRoot);
  const expectedGraphPath = path.resolve(repositoryRoot, ...expected.expectedGraph.path.split("/"));
  assert.equal(fileSha256(expectedGraphPath), expected.expectedGraph.sha256);
  const replayedJs = runJson(process.execPath, [analyzerPath, leafRoot, expectedGraphPath], `${record.replayId}: binder JS reanalysis`);
  const replayedPy = runJson(python, [verifierPath, "--output-root", leafRoot, "--expected", expectedGraphPath, "--analysis", js.path], `${record.replayId}: binder Python reverification`);
  assert.deepEqual(replayedJs, js.json, `${record.replayId}: binder JS report drift`);
  assert.deepEqual(replayedPy, py.json, `${record.replayId}: binder Python report drift`);
  return { js: js.json, py: py.json };
}

function main() {
  const { mode, waveRoot, python } = args();
  const replayResultPath = path.join(waveRoot, "wave-replay-result-v1.json");
  const replayResult = readJson(replayResultPath);
  const index = readJson(replayIndexPath);
  const wave = readJson(waveContractPath);
  assert.equal(replayResult.kind, "ABI04_DYNAMIC_OFFSET_S1_EXACT_REPLAY_RESULT");
  assert.equal(replayResult.status, "PASS_12_OF_12_EXACT_REPLAY_JS_PYTHON_CREDIT_BOUNDARY_S1_ONLY");
  assert.equal(replayResult.exactPairs, 6);
  assert.equal(replayResult.exactReplays, 12);
  assert.equal(replayResult.replays.length, 12);
  assert.equal(replayResult.closureBefore.filesRootSha256, replayResult.closureAfter.filesRootSha256);
  assert.equal(replayResult.closureBefore.exactFiles, replayResult.closureAfter.exactFiles);
  assert.equal(replayResult.closureBefore.closureHashSha256, replayResult.closureAfter.closureHashSha256);
  assert.equal(replayResult.closureBefore.workerResultSha256, replayResult.closureAfter.workerResultSha256);
  assert.deepEqual(replayResult.closureBefore.counts, replayResult.closureAfter.counts);
  for (const key of ["missing", "unexpected", "duplicate", "declaredActualMismatch", "invalidated"]) assert.equal(replayResult.closureBefore.counts[key], 0, `nonzero closure ${key}`);
  assert.equal(replayResult.closureBefore.jsPythonClosureAgreement, true);
  assert.equal(replayResult.closureAfter.jsPythonClosureAgreement, true);
  const closureBeforePath = path.join(waveRoot, "closure-files-before.json");
  const closureAfterPath = path.join(waveRoot, "closure-files-after.json");
  const closureBeforeReportPath = path.join(waveRoot, "closure-verification-before.json");
  const closureAfterReportPath = path.join(waveRoot, "closure-verification-after.json");
  const closureBefore = readJson(closureBeforePath);
  const closureAfter = readJson(closureAfterPath);
  assert.deepEqual(closureAfter, closureBefore, "recorded closure trees differ");
  assert.equal(closureBefore.rootSha256, replayResult.closureBefore.filesRootSha256);
  assert.equal(closureBefore.files.length, replayResult.closureBefore.exactFiles);
  assert.equal(fileSha256(closureBeforeReportPath), replayResult.closureBefore.reportSha256);
  assert.equal(fileSha256(closureAfterReportPath), replayResult.closureAfter.reportSha256);
  const closureBeforeReport = readJson(closureBeforeReportPath);
  const closureAfterReport = readJson(closureAfterReportPath);
  assert.equal(closureBeforeReport.status, "PASS");
  assert.equal(closureAfterReport.status, "PASS");
  assert.equal(closureBeforeReport.closureHashSha256, replayResult.closureBefore.closureHashSha256);
  assert.equal(closureAfterReport.closureHashSha256, replayResult.closureAfter.closureHashSha256);
  assert.equal(closureBeforeReport.workerResultSha256, replayResult.closureBefore.workerResultSha256);
  assert.equal(closureAfterReport.workerResultSha256, replayResult.closureAfter.workerResultSha256);
  assert.deepEqual(closureBeforeReport.counts, replayResult.closureBefore.counts);
  assert.deepEqual(closureAfterReport.counts, replayResult.closureAfter.counts);
  assert.equal(closureBeforeReport.repositoryNodesVerified, replayResult.closureBefore.repositoryNodesVerified);
  assert.equal(closureAfterReport.repositoryNodesVerified, replayResult.closureAfter.repositoryNodesVerified);
  assert.equal(closureBeforeReport.generationNodesVerified, replayResult.closureBefore.generationNodesVerified);
  assert.equal(closureAfterReport.generationNodesVerified, replayResult.closureAfter.generationNodesVerified);
  assert.deepEqual(hashTree(path.resolve(replayResult.closureFreezeRoot)), closureBefore, "live closure tree differs from wave freeze");
  const liveClosureVerdict = runJson(python, [closureVerifierPath, "--root", replayResult.closureFreezeRoot, "--repository-root", repositoryRoot, "--require-pass"], "binder live closure verification");
  assert.equal(liveClosureVerdict.status, "PASS");
  assert.equal(liveClosureVerdict.workerResultSha256, replayResult.closureBefore.workerResultSha256);
  assert.equal(liveClosureVerdict.closureHashSha256, replayResult.closureBefore.closureHashSha256);
  assert.deepEqual(liveClosureVerdict.counts, replayResult.closureBefore.counts);
  assert.equal(replayResult.replayIndex.sha256, fileSha256(replayIndexPath));
  assert.equal(replayResult.waveContract.sha256, fileSha256(waveContractPath));
  assert.equal(index.exactReplayCount, 12);
  assert.equal(wave.centralBindingAllowed, false);
  assert.deepEqual(wave.expectedGraphSet, index.expectedGraphSet, "wave/replay expected-graph set drift");
  assert.deepEqual(wave.leaves.map(({ claimId }) => claimId), index.claims.map(({ claimId }) => claimId), "wave/replay claim order drift");
  const sourceBindings = {
    pairBinder: selfPath,
    analysisTool: path.join(familyDir, "analyze-dynamic-offset-replay-v1.mjs"),
    independentVerifier: path.join(familyDir, "verify-dynamic-offset-replay-v1.py"),
    waveCoordinator: path.join(familyDir, "run-dynamic-offset-wave-v1.mjs"),
    waveReverseCheck: path.join(familyDir, "reverse-check-dynamic-offset-wave-v1.mjs"),
    closureFreezeVerifier: closureVerifierPath,
  };
  for (const [name, sourcePath] of Object.entries(sourceBindings)) {
    assert.equal(index.sourceBinding[name].path, path.relative(repositoryRoot, sourcePath).split(path.sep).join("/"));
    assert.equal(index.sourceBinding[name].sha256, fileSha256(sourcePath));
    assert.deepEqual(wave.sourceBinding[name], index.sourceBinding[name]);
  }

  const expectedReplays = index.claims.flatMap((claim) => [
    {
      claimId: claim.claimId,
      endpointId: claim.endpointId,
      selector: claim.selector,
      replayId: claim.canonicalPositive.replayId,
      runnerSide: claim.canonicalPositive.runnerSide,
      expectedProcessExitCode: claim.canonicalPositive.expectedProcessExitCode,
      expectedGraph: claim.canonicalPositive.expectedGraph,
      sourceClaimSha256: claim.sourceClaim.sha256,
      strippedClaimSha256: claim.sourceClaim.strippedSha256,
    },
    {
      claimId: claim.claimId,
      endpointId: claim.endpointId,
      selector: claim.selector,
      replayId: claim.unchangedClaimMutantNegative.replayId,
      runnerSide: claim.unchangedClaimMutantNegative.runnerSide,
      expectedProcessExitCode: claim.unchangedClaimMutantNegative.expectedProcessExitCode,
      expectedGraph: claim.unchangedClaimMutantNegative.expectedGraph,
      sourceClaimSha256: claim.sourceClaim.sha256,
      strippedClaimSha256: claim.sourceClaim.strippedSha256,
    },
  ]);
  assert.deepEqual(replayResult.replayIds, expectedReplays.map(({ replayId }) => replayId));
  assert.deepEqual(replayResult.replays.map(({ replayId }) => replayId), expectedReplays.map(({ replayId }) => replayId));
  assert.equal(new Set(replayResult.replayIds).size, 12);

  const validated = replayResult.replays.map((record, indexValue) => validateReplay(record, expectedReplays[indexValue], waveRoot, python));
  const binderDirectory = path.join(waveRoot, "pair-binders");
  const binderFiles = [];
  for (let pairIndex = 0; pairIndex < 6; pairIndex += 1) {
    const claim = index.claims[pairIndex];
    const positiveRecord = replayResult.replays[pairIndex * 2];
    const negativeRecord = replayResult.replays[pairIndex * 2 + 1];
    const positive = validated[pairIndex * 2].js;
    const negative = validated[pairIndex * 2 + 1].js;
    assert.equal(positive.sourceClaimSha256, negative.sourceClaimSha256, `${claim.claimId}: claim source drift`);
    assert.equal(positive.strippedClaimSha256, negative.strippedClaimSha256, `${claim.claimId}: stripped claim drift`);
    assert.equal(positive.proofId, negative.proofId, `${claim.claimId}: proof ID drift`);
    assert.equal(positive.graph.pending, 0);
    assert.equal(negative.graph.pending, 0);
    assert.equal(positive.graph.admitted, false);
    assert.equal(negative.graph.admitted, false);
    assert.equal(positive.graph.terminal, 0);
    assert.equal(negative.graph.terminal, 1);
    assert.ok(negative.terminalWitnessObservation, `${claim.claimId}: missing negative terminal witness`);
    assert.equal(negative.terminalWitnessObservation.statusLabel, "EVMC_SUCCESS_NETWORK_EndStatusCode");
    assert.equal(negative.terminalWitnessObservation.outputToken, 'b""');
    assert.equal(negative.terminalWitnessObservation.endpointStorageEqualsOriginal, true);

    const binder = {
      schemaVersion: 1,
      kind: "ABI04_DYNAMIC_OFFSET_AUTHORITATIVE_PAIR_BINDER",
      obligationId: "ABI-04",
      stage: "S1",
      status: "PASS_AUTHORITATIVE_PAIR",
      pairOrdinal: pairIndex + 1,
      claimId: claim.claimId,
      endpointId: claim.endpointId,
      selector: claim.selector,
      proofId: positive.proofId,
      unchangedClaim: {
        sourceClaimSha256: positive.sourceClaimSha256,
        strippedClaimSha256: positive.strippedClaimSha256,
        positiveEqualsNegative: true,
      },
      canonicalPositive: {
        replayId: positiveRecord.replayId,
        outputRoot: positiveRecord.outputRoot,
        expectedExitCode: 0,
        graph: positive.graph,
        incomplete: 0,
        expectedGraphSha256: positiveRecord.expectedGraphSha256,
        analysisJs: positiveRecord.analysisJs,
        analysisPython: positiveRecord.analysisPython,
        integrity: "PASS",
        survivors: 0,
      },
      unchangedClaimMutantNegative: {
        replayId: negativeRecord.replayId,
        runnerSide: "mutant-negative",
        outputRoot: negativeRecord.outputRoot,
        expectedExitCode: 1,
        graph: negative.graph,
        incomplete: 0,
        expectedGraphSha256: negativeRecord.expectedGraphSha256,
        analysisJs: negativeRecord.analysisJs,
        analysisPython: negativeRecord.analysisPython,
        terminalWitnessObservation: negative.terminalWitnessObservation,
        integrity: "PASS",
        survivors: 0,
      },
      frozenClosure: {
        closureHashSha256: replayResult.closureBefore.closureHashSha256,
        workerResultSha256: replayResult.closureBefore.workerResultSha256,
        counts: replayResult.closureBefore.counts,
        beforeRootSha256: replayResult.closureBefore.filesRootSha256,
        afterRootSha256: replayResult.closureAfter.filesRootSha256,
        unchanged: true,
      },
      replayIndexSha256: fileSha256(replayIndexPath),
      waveContractSha256: fileSha256(waveContractPath),
      binderToolSha256: fileSha256(selfPath),
      exactReplayCount: 2,
      exactGraphCount: 2,
      jsPythonAgreement: true,
      proofCredit: true,
      proofCreditBoundary: "S1_DYNAMIC_OFFSET_PAIR_ONLY",
      centralCredit: false,
      rowDisposition: "OPEN",
    };
    const binderPath = path.join(binderDirectory, `${claim.endpointId}-authoritative-pair-v1.json`);
    writeOrCheck(mode, binderPath, render(binder));
    binderFiles.push({
      pairOrdinal: pairIndex + 1,
      claimId: claim.claimId,
      endpointId: claim.endpointId,
      path: waveRelative(waveRoot, binderPath),
      sha256: sha256(Buffer.from(render(binder))),
      status: "PASS_AUTHORITATIVE_PAIR",
      proofCredit: true,
      centralCredit: false,
    });
  }

  const authoritative = {
    schemaVersion: 1,
    kind: "ABI04_DYNAMIC_OFFSET_S1_AUTHORITATIVE_WAVE_RESULT",
    obligationId: "ABI-04",
    stage: "S1",
    status: "PASS_S1_6_OF_6_PAIR_CREDIT_ROW_OPEN",
    exactPairCount: 6,
    exactReplayCount: 12,
    exactReplayIds: replayResult.replayIds,
    pairBinders: binderFiles,
    pairBinderSetRootSha256: sha256(Buffer.from(JSON.stringify(binderFiles.map(({ claimId, path: binderPath, sha256: digest }) => ({ claimId, path: binderPath, sha256: digest }))))),
    replayResult: { path: waveRelative(waveRoot, replayResultPath), sha256: fileSha256(replayResultPath) },
    replayIndex: { path: path.relative(repositoryRoot, replayIndexPath).split(path.sep).join("/"), sha256: fileSha256(replayIndexPath) },
    waveContract: { path: path.relative(repositoryRoot, waveContractPath).split(path.sep).join("/"), sha256: fileSha256(waveContractPath) },
    frozenClosure: {
      closureHashSha256: replayResult.closureBefore.closureHashSha256,
      workerResultSha256: replayResult.closureBefore.workerResultSha256,
      counts: replayResult.closureBefore.counts,
      beforeRootSha256: replayResult.closureBefore.filesRootSha256,
      afterRootSha256: replayResult.closureAfter.filesRootSha256,
      exactFiles: replayResult.closureBefore.exactFiles,
      unchanged: true,
    },
    jsPythonAgreement: true,
    proofCredit: true,
    proofCreditBoundary: "S1_DYNAMIC_OFFSET_6_OF_6_ONLY",
    centralCredit: false,
    rowDisposition: "OPEN_PENDING_DYNAMIC_LENGTH_HIGH_BITS_SYMBOLIC_162_AGGREGATE_ISABELLE_INDEPENDENT",
  };
  assert.deepEqual(fs.readdirSync(binderDirectory).sort(), binderFiles.map(({ path: binderPath }) => path.basename(binderPath)).sort(), "pair binder file exact set mismatch");
  const authoritativePath = path.join(waveRoot, "authoritative-wave-result-v1.json");
  writeOrCheck(mode, authoritativePath, render(authoritative));
  process.stdout.write(render({
    status: mode === "write" ? "PASS_BOUND_S1_6_OF_6_ROW_OPEN" : "PASS_CHECKED_S1_6_OF_6_ROW_OPEN",
    exactPairs: 6,
    exactReplays: 12,
    pairBinderSetRootSha256: authoritative.pairBinderSetRootSha256,
    proofCredit: true,
    proofCreditBoundary: authoritative.proofCreditBoundary,
    centralCredit: false,
    rowDisposition: authoritative.rowDisposition,
  }));
}

main();
