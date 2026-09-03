#!/usr/bin/env node
// One-process/one-session ABI-04 replay launcher for the 81-claim exact row.
// S1 remains on its frozen v4 launcher; this launcher owns only row-wide v1
// records and records sufficient immutable inputs for dual independent review.
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { spawn, spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const scriptPath = fileURLToPath(import.meta.url);
const familyDir = path.dirname(scriptPath);
const rowDir = path.dirname(familyDir);
const repositoryRoot = path.resolve(rowDir, "../../../..");
const indexPath = path.join(familyDir, "full-row-replay-index-v1.json");
const analyzerPath = path.join(familyDir, "analyze-abi-04-replay-v1.mjs");
const verifierPath = path.join(familyDir, "verify_abi_04_replay_v1.py");
const freezeVerifierPath = path.join(rowDir, "anti-drift", "verify-freeze-receipt.py");
const toolchainContractPath = path.join(rowDir, "dynamic-offset-v1", "s1-toolchain-contract-v1.json");

const sha256 = (value) => crypto.createHash("sha256").update(value).digest("hex");
const fileSha256 = (filePath) => sha256(fs.readFileSync(filePath));
const readJson = (filePath) => JSON.parse(fs.readFileSync(filePath, "utf8"));
const writeText = (filePath, value) => fs.writeFileSync(filePath, `${value}\n`, "utf8");
const writeJson = (filePath, value) => fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
const writeJsonAtomic = (filePath, value) => {
  const temporaryPath = `${filePath}.tmp-${process.pid}`;
  writeJson(temporaryPath, value);
  fs.renameSync(temporaryPath, filePath);
};
const posix = (value) => path.relative(repositoryRoot, value).split(path.sep).join("/");
const absolute = (value) => {
  assert.equal(path.isAbsolute(value), false, `repository binding must be relative: ${value}`);
  const resolved = path.resolve(repositoryRoot, ...value.split("/"));
  assert.ok(resolved.startsWith(`${repositoryRoot}${path.sep}`), `repository binding escapes root: ${value}`);
  return resolved;
};
const sleep = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));
const verifySourceBindings = (value, label = "sourceBinding") => {
  if (Array.isArray(value)) return value.forEach((item, index) => verifySourceBindings(item, `${label}/${index}`));
  if (!value || typeof value !== "object") return;
  if (typeof value.path === "string" && typeof value.sha256 === "string") requireHash(absolute(value.path), value.sha256, label);
  for (const [key, child] of Object.entries(value)) verifySourceBindings(child, `${label}/${key}`);
};

function parseArgs(argv) {
  const args = { mode: null, replayId: null, outputRoot: null, closureRoot: null, python: "/usr/bin/python3.14", preverifiedClosureWorkerSha256: null, preverifiedClosureHashSha256: null };
  for (let i = 0; i < argv.length; i += 1) {
    const value = argv[i];
    if (value === "--run" || value === "--print-command") args.mode = value.slice(2);
    else if (value === "--replay-id") args.replayId = argv[++i];
    else if (value === "--output-root") args.outputRoot = argv[++i];
    else if (value === "--closure-freeze-root") args.closureRoot = argv[++i];
    else if (value === "--python") args.python = argv[++i];
    else if (value === "--preverified-closure-worker-sha256") args.preverifiedClosureWorkerSha256 = argv[++i];
    else if (value === "--preverified-closure-hash-sha256") args.preverifiedClosureHashSha256 = argv[++i];
    else throw new Error(`unknown argument: ${value}`);
  }
  assert.ok(["run", "print-command"].includes(args.mode), "use --run or --print-command");
  for (const [name, value] of [["replay id", args.replayId], ["output root", args.outputRoot], ["closure freeze root", args.closureRoot]]) assert.ok(value, `missing ${name}`);
  assert.ok(path.isAbsolute(args.outputRoot), "output root must be absolute");
  assert.ok(path.isAbsolute(args.closureRoot), "closure freeze root must be absolute");
  assert.equal(Boolean(args.preverifiedClosureWorkerSha256), Boolean(args.preverifiedClosureHashSha256), "preverified closure hashes must be supplied together");
  if (args.preverifiedClosureWorkerSha256) {
    assert.equal(args.mode, "print-command", "preverified closure shortcut is proof-free print-command only");
    assert.match(args.preverifiedClosureWorkerSha256, /^[0-9a-f]{64}$/);
    assert.match(args.preverifiedClosureHashSha256, /^[0-9a-f]{64}$/);
  }
  return args;
}

