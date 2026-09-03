#!/usr/bin/env node
// Future executable mutant builder. Static generation never invokes it.
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const rowDir=path.dirname(fileURLToPath(import.meta.url));
const root=path.resolve(rowDir,"../../../..");
const read=(p)=>JSON.parse(fs.readFileSync(p,"utf8"));
const sha=(v)=>crypto.createHash("sha256").update(v).digest("hex");
const lockPath=path.join(root,"formal/kevm/dependencies.lock.json");
assert.equal(sha(fs.readFileSync(lockPath)),"3134e7692086170f86b6dd42e7ebd0256c188da8db8cbd17241c3d2c8d315196");
const lock=read(lockPath);
const input=read(path.join(root,"evidence/end-to-end-refinement/runtime-binding/native/standard-json-input.json"));
const key="implementation/src/TrustPolicyBinding.sol";
const before=`        if (!ok || output.length != 128) {\n            return (TrustTypes.AssessmentOutcome.OPERATIONAL_FAILURE, bytes32(0), 202);\n        }`;
const after=`        if (!ok) {\n            return (TrustTypes.AssessmentOutcome.APPLICABLE, bytes32(0), 0);\n        }\n        if (output.length != 128) {\n            return (TrustTypes.AssessmentOutcome.OPERATIONAL_FAILURE, bytes32(0), 202);\n        }`;
assert.equal(input.sources[key].content.split(before).length-1,1);
input.sources[key].content=input.sources[key].content.replace(before,after);
const solc=process.env.FAIL03_SOLC_0_8_36;
assert.ok(solc,"set FAIL03_SOLC_0_8_36 to exact pinned solc");
assert.equal(sha(fs.readFileSync(solc)),lock.components.solc.binarySha256);
const run=spawnSync(solc,["--standard-json"],{input:JSON.stringify(input),encoding:"utf8",maxBuffer:256*1024*1024});
if(run.error)throw run.error; assert.equal(run.status,0,run.stderr);
const output=JSON.parse(run.stdout); assert.deepEqual((output.errors||[]).filter((x)=>x.severity==="error"),[]);
const out=path.join(rowDir,"bridge"); fs.mkdirSync(out,{recursive:true});
fs.writeFileSync(path.join(out,"mutant-standard-json-input.json"),JSON.stringify(input));
fs.writeFileSync(path.join(out,"mutant-standard-json-output.json"),JSON.stringify(output));
console.log(JSON.stringify({status:"PINNED_MUTANT_COMPILED_NOT_PROOF",solcVersion:lock.components.solc.version},null,2));
