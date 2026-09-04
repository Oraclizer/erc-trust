# Conformance profiles

A profile is an evidence-backed deployment claim, not an interface-detection
shortcut. A deployment inherits no Full status by importing these contracts,
using the same function names, or matching an ERC-165 identifier. Every
endpoint reports one `ProfileDescriptor` through `trustProfile()`; the
descriptor is a declaration. A Full profile computes `full` from its live
conformance conditions; a Partial or Unsupported profile always returns
`full = false`.

| Profile | Identifier | Six actions | ERC-7943 | State owner | Classification |
| --- | --- | --- | --- | --- | --- |
| Native Full | `keccak256("ERC-TRUST/v2/native-full")` | Yes | Fungible `0x3edbb4c4` and the exact-use route `0x5cd8d207` | Token | Exact immutable source, pinned compiler, and four bound read-only dependencies |
| ERC-3643 Partial reference | `keccak256("ERC-TRUST/v2/erc3643-partial")` | Yes, within the documented adapter boundary | Not claimed | Adapter, over a sealed token | Current reference; `profileKind = PARTIAL`, `full = false` |
| ERC-3643 Verified Full | `keccak256("ERC-TRUST/v2/erc3643-verified-full")` | Reserved TRUST 1.2 class | Not claimed | Future hook-enabled endpoint | No current reference reports this identifier |
| Unsupported | none | No reliable declaration | No | Unknown | Missing, stale, or contradictory evidence |

Both reference profiles implement the kernel interface `0x2b020308` from the
same generated copy of the kernel machine source (`spec/erc-trust-kernel-v2.json`)
and report `standardVersion = 2`, `actionMask = 0x3f`, `reversalMask = 0x07`,
and `proxySupported = false`. The ERC-3643 reference also reports
`PROFILE_ERC3643_PARTIAL`, `profileKind = PARTIAL`, and `full = false` even
while its narrower sealed topology is live.

## Native Full

The endpoint is the token itself; `underlyingToken` is zero and
`manifestHash` is the current `dependencyRoot`. The declaration is valid only
while all of the following remain true:

- the deployed runtime bytecode matches the declared source, compiler, EVM
  version, optimizer, IR, metadata, and constructor inputs (the reference
  binds these in `evidence/release-manifest.json` and
  `evidence/runtime-binding-v3.json`);
- the deployment is immutable and relies on no proxy, `delegatecall`,
  migration, or unbound extension surface;
- the four dependencies (policy, identity, settlement, entitlement) match
  their bound address, runtime code, configuration digest, schema, and
  per-kind epoch, and the ordered dependency root and global epoch reported by
  `dependencyState()` are the ones every command carries;
- all six actions and three reversals retain the case transition table, the
  custody backing rule, the replay keys, the failure classes, and the receipt
  preimage of the kernel;
- raw `setFrozenTokens` and `forcedTransfer` calls remain closed and the
  exact-use route ticket remains same-transaction and single-consumption.

Authority is direct: the caller of a command is the account registered for
its `authorityRef`, which may be a contract; the kernel has no delegation
surface. Any source, compiler, dependency, authority, or deployment change
requires a new manifest and an evidence-impact assessment.

## ERC-3643 Partial reference

The conformance unit is a `ProfileGovernor` together with an
`ERC3643TrustAdapter`; the adapter is the endpoint, the sealed token is
`underlyingToken`, and `manifestHash` is the sealed binding. The dependency
root is fed from the sealed topology: Compliance as the policy binding, the
Identity Registry as the identity binding, and zero for the settlement and
entitlement slots, which the manifest of the profile declares here. The
reference governor seals exactly once, so the dependency epoch is 1 for the
life of the unit; a profile that offers a reseal must increment the epoch and
change the root on every reseal.

`sealedTopologyLive()` is true only while the one-way seal, exclusive Agent
topology, token code identity, registries, and bound dependency code remain
live. It is an operational predicate, not a Full-conformance signal. The
reference checks:

- the exact upstream token runtime code identity declared at the seal (the
  seal binds the declared value to the live code and does not audit the code);
- `ProfileGovernor` as token owner with no arbitrary-call, Agent-management,
  or registry-rebinding surface after its one-way seal;
