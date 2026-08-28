#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: run-row-bundle.sh --positive-definition DIR --negative-definition DIR --output-directory DIR --report PATH --no-use-booster [--proof-timeout-seconds N]

The outer process timeout must exceed the internal proof timeout. The runner
uses GNU timeout for each proof so caller interruption cannot be mistaken for
a semantic result. Exit 124 is always an incomplete replay, never PASS.
EOF
  exit 64
}

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repository_root=$(cd -- "$script_dir/../../../.." && pwd -P)
positive_claim="$script_dir/positive/claim.k"
negative_claim="$script_dir/negative/claim.k"
mutation_path="$repository_root/evidence/end-to-end-refinement/row-bundles/bal-06/negative/mutation.json"
lock_path="$repository_root/formal/kevm/dependencies.lock.json"
positive_definition=
negative_definition=
output_directory=
report_path=
proof_timeout_seconds=7200
no_use_booster=false

while (($#)); do
  case "$1" in
    --positive-definition) (($# >= 2)) || usage; positive_definition=$2; shift 2 ;;
    --negative-definition) (($# >= 2)) || usage; negative_definition=$2; shift 2 ;;
    --output-directory) (($# >= 2)) || usage; output_directory=$2; shift 2 ;;
    --report) (($# >= 2)) || usage; report_path=$2; shift 2 ;;
    --proof-timeout-seconds) (($# >= 2)) || usage; proof_timeout_seconds=$2; shift 2 ;;
    --no-use-booster) no_use_booster=true; shift ;;
    *) usage ;;
  esac
done

[[ -n $positive_definition && -n $negative_definition && -n $output_directory && -n $report_path ]] || usage
[[ $no_use_booster == true ]] || { echo "authoritative replay requires --no-use-booster" >&2; exit 64; }
[[ $proof_timeout_seconds =~ ^[1-9][0-9]*$ ]] || { echo "invalid proof timeout" >&2; exit 64; }
command -v kevm >/dev/null || { echo "kevm is not on PATH" >&2; exit 69; }
command -v timeout >/dev/null || { echo "GNU timeout is not on PATH" >&2; exit 69; }
command -v python3 >/dev/null || { echo "python3 is not on PATH" >&2; exit 69; }
for path in "$positive_claim" "$negative_claim" "$mutation_path" "$lock_path"; do
  [[ -f $path ]] || { echo "missing required file: $path" >&2; exit 66; }
done
for definition in "$positive_definition" "$negative_definition"; do
  [[ -f $definition/definition.kore && -f $definition/compiled.json ]] || {
    echo "incomplete KEVM definition: $definition" >&2
    exit 66
  }
done
cmp -s "$positive_claim" "$negative_claim" || { echo "positive/negative claim source drift" >&2; exit 65; }
[[ $(head -n 1 "$positive_claim") == 'requires "../../../trust-runtime-verification.k"' ]] || {
  echo "common-runner requires prelude drift" >&2
  exit 65
}

positive_definition_sha=$(sha256sum "$positive_definition/definition.kore" | awk '{print $1}')
positive_compiled_sha=$(sha256sum "$positive_definition/compiled.json" | awk '{print $1}')
[[ $positive_definition_sha == bac21e3e90990c4c060bf77ecfe161a70d18900c631dcea5a37343765e6b3e33 ]] || {
  echo "positive definition identity mismatch" >&2
  exit 65
}
[[ $positive_compiled_sha == 5ba6257f64024f7eff4ec99c569db9f9477fd5d2a625f44ed04e091fdf795a50 ]] || {
  echo "positive compiled identity mismatch" >&2
  exit 65
}

kore_rpc_command=$(python3 - "$lock_path" <<'PY'
import json
import sys
from pathlib import Path
lock = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(lock["components"]["kore"]["rpcStorePath"] + "/bin/kore-rpc")
PY
)
[[ -x $kore_rpc_command ]] || { echo "pinned Kore RPC is not executable" >&2; exit 66; }

mkdir -p "$output_directory/positive-save" "$output_directory/positive-temp" \
  "$output_directory/negative-save" "$output_directory/negative-temp" "$(dirname -- "$report_path")"
positive_executed_claim="$output_directory/positive-claim.k"
negative_executed_claim="$output_directory/negative-claim.k"
tail -n +2 "$positive_claim" >"$positive_executed_claim"
tail -n +2 "$negative_claim" >"$negative_executed_claim"
cmp -s "$positive_executed_claim" "$negative_executed_claim" || {
  echo "executed positive/negative claim drift" >&2
  exit 65
}

run_proof() {
  local polarity=$1
  local claim_path=$2
  local definition=$3
  local log_path="$output_directory/$polarity.log"
  local exit_path="$output_directory/$polarity.exit-code"
  local proof_exit
  if timeout --signal=TERM --kill-after=30s "$proof_timeout_seconds" \
    kevm prove "$claim_path" \
      --definition "$definition" \
      --spec-module TRUST-BAL-06-ORDINARY-TRANSFER-PRESERVES-FLOOR-SPEC \
      --save-directory "$output_directory/$polarity-save" \
      --temp-directory "$output_directory/$polarity-temp" \
      --kore-rpc-command "$kore_rpc_command" \
      --no-use-booster \
      --workers 1 \
      --force-sequential >"$log_path" 2>&1; then
    proof_exit=0
  else
    proof_exit=$?
  fi
  printf '%s\n' "$proof_exit" >"$exit_path"
  if [[ $proof_exit -eq 124 || $proof_exit -eq 137 ]]; then
    echo "$polarity proof timed out; replay incomplete" >&2
    exit 124
  fi
  return "$proof_exit"
}

run_proof positive "$positive_executed_claim" "$positive_definition"
set +e
run_proof negative "$negative_executed_claim" "$negative_definition"
negative_exit=$?
set -e
[[ $negative_exit -eq 1 ]] || { echo "negative proof exit $negative_exit, expected semantic failure exit 1" >&2; exit 1; }

python3 - \
  "$repository_root" "$output_directory" "$report_path" "$positive_definition" "$negative_definition" \
  "$positive_claim" "$mutation_path" <<'PY'
import datetime
import hashlib
import json
import sys
from pathlib import Path

repository_root, output_directory, report_path, positive_definition, negative_definition, claim_path, mutation_path = map(Path, sys.argv[1:])
claim_id = None

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def find_proof(save_root):
    proofs = list(save_root.glob("*/proof.json"))
    if len(proofs) != 1:
        raise SystemExit(f"expected one proof in {save_root}, found {len(proofs)}")
    proof = json.loads(proofs[0].read_text(encoding="utf-8"))
    kcfg_path = proofs[0].parent / "kcfg" / "kcfg.json"
    if not kcfg_path.is_file():
        raise SystemExit(f"missing KCFG: {kcfg_path}")
    return proofs[0], proof, kcfg_path, json.loads(kcfg_path.read_text(encoding="utf-8"))

positive_proof_path, positive_proof, positive_kcfg_path, positive_kcfg = find_proof(output_directory / "positive-save")
negative_proof_path, negative_proof, negative_kcfg_path, negative_kcfg = find_proof(output_directory / "negative-save")
claim_id = positive_proof.get("id")
if not claim_id or negative_proof.get("id") != claim_id:
    raise SystemExit("positive/negative claim identity mismatch")
positive_log = (output_directory / "positive.log").read_text(encoding="utf-8", errors="replace")
negative_log = (output_directory / "negative.log").read_text(encoding="utf-8", errors="replace")
if (
    positive_proof.get("admitted") is not False
    or positive_kcfg.get("stuck")
    or positive_kcfg.get("vacuous")
    or f"PROOF PASSED: {claim_id}" not in positive_log
):
    raise SystemExit("positive proof graph is not a theorem-grade PASS")
if (
    f"PROOF FAILED: {claim_id}" not in negative_log
    or "Runtime error" in negative_log
    or "Proof crashed" in negative_log
    or "Cancelled" in negative_log
    or "Timeout" in negative_log
):
    raise SystemExit("negative run is not a semantic counterexample")
terminal = [int(node) for node in negative_proof.get("terminal", [])]
if len(terminal) != 1 or terminal[0] not in negative_kcfg.get("nodes", []):
    raise SystemExit("negative terminal witness is not unique")
failure_node_path = negative_proof_path.parent / "kcfg" / "nodes" / f"{terminal[0]}.json"
failure_text = failure_node_path.read_text(encoding="utf-8", errors="replace")
if not all(token in failure_text for token in ("BACKING", "29")):
    raise SystemExit("negative terminal witness does not expose backing/idle frame")

mutation = json.loads(mutation_path.read_text(encoding="utf-8"))
report = {
    "schemaVersion": 1,
    "obligationId": "BAL-06",
    "status": "PASS",
    "createdAtUtc": datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "claimId": claim_id,
    "claimSha256": sha(claim_path),
    "positive": {
        "result": "PASS",
        "definitionKoreSha256": sha(positive_definition / "definition.kore"),
        "compiledJsonSha256": sha(positive_definition / "compiled.json"),
        "proofSha256": sha(positive_proof_path),
        "kcfgSha256": sha(positive_kcfg_path),
        "nodes": len(positive_kcfg.get("nodes", [])),
        "edges": len(positive_kcfg.get("edges", [])),
        "covers": len(positive_kcfg.get("covers", [])),
        "admitted": False,
    },
    "negative": {
        "result": "FAILED_AS_EXPECTED",
        "exitCode": 1,
        "mutationId": mutation["mutationId"],
        "mutantRuntimeSha256": mutation["runtime"]["mutantResolvedSha256"],
        "definitionKoreSha256": sha(negative_definition / "definition.kore"),
        "compiledJsonSha256": sha(negative_definition / "compiled.json"),
        "proofSha256": sha(negative_proof_path),
        "kcfgSha256": sha(negative_kcfg_path),
        "terminalFailureNode": terminal[0],
        "failureNodeSha256": sha(failure_node_path),
        "backendRuntimeError": False,
    },
    "residualNonclaims": [
        "This row does not prove compiler correctness or live deployment identity.",
        "This row covers transfer, not transferFrom allowance behavior.",
        "Registry and ledger binding remain coordinator-owned.",
    ],
}
report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(json.dumps({"status": "PASS", "claimId": claim_id, "report": str(report_path), "reportSha256": sha(report_path)}, indent=2))
PY
