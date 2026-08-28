# Exact-runtime refinement with KEVM

This directory is the concrete-runtime half of the ERC-TRUST refinement
chain. It is not a replacement for the Isabelle abstract semantics and it is
not a continuation of the three preserved bounded Kontrol checks.

The intended composition is:

```text
abstract TRUST transition
  -> concrete TRUST configuration through the Isabelle retrieve relation
  -> exact pinned CANCUN EVM runtime execution through KEVM reachability
```

The authoritative KEVM run starts at the runtime dispatcher with exact raw
calldata, account code, storage, caller, time, chain context, gas mode,
external accounts, returndata, and log state. It ends only at a success or
revert halt. Booster is disabled for the authoritative run. The installed
Booster closure remains identified because preserved bounded cross-checks may
use it.

`dependencies.lock.json` separates the KEVM semantics source from the stale
`kevm version` label and records the source, compiled definition, K, Kore,
Booster, Z3, compiler, and host identities. No dependency source is vendored
into this repository.

Completion requires all of the following:

- direct-runtime claims for all six actions and all three reversals;
- direct and custody paths where both exist;
- malformed calldata, rejection, dependency failure, malformed returndata,
  and downstream revert-to-stutter claims;
- exact storage frames, finite mapping-key nonalias premises, and idle
  auxiliary state;
- external-call and exact-use ticket assume/guarantee claims;
- complete committed event order and final receipt relation;
- a generated-and-reverse-verified bridge to the Isabelle configuration;
- obligation-index coverage, negative adequacy, and independent replay.

Until those artifacts exist and replay cleanly, this directory reports an
open proof program rather than end-to-end completion.

The first discharged row is `FAIL-05`. Its exact unknown-selector runtime
claim, typed-payload semantic mutant, named Isabelle theorem, checked selector
bridge, and independent replay report are indexed under
`evidence/end-to-end-refinement/`. This is one row of 79 and is not a program
completion claim.

The repository-owned replay entry point is:

```text
bash formal/kevm/run-runtime-claims.sh \
  --positive-definition <exact-positive-definition> \
  --negative-definition <exact-negative-definition> \
  --no-use-booster
```

The runner verifies the definition and source hashes before executing, imports
the already compiled runtime modules to avoid K absolute-source redeclaration,
checks the positive KCFG and expected-negative witness, and emits a sanitized
durable report without retaining temporary proof paths.

The initial ABI calldata campaign replay entry point is:

```text
bash formal/kevm/run-abi-calldata-claims.sh \
  --definition <exact-positive-definition> \
  --no-use-booster
```

Its current sanitized record is
`evidence/end-to-end-refinement/kevm/abi-calldata-initial-campaign.json`.
The selector-only ABI-04 action case passes, but the ABI-03 trailing-word case
is backend-blocked during SMT target subsumption. The report is bounded
campaign evidence only; it discharges neither ABI obligation.
