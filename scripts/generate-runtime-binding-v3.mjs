// SPDX-License-Identifier: BSD-3-Clause
//
// Two-layer runtime binding of the successor subjects (kernel version 2).
//
// Layer 1 (template identity): the Foundry artifacts of the native token, the ERC-3643
// profile adapter, and the profile governor are read from out/ and their runtime and
// creation bytecode hashes are bound to the generated runtime bridge and the release
// manifest.
//
// Layer 2 (pinned-compiler replay): the exact Solidity sources of each subject (the import
// closure of its root file) are compiled again with the pinned solc binary through the
// standard JSON interface, with the settings of foundry.toml, and the six semantic
// projections (ABI, storage layout, creation bytecode, runtime template, method
// identifiers, immutable references) of the compiler output are compared with the Foundry
// artifact. The exact standard JSON input is stored; the compiler output is bound by hash.
//
// Usage:
//   node scripts/generate-runtime-binding-v3.mjs          write evidence/runtime-binding-v3/** and evidence/runtime-binding-v3.json
//   node scripts/generate-runtime-binding-v3.mjs --check  regenerate in memory and fail on any drift of the written files
//
// The receipt is bound to the current source root with the same algorithm as
// scripts/verify-current-profile-release-v3.mjs, so a stale receipt is rejected by the
// lane verifier and by scripts/verify-runtime-binding-v3.mjs.

import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, posix, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { resolvePinnedSolc } from "./lib/resolve-pinned-solc.mjs";
import { immutablePositions, normalizeHex, pinnedCompilerSettings, semanticCheckNames, semanticChecks, semanticStorageLayout, stable } from "./lib/runtime-binding-semantics.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const checkMode = process.argv.includes("--check");
const evidenceDir = "evidence/runtime-binding-v3";
const receiptPath = "evidence/runtime-binding-v3.json";

const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const abs = (path) => resolve(root, ...path.split("/"));
const bytes = (path) => readFileSync(abs(path));
const text = (path) => bytes(path).toString("utf8").replace(/\r\n?/g, "\n");
const json = (path) => JSON.parse(text(path));
const stableJson = (value) => `${JSON.stringify(stable(value), null, 2)}\n`;
function walk(path) {
  if (!existsSync(abs(path))) return [];
  return readdirSync(abs(path), { withFileTypes: true }).flatMap((entry) => {
    const child = `${path}/${entry.name}`;
    return entry.isDirectory() ? walk(child) : [child];
  });
}
function rootOf(paths) {
  const sorted = [...paths].sort((left, right) => (left < right ? -1 : left > right ? 1 : 0));
  return sha256(Buffer.from(sorted.map((path) => `${sha256(bytes(path))}  ${path}\n`).join(""), "utf8"));
}

// ---------------------------------------------------------------------------
// Pinned compiler and settings (the standard JSON equivalent of foundry.toml)
// ---------------------------------------------------------------------------

const dependencyLock = json("formal/kevm/dependencies.lock.json");
const solc = dependencyLock.components.solc;
const pinnedSolc = resolvePinnedSolc(solc);
const settings = pinnedCompilerSettings;

const bundles = [
  {
    id: "native",
    roots: ["implementation/src/TrustToken.sol"],
    subjects: [{ id: "native", source: "implementation/src/TrustToken.sol", contract: "TrustToken", artifact: "out/TrustToken.sol/TrustToken.json" }],
  },
  {
    id: "verified-profile",
    roots: ["implementation/src/profiles/ERC3643TrustAdapter.sol", "implementation/src/profiles/ProfileGovernor.sol"],
    subjects: [
      { id: "profileAdapter", source: "implementation/src/profiles/ERC3643TrustAdapter.sol", contract: "ERC3643TrustAdapter", artifact: "out/ERC3643TrustAdapter.sol/ERC3643TrustAdapter.json" },
      { id: "profileGovernor", source: "implementation/src/profiles/ProfileGovernor.sol", contract: "ProfileGovernor", artifact: "out/ProfileGovernor.sol/ProfileGovernor.json" },
    ],
  },
];

// ---------------------------------------------------------------------------
// Exact compiler input: the import closure of each bundle's roots
// ---------------------------------------------------------------------------

