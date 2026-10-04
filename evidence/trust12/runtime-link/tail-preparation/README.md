# TRUST 1.2 runtime-link tail preparation

Status: prepared, not closed. Nothing in this directory discharges a runtime-link cell, the
malformed branch, the acceptance partition, the central refinement closure or the independent
Assurance, and nothing here authorizes a merge, a release or a deployment.

The runtime link of TRUST 1.2 is organised as twenty-seven cells (three runtime profiles times nine
regulatory operations) plus the conditions that tie the cells together. This directory prepares
the inputs of those remaining conditions: the malformed branch of each profile, the certificate
registry and acceptance partition, the code identity of each profile, the route, state and
receipt crosswalks, and the frozen input seal of the independent Assurance.
[The obligation list](tail-obligations-v1.json) names, for each condition, the evidence a closure
needs, the prepared inputs, the acceptance criteria and the findings that block a closure today.

## Documents

| Document | Contents |
| --- | --- |
| [tail-obligations-v1.json](tail-obligations-v1.json) | The remaining conditions, their acceptance criteria and the blocking findings |
| [malformed-inputs-v1.json](malformed-inputs-v1.json) | Malformed input classes of the three endpoints and the concrete probe recipes |
| [code-identity-v1.json](code-identity-v1.json) | Runtime templates, immutable ranges and typed failure selector loads per profile |
| [route-inventory-v1.json](route-inventory-v1.json) | Every selector of the seven profile runtimes with its class and disposition |
| [state-receipt-crosswalk-v1.json](state-receipt-crosswalk-v1.json) | Abstract state and receipt fields traced to storage, ABI and events |
| [certificate-registry-schema-v1.json](certificate-registry-schema-v1.json) | Registry, partition coverage and certificate locator formats |
| [certificate-registry-schema-v2.json](certificate-registry-schema-v2.json) | Registry version 2: the executed code and runtime set of every certificate, the records that consumed each recorded world, the acceptance verdict and the locator format |
| [certificate-registry-checkpoint-v1.json](certificate-registry-checkpoint-v1.json) | Public record of the registry built from the private evidence: coverage, executed code, retained assumptions and the private registry and locator file by hash |
| [route-dispositions-v1.json](route-dispositions-v1.json) | One disposition record for every state-changing route outside the typed commands: callers, writes, reason, and the ledger rows, decision sentences, source lines and tests that cover it |
| [route-inventory-checkpoint-v1.json](route-inventory-checkpoint-v1.json) | Public record of the route inventory built in closure mode: every selector with its class and disposition, the evidence of every disposition, the recorded test results and probe rows, and the private run records by hash |
| [typed-failure-probe-mutants-v1.json](typed-failure-probe-mutants-v1.json) | Revert sites whose changed argument layout or selector must turn the named typed failure probe cases from bound into not bound |
| [typed-failure-checkpoint-v1.json](typed-failure-checkpoint-v1.json) | Public record of the typed failure probe, its mutants and the selector loads of a recorded isolated build: every recorded payload with its verdict, every mutant with the cases it unbinds, the loads of every runtime, and the private run records by hash |
| [reflection-dispositions-v1.json](reflection-dispositions-v1.json) | Reviewed dispositions: the reason and ledger rows of every storage variable that the crosswalk leaves open, the guards that no consumer snippet names, the Hook adapter writers with their own source text and the open items of the crosswalk |
| [reflection-scan-checkpoint-v1.json](reflection-scan-checkpoint-v1.json) | Public record of the reflection scan: every state write and guard on the typed command paths with its classification, the compiled layout counts, the storage dispositions, and the stored build information and scan report by hash |
| [malformed-word-guard-mutants-v1.json](malformed-word-guard-mutants-v1.json) | The bounded word guard mutants: the kind of check each one weakens and the outcome the word guard probe must observe |
| [malformed-word-guard-mutants-checkpoint-v1.json](malformed-word-guard-mutants-checkpoint-v1.json) | Public record of the word guard probe on the unmodified copy and on each mutant, with the private receipts by hash |
| [storage-reader-checkpoint-v1.json](storage-reader-checkpoint-v1.json) | Public record of the storage readers of the three profile manifests: the quoted reader clauses, the read form of every abstract field, the comparison with every crosswalk column, the open item that it closes, and the session databases that stored the reader sources by hash |
| [assurance-input-seal-schema-v1.json](assurance-input-seal-schema-v1.json) | Format of the frozen Assurance inputs |
| [assurance-input-seal-spec-v1.json](assurance-input-seal-spec-v1.json) | Bundles, toolchain pins, reproduction commands and independent checks of the seal |
| [assurance-checklist-v1.md](assurance-checklist-v1.md) | Procedure of the independent assessor |

