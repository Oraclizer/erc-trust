import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const rowRoot = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(rowRoot, "../../../..");
const evidenceRoot = join(repositoryRoot, "evidence", "end-to-end-refinement");
const bindingRoot = join(repositoryRoot, "evidence", "end-to-end-refinement", "runtime-binding");
const obligationIndexPath = join(evidenceRoot, "obligation-evidence-index.json");
const theoremInventoryPath = join(evidenceRoot, "theorem-obligations.md");
const proofLedgerPath = join(evidenceRoot, "proof-run-ledger.json");
const runtimeSchemaPath = join(evidenceRoot, "runtime-bridge", "schema.json");
const lockPath = join(repositoryRoot, "formal", "kevm", "dependencies.lock.json");
const compilerArtifactsPath = join(bindingRoot, "native", "bridge-artifacts.json");
const bindingManifestPath = join(bindingRoot, "manifest.json");
const constructorFixturePath = join(bindingRoot, "resolved", "fixture.json");
const resolvedRuntimePath = join(bindingRoot, "resolved", "native", "TrustToken.hex");
const canonicalBridgePath = join(repositoryRoot, "formal", "kevm", "generated", "trust-runtime-bridge.k");
const interfacePath = join(repositoryRoot, "implementation", "src", "interfaces", "IERCTrust.sol");
const tokenSourcePath = join(repositoryRoot, "implementation", "src", "TrustToken.sol");
const kontrolHarnessPath = join(repositoryRoot, "implementation", "kontrol", "TrustTokenKontrolTest.t.sol");
const kontrolAssertionPath = join(repositoryRoot, "implementation", "kontrol", "erc-trust-log-assertions.k");
const foundryEventTestPath = join(repositoryRoot, "implementation", "test", "TrustActions.unit.t.sol");
const transactionTheoryPath = join(repositoryRoot, "formal", "isabelle", "ERC_TRUST", "TRUST_Transaction_Refinement.thy");
const generatedIsabelleBridgePath = join(repositoryRoot, "formal", "isabelle", "ERC_TRUST", "TRUST_Runtime_Bridge_Generated.thy");
const fixtureTemplatePath = join(rowRoot, "fixture-template.json");
const materializedFixturePath = join(rowRoot, "fixture.json");
const fixtureValidatorPath = join(rowRoot, "validate-fixture.py");
const claimTemplatePath = join(rowRoot, "claim-template.k.in");
const materializedClaimPath = join(rowRoot, "claim.k");
const mutantControlClaimPath = join(rowRoot, "mutant-control-claim.k");
const dependencyGraphPath = join(rowRoot, "dependency-graph.json");
const compositionGraphPath = join(rowRoot, "composition-graph.json");
const skeletonBundlePath = join(rowRoot, "bundle.skeleton.json");
const runnerDescriptorPath = join(rowRoot, "runner-descriptor.skeleton.json");
const parseClaimsPath = join(rowRoot, "parse-claims.py");
const generatedRoot = join(rowRoot, "generated");
const mutantBridgePath = join(generatedRoot, "mutant-runtime-bridge.k");
const mutantVerificationPath = join(generatedRoot, "mutant-runtime-verification.k");
const rowBridgePath = join(rowRoot, "bridge", "row-bridge.json");
const rowManifestPath = join(rowRoot, "bridge", "row-manifest.json");
const theoryPath = join(rowRoot, "isabelle", "SEP_04_Receipt_Event_Binding.thy");
const sharedRunnerRoot = join(repositoryRoot, "formal", "kevm", "row-bundles");

const OBLIGATION_ID = "SEP-04";
const REQUIRED_PROPERTY = "`receipt_preimage_matches_storage_return_and_final_event`";
const THEOREM_NAME = "receipt_preimage_matches_storage_return_and_final_event";
const POSITIVE_MODULE = "TRUST-SEP-04-RECEIPT-PREIMAGE-STORAGE-RETURN-FINAL-EVENT-SPEC";
const CONTROL_MODULE = "TRUST-SEP-04-MUTANT-EVENT-TOPIC-CONTROL-SPEC";
const PLACEHOLDER_SHA256 = "e4fcabd40c8b18e3900050a590b6b80c687d4d115f61bc12439af6099e83434e";
const EVENT_SIGNATURE = "RegulatoryActionApplied(bytes32,uint8,bytes32,bytes32)";
const EXPECTED_TOPIC0 = "aadd5db99c0c1f57ce6f82b109958a00899fc4cea03e70fdae7741b9e7050091";
const MASK_64 = (1n << 64n) - 1n;
const ROUND_CONSTANTS = [
  0x0000000000000001n, 0x0000000000008082n, 0x800000000000808an,
  0x8000000080008000n, 0x000000000000808bn, 0x0000000080000001n,
  0x8000000080008081n, 0x8000000000008009n, 0x000000000000008an,
  0x0000000000000088n, 0x0000000080008009n, 0x000000008000000an,
  0x000000008000808bn, 0x800000000000008bn, 0x8000000000008089n,
  0x8000000000008003n, 0x8000000000008002n, 0x8000000000000080n,
  0x000000000000800an, 0x800000008000000an, 0x8000000080008081n,
  0x8000000000008080n, 0x0000000080000001n, 0x8000000080008008n,
];
const ROTATION = [
  0, 1, 62, 28, 27,
  36, 44, 6, 55, 20,
  3, 10, 43, 25, 39,
  41, 45, 15, 21, 8,
  18, 2, 61, 56, 14,
];

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function repoPath(path) {
  return relative(repositoryRoot, path).split(sep).join("/");
}

function ref(path) {
  return { path: repoPath(path), sha256: sha256(readFileSync(path)) };
}

function sourceBlock(bytes, startToken, endToken) {
  const text = bytes.toString("utf8");
  const start = text.indexOf(startToken);
  const end = text.indexOf(endToken, start + startToken.length);
  if (start < 0 || end < 0) throw new Error(`source block drift: ${startToken}`);
  return Buffer.from(text.slice(start, end), "utf8");
}

function assertSafeJsonNumbers(value, path = "$") {
  if (typeof value === "number") {
    if (!Number.isSafeInteger(value)) throw new Error(`unsafe JSON number at ${path}`);
    return;
  }
  if (Array.isArray(value)) {
    value.forEach((entry, index) => assertSafeJsonNumbers(entry, `${path}[${index}]`));
    return;
  }
  if (value !== null && typeof value === "object") {
    for (const [key, entry] of Object.entries(value)) assertSafeJsonNumbers(entry, `${path}.${key}`);
  }
}

function write(path, text) {
  mkdirSync(dirname(path), { recursive: true });
  const normalized = text.replaceAll("\r\n", "\n").replaceAll("\r", "\n");
  // The static generator is deterministic.  Avoid reopening a byte-identical
  // generated artifact, because an active read-only verifier may hold it open.
  if (existsSync(path) && readFileSync(path, "utf8") === normalized) return;
  writeFileSync(path, normalized, "utf8");
}

function stable(value) {
  if (Array.isArray(value)) return value.map(stable);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stable(value[key])]));
  }
  return value;
}

function json(value) {
  return `${JSON.stringify(stable(value), null, 2)}\n`;
}

function normalizeHex(text) {
  const value = text.trim().toLowerCase();
  if (!/^0x[0-9a-f]*$/.test(value) || value.length % 2 !== 0) throw new Error("invalid even-length hex");
  return value;
}

