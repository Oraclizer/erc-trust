// SPDX-License-Identifier: BSD-3-Clause
// Exact-input reuse of the legacy profiles. New inputs have separate owners.
import {createHash} from "node:crypto";
import {execFileSync} from "node:child_process";
import {readFileSync,writeFileSync,readdirSync,existsSync} from "node:fs";
import {resolve,dirname} from "node:path";
import {fileURLToPath} from "node:url";
const repository=resolve(dirname(fileURLToPath(import.meta.url)),"..");
const manifestPath="evidence/trust12/evidence-reuse.json";
const baseline="2545efa64289ad82fe3ad8a99e5dfad01ff92c10";
// Independently reconstructed from all 37 blobs at the baseline commit.
// This pins the inventory itself, including runner, vectors and proof dependencies.
const preservedInputsRoot="436845a990a6d229393c60eae0abaf8755474e6e6ea60aad1f6c9f6aadec718f";
const newInputs=[
  ...["Adapter","Compliance","Deployment","Factory","Governor"].map(n=>({path:`implementation/src/profiles/ERC3643Hook${n}.sol`,owner:"hook-functional"})),
  {path:"implementation/test/ERC3643HookTrexIntegration.t.sol",owner:"hook-functional"},
  {path:"implementation/kontrol/trust12/TrustTokenSymbolicKontrolTest.t.sol",owner:"native-symbolic-expanded"},
  {path:"implementation/kontrol/trust12/TrustTokenDeferredSymbolicKontrolTest.t.sol",owner:"native-symbolic-deferred"},
];
const extraPaths=["vectors/conformance-v2.json","formal/kevm/dependencies.lock.json","scripts/run-mutations.ps1","scripts/mutation-campaign-v1.json","scripts/lib/mutation-campaign.mjs"];
const hash=x=>createHash("sha256").update(x).digest("hex");
const canonical=x=>{if(Array.isArray(x))return x.map(canonical);if(x&&typeof x==="object")return Object.fromEntries(Object.keys(x).sort().map(k=>[k,canonical(x[k])]));return x;};
const encoded=x=>JSON.stringify(canonical(x),null,2)+"\n";
const assert=(c,m)=>{if(!c)throw Error(m);};
function api(root){
 const bytes=p=>readFileSync(resolve(root,p));
 const json=p=>JSON.parse(bytes(p));
 const walk=p=>existsSync(resolve(root,p))?readdirSync(resolve(root,p),{withFileTypes:true}).flatMap(e=>e.isDirectory()?walk(`${p}/${e.name}`):[`${p}/${e.name}`]):[];
 const sourcePaths=()=>[...walk("implementation/src"),...walk("implementation/test"),"foundry.toml"].sort();
 const entriesRoot=es=>hash([...es].sort((a,b)=>a.path<b.path?-1:a.path>b.path?1:0).map(e=>`${e.sha256}  ${e.path}\n`).join(""));
 const currentRoot=()=>entriesRoot(sourcePaths().map(path=>({path,sha256:hash(bytes(path))})));
 return {bytes,json,walk,sourcePaths,entriesRoot,currentRoot};
}
export function verifyTrust12EvidenceReuse(root=repository, supplied=null){
 const a=api(root),m=supplied??a.json(manifestPath);
 assert(m.schema==="trust12-evidence-reuse-v1"&&m.baselineCommit===baseline,"reuse manifest identity");
 assert(a.entriesRoot(m.preservedInputs)===preservedInputsRoot,"preserved baseline inventory root drift");
 assert(m.currentSourceRootSha256===a.currentRoot(),"reuse current aggregate source root drift");
 assert(new Set(m.preservedInputs.map(e=>e.path)).size===m.preservedInputs.length,"duplicate preserved input");
 for(const e of m.preservedInputs)assert(hash(a.bytes(e.path))===e.sha256,`preserved input drift: ${e.path}`);
 assert(JSON.stringify(m.newInputs.map(({path,owner})=>({path,owner})))===JSON.stringify(newInputs),"new input ownership drift");
 for(const e of m.newInputs)assert(hash(a.bytes(e.path))===e.sha256,`owned new input drift: ${e.path}`);
 const baselineSources=m.preservedInputs.filter(e=>e.path.startsWith("implementation/src/")||e.path.startsWith("implementation/test/"));
 const ownedSource=m.newInputs.filter(e=>!e.path.startsWith("implementation/kontrol/"));
 assert(JSON.stringify([...baselineSources,...ownedSource].map(e=>e.path).concat("foundry.toml").sort())===JSON.stringify(a.sourcePaths()),"unowned or removed implementation input");
 for(const area of ["implementation/kontrol","implementation/certora"]){
   const declared=[...m.preservedInputs,...m.newInputs].filter(e=>e.path.startsWith(area+"/")).map(e=>e.path).sort();
   assert(JSON.stringify(declared)===JSON.stringify(a.walk(area).sort()),`unowned proof input: ${area}`);
 }
 for(const path of extraPaths)assert(m.preservedInputs.some(e=>e.path===path),`missing execution input: ${path}`);
 const oldConfig=m.foundryConfiguration.baselineText;
 const additions=', { access = "read", path = "./out/trust12/trex/out" }, { access = "read", path = "./out/trust12/trex-seeded/out" }';
 const oldPermission='fs_permissions = [{ access = "read", path = "./vectors/conformance-v2.json" }]';
 assert(oldConfig.split(oldPermission).length===2,"baseline file-read permission differs");
 const expected=oldConfig.replace(oldPermission,oldPermission.slice(0,-1)+additions+"]");
 assert(a.bytes("foundry.toml").toString("utf8")===expected,"compiler or execution configuration changed beyond the two Hook artifact reads");
 for(const e of baselineSources.filter(e=>e.path.startsWith("implementation/test/")))assert(!a.bytes(e.path).includes(Buffer.from("out/trust12/")),"legacy detector consumes a new Hook artifact");
 const mutation=a.json("evidence/mutation-results.json");
 assert(hash(a.bytes("evidence/mutation-results.json"))===m.preservedMutation.receiptSha256,"historical mutation receipt changed");
 const oldRoot=a.entriesRoot([...baselineSources,{path:"foundry.toml",sha256:hash(oldConfig)}]);
 assert(oldRoot===mutation.candidateInput.sourceRootSha256&&oldRoot===m.preservedMutation.sourceRootSha256,"historical mutation input root is not reconstructed");
 assert(mutation.total===121&&mutation.killed===121&&mutation.survived===0,"legacy mutation campaign results");
 const expectedProofs=a.json("evidence/evidence-expectations-v3.json");
 for(const [lane,path,field] of [["kontrol","evidence/kontrol-results-v3.json","sourceInputs"],["certora","evidence/certora-results-v3.json","inputs"]]){
   const receipt=a.json(path),expected=expectedProofs[lane];
   assert(hash(a.bytes(path))===m.preservedProofs[lane].receiptSha256,`${lane} historical receipt drift`);
   assert(a.entriesRoot(expected.expectedInputPaths.map(path=>({path,sha256:hash(a.bytes(path))})))===expected.expectedInputsRootSha256,`${lane} frozen input root drift`);
   for(const input of receipt[field])assert(m.preservedInputs.some(e=>e.path===input.path&&e.sha256===input.sha256),`${lane} input outside the preserved closure`);
 }
 return {schema:m.schema,manifest:{path:manifestPath,sha256:hash(a.bytes(manifestPath))},currentSourceRootSha256:m.currentSourceRootSha256,legacyMutationSourceRootSha256:oldRoot,kontrolInputPaths:expectedProofs.kontrol.expectedInputPaths,owners:newInputs,claim:"Legacy exact-input results are preserved. The new Hook and expanded symbolic target receive no legacy proof credit."};
}
export function mutationInputMatches(root,receiptRoot,currentRoot){
 const reuse=verifyTrust12EvidenceReuse(root);
 return reuse.currentSourceRootSha256===currentRoot&&(receiptRoot===currentRoot||reuse.legacyMutationSourceRootSha256===receiptRoot);
}
export function assertTrust12DevelopmentMode(mode){
 assert(mode==="successor-development","TRUST 1.2 checkpoint is development-only: profile-scoped mandatory obligations and release evidence are not closed");
}
function record(){
 const a=api(repository);
 assert(!existsSync(resolve(repository,manifestPath)),"reuse manifest already exists; explicit review is required before supersession");
 const git=args=>execFileSync("git",args,{cwd:repository,maxBuffer:64*1024*1024});
 const list=git(["ls-tree","-r","--name-only",baseline,"--","implementation/src","implementation/test","implementation/kontrol","implementation/certora"]).toString().trim().split("\n");
 const preservedInputs=[...new Set([...list,...extraPaths])].sort().map(path=>({path,sha256:hash(git(["show",`${baseline}:${path}`]))}));
 const mutation=a.json("evidence/mutation-results.json");
 const m={schema:"trust12-evidence-reuse-v1",baselineCommit:baseline,inputCommit:git(["rev-parse","HEAD"]).toString().trim(),currentSourceRootSha256:a.currentRoot(),preservedInputs,newInputs:newInputs.map(e=>({...e,sha256:hash(a.bytes(e.path))})),foundryConfiguration:{baselineText:git(["show",`${baseline}:foundry.toml`]).toString(),permittedChange:"Two read-only T-REX artifact paths used solely by the new integration test; compiler and legacy detector settings are unchanged."},preservedMutation:{receiptPath:"evidence/mutation-results.json",receiptSha256:hash(a.bytes("evidence/mutation-results.json")),sourceRootSha256:mutation.candidateInput.sourceRootSha256,execution:"Historical execution retained without rewriting its candidateInput; all 121 detector, source, vector and campaign inputs are compared here. No new execution is claimed."},preservedProofs:Object.fromEntries(["kontrol","certora"].map(lane=>[lane,{receiptSha256:hash(a.bytes(`evidence/${lane}-results-v3.json`))}])),nonclaim:"The original receipts retain their original execution identities. This receipt proves input preservation, not a new prover run or general runtime correspondence."};
 // Validate before writing; the returned file reference is read only after this preflight.
 for(const e of preservedInputs)assert(hash(a.bytes(e.path))===e.sha256,`baseline drift: ${e.path}`);
 writeFileSync(resolve(repository,manifestPath),encoded(m));
 try{verifyTrust12EvidenceReuse(repository);}catch(error){throw Error(`new reuse manifest failed validation: ${error.message}`);}
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 if(process.argv.includes("--record"))record();
 console.log(JSON.stringify(verifyTrust12EvidenceReuse(),null,2));
}
