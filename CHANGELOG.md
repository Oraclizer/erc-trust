# Changelog

## Unreleased

- Align the installable SDK, receipt schema, evidence gates, and pre-ERC draft
  with kernel version 2. The package root now exports version 2 while the
  historical helper remains at `./v1`; continuous integration packs and
  installs the actual tarball before checking identifiers, calldata, and both
  receipt kinds. The 17-field receipt schema is generated from the kernel
  machine source and consumed against the generated Solidity struct and all
  action and reversal vectors. Kontrol and Certora receipts require nonzero
  exact proof or rule sets, exact inputs, and run provenance. The mutation
  receipt is bound to the normalized definitions and their exact source hash,
  with the historical run reused only after byte-equality of its definition
  source was established. Ledger claims distinguish killed consumer-removal
  mutations from bounded behavioral negatives, independent reproduction
  separates resolved historical findings from current limits, and repository
  documents describe private `main` and successor-development evidence without
  a release or refinement-complete claim.
- Rewrite the public packet for kernel version 2. The proposal text
  `docs/ERC-DRAFT.md` is rewritten in EIP-1 form from the kernel machine source
  and the decision records: the types and interface with their identifiers, the
  hash preimages, authorization and replay, the validation order and field
  rules, the outcomes with the definition of a full-state stutter, the case
  transition table, the reversal effects, the receipt with the sourcing of every
  field, the dependency root and epoch, the bound dependency boundary, the two
  reference profiles including onboarding and owned upstream state, the ERC-7943
  route, and the rationale, compatibility, test cases, reference, and security
  sections. The kernel machine source states in prose what the independent
  reproduction had to infer (full-state stutter, the profile interface identifier
  rule, the meaning of `same` in the field rules, the sourcing of reversal receipt
  fields and the external commitment, the per-kind binding epoch), with no value,
  selector, vector, or generated Solidity byte changing. README,
  FORMAL_VERIFICATION, PROFILES, INTEGRATION, ARCHITECTURE, SECURITY,
  COMMUNITY-REVIEW, CITATION.cff, CONTRIBUTING, GOVERNANCE, the specification
  README, the evidence README, the verification summary, and the SDK README
  describe the successor as current and keep the candidate 2 measurements as
  history; `evidence/known-limitations.md` lists what the code, the evidence, and
  the documents do not establish, each entry with its owner. The link checker
  classifies every link (repository, EIP repository, allowlisted external host,
  mailto) and checks that every backtick path names a file or directory in the
  tree. No completion, release, or Full claim is made; the Certora lanes stay
  pending by decision.
- Bind the runtime identity of the three successor endpoints to their evidence. The
  deterministic build receipt records two isolated clean builds of the native token, the
  ERC-3643 profile adapter, and the profile governor; the release manifest binds all three
  creation and runtime hashes; a two-layer runtime binding (`scripts/generate-runtime-binding-v3.mjs`,
  `scripts/verify-runtime-binding-v3.mjs`) records the template identity of the artifacts and
  replays the exact sources under the pinned compiler, requiring the six semantic projections
  to match, rejecting stale receipts, and proving its own classifier against deliberate
  mutants; an independent, specification-only implementation
  (`scripts/independent-reproduction-v3.mjs`) reproduces every identifier, hash, calldata, and
  receipt hash of the conformance vectors and its receipt is checked in continuous
  integration; the claim matrix gains a successor section; and the generated kernel prose
  renders string-valued shape rule entries as text (decision 11). The Certora lanes stay
  pending by decision, so the evidence mode stays successor-development.
