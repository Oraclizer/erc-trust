#!/usr/bin/env node
// Deterministically derives the ABI-04 dynamic-offset v1 family from the six
// exact finite matrix leaves. Static generation only: no K/KEVM/Isabelle run.
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const familyDir = path.dirname(fileURLToPath(import.meta.url));
const rowDir = path.dirname(familyDir);
const repositoryRoot = path.resolve(rowDir, "../../../..");
const claimsDir = path.join(familyDir, "claims");
const isabelleDir = path.join(familyDir, "isabelle");
const matrixPath = path.join(rowDir, "case-matrix.json");
const mutationPath = path.join(rowDir, "mutation", "mutation-manifest.json");
const mutantBridgePath = path.join(rowDir, "generated", "mutant-runtime-bridge.k");
const mutantVerificationPath = path.join(rowDir, "generated", "mutant-runtime-verification.k");
const repositoryRunnerPath = path.join(repositoryRoot, "formal", "kevm", "run-abi-calldata-claims.sh");
const lockPath = path.join(repositoryRoot, "formal", "kevm", "dependencies.lock.json");
const parseOnlyPath = path.join(familyDir, "parse-only-preflight-v1.json");
const indexPath = path.join(familyDir, "claims-index-v1.json");
const bigintPath = path.join(familyDir, "bigint-boundaries-v1.json");
const mutantContractPath = path.join(familyDir, "executable-mutant-contract-v1.json");
const runnerPlanPath = path.join(familyDir, "repository-runner-coupling-plan-v1.json");
const contractPath = path.join(familyDir, "dynamic-offset-family-v1-contract.json");
const theoryPath = path.join(isabelleDir, "ABI_04_Dynamic_Offset_Family_V1.thy");
const rootPath = path.join(isabelleDir, "ROOT");
const checkOnly = process.argv.includes("--check");
const write = process.argv.includes("--write");
const planOnly = process.argv.includes("--plan");
const printAll = process.argv.includes("--print-all");
const printFileIndex = process.argv.indexOf("--print-file");
assert.equal([checkOnly, write, planOnly, printAll, printFileIndex >= 0].filter(Boolean).length, 1, "use exactly one output mode");

const sha256 = (value) => crypto.createHash("sha256").update(value).digest("hex");
const fileSha256 = (value) => sha256(fs.readFileSync(value));
const readJson = (value) => JSON.parse(fs.readFileSync(value, "utf8"));
const posix = (value) => path.relative(repositoryRoot, value).split(path.sep).join("/");
const render = (value) => JSON.stringify(value, null, 2) + "\n";
const count = (source, fragment) => source.split(fragment).length - 1;

const matrix = readJson(matrixPath);
const mutation = readJson(mutationPath);
const lock = readJson(lockPath);
const priorParseOnly = fs.existsSync(parseOnlyPath) ? readJson(parseOnlyPath) : null;
const cases = matrix.cases.filter((item) => item.malformedClass === "offset");
assert.equal(matrix.obligationId, "ABI-04");
assert.equal(cases.length, 6);
assert.equal(new Set(cases.map((item) => item.endpointId)).size, 6);
assert.equal(mutation.mutationKind, "EXECUTABLE_SEMANTIC_BYTECODE_MUTANT");
if (priorParseOnly) assert.equal(priorParseOnly.kind, "ABI04_DYNAMIC_OFFSET_V1_K_PARSE_ONLY_PREFLIGHT");
assert.equal(priorParseOnly, null, "stale dynamic-offset parse-only receipt must be absent after source regeneration");

const emptyOmmersHashDecimal = BigInt("0x1dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347").toString();
const zeroBloomHex = `0x${"00".repeat(256)}`;
const oldBlock = `            <block>
              <coinbase> 0 </coinbase>
              <gasLimit> 30000000 </gasLimit>
              <gasUsed> 0:Gas </gasUsed>
              <baseFee> 0 </baseFee>
              ...
            </block>
            ...`;
