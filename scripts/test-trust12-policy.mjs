// SPDX-License-Identifier: BSD-3-Clause
// Isolated policy controls: fixture successes are not product evidence or approvals.
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { dirname, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { check, encoded, fileRef, json, sha256 } from './lib/local-evidence.mjs';
import { completionWordingDocuments, components, deferralDisclosure, disclosures, hasFixture, implementationDisclosures, profiles, registeredClosureId, registeredCompletionDisclosure, registeredFinalInputs, verifiedCentralCompletion, verifyTrust12Policy, withoutIsabelleComments } from './lib/trust12-policy.mjs';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const out = resolve(root, 'out/trust12');
mkdirSync(out, { recursive: true });
const scratch = mkdtempSync(resolve(out, 'policy-controls-'));
const policyPath = 'evidence/trust12/release-policy.json', ledgerPath = 'evidence/trust12/obligation-ledger.json';
const policy = json(root, policyPath), recorded = json(root, ledgerPath), results = [];
// The controls model the state before the fresh assurance. A recorded assurance is removed from their baseline
// and checked by its own control; the fixtures below still construct a completion from that pending baseline.
function pendingLedger(ledger) {
  const pending = structuredClone(ledger);
  if (!pending.centralClosure.independentAssurance) return pending;
  delete pending.centralClosure.independentAssurance;
  pending.centralClosure.status = 'INCOMPLETE';
  Object.assign(pending.releaseAssessment, { status: 'ASSURANCE_PENDING', trust12Complete: false });
  return pending;
}
const baseline = pendingLedger(recorded);
const endToEndPath = 'evidence/end-to-end-refinement/obligation-ledger-v3.json';
const endToEndBaseline = json(root, endToEndPath);
function put(path, value) {
  mkdirSync(dirname(resolve(scratch, path)), { recursive: true });
  writeFileSync(resolve(scratch, path), typeof value === 'string' || Buffer.isBuffer(value) ? value : encoded(value));
}
const checkpointVerifier = 'scripts/trust12/verify_second_freeze_rejection_v1.py';
const refs = new Map();
function collect(value) {
  if (!value || typeof value !== 'object') return;
  if (typeof value.path === 'string' && typeof value.sha256 === 'string') refs.set(value.path, value);
  for (const v of Object.values(value)) collect(v);
}
collect(policy); collect(recorded); collect(json(root, 'evidence/trust12/runtime-identity.json'));
// A closed registered closure cites checkpoint records and their verifiers; the controls copy them as well.
const registeredBaseline = baseline.obligations.find(r => r.id === registeredClosureId);
const registeredClosurePaths = Object.values(registeredBaseline.registeredClosureEvidence?.references ?? {})
  .map(ref => ref.path);
for (const path of registeredClosurePaths) {
  const record = json(root, path);
  collect(record);
  for (const items of [...Object.values(record.conditionEvidence ?? {}),
    ...Object.values(record.findingDispositions ?? {}).map(item => item.evidence ?? [])])
    for (const item of items) collect(json(root, item.path).rehashVerifier);
}
// A recorded fresh assurance names its report, and the report names its input seal; the controls copy both.
const assuranceReport = recorded.centralClosure.independentAssurance?.report;
if (assuranceReport) collect(json(root, assuranceReport.path));
for (const path of new Set([...refs.keys(), 'evidence/trust12/symbolic-kontrol.json',
  'evidence/end-to-end-refinement/obligation-ledger-v3.json',
  'evidence/isabelle-results-v3.json', 'evidence/trust12/runtime-identity.json',
  'spec/generated/kernel-v2-abi.json', 'evidence/trust12/runtime-link/tail-preparation/tail-obligations-v1.json',
  'scripts/verify-trust12-required.mjs', checkpointVerifier,
  'evidence/certora-results-v3.json', ...implementationDisclosures, ...completionWordingDocuments]))
  put(path, readFileSync(resolve(root, path)));
const recordedDocuments = Object.fromEntries([...new Set([...implementationDisclosures, ...completionWordingDocuments])]
  .map(path => [path, readFileSync(resolve(root, path), 'utf8')]));
// The same pattern as the completion claim of the release policy; the pending documents carry no completion claim.
const completionWording = /TRUST\s+1\.2\s+(?:is\s+(?:now\s+|fully\s+)?complete(?:d)?\b|has\s+been\s+completed\b|was\s+completed\b|completed\s+(?:at|within)\b)|\bis\s+(?:now\s+)?complete\s+within\s+the\s+registered-execution\s+scope/gi;
const documents = recorded.centralClosure.independentAssurance
  ? Object.fromEntries(Object.entries(recordedDocuments).map(([path, text]) => [path,
    text.split(registeredCompletionDisclosure).join('').replace(completionWording, 'TRUST 1.2 awaits assurance')]))
  : recordedDocuments;
const tailConditionsPath = 'evidence/trust12/runtime-link/tail-preparation/tail-obligations-v1.json';
function reset() {
  put(policyPath, policy); put(ledgerPath, baseline);
  // The original bytes: a recorded fresh assurance binds the SHA-256 of this file in its final identities.
  put(endToEndPath, readFileSync(resolve(root, endToEndPath)));
  put(tailConditionsPath, readFileSync(resolve(root, tailConditionsPath)));
  for (const path of registeredClosurePaths) put(path, readFileSync(resolve(root, path)));
  for (const [path, text] of Object.entries(documents)) put(path, text);
}
function test(name, mutate, expected = null, options = {}) {
  reset(); const ledger = structuredClone(baseline), p = structuredClone(policy);
  mutate(ledger, p); put(ledgerPath, ledger); put(policyPath, p);
  let error, report;
  try { report = verifyTrust12Policy(scratch, options); } catch (e) { error = e.message; }
  if (expected) check(error?.includes(expected), `${name}: expected ${expected}; observed ${error ?? 'PASS'}`);
  else check(!error, `${name}: ${error}`);
  results.push({ name, status: expected ? 'REJECTED' : 'PASS', reason: error ?? report.releaseReadiness });
  return report;
}
function row(ledger, id = 'RUNTIME-LINK-HOOK') { return ledger.obligations.find(r => r.id === id); }
function promoteTests(cell) {
  put('evidence/trust12/fixture-result.json', { fixtureOnly: true, status: 'PASS' });
  const ref = fileRef(scratch, 'evidence/trust12/fixture-result.json');
  Object.assign(cell, { evidenceGrade: 'EXECUTION_TESTS', evidence: [ref], artifactBindings: [ref],
    assumptions: ['Fixture semantics only'], review: ref,
    negative: { kind: 'BOUNDED_BEHAVIORAL', scope: 'Fixture input', evidence: [ref] },
    result: { kind: 'TESTS', status: 'PASS', sampleScope: 'Fixture case only' } });
}
// The readiness that the policy derives while no fresh assurance exists.
function settle(ledger) {
  const pending = ledger.centralClosure.currentMandatory.length > 0;
  ledger.releaseAssessment.status = pending ? 'PENDING' : 'ASSURANCE_PENDING';
  ledger.status = pending ? 'IN_PROGRESS'
    : ledger.centralClosure.shippingExceptions.length ? 'EVIDENCE_COMPLETE_WITH_EXCEPTIONS' : 'EVIDENCE_COMPLETE';
}
function reopenRegistered(ledger) {
  const r=row(ledger,registeredClosureId);
  Object.assign(r,{status:'CURRENT-MANDATORY',proofCompleted:false,positiveActivation:'Pending',
    consumerRemovalNegative:'Pending',compiledConsumer:'Pending'});
  delete r.registeredClosureEvidence;
  if (!ledger.centralClosure.currentMandatory.includes(registeredClosureId))
    ledger.centralClosure.currentMandatory.push(registeredClosureId);
  settle(ledger);
  return r;
}
function approvedException(ledger) {
  const r = row(ledger, 'NATIVE-SYMBOLIC-FREEZE');
  const approval = { kind: 'SHIPPING_EXCEPTION', approvedBy: 'Jay Kim', date: '2026-09-13',
    obligationId: r.id, allowedScope: 'TEST FIXTURE ONLY', userInstruction: 'TEST FIXTURE, NOT A REAL USER APPROVAL' };
  const path = 'evidence/trust12/fixture-approval.json'; put(path, approval);
  r.status = 'OPEN-SHIPPING-EXCEPTION';
  r.shippingException = { proofCompleted: false, allowedScope: approval.allowedScope,
    unverifiedScope: 'Original general input domain remains unproven', approval: fileRef(scratch, path),
    carryover: { receivingProcess: 'Test follow-up', responsibleArtifact: 'Test symbolic receipt',
      closureEvidence: 'Full original proof and negative', resumeCondition: 'Test evidence available' },
    disclosure: 'TEST ONLY: NATIVE-SYMBOLIC-FREEZE remains unproven; approved test exception.' };
  ledger.centralClosure.currentMandatory = ledger.centralClosure.currentMandatory.filter(id => id !== r.id);
  ledger.centralClosure.shippingExceptions = [r.id];
  settle(ledger);
  for (const [path, text] of Object.entries(documents))
    put(path, text.replace('TRUST 1.2 shipping exceptions: none.', r.shippingException.disclosure));
  return r;
}
function nativeProofFixture(ledger) {
  const r=row(ledger,'NATIVE-SYMBOLIC-FREEZE'), e=r.symbolicEvidence;
  promoteTests(e);
  const proofPath='evidence/trust12/fixture-proof-result.json';
  put(proofPath,{proofs:[{id:'test-only-general-claim',status:'PASS',unresolvedGoals:0,admittedGoals:0,vacuous:false}]});
  Object.assign(e,{evidenceGrade:'FULL_SCOPE_PROOF',property:r.abstractCondition,inputScope:r.inputDomain,notAssumed:r.notAssumed,
    result:{tool:'Kontrol/KEVM',kind:'PROOF',status:'PASS',unresolvedGoals:0,admittedGoals:0,vacuous:false,
      claimIds:['test-only-general-claim'],coversDeclaredScope:true,receipt:fileRef(scratch,proofPath)}});
  Object.assign(e.negative,{kind:'KILLED_CONSUMER_REMOVAL',inputScope:r.inputDomain,notAssumed:r.notAssumed,coversDeclaredScope:true,
    testedBranchPredicates:['first <= SUPPLY','SUPPLY < first'],fullInputDomainNegative:true,wholeMutantTransactionProved:false,
    evidence:[...e.negative.evidence,fileRef(scratch,'evidence/trust12/runtime-link/native-supply-direction-negative-checkpoint-v1.json')]});
  r.fullDomainNegativeReceived=true;
  r.status='CLOSED';r.positiveActivation='Test-only full scope';r.consumerRemovalNegative='Test-only same-domain removal';
  ledger.centralClosure.currentMandatory=ledger.centralClosure.currentMandatory.filter(id=>id!==r.id);
  settle(ledger);
  return e;
}
const fixtures = { fixtureMode: true };
function registeredClosureFixture(ledger) {
  const r=row(ledger,registeredClosureId);
  const tailPath='evidence/trust12/runtime-link/tail-preparation/tail-obligations-v1.json', tail=json(scratch,tailPath);
  const discharged=tail.conditions.map(c=>c.id).filter(id=>id!=='independent-assurance');
  const evidencePath='evidence/trust12/fixture-registered-condition.json';
  put(evidencePath,{status:'PASS_FIXTURE_ONLY',fixtureOnly:true,rehashVerifier:fileRef(scratch,checkpointVerifier)});
  const evidence=fileRef(scratch,evidencePath);
  const closurePath='evidence/trust12/fixture-registered-closure.json';
  put(closurePath,{schema:'trust12-registered-central-closure-v1',status:'PASS',fixtureOnly:true,
    finalInputs:registeredFinalInputs(scratch,r),dischargedConditions:discharged,
    conditionEvidence:Object.fromEntries(discharged.map(id=>[id,[evidence]])),
    findingDispositions:Object.fromEntries(tail.findings.map(f=>[f.id,{kind:'RESOLVED',detail:'Fixture-only disposition',evidence:[evidence]}])),
    retainedAssumptions:[...json(scratch,endToEndPath).assumptions.map(a=>a.id),'A-KEVM-TOOLCHAIN'],
    generalRuntimeLinkDischarged:false});
  const closure=fileRef(scratch,closurePath);
  const references={closure};
  for(const role of ['positive','negative','compiledConsumer']){
    const path=`evidence/trust12/fixture-registered-${role}.json`;
    put(path,{schema:'trust12-registered-closure-evidence-v1',role,closureSha256:closure.sha256,
      status:role==='negative'?'KILLED':'PASS',fixtureOnly:true});
    references[role]=fileRef(scratch,path);
  }
  Object.assign(r,{status:'CLOSED',proofCompleted:true,positiveActivation:'Fixture-only registered positive',
    consumerRemovalNegative:'Fixture-only registered negative',compiledConsumer:'Fixture-only registered consumer',
    registeredClosureEvidence:{status:'PASS_REGISTERED_CENTRAL_CLOSURE',references}});
  ledger.centralClosure.currentMandatory=ledger.centralClosure.currentMandatory.filter(x=>x!==registeredClosureId);
  ledger.releaseAssessment.status='ASSURANCE_PENDING'; ledger.status='EVIDENCE_COMPLETE';
  return r;
}
function registeredCompletionFixture(ledger, closureDigest) {
  const r=registeredClosureFixture(ledger);
  const finalIdentities={formalRootSha256:json(scratch,'evidence/isabelle-results-v3.json').formalSource.rootSha256,
    runtimeIdentitySha256:fileRef(scratch,'evidence/trust12/runtime-identity.json').sha256,
    abiSha256:fileRef(scratch,'spec/generated/kernel-v2-abi.json').sha256,
    endToEndLedgerSha256:fileRef(scratch,endToEndPath).sha256,
    registeredClosureSha256:closureDigest ?? sha256(encoded(r.registeredClosureEvidence)),
    generalProofDigests:Object.fromEntries(profiles.map(profile=>[profile,null]))};
  const sealPath='evidence/trust12/assurance/fixture-registered-seal.json';
  put(sealPath,{schema:'trust12-tail-preparation-assurance-input-seal-v1',status:'SEALED_FOR_INDEPENDENT_ASSURANCE',
    fixtureOnly:true,product:{cleanWorktree:true},sealRootSha256:'a'.repeat(64)});
  const seal=fileRef(scratch,sealPath);
  finalIdentities.assuranceSealSha256=seal.sha256;
  const path='evidence/trust12/assurance/fixture-registered-final.json';
  put(path,{schema:'trust12-final-assurance-v1',status:'PASS_FRESH_ASSURANCE',fixtureOnly:true,independentOfBuilding:true,
    reviewer:'Fixture reviewer, not a real assurance',reproduction:{status:'PASS'},consumerRemoval:{status:'PASS'},seal,finalIdentities});
  ledger.centralClosure.independentAssurance={status:'PASS_FRESH_ASSURANCE',report:fileRef(scratch,path)};
  ledger.centralClosure.status='COMPLETE_REGISTERED_SCOPE'; ledger.releaseAssessment.trust12Complete=true;
  ledger.releaseAssessment.status='EVIDENCE_READY';
  for (const path of disclosures) put(path,documents[path]+'\n'+registeredCompletionDisclosure+'\n');
  return r;
}
function rewriteClosure(r, mutate) {
  const ref=r.registeredClosureEvidence.references.closure, closure=json(scratch,ref.path);
  mutate(closure); put(ref.path,closure);
  r.registeredClosureEvidence.references.closure=fileRef(scratch,ref.path);
  for(const role of ['positive','negative','compiledConsumer']){
    const roleRef=r.registeredClosureEvidence.references[role], record=json(scratch,roleRef.path);
    record.closureSha256=r.registeredClosureEvidence.references.closure.sha256; put(roleRef.path,record);
    r.registeredClosureEvidence.references[role]=fileRef(scratch,roleRef.path);
  }
}
function generalProofFixture(ledger, id) {
  const r=row(ledger,id), roles=['execution','formalProof','positive','negative','compiledConsumer'];
  const references=Object.fromEntries(roles.map(role=>{
    const path=`evidence/trust12/fixture-general-${role}.json`;
    put(path,{fixtureOnly:true,status:'PASS',role});
    return [role,fileRef(scratch,path)];
  }));
  r.status='CLOSED';r.proofCompleted=true;
  r.positiveActivation='Fixture-only general positive';r.consumerRemovalNegative='Fixture-only general negative';
  const profile=id.slice('RESEARCH-RUNTIME-LINK-'.length);
  r.generalProofEvidence={status:'PASS_GENERAL_RUNTIME_LINK',profile,
    theoremName:`${profile.toLowerCase()}_general_runtime_link_fixture`,formalSession:'TRUST12_GENERAL_FIXTURE',
    references};
  ledger.centralClosure.currentMandatory=ledger.centralClosure.currentMandatory.filter(x=>x!==id);
  return r;
}
try {
  test('current-policy', () => {});
  if (recorded.centralClosure.independentAssurance) {
    // The recorded fresh assurance of this tree completes TRUST 1.2 within the registered-execution scope.
    reset(); put(ledgerPath, recorded);
    for (const [path, text] of Object.entries(recordedDocuments)) put(path, text);
    const completed = verifyTrust12Policy(scratch);
    check(completed.trust12Complete === true && completed.fullRefinementComplete === false
      && completed.releaseReadiness === 'EVIDENCE_READY', 'recorded assurance does not complete TRUST 1.2');
    results.push({ name: 'recorded-registered-completion', status: 'PASS', reason: completed.releaseReadiness });
  }
  test('reopened-registered-row-is-consistent', l => { reopenRegistered(l); });
  test('unknown-state', l => { row(l).status = 'PASS'; }, 'unknown status');
  test('missing-component', l => row(l).components.pop(), 'exactly seven');
  test('duplicate-component', l => { row(l).components[1].id = components[0]; }, 'exactly seven');
  test('grade-inflation', l => { row(l).evidenceGrade = 'FULL_SCOPE_PROOF'; }, 'weakest component');
  test('test-is-not-proof', l => { const r = row(l); for (const c of r.components) promoteTests(c);
    r.evidenceGrade = 'FULL_SCOPE_PROOF'; }, 'weakest component');
  test('one-unverified-prevents-closure', l => { const r = row(l), c=r.components[0];
    c.evidenceGrade='UNVERIFIED'; delete c.result; c.negative={kind:'UNVERIFIED',scope:'Test fixture',evidence:[]};
    r.evidenceGrade='UNVERIFIED'; r.status='CLOSED';
    r.positiveActivation='Completed fixture'; r.consumerRemovalNegative='Completed fixture'; }, 'unreviewed mandatory obligation removal');
  test('missing-positive', l => { const c = row(l).components[0]; promoteTests(c); c.evidence=[]; }, 'lacks bound evidence');
  test('stale-artifact', l => { const c = row(l).components[0]; promoteTests(c);
    c.artifactBindings=[{...c.artifactBindings[0],sha256:'0'.repeat(64)}]; }, 'compiled artifact reference drift');
  test('missing-negative', l => { const c = row(l).components[0]; promoteTests(c); c.negative.kind='UNVERIFIED'; }, 'lacks negative evidence');
  test('timeout-not-proof', l => { const c = row(l).components[0]; promoteTests(c); c.evidenceGrade='FULL_SCOPE_PROOF';
    c.result={tool:'Kontrol/KEVM',kind:'PROOF',status:'TIMEOUT'}; }, 'no PASS result');
  test('unresolved-not-proof', l => { const c = row(l).components[0]; promoteTests(c); c.evidenceGrade='FULL_SCOPE_PROOF';
    c.result={tool:'Kontrol/KEVM',kind:'PROOF',status:'PASS',unresolvedGoals:1}; }, 'completed nonvacuous proof');
  test('ledger-only-proof-metadata-rejected', l => { const c=row(l,'RUNTIME-LINK-NATIVE').components[1];
    c.evidenceGrade='LIMITED_SCOPE_PROOF'; c.result={tool:'Kontrol/KEVM',kind:'PROOF',status:'PASS',unresolvedGoals:0,
      admittedGoals:0,vacuous:false,claimIds:['implementation%kontrol%TrustTokenKontrolTest.testKontrol_RawSensitiveSelectorsStayClosed():0'],
      limits:'Test fixture',receipt:c.evidence.find(ref=>ref.path==='evidence/kontrol-results-v3.json')};
  }, 'proof result metadata is not receipt-backed');
  test('general-link-cannot-return-to-mandatory', l => { row(l,'RESEARCH-RUNTIME-LINK-HOOK').status='CURRENT-MANDATORY';
    l.centralClosure.currentMandatory.push('RESEARCH-RUNTIME-LINK-HOOK'); }, 'general runtime link status or completion role drift');
  test('deferred-link-cannot-be-required', l => { row(l,'RESEARCH-RUNTIME-LINK-NATIVE').requiredForTrust12Completion=true; },
    'general runtime link status or completion role drift');
  test('deferred-link-needs-recorded-decision', l => { delete row(l,'RESEARCH-RUNTIME-LINK-PARTIAL').deferral; },
    'deferral is not the recorded decision');
  test('deferred-link-cannot-claim-proof', l => { row(l,'RESEARCH-RUNTIME-LINK-PARTIAL').proofCompleted=true; },
    'unproved general runtime link claims completion');
  test('residual-status-only-for-general-links', l => { row(l,'NATIVE-SYMBOLIC-FREEZE').status='RESEARCH-RESIDUAL'; },
    'research residual is limited to general runtime links');
  test('residual-list-must-match', l => { l.centralClosure.researchResiduals=[]; }, 'research residual list differs');
  test('deferral-disclosure-required', () => { const path='evidence/known-limitations.md';
    put(path,documents[path].replace(deferralDisclosure,'')); }, 'general runtime link deferral disclosure drift');
  test('superseded-direction-history-required', (l,p) => { delete p.supersededCompletionDirections; },
    'completion direction history missing');
  test('general-link-cannot-return-to-release-requirement', (l,p) => { p.generalRuntimeLinkRequiredForRelease=true; },
    'release policy boundary drift');
  test('old-direction-cannot-be-current', (l,p) => { p.completionDirection=p.supersededCompletionDirections[0]; },
    'current TRUST 1.2 completion direction missing');
  test('registered-closure-cannot-be-dropped', l => { l.obligations=l.obligations.filter(r=>r.id!==registeredClosureId);
    l.centralClosure.currentMandatory=[]; }, 'named obligation inventory drift');
  test('registered-closure-cannot-be-optional', l => { row(l,registeredClosureId).requiredForTrust12Completion=false; },
    'registered central closure row drift');
  test('registered-closure-needs-conditions-source', l => { row(l,registeredClosureId).conditionsSource='evidence/trust12/README.md'; },
    'registered central closure row drift');
  test('registered-closure-cannot-be-exception', l => { row(l,registeredClosureId).status='OPEN-SHIPPING-EXCEPTION';
    l.centralClosure.currentMandatory=[]; l.centralClosure.shippingExceptions=[registeredClosureId]; }, 'registered central closure row drift');
  test('evidence-less-registered-closure-rejected', l => { const r=row(l,registeredClosureId);
    Object.assign(r,{status:'CLOSED',proofCompleted:true,positiveActivation:'Fixture',consumerRemovalNegative:'Fixture',
      compiledConsumer:'Fixture'}); delete r.registeredClosureEvidence;
    l.centralClosure.currentMandatory=[]; l.releaseAssessment.status='EVIDENCE_READY'; l.status='EVIDENCE_COMPLETE'; },
    'registered central closure lacks a verified evidence contract');
  test('fixture-closure-rejected-in-production', l => { registeredClosureFixture(l); }, 'uses fixture records');
  if (registeredClosurePaths.length) {
    // Controls on the real closure record, without fixture mode.
    test('closed-closure-condition-evidence-removed', l => {
      rewriteClosure(row(l,registeredClosureId), c => { delete c.conditionEvidence['route-exhaustiveness']; }); },
      'does not discharge every recorded condition');
    test('closed-closure-blocking-finding-nonclaim', l => {
      rewriteClosure(row(l,registeredClosureId), c => {
        c.findingDispositions['unclassified-hook-routes']={kind:'NONCLAIM',detail:'Declared out of scope'}; }); },
      'while its blocking finding is not resolved');
    test('closed-closure-assumption-removed', l => {
      rewriteClosure(row(l,registeredClosureId), c => {
        c.retainedAssumptions=c.retainedAssumptions.filter(a=>a!=='A-KEVM-TOOLCHAIN'); }); },
      'does not discharge every recorded condition');
    test('closed-closure-role-unbound', l => { const r=row(l,registeredClosureId),
      ref=r.registeredClosureEvidence.references.negative, record=json(scratch,ref.path);
      record.closureSha256='0'.repeat(64); put(ref.path,record);
      r.registeredClosureEvidence.references.negative=fileRef(scratch,ref.path); }, 'negative is not bound');
    test('closed-closure-ungated-evidence', l => {
      const path='evidence/trust12/runtime-link/malformed/native-relation-checkpoint-v1.json';
      put(path, readFileSync(resolve(root,path)));
      rewriteClosure(row(l,registeredClosureId), c => {
        c.conditionEvidence['malformed-native']=[...c.conditionEvidence['malformed-native'],fileRef(scratch,path)]; }); },
      'not a checkpoint verified by the required gate');
    test('closed-closure-readiness-forged', l => { l.releaseAssessment.status='EVIDENCE_READY'; },
      'release readiness drift');
  }
  check(hasFixture({a:[{b:{fixtureOnly:true}}]}) && !hasFixture({a:[{b:1}]}), 'fixture marker detection failed');
  results.push({name:'nested-fixture-marker-detected',status:'PASS'});
  let reservedError;
  try { verifyTrust12Policy(root, fixtures); } catch (e) { reservedError = e.message; }
  check(reservedError?.includes('fixture mode is reserved'), 'fixture mode accepted on the product root');
  results.push({name:'fixture-mode-reserved-for-isolated-controls',status:'REJECTED',reason:reservedError});
  test('registered-closure-evidence-must-be-a-json-checkpoint', l => {
    rewriteClosure(registeredClosureFixture(l), c => { for (const id of Object.keys(c.conditionEvidence))
      c.conditionEvidence[id]=[fileRef(scratch,'evidence/known-limitations.md')]; }); },
    'not a checkpoint record in the evidence tree', fixtures);
  test('registered-closure-evidence-outside-evidence-tree', l => {
    rewriteClosure(registeredClosureFixture(l), c => { for (const id of Object.keys(c.conditionEvidence))
      c.conditionEvidence[id]=[fileRef(scratch,'spec/generated/kernel-v2-abi.json')]; }); },
    'not a checkpoint record in the evidence tree', fixtures);
  test('registered-closure-evidence-needs-gate-verifier', l => { registeredClosureFixture(l);
    put('evidence/trust12/fixture-registered-condition.json',{status:'PASS_FIXTURE_ONLY',fixtureOnly:true});
    rewriteClosure(row(l,registeredClosureId), c => { for (const id of Object.keys(c.conditionEvidence))
      c.conditionEvidence[id]=[fileRef(scratch,'evidence/trust12/fixture-registered-condition.json')]; }); },
    'not a checkpoint verified by the required gate', fixtures);
  test('registered-closure-evidence-verifier-must-be-gated', l => { registeredClosureFixture(l);
    put('scripts/trust12/fixture_unlisted_verifier.py','# fixture only\n');
    put('evidence/trust12/fixture-registered-condition.json',{status:'PASS_FIXTURE_ONLY',fixtureOnly:true,
      rehashVerifier:fileRef(scratch,'scripts/trust12/fixture_unlisted_verifier.py')});
    rewriteClosure(row(l,registeredClosureId), c => { for (const id of Object.keys(c.conditionEvidence))
      c.conditionEvidence[id]=[fileRef(scratch,'evidence/trust12/fixture-registered-condition.json')]; }); },
    'not a checkpoint verified by the required gate', fixtures);
  test('registered-closure-condition-evidence-key-missing', l => {
    rewriteClosure(registeredClosureFixture(l), c => { delete c.conditionEvidence[c.dischargedConditions[0]]; }); },
    'does not discharge every recorded condition', fixtures);
  test('blocking-finding-cannot-be-a-nonclaim', l => {
    rewriteClosure(registeredClosureFixture(l), c => {
      c.findingDispositions['per-certificate-program-identity']={kind:'NONCLAIM',detail:'Fixture-only'}; }); },
    'while its blocking finding is not resolved', fixtures);
  test('finding-disposition-must-be-structured', l => {
    rewriteClosure(registeredClosureFixture(l), c => { c.findingDispositions['no-formal-storage-reader']='Free text'; }); },
    'finding disposition is incomplete', fixtures);
  test('resolved-finding-needs-evidence', l => {
    rewriteClosure(registeredClosureFixture(l), c => { c.findingDispositions['no-formal-storage-reader'].evidence=[]; }); },
    'resolved registered closure finding has no evidence', fixtures);
  test('toolchain-assumption-required', l => {
    rewriteClosure(registeredClosureFixture(l), c => { c.retainedAssumptions=c.retainedAssumptions.filter(a=>a!=='A-KEVM-TOOLCHAIN'); }); },
    'does not discharge every recorded condition', fixtures);
  test('pinned-assumption-survives-ledger-discharge', l => { registeredClosureFixture(l);
    const e=json(scratch,endToEndPath); e.assumptions.find(a=>a.id==='A-MUTATION').status='DISCHARGED'; put(endToEndPath,e);
    rewriteClosure(row(l,registeredClosureId), c => { c.retainedAssumptions=c.retainedAssumptions.filter(a=>a!=='A-MUTATION'); }); },
    'does not discharge every recorded condition', fixtures);
  test('closed-registered-row-needs-proof-flag', l => { registeredClosureFixture(l).proofCompleted=false; },
    'closed registered central closure has pending evidence', fixtures);
  test('assurance-needs-an-input-seal', l => { registeredCompletionFixture(l);
    const ref=l.centralClosure.independentAssurance.report, report=json(scratch,ref.path); delete report.seal; put(ref.path,report);
    l.centralClosure.independentAssurance.report=fileRef(scratch,ref.path); }, 'names no input seal', fixtures);
  test('assurance-seal-must-be-final', l => { registeredCompletionFixture(l);
    put('evidence/trust12/assurance/fixture-registered-seal.json',{schema:'trust12-tail-preparation-assurance-input-seal-v1',
      status:'TEMPLATE_DRY_RUN',fixtureOnly:true,product:{cleanWorktree:true},sealRootSha256:'a'.repeat(64)});
    const ref=l.centralClosure.independentAssurance.report, report=json(scratch,ref.path);
    report.seal=fileRef(scratch,'evidence/trust12/assurance/fixture-registered-seal.json');
    report.finalIdentities.assuranceSealSha256=report.seal.sha256; put(ref.path,report);
    l.centralClosure.independentAssurance.report=fileRef(scratch,ref.path); }, 'not a final seal', fixtures);
  for (const [name, path, wording] of [
    ['completion-wording-has-been-completed', 'evidence/claim-matrix.md', 'TRUST 1.2 has been completed within the registered-execution scope.'],
    ['completion-wording-fully-complete', 'evidence/trust12/release-notes.md', 'TRUST 1.2 is fully complete.'],
    ['completion-wording-across-lines', 'evidence/known-limitations.md', 'TRUST 1.2 is\ncomplete within the\nregistered-execution scope'],
    ['completion-wording-in-formal-verification', 'FORMAL_VERIFICATION.md', 'TRUST 1.2 completed at the registered-execution scope.'],
    ['completion-wording-in-changelog', 'CHANGELOG.md', '- TRUST 1.2 is complete.'],
  ]) test(name, () => { put(path, documents[path] + '\n' + wording + '\n'); }, 'registered completion disclosure drift');
  test('open-state-wording-is-allowed', () => { const path='evidence/known-limitations.md';
    put(path, documents[path] + '\nTRUST 1.2 is not yet complete within the registered-execution scope.\n'); });
  const registeredOnly = test('registered-closure-fixture-without-assurance', l => { registeredClosureFixture(l); }, null, fixtures);
  check(registeredOnly.trust12Complete===false && registeredOnly.fullRefinementComplete===false
    && registeredOnly.releaseReadiness==='ASSURANCE_PENDING', 'registered closure without fresh assurance promoted to completion');
  test('closed-evidence-is-not-ready-before-assurance', l => { registeredClosureFixture(l);
    l.releaseAssessment.status='EVIDENCE_READY'; }, 'release readiness drift', fixtures);
  test('registered-closure-must-cover-every-condition', l => {
    rewriteClosure(registeredClosureFixture(l), c => { c.dischargedConditions.pop(); }); }, 'does not discharge every recorded condition', fixtures);
  test('registered-closure-cannot-claim-the-assurance', l => {
    rewriteClosure(registeredClosureFixture(l), c => { c.dischargedConditions.push('independent-assurance');
      c.conditionEvidence['independent-assurance']=c.conditionEvidence[c.dischargedConditions[0]]; }); },
    'does not discharge every recorded condition', fixtures);
  test('registered-closure-must-dispose-every-finding', l => {
    rewriteClosure(registeredClosureFixture(l), c => { c.findingDispositions={}; }); }, 'does not discharge every recorded condition', fixtures);
  test('registered-closure-must-name-every-assumption', l => {
    rewriteClosure(registeredClosureFixture(l), c => { c.retainedAssumptions=c.retainedAssumptions.filter(a=>a!=='A-COMPILER'); }); },
    'does not discharge every recorded condition', fixtures);
  test('registered-closure-cannot-claim-general-link', l => {
    rewriteClosure(registeredClosureFixture(l), c => { c.generalRuntimeLinkDischarged=true; }); }, 'does not discharge every recorded condition', fixtures);
  test('registered-closure-bound-to-final-abi', l => {
    rewriteClosure(registeredClosureFixture(l), c => { c.finalInputs.abiSha256='0'.repeat(64); }); }, 'does not discharge every recorded condition', fixtures);
  test('registered-closure-bound-to-row-condition', l => { const r=registeredClosureFixture(l);
    r.abstractCondition+=' Changed after closure.'; }, 'does not discharge every recorded condition', fixtures);
  test('registered-closure-condition-needs-evidence', l => {
    rewriteClosure(registeredClosureFixture(l), c => { c.conditionEvidence[c.dischargedConditions[0]]=[]; }); },
    'condition has no evidence', fixtures);
  test('registered-closure-evidence-must-pass', l => { registeredClosureFixture(l);
    const path='evidence/trust12/fixture-registered-condition.json', closurePath='evidence/trust12/fixture-registered-closure.json';
    put(path,{status:'FAIL',fixtureOnly:true}); const r=row(l,registeredClosureId);
    rewriteClosure(r, c => { for (const id of Object.keys(c.conditionEvidence)) c.conditionEvidence[id]=[fileRef(scratch,path)]; }); },
    'not a passing record', fixtures);
  test('registered-closure-conditions-list-is-pinned', l => { registeredClosureFixture(l);
    const tailPath='evidence/trust12/runtime-link/tail-preparation/tail-obligations-v1.json', tail=json(scratch,tailPath);
    tail.findings.pop(); put(tailPath,tail); }, 'differ from the reviewed list', fixtures);
  test('registered-closure-role-bound-to-closure', l => { const r=registeredClosureFixture(l), ref=r.registeredClosureEvidence.references.positive;
    const record=json(scratch,ref.path); record.closureSha256='0'.repeat(64); put(ref.path,record);
    r.registeredClosureEvidence.references.positive=fileRef(scratch,ref.path); }, 'positive is not bound', fixtures);
  test('registered-closure-roles-are-distinct', l => { const r=registeredClosureFixture(l);
    r.registeredClosureEvidence.references.positive=r.registeredClosureEvidence.references.compiledConsumer; },
    'evidence roles drift', fixtures);
  test('registered-closure-negative-must-kill', l => { const r=registeredClosureFixture(l), ref=r.registeredClosureEvidence.references.negative;
    const n=json(scratch,ref.path); n.status='PASS'; put(ref.path,n); r.registeredClosureEvidence.references.negative=fileRef(scratch,ref.path); },
    'registered central closure negative is not bound', fixtures);
  test('closed-registered-row-pending-consumer', l => { registeredClosureFixture(l).compiledConsumer='Pending'; },
    'closed registered central closure has pending evidence', fixtures);
  test('open-registered-row-with-evidence', l => { reopenRegistered(l).registeredClosureEvidence={status:'PASS_REGISTERED_CENTRAL_CLOSURE'}; },
    'open registered central closure claims completion');
  test('open-registered-row-proof-flag', l => { reopenRegistered(l).proofCompleted=true; },
    'open registered central closure claims completion');
  test('registered-row-contract-field-required', l => { delete row(l,registeredClosureId).reopenCondition; },
    'registered central closure missing reopenCondition');
  test('trust12-complete-flag-forged', l => { l.releaseAssessment.trust12Complete=true; }, 'release readiness drift');
  test('fixture-completion-rejected-in-production', l => { registeredCompletionFixture(l); }, 'uses fixture records');
  const registeredComplete = test('registered-completion-with-fresh-assurance-fixture', l => { registeredCompletionFixture(l); }, null, fixtures);
  check(registeredComplete.trust12Complete===true && registeredComplete.fullRefinementComplete===false
    && registeredComplete.releaseReadiness==='EVIDENCE_READY' && registeredComplete.researchResiduals.length===3,
    'registered completion fixture did not keep the general links deferred');
  test('registered-completion-cannot-claim-full-refinement', l => { registeredCompletionFixture(l);
    l.centralClosure.status='COMPLETE'; l.releaseAssessment.fullRefinementComplete=true; }, 'central completion status drift', fixtures);
  test('registered-completion-needs-current-closure-assurance', l => { registeredCompletionFixture(l,'0'.repeat(64)); },
    'fresh assurance report is not independently reproduced on the final inputs', fixtures);
  test('registered-completion-keeps-end-to-end-incomplete-label', l => { registeredCompletionFixture(l);
    for (const path of disclosures) put(path,documents[path].replaceAll('mapped implementation evidence; end-to-end refinement incomplete','mapped implementation evidence')
      +'\n'+registeredCompletionDisclosure+'\n'); }, 'claim boundary drift', fixtures);
  test('registered-completion-phrase-required-in-every-disclosure', l => { registeredCompletionFixture(l);
    put(disclosures[2],documents[disclosures[2]]); }, 'registered completion disclosure drift', fixtures);
  test('registered-completion-before-assurance-rejected', l => { registeredClosureFixture(l);
    l.centralClosure.status='COMPLETE_REGISTERED_SCOPE'; l.releaseAssessment.trust12Complete=true; }, 'central completion status drift', fixtures);
  test('completion-wording-variant-rejected-while-open', () => { const path='evidence/known-limitations.md';
    put(path,documents[path]+'\nTRUST 1.2 is complete\n'); }, 'registered completion disclosure drift');
  test('policy-schema-v2-rejected', (l,p) => { p.schema='trust12-release-policy-v2'; }, 'release policy schema');
  test('parser-development-cannot-return-to-mandatory', (l,p) => { p.parserDevelopment='ACTIVE_FOR_TRUST12'; },
    'release policy boundary drift');
  test('direction-history-cannot-grow', (l,p) => { p.supersededCompletionDirections.push(structuredClone(p.supersededCompletionDirections[0])); },
    'completion direction history missing');
  test('deferral-date-must-match-direction', l => { row(l,'RESEARCH-RUNTIME-LINK-HOOK').deferral.date='2026-10-05'; },
    'deferral is not the recorded decision');
  test('registered-completion-phrase-rejected-while-open', () => { const path='evidence/claim-matrix.md';
    put(path,documents[path]+'\n'+registeredCompletionDisclosure+'\n'); }, 'registered completion disclosure drift');
  test('general-profile-scope-cannot-be-narrowed', (l,p) => { p.profileScopes.PARTIAL='One fixed fixture only'; },
    'general profile scope missing or narrowed');
  test('general-link-closure-contract-required', l => { delete row(l,'RESEARCH-RUNTIME-LINK-HOOK').reopenCondition; }, 'general runtime link missing reopenCondition');
  test('evidence-less-general-promotion-rejected', l => {
    const r=row(l,'RESEARCH-RUNTIME-LINK-HOOK');r.status='CLOSED';r.proofCompleted=true;
    r.positiveActivation='Fixture-only positive';r.consumerRemovalNegative='Fixture-only negative';
    l.centralClosure.currentMandatory=l.centralClosure.currentMandatory.filter(x=>x!==r.id);
  }, 'general runtime link lacks a verified proof contract');
  test('whole-completion-before-general-rejected', l => {
    l.centralClosure.status='COMPLETE';l.releaseAssessment.fullRefinementComplete=true;
  }, 'central completion status drift');
  test('unadmitted-role-files-cannot-complete', l => {
    nativeProofFixture(l);
    for(const id of ['RESEARCH-RUNTIME-LINK-HOOK','RESEARCH-RUNTIME-LINK-NATIVE','RESEARCH-RUNTIME-LINK-PARTIAL'])
      generalProofFixture(l,id);
    const endToEnd=structuredClone(endToEndBaseline);
    endToEnd.closure.status='COMPLETE';
    for(const r of endToEnd.rows) if(r.status==='SUCCESSOR-MANDATORY') r.status='CLOSED';
    put(endToEndPath,endToEnd);
    l.centralClosure.status='COMPLETE';l.releaseAssessment.status='EVIDENCE_READY';
    l.releaseAssessment.fullRefinementComplete=true;l.status='EVIDENCE_COMPLETE';
  }, 'general runtime link evidence roles or formal receipt drift');
  test('old-or-fabricated-assurance-rejected', l => {
    const path='evidence/trust12/assurance/fixture-audit.json';
    put(path,{schema:'trust12-final-assurance-v1',status:'PASS_FRESH_ASSURANCE',independentOfBuilding:true});
    l.centralClosure.independentAssurance={status:'PASS_FRESH_ASSURANCE',report:fileRef(scratch,path)};
  }, 'fresh assurance report names no input seal');
  test('contradictory-public-completion-rejected', () => {
    const path='evidence/known-limitations.md';
    put(path,documents[path]+'\nend-to-end refinement complete within the declared profiles\n');
  }, 'claim boundary drift');
  test('native-domain-not-narrowed', l => { row(l,'NATIVE-SYMBOLIC-FREEZE').inputDomain+=' and first <= supply'; }, 'native general domain narrowed');
  test('native-proof-original-scope-fixture', l => { nativeProofFixture(l); });
  test('native-narrow-proof-input', l => { nativeProofFixture(l).inputScope='first = second = 1'; }, 'Native proof scope');
  test('native-changed-proof-property', l => { nativeProofFixture(l).property='Only a storage lookup'; }, 'Native proof scope');
  test('native-hidden-supply-assumption', l => { nativeProofFixture(l).notAssumed=''; }, 'Native proof scope');
  test('native-narrow-negative', l => { nativeProofFixture(l).negative.inputScope='first = second = 1'; }, 'Native negative');
  test('native-bounded-behavior-negative', l => { nativeProofFixture(l).negative.kind='BOUNDED_BEHAVIORAL'; }, 'Native negative');
  test('native-one-branch-negative', l => { row(l,'NATIVE-SYMBOLIC-FREEZE').symbolicEvidence.negative.testedBranchPredicates=['first <= SUPPLY']; }, 'Native negative branch coverage');
  test('native-mutant-transaction-promoted', l => { row(l,'NATIVE-SYMBOLIC-FREEZE').symbolicEvidence.negative.wholeMutantTransactionProved=true; }, 'Native negative branch coverage');
  test('native-domain-flag-dropped', l => { row(l,'NATIVE-SYMBOLIC-FREEZE').fullDomainNegativeReceived=false; }, 'Native negative branch coverage');
  test('native-supply-checkpoint-unbound', l => { const n=row(l,'NATIVE-SYMBOLIC-FREEZE').symbolicEvidence.negative;
    n.evidence=n.evidence.filter(ref=>ref.path!=='evidence/trust12/runtime-link/native-supply-direction-negative-checkpoint-v1.json'); }, 'supply-direction checkpoint');
  test('short-tool-pin', (l,p) => { p.toolchain.kevmCommit=p.toolchain.kevmCommit.slice(0,7); }, 'tool pin differs from formal TCB');
  test('swapped-tool-pin', (l,p) => { p.toolchain.kevmCommit=p.toolchain.kCommit; }, 'tool pin differs from formal TCB');
  test('stale-certora-version', (l,p) => { p.toolchain.certora='UNRECORDED'; }, 'Certora tool version');
  test('profile-grade-disclosure-required', () => {
    const path='evidence/trust12/README.md'; put(path, readFileSync(resolve(root,path),'utf8').replace('TRUST 1.2 profile row grades:', 'Removed profile grades:'));
  }, 'profile grade disclosure drift');
  test('bounded-native-not-closed', l => { const r=row(l,'NATIVE-SYMBOLIC-FREEZE'); promoteTests(r.symbolicEvidence);
    r.status='CLOSED'; r.positiveActivation='Fixture'; r.consumerRemovalNegative='Fixture'; }, 'bounded evidence cannot close');
  test('exception-requires-approval', l => { row(l,'NATIVE-SYMBOLIC-FREEZE').status='OPEN-SHIPPING-EXCEPTION';
    l.centralClosure.currentMandatory=l.centralClosure.currentMandatory.filter(x=>x!=='NATIVE-SYMBOLIC-FREEZE');
    l.centralClosure.shippingExceptions=['NATIVE-SYMBOLIC-FREEZE']; }, 'exception must retain unproved scope');
  test('approved-exception-remains-unproven', l => { approvedException(l); });
  test('exception-not-proof', l => { approvedException(l).shippingException.proofCompleted=true; }, 'exception must retain unproved scope');
  test('exception-needs-carryover', l => { delete approvedException(l).shippingException.carryover.resumeCondition; }, 'carryover resumeCondition');
  test('wrong-approver', l => { const r=approvedException(l), a=json(scratch,r.shippingException.approval.path);
    a.approvedBy='Assistant'; put(r.shippingException.approval.path,a);
    r.shippingException.approval=fileRef(scratch,r.shippingException.approval.path); }, 'invalid row-specific shipping approval');
  test('scope-reset-not-exception-approval', l => { const r=approvedException(l);
    r.shippingException.approval=fileRef(scratch,policyPath); }, 'invalid row-specific shipping approval');
  test('exception-disclosure-required', l => { approvedException(l); put(disclosures[1], documents[disclosures[1]]); }, 'missing exception disclosure');
  const ready = test('exception-cannot-bypass-completion', l => {
    approvedException(l);
    for (const p of profiles) { const r=row(l,`RUNTIME-LINK-${p}`); for(const c of r.components) promoteTests(c);
      r.evidenceGrade='EXECUTION_TESTS'; r.status='CLOSED'; r.positiveActivation='Scoped fixture'; r.consumerRemovalNegative='Scoped fixture'; }
    registeredClosureFixture(l);
    l.releaseAssessment.status='ASSURANCE_PENDING'; l.status='EVIDENCE_COMPLETE_WITH_EXCEPTIONS';
  }, null, fixtures);
  check(ready.releaseReadiness==='ASSURANCE_PENDING' && ready.fullRefinementComplete===false && ready.trust12Complete===false
    && ready.shippingExceptions.length===1, 'exception promoted to completion');
  check(!withoutIsabelleComments('(* @{thm fake} (* nested *) *)').includes('@{thm fake}'),
    'comment-only theorem anchor was accepted');
  check(withoutIsabelleComments('text ‹@{thm real}›').includes('@{thm real}'),
    'live theorem antiquotation was removed');
  results.push({name:'comment-only-proof-audit-anchor',status:'REJECTED'});
  const central=structuredClone(endToEndBaseline);
  central.closure.status='COMPLETE';central.closure.profileCoverage=[...profiles];
  for(const r of central.rows) if(r.status==='SUCCESSOR-MANDATORY') r.status='CLOSED';
  for(const a of central.assumptions) if(['A-RUNTIME-LINK','A-RUNTIME-LINK-SPEC'].includes(a.id)) a.status='DISCHARGED';
  check(verifiedCentralCompletion(central)===true, 'complete central fixture rejected');
  results.push({name:'complete-central-fixture',status:'PASS'});
  for(const [name,mutate] of [
    ['native-link-not-applicable', x=>{x.rows.find(r=>r.id==='NAT-E2E-01').status='NOT-APPLICABLE';}],
    ['partial-link-not-applicable', x=>{x.rows.find(r=>r.id==='ADP-E2E-01').status='NOT-APPLICABLE';}],
    ['runtime-assumption-undischarged', x=>{x.assumptions.find(a=>a.id==='A-RUNTIME-LINK').status='UNDISCHARGED';}],
    ['hook-profile-omitted', x=>{x.closure.profileCoverage=['NATIVE','PARTIAL'];}],
  ]) {
    const mutant=structuredClone(central);mutate(mutant);
    check(verifiedCentralCompletion(mutant)===false, `${name}: central completion false positive`);
    results.push({name,status:'REJECTED'});
  }
  const report={status:'PASS',controls:results,nonclaim:'Isolated validator fixtures only. No product proof or shipping approval was created.'};
  writeFileSync(resolve(out,'policy-controls.json'),encoded(report));
  console.log(JSON.stringify({status:'PASS',controls:results.length},null,2));
} finally {
  const rel=relative(out,scratch); check(rel.startsWith('policy-controls-')&&!rel.includes('/')&&!rel.includes('\\'), 'unsafe fixture cleanup');
  rmSync(scratch,{recursive:true,force:true});
}
