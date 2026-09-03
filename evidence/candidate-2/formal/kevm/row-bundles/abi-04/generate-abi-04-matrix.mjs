#!/usr/bin/env node
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const rowDir = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(rowDir, "../../../..");
const repo = (...parts) => path.join(repositoryRoot, ...parts);
const posix = (value) => path.relative(repositoryRoot, value).split(path.sep).join("/");
const sha256 = (value) => crypto.createHash("sha256").update(value).digest("hex");
const fileSha256 = (value) => sha256(fs.readFileSync(value));
const canonicalJson = (value) => JSON.stringify(value, Object.keys(value).sort());
const word = (value) => BigInt(value).toString(16).padStart(64, "0");
const writeMode = process.argv.includes("--write");
const checkMode = process.argv.includes("--check");
const planMode = process.argv.includes("--plan");
if ([writeMode, checkMode, planMode].filter(Boolean).length !== 1) throw new Error("use exactly one of --write, --check, or --plan");
const generatedContent = new Map();
const generationPlan = [];
function emit(filePath, content) {
  generatedContent.set(path.resolve(filePath), content);
  if (writeMode) fs.writeFileSync(filePath, content, "utf8");
}
function generatedSha256(filePath) {
  const content = generatedContent.get(path.resolve(filePath));
  return content === undefined ? fileSha256(filePath) : sha256(content);
}

const nativeOutputPath = repo(
  "evidence/end-to-end-refinement/runtime-binding/native/standard-json-output.json",
);
const profileOutputPath = repo(
  "evidence/end-to-end-refinement/runtime-binding/verified-profile/standard-json-output.json",
);
const nativeRuntimePath = repo(
  "evidence/end-to-end-refinement/runtime-binding/resolved/native/TrustToken.hex",
);
const profileRuntimePath = repo(
  "evidence/end-to-end-refinement/runtime-binding/resolved/verified-profile/ERC3643TrustAdapter.hex",
);

const ACTION_SIGNATURE =
  "(bytes32,bytes32,uint8,address,address,address,address,uint256,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,uint64,uint64,uint256,uint48,uint48)";
const REVERSAL_SIGNATURE =
  "(bytes32,bytes32,bytes32,uint8,bytes32,uint64,uint256,uint48,uint48)";

const endpoints = [
  {
    id: "native-regulatory-action",
    contract: "TrustToken",
    source: "implementation/src/TrustToken.sol",
    compilerOutputPath: nativeOutputPath,
    function: "executeRegulatoryAction",
    signature: `executeRegulatoryAction(${ACTION_SIGNATURE})`,
    selector: "9da23539",
    shape: "action",
    tupleWords: 21,
    address: "1324161310598743833836268493538283093091898295570",
    runtimeMacro: "#trustTrustTokenRuntime()",
    guardSlot: 29,
    runtimePath: nativeRuntimePath,
    runtimeId: "TrustToken",
  },
  {
    id: "native-erc7943-action",
    contract: "TrustToken",
    source: "implementation/src/TrustToken.sol",
    compilerOutputPath: nativeOutputPath,
    function: "executeERC7943Action",
    signature: `executeERC7943Action(${ACTION_SIGNATURE})`,
    selector: "9295b54c",
    shape: "action",
    tupleWords: 21,
    address: "1324161310598743833836268493538283093091898295570",
    runtimeMacro: "#trustTrustTokenRuntime()",
    guardSlot: 29,
    runtimePath: nativeRuntimePath,
    runtimeId: "TrustToken",
  },
  {
    id: "profile-regulatory-action",
    contract: "ERC3643TrustAdapter",
    source: "implementation/src/profiles/ERC3643TrustAdapter.sol",
    compilerOutputPath: profileOutputPath,
    function: "executeRegulatoryAction",
    signature: `executeRegulatoryAction(${ACTION_SIGNATURE})`,
    selector: "9da23539",
    shape: "action",
    tupleWords: 21,
    address: "7973173272142053871140891859049224849605192591",
    runtimeMacro: "#trustERC3643TrustAdapterRuntime()",
    guardSlot: 0,
    runtimePath: profileRuntimePath,
    runtimeId: "ERC3643TrustAdapter",
  },
  {
    id: "native-regulatory-reversal",
    contract: "TrustToken",
    source: "implementation/src/TrustToken.sol",
    compilerOutputPath: nativeOutputPath,
    function: "executeRegulatoryReversal",
    signature: `executeRegulatoryReversal(${REVERSAL_SIGNATURE})`,
    selector: "7aab169b",
    shape: "reversal",
    tupleWords: 9,
    address: "1324161310598743833836268493538283093091898295570",
    runtimeMacro: "#trustTrustTokenRuntime()",
    guardSlot: 29,
    runtimePath: nativeRuntimePath,
    runtimeId: "TrustToken",
  },
  {
    id: "native-erc7943-reversal",
    contract: "TrustToken",
    source: "implementation/src/TrustToken.sol",
    compilerOutputPath: nativeOutputPath,
    function: "executeERC7943Reversal",
    signature: `executeERC7943Reversal(${REVERSAL_SIGNATURE})`,
    selector: "75c28d96",
    shape: "reversal",
    tupleWords: 9,
    address: "1324161310598743833836268493538283093091898295570",
    runtimeMacro: "#trustTrustTokenRuntime()",
    guardSlot: 29,
    runtimePath: nativeRuntimePath,
    runtimeId: "TrustToken",
  },
  {
    id: "profile-regulatory-reversal",
    contract: "ERC3643TrustAdapter",
    source: "implementation/src/profiles/ERC3643TrustAdapter.sol",
    compilerOutputPath: profileOutputPath,
    function: "executeRegulatoryReversal",
    signature: `executeRegulatoryReversal(${REVERSAL_SIGNATURE})`,
    selector: "7aab169b",
    shape: "reversal",
    tupleWords: 9,
    address: "7973173272142053871140891859049224849605192591",
    runtimeMacro: "#trustERC3643TrustAdapterRuntime()",
    guardSlot: 0,
    runtimePath: profileRuntimePath,
    runtimeId: "ERC3643TrustAdapter",
  },
];

