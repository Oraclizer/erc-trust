# Community review guide

ERC-TRUST is a pre-ERC standards candidate for representing and executing
typed regulatory actions without collapsing legal meaning, token mechanics,
and implementation assurance into one opaque privileged call.

> [!WARNING]
> The candidate is unaudited and not for production. No ERC number, deployed
> address, external audit, or production designation is claimed.

## Review scope

The draft defines six actions: freeze, seize, confiscate, liquidate, restrict,
and recover. Unfreeze, release, and unrestrict are separate reversals. A
request binds its authority and authority epoch, its case, the endpoint's
current dependency root and epoch, its nonce and validity window, its
provenance commitment, and its action-specific commitments. A case transition
table fixes what a second command in a case means and when a case can never
be reused. Successful execution ends with a recomputable receipt that actions
and reversals share.

The reference candidate demonstrates two mechanisms:

- an immutable native token with four read-only dependencies folded into one
  dependency root and an exact-use, same-transaction ERC-7943 route ticket;
  and
- an ERC-3643 adapter that is Full only under a sealed exclusive-Agent
  topology with a declared initial state and owned upstream state.

The design deliberately does not claim that a commitment proves legal title,
identity, settlement completion, proceeds, entitlement, or ownership truth.

## Questions for standards reviewers

1. Is the six-action vocabulary sufficiently precise without embedding
   jurisdiction-specific legal conclusions?
2. Should the base interface contain only typed action and reversal execution,
   with ERC-7943 wrappers kept in an optional interface?
3. Which receipt fields are essential for cross-implementation comparison?
4. Should deployment profiles be normative, informational, or maintained as a
   separate conformance document?
5. Are rejection and operational failure separated clearly enough for
   interoperable relayers and monitoring systems?
6. Do the action-specific custody, terminal-case, settlement, proceeds, and
   entitlement rules expose any unintended legal interpretation?
7. Is a single dependency root with a global epoch the right granularity for
   stale-command invalidation, or should some profiles bind per-kind epochs?
8. Should the kernel stay free of a delegation surface, leaving delegation to
   the registered authority account?

## Questions for implementation reviewers

1. Does the ERC-7943 ticket bind every value needed to prevent confused-deputy,
   reuse, altered-calldata, and direct-selector paths?
2. Is exclusive adapter Agent, inert owner, exact upstream runtime code hash,
   and sealed registry/compliance topology an adequate minimum for an
   ERC-3643 Verified Full profile?
3. Which additional stateful invariants or negative mutations would most
   increase confidence?
4. Are receipt pre-state and post-state observations sufficient for
   independent reconstruction?
5. Which deployment, signer, relayer, and monitoring risks should a future
   operational profile standardize?

## Evidence available for review

- [Pre-ERC draft](ERC-DRAFT.md)
- [Architecture and trust boundaries](ARCHITECTURE.md)
- [Conformance profiles](PROFILES.md)
- [Formal verification guide](../FORMAL_VERIFICATION.md)
- [TRUST-REF matrix](../evidence/trust-ref-matrix.md)
- [Public claim matrix](../evidence/claim-matrix.md)
- [Verification summary](../evidence/verification-summary.md)
- [Known limitations](../evidence/known-limitations.md)
- [Release manifest](../evidence/release-manifest.json)

Answers to the open questions above are welcome through the Specification
issue form; a review that spans several questions can arrive as one issue.
Reviewers should cite the exact commit and evidence row they are evaluating.
Passing a bounded row must not be generalized into a full-system, legal-truth,
deployment, audit, or production-safety claim.
