# Decision 15: dispositions of state-changing routes that no closed obligation names

Status: accepted. It states the existing behavior of eight routes and changes no source or runtime.

Every state-changing route outside the typed commands has a disposition record in
`evidence/trust12/runtime-link/tail-preparation/route-dispositions-v1.json`, and the route inventory
(`scripts/trust12/tail-preparation/route_inventory_v2.py`) accepts a disposition only when a closed
obligation row or an accepted decision record of the route's own runtime justifies it and a test
that passed in a recorded run executes the route on that runtime. Decision 14 explains why the
class record does not count as a justification. No closed obligation row names the eight routes
below, so this record states their behavior. Every item quotes the source lines it relies on, and
the disposition records cite those lines with their exact occurrence counts, which the route
inventory checks against the source.

## Decision

1. **Native allowance route.** `approve` of the Native endpoint
   (`implementation/src/TrustToken.sol`, runtime `TrustToken`) writes one entry of the allowance
   mapping and emits `Approval`:

   ```solidity
   if (spender == address(0)) revert TrustZeroAddress();
   _allowances[msg.sender][spender] = value;
   emit Approval(msg.sender, spender, value);
   ```

   It reads and writes no balance, frozen target, restriction flag, custody record, effect head,
   case, action record, nonce, binding or receipt. An allowance moves no tokens by itself: tokens
   leave an account under an allowance only through `transferFrom`, which spends the allowance and
   then runs the same ordinary transfer as `transfer` (`_ordinaryTransfer(from, to, value);`). The
   ordinary transfer checks the balance, the restriction flag of the sending account, the
   restriction flag of the receiving account and the unfrozen capacity before it moves the
   balance:

   ```solidity
   if (!canSend(from)) revert ERC7943CannotSend(from);
   if (!canReceive(to)) revert ERC7943CannotReceive(to);
   if (amount > available) revert ERC7943InsufficientUnfrozenBalance(from, amount, available);
   ```

   The allowances are part of the abstract compositional state, and no regulatory condition reads
   them (runtime-only list of `evidence/end-to-end-refinement/obligation-ledger-v3.json`). A
   restricted account can still set an allowance; the restriction applies when the allowance is
   spent. The account that spends an allowance is not an argument of the ordinary transfer, so its
   own restriction flag is not read. The pinned upstream ERC-3643 reference token behaves the same
   way: its `transferFrom` checks the frozen status of the sending and the receiving account and not
   of the account that spends the allowance. Whether a later profile also checks the spending
   account is outside this decision.

2. **Hook resynchronisation route.** `resynchroniseFrozen` of the Hook endpoint
   (`implementation/src/profiles/ERC3643HookAdapter.sol`, runtime `ERC3643HookAdapter`) is
   permissionless. It requires the live sealed topology and the ownership precondition, then brings
   the upstream frozen amount of one account to its owned target saturated at the current balance:

   ```solidity
   _requireLiveTopology(bytes32(0));
   _requireOwnedUpstreamState(bytes32(0), account);
   _syncFrozen(bytes32(0), account);
   ```

   It writes the applied frozen amount of that account and, through the Agent role of the
   endpoint, the upstream frozen amount of that account, and emits `FrozenTargetResynchronised`. It
   writes no owned target, restriction flag, case, action record, nonce or receipt. An upstream
   frozen amount or address freeze flag that differs from the state the endpoint applied fails the
   ownership precondition with reason 304:

   ```solidity
   revert TrustOperationalFailure(commandId, REASON_UPSTREAM_STATE_NOT_OWNED, _addressRef(account));
   ```

   The balance callback, which the Compliance module calls after an upstream transfer, mint or burn,
   runs the same synchronisation, and the source keeps this route "as an idempotent diagnosis and
   repair entrypoint under the same live topology checks". The function body is the body of the
   Partial endpoint's route, which closed obligation rows cover for the Partial runtime; this record
   does not take that coverage as evidence for the Hook runtime.

3. **Hook seal activation never succeeds.** `activateSeal` of the Hook endpoint (runtime
   `ERC3643HookAdapter`) admits only the governor as caller:

   ```solidity
   if (msg.sender != address(profileGovernor)) revert TrustUnauthorized(msg.sender, bytes32(0));
   ```

   The Hook governor (`implementation/src/profiles/ERC3643HookGovernor.sol`) and the deployment
   library (`implementation/src/profiles/ERC3643HookDeployment.sol`) contain no call to
   `activateSeal`, and the endpoint constructor seals through the internal
   `_activateEmptySeal();`. The seal flag is therefore set before any external call can reach the
   endpoint, and a call from the governor address would fail the next check with reason 301. No
   transaction can make the route succeed.