const fullBlock = `            <blockhashes> .List </blockhashes>
            <previousExcessBlobGas> 0 </previousExcessBlobGas>
            <previousBlobGasUsed> 0 </previousBlobGasUsed>

            <block>
              <previousHash> 0 </previousHash>
              <ommersHash> ${emptyOmmersHashDecimal} </ommersHash>
              <coinbase> 0 </coinbase>
              <stateRoot> 0 </stateRoot>
              <transactionsRoot> 0 </transactionsRoot>
              <receiptsRoot> 0 </receiptsRoot>
              <logsBloom> #parseByteStack("${zeroBloomHex}") </logsBloom>
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
            ...`;

function indentTwo(value) {
  return value.split("\n").map((line) => line ? `  ${line}` : line).join("\n");
}

function sourceFor(item) {
  const sourcePath = path.join(repositoryRoot, ...item.claim.path.split("/"));
  let source = fs.readFileSync(sourcePath, "utf8").replaceAll("\r\n", "\n");
  const claimId = `${item.caseId}-v1`;
  const module = item.module.replace(/_SPEC$/, "_V1_SPEC");
  const replacements = [
    ["// GENERATED ABI-04 theorem-grade exact-runtime claim. DO NOT EDIT.", "// GENERATED ABI-04 dynamic-offset theorem-grade backend-ready v1 claim. DO NOT EDIT."],
    [`// Case: ${item.caseId}`, `// Claim family leaf: ${claimId}`],
    ["// Malformed class: offset", "// Malformed class: noncanonical dynamic-offset envelope over a static tuple"],
    [`module ${item.module}`, `module ${module}`],
  ];
  for (const [before, after] of replacements) {
    assert.equal(count(source, before), 1, `${item.caseId}: unique source fragment`);
    source = source.replace(before, after);
  }

  const endpoint = matrix.endpoints.find((candidate) => candidate.id === item.endpointId);
  assert.ok(endpoint);
  const data = `#parseByteStack("${item.calldata}")`;
  const gasFact = `1000000 >=Int maxInt(G0(CANCUN, ${data}, 0, lengthBytes(${data}), 0) +Int 21000, 0)`;
  assert.equal(count(source, gasFact), 1, `${item.caseId}: exact gas premise`);
  assert.equal(count(source, "<previousHash> 0 </previousHash>"), 1, `${item.caseId}: full Cancun frame`);
  assert.equal(count(source, "// Whole-cell rewrite fixes the three keyed accounts on both sides."), 1, `${item.caseId}: whole accounts rewrite`);
  assert.equal(source.includes("<nonce> 0 => 1 </nonce>"), false, `${item.caseId}: no partial keyed-account rewrite`);
  assert.equal(count(source, `<data> ${data} </data>`), 1, `${item.caseId}: exact calldata`);
  assert.equal(count(source, "<statusCode> .StatusCode => EVMC_REVERT </statusCode>"), 1, `${item.caseId}: unchanged revert target`);
  return { source, claimId, module, gasFact, endpoint };
}