- Connect both kernel version 2 endpoints to the abstract model through a central
  obligation ledger (`evidence/end-to-end-refinement/obligation-ledger-v3.json`, checked
  and rendered by `scripts/verify-obligation-ledger-v3.mjs` in CI). The Isabelle session is
  rewritten for kernel version 2: typed commands, the case transition table, the ordered
  dependency root with the global epoch, the unified receipt, custody backing and floor
  arithmetic, the ordinary transfer relation, and the verified-profile onboarding with the
  import manifest and the single immutable authority. The runtime bridge is regenerated for
  the three successor runtimes by `scripts/generate-runtime-bridge-v2.mjs` (checked in CI)
  and binds runtime hashes, every selector with its route class, storage layouts, error
  selectors, event topics, and the fixed-width guard positions. The candidate 2 bridge
  theories, current-profile theories, and KEVM claim inputs move byte for byte under
  `evidence/candidate-2/formal/`. The four Kontrol proofs are rerun on the successor native
  runtime, and the deterministic build, Foundry, mutation, Isabelle, and Kontrol receipts
  are recorded from the committed tree by the tracked recorder scripts. Every closed ledger row names its source consumer, positive test,
  consumer-removal mutation or behavioral negative (the campaign grows from fifty-one to
  one hundred and eleven faults), and compiled consumer; the two rows that name the undischarged runtime link stay
  open, so the closure is conditional and the claim is "mapped implementation evidence;
  end-to-end refinement incomplete". The unused effect hash of the effect head and effect
  record is removed from both endpoints (decision 10); the storage slots are unchanged. No
  completion, Full, or refinement-complete claim is made.
- Wire the ERC-3643 Verified Full profile adapter to kernel version 2. The
  adapter and its governor consume the same generated kernel copy as the native
  token, report the kernel interface identifier, and feed the dependency root
  from the sealed topology (Compliance as the policy binding, the Identity
  Registry as the identity binding, zero settlement and entitlement bindings).
  Onboarding is a fresh zero-state seal or an exact import manifest that the
  seal verifies entry by entry against the live upstream state; declared frozen
  amounts and address freezes become imported cases with a live head, so they are
  reversible under the case transition table. Before consuming any command the
  adapter checks that the upstream frozen amount and address freeze flag of each
  account it acts on are exactly the state it declared or applied, and fails
  closed with the new class 300 reason 304 otherwise; upstream state is never
  overwritten or silently adopted. Custody is confined to the adapter, upstream
  execution and views are typed (reasons 400 to 403), topology drift is reason
  300 and dependency code drift reason 200, and the frozen amount of both
  accounts is resynchronised to the owned target after every forced transfer.
  Because an ERC-3643 token freezes an amount rather than a target, balance
  growth between two adapter touches stays transferable until the next touch;
  the profile surface adds `resynchroniseFrozen`, which anyone may call and
  which only raises the upstream frozen amount toward the owned target, and
  `ownedState` for indexers and keepers. The kernel version 1 profile interface, types, decision helpers,
  and error set are removed. The suite runs against two fixtures (a clean-room
  fixture and an independent one that unfreezes on forced transfers and keeps the
  full owner and Agent surface), a stateful campaign drives the adapter through
  freezes, seizures, releases, and custody confiscations, and the mutation
  campaign gains twenty-one adapter and governor faults. No completion, release,
  or Verified Full claim is made; the profile's runtime identity is bound in the
  runtime assurance change.
- Wire the native token to kernel version 2. The token consumes a generated
  copy of the normative kernel types and interfaces, reports the kernel
  interface identifier and the native route identifier, and implements the
  ordered dependency root with a global dependency epoch, the case transition
  table with its terminal-case guard, the unified action and reversal receipt
  with its kind tag, the reason classes, and the single profile descriptor.
  Delegation, cancellation, the caller-supplied scope hash, and the version 1
  convenience getters are removed. Actions and reversals share one validation
  order (stale and replayed commands are reported before any state-dependent
  rule), a malformed dependency response is reason 202 and only an echo
  mismatch is reason 203, the exact-use route ticket is enforced field by
  field with no stored key, and the stateful campaign drives freeze, unfreeze,
  seizure, release, and custody confiscation through the kernel. The schema
  text gains the custody-case overlay rule (CT-16), the direct-path custody
  backing rule, the dependency failure code mapping, and the statement that
  non-canonical calldata is a decoding failure; no value, selector, or
  identifier changes. The candidate 2 receipts and proof inputs
  move byte for byte to `evidence/candidate-2/`; the successor evidence is
  tracked lane by lane in `evidence/current-profile-release-index-v3.json`
  under `evidence/evidence-mode.json`, where lanes without a receipt for the
  current identity are pending and owned by later changes. The ERC-3643 profile
  adapter still implements kernel version 1. The working label of the successor
  is `0.2.0-candidate.1`; no release, tag, or completion claim is made.
