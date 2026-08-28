# ERC-TRUST Abstract-Model Claim and Obligation Matrix

Date: 2026-07-23
Scope: abstract semantics and compatibility layer
Maximum allowed claim: **mechanically verified regulatory dynamics over the declared domain**

This matrix separates the Isabelle conjunct from the Solidity, bytecode,
deployment, and migration conjuncts that require implementation-correspondence
or deployment evidence. `PROVED (abstract model)` never means that an implementation or deployment refines the
model.

## Normative requirements

| ID | Abstract conjunct | Model status | Exact downstream receiver |
|---|---|---|---|
| T-N01 | No ABI or ERC-165 implementation claim is made. | N/A: concrete interface obligation | ABI/interface manifest and selector tests; reopen the implementation claim if any advertised interface is false. |
| T-N02 | Six RCP values, descriptors, and receipts stay distinct. | PROVED (abstract model) | Enum/ABI/event round-trip; reopen on collision or alias. |
| T-N03 | Six RCP actions and seven foundation-model labels are separate; RECOVER/LIQUIDATE have no foundation-model label; UNFREEZE/UNRESTRICT/RELEASE each has a reachable execution witness. | PROVED (abstract model) | Encoding and call-graph mapping; `MUT-04` is the model reopen test. |
| T-N04 | Typed record binds domain, token, version, action, scope, authority/policy epochs, provenance, nonce, and validity. | PROVED (abstract model) | Storage/hash/signature encoding; reopen the implementation claim if any field is absent from the signed or stored commitment. |
| T-N05 | Create requires an explicit caller equal to the record issuer and contained in the configured regulatory-authority anchor; approve/cancel/delegate recheck the anchored issuer, and issuer/delegate plus complete payload/binding checks precede execution. Untrusted self-issuance has a reachable fail-closed witness. | PROVED (abstract model) | Credential/signature and role topology plus delegated-scope enforcement; reopen the model on removal of the configured anchor and the implementation claim on caller/record/credential mismatch. |
| T-N06 | Create/approve/cancel/delegate/consume lifecycle, nonce consumption, stale authorization, replay rejection, monotonic authority rotation, and policy rebind invalidation. | PROVED (abstract model) | Concrete storage and refinement evidence; `MUT-06` reopens the model. |
| T-N07 | Native, typed ERC-7943, and declared ERC-3643 profile paths normalize to one canonical request; untyped paths fail closed. | PROVED (abstract model) | Exhaustive reverse call graph and no-bypass evidence; CE-04 remains OPEN until the concrete obligation is discharged. |
| T-N08 | Applied is one atomic abstract state update; reject/failure stutter. | PROVED (abstract model) | Revert/event/external-call ordering and forward simulation. |
| T-N09 | Applied, Rejected, and OperationalFailure are disjoint; generic canonical and entrypoint reject/failure implications preserve the complete abstract state. Ordinary, governance, and authorization-command reject paths also have generic full-state stutter theorems. | PROVED (abstract model) | Custom errors/revert traces and atomic downstream behavior. |
| T-N10 | Policy address/code identifier, schema, config, authority epoch, policy epoch, and validity are load-bearing; dependency failure is fail-closed. | PROVED (abstract model) | Module calls and rebind topology; CE-05 remains OPEN until the concrete obligation is discharged. |
| T-N11 | ERC-7943 frozen amount is absolute and may exceed balance; boolean failure is false while TRUST keeps a detailed failure; permission view does not replace base balance checks. | PROVED (abstract model) | Public transfer/mint/burn and event-order differential tests. |
| T-N12 | Enforcement transfer requires the typed authorization path and action-specific destination; ordinary transfer has a separate executable gate, success witness, denial witness, and balance-only frame. | PROVED (abstract model) | Allowed-override matrix and raw-selector negative evidence. |
| T-N13 | Applied receipt binds action, authorization, source, destination, amount, case, policy, provenance, pre/post commitments, action-specific settlement status, and is the last persistent receipt in the abstract step. | PROVED (abstract model) | Base/ERC-7943 event and external-hook ordering; CE-13 remains concrete. |
| T-N14 | SEIZE preserves balance/title separation and records custodian, declared prior holder, case, and encumbered amount; RELEASE and explicit RECOVER/LIQUIDATE escalation consume custody, encumbrance, and prior-holder state together from nonempty reachable fixtures. | PROVED (abstract model) | Concrete storage/release evidence and retrieve relation; `MUT-10` reopens the model. |
| T-N15 | LIQUIDATE binds token disposition fields, settlement/proceeds references, and external settlement status in state and receipt; RECOVER binds entitlement/destination/amount/one-time consumption; external legal truth is excluded. | PROVED (abstract model) | Adapter calls and concrete retrieve relation; external truth remains outside every evidence layer. |
| T-N16 | ERC-7943 absolute frozen delta maps increase/decrease/equality to FREEZE/UNFREEZE/no typed change; forced transfer needs a typed transfer binding. | PROVED (abstract model) | Same-transaction context mechanism and raw-call negative vectors. |
| T-N17 | ERC-3643 support is an explicit optional subset; generic forced transfer and pause are not assigned RCP meaning. | PROVED (abstract mapping) | Owner/Agent/Compliance/Identity topology and direct-Agent negative test; CE-14 remains OPEN. |
| T-N18 | No compiler, bytecode, or deployment identity claim exists at the abstract-model layer. | N/A: concrete evidence obligation | Source/build hash manifest and runtime-bytecode binding. |
| T-N19 | Theory/source hashes invalidate this evidence when the abstract bundle changes; every TRUST manifest outcome, target, observable, and write-set is evaluated from a reachable `execute_entrypoint` fixture rather than copied from a scenario constant. | PROVED for the abstract bundle | Implementation, adapter, config, upgrade, and migration reopen mechanisms. |
| T-N20 | Claim inventory excludes legal truth and implementation/deployment verification. | PROVED (abstract model) | Claim diff; reopen the responsible evidence layer on any stronger public claim. |
| T-N21 | Abstract optional-profile subset is explicit; no live capability endpoint is claimed. | PARTIAL (abstract mapping only) | Capability/introspection endpoint and conflict rejection. |
| T-N22 | RCP/reversal/ordinary/typed-governance and authorization/policy-lifecycle allowed write-sets are explicit. Ordinary success proves exact source/destination deltas. Generic stutter and successful frames cover unrelated balances, allowances, supply where applicable, cases, authorizations, nonces, policy/authority configuration, custody, receipts, and auxiliary state. | PROVED for the abstract operations | Concrete all-entrypoint storage/event frame and external traces; CE-13/15 remain concrete. |
| T-N23 | Typed governance mint, burn, two-entry batch mint/burn, and recovery supply transfer require domain-bound governance authority/epoch/nonce, require every touched account to be ACTIVE with frozen/custody/encumbrance/prior-holder state clear, emit an exact write-set receipt, preserve regulatory state, and reject replay/unauthorized/bypass attempts. | PROVED (abstract model) | Exhaustive privileged-entrypoint inventory, arbitrary batch implementation, selector/event tests, and typed-governance evidence; CE-16 concrete topology remains OPEN. |
| T-N24 | Migration is outside the abstract executable domain. | N/A: intentionally outside declared domain | Full-state reconciliation, nonce non-revival, cutover, and rollback-disable evidence; CE-17 remains OPEN. |
| T-N25 | Proxy mechanics are outside the abstract executable domain. | N/A: intentionally outside declared domain | Initializer/selector/slot/upgrade proof, or an immutable profile that makes proxy duties inapplicable with evidence; CE-18 remains OPEN. |

