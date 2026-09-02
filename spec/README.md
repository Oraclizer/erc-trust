# Normative kernel machine source

This directory holds the single machine-readable source of the ERC-TRUST kernel
wire format: the domain constant, enums, request and receipt structs, hash
preimages, the kernel interface and its ERC-165 identifier, shape rules, the
case transition table, reason classes, and profile descriptors.

> **Unaudited. Not for production.** The kernel described here is version 2 of
> the wire format. The Solidity under `implementation/` still implements
> version 1; wiring the implementation, the ERC-3643 profile, the formal
> mapping, and the runtime evidence to version 2 lands in later changes. Nothing
> in this directory claims that any implementation conforms to it yet.

## Layout

| Path | Role |
| --- | --- |
| `erc-trust-kernel-v2.json` | The normative machine source. Edit this file and regenerate; never edit generated files. |
| `decisions/` | Decision records that explain why the kernel has the shape it has, what was rejected, and what would reopen each decision. |
| `generated/IERCTrustKernel.sol` | Generated Solidity types and interfaces. |
| `generated/kernel-v2-abi.json` | Generated JSON ABI, selectors, calldata lengths, and interface identifier. |
| `generated/kernel-v2.md` | Generated human-readable rendering of the schema. |
| `../sdk/src/kernel-v2.ts` | Generated TypeScript types and hash helpers. |
| `../vectors/conformance-v2.json` | Generated conformance vectors for all six actions and three reversals. |

## Regenerate and check

```bash
pnpm --dir sdk install --frozen-lockfile --ignore-scripts
node scripts/generate-normative-kernel.mjs
node scripts/generate-normative-kernel.mjs --check
pnpm --dir sdk test
```

The generator recomputes the domain, tag, profile, and interface identifiers
from their strings and function signatures and refuses to run when a literal in
the schema disagrees with the recomputation. Continuous Integration runs the
check mode, so a schema edit without regeneration, or a hand edit of a
generated file, fails the build.

## Independent reproduction

An implementer or indexer should be able to reproduce every value in
`vectors/conformance-v2.json` from `erc-trust-kernel-v2.json` and the decision
records alone, without reading the generator, the SDK, or the Solidity under
`implementation/`. The reproduction needs keccak-256, the ABI encoding of
static tuples, and the ABI rule for function selectors, all of which the
schema restates under `hashes.encoding`; nothing else. If a value cannot be reproduced from the schema
text, that is a defect in the schema, not in the reproduction.

## Relationship to the draft

`docs/ERC-DRAFT.md` is the prose proposal. The prose is updated to kernel
version 2 in the documentation change that closes this project; until then the
schema, not the prose, is the authority for the version 2 wire format, and the
prose remains the authority for the shipped version 1 candidate.
