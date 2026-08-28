#!/usr/bin/env node
// Independent static reverse check for the S1 v4 runner and immutable wave
// contract. It executes no KEVM command and grants no proof credit.
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const familyDir = path.dirname(fileURLToPath(import.meta.url));
const rowDir = path.dirname(familyDir);
const repositoryRoot = path.resolve(rowDir, "../../../..");
const readJson = (filePath) => JSON.parse(fs.readFileSync(filePath, "utf8"));
const sha256 = (value) => crypto.createHash("sha256").update(value).digest("hex");
const fileSha256 = (filePath) => sha256(fs.readFileSync(filePath));
const count = (source, fragment) => source.split(fragment).length - 1;
const windowsPath = (wslPath) => wslPath.replace("/mnt/c/", "C:\\").replaceAll("/", "\\");
const hostPath = (declaredPath) => process.platform === "win32" ? windowsPath(declaredPath) : declaredPath;

const runnerPath = path.join(familyDir, "run-dynamic-offset-leaf-v4.sh");
const launcherContractPath = path.join(familyDir, "dynamic-offset-leaf-v4-contract.json");
const waveContractPath = path.join(familyDir, "s1-dynamic-offset-wave-contract-v1.json");
const replayIndexPath = path.join(familyDir, "remaining-leaves-replay-index-v2.json");
const claimsIndexPath = path.join(familyDir, "claims-index-v1.json");
const dependencyLockPath = path.join(repositoryRoot, "formal", "kevm", "dependencies.lock.json");
const closureFreezeVerifierPath = path.join(rowDir, "anti-drift", "verify-freeze-receipt.py");
const waveCoordinatorPath = path.join(familyDir, "run-dynamic-offset-wave-v1.mjs");
const analysisToolPath = path.join(familyDir, "analyze-dynamic-offset-replay-v1.mjs");
const independentVerifierPath = path.join(familyDir, "verify-dynamic-offset-replay-v1.py");
const pairBinderPath = path.join(familyDir, "bind-dynamic-offset-wave-v1.mjs");
const waveReverseCheckPath = path.join(familyDir, "reverse-check-dynamic-offset-wave-v1.mjs");
const matrixPath = path.join(rowDir, "case-matrix.json");
const canonicalExpectedPath = path.join(familyDir, "expected-graphs", "native-regulatory-action-canonical-positive-v1.json");
const mutantExpectedPath = path.join(familyDir, "expected-graphs", "native-regulatory-action-mutant-negative-v1.json");
const nativeErc7943CanonicalExpectedPath = path.join(familyDir, "expected-graphs", "native-erc7943-action-canonical-positive-v1.json");
const nativeErc7943MutantExpectedPath = path.join(familyDir, "expected-graphs", "native-erc7943-action-mutant-negative-v1.json");
const profileCanonicalExpectedPath = path.join(familyDir, "expected-graphs", "profile-regulatory-action-canonical-positive-v1.json");
const profileMutantExpectedPath = path.join(familyDir, "expected-graphs", "profile-regulatory-action-mutant-negative-v1.json");
const nativeRegulatoryReversalCanonicalExpectedPath = path.join(familyDir, "expected-graphs", "native-regulatory-reversal-canonical-positive-v1.json");
const nativeRegulatoryReversalMutantExpectedPath = path.join(familyDir, "expected-graphs", "native-regulatory-reversal-mutant-negative-v1.json");
const nativeErc7943ReversalCanonicalExpectedPath = path.join(familyDir, "expected-graphs", "native-erc7943-reversal-canonical-positive-v1.json");
const nativeErc7943ReversalMutantExpectedPath = path.join(familyDir, "expected-graphs", "native-erc7943-reversal-mutant-negative-v1.json");
const profileReversalCanonicalExpectedPath = path.join(familyDir, "expected-graphs", "profile-regulatory-reversal-canonical-positive-v1.json");
const profileReversalMutantExpectedPath = path.join(familyDir, "expected-graphs", "profile-regulatory-reversal-mutant-negative-v1.json");

