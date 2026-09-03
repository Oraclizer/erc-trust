#!/usr/bin/env bash
set -euo pipefail

: "${M4_PACKAGE:?set M4_PACKAGE}"
: "${M4_DEFINITION:?set M4_DEFINITION}"
: "${M4_OUTPUT_ROOT:?set M4_OUTPUT_ROOT to an absent directory}"

readonly expected_module=TRUST-C0-CANONICAL-DECODE-CUTPOINT-CLAIM
readonly expected_package=e9d9a9ad517c2bd26bec093cac43271a3fd9403c21fb4254ce2abc2445f2f018
readonly expected_definition=e3b3a2bf3574c4283d69ed0a68e0667d5be37c978c23cd28cc68cf3caff35c7b
readonly expected_compiled_json=9070d97d99597b9d43d24bee8d008d0897b27914e50d27b041b455200c1010a1
readonly expected_compiled_bin=e881e3bd88816d095b29e7abd24cf7afb5bf78e24570986fc682564903309e78
readonly expected_lock=3134e7692086170f86b6dd42e7ebd0256c188da8db8cbd17241c3d2c8d315196
readonly kprove=/nix/store/y63xkr8pk2bqd5lh4889rlwldw26v9f4-k-7.1.337-4a46d1231473b599c699160132fd6e76a5c46406/bin/kprove

[[ ! -e $M4_OUTPUT_ROOT ]] || { echo "output root exists: $M4_OUTPUT_ROOT" >&2; exit 64; }
for path in "$M4_PACKAGE" "$M4_DEFINITION/definition.kore" "$M4_DEFINITION/compiled.json" "$M4_DEFINITION/compiled.bin" "$kprove"; do
  [[ -f $path ]] || { echo "missing exact input: $path" >&2; exit 66; }
done

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

native_root=$(mktemp -d /tmp/erc-trust-m4-c0-canonical-parse-XXXXXX)
mkdir -p "$native_root/definition" "$native_root/temp"
cp "$M4_PACKAGE" "$native_root/package.k"
cp -a "$M4_DEFINITION/." "$native_root/definition/"
sha256sum "$native_root/package.k" "$native_root/definition"/* > "$M4_OUTPUT_ROOT/native-input-sha256.txt"

parse_pid=
cleanup() {
  if [[ -n ${parse_pid:-} ]] && kill -0 "$parse_pid" 2>/dev/null; then
    kill -- "-$parse_pid" 2>/dev/null || true
    sleep 2
    kill -KILL -- "-$parse_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

set +e
setsid "$kprove" "$native_root/package.k" \
  --definition "$native_root/definition" \
  --spec-module "$expected_module" \
  --dry-run \
  --emit-json-spec "$M4_OUTPUT_ROOT/parsed-spec.json" \
  --temp-dir "$native_root/temp" \
  > "$M4_OUTPUT_ROOT/parse.log" 2>&1 &
parse_pid=$!
wait "$parse_pid"
exit_code=$?
set -e

parse_pgid=$parse_pid
parse_pid=
trap - EXIT INT TERM
remaining=$(ps -eo pid=,pgid=,args= | awk -v pg="$parse_pgid" '$2 == pg {print}')
[[ -z $remaining ]] || { echo "parse descendants remain: $remaining" >&2; exit 1; }

cp -a "$native_root/temp" "$M4_OUTPUT_ROOT/temp"
elapsed=$(( $(date +%s) - started ))
backend_started=false
if grep -Eq 'Starting KoreServer|kore-rpc.*started|Proof started' "$M4_OUTPUT_ROOT/parse.log"; then backend_started=true; fi
printf '%s\n' "$exit_code" > "$M4_OUTPUT_ROOT/exit-code.txt"
printf '%s\n' "$elapsed" > "$M4_OUTPUT_ROOT/wall-seconds.txt"
date -Is > "$M4_OUTPUT_ROOT/ended-at.txt"
printf '{"exitCode":%s,"wallSeconds":%s,"dryRun":true,"backendStarted":%s,"proofCredit":false,"definitionProfile":"C0_PC3477_CANONICAL_DECODE_PRIORITY1_V1"}\n' \
  "$exit_code" "$elapsed" "$backend_started" > "$M4_OUTPUT_ROOT/run-summary.json"
cat "$M4_OUTPUT_ROOT/run-summary.json"

[[ $exit_code -eq 0 ]] || exit "$exit_code"
[[ $backend_started == false ]] || { echo "dry-run unexpectedly started proof backend" >&2; exit 70; }

