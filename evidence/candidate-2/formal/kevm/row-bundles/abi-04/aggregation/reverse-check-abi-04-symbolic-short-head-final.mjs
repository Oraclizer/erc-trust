#!/usr/bin/env node
// Fail-closed static reverse check for the final ABI-04 symbolic short-head
// exact set. This invokes neither KEVM nor kore-rpc and grants no proof credit.
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const aggregationDir = path.dirname(fileURLToPath(import.meta.url));
const rowDir = path.dirname(aggregationDir);
const repositoryRoot = path.resolve(rowDir, "../../../..");
const matrixPath = path.join(rowDir, "case-matrix.json");
const mutationPath = path.join(rowDir, "mutation", "mutation-manifest.json");
const indexPath = path.join(aggregationDir, "abi-04-symbolic-short-head-final-claims-index.json");
const contractPath = path.join(aggregationDir, "abi-04-symbolic-short-head-final-contract.json");
const calibratedV5Path = path.join(rowDir, "symbolic-claims-v5", "abi04-native-regulatory-action-short-head-symbolic-lower-v5.k");
const generatorPath = path.join(aggregationDir, "generate-abi-04-symbolic-short-head-final.mjs");
const reverseCheckPath = fileURLToPath(import.meta.url);
const readJson = (value) => JSON.parse(fs.readFileSync(value, "utf8"));
const sha256 = (value) => crypto.createHash("sha256").update(value).digest("hex");
const fileSha256 = (value) => sha256(fs.readFileSync(value));
const count = (source, fragment) => source.split(fragment).length - 1;
const posix = (value) => path.relative(repositoryRoot, value).split(path.sep).join("/");
const matrix = readJson(matrixPath);
const mutation = readJson(mutationPath);
const index = readJson(indexPath);
const contract = readJson(contractPath);

assert.equal(index.kind, "ABI04_SYMBOLIC_SHORT_HEAD_FINAL_CLAIMS_INDEX");
assert.equal(index.classification, "THEOREM_GRADE_SYMBOLIC_EXACT_SET_NOT_PROOF_EVIDENCE");
assert.equal(index.designStatus, "PASS_OPEN_STATIC");
assert.equal(index.parseStatus, "NOT_RUN_AFTER_FINAL_REGENERATION");
assert.equal(index.proofStatus, "NOT_RUN");
assert.equal(index.centralCredit, false);
assert.equal(index.exactClaimCardinality, 12);
assert.equal(index.exactReplayCardinality, 24);
assert.equal(index.representedSubcanonicalLengths, 2868);
assert.equal(index.claims.length, 12);
assert.equal(new Set(index.claims.map((item) => item.semanticClaimId)).size, 12);

const expected = [];
for (const endpoint of matrix.endpoints) {
  const intervals = endpoint.shape === "action" ? [
    { id: "lower", tailFromInclusive: 1, tailToInclusive: 639, calldataFromInclusive: 5, calldataToInclusive: 643, normalizedGapIndexFromInclusive: 0, normalizedGapIndexToInclusive: 638, cardinality: 639 },
    { id: "upper", tailFromInclusive: 641, tailToInclusive: 671, calldataFromInclusive: 645, calldataToInclusive: 675, normalizedGapIndexFromInclusive: 639, normalizedGapIndexToInclusive: 669, cardinality: 31 },
  ] : [
    { id: "lower", tailFromInclusive: 1, tailToInclusive: 255, calldataFromInclusive: 5, calldataToInclusive: 259, normalizedGapIndexFromInclusive: 0, normalizedGapIndexToInclusive: 254, cardinality: 255 },
    { id: "upper", tailFromInclusive: 257, tailToInclusive: 287, calldataFromInclusive: 261, calldataToInclusive: 291, normalizedGapIndexFromInclusive: 255, normalizedGapIndexToInclusive: 285, cardinality: 31 },
  ];
  for (const interval of intervals) expected.push({
    semanticClaimId: `ABI04-${endpoint.id}-short-head-symbolic-${interval.id}`,
    endpoint,
    interval,
  });
}
assert.equal(expected.length, 12);
assert.equal(expected.reduce((sum, item) => sum + item.interval.cardinality, 0), 2868);
assert.deepEqual(index.claims.map((item) => item.semanticClaimId), expected.map((item) => item.semanticClaimId));