const runner = fs.readFileSync(runnerPath, "utf8").replaceAll("\r\n", "\n");
const analysisTool = fs.readFileSync(analysisToolPath, "utf8").replaceAll("\r\n", "\n");
const independentVerifier = fs.readFileSync(independentVerifierPath, "utf8").replaceAll("\r\n", "\n");
const launcherContract = readJson(launcherContractPath);
const wave = readJson(waveContractPath);
const replayIndex = readJson(replayIndexPath);
const index = readJson(claimsIndexPath);
const lock = readJson(dependencyLockPath);
const matrix = readJson(matrixPath);
const closureFreezeVerifier = fs.readFileSync(closureFreezeVerifierPath, "utf8").replaceAll("\r\n", "\n");
const waveCoordinator = fs.readFileSync(waveCoordinatorPath, "utf8").replaceAll("\r\n", "\n");
const pairBinder = fs.readFileSync(pairBinderPath, "utf8").replaceAll("\r\n", "\n");
const waveReverseCheck = fs.readFileSync(waveReverseCheckPath, "utf8").replaceAll("\r\n", "\n");
checkWaveSourceInvariants();
if (process.argv.includes("--source-only")) {
  console.log(JSON.stringify({
    status: "PASS_WAVE_SOURCE_INVARIANTS_ONLY_NO_PROOF_CREDIT",
    waveCoordinatorSha256: fileSha256(waveCoordinatorPath),
    pairBinderSha256: fileSha256(pairBinderPath),
    waveReverseCheckSha256: fileSha256(waveReverseCheckPath),
    heavyProofExecuted: false,
    proofCredit: false,
    centralCredit: false,
  }, null, 2));
  process.exit(0);
}

assert.equal(launcherContract.contractId, "ABI04-DYNAMIC-OFFSET-LEAF-V4");
assert.equal(launcherContract.stage, "S1");
assert.equal(launcherContract.requirements.freshOutputRoot, true);
assert.equal(launcherContract.requirements.preRunExpectedGraphContract, true);
assert.equal(launcherContract.requirements.exactExpectedGraphContracts, 12);
assert.equal(launcherContract.requirements.expectedGraphIncludedInImmutableSnapshot, true);
assert.equal(launcherContract.requirements.expectedGraphSnapshotHashMatch, true);
assert.equal(launcherContract.requirements.immutableInputSnapshotBeforeProof, true);
assert.equal(launcherContract.requirements.analysisToolsIncludedInImmutableSnapshot, true);
assert.equal(launcherContract.requirements.analysisToolsPreAndPostHashMatch, true);
assert.equal(launcherContract.requirements.priorAuthoritativePairBindersIncludedInImmutableSnapshot, false);
assert.equal(launcherContract.requirements.passClosureFreezeReceiptRequired, true);
assert.equal(launcherContract.requirements.closureFreezeExactScopeRecalculatedBeforeAndAfter, true);
assert.equal(launcherContract.requirements.closureFreezeIncludedInImmutableSnapshot, true);
assert.equal(launcherContract.requirements.externalDefinitionPreAndPostHashMatch, true);
assert.equal(launcherContract.requirements.actualChildPidSidPgidRecorded, true);
assert.equal(launcherContract.requirements.ownedSessionTerminationOnSignal, true);
assert.equal(launcherContract.requirements.postRunOwnedSessionSurvivors, 0);
assert.equal(launcherContract.requirements.separateProofAndLauncherExitRecords, true);
assert.equal(launcherContract.requirements.timeoutCancelLauncherErrorCredit, 0);
assert.equal(launcherContract.requirements.exactWaveCoordinatorRequired, true);
assert.equal(launcherContract.requirements.maxConcurrentHeavyProofs, 2);
assert.equal(launcherContract.requirements.jsAnalysisPerReplayRequired, true);
assert.equal(launcherContract.requirements.independentPythonVerificationPerReplayRequired, true);
assert.equal(launcherContract.requirements.exactSixPairBinderSetRequired, true);
assert.equal(launcherContract.requirements.postWaveIndependentReverseCheckRequired, true);

