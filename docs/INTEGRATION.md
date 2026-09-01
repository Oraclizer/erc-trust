# Integration guide

This guide is for evaluating and reproducing the unaudited reference
candidate. It is not a deployment runbook.

> [!WARNING]
> **Unaudited. Not for production.** Do not use this candidate with
> production assets. No audit, deployment, proxy, migration, signer, relayer,
> monitoring, or incident-response system is included.

## 1. Reproduce the candidate

Use the exact toolchain recorded in
[`evidence/release-manifest.json`](../evidence/release-manifest.json):

- Foundry `1.7.1`
- Solidity `0.8.36`
- Node.js `24.14.0`
- pnpm `11.9.0`

```bash
forge fmt --check
forge build --sizes
forge test --fuzz-runs 256 -vv
forge lint

corepack enable
corepack prepare pnpm@11.9.0 --activate
pnpm --dir sdk install --frozen-lockfile --ignore-scripts
pnpm --dir sdk test
```

Then verify the deterministic public package:

```bash
node scripts/generate-vectors.mjs
forge build
node scripts/verify-release.mjs
node scripts/verify-links.mjs
node scripts/verify-public-surface.mjs
node scripts/verify-repository-health.mjs
```

`forge build --sizes` is a release gate. The native runtime is currently only
399 bytes below the EIP-170 limit with the pinned optimizer settings.

## 2. Select and bind a profile

Do not infer a profile from a token name or interface probe. Use the
[profile rules](PROFILES.md):

- Native Full v1 requires the exact immutable implementation and bound
  dependencies.
- ERC-3643 Verified Full v1 requires a sealed, exclusive topology.
- Any missing Full condition must be declared Partial or Unsupported.

This repository provides no deployable address or deployment manifest. An
integrator evaluating a deployment must create a separate manifest and bind
the exact commit, source-tree root, compiler settings, bytecode, chain,
addresses, roles, constructor inputs, bindings, and evidence package.

## 3. Construct a typed request

An action request contains:

| Field group | Purpose |
| --- | --- |
| `domain`, `actionId`, `action` | Protocol separation, deterministic identity, and typed meaning |
| `subject`, `source`, `destination`, `custodian`, `amount`, `caseId` | Action-specific state transition |
| `scopeHash` | Delegated authority scope |
| policy and provenance commitments | Policy and evidence version binding |
| settlement, proceeds, entitlement commitments | Action-specific external inputs |
| `authorityRef`, authority and policy epochs | Current authority and dependency generations |
| `nonce`, `validAfter`, `validBefore` | Replay and validity controls |

Start from a vector in
[`vectors/conformance-v1.json`](../vectors/conformance-v1.json), not from a
partially populated object. Action-specific shape rules intentionally require
some fields to be zero and others to be nonzero.

The minimal SDK derives IDs, hashes, and calldata:

```ts
import {
  ActionKind,
  TRUST_DOMAIN,
  deriveActionId,
  encodeAction,
} from "@oraclizer/erc-trust-sdk";

const unsigned = {
  domain: TRUST_DOMAIN,
  actionId: "0x" + "00".repeat(32),
  action: ActionKind.FREEZE,
  // Supply every remaining field from the selected profile and case.
};

const actionId = deriveActionId(tokenAddress, chainId, unsigned);
const request = { ...unsigned, actionId };
const calldata = encodeAction(request);
```

The SDK does not decide authority, obtain facts, manage keys, submit a
transaction, or validate a deployment.

## 4. Submit only through a canonical entrypoint

| Intent | Entrypoint |
| --- | --- |
| Native action | `executeRegulatoryAction` |
| Native reversal | `executeRegulatoryReversal` |
| Native ERC-7943-compatible action route | `executeERC7943Action` |
| Native ERC-7943-compatible reversal route | `executeERC7943Reversal` |
| ERC-3643 profile action | adapter `executeRegulatoryAction` |
| ERC-3643 profile reversal | adapter `executeRegulatoryReversal` |

Never call `setFrozenTokens` or `forcedTransfer` as an operator shortcut. The
native reference rejects raw calls unless a canonical wrapper has created an
exact-use, same-transaction ticket.

Before submission, independently confirm:

- the chain ID and contract address used to derive the command ID;
- the current authority account, authority epoch, and delegation scope;
- the current policy epoch and binding;
- the validity window and unused authority nonce;
- all action-specific commitments and exact address/amount shape;
- the profile still satisfies its Full or Partial declaration.

## 5. Interpret failures

| Failure class | Meaning | Operator response |
| --- | --- | --- |
| Invalid command | Domain, ID, time, shape, epoch, or state precondition is wrong | Rebuild from current canonical state; do not retry unchanged |
| Unauthorized or replay | Caller, scope, action ID, or nonce is not usable | Investigate authority state; never bypass |
| Rejected assessment | A bound dependency answered that the action is not applicable | Treat as denied |
| Operational failure | A dependency or upstream call was absent, malformed, stale, or mismatched | Stop and repair the dependency or topology |
| Route mismatch | A sensitive ERC-7943 selector lacked the exact ticket | Use the canonical typed wrapper |
| Terminal case | A prior confiscation closed the case | Do not attempt another disposition |

All these paths revert. A failed command must not be treated as authorization
to continue through another administrative mechanism.

## 6. Verify and retain the receipt

On success:

1. Wait for the transaction receipt under the integrator's chosen finality
   policy.
2. Read the canonical TRUST receipt for the command ID.
3. Recompute its hash independently with `actionReceiptHash` or an independent
   ABI implementation.
4. Confirm the receipt event is the final protocol event and matches the
   stored hash.
5. Retain the request, deployment manifest, dependency versions, transaction
   hash, block context, and recomputed receipt together.

A matching receipt shows that the candidate committed to the observed fields.
It does not prove off-chain legal authority or factual truth.

## 7. Integration exit criteria

Before an integration may describe itself as evaluation-ready, it should have:

- a reproducible source and bytecode binding;
- an explicit Native Full, ERC-3643 Verified Full, Partial, or Unsupported
  declaration;
- independent command-ID, calldata, vector, and receipt reproduction;
- negative tests for replay, stale epochs, dependency failure, topology drift,
  direct ERC-7943 calls, and action-specific shape errors;
- a documented signer, relayer, finality, monitoring, rollback, and incident
  process outside this repository.

Production use additionally requires independent audit and deployment-specific
assurance. Repository verification alone does not satisfy that bar.