function rotateLeft64(value, shift) {
  if (shift === 0) return value & MASK_64;
  const amount = BigInt(shift);
  return ((value << amount) | (value >> (64n - amount))) & MASK_64;
}

function keccakPermutation(state) {
  for (const roundConstant of ROUND_CONSTANTS) {
    const c = Array(5).fill(0n);
    const d = Array(5).fill(0n);
    for (let x = 0; x < 5; x += 1) {
      c[x] = state[x] ^ state[x + 5] ^ state[x + 10] ^ state[x + 15] ^ state[x + 20];
    }
    for (let x = 0; x < 5; x += 1) d[x] = c[(x + 4) % 5] ^ rotateLeft64(c[(x + 1) % 5], 1);
    for (let x = 0; x < 5; x += 1) {
      for (let y = 0; y < 5; y += 1) state[x + 5 * y] = (state[x + 5 * y] ^ d[x]) & MASK_64;
    }
    const b = Array(25).fill(0n);
    for (let x = 0; x < 5; x += 1) {
      for (let y = 0; y < 5; y += 1) {
        b[y + 5 * ((2 * x + 3 * y) % 5)] = rotateLeft64(state[x + 5 * y], ROTATION[x + 5 * y]);
      }
    }
    for (let x = 0; x < 5; x += 1) {
      for (let y = 0; y < 5; y += 1) {
        state[x + 5 * y] = (b[x + 5 * y] ^ ((~b[(x + 1) % 5 + 5 * y]) & b[(x + 2) % 5 + 5 * y])) & MASK_64;
      }
    }
    state[0] ^= roundConstant;
  }
}

function keccak256Utf8(text) {
  const rate = 136;
  const input = Buffer.from(text, "utf8");
  const paddedLength = Math.ceil((input.length + 1) / rate) * rate;
  const padded = Buffer.alloc(paddedLength);
  input.copy(padded);
  padded[input.length] = 0x01;
  padded[padded.length - 1] |= 0x80;
  const state = Array(25).fill(0n);
  for (let offset = 0; offset < padded.length; offset += rate) {
    for (let lane = 0; lane < rate / 8; lane += 1) {
      let word = 0n;
      for (let byte = 0; byte < 8; byte += 1) word |= BigInt(padded[offset + lane * 8 + byte]) << BigInt(8 * byte);
      state[lane] ^= word;
    }
    keccakPermutation(state);
  }
  const output = Buffer.alloc(32);
  for (let index = 0; index < output.length; index += 1) {
    output[index] = Number((state[Math.floor(index / 8)] >> BigInt(8 * (index % 8))) & 0xffn);
  }
  return output.toString("hex");
}

const obligationIndexBytes = readFileSync(obligationIndexPath);
const theoremInventoryBytes = readFileSync(theoremInventoryPath);
const proofLedgerBytes = readFileSync(proofLedgerPath);
const runtimeSchemaBytes = readFileSync(runtimeSchemaPath);
const lockBytes = readFileSync(lockPath);
const generatedIsabelleBridgeBytes = readFileSync(generatedIsabelleBridgePath);
const compilerArtifactsBytes = readFileSync(compilerArtifactsPath);
const bindingManifestBytes = readFileSync(bindingManifestPath);
const constructorFixtureBytes = readFileSync(constructorFixturePath);
const materializedFixtureBytes = readFileSync(materializedFixturePath);
const canonicalBridgeBytes = readFileSync(canonicalBridgePath);
const resolvedRuntimeBytes = readFileSync(resolvedRuntimePath);
const interfaceBytes = readFileSync(interfacePath);
const tokenSourceBytes = readFileSync(tokenSourcePath);
const kontrolHarnessBytes = readFileSync(kontrolHarnessPath);
const kontrolAssertionBytes = readFileSync(kontrolAssertionPath);
const foundryEventTestBytes = readFileSync(foundryEventTestPath);
const transactionTheoryBytes = readFileSync(transactionTheoryPath);
const obligationIndex = JSON.parse(obligationIndexBytes);
const obligation = obligationIndex.obligations.find((entry) => entry.obligationId === OBLIGATION_ID);
if (!obligation || obligation.requiredProperty !== REQUIRED_PROPERTY || obligation.statement?.name !== THEOREM_NAME) {
  throw new Error("SEP-04 canonical requiredProperty drift");
}
if (obligation.status?.classification !== "OPEN" || obligation.status?.discharged !== false) {
  throw new Error("SEP-04 canonical status drift");
}
if (!theoremInventoryBytes.toString("utf8").includes("| SEP-04 | `receipt_preimage_matches_storage_return_and_final_event` |")) {
  throw new Error("SEP-04 theorem inventory drift");
}
const canonicalPlaceholder = obligation.tcb.find((entry) => entry.tcbId === "TCB-LOCK")?.exactIdentityRef;
if (!canonicalPlaceholder || canonicalPlaceholder.sha256 !== PLACEHOLDER_SHA256) {
  throw new Error("SEP-04 canonical OPEN lock placeholder drift");
}
const currentLockSha256 = sha256(lockBytes);
const proofLedger = JSON.parse(proofLedgerBytes);
for (const runId of ["RUN-BRIDGE-GENERATE-VERIFY-001", "RUN-ISABELLE-CLOSURE-001"]) {
  const run = proofLedger.runs.find((entry) => entry.runId === runId);
  if (!run || run.status !== "PASS" || !run.targetObligationIds.includes(OBLIGATION_ID)) {
    throw new Error(`missing SEP-04 provenance PASS: ${runId}`);
  }
}
const compilerArtifacts = JSON.parse(compilerArtifactsBytes);
const bindingManifest = JSON.parse(bindingManifestBytes);
const constructorFixture = JSON.parse(constructorFixtureBytes);
const materializedFixture = JSON.parse(materializedFixtureBytes);
assertSafeJsonNumbers(materializedFixture);
const artifact = compilerArtifacts.find((entry) => entry.contract === "TrustToken");
const deployment = constructorFixture.deployments.find((entry) => entry.label === "TrustToken");
if (!artifact || !deployment) throw new Error("TrustToken compiler artifact or resolved deployment missing");
if (bindingManifest.sourceIdentity?.dependencyLockSha256 !== currentLockSha256) {
  throw new Error("runtime-binding dependency lock drift");
}
const runtimeSchemaSha256 = sha256(runtimeSchemaBytes);
const generatedIsabelleBridge = generatedIsabelleBridgeBytes.toString("utf8");
if (!generatedIsabelleBridge.includes(`runtime_bridge_schema_sha256 = ''${runtimeSchemaSha256}''`)) {
  throw new Error("generated Isabelle runtime schema drift");
}

const eventAbi = artifact.abi.find((entry) => entry.type === "event" && entry.name === "RegulatoryActionApplied");
const expectedInputs = [
  ["bytes32", true, "actionId"],
  ["uint8", true, "action"],
  ["bytes32", true, "caseId"],
  ["bytes32", false, "receiptHash"],
];
if (!eventAbi || eventAbi.anonymous !== false || eventAbi.inputs.length !== expectedInputs.length) {
  throw new Error("canonical RegulatoryActionApplied ABI missing");
}
for (let index = 0; index < expectedInputs.length; index += 1) {
  const [type, indexed, name] = expectedInputs[index];
  const actual = eventAbi.inputs[index];
  if (actual.type !== type || actual.indexed !== indexed || actual.name !== name) {
    throw new Error(`RegulatoryActionApplied ABI drift at input ${index}`);
  }
}
const derivedTopic0 = keccak256Utf8(EVENT_SIGNATURE);
if (derivedTopic0 !== EXPECTED_TOPIC0) throw new Error(`Keccak derivation mismatch: ${derivedTopic0}`);