4. **Compliance setup steps run once, inside construction.** `activate` and `bindToken` of the
   Hook Compliance module (`implementation/src/profiles/ERC3643HookCompliance.sol`, runtime
   `ERC3643HookCompliance`) each set one field that no other code of the module writes:

   ```solidity
   require(msg.sender == factory && endpoint == address(0) && endpoint_ == factory, "invalid activation");
   require(!bound && msg.sender == token && token_ == token, "invalid binding");
   ```

   The module records the contract that constructed it as `factory`. In a Hook unit that is the
   endpoint, because the deployment library runs inside the endpoint constructor and calls
   `hook.activate(address(this));` once. `bound` is true once the unit is constructed, and
   `bindToken` is the only code that sets it and requires the token as caller, so the token bound
   the module during construction. After construction both fields are set, `unbindToken` always
   reverts (`revert("immutable binding");`), and both steps fail for every caller.

5. **Compliance callbacks only forward.** `created`, `transferred` and `destroyed` of the Hook
   Compliance module (runtime `ERC3643HookCompliance`) write no storage of their own. Once the
   endpoint is set, each accepts only the bound token as caller and passes the touched accounts to
   the balance callback of the endpoint:

   ```solidity
   require(msg.sender == token && bound, "only token");
   ITrustBalanceHook(endpoint).onTokenBalanceChanged(from, to);
   ```

   Before the endpoint is set, during the initial mint of construction, `created` only checks
   that the bound token calls it (`require(msg.sender == token && bound, "only bootstrap mint");`)
   and returns. In ERC-3643 the token calls `created` after a mint and `destroyed` after a burn,
   and only an Agent can mint or burn. The endpoint is the only Agent of the token (obligation row
   `HOOK-SOLE-AGENT`). Its constructor mints the initial supply once through the deployment library
   (`if (supply != 0) upstream.mint(holder, supply);`), and outside the constructor its only
   state-changing calls to the token are forced transfers, partial freezes and unfreezes, and address
   freezes; the endpoint source contains no burn call. After construction the token therefore calls
   neither route, and a call by any other account fails the token check.

## Why

Route exhaustiveness asks that every state-changing route outside the typed commands lie on an
explicit path outside the runtime-link relation. Closed obligation rows of the central refinement
ledger and of the TRUST 1.2 ledger cover twelve of the twenty such routes of the seven profile
runtimes on their own runtime. For the eight routes above that coverage is missing or indirect: the
allowance route is listed only as runtime-only bookkeeping, the two Hook adapter routes are covered
only on the Partial runtime, and the rows that cover the Hook construction and callbacks do not
name the Compliance routes. Each item states what the source does, so that a reviewer can accept
or reject each disposition on its quoted lines.

## Alternatives considered

- Add the allowance route to decision 14 as a Native section. Rejected: decision 14 classifies
  the Hook runtimes, and the route inventory refuses the class record as a justification so that
  classes and dispositions are reviewed separately. A Native section there would need that rule
  removed and would tie a Native disposition to the reopen conditions of the Hook classes.
- Add obligation rows for these routes to the ledgers. Rejected: the central refinement ledger and
  the TRUST 1.2 ledger are closed records of earlier work whose row inventories the required gate
  checks, and the routes need a statement of behavior, not a new proof obligation.
- Take the coverage of the Partial resynchronisation route as coverage of the Hook route because
  the function bodies are equal. Rejected: the Hook implementation evidence does not accept source
  similarity as Hook evidence; the Hook route is executed on a Hook unit instead.

## Consequences

- The disposition records of the eight routes cite the matching item of this record together with
  the quoted source lines, and the tests under `scripts/trust12/tail-preparation/route-dispositions`
  execute each route on its own runtime.
- The record describes the current behavior. A change of that behavior is a source change, which
  reopens the matching disposition.

## Reopen when

- `approve`, `transferFrom` or the ordinary transfer of the Native endpoint changes, or a decision
  makes an allowance or the account that spends it part of a regulatory condition;
- the Hook adapter, governor, deployment library or Compliance module changes;
- the token of a Hook unit gains another Agent, or the endpoint gains a mint or burn call.
