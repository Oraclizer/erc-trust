#!/usr/bin/env node
// Bounded executable control for one remaining ABI-04 dynamic-offset leaf.
// This reconstructs the exact manifest mutant and interprets its dispatcher;
// it is deliberately not a KEVM proof and grants no replay credit.
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const familyDir = path.dirname(fileURLToPath(import.meta.url));
const rowDir = path.dirname(familyDir);
const repositoryRoot = path.resolve(rowDir, "../../../..");
const [claimId] = process.argv.slice(2);
assert.ok(claimId, "usage: dynamic-offset-leaf-mutant-control-v2.mjs CLAIM_ID");

const replayIndex = JSON.parse(fs.readFileSync(path.join(familyDir, "remaining-leaves-replay-index-v2.json"), "utf8"));
const claimsIndex = JSON.parse(fs.readFileSync(path.join(familyDir, "claims-index-v1.json"), "utf8"));
const manifest = JSON.parse(fs.readFileSync(path.join(rowDir, "mutation", "mutation-manifest.json"), "utf8"));
const bridge = fs.readFileSync(path.join(rowDir, "generated", "mutant-runtime-bridge.k"), "utf8");
const descriptor = replayIndex.leaves.find((leaf) => leaf.claimId === claimId);
const indexedClaim = claimsIndex.claims.find((leaf) => leaf.claimId === claimId);
assert.ok(descriptor, `claim is not one of the five remaining leaves: ${claimId}`);
assert.ok(indexedClaim, `claim missing from claims index: ${claimId}`);
assert.equal(indexedClaim.claim.sha256, descriptor.claimSourceSha256);
assert.equal(indexedClaim.selector, descriptor.selector);
assert.equal(indexedClaim.module, descriptor.module);

const runtime = manifest.runtimes.find(({ id }) => id === descriptor.runtimeId);
assert.ok(runtime, `runtime missing from mutation manifest: ${descriptor.runtimeId}`);
const claimPath = path.join(repositoryRoot, ...descriptor.claimPath.split("/"));
const claim = fs.readFileSync(claimPath, "utf8");
const sha256 = (value) => crypto.createHash("sha256").update(value).digest("hex");
assert.equal(sha256(fs.readFileSync(claimPath)), descriptor.claimSourceSha256);
assert.match(claim, /<statusCode> \.StatusCode => EVMC_REVERT <\/statusCode>/);
assert.match(claim, /<output> \.Bytes <\/output>/);
assert.ok(claim.includes(`<data> #parseByteStack("${indexedClaim.calldata}") </data>`));

const canonicalPath = path.join(repositoryRoot, ...runtime.runtimePath.split("/"));
const canonicalHex = fs.readFileSync(canonicalPath, "utf8").trim();
assert.match(canonicalHex, /^0x[0-9a-f]+$/);
const canonical = Buffer.from(canonicalHex.slice(2), "hex");
assert.equal(canonical.length, runtime.canonicalLength);
assert.equal(sha256(canonical), runtime.canonicalSha256);
assert.equal(runtime.canonicalSha256, descriptor.canonicalRuntimeSha256);

const stub = Buffer.from(runtime.appendedSuccessStubHex.slice(2), "hex");
assert.equal(stub.toString("hex"), "5b60006000f3");
const alignmentPadding = Buffer.from(runtime.alignmentPaddingHex.slice(2), "hex");
assert.equal(alignmentPadding.length, runtime.alignmentPaddingBytes);
assert.equal(runtime.appendedSuccessStubOffset, canonical.length + alignmentPadding.length);
const reconstructed = Buffer.from(canonical);
for (const patch of runtime.patches) {
  const selector = Buffer.from(patch.selector.slice(2), "hex");
  assert.equal(reconstructed[patch.dispatcherOffset], 0x63);
  assert.deepEqual(reconstructed.subarray(patch.dispatcherOffset + 1, patch.dispatcherOffset + 5), selector);
  assert.equal(reconstructed[patch.dispatcherOffset + 5], 0x14);
  assert.equal(reconstructed[patch.dispatcherOffset + 6], 0x61);
  assert.equal(patch.destinationOffset, patch.dispatcherOffset + 7);
  assert.equal(reconstructed.readUInt16BE(patch.destinationOffset), patch.originalDestination);
  assert.equal(reconstructed[patch.destinationOffset + 2], 0x57);
  reconstructed.writeUInt16BE(patch.mutatedDestination, patch.destinationOffset);
}
const mutated = Buffer.concat([reconstructed, alignmentPadding, stub]);
assert.equal(mutated.length, runtime.mutatedLength);
assert.equal(sha256(mutated), runtime.mutatedSha256);
assert.equal(runtime.mutatedSha256, descriptor.mutatedRuntimeSha256);