const uint256Max = (1n << 256n) - 1n;
const uint32Max = (1n << 32n) - 1n;
const claims = cases.map((item) => {
  const derived = sourceFor(item);
  const claimPath = path.join(claimsDir, `${derived.claimId.toLowerCase()}.k`);
  const raw = item.calldata.slice(2);
  const bytes = BigInt(raw.length / 2);
  const selector = BigInt(`0x${raw.slice(0, 8)}`);
  const words = [];
  for (let index = 8; index < raw.length; index += 64) words.push(BigInt(`0x${raw.slice(index, index + 64)}`));
  const nonzeroBytes = BigInt((raw.match(/../g) ?? []).filter((byte) => byte !== "00").length);
  const zeroBytes = bytes - nonzeroBytes;
  const exactCalldataGas = nonzeroBytes * 16n + zeroBytes * 4n;
  const worstCaseCalldataGas = bytes * 16n;
  assert.equal(words[0], 32n);
  assert.ok(words.slice(1).every((word) => word === 0n));
  assert.equal(bytes, BigInt(derived.endpoint.canonicalCalldataBytes + 32));
  assert.equal(words.length, derived.endpoint.tupleWords + 1);
  assert.ok(selector <= uint32Max && words.every((word) => word <= uint256Max));
  return {
    claimId: derived.claimId,
    baseCaseId: item.caseId,
    endpointId: item.endpointId,
    shape: derived.endpoint.shape,
    selector: item.calldata.slice(0, 10),
    module: derived.module,
    claim: { path: posix(claimPath), sha256: sha256(derived.source) },
    originalClaim: { path: item.claim.path, sha256: item.claim.sha256 },
    calldata: item.calldata,
    calldataBytes: item.calldataBytes,
    calldataSha256: item.calldataSha256,
    tupleWords: derived.endpoint.tupleWords,
    envelopeWords: words.length,
    offsetWordDecimal: words[0].toString(),
    nonzeroBytes: nonzeroBytes.toString(),
    exactIntrinsicGas: (21000n + exactCalldataGas).toString(),
    worstCaseIntrinsicGasUpperBound: (21000n + worstCaseCalldataGas).toString(),
    transactionGasLimit: "1000000",
    runtimeBytesSha256: derived.endpoint.resolvedRuntime.runtimeBytesSha256,
    expected: item.expected,
    gasFact: derived.gasFact,
    canonicalReplayId: `${derived.claimId}::canonical-positive`,
    mutantReplayId: `${derived.claimId}::unchanged-claim-mutant-negative`,
    source: derived.source,
  };
});

const rootInput = claims.map((claim) => ({
  claimId: claim.claimId,
  endpointId: claim.endpointId,
  claimSha256: claim.claim.sha256,
  calldataSha256: claim.calldataSha256,
  runtimeBytesSha256: claim.runtimeBytesSha256,
  module: claim.module,
}));
const claimsRootSha256 = sha256(Buffer.from(JSON.stringify(rootInput)));
const index = {
  schemaVersion: 1,
  kind: "ABI04_DYNAMIC_OFFSET_V1_CLAIMS_INDEX",
  obligationId: "ABI-04",
  classification: "STATIC_BACKEND_READY_CLAIM_INDEX_NOT_PROOF_EVIDENCE",
  designStatus: "PASS_OPEN_STATIC",
  kParseStatus: "NOT_RUN_AFTER_SOURCE_REGENERATION",
  proofStatus: "NOT_RUN",
  closureStatus: "OPEN",
  exactFamilyCardinality: 6,
  endpointPartition: { action: 3, reversal: 3 },
  claimsRootSha256,
  claims: claims.map(({ source, ...claim }) => claim),
};
const indexText = render(index);

