# Veri integration review

Status: PASS for the named bounded observations and the checked summary instance.
General symbolic FREEZE completion and EVM-to-Isabelle correspondence remain incomplete.

Separate source and raw-evidence reviews found two false-acceptance gaps in the first
Native detector: balance loss during FREEZE and a changed receipt source field could
remain internally consistent. Both were reproduced against compiled mutants and fixed.
The final controls additionally cover receipt state hashes and policy binding inputs.

Source, wheel and independently installed core files were compared byte for byte.
Native return data, mapping storage, event order, receipt preimages and revert writes
were independently recalculated. The stored freeze target remains the requested value
above supply; only the public observation saturates. The exact fresh rejection payload
includes the second command ID and direction reason 12.

The Partial and actual T-REX Hook observations keep their different inbound behavior.
Source-based entrypoint enumeration was followed by 35 additional named rejection
controls, repeated resynchronisation, and batch rollback after a real earlier Transfer
emission. These tests do not establish arbitrary-route or all-input refinement.

The summary instance was compared to the completed CSE rule, its actual 1-to-3
execution edge, all 37 source conditions, the unchanged program and seven input words.
Only five ground input variables are substituted. Command hash and amount remain
symbolic; label and priority changes are separately recorded.

Textual K transport failed before execution. The structured KRule/KFlatModule/Kore
path is the same conversion used for CSE. The module is explicitly selected for
execution. A 50-step instance replay returns to the 20,043-byte Native program at
PC 7821; the same starting state without the instance remains in the 772-byte
dependency at PC 18. Dynamic rewrite logs report an UNKNOWN unique ID, so the
consumption conclusion uses the explicit module, single added rule, equal-input
control and resulting programs, not an invented textual rule ID.

The later APR continuation did not complete. The last saved state has one pending
node and no failing node. This is neither a successful universal proof nor a checked
counterexample. The unchanged original graph and diagnostic copies are retained locally.

Curated entrypoints: [observations](veri-observation-results.json),
[symbolic development](veri-symbolic-results.json), and [library pin](veri-dependency.json).
The original abstract model, source-bound legacy evidence and existing runtime blockers
retain their separate validity. The four current mandatory obligations remain open.

## Native storage and operational CSE review (2026-09-09)

Independent non-writing reviews checked the finite-map queries, exact intermediate
predicates, strict Top/Top results, duplicate controls and total-term instances.
Main then rechecked the retained original proofs, both dependency CSE copies and
the actual SLOAD, push and PC-increment edges. A separate review rehashed all
789 retained inputs in native-storage-raw-inventory.json: no missing file or
digest mismatch was found. Returned RPC implications are normalized terms; the
original Ceil requests remain preserved separately.

The case20 operational CSE contains an actual EVM.jumpi.false edge followed by
a strict checked cover to the original target. Its WORD domain, frame variables
and export are preserved, with no added Ceil premise or trust attribute. The
first actual Native consumer was interrupted during add-module before execute.
The reviewed receipt therefore gives it no actual Native-consumption credit.

This is a bounded source/artifact review, not independent full solver replay,
same-domain FREEZE guard-removal completion or an EVM-to-Isabelle receiver.
The four mandatory obligations remain open. Current curated evidence is
[native-storage-progress.json](native-storage-progress.json).