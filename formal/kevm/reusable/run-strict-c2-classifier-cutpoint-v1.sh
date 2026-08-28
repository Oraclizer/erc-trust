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
[[ $(sha256sum "$repository_root/formal/kevm/dependencies.lock.json" | awk '{print $1}') == 3134e7692086170f86b6dd42e7ebd0256c188da8db8cbd17241c3d2c8d315196 ]] || { echo "legacy lock drift" >&2; exit 65; }
[[ $(sha256sum "$M4_DEFINITION/definition.kore" | awk '{print $1}') == e45f40606a32a4dbaa7d2fd74d46b189fbc9579858c986c5b855b3f513f32807 ]] || { echo "classifier definition drift" >&2; exit 65; }
[[ $(sha256sum "$M4_DEFINITION/compiled.json" | awk '{print $1}') == 1ec8d4d842249434a0954618cbc49c185a609c3a80652dfb7ed7e3726f535d35 ]] || { echo "classifier compiled json drift" >&2; exit 65; }
[[ $(sha256sum "$M4_DEFINITION/compiled.bin" | awk '{print $1}') == 27b0b6aff3c93e431c97bc6550fe0324b112b513b1fd15adc2a9945045ce2567 ]] || { echo "classifier compiled binary drift" >&2; exit 65; }
mkdir -p "$M4_OUTPUT_ROOT"
sha256sum "$M4_PACKAGE" > "$M4_OUTPUT_ROOT/package-sha256.txt"
printf '%s\n' "$M4_MODULE" > "$M4_OUTPUT_ROOT/spec-module.txt"
date -Is > "$M4_OUTPUT_ROOT/started-at.txt"
started=$(date +%s)
kore_rpc=/nix/store/wij5nr1s0q3ksvyng4lcybhy467bn9gh-kore-rpc/bin/kore-rpc
[[ -x $kore_rpc ]] || { echo "strict kore-rpc missing" >&2; exit 66; }
native_root=$(mktemp -d /tmp/erc-trust-m4-c2-classifier-strict-XXXXXX)
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
printf '{"exitCode":%s,"wallSeconds":%s,"booster":false,"assumeDefined":false,"workers":1,"forceSequential":true,"definitionProfile":"C2_PC22155_IDENTITY_CUTPOINT_PRIORITY1_V1"}\n' "$exit_code" "$elapsed" > "$M4_OUTPUT_ROOT/run-summary.json"
cat "$M4_OUTPUT_ROOT/run-summary.json"
exit "$exit_code"