assert.equal(wave.contractId, "ABI04-DYNAMIC-OFFSET-S1-WAVE-V1");
assert.equal(wave.obligationId, "ABI-04");
assert.equal(wave.classification, "LEAF_EVIDENCE_CONTRACT_NOT_CENTRAL_DISCHARGE");
assert.equal(wave.centralBindingAllowed, false);
assert.equal(wave.rowDispositionAfterSuccessfulWave, "OPEN_PENDING_DYNAMIC_LENGTH_HIGH_BITS_SYMBOLIC_162_AGGREGATE_ISABELLE_INDEPENDENT");
assert.equal(wave.schedule, "CANCUN");
assert.equal(wave.exactReplayCount, 12);
assert.equal(wave.leaves.length, 6);
assert.equal(wave.progress.status, "CALIBRATION_FROZEN_5_OF_6_CREDIT_0");
assert.equal(wave.progress.calibrationLeafPairsObserved, 5);
assert.equal(wave.progress.authoritativeLeafPairsPassed, 0);
assert.equal(wave.progress.remainingFreshLeafPairs, 6);
assert.equal(wave.progress.centralBindingAllowed, false);
assert.deepEqual(wave.progress.pairBinders, []);
assert.equal(wave.progress.proofCredit, false);
assert.equal(new Set(wave.leaves.map(({ claimId }) => claimId)).size, 6);
assert.equal(wave.caseMatrix.fileSha256, fileSha256(matrixPath));
assert.equal(wave.caseMatrix.caseMatrixRootSha256, matrix.caseMatrixRootSha256);
assert.equal(wave.claims.indexSha256, fileSha256(claimsIndexPath));
assert.equal(wave.claims.sixClaimRootSha256, index.claimsRootSha256);
assert.equal(wave.sourceBinding.replayIndex.sha256, fileSha256(replayIndexPath));
for (const [name, sourcePath] of [
  ["waveCoordinator", waveCoordinatorPath],
  ["analysisTool", analysisToolPath],
  ["independentVerifier", independentVerifierPath],
  ["pairBinder", pairBinderPath],
  ["waveReverseCheck", waveReverseCheckPath],
]) {
  assert.equal(wave.sourceBinding[name].path, path.relative(repositoryRoot, sourcePath).split(path.sep).join("/"));
  assert.equal(wave.sourceBinding[name].sha256, fileSha256(sourcePath));
  assert.deepEqual(replayIndex.sourceBinding[name], wave.sourceBinding[name]);
}
assert.equal(replayIndex.kind, "ABI04_DYNAMIC_OFFSET_EXACT_REPLAY_INDEX");
assert.equal(replayIndex.exactClaimCount, 6);
assert.equal(replayIndex.exactReplayCount, 12);
assert.equal(replayIndex.claims.length, 6);
assert.deepEqual(wave.coordinator, replayIndex.coordinator);
assert.equal(wave.coordinator.exactReplayPlanFromFrozenIndex, true);
assert.equal(wave.coordinator.exactReplayCount, 12);
assert.equal(wave.coordinator.exactPairCount, 6);
assert.equal(wave.coordinator.maxConcurrentHeavyProofs, 2);
assert.equal(wave.coordinator.failClosedOnAnyReplayOrVerifierFailure, true);
assert.equal(wave.coordinator.jsAnalysisAndIndependentPythonRequired, true);
assert.equal(wave.coordinator.pairBindingOnlyAfterAllTwelvePass, true);
assert.equal(wave.coordinator.independentPostWaveReverseCheckRequired, true);
assert.equal(wave.coordinator.s1CreditBoundary, "S1_DYNAMIC_OFFSET_6_OF_6_ONLY");
assert.equal(wave.coordinator.centralCredit, false);
function checkWaveSourceInvariants() {
for (const token of [
  'maxHeavy >= 1 && maxHeavy <= 2',
  'use exactly one of --plan, --preflight, or --run',
  'PASS_NO_HEAVY_PROOF_EXECUTED',
  'exactReplayPrintChecks',
  'import jsonschema',
  'toolchainContract',
  'Node executable pin mismatch',
  'Python binary hash mismatch',
  'toolchain contract target hash mismatch',
  'assert.equal(fs.existsSync(outputRoot), false',
  'assert.equal(fs.realpathSync(closureRoot), closureRoot',
  'assert.equal(overlaps(repositoryRoot, outputRoot)',
  'assert.equal(overlaps(closureRoot, outputRoot)',
  'process.kill(-pid, signal)',
  'terminateActive("SIGKILL")',
  'analysis-js.json',
  'analysis-python.json',
  'PASS_EXACT_GRAPH_JS_PYTHON',
  'assert.deepEqual(closureAfter, closureBefore',
  'closure DAG hash changed during wave',
  'closure worker-result changed during wave',
  'pair-binder-generation.stdout.json',
  'wave-reverse-check-v1.json',
  'invalidatedDescendants',
  'S1_DYNAMIC_OFFSET_6_OF_6_ONLY',
  'OPEN_PENDING_DYNAMIC_LENGTH_HIGH_BITS_SYMBOLIC_162_AGGREGATE_ISABELLE_INDEPENDENT',
]) assert.ok(waveCoordinator.includes(token), `wave coordinator invariant missing: ${token}`);
assert.equal(count(waveCoordinator, "await requireClosurePass("), 3);
assert.ok(count(waveCoordinator, "detached: true") >= 5, "wave child process groups are not isolated");
assert.ok(count(waveCoordinator, "centralCredit: false") >= 3, "wave central-credit boundary missing");
assert.equal(count(waveCoordinator, "if (!failure) {"), 1, "wave first-failure preservation guard missing");
assert.equal(count(waveCoordinator, "failure = error;"), 1, "wave failure assignment must occur exactly once behind the preservation guard");

for (const token of [
  'PASS_12_OF_12_EXACT_REPLAY_JS_PYTHON_CREDIT_BOUNDARY_S1_ONLY',
  'assert.deepEqual(replayResult.replayIds, expectedReplays.map',
  'assert.equal(new Set(replayResult.replayIds).size, 12)',
  'analysisJs',
  'analysisPython',
  'binder JS reanalysis',
  'binder Python reverification',
  'binder live closure verification',
  'assert.deepEqual(replayedJs, js.json',
  'assert.deepEqual(replayedPy, py.json',
  'positiveEqualsNegative: true',
  'incomplete: 0',
  'EVMC_SUCCESS_NETWORK_EndStatusCode',
  'outputToken, \'b""\'',
  'pair binder file exact set mismatch',
  'S1_DYNAMIC_OFFSET_PAIR_ONLY',
  'PASS_S1_6_OF_6_PAIR_CREDIT_ROW_OPEN',
]) assert.ok(pairBinder.includes(token), `pair binder invariant missing: ${token}`);
assert.ok(count(pairBinder, "centralCredit: false") >= 3, "pair binder central-credit boundary missing");

for (const token of [
  'runJson(process.execPath, [analyzerPath',
  'runJson(args.python, [verifierPath',
  'pair binder deterministic check',
  'replay output-root exact set mismatch',
  'pair binder file exact set mismatch',
  'live closure tree differs from wave freeze',
  'nonzero closure ${key}',
  'S1_DYNAMIC_OFFSET_6_OF_6_ONLY',
  'centralCredit: false',
]) assert.ok(waveReverseCheck.includes(token), `wave reverse-check invariant missing: ${token}`);
}
assert.deepEqual(wave.leaves.map(({ claimId }) => claimId).sort(), index.claims.map(({ claimId }) => claimId).sort());

