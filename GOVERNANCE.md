# Governance

ERC-TRUST is currently maintained by Jinwook Kim ([@jay-oraclizer](https://github.com/jay-oraclizer)) on behalf of Oraclizer. The project is in a
pre-standard candidate phase and has no elected governance body, token vote,
or delegated release committee.

## Maintainer authority

The maintainer controls repository access, issue triage, merge decisions,
candidate designations, tags, releases, and external standard submissions.
Opening an issue or Pull Request does not create an obligation to accept,
merge, publish, or respond within a particular period.

## Decision principles

Changes are evaluated against:

1. semantic correctness and compatibility with the typed action model;
2. fail-closed behavior and explicit trust boundaries;
3. interoperability value for independent implementers;
4. evidence quality and reproducibility;
5. minimal normative surface;
6. compatibility and maintenance cost;
7. claim honesty and public safety.

Normative changes should begin with an issue. Material interface, storage,
receipt, profile, or assurance changes require an updated draft, tests,
evidence mapping, and public rationale.

## Merge policy

Required checks must pass before merge. Code changes require tests and, where
relevant, updated formal or bounded verification evidence. Documentation-only
changes must pass link, public-surface, encoding, and repository-health checks.

The public signing baseline starts with the 2026-09-01 launch commit. Earlier
history predates that policy and may be unsigned. New commits on `main` are
squash-merged through GitHub and must display a verified platform signature;
unsigned contributor branch commits are not release identities.

The maintainer may request independent review before accepting security
critical work. A green check does not oblige a merge.

## Releases

A version tag and GitHub release must:

- identify an exact commit;
- bind the release manifest and candidate status;
- distinguish unaudited candidates from any future audited release;
- include relevant compatibility and security notes;
- never reuse or move an existing tag.

Candidate tags use `vX.Y.Z-candidate.N`; later stable tags use `vX.Y.Z`.
No other tag naming family is used.

The historical tag `v0.1.0-candidate.1` remains immutable. Candidate 2
(`0.1.0-candidate.2`) is the shipped reference candidate; the successor on
the integration branch carries the working label `0.2.0-candidate.1`. Tags and
GitHub Releases for either are separate maintainer actions whose current state
is shown by the repository's tag and Release records.

## Standards process

Repository governance is separate from Ethereum's ERC process. A repository
candidate, community discussion, or Pull Request does not imply Ethereum
editor approval, ERC assignment, Final status, audit, or production
endorsement.

Community feedback may change the draft and implementation. Accepted
contributors will be credited through Git history and, when appropriate,
release notes or security advisories.

## Amendments

This governance document may evolve as maintainers and independent
implementers join. Changes are recorded in `CHANGELOG.md` and remain subject
to the repository license and public claim boundaries.
