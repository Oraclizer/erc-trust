#!/usr/bin/env node
// Independent static reverse check for the ABI-04 dynamic-offset v1 family.
// It performs no K/KEVM/Isabelle execution and grants no proof credit.
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const familyDir = path.dirname(fileURLToPath(import.meta.url));
const rowDir = path.dirname(familyDir);
const repositoryRoot = path.resolve(rowDir, "../../../..");
const readJson = (value) => JSON.parse(fs.readFileSync(value, "utf8"));
const sha256 = (value) => crypto.createHash("sha256").update(value).digest("hex");
const fileSha256 = (value) => sha256(fs.readFileSync(value));
const resolveRepo = (value) => path.join(repositoryRoot, ...value.split("/"));
const count = (source, fragment) => source.split(fragment).length - 1;

const matrix = readJson(path.join(rowDir, "case-matrix.json"));
const index = readJson(path.join(familyDir, "claims-index-v1.json"));
const bigint = readJson(path.join(familyDir, "bigint-boundaries-v1.json"));
const mutant = readJson(path.join(familyDir, "executable-mutant-contract-v1.json"));
const runner = readJson(path.join(familyDir, "repository-runner-coupling-plan-v1.json"));
const contract = readJson(path.join(familyDir, "dynamic-offset-family-v1-contract.json"));
const parseOnlyPath = path.join(familyDir, "parse-only-preflight-v1.json");

assert.equal(index.kind, "ABI04_DYNAMIC_OFFSET_V1_CLAIMS_INDEX");
assert.equal(index.claims.length, 6);
assert.equal(new Set(index.claims.map((claim) => claim.claimId)).size, 6);
assert.deepEqual(index.endpointPartition, { action: 3, reversal: 3 });
assert.equal(index.proofStatus, "NOT_RUN");
assert.equal(index.closureStatus, "OPEN");
assert.equal(index.kParseStatus, "NOT_RUN_AFTER_SOURCE_REGENERATION");
assert.equal(contract.designStatus, "PASS_OPEN_STATIC");
assert.equal(contract.kevmStatus, "NOT_RUN");
assert.equal(contract.isabelleBuildStatus, "NOT_RUN");
assert.equal(contract.closureStatus, "OPEN");
assert.equal(contract.eligibleForDischarge, false);
assert.equal(contract.kParseStatus, "NOT_RUN_AFTER_SOURCE_REGENERATION");
assert.deepEqual(contract.replayCounts, { canonicalPositive: 6, executableMutantNegative: 6, total: 12 });
assert.equal(contract.v1Corrections.productPremiseAdded, false);
assert.equal(contract.v1Corrections.calldataWeakened, false);
assert.equal(contract.v1Corrections.propertyWeakened, false);

for (const binding of Object.values(contract.sourceBinding)) {
  if (binding.path && binding.sha256) assert.equal(fileSha256(resolveRepo(binding.path)), binding.sha256, `contract binding: ${binding.path}`);
}
assert.deepEqual(contract.sourceBinding.parseOnlyPreflight, {
  path: "formal/kevm/row-bundles/abi-04/dynamic-offset-v1/parse-only-preflight-v1.json",
  priorSha256: null,
  status: "INVALIDATED_BY_SOURCE_REGENERATION",
  exactSetComplete: false,
  proofCredit: false,
});
assert.equal(fs.existsSync(parseOnlyPath), false, "stale dynamic-offset parse-only receipt must not remain");
assert.equal(contract.sourceBinding.caseMatrix.rootSha256, matrix.caseMatrixRootSha256);
assert.equal(contract.sourceBinding.claimsIndex.claimsRootSha256, index.claimsRootSha256);

const uint32Max = (1n << 32n) - 1n;
const uint256Max = (1n << 256n) - 1n;
assert.equal(BigInt(bigint.uint32MaxDecimal), uint32Max);
assert.equal(BigInt(bigint.uint256MaxDecimal), uint256Max);
assert.equal(BigInt(bigint.offsetWordDecimal), 32n);
assert.equal(BigInt(bigint.transactionGasLimitDecimal), 1000000n);

