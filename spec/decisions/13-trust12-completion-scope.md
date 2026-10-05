# Decision 13: the completion scope of TRUST 1.2

Status: recorded as the 2026-10-04 completion direction in
`evidence/trust12/release-policy.json`, 2026-10-04. Met on 2026-10-05, when the
fresh independent assurance passed and the ledger recorded TRUST 1.2 as complete
within the registered-execution scope. The evidence mode remains
`successor-development`; no release or deployment claim follows.

## Decision

1. TRUST 1.2 completion is defined at the registered-execution scope.
   Completion needs all of the following:
   - the verified Isabelle abstract model (sessions `ERC_TRUST` and
     `TRUST12_Accounting_Obstruction`);
   - the registered executions of the three declared profiles, that is the
     registered certificates of the twenty-seven profile and operation cells
     and the registered requests outside canonical form, bound to their exact
     compiled runtimes and related to the model by kernel-checked relations with
     positive, same-scope negative and compiled-consumer evidence;
   - one registered-scope central closure that discharges every condition in
     `evidence/trust12/runtime-link/tail-preparation/tail-obligations-v1.json`
     other than the independent assurance, resolves every finding that blocks a
     discharged condition, disposes the other recorded findings and names every
     assumption that remains (ledger row `REGISTERED-CENTRAL-CLOSURE`);
   - fresh independent assurance on inputs frozen by a final input seal, which
     binds that closure.
2. General runtime-to-model correspondence in each declared profile, that is a
   discharge of the `runtime_link` and `runtime_link_spec` locale assumptions
   for every declared execution, is deferred research. TRUST 1.2 completion
   does not require it. The three ledger rows that track it keep their declared
   profile scopes and closure contracts, and a verified general proof can still
   close each of them.
3. The permitted claim does not change: "mapped implementation evidence;
   end-to-end refinement incomplete". Completion of TRUST 1.2 adds the sentence
   "TRUST 1.2 is complete within the registered-execution scope." The
   end-to-end completion sentence still requires every general connection and
   the central end-to-end ledger.
4. The 2026-09-25 completion direction, which made the general correspondence
   mandatory for TRUST 1.2, is kept in `supersededCompletionDirections` as
   history.
5. `scripts/lib/trust12-policy.mjs` checks the accounting of this decision. A
   closed registered closure must be a non-fixture record bound to the final
   profile runtimes, source inventory, ABI, admitted formal root, the closure
   row's condition and the pinned conditions list. It may cite as evidence only
   passing checkpoint records whose public rehash verifier the required gate
   runs, and it must name the pinned assumptions: the open assumptions of the
   central end-to-end ledger and `A-KEVM-TOOLCHAIN`, under which K, KEVM and
   Kontrol with its backend are trusted to produce the registered
   certificates. The fresh assurance report must cite a final input seal. The
   policy check does not replay kernel evidence: the saved-mode verifier of
   each checkpoint and the fresh independent assurance do, and a committed
   record is trusted only after review.

## Why

The remaining registered-scope conditions are recorded in
`tail-obligations-v1.json` as concrete inputs, checks and acceptance criteria.
A general proof for every declared execution additionally needs a checked
receiver of arbitrary EVM executions in Isabelle, which the source and tool
interface inspection did not find
(`evidence/trust12/runtime-link-source-blockers.md`), and a proof replay that
fits the public proof job. Neither is available, so the cost of the general
proof has no measured bound, and every change to the source, ABI or runtime
would reopen it. Defining TRUST 1.2 completion at the registered scope keeps
every claim exact and keeps the general proof open as research instead of as
an unbounded release prerequisite.

## Alternatives considered

- Keep the general correspondence mandatory for TRUST 1.2 (the 2026-09-25
  direction). Rejected: the completion date would depend on research whose
  cost has no measured bound.
- State the general theorem conditionally on the external symbolic execution
  engine. Not adopted: it moves the trusted base to that engine's results
  without removing the missing receiver, and it is not needed for the
  registered-scope claim.

## Consequences

The release policy schema becomes `trust12-release-policy-v3`. The three
general rows become `RESEARCH-RESIDUAL` with `requiredForTrust12Completion`
false and a deferral that names this decision. A new mandatory row
`REGISTERED-CENTRAL-CLOSURE` tracks the registered-scope central closure. The
policy check separates TRUST 1.2 completion from full end-to-end refinement,
reports `ASSURANCE_PENDING` while closed evidence waits for the fresh
independent assurance, requires the three disclosures to state the deferral
while any general row is deferred, and rejects completion wording in the
public documents while TRUST 1.2 is open.

## Reopen when

- a separate decision resumes the general correspondence;
- a counterparty or reviewer requires a general runtime-to-model theorem for a
  frozen release;
- a checked receiver of arbitrary EVM executions becomes available with a
  measured replay cost.