for (const leaf of wave.leaves) {
  const claim = index.claims.find(({ claimId }) => claimId === leaf.claimId);
  const replayLeaf = replayIndex.claims.find(({ claimId }) => claimId === leaf.claimId);
  assert.ok(claim, `missing indexed claim: ${leaf.claimId}`);
  assert.ok(replayLeaf, `missing replay-index claim: ${leaf.claimId}`);
  assert.equal(leaf.endpointId, claim.endpointId);
  assert.equal(leaf.selector, claim.selector);
  assert.equal(leaf.sourceClaimSha256, claim.claim.sha256);
  assert.equal(leaf.calldataSha256, claim.calldataSha256);
  const claimPath = path.join(repositoryRoot, ...claim.claim.path.split("/"));
  const source = fs.readFileSync(claimPath, "utf8").replaceAll("\r\n", "\n");
  assert.equal(source.split("\n")[0], 'requires "../../../trust-runtime-verification.k"');
  const stripped = source.split("\n").slice(1).join("\n");
  assert.equal(fileSha256(claimPath), leaf.sourceClaimSha256);
  assert.equal(sha256(stripped), leaf.strippedClaimSha256);
  assert.equal(count(runner, `${leaf.claimId})`), 1);
  assert.equal(count(runner, `expected_source_sha256=${leaf.sourceClaimSha256}`), 1);
  assert.equal(count(runner, `expected_stripped_sha256=${leaf.strippedClaimSha256}`), 1);
  assert.equal(leaf.freshOutputRoot, null);
  assert.equal(leaf.replayStatus, "NOT_RUN_AFTER_CLOSURE_FREEZE");
  assert.equal(replayLeaf.canonicalPositive.replayId, `${leaf.claimId}::canonical-positive`);
  assert.equal(replayLeaf.canonicalPositive.runnerSide, "canonical-positive");
  assert.equal(replayLeaf.unchangedClaimMutantNegative.replayId, `${leaf.claimId}::unchanged-claim-mutant-negative`);
  assert.equal(replayLeaf.unchangedClaimMutantNegative.runnerSide, "mutant-negative");
  assert.equal(replayLeaf.unchangedClaimMutantNegative.claimSourceUnchanged, true);
}