function walkFiles(directory) {
  const files = [];
  const visit = (current) => {
    for (const entry of fs.readdirSync(current, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
      const target = path.join(current, entry.name);
      if (entry.isDirectory()) visit(target);
      else if (entry.isFile()) files.push(target);
    }
  };
  visit(directory);
  return files;
}

function treeManifest(directory) {
  return walkFiles(directory).map((filePath) => ({
    path: path.relative(directory, filePath).split(path.sep).join("/"),
    sha256: fileSha256(filePath),
    bytes: fs.statSync(filePath).size,
  }));
}

function runJson(command, commandArgs, label) {
  const result = spawnSync(command, commandArgs, { cwd: repositoryRoot, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  assert.notEqual(result.status, null, `${label} did not start`);
  assert.equal(result.status, 0, `${label} failed: ${result.stderr || result.stdout}`);
  return JSON.parse(result.stdout);
}

function requireHash(filePath, expected, label) {
  assert.ok(fs.existsSync(filePath), `missing ${label}: ${filePath}`);
  assert.equal(fileSha256(filePath), expected, `${label} SHA-256 mismatch`);
}

function processIdentity(psExecutable, pid) {
  const result = spawnSync(psExecutable, ["-o", "pid=,ppid=,sid=,pgid=,stat=,comm=", "-p", String(pid)], { encoding: "utf8" });
  return result.status === 0 ? result.stdout.trim() : "";
}

function parseProcessIdentity(identity) {
  const columns = identity.trim().split(/\s+/);
  assert.ok(columns.length >= 6, `malformed process identity: ${identity}`);
  const parsed = { raw: identity, pid: Number(columns[0]), ppid: Number(columns[1]), sid: Number(columns[2]), pgid: Number(columns[3]), stat: columns[4], comm: columns.slice(5).join(" ") };
  for (const key of ["pid", "ppid", "sid", "pgid"]) assert.ok(Number.isSafeInteger(parsed[key]) && parsed[key] >= 0, `invalid process identity ${key}`);
  return parsed;
}

function sessionProcesses(psExecutable, sid) {
  const result = spawnSync(psExecutable, ["-eo", "pid,ppid,sid,pgid,stat,comm"], { encoding: "utf8" });
  assert.equal(result.status, 0, "ps session audit failed");
  const lines = result.stdout.trimEnd().split("\n");
  const matches = lines.slice(1).filter((line) => line.trim().split(/\s+/)[2] === String(sid));
  return [lines[0], ...matches].join("\n") + "\n";
}

function ownedProcessRows(psExecutable, sid, pgid) {
  const result = spawnSync(psExecutable, ["-eo", "pid=,ppid=,sid=,pgid=,stat=,comm="], { encoding: "utf8" });
  assert.equal(result.status, 0, "owned process audit failed");
  return result.stdout.trim().split("\n").filter(Boolean).map(parseProcessIdentity)
    .filter((item) => item.pid === sid || item.sid === sid || item.pgid === pgid);
}

function processStartTimeTicks(pid) {
  const stat = fs.readFileSync(`/proc/${pid}/stat`, "utf8").trim();
  const close = stat.lastIndexOf(")");
  assert.ok(close > 0, `malformed /proc/${pid}/stat`);
  const fieldsFromState = stat.slice(close + 1).trim().split(/\s+/);
  const startTimeTicks = fieldsFromState[19];
  assert.match(startTimeTicks ?? "", /^[0-9]+$/, `missing process start time for PID ${pid}`);
  return startTimeTicks;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const index = readJson(indexPath);
  assert.equal(index.kind, "ABI04_FULL_ROW_REPLAY_INDEX_V1");
  assert.match(args.replayId, /^ABI04-[a-z0-9-]+::(?:canonical-positive|unchanged-claim-mutant-negative)$/);
  verifySourceBindings(index.sourceBinding);
  const matches = index.records.filter((item) => item.replayId === args.replayId);
  assert.equal(matches.length, 1, `replay absent or duplicate in exact index: ${args.replayId}`);
  const record = matches[0];
  const claimPath = absolute(record.claim.path);
  const definition = record.executionSide === "canonical-positive" ? index.definitions.canonicalPositive : index.definitions.mutantNegative;
  const definitionRoot = definition.absoluteRoot;
  const definitionKorePath = path.join(definitionRoot, "definition.kore");
  const compiledJsonPath = path.join(definitionRoot, "compiled.json");
  const closureWorkerPath = path.join(args.closureRoot, "worker-result.json");
  const tools = index.sourceBinding.tools;
  requireHash(scriptPath, tools.runner.sha256, "runner");
  requireHash(analyzerPath, tools.javascriptAnalyzer.sha256, "JavaScript analyzer");
  requireHash(verifierPath, tools.pythonVerifier.sha256, "Python verifier");
  requireHash(freezeVerifierPath, tools.freezeVerifier.sha256, "freeze verifier");
  requireHash(toolchainContractPath, index.sourceBinding.toolchainContract.sha256, "toolchain contract");
  requireHash(claimPath, record.claim.sha256, "claim source");
  requireHash(definitionKorePath, definition.definitionKoreSha256, "definition.kore");
  requireHash(compiledJsonPath, definition.compiledJsonSha256, "compiled.json");
  assert.ok(fs.existsSync(closureWorkerPath), "missing closure freeze worker result");
  const toolchain = index.toolchain;
  const executableToolKeys = ["node", "python", "bash", "kevm", "kprove", "koreRpc", "setsid", "timeout", "ps"];
  for (const key of executableToolKeys) {
    const item = toolchain[key];
    assert.ok(item && path.posix.isAbsolute(item.executable), `missing absolute pinned executable: ${key}`);
    requireHash(item.executable, item.sha256, `pinned executable ${key}`);
  }
  assert.equal(process.execPath, toolchain.node.executable, "launcher must run under pinned POSIX Node");
  assert.equal(args.python, toolchain.python.executable, "Python executable differs from pinned contract");
  const source = fs.readFileSync(claimPath);
  const newline = source.indexOf(10);
  assert.ok(newline > 0 && source.subarray(0, newline).toString("utf8").startsWith("requires "), "claim lacks requires prelude");
  const stripped = source.subarray(newline + 1);
  assert.equal(sha256(stripped), record.strippedClaimSha256, "stripped claim SHA-256 mismatch");
  const command = [
    toolchain.kevm.executable, "prove", path.join(args.outputRoot, "claim.k"),
    "--definition", definitionRoot, "--spec-module", record.module,
    "--save-directory", path.join(args.outputRoot, "save"),
    "--temp-directory", path.join(args.outputRoot, "temp"),
    "--kore-rpc-command", toolchain.koreRpc.executable,
    "--no-use-booster", "--workers", "1", "--force-sequential", "--max-depth", "1",
  ];
  const closure = args.preverifiedClosureWorkerSha256 ? {
    status: "PASS",
    freezeRoot: path.resolve(args.closureRoot),
    workerResultSha256: args.preverifiedClosureWorkerSha256,
    closureHashSha256: args.preverifiedClosureHashSha256,
    proofFreeCoordinatorPreverified: true,
  } : runJson(args.python, [freezeVerifierPath, "--root", args.closureRoot, "--repository-root", repositoryRoot, "--require-pass"], "closure freeze verification");
  assert.equal(closure.status, "PASS");
  assert.equal(fileSha256(closureWorkerPath), closure.workerResultSha256, "closure worker differs from verified coordinator verdict");
  if (args.mode === "print-command") {
    process.stdout.write(`${JSON.stringify({
      schemaVersion: 1, kind: "ABI04_FULL_ROW_REPLAY_PRINT_COMMAND_V1", status: "PASS_NO_HEAVY_PROOF_EXECUTED",
      replayId: record.replayId, semanticClaimId: record.semanticClaimId, executionClaimId: record.executionClaimId,
      executionSide: record.executionSide, expectedProcessExitCode: record.expectedProcessExitCode,
      claim: record.claim, strippedClaimSha256: record.strippedClaimSha256, module: record.module,
      definition: { absoluteRoot: definitionRoot, definitionKoreSha256: definition.definitionKoreSha256, compiledJsonSha256: definition.compiledJsonSha256 },
      closureFreeze: { root: args.closureRoot, workerResultSha256: fileSha256(closureWorkerPath), closureHashSha256: closure.closureHashSha256 },
      command: [toolchain.setsid.executable, "--wait", toolchain.timeout.executable, "--signal=TERM", "--kill-after=30s", "7200", ...command],
      proofExecuted: false, proofCredit: false, centralCredit: false,
    }, null, 2)}\n`);
    return;
  }
  assert.equal(fs.existsSync(args.outputRoot), false, `refusing existing output root: ${args.outputRoot}`);
  fs.mkdirSync(args.outputRoot, { recursive: true });
  const saveRoot = path.join(args.outputRoot, "save");
  const tempRoot = path.join(args.outputRoot, "temp");
  const snapshotRoot = path.join(args.outputRoot, "input-snapshot");
  fs.mkdirSync(saveRoot); fs.mkdirSync(tempRoot); fs.mkdirSync(snapshotRoot);
  const started = Math.floor(Date.now() / 1000);
  writeText(path.join(args.outputRoot, "started-at-epoch.txt"), started);
  writeText(path.join(args.outputRoot, "started-at-utc.txt"), new Date().toISOString());
  writeText(path.join(args.outputRoot, "replay-id.txt"), record.replayId);
  writeText(path.join(args.outputRoot, "semantic-claim-id.txt"), record.semanticClaimId);
  writeText(path.join(args.outputRoot, "execution-side.txt"), record.executionSide);
  writeText(path.join(args.outputRoot, "expected-exit-code.txt"), record.expectedProcessExitCode);
  fs.writeFileSync(path.join(args.outputRoot, "claim.k"), stripped);
  writeJson(path.join(args.outputRoot, "pre-proof-closure-verification.json"), closure);
  writeJson(path.join(args.outputRoot, "closure-freeze-files-before.json"), treeManifest(args.closureRoot));

  fs.copyFileSync(scriptPath, path.join(snapshotRoot, "run-abi-04-replay-v1.mjs"));
  fs.copyFileSync(claimPath, path.join(snapshotRoot, "claim-source.k"));
  fs.copyFileSync(analyzerPath, path.join(snapshotRoot, "analyze-abi-04-replay-v1.mjs"));
  fs.copyFileSync(verifierPath, path.join(snapshotRoot, "verify_abi_04_replay_v1.py"));
  fs.copyFileSync(freezeVerifierPath, path.join(snapshotRoot, "verify-freeze-receipt.py"));
  fs.copyFileSync(indexPath, path.join(snapshotRoot, "full-row-replay-index-v1.json"));
  fs.copyFileSync(toolchainContractPath, path.join(snapshotRoot, "s1-toolchain-contract-v1.json"));
  fs.cpSync(args.closureRoot, path.join(snapshotRoot, "closure-freeze"), { recursive: true, errorOnExist: true });
  writeJson(path.join(snapshotRoot, "record.json"), record);
  const liveInputs = () => [
    [scriptPath, "runner"], [claimPath, "claim"], [analyzerPath, "javascript-analyzer"],
    [verifierPath, "python-verifier"], [freezeVerifierPath, "freeze-verifier"], [indexPath, "replay-index"],
    [definitionKorePath, "definition.kore"], [compiledJsonPath, "compiled.json"], [closureWorkerPath, "closure-worker-result"],
    [toolchain.node.executable, "node-executable"], [toolchain.python.executable, "python-executable"],
    [toolchain.bash.executable, "bash-executable"], [toolchain.kevm.executable, "kevm-executable"],
    [toolchain.kprove.executable, "kprove-executable"], [toolchain.koreRpc.executable, "kore-rpc-executable"],
    [toolchain.setsid.executable, "setsid-executable"], [toolchain.timeout.executable, "timeout-executable"],
    [toolchain.ps.executable, "ps-executable"],
  ].map(([filePath, role]) => ({ role, path: filePath, sha256: fileSha256(filePath) }));
  const before = liveInputs();
  writeJson(path.join(args.outputRoot, "live-input-hashes-before.json"), before);
  const executionManifest = {
    schemaVersion: 1, kind: "ABI04_FULL_ROW_REPLAY_EXECUTION_MANIFEST_V1", replayId: record.replayId,
    semanticClaimId: record.semanticClaimId, executionClaimId: record.executionClaimId, executionSide: record.executionSide,
    claimSourceSha256: record.claim.sha256, strippedClaimSha256: record.strippedClaimSha256,
    definitionRoot, definitionKoreSha256: definition.definitionKoreSha256, compiledJsonSha256: definition.compiledJsonSha256,
    closureFreezeRoot: args.closureRoot, closureFreezeWorkerResultSha256: fileSha256(closureWorkerPath), closureHashSha256: closure.closureHashSha256,
    toolchainContractSha256: fileSha256(toolchainContractPath), expectedProcessExitCode: record.expectedProcessExitCode,
    boosterEnabled: false, workers: 1, forceSequential: true, maxDepth: 1, timeoutSeconds: 7200, terminationGraceSeconds: 30,
    command: [toolchain.setsid.executable, "--wait", toolchain.timeout.executable, "--signal=TERM", "--kill-after=30s", "7200", ...command],
  };
  writeJson(path.join(snapshotRoot, "execution-manifest.json"), executionManifest);
  const snapshotEntries = treeManifest(snapshotRoot);
  writeJson(path.join(snapshotRoot, "snapshot-files.json"), snapshotEntries);
  writeText(path.join(args.outputRoot, "snapshot-manifest.sha256"), fileSha256(path.join(snapshotRoot, "snapshot-files.json")));
  const launcherIdentityText = processIdentity(toolchain.ps.executable, process.pid);
  assert.ok(launcherIdentityText, "failed to capture launcher process identity");
  const launcherIdentity = parseProcessIdentity(launcherIdentityText);
  assert.equal(launcherIdentity.pid, process.pid, "launcher PID identity mismatch");
  writeText(path.join(args.outputRoot, "launcher-pid.txt"), process.pid);
  writeText(path.join(args.outputRoot, "launcher-pgid.txt"), launcherIdentity.pgid);
  writeText(path.join(args.outputRoot, "launcher-process-identity.txt"), launcherIdentityText);
  writeText(path.join(args.outputRoot, "invocation.json"), JSON.stringify(executionManifest.command));

  const proveLog = fs.openSync(path.join(args.outputRoot, "prove.log"), "wx");
  let proveLogClosed = false;
  let child = null;
  let childSid = null;
  let childPgid = null;
  let childExited = false;
  let childExitPromise = null;
  let childBirthReceipt = null;
  let resolveIdentityReady;
  const identityReady = new Promise((resolve) => { resolveIdentityReady = resolve; });
  let terminationPromise = null;
  let finished = false;
  const closeProveLog = () => {
    if (!proveLogClosed) { fs.closeSync(proveLog); proveLogClosed = true; }
  };
  const clearOwnedProcesses = async () => {
    if (!child) return;
    const ownedSid = childSid ?? child.pid;
    const ownedPgid = childPgid ?? child.pid;
    assert.ok(Number.isSafeInteger(ownedSid) && ownedSid > 0 && Number.isSafeInteger(ownedPgid) && ownedPgid > 0, "invalid owned session fallback identity");
    let rows = ownedProcessRows(toolchain.ps.executable, ownedSid, ownedPgid);
    if (rows.length === 0) return;
    const groups = [...new Set(rows.map((item) => item.pgid))].filter((value) => value > 0 && value !== launcherIdentity.pgid);
    for (const group of groups) try { process.kill(-group, "SIGKILL"); } catch (error) { if (error?.code !== "ESRCH") throw error; }
    for (const row of rows) if (row.pid !== process.pid) try { process.kill(row.pid, "SIGKILL"); } catch (error) { if (error?.code !== "ESRCH") throw error; }
    for (let i = 0; i < 100; i += 1) {
      rows = ownedProcessRows(toolchain.ps.executable, ownedSid, ownedPgid);
      if (rows.length === 0) break;
      await sleep(100);
    }
    assert.deepEqual(ownedProcessRows(toolchain.ps.executable, ownedSid, ownedPgid), [], "owned proof session descendants survived SIGKILL cleanup");
  };
  const terminate = (signalName) => {
    if (terminationPromise) return terminationPromise;
    terminationPromise = (async () => {
      if (!child) return;
      if (!childExited) writeText(path.join(args.outputRoot, "cancellation-signal.txt"), signalName);
      if (childPgid === null && !childExited) await Promise.race([identityReady, sleep(10_000)]);
      if (!childExited && childPgid === null) {
        try { child.kill("SIGTERM"); } catch {}
        await Promise.race([childExitPromise?.catch(() => null) ?? Promise.resolve(), sleep(30_000)]);
        if (!childExited) {
          try { child.kill("SIGKILL"); } catch {}
          await Promise.race([childExitPromise?.catch(() => null) ?? Promise.resolve(), sleep(10_000)]);
        }
      } else if (!childExited) {
        assert.notEqual(childPgid, launcherIdentity.pgid, "owned proof PGID equals launcher PGID");
        try { process.kill(-childPgid, "SIGTERM"); } catch { try { child.kill("SIGTERM"); } catch {} }
        await Promise.race([childExitPromise?.catch(() => null) ?? Promise.resolve(), sleep(30_000)]);
      }
      await clearOwnedProcesses();
      assert.equal(childExited, true, "owned proof launcher did not exit after cleanup");
    })();
    return terminationPromise;
  };
  const signalHandlers = new Map();
  for (const signalName of ["SIGINT", "SIGTERM", "SIGHUP"]) {
    const handler = async () => {
      if (finished) return;
      await terminate(signalName);
      process.exit(signalName === "SIGINT" ? 130 : signalName === "SIGHUP" ? 129 : 143);
    };
    signalHandlers.set(signalName, handler);
    process.once(signalName, handler);
  }
  let observed;
  try {
    child = spawn(toolchain.setsid.executable, ["--wait", toolchain.timeout.executable, "--signal=TERM", "--kill-after=30s", "7200", ...command], {
      cwd: repositoryRoot, stdio: ["ignore", proveLog, proveLog], env: { ...process.env, PATH: `${path.dirname(toolchain.kevm.executable)}:${path.dirname(toolchain.kprove.executable)}:${path.dirname(toolchain.koreRpc.executable)}:${process.env.PATH}` },
    });
    childExitPromise = new Promise((resolve, reject) => {
      child.once("error", (error) => { childExited = true; resolveIdentityReady(); reject(error); });
      child.once("exit", (code, signal) => { childExited = true; resolveIdentityReady(); resolve({ code, signal }); });
    });
    writeText(path.join(args.outputRoot, "child-pid.txt"), child.pid);
    const bootId = fs.readFileSync("/proc/sys/kernel/random/boot_id", "utf8").trim();
    assert.match(bootId, /^[0-9a-f-]{36}$/, "invalid Linux boot ID");
    let startTimeTicks = null;
    for (let i = 0; i < 20 && startTimeTicks === null && !childExited; i += 1) {
      try { startTimeTicks = processStartTimeTicks(child.pid); } catch { await sleep(50); }
    }
    assert.ok(startTimeTicks, "failed to capture child process birth identity");
    childBirthReceipt = { schemaVersion: 1, kind: "ABI04_PROOF_CHILD_BIRTH_RECEIPT_V1", pid: child.pid, bootId, startTimeTicks };
    writeJsonAtomic(path.join(args.outputRoot, "child-birth-receipt.json"), childBirthReceipt);
    let identity = "";
    for (let i = 0; i < 100 && !identity && !childExited; i += 1) {
      const candidate = processIdentity(toolchain.ps.executable, child.pid);
      if (candidate) {
        const parsed = parseProcessIdentity(candidate);
        if (parsed.pid === child.pid && parsed.sid === child.pid && parsed.pgid === child.pid && parsed.pgid !== launcherIdentity.pgid) {
          identity = candidate;
          childSid = parsed.sid;
          childPgid = parsed.pgid;
          resolveIdentityReady();
          break;
        }
      }
      await sleep(100);
    }
    assert.ok(identity, "failed to capture isolated child identity with PID == SID == PGID");
    writeJsonAtomic(path.join(args.outputRoot, "child-session-receipt.json"), {
      schemaVersion: 1, kind: "ABI04_PROOF_CHILD_SESSION_RECEIPT_V1", pid: child.pid,
      sid: childSid, pgid: childPgid, launcherPgid: launcherIdentity.pgid,
      bootId: childBirthReceipt.bootId, startTimeTicks: childBirthReceipt.startTimeTicks,
    });
    writeText(path.join(args.outputRoot, "child-sid.txt"), childSid);
    writeText(path.join(args.outputRoot, "child-pgid.txt"), childPgid);
    writeText(path.join(args.outputRoot, "child-process-identity.txt"), identity);
    observed = await childExitPromise;
  } finally {
    if (child) await terminate("runner-finally-cleanup");
    closeProveLog();
    for (const [signalName, handler] of signalHandlers) process.removeListener(signalName, handler);
  }
  const proofExit = observed.code === null ? (observed.signal === "SIGTERM" ? 143 : 128) : observed.code;
  writeText(path.join(args.outputRoot, "proof-exit-code.txt"), proofExit);
  const processes = sessionProcesses(toolchain.ps.executable, childSid);
  writeText(path.join(args.outputRoot, "post-run-owned-session-processes.txt"), processes.trimEnd());
  const survivorCount = Math.max(0, processes.trimEnd().split("\n").length - 1);
  writeText(path.join(args.outputRoot, "post-run-owned-session-survivor-count.txt"), survivorCount);
  const after = liveInputs();
  writeJson(path.join(args.outputRoot, "live-input-hashes-after.json"), after);
  const postClosure = runJson(args.python, [freezeVerifierPath, "--root", args.closureRoot, "--repository-root", repositoryRoot, "--require-pass"], "post-proof closure freeze verification");
  writeJson(path.join(args.outputRoot, "post-proof-closure-verification.json"), postClosure);
  writeJson(path.join(args.outputRoot, "closure-freeze-files-after.json"), treeManifest(args.closureRoot));
  const integrityPass = JSON.stringify(before) === JSON.stringify(after)
    && JSON.stringify(readJson(path.join(args.outputRoot, "closure-freeze-files-before.json"))) === JSON.stringify(readJson(path.join(args.outputRoot, "closure-freeze-files-after.json")))
    && treeManifest(snapshotRoot).every((item) => item.path === "snapshot-files.json" || snapshotEntries.some((expected) => expected.path === item.path && expected.sha256 === item.sha256));
  writeText(path.join(args.outputRoot, "input-integrity-status.txt"), integrityPass ? "PASS" : "FAIL");
  const classification = [124, 137, 143].includes(proofExit) ? "TIMEOUT_OR_FORCED_TERMINATION"
    : proofExit !== record.expectedProcessExitCode ? "PROCESS_EXIT_MISMATCH"
      : record.executionSide === "canonical-positive" ? "EXPECTED_POSITIVE_PROCESS_EXIT" : "EXPECTED_NEGATIVE_PROCESS_EXIT";
  writeText(path.join(args.outputRoot, "run-classification.txt"), classification);
  const finishedEpoch = Math.floor(Date.now() / 1000);
  writeText(path.join(args.outputRoot, "finished-at-epoch.txt"), finishedEpoch);
  writeText(path.join(args.outputRoot, "finished-at-utc.txt"), new Date().toISOString());
  writeText(path.join(args.outputRoot, "elapsed-seconds.txt"), finishedEpoch - started);
  let finalExit = proofExit;
  if (proofExit !== record.expectedProcessExitCode) finalExit = 76;
  if (!integrityPass) finalExit = 74;
  if (survivorCount !== 0) finalExit = 75;
  writeText(path.join(args.outputRoot, "exit-code.txt"), finalExit);
  finished = true;
  process.exitCode = finalExit;
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exitCode = 1;
});
