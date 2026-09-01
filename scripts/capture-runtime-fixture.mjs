import { createHash } from "node:crypto";
import { execFileSync, spawn } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { resolvePinnedSolc } from "./lib/resolve-pinned-solc.mjs";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const wslRoot = `/mnt/${repositoryRoot[0].toLowerCase()}${repositoryRoot.slice(2).replaceAll("\\", "/")}`;
const outputArgument = process.argv.find((argument) => argument.startsWith("--output-root="));
const evidenceRoot = outputArgument
  ? resolve(repositoryRoot, outputArgument.slice("--output-root=".length))
  : join(repositoryRoot, "evidence", "end-to-end-refinement", "runtime-binding");
if (!evidenceRoot.startsWith(`${repositoryRoot}${sep}`)) throw new Error("runtime fixture output root escaped repository");
const resolvedRoot = join(evidenceRoot, "resolved");
const dependencyLock = JSON.parse(readFileSync(join(repositoryRoot, "formal", "kevm", "dependencies.lock.json"), "utf8"));
const pinnedSolc = resolvePinnedSolc(dependencyLock.components.solc);
const compilerManifest = JSON.parse(readFileSync(join(evidenceRoot, "manifest.json"), "utf8"));
const rpcUrl = "http://127.0.0.1:18547";
const privateKey = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
const deployer = "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266";
const chainId = 31337;
const genesisTimestamp = 1_700_000_000;
const supply = "1000000000000000000000000";

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function repoPath(path) {
  return relative(repositoryRoot, path).split(sep).join("/");
}

function stable(value) {
  if (Array.isArray(value)) return value.map(stable);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stable(value[key])]));
  }
  return value;
}

function writeJson(path, value) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, `${JSON.stringify(stable(value), null, 2)}\n`, "utf8");
}

function wsl(args, options = {}) {
  return execFileSync("wsl.exe", ["-d", "Ubuntu", "-e", ...args], {
    encoding: "utf8",
    maxBuffer: 128 * 1024 * 1024,
    stdio: ["pipe", "pipe", "pipe"],
    ...options,
  }).trim();
}

function cast(args, options = {}) {
  return wsl(["cast", ...args], options);
}

function parseJsonOutput(output) {
  const start = output.indexOf("{");
  const end = output.lastIndexOf("}");
  if (start < 0 || end < start) throw new Error(`JSON object missing from output: ${output}`);
  return JSON.parse(output.slice(start, end + 1));
}

function normalizeHex(value) {
  const hex = value.startsWith("0x") ? value.slice(2) : value;
  if (!/^[0-9a-fA-F]*$/.test(hex) || hex.length % 2 !== 0) throw new Error("invalid hex");
  return hex.toLowerCase();
}

function keccakHex(hex) {
  const value = cast(["keccak"], { input: `0x${normalizeHex(hex)}` });
  if (!/^0x[0-9a-f]{64}$/.test(value)) throw new Error(`bad Keccak output: ${value}`);
  return value;
}

function keccakUtf8(value) {
  const result = cast(["keccak"], { input: value });
  if (!/^0x[0-9a-f]{64}$/.test(result)) throw new Error(`bad Keccak output: ${result}`);
  return result;
}

function waitForAnvil(server) {
  for (let attempt = 0; attempt < 80; attempt += 1) {
    if (server.exitCode !== null) throw new Error(`anvil exited early with ${server.exitCode}`);
    try {
      if (cast(["block-number", "--rpc-url", rpcUrl]) === "0") return;
    } catch {
      // The local RPC is still starting.
    }
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 100);
  }
  throw new Error("timed out waiting for local Anvil");
}

function compilerBundle(bundleId) {
  const output = JSON.parse(readFileSync(join(evidenceRoot, bundleId, "standard-json-output.json"), "utf8"));
  const bridge = JSON.parse(readFileSync(join(evidenceRoot, bundleId, "bridge-artifacts.json"), "utf8"));
  return { output, bridge: Object.fromEntries(bridge.map((entry) => [entry.id, entry])) };
}

