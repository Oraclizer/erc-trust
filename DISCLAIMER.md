# Disclaimer

ERC-TRUST is a pre-ERC interface and reference candidate for typed,
fail-closed regulatory actions and recomputable receipts for security tokens.
This document states in plain language what the candidate establishes and
where its boundaries are. For BSD-covered software and artifacts, the
[BSD 3-Clause License](LICENSE) controls the legal warranty and liability
terms and is not modified or expanded here. The proposed ERC text is under
CC0, and four byte-bound historical pilot source files retain file-level MIT
headers, as listed in the README.

## What the evidence establishes

- The bounded verification results (Foundry tests, fuzzing, invariants,
  Certora rules, KEVM claims, and Isabelle sessions) apply to the exact
  candidate, rules, harnesses, assumptions, and artifacts identified in the
  evidence package, and can be replayed from the repository.
- The verified properties and their exact scope are listed in the README
  assurance snapshot and the claim matrix under `evidence/`.

## Boundaries

- This is research and reference software: unaudited, unreleased, and not
  for production. No ERC number is assigned, and no contract here is claimed
  as deployed.
- Verification covers the exact bytes it names. Forks, modifications,
  compiler or dependency changes, and deployments require their own review
  and evidence.
- ERC-TRUST records and binds inputs about authority, policy, identity,
  settlement, proceeds, entitlement, and ownership; the software does not
  prove that those external claims are true, legally valid, current, or
  enforceable in a particular jurisdiction.
- Nothing in this repository is legal, regulatory, tax, investment, or
  operational advice.
- As with any smart-contract system, defects, misunderstood assumptions,
  compromised keys, dependency failures, or integration errors remain
  possible. Verification and testing reduce the named risks and no others.

Do not use this candidate with assets, rights, production systems, or real
users.
