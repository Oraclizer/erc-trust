# External mutator inventory

## Native `TrustToken`

| Selector | Method | Class |
| --- | --- | --- |
| `0x095ea7b3` | `approve(address,uint256)` | ordinary ERC-20 |
| `0xa9059cbb` | `transfer(address,uint256)` | ordinary ERC-20 |
| `0x23b872dd` | `transferFrom(address,address,uint256)` | ordinary ERC-20 |
| `0x9da23539` | `executeRegulatoryAction(ActionRequest)` | canonical TRUST |
| `0x7aab169b` | `executeRegulatoryReversal(ReversalRequest)` | canonical TRUST reversal |
| `0x9295b54c` | `executeERC7943Action(ActionRequest)` | exact-use compatibility wrapper |
| `0x75c28d96` | `executeERC7943Reversal(ReversalRequest)` | exact-use compatibility reversal |
| `0xebe45cba` | `setFrozenTokens(address,uint256)` | self-call ticket target; raw calls fail |
| `0x9fc1d0e7` | `forcedTransfer(address,address,uint256)` | self-call ticket target; raw calls fail |
| `0xa4fc4aad` | `configureAuthority(...)` | governor governance |
| `0x1f78603d` | `configureDelegation(...)` | governor governance |
| `0xf60d7b6f` | `rebindDependency(...)` | governor governance |

No public mint, burn, upgrade, delegatecall, selfdestruct, proxy-admin, or
arbitrary-call method exists.

## ERC-3643 profile

`ERC3643TrustAdapter` exposes only typed action/reversal mutation. The upstream
fixture exposes direct and batch Agent methods so the tests can prove that
non-adapter callers fail. A real Full deployment must repeat the inventory
against its exact runtime code hash; ERC-3643 Agent mappings are not generally
enumerable, so `isAgent(adapter)` alone is insufficient.

## External-call inventory

| Owner | Call class | Target and bound | Failure behavior |
| --- | --- | --- | --- |
| `TrustPolicyBinding` | gas-bounded `staticcall` | exact dependency address, runtime code hash, configuration digest, schema, and epoch | revert, short/malformed data, wrong echo, wrong binding, or stale version becomes `OperationalFailure` |
| `TrustToken` | `address(this).call` | exact-use ticket binds caller, selector, calldata hash, policy binding, epochs, and command ID | raw/mismatched calls revert; ticket is deleted before effect and cannot persist |
| `ERC3643TrustAdapter` | `staticcall` | sealed Identity Registry `isVerified` and Compliance `canTransfer` endpoints | revert or non-canonical return fails closed |
| `ERC3643TrustAdapter` | stateful `call` | sealed token runtime and exact ERC-3643 mutator selector/calldata | token revert, false/malformed return, or failed postcondition reverts the entire adapter transition |

The source inventory contains no `delegatecall` or `selfdestruct`. The only
inline assembly is the bounded return-data word read in
`TrustPolicyBinding` and a selector read in `TrustToken`; neither changes the
external-call target or introduces an arbitrary-call surface.
