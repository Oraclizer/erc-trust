// SPDX-License-Identifier: BSD-3-Clause
// Promote an existing local double build without changing its execution identity.
import { execFileSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { assertCommitInputs, check, encoded, fileRef, implementationPaths, inventoryRoot, json, localFoundryRun, read, sha256 } from './lib/local-evidence.mjs';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const sourcePath = 'evidence/trust12/deterministic-build-replay.json';
const validationPath = 'evidence/trust12/local-validation.json';
const run = json(root, sourcePath), validation = json(root, validationPath);
const commit = run.candidateInput.gitHead;
const inputs = assertCommitInputs(root, implementationPaths(root), commit);
check(run.status === 'PASS' && run.schema === 'erc-trust-deterministic-build-v3', 'double build is not PASS');
check(encoded(run.buildA) === encoded(run.buildB), 'double build outputs differ');
check(run.candidateInput.sourceRootSha256 === inventoryRoot(inputs), 'double build source root drift');
check(fileRef(root, sourcePath).sha256 === validation.deterministicBuild.sha256, 'curated deterministic receipt drift');
const raw = read(root, 'out/trust12/deterministic-build-replay.json');
check(sha256(raw) === validation.deterministicBuild.rawReplaySha256 && encoded(JSON.parse(raw)) === encoded(run), 'raw/normalized deterministic mismatch');
localFoundryRun(root, validationPath, commit);
const manifest = json(root, 'evidence/release-manifest.json');
for (const [id, artifact, bound] of [
  ['native', 'out/TrustToken.sol/TrustToken.json', manifest.trustToken],
  ['erc3643Adapter', 'out/ERC3643TrustAdapter.sol/ERC3643TrustAdapter.json', manifest.profileRuntimes.erc3643Adapter],
  ['profileGovernor', 'out/ProfileGovernor.sol/ProfileGovernor.json', manifest.profileRuntimes.profileGovernor],
]) {
  const subject = run.buildA.subjects[id], compiled = json(root, artifact);
  for (const [key, field] of [['runtimeSha256', 'deployedBytecode'], ['creationSha256', 'bytecode']]) {
    check(subject[key] === bound[key] && subject[key] === sha256(Buffer.from(compiled[field].object.replace(/^0x/, ''), 'hex')), `deterministic ${id} ${key} differs from artifact/manifest`);
  }
}
const predecessorCommit = 'dfbd779ef5a49d5907ead2e8d3322859378519ec';
const historical = execFileSync('git', ['show', `${predecessorCommit}:evidence/deterministic-build.json`], { cwd: root });
const receipt = { ...run, provider: 'local-wsl-foundry',
  provenance: { source: fileRef(root, sourcePath), validation: fileRef(root, validationPath),
    sourceInputs: inputs, sourceRootSha256: inventoryRoot(inputs),
    supersedes: { commit: predecessorCommit, path: 'evidence/deterministic-build.json', sha256: sha256(historical) },
    statement: 'The original local double-build commit and output are preserved. Recording verifies unchanged current input bytes and artifact identities; it does not assert another build or a CI run.' } };
if (process.argv.includes('--write')) writeFileSync(resolve(root, 'evidence/deterministic-build.json'), encoded(receipt));
console.log(JSON.stringify({ status: 'PASS', sourceCommit: commit, sourceRootSha256: inventoryRoot(inputs), written: process.argv.includes('--write') }, null, 2));
