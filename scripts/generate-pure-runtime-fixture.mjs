// SPDX-License-Identifier: BSD-3-Clause
// Historical candidate 2 fixture tooling. The kernel v2 successor uses the v3 runtime-binding tools.

import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { getCreateAddress, keccak256 } from "../sdk/node_modules/ethers/lib.esm/index.js";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const checkMode = process.argv.includes("--check");
const currentRoot = join(repositoryRoot, "evidence", "end-to-end-refinement", "runtime-binding-current-v2");
const historicalFixturePath = join(
  repositoryRoot,
  "evidence",
  "end-to-end-refinement",
  "runtime-binding",
  "resolved",
  "fixture.json",
);
const manifestPath = join(currentRoot, "manifest.json");
const outputPath = join(currentRoot, "resolved", "fixture-pure-v1.json");

const manifestBytes = readFileSync(manifestPath);
const manifest = JSON.parse(manifestBytes.toString("utf8"));
const historicalBytes = readFileSync(historicalFixturePath);
const historical = JSON.parse(historicalBytes.toString("utf8"));
if (historical.deployments.length !== 7 || historical.deployments.some((entry) => !entry.immutablePatch.exactMatch)) {
  throw new Error("historical seven-subject runtime cross-check is incomplete");
}

const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");
const normalizeHex = (value) => {
  const hex = value.startsWith("0x") ? value.slice(2) : value;
  if (!/^[0-9a-fA-F]*$/.test(hex) || hex.length % 2 !== 0) throw new Error("invalid hex");
  return hex.toLowerCase();
};
const stable = (value) => {
  if (Array.isArray(value)) return value.map(stable);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stable(value[key])]));
  }
  return value;
};
const writeJson = (path, value) => {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, `${JSON.stringify(stable(value), null, 2)}\n`, "utf8");
};
const repoPath = (path) => relative(repositoryRoot, path).split(sep).join("/");

const compilerBundles = Object.fromEntries(manifest.bundles.map((bundle) => {
  const outputFile = bundle.files.find((file) => file.path.endsWith("standard-json-output.json"));
  if (!outputFile) throw new Error(`compiler output missing: ${bundle.id}`);
  return [bundle.id, JSON.parse(readFileSync(join(repositoryRoot, outputFile.path), "utf8"))];
}));

function compilerContract(bundleId, id) {
  const separator = id.lastIndexOf(":");
  const source = id.slice(0, separator);
  const contract = id.slice(separator + 1);
  const output = compilerBundles[bundleId].contracts?.[source]?.[contract];
  if (!output) throw new Error(`compiler subject missing: ${id}`);
  return { output, source, contract };
}

function immutableDeclarations(bundleId) {
  const found = new Map();
  const walk = (node, sourcePath) => {
    if (Array.isArray(node)) {
      for (const child of node) walk(child, sourcePath);
      return;
    }
    if (node === null || typeof node !== "object") return;
    if (node.nodeType === "VariableDeclaration" && node.mutability === "immutable" && node.stateVariable) {
      found.set(String(node.id), {
        astId: node.id,
        sourcePath,
        name: node.name,
        canonicalType: node.typeDescriptions?.typeString,
        sourceSpan: node.src,
      });
    }
    for (const value of Object.values(node)) walk(value, sourcePath);
  };
  for (const [sourcePath, source] of Object.entries(compilerBundles[bundleId].sources)) walk(source.ast, sourcePath);
  return found;
}

const declarations = {
  native: immutableDeclarations("native"),
  "verified-profile": immutableDeclarations("verified-profile"),
};

function encodeWord(value) {
  if (typeof value === "string" && /^0x[0-9a-fA-F]{40}$/.test(value)) {
    return value.slice(2).toLowerCase().padStart(64, "0");
  }
  if (typeof value === "string" && /^0x[0-9a-fA-F]{64}$/.test(value)) return value.slice(2).toLowerCase();
  const integer = BigInt(value);
  if (integer < 0n || integer >= 2n ** 256n) throw new Error(`word out of range: ${value}`);
  return integer.toString(16).padStart(64, "0");
}

function patchRuntime(bundleId, id, values) {
  const { output } = compilerContract(bundleId, id);
  const template = normalizeHex(output.evm.deployedBytecode.object);
  const patched = Buffer.from(template, "hex");
  const references = output.evm.deployedBytecode.immutableReferences ?? {};
  const resolved = [];
  const occupied = new Set();
  for (const [astId, locations] of Object.entries(references)) {
    const declaration = declarations[bundleId].get(astId);
    if (!declaration) throw new Error(`immutable declaration missing: ${id}:${astId}`);
    if (!(declaration.name in values)) throw new Error(`immutable value missing: ${id}:${declaration.name}`);
    const word = Buffer.from(encodeWord(values[declaration.name]), "hex");
    for (const location of locations) {
      if (location.length !== 32 || location.start < 0 || location.start + 32 > patched.length) {
        throw new Error(`invalid immutable location: ${id}:${declaration.name}`);
      }
      for (let index = location.start; index < location.start + 32; index += 1) {
        if (occupied.has(index)) throw new Error(`overlapping immutable location: ${id}`);
        occupied.add(index);
      }
      if (patched.subarray(location.start, location.start + 32).some((byte) => byte !== 0)) {
        throw new Error(`immutable template location is not zero-filled: ${id}:${declaration.name}`);
      }
      word.copy(patched, location.start);
    }
    resolved.push({ ...declaration, value: values[declaration.name], encodedWord: `0x${word.toString("hex")}`, locations });
  }
  if (Object.keys(values).some((name) => !resolved.some((entry) => entry.name === name))) {
    throw new Error(`extra immutable value supplied: ${id}`);
  }
  return { bytes: patched, declarations: resolved };
}

