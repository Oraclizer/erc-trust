# TRUST 1.2 development evidence

The implementation adds a fresh T-REX hook profile. This directory records development
evidence separately from the published kernel version 2 baseline. It does not declare
all TRUST 1.2 work complete or discharge the general runtime link.

## Implemented profile

The `ERC3643HookAdapter` constructor creates the token, a fixed-membership Identity
Registry, an immutable Compliance callback, and an inert token owner. It accepts no
existing token, governor, Agent list, or imported regulatory state. It reads the exact
upstream token creation bytes from an immutable code carrier and checks their hash.

The token's one Agent is the constructing endpoint. Initial minting and initialization
finish before the constructor returns. Every later balance callback synchronizes the
owned target to the actual balance. The stock token's ordinary transfer guard then
enforces that frozen amount, including between successive calls in one transaction.
Raw mint, burn, recovery, freeze and administration remain inaccessible to callers.
Membership and supply are fixed after construction in this reference profile.

`ERC3643HookFactory` admits only the pinned endpoint creation code and supplies the
constructor arguments itself. The code carrier avoids including the upstream initcode
again in each endpoint's constructor arguments. The factory checks the complete
initcode length, including the membership array.

## Separate evidence boundaries

- Native, legacy Partial adapter, and legacy governor source files and runtime templates
  are preserved byte for byte; `runtime-identity.json` independently recomputes the runtime comparison.
  The new endpoint owns an isolated copy of the adapter kernel so those historical source
  identities do not move. The same receipt compares every common function body and permits
  differences only in interface discovery, profile reporting and profile-specific binding.
- The original T-REX integration input is Tokeny 4.1.3 at
  `0fa344b761cf861bb9e8e1c8e472ba72815316c2`, compiled with solc 0.8.17.
  Its source/license and the OpenZeppelin 4.9.3 / ONCHAINID 2.1.0 dependencies are
  pinned by archive SHA-256 in the preparation script. Upstream GPL source is kept
  separately from the BSD implementation and is not relabelled.
- `ERC3643HookTrexIntegration.t.sol` executes that actual upstream bytecode.
  `ERC3643ProfileTrexFixture.t.sol` remains a distinct clean-room fixture.
- The model's self-transfer update and inactive custody amount were corrected.
  `TRUST_State_Invariants.thy` develops finite accounting invariants; its initial
  model state is not a proof of the deployed constructor's storage projection.
  The separate `TRUST12_Accounting_Obstruction` session proves that accounting
  consistency alone cannot establish preservation across every regulatory step.
- The symbolic Native harness admits every positive pair `second <= first`,
  including targets above supply. A Foundry fuzz pass is not a Kontrol proof receipt.
- General `runtime_link`, full forward/reversal invariant preservation, connected
  runtime histories, and fresh independent conformance/assurance remain separate
  obligations. Legacy evidence is not automatically credited to the new hook profile.
- `obligation-ledger.json` keeps functional conformance and runtime refinement separate.
  Its `CURRENT-MANDATORY` rows prevent the bounded results from becoming an end-to-end claim.

## Local replay

On Linux or WSL, with the repository's pinned Foundry and Python 3.12 or newer:

```sh
python3 scripts/prepare-trex-integration.py
forge build
python3 scripts/check-trust12-runtime-identity.py
forge test --match-contract ERC3643HookTrexIntegrationTest -vv
python3 scripts/check-hook-consumer-removal.py inbound
python3 scripts/check-hook-consumer-removal.py initial
python3 scripts/check-hook-consumer-removal.py receipt
```

The preparation script also compiles an explicitly modified upstream constructor with
an undeclared restricted account for the negative control. It does not replace the
original integration input. Mutation workspaces, downloaded dependencies and raw logs
are generated under `out/trust12/`; curated receipts stay in this directory.

