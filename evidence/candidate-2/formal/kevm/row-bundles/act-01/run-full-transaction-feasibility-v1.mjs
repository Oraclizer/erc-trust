import { createHash } from "node:crypto";
import { execFileSync, spawn } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { gunzipSync } from "node:zlib";
import { resolvePinnedSolc } from "../../../../scripts/lib/resolve-pinned-solc.mjs";

const repositoryRoot = resolve(import.meta.dirname, "../../../..");
const outputIndex = process.argv.indexOf("--output-root");
const controlIndex = process.argv.indexOf("--external-control-root");
if (outputIndex < 0 || !process.argv[outputIndex + 1] || controlIndex < 0 || !process.argv[controlIndex + 1]) {
  throw new Error("usage: node run-full-transaction-feasibility-v1.mjs --output-root <absolute-new-path> --external-control-root <path> [--port <port>]");
}
const outputRoot = resolve(process.argv[outputIndex + 1]);
const controlRoot = resolve(process.argv[controlIndex + 1]);
if (existsSync(outputRoot)) throw new Error(`output root already exists: ${outputRoot}`);
const portIndex = process.argv.indexOf("--port");
const port = portIndex >= 0 ? Number(process.argv[portIndex + 1]) : 18551;
if (!Number.isInteger(port) || port < 1024 || port > 65535) throw new Error("invalid port");

const rpcUrl = `http://127.0.0.1:${port}`;
const chainId = 31337;
const deployer = "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266";
const zeroAddress = `0x${"00".repeat(20)}`;
const zeroWord = `0x${"00".repeat(32)}`;
const maxUint48 = (2n ** 48n) - 1n;
const actionTypes = "(bytes32,bytes32,uint8,address,address,address,address,uint256,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,uint64,uint64,uint256,uint48,uint48)";
const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const fileSha256 = (path) => sha256(readFileSync(path));
const encodeWord = (value) => {
  if (typeof value === "string" && /^0x[0-9a-fA-F]{40}$/.test(value)) return value.slice(2).toLowerCase().padStart(64, "0");
  if (typeof value === "string" && /^0x[0-9a-fA-F]{64}$/.test(value)) return value.slice(2).toLowerCase();
  return BigInt(value).toString(16).padStart(64, "0");
};
const rawCallData = (selector, words) => `${selector}${words.map(encodeWord).join("")}`;

function wslPath(path) {
  return execFileSync("wsl.exe", ["-d", "Ubuntu", "-e", "wslpath", "-a", path], { encoding: "utf8" }).trim();
}
const wslRepository = wslPath(repositoryRoot);
const wslOutput = wslPath(outputRoot);

function wsl(args, options = {}) {
  return execFileSync("wsl.exe", ["-d", "Ubuntu", "-e", ...args], {
    encoding: "utf8",
    maxBuffer: 128 * 1024 * 1024,
    stdio: ["pipe", "pipe", "pipe"],
    ...options,
  }).trim();
}
const cast = (args, options = {}) => wsl(["cast", ...args], options);
function parseJsonObject(text) {
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start < 0 || end < start) throw new Error(`JSON object missing: ${text.slice(0, 240)}`);
  return JSON.parse(text.slice(start, end + 1));
}
function waitForAnvil(server) {
  for (let attempt = 0; attempt < 200; attempt += 1) {
    if (server.exitCode !== null) throw new Error(`anvil exited early: ${server.exitCode}`);
    try {
      if (cast(["block-number", "--rpc-url", rpcUrl]) === "0") return;
    } catch {}
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 100);
  }
  throw new Error("anvil startup timeout");
}
async function rpcResponse(method, params) {
  const response = await fetch(rpcUrl, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
  });
  if (!response.ok) throw new Error(`RPC HTTP ${response.status}`);
  return response.json();
}
async function rpc(method, params) {
  const response = await rpcResponse(method, params);
  if (response.error) throw new Error(`${method}: ${JSON.stringify(response.error)}`);
  return response.result;
}
async function waitReceipt(hash) {
  for (let attempt = 0; attempt < 200; attempt += 1) {
    const receipt = await rpc("eth_getTransactionReceipt", [hash]);
    if (receipt) return receipt;
    await new Promise((resolveWait) => setTimeout(resolveWait, 50));
  }
  throw new Error(`receipt timeout: ${hash}`);
}
function deploy(id, constructorArgs = []) {
  const args = [
    "env", `FOUNDRY_OUT=${wslOutput}/forge-out`, `FOUNDRY_CACHE_PATH=${wslOutput}/forge-cache`,
    "forge", "create", "--root", wslRepository, "--rpc-url", rpcUrl, "--unlocked", "--from", deployer,
    "--broadcast", "--json", "--offline", "--use", pinnedSolc.binaryPath, id,
  ];
  if (constructorArgs.length > 0) args.push("--constructor-args", ...constructorArgs.map(String));
  return parseJsonObject(wsl(args)).deployedTo.toLowerCase();
}
async function deployCreationBytecode(data) {
  const hash = await rpc("eth_sendTransaction", [{ from: deployer, data, gas: "0x1c9c380" }]);
  const receipt = await waitReceipt(hash);
  if (receipt.status !== "0x1" || !receipt.contractAddress) throw new Error("control deployment failed");
  return receipt.contractAddress.toLowerCase();
}
function errorData(response) {
  const data = response?.error?.data;
  if (typeof data === "string") return data;
  if (typeof data?.data === "string") return data.data;
  if (typeof data?.result === "string") return data.result;
  return null;
}
async function deriveId(to, selector, words) {
  const result = await rpc("eth_call", [{ from: deployer, to, data: rawCallData(selector, words) }, "latest"]);
  if (!/^0x[0-9a-fA-F]{64}$/.test(result)) throw new Error("unexpected derived ID");
  return result.toLowerCase();
}
const wordAt = (hex, index) => `0x${hex.replace(/^0x/, "").slice(index * 64, (index + 1) * 64)}`;
const numberAt = (hex, index) => BigInt(wordAt(hex, index));