const compiler = {
  native: compilerBundle("native"),
  "verified-profile": compilerBundle("verified-profile"),
};

function compilerContract(bundleId, id) {
  const split = id.lastIndexOf(":");
  const source = id.slice(0, split);
  const contract = id.slice(split + 1);
  const output = compiler[bundleId].output.contracts?.[source]?.[contract];
  if (!output) throw new Error(`compiler subject missing: ${id}`);
  return output;
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
      if (found.has(String(node.id))) throw new Error(`duplicate immutable AST id: ${node.id}`);
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
  for (const [sourcePath, source] of Object.entries(compiler[bundleId].output.sources)) {
    walk(source.ast, sourcePath);
  }
  return found;
}

const declarations = {
  native: immutableDeclarations("native"),
  "verified-profile": immutableDeclarations("verified-profile"),
};

function encodeWord(value) {
  if (typeof value === "string" && /^0x[0-9a-fA-F]{40}$/.test(value)) return value.slice(2).toLowerCase().padStart(64, "0");
  if (typeof value === "string" && /^0x[0-9a-fA-F]{64}$/.test(value)) return value.slice(2).toLowerCase();
  const integer = BigInt(value);
  if (integer < 0n || integer >= 2n ** 256n) throw new Error(`word out of range: ${value}`);
  return integer.toString(16).padStart(64, "0");
}

function patchRuntime(bundleId, id, values) {
  const contract = compilerContract(bundleId, id);
  const template = normalizeHex(contract.evm.deployedBytecode.object);
  const patched = Buffer.from(template, "hex");
  const references = contract.evm.deployedBytecode.immutableReferences ?? {};
  const resolved = [];
  const occupied = new Set();
  for (const [astId, locations] of Object.entries(references)) {
    const declaration = declarations[bundleId].get(astId);
    if (!declaration) throw new Error(`immutable declaration missing for ${id}:${astId}`);
    if (!(declaration.name in values)) throw new Error(`immutable value missing for ${id}:${declaration.name}`);
    const word = Buffer.from(encodeWord(values[declaration.name]), "hex");
    for (const location of locations) {
      if (location.length !== 32 || location.start < 0 || location.start + 32 > patched.length) {
        throw new Error(`invalid immutable location for ${id}:${declaration.name}`);
      }
      for (let index = location.start; index < location.start + 32; index += 1) {
        if (occupied.has(index)) throw new Error(`overlapping immutable location for ${id}`);
        occupied.add(index);
      }
      if (patched.subarray(location.start, location.start + 32).some((byte) => byte !== 0)) {
        throw new Error(`immutable template location is not zero-filled for ${id}:${declaration.name}`);
      }
      word.copy(patched, location.start);
    }
    resolved.push({ ...declaration, value: values[declaration.name], encodedWord: `0x${word.toString("hex")}`, locations });
  }
  return { bytes: patched, declarations: resolved };
}

