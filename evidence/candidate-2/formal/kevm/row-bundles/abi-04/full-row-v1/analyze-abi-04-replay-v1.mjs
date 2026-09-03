#!/usr/bin/env node
// Independent JavaScript structural analyzer for one ABI-04 full-row replay.
// Unlike the S1 calibration-sensitive analyzer, this analyzer checks the
// acceptance contract recorded before execution and does not derive a frozen
// expected graph from the result it is judging.
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const analyzerPath = fileURLToPath(import.meta.url);
const familyDir = path.dirname(analyzerPath);
const rowDir = path.dirname(familyDir);
const repositoryRoot = path.resolve(rowDir, "../../../..");

const forbiddenLogTokens = [
  "Runtime error", "Proof crashed", "timed out", "timeout", "canceled",
  "cancelled", "SMT solver error", "BackendError",
];
const sha256 = (value) => crypto.createHash("sha256").update(value).digest("hex");
const fileSha256 = (filePath) => sha256(fs.readFileSync(filePath));
const readText = (filePath) => fs.readFileSync(filePath, "utf8").replaceAll("\r\n", "\n");
const readJson = (filePath) => JSON.parse(readText(filePath));
const repositoryBound = (relativePath, label) => {
  assert.equal(path.isAbsolute(relativePath), false, `${label}: expected repository-relative path`);
  const resolved = path.resolve(repositoryRoot, ...relativePath.split("/"));
  assert.ok(resolved.startsWith(`${repositoryRoot}${path.sep}`), `${label}: repository path escape`);
  return resolved;
};
const readInteger = (filePath) => {
  const value = Number.parseInt(readText(filePath).trim(), 10);
  assert.ok(Number.isSafeInteger(value), `not an integer: ${filePath}`);
  return value;
};
const countCollection = (value) => Array.isArray(value) ? value.length : value && typeof value === "object" ? Object.keys(value).length : 0;
const applyLabel = (value) => value?.label?.name;
const findApplies = (value, label, matches = []) => {
  if (Array.isArray(value)) for (const item of value) findApplies(item, label, matches);
  else if (value && typeof value === "object") {
    if (applyLabel(value) === label) matches.push(value);
    for (const item of Object.values(value)) findApplies(item, label, matches);
  }
  return matches;
};
const directChildApply = (value, label) => (value?.args ?? []).find((item) => applyLabel(item) === label);
const cellValue = (cell, label) => {
  assert.ok(cell, `missing ${label} cell`);
  assert.equal(cell.args?.length, 1, `${label} cell arity`);
  return cell.args[0];
};
const singleCell = (root, label) => {
  const cells = findApplies(root, label);
  assert.equal(cells.length, 1, `expected one ${label} cell`);
  return cells[0];
};
const tokenValue = (value, label) => {
  assert.equal(value?.node, "KToken", `${label} is not a KToken`);
  return value.token;
};

function pendingCount(proof, logText) {
  if (proof.pending !== undefined) return countCollection(proof.pending);
  const summary = logText.match(/\((\d+)\s+pending\s+and\s+\d+\s+failing\)/i);
  if (summary) return Number.parseInt(summary[1], 10);
  if (logText.includes(`PROOF PASSED: ${proof.id}`)) return 0;
  throw new Error("proof serialization has no pending set and log has no pending summary");
}

function parseSnapshotManifest(snapshotRoot) {
  const manifestPath = path.join(snapshotRoot, "snapshot-files.json");
  const entries = readJson(manifestPath);
  assert.ok(Array.isArray(entries) && entries.length > 0, "empty snapshot manifest");
  assert.equal(new Set(entries.map((item) => item.path)).size, entries.length, "duplicate snapshot path");
  const lexicalRoot = path.resolve(snapshotRoot);
  const realRoot = fs.realpathSync(lexicalRoot);
  for (const entry of entries) {
    assert.match(entry.sha256, /^[0-9a-f]{64}$/);
    const target = path.resolve(snapshotRoot, ...entry.path.split("/"));
    assert.ok(target.startsWith(`${lexicalRoot}${path.sep}`), `snapshot path escape: ${entry.path}`);
    const realTarget = fs.realpathSync(target);
    assert.ok(realTarget.startsWith(`${realRoot}${path.sep}`), `snapshot symlink escape: ${entry.path}`);
    assert.equal(fs.statSync(realTarget).isFile(), true, `snapshot entry is not a file: ${entry.path}`);
    assert.equal(fileSha256(target), entry.sha256, `snapshot mismatch: ${entry.path}`);
  }
  return { manifestPath, entries };
}

