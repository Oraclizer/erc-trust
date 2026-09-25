# TRUST 1.2 release-evidence policy (unreleased)

Unaudited. Not for production. No deployment, proxy, migration, or external
legal/factual truth is verified. This file does not announce a release.

The 2026-09-13 release-scope reset is historical. Jay Kim's 2026-09-25 completion
direction requires general machine-checked runtime-to-model correspondence for
Native, Partial and Hook within each declared product scope. The current evidence
does not discharge those obligations. Verified Isabelle model evidence and scoped
compiled-code checks remain valid at their stated levels. The permitted claim is
"mapped implementation evidence; end-to-end refinement incomplete".

The ledger has seven components for each of Native, Partial and Hook. Each records
full declared-scope proof, limited-scope proof, execution tests/fuzz, or unverified;
the profile grade is its weakest component. Input/state scopes, tool pins, negative
kind, artifact bindings and scope review must accompany graded evidence.
The 21 component entries have now been scope-reviewed against current source,
historical receipts and compiled artifact bindings. Native, Partial and Hook each
have seven execution-test components. All three profile row grades are therefore
EXECUTION_TESTS, the weakest component grade. The three profile implementation-
evidence rows are closed within those scopes. No test or bounded proof was upgraded
beyond its original inputs, states or claims. The exact Certora CLI and server version
8.19.1 was recovered from the existing receipt; no new Certora execution occurred.
Existing Kontrol PASS records remain supplemental bounded evidence because their
receipt does not record the proof metadata required for a proof-grade classification.

TRUST 1.2 profile row grades: Native EXECUTION_TESTS; Partial EXECUTION_TESTS; Hook EXECUTION_TESTS.

Native symbolic FREEZE is still open in its original general domain, including
first targets above supply. The bounded alternative probe reused checked summaries
and advanced the exact state from program counter 7618 to 7619. Standard K/KEVM
single-step execution then timed out twice, once on the whole summarized state and
once on a smaller typed JUMP-decode frame, so the probe stopped under its approved
failure rule. The same-domain guard-removal negative was not run. Time spent cannot
close the proof. A shipping exception requires a separate Jay decision and leaves
the proof explicitly unproven, with a receiving process, responsible artifact,
closure evidence and resume condition. Existing parser and symbolic receiver work
is available for the mandatory general connection; no unproved producer is promoted.

TRUST 1.2 shipping exceptions: none.

`release-policy.json` records the historical and current decisions. `obligation-ledger.json` records
the 21 graded components, the open Native symbolic proof and the three mandatory
general connections separately from end-to-end proof completeness and public-release
authorization. `profile-implementation-evidence-review.json` records the scope
inventory, and `native-alternative-probe.json` records the bounded probe result.
The local proof-run inventory and the end-to-end product ledger have different
denominators and cannot substitute for these open TRUST 1.2 product obligations.
The verifier checks consistency of approval records; it does not authenticate human
authority or replace independent semantic review.