const deployments = [];
function deploy({ label, bundleId, id, constructorSignature, constructorArgs, immutableValues }) {
  const nonce = Number(cast(["nonce", deployer, "--rpc-url", rpcUrl]));
  const computedAddressOutput = cast(["compute-address", deployer, "--nonce", String(nonce)]).toLowerCase();
  const expectedAddress = computedAddressOutput.match(/0x[0-9a-f]{40}/)?.[0];
  if (!expectedAddress) throw new Error(`could not parse CREATE address: ${computedAddressOutput}`);
  const args = [
    "forge", "create",
    "--root", wslRoot,
    "--rpc-url", rpcUrl,
    "--private-key", privateKey,
    "--broadcast",
    "--json",
    "--offline",
    "--use", pinnedSolc.binaryPath,
    id,
  ];
  if (constructorArgs.length !== 0) args.push("--constructor-args", ...constructorArgs.map(String));
  const started = process.hrtime.bigint();
  const creation = parseJsonOutput(wsl(args));
  const elapsedWallMs = Math.round(Number(process.hrtime.bigint() - started) / 1_000_000);
  const address = creation.deployedTo.toLowerCase();
  if (address !== expectedAddress) throw new Error(`CREATE address mismatch for ${label}: ${address} != ${expectedAddress}`);
  const transactionHash = creation.transactionHash;
  const transaction = parseJsonOutput(cast(["rpc", "--rpc-url", rpcUrl, "eth_getTransactionByHash", transactionHash]));
  const receipt = parseJsonOutput(cast(["receipt", transactionHash, "--rpc-url", rpcUrl, "--json"]));
  const runtimeHex = normalizeHex(cast(["code", address, "--rpc-url", rpcUrl]));
  const compilerOutput = compilerContract(bundleId, id);
  const creationTemplate = normalizeHex(compilerOutput.evm.bytecode.object);
  const creationInput = normalizeHex(transaction.input);
  if (!creationInput.startsWith(creationTemplate)) throw new Error(`creation input prefix mismatch for ${label}`);
  const patched = patchRuntime(bundleId, id, immutableValues);
  if (runtimeHex !== patched.bytes.toString("hex")) throw new Error(`constructor runtime does not match pure patcher for ${label}`);
  const runtimePath = join(resolvedRoot, bundleId, `${label}.hex`);
  mkdirSync(dirname(runtimePath), { recursive: true });
  writeFileSync(runtimePath, `0x${runtimeHex}\n`, "utf8");
  const runtimeBytes = Buffer.from(runtimeHex, "hex");
  const argsHex = creationInput.slice(creationTemplate.length);
  const record = {
    sequence: deployments.length,
    label,
    bundleId,
    subjectId: id,
    deployer,
    deployerNonce: nonce,
    expectedAddress,
    address,
    transactionHash,
    blockNumber: Number(BigInt(receipt.blockNumber)),
    gasUsed: Number(BigInt(receipt.gasUsed)),
    status: receipt.status,
    elapsedWallMs,
    constructor: {
      signature: constructorSignature,
      typedArguments: constructorArgs.map(String),
      encodedArguments: `0x${argsHex}`,
      encodedArgumentsSha256: sha256(Buffer.from(argsHex, "hex")),
      creationInputSha256: sha256(Buffer.from(creationInput, "hex")),
      creationInputKeccak256: keccakHex(creationInput),
    },
    runtime: {
      path: repoPath(runtimePath),
      textFileSha256: sha256(readFileSync(runtimePath)),
      byteLength: runtimeBytes.length,
      sha256: sha256(runtimeBytes),
      keccak256: keccakHex(runtimeHex),
      eip170MarginBytes: 24_576 - runtimeBytes.length,
    },
    immutablePatch: {
      declarationCount: patched.declarations.length,
      declarations: patched.declarations,
      patchedSha256: sha256(patched.bytes),
      ethGetCodeSha256: sha256(runtimeBytes),
      exactMatch: true,
    },
  };
  deployments.push(record);
  return record;
}

function send(address, signature, args = []) {
  const result = parseJsonOutput(cast([
    "send", address, signature, ...args.map(String),
    "--rpc-url", rpcUrl,
    "--private-key", privateKey,
    "--json",
  ]));
  return {
    transactionHash: result.transactionHash,
    blockNumber: Number(BigInt(result.blockNumber)),
    gasUsed: Number(BigInt(result.gasUsed)),
    status: result.status,
  };
}

