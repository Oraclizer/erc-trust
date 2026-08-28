# Conformance profiles

A profile is an evidence-backed deployment claim, not an interface-detection
shortcut. A deployment inherits no Full status merely by importing these
contracts, using the same function names, or matching an ERC-165 identifier.

| Profile | Six actions | ERC-7943 | State owner | Full gate |
| --- | --- | --- | --- | --- |
| Native Full v1 | Yes | Fungible `0x3edbb4c4` | Token | Exact immutable source and bound read-only dependencies |
| ERC-3643 Verified Full v1 | Yes | Not claimed | Adapter | Sealed code hash, inert owner, exact registries, exclusive adapter Agent |
| ERC-3643 Partial | Deployment-specific | Not claimed | Adapter or token | One or more Full topology conditions unproved |
| Unsupported | No reliable declaration | No | Unknown | Missing, stale, or contradictory evidence |

## Native Full v1

The declaration is valid only while all of the following remain true:

- the deployed runtime bytecode matches the declared source, compiler, EVM
  version, optimizer, IR, metadata, and constructor inputs;
- the deployment is immutable and does not rely on a proxy, `delegatecall`,
  migration, or unbound extension surface;
- policy, identity, settlement, and entitlement dependencies match their
  bound address, runtime code hash, configuration digest, schema, epoch, and
  binding hash;
- all six actions and three reversals retain the action-specific state,
  replay, failure, custody, terminal-case, and receipt semantics;
- raw sensitive ERC-7943 calls remain closed and exact-use tickets remain
  same-transaction and single-consumption.

Any source, compiler, dependency, governance, or deployment change requires a
new manifest and an evidence-impact assessment.

## ERC-3643 Verified Full v1

The declaration is valid only when `ProfileGovernor.isFull(adapter)` remains
true and the deployment evidence independently establishes:

- the exact upstream token runtime code hash;
- `ProfileGovernor` as token owner;
- the exact Identity Registry and Compliance addresses;
- the adapter as Agent;
- the adapter as the exclusive Agent;
- a completed one-way seal bound to the chain, governor, token, adapter,
  registry, compliance, and expected code hash;
- no arbitrary-call or Agent-management surface on the sealed governor;
- exact postcondition checks after upstream mutations.

An ordinary ERC-3643 token with several Agents, a mutable owner, an upgradeable
runtime, or unbound registries is not Verified Full. It must be described as
Partial or Unsupported based on the evidence actually available.

## Partial and Unsupported

Partial is an explicit gap report. It must list each unproved or unsupported
Full condition and must not use Full badges, documentation, or machine-readable
claims.

Unsupported is required when evidence is absent, internally inconsistent,
stale, or impossible to bind to the deployed runtime. Unsupported is a safe
classification, not a statement that the deployment is malicious.

## Required deployment manifest

No deployment manifest is included in this candidate because no deployment is
claimed. A deployment-specific manifest should bind at least:

| Category | Required binding |
| --- | --- |
| Identity | Chain ID, addresses, deployment transactions, block numbers |
| Source | Repository, exact commit, source-tree root, license |
| Build | Compiler and commit, EVM version, optimizer, runs, via-IR, metadata settings |
| Bytecode | Creation and runtime hashes, linked libraries, constructor arguments |
| Profile | Profile identifier, action mask, proxy and migration flags |
| Governance | Owners, authorities, Agents, role holders, epochs, signer policy |
| Dependencies | Addresses, code hashes, schemas, configurations, binding hashes, epochs |
| Evidence | Test, proof, mutation, audit, deterministic-build, and provenance manifests |
| Operations | Finality, monitoring, incident response, upgrade or immutability statement |

The manifest must distinguish repository evidence from deployment evidence.
An audit of one commit does not cover a different runtime, and a matching
runtime does not verify current external facts.

## Reference candidate flags

For both reference v1 profiles:

```text
proxySupported = false
migrationSupported = false
```

No profile in this repository is audited or approved for production.
