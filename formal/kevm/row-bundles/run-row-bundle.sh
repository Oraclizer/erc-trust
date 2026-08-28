#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: run-row-bundle.sh --bundle FILE --positive-definition DIR \
  --negative-definition DIR --output-directory DIR --report FILE \
  --curated-evidence-directory DIR --isabelle-report FILE \
  --side-timeout-seconds NATURAL --no-use-booster
EOF
  exit 64
}

bundle=
positive_definition=
negative_definition=
output_directory=
report_path=
curated_evidence_directory=
isabelle_report=
side_timeout_seconds=
no_use_booster=false
while (($#)); do
  case "$1" in
    --bundle) bundle=$2; shift 2 ;;
    --positive-definition) positive_definition=$2; shift 2 ;;
    --negative-definition) negative_definition=$2; shift 2 ;;
    --output-directory) output_directory=$2; shift 2 ;;
    --report) report_path=$2; shift 2 ;;
    --curated-evidence-directory) curated_evidence_directory=$2; shift 2 ;;
    --isabelle-report) isabelle_report=$2; shift 2 ;;
    --side-timeout-seconds) side_timeout_seconds=$2; shift 2 ;;
    --no-use-booster) no_use_booster=true; shift ;;
    *) usage ;;
  esac
done

[[ -n $bundle && -n $positive_definition && -n $negative_definition && -n $output_directory && -n $report_path && -n $curated_evidence_directory && -n $isabelle_report && -n $side_timeout_seconds ]] || usage
[[ $side_timeout_seconds =~ ^[1-9][0-9]*$ ]] || usage
[[ $no_use_booster == true ]] || { echo "authoritative replay requires --no-use-booster" >&2; exit 64; }

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repository_root=$(cd -- "$script_dir/../../.." && pwd -P)
bundle=$(realpath "$bundle")
positive_definition=$(realpath "$positive_definition")
negative_definition=$(realpath "$negative_definition")
isabelle_report=$(realpath "$isabelle_report")
mkdir -p "$output_directory" "$(dirname -- "$report_path")"
output_directory=$(realpath "$output_directory")
report_path=$(realpath -m "$report_path")
curated_evidence_directory=$(realpath -m "$curated_evidence_directory")

for path in "$bundle" "$positive_definition/definition.kore" "$positive_definition/compiled.json" \
  "$negative_definition/definition.kore" "$negative_definition/compiled.json" "$isabelle_report"; do
  [[ -f $path ]] || { echo "missing required file: $path" >&2; exit 66; }
done
command -v kevm >/dev/null || { echo "kevm is not on PATH" >&2; exit 69; }
command -v python3 >/dev/null || { echo "python3 is not on PATH" >&2; exit 69; }
command -v node.exe >/dev/null || { echo "node.exe is not on the WSL interop PATH" >&2; exit 69; }
python3 "$script_dir/validate-bundle.py" "$bundle" >"$output_directory/bundle-schema-validation.json"

mapfile -t fields < <(python3 - "$bundle" <<'PY'
import json, sys
from pathlib import Path
b = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if b.get("schemaVersion") != 1:
    raise SystemExit("unsupported row bundle schema")
if b["positive"]["expectedExitCode"] != 0:
    raise SystemExit("positive row proof must expect exit code zero")
if b["positive"]["expectedGraph"]["pending"] != 0:
    raise SystemExit("positive row proof must expect zero pending nodes")
if b["positive"]["expectedGraph"]["terminal"] != 0:
    raise SystemExit("positive row proof must expect zero terminal failure nodes")
if b["negative"]["expectedExitCode"] != 1:
    raise SystemExit("negative row proof must expect semantic failure exit code one")
if b["negative"]["mutationKind"] != "EXECUTABLE_SEMANTIC_MUTANT":
    raise SystemExit("negative row proof must name an executable semantic mutant")
if b["negative"]["expectedGraph"]["terminal"] < 1:
    raise SystemExit("negative row proof must expect a terminal semantic counterexample")
print(b["obligationId"])
print(b["proofSpec"]["path"])
print(b["proofSpec"]["module"])
print(b["proofSpec"]["claimId"])
print(b["proofSpec"]["sha256"])
print(b["positive"]["definitionKoreSha256"])
print(b["positive"]["compiledJsonSha256"])
print(b["positive"]["expectedExitCode"])
print(b["negative"]["definitionKoreSha256"])
print(b["negative"]["compiledJsonSha256"])
print(b["negative"]["expectedExitCode"])
print(b["bridge"]["path"])
print(b["bridge"]["sha256"])
print(b["bridge"]["reverseCheck"])
print(b["isabelle"]["theoryPath"])
print(b["isabelle"]["sourceSha256"])
print(b["isabelle"]["theoremName"])
print(b["isabelle"]["session"])
print(b["isabelle"]["rowManifestPath"])
print(b["isabelle"]["rowManifestSha256"])
PY
)
obligation_id=${fields[0]}
spec_path="$repository_root/${fields[1]}"
spec_module=${fields[2]}
claim_id=${fields[3]}
bridge_path="$repository_root/${fields[11]}"
reverse_check="$repository_root/${fields[13]}"
theory_path="$repository_root/${fields[14]}"
row_manifest_path="$repository_root/${fields[18]}"

