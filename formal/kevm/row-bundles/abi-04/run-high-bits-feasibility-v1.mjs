import { createHash } from "node:crypto";
import { execFileSync, spawn } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { resolvePinnedSolc } from "../../../../scripts/lib/resolve-pinned-solc.mjs";

const repositoryRoot = resolve(import.meta.dirname, "../../../..");
const outputIndex = process.argv.indexOf("--output-root");
if (outputIndex < 0 || !process.argv[outputIndex + 1]) {
  throw new Error("usage: node run-high-bits-feasibility-v1.mjs --output-root <absolute-new-path> [--port <port>]");
}
const outputRoot = resolve(process.argv[outputIndex + 1]);
if (existsSync(outputRoot)) throw new Error(`output root already exists: ${outputRoot}`);
const portIndex = process.argv.indexOf("--port");
const port = portIndex >= 0 ? Number(process.argv[portIndex + 1]) : 18550;
if (!Number.isInteger(port) || port < 1024 || port > 65535) throw new Error("invalid port");

const rpcUrl = `http://127.0.0.1:${port}`;
const chainId = 31337;
const deployer = "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266";
const subjectRegulatory = deployer;
const subject7943 = "0x00000000000000000000000000000000000000a1";
const buyer = "0x0000000000000000000000000000000000000b0b";
const recovered = "0x000000000000000000000000000000000000beef";
const zeroAddress = `0x${"00".repeat(20)}`;
const zeroWord = `0x${"00".repeat(32)}`;
const maxUint48 = (2n ** 48n) - 1n;
const actionTypes = "(bytes32,bytes32,uint8,address,address,address,address,uint256,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,uint64,uint64,uint256,uint48,uint48)";
const reversalTypes = "(bytes32,bytes32,bytes32,uint8,bytes32,uint64,uint256,uint48,uint48)";
const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const fileSha256 = (path) => sha256(readFileSync(path));

function wslPath(path) {
  return execFileSync("wsl.exe", ["-d", "Ubuntu", "-e", "wslpath", "-a", path], { encoding: "utf8" }).trim();
}
const wslRepository = wslPath(repositoryRoot);
const wslOutput = wslPath(outputRoot);
const forgeOut = `${wslOutput}/forge-out`;
const forgeCache = `${wslOutput}/forge-cache`;

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
    "env",
    `FOUNDRY_OUT=${forgeOut}`,
    `FOUNDRY_CACHE_PATH=${forgeCache}`,
    "forge",
    "create",
    "--root",
    wslRepository,
    "--rpc-url",
    rpcUrl,
    "--unlocked",
    "--from",
    deployer,
    "--broadcast",
    "--json",
    "--offline",
    "--use",
    pinnedSolc.binaryPath,
    id,
  ];
  if (constructorArgs.length > 0) args.push("--constructor-args", ...constructorArgs.map(String));
  return parseJsonObject(wsl(args)).deployedTo.toLowerCase();
}

function sendSignature(address, signature, args = []) {
  return parseJsonObject(cast([
    "send",
    address,
    signature,
    ...args.map(String),
    "--rpc-url",
    rpcUrl,
    "--unlocked",
    "--from",
    deployer,
    "--json",
  ]));
}

async function sendRaw(to, data) {
  const hash = await rpc("eth_sendTransaction", [{ from: deployer, to, data, gas: "0xe4e1c0" }]);
  const receipt = await waitReceipt(hash);
  if (receipt.status !== "0x1") throw new Error(`transaction failed: ${hash}`);
  return receipt;
}

function encodeWord(value) {
  if (typeof value === "string" && /^0x[0-9a-fA-F]{40}$/.test(value)) return value.slice(2).toLowerCase().padStart(64, "0");
  if (typeof value === "string" && /^0x[0-9a-fA-F]{64}$/.test(value)) return value.slice(2).toLowerCase();
  return BigInt(value).toString(16).padStart(64, "0");
}

const rawCallData = (selector, words) => `${selector}${words.map(encodeWord).join("")}`;

function errorData(response) {
  const data = response?.error?.data;
  if (typeof data === "string") return data;
  if (typeof data?.data === "string") return data.data;
  if (typeof data?.result === "string") return data.result;
  return null;
}

