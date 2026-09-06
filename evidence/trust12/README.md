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