The generated documents are rebuilt from tracked sources only: the kernel schema and ABI, the
formal runtime bridge constants and route tables, the formal state records, the conditional
central ledger and the runtime binding artifacts of the three profiles.

## Tools

All tools are in `scripts/trust12/tail-preparation`. They never run a prover and fail closed.

| Tool | Purpose |
| --- | --- |
| `prepare_tail.py` | Generates or checks every generated document, validates the obligation list, verifies a row map and writes the process return manifest |
| `malformed_inputs.py` | Builds the malformed catalog and the generated probe table from three sources that must agree |
| `code_identity.py` | Records the code identity of each profile and, with compiled artifacts, the typed failure selector loads |
| `route_inventory.py` | Enumerates and classifies every selector and checks the Native and Partial sets against the formal route tables |
| `state_receipt_crosswalk.py` | Traces the abstract fields to the storage of every runtime and the receipt to the ABI and events |
| `certificate_registry.py` | Builds and verifies the certificate registry and its partition coverage from an evidence-side locator file |
| `certificate_registry_v2.py` | Builds and verifies registry version 2 from an evidence-side locator file: the executed code and runtime set read from each recorded world, the kind of each record that consumed the world, and the acceptance verdict, recorded or recomputed from a stored proof graph |
| `malformed_call_trace.py` | Reads the call frames of each registered request outside canonical form from its stored proof graph and checks them against the call list the kernel stages supply |
| `reflection_scan.py` | Lists every state write and guard on the typed command paths from the solc build information of the exact tree, compares the compiled layouts with the crosswalk and checks every disposition against the build |
| `word_guard_mutation.py` | Rewrites an isolated copy of the sources so that one kind of bounded word is read without its decoder check |
| `run_word_guard_probe.py` | Runs the word guard probe and the malformed probe on an isolated copy, unmodified or with one declared mutant, and records the witnesses |
| `storage_reader.py` | Reads the storage readers of the three profile manifests from the reader sources or quoted clauses and compares their read forms with the crosswalk, the generated slot tables, the recorded-world theorems, the cell theorem statements and the compiled struct layouts |
| `kore_accounts.py` | Reads the accounts and the executing frame identifier of a KEVM configuration in KORE text form and fails closed on anything it does not recognise |
| `assurance_seal.py` | Seals and verifies the frozen inputs of the independent Assurance |
| `run_malformed_probe.py` | Runs the concrete malformed probe of the three endpoints in an isolated build directory |
| `route_inventory_v2.py` | Classifies every selector with the formal route tables and the Hook class table of decision 14, checks every disposition record against the tree and its recorded test runs, and closes only when every acceptance criterion of route exhaustiveness holds |
| `run_route_disposition_tests.py` | Runs the route disposition tests under `route-dispositions` in an isolated build directory and records the result |
| `typed_failure_report.py` | The fixed ABI reading of a typed failure report and its binding to the command and the sender, with the selector constants and reason codes read from the formal runtime bridge |
| `run_typed_failure_probe.py` | Runs the typed failure probe under `typed-failure-probe`, or one declared mutant of it, in an isolated build directory and judges every case with the fixed reading |
| `code_identity_v2.py` | Recomputes the typed failure selector loads from the compiled artifacts of a recorded isolated build and binds them to the runtime templates and the bound compiler inputs |

## Reproduction

Check the generated documents and run the tests:

```
python3 scripts/trust12/tail-preparation/prepare_tail.py check
python3 -m unittest discover -s scripts/trust12/tail-preparation -p "test_*.py"
```

With a fresh build in `out`, the compiled selector scan of the code identity is recomputed too:

```
forge build
python3 scripts/trust12/tail-preparation/prepare_tail.py check --artifacts out
```

The malformed probe needs the pinned Foundry and the pinned upstream token artifacts that
`scripts/prepare-trex-integration.py` builds. It copies the product sources into the given empty
directory, runs the three profile probes there and writes a receipt:

```
python3 scripts/trust12/tail-preparation/run_malformed_probe.py --product . --trex-artifacts out/trust12/trex/out --workdir WORKDIR --output RECEIPT_DIRECTORY
```

The public record of the certificate registry is checked against the tracked files alone, and its
negative controls run without private files:

```
python3 scripts/trust12/verify_certificate_registry_v1.py --metadata-only
python3 scripts/test-certificate-registry.py
```

With the private evidence root and the private index of the registry and its locator file, the
verifier rehashes both, rebuilds the registry in closure mode and requires it to equal the stored one:

