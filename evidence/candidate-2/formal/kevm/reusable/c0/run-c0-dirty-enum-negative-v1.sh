#!/usr/bin/env bash
set -euo pipefail

: "${M4_MODE:?set M4_MODE to parse or strict}"
: "${M4_PACKAGE:?set M4_PACKAGE}"
: "${M4_DEFINITION:?set M4_DEFINITION}"
: "${M4_OUTPUT_ROOT:?set M4_OUTPUT_ROOT to an absent directory}"

readonly expected_module=ABI04_NATIVE_REGULATORY_ACTION_ENUM_DIRTY_HIGH_BITS_SPEC
readonly expected_package=676cdd2e25c7beb017bcb22c8259adcdd623e010274f394bcf76aaca40fc7265
readonly expected_definition=bac21e3e90990c4c060bf77ecfe161a70d18900c631dcea5a37343765e6b3e33
readonly expected_compiled_json=5ba6257f64024f7eff4ec99c569db9f9477fd5d2a625f44ed04e091fdf795a50
readonly expected_compiled_bin=6363c878ee8e9d4a1cd61b0c862e5feb8c6e485af518f64e654130f453f8350e
readonly expected_lock=3134e7692086170f86b6dd42e7ebd0256c188da8db8cbd17241c3d2c8d315196
readonly kprove=/nix/store/y63xkr8pk2bqd5lh4889rlwldw26v9f4-k-7.1.337-4a46d1231473b599c699160132fd6e76a5c46406/bin/kprove
readonly kore_rpc=/nix/store/wij5nr1s0q3ksvyng4lcybhy467bn9gh-kore-rpc/bin/kore-rpc

[[ $M4_MODE == parse || $M4_MODE == strict ]] || { echo "M4_MODE must be parse or strict" >&2; exit 64; }
if [[ $M4_MODE == strict ]]; then
  : "${M4_TIMEOUT_SECONDS:?set an explicit positive timeout for strict mode}"
  [[ $M4_TIMEOUT_SECONDS =~ ^[1-9][0-9]*$ ]] || { echo "M4_TIMEOUT_SECONDS must be a positive integer" >&2; exit 64; }
fi
[[ ! -e $M4_OUTPUT_ROOT ]] || { echo "output root exists: $M4_OUTPUT_ROOT" >&2; exit 64; }
for path in "$M4_PACKAGE" "$M4_DEFINITION/definition.kore" "$M4_DEFINITION/compiled.json" "$M4_DEFINITION/compiled.bin" "$kprove"; do
  [[ -f $path ]] || { echo "missing exact input: $path" >&2; exit 66; }
done
if [[ $M4_MODE == strict ]]; then
  [[ -x $kore_rpc ]] || { echo "strict kore-rpc missing" >&2; exit 66; }
  command -v kevm >/dev/null || { echo "kevm missing" >&2; exit 69; }
fi

repository_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd -P)
[[ $(sha256sum "$repository_root/formal/kevm/dependencies.lock.json" | awk '{print $1}') == "$expected_lock" ]] || { echo "legacy lock drift" >&2; exit 65; }
[[ $(sha256sum "$M4_PACKAGE" | awk '{print $1}') == "$expected_package" ]] || { echo "C0 dirty-enum claim drift" >&2; exit 65; }
[[ $(sha256sum "$M4_DEFINITION/definition.kore" | awk '{print $1}') == "$expected_definition" ]] || { echo "legacy definition.kore drift" >&2; exit 65; }
[[ $(sha256sum "$M4_DEFINITION/compiled.json" | awk '{print $1}') == "$expected_compiled_json" ]] || { echo "legacy compiled.json drift" >&2; exit 65; }
[[ $(sha256sum "$M4_DEFINITION/compiled.bin" | awk '{print $1}') == "$expected_compiled_bin" ]] || { echo "legacy compiled.bin drift" >&2; exit 65; }

