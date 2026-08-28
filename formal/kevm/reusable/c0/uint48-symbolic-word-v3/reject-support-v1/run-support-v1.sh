#!/usr/bin/env bash
set -euo pipefail

: "${C0_UINT48_DEFINITION:?set C0_UINT48_DEFINITION}"
: "${C0_UINT48_OUTPUT_ROOT:?set C0_UINT48_OUTPUT_ROOT to an absent directory}"
parse_only=${C0_UINT48_PARSE_ONLY:-false}
timeout_seconds=${C0_UINT48_TIMEOUT_SECONDS:-1800}
support_version=${C0_UINT48_SUPPORT_VERSION:-1}
[[ $parse_only == true || $parse_only == false ]] || exit 64
[[ $timeout_seconds =~ ^[0-9]+$ ]] && (( timeout_seconds > 0 && timeout_seconds <= 1800 )) || exit 64
[[ $support_version == 1 || $support_version == 2 ]] || exit 64
[[ ! -e $C0_UINT48_OUTPUT_ROOT ]] || exit 64

repository_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../../../.." && pwd -P)
support_root="$repository_root/formal/kevm/reusable/c0/uint48-symbolic-word-v3/reject-support-v1"
definition_receipt="$repository_root/evidence/end-to-end-refinement/c0-uint48-symbolic-word-v3-definition-receipt.json"
lock="$repository_root/formal/kevm/dependencies.lock.json"
if [[ $support_version == 1 ]]; then
  manifest="$support_root/manifest-v1.json"
  claim="$support_root/c0-uint48-high-mask-is-not-self.k"
  expected_manifest=c0eeb756b5030a4ed827bf1b212f83399773b9bbe6ab79bddf039e7fbc5c03f5
  expected_claim=9cd999804340dd3d48a361158cc2be47770f89e0289f2d9be982e62fa1fca9c6
  module=C0-UINT48-REJECT-SUPPORT-SPEC
else
  manifest="$support_root/manifest-v2.json"
  claim="$support_root/c0-uint48-high-mask-is-not-self-v2.k"
  expected_manifest=228966e8f98b39ce5066a9a2877ab65a652b44e49db01dc5ddf3a82f38d6509e
  expected_claim=812d4e0ae44ca8db82e8a2655fe6453ac8218eaad3c59bc4a8a085ad9b3ee3fd
  module=C0-UINT48-REJECT-SUPPORT-V2-SPEC
fi
readonly expected_manifest expected_claim module
readonly expected_definition_receipt=af9e77a2f82a5587d62345de44e3f8bf6a6afa3a315bc3762afc6a82cb9dbe3a
readonly expected_definition=d8ad03e19b362aeea0344ae0ffa1882c228cb72f3ebdfc146b09554862ad2507
readonly expected_compiled_json=0b9f666bf720a3e72b5ce87b3c87fa167928c70af481db8b629bef3f4c864d9c
readonly expected_compiled_bin=ed68d8f5c769c0523cb1ebba9e7ff9bf1995d147c9a4db4b7aa6fdf64e266c0b
readonly expected_lock=3134e7692086170f86b6dd42e7ebd0256c188da8db8cbd17241c3d2c8d315196
readonly kprove=/nix/store/y63xkr8pk2bqd5lh4889rlwldw26v9f4-k-7.1.337-4a46d1231473b599c699160132fd6e76a5c46406/bin/kprove
readonly kore_rpc=/nix/store/wij5nr1s0q3ksvyng4lcybhy467bn9gh-kore-rpc/bin/kore-rpc

for path in "$manifest" "$claim" "$definition_receipt" "$lock" "$C0_UINT48_DEFINITION/definition.kore" \
  "$C0_UINT48_DEFINITION/compiled.json" "$C0_UINT48_DEFINITION/compiled.bin" "$kprove" "$kore_rpc"; do
  [[ -f $path ]] || exit 66
done
[[ $(sha256sum "$manifest" | awk '{print $1}') == "$expected_manifest" ]] || exit 65
[[ $(sha256sum "$claim" | awk '{print $1}') == "$expected_claim" ]] || exit 65
[[ $(sha256sum "$definition_receipt" | awk '{print $1}') == "$expected_definition_receipt" ]] || exit 65
[[ $(sha256sum "$lock" | awk '{print $1}') == "$expected_lock" ]] || exit 65
[[ $(sha256sum "$C0_UINT48_DEFINITION/definition.kore" | awk '{print $1}') == "$expected_definition" ]] || exit 65
[[ $(sha256sum "$C0_UINT48_DEFINITION/compiled.json" | awk '{print $1}') == "$expected_compiled_json" ]] || exit 65
[[ $(sha256sum "$C0_UINT48_DEFINITION/compiled.bin" | awk '{print $1}') == "$expected_compiled_bin" ]] || exit 65

mkdir -p "$C0_UINT48_OUTPUT_ROOT"
sha256sum "$claim" > "$C0_UINT48_OUTPUT_ROOT/package-sha256.txt"
sha256sum "$manifest" > "$C0_UINT48_OUTPUT_ROOT/manifest-sha256.txt"
date -Is > "$C0_UINT48_OUTPUT_ROOT/started-at.txt"
started=$(date +%s)
native_root=$(mktemp -d /tmp/erc-trust-c0-uint48-support-XXXXXX)
mkdir -p "$native_root/definition" "$native_root/save" "$native_root/temp"
cp "$claim" "$native_root/package.k"
cp -a "$C0_UINT48_DEFINITION/." "$native_root/definition/"
(
  sha256sum "$native_root/package.k"
  find "$native_root/definition" -type f -print0 | sort -z | xargs -0 sha256sum
) > "$C0_UINT48_OUTPUT_ROOT/native-input-sha256.txt"

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
  setsid "$kprove" "$native_root/package.k" --definition "$native_root/definition" --spec-module "$module" \
    --dry-run --emit-json-spec "$C0_UINT48_OUTPUT_ROOT/parsed-spec.json" --temp-dir "$native_root/temp" \
    > "$C0_UINT48_OUTPUT_ROOT/parse.log" 2>&1 &
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
  date -Is > "$C0_UINT48_OUTPUT_ROOT/ended-at.txt"
  printf '{"claimId":"c0-uint48-high-mask-is-not-self","supportVersion":%s,"parseOnly":true,"backendStarted":%s,"exitCode":%s,"wallSeconds":%s,"booster":false,"assumeDefined":false,"resumed":false,"credit":0}\n' \
    "$support_version" "$backend_started" "$exit_code" "$elapsed" > "$C0_UINT48_OUTPUT_ROOT/run-summary.json"
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
date -Is > "$C0_UINT48_OUTPUT_ROOT/ended-at.txt"
printf '{"claimId":"c0-uint48-high-mask-is-not-self","supportVersion":%s,"parseOnly":false,"exitCode":%s,"wallSeconds":%s,"timeoutSeconds":%s,"definitionKoreSha256":"%s","booster":false,"assumeDefined":false,"workers":1,"forceSequential":true,"breakEveryStep":true,"resumed":false,"credit":0}\n' \
  "$support_version" "$exit_code" "$elapsed" "$timeout_seconds" "$expected_definition" > "$C0_UINT48_OUTPUT_ROOT/run-summary.json"
cat "$C0_UINT48_OUTPUT_ROOT/run-summary.json"
exit "$exit_code"