assert.equal(wave.toolchain.dependencyLockSha256, fileSha256(dependencyLockPath));
assert.equal(wave.toolchain.kevmSemantics.tag, lock.components.kevmSemantics.tag);
assert.equal(wave.toolchain.kevmSemantics.commit, lock.components.kevmSemantics.commit);
assert.equal(wave.toolchain.kevmSemantics.sourceStorePath, lock.components.kevmSemantics.sourceStorePath);
assert.equal(wave.toolchain.kevmSemantics.sourceNarHash, lock.components.kevmSemantics.sourceNarHash);
assert.equal(wave.toolchain.kevmSemantics.compiledStorePath, lock.components.kevmSemantics.compiledStorePath);
assert.equal(wave.toolchain.kevmSemantics.compiledNarHash, lock.components.kevmSemantics.compiledNarHash);
assert.equal(wave.toolchain.kevmDriver.wheelVersion, lock.components.kevmDriver.wheelVersion);
assert.equal(wave.toolchain.kevmDriver.reportedCliVersion, lock.components.kevmDriver.reportedCliVersion);
assert.equal(wave.toolchain.kFramework.version, lock.components.kFramework.version);
assert.equal(wave.toolchain.kFramework.commit, lock.components.kFramework.commit);
assert.equal(wave.toolchain.koreRpc.version, lock.components.kore.version);
assert.equal(wave.toolchain.koreRpc.commit, lock.components.kore.commit);
assert.equal(wave.executionPolicy.workersPerReplay, 1);
assert.equal(wave.executionPolicy.maxConcurrentHeavyProofs, 2);
assert.equal(wave.executionPolicy.boosterEnabled, false);
assert.equal(wave.executionPolicy.forceSequential, true);
assert.equal(wave.executionPolicy.maxDepth, 1);
assert.equal(wave.executionPolicy.timeoutSeconds, 7200);
assert.equal(wave.executionPolicy.terminationGraceSeconds, 30);
assert.equal(wave.executionPolicy.timeoutCancelLauncherErrorCredit, 0);

for (const definition of Object.values(wave.definitions).filter((value) => value && typeof value === "object" && "root" in value)) {
  const root = hostPath(definition.root);
  assert.equal(fileSha256(path.join(root, "definition.kore")), definition.definitionKoreSha256);
  assert.equal(fileSha256(path.join(root, "compiled.json")), definition.compiledJsonSha256);
}