const bigintBoundaries = {
  schemaVersion: 1,
  kind: "ABI04_DYNAMIC_OFFSET_V1_BIGINT_BOUNDARIES",
  obligationId: "ABI-04",
  arithmeticDomain: "ECMAScript BigInt; decimal fields are strings and are never coerced through Number",
  uint32MaxDecimal: uint32Max.toString(),
  uint256MaxDecimal: uint256Max.toString(),
  offsetWordDecimal: "32",
  transactionGasLimitDecimal: "1000000",
  gasConstants: { transactionBase: "21000", calldataZeroByte: "4", calldataNonzeroByte: "16" },
  families: {
    action: { canonicalCalldataBytes: "676", envelopeCalldataBytes: "708", addedEnvelopeBytes: "32", envelopeWordsAfterSelector: "22", exactIntrinsicGas: "23892", worstCaseIntrinsicGasUpperBound: "32328", minimumWorstCaseMargin: "967672" },
    reversal: { canonicalCalldataBytes: "292", envelopeCalldataBytes: "324", addedEnvelopeBytes: "32", envelopeWordsAfterSelector: "10", exactIntrinsicGas: "22356", worstCaseIntrinsicGasUpperBound: "26184", minimumWorstCaseMargin: "973816" },
  },
  claims: claims.map((claim) => ({ claimId: claim.claimId, selector: claim.selector, selectorDecimal: BigInt(claim.selector).toString(), calldataBytes: String(claim.calldataBytes), envelopeWordsAfterSelector: String(claim.envelopeWords), firstWordDecimal: claim.offsetWordDecimal, remainingWordsAllZero: true, nonzeroBytes: claim.nonzeroBytes, exactIntrinsicGas: claim.exactIntrinsicGas, worstCaseIntrinsicGasUpperBound: claim.worstCaseIntrinsicGasUpperBound, transactionGasLimit: claim.transactionGasLimit })),
  invariants: ["selector <= 2^32 - 1", "each 32-byte word <= 2^256 - 1", "first word = 32", "every remaining word = 0", "envelope calldata bytes = canonical calldata bytes + 32", "exact intrinsic gas <= worst-case intrinsic gas upper bound <= 1000000"],
  status: "PASS_OPEN_STATIC",
  proofCredit: false,
};
const bigintText = render(bigintBoundaries);

const mutantByRuntime = new Map(mutation.runtimes.map((runtime) => [runtime.id, runtime]));
const endpointRuntimeId = (claim) => claim.endpointId.startsWith("profile-") ? "ERC3643TrustAdapter" : "TrustToken";
const mutantLeaves = claims.map((claim) => {
  const runtime = mutantByRuntime.get(endpointRuntimeId(claim));
  const patch = runtime.patches.find((candidate) => candidate.selector === claim.selector);
  assert.ok(patch, `${claim.claimId}: mutant selector patch`);
  return { claimId: claim.claimId, endpointId: claim.endpointId, selector: claim.selector, runtimeId: runtime.id, canonicalRuntimeSha256: runtime.canonicalSha256, mutatedRuntimeSha256: runtime.mutatedSha256, appendedSuccessStubHex: runtime.appendedSuccessStubHex, patch, unchangedClaimSha256: claim.claim.sha256, expectedCanonicalStatus: "BACKEND_COMPLETE_PASS", expectedMutantStatus: "SEMANTIC_COUNTEREXAMPLE", requiredMutantObservation: { statusCode: "EVMC_SUCCESS", outputHex: "0x", contradiction: "The unchanged claim requires EVMC_REVERT." } };
});
const mutantContract = {
  schemaVersion: 1,
  kind: "ABI04_DYNAMIC_OFFSET_V1_EXECUTABLE_MUTANT_CONTRACT",
  obligationId: "ABI-04",
  classification: "STATIC_EXECUTABLE_SEMANTIC_MUTANT_BINDING_NOT_REPLAY_EVIDENCE",
  designStatus: "PASS_OPEN_STATIC",
  compileStatus: "NOT_RUN",
  replayStatus: "NOT_RUN",
  sourceBinding: {
    mutationManifest: { path: posix(mutationPath), sha256: fileSha256(mutationPath), mutationId: mutation.mutationId },
    mutantRuntimeBridge: { path: posix(mutantBridgePath), sha256: fileSha256(mutantBridgePath) },
    mutantRuntimeVerification: { path: posix(mutantVerificationPath), sha256: fileSha256(mutantVerificationPath) },
    claimsIndex: { path: posix(indexPath), sha256: sha256(indexText), claimsRootSha256 },
  },
  design: {
    mutationKind: mutation.mutationKind,
    definitionDeltaOnly: "Canonical runtime bridge macros are replaced by dispatcher-patched runtimes; the v1 claim bytes are unchanged between positive and negative sides.",
    patchScope: "Only the six covered endpoint selectors are redirected to the appended 0x5b60006000f3 JUMPDEST/PUSH0/PUSH0/RETURN empty-success stub.",
    adequacy: "The mutant bypasses the generated static-tuple ABI decoder, so each exact dynamic-envelope calldata succeeds with empty output and contradicts the unchanged EVMC_REVERT target.",
    prohibitedNegativeCredit: ["negative PASS", "compile failure", "parse failure", "timeout", "cancellation", "backend error", "pending/stuck/vacuous/admitted graph"],
  },
  leaves: mutantLeaves,
  proofCredit: false,
};
const mutantText = render(mutantContract);

