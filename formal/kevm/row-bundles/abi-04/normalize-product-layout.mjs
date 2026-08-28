#!/usr/bin/env node
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const rowDir = path.dirname(fileURLToPath(import.meta.url));
const write = process.argv.includes("--write");
const check = process.argv.includes("--check");
assert.notEqual(write, check, "use exactly one of --write or --check");

const textExtensions = new Set([".json", ".k", ".md", ".mjs", ".py", ".sh", ".thy"]);
const excludedNames = new Set(["normalize-product-layout.mjs"]);
const replacements = [
  ["formal/kevm/workers/abi-fail/abi-04", "formal/kevm/row-bundles/abi-04"],
  ['requires "../../../../trust-runtime-verification.k"', 'requires "../../../trust-runtime-verification.k"'],
  ['path.resolve(rowDir, "../../../../..")', 'path.resolve(rowDir, "../../../..")'],
  ['$script_dir/../../../../../..', '$script_dir/../../../../..'],
];
const prohibited = ["C:\\tmp", "/mnt/c/tmp", "formal/kevm/workers/abi-fail/abi-04"];

function walk(directory) {
  const output = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) output.push(...walk(absolute));
    else if (entry.isFile() && textExtensions.has(path.extname(entry.name)) && !excludedNames.has(entry.name)) output.push(absolute);
  }
  return output;
}

const changed = [];
for (const file of walk(rowDir)) {
  const before = fs.readFileSync(file, "utf8").replaceAll("\r\n", "\n");
  let after = before;
  for (const [from, to] of replacements) after = after.replaceAll(from, to);
  if (after !== before) {
    changed.push(path.relative(rowDir, file).split(path.sep).join("/"));
    if (write) fs.writeFileSync(file, after, "utf8");
  }
}

if (check) assert.deepEqual(changed, [], `stale layout paths: ${changed.join(", ")}`);

const violations = [];
for (const file of walk(rowDir)) {
  const text = fs.readFileSync(file, "utf8");
  for (const token of prohibited) if (text.includes(token)) violations.push({ file: path.relative(rowDir, file).split(path.sep).join("/"), token });
}
assert.deepEqual(violations, [], `prohibited product paths: ${JSON.stringify(violations)}`);

console.log(JSON.stringify({
  status: "PASS",
  mode: write ? "write" : "check",
  changedFiles: changed,
  changedCount: changed.length,
  prohibitedPathViolations: 0,
}, null, 2));
