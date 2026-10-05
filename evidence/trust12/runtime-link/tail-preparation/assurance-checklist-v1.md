# Independent Assurance checklist for the TRUST 1.2 runtime link

Status: prepared template. This checklist has not been executed. It becomes usable only after
every runtime-link cell, the malformed branch of each profile and the central closure artifact
exist and a seal with status `SEALED_FOR_INDEPENDENT_ASSURANCE` has been produced from them.

The checklist implements the four independent checks of the central refinement closure. The
frozen inputs, reproduction commands and reuse conditions are defined by
[the seal specification](assurance-input-seal-spec-v1.json) and validated against
[the seal schema](assurance-input-seal-schema-v1.json).

## Who may run it

1. The assessor has not taken part in any Building session of this runtime link and does not
   reuse an agent, a transcript or a conclusion of one.
2. The assessor reads only the sealed inputs. Handoffs, status summaries and chat reports are
   not inputs.
3. The assessor never edits a sealed file. Any change returns the work to Building and needs a
   new seal.

## Before the checks

1. Verify the seal against the bound roots and record the output:

   ```
   python3 scripts/trust12/tail-preparation/assurance_seal.py verify --seal SEAL --root PRODUCT=PRODUCT_CHECKOUT --root EVIDENCE=EVIDENCE_ROOT
   ```

2. Confirm that the seal status is `SEALED_FOR_INDEPENDENT_ASSURANCE`. A `TEMPLATE_DRY_RUN`
   seal ends the Assurance with the result "not started".
3. Install the toolchain exactly as pinned by the seal. Record the observed versions next to the
   pinned ones.
4. Select the declared replay scope before sealing and running the checks. This specification
   describes current-completion Assurance: verify every sealed result and native freshness,
   replay changed units and their affected consumers, and replay gate checks and selected
   top-level kernel consumers. The public product proof sessions still receive a clean replay.
   Each reused unit must satisfy all five reuse conditions of the seal. For a final frozen-source
   clean Assurance, prepare a separate specification and seal with `coldReplay: true` for
   `runtime-link-kernel-replay` and a command that executes every sealed kernel run without
   recorded heaps. Do not relabel or edit a current-completion seal as a final clean seal.
   Both scopes reuse the proof sources and tools; neither requires rebuilding the proof method
   from scratch.

## Check 1: reconstruction from the frozen specification

| Step | Action | Pass when |
| --- | --- | --- |
| 1.1 | Rebuild each conformance vector command, calldata and receipt from the kernel schema and generated ABI only | Every rebuilt observable equals the sealed vector |
| 1.2 | Rebuild the malformed input catalog from the kernel ABI and the generated bridge constants | The rebuilt catalog equals the sealed catalog byte for byte |
| 1.3 | Rerun the independent specification-only reproduction | Its receipt equals the sealed receipt |

## Check 2: reverse enumeration of obligations

| Step | Action | Pass when |
| --- | --- | --- |
| 2.1 | Build the sealed sources and enumerate every public and external selector of every profile runtime | The set equals the sealed route inventory, and every selector has a disposition |
| 2.2 | Enumerate storage variables and emitted events of every profile runtime | Each one is mapped in the state and receipt crosswalk or listed as runtime-only with a reason |
| 2.3 | Enumerate the obligation ledger rows and every theorem they cite | No orphan theorem, orphan code, unmapped route or unused lifecycle state remains |

## Check 3: removal negatives

| Step | Action | Pass when |
| --- | --- | --- |
| 3.1 | Replay every certificate-removal and consumer-removal negative cited by the ledger | Each negative fails at the claimed consumer |
| 3.2 | Rerun the declared mutation campaign and the semantic consumer removals | Every declared fault is killed by its declared detector |
| 3.3 | For each profile, disable one malformed guard at a time and rerun the malformed probe | The probe fails for every disabled guard |

## Check 4: recomputation of the central artifact

| Step | Action | Pass when |
| --- | --- | --- |
| 4.1 | Rebuild the obligation ledger from the sealed evidence | Every row status, count and hash equals the sealed ledger |
| 4.2 | Recompute the certificate registry with its saved-mode verifier from the sealed locator file and evidence | The rebuilt registry equals the sealed registry byte for byte; the coverage, distinctness, executed code identity, consumed world and acceptance checks pass; and the public registry record follows from the rebuilt registry |
| 4.3 | Recompute the central closure counts | No row is closed by a human-written table alone, and current mandatory rows are zero only if the recomputation says so |
| 4.4 | Recompute the route inventory with its saved-mode verifier from the sealed run records | The rebuilt inventory equals the sealed inventory byte for byte, and every state-changing route outside the typed commands has a disposition that a closed row or an accepted decision record justifies and a passed test executes |
| 4.5 | Recompute the typed failure records with their saved-mode verifier from the sealed run records and compiled artifacts | Every probe and mutant receipt and the load scan recompute byte for byte, every case is bound and every declared mutant unbinds its named cases |
| 4.6 | Recompute the call frame record of the requests outside canonical form with its saved-mode verifier from the sealed proof graphs and stage sources | The rebuilt report equals the sealed report byte for byte, no command segment enters a call frame, and every stage record supplies the empty external call list |
| 4.7 | Recompute the reflection scan with its saved-mode verifier from the sealed build information and the sealed scan report | The rerun scan equals the sealed report byte for byte, no state write or guard on the typed command paths is unclassified, the compiled layouts agree with the crosswalk, and every storage variable that the crosswalk leaves open has a reviewed reason whose writers equal the scanned writers |
| 4.8 | Rehash the bounded word guard mutant receipts with the saved-mode verifier of their record | Every receipt matches the public record, every witness of a detected mutant deviates, every witness of the equivalent mutant fails with the declared typed failure, and every other witness fails quietly |
| 4.9 | Recompute the storage reader record with its saved-mode verifier from the sealed session databases and build information | Every reader source equals the source its completed session database stored, every quoted clause, read form and comparison row follows from those sources and the crosswalk, and the struct member locations equal the compiled layouts |
| 4.10 | Recompute the registered gate record with its saved-mode verifier from the sealed session databases, run records and private certificate registry | Every quoted definition and theorem is stated with the same text and context in the source that its completed session database stored, every checkpoint and final audit marker holds, the session heaps form one chain from the aligned gate anchor, every recorded input file is unchanged, and the certificate list equals the private registry |
| 4.11 | Check the registered central closure record with its verifier against the sealed tree, and confirm that every saved-mode recomputation above covers a record that the closure cites | Every cited record is current and gated, every acceptance criterion is quoted from the sealed conditions list with fields that still hold, every finding is resolved with evidence, every retained assumption is named, and the role records and the ledger row bind the closure |

## Result record

The assessor writes one result document next to the seal, never inside it, with:

1. the seal root hash and the verification output of the seal before and after the checks;
2. the observed toolchain versions;
3. for every step above, the command, exit code, elapsed time, output hash and verdict;
4. the list of reused units with the evidence for each of the five reuse conditions;
5. a final verdict of PASS, or RETURN TO BUILDING with the failing steps.

A PASS verdict supports only the exact scope that the sealed central artifact names. It does not
extend to compiler correctness, deployment identity or external dependency behavior unless the
seal contains a separate closure for them.