assert.equal(count(runner, "--no-use-booster"), 1);
assert.equal(count(runner, "--workers 1"), 1);
assert.equal(count(runner, "--force-sequential"), 1);
assert.equal(count(runner, "--max-depth 1"), 1);
assert.equal(count(runner, "setsid --wait timeout --signal=TERM --kill-after=30s 7200"), 1);
assert.equal(count(runner, "child_pid=$!"), 1);
assert.equal(count(runner, 'printf \'%s\\n\' "$child_sid" > "$output_root/child-sid.txt"'), 1);
assert.equal(count(runner, 'printf \'%s\\n\' "$child_pgid" > "$output_root/child-pgid.txt"'), 1);
assert.equal(count(runner, 'kill -TERM -- "-$child_pgid"'), 1);
assert.equal(count(runner, 'kill -KILL -- "-$child_pgid"'), 1);
assert.equal(count(runner, "trap 'on_signal INT 130' INT"), 1);
assert.equal(count(runner, "trap 'on_signal TERM 143' TERM"), 1);
assert.equal(count(runner, "trap 'on_signal HUP 129' HUP"), 1);
assert.equal(count(runner, "post-run-owned-session-survivor-count.txt"), 3);
assert.equal(count(runner, "live-input-hashes-before.sha256"), 7);
assert.equal(count(runner, "live-input-hashes-after.sha256"), 7);
assert.equal(count(analysisTool, 'assert.equal(before.length, 7, "live input hash cardinality mismatch")'), 1);
assert.equal(count(analysisTool, 'path.join(snapshotRoot, "verify-freeze-receipt.py")'), 1);
assert.equal(count(analysisTool, "before[5].sha256"), 1);
assert.equal(count(analysisTool, "before[6].sha256"), 1);
assert.equal(count(independentVerifier, "if prior_pair_binders != []:"), 1);
assert.equal(count(independentVerifier, 'execution.get("priorAuthoritativePairBindersIncluded") is not False'), 1);
assert.equal(count(independentVerifier, "if len(live_lines) != 7:"), 1);
assert.equal(count(independentVerifier, 'sha256(snapshot / "verify-freeze-receipt.py") != live_hashes[4]'), 1);
assert.equal(count(independentVerifier, 'execution.get("definitionKoreSha256") != live_hashes[5]'), 1);
assert.equal(count(independentVerifier, 'execution.get("compiledJsonSha256") != live_hashes[6]'), 1);
assert.equal(count(independentVerifier, "6 + len(prior_pair_binders)"), 0);
assert.equal(count(independentVerifier, "definition_index = 4 + len(prior_pair_binders)"), 0);
assert.equal(count(runner, "pre-proof-closure-verification.json"), 1);
assert.equal(count(runner, "post-proof-closure-verification.json"), 1);
assert.equal(count(runner, 'python3 "$closure_freeze_verifier" --root "$closure_freeze_root" --repository-root "$repo_root" --require-pass'), 2);
assert.equal(count(runner, "closure-freeze-files-before.sha256"), 2);
assert.equal(count(runner, "closure-freeze-files-after.sha256"), 2);
assert.equal(count(runner, "input-integrity-status.txt"), 1);
assert.equal(count(runner, "proof-exit-code.txt"), 5);
assert.equal(count(runner, "exit-code.txt"), 10);
assert.equal(count(runner, "CANCELED_"), 4);
assert.equal(count(runner, "LAUNCHER_BOOTSTRAP_ERROR"), 1);
assert.equal(count(runner, "TIMEOUT_OR_FORCED_TERMINATION"), 1);
assert.equal(count(runner, "tail -n +2 -- \"$source_claim\" > \"$claim_path\""), 1);
for (const requiredFreezeInvariant of [
  "ABI04_DETERMINISTIC_DESCENDANT_GENERATION_RECEIPT",
  "PASS_BYTE_IDENTICAL_CLEAN_SECOND_CHECK",
  "PASS_EXACT_MANAGED_OUTPUT_SET",
  "changedDescendantSetSha256",
  "pass2ChangedDescendants",
  "managedOutputExactSet",
  "generationReceiptSha256",
]) assert.ok(closureFreezeVerifier.includes(requiredFreezeInvariant), `closure freeze verifier missing invariant: ${requiredFreezeInvariant}`);

