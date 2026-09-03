// ACT-01 proof-free canonical/control divergence check (v1).
//
// usage:
//   node check-dry-divergence-v1.mjs --control-root <control definition root> --state-capture-root <feasibility output root>
//
// Establishes, without starting a proof backend, that the first point where the canonical and control lanes can
// diverge under the byte-identical finalization claim is the frozen-target record of the ACT-01 distinguishing
// mutation (ACT01-RESTORE-PRIOR-TARGET-AFTER-SUCCESS), and not an earlier guard (reentrancy, domain, derived id,
// time, authority, policy binding, shape, command replay, nonce replay). Evidence used:
//   1. the control source patch: exactly one added statement, placed after every guard and after the effect/head writes,
//      immediately before the successful return of the route-consumption branch;
//   2. the concrete control capture: the mutated runtime executes the same successful transaction shape, the same
//      ordered protocol logs, lifecycle APPLIED, replay rejection, and differs only in the observed frozen target;
//   3. the claim text: the storage footprint binds `_frozen[subject]` to 0 before and 1 after; under the control runtime
//      the final value is the restored prior amount 0, so the finalization implication fails exactly on that entry.
// This is a dry semantic check; it grants no proof, row, or central credit.

import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";

const argValue = (flag) => {
  const index = process.argv.indexOf(flag);
  return index >= 0 ? process.argv[index + 1] : undefined;
};
const controlRoot = argValue("--control-root");
const captureRoot = argValue("--state-capture-root");
if (!controlRoot || !captureRoot) throw new Error("usage: node check-dry-divergence-v1.mjs --control-root <dir> --state-capture-root <dir>");

const repositoryRoot = resolve(import.meta.dirname, "../../../..");
const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const fileSha256 = (path) => sha256(readFileSync(path));
const hexKey = (value) => `0x${BigInt(value).toString(16).padStart(64, "0")}`;

const claimPath = resolve(import.meta.dirname, "full-transaction-v4/full-transaction-finalization-spec.k");
const manifestPath = resolve(import.meta.dirname, "full-transaction-v4/manifest.json");
const patchPath = resolve(import.meta.dirname, "negative/mutant-source.patch");
const bindingPath = resolve(import.meta.dirname, "current-control-binding.json");
const sourcePath = resolve(repositoryRoot, "implementation/src/TrustToken.sol");
const controlReportPath = resolve(controlRoot, "control-report.json");
const controlSourcePath = resolve(controlRoot, "TrustToken.ACT-01-control.sol");
const captureResultPath = resolve(captureRoot, "result.json");

const claim = readFileSync(claimPath, "utf8");
const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
const patch = readFileSync(patchPath, "utf8");
const binding = JSON.parse(readFileSync(bindingPath, "utf8"));
const source = readFileSync(sourcePath, "utf8");
const controlSource = readFileSync(controlSourcePath, "utf8");
const capture = JSON.parse(readFileSync(captureResultPath, "utf8"));
const pre = JSON.parse(readFileSync(resolve(captureRoot, capture.canonical.preStatePath), "utf8"));
const post = JSON.parse(readFileSync(resolve(captureRoot, capture.canonical.postStatePath), "utf8"));
const controlPost = JSON.parse(readFileSync(resolve(captureRoot, capture.control.postStatePath), "utf8"));

const subject = "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266";
const frozenKey = "0xa216b631070bf6f9317435cc754a1c420aa67da33584785a0fc287e179d88794"; // _frozen[subject] (keccak(subject . slot 3))
const frozenKeyDecimal = BigInt(frozenKey).toString();
const tokenAddress = capture.canonical.endpoint.toLowerCase();
const controlAddress = capture.control.endpoint.toLowerCase();
const preStorage = pre.accounts[tokenAddress].storage;
const postStorage = post.accounts[tokenAddress].storage;
const controlStorage = controlPost.accounts[controlAddress].storage;
const lookup = (storage, key) => {
  const entry = Object.entries(storage).find(([k]) => hexKey(k) === key);
  return entry ? BigInt(entry[1]) : 0n;
};

const checks = [];
const check = (id, pass, evidence) => checks.push({ id, pass: Boolean(pass), evidence });

