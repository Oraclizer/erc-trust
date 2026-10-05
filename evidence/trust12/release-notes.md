# TRUST 1.2 release-evidence policy (unreleased)

Unaudited. Not for production. No deployment, proxy, migration, or external
legal/factual truth is verified. This file does not announce a release.

The 2026-09-13 release-scope reset and Jay Kim's 2026-09-25 completion direction
are historical. Jay Kim's 2026-10-04 completion direction defines TRUST 1.2
completion at the registered-execution scope: the verified Isabelle abstract model, kernel-checked
registered executions of Native, Partial and Hook bound to their exact compiled
runtimes, one registered-scope central closure that names its remaining
assumptions, and fresh independent assurance.
Of these, the abstract model, the kernel-checked registered executions and the
registered-scope central closure are recorded. The closure record
`registered-central-closure/closure-v1.json` discharges every gate, malformed-branch
and central condition recorded in `runtime-link/tail-preparation/tail-obligations-v1.json`
other than the independent assurance and names the assumptions that remain.
TRUST 1.2 is complete within the registered-execution scope.

Independent assurance. A reviewer who took no part in building this evidence checked it on
inputs frozen by the seal `assurance/trust12-runtime-link-assurance-seal-v2.json` and recorded a
PASS verdict in `assurance/trust12-runtime-link-assurance-seal-v2-final-assurance.json`. This was
an internal review by a non-participant, not a third-party audit. The review reran the product
build, tests and malformed input probes on the sealed commit and reused the mutation campaign of
its first attempt, whose implementation sources are byte-identical; recomputed the saved
verification records from the sealed inputs; checked a clean CI replay of the public product proof
sessions without saved heaps or databases on the sealed commit; and compared a rebuild of the
registered gate sessions and one cell session of each profile, made in its first attempt from the
same sealed sources over the recorded heaps of their ancestors, with their recorded results. Every
other recorded kernel result was accepted only after its stored bytes
matched the sealed manifest and a no-build run of the pinned Isabelle found it current for the
sealed sources. The internal runtime-link proof chain was not rebuilt in full from an empty heap
store.
General runtime-to-model correspondence in each declared profile is deferred research and is not required for TRUST 1.2 completion.
The current evidence does not discharge the general runtime links. Verified Isabelle model evidence and scoped
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

Native symbolic FREEZE is closed in its original general domain, including first
targets above supply. The assembled positive is complete under the declared
A-KECCAK/A-LAYOUT assumptions. At the direction guard, changing only the resolved
guard condition leaves the rejection path on both complementary supply branches with
the same constraints and frame, and the original branches rejoin established exact
states. A compiled copy that removes only this guard fails the deferred symbolic
test's rejection assertions when they are replayed concretely at one input above
supply. The complete mutant transaction is not claimed. The earlier bounded alternative probe, which timed out twice, is
retained as history. A shipping exception requires a separate Jay decision and leaves
the proof explicitly unproven, with a receiving process, responsible artifact,
closure evidence and resume condition. Existing parser and symbolic receiver work
is preserved for the deferred general connection; no unproved producer is promoted.

TRUST 1.2 shipping exceptions: none.

`release-policy.json` records the historical and current decisions. `obligation-ledger.json` records
the 21 graded components, the closed Native symbolic proof, the closed
registered-scope central closure and the three deferred general connections
separately from end-to-end proof completeness and public-release
authorization. `profile-implementation-evidence-review.json` records the scope
inventory, and `native-alternative-probe.json` records the bounded probe result.
The local proof-run inventory and the end-to-end product ledger have different
denominators and cannot substitute for these TRUST 1.2 product obligations.
The verifier checks consistency of approval records; it does not authenticate human
authority or replace independent semantic review.
