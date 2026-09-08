"""Load exactly the library source pinned by the TRUST consumer."""
import hashlib
import json
from pathlib import Path
import re
import sys

def load_veri(directory):
    root=Path(__file__).resolve().parents[1]
    pin=json.loads((root/"evidence/trust12/veri-dependency.json").read_text())
    if pin.get("schema")!="trust-veri-dependency-v1" or not re.fullmatch(r"[0-9a-f]{40}",pin.get("revision","")):
        raise ValueError("invalid Veri revision pin")
    directory=directory.resolve()
    expected={entry["path"]:entry["sha256"] for entry in pin["files"]}
    actual={p.relative_to(directory).as_posix():hashlib.sha256(p.read_bytes()).hexdigest()
            for p in (directory/"veri").rglob("*.py")}
    if not expected or actual!=expected:
        raise ValueError("Veri library differs from the immutable source pin")
    sys.path.insert(0,str(directory))
    return {"revision":pin["revision"],"tree":pin["tree"],"files":pin["files"]}

def driver_identity(path):
    return {"path":"scripts/"+Path(path).name,
            "sha256":hashlib.sha256(Path(path).read_bytes()).hexdigest()}