const enumNoncanonicalWord = (cardinality) => (1n << 8n) | BigInt(cardinality);
const enumEncodingContract = (cardinality) => ({
  externalAbiType: "uint8",
  externalAbiWidthBits: 8,
  dirtyHighBitsRequired: true,
  lowByteEnumCardinality: cardinality,
  lowByteValue: cardinality,
  lowByteOutOfRangeRequired: true,
  classification: "NONCANONICAL_UINT8_WORD_WITH_OUT_OF_RANGE_LOW_BYTE",
});

const fieldCases = {
  action: [
    {
      name: "enum-out-of-range", malformedClass: "high_bits", fieldIndex: 2, fieldType: "uint8-enum",
      value: enumNoncanonicalWord(6), encodingContract: enumEncodingContract(6),
    },
    { name: "enum-dirty-high-bits", malformedClass: "high_bits", fieldIndex: 2, fieldType: "uint8-enum", value: 1n << 8n },
    ...[3, 4, 5, 6].map((fieldIndex) => ({
      name: `address-${fieldIndex}-dirty-high-bits`, malformedClass: "high_bits", fieldIndex,
      fieldType: "address", value: 1n << 160n,
    })),
    ...[16, 17].map((fieldIndex) => ({
      name: `uint64-${fieldIndex}-dirty-high-bits`, malformedClass: "high_bits", fieldIndex,
      fieldType: "uint64", value: 1n << 64n,
    })),
    ...[19, 20].map((fieldIndex) => ({
      name: `uint48-${fieldIndex}-dirty-high-bits`, malformedClass: "high_bits", fieldIndex,
      fieldType: "uint48", value: 1n << 48n,
    })),
  ],
  reversal: [
    {
      name: "enum-out-of-range", malformedClass: "high_bits", fieldIndex: 3, fieldType: "uint8-enum",
      value: enumNoncanonicalWord(3), encodingContract: enumEncodingContract(3),
    },
    { name: "enum-dirty-high-bits", malformedClass: "high_bits", fieldIndex: 3, fieldType: "uint8-enum", value: 1n << 8n },
    { name: "uint64-5-dirty-high-bits", malformedClass: "high_bits", fieldIndex: 5, fieldType: "uint64", value: 1n << 64n },
    { name: "uint48-7-dirty-high-bits", malformedClass: "high_bits", fieldIndex: 7, fieldType: "uint48", value: 1n << 48n },
    { name: "uint48-8-dirty-high-bits", malformedClass: "high_bits", fieldIndex: 8, fieldType: "uint48", value: 1n << 48n },
  ],
};

function calldataFor(endpoint, recipe) {
  if (recipe.kind === "selector-only") return `0x${endpoint.selector}`;
  const words = Array(endpoint.tupleWords).fill(word(0));
  if (recipe.kind === "last-word-missing") words.pop();
  if (recipe.kind === "field") words[recipe.fieldIndex] = word(recipe.value);
  if (recipe.kind === "dynamic-offset-envelope") words.unshift(word(32));
  if (recipe.kind === "dynamic-length-envelope") words.unshift(word(endpoint.tupleWords), word(32));
  return `0x${endpoint.selector}${words.join("")}`;
}

function recipesFor(endpoint) {
  return [
    { name: "selector-only", malformedClass: "short_head", kind: "selector-only" },
    { name: "last-word-missing", malformedClass: "short_head", kind: "last-word-missing" },
    {
      name: "dynamic-offset-envelope", malformedClass: "offset", kind: "dynamic-offset-envelope",
      overlap: "This static tuple has no canonical offset word; the envelope is overlength and also lies in ABI-03's trailing-calldata domain.",
    },
    {
      name: "dynamic-length-envelope", malformedClass: "length", kind: "dynamic-length-envelope",
      overlap: "This static tuple has no canonical length word; the envelope is overlength and also lies in ABI-03's trailing-calldata domain.",
    },
    ...fieldCases[endpoint.shape].map((item) => ({ ...item, kind: "field" })),
  ];
}

const EMPTY_OMMERS_HASH_DECIMAL = BigInt("0x1dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347").toString();
const ZERO_BLOOM_HEX = `0x${"00".repeat(256)}`;