sha256_file() { sha256sum "$1" | awk '{print $1}'; }
check_hash() {
  local path=$1 expected=$2 actual
  actual=$(sha256_file "$path")
  [[ $actual == "$expected" ]] || { echo "SHA-256 mismatch: $path: $actual != $expected" >&2; exit 65; }
}
check_hash "$spec_path" "${fields[4]}"
check_hash "$positive_definition/definition.kore" "${fields[5]}"
check_hash "$positive_definition/compiled.json" "${fields[6]}"
check_hash "$negative_definition/definition.kore" "${fields[8]}"
check_hash "$negative_definition/compiled.json" "${fields[9]}"
check_hash "$bridge_path" "${fields[12]}"
check_hash "$theory_path" "${fields[15]}"
check_hash "$row_manifest_path" "${fields[19]}"

python3 "$reverse_check" >"$output_directory/bridge-reverse-check.json"
python3 - "$bundle" "$spec_path" "$theory_path" "$isabelle_report" <<'PY'
import json, re, sys
from pathlib import Path
bundle = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
spec = Path(sys.argv[2]).read_text(encoding="utf-8")
theory = Path(sys.argv[3]).read_text(encoding="utf-8")
report = json.loads(Path(sys.argv[4]).read_text(encoding="utf-8"))
for token in bundle["negative"]["claimRequirementTokens"]:
    if token not in spec:
        raise SystemExit(f"negative target requirement token missing from unchanged claim: {token}")
for token in bundle["isabelle"]["bannedTokens"]:
    if re.search(r"\b" + re.escape(token) + r"\b", theory, flags=re.IGNORECASE):
        raise SystemExit(f"banned Isabelle source token: {token}")
if f'theorem {bundle["isabelle"]["theoremName"]}:' not in theory:
    raise SystemExit("named Isabelle theorem missing")
if (
    report.get("status") != "PASS"
    or report.get("session") != bundle["isabelle"]["session"]
    or report.get("theoremName") != bundle["isabelle"]["theoremName"]
    or report.get("buildExitCode") != 0
    or report.get("bannedSourceForms") != 0
    or report.get("oracleDependencyCount") != 0
    or report.get("theorySha256") != bundle["isabelle"]["sourceSha256"]
    or report.get("rowManifestSha256") != bundle["isabelle"]["rowManifestSha256"]
):
    raise SystemExit("Isabelle closure report does not satisfy the row contract")
PY

positive_spec="$output_directory/positive-claim.k"
negative_spec="$output_directory/negative-claim.k"
python3 - "$spec_path" "$positive_spec" "$negative_spec" <<'PY'
import sys
from pathlib import Path
source = Path(sys.argv[1]).read_text(encoding="utf-8")
lines = source.splitlines(keepends=True)
if not lines or not lines[0].startswith("requires "):
    raise SystemExit("row claim must begin with a requires prelude")
claim = "".join(lines[1:])
Path(sys.argv[2]).write_text(claim, encoding="utf-8", newline="\n")
Path(sys.argv[3]).write_text(claim, encoding="utf-8", newline="\n")
PY

positive_save="$output_directory/positive-save"
negative_save="$output_directory/negative-save"
positive_log="$output_directory/positive.log"
negative_log="$output_directory/negative.log"
kore_rpc_command=$(python3 - "$repository_root/formal/kevm/dependencies.lock.json" <<'PY'
import json, sys
from pathlib import Path
print(json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["components"]["kore"]["rpcStorePath"] + "/bin/kore-rpc")
PY
)
[[ -x $kore_rpc_command ]] || { echo "Kore RPC is not executable: $kore_rpc_command" >&2; exit 66; }

