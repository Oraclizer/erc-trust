#!/usr/bin/env node
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const antiDir = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(antiDir, "../../../../..");
const policyPath = path.join(antiDir, "closure-policy.json");
const policy = JSON.parse(fs.readFileSync(policyPath, "utf8"));
const topologyAdjacency = new Map();
for (const node of policy.requiredNodes) {
  if (!topologyAdjacency.has(node.path)) topologyAdjacency.set(node.path, new Set());
  for (const dependency of node.dependsOn) {
    if (!topologyAdjacency.has(dependency)) topologyAdjacency.set(dependency, new Set());
    topologyAdjacency.get(dependency).add(node.path);
  }
}
const topologyState = new Map();
const visitTopology = (node, stack = []) => {
  const state = topologyState.get(node) ?? 0;
  assert.notEqual(state, 1, `closure policy dependency cycle: ${[...stack, node].join(" -> ")}`);
  if (state === 2) return;
  topologyState.set(node, 1);
  for (const child of topologyAdjacency.get(node) ?? []) visitTopology(child, [...stack, node]);
  topologyState.set(node, 2);
};
for (const node of topologyAdjacency.keys()) visitTopology(node);
const manifestPath = path.join(repositoryRoot, ...policy.closureManifest.path.split("/"));
const outIndex = process.argv.indexOf("--out");
const outDir = outIndex >= 0 ? path.resolve(process.argv[outIndex + 1]) : null;
const fullOutput = process.argv.includes("--full");

const posix = (value) => path.relative(repositoryRoot, value).split(path.sep).join("/");
const absolute = (value) => path.join(repositoryRoot, ...value.split("/"));
const sha256 = (value) => crypto.createHash("sha256").update(value).digest("hex");
const fileSha256 = (value) => sha256(fs.readFileSync(value));
const isSha256 = (value) => typeof value === "string" && /^[0-9a-f]{64}$/i.test(value);
const stable = (value) => {
  if (Array.isArray(value)) return `[${value.map(stable).join(",")}]`;
  if (value && typeof value === "object") return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stable(value[key])}`).join(",")}}`;
  return JSON.stringify(value);
};
const compareCodePoints = (left, right) => left < right ? -1 : left > right ? 1 : 0;
const writeJson = (filePath, value) => {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
};

function walk(directory) {
  if (!fs.existsSync(directory)) return [];
  const result = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    const current = path.join(directory, entry.name);
    if (entry.isDirectory()) result.push(...walk(current));
    else if (entry.isFile()) result.push(current);
  }
  return result;
}

function category(relativePath) {
  const required = policy.requiredNodes.find((item) => item.path === relativePath);
  if (required) return required.category;
  if (relativePath.includes("/expected-graphs/")) return "expected-graph";
  if (relativePath.includes("/authoritative-pairs/")) return "authoritative-binder";
  if (relativePath.includes("/claims/") || relativePath.includes("/symbolic-claims")) return "claim-source";
  if (relativePath.includes("/isabelle/") || relativePath.endsWith("/ROOT")) return "isabelle-input";
  if (relativePath.endsWith(".mjs") || relativePath.endsWith(".py") || relativePath.endsWith(".sh")) return "tool-source";
  if (relativePath.startsWith("evidence/")) return "evidence";
  return "product-source";
}

const allowedExtensions = new Set(policy.allowedFileExtensions);
const excluded = (relativePath) => policy.excludedPrefixes.some((prefix) => relativePath.startsWith(prefix));
const discovered = [];
const unexpected = [];
for (const scopeRoot of policy.scopeRoots) {
  for (const filePath of walk(absolute(scopeRoot))) {
    const relativePath = posix(filePath);
    if (excluded(relativePath)) continue;
    const extension = path.extname(filePath);
    if (!allowedExtensions.has(extension) && path.basename(filePath) !== "ROOT") {
      unexpected.push({ kind: "UNEXPECTED_FILE_TYPE", path: relativePath });
      continue;
    }
    discovered.push(relativePath);
  }
}