const runnerPlan = {
  schemaVersion: 1,
  kind: "ABI04_DYNAMIC_OFFSET_V1_REPOSITORY_RUNNER_COUPLING_PLAN",
  obligationId: "ABI-04",
  classification: "WORKER_LOCAL_EXTENSION_PLAN_NOT_APPLIED",
  status: "NOT_RUN",
  repositoryRunner: { path: posix(repositoryRunnerPath), sha256: fileSha256(repositoryRunnerPath), currentBoundary: "Hard-coded two-claim canonical-only initial ABI campaign." },
  dependencyLock: { path: posix(lockPath), sha256: fileSha256(lockPath), kproveStorePath: lock.components.kFramework.outputStorePath, koreRpcStorePath: lock.components.kore.rpcStorePath },
  family: { claimsIndexPath: posix(indexPath), claimsIndexSha256: sha256(indexText), claimsRootSha256, leaves: 6, replaySides: 2, requiredReplayCount: 12, kParseStatus: "NOT_RUN_AFTER_SOURCE_REGENERATION" },
  integrationPlan: [
    "Add an explicit campaign-descriptor input without changing the legacy default campaign.",
    "Resolve exactly the six v1 claim paths/modules/hashes from claims-index-v1.json and reject missing, duplicate, or extra leaves.",
    "Strip only the first relative requires line into a fresh output root; rehash and parse every module against the pinned definition.",
    "Run canonical positives serially with one worker, --force-sequential, --no-use-booster, and unique save/temp/log directories.",
    "Compile the existing executable mutant verification source into a fresh negative definition, reverse-check runtime patch hashes, then run byte-identical claims serially.",
    "Classify saved proof/KCFG artifacts structurally and emit one record per exact replay ID; never infer status from exit code alone.",
  ],
  graphContract: {
    kind: "CONJUNCTIVE_12_REPLAY_DAG",
    rootNodeId: "ABI-04::dynamic-offset-v1",
    leafNodePattern: "<claimId>::canonical-positive | <claimId>::unchanged-claim-mutant-negative",
    canonicalAcceptance: ["status=PASS", "backendComplete=true", "pending=0", "stuck=0", "vacuous=0", "admitted=false", "target EVMC_REVERT/output/log/storage property matched"],
    mutantAcceptance: ["status=SEMANTIC_COUNTEREXAMPLE", "terminalWitness=true", "observedStatus=EVMC_SUCCESS", "observedOutputHex=0x", "same claim hash as positive side", "no timeout/cancellation/backend error"],
    successCondition: "All 12 exact leaves accepted; any absent, duplicate, mismatched, or prohibited result leaves the family OPEN.",
  },
  isolation: { workers: 1, forceSequential: true, booster: false, oneProcessPerClaimSide: true, freshDefinitionsPerCampaign: true, uniqueOutputPerClaimSide: true },
  currentRepositoryMutation: false,
  proofCredit: false,
};
const runnerText = render(runnerPlan);

