#!/usr/bin/env node
// Analyzer for one completed S1 ABI-04 dynamic-offset replay. The expected
// descriptor must bind the exact serialized graph; this tool never infers an
// expected graph from the replay it is judging.
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const forbiddenLogTokens = [
  "Runtime error",
  "Proof crashed",
  "timed out",
  "timeout",
  "canceled",
  "cancelled",
  "SMT solver error",
  "BackendError"
];

const sha256 = (value) => crypto.createHash("sha256").update(value).digest("hex");
const fileSha256 = (filePath) => sha256(fs.readFileSync(filePath));
const readText = (filePath) => fs.readFileSync(filePath, "utf8").replaceAll("\r\n", "\n");
const readJson = (filePath) => JSON.parse(readText(filePath));
const readInteger = (filePath) => {
  const value = Number.parseInt(readText(filePath).trim(), 10);
  assert.ok(Number.isSafeInteger(value), `not an integer: ${filePath}`);
  return value;
};
const countCollection = (value) => Array.isArray(value) ? value.length : value && typeof value === "object" ? Object.keys(value).length : 0;

const applyLabel = (value) => value?.label?.name;
const findApplies = (value, label, matches = []) => {
  if (Array.isArray(value)) {
    for (const item of value) findApplies(item, label, matches);
  } else if (value && typeof value === "object") {
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
  throw new Error("proof serialization has no pending set and the log has no pending summary");
}

function parseSnapshotManifest(snapshotRoot) {
  const manifestPath = path.join(snapshotRoot, "snapshot-files.sha256");
  const entries = readText(manifestPath).trim().split("\n").filter(Boolean).map((line) => {
    const match = line.match(/^([0-9a-f]{64})\s+[ *](.+)$/);
    assert.ok(match, `invalid snapshot manifest line: ${line}`);
    return { sha256: match[1], relativePath: match[2].replace(/^\.\//, "") };
  });
  assert.ok(entries.length > 0, "empty snapshot manifest");
  assert.equal(new Set(entries.map(({ relativePath }) => relativePath)).size, entries.length, "duplicate snapshot path");
  for (const entry of entries) {
    const filePath = path.resolve(snapshotRoot, entry.relativePath);
    assert.ok(filePath.startsWith(`${path.resolve(snapshotRoot)}${path.sep}`), `snapshot path escape: ${entry.relativePath}`);
    assert.equal(fileSha256(filePath), entry.sha256, `snapshot SHA-256 mismatch: ${entry.relativePath}`);
  }
  return { manifestPath, entries };
}

function parseLiveHashes(filePath) {
  const entries = readText(filePath).trim().split("\n").filter(Boolean).map((line) => {
    const match = line.match(/^([0-9a-f]{64})\s+(.+)$/);
    assert.ok(match, `invalid live hash line: ${line}`);
    return { sha256: match[1], filePath: match[2] };
  });
  assert.ok(entries.length >= 7, `expected at least seven live input hashes: ${filePath}`);
  return entries;
}

function main() {
  const [outputArgument, expectedArgument, reportArgument] = process.argv.slice(2);
  if (!outputArgument || !expectedArgument) {
    throw new Error("usage: analyze-dynamic-offset-replay-v1.mjs OUTPUT_ROOT EXPECTED_GRAPH_JSON [REPORT_JSON]");
  }
  const outputRoot = path.resolve(outputArgument);
  const expectedPath = path.resolve(expectedArgument);
  const expected = readJson(expectedPath);
  const snapshotRoot = path.join(outputRoot, "input-snapshot");
  assert.equal(expected.schemaVersion, 1);
  assert.ok(["canonical-positive", "mutant-negative"].includes(expected.side));
  assert.equal(readText(path.join(outputRoot, "claim-id.txt")).trim(), expected.claimId);
  assert.equal(readText(path.join(outputRoot, "replay-side.txt")).trim(), expected.side);
  assert.equal(readInteger(path.join(outputRoot, "expected-exit-code.txt")), expected.processExitCode);
  assert.equal(readInteger(path.join(outputRoot, "proof-exit-code.txt")), expected.processExitCode);
  assert.equal(readInteger(path.join(outputRoot, "exit-code.txt")), expected.launcherExitCode);
  assert.equal(readText(path.join(outputRoot, "run-classification.txt")).trim(), expected.runClassification);
  assert.equal(readText(path.join(outputRoot, "input-integrity-status.txt")).trim(), "PASS");
  assert.equal(readInteger(path.join(outputRoot, "post-run-owned-session-survivor-count.txt")), 0);
  assert.ok(readInteger(path.join(outputRoot, "elapsed-seconds.txt")) >= 0);
  for (const name of ["launcher-pid.txt", "child-pid.txt", "child-sid.txt", "child-pgid.txt"]) assert.ok(readInteger(path.join(outputRoot, name)) > 0);
  assert.equal(readInteger(path.join(outputRoot, "child-sid.txt")), readInteger(path.join(outputRoot, "child-pid.txt")));
  assert.equal(readInteger(path.join(outputRoot, "child-pgid.txt")), readInteger(path.join(outputRoot, "child-pid.txt")));

  const snapshot = parseSnapshotManifest(snapshotRoot);
  assert.equal(readText(path.join(outputRoot, "snapshot-manifest.sha256")).trim(), fileSha256(snapshot.manifestPath));
  const snapshotExpectedPath = path.join(snapshotRoot, "expected-graph-contract.json");
  assert.equal(fileSha256(snapshotExpectedPath), fileSha256(expectedPath), "pre-run expected graph snapshot hash mismatch");
  assert.deepEqual(readJson(snapshotExpectedPath), expected, "pre-run expected graph snapshot content mismatch");
  const execution = readJson(path.join(snapshotRoot, "execution-manifest.json"));
  const priorPairBinders = execution.priorAuthoritativePairBinders ?? [];
  const before = parseLiveHashes(path.join(outputRoot, "live-input-hashes-before.sha256"));
  const after = parseLiveHashes(path.join(outputRoot, "live-input-hashes-after.sha256"));
  assert.deepEqual(after, before, "live input hashes changed during replay");
  assert.deepEqual(priorPairBinders, [], "prior authoritative pair binders are forbidden for the S1 wave");
  assert.equal(execution.priorAuthoritativePairBindersIncluded, false, "execution manifest prior binder flag drift");
  assert.equal(before.length, 7, "live input hash cardinality mismatch");
  assert.equal(fileSha256(path.join(snapshotRoot, "launcher.sh")), before[0].sha256, "executed launcher snapshot mismatch");
  assert.equal(before[1].sha256, expected.sourceClaimSha256, "live source claim hash mismatch");
  assert.equal(fileSha256(path.join(snapshotRoot, "analyze-dynamic-offset-replay-v1.mjs")), before[2].sha256, "analysis tool snapshot mismatch");
  assert.equal(fileSha256(path.join(snapshotRoot, "verify-dynamic-offset-replay-v1.py")), before[3].sha256, "independent verifier snapshot mismatch");
  assert.equal(fileSha256(path.join(snapshotRoot, "verify-freeze-receipt.py")), before[4].sha256, "closure freeze verifier snapshot mismatch");
  assert.equal(fileSha256(path.join(outputRoot, "claim.k")), expected.strippedClaimSha256);
  assert.equal(fileSha256(path.join(snapshotRoot, "claim-source.k")), expected.sourceClaimSha256);
  assert.equal(execution.analysisToolSha256, before[2].sha256, "execution manifest analysis tool hash mismatch");
  assert.equal(execution.independentVerifierSha256, before[3].sha256, "execution manifest independent verifier hash mismatch");
  assert.equal(execution.definitionKoreSha256, before[5].sha256, "execution manifest definition hash mismatch");
  assert.equal(execution.compiledJsonSha256, before[6].sha256, "execution manifest compiled definition hash mismatch");

  const saveRoot = path.join(outputRoot, "save");
  const proofIds = fs.readdirSync(saveRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && /^[0-9a-f]{64}$/.test(entry.name))
    .map((entry) => entry.name);
  assert.deepEqual(proofIds, [expected.proofId], "proof ID exact-set mismatch");
  const proofRoot = path.join(saveRoot, expected.proofId);
  const proofPath = path.join(proofRoot, "proof.json");
  const kcfgPath = path.join(proofRoot, "kcfg", "kcfg.json");
  const nodesRoot = path.join(proofRoot, "kcfg", "nodes");
  const logPath = path.join(outputRoot, "prove.log");
  const proof = readJson(proofPath);
  const kcfg = readJson(kcfgPath);
  const logText = readText(logPath);
  assert.equal(proof.id, expected.proofId);
  assert.equal(proof.admitted, false, "admitted proof");
  for (const token of forbiddenLogTokens) assert.ok(!logText.toLowerCase().includes(token.toLowerCase()), `forbidden log token: ${token}`);
  assert.ok(logText.includes(expected.statusMarker), `missing proof status marker: ${expected.statusMarker}`);

  const graph = {
    nodes: countCollection(kcfg.nodes),
    edges: countCollection(kcfg.edges),
    covers: countCollection(kcfg.covers),
    terminal: countCollection(proof.terminal),
    stuck: countCollection(kcfg.stuck),
    vacuous: countCollection(kcfg.vacuous),
    pending: pendingCount(proof, logText),
    bounded: countCollection(kcfg.bounded),
    admitted: proof.admitted
  };
  assert.deepEqual(graph, expected.graph, "serialized graph differs from exact expected contract");

  const terminalNodeIds = [...(proof.terminal ?? [])].map((value) => Number(value));
  const terminalNodes = terminalNodeIds.map((nodeId) => {
    const nodePath = path.join(nodesRoot, `${nodeId}.json`);
    return { nodeId, path: nodePath, sha256: fileSha256(nodePath), text: readText(nodePath), json: readJson(nodePath) };
  });
  assert.deepEqual(terminalNodeIds, expected.terminalNodeIds ?? terminalNodeIds, "terminal node ID exact-set mismatch");
  const terminalCorpus = terminalNodes.map(({ text }) => text).join("\n");
  for (const token of expected.terminalWitnessTokens ?? []) assert.ok(terminalCorpus.includes(token), `missing terminal witness token: ${token}`);
  let terminalWitnessObservation = null;
  if (expected.side === "canonical-positive") {
    assert.equal(graph.terminal, 0);
    assert.equal(graph.pending, 0);
    assert.equal(graph.stuck, 0);
    assert.equal(graph.vacuous, 0);
    assert.equal(graph.bounded, 0);
  } else {
    assert.equal(graph.terminal, 1);
    assert.equal(graph.pending, 0);
    assert.equal(graph.stuck, 0);
    assert.equal(graph.vacuous, 0);
    assert.equal(graph.bounded, 0);
    const witness = expected.terminalWitness;
    assert.ok(witness, "mutant negative requires a structural terminal witness contract");
    const terminal = terminalNodes[0].json;
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
    const endpointStorage = cellValue(directChildApply(endpoint, "<storage>"), "<storage>");
    const endpointOrigStorage = cellValue(directChildApply(endpoint, "<origStorage>"), "<origStorage>");
    assert.deepEqual(endpointStorage, endpointOrigStorage, "endpoint storage/original-storage did not stutter");
    const endpointNonce = tokenValue(cellValue(directChildApply(endpoint, "<nonce>"), "<nonce>"), "endpoint nonce");
    const senderNonce = tokenValue(cellValue(directChildApply(sender, "<nonce>"), "<nonce>"), "sender nonce");
    assert.equal(endpointNonce, witness.endpointNonce);
    assert.equal(senderNonce, witness.senderNonce);
    terminalWitnessObservation = {
      nodeId: terminalNodes[0].nodeId,
      outputToken: tokenValue(output, "<output>"),
      statusLabel: applyLabel(status),
      logLabel: applyLabel(log),
      txPendingLabel: applyLabel(txPending),
      endpointAccountId: witness.endpointAccountId,
      endpointNonce,
      endpointStorageEqualsOriginal: true,
      senderAccountId: witness.senderAccountId,
      senderNonce,
    };
  }

  const report = {
    schemaVersion: 1,
    status: "PASS",
    obligationId: "ABI-04",
    stage: "S1",
    claimId: expected.claimId,
    proofId: expected.proofId,
    side: expected.side,
    processExitCode: expected.processExitCode,
    launcherExitCode: expected.launcherExitCode,
    graph,
    elapsedSeconds: readInteger(path.join(outputRoot, "elapsed-seconds.txt")),
    inputIntegrityStatus: "PASS",
    ownedSessionSurvivorCount: 0,
    runnerSha256: fileSha256(path.join(snapshotRoot, "launcher.sh")),
    analysisToolSha256: fileSha256(path.join(snapshotRoot, "analyze-dynamic-offset-replay-v1.mjs")),
    independentVerifierSha256: fileSha256(path.join(snapshotRoot, "verify-dynamic-offset-replay-v1.py")),
    sourceClaimSha256: fileSha256(path.join(snapshotRoot, "claim-source.k")),
    strippedClaimSha256: fileSha256(path.join(outputRoot, "claim.k")),
    proof: { path: proofPath, sha256: fileSha256(proofPath) },
    kcfg: { path: kcfgPath, sha256: fileSha256(kcfgPath) },
    log: { path: logPath, sha256: fileSha256(logPath) },
    snapshotManifest: { path: snapshot.manifestPath, sha256: fileSha256(snapshot.manifestPath) },
    terminalWitnesses: terminalNodes.map(({ nodeId, path: nodePath, sha256: digest }) => ({ nodeId, path: nodePath, sha256: digest })),
    terminalWitnessObservation,
    expectedGraphContract: { path: expectedPath, sha256: fileSha256(expectedPath) },
    proofCreditBoundary: "LEAF_REPLAY_ONLY_NOT_CENTRAL_DISCHARGE"
  };
  const serialized = `${JSON.stringify(report, null, 2)}\n`;
  if (reportArgument) fs.writeFileSync(path.resolve(reportArgument), serialized, { encoding: "utf8", flag: "wx" });
  process.stdout.write(serialized);
}

main();
