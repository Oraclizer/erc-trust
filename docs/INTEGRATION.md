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

Then verify the generated artifacts, the evidence bindings, and the public
surface:

```bash
node scripts/generate-normative-kernel.mjs --check
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

`forge build --sizes` is a release gate. The three runtimes and their
EIP-170 margins are bound by the release manifest and the deterministic build
receipt (`evidence/deterministic-build.json`); any native source change
requires the full size, test, proof, mutation, and manifest replay.

## 2. Select and bind a profile

Do not infer a profile from a token name or an interface probe. Read
`trustProfile()` and apply the [profile rules](PROFILES.md):

- Native Full requires the exact immutable implementation and its four bound
  read-only dependencies.
- ERC-3643 Verified Full requires a sealed, exclusive topology, a declared
  initial state, and owned upstream state.
- Any missing Full condition must be declared Partial or Unsupported.

This repository provides no deployable address or deployment manifest. An
integrator evaluating a deployment must create a separate manifest and bind
the exact commit, source-tree root, compiler settings, bytecode, chain,
addresses, roles, constructor inputs, bindings, and evidence package.

## 3. Construct a typed request

Every value of the wire format is defined by the machine-readable kernel
source (`spec/erc-trust-kernel-v2.json`) and rendered in
`spec/generated/kernel-v2.md`. An action request contains:

| Field group | Purpose |
| --- | --- |
| `domain`, `actionId`, `action` | Protocol separation, deterministic identity, and typed meaning |
| `subject`, `source`, `destination`, `custodian`, `amount`, `caseId` | Action-specific state transition and the case the command belongs to |
| `dependencyRoot`, `dependencyEpoch` | The endpoint's current dependency state, read from `dependencyState()` |
| `provenanceCommitment` | The evidence record the command binds |
| `settlementCommitment`, `proceedsCommitment`, `entitlementCommitment` | Action-specific external inputs (`LIQUIDATE` and `RECOVER`) |
| `authorityRef`, `authorityEpoch` | The authority and its current epoch |
| `nonce`, `validAfter`, `validBefore` | Replay and validity controls |

A reversal request carries the reversed `actionId`, the reversal kind, the
dependency pair, the provenance commitment, the authority, the nonce, and the
validity window. Start from a vector in
[`vectors/conformance-v2.json`](../vectors/conformance-v2.json), not from a
partially populated object: the field rules require some fields to be zero
and others to be nonzero, and the request is rejected as a decoding failure
if any field carries bits outside its declared width.

The generated TypeScript helpers in `sdk/src/kernel-v2.ts` derive
identifiers, hashes, and calldata for kernel version 2:

```ts
import {
  ActionKind,
  KERNEL_DOMAIN,
  deriveActionId,
  encodeAction,
} from "@oraclizer/erc-trust-sdk";

const unsigned = {
  domain: KERNEL_DOMAIN,
  actionId: "0x" + "00".repeat(32),
  action: ActionKind.FREEZE,
  // Supply every remaining field from the selected profile, case, and dependencyState().
};

const actionId = deriveActionId(endpointAddress, chainId, unsigned);
const request = { ...unsigned, actionId };
const calldata = encodeAction(request);
```

The package root exports the kernel version 2 helpers. Historical kernel
version 1 helpers remain available only from the explicit
`@oraclizer/erc-trust-sdk/v1` subpath. A pack-install smoke verifies the
installed package root against the version 2 conformance vectors.
The SDK does not decide authority, obtain facts, manage keys, submit a
transaction, or validate a deployment.

## 4. Submit only through a canonical entrypoint

| Intent | Entrypoint |
| --- | --- |
| Native action | `executeRegulatoryAction` |
| Native reversal | `executeRegulatoryReversal` |
| Native ERC-7943 exact-use route | `executeERC7943Action`, `executeERC7943Reversal` |
| ERC-3643 profile action | adapter `executeRegulatoryAction` |
| ERC-3643 profile reversal | adapter `executeRegulatoryReversal` |
| ERC-3643 profile resynchronisation | adapter `resynchroniseFrozen(account)` (anyone; only raises the upstream frozen amount toward the owned target) |

Never call `setFrozenTokens` or `forcedTransfer` as an operator shortcut. The
native reference rejects raw calls unless a canonical wrapper has created an
exact-use, same-transaction ticket.

Before submission, independently confirm:

- the chain ID and endpoint address used to derive the command identifier;
- the account currently registered for the authority and its epoch;
- the current `dependencyState()` pair, which every command must carry;
- the validity window and an unused nonce under the current authority epoch;
- the case: an open case of the right family, a live head for a reversal, an
  active custody record for `RELEASE` or a custody disposition, and no
  terminal case;
- all action-specific commitments and the exact address and amount shape;
- that the profile still satisfies its Full or Partial declaration.

## 5. Interpret failures

| Failure | Meaning | Operator response |
| --- | --- | --- |
| `TrustInvalidCommand` (reason class 1) | Domain, identifier, window, authority epoch, dependency pair, field rule, or a case, custody, entitlement, pairing, live-head, freeze-direction, or no-change rule failed; the reason names the earliest failing check | Rebuild from the current state; do not retry unchanged |
| `TrustUnauthorized`, `TrustReplay` | The caller is not the registered authority, or the command identifier or nonce tuple was already consumed | Investigate authority state; never bypass |
| `TrustRejected` (class 100) | A completed assessment denied the command | Treat as denied |
| `TrustOperationalFailure` (classes 200, 300, 400) | A bound dependency, the sealed topology, or an upstream call was unavailable, malformed, stale, or inconsistent | Stop and repair the dependency or topology |
| `TrustRouteMismatch` | A sensitive ERC-7943 selector lacked the exact ticket | Use the canonical typed wrapper |
| `TrustTerminal` | The case is terminal | Do not attempt another command in that case |
| plain revert | Non-canonical calldata (wrong length, dirty bits, enum out of range) | Re-encode from the canonical types |

Every one of these paths is a full-state stutter: the call leaves the
endpoint exactly as it was and consumes nothing. A failed command must not
be treated as authorization to continue through another administrative
mechanism.

## 6. Verify and retain the receipt

On success:

1. Wait for the transaction receipt under the integrator's chosen finality
   policy.
2. Read the stored receipt with `receipt(commandId)`; every preimage input is
   returned, so the hash is recomputable without the transaction calldata.
3. Recompute `receiptHash` independently with the SDK helper or an
   independent ABI implementation (the domain, then the first sixteen
   fields in declared order).
4. Confirm that the applied event is the final protocol log of the command,
   that its `receiptHash` equals the stored value and the execute return
   value, and that `parentCommandId` of a reversal receipt names the reversed
   action.
5. Retain the request, the deployment manifest, the dependency root and epoch
   the command was validated against, the transaction hash, the block
   context, and the recomputed receipt together.

A matching receipt shows that the endpoint committed to the observed fields.
It does not prove off-chain legal authority or factual truth.

## 7. Integration exit criteria

Before an integration may describe itself as evaluation-ready, it should have:

- a reproducible source and bytecode binding;
- an explicit Native Full, ERC-3643 Verified Full, Partial, or Unsupported
  declaration;
- independent identifier, calldata, vector, and receipt reproduction;
- negative tests for replay, stale dependency pairs, dependency failure,
  topology drift, direct ERC-7943 calls, terminal cases, and action-specific
  shape errors;
- a documented signer, relayer, finality, monitoring, rollback, and incident
  process outside this repository.

Production use additionally requires independent audit and deployment-specific
assurance. Repository verification alone does not satisfy that bar.