function terminalObservation(terminal, witness) {
  const output = cellValue(singleCell(terminal, "<output>"), "<output>");
  const status = cellValue(singleCell(terminal, "<statusCode>"), "<statusCode>");
  const log = cellValue(singleCell(terminal, "<log>"), "<log>");
  const txPending = cellValue(singleCell(terminal, "<txPending>"), "<txPending>");
  assert.equal(tokenValue(output, "<output>"), witness.outputToken);
  assert.equal(applyLabel(status), witness.statusLabel);
  assert.equal(applyLabel(log), witness.logLabel);
  assert.equal(applyLabel(txPending), witness.txPendingLabel);
  const accounts = findApplies(terminal, "<account>");
  const accountById = (accountId) => accounts.find((account) => {
    const idCell = directChildApply(account, "<acctID>");
    return idCell && tokenValue(cellValue(idCell, "<acctID>"), "<acctID>") === accountId;
  });
  const endpoint = accountById(witness.endpointAccountId);
  const sender = accountById(witness.senderAccountId);
  assert.ok(endpoint, "missing endpoint account in terminal witness");
  assert.ok(sender, "missing sender account in terminal witness");
  const storage = cellValue(directChildApply(endpoint, "<storage>"), "<storage>");
  const originalStorage = cellValue(directChildApply(endpoint, "<origStorage>"), "<origStorage>");
  assert.deepEqual(storage, originalStorage, "endpoint storage did not stutter");
  const endpointNonce = tokenValue(cellValue(directChildApply(endpoint, "<nonce>"), "<nonce>"), "endpoint nonce");
  const senderNonce = tokenValue(cellValue(directChildApply(sender, "<nonce>"), "<nonce>"), "sender nonce");
  assert.equal(endpointNonce, witness.endpointNonce);
  assert.equal(senderNonce, witness.senderNonce);
  return {
    outputToken: tokenValue(output, "<output>"), statusLabel: applyLabel(status),
    logLabel: applyLabel(log), txPendingLabel: applyLabel(txPending),
    endpointAccountId: witness.endpointAccountId, endpointNonce,
    endpointStorageEqualsOriginal: true, senderAccountId: witness.senderAccountId, senderNonce,
  };
}

