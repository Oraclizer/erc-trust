# ERC-TRUST Preserved FREEZE Pilot : Verification Evidence

Date: 2026-07-28

Overall status: **PILOT CONJUNCT VERIFIED**

Repository: `Oraclizer/erc-trust`

Base revision: `23e5a3c777c3516d7864b9e36bd4a901d916534c`

The executable candidate described below passed Foundry, Certora, Kontrol,
deterministic-build comparison, and the five required negative mutations.
Public-label-only edits later changed comments, configuration messages, and
evidence labels without changing creation/runtime bytecode or CVL rule logic.
The containing Git commit binds the current source, ABI, bytecode,
specification, historical sanitized remote result, report, and hash manifest
in one tree. No fresh Certora or Kontrol run is claimed after the label edits.
The allowed completion statement remains `pilot conjunct VERIFIED` within this
qualified boundary.

## What the workflow establishes

- Foundry pins the Solidity compiler and settings, builds the exact pilot
  bytecode, and runs concrete plus fuzz tests.
- The historical Certora run checked the 13 declared quantified rules over
  contract states and inputs and completed with every top-level rule
  successful. Current CVL rule logic is unchanged; its file hash changed.
- The historical Kontrol run symbolically executed the compiled bytecode
  against KEVM as an independent semantic cross-check. The bytecode is
  unchanged; a harness comment changed its file hash.
- Five temporary negative mutations demonstrate that the regression harness
  detects the declared route, frozen-floor, fail-closed, and receipt-order
  faults.

## Scope and claim boundary

The artifact is a non-production vertical slice:

`Native FREEZE -> exact-use staged setFrozenTokens -> ordinary-transfer gate -> canonical receipt`

It does not implement or claim:

- full IERC7943Fungible compatibility or `forcedTransfer`;
- production cryptographic authorization verification;
- full ERC-TRUST refinement;
- a frozen ABI;
- full reference-implementation completion or production readiness.

`trustProfile()` therefore returns `UNSUPPORTED` with the FREEZE action bit
only, and `supportsInterface` does not report the full IERC7943Fungible
interface ID.

## Reproducible toolchain

- Ubuntu WSL2, 16 GiB swap
- solc `0.8.36+commit.8a079791`
- Foundry/forge `1.7.1` (`4072e48705af9d93e3c0f6e29e93b5e9a40caed8`)
- certora-cli and Certora server `8.17.1`
- Kontrol `1.0.255`
- KEVM `1.0.678`
- EVM version `cancun`
- optimizer enabled, 200 runs, `via_ir=true`
- metadata bytecode hash disabled and CBOR metadata disabled

Certora uses `strict_solc_optimizer=true`, so certora-cli does not replace the
0.8.36 optimizer sequence with a separate proof-oriented sequence.

## Foundry and deterministic-build result

Commands:

```text
forge fmt --check
forge build --sizes
forge test --fuzz-runs 256 -vv
forge lint
```

Result:

- 13 tests passed, 0 failed, 0 skipped.
- `testFuzzOrdinaryGate` passed 256 runs.
- Runtime size: 18,914 bytes.
- EIP-170 runtime margin: 5,662 bytes.
- Four lint warnings remain, all for the intentional validity-window
  comparisons using `block.timestamp`; no lint errors were reported.

Two isolated clean builds produced identical artifact and bytecode hashes:

- `TrustFreezePilot.json`:
  `59b6275ff97e99baf45da3bf9ba7e563b57303cc7a76cfde56306a1a50f6ad71`
- `MockBoundPolicy.json`:
  `f223b2d8b77e97dd595cf915234715da2c27c17d9fb3a2cab4113a7883db5bf9`
- `TrustFreezePilot` creation bytecode:
  `ee570f5b42a2f11c8af53ab1e3be319c5b91383ead7f864bfeafa36d99c2b7f2`
- `TrustFreezePilot` runtime bytecode:
  `43daa22719f0c7d6bbc9612be2aff28889646a9a6072d5c0a2471ef367d02b29`

## Kontrol/KEVM result

Build and proof shape:

```text
kontrol build --foundry-project-root <pilot> --regen --rekompile
kontrol prove --foundry-project-root <pilot> --schedule CANCUN \
  --match-test <test> \
  --lemmas kontrol/erc-trust-log-assertions.k:ERC-TRUST-LOG-ASSERTIONS
```

Final proofs for the exact current bytecode:

