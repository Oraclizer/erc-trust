#!/usr/bin/env node
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const rowDir = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(rowDir, "../../../..");
const readJson = (value) => JSON.parse(fs.readFileSync(value, "utf8"));
const sha256 = (value) => crypto.createHash("sha256").update(value).digest("hex");
const fileSha256 = (value) => sha256(fs.readFileSync(value));
const resolveRepo = (value) => path.join(repositoryRoot, ...value.split("/"));
const scanInstructions = (bytes) => {
  const boundaries = new Set();
  const jumpDestinations = new Set();
  let pc = 0;
  let finalInstructionStart = 0;
  while (pc < bytes.length) {
    finalInstructionStart = pc;
    boundaries.add(pc);
    const opcode = bytes[pc];
    if (opcode === 0x5b) jumpDestinations.add(pc);
    pc += 1 + (opcode >= 0x60 && opcode <= 0x7f ? opcode - 0x5f : 0);
  }
  return { boundaries, jumpDestinations, finalInstructionStart, nextInstructionOffset: pc };
};

const matrixPath = path.join(rowDir, "case-matrix.json");
const bridgePath = path.join(rowDir, "bridge", "row-bridge.json");
const manifestPath = path.join(rowDir, "bridge", "row-manifest.json");
const mutationPath = path.join(rowDir, "mutation", "mutation-manifest.json");
const matrix = readJson(matrixPath);
const bridge = readJson(bridgePath);
const manifest = readJson(manifestPath);
const mutation = readJson(mutationPath);

assert.equal(matrix.obligationId, "ABI-04");
assert.equal(matrix.classification, "STATIC_DECOMPOSED_CLAIM_PLAN_NOT_DISCHARGE_EVIDENCE");
assert.deepEqual(matrix.counts, { endpoints: 6, cases: 69, shortHead: 12, offset: 6, length: 6, highBitsAndInvalidEnum: 45 });
assert.equal(new Set(matrix.cases.map((item) => item.caseId)).size, 69);
assert.equal(new Set(matrix.endpoints.map((item) => item.id)).size, 6);
assert.equal(matrix.semanticCorrections.length, 1);
const enumCorrection = matrix.semanticCorrections[0];
assert.equal(enumCorrection.correctionId, "ABI04-ENUM-NONCANONICAL-WORD-V1");
assert.equal(enumCorrection.status, "REVIEWED_FAIL_CLOSED_INPUT_CORRECTION");
assert.deepEqual(enumCorrection.priorValues, { action: "0x6", reversal: "0x3" });
assert.deepEqual(enumCorrection.correctedValues, { action: "0x106", reversal: "0x103" });
assert.equal(enumCorrection.priorReplayCredit, false);
assert.equal(enumCorrection.outputPropertyWeakened, false);
assert.equal(enumCorrection.caseCountChanged, false);