function main() {
  const [outputArgument, indexArgument, reportArgument] = process.argv.slice(2);
  if (!outputArgument || !indexArgument) throw new Error("usage: analyze-abi-04-replay-v1.mjs OUTPUT_ROOT INDEX_JSON [REPORT_JSON]");
  const outputRoot = path.resolve(outputArgument);
  const indexPath = path.resolve(indexArgument);
  const index = readJson(indexPath);
  assert.equal(index.kind, "ABI04_FULL_ROW_REPLAY_INDEX_V1");
  const replayId = readText(path.join(outputRoot, "replay-id.txt")).trim();
  const record = index.records.find((item) => item.replayId === replayId);
  assert.ok(record, `replay absent from exact index: ${replayId}`);
  const snapshotRoot = path.join(outputRoot, "input-snapshot");
  assert.equal(readText(path.join(outputRoot, "semantic-claim-id.txt")).trim(), record.semanticClaimId);
  assert.equal(readText(path.join(outputRoot, "execution-side.txt")).trim(), record.executionSide);
  assert.equal(readInteger(path.join(outputRoot, "expected-exit-code.txt")), record.expectedProcessExitCode);
  assert.equal(readInteger(path.join(outputRoot, "proof-exit-code.txt")), record.expectedProcessExitCode);
  assert.equal(readInteger(path.join(outputRoot, "exit-code.txt")), record.expectedProcessExitCode);
  assert.equal(readText(path.join(outputRoot, "input-integrity-status.txt")).trim(), "PASS");
  assert.equal(readInteger(path.join(outputRoot, "post-run-owned-session-survivor-count.txt")), 0);
  assert.ok(readInteger(path.join(outputRoot, "elapsed-seconds.txt")) >= 0);
  const snapshot = parseSnapshotManifest(snapshotRoot);
  assert.equal(fileSha256(snapshot.manifestPath), readText(path.join(outputRoot, "snapshot-manifest.sha256")).trim());
  assert.equal(fileSha256(path.join(snapshotRoot, "claim-source.k")), record.claim.sha256);
  assert.equal(fileSha256(path.join(outputRoot, "claim.k")), record.strippedClaimSha256);
  assert.deepEqual(readJson(path.join(snapshotRoot, "record.json")), record);
  assert.deepEqual(readJson(path.join(snapshotRoot, "full-row-replay-index-v1.json")), index);
  const execution = readJson(path.join(snapshotRoot, "execution-manifest.json"));
  const preClosure = readJson(path.join(outputRoot, "pre-proof-closure-verification.json"));
  const closureFilesBefore = readJson(path.join(outputRoot, "closure-freeze-files-before.json"));
  assert.ok(Array.isArray(closureFilesBefore) && closureFilesBefore.length > 0, "empty closure freeze manifest");
  const expectedSnapshotPaths = [
    "run-abi-04-replay-v1.mjs", "claim-source.k", "analyze-abi-04-replay-v1.mjs",
    "verify_abi_04_replay_v1.py", "verify-freeze-receipt.py", "full-row-replay-index-v1.json",
    "s1-toolchain-contract-v1.json", "record.json", "execution-manifest.json",
    ...closureFilesBefore.map((item) => `closure-freeze/${item.path}`),
  ].sort();
  assert.deepEqual(snapshot.entries.map((item) => item.path).sort(), expectedSnapshotPaths, "snapshot exact path set mismatch");
  const snapshotByPath = new Map(snapshot.entries.map((item) => [item.path, item]));
  const expectedStaticSnapshotHashes = {
    "run-abi-04-replay-v1.mjs": index.sourceBinding.tools.runner.sha256,
    "claim-source.k": record.claim.sha256,
    "analyze-abi-04-replay-v1.mjs": index.sourceBinding.tools.javascriptAnalyzer.sha256,
    "verify_abi_04_replay_v1.py": index.sourceBinding.tools.pythonVerifier.sha256,
    "verify-freeze-receipt.py": index.sourceBinding.tools.freezeVerifier.sha256,
    "full-row-replay-index-v1.json": fileSha256(indexPath),
    "s1-toolchain-contract-v1.json": index.sourceBinding.toolchainContract.sha256,
  };
  for (const [relativePath, expectedSha256] of Object.entries(expectedStaticSnapshotHashes)) assert.equal(snapshotByPath.get(relativePath)?.sha256, expectedSha256, `snapshot bound hash mismatch: ${relativePath}`);
  for (const item of closureFilesBefore) assert.equal(snapshotByPath.get(`closure-freeze/${item.path}`)?.sha256, item.sha256, `snapshot closure hash mismatch: ${item.path}`);
  const before = readJson(path.join(outputRoot, "live-input-hashes-before.json"));
  const after = readJson(path.join(outputRoot, "live-input-hashes-after.json"));
  assert.deepEqual(after, before, "live input hashes changed during replay");
  const definition = record.executionSide === "canonical-positive" ? index.definitions.canonicalPositive : index.definitions.mutantNegative;
  const childPid = readInteger(path.join(outputRoot, "child-pid.txt"));
  const childSid = readInteger(path.join(outputRoot, "child-sid.txt"));
  const childPgid = readInteger(path.join(outputRoot, "child-pgid.txt"));
  const launcherPgid = readInteger(path.join(outputRoot, "launcher-pgid.txt"));
  assert.equal(childPid, childSid); assert.equal(childPid, childPgid); assert.notEqual(childPgid, launcherPgid);
  const birthReceipt = readJson(path.join(outputRoot, "child-birth-receipt.json"));
  const sessionReceipt = readJson(path.join(outputRoot, "child-session-receipt.json"));
  assert.deepEqual(birthReceipt, {
    schemaVersion: 1, kind: "ABI04_PROOF_CHILD_BIRTH_RECEIPT_V1", pid: childPid,
    bootId: birthReceipt.bootId, startTimeTicks: birthReceipt.startTimeTicks,
  });
  assert.match(birthReceipt.bootId, /^[0-9a-f-]{36}$/); assert.match(birthReceipt.startTimeTicks, /^[0-9]+$/);
  assert.equal(birthReceipt.bootId, readText("/proc/sys/kernel/random/boot_id").trim());
  assert.deepEqual(sessionReceipt, {
    schemaVersion: 1, kind: "ABI04_PROOF_CHILD_SESSION_RECEIPT_V1", pid: childPid, sid: childSid, pgid: childPgid,
    launcherPgid, bootId: birthReceipt.bootId, startTimeTicks: birthReceipt.startTimeTicks,
  });
  const expectedLiveInputs = [
    { role: "runner", path: repositoryBound(index.sourceBinding.tools.runner.path, "runner"), sha256: index.sourceBinding.tools.runner.sha256 },
    { role: "claim", path: repositoryBound(record.claim.path, "claim"), sha256: record.claim.sha256 },
    { role: "javascript-analyzer", path: repositoryBound(index.sourceBinding.tools.javascriptAnalyzer.path, "javascript-analyzer"), sha256: index.sourceBinding.tools.javascriptAnalyzer.sha256 },
    { role: "python-verifier", path: repositoryBound(index.sourceBinding.tools.pythonVerifier.path, "python-verifier"), sha256: index.sourceBinding.tools.pythonVerifier.sha256 },
    { role: "freeze-verifier", path: repositoryBound(index.sourceBinding.tools.freezeVerifier.path, "freeze-verifier"), sha256: index.sourceBinding.tools.freezeVerifier.sha256 },
    { role: "replay-index", path: indexPath, sha256: fileSha256(indexPath) },
    { role: "definition.kore", path: path.join(definition.absoluteRoot, "definition.kore"), sha256: definition.definitionKoreSha256 },
    { role: "compiled.json", path: path.join(definition.absoluteRoot, "compiled.json"), sha256: definition.compiledJsonSha256 },
    { role: "closure-worker-result", path: path.join(execution.closureFreezeRoot, "worker-result.json"), sha256: preClosure.workerResultSha256 },
    { role: "node-executable", path: index.toolchain.node.executable, sha256: index.toolchain.node.sha256 },
    { role: "python-executable", path: index.toolchain.python.executable, sha256: index.toolchain.python.sha256 },
    { role: "bash-executable", path: index.toolchain.bash.executable, sha256: index.toolchain.bash.sha256 },
    { role: "kevm-executable", path: index.toolchain.kevm.executable, sha256: index.toolchain.kevm.sha256 },
    { role: "kprove-executable", path: index.toolchain.kprove.executable, sha256: index.toolchain.kprove.sha256 },
    { role: "kore-rpc-executable", path: index.toolchain.koreRpc.executable, sha256: index.toolchain.koreRpc.sha256 },
    { role: "setsid-executable", path: index.toolchain.setsid.executable, sha256: index.toolchain.setsid.sha256 },
    { role: "timeout-executable", path: index.toolchain.timeout.executable, sha256: index.toolchain.timeout.sha256 },
    { role: "ps-executable", path: index.toolchain.ps.executable, sha256: index.toolchain.ps.sha256 },
  ];
  assert.deepEqual(before, expectedLiveInputs, "live input exact ordered role/path/hash mismatch");
  assert.equal(execution.replayId, replayId);
  assert.equal(execution.claimSourceSha256, record.claim.sha256);
  assert.equal(execution.strippedClaimSha256, record.strippedClaimSha256);
  assert.equal(execution.definitionKoreSha256, before[6].sha256);
  assert.equal(execution.compiledJsonSha256, before[7].sha256);
  assert.equal(execution.closureFreezeWorkerResultSha256, before[8].sha256);
  const expectedCommand = [
    index.toolchain.setsid.executable, "--wait", index.toolchain.timeout.executable, "--signal=TERM", "--kill-after=30s", "7200",
    index.toolchain.kevm.executable, "prove", path.join(outputRoot, "claim.k"), "--definition", definition.absoluteRoot,
    "--spec-module", record.module, "--save-directory", path.join(outputRoot, "save"), "--temp-directory", path.join(outputRoot, "temp"),
    "--kore-rpc-command", index.toolchain.koreRpc.executable, "--no-use-booster", "--workers", "1", "--force-sequential", "--max-depth", "1",
  ];
  assert.deepEqual(execution.command, expectedCommand, "execution command mismatch");
  assert.deepEqual(readJson(path.join(outputRoot, "invocation.json")), expectedCommand, "invocation command mismatch");
  assert.equal(preClosure.status, "PASS");
  assert.equal(readJson(path.join(outputRoot, "post-proof-closure-verification.json")).status, "PASS");
  assert.deepEqual(readJson(path.join(outputRoot, "closure-freeze-files-after.json")), closureFilesBefore, "closure freeze changed during replay");

  const saveRoot = path.join(outputRoot, "save");
  const proofIds = fs.readdirSync(saveRoot, { withFileTypes: true }).filter((entry) => entry.isDirectory() && /^[0-9a-f]{64}$/.test(entry.name)).map((entry) => entry.name);
  assert.equal(proofIds.length, 1, "proof ID exact-set mismatch");
  const proofId = proofIds[0];
  const proofRoot = path.join(saveRoot, proofId);
  const proofPath = path.join(proofRoot, "proof.json");
  const kcfgPath = path.join(proofRoot, "kcfg", "kcfg.json");
  const nodesRoot = path.join(proofRoot, "kcfg", "nodes");
  const logPath = path.join(outputRoot, "prove.log");
  const proof = readJson(proofPath);
  const kcfg = readJson(kcfgPath);
  const logText = readText(logPath);
  assert.equal(proof.id, proofId);
  assert.equal(proof.admitted, false, "admitted proof");
  for (const token of forbiddenLogTokens) assert.ok(!logText.toLowerCase().includes(token.toLowerCase()), `forbidden log token: ${token}`);
  const marker = record.executionSide === "canonical-positive" ? `PROOF PASSED: ${proofId}` : `PROOF FAILED: ${proofId}`;
  assert.ok(logText.includes(marker), `missing proof status marker: ${marker}`);
  const graph = {
    nodes: countCollection(kcfg.nodes), edges: countCollection(kcfg.edges), covers: countCollection(kcfg.covers),
    terminal: countCollection(proof.terminal), stuck: countCollection(kcfg.stuck), vacuous: countCollection(kcfg.vacuous),
    pending: pendingCount(proof, logText), bounded: countCollection(kcfg.bounded), admitted: proof.admitted,
  };
  assert.ok(graph.nodes >= 1 && graph.edges >= 0 && graph.covers >= 0, "invalid KCFG structural cardinality");
  assert.ok(graph.terminal <= graph.nodes, "terminal nodes exceed KCFG nodes");
  assert.deepEqual(index.acceptancePolicy.topologyCardinalityNotClaimed, ["nodes", "edges", "covers"]);
  assert.equal(index.acceptancePolicy.structuralCardinalityChecksRequired, true);
  assert.deepEqual({ terminal: graph.terminal, stuck: graph.stuck, vacuous: graph.vacuous, pending: graph.pending, bounded: graph.bounded, admitted: graph.admitted }, record.acceptanceContract.graph);
  const terminalNodeIds = [...(proof.terminal ?? [])].map(Number);
  const terminalNodes = terminalNodeIds.map((nodeId) => {
    const nodePath = path.join(nodesRoot, `${nodeId}.json`);
    return { nodeId, path: nodePath, sha256: fileSha256(nodePath), json: readJson(nodePath) };
  });
  let witness = null;
  if (record.executionSide === "canonical-positive") assert.equal(terminalNodes.length, 0);
  else {
    assert.equal(terminalNodes.length, 1);
    witness = { nodeId: terminalNodes[0].nodeId, ...terminalObservation(terminalNodes[0].json, record.terminalWitnessContract) };
  }
  const report = {
    schemaVersion: 1, kind: "ABI04_FULL_ROW_REPLAY_JS_ANALYSIS_V1", status: "PASS", obligationId: "ABI-04",
    replayId, semanticClaimId: record.semanticClaimId, executionClaimId: record.executionClaimId,
    side: record.side, executionSide: record.executionSide, proofId,
    processExitCode: record.expectedProcessExitCode, launcherExitCode: record.expectedProcessExitCode,
    graph, elapsedSeconds: readInteger(path.join(outputRoot, "elapsed-seconds.txt")), inputIntegrityStatus: "PASS",
    ownedSessionSurvivorCount: 0, claimSourceSha256: record.claim.sha256, strippedClaimSha256: record.strippedClaimSha256,
    definitionKoreSha256: execution.definitionKoreSha256, compiledJsonSha256: execution.compiledJsonSha256,
    proof: { path: proofPath, sha256: fileSha256(proofPath) }, kcfg: { path: kcfgPath, sha256: fileSha256(kcfgPath) },
    log: { path: logPath, sha256: fileSha256(logPath) }, snapshotManifest: { path: snapshot.manifestPath, sha256: fileSha256(snapshot.manifestPath) },
    terminalWitnesses: terminalNodes.map(({ nodeId, path: nodePath, sha256: digest }) => ({ nodeId, path: nodePath, sha256: digest })),
    terminalWitnessObservation: witness, closureFreezeUnchanged: true,
    proofCreditBoundary: "ONE_EXACT_REPLAY_ONLY_NOT_AGGREGATE_OR_CENTRAL",
  };
  const serialized = `${JSON.stringify(report, null, 2)}\n`;
  if (reportArgument) fs.writeFileSync(path.resolve(reportArgument), serialized, { encoding: "utf8", flag: "wx" });
  process.stdout.write(serialized);
}

main();
