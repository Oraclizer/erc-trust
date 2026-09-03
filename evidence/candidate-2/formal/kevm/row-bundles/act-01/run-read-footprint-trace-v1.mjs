// ACT-01 proof-free read-footprint trace (v1).
//
// usage:
//   node run-read-footprint-trace-v1.mjs --state-capture-root <feasibility output root> --output-root <new absolute directory> [--port 18546]
//
// What it does (no proof backend, no credit):
//   1. starts a WSL anvil from the captured canonical prestate dump (anvil --load-state),
//   2. pins the next block timestamp to the captured block timestamp,
//   3. replays the captured calldata from the captured sender to the captured endpoint,
//   4. asks anvil for the transaction trace and collects every storage slot that was read or written
//      (prestateTracer in diff mode, with a structLog fallback) and every account the transaction touched,
//   5. checks that every token storage slot the runtime read or wrote lies inside the declared 88-key footprint,
//      that the replayed post storage equals the captured post storage, and that every touched account is one of the
//      named claim accounts (sender, token, dependency, coinbase),
//   6. stops anvil and records a zero-process census.
// The result is an input to the initial-frame contract; it is not a discharge, proof, or replay credit.

import { execFileSync, spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";

const argValue = (flag) => {
  const index = process.argv.indexOf(flag);
  return index >= 0 ? process.argv[index + 1] : undefined;
};
const captureRoot = argValue("--state-capture-root");
const outputRootArg = argValue("--output-root");
const port = Number(argValue("--port") ?? "18546");
const captureBoundaries = process.argv.includes("--capture-boundaries");
const skipEvidenceWrite = process.argv.includes("--skip-evidence-write");
if (!captureRoot || !outputRootArg) {
  throw new Error("usage: node run-read-footprint-trace-v1.mjs --state-capture-root <path> --output-root <new absolute dir> [--port N]");
}
const outputRoot = resolve(outputRootArg);
if (!/^[A-Za-z]:[\\/]/.test(outputRootArg) && !outputRootArg.startsWith("/")) throw new Error("output root must be absolute");
if (existsSync(outputRoot)) throw new Error(`output root already exists: ${outputRoot}`);

const repositoryRoot = resolve(import.meta.dirname, "../../../..");
const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const fileSha256 = (path) => sha256(readFileSync(path));
const hexKey = (value) => `0x${BigInt(value).toString(16).padStart(64, "0")}`;
const sortedHex = (iterable) => [...new Set([...iterable].map(hexKey))].sort();

const result = JSON.parse(readFileSync(resolve(captureRoot, "result.json"), "utf8"));
if (result.status !== "PASS_FULL_TRANSACTION_FEASIBILITY_NO_CREDIT") throw new Error("state-capture result is not PASS");
const prePath = resolve(captureRoot, result.canonical.preStatePath);
const postPath = resolve(captureRoot, result.canonical.postStatePath);
const pre = JSON.parse(readFileSync(prePath, "utf8"));
const post = JSON.parse(readFileSync(postPath, "utf8"));
const tokenAddress = result.canonical.endpoint.toLowerCase();
const senderAddress = "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266";
const dependencyAddress = "0x5fbdb2315678afecb367f032d93f642f64180aa3";
const coinbaseAddress = "0x0000000000000000000000000000000000000000";
const namedAccounts = new Set([senderAddress, tokenAddress, dependencyAddress, coinbaseAddress]);
const preStorage = pre.accounts[tokenAddress].storage;
const postStorage = post.accounts[tokenAddress].storage;
const footprint = new Set(sortedHex([...Object.keys(preStorage), ...Object.keys(postStorage)]));
if (footprint.size !== 88) throw new Error(`footprint size drift: ${footprint.size}`);
const capturedBlock = post.blocks.at(-1);
const capturedTimestamp = BigInt(capturedBlock.header.timestamp);
const capturedGasUsed = BigInt(result.canonical.gasUsed);
const calldata = result.canonical.calldataHex.toLowerCase();

function wslPath(path) {
  return execFileSync("wsl.exe", ["-d", "Ubuntu", "-e", "wslpath", "-a", path], { encoding: "utf8" }).trim();
}
const rpcUrl = `http://127.0.0.1:${port}`;
let rpcId = 0;
async function rpcResponse(method, params) {
  const response = await fetch(rpcUrl, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: ++rpcId, method, params }),
  });
  const text = await response.text();
  return JSON.parse(text);
}
async function rpc(method, params) {
  const payload = await rpcResponse(method, params);
  if (payload.error) throw new Error(`${method}: ${JSON.stringify(payload.error)}`);
  return payload.result;
}
const sleep = (ms) => new Promise((done) => setTimeout(done, ms));