for (const [position, item] of index.claims.entries()) {
  const wanted = expected[position];
  const endpoint = wanted.endpoint;
  const interval = wanted.interval;
  assert.equal(item.semanticClaimId, wanted.semanticClaimId);
  assert.equal(item.claimId, item.semanticClaimId);
  assert.equal(item.endpointId, endpoint.id);
  assert.equal(item.shape, endpoint.shape);
  assert.deepEqual(item.interval, interval);
  assert.equal(item.selector, endpoint.selector.toLowerCase());
  assert.equal(item.runtimeBytesSha256, endpoint.resolvedRuntime.runtimeBytesSha256);
  assert.equal(item.canonicalReplayId, `${item.semanticClaimId}::canonical-positive`);
  assert.equal(item.mutantReplayId, `${item.semanticClaimId}::unchanged-claim-mutant-negative`);
  assert.equal(item.parseStatus, "NOT_RUN_AFTER_FINAL_REGENERATION");
  assert.equal(item.proofStatus, "NOT_RUN");
  assert.equal(item.tailContentsConstrained, false);
  assert.equal(item.selectorPrefixGasAccumulator, 64);
  assert.deepEqual(item.target, { k: "#finalizeBlock", exitCode: 1, statusCode: "EVMC_REVERT", output: ".Bytes", storageStutter: true });

  const claimPath = path.join(repositoryRoot, ...item.claim.path.split("/"));
  const recipePath = path.join(repositoryRoot, ...item.recipe.path.split("/"));
  assert.equal(posix(claimPath), item.claim.path);
  assert.equal(fileSha256(claimPath), item.claim.sha256);
  assert.equal(fileSha256(recipePath), item.recipe.sha256);
  assert.equal(item.recipe.claimId, `${item.semanticClaimId}-v2`);
  assert.equal(item.recipe.frameVersion, 2);

  const source = fs.readFileSync(claimPath, "utf8").replaceAll("\r\n", "\n");
  const data = `#parseByteStack("${item.selector}") +Bytes SHORT_TAIL`;
  const selectorDecimal = BigInt(item.selector).toString();
  const selectorBytes = [...Buffer.from(item.selector.slice(2), "hex")];
  assert.deepEqual(item.selectorBytesDecimal, selectorBytes);
  assert.ok(selectorBytes.every((value) => value > 0));
  assert.equal(count(source, `module ${item.module}`), 1);
  assert.equal(count(source, `<data> ${data} </data>`), 1);
  assert.equal(count(source, `requires ${interval.tailFromInclusive} <=Int lengthBytes(SHORT_TAIL)`), 1);
  assert.equal(count(source, `lengthBytes(SHORT_TAIL) <=Int ${interval.tailToInclusive}`), 1);
  assert.equal(count(source, `${interval.calldataFromInclusive} <=Int lengthBytes(${data})`), 1);
  assert.equal(count(source, `(#asWord(#range(${data}, 0, 32)) >>Word 224) ==Int ${selectorDecimal}`), 1);
  for (const [byteIndex, byte] of selectorBytes.entries()) {
    assert.equal(count(source, `(${data})[${byteIndex}] ==Int ${byte}`), 1);
  }
  assert.equal(count(source, `G0(CANCUN, ${data}, 0, lengthBytes(${data}), 0)`), 1);
  assert.equal(count(source, `G0(CANCUN, ${data}, 4, lengthBytes(${data}), 64)`), 1);
  assert.equal(count(source, `notBool ${endpoint.guardSlot} in_keys(ENDPOINT_STORAGE)`), 1);
  assert.equal(count(source, "SHORT_TAIL"), 13);
  assert.equal(count(source, "[4] ==Int"), 0, "tail byte contents must remain unconstrained");
  assert.equal(count(source, "<previousHash> 0 </previousHash>"), 1);
  assert.equal(count(source, "// Whole-cell rewrite prevents ambiguous nested matching in the AC account collection."), 1);
  assert.equal(source.includes("<nonce> 0 => 1 </nonce>"), false);
  assert.equal(count(source, "=> #finalizeBlock"), 1);
  assert.equal(count(source, "=> .K"), 0);
  assert.equal(count(source, "<statusCode> .StatusCode => EVMC_REVERT </statusCode>"), 1);
  assert.equal(count(source, "<output> .Bytes </output>"), 1);
}

