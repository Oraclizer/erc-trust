# ERC-TRUST operator SDK

This candidate package provides deterministic, side-effect-free helpers for:

- action and reversal identifiers;
- canonical command and action-receipt hashes;
- native and ERC-7943 wrapper calldata;
- address checksum normalization.

It does not submit transactions, manage or store keys, decide legal authority,
fetch policy or identity data, validate a deployment, or attest external
facts.

> [!WARNING]
> Unaudited and not for production. The SDK is a convenience implementation,
> not an independent security boundary.

## Requirements

- Node.js `24.14.0`
- pnpm `11.9.0`

```bash
corepack enable
corepack prepare pnpm@11.9.0 --activate
pnpm install --frozen-lockfile --ignore-scripts
pnpm test
```

## Example

```ts
import {
  ActionKind,
  TRUST_DOMAIN,
  deriveActionId,
  encodeAction,
} from "@oraclizer/erc-trust-sdk";

const unsignedRequest = {
  domain: TRUST_DOMAIN,
  actionId: "0x" + "00".repeat(32),
  action: ActionKind.FREEZE,
  // Provide every other field from the selected deployment profile and case.
};

const actionId = deriveActionId(tokenAddress, chainId, unsignedRequest);
const request = { ...unsignedRequest, actionId };
const calldata = encodeAction(request);
```

Pass `true` as the second argument to `encodeAction` or `encodeReversal` only
when intentionally selecting the native exact-use ERC-7943 wrapper.

## Integration rules

- Populate all fields. Action-specific zero and nonzero requirements are
  security-relevant.
- Derive IDs from the actual chain ID and deployed contract address.
- Bind the current authority and epoch, the dependency root and epoch,
  nonce, validity, and action-specific commitments before encoding.
- Compare results against
  [`../vectors/conformance-v2.json`](../vectors/conformance-v2.json) for
  kernel version 2 and
  [`../vectors/conformance-v1.json`](../vectors/conformance-v1.json) for the
  shipped version 1 helpers.
- Recompute the stored receipt and emitted receipt hash independently.
- Never treat SDK output as proof that an upstream fact or authority is valid.

See the repository [integration guide](../docs/INTEGRATION.md) for the complete
request and failure lifecycle.

## Kernel version 2 helpers

`src/kernel-v2.ts` is generated from `spec/erc-trust-kernel-v2.json` and
provides the version 2 identifiers, command hashes, dependency root, binding
hash, nonce key, and the unified action and reversal receipt hash. The
Solidity endpoints under `implementation/` implement kernel version 2; the
package entry point (`src/index.ts`) and the example above still expose the
version 1 helpers of the shipped candidate, so use `src/kernel-v2.ts` for
the successor until the entry point is switched.
