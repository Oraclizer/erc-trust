// Historical candidate 2 fixture verifier. The kernel v2 successor uses verify-runtime-binding-v3.mjs.

import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const evidenceRoot = join(repositoryRoot, "evidence", "end-to-end-refinement", "runtime-binding");
const fixturePath = join(evidenceRoot, "resolved", "fixture.json");
const fixture = JSON.parse(readFileSync(fixturePath, "utf8"));
const compilerManifestPath = join(evidenceRoot, "manifest.json");
const compilerManifest = JSON.parse(readFileSync(compilerManifestPath, "utf8"));

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function stable(value) {
  if (Array.isArray(value)) return value.map(stable);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stable(value[key])]));
  }
  return value;
}

function absolute(repoPath) {
  return join(repositoryRoot, ...repoPath.split("/"));
}

function normalizeHex(value) {
  const hex = value.startsWith("0x") ? value.slice(2) : value;
  if (!/^[0-9a-fA-F]*$/.test(hex) || hex.length % 2 !== 0) throw new Error("invalid hex");
  return hex.toLowerCase();
}

function keccak(hex) {
  const result = execFileSync("wsl.exe", ["-d", "Ubuntu", "-e", "cast", "keccak"], {
    input: `0x${normalizeHex(hex)}`,
    encoding: "utf8",
    stdio: ["pipe", "pipe", "pipe"],
  }).trim();
  if (!/^0x[0-9a-f]{64}$/.test(result)) throw new Error(`bad Keccak output: ${result}`);
  return result;
}

function encodeWord(value) {
  if (/^0x[0-9a-fA-F]{40}$/.test(value)) return value.slice(2).toLowerCase().padStart(64, "0");
  if (/^0x[0-9a-fA-F]{64}$/.test(value)) return value.slice(2).toLowerCase();
  const integer = BigInt(value);
  if (integer < 0n || integer >= 2n ** 256n) throw new Error(`word out of range: ${value}`);
  return integer.toString(16).padStart(64, "0");
}

function bundleOutput(bundleId) {
  return JSON.parse(readFileSync(join(evidenceRoot, bundleId, "standard-json-output.json"), "utf8"));
}

const outputs = {
  native: bundleOutput("native"),
  "verified-profile": bundleOutput("verified-profile"),
};

function contractOutput(bundleId, subjectId) {
  const separator = subjectId.lastIndexOf(":");
  const source = subjectId.slice(0, separator);
  const contract = subjectId.slice(separator + 1);
  const output = outputs[bundleId].contracts?.[source]?.[contract];
  if (!output) throw new Error(`unknown compiler subject: ${subjectId}`);
  return output;
}

function immutableMap(bundleId) {
  const found = new Map();
  const visit = (value, sourcePath) => {
    if (Array.isArray(value)) {
      for (const item of value) visit(item, sourcePath);
      return;
    }
    if (value === null || typeof value !== "object") return;
    if (value.nodeType === "VariableDeclaration" && value.stateVariable && value.mutability === "immutable") {
      found.set(String(value.id), {
        astId: value.id,
        sourcePath,
        name: value.name,
        canonicalType: value.typeDescriptions?.typeString,
        sourceSpan: value.src,
      });
    }
    for (const child of Object.values(value)) visit(child, sourcePath);
  };
  for (const [sourcePath, output] of Object.entries(outputs[bundleId].sources)) visit(output.ast, sourcePath);
  return found;
}

const immutables = { native: immutableMap("native"), "verified-profile": immutableMap("verified-profile") };

if (fixture.schemaVersion !== 1) throw new Error(`unsupported fixture schema: ${fixture.schemaVersion}`);
if (fixture.compilerBinding.manifestSha256 !== sha256(readFileSync(compilerManifestPath))) {
  throw new Error("compiler manifest hash mismatch");
}
if (fixture.compilerBinding.deterministicRootSha256 !== compilerManifest.deterministicRootSha256) {
  throw new Error("compiler deterministic root mismatch");
}
if (fixture.deployments.length !== 7) throw new Error(`unexpected deployment count: ${fixture.deployments.length}`);

