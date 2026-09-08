#!/usr/bin/env python3
"""Test immutable Veri consumption without starting an EVM."""
import argparse
import json
from pathlib import Path
import shutil
import tempfile
from veri_dependency import load_veri

ap=argparse.ArgumentParser()
ap.add_argument("--veri-root",type=Path,required=True)
ap.add_argument("--output",type=Path,required=True)
args=ap.parse_args()
pin=load_veri(args.veri_root)
with tempfile.TemporaryDirectory(prefix="veri-pin-control-",dir=args.output.parent) as directory:
    root=Path(directory)
    shutil.copytree(args.veri_root/"veri",root/"veri",ignore=shutil.ignore_patterns("__pycache__"))
    (root/"veri/abi.py").write_bytes((root/"veri/abi.py").read_bytes()+b"\n# changed input\n")
    try:
        load_veri(root)
    except ValueError as error:
        if str(error)!="Veri library differs from the immutable source pin": raise
        status="REJECTED"
    else:
        raise RuntimeError("modified library was accepted")
result={"schema":"trust-veri-dependency-controls-v1","positive":"PASS",
        "modifiedLibrary":status,"revision":pin["revision"],"evmStarted":False}
args.output.write_text(json.dumps(result,indent=2)+"\n")
print(json.dumps(result))
