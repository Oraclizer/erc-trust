import { createHash } from "node:crypto";
import { execFileSync, spawn } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { gunzipSync } from "node:zlib";
import { resolvePinnedSolc } from "../../../../scripts/lib/resolve-pinned-solc.mjs";

const rowRoot = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(rowRoot, "../../../..");
const wslRoot = `/mnt/${repositoryRoot[0].toLowerCase()}${repositoryRoot.slice(2).replaceAll("\\", "/")}`;
const lockPath = join(repositoryRoot, "formal", "kevm", "dependencies.lock.json");
const lock = JSON.parse(readFileSync(lockPath, "utf8"));
const pinnedSolc = resolvePinnedSolc(lock.components.solc);
const compilerOutputPath = join(
  repositoryRoot,
  "evidence", "end-to-end-refinement", "runtime-binding", "native", "standard-json-output.json",
);
const runtimeRoot = join(
  repositoryRoot,
  "evidence", "end-to-end-refinement", "runtime-binding", "resolved", "native",
);
const fixturePath = join(rowRoot, "fixture.json");

const port = Number(process.env.SEP04_ANVIL_PORT ?? "28564");
if (!Number.isSafeInteger(port) || port < 1024 || port > 65535) throw new Error("invalid SEP04_ANVIL_PORT");
const rpcUrl = `http://127.0.0.1:${port}`;
const privateKey = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
const sender = "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266";
const destination = "0x000000000000000000000000000000000000beef";
const chainId = 31337;
const genesisTimestamp = 1_700_000_000;
const blockGasLimit = 30_000_000;
const transactionGasLimit = 12_000_000;
const supply = "1000000000000000000000000";
const amount = "9000000000000000000";
const actionKind = 3;
const requestNonce = "2";
const maxUint48 = "281474976710655";
const canonicalFinalTopic = "0xaadd5db99c0c1f57ce6f82b109958a00899fc4cea03e70fdae7741b9e7050091";
const actionTupleType = "(bytes32,bytes32,uint8,address,address,address,address,uint256,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,uint64,uint64,uint256,uint48,uint48)";

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

function repoPath(path) {
  return relative(repositoryRoot, path).split(sep).join("/");
}

