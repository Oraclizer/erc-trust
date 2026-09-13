// SPDX-License-Identifier: BSD-3-Clause
// Isolated policy controls: fixture successes are not product evidence or approvals.
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { dirname, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { check, encoded, fileRef, json } from './lib/local-evidence.mjs';
import { components, disclosures, profiles, verifyTrust12Policy } from './lib/trust12-policy.mjs';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const out = resolve(root, 'out/trust12');
mkdirSync(out, { recursive: true });
const scratch = mkdtempSync(resolve(out, 'policy-controls-'));
const policyPath = 'evidence/trust12/release-policy.json', ledgerPath = 'evidence/trust12/obligation-ledger.json';
const policy = json(root, policyPath), baseline = json(root, ledgerPath), results = [];
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
for (const path of new Set([...refs.keys(), 'evidence/trust12/symbolic-kontrol.json', ...disclosures]))
  put(path, readFileSync(resolve(root, path)));
const documents = Object.fromEntries(disclosures.map(path => [path, readFileSync(resolve(root, path), 'utf8')]));
function reset() {
  put(policyPath, policy); put(ledgerPath, baseline);
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
  for (const [path, text] of Object.entries(documents))
    put(path, text.replace('TRUST 1.2 shipping exceptions: none.', r.shippingException.disclosure));
  return r;
}
function nativeProofFixture(ledger) {
  const r=row(ledger,'NATIVE-SYMBOLIC-FREEZE'), e=r.symbolicEvidence;
  promoteTests(e);
  Object.assign(e,{evidenceGrade:'FULL_SCOPE_PROOF',property:r.abstractCondition,inputScope:r.inputDomain,notAssumed:r.notAssumed,
    result:{tool:'Kontrol/KEVM',kind:'PROOF',status:'PASS',unresolvedGoals:0,admittedGoals:0,vacuous:false,
      claimIds:['test-only-general-claim'],coversDeclaredScope:true}});
  Object.assign(e.negative,{kind:'KILLED_CONSUMER_REMOVAL',inputScope:r.inputDomain,notAssumed:r.notAssumed,coversDeclaredScope:true});
  r.status='CLOSED';r.positiveActivation='Test-only full scope';r.consumerRemovalNegative='Test-only same-domain removal';
  ledger.centralClosure.currentMandatory=ledger.centralClosure.currentMandatory.filter(id=>id!==r.id);
  return e;
}
try {
  test('current-open-policy', () => {});
  test('unknown-state', l => { row(l).status = 'PASS'; }, 'unknown status');
  test('missing-component', l => row(l).components.pop(), 'exactly seven');
  test('duplicate-component', l => { row(l).components[1].id = components[0]; }, 'exactly seven');
  test('grade-inflation', l => { row(l).evidenceGrade = 'FULL_SCOPE_PROOF'; }, 'weakest component');
  test('test-is-not-proof', l => { const r = row(l); for (const c of r.components) promoteTests(c);
    r.evidenceGrade = 'FULL_SCOPE_PROOF'; }, 'weakest component');
  test('one-unverified-prevents-closure', l => { const r = row(l); r.status='CLOSED';
    r.positiveActivation='Completed fixture'; r.consumerRemovalNegative='Completed fixture'; }, 'unreviewed mandatory obligation removal');
  test('missing-positive', l => { const c = row(l).components[0]; promoteTests(c); c.evidence=[]; }, 'lacks bound evidence');
  test('stale-artifact', l => { const c = row(l).components[0]; promoteTests(c);
    c.artifactBindings=[{...c.artifactBindings[0],sha256:'0'.repeat(64)}]; }, 'compiled artifact reference drift');
  test('missing-negative', l => { const c = row(l).components[0]; promoteTests(c); c.negative.kind='UNVERIFIED'; }, 'lacks negative evidence');
  test('timeout-not-proof', l => { const c = row(l).components[0]; promoteTests(c); c.evidenceGrade='FULL_SCOPE_PROOF';
    c.result={tool:'Kontrol/KEVM',kind:'PROOF',status:'TIMEOUT'}; }, 'no PASS result');
  test('unresolved-not-proof', l => { const c = row(l).components[0]; promoteTests(c); c.evidenceGrade='FULL_SCOPE_PROOF';
    c.result={tool:'Kontrol/KEVM',kind:'PROOF',status:'PASS',unresolvedGoals:1}; }, 'completed nonvacuous proof');
  test('research-stays-open', l => { row(l,'RESEARCH-RUNTIME-LINK-HOOK').status='CURRENT-MANDATORY'; }, 'runtime research residual');
  test('research-carryover-required', l => { delete row(l,'RESEARCH-RUNTIME-LINK-HOOK').reopenCondition; }, 'research residual missing reopenCondition');
  test('native-domain-not-narrowed', l => { row(l,'NATIVE-SYMBOLIC-FREEZE').inputDomain+=' and first <= supply'; }, 'native general domain narrowed');
  test('native-proof-original-scope-fixture', l => { nativeProofFixture(l); });
  test('native-narrow-proof-input', l => { nativeProofFixture(l).inputScope='first = second = 1'; }, 'Native proof scope');
  test('native-changed-proof-property', l => { nativeProofFixture(l).property='Only a storage lookup'; }, 'Native proof scope');
  test('native-hidden-supply-assumption', l => { nativeProofFixture(l).notAssumed=''; }, 'Native proof scope');
  test('native-narrow-negative', l => { nativeProofFixture(l).negative.inputScope='first = second = 1'; }, 'Native negative');
  test('native-bounded-behavior-negative', l => { nativeProofFixture(l).negative.kind='BOUNDED_BEHAVIORAL'; }, 'Native negative');
  test('short-tool-pin', (l,p) => { p.toolchain.kevmCommit=p.toolchain.kevmCommit.slice(0,7); }, 'tool pin differs from formal TCB');
  test('swapped-tool-pin', (l,p) => { p.toolchain.kevmCommit=p.toolchain.kCommit; }, 'tool pin differs from formal TCB');
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
  const ready = test('ready-with-exception-not-full-refinement', l => {
    approvedException(l);
    for (const p of profiles) { const r=row(l,`RUNTIME-LINK-${p}`); for(const c of r.components) promoteTests(c);
      r.evidenceGrade='EXECUTION_TESTS'; r.status='CLOSED'; r.positiveActivation='Scoped fixture'; r.consumerRemovalNegative='Scoped fixture'; }
    l.centralClosure.currentMandatory=[]; l.releaseAssessment.status='READY_WITH_EXCEPTIONS'; l.status='EVIDENCE_COMPLETE_WITH_EXCEPTIONS';
  });
  check(ready.releaseReadiness==='READY_WITH_EXCEPTIONS' && ready.fullRefinementComplete===false, 'exception promoted to full refinement');
  const report={status:'PASS',controls:results,nonclaim:'Isolated validator fixtures only. No product proof or shipping approval was created.'};
  writeFileSync(resolve(out,'policy-controls.json'),encoded(report));
  console.log(JSON.stringify({status:'PASS',controls:results.length},null,2));
} finally {
  const rel=relative(out,scratch); check(rel.startsWith('policy-controls-')&&!rel.includes('/')&&!rel.includes('\\'), 'unsafe fixture cleanup');
  rmSync(scratch,{recursive:true,force:true});
}