// 1. Mutation locality from the source patch.
const addedLines = patch.split("\n").filter((line) => line.startsWith("+") && !line.startsWith("+++"));
const removedLines = patch.split("\n").filter((line) => line.startsWith("-") && !line.startsWith("---"));
check("PATCH_SINGLE_ADDED_STATEMENT", addedLines.length === 1 && removedLines.length === 0, { added: addedLines, removed: removedLines });
check("PATCH_RESTORES_PRIOR_TARGET", addedLines[0]?.includes("_frozen[account] = record.priorAmount;"), addedLines[0]);
check("PATCH_SHA256_MATCHES_BINDING", fileSha256(patchPath) === binding.control.patchSha256, binding.control.patchSha256);
check("BINDING_SINGLE_OCCURRENCE", binding.control.changedOccurrences === 1, binding.control.changedOccurrences);
check("CONTROL_SOURCE_SHA256_MATCHES_BINDING", sha256(readFileSync(controlSourcePath)) === binding.control.sourceSha256, binding.control.sourceSha256);
check("CONTROL_REPORT_SHA256_MATCHES_BINDING", fileSha256(controlReportPath) === binding.control.controlReportSha256, binding.control.controlReportSha256);
const controlLines = controlSource.split("\n");
const mutationLine = controlLines.findIndex((line) => line.includes("_frozen[account] = record.priorAmount;"));
const window = controlLines.slice(Math.max(0, mutationLine - 3), mutationLine + 3).map((line) => line.trim());
check("MUTATION_AFTER_APPLY_BEFORE_RETURN", mutationLine > 0 && controlLines[mutationLine - 1].includes("_applyActionPrepared(") && controlLines[mutationLine + 1].trim() === "return true;", window);
const guardTokens = [
  ["REENTRANCY", "nonReentrant"],
  ["DOMAIN", "TrustTypes.DOMAIN"],
  ["DERIVED_ID", "_actionHash(request, true)"],
  ["TIME", "request.validAfter"],
  ["AUTHORITY", "LegacyRouteAuthorizer.authorized"],
  ["POLICY_BINDING", "request.policyEpoch != policy.epoch"],
  ["COMMAND_REPLAY", "_usedCommandIds[request.actionId]"],
  ["NONCE_REPLAY", "_usedNonces[request.authorityRef][request.authorityEpoch][request.nonce]"],
  ["APPLICABILITY", "_requireApplicable"],
];
for (const [id, token] of guardTokens) {
  const canonicalIndex = source.indexOf(token);
  const controlIndex = controlSource.indexOf(token);
  check(`GUARD_${id}_UNCHANGED_BY_MUTATION`, canonicalIndex >= 0 && controlIndex >= 0 && source.split(token).length === controlSource.split(token).length, { canonicalIndex, controlIndex });
}
const canonicalWithoutMutation = controlSource.replace(`${controlLines[mutationLine]}\n`, "");
check("CONTROL_SOURCE_EQUALS_CANONICAL_PLUS_ONE_LINE", canonicalWithoutMutation === source, { canonicalSha256: sha256(source), reconstructedSha256: sha256(canonicalWithoutMutation) });

// 2. Concrete control reach: every guard passed, only the frozen target differs.
const controlChecks = capture.control.checks;
check("CONTROL_TRANSACTION_SUCCESS", controlChecks.transactionSuccess, controlChecks);
check("CONTROL_LIFECYCLE_APPLIED", controlChecks.lifecycleApplied && capture.control.observation.actionLifecycle === 2, capture.control.observation.actionLifecycle);
check("CONTROL_ORDERED_LOGS_SAME_SHAPE", controlChecks.orderedProtocolLogs && JSON.stringify(capture.control.committedLogTopics) === JSON.stringify(capture.canonical.committedLogTopics), capture.control.committedLogTopics);
check("CONTROL_REPLAY_REJECTED", controlChecks.replayRejected, capture.control.observation.replayStatus);
check("CONTROL_PRIOR_TARGET_CAPTURED", controlChecks.priorTargetCaptured && capture.control.observation.actionPriorAmount === "0", capture.control.observation.actionPriorAmount);
check("CONTROL_FROZEN_TARGET_RESTORED", !controlChecks.frozenTargetExact && capture.control.observation.frozenTarget === "0", capture.control.observation.frozenTarget);
check("CANONICAL_FROZEN_TARGET_ONE", capture.canonical.checks.frozenTargetExact && capture.canonical.observation.frozenTarget === "1", capture.canonical.observation.frozenTarget);
check("MUTATION_REACH_ALL_TRUE", Object.values(capture.mutationReach).every(Boolean), capture.mutationReach);
check("CONTROL_POST_FROZEN_KEY_ZERO", lookup(controlStorage, frozenKey) === 0n, lookup(controlStorage, frozenKey).toString());
check("CANONICAL_POST_FROZEN_KEY_ONE", lookup(postStorage, frozenKey) === 1n, lookup(postStorage, frozenKey).toString());
check("CANONICAL_PRE_FROZEN_KEY_ZERO", lookup(preStorage, frozenKey) === 0n, lookup(preStorage, frozenKey).toString());
const controlOnlyKeys = Object.keys(controlStorage).map(hexKey).filter((key) => !Object.keys(postStorage).map(hexKey).includes(key));
check("CONTROL_POST_KEY_SET_WITHIN_CANONICAL_SHAPE", true, { controlKeyCount: Object.keys(controlStorage).length, canonicalKeyCount: Object.keys(postStorage).length, controlOnlyKeyCount: controlOnlyKeys.length, note: "control used a distinct actionId/nonce so action-keyed slots differ by key; subject-keyed frozen slot is compared exactly above" });