const seenAddresses = new Set();
const seenTransactions = new Set();
for (const [index, deployment] of fixture.deployments.entries()) {
  if (deployment.sequence !== index) throw new Error(`deployment sequence mismatch: ${deployment.label}`);
  if (deployment.address !== deployment.expectedAddress) throw new Error(`CREATE address mismatch: ${deployment.label}`);
  if (seenAddresses.has(deployment.address)) throw new Error(`duplicate deployed address: ${deployment.address}`);
  if (seenTransactions.has(deployment.transactionHash)) throw new Error(`duplicate deployment transaction: ${deployment.transactionHash}`);
  seenAddresses.add(deployment.address);
  seenTransactions.add(deployment.transactionHash);
  if (deployment.status !== "0x1") throw new Error(`failed deployment receipt: ${deployment.label}`);

  const compiler = contractOutput(deployment.bundleId, deployment.subjectId);
  const template = Buffer.from(normalizeHex(compiler.evm.deployedBytecode.object), "hex");
  const patched = Buffer.from(template);
  const references = compiler.evm.deployedBytecode.immutableReferences ?? {};
  const recorded = new Map(deployment.immutablePatch.declarations.map((entry) => [String(entry.astId), entry]));
  if (recorded.size !== Object.keys(references).length) throw new Error(`immutable count mismatch: ${deployment.label}`);
  const occupied = new Set();
  for (const [astId, locations] of Object.entries(references)) {
    const declaration = immutables[deployment.bundleId].get(astId);
    const evidence = recorded.get(astId);
    if (!declaration || !evidence) throw new Error(`immutable evidence missing: ${deployment.label}:${astId}`);
    if (JSON.stringify(stable(declaration)) !== JSON.stringify(stable({
      astId: evidence.astId,
      sourcePath: evidence.sourcePath,
      name: evidence.name,
      canonicalType: evidence.canonicalType,
      sourceSpan: evidence.sourceSpan,
    }))) throw new Error(`immutable declaration mismatch: ${deployment.label}:${astId}`);
    const wordHex = encodeWord(String(evidence.value));
    if (`0x${wordHex}` !== evidence.encodedWord) throw new Error(`immutable word mismatch: ${deployment.label}:${evidence.name}`);
    const word = Buffer.from(wordHex, "hex");
    for (const location of locations) {
      if (location.length !== 32 || location.start + 32 > patched.length) throw new Error("immutable bounds failure");
      for (let offset = location.start; offset < location.start + 32; offset += 1) {
        if (occupied.has(offset)) throw new Error(`immutable overlap: ${deployment.label}`);
        occupied.add(offset);
      }
      if (patched.subarray(location.start, location.start + 32).some((byte) => byte !== 0)) {
        throw new Error(`nonzero immutable template span: ${deployment.label}`);
      }
      word.copy(patched, location.start);
    }
  }

  const runtimeText = readFileSync(absolute(deployment.runtime.path), "utf8");
  const runtimeHex = normalizeHex(runtimeText.trim());
  const runtime = Buffer.from(runtimeHex, "hex");
  if (sha256(Buffer.from(runtimeText, "utf8")) !== deployment.runtime.textFileSha256) {
    throw new Error(`runtime text hash mismatch: ${deployment.label}`);
  }
  if (
    runtime.length !== deployment.runtime.byteLength
    || sha256(runtime) !== deployment.runtime.sha256
    || keccak(runtimeHex) !== deployment.runtime.keccak256
    || 24_576 - runtime.length !== deployment.runtime.eip170MarginBytes
  ) throw new Error(`resolved runtime identity mismatch: ${deployment.label}`);
  if (!patched.equals(runtime)) throw new Error(`pure patch reverse check failed: ${deployment.label}`);
  if (
    deployment.immutablePatch.patchedSha256 !== sha256(patched)
    || deployment.immutablePatch.ethGetCodeSha256 !== sha256(runtime)
    || !deployment.immutablePatch.exactMatch
  ) throw new Error(`patch evidence mismatch: ${deployment.label}`);

  const creation = normalizeHex(compiler.evm.bytecode.object);
  const encodedArguments = normalizeHex(deployment.constructor.encodedArguments);
  const creationInput = `${creation}${encodedArguments}`;
  if (
    sha256(Buffer.from(encodedArguments, "hex")) !== deployment.constructor.encodedArgumentsSha256
    || sha256(Buffer.from(creationInput, "hex")) !== deployment.constructor.creationInputSha256
    || keccak(creationInput) !== deployment.constructor.creationInputKeccak256
  ) throw new Error(`constructor input mismatch: ${deployment.label}`);
}

if (fixture.topologyTransactions.length !== 5) throw new Error("topology transaction count mismatch");
for (const transaction of fixture.topologyTransactions) {
  if (transaction.status !== "0x1") throw new Error(`topology transaction failed: ${transaction.operation}`);
  if (seenTransactions.has(transaction.transactionHash)) throw new Error(`duplicate topology transaction: ${transaction.operation}`);
  seenTransactions.add(transaction.transactionHash);
}
if (!fixture.topologyChecks.exclusiveAgentMatchesAdapter || fixture.topologyChecks.topologySealed !== "true") {
  throw new Error("sealed profile topology check failed");
}

const deterministicDeployments = fixture.deployments.map(({ elapsedWallMs: _elapsedWallMs, ...entry }) => entry);
const {
  latestBlockHash: _latestBlockHash,
  latestBlockTimestamp: _latestBlockTimestamp,
  ...deterministicChain
} = fixture.chain;
const deterministicRoot = sha256(Buffer.from(JSON.stringify(stable({
  chain: deterministicChain,
  deployments: deterministicDeployments,
  topologyTransactions: fixture.topologyTransactions,
  topologyChecks: fixture.topologyChecks,
})), "utf8"));
if (deterministicRoot !== fixture.deterministicRootSha256) throw new Error("fixture deterministic root mismatch");

console.log(JSON.stringify({
  status: "PASS",
  deterministicRootSha256: deterministicRoot,
  deploymentCount: fixture.deployments.length,
  resolvedRuntimeExactMatches: fixture.deployments.filter((entry) => entry.immutablePatch.exactMatch).length,
  latestStateRoot: fixture.chain.latestStateRoot,
}, null, 2));