function sourceImports(sourcePath, content) {
  const imports = [];
  for (const match of content.matchAll(/\bimport\s+(?:[^"']*?\s+from\s+)?["']([^"']+)["']\s*;/g)) {
    const requested = match[1];
    if (!requested.startsWith(".")) throw new Error(`non-relative import in ${sourcePath}: ${requested}`);
    imports.push(posix.normalize(posix.join(posix.dirname(sourcePath), requested)));
  }
  return imports;
}
function importClosure(roots) {
  const pending = [...roots];
  const found = new Map();
  while (pending.length !== 0) {
    const sourcePath = pending.pop();
    if (found.has(sourcePath)) continue;
    if (!existsSync(abs(sourcePath))) throw new Error(`missing Solidity source: ${sourcePath}`);
    const content = text(sourcePath);
    found.set(sourcePath, content);
    pending.push(...sourceImports(sourcePath, content));
  }
  return new Map([...found.entries()].sort(([left], [right]) => (left < right ? -1 : left > right ? 1 : 0)));
}
function runSolc(inputText) {
  const command = pinnedSolc.execution === "wsl" ? "wsl.exe" : pinnedSolc.binaryPath;
  const args = pinnedSolc.execution === "wsl" ? ["-d", pinnedSolc.distribution, "-e", pinnedSolc.binaryPath, "--standard-json"] : ["--standard-json"];
  const started = process.hrtime.bigint();
  const outputText = execFileSync(command, args, { input: inputText, encoding: "utf8", maxBuffer: 512 * 1024 * 1024 });
  const elapsedMs = Number(process.hrtime.bigint() - started) / 1_000_000;
  const output = JSON.parse(outputText);
  const errors = (output.errors ?? []).filter((entry) => entry.severity === "error");
  if (errors.length !== 0) throw new Error(`solc error: ${errors[0].formattedMessage}`);
  return { output, outputText, elapsedMs };
}


// ---------------------------------------------------------------------------
// Generation
// ---------------------------------------------------------------------------

const mode = json("evidence/evidence-mode.json");
const bridge = json("evidence/end-to-end-refinement/runtime-bridge-v2/schema.json");
const sourceRootSha256 = rootOf([...walk("implementation/src"), ...walk("implementation/test"), "foundry.toml"]);
const written = new Map(); // repo path -> content
const bundleRecords = [];
const subjectRecords = [];
for (const bundle of bundles) {
  const closure = importClosure(bundle.roots);
  const input = { language: "Solidity", sources: Object.fromEntries([...closure.entries()].map(([path, content]) => [path, { content }])), settings };
  const inputText = `${JSON.stringify(input, null, 2)}\n`;
  const run = runSolc(inputText);
  const sourceIdentities = [...closure.entries()].map(([path, content]) => ({ path, bytes: Buffer.byteLength(content), sha256: sha256(Buffer.from(content, "utf8")) }));
  const bridgeArtifacts = [];
  for (const subject of bundle.subjects) {
    const compiler = run.output.contracts?.[subject.source]?.[subject.contract];
    if (!compiler) throw new Error(`compiler output missing ${subject.source}:${subject.contract}`);
    if (!existsSync(abs(subject.artifact))) throw new Error(`missing Foundry artifact: ${subject.artifact}; run forge build first`);
    const artifact = json(subject.artifact);
    const checks = semanticChecks(artifact, compiler);
    const failed = semanticCheckNames.filter((name) => checks[name] !== true);
    if (failed.length !== 0) throw new Error(`pinned-compiler replay differs from the Foundry artifact for ${subject.id}: ${failed.join(", ")}`);
    const runtime = Buffer.from(normalizeHex(compiler.evm.deployedBytecode.object), "hex");
    const creation = Buffer.from(normalizeHex(compiler.evm.bytecode.object), "hex");
    const bridgeSubject = bridge.subjects[subject.id];
    if (!bridgeSubject || bridgeSubject.runtime.sha256 !== sha256(runtime)) throw new Error(`runtime of ${subject.id} differs from the generated runtime bridge`);
    const record = {
      id: subject.id,
      bundle: bundle.id,
      source: subject.source,
      contract: subject.contract,
      artifact: subject.artifact,
      runtimeTemplate: { bytes: runtime.length, sha256: sha256(runtime), eip170MarginBytes: 24576 - runtime.length },
      creationBytecode: { bytes: creation.length, sha256: sha256(creation) },
      immutableReferences: immutablePositions(compiler.evm.deployedBytecode.immutableReferences),
      semanticChecks: checks,
    };
    subjectRecords.push(record);
    bridgeArtifacts.push({ ...record, abi: compiler.abi, storageLayout: semanticStorageLayout(compiler.storageLayout), methodIdentifiers: compiler.evm.methodIdentifiers });
  }
  const dir = `${evidenceDir}/${bundle.id}`;
  written.set(`${dir}/standard-json-input.json`, inputText);
  written.set(`${dir}/bridge-artifacts.json`, stableJson(bridgeArtifacts));
  written.set(`${dir}/source-identities.json`, stableJson(sourceIdentities));
  bundleRecords.push({
    id: bundle.id,
    roots: bundle.roots,
    sourceCount: closure.size,
    subjects: bundle.subjects.map((subject) => subject.id),
    compilerRun: { outputSha256: sha256(Buffer.from(run.outputText, "utf8")) },
    files: [`${dir}/standard-json-input.json`, `${dir}/bridge-artifacts.json`, `${dir}/source-identities.json`].map((path) => ({ path, sha256: sha256(Buffer.from(written.get(path), "utf8")) })),
  });
}

const receipt = {
  schema: "erc-trust-runtime-binding-v3",
  kind: "ERC_TRUST_RUNTIME_BINDING_V3",
  candidate: mode.candidate,
  status: "PASS_RUNTIME_SEMANTIC_IDENTITY",
  runtimeTemplateSha256: subjectRecords.find((subject) => subject.id === "native").runtimeTemplate.sha256,
  sourceRootAlgorithm: "sha256-raw-files-case-sensitive-path-order-v1",
  sourceRootSha256,
  compiler: {
    version: solc.version,
    binaryLocator: solc.binaryLocator,
    binarySha256: solc.binarySha256,
    settingsSha256: sha256(Buffer.from(stableJson(settings), "utf8")),
    foundryTomlSha256: sha256(bytes("foundry.toml")),
    correctnessClaimed: false,
  },
  bridge: { path: "evidence/end-to-end-refinement/runtime-bridge-v2/schema.json", sha256: sha256(bytes("evidence/end-to-end-refinement/runtime-bridge-v2/schema.json")) },
  layers: {
    templateIdentity: "the Foundry artifact runtime and creation hashes of each subject, bound to the generated runtime bridge, the release manifest, and the deterministic build receipt",
    pinnedCompilerReplay: "the exact import closure of each subject compiled again with the pinned solc binary through standard JSON with the settings of foundry.toml; the six semantic projections of the output equal the Foundry artifact",
  },
  subjects: subjectRecords,
  bundles: bundleRecords,
  replay: {
    generate: "node scripts/generate-runtime-binding-v3.mjs",
    verify: "node scripts/verify-runtime-binding-v3.mjs --replay",
    check: "node scripts/generate-runtime-binding-v3.mjs --check",
  },
  nonclaims: [
    "Equality of the six semantic projections between the pinned compiler output and the Foundry artifact binds the compiled bytes to the exact sources; it does not establish compiler correctness.",
    "The runtime template is the unresolved artifact runtime; constructor execution, immutable resolution, and deployment identity are outside this receipt.",
    "No audit, deployment, production, or legal-truth claim is made.",
  ],
};
written.set(receiptPath, stableJson(receipt));

if (checkMode) {
  const drift = [];
  for (const [path, content] of written) {
    if (!existsSync(abs(path)) || text(path) !== content) drift.push(path);
  }
  if (drift.length !== 0) {
    for (const path of drift) console.error(`runtime binding drift: ${path}`);
    process.exit(1);
  }
  console.log(`runtime binding check PASS: ${subjectRecords.length} subjects replayed under solc ${solc.version}`);
} else {
  for (const [path, content] of written) {
    mkdirSync(dirname(abs(path)), { recursive: true });
    writeFileSync(abs(path), content, "utf8");
  }
  console.log(JSON.stringify({ status: receipt.status, subjects: subjectRecords.map((subject) => ({ id: subject.id, runtime: subject.runtimeTemplate.sha256, bytes: subject.runtimeTemplate.bytes })), sourceRootSha256 }, null, 2));
}
