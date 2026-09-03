# Decision 11: how the runtime identity of the successor endpoints is bound to its evidence

Status: implemented for the native token, the ERC-3643 profile adapter, and the profile
governor. This decision closes the runtime assurance of the successor code short of the
Certora lanes, which stay pending until source may be sent to the cloud prover.

## Decision

1. The deterministic build receipt (`evidence/deterministic-build.json`, schema
   `erc-trust-deterministic-build-v3`) records two isolated clean builds of all three
   runtimes. The native fields keep their version 2 shape; `subjects.native`,
   `subjects.erc3643Adapter`, and `subjects.profileGovernor` carry the artifact, creation,
   and runtime identities of each contract. The receipt passes only when the two builds
   agree byte for byte on every subject.
2. The release manifest binds the three runtimes: `trustToken` as before, and
   `profileRuntimes.erc3643Adapter` and `profileRuntimes.profileGovernor` with their creation
   and runtime hashes and sizes. `scripts/verify-release.mjs` recomputes all three from the
   artifacts and cross-checks them against the deterministic build receipt.
3. The runtime binding is two layers. Layer 1 is the template identity of the Foundry
   artifacts, bound to the generated runtime bridge, the release manifest, and the
   deterministic build receipt. Layer 2 is a pinned-compiler replay: the exact import closure
   of each subject is compiled again with the pinned solc binary through the standard JSON
   interface with the settings of `foundry.toml`, and the six semantic projections of the
   output (ABI, storage layout without AST node identifiers, creation bytecode, runtime
   template, method identifiers, immutable references) must equal the artifact.
   `scripts/generate-runtime-binding-v3.mjs` writes `evidence/runtime-binding-v3.json` and the
   exact compiler inputs under `evidence/runtime-binding-v3/`; `scripts/verify-runtime-binding-v3.mjs`
   rejects a receipt whose source root, stored inputs, or hashes differ from the tree, rejects
   every other successor receipt that binds a different source root or runtime template
   (stale evidence), proves that its own classifier kills one deliberate mutant per semantic
   class and subject, and with `--replay` recompiles and compares again. Continuous
   integration runs both.
4. An independent implementer who read only the kernel machine source, the generated
   prose and ABI, and the conformance vectors wrote `scripts/independent-reproduction-v3.mjs`;
   it reproduces every identifier, hash, calldata, and receipt hash of the vectors and records
   `evidence/independent-reproduction-v3.json`. Continuous integration reruns it against the
   committed vectors and requires the committed receipt to match. The implementer's report
   of specification ambiguities is an input to the documentation change.
5. The evidence mode stays `successor-development`. The lanes `certora` and `certoraInputs`
   are pending because no source has been sent to the cloud prover, which is a separate
   approval; every other lane is a receipt of the current identity. Release mode requires
   zero pending lanes and is therefore not switched in this change.

## Consequences

- Any change to `implementation/**` or `foundry.toml` invalidates the deterministic build,
  runtime binding, Foundry, mutation, Kontrol, and Certora receipts together, and the
  verifiers report the stale ones instead of accepting them.
- The generated prose of the kernel renders string-valued shape rule entries as text; the
  earlier rendering listed them character by character.
- The claim matrix carries a successor section that names, for each allowed claim, the
  receipt that backs it and the qualifier it must carry.
