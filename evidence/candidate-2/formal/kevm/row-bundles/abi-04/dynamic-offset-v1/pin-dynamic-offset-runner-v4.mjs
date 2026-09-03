#!/usr/bin/env node
// Deterministically pins every repository-local v4 runner input that is not
// already protected by the external full-closure receipt. No proof is run.
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const familyDir = path.dirname(fileURLToPath(import.meta.url));
const rowDir = path.dirname(familyDir);
const repositoryRoot = path.resolve(rowDir, "../../../..");
const runnerPath = path.join(familyDir, "run-dynamic-offset-leaf-v4.sh");
const indexPath = path.join(familyDir, "claims-index-v1.json");
const mode = process.argv.includes("--write") ? "write" : process.argv.includes("--check") ? "check" : process.argv.includes("--plan") ? "plan" : null;
assert.ok(mode, "use exactly one of --write, --check, or --plan");
assert.equal(["--write", "--check", "--plan"].filter((value) => process.argv.includes(value)).length, 1);
const sha256 = (value) => crypto.createHash("sha256").update(value).digest("hex");
const fileSha256 = (value) => sha256(fs.readFileSync(value));
const index = JSON.parse(fs.readFileSync(indexPath, "utf8"));
let expected = fs.readFileSync(runnerPath, "utf8").replaceAll("\r\n", "\n");

function replaceOne(pattern, replacement, label) {
  const globalPattern = new RegExp(pattern.source, pattern.flags.includes("g") ? pattern.flags : `${pattern.flags}g`);
  const matches = [...expected.matchAll(globalPattern)];
  assert.equal(matches.length, 1, `${label}: expected one match, found ${matches.length}`);
  expected = expected.replace(pattern, replacement);
}

for (const claim of index.claims) {
  const claimPath = path.join(repositoryRoot, ...claim.claim.path.split("/"));
  const source = fs.readFileSync(claimPath);
  const stripped = Buffer.from(source.toString("utf8").replaceAll("\r\n", "\n").split("\n").slice(1).join("\n"));
  const sourceHash = sha256(source);
  const strippedHash = sha256(stripped);
  const escapedFile = claim.claim.path.split("/").at(-1).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const blockPattern = new RegExp(`(claim_file=${escapedFile}\\n\\s*spec_module=[^\\n]+\\n\\s*expected_source_sha256=)[0-9a-f]{64}(\\n\\s*expected_stripped_sha256=)[0-9a-f]{64}`);
  replaceOne(blockPattern, `$1${sourceHash}$2${strippedHash}`, `${claim.claimId}: source pins`);
}

const graphDir = path.join(familyDir, "expected-graphs");
for (const graphName of fs.readdirSync(graphDir).filter((value) => value.endsWith(".json")).sort()) {
  const graphPath = path.join(graphDir, graphName);
  const graph = JSON.parse(fs.readFileSync(graphPath, "utf8"));
  assert.ok(index.claims.some((claim) => claim.claimId === graph.claimId), `${graphName}: indexed claim`);
  assert.ok(["canonical-positive", "mutant-negative"].includes(graph.side), `${graphName}: exact side`);
  const escapedName = graphName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const pattern = new RegExp(`(expected_graph=\"\\$expected_graph_directory/${escapedName}\"\\n\\s*expected_graph_sha256=)[0-9a-f]{64}`);
  replaceOne(pattern, `$1${fileSha256(graphPath)}`, `${graphName}: graph pin`);
}
assert.equal(fs.readdirSync(graphDir).filter((value) => value.endsWith(".json")).length, 12);

const localPins = [
  ["case_matrix", path.join(rowDir, "case-matrix.json")],
  ["claims_index", indexPath],
  ["family_contract", path.join(familyDir, "dynamic-offset-family-v1-contract.json")],
  ["executable_mutant_contract", path.join(familyDir, "executable-mutant-contract-v1.json")],
  ["leaf_control", path.join(familyDir, "dynamic-offset-leaf-mutant-control-v2.mjs")],
  ["analysis_tool", path.join(familyDir, "analyze-dynamic-offset-replay-v1.mjs")],
  ["independent_verifier", path.join(familyDir, "verify-dynamic-offset-replay-v1.py")],
  ["closure_freeze_verifier", path.join(rowDir, "anti-drift", "verify-freeze-receipt.py")],
  ["dependency_lock", path.join(repositoryRoot, "formal", "kevm", "dependencies.lock.json")],
  ["mutation_manifest", path.join(rowDir, "mutation", "mutation-manifest.json")],
  ["mutant_bridge", path.join(rowDir, "generated", "mutant-runtime-bridge.k")],
  ["mutant_verification", path.join(rowDir, "generated", "mutant-runtime-verification.k")],
];
for (const [variable, target] of localPins) {
  assert.ok(fs.existsSync(target), `${variable}: missing pin target`);
  const pattern = new RegExp(`(require_hash \"\\$${variable}\" )[0-9a-f]{64}`);
  replaceOne(pattern, `$1${fileSha256(target)}`, `${variable}: local input pin`);
}

const executionManifestPins = [
  ["analysisToolSha256", path.join(familyDir, "analyze-dynamic-offset-replay-v1.mjs")],
  ["independentVerifierSha256", path.join(familyDir, "verify-dynamic-offset-replay-v1.py")],
];
for (const [field, target] of executionManifestPins) {
  const pattern = new RegExp(`("${field}": ")[0-9a-f]{64}(")`);
  replaceOne(pattern, `$1${fileSha256(target)}$2`, `${field}: execution manifest pin`);
}

const actual = fs.readFileSync(runnerPath, "utf8").replaceAll("\r\n", "\n");
const status = actual === expected ? "UNCHANGED" : "CHANGED";
if (mode === "write") fs.writeFileSync(runnerPath, expected, "utf8");
else if (mode === "check") assert.equal(actual, expected, "v4 runner repository-local pins are stale");
console.log(JSON.stringify({
  status: mode === "write" ? "PINNED_STATIC_ONLY" : mode === "check" ? "PASS_STATIC_PINS" : "PASS_PIN_PLAN",
  mode,
  change: status,
  claimPins: index.claims.length,
  expectedGraphPins: 12,
  repositoryLocalPins: localPins.length,
  executionManifestPins: executionManifestPins.length,
  actualSha256: sha256(Buffer.from(actual)),
  expectedSha256: sha256(Buffer.from(expected)),
  proofCredit: false,
  centralCredit: false,
}, null, 2));
