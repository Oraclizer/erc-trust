#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: run-runtime-claims.sh --positive-definition DIR --negative-definition DIR [options]

Required:
  --positive-definition DIR  Exact pinned canonical KEVM definition
  --negative-definition DIR  Exact pinned typed-payload-mutant KEVM definition

Options:
  --kore-rpc-command PATH     Override the pinned Kore RPC executable
  --output-directory DIR     Preserve replay saves and logs in DIR
  --report PATH              Write the sanitized replay report to PATH
  --no-use-booster           Required authoritative-backend boundary
EOF
  exit 64
}

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repository_root=$(cd -- "$script_dir/../.." && pwd -P)
evidence_root="$repository_root/evidence/end-to-end-refinement/kevm/fail-05-generic-dispatcher-revert-20260802T174934Z"
evidence_path="$evidence_root/evidence.json"
spec_path="$repository_root/formal/kevm/specs/full-transaction-generic-dispatcher-revert-spec.k"
negative_source_root="$evidence_root/negative"
generated_bridge_path="$repository_root/formal/kevm/generated/trust-runtime-bridge.k"
lock_path="$repository_root/formal/kevm/dependencies.lock.json"
positive_definition=${ERC_TRUST_POSITIVE_DEFINITION:-}
negative_definition=${ERC_TRUST_NEGATIVE_DEFINITION:-}
kore_rpc_command=${ERC_TRUST_KORE_RPC_COMMAND:-}
output_directory=${ERC_TRUST_RUNTIME_REPLAY_OUTPUT:-}
report_path="$evidence_root/independent-replay.json"
no_use_booster=false

