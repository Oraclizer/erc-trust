# Theorem-grade row bundles

This directory defines the repository-owned interface for discharging one
end-to-end refinement obligation at a time. A row bundle is intentionally
narrow: it names one obligation, one unchanged positive claim, one executable
semantic mutant, one reverse-checked bridge, and one named Isabelle theorem.
It never changes the central obligation registry or proof ledger directly.

Each bundle must provide:

- `bundle.json`, conforming to `schema.json`;
- an exact-runtime KEVM claim whose configuration uses the pinned generated
  runtime macro;
- a reachable semantic mutant that leaves the claim unchanged and fails with
  a named witness;
- a row-local generated bridge and independent reverse checker;
- a named Isabelle theorem and a clean child-session build report;
- `run-row-bundle.sh` replay output with zero admitted, stuck, vacuous,
  pending positive states, or backend-error states. An expected-negative proof
  may retain fail-fast pending branches only when it also records the exact
  pending count and a named terminal semantic counterexample.

Validate a descriptor before any proof run:

```bash
python3 formal/kevm/row-bundles/validate-bundle.py \
  formal/kevm/row-bundles/art-02/bundle.json
```

`run-row-bundle.sh` owns KEVM replay. It requires explicit positive and
negative definition directories, disables Booster, uses one worker, and writes
all saves, temporary files, and logs below a caller-selected output directory.
The runner rejects cancellation, timeout, backend errors, crash markers,
stuck nodes, vacuous nodes, admitted claims, and any graph count that differs
from the row contract.

Kompile records the absolute K source path in `Source(...)` metadata and may
emit a different `compiled.json` rule order across fresh compilations. A
bundle therefore pins the exact coordinator-approved compiled definition used
by its authoritative replay; the generated K source, row bridge, claim, and
reverse checker remain the repository-portable reconstruction boundary. A
definition freshly compiled in another worktree is a new identity and must not
be silently substituted for the pinned replay input.

On success, the runner copies the proof, KCFG, log, analysis, negative terminal
witness, bridge check, schema check, and Isabelle closure report into the
explicit repository-owned curated evidence directory. The final report binds
every copy plus the definition, claim, bridge, theory, manifest, closure, and
executed runner identities. `verify-curated-evidence.py` reverse-checks those
paths and hashes independently.

Only the coordinator may promote a passing report into the shared obligation
index and proof ledger. Preview that exact promotion first, then write it and
rerun the global verifier:

```powershell
node scripts/bind-row-discharge.mjs ART-02 `
  evidence/end-to-end-refinement/row-bundles/art-02/replay.json
node scripts/bind-row-discharge.mjs ART-02 `
  evidence/end-to-end-refinement/row-bundles/art-02/replay.json --write
node scripts/verify-end-to-end-evidence.mjs
```

The binder refuses FAIL-05, already-discharged rows, candidate reports, stale
runner identities, open graph branches, admitted proofs, backend-error
negatives, and missing named-theorem closure. The global verifier then checks
all promoted row artifacts and their exact ledger binding independently.

`bootstrap-row-proof.sh` is diagnostic-only. It can discover a claim ID and
freeze a serialized graph shape before a bundle is finalized, but it always
labels its report `DIAGNOSTIC_ONLY` and `dischargeEvidence: false`. A final
`run-row-bundle.sh` replay must use a fresh save directory.

`analyze-row-proof.mjs` is kept separate so its rejection behavior can be
tested without running KEVM. Run:

```powershell
node formal/kevm/row-bundles/test-analyzer.mjs
```

The already-discharged FAIL-05 proof structure is the design pilot for this
interface and must not be repeated. `art-02` is the first independent non-FAIL
consumer and demonstrates that the pipeline is not special-cased to FAIL rows.

## ABI-04 dynamic-offset S1 wave sources

