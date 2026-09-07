// SPDX-License-Identifier: BSD-3-Clause
// Bind a real CI or local clean build to the complete named session graph.
import { execFileSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import { dirname, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { check, encoded, fileRef, inputInventory, json, read, sha256, walk } from './lib/local-evidence.mjs';
import { formalAdmissionDigest, formalIdentity, validateFormalIdentity } from './lib/formal-inputs.mjs';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const arg = name => args.includes(name) ? args[args.indexOf(name) + 1] : null;
const commit = arg('--commit'), runPath = arg('--run'), local = args.includes('--local');
check(runPath && commit, 'usage: --run <summary> --commit <full SHA> [--local] [--write]');
const formalSource = formalIdentity(root, commit);
const source = json(root, runPath), mode = json(root, 'evidence/evidence-mode.json');
let checks, sessions, provenance, localReplay;
function audit(text) {
  const fields = Object.fromEntries(text.trim().split(/\r?\n/).map(line => line.split('=')));
  check(fields.status === 'PASS' && fields.oracle_dependency_count === '0', 'proof export has oracle dependencies or is not PASS');
  const explicitRoots = Number(fields.explicit_root_count), qualifiedFacts = Number(fields.qualified_fact_count);
  check(Number.isInteger(explicitRoots) && explicitRoots > 0 && Number.isInteger(qualifiedFacts) && qualifiedFacts >= explicitRoots, 'proof audit is empty or inconsistent');
  return { explicitRoots, qualifiedFacts, oracleDependencies: 0 };
}
if (local) {
  check(source.provider === 'local-windows-isabelle' && source.exitCode === 0 && source.sourceCommit === commit, 'local Isabelle execution identity or exit mismatch');
  check(Number.isFinite(Date.parse(source.startedAt)) && Date.parse(source.finishedAt) >= Date.parse(source.startedAt), 'invalid local Isabelle timestamps');
  check(sha256(read(root, source.logPath)) === source.logSha256, 'local Isabelle launcher log drift');
  validateFormalIdentity(root, json(root, source.formalInputBefore));
  const summary = JSON.parse(read(root, source.logPath).toString('utf8').trim());
  const dir = relative(root, summary.runDirectory).replaceAll('\\', '/');
  const report = json(root, `${dir}/closure-report.json`);
  check(report.repositoryCommit === commit && report.status === 'PASS' && report.build.exitCode === 0
    && report.proofAudit.exportExitCode === 0 && report.bannedSourceForms === 0, 'local clean build or export failed');
  const buildLog = read(root, `${dir}/isabelle-clean-build.log`).toString('utf8');
  check(sha256(Buffer.from(buildLog)) === report.build.logSha256.toLowerCase(), 'local clean build log drift');
  sessions = formalSource.sessions.map(name => {
    check(buildLog.includes(`Cleaned ${name}`) && buildLog.includes(`Finished ${name} (`), `session was not clean-built: ${name}`);
    const suffix = name === 'ERC_TRUST' ? '/model-proof-trust.txt' : '/trust12-obstruction-proof-trust.txt';
    const matches = walk(root, `${dir}/isabelle-export`).filter(path => path.endsWith(suffix));
    check(matches.length === 1, `missing or duplicate proof export: ${name}`);
    const parsed = audit(read(root, matches[0]).toString('utf8'));
    return { name, status: 'PASS', cleanBuild: 'PASS', proofExport: 'PASS', ...parsed, exportSha256: sha256(read(root, matches[0])) };
  });
  const foundationRoot = arg('--foundation-root'), overlayRoot = arg('--overlay-root'), adsRoot = arg('--ads-root');
  check(foundationRoot && overlayRoot && adsRoot, 'local run requires exact foundation, overlay and ADS input roots');
  execFileSync(process.execPath, [resolve(root, 'scripts/verify-formal-foundation-supersession.mjs'), '--foundation-root', foundationRoot], { cwd: root, stdio: 'pipe' });
  const foundationPaths = walk(foundationRoot, 'Cross_Domain_State_Preservation').filter(path => path.endsWith('.thy'));
  for (const path of foundationPaths) check(read(foundationRoot, path).equals(read(overlayRoot, path.split('/').at(-1))), `foundation overlay source drift: ${path}`);
  check(read(foundationRoot, 'Regulatory_Action_Composition/Regulatory_Action_Composition.thy').equals(read(overlayRoot, 'Regulatory_Action_Composition.thy')), 'RAC overlay source drift');
  const originalRoot = read(foundationRoot, 'Cross_Domain_State_Preservation/ROOT').toString('utf8').replace(/\r\n/g, '\n');
  check(read(overlayRoot, 'ROOT').toString('utf8').replace(/\r\n/g, '\n') === originalRoot.replace('    Regulatory_Instance\n', '    Regulatory_Instance\n    Regulatory_Action_Composition\n'), 'foundation overlay ROOT transformation drift');
  check(report.inputCapture?.before === 'build-input-before.json' && report.inputCapture?.after === 'build-input-after.json', 'actual build dependency capture missing');
  const capturedBefore = json(root,`${dir}/${report.inputCapture.before}`), capturedAfter = json(root,`${dir}/${report.inputCapture.after}`);
  check(encoded(capturedBefore) === encoded(capturedAfter) && sha256(read(root,`${dir}/${report.inputCapture.before}`)) === report.inputCapture.sha256, 'build input capture changed or drifted');
  check(encoded(capturedBefore.formalSource) === encoded(formalSource) && capturedBefore.executionCommit === commit, 'captured formal build identity differs');
  check(resolve(capturedBefore.foundation.directory) === resolve(overlayRoot) && resolve(capturedBefore.adsFunctor.directory) === resolve(adsRoot), 'recorder dependency path differs from actual build input');
  const overlayInputs = inputInventory(overlayRoot, walk(overlayRoot,'.').filter(path=>path.endsWith('.thy') || path.endsWith('.ML') || path.endsWith('/ROOT') || path.endsWith('/ROOTS')));
  const adsInputs = inputInventory(adsRoot, walk(adsRoot,'.').filter(path=>path.endsWith('.thy') || path.endsWith('.ML') || path.endsWith('/ROOT') || path.endsWith('/ROOTS')));
  check(encoded(overlayInputs) === encoded(capturedBefore.foundation.inputs) && encoded(adsInputs) === encoded(capturedBefore.adsFunctor.inputs), 'dependency bytes differ from actual clean build');
  const dependencyInputs = {
    foundationCommit: formalSource.foundationCommit,
    overlay: overlayInputs,
    adsFunctor: adsInputs,
  };
  localReplay = { schema: 'trust12-formal-build-replay-v1', status: 'PASS', provider: source.provider, sourceCommit: commit,
    startedAt: source.startedAt, finishedAt: source.finishedAt, processExit: 0,
    command: 'isabelle build -c -o record_proofs=1 -o threads=2 -o parallel_proofs=0 -d <ADS_Functor> -d <verified-foundation-overlay> -d formal/isabelle ERC_TRUST TRUST12_Accounting_Obstruction',
    inputCapture: { sha256: report.inputCapture.sha256, beforeAfterEqual: true },
    rawRun: fileRef(root, runPath), buildLog: fileRef(root, `${dir}/isabelle-clean-build.log`),
    exportLog: fileRef(root, `${dir}/isabelle-export.log`), formalSource, dependencyInputs, sessions,
    nonclaim: 'A local kernel-checked model build with explicit dependency bytes. No CI execution, constructor decoding, compiler correctness or runtime_link discharge is asserted.' };
  localReplay.admissionDigest = formalAdmissionDigest(localReplay);
  provenance = { admissionDigest: localReplay.admissionDigest, provider: source.provider, run: { provider: source.provider,
    source: { path: 'evidence/trust12/formal-build-replay.json', sha256: sha256(encoded(localReplay)) },
    startedAt: source.startedAt, finishedAt: source.finishedAt, sourceInputs: formalSource.inputs,
    sourceRootSha256: formalSource.rootSha256, dependencyInputs, sessions } };
  checks = { cleanBuild: 'PASS', proofExport: 'PASS', bannedSourceForms: 0, oracleDependencyCount: 0,
    explicitRootCount: sessions.reduce((n,s) => n+s.explicitRoots,0), qualifiedFactCount: sessions.reduce((n,s) => n+s.qualifiedFacts,0) };
} else {
  check(source.workflow?.jobConclusion === 'success' && Number.isInteger(source.workflow.runId) && Number.isInteger(source.workflow.jobId), 'workflow identity incomplete');
  checks = source.checks; sessions = source.sessions;
  provenance = { provider: 'github-actions', workflow: source.workflow };
}
check(checks?.cleanBuild === 'PASS' && checks?.proofExport === 'PASS' && checks?.bannedSourceForms === 0 && checks?.oracleDependencyCount === 0, 'proof job did not pass');
check(Array.isArray(sessions) && encoded(sessions.map(s=>s.name).sort()) === encoded(formalSource.sessions)
  && sessions.every(s=>s.status==='PASS' && s.cleanBuild==='PASS' && s.proofExport==='PASS' && s.oracleDependencies===0 && s.explicitRoots>0), 'required named session evidence missing');
const receipt = { schema: 'erc-trust-isabelle-results-v3', candidate: mode.candidate, status: 'PASS', sourceCommit: commit,
  ...provenance, toolchain: { isabelle: 'Isabelle2025-2', sessions: formalSource.sessions, foundationCommit: formalSource.foundationCommit },
  formalSource, checks, sessions,
  claimBoundary: 'Clean model build and recursive proof audit of every named TRUST session, including child theories, ROOT/ROOTS and declared foundation inputs. The compiled-runtime link remains an assumption.' };
if (args.includes('--write')) {
  if (localReplay) writeFileSync(resolve(root, 'evidence/trust12/formal-build-replay.json'), encoded(localReplay));
  writeFileSync(resolve(root, 'evidence/isabelle-results-v3.json'), encoded(receipt));
}
console.log(JSON.stringify({ status: 'PASS', sourceCommit: commit, formalRoot: formalSource.rootSha256, sessions, written: args.includes('--write') }, null, 2));