const theory = `theory ABI_04_Dynamic_Offset_Family_V1
  imports Main
begin

definition abi04_offset_word :: nat where "abi04_offset_word = 32"
definition abi04_uint256_bound :: nat where "abi04_uint256_bound = 2 ^ 256"
definition abi04_action_envelope_bytes :: nat where "abi04_action_envelope_bytes = 708"
definition abi04_reversal_envelope_bytes :: nat where "abi04_reversal_envelope_bytes = 324"
definition abi04_action_gas_upper :: nat where "abi04_action_gas_upper = 21000 + 708 * 16"
definition abi04_reversal_gas_upper :: nat where "abi04_reversal_gas_upper = 21000 + 324 * 16"
definition abi04_tx_gas_limit :: nat where "abi04_tx_gas_limit = 1000000"

theorem abi04_dynamic_offset_v1_arithmetic:
  "abi04_offset_word < abi04_uint256_bound \<and>
   abi04_action_envelope_bytes = 676 + 32 \<and>
   abi04_reversal_envelope_bytes = 292 + 32 \<and>
   abi04_action_gas_upper = 32328 \<and>
   abi04_reversal_gas_upper = 26184 \<and>
   abi04_action_gas_upper \<le> abi04_tx_gas_limit \<and>
   abi04_reversal_gas_upper \<le> abi04_tx_gas_limit \<and>
   3 + 3 = (6::nat) \<and> 6 * 2 = (12::nat)"
  by (simp add: abi04_offset_word_def abi04_uint256_bound_def
      abi04_action_envelope_bytes_def abi04_reversal_envelope_bytes_def
      abi04_action_gas_upper_def abi04_reversal_gas_upper_def abi04_tx_gas_limit_def)

end
`;
const root = `session ERC_TRUST_ABI_04_DYNAMIC_OFFSET_V1 = ERC_TRUST +
  theories
    ABI_04_Dynamic_Offset_Family_V1
`;

const contract = {
  schemaVersion: 1,
  kind: "ABI04_DYNAMIC_OFFSET_V1_FAMILY_CONTRACT",
  obligationId: "ABI-04",
  requiredFacet: "noncanonical_dynamic_offset_envelope_reverts_and_stutters",
  classification: "THEOREM_GRADE_BACKEND_READY_STATIC_FAMILY_NOT_PROOF_EVIDENCE",
  designStatus: "PASS_OPEN_STATIC",
  kParseStatus: "NOT_RUN_AFTER_SOURCE_REGENERATION",
  kevmStatus: "NOT_RUN",
  isabelleBuildStatus: "NOT_RUN",
  closureStatus: "OPEN",
  eligibleForDischarge: false,
  sourceBinding: {
    caseMatrix: { path: posix(matrixPath), sha256: fileSha256(matrixPath), rootSha256: matrix.caseMatrixRootSha256 },
    parseOnlyPreflight: {
      path: posix(parseOnlyPath),
      priorSha256: priorParseOnly ? fileSha256(parseOnlyPath) : null,
      status: "INVALIDATED_BY_SOURCE_REGENERATION",
      exactSetComplete: false,
      proofCredit: false,
    },
    claimsIndex: { path: posix(indexPath), sha256: sha256(indexText), claimsRootSha256 },
    bigintBoundaries: { path: posix(bigintPath), sha256: sha256(bigintText) },
    executableMutantContract: { path: posix(mutantContractPath), sha256: sha256(mutantText) },
    repositoryRunnerCouplingPlan: { path: posix(runnerPlanPath), sha256: sha256(runnerText) },
    isabelleTheory: { path: posix(theoryPath), sha256: sha256(theory), session: "ERC_TRUST_ABI_04_DYNAMIC_OFFSET_V1", theorem: "abi04_dynamic_offset_v1_arithmetic" },
    isabelleRoot: { path: posix(rootPath), sha256: sha256(root) },
  },
  exactProperty: {
    caseCount: 6,
    endpoints: claims.map((claim) => claim.endpointId),
    calldataRule: "Every v1 leaf retains the byte-identical concrete calldata literal and calldata SHA-256 from its case-matrix leaf.",
    postconditionRule: "Every v1 leaf retains EVMC_REVERT, empty output, committed-log stutter, endpoint storage/original-storage stutter, and the endpoint guard anti-alias condition.",
    dynamicOffsetInterpretation: "The static ActionRequest/ReversalRequest tuples have no canonical offset word. The exact 32-prefixed overlength envelopes are concrete noncanonical impostors and overlap ABI-03 without granting ABI-03 credit.",
  },
  v1Corrections: {
    fullCancunFrame: true,
    wholeAccountsCellRewrite: true,
    exactIntrinsicGasSufficiencyFact: true,
    productPremiseAdded: false,
    calldataWeakened: false,
    propertyWeakened: false,
  },
  expectedGraph: runnerPlan.graphContract,
  replayCounts: { canonicalPositive: 6, executableMutantNegative: 6, total: 12 },
  nonClaims: ["Static generation, BigInt checks, and source-only Isabelle text do not prove KEVM semantics.", "The completed K parse-only exact set does not grant proof credit.", "No heavy KEVM or Isabelle execution has run.", "The six cases do not grant ABI-03 coverage credit.", "ABI-04 remains OPEN."],
};
const contractText = render(contract);

