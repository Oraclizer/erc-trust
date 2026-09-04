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
const executable = (name) => name === "node" ? process.execPath : process.platform === "win32" ? `${name}.cmd` : name;

function run(command, args, cwd) {
  const result = spawnSync(executable(command), args, {
    cwd,
    encoding: "utf8",
    shell: process.platform === "win32" && command !== "node",
  });
  if (result.status !== 0) {
    throw new Error(`${command} ${args.join(" ")} failed\n${result.error ?? ""}\n${result.stdout ?? ""}\n${result.stderr ?? ""}`);
  }
}

try {
  run("npm", ["pack", "--pack-destination", work], sdk);
  const archives = readdirSync(work).filter((name) => name.endsWith(".tgz"));
  assert.equal(archives.length, 1, "npm pack must produce exactly one tarball");
  const archive = join(work, archives[0]);

  mkdirSync(installRoot);
  run("npm", ["init", "--yes"], installRoot);
  run("npm", ["install", "--ignore-scripts", "--no-audit", "--no-fund", archive], installRoot);

  const packageRoot = join(installRoot, "node_modules", "@oraclizer", "erc-trust-sdk");
  for (const name of ["index.js", "index.d.ts", "kernel-v2.js", "kernel-v2.d.ts", "v1.js", "v1.d.ts"]) {
    assert.equal(existsSync(join(packageRoot, "dist", name)), true, `packed dist/${name}`);
  }
  assert.equal(readdirSync(join(packageRoot, "dist")).some((name) => name.includes(".test.")), false, "tests must not be packed");
  const vectors = JSON.parse(readFileSync(resolve(root, "vectors/conformance-v2.json"), "utf8"));
  writeFileSync(join(installRoot, "fixture.json"), JSON.stringify({
    constants: vectors.constants,
    fixture: vectors.fixture,
    action: vectors.actions[0],
    reversal: vectors.reversals[0],
  }), "utf8");
  writeFileSync(join(installRoot, "consumer.mjs"), `
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import * as installed from "@oraclizer/erc-trust-sdk";
import * as historical from "@oraclizer/erc-trust-sdk/v1";
const vectors = JSON.parse(readFileSync(new URL("./fixture.json", import.meta.url), "utf8"));
const action = vectors.action;
const reversal = vectors.reversal;
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
`, "utf8");
  run("node", ["consumer.mjs"], installRoot);

  console.log("installed SDK package consumer PASS: root is kernel version 2 and ./v1 is explicit");
} finally {
  rmSync(work, { recursive: true, force: true });
}
