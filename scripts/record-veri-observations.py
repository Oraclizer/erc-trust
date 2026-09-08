#!/usr/bin/env python3
"""Record supplemental Veri observations without changing refinement completion."""
import hashlib
import json
from pathlib import Path
root=Path(__file__).resolve().parents[1]
def read(relative): return json.loads((root/relative).read_text())
def ref(relative):
    return {"path":relative,"sha256":hashlib.sha256((root/relative).read_bytes()).hexdigest()}
native_path="out/trust12/veri-native-pinned-final/result.json"
profiles_path="out/trust12/veri-profiles-final-records/result.json"
native,profiles=read(native_path),read(profiles_path)
if native["status"]!="PASS" or profiles["status"]!="PASS": raise RuntimeError("positive observations incomplete")
for report in (native,profiles):
    if report["runtimeLinkDischarged"] is not False: raise RuntimeError("runtime overclaim")
    if ref(report["driver"]["path"])["sha256"]!=report["driver"]["sha256"]: raise RuntimeError("driver changed")
    if report["tool"]!= {k:read("evidence/trust12/veri-dependency.json")[k] for k in ("revision","tree","files")}:
        raise RuntimeError("tool binding changed")
controls=read("out/trust12/veri-audit-final/result.json")
extra=read("out/trust12/veri-observation-controls-02/result.json")
if controls["status"]!="PASS" or extra["status"]!="PASS": raise RuntimeError("controls incomplete")
report={
 "schema":"trust-veri-observations-v1","status":"PASS_BOUNDED_OBSERVATIONS",
 "runtimeLinkDischarged":False,
 "tool":native["tool"],
 "native":{"cases":native["cases"],"driver":native["driver"],
           "transactions":len(native["observations"]),"stateAndViewReads":len(native["stateAndViewReads"]),
           "boundSources":native["boundSources"],"raw":ref(native_path)},
 "profiles":{"results":profiles["profiles"],"driver":profiles["driver"],
             "transactions":len(profiles["observations"]),"stateAndViewReads":len(profiles["stateAndViewReads"]),
             "hookRouteControls":profiles["hookRouteControls"],"raw":ref(profiles_path)},
 "controls":{"results":controls["results"]+extra["results"],
             "raw":[ref("out/trust12/veri-audit-final/result.json"),ref("out/trust12/veri-observation-controls-02/result.json")]},
 "pinControl":read("out/trust12/veri-dependency-controls.json"),
 "assumptions":["Anvil and trace correctness","compiler metadata is trusted provenance, not arbitrary-artifact authentication",
                "Keccak implementation","specified constructor/dependency inputs","project observation footprint"],
 "nonclaim":"No general EVM-to-Isabelle derivation, exhaustive input proof, production certification, or publication approval."
}
(root/"evidence/trust12/veri-observation-results.json").write_text(json.dumps(report,indent=2)+"\n")
print(json.dumps({"status":report["status"],"nativeCases":len(native["cases"]),
                  "hookRouteControls":len(profiles["hookRouteControls"]),"controls":len(report["controls"]["results"])}))
