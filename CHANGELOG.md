# Changelog

## Unreleased

The public candidate consolidates the reference implementation, its formal
evidence, and the release tooling into a reviewed tree with a two-commit
public history. Development history before the public tree was assembled is
retained by the maintainer and summarized here rather than replayed
entry by entry.

- Established the public release candidate: the immutable Solidity reference
  implementation with compatibility profiles, the TypeScript SDK, the
  specification drafts, and the machine-checkable evidence package.
- Completed the current verification profile: 49 of 49 core refinement rows
  and 24 of 24 supporting rows qualified against the seven reusable
  verification packages, whose bytes are unchanged since qualification.
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

No tag or release exists yet; version sections begin with the first tagged
candidate.
