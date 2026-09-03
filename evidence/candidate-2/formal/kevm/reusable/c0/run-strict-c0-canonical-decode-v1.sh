#!/usr/bin/env bash
set -euo pipefail

: "${M4_PACKAGE:?set M4_PACKAGE}"
: "${M4_DEFINITION:?set M4_DEFINITION}"
: "${M4_OUTPUT_ROOT:?set M4_OUTPUT_ROOT to an absent directory}"
: "${M4_TIMEOUT_SECONDS:?set an explicit positive timeout}"

readonly expected_module=TRUST-C0-CANONICAL-DECODE-CUTPOINT-CLAIM
readonly expected_package=e9d9a9ad517c2bd26bec093cac43271a3fd9403c21fb4254ce2abc2445f2f018
readonly expected_definition=e3b3a2bf3574c4283d69ed0a68e0667d5be37c978c23cd28cc68cf3caff35c7b
readonly expected_compiled_json=9070d97d99597b9d43d24bee8d008d0897b27914e50d27b041b455200c1010a1
readonly expected_compiled_bin=e881e3bd88816d095b29e7abd24cf7afb5bf78e24570986fc682564903309e78
readonly expected_lock=3134e7692086170f86b6dd42e7ebd0256c188da8db8cbd17241c3d2c8d315196
readonly kore_rpc=/nix/store/wij5nr1s0q3ksvyng4lcybhy467bn9gh-kore-rpc/bin/kore-rpc

[[ $M4_TIMEOUT_SECONDS =~ ^[1-9][0-9]*$ ]] || { echo "M4_TIMEOUT_SECONDS must be a positive integer" >&2; exit 64; }
[[ ! -e $M4_OUTPUT_ROOT ]] || { echo "output root exists: $M4_OUTPUT_ROOT" >&2; exit 64; }
for path in "$M4_PACKAGE" "$M4_DEFINITION/definition.kore" "$M4_DEFINITION/compiled.json" "$M4_DEFINITION/compiled.bin" "$kore_rpc"; do
  [[ -f $path ]] || { echo "missing exact input: $path" >&2; exit 66; }
done
command -v kevm >/dev/null || { echo "kevm missing" >&2; exit 69; }

repository_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd -P)
[[ $(sha256sum "$repository_root/formal/kevm/dependencies.lock.json" | awk '{print $1}') == "$expected_lock" ]] || { echo "legacy lock drift" >&2; exit 65; }
[[ $(sha256sum "$M4_PACKAGE" | awk '{print $1}') == "$expected_package" ]] || { echo "C0 claim drift" >&2; exit 65; }
[[ $(sha256sum "$M4_DEFINITION/definition.kore" | awk '{print $1}') == "$expected_definition" ]] || { echo "C0 definition.kore drift" >&2; exit 65; }
[[ $(sha256sum "$M4_DEFINITION/compiled.json" | awk '{print $1}') == "$expected_compiled_json" ]] || { echo "C0 compiled.json drift" >&2; exit 65; }
[[ $(sha256sum "$M4_DEFINITION/compiled.bin" | awk '{print $1}') == "$expected_compiled_bin" ]] || { echo "C0 compiled.bin drift" >&2; exit 65; }

mkdir -p "$M4_OUTPUT_ROOT"
sha256sum "$M4_PACKAGE" > "$M4_OUTPUT_ROOT/package-sha256.txt"
printf '%s\n' "$expected_module" > "$M4_OUTPUT_ROOT/spec-module.txt"
date -Is > "$M4_OUTPUT_ROOT/started-at.txt"
started=$(date +%s)

native_root=$(mktemp -d /tmp/erc-trust-m4-c0-canonical-strict-XXXXXX)
mkdir -p "$native_root/definition" "$native_root/save" "$native_root/temp"
cp "$M4_PACKAGE" "$native_root/package.k"
cp -a "$M4_DEFINITION/." "$native_root/definition/"
sha256sum "$native_root/package.k" "$native_root/definition"/* > "$M4_OUTPUT_ROOT/native-input-sha256.txt"

proof_pid=
cleanup() {
  if [[ -n ${proof_pid:-} ]] && kill -0 "$proof_pid" 2>/dev/null; then
    kill -- "-$proof_pid" 2>/dev/null || true
    sleep 2
    kill -KILL -- "-$proof_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

set +e
setsid timeout --signal=TERM --kill-after=30s "${M4_TIMEOUT_SECONDS}s" \
  kevm prove "$native_root/package.k" \
    --definition "$native_root/definition" \
    --spec-module "$expected_module" \
    --save-directory "$native_root/save" \
    --temp-directory "$native_root/temp" \
    --no-use-booster \
    --workers 1 \
    --force-sequential \
    --failure-information \
    --kore-rpc-command "$kore_rpc" \
    > "$M4_OUTPUT_ROOT/prove.log" 2>&1 &
proof_pid=$!
wait "$proof_pid"
exit_code=$?
set -e

proof_pgid=$proof_pid
proof_pid=
trap - EXIT INT TERM
remaining=$(ps -eo pid=,pgid=,args= | awk -v pg="$proof_pgid" '$2 == pg {print}')
[[ -z $remaining ]] || { echo "proof descendants remain: $remaining" >&2; exit 1; }

cp -a "$native_root/save" "$M4_OUTPUT_ROOT/save"
cp -a "$native_root/temp" "$M4_OUTPUT_ROOT/temp"
elapsed=$(( $(date +%s) - started ))
printf '%s\n' "$exit_code" > "$M4_OUTPUT_ROOT/exit-code.txt"
printf '%s\n' "$elapsed" > "$M4_OUTPUT_ROOT/wall-seconds.txt"
date -Is > "$M4_OUTPUT_ROOT/ended-at.txt"
printf '{"exitCode":%s,"wallSeconds":%s,"timeoutSeconds":%s,"booster":false,"assumeDefined":false,"workers":1,"forceSequential":true,"definitionProfile":"C0_PC3477_CANONICAL_DECODE_PRIORITY1_V1"}\n' \
  "$exit_code" "$elapsed" "$M4_TIMEOUT_SECONDS" > "$M4_OUTPUT_ROOT/run-summary.json"
cat "$M4_OUTPUT_ROOT/run-summary.json"
exit "$exit_code"

