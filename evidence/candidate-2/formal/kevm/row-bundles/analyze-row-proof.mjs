import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const DEFAULT_FORBIDDEN = [
  "Runtime error",
  "Proof crashed",
  "timed out",
  "timeout",
  "canceled",
  "cancelled",
  "SMT solver error",
  "BackendError",
];

function countCollection(value) {
  if (Array.isArray(value)) return value.length;
  if (value && typeof value === "object") return Object.keys(value).length;
  return 0;
}

function pendingCount(proof, logText) {
  if (proof.pending !== undefined) return countCollection(proof.pending);
  const summary = logText.match(/\((\d+)\s+pending\s+and\s+\d+\s+failing\)/i);
  if (summary) return Number.parseInt(summary[1], 10);
  if (logText.includes(`PROOF PASSED: ${proof.id}`)) return 0;
  throw new Error("proof serialization has no pending set and the log has no pending summary");
}

export function analyzeProof({ side, proof, kcfg, logText, nodeTexts = [], expected }) {
  const forbidden = [...new Set([...DEFAULT_FORBIDDEN, ...(expected.forbiddenLogTokens ?? [])])];
  const forbiddenHits = forbidden.filter((token) => logText.toLowerCase().includes(token.toLowerCase()));
  if (forbiddenHits.length) throw new Error(`${side}: forbidden backend/log markers: ${forbiddenHits.join(", ")}`);

  if (proof.id !== expected.claimId) throw new Error(`${side}: claim id mismatch`);
  if (proof.admitted !== false) throw new Error(`${side}: admitted proof`);

  const actual = {
    nodes: countCollection(kcfg.nodes),
    edges: countCollection(kcfg.edges),
    covers: countCollection(kcfg.covers),
    terminal: countCollection(proof.terminal),
    stuck: countCollection(kcfg.stuck),
    vacuous: countCollection(kcfg.vacuous),
    pending: pendingCount(proof, logText),
    admitted: proof.admitted,
  };
  for (const [key, value] of Object.entries(expected.graph)) {
    if (actual[key] !== value) throw new Error(`${side}: graph ${key}=${actual[key]} expected ${value}`);
  }

  const statusMarker = expected.exitCode === 0 ? `PROOF PASSED: ${expected.claimId}` : `PROOF FAILED: ${expected.claimId}`;
  if (!logText.includes(statusMarker)) throw new Error(`${side}: missing status marker ${statusMarker}`);
  const witnessCorpus = `${logText}\n${JSON.stringify(kcfg)}\n${nodeTexts.join("\n")}`;
  for (const token of expected.witnessTokens) {
    if (!witnessCorpus.includes(token)) {
      throw new Error(`${side}: missing semantic witness token ${token}`);
    }
  }
  return actual;
}

function cli() {
  const [side, proofPath, kcfgPath, logPath, expectedPath] = process.argv.slice(2);
  if (!expectedPath) {
    throw new Error("usage: analyze-row-proof.mjs SIDE PROOF_JSON KCFG_JSON LOG EXPECTED_JSON");
  }
  const expected = JSON.parse(readFileSync(expectedPath, "utf8"));
  const proof = JSON.parse(readFileSync(proofPath, "utf8"));
  const kcfg = JSON.parse(readFileSync(kcfgPath, "utf8"));
  const nodesDirectory = resolve(kcfgPath, "..", "nodes");
  const preferredNodes = (proof.terminal ?? []).length ? proof.terminal : (kcfg.nodes ?? []);
  const nodeTexts = preferredNodes.map((node) => {
    try {
      return readFileSync(resolve(nodesDirectory, `${node}.json`), "utf8");
    } catch {
      return "";
    }
  });
  const graph = analyzeProof({
    side,
    proof,
    kcfg,
    logText: readFileSync(logPath, "utf8"),
    nodeTexts,
    expected,
  });
  process.stdout.write(`${JSON.stringify({ status: "PASS", side, graph }, null, 2)}\n`);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
  cli();
}
