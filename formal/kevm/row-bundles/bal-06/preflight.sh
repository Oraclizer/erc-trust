#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 POSITIVE_DEFINITION NEW_OUTPUT_DIRECTORY REPORT_PATH" >&2
  exit 64
fi

positive_definition=$1
output_directory=$2
report_path=$3
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repository_root=$(cd -- "$script_dir/../../../.." && pwd -P)
claim_source="$script_dir/positive/claim.k"
lock_path="$repository_root/formal/kevm/dependencies.lock.json"
k_root=/nix/store/y63xkr8pk2bqd5lh4889rlwldw26v9f4-k-7.1.337-4a46d1231473b599c699160132fd6e76a5c46406
kevm_python_root=/nix/store/cj49dhi36y3vzjfs8bjz5g9m7rk20p53-kevm-pyk-env/lib/python3.10/site-packages/kevm_pyk
evm_include=$kevm_python_root/kproj/evm-semantics
plugin_include=$kevm_python_root/kproj/plugin

[[ ! -e $output_directory ]] || { echo "preflight output must be new: $output_directory" >&2; exit 64; }
[[ -f $positive_definition/definition.kore && -f $positive_definition/compiled.json ]] || {
  echo "incomplete positive definition" >&2
  exit 66
}
for path in "$claim_source" "$lock_path" "$k_root/bin/kprove" "$evm_include" "$plugin_include"; do
  [[ -e $path ]] || { echo "missing pinned preflight input: $path" >&2; exit 66; }
done
command -v timeout >/dev/null || { echo "GNU timeout is not on PATH" >&2; exit 69; }
command -v python3 >/dev/null || { echo "python3 is not on PATH" >&2; exit 69; }

definition_sha=$(sha256sum "$positive_definition/definition.kore" | awk '{print $1}')
compiled_sha=$(sha256sum "$positive_definition/compiled.json" | awk '{print $1}')
[[ $definition_sha == bac21e3e90990c4c060bf77ecfe161a70d18900c631dcea5a37343765e6b3e33 ]] || {
  echo "positive definition.kore identity mismatch" >&2
  exit 65
}
[[ $compiled_sha == 5ba6257f64024f7eff4ec99c569db9f9477fd5d2a625f44ed04e091fdf795a50 ]] || {
  echo "positive compiled.json identity mismatch" >&2
  exit 65
}
[[ $(head -n 1 "$claim_source") == 'requires "../../../trust-runtime-verification.k"' ]] || {
  echo "common-runner requires prelude drift" >&2
  exit 65
}
grep -Fq '29 |-> 0' "$claim_source" || { echo "literal slot 29 frame missing" >&2; exit 65; }
if grep -Fq '.IntList' "$claim_source"; then
  echo "ambiguous scalar slot helper remains" >&2
  exit 65
fi

mkdir -p "$output_directory/temp" "$(dirname -- "$report_path")"
claim_path="$output_directory/executed-claim.k"
tail -n +2 "$claim_source" >"$claim_path"
parsed_path="$output_directory/claim.parsed.json"
log_path="$output_directory/kprove-dry-run.log"
if timeout --signal=TERM --kill-after=30s 600 \
  "$k_root/bin/kprove" "$claim_path" \
    --definition "$positive_definition" \
    --spec-module TRUST-BAL-06-ORDINARY-TRANSFER-PRESERVES-FLOOR-SPEC \
    --md-selector k \
    -I "$evm_include" \
    -I "$plugin_include" \
    --output json \
    --temp-dir "$output_directory/temp" \
    --dry-run \
    --emit-json-spec "$parsed_path" \
    --allow-rules >"$log_path" 2>&1; then
  parse_exit=0
else
  parse_exit=$?
fi
if [[ $parse_exit -eq 124 || $parse_exit -eq 137 ]]; then
  echo "kprove dry-run timed out; preflight incomplete" >&2
  exit 124
fi
[[ $parse_exit -eq 0 ]] || { echo "kprove dry-run failed with exit $parse_exit" >&2; exit "$parse_exit"; }
[[ -s $parsed_path ]] || { echo "kprove dry-run emitted no parsed claim" >&2; exit 65; }

python3 - \
  "$claim_source" "$claim_path" "$parsed_path" "$report_path" "$definition_sha" "$compiled_sha" <<'PY'
import datetime
import hashlib
import json
import sys
from pathlib import Path

claim_source, claim_path, parsed_path, report_path = map(Path, sys.argv[1:5])
definition_sha, compiled_sha = sys.argv[5:7]
parsed = json.loads(parsed_path.read_text(encoding="utf-8"))
expected_module = "TRUST-BAL-06-ORDINARY-TRANSFER-PRESERVES-FLOOR-SPEC"
term = parsed.get("term", {})
if (
    parsed.get("format") != "KAST"
    or parsed.get("version") != 4
    or term.get("node") != "KFlatModuleList"
    or term.get("mainModule") != expected_module
):
    raise SystemExit("parsed module identity mismatch")
modules = [value for value in term.get("term", []) if value.get("node") == "KFlatModule"]
main_modules = [value for value in modules if value.get("name") == expected_module]
if len(main_modules) != 1:
    raise SystemExit("parsed main module cardinality mismatch")
claims = [
    value
    for value in main_modules[0].get("localSentences", [])
    if value.get("node") == "KClaim"
]
if len(claims) != 1:
    raise SystemExit("parsed claim cardinality mismatch")

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

claim_text = claim_path.read_text(encoding="utf-8")
if claim_text.count("29 |-> 0") != 2 or ".IntList" in claim_text:
    raise SystemExit("literal scalar slot 29 source gate failed")
report = {
    "schemaVersion": 1,
    "obligationId": "BAL-06",
    "status": "PASS",
    "createdAtUtc": datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "module": expected_module,
    "claimSourceSha256": sha(claim_source),
    "executedClaimSha256": sha(claim_path),
    "parsedClaimSha256": sha(parsed_path),
    "parsedClaimBytes": parsed_path.stat().st_size,
    "definitionKoreSha256": definition_sha,
    "compiledJsonSha256": compiled_sha,
    "scalarSlot29": {"storageKey": 29, "prePostOccurrences": 2, "ambiguousIntListHelper": False},
    "backendStarted": False,
    "claimBoundary": "Parse, type, macro, and exact-definition identity preflight only. No proof result is claimed.",
}
report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(json.dumps(report, indent=2, sort_keys=True))
PY
