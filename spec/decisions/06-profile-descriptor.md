# Decision 06: one profile descriptor and one kernel interface for every endpoint

Status: frozen in kernel version 2 machine source (`structs.ProfileDescriptor`,
`profiles`, `interface`). Native endpoint wired (`implementation/src/TrustToken.sol`, see
`08-native-wiring.md`); ERC-3643 profile adapter wired (`09-erc3643-profile-wiring.md`).

## Decision

1. Every endpoint, native token or profile adapter, implements the same
   `IERCTrustKernel` interface with the same ERC-165 identifier. There is no
   longer a separate profile interface with a different function set and a
   different `trustProfile()` shape.
2. `trustProfile()` returns one `ProfileDescriptor`: `profileId`,
   `profileKind`, `standardVersion`, `actionMask`, `reversalMask`,
   `underlyingToken`, `manifestHash`, `full`, `proxySupported`.
3. `full` MUST be computed from the live topology and dependency state; it is
   never a stored constant. A native endpoint reports `full` as true only while
   its bound dependencies match their bindings; a sealed adapter reports true
   only while the sealed topology holds.
4. Profile identifiers are `keccak256("ERC-TRUST/v2/native-full")` and
   `keccak256("ERC-TRUST/v2/erc3643-verified-full")`. The strings name the
   profile's meaning, not a repository.
5. Views that only one profile needs (custody, settlement, and entitlement
   records; the exact-use ERC-7943 route) live in profile interfaces with
   their own identifiers and are not part of the kernel identifier.
6. A non-mutating assessment view is OPTIONAL. An implementation that offers
   one MUST name it `assessRegulatoryAction` or `assessRegulatoryReversal`,
   MUST take the same single request parameter as the corresponding execute
   function, MUST be `view`, and MUST produce the same outcome the execute
   path would produce for the same request and state (returning on
   applicable, reverting with the same typed error otherwise). These views
   are not part of the kernel interface identifier. The execute path itself
   already reveals the outcome class through its typed errors under a
   simulated call, which is why the view is optional.

## Why

In version 1 the native token exposed `IERCTrust` (identifier `0x15e0c235`,
ten functions) and the adapter exposed `IERCTrustProfile` (identifier
`0xbcc2afa9`, eight functions). `trustProfile()` returned three values on one
and four on the other. A registry, wallet, or indexer therefore needed two
code paths and two probes to answer the single question "does this endpoint
speak ERC-TRUST". One versioned interface, one command format, one receipt
format, and one discovery shape for both profiles is the condition under
which a single integrator code path can serve both.

The version 1 native token also stored `full` implicitly as a constant
(`trustProfile` was `pure`), which cannot express a dependency drift.

## Alternatives considered

- Keep two interfaces and document both identifiers. Rejected: it fails the
  single-endpoint requirement and doubles integrator cost.
- Make the assessment view mandatory. Rejected: the execute path under a
  simulated call already distinguishes applicable, rejected, and operational
  failure by error selector without state change, and a mandatory second
  surface creates a divergence risk between two decision paths for no
  additional observable.

## Consequences

- The kernel identifier is computed from nine functions; the native route
  interface and the dependency interface have separate identifiers.
- The native token's convenience getters that are not part of any declared
  interface are candidates for removal when the implementation is wired,
  which recovers runtime size.

## Reopen when

- A profile cannot report `full` from live state without an external call it
  is not allowed to make; it must then report `PARTIAL` and explain.
