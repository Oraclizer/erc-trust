#!/usr/bin/env node
// Deterministically derives the ABI-04 dynamic-length v1 family from the six
// exact finite matrix leaves and the already checked full-frame offset family.
// Static generation only: no K/KEVM/Isabelle execution.
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
const offsetDir = path.join(rowDir, "dynamic-offset-v1");
const matrixPath = path.join(rowDir, "case-matrix.json");
const offsetIndexPath = path.join(offsetDir, "claims-index-v1.json");
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
const contractPath = path.join(familyDir, "dynamic-length-family-v1-contract.json");
const theoryPath = path.join(isabelleDir, "ABI_04_Dynamic_Length_Family_V1.thy");
const rootPath = path.join(isabelleDir, "ROOT");
const readmePath = path.join(familyDir, "README.md");
const checkOnly = process.argv.includes("--check");
const write = process.argv.includes("--write");
const planOnly = process.argv.includes("--plan");
assert.equal([checkOnly, write, planOnly].filter(Boolean).length, 1, "use exactly one of --write, --check, or --plan");

const sha256 = (value) => crypto.createHash("sha256").update(value).digest("hex");
const fileSha256 = (value) => sha256(fs.readFileSync(value));
const readJson = (value) => JSON.parse(fs.readFileSync(value, "utf8"));
const posix = (value) => path.relative(repositoryRoot, value).split(path.sep).join("/");
const render = (value) => JSON.stringify(value, null, 2) + "\n";
const count = (source, fragment) => source.split(fragment).length - 1;
const replaceOnce = (source, before, after, message) => {
  assert.equal(count(source, before), 1, message);
  return source.replace(before, after);
};

const matrix = readJson(matrixPath);
const offsetIndex = readJson(offsetIndexPath);
const mutation = readJson(mutationPath);
const lock = readJson(lockPath);
const cases = matrix.cases.filter((item) => item.malformedClass === "length");
assert.equal(matrix.obligationId, "ABI-04");
assert.equal(cases.length, 6);
assert.equal(new Set(cases.map((item) => item.endpointId)).size, 6);
assert.equal(offsetIndex.kind, "ABI04_DYNAMIC_OFFSET_V1_CLAIMS_INDEX");
assert.equal(offsetIndex.claims.length, 6);
assert.equal(mutation.mutationKind, "EXECUTABLE_SEMANTIC_BYTECODE_MUTANT");

