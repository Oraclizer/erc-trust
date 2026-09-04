# Decision 10: how the kernel version 2 endpoints are connected to the abstract model

Status: implemented for the native token, the ERC-3643 profile adapter, and the profile
governor. The connection is a machine-checked obligation ledger over a rewritten abstract
model; the runtime evidence that binds the compiled bytes of both endpoints follows in the
runtime assurance change. The claim this decision permits is stated in item 7 and nowhere
stronger.

## Decision

1. The Isabelle session `ERC_TRUST` models kernel version 2 directly. The compositional
   state, the typed commands, the case transition table with its terminal-case guard, the
   ordered dependency root with the global epoch, the unified action and reversal receipt
   with its kind tag, the reason classes, the custody backing and floor arithmetic, and the
   ordinary transfer relation are the objects of `TRUST_Compositional_State`,
   `TRUST_Transaction_Refinement`, `TRUST_Bound_Dependency_Assume_Guarantee`, and
   `TRUST_Retrieve_Relation`. Delegation, cancellation, the caller-supplied scope hash, and
   the version 1 burn semantics of `CONFISCATE` are not modelled because kernel version 2
   removed them (decisions 01 to 07). `CONFISCATE` moves the exact amount and preserves
   total supply, as the code does.
2. The ERC-3643 Partial reference is modelled in
   `TRUST_Verified_Profile_Onboarding` with the declared-entry facts that decision
   09 fixes: imported frozen and restricted entries open reversible cases with a
   live head, while an empty manifest changes no declared state and proves no
   completeness or fresh-zero property. Profile authorization is exactly the
   single immutable authority at the seal epoch. Upstream state the adapter does
   not own is an operational stutter; forced-transfer restriction mismatch is a
   reason-401 stutter; receipt observations consume actual restriction values;
   and resynchronisation only raises the upstream frozen amount toward the owned
   target.
3. The generated bridge is regenerated for the three successor runtimes by
   `scripts/generate-runtime-bridge-v2.mjs` from the compiled artifacts and the kernel
   schema. It binds the runtime template hashes, every selector with its route class, the
   storage layouts, the typed error selectors, the event topics, and the fixed-width guard
   positions of the typed commands. It classifies every selector or fails; a selector outside
   the classification falls through the compiler dispatcher and is the unclassified generic
   input of the model. Continuous integration runs the generator in check mode after the
   build, so the bridge cannot drift from the artifacts.
4. The central obligation ledger `evidence/end-to-end-refinement/obligation-ledger-v3.json`
   carries one row per load-bearing abstract condition of each endpoint. A row names the
   abstract facts, the normative receiver in the kernel machine source, the exact source
   consumer lines with their occurrence counts, the positive activation tests, the
   declared negative detectors (a killed consumer-removal mutation when one source consumer can
   be removed, otherwise a bounded behavioral negative whose scope the row states), the compiled or downstream consumer
   (Kontrol proof, bridge field, bounded runtime execution, or conformance vector), the
   assumptions it rests on, and its status. `scripts/verify-obligation-ledger-v3.mjs`
   checks every anchor against the current tree, requires every mutation to be declared and,
   once a receipt of the current identity exists, killed, and renders
   `TRUST_Obligation_Ledger_Generated.thy`, which makes the Isabelle build fail when a cited
   fact disappears. Continuous integration runs the verifier. A row with status
   `CURRENT-MANDATORY` fails the check; the merge condition of this change is that none
   exists.
5. The candidate 2 bridge theories, the current-profile per-row theories, the C0 runtime
   occurrence theories, the KEVM claim specifications, row bundles, reusable claims, and
   runner scripts were bound to the candidate 2 runtime template and the version 1 kernel.
   They cannot be rebound by regeneration because the commands, the receipt, the cases, and
   the dependency root changed shape. They are moved byte for byte to
   `evidence/candidate-2/formal/` as history. `TRUST_M4_Action_Reversal_Row_Corollaries.thy`
   stays at its path unchanged because it is a proof-bound allowlisted source and its facts
   remain valid over kernel version 2.
6. The effect head and the effect record of both endpoints carried an `effectHash` that no
   consumer checked (the reversal path validated the head by action identifier and by
   state). A condition with no consumer cannot have a consumer-removal negative, so the
   field, its computation, and its storage writes are removed from
   `TrustNativeTypes`, `ERC3643ProfileTypes`, `TrustToken`, and `ERC3643TrustAdapter`. The
   head is identified by the action itself; the action record and the effect record are
   immutable once written. The storage slot numbering of both endpoints is unchanged. The
   native runtime template is 20,043 bytes and the current Partial adapter is 19,480 bytes. The
   proposal to add a length-parity view for the derive functions is rejected: it adds bytes
   without closing an abstract condition and is recorded as a nonclaim.
7. The claim permitted by this decision is "mapped implementation evidence; end-to-end
   refinement incomplete". The locale assumption `pinned_runtime_refinement.runtime_link`,
   that every accepted execution of the pinned runtime template corresponds to an admitted
   abstract transaction, is not discharged. The four Kontrol proofs rerun on the successor
   native runtime and the Foundry executions are bounded instances of that link, not a proof
   of it, and the adapter has no symbolic lane at all. The two ledger rows that name this
   link (`NAT-E2E-01`, `ADP-E2E-01`) have status `SUCCESSOR-MANDATORY`, the closure status is
   `CONDITIONAL`, and the words "Full", "refinement complete", "end-to-end refinement
   complete", and "implementation conforms to the model" are not used for the successor
   until those rows are closed and the closure record says so.

## Consequences

- `formal/kevm/` holds the regenerated bridge, the compile script, and the dependency lock
  only; it is the input side of a KEVM program that has not been restarted for kernel
  version 2.
- The mutation campaign gains sixty faults (fifty-two to one hundred and eleven). Every closed
  ledger row has a declared negative detector: a code mutation wherever a single source line
  carries the condition, and a bounded behavioral negative test for the rows whose
  consumer is compiler-generated or whose condition is a whole-state invariant (the ledger
  names which). Killed mutations are established by the mutation receipt, not by the
  ledger verifier alone.
- Any change to the kernel schema, the compiled artifacts, the storage layout, or a cited
  theorem reopens the ledger: the generator check, the ledger verifier, and the Isabelle
  build fail until the ledger is regenerated and every row is re-examined.
- The runtime assurance change binds the deterministic build of all three runtimes to the
  bridge and the ledger summary; until then the lane `obligationLedger` of the successor
  index is pending on that binding, not on the ledger itself.
