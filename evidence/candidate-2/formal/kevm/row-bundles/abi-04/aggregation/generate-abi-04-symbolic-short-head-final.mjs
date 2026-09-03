#!/usr/bin/env node
// Deterministically materializes the twelve final ABI-04 symbolic short-head
// claims. It generalizes the v5 fixed-prefix/G0 facts to every endpoint without
// narrowing SHORT_TAIL or weakening the revert/stutter target.
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const aggregationDir = path.dirname(fileURLToPath(import.meta.url));
const rowDir = path.dirname(aggregationDir);
const repositoryRoot = path.resolve(rowDir, "../../../..");
const generatorPath = fileURLToPath(import.meta.url);
const reverseCheckPath = path.join(aggregationDir, "reverse-check-abi-04-symbolic-short-head-final.mjs");
const calibratedV5Path = path.join(rowDir, "symbolic-claims-v5", "abi04-native-regulatory-action-short-head-symbolic-lower-v5.k");
const matrixPath = path.join(rowDir, "case-matrix.json");
const mutationPath = path.join(rowDir, "mutation", "mutation-manifest.json");
const recipesDir = path.join(rowDir, "symbolic-claims-v2");
const outputDir = path.join(rowDir, "symbolic-claims");
const indexPath = path.join(aggregationDir, "abi-04-symbolic-short-head-final-claims-index.json");
const contractPath = path.join(aggregationDir, "abi-04-symbolic-short-head-final-contract.json");
const writeMode = process.argv.includes("--write");
const checkMode = process.argv.includes("--check");
const planMode = process.argv.includes("--plan");
assert.equal([writeMode, checkMode, planMode].filter(Boolean).length, 1, "use exactly one of --write, --check, or --plan");

const sha256 = (value) => crypto.createHash("sha256").update(value).digest("hex");
const fileSha256 = (value) => sha256(fs.readFileSync(value));
const readJson = (value) => JSON.parse(fs.readFileSync(value, "utf8"));
const posix = (value) => path.relative(repositoryRoot, value).split(path.sep).join("/");
const render = (value) => `${JSON.stringify(value, null, 2)}\n`;
const count = (source, fragment) => source.split(fragment).length - 1;
const matrix = readJson(matrixPath);
const mutation = readJson(mutationPath);
assert.equal(matrix.obligationId, "ABI-04");
assert.equal(matrix.endpoints.length, 6);
assert.equal(mutation.mutationKind, "EXECUTABLE_SEMANTIC_BYTECODE_MUTANT");

const intervalsFor = (endpoint) => endpoint.shape === "action" ? [
  { id: "lower", tailFromInclusive: 1, tailToInclusive: 639, calldataFromInclusive: 5, calldataToInclusive: 643, normalizedGapIndexFromInclusive: 0, normalizedGapIndexToInclusive: 638, cardinality: 639 },
  { id: "upper", tailFromInclusive: 641, tailToInclusive: 671, calldataFromInclusive: 645, calldataToInclusive: 675, normalizedGapIndexFromInclusive: 639, normalizedGapIndexToInclusive: 669, cardinality: 31 },
] : [
  { id: "lower", tailFromInclusive: 1, tailToInclusive: 255, calldataFromInclusive: 5, calldataToInclusive: 259, normalizedGapIndexFromInclusive: 0, normalizedGapIndexToInclusive: 254, cardinality: 255 },
  { id: "upper", tailFromInclusive: 257, tailToInclusive: 287, calldataFromInclusive: 261, calldataToInclusive: 291, normalizedGapIndexFromInclusive: 255, normalizedGapIndexToInclusive: 285, cardinality: 31 },
];

function replaceOnce(source, before, after, message) {
  assert.equal(count(source, before), 1, message);
  return source.replace(before, after);
}