- Add the normative kernel machine source for wire-format version 2 under
  `spec/`, with a generator that emits the Solidity interface, the JSON ABI
  and interface identifier, a human-readable rendering, the TypeScript kernel
  helpers, and six-action, three-reversal conformance vectors. The decision
  records under `spec/decisions/` fix delegation and cancellation removal, the
  case transition table, the ordered dependency root and global epoch, the
  unified receipt preimage, reason classes, the single profile descriptor and
  kernel interface, and the exact interface identity. The SDK tests reproduce
  every vector, recompute every identifier and receipt hash word by word
  without the ABI coder, and consume the negative vectors; a new check
  compiles the generated interface with the pinned compiler and compares its
  method identifiers and interface identifier with the generator's. The
  Solidity candidate under `implementation/` still implements version 1;
  nothing here changes its evidence or its claims.

Candidate 2 repairs the FREEZE-direction mismatch found during independent
pre-publication review and rebinds the implementation, formal model, evidence,
and release tooling to one successor identity. Development history before the
public tree was assembled remains preserved rather than replayed entry by
entry.

- Require every successful `FREEZE` to set a strictly greater absolute target.
  Equal or decreasing forward requests revert without consuming authorization;
  a decrease requires a separately authorized `UNFREEZE` reversal.
- Add two current targeted Certora rules over the production internal shape
  guard, four selected Kontrol proofs, a 12-fault mutation campaign, and a
  seven-subject runtime successor. Two exploratory full Certora jobs remain
  recorded as provider-error UNKNOWN and receive no proof credit.
- Reissue all seven packages and all 49 Core and 24 mandatory Supporting rows
  through current evidence or a verifier-enforced exact two-guard delta. This
  is a successor qualification, not a claim that 73 independent whole-runtime
  proofs were rerun.
- Add the accompanying
  [arXiv paper](https://arxiv.org/abs/2608.29134) and document its versioned
  artifact binding: v1 remains candidate 1 history, while candidate 2 is the
  corrected successor for the replacement line.
- Align the BSD-covered copyright notice with company ownership by naming
  Oraclizer Labs, Inc., while preserving the four byte-bound pilot sources
  under their historical MIT headers. The proposed ERC text remains separately
  dedicated under CC0.
- Establish the public `main` signature baseline at launch. Earlier candidate
  history may be unsigned; later `main` commits must be GitHub-verified squash
  merges.
- Keep the root license machine-detectable as BSD-3-Clause and place the
  complete scoped MIT notice for the four historical pilot sources in the
  README without changing those byte-bound files.

- Established the public release candidate: the immutable Solidity reference
  implementation with compatibility profiles, the TypeScript SDK, the
  specification drafts, and the machine-checkable evidence package.
- Completed the current verification profile: 49 of 49 core refinement rows
  and 24 of 24 supporting rows qualified against seven successor verification
  packages for the repaired source and runtime.
- Implemented the two-layer runtime-binding qualification without changing
  any historical expected hash. Pinned-solc replay and all six semantic
  projections pass for seven subjects; hostile validation kills 42 of 42
  semantic mutations, classifies 7 of 7 packaging-only mutations as
  drift-PASS, and rejects 7 of 7 expected-hash overwrites.
- Kept the Foundry lane green: 31 tests across five suites, two fuzz
  properties at 256 runs each, and three invariants totaling 384,000 calls
  with zero reverts.
- Superseded the publicly unreachable formal-foundation commit with the
  reachable public revision through a new versioned lock. Every ERC proof
  source, statement, qualification receipt, and expected hash is unchanged;
  a fourteen-file mapping verifies the succession, and hostile validation
  rejects all fourteen mapped-file mutations plus missing-registration,
  wrong-import, and wrong-commit overlay mutations. The temporary
  sibling-session overlay clean-builds `ERC_TRUST` with proof audit PASS and
  zero oracle dependencies.
- Limited the release manifest to protected implementation, proof, evidence,
  schema, vector, SDK, lock, and replay inputs. Pull requests verify the
  protected-input mode, while main and candidate-release runs additionally
  verify the protected source-tree root, so documentation changes do not
  force unrelated manifest churn.
- Named the active maintainer, fixed the public tag families to
  `vX.Y.Z-candidate.N` and `vX.Y.Z`, and set the public citation identity to
  `Jinwook Kim` with ORCID `0009-0004-4993-8005`.

The historical `v0.1.0-candidate.1` tag remains immutable. Candidate 2 tagging
and GitHub Release publication are separate maintainer actions; this changelog
does not assert their current presence or absence.
