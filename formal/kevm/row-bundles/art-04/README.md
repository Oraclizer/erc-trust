# ART-04 row-local proof-input skeleton

This directory prepares, but does not discharge, the canonical property
`storage_layout_abi_ast_and_immutable_references_are_hash_bound`.

The positive full-transaction claim calls canonical `totalSupply()` selector
`0x18160ddd` against the exact constructor-resolved TrustToken runtime. Storage
slot 2 contains `42`, while adjacent slot 3 contains `99`; the claim requires
the ABI word for `42`. The executable negative definition changes only runtime
byte 8340, the PUSH1 immediate feeding this getter's SLOAD, from slot 2 to slot
3. The selector and return path stay unchanged, and the mutant therefore returns
`99` against the unchanged `42` requirement.

The generated bridge independently binds the complete ABI, storage layout,
TrustStorage AST, and immutable-reference maps from the pinned Standard JSON
output. `e4fc...` is recorded only as the canonical OPEN placeholder; the row
uses actual current lock `3134...`, classified
`OPEN_PLACEHOLDER_PENDING_COORDINATOR_BINDING`, with no product-drift or proof
blocker claim.

All proof IDs, definition hashes, graph facts, Isabelle results, and replay
facts remain null or `NOT_RUN`. `bundle.json` is reserved for the coordinator
after fresh authoritative closure.

```powershell
node formal/kevm/row-bundles/art-04/generate-row-artifacts.mjs
python3 formal/kevm/row-bundles/art-04/reverse-check.py
```

These static commands do not run KEVM, a K dry-run, Isabelle, or solc.

