#!/usr/bin/env bash
# Diagnostic-only bounded canary for comparing ACT-01 proof topologies.
# It records RPC call start and response events through sitecustomize.py.
set -uo pipefail

: "${M4_OUTPUT_ROOT:?set M4_OUTPUT_ROOT to an absent directory}"
: "${M4_CLAIM:?set M4_CLAIM to the input claim}"
: "${M4_SPEC_MODULE:?set M4_SPEC_MODULE}"
: "${M4_DEFINITION:?set M4_DEFINITION}"
: "${M4_BOOSTER:?set M4_BOOSTER}"
: "${M4_HOOK_DIR:?set M4_HOOK_DIR to the sitecustomize.py directory}"

if [[ -e "$M4_OUTPUT_ROOT" ]]; then
  printf 'output root already exists: %s\n' "$M4_OUTPUT_ROOT" >&2
  exit 64
fi

timeout_seconds="${M4_TIMEOUT_SECONDS:-600}"
max_depth="${M4_MAX_DEPTH:-1}"
iteration_args=()
if [[ -n "${M4_MAX_ITERATIONS:-}" ]]; then
  iteration_args+=(--max-iterations "$M4_MAX_ITERATIONS")
fi
haskell_log_args=()
if [[ "${M4_CAPTURE_HASKELL_LOGS:-false}" == "true" ]]; then
  haskell_log_args+=(--haskell-log-dir "$M4_OUTPUT_ROOT/hlog")
fi
mkdir -p "$M4_OUTPUT_ROOT/save" "$M4_OUTPUT_ROOT/temp" "$M4_OUTPUT_ROOT/hlog"
if [[ "${M4_STRIP_LEADING_REQUIRES:-false}" == "true" ]]; then
  tail -n +2 "$M4_CLAIM" > "$M4_OUTPUT_ROOT/claim.k"
else
  cp "$M4_CLAIM" "$M4_OUTPUT_ROOT/claim.k"
fi
sha256sum "$M4_OUTPUT_ROOT/claim.k" > "$M4_OUTPUT_ROOT/claim-sha256.txt"
date -Is > "$M4_OUTPUT_ROOT/started-at.txt"

export PYTHONPATH="$M4_HOOK_DIR${PYTHONPATH:+:$PYTHONPATH}"
export M4_RPC_LIFECYCLE_LOG="$M4_OUTPUT_ROOT/rpc-lifecycle.jsonl"

printf 'elapsed_s\tserver_rss_kb\tserver_cpu_pct\tmem_available_mb\tnodes\tedges\n' \
  > "$M4_OUTPUT_ROOT/resource-curve.tsv"
start_epoch="$(date +%s)"

graph_counts() {
  local kcfg
  kcfg="$(find "$M4_OUTPUT_ROOT/save" -path '*/kcfg/kcfg.json' -type f -print -quit 2>/dev/null)"
  if [[ -z "$kcfg" ]]; then
    printf '0\t0'
    return
  fi
  python3 -c '
import json, sys
try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
    nodes = data.get("nodes")
    edges = data.get("edges")
    print(f"{len(nodes) if isinstance(nodes, list) else 0}\t{len(edges) if isinstance(edges, list) else 0}")
except Exception:
    print("0\t0")
' "$kcfg"
}

sample_resources() {
  while [[ ! -f "$M4_OUTPUT_ROOT/exit-code.txt" ]]; do
    local rss cpu available graph elapsed
    rss="$(ps -eo rss=,comm= | awk '$2 ~ /^\.?kore-rpc-boost/ {print $1; exit}')"
    cpu="$(ps -eo pcpu=,comm= | awk '$2 ~ /^\.?kore-rpc-boost/ {print $1; exit}')"
    available="$(free -m | awk 'NR == 2 {print $7}')"
    graph="$(graph_counts)"
    elapsed="$(( $(date +%s) - start_epoch ))"
    printf '%s\t%s\t%s\t%s\t%s\n' "$elapsed" "${rss:-0}" "${cpu:-0}" "${available:-0}" "$graph" \
      >> "$M4_OUTPUT_ROOT/resource-curve.tsv"
    sleep 10
  done
}

sample_resources &
sampler_pid="$!"

server_command="$M4_BOOSTER -l Aborts --log-timestamps --log-file $M4_OUTPUT_ROOT/booster.log"

set +e
timeout --foreground --signal=TERM --kill-after=15s "${timeout_seconds}s" \
  kevm prove "$M4_OUTPUT_ROOT/claim.k" \
    --definition "$M4_DEFINITION" \
    --spec-module "$M4_SPEC_MODULE" \
    --save-directory "$M4_OUTPUT_ROOT/save" \
    --temp-directory "$M4_OUTPUT_ROOT/temp" \
    "${haskell_log_args[@]}" \
    --use-booster \
    --fallback-on Branching,Stuck,Aborted \
    --assume-defined \
    --max-depth "$max_depth" \
    "${iteration_args[@]}" \
    --break-on-calls \
    --break-on-basic-blocks \
    --workers 1 \
    --force-sequential \
    --failure-information \
    --kore-rpc-command "$server_command" \
    > "$M4_OUTPUT_ROOT/prove.log" 2>&1
exit_code="$?"
set -e

printf '%s\n' "$exit_code" > "$M4_OUTPUT_ROOT/exit-code.txt"
date -Is > "$M4_OUTPUT_ROOT/ended-at.txt"
kill "$sampler_pid" 2>/dev/null || true
wait "$sampler_pid" 2>/dev/null || true

graph="$(graph_counts)"
request_starts="$(grep -c '"event": "client-pre-send"' "$M4_OUTPUT_ROOT/rpc-lifecycle.jsonl" 2>/dev/null || true)"
execute_starts="$(grep -c '"event": "client-pre-send".*"method": "execute"' "$M4_OUTPUT_ROOT/rpc-lifecycle.jsonl" 2>/dev/null || true)"
execute_ends="$(grep -c '"event": "client-response".*"method": "execute"' "$M4_OUTPUT_ROOT/rpc-lifecycle.jsonl" 2>/dev/null || true)"

{
  printf 'exit_code\t%s\n' "$exit_code"
  printf 'wall_seconds\t%s\n' "$(( $(date +%s) - start_epoch ))"
  printf 'request_starts\t%s\n' "${request_starts:-0}"
  printf 'execute_starts\t%s\n' "${execute_starts:-0}"
  printf 'execute_ends\t%s\n' "${execute_ends:-0}"
  printf 'nodes_edges\t%s\n' "$graph"
} > "$M4_OUTPUT_ROOT/summary.tsv"

cat "$M4_OUTPUT_ROOT/summary.tsv"