function finalSource(endpoint, interval) {
  const semanticClaimId = `ABI04-${endpoint.id}-short-head-symbolic-${interval.id}`;
  const recipeClaimId = `${semanticClaimId}-v2`;
  const recipeModule = `${recipeClaimId.replaceAll("-", "_").toUpperCase()}_SPEC`;
  const module = `${semanticClaimId.replaceAll("-", "_").toUpperCase()}_SPEC`;
  const recipePath = path.join(recipesDir, `${recipeClaimId.toLowerCase()}.k`);
  let source = fs.readFileSync(recipePath, "utf8").replaceAll("\r\n", "\n");
  source = replaceOnce(source, "// GENERATED ABI-04 symbolic short-head interval v2 claim. DO NOT EDIT.", "// GENERATED ABI-04 symbolic short-head final claim. DO NOT EDIT.", `${semanticClaimId}: recipe marker`);
  source = replaceOnce(source, `// Claim family: ${recipeClaimId}`, `// Claim family: ${semanticClaimId}`, `${semanticClaimId}: recipe identity`);
  source = replaceOnce(source, `// Universal tail interval: ${interval.tailFromInclusive}..${interval.tailToInclusive} bytes`, `// Universal tail interval: ${interval.tailFromInclusive}..${interval.tailToInclusive} bytes\n// Fixed selector facts and the entailed index-4 G0 premise preserve this entire interval.`, `${semanticClaimId}: interval marker`);
  source = replaceOnce(source, `module ${recipeModule}`, `module ${module}`, `${semanticClaimId}: recipe module`);

  const selector = endpoint.selector.toLowerCase();
  const selectorHex = selector.slice(2);
  const selectorBytes = selectorHex.match(/../g).map((value) => Number.parseInt(value, 16));
  assert.equal(selectorBytes.length, 4);
  assert.ok(selectorBytes.every((value) => value > 0), `${semanticClaimId}: selector bytes must all be nonzero for accumulator 64`);
  const data = `#parseByteStack("${selector}") +Bytes SHORT_TAIL`;
  const requires = `    requires ${interval.tailFromInclusive} <=Int lengthBytes(SHORT_TAIL)
      andBool lengthBytes(SHORT_TAIL) <=Int ${interval.tailToInclusive}
      andBool ${interval.calldataFromInclusive} <=Int lengthBytes(${data})
      andBool (#asWord(#range(${data}, 0, 32)) >>Word 224) ==Int ${BigInt(selector).toString()}
${selectorBytes.map((value, index) => `      andBool (${data})[${index}] ==Int ${value}`).join("\n")}
      andBool 1000000 >=Int maxInt(G0(CANCUN, ${data}, 0, lengthBytes(${data}), 0) +Int 21000, 0)
      andBool 1000000 >=Int maxInt(G0(CANCUN, ${data}, 4, lengthBytes(${data}), 64) +Int 21000, 0)
      andBool notBool ${endpoint.guardSlot} in_keys(ENDPOINT_STORAGE)`;
  const requiresPattern = /    requires [\s\S]*?\nendmodule\n$/;
  assert.match(source, requiresPattern, `${semanticClaimId}: requires block`);
  source = source.replace(requiresPattern, `${requires}\nendmodule\n`);

  assert.equal(count(source, "<previousHash> 0 </previousHash>"), 1, `${semanticClaimId}: full Cancun frame`);
  assert.equal(count(source, "// Whole-cell rewrite prevents ambiguous nested matching in the AC account collection."), 1, `${semanticClaimId}: whole accounts rewrite`);
  assert.equal(source.includes("<nonce> 0 => 1 </nonce>"), false, `${semanticClaimId}: no partial account rewrite`);
  assert.equal(count(source, `<data> ${data} </data>`), 1, `${semanticClaimId}: unchanged symbolic calldata`);
  assert.equal(count(source, "<statusCode> .StatusCode => EVMC_REVERT </statusCode>"), 1, `${semanticClaimId}: unchanged revert target`);
  assert.equal(count(source, "<output> .Bytes </output>"), 1, `${semanticClaimId}: unchanged output target`);
  // The appended premises reference SHORT_TAIL exactly ten additional times:
  // length (1), selector word (1), four fixed bytes (4), and two G0 facts
  // whose data and length operands each reference it (4). This guards the
  // transformation surface without pretending a raw token count is a proof.
  assert.equal(count(source, "SHORT_TAIL"), count(fs.readFileSync(recipePath, "utf8"), "SHORT_TAIL") + 10, `${semanticClaimId}: exact entailed SHORT_TAIL fact surface`);
  if (semanticClaimId === "ABI04-native-regulatory-action-short-head-symbolic-lower") {
    const calibratedV5 = fs.readFileSync(calibratedV5Path, "utf8").replaceAll("\r\n", "\n");
    const claimBody = (value) => value.slice(value.indexOf("    claim\n"));
    assert.notEqual(claimBody(source), source, `${semanticClaimId}: generated claim body marker`);
    assert.notEqual(claimBody(calibratedV5), calibratedV5, `${semanticClaimId}: calibrated v5 claim body marker`);
    assert.equal(claimBody(source), claimBody(calibratedV5), `${semanticClaimId}: exact calibrated v5 semantic body parity`);
  }
  return { semanticClaimId, recipeClaimId, recipeModule, module, recipePath, source, selector, selectorBytes, data };
}

