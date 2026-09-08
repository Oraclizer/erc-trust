#!/usr/bin/env python3
"""Isolated deferred-symbolic feasibility run. Timeout is never proof credit."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

root=Path(__file__).resolve().parents[1]
ap=argparse.ArgumentParser()
ap.add_argument("--resume-prove",action="store_true")
ap.add_argument("--project",type=Path)
ap.add_argument("--build-only",action="store_true")
args=ap.parse_args()
lane=args.project.resolve() if args.project else root/"out/trust12/deferred-symbolic"
if not args.resume_prove: lane.mkdir(parents=True,exist_ok=False)
if not args.resume_prove: shutil.copytree(root/"implementation",lane/"implementation")
if not args.resume_prove: shutil.copy2(root/"foundry.toml",lane/"foundry.toml")
env=os.environ | {"FOUNDRY_PROFILE":"kontrol"}
kontrol=shutil.which("kontrol")
if kontrol is None: raise RuntimeError("kontrol is unavailable")
report={"schema":"trust-deferred-symbolic-feasibility-v1","status":"RUNNING",
        "inputDomain":"first > 0; second > 0; second <= first; uint256",
        "strategy":"concrete constructor before two fresh symbolic values",
        "runtimeLinkDischarged":False,"runs":[]}
(lane/"process.json").write_text(json.dumps({"pid":os.getpid(),"started":time.time()}))
commands=[
 ("build",[kontrol,"build","--foundry-project-root",str(lane),"--regen","--rekompile"],600),
 ("prove",[kontrol,"prove","--foundry-project-root",str(lane),
  "--match-test","TrustTokenDeferredSymbolicKontrolTest.testKontrol_DeferredSymbolicNonincreasingFreeze()",
  "--workers","1","--max-depth","10000","--max-iterations","1000",
  "--smt-timeout","10000","--schedule","CANCUN","--use-booster","--reinit"],900)]
if args.resume_prove: commands = [("prove-repair",commands[1][1],commands[1][2])]
if args.build_only: commands = commands[:1]
if args.resume_prove:
    import hashlib
    for source in (root/"implementation").rglob("*"):
        if source.is_file():
            twin=lane/source.relative_to(root)
            if source.read_bytes()!=twin.read_bytes():
                raise RuntimeError("resume source drift")
    if (root/"foundry.toml").read_bytes()!=(lane/"foundry.toml").read_bytes():
        raise RuntimeError("resume config drift")
    if (lane/"result.json").exists():
        shutil.copy2(lane/"result.json",lane/("result-before-"+str(time.time_ns())+".json"))
for name,cmd,budget in commands:
    if (lane/(name+".log")).exists():
        name += "-" + str(time.time_ns())
    started=time.monotonic()
    # Linux timeout terminates the whole process group including its solver children.
    with (lane/(name+".log")).open("w") as log:
        proc=subprocess.run(["timeout","--signal=TERM","--kill-after=10s",str(budget)+"s"]+cmd,
            cwd=lane,env=env,stdout=log,stderr=subprocess.STDOUT)
    report["runs"].append({"name":name,"exit":proc.returncode,
        "elapsedSeconds":round(time.monotonic()-started,3)})
    report["status"]="TIMEOUT" if proc.returncode in (124,137) else "CHECK_REQUIRED" if proc.returncode==0 else "FAIL"
    (lane/"result.json").write_text(json.dumps(report,indent=2)+"\n")
    print(json.dumps(report),flush=True)
    if proc.returncode!=0:
        break
(lane/"process.json").write_text(json.dumps({"pid":os.getpid(),"finished":time.time(),"running":False}))
sys.exit(0 if report["status"]=="CHECK_REQUIRED" else 1)
