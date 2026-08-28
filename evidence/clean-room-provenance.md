# Clean-room and dependency provenance

The Solidity reference is BSD-3-Clause. All production source files carry an
SPDX identifier.

The ERC-3643 compatibility work uses only publicly documented function
signatures and behavioral descriptions. No GPL ERC-3643 implementation file
was copied, translated, or adapted. The repository's
`IERC3643External.sol` contains narrow interface declarations; the
`MockERC3643Token` is an independently written test-only conformance fixture
and explicitly is not an ERC-3643 implementation.

SDK runtime dependency:

- `ethers@6.17.0`, MIT

SDK development dependencies:

- `typescript@7.0.2`, Apache-2.0
- `@types/node@24.10.1`, MIT

Exact transitive versions and integrity hashes are in `sdk/pnpm-lock.yaml`.
The installed transitive license inventory contains only MIT, Apache-2.0, and
0BSD packages. `pnpm audit --audit-level high` reported no known
vulnerabilities for the locked graph during candidate validation. This is a
time-bound registry result, not a continuing security guarantee.
Foundry, Solidity, Certora, Kontrol, KEVM, and Isabelle versions are recorded
in `evidence/release-manifest.json`; they are build/proof tools, not linked
runtime dependencies of the Solidity contracts.