function accountState(endpoint, senderNonce) {
  const storage = `(${endpoint.guardSlot} |-> 0) ENDPOINT_STORAGE:Map`;
  return `                <account>
                  <acctID> 0 </acctID>
                  <balance> 0 </balance>
                  <code> .Bytes </code>
                  <storage> .Map </storage>
                  <origStorage> .Map </origStorage>
                  <transientStorage> .Map </transientStorage>
                  <nonce> 0 </nonce>
                </account>
                <account>
                  <acctID> 1390849295786071768276380950238675083608645509734 </acctID>
                  <balance> 1000000000 </balance>
                  <code> .Bytes </code>
                  <storage> .Map </storage>
                  <origStorage> .Map </origStorage>
                  <transientStorage> .Map </transientStorage>
                  <nonce> ${senderNonce} </nonce>
                </account>
                <account>
                  <acctID> ${endpoint.address} </acctID>
                  <balance> 0 </balance>
                  <code> ${endpoint.runtimeMacro} </code>
                  <storage> ${storage} </storage>
                  <origStorage> ${storage.replace(":Map", "")} </origStorage>
                  <transientStorage> .Map </transientStorage>
                  <nonce> 1 </nonce>
                </account>`;
}

function claimSource(caseRecord, endpoint) {
  const data = `#parseByteStack("${caseRecord.calldata}")`;
  const gasFact = `1000000 >=Int maxInt(G0(CANCUN, ${data}, 0, lengthBytes(${data}), 0) +Int 21000, 0)`;
  return `requires "../../../trust-runtime-verification.k"
// GENERATED ABI-04 theorem-grade exact-runtime claim. DO NOT EDIT.
// Case: ${caseRecord.caseId}
// Malformed class: ${caseRecord.malformedClass}
// Endpoint: ${endpoint.signature}
module ${caseRecord.module}
    imports TRUST-RUNTIME-VERIFICATION

    claim
      <kevm>
        <k>
          loadTx(1390849295786071768276380950238675083608645509734)
          => #finalizeBlock
        </k>
        <exit-code> 1 </exit-code>
        <mode> NORMAL </mode>
        <schedule> CANCUN </schedule>
        <useGas> false </useGas>

        <ethereum>
          <evm>
            <output> .Bytes </output>
            <statusCode> .StatusCode => EVMC_REVERT </statusCode>
            <callStack> .List </callStack>
            <interimStates> .List </interimStates>
            <touchedAccounts> .Set </touchedAccounts>

            <callState>
              <program> .Bytes </program>
              <static> false </static>
              ...
            </callState>

            <substate>
              <selfDestruct> .Set </selfDestruct>
              <log> .List </log>
              <refund> 0 </refund>
              <accessedAccounts> .Set </accessedAccounts>
              <accessedStorage> .Map </accessedStorage>
              <createdAccounts> .Set </createdAccounts>
            </substate>

            <gasPrice> 0 </gasPrice>
            <origin>
              .Account
              => 1390849295786071768276380950238675083608645509734
            </origin>

            <blockhashes> .List </blockhashes>
            <previousExcessBlobGas> 0 </previousExcessBlobGas>
            <previousBlobGasUsed> 0 </previousBlobGasUsed>

            <block>
              <previousHash> 0 </previousHash>
              <ommersHash> ${EMPTY_OMMERS_HASH_DECIMAL} </ommersHash>
              <coinbase> 0 </coinbase>
              <stateRoot> 0 </stateRoot>
              <transactionsRoot> 0 </transactionsRoot>
              <receiptsRoot> 0 </receiptsRoot>
              <logsBloom> #parseByteStack("${ZERO_BLOOM_HEX}") </logsBloom>
              <difficulty> 0 </difficulty>
              <number> 1 </number>
              <gasLimit> 30000000 </gasLimit>
              <gasUsed> 0:Gas </gasUsed>
              <timestamp> 1 </timestamp>
              <extraData> .Bytes </extraData>
              <mixHash> 0 </mixHash>
              <blockNonce> 0 </blockNonce>
              <baseFee> 0 </baseFee>
              <withdrawalsRoot> 0 </withdrawalsRoot>
              <blobGasUsed> 0 </blobGasUsed>
              <excessBlobGas> 0 </excessBlobGas>
              <beaconRoot> 0 </beaconRoot>
              <requestsRoot> 0 </requestsRoot>
              <ommerBlockHeaders> [ .JSONs ] </ommerBlockHeaders>
            </block>
            ...
          </evm>

          <network>
            <chainID> 31337 </chainID>
            // Whole-cell rewrite fixes the three keyed accounts on both sides.
            <accounts>
              (
${accountState(endpoint, 0)}
              =>
${accountState(endpoint, 1)}
              )
            </accounts>

            <txOrder> .List </txOrder>
            <txPending> ListItem(0) => .List </txPending>
            <messages>
              <message>
                <msgID> 0 </msgID>
                <txNonce> 0 </txNonce>
                <txGasPrice> 0 </txGasPrice>
                <txGasLimit> 1000000 </txGasLimit>
                <to> ${endpoint.address} </to>
                <value> 0 </value>
                <sigV> 0 </sigV>
                <sigR> .Bytes </sigR>
                <sigS> .Bytes </sigS>
                <data> ${data} </data>
                <txAccess> [ .JSONs ] </txAccess>
                <txChainID> 31337 </txChainID>
                <txPriorityFee> 0 </txPriorityFee>
                <txMaxFee> 0 </txMaxFee>
                <txType> Legacy </txType>
                <txMaxBlobFee> 0 </txMaxBlobFee>
                <txVersionedHashes> .List </txVersionedHashes>
                <txAuthList> .List </txAuthList>
              </message>
            </messages>
            <withdrawalsPending> .List </withdrawalsPending>
            <withdrawalsOrder> .List </withdrawalsOrder>
            <withdrawals> .Bag </withdrawals>
            <requests>
              <depositRequests> .Bytes </depositRequests>
              <withdrawalRequests> .Bytes </withdrawalRequests>
              <consolidationRequests> .Bytes </consolidationRequests>
            </requests>
            ...
          </network>
        </ethereum>
      </kevm>
    requires ${gasFact}
      andBool notBool ${endpoint.guardSlot} in_keys(ENDPOINT_STORAGE)
endmodule
`;
}