const endpointById = new Map(matrix.endpoints.map((item) => [item.id, item]));
const expectedEnumCaseIds = matrix.endpoints.map((endpoint) => `ABI04-${endpoint.id}-enum-out-of-range`).sort();
assert.deepEqual(enumCorrection.affectedCaseIds, expectedEnumCaseIds);
const enumCases = matrix.cases.filter((item) => item.subtype === "enum-out-of-range");
assert.deepEqual(enumCases.map((item) => item.caseId).sort(), expectedEnumCaseIds);
assert.deepEqual(
  matrix.cases.filter((item) => item.encodingContract !== null).map((item) => item.caseId).sort(),
  expectedEnumCaseIds,
  "enum encoding contracts must exist on the reviewed exact case set only",
);
for (const item of enumCases) {
  const endpoint = endpointById.get(item.endpointId);
  assert.ok(endpoint, `${item.caseId}: enum endpoint`);
  const cardinality = endpoint.shape === "action" ? 6 : 3;
  const expectedFieldIndex = endpoint.shape === "action" ? 2 : 3;
  assert.equal(item.caseId, `ABI04-${item.endpointId}-enum-out-of-range`, `${item.caseId}: enum case identity`);
  assert.equal(item.fieldType, "uint8-enum", `${item.caseId}: enum field type`);
  assert.equal(item.fieldIndex, expectedFieldIndex, `${item.caseId}: enum field index`);
  assert.equal(item.calldataBytes, endpoint.canonicalCalldataBytes, `${item.caseId}: canonical tuple length`);
  const correctedValue = (1n << 8n) | BigInt(cardinality);
  assert.equal(item.fieldValueHex, `0x${correctedValue.toString(16)}`, `${item.caseId}: corrected enum value`);
  assert.deepEqual(item.encodingContract, {
    externalAbiType: "uint8",
    externalAbiWidthBits: 8,
    dirtyHighBitsRequired: true,
    lowByteEnumCardinality: cardinality,
    lowByteValue: cardinality,
    lowByteOutOfRangeRequired: true,
    classification: "NONCANONICAL_UINT8_WORD_WITH_OUT_OF_RANGE_LOW_BYTE",
  }, `${item.caseId}: enum encoding contract`);
  const calldata = Buffer.from(item.calldata.slice(2), "hex");
  const wordOffset = 4 + item.fieldIndex * 32;
  const encodedWord = BigInt(`0x${calldata.subarray(wordOffset, wordOffset + 32).toString("hex")}`);
  assert.equal(encodedWord, correctedValue, `${item.caseId}: encoded enum word`);
  assert.ok((encodedWord >> 8n) > 0n, `${item.caseId}: dirty enum high bits`);
  assert.ok(Number(encodedWord & 0xffn) >= cardinality, `${item.caseId}: low-byte enum range`);
}
for (const endpoint of matrix.endpoints) {
  const compiler = readJson(resolveRepo(endpoint.compilerOutput));
  const methodIdentifiers = compiler.contracts[endpoint.source][endpoint.contract].evm.methodIdentifiers;
  assert.equal(`0x${methodIdentifiers[endpoint.signature]}`, endpoint.selector, `${endpoint.id}: compiler selector`);
  const runtimeArtifact = fs.readFileSync(resolveRepo(endpoint.resolvedRuntime.path));
  const runtimeHex = runtimeArtifact.toString("utf8").trim();
  const runtimeBytes = Buffer.from(runtimeHex.slice(2), "hex");
  assert.equal(sha256(runtimeArtifact), endpoint.resolvedRuntime.artifactSha256, `${endpoint.id}: runtime artifact hash`);
  assert.equal(sha256(runtimeBytes), endpoint.resolvedRuntime.runtimeBytesSha256, `${endpoint.id}: runtime bytes hash`);
  assert.equal(runtimeBytes.length, endpoint.resolvedRuntime.runtimeBytes, `${endpoint.id}: runtime byte length`);
  const endpointCases = matrix.cases.filter((item) => item.endpointId === endpoint.id);
  assert.equal(endpointCases.length, endpoint.shape === "action" ? 14 : 9, `${endpoint.id}: case count`);
}

for (const item of matrix.cases) {
  const endpoint = endpointById.get(item.endpointId);
  assert.ok(endpoint, `${item.caseId}: endpoint`);
  assert.ok(item.calldata.startsWith(endpoint.selector), `${item.caseId}: selector prefix`);
  assert.equal((item.calldata.length - 2) / 2, item.calldataBytes, `${item.caseId}: byte length`);
  assert.equal(sha256(Buffer.from(item.calldata.slice(2), "hex")), item.calldataSha256, `${item.caseId}: calldata hash`);
  const claimPath = resolveRepo(item.claim.path);
  assert.equal(fileSha256(claimPath), item.claim.sha256, `${item.caseId}: claim hash`);
  const claim = fs.readFileSync(claimPath, "utf8");
  assert.ok(claim.includes(`module ${item.module}`), `${item.caseId}: module`);
  assert.ok(claim.includes(`#parseByteStack("${item.calldata}")`), `${item.caseId}: calldata literal`);
  assert.ok(claim.includes(`<acctID> ${endpoint.addressDecimal} </acctID>`), `${item.caseId}: endpoint address`);
  assert.ok(claim.includes(`<code> ${endpoint.runtimeMacro} </code>`), `${item.caseId}: runtime macro`);
  assert.ok(claim.includes(`andBool notBool ${endpoint.guardSlot} in_keys(ENDPOINT_STORAGE)`), `${item.caseId}: guard anti-alias`);
  assert.equal((claim.match(/<log> \.List <\/log>/g) ?? []).length, 1, `${item.caseId}: committed-log stutter`);
  assert.equal((claim.match(/<statusCode> \.StatusCode => EVMC_REVERT <\/statusCode>/g) ?? []).length, 1, `${item.caseId}: revert target`);
}

