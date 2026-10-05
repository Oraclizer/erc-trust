// SPDX-License-Identifier: BSD-3-Clause
// Semantic controls for evidence admission. These are not implementation mutations.
import { execFileSync, spawnSync } from 'node:child_process';
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { check, encoded, json, sha256 } from './lib/local-evidence.mjs';
import { formalIdentity } from './lib/formal-inputs.mjs';
import { verifyRuntimeBundles } from './lib/runtime-bundles.mjs';
import { verifyTrust12Required } from './verify-trust12-required.mjs';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..'), output = resolve(root,'out/trust12');
mkdirSync(output,{recursive:true});
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
function test(name, mutate, expected, entrypoint = null, directVerifier = null) {
  try {
    mutate(); reseal(); let reason;
    if (directVerifier) { try { directVerifier(scratch); } catch(error) { reason=error.message; } }
    else if (entrypoint) { const run=spawnSync(process.execPath,[resolve(scratch,`scripts/${entrypoint}.mjs`)],{encoding:'utf8'});reason=`${run.stdout??''}${run.stderr??''}`;check(run.status!==0,'negative entrypoint unexpectedly passed'); }
    else { try { verifyTrust12Required(scratch); } catch(error) { reason=error.message; } }
    check(reason?.includes(expected),`${name}: expected ${expected}, observed ${reason??'PASS'}`);
    results.push({name,status:'REJECTED',reason:expected});
  } finally { for(const [path,bytes] of saved) { if(bytes===null) rmSync(resolve(scratch,path),{force:true});else writeFileSync(resolve(scratch,path),bytes); } saved.clear(); }
}
try {
  execFileSync(process.execPath,[resolve(root,'scripts/test-trust12-policy.mjs')],{stdio:'pipe'});
  verifyTrust12Required(scratch);
  for(const path of ['scripts/test-typed-failure-binding.py','scripts/trust12/verify_typed_failure_binding_v1.py','scripts/trust12/tail-preparation/typed_failure_report.py','scripts/trust12/tail-preparation/run_typed_failure_probe.py','scripts/trust12/tail-preparation/code_identity_v2.py','scripts/trust12/tail-preparation/test_typed_failure_binding.py','scripts/trust12/tail-preparation/typed-failure-probe/TypedFailureProbeCore.sol','scripts/trust12/tail-preparation/typed-failure-probe/NativeTypedFailureProbe.t.sol','scripts/trust12/tail-preparation/typed-failure-probe/PartialTypedFailureProbe.t.sol','scripts/trust12/tail-preparation/typed-failure-probe/HookTypedFailureProbe.t.sol','evidence/trust12/runtime-link/tail-preparation/typed-failure-probe-mutants-v1.json','evidence/trust12/runtime-link/tail-preparation/typed-failure-checkpoint-v1.json','scripts/test-route-inventory.py','scripts/trust12/verify_route_inventory_v1.py','scripts/trust12/tail-preparation/route_inventory_v2.py','scripts/trust12/tail-preparation/run_route_disposition_tests.py','scripts/trust12/tail-preparation/test_route_inventory_v2.py','scripts/trust12/tail-preparation/route-dispositions/HookRouteDispositions.t.sol','scripts/trust12/tail-preparation/route-dispositions/NativeAllowanceRoutes.t.sol','spec/decisions/14-hook-route-classes.md','spec/decisions/15-route-dispositions.md','spec/generated/hook-route-classes-v1.json','evidence/trust12/runtime-link/tail-preparation/route-dispositions-v1.json','evidence/trust12/runtime-link/tail-preparation/route-inventory-checkpoint-v1.json','scripts/test-certificate-registry.py','scripts/trust12/verify_certificate_registry_v1.py','scripts/trust12/tail-preparation/certificate_registry_v2.py','scripts/trust12/tail-preparation/kore_accounts.py','scripts/trust12/tail-preparation/test_certificate_registry_v2.py','evidence/trust12/runtime-link/tail-preparation/certificate-registry-schema-v2.json','evidence/trust12/runtime-link/tail-preparation/certificate-registry-checkpoint-v1.json','scripts/test-malformed-aligned-gate.py','scripts/trust12/verify_malformed_aligned_gate_v1.py','evidence/trust12/runtime-link/malformed/aligned-gate-checkpoint-v1.json','scripts/trust12/verify_malformed_call_trace_v1.py','scripts/test-malformed-call-trace.py','scripts/trust12/tail-preparation/malformed_call_trace.py','scripts/trust12/tail-preparation/test_malformed_call_trace.py','evidence/trust12/runtime-link/malformed/call-trace-checkpoint-v1.json','scripts/trust12/verify_reflection_scan_v1.py','scripts/test-reflection-scan.py','scripts/trust12/tail-preparation/reflection_scan.py','scripts/trust12/tail-preparation/test_reflection_scan.py','evidence/trust12/runtime-link/tail-preparation/reflection-dispositions-v1.json','evidence/trust12/runtime-link/tail-preparation/reflection-scan-checkpoint-v1.json','scripts/trust12/verify_storage_reader_v1.py','scripts/test-storage-reader.py','scripts/trust12/tail-preparation/storage_reader.py','scripts/trust12/tail-preparation/test_storage_reader.py','evidence/trust12/runtime-link/tail-preparation/storage-reader-checkpoint-v1.json','scripts/trust12/verify_registered_gate_v1.py','scripts/test-registered-gate.py','scripts/trust12/tail-preparation/test_registered_gate.py','evidence/trust12/runtime-link/tail-preparation/registered-gate-checkpoint-v1.json','scripts/trust12/verify_malformed_guard_mutants_v1.py','scripts/test-malformed-guard-mutants.py','scripts/trust12/tail-preparation/run_malformed_probe_v2.py','evidence/trust12/runtime-link/tail-preparation/malformed-probe-mutants-v1.json','evidence/trust12/runtime-link/tail-preparation/malformed-guard-mutants-checkpoint-v1.json','scripts/trust12/verify_malformed_word_guard_mutants_v1.py','scripts/test-malformed-word-guard-mutants.py','scripts/trust12/tail-preparation/word_guard_mutation.py','scripts/trust12/tail-preparation/run_word_guard_probe.py','scripts/trust12/tail-preparation/test_word_guard_mutation.py','scripts/trust12/tail-preparation/word-guard-probe/WordGuardProbeCore.sol','scripts/trust12/tail-preparation/word-guard-probe/NativeWordGuardProbe.t.sol','scripts/trust12/tail-preparation/word-guard-probe/PartialWordGuardProbe.t.sol','scripts/trust12/tail-preparation/word-guard-probe/HookWordGuardProbe.t.sol','evidence/trust12/runtime-link/tail-preparation/malformed-word-guard-mutants-v1.json','evidence/trust12/runtime-link/tail-preparation/malformed-word-guard-mutants-checkpoint-v1.json','scripts/test-second-freeze-rejection.py','scripts/trust12/verify_second_freeze_rejection_v1.py','evidence/trust12/runtime-link/second-freeze-rejection-checkpoint-v1.json','scripts/test-dependency-call-provenance.py','scripts/trust12/verify_dependency_call_provenance_v1.py','evidence/trust12/runtime-link/dependency-call-provenance-checkpoint-v1.json','scripts/test-assess-call-reception.py','scripts/trust12/verify_assess_call_reception_v1.py','evidence/trust12/runtime-link/assess-call-reception-checkpoint-v1.json','scripts/test-native-supply-direction-negative.py','scripts/trust12/verify_native_supply_direction_negative_v1.py','evidence/trust12/runtime-link/native-supply-direction-negative-checkpoint-v1.json','scripts/test-original-binding-meaning.py','scripts/trust12/verify_original_binding_meaning_v1.py','evidence/trust12/runtime-link/original-binding-meaning-checkpoint-v1.json','scripts/test-primitive-source-controls.py','scripts/trust12/verify_primitive_source_controls_v1.py','evidence/trust12/runtime-link/primitive-source-controls-checkpoint-v1.json','scripts/test-received-transaction-controls.py','scripts/trust12/verify_received_transaction_controls_v1.py','evidence/trust12/runtime-link/received-transaction-controls-checkpoint-v1.json','scripts/test-model-source-reception.py','scripts/trust12/verify_model_source_reception_v1.py','evidence/trust12/runtime-link/model-source-reception-checkpoint-v1.json','evidence/trust12/formal-build-replay.json','evidence/trust12/local-validation.json','evidence/trust12/independent-audit.md','evidence/trust12/mutation-inbound.json','evidence/trust12/model-results.json','evidence/trust12/model-preservation-audit.md','evidence/trust12/linked-controls-audit.md','evidence/trust12/model-source-normalization.json','evidence/trust12/runtime-producer-feasibility.json']) test(`missing-required:${path}`,()=>{set(path,null);change('evidence/trust12/input-seal.json',s=>{s.files=s.files.filter(x=>x.path!==path);});},'required TRUST 1.2 input is not sealed');
  for(const path of ['formal/isabelle/ERC_TRUST/TRUST_Transaction_Refinement.thy','formal/isabelle/TRUST12_OBSTRUCTIONS/TRUST_State_Invariants.thy','formal/isabelle/ERC_TRUST/ROOT','formal/isabelle/TRUST12_OBSTRUCTIONS/ROOT','formal/isabelle/ROOTS','formal-dependencies-public-v1.lock.json','formal/isabelle/TRUST12_OBSTRUCTIONS/TRUST_Linked_Run.thy','formal/isabelle/TRUST12_OBSTRUCTIONS/TRUST_State_Interaction_Controls.thy','scripts/generate-trust12-proof-audit.py','scripts/capture-isabelle-local-inputs.mjs','scripts/lib/formal-inputs.mjs','scripts/proof-ci.mjs','scripts/run-proof-ci.sh','scripts/test-proof-ci.mjs','formal/isabelle/ERC_TRUST/evidence/model-verification/run-trust-closure.ps1']) test(`changed-formal:${path}`,()=>set(path,Buffer.concat([readFileSync(resolve(scratch,path)),Buffer.from('\n ')])),'local input inventory drift');
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
  },'required compiler bundle inventory missing',null,(fixture)=>verifyRuntimeBundles(fixture,json(fixture,'evidence/runtime-binding-v3.json')));
  test('missing-hook-bundle-file-reference',()=>change('evidence/runtime-binding-v3.json',r=>{r.bundles.find(b=>b.id==='erc3643-hook').files.pop();}),'required compiler bundle files missing',null,(fixture)=>verifyRuntimeBundles(fixture,json(fixture,'evidence/runtime-binding-v3.json')));
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
  test('rewritten-model-execution',()=>change('evidence/trust12/model-results.json',r=>{r.executionCommit='0'.repeat(40);}),'unreviewed model result promotion');
  test('removed-model-state-link-control',()=>change('evidence/trust12/model-results.json',r=>{r.groups.linkedNegative=r.groups.linkedNegative.filter(x=>x!=='state_link_removal_accepts_spliced_steps');}),'unreviewed model result promotion');
  test('false-model-runtime-discharge',()=>change('evidence/trust12/model-results.json',r=>{r.nonclaims.runtimeLinkDischarged=true;}),'unreviewed model result promotion');
  test('paired-model-review-drift',()=>{
    const path='evidence/trust12/linked-controls-audit.md';
    set(path,Buffer.concat([readFileSync(resolve(scratch,path)),Buffer.from('\nChanged review.\n')]));
    change('evidence/trust12/model-results.json',r=>{r.sourceReviews.linkedRun.sha256=sha256(readFileSync(resolve(scratch,path)));});
  },'unreviewed model result promotion');
  test('false-feasibility-completion',()=>change('evidence/trust12/runtime-producer-feasibility.json',r=>{r.status='FEASIBLE';r.executionBoundary.runtimeLinkDischarged=true;}),'feasibility inspection cannot discharge runtime link');
  test('false-booster-pass',()=>change('evidence/trust12/symbolic-booster.json',r=>{r.status='PASS';r.prove.exitCode=0;}),'unreviewed Booster proof result promotion');
  test('false-symbolic-pass',()=>change('evidence/trust12/symbolic-kontrol.json',r=>{r.status='PASS';}),'symbolic scope or source drift');
  test('narrowed-symbolic-domain',()=>change('evidence/trust12/symbolic-kontrol.json',r=>{r.target.inputDomain+=' and first <= supply';}),'symbolic input domain narrowed');
  test('false-mandatory-closure',()=>change('evidence/trust12/obligation-ledger.json',r=>{const n=r.obligations.find(x=>x.id==='NATIVE-SYMBOLIC-FREEZE');n.status='CLOSED';n.symbolicEvidence.negative.coversDeclaredScope=false;r.centralClosure.currentMandatory=r.centralClosure.currentMandatory.filter(x=>x!=='NATIVE-SYMBOLIC-FREEZE');}),'Native negative does not cover original input domain');
  test('release-with-open-obligations',()=>change('evidence/evidence-mode.json',r=>{r.mode='release';r.pendingAllowed=false;}),'open TRUST 1.2 obligations prohibit release');
  for(const entrypoint of ['verify-current-profile-release-v3','verify-obligation-ledger-v3','verify-runtime-binding-v3']) test(`required-consumer:${entrypoint}`,()=>{const path='evidence/trust12/formal-build-replay.json';set(path,null);change('evidence/trust12/input-seal.json',s=>{s.files=s.files.filter(x=>x.path!==path);});},'required TRUST 1.2 input is not sealed',entrypoint);
  const checkpointControls = spawnSync(process.env.PYTHON ?? (process.platform === 'win32' ? 'python' : 'python3'),
    ['-B', resolve(root, 'scripts/test-full-source-admission.py')], { cwd: root, encoding: 'utf8' });
  check(!checkpointControls.error && checkpointControls.status === 0, 'captured-source metadata controls failed');
  const modelCheckpointControls = spawnSync(process.env.PYTHON ?? (process.platform === 'win32' ? 'python' : 'python3'),
    ['-B', resolve(root, 'scripts/test-model-source-reception.py')], { cwd: root, encoding: 'utf8' });
  check(!modelCheckpointControls.error && modelCheckpointControls.status === 0, 'model-source metadata controls failed');
  const bindingMeaningControls = spawnSync(process.env.PYTHON ?? (process.platform === 'win32' ? 'python' : 'python3'),
    ['-B', resolve(root, 'scripts/test-original-binding-meaning.py')], { cwd: root, encoding: 'utf8' });
  check(!bindingMeaningControls.error && bindingMeaningControls.status === 0, 'original-binding-meaning metadata controls failed');
  const assessCallControls = spawnSync(process.env.PYTHON ?? (process.platform === 'win32' ? 'python' : 'python3'),
    ['-B', resolve(root, 'scripts/test-assess-call-reception.py')],
    { cwd: root, encoding: 'utf8' });
  check(!assessCallControls.error && assessCallControls.status === 0, 'assess-call-reception metadata controls failed');
  const supplyNegativeControls = spawnSync(process.env.PYTHON ?? (process.platform === 'win32' ? 'python' : 'python3'),
    ['-B', resolve(root, 'scripts/test-native-supply-direction-negative.py')],
    { cwd: root, encoding: 'utf8' });
  check(!supplyNegativeControls.error && supplyNegativeControls.status === 0, 'native-supply-direction-negative metadata controls failed');
  const dependencyCallControls = spawnSync(process.env.PYTHON ?? (process.platform === 'win32' ? 'python' : 'python3'),
    ['-B', resolve(root, 'scripts/test-dependency-call-provenance.py')],
    { cwd: root, encoding: 'utf8' });
  check(!dependencyCallControls.error && dependencyCallControls.status === 0, 'dependency-call-provenance metadata controls failed');
  const secondFreezeControls = spawnSync(process.env.PYTHON ?? (process.platform === 'win32' ? 'python' : 'python3'),
    ['-B', resolve(root, 'scripts/test-second-freeze-rejection.py')],
    { cwd: root, encoding: 'utf8' });
  check(!secondFreezeControls.error && secondFreezeControls.status === 0, 'second-freeze-rejection metadata controls failed');
  const alignedGateControls = spawnSync(process.env.PYTHON ?? (process.platform === 'win32' ? 'python' : 'python3'),
    ['-B', resolve(root, 'scripts/test-malformed-aligned-gate.py')],
    { cwd: root, encoding: 'utf8' });
  check(!alignedGateControls.error && alignedGateControls.status === 0, 'malformed-aligned-gate metadata controls failed');
  const guardMutantsControls = spawnSync(process.env.PYTHON ?? (process.platform === 'win32' ? 'python' : 'python3'),
    ['-B', resolve(root, 'scripts/test-malformed-guard-mutants.py')],
    { cwd: root, encoding: 'utf8' });
  check(!guardMutantsControls.error && guardMutantsControls.status === 0, 'malformed-guard-mutants metadata controls failed');
  const wordGuardMutantsControls = spawnSync(process.env.PYTHON ?? (process.platform === 'win32' ? 'python' : 'python3'),
    ['-B', resolve(root, 'scripts/test-malformed-word-guard-mutants.py')],
    { cwd: root, encoding: 'utf8' });
  check(!wordGuardMutantsControls.error && wordGuardMutantsControls.status === 0, 'malformed-word-guard-mutants metadata controls failed');
  const callTraceControls = spawnSync(process.env.PYTHON ?? (process.platform === 'win32' ? 'python' : 'python3'),
    ['-B', resolve(root, 'scripts/test-malformed-call-trace.py')],
    { cwd: root, encoding: 'utf8' });
  check(!callTraceControls.error && callTraceControls.status === 0, 'malformed-call-trace metadata controls failed');
  const certificateRegistryControls = spawnSync(process.env.PYTHON ?? (process.platform === 'win32' ? 'python' : 'python3'),
    ['-B', resolve(root, 'scripts/test-certificate-registry.py')],
    { cwd: root, encoding: 'utf8' });
  check(!certificateRegistryControls.error && certificateRegistryControls.status === 0, 'certificate-registry metadata controls failed');
  const certificateRegistrySyntheticControls = spawnSync(process.env.PYTHON ?? (process.platform === 'win32' ? 'python' : 'python3'),
    ['-B', resolve(root, 'scripts/trust12/tail-preparation/test_certificate_registry_v2.py')],
    { cwd: root, encoding: 'utf8' });
  check(!certificateRegistrySyntheticControls.error && certificateRegistrySyntheticControls.status === 0,
    'certificate-registry synthetic controls failed');
  const routeInventoryControls = spawnSync(process.env.PYTHON ?? (process.platform === 'win32' ? 'python' : 'python3'),
    ['-B', resolve(root, 'scripts/test-route-inventory.py')],
    { cwd: root, encoding: 'utf8' });
  check(!routeInventoryControls.error && routeInventoryControls.status === 0, 'route-inventory metadata controls failed');
  const routeInventorySyntheticControls = spawnSync(process.env.PYTHON ?? (process.platform === 'win32' ? 'python' : 'python3'),
    ['-B', resolve(root, 'scripts/trust12/tail-preparation/test_route_inventory_v2.py')],
    { cwd: root, encoding: 'utf8' });
  check(!routeInventorySyntheticControls.error && routeInventorySyntheticControls.status === 0,
    'route-inventory synthetic controls failed');
  const typedFailureControls = spawnSync(process.env.PYTHON ?? (process.platform === 'win32' ? 'python' : 'python3'),
    ['-B', resolve(root, 'scripts/test-typed-failure-binding.py')],
    { cwd: root, encoding: 'utf8' });
  check(!typedFailureControls.error && typedFailureControls.status === 0, 'typed-failure-binding metadata controls failed');
  const typedFailureSyntheticControls = spawnSync(process.env.PYTHON ?? (process.platform === 'win32' ? 'python' : 'python3'),
    ['-B', resolve(root, 'scripts/trust12/tail-preparation/test_typed_failure_binding.py')],
    { cwd: root, encoding: 'utf8' });
  check(!typedFailureSyntheticControls.error && typedFailureSyntheticControls.status === 0,
    'typed-failure-binding synthetic controls failed');
  const primitiveCheckpointControls = spawnSync(process.env.PYTHON ?? (process.platform === 'win32' ? 'python' : 'python3'),
    ['-B', resolve(root, 'scripts/test-primitive-source-controls.py')], { cwd: root, encoding: 'utf8' });
  check(!primitiveCheckpointControls.error && primitiveCheckpointControls.status === 0, 'primitive-source-controls metadata controls failed');
  const transactionCheckpointControls = spawnSync(process.env.PYTHON ?? (process.platform === 'win32' ? 'python' : 'python3'),
    ['-B', resolve(root, 'scripts/test-received-transaction-controls.py')], { cwd: root, encoding: 'utf8' });
  check(!transactionCheckpointControls.error && transactionCheckpointControls.status === 0, 'transaction-controls metadata controls failed');
  const reflectionScanControls = spawnSync(process.env.PYTHON ?? (process.platform === 'win32' ? 'python' : 'python3'),
    ['-B', resolve(root, 'scripts/test-reflection-scan.py')],
    { cwd: root, encoding: 'utf8' });
  check(!reflectionScanControls.error && reflectionScanControls.status === 0, 'reflection-scan metadata controls failed');
  const storageReaderControls = spawnSync(process.env.PYTHON ?? (process.platform === 'win32' ? 'python' : 'python3'),
    ['-B', resolve(root, 'scripts/test-storage-reader.py')],
    { cwd: root, encoding: 'utf8' });
  check(!storageReaderControls.error && storageReaderControls.status === 0, 'storage-reader metadata controls failed');
  const registeredGateControls = spawnSync(process.env.PYTHON ?? (process.platform === 'win32' ? 'python' : 'python3'),
    ['-B', resolve(root, 'scripts/test-registered-gate.py')],
    { cwd: root, encoding: 'utf8' });
  check(!registeredGateControls.error && registeredGateControls.status === 0, 'registered-gate metadata controls failed');
  const report={schema:'trust12-required-controls-v1',status:'PASS',positive:'PASS_CONSISTENT_DEVELOPMENT',negativeControls:results,
    source:{verifierSha256:sha256(readFileSync(resolve(root,'scripts/verify-trust12-required.mjs'))),testSha256:sha256(readFileSync(fileURLToPath(import.meta.url)))},
    nonclaim:'Admission and required-consumer controls. No new implementation mutation campaign, symbolic theorem or runtime refinement is claimed.'};
  writeFileSync(resolve(output,'required-controls.json'),encoded(report));
  console.log(JSON.stringify({status:'PASS',positive:report.positive,negativeControls:results.length},null,2));
} finally { const rel=relative(output,scratch);check(rel&&!rel.startsWith('..')&&!rel.includes(sep)&&rel.startsWith('required-controls-'),'unsafe fixture cleanup');rmSync(scratch,{recursive:true,force:true}); }