function readRuntime(runtimePath) {
  const text = fs.readFileSync(runtimePath, "utf8").trim();
  if (!/^0x[0-9a-f]+$/.test(text) || text.length % 2 !== 0) {
    throw new Error(`invalid runtime hex: ${runtimePath}`);
  }
  return Buffer.from(text.slice(2), "hex");
}

function instructionScan(bytes) {
  const boundaries = new Set();
  const jumpDestinations = new Set();
  let pc = 0;
  let finalInstructionStart = 0;
  let nextInstructionOffset = 0;
  while (pc < bytes.length) {
    finalInstructionStart = pc;
    boundaries.add(pc);
    const opcode = bytes[pc];
    if (opcode === 0x5b) jumpDestinations.add(pc);
    const pushWidth = opcode >= 0x60 && opcode <= 0x7f ? opcode - 0x5f : 0;
    pc += 1 + pushWidth;
    nextInstructionOffset = pc;
  }
  return { boundaries, jumpDestinations, finalInstructionStart, nextInstructionOffset };
}

function patchDispatcher(runtimePath, selectors) {
  const original = readRuntime(runtimePath);
  const mutated = Buffer.from(original);
  const stub = Buffer.from("5b60006000f3", "hex");
  const originalScan = instructionScan(original);
  const alignmentPaddingBytes = Math.max(0, originalScan.nextInstructionOffset - original.length);
  const alignmentPadding = Buffer.alloc(alignmentPaddingBytes, 0);
  const stubOffset = original.length + alignmentPaddingBytes;
  if (stubOffset > 0xffff) throw new Error(`PUSH2 cannot address appended stub: ${runtimePath}`);
  const patches = [];
  for (const selector of selectors) {
    const needle = Buffer.from(`63${selector}1461`, "hex");
    const first = original.indexOf(needle);
    if (first < 0 || original.indexOf(needle, first + 1) >= 0) {
      throw new Error(`expected exactly one PUSH4/EQ/PUSH2 dispatcher pattern for ${selector}`);
    }
    const destinationOffset = first + needle.length;
    if (original[destinationOffset + 2] !== 0x57) {
      throw new Error(`dispatcher pattern for ${selector} is not followed by JUMPI`);
    }
    const originalDestination = original.readUInt16BE(destinationOffset);
    mutated.writeUInt16BE(stubOffset, destinationOffset);
    patches.push({ selector: `0x${selector}`, dispatcherOffset: first, destinationOffset, originalDestination, mutatedDestination: stubOffset });
  }
  const bytes = Buffer.concat([mutated, alignmentPadding, stub]);
  const mutatedScan = instructionScan(bytes);
  if (!mutatedScan.boundaries.has(stubOffset) || !mutatedScan.jumpDestinations.has(stubOffset)) {
    throw new Error(`aligned stub is not a valid JUMPDEST at ${stubOffset}: ${runtimePath}`);
  }
  return {
    canonicalSha256: sha256(original),
    canonicalLength: original.length,
    mutatedSha256: sha256(bytes),
    mutatedLength: bytes.length,
    alignmentPaddingBytes,
    alignmentPaddingHex: `0x${alignmentPadding.toString("hex")}`,
    canonicalTailInstructionStart: originalScan.finalInstructionStart,
    canonicalNextInstructionOffset: originalScan.nextInstructionOffset,
    appendedSuccessStubHex: `0x${stub.toString("hex")}`,
    appendedSuccessStubOffset: stubOffset,
    appendedSuccessStubIsValidJumpDestination: true,
    patches,
    bytes,
  };
}

for (const directory of ["claims", "bridge", "generated", "mutation", "isabelle"]) {
  fs.mkdirSync(path.join(rowDir, directory), { recursive: true });
}

