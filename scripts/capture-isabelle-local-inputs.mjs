// SPDX-License-Identifier: BSD-3-Clause
// Capture the exact directories supplied to the local Isabelle build, before and after it.
import { execFileSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { check, encoded, inputInventory, walk } from './lib/local-evidence.mjs';
import { formalIdentity } from './lib/formal-inputs.mjs';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2), arg = name => args.includes(name) ? args[args.indexOf(name)+1] : null;
check(arg('--foundation') && arg('--ads') && arg('--out'), 'usage: --foundation <actual overlay> --ads <actual ADS> --out <snapshot>');
const capture = directory => ({ directory: resolve(directory), inputs: inputInventory(directory, walk(directory,'.').filter(path=>
  path.endsWith('.thy') || path.endsWith('.ML') || path.endsWith('/ROOT') || path.endsWith('/ROOTS'))) });
const result = { schema: 'trust12-isabelle-build-input-capture-v1',
  executionCommit: execFileSync('git',['rev-parse','HEAD'],{cwd:root,encoding:'utf8'}).trim(),
  formalSource: formalIdentity(root), foundation: capture(arg('--foundation')), adsFunctor: capture(arg('--ads')) };
writeFileSync(resolve(arg('--out')),encoded(result));