- the exact Identity Registry and Compliance addresses;
- the adapter as the exclusive Agent;
- a completed one-way seal bound to the chain, governor, token, expected token
  code identity, adapter, both registries, and the import manifest;
- an import manifest whose included entries are verified against live upstream
  state (reason 303 on any difference), without claiming that the manifest is
  complete or that an empty manifest proves a fresh zero state;
- exact balance and frozen-amount postconditions after every upstream mutation,
  plus actual source and destination restriction postconditions after every
  forced transfer (reasons 400 and 401), and the ownership check before every
  command (reason 304);
- receipt observations that bind actual upstream restriction flags for the
  subject, source, and destination.

Custody is confined to the adapter: `SEIZE` requires the custodian and the
destination to be the adapter, so the Identity Registry must report the
adapter as verified for seizures to execute. An ordinary ERC-3643 token with
several Agents, a mutable owner, an upgradeable runtime, unbound registries,
or undeclared frozen state remains Partial or Unsupported according to the
evidence actually available. Exact declared entries do not prove that another
legacy account was not omitted.

### Known limitation of the adapted frozen target

An ERC-3643 token freezes an amount; the kernel holds a frozen target. The
adapter materialises the owned target upstream only at its own touch points
(after every forced transfer it restores both accounts to their owned targets
saturated at the current balance). Tokens received by an ordinary inbound
transfer between two touches stay transferable until the next command that
touches the account or a call to `resynchroniseFrozen(account)` on the
profile surface, which anyone may call and which only raises the upstream
frozen amount toward the owned target. Closing that window atomically would
need a transfer hook inside the token or its Compliance, which this profile
does not use. `ownedState(account)` exposes the owned target, the applied
upstream amount, and the owned restriction flag so that an indexer or keeper
can see when a resynchronisation is due. This window is a reason the current
reference is Partial, not a limitation compatible with Full. The full list is in
`evidence/known-limitations.md`.

## TRUST 1.2 Verified Full requirements

The Verified Full identifier is reserved for a future profile. A deployment
may report it only when all of the following are bound to the same runtime and
evidence identity:

- atomic fresh deployment of the token and endpoint;
- a complete initial-state gate, not an attestational list of selected entries;
- a token or Compliance hook that enforces the TRUST frozen target on every
  ordinary transfer in the same transaction;
- actual balance, frozen amount, and restriction post-state equality after
  forced transfers, with the same actual restriction values in receipts;
- proxy and upgrade paths rejected, or the implementation, admin, and epoch
  explicitly bound.

Existing T-REX imports are not eligible without an enumerable state root,
account count, and completeness proof. A generic attestation does not supply
that missing primitive. This repository does not implement the TRUST 1.2
profile.

## Partial and Unsupported

Partial is an explicit gap report. It must list each unproved or unsupported
Full condition and must not use Full badges, documentation, or machine-readable
claims. Unsupported is required when evidence is absent, internally
inconsistent, stale, or impossible to bind to the deployed runtime.
Unsupported is a safe classification, not a statement that the deployment is
malicious.

## Required deployment manifest

No deployment manifest is included because no deployment is claimed. A
deployment-specific manifest should bind at least:

| Category | Required binding |
| --- | --- |
| Identity | Chain ID, addresses, deployment transactions, block numbers |
| Source | Repository, exact commit, source-tree root, license |
| Build | Compiler and commit, EVM version, optimizer, runs, via-IR, metadata settings |
| Bytecode | Creation and runtime hashes, linked libraries, constructor arguments |
| Profile | Profile identifier, action and reversal masks, proxy flag, `full` at the time of the claim |
| Governance | Owners, authorities and their epochs, Agents, role holders, signer policy |
| Dependencies | Addresses, code identities, schemas, configurations, per-kind binding hashes and epochs, dependency root and epoch |
| Evidence | Test, proof, mutation, audit, deterministic-build, runtime-binding, and provenance manifests |
| Operations | Finality, monitoring, incident response, upgrade or immutability statement |

The manifest must distinguish repository evidence from deployment evidence.
An audit of one commit does not cover a different runtime, and a matching
runtime does not verify current external facts.

No profile in this repository is audited or approved for production.
