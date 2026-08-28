import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, posix, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { resolvePinnedSolc } from "./lib/resolve-pinned-solc.mjs";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const evidenceRoot = join(repositoryRoot, "evidence", "end-to-end-refinement", "runtime-binding");
const dependencyLockPath = join(repositoryRoot, "formal", "kevm", "dependencies.lock.json");
const dependencyLock = JSON.parse(readFileSync(dependencyLockPath, "utf8"));
const solc = dependencyLock.components.solc;
const pinnedSolc = resolvePinnedSolc(solc);

const settings = {
  optimizer: { enabled: true, runs: 1 },
  metadata: { useLiteralContent: false, bytecodeHash: "none", appendCBOR: false },
  outputSelection: {
    "*": {
      "": ["ast"],
      "*": [
        "abi",
        "evm.bytecode.object",
        "evm.bytecode.sourceMap",
        "evm.bytecode.linkReferences",
        "evm.deployedBytecode.object",
        "evm.deployedBytecode.sourceMap",
        "evm.deployedBytecode.linkReferences",
        "evm.deployedBytecode.immutableReferences",
        "evm.methodIdentifiers",
        "metadata",
        "storageLayout",
      ],
    },
  },
  evmVersion: "cancun",
  viaIR: true,
  libraries: {},
};

const bundles = [
  {
    id: "native",
    roots: ["implementation/src/TrustToken.sol", "implementation/test/mocks/MockBoundDependency.sol"],
    subjects: [
      {
        source: "implementation/src/TrustToken.sol",
        contract: "TrustToken",
        foundryArtifact: "out/TrustToken.sol/TrustToken.json",
      },
      {
        source: "implementation/test/mocks/MockBoundDependency.sol",
        contract: "MockBoundDependency",
        foundryArtifact: "out/MockBoundDependency.sol/MockBoundDependency.json",
      },
    ],
  },
  {
    id: "verified-profile",
    roots: [
      "implementation/src/profiles/ERC3643TrustAdapter.sol",
      "implementation/src/profiles/ProfileGovernor.sol",
      "implementation/test/mocks/MockERC3643Token.sol",
      "implementation/test/mocks/MockERC3643Dependencies.sol",
    ],
    subjects: [
      {
        source: "implementation/src/profiles/ERC3643TrustAdapter.sol",
        contract: "ERC3643TrustAdapter",
        foundryArtifact: "out/ERC3643TrustAdapter.sol/ERC3643TrustAdapter.json",
      },
      {
        source: "implementation/src/profiles/ProfileGovernor.sol",
        contract: "ProfileGovernor",
        foundryArtifact: "out/ProfileGovernor.sol/ProfileGovernor.json",
      },
      {
        source: "implementation/test/mocks/MockERC3643Token.sol",
        contract: "MockERC3643Token",
        foundryArtifact: "out/MockERC3643Token.sol/MockERC3643Token.json",
      },
      {
        source: "implementation/test/mocks/MockERC3643Dependencies.sol",
        contract: "MockERC3643IdentityRegistry",
        foundryArtifact: "out/MockERC3643Dependencies.sol/MockERC3643IdentityRegistry.json",
      },
      {
        source: "implementation/test/mocks/MockERC3643Dependencies.sol",
        contract: "MockERC3643Compliance",
        foundryArtifact: "out/MockERC3643Dependencies.sol/MockERC3643Compliance.json",
      },
    ],
  },
];

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function readBytes(path) {
  return readFileSync(path);
}

function repoPath(path) {
  return relative(repositoryRoot, path).split(sep).join("/");
}

function absolute(repoRelativePath) {
  const path = resolve(repositoryRoot, ...repoRelativePath.split("/"));
  if (!path.startsWith(`${repositoryRoot}${sep}`)) throw new Error(`path escapes repository: ${repoRelativePath}`);
  return path;
}

function stable(value) {
  if (Array.isArray(value)) return value.map(stable);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stable(value[key])]));
  }
  return value;
}

function stableJson(value) {
  return `${JSON.stringify(stable(value), null, 2)}\n`;
}

function writeJson(path, value) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, stableJson(value), "utf8");
}

function normalizeHex(value) {
  const hex = value.startsWith("0x") ? value.slice(2) : value;
  if (!/^[0-9a-fA-F]*$/.test(hex) || hex.length % 2 !== 0) throw new Error("invalid bytecode hex");
  return hex.toLowerCase();
}

function normalizedAbi(value) {
  return value.map(stable).sort((left, right) => JSON.stringify(left).localeCompare(JSON.stringify(right)));
}