const expectedGraphs = [
  {
    path: canonicalExpectedPath,
    claimId: "ABI04-native-regulatory-action-dynamic-offset-envelope-v1",
    side: "canonical-positive",
  },
  {
    path: mutantExpectedPath,
    claimId: "ABI04-native-regulatory-action-dynamic-offset-envelope-v1",
    side: "mutant-negative",
  },
  {
    path: nativeErc7943CanonicalExpectedPath,
    claimId: "ABI04-native-erc7943-action-dynamic-offset-envelope-v1",
    side: "canonical-positive",
  },
  {
    path: nativeErc7943MutantExpectedPath,
    claimId: "ABI04-native-erc7943-action-dynamic-offset-envelope-v1",
    side: "mutant-negative",
  },
  {
    path: profileCanonicalExpectedPath,
    claimId: "ABI04-profile-regulatory-action-dynamic-offset-envelope-v1",
    side: "canonical-positive",
  },
  {
    path: profileMutantExpectedPath,
    claimId: "ABI04-profile-regulatory-action-dynamic-offset-envelope-v1",
    side: "mutant-negative",
  },
  {
    path: nativeRegulatoryReversalCanonicalExpectedPath,
    claimId: "ABI04-native-regulatory-reversal-dynamic-offset-envelope-v1",
    side: "canonical-positive",
  },
  {
    path: nativeRegulatoryReversalMutantExpectedPath,
    claimId: "ABI04-native-regulatory-reversal-dynamic-offset-envelope-v1",
    side: "mutant-negative",
  },
  {
    path: nativeErc7943ReversalCanonicalExpectedPath,
    claimId: "ABI04-native-erc7943-reversal-dynamic-offset-envelope-v1",
    side: "canonical-positive",
  },
  {
    path: nativeErc7943ReversalMutantExpectedPath,
    claimId: "ABI04-native-erc7943-reversal-dynamic-offset-envelope-v1",
    side: "mutant-negative",
  },
  {
    path: profileReversalCanonicalExpectedPath,
    claimId: "ABI04-profile-regulatory-reversal-dynamic-offset-envelope-v1",
    side: "canonical-positive",
  },
  {
    path: profileReversalMutantExpectedPath,
    claimId: "ABI04-profile-regulatory-reversal-dynamic-offset-envelope-v1",
    side: "mutant-negative",
  },
];
for (const item of expectedGraphs) {
  const contract = readJson(item.path);
  const digest = fileSha256(item.path);
  const waveBinding = wave.expectedGraphSet.graphs.find((binding) => binding.claimId === item.claimId && binding.side === item.side);
  assert.ok(waveBinding, `${item.claimId}::${item.side}: wave graph binding`);
  assert.equal(contract.kind, "ABI04_DYNAMIC_OFFSET_PRE_RUN_EXACT_GRAPH_CONTRACT");
  assert.equal(contract.claimId, item.claimId);
  assert.equal(contract.side, item.side);
  assert.equal(waveBinding.sha256, digest);
  assert.equal(contract.processExitCode, item.side === "canonical-positive" ? 0 : 1);
  assert.equal(contract.launcherExitCode, item.side === "canonical-positive" ? 0 : 1);
  assert.equal(contract.graph.pending, 0);
  assert.equal(contract.graph.admitted, false);
  assert.equal(contract.calibration.proofCredit, false);
  assert.equal(contract.calibration.sourcePathNormalization.status, "BYTE_IDENTICAL_AFTER_FIRST_REQUIRES_LINE");
  assert.equal(contract.calibration.sourcePathNormalization.semanticClaimBodyChanged, false);
  assert.equal(contract.calibration.sourcePathNormalization.proofRootReused, false);
  assert.ok(runner.includes(`expected_graph_sha256=${digest}`));
}
assert.equal(count(runner, 'require_hash "$expected_graph" "$expected_graph_sha256"'), 1);
assert.equal(count(runner, 'cp -- "$expected_graph" "$snapshot_directory/expected-graph-contract.json"'), 1);
assert.equal(count(runner, '"expectedGraphSha256": "$expected_graph_sha256"'), 1);
assert.equal(expectedGraphs.length, 12);
assert.equal(new Set(expectedGraphs.map((item) => `${item.claimId}::${item.side}`)).size, 12);

const requiredSnapshotNames = [
  "launcher.sh",
  "claim-source.k",
  "expected-graph-contract.json",
  "case-matrix.json",
  "claims-index-v1.json",
  "dynamic-offset-family-v1-contract.json",
  "remaining-leaves-replay-index-v2.json",
  "s1-dynamic-offset-wave-contract-v1.json",
  "dynamic-offset-leaf-v4-contract.json",
  "executable-mutant-contract-v1.json",
  "dynamic-offset-leaf-mutant-control-v2.mjs",
  "analyze-dynamic-offset-replay-v1.mjs",
  "verify-dynamic-offset-replay-v1.py",
  "verify-freeze-receipt.py",
  "closure-freeze",
  "dependencies.lock.json",
  "execution-manifest.json",
  "snapshot-files.sha256"
];
for (const fileName of requiredSnapshotNames) assert.ok(runner.includes(fileName), `snapshot input missing from runner: ${fileName}`);

console.log(JSON.stringify({
  status: "PASS_OPEN_STATIC",
  obligationId: "ABI-04",
  stage: "S1",
  runnerSha256: fileSha256(runnerPath),
  launcherContractSha256: fileSha256(launcherContractPath),
  waveContractSha256: fileSha256(waveContractPath),
  claimsRootSha256: index.claimsRootSha256,
  exactLeaves: wave.leaves.length,
  exactReplays: wave.exactReplayCount,
  frozenExpectedGraphContracts: expectedGraphs.length,
  heavyProofExecuted: false,
  centralBindingAllowed: wave.centralBindingAllowed,
  rowDisposition: wave.rowDispositionAfterSuccessfulWave
}, null, 2));
