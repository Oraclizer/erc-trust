// SPDX-License-Identifier: BSD-3-Clause
// Input and entrypoint controls; these do not rerun the preserved prover results.
import {createHash} from "node:crypto";
import {execFileSync,spawnSync} from "node:child_process";
import {readFileSync,writeFileSync,mkdirSync,mkdtempSync,copyFileSync,rmSync} from "node:fs";
import {resolve,dirname,relative,sep} from "node:path";
import {fileURLToPath} from "node:url";
import {verifyTrust12EvidenceReuse,mutationInputMatches,assertTrust12DevelopmentMode} from "./verify-trust12-evidence-reuse.mjs";
const root=resolve(dirname(fileURLToPath(import.meta.url)),"..");
const manifest="evidence/trust12/evidence-reuse.json";
const original=JSON.parse(readFileSync(resolve(root,manifest)));
const sha=x=>createHash("sha256").update(x).digest("hex");
const assert=(c,m)=>{if(!c)throw Error(m);};
const output=resolve(root,"out/trust12");
mkdirSync(output,{recursive:true});
const scratch=mkdtempSync(resolve(output,"reuse-controls-"));
const inputs=[...original.preservedInputs,...original.newInputs].map(e=>e.path);
inputs.push(manifest,"foundry.toml","evidence/mutation-results.json","evidence/kontrol-results-v3.json","evidence/certora-results-v3.json","evidence/evidence-expectations-v3.json");
const results=[];
function fixture(name){
 const dir=resolve(scratch,name);
 for(const p of inputs){mkdirSync(dirname(resolve(dir,p)),{recursive:true});copyFileSync(resolve(root,p),resolve(dir,p));}
 return dir;
}
function reject(name,change,expected,invoke=(dir,m)=>verifyTrust12EvidenceReuse(dir,m)){
 const dir=fixture(name),m=structuredClone(original);change(dir,m);
 let reason=null;try{invoke(dir,m);}catch(e){reason=e.message;}
 assert(reason&&reason.includes(expected),`${name}: expected ${expected}, got ${reason}`);
 results.push({name,status:"REJECTED",reason});
}
try{
 const positive=fixture("positive");verifyTrust12EvidenceReuse(positive);
 assertTrust12DevelopmentMode("successor-development");
 assert(mutationInputMatches(positive,original.preservedMutation.sourceRootSha256,original.currentSourceRootSha256),"preserved mutation did not match");
 reject("paired-runner-change",(dir,m)=>{
   const p="scripts/run-mutations.ps1",b=Buffer.concat([readFileSync(resolve(dir,p)),Buffer.from("\n# changed runner\n")]);
   writeFileSync(resolve(dir,p),b);m.preservedInputs.find(e=>e.path===p).sha256=sha(b);
 },"preserved baseline inventory root drift");
 reject("fabricated-historical-proof",(dir,m)=>{
   const p="implementation/kontrol/Fabricated.t.sol",b=Buffer.from("// never in the historical proof\n");
   writeFileSync(resolve(dir,p),b);m.preservedInputs.push({path:p,sha256:sha(b)});
 },"preserved baseline inventory root drift");
 reject("changed-preserved-source",(dir)=>writeFileSync(resolve(dir,"implementation/src/TrustToken.sol"),"// changed\n"),"aggregate source root drift");
 reject("missing-runtime-vector",(_,m)=>{m.preservedInputs=m.preservedInputs.filter(e=>e.path!=="vectors/conformance-v2.json")},"preserved baseline inventory root drift");
 reject("new-source-unowned",dir=>writeFileSync(resolve(dir,"implementation/src/Unowned.sol"),"// unowned\n"),"aggregate source root drift");
 reject("missing-owner",(_,m)=>m.newInputs.pop(),"new input ownership drift");
 reject("duplicate-owner",(_,m)=>m.newInputs.push(m.newInputs[0]),"new input ownership drift");
 reject("changed-compiler",(_,m)=>{m.foundryConfiguration.baselineText=m.foundryConfiguration.baselineText.replace("optimizer_runs = 1","optimizer_runs = 2")},"compiler or execution configuration changed");
 reject("changed-receipt",(_,m)=>{m.preservedMutation.receiptSha256="0".repeat(64)},"historical mutation receipt changed");
 reject("current-root-fast-path",dir=>writeFileSync(resolve(dir,"scripts/run-mutations.ps1"),"# changed\n"),"preserved input drift",dir=>mutationInputMatches(dir,original.currentSourceRootSha256,original.currentSourceRootSha256));
 reject("release-mode",()=>{},"development-only",()=>assertTrust12DevelopmentMode("release"));
 for(const name of ["verify-current-profile-release-v3.mjs","verify-obligation-ledger-v3.mjs","verify-runtime-binding-v3.mjs"]){
   const dir=fixture(name),scripts=resolve(dir,"scripts");mkdirSync(scripts,{recursive:true});
   copyFileSync(resolve(root,"scripts",name),resolve(scripts,name));
   copyFileSync(resolve(root,"scripts/verify-trust12-evidence-reuse.mjs"),resolve(scripts,"verify-trust12-evidence-reuse.mjs"));
   for(const helper of ["mutation-campaign.mjs","resolve-pinned-solc.mjs","runtime-binding-semantics.mjs"]){
     mkdirSync(resolve(scripts,"lib"),{recursive:true});copyFileSync(resolve(root,"scripts/lib",helper),resolve(scripts,"lib",helper));
   }
   copyFileSync(resolve(root,"evidence/evidence-mode.json"),resolve(dir,"evidence/evidence-mode.json"));
   const m=structuredClone(original);m.preservedInputs[0].sha256="0".repeat(64);writeFileSync(resolve(dir,manifest),JSON.stringify(m));
   // Removing the mutation receipt must not skip the inventory check.
   rmSync(resolve(dir,"evidence/mutation-results.json"));
   const run=spawnSync(process.execPath,[resolve(scripts,name)],{encoding:"utf8"});
   const text=(run.stdout??"")+(run.stderr??"");
   assert(run.status!==0&&text.includes("preserved baseline inventory root drift"),`${name}: entrypoint skipped inventory: ${text}`);
   results.push({name:`entrypoint:${name}`,status:"REJECTED",reason:"preserved baseline inventory root drift before absent mutation receipt"});
 }
 const report={schema:"trust12-evidence-reuse-controls-v1",status:"PASS",positive:"PASS",negativeControls:results,inputs:{verifierSha256:sha(readFileSync(resolve(root,"scripts/verify-trust12-evidence-reuse.mjs"))),testSha256:sha(readFileSync(fileURLToPath(import.meta.url))),manifestSha256:sha(readFileSync(resolve(root,manifest)))},nonclaim:"These are input-verifier and entrypoint controls, not new implementation mutation runs, symbolic proofs, model proofs, or end-to-end refinement."};
 writeFileSync(resolve(output,"evidence-reuse-controls.json"),JSON.stringify(report,null,2)+"\n");
 console.log(JSON.stringify({status:report.status,positive:report.positive,negativeControls:results.length}));
}finally{
 const rel=relative(output,scratch);
 assert(rel&&!rel.startsWith("..")&&!rel.includes(sep)&&rel.startsWith("reuse-controls-"),"unsafe scratch cleanup");
 rmSync(scratch,{recursive:true,force:true});
}
