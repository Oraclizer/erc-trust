#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: run-abi-calldata-claims.sh --definition DIR [options]

Required:
  --definition DIR        Exact pinned canonical KEVM definition

Options:
  --kore-rpc-command PATH Override the pinned Kore RPC executable
  --output-directory DIR  Preserve replay saves and logs in DIR
  --report PATH           Write the sanitized campaign report to PATH
  --no-use-booster        Required authoritative-backend boundary
EOF
  exit 64
}

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repository_root=$(cd -- "$script_dir/../.." && pwd -P)
lock_path="$repository_root/formal/kevm/dependencies.lock.json"
fail05_evidence_path="$repository_root/evidence/end-to-end-refinement/kevm/fail-05-generic-dispatcher-revert-20260802T174934Z/evidence.json"
short_spec_path="$repository_root/formal/kevm/specs/full-transaction-action-short-calldata-revert-spec.k"
trailing_spec_path="$repository_root/formal/kevm/specs/full-transaction-action-trailing-calldata-revert-spec.k"
report_path="$repository_root/evidence/end-to-end-refinement/kevm/abi-calldata-initial-campaign.json"
definition=${ERC_TRUST_ABI_DEFINITION:-}
kore_rpc_command=${ERC_TRUST_KORE_RPC_COMMAND:-}
output_directory=${ERC_TRUST_ABI_REPLAY_OUTPUT:-}
no_use_booster=false