const senderId = "1390849295786071768276380950238675083608645509734";
for (const claim of index.claims) {
  const matrixCase = matrix.cases.find((item) => item.caseId === claim.baseCaseId);
  const endpoint = matrix.endpoints.find((item) => item.id === claim.endpointId);
  const boundary = bigint.claims.find((item) => item.claimId === claim.claimId);
  assert.ok(matrixCase && endpoint && boundary);
  assert.equal(matrixCase.malformedClass, "offset");
  assert.equal(claim.calldata, matrixCase.calldata);
  assert.equal(claim.calldataSha256, matrixCase.calldataSha256);
  assert.deepEqual(claim.expected, matrixCase.expected);
  assert.equal(claim.canonicalReplayId, `${claim.claimId}::canonical-positive`);
  assert.equal(claim.mutantReplayId, `${claim.claimId}::unchanged-claim-mutant-negative`);
  assert.equal(claim.originalClaim.sha256, matrixCase.claim.sha256);
  assert.equal(claim.runtimeBytesSha256, endpoint.resolvedRuntime.runtimeBytesSha256);

  const raw = claim.calldata.slice(2);
  const bytes = BigInt(raw.length / 2);
  const selector = BigInt(`0x${raw.slice(0, 8)}`);
  const words = [];
  for (let index = 8; index < raw.length; index += 64) words.push(BigInt(`0x${raw.slice(index, index + 64)}`));
  assert.ok(selector <= uint32Max);
  assert.ok(words.every((word) => word <= uint256Max));
  assert.equal(words[0], 32n);
  assert.ok(words.slice(1).every((word) => word === 0n));
  assert.equal(bytes, BigInt(endpoint.canonicalCalldataBytes + 32));
  assert.equal(words.length, endpoint.tupleWords + 1);
  assert.equal(boundary.selectorDecimal, selector.toString());
  assert.equal(boundary.firstWordDecimal, "32");
  assert.equal(boundary.remainingWordsAllZero, true);

  const bytePairs = raw.match(/../g) ?? [];
  const nonzero = BigInt(bytePairs.filter((byte) => byte !== "00").length);
  const exactIntrinsic = 21000n + nonzero * 16n + (bytes - nonzero) * 4n;
  const worstCase = 21000n + bytes * 16n;
  assert.equal(BigInt(claim.nonzeroBytes), nonzero);
  assert.equal(BigInt(claim.exactIntrinsicGas), exactIntrinsic);
  assert.equal(BigInt(claim.worstCaseIntrinsicGasUpperBound), worstCase);
  assert.ok(exactIntrinsic <= worstCase && worstCase <= 1000000n);

  const source = fs.readFileSync(resolveRepo(claim.claim.path), "utf8").replaceAll("\r\n", "\n");
  assert.equal(fileSha256(resolveRepo(claim.claim.path)), claim.claim.sha256);
  assert.equal(count(source, `module ${claim.module}`), 1);
  assert.equal(count(source, `<data> #parseByteStack("${claim.calldata}") </data>`), 1, `${claim.claimId}: exact calldata cell`);
  assert.equal(count(source, claim.gasFact), 1, `${claim.claimId}: exact gas fact`);
  assert.equal(count(source, `#parseByteStack("${claim.calldata}")`), 3, `${claim.claimId}: data plus two gas-term occurrences`);
  assert.equal(count(source, "G0(CANCUN,"), 1);
  assert.doesNotMatch(source, /\*Int|lengthBytes\([^)]*\)\s*\*Int/, `${claim.claimId}: no product premise`);
  assert.equal(count(source, "<statusCode> .StatusCode => EVMC_REVERT </statusCode>"), 1);
  assert.equal(count(source, "<output> .Bytes </output>"), 1);
  assert.equal(count(source, "<log> .List </log>"), 1);
  assert.equal(count(source, `notBool ${endpoint.guardSlot} in_keys(ENDPOINT_STORAGE)`), 1);

  const block = source.match(/            <block>\n([\s\S]*?)            <\/block>/)?.[1];
  assert.ok(block && !block.includes("..."));
  for (const cell of ["previousHash", "ommersHash", "coinbase", "stateRoot", "transactionsRoot", "receiptsRoot", "logsBloom", "difficulty", "number", "gasLimit", "gasUsed", "timestamp", "extraData", "mixHash", "blockNonce", "baseFee", "withdrawalsRoot", "blobGasUsed", "excessBlobGas", "beaconRoot", "requestsRoot", "ommerBlockHeaders"]) {
    assert.equal(count(source, `<${cell}>`), 1, `${claim.claimId}: full block ${cell}`);
  }
  for (const cell of ["blockhashes", "previousExcessBlobGas", "previousBlobGasUsed"]) assert.equal(count(source, `<${cell}>`), 1);

  const accounts = source.match(/            <accounts>\n([\s\S]*?)            <\/accounts>/)?.[1];
  assert.ok(accounts);
  assert.equal(count(accounts, "=>"), 1);
  assert.equal(count(accounts, "0 => 1"), 0);
  const sides = accounts.split(/\n\s*=>\n/);
  assert.equal(sides.length, 2);
  const expectedIds = ["0", senderId, endpoint.addressDecimal].sort();
  for (const side of sides) {
    const ids = [...side.matchAll(/<acctID> ([0-9]+) <\/acctID>/g)].map((match) => match[1]).sort();
    assert.deepEqual(ids, expectedIds);
    assert.equal(new Set(ids).size, 3);
  }
  assert.equal(count(sides[0], "<nonce> 0 </nonce>"), 2);
  assert.equal(count(sides[1], "<nonce> 0 </nonce>"), 1);
  assert.equal(count(sides[1], "<nonce> 1 </nonce>"), 2);
}

