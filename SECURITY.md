# Security policy

## Current status

ERC-TRUST is an unaudited research and reference candidate. The shipped
candidate is `0.1.0-candidate.2`; the successor under development on private
`main` carries the working label `0.2.0-candidate.1` and has no
tag or release. Neither is for production use. No deployed instance, fork, proxy,
migration, operator, key-management process, or downstream integration is
covered by this policy.

| Version | Security support |
| --- | --- |
| `0.2.0-candidate.1` (private main, no tag) | Reports accepted for evaluation; no patch service-level agreement |
| `0.1.0-candidate.2` | Reports accepted for evaluation; no patch service-level agreement |
| `0.1.0-candidate.1` | Superseded research candidate; unsupported |
| Earlier commits and forks | Unsupported |
| Deployments | Unsupported |

This table describes report handling, not a warranty or a promise that the
candidate is secure.

## Report a vulnerability privately

Use GitHub Private Vulnerability Reporting for this repository after it is
public:

1. Open the repository's **Security** tab.
2. Select **Advisories**.
3. Select **Report a vulnerability**.

While the repository remains private, contact the maintainer at
`jay@oraclizer.io` with the subject `ERC-TRUST SECURITY`. Do not include
secrets, personal data, production credentials, or unrelated private
deployment information.

Do not disclose exploit details in a public issue, Pull Request, discussion,
social post, or standards forum.

## What to include

Provide enough information to reproduce and assess the report:

- the exact commit, file, function, and profile;
- a minimal reproduction, failing test, proof counterexample, or transaction
  sequence;
- expected and observed state transitions;
- affected balances, records, nonces, events, or receipts;
- whether the issue crosses a declared claim or trust boundary;
- known preconditions and impact;
- suggested embargo needs, if any.

Good-faith reports that challenge the model-to-code mapping, fail-closed
behavior, authorization binding, route isolation, state-frame claims,
canonical receipt, profile topology, or verification harness are in scope.

## Handling

The maintainer will evaluate whether a report affects the candidate and may
request additional information. There is no guaranteed acknowledgement,
remediation, disclosure, or release timeline. There is no bug bounty or
financial reward program.

If a report is accepted, the maintainer may coordinate a fix and disclosure
through a draft GitHub Security Advisory. Credit may be offered in the
advisory or release notes when requested and appropriate.

Public design questions, non-sensitive specification ambiguities, and ordinary
bugs may use the issue tracker after the repository becomes public.

## Verification and audit boundary

The successor Foundry, Kontrol, mutation, deterministic-build,
runtime-binding, obligation-ledger, and Isabelle results apply only to their
exact source, runtime, harnesses, assumptions, and claim boundaries. The
successor Certora lane is pending and no successor source has been sent to the
cloud prover; published Certora receipts under `evidence/candidate-2/` describe
different historical bytes. None of these results is an independent security
audit or covers deployments or external legal and factual truth.

See:

- [Verification summary](evidence/verification-summary.md)
- [Known limitations](evidence/known-limitations.md)
- [Public claim matrix](evidence/claim-matrix.md)
- [Disclaimer](DISCLAIMER.md)
- [Formal verification and refinement map](FORMAL_VERIFICATION.md)

## Legal

The current implementation, SDK, tooling, and formal artifacts are provided
under the BSD 3-Clause License, including its warranty disclaimer and
limitation of liability. The proposed ERC text is under CC0, and four
byte-bound historical pilot source files retain file-level MIT headers, as
listed in the README. This policy does not expand any license, create a
support contract, or make a representation about security, fitness, legal
compliance, or production readiness.
