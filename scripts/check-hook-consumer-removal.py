#!/usr/bin/env python3
"""Replay one semantic consumer-removal negative on an isolated T-REX integration build."""
from pathlib import Path
import hashlib, json, re, shutil, subprocess, sys, time

root=Path(__file__).resolve().parents[1]
kind=sys.argv[1] if len(sys.argv)>1 else "inbound"
cases={
 "inbound":("ERC3643HookAdapter.sol",
    "if (to != address(0) && to != from) _syncFrozen(bytes32(0), to);",
    "/* incoming frozen-target consumer removed */",
    "testHookInboundCannotEscapeInSameTransaction","hook did not freeze inbound",
    "seal, FREEZE, SEIZE, ordinary inbound, actual frozen-floor assertion"),
 "initial":("ERC3643HookDeployment.sol",
    'require(keccak256(tokenCreationCode) == TOKEN_CREATION_HASH, "unapproved token creation code");',
    "/* fresh initial-state source pin removed */",
    "testHookDirectFreshZeroSupplyAndCreationPins","seeded initial state was admitted",
    "real upstream with undeclared initial restriction was created and admitted"),
 "receipt":("ERC3643HookAdapter.sol",
    "_upstreamRestricted(commandId, source)","false",
    "testHookReceiptObservesRestrictedCustodySource","wrong actual pre-observation",
    "SEIZE, custody-source RESTRICT, disposition, independent actual-state receipt comparison")
 ,"callback-auth":("ERC3643HookAdapter.sol",
    "if (msg.sender != profileGovernor.compliance()) revert TrustUnauthorized(msg.sender, bytes32(0));",
    "/* bound Compliance caller check removed */",
    "testHookFactoryFreshStateAndAuthorityClosure","unauthenticated callback",
    "fresh unit, unauthorized callback invocation, exact caller rejection assertion")
 ,"hidden-agent":("ERC3643HookDeployment.sol",
    "upstream.addAgent(address(this));",
    "upstream.addAgent(address(this)); upstream.addAgent(address(0xbad));",
    "testHookFactoryFreshStateAndAuthorityClosure","hidden Agent admitted",
    "fresh unit sealed with an added undeclared Agent, sole-Agent assertion")
 ,"factory-pin":("ERC3643HookFactory.sol",
    'require(keccak256(adapterCreationCode) == ADAPTER_CREATION_HASH, "unapproved adapter creation code");',
    "/* endpoint creation-code admission check removed */",
    "testHookDirectFreshZeroSupplyAndCreationPins","factory accepted bypass endpoint",
    "factory deployed and accepted a constructible endpoint that implements no TRUST behavior")
}
if kind not in cases:
    raise SystemExit("choose inbound, initial, receipt, callback-auth, hidden-agent, or factory-pin")
filename,consumer,replacement,detector,message,milestone=cases[kind]
started=time.monotonic()
work=root/"out/trust12"/("mutation-"+kind)
work.mkdir(parents=True,exist_ok=True)
for part in ("src","test"):
    shutil.copytree(root/"implementation"/part,work/"implementation"/part,dirs_exist_ok=True)
shutil.copytree(root/"vectors",work/"vectors",dirs_exist_ok=True)
shutil.copy2(root/"foundry.toml",work/"foundry.toml")
for variant in ("trex","trex-seeded"):
    artifact=Path("out/trust12")/variant/"out/Token.sol/Token.json"
    (work/artifact).parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(root/artifact,work/artifact)
target=work/"implementation/src/profiles"/filename
source=target.read_text()
if source.count(consumer)!=1: raise RuntimeError("consumer identity drift")
target.write_text(source.replace(consumer,replacement),encoding="utf8")
# This non-target custody adjustment lets the deliberately mutated endpoint reach its
# semantic consumer. It is explicitly recorded, never applied to the product factory.
subprocess.run(["forge","build"],cwd=work,check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
creation=subprocess.check_output(["forge","inspect","ERC3643HookAdapter","bytecode"],cwd=work,text=True).strip()
mutant_pin=subprocess.check_output(["cast","keccak",creation],text=True).strip()
factory=work/"implementation/src/profiles/ERC3643HookFactory.sol"
body,count=re.subn(r"ADAPTER_CREATION_HASH\s*=\s*0x[0-9a-fA-F]{64}",
    "ADAPTER_CREATION_HASH = "+mutant_pin,factory.read_text())
if count!=1: raise RuntimeError("factory pin anchor drift")
factory.write_text(body)
result=subprocess.run(["forge","test","--match-contract","ERC3643HookTrexIntegrationTest",
    "--match-test",detector,"-vv"],cwd=work,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
(work/"run.log").write_text(result.stdout)
killed=message in result.stdout and result.returncode!=0
report={"mutation":kind,"status":"KILLED" if killed else "FAIL","semanticMilestone":milestone,
    "factoryPinReboundForSemanticReach":mutant_pin,"exitCode":result.returncode,
    "secondsIncludingBuild":round(time.monotonic()-started,3),
    "sourcePath":"implementation/src/profiles/"+filename,
    "originalSha256":hashlib.sha256(source.encode()).hexdigest(),
    "mutantSha256":hashlib.sha256(target.read_bytes()).hexdigest(),"detector":detector,
    "nonclaim":"A semantic negative detector, not behavioral equivalence or exhaustive coverage."}
(work/"result.json").write_text(json.dumps(report,indent=2)+"\n")
print(result.stdout)
print(json.dumps(report,indent=2))
if not killed: raise SystemExit(1)
