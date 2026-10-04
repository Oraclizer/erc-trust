# Decision 14: route classes of the ERC-3643 Hook profile runtimes

Status: accepted. It classifies the existing Hook entrypoints and changes no source or runtime.

The route inventory (`scripts/trust12/tail-preparation/route_inventory_v2.py`) reads this record as
the normative class source of the Hook runtimes while the status line above starts with an
accepted status. The machine table is generated from this record into
`spec/generated/hook-route-classes-v1.json` by `route_inventory_v2.py render-classes`, and the
route inventory fails when the table and this record disagree.

## Decision

1. **Where the classes live.** The generated formal runtime bridge
   (`formal/isabelle/ERC_TRUST/TRUST_Runtime_Bridge_Generated.thy`) keeps classifying the Native
   and Partial runtimes and is not changed. The four Hook runtimes (`ERC3643HookAdapter`,
   `ERC3643HookGovernor`, `ERC3643HookCompliance`, `ERC3643HookFactory`) are classified by this
   record and its generated table. The Hook runtimes are bound by the TRUST 1.2 runtime identity,
   not by a formal bridge constant, and their route classes are consumed by the route inventory,
   not by a theorem.
2. **Vocabulary.** The thirteen constructors of `trust_route_class` keep their meaning. The five
   spec classes below are added for entrypoints that have no Native or Partial counterpart. No spec
   class has the name of a formal class, and no spec class is in the runtime-link domain.
3. **Reuse of a counterpart class is a review, not an inheritance.** A Hook adapter or governor
   selector that also exists on the Partial runtime it was derived from takes the same class only
   because its Hook source was read and has the same role. The inventory reports the counterpart
   class next to the class of this record and fails when the two differ. Equality of selectors
   alone never classifies a route.
4. **Runtime-link domain.** The only Hook routes in the runtime-link domain are
   `executeRegulatoryAction` and `executeRegulatoryReversal` of the adapter
   (`Route_Kernel_Command`). They are the typed entrypoints that the malformed input catalog lists
   for the Hook endpoint. The governor, the Compliance module and the factory have no route in the
   domain.
5. **Classes name roles, not reachability.** A route keeps the class of its role when it succeeds
   only during construction or never succeeds: `activateSeal` of the adapter and `sealFresh` of the
   governor are `Route_Seal_Command`, and `activate` and `bindToken` of the Compliance module are
   `Route_Compliance_Setup`. Why a state-changing route outside the typed commands lies outside the
   runtime-link relation is stated in its disposition, not in its class.
6. **Upstream token.** The pinned upstream token is a dependency of the Hook profile, not one of
   its runtimes, and its entrypoints are not classified here. Its Agent and owner roles are held by
   the endpoint and the inert governor alone (obligation row `HOOK-SOLE-AGENT`).
7. **Dispositions are justified elsewhere.** Every state-changing route outside the typed
   commands, of every profile, has one record in
   `evidence/trust12/runtime-link/tail-preparation/route-dispositions-v1.json`. A disposition is
   justified by a closed obligation row or by an accepted decision record of its own runtime other
   than this record; the route inventory refuses this record as a justification, so that the
   classes and the dispositions are reviewed separately. Decision 15 states the dispositions that
   no closed obligation row names.

## Spec classes

| Class | Mutating | Definition |
| --- | --- | --- |
| `Route_Hook_Balance_Callback` | yes | The post-balance callback of the endpoint, called by the bound Compliance module after an upstream balance change; it brings the upstream frozen amount of the touched accounts to their owned targets saturated at the new balances and records the applied amount. |
| `Route_Compliance_Callback` | yes | An ERC-3643 Compliance hook that the bound token calls after a mint, a transfer or a burn; once the endpoint is set, its only effect is to forward the touched accounts to the balance callback of the endpoint. |
| `Route_Compliance_Setup` | yes | A one-time binding or activation step of the Compliance module that the construction of the unit performs exactly once; every later call reverts. |
| `Route_Compliance_View` | no | A view or pure function of the Compliance module, including the pure unbinding entrypoint that always reverts. |
| `Route_Unit_Creation` | yes | Creation of a new conformance unit by the factory; it writes no storage of an existing unit. |

## Route class table

