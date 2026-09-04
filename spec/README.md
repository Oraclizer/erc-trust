# Normative kernel machine source

This directory holds the single machine-readable source of the ERC-TRUST kernel
wire format: the domain constant, enums, request and receipt structs, hash
preimages, the kernel interface and its ERC-165 identifier, shape rules, the
case transition table, reason classes, and profile descriptors.

> **Unaudited. Not for production.** The kernel described here is version 2 of
> the wire format. The native token and the ERC-3643 profile adapter under
> `implementation/` both consume the generated copy of this kernel
> (`decisions/08-native-wiring.md`, `decisions/09-erc3643-profile-wiring.md`);
> the abstract model and the obligation ledger connect both endpoints
> (`decisions/10-refinement-closure.md`); the runtime identity of the successor code is
> bound by the runtime assurance change (`decisions/11-runtime-assurance.md`). Conformance of an endpoint is established only by the evidence lanes
> in `../evidence/current-profile-release-index-v3.json`, never by this
> directory.

## Layout

| Path | Role |
| --- | --- |
| `erc-trust-kernel-v2.json` | The normative machine source. Edit this file and regenerate; never edit generated files. |
| `decisions/` | Decision records that explain why the kernel has the shape it has, what was rejected, and what would reopen each decision. |
| `generated/IERCTrustKernel.sol` | Generated Solidity types and interfaces. |
| `../implementation/src/generated/IERCTrustKernel.sol` | Byte-identical copy consumed by the native token and the ERC-3643 adapter; the check mode rejects any drift between the two. |
| `generated/kernel-v2-abi.json` | Generated JSON ABI, selectors, calldata lengths, and interface identifier. |
| `generated/kernel-v2.md` | Generated human-readable rendering of the schema. |
| `../sdk/src/kernel-v2.ts` | Generated TypeScript types and hash helpers. |
| `../vectors/conformance-v2.json` | Generated conformance vectors for all six actions and three reversals. |
| `../schemas/receipt.schema.json` | Generated canonical JSON schema for the 17-field action and reversal receipt. |

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
text, that is a defect in the schema, not in the reproduction. Such a reproduction exists:
`scripts/independent-reproduction-v3.mjs`, written from the machine source, the generated prose
and ABI, and the vectors alone, records `evidence/independent-reproduction-v3.json` and is
rerun in continuous integration; the specification corrections it produced are recorded in
`decisions/11-runtime-assurance.md`.

## Relationship to the release manifest

The successor release manifest (`evidence/release-manifest.json`) protects
`spec/` as one of its roots, so the schema, the decision records, and the
generated renderings are bound to the same identity as the code they govern.

## Relationship to the draft

`docs/ERC-DRAFT.md` is the prose proposal for kernel version 2, written from
this schema. When the two disagree the schema is the authority and the prose
is corrected; the generated rendering `generated/kernel-v2.md` is the bridge
between them.
