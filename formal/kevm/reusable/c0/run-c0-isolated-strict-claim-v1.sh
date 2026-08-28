#!/usr/bin/env bash
set -euo pipefail

: "${C0_CLAIM_ID:?set C0_CLAIM_ID}"
: "${C0_PROFILE:?set C0_PROFILE to canonical or mutant}"
: "${C0_DEFINITION:?set C0_DEFINITION}"
: "${C0_OUTPUT_ROOT:?set C0_OUTPUT_ROOT to an absent directory}"
timeout_seconds=${C0_TIMEOUT_SECONDS:-1800}
parse_only=${C0_PARSE_ONLY:-false}
max_depth=${C0_MAX_DEPTH:-}
[[ $C0_PROFILE == canonical || $C0_PROFILE == mutant ]] || { echo "invalid C0_PROFILE" >&2; exit 64; }
[[ $parse_only == true || $parse_only == false ]] || { echo "C0_PARSE_ONLY must be true or false" >&2; exit 64; }
[[ $timeout_seconds =~ ^[0-9]+$ ]] && (( timeout_seconds > 0 && timeout_seconds <= 1800 )) || {
  echo "C0_TIMEOUT_SECONDS must be 1..1800" >&2
  exit 64
}
max_depth_args=()
max_depth_json=null
if [[ -n $max_depth ]]; then
  [[ $max_depth =~ ^[0-9]+$ ]] && (( max_depth > 0 )) || {
    echo "C0_MAX_DEPTH must be a positive integer" >&2
    exit 64
  }
  max_depth_args=(--max-depth "$max_depth")
  max_depth_json=$max_depth
fi
[[ ! -e $C0_OUTPUT_ROOT ]] || { echo "output root exists: $C0_OUTPUT_ROOT" >&2; exit 64; }

repository_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd -P)
manifest="$repository_root/formal/kevm/reusable/c0/isolated-length-v1/manifest-v1.json"
runner="$repository_root/formal/kevm/reusable/c0/run-c0-isolated-strict-claim-v1.sh"
lock="$repository_root/formal/kevm/dependencies.lock.json"
[[ -f $manifest && -f $runner && -f $lock ]] || { echo "isolated input missing" >&2; exit 66; }

