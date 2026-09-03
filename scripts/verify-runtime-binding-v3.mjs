// SPDX-License-Identifier: BSD-3-Clause
//
// Verify the two-layer runtime binding of the successor subjects
// (evidence/runtime-binding-v3.json and evidence/runtime-binding-v3/**).
//
// Without flags the verifier needs only the tree and the Foundry artifacts: it rejects a
// receipt whose source root, stored compiler input, source identities, bridge artifacts,
// or runtime hashes differ from the current tree, the generated runtime bridge, the release
// manifest, and the deterministic build receipt; it rejects each of the five enumerated
// successor receipts (deterministic build, Foundry, mutation, Kontrol, Certora) that is
// present and binds a different source root or runtime template (stale evidence), and lists
// the absent ones; it requires the stored compiler settings to be the pinned settings; and it proves
// that its own semantic classifier kills one deliberate mutant per semantic class and
// subject. With --replay it also recompiles the stored standard JSON input with the pinned
// solc binary and requires the output hash and the six semantic projections to match.
//
// Usage:
//   node scripts/verify-runtime-binding-v3.mjs            structural verification
//   node scripts/verify-runtime-binding-v3.mjs --replay   plus pinned-compiler replay

import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { dirname, posix, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { resolvePinnedSolc } from "./lib/resolve-pinned-solc.mjs";
import { artifactAsCompilerContract, immutablePositions, normalizedAbi, pinnedCompilerSettings, semanticCheckNames, semanticChecks, semanticMutant, semanticStorageLayout, stable } from "./lib/runtime-binding-semantics.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const replay = process.argv.includes("--replay");
const receiptPath = "evidence/runtime-binding-v3.json";
const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const abs = (path) => resolve(root, ...path.split("/"));
const exists = (path) => existsSync(abs(path));
const bytes = (path) => readFileSync(abs(path));
const text = (path) => bytes(path).toString("utf8").replace(/\r\n?/g, "\n");
const json = (path) => JSON.parse(text(path));
const failures = [];
const check = (condition, message) => { if (!condition) failures.push(message); };
function walk(path) {
  if (!exists(path)) return [];
  return readdirSync(abs(path), { withFileTypes: true }).flatMap((entry) => {
    const child = `${path}/${entry.name}`;
    return entry.isDirectory() ? walk(child) : [child];
  });
}
function rootOf(paths) {
  const sorted = [...paths].sort((left, right) => (left < right ? -1 : left > right ? 1 : 0));
  return sha256(Buffer.from(sorted.map((path) => `${sha256(bytes(path))}  ${path}\n`).join(""), "utf8"));
}
function sourceImports(sourcePath, content) {
  const imports = [];
  for (const match of content.matchAll(/\bimport\s+(?:[^"']*?\s+from\s+)?["']([^"']+)["']\s*;/g)) {
    if (!match[1].startsWith(".")) throw new Error(`non-relative import in ${sourcePath}: ${match[1]}`);
    imports.push(posix.normalize(posix.join(posix.dirname(sourcePath), match[1])));
  }
  return imports;
}
function importClosure(roots) {
  const pending = [...roots];
  const found = new Map();
  while (pending.length !== 0) {
    const sourcePath = pending.pop();
    if (found.has(sourcePath)) continue;
    check(exists(sourcePath), `missing Solidity source: ${sourcePath}`);
    if (!exists(sourcePath)) continue;
    const content = text(sourcePath);
    found.set(sourcePath, content);
    pending.push(...sourceImports(sourcePath, content));
  }
  return new Map([...found.entries()].sort(([left], [right]) => (left < right ? -1 : left > right ? 1 : 0)));
}

// ---------------------------------------------------------------------------
// Receipt identity and stale-evidence rejection
// ---------------------------------------------------------------------------

check(exists(receiptPath), `runtime binding receipt missing: ${receiptPath}`);
if (!exists(receiptPath)) { for (const failure of failures) console.error(failure); process.exit(1); }
const receipt = json(receiptPath);
const mode = json("evidence/evidence-mode.json");
check(receipt.schema === "erc-trust-runtime-binding-v3" && receipt.candidate === mode.candidate, "runtime binding receipt identity");
check(receipt.status === "PASS_RUNTIME_SEMANTIC_IDENTITY", "runtime binding status");
const sourceRootSha256 = rootOf([...walk("implementation/src"), ...walk("implementation/test"), "foundry.toml"]);
check(receipt.sourceRootSha256 === sourceRootSha256, "runtime binding receipt binds a different source root (stale)");
check(sha256(bytes("foundry.toml")) === receipt.compiler.foundryTomlSha256, "foundry.toml changed since the receipt");
const bridge = json("evidence/end-to-end-refinement/runtime-bridge-v2/schema.json");
check(sha256(bytes("evidence/end-to-end-refinement/runtime-bridge-v2/schema.json")) === receipt.bridge.sha256, "runtime binding receipt binds a different runtime bridge");
const manifest = json("evidence/release-manifest.json");
const deterministic = exists("evidence/deterministic-build.json") ? json("evidence/deterministic-build.json") : null;

const subjectsById = new Map(receipt.subjects.map((subject) => [subject.id, subject]));
for (const id of ["native", "profileAdapter", "profileGovernor"]) check(subjectsById.has(id), `receipt lacks subject ${id}`);
for (const subject of receipt.subjects) {
  check(exists(subject.artifact), `Foundry artifact missing: ${subject.artifact}; run forge build first`);
  if (!exists(subject.artifact)) continue;
  const artifact = json(subject.artifact);
  const runtime = Buffer.from(artifact.deployedBytecode.object.replace(/^0x/, ""), "hex");
  const creation = Buffer.from(artifact.bytecode.object.replace(/^0x/, ""), "hex");
  check(sha256(runtime) === subject.runtimeTemplate.sha256 && runtime.length === subject.runtimeTemplate.bytes, `layer 1: runtime of ${subject.id} differs from the Foundry artifact`);
  check(sha256(creation) === subject.creationBytecode.sha256 && creation.length === subject.creationBytecode.bytes, `layer 1: creation bytecode of ${subject.id} differs from the Foundry artifact`);
  check(bridge.subjects[subject.id]?.runtime?.sha256 === subject.runtimeTemplate.sha256, `runtime of ${subject.id} differs from the generated runtime bridge`);
  check(subject.runtimeTemplate.bytes <= 24576, `EIP-170 overflow: ${subject.id}`);
  check(JSON.stringify(stable(immutablePositions(artifact.deployedBytecode.immutableReferences))) === JSON.stringify(stable(subject.immutableReferences)), `immutable reference positions of ${subject.id} differ from the Foundry artifact`);
  for (const name of semanticCheckNames) check(subject.semanticChecks?.[name] === true, `layer 2 check ${name} not recorded as passed for ${subject.id}`);
}
check(receipt.runtimeTemplateSha256 === subjectsById.get("native")?.runtimeTemplate.sha256, "runtimeTemplateSha256 is not the native runtime");
check(manifest.trustToken?.runtimeSha256 === receipt.runtimeTemplateSha256, "release manifest binds a different native runtime");
check(manifest.profileRuntimes?.erc3643Adapter?.runtimeSha256 === subjectsById.get("profileAdapter")?.runtimeTemplate.sha256, "release manifest does not bind the adapter runtime of the receipt");
check(manifest.profileRuntimes?.profileGovernor?.runtimeSha256 === subjectsById.get("profileGovernor")?.runtimeTemplate.sha256, "release manifest does not bind the governor runtime of the receipt");
check(deterministic !== null, "deterministic build receipt missing: the runtime binding cannot be verified without it");
check(deterministic?.buildA?.runtimeSha256 === receipt.runtimeTemplateSha256, "deterministic build receipt binds a different native runtime");
for (const [id, key] of [["profileAdapter", "erc3643Adapter"], ["profileGovernor", "profileGovernor"]]) {
  check(deterministic?.buildA?.subjects?.[key]?.runtimeSha256 === subjectsById.get(id)?.runtimeTemplate.sha256, `deterministic build receipt does not bind the ${id} runtime of the receipt`);
}

// Every other successor receipt that binds a source root or a runtime template must bind the current one.
const staleChecks = [
  ["evidence/deterministic-build.json", (data) => data.candidateInput?.sourceRootSha256 === sourceRootSha256],
  ["evidence/foundry-results-v3.json", (data) => data.sourceRootSha256 === sourceRootSha256 && data.runtimeTemplate?.sha256 === receipt.runtimeTemplateSha256],
  ["evidence/mutation-results.json", (data) => data.candidateInput?.sourceRootSha256 === sourceRootSha256],
  ["evidence/kontrol-results-v3.json", (data) => data.runtimeBinding?.runtimeSha256 === receipt.runtimeTemplateSha256],
  ["evidence/certora-results-v3.json", (data) => data.runtimeTemplateSha256 === receipt.runtimeTemplateSha256],
];
const staleEvidence = [];
const skippedReceipts = [];
for (const [path, current] of staleChecks) {
  if (!exists(path)) { skippedReceipts.push(path); continue; }
  const ok = current(json(path));
  staleEvidence.push({ path, current: ok });
  check(ok, `stale evidence rejected: ${path} binds a different source root or runtime`);
}

// ---------------------------------------------------------------------------
// Stored compiler input, source identities, bridge artifacts
// ---------------------------------------------------------------------------

for (const bundle of receipt.bundles) {
  const dir = `evidence/runtime-binding-v3/${bundle.id}`;
  for (const file of bundle.files) {
    check(exists(file.path), `stored file missing: ${file.path}`);
    if (exists(file.path)) check(sha256(Buffer.from(text(file.path), "utf8")) === file.sha256, `stored file drift: ${file.path}`);
  }
  if (!exists(`${dir}/standard-json-input.json`)) continue;
  const stored = json(`${dir}/standard-json-input.json`);
  const closure = importClosure(bundle.roots);
  check(JSON.stringify(stable(stored.settings)) === JSON.stringify(stable(pinnedCompilerSettings)), `stored compiler settings of ${bundle.id} are not the pinned settings`);
  check(JSON.stringify(Object.keys(stored.sources)) === JSON.stringify([...closure.keys()]), `stored compiler input of ${bundle.id} does not name the current import closure`);
  for (const [path, content] of closure) check(stored.sources[path]?.content === content, `stored compiler input of ${bundle.id} differs from the current source ${path}`);
  const identities = json(`${dir}/source-identities.json`);
  check(JSON.stringify(identities.map((entry) => [entry.path, entry.sha256])) === JSON.stringify([...closure.entries()].map(([path, content]) => [path, sha256(Buffer.from(content, "utf8"))])), `source identities of ${bundle.id} differ from the current sources`);
  const bridgeArtifacts = json(`${dir}/bridge-artifacts.json`);
  for (const stored of bridgeArtifacts) {
    const subject = subjectsById.get(stored.id);
    if (!subject || !exists(subject.artifact)) continue;
    const artifact = json(subject.artifact);
    check(JSON.stringify(normalizedAbi(stored.abi)) === JSON.stringify(normalizedAbi(artifact.abi)), `stored ABI of ${stored.id} differs from the Foundry artifact`);
    check(JSON.stringify(stable(stored.storageLayout)) === JSON.stringify(stable(semanticStorageLayout(artifact.storageLayout))), `stored storage layout of ${stored.id} differs from the Foundry artifact`);
    check(JSON.stringify(stable(stored.methodIdentifiers)) === JSON.stringify(stable(artifact.methodIdentifiers)), `stored method identifiers of ${stored.id} differ from the Foundry artifact`);
  }
  if (replay) {
    const solc = json("formal/kevm/dependencies.lock.json").components.solc;
    check(solc.binarySha256 === receipt.compiler.binarySha256 && solc.version === receipt.compiler.version, "pinned solc identity differs from the receipt");
    const pinned = resolvePinnedSolc(solc);
    const command = pinned.execution === "wsl" ? "wsl.exe" : pinned.binaryPath;
    const args = pinned.execution === "wsl" ? ["-d", pinned.distribution, "-e", pinned.binaryPath, "--standard-json"] : ["--standard-json"];
    const outputText = execFileSync(command, args, { input: text(`${dir}/standard-json-input.json`), encoding: "utf8", maxBuffer: 512 * 1024 * 1024 });
    check(sha256(Buffer.from(outputText, "utf8")) === bundle.compilerRun.outputSha256, `pinned-compiler replay of ${bundle.id} produced a different output`);
    const output = JSON.parse(outputText);
    for (const id of bundle.subjects) {
      const subject = subjectsById.get(id);
      const compiler = output.contracts?.[subject.source]?.[subject.contract];
      check(compiler !== undefined, `replay output lacks ${subject.contract}`);
      if (!compiler || !exists(subject.artifact)) continue;
      const checks = semanticChecks(json(subject.artifact), compiler);
      for (const name of semanticCheckNames) check(checks[name] === true, `replay semantic check ${name} failed for ${id}`);
    }
  }
}

// ---------------------------------------------------------------------------
// The classifier kills its own deliberate mutants
// ---------------------------------------------------------------------------

let killed = 0;
let required = 0;
for (const subject of receipt.subjects) {
  if (!exists(subject.artifact)) continue;
  const artifact = json(subject.artifact);
  for (const semanticClass of semanticCheckNames) {
    required += 1;
    const checks = semanticChecks(semanticMutant(artifact, semanticClass), artifactAsCompilerContract(artifact));
    const failed = semanticCheckNames.filter((name) => checks[name] !== true);
    if (failed.length === 1 && failed[0] === semanticClass) killed += 1;
    else failures.push(`semantic mutant ${semanticClass} of ${subject.id} was not killed by exactly its own check (${failed.join(", ") || "none"})`);
  }
}

if (failures.length) { for (const failure of failures) console.error(failure); process.exit(1); }
console.log(JSON.stringify({
  status: "PASS",
  replay,
  subjects: receipt.subjects.map((subject) => ({ id: subject.id, runtime: subject.runtimeTemplate.sha256, bytes: subject.runtimeTemplate.bytes })),
  staleEvidence,
  skippedReceipts,
  verifierMutationValidation: { killed, required },
}, null, 2));