async function deriveId(to, selector, words) {
  const result = await rpc("eth_call", [{ from: deployer, to, data: rawCallData(selector, words) }, "latest"]);
  if (!/^0x[0-9a-fA-F]{64}$/.test(result)) throw new Error(`unexpected derived ID: ${result}`);
  return result.toLowerCase();
}

const compilerOutputs = {
  native: JSON.parse(readFileSync(resolve(repositoryRoot, "evidence/end-to-end-refinement/runtime-binding/native/standard-json-output.json"), "utf8")),
  profile: JSON.parse(readFileSync(resolve(repositoryRoot, "evidence/end-to-end-refinement/runtime-binding/verified-profile/standard-json-output.json"), "utf8")),
};
const sourceConfigs = {
  native: { source: "implementation/src/TrustToken.sol", contract: "TrustToken" },
  profile: { source: "implementation/src/profiles/ERC3643TrustAdapter.sol", contract: "ERC3643TrustAdapter" },
};

function sourceAtPc(bundle, pc) {
  const config = sourceConfigs[bundle];
  const artifact = compilerOutputs[bundle].contracts[config.source][config.contract];
  const bytes = Buffer.from(artifact.evm.deployedBytecode.object, "hex");
  const entries = artifact.evm.deployedBytecode.sourceMap.split(";");
  const decoded = [];
  let previous = [0, 0, -1, "", 0];
  for (const entry of entries) {
    const parts = entry.split(":");
    const current = previous.map((value, index) => parts[index] === undefined || parts[index] === "" ? value : index < 3 || index === 4 ? Number(parts[index]) : parts[index]);
    decoded.push(current);
    previous = current;
  }
  let offset = 0;
  let index = 0;
  while (offset < bytes.length && offset !== pc) {
    const opcode = bytes[offset];
    offset += 1 + (opcode >= 0x60 && opcode <= 0x7f ? opcode - 0x5f : 0);
    index += 1;
  }
  if (offset !== pc) return { pc, instructionBoundary: false };
  const [start, length, fileId] = decoded[index] ?? previous;
  const sourceEntry = Object.entries(compilerOutputs[bundle].sources).find(([, value]) => value.id === fileId);
  const sourcePath = sourceEntry?.[0] ?? null;
  let line = null;
  if (sourcePath && start >= 0 && length >= 0) {
    try {
      line = readFileSync(resolve(repositoryRoot, sourcePath), "utf8").slice(0, start).split("\n").length;
    } catch {}
  }
  return { pc, instructionBoundary: true, sourcePath, line };
}

async function traceCall(to, data, bundle) {
  const call = { from: deployer, to, data, gas: "0xe4e1c0" };
  const response = await rpcResponse("eth_call", [call, "latest"]);
  const trace = await rpc("debug_traceCall", [call, "latest", {
    disableStorage: true,
    disableStack: true,
    enableMemory: false,
    enableReturnData: true,
  }]);
  const terminal = [...trace.structLogs].reverse().find((step) => step.op === "REVERT" || step.op === "RETURN") ?? trace.structLogs.at(-1);
  const returnValue = trace.returnValue ? `0x${trace.returnValue.replace(/^0x/, "")}` : (errorData(response) ?? "0x");
  const stateOps = trace.structLogs.filter((step) => step.op === "SSTORE" || /^LOG[0-4]$/.test(step.op));
  return {
    status: response.error ? "REVERT" : "SUCCESS",
    errorData: errorData(response),
    returnValue,
    selector: returnValue.length >= 10 ? returnValue.slice(0, 10) : "0x00000000",
    steps: trace.structLogs.length,
    stateChangingOpcodeCount: stateOps.length,
    terminal: terminal ? { op: terminal.op, ...sourceAtPc(bundle, terminal.pc) } : null,
  };
}

