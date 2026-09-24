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
| `assurance_seal.py` | Seals and verifies the frozen inputs of the independent Assurance |
| `run_malformed_probe.py` | Runs the concrete malformed probe of the three endpoints in an isolated build directory |

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
4. The Hook runtimes have no normative route classes, several storage variables have no recorded
   runtime-only reason, and the formal model has no per-profile storage reader yet.

## Integration accounting

The public tree accounting and the release manifest describe the whole tracked tree. This
preparation may write only its two directories, so the checks that compare those documents with
the tree fail on the preparation branch until the integration owner regenerates them once for the
merged tree. The process return manifest lists the added files and their hashes for that step.
