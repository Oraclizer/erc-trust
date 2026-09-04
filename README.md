<div align="center">
  <img src="docs/assets/erc-trust-banner.svg" alt="ERC-TRUST: Typed Regulatory Uniformity for Security Tokens" width="860">

  <p><strong>A typed, fail-closed execution standard candidate for regulatory actions on security tokens.</strong></p>

  [![CI](https://github.com/Oraclizer/erc-trust/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/Oraclizer/erc-trust/actions/workflows/ci.yml)
  [![Release identity](https://github.com/Oraclizer/erc-trust/actions/workflows/identity.yml/badge.svg?branch=main)](https://github.com/Oraclizer/erc-trust/actions/workflows/identity.yml)
  [![Proofs](https://github.com/Oraclizer/erc-trust/actions/workflows/proofs.yml/badge.svg?branch=main)](https://github.com/Oraclizer/erc-trust/actions/workflows/proofs.yml)
  [![Paper](https://img.shields.io/badge/arXiv-2608.29134-b31b1b.svg)](https://arxiv.org/abs/2608.29134)
  [![Solidity](https://img.shields.io/badge/solidity-0.8.36-2b247c.svg)](https://github.com/Oraclizer/erc-trust/actions/workflows/ci.yml)
  [![Software license](https://img.shields.io/badge/license-BSD--3--Clause-0b5cad.svg)](LICENSE)

  [Draft](docs/ERC-DRAFT.md) |
  [Architecture](docs/ARCHITECTURE.md) |
  [Integration](docs/INTEGRATION.md) |
  [Profiles](docs/PROFILES.md) |
  [Verification](FORMAL_VERIFICATION.md) |
  [Paper](https://arxiv.org/abs/2608.29134) |
  [Community review](docs/COMMUNITY-REVIEW.md)
</div>

> **Unaudited. Not for production.** No deployment, proxy, migration, or
> external legal or factual truth is verified. ERC-TRUST is a pre-ERC
> candidate. No ERC number has been assigned or assumed.

## Standards track status

ERC-TRUST is a conformance extension of the proposed **ERC-8319**
(Regulatory Compliance Protocol). ERC-8319 is an open, not-yet-merged Draft
at [ethereum/ERCs PR #1848](https://github.com/ethereum/ERCs/pull/1848). The
official ERC-TRUST proposal will be submitted after ERC-8319 merges, with the
intended preamble `requires: 20, 165, 7943, 8319`; until then ERC-TRUST has
no official ERC number and [`docs/ERC-DRAFT.md`](docs/ERC-DRAFT.md) is the
working draft.

## Research paper

The accompanying paper,
[Mechanizing Typed Regulatory Actions for Security Tokens: Semantics, Falsification, and Bounded EVM Evidence](https://arxiv.org/abs/2608.29134),
sets out the Isabelle/HOL semantics, falsification strategy, and bounded
implementation-evidence boundary. The repository remains the executable
artifact and exact candidate SSOT; the paper does not turn bounded evidence
into an audit, deployment verification, compiler-correctness result, or a
complete Isabelle-to-EVM refinement theorem.

The permanent arXiv record preserves its version history: v1 binds candidate
1 and v2 binds candidate 2, the shipped candidate. The successor now on the
public `main` branch implements kernel version 2 of the wire format, which
the paper does not yet describe; a revision is pending, and until it appears
this repository, not the paper, describes the successor. Readers should use
the latest arXiv version together with the exact commit and manifest
identities stated here.

## The problem

Security-token systems expose privileged mechanics such as freezing balances
or forcing transfers. A primitive alone does not identify the regulatory
meaning of an operation, the authority and evidence that permitted it, whether
it may be replayed or reversed, or the receipt that an independent observer
should recompute.

ERC-TRUST binds those concerns without claiming that software can establish
the underlying legal facts.

| Layer | Question | ERC-TRUST contribution |
| --- | --- | --- |
| Meaning | What regulatory action is requested? | Six typed actions with separate reversal semantics |
| Mechanism | How is the token state changed? | Native execution, an exact-use ERC-7943 route, or a sealed ERC-3643 adapter |
| Assurance | What evidence applies to this exact candidate? | Recomputable receipts, claim matrices, pinned builds, and bounded verification rows |

## Candidate at a glance

The wire format is kernel version 2, defined once in the machine-readable
source `spec/erc-trust-kernel-v2.json`, from which the Solidity interface,
the ABI, the SDK types, the human-readable rendering, and the conformance
vectors are generated. The immutable native reference implements:

- the six typed actions `FREEZE`, `SEIZE`, `CONFISCATE`, `LIQUIDATE`,
  `RESTRICT`, and `RECOVER`, and the separate `UNFREEZE`, `RELEASE`, and
  `UNRESTRICT` reversals;
- ERC-20, ERC-165, the ERC-7943 fungible interface, and the kernel
  interface `0x2b020308`;
- exactly-once command identifiers and authority nonce tuples, with stale
  and replayed commands reported before any state-dependent rule;
- a case transition table with one live overlay head per subject and
  family, one custody record per case, and terminal cases;
- distinct `TrustRejected` and `TrustOperationalFailure` outcomes, every
  failure a full-state stutter;
- four read-only dependencies bound by address, runtime code, configuration
  digest, schema, and epoch, folded into one dependency root that every
  command carries and any rebind invalidates;
- same-transaction exact-use tickets for the sensitive ERC-7943 selectors;
- one seventeen-field receipt for actions and reversals, stored, returned by
  `receipt(commandId)`, and emitted as the final log of the command.

The optional ERC-3643 reference uses a separate adapter over a sealed token and
reports `profileKind = PARTIAL`, `full = false`, with profile identifier
`keccak256("ERC-TRUST/v2/erc3643-partial")`. A one-way `ProfileGovernor` binds
the expected token code identity, token owner, Identity Registry, Compliance
contract, exclusive adapter Agent, and declared import entries. The manifest
checks included entries only; it does not prove global state completeness.
`sealedTopologyLive()` exposes the narrower operational topology predicate and
does not elevate the reference to Full. Forced transfers recheck actual source
and destination restriction flags after balance and frozen-target
synchronization, and receipt observations bind actual restriction flags for
subject, source, and destination. The ordinary inbound-growth window remains a
documented Partial limitation.

Proxy and migration support are `false` for both endpoints. The native
runtime is 20,043 bytes under the pinned compiler settings (4,533 bytes below
the EIP-170 limit), the ERC-3643 profile adapter 19,480, and the profile
governor 2,787, as bound by `evidence/release-manifest.json` and
`evidence/deterministic-build.json`. Any native source change requires the
full size, test, proof, mutation, and manifest replay.

## Architecture

<div align="center">
  <img src="docs/assets/architecture-overview.svg" alt="Four-stage ERC-TRUST action flow: command boundary, fail-closed gate, typed execution across the native and adapter profiles, and a canonical receipt emitted last" width="900">
</div>

The native token owns balances and TRUST state. The ERC-3643 adapter owns
TRUST state and receipts while the upstream token owns balances. Every
external response is treated as a bound input, never as proof that a legal,
identity, settlement, entitlement, or ownership claim is true.

The Native Full path gates sensitive ERC-7943 selectors behind a
same-transaction exact-use ticket. The ERC-3643 path rechecks a sealed
`ProfileGovernor` topology before using the upstream token, Identity Registry,
or Compliance contract.

See [Architecture and trust boundaries](docs/ARCHITECTURE.md) for component
ownership, action flow, failure behavior, and deployment boundaries.

## Choose a profile

| Profile | Intended use | Classification condition |
| --- | --- | --- |
| Native Full | New immutable ERC-20 deployment | Exact source, compiler settings, and four bound read-only dependencies |
| ERC-3643 Partial reference | Existing ERC-3643 interoperability with declared-entry checks and fail-closed adapter touch points | Always `full = false`; limitations include manifest incompleteness and the ordinary inbound-growth window |
| ERC-3643 Verified Full | Reserved TRUST 1.2 hook-enabled fresh deployment class | Atomic deployment, complete initial-state gate, same-transaction transfer/Compliance hook, actual upstream post-state and receipt equality |
| Unsupported | Missing or contradictory evidence | No reliable conformance declaration |

No deployment manifest is included because this repository claims no
deployment. A deployment must bind exact runtime bytecode, compiler settings,
addresses, roles, dependency epochs, and the evidence manifest.

## Quickstart

### Prerequisites

- Foundry `1.7.1`
- Solidity `0.8.36`, selected through `foundry.toml`
- Node.js `24.14.0`
- pnpm `11.9.0`

Exact pins are recorded in
[`evidence/release-manifest.json`](evidence/release-manifest.json).

### Build and test the Solidity candidate

```bash
forge fmt --check
forge build --sizes
forge test --fuzz-runs 256 -vv
forge lint
```

### Build and test the operator SDK

```bash
corepack enable
corepack prepare pnpm@11.9.0 --activate
pnpm --dir sdk install --frozen-lockfile --ignore-scripts
pnpm --dir sdk test
```

### Verify generated artifacts and public surface

```bash
node scripts/generate-normative-kernel.mjs --check
forge build
node scripts/generate-runtime-bridge-v2.mjs --check
node scripts/verify-obligation-ledger-v3.mjs
node scripts/generate-runtime-binding-v3.mjs --check
node scripts/verify-runtime-binding-v3.mjs --replay
node scripts/verify-current-profile-release-v3.mjs
node scripts/generate-release-manifest.mjs
node scripts/verify-release.mjs
node scripts/verify-links.mjs
node scripts/verify-public-surface.mjs
node scripts/verify-repository-health.mjs
```

On Windows, the complete current-profile release replay is:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/replay-current-profile-release.ps1
```

Start with the [integration guide](docs/INTEGRATION.md) before constructing a
request. Operators must not call `setFrozenTokens` or `forcedTransfer` as
shortcuts. The native reference rejects raw calls.

## Assurance snapshot

Most of this repository is proof and evidence rather than implementation,
which is why the repository language bar is dominated by K and Isabelle rather
than Solidity. Measured on this tree (files | lines):

| Layer | Successor (kernel version 2) | Preserved candidate 2 history | What it is |
| --- | --- | --- | --- |
| Isabelle/HOL theories | 22 files, 9,413 lines in `formal/isabelle/ERC_TRUST/` | 41 files, 2,802 lines under `evidence/candidate-2/` | The abstract model, its theorems, and the generated bridge and ledger theories |
| KEVM and Kontrol K sources | 1 file, 37 lines under `formal/kevm/` | 248 files, 35,114 lines under `evidence/candidate-2/formal/kevm/` | Bytecode-level claims and lemmas; the successor KEVM program has not been restarted |
| Certora rules | 1 successor spec with 4 rules and 56 lines under `implementation/certora/`; exact 4/4 PASS receipt recorded | 11 files, 858 lines under `evidence/candidate-2/` | Bounded source-level rules on the current Partial adapter runtime; not an end-to-end refinement result |
| Solidity | 14 source files, 3,211 lines, plus 15 test, Kontrol, and Certora harness files with 5,022 lines | 30 files, 15,315 lines under `evidence/candidate-2/` and `pilot/` | The reference contracts those artifacts are about |

The boundaries of what that evidence does and does not establish are stated
below, in `evidence/claim-matrix.md`, and in `evidence/known-limitations.md`;
they are part of the claim.

<div align="center">
  <img src="docs/assets/verification-architecture.svg" alt="ERC-TRUST verification architecture separating the Isabelle abstract model, Solidity and Certora checks, compiled EVM bytecode, Kontrol and KEVM proofs, the unclaimed full refinement theorem, and the separate deployment boundary" width="900">
</div>

The verification layers are complementary, not interchangeable. Solid paths
show actual artifact or verification inputs. The coral obligation boundary
does not claim a complete Isabelle-to-Solidity-to-EVM refinement theorem, and
the deployment boundary remains separate from repository evidence.

The successor on public `main` (kernel version 2, working label
`0.2.0-candidate.1`) has the following disposition, lane by lane in
`evidence/current-profile-release-index-v3.json`:

| Layer | Result |
| --- | --- |
| Foundry | 93/93 tests across seven suites; two fuzz properties at 256 runs; nine invariants at 256 runs and depth 500 (1,152,000 calls, zero reverts) |
| Mutation | 121/121 declared faults killed, including Partial descriptor, touched-account restriction post-state, role-authentic observation, sealed-topology view, and Partial interface ID negatives |
| Kontrol and KEVM | 4/4 proofs rerun on the successor native runtime; the adapter has no symbolic lane |
| Isabelle/HOL abstract model | 22 theories modelling kernel version 2; clean build and proof audit with 409 explicit roots and zero oracle dependencies |
| Obligation ledger | 74 rows: 70 closed, 2 open (the undischarged runtime link), 2 not applicable; closure conditional |
| Deterministic build | Two isolated clean builds of the three runtimes, byte-identical |
| Runtime binding | Three runtimes agree with the pinned-compiler replay in six semantic projections; verifier self-mutation 18/18 |
| Independent reproduction | 23 vectors, 401 assertions reproduced from the specification alone |
| Certora | 4/4 named rules PASS with advanced sanity, exact nine-file input root, provider provenance, and current Partial adapter runtime binding |
| SDK | 13 source tests plus a pack-install consumer smoke from the package root |

The claim this supports is "mapped implementation evidence; end-to-end
refinement incomplete": no theorem states that the compiled runtime
implements the model, and no Full or refinement-complete wording applies. The
shipped candidate `0.1.0-candidate.2` keeps its own disposition as history in
the [verification summary](evidence/verification-summary.md); the exact runs,
hashes, harnesses, and replay commands of both are in that summary,
[`FORMAL_VERIFICATION.md`](FORMAL_VERIFICATION.md), and the
[release manifest](evidence/release-manifest.json).

These results do not establish:

- an independent security audit;
- production safety or fitness for a particular purpose;
- a machine-checked Isabelle-to-Solidity-to-EVM refinement theorem;
- a verified deployment, proxy, migration, address, chain, or key-management
  process;
- the truth of an external policy, identity, legal, settlement, proceeds,
  entitlement, or ownership assertion.

The official Isabelle/Solidity AFP framework was inspected and clean-built.
Its candidate disposition is
[NOT APPLICABLE](evidence/isabelle-solidity-applicability.md) because the
available shallow translation does not cover the implementation's principal
stateful, external-call, revert, compiled-route, and event-order risks. The
implementation-level TRUST-REF obligations were instead discharged within
their stated boundaries through Foundry, Certora, Kontrol, mutation testing,
deterministic builds, and provenance.

## Documentation

| Document | Use it for |
| --- | --- |
| [Pre-ERC draft](docs/ERC-DRAFT.md) | Proposed normative interface and conformance language |
| [Architecture](docs/ARCHITECTURE.md) | Components, ownership, flows, and trust boundaries |
| [Integration](docs/INTEGRATION.md) | Build, request lifecycle, receipt handling, and failure behavior |
| [Profiles](docs/PROFILES.md) | Native and ERC-3643 conformance declarations |
| [Formal verification](FORMAL_VERIFICATION.md) | Model ownership and model-to-implementation evidence |
| [Obligation ledger](evidence/end-to-end-refinement/obligation-ledger-v3.json) | The successor's abstract-condition-by-condition connection to the code |
| [TRUST-REF matrix](evidence/trust-ref-matrix.md) | The shipped candidate's obligation-by-obligation evidence (history) |
| [Public claim matrix](evidence/claim-matrix.md) | Allowed and forbidden claims |
| [Known limitations](evidence/known-limitations.md) | What the code, the evidence, and the documents do not establish |
| [Community review](docs/COMMUNITY-REVIEW.md) | Questions for standards and implementation reviewers |
| [Disclaimer](DISCLAIMER.md) | Plain-language use, legal, and deployment boundaries |
| [Security policy](SECURITY.md) | Private vulnerability reporting |

## Related research and formal artifacts

ERC-TRUST is an independent pre-ERC candidate. The resources below provide
its broader regulatory and formal-methods context.

- [Regulatory Compliance Protocol (RCP)](https://arxiv.org/abs/2603.29278)
  provides the regulatory-coverage benchmark from which the typed-action
  problem was distilled.
- [The Cross-Domain State Preservation Functor](https://arxiv.org/abs/2604.03844)
  develops the model-level state-preservation framework in Isabelle/HOL.
- [Oraclizer formal-verification](https://github.com/Oraclizer/formal-verification)
  publishes the reusable Isabelle/HOL artifacts that the formal work here
  builds on; the scope of each layer is recorded in FORMAL_VERIFICATION.md.

## Repository layout

| Path | Role |
| --- | --- |
| `spec/` | Normative kernel machine source, decision records, and generated renderings |
| `implementation/src/` | Native reference and ERC-3643 profile |
| `implementation/test/` | Unit, fuzz, invariant, and profile tests |
| `implementation/certora/` | Successor ERC-3643 Partial harness, four CVL rules, and the config recorded by the current Certora receipt |
| `evidence/candidate-2/implementation/certora/` | Candidate 2 Certora Verification Language rules and configurations (history) |
| `implementation/kontrol/` | KEVM high-risk cross-checks |
| `sdk/` | Deterministic TypeScript request, receipt, and calldata helpers |
| `schemas/` | Canonical receipt schema generated from the kernel machine source |
| `vectors/` | Positive and negative conformance vectors |
| `evidence/` | Claim, provenance, mutation, proof, and release manifests |
| `formal/isabelle/ERC_TRUST/` | Abstract kernel version 2 model, the generated runtime bridge and obligation ledger theories |
| `pilot/` | Preserved Native FREEZE vertical slice |

### Tooling and language map

| Language or format | Purpose in this repository |
| --- | --- |
| Solidity | Immutable reference implementation, compatibility profiles, and Foundry unit, fuzz, and invariant tests |
| Isabelle/HOL | Abstract action semantics and model-level theorems, with their exact scope recorded in FORMAL_VERIFICATION.md |
| PowerShell | Windows orchestration for deterministic builds, mutation campaigns, and abstract-model evidence closure |
| JavaScript (Node.js `.mjs`) | Conformance vectors, manifests, hash binding, link checks, and public-surface/repository-health validation |
| TypeScript | Operator SDK for typed requests, identifiers, hashes, calldata, receipts, and associated tests |
| Certora Verification Language (`.spec`) | Bounded implementation and pilot rules; excluded from GitHub's language bar because Linguist otherwise misidentifies this DSL as Python |
| K Framework (Kontrol/KEVM `.k`) | Selected bytecode-level, high-risk cross-check assertions |
| YAML, TOML, JSON, and LaTeX | CI, build configuration, schemas, evidence records, and generated formal documentation |

Generated build output, prover caches, mutation workspaces, private logs, and
local environment state do not belong in the tracked public tree.

## Version and release policy

`0.1.0-candidate.2` identifies the shipped unaudited reference candidate;
`0.2.0-candidate.1` is the working label of the successor on public `main`,
which has no tag or release. The historical `v0.1.0-candidate.1` tag
remains immutable. A candidate 2 tag and a
GitHub Release are separate maintainer actions whose current state is shown by
the repository's tags and Releases pages; this README does not infer either.
Tags, releases, deployment claims, and a production designation require
separate maintainer approval and must bind an exact commit and manifest. A
later ERC number, if assigned, will not retroactively make older
implementation commits audited or production-ready.

## Security, support, and contributions

- Report potential vulnerabilities through the private path in
  [SECURITY.md](SECURITY.md). Do not disclose exploit details in a public
  issue.
- Use [SUPPORT.md](SUPPORT.md) to distinguish usage questions from defects
  and security reports.
- Read [CONTRIBUTING.md](CONTRIBUTING.md) before proposing a specification,
  implementation, proof, or documentation change.
- Project decision and merge rules are documented in
  [GOVERNANCE.md](GOVERNANCE.md).
- Participation is governed by the
  [Code of Conduct](CODE_OF_CONDUCT.md).

## License, citation, and provenance

Copyright in first-party BSD-covered content is held by Oraclizer Labs, Inc.
Licensing follows the path:

- Code, tests, scripts, the SDK, and the formal artifacts:
  [BSD 3-Clause License](LICENSE), copyright Oraclizer Labs, Inc., except for the
  exact historical pilot sources listed below.
- The byte-bound pilot sources
  `pilot/src/TrustFreezePilot.sol`, `pilot/src/MockBoundPolicy.sol`,
  `pilot/test/TrustFreezePilot.t.sol`, and
  `pilot/kontrol/TrustFreezePilotTest.t.sol` retain their historical
  `MIT` SPDX headers. The scoped
  [MIT notice](#mit-license-for-four-historical-pilot-source-files) below
  controls those four files and does not change the BSD license of the current
  reference implementation.
- The proposed ERC text in [`docs/ERC-DRAFT.md`](docs/ERC-DRAFT.md):
  copyright and related rights waived under
  [CC0 1.0 Universal](docs/LICENSE-CC0.md), matching the public-domain
  requirement for EIP/ERC documents. The waiver does not change the license
  of the reference implementation.
- The accompanying TRUST paper: CC BY 4.0, published separately from this
  repository.

The BSD 3-Clause License includes warranty and liability limitations.
[DISCLAIMER.md](DISCLAIMER.md) provides a plain-language summary but does not
replace either license or waiver.

ERC-3643 compatibility declarations are clean-room interface signatures. No
GPL implementation source is copied or adapted. See the
[provenance record](evidence/clean-room-provenance.md).

Academic and standards references can use [CITATION.cff](CITATION.cff).
Contributions use the license applicable to the changed path as described in
[CONTRIBUTING.md](CONTRIBUTING.md).

### MIT License for four historical pilot source files

The following byte-bound historical pilot source files are licensed under the
MIT License in this subsection instead of the BSD 3-Clause License:

- `pilot/src/TrustFreezePilot.sol`
- `pilot/src/MockBoundPolicy.sol`
- `pilot/test/TrustFreezePilot.t.sol`
- `pilot/kontrol/TrustFreezePilotTest.t.sol`

Copyright (c) 2026 Oraclizer Labs, Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

The standalone [ERC-TRUST project mark](docs/assets/erc-trust-mark.svg)
identifies this independent project; it implies no endorsement by the
Ethereum Foundation, Ethereum core contributors, or EIP/ERC editors, and no
assigned ERC number.
