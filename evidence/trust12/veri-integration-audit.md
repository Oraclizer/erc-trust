# Veri integration review

Status: PASS for the named bounded observations and the checked summary instance.
The assembled general symbolic FREEZE positive is complete under the declared TCB. Whole-domain removal coverage and EVM-to-Isabelle correspondence remain incomplete.

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

The case20 operational CSE contains a `kore-rpc` EVM.jumpi.false edge followed
by a separate strict checked cover to the original target. Its WORD domain,
frame variables and export are preserved, with no added Ceil premise or trust
attribute. The caller requested `assumeStateDefined=false`; the installed proxy
sets true on its internal fallback execute. The fallback definedness boundary
remains undischarged. The first actual Native consumer was interrupted during
add-module before execute. The reviewed receipt therefore gives the CSE no
actual Native-consumption credit.

The original node99 SLOAD, push and PC-increment edges are distinct: their
stored rewrite origins are `booster`, and this route does not invoke that legacy
fallback execute. The value-zero simplification completed, but its detailed
simplification engine was not recorded.

This is a bounded source/artifact review, not independent full solver replay,
same-domain FREEZE guard-removal completion or an EVM-to-Isabelle receiver.
The four mandatory obligations remain open. Current curated evidence is
[native-storage-progress.json](native-storage-progress.json).

## Direct case20 frame review (2026-09-09)

A non-writing review checked the direct endpoint command, effective false
definedness setting, conditional and general-frame proof graphs, exported rules,
P3 conditions, typed frame paths and exact structural node148 substitution. The
general-frame rule has no local CHECK premise, Ceil, admission, circularity or
trust attribute. Its dynamic rewrite log reports an unknown rule identifier. The
structural substitution was not returned by a checker and was not used as a cover.
Accordingly this review does not claim actual node148 consumption.


## Current general symbolic FREEZE reception (2026-10-03)

The sealed assembled derivation covers both complementary supply branches for
positive uint256 first and second targets with second <= first. The test assumes
no first <= supply bound. Its state scope is the fixed constructor/dependency
mode and the seven named observations listed in veri-symbolic-results.json.
This is the assembled chain of original APR prefixes, checked summary
instantiations, native continuations and target subsumption under the existing
A-KECCAK/A-LAYOUT assumptions. It does not mark the original APR as a whole PASS.
The 512 selected results and five manifest commitments were rehashed on the
current saved files; the unchanged Native test source and runtime identity are
retained. The public receipt is a sanitized projection, not a byte-exact copy
of a private result or a replacement for its replay inputs.

The exact removal comparison retains the fourteen conditions of the symbolic
first <= SUPPLY branch. The original and removed controls have the same frame
except PC/K and diverge to PC11739 and PC11515. The matching compiled source
mutation is killed. This establishes consumer sensitivity in that branch; it
does not prove the supply-exceeding negative or the entire mutant transaction.
The ledger therefore retains its current completion requirement rather than
relabelling this branch as whole-domain negative coverage.

This review concerns saved source/result identity, declared scope and receipt
reception. It is a Building review, not fresh final Assurance or independent
full solver replay. General Native, Partial and Hook runtime correspondence
remain required.


## Supply-exceeding direction-guard negative (2026-10-04)

The complementary symbolic branch SUPPLY < first now has the same exact removal
comparison. A bounded standard step from the established branch state reaches the
same direction-guard jump with the same fourteen conditions; its 245 rewrites are
the prefix of the established 256-rewrite segment. Changing only the resolved
guard condition from one to zero keeps every other cell, the constraints and the
continuation. The original and removed controls diverge to PC11739 and PC11515
with the same frame outside PC/K, and the original branch rejoins the established
segment's exact final state after nine further rewrites. The two branch sources
share thirteen conditions and differ only in ?WORD <= 10^24 versus 10^24 < ?WORD,
so together they cover the declared positive two-target domain at this guard.

A compiled copy that removes only this guard was run against the original
rejection consumer at first = SUPPLY + 2 and second = SUPPLY + 1. The original
source passes; the mutant accepts the action, writes lifecycle APPLIED and a
nonzero receipt, keeps the same saturated visible floor and fails the original
consumer with "rejection wrote action". Both the symbolic chain and the compiled
pair are bound by native-supply-direction-negative-checkpoint-v1.json, whose full
mode rehashes the retained artifacts.

This qualifies the existing whole-domain removal requirement of the Native symbolic
obligation. It is not a proof of the complete mutant transaction, of compiler
correctness or of the general runtime links, and it is a Building review rather
than fresh final Assurance.