const interfaceSource = interfaceBytes.toString("utf8");
const tokenSource = tokenSourceBytes.toString("utf8");
const kontrolHarness = kontrolHarnessBytes.toString("utf8");
const kontrolAssertion = kontrolAssertionBytes.toString("utf8");
const foundryEventTest = foundryEventTestBytes.toString("utf8");
const transactionTheory = transactionTheoryBytes.toString("utf8");
if (!interfaceSource.includes("event RegulatoryActionApplied(")) throw new Error("interface event declaration missing");
if (!tokenSource.includes("emit RegulatoryActionApplied(request.actionId, request.action, request.caseId, receiptHash);")) {
  throw new Error("TrustToken canonical receipt event emission drift");
}
if (!kontrolHarness.includes("testKontrol_LiquidateExactDeltaReceiptAndFinalLog")) throw new Error("Kontrol support path missing");
if (!kontrolHarness.includes("record.receiptHash == returned && actionReceipt.receiptHash == returned")) {
  throw new Error("Kontrol storage/return cross-check drift");
}
if (!kontrolAssertion.includes("erc-trust.assert-final-receipt-log")) throw new Error("Kontrol final-log assertion missing");
if (!foundryEventTest.includes("testCanonicalEventOrder")) throw new Error("Foundry event-order support test missing");
if (!transactionTheory.includes("theorem success_has_final_canonical_receipt_event")) {
  throw new Error("transaction receipt-event theorem missing");
}

const resolvedRuntime = normalizeHex(resolvedRuntimeBytes.toString("utf8"));
const runtime = Buffer.from(resolvedRuntime.slice(2), "hex");
if (sha256(runtime) !== deployment.runtime.sha256) throw new Error("resolved runtime hash drift");
const canonicalBridge = canonicalBridgeBytes.toString("utf8");
if (!canonicalBridge.includes(`rule #trustBridgeSchemaSha256 => "${runtimeSchemaSha256}"`)) {
  throw new Error("canonical K runtime schema drift");
}
const macroPrefix = "rule #trustTrustTokenRuntime() => #parseByteStack(\"";
const macroStart = canonicalBridge.indexOf(macroPrefix);
if (macroStart < 0) throw new Error("TrustToken runtime macro missing");
const runtimeStart = macroStart + macroPrefix.length;
const runtimeEnd = canonicalBridge.indexOf("\")", runtimeStart);
if (runtimeEnd < 0) throw new Error("TrustToken runtime macro unterminated");
const macroRuntime = normalizeHex(canonicalBridge.slice(runtimeStart, runtimeEnd));
if (macroRuntime !== resolvedRuntime) throw new Error("K runtime macro differs from resolved runtime");

const runtimeHex = resolvedRuntime.slice(2);
const topicOffset = runtimeHex.indexOf(EXPECTED_TOPIC0);
if (topicOffset < 0 || runtimeHex.indexOf(EXPECTED_TOPIC0, topicOffset + 1) >= 0) {
  throw new Error("canonical RegulatoryActionApplied topic is not unique in resolved runtime");
}
if (topicOffset % 2 !== 0) throw new Error("event topic is not byte-aligned");
if (runtime[topicOffset / 2 - 1] !== 0x7f) throw new Error("canonical event topic is not the immediate operand of PUSH32");
const mutationHexOffset = topicOffset;
const mutantTopic0 = `ab${EXPECTED_TOPIC0.slice(2)}`;
const mutantRuntime = `0x${runtimeHex.slice(0, mutationHexOffset)}${mutantTopic0}${runtimeHex.slice(mutationHexOffset + EXPECTED_TOPIC0.length)}`;
const mutantRuntimeBytes = Buffer.from(mutantRuntime.slice(2), "hex");
if (mutantRuntimeBytes.length !== runtime.length) throw new Error("event-topic mutant changed runtime length");
const differingByteOffsets = [];
for (let index = 0; index < runtime.length; index += 1) {
  if (runtime[index] !== mutantRuntimeBytes[index]) differingByteOffsets.push(index);
}
if (differingByteOffsets.length !== 1 || differingByteOffsets[0] !== topicOffset / 2) {
  throw new Error("event-topic mutant must differ by exactly one byte");
}
if (mutantRuntimeBytes[topicOffset / 2] !== 0xab || runtime[topicOffset / 2] !== 0xaa) {
  throw new Error("event-topic mutation byte mismatch");
}
if (mutantRuntime.slice(2).includes(EXPECTED_TOPIC0)) throw new Error("canonical topic remains in mutant runtime");
if (!mutantRuntime.slice(2).includes(mutantTopic0)) throw new Error("mutant topic absent from mutant runtime");

const mutantBridge = `${canonicalBridge.slice(0, runtimeStart)}${mutantRuntime}${canonicalBridge.slice(runtimeEnd)}`;
write(mutantBridgePath, mutantBridge);
write(mutantVerificationPath,
  `requires "mutant-runtime-bridge.k"\nrequires "driver.md"\n\n` +
  `module TRUST-RUNTIME-VERIFICATION\n    imports TRUST-RUNTIME-BRIDGE\n    imports ETHEREUM-SIMULATION\nendmodule\n`);

const requiredPorts = [...readFileSync(claimTemplatePath, "utf8").matchAll(/@@([A-Z0-9_]+)@@/g)]
  .map((match) => match[1])
  .filter((value, index, values) => values.indexOf(value) === index)
  .sort();

if (materializedFixture.obligationId !== "SEP-04" || materializedFixture.status !== "OPEN"
    || materializedFixture.eligibleForDischarge !== false) {
  throw new Error("materialized fixture must remain the OPEN, ineligible SEP-04 capture");
}
const fixturePorts = materializedFixture.ports;
if (fixturePorts === null || typeof fixturePorts !== "object" || Array.isArray(fixturePorts)) {
  throw new Error("materialized fixture ports missing");
}
const fixturePortNames = Object.keys(fixturePorts).sort();
if (JSON.stringify(fixturePortNames) !== JSON.stringify(requiredPorts)) {
  throw new Error("materialized fixture port list differs from claim template");
}
let materializedClaim = readFileSync(claimTemplatePath, "utf8");
for (const portName of requiredPorts) {
  const value = fixturePorts[portName];
  if (typeof value !== "string" || value.trim() === "" || value.includes("@@")) {
    throw new Error(`fixture port is not a closed K term: ${portName}`);
  }
  materializedClaim = materializedClaim.replaceAll(`@@${portName}@@`, value);
}
if (/@@[A-Z0-9_]+@@/.test(materializedClaim)) throw new Error("unclosed materialized claim port");
write(materializedClaimPath, materializedClaim);
const materializedClaimBytes = readFileSync(materializedClaimPath);

