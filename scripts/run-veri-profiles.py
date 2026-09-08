#!/usr/bin/env python3
"""Separate bounded Partial and actual T-REX Hook observations using Veri."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import time

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--veri-root",type=Path,required=True)
    ap.add_argument("--output",type=Path,required=True)
    args=ap.parse_args()
    from veri_dependency import load_veri, driver_identity
    tool_pin=load_veri(args.veri_root)
    from veri import LocalEVM, Artifact, Storage, require, encode, decode
    from veri.abi import signature
    root=Path(__file__).resolve().parents[1]
    def artifact(name,filename=None):
        a = Artifact(root/"out"/((filename or name)+".sol")/(name+".json"))
        a.bind_sources(evm,root)
        return a
    args.output.mkdir(parents=True,exist_ok=False)
    report={"schema":"oraclizer-veri-profiles-v1","status":"RUNNING","runtimeLinkDischarged":False,
            "claim":"bounded-implementation-evidence","profiles":[],"tool":tool_pin,"driver":driver_identity(__file__)}
    started=time.monotonic()
    try:
        with LocalEVM(args.output/"evm") as evm:
            owner,holder,buyer=evm.accounts[:3]
            zero="0x"+"00"*32
            azero="0x"+"00"*20
            domain=evm.keccak(b"ERC-TRUST/v2")
            authority=evm.keccak(b"ERC3643-AUTHORITY")
            # Arrays are deliberately encoded by the pinned Foundry cast ABI backend.
            # The same Veri execution and storage code is used for both profiles.
            def array_call(art,address,name,values,label):
                entry=art.entry(name)
                proc=subprocess.run(["cast","calldata",signature(entry)]+values,
                                    capture_output=True,text=True,check=True)
                return evm.transact(proc.stdout.strip(),address,label=label)
            def ok(result,message):
                require(int(result["receipt"]["status"],16)==1,message)
                return result
            for profile in ("partial","hook"):
                if profile=="partial":
                    identity_art=artifact("MockERC3643IdentityRegistry","MockERC3643Dependencies")
                    compliance_art=artifact("MockERC3643Compliance","MockERC3643Dependencies")
                    identity,_=evm.deploy(identity_art,[],"identity")
                    compliance,_=evm.deploy(compliance_art,[],"compliance")
                    for account in (owner,holder,buyer):
                        ok(evm.transaction(identity_art,identity,"setVerified",[account,True]),"identity registration")
                    token_art=artifact("MockERC3643TokenTrex")
                    token,_=evm.deploy(token_art,[identity,compliance,1000],"partial-token")
                    gov_art=artifact("ProfileGovernor")
                    code=bytes.fromhex(evm.rpc("eth_getCode",token,"latest")[2:])
                    governor,_=evm.deploy(gov_art,[token,identity,compliance,owner,evm.keccak(code)],"partial-governor")
                    art=artifact("ERC3643TrustAdapter")
                    endpoint,_=evm.deploy(art,[governor,owner,authority],"partial-adapter")
                    ok(evm.transaction(identity_art,identity,"setVerified",[endpoint,True]),"adapter identity")
                    ok(evm.transaction(token_art,token,"setExclusiveAgent",[endpoint]),"exclusive agent")
                    ok(evm.transaction(token_art,token,"transferOwnership",[governor]),"owner transfer")
                    ok(array_call(gov_art,governor,"seal",[endpoint,"[]"],"partial-seal"),"partial seal")
                else:
                    token_art=Artifact(root/"out/trust12/trex/out/Token.sol/Token.json")
                    factory_art=artifact("ERC3643HookFactory")
                    factory,_=evm.deploy(factory_art,[token_art.creation],"hook-factory")
                    art=artifact("ERC3643HookAdapter")
                    deployed=ok(array_call(factory_art,factory,"deploy",
                        [art.creation,owner,authority,owner,"1000","["+holder+","+buyer+"]"],
                        "hook-unit"),"hook factory deployment")
                    token,endpoint,governor=decode(factory_art.entry("deploy")["outputs"],deployed["returnData"])
                    art.check_runtime(evm.rpc("eth_getCode",endpoint,"latest"))
                    token_art.check_runtime(evm.rpc("eth_getCode",token,"latest"))
                    topic=evm.keccak(b"HookUnitCreated(address,address,address)")
                    require(deployed["receipt"]["logs"][-1]["topics"]==
                        [topic]+["0x"+encode([{"type":"address"}],[a]).hex() for a in (token,endpoint,governor)],
                        "factory final event")
                st=Storage(evm,art,endpoint)
                desc=evm.call(art,endpoint,"trustProfile")[0]
                require(desc[7] is (profile=="hook"),"profile full flag")
                require(evm.call(art,endpoint,"sealedTopologyLive")==[True],"sealed topology")
                require(evm.call(token_art,token,"owner")==[governor],"token owner")
                ok(evm.transaction(token_art,token,"transfer",[holder,100],"seed-holder"),"holder seed")
                dep_root,epoch=evm.call(art,endpoint,"dependencyState")
                fields=art.entry("executeRegulatoryAction")["inputs"][0]["components"]
                def request(kind,nonce,amount,case):
                    r=dict(zip([p["name"] for p in fields],[domain,zero,kind,holder,holder,
                        endpoint if kind==1 else azero,endpoint if kind==1 else azero,amount,
                        case,dep_root,epoch,evm.keccak(("ORDER"+str(nonce)).encode()),
                        zero,zero,zero,authority,1,nonce,0,2**48-1]))
                    prefix=encode([{"type":"bytes32"},{"type":"address"},{"type":"uint256"}],
                                  [domain,endpoint,31337])
                    r["actionId"]=evm.keccak(prefix+encode([{"type":"tuple","components":fields}],[r]))
                    require(evm.call(art,endpoint,"deriveActionId",[r])==[r["actionId"]],"profile action hash")
                    return r
                freeze=request(0,1,100,evm.keccak(b"FREEZE-CASE"))
                frozen=ok(evm.transaction(art,endpoint,"executeRegulatoryAction",[freeze],"profile-freeze"),"profile freeze")
                require(evm.call(token_art,token,"getFrozenTokens",[holder])==[100],"upstream frozen")
                receipt_fields=art.entry("receipt")["outputs"][0]["components"]
                receipt=evm.call(art,endpoint,"receipt",[freeze["actionId"]])[0]
                require(st.read("_receipts",[freeze["actionId"]])==
                        dict(zip([p["name"] for p in receipt_fields],receipt)),"profile stored receipt")
                receipt_hash=evm.keccak(encode([{"type":"bytes32"}]+receipt_fields[:-1],[domain]+receipt[:-1]))
                require(decode([{"type":"bytes32"}],frozen["returnData"])==[receipt_hash],"profile receipt return")
                require(frozen["receipt"]["logs"][-1]["address"]==endpoint and
                        frozen["receipt"]["logs"][-1]["data"]==receipt_hash,"profile final receipt")
                rejected=request(0,2,80,freeze["caseId"])
                rejection=evm.transaction(art,endpoint,"executeRegulatoryAction",[rejected],"profile-reject")
                require(int(rejection["receipt"]["status"],16)==0 and rejection["receipt"]["logs"]==[],"profile rejection")
                require(rejection["returnData"]==evm.keccak(b"TrustInvalidCommand(bytes32,uint16)")[:10]+
                        encode([{"type":"bytes32"},{"type":"uint16"}],[rejected["actionId"],12]).hex(),
                        "profile exact direction reason")
                require(st.read("_usedNonces",[evm.keccak(encode([{ "type":"bytes32"},{"type":"bytes32"},{"type":"uint64"},{"type":"uint256"}],[domain,authority,1,2]))]) is False and st.read("_entered")==0,"profile rollback")
                seizure=request(1,3,30,evm.keccak(b"SEIZE-CASE"))
                ok(evm.transaction(art,endpoint,"executeRegulatoryAction",[seizure],"seize"),"profile seize")
                require(evm.call(token_art,token,"getFrozenTokens",[holder])==[70],"post-seize saturation")
                inbound=ok(evm.transaction(token_art,token,"transfer",[holder,30],"inbound"),"inbound")
                expected=100 if profile=="hook" else 70
                require(evm.call(token_art,token,"getFrozenTokens",[holder])==[expected],"inbound profile semantics")
                attempted=evm.transact(token_art.calldata(evm,"transfer",[buyer,30]),token,sender=holder,label="outbound")
                require(int(attempted["receipt"]["status"],16)==(0 if profile=="hook" else 1),
                        "inbound escape boundary")
                if profile=="hook":
                    callback=evm.transaction(art,endpoint,"onTokenBalanceChanged",[owner,buyer],"forged-callback")
                    require(int(callback["receipt"]["status"],16)==0,"unauthorized callback")
                    route_controls=[]
                    def rejected_control(result,name):
                        require(int(result["receipt"]["status"],16)==0 and
                                result["receipt"]["logs"]==[],name+" was not rejected cleanly")
                        route_controls.append(name)
                    for name,values in [
                        ("removeAgent",[endpoint]),("renounceOwnership",[]),
                        ("setIdentityRegistry",[buyer]),("setCompliance",[buyer]),
                        ("transferOwnership",[buyer]),("setName",["Changed"]),("setSymbol",["X"]),
                        ("setOnchainID",[buyer]),("pause",[]),("unpause",[]),
                        ("unfreezePartialTokens",[holder,1]),("freezePartialTokens",[holder,1]),
                        ("mint",[buyer,1]),("burn",[holder,1]),("setAddressFrozen",[holder,True])]:
                        rejected_control(evm.transaction(token_art,token,name,values,"authority-"+name),name)
                    for name,values in [
                        ("batchMint",["["+buyer+"]","[1]"]),
                        ("batchBurn",["["+holder+"]","[1]"]),
                        ("batchSetAddressFrozen",["["+holder+"]","[true]"]),
                        ("batchFreezePartialTokens",["["+holder+"]","[1]"]),
                        ("batchUnfreezePartialTokens",["["+holder+"]","[1]"]),
                        ("batchForcedTransfer",["["+holder+"]","["+buyer+"]","[1]"])]:
                        rejected_control(array_call(token_art,token,name,values,"authority-"+name),name)
                    hook_art=artifact("ERC3643HookCompliance")
                    hook=evm.call(token_art,token,"compliance")[0]
                    for name,values in [("transferred",[owner,buyer,1]),("created",[buyer,1]),
                        ("destroyed",[holder,1]),("bindToken",[token]),("unbindToken",[token]),
                        ("activate",[endpoint])]:
                        rejected_control(evm.transaction(hook_art,hook,name,values,"hook-"+name),name)
                    sync=ok(evm.transaction(art,endpoint,"resynchroniseFrozen",[holder],"resynchronise"),"permissionless sync")
                    require(decode([{"type":"uint256"}],sync["returnData"])==[100],"resynchronise amount")
                    again=ok(evm.transaction(art,endpoint,"resynchroniseFrozen",[holder],"resynchronise-again"),"idempotent sync")
                    require(decode([{"type":"uint256"}],again["returnData"])==[100],"resynchronise idempotence")
                    balances=[evm.call(token_art,token,"balanceOf",[a])[0] for a in (owner,holder)]
                    batch=array_call(token_art,token,"batchTransfer",
                                     ["["+holder+","+azero+"]","[1,1]"],"batch-revert")
                    rejected_control(batch,"batch atomic rollback")
                    require([evm.call(token_art,token,"balanceOf",[a])[0] for a in (owner,holder)]==balances,
                            "batch retained an earlier transfer")
                    trace=json.loads((args.output/"evm"/(str(len(evm.observations)-1)+"-batch-revert-trace.json")).read_text())
                    require(any(s["op"]=="LOG3" for s in trace["structLogs"]),
                            "batch control never reached earlier Transfer emission")
                    require(evm.call(token_art,token,"getFrozenTokens",[holder])==[100],"batch retained hook state")
                    rejected_control(evm.transaction(token_art,token,"addAgent",[buyer],"authority-addAgent"),"addAgent")
                    rejected_control(evm.transaction(token_art,token,"forcedTransfer",[holder,buyer,1],"authority-forcedTransfer"),"forcedTransfer")
                    rejected_control(evm.transaction(token_art,token,"recoveryAddress",[holder,buyer,buyer],"authority-recovery"),"recoveryAddress")
                    registry=evm.call(token_art,token,"identityRegistry")[0]
                    rejected_control(evm.transaction(token_art,token,"init",
                        [registry,hook,"TRUST T-REX","TRX",18,azero],"repeat-init"),"repeat init")
                    hook_gov=artifact("ERC3643HookGovernor")
                    rejected_control(evm.transaction(hook_gov,governor,"sealFresh",[],"repeat-seal"),"sealFresh")
                    rejected_control(array_call(art,endpoint,"activateSeal",["[]"],"repeat-activation"),"activateSeal")
                    snapshot=evm.rpc("evm_snapshot")
                    evm.rpc("anvil_setCode",hook,"0x00")
                    rejected_control(evm.transaction(art,endpoint,"resynchroniseFrozen",[holder],"sync-topology-drift"),
                                     "resynchronise topology drift")
                    require(evm.rpc("evm_revert",snapshot),"restore topology control")

                    report["hookRouteControls"]=route_controls

                report["profiles"].append({"profile":profile,"status":"PASS","storedReceipt":receipt_hash,
                    "underlying":"Tokeny T-REX 4.1.3" if profile=="hook" else "clean-room ERC3643 fixture",
                    "inboundFrozen":str(expected),"outboundAfterInbound":"rejected" if profile=="hook" else "allowed",
                    "fullConformanceFlag":profile=="hook"})
            report["observations"]=evm.observations
            report["stateAndViewReads"]=evm.reads
            report["status"]="PASS"
    except Exception as error:
        report["status"]="FAIL"
        report["error"]=type(error).__name__+": "+str(error)
    if "evm" in locals():
        report["observations"]=evm.observations
        report["stateAndViewReads"]=evm.reads
    report["elapsedSeconds"]=round(time.monotonic()-started,3)
    (args.output/"result.json").write_text(json.dumps(report,indent=2)+"\n")
    print(json.dumps({k:report[k] for k in ("status","profiles","elapsedSeconds")}|
                    ({"error":report["error"]} if "error" in report else {})))
    return 0 if report["status"]=="PASS" else 1

if __name__=="__main__":
    sys.exit(main())
