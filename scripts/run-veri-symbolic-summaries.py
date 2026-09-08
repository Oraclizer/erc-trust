#!/usr/bin/env python3
"""Prove a dependency summary, then consume checked summaries in the full-domain target."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--project",type=Path,required=True)
    ap.add_argument("--output",type=Path,required=True)
    args=ap.parse_args()
    root=Path(__file__).resolve().parents[1]
    project=args.project.resolve()
    args.output.mkdir(parents=True,exist_ok=False)
    for p in (root/"implementation").rglob("*"):
        if p.is_file() and p.read_bytes()!=(project/p.relative_to(root)).read_bytes():
            raise RuntimeError("summary input drift")
    if (root/"foundry.toml").read_bytes()!=(project/"foundry.toml").read_bytes():
        raise RuntimeError("summary configuration drift")
    if (project/"out/proofs").exists():
        shutil.copytree(project/"out/proofs",args.output/"prior-proofs")
    kontrol=shutil.which("kontrol")
    env=os.environ|{"FOUNDRY_PROFILE":"kontrol"}
    common=[kontrol,"prove","--foundry-project-root",str(project),"--workers","1",
            "--max-depth","10000","--max-iterations","1000","--smt-timeout","10000",
            "--schedule","CANCUN","--use-booster","--reinit"]
    commands=[
      ("configuration-summary",common+["--match-test","MockBoundDependency.configurationDigest()","--cse"],300),
      ("assess-summary",common+["--match-test","MockBoundDependency.assess(bytes32,uint8,address,address,uint256,bytes32,uint64)","--cse"],300),
      ("native-with-summaries",common+["--match-test","TrustTokenDeferredSymbolicKontrolTest.testKontrol_DeferredSymbolicNonincreasingFreeze()",
         "--include-summary","MockBoundDependency.configurationDigest():0",
         "--include-summary","MockBoundDependency.assess(bytes32,uint8,address,address,uint256,bytes32,uint64):0"],900)]
    report={"schema":"trust-checked-summary-attempt-v1","status":"RUNNING","runs":[],"runtimeLinkDischarged":False}
    for name,command,budget in commands:
        start=time.monotonic()
        with (args.output/(name+".log")).open("x") as log:
            p=subprocess.run(["timeout","--signal=TERM","--kill-after=10s",str(budget)+"s"]+command,
                  cwd=project,env=env,stdout=log,stderr=subprocess.STDOUT)
        report["runs"].append({"name":name,"exit":p.returncode,"elapsedSeconds":round(time.monotonic()-start,3)})
        report["status"]="CHECK_REQUIRED" if p.returncode==0 else "TIMEOUT" if p.returncode in (124,137) else "FAIL"
        (args.output/"result.json").write_text(json.dumps(report,indent=2)+"\n")
        print(json.dumps(report),flush=True)
        if p.returncode!=0: break
    return 0 if report["status"]=="CHECK_REQUIRED" else 1
if __name__=="__main__": sys.exit(main())
