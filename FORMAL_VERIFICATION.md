# ERC-TRUST verification and refinement map

This is the repository-level entry point for the exact
`0.1.0-candidate.2` verification package. It separates the abstract Isabelle
model, the native Solidity reference, the ERC-3643 conformance fixture, and the
preserved FREEZE pilot. A PASS below applies only to the named source, build, rule,
and harness boundary.

The accompanying [research paper](https://arxiv.org/abs/2608.29134) explains
the domain semantics and evidence taxonomy. This repository remains the exact
executable artifact and release-identity SSOT.

> **Unaudited. Not for production. No deployment, proxy, migration, or
> external legal/factual truth is verified.**

## Verification architecture

<div align="center">
  <img src="docs/assets/verification-architecture.svg" alt="ERC-TRUST verification architecture separating the Isabelle abstract model, Solidity and Certora checks, compiled EVM bytecode, Kontrol and KEVM proofs, the unclaimed full refinement theorem, and the separate deployment boundary" width="900">
</div>

Solid paths show actual artifact or verification inputs. The coral obligation
boundary marks a relationship that still requires a complete refinement
theorem; it is not a discharged theorem. Deployment identity, chain, roles,
and operations require separate evidence.

## Ownership and canonical locations

| Role | Canonical location |
| --- | --- |
| Abstract model | `formal/isabelle/ERC_TRUST/` |
| Model replay and claim matrix | `formal/isabelle/ERC_TRUST/evidence/model-verification/` |
| Native reference implementation | `implementation/src/TrustToken.sol` |
| ERC-3643 fixture profile | `implementation/src/profiles/` |
| Unit, fuzz, and invariant evidence | `implementation/test/` |
| Bounded CVL rules | `implementation/certora/` |
| KEVM high-risk cross-checks | `implementation/kontrol/` |
| Preserved FREEZE pilot | `pilot/` |
| Exact result and release bindings | `evidence/` |
| Isabelle/Solidity applicability | `evidence/isabelle-solidity-applicability.md` |
| Successor obligation ledger (kernel version 2) | `evidence/end-to-end-refinement/obligation-ledger-v3.json`; rendered `obligation-ledger-summary-v3.json`, `central-closure-v3.json`, and `formal/isabelle/ERC_TRUST/TRUST_Obligation_Ledger_Generated.thy` |
| Successor runtime bridge | `evidence/end-to-end-refinement/runtime-bridge-v2/`; `formal/isabelle/ERC_TRUST/TRUST_Runtime_Bridge_Generated.thy`; `formal/kevm/generated/trust-runtime-bridge.k` |
| Successor Kontrol receipt | `evidence/kontrol-results-v3.json` |
| Superseded candidate 2 formal artifacts | `evidence/candidate-2/formal/` |
| End-to-end evidence map | `evidence/candidate-2/end-to-end-refinement/README.md` |
| End-to-end semantic decision | `evidence/candidate-2/end-to-end-refinement/semantic-alignment-decision.md` |
| End-to-end theorem obligations | `evidence/candidate-2/end-to-end-refinement/theorem-obligations.md` |
| Public current-profile release index | `evidence/candidate-2/current-profile-release-index-v2.json` |
| Successor package qualification | `evidence/candidate-2/end-to-end-refinement/c-series-terminal-qualification-v2.json` |
| Successor row qualification | `evidence/candidate-2/end-to-end-refinement/current-profile-row-qualifications-v2.json` |
| Historical row qualification index | `evidence/candidate-2/end-to-end-refinement/m4-current-profile-row-qualifications-v1.json` |
| Public two-layer runtime binding | `evidence/candidate-2/end-to-end-refinement/runtime-binding-current-profile-qualification-v3.json` |
| Public archive separation | `evidence/public-release/diet-manifest-v2.json`; historical removal set in `diet-manifest-v1.json`; `evidence/public-release/supersession-manifest-v1.json` |

The product repository owns the ERC-TRUST model and implementation. The
external `Cross_Domain_State_Preservation` session supplies reusable
regulatory state-machine foundations; that dependency does not transfer model
or implementation ownership.

The historical closure remains bound to the byte-exact
`formal-dependencies.lock.json`. Its pinned commit is no longer reachable from
the public foundation repository, so the public build uses the versioned
`formal-dependencies-public-v1.lock.json`. The successor maps all fourteen
historical foundation files to the reachable public revision. Ten theory files
and one bibliography input are byte-exact. The regulatory-action theory differs
only in its title comment and qualified import path; its theorem statements and
bodies are otherwise byte-exact. The remaining two mappings record the
session and non-proof document split.

Continuous Integration copies the mapped regulatory-action theory into a
temporary foundation session and registers it for that build only. The
compatibility session does not modify this repository's proof source or create
new proof credit. `scripts/verify-formal-foundation-supersession.mjs` rejects
foundation-commit drift, any mapped-file drift, a missing registration, a
wrong import, and a wrong overlay commit. The temporary session is removed
when a stable public foundation commit directly provides the same qualified
theory and the same succession verification passes.

## Successor refinement closure (kernel version 2)

The successor code under `implementation/` is connected to the abstract model by
the central obligation ledger described in `spec/decisions/10-refinement-closure.md`.
The Isabelle session models kernel version 2 directly; the runtime bridge is
regenerated from the compiled artifacts of the native token, the ERC-3643
profile adapter, and the profile governor; and every closed ledger row names
the exact source consumer, the positive activation test, the consumer-removal
mutation or behavioral negative, and the compiled or downstream consumer of one
abstract condition. The verifier checks every anchor against the current tree
and renders the ledger into the Isabelle session, so a cited fact cannot
disappear without failing the build.

The claim this establishes is "mapped implementation evidence; end-to-end
refinement incomplete". The locale assumption `runtime_link` in
`TRUST_End_To_End_Composition.thy` is not discharged: no theorem states that
the compiled runtime implements the model. The four Kontrol proofs rerun on the
successor native runtime and the Foundry executions are bounded instances of
that link, and the adapter has no symbolic lane. The two ledger rows that name
the link are open, the closure record is conditional, and no Full or
refinement-complete wording applies to the successor. Replay from the
repository root:

```bash
forge build
node scripts/generate-runtime-bridge-v2.mjs --check
node scripts/verify-obligation-ledger-v3.mjs
```

The sections that follow describe the shipped `0.1.0-candidate.2` package and
its historical evidence.

## Native Full financial-core refinement scope

The complete 79-row registry remains a historical assurance inventory. It is
not executed as 79 independent whole-transaction KEVM claims. The mandatory
Native Full current profile is tracked separately:

- Core Refinement: `49/49` current-profile qualified;
- Core Supporting: six legacy-closed, `24/24` current-profile qualified;
- optional Full/Profile backlog: `0/6`, nonblocking and still OPEN.

All 49 Core rows remain row-specific statements and distinguishing negatives,
but their expensive runtime reasoning is provided by 22 reusable universal
claims in seven C0-C6 parser batches. Certora supplies bounded source-level
rules, Foundry and mutation tests provide concrete falsification evidence,
and KEVM is restricted to exact ABI, call, revert, rollback, log,
receipt, sparse-frame composition, and final row-corollary seams. Tool results
placed side by side are layered assurance; an explicit Isabelle/K bridge and
row corollary are required for formal refinement credit.

ACT-01 is a Native FREEZE corollary of the reusable State/ABI,
Authorization/Replay, Dependency, Exact-use Route, Forward Effect, and
Commit/Rollback/Receipt packages. Its concrete two-segment PASS is preserved as
a topology canary and is not extended manually. The reusable C0-C6 campaign is
now terminal `7/7`; each package is bound to a positive proof, distinguishing
negative or executable mutant, baseline restore, frame, assumptions, and
nonclaims in the historical v1 receipts. Candidate 2 reissues all seven
packages in `c-series-terminal-qualification-v2.json`: C0 is rebound to the
current runtime evidence, while C1-C6 carry forward only through the verifier's
exact two-guard production delta and named current evidence. This does not
claim seven fresh whole-runtime proofs.
The row qualification index now also binds the `STATE-04` theorem that FREEZE
and RESTRICT retain separate observations, a typed coexistence inhabitant, and
a same-state conflation negative. The successor row index binds it to the
repaired source and package root rather than treating the historical runtime
as unchanged.
`STATE-05` similarly binds case-scoped terminality. The first batch fans the
same immutable package layer out to the remaining eight action-success and
three reversal-success statements, while preserving one distinguishing
negative and one current product inhabitant for every row.
All 24 mandatory Supporting rows are current-profile qualified through their
existing retrieve/ABI/artifact/nonclaim theorems or checked properties and
fail-closed row negatives. For `STATE-02`, `STATE-03`, and `ART-01`, the
two-layer runtime-binding package preserves the historical
whole-file Foundry hashes while separately checking ABI, semantic storage
layout, creation bytecode, runtime bytecode, method identifiers, and immutable
reference positions against pinned-solc replay. All seven current artifacts
are semantic-payload exact with packaging drift. The verifier kills all 42
subject-by-semantic mutations, classifies all seven packaging-only mutations
as drift-PASS, and fails closed on all seven expected-hash overwrite
mutations. The repaired runtime is 24,177 bytes: the deterministic artifact
template and pure immutable-resolved runtime have distinct hashes but the same
length. `runtime-binding-current-profile-qualification-v3.json` binds the new
identity, and the pure-fixture checker recomputes all seven subjects. Historical
runtime receipts remain scoped to their original bytes.

### Composite proof for fixed-width decoder guards

The fixed-width decoder checks are proved with a deliberately explicit
two-kernel composition. KEVM proves the exact runtime reachability claim under
two bounds on the result of the bitwise mask. Isabelle/HOL independently proves
that both bounds hold for every 256-bit word, using the standard unsigned-word
projection and standard word-library lemmas. A hash-bound correspondence record
states how the nonnegative K integer domain, K bitwise AND, Isabelle 256-bit
words, and Isabelle word AND denote the same masked unsigned value.

This composition preserves the full accepted/rejected input partition, and a
branch-flip mutation changes the observed runtime result as required. It is not
reported as an independently unconditional KEVM theorem: no single proof kernel
checks the K-to-Isabelle correspondence itself, and the result is not a complete
Isabelle-to-EVM refinement theorem.

| Term | Meaning in this package |
| --- | --- |
| Conditional reachability claim | A KEVM theorem whose runtime conclusion is proved from explicitly listed premises |
| Redundant premise | A premise proved by Isabelle/HOL to hold for every value in the frozen 256-bit input domain, so it removes no input from the stated coverage |
| Correspondence record | The hash-bound declaration relating K integer bit operations to Isabelle fixed-width word operations; it is an explicit trust seam, not a cross-kernel proof object |
| Composite fixed-width result | The conditional KEVM theorem, Isabelle redundancy theorem, exact correspondence record, and mutation witnesses considered together |

The trusted computing base for this composite result includes the pinned K and
KEVM semantics, Kore backend and solver behavior, the Isabelle kernel and HOL
word library, and review of the explicit K/Isabelle correspondence. Repository
verifiers freeze the exact claims, theorem source, approved premises, compiled
definition, and correspondence hashes; they reject extra premises, carrier
changes, local semantic rules, and forbidden computation-reflection shortcuts.

## Model-to-implementation refinement map

This table is the candidate 2 map. The successor map is the obligation ledger
(`evidence/end-to-end-refinement/obligation-ledger-v3.json`).

| Obligation | Abstract anchor | Reference-implementation anchor | Current evidence boundary |
| --- | --- | --- | --- |
| Six typed actions | `Regulatory_Execution_Semantics.thy`; `RCP_Action_Mapping.thy` | `ActionKind`; `executeRegulatoryAction` | All six concrete effects are covered by unit/fuzz tests; terminality and supply preservation are bounded CVL obligations |
| Three separate reversals | execution lifecycle theories | `ReversalKind`; `executeRegulatoryReversal` | UNFREEZE, RELEASE, and UNRESTRICT are concrete tests; successful lifecycle/supply behavior is a bounded CVL obligation |
| Rejected versus operational failure | canonical assessment outcomes | `TrustDecision`; bound dependency calls | Full-storage stutter is checked in unit tests, CVL, and the KEVM operational-failure cross-check |
| Replay and authorization binding | nonce, epoch, and command lifecycle | action/reversal IDs, authority/delegation epochs, nonce keys | Replay/fixed-field tests, CVL structural stutter, and negative mutations |
| Exact action effects and receipts | transition frames and observables | action records, typed effect storage, canonical receipts | Unit/fuzz checks plus the KEVM LIQUIDATE exact-delta and final-log proof |
| Ordinary transfer relation | token compatibility theories | ERC-20 paths and ERC-7943 frozen floor | Unit/fuzz/invariant checks and bounded CVL exact-delta/failure-stutter rules |
| Exact-use compatibility route | token compatibility theories | same-transaction route ticket | Raw selector KEVM proof, route invariant, and mutation detector |
| ERC-3643 profile | optional compatibility profile | sealed `ProfileGovernor` and `ERC3643TrustAdapter` | Clean-room fixture-bound tests only; arbitrary deployments require a new exact runtime inventory |
| External truth boundary | `Claim_Boundary.thy` | codehash/config/schema/epoch bindings and commitments | The implementation records and checks bindings; it does not establish legal, policy, identity, settlement, proceeds, or entitlement truth |

This evidence does not establish a machine-checked end-to-end refinement
theorem from Isabelle to EVM bytecode. The detailed row disposition is in
`evidence/trust-ref-matrix.md`.

The approved semantic alignment and theorem registry are recorded under
`evidence/candidate-2/end-to-end-refinement/`. In the historical candidate 1 registry,
six rows were discharged and the other 73 were open; those dispositions remain
historical facts only. Candidate 2's successor profile rebinds all 49 Core and
24 mandatory Supporting rows through
`current-profile-row-qualifications-v2.json`, using named current evidence or
the verifier-enforced exact two-guard delta. This repository qualification is
not a claim that the former open rows became 73 independent unconditional
compiler-to-EVM theorems.

The pinned Isabelle/EVM candidate passed an isolated Isabelle2025-2
compatibility build, but its root theory-source license is not stated. It is
therefore not adopted or vendored, and implementation is stopped at the
dependency gate. Exact identity, hashes, replay command, semantic limits, and
resume alternatives are recorded in
`evidence/candidate-2/end-to-end-refinement/isabelle-evm-feasibility.md`.

The official Isabelle/Solidity AFP framework was source-inspected and its
selected session was clean-built successfully. Its candidate disposition is
**NOT APPLICABLE**: the only easy translations are non-stateful helpers, while
the principal risks depend on low-level calls and decoding, revert stutter,
compiled exact-use routes, storage closure, and event order that the evaluated
shallow embedding does not connect to the Solidity compiler or EVM bytecode.
The exact source binding and non-claims are in
`evidence/isabelle-solidity-applicability.md`.

## Exact reference-candidate verification disposition

### Foundry

The pinned Foundry 1.7.1 / Solidity 0.8.36 build passed:

- 31 tests, 0 failures, 0 skipped;
- two fuzz properties at 256 runs each;
- three invariants at 256 runs × 500 calls each, or 384,000 calls total;
- runtime size 24,177 bytes, leaving 399 bytes below the EIP-170 limit;
- six intentional `block.timestamp` validity-window warnings and no lint
  errors.

The invariant campaign checks supply conservation, absence of a persistent
route ticket, and interface truth. The profile suite includes a negative
unsealed/non-exclusive topology case.

### Certora

Certora CLI/server 8.19.1 completed the two targeted current-candidate rules:

| Configuration | Run | Result |
| --- | --- | --- |
| `TrustFreezeDirection.conf` | [`2f7c362ce29d465e9fb8e3facb1320ad`](https://prover.certora.com/output/10491299/2f7c362ce29d465e9fb8e3facb1320ad) | 2/2 rules SUCCESS; advanced sanity nonvacuity witnesses present; 0 fail, timeout, or unknown |

The verification-only harness inherits the production `TrustToken` and calls
its internal `_validateActionShape` without copying the guard. It proves that a
strictly increasing FREEZE target is accepted and that an equal or decreasing
target reverts with complete inherited-storage rollback in the wrapper
transaction. It does not prove the complete external action entrypoint,
authorization, dependency, receipt, event, or whole-runtime behavior.

Two exploratory full financial-core jobs, on CLI/server 8.17.1 and 8.19.1,
both ended UNKNOWN because of provider internal error `4201170908`. They grant
no proof credit. The targeted PASS and both provider-defect dispositions are
recorded in `evidence/candidate-2/certora-financial-core-v2.json`.

The former `TrustToken.conf` 7/7 and inventory 12/12 runs remain historical
candidate 1 evidence in `evidence/candidate-2/certora-results.json`; they are not presented
as fresh candidate 2 proofs.

#### Policy-binding classifier inputs

`TrustPolicyBindingHarness.sol` isolates the fail-closed classification of a
bound dependency observation. Its CVL specification checks the complete result
partition, evidence clearing for malformed observations, evidence preservation
for canonical observations, and an inhabitant for every declared result class.
The paired mutation removes the binding-echo check and is evaluated against the
same partition rule. Foundry unit tests independently cover the canonical and
malformed branches.

This verification-only boundary does not prove that a low-level call occurred,
that return data was copied correctly, or that the token consumed the result in
a complete action transaction. Those compiled-EVM and full-transaction
relationships remain separate refinement work.

### Kontrol/KEVM

Kontrol 1.0.255 with KEVM 1.0.678 rebuilt the exact CANCUN bytecode and passed
all four selected proofs:

| Proof | Result |
| --- | --- |
| `testKontrol_RawSensitiveSelectorsStayClosed():0` | PASS |
| `testKontrol_OperationalFailureStuttersProjection():0` | PASS |
| `testKontrol_NonincreasingFreezeStuttersProjection():0` | PASS |
| `testKontrol_LiquidateExactDeltaReceiptAndFinalLog():1` | PASS |

The final proof imports `erc-trust-log-assertions.k` to check the final
canonical receipt log. Exact proof IDs and timings are in
`evidence/candidate-2/kontrol-results-v2.json`.

### Deterministic build and mutation

Two isolated clean builds produced byte-for-byte identical `TrustToken`
artifact, creation bytecode, and runtime bytecode. The machine-readable result
is `evidence/deterministic-build.json`.

Twelve temporary negative mutations were killed. In addition to
frozen-floor, route-ticket, receipt-order, fail-closed, fixed-action, nonce,
and ERC-3643 bypass faults, the campaign covers FREEZE direction, case
terminality, custody closure, current-policy reversal, and ERC-3643
FREEZE-direction checks. The
machine-readable result is `evidence/mutation-results.json`.

### Abstract model and preserved pilot

The unchanged Isabelle2025-2 `ERC_TRUST` session passed proof audit and closure.
The generated manifest contains 18 TRUST rows and 35 foundation-model rows; the
independent Node reverse checker re-enumerated the same unique key sets. The model negative
mutation campaign remains a model-level gate and does not prove Solidity.

The preserved pilot is byte-for-byte bound by `pilot/evidence/hashes.json`.
Its current local Foundry replay remains 13/13 PASS at 256 fuzz runs. The
previous Certora 13/13 and Kontrol 2/2 results remain historical provenance.
Public-label-only edits changed source/harness file hashes while leaving the
compiled pilot bytecode and CVL rule logic unchanged, so no fresh remote or
symbolic proof run is claimed and those results are not reused as
reference-candidate proof.

## Replaying the candidate

```text
forge fmt --check
forge build --sizes
FOUNDRY_FUZZ_RUNS=256 FOUNDRY_INVARIANT_RUNS=256 \
  FOUNDRY_INVARIANT_DEPTH=500 forge test
forge lint

(cd implementation && certoraRun certora/TrustFreezeDirection.conf \
  --rule strict_increase_is_the_only_accepted_freeze_shape \
         nonincreasing_freeze_shape_reverts_and_restores_storage)

FOUNDRY_PROFILE=kontrol kontrol build --foundry-project-root . --regen --rekompile
FOUNDRY_PROFILE=kontrol kontrol prove --foundry-project-root . --schedule CANCUN \
  --match-test <exact-proof-name>

node scripts/generate-pure-runtime-fixture.mjs --check
node scripts/verify-runtime-binding.mjs --check-receipt
node scripts/verify-current-profile-release-v2.mjs
```

Windows replay commands for deterministic builds, mutation checks, manifest
generation, release verification, and public-surface scanning are under
`scripts/`.

## Change discipline

A change to a model file, mapped Solidity symbol, verification specification,
dependency commit, compiler setting, evidence hash, or claim disposition must
update this map and regenerate the release manifest in the same change.
Historical raw runs and generated directories are not canonical source.
