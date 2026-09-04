// SPDX-License-Identifier: BSD-3-Clause

import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const argv = process.argv.slice(2);
const valueOf = (flag) => {
  const index = argv.indexOf(flag);
  return index === -1 ? null : argv[index + 1];
};
const runPath = valueOf("--run");
const write = argv.includes("--write");
if (!runPath) throw new Error("usage: node scripts/record-certora-results-v3.mjs --run <provider-run.json> [--write]");

const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const bytes = (path) => readFileSync(resolve(root, path));
const json = (path) => JSON.parse(readFileSync(resolve(root, path), "utf8"));
const check = (condition, message) => {
  if (!condition) throw new Error(message);
};
const stable = (value) => {
  if (Array.isArray(value)) return value.map(stable);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stable(value[key])]));
  }
  return value;
};
const exactSet = (actual, expected, label) => {
  check(Array.isArray(actual) && Array.isArray(expected) && expected.length > 0, `${label} is empty`);
  check(new Set(actual).size === actual.length, `${label} contains duplicates`);
  check(JSON.stringify([...actual].sort()) === JSON.stringify([...expected].sort()), `${label} differs from frozen expectations`);
};
const rootOf = (paths) => sha256(Buffer.from(
  [...paths].sort().map((path) => `${sha256(bytes(path))}  ${path}\n`).join(""),
  "utf8",
));

const expected = json("evidence/evidence-expectations-v3.json").certora;
const candidate = json("evidence/evidence-mode.json").candidate;
const provider = JSON.parse(readFileSync(resolve(root, runPath), "utf8"));
check(provider.schema === "erc-trust-certora-provider-run-v1", "provider run schema");
check(provider.provider === expected.provider, "provider identity");
check(expected.runtimeSubject === "profileAdapter", "Certora runtime subject");
check(["FROZEN_PENDING_APPROVAL_OR_RUN", "RECORDED_PASS"].includes(expected.status),
  "Certora expectations are not frozen or recorded");
exactSet(provider.rules.map((rule) => rule.id), expected.expectedRuleIds, "provider rules");
check(provider.rules.every((rule) => rule.status === "PASS" && rule.sanity === "PASS"), "provider rule or sanity failure");
check(provider.outputNamespace === expected.expectedOutputNamespace, "provider output namespace");
check(typeof provider.runHash === "string" && /^[0-9a-f]{32}$/.test(provider.runHash), "provider run hash");
check(provider.url === `https://prover.certora.com/output/${provider.outputNamespace}/${provider.runHash}`, "provider run URL");
check(provider.processExit === 0 && provider.terminalResult === expected.expectedTerminalResult, "provider terminal result");
check(provider.toolchain?.certoraCli === expected.expectedCertoraCli, "Certora CLI version");
check(provider.toolchain?.certoraServer === expected.expectedCertoraServer, "Certora server version");
check(provider.toolchain?.solidity === expected.expectedSolidity, "Solidity version");
check(provider.toolchain?.ruleSanity === expected.expectedRuleSanity, "rule sanity mode");

const inputs = expected.expectedInputPaths.map((path) => ({ path, sha256: sha256(bytes(path)) }));
const inputsRootSha256 = rootOf(expected.expectedInputPaths);
check(inputsRootSha256 === expected.expectedInputsRootSha256, "frozen Certora input root drift");
const bridge = json("evidence/end-to-end-refinement/runtime-bridge-v2/schema.json");
const runtimeTemplateSha256 = bridge.subjects.profileAdapter.runtime.sha256;
const names = provider.rules.map((rule) => rule.id);
const receipt = {
  schema: "erc-trust-certora-results-v3",
  candidate,
  status: "PASS",
  rules: {
    total: names.length,
    success: names.length,
    fail: 0,
    sanityFail: 0,
    timeout: 0,
    unknown: 0,
    names,
  },
  ruleResults: provider.rules.map((rule) => ({ id: rule.id, status: rule.status })),
  inputs,
  inputsRootSha256,
  runtimeTemplateSha256,
  toolchain: provider.toolchain,
  run: {
    provider: provider.provider,
    runId: provider.runHash,
    runHash: provider.runHash,
    outputNamespace: provider.outputNamespace,
    url: provider.url,
    processExit: provider.processExit,
    terminalResult: provider.terminalResult,
    startedAt: provider.startedAt,
    finishedAt: provider.finishedAt,
    replay: provider.replay,
  },
};

const output = `${JSON.stringify(stable(receipt), null, 2)}\n`;
if (write) writeFileSync(resolve(root, "evidence/certora-results-v3.json"), output);
process.stdout.write(output);