The ABI-04 bundle remains OPEN. Its frozen-graph S1 replay is coordinated by
`abi-04/dynamic-offset-v1/run-dynamic-offset-wave-v1.mjs`, which consumes the
generated exact replay index, limits heavy KEVM concurrency to two, and
requires both the JS leaf analysis and independent Python verification for all
12 replays. `bind-dynamic-offset-wave-v1.mjs` may create six S1-only pair
binders only after that exact set passes. `reverse-check-dynamic-offset-wave-v1.mjs`
replays both verification paths and checks the binder exact set independently.
None of these sources grants ABI-04 central credit; dynamic length, high bits,
symbolic coverage, the 162-replay matrix, aggregation, Isabelle, and independent
row replay remain separate gates.

## Wave 2 recovered no-credit packages

The current tree also owns proof-free inputs for ACT-01, STATE-05, REV-01, and
REV-02. ACT-01 has canonical and state-restoration-control parse-only receipts;
STATE-05 has a current-runtime parse-only receipt and an unbuilt row-local
Isabelle target; REV-01 has the target-versus-enforceable-floor meaning
contract; REV-02 has a proof-module-safe claim with a current-runtime parse-only
receipt. `scripts/run-m4-row-parse-only-rebind.ps1` reproduces the K dry-run
boundary and `scripts/verify-m4-wave2-rebinding.mjs` checks all current bindings.

These artifacts grant no proof or row credit. ACT-01 produced a concrete
successful wrapper feasibility/state capture, but its v1-001 through v1-004
proof attempts exposed one repeated upper failure class: an underconstrained
whole-transaction initial frame.
`evidence/end-to-end-refinement/row-bundles/act-01/attempt-history-freeze-v1.json`, the
fresh read-only audit, and the 82-step target-first canary preserve the exact
credit-zero stop. The canary is `RETRY_FORBIDDEN`: 26 zero-to-nonzero keys are
not bound to zero initially, call-depth/call-gas/default-account cells are not
fully represented, and the normalized Legacy envelope must not be called the
exact captured DynamicFee transaction. No v1-005 command manifest or output
reservation exists. STATE-05 lacks both runtime halves and a built
Isabelle theorem, REV-01 lacks target-zero/above-balance witnesses and
distinguishing mutations, and REV-02 lacks backend proof, control compilation,
Isabelle closure, and independent replay.

ABI-04 high-bits feasibility is now executable with
`abi-04/run-high-bits-feasibility-v1.mjs`. The current receipt covers all 45
high-bit cases across six endpoints: 30 native cases use one free target
mutation plus a derived companion ID, and 15 profile cases use the target-only
typed-decoder relation. Every case has a successful canonical control, exact
empty typed rejection, zero custom-error selector, failed-transaction storage
and committed-log stutter, and a legalized post-target milestone. The result is
bound by `evidence/end-to-end-refinement/m4-runtime-freeze-v1.json`; it remains
feasibility-only and grants ABI-04 central credit zero.

The source-level process, exact-set, closure, and credit-boundary invariants can
be checked before generated descendants are materialized:

```powershell
node formal/kevm/row-bundles/abi-04/dynamic-offset-v1/reverse-check-dynamic-offset-leaf-v4.mjs --source-only
```

This command executes no proof and grants no S1 or central credit.

### ABI-04 corrected prove/certify/attest boundary

ABI-04 keeps semantic proof, proof certification, and build provenance as
three separate gates. SHA-256 bindings establish exact input/output identity;
they do not establish that a claim is semantically true. KEVM and Isabelle
remain the semantic proof boundary, while the JS/Python closure verifiers and
receipts are provenance checks.

Before any heavy replay, `anti-drift/generate-closure-manifest.mjs` freezes the
complete scoped node path/hash set and every required policy edge with both
parent and child hashes. The independent JS and Python implementations reject
an extra allowed-extension file, a missing node or edge, duplicate identities,
and any frozen/actual mismatch. `anti-drift/test-closure-fail-closed.mjs`
regression-tests both an unexpected node and a changed parent; both must exit
nonzero and invalidate the reachable descendants.

The static ABI-04 pipeline currently runs in full rather than trusting the
stage impact approximation. It materializes twice, performs all clean and
reverse checks, and then removes generator-owned outputs in two fresh isolated
repository roots and rebuilds them. Both roots must be byte-identical to each
other and canonical. This is same-toolchain fresh-root repeatability, not a
claim of reproduction by an independent builder.

