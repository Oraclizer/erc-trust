# Isabelle/Solidity applicability assessment

Candidate: `0.1.0-candidate.1`

Assessment date: 2026-07-28

Disposition: **NOT APPLICABLE to the reference-implementation evidence package**

This disposition is not a failure of Isabelle/Solidity and does not change the
PASS status of the preserved abstract `ERC_TRUST` Isabelle session. It means
that translating a small part of the current Solidity candidate into the
shallow embedding would not materially reduce the candidate's principal
model-to-implementation risks.

## Evaluated framework and source binding

The assessment used the official [Archive of Formal Proofs
entry](https://isa-afp.org/entries/Isabelle-Solidity.html) and the official
[current AFP archive](https://isa-afp.org/download/). The evaluated archive
had these exact properties:

| Property | Value |
| --- | --- |
| Downloaded archive | `afp-current.tar.gz` published as `afp-2026-07-21` |
| Archive SHA-256 | `544de82b35d1bb6aaa1923f11cdd50d702824a6e0601cd72ee7e43e5eca85d6f` |
| AFP version declared by the archive | `2025-2` |
| Isabelle runtime | `Isabelle2025-2` |
| Selected sessions | `Finite-Map-Extras`, `Isabelle-Solidity` |
| Build | clean `Isabelle-Solidity` session build with document generation disabled |
| Result | PASS |

Reproduction, after extracting the two selected AFP entries:

```text
$ISABELLE_HOME/bin/isabelle build -c \
  -d Finite-Map-Extras \
  -d Isabelle-Solidity \
  -o document=false Isabelle-Solidity
```

The framework is a manually written shallow embedding, not an importer from
Solidity source or compiler artifacts. Its published semantics and examples
cover storage, memory, calldata, mappings, arrays, arithmetic and comparison,
conditionals, loops, internal calls, an abstract external-call operation,
Keccak, exceptions, and weakest-precondition reasoning. See the
[AFP entry](https://isa-afp.org/entries/Isabelle-Solidity.html) and the
[authors' paper](https://logicalhacking.com/publications/marmsoler.ea-secure-smart-contracts-2024/marmsoler.ea-secure-smart-contracts-2024.pdf).

## Fit against the reference candidate

The security-critical reference behavior is concentrated in stateful code:

- `_validateActionShape`, `_applyActionPrepared`, and
  `_applyReversalPrepared`;
- `_consumeRoute` and exact-use self-call routing;
- versioned, code-hash-bound policy and registry calls;
- fail-closed decoding of gas-bounded low-level calls;
- nested action, reversal, custody, settlement, and entitlement records;
- revert stutter, deletion/closure, and exact final receipt-log ordering.

The candidate also relies on `abi.encode`, typed call encoding, custom errors,
runtime code hashes, assembly-assisted code/return-data inspection, and
Solidity/EVM event behavior. The inspected framework source does not provide a
source importer, compiler/code-generation relation, bytecode semantics,
returndata/canonical-decoding model, or an event/log semantics suitable for
the exact receipt-order obligation. External calls are represented
abstractly, so the candidate's malformed-return and operational-failure
boundary would need to be re-expressed manually.

The only readily isolated pure candidates are hash/mask helpers such as
`TrustDecision.nonceKey`, `actionMask`, `reversalMatches`, and
`isForcedTransferAction`, plus parts of `TrustPolicyBinding.compute`. Proving
manual translations of those helpers would be technically possible but would
not exercise the state transition, fail-closed dependency boundary, custody
closure, exact-use route, or receipt order. It would therefore add a
translation trust boundary without reducing a principal reference-implementation risk.

There is also a version boundary. The published embedding is described
against Solidity 0.8.25, while this candidate is compiled with Solidity
0.8.36, optimizer runs 1, via-IR, Cancun, and metadata disabled. Solidity
compiler and language changes are documented in the official
[release history](https://github.com/argotorg/solidity/releases) and
[changelog](https://github.com/argotorg/solidity/blob/develop/Changelog.md).
No equivalence between the embedding, the candidate compiler pipeline, and
the emitted EVM bytecode is established here.

## Evidence disposition

No reference-candidate Solidity theory was added because none of the available slices met both
conditions:

1. it contains a principal implementation-level risk; and
2. the framework can represent that risk without manually replacing most of
   the behavior being checked.

The applicable implementation evidence remains:

- Foundry unit, fuzz, and invariant checks for full concrete transitions;
- bounded Certora rules for storage, stutter, terminality, supply, transfer,
  interface, and mutator-inventory obligations;
- Kontrol/KEVM proofs over compiled bytecode for raw-selector closure,
  operational-failure stutter, and LIQUIDATE delta/final-log behavior;
- deterministic compiler-output hashes, mutation detectors, conformance
  vectors, and the release manifest.

## Trust boundary and forbidden claims

This assessment supports only the claim that the official framework was
evaluated, its selected session was clean-built, and it is not evidence-positive
for the current reference kernel. It does **not** support any of these claims:

- the Solidity implementation was verified in Isabelle/Solidity;
- the abstract `ERC_TRUST` model refines the Solidity or EVM implementation;
- compiler correctness or source-to-bytecode equivalence was proved;
- events, external dependencies, or legal/factual truth were verified by
  Isabelle.

Revisit this disposition if the implementation acquires a small,
security-critical pure execution kernel, or if a maintained framework adds
source import plus the required call, ABI, revert, log, compiler, and bytecode
relations.