const bridgeFunction = `#trust${runtime.id}Runtime`;
const escapedBridgeFunction = bridgeFunction.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const bridgeMatch = bridge.match(new RegExp(`${escapedBridgeFunction}\\(\\) => #parseByteStack\\(\"(0x[0-9a-f]+)\"\\)`));
assert.ok(bridgeMatch, `mutated bridge function missing: ${bridgeFunction}`);
assert.equal(bridgeMatch[1], `0x${mutated.toString("hex")}`);

function validJumpDestinations(code) {
  const destinations = new Set();
  for (let pc = 0; pc < code.length;) {
    const opcode = code[pc];
    if (opcode === 0x5b) destinations.add(pc);
    pc += 1 + (opcode >= 0x60 && opcode <= 0x7f ? opcode - 0x5f : 0);
  }
  return destinations;
}

const validDestinations = validJumpDestinations(mutated);
assert.equal(runtime.appendedSuccessStubIsValidJumpDestination, true);
assert.ok(validDestinations.has(runtime.appendedSuccessStubOffset), "appended success stub is not an instruction-boundary JUMPDEST");

const mask256 = (1n << 256n) - 1n;
const pop = (stack) => {
  assert.ok(stack.length > 0, "stack underflow");
  return stack.pop();
};
const toWord = (bytes) => bytes.reduce((value, byte) => (value << 8n) | BigInt(byte), 0n);
const ensureMemory = (memory, size) => {
  if (memory.length >= size) return memory;
  const expanded = Buffer.alloc(size);
  memory.copy(expanded);
  return expanded;
};

