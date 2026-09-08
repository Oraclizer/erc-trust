#!/usr/bin/env python3
"""Compile isolated source mutants and require semantic observation failures."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--veri-root",type=Path,required=True)
    ap.add_argument("--output",type=Path,required=True)
    args = ap.parse_args()
    root = Path(__file__).resolve().parents[1]
    output = args.output.resolve()
    output.mkdir(parents=True,exist_ok=False)
    original = (root/"implementation/src/TrustToken.sol").read_text()
    mutants = {
      "direction":("if (request.amount <= _frozen[request.subject]) {",
                   "if (false) {","nonincreasing target accepted"),
      "receipt-event":("emit RegulatoryActionApplied(request.actionId, uint8(request.action), request.caseId, receiptHash);",
                       "","FREEZE event count"),
      "balance":("_frozen[request.subject] = request.amount;",
                 "_frozen[request.subject] = request.amount; if (request.amount == 60) { _balances[request.subject] -= 1; }",
                 "FREEZE changed balance or supply"),
      "receipt-source":("source: request.source,\n                destination: request.destination,\n                amount: request.amount,",
                        "source: address(0),\n                destination: request.destination,\n                amount: request.amount,",
                        "receipt field source mismatch"),

      "storage-write":("_frozen[request.subject] = request.amount;",
                       "_custodyBacking[request.subject] = request.amount;","stored frozen target mismatch")
    }
    results = []
    started = time.monotonic()
    for name,(old,new,expected) in mutants.items():
        if original.count(old) != 1:
            raise RuntimeError("mutation anchor mismatch: "+name)
        lane = output/name
        shutil.copytree(root/"implementation/src",lane/"implementation/src")
        mock = lane/"implementation/test/mocks"
        mock.mkdir(parents=True)
        shutil.copy2(root/"implementation/test/mocks/MockBoundDependency.sol",mock)
        shutil.copy2(root/"foundry.toml",lane/"foundry.toml")
        source = lane/"implementation/src/TrustToken.sol"
        source.write_text(original.replace(old,new),encoding="utf-8")
        with (lane/"build.log").open("w") as log:
            build = subprocess.run(["forge","build","--offline"],cwd=lane,stdout=log,stderr=subprocess.STDOUT)
        if build.returncode != 0:
            raise RuntimeError("mutation compile failure (not detection): "+name)
        command = [sys.executable,str(root/"scripts/run-veri-native.py"),
                   "--veri-root",str(args.veri_root.resolve()),
                   "--artifact-root",str(lane/"out"),"--source-root",str(lane),"--output",str(lane/"run")]
        with (lane/"run.log").open("w") as log:
            run = subprocess.run(command,stdout=log,stderr=subprocess.STDOUT)
        report = json.loads((lane/"run/result.json").read_text())
        detected = run.returncode == 1 and report.get("error") == "CheckFailure: "+expected
        results.append({"mutation":name,"status":"DETECTED" if detected else "FAIL",
                        "compileExit":build.returncode,"detectorExit":run.returncode,
                        "error":report.get("error"),"mutantSourceSha256":hashlib.sha256(source.read_bytes()).hexdigest()})
        print(json.dumps(results[-1]),flush=True)
        if not detected:
            break
    lane = output/"storage-decoder"
    with (output/"decoder.log").open("w") as log:
        run = subprocess.run([sys.executable,str(root/"scripts/run-veri-native.py"),
            "--veri-root",str(args.veri_root.resolve()),"--output",str(lane),
            "--decoder-mutation"],stdout=log,stderr=subprocess.STDOUT)
    report = json.loads((lane/"result.json").read_text())
    detected = run.returncode == 1 and report.get("error") == "CheckFailure: stored frozen target mismatch"
    results.append({"mutation":"storage-decoder","status":"DETECTED" if detected else "FAIL",
                    "detectorExit":run.returncode,"error":report.get("error")})
    result = {"schema":"oraclizer-veri-native-mutations-v1",
              "status":"PASS" if len(results)==6 and all(r["status"]=="DETECTED" for r in results) else "FAIL",
              "runtimeLinkDischarged":False,"results":results,
              "elapsedSeconds":round(time.monotonic()-started,3)}
    (output/"result.json").write_text(json.dumps(result,indent=2)+"\n")
    print(json.dumps(result))
    return 0 if result["status"]=="PASS" else 1

if __name__=="__main__":
    sys.exit(main())