mkdirSync(outputRoot, { recursive: true });
const census = (label) => {
  let windows = "";
  let wsl = "";
  try { windows = execFileSync("tasklist.exe", [], { encoding: "utf8" }); } catch { windows = ""; }
  try { wsl = execFileSync("wsl.exe", ["-d", "Ubuntu", "-e", "bash", "-lc", "pgrep -af '[a]nvil' || true"], { encoding: "utf8" }); } catch { wsl = ""; }
  const windowsCount = windows.split(/\r?\n/).filter((line) => /^anvil/i.test(line)).length;
  const wslCount = wsl.split(/\r?\n/).filter((line) => line.trim().length > 0).length;
  return { label, windowsAnvilProcessCount: windowsCount, wslAnvilProcessCount: wslCount };
};

const beforeCensus = census("before");
let server = null;
let report = null;
try {
  try {
    await rpc("eth_blockNumber", []);
    throw new Error(`port already in use: ${rpcUrl}`);
  } catch (error) {
    if (String(error.message).includes("already in use")) throw error;
  }
  const anvilArgs = [
    "-d", "Ubuntu", "-e", "anvil", "--silent", "--port", String(port), "--chain-id", "31337", "--hardfork", "cancun",
    "--load-state", wslPath(prePath),
  ];
  if (captureBoundaries) anvilArgs.push("--steps-tracing");
  server = spawn("wsl.exe", anvilArgs, { windowsHide: true, stdio: ["ignore", "pipe", "pipe"] });
  let stderr = "";
  server.stderr.on("data", (chunk) => { stderr += String(chunk); });
  let started = false;
  for (let attempt = 0; attempt < 300; attempt += 1) {
    if (server.exitCode !== null) throw new Error(`anvil exited early: ${server.exitCode} ${stderr.slice(0, 400)}`);
    try {
      const block = await rpc("eth_blockNumber", []);
      if (BigInt(block) === BigInt(pre.best_block_number)) { started = true; break; }
      throw new Error(`unexpected loaded block number ${block}`);
    } catch (error) {
      if (String(error.message).startsWith("unexpected loaded block number")) throw error;
    }
    await sleep(100);
  }
  if (!started) throw new Error("anvil startup timeout");

  const loadedTokenCode = await rpc("eth_getCode", [tokenAddress, "latest"]);
  const loadedSenderNonce = BigInt(await rpc("eth_getTransactionCount", [senderAddress, "latest"]));
  // Pin the replay block timestamp to the captured one. A loaded chain keeps a wall-clock time source, so the
  // internal clock is moved back first; every attempt is recorded and the check below reports the outcome.
  const timestampPinning = [];
  for (const attempt of [
    () => rpc("evm_setNextBlockTimestamp", [`0x${capturedTimestamp.toString(16)}`]),
    async () => { await rpc("evm_setTime", [Number(capturedTimestamp - 1n)]); return rpc("evm_setNextBlockTimestamp", [`0x${capturedTimestamp.toString(16)}`]); },
    async () => { await rpc("anvil_setTime", [Number(capturedTimestamp - 1n)]); return rpc("evm_setNextBlockTimestamp", [`0x${capturedTimestamp.toString(16)}`]); },
  ]) {
    try { await attempt(); timestampPinning.push("ok"); break; } catch (error) { timestampPinning.push(String(error.message).slice(0, 160)); }
  }
  const txHash = await rpc("eth_sendTransaction", [{ from: senderAddress, to: tokenAddress, data: calldata, gas: "0xe4e1c0" }]);
  let receipt = null;
  for (let attempt = 0; attempt < 100 && !receipt; attempt += 1) {
    receipt = await rpc("eth_getTransactionReceipt", [txHash]);
    if (!receipt) await sleep(100);
  }
  if (!receipt) throw new Error("receipt timeout");
  const minedBlock = await rpc("eth_getBlockByNumber", [receipt.blockNumber, false]);

  // Replayed post state.
  const { gunzipSync } = await import("node:zlib");
  const dumpHex = await rpc("anvil_dumpState", []);
  const replayPost = JSON.parse(gunzipSync(Buffer.from(dumpHex.replace(/^0x/, ""), "hex")).toString("utf8"));
  const replayStorage = replayPost.accounts[tokenAddress].storage;
  const normalize = (storage) => Object.fromEntries(Object.entries(storage).map(([key, value]) => [hexKey(key), hexKey(value)]).sort(([a], [b]) => a < b ? -1 : 1));
  const capturedPostNormalized = normalize(postStorage);
  const replayPostNormalized = normalize(replayStorage);
  const postStorageEqual = JSON.stringify(capturedPostNormalized) === JSON.stringify(replayPostNormalized);

  // Trace: prestateTracer (diff mode gives read-or-written pre values plus written post values).
  let tracerUsed = null;
  let touchedAccounts = new Set();
  let tokenAccessedKeys = new Set();
  let tokenWrittenKeys = new Set();
  let dependencyAccessedKeys = new Set();
  let otherAccessedStorage = {};
  let rawTracePath = null;
  let structLogSummary = null;
  const prestateDiff = await rpcResponse("debug_traceTransaction", [txHash, { tracer: "prestateTracer", tracerConfig: { diffMode: true } }]);
  const prestateFull = await rpcResponse("debug_traceTransaction", [txHash, { tracer: "prestateTracer", tracerConfig: { diffMode: false } }]);
  if (!prestateDiff.error && !prestateFull.error && prestateFull.result && typeof prestateFull.result === "object") {
    tracerUsed = "prestateTracer";
    rawTracePath = resolve(outputRoot, "prestate-tracer.json");
    writeFileSync(rawTracePath, `${JSON.stringify({ full: prestateFull.result, diff: prestateDiff.result }, null, 2)}\n`);
    for (const [address, state] of Object.entries(prestateFull.result)) {
      const lower = address.toLowerCase();
      touchedAccounts.add(lower);
      const storage = state.storage ?? {};
      const keys = Object.keys(storage);
      if (lower === tokenAddress) keys.forEach((key) => tokenAccessedKeys.add(hexKey(key)));
      else if (lower === dependencyAddress) keys.forEach((key) => dependencyAccessedKeys.add(hexKey(key)));
      else if (keys.length > 0) otherAccessedStorage[lower] = sortedHex(keys);
    }
    const diffPost = prestateDiff.result?.post ?? {};
    for (const [address, state] of Object.entries(diffPost)) {
      if (address.toLowerCase() === tokenAddress) Object.keys(state.storage ?? {}).forEach((key) => tokenWrittenKeys.add(hexKey(key)));
    }
  }
  // Fallback or cross-check with structLogs (stack only).
  let structPayload = await rpcResponse("debug_traceTransaction", [txHash, captureBoundaries
    ? { disableStorage: false, disableMemory: false, disableStack: false, enableReturnData: true }
    : { disableStorage: true, disableMemory: true, enableMemory: false, disableStack: false, enableReturnData: false }]);
  if (captureBoundaries && !structPayload.error && Array.isArray(structPayload.result?.structLogs) && structPayload.result.structLogs.length === 0) {
    structPayload = await rpcResponse("debug_traceTransaction", [txHash, {}]);
  }
  if (!structPayload.error && structPayload.result && Array.isArray(structPayload.result.structLogs)) {
    const logs = structPayload.result.structLogs;
    const context = { 1: tokenAddress };
    let pending = null;
    const reads = {};
    const writes = {};
    const transientOps = [];
    const accountTargets = {};
    const calls = [];
    let createSeen = 0;
    const addKey = (bucket, address, key) => { (bucket[address] ??= new Set()).add(hexKey(key)); };
    for (let index = 0; index < logs.length; index += 1) {
      const entry = logs[index];
      const depth = entry.depth;
      if (pending && depth === pending.depth) { context[depth] = pending.address; pending = null; }
      else if (pending && depth < pending.depth) pending = null;
      const address = context[depth] ?? null;
      const stack = entry.stack ?? [];
      const top = stack.length > 0 ? stack[stack.length - 1] : null;
      const second = stack.length > 1 ? stack[stack.length - 2] : null;
      switch (entry.op) {
        case "SLOAD": addKey(reads, address, top); break;
        case "SSTORE": addKey(writes, address, top); break;
        case "TLOAD": case "TSTORE": transientOps.push({ op: entry.op, address, key: hexKey(top) }); break;
        case "BALANCE": case "EXTCODESIZE": case "EXTCODEHASH": case "EXTCODECOPY":
          (accountTargets[entry.op] ??= new Set()).add(`0x${BigInt(top).toString(16).padStart(40, "0")}`); break;
        case "SELFBALANCE": (accountTargets.SELFBALANCE ??= new Set()).add(address); break;
        case "CALL": case "CALLCODE": case "DELEGATECALL": case "STATICCALL": {
          const callee = `0x${BigInt(second).toString(16).padStart(40, "0")}`;
          calls.push({ op: entry.op, from: address, to: callee, depth });
          (accountTargets[entry.op] ??= new Set()).add(callee);
          pending = { depth: depth + 1, address: entry.op === "DELEGATECALL" || entry.op === "CALLCODE" ? address : callee };
          break;
        }
        case "CREATE": case "CREATE2": createSeen += 1; pending = { depth: depth + 1, address: "0xcreate" }; break;
        default: break;
      }
    }
    const setsToSorted = (bucket) => Object.fromEntries(Object.entries(bucket).map(([k, v]) => [k, [...v].sort()]));
    structLogSummary = {
      stepCount: logs.length,
      maxDepth: Math.max(...logs.map((entry) => entry.depth)),
      reads: setsToSorted(reads),
      writes: setsToSorted(writes),
      transientOps,
      accountTargets: setsToSorted(accountTargets),
      calls,
      createSeen,
      failed: structPayload.result.failed ?? null,
      gas: structPayload.result.gas ?? null,
    };
    const structPath = resolve(outputRoot, "struct-log-summary.json");
    writeFileSync(structPath, `${JSON.stringify(structLogSummary, null, 2)}\n`);
    if (captureBoundaries) {
      const boundaryPcs = new Set([
        0, 925, 1869, 2030, 2771, 2819, 2828, 2838, 3190, 3201,
        3477, 3525, 3570, 3576, 4021, 4029, 4507, 4515,
        11194, 12870, 13052, 13431, 13446, 13465, 13487, 13500,
        13507, 13527, 13544, 13558, 13574, 13592, 13609, 13627,
        13643, 13660, 13678, 13695, 13712, 13718, 13736, 13751,
        13758, 15042, 15051, 15087, 15165, 15187, 15195, 15217,
        15224, 15242, 15257, 15275, 15368, 16091, 17399, 22370,
        22384, 22402, 22527,
        21482, 21532, 21899, 21900, 21907, 22051, 22149, 22155, 22251,
      ]);
      const snapshots = [];
      const boundaryContext = { 1: tokenAddress };
      let boundaryPending = null;
      const currentStorage = Object.fromEntries(Object.entries(prestateFull.result).map(([address, state]) => [
        address.toLowerCase(),
        normalize(state.storage ?? {}),
      ]));
      for (let index = 0; index < logs.length; index += 1) {
        const entry = logs[index];
        const depth = entry.depth;
        if (boundaryPending && depth === boundaryPending.depth) {
          boundaryContext[depth] = boundaryPending.address;
          boundaryPending = null;
        } else if (boundaryPending && depth < boundaryPending.depth) {
          boundaryPending = null;
        }
        const address = boundaryContext[depth] ?? null;
        const stack = entry.stack ?? [];
        const top = stack.length > 0 ? stack[stack.length - 1] : null;
        const second = stack.length > 1 ? stack[stack.length - 2] : null;
        if (entry.op === "SSTORE" && address && top !== null && second !== null) {
          (currentStorage[address] ??= {})[hexKey(top)] = hexKey(second);
        }
        if (!boundaryPcs.has(entry.pc)) continue;
        snapshots.push({
          index,
          pc: entry.pc,
          op: entry.op,
          depth,
          address,
          gas: entry.gas ?? null,
          gasCost: entry.gasCost ?? null,
          stack,
          memory: entry.memory ?? null,
          tokenStorage: currentStorage[tokenAddress]
            ? Object.fromEntries(Object.entries(currentStorage[tokenAddress]).sort(([left], [right]) => left.localeCompare(right)))
            : null,
          returnData: entry.returnData ?? null,
          previous: index > 0 ? { pc: logs[index - 1].pc, op: logs[index - 1].op, depth: logs[index - 1].depth } : null,
          next: index + 1 < logs.length ? { pc: logs[index + 1].pc, op: logs[index + 1].op, depth: logs[index + 1].depth } : null,
        });
        if (["CALL", "CALLCODE", "DELEGATECALL", "STATICCALL"].includes(entry.op) && second !== null) {
          const callee = `0x${BigInt(second).toString(16).padStart(40, "0")}`;
          boundaryPending = {
            depth: depth + 1,
            address: entry.op === "DELEGATECALL" || entry.op === "CALLCODE" ? address : callee,
          };
        }
      }
      writeFileSync(resolve(outputRoot, "struct-log-boundaries.json"), `${JSON.stringify({
        txHash,
        stepCount: logs.length,
        requestedPcs: [...boundaryPcs].sort((left, right) => left - right),
        snapshots,
      }, null, 2)}\n`);
    }
    if (!tracerUsed) {
      tracerUsed = "structLogs";
      rawTracePath = structPath;
      (reads[tokenAddress] ?? new Set()).forEach((key) => tokenAccessedKeys.add(key));
      (writes[tokenAddress] ?? new Set()).forEach((key) => { tokenAccessedKeys.add(key); tokenWrittenKeys.add(key); });
      (reads[dependencyAddress] ?? new Set()).forEach((key) => dependencyAccessedKeys.add(key));
      for (const target of Object.values(accountTargets)) target.forEach((addr) => touchedAccounts.add(addr));
      touchedAccounts.add(senderAddress); touchedAccounts.add(tokenAddress);
    }
  }
  if (!tracerUsed) throw new Error(`no usable trace: ${JSON.stringify(prestateFull.error ?? structPayload.error).slice(0, 300)}`);

  const tokenAccessed = [...tokenAccessedKeys].sort();
  const tokenWritten = [...tokenWrittenKeys].sort();
  const readsOutsideFootprint = tokenAccessed.filter((key) => !footprint.has(key));
  const writesOutsideFootprint = tokenWritten.filter((key) => !footprint.has(key));
  const structReads = structLogSummary ? (structLogSummary.reads[tokenAddress] ?? []) : null;
  const structWrites = structLogSummary ? (structLogSummary.writes[tokenAddress] ?? []) : null;
  const structReadsOutside = structReads ? structReads.filter((key) => !footprint.has(key)) : null;
  const structWritesOutside = structWrites ? structWrites.filter((key) => !footprint.has(key)) : null;
  const touched = [...touchedAccounts].sort();
  const touchedOutsideNamed = touched.filter((address) => !namedAccounts.has(address));
  const structTargets = structLogSummary ? [...new Set(Object.values(structLogSummary.accountTargets).flat())].sort() : [];
  const structTargetsOutsideNamed = structTargets.filter((address) => !namedAccounts.has(address));
  const capturedTopics = receipt.logs.map((entry) => entry.topics[0].toLowerCase());
  const expectedTopics = result.canonical.committedLogTopics.map((topic) => topic.toLowerCase());

  const checks = {
    loadedStateBlockNumber: BigInt(pre.best_block_number) === 3n,
    loadedTokenCodeMatchesCapture: sha256(Buffer.from(loadedTokenCode.replace(/^0x/, ""), "hex")) === result.runtime.canonicalSha256,
    loadedSenderNonceMatchesCapture: loadedSenderNonce === BigInt(result.canonical.senderNonceBefore),
    replayMinedAtCapturedTimestamp: BigInt(minedBlock.timestamp) === capturedTimestamp,
    replayStatusSuccess: receipt.status === "0x1",
    replayGasUsedMatchesCapture: BigInt(receipt.gasUsed) === capturedGasUsed,
    replayLogTopicsMatchCapture: JSON.stringify(capturedTopics) === JSON.stringify(expectedTopics),
    replayPostStorageEqualsCapture: postStorageEqual,
    tokenReadsWithinFootprint: readsOutsideFootprint.length === 0,
    tokenWritesWithinFootprint: writesOutsideFootprint.length === 0,
    structLogReadsWithinFootprint: structReadsOutside === null ? null : structReadsOutside.length === 0,
    structLogWritesWithinFootprint: structWritesOutside === null ? null : structWritesOutside.length === 0,
    touchedAccountsWithinNamed: touchedOutsideNamed.length === 0,
    structLogAccountTargetsWithinNamed: structTargetsOutsideNamed.length === 0,
    noTransientStorage: structLogSummary ? structLogSummary.transientOps.length === 0 : null,
    noCreate: structLogSummary ? structLogSummary.createSeen === 0 : null,
    dependencyStorageReadsEmptyOrNamed: true,
  };
  const status = Object.values(checks).every((value) => value !== false) ? "PASS_READ_FOOTPRINT_WITHIN_88_KEYS_NO_CREDIT" : "FAIL_READ_FOOTPRINT_OR_REPLAY_MISMATCH_NO_CREDIT";
  report = {
    schemaVersion: 1,
    kind: "ACT01_READ_FOOTPRINT_TRACE_V1",
    obligationId: "ACT-01",
    status,
    classification: "PROOF_FREE_TRACE_NO_CREDIT",
    outputRootRef: `external-scratch/${outputRoot.replace(/\\/g, "/").split("/").pop()}`,
    inputs: {
      captureResultRef: "external-scratch/erc-trust-m4-wave4-act01-full-transaction-feasibility-v1-002/result.json",
      captureResultSha256: fileSha256(resolve(captureRoot, "result.json")),
      preStateSha256: fileSha256(prePath),
      postStateSha256: fileSha256(postPath),
      calldataSha256: result.canonical.calldataSha256,
      capturedTimestamp: capturedTimestamp.toString(),
      capturedGasUsed: capturedGasUsed.toString(),
    },
    anvil: { distribution: "Ubuntu", port, tracerUsed, rawTraceSha256: rawTracePath ? fileSha256(rawTracePath) : null },
    replay: {
      txHash,
      blockNumber: receipt.blockNumber,
      status: receipt.status,
      gasUsed: BigInt(receipt.gasUsed).toString(),
      logTopics: capturedTopics,
      postStorageEqual,
    },
    footprint: {
      declaredKeyCount: footprint.size,
      tokenAccessedKeyCount: tokenAccessed.length,
      tokenWrittenKeyCount: tokenWritten.length,
      tokenAccessedKeys: tokenAccessed,
      tokenWrittenKeys: tokenWritten,
      readsOutsideFootprint,
      writesOutsideFootprint,
      structLogTokenReadKeyCount: structReads ? structReads.length : null,
      structLogTokenWriteKeyCount: structWrites ? structWrites.length : null,
      structLogReadsOutsideFootprint: structReadsOutside,
      structLogWritesOutsideFootprint: structWritesOutside,
      dependencyAccessedKeys: [...dependencyAccessedKeys].sort(),
      otherAccessedStorage,
    },
    accounts: {
      named: [...namedAccounts].sort(),
      touched,
      touchedOutsideNamed,
      structLogAccountTargets: structTargets,
      structLogAccountTargetsOutsideNamed: structTargetsOutsideNamed,
      structLogCalls: structLogSummary ? structLogSummary.calls : null,
    },
    checks,
    proofExecuted: false,
    proofCredit: false,
    centralCredit: false,
  };
} finally {
  if (server && server.exitCode === null) {
    try { execFileSync("wsl.exe", ["-d", "Ubuntu", "-e", "bash", "-lc", "pkill -TERM -f '[a]nvil --silent --port " + port + "' || true"], { encoding: "utf8" }); } catch {}
    try { server.kill(); } catch {}
    await sleep(1500);
  }
}
const afterCensus = census("after");
report.processCensus = { before: beforeCensus, after: afterCensus };
if (afterCensus.windowsAnvilProcessCount !== 0 || afterCensus.wslAnvilProcessCount !== 0) report.status = `${report.status}_BUT_ANVIL_SURVIVOR`;
const reportPath = resolve(outputRoot, "result.json");
writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`);
const evidencePath = resolve(repositoryRoot, "evidence/end-to-end-refinement/row-bundles/act-01/read-footprint-trace-v1.json");
if (!skipEvidenceWrite) writeFileSync(evidencePath, `${JSON.stringify(report, null, 2)}\n`);
process.stdout.write(`${JSON.stringify({ status: report.status, tracerUsed: report.anvil.tracerUsed, checks: report.checks, readsOutsideFootprint: report.footprint.readsOutsideFootprint, writesOutsideFootprint: report.footprint.writesOutsideFootprint, touchedOutsideNamed: report.accounts.touchedOutsideNamed, census: report.processCensus.after }, null, 2)}\n`);
