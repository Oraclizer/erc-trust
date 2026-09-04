// SPDX-License-Identifier: BSD-3-Clause

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const readJson = (path) => JSON.parse(readFileSync(resolve(root, path), "utf8"));
const schema = readJson("schemas/receipt.schema.json");
const vectors = readJson("vectors/conformance-v2.json");
const solidity = readFileSync(resolve(root, "implementation/src/generated/IERCTrustKernel.sol"), "utf8");

const bytes32 = /^0x[0-9a-fA-F]{64}$/;
const address = /^0x[0-9a-fA-F]{40}$/;
const uintString = /^(0|[1-9][0-9]*)$/;

function validate(receipt) {
  const failures = [];
  const keys = Object.keys(receipt);
  for (const name of schema.required) if (!(name in receipt)) failures.push(`missing ${name}`);
  for (const name of keys) if (!(name in schema.properties)) failures.push(`unexpected ${name}`);
  for (const [name, rule] of Object.entries(schema.properties)) {
    if (!(name in receipt)) continue;
    const value = receipt[name];
    if (rule.$ref?.endsWith("/bytes32") && !bytes32.test(value)) failures.push(`${name} bytes32`);
    if (rule.$ref?.endsWith("/address") && !address.test(value)) failures.push(`${name} address`);
    if (rule.$ref?.endsWith("/uintString") && !uintString.test(value)) failures.push(`${name} uintString`);
    if (rule.type === "integer" && !Number.isInteger(value)) failures.push(`${name} integer`);
    if (rule.enum && !rule.enum.includes(value)) failures.push(`${name} enum`);
    if (rule.minimum !== undefined && value < rule.minimum) failures.push(`${name} minimum`);
    if (rule.maximum !== undefined && value > rule.maximum) failures.push(`${name} maximum`);
  }
  if (receipt.receiptKind === 1) {
    if (receipt.commandKind > 5) failures.push("action commandKind");
    if (receipt.parentCommandId !== `0x${"00".repeat(32)}`) failures.push("action parentCommandId");
  }
  if (receipt.receiptKind === 2 && receipt.commandKind > 2) failures.push("reversal commandKind");
  if (receipt.receiptKind === 2 && receipt.parentCommandId === `0x${"00".repeat(32)}`) failures.push("reversal parentCommandId");
  return failures;
}

const structMatch = solidity.match(/struct Receipt \{([\s\S]*?)\n    \}/);
assert.ok(structMatch, "generated Solidity Receipt struct not found");
const solidityFields = [...structMatch[1].matchAll(/^\s+[^/\n;]+\s+(\w+);$/gm)].map((match) => match[1]);
assert.deepEqual(schema.required, solidityFields, "schema field order must equal generated Solidity Receipt");
assert.deepEqual(Object.keys(schema.properties), solidityFields, "schema property order must equal generated Solidity Receipt");
assert.equal(solidityFields.length, 17);

const receipts = [
  ...vectors.actions.map((vector) => ({ ...vector.receiptInput, receiptHash: vector.receiptHash })),
  ...vectors.reversals.map((vector) => ({ ...vector.receiptInput, receiptHash: vector.receiptHash })),
].map((receipt) => ({ ...receipt, receiptKind: Number(receipt.receiptKind), commandKind: Number(receipt.commandKind) }));

for (const [index, receipt] of receipts.entries()) {
  assert.deepEqual(validate(receipt), [], `vector receipt ${index}`);
}

const base = receipts[0];
const missing = { ...base };
delete missing.dependencyRoot;
assert.ok(validate(missing).some((failure) => failure === "missing dependencyRoot"));
assert.ok(validate({ ...base, legacyPolicyBinding: base.dependencyRoot }).some((failure) => failure === "unexpected legacyPolicyBinding"));
assert.ok(validate({ ...base, receiptKind: 0 }).some((failure) => failure === "receiptKind enum"));
assert.ok(validate({ ...base, amount: "01" }).some((failure) => failure === "amount uintString"));
assert.ok(validate({ ...receipts.at(-1), commandKind: 5 }).some((failure) => failure === "reversal commandKind"));
assert.ok(validate({ ...receipts.at(-1), parentCommandId: `0x${"00".repeat(32)}` }).some((failure) => failure === "reversal parentCommandId"));

console.log(`receipt schema consumer PASS: ${receipts.length} vectors, ${solidityFields.length} generated Solidity fields`);