const deployer = historical.deployer.address;
const predictedAddresses = historical.deployments.map((entry) => {
  const predictedAddress = getCreateAddress({ from: deployer, nonce: entry.deployerNonce }).toLowerCase();
  if (predictedAddress !== entry.address.toLowerCase()) throw new Error(`historical CREATE schedule drift: ${entry.label}`);
  return [entry.label, predictedAddress];
});
const addressByLabel = Object.fromEntries(predictedAddresses);

const valuesByLabel = Object.fromEntries(historical.deployments.map((entry) => [
  entry.label,
  Object.fromEntries(entry.immutablePatch.declarations.map((declaration) => [declaration.name, declaration.value])),
]));
valuesByLabel.MockERC3643Token.identityRegistry = addressByLabel.MockERC3643IdentityRegistry;
valuesByLabel.MockERC3643Token.compliance = addressByLabel.MockERC3643Compliance;

const tokenEntry = historical.deployments.find((entry) => entry.label === "MockERC3643Token");
const tokenPatched = patchRuntime(tokenEntry.bundleId, tokenEntry.subjectId, valuesByLabel.MockERC3643Token);
const tokenCodeId = keccak256(`0x${tokenPatched.bytes.toString("hex")}`);
Object.assign(valuesByLabel.ProfileGovernor, {
  token: addressByLabel.MockERC3643Token,
  identityRegistry: addressByLabel.MockERC3643IdentityRegistry,
  compliance: addressByLabel.MockERC3643Compliance,
  expectedTokenCodeId: tokenCodeId,
});
Object.assign(valuesByLabel.ERC3643TrustAdapter, {
  profileGovernor: addressByLabel.ProfileGovernor,
  token: addressByLabel.MockERC3643Token,
  _tokenView: addressByLabel.MockERC3643Token,
});

const deployments = historical.deployments.map((entry) => {
  const patched = patchRuntime(entry.bundleId, entry.subjectId, valuesByLabel[entry.label]);
  const runtimePath = join(currentRoot, "resolved", entry.bundleId, `${entry.label}.hex`);
  const runtimeText = `0x${patched.bytes.toString("hex")}\n`;
  if (checkMode) {
    if (!existsSync(runtimePath) || readFileSync(runtimePath, "utf8") !== runtimeText) {
      throw new Error(`resolved runtime drift: ${repoPath(runtimePath)}`);
    }
  } else {
    mkdirSync(dirname(runtimePath), { recursive: true });
    writeFileSync(runtimePath, runtimeText, "utf8");
  }
  return {
    sequence: entry.sequence,
    label: entry.label,
    bundleId: entry.bundleId,
    subjectId: entry.subjectId,
    deployer,
    deployerNonce: entry.deployerNonce,
    predictedAddress: addressByLabel[entry.label],
    runtime: {
      path: repoPath(runtimePath),
      textFileSha256: sha256(Buffer.from(runtimeText, "utf8")),
      byteLength: patched.bytes.length,
      sha256: sha256(patched.bytes),
      keccak256: keccak256(`0x${patched.bytes.toString("hex")}`),
      eip170MarginBytes: 24_576 - patched.bytes.length,
    },
    immutablePatch: {
      declarationCount: patched.declarations.length,
      declarations: patched.declarations,
      pureResolutionPass: true,
    },
  };
});

const fixture = {
  schemaVersion: 1,
  kind: "ERC_TRUST_RUNTIME_FIXTURE_PURE_RESOLUTION_V1",
  status: "PASS_PURE_RUNTIME_RESOLUTION",
  claimBoundary:
    "Deterministic compiler-metadata-derived runtime resolution for the seven named subjects under the pinned solc input, frozen constructor values, predicted CREATE address schedule, and enumerated immutable references. No constructor or transaction execution, eth_getCode observation, deployed-address existence, live topology, KEVM theorem, deployment assurance, or production claim is made.",
  compilerBinding: {
    manifestPath: repoPath(manifestPath),
    manifestSha256: sha256(manifestBytes),
    deterministicRootSha256: manifest.deterministicRootSha256,
  },
  historicalCrossCheck: {
    fixturePath: repoPath(historicalFixturePath),
    fixtureSha256: sha256(historicalBytes),
    exactMatches: 7,
    statement:
      "The same immutable-slot patch procedure matched ephemeral Anvil eth_getCode for all seven historical subjects. This is regression support, not a current constructor-execution replay.",
  },
  deployer,
  deployments,
  topology: {
    tokenCodeId,
    nativeEndpoint: addressByLabel.TrustToken,
    nativeDependency: addressByLabel.MockBoundDependency,
    profileEndpoint: addressByLabel.ERC3643TrustAdapter,
    topologyReplayed: false,
  },
};
fixture.deterministicRootSha256 = sha256(Buffer.from(JSON.stringify(stable({
  compilerBinding: fixture.compilerBinding,
  deployments: fixture.deployments,
  topology: fixture.topology,
})), "utf8"));
const fixtureText = `${JSON.stringify(stable(fixture), null, 2)}\n`;
if (checkMode) {
  if (!existsSync(outputPath) || readFileSync(outputPath, "utf8") !== fixtureText) {
    throw new Error(`pure runtime fixture drift: ${repoPath(outputPath)}`);
  }
} else {
  writeJson(outputPath, fixture);
}
console.log(JSON.stringify({
  status: fixture.status,
  mode: checkMode ? "check" : "write",
  fixture: repoPath(outputPath),
  fixtureSha256: sha256(Buffer.from(fixtureText, "utf8")),
  deterministicRootSha256: fixture.deterministicRootSha256,
  subjectCount: deployments.length,
  nativeRuntimeBytes: deployments.find((entry) => entry.label === "TrustToken").runtime.byteLength,
}, null, 2));