async function failedTransactionStutter(to, data) {
  const snapshot = await rpc("evm_snapshot", []);
  try {
    const before = await rpc("eth_getProof", [to, [], "latest"]);
    const response = await rpcResponse("eth_sendTransaction", [{ from: deployer, to, data, gas: "0xe4e1c0" }]);
    if (response.error || !response.result) throw new Error(`malformed transaction was not mined: ${JSON.stringify(response.error)}`);
    const receipt = await waitReceipt(response.result);
    const after = await rpc("eth_getProof", [to, [], "latest"]);
    return {
      status: receipt.status,
      storageHashBefore: before.storageHash,
      storageHashAfter: after.storageHash,
      storageStutter: before.storageHash === after.storageHash,
      committedLogs: receipt.logs.length,
      committedLogsEmpty: receipt.logs.length === 0,
    };
  } finally {
    const reverted = await rpc("evm_revert", [snapshot]);
    if (reverted !== true) throw new Error("evm_revert failed");
  }
}

function legalizedValue(entry) {
  if (entry.fieldType === "uint8-enum") return 0n;
  if (entry.fieldType === "address") return 0n;
  if (entry.fieldType === "uint64") return 0n;
  if (entry.fieldType === "uint48") return 0n;
  throw new Error(`unsupported high-bits type: ${entry.fieldType}`);
}

async function executeCase(entry, endpoint, controlWords, selectors, bundle) {
  const controlData = rawCallData(endpoint.selector, controlWords);
  const control = await traceCall(endpoint.address, controlData, bundle);
  if (control.status !== "SUCCESS") throw new Error(`${entry.caseId}: canonical control did not succeed`);

  const malformedWords = [...controlWords];
  malformedWords[entry.fieldIndex] = BigInt(entry.fieldValueHex);
  let relation;
  if (endpoint.relation === "native-companion") {
    malformedWords[1] = await deriveId(endpoint.address, selectors.derive, malformedWords);
    relation = "ONE_FREE_TARGET_MUTATION_PLUS_DERIVED_COMPANION_ID";
  } else {
    relation = "TARGET_ONLY_PROFILE_TYPED_DECODER_RELATION";
  }
  const malformedData = rawCallData(endpoint.selector, malformedWords);
  const malformed = await traceCall(endpoint.address, malformedData, bundle);
  const transactionStutter = await failedTransactionStutter(endpoint.address, malformedData);

  const legalizedWords = [...controlWords];
  legalizedWords[entry.fieldIndex] = legalizedValue(entry);
  if (endpoint.relation === "native-companion") {
    legalizedWords[1] = await deriveId(endpoint.address, selectors.derive, legalizedWords);
  }
  const legalizedData = rawCallData(endpoint.selector, legalizedWords);
  const legalized = await traceCall(endpoint.address, legalizedData, bundle);

  const rawWordDiffIndices = controlWords
    .map((value, index) => encodeWord(value) === encodeWord(malformedWords[index]) ? null : index)
    .filter((value) => value !== null);
  const expectedDiff = endpoint.relation === "native-companion"
    ? [1, entry.fieldIndex].sort((a, b) => a - b)
    : [entry.fieldIndex];
  const diffPass = JSON.stringify(rawWordDiffIndices) === JSON.stringify(expectedDiff);
  const malformedPass = malformed.status === "REVERT"
    && malformed.returnValue === "0x"
    && malformed.selector === "0x00000000"
    && transactionStutter.status === "0x0"
    && transactionStutter.storageStutter
    && transactionStutter.committedLogsEmpty;
  const legalizedPostTarget = legalized.status === "SUCCESS" || (legalized.status === "REVERT" && legalized.returnValue !== "0x");
  const status = control.status === "SUCCESS" && diffPass && malformedPass && legalizedPostTarget ? "PASS" : "FAIL";
  return {
    caseId: entry.caseId,
    endpointId: entry.endpointId,
    subtype: entry.subtype,
    fieldIndex: entry.fieldIndex,
    fieldType: entry.fieldType,
    relation,
    semanticFieldMutations: 1,
    rawWordDiffIndices,
    expectedRawWordDiffIndices: expectedDiff,
    control,
    malformed,
    transactionStutter,
    legalized,
    checks: {
      canonicalControlSuccess: control.status === "SUCCESS",
      exactDiffRelation: diffPass,
      exactTargetTypedEmptyRevert: malformed.status === "REVERT" && malformed.returnValue === "0x",
      customErrorSelectorZero: malformed.selector === "0x00000000",
      storageAndLogStutter: transactionStutter.storageStutter && transactionStutter.committedLogsEmpty,
      legalizedControlReachedPostTargetMilestone: legalizedPostTarget,
    },
    status,
    proofExecuted: false,
    proofCredit: false,
    centralCredit: false,
  };
}