while (($#)); do
  case "$1" in
    --positive-definition)
      (($# >= 2)) || usage
      positive_definition=$2
      shift 2
      ;;
    --negative-definition)
      (($# >= 2)) || usage
      negative_definition=$2
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

[[ -n $positive_definition && -n $negative_definition ]] || usage
[[ $no_use_booster == true ]] || {
  echo "authoritative replay requires --no-use-booster" >&2
  exit 64
}
for required_file in "$evidence_path" "$spec_path" "$generated_bridge_path" "$lock_path"; do
  [[ -f $required_file ]] || { echo "missing required file: $required_file" >&2; exit 66; }
done
for definition in "$positive_definition" "$negative_definition"; do
  [[ -f $definition/definition.kore && -f $definition/compiled.json ]] || {
    echo "incomplete KEVM definition: $definition" >&2
    exit 66
  }
done
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

mapfile -t expected < <(python3 - "$evidence_path" <<'PY'
import json
import sys
from pathlib import Path
evidence = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(evidence["claimId"])
print(evidence["positive"]["definitionKoreSha256"])
print(evidence["positive"]["compiledJsonSha256"])
print(evidence["positive"]["runtimeBridgeSchemaSha256"])
print(evidence["positive"]["runtimeBridgeSha256"])
print(evidence["negative"]["definitionKoreSha256"])
print(evidence["negative"]["compiledJsonSha256"])
print(evidence["negative"]["mutantBridgeSha256"])
print(evidence["negative"]["claimSha256"])
print(evidence["negative"]["runtimeVerificationSha256"])
print(evidence["negative"]["witnessOutputHex"])
print(evidence["selectorBridge"]["genericDispatcherInputSelector"])
print(evidence["selectorBridge"]["expectedRevertData"])
PY
)
claim_id=${expected[0]}

sha256_file() { sha256sum "$1" | awk '{print $1}'; }
check_hash() {
  local path=$1
  local expected_hash=$2
  local actual_hash
  actual_hash=$(sha256_file "$path")
  [[ $actual_hash == "$expected_hash" ]] || {
    echo "SHA-256 mismatch: $path: $actual_hash != $expected_hash" >&2
    exit 65
  }
}

check_hash "$positive_definition/definition.kore" "${expected[1]}"
check_hash "$positive_definition/compiled.json" "${expected[2]}"
check_hash "$negative_definition/definition.kore" "${expected[5]}"
check_hash "$negative_definition/compiled.json" "${expected[6]}"
check_hash "$negative_source_root/mutant-runtime-bridge.k" "${expected[7]}"
check_hash "$spec_path" "$(python3 - "$evidence_path" <<'PY'
import json
import sys
from pathlib import Path
print(json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["positive"]["claimSha256"])
PY
)"
check_hash "$negative_source_root/claim.k" "${expected[8]}"
check_hash "$negative_source_root/mutant-runtime-verification.k" "${expected[9]}"

if [[ -z $output_directory ]]; then
  output_directory=$(mktemp -d "${TMPDIR:-/tmp}/erc-trust-runtime-claims.XXXXXX")
else
  mkdir -p "$output_directory"
  output_directory=$(cd -- "$output_directory" && pwd -P)
fi
positive_save="$output_directory/positive-save"
negative_save="$output_directory/negative-save"
positive_spec_root="$output_directory/positive-spec"
negative_spec_root="$output_directory/negative-spec"
mkdir -p "$positive_save" "$negative_save" "$positive_spec_root" "$negative_spec_root" "$(dirname -- "$report_path")"
python3 - "$spec_path" "$positive_spec_root/claim.k" \
  "$negative_source_root/claim.k" "$negative_spec_root/claim.k" <<'PY'
import sys
from pathlib import Path

for source_name, output_name in ((sys.argv[1], sys.argv[2]), (sys.argv[3], sys.argv[4])):
    source = Path(source_name).read_text(encoding="utf-8")
    lines = source.splitlines(keepends=True)
    if not lines or not lines[0].startswith("requires "):
        raise SystemExit(f"expected a required-module prelude: {source_name}")
    Path(output_name).write_text("".join(lines[1:]), encoding="utf-8", newline="\n")
PY

positive_log="$output_directory/positive.log"
negative_log="$output_directory/negative.log"
positive_started=$(date +%s)
kevm prove "$positive_spec_root/claim.k" \
  --definition "$positive_definition" \
  --spec-module TRUST-FULL-TRANSACTION-GENERIC-DISPATCHER-REVERT-SPEC \
  --save-directory "$positive_save" \
  --temp-directory "$output_directory/positive-temp" \
  --kore-rpc-command "$kore_rpc_command" \
  --no-use-booster \
  --workers 1 \
  --force-sequential >"$positive_log" 2>&1
positive_elapsed=$(( $(date +%s) - positive_started ))

negative_started=$(date +%s)
set +e
kevm prove "$negative_spec_root/claim.k" \
  --definition "$negative_definition" \
  --spec-module TRUST-FULL-TRANSACTION-GENERIC-DISPATCHER-REVERT-SPEC \
  --save-directory "$negative_save" \
  --temp-directory "$output_directory/negative-temp" \
  --kore-rpc-command "$kore_rpc_command" \
  --no-use-booster \
  --workers 1 \
  --force-sequential >"$negative_log" 2>&1
negative_exit=$?
set -e
negative_elapsed=$(( $(date +%s) - negative_started ))
[[ $negative_exit -eq 1 ]] || {
  echo "semantic mutant returned unexpected exit code: $negative_exit" >&2
  exit 1
}

python3 - \
  "$repository_root" "$evidence_path" "$spec_path" "$positive_definition" "$negative_definition" \
  "$positive_save" "$negative_save" "$positive_log" "$negative_log" "$negative_exit" \
  "$positive_elapsed" "$negative_elapsed" "$report_path" "$output_directory" <<'PY'
import datetime
import hashlib
import json
import sys
from pathlib import Path

(
    repository_root, evidence_path, spec_path, positive_definition, negative_definition,
    positive_save, negative_save, positive_log, negative_log, negative_exit,
    positive_elapsed, negative_elapsed, report_path, output_directory,
) = sys.argv[1:]
repository_root = Path(repository_root)
evidence_path = Path(evidence_path)
spec_path = Path(spec_path)
positive_definition = Path(positive_definition)
negative_definition = Path(negative_definition)
positive_save = Path(positive_save)
negative_save = Path(negative_save)
positive_log = Path(positive_log)
negative_log = Path(negative_log)
negative_exit = int(negative_exit)
positive_elapsed = int(positive_elapsed)
negative_elapsed = int(negative_elapsed)
report_path = Path(report_path)
output_directory = Path(output_directory)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def repo(path):
    return path.resolve().relative_to(repository_root.resolve()).as_posix()

evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
claim_id = evidence["claimId"]
canonical_sequence = evidence["negative"]["canonicalSequence"]
mutant_sequence = evidence["negative"]["mutantSequence"]
generated_bridge_path = repository_root / "formal" / "kevm" / "generated" / "trust-runtime-bridge.k"
mutant_bridge_path = evidence_path.parent / "negative" / "mutant-runtime-bridge.k"
generated_bridge_text = generated_bridge_path.read_text(encoding="utf-8")
mutant_bridge_text = mutant_bridge_path.read_text(encoding="utf-8")
if (
    generated_bridge_text.count(canonical_sequence) != 1
    or generated_bridge_text.count(mutant_sequence) != 0
    or mutant_bridge_text.count(canonical_sequence) != 0
    or mutant_bridge_text.count(mutant_sequence) != 1
):
    raise SystemExit("canonical/mutant runtime boundary mismatch")
positive_proof_path = positive_save / claim_id / "proof.json"
positive_kcfg_path = positive_save / claim_id / "kcfg" / "kcfg.json"
negative_proof_path = negative_save / claim_id / "proof.json"
negative_kcfg_path = negative_save / claim_id / "kcfg" / "kcfg.json"
for path in (positive_proof_path, positive_kcfg_path, negative_proof_path, negative_kcfg_path):
    if not path.is_file():
        raise SystemExit(f"missing replay artifact: {path}")

positive_proof = json.loads(positive_proof_path.read_text(encoding="utf-8"))
positive_kcfg = json.loads(positive_kcfg_path.read_text(encoding="utf-8"))
positive_log_text = positive_log.read_text(encoding="utf-8", errors="replace")
if (
    positive_proof.get("id") != claim_id
    or positive_proof.get("admitted") is not False
    or len(positive_kcfg.get("nodes", [])) != 4
    or len(positive_kcfg.get("edges", [])) != 2
    or len(positive_kcfg.get("covers", [])) != 1
    or positive_kcfg.get("stuck")
    or positive_kcfg.get("vacuous")
    or f"PROOF PASSED: {claim_id}" not in positive_log_text
):
    raise SystemExit("positive replay graph or log mismatch")

negative_proof = json.loads(negative_proof_path.read_text(encoding="utf-8"))
negative_kcfg = json.loads(negative_kcfg_path.read_text(encoding="utf-8"))
negative_log_text = negative_log.read_text(encoding="utf-8", errors="replace")
terminal_nodes = [int(node) for node in negative_proof.get("terminal", [])]
if (
    negative_proof.get("id") != claim_id
    or len(terminal_nodes) != 1
    or terminal_nodes[0] not in negative_kcfg.get("nodes", [])
    or f"PROOF FAILED: {claim_id}" not in negative_log_text
    or "Runtime error" in negative_log_text
    or "Proof crashed" in negative_log_text
):
    raise SystemExit("negative replay did not produce the expected semantic failure")
failure_node_path = negative_save / claim_id / "kcfg" / "nodes" / f"{terminal_nodes[0]}.json"
failure_node_text = failure_node_path.read_text(encoding="utf-8")
if any(token not in failure_node_text for token in ("EVMC_REVERT", "x8c", "xf6", "x0b")):
    raise SystemExit("negative replay witness payload missing")

runner_path = repository_root / "formal" / "kevm" / "run-runtime-claims.sh"
report = {
    "schemaVersion": 1,
    "obligationId": "FAIL-05",
    "status": "PASS",
    "createdAtUtc": datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "claimId": claim_id,
    "runner": {"path": repo(runner_path), "sha256": sha(runner_path)},
    "proofSpec": {"path": repo(spec_path), "sha256": sha(spec_path)},
    "generatedBridge": {"path": repo(generated_bridge_path), "sha256": sha(generated_bridge_path)},
    "pinnedCompatibilityBridge": {
        "schemaSha256": evidence["positive"]["runtimeBridgeSchemaSha256"],
        "sha256": evidence["positive"]["runtimeBridgeSha256"],
        "construction": "recorded source closure of the exact positive definition; replay imports the compiled module without re-declaring source modules",
    },
    "selectorBoundary": evidence["selectorBridge"],
    "positive": {
        "result": "PASS",
        "exitCode": 0,
        "elapsedWallSeconds": positive_elapsed,
        "definitionKoreSha256": sha(positive_definition / "definition.kore"),
        "compiledJsonSha256": sha(positive_definition / "compiled.json"),
        "proofSha256": sha(positive_proof_path),
        "kcfgSha256": sha(positive_kcfg_path),
        "nodes": len(positive_kcfg["nodes"]),
        "edges": len(positive_kcfg["edges"]),
        "covers": len(positive_kcfg["covers"]),
        "admitted": False,
    },
    "negative": {
        "result": "FAILED_AS_EXPECTED",
        "exitCode": negative_exit,
        "elapsedWallSeconds": negative_elapsed,
        "definitionKoreSha256": sha(negative_definition / "definition.kore"),
        "compiledJsonSha256": sha(negative_definition / "compiled.json"),
        "proofSha256": sha(negative_proof_path),
        "kcfgSha256": sha(negative_kcfg_path),
        "terminalFailureNode": terminal_nodes[0],
        "failureNodeSha256": sha(failure_node_path),
        "witnessOutputHex": evidence["negative"]["witnessOutputHex"],
        "backendRuntimeError": False,
    },
    "curatedEvidence": {"path": repo(evidence_path), "sha256": sha(evidence_path)},
    "residualNonclaims": [
        "The replay does not prove compiler correctness or live deployment identity.",
        "The expected-negative run records one named counterexample, not discharge of its fail-fast pending branches.",
        "The replay discharges only FAIL-05, not the remaining refinement registry.",
    ],
}
report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(json.dumps({
    "status": "PASS",
    "claimId": claim_id,
    "positiveElapsedSeconds": positive_elapsed,
    "negativeElapsedSeconds": negative_elapsed,
    "negativeTerminalNode": terminal_nodes[0],
    "report": repo(report_path),
    "reportSha256": sha(report_path),
    "replayOutputDirectory": str(output_directory),
}, indent=2))
PY
