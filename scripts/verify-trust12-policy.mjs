// SPDX-License-Identifier: BSD-3-Clause
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { verifyTrust12Policy } from './lib/trust12-policy.mjs';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
console.log(JSON.stringify(verifyTrust12Policy(root), null, 2));
