# Decision 11: how the runtime identity of the successor endpoints is bound to its evidence

Status: implemented for the native token, the ERC-3643 profile adapter, and the profile
governor. The current Certora receipt is recorded against the exact Partial adapter
runtime; the evidence mode remains `successor-development` and no release or deployment
claim follows.

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
5. The evidence mode stays `successor-development`. All twelve current lanes are PASS,
   including `certora` and `certoraInputs`: the receipt records four named rules with
   advanced sanity, the exact nine-file input root, provider run and toolchain provenance,
   terminal success, and the current Partial adapter runtime. Zero pending lanes does not
   itself authorize release mode, a tag, a deployment claim, or end-to-end refinement.

6. Two corrections of the normative prose were found by the independent reproduction and
   the review of this change and are applied here with the generator rerun: a missing
   `RECOVER` entitlement commitment is a field rule (reason 6) and reason 9 is reserved for a
   commitment already consumed, which is what the endpoints do; and the shape rules state
   their check order (common rules in the listed order, then the field rules; the earliest
   failing rule names the reason), which is why the `domain` row of the field-binding
   vectors reports reason 1. The independent program was aligned to the corrected text after
   its original run; both the original run (against the text before the correction) and the
   aligned run reproduce every vector.
7. The stale-evidence rejection of the runtime binding verifier covers the five receipts
   it enumerates (deterministic build, Foundry, mutation, Kontrol, Certora) when they are
   present and lists the absent ones; the lane index carries the source-root checks of the
   receipts that bind code identity. The stored compiler inputs under
   `evidence/runtime-binding-v3/` are the exact byte streams the replay pipes to the pinned
   compiler and the comparison targets of the offline check; they are kept because the
   replay is not reproducible without them.
8. Receipts bind byte roots, not commit ancestry. The trunk is reached by GitHub merges
   that rewrite commit identities (rebase for own pull requests, squash for external ones),
   so the commit a receipt names is never an ancestor of `main`. The lane verifier therefore
   compares the source root or formal root a receipt declares with the root it recomputes
   from the tree it runs on, and keeps the recorded commit as provenance that the recorder
   checked at record time. Ancestry checks were removed from the lane verifier before the
   integration branch reached `main`, and from the full mode of the release verifier
   (which the pull request mode had not exercised) right after.

## Consequences

- Any change to `implementation/**` or `foundry.toml` invalidates the deterministic build,
  runtime binding, Foundry, mutation, Kontrol, and Certora receipts together, and the
  verifiers report the stale ones instead of accepting them.
- The generated prose of the kernel renders string-valued shape rule entries as text; the
  earlier rendering listed them character by character.
- The claim matrix carries a successor section that names, for each allowed claim, the
  receipt that backs it and the qualifier it must carry.
