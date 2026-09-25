// SPDX-License-Identifier: BSD-3-Clause
// Isolated policy controls: fixture successes are not product evidence or approvals.
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { dirname, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { check, encoded, fileRef, json } from './lib/local-evidence.mjs';
import { components, disclosures, implementationDisclosures, profiles, verifiedCentralCompletion, verifyTrust12Policy, withoutIsabelleComments } from './lib/trust12-policy.mjs';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const out = resolve(root, 'out/trust12');
mkdirSync(out, { recursive: true });
const scratch = mkdtempSync(resolve(out, 'policy-controls-'));
const policyPath = 'evidence/trust12/release-policy.json', ledgerPath = 'evidence/trust12/obligation-ledger.json';
const policy = json(root, policyPath), baseline = json(root, ledgerPath), results = [];
const endToEndPath = 'evidence/end-to-end-refinement/obligation-ledger-v3.json';
const endToEndBaseline = json(root, endToEndPath);
function put(path, value) {
  mkdirSync(dirname(resolve(scratch, path)), { recursive: true });
  writeFileSync(resolve(scratch, path), typeof value === 'string' || Buffer.isBuffer(value) ? value : encoded(value));
}
const refs = new Map();
function collect(value) {
  if (!value || typeof value !== 'object') return;
  if (typeof value.path === 'string' && typeof value.sha256 === 'string') refs.set(value.path, value);
  for (const v of Object.values(value)) collect(v);
}
collect(policy); collect(baseline);
for (const path of new Set([...refs.keys(), 'evidence/trust12/symbolic-kontrol.json',
  'evidence/end-to-end-refinement/obligation-ledger-v3.json',
  'evidence/isabelle-results-v3.json', 'evidence/trust12/runtime-identity.json',
  'spec/generated/kernel-v2-abi.json',
  'evidence/certora-results-v3.json', ...implementationDisclosures]))
  put(path, readFileSync(resolve(root, path)));
const documents = Object.fromEntries(implementationDisclosures.map(path => [path, readFileSync(resolve(root, path), 'utf8')]));
function reset() {
  put(policyPath, policy); put(ledgerPath, baseline);
  put(endToEndPath, endToEndBaseline);
  for (const [path, text] of Object.entries(documents)) put(path, text);
}
function test(name, mutate, expected = null) {
  reset(); const ledger = structuredClone(baseline), p = structuredClone(policy);
  mutate(ledger, p); put(ledgerPath, ledger); put(policyPath, p);
  let error, report;
  try { report = verifyTrust12Policy(scratch); } catch (e) { error = e.message; }
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
  ledger.releaseAssessment.status='PENDING'; ledger.status='IN_PROGRESS';
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
  Object.assign(e.negative,{kind:'KILLED_CONSUMER_REMOVAL',inputScope:r.inputDomain,notAssumed:r.notAssumed,coversDeclaredScope:true});
  r.status='CLOSED';r.positiveActivation='Test-only full scope';r.consumerRemovalNegative='Test-only same-domain removal';
  ledger.centralClosure.currentMandatory=ledger.centralClosure.currentMandatory.filter(id=>id!==r.id);
  ledger.releaseAssessment.status='PENDING'; ledger.status='IN_PROGRESS';
  return e;
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
  test('current-open-policy', () => {});
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
  test('general-link-cannot-be-residual', l => { row(l,'RESEARCH-RUNTIME-LINK-HOOK').status='RESEARCH-RESIDUAL'; }, 'unknown status');
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
  }, 'fresh assurance report is not independently reproduced on the final inputs');
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
  const ready = test('exception-cannot-bypass-general-refinement', l => {
    approvedException(l);
    for (const p of profiles) { const r=row(l,`RUNTIME-LINK-${p}`); for(const c of r.components) promoteTests(c);
      r.evidenceGrade='EXECUTION_TESTS'; r.status='CLOSED'; r.positiveActivation='Scoped fixture'; r.consumerRemovalNegative='Scoped fixture'; }
    l.releaseAssessment.status='PENDING'; l.status='IN_PROGRESS';
  });
  check(ready.releaseReadiness==='PENDING' && ready.fullRefinementComplete===false, 'exception promoted to full refinement');
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