const claims = [];
for (const endpoint of matrix.endpoints) {
  for (const interval of intervalsFor(endpoint)) {
    const derived = finalSource(endpoint, interval);
    const claimPath = path.join(outputDir, `${derived.semanticClaimId.toLowerCase()}.k`);
    claims.push({
      semanticClaimId: derived.semanticClaimId,
      claimId: derived.semanticClaimId,
      endpointId: endpoint.id,
      shape: endpoint.shape,
      interval,
      selector: derived.selector,
      module: derived.module,
      claim: { path: posix(claimPath), sha256: sha256(derived.source) },
      recipe: { claimId: derived.recipeClaimId, path: posix(derived.recipePath), sha256: fileSha256(derived.recipePath), frameVersion: 2 },
      runtimeBytesSha256: endpoint.resolvedRuntime.runtimeBytesSha256,
      calldataExpression: derived.data,
      selectorBytesDecimal: derived.selectorBytes,
      selectorPrefixGasAccumulator: 64,
      tailContentsConstrained: false,
      target: { k: "#finalizeBlock", exitCode: 1, statusCode: "EVMC_REVERT", output: ".Bytes", storageStutter: true },
      canonicalReplayId: `${derived.semanticClaimId}::canonical-positive`,
      mutantReplayId: `${derived.semanticClaimId}::unchanged-claim-mutant-negative`,
      parseStatus: "NOT_RUN_AFTER_FINAL_REGENERATION",
      proofStatus: "NOT_RUN",
      source: derived.source,
    });
  }
}
assert.equal(claims.length, 12);
assert.equal(new Set(claims.map((item) => item.semanticClaimId)).size, 12);
assert.equal(claims.reduce((total, item) => total + item.interval.cardinality, 0), 2868);

