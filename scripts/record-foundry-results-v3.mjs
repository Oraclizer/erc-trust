// SPDX-License-Identifier: BSD-3-Clause
//
// Record the continuous-integration Foundry run of one commit as
// evidence/foundry-results-v3.json.
//
// The Foundry job runs in continuous integration; this script binds its recorded
// outcome to the exact source root of the current tree, refuses to write when the
// named commit does not produce that source root, and measures the runtime
// templates from the compiled artifacts so the receipt can only bind the runtime
// the generated bridge names.
//
// Usage:
//   node scripts/record-foundry-results-v3.mjs --run <run-summary.json> --commit <sha>          check only
//   node scripts/record-foundry-results-v3.mjs --run <run-summary.json> --commit <sha> --write  write the receipt
//
// The run summary is written by the operator from the job log:
//   { "workflow": { "runId", "jobId", "url", "jobConclusion" },
//     "toolchain": { "foundry", "solidity", "evmVersion" },
//     "checks": { "format", "buildAndSize", "tests": { passed, failed, skipped, suites,
//                 fuzzProperties, fuzzRunsEach, invariants, invariantRunsEach, invariantDepth,
//                 invariantCalls, invariantReverts }, "lintErrors", "intentionalTimestampWarnings" } }

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const argValue = (name) => { const index = args.indexOf(name); return index === -1 ? null : args[index + 1] ?? null; };
const writeMode = args.includes("--write");
const runPath = argValue("--run");
const commit = argValue("--commit");
if (!runPath || !commit) {
  console.error("usage: node scripts/record-foundry-results-v3.mjs --run <run-summary.json> --commit <sha> [--write]");
  process.exit(2);
}

const EIP170_LIMIT = 24576;
const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const bytes = (path) => readFileSync(resolve(root, path));
const stable = (value) => {
  if (Array.isArray(value)) return value.map(stable);
  if (value !== null && typeof value === "object") return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stable(value[key])]));
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
function sourceRootOfCommit(sha) {
  const listing = execFileSync("git", ["ls-tree", "-r", "-z", sha, "--", "implementation/src", "implementation/test", "foundry.toml"], { cwd: root, encoding: "utf8" });
  const entries = listing.split("\0").filter(Boolean).map((line) => { const [meta, path] = line.split("\t"); return { blob: meta.split(" ")[2], path }; });
  entries.sort((left, right) => (left.path < right.path ? -1 : left.path > right.path ? 1 : 0));
  const material = entries.map((entry) => `${sha256(execFileSync("git", ["cat-file", "blob", entry.blob], { cwd: root, maxBuffer: 64 * 1024 * 1024 }))}  ${entry.path}\n`).join("");
  return sha256(Buffer.from(material, "utf8"));
}
function runtimeOf(artifactPath) {
  check(existsSync(resolve(root, artifactPath)), `forge artifact missing: ${artifactPath}; run forge build first`);
  if (!existsSync(resolve(root, artifactPath))) return null;
  const artifact = JSON.parse(bytes(artifactPath).toString("utf8"));
  const hex = artifact.deployedBytecode.object.replace(/^0x/, "");
  const length = hex.length / 2;
  return { bytes: length, eip170MarginBytes: EIP170_LIMIT - length, sha256: sha256(Buffer.from(hex, "hex")) };
}

const run = JSON.parse(readFileSync(resolve(process.cwd(), runPath), "utf8"));
const mode = JSON.parse(bytes("evidence/evidence-mode.json").toString("utf8"));
const sourceRootSha256 = rootOf([...walk("implementation/src"), ...walk("implementation/test"), "foundry.toml"]);
check(/^[0-9a-f]{40}$/.test(commit), "commit must be a full sha");
check(sourceRootOfCommit(commit) === sourceRootSha256, "the named commit does not produce the current source root");

const runtimeTemplate = runtimeOf("out/TrustToken.sol/TrustToken.json");
const erc3643Adapter = runtimeOf("out/ERC3643TrustAdapter.sol/ERC3643TrustAdapter.json");
const profileGovernor = runtimeOf("out/ProfileGovernor.sol/ProfileGovernor.json");
const bridge = JSON.parse(bytes("evidence/end-to-end-refinement/runtime-bridge-v2/schema.json").toString("utf8"));
check(runtimeTemplate?.sha256 === bridge.subjects.native.runtime.sha256, "native runtime differs from the generated bridge");
check(erc3643Adapter?.sha256 === bridge.subjects.profileAdapter.runtime.sha256, "adapter runtime differs from the generated bridge");
check(profileGovernor?.sha256 === bridge.subjects.profileGovernor.runtime.sha256, "governor runtime differs from the generated bridge");

const checks = run.checks;
check(checks?.tests?.failed === 0 && checks?.lintErrors === 0 && checks?.format === "PASS" && checks?.buildAndSize === "PASS", "run summary does not describe a passing job");
check(run.workflow?.jobConclusion === "success" && Number.isInteger(run.workflow?.runId) && Number.isInteger(run.workflow?.jobId), "workflow identity incomplete");

const receipt = {
  schema: "erc-trust-foundry-results-v3",
  candidate: mode.candidate,
  status: "PASS",
  sourceCommit: commit,
  sourceRootAlgorithm: "sha256-raw-files-case-sensitive-path-order-v1",
  sourceRootSha256,
  workflow: run.workflow,
  toolchain: run.toolchain,
  checks,
  runtimeTemplate,
  profileRuntimes: { erc3643Adapter, profileGovernor },
  claimBoundary: "Pinned Foundry build, format, unit, fuzz, invariant, size, and lint results for the named commit and source root. The three runtime hashes are measured from the compiled artifacts and equal the generated runtime bridge; the deterministic-build receipt binds the native template and the release manifest binds all three. This is not an audit, deployment result, or production-safety claim.",
};

if (failures.length) { for (const failure of failures) console.error(failure); process.exit(1); }
const rendered = `${JSON.stringify(stable(receipt), null, 2)}\n`;
if (writeMode) writeFileSync(resolve(root, "evidence/foundry-results-v3.json"), rendered, "utf8");
console.log(JSON.stringify({ status: "PASS", sourceCommit: commit, sourceRootSha256, runtime: runtimeTemplate.sha256, written: writeMode }, null, 2));
