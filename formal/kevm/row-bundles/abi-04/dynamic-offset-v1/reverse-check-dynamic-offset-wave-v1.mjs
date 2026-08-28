#!/usr/bin/env node
// Independent post-wave exact-set check. It reruns every JS analysis and every
// independent Python replay verification, checks all six pair binders, and
// confirms that S1 credit does not cross the ABI-04 central-credit boundary.
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const familyDir = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(familyDir, "../../../../..");
const analyzerPath = path.join(familyDir, "analyze-dynamic-offset-replay-v1.mjs");
const verifierPath = path.join(familyDir, "verify-dynamic-offset-replay-v1.py");
const closureVerifierPath = path.join(familyDir, "..", "anti-drift", "verify-freeze-receipt.py");
const replayIndexPath = path.join(familyDir, "remaining-leaves-replay-index-v2.json");
const waveContractPath = path.join(familyDir, "s1-dynamic-offset-wave-contract-v1.json");
const binderToolPath = path.join(familyDir, "bind-dynamic-offset-wave-v1.mjs");
const selfPath = fileURLToPath(import.meta.url);
const sha256 = (value) => crypto.createHash("sha256").update(value).digest("hex");
const fileSha256 = (filePath) => sha256(fs.readFileSync(filePath));
const readJson = (filePath) => JSON.parse(fs.readFileSync(filePath, "utf8"));
const render = (value) => `${JSON.stringify(value, null, 2)}\n`;

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

function parseArgs() {
  const values = process.argv.slice(2);
  const rootIndex = values.indexOf("--wave-root");
  assert.ok(rootIndex >= 0 && values[rootIndex + 1], "--wave-root is required");
  assert.equal(path.isAbsolute(values[rootIndex + 1]), true, "wave root must be absolute");
  const option = (name, fallback = null) => {
    const index = values.indexOf(name);
    return index < 0 ? fallback : values[index + 1];
  };
  return { waveRoot: path.resolve(values[rootIndex + 1]), python: option("--python", "python3"), report: option("--report") };
}

function contained(root, relativePath) {
  assert.equal(path.isAbsolute(relativePath), false, `expected wave-relative path: ${relativePath}`);
  const target = path.resolve(root, ...relativePath.split("/"));
  const rel = path.relative(root, target);
  assert.ok(rel && rel !== ".." && !rel.startsWith(`..${path.sep}`), `wave path escape: ${relativePath}`);
  return target;
}

function runJson(command, args, label) {
  const result = spawnSync(command, args, { cwd: repositoryRoot, encoding: "utf8", maxBuffer: 32 * 1024 * 1024 });
  assert.equal(result.error, undefined, `${label}: spawn error`);
  assert.equal(result.signal, null, `${label}: signal`);
  assert.equal(result.status, 0, `${label}: ${result.stderr}`);
  return JSON.parse(result.stdout);
}

