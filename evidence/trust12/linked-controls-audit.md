# TRUST 1.2 linked-run and control review

Status: PASS for the frozen inputs below.

A fresh reviewer read the linked-run theory, both control theories, their
underlying definitions, and the audit generator. All sixteen inputs matched
at the start, during review and at completion. No source defect was returned.
Other review conclusions were not used as evidence.

## Frozen inputs

| Input | SHA-256 |
|---|---|
| `formal/isabelle/TRUST12_OBSTRUCTIONS/TRUST_Linked_Run.thy` | `47813adc486ad97b256df3721baf792f0a59d6edd4906babf1eca4c1a0d88f68` |
| `formal/isabelle/TRUST12_OBSTRUCTIONS/TRUST_Structure_Invariant_Controls.thy` | `d9c5603ae6343151448e3fc97d2448fd0eda0c764d8868610f9bf5742e527bdc` |
| `formal/isabelle/TRUST12_OBSTRUCTIONS/TRUST_State_Interaction_Controls.thy` | `68c740c4e75fb0b95facc1c3bd174fb9959e6c0fbf3a74179d2f255d100afc4e` |
| `formal/isabelle/TRUST12_OBSTRUCTIONS/TRUST12_Obstruction_Proof_Audit.thy` | `e073c4787c450f41eaeb437e6e630995e082b3a2bf749958a0bc8e69208a9e68` |
| `formal/isabelle/TRUST12_OBSTRUCTIONS/ROOT` | `04a30338160d9f7cb8c725ff15e4e7acda46c1483a0650f26029d08d6bb8ac5d` |
| `scripts/generate-trust12-proof-audit.py` | `a749060fd8a192e82a3b7bb95074b2986cdcf661488a6e6d13ed474581783997` |
| `formal/isabelle/TRUST12_OBSTRUCTIONS/TRUST_State_Invariants.thy` | `1f05719150c9c1eac15ca417eb0516b738150077589da0fa827acb19cdc792fe` |
| `formal/isabelle/TRUST12_OBSTRUCTIONS/TRUST_Regulatory_Preservation.thy` | `77a5ccac16322ea85c35d968a40f53d786d2911254ddb7e6697659bea797b4fb` |
| `formal/isabelle/TRUST12_OBSTRUCTIONS/TRUST_Release_Preservation.thy` | `bd67dc946e059fed4d779b4ca44d6e5ba7721a7e6f301ea06d8b08b38ca74eb6` |
| `formal/isabelle/ERC_TRUST/TRUST_Transaction_Refinement.thy` | `b49b9d7a71455e547bf5185fcd66195597b185bbb5d50441b281e37eabf60149` |
| `formal/isabelle/ERC_TRUST/TRUST_Compositional_State.thy` | `ecb28da66b0ea1d1e1e4d05255a00246294d5ec9b5aafd320866af92c3ac880a` |
| `formal/isabelle/ERC_TRUST/TRUST_Concrete_Configuration.thy` | `642daa38742595bb7a00700b08b0a24d74e18d1239eb848f45e197c78ba5ce56` |
| `formal/isabelle/ERC_TRUST/TRUST_End_To_End_Composition.thy` | `dde2f9c95d702cf4f394dc3bde7e0e000203ba95698cfd7a8ba6569e59f8ccc5` |
| `out/trust12/all-model-controls-support-repair.log` | `bd119eb913f23303364c795d3aea522efc324b46bcb8494527fd68835bea2045` |
| `out/trust12/all-model-controls-support-repair.exit` | `13bf7b3039c63bf5a50491fa3cfd8eb4e699d1ba1436315aef9cbe5711530354` |
| `out/trust12/model219-export/TRUST12_Accounting_Obstruction.TRUST12_Obstruction_Proof_Audit/erc-trust/trust12-obstruction-proof-trust.txt` | `85fe1610f63a4a0922fab0f77cabf7058862e3fd3f008102d94448d75326dd51` |

## Meaning and control checks

The model step consumes existing admission and success-state definitions; it
does not assume the post invariant. linked_run checks its initial pre-state and
every adjacent post/pre state. The observation retains command kind, every
outcome and Applied-only success receipts, including the reversal command.

The reviewer checked the admitted Applied-to-Rejected, SEIZE-to-RELEASE-to-new
command, shared-custodian 40/60 release, and supply-100 freeze 60/140, two-pop,
new-case controls. The state-link deletion, outcome deletion, post substitution,
state-effect removal and malformed custody-reference fixtures consume their
actual predicates. They do not classify a syntax error or timeout as detection.

The concrete-run result remains conditional on runtime_link and connected
configurations. Its configuration relation uses transaction_post_configuration,
which changes the world while retaining the other pre-configuration fields.
An initial state_wf assumption is separately needed for the final invariant.

The reviewer independently enumerated the source without running the generator:
219 declared roots and 219 audit references, with no omission, addition or
duplicate. The qualified locale root is present. The actual export is PASS,
219 roots, 236 facts and zero oracle dependencies; the raw child build took
94 seconds, 104 seconds total, exit 0.

## Limits and final formatting

This is model-level source and control review. It does not establish an EVM
producer, constructor/storage decoder, runtime_link discharge, compiled-runtime
mutation result or reachable attack. Aggregate admission and the subsequent
committed-source clean build were outside this review.

After review, Main removed one trailing blank line from ROOT and normalized the
one CRLF after the final qed in RELEASE. model-source-normalization.json records
both hashes and the exact reversible reconstruction rules. The
reviewed bytes reconstruct exactly. No theory statement, proof,
session membership or option changed in those files. The separate clean-build
runner and CI use two threads and disable parallel proof processing.

The reviewer recommended one serialized clean build bound to the final inputs,
rather than repeating unchanged model meaning review or compiled-code proofs.
Hash drift, a missing theorem, nonzero build exit, an oracle dependency or an
input/export mismatch reopens the affected check. No reviewer writes, builds,
tests, Git mutations or external actions were performed.