mapfile -t contract < <(python3 - "$manifest" "$C0_CLAIM_ID" "$C0_PROFILE" <<'PY'
import json, sys
manifest_path, claim_id, profile = sys.argv[1:]
with open(manifest_path, encoding="utf-8") as handle:
    manifest = json.load(handle)
claim = next((entry for entry in manifest["claims"] if entry["id"] == claim_id), None)
if claim is None:
    raise SystemExit(f"unknown claim: {claim_id}")
definition = manifest["definitions"][profile]
print(claim["path"])
print(claim["module"])
print(claim["sha256"])
print(definition["definitionKoreSha256"])
print(definition["compiledJsonSha256"])
print(definition["compiledBinSha256"])
print(manifest["runner"]["sha256"])
print(manifest["dependencyLockSha256"])
PY
)
(( ${#contract[@]} == 8 )) || { echo "isolated manifest extraction failed" >&2; exit 65; }
claim_path="$repository_root/${contract[0]}"
module=${contract[1]}
expected_claim=${contract[2]}
expected_definition=${contract[3]}
expected_compiled=${contract[4]}
expected_bin=${contract[5]}
expected_runner=${contract[6]}
expected_lock=${contract[7]}

for path in "$claim_path" "$C0_DEFINITION/definition.kore" "$C0_DEFINITION/compiled.json" "$C0_DEFINITION/compiled.bin"; do
  [[ -f $path ]] || { echo "missing exact input: $path" >&2; exit 66; }
done
[[ $(sha256sum "$claim_path" | awk '{print $1}') == "$expected_claim" ]] || { echo "claim drift" >&2; exit 65; }
[[ $(sha256sum "$C0_DEFINITION/definition.kore" | awk '{print $1}') == "$expected_definition" ]] || { echo "definition drift" >&2; exit 65; }
[[ $(sha256sum "$C0_DEFINITION/compiled.json" | awk '{print $1}') == "$expected_compiled" ]] || { echo "compiled definition drift" >&2; exit 65; }
[[ $(sha256sum "$C0_DEFINITION/compiled.bin" | awk '{print $1}') == "$expected_bin" ]] || { echo "compiled binary drift" >&2; exit 65; }
[[ $(sha256sum "$runner" | awk '{print $1}') == "$expected_runner" ]] || { echo "runner drift" >&2; exit 65; }
[[ $(sha256sum "$lock" | awk '{print $1}') == "$expected_lock" ]] || { echo "dependency lock drift" >&2; exit 65; }

mkdir -p "$C0_OUTPUT_ROOT"
printf '%s\n' "$C0_CLAIM_ID" > "$C0_OUTPUT_ROOT/claim-id.txt"
printf '%s\n' "$C0_PROFILE" > "$C0_OUTPUT_ROOT/profile.txt"
printf '%s\n' "$module" > "$C0_OUTPUT_ROOT/spec-module.txt"
sha256sum "$claim_path" > "$C0_OUTPUT_ROOT/claim-sha256.txt"
sha256sum "$manifest" > "$C0_OUTPUT_ROOT/manifest-sha256.txt"
started_at=$(date -Is)
started_epoch=$(date +%s)
printf '%s\n' "$started_at" > "$C0_OUTPUT_ROOT/started-at.txt"

native_root=$(mktemp -d /tmp/erc-trust-c0-isolated-XXXXXX)
mkdir -p "$native_root/definition" "$native_root/save" "$native_root/temp"
cp "$claim_path" "$native_root/package.k"
cp -a "$C0_DEFINITION/." "$native_root/definition/"
sha256sum "$native_root/package.k" "$native_root/definition"/* > "$C0_OUTPUT_ROOT/native-input-sha256.txt"

proof_pid=
cleanup() {
  if [[ -n ${proof_pid:-} ]] && kill -0 "$proof_pid" 2>/dev/null; then
    kill -- "-$proof_pid" 2>/dev/null || true
    sleep 2
    kill -KILL -- "-$proof_pid" 2>/dev/null || true
  fi
  rm -rf -- "$native_root"
}
trap cleanup EXIT INT TERM
kore_rpc=/nix/store/wij5nr1s0q3ksvyng4lcybhy467bn9gh-kore-rpc/bin/kore-rpc
[[ -x $kore_rpc ]] || { echo "strict kore-rpc missing" >&2; exit 66; }

if [[ $parse_only == true ]]; then
  kprove=/nix/store/y63xkr8pk2bqd5lh4889rlwldw26v9f4-k-7.1.337-4a46d1231473b599c699160132fd6e76a5c46406/bin/kprove
  [[ -x $kprove ]] || { echo "exact kprove missing" >&2; exit 66; }
  set +e
  "$kprove" "$native_root/package.k" \
    --definition "$native_root/definition" \
    --spec-module "$module" \
    --dry-run \
    --emit-json-spec "$C0_OUTPUT_ROOT/parsed-spec.json" \
    --temp-dir "$native_root/temp" \
    > "$C0_OUTPUT_ROOT/parse.log" 2>&1
  exit_code=$?
  set -e
  ended_at=$(date -Is)
  wall_seconds=$(( $(date +%s) - started_epoch ))
  backend_started=false
  if grep -Eq 'Starting KoreServer|kore-rpc.*started|Proof started' "$C0_OUTPUT_ROOT/parse.log"; then backend_started=true; fi
  cp -a "$native_root/temp" "$C0_OUTPUT_ROOT/temp"
  printf '%s\n' "$exit_code" > "$C0_OUTPUT_ROOT/exit-code.txt"
  printf '%s\n' "$wall_seconds" > "$C0_OUTPUT_ROOT/wall-seconds.txt"
  printf '%s\n' "$ended_at" > "$C0_OUTPUT_ROOT/ended-at.txt"
  printf '{"claimId":"%s","profile":"%s","parseOnly":true,"backendStarted":%s,"exitCode":%s,"wallSeconds":%s,"startedAt":"%s","endedAt":"%s","resumed":false}\n' \
    "$C0_CLAIM_ID" "$C0_PROFILE" "$backend_started" "$exit_code" "$wall_seconds" "$started_at" "$ended_at" \
    > "$C0_OUTPUT_ROOT/run-summary.json"
  cat "$C0_OUTPUT_ROOT/run-summary.json"
  [[ $backend_started == false ]] || exit 70
  exit "$exit_code"
fi

set +e
setsid timeout --signal=TERM --kill-after=30s "${timeout_seconds}s" \
  kevm prove "$native_root/package.k" \
    --definition "$native_root/definition" \
    --spec-module "$module" \
    --save-directory "$native_root/save" \
    --temp-directory "$native_root/temp" \
    --no-use-booster \
    --workers 1 \
    --force-sequential \
    "${max_depth_args[@]}" \
    --failure-information \
    --kore-rpc-command "$kore_rpc" \
    > "$C0_OUTPUT_ROOT/prove.log" 2>&1 &
proof_pid=$!
wait "$proof_pid"
exit_code=$?
set -e
proof_pgid=$proof_pid
proof_pid=
remaining=$(ps -eo pid=,pgid=,args= | awk -v pg="$proof_pgid" '$2 == pg {print}')
[[ -z $remaining ]] || { echo "proof descendants remain: $remaining" >&2; exit 1; }
cp -a "$native_root/save" "$C0_OUTPUT_ROOT/save"
cp -a "$native_root/temp" "$C0_OUTPUT_ROOT/temp"
ended_at=$(date -Is)
wall_seconds=$(( $(date +%s) - started_epoch ))
printf '%s\n' "$exit_code" > "$C0_OUTPUT_ROOT/exit-code.txt"
printf '%s\n' "$wall_seconds" > "$C0_OUTPUT_ROOT/wall-seconds.txt"
printf '%s\n' "$ended_at" > "$C0_OUTPUT_ROOT/ended-at.txt"
printf '{"claimId":"%s","profile":"%s","exitCode":%s,"wallSeconds":%s,"timeoutSeconds":%s,"maxDepth":%s,"startedAt":"%s","endedAt":"%s","booster":false,"assumeDefined":false,"workers":1,"forceSequential":true,"resumed":false}\n' \
  "$C0_CLAIM_ID" "$C0_PROFILE" "$exit_code" "$wall_seconds" "$timeout_seconds" "$max_depth_json" "$started_at" "$ended_at" \
  > "$C0_OUTPUT_ROOT/run-summary.json"
cat "$C0_OUTPUT_ROOT/run-summary.json"
exit "$exit_code"