const files = [
  ...claims.map((claim) => ({ path: path.join(repositoryRoot, ...claim.claim.path.split("/")), content: claim.source })),
  { path: indexPath, content: indexText },
  { path: bigintPath, content: bigintText },
  { path: mutantContractPath, content: mutantText },
  { path: runnerPlanPath, content: runnerText },
  { path: contractPath, content: contractText },
  { path: theoryPath, content: theory },
  { path: rootPath, content: root },
];
const generationPlan = files.map((file) => {
  const actual = fs.existsSync(file.path) ? fs.readFileSync(file.path, "utf8").replaceAll("\r\n", "\n") : null;
  return { path: posix(file.path), status: actual === file.content ? "UNCHANGED" : actual === null ? "MISSING" : "CHANGED", actualSha256: actual === null ? null : sha256(actual), expectedSha256: sha256(file.content) };
});

if (write) {
  for (const file of files) {
    fs.mkdirSync(path.dirname(file.path), { recursive: true });
    fs.writeFileSync(file.path, file.content, "utf8");
  }
  console.log(JSON.stringify({ status: "MATERIALIZED_STATIC_ONLY", family: "dynamic-offset-v1", files: files.length, claims: claims.length, claimsRootSha256, kParseStatus: contract.kParseStatus }, null, 2));
} else if (printFileIndex >= 0) {
  const requested = process.argv[printFileIndex + 1];
  assert.ok(requested, "--print-file requires a repository-relative path");
  const selected = files.find((file) => posix(file.path) === requested);
  assert.ok(selected, `unknown generated file: ${requested}`);
  process.stdout.write(selected.content);
} else if (printAll) {
  process.stdout.write(JSON.stringify({ files }));
} else if (planOnly) {
  console.log(JSON.stringify({ status: "PASS_GENERATION_PLAN", family: "dynamic-offset-v1", files: files.length, claims: claims.length, claimsRootSha256, changes: { changed: generationPlan.filter((item) => item.status === "CHANGED").length, missing: generationPlan.filter((item) => item.status === "MISSING").length, unchanged: generationPlan.filter((item) => item.status === "UNCHANGED").length, files: generationPlan }, proofCredit: false, centralCredit: false }, null, 2));
} else if (checkOnly) {
  for (const file of files) assert.equal(fs.readFileSync(file.path, "utf8").replaceAll("\r\n", "\n"), file.content, `stale generated file: ${file.path}`);
  console.log(JSON.stringify({ status: "PASS_OPEN_STATIC", obligationId: "ABI-04", family: "dynamic-offset-v1", claims: claims.length, claimsRootSha256, kParseStatus: contract.kParseStatus, kevmStatus: contract.kevmStatus, isabelleBuildStatus: contract.isabelleBuildStatus, closureStatus: contract.closureStatus }, null, 2));
} else {
  throw new Error("Use --write for deterministic materialization, --plan/--print-all/--print-file for inspection, or --check.");
}