| Runtime | Signature | Selector | Class |
| --- | --- | --- | --- |
| `ERC3643HookAdapter` | `supportsInterface(bytes4)` | `0x01ffc9a7` | `Route_Kernel_View` |
| `ERC3643HookAdapter` | `profileGovernor()` | `0x164068a4` | `Route_Immutable_View` |
| `ERC3643HookAdapter` | `receipt(bytes32)` | `0x198a27aa` | `Route_Kernel_View` |
| `ERC3643HookAdapter` | `resynchroniseFrozen(address)` | `0x24933056` | `Route_Profile_Command` |
| `ERC3643HookAdapter` | `caseRecord(bytes32)` | `0x2a408631` | `Route_Kernel_View` |
| `ERC3643HookAdapter` | `executeRegulatoryReversal((bytes32,bytes32,bytes32,uint8,bytes32,uint64,bytes32,bytes32,uint64,uint256,uint48,uint48))` | `0x2b892e8f` | `Route_Kernel_Command` |
| `ERC3643HookAdapter` | `sealedTopologyLive()` | `0x2ca444f1` | `Route_Profile_View` |
| `ERC3643HookAdapter` | `executeRegulatoryAction((bytes32,bytes32,uint8,address,address,address,address,uint256,bytes32,bytes32,uint64,bytes32,bytes32,bytes32,bytes32,bytes32,uint64,uint256,uint48,uint48))` | `0x2f4e0773` | `Route_Kernel_Command` |
| `ERC3643HookAdapter` | `actionRecord(bytes32)` | `0x330fcfde` | `Route_Kernel_View` |
| `ERC3643HookAdapter` | `trustProfile()` | `0x5ba37779` | `Route_Kernel_View` |
| `ERC3643HookAdapter` | `dependencyState()` | `0x7bf8f8b6` | `Route_Kernel_View` |
| `ERC3643HookAdapter` | `activateSeal((address,uint256,bool)[])` | `0x8efb3179` | `Route_Seal_Command` |
| `ERC3643HookAdapter` | `ownedState(address)` | `0x963f57d1` | `Route_Profile_View` |
| `ERC3643HookAdapter` | `onTokenBalanceChanged(address,address)` | `0x9cbfdbf8` | `Route_Hook_Balance_Callback` |
| `ERC3643HookAdapter` | `authority()` | `0xbf7e214f` | `Route_Immutable_View` |
| `ERC3643HookAdapter` | `authorityRef()` | `0xf161af61` | `Route_Immutable_View` |
| `ERC3643HookAdapter` | `deriveReversalId((bytes32,bytes32,bytes32,uint8,bytes32,uint64,bytes32,bytes32,uint64,uint256,uint48,uint48))` | `0xf3315a6c` | `Route_Kernel_View` |
| `ERC3643HookAdapter` | `token()` | `0xfc0c546a` | `Route_Immutable_View` |
| `ERC3643HookAdapter` | `deriveActionId((bytes32,bytes32,uint8,address,address,address,address,uint256,bytes32,bytes32,uint64,bytes32,bytes32,bytes32,bytes32,bytes32,uint64,uint256,uint48,uint48))` | `0xfc6a9112` | `Route_Kernel_View` |
| `ERC3643HookGovernor` | `importManifestHash()` | `0x0ed81c40` | `Route_Seal_View` |
| `ERC3643HookGovernor` | `identityRegistry()` | `0x134e18f4` | `Route_Immutable_View` |
| `ERC3643HookGovernor` | `sealedTopologyLive(address)` | `0x155917d8` | `Route_Seal_View` |
| `ERC3643HookGovernor` | `compliance()` | `0x6290865d` | `Route_Immutable_View` |
| `ERC3643HookGovernor` | `topologySealed()` | `0x7f3bffea` | `Route_Seal_View` |
| `ERC3643HookGovernor` | `expectedRegistryCodeId()` | `0x83300190` | `Route_Immutable_View` |
| `ERC3643HookGovernor` | `expectedComplianceCodeId()` | `0xa35530ba` | `Route_Immutable_View` |
| `ERC3643HookGovernor` | `sealFresh()` | `0xa941f8f9` | `Route_Seal_Command` |
| `ERC3643HookGovernor` | `expectedTokenCodeId()` | `0xb534e5ab` | `Route_Immutable_View` |
| `ERC3643HookGovernor` | `sealedBinding()` | `0xb98705b4` | `Route_Seal_View` |
| `ERC3643HookGovernor` | `bootstrapAuthority()` | `0xce29a7f9` | `Route_Immutable_View` |
| `ERC3643HookGovernor` | `exclusiveAdapter()` | `0xf877bff3` | `Route_Seal_View` |
| `ERC3643HookGovernor` | `token()` | `0xfc0c546a` | `Route_Immutable_View` |
| `ERC3643HookCompliance` | `activate(address)` | `0x1c5a9d9c` | `Route_Compliance_Setup` |
| `ERC3643HookCompliance` | `bindToken(address)` | `0x3ff5aa02` | `Route_Compliance_Setup` |
| `ERC3643HookCompliance` | `unbindToken(address)` | `0x40db3b50` | `Route_Compliance_View` |
| `ERC3643HookCompliance` | `endpoint()` | `0x5e280f11` | `Route_Compliance_View` |
| `ERC3643HookCompliance` | `created(address,uint256)` | `0x5f8dead3` | `Route_Compliance_Callback` |
| `ERC3643HookCompliance` | `getTokenBound()` | `0x6a3edf28` | `Route_Immutable_View` |
| `ERC3643HookCompliance` | `transferred(address,address,uint256)` | `0x8baf29b4` | `Route_Compliance_Callback` |
| `ERC3643HookCompliance` | `destroyed(address,uint256)` | `0x8d2ea772` | `Route_Compliance_Callback` |
| `ERC3643HookCompliance` | `isTokenBound(address)` | `0x993e8b95` | `Route_Compliance_View` |
| `ERC3643HookCompliance` | `bound()` | `0xbe4df7d6` | `Route_Compliance_View` |
| `ERC3643HookCompliance` | `factory()` | `0xc45a0155` | `Route_Immutable_View` |
| `ERC3643HookCompliance` | `canTransfer(address,address,uint256)` | `0xe46638e6` | `Route_Compliance_View` |
| `ERC3643HookCompliance` | `token()` | `0xfc0c546a` | `Route_Immutable_View` |
| `ERC3643HookFactory` | `ADAPTER_CREATION_HASH()` | `0x1f0678e4` | `Route_Immutable_View` |
| `ERC3643HookFactory` | `deploy(bytes,address,bytes32,address,uint256,address[])` | `0x39c6db74` | `Route_Unit_Creation` |
| `ERC3643HookFactory` | `tokenCreationSource()` | `0xaf897f60` | `Route_Immutable_View` |