try {
  try {
    cast(["block-number", "--rpc-url", rpcUrl]);
    throw new Error(`local fixture port is already in use: ${rpcUrl}`);
  } catch (error) {
    if (String(error.message).includes("already in use")) throw error;
  }

  const anvilVersion = wsl(["anvil", "--version"]);
  const server = spawn("wsl.exe", [
    "-d", "Ubuntu", "-e", "anvil",
    "--silent",
    "--port", "18547",
    "--chain-id", String(chainId),
    "--hardfork", "cancun",
    "--timestamp", String(genesisTimestamp),
  ], { windowsHide: true, stdio: ["ignore", "pipe", "pipe"] });
  let serverStderr = "";
  server.stderr.on("data", (chunk) => { serverStderr += chunk.toString(); });
  try {
    waitForAnvil(server);
    const authorityRef = keccakUtf8("AUTHORITY");
    const profileAuthorityRef = keccakUtf8("ERC3643-AUTHORITY");
    const config = keccakUtf8("CONFIG-V1");
    const schema = keccakUtf8("SCHEMA-V1");

    const dependency = deploy({
      label: "MockBoundDependency",
      bundleId: "native",
      id: "implementation/test/mocks/MockBoundDependency.sol:MockBoundDependency",
      constructorSignature: "constructor(uint8,bytes32)",
      constructorArgs: ["0", config],
      immutableValues: { mode: "0", config },
    });
    const native = deploy({
      label: "TrustToken",
      bundleId: "native",
      id: "implementation/src/TrustToken.sol:TrustToken",
      constructorSignature:
        "constructor(string,string,uint8,address,address,uint256,bytes32,address,address,address,address,address,bytes32)",
      constructorArgs: [
        "ERC-TRUST Reference", "TRUST", "18", deployer, deployer, supply, authorityRef, deployer,
        dependency.address, dependency.address, dependency.address, dependency.address, schema,
      ],
      immutableValues: { decimals: "18", governor: deployer },
    });

    const identity = deploy({
      label: "MockERC3643IdentityRegistry",
      bundleId: "verified-profile",
      id: "implementation/test/mocks/MockERC3643Dependencies.sol:MockERC3643IdentityRegistry",
      constructorSignature: "constructor()",
      constructorArgs: [],
      immutableValues: {},
    });
    const compliance = deploy({
      label: "MockERC3643Compliance",
      bundleId: "verified-profile",
      id: "implementation/test/mocks/MockERC3643Dependencies.sol:MockERC3643Compliance",
      constructorSignature: "constructor()",
      constructorArgs: [],
      immutableValues: {},
    });
    const token = deploy({
      label: "MockERC3643Token",
      bundleId: "verified-profile",
      id: "implementation/test/mocks/MockERC3643Token.sol:MockERC3643Token",
      constructorSignature: "constructor(address,address,uint256)",
      constructorArgs: [identity.address, compliance.address, supply],
      immutableValues: { identityRegistry: identity.address, compliance: compliance.address },
    });
    const tokenCodeId = cast(["codehash", token.address, "--rpc-url", rpcUrl]);
    const governor = deploy({
      label: "ProfileGovernor",
      bundleId: "verified-profile",
      id: "implementation/src/profiles/ProfileGovernor.sol:ProfileGovernor",
      constructorSignature: "constructor(address,address,address,address,bytes32)",
      constructorArgs: [token.address, identity.address, compliance.address, deployer, tokenCodeId],
      immutableValues: {
        token: token.address,
        identityRegistry: identity.address,
        compliance: compliance.address,
        bootstrapAuthority: deployer,
        expectedTokenCodeId: tokenCodeId,
      },
    });
    const adapter = deploy({
      label: "ERC3643TrustAdapter",
      bundleId: "verified-profile",
      id: "implementation/src/profiles/ERC3643TrustAdapter.sol:ERC3643TrustAdapter",
      constructorSignature: "constructor(address,address,bytes32,uint64)",
      constructorArgs: [governor.address, deployer, profileAuthorityRef, "1"],
      immutableValues: {
        profileGovernor: governor.address,
        token: token.address,
        _tokenView: token.address,
        authority: deployer,
        authorityRef: profileAuthorityRef,
        authorityEpoch: "1",
      },
    });

    const topologyTransactions = [
      { operation: "setExclusiveAgent", ...send(token.address, "setExclusiveAgent(address)", [adapter.address]) },
      { operation: "transferOwnership", ...send(token.address, "transferOwnership(address)", [governor.address]) },
      { operation: "seal", ...send(governor.address, "seal(address)", [adapter.address]) },
      { operation: "verifyDeployer", ...send(identity.address, "setVerified(address,bool)", [deployer, "true"]) },
      { operation: "verifyAdapter", ...send(identity.address, "setVerified(address,bool)", [adapter.address, "true"]) },
    ];

    const sealedBinding = cast(["call", governor.address, "sealedBinding()(bytes32)", "--rpc-url", rpcUrl]);
    const topologySealed = cast(["call", governor.address, "topologySealed()(bool)", "--rpc-url", rpcUrl]);
    const exclusiveAgent = cast(["call", token.address, "exclusiveAgent()(address)", "--rpc-url", rpcUrl]).toLowerCase();
    const latestBlock = parseJsonOutput(cast(["rpc", "--rpc-url", rpcUrl, "eth_getBlockByNumber", "latest", "false"]));

    const fixture = {
      schemaVersion: 1,
      claimBoundary:
        "Deterministic local constructor execution and runtime resolution only; no live deployment or KEVM theorem is claimed.",
      compilerBinding: {
        manifestPath: "evidence/end-to-end-refinement/runtime-binding/manifest.json",
        manifestSha256: sha256(readFileSync(join(evidenceRoot, "manifest.json"))),
        deterministicRootSha256: compilerManifest.deterministicRootSha256,
      },
      chain: {
        rpcScope: "ephemeral localhost only",
        chainId,
        hardfork: "cancun",
        genesisTimestamp,
        latestBlockNumber: Number(BigInt(latestBlock.number)),
        latestBlockTimestamp: Number(BigInt(latestBlock.timestamp)),
        latestBlockHash: latestBlock.hash,
        latestStateRoot: latestBlock.stateRoot,
      },
      tools: {
        anvilVersion,
        forgeVersion: dependencyLock.components.forge,
        solc: dependencyLock.components.solc,
      },
      deployer: { address: deployer, privateKeySource: "Foundry public deterministic local test key" },
      deployments,
      topologyTransactions,
      topologyChecks: {
        tokenCodeId,
        sealedBinding,
        topologySealed,
        exclusiveAgent,
        exclusiveAgentMatchesAdapter: exclusiveAgent === adapter.address,
        nativeEndpoint: native.address,
        nativeDependency: dependency.address,
        profileEndpoint: adapter.address,
      },
      serverStderr,
    };
    const deterministicDeployments = fixture.deployments.map(({ elapsedWallMs: _elapsedWallMs, ...entry }) => entry);
    const {
      latestBlockHash: _latestBlockHash,
      latestBlockTimestamp: _latestBlockTimestamp,
      ...deterministicChain
    } = fixture.chain;
    fixture.deterministicRootSha256 = sha256(Buffer.from(JSON.stringify(stable({
      chain: deterministicChain,
      deployments: deterministicDeployments,
      topologyTransactions: fixture.topologyTransactions,
      topologyChecks: fixture.topologyChecks,
    })), "utf8"));
    const fixturePath = join(resolvedRoot, "fixture.json");
    writeJson(fixturePath, fixture);
    console.log(JSON.stringify({
      status: "PASS",
      fixture: repoPath(fixturePath),
      fixtureSha256: sha256(readFileSync(fixturePath)),
      deterministicRootSha256: fixture.deterministicRootSha256,
      deploymentCount: deployments.length,
      topologyTransactionCount: topologyTransactions.length,
      resolvedRuntimeExactMatches: deployments.filter((entry) => entry.immutablePatch.exactMatch).length,
    }, null, 2));
  } finally {
    server.kill();
  }
} catch (error) {
  console.error(error.stack ?? String(error));
  process.exitCode = 1;
}