const rootMaterial = matrix.cases.map((item) => ({
  caseId: item.caseId,
  endpointId: item.endpointId,
  malformedClass: item.malformedClass,
  calldataSha256: item.calldataSha256,
  claimSha256: item.claim.sha256,
}));
assert.equal(sha256(Buffer.from(JSON.stringify(rootMaterial))), matrix.caseMatrixRootSha256, "matrix root");
assert.equal(bridge.caseMatrix.sha256, fileSha256(matrixPath), "bridge matrix file hash");
assert.equal(bridge.caseMatrix.rootSha256, matrix.caseMatrixRootSha256, "bridge matrix root");
assert.equal(fileSha256(resolveRepo(bridge.generator.path)), bridge.generator.sha256, "bridge generator hash");
assert.equal(fileSha256(resolveRepo(bridge.reverseCheck.path)), bridge.reverseCheck.sha256, "bridge reverse-check hash");
for (const artifact of [...bridge.compilerOutputs, ...bridge.generated, bridge.mutationManifest]) {
  assert.equal(fileSha256(resolveRepo(artifact.path)), artifact.sha256, `bridge artifact: ${artifact.path}`);
}
for (const artifact of bridge.resolvedRuntimes) {
  const runtimeArtifact = fs.readFileSync(resolveRepo(artifact.path));
  const runtimeBytes = Buffer.from(runtimeArtifact.toString("utf8").trim().slice(2), "hex");
  assert.equal(sha256(runtimeArtifact), artifact.artifactSha256, `bridge runtime artifact: ${artifact.path}`);
  assert.equal(sha256(runtimeBytes), artifact.runtimeBytesSha256, `bridge runtime bytes: ${artifact.path}`);
  assert.equal(runtimeBytes.length, artifact.runtimeBytes, `bridge runtime length: ${artifact.path}`);
}
assert.equal(bridge.claimsRootSha256, sha256(Buffer.from(matrix.cases.map((item) => item.claim.sha256).join("\n") + "\n")), "claims root");
const rowKBridgeArtifact = bridge.generated.find((item) => item.path.endsWith("generated/abi-04-row-bridge.k"));
assert.ok(rowKBridgeArtifact, "generated row K bridge entry");
const rowKBridge = fs.readFileSync(resolveRepo(rowKBridgeArtifact.path), "utf8");
assert.ok(rowKBridge.includes(`rule #trustAbi04CaseMatrixRootSha256 => "${matrix.caseMatrixRootSha256}"`), "K bridge matrix root");
assert.ok(rowKBridge.includes(`rule #trustAbi04EndpointCount => ${matrix.counts.endpoints}`), "K bridge endpoint count");
assert.ok(rowKBridge.includes(`rule #trustAbi04CaseCount => ${matrix.counts.cases}`), "K bridge case count");
for (const endpoint of matrix.endpoints) {
  assert.ok(rowKBridge.includes(`Selector => ${Number.parseInt(endpoint.selector.slice(2), 16)}`), `${endpoint.id}: K bridge selector`);
}
const generatedTheoryArtifact = bridge.generated.find((item) => item.path.endsWith("isabelle/ABI_04_Generated.thy"));
assert.ok(generatedTheoryArtifact, "generated Isabelle bridge entry");
const generatedTheory = fs.readFileSync(resolveRepo(generatedTheoryArtifact.path), "utf8");
assert.ok(generatedTheory.includes("imports ERC_TRUST.TRUST_Runtime_Bridge_Generated"), "generated Isabelle canonical bridge import");
assert.ok(generatedTheory.includes(`abi_04_case_matrix_root_sha256 = ''${matrix.caseMatrixRootSha256}''`), "generated Isabelle matrix root");
for (const runtime of mutation.runtimes) {
  assert.ok(generatedTheory.includes(runtime.canonicalSha256), `${runtime.id}: generated Isabelle canonical runtime hash`);
  assert.ok(generatedTheory.includes(runtime.mutatedSha256), `${runtime.id}: generated Isabelle mutant runtime hash`);
}
assert.ok(!/^\s*(sorry|oops|axiomatization|oracle)\b|\bby\s+eval\b|\bnative_decide\b|\bskip_proof\b/m.test(generatedTheory), "banned generated Isabelle source form");