let manifest = null;
const missing = [];
const duplicate = [];
const mismatches = [];
if (!fs.existsSync(manifestPath)) {
  missing.push({ kind: "MISSING_CLOSURE_MANIFEST", path: policy.closureManifest.path });
} else {
  try {
    manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
    assert.equal(manifest.kind, "ABI04_FROZEN_EXACT_CLOSURE_MANIFEST");
    assert.equal(manifest.schemaVersion, 2);
    assert.equal(manifest.selfPath, policy.closureManifest.path);
    assert.ok(Array.isArray(manifest.nodeRecords));
    assert.ok(Array.isArray(manifest.topologyEdges));
    assert.ok(manifest.nodeRecords.every((item) => typeof item.path === "string" && isSha256(item.sha256)), "manifest node record schema");
    assert.equal(manifest.nodeSetSha256, sha256(stable(manifest.nodeRecords)), "manifest node-set root");
    assert.equal(manifest.topologyEdgeSetSha256, sha256(stable(manifest.topologyEdges)), "manifest topology-edge root");
    assert.equal(manifest.exactTopologyEdgeCount, manifest.topologyEdges.length, "manifest topology-edge count");
  } catch (error) {
    mismatches.push({ kind: "CLOSURE_MANIFEST_PARSE_OR_SCHEMA_ERROR", consumer: policy.closureManifest.path, seedPath: policy.closureManifest.path, detail: String(error.message) });
    manifest = null;
  }
}

const manifestRecords = manifest?.nodeRecords ?? [];
const manifestPathCounts = new Map();
for (const record of manifestRecords) manifestPathCounts.set(record.path, (manifestPathCounts.get(record.path) ?? 0) + 1);
for (const [recordPath, count] of manifestPathCounts) if (count > 1) duplicate.push({ kind: "DUPLICATE_MANIFEST_NODE_PATH", path: recordPath, count });
const expectedNodePaths = new Set([...manifestRecords.map((item) => item.path), policy.closureManifest.path]);
const discoveredNodePaths = new Set(discovered);
if (manifest) {
  assert.equal(manifest.exactNodeCount, expectedNodePaths.size, "manifest exact node count mismatch");
  for (const expectedPath of [...expectedNodePaths].sort()) if (!discoveredNodePaths.has(expectedPath)) missing.push({ kind: "MISSING_EXACT_NODE", path: expectedPath });
  for (const actualPath of [...discoveredNodePaths].sort()) if (!expectedNodePaths.has(actualPath)) unexpected.push({ kind: "UNEXPECTED_EXACT_NODE", path: actualPath });
}

const requiredByPath = new Map(policy.requiredNodes.map((item) => [item.path, item]));
for (const expectedPath of expectedNodePaths) if (!requiredByPath.has(expectedPath)) requiredByPath.set(expectedPath, { id: `manifest-node:${expectedPath}`, category: "frozen-exact-node", path: expectedPath, dependsOn: [] });
for (const setName of ["expectedGraphs", "authoritativeBinders"]) {
  const set = policy.exactSets[setName];
  for (const name of set.expectedNames) {
    const relativePath = `${set.directory}/${name}`;
    if (!requiredByPath.has(relativePath)) requiredByPath.set(relativePath, { id: `${setName}:${name}`, category: setName === "expectedGraphs" ? "expected-graph" : "authoritative-binder", path: relativePath, dependsOn: [] });
  }
}

const allPaths = [...new Set([...discovered, ...requiredByPath.keys()])].sort();
const nodes = allPaths.map((relativePath) => {
  const filePath = absolute(relativePath);
  return {
    id: `file:${relativePath}`,
    path: relativePath,
    category: category(relativePath),
    required: requiredByPath.has(relativePath),
    exists: fs.existsSync(filePath),
    actualSha256: fs.existsSync(filePath) ? fileSha256(filePath) : null,
  };
});
const nodeByPath = new Map(nodes.map((item) => [item.path, item]));
missing.push(...nodes.filter((item) => item.required && !item.exists).map((item) => ({ kind: "MISSING_REQUIRED_NODE", path: item.path })));

function pointer(parts) {
  return `/${parts.map((part) => String(part).replaceAll("~", "~0").replaceAll("/", "~1")).join("/")}`;
}