function main() {
  const args = parseArgs();
  assert.equal(fs.statSync(args.waveRoot).isDirectory(), true);
  assert.equal(fs.realpathSync(args.waveRoot), args.waveRoot, "wave root must not traverse a symlink");
  const replayResultPath = path.join(args.waveRoot, "wave-replay-result-v1.json");
  const authoritativePath = path.join(args.waveRoot, "authoritative-wave-result-v1.json");
  const replayResult = readJson(replayResultPath);
  const authoritative = readJson(authoritativePath);
  const replayIndex = readJson(replayIndexPath);
  const wave = readJson(waveContractPath);

  assert.equal(replayResult.status, "PASS_12_OF_12_EXACT_REPLAY_JS_PYTHON_CREDIT_BOUNDARY_S1_ONLY");
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
  const recordedClosureBefore = readJson(path.join(args.waveRoot, "closure-files-before.json"));
  const recordedClosureAfter = readJson(path.join(args.waveRoot, "closure-files-after.json"));
  assert.deepEqual(recordedClosureAfter, recordedClosureBefore, "recorded closure trees differ");
  assert.equal(recordedClosureBefore.rootSha256, replayResult.closureBefore.filesRootSha256);
  assert.equal(recordedClosureBefore.files.length, replayResult.closureBefore.exactFiles);
  assert.equal(fileSha256(path.join(args.waveRoot, "closure-verification-before.json")), replayResult.closureBefore.reportSha256);
  assert.equal(fileSha256(path.join(args.waveRoot, "closure-verification-after.json")), replayResult.closureAfter.reportSha256);
  const closureBeforeReport = readJson(path.join(args.waveRoot, "closure-verification-before.json"));
  const closureAfterReport = readJson(path.join(args.waveRoot, "closure-verification-after.json"));
  assert.equal(closureBeforeReport.status, "PASS");
  assert.equal(closureAfterReport.status, "PASS");
  assert.equal(closureBeforeReport.closureHashSha256, replayResult.closureBefore.closureHashSha256);
  assert.equal(closureAfterReport.closureHashSha256, replayResult.closureAfter.closureHashSha256);
  assert.equal(closureBeforeReport.workerResultSha256, replayResult.closureBefore.workerResultSha256);
  assert.equal(closureAfterReport.workerResultSha256, replayResult.closureAfter.workerResultSha256);
  assert.deepEqual(closureBeforeReport.counts, replayResult.closureBefore.counts);
  assert.deepEqual(closureAfterReport.counts, replayResult.closureAfter.counts);
  assert.deepEqual(hashTree(path.resolve(replayResult.closureFreezeRoot)), recordedClosureBefore, "live closure tree differs from wave freeze");
  assert.equal(authoritative.status, "PASS_S1_6_OF_6_PAIR_CREDIT_ROW_OPEN");
  assert.equal(authoritative.exactPairCount, 6);
  assert.equal(authoritative.exactReplayCount, 12);
  assert.equal(authoritative.centralCredit, false);
  assert.equal(authoritative.rowDisposition, "OPEN_PENDING_DYNAMIC_LENGTH_HIGH_BITS_SYMBOLIC_162_AGGREGATE_ISABELLE_INDEPENDENT");
  assert.equal(authoritative.replayResult.sha256, fileSha256(replayResultPath));
  assert.equal(authoritative.replayIndex.sha256, fileSha256(replayIndexPath));
  assert.equal(authoritative.waveContract.sha256, fileSha256(waveContractPath));
  assert.equal(wave.centralBindingAllowed, false);
  assert.equal(wave.exactReplayCount, 12);
  assert.deepEqual(wave.expectedGraphSet, replayIndex.expectedGraphSet, "wave/replay expected-graph set drift");
  assert.deepEqual(wave.leaves.map(({ claimId }) => claimId), replayIndex.claims.map(({ claimId }) => claimId), "wave/replay claim order drift");
  for (const [name, sourcePath] of Object.entries({
    waveCoordinator: path.join(familyDir, "run-dynamic-offset-wave-v1.mjs"),
    analysisTool: analyzerPath,
    independentVerifier: verifierPath,
    pairBinder: binderToolPath,
    waveReverseCheck: selfPath,
  })) {
    assert.equal(replayIndex.sourceBinding[name].path, path.relative(repositoryRoot, sourcePath).split(path.sep).join("/"));
    assert.equal(replayIndex.sourceBinding[name].sha256, fileSha256(sourcePath));
    assert.deepEqual(wave.sourceBinding[name], replayIndex.sourceBinding[name]);
  }

  const expected = replayIndex.claims.flatMap((claim) => [
    { claim, side: claim.canonicalPositive, runnerSide: "canonical-positive" },
    { claim, side: claim.unchangedClaimMutantNegative, runnerSide: "mutant-negative" },
  ]);
  assert.equal(expected.length, 12);
  assert.deepEqual(replayResult.replayIds, expected.map(({ side }) => side.replayId));
  assert.deepEqual(authoritative.exactReplayIds, expected.map(({ side }) => side.replayId));
  assert.equal(new Set(replayResult.replayIds).size, 12);
  const replayDirectory = path.join(args.waveRoot, "replays");
  const expectedReplayParents = replayResult.replays.map(({ ordinal, endpointId }) => `${String(ordinal).padStart(3, "0")}-${endpointId}`).sort();
  const actualReplayParents = fs.readdirSync(replayDirectory, { withFileTypes: true });
  assert.ok(actualReplayParents.every((entry) => entry.isDirectory()), "unexpected non-directory in replay root");
  assert.deepEqual(actualReplayParents.map(({ name }) => name).sort(), expectedReplayParents, "replay output-root exact set mismatch");

  const verified = replayResult.replays.map((record, index) => {
    const contract = expected[index];
    assert.equal(record.replayId, contract.side.replayId);
    assert.equal(record.claimId, contract.claim.claimId);
    assert.equal(record.runnerSide, contract.runnerSide);
    assert.equal(record.expectedGraphSha256, contract.side.expectedGraph.sha256);
    assert.equal(record.status, "PASS_EXACT_GRAPH_JS_PYTHON");
    const replayParent = path.dirname(contained(args.waveRoot, record.outputRoot));
    const sideEntries = fs.readdirSync(replayParent, { withFileTypes: true });
    assert.deepEqual(sideEntries.map(({ name }) => name), [record.runnerSide], `${record.replayId}: output side exact set`);
    assert.equal(sideEntries[0].isDirectory(), true);
    const leafRoot = contained(args.waveRoot, record.outputRoot);
    const expectedGraphPath = path.resolve(repositoryRoot, ...contract.side.expectedGraph.path.split("/"));
    assert.equal(fileSha256(expectedGraphPath), contract.side.expectedGraph.sha256);
    const analysisPath = contained(args.waveRoot, record.analysisJs.path);
    const independentPath = contained(args.waveRoot, record.analysisPython.path);
    assert.equal(fileSha256(analysisPath), record.analysisJs.sha256);
    assert.equal(fileSha256(independentPath), record.analysisPython.sha256);

    const jsReplay = runJson(process.execPath, [analyzerPath, leafRoot, expectedGraphPath], `${record.replayId}: JS reanalysis`);
    const pyReplay = runJson(args.python, [verifierPath, "--output-root", leafRoot, "--expected", expectedGraphPath, "--analysis", analysisPath], `${record.replayId}: Python reverification`);
    assert.deepEqual(jsReplay, readJson(analysisPath), `${record.replayId}: JS replay drift`);
    assert.deepEqual(pyReplay, readJson(independentPath), `${record.replayId}: Python replay drift`);
    assert.deepEqual(jsReplay.graph, contract.side.expectedGraph.graph);
    assert.deepEqual(pyReplay.graph, contract.side.expectedGraph.graph);
    assert.equal(jsReplay.processExitCode, contract.side.expectedProcessExitCode);
    assert.equal(jsReplay.launcherExitCode, contract.side.expectedProcessExitCode);
    assert.equal(jsReplay.inputIntegrityStatus, "PASS");
    assert.equal(jsReplay.ownedSessionSurvivorCount, 0);
    assert.equal(jsReplay.proofCreditBoundary, "LEAF_REPLAY_ONLY_NOT_CENTRAL_DISCHARGE");
    assert.equal(pyReplay.proofCreditBoundary, "LEAF_REPLAY_ONLY_NOT_CENTRAL_DISCHARGE");
    if (contract.runnerSide === "canonical-positive") {
      assert.equal(jsReplay.graph.terminal, 0);
    } else {
      assert.equal(jsReplay.graph.terminal, 1);
      assert.equal(jsReplay.terminalWitnessObservation.statusLabel, "EVMC_SUCCESS_NETWORK_EndStatusCode");
      assert.equal(jsReplay.terminalWitnessObservation.outputToken, 'b""');
      assert.equal(jsReplay.terminalWitnessObservation.endpointStorageEqualsOriginal, true);
    }
    return { replayId: record.replayId, analysisJsSha256: record.analysisJs.sha256, analysisPythonSha256: record.analysisPython.sha256, status: "PASS" };
  });

  const binderCheck = runJson(process.execPath, [binderToolPath, "--check", "--wave-root", args.waveRoot, "--python", args.python], "pair binder deterministic check");
  assert.equal(binderCheck.status, "PASS_CHECKED_S1_6_OF_6_ROW_OPEN");
  assert.equal(authoritative.pairBinders.length, 6);
  assert.equal(new Set(authoritative.pairBinders.map(({ claimId }) => claimId)).size, 6);
  const binderRecords = authoritative.pairBinders.map((binding, index) => {
    assert.equal(binding.pairOrdinal, index + 1);
    assert.equal(binding.claimId, replayIndex.claims[index].claimId);
    assert.equal(binding.endpointId, replayIndex.claims[index].endpointId);
    assert.equal(binding.status, "PASS_AUTHORITATIVE_PAIR");
    assert.equal(binding.proofCredit, true);
    assert.equal(binding.centralCredit, false);
    const binderPath = contained(args.waveRoot, binding.path);
    assert.equal(fileSha256(binderPath), binding.sha256);
    const binder = readJson(binderPath);
    assert.equal(binder.kind, "ABI04_DYNAMIC_OFFSET_AUTHORITATIVE_PAIR_BINDER");
    assert.equal(binder.claimId, binding.claimId);
    assert.equal(binder.canonicalPositive.replayId, `${binding.claimId}::canonical-positive`);
    assert.equal(binder.unchangedClaimMutantNegative.replayId, `${binding.claimId}::unchanged-claim-mutant-negative`);
    assert.equal(binder.unchangedClaim.positiveEqualsNegative, true);
    assert.equal(binder.canonicalPositive.expectedExitCode, 0);
    assert.equal(binder.unchangedClaimMutantNegative.expectedExitCode, 1);
    assert.equal(binder.canonicalPositive.incomplete, 0);
    assert.equal(binder.unchangedClaimMutantNegative.incomplete, 0);
    assert.equal(binder.canonicalPositive.graph.pending, 0);
    assert.equal(binder.unchangedClaimMutantNegative.graph.pending, 0);
    assert.equal(binder.canonicalPositive.graph.admitted, false);
    assert.equal(binder.unchangedClaimMutantNegative.graph.admitted, false);
    assert.equal(binder.jsPythonAgreement, true);
    assert.equal(binder.proofCreditBoundary, "S1_DYNAMIC_OFFSET_PAIR_ONLY");
    assert.equal(binder.frozenClosure.closureHashSha256, replayResult.closureBefore.closureHashSha256);
    assert.equal(binder.frozenClosure.workerResultSha256, replayResult.closureBefore.workerResultSha256);
    assert.deepEqual(binder.frozenClosure.counts, replayResult.closureBefore.counts);
    assert.equal(binder.centralCredit, false);
    assert.equal(binder.rowDisposition, "OPEN");
    return { ...binding };
  });
  const binderRoot = sha256(Buffer.from(JSON.stringify(binderRecords.map(({ claimId, path: binderPath, sha256: digest }) => ({ claimId, path: binderPath, sha256: digest })))));
  assert.equal(binderRoot, authoritative.pairBinderSetRootSha256);
  assert.deepEqual(fs.readdirSync(path.join(args.waveRoot, "pair-binders")).sort(), binderRecords.map(({ path: binderPath }) => path.basename(binderPath)).sort(), "pair binder file exact set mismatch");

  const closurePass = runJson(args.python, [closureVerifierPath, "--root", replayResult.closureFreezeRoot, "--repository-root", repositoryRoot, "--require-pass"], "post-wave closure verification");
  assert.equal(closurePass.status, "PASS");
  const report = {
    schemaVersion: 1,
    kind: "ABI04_DYNAMIC_OFFSET_S1_WAVE_INDEPENDENT_REVERSE_CHECK",
    status: "PASS_S1_6_OF_6_EXACT_REPLAY_AND_BINDER_SET_ROW_OPEN",
    obligationId: "ABI-04",
    stage: "S1",
    exactPairs: 6,
    exactReplays: 12,
    replayIds: verified.map(({ replayId }) => replayId),
    replays: verified,
    pairBinders: binderRecords,
    pairBinderSetRootSha256: binderRoot,
    replayResultSha256: fileSha256(replayResultPath),
    authoritativeWaveResultSha256: fileSha256(authoritativePath),
    replayIndexSha256: fileSha256(replayIndexPath),
    waveContractSha256: fileSha256(waveContractPath),
    analyzerSha256: fileSha256(analyzerPath),
    independentVerifierSha256: fileSha256(verifierPath),
    binderToolSha256: fileSha256(binderToolPath),
    reverseCheckSha256: fileSha256(selfPath),
    closureFreezeUnchanged: true,
    closureHashSha256: replayResult.closureBefore.closureHashSha256,
    closureWorkerResultSha256: replayResult.closureBefore.workerResultSha256,
    closureCounts: replayResult.closureBefore.counts,
    jsPythonAgreement: true,
    proofCredit: true,
    proofCreditBoundary: "S1_DYNAMIC_OFFSET_6_OF_6_ONLY",
    centralCredit: false,
    rowDisposition: "OPEN_PENDING_DYNAMIC_LENGTH_HIGH_BITS_SYMBOLIC_162_AGGREGATE_ISABELLE_INDEPENDENT",
  };
  const serialized = render(report);
  if (args.report) {
    const reportPath = path.resolve(args.report);
    assert.equal(fs.existsSync(reportPath), false, `refusing existing reverse report: ${reportPath}`);
    fs.writeFileSync(reportPath, serialized, { encoding: "utf8", flag: "wx" });
  }
  process.stdout.write(serialized);
}

main();
