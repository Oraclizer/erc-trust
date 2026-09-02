# Decision 07: exact interface identity, domain, and canonical encoding

Status: frozen in kernel version 2 machine source (`domain`, `hashes.encoding`,
`interface.erc165`).

## Decision

1. The kernel domain is `keccak256("ERC-TRUST/v2")`. Version 1 used
   `keccak256("ERC-TRUST/reference-v1")`; the word "reference" named the
   reference implementation rather than the standard and is dropped.
2. The ERC-165 identifier of `IERCTrustKernel` is the XOR of the selectors of
   its nine functions, excluding the inherited `supportsInterface(bytes4)`.
   The literal value, the function signatures, and every selector are recorded
   in the schema and in `generated/kernel-v2-abi.json`; the generator refuses
   to run if the literal and the recomputation disagree.
3. Every hash preimage is the canonical ABI encoding of the listed items.
   An endpoint MUST reject calldata that is not the canonical encoding of the
   declared static tuple: wrong length, dirty high bits in narrow integer or
   address words, or enum values outside the declared range. For every
   accepted command the received calldata bytes and the canonical encoding
   therefore coincide, which is what lets an implementation hash the raw
   calldata while an indexer hashes an ABI encoding and both agree.
4. Enum values are part of the ABI. `ActionKind` is `FREEZE 0, SEIZE 1,
   CONFISCATE 2, LIQUIDATE 3, RESTRICT 4, RECOVER 5`, the order of the shipped
   version 1 SDK and vectors. `ReversalKind` is `UNFREEZE 0, RELEASE 1,
   UNRESTRICT 2`.

## Why

Version 1 never wrote its interface identifiers down anywhere a non-Solidity
implementer could find them; they existed only in compiler output. The draft
text said `type(IERCTrust).interfaceId`, which is a Solidity expression, not a
value. Version 1 also said the identifier preimage was `abi.encode` while the
native token hashed raw calldata; the two agree only because the token
rejects non-canonical calldata, and that condition was never stated.

Recording the literal in the schema and recomputing it on every generation
turns the identifier into a checked constant rather than a convention.

## Alternatives considered

- Keep the version 1 domain string. Rejected: third-party implementations
  would have to write "reference" into their own domain, and the version 2
  wire format is incompatible with version 1 in any case.
- Define the preimage as the received calldata bytes. Rejected: an indexer
  does not have the calldata when it reads a receipt, and a non-EVM tool has
  no calldata at all.

## Consequences

- Kernel version 2 identifiers, hashes, and receipts are incompatible with
  version 1. A deployment of either version is identified by its
  `standardVersion` and its domain.
- The size of a canonical action call is 644 bytes and of a reversal call is
  388 bytes; endpoints check the exact length.

## Reopen when

- A function is added to or removed from `IERCTrustKernel`; that is a new
  kernel version with a new identifier, never an in-place edit.
