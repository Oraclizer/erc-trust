// SPDX-License-Identifier: BSD-3-Clause

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import Ajv2020 from "../sdk/node_modules/ajv/dist/2020.js";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const readJson = (path) => JSON.parse(readFileSync(resolve(root, path), "utf8"));
const schema = readJson("schemas/receipt.schema.json");
const kernel = readJson("spec/erc-trust-kernel-v2.json");
const vectors = readJson("vectors/conformance-v2.json");
const solidity = readFileSync(resolve(root, "implementation/src/generated/IERCTrustKernel.sol"), "utf8");
const validate = new Ajv2020({ allErrors: true, strict: true }).compile(schema);

const structMatch = solidity.match(/struct Receipt \{([\s\S]*?)\n    \}/);
assert.ok(structMatch, "generated Solidity Receipt struct not found");
const solidityFields = [...structMatch[1].matchAll(/^\s+([^/\n;]+)\s+(\w+);$/gm)]
  .map((match) => ({ type: match[1].trim(), name: match[2] }));
const kernelFields = kernel.structs.Receipt.fields.map((field) => ({
  type: field.enum ? `TrustKernelTypes.${field.enum}` : field.type,
  name: field.name,
}));
assert.deepEqual(solidityFields, kernelFields, "generated Solidity Receipt type/name order must equal the machine source");
assert.deepEqual(schema.required, kernelFields.map((field) => field.name), "schema field order must equal the machine source");
assert.deepEqual(Object.keys(schema.properties), kernelFields.map((field) => field.name), "schema property order must equal the machine source");
assert.equal(solidityFields.length, 17);

const receipts = [
  ...vectors.actions.map((vector) => ({ ...vector.receiptInput, receiptHash: vector.receiptHash })),
  ...vectors.reversals.map((vector) => ({ ...vector.receiptInput, receiptHash: vector.receiptHash })),
].map((receipt) => ({ ...receipt, receiptKind: Number(receipt.receiptKind), commandKind: Number(receipt.commandKind) }));

for (const [index, receipt] of receipts.entries()) {
  assert.equal(validate(receipt), true, `vector receipt ${index}: ${JSON.stringify(validate.errors)}`);
}

const base = receipts[0];
const missing = { ...base };
delete missing.dependencyRoot;
for (const invalid of [
  missing,
  { ...base, legacyPolicyBinding: base.dependencyRoot },
  { ...base, receiptKind: 0 },
  { ...base, amount: "01" },
  { ...base, parentCommandId: `0x${"11".repeat(32)}` },
  { ...receipts.at(-1), commandKind: 5 },
  { ...receipts.at(-1), parentCommandId: `0x${"00".repeat(32)}` },
]) {
  assert.equal(validate(invalid), false, `negative receipt unexpectedly validated: ${JSON.stringify(invalid)}`);
}

console.log(`receipt schema consumer PASS: ${receipts.length} vectors, ${solidityFields.length} generated Solidity fields`);
