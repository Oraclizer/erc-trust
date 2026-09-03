// SPDX-License-Identifier: BSD-3-Clause
//
// Record the Kontrol proof run of the successor native runtime as
// evidence/kontrol-results-v3.json.
//
// The run itself is executed outside this script (kontrol build, then kontrol
// prove per test, on an isolated copy of the committed sources). This script
// binds the recorded outcome to the exact inputs of the current tree: it hashes
// implementation/src/TrustToken.sol and every file under implementation/kontrol,
// refuses to write when those hashes differ from the hashes observed at run
// time, computes the inputs root with the same algorithm as
// scripts/verify-current-profile-release-v3.mjs, and binds the runtime template
// of the compiled artifact to the generated runtime bridge.
//
// Usage:
//   node scripts/record-kontrol-results-v3.mjs --run <run-summary.json>          check only
//   node scripts/record-kontrol-results-v3.mjs --run <run-summary.json> --write  write the receipt
//
// The run summary is a small JSON file written by the operator of the run:
//   {
//     "startedAt", "finishedAt", "host",
//     "toolchain": { "kontrol", "kevm", "forge", "solidity", "schedule" },
//     "buildSeconds",
//     "observedInputs": [{ "path", "sha256" }],
//     "proofs": [{ "test", "status", "executionSeconds", "nodes", "lemmas", "reinitialized" }]
//   }

import { createHash } from "node:crypto";
import { existsSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const writeMode = args.includes("--write");
const runIndex = args.indexOf("--run");
if (runIndex === -1 || !args[runIndex + 1]) {
  console.error("usage: node scripts/record-kontrol-results-v3.mjs --run <run-summary.json> [--write]");
  process.exit(2);
}

const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const bytes = (path) => readFileSync(resolve(root, path));
const json = (path) => JSON.parse(readFileSync(path, "utf8"));
const stable = (value) => {
  if (Array.isArray(value)) return value.map(stable);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stable(value[key])]));
  }
  return value;
};
const failures = [];
const check = (condition, message) => { if (!condition) failures.push(message); };

function walk(path) {
  if (!existsSync(resolve(root, path))) return [];
  return readdirSync(resolve(root, path), { withFileTypes: true }).flatMap((entry) => {
    const child = `${path}/${entry.name}`;
    return entry.isDirectory() ? walk(child) : [child];
  });
}
function rootOf(paths) {
  const sorted = [...paths].sort((left, right) => (left < right ? -1 : left > right ? 1 : 0));
  return sha256(Buffer.from(sorted.map((path) => `${sha256(bytes(path))}  ${path}\n`).join(""), "utf8"));
}

const run = json(resolve(process.cwd(), args[runIndex + 1]));
const mode = JSON.parse(bytes("evidence/evidence-mode.json").toString("utf8"));
const candidate = mode.candidate;

// Inputs of the run, hashed from the current tree and compared with the observed hashes.
const inputPaths = ["implementation/src/TrustToken.sol", ...walk("implementation/kontrol")].sort();
const sourceInputs = inputPaths.map((path) => ({ path, sha256: sha256(bytes(path)) }));
const observedInputs = [...(run.observedInputs ?? [])].sort((left, right) => (left.path < right.path ? -1 : left.path > right.path ? 1 : 0));
check(JSON.stringify(observedInputs.map((entry) => entry.path)) === JSON.stringify(sourceInputs.map((entry) => entry.path)),
  "run summary does not observe exactly the current Kontrol input set (the token source and every file under implementation/kontrol)");
for (const observed of observedInputs) {
  const current = sourceInputs.find((entry) => entry.path === observed.path);
  if (current) check(current.sha256 === observed.sha256, `input changed since the run: ${observed.path}`);
}
const inputsRootSha256 = rootOf(walk("implementation/kontrol"));

