import { createHash } from "node:crypto";
import { existsSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { basename, relative, resolve, sep } from "node:path";

const args = process.argv.slice(2);
const rootIndex = args.indexOf("--output-root");
const laneIndex = args.indexOf("--lane");
const reportIndex = args.indexOf("--report");
if (rootIndex < 0 || laneIndex < 0 || !args[rootIndex + 1] || !args[laneIndex + 1]) {
  throw new Error("usage: node analyze-full-transaction-heavy-v1.mjs --output-root PATH --lane canonical-final|control-final|canonical-event");
}
const outputRoot = resolve(args[rootIndex + 1]);
const lane = args[laneIndex + 1];
if (!new Set(["canonical-final", "control-final", "canonical-event"]).has(lane)) throw new Error("invalid lane");
const repositoryRoot = resolve(import.meta.dirname, "../../../..");
const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const publicPath = (path) => path.startsWith(`${repositoryRoot}\\`) || path.startsWith(`${repositoryRoot}/`)
  ? relative(repositoryRoot, path).split(sep).join("/")
  : `external-scratch/${basename(outputRoot)}/${relative(outputRoot, path).split(sep).join("/")}`;
const bind = (path) => ({ path: publicPath(path), sha256: sha256(readFileSync(path)) });
const count = (value) => Array.isArray(value) ? value.length : value && typeof value === "object" ? Object.keys(value).length : 0;

const resultPath = resolve(outputRoot, "result.json");
const claimPath = resolve(outputRoot, "claim.k");
const logPath = resolve(outputRoot, "prove.log");
for (const path of [resultPath, claimPath, logPath]) if (!existsSync(path)) throw new Error(`missing heavy output: ${path}`);
const result = JSON.parse(readFileSync(resultPath, "utf8"));
if (result.obligationId !== "ACT-01" || result.lane !== lane || !result.proofExecuted || result.centralCredit) {
  throw new Error("heavy result identity/credit boundary mismatch");
}
const expectedStatus = lane === "control-final" ? "PASS_EXPECTED_SEMANTIC_CONTROL_FAILURE" : "PASS_CANONICAL_POSITIVE";
const expectedExit = lane === "control-final" ? 1 : 0;
if (result.status !== expectedStatus || result.actualExitCode !== expectedExit || result.timedOut || result.runtimeFailureMarkerPresent) {
  throw new Error(`heavy result contract failed: ${result.status}`);
}
if (sha256(readFileSync(claimPath)) !== result.executedClaimSha256) throw new Error("executed claim hash drift");
const sourceClaimPath = resolve(repositoryRoot, ...result.claimPath.split("/"));
if (sha256(readFileSync(sourceClaimPath)) !== result.claimSourceSha256) throw new Error("source claim hash drift");

const saveRoot = resolve(outputRoot, "save");
const proofRoots = readdirSync(saveRoot)
  .map((name) => resolve(saveRoot, name))
  .filter((path) => statSync(path).isDirectory() && existsSync(resolve(path, "proof.json")));
if (proofRoots.length !== 1) throw new Error(`expected one proof root, found ${proofRoots.length}`);
const proofRoot = proofRoots[0];
const proofPath = resolve(proofRoot, "proof.json");
const kcfgPath = resolve(proofRoot, "kcfg/kcfg.json");
const nodesRoot = resolve(proofRoot, "kcfg/nodes");
const proof = JSON.parse(readFileSync(proofPath, "utf8"));
const kcfg = JSON.parse(readFileSync(kcfgPath, "utf8"));
const logText = readFileSync(logPath, "utf8");
if (proof.admitted !== false || proof.id !== basename(proofRoot)) throw new Error("proof serialization identity/admission mismatch");
for (const token of ["Runtime error", "Proof crashed", "timed out", "SMT solver error", "BackendError"]) {
  if (logText.toLowerCase().includes(token.toLowerCase())) throw new Error(`forbidden backend marker: ${token}`);
}
const pending = proof.pending !== undefined
  ? count(proof.pending)
  : expectedExit === 0
    ? 0
    : Number.parseInt(logText.match(/\((\d+)\s+pending\s+and\s+\d+\s+failing\)/i)?.[1] ?? "-1", 10);
const graph = {
  nodes: count(kcfg.nodes),
  edges: count(kcfg.edges),
  covers: count(kcfg.covers),
  terminal: count(proof.terminal),
  stuck: count(kcfg.stuck),
  vacuous: count(kcfg.vacuous),
  pending,
  admitted: proof.admitted,
};
if (graph.nodes < 1 || graph.stuck !== 0 || graph.vacuous !== 0 || graph.pending < 0) throw new Error("invalid proof graph shape");
if (expectedExit === 0 && (graph.pending !== 0 || graph.terminal !== 0 || !logText.includes(`PROOF PASSED: ${proof.id}`))) {
  throw new Error("canonical proof did not close");
}
if (expectedExit === 1 && (graph.terminal < 1 || !logText.includes(`PROOF FAILED: ${proof.id}`))) {
  throw new Error("control proof lacks terminal semantic counterexample");
}

const terminalNodeIds = Array.isArray(proof.terminal) ? proof.terminal : Object.keys(proof.terminal ?? {});
const terminalNodePaths = terminalNodeIds.map((id) => resolve(nodesRoot, `${id}.json`));
for (const path of terminalNodePaths) if (!existsSync(path)) throw new Error(`terminal node missing: ${path}`);
const frozenTargetSlotHex = "0xa216b631070bf6f9317435cc754a1c420aa67da33584785a0fc287e179d88794";
const frozenTargetSlotDecimal = BigInt(frozenTargetSlotHex).toString();
const terminalCorpus = `${logText}\n${terminalNodePaths.map((path) => readFileSync(path, "utf8")).join("\n")}`;
if (lane === "control-final") {
  for (const token of ["Matching failed.", "ACCOUNTS_CELL", frozenTargetSlotDecimal]) {
    if (!terminalCorpus.includes(token)) throw new Error(`control terminal witness missing: ${token}`);
  }
}

const analysis = {
  schemaVersion: 1,
  status: "PASS",
  obligationId: "ACT-01",
  lane,
  claimId: proof.id,
  graph,
  result: bind(resultPath),
  proof: bind(proofPath),
  kcfg: bind(kcfgPath),
  log: bind(logPath),
  terminalWitness: lane === "control-final" ? {
    nodeIds: terminalNodeIds,
    nodes: terminalNodePaths.map(bind),
    frozenTargetSlotHex,
    frozenTargetSlotDecimal,
    expectedTarget: "1",
    actualControlTarget: "0",
  } : null,
  centralCredit: false,
};
const serialized = `${JSON.stringify(analysis, null, 2)}\n`;
if (reportIndex >= 0) {
  if (!args[reportIndex + 1]) throw new Error("--report requires a path");
  writeFileSync(resolve(args[reportIndex + 1]), serialized, "utf8");
}
process.stdout.write(serialized);