function semanticStorageLayout(layout) {
  const memo = new Map();
  const expand = (typeId) => {
    if (memo.has(typeId)) return memo.get(typeId);
    const source = layout.types[typeId];
    if (!source) throw new Error(`unknown storage-layout type: ${typeId}`);
    const target = {
      encoding: source.encoding,
      label: source.label,
      numberOfBytes: source.numberOfBytes,
    };
    memo.set(typeId, target);
    if (source.key) target.key = expand(source.key);
    if (source.value) target.value = expand(source.value);
    if (source.base) target.base = expand(source.base);
    if (source.members) {
      target.members = source.members.map((member) => ({
        contract: member.contract,
        label: member.label,
        offset: member.offset,
        slot: member.slot,
        type: expand(member.type),
      }));
    }
    return target;
  };
  return layout.storage.map((item) => ({
    contract: item.contract,
    label: item.label,
    offset: item.offset,
    slot: item.slot,
    type: expand(item.type),
  }));
}

function immutablePositions(value) {
  return Object.values(value ?? {}).flat().map(({ start, length }) => ({ start, length }))
    .sort((left, right) => left.start - right.start || left.length - right.length);
}

function keccak256(hex) {
  const result = execFileSync("wsl.exe", ["-d", "Ubuntu", "--", "cast", "keccak"], {
    input: `0x${normalizeHex(hex)}`,
    encoding: "utf8",
    maxBuffer: 4 * 1024 * 1024,
  }).trim();
  if (!/^0x[0-9a-f]{64}$/.test(result)) throw new Error(`unexpected cast keccak output: ${result}`);
  return result;
}