function declarations(value, parts = [], output = []) {
  if (Array.isArray(value)) {
    value.forEach((item, index) => declarations(item, [...parts, index], output));
    return output;
  }
  if (!value || typeof value !== "object") return output;
  if (typeof value.path === "string") {
    for (const hashKey of ["sha256", "fileSha256", "sourceSha256", "artifactSha256", "declaredSha256"]) {
      if (isSha256(value[hashKey])) {
        output.push({ declaredPath: value.path, declaredSha256: value[hashKey].toLowerCase(), pointer: pointer([...parts, `path+${hashKey}`]), kind: "path-hash" });
        break;
      }
    }
  }
  for (const [key, child] of Object.entries(value)) {
    if (typeof child === "string" && key.endsWith("Path")) {
      const stem = key.slice(0, -4);
      for (const hashKey of [`${stem}Sha256`, `${stem}FileSha256`, `${stem}SourceSha256`]) {
        if (isSha256(value[hashKey])) {
          output.push({ declaredPath: child, declaredSha256: value[hashKey].toLowerCase(), pointer: pointer([...parts, `${key}+${hashKey}`]), kind: "named-path-hash" });
          break;
        }
      }
    }
    declarations(child, [...parts, key], output);
  }
  return output;
}

const edges = [];
for (const node of nodes.filter((item) => item.exists && item.path.endsWith(".json") && item.path !== policy.closureManifest.path)) {
  let json;
  try {
    json = JSON.parse(fs.readFileSync(absolute(node.path), "utf8"));
  } catch (error) {
    mismatches.push({ kind: "JSON_PARSE_ERROR", consumer: node.path, detail: String(error.message) });
    continue;
  }
  for (const declaration of declarations(json)) {
    if (path.isAbsolute(declaration.declaredPath) || declaration.declaredPath.startsWith("/")) {
      unexpected.push({ kind: "ABSOLUTE_DECLARED_PATH", consumer: node.path, pointer: declaration.pointer, path: declaration.declaredPath });
      continue;
    }
    const dependencyPath = declaration.declaredPath.replaceAll("\\", "/");
    const dependencyFile = absolute(dependencyPath);
    const actualSha256 = fs.existsSync(dependencyFile) ? fileSha256(dependencyFile) : null;
    const status = actualSha256 === null ? "MISSING" : actualSha256 === declaration.declaredSha256 ? "PASS" : "MISMATCH";
    const edge = {
      dependency: `file:${dependencyPath}`,
      consumer: node.id,
      declarationSource: node.path,
      declarationPointer: declaration.pointer,
      declarationKind: declaration.kind,
      declaredSha256: declaration.declaredSha256,
      actualSha256,
      status,
    };
    edges.push(edge);
    if (!nodeByPath.has(dependencyPath)) {
      const dependencyNode = { id: `file:${dependencyPath}`, path: dependencyPath, category: "declared-dependency", required: true, exists: fs.existsSync(dependencyFile), actualSha256 };
      nodes.push(dependencyNode);
      nodeByPath.set(dependencyPath, dependencyNode);
      if (!dependencyNode.exists) missing.push({ kind: "MISSING_DECLARED_DEPENDENCY", path: dependencyPath, consumer: node.path, pointer: declaration.pointer });
    }
    if (status !== "PASS") mismatches.push({ kind: status === "MISSING" ? "DECLARED_DEPENDENCY_MISSING" : "DECLARED_ACTUAL_MISMATCH", dependency: dependencyPath, consumer: node.path, seedPath: dependencyPath, pointer: declaration.pointer, declaredSha256: declaration.declaredSha256, actualSha256 });
  }
}

for (const [index, record] of manifestRecords.entries()) {
  const actualSha256 = nodeByPath.get(record.path)?.actualSha256 ?? null;
  const status = actualSha256 === null ? "MISSING" : actualSha256 === record.sha256 ? "PASS" : "MISMATCH";
  edges.push({
    dependency: `file:${record.path}`,
    consumer: `file:${policy.closureManifest.path}`,
    declarationSource: policy.closureManifest.path,
    declarationPointer: `/nodeRecords/${index}`,
    declarationKind: "frozen-exact-node-hash",
    declaredSha256: record.sha256,
    actualSha256,
    status,
  });
  if (status !== "PASS") mismatches.push({ kind: status === "MISSING" ? "FROZEN_NODE_MISSING" : "FROZEN_NODE_HASH_MISMATCH", dependency: record.path, consumer: policy.closureManifest.path, seedPath: record.path, pointer: `/nodeRecords/${index}`, declaredSha256: record.sha256, actualSha256 });
}