const integerPortNames = [
  "BLOCK_GAS_LIMIT_INT",
  "BLOCK_NUMBER_INT",
  "SENDER_INT",
  "SENDER_NONCE_BEFORE_INT",
  "TIMESTAMP_INT",
  "TOKEN_ADDRESS_INT",
  "TX_GAS_LIMIT_INT",
];
const integerPorts = {};
for (const portName of integerPortNames) {
  const text = fixturePorts[portName];
  if (typeof text !== "string" || !/^(0|[1-9][0-9]*)$/.test(text)) {
    throw new Error(`BigInt boundary port is not canonical decimal text: ${portName}`);
  }
  const parsed = BigInt(text);
  if (parsed.toString() !== text) throw new Error(`BigInt boundary round-trip drift: ${portName}`);
  integerPorts[portName] = text;
}
for (const largePort of ["SENDER_INT", "TOKEN_ADDRESS_INT"]) {
  if (BigInt(integerPorts[largePort]) <= BigInt(Number.MAX_SAFE_INTEGER)) {
    throw new Error(`expected large BigInt boundary port: ${largePort}`);
  }
}
for (const kTermPort of ["PRE_ACCOUNTS_K", "POST_ACCOUNTS_K", "COMPLETE_LOG_LIST_K", "ACCESSED_ACCOUNTS_K", "ACCESSED_STORAGE_K"]) {
  if (typeof fixturePorts[kTermPort] !== "string") throw new Error(`K term port must remain text: ${kTermPort}`);
}

const canonicalTopicDecimal = BigInt(`0x${EXPECTED_TOPIC0}`).toString();
const mutantTopicDecimal = BigInt(`0x${mutantTopic0}`).toString();
if (canonicalTopicDecimal === mutantTopicDecimal ||
    BigInt(canonicalTopicDecimal) <= BigInt(Number.MAX_SAFE_INTEGER) ||
    BigInt(mutantTopicDecimal) <= BigInt(Number.MAX_SAFE_INTEGER)) {
  throw new Error("event topic BigInt boundary drift");
}
if (materializedClaim.split(canonicalTopicDecimal).length !== 2) {
  throw new Error("positive claim must contain the canonical final-event topic decimal exactly once");
}
let mutantControlClaim = materializedClaim
  .replace('requires "../../trust-runtime-verification.k"', 'requires "generated/mutant-runtime-verification.k"')
  .replace(POSITIVE_MODULE, CONTROL_MODULE)
  .replace(canonicalTopicDecimal, mutantTopicDecimal);
if (mutantControlClaim.includes(canonicalTopicDecimal) || !mutantControlClaim.includes(mutantTopicDecimal) ||
    !mutantControlClaim.includes(CONTROL_MODULE) || mutantControlClaim.includes(POSITIVE_MODULE)) {
  throw new Error("mutant executable control materialization drift");
}
write(mutantControlClaimPath, mutantControlClaim);
const mutantControlClaimBytes = readFileSync(mutantControlClaimPath);

const bigIntBoundary = {
  policy: "all authoritative EVM integers and K terms remain canonical decimal/hex strings until explicit BigInt conversion",
  numberMaxSafeInteger: Number.MAX_SAFE_INTEGER.toString(),
  allFixtureJsonNumbersSafe: true,
  integerPorts,
  largeIntegerPorts: ["SENDER_INT", "TOKEN_ADDRESS_INT"],
  canonicalTopicDecimal,
  mutantTopicDecimal,
  topicDecimalsRoundTrip: BigInt(canonicalTopicDecimal).toString() === canonicalTopicDecimal &&
    BigInt(mutantTopicDecimal).toString() === mutantTopicDecimal,
};

const sourceBlocks = {
  regulatoryActionEventDeclarationSha256: sha256(sourceBlock(
    interfaceBytes,
    "event RegulatoryActionApplied(",
    "event RegulatoryReversalApplied(")),
  actionReceiptStorageReturnEventSha256: sha256(sourceBlock(
    tokenSourceBytes,
    "function _applyActionPrepared(",
    "function _applyReversal(")),
  transactionBridgeRecordSha256: sha256(sourceBlock(
    transactionTheoryBytes,
    "record trust_transaction_bridge =",
    "record trust_transaction_abstraction =")),
  canonicalReceiptTraceSha256: sha256(sourceBlock(
    transactionTheoryBytes,
    "definition canonical_receipt_trace ::",
    "definition alpha_transaction ::")),
  finalCanonicalReceiptEventTheoremSha256: sha256(sourceBlock(
    transactionTheoryBytes,
    "theorem success_has_final_canonical_receipt_event:",
    "theorem committed_history_excludes_failure_receipts:")),
};

const dependencyGraphBytes = readFileSync(dependencyGraphPath);
const dependencyGraph = JSON.parse(dependencyGraphBytes);
if (dependencyGraph.selectedObligation?.id !== OBLIGATION_ID ||
    dependencyGraph.selectedObligation?.property !== REQUIRED_PROPERTY ||
    dependencyGraph.selectedObligation?.theoremName !== THEOREM_NAME ||
    dependencyGraph.selectedObligation?.status !== "OPEN") {
  throw new Error("SEP-04 dependency graph selected boundary drift");
}

const observation = materializedFixture.observations;
const storageObservation = materializedFixture.storageObservations;
const receiptHash = observation.receiptHash;
for (const [label, value] of Object.entries({
  returnPayloadHex: observation.returnPayloadHex,
  ethCallReturnPayloadHex: observation.ethCallReturnPayloadHex,
  finalLogDataHex: observation.finalLogDataHex,
  actionRecordReceiptHash: observation.actionRecordReceiptHash,
  receiptRecordReceiptHash: observation.receiptRecordReceiptHash,
  storageActionRecordReceiptHash: storageObservation.actionRecordReceiptHash,
  storageReceiptRecordReceiptHash: storageObservation.receiptRecordReceiptHash,
})) {
  if (value !== receiptHash) throw new Error(`receipt preimage observation drift: ${label}`);
}
if (observation.finalLogTopics?.[0] !== `0x${EXPECTED_TOPIC0}` ||
    observation.completeLogs?.at(-1)?.topics?.[0] !== `0x${EXPECTED_TOPIC0}` ||
    observation.completeLogs?.at(-1)?.data !== receiptHash) {
  throw new Error("canonical final event observation drift");
}