mkdir -p "$M4_OUTPUT_ROOT"
sha256sum "$M4_PACKAGE" > "$M4_OUTPUT_ROOT/package-sha256.txt"
printf '%s\n' "$expected_module" > "$M4_OUTPUT_ROOT/spec-module.txt"
printf '%s\n' "$M4_MODE" > "$M4_OUTPUT_ROOT/mode.txt"
date -Is > "$M4_OUTPUT_ROOT/started-at.txt"
started=$(date +%s)

native_root=$(mktemp -d "/tmp/erc-trust-m4-c0-dirty-enum-${M4_MODE}-XXXXXX")
mkdir -p "$native_root/definition" "$native_root/save" "$native_root/temp"
cp "$M4_PACKAGE" "$native_root/package.k"
cp -a "$M4_DEFINITION/." "$native_root/definition/"
sha256sum "$native_root/package.k" "$native_root/definition"/* > "$M4_OUTPUT_ROOT/native-input-sha256.txt"

worker_pid=
cleanup() {
  if [[ -n ${worker_pid:-} ]] && kill -0 "$worker_pid" 2>/dev/null; then
    kill -- "-$worker_pid" 2>/dev/null || true
    sleep 2
    kill -KILL -- "-$worker_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

set +e
if [[ $M4_MODE == parse ]]; then
  setsid "$kprove" "$native_root/package.k" \
    --definition "$native_root/definition" \
    --spec-module "$expected_module" \
    --dry-run \
    --emit-json-spec "$M4_OUTPUT_ROOT/parsed-spec.json" \
    --temp-dir "$native_root/temp" \
    > "$M4_OUTPUT_ROOT/parse.log" 2>&1 &
else
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
fi
worker_pid=$!
wait "$worker_pid"
exit_code=$?
set -e

worker_pgid=$worker_pid
worker_pid=
trap - EXIT INT TERM
remaining=$(ps -eo pid=,pgid=,args= | awk -v pg="$worker_pgid" '$2 == pg {print}')
[[ -z $remaining ]] || { echo "C0 negative descendants remain: $remaining" >&2; exit 1; }

cp -a "$native_root/temp" "$M4_OUTPUT_ROOT/temp"
if [[ $M4_MODE == strict ]]; then cp -a "$native_root/save" "$M4_OUTPUT_ROOT/save"; fi
elapsed=$(( $(date +%s) - started ))
printf '%s\n' "$exit_code" > "$M4_OUTPUT_ROOT/exit-code.txt"
printf '%s\n' "$elapsed" > "$M4_OUTPUT_ROOT/wall-seconds.txt"
date -Is > "$M4_OUTPUT_ROOT/ended-at.txt"

if [[ $M4_MODE == parse ]]; then
  backend_started=false
  if grep -Eq 'Starting KoreServer|kore-rpc.*started|Proof started' "$M4_OUTPUT_ROOT/parse.log"; then backend_started=true; fi
  printf '{"exitCode":%s,"wallSeconds":%s,"mode":"parse","dryRun":true,"backendStarted":%s,"proofCredit":false,"definitionProfile":"CURRENT_NATIVE_RUNTIME"}\n' \
    "$exit_code" "$elapsed" "$backend_started" > "$M4_OUTPUT_ROOT/run-summary.json"
  cat "$M4_OUTPUT_ROOT/run-summary.json"
  [[ $exit_code -eq 0 ]] || exit "$exit_code"
  [[ $backend_started == false ]] || { echo "dry-run unexpectedly started proof backend" >&2; exit 70; }
else
  printf '{"exitCode":%s,"wallSeconds":%s,"mode":"strict","timeoutSeconds":%s,"booster":false,"assumeDefined":false,"workers":1,"forceSequential":true,"definitionProfile":"CURRENT_NATIVE_RUNTIME"}\n' \
    "$exit_code" "$elapsed" "$M4_TIMEOUT_SECONDS" > "$M4_OUTPUT_ROOT/run-summary.json"
  cat "$M4_OUTPUT_ROOT/run-summary.json"
  exit "$exit_code"
fi
