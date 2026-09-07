# TRUST 1.2 regulatory preservation source review

Status: PASS for the seven frozen model source files below.

This fresh read-only reviewer did not participate in their construction. The
review read each complete source and checked the manifest and source hashes at
the start, during review and at completion (2026-09-07T12:46:34Z). Main then
recalculated the seven hashes and re-read the identified model and Solidity
push/pop source. No model-source repair was requested.

## Inputs

| Source | SHA-256 |
|---|---|
| `formal/isabelle/ERC_TRUST/TRUST_Transaction_Refinement.thy` | `b49b9d7a71455e547bf5185fcd66195597b185bbb5d50441b281e37eabf60149` |
| `formal/isabelle/TRUST12_OBSTRUCTIONS/TRUST_State_Invariants.thy` | `1f05719150c9c1eac15ca417eb0516b738150077589da0fa827acb19cdc792fe` |
| `formal/isabelle/TRUST12_OBSTRUCTIONS/TRUST_Custody_Accounting.thy` | `bee1f0f5cbf68f91fa9c3ca92fb5851020dd272a61b13ce5db18ccc8c8044ce9` |
| `formal/isabelle/TRUST12_OBSTRUCTIONS/TRUST_Regulatory_Preservation.thy` | `77a5ccac16322ea85c35d968a40f53d786d2911254ddb7e6697659bea797b4fb` |
| `formal/isabelle/TRUST12_OBSTRUCTIONS/TRUST_Reversal_Preservation.thy` | `fcaa7178a21e63e077d303069ba80ef76cc8aef2c9e7440bc16921febf3e6aba` |
| `formal/isabelle/TRUST12_OBSTRUCTIONS/TRUST_Unfreeze_Preservation.thy` | `142a7302a0c9378b4d2631a5994b56cd32edd0330664364c59150a2c4e4f4654` |
| `formal/isabelle/TRUST12_OBSTRUCTIONS/TRUST_Release_Preservation.thy` | `bd67dc946e059fed4d779b4ca44d6e5ba7721a7e6f301ea06d8b08b38ca74eb6` |

## Findings

The invariant links active custody to the exact Applied SEIZE record and
connects overlay heads, subjects and open case heads in both directions. It
distinguishes historical effects from the live FREEZE chain. A historical
parent can be Reversed; a live chain member must be Applied. Pop advances the
head generation without changing the parent effect generation.

The forward and reversal results derive state_wf after the actual model update
from pre-state state_wf and admission. They do not assume the post invariant.
Account and case support can expand. FREEZE has no balance or supply ceiling.
RELEASE derives payment validity from custody coverage and backing bounds
separately from the arithmetic backing-preservation lemma.

## Execution observed

The reviewer directly read `out/trust12/all-reversal-state-wf.log` and its exit
file: child Finished in 81 seconds, 91 seconds total, exit 0. That log does not
itself bind all current source hashes or expose the root count. The fresh clean
build/input capture and formal admission remain a separate obligation.

## Required boundary and remaining validation

This is a bounded source-meaning review, not whole-project Assurance. The
current ROOT, controls, linked-run theory, final clean build and proof exports
were outside this review. Constructor/storage decoding, natural-number to EVM
word correspondence, ABI/overflow behavior and the runtime_link producer were
not established. state_wf is not a complete characterization of reachable TRUST
states and does not own all receipt, nonce, authority or dependency invariants.

The reviewer recommended typed controls for below/above-supply pushes and pops,
cross-family overlays, multiple custody cases sharing one custodian, direct and
custody disposition, and expanded support/self-transfer. Corrupted-state
fixtures must be labeled invariant-detection controls rather than reachable
attacks. Main owns their implementation, execution and subsequent review.

No file or Git mutation, build, remote action or paid computation was performed
by the reviewer. Review recommendations are advice; source and execution checks
remain Main responsibilities.

## Line-ending normalization

After the frozen review, Main changed the final CRLF of
`TRUST_Release_Preservation.thy` to LF. The exact reviewed bytes are reconstructed
by replacing the normalized file's final LF with CRLF.
`model-source-normalization.json` records both hashes and the reversible rule.
The theorem text is otherwise identical. The committed-source clean build will
bind the normalized source rather than rewrite the earlier review identity.
