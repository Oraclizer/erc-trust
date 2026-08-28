# ERC-TRUST Isabelle/HOL entry

This directory contains the model-level formal verification package for
ERC-TRUST, Typed Regulatory Uniformity for Security Tokens.

## Ownership and dependency

`ERC_TRUST` is an independent, product-owned Isabelle session in the
`erc-trust` repository. It uses `Cross_Domain_State_Preservation` as its parent
session because the TRUST model depends on the regulatory state machine and
regulatory-action composition theory defined in the external
`formal-verification` repository. The dependency does not make ERC-TRUST part
of the CDSP entry or transfer product ownership.

## Theory order

The authoritative order is the session declaration in `ROOT`. The current
sequence contains the base regulatory model, compositional and concrete
configuration layers, generated runtime bridges, C0 decoder and guard
theories, reusable summaries, end-to-end composition, the ACT-01 current
profile theorem, the sealed `STATE-04` and `STATE-05` per-row theories, and
the action/reversal row-negative batch theory. Two final conditional
certificate theories cover the remaining balance/reversal and contract
boundary rows. `Proof_Audit.thy` remains last.

## Build

From the `erc-trust` repository root, first verify the pinned external
formal-foundation checkout and prepare a temporary compatibility session:

```bash
node scripts/verify-formal-foundation-supersession.mjs --foundation-root /path/to/formal-verification --prepare-overlay /temporary/path/formal-foundation-overlay
isabelle build -d /path/to/ADS_Functor -d /temporary/path/formal-foundation-overlay -d formal/isabelle ERC_TRUST
isabelle build -o document=pdf -d /path/to/ADS_Functor -d /temporary/path/formal-foundation-overlay -d formal/isabelle ERC_TRUST
```

The tracked release PDF is `release/ERC_TRUST.pdf`. Generated
`document.pdf` files outside that release path are build outputs and are not
the release artifact. The existing release manifest preserves the original
build provenance from before the ownership relocation.

## Evidence lifecycle

`evidence/model-verification/` tracks the claim matrix and replay scripts.
Running those scripts produces `evidence/model-verification/out/`, which is ignored because timestamped
exports, mutation workspaces, and console logs are generated artifacts. The
preserved closure and release hashes are recorded in the immutable historical
`formal-dependencies.lock.json`. The current public foundation and temporary
session procedure are recorded in `formal-dependencies-public-v1.lock.json`.

Public verification packages should expose the source, scripts, claim
boundary, final report, and sealed artifact hashes. Raw run bundles belong in
release/CI artifacts or a private provenance archive, not in the canonical
source tree.

## Claim boundary

The session establishes mechanically verified regulatory dynamics over the
declared abstract domain. It does not establish legal title, judicial
validity, off-chain evidence truth, Solidity-bytecode conformance, or
deployment correctness.