while (($#)); do
  case "$1" in
    --definition)
      (($# >= 2)) || usage
      definition=$2
      shift 2
      ;;
    --kore-rpc-command)
      (($# >= 2)) || usage
      kore_rpc_command=$2
      shift 2
      ;;
    --output-directory)
      (($# >= 2)) || usage
      output_directory=$2
      shift 2
      ;;
    --report)
      (($# >= 2)) || usage
      report_path=$2
      shift 2
      ;;
    --no-use-booster)
      no_use_booster=true
      shift
      ;;
    *) usage ;;
  esac
done

[[ -n $definition ]] || usage
[[ $no_use_booster == true ]] || { echo "authoritative replay requires --no-use-booster" >&2; exit 64; }
for required_file in "$lock_path" "$fail05_evidence_path" "$short_spec_path" "$trailing_spec_path"; do
  [[ -f $required_file ]] || { echo "missing required file: $required_file" >&2; exit 66; }
done
[[ -f $definition/definition.kore && -f $definition/compiled.json ]] || {
  echo "incomplete KEVM definition: $definition" >&2
  exit 66
}
command -v kevm >/dev/null || { echo "kevm is not on PATH" >&2; exit 69; }
command -v python3 >/dev/null || { echo "python3 is not on PATH" >&2; exit 69; }

if [[ -z $kore_rpc_command ]]; then
  kore_rpc_command=$(python3 - "$lock_path" <<'PY'
import json
import sys
from pathlib import Path
lock = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(lock["components"]["kore"]["rpcStorePath"] + "/bin/kore-rpc")
PY
  )
fi
[[ -x $kore_rpc_command ]] || { echo "Kore RPC is not executable: $kore_rpc_command" >&2; exit 66; }

mapfile -t expected_definition_hashes < <(python3 - "$fail05_evidence_path" <<'PY'
import json
import sys
from pathlib import Path
evidence = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(evidence["positive"]["definitionKoreSha256"])
print(evidence["positive"]["compiledJsonSha256"])
PY
)
sha256_file() { sha256sum "$1" | awk '{print $1}'; }
for pair in \
  "$definition/definition.kore:${expected_definition_hashes[0]}" \
  "$definition/compiled.json:${expected_definition_hashes[1]}"; do
  path=${pair%%:*}
  expected_hash=${pair##*:}
  actual_hash=$(sha256_file "$path")
  [[ $actual_hash == "$expected_hash" ]] || {
    echo "SHA-256 mismatch: $path: $actual_hash != $expected_hash" >&2
    exit 65
  }
done

python3 - "$short_spec_path" "$trailing_spec_path" <<'PY'
import re
import sys
from pathlib import Path

expected = ((Path(sys.argv[1]), 4), (Path(sys.argv[2]), 708))
for path, byte_length in expected:
    text = path.read_text(encoding="utf-8")
    matches = re.findall(r'#parseByteStack\("(0x[0-9a-f]+)"\)', text)
    if len(matches) != 1:
        raise SystemExit(f"expected one concrete calldata literal: {path}")
    calldata = matches[0]
    if calldata[:10] != "0x9da23539" or (len(calldata) - 2) // 2 != byte_length:
        raise SystemExit(f"calldata boundary mismatch: {path}")
    if "\n    requires " in text:
        raise SystemExit(f"claim prelude must import the exact compiled module directly: {path}")
    if text.count("<storage> TOKEN_STORAGE:Map </storage>") != 1 or text.count("<origStorage> TOKEN_STORAGE </origStorage>") != 1:
        raise SystemExit(f"symbolic TrustToken storage boundary mismatch: {path}")
    if text.count("<storage> .Map </storage>") != 2 or text.count("<origStorage> .Map </origStorage>") != 2:
        raise SystemExit(f"zero-account or sender storage boundary mismatch: {path}")
if not expected[1][0].read_text(encoding="utf-8").split('0x9da23539', 1)[1].startswith("00"):
    raise SystemExit("trailing case tuple head mismatch")
PY

if [[ -z $output_directory ]]; then
  output_directory=$(mktemp -d "${TMPDIR:-/tmp}/erc-trust-abi-calldata.XXXXXX")
else
  mkdir -p "$output_directory"
  output_directory=$(cd -- "$output_directory" && pwd -P)
fi
source_root="$output_directory/specs"
mkdir -p "$source_root" "$output_directory/short-save" "$output_directory/trailing-save" "$(dirname -- "$report_path")"
python3 - "$short_spec_path" "$source_root/short.k" "$trailing_spec_path" "$source_root/trailing.k" <<'PY'
import sys
from pathlib import Path

for source_name, output_name in ((sys.argv[1], sys.argv[2]), (sys.argv[3], sys.argv[4])):
    source = Path(source_name).read_text(encoding="utf-8")
    lines = source.splitlines(keepends=True)
    if not lines:
        raise SystemExit(f"empty claim source: {source_name}")
    if lines[0].startswith("requires "):
        lines = lines[1:]
    Path(output_name).write_text("".join(lines), encoding="utf-8", newline="\n")
PY

run_claim() {
  local label=$1
  local source=$2
  local module=$3
  local save_directory="$output_directory/$label-save"
  local log="$output_directory/$label.log"
  local started
  started=$(date +%s)
  kevm prove "$source" \
    --definition "$definition" \
    --spec-module "$module" \
    --save-directory "$save_directory" \
    --temp-directory "$output_directory/$label-temp" \
    --kore-rpc-command "$kore_rpc_command" \
    --no-use-booster \
    --workers 1 \
    --force-sequential >"$log" 2>&1
  printf '%s' "$(( $(date +%s) - started ))"
}

short_elapsed=$(run_claim short "$source_root/short.k" TRUST-FULL-TRANSACTION-ACTION-SHORT-CALLDATA-REVERT-SPEC)
trailing_elapsed=$(run_claim trailing "$source_root/trailing.k" TRUST-FULL-TRANSACTION-ACTION-TRAILING-CALLDATA-REVERT-SPEC)

python3 - \
  "$repository_root" "$definition" "$short_spec_path" "$trailing_spec_path" \
  "$output_directory/short-save" "$output_directory/trailing-save" \
  "$output_directory/short.log" "$output_directory/trailing.log" \
  "$short_elapsed" "$trailing_elapsed" "$report_path" <<'PY'
import datetime
import hashlib
import json
import re
import sys
from pathlib import Path

(
    repository_root, definition, short_spec, trailing_spec, short_save, trailing_save,
    short_log, trailing_log, short_elapsed, trailing_elapsed, report_path,
) = sys.argv[1:]
repository_root = Path(repository_root)
definition = Path(definition)
short_spec = Path(short_spec)
trailing_spec = Path(trailing_spec)
short_save = Path(short_save)
trailing_save = Path(trailing_save)
short_log = Path(short_log)
trailing_log = Path(trailing_log)
report_path = Path(report_path)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def repo(path):
    return path.resolve().relative_to(repository_root.resolve()).as_posix()

def inspect(label, save, log, elapsed, expected_bytes):
    proof_paths = list(save.glob("*/proof.json"))
    if len(proof_paths) != 1:
        raise SystemExit(f"{label}: expected one proof artifact")
    proof_path = proof_paths[0]
    claim_id = proof_path.parent.name
    kcfg_path = proof_path.parent / "kcfg" / "kcfg.json"
    proof = json.loads(proof_path.read_text(encoding="utf-8"))
    kcfg = json.loads(kcfg_path.read_text(encoding="utf-8"))
    log_text = log.read_text(encoding="utf-8", errors="replace")
    if (
        proof.get("id") != claim_id
        or proof.get("admitted") is not False
        or kcfg.get("stuck")
        or kcfg.get("vacuous")
        or f"PROOF PASSED: {claim_id}" not in log_text
    ):
        raise SystemExit(f"{label}: proof graph or log mismatch")
    return {
        "result": "PASS",
        "claimId": claim_id,
        "elapsedWallSeconds": int(elapsed),
        "calldataBytes": expected_bytes,
        "proofSha256": sha(proof_path),
        "kcfgSha256": sha(kcfg_path),
        "nodes": len(kcfg.get("nodes", [])),
        "edges": len(kcfg.get("edges", [])),
        "covers": len(kcfg.get("covers", [])),
        "admitted": False,
    }

runner_path = repository_root / "formal" / "kevm" / "run-abi-calldata-claims.sh"
report = {
    "schemaVersion": 1,
    "status": "PASS",
    "classification": "INITIAL_CAMPAIGN_EVIDENCE",
    "createdAtUtc": datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "targetObligationIds": ["ABI-03", "ABI-04"],
    "runner": {"path": repo(runner_path), "sha256": sha(runner_path)},
    "definition": {
        "definitionKoreSha256": sha(definition / "definition.kore"),
        "compiledJsonSha256": sha(definition / "compiled.json"),
        "schedule": "CANCUN",
        "boosterEnabled": False,
    },
    "cases": {
        "ABI-03-action-trailing-word": {
            "spec": {"path": repo(trailing_spec), "sha256": sha(trailing_spec)},
            **inspect("trailing", trailing_save, trailing_log, trailing_elapsed, 708),
        },
        "ABI-04-action-selector-only": {
            "spec": {"path": repo(short_spec), "sha256": sha(short_spec)},
            **inspect("short", short_save, short_log, short_elapsed, 4),
        },
    },
    "selector": "0x9da23539",
    "canonicalActionCalldataBytes": 676,
    "initialStateAssumptions": [
        "The zero account and transaction sender begin with empty storage; TrustToken storage is an arbitrary symbolic map equal to original storage.",
        "The claim covers one concrete valid native-action selector and the exact CANCUN transaction envelope encoded in the spec.",
    ],
    "residualGates": [
        "ABI-03 still needs endpoint coverage, checked bridge linkage, negative adequacy, and a backend-complete replay of the trailing-word claim.",
        "ABI-04 still needs the remaining short-head, offset, length, and high-bit cases, checked bridge linkage, and negative adequacy.",
        "Both obligations still need named Isabelle closure and independent replay indexing before discharge.",
    ],
}
report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(json.dumps({
    "status": "PASS",
    "report": repo(report_path),
    "reportSha256": sha(report_path),
    "shortClaimId": report["cases"]["ABI-04-action-selector-only"]["claimId"],
    "trailingClaimId": report["cases"]["ABI-03-action-trailing-word"]["claimId"],
    "shortElapsedSeconds": int(short_elapsed),
    "trailingElapsedSeconds": int(trailing_elapsed),
}, indent=2))
PY