const rootInput = index.claims.map((claim) => ({ claimId: claim.claimId, endpointId: claim.endpointId, claimSha256: claim.claim.sha256, calldataSha256: claim.calldataSha256, runtimeBytesSha256: claim.runtimeBytesSha256, module: claim.module }));
assert.equal(index.claimsRootSha256, sha256(Buffer.from(JSON.stringify(rootInput))));

assert.equal(mutant.kind, "ABI04_DYNAMIC_OFFSET_V1_EXECUTABLE_MUTANT_CONTRACT");
assert.equal(mutant.leaves.length, 6);
assert.equal(mutant.compileStatus, "NOT_RUN");
assert.equal(mutant.replayStatus, "NOT_RUN");
for (const binding of Object.values(mutant.sourceBinding)) assert.equal(fileSha256(resolveRepo(binding.path)), binding.sha256);
for (const leaf of mutant.leaves) {
  const claim = index.claims.find((candidate) => candidate.claimId === leaf.claimId);
  assert.ok(claim);
  assert.equal(leaf.unchangedClaimSha256, claim.claim.sha256);
  assert.equal(leaf.selector, claim.selector);
  assert.equal(leaf.appendedSuccessStubHex, "0x5b60006000f3");
  assert.equal(leaf.patch.selector, claim.selector);
  assert.equal(leaf.expectedCanonicalStatus, "BACKEND_COMPLETE_PASS");
  assert.equal(leaf.expectedMutantStatus, "SEMANTIC_COUNTEREXAMPLE");
  assert.equal(leaf.requiredMutantObservation.statusCode, "EVMC_SUCCESS");
}

assert.equal(runner.kind, "ABI04_DYNAMIC_OFFSET_V1_REPOSITORY_RUNNER_COUPLING_PLAN");
assert.equal(runner.currentRepositoryMutation, false);
assert.equal(runner.family.requiredReplayCount, 12);
assert.equal(fileSha256(resolveRepo(runner.repositoryRunner.path)), runner.repositoryRunner.sha256);
assert.deepEqual(runner.graphContract, contract.expectedGraph);
assert.equal(runner.isolation.workers, 1);
assert.equal(runner.isolation.forceSequential, true);
assert.equal(runner.isolation.booster, false);

const theory = fs.readFileSync(resolveRepo(contract.sourceBinding.isabelleTheory.path), "utf8");
assert.match(theory, /theorem abi04_dynamic_offset_v1_arithmetic:/);
assert.match(theory, /abi04_offset_word < abi04_uint256_bound/);
assert.match(theory, /abi04_action_gas_upper = 32328/);
assert.match(theory, /abi04_reversal_gas_upper = 26184/);
assert.doesNotMatch(theory, /\bsorry\b|\badmit\b|axiomatization|oracle/i);

console.log(JSON.stringify({ status: "PASS_OPEN_STATIC", obligationId: "ABI-04", family: "dynamic-offset-v1", exactClaims: 6, bigintBoundaryStatus: "PASS", fullCancunFrame: true, wholeAccountsRewrite: true, exactCalldataPreserved: true, productPremiseAdded: false, canonicalPositiveLeaves: 6, executableMutantNegativeLeaves: 6, kParseStatus: contract.kParseStatus, parseOnlyExactSetStatus: "INVALIDATED_NOT_PRESENT_CREDIT_0", kevmStatus: contract.kevmStatus, isabelleBuildStatus: contract.isabelleBuildStatus, closureStatus: contract.closureStatus, eligibleForDischarge: contract.eligibleForDischarge, claimsRootSha256: index.claimsRootSha256 }, null, 2));
