#!/usr/bin/env node
// Deterministically freezes the exact ABI-04 closure node set and every
// policy topology edge with the actual parent and child digests. The manifest
// is generated before proof and is verification-only thereafter.
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const antiDir = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(antiDir, "../../../../..");
const policyPath = path.join(antiDir, "closure-policy.json");
const manifestPath = path.join(antiDir, "closure-manifest.json");
const selfPath = fileURLToPath(import.meta.url);
const mode = process.argv.includes("--write") ? "write" : process.argv.includes("--check") ? "check" : process.argv.includes("--plan") ? "plan" : null;
assert.ok(mode, "use exactly one of --write, --check, or --plan");
assert.equal(["--write", "--check", "--plan"].filter((flag) => process.argv.includes(flag)).length, 1);

const policy = JSON.parse(fs.readFileSync(policyPath, "utf8"));
assert.equal(policy.closureManifest.path, path.relative(repositoryRoot, manifestPath).split(path.sep).join("/"));
assert.equal(policy.closureManifest.generator, path.relative(repositoryRoot, selfPath).split(path.sep).join("/"));

const sha256 = (value) => crypto.createHash("sha256").update(value).digest("hex");
const fileSha256 = (value) => sha256(fs.readFileSync(value));
const relative = (value) => path.relative(repositoryRoot, value).split(path.sep).join("/");
const absolute = (value) => path.join(repositoryRoot, ...value.split("/"));
const stable = (value) => {
  if (Array.isArray(value)) return `[${value.map(stable).join(",")}]`;
  if (value && typeof value === "object") return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stable(value[key])}`).join(",")}}`;
  return JSON.stringify(value);
};
const render = (value) => `${JSON.stringify(value, null, 2)}\n`;
const allowed = new Set(policy.allowedFileExtensions);
const excluded = (value) => policy.excludedPrefixes.some((prefix) => value.startsWith(prefix));

function walk(directory) {
  if (!fs.existsSync(directory)) return [];
  const result = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0)) {
    const target = path.join(directory, entry.name);
    assert.equal(entry.isSymbolicLink(), false, `closure scope contains symlink: ${target}`);
    if (entry.isDirectory()) result.push(...walk(target));
    else if (entry.isFile()) result.push(target);
    else assert.fail(`unsupported closure scope entry: ${target}`);
  }
  return result;
}

const discovered = [];
for (const scopeRoot of policy.scopeRoots) {
  for (const filePath of walk(absolute(scopeRoot))) {
    const repositoryPath = relative(filePath);
    if (excluded(repositoryPath) || filePath === manifestPath) continue;
    const extension = path.extname(filePath);
    assert.ok(allowed.has(extension) || path.basename(filePath) === "ROOT", `unexpected scoped file type: ${repositoryPath}`);
    discovered.push(repositoryPath);
  }
}
discovered.sort();
assert.equal(new Set(discovered).size, discovered.length, "duplicate discovered closure path");

const nodeRecords = discovered.map((repositoryPath) => ({ path: repositoryPath, sha256: fileSha256(absolute(repositoryPath)) }));
const nodeByPath = new Map(nodeRecords.map((item) => [item.path, item]));
const topologyEdges = [];
for (const required of policy.requiredNodes) {
  if (required.path === relative(manifestPath)) {
    assert.deepEqual(required.dependsOn, [], "closure manifest cannot depend on itself");
    continue;
  }
  assert.ok(nodeByPath.has(required.path), `required child is outside exact node set: ${required.path}`);
  for (const parentPath of required.dependsOn) {
    assert.ok(nodeByPath.has(parentPath), `required parent is outside exact node set: ${parentPath}`);
    topologyEdges.push({
      parent: nodeByPath.get(parentPath),
      child: nodeByPath.get(required.path),
      relation: "declared-policy-dependency",
      declarationId: `${required.id}::${parentPath}`,
    });
  }
}
topologyEdges.sort((left, right) => left.declarationId < right.declarationId ? -1 : left.declarationId > right.declarationId ? 1 : 0);
assert.equal(new Set(topologyEdges.map((item) => item.declarationId)).size, topologyEdges.length, "duplicate policy topology edge");

const manifest = {
  schemaVersion: 2,
  kind: "ABI04_FROZEN_EXACT_CLOSURE_MANIFEST",
  obligationId: "ABI-04",
  status: "FROZEN_PRE_PROOF_CREDIT_0",
  generatedBy: { path: relative(selfPath), sha256: fileSha256(selfPath) },
  policy: { path: relative(policyPath), sha256: fileSha256(policyPath) },
  selfPath: relative(manifestPath),
  scopeRoots: policy.scopeRoots,
  excludedPrefixes: policy.excludedPrefixes,
  allowedFileExtensions: policy.allowedFileExtensions,
  exactNodeCount: nodeRecords.length + 1,
  nodeRecords,
  nodeSetSha256: sha256(stable(nodeRecords)),
  exactTopologyEdgeCount: topologyEdges.length,
  topologyEdges,
  topologyEdgeSetSha256: sha256(stable(topologyEdges)),
  proofExecuted: false,
  proofCredit: false,
  centralCredit: false,
};
const expected = render(manifest);
const actual = fs.existsSync(manifestPath) ? fs.readFileSync(manifestPath, "utf8").replaceAll("\r\n", "\n") : null;
const change = actual === expected ? "UNCHANGED" : actual === null ? "MISSING" : "CHANGED";
if (mode === "write") fs.writeFileSync(manifestPath, expected, "utf8");
else if (mode === "check") assert.equal(change, "UNCHANGED", "frozen closure manifest is stale; regenerate before proof, never during proof");

console.log(JSON.stringify({
  status: mode === "write" ? "FROZEN_EXACT_CLOSURE_MANIFEST_CREDIT_0" : mode === "check" ? "PASS_FROZEN_EXACT_CLOSURE_MANIFEST" : "PASS_CLOSURE_MANIFEST_PLAN",
  mode,
  change,
  path: relative(manifestPath),
  actualSha256: actual === null ? null : sha256(Buffer.from(actual)),
  expectedSha256: sha256(Buffer.from(expected)),
  exactNodeCount: manifest.exactNodeCount,
  exactTopologyEdgeCount: manifest.exactTopologyEdgeCount,
  nodeSetSha256: manifest.nodeSetSha256,
  topologyEdgeSetSha256: manifest.topologyEdgeSetSha256,
  proofExecuted: false,
  proofCredit: false,
  centralCredit: false,
}, null, 2));
