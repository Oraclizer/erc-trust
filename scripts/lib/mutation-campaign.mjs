// SPDX-License-Identifier: BSD-3-Clause

import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";

const ALGORITHM = "sha256-canonical-json-sorted-keys-v1";
const LEGACY_RECEIPT_HEAD = "1de893b8d6bf1e26669baf0d8e6a8d3216f5a44e";
const LEGACY_DEFINITION_SHA256 = "a56e9052820612032fd3be549c15593de2a09668c32628137017e0d36fe38acd";
const LEGACY_SCRIPT_BLOB = "a670d6edca358461dbc88ee2a209029099d5f83f";
const LEGACY_SCRIPT_RAW_SHA256 = "c28210bec081c305f4a364d7dc71fec04c08615f249ed2c3b3e058f000f14264";
const CLOSURE_BASELINE = "1e6375c66ec18a48759df80a1579961f27533e3a";

const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const stable = (value) => {
  if (Array.isArray(value)) return value.map(stable);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stable(value[key])]));
  }
  return value;
};

export const canonicalMutationDefinitionsSha256 = (definitions) =>
  sha256(Buffer.from(JSON.stringify(stable(definitions)), "utf8"));

function git(repoRoot, args, encoding = "utf8") {
  const safe = repoRoot.replaceAll("\\", "/");
  return execFileSync("git", ["-c", `safe.directory=${safe}`, ...args], { cwd: repoRoot, encoding });
}

export function validateMutationDefinitionBinding(receipt, repoRoot, manifestPath, rebindPath, check) {
  const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
  const rebind = JSON.parse(readFileSync(rebindPath, "utf8"));
  check(manifest.schema === "erc-trust-mutation-campaign-v1", "mutation definition manifest schema");
  check(manifest.algorithm === ALGORITHM, "mutation definition manifest algorithm");
  check(Array.isArray(manifest.definitions) && manifest.definitions.length > 0, "mutation definition manifest is empty");
  check(manifest.campaignDefinitionSha256 === canonicalMutationDefinitionsSha256(manifest.definitions), "mutation definition manifest hash drift");
  check(receipt.campaignDefinitionAlgorithm === ALGORITHM, "mutation receipt definition algorithm");
  check(receipt.campaignDefinitionSha256 === manifest.campaignDefinitionSha256, "mutation receipt definition hash drift");
  check(JSON.stringify(receipt.campaignDefinition) === JSON.stringify(manifest.definitions), "mutation receipt definition set differs from the current manifest");
  check(receipt.campaignDefinition.length === receipt.results.length, "mutation definition/result count mismatch");

  const ids = new Set();
  for (let index = 0; index < receipt.campaignDefinition.length; index += 1) {
    const definition = receipt.campaignDefinition[index];
    const result = receipt.results[index];
    check(typeof definition.id === "string" && !ids.has(definition.id), `invalid or duplicate mutation definition id at ${index}`);
    ids.add(definition.id);
    check(typeof definition.fault === "string" && definition.fault.length > 0, `mutation definition fault: ${definition.id}`);
    check(typeof definition.file === "string" && !definition.file.includes("\\"), `mutation definition path is not normalized: ${definition.id}`);
    check(typeof definition.old === "string" && typeof definition.new === "string", `mutation definition replacement missing: ${definition.id}`);
    check(Number.isInteger(definition.expectedOccurrences) && definition.expectedOccurrences > 0, `mutation definition occurrence count: ${definition.id}`);
    check(typeof definition.firstOnly === "boolean", `mutation definition firstOnly: ${definition.id}`);
    check(typeof definition.detector?.contract === "string" && typeof definition.detector?.test === "string", `mutation definition detector: ${definition.id}`);
    check(result.id === definition.id && result.fault === definition.fault, `mutation definition/result identity mismatch: ${definition.id}`);
    check(result.anchorOccurrences === definition.expectedOccurrences, `mutation occurrence receipt mismatch: ${definition.id}`);
    check(result.detector === `${definition.detector.contract}.${definition.detector.test}`, `mutation detector receipt mismatch: ${definition.id}`);
  }

  if (receipt.candidateInput?.gitHead === LEGACY_RECEIPT_HEAD) {
    check(receipt.campaignDefinitionSha256 === LEGACY_DEFINITION_SHA256, "legacy mutation receipt cannot inherit a changed campaign");
    check(rebind.schema === "erc-trust-mutation-definition-rebind-v1", "mutation rebind schema");
    check(rebind.receiptGitHead === LEGACY_RECEIPT_HEAD, "mutation rebind receipt head");
    check(rebind.comparisonBaseline === CLOSURE_BASELINE, "mutation rebind comparison baseline");
    check(rebind.campaignDefinitionSource === "scripts/mutation-campaign-v1.json", "mutation rebind definition source");
    check(rebind.campaignDefinitionSha256 === LEGACY_DEFINITION_SHA256, "mutation rebind definition hash");
    check(rebind.historicalGitBlob === LEGACY_SCRIPT_BLOB && rebind.baselineGitBlob === LEGACY_SCRIPT_BLOB,
      "mutation rebind historical/baseline blob identity");
    const baselineBlob = git(repoRoot, ["rev-parse", `${rebind.comparisonBaseline}:${rebind.definitionSource}`]).trim();
    check(rebind.historicalGitBlob === LEGACY_SCRIPT_BLOB && rebind.historicalRawSha256 === LEGACY_SCRIPT_RAW_SHA256,
      "mutation rebind historical identity differs from the frozen legacy constants");
    check(baselineBlob === rebind.baselineGitBlob, "mutation rebind baseline Git blob");
    check(sha256(git(repoRoot, ["cat-file", "blob", baselineBlob], null)) === rebind.baselineRawSha256,
      "mutation rebind baseline raw hash");
    check(rebind.result === "BYTE_EXACT_DEFINITION_SOURCE", "mutation rebind disposition");
  }
}