async function observe(endpoint, actionId, subject, calldata) {
  const frozenSelector = cast(["sig", "getFrozenTokens(address)"]);
  const actionSelector = cast(["sig", "actionRecord(bytes32)"]);
  const receiptSelector = cast(["sig", "receipt(bytes32)"]);
  const frozen = await rpc("eth_call", [{ from: deployer, to: endpoint, data: `${frozenSelector}${encodeWord(subject)}` }, "latest"]);
  const action = await rpc("eth_call", [{ from: deployer, to: endpoint, data: `${actionSelector}${encodeWord(actionId)}` }, "latest"]);
  const storedReceipt = await rpc("eth_call", [{ from: deployer, to: endpoint, data: `${receiptSelector}${encodeWord(actionId)}` }, "latest"]);
  const replay = await rpcResponse("eth_call", [{ from: deployer, to: endpoint, data: calldata, gas: "0xe4e1c0" }, "latest"]);
  return {
    frozenTarget: numberAt(frozen, 0).toString(),
    actionLifecycle: Number(numberAt(action, 1)),
    actionAmount: numberAt(action, 6).toString(),
    actionPriorAmount: numberAt(action, 7).toString(),
    actionReceiptHash: wordAt(action, 15),
    storedReceiptHash: wordAt(storedReceipt, 11),
    replayStatus: replay.error ? "REVERT" : "SUCCESS",
    replayErrorData: errorData(replay),
  };
}

