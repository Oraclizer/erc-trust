// SPDX-License-Identifier: BSD-3-Clause

import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  canonicalMutationDefinitionsSha256,
  validateMutationDefinitionBinding,
} from "./lib/mutation-campaign.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = resolve(root, "scripts/mutation-campaign-v1.json");
const rebind = resolve(root, "evidence/mutation-definition-rebind-v1.json");
const receipt = JSON.parse(readFileSync(resolve(root, "evidence/mutation-results.json"), "utf8"));
const check = (condition, message) => { if (!condition) throw new Error(message); };
const validate = (value, manifestPath = manifest, rebindPath = rebind) =>
  validateMutationDefinitionBinding(value, root, manifestPath, rebindPath, check);
const expectRejected = (mutate, label) => {
  const value = structuredClone(receipt);
  mutate(value);
  assert.throws(() => validate(value), label);
};

validate(receipt);
expectRejected((value) => { value.campaignDefinition[0].old += " "; }, "old anchor drift");
expectRejected((value) => { value.campaignDefinition[0].new += " "; }, "replacement drift");
expectRejected((value) => { value.campaignDefinition[0].file = "implementation/src/Other.sol"; }, "target drift");
expectRejected((value) => { value.campaignDefinition[0].expectedOccurrences += 1; }, "occurrence drift");
expectRejected((value) => { value.campaignDefinition[0].detector.test += "Changed"; }, "detector drift");
expectRejected((value) => { value.campaignDefinitionSha256 = "0".repeat(64); }, "campaign hash drift");

const work = mkdtempSync(join(tmpdir(), "erc-trust-mutation-binding-"));
try {
  const changedManifest = JSON.parse(readFileSync(manifest, "utf8"));
  const changedReceipt = structuredClone(receipt);
  const changedRebind = JSON.parse(readFileSync(rebind, "utf8"));
  changedManifest.definitions[0].new += " ";
  const changedHash = canonicalMutationDefinitionsSha256(changedManifest.definitions);
  changedManifest.campaignDefinitionSha256 = changedHash;
  changedReceipt.campaignDefinition = changedManifest.definitions;
  changedReceipt.campaignDefinitionSha256 = changedHash;
  changedRebind.campaignDefinitionSha256 = changedHash;
  const manifestPath = join(work, "campaign.json");
  const rebindPath = join(work, "rebind.json");
  writeFileSync(manifestPath, JSON.stringify(changedManifest), "utf8");
  writeFileSync(rebindPath, JSON.stringify(changedRebind), "utf8");
  assert.throws(
    () => validate(changedReceipt, manifestPath, rebindPath),
    "correlated manifest, receipt, and rebind drift must not inherit legacy results",
  );
} finally {
  rmSync(work, { recursive: true, force: true });
}

console.log("mutation definition binding self-test PASS: six direct and one correlated definition-drift negatives rejected");
