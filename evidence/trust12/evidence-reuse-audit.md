# Evidence reuse checkpoint review

Status: PASS for the three repaired findings below, within the named local
checkpoint scope. This is not final TRUST 1.2 Assurance or aggregate release
approval. The reviewer did not modify source or run the tests.

The initial independent source review returned three findings: the baseline
inventory itself was not pinned; new owner metadata did not prevent release
promotion; and the ledger/runtime entrypoints could skip inventory validation.
The writer repaired all three and executed the isolated controls. The independent
follow-up reviewed the actual repaired code, the test implementation, and the
recorded output and recalculated the inventory and file digests.

The 37 baseline input hashes produce
`436845a990a6d229393c60eae0abaf8755474e6e6ea60aad1f6c9f6aadec718f`.
The checker now requires that fixed root. The release entrypoint requires
successor-development mode. Every entrypoint checks the inventory even if the
mutation receipt is absent or its source root already matches.

`evidence-reuse-controls.json` records one positive fixture and fourteen rejected
controls. The controls edit actual isolated runner/proof files, remove the
mutation receipt and invoke all three aggregate entrypoints. The independent
review verified this implementation and the current receipt hashes; it did not
claim a separate test execution. No additional return item was found for these
three repairs.

## Reviewed inputs

- `scripts/verify-trust12-evidence-reuse.mjs`: `ba99c4f1b32b173a696d92678b580f7e944073ae9ed81ee7b7685cd732f48fec`
- `scripts/test-trust12-evidence-reuse.mjs`: `f44bff21158707a04ed16cc68df788167606d55425efde9d50eab12a04d55bc5`
- `scripts/verify-current-profile-release-v3.mjs`: `8baa8b3c3ed6511ce0db87387c85389d7692601aa77fbad60d2e6f4fada9a8ed`
- `scripts/verify-obligation-ledger-v3.mjs`: `4a9c219bd873b65f005330e4e8b205b267df89d061ca9ab3aabfb8ab8a858415`
- `scripts/verify-runtime-binding-v3.mjs`: `e3d47a7217832463e7eee7f678d699bd5bc07058216956a3fda0e97aabd9591e`
- `evidence/trust12/evidence-reuse.json`: `7d25dc41ea3d83bd49e41f29139daa795815f9d324e2790a4258b6a40fe0979a`

## Remaining work

The global deterministic, Foundry and Isabelle receipts and the runtime-binding
bundle still need explicit local-provenance supersession. The 1.2 ledger still
contains mandatory model/run/symbolic/runtime obligations. New owner labels are
not proof credit. Replacing the development-only hold requires completed
profile-scoped evidence and a reviewed release decision.