async function executeFullTransaction(endpoint, words, selectors, label) {
  const calldata = rawCallData(selectors.execute, words);
  const preStateDumpHex = await rpc("anvil_dumpState", []);
  const preStateDump = gunzipSync(Buffer.from(preStateDumpHex.replace(/^0x/, ""), "hex"));
  const preStatePath = resolve(outputRoot, `${label}-prestate.json`);
  writeFileSync(preStatePath, preStateDump);
  const preProof = await rpc("eth_getProof", [endpoint, [], "latest"]);
  const senderNonceBefore = BigInt(await rpc("eth_getTransactionCount", [deployer, "latest"]));
  const callResult = await rpc("eth_call", [{ from: deployer, to: endpoint, data: calldata, gas: "0xe4e1c0" }, "latest"]);
  const txHash = await rpc("eth_sendTransaction", [{ from: deployer, to: endpoint, data: calldata, gas: "0xe4e1c0" }]);
  const receipt = await waitReceipt(txHash);
  const postStateDumpHex = await rpc("anvil_dumpState", []);
  const postStateDump = gunzipSync(Buffer.from(postStateDumpHex.replace(/^0x/, ""), "hex"));
  const postStatePath = resolve(outputRoot, `${label}-poststate.json`);
  writeFileSync(postStatePath, postStateDump);
  const senderNonceAfter = BigInt(await rpc("eth_getTransactionCount", [deployer, "latest"]));
  const postProof = await rpc("eth_getProof", [endpoint, [], "latest"]);
  const observation = await observe(endpoint, words[1], words[3], calldata);
  const frozenTopic = cast(["keccak"], { input: "Frozen(address,uint256)" }).toLowerCase();
  const appliedTopic = cast(["keccak"], { input: "RegulatoryActionApplied(bytes32,uint8,bytes32,bytes32)" }).toLowerCase();
  const topics = receipt.logs.map((entry) => entry.topics[0].toLowerCase());
  const checks = {
    transactionSuccess: receipt.status === "0x1",
    senderNonceIncrementedOnce: senderNonceAfter === senderNonceBefore + 1n,
    tokenStorageChanged: preProof.storageHash !== postProof.storageHash,
    frozenTargetExact: observation.frozenTarget === "1",
    lifecycleApplied: observation.actionLifecycle === 2,
    actionAmountExact: observation.actionAmount === "1",
    priorTargetCaptured: observation.actionPriorAmount === "0",
    receiptReturnMatchesRecord: callResult.toLowerCase() === observation.actionReceiptHash.toLowerCase(),
    receiptStorageMatchesRecord: observation.storedReceiptHash.toLowerCase() === observation.actionReceiptHash.toLowerCase(),
    orderedProtocolLogs: topics.length === 2 && topics[0] === frozenTopic && topics[1] === appliedTopic,
    replayRejected: observation.replayStatus === "REVERT",
  };
  return {
    label,
    endpoint,
    actionId: words[1],
    calldataHex: calldata,
    calldataSha256: sha256(Buffer.from(calldata.slice(2), "hex")),
    preStatePath: `${label}-prestate.json`,
    preStateSha256: fileSha256(preStatePath),
    postStatePath: `${label}-poststate.json`,
    postStateSha256: fileSha256(postStatePath),
    callReceiptHash: callResult,
    txHash,
    blockNumber: receipt.blockNumber,
    transactionIndex: receipt.transactionIndex,
    gasUsed: BigInt(receipt.gasUsed).toString(),
    senderNonceBefore: senderNonceBefore.toString(),
    senderNonceAfter: senderNonceAfter.toString(),
    tokenStorageHashBefore: preProof.storageHash,
    tokenStorageHashAfter: postProof.storageHash,
    committedLogCount: receipt.logs.length,
    committedLogTopics: topics,
    observation,
    checks,
    status: Object.values(checks).every(Boolean) ? "PASS" : "FAIL",
  };
}