run_side() {
  local side=$1 definition=$2 spec=$3 save=$4 log=$5 expected_exit=$6 started exit_code proof_pid proof_pgid remaining
  started=$(date +%s)
  proof_pid=
  cleanup_side_process_group() {
    if [[ -n $proof_pid ]] && kill -0 "$proof_pid" 2>/dev/null; then
      kill -- "-$proof_pid" 2>/dev/null || true
      for _ in 1 2 3 4 5; do
        kill -0 "$proof_pid" 2>/dev/null || break
        sleep 1
      done
      kill -KILL -- "-$proof_pid" 2>/dev/null || true
    fi
  }
  trap cleanup_side_process_group EXIT INT TERM
  set +e
  setsid timeout --signal=TERM --kill-after=30s "$side_timeout_seconds" kevm prove "$spec" \
    --definition "$definition" \
    --spec-module "$spec_module" \
    --save-directory "$save" \
    --temp-directory "$output_directory/$side-temp" \
    --kore-rpc-command "$kore_rpc_command" \
    --no-use-booster --workers 1 --force-sequential >"$log" 2>&1 &
  proof_pid=$!
  wait "$proof_pid"
  exit_code=$?
  set -e
  proof_pgid=$proof_pid
  proof_pid=
  trap - EXIT INT TERM
  remaining=$(ps -eo pid=,pgid=,args= | awk -v pg="$proof_pgid" '$2 == pg { print }')
  [[ -z $remaining ]] || {
    echo "$side proof process group $proof_pgid still has descendants:" >&2
    echo "$remaining" >&2
    exit 1
  }
  [[ $exit_code -ne 124 && $exit_code -ne 137 ]] || {
    echo "$side proof timed out with exit $exit_code; timeout is never proof evidence" >&2
    exit 1
  }
  [[ $exit_code -eq $expected_exit ]] || { echo "$side proof exit $exit_code expected $expected_exit" >&2; exit 1; }
  printf '%s\n' "$(( $(date +%s) - started ))" >"$output_directory/$side-elapsed-seconds.txt"
}
run_side positive "$positive_definition" "$positive_spec" "$positive_save" "$positive_log" "${fields[7]}"
run_side negative "$negative_definition" "$negative_spec" "$negative_save" "$negative_log" "${fields[10]}"

positive_proof="$positive_save/$claim_id/proof.json"
positive_kcfg="$positive_save/$claim_id/kcfg/kcfg.json"
negative_proof="$negative_save/$claim_id/proof.json"
negative_kcfg="$negative_save/$claim_id/kcfg/kcfg.json"
for path in "$positive_proof" "$positive_kcfg" "$negative_proof" "$negative_kcfg"; do
  [[ -f $path ]] || { echo "missing replay artifact: $path" >&2; exit 66; }
done

python3 - "$bundle" "$output_directory/positive-expected.json" "$output_directory/negative-expected.json" <<'PY'
import json, sys
from pathlib import Path
b = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
for side, output in (("positive", sys.argv[2]), ("negative", sys.argv[3])):
    value = {
        "claimId": b["proofSpec"]["claimId"],
        "exitCode": b[side]["expectedExitCode"],
        "graph": b[side]["expectedGraph"],
        "witnessTokens": b[side]["witnessTokens"],
        "forbiddenLogTokens": b[side]["forbiddenLogTokens"],
    }
    Path(output).write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
PY
analyzer_windows=$(wslpath -w "$script_dir/analyze-row-proof.mjs")
node.exe "$analyzer_windows" positive \
  "$(wslpath -w "$positive_proof")" "$(wslpath -w "$positive_kcfg")" \
  "$(wslpath -w "$positive_log")" "$(wslpath -w "$output_directory/positive-expected.json")" \
  >"$output_directory/positive-analysis.json"
node.exe "$analyzer_windows" negative \
  "$(wslpath -w "$negative_proof")" "$(wslpath -w "$negative_kcfg")" \
  "$(wslpath -w "$negative_log")" "$(wslpath -w "$output_directory/negative-expected.json")" \
  >"$output_directory/negative-analysis.json"

python3 "$script_dir/curate-row-output.py" \
  --repository-root "$repository_root" \
  --bundle "$bundle" \
  --isabelle-report "$isabelle_report" \
  --output-directory "$output_directory" \
  --curated-evidence-directory "$curated_evidence_directory" \
  --report "$report_path"
python3 "$script_dir/verify-curated-evidence.py" \
  --repository-root "$repository_root" \
  --report "$report_path"
