// SPDX-License-Identifier: BSD-3-Clause

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const sdk = resolve(root, "sdk");
const work = mkdtempSync(join(tmpdir(), "erc-trust-sdk-package-"));
const installRoot = join(work, "consumer");
const npmCli = [
  resolve(dirname(process.execPath), "node_modules", "npm", "bin", "npm-cli.js"),
  resolve(dirname(process.execPath), "..", "lib", "node_modules", "npm", "bin", "npm-cli.js"),
].find((candidate) => existsSync(candidate));

function run(command, args, cwd) {
  const result = spawnSync(command, args, { cwd, encoding: "utf8" });
  if (result.status !== 0) {
    throw new Error(`${command} ${args.join(" ")} failed\n${result.error ?? ""}\n${result.stdout ?? ""}\n${result.stderr ?? ""}`);
  }
}

const runNpm = (args, cwd) => run(process.execPath, [npmCli, ...args], cwd);

try {
  assert.equal(typeof npmCli, "string", "npm CLI must be installed in the Windows or Unix Node.js prefix");
  runNpm(["pack", "--pack-destination", work], sdk);
  const archives = readdirSync(work).filter((name) => name.endsWith(".tgz"));
  assert.equal(archives.length, 1, "npm pack must produce exactly one tarball");
  const archive = join(work, archives[0]);

  mkdirSync(installRoot);
  runNpm(["init", "--yes"], installRoot);
  runNpm(["install", "--ignore-scripts", "--no-audit", "--no-fund", archive], installRoot);

  const packageRoot = join(installRoot, "node_modules", "@oraclizer", "erc-trust-sdk");
  for (const name of ["index.js", "index.d.ts", "kernel-v2.js", "kernel-v2.d.ts", "v1.js", "v1.d.ts"]) {
    assert.equal(existsSync(join(packageRoot, "dist", name)), true, `packed dist/${name}`);
  }
  assert.equal(readdirSync(join(packageRoot, "dist")).some((name) => name.includes(".test.")), false, "tests must not be packed");
  assert.doesNotMatch(readFileSync(join(packageRoot, "README.md"), "utf8"), /\]\(\.\.\//, "packed README must not link outside the package");
  const vectors = JSON.parse(readFileSync(resolve(root, "vectors/conformance-v2.json"), "utf8"));
  const historicalVectors = JSON.parse(readFileSync(resolve(root, "vectors/conformance-v1.json"), "utf8"));
  writeFileSync(join(installRoot, "fixture.json"), JSON.stringify({
    constants: vectors.constants,
    fixture: vectors.fixture,
    action: vectors.actions[0],
    reversal: vectors.reversals[0],
    historical: historicalVectors.positive,
  }), "utf8");
  writeFileSync(join(installRoot, "consumer.mjs"), `
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import * as installed from "@oraclizer/erc-trust-sdk";
import * as historical from "@oraclizer/erc-trust-sdk/v1";
const vectors = JSON.parse(readFileSync(new URL("./fixture.json", import.meta.url), "utf8"));
const action = vectors.action;
const reversal = vectors.reversal;
const historicalVector = vectors.historical;
const actionRequest = { ...action.request, action: Number(action.request.action), amount: BigInt(action.request.amount), dependencyEpoch: BigInt(action.request.dependencyEpoch), authorityEpoch: BigInt(action.request.authorityEpoch), nonce: BigInt(action.request.nonce), validAfter: BigInt(action.request.validAfter), validBefore: BigInt(action.request.validBefore) };
const reversalRequest = { ...reversal.request, reversal: Number(reversal.request.reversal), dependencyEpoch: BigInt(reversal.request.dependencyEpoch), authorityEpoch: BigInt(reversal.request.authorityEpoch), nonce: BigInt(reversal.request.nonce), validAfter: BigInt(reversal.request.validAfter), validBefore: BigInt(reversal.request.validBefore) };
const receiptInput = { ...action.receiptInput, receiptKind: Number(action.receiptInput.receiptKind), commandKind: BigInt(action.receiptInput.commandKind), amount: BigInt(action.receiptInput.amount) };
assert.equal(installed.KERNEL_VERSION, 2);
assert.equal(installed.KERNEL_DOMAIN, vectors.constants.domain);
assert.equal(installed.KERNEL_INTERFACE_ID, vectors.constants.kernelInterfaceId);
assert.equal(installed.KERNEL_SELECTORS.executeRegulatoryAction, action.calldata.slice(0, 10));
assert.equal(installed.KERNEL_SELECTORS.executeRegulatoryReversal, reversal.calldata.slice(0, 10));
assert.equal(installed.deriveActionId(vectors.fixture.endpoint, BigInt(vectors.fixture.chainId), actionRequest), action.actionId);
assert.equal(installed.encodeAction(actionRequest), action.calldata);
assert.equal((action.calldata.length - 2) / 2, 644);
assert.equal(installed.receiptHash(receiptInput), action.receiptHash);
assert.equal(installed.deriveReversalId(vectors.fixture.endpoint, BigInt(vectors.fixture.chainId), reversalRequest), reversal.reversalId);
assert.equal(installed.encodeReversal(reversalRequest), reversal.calldata);
assert.equal((reversal.calldata.length - 2) / 2, 388);
assert.equal(historical.TRUST_DOMAIN, "0x8f99afa60666700eaaef54913dd2d5deee2e8189907e4b356645a90710d5907c");
const historicalRequest = { ...historicalVector.actionRequest, action: Number(historicalVector.actionRequest.action), amount: BigInt(historicalVector.actionRequest.amount), authorityEpoch: BigInt(historicalVector.actionRequest.authorityEpoch), policyEpoch: BigInt(historicalVector.actionRequest.policyEpoch), nonce: BigInt(historicalVector.actionRequest.nonce), validAfter: BigInt(historicalVector.actionRequest.validAfter), validBefore: BigInt(historicalVector.actionRequest.validBefore) };
const historicalReceipt = { ...historicalVector.receiptInput, action: Number(historicalVector.receiptInput.action), amount: BigInt(historicalVector.receiptInput.amount) };
assert.equal(historical.deriveActionId(historicalVector.token, BigInt(historicalVector.chainId), historicalRequest), historicalVector.actionId);
assert.equal(historical.encodeAction(historicalRequest), historicalVector.calldata);
assert.equal(historical.actionReceiptHash(historicalReceipt), historicalVector.receiptHash);
`, "utf8");
  run(process.execPath, ["consumer.mjs"], installRoot);

  console.log("installed SDK package consumer PASS: root is kernel version 2 and ./v1 is explicit");
} finally {
  rmSync(work, { recursive: true, force: true });
}
