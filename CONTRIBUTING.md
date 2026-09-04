# Contributing to ERC-TRUST

ERC-TRUST is a pre-standard research and reference candidate. Contributions
that improve technical correctness, interoperability, verification,
reproducibility, and clarity are welcome. Submission does not guarantee
acceptance or a response within a particular period.

Read the [Code of Conduct](CODE_OF_CONDUCT.md), [Security
policy](SECURITY.md), and [Governance](GOVERNANCE.md) before contributing.

## Choose the right channel

| Contribution | Channel |
| --- | --- |
| Reproducible implementation defect | Bug issue form |
| Specification, conformance, or evidence challenge | Specification issue form |
| Documentation defect | Documentation issue form |
| Potential vulnerability | Private path in `SECURITY.md`, never a public issue |
| Usage or integration question | `SUPPORT.md` |
| Large interface or architecture proposal | Issue-first design discussion |

Search open and closed issues before creating a new one. Keep reports narrowly
scoped and include the exact commit and reproduction.

## Discuss first

Open an issue before work that changes:

- public interfaces, events, errors, storage layout, or receipt schema;
- regulatory-action or reversal semantics;
- authorization, policy, epoch, nonce, validity, or replay behavior;
- ERC-7943 or ERC-3643 conformance;
- Foundry, Certora, Kontrol, KEVM, Isabelle, mutation, or deterministic-build
  assumptions;
- claim boundaries, evidence interpretation, or release metadata.

Early discussion avoids work that conflicts with frozen semantics or
verification boundaries. The maintainer may close proposals that duplicate
existing work, broaden the standard without demonstrated interoperability
value, or cannot be verified within the project boundary.

## Development setup

Use the versions pinned in
[`evidence/release-manifest.json`](evidence/release-manifest.json).

From the repository root:

```bash
forge fmt --check
forge build --sizes --skip TrustTokenC
FOUNDRY_FUZZ_RUNS=256 FOUNDRY_INVARIANT_RUNS=256 FOUNDRY_INVARIANT_DEPTH=500 forge test -vv
forge lint
```

Run the SDK lane:

```bash
corepack enable
corepack prepare pnpm@11.9.0 --activate
pnpm --dir sdk install --frozen-lockfile --ignore-scripts
pnpm --dir sdk test
```

Run the generated-artifact and repository checks after a clean Solidity build:

```bash
node scripts/generate-vectors.mjs
node scripts/generate-release-manifest.mjs
node scripts/verify-release.mjs --mode=full
node scripts/verify-links.mjs
node scripts/verify-public-surface.mjs
node scripts/verify-repository-health.mjs
node scripts/verify-current-profile-release.mjs
node scripts/verify-public-release-tree.mjs
```