const claimsRootInput = claims.map((item) => ({ semanticClaimId: item.semanticClaimId, endpointId: item.endpointId, interval: item.interval, selector: item.selector, claimSha256: item.claim.sha256, runtimeBytesSha256: item.runtimeBytesSha256 }));
const claimsRootSha256 = sha256(Buffer.from(JSON.stringify(claimsRootInput)));
const index = {
  schemaVersion: 1,
  kind: "ABI04_SYMBOLIC_SHORT_HEAD_FINAL_CLAIMS_INDEX",
  obligationId: "ABI-04",
  classification: "THEOREM_GRADE_SYMBOLIC_EXACT_SET_NOT_PROOF_EVIDENCE",
  designStatus: "PASS_OPEN_STATIC",
  parseStatus: "NOT_RUN_AFTER_FINAL_REGENERATION",
  proofStatus: "NOT_RUN",
  centralCredit: false,
  exactClaimCardinality: 12,
  exactReplayCardinality: 24,
  representedSubcanonicalLengths: 2868,
  claimsRootSha256,
  claims: claims.map(({ source, ...item }) => item),
};
const indexText = render(index);
const contract = {
  schemaVersion: 1,
  kind: "ABI04_SYMBOLIC_SHORT_HEAD_FINAL_CONTRACT",
  obligationId: "ABI-04",
  classification: "STATIC_FINAL_SYMBOLIC_CONTRACT_NOT_DISCHARGE_EVIDENCE",
  sourceBinding: {
    generator: { path: posix(generatorPath), sha256: fileSha256(generatorPath) },
    reverseCheck: { path: posix(reverseCheckPath), sha256: fileSha256(reverseCheckPath) },
    calibratedRepresentativeV5: { path: posix(calibratedV5Path), sha256: fileSha256(calibratedV5Path), proofCredit: false },
    caseMatrix: { path: posix(matrixPath), sha256: fileSha256(matrixPath), rootSha256: matrix.caseMatrixRootSha256 },
    mutationManifest: { path: posix(mutationPath), sha256: fileSha256(mutationPath), mutationId: mutation.mutationId },
    claimsIndex: { path: posix(indexPath), sha256: sha256(indexText), claimsRootSha256 },
    recipes: claims.map((item) => item.recipe),
  },
  exactSet: { endpoints: 6, intervalsPerEndpoint: 2, claims: 12, replaySides: 2, exactReplays: 24, representedSubcanonicalLengths: 2868 },
  semanticPreservation: {
    tailIntervalsUnchanged: true,
    tailContentsUnconstrained: true,
    calldataExpressionUnchanged: true,
    finalizeBlockTargetUnchanged: true,
    revertAndEmptyOutputTargetUnchanged: true,
    fullCancunFrame: true,
    wholeAccountsRewrite: true,
    addedFacts: "Only fixed selector-byte equalities plus original and resumed G0 sufficiency facts entailed by each preserved bounded interval.",
    claimTargetWeakened: false,
    intervalNarrowed: false,
    productPremiseAdded: false
  },
  parseStatus: "NOT_RUN_AFTER_FINAL_REGENERATION",
  proofStatus: "NOT_RUN",
  closureStatus: "OPEN",
  proofCredit: false,
  centralCredit: false,
};
const contractText = render(contract);
const files = [
  ...claims.map((item) => ({ path: path.join(repositoryRoot, ...item.claim.path.split("/")), content: item.source })),
  { path: indexPath, content: indexText },
  { path: contractPath, content: contractText },
];

const plan = files.map((item) => {
  const actual = fs.existsSync(item.path) ? fs.readFileSync(item.path, "utf8").replaceAll("\r\n", "\n") : null;
  return { path: posix(item.path), status: actual === item.content ? "UNCHANGED" : actual === null ? "MISSING" : "CHANGED", actualSha256: actual === null ? null : sha256(actual), expectedSha256: sha256(item.content) };
});
if (writeMode) {
  for (const item of files) {
    fs.mkdirSync(path.dirname(item.path), { recursive: true });
    fs.writeFileSync(item.path, item.content, "utf8");
  }
} else if (checkMode) {
  const stale = plan.filter((item) => item.status !== "UNCHANGED");
  assert.deepEqual(stale, [], `stale final symbolic descendants: ${stale.map((item) => item.path).join(", ")}`);
}

console.log(JSON.stringify({
  status: writeMode ? "MATERIALIZED_STATIC_ONLY" : checkMode ? "PASS_OPEN_STATIC" : "PASS_GENERATION_PLAN",
  mode: writeMode ? "write" : checkMode ? "check" : "plan",
  files: files.length,
  claims: claims.length,
  exactReplays: 24,
  representedSubcanonicalLengths: 2868,
  claimsRootSha256,
  changes: planMode ? { changed: plan.filter((item) => item.status === "CHANGED").length, missing: plan.filter((item) => item.status === "MISSING").length, unchanged: plan.filter((item) => item.status === "UNCHANGED").length, files: plan } : undefined,
  parseStatus: index.parseStatus,
  proofStatus: index.proofStatus,
  centralCredit: index.centralCredit,
}, null, 2));