const cases = [];
for (const endpoint of endpoints) {
  for (const recipe of recipesFor(endpoint)) {
    const caseId = `ABI04-${endpoint.id}-${recipe.name}`;
    const module = caseId.replaceAll("-", "_").toUpperCase() + "_SPEC";
    const calldata = calldataFor(endpoint, recipe);
    const record = {
      caseId,
      endpointId: endpoint.id,
      malformedClass: recipe.malformedClass,
      subtype: recipe.name,
      fieldIndex: recipe.fieldIndex ?? null,
      fieldType: recipe.fieldType ?? null,
      fieldValueHex: recipe.value === undefined ? null : `0x${BigInt(recipe.value).toString(16)}`,
      encodingContract: recipe.encodingContract ?? null,
      overlap: recipe.overlap ?? null,
      calldata,
      calldataBytes: (calldata.length - 2) / 2,
      calldataSha256: sha256(Buffer.from(calldata.slice(2), "hex")),
      module,
      expected: { status: "EVMC_REVERT", outputHex: "0x", committedLogs: 0, storageStutter: true },
    };
    if (record.encodingContract !== null) {
      const encodedValue = BigInt(recipe.value);
      const lowByte = Number(encodedValue & 0xffn);
      assert.ok((encodedValue >> 8n) > 0n, `${caseId}: enum correction must retain dirty high bits`);
      assert.equal(lowByte, record.encodingContract.lowByteValue, `${caseId}: enum correction low byte`);
      assert.ok(lowByte >= record.encodingContract.lowByteEnumCardinality, `${caseId}: enum low byte must be out of range`);
      assert.equal(record.calldataBytes, 4 + endpoint.tupleWords * 32, `${caseId}: enum correction canonical length`);
    }
    const claimPath = path.join(rowDir, "claims", `${caseId.toLowerCase()}.k`);
    const source = claimSource(record, endpoint);
    assert.equal(source.split("<previousHash> 0 </previousHash>").length - 1, 1, `${caseId}: full Cancun block frame`);
    assert.equal(source.split("// Whole-cell rewrite fixes the three keyed accounts on both sides.").length - 1, 1, `${caseId}: whole accounts rewrite`);
    assert.equal(source.includes("<nonce> 0 => 1 </nonce>"), false, `${caseId}: no partial keyed-account rewrite`);
    assert.equal(source.split("1000000 >=Int maxInt(G0(CANCUN,").length - 1, 1, `${caseId}: exact intrinsic gas premise`);
    assert.equal(source.split(`<data> #parseByteStack("${record.calldata}") </data>`).length - 1, 1, `${caseId}: exact calldata literal`);
    assert.equal(source.split("<statusCode> .StatusCode => EVMC_REVERT </statusCode>").length - 1, 1, `${caseId}: unchanged revert target`);
    assert.equal(source.split("<output> .Bytes </output>").length - 1, 1, `${caseId}: unchanged empty output target`);
    emit(claimPath, source);
    record.claim = { path: posix(claimPath), sha256: sha256(source) };
    cases.push(record);
  }
}

const stableCaseProjection = (item) => ({
  caseId: item.caseId,
  endpointId: item.endpointId,
  malformedClass: item.malformedClass,
  subtype: item.subtype,
  fieldIndex: item.fieldIndex,
  fieldType: item.fieldType,
  fieldValueHex: item.fieldValueHex,
  encodingContract: item.encodingContract ?? null,
  overlap: item.overlap,
  calldata: item.calldata,
  calldataBytes: item.calldataBytes,
  calldataSha256: item.calldataSha256,
  module: item.module,
  expected: item.expected,
});

const priorMatrixPath = path.join(rowDir, "case-matrix.json");
if (fs.existsSync(priorMatrixPath)) {
  const priorMatrix = JSON.parse(fs.readFileSync(priorMatrixPath, "utf8"));
  const currentProjection = cases.map(stableCaseProjection);
  const priorProjection = priorMatrix.cases.map(stableCaseProjection);
  if (JSON.stringify(currentProjection) !== JSON.stringify(priorProjection)) {
    const currentById = new Map(currentProjection.map((item) => [item.caseId, item]));
    const priorById = new Map(priorProjection.map((item) => [item.caseId, item]));
    const changedCaseIds = [...new Set([...currentById.keys(), ...priorById.keys()])]
      .filter((caseId) => JSON.stringify(currentById.get(caseId)) !== JSON.stringify(priorById.get(caseId)))
      .sort();
    const expectedChangedCaseIds = endpoints.map((endpoint) => `ABI04-${endpoint.id}-enum-out-of-range`).sort();
    assert.deepEqual(changedCaseIds, expectedChangedCaseIds, "ABI-04 semantic projection changed outside the reviewed enum correction exact set");
    const withoutCorrection = ({ fieldValueHex, calldata, calldataSha256, encodingContract, ...rest }) => rest;
    for (const caseId of expectedChangedCaseIds) {
      const endpointId = caseId.slice("ABI04-".length, -"-enum-out-of-range".length);
      const endpoint = endpoints.find((item) => item.id === endpointId);
      const current = currentById.get(caseId);
      const prior = priorById.get(caseId);
      assert.ok(endpoint && current && prior, `${caseId}: missing reviewed enum correction projection`);
      const cardinality = endpoint.shape === "action" ? 6 : 3;
      const legacyValue = BigInt(cardinality);
      const correctedValue = enumNoncanonicalWord(cardinality);
      assert.equal(prior.fieldValueHex, `0x${legacyValue.toString(16)}`, `${caseId}: unexpected legacy enum value`);
      assert.equal(current.fieldValueHex, `0x${correctedValue.toString(16)}`, `${caseId}: unexpected corrected enum value`);
      assert.equal(prior.encodingContract, null, `${caseId}: unexpected legacy enum encoding contract`);
      assert.deepEqual(current.encodingContract, enumEncodingContract(cardinality), `${caseId}: corrected enum encoding contract`);
      assert.equal(prior.calldata, calldataFor(endpoint, { kind: "field", fieldIndex: current.fieldIndex, value: legacyValue }), `${caseId}: legacy calldata mismatch`);
      assert.equal(current.calldata, calldataFor(endpoint, { kind: "field", fieldIndex: current.fieldIndex, value: correctedValue }), `${caseId}: corrected calldata mismatch`);
      assert.deepEqual(withoutCorrection(current), withoutCorrection(prior), `${caseId}: unreviewed semantic projection change`);
    }
  }
}