The mutation runner rebinds the isolated factory's creation-code pin to the mutant
endpoint so that the detector reaches the intended semantic check. It reports this
adjustment explicitly. A compiler error, stale pin, or setup failure is not a killed
semantic mutation.

## Evidence-reuse checkpoint

`evidence-reuse.json` records the exact unchanged inputs of the historical Native
and Partial results. `scripts/verify-trust12-evidence-reuse.mjs` checks a baseline
inventory root independently reconstructed from 37 Git blobs, the unchanged
compiler settings, the two added Hook-only artifact reads, and the exhaustive
ownership of new implementation and proof inputs. The historical mutation,
Kontrol and Certora receipts keep their original execution identities.

`local-validation.json` and `deterministic-build-replay.json` preserve a fresh
local double build and all 102 Foundry tests at the first Hook checkpoint.
`evidence-reuse-controls.json` records 14 negative input and entrypoint controls.
Run `node scripts/test-trust12-evidence-reuse.mjs` to reproduce those controls.
They are not a rerun of the historical 121 implementation mutations.

## Required aggregate evidence

The three v3 aggregate entrypoints consume `verify-trust12-required.mjs`. It binds
legacy Native and Partial evidence, the exact previously audited Hook inputs, the
nine actual T-REX integration tests and six semantic mutations, the complete
Isabelle parent/child session graph, and the open TRUST 1.2 obligations. A passing
check means consistent development evidence; general runtime refinement remains
incomplete and release mode stays prohibited.

The Foundry recorder accepts `--local` with the original `local-validation.json`.
It checks raw log hashes and individual test outcomes against the recorded source
commit. `record-trust12-deterministic.mjs` promotes the existing double build while
retaining its execution commit and output. No CI run identifiers are invented.

`formal-build-replay.json` records a fresh local clean build and proof export of
both named sessions. The formal input identity includes theories, ROOT/ROOTS,
foundation locks and workflow, plus the exact foundation overlay and ADS input
inventory. The previous `formal-build.json` remains historical evidence.

Pinned-compiler replay now covers the three legacy runtime subjects and the four
Hook subjects. The Hook subjects bind their own feature identity receipt and
receive no legacy HOL bridge credit. Run `node scripts/test-trust12-required.mjs`
for the missing-input, altered-provenance, session-graph and release-promotion
controls. These controls are separate from implementation mutation campaigns.

## Symbolic backend comparison

`symbolic-booster.json` records one new proof identity with the original symbolic
harness and domain, changing only Booster selection. Its build passed and its
prove timed out at the same 900-second bound. The saved state reaches deployed
Native runtime calls beyond the earlier constructor stop. It is neither a PASS
nor a counterexample and has no completed guard-removal counterpart. The original
two no-Booster receipts remain unchanged. Raw proof files were recovered and
compared before the owned WSL workspace was removed.

`runtime-link-source-blockers.md` assigns the seven correspondence parts to each
profile and states the exact checked producer, replay conditions and trust-boundary
work still needed. Its source inspection is not an impossibility theorem.

## Structural model work in progress

The canonical child theories now separate state definitions, custody arithmetic,
six forward actions, UNRESTRICT, UNFREEZE and RELEASE preservation. The general
`forward_preserves_state_wf` and `reversal_preserves_state_wf` results have a local
kernel build. The linked-run, shared-custodian, below/above-supply and
source-effect removal controls also passed. The 219-root, 236-fact recursive
audit reports zero oracle dependencies. Independent integration review and
admission of the fresh committed-source clean build remain in progress. None of these model results supplies an EVM-to-HOL producer.

`generate-trust12-proof-audit.py` enumerates every declared child theorem, using
qualified names for locale theorems. Both the local closure runner and proof CI
check the generated inventory before building. The generator is itself part of
the formal input identity, and the review seal includes every child theory.

`model-preservation-audit.md` records the bounded seven-source independent review.
`record-trust12-model-results.mjs` requires the current clean-build identity and
actual proof export before recording the model theorem and control groups.
