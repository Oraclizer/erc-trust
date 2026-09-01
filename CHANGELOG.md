# Changelog

## Unreleased

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
- Align the BSD-covered copyright notice with current pre-incorporation
  ownership by naming Jinwook Kim, while preserving the four byte-bound pilot
  sources under their historical MIT headers. The proposed ERC text remains
  separately dedicated under CC0.
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