const runtimeGroups = [
  {
    id: "TrustToken",
    macro: "#trustTrustTokenRuntime",
    runtimePath: nativeRuntimePath,
    selectors: [...new Set(endpoints.filter((x) => x.runtimeId === "TrustToken").map((x) => x.selector))],
  },
  {
    id: "ERC3643TrustAdapter",
    macro: "#trustERC3643TrustAdapterRuntime",
    runtimePath: profileRuntimePath,
    selectors: [...new Set(endpoints.filter((x) => x.runtimeId === "ERC3643TrustAdapter").map((x) => x.selector))],
  },
];
const mutations = runtimeGroups.map((group) => ({ ...group, ...patchDispatcher(group.runtimePath, group.selectors) }));

const matrixRoot = sha256(Buffer.from(JSON.stringify(cases.map((item) => ({
  caseId: item.caseId,
  endpointId: item.endpointId,
  malformedClass: item.malformedClass,
  calldataSha256: item.calldataSha256,
  claimSha256: item.claim.sha256,
})))));

const matrix = {
  schemaVersion: 1,
  obligationId: "ABI-04",
  requiredProperty: "short_head_offset_length_and_high_bits_revert_and_stutter",
  classification: "STATIC_DECOMPOSED_CLAIM_PLAN_NOT_DISCHARGE_EVIDENCE",
  semanticCorrections: [
    {
      correctionId: "ABI04-ENUM-NONCANONICAL-WORD-V1",
      status: "REVIEWED_FAIL_CLOSED_INPUT_CORRECTION",
      rationale: "A bare enum cardinality is canonical uint8 ABI and can reach unrelated application guards. Each enum-out-of-range leaf now retains that out-of-range low byte and adds a dirty high bit so the exact field word is ABI-noncanonical without changing tuple length.",
      affectedCaseIds: endpoints.map((endpoint) => `ABI04-${endpoint.id}-enum-out-of-range`).sort(),
      priorValues: { action: "0x6", reversal: "0x3" },
      correctedValues: { action: "0x106", reversal: "0x103" },
      priorReplayCredit: false,
      outputPropertyWeakened: false,
      caseCountChanged: false,
    },
  ],
  caseMatrixRootSha256: matrixRoot,
  coverageRule: "No endpoint or narrow field position inherits coverage from another case. Each listed case requires its own fresh positive replay against the exact pinned runtime.",
  staticTupleBoundary: {
    statement: "ActionRequest and ReversalRequest are entirely static tuples. They contain no canonical ABI offset or length fields.",
    offsetLengthInterpretation: "Offset and length cases are noncanonical dynamic-envelope impostors. Because they append words, they overlap ABI-03's trailing-calldata domain and must not be advertised as distinct canonical fields.",
  },
  endpoints: endpoints.map((item) => ({
    id: item.id,
    contract: item.contract,
    source: item.source,
    compilerOutput: posix(item.compilerOutputPath),
    signature: item.signature,
    selector: `0x${item.selector}`,
    shape: item.shape,
    tupleWords: item.tupleWords,
    canonicalCalldataBytes: 4 + item.tupleWords * 32,
    addressDecimal: item.address,
    runtimeMacro: item.runtimeMacro,
    guardSlot: item.guardSlot,
    resolvedRuntime: {
      path: posix(item.runtimePath),
      artifactSha256: fileSha256(item.runtimePath),
      runtimeBytesSha256: sha256(readRuntime(item.runtimePath)),
      runtimeBytes: readRuntime(item.runtimePath).length,
    },
  })),
  cases,
  counts: {
    endpoints: endpoints.length,
    cases: cases.length,
    shortHead: cases.filter((x) => x.malformedClass === "short_head").length,
    offset: cases.filter((x) => x.malformedClass === "offset").length,
    length: cases.filter((x) => x.malformedClass === "length").length,
    highBitsAndInvalidEnum: cases.filter((x) => x.malformedClass === "high_bits").length,
  },
  historicalEvidence: {
    caseId: "ABI04-native-regulatory-action-selector-only",
    priorClaimId: "9e0afaeb3f0e9dae08a924e5843f204f97106e045ddcf0f4efb39a5b5d478ee1",
    status: "BOUNDED_PASS_REQUIRES_FRESH_ROW_REPLAY",
  },
  unresolvedProofRisk: [
    "The concrete short-head cases are endpoint sentinels, not a universal theorem over every byte length below the canonical size.",
    "The common row-bundle schema currently binds one proofSpec and one graph; this 69-claim matrix needs a coordinator-approved matrix extension or a backend-complete finite/universal aggregation claim.",
    "No KEVM or Isabelle process was run while the coordinator held both heavy-proof slots and the serialized Isabelle slot.",
  ],
};
const matrixPath = path.join(rowDir, "case-matrix.json");
emit(matrixPath, JSON.stringify(matrix, null, 2) + "\n");