const compositionInputs = {
  schemaVersion: 2,
  obligationId: OBLIGATION_ID,
  requiredProperty: REQUIRED_PROPERTY,
  theoremName: THEOREM_NAME,
  tcb: {
    canonicalPlaceholder,
    actualCurrentLock: ref(lockPath),
    runtimeBindingManifest: ref(bindingManifestPath),
  },
  canonicalSources: {
    obligationIndex: ref(obligationIndexPath),
    theoremInventory: ref(theoremInventoryPath),
    runtimeSchema: ref(runtimeSchemaPath),
    canonicalKBridge: ref(canonicalBridgePath),
    generatedIsabelleBridge: ref(generatedIsabelleBridgePath),
    interface: ref(interfacePath),
    tokenSource: ref(tokenSourcePath),
    transactionTheory: ref(transactionTheoryPath),
    sourceBlocks,
  },
  dependencies: {
    graph: ref(dependencyGraphPath),
    evidenceInherited: false,
    dischargeInherited: false,
  },
  runtime: {
    resolvedRuntime: ref(resolvedRuntimePath),
    byteSha256: sha256(runtime),
    byteLength: runtime.length,
    fixture: ref(constructorFixturePath),
  },
  exactTransactionFixture: {
    fixture: ref(materializedFixturePath),
    action: "LIQUIDATE",
    boundary: "loadTx -> #call -> #finishTx -> #finalizeTx",
    receiptHash,
    storageReceiptHashes: [
      storageObservation.actionRecordReceiptHash,
      storageObservation.receiptRecordReceiptHash,
    ],
    successfulReturnPayload: observation.returnPayloadHex,
    finalEventData: observation.finalLogDataHex,
    finalEventTopics: observation.finalLogTopics,
    exactThreeWayEquality: true,
  },
  claims: {
    positive: { ...ref(materializedClaimPath), module: POSITIVE_MODULE, expectedExitCode: 0 },
    unchangedNegativeDetector: {
      ...ref(materializedClaimPath),
      module: POSITIVE_MODULE,
      definitionRole: "one-byte event-topic mutant",
      expectedExitCode: 1,
    },
    mutantExecutableControl: {
      ...ref(mutantControlClaimPath),
      module: CONTROL_MODULE,
      expectedExitCode: 0,
      requiredMutantTopic0: `0x${mutantTopic0}`,
    },
  },
  mutation: {
    mutationId: "SEP-04-MUT-EVENT-TOPIC-001",
    byteOffset: topicOffset / 2,
    canonicalTopic0: `0x${EXPECTED_TOPIC0}`,
    mutantTopic0: `0x${mutantTopic0}`,
    canonicalOpcode: "PUSH32 0xaa-prefixed topic operand",
    mutantOpcode: "PUSH32 0xab-prefixed topic operand",
    exactByteDifferenceCount: 1,
    mutantRuntimeSha256: sha256(mutantRuntimeBytes),
    mutantBridge: ref(mutantBridgePath),
    mutantVerification: ref(mutantVerificationPath),
    obligationDistinction: "storage and successful return retain the canonical receipt preimage while only the final event topic0 becomes noncanonical",
  },
  bigIntBoundary,
};
const compositionRootSha256 = sha256(Buffer.from(JSON.stringify(stable(compositionInputs))));
write(compositionGraphPath, json({
  ...compositionInputs,
  compositionRootSha256,
  claimBoundary: "v2 binds one exact full-transaction positive claim, the unchanged obligation detector against a one-byte event-topic mutant, and an executable mutant control; proof graphs and the checked K-to-Isabelle certificate remain absent",
}));

const bridge = {
  schemaVersion: 2,
  obligationId: OBLIGATION_ID,
  requiredProperty: REQUIRED_PROPERTY,
  theoremName: THEOREM_NAME,
  status: "OPEN",
  proofStatus: "PASS_OPEN_STATIC_V2",
  eligibleForDischarge: false,
  canonicalObligation: {
    index: ref(obligationIndexPath),
    theoremInventory: ref(theoremInventoryPath),
    classification: "OPEN",
    discharged: false,
  },
  tcb: {
    classification: "OPEN_PLACEHOLDER_PENDING_COORDINATOR_BINDING",
    canonicalIndexPlaceholder: canonicalPlaceholder,
    actualCurrentLock: ref(lockPath),
    runtimeBindingManifest: { ...ref(bindingManifestPath), dependencyLockSha256: currentLockSha256 },
    productDrift: false,
    staticBlocker: false,
  },
  dependencyBoundary: {
    graph: ref(dependencyGraphPath),
    evidenceInherited: false,
    dischargeInherited: false,
  },
  claimBoundary: {
    positive: compositionInputs.claims.positive,
    unchangedNegativeDetector: compositionInputs.claims.unchangedNegativeDetector,
    mutantExecutableControl: compositionInputs.claims.mutantExecutableControl,
    fullTransactionBoundaryPreserved: true,
    exactReceiptPreimageEqualityPreserved: true,
  },
  sourceBlocks,
  bigIntBoundary,
  composition: { graph: ref(compositionGraphPath), rootSha256: compositionRootSha256 },
  semanticBridge: {
    status: "NOT_RUN",
    certificate: null,
    requiredRelation: "checked exact-runtime storage, successful return, and final event observations must instantiate alpha_transaction and canonical_receipt_trace for the same compositional receipt hash",
  },
  selectedExecution: {
    action: "LIQUIDATE",
    reason: "existing exact-bytecode support path observes storage/return/final-log equality and provides a narrow full-transaction fixture target",
    requiredBoundary: "loadTx -> #call -> #finishTx -> #finalizeTx",
  },
  runtimeBinding: {
    bindingManifestPath: repoPath(bindingManifestPath),
    bindingManifestSha256: sha256(bindingManifestBytes),
    deterministicRootSha256: bindingManifest.deterministicRootSha256,
    fixturePath: repoPath(constructorFixturePath),
    fixtureSha256: sha256(constructorFixtureBytes),
    canonicalBridgePath: repoPath(canonicalBridgePath),
    canonicalBridgeSha256: sha256(canonicalBridgeBytes),
    runtimePath: repoPath(resolvedRuntimePath),
    runtimeByteLength: runtime.length,
    runtimeSha256: sha256(runtime),
    runtimeMacro: "#trustTrustTokenRuntime",
  },
  abiEventBinding: {
    compilerArtifactsPath: repoPath(compilerArtifactsPath),
    compilerArtifactsSha256: sha256(compilerArtifactsBytes),
    subject: artifact.id,
    signature: EVENT_SIGNATURE,
    topic0: `0x${derivedTopic0}`,
    anonymous: eventAbi.anonymous,
    inputs: eventAbi.inputs.map(({ name, type, indexed }) => ({ name, type, indexed })),
    finalLogShape: "topic0, actionId, uint8 action, caseId; 32-byte receiptHash data",
  },
  semanticMutation: {
    mutationId: "SEP-04-MUT-EVENT-TOPIC-001",
    kind: "EXECUTABLE_SEMANTIC_MUTANT",
    byteOffset: topicOffset / 2,
    operandInstruction: "PUSH32",
    canonicalByte: "0xaa",
    mutantByte: "0xab",
    canonicalTopic0: `0x${EXPECTED_TOPIC0}`,
    mutantTopic0: `0x${mutantTopic0}`,
    mutantRuntimeSha256: sha256(mutantRuntimeBytes),
    exactByteDifferenceCount: differingByteOffsets.length,
    mutantBridgePath: repoPath(mutantBridgePath),
    mutantBridgeSha256: sha256(readFileSync(mutantBridgePath)),
    mutantVerificationPath: repoPath(mutantVerificationPath),
    mutantVerificationSha256: sha256(readFileSync(mutantVerificationPath)),
    mutantControlClaimPath: repoPath(mutantControlClaimPath),
    mutantControlClaimSha256: sha256(mutantControlClaimBytes),
    mutantControlModule: CONTROL_MODULE,
    discriminatingRequirement: "unchanged claim requires the canonical final event topic while preserving the same storage and return receipt hash",
    acceptableNegative: "exit 1 with a terminal counterexample containing the 0xab-prefixed event topic; no cancellation, timeout, backend error, or pending-only graph",
  },
  supportingCrossChecks: [
    { path: repoPath(kontrolHarnessPath), sha256: sha256(kontrolHarnessBytes), role: "exact-bytecode LIQUIDATE storage/return/final-log cross-check" },
    { path: repoPath(kontrolAssertionPath), sha256: sha256(kontrolAssertionBytes), role: "final log shape assertion" },
    { path: repoPath(foundryEventTestPath), sha256: sha256(foundryEventTestBytes), role: "source-level event ordering cross-check" },
    { path: repoPath(interfacePath), sha256: sha256(interfaceBytes), role: "canonical event declaration" },
    { path: repoPath(tokenSourcePath), sha256: sha256(tokenSourceBytes), role: "receipt storage and event emission source" },
    { path: repoPath(transactionTheoryPath), sha256: sha256(transactionTheoryBytes), role: "abstract transaction receipt trace relation" },
  ],
  materialization: {
    fixtureTemplatePath: repoPath(fixtureTemplatePath),
    fixtureTemplateSha256: sha256(readFileSync(fixtureTemplatePath)),
    fixturePath: repoPath(materializedFixturePath),
    fixtureSha256: sha256(materializedFixtureBytes),
    fixtureValidatorPath: repoPath(fixtureValidatorPath),
    fixtureValidatorSha256: sha256(readFileSync(fixtureValidatorPath)),
    claimTemplatePath: repoPath(claimTemplatePath),
    claimTemplateSha256: sha256(readFileSync(claimTemplatePath)),
    materializedClaimPath: repoPath(materializedClaimPath),
    materializedClaimSha256: sha256(materializedClaimBytes),
    mutantControlClaimPath: repoPath(mutantControlClaimPath),
    mutantControlClaimSha256: sha256(mutantControlClaimBytes),
    requiredPorts,
    missingProofArtifacts: [
      "positive definition and compiled claim hashes",
      "fully closed positive KCFG",
      "mutant definition and compiled claim hashes",
      "terminal discriminating negative KCFG",
      "closed mutant executable-control KCFG",
      "checked exact-runtime observation to alpha_transaction/canonical_receipt_trace certificate",
      "serial Isabelle closure report",
      "fresh independent replay report",
    ],
  },
};
write(rowBridgePath, json(bridge));