const rootInput = index.claims.map((item) => ({
  semanticClaimId: item.semanticClaimId,
  endpointId: item.endpointId,
  interval: item.interval,
  selector: item.selector,
  claimSha256: item.claim.sha256,
  runtimeBytesSha256: item.runtimeBytesSha256,
}));
assert.equal(index.claimsRootSha256, sha256(Buffer.from(JSON.stringify(rootInput))));

assert.equal(contract.kind, "ABI04_SYMBOLIC_SHORT_HEAD_FINAL_CONTRACT");
assert.equal(contract.classification, "STATIC_FINAL_SYMBOLIC_CONTRACT_NOT_DISCHARGE_EVIDENCE");
assert.deepEqual(contract.sourceBinding.generator, { path: posix(generatorPath), sha256: fileSha256(generatorPath) });
assert.deepEqual(contract.sourceBinding.reverseCheck, { path: posix(reverseCheckPath), sha256: fileSha256(reverseCheckPath) });
assert.deepEqual(contract.sourceBinding.calibratedRepresentativeV5, { path: posix(calibratedV5Path), sha256: fileSha256(calibratedV5Path), proofCredit: false });
assert.equal(contract.sourceBinding.caseMatrix.path, posix(matrixPath));
assert.equal(contract.sourceBinding.caseMatrix.sha256, fileSha256(matrixPath));
assert.equal(contract.sourceBinding.caseMatrix.rootSha256, matrix.caseMatrixRootSha256);
assert.equal(contract.sourceBinding.mutationManifest.path, posix(mutationPath));
assert.equal(contract.sourceBinding.mutationManifest.sha256, fileSha256(mutationPath));
assert.equal(contract.sourceBinding.mutationManifest.mutationId, mutation.mutationId);
assert.equal(contract.sourceBinding.claimsIndex.path, posix(indexPath));
assert.equal(contract.sourceBinding.claimsIndex.sha256, fileSha256(indexPath));
assert.equal(contract.sourceBinding.claimsIndex.claimsRootSha256, index.claimsRootSha256);
assert.deepEqual(contract.sourceBinding.recipes, index.claims.map((item) => item.recipe));
assert.deepEqual(contract.exactSet, { endpoints: 6, intervalsPerEndpoint: 2, claims: 12, replaySides: 2, exactReplays: 24, representedSubcanonicalLengths: 2868 });
assert.equal(contract.semanticPreservation.tailIntervalsUnchanged, true);
assert.equal(contract.semanticPreservation.tailContentsUnconstrained, true);
assert.equal(contract.semanticPreservation.claimTargetWeakened, false);
assert.equal(contract.semanticPreservation.intervalNarrowed, false);
assert.equal(contract.semanticPreservation.productPremiseAdded, false);
assert.equal(contract.parseStatus, "NOT_RUN_AFTER_FINAL_REGENERATION");
assert.equal(contract.proofStatus, "NOT_RUN");
assert.equal(contract.closureStatus, "OPEN");
assert.equal(contract.proofCredit, false);
assert.equal(contract.centralCredit, false);

const representative = index.claims.find((item) => item.semanticClaimId === "ABI04-native-regulatory-action-short-head-symbolic-lower");
const representativeSource = fs.readFileSync(path.join(repositoryRoot, ...representative.claim.path.split("/")), "utf8").replaceAll("\r\n", "\n");
const calibratedV5 = fs.readFileSync(calibratedV5Path, "utf8").replaceAll("\r\n", "\n");
const claimBody = (value) => value.slice(value.indexOf("    claim\n"));
assert.equal(claimBody(representativeSource), claimBody(calibratedV5), "representative final claim must preserve calibrated v5 semantic body exactly");

console.log(JSON.stringify({
  status: "PASS_OPEN_STATIC",
  obligationId: "ABI-04",
  classification: index.classification,
  exactClaims: index.claims.length,
  exactReplays: index.exactReplayCardinality,
  representedSubcanonicalLengths: index.representedSubcanonicalLengths,
  claimsRootSha256: index.claimsRootSha256,
  parseStatus: index.parseStatus,
  proofStatus: index.proofStatus,
  centralCredit: index.centralCredit,
}, null, 2));