function executeDispatcher(code, calldata, maximumSteps = 512) {
  const stack = [];
  const jumpTargets = [];
  const jumpDestinations = validJumpDestinations(code);
  let memory = Buffer.alloc(0);
  let pc = 0;
  for (let steps = 1; steps <= maximumSteps; steps += 1) {
    const opcodePc = pc;
    const opcode = code[pc++];
    assert.notEqual(opcode, undefined, "program counter out of range");
    if (opcode === 0x5f) {
      stack.push(0n);
    } else if (opcode >= 0x60 && opcode <= 0x7f) {
      const width = opcode - 0x5f;
      stack.push(toWord(code.subarray(pc, pc + width)));
      pc += width;
    } else if (opcode >= 0x80 && opcode <= 0x8f) {
      const depth = opcode - 0x7f;
      assert.ok(stack.length >= depth, "DUP stack underflow");
      stack.push(stack[stack.length - depth]);
    } else if (opcode >= 0x90 && opcode <= 0x9f) {
      const depth = opcode - 0x8f;
      assert.ok(stack.length > depth, "SWAP stack underflow");
      const top = stack.length - 1;
      [stack[top], stack[top - depth]] = [stack[top - depth], stack[top]];
    } else if (opcode === 0x50) {
      pop(stack);
    } else if (opcode === 0x10) {
      const first = pop(stack);
      const second = pop(stack);
      stack.push(first < second ? 1n : 0n);
    } else if (opcode === 0x14) {
      stack.push(pop(stack) === pop(stack) ? 1n : 0n);
    } else if (opcode === 0x15) {
      stack.push(pop(stack) === 0n ? 1n : 0n);
    } else if (opcode === 0x1c) {
      const shift = pop(stack);
      const value = pop(stack);
      stack.push(shift >= 256n ? 0n : value >> shift);
    } else if (opcode === 0x35) {
      const offset = Number(pop(stack));
      const word = Buffer.alloc(32);
      calldata.subarray(offset, offset + 32).copy(word);
      stack.push(toWord(word));
    } else if (opcode === 0x36) {
      stack.push(BigInt(calldata.length));
    } else if (opcode === 0x52) {
      const offset = Number(pop(stack));
      const value = pop(stack) & mask256;
      memory = ensureMemory(memory, offset + 32);
      Buffer.from(value.toString(16).padStart(64, "0"), "hex").copy(memory, offset);
    } else if (opcode === 0x56) {
      const destination = Number(pop(stack));
      assert.ok(jumpDestinations.has(destination), "JUMP target must be an instruction-boundary JUMPDEST");
      jumpTargets.push({ opcodePc, destination, conditional: false });
      pc = destination;
    } else if (opcode === 0x57) {
      const destination = Number(pop(stack));
      const condition = pop(stack);
      if (condition !== 0n) {
        assert.ok(jumpDestinations.has(destination), "JUMPI target must be an instruction-boundary JUMPDEST");
        jumpTargets.push({ opcodePc, destination, conditional: true });
        pc = destination;
      }
    } else if (opcode === 0x5b) {
      // JUMPDEST
    } else if (opcode === 0xf3 || opcode === 0xfd) {
      const offset = Number(pop(stack));
      const size = Number(pop(stack));
      const output = Buffer.alloc(size);
      memory.subarray(offset, offset + size).copy(output);
      return {
        statusCode: opcode === 0xf3 ? "EVMC_SUCCESS" : "EVMC_REVERT",
        outputHex: `0x${output.toString("hex")}`,
        terminalOpcode: `0x${opcode.toString(16)}`,
        terminalOpcodePc: opcodePc,
        steps,
        jumpTargets,
      };
    } else {
      throw new Error(`unsupported dispatcher opcode 0x${opcode.toString(16)} at pc ${opcodePc}`);
    }
  }
  throw new Error(`dispatcher did not terminate within ${maximumSteps} steps`);
}

const targetPatch = runtime.patches.find(({ selector }) => selector === descriptor.selector);
assert.ok(targetPatch, `selector patch missing: ${descriptor.selector}`);
for (const key of ["dispatcherOffset", "destinationOffset", "originalDestination", "mutatedDestination"]) {
  assert.equal(targetPatch[key], descriptor[key], `descriptor mismatch: ${key}`);
}
const calldata = Buffer.from(indexedClaim.calldata.slice(2), "hex");
const observation = executeDispatcher(mutated, calldata);
assert.equal(observation.statusCode, "EVMC_SUCCESS");
assert.equal(observation.outputHex, "0x");
assert.equal(observation.terminalOpcode, "0xf3");
assert.equal(observation.terminalOpcodePc, runtime.appendedSuccessStubOffset + stub.length - 1);
assert.ok(observation.jumpTargets.some(({ destination }) => destination === runtime.appendedSuccessStubOffset));

console.log(JSON.stringify({
  status: "PASS_EXECUTABLE_MUTANT_CONTROL_NOT_PROOF",
  obligationId: "ABI-04",
  claimId: descriptor.claimId,
  endpointId: descriptor.endpointId,
  selector: descriptor.selector,
  unchangedClaimSourceSha256: descriptor.claimSourceSha256,
  unchangedStrippedClaimSha256: descriptor.strippedClaimSha256,
  runtimeId: runtime.id,
  canonicalRuntimeSha256: runtime.canonicalSha256,
  mutatedRuntimeSha256: runtime.mutatedSha256,
  dispatcherOffset: targetPatch.dispatcherOffset,
  destinationOffset: targetPatch.destinationOffset,
  originalDestination: targetPatch.originalDestination,
  mutatedDestination: targetPatch.mutatedDestination,
  appendedSuccessStubHex: runtime.appendedSuccessStubHex,
  observation,
  contradiction: "The unchanged K claim requires EVMC_REVERT and empty output.",
  proofCredit: false,
}, null, 2));
