// SPDX-License-Identifier: BSD-3-Clause
import { check, encoded, read, sha256 } from './local-evidence.mjs';
const subject = (id, contract, source) => ({ id, contract, source, artifact: `out/${contract}.sol/${contract}.json` });
const hooks = ['ERC3643HookAdapter','ERC3643HookGovernor','ERC3643HookCompliance','ERC3643HookFactory'];
export const runtimeBundles = [
  { id: 'native', roots: ['implementation/src/TrustToken.sol'], subjects: [subject('native','TrustToken','implementation/src/TrustToken.sol')] },
  { id: 'erc3643-partial', roots: ['implementation/src/profiles/ERC3643TrustAdapter.sol','implementation/src/profiles/ProfileGovernor.sol'],
    subjects: [subject('profileAdapter','ERC3643TrustAdapter','implementation/src/profiles/ERC3643TrustAdapter.sol'),subject('profileGovernor','ProfileGovernor','implementation/src/profiles/ProfileGovernor.sol')] },
  { id: 'erc3643-hook', roots: hooks.map(name=>`implementation/src/profiles/${name}.sol`), subjects: hooks.map(name=>subject(name,name,`implementation/src/profiles/${name}.sol`)) },
];
export function verifyRuntimeBundles(root, receipt) {
  check(encoded(receipt.bundles?.map(b=>b.id)) === encoded(runtimeBundles.map(b=>b.id)), 'required compiler bundle inventory missing or changed');
  const allSubjects = runtimeBundles.flatMap(b=>b.subjects.map(s=>({...s,bundle:b.id})));
  check(encoded(receipt.subjects?.map(s=>s.id)) === encoded(allSubjects.map(s=>s.id)), 'required compiler subject inventory missing or changed');
  for (const expected of allSubjects) {
    const actual=receipt.subjects.find(s=>s.id===expected.id);
    check(Object.entries(expected).every(([key,value])=>actual[key]===value), `compiler subject mapping drift: ${expected.id}`);
  }
  for (const expected of runtimeBundles) {
    const actual=receipt.bundles.find(b=>b.id===expected.id);
    check(encoded(actual.roots)===encoded(expected.roots) && encoded(actual.subjects)===encoded(expected.subjects.map(s=>s.id)), `compiler bundle mapping drift: ${expected.id}`);
    const paths=['standard-json-input.json','bridge-artifacts.json','source-identities.json'].map(name=>`evidence/runtime-binding-v3/${expected.id}/${name}`);
    check(encoded(actual.files?.map(f=>f.path))===encoded(paths), `required compiler bundle files missing: ${expected.id}`);
    for(const file of actual.files) check(sha256(Buffer.from(read(root,file.path).toString('utf8').replace(/\r\n?/g,'\n')))===file.sha256, `compiler bundle file drift: ${file.path}`);
    const artifacts=JSON.parse(read(root,paths[1]).toString('utf8'));
    check(encoded(artifacts.map(s=>s.id))===encoded(expected.subjects.map(s=>s.id)), `stored compiler artifact inventory drift: ${expected.id}`);
  }
}
