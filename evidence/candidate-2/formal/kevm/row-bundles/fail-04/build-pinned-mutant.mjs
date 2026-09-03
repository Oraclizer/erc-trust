#!/usr/bin/env node
// Future pinned mutant compiler. This file is intentionally not run by the
// static wave; outputs are admitted only after exact lock and source checks.
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const rowDir = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(rowDir, "../../../..");
const readJson = (p) => JSON.parse(fs.readFileSync(p, "utf8"));
const sha = (v) => crypto.createHash("sha256").update(v).digest("hex");
const lock = readJson(path.join(root, "formal/kevm/dependencies.lock.json"));
assert.equal(sha(fs.readFileSync(path.join(root, "formal/kevm/dependencies.lock.json"))), "3134e7692086170f86b6dd42e7ebd0256c188da8db8cbd17241c3d2c8d315196");
const inputPath = path.join(root, "evidence/end-to-end-refinement/runtime-binding/native/standard-json-input.json");
const input = readJson(inputPath);
const sourceKey = "implementation/src/TrustPolicyBinding.sol";
const before = "        if (!ok || output.length != 128) {";
const after = "        if (!ok || output.length != 127) {";
assert.equal(input.sources[sourceKey].content.split(before).length - 1, 1);
input.sources[sourceKey].content = input.sources[sourceKey].content.replace(before, after);
const solc = process.env.FAIL04_SOLC_0_8_36;
assert.ok(solc, "set FAIL04_SOLC_0_8_36 to the exact pinned solc 0.8.36 binary");
assert.equal(sha(fs.readFileSync(solc)), lock.components.solc.binarySha256);
const result = spawnSync(solc, ["--standard-json"], { input: JSON.stringify(input), encoding: "utf8", maxBuffer: 256 * 1024 * 1024 });
if (result.error) throw result.error;
assert.equal(result.status, 0, result.stderr);
const output = JSON.parse(result.stdout);
const fatal = (output.errors || []).filter((item) => item.severity === "error");
assert.deepEqual(fatal, []);
const outDir = path.join(rowDir, "bridge");
fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, "mutant-standard-json-input.json"), JSON.stringify(input));
fs.writeFileSync(path.join(outDir, "mutant-standard-json-output.json"), JSON.stringify(output));
console.log(JSON.stringify({ status: "PINNED_MUTANT_COMPILED_NOT_PROOF", solcVersion: lock.components.solc.version }, null, 2));
