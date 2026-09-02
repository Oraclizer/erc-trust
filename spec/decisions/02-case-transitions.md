# Decision 02: case transition table

Status: frozen in kernel version 2 machine source (`caseTransitions`).
Native endpoint wired (`implementation/src/TrustToken.sol`, see
`08-native-wiring.md`); ERC-3643 profile wiring pending. Model wiring pending.

## Decision

A case is opened by its first applied command and is bound to that command's
family for its whole life: `FREEZE`, `RESTRICT`, `CUSTODY` (opened by `SEIZE`),
or `DISPOSITION` (opened and immediately closed by a direct `CONFISCATE`,
`LIQUIDATE`, or `RECOVER`).

1. A subject has at most one live head per overlay family across all cases. A
   `FREEZE` or `RESTRICT` whose subject already has a live head owned by a
   different open case is rejected (reason 10, `CASE_CONFLICT`). Overlays of
   different families (a freeze and a restriction) may coexist on one subject
   in different cases.
2. Within the owning case, a `FREEZE` amendment that strictly raises the
   absolute target is allowed and pushes a new head whose parent is the
   previous head. A second `RESTRICT` in its own case is rejected as no state
   change (reason 13).
3. A reversal reverses the subject's current live head only. After the pop,
   the case stays `OPEN` when the popped head's parent belongs to the same
   case (an earlier amendment is now the head), and becomes `TERMINAL`
   otherwise.
4. A `CUSTODY` case is closed only by `RELEASE` or by a custody disposition
   (`CONFISCATE`, `LIQUIDATE`, `RECOVER` consuming the whole custody record).
   A second `SEIZE` in the same case is rejected (reason 8).
5. A direct disposition is accepted only against a case with no prior
   command. A disposition against an open overlay case is rejected (reason
   10). A disposition in one case never clears an overlay owned by another
   case; the overlay stays live and its frozen target saturates at the
   current balance when observed.
6. A `TERMINAL` case accepts no action and no reversal (`TrustTerminal`).

The machine-readable table is `caseTransitions` in the schema; rules `CT-1`
to `CT-15` are the normative statement, and this record is the explanation.

## Why

Three traps existed in the shipped version 1 candidate.

- A reversal never checked case terminality. A `FREEZE` in case C followed by
  a `CONFISCATE` in the same case C made C terminal, yet the `UNFREEZE` of
  that freeze still passed, because the reversal path looked only at the
  action lifecycle. The abstract admissibility relation already required the
  case to be non-terminal, so the code was weaker than the model.
- Nothing stopped a disposition from being filed against an open overlay case.
  Once such a case was terminal, the overlay it contained could never be
  reversed. Rule 5 closes the entrance; rule 6 closes the exit.
- Overlay heads were stacked per subject across cases. A `FREEZE` in case Y
  on top of case X's live freeze buried X's freeze until Y was reversed, and
  the burial was invisible to a reader of case X. Rule 1 removes cross-case
  stacking. Amendments stay possible, but only inside the owning case, which
  matches the abstract model where a non-active subject may be acted on only
  by the case that owns its current mode.

Rule 3 follows the foundational semantics, where an unfreeze to a nonzero
target keeps the subject frozen and the case open, and only the return to the
active mode closes the case. The transaction-level refinement theory of
version 1 made every reversal terminal; it is generalized to rule 3 when the
model is rebound to version 2.

## Alternatives considered

- One applied action per case. Rejected: `SEIZE` followed by `RELEASE` or by a
  custody disposition is a legitimate multi-step case.
- Unlimited cross-case stacking with per-subject LIFO reversal (version 1).
  Rejected: it buries earlier cases silently and lets a later case block an
  earlier case's reversal.
- Reversal always closes the case, with no amendment chains. Rejected: raising
  a frozen target would then require an unfreeze followed by a new freeze in a
  new case, leaving the subject unfrozen between two transactions.

## Consequences

- `caseRecord(caseId)` replaces the version 1 `caseTerminal(caseId)` view and
  reports the phase, family, live head, and generation.
- `TrustTerminal` now carries the case identifier rather than an action
  identifier.
- The refinement ledger needs positive witnesses for every rule that admits a
  command and consumer-removal negatives for rules 1, 3, 5, and 6.

## Reopen when

- A regulatory workflow needs two open cases to hold live heads of the same
  overlay family on one subject at the same time.
- A profile needs a reversal that closes an amendment chain in one step; that
  profile must then define how the intermediate targets are recorded.
