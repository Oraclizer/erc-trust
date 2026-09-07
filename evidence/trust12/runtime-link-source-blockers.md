# Runtime correspondence: current source blockers

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

A proposed first feasibility window is 45 minutes to locate or construct a typed
execution witness and a checked receiver in the existing stack. This window has
not been run. A reliable estimate for a complete implementation is unavailable
until that smallest correspondence is demonstrated; it must not be represented
as a routine recorder repair. No new paid service is required for the proposed
local diagnostic, and no external computation has been authorized by this file.

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
