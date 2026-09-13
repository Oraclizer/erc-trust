# Runtime correspondence: current source blockers

> 2026-09-13 release-scope reset: the general correspondence obligations described
> below remain open as RESEARCH-RESIDUAL rows. They are not current TRUST 1.2 release
> requirements. The three RUNTIME-LINK release rows now own profile implementation
> evidence under `release-policy.json`; this preserves the historical research
> diagnosis without claiming its missing producer was proved.

Status: SOURCE_BLOCKED for general compiled-runtime correspondence. This is a
source and tool-interface inspection, not a machine-checked impossibility result.
The development evidence and model theorems keep their own narrower validity.

## Exact missing producer

`formal/isabelle/ERC_TRUST/TRUST_End_To_End_Composition.thy` declares
`runtime_execution` and `runtime_abstraction` as free locale parameters.
Its `runtime_link` assumption supplies `alpha_transaction`, defined in
`TRUST_Transaction_Refinement.thy`. The available generated bridge, compiler
replay, Foundry observations and Kontrol/Certora receipts do not construct a
kernel-checked derivation from an actual EVM execution to that relation.

The inspected Kontrol graphs record states, edges and tool results. The new
Booster graph reaches a deployed Native call frame but has no target cover and
is not a completed deployment summary. Parsing its storage or observing a
successful EVM status would supply data, not the missing proof of correspondence.
The existing calldata guard theorems are useful model facts; they do not prove
that every compiled dispatch and call implements those guards.

## Obligations owned by each profile

Every row below remains open for Native, legacy Partial and the fresh Hook.
The responsible artifact is the corresponding `RUNTIME-LINK-*` row of
`evidence/trust12/obligation-ledger.json`, with the named model/source consumer.

| Part | Existing consumer and evidence | Required checked result |
| --- | --- | --- |
| Constructor and storage | `TrustToken` constructor; fresh Hook deployment; `native_initial_state`; generated storage layout | Exact creation execution, immutable resolution, complete mapping storage and word decoding produce the initial abstract state. Imported Partial state must retain its stated completeness assumptions. |
| Calldata and dispatch | `TRUST_C0_Decode_Slices`, `TRUST_State_Abi_Normal_Form`; generated selectors and route inventory | Actual byte dispatch, length, word and enum checks produce the typed command, including malformed-call outcomes. |
| Authorization and replay | `forward_admitted`, `reversal_admitted`; endpoint authorization and nonce code; selected bounded tests/proofs | Actual caller, authority, epochs, identifiers and stored replay checks entail model admission or the exact failure class. |
| Dependency calls | `TrustDependencyBinding`; `TRUST_Bound_Dependency_Assume_Guarantee` | Actual STATICCALL, code/configuration identity, return shape and echoed fields supply the model's declared dependency observations. |
| Effect and frame | `forward_success_state`, `reversal_success_state`; endpoint state writes and transfer paths | The actual post-storage state decodes to the specified effect, with untouched fields and word/overflow behavior accounted for. |
| Revert | `abstract_failure_transition`; Foundry rollback observations | EVM failure and call-frame rollback entail persistent state stutter, while preserving the actual observed failure outcome. |
| Receipt and logs | `receipt_matches_forward`, `receipt_matches_reversal`, `alpha_transaction`; stored/returned/emitted receipt tests | Actual event order, data, return bytes and receipt preimages decode to the same model result. Hash/selector equality alone is insufficient. |

Native has preserved bounded compiled-code evidence and an incomplete expanded
symbolic attempt. Partial retains its narrower profile and four historical
Certora rules. Hook has its own nine actual T-REX integration tests, six feature
mutations and compiler identity. None supplies the missing general producer for
another profile.

## Minimum next experiment and trust boundary

The smallest useful correspondence experiment is a source-bound Native slice:
exact constructor/storage, one FREEZE command, its dependency calls, and both a
successful result and a nonincreasing-target rejection. Its deliverable must be
an executable producer plus an Isabelle-checked relationship to actual EVM
semantics, with state/receipt observation removal controls. A table of slots,
selectors, hashes or externally asserted PASS values does not meet that target.

The local feasibility window has now completed in 1,261.947 seconds (about
21 minutes) within its 45-minute limit. `runtime-producer-feasibility.json`
records the installed Kontrol 1.0.255 interface and source inspection, the
18-file Kontrol and 123-file pyk Python census, selected exporter/serialization
source hashes, and the actual saved-graph parse. The 22 source proof files
remained byte-exact. The graph parsed as pyk KCFG with 20 nodes, 14 edges,
two splits and zero covers. This is data-format evidence only.

The inspected load-state path emits Solidity state-loading contracts; graph
export emits K/KEVM modules or best-effort claims/rules. No Isabelle-checked
operational receiver was found in the inspected local source. The HOL review
separately confirmed that the execution record merely carries supplied fields,
manifest projections are supplied functions, and the native word decoder does
not implement bytes-to-typed-command decoding. A source-bound HOL execution
inhabitant, correspondence positive/negative pair and semantic mutation were
therefore not produced. Formal correspondence Building was not opened.

The disposition is PARTIAL / SOURCE_BLOCKED, not an impossibility theorem.
A reliable complete-implementation estimate is unavailable until a checked EVM
receiver or verified trace/proof translator is selected and demonstrated. The
minimum Native slice needs actual constructor/storage, calldata, external-call,
return/revert and receipt/log decoding, plus a checked operational derivation.
No new prover, deployment, paid calculation or alternative proof stack was run
in this feasibility window. Existing model and bounded implementation evidence
retain their separate validity.

A kernel-checked operational correspondence can keep the Isabelle proof kernel
as the final checker, but the exact EVM semantics and any translation must still
be specified and reviewed. Treating a Kontrol result or a decoded snapshot as an
unproved HOL premise leaves the result conditional and does not discharge
`runtime_link`. Replacing the proof stack is a separate design decision.
Act, hevm and Rocq were not run or credited in this work.

CLOSED requires the actual producer and its positive, negative and independent
replay evidence for each named profile. If the typed source witness or checked
receiver is unavailable, preserve this blocker and prepare the specific new
semantics/translation scope before changing the trust model. Model preservation,
linked model runs and bounded implementation work can continue independently.
