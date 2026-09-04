# ERC-TRUST operator SDK

This candidate package provides deterministic, side-effect-free helpers for:

- action and reversal identifiers;
- canonical command, reversal, dependency, and receipt hashes;
- kernel version 2 calldata;
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
  KERNEL_DOMAIN,
  deriveActionId,
  encodeAction,
} from "@oraclizer/erc-trust-sdk";

const unsignedRequest = {
  domain: KERNEL_DOMAIN,
  actionId: "0x" + "00".repeat(32),
  action: ActionKind.FREEZE,
  // Provide every other field from the selected deployment profile and case.
};

const actionId = deriveActionId(tokenAddress, chainId, unsignedRequest);
const request = { ...unsignedRequest, actionId };
const calldata = encodeAction(request);
```

The package root is kernel version 2. Historical kernel version 1 helpers are
available from the explicit `@oraclizer/erc-trust-sdk/v1` subpath:

```ts
import {
  TRUST_DOMAIN,
  actionReceiptHash,
} from "@oraclizer/erc-trust-sdk/v1";
```

## Integration rules

- Populate all fields. Action-specific zero and nonzero requirements are
  security-relevant.
- Derive IDs from the actual chain ID and deployed contract address.
- Bind the current authority and epoch, the dependency root and epoch,
  nonce, validity, and action-specific commitments before encoding.
- Compare results against
  [`../vectors/conformance-v2.json`](../vectors/conformance-v2.json). The
  explicit `./v1` subpath is compared with
  [`../vectors/conformance-v1.json`](../vectors/conformance-v1.json).
- Recompute the stored receipt and emitted receipt hash independently.
- Never treat SDK output as proof that an upstream fact or authority is valid.

See the repository [integration guide](../docs/INTEGRATION.md) for the complete
request and failure lifecycle.

## Package entry points

The package root re-exports `src/kernel-v2.ts`, generated from
`spec/erc-trust-kernel-v2.json`. It provides the version 2 identifiers,
command hashes, dependency root, binding hash, nonce key, calldata, and the
unified action and reversal receipt hash. `./v1` preserves the historical
candidate 2 helper surface without making it the package default.
