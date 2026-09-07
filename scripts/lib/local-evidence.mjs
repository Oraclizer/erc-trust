// SPDX-License-Identifier: BSD-3-Clause
// Local receipts are checked against actual logs and Git blobs at recording time.
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, relative, isAbsolute } from 'node:path';

export const sha256 = value => createHash('sha256').update(value).digest('hex');
export const check = (condition, message) => { if (!condition) throw new Error(message); };
export const stable = value => Array.isArray(value) ? value.map(stable) : value && typeof value === 'object'
  ? Object.fromEntries(Object.keys(value).sort().map(key => [key, stable(value[key])])) : value;
export const encoded = value => `${JSON.stringify(stable(value), null, 2)}\n`;
export function read(root, path) {
  const full = resolve(root, path), rel = relative(root, full);
  check(!isAbsolute(rel) && rel !== '..' && !rel.startsWith('../') && !rel.startsWith('..\\'), `path outside repository: ${path}`);
  return readFileSync(full);
}
export const json = (root, path) => JSON.parse(read(root, path).toString('utf8'));
export const fileRef = (root, path) => ({ path, sha256: sha256(read(root, path)) });
export function walk(root, path) {
  return readdirSync(resolve(root, path), { withFileTypes: true }).flatMap(entry => {
    const child = `${path}/${entry.name}`;
    return entry.isDirectory() ? walk(root, child) : [child];
  });
}
export function inputInventory(root, paths, commit = null) {
  if (commit) check(/^[a-f0-9]{40}$/.test(commit), 'full source commit required');
  return [...new Set(paths)].sort().map(path => ({ path, sha256: sha256(commit
    ? execFileSync('git', ['show', `${commit}:${path}`], { cwd: root, maxBuffer: 64 * 1024 * 1024 }) : read(root, path)) }));
}
export const inventoryRoot = inputs => sha256(inputs.map(input => `${input.sha256}  ${input.path}\n`).join(''));
export function assertCommitInputs(root, paths, commit) {
  const actual = inputInventory(root, paths), committed = inputInventory(root, paths, commit);
  check(encoded(actual) === encoded(committed), 'named commit does not carry current input bytes');
  return actual;
}
export const implementationPaths = root => [...walk(root, 'implementation/src'), ...walk(root, 'implementation/test'), 'foundry.toml'];

export function localFoundryRun(root, validationPath, commit) {
  const run = json(root, validationPath);
  check(run.schema === 'trust12-local-validation-v1' && run.status === 'PASS_NAMED_CHECKS'
    && run.provider === 'local-wsl-foundry', 'unsupported local Foundry validation');
  check(run.sourceCommit === commit, 'local run commit differs from requested source commit');
  const inputs = assertCommitInputs(root, implementationPaths(root), commit);
  check(inventoryRoot(inputs) === run.sourceRootSha256, 'local run source root mismatch');
  const required = { format: 'forge fmt --check', 'build-size': 'forge build --sizes', tests: 'forge test --json', lint: 'forge lint' };
  check(Array.isArray(run.commands) && run.commands.length === 4 && new Set(run.commands.map(c => c.id)).size === 4, 'local command inventory mismatch');
  for (const command of run.commands) {
    check(required[command.id] === command.command && command.exitCode === 0, `local command did not pass: ${command.id}`);
    check(Number.isFinite(Date.parse(command.startedAt)) && Date.parse(command.finishedAt) >= Date.parse(command.startedAt), 'invalid local command timestamps');
    check(sha256(read(root, command.logPath)) === command.logSha256, `local log drift: ${command.id}`);
  }
  const testCommand = run.commands.find(c => c.id === 'tests');
  const suites = json(root, testCommand.logPath);
  const results = Object.entries(suites).flatMap(([suite, value]) => Object.entries(value.test_results ?? {}).map(([test, result]) => ({ suite, test, ...result })));
  check(results.length > 0 && results.every(result => result.status === 'Success'), 'local test log is empty or contains unsuccessful tests');
  check(run.tests.passed === results.length && run.tests.suites === Object.keys(suites).length
    && run.tests.failed === 0 && run.tests.skipped === 0, 'local test totals differ from raw log');
  const fuzz = results.filter(result => result.kind.Fuzz).map(result => result.kind.Fuzz);
  const invariants = results.filter(result => result.kind.Invariant).map(result => result.kind.Invariant);
  const tests = { ...run.tests, fuzzProperties: fuzz.length, fuzzRuns: fuzz.map(result => result.runs),
    invariants: invariants.length, invariantRuns: invariants.map(result => result.runs),
    invariantCalls: invariants.reduce((sum, result) => sum + result.calls, 0),
    invariantReverts: invariants.reduce((sum, result) => sum + result.reverts, 0) };
  return {
    provider: run.provider,
    run: { provider: run.provider, source: fileRef(root, validationPath), commands: run.commands,
      sourceInputs: inputs, sourceRootSha256: inventoryRoot(inputs),
      observation: 'Actual local process exits and SHA-256 checked raw logs; no GitHub workflow identity is asserted.' },
    toolchain: { foundry: `${run.toolchain.forge}+${run.toolchain.forgeCommit}`, solidity: run.toolchain.solidity, evmVersion: run.toolchain.evmVersion },
    checks: { format: 'PASS', buildAndSize: 'PASS', lintErrors: 0, tests },
    testInventory: results.map(({ suite, test, status }) => ({ suite, test, status })),
  };
}

export function checkLocalReceiptProvenance(root, receipt, provider) {
  check(receipt.provider === provider && !receipt.workflow, 'local receipt cannot assert CI workflow provenance');
  check(receipt.run?.provider === provider && receipt.run?.source, 'local receipt provenance missing');
  const source = receipt.run.source;
  const expectedPath = provider === 'local-wsl-foundry' ? 'evidence/trust12/local-validation.json' : 'evidence/trust12/formal-build-replay.json';
  check(source.path === expectedPath, 'local provenance source path mismatch');
  const original = json(root, source.path);
  check(original.provider === provider && original.sourceCommit === receipt.sourceCommit, 'local provider or execution commit mismatch');
  if (provider === 'local-wsl-foundry') {
    check(original.status === 'PASS_NAMED_CHECKS' && original.sourceRootSha256 === receipt.sourceRootSha256, 'local Foundry source identity mismatch');
    check(encoded(original.commands) === encoded(receipt.run.commands), 'local Foundry command provenance mismatch');
    check(original.commands.length === 4 && new Set(original.commands.map(c=>c.id)).size === 4
      && original.commands.every(c=>c.exitCode===0 && Number.isFinite(Date.parse(c.startedAt)) && Date.parse(c.finishedAt)>=Date.parse(c.startedAt)), 'local Foundry command failed or timestamp invalid');
    check(encoded(receipt.run.sourceInputs) === encoded(inputInventory(root, implementationPaths(root))), 'local Foundry inventory is not exhaustive');
  } else {
    check(original.status === 'PASS' && original.processExit === 0, 'local Isabelle execution failed');
    check(encoded(original.sessions) === encoded(receipt.sessions) && encoded(original.dependencyInputs) === encoded(receipt.run.dependencyInputs), 'local Isabelle session/dependency provenance mismatch');
  }

  check(sha256(read(root, source.path)) === source.sha256, 'local provenance source drift');
  check(Array.isArray(receipt.run.sourceInputs) && receipt.run.sourceInputs.length > 0, 'local source inventory missing');
  check(encoded(inputInventory(root, receipt.run.sourceInputs.map(x => x.path))) === encoded(receipt.run.sourceInputs), 'local input inventory drift');
}