const theory = `theory SEP_04_Receipt_Event_Binding\n` +
`  imports ERC_TRUST.TRUST_Transaction_Refinement\n` +
`          ERC_TRUST.TRUST_Runtime_Bridge_Generated\n` +
`begin\n\n` +
`definition sep04_runtime_sha256 :: string where\n` +
`  "sep04_runtime_sha256 = ''${bridge.runtimeBinding.runtimeSha256}''"\n\n` +
`definition sep04_event_signature :: string where\n` +
`  "sep04_event_signature = ''${EVENT_SIGNATURE}''"\n\n` +
`definition sep04_canonical_event_topic :: string where\n` +
`  "sep04_canonical_event_topic = ''0x${EXPECTED_TOPIC0}''"\n\n` +
`definition sep04_mutant_event_topic :: string where\n` +
`  "sep04_mutant_event_topic = ''0x${mutantTopic0}''"\n\n` +
`definition sep04_event_topic_byte_offset :: nat where\n` +
`  "sep04_event_topic_byte_offset = ${bridge.semanticMutation.byteOffset}"\n\n` +
`definition sep04_composition_root_sha256 :: string where\n` +
`  "sep04_composition_root_sha256 = ''${compositionRootSha256}''"\n\n` +
`definition sep04_action_receipt_source_sha256 :: string where\n` +
`  "sep04_action_receipt_source_sha256 = ''${sourceBlocks.actionReceiptStorageReturnEventSha256}''"\n\n` +
`definition sep04_canonical_receipt_trace_source_sha256 :: string where\n` +
`  "sep04_canonical_receipt_trace_source_sha256 = ''${sourceBlocks.canonicalReceiptTraceSha256}''"\n\n` +
`definition sep04_canonical_topic_decimal :: string where\n` +
`  "sep04_canonical_topic_decimal = ''${canonicalTopicDecimal}''"\n\n` +
`definition sep04_mutant_topic_decimal :: string where\n` +
`  "sep04_mutant_topic_decimal = ''${mutantTopicDecimal}''"\n\n` +
`theorem receipt_preimage_matches_storage_return_and_final_event:\n` +
`  assumes alpha: "alpha_transaction manifest bridge execution abstraction"\n` +
`      and applied: "abstraction_outcome abstraction = TRUST_Abstract_Applied"\n` +
`      and receipt: "abstraction_receipt abstraction = Some receipt"\n` +
`  shows "expected_success_state abstraction = Some (abstraction_post_state abstraction) \\<and>\n` +
`         transaction_raw_logs execution \\<noteq> [] \\<and>\n` +
`         last (transaction_raw_logs execution) = bridge_receipt_log bridge receipt \\<and>\n` +
`         (\\<exists>payload. transaction_result execution = TRUST_Return_Success payload \\<and>\n` +
`           bridge_return_receipt_hash bridge payload =\n` +
`             Some (compositional_receipt_hash receipt))"\n` +
`  using assms\n` +
`  by (auto simp: alpha_transaction_def canonical_receipt_trace_def)\n\n` +
`theorem sep04_generated_event_boundary_is_distinct:\n` +
`  "sep04_runtime_sha256 = native_resolved_runtime_sha256 \\<and>\n` +
`   sep04_canonical_event_topic \\<noteq> sep04_mutant_event_topic \\<and>\n` +
`   sep04_event_topic_byte_offset < native_resolved_runtime_byte_length \\<and>\n` +
`   sep04_composition_root_sha256 \\<noteq> '''' \\<and>\n` +
`   sep04_action_receipt_source_sha256 \\<noteq> '''' \\<and>\n` +
`   sep04_canonical_receipt_trace_source_sha256 \\<noteq> '''' \\<and>\n` +
`   sep04_canonical_topic_decimal \\<noteq> sep04_mutant_topic_decimal"\n` +
`  by (simp add: sep04_runtime_sha256_def native_resolved_runtime_sha256_def\n` +
`      sep04_canonical_event_topic_def sep04_mutant_event_topic_def\n` +
`      sep04_event_topic_byte_offset_def native_resolved_runtime_byte_length_def\n` +
`      sep04_composition_root_sha256_def sep04_action_receipt_source_sha256_def\n` +
`      sep04_canonical_receipt_trace_source_sha256_def\n` +
`      sep04_canonical_topic_decimal_def sep04_mutant_topic_decimal_def)\n\n` +
`ML \\<open>\n` +
`  val row_fact = @{thm receipt_preimage_matches_storage_return_and_final_event};\n` +
`  val row_oracles = Thm_Deps.all_oracles [row_fact];\n` +
`  val _ = if null row_oracles then () else\n` +
`    error ("SEP-04 proof audit found " ^ string_of_int (length row_oracles) ^ " oracle dependencies");\n` +
`  val audit_report =\n` +
`    "status=PASS\\n" ^\n` +
`    "qualified_theorem=SEP_04_Receipt_Event_Binding.receipt_preimage_matches_storage_return_and_final_event\\n" ^\n` +
`    "oracle_dependency_count=0\\n";\n` +
`  val _ = Export.export \\<^theory>\n` +
`    \\<^path_binding>\\<open>erc-trust-sep-04/proof-trust.txt\\<close> [XML.Text audit_report];\n` +
`\\<close>\n\n` +
`end\n`;
write(theoryPath, theory);