const uint32Max = (1n << 32n) - 1n;
const uint256Max = (1n << 256n) - 1n;
const claims = cases.map((item) => {
  const endpoint = matrix.endpoints.find((candidate) => candidate.id === item.endpointId);
  const offsetClaim = offsetIndex.claims.find((candidate) => candidate.endpointId === item.endpointId);
  assert.ok(endpoint && offsetClaim, `${item.endpointId}: endpoint and offset template`);
  const offsetPath = path.join(repositoryRoot, ...offsetClaim.claim.path.split("/"));
  let source = fs.readFileSync(offsetPath, "utf8").replaceAll("\r\n", "\n");
  const claimId = `${item.caseId}-v1`;
  const module = item.module.replace(/_SPEC$/, "_V1_SPEC");
  source = replaceOnce(source,
    "// GENERATED ABI-04 dynamic-offset theorem-grade backend-ready v1 claim. DO NOT EDIT.",
    "// GENERATED ABI-04 dynamic-length theorem-grade backend-ready v1 claim. DO NOT EDIT.",
    `${claimId}: generated identity`);
  source = replaceOnce(source,
    `// Claim family leaf: ${offsetClaim.claimId}`,
    `// Claim family leaf: ${claimId}`,
    `${claimId}: claim identity`);
  source = replaceOnce(source,
    "// Malformed class: noncanonical dynamic-offset envelope over a static tuple",
    "// Malformed class: noncanonical dynamic-length envelope over a static tuple",
    `${claimId}: malformed class`);
  source = replaceOnce(source, `module ${offsetClaim.module}`, `module ${module}`, `${claimId}: module`);
  assert.equal(count(source, offsetClaim.calldata), 3, `${claimId}: offset calldata occurrences`);
  source = source.replaceAll(offsetClaim.calldata, item.calldata);

  const raw = item.calldata.slice(2);
  const bytes = BigInt(raw.length / 2);
  const selector = BigInt(`0x${raw.slice(0, 8)}`);
  const words = [];
  for (let index = 8; index < raw.length; index += 64) words.push(BigInt(`0x${raw.slice(index, index + 64)}`));
  const nonzeroBytes = BigInt((raw.match(/../g) ?? []).filter((byte) => byte !== "00").length);
  const zeroBytes = bytes - nonzeroBytes;
  const exactIntrinsicGas = 21000n + nonzeroBytes * 16n + zeroBytes * 4n;
  const worstCaseIntrinsicGas = 21000n + bytes * 16n;
  assert.equal(words[0], BigInt(endpoint.tupleWords));
  assert.equal(words[1], 32n);
  assert.ok(words.slice(2).every((word) => word === 0n));
  assert.equal(bytes, BigInt(endpoint.canonicalCalldataBytes + 64));
  assert.equal(words.length, endpoint.tupleWords + 2);
  assert.ok(selector <= uint32Max && words.every((word) => word <= uint256Max));
  assert.equal(sha256(Buffer.from(raw, "hex")), item.calldataSha256);
  const claimPath = path.join(claimsDir, `${claimId.toLowerCase()}.k`);
  const data = `#parseByteStack("${item.calldata}")`;
  const gasFact = `1000000 >=Int maxInt(G0(CANCUN, ${data}, 0, lengthBytes(${data}), 0) +Int 21000, 0)`;
  assert.equal(count(source, gasFact), 1, `${claimId}: gas fact after calldata replacement`);
  return {
    claimId,
    baseCaseId: item.caseId,
    endpointId: item.endpointId,
    shape: endpoint.shape,
    selector: item.calldata.slice(0, 10),
    module,
    claim: { path: posix(claimPath), sha256: sha256(source) },
    templateOffsetClaim: { path: offsetClaim.claim.path, sha256: offsetClaim.claim.sha256 },
    originalClaim: { path: item.claim.path, sha256: item.claim.sha256 },
    calldata: item.calldata,
    calldataBytes: item.calldataBytes,
    calldataSha256: item.calldataSha256,
    tupleWords: endpoint.tupleWords,
    envelopeWords: words.length,
    lengthWordDecimal: words[0].toString(),
    secondWordDecimal: words[1].toString(),
    trailingWordsAllZero: true,
    nonzeroBytes: nonzeroBytes.toString(),
    exactIntrinsicGas: exactIntrinsicGas.toString(),
    worstCaseIntrinsicGasUpperBound: worstCaseIntrinsicGas.toString(),
    transactionGasLimit: "1000000",
    runtimeBytesSha256: endpoint.resolvedRuntime.runtimeBytesSha256,
    expected: item.expected,
    gasFact,
    canonicalReplayId: `${claimId}::canonical-positive`,
    mutantReplayId: `${claimId}::unchanged-claim-mutant-negative`,
    source,
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
  kind: "ABI04_DYNAMIC_LENGTH_V1_CLAIMS_INDEX",
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

const actionClaims = claims.filter((claim) => claim.endpointId.endsWith("action"));
const reversalClaims = claims.filter((claim) => claim.endpointId.endsWith("reversal"));
assert.ok(actionClaims.every((claim) => claim.calldataBytes === 740 && claim.lengthWordDecimal === "21" && claim.secondWordDecimal === "32"));
assert.ok(reversalClaims.every((claim) => claim.calldataBytes === 356 && claim.lengthWordDecimal === "9" && claim.secondWordDecimal === "32"));
const bigint = {
  schemaVersion: 1,
  kind: "ABI04_DYNAMIC_LENGTH_V1_BIGINT_BOUNDARIES",
  obligationId: "ABI-04",
  arithmeticDomain: "ECMAScript BigInt; decimal fields are strings and are never coerced through Number",
  uint32MaxDecimal: uint32Max.toString(),
  uint256MaxDecimal: uint256Max.toString(),
  transactionGasLimitDecimal: "1000000",
  gasConstants: { transactionBase: "21000", calldataZeroByte: "4", calldataNonzeroByte: "16" },
  families: {
    action: { tupleWords: "21", lengthWordDecimal: "21", secondWordDecimal: "32", canonicalCalldataBytes: "676", envelopeCalldataBytes: "740", addedEnvelopeBytes: "64", envelopeWordsAfterSelector: "23", exactIntrinsicGas: "24032", worstCaseIntrinsicGasUpperBound: "32840", minimumWorstCaseMargin: "967160" },
    reversal: { tupleWords: "9", lengthWordDecimal: "9", secondWordDecimal: "32", canonicalCalldataBytes: "292", envelopeCalldataBytes: "356", addedEnvelopeBytes: "64", envelopeWordsAfterSelector: "11", exactIntrinsicGas: "22496", worstCaseIntrinsicGasUpperBound: "26696", minimumWorstCaseMargin: "973304" },
  },
  claims: claims.map((claim) => ({ claimId: claim.claimId, selector: claim.selector, selectorDecimal: BigInt(claim.selector).toString(), calldataBytes: String(claim.calldataBytes), envelopeWordsAfterSelector: String(claim.envelopeWords), lengthWordDecimal: claim.lengthWordDecimal, secondWordDecimal: claim.secondWordDecimal, trailingWordsAllZero: claim.trailingWordsAllZero, nonzeroBytes: claim.nonzeroBytes, exactIntrinsicGas: claim.exactIntrinsicGas, worstCaseIntrinsicGasUpperBound: claim.worstCaseIntrinsicGasUpperBound, transactionGasLimit: claim.transactionGasLimit })),
  invariants: ["selector <= 2^32 - 1", "each 32-byte word <= 2^256 - 1", "first word = endpoint tuple-word count (21 action or 9 reversal)", "second word = 32", "every remaining word = 0", "envelope calldata bytes = canonical calldata bytes + 64", "exact intrinsic gas <= worst-case intrinsic gas upper bound <= 1000000"],
  status: "PASS_OPEN_STATIC",
  proofCredit: false,
};
const bigintText = render(bigint);

const mutantByRuntime = new Map(mutation.runtimes.map((runtime) => [runtime.id, runtime]));
const runtimeId = (claim) => claim.endpointId.startsWith("profile-") ? "ERC3643TrustAdapter" : "TrustToken";
const mutantLeaves = claims.map((claim) => {
  const runtime = mutantByRuntime.get(runtimeId(claim));
  const patch = runtime.patches.find((candidate) => candidate.selector === claim.selector);
  assert.ok(patch, `${claim.claimId}: mutant selector patch`);
  return { claimId: claim.claimId, endpointId: claim.endpointId, selector: claim.selector, runtimeId: runtime.id, canonicalRuntimeSha256: runtime.canonicalSha256, mutatedRuntimeSha256: runtime.mutatedSha256, appendedSuccessStubHex: runtime.appendedSuccessStubHex, patch, unchangedClaimSha256: claim.claim.sha256, expectedCanonicalStatus: "BACKEND_COMPLETE_PASS", expectedMutantStatus: "SEMANTIC_COUNTEREXAMPLE", requiredMutantObservation: { statusCode: "EVMC_SUCCESS", outputHex: "0x", contradiction: "The unchanged claim requires EVMC_REVERT." } };
});
const mutantContract = {
  schemaVersion: 1,
  kind: "ABI04_DYNAMIC_LENGTH_V1_EXECUTABLE_MUTANT_CONTRACT",
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
    definitionDeltaOnly: "Canonical runtime bridge macros are replaced by dispatcher-patched runtimes; every v1 claim is byte-identical across positive and negative sides.",
    patchScope: "Only the six covered endpoint selectors are redirected to the appended 0x5b60006000f3 empty-success stub.",
    adequacy: "The mutant bypasses the static-tuple decoder, so each exact length-envelope calldata succeeds with empty output and contradicts the unchanged EVMC_REVERT target.",
    prohibitedNegativeCredit: ["negative PASS", "compile failure", "parse failure", "timeout", "cancellation", "backend error", "pending/stuck/vacuous/admitted graph"],
  },
  leaves: mutantLeaves,
  proofCredit: false,
};
const mutantText = render(mutantContract);

const graphContract = {
  kind: "CONJUNCTIVE_12_REPLAY_DAG",
  rootNodeId: "ABI-04::dynamic-length-v1",
  leafNodePattern: "<claimId>::canonical-positive | <claimId>::unchanged-claim-mutant-negative",
  canonicalAcceptance: ["status=PASS", "backendComplete=true", "pending=0", "stuck=0", "vacuous=0", "admitted=false", "target EVMC_REVERT/output/log/storage property matched"],
  mutantAcceptance: ["status=SEMANTIC_COUNTEREXAMPLE", "terminalWitness=true", "observedStatus=EVMC_SUCCESS", "observedOutputHex=0x", "same claim hash as positive side", "no timeout/cancellation/backend error"],
  successCondition: "All 12 exact leaves accepted; any absent, duplicate, mismatched, or prohibited result leaves this family OPEN and grants no row discharge.",
};
const runnerPlan = {
  schemaVersion: 1,
  kind: "ABI04_DYNAMIC_LENGTH_V1_REPOSITORY_RUNNER_COUPLING_PLAN",
  obligationId: "ABI-04",
  classification: "WORKER_LOCAL_EXTENSION_PLAN_NOT_APPLIED",
  status: "NOT_RUN",
  repositoryRunner: { path: posix(repositoryRunnerPath), sha256: fileSha256(repositoryRunnerPath), currentBoundary: "Hard-coded two-claim canonical-only initial ABI campaign." },
  dependencyLock: { path: posix(lockPath), sha256: fileSha256(lockPath), kproveStorePath: lock.components.kFramework.outputStorePath, koreRpcStorePath: lock.components.kore.rpcStorePath },
  family: { claimsIndexPath: posix(indexPath), claimsIndexSha256: sha256(indexText), claimsRootSha256, leaves: 6, replaySides: 2, requiredReplayCount: 12, kParseStatus: index.kParseStatus },
  integrationPlan: [
    "Add an explicit campaign descriptor without changing the legacy default campaign.",
    "Resolve exactly the six v1 claim paths/modules/hashes and reject missing, duplicate, or extra leaves.",
    "Strip only the first relative requires line into a fresh output root; rehash and parse every module against the pinned definition.",
    "Run canonical positives serially with one worker, --force-sequential, --no-use-booster, and unique save/temp/log directories.",
    "Compile the existing executable mutant verification source into a fresh negative definition, reverse-check runtime patch hashes, then run byte-identical claims serially.",
    "Classify saved proof/KCFG artifacts structurally and emit one record per exact replay ID; never infer status from exit code alone.",
    "Keep this family separate from dynamic-offset-v1 and all other ABI-04 families; no family result alone discharges the row."
  ],
  graphContract,
  isolation: { workers: 1, forceSequential: true, booster: false, oneProcessPerClaimSide: true, freshDefinitionsPerCampaign: true, uniqueOutputPerClaimSide: true },
  currentRepositoryMutation: false,
  proofCredit: false,
};
const runnerText = render(runnerPlan);

const theory = `theory ABI_04_Dynamic_Length_Family_V1
  imports Main
begin

definition abi04_action_tuple_words :: nat where "abi04_action_tuple_words = 21"
definition abi04_reversal_tuple_words :: nat where "abi04_reversal_tuple_words = 9"
definition abi04_second_word :: nat where "abi04_second_word = 32"
definition abi04_uint256_bound :: nat where "abi04_uint256_bound = 2 ^ 256"
definition abi04_action_envelope_bytes :: nat where "abi04_action_envelope_bytes = 740"
definition abi04_reversal_envelope_bytes :: nat where "abi04_reversal_envelope_bytes = 356"
definition abi04_action_gas_upper :: nat where "abi04_action_gas_upper = 21000 + 740 * 16"
definition abi04_reversal_gas_upper :: nat where "abi04_reversal_gas_upper = 21000 + 356 * 16"
definition abi04_tx_gas_limit :: nat where "abi04_tx_gas_limit = 1000000"

theorem abi04_dynamic_length_v1_arithmetic:
  "abi04_action_tuple_words < abi04_uint256_bound \<and>
   abi04_reversal_tuple_words < abi04_uint256_bound \<and>
   abi04_second_word < abi04_uint256_bound \<and>
   abi04_action_envelope_bytes = 676 + 64 \<and>
   abi04_reversal_envelope_bytes = 292 + 64 \<and>
   abi04_action_gas_upper = 32840 \<and>
   abi04_reversal_gas_upper = 26696 \<and>
   abi04_action_gas_upper \<le> abi04_tx_gas_limit \<and>
   abi04_reversal_gas_upper \<le> abi04_tx_gas_limit \<and>
   3 + 3 = (6::nat) \<and> 6 * 2 = (12::nat)"
  by (simp add: abi04_action_tuple_words_def abi04_reversal_tuple_words_def
      abi04_second_word_def abi04_uint256_bound_def
      abi04_action_envelope_bytes_def abi04_reversal_envelope_bytes_def
      abi04_action_gas_upper_def abi04_reversal_gas_upper_def abi04_tx_gas_limit_def)

end
`;
const root = `session ERC_TRUST_ABI_04_DYNAMIC_LENGTH_V1 = ERC_TRUST +
  theories
    ABI_04_Dynamic_Length_Family_V1
`;

const readme = `# ABI-04 dynamic-length theorem-grade backend-ready v1

This worker-local family upgrades the six exact dynamic-length matrix leaves
without changing calldata bytes or the required revert/stutter property. The
static tuples have no canonical dynamic length field. Action envelopes prepend
the concrete words 21 and 32 to 21 zero tuple words; reversal envelopes prepend
9 and 32 to 9 zero tuple words. These noncanonical overlength impostors overlap
ABI-03 trailing calldata but grant no ABI-03 credit.

Each claim preserves the exact matrix calldata literal and hash, runtime,
EVMC_REVERT, empty output, committed-log stutter, storage/original-storage
stutter, and guard anti-alias condition. It reuses the full Cancun frame, whole
accounts rewrite, and sound exact G0 sufficiency shape from dynamic-offset-v1.

The same unchanged claim is required on the executable selector-to-empty-success
mutant side. Canonical leaves require backend-complete PASS; mutant leaves require
a terminal EVMC_SUCCESS/empty-output semantic counterexample. The 12 leaves form
only this family's conjunction and never discharge ABI-04 by themselves.

Static reproduction:

\`\`\`powershell
node formal/kevm/row-bundles/abi-04/dynamic-length-v1/generate-dynamic-length-family-v1.mjs --check
node formal/kevm/row-bundles/abi-04/dynamic-length-v1/reverse-check-dynamic-length-family-v1.mjs
\`\`\`

All six sources are required to pass pinned K parse-only. Heavy KEVM and the
source-only Isabelle build remain NOT_RUN.
`;

const priorParseOnly = fs.existsSync(parseOnlyPath) ? readJson(parseOnlyPath) : null;
if (priorParseOnly) assert.equal(priorParseOnly.kind, "ABI04_DYNAMIC_LENGTH_V1_K_PARSE_ONLY_PREFLIGHT");
assert.equal(priorParseOnly, null, "stale dynamic-length parse-only receipt must be absent after source regeneration");
const contract = {
  schemaVersion: 1,
  kind: "ABI04_DYNAMIC_LENGTH_V1_FAMILY_CONTRACT",
  obligationId: "ABI-04",
  requiredFacet: "noncanonical_dynamic_length_envelope_reverts_and_stutters",
  classification: "THEOREM_GRADE_BACKEND_READY_STATIC_FAMILY_NOT_PROOF_EVIDENCE",
  designStatus: "PASS_OPEN_STATIC",
  kParseStatus: "NOT_RUN_AFTER_SOURCE_REGENERATION",
  kevmStatus: "NOT_RUN",
  isabelleBuildStatus: "NOT_RUN",
  closureStatus: "OPEN",
  eligibleForDischarge: false,
  sourceBinding: {
    caseMatrix: { path: posix(matrixPath), sha256: fileSha256(matrixPath), rootSha256: matrix.caseMatrixRootSha256 },
    offsetTemplateIndex: { path: posix(offsetIndexPath), sha256: fileSha256(offsetIndexPath), claimsRootSha256: offsetIndex.claimsRootSha256 },
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
    isabelleTheory: { path: posix(theoryPath), sha256: sha256(theory), session: "ERC_TRUST_ABI_04_DYNAMIC_LENGTH_V1", theorem: "abi04_dynamic_length_v1_arithmetic" },
    isabelleRoot: { path: posix(rootPath), sha256: sha256(root) },
  },
  exactProperty: {
    caseCount: 6,
    endpoints: claims.map((claim) => claim.endpointId),
    calldataRule: "Every leaf retains the byte-identical concrete calldata literal and calldata SHA-256 from its dynamic-length case-matrix leaf.",
    postconditionRule: "Every leaf retains EVMC_REVERT, empty output, committed-log stutter, endpoint storage/original-storage stutter, and the endpoint guard anti-alias condition.",
    dynamicLengthInterpretation: "Static ActionRequest/ReversalRequest tuples have no canonical length word. Exact 21/9 then 32 prefixed envelopes are noncanonical overlength impostors and overlap ABI-03 without granting ABI-03 credit.",
  },
  v1Corrections: { fullCancunFrame: true, wholeAccountsCellRewrite: true, exactIntrinsicGasSufficiencyFact: true, productPremiseAdded: false, calldataWeakened: false, propertyWeakened: false },
  expectedGraph: graphContract,
  replayCounts: { canonicalPositive: 6, executableMutantNegative: 6, total: 12 },
  aggregationBoundary: "This contract closes no other ABI-04 family and is insufficient for row discharge by itself.",
  nonClaims: ["Static generation, BigInt checks, and source-only Isabelle text do not prove KEVM semantics.", "K parse-only grants no proof credit.", "No heavy KEVM or Isabelle execution has run.", "The six cases grant no ABI-03 coverage credit.", "ABI-04 remains OPEN."],
};

const files = [
  ...claims.map((claim) => ({ path: path.join(repositoryRoot, ...claim.claim.path.split("/")), content: claim.source })),
  { path: indexPath, content: indexText },
  { path: bigintPath, content: bigintText },
  { path: mutantContractPath, content: mutantText },
  { path: runnerPlanPath, content: runnerText },
  { path: theoryPath, content: theory },
  { path: rootPath, content: root },
  { path: readmePath, content: readme },
  { path: contractPath, content: render(contract) },
];
const generationPlan = files.map((file) => {
  const actual = fs.existsSync(file.path) ? fs.readFileSync(file.path, "utf8").replaceAll("\r\n", "\n") : null;
  return { path: posix(file.path), status: actual === file.content ? "UNCHANGED" : actual === null ? "MISSING" : "CHANGED", actualSha256: actual === null ? null : sha256(actual), expectedSha256: sha256(file.content) };
});

if (write) {
  for (const file of files) {
    fs.mkdirSync(path.dirname(file.path), { recursive: true });
    fs.writeFileSync(file.path, file.content);
  }
  console.log(JSON.stringify({ status: "MATERIALIZED_STATIC_ONLY", family: "dynamic-length-v1", files: files.length, claims: claims.length, claimsRootSha256, kParseStatus: index.kParseStatus, contractMaterialized: true }, null, 2));
} else if (planOnly) {
  console.log(JSON.stringify({ status: "PASS_GENERATION_PLAN", family: "dynamic-length-v1", files: files.length, claims: claims.length, claimsRootSha256, changes: { changed: generationPlan.filter((item) => item.status === "CHANGED").length, missing: generationPlan.filter((item) => item.status === "MISSING").length, unchanged: generationPlan.filter((item) => item.status === "UNCHANGED").length, files: generationPlan }, proofCredit: false, centralCredit: false }, null, 2));
} else if (checkOnly) {
  for (const file of files) assert.equal(fs.readFileSync(file.path, "utf8").replaceAll("\r\n", "\n"), file.content, `stale generated file: ${file.path}`);
  console.log(JSON.stringify({ status: "PASS_OPEN_STATIC", obligationId: "ABI-04", family: "dynamic-length-v1", claims: claims.length, claimsRootSha256, kParseStatus: contract.kParseStatus, kevmStatus: contract.kevmStatus, isabelleBuildStatus: contract.isabelleBuildStatus, closureStatus: contract.closureStatus }, null, 2));
} else {
  throw new Error("Use --write for deterministic materialization, --plan for inspection, or --check.");
}
