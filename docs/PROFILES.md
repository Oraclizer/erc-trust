# Conformance profiles

A profile is an evidence-backed deployment claim, not an interface-detection
shortcut. A deployment inherits no Full status by importing these contracts,
using the same function names, or matching an ERC-165 identifier. Every
endpoint reports one `ProfileDescriptor` through `trustProfile()`; the
descriptor is a declaration, and its `full` flag is computed from the live
topology and dependency state, never stored.

| Profile | Identifier | Six actions | ERC-7943 | State owner | Full gate |
| --- | --- | --- | --- | --- | --- |
| Native Full | `keccak256("ERC-TRUST/v2/native-full")` | Yes | Fungible `0x3edbb4c4` and the exact-use route `0x5cd8d207` | Token | Exact immutable source, pinned compiler, and four bound read-only dependencies |
| ERC-3643 Verified Full | `keccak256("ERC-TRUST/v2/erc3643-verified-full")` | Yes | Not claimed | Adapter, over a sealed token | Sealed code identity, inert owner, exact registries, exclusive adapter Agent, declared initial state, owned upstream state |
| ERC-3643 Partial | profile-specific | Deployment-specific | Not claimed | Adapter or token | One or more Full conditions unproved and listed |
| Unsupported | none | No reliable declaration | No | Unknown | Missing, stale, or contradictory evidence |

Both reference profiles implement the kernel interface `0x2b020308` from the
same generated copy of the kernel machine source (`spec/erc-trust-kernel-v2.json`)
and report `standardVersion = 2`, `actionMask = 0x3f`, `reversalMask = 0x07`,
and `proxySupported = false`.

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

## ERC-3643 Verified Full

The conformance unit is a `ProfileGovernor` together with an
`ERC3643TrustAdapter`; the adapter is the endpoint, the sealed token is
`underlyingToken`, and `manifestHash` is the sealed binding. The dependency
root is fed from the sealed topology: Compliance as the policy binding, the
Identity Registry as the identity binding, and zero for the settlement and
entitlement slots, which the manifest of the profile declares here. The
reference governor seals exactly once, so the dependency epoch is 1 for the
life of the unit; a profile that offers a reseal must increment the epoch and
change the root on every reseal.

The declaration is valid only while `ProfileGovernor.isFull(adapter)` remains
true and the deployment evidence independently establishes:

- the exact upstream token runtime code identity declared at the seal (the
  seal binds the declared value to the live code and does not audit the code);
- `ProfileGovernor` as token owner with no arbitrary-call, Agent-management,
  or registry-rebinding surface after its one-way seal;
- the exact Identity Registry and Compliance addresses;
- the adapter as the exclusive Agent;
- a completed one-way seal bound to the chain, governor, token, expected token
  code identity, adapter, both registries, and the import manifest;
- an onboarding that was either a fresh zero-state seal or an exact import
  manifest verified entry by entry against the live upstream state (reason
  303 on any difference), so that every frozen amount and address freeze the
  adapter later touches is state it declared or applied;
- exact postcondition checks after every upstream mutation (reasons 400 and
  401) and the ownership check before every command (reason 304).

Custody is confined to the adapter: `SEIZE` requires the custodian and the
destination to be the adapter, so the Identity Registry must report the
adapter as verified for seizures to execute. An ordinary ERC-3643 token with
several Agents, a mutable owner, an upgradeable runtime, unbound registries,
or undeclared frozen state is not Verified Full; it is Partial or
Unsupported according to the evidence actually available.

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
can see when a resynchronisation is due. The full list is in
`evidence/known-limitations.md`.

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
