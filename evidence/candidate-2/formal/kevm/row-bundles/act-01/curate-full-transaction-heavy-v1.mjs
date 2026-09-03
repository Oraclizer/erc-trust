import { createHash } from "node:crypto";
import { copyFileSync, existsSync, mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { basename, relative, resolve, sep } from "node:path";

const args = process.argv.slice(2);
const rootIndex = args.indexOf("--output-root");
const laneIndex = args.indexOf("--lane");
if (rootIndex < 0 || laneIndex < 0 || !args[rootIndex + 1] || !args[laneIndex + 1]) {
  throw new Error("usage: node curate-full-transaction-heavy-v1.mjs --output-root PATH --lane canonical-final|control-final|canonical-event");
}
const outputRoot = resolve(args[rootIndex + 1]);
const lane = args[laneIndex + 1];
if (!new Set(["canonical-final", "control-final", "canonical-event"]).has(lane)) throw new Error("invalid lane");
const repositoryRoot = resolve(import.meta.dirname, "../../../..");
const destinationRoot = resolve(repositoryRoot, `evidence/end-to-end-refinement/row-bundles/act-01/artifacts/${lane}`);
if (existsSync(destinationRoot)) throw new Error(`curated destination already exists: ${destinationRoot}`);
const analysisPath = resolve(outputRoot, "analysis.json");
if (!existsSync(analysisPath)) throw new Error("external analysis.json is missing");
const analysis = JSON.parse(readFileSync(analysisPath, "utf8"));
if (analysis.status !== "PASS" || analysis.obligationId !== "ACT-01" || analysis.lane !== lane || analysis.centralCredit) {
  throw new Error("analysis identity/credit boundary mismatch");
}

const saveRoot = resolve(outputRoot, "save");
const proofRoots = readdirSync(saveRoot)
  .map((name) => resolve(saveRoot, name))
  .filter((path) => statSync(path).isDirectory() && existsSync(resolve(path, "proof.json")));
if (proofRoots.length !== 1) throw new Error("expected exactly one proof root");
const proofRoot = proofRoots[0];
const sha256 = (path) => createHash("sha256").update(readFileSync(path)).digest("hex");
const repo = (path) => relative(repositoryRoot, path).split(sep).join("/");
const copy = (source, name) => {
  const destination = resolve(destinationRoot, name);
  copyFileSync(source, destination);
  return { path: repo(destination), sha256: sha256(destination) };
};
mkdirSync(destinationRoot, { recursive: true });
const curated = {
  ...analysis,
  result: copy(resolve(outputRoot, "result.json"), "result.json"),
  executedClaim: copy(resolve(outputRoot, "claim.k"), "claim.k"),
  proof: copy(resolve(proofRoot, "proof.json"), "proof.json"),
  kcfg: copy(resolve(proofRoot, "kcfg/kcfg.json"), "kcfg.json"),
  log: copy(resolve(outputRoot, "prove.log"), "prove.log"),
  timing: copy(resolve(outputRoot, "time.txt"), "time.txt"),
  exitCode: copy(resolve(outputRoot, "exit-code.txt"), "exit-code.txt"),
  externalOutputRootRef: `external-scratch/${basename(outputRoot)}`,
  curatedAtUtc: new Date().toISOString(),
};
if (analysis.terminalWitness) {
  curated.terminalWitness = {
    ...analysis.terminalWitness,
    nodes: analysis.terminalWitness.nodeIds.map((id) => copy(resolve(proofRoot, `kcfg/nodes/${id}.json`), `terminal-node-${id}.json`)),
  };
}
const curatedPath = resolve(destinationRoot, "analysis.json");
writeFileSync(curatedPath, `${JSON.stringify(curated, null, 2)}\n`, "utf8");
process.stdout.write(`${JSON.stringify({
  status: "PASS",
  obligationId: "ACT-01",
  lane,
  analysis: { path: repo(curatedPath), sha256: sha256(curatedPath) },
  graph: curated.graph,
  centralCredit: false,
}, null, 2)}\n`);