function wsl(args, options = {}) {
  return execFileSync("wsl.exe", ["-d", "Ubuntu", "-e", ...args], {
    encoding: "utf8",
    maxBuffer: 256 * 1024 * 1024,
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

function normalizeHex(value, bytes = null) {
  const raw = String(value).startsWith("0x") ? String(value).slice(2) : String(value);
  if (!/^[0-9a-fA-F]*$/.test(raw)) throw new Error(`invalid hex: ${value}`);
  let hex = raw.toLowerCase();
  if (hex.length % 2 !== 0) hex = `0${hex}`;
  if (bytes !== null) {
    if (hex.length > bytes * 2) throw new Error(`hex exceeds ${bytes} bytes: ${value}`);
    hex = hex.padStart(bytes * 2, "0");
  }
  return `0x${hex}`;
}

function hexInt(value) {
  return BigInt(value).toString(10);
}

function keccakInput(input) {
  const result = cast(["keccak"], { input });
  if (!/^0x[0-9a-fA-F]{64}$/.test(result)) throw new Error(`bad Keccak result: ${result}`);
  return result.toLowerCase();
}

function abiHash(signature, args) {
  const encoded = cast(["abi-encode", signature, ...args.map(String)]);
  return keccakInput(encoded);
}

async function rpc(method, params = []) {
  const response = await fetch(rpcUrl, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
  });
  const payload = await response.json();
  if (payload.error) throw new Error(`${method}: ${JSON.stringify(payload.error)}`);
  return payload.result;
}

async function waitForAnvil(server) {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    if (server.exitCode !== null) throw new Error(`anvil exited early with ${server.exitCode}`);
    try {
      if (await rpc("eth_blockNumber") === "0x0") return;
    } catch {
      // RPC is still starting.
    }
    await new Promise((resolveWait) => setTimeout(resolveWait, 100));
  }
  throw new Error("timed out waiting for Anvil");
}

function parseStateDump(value) {
  let parsed = value;
  for (let index = 0; index < 3 && typeof parsed === "string"; index += 1) {
    let text = parsed;
    if (/^0x[0-9a-fA-F]+$/.test(parsed)) {
      let bytes = Buffer.from(parsed.slice(2), "hex");
      if (bytes[0] === 0x1f && bytes[1] === 0x8b) bytes = gunzipSync(bytes);
      text = bytes.toString("utf8");
    }
    parsed = JSON.parse(text);
  }
  const candidates = [parsed?.accounts, parsed?.state?.accounts, parsed?.data?.accounts];
  const accounts = candidates.find((candidate) => candidate && typeof candidate === "object");
  if (!accounts) throw new Error(`Anvil state dump has no accounts map: ${JSON.stringify(parsed).slice(0, 500)}`);
  return Object.fromEntries(Object.entries(accounts).map(([address, account]) => [address.toLowerCase(), {
    balance: normalizeHex(account.balance ?? "0x0"),
    nonce: normalizeHex(account.nonce ?? "0x0"),
    code: normalizeHex(account.code ?? "0x"),
    storage: Object.fromEntries(Object.entries(account.storage ?? {}).map(([slot, word]) => [
      normalizeHex(slot, 32), normalizeHex(word, 32),
    ])),
  }]));
}

function stateHash(accounts) {
  return sha256(Buffer.from(JSON.stringify(stable(accounts)), "utf8"));
}

function storageK(storage) {
  const entries = Object.entries(storage)
    .filter(([, value]) => BigInt(value) !== 0n)
    .sort(([left], [right]) => (BigInt(left) < BigInt(right) ? -1 : 1))
    .map(([slot, value]) => `${BigInt(slot)} |-> ${BigInt(value)}`);
  return entries.length === 0 ? ".Map" : entries.join(" ");
}

function codeK(address, code, tokenAddress, dependencyAddress) {
  if (address === tokenAddress) return "#trustTrustTokenRuntime()";
  if (address === dependencyAddress) return "#trustMockBoundDependencyRuntime()";
  return code === "0x" ? ".Bytes" : `#parseByteStack(\"${code}\")`;
}

function accountsK(accounts, tokenAddress, dependencyAddress) {
  return Object.entries(accounts)
    .sort(([left], [right]) => (BigInt(left) < BigInt(right) ? -1 : 1))
    .map(([address, account]) => {
      const storage = storageK(account.storage);
      return [
        "<account>",
        `  <acctID> ${BigInt(address)} </acctID>`,
        `  <balance> ${BigInt(account.balance)} </balance>`,
        `  <code> ${codeK(address, account.code, tokenAddress, dependencyAddress)} </code>`,
        `  <storage> ${storage} </storage>`,
        `  <origStorage> ${storage} </origStorage>`,
        "  <transientStorage> .Map </transientStorage>",
        `  <nonce> ${BigInt(account.nonce)} </nonce>`,
        "</account>",
      ].join("\n");
    })
    .join("\n");
}

function completeLogsK(logs) {
  return logs.map((log) => {
    const topics = log.topics.length === 0
      ? ".List"
      : log.topics.map((topic) => `ListItem(${BigInt(topic)})`).join(" ");
    return `ListItem({ ${BigInt(log.emitter)} | ${topics} | #parseByteStack(\"${log.data}\") })`;
  }).join(" ");
}

function contractStorageLayout() {
  const output = JSON.parse(readFileSync(compilerOutputPath, "utf8"));
  const layout = output.contracts?.["implementation/src/TrustToken.sol"]?.TrustToken?.storageLayout;
  if (!layout) throw new Error("TrustToken storage layout missing from pinned compiler output");
  return layout;
}

function receiptSlots(actionId) {
  const layout = contractStorageLayout();
  function memberSlot(mappingLabel) {
    const mapping = layout.storage.find((entry) => entry.label === mappingLabel);
    if (!mapping) throw new Error(`storage mapping missing: ${mappingLabel}`);
    const mappingType = layout.types[mapping.type];
    const structType = layout.types[mappingType.value];
    const receiptMember = structType.members.find((member) => member.label === "receiptHash");
    if (!receiptMember) throw new Error(`receiptHash member missing: ${mappingLabel}`);
    const base = keccakInput(`0x${actionId.slice(2)}${BigInt(mapping.slot).toString(16).padStart(64, "0")}`);
    return normalizeHex(`0x${(BigInt(base) + BigInt(receiptMember.slot)).toString(16)}`, 32);
  }
  return {
    actionRecordReceiptSlot: memberSlot("_actions"),
    receiptRecordReceiptSlot: memberSlot("_receipts"),
  };
}

function deployment(label, id, constructorArgs) {
  const nonce = Number(cast(["nonce", sender, "--rpc-url", rpcUrl]));
  const expectedAddress = cast(["compute-address", sender, "--nonce", String(nonce)])
    .toLowerCase().match(/0x[0-9a-f]{40}/)?.[0];
  if (!expectedAddress) throw new Error(`could not compute CREATE address for ${label}`);
  const output = parseJsonOutput(wsl([
    "forge", "create", "--root", wslRoot, "--rpc-url", rpcUrl,
    "--private-key", privateKey, "--broadcast", "--json", "--offline",
    "--use", pinnedSolc.binaryPath, id, "--constructor-args", ...constructorArgs.map(String),
  ]));
  const address = output.deployedTo.toLowerCase();
  if (address !== expectedAddress) throw new Error(`${label} CREATE address mismatch`);
  const runtime = normalizeHex(cast(["code", address, "--rpc-url", rpcUrl]));
  const runtimeFile = join(runtimeRoot, `${label}.hex`);
  const pinnedRuntime = normalizeHex(readFileSync(runtimeFile, "utf8").trim());
  if (runtime !== pinnedRuntime) throw new Error(`${label} runtime differs from pinned resolved runtime`);
  return {
    address,
    nonce,
    transactionHash: output.transactionHash.toLowerCase(),
    runtimeSha256: sha256(Buffer.from(runtime.slice(2), "hex")),
    runtimeByteLength: (runtime.length - 2) / 2,
    runtimeFile: repoPath(runtimeFile),
    runtimeFileSha256: sha256(readFileSync(runtimeFile)),
  };
}

function requestTuple(fields) {
  return `(${[
    fields.domain, fields.actionId, fields.action, fields.subject, fields.source, fields.destination,
    fields.custodian, fields.amount, fields.caseId, fields.scopeHash, fields.policyCommitment,
    fields.provenanceCommitment, fields.settlementCommitment, fields.proceedsCommitment,
    fields.entitlementCommitment, fields.authorityRef, fields.authorityEpoch, fields.policyEpoch,
    fields.nonce, fields.validAfter, fields.validBefore,
  ].join(",")})`;
}

function traceAccessSummary(trace, rootAddress) {
  const accounts = new Set([rootAddress]);
  const storage = new Map();
  const addressAtDepth = new Map([[1, rootAddress]]);
  let pendingCall = null;
  for (const step of trace.structLogs ?? []) {
    if (!addressAtDepth.has(step.depth) && pendingCall?.depth + 1 === step.depth) {
      addressAtDepth.set(step.depth, pendingCall.target);
      accounts.add(pendingCall.target);
    }
    for (const depth of [...addressAtDepth.keys()]) if (depth > step.depth) addressAtDepth.delete(depth);
    const current = addressAtDepth.get(step.depth) ?? rootAddress;
    const stack = step.stack ?? [];
    if ((step.op === "SLOAD" || step.op === "SSTORE") && stack.length > 0) {
      const slot = normalizeHex(stack.at(-1), 32);
      if (!storage.has(current)) storage.set(current, new Set());
      storage.get(current).add(slot);
    }
    if (["CALL", "CALLCODE", "DELEGATECALL", "STATICCALL"].includes(step.op) && stack.length >= 2) {
      const target = normalizeHex(stack.at(-2), 20).toLowerCase();
      accounts.add(target);
      pendingCall = { depth: step.depth, target };
    } else {
      pendingCall = null;
    }
  }
  return {
    accounts: [...accounts].sort(),
    storage: Object.fromEntries([...storage.entries()].sort().map(([address, slots]) => [address, [...slots].sort()])),
  };
}

function receiptLogs(receipt) {
  return receipt.logs.map((log) => ({
    index: Number(BigInt(log.logIndex)),
    emitter: log.address.toLowerCase(),
    topics: log.topics.map((topic) => normalizeHex(topic, 32)),
    data: normalizeHex(log.data),
  }));
}

try {
  try {
    await rpc("eth_blockNumber");
    throw new Error(`SEP-04 capture port already in use: ${rpcUrl}`);
  } catch (error) {
    if (String(error.message).includes("already in use")) throw error;
  }

  const anvilVersion = wsl(["anvil", "--version"]);
  const forgeVersion = wsl(["forge", "--version"]);
  const castVersion = wsl(["cast", "--version"]);
  const solcSha256 = wsl(["sha256sum", pinnedSolc.binaryPath]).split(/\s+/)[0];
  if (solcSha256 !== lock.components.solc.binarySha256) throw new Error("pinned solc binary SHA-256 mismatch");

  const server = spawn("wsl.exe", [
    "-d", "Ubuntu", "-e", "anvil", "--silent", "--steps-tracing",
    "--port", String(port), "--chain-id", String(chainId), "--hardfork", "cancun",
    "--timestamp", String(genesisTimestamp), "--gas-limit", String(blockGasLimit),
    "--base-fee", "0", "--gas-price", "0",
  ], { windowsHide: true, stdio: ["ignore", "pipe", "pipe"] });
  let serverStderr = "";
  server.stderr.on("data", (chunk) => { serverStderr += chunk.toString(); });
  try {
    await waitForAnvil(server);

    // These constructor inputs are the repository-owned resolved-runtime fixture inputs.
    // Request-only commitments below retain the successful LIQUIDATE test shape.
    const authorityRef = keccakInput("AUTHORITY");
    const config = keccakInput("CONFIG-V1");
    const schema = keccakInput("SCHEMA-V1");
    const domain = keccakInput("ERC-TRUST/reference-v1");
    const scopeHash = keccakInput("KONTROL-SCOPE");
    const caseId = abiHash("f(string,uint256)", ["KONTROL-CASE", requestNonce]);
    const provenanceCommitment = abiHash("f(string,uint256)", ["KONTROL-PROVENANCE", requestNonce]);
    const settlementCommitment = abiHash("f(string,uint256)", ["KONTROL-SETTLEMENT", requestNonce]);
    const proceedsCommitment = abiHash("f(string,uint256)", ["KONTROL-PROCEEDS", requestNonce]);
    const zeroWord = normalizeHex("0x", 32);
    const zeroAddress = normalizeHex("0x", 20);

    const dependency = deployment(
      "MockBoundDependency",
      "implementation/test/mocks/MockBoundDependency.sol:MockBoundDependency",
      ["0", config],
    );
    const token = deployment(
      "TrustToken",
      "implementation/src/TrustToken.sol:TrustToken",
      [
        "ERC-TRUST", "TRUST", "18", sender, sender, supply, authorityRef, sender,
        dependency.address, dependency.address, dependency.address, dependency.address, schema,
      ],
    );
    if (token.runtimeSha256 !== "3697706d4948c34fada47e049d32ad3e1866cf24ded6328f0c209d858614a86d") {
      throw new Error("TrustToken runtime SHA-256 is not the SEP-04 pinned identity");
    }

    const bindingLines = cast([
      "call", token.address, "getBindingState(uint8)(address,bytes32,uint64)", "0", "--rpc-url", rpcUrl,
    ]).split(/\r?\n/).filter(Boolean);
    if (bindingLines.length !== 3) throw new Error(`unexpected getBindingState output: ${bindingLines}`);
    const policyCommitment = normalizeHex(bindingLines[1], 32);
    const policyEpoch = BigInt(bindingLines[2]).toString();
    const request = {
      domain, actionId: zeroWord, action: String(actionKind), subject: sender, source: sender,
      destination, custodian: zeroAddress, amount, caseId, scopeHash, policyCommitment,
      provenanceCommitment, settlementCommitment, proceedsCommitment,
      entitlementCommitment: zeroWord, authorityRef, authorityEpoch: "1", policyEpoch,
      nonce: requestNonce, validAfter: "0", validBefore: maxUint48,
    };
    const derivedActionId = normalizeHex(cast([
      "call", token.address, `deriveActionId(${actionTupleType})(bytes32)`, requestTuple(request),
      "--from", sender, "--rpc-url", rpcUrl,
    ]), 32);
    request.actionId = derivedActionId;
    const calldataHex = normalizeHex(cast([
      "calldata", `executeRegulatoryAction(${actionTupleType})`, requestTuple(request),
    ]));

    const senderNonceBefore = BigInt(await rpc("eth_getTransactionCount", [sender, "latest"]));
    if (senderNonceBefore !== 2n) throw new Error(`unexpected sender nonce before action: ${senderNonceBefore}`);
    const preBlock = await rpc("eth_getBlockByNumber", ["latest", false]);
    const preAccounts = parseStateDump(await rpc("anvil_dumpState"));
    const callReturn = normalizeHex(await rpc("eth_call", [{
      from: sender, to: token.address, data: calldataHex,
      gas: normalizeHex(`0x${transactionGasLimit.toString(16)}`), gasPrice: "0x0", value: "0x0",
    }, "latest"]), 32);

    const sent = parseJsonOutput(cast([
      "send", token.address, "--data", calldataHex, "--gas-limit", String(transactionGasLimit),
      "--gas-price", "0", "--legacy", "--private-key", privateKey, "--rpc-url", rpcUrl, "--json",
    ]));
    const transactionHash = sent.transactionHash.toLowerCase();
    const receipt = await rpc("eth_getTransactionReceipt", [transactionHash]);
    const transaction = await rpc("eth_getTransactionByHash", [transactionHash]);
    const actionBlock = await rpc("eth_getBlockByHash", [receipt.blockHash, false]);
    const trace = await rpc("debug_traceTransaction", [transactionHash, {
      disableMemory: true, disableStorage: true, disableStack: false,
    }]);
    const postAccounts = parseStateDump(await rpc("anvil_dumpState"));
    const senderNonceAfter = BigInt(await rpc("eth_getTransactionCount", [sender, "latest"]));

    if (receipt.status !== "0x1") throw new Error(`LIQUIDATE transaction failed: ${receipt.status}`);
    if (senderNonceAfter !== senderNonceBefore + 1n) throw new Error("sender nonce transition is not exact +1");
    const traceReturn = normalizeHex(trace.returnValue ?? trace.output ?? "0x", 32);
    if (traceReturn !== callReturn) throw new Error("eth_call return and transaction trace return differ");
    const logs = receiptLogs(receipt);
    if (logs.length === 0) throw new Error("successful LIQUIDATE emitted no logs");
    const finalLog = logs.at(-1);
    const expectedTopics = [
      canonicalFinalTopic, derivedActionId, normalizeHex(`0x${actionKind.toString(16)}`, 32), caseId,
    ];
    if (finalLog.emitter !== token.address || JSON.stringify(finalLog.topics) !== JSON.stringify(expectedTopics)) {
      throw new Error("final RegulatoryActionApplied emitter/topics mismatch");
    }
    if (normalizeHex(finalLog.data, 32) !== callReturn) throw new Error("final log data differs from return receipt");

    const slots = receiptSlots(derivedActionId);
    const zeroStorage = normalizeHex("0x", 32);
    const preActionReceipt = normalizeHex(await rpc("eth_getStorageAt", [token.address, slots.actionRecordReceiptSlot, preBlock.number]), 32);
    const preReceiptRecord = normalizeHex(await rpc("eth_getStorageAt", [token.address, slots.receiptRecordReceiptSlot, preBlock.number]), 32);
    const postActionReceipt = normalizeHex(await rpc("eth_getStorageAt", [token.address, slots.actionRecordReceiptSlot, "latest"]), 32);
    const postReceiptRecord = normalizeHex(await rpc("eth_getStorageAt", [token.address, slots.receiptRecordReceiptSlot, "latest"]), 32);
    if (preActionReceipt !== zeroStorage || preReceiptRecord !== zeroStorage) throw new Error("receipt storage was nonzero before LIQUIDATE");
    if (postActionReceipt !== callReturn || postReceiptRecord !== callReturn) {
      throw new Error("committed action/receipt storage differs from return receipt");
    }

    const accessed = traceAccessSummary(trace, token.address);
    const ports = {
      ACCESSED_ACCOUNTS_K: ".Set",
      ACCESSED_STORAGE_K: ".Map",
      BLOCK_GAS_LIMIT_INT: BigInt(actionBlock.gasLimit).toString(),
      BLOCK_NUMBER_INT: BigInt(actionBlock.number).toString(),
      CALLDATA_HEX: calldataHex,
      COMPLETE_LOG_LIST_K: completeLogsK(logs),
      POST_ACCOUNTS_K: accountsK(postAccounts, token.address, dependency.address),
      PRE_ACCOUNTS_K: accountsK(preAccounts, token.address, dependency.address),
      RETURN_PAYLOAD_HEX: callReturn,
      SENDER_INT: BigInt(sender).toString(),
      SENDER_NONCE_BEFORE_INT: senderNonceBefore.toString(),
      TIMESTAMP_INT: BigInt(actionBlock.timestamp).toString(),
      TOKEN_ADDRESS_INT: BigInt(token.address).toString(),
      TX_GAS_LIMIT_INT: BigInt(transaction.gas).toString(),
    };

    const fixture = {
      schemaVersion: 1,
      obligationId: "SEP-04",
      status: "OPEN",
      eligibleForDischarge: false,
      claimBoundary: "Pinned deterministic Anvil full-transaction capture only; no KEVM or Isabelle proof was run.",
      compilerRuntimeIdentity: {
        schedule: "CANCUN",
        kevmDefinitionRevision: lock.components.kevmSemantics.commit,
        solcVersion: lock.components.solc.version,
        solcBinarySha256: solcSha256,
        compilerOutputPath: repoPath(compilerOutputPath),
        compilerOutputSha256: sha256(readFileSync(compilerOutputPath)),
        dependencyLockPath: repoPath(lockPath),
        dependencyLockSha256: sha256(readFileSync(lockPath)),
        trustTokenRuntimeSha256: token.runtimeSha256,
        trustTokenRuntimeByteLength: token.runtimeByteLength,
        dependencyRuntimeSha256: dependency.runtimeSha256,
        dependencyRuntimeByteLength: dependency.runtimeByteLength,
      },
      tools: { anvilVersion, forgeVersion, castVersion },
      chain: {
        rpcScope: "ephemeral localhost only",
        chainId,
        hardfork: "cancun",
        genesisTimestamp,
        preBlockNumber: Number(BigInt(preBlock.number)),
        actionBlockNumber: Number(BigInt(actionBlock.number)),
        actionBlockHash: actionBlock.hash,
        actionBlockStateRoot: actionBlock.stateRoot,
        actionBlockTimestamp: Number(BigInt(actionBlock.timestamp)),
        blockGasLimit: Number(BigInt(actionBlock.gasLimit)),
      },
      deployments: { dependency, token },
      transaction: {
        hash: transactionHash,
        sender,
        senderNonceBefore: senderNonceBefore.toString(),
        senderNonceAfter: senderNonceAfter.toString(),
        tokenAddress: token.address,
        dependencyAddress: dependency.address,
        calldataHex,
        gasLimit: BigInt(transaction.gas).toString(),
        gasUsed: BigInt(receipt.gasUsed).toString(),
        value: BigInt(transaction.value).toString(),
        type: transaction.type,
        status: receipt.status,
      },
      request,
      preState: {
        accounts: preAccounts,
        canonicalSha256: stateHash(preAccounts),
      },
      postState: {
        accounts: postAccounts,
        canonicalSha256: stateHash(postAccounts),
      },
      trace: {
        failed: trace.failed,
        gas: trace.gas,
        returnValue: traceReturn,
        structLogCount: trace.structLogs?.length ?? 0,
        canonicalSha256: sha256(Buffer.from(JSON.stringify(stable(trace)), "utf8")),
        accessedBeforeFinalize: accessed,
        terminalAccessPorts: {
          accessedAccounts: ".Set",
          accessedStorage: ".Map",
          reason: "Pinned KEVM #finalizeTx(true, _) clears both cells before #finalizeBlock.",
        },
      },
      observations: {
        receiptHash: callReturn,
        ethCallReturnPayloadHex: callReturn,
        returnPayloadHex: traceReturn,
        actionRecordReceiptHash: postActionReceipt,
        receiptRecordReceiptHash: postReceiptRecord,
        completeLogs: logs,
        completeLogsK: ports.COMPLETE_LOG_LIST_K,
        finalLogEmitter: finalLog.emitter,
        finalLogTopics: finalLog.topics,
        finalLogDataHex: finalLog.data,
      },
      storageObservations: {
        storageLayoutDerived: true,
        actionRecordReceiptSlot: slots.actionRecordReceiptSlot,
        receiptRecordReceiptSlot: slots.receiptRecordReceiptSlot,
        preActionRecordReceiptHash: preActionReceipt,
        preReceiptRecordReceiptHash: preReceiptRecord,
        actionRecordReceiptHash: postActionReceipt,
        receiptRecordReceiptHash: postReceiptRecord,
      },
      ports,
      independentChecks: {
        calldataDecodesExactly: false,
        prePostStorageDiffEnumerated: true,
        returnEqualsActionRecordReceipt: true,
        returnEqualsReceiptRecordReceipt: true,
        returnEqualsFinalLogData: true,
        finalLogIsLast: true,
        runtimeAndDependencyHashesPinned: true,
        independentlyVerified: false,
      },
      captureDiagnostics: {
        anvilPort: port,
        serverStderrSha256: sha256(Buffer.from(serverStderr, "utf8")),
      },
    };
    writeFileSync(fixturePath, `${JSON.stringify(stable(fixture), null, 2)}\n`, "utf8");
    console.log(JSON.stringify({
      status: "CAPTURE_PASS_OPEN",
      fixture: repoPath(fixturePath),
      fixtureSha256: sha256(readFileSync(fixturePath)),
      transactionHash,
      receiptHash: callReturn,
      logCount: logs.length,
      accountCount: Object.keys(postAccounts).length,
      portCount: Object.keys(ports).length,
    }, null, 2));
  } finally {
    server.kill();
  }
} catch (error) {
  console.error(error.stack ?? String(error));
  process.exitCode = 1;
}
