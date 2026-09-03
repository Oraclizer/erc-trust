#!/usr/bin/env bash
set -euo pipefail

: "${C0_UINT48_CLAIM_ID:?set C0_UINT48_CLAIM_ID}"
: "${C0_UINT48_DEFINITION:?set C0_UINT48_DEFINITION}"
: "${C0_UINT48_OUTPUT_ROOT:?set C0_UINT48_OUTPUT_ROOT to an absent directory}"
parse_only=${C0_UINT48_PARSE_ONLY:-false}
timeout_seconds=${C0_UINT48_TIMEOUT_SECONDS:-1800}
[[ $parse_only == true || $parse_only == false ]] || { echo "C0_UINT48_PARSE_ONLY must be true or false" >&2; exit 64; }
[[ $timeout_seconds =~ ^[0-9]+$ ]] && (( timeout_seconds > 0 && timeout_seconds <= 1800 )) || exit 64
[[ ! -e $C0_UINT48_OUTPUT_ROOT ]] || { echo "output root exists: $C0_UINT48_OUTPUT_ROOT" >&2; exit 64; }

repository_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd -P)
source_manifest="$repository_root/formal/kevm/reusable/c0/uint48-symbolic-word-v2/source-manifest-v2.json"
lock="$repository_root/formal/kevm/dependencies.lock.json"
readonly expected_source_manifest=1627edad156c84d14193d99ce4f46bf78b55fe7771041dadd36fa67e285b203c
readonly expected_lock=3134e7692086170f86b6dd42e7ebd0256c188da8db8cbd17241c3d2c8d315196
readonly expected_definition=bac21e3e90990c4c060bf77ecfe161a70d18900c631dcea5a37343765e6b3e33
readonly expected_compiled_json=5ba6257f64024f7eff4ec99c569db9f9477fd5d2a625f44ed04e091fdf795a50
readonly expected_compiled_bin=6363c878ee8e9d4a1cd61b0c862e5feb8c6e485af518f64e654130f453f8350e
readonly kprove=/nix/store/y63xkr8pk2bqd5lh4889rlwldw26v9f4-k-7.1.337-4a46d1231473b599c699160132fd6e76a5c46406/bin/kprove
readonly kore_rpc=/nix/store/wij5nr1s0q3ksvyng4lcybhy467bn9gh-kore-rpc/bin/kore-rpc

for path in "$source_manifest" "$lock" "$C0_UINT48_DEFINITION/definition.kore" \
  "$C0_UINT48_DEFINITION/compiled.json" "$C0_UINT48_DEFINITION/compiled.bin" "$kprove" "$kore_rpc"; do
  [[ -f $path ]] || { echo "missing exact input: $path" >&2; exit 66; }
done
[[ -x $kprove && -x $kore_rpc ]] || exit 66
[[ $(sha256sum "$source_manifest" | awk '{print $1}') == "$expected_source_manifest" ]] || { echo "source manifest drift" >&2; exit 65; }
[[ $(sha256sum "$lock" | awk '{print $1}') == "$expected_lock" ]] || { echo "dependency lock drift" >&2; exit 65; }
[[ $(sha256sum "$C0_UINT48_DEFINITION/definition.kore" | awk '{print $1}') == "$expected_definition" ]] || { echo "definition drift" >&2; exit 65; }
[[ $(sha256sum "$C0_UINT48_DEFINITION/compiled.json" | awk '{print $1}') == "$expected_compiled_json" ]] || { echo "compiled definition drift" >&2; exit 65; }
[[ $(sha256sum "$C0_UINT48_DEFINITION/compiled.bin" | awk '{print $1}') == "$expected_compiled_bin" ]] || { echo "compiled binary drift" >&2; exit 65; }

