#!/usr/bin/env bash
set -euo pipefail

: "${M4_PACKAGE:?set M4_PACKAGE}"
: "${M4_MODULE:?set M4_MODULE}"
: "${M4_DEFINITION:?set M4_DEFINITION}"
: "${M4_OUTPUT_ROOT:?set M4_OUTPUT_ROOT to an absent directory}"
timeout_seconds=${M4_TIMEOUT_SECONDS:-900}

[[ ! -e $M4_OUTPUT_ROOT ]] || { echo "output root exists: $M4_OUTPUT_ROOT" >&2; exit 64; }
for path in "$M4_PACKAGE" "$M4_DEFINITION/definition.kore" "$M4_DEFINITION/compiled.json" "$M4_DEFINITION/compiled.bin"; do
  [[ -f $path ]] || { echo "missing input: $path" >&2; exit 66; }
done
command -v kevm >/dev/null || { echo "kevm missing" >&2; exit 69; }

repository_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)
expected_lock=3134e7692086170f86b6dd42e7ebd0256c188da8db8cbd17241c3d2c8d315196
[[ $(sha256sum "$repository_root/formal/kevm/dependencies.lock.json" | awk '{print $1}') == "$expected_lock" ]] || { echo "legacy lock drift" >&2; exit 65; }
expected_definition=3f1ad02f72dd096ef83e37dcf5ae519339b1d638ae787187133e814413922767
expected_compiled=cf1006dd544b40230447848b8659f9ec9b1ac85db0f287bacca924a661270247
expected_compiled_bin=f6604a2639297982f8832dd95fffb8dc6cb385eab202ff93fa270a9b4d407724
[[ $(sha256sum "$M4_DEFINITION/definition.kore" | awk '{print $1}') == "$expected_definition" ]] || { echo "cutpoint definition drift" >&2; exit 65; }
[[ $(sha256sum "$M4_DEFINITION/compiled.json" | awk '{print $1}') == "$expected_compiled" ]] || { echo "cutpoint compiled json drift" >&2; exit 65; }
[[ $(sha256sum "$M4_DEFINITION/compiled.bin" | awk '{print $1}') == "$expected_compiled_bin" ]] || { echo "cutpoint compiled binary drift" >&2; exit 65; }

mkdir -p "$M4_OUTPUT_ROOT"
sha256sum "$M4_PACKAGE" > "$M4_OUTPUT_ROOT/package-sha256.txt"
printf '%s\n' "$M4_MODULE" > "$M4_OUTPUT_ROOT/spec-module.txt"
date -Is > "$M4_OUTPUT_ROOT/started-at.txt"
started=$(date +%s)
kore_rpc=/nix/store/wij5nr1s0q3ksvyng4lcybhy467bn9gh-kore-rpc/bin/kore-rpc
[[ -x $kore_rpc ]] || { echo "strict kore-rpc missing" >&2; exit 66; }

native_root=$(mktemp -d /tmp/erc-trust-m4-c2-cutpoint-strict-XXXXXX)
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
setsid timeout --signal=TERM --kill-after=30s "${timeout_seconds}s" \
  kevm prove "$native_root/package.k" \
    --definition "$native_root/definition" \
    --spec-module "$M4_MODULE" \
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
printf '{"exitCode":%s,"wallSeconds":%s,"booster":false,"assumeDefined":false,"workers":1,"forceSequential":true,"definitionProfile":"C2_PC21900_IDENTITY_CUTPOINT_PRIORITY1_V1"}\n' \
  "$exit_code" "$elapsed" > "$M4_OUTPUT_ROOT/run-summary.json"
cat "$M4_OUTPUT_ROOT/run-summary.json"
exit "$exit_code"