const mutationManifest = {
  schemaVersion: 1,
  obligationId: "ABI-04",
  mutationId: "ABI04-DISPATCH-MALFORMED-SELECTORS-TO-SUCCESS-STUB",
  mutationKind: "EXECUTABLE_SEMANTIC_BYTECODE_MUTANT",
  description: "Only the six covered typed endpoint selectors are retargeted from their generated ABI decoders to an appended empty-success EVM stub. Non-target dispatcher entries remain byte-identical.",
  unchangedClaimRequirement: "The positive K claim sources are replayed unchanged against a definition whose TRUST-RUNTIME-BRIDGE macros contain these patched runtimes.",
  runtimes: mutations.map(({ bytes, runtimePath, macro, selectors, ...item }) => ({
    ...item,
    runtimePath: posix(runtimePath),
    macro,
    selectors: selectors.map((x) => `0x${x}`),
  })),
};
const mutationManifestPath = path.join(rowDir, "mutation", "mutation-manifest.json");
emit(mutationManifestPath, JSON.stringify(mutationManifest, null, 2) + "\n");

const mutantBridgePath = path.join(rowDir, "generated", "mutant-runtime-bridge.k");
const mutantBridge = `// GENERATED ABI-04 executable semantic mutant. DO NOT EDIT.
requires "edsl.md"

module TRUST-RUNTIME-BRIDGE
    imports EDSL

    syntax Bytes ::= "#trustTrustTokenRuntime" "(" ")" [macro]
    rule #trustTrustTokenRuntime() => #parseByteStack("0x${mutations.find((x) => x.id === "TrustToken").bytes.toString("hex")}")

    syntax Bytes ::= "#trustERC3643TrustAdapterRuntime" "(" ")" [macro]
    rule #trustERC3643TrustAdapterRuntime() => #parseByteStack("0x${mutations.find((x) => x.id === "ERC3643TrustAdapter").bytes.toString("hex")}")
endmodule
`;
emit(mutantBridgePath, mutantBridge);
const mutantVerificationPath = path.join(rowDir, "generated", "mutant-runtime-verification.k");
emit(mutantVerificationPath, `requires "mutant-runtime-bridge.k"\nrequires "driver.md"\n\nmodule TRUST-RUNTIME-VERIFICATION\n    imports TRUST-RUNTIME-BRIDGE\n    imports ETHEREUM-SIMULATION\nendmodule\n`);

const rowKBridgePath = path.join(rowDir, "generated", "abi-04-row-bridge.k");
const rowKBridge = `// GENERATED ABI-04 row-local metadata bridge. DO NOT EDIT.
requires "edsl.md"

module TRUST-ABI-04-ROW-BRIDGE
    imports EDSL
    syntax String ::= "#trustAbi04CaseMatrixRootSha256" [macro]
    rule #trustAbi04CaseMatrixRootSha256 => "${matrixRoot}"
    syntax Int ::= "#trustAbi04EndpointCount" [macro]
    rule #trustAbi04EndpointCount => ${endpoints.length}
    syntax Int ::= "#trustAbi04CaseCount" [macro]
    rule #trustAbi04CaseCount => ${cases.length}
${[...new Map(endpoints.map((item) => [item.id, item])).values()].map((item) => `    // ${item.signature}\n    syntax Int ::= "#trustAbi04${item.id.split("-").map((part) => part[0].toUpperCase() + part.slice(1)).join("")}Selector" [macro]\n    rule #trustAbi04${item.id.split("-").map((part) => part[0].toUpperCase() + part.slice(1)).join("")}Selector => ${Number.parseInt(item.selector, 16)}`).join("\n")}
endmodule
`;
emit(rowKBridgePath, rowKBridge);

const generatedTheoryPath = path.join(rowDir, "isabelle", "ABI_04_Generated.thy");
const generatedTheory = `theory ABI_04_Generated
  imports ERC_TRUST.TRUST_Runtime_Bridge_Generated
begin

definition abi_04_case_matrix_root_sha256 :: string where
  "abi_04_case_matrix_root_sha256 = ''${matrixRoot}''"
definition abi_04_endpoint_count :: nat where "abi_04_endpoint_count = ${endpoints.length}"
definition abi_04_case_count :: nat where "abi_04_case_count = ${cases.length}"
definition abi_04_short_head_case_count :: nat where "abi_04_short_head_case_count = ${matrix.counts.shortHead}"
definition abi_04_offset_impostor_case_count :: nat where "abi_04_offset_impostor_case_count = ${matrix.counts.offset}"
definition abi_04_length_impostor_case_count :: nat where "abi_04_length_impostor_case_count = ${matrix.counts.length}"
definition abi_04_high_bits_and_invalid_enum_case_count :: nat where "abi_04_high_bits_and_invalid_enum_case_count = ${matrix.counts.highBitsAndInvalidEnum}"
definition abi_04_native_runtime_sha256 :: string where
  "abi_04_native_runtime_sha256 = ''${mutations.find((x) => x.id === "TrustToken").canonicalSha256}''"
definition abi_04_native_mutant_sha256 :: string where
  "abi_04_native_mutant_sha256 = ''${mutations.find((x) => x.id === "TrustToken").mutatedSha256}''"
definition abi_04_profile_runtime_sha256 :: string where
  "abi_04_profile_runtime_sha256 = ''${mutations.find((x) => x.id === "ERC3643TrustAdapter").canonicalSha256}''"
definition abi_04_profile_mutant_sha256 :: string where
  "abi_04_profile_mutant_sha256 = ''${mutations.find((x) => x.id === "ERC3643TrustAdapter").mutatedSha256}''"
