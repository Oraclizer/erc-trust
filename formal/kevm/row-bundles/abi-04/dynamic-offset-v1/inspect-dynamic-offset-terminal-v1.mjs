#!/usr/bin/env node
// Structural inspector for a serialized calibration terminal node. This tool
// grants no proof credit; it emits candidate values for a future pre-run
// expected-graph contract.
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";

const [nodeArgument] = process.argv.slice(2);
if (!nodeArgument) throw new Error("usage: inspect-dynamic-offset-terminal-v1.mjs TERMINAL_NODE_JSON");
const nodePath = path.resolve(nodeArgument);
const root = JSON.parse(fs.readFileSync(nodePath, "utf8"));
const applyLabel = (value) => value?.label?.name;
const findApplies = (value, label, matches = []) => {
  if (Array.isArray(value)) {
    for (const item of value) findApplies(item, label, matches);
  } else if (value && typeof value === "object") {
    if (applyLabel(value) === label) matches.push(value);
    for (const item of Object.values(value)) findApplies(item, label, matches);
  }
  return matches;
};
const directChildApply = (value, label) => (value?.args ?? []).find((item) => applyLabel(item) === label);
const cellValue = (cell, label) => {
  assert.ok(cell, `missing ${label} cell`);
  assert.equal(cell.args?.length, 1, `${label} cell arity`);
  return cell.args[0];
};
const singleCell = (label) => {
  const cells = findApplies(root, label);
  assert.equal(cells.length, 1, `expected one ${label} cell`);
  return cells[0];
};
const tokenValue = (value, label) => {
  assert.equal(value?.node, "KToken", `${label} is not a KToken`);
  return value.token;
};
const output = cellValue(singleCell("<output>"), "<output>");
const status = cellValue(singleCell("<statusCode>"), "<statusCode>");
const log = cellValue(singleCell("<log>"), "<log>");
const txPending = cellValue(singleCell("<txPending>"), "<txPending>");
const accounts = findApplies(root, "<account>").map((account) => {
  const accountId = tokenValue(cellValue(directChildApply(account, "<acctID>"), "<acctID>"), "<acctID>");
  const nonce = tokenValue(cellValue(directChildApply(account, "<nonce>"), "<nonce>"), "<nonce>");
  const storage = cellValue(directChildApply(account, "<storage>"), "<storage>");
  const originalStorage = cellValue(directChildApply(account, "<origStorage>"), "<origStorage>");
  return { accountId, nonce, storageEqualsOriginal: JSON.stringify(storage) === JSON.stringify(originalStorage) };
});
process.stdout.write(`${JSON.stringify({
  schemaVersion: 1,
  status: "CALIBRATION_OBSERVATION_CREDIT_0",
  proofCredit: false,
  nodePath,
  outputToken: tokenValue(output, "<output>"),
  statusLabel: applyLabel(status),
  logLabel: applyLabel(log),
  txPendingLabel: applyLabel(txPending),
  accounts
}, null, 2)}\n`);