function sourceImports(sourcePath, content) {
  const imports = [];
  const pattern = /\bimport\s+(?:[^"']*?\s+from\s+)?["']([^"']+)["']\s*;/g;
  for (const match of content.matchAll(pattern)) {
    const requested = match[1];
    if (!requested.startsWith(".")) throw new Error(`non-relative import in ${sourcePath}: ${requested}`);
    const resolved = posix.normalize(posix.join(posix.dirname(sourcePath), requested));
    imports.push(resolved);
  }
  return imports;
}

function importClosure(roots) {
  const pending = [...roots];
  const found = new Map();
  while (pending.length !== 0) {
    const sourcePath = pending.pop();
    if (found.has(sourcePath)) continue;
    const path = absolute(sourcePath);
    if (!existsSync(path)) throw new Error(`missing Solidity source: ${sourcePath}`);
    const content = readFileSync(path, "utf8");
    found.set(sourcePath, content);
    pending.push(...sourceImports(sourcePath, content));
  }
  return new Map([...found.entries()].sort(([left], [right]) => left.localeCompare(right)));
}

function exactInput(roots) {
  const sources = {};
  for (const [path, content] of importClosure(roots)) sources[path] = { content };
  return { language: "Solidity", sources, settings };
}

function runSolc(inputText) {
  const started = process.hrtime.bigint();
  const outputText = execFileSync("wsl.exe", ["-d", pinnedSolc.distribution, "-e", pinnedSolc.binaryPath, "--standard-json"], {
    input: inputText,
    encoding: "utf8",
    maxBuffer: 512 * 1024 * 1024,
  });
  const elapsedMs = Number(process.hrtime.bigint() - started) / 1_000_000;
  const output = JSON.parse(outputText);
  const errors = (output.errors ?? []).filter((entry) => entry.severity === "error");
  if (errors.length !== 0) throw new Error(`solc error: ${errors[0].formattedMessage}`);
  return { output, outputText, elapsedMs, version: pinnedSolc.versionOutput };
}

function compilerContract(output, subject) {
  const contract = output.contracts?.[subject.source]?.[subject.contract];
  if (!contract) throw new Error(`compiler output missing ${subject.source}:${subject.contract}`);
  return contract;
}

function foundryCrossCheck(subject, compiler) {
  const artifactPath = absolute(subject.foundryArtifact);
  if (!existsSync(artifactPath)) throw new Error(`missing Foundry artifact: ${subject.foundryArtifact}`);
  const artifact = JSON.parse(readFileSync(artifactPath, "utf8"));
  const checks = {
    abi: JSON.stringify(normalizedAbi(artifact.abi)) === JSON.stringify(normalizedAbi(compiler.abi)),
    storageLayout:
      JSON.stringify(stable(semanticStorageLayout(artifact.storageLayout)))
        === JSON.stringify(stable(semanticStorageLayout(compiler.storageLayout))),
    creationBytecode: normalizeHex(artifact.bytecode.object) === normalizeHex(compiler.evm.bytecode.object),
    runtimeTemplate: normalizeHex(artifact.deployedBytecode.object) === normalizeHex(compiler.evm.deployedBytecode.object),
    methodIdentifiers:
      JSON.stringify(stable(artifact.methodIdentifiers)) === JSON.stringify(stable(compiler.evm.methodIdentifiers)),
    immutableReferences:
      JSON.stringify(immutablePositions(artifact.deployedBytecode.immutableReferences))
        === JSON.stringify(immutablePositions(compiler.evm.deployedBytecode.immutableReferences)),
  };
  if (Object.values(checks).some((value) => !value)) {
    throw new Error(`Foundry cross-check failed for ${subject.source}:${subject.contract}: ${JSON.stringify(checks)}`);
  }
  return { artifactPath: subject.foundryArtifact, artifactSha256: sha256(readBytes(artifactPath)), checks };
}

function subjectBridge(subject, compiler) {
  const runtime = normalizeHex(compiler.evm.deployedBytecode.object);
  const creation = normalizeHex(compiler.evm.bytecode.object);
  const runtimeBytes = Buffer.from(runtime, "hex");
  const creationBytes = Buffer.from(creation, "hex");
  return {
    id: `${subject.source}:${subject.contract}`,
    source: subject.source,
    contract: subject.contract,
    abi: compiler.abi,
    storageLayout: compiler.storageLayout,
    methodIdentifiers: compiler.evm.methodIdentifiers,
    runtimeTemplate: {
      byteLength: runtimeBytes.length,
      sha256: sha256(runtimeBytes),
      keccak256: keccak256(runtime),
      immutableReferences: compiler.evm.deployedBytecode.immutableReferences ?? {},
      linkReferences: compiler.evm.deployedBytecode.linkReferences ?? {},
    },
    creationBytecode: {
      byteLength: creationBytes.length,
      sha256: sha256(creationBytes),
      keccak256: keccak256(creation),
      linkReferences: compiler.evm.bytecode.linkReferences ?? {},
    },
    foundryCrossCheck: foundryCrossCheck(subject, compiler),
  };
}

function git(args) {
  return execFileSync("git", args, { cwd: repositoryRoot, encoding: "utf8" }).trim();
}

mkdirSync(evidenceRoot, { recursive: true });
const manifest = {
  schemaVersion: 2,
  claimBoundary:
    "Exact compiler-input/output and unresolved runtime-template binding. Constructor execution, resolved runtime, KEVM proofs, and end-to-end discharge remain separate evidence.",
  sourceIdentity: {
    branch: git(["branch", "--show-current"]),
    head: git(["rev-parse", "HEAD"]),
    dirty: git(["status", "--porcelain"]).length !== 0,
    foundryTomlSha256: sha256(readBytes(join(repositoryRoot, "foundry.toml"))),
    dependencyLockSha256: sha256(readBytes(dependencyLockPath)),
  },
  compiler: {
    version: solc.version,
    binaryLocator: solc.binaryLocator,
    binarySha256: solc.binarySha256,
    settingsSha256: sha256(Buffer.from(stableJson(settings), "utf8")),
  },
  bundles: [],
};

for (const bundle of bundles) {
  const input = exactInput(bundle.roots);
  const inputText = `${JSON.stringify(input, null, 2)}\n`;
  const run = runSolc(inputText);
  const bundleRoot = join(evidenceRoot, bundle.id);
  const inputPath = join(bundleRoot, "standard-json-input.json");
  const outputPath = join(bundleRoot, "standard-json-output.json");
  const bridgePath = join(bundleRoot, "bridge-artifacts.json");
  const sourceIdentityPath = join(bundleRoot, "source-identities.json");
  const bridge = bundle.subjects.map((subject) => subjectBridge(subject, compilerContract(run.output, subject)));
  const sourceIdentities = Object.entries(input.sources).map(([path, source]) => ({
    path,
    bytes: Buffer.byteLength(source.content),
    sha256: sha256(Buffer.from(source.content, "utf8")),
  }));

  mkdirSync(bundleRoot, { recursive: true });
  writeFileSync(inputPath, inputText, "utf8");
  writeFileSync(outputPath, run.outputText, "utf8");
  writeJson(bridgePath, bridge);
  writeJson(sourceIdentityPath, sourceIdentities);

  const files = [inputPath, outputPath, bridgePath, sourceIdentityPath].map((path) => ({
    path: repoPath(path),
    bytes: statSync(path).size,
    sha256: sha256(readBytes(path)),
  }));
  manifest.bundles.push({
    id: bundle.id,
    roots: bundle.roots,
    sourceCount: Object.keys(input.sources).length,
    subjectCount: bundle.subjects.length,
    subjects: bridge.map(({ id }) => id),
    compilerRun: { elapsedWallMs: Math.round(run.elapsedMs), versionOutput: run.version },
    files,
  });
}

manifest.deterministicRootSha256 = sha256(Buffer.from(
  manifest.bundles.flatMap((bundle) => bundle.files.map((file) => `${file.path}\0${file.sha256}\n`)).join(""),
  "utf8",
));
const manifestPath = join(evidenceRoot, "manifest.json");
writeJson(manifestPath, manifest);
console.log(JSON.stringify({
  status: "PASS",
  manifest: repoPath(manifestPath),
  manifestSha256: sha256(readBytes(manifestPath)),
  deterministicRootSha256: manifest.deterministicRootSha256,
  bundles: manifest.bundles.map(({ id, sourceCount, subjectCount, compilerRun }) => ({
    id,
    sourceCount,
    subjectCount,
    compilerElapsedWallMs: compilerRun.elapsedWallMs,
  })),
}, null, 2));
