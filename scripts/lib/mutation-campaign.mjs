// SPDX-License-Identifier: BSD-3-Clause

import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";

const sha256 = (value) => createHash("sha256").update(value).digest("hex");

export function mutationDefinitionBlockSha256(path) {
  const source = readFileSync(path, "utf8").replace(/\r\n?/g, "\n");
  const match = source.match(/# MUTATION_DEFINITIONS_BEGIN\n([\s\S]*?)# MUTATION_DEFINITIONS_END/);
  if (!match) throw new Error("mutation definition markers missing");
  return sha256(Buffer.from(match[1], "utf8"));
}

export function validateMutationDefinitionBinding(receipt, scriptPath, manifestPath, fail) {
  const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
  fail(manifest.schema === "erc-trust-mutation-campaign-v1", "mutation definition manifest schema");
  fail(manifest.algorithm === "sha256-utf8-lf-mutation-definition-block-v1", "mutation definition manifest algorithm");
  fail(manifest.campaignDefinitionSha256 === mutationDefinitionBlockSha256(scriptPath), "mutation definition manifest hash drift");
  fail(receipt.campaignDefinitionAlgorithm === "sha256-utf8-lf-mutation-definition-block-v1", "mutation definition algorithm");
  fail(receipt.campaignDefinitionSha256 === manifest.campaignDefinitionSha256, "mutation campaign definition hash drift");
  fail(Array.isArray(receipt.campaignDefinition) && receipt.campaignDefinition.length > 0, "mutation definition set is empty");
  fail(JSON.stringify(receipt.campaignDefinition) === JSON.stringify(manifest.definitions), "mutation receipt definition set differs from the current manifest");
  fail(receipt.campaignDefinition.length === receipt.results.length, "mutation definition/result count mismatch");
  const ids = new Set();
  for (let index = 0; index < receipt.campaignDefinition.length; index += 1) {
    const definition = receipt.campaignDefinition[index];
    const result = receipt.results[index];
    fail(typeof definition.id === "string" && !ids.has(definition.id), `invalid or duplicate mutation definition id at ${index}`);
    ids.add(definition.id);
    fail(typeof definition.file === "string" && !definition.file.includes("\\"), `mutation definition path is not normalized: ${definition.id}`);
    fail(typeof definition.old === "string" && typeof definition.new === "string", `mutation definition replacement missing: ${definition.id}`);
    fail(Number.isInteger(definition.expectedOccurrences) && definition.expectedOccurrences > 0, `mutation definition occurrence count: ${definition.id}`);
    fail(typeof definition.firstOnly === "boolean", `mutation definition firstOnly: ${definition.id}`);
    fail(typeof definition.detector?.contract === "string" && typeof definition.detector?.test === "string", `mutation definition detector: ${definition.id}`);
    fail(result.id === definition.id, `mutation definition/result id mismatch: ${definition.id}`);
    fail(result.anchorOccurrences === definition.expectedOccurrences, `mutation occurrence receipt mismatch: ${definition.id}`);
    fail(result.detector === `${definition.detector.contract}.${definition.detector.test}`, `mutation detector receipt mismatch: ${definition.id}`);
  }
}