const dependencyLock = JSON.parse(readFileSync(resolve(repositoryRoot, "formal/kevm/dependencies.lock.json"), "utf8"));
const pinnedSolc = resolvePinnedSolc(dependencyLock.components.solc);
mkdirSync(outputRoot, { recursive: false });
let server;
try {
  try {
    cast(["block-number", "--rpc-url", rpcUrl]);
    throw new Error(`port already in use: ${rpcUrl}`);
  } catch (error) {
    if (String(error.message).includes("already in use")) throw error;
  }
  server = spawn("wsl.exe", ["-d", "Ubuntu", "-e", "anvil", "--silent", "--port", String(port), "--chain-id", String(chainId), "--hardfork", "cancun", "--timestamp", "1700000000"], {
    windowsHide: true,
    stdio: ["ignore", "pipe", "pipe"],
  });
  waitForAnvil(server);

  const domain = cast(["keccak"], { input: "ERC-TRUST/reference-v1" });
  const authorityRef = cast(["keccak"], { input: "AUTHORITY" });
  const config = cast(["keccak"], { input: "CONFIG-V1" });
  const schema = cast(["keccak"], { input: "SCHEMA-V1" });
  const scope = cast(["keccak"], { input: "GLOBAL-SCOPE" });
  const supply = "1000000000000000000000000";
  const dependency = deploy("implementation/test/mocks/MockBoundDependency.sol:MockBoundDependency", ["0", config]);
  const constructorArgs = [
    "ERC-TRUST Reference", "TRUST", "18", deployer, deployer, supply, authorityRef, deployer,
    dependency, dependency, dependency, dependency, schema,
  ];
  const canonical = deploy("implementation/src/TrustToken.sol:TrustToken", constructorArgs);

  const controlOutput = JSON.parse(readFileSync(resolve(controlRoot, "standard-json-output.json"), "utf8"));
  const creationObject = controlOutput.contracts["implementation/src/TrustToken.sol"].TrustToken.evm.bytecode.object;
  const encodedArgs = cast([
    "abi-encode",
    "f(string,string,uint8,address,address,uint256,bytes32,address,address,address,address,address,bytes32)",
    ...constructorArgs.map(String),
  ]).replace(/^0x/, "");
  const control = await deployCreationBytecode(`0x${creationObject}${encodedArgs}`);

  const curatedRuntime = readFileSync(resolve(repositoryRoot, "evidence/end-to-end-refinement/runtime-binding/resolved/native/TrustToken.hex"), "utf8").trim().replace(/^0x/, "");
  const canonicalRuntimeSha256 = sha256(Buffer.from((await rpc("eth_getCode", [canonical, "latest"])).slice(2), "hex"));
  const controlRuntimeSha256 = sha256(Buffer.from((await rpc("eth_getCode", [control, "latest"])).slice(2), "hex"));
  if (canonicalRuntimeSha256 !== sha256(Buffer.from(curatedRuntime, "hex"))) throw new Error("canonical runtime drift");
  if (controlRuntimeSha256 !== "bebc8d68c0f4f363126c9b6070dbcdafd09cd906f426ee1f7f7bdc8a7aa6f801") throw new Error("control runtime drift");

  const deriveSelector = cast(["sig", `deriveActionId(${actionTypes})`]);
  const executeSelector = cast(["sig", `executeERC7943Action(${actionTypes})`]);
  async function binding(endpoint) {
    const call = `${cast(["sig", "getBindingState(uint8)"])}${encodeWord(0)}`;
    const result = await rpc("eth_call", [{ from: deployer, to: endpoint, data: call }, "latest"]);
    return { hash: `0x${result.slice(2 + 64, 2 + 128)}`, epoch: BigInt(`0x${result.slice(2 + 128, 2 + 192)}`) };
  }
  async function request(endpoint, nonce, label) {
    const policy = await binding(endpoint);
    const words = [
      domain, zeroWord, 0, deployer, deployer, zeroAddress, zeroAddress, 1,
      cast(["keccak"], { input: `${label}-CASE` }), scope, policy.hash,
      cast(["keccak"], { input: `${label}-PROVENANCE` }), zeroWord, zeroWord, zeroWord,
      authorityRef, 1, policy.epoch, nonce, 0, maxUint48,
    ];
    words[1] = await deriveId(endpoint, deriveSelector, words);
    return words;
  }

  const canonicalRun = await executeFullTransaction(canonical, await request(canonical, 1001n, "ACT01-CANONICAL"), { execute: executeSelector }, "canonical-positive");
  const controlRun = await executeFullTransaction(control, await request(control, 1002n, "ACT01-CONTROL"), { execute: executeSelector }, "unchanged-claim-control-negative");
  const result = {
    schemaVersion: 1,
    kind: "ACT01_FULL_TRANSACTION_FEASIBILITY_V1",
    classification: "FEASIBILITY_NO_CREDIT",
    repository: {
      branch: execFileSync("git", ["-C", repositoryRoot, "branch", "--show-current"], { encoding: "utf8" }).trim(),
      head: execFileSync("git", ["-C", repositoryRoot, "rev-parse", "HEAD"], { encoding: "utf8" }).trim(),
    },
    runtime: {
      canonicalSha256: canonicalRuntimeSha256,
      controlSha256: controlRuntimeSha256,
    },
    canonical: canonicalRun,
    control: controlRun,
    mutationReach: {
      sameSuccessfulTransactionShape: canonicalRun.checks.transactionSuccess && controlRun.checks.transactionSuccess,
      sameOrderedProtocolLogShape: canonicalRun.checks.orderedProtocolLogs && controlRun.checks.orderedProtocolLogs,
      canonicalTargetOne: canonicalRun.observation.frozenTarget === "1",
      controlRestoredPriorTarget: controlRun.observation.frozenTarget === "0",
      unchangedAct01TargetWouldDistinguish: canonicalRun.observation.frozenTarget !== controlRun.observation.frozenTarget,
    },
    status: canonicalRun.status === "PASS"
      && controlRun.checks.transactionSuccess
      && controlRun.checks.lifecycleApplied
      && controlRun.checks.receiptReturnMatchesRecord
      && controlRun.checks.receiptStorageMatchesRecord
      && controlRun.checks.orderedProtocolLogs
      && controlRun.observation.frozenTarget === "0"
      ? "PASS_FULL_TRANSACTION_FEASIBILITY_NO_CREDIT"
      : "FAIL_FULL_TRANSACTION_FEASIBILITY",
    proofExecuted: false,
    proofCredit: false,
    centralCredit: false,
  };
  writeFileSync(resolve(outputRoot, "result.json"), `${JSON.stringify(result, null, 2)}\n`);
  if (!result.status.startsWith("PASS")) throw new Error("ACT-01 full transaction feasibility failed");
  process.stdout.write(`${JSON.stringify({ status: result.status, canonical: canonicalRun.status, controlTarget: controlRun.observation.frozenTarget, resultSha256: fileSha256(resolve(outputRoot, "result.json")) })}\n`);
} finally {
  if (server && server.exitCode === null) {
    server.kill();
    await new Promise((resolveWait) => server.once("exit", resolveWait));
  }
}
