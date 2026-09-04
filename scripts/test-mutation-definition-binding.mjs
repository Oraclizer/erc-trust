// SPDX-License-Identifier: BSD-3-Clause

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { validateMutationDefinitionBinding } from "./lib/mutation-campaign.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const script = resolve(root, "scripts/run-mutations.ps1");
const manifest = resolve(root, "scripts/mutation-campaign-v1.json");
const receipt = JSON.parse(readFileSync(resolve(root, "evidence/mutation-results.json"), "utf8"));
const check = (condition, message) => { if (!condition) throw new Error(message); };
const validate = (value) => validateMutationDefinitionBinding(value, script, manifest, check);
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

console.log("mutation definition binding self-test PASS: six definition-drift negatives rejected");