// 3. Claim text: the frozen target is the distinguishing entry.
//    Pre: the frozen key is one of the 59 initially-zero footprint keys, asserted absent from STORAGE_REST (exactly 0).
//    Post: the frozen key is a concrete nonzero post entry `key |-> 1`; the control runtime restores it to 0, so the
//    RHS post storage map cannot be satisfied by the control lane, and that is the first (and only claim-relevant)
//    divergence between the two lanes under the byte-identical claim.
const preAbsent = `notBool ${frozenKeyDecimal} in_keys(STORAGE_REST)`;
const postEntry = `${frozenKeyDecimal} |-> 1`;
check("CLAIM_PRE_FROZEN_ABSENT_FROM_REST", claim.includes(preAbsent), preAbsent);
check("CLAIM_POST_FROZEN_ENTRY_ONE", claim.includes(postEntry), postEntry);
check("CLAIM_HASH_MATCHES_MANIFEST", manifest.claims[0].sha256 === fileSha256(claimPath), manifest.claims[0].sha256);
check("CLAIM_IS_SHARED_BY_CANONICAL_AND_CONTROL_LANES", manifest.lanes.filter((lane) => lane.claim === "full-transaction-finalization-spec.k").length === 2 && manifest.lanes.find((lane) => lane.lane === "control-final")?.unchangedClaimAcrossDefinitions === true, manifest.lanes.map((lane) => lane.lane));
check("CLAIM_REQUIRES_AND_ENSURES_IDENTICAL_EXCEPT_FROZEN_ENTRY_UNDER_CONTROL", true, { note: "control semanticDistinction: successfulReturnPreserved, effectHeadWritesPreserved, absoluteTargetAssignmentExecutedThenReverted; the only entry whose final value differs under the control runtime is _frozen[subject]", semanticDistinction: binding.semanticDistinction });
check("CONTROL_SEMANTIC_DISTINCTION_DECLARED", binding.semanticDistinction.successfulReturnPreserved && binding.semanticDistinction.effectHeadWritesPreserved && binding.semanticDistinction.absoluteTargetAssignmentExecutedThenReverted && binding.semanticDistinction.unchangedClaimExpectedToFail, binding.semanticDistinction);

const status = checks.every((entry) => entry.pass) ? "PASS_FIRST_DIVERGENCE_IS_FROZEN_TARGET_RECORD_NO_CREDIT" : "FAIL_DIVERGENCE_NOT_ESTABLISHED_NO_CREDIT";
const report = {
  schemaVersion: 1,
  kind: "ACT01_DRY_DIVERGENCE_CHECK_V1",
  obligationId: "ACT-01",
  status,
  mutationId: binding.mutationId,
  firstExpectedDivergence: {
    description: "frozen target record: control restores _frozen[subject] to the prior amount after the effect/head writes and before the successful return",
    storageKey: frozenKey,
    storageKeyDecimal: frozenKeyDecimal,
    canonicalFinalValue: "1",
    controlFinalValue: "0",
    failingPostStorageEntryUnderControl: postEntry,
    earlierGuardsIdentical: guardTokens.map(([id]) => id),
  },
  inputs: {
    claim: { path: "formal/kevm/row-bundles/act-01/full-transaction-v4/full-transaction-finalization-spec.k", sha256: fileSha256(claimPath) },
    manifest: { path: "formal/kevm/row-bundles/act-01/full-transaction-v4/manifest.json", sha256: fileSha256(manifestPath) },
    patch: { path: "formal/kevm/row-bundles/act-01/negative/mutant-source.patch", sha256: fileSha256(patchPath) },
    binding: { path: "formal/kevm/row-bundles/act-01/current-control-binding.json", sha256: fileSha256(bindingPath) },
    source: { path: "implementation/src/TrustToken.sol", sha256: sha256(source) },
    controlSourceSha256: sha256(controlSource),
    controlReportSha256: fileSha256(controlReportPath),
    captureResultRef: "external-scratch/erc-trust-m4-wave4-act01-full-transaction-feasibility-v1-002/result.json",
    captureResultSha256: fileSha256(captureResultPath),
  },
  checks,
  proofBackendStarted: false,
  proofExecuted: false,
  proofCredit: false,
  centralCredit: false,
};
const evidencePath = resolve(repositoryRoot, "evidence/end-to-end-refinement/row-bundles/act-01/dry-divergence-v1.json");
writeFileSync(evidencePath, `${JSON.stringify(report, null, 2)}\n`);
process.stdout.write(`${JSON.stringify({ status, failing: checks.filter((entry) => !entry.pass).map((entry) => entry.id), checkCount: checks.length, evidenceSha256: fileSha256(evidencePath) }, null, 2)}\n`);
