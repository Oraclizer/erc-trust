#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: bootstrap-row-proof.sh --spec FILE --module MODULE --definition DIR \
  --output-directory DIR --expected-exit 0|1 --timeout-seconds NATURAL \
  [--max-iterations NATURAL]

This runner creates diagnostic-only proof material for fixing a row claim ID
and its serialized graph contract. It never reports a discharge PASS.
EOF
  exit 64
}

spec=
spec_module=
definition=
output_directory=
expected_exit=
max_iterations=
timeout_seconds=
while (($#)); do
  case "$1" in
    --spec) spec=$2; shift 2 ;;
    --module) spec_module=$2; shift 2 ;;
    --definition) definition=$2; shift 2 ;;
    --output-directory) output_directory=$2; shift 2 ;;
    --expected-exit) expected_exit=$2; shift 2 ;;
    --timeout-seconds) timeout_seconds=$2; shift 2 ;;
    --max-iterations) max_iterations=$2; shift 2 ;;
    *) usage ;;
  esac
done
[[ -n $spec && -n $spec_module && -n $definition && -n $output_directory && -n $expected_exit && -n $timeout_seconds ]] || usage
[[ $expected_exit == 0 || $expected_exit == 1 ]] || usage
[[ $timeout_seconds =~ ^[1-9][0-9]*$ ]] || usage
if [[ -n $max_iterations && ! $max_iterations =~ ^[0-9]+$ ]]; then usage; fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repository_root=$(cd -- "$script_dir/../../.." && pwd -P)
spec=$(realpath "$spec")
definition=$(realpath "$definition")
mkdir -p "$output_directory"
output_directory=$(realpath "$output_directory")
[[ -f $definition/definition.kore && -f $definition/compiled.json ]] || {
  echo "compiled definition is incomplete: $definition" >&2
  exit 66
}
command -v timeout >/dev/null || { echo "GNU timeout is not on PATH" >&2; exit 69; }

claim_copy="$output_directory/claim.k"
python3 - "$spec" "$claim_copy" <<'PY'
import sys
from pathlib import Path
source = Path(sys.argv[1]).read_text(encoding="utf-8")
lines = source.splitlines(keepends=True)
if not lines or not lines[0].startswith("requires "):
    raise SystemExit("row claim must begin with a requires prelude")
Path(sys.argv[2]).write_text("".join(lines[1:]), encoding="utf-8", newline="\n")
PY

kore_rpc_command=$(python3 - "$repository_root/formal/kevm/dependencies.lock.json" <<'PY'
import json, sys
from pathlib import Path
value = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(value["components"]["kore"]["rpcStorePath"] + "/bin/kore-rpc")
PY
)
[[ -x $kore_rpc_command ]] || { echo "Kore RPC is not executable: $kore_rpc_command" >&2; exit 66; }

command=(timeout --signal=TERM --kill-after=30s "${timeout_seconds}s" kevm prove "$claim_copy"
  --definition "$definition"
  --spec-module "$spec_module"
  --save-directory "$output_directory/save"
  --temp-directory "$output_directory/temp"
  --kore-rpc-command "$kore_rpc_command"
  --no-use-booster --workers 1 --force-sequential)
if [[ -n $max_iterations ]]; then command+=(--max-iterations "$max_iterations"); fi
proof_pid=
proof_pgid=
cleanup_process_group() {
  if [[ -n $proof_pid ]] && kill -0 "$proof_pid" 2>/dev/null; then
    kill -- "-$proof_pid" 2>/dev/null || true
    for _ in 1 2 3 4 5; do
      kill -0 "$proof_pid" 2>/dev/null || break
      sleep 1
    done
    kill -KILL -- "-$proof_pid" 2>/dev/null || true
  fi
}
trap cleanup_process_group EXIT INT TERM
set +e
setsid "${command[@]}" >"$output_directory/prove.log" 2>&1 &
proof_pid=$!
wait "$proof_pid"
actual_exit=$?
set -e
proof_pgid=$proof_pid
proof_pid=
trap - EXIT INT TERM
printf '%s\n' "$actual_exit" >"$output_directory/exit-code.txt"
remaining=$(ps -eo pid=,pgid=,args= | awk -v pg="$proof_pgid" '$2 == pg { print }')
[[ -z $remaining ]] || {
  echo "diagnostic proof process group $proof_pgid still has descendants:" >&2
  echo "$remaining" >&2
  exit 1
}
[[ $actual_exit -ne 124 && $actual_exit -ne 137 ]] || {
  echo "diagnostic timed out with exit $actual_exit; timeout is never proof evidence" >&2
  exit 1
}
[[ $actual_exit -eq $expected_exit ]] || {
  echo "diagnostic exit $actual_exit expected $expected_exit" >&2
  exit 1
}

mapfile -t claim_ids < <(find "$output_directory/save" -mindepth 1 -maxdepth 1 -type d \
  -printf '%f\n' | grep -E '^[0-9a-f]{64}$')
[[ ${#claim_ids[@]} -eq 1 ]] || { echo "expected exactly one claim directory" >&2; exit 65; }
claim_id=${claim_ids[0]}
python3 - "$output_directory" "$claim_id" "$actual_exit" "$max_iterations" <<'PY'
import json, re, sys
from pathlib import Path
root = Path(sys.argv[1])
claim_id = sys.argv[2]
actual_exit = int(sys.argv[3])
max_iterations = None if sys.argv[4] == "" else int(sys.argv[4])
proof_root = root / "save" / claim_id
proof = json.loads((proof_root / "proof.json").read_text(encoding="utf-8"))
kcfg = json.loads((proof_root / "kcfg" / "kcfg.json").read_text(encoding="utf-8"))
log = (root / "prove.log").read_text(encoding="utf-8", errors="replace")
pending_match = re.search(r"\((\d+)\s+pending\s+and\s+\d+\s+failing\)", log, re.I)
pending = int(pending_match.group(1)) if pending_match else (0 if f"PROOF PASSED: {claim_id}" in log else None)
report = {
    "status": "DIAGNOSTIC_ONLY",
    "claimId": claim_id,
    "exitCode": actual_exit,
    "maxIterations": max_iterations,
    "graph": {
        "nodes": len(kcfg.get("nodes", [])),
        "edges": len(kcfg.get("edges", [])),
        "covers": len(kcfg.get("covers", [])),
        "terminal": len(proof.get("terminal", [])),
        "stuck": len(kcfg.get("stuck", [])),
        "vacuous": len(kcfg.get("vacuous", [])),
        "pending": pending,
        "admitted": proof.get("admitted"),
    },
    "dischargeEvidence": False,
}
(root / "diagnostic-report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
print(json.dumps(report, indent=2))
PY