assert.equal(mutation.mutationKind, "EXECUTABLE_SEMANTIC_BYTECODE_MUTANT");
const mutantBridgeArtifact = bridge.generated.find((item) => item.path.endsWith("generated/mutant-runtime-bridge.k"));
assert.ok(mutantBridgeArtifact, "generated mutant bridge entry");
const mutantBridge = fs.readFileSync(resolveRepo(mutantBridgeArtifact.path), "utf8");
for (const runtime of mutation.runtimes) {
  const originalHex = fs.readFileSync(resolveRepo(runtime.runtimePath), "utf8").trim();
  const original = Buffer.from(originalHex.slice(2), "hex");
  const originalScan = scanInstructions(original);
  const padding = Buffer.from(runtime.alignmentPaddingHex.slice(2), "hex");
  const reconstructed = Buffer.concat([Buffer.from(original), padding, Buffer.from("5b60006000f3", "hex")]);
  assert.equal(sha256(original), runtime.canonicalSha256, `${runtime.id}: canonical mutation input`);
  assert.equal(runtime.alignmentPaddingBytes, originalScan.nextInstructionOffset - original.length, `${runtime.id}: EOF-crossing PUSH padding`);
  assert.equal(padding.length, runtime.alignmentPaddingBytes, `${runtime.id}: padding length`);
  assert.equal(runtime.canonicalTailInstructionStart, originalScan.finalInstructionStart, `${runtime.id}: canonical tail instruction`);
  assert.equal(runtime.canonicalNextInstructionOffset, originalScan.nextInstructionOffset, `${runtime.id}: next instruction boundary`);
  assert.equal(runtime.mutatedLength, runtime.canonicalLength + padding.length + 6, `${runtime.id}: padded stub length`);
  assert.equal(runtime.appendedSuccessStubHex, "0x5b60006000f3", `${runtime.id}: success stub`);
  for (const patch of runtime.patches) {
    assert.equal(original[patch.dispatcherOffset], 0x63, `${runtime.id}/${patch.selector}: PUSH4`);
    assert.equal(original.subarray(patch.dispatcherOffset + 1, patch.dispatcherOffset + 5).toString("hex"), patch.selector.slice(2), `${runtime.id}/${patch.selector}: selector bytes`);
    assert.equal(original[patch.destinationOffset - 1], 0x61, `${runtime.id}/${patch.selector}: PUSH2`);
    assert.equal(original[patch.destinationOffset + 2], 0x57, `${runtime.id}/${patch.selector}: JUMPI`);
    assert.equal(original.readUInt16BE(patch.destinationOffset), patch.originalDestination, `${runtime.id}/${patch.selector}: original destination`);
    assert.equal(patch.mutatedDestination, runtime.appendedSuccessStubOffset, `${runtime.id}/${patch.selector}: patched destination`);
    reconstructed.writeUInt16BE(patch.mutatedDestination, patch.destinationOffset);
  }
  assert.equal(reconstructed.length, runtime.mutatedLength, `${runtime.id}: reconstructed mutant length`);
  const reconstructedScan = scanInstructions(reconstructed);
  assert.equal(runtime.appendedSuccessStubIsValidJumpDestination, true, `${runtime.id}: manifest jumpdest classification`);
  assert.ok(reconstructedScan.boundaries.has(runtime.appendedSuccessStubOffset), `${runtime.id}: stub instruction boundary`);
  assert.ok(reconstructedScan.jumpDestinations.has(runtime.appendedSuccessStubOffset), `${runtime.id}: valid stub JUMPDEST`);
  assert.equal(sha256(reconstructed), runtime.mutatedSha256, `${runtime.id}: reconstructed mutant hash`);
  assert.ok(mutantBridge.includes(`#parseByteStack("0x${reconstructed.toString("hex")}")`), `${runtime.id}: mutant bridge bytes`);
}

assert.equal(manifest.bridge.sha256, fileSha256(bridgePath), "manifest bridge hash");
assert.equal(manifest.caseMatrix.sha256, fileSha256(matrixPath), "manifest matrix hash");
const theoryPath = resolveRepo(manifest.theorem.path);
assert.equal(manifest.theorem.sourceSha256, fileSha256(theoryPath), "manifest theory hash");
const theory = fs.readFileSync(theoryPath, "utf8");
assert.ok(theory.includes(`theorem ${manifest.theorem.name}:`), "named Isabelle theorem");
assert.ok(!/^\s*(sorry|oops|axiomatization|oracle)\b|\bby\s+eval\b|\bnative_decide\b|\bskip_proof\b/m.test(theory), "banned Isabelle source form");

console.log(JSON.stringify({
  status: "PASS",
  classification: "STATIC_REVERSE_CHECK_ONLY",
  obligationId: "ABI-04",
  caseMatrixRootSha256: matrix.caseMatrixRootSha256,
  endpoints: matrix.counts.endpoints,
  cases: matrix.counts.cases,
  bridgeSha256: fileSha256(bridgePath),
  manifestSha256: fileSha256(manifestPath),
  proofStatus: manifest.proofStatus,
}, null, 2));
