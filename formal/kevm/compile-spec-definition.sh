#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "usage: $0 MAIN_FILE MAIN_MODULE SYNTAX_MODULE OUTPUT_DIRECTORY" >&2
  exit 64
fi

main_file=$1
main_module=$2
syntax_module=$3
output_directory=$4

k_root=/nix/store/y63xkr8pk2bqd5lh4889rlwldw26v9f4-k-7.1.337-4a46d1231473b599c699160132fd6e76a5c46406
kevm_python_root=/nix/store/cj49dhi36y3vzjfs8bjz5g9m7rk20p53-kevm-pyk-env/lib/python3.10/site-packages/kevm_pyk
evm_include=$kevm_python_root/kproj/evm-semantics
plugin_include=$kevm_python_root/kproj/plugin

for required_path in \
  "$k_root/bin/kompile" \
  "$evm_include/edsl.md" \
  "$plugin_include"
do
  if [[ ! -e $required_path ]]; then
    echo "missing pinned dependency: $required_path" >&2
    exit 66
  fi
done

exec "$k_root/bin/kompile" \
  "$main_file" \
  --main-module "$main_module" \
  --syntax-module "$syntax_module" \
  -I "$evm_include" \
  -I "$plugin_include" \
  --md-selector 'k & ! concrete' \
  --hook-namespaces 'JSON KRYPTO' \
  --emit-json \
  --backend haskell \
  --output-definition "$output_directory" \
  --type-inference-mode simplesub