```
python3 scripts/trust12/verify_certificate_registry_v1.py --evidence EVIDENCE_ROOT --artifact-index ARTIFACT_INDEX
```

The route disposition tests run in an isolated build directory like the malformed probe:

```
python3 scripts/trust12/tail-preparation/run_route_disposition_tests.py --product . --trex-artifacts out/trust12/trex/out --workdir WORKDIR --output RUN_DIRECTORY
```

The public record of the route inventory is checked by rebuilding the inventory from the tracked files with the
test results and probe rows it carries; its negative controls run without private files. With the private index of
the test receipt, its forge report, the malformed probe receipt and the stored inventory, the verifier rehashes them
and rebuilds the inventory from the private receipts:

```
python3 scripts/trust12/verify_route_inventory_v1.py --metadata-only
python3 scripts/test-route-inventory.py
python3 scripts/trust12/verify_route_inventory_v1.py --artifact-index ARTIFACT_INDEX
```

The typed failure probe and each of its mutants run in an isolated build directory; the selector loads are scanned
from the compiled artifacts of a build of the frozen sources in an isolated copy:

```
python3 scripts/trust12/tail-preparation/run_typed_failure_probe.py --product . --trex-artifacts out/trust12/trex/out --workdir WORKDIR --output PROBE_DIRECTORY [--mutant MUTANT_ID]
python3 scripts/trust12/tail-preparation/code_identity_v2.py --artifacts BUILD_OUT --build-record BUILD_RECORD --mode closure --output SCAN_FILE
```

The public record of the typed failure binding is checked by re-reading every recorded payload with the current reading;
with the private index of the run records and the compiled artifacts, the verifier recomputes every receipt and the scan:

```
python3 scripts/trust12/verify_typed_failure_binding_v1.py --metadata-only
python3 scripts/test-typed-failure-binding.py
python3 scripts/trust12/verify_typed_failure_binding_v1.py --artifact-index ARTIFACT_INDEX
```

The reflection scan reads the solc build information of a build of the exact tree and reports every write, guard and
disposition it cannot match:

```
python3 scripts/trust12/tail-preparation/reflection_scan.py --build-info out/build-info/*.json --out REPORT
```

The public record of the reflection scan is checked against the tracked files alone, and its negative controls run
without private files. With the private index of the stored build information and the stored scan report, the
verifier rehashes both, reruns the scan on the stored build information and requires the result to equal the stored
report:

```
python3 scripts/trust12/verify_reflection_scan_v1.py --metadata-only
python3 scripts/test-reflection-scan.py
python3 scripts/trust12/verify_reflection_scan_v1.py --artifact-index ARTIFACT_INDEX
```

The public record of the storage readers recomputes every read form and comparison row from the reader clauses it
quotes and the tracked crosswalk, and its negative controls run without private files. With the private index of the
session databases and the stored build information, the verifier rereads every reader source from the database that
stored it and recomputes the whole record:

```
python3 scripts/trust12/verify_storage_reader_v1.py --metadata-only
python3 scripts/test-storage-reader.py
python3 scripts/trust12/verify_storage_reader_v1.py --artifact-index ARTIFACT_INDEX
```

## Findings of the preparation

1. The typed entrypoints evaluate the domain and identifier rules, and by source order further
   kernel rules, before they validate every bounded word, so a request outside canonical form can
   end in a typed failure. The concrete probe observed this for every ordering recipe on all three
   profiles, without any external call, log or committed write. Decision 12 resolves it: the
   revert data of such a request and the order in which its defects are detected are not
   specified, and the formal relation classifies it as a full-state stutter.
2. Canonical calldata with a nonzero call value reverts with an empty payload. Decision 12
   resolves it: canonical form includes a zero call value.
3. Every other malformed recipe (short, long and trailing calldata, unknown selectors and every
   dirty bounded word) ended in an empty revert with no external call, log or committed write, and
   the well-formed controls confirmed that the probe observes those effects.
4. The Hook runtimes had no normative route classes; decision 14 classifies them, and the route
   inventory record shows every state-changing route outside the typed commands disposed. The reflection
   scan record gives a reviewed reason and ledger rows for every storage variable that the crosswalk
   leaves open, and the storage reader record compares the storage reader of each profile
   manifest with the crosswalk column by column.

## Integration accounting

The public tree accounting and the release manifest describe the whole tracked tree. This
preparation may write only its two directories, so the checks that compare those documents with
the tree fail on the preparation branch until the integration owner regenerates them once for the
merged tree. The process return manifest lists the added files and their hashes for that step.