The S1 wave also has a proof-free `--preflight` mode. It binds a frozen POSIX
Node/Python/Bash/KEVM/K/kore-rpc contract, verifies the closure receipt, and
prints the exact command for all 12 leaves without starting KEVM. `--run`
performs the same preflight before creating any heavy-proof job.

The current 69 finite + 12 symbolic positive/negative exact-replay contract is
unchanged. Replacing repeated heavy replays with a stronger parameterized ABI
rejection theorem and generated specialization certificates requires a
separate reviewed methodology change; until then, no replay or obligation may
be deleted, merged, or weakened.

## ACT-01 trace/basic-block redesign diagnostics

The earlier `RETRY_FORBIDDEN` label froze one defective whole-transaction
attempt class; it was not a permanent ban on changing the proof topology. The
current redesign keeps all 79 obligations and splits execution at boundaries
that are present in both a successful Anvil steps trace and KEVM's actual
basic-block/call stop set.

`act-01/run-read-footprint-trace-v1.mjs` captures the trace boundary stack,
memory, storage, call context, and adjacent opcode metadata.
`act-01/generate-concrete-boundary-canary-v1.mjs` produces exact positive
topology canaries. With `useGas=false`, it preserves `#gas(_VGAS)` and
`_VMEMUSED`; observed Anvil gas and memory sizes remain metadata.
`act-01/compose-concrete-boundary-canaries-v1.mjs` batches independent claims
into one K module so the fixed parser cost is paid once per family batch.
`act-01/sitecustomize.py` records RPC pre-send and response events separately,
and `act-01/run-request-lifecycle-canary-v1.sh` records resource and KCFG
progress under a bounded execution contract.

Execution `CURRENT-PROFILE-ACT01-CONCRETE-CHAIN-BATCH-039` closed both positive concrete
segments `PC 13431 -> 15224` and `PC 15224 -> 13465`. Each proof has 5 nodes,
3 edges, no pending/failing/terminal/bounded/stuck/vacuous states, and
`admitted=false`. The first target and second initial configuration match in
all 26 explicitly owned boundary cells. The archived run output file-set
SHA-256 is
`10785de720f24c43b99ac07aaf0b84b2fec6b3458d85d7863a79365a20867b6b`.

This is a positive concrete topology result only. It grants no ACT-01, family,
or central credit. Credit still requires a sparse-owned/shared-frame universal
contract, same-entry distinguishing negatives, all adjacent segments, an
explicit composition theorem and row corollary, exact artifact/runtime
binding, an approved TCB profile, and independent replay.

The current `dependencies.lock.json` declares authoritative Kore RPC with
Booster disabled, whereas these no-credit canaries use Booster and
`assume-defined`. Do not rewrite the existing lock in place. A separate TCB
addendum/profile and row-by-row requalification decision are required before
any redesigned proof is credit eligible.

### Native Full Core superseding disposition

The Director-approved Core redesign supersedes continued manual expansion of
the ACT-01 concrete basic-block chain. Executions 033 and 039 remain preserved
performance and topology canaries; they are not the root of the production
proof DAG.

The current authority is
`evidence/end-to-end-refinement/m4-core-refinement-scope-v1.json`. KEVM owns
seven reusable packages with 22 universal canonical claims and eight mutation
lanes:

- C0 State/ABI normal form;
- C1 authorization and replay;
- C2 bound-dependency assume/guarantee;
- C3 exact-use route;
- C4 forward financial effects;
- C5 reversal and LIFO;
- C6 transaction commit, rollback, and receipt.

ACT-01 is a Native FREEZE row corollary of C0/C1/C2/C3/C4/C6. A concrete PC
segment cannot grant credit. Every credit-bearing package requires a universal
positive, same-entry distinguishing negative, explicit frame and boundary
composition, no open or admitted proof state, an approved TCB profile, and a
fresh strict Kore replay. Certora owns the reusable compiled-bytecode financial
rules; Foundry and Halmos own counterexample and mutation preflight; KEVM owns
the exact EVM seams and final row corollary. Tool agreement without an explicit
Isabelle/K bridge remains layered assurance, not formal refinement.
