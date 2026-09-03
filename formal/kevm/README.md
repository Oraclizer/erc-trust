# KEVM inputs for the kernel version 2 runtimes

This directory holds the concrete-runtime inputs of the ERC-TRUST refinement chain for the
successor code under `implementation/`. It contains no claim specifications and reports no
completed KEVM program.

Contents:

| Path | What it is |
| --- | --- |
| `generated/trust-runtime-bridge.k` | The runtime templates of the native token, the ERC-3643 profile adapter, and the profile governor as K byte-stack macros, regenerated from the compiled artifacts by `scripts/generate-runtime-bridge-v2.mjs`; the same generation writes `formal/isabelle/ERC_TRUST/TRUST_Runtime_Bridge_Generated.thy` and the JSON schema under `evidence/end-to-end-refinement/runtime-bridge-v2/` |
| `compile-spec-definition.sh` | Compiles a claim specification against the pinned KEVM semantics named in the lock |
| `dependencies.lock.json` | The KEVM semantics source, compiled definition, K, Kore, Booster, Z3, compiler, and host identities; no dependency source is vendored |

The intended composition is unchanged:

```text
abstract TRUST transition
  -> concrete TRUST configuration through the Isabelle retrieve relation
  -> exact pinned CANCUN EVM runtime execution through KEVM reachability
```

What exists today for the successor runtimes is the first arrow (the Isabelle session
`ERC_TRUST`) and the obligation ledger that connects its conditions to the source
(`evidence/end-to-end-refinement/obligation-ledger-v3.json`, decision 10). The second arrow is
the locale assumption `pinned_runtime_refinement.runtime_link` in
`TRUST_End_To_End_Composition.thy`; it is not discharged. The four bounded Kontrol proofs
under `implementation/kontrol/` are instances of it on the native runtime; their receipt is
`evidence/kontrol-results-v3.json`, written by `scripts/record-kontrol-results-v3.mjs` from
the committed tree and absent while the kontrol lane is pending in the successor index. They
are not the KEVM program.

The candidate 2 KEVM claim specifications, row bundles, reusable claims, runner scripts, and
generated bridges were bound to the candidate 2 runtime template and the version 1 kernel.
They are preserved byte for byte under `evidence/candidate-2/formal/kevm/` and are not inputs
for the successor.

Regenerate and check the bridge from the repository root after `forge build`:

```bash
node scripts/generate-runtime-bridge-v2.mjs
node scripts/generate-runtime-bridge-v2.mjs --check
```
