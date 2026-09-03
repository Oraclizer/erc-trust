#!/usr/bin/env node
// Extracts deterministic graph shape and terminal-node anchors from a v3 or
// v4 calibration run.
// Output is explicitly calibration-only and is never discharge evidence.
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const [rootArgument, reportArgument] = process.argv.slice(2);
if (!rootArgument) throw new Error("usage: extract-dynamic-offset-calibration-v1.mjs OUTPUT_ROOT [REPORT_JSON]");
const root = path.resolve(rootArgument);
const text = (filePath) => fs.readFileSync(filePath, "utf8").replaceAll("\r\n", "\n");
const optionalText = (filePath) => fs.existsSync(filePath) ? text(filePath).trim() : null;
const json = (filePath) => JSON.parse(text(filePath));
const sha256 = (filePath) => crypto.createHash("sha256").update(fs.readFileSync(filePath)).digest("hex");
const count = (value) => Array.isArray(value) ? value.length : value && typeof value === "object" ? Object.keys(value).length : 0;
const logPath = path.join(root, "prove.log");
const log = text(logPath);
const proofIds = fs.readdirSync(path.join(root, "save"), { withFileTypes: true })
  .filter((entry) => entry.isDirectory() && /^[0-9a-f]{64}$/.test(entry.name))
  .map((entry) => entry.name);
assert.equal(proofIds.length, 1, "calibration must contain exactly one serialized proof ID");
const proofId = proofIds[0];
const proofRoot = path.join(root, "save", proofId);
const proofPath = path.join(proofRoot, "proof.json");
const kcfgPath = path.join(proofRoot, "kcfg", "kcfg.json");
const proof = json(proofPath);
const kcfg = json(kcfgPath);
assert.equal(proof.id, proofId);
const claimId = text(path.join(root, "claim-id.txt")).trim();
const side = text(path.join(root, "replay-side.txt")).trim();
const proofExitCode = Number.parseInt(text(path.join(root, "proof-exit-code.txt")).trim(), 10);
const launcherExitCode = Number.parseInt(text(path.join(root, "exit-code.txt")).trim(), 10);
const recordedRunClassification = optionalText(path.join(root, "run-classification.txt"));
const recordedSurvivorCount = optionalText(path.join(root, "post-run-owned-session-survivor-count.txt"));
let pending;
if (proof.pending !== undefined) pending = count(proof.pending);
else {
  const match = log.match(/\((\d+)\s+pending\s+and\s+\d+\s+failing\)/i);
  pending = match ? Number.parseInt(match[1], 10) : log.includes(`PROOF PASSED: ${proofId}`) ? 0 : null;
}
assert.notEqual(pending, null, "calibration cannot determine pending count");
const terminalNodes = [...(proof.terminal ?? [])].map((nodeId) => {
  const nodePath = path.join(proofRoot, "kcfg", "nodes", `${Number(nodeId)}.json`);
  const nodeText = text(nodePath);
  return {
    nodeId: Number(nodeId),
    path: nodePath,
    sha256: sha256(nodePath),
    observedTokenPresence: {
      EVMC_SUCCESS: nodeText.includes("EVMC_SUCCESS"),
      EVMC_REVERT: nodeText.includes("EVMC_REVERT"),
      emptyBytesDotBytes: nodeText.includes(".Bytes"),
      emptyOutputHex: nodeText.includes('"0x"'),
      emptyList: nodeText.includes(".List")
    }
  };
});
const value = {
  schemaVersion: 1,
  status: "CALIBRATION_CREDIT_0",
  proofCredit: false,
  claimId,
  side,
  proofId,
  proofExitCode,
  launcherExitCode,
  runClassification: recordedRunClassification ?? (
    side === "canonical-positive" && proofExitCode === 0 && launcherExitCode === 0
      ? "CALIBRATION_EXPECTED_POSITIVE_PROCESS_EXIT"
      : side === "mutant-negative" && proofExitCode === 1 && launcherExitCode === 1
        ? "CALIBRATION_EXPECTED_NEGATIVE_PROCESS_EXIT"
        : "CALIBRATION_PROCESS_EXIT_MISMATCH"
  ),
  runClassificationRecordedByLauncher: recordedRunClassification !== null,
  inputIntegrityStatus: text(path.join(root, "input-integrity-status.txt")).trim(),
  ownedSessionSurvivorCount: recordedSurvivorCount === null ? null : Number.parseInt(recordedSurvivorCount, 10),
  ownedSessionSurvivorCountRecordedByLauncher: recordedSurvivorCount !== null,
  graph: {
    nodes: count(kcfg.nodes),
    edges: count(kcfg.edges),
    covers: count(kcfg.covers),
    terminal: count(proof.terminal),
    stuck: count(kcfg.stuck),
    vacuous: count(kcfg.vacuous),
    pending,
    bounded: count(kcfg.bounded),
    admitted: proof.admitted
  },
  statusMarkers: {
    proofPassed: log.includes(`PROOF PASSED: ${proofId}`),
    proofFailed: log.includes(`PROOF FAILED: ${proofId}`)
  },
  artifacts: {
    proof: { path: proofPath, sha256: sha256(proofPath) },
    kcfg: { path: kcfgPath, sha256: sha256(kcfgPath) },
    log: { path: logPath, sha256: sha256(logPath) },
    terminalNodes
  },
  useBoundary: "May seed a future pre-run exact graph contract; must not be reclassified as authoritative replay evidence."
};
const serialized = `${JSON.stringify(value, null, 2)}\n`;
if (reportArgument) fs.writeFileSync(path.resolve(reportArgument), serialized, { encoding: "utf8", flag: "wx" });
process.stdout.write(serialized);