The complete Windows current-profile replay is:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/replay-current-profile-release.ps1
```

On the GitHub-hosted `ubuntu-24.04` runner, the mandatory Continuous
Integration implementation and package jobs normally complete in about two
minutes. The Foundry lane uses 256 fuzz runs and 256 invariant runs at depth
500. A separate job downloads digest-pinned Isabelle2025-2 and ADS_Functor,
checks out the public commit-pinned formal foundation, verifies its recorded
fourteen-file succession, prepares the temporary compatibility session,
clean-builds `ERC_TRUST`, and audits the exported proof-trust report for zero oracle dependencies. Local
timing varies with CPU, disk, and solver availability; each replay reports the
exact gate that fails.

Two of these checks compare regenerated files against the committed ones, so
when your change touches a protected release input, commit the regenerated
outputs of the kernel generator (`spec/generated/`, `sdk/src/kernel-v2.ts`,
`vectors/conformance-v2.json`, `schemas/receipt.schema.json`), the runtime bridge, the obligation ledger
renderings, and `evidence/release-manifest.json` in the same pull request; otherwise the determinism checks fail with a diff showing
exactly what moved. Protected inputs include implementation and verification
source, replay evidence, schemas, vectors, toolchain locks, SDK source and
dependency locks, and release scripts. Ordinary documentation, community
files, and workflow metadata remain subject to the public-surface and
repository-health checks but do not change the release-input root.

Pull Requests run `verify-release.mjs --mode=pr` over the protected inputs and
built runtime. Main and candidate-release workflows run `--mode=full`, which
also checks the protected source-tree root. A dependency bot change to a
protected lock file therefore needs a maintainer regeneration commit before
merge; the bot branch is not granted a manifest bypass.

The repository scanners also refuse project-internal lifecycle identifiers
(milestone identifiers of the shape `M<n>`, `G<n>`, or `FV<n>`) in tracked
text and file names, and report the exact file, line, and token when they
match. Note that this pattern currently collides with common legitimate
terms, most notably the standard one-letter-one-digit short names of the
two BLS12-381 pairing source groups and of Apple silicon chips: if your
change needs such a term, say so in the pull request so the scanner can
learn the exception explicitly rather than rewording the mathematics.

Three further mechanical rules are enforced by the release-tree check and
are easy to trip without knowing them:

- Markdown files must not contain em or en dashes; the check fails with
  `dash punctuation: <path>`. Use a comma, a colon, or parentheses.
- Adding or removing any tracked file changes the retained-path count, and
  the count is pinned: update `retainedFiles` in
  `evidence/public-release/diet-manifest-v2.json` in the same pull request,
  or the check fails with `retained path count drift`.
- The README badge row is pinned to its exact badge count for the same
  reason; changing the badges means updating the pin in
  `scripts/verify-public-release-tree.mjs` alongside.

The proof lane (`Proofs`) is a required check, but it does not tax ordinary
changes: a gate job compares the pull request against its base and the long
Isabelle build runs only when a proof input changed (`formal/`, the
foundation-supersession checker or its pinned record, or the proof workflow
itself). Every other pull request gets a fast positive "no proof input
changed" result in about a minute.

Changes to Certora Verification Language rules or K assertions must identify:

1. the property that changes;
2. why the prior property was insufficient;
3. the positive evidence that passes;
4. a negative mutation or counterexample that detects regression.

The candidate 2 Certora entrypoints are preserved as history under
`evidence/candidate-2/implementation/certora/` (`TrustToken.conf` and
`TrustToken.inventory.conf`); the successor has no Certora lane yet. The KEVM
harness is `implementation/kontrol/TrustTokenKontrolTest.t.sol`.

## Pull Request requirements

A Pull Request should:

- solve one reviewable problem;
- link the issue for non-trivial work;
- explain public claim and compatibility impact;
- add or update tests before changing behavior;
- update architecture, profile, integration, schema, vector, and evidence
  documents when affected;
- preserve exact toolchain and dependency pins unless the change is an
  intentional upgrade;
- include command results or links to Continuous Integration checks;
- contain no credentials, absolute local paths, caches, generated prover
  output, mutation workspace, or raw private logs;
- retain the mandatory unaudited and not-for-production warning where
  applicable.

Maintainers may request a smaller change, additional evidence, or a separate
proposal for normative work. Pull Requests are normally squash-merged after
required checks and review. The public `main` signing baseline starts with the
2026-09-01 launch commit. Earlier history may be unsigned; later `main` commits
must display a verified platform signature.

## Formal verification

The product-specific Isabelle/HOL source is owned by this repository under
`formal/isabelle/ERC_TRUST/`. A regulatory semantic change must update the
model, implementation mapping, claim boundary, and relevant implementation
evidence together.

Do not copy the external Cross-Domain State Preservation foundation into this
repository. `formal-dependencies.lock.json` is the immutable historical proof
closure record. A public foundation successor must be issued as a new lock,
currently `formal-dependencies-public-v1.lock.json`, only after the file map,
theory-source comparison, compatibility-session mutations, and
cross-repository Isabelle build have passed.

Keep authoritative formal sources, claim matrices, replay scripts, dependency
locks, curated final reports, and release manifests in Git. Do not commit:

- pre-mechanization sketches or scratch theories containing `sorry`;
- timestamped build and export directories;
- generated prover caches or mutation workspaces;
- raw console logs that duplicate a curated report;
- local absolute paths, credentials, or private workspace state.

Historical evidence must not be rewritten to appear current. Its hash,
candidate, and disposition belong in the dependency or provenance record.

## Contribution rights and license

Licensing follows the changed path:

- contributions to `docs/ERC-DRAFT.md` are dedicated under
  [CC0 1.0 Universal](docs/LICENSE-CC0.md);
- the four byte-bound historical pilot sources identified in the README retain
  their file-level [MIT license](README.md#mit-license-for-four-historical-pilot-source-files)
  and are not an open contribution surface;
- contributions to `CODE_OF_CONDUCT.md` remain under the Creative Commons
  Attribution 4.0 terms stated in that file, and license legal-code files are
  not an open contribution surface;
- contributions to the implementation, SDK, tooling, project assets, and all
  other first-party repository content without a file-level exception are
  licensed under the repository's
  [BSD 3-Clause License](LICENSE).

By submitting a contribution, you represent that:

- you have the right to submit it;
- it does not knowingly include confidential information or code copied under
  incompatible terms;
- you agree to provide the contribution under the license or waiver that
  applies to the changed path above.

Meaningful contributions may be credited through Git history, release notes,
or a security advisory. Please state a preferred credit name if it differs
from your GitHub identity.

No contribution creates employment, agency, partnership, support, or
acceptance obligations.