const policyTopologyKeys = policy.requiredNodes.flatMap((required) => required.dependsOn.map((parentPath) => `${parentPath}\u0000${required.path}`)).sort();
const manifestTopologyKeys = (manifest?.topologyEdges ?? []).map((edge) => `${edge.parent?.path}\u0000${edge.child?.path}`).sort();
for (const key of policyTopologyKeys.filter((item) => !manifestTopologyKeys.includes(item))) missing.push({ kind: "MISSING_FROZEN_TOPOLOGY_EDGE", path: policy.closureManifest.path, edge: key });
for (const key of manifestTopologyKeys.filter((item) => !policyTopologyKeys.includes(item))) unexpected.push({ kind: "UNEXPECTED_FROZEN_TOPOLOGY_EDGE", path: policy.closureManifest.path, edge: key });
if (new Set(manifestTopologyKeys).size !== manifestTopologyKeys.length) duplicate.push({ kind: "DUPLICATE_FROZEN_TOPOLOGY_EDGE", path: policy.closureManifest.path });
for (const [index, topology] of (manifest?.topologyEdges ?? []).entries()) {
  const parentPath = topology.parent?.path;
  const childPath = topology.child?.path;
  const parentActual = nodeByPath.get(parentPath)?.actualSha256 ?? null;
  const childActual = nodeByPath.get(childPath)?.actualSha256 ?? null;
  const parentPass = parentActual !== null && parentActual === topology.parent?.sha256;
  const childPass = childActual !== null && childActual === topology.child?.sha256;
  edges.push({
    dependency: `file:${parentPath}`,
    consumer: `file:${childPath}`,
    declarationSource: policy.closureManifest.path,
    declarationPointer: `/topologyEdges/${index}`,
    declarationKind: "frozen-parent-child-hash",
    declaredSha256: topology.parent?.sha256 ?? null,
    actualSha256: parentActual,
    declaredConsumerSha256: topology.child?.sha256 ?? null,
    actualConsumerSha256: childActual,
    status: parentPass && childPass ? "PASS" : "MISMATCH",
  });
  if (!parentPass) mismatches.push({ kind: parentActual === null ? "FROZEN_EDGE_PARENT_MISSING" : "FROZEN_EDGE_PARENT_HASH_MISMATCH", dependency: parentPath, consumer: childPath, seedPath: parentPath, pointer: `/topologyEdges/${index}/parent`, declaredSha256: topology.parent?.sha256 ?? null, actualSha256: parentActual });
  if (!childPass) mismatches.push({ kind: childActual === null ? "FROZEN_EDGE_CHILD_MISSING" : "FROZEN_EDGE_CHILD_HASH_MISMATCH", dependency: parentPath, consumer: childPath, seedPath: childPath, pointer: `/topologyEdges/${index}/child`, declaredSha256: topology.child?.sha256 ?? null, actualSha256: childActual });
}

function getPointer(value, jsonPointer) {
  return jsonPointer.split("/").slice(1).reduce((current, token) => current?.[token.replaceAll("~1", "/").replaceAll("~0", "~")], value);
}

const exactSetVerdicts = {};
for (const setName of ["finiteClaims", "symbolicClaims", "exactReplayRecords", "nonReplayGates"]) {
  const spec = policy.exactSets[setName];
  const sourcePath = absolute(spec.source);
  let ids = [];
  if (fs.existsSync(sourcePath)) {
    const source = JSON.parse(fs.readFileSync(sourcePath, "utf8"));
    const records = getPointer(source, spec.arrayPointer);
    if (Array.isArray(records)) ids = records.map((record) => record?.[spec.idField] ?? record?.[spec.fallbackIdField]).filter((item) => typeof item === "string");
  }
  const counts = new Map();
  ids.forEach((id) => counts.set(id, (counts.get(id) ?? 0) + 1));
  const actualUniqueIds = [...counts.keys()].sort();
  const expectedIds = Array.isArray(spec.expectedIds) ? [...spec.expectedIds].sort() : null;
  const absent = expectedIds === null ? [] : expectedIds.filter((id) => !counts.has(id));
  const expectedIdSet = expectedIds === null ? null : new Set(expectedIds);
  const extra = expectedIdSet === null ? [] : actualUniqueIds.filter((id) => !expectedIdSet.has(id));
  const duplicateIds = [...counts].filter(([, count]) => count > 1).map(([id]) => id).sort();
  duplicateIds.forEach((id) => duplicate.push({ kind: "DUPLICATE_EXACT_SET_ID", set: setName, id }));
  absent.forEach((id) => missing.push({ kind: "MISSING_EXACT_SET_ID", set: setName, id, path: spec.source }));
  extra.forEach((id) => unexpected.push({ kind: "UNEXPECTED_EXACT_SET_ID", set: setName, id, path: spec.source }));
  exactSetVerdicts[setName] = {
    source: spec.source,
    expectedCount: spec.expectedCount,
    actualCount: ids.length,
    uniqueCount: counts.size,
    idsSha256: sha256(stable(actualUniqueIds)),
    expectedIdsSha256: expectedIds === null ? null : sha256(stable(expectedIds)),
    missing: absent,
    unexpected: extra,
    duplicateIds,
    status: ids.length === spec.expectedCount && counts.size === spec.expectedCount && absent.length === 0 && extra.length === 0 ? "PASS" : "FAIL",
  };
}