mapfile -t claim_contract < <(python3 - "$source_manifest" "$C0_UINT48_CLAIM_ID" <<'PY'
import json, sys
manifest_path, claim_id = sys.argv[1:]
with open(manifest_path, encoding="utf-8") as handle:
    manifest = json.load(handle)
claim = next((entry for entry in manifest["claims"] if entry["id"] == claim_id), None)
if claim is None:
    raise SystemExit(f"unknown UINT48 v2 claim: {claim_id}")
print(claim["path"])
print(claim["module"])
print(claim["sha256"])
print(claim["role"])
PY
)
(( ${#claim_contract[@]} == 4 )) || exit 65
claim_path="$repository_root/${claim_contract[0]}"
module=${claim_contract[1]}
expected_claim=${claim_contract[2]}
role=${claim_contract[3]}
[[ -f $claim_path ]] || exit 66
[[ $(sha256sum "$claim_path" | awk '{print $1}') == "$expected_claim" ]] || { echo "claim drift" >&2; exit 65; }

mkdir -p "$C0_UINT48_OUTPUT_ROOT"
printf '%s\n' "$C0_UINT48_CLAIM_ID" > "$C0_UINT48_OUTPUT_ROOT/claim-id.txt"
printf '%s\n' "$role" > "$C0_UINT48_OUTPUT_ROOT/claim-role.txt"
printf '%s\n' "$module" > "$C0_UINT48_OUTPUT_ROOT/spec-module.txt"
sha256sum "$claim_path" > "$C0_UINT48_OUTPUT_ROOT/package-sha256.txt"
sha256sum "$source_manifest" > "$C0_UINT48_OUTPUT_ROOT/source-manifest-sha256.txt"
date -Is > "$C0_UINT48_OUTPUT_ROOT/started-at.txt"
started=$(date +%s)

native_root=$(mktemp -d /tmp/erc-trust-c0-uint48-v2-canonical-XXXXXX)
mkdir -p "$native_root/definition" "$native_root/save" "$native_root/temp"
cp "$claim_path" "$native_root/package.k"
cp -a "$C0_UINT48_DEFINITION/." "$native_root/definition/"
sha256sum "$native_root/package.k" "$native_root/definition"/* > "$C0_UINT48_OUTPUT_ROOT/native-input-sha256.txt"

child_pid=
cleanup() {
  if [[ -n ${child_pid:-} ]] && kill -0 "$child_pid" 2>/dev/null; then
    kill -- "-$child_pid" 2>/dev/null || true
    sleep 2
    kill -KILL -- "-$child_pid" 2>/dev/null || true
  fi
  rm -rf -- "$native_root"
}
trap cleanup EXIT INT TERM

if [[ $parse_only == true ]]; then
  set +e
  setsid "$kprove" "$native_root/package.k" --definition "$native_root/definition" \
    --spec-module "$module" --dry-run --emit-json-spec "$C0_UINT48_OUTPUT_ROOT/parsed-spec.json" \
    --temp-dir "$native_root/temp" > "$C0_UINT48_OUTPUT_ROOT/parse.log" 2>&1 &
  child_pid=$!
  wait "$child_pid"
  exit_code=$?
  set -e
  child_pgid=$child_pid
  child_pid=
  remaining=$(ps -eo pid=,pgid=,args= | awk -v pg="$child_pgid" '$2 == pg {print}')
  [[ -z $remaining ]] || exit 1
  backend_started=false
  if grep -Eq 'Starting KoreServer|kore-rpc.*started|Proof started' "$C0_UINT48_OUTPUT_ROOT/parse.log"; then backend_started=true; fi
  elapsed=$(( $(date +%s) - started ))
  printf '%s\n' "$exit_code" > "$C0_UINT48_OUTPUT_ROOT/exit-code.txt"
  printf '%s\n' "$elapsed" > "$C0_UINT48_OUTPUT_ROOT/wall-seconds.txt"
  date -Is > "$C0_UINT48_OUTPUT_ROOT/ended-at.txt"
  printf '{"claimId":"%s","role":"%s","profile":"canonical-v2","parseOnly":true,"backendStarted":%s,"exitCode":%s,"wallSeconds":%s,"booster":false,"assumeDefined":false,"resumed":false,"familyCredit":0}\n' \
    "$C0_UINT48_CLAIM_ID" "$role" "$backend_started" "$exit_code" "$elapsed" > "$C0_UINT48_OUTPUT_ROOT/run-summary.json"
  cat "$C0_UINT48_OUTPUT_ROOT/run-summary.json"
  [[ $backend_started == false ]] || exit 70
  exit "$exit_code"
fi

set +e
setsid timeout --signal=TERM --kill-after=30s "${timeout_seconds}s" \
  kevm prove "$native_root/package.k" --definition "$native_root/definition" --spec-module "$module" \
    --save-directory "$native_root/save" --temp-directory "$native_root/temp" --no-use-booster \
    --workers 1 --force-sequential --failure-information --break-every-step \
    --kore-rpc-command "$kore_rpc" > "$C0_UINT48_OUTPUT_ROOT/prove.log" 2>&1 &
child_pid=$!
wait "$child_pid"
exit_code=$?
set -e
child_pgid=$child_pid
child_pid=
remaining=$(ps -eo pid=,pgid=,args= | awk -v pg="$child_pgid" '$2 == pg {print}')
[[ -z $remaining ]] || exit 1
cp -a "$native_root/save" "$C0_UINT48_OUTPUT_ROOT/save"
cp -a "$native_root/temp" "$C0_UINT48_OUTPUT_ROOT/temp"
elapsed=$(( $(date +%s) - started ))
printf '%s\n' "$exit_code" > "$C0_UINT48_OUTPUT_ROOT/exit-code.txt"
printf '%s\n' "$elapsed" > "$C0_UINT48_OUTPUT_ROOT/wall-seconds.txt"
date -Is > "$C0_UINT48_OUTPUT_ROOT/ended-at.txt"
printf '{"claimId":"%s","role":"%s","profile":"canonical-v2","parseOnly":false,"exitCode":%s,"wallSeconds":%s,"timeoutSeconds":%s,"booster":false,"assumeDefined":false,"workers":1,"forceSequential":true,"breakEveryStep":true,"resumed":false,"familyCredit":0}\n' \
  "$C0_UINT48_CLAIM_ID" "$role" "$exit_code" "$elapsed" "$timeout_seconds" > "$C0_UINT48_OUTPUT_ROOT/run-summary.json"
cat "$C0_UINT48_OUTPUT_ROOT/run-summary.json"
exit "$exit_code"
