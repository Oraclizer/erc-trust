// SPDX-License-Identifier: BSD-3-Clause
// Semantic controls for evidence admission. These are not implementation mutations.
import { execFileSync, spawnSync } from 'node:child_process';
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { check, encoded, json, sha256 } from './lib/local-evidence.mjs';
import { formalIdentity } from './lib/formal-inputs.mjs';
import { verifyTrust12Required } from './verify-trust12-required.mjs';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..'), output = resolve(root,'out/trust12');
const scratch = mkdtempSync(resolve(output,'required-controls-'));
const files = execFileSync('git',['ls-files','--cached','--others','--exclude-standard','-z'],{cwd:root,encoding:'utf8'}).split('\0').filter(Boolean);
for (const path of files) { mkdirSync(dirname(resolve(scratch,path)),{recursive:true}); copyFileSync(resolve(root,path),resolve(scratch,path)); }
const saved = new Map(), results = [];
function set(path, value) {
  if (!saved.has(path)) saved.set(path,existsSync(resolve(scratch,path)) ? readFileSync(resolve(scratch,path)) : null);
  if (value === null) rmSync(resolve(scratch,path));
  else writeFileSync(resolve(scratch,path),Buffer.isBuffer(value) ? value : encoded(value));
}
function change(path, mutate) { const value = json(scratch,path); mutate(value); set(path,value); }
function reseal() { change('evidence/trust12/input-seal.json',seal=>{for(const item of seal.files) if(existsSync(resolve(scratch,item.path))) item.sha256=sha256(readFileSync(resolve(scratch,item.path)));}); }
function rebindFoundrySource() { change('evidence/foundry-results-v3.json',receipt=>{receipt.run.source.sha256=sha256(readFileSync(resolve(scratch,receipt.run.source.path)));receipt.run.commands=json(scratch,receipt.run.source.path).commands;}); }
function test(name, mutate, expected, entrypoint = null) {
  try {
    mutate(); reseal(); let reason;
    if (entrypoint) { const run=spawnSync(process.execPath,[resolve(scratch,`scripts/${entrypoint}.mjs`)],{encoding:'utf8'});reason=`${run.stdout??''}${run.stderr??''}`;check(run.status!==0,'negative entrypoint unexpectedly passed'); }
    else { try { verifyTrust12Required(scratch); } catch(error) { reason=error.message; } }
    check(reason?.includes(expected),`${name}: expected ${expected}, observed ${reason??'PASS'}`);
    results.push({name,status:'REJECTED',reason:expected});
  } finally { for(const [path,bytes] of saved) { if(bytes===null) rmSync(resolve(scratch,path),{force:true});else writeFileSync(resolve(scratch,path),bytes); } saved.clear(); }
}
try {
  verifyTrust12Required(scratch);
  for(const path of ['evidence/trust12/formal-build-replay.json','evidence/trust12/local-validation.json','evidence/trust12/independent-audit.md','evidence/trust12/mutation-inbound.json']) test(`missing-required:${path}`,()=>{set(path,null);change('evidence/trust12/input-seal.json',s=>{s.files=s.files.filter(x=>x.path!==path);});},'required TRUST 1.2 input is not sealed');
  for(const path of ['formal/isabelle/ERC_TRUST/TRUST_Transaction_Refinement.thy','formal/isabelle/TRUST12_OBSTRUCTIONS/TRUST_State_Invariants.thy','formal/isabelle/ERC_TRUST/ROOT','formal/isabelle/TRUST12_OBSTRUCTIONS/ROOT','formal/isabelle/ROOTS','formal-dependencies-public-v1.lock.json']) test(`changed-formal:${path}`,()=>set(path,Buffer.concat([readFileSync(resolve(scratch,path)),Buffer.from('\n ')])),'local input inventory drift');
  test('paired-formal-receipt-drift',()=>{
    const path='formal/isabelle/TRUST12_OBSTRUCTIONS/TRUST_State_Invariants.thy';
    set(path,Buffer.concat([readFileSync(resolve(scratch,path)),Buffer.from('\n(* paired drift *)\n')]));
    const identity=formalIdentity(scratch);
    change('evidence/trust12/formal-build-replay.json',r=>{r.formalSource=identity;});
    change('evidence/isabelle-results-v3.json',r=>{r.formalSource=identity;r.run.sourceInputs=identity.inputs;r.run.sourceRootSha256=identity.rootSha256;r.run.source.sha256=sha256(readFileSync(resolve(scratch,r.run.source.path)));});
  },'formal inputs differ from the admitted clean build');
  test('missing-whole-hook-compiler-bundle',()=>{
    change('evidence/runtime-binding-v3.json',r=>{r.bundles=r.bundles.filter(b=>b.id!=='erc3643-hook');});
    for(const name of ['standard-json-input','source-identities','bridge-artifacts'])set(`evidence/runtime-binding-v3/erc3643-hook/${name}.json`,null);
  },'required compiler bundle inventory missing');
  test('missing-hook-bundle-file-reference',()=>change('evidence/runtime-binding-v3.json',r=>{r.bundles.find(b=>b.id==='erc3643-hook').files.pop();}),'required compiler bundle files missing');
  test('paired-dependency-receipt-drift',()=>{
    change('evidence/trust12/formal-build-replay.json',r=>{r.dependencyInputs.adsFunctor[0].sha256='0'.repeat(64);});
    change('evidence/isabelle-results-v3.json',r=>{r.run.dependencyInputs=json(scratch,r.run.source.path).dependencyInputs;r.run.source.sha256=sha256(readFileSync(resolve(scratch,r.run.source.path)));});
  },'admitted execution or dependency evidence drift');
  test('missing-child-session',()=>change('evidence/isabelle-results-v3.json',r=>r.sessions.pop()),'local Isabelle session/dependency provenance mismatch');
  test('failed-clean-build',()=>change('evidence/isabelle-results-v3.json',r=>{r.checks.cleanBuild='FAIL';}),'required clean proof build/export failed');
  test('failed-export',()=>change('evidence/isabelle-results-v3.json',r=>{r.checks.proofExport='FAIL';}),'required clean proof build/export failed');
  test('zero-test-summary',()=>change('evidence/foundry-results-v3.json',r=>{r.checks.tests.passed=0;}),'required named Foundry test set or results drift');
  test('missing-hook-test',()=>change('evidence/foundry-results-v3.json',r=>{r.testInventory=r.testInventory.filter(t=>!t.test.startsWith('testHookInboundCannotEscape'));r.checks.tests.passed=r.testInventory.length;}),'required named Foundry test set or results drift');
  test('local-claims-ci-workflow',()=>change('evidence/foundry-results-v3.json',r=>{r.workflow={runId:1,jobId:1,jobConclusion:'success'};}),'local receipt cannot assert CI');
  test('forged-local-provider',()=>change('evidence/foundry-results-v3.json',r=>{r.provider='github-actions';}),'local receipt cannot assert CI');
  test('rewritten-local-commit',()=>change('evidence/foundry-results-v3.json',r=>{r.sourceCommit='0'.repeat(40);}),'local provider or execution commit mismatch');
  test('failed-exit-with-rehashed-provenance',()=>{change('evidence/trust12/local-validation.json',r=>{r.commands[0].exitCode=1;});rebindFoundrySource();},'local Foundry command failed');
  test('backwards-time-with-rehashed-provenance',()=>{change('evidence/trust12/local-validation.json',r=>{r.commands[0].finishedAt='2000-01-01T00:00:00Z';});rebindFoundrySource();},'local Foundry command failed');
  test('rewritten-deterministic-execution',()=>change('evidence/deterministic-build.json',r=>{r.candidateInput.gitHead='0'.repeat(40);}),'deterministic execution identity was rewritten');
  test('false-symbolic-pass',()=>change('evidence/trust12/symbolic-kontrol.json',r=>{r.status='PASS';}),'symbolic scope or source drift');
  test('narrowed-symbolic-domain',()=>change('evidence/trust12/symbolic-kontrol.json',r=>{r.target.inputDomain+=' and first <= supply';}),'symbolic input domain narrowed');
  test('false-mandatory-closure',()=>change('evidence/trust12/obligation-ledger.json',r=>{r.obligations.find(x=>x.id==='RUNTIME-LINK-HOOK').status='CLOSED';r.centralClosure.currentMandatory=r.centralClosure.currentMandatory.filter(x=>x!=='RUNTIME-LINK-HOOK');}),'unreviewed mandatory obligation removal');
  test('release-with-open-obligations',()=>change('evidence/evidence-mode.json',r=>{r.mode='release';r.pendingAllowed=false;}),'open TRUST 1.2 obligations prohibit release');
  for(const entrypoint of ['verify-current-profile-release-v3','verify-obligation-ledger-v3','verify-runtime-binding-v3']) test(`required-consumer:${entrypoint}`,()=>{const path='evidence/trust12/formal-build-replay.json';set(path,null);change('evidence/trust12/input-seal.json',s=>{s.files=s.files.filter(x=>x.path!==path);});},'required TRUST 1.2 input is not sealed',entrypoint);
  const report={schema:'trust12-required-controls-v1',status:'PASS',positive:'PASS_CONSISTENT_DEVELOPMENT',negativeControls:results,
    source:{verifierSha256:sha256(readFileSync(resolve(root,'scripts/verify-trust12-required.mjs'))),testSha256:sha256(readFileSync(fileURLToPath(import.meta.url)))},
    nonclaim:'Admission and required-consumer controls. No new implementation mutation campaign, symbolic theorem or runtime refinement is claimed.'};
  writeFileSync(resolve(output,'required-controls.json'),encoded(report));
  console.log(JSON.stringify({status:'PASS',positive:report.positive,negativeControls:results.length},null,2));
} finally { const rel=relative(output,scratch);check(rel&&!rel.startsWith('..')&&!rel.includes(sep)&&rel.startsWith('required-controls-'),'unsafe fixture cleanup');rmSync(scratch,{recursive:true,force:true}); }