const remainingBlockers = [
  "fresh closed positive KEVM graph for the exact full-transaction LIQUIDATE claim",
  "fresh terminal semantic negative graph for the unchanged claim against the one-byte final-event-topic mutant",
  "fresh closed mutant executable-control graph requiring the 0xab-prefixed final event topic",
  "checked exact-runtime observation to Isabelle alpha_transaction/canonical_receipt_trace certificate",
  "serial Isabelle clean build and oracle-free export",
  "repository-owned independent replay",
];
const proofInputs = {
  claim: { path: repoPath(materializedClaimPath), sha256: sha256(materializedClaimBytes) },
  claimTemplate: ref(claimTemplatePath),
  mutantExecutableControlClaim: {
    ...ref(mutantControlClaimPath),
    module: CONTROL_MODULE,
  },
  positiveVerification: {
    path: "formal/kevm/trust-runtime-verification.k",
    sha256: sha256(readFileSync(join(repositoryRoot, "formal", "kevm", "trust-runtime-verification.k"))),
  },
  negativeVerification: {
    path: repoPath(mutantVerificationPath),
    sha256: sha256(readFileSync(mutantVerificationPath)),
  },
  negativeRuntimeBridge: {
    path: repoPath(mutantBridgePath),
    sha256: sha256(readFileSync(mutantBridgePath)),
    mutationId: bridge.semanticMutation.mutationId,
    canonicalTopic0: bridge.semanticMutation.canonicalTopic0,
    mutantTopic0: bridge.semanticMutation.mutantTopic0,
  },
  parseOnlyHelper: ref(parseClaimsPath),
};
const skeletonBundle = {
  schemaVersion: 2,
  obligationId: OBLIGATION_ID,
  requiredProperty: REQUIRED_PROPERTY,
  theoremName: THEOREM_NAME,
  status: "OPEN",
  proofStatus: "PASS_OPEN_STATIC_V2",
  eligibleForDischarge: false,
  tcbBinding: {
    classification: bridge.tcb.classification,
    canonicalPlaceholderSha256: PLACEHOLDER_SHA256,
    actualCurrentLock: bridge.tcb.actualCurrentLock,
    runtimeBindingManifestDependencyLockSha256: currentLockSha256,
    productDrift: false,
    blocker: false,
  },
  dependencies: {
    graph: ref(dependencyGraphPath),
    evidenceInherited: false,
    dischargeInherited: false,
  },
  fixture: { path: repoPath(materializedFixturePath), sha256: sha256(materializedFixtureBytes) },
  proofSpec: {
    templatePath: repoPath(claimTemplatePath),
    materializedPath: repoPath(materializedClaimPath),
    module: POSITIVE_MODULE,
    claimId: null,
    sha256: sha256(materializedClaimBytes),
  },
  proofInputs,
  positive: {
    definitionKoreSha256: null,
    compiledJsonSha256: null,
    graph: null,
    requiredExitCode: 0,
    requiredWitnesses: ["EVMC_SUCCESS", "canonical receipt return", "canonical final RegulatoryActionApplied log"],
  },
  negative: {
    mutationId: bridge.semanticMutation.mutationId,
    mutationKind: bridge.semanticMutation.kind,
    definitionKoreSha256: null,
    compiledJsonSha256: null,
    graph: null,
    requiredExitCode: 1,
    requiredWitness: "terminal counterexample distinguishes canonical and 0xab-prefixed event topic",
  },
  mutantExecutableControl: {
    claimId: null,
    graph: null,
    module: CONTROL_MODULE,
    requiredExitCode: 0,
    requiredWitnesses: [
      "EVMC_SUCCESS",
      "canonical receipt hash remains in storage and successful return",
      `final RegulatoryActionApplied topic0 is 0x${mutantTopic0}`,
    ],
  },
  bridge: {
    path: repoPath(rowBridgePath),
    sha256: sha256(readFileSync(rowBridgePath)),
    reverseCheck: "formal/kevm/row-bundles/sep-04/reverse-check.py",
    semanticCertificate: null,
  },
  composition: { ...ref(compositionGraphPath), rootSha256: compositionRootSha256 },
  bigIntBoundary,
  isabelle: {
    theoryPath: repoPath(theoryPath),
    theoremName: THEOREM_NAME,
    session: "ERC_TRUST_SEP_04",
    buildStatus: "NOT_RUN_IN_WORKER",
    closureReport: null,
  },
  replay: { status: "NOT_RUN", report: null, traceRoot: null, stateRoot: null, proofRoot: null },
  blockers: remainingBlockers,
  prohibitedUntilHeavySlotsAvailable: ["KEVM_FULL_PROVE", "ISABELLE_BUILD", "SOLC_COMPILE"],
};
write(skeletonBundlePath, json(skeletonBundle));