for (const setName of ["expectedGraphs", "authoritativeBinders"]) {
  const spec = policy.exactSets[setName];
  const directory = absolute(spec.directory);
  const actualNames = fs.existsSync(directory) ? fs.readdirSync(directory, { withFileTypes: true }).filter((entry) => entry.isFile() && entry.name.endsWith(".json")).map((entry) => entry.name).sort() : [];
  const expectedNames = [...spec.expectedNames].sort();
  const absent = expectedNames.filter((name) => !actualNames.includes(name));
  const extra = actualNames.filter((name) => !expectedNames.includes(name));
  absent.forEach((name) => missing.push({ kind: "MISSING_EXACT_SET_FILE", set: setName, path: `${spec.directory}/${name}` }));
  extra.forEach((name) => unexpected.push({ kind: "UNEXPECTED_EXACT_SET_FILE", set: setName, path: `${spec.directory}/${name}` }));
  exactSetVerdicts[setName] = { directory: spec.directory, expectedCount: spec.expectedCount, actualCount: actualNames.length, expectedNamesSha256: sha256(stable(expectedNames)), actualNamesSha256: sha256(stable(actualNames)), missing: absent, unexpected: extra, status: absent.length === 0 && extra.length === 0 && actualNames.length === spec.expectedCount ? "PASS" : "FAIL" };
}

if (exactSetVerdicts.finiteClaims.status === "PASS" && exactSetVerdicts.symbolicClaims.status === "PASS") {
  const finiteSource = JSON.parse(fs.readFileSync(absolute(policy.exactSets.finiteClaims.source), "utf8"));
  const symbolicSource = JSON.parse(fs.readFileSync(absolute(policy.exactSets.symbolicClaims.source), "utf8"));
  const semanticIds = [
    ...getPointer(finiteSource, policy.exactSets.finiteClaims.arrayPointer).map((item) => item.caseId),
    ...getPointer(symbolicSource, policy.exactSets.symbolicClaims.arrayPointer).map((item) => item.semanticClaimId ?? item.claimId),
  ].sort();
  const expectedReplayIds = semanticIds.flatMap((id) => [`${id}::canonical-positive`, `${id}::unchanged-claim-mutant-negative`]).sort();
  exactSetVerdicts.expectedReplayIds = { count: expectedReplayIds.length, sha256: sha256(stable(expectedReplayIds)), status: expectedReplayIds.length === 162 ? "PASS" : "FAIL" };
  if (fs.existsSync(absolute(policy.exactSets.exactReplayRecords.source))) {
    const ledger = JSON.parse(fs.readFileSync(absolute(policy.exactSets.exactReplayRecords.source), "utf8"));
    const actualReplayIds = getPointer(ledger, policy.exactSets.exactReplayRecords.arrayPointer).map((item) => item.replayId).sort();
    exactSetVerdicts.exactReplayRecords.missing = expectedReplayIds.filter((id) => !actualReplayIds.includes(id));
    exactSetVerdicts.exactReplayRecords.unexpected = actualReplayIds.filter((id) => !expectedReplayIds.includes(id));
    exactSetVerdicts.exactReplayRecords.missing.forEach((id) => missing.push({ kind: "MISSING_EXACT_SET_ID", set: "exactReplayRecords", id, path: policy.exactSets.exactReplayRecords.source }));
    exactSetVerdicts.exactReplayRecords.unexpected.forEach((id) => unexpected.push({ kind: "UNEXPECTED_EXACT_SET_ID", set: "exactReplayRecords", id, path: policy.exactSets.exactReplayRecords.source }));
    if (exactSetVerdicts.exactReplayRecords.missing.length || exactSetVerdicts.exactReplayRecords.unexpected.length) exactSetVerdicts.exactReplayRecords.status = "FAIL";
  }
}

