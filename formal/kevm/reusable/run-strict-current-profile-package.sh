#!/usr/bin/env bash
set -euo pipefail

: "${M4_PACKAGE:?set M4_PACKAGE}"
: "${M4_MODULE:?set M4_MODULE}"
: "${M4_DEFINITION:?set M4_DEFINITION}"
: "${M4_OUTPUT_ROOT:?set M4_OUTPUT_ROOT to an absent directory}"
timeout_seconds=${M4_TIMEOUT_SECONDS:-900}
break_every_step=${M4_BREAK_EVERY_STEP:-false}
resume_root=${M4_RESUME_ROOT:-}
definition_profile=${M4_DEFINITION_PROFILE:-canonical}
[[ $break_every_step == true || $break_every_step == false ]] || { echo "M4_BREAK_EVERY_STEP must be true or false" >&2; exit 64; }
[[ $definition_profile == canonical || $definition_profile == c0-d1-d3-mutant ]] || { echo "unsupported M4_DEFINITION_PROFILE" >&2; exit 64; }
if [[ -n $resume_root ]]; then
  [[ -d $resume_root/save ]] || { echo "resume save directory missing: $resume_root/save" >&2; exit 66; }
  [[ -f $resume_root/package-sha256.txt ]] || { echo "resume package receipt missing" >&2; exit 66; }
  [[ $(awk '{print $1}' "$resume_root/package-sha256.txt") == $(sha256sum "$M4_PACKAGE" | awk '{print $1}') ]] || { echo "resume package drift" >&2; exit 65; }
fi

[[ ! -e $M4_OUTPUT_ROOT ]] || { echo "output root exists: $M4_OUTPUT_ROOT" >&2; exit 64; }
for path in "$M4_PACKAGE" "$M4_DEFINITION/definition.kore" "$M4_DEFINITION/compiled.json" "$M4_DEFINITION/compiled.bin"; do
  [[ -f $path ]] || { echo "missing input: $path" >&2; exit 66; }
done
command -v kevm >/dev/null || { echo "kevm missing" >&2; exit 69; }
command -v python3 >/dev/null || { echo "python3 missing" >&2; exit 69; }

repository_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)
expected_lock=3134e7692086170f86b6dd42e7ebd0256c188da8db8cbd17241c3d2c8d315196
actual_lock=$(sha256sum "$repository_root/formal/kevm/dependencies.lock.json" | awk '{print $1}')
[[ $actual_lock == "$expected_lock" ]] || { echo "legacy lock drift" >&2; exit 65; }
if [[ $definition_profile == canonical ]]; then
  expected_definition=bac21e3e90990c4c060bf77ecfe161a70d18900c631dcea5a37343765e6b3e33
  expected_compiled=5ba6257f64024f7eff4ec99c569db9f9477fd5d2a625f44ed04e091fdf795a50
  expected_compiled_bin=6363c878ee8e9d4a1cd61b0c862e5feb8c6e485af518f64e654130f453f8350e
else
  expected_definition=8b5e2446d9a1a33457528fa3d09a4c53b77862c5c42fa647a08938095b9863f3
  expected_compiled=afae21d485867b69915beecbc4c835968b6bb5f3183ef6f9fb8e76d84798b382
  expected_compiled_bin=f5eaabb3d399b2f8db5cba8088cc3e4327d2c8ffa0182d4ea7bd2fd9f095fe38
fi
[[ $(sha256sum "$M4_DEFINITION/definition.kore" | awk '{print $1}') == "$expected_definition" ]] || { echo "definition drift" >&2; exit 65; }
[[ $(sha256sum "$M4_DEFINITION/compiled.json" | awk '{print $1}') == "$expected_compiled" ]] || { echo "compiled definition drift" >&2; exit 65; }
[[ $(sha256sum "$M4_DEFINITION/compiled.bin" | awk '{print $1}') == "$expected_compiled_bin" ]] || { echo "compiled binary drift" >&2; exit 65; }

mkdir -p "$M4_OUTPUT_ROOT"
sha256sum "$M4_PACKAGE" > "$M4_OUTPUT_ROOT/package-sha256.txt"
printf '%s\n' "$M4_MODULE" > "$M4_OUTPUT_ROOT/spec-module.txt"
date -Is > "$M4_OUTPUT_ROOT/started-at.txt"
started=$(date +%s)
kore_rpc=/nix/store/wij5nr1s0q3ksvyng4lcybhy467bn9gh-kore-rpc/bin/kore-rpc
[[ -x $kore_rpc ]] || { echo "strict kore-rpc missing" >&2; exit 66; }

# K's parser and proof graph are memory and I/O intensive on the Windows/WSL
# translation layer. Copy the already hash-checked inputs to native ext4 and
# copy the complete proof artifacts back to the caller-owned evidence root.
native_root=$(mktemp -d /tmp/erc-trust-m4-strict-XXXXXX)
mkdir -p "$native_root/definition" "$native_root/save" "$native_root/temp"
cp "$M4_PACKAGE" "$native_root/package.k"
cp -a "$M4_DEFINITION/." "$native_root/definition/"
if [[ -n $resume_root ]]; then
  cp -a "$resume_root/save/." "$native_root/save/"
  printf '%s\n' "$resume_root" > "$M4_OUTPUT_ROOT/resume-source.txt"
fi
sha256sum "$native_root/package.k" "$native_root/definition"/* \
  > "$M4_OUTPUT_ROOT/native-input-sha256.txt"

proof_pid=
extra_prove_args=()
[[ $break_every_step == true ]] && extra_prove_args+=(--break-every-step)
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
    "${extra_prove_args[@]}" \
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
resumed=false
[[ -n $resume_root ]] && resumed=true
printf '{"exitCode":%s,"wallSeconds":%s,"booster":false,"assumeDefined":false,"workers":1,"forceSequential":true,"breakEveryStep":%s,"resumed":%s,"definitionProfile":"%s"}\n' \
  "$exit_code" "$elapsed" "$break_every_step" "$resumed" "$definition_profile" > "$M4_OUTPUT_ROOT/run-summary.json"
cat "$M4_OUTPUT_ROOT/run-summary.json"
exit "$exit_code"
