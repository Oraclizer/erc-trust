// SPDX-License-Identifier: BSD-3-Clause
//
// Record the continuous-integration Isabelle run (workflow Proofs) of one commit as
// evidence/isabelle-results-v3.json.
//
// The clean build and proof audit run in continuous integration; this script binds
// the recorded outcome to the exact formal source root of the current tree with the
// same algorithm as scripts/verify-current-profile-release-v3.mjs, and refuses to
// write when the named commit does not carry the same theory files.
//
// Usage:
//   node scripts/record-isabelle-results-v3.mjs --run <run-summary.json> --commit <sha>          check only
//   node scripts/record-isabelle-results-v3.mjs --run <run-summary.json> --commit <sha> --write  write the receipt
//
// The run summary is written by the operator from the job log:
//   { "workflow": { "runId", "jobId", "url", "jobConclusion" },
//     "checks": { "cleanBuild", "proofExport", "bannedSourceForms", "oracleDependencyCount",
//                 "explicitRootCount", "qualifiedFactCount" } }

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
  console.error("usage: node scripts/record-isabelle-results-v3.mjs --run <run-summary.json> --commit <sha> [--write]");
  process.exit(2);
}

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
const theoryDir = "formal/isabelle/ERC_TRUST";
const theoryPaths = walk(theoryDir).filter((path) => path.endsWith(".thy")).sort((left, right) => (left < right ? -1 : left > right ? 1 : 0));
const rootSha256 = sha256(Buffer.from(theoryPaths.map((path) => `${sha256(bytes(path))}  ${path}\n`).join(""), "utf8"));

function formalRootOfCommit(sha) {
  const listing = execFileSync("git", ["ls-tree", "-r", "-z", sha, "--", theoryDir], { cwd: root, encoding: "utf8" });
  const entries = listing.split("\0").filter(Boolean).map((line) => { const [meta, path] = line.split("\t"); return { blob: meta.split(" ")[2], path }; })
    .filter((entry) => entry.path.endsWith(".thy"));
  entries.sort((left, right) => (left.path < right.path ? -1 : left.path > right.path ? 1 : 0));
  const material = entries.map((entry) => `${sha256(execFileSync("git", ["cat-file", "blob", entry.blob], { cwd: root, maxBuffer: 64 * 1024 * 1024 }))}  ${entry.path}\n`).join("");
  return { theoryFiles: entries.length, rootSha256: sha256(Buffer.from(material, "utf8")) };
}

const run = JSON.parse(readFileSync(resolve(process.cwd(), runPath), "utf8"));
const mode = JSON.parse(bytes("evidence/evidence-mode.json").toString("utf8"));
check(/^[0-9a-f]{40}$/.test(commit), "commit must be a full sha");
const atCommit = formalRootOfCommit(commit);
check(atCommit.theoryFiles === theoryPaths.length && atCommit.rootSha256 === rootSha256, "the named commit does not carry the current formal source root");
const foundationLine = bytes(".github/workflows/proofs.yml").toString("utf8").match(/FORMAL_FOUNDATION_COMMIT:\s*([0-9a-f]{40})/);
check(foundationLine !== null, "foundation commit not found in the Proofs workflow");
const checks = run.checks;
check(checks?.cleanBuild === "PASS" && checks?.proofExport === "PASS" && checks?.bannedSourceForms === 0 && checks?.oracleDependencyCount === 0, "run summary does not describe a passing proof job");
check(run.workflow?.jobConclusion === "success" && Number.isInteger(run.workflow?.runId) && Number.isInteger(run.workflow?.jobId), "workflow identity incomplete");

const receipt = {
  schema: "erc-trust-isabelle-results-v3",
  candidate: mode.candidate,
  status: "PASS",
  sourceCommit: commit,
  workflow: run.workflow,
  toolchain: { isabelle: "Isabelle2025-2", session: "ERC_TRUST", foundationCommit: foundationLine ? foundationLine[1] : null },
  formalSource: { path: theoryDir, theoryFiles: theoryPaths.length, rootSha256, algorithm: "sha256-raw-files-lexicographic-path-order-v1" },
  checks,
  claimBoundary: "Kernel-checked clean build and proof audit of the exact formal source tree at the named commit. The formal source models kernel version 2 and is connected to the successor endpoints by the generated runtime bridge and the obligation ledger; the runtime link of the composition locale is not discharged. This does not establish compiler correctness or a complete Isabelle-to-EVM refinement theorem.",
};

if (failures.length) { for (const failure of failures) console.error(failure); process.exit(1); }
const rendered = `${JSON.stringify(stable(receipt), null, 2)}\n`;
if (writeMode) writeFileSync(resolve(root, "evidence/isabelle-results-v3.json"), rendered, "utf8");
console.log(JSON.stringify({ status: "PASS", sourceCommit: commit, theoryFiles: theoryPaths.length, rootSha256, written: writeMode }, null, 2));