const duplicateEdges = [];
const edgeKeys = new Map();
for (const edge of edges) {
  const key = `${edge.dependency}\u0000${edge.consumer}\u0000${edge.declarationSource}\u0000${edge.declarationPointer}`;
  edgeKeys.set(key, (edgeKeys.get(key) ?? 0) + 1);
}
for (const [key, count] of edgeKeys) if (count > 1) duplicateEdges.push({ kind: "DUPLICATE_DECLARATION_EDGE", key, count });
duplicate.push(...duplicateEdges);

nodes.sort((left, right) => compareCodePoints(left.id, right.id));
edges.sort((left, right) => compareCodePoints(stable(left), stable(right)));
const closureMaterial = { nodes, edges };
const closureHash = sha256(stable(closureMaterial));

const adjacency = new Map();
for (const edge of edges) {
  if (!adjacency.has(edge.dependency)) adjacency.set(edge.dependency, new Set());
  adjacency.get(edge.dependency).add(edge.consumer);
}
const seeds = new Set();
missing.forEach((item) => seeds.add(`file:${item.path}`));
unexpected.forEach((item) => {
  if (item.consumer) seeds.add(`file:${item.consumer}`);
  else if (item.path && !path.isAbsolute(item.path)) seeds.add(`file:${item.path}`);
});
mismatches.forEach((item) => {
  const seedPath = item.seedPath ?? item.consumer;
  if (seedPath) seeds.add(seedPath.startsWith("file:") ? seedPath : `file:${seedPath}`);
});
for (const [setName, verdict] of Object.entries(exactSetVerdicts)) if (verdict?.status === "FAIL" && verdict.source) seeds.add(`file:${verdict.source}`);
const invalidated = new Set(seeds);
const queue = [...seeds].sort();
while (queue.length) {
  const current = queue.shift();
  for (const consumer of [...(adjacency.get(current) ?? [])].sort()) if (!invalidated.has(consumer)) { invalidated.add(consumer); queue.push(consumer); }
}

const failedExactSets = Object.entries(exactSetVerdicts).filter(([, value]) => value?.status === "FAIL").map(([name]) => name);
const failed = missing.length > 0 || unexpected.length > 0 || duplicate.length > 0 || mismatches.length > 0 || failedExactSets.length > 0;
const dag = {
  schemaVersion: 1,
  kind: "ABI04_STRICT_TRANSITIVE_HASH_DAG",
  obligationId: "ABI-04",
  closureHashSha256: closureHash,
  nodes,
  edges,
  exactSets: exactSetVerdicts,
};
const verdict = {
  schemaVersion: 1,
  kind: "ABI04_JS_STRICT_CLOSURE_VERDICT",
  implementation: "independent-javascript",
  status: failed ? "FAIL_CLOSED_INVALIDATED" : "PASS",
  exitCode: failed ? 1 : 0,
  closureHashSha256: closureHash,
  counts: { nodes: nodes.length, edges: edges.length, missing: missing.length, unexpected: unexpected.length, duplicate: duplicate.length, declaredActualMismatch: mismatches.length, invalidated: invalidated.size },
  missing,
  unexpected,
  duplicate,
  declaredActualMismatch: mismatches,
  failedExactSets,
  invalidationSeeds: [...seeds].sort(),
  invalidatedDescendants: [...invalidated].sort(),
  policy: { path: posix(policyPath), sha256: fileSha256(policyPath) },
  prohibitions: policy.failurePolicy,
  nonclaims: ["This verdict grants no proof or discharge credit.", "PASS is necessary but insufficient for ABI-04 central discharge."],
};

if (outDir) {
  writeJson(path.join(outDir, "dependency-closure.json"), dag);
  writeJson(path.join(outDir, "js-verdict.json"), verdict);
}
console.log(JSON.stringify(fullOutput ? verdict : { status: verdict.status, exitCode: verdict.exitCode, closureHashSha256: closureHash, counts: verdict.counts, failedExactSets }, null, 2));
process.exitCode = verdict.exitCode;