## Inherited counterexamples

| Counterexample | Model disposition | Evidence that closes the abstract semantic layer | Remaining receiver and reopen rule |
|---|---|---|---|
| CE-02: SEIZE custody/title | CLOSED at the abstract semantic layer only | `ce02_retrieve_relation`, its nonvacuous foundation→TRUST witness, custody/prior-holder/encumbrance theorem, full-state deny/failure stutter, and `MUT-10`/`MUT-24` killed | Concrete storage/call evidence and retrieve relation. Reopen the model if the abstract retrieve relation or any custody, declared-prior-holder, or encumbrance conjunct disappears. |
| CE-11: LIQUIDATE settlement/debt boundary | CLOSED at the abstract semantic layer only | Generic `ce11_liquidate_assume_guarantee`, reachable state-and-receipt binding witness for destination/amount/settlement/proceeds/status, negative evidence/capability verdicts, stale-custody consumption theorem, `MUT-25` killed, and two-world claim boundary | Settlement adapter and concrete refinement. Reopen the model if an Applied LIQUIDATE no longer entails declared settlement/capability premises and all state/receipt bindings, or if actual sale/debt truth enters a theorem conclusion. |
| CE-12: RECOVER rightful-owner boundary | CLOSED at the abstract semantic layer only | Generic `ce12_recover_assume_guarantee`, reachable state-and-receipt binding witness for entitlement/destination/amount, negative entitlement verdict, stale-custody consumption theorem, replay rejection, `MUT-06`/`MUT-26` killed, and two-world claim boundary | Entitlement provider and concrete refinement. Reopen the model if an Applied RECOVER no longer entails entitlement attestation, destination credit, receipt binding, and one-time consumption, or if rightful ownership becomes a theorem conclusion. |

## Refinement register status

- TRUST-REF-01a-g: **not discharged**. The abstract bundle supplies the model side only.
- TRUST-REF-02a: **not started at the model layer**; ABI/ERC-165 is a concrete obligation.
- TRUST-REF-02b-f: **Isabelle-layer conjunct proved or specified as shown
  above; concrete conjunct pending**. None is marked discharged.
- TRUST-REF-02g: **claim boundary specified; migration/deployment proof pending**.

## Reproduction entrypoints

Run these separately and preserve their exit codes and logs:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ERC_TRUST\evidence\model-verification\run-trust-closure.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\evidence\model-verification\generate-manifest.ps1
node.exe .\evidence\model-verification\reverse-check-manifest.mjs
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\evidence\model-verification\run-negative-mutations.ps1
```

The manifest envelope and `sha256.tsv` are the hash SSOT. This document does
not embed their values, avoiding a self-referential hash.
