// SPDX-License-Identifier: BSD-3-Clause
import { basename } from 'node:path';
import { assertCommitInputs, check, encoded, inputInventory, inventoryRoot, json, read, sha256, walk } from './local-evidence.mjs';
export function formalInputPaths(root) {
  return [...walk(root, 'formal/isabelle').filter(path => !path.includes('/evidence/') &&
    (path.endsWith('.thy') || path.endsWith('.ML') || ['ROOT', 'ROOTS'].includes(basename(path)))),
    'formal-dependencies.lock.json', 'formal-dependencies-public-v1.lock.json',
    'evidence/public-release/formal-foundation-supersession-v1.json', '.github/workflows/proofs.yml',
    'scripts/generate-trust12-proof-audit.py', 'scripts/capture-isabelle-local-inputs.mjs',
    'scripts/lib/formal-inputs.mjs',
    'formal/isabelle/ERC_TRUST/evidence/model-verification/run-trust-closure.ps1'].sort();
}
export function formalIdentity(root, commit = null) {
  const paths = formalInputPaths(root);
  const inputs = commit ? assertCommitInputs(root, paths, commit) : inputInventory(root, paths);
  const dirs = read(root, 'formal/isabelle/ROOTS').toString('utf8').split(/\r?\n/).map(line => line.trim()).filter(line => line && !line.startsWith('#'));
  const sessions = dirs.flatMap(dir => [...read(root, `formal/isabelle/${dir}/ROOT`).toString('utf8').matchAll(/\bsession\s+(\w+)\s*=/g)].map(match => match[1])).sort();
  check(sessions.includes('ERC_TRUST') && sessions.includes('TRUST12_Accounting_Obstruction'), 'required named sessions missing');
  const lock = json(root, 'formal-dependencies-public-v1.lock.json');
  const foundationCommit = lock.formalFoundationDependency.repositoryCommit;
  check(read(root, '.github/workflows/proofs.yml').toString('utf8').includes(`FORMAL_FOUNDATION_COMMIT: ${foundationCommit}`), 'foundation workflow/lock mismatch');
  return { path: 'formal/isabelle', theoryFiles: inputs.filter(input => input.path.endsWith('.thy')).length,
    rootSha256: inventoryRoot(inputs), algorithm: 'sha256-formal-session-graph-inputs-v2', inputs, sessions, foundationCommit };
}
export function validateFormalIdentity(root, recorded) {
  check(encoded(recorded) === encoded(formalIdentity(root)), 'formal session graph, theory or foundation input drift');
}

// Location-independent identity of the actual execution inputs and kernel audit exports.
export function formalAdmissionDigest(replay) {
  return sha256(encoded({ executionCommit: replay.sourceCommit, formalSource: replay.formalSource,
    dependencyInputs: replay.dependencyInputs, sessions: replay.sessions }));
}