const repositoryOwnedTools = [
  "run-row-bundle.sh",
  "validate-bundle.py",
  "analyze-row-proof.mjs",
  "curate-row-output.py",
  "verify-curated-evidence.py",
  "bootstrap-row-proof.sh",
].map((name) => ref(join(sharedRunnerRoot, name)));
const runnerDescriptor = {
  schemaVersion: 2,
  obligationId: OBLIGATION_ID,
  requiredProperty: REQUIRED_PROPERTY,
  theoremName: THEOREM_NAME,
  status: "OPEN",
  proofStatus: "PASS_OPEN_STATIC_V2",
  eligibleForDischarge: false,
  repositoryOwnedTools,
  interfacePilot: [
    "ABI-01", "STATE-02", "STATE-03", "STATE-06", "AUTH-01", "AUTH-02",
    "AUTH-03", "ACT-05", "EXT-01", "SEP-01", "SEP-02", "ART-02",
    "ART-03", "ART-04", "ART-05", "ART-06", "ART-07",
  ],
  inputs: {
    skeletonBundle: ref(skeletonBundlePath),
    compositionGraph: { ...ref(compositionGraphPath), rootSha256: compositionRootSha256 },
    fixture: ref(materializedFixturePath),
    claim: ref(materializedClaimPath),
    mutantExecutableControlClaim: ref(mutantControlClaimPath),
    positiveVerification: proofInputs.positiveVerification,
    negativeVerification: proofInputs.negativeVerification,
    negativeRuntimeBridge: ref(mutantBridgePath),
    parseOnlyHelper: ref(parseClaimsPath),
    isabelleClosureScript: ref(join(rowRoot, "isabelle", "run-closure.ps1")),
  },
  definitionCompileCommandTemplates: {
    positive: [
      "kevm", "kompile-spec", "formal/kevm/trust-runtime-verification.k",
      "--main-module", "TRUST-RUNTIME-VERIFICATION", "--target", "haskell",
      "--emit-json", "--output-definition", "<fresh-positive-definition-directory>",
    ],
    negative: [
      "kevm", "kompile-spec",
      "formal/kevm/row-bundles/sep-04/generated/mutant-runtime-verification.k",
      "--main-module", "TRUST-RUNTIME-VERIFICATION", "--target", "haskell",
      "--emit-json", "--output-definition", "<fresh-negative-definition-directory>",
    ],
  },
  parseOnlyCommandTemplates: {
    positive: [
      "<kevm-pyk-python>", "formal/kevm/row-bundles/sep-04/parse-claims.py",
      "--definition", "<existing-pinned-kevm-definition-directory>",
      "--role", "positive",
    ],
    control: [
      "<kevm-pyk-python>", "formal/kevm/row-bundles/sep-04/parse-claims.py",
      "--definition", "<existing-pinned-kevm-definition-directory>",
      "--role", "control",
    ],
  },
  mutantExecutableControlCommandTemplate: [
    "bash", "formal/kevm/row-bundles/bootstrap-row-proof.sh",
    "--spec", "formal/kevm/row-bundles/sep-04/mutant-control-claim.k",
    "--module", CONTROL_MODULE,
    "--definition", "<exact-negative-definition-directory>",
    "--output-directory", "<fresh-mutant-control-output-directory>",
    "--expected-exit", "0",
  ],
  isabelleClosureCommandTemplate: [
    "powershell", "-File", "formal/kevm/row-bundles/sep-04/isabelle/run-closure.ps1",
    "-IsabelleRoot", "<exact-isabelle-root>",
    "-AdsFunctor", "<exact-ads-functor-directory>",
    "-FormalFoundation", "<exact-formal-foundation-directory>",
    "-OutputDirectory", "<fresh-isabelle-output-directory>",
  ],
  completedBundleValidationCommandTemplate: [
    "python3", "formal/kevm/row-bundles/validate-bundle.py", "<completed-sep-04-bundle.json>",
  ],
  authoritativeCommandTemplate: [
    "bash", "formal/kevm/row-bundles/run-row-bundle.sh",
    "--bundle", "<completed-sep-04-bundle.json>",
    "--positive-definition", "<exact-positive-definition-directory>",
    "--negative-definition", "<exact-negative-definition-directory>",
    "--output-directory", "<fresh-output-directory>",
    "--report", "<fresh-replay-report.json>",
    "--curated-evidence-directory", "<fresh-curated-evidence-directory>",
    "--isabelle-report", "<fresh-sep-04-isabelle-closure-report.json>",
    "--side-timeout-seconds", "<positive-integer>",
    "--no-use-booster",
  ],
  independentReplayPlan: [
    "regenerate, validate the captured fixture, audit BigInt boundaries, and reverse-check all row-local identities",
    "compile fresh canonical and one-byte-mutant KEVM definitions",
    "run the mutant executable-control claim and require a closed 0xab-topic witness",
    "run the unchanged exact-runtime claim against both definitions through the serial repository-owned row runner",
    "produce a checked storage/return/final-event observation to alpha_transaction/canonical_receipt_trace certificate",
    "perform a clean Isabelle build and oracle-free theorem export",
    "validate the completed bundle and independently replay into fresh output and curated evidence",
  ],
  coordinatorSuppliedAfterAuthoritativeRuns: {
    completedBundlePath: null,
    positiveDefinitionDirectory: null,
    negativeDefinitionDirectory: null,
    mutantControlReport: null,
    semanticBridgeCertificate: null,
    isabelleClosureReport: null,
    outputDirectory: null,
    curatedEvidenceDirectory: null,
    replayReport: null,
  },
  proofFacts: {
    positiveClaimId: null,
    positiveDefinitionHashes: null,
    positiveGraph: null,
    negativeDefinitionHashes: null,
    negativeGraph: null,
    mutantControlClaimId: null,
    mutantControlGraph: null,
    semanticBridgeCertificate: null,
    isabelleBuild: null,
    replay: null,
  },
};
write(runnerDescriptorPath, json(runnerDescriptor));

const rowManifest = {
  schemaVersion: 2,
  obligationId: OBLIGATION_ID,
  requiredProperty: REQUIRED_PROPERTY,
  theoremName: THEOREM_NAME,
  status: "OPEN",
  proofStatus: "PASS_OPEN_STATIC_V2",
  eligibleForDischarge: false,
  tcbBinding: skeletonBundle.tcbBinding,
  bridge: { path: repoPath(rowBridgePath), sha256: sha256(readFileSync(rowBridgePath)) },
  compositionGraph: { ...ref(compositionGraphPath), rootSha256: compositionRootSha256 },
  theorem: {
    path: repoPath(theoryPath),
    sha256: sha256(readFileSync(theoryPath)),
    session: "ERC_TRUST_SEP_04",
    name: THEOREM_NAME,
    buildStatus: "NOT_RUN_IN_WORKER",
  },
  proofTemplate: {
    path: repoPath(claimTemplatePath),
    sha256: sha256(readFileSync(claimTemplatePath)),
    module: POSITIVE_MODULE,
    materializedClaim: { path: repoPath(materializedClaimPath), sha256: sha256(materializedClaimBytes) },
  },
  mutantExecutableControl: {
    ...ref(mutantControlClaimPath),
    module: CONTROL_MODULE,
    claimId: null,
    graph: null,
  },
  fixture: { path: repoPath(materializedFixturePath), sha256: sha256(materializedFixtureBytes) },
  generated: [mutantBridgePath, mutantVerificationPath].map((path) => ({
    path: repoPath(path), sha256: sha256(readFileSync(path)),
  })),
  dependencyGraph: { path: repoPath(dependencyGraphPath), sha256: sha256(readFileSync(dependencyGraphPath)) },
  skeletonBundle: { path: repoPath(skeletonBundlePath), sha256: sha256(readFileSync(skeletonBundlePath)) },
  runnerDescriptor: ref(runnerDescriptorPath),
  proofFacts: {
    positiveClaimId: null,
    positiveGraph: null,
    negativeGraph: null,
    mutantControlGraph: null,
    semanticBridgeCertificate: null,
    isabelleClosure: null,
    replay: null,
  },
};
write(rowManifestPath, json(rowManifest));

process.stdout.write(`${JSON.stringify({
  status: "PASS_OPEN_STATIC_V2",
  proofStatus: "NOT_RUN",
  eligibleForDischarge: false,
  obligationId: OBLIGATION_ID,
  requiredProperty: REQUIRED_PROPERTY,
  theoremName: THEOREM_NAME,
  runtimeSha256: bridge.runtimeBinding.runtimeSha256,
  eventTopic0: bridge.abiEventBinding.topic0,
  eventTopicByteOffset: bridge.semanticMutation.byteOffset,
  mutantRuntimeSha256: bridge.semanticMutation.mutantRuntimeSha256,
  bridge: repoPath(rowBridgePath),
  bridgeSha256: sha256(readFileSync(rowBridgePath)),
  theory: repoPath(theoryPath),
  theorySha256: sha256(readFileSync(theoryPath)),
  rowManifest: repoPath(rowManifestPath),
  rowManifestSha256: sha256(readFileSync(rowManifestPath)),
  fixture: repoPath(materializedFixturePath),
  fixtureSha256: sha256(materializedFixtureBytes),
  claim: repoPath(materializedClaimPath),
  claimSha256: sha256(materializedClaimBytes),
  positiveModule: POSITIVE_MODULE,
  mutantControlClaim: repoPath(mutantControlClaimPath),
  mutantControlClaimSha256: sha256(mutantControlClaimBytes),
  mutantControlModule: CONTROL_MODULE,
  compositionGraph: repoPath(compositionGraphPath),
  compositionRootSha256,
  bundleSkeleton: repoPath(skeletonBundlePath),
  bundleSkeletonSha256: sha256(readFileSync(skeletonBundlePath)),
  runnerDescriptor: repoPath(runnerDescriptorPath),
  runnerDescriptorSha256: sha256(readFileSync(runnerDescriptorPath)),
  bigIntBoundary,
  requiredPorts: requiredPorts.length,
}, null, 2)}\n`);