// Runtime template of the compiled artifact, bound to the generated bridge.
const artifactPath = "out/TrustToken.sol/TrustToken.json";
check(existsSync(resolve(root, artifactPath)), "forge artifact missing: run forge build first");
const artifact = existsSync(resolve(root, artifactPath)) ? JSON.parse(bytes(artifactPath).toString("utf8")) : null;
const runtimeHex = artifact?.deployedBytecode?.object?.replace(/^0x/, "") ?? "";
const runtimeSha256 = sha256(Buffer.from(runtimeHex, "hex"));
const runtimeBytes = runtimeHex.length / 2;
const bridgeSchemaPath = "evidence/end-to-end-refinement/runtime-bridge-v2/schema.json";
const bridge = JSON.parse(bytes(bridgeSchemaPath).toString("utf8"));
check(bridge.subjects.native.runtime.sha256 === runtimeSha256, "compiled runtime differs from the generated bridge; regenerate the bridge");

// Proof outcomes.
const expectedTests = [...bytes("implementation/kontrol/TrustTokenKontrolTest.t.sol").toString("utf8").matchAll(/function\s+(testKontrol_[A-Za-z0-9_]+)\s*\(/g)].map((match) => match[1]);
const proofs = (run.proofs ?? []).map((proof) => ({
  id: `implementation%kontrol%TrustTokenKontrolTest.${proof.test}():0`,
  test: proof.test,
  status: proof.status === "PASSED" || proof.status === "PASS" ? "PASS" : "FAIL",
  executionSeconds: proof.executionSeconds,
  nodes: proof.nodes ?? null,
  lemmas: proof.lemmas ?? null,
  reinitialized: Boolean(proof.reinitialized),
}));
for (const test of expectedTests) check(proofs.some((proof) => proof.test === test), `no proof outcome recorded for ${test}`);
for (const proof of proofs) check(expectedTests.includes(proof.test), `proof outcome for a test that is not in the Kontrol test file: ${proof.test}`);
const summary = { total: proofs.length, passed: proofs.filter((proof) => proof.status === "PASS").length, failed: proofs.filter((proof) => proof.status !== "PASS").length };
check(summary.failed === 0 && summary.total === expectedTests.length, "not every Kontrol proof passed");

const receipt = {
  schema: "erc-trust-kontrol-results-v3",
  candidate,
  status: summary.failed === 0 ? "PASS" : "FAIL",
  sourceInputs,
  inputsRootSha256,
  toolchain: { ...run.toolchain, foundryProfile: "kontrol" },
  runtimeBinding: {
    kind: "FOUNDRY_ARTIFACT_RUNTIME_TEMPLATE",
    runtimeBytes,
    runtimeSha256,
    bridge: { path: bridgeSchemaPath, sha256: sha256(bytes(bridgeSchemaPath)) },
    note: "Kontrol rebuilt the exact source under the pinned compiler with the kontrol Foundry profile. The template hash identifies the default-profile Foundry artifact that the generated bridge names; the proofs run on the kontrol-profile build of the same source. No claim that the proof graph itself was keyed by the template hash.",
  },
  build: { command: "kontrol build --foundry-project-root . --regen --rekompile", seconds: run.buildSeconds ?? null },
  proofs,
  summary,
  run: { startedAt: run.startedAt ?? null, finishedAt: run.finishedAt ?? null, host: run.host ?? null, replay: "node scripts/record-kontrol-results-v3.mjs --run <run-summary.json>" },
  claimBoundary: "Four bounded symbolic proofs on the successor native runtime: raw sensitive selectors stay closed, an operational dependency failure and a non-increasing FREEZE stutter the projection, and LIQUIDATE moves the exact delta with the receipt as the final log. They are bounded instances of the undischarged runtime link of the abstract model, not a proof of it, and they cover the native token only. Not an audit, deployment result, or production-safety claim.",
};

if (failures.length) {
  for (const failure of failures) console.error(failure);
  process.exit(1);
}
const rendered = `${JSON.stringify(stable(receipt), null, 2)}\n`;
if (writeMode) writeFileSync(resolve(root, "evidence/kontrol-results-v3.json"), rendered, "utf8");
console.log(JSON.stringify({ status: receipt.status, proofs: summary, runtimeSha256, inputsRootSha256, written: writeMode }, null, 2));
