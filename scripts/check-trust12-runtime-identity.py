#!/usr/bin/env python3
"""Check factory pins, legacy identity, and the copied HookAdapter kernel surface."""
from pathlib import Path
import hashlib, json, re, subprocess, sys
root=Path(__file__).resolve().parents[1]
expected={
 "TrustToken":"b82010913d2b6f1f7778c48d05a63e73c7498b62f8829f0ed33a86783c0667c1",
 "ERC3643TrustAdapter":"7a2dfa433911dd37e389498129356db30693e8ee8e128f8da63a5d3044a56349",
 "ProfileGovernor":"78c08fbe4be793482e44a8cdf32fcc1af3276277c8cc78f48761fdcbc4bf9399"}
contracts=[*expected,"ERC3643HookAdapter","ERC3643HookGovernor","ERC3643HookCompliance","ERC3643HookFactory"]
runtimes={}
artifacts={}
for name in contracts:
    artifact=json.loads((root/"out"/(name+".sol")/(name+".json")).read_text())
    artifacts[name]=artifact
    runtime=bytes.fromhex(artifact["deployedBytecode"]["object"].removeprefix("0x"))
    creation=bytes.fromhex(artifact["bytecode"]["object"].removeprefix("0x"))
    digest=hashlib.sha256(runtime).hexdigest()
    if name in expected and digest!=expected[name]:
        raise RuntimeError("legacy runtime changed: "+name)
    if len(runtime)>24576 or len(creation)>49152:
        raise RuntimeError("contract size limit: "+name)
    runtimes[name]={"runtimeSha256":digest,"runtimeBytes":len(runtime),"creationBytes":len(creation)}
legacy_sources=[
 "implementation/src/profiles/ERC3643TrustAdapter.sol",
 "implementation/src/profiles/ProfileGovernor.sol"]
for path in legacy_sources:
    baseline=subprocess.check_output(
        ["git","show","2545efa64289ad82fe3ad8a99e5dfad01ff92c10:"+path],cwd=root)
    if baseline != (root/path).read_bytes():
        raise RuntimeError("legacy source changed: "+path)

def function_bodies(contract_name):
    source=(root/"implementation/src/profiles"/(contract_name+".sol")).read_text()
    contract=next(
        node for node in artifacts[contract_name]["ast"]["nodes"]
        if node["nodeType"]=="ContractDefinition" and node["name"]==contract_name)
    bodies={}
    for function in (node for node in contract["nodes"] if node["nodeType"]=="FunctionDefinition"):
        parameters=",".join(
            parameter["typeDescriptions"]["typeString"]
            for parameter in function["parameters"]["parameters"])
        key=f'{function["kind"]}:{function["name"]}:{parameters}'
        if function["body"] is None:
            bodies[key]=""
            continue
        start,length,_=map(int,function["body"]["src"].split(":"))
        bodies[key]=re.sub(r"\s+","",source[start:start+length])
    return bodies

partial_bodies=function_bodies("ERC3643TrustAdapter")
hook_bodies=function_bodies("ERC3643HookAdapter")
only_partial=set(partial_bodies)-set(hook_bodies)
only_hook=set(hook_bodies)-set(partial_bodies)
expected_only_partial={"constructor::address,address,bytes32"}
expected_only_hook={
 "constructor::address,address,bytes32,address,uint256,address[]",
 "function:_activateEmptySeal:",
 "function:onTokenBalanceChanged:address,address",
 "function:_profileSchema:"}
if only_partial!=expected_only_partial or only_hook!=expected_only_hook:
    raise RuntimeError("HookAdapter kernel function surface drift")
allowed_body_differences={
 "function:supportsInterface:bytes4",
 "function:trustProfile:",
 "function:_bind:enum TrustKernelTypes.BindingKind,address,bytes32"}
actual_body_differences={
    key for key in set(partial_bodies)&set(hook_bodies)
    if partial_bodies[key]!=hook_bodies[key]}
if actual_body_differences!=allowed_body_differences:
    raise RuntimeError("unexpected HookAdapter kernel body drift")

hook=artifacts["ERC3643HookAdapter"]
creation_keccak=subprocess.check_output(["cast","keccak",hook["bytecode"]["object"]],text=True).strip()
factory=(root/"implementation/src/profiles/ERC3643HookFactory.sol").read_text()
match=re.search(r"ADAPTER_CREATION_HASH\s*=\s*(0x[0-9a-fA-F]{64})",factory)
if not match or match.group(1)!=creation_keccak:
    raise RuntimeError("factory does not admit the current endpoint creation code")
paths=sorted([root/"foundry.toml",*root.glob("implementation/src/**/*.sol")],key=lambda p:p.relative_to(root).as_posix())
inputs=[{"path":p.relative_to(root).as_posix(),"sha256":hashlib.sha256(p.read_bytes()).hexdigest()} for p in paths]
report={"schema":"trust12-runtime-identity-v1","status":"PASS",
    "baselineCommit":"2545efa64289ad82fe3ad8a99e5dfad01ff92c10",
    "legacySourcePreserved":legacy_sources,"legacyRuntimePreserved":list(expected),"runtimes":runtimes,
    "sharedKernel":{"commonFunctionBodies":len(set(partial_bodies)&set(hook_bodies)),
      "allowedBodyDifferences":sorted(allowed_body_differences),
      "hookOnlyFunctions":sorted(expected_only_hook)},
    "factoryAdapterCreationKeccak256":creation_keccak,
    "sourceInputs":inputs,"compiler":{"solc":"0.8.36","evm":"cancun","viaIR":True,"optimizerRuns":1},
    "upstream":{"name":"Tokeny T-REX","tag":"4.1.3","commit":"0fa344b761cf861bb9e8e1c8e472ba72815316c2",
      "compiler":"0.8.17","evm":"london","viaIR":False,"optimizerRuns":200,
      "creationKeccak256":"0x1278126a159c0439e8defb9b59f26ae2ad6790cb0c99d81a0722a0bb23ab9438",
      "runtimeKeccak256":"0x62d82077b0b4b127a9f788f8482841166e1e9f788d760d24c4d698cf7d517931"},
    "nonclaim":"Identity and size checks only. Model changes, symbolic proofs, profile conformance, deployment and end-to-end refinement have separate evidence."}
if "--write" in sys.argv:
    dest=root/"evidence/trust12/runtime-identity.json";dest.parent.mkdir(parents=True,exist_ok=True)
    dest.write_text(json.dumps(report,indent=2)+"\n")
print(json.dumps({k:v for k,v in report.items() if k!="sourceInputs"},indent=2))
