#!/usr/bin/env python3
"""Run exact Native bytecode through Oraclizer Veri's bounded observation API.
This executable specification mirrors the named model slice. It is not a HOL
operational-semantics receiver and does not discharge runtime_link.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--veri-root", type=Path, required=True)
    parser.add_argument("--artifact-root", type=Path)
    parser.add_argument("--source-root", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--decoder-mutation", action="store_true")
    args = parser.parse_args()
    from veri_dependency import load_veri, driver_identity
    tool_pin=load_veri(args.veri_root)
    from veri import LocalEVM, Artifact, Storage, CheckFailure, require, encode, decode
    root = Path(__file__).resolve().parents[1]
    artifacts = args.artifact_root or root/"out"
    token_art = Artifact(artifacts/"TrustToken.sol"/"TrustToken.json")
    dep_art = Artifact(artifacts/"MockBoundDependency.sol"/"MockBoundDependency.json")
    normative = json.loads((root/"spec/erc-trust-kernel-v2.json").read_text())
    domain = normative["domain"]["keccak256"]
    zero = "0x"+"00"*32
    addr_zero = "0x"+"00"*20
    source_root = args.source_root or root
    if args.artifact_root and not args.source_root:
        parser.error("--artifact-root requires the exact --source-root")
    source_files = sorted((source_root/"implementation/src").rglob("*.sol"))
    inputs = {str(p.relative_to(source_root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in source_files}
    started = time.monotonic()
    report = {"schema":"oraclizer-veri-native-observations-v1",
              "status":"RUNNING", "claim":"bounded-implementation-evidence",
              "runtimeLinkDischarged":False, "inputSources":inputs, "cases":[],
              "tool":tool_pin,"driver":driver_identity(__file__),
              "artifactSha256":token_art.sha256,
              "scope":{"fork":"cancun", "chainId":31337, "supply":"100",
                       "dependency":"MockBoundDependency/APPLICABLE",
                       "gas":"29000000", "quantification":"listed concrete input pairs",
                       "proofKernelReceiver":False}}
    try:
        with LocalEVM(args.output/"evm") as evm:
            report["backend"] = evm.version
            report["boundSources"] = token_art.bind_sources(evm,source_root) | dep_art.bind_sources(evm,source_root)
            report["compiler"] = token_art.data["metadata"]["compiler"]
            report["compilerSettings"] = token_art.data["metadata"]["settings"]
            owner = evm.accounts[0]
            authority = evm.keccak(b"AUTHORITY")
            schema = evm.keccak(b"SCHEMA-V2")
            config = evm.keccak(b"CONFIG-V1")
            for first, second in [(60,40), (140,120), (2**256-1,2**256-1)]:
                dep, dep_creation = evm.deploy(dep_art, [0,config], "dependency")
                token, creation = evm.deploy(token_art, ["ERC-TRUST Reference","TRUST",18,
                    owner,owner,100,authority,owner,dep,dep,dep,dep,schema], "native")
                st = Storage(evm, token_art, token)
                require(st.read("_totalSupply") == 100, "constructor supply")
                require(st.read("_balances",[owner]) == 100, "constructor balance")
                require(st.read("_frozen",[owner]) == 0, "constructor frozen target")
                require(st.read("_dependencyEpoch") == 1, "constructor epoch")
                require(evm.call(token_art,token,"governor")[0] == owner, "constructor governor")
                require(evm.call(token_art,token,"decimals")[0] == 18, "constructor decimals")
                dep_root, epoch = evm.call(token_art,token,"dependencyState")
                require(st.read("_dependencyRoot") == dep_root, "dependency root decode")
                params = token_art.entry("executeRegulatoryAction")["inputs"]
                receipt_fields = token_art.entry("receipt")["outputs"][0]["components"]
                def request(amount, nonce, case_id):
                    r = dict(zip([c["name"] for c in params[0]["components"]],
                        [domain,zero,0,owner,owner,addr_zero,addr_zero,amount,case_id,
                         dep_root,epoch,evm.keccak(("ORDER"+str(nonce)).encode()),
                         zero,zero,zero,authority,1,nonce,0,2**48-1]))
                    prefix = encode([{"type":"bytes32"},{"type":"address"},{"type":"uint256"}],
                                    [domain,token,31337])
                    r["actionId"] = evm.keccak(prefix+encode(params,[r]))
                    require(evm.call(token_art,token,"deriveActionId",[r])[0] == r["actionId"],
                            "independent action ID mismatch")
                    return r
                case_id = evm.keccak(b"CASE-1")
                r1 = request(first,1,case_id)
                r2 = request(second,2,case_id)
                # The second command uses the same active case, a fresh ID and nonce.
                require(r1["actionId"] != r2["actionId"], "command ID freshness")
                def observation():
                    custody=st.read("_custody",[case_id])
                    freeze_head=st.read("_freezeHeads",[owner])
                    restrict_head=st.read("_restrictionHeads",[owner])
                    cs=st.read("_cases",[case_id])
                    head_type={"type":"tuple","components":[{"name":"actionId","type":"bytes32"},{"name":"generation","type":"uint64"}]}
                    custody_type={"type":"tuple","components":[{"name":"custodian","type":"address"},
                        {"name":"declaredPriorHolder","type":"address"},{"name":"encumberedAmount","type":"uint256"},
                        {"name":"actionId","type":"bytes32"},{"name":"active","type":"bool"}]}
                    case_type={"type":"tuple","components":[{"name":"phase","type":"uint8"},
                        {"name":"family","type":"uint8"},{"name":"headActionId","type":"bytes32"},
                        {"name":"generation","type":"uint64"}]}
                    types=[{"type":t} for t in ("uint256","address","uint256","uint256","bool",
                        "address","uint256","uint256","address","uint256","uint256")]
                    values=[st.read("_totalSupply"),owner,st.read("_balances",[owner]),
                        st.read("_frozen",[owner]),st.read("_restricted",[owner]),
                        owner,st.read("_balances",[owner]),st.read("_custodyBacking",[owner]),
                        addr_zero,st.read("_balances",[addr_zero]),st.read("_custodyBacking",[addr_zero])]
                    return evm.keccak(encode(types+[custody_type,head_type,head_type,case_type],
                        values+[custody,freeze_head,restrict_head,cs]))
                observed_pre_state=observation()

                success = evm.transaction(token_art,token,"executeRegulatoryAction",[r1],"freeze")
                require(int(success["receipt"]["status"],16) == 1, "FREEZE success")
                require(st.read("_balances",[owner]) == 100 and st.read("_totalSupply") == 100,
                        "FREEZE changed balance or supply")
                frozen_label = "_balances" if args.decoder_mutation else "_frozen"
                require(st.read(frozen_label,[owner]) == first, "stored frozen target mismatch")
                require(evm.call(token_art,token,"getFrozenTokens",[owner])[0] == min(first,100),
                        "saturating public frozen observation")
                receipt_value = evm.call(token_art,token,"receipt",[r1["actionId"]])[0]
                receipt_map = dict(zip([p["name"] for p in receipt_fields],receipt_value))
                require(st.read("_receipts",[r1["actionId"]]) == receipt_map,
                        "stored receipt/ABI receipt mismatch")
                expected_receipt = {"receiptKind":1, "commandId":r1["actionId"],"commandKind":0,
                    "parentCommandId":zero,"subject":owner,"source":owner,"destination":addr_zero,
                    "amount":first,"caseId":case_id,"authorityRef":authority,"dependencyRoot":dep_root,
                    "provenanceCommitment":r1["provenanceCommitment"],"externalCommitment":zero}
                require(all(receipt_map[k] == v for k,v in expected_receipt.items()),
                        "receipt field source mismatch")
                action_record = st.read("_actions",[r1["actionId"]])
                require(action_record["lifecycle"] == 2 and action_record["amount"] == first
                        and action_record["priorAmount"] == 0, "FREEZE action record")
                case_record = st.read("_cases",[case_id])
                require(case_record == {"phase":1,"family":1,"headActionId":r1["actionId"],"generation":1},
                        "FREEZE case transition")
                require(st.read("_freezeHeads",[owner])["actionId"] == r1["actionId"],
                        "FREEZE effect head")
                require(receipt_map["commandId"] == r1["actionId"] and receipt_map["amount"] == first,
                        "receipt command/amount mismatch")
                require(receipt_map["subject"] == owner and receipt_map["caseId"] == case_id,
                        "receipt subject/case mismatch")
                require(receipt_map["preState"] == observed_pre_state and receipt_map["postState"] == observation(),
                        "receipt state observation mismatch")
                receipt_hash = evm.keccak(encode([{"type":"bytes32"}]+receipt_fields[:-1],
                                               [domain]+receipt_value[:-1]))
                require(receipt_hash == receipt_map["receiptHash"], "receipt preimage mismatch")
                require(decode([{"type":"bytes32"}],success["returnData"])[0] == receipt_hash,
                        "actual execution return hash")
                logs = success["receipt"]["logs"]
                require(len(logs) == 2, "FREEZE event count")
                frozen_topic = evm.keccak(b"Frozen(address,uint256)")
                receipt_topic = evm.keccak(b"RegulatoryActionApplied(bytes32,uint8,bytes32,bytes32)")
                require(logs[0]["address"] == token and logs[0]["topics"] ==
                    [frozen_topic,"0x"+encode([{"type":"address"}],[owner]).hex()] and
                    decode([{"type":"uint256"}],logs[0]["data"]) == [first], "Frozen event semantics")
                require(logs[1]["address"] == token and logs[1]["topics"] ==
                    [receipt_topic,r1["actionId"],zero,case_id] and
                    decode([{"type":"bytes32"}],logs[1]["data"]) == [receipt_hash],
                    "final receipt event semantics")
                calls = success["callTree"].get("calls",[])
                require(calls and all(c["type"] == "STATICCALL" and c["to"] == dep for c in calls),
                        "dependency call target/type")
                assess = [c for c in calls if c["input"].startswith(
                    evm.keccak(b"assess(bytes32,uint8,address,address,uint256,bytes32,uint64)")[:10])]
                require(len(assess) == 1, "one actual policy assessment")
                actual_assess = decode(dep_art.entry("assess")["inputs"],"0x"+assess[0]["input"][10:])
                prefix = encode([{"type":"bytes32"},{"type":"address"},{"type":"uint256"}],
                                [domain,token,31337])
                command_hash = evm.keccak(prefix+encode(params,[r1]))
                require(actual_assess[:5] == [command_hash,0,owner,addr_zero,first],
                        "assessment calldata binding")
                code_id=evm.keccak(bytes.fromhex(evm.rpc("eth_getCode",dep,"latest")[2:]))
                binding_types=[{"type":t} for t in ("bytes32","uint8","address","bytes32","bytes32","bytes32","uint64")]
                policy_binding=evm.keccak(encode(binding_types,[domain,0,dep,code_id,config,schema,1]))
                require(actual_assess[5:] == [policy_binding,1],"assessment binding hash or epoch")

                assessed = decode(dep_art.entry("assess")["outputs"],assess[0]["output"])
                require(assessed == [0,command_hash,actual_assess[5],
                        evm.keccak(encode([{"type":"bytes32"},{"type":"bytes32"}],[config,command_hash]))],
                        "assessment return semantics")
                require(assessed[3] == receipt_map["assessmentEvidence"], "assessment receipt evidence")
                require(st.read("_usedNonces",[authority,1,1]) is True, "success nonce consumption")
                require(st.read("_usedNonces",[authority,1,2]) is False, "rejection nonce fresh")
                before = {"frozen":st.read("_frozen",[owner]), "balance":st.read("_balances",[owner]),
                          "case":st.read("_cases",[case_id]), "head":st.read("_freezeHeads",[owner]),
                          "receipt":st.read("_receipts",[r2["actionId"]])}
                rejection = evm.transaction(token_art,token,"executeRegulatoryAction",[r2],"reject")
                require(int(rejection["receipt"]["status"],16) == 0, "nonincreasing target accepted")
                expected = evm.keccak(b"TrustInvalidCommand(bytes32,uint16)")[:10] + encode(
                    [{"type":"bytes32"},{"type":"uint16"}],[r2["actionId"],12]).hex()
                require(rejection["returnData"] == expected, "wrong rejection reason or command ID")
                require(rejection["receipt"]["logs"] == [], "revert leaked logs")
                require(rejection["callTree"].get("calls",[]) == [], "direction rejection made dependency call")
                after = {"frozen":st.read("_frozen",[owner]), "balance":st.read("_balances",[owner]),
                         "case":st.read("_cases",[case_id]), "head":st.read("_freezeHeads",[owner]),
                         "receipt":st.read("_receipts",[r2["actionId"]])}
                require(before == after, "rejection storage rollback")
                require(st.read("_usedNonces",[authority,1,2]) is False, "rejection consumed nonce")
                require(st.read("_entered") == 0, "reentrancy frame did not roll back")
                trace_path = args.output/"evm"/(str(len(evm.observations)-1)+"-reject-trace.json")
                trace = json.loads(trace_path.read_text())
                writes = {int(s["stack"][-1],16) for s in trace["structLogs"] if s["op"] == "SSTORE"}
                require(writes, "rollback control never reached a state write")
                for slot in writes:
                    require(st.word(slot,rejection["beforeBlock"]) == st.word(slot), "written slot did not roll back")
                report["cases"].append({"first":str(first),"second":str(second),"status":"PASS",
                    "runtimeSha256":creation["runtimeSha256"],"constructor":creation["hash"],
                    "success":success["hash"],"rejection":rejection["hash"],
                    "receiptHash":receipt_hash,"storedFrozen":str(after["frozen"]),
                    "rollbackWrittenSlots":[str(s) for s in sorted(writes)]})
            report["observations"] = evm.observations
            report["stateAndViewReads"] = evm.reads
            report["status"] = "PASS"
    except Exception as error:
        report["status"] = "FAIL"
        report["error"] = type(error).__name__+": "+str(error)
    if "evm" in locals():
        report["observations"] = evm.observations
        report["stateAndViewReads"] = evm.reads
    report["elapsedSeconds"] = round(time.monotonic()-started,3)
    args.output.mkdir(parents=True,exist_ok=True)
    (args.output/"result.json").write_text(json.dumps(report,indent=2)+"\n")
    print(json.dumps({k:report[k] for k in ("status","cases","elapsedSeconds")} |
                     ({"error":report["error"]} if "error" in report else {})))
    return 0 if report["status"] == "PASS" else 1

if __name__ == "__main__":
    sys.exit(main())
