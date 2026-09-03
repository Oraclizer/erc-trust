# ART-03 row-local proof-input skeleton

This directory prepares, but does not discharge, the canonical obligation
`constructor_resolved_local_runtime_is_hash_bound`.

The positive claim calls `TrustToken.decimals()` on the exact pinned
constructor-resolved runtime and requires the ABI word for `18`.  The negative
definition changes only byte 7001, the last byte of immutable AST declaration
622 at runtime range `[6970, 7002)`, from `0x12` to `0x13`.  The selector and
control-flow path remain unchanged, so the unchanged claim must distinguish
constructor resolution rather than a generic dispatcher behavior.

`bundle.skeleton.json` and `runner-descriptor.skeleton.json` deliberately keep
all proof identities, compiled-definition hashes, graph facts, replay facts,
and Isabelle build facts null or `NOT_RUN`.  `bundle.json` is reserved for a
coordinator after fresh positive/negative KEVM runs and a serial clean Isabelle
build have produced the exact facts required by the shared row-bundle schema.

The canonical index's `e4fc...` TCB value is the standard unbound placeholder
for an OPEN row, not product drift and not an extra proof blocker.  This row is
classified `OPEN_PLACEHOLDER_PENDING_COORDINATOR_BINDING` and statically binds
the actual current lock (`3134...`), which is also the dependency-lock identity
inside the current runtime-binding manifest.  The coordinator's discharge
binder replaces the index placeholder when and only when the row is discharged;
this row-local preparation does not edit the shared index.

Static materialization and reverse checking:

```powershell
node formal/kevm/row-bundles/art-03/generate-row-artifacts.mjs
python3 formal/kevm/row-bundles/art-03/reverse-check.py
```

Neither command runs KEVM or Isabelle.

After coordinator application, the next authoritative sequence is recorded in
`runner-descriptor.skeleton.json`: compile fresh canonical and mutant Haskell
definitions, run the row-local clean Isabelle closure script, fill a new
schema-valid `bundle.json` only from those observed facts, and invoke the shared
`run-row-bundle.sh` with one worker, Booster disabled, and fresh output paths.

