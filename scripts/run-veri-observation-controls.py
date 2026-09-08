#!/usr/bin/env python3
"""Compile narrowly scoped observation controls against the pinned Veri consumer."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

ap=argparse.ArgumentParser()
ap.add_argument("--veri-root",type=Path,required=True)
ap.add_argument("--output",type=Path,required=True)
args=ap.parse_args()
root=Path(__file__).resolve().parents[1]
args.output.mkdir(parents=True,exist_ok=False)
controls=[
 ("receipt-state","implementation/src/TrustToken.sol",
  [("assessmentEvidence: record.evidenceHash,\n                preState: preState,","assessmentEvidence: record.evidenceHash,\n                preState: bytes32(uint256(1)),")],"receipt state observation mismatch"),
 ("assessment-binding","implementation/src/TrustDependencyBinding.sol",
  [("(commandHash, operation, subject, destination, amount, binding.bindingHash, binding.epoch)",
    "(commandHash, operation, subject, destination, amount, bytes32(0), binding.epoch)"),
   ("bindingEcho != binding.bindingHash","bindingEcho != bytes32(0)")],
   "assessment binding hash or epoch")]
results=[]
for name,filename,changes,expected in controls:
    lane=args.output/name
    shutil.copytree(root/"implementation/src",lane/"implementation/src")
    (lane/"implementation/test/mocks").mkdir(parents=True)
    shutil.copy2(root/"implementation/test/mocks/MockBoundDependency.sol",lane/"implementation/test/mocks")
    shutil.copy2(root/"foundry.toml",lane/"foundry.toml")
    source=lane/filename
    text=source.read_text()
    for old,new in changes:
        if text.count(old)!=1: raise RuntimeError("mutation anchor is not unique")
        text=text.replace(old,new)
    source.write_text(text)
    with (lane/"build.log").open("w") as log:
        build=subprocess.run(["forge","build","--offline"],cwd=lane,stdout=log,stderr=subprocess.STDOUT)
    if build.returncode!=0: raise RuntimeError("compile failure is not detection")
    with (lane/"run.log").open("w") as log:
        run=subprocess.run([sys.executable,str(root/"scripts/run-veri-native.py"),
             "--veri-root",str(args.veri_root.resolve()),"--artifact-root",str((lane/"out").resolve()),
             "--source-root",str(lane.resolve()),"--output",str((lane/"run").resolve())],
             stdout=log,stderr=subprocess.STDOUT)
    report=json.loads((lane/"run/result.json").read_text())
    detected=run.returncode==1 and report.get("error")=="CheckFailure: "+expected
    results.append({"mutation":name,"status":"DETECTED" if detected else "FAIL",
                    "compileExit":build.returncode,"exit":run.returncode,"error":report.get("error"),
                    "sourceBindingChecked":bool(report.get("boundSources")),
                    "transactions":len(report.get("observations",[]))})
    print(json.dumps(results[-1]),flush=True)
summary={"schema":"trust-veri-observation-controls-v1",
         "status":"PASS" if all(x["status"]=="DETECTED" for x in results) else "FAIL",
         "results":results,"runtimeLinkDischarged":False}
(args.output/"result.json").write_text(json.dumps(summary,indent=2)+"\n")
sys.exit(0 if summary["status"]=="PASS" else 1)
