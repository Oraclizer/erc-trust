#!/usr/bin/env python3
"""Replay already compiled semantic mutants after a detector repair."""
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
    ap.add_argument("--mutations",type=Path,required=True)
    ap.add_argument("--audit-mutations",type=Path,required=True)
    args=ap.parse_args()
    root=Path(__file__).resolve().parents[1]
    args.output.mkdir(parents=True,exist_ok=False)
    cases=[("direction",args.mutations/"direction","nonincreasing target accepted"),
           ("receipt-event",args.mutations/"receipt-event","FREEZE event count"),
           ("storage-write",args.mutations/"storage-write","stored frozen target mismatch"),
           ("balance",args.audit_mutations/"balance","FREEZE changed balance or supply"),
           ("receipt-source",args.audit_mutations/"receipt-source","receipt field source mismatch")]
    results=[]
    for name,lane,expected in cases:
        output=args.output/name
        command=[sys.executable,str(root/"scripts/run-veri-native.py"),"--veri-root",str(args.veri_root.resolve()),
                 "--artifact-root",str((lane/"out").resolve()),"--source-root",str(lane.resolve()),
                 "--output",str(output.resolve())]
        run=subprocess.run(command,capture_output=True,text=True)
        (args.output/(name+".log")).write_text(run.stdout+run.stderr)
        report=json.loads((output/"result.json").read_text())
        detected=run.returncode==1 and report.get("error")=="CheckFailure: "+expected
        results.append({"mutation":name,"status":"DETECTED" if detected else "FAIL",
                        "exit":run.returncode,"error":report.get("error"),
                        "sourceBindingChecked":bool(report.get("boundSources")),
                        "actualTransactions":len(report.get("observations",[]))})
        print(json.dumps(results[-1]),flush=True)
    # Keep ordinary production sources fixed, but pair them with the balance-mutant artifact.
    output=args.output/"stale-artifact"
    run=subprocess.run([sys.executable,str(root/"scripts/run-veri-native.py"),"--veri-root",str(args.veri_root.resolve()),
        "--artifact-root",str((args.audit_mutations/"balance/out").resolve()),"--source-root",str(root),
        "--output",str(output.resolve())],capture_output=True,text=True)
    report=json.loads((output/"result.json").read_text())
    results.append({"mutation":"stale-artifact","status":"DETECTED" if run.returncode==1 and
        "source/artifact mismatch" in report.get("error","") else "FAIL",
        "exit":run.returncode,"error":report.get("error")})
    output=args.output/"storage-decoder"
    run=subprocess.run([sys.executable,str(root/"scripts/run-veri-native.py"),"--veri-root",str(args.veri_root.resolve()),
        "--output",str(output.resolve()),"--decoder-mutation"],capture_output=True,text=True)
    report=json.loads((output/"result.json").read_text())
    results.append({"mutation":"storage-decoder","status":"DETECTED" if run.returncode==1 and
        report.get("error")=="CheckFailure: stored frozen target mismatch" else "FAIL",
        "exit":run.returncode,"error":report.get("error")})
    summary={"schema":"oraclizer-veri-repaired-mutations-v1",
        "status":"PASS" if all(r["status"]=="DETECTED" for r in results) else "FAIL",
        "results":results,"runtimeLinkDischarged":False}
    (args.output/"result.json").write_text(json.dumps(summary,indent=2)+"\n")
    print(json.dumps(summary))
    return 0 if summary["status"]=="PASS" else 1
if __name__=="__main__": sys.exit(main())