const matrixPath = resolve(repositoryRoot, "formal/kevm/row-bundles/abi-04/case-matrix.json");
const matrix = JSON.parse(readFileSync(matrixPath, "utf8"));
const highBits = matrix.cases.filter((entry) => entry.malformedClass === "high_bits");
const exactCaseSetSha256 = sha256(`${highBits.map((entry) => entry.caseId).sort().join("\n")}\n`);
if (highBits.length !== 45 || exactCaseSetSha256 !== "66e2e07bf4f214e319df38cb4e72687e8d733d2cccc90c91eeb4f8273f618e7b") {
  throw new Error("high-bits exact case set drift");
}

const dependencyLock = JSON.parse(readFileSync(resolve(repositoryRoot, "formal/kevm/dependencies.lock.json"), "utf8"));
const pinnedSolc = resolvePinnedSolc(dependencyLock.components.solc);
const output = {
  schemaVersion: 1,
  kind: "ABI04_HIGH_BITS_FEASIBILITY_FULL_V1",
  classification: "FEASIBILITY_NO_CREDIT",
  repository: {
    branch: execFileSync("git", ["-C", repositoryRoot, "branch", "--show-current"], { encoding: "utf8" }).trim(),
    head: execFileSync("git", ["-C", repositoryRoot, "rev-parse", "HEAD"], { encoding: "utf8" }).trim(),
  },
  caseMatrixSha256: fileSha256(matrixPath),
  highBitsExactCaseSetSha256: exactCaseSetSha256,
  highBitsCaseCount: highBits.length,
  toolchain: {
    evmSchedule: dependencyLock.evmSchedule,
    forge: dependencyLock.components.forge,
    solcVersion: dependencyLock.components.solc.version,
    solcBinarySha256: dependencyLock.components.solc.binarySha256,
  },
  outputRootRef: `external-scratch/${outputRoot.split(/[\\/]/).at(-1)}`,
  cases: [],
  proofExecuted: false,
  proofCredit: false,
  centralCredit: false,
};

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
  const nativeAuthorityRef = cast(["keccak"], { input: "AUTHORITY" });
  const profileAuthorityRef = cast(["keccak"], { input: "ERC3643-AUTHORITY" });
  const config = cast(["keccak"], { input: "CONFIG-V1" });
  const schema = cast(["keccak"], { input: "SCHEMA-V1" });
  const scope = cast(["keccak"], { input: "GLOBAL-SCOPE" });
  const supply = "1000000000000000000000000";

  const dependency = deploy("implementation/test/mocks/MockBoundDependency.sol:MockBoundDependency", ["0", config]);
  const native = deploy("implementation/src/TrustToken.sol:TrustToken", [
    "ERC-TRUST Reference", "TRUST", "18", deployer, deployer, supply, nativeAuthorityRef, deployer,
    dependency, dependency, dependency, dependency, schema,
  ]);

  const identity = deploy("implementation/test/mocks/MockERC3643Dependencies.sol:MockERC3643IdentityRegistry");
  const compliance = deploy("implementation/test/mocks/MockERC3643Dependencies.sol:MockERC3643Compliance");
  const token = deploy("implementation/test/mocks/MockERC3643Token.sol:MockERC3643Token", [identity, compliance, supply]);
  const tokenCode = await rpc("eth_getCode", [token, "latest"]);
  const tokenCodeHash = cast(["keccak", tokenCode]);
  const governor = deploy("implementation/src/profiles/ProfileGovernor.sol:ProfileGovernor", [token, identity, compliance, deployer, tokenCodeHash]);
  const profile = deploy("implementation/src/profiles/ERC3643TrustAdapter.sol:ERC3643TrustAdapter", [governor, deployer, profileAuthorityRef, "1"]);
  sendSignature(token, "setExclusiveAgent(address)", [profile]);
  sendSignature(token, "transferOwnership(address)", [governor]);
  sendSignature(governor, "seal(address)", [profile]);
  for (const account of [deployer, profile, subject7943, buyer, recovered]) {
    sendSignature(identity, "setVerified(address,bool)", [account, "true"]);
  }

  const curatedNative = readFileSync(resolve(repositoryRoot, "evidence/end-to-end-refinement/runtime-binding/resolved/native/TrustToken.hex"), "utf8").trim().replace(/^0x/, "");
  const curatedProfile = readFileSync(resolve(repositoryRoot, "evidence/end-to-end-refinement/runtime-binding/resolved/verified-profile/ERC3643TrustAdapter.hex"), "utf8").trim().replace(/^0x/, "");
  const liveNative = (await rpc("eth_getCode", [native, "latest"])).slice(2);
  const liveProfile = (await rpc("eth_getCode", [profile, "latest"])).slice(2);
  output.runtime = {
    nativeSha256: sha256(Buffer.from(liveNative, "hex")),
    profileSha256: sha256(Buffer.from(liveProfile, "hex")),
  };
  if (output.runtime.nativeSha256 !== sha256(Buffer.from(curatedNative, "hex"))) throw new Error("native runtime drift");
  if (output.runtime.profileSha256 !== sha256(Buffer.from(curatedProfile, "hex"))) throw new Error("profile runtime drift");

  const nativeBindingCall = `${cast(["sig", "getBindingState(uint8)"])}${encodeWord(0)}`;
  const nativeBindingResult = await rpc("eth_call", [{ from: deployer, to: native, data: nativeBindingCall }, "latest"]);
  const nativeBinding = `0x${nativeBindingResult.slice(2 + 64, 2 + 128)}`;
  const nativePolicyEpoch = BigInt(`0x${nativeBindingResult.slice(2 + 128, 2 + 192)}`);
  const profileBinding = await rpc("eth_call", [{ from: deployer, to: governor, data: cast(["sig", "sealedBinding()"]) }, "latest"]);

  const selectors = {
    nativeActionDerive: cast(["sig", `deriveActionId(${actionTypes})`]),
    nativeActionExecute: cast(["sig", `executeRegulatoryAction(${actionTypes})`]),
    native7943ActionExecute: cast(["sig", `executeERC7943Action(${actionTypes})`]),
    nativeReversalDerive: cast(["sig", `deriveReversalId(${reversalTypes})`]),
    nativeReversalExecute: cast(["sig", `executeRegulatoryReversal(${reversalTypes})`]),
    native7943ReversalExecute: cast(["sig", `executeERC7943Reversal(${reversalTypes})`]),
    profileActionDerive: cast(["sig", `deriveActionId(${actionTypes})`]),
    profileActionExecute: cast(["sig", `executeRegulatoryAction(${actionTypes})`]),
    profileReversalDerive: cast(["sig", `deriveReversalId(${reversalTypes})`]),
    profileReversalExecute: cast(["sig", `executeRegulatoryReversal(${reversalTypes})`]),
  };

  async function actionWords(to, deriveSelector, authorityRef, policyBinding, policyEpoch, subject, nonce, caseLabel) {
    const words = [
      domain, zeroWord, 0, subject, subject, zeroAddress, zeroAddress, 1,
      cast(["keccak"], { input: caseLabel }), scope, policyBinding,
      cast(["keccak"], { input: `${caseLabel}-PROVENANCE` }), zeroWord, zeroWord, zeroWord,
      authorityRef, 1, policyEpoch, nonce, 0, maxUint48,
    ];
    words[1] = await deriveId(to, deriveSelector, words);
    return words;
  }

  const nativeRegAction = await actionWords(native, selectors.nativeActionDerive, nativeAuthorityRef, nativeBinding, nativePolicyEpoch, subjectRegulatory, 101n, "ABI04-NATIVE-REG-ACTION");
  const native7943Action = await actionWords(native, selectors.nativeActionDerive, nativeAuthorityRef, nativeBinding, nativePolicyEpoch, subject7943, 201n, "ABI04-NATIVE-7943-ACTION");
  const profileAction = await actionWords(profile, selectors.profileActionDerive, profileAuthorityRef, profileBinding, 1n, deployer, 301n, "ABI04-PROFILE-ACTION");

  const appliedNativeReg = await actionWords(native, selectors.nativeActionDerive, nativeAuthorityRef, nativeBinding, nativePolicyEpoch, subjectRegulatory, 901n, "ABI04-NATIVE-REG-REVERSAL");
  const appliedNative7943 = await actionWords(native, selectors.nativeActionDerive, nativeAuthorityRef, nativeBinding, nativePolicyEpoch, subject7943, 902n, "ABI04-NATIVE-7943-REVERSAL");
  const appliedProfile = await actionWords(profile, selectors.profileActionDerive, profileAuthorityRef, profileBinding, 1n, deployer, 903n, "ABI04-PROFILE-REVERSAL");
  await sendRaw(native, rawCallData(selectors.nativeActionExecute, appliedNativeReg));
  await sendRaw(native, rawCallData(selectors.native7943ActionExecute, appliedNative7943));
  await sendRaw(profile, rawCallData(selectors.profileActionExecute, appliedProfile));

  async function reversalWords(to, deriveSelector, authorityRef, actionId, nonce) {
    const words = [domain, zeroWord, actionId, 0, authorityRef, 1, nonce, 0, maxUint48];
    words[1] = await deriveId(to, deriveSelector, words);
    return words;
  }
  const nativeRegReversal = await reversalWords(native, selectors.nativeReversalDerive, nativeAuthorityRef, appliedNativeReg[1], 911n);
  const native7943Reversal = await reversalWords(native, selectors.nativeReversalDerive, nativeAuthorityRef, appliedNative7943[1], 912n);
  const profileReversal = await reversalWords(profile, selectors.profileReversalDerive, profileAuthorityRef, appliedProfile[1], 913n);

  const endpointRuntime = new Map([
    ["native-regulatory-action", { address: native, selector: selectors.nativeActionExecute, relation: "native-companion", derive: selectors.nativeActionDerive, words: nativeRegAction, bundle: "native" }],
    ["native-erc7943-action", { address: native, selector: selectors.native7943ActionExecute, relation: "native-companion", derive: selectors.nativeActionDerive, words: native7943Action, bundle: "native" }],
    ["profile-regulatory-action", { address: profile, selector: selectors.profileActionExecute, relation: "profile-target-only", derive: selectors.profileActionDerive, words: profileAction, bundle: "profile" }],
    ["native-regulatory-reversal", { address: native, selector: selectors.nativeReversalExecute, relation: "native-companion", derive: selectors.nativeReversalDerive, words: nativeRegReversal, bundle: "native" }],
    ["native-erc7943-reversal", { address: native, selector: selectors.native7943ReversalExecute, relation: "native-companion", derive: selectors.nativeReversalDerive, words: native7943Reversal, bundle: "native" }],
    ["profile-regulatory-reversal", { address: profile, selector: selectors.profileReversalExecute, relation: "profile-target-only", derive: selectors.profileReversalDerive, words: profileReversal, bundle: "profile" }],
  ]);

  for (const entry of highBits) {
    const endpoint = endpointRuntime.get(entry.endpointId);
    if (!endpoint) throw new Error(`missing runtime endpoint: ${entry.endpointId}`);
    output.cases.push(await executeCase(entry, endpoint, endpoint.words, { derive: endpoint.derive }, endpoint.bundle));
  }

  output.passCount = output.cases.filter((entry) => entry.status === "PASS").length;
  output.failCount = output.cases.length - output.passCount;
  output.status = output.passCount === 45 ? "PASS_45_OF_45_FEASIBILITY_NO_CREDIT" : "FAIL_HIGH_BITS_FEASIBILITY";
  output.processStateAtReceipt = "ANVIL_RUNNING_UNTIL_FINALLY_CLEANUP";
  writeFileSync(resolve(outputRoot, "result.json"), `${JSON.stringify(output, null, 2)}\n`);
  if (output.failCount !== 0) throw new Error(`${output.failCount} high-bits cases failed`);
  process.stdout.write(`${JSON.stringify({ status: output.status, passCount: output.passCount, failCount: output.failCount, resultSha256: fileSha256(resolve(outputRoot, "result.json")) })}\n`);
} finally {
  if (server && server.exitCode === null) {
    server.kill();
    await new Promise((resolveWait) => server.once("exit", resolveWait));
  }
}
