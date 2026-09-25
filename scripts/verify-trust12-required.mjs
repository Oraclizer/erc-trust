// SPDX-License-Identifier: BSD-3-Clause
// Required consistency gate, separate from proof completeness and release approval.
import { verifyRuntimeBundles } from './lib/runtime-bundles.mjs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { check, checkLocalReceiptProvenance, encoded, fileRef, inputInventory, inventoryRoot, json, read, sha256, walk } from './lib/local-evidence.mjs';
import { formalAdmissionDigest, validateFormalIdentity } from './lib/formal-inputs.mjs';
import { verifyTrust12Policy, mandatoryIds, researchIds } from './lib/trust12-policy.mjs';
const repository = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const functionalRoot = '8d228ae9224b34e8e05eddc308d5ce77f0595ef0e02bc408fff31d1b5df467e2';
const testsRoot = '23f88d74a162d19792b51bdbd976d111c65e731b96ba5aac495b51be33125d7d';
const mutationIds = ['callback-auth','factory-pin','hidden-agent','inbound','initial','receipt'];
export const requiredTrust12Paths = [
  'evidence/trust12/release-policy.json','evidence/trust12/release-notes.md',
  'evidence/claim-matrix.md','evidence/known-limitations.md',
  'scripts/lib/trust12-policy.mjs','scripts/verify-trust12-policy.mjs','scripts/test-trust12-policy.mjs',
  'evidence/trust12/obligation-ledger.json','evidence/trust12/runtime-identity.json','evidence/trust12/runtime-link-source-blockers.md',
  'evidence/trust12/independent-audit.md','evidence/trust12/symbolic-kontrol.json','evidence/trust12/symbolic-booster.json',
  'evidence/trust12/runtime-producer-feasibility.json',
  'evidence/trust12/formal-build.json','evidence/trust12/formal-build-replay.json',
  'evidence/trust12/model-results.json','evidence/trust12/model-preservation-audit.md',
  'evidence/trust12/linked-controls-audit.md','evidence/trust12/model-source-normalization.json',
  'evidence/trust12/local-validation.json','evidence/trust12/deterministic-build-replay.json',
  'evidence/trust12/evidence-reuse.json','evidence/trust12/evidence-reuse-controls.json',
  'evidence/trust12/evidence-reuse-audit.md','evidence/trust12/functional-evidence-reuse.json',
  ...mutationIds.map(id => `evidence/trust12/mutation-${id}.json`),
  'scripts/capture-isabelle-local-inputs.mjs','scripts/lib/runtime-bundles.mjs','scripts/generate-trust12-proof-audit.py',
  'scripts/proof-ci.mjs','scripts/run-proof-ci.sh','scripts/test-proof-ci.mjs',
  'scripts/test-trust12-required.mjs',
  'scripts/verify-trust12-required.mjs','scripts/lib/local-evidence.mjs','scripts/lib/formal-inputs.mjs',
  'scripts/record-foundry-results-v3.mjs','scripts/record-isabelle-results-v3.mjs',
  'scripts/record-trust12-deterministic.mjs','scripts/record-trust12-model-results.mjs','scripts/generate-runtime-binding-v3.mjs',
];
export function verifyTrust12Required(root = repository) {
  const seal = json(root,'evidence/trust12/input-seal.json');
  check(seal.schema === 'trust12-input-seal-v2' && Array.isArray(seal.files), 'TRUST 1.2 seal schema');
  check(new Set(seal.files.map(x=>x.path)).size === seal.files.length, 'duplicate sealed input');
  for (const path of requiredTrust12Paths) check(seal.files.some(x=>x.path===path), `required TRUST 1.2 input is not sealed: ${path}`);
  for (const entry of seal.files) check(sha256(read(root,entry.path)) === entry.sha256, `sealed input drift: ${entry.path}`);
  const functional = json(root,'evidence/trust12/functional-evidence-reuse.json');
  check(functional.schema === 'trust12-functional-evidence-reuse-v1' && inventoryRoot(functional.inputs) === functionalRoot
    && functional.inputRootSha256 === functionalRoot, 'audited Hook input inventory drift');
  check(encoded(inputInventory(root,functional.inputs.map(x=>x.path))) === encoded(functional.inputs), 'audited Hook source or feature evidence drift');
  const runtime = json(root,'evidence/trust12/runtime-identity.json');
  check(runtime.status === 'PASS' && runtime.upstream.commit === '0fa344b761cf861bb9e8e1c8e472ba72815316c2', 'Hook runtime or actual upstream identity');
  check(encoded(runtime.sourceInputs.map(x=>x.path).sort()) === encoded([...walk(root,'implementation/src'),'foundry.toml'].sort()), 'Hook runtime source inventory incomplete');
  for (const input of runtime.sourceInputs) check(sha256(read(root,input.path)) === input.sha256, `Hook runtime source drift: ${input.path}`);
  const deterministic = json(root,'evidence/deterministic-build.json');
  check(deterministic.provider === 'local-wsl-foundry' && deterministic.provenance?.source?.path === 'evidence/trust12/deterministic-build-replay.json', 'deterministic local provenance missing');
  check(deterministic.provenance.source.sha256 === sha256(read(root,deterministic.provenance.source.path)), 'deterministic original receipt drift');
  const { provider, provenance, ...originalDeterministic } = deterministic;
  check(encoded(originalDeterministic) === encoded(json(root,provenance.source.path)), 'deterministic execution identity was rewritten');
  check(encoded(inputInventory(root,provenance.sourceInputs.map(x=>x.path))) === encoded(provenance.sourceInputs), 'deterministic current inputs drift');
  const foundry = json(root,'evidence/foundry-results-v3.json');
  checkLocalReceiptProvenance(root,foundry,'local-wsl-foundry');
  check(foundry.status === 'PASS' && foundry.checks.format === 'PASS' && foundry.checks.buildAndSize === 'PASS'
    && foundry.checks.lintErrors === 0 && foundry.checks.tests.failed === 0 && foundry.checks.tests.skipped === 0, 'required Foundry checks failed');
  check(Array.isArray(foundry.testInventory) && sha256(encoded(foundry.testInventory)) === testsRoot
    && functional.testsRootSha256 === testsRoot && foundry.checks.tests.passed === foundry.testInventory.length
    && foundry.testInventory.every(t=>t.status==='Success'), 'required named Foundry test set or results drift');
  const hookTests = foundry.testInventory.filter(t=>t.suite.endsWith(':ERC3643HookTrexIntegrationTest'));
  check(hookTests.length === 9, 'actual T-REX integration evidence incomplete');
  for (const id of mutationIds) {
    const mutation = json(root,`evidence/trust12/mutation-${id}.json`);
    check(mutation.mutation === id && mutation.status === 'KILLED' && mutation.exitCode !== 0
      && mutation.semanticMilestone && mutation.originalSha256 === sha256(read(root,mutation.sourcePath)), `Hook semantic mutation drift: ${id}`);
    check(hookTests.some(t=>t.test.startsWith(`${mutation.detector}(`)), `Hook mutation has no successful original detector: ${id}`);
  }
  const formal = json(root,'evidence/isabelle-results-v3.json');
  checkLocalReceiptProvenance(root,formal,'local-windows-isabelle');
  validateFormalIdentity(root,formal.formalSource);
  check(formal.formalSource.rootSha256 === '7c6d08d4cca6ca035959f46d2cd5e4ae26595ad5005abaf9dd2da5e9c908954a', 'formal inputs differ from the admitted clean build; new execution and review required');
  const formalReplay = json(root,'evidence/trust12/formal-build-replay.json');
  // Recomputed from the actual captured inputs and both original proof exports.
  // New proof inputs must receive execution and independent review before admission.
  const admittedBuild = 'b938a742ef50ccbfa3453462412057c6a59790e315373b4a7a1ded8062052bc4';
  check(formalAdmissionDigest(formalReplay) === admittedBuild && formalReplay.admissionDigest === admittedBuild
    && formal.admissionDigest === admittedBuild, 'admitted execution or dependency evidence drift');

  check(encoded(formalReplay.formalSource) === encoded(formal.formalSource) && formalReplay.processExit === 0
    && formalReplay.status === 'PASS', 'formal replay/input mismatch');
  check(formal.status === 'PASS' && formal.checks.cleanBuild === 'PASS' && formal.checks.proofExport === 'PASS'
    && formal.checks.bannedSourceForms === 0 && formal.checks.oracleDependencyCount === 0, 'required clean proof build/export failed');
  check(encoded(formal.sessions.map(s=>s.name).sort()) === encoded(formal.formalSource.sessions)
    && encoded(formal.sessions) === encoded(formalReplay.sessions), 'formal named session evidence mismatch');
  for (const session of formal.sessions) check(session.status === 'PASS' && session.cleanBuild === 'PASS' && session.proofExport === 'PASS'
    && session.explicitRoots > 0 && session.oracleDependencies === 0 && /^[a-f0-9]{64}$/.test(session.exportSha256), `formal session incomplete: ${session.name}`);
  // These model bytes are admitted only with the current clean build and source reviews.
  const modelPath = 'evidence/trust12/model-results.json';
  const model = json(root,modelPath);
  check(sha256(read(root,modelPath)) === '9dd096aed9fb49c59fc11ba3b2c341f31ce2c06a29c58c20e8b21587572e5414', 'unreviewed model result promotion');
  const child = formal.sessions.find(s=>s.name==='TRUST12_Accounting_Obstruction');
  check(model.status === 'PASS_KERNEL_CHECKED_MODEL' && model.executionCommit === formal.sourceCommit
    && model.formalRootSha256 === formal.formalSource.rootSha256 && model.formalAdmissionDigest === admittedBuild,
    'model result does not match current clean execution');
  check(model.proofAudit.explicitRoots === child.explicitRoots && model.proofAudit.qualifiedFacts === child.qualifiedFacts
    && model.proofAudit.exportSha256 === child.exportSha256 && model.proofAudit.oracleDependencies === 0,
    'model theorem inventory differs from actual kernel export');
  const references = [model.proofAudit,model.sourceReviews.preservation,model.sourceReviews.linkedRun,model.sourceNormalization,...model.controls];
  for(const ref of references) check(sha256(read(root,ref.path)) === ref.sha256, `model source or review reference drift: ${ref.path}`);
  check(Object.values(model.nonclaims).every(value=>value===false), 'model result cannot discharge runtime or constructor obligations');
  const normalization = json(root,model.sourceNormalization.path);
  check(normalization.status === 'PASS_REVERSIBLE_LINE_ENDING_ONLY' && normalization.files.length === 2, 'model normalization inventory drift');
  for(const entry of normalization.files) {
    check(['formal/isabelle/TRUST12_OBSTRUCTIONS/ROOT','formal/isabelle/TRUST12_OBSTRUCTIONS/TRUST_Release_Preservation.thy'].includes(entry.path), 'unexpected normalized model source');
    const current = read(root,entry.path), rule = entry.reconstructReviewedBytes;
    check(sha256(current) === entry.afterSha256, 'normalized model source drift');
    let reviewed;
    if(rule.kind === 'append-final-LF' && rule.count === 1) reviewed = Buffer.concat([current,Buffer.from('\n')]);
    else if(rule.kind === 'insert-CR-before-LF' && Number.isInteger(rule.byteOffset) && current[rule.byteOffset] === 10)
      reviewed = Buffer.concat([current.subarray(0,rule.byteOffset),Buffer.from('\r'),current.subarray(rule.byteOffset)]);
    else check(false,'invalid model normalization reconstruction');
    check(sha256(reviewed) === entry.beforeSha256, 'reviewed model bytes do not reconstruct');
  }
  const symbolic = json(root,'evidence/trust12/symbolic-kontrol.json');
  check(symbolic.status === 'INCOMPLETE' && symbolic.target.sourceSha256 === sha256(read(root,symbolic.target.source)), 'symbolic scope or source drift');
  check(symbolic.target.inputDomain === 'first > 0 and second > 0 and second <= first'
    && symbolic.target.explicitlyNotAssumed === 'first <= total supply', 'symbolic input domain narrowed');
  check(symbolic.attempts.every(a=>a.prove.status==='TIMEOUT' && a.prove.exitCode===124), 'unreviewed symbolic result promotion');
  const booster = json(root,'evidence/trust12/symbolic-booster.json');
  check(booster.status === 'INCOMPLETE' && booster.provider === 'local-wsl-kontrol' && booster.build.exitCode === 0
    && booster.prove.exitCode === 124 && booster.backend.booster === true && booster.backend.wallTimeoutSeconds === 900,
    'unreviewed Booster proof result promotion');
  check(booster.harnessSha256 === symbolic.target.sourceSha256 && booster.inputDomain === symbolic.target.inputDomain
    && booster.notAssumed === 'first <= supply', 'Booster source or input domain drift');
  const feasibility = json(root,'evidence/trust12/runtime-producer-feasibility.json');
  check(feasibility.schema === 'trust12-runtime-producer-feasibility-v1' && feasibility.status === 'PARTIAL_SOURCE_BLOCKED'
    && feasibility.receiver.status === 'NOT_FOUND_IN_INSPECTED_LOCAL_SOURCE'
    && feasibility.feasibility.checkedProducer === 'NOT_ESTABLISHED' && feasibility.feasibility.formalBuildingOpened === false
    && feasibility.executionBoundary.runtimeLinkDischarged === false && feasibility.executionBoundary.newProverRuns === 0,
    'feasibility inspection cannot discharge runtime link');
  check(feasibility.dataWitness.status === 'PARSED_KCFG_DATA_ONLY' && feasibility.dataWitness.sourceBeforeAfterEqual === true
    && feasibility.dataWitness.sourceKcfgSha256 === booster.graph.kcfgSha256
    && feasibility.dataWitness.sourceProofSha256 === booster.graph.proofSha256,
    'runtime data witness identity or nonclaim drift');
  const ledger = json(root,'evidence/trust12/obligation-ledger.json');
  const rows = new Map(ledger.obligations.map(row=>[row.id,row]));
  check(rows.size === ledger.obligations.length, 'duplicate TRUST 1.2 obligation');
  const policy = verifyTrust12Policy(root);
  const mandatory = policy.currentMandatory;
  const expectedRows = ['HOOK-FRESH-INITIAL','HOOK-FACTORY-CREATION','HOOK-SOLE-AGENT','HOOK-INBOUND-FLOOR','HOOK-CALLER-AUTH','HOOK-CALLBACK-ROLLBACK','HOOK-ACTUAL-RECEIPT','HOOK-INDEPENDENT-FINAL','MODEL-INITIAL-WF','MODEL-ORDINARY-PRESERVATION','MODEL-REGULATORY-PRESERVATION','MODEL-LINKED-RUN'];
  check(rows.size === expectedRows.length + mandatoryIds.length + researchIds.length && expectedRows.every(id=>rows.get(id)?.status==='CLOSED'), 'named feature/model obligation inventory drift');
  const binding = json(root,'evidence/runtime-binding-v3.json');
  verifyRuntimeBundles(root,binding);
  for (const name of ['ERC3643HookAdapter','ERC3643HookGovernor','ERC3643HookCompliance','ERC3643HookFactory']) {
    const subject = binding.subjects.find(s=>s.id===name);
    check(subject?.runtimeTemplate.sha256 === runtime.runtimes[name].runtimeSha256
      && ['abi','storageLayout','creationBytecode','runtimeTemplate','methodIdentifiers','immutableReferences'].every(key=>subject.semanticChecks[key]===true), `Hook pinned compiler identity missing: ${name}`);
  }
  check(json(root,'evidence/evidence-mode.json').mode === 'successor-development', 'open TRUST 1.2 obligations prohibit release promotion');
  return { status: 'PASS_CONSISTENT_DEVELOPMENT', centralClosure: 'INCOMPLETE', currentMandatory: mandatory,
    releaseReadiness: policy.releaseReadiness, researchResiduals: policy.researchResiduals,
    shippingExceptions: policy.shippingExceptions, fullRefinementComplete: false,
    profiles: { native: { existingEvidence: 'PRESERVED', runtimeRefinement: 'INCOMPLETE' },
      partial: { existingEvidence: 'PRESERVED', full: false, runtimeRefinement: 'INCOMPLETE' },
      hook: { functionalConformance: 'PASS_PINNED_FRESH_TREX', integrationTests: hookTests.length, semanticMutations: mutationIds.length, runtimeRefinement: 'INCOMPLETE' } },
    models: { preservation:'PASS_ABSTRACT_MODEL',linkedRun:'PASS_ABSTRACT_MODEL',runtimeConnection:'CONDITIONAL' },
    symbolicBackendComparison: { status: booster.status, proofExit: booster.prove.exitCode, guardRemoval: booster.scope.guardRemoval },
    evidence: [...requiredTrust12Paths.filter(p=>p.startsWith('evidence/')), 'evidence/trust12/input-seal.json'].map(p=>fileRef(root,p)),
    nonclaim: 'Required evidence is present and bound to the current inputs. Policy consistency is not proof completion or shipping approval; the general runtime link remains a research residual.' };
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) console.log(JSON.stringify(verifyTrust12Required(),null,2));