## Why

Route exhaustiveness asks that every public, external, inherited, governance and profile
entrypoint of every profile runtime belong to an abstract operation or to an explicit path outside
the runtime-link relation. The Native and Partial runtimes meet the first half through the route
tables of the formal bridge. The Hook runtimes had no normative class at all, so every
state-changing Hook selector was unclassified, including the two typed entrypoints of the
adapter.

Putting the Hook tables into the formal bridge would change the admitted formal root and reopen
every proof that imports the bridge, while no theorem consumes a Hook route class. A spec record
with a generated, checked table gives the same exhaustiveness check without that cost.

The compliance module names its constructing contract `factory`. In the Hook construction this is
the endpoint itself, because the deployment library runs inside the endpoint constructor; it is
not `ERC3643HookFactory`.

## Alternatives considered

- Add Hook route tables and new constructors of `trust_route_class` to the formal bridge.
  Rejected for TRUST 1.2: it changes the formal root without a consuming theorem. It is the right
  step when a theorem starts to read Hook route classes.
- Take the class of the identical Partial selector automatically. Rejected: the Hook governor and
  adapter have the same selectors with different callers and lifecycles (`activateSeal` never
  succeeds on the Hook adapter, while it is the seal step of the Partial adapter), so selector
  equality is evidence for a review, not a classification.
- One class for every Hook-only entrypoint. Rejected: the balance callback, the Compliance hooks,
  the one-time setup steps and the factory have different callers and different effects, and a
  disposition needs to name them separately.

## Consequences

- `route_inventory_v2.py` reads the generated table for the Hook runtimes and the formal route
  tables for the Native and Partial runtimes, and fails on any selector without a class, any class
  outside the vocabulary, any class whose mutability disagrees with the ABI, and any Hook class
  that differs from its counterpart class.
- Every change to a Hook runtime ABI reopens this record: the generated table and the route
  inventory fail until the table is updated.
- The dispositions that rely on construction-only or never-succeeding behavior are executed on a
  factory unit by the tests under `scripts/trust12/tail-preparation/route-dispositions`.

## Reopen when

- a theorem needs Hook route classes, which moves the table into the formal bridge;
- a Hook runtime gains, loses or renames an entrypoint;
- the upstream token, the Agent set or the owner of a Hook unit can change after construction.