| Proof ID | Result | Nodes | Pending | Failing | Stuck | Time |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `testKontrol_StagedFreezeEventOrder():7` | PASS | 71 | 0 | 0 | 0 | 4m 07s |
| `testKontrol_PolicyFailureStutters():2` | PASS | 52 | 0 | 0 | 0 | 3m 06s |

The staged proof checks the exact final log suffix: `Frozen`, followed by the
canonical `RegulatoryActionApplied` receipt event. The policy-failure proof
checks that the complete log cell remains the constructor `Transfer` only and
that the pilot state fingerprint is unchanged.

## Certora result

Command:

```text
certoraRun certora/TrustFreezePilot.conf
```

Final remote run:

- Output namespace: `10491299`
- Run hash: `3fbecc448ae64246b3d7fabac50dc74b`
- URL:
  <https://prover.certora.com/output/10491299/3fbecc448ae64246b3d7fabac50dc74b>
- certora-cli/server: `8.17.1`
- Process exit: `0`
- Prover terminal result: `No errors found by Prover!`
- Top-level result: 13 `SUCCESS`, 0 `FAIL`, 0 `SANITY_FAIL`,
  0 timeout, 0 unknown.
- Parametric mutator classification: all 9 instantiated external mutators
  `SUCCESS`.

| Top-level rule | Result |
| --- | --- |
| `direct_and_staged_freeze_converge` | SUCCESS |
| `rejected_assessment_reverts_and_stutters` | SUCCESS |
| `operational_failure_reverts_and_stutters` | SUCCESS |
| `wrong_route_caller_preserves_target_ticket` | SUCCESS |
| `wrong_route_calldata_preserves_target_ticket` | SUCCESS |
| `cancelled_ticket_cannot_be_used` | SUCCESS |
| `stale_binding_call_preserves_target_ticket` | SUCCESS |
| `consumed_ticket_cannot_replay` | SUCCESS |
| `transfer_respects_frozen_floor` | SUCCESS |
| `can_transfer_query_matches_balance_and_frozen_floor` | SUCCESS |
| `successful_transfer_frame` | SUCCESS |
| `transfer_from_respects_frozen_floor` | SUCCESS |
| `all_external_mutators_are_classified` | SUCCESS (9 instances) |

The routine gate uses `rule_sanity=basic`, which keeps Certora's
non-vacuity/trivial-invariant checks. Advanced sanity was used during
diagnosis, but it also classifies deterministic postconditions in contract
function bodies as tautological or redundant. It is therefore retained as a
diagnostic mode rather than the final pass/fail gate. No `prover_args`,
optimistic fallback, or always-allow summary is present in the final
configuration.

The final rules preserve the intended obligations:

- wrong caller, wrong calldata, and stale-binding calls preserve the exact
  target route ticket and its prepared record;
- cancelled and consumed tickets expose their exact terminal lifecycle and
  cannot be used;
- direct and staged FREEZE converge on the active pilot state projection;
- frozen-floor checks include over-frozen symbolic states;
- operational failure is selected through a deterministic live-vs-bound
  policy code-identity mismatch and must revert with full storage stutter.

## Negative mutation campaign

Each mutation was applied only to a separate temporary copy of the exact final
source. All five were killed by the expected detector:

| Mutation | Expected detector | Result |
| --- | --- | --- |
| Remove the ordinary frozen-floor gate | `spent frozen amount` | KILLED |
| Keep a consumed route ticket | `route not consumed` | KILLED |
| Reverse `Frozen` / receipt event order | `log != expected log` | KILLED |
| Remove exact caller/calldata route binding | `wrong caller succeeded` | KILLED |
| Allow operational failure to execute | `policy failure applied` | KILLED |

## Trust assumptions and residual risks

- `MockBoundPolicy` is an immutable test double, not a production policy.
- The pilot authorization proof is a digest echo, not a signature scheme.
- The custom K log adapter and CVL specification are part of the trusted
  verification harness and require human review.
- Basic sanity is the final Certora non-vacuity gate; advanced sanity remains
  diagnostic and is not being claimed as green.
- The containing Git commit and `hashes.json` bind the current pilot source,
  specification, configuration, artifact hashes, and historical evidence in
  one tree. The remote records retain their submitted hashes.
- No claim is made beyond this declared pilot conjunct.

## Completion gate

All technical proof lanes, mutation checks, deterministic-build checks, and
the containing-commit source/evidence binding are closed for this exact
candidate. The admissible completion statement is
`pilot conjunct VERIFIED`.

This closes only the preserved FREEZE pilot conjunct. It does not freeze the ABI,
discharge full TRUST-REF, verify a deployment, establish production readiness,
or decide full reference-implementation readiness. Those remain separate evidence layers.
