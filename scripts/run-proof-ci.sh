#!/usr/bin/env bash
set -euo pipefail

isabelle="$RUNNER_TEMP/Isabelle2025-2/bin/isabelle"
afp="$RUNNER_TEMP/afp/ADS_Functor"
foundation="$RUNNER_TEMP/formal-foundation-overlay"
options=(-b -v -o record_proofs=1)
if [ "$CLEAN_REPLAY" = true ]; then
  options+=(-c)
elif [ "$CLEAN_REPLAY" != false ]; then
  echo "Invalid clean replay decision" >&2
  exit 1
fi
node scripts/proof-ci.mjs scan formal/isabelle "$foundation"
# -D selects the entire ROOTS catalog; Isabelle checks source digests, session
# options, successful database state and transitive input/output heap identity.
"$isabelle" build "${options[@]}" -d "$afp" -d "$foundation" -D formal/isabelle
# A fresh export destination makes absence or a stale report a failure.
export_root="$(mktemp -d "$RUNNER_TEMP/isabelle-export.XXXXXX")"
"$isabelle" export -d "$afp" -d "$foundation" -d formal/isabelle \
  -x '*:erc-trust/model-proof-trust.txt' -O "$export_root" ERC_TRUST
"$isabelle" export -d "$afp" -d "$foundation" -d formal/isabelle \
  -x '*:erc-trust/trust12-obstruction-proof-trust.txt' -O "$export_root" TRUST12_Accounting_Obstruction
node scripts/proof-ci.mjs audit "$export_root"