definition abi_04_expected_revert :: bool where "abi_04_expected_revert = True"
definition abi_04_expected_storage_stutter :: bool where "abi_04_expected_storage_stutter = True"

end
`;
emit(generatedTheoryPath, generatedTheory);

const bridge = {
  schemaVersion: 1,
  obligationId: "ABI-04",
  classification: "ROW_LOCAL_GENERATED_REVERSE_CHECK_REQUIRED",
  generator: {
    path: posix(fileURLToPath(import.meta.url)),
    sha256: fileSha256(fileURLToPath(import.meta.url)),
  },
  reverseCheck: {
    path: "formal/kevm/row-bundles/abi-04/reverse-check.mjs",
    sha256: fileSha256(path.join(rowDir, "reverse-check.mjs")),
  },
  caseMatrix: { path: posix(matrixPath), sha256: generatedSha256(matrixPath), rootSha256: matrixRoot },
  compilerOutputs: [nativeOutputPath, profileOutputPath].map((item) => ({ path: posix(item), sha256: fileSha256(item) })),
  resolvedRuntimes: [nativeRuntimePath, profileRuntimePath].map((item) => ({
    path: posix(item),
    artifactSha256: fileSha256(item),
    runtimeBytesSha256: sha256(readRuntime(item)),
    runtimeBytes: readRuntime(item).length,
  })),
  generated: [mutantBridgePath, mutantVerificationPath, rowKBridgePath, generatedTheoryPath].map((item) => ({ path: posix(item), sha256: generatedSha256(item) })),
  mutationManifest: { path: posix(mutationManifestPath), sha256: generatedSha256(mutationManifestPath) },
  claimsRootSha256: sha256(Buffer.from(cases.map((item) => item.claim.sha256).join("\n") + "\n")),
};
const bridgePath = path.join(rowDir, "bridge", "row-bridge.json");
emit(bridgePath, JSON.stringify(bridge, null, 2) + "\n");

const handwrittenTheoryPath = path.join(rowDir, "isabelle", "ABI_04_Short_Head_Offset_Length_And_High_Bits.thy");
const manifest = {
  schemaVersion: 1,
  obligationId: "ABI-04",
  classification: "STATIC_CANDIDATE_NOT_CLOSURE_REPORT",
  bridge: { path: posix(bridgePath), sha256: generatedSha256(bridgePath) },
  caseMatrix: { path: posix(matrixPath), sha256: generatedSha256(matrixPath), rootSha256: matrixRoot },
  reverseCheck: "formal/kevm/row-bundles/abi-04/reverse-check.mjs",
  theorem: {
    path: posix(handwrittenTheoryPath),
    name: "abi_04_short_head_offset_length_and_high_bits_revert_and_stutter",
    session: "ERC_TRUST_ABI_04_CANDIDATE",
    sourceSha256: fs.existsSync(handwrittenTheoryPath) ? fileSha256(handwrittenTheoryPath) : null,
  },
  proofStatus: "NOT_RUN",
};
emit(path.join(rowDir, "bridge", "row-manifest.json"), JSON.stringify(manifest, null, 2) + "\n");

if (checkMode || planMode) {
  for (const [filePath, expected] of [...generatedContent.entries()].sort(([left], [right]) => left.localeCompare(right))) {
    const actual = fs.existsSync(filePath) ? fs.readFileSync(filePath, "utf8").replaceAll("\r\n", "\n") : null;
    generationPlan.push({
      path: posix(filePath),
      status: actual === expected ? "UNCHANGED" : actual === null ? "MISSING" : "CHANGED",
      actualSha256: actual === null ? null : sha256(actual),
      expectedSha256: sha256(expected),
    });
  }
  if (checkMode) {
    const stale = generationPlan.filter(({ status }) => status !== "UNCHANGED").map(({ path: filePath }) => filePath);
    if (stale.length > 0) throw new Error(`stale generated ABI-04 matrix descendants: ${stale.join(", ")}`);
  }
}

console.log(JSON.stringify({
  status: checkMode ? "PASS_GENERATED_CHECK" : planMode ? "PASS_GENERATION_PLAN" : "GENERATED_STATIC_CANDIDATE",
  mode: checkMode ? "check" : planMode ? "plan" : "write",
  generatedFiles: generatedContent.size,
  changes: planMode ? {
    changed: generationPlan.filter(({ status }) => status === "CHANGED").length,
    missing: generationPlan.filter(({ status }) => status === "MISSING").length,
    unchanged: generationPlan.filter(({ status }) => status === "UNCHANGED").length,
    files: generationPlan,
  } : undefined,
  caseMatrix: posix(matrixPath),
  caseMatrixRootSha256: matrixRoot,
  endpoints: endpoints.length,
  cases: cases.length,
  counts: matrix.counts,
  nativeRuntimeSha256: mutations.find((x) => x.id === "TrustToken").canonicalSha256,
  nativeMutantSha256: mutations.find((x) => x.id === "TrustToken").mutatedSha256,
  profileRuntimeSha256: mutations.find((x) => x.id === "ERC3643TrustAdapter").canonicalSha256,
  profileMutantSha256: mutations.find((x) => x.id === "ERC3643TrustAdapter").mutatedSha256,
}, null, 2));
