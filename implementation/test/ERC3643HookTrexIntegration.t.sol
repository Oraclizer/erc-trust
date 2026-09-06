// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {Vm} from "./TrustTestBase.t.sol";
import {IERCTrustKernel, TrustKernelTypes} from "../src/generated/IERCTrustKernel.sol";
import {ERC3643HookFactory, ERC3643CreationCode} from "../src/profiles/ERC3643HookFactory.sol";
import {ERC3643HookAdapter} from "../src/profiles/ERC3643HookAdapter.sol";
import {ERC3643HookGovernor} from "../src/profiles/ERC3643HookGovernor.sol";

import {ERC3643ProfileTypes} from "../src/profiles/ERC3643ProfileTypes.sol";

interface ITrexIntegrationToken {
    function batchTransfer(address[] calldata recipients, uint256[] calldata amounts) external;
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address who) external view returns (uint256);
    function getFrozenTokens(address who) external view returns (uint256);
    function isFrozen(address who) external view returns (bool);
    function isAgent(address who) external view returns (bool);
    function owner() external view returns (address);
    function totalSupply() external view returns (uint256);
    function compliance() external view returns (address);
    function allowance(address owner, address spender) external view returns (uint256);
}

interface HookFaultVm {
    function mockCallRevert(address target, bytes calldata data, bytes calldata result) external;
    function clearMockedCalls() external;
}

interface ArtifactVm {
    function getCode(string calldata artifact) external view returns (bytes memory);
}

/// @dev A factory-pin negative that is valid creation code for the factory's exact constructor ABI.
///      It satisfies the factory's three post-creation reads while implementing no TRUST behavior.
contract FactoryPinBypassEndpoint {
    address public token;
    address public profileGovernor;

    constructor(address, address, bytes32, address initialHolder, uint256, address[] memory) {
        token = initialHolder;
        profileGovernor = address(this);
    }

    function trustProfile() external view returns (TrustKernelTypes.ProfileDescriptor memory descriptor) {
        descriptor = TrustKernelTypes.ProfileDescriptor({
            profileId: keccak256("INVALID-FACTORY-BYPASS"),
            profileKind: TrustKernelTypes.ProfileKind.VERIFIED_FULL,
            standardVersion: 0,
            actionMask: 0,
            reversalMask: 0,
            underlyingToken: token,
            manifestHash: bytes32(0),
            full: true,
            proxySupported: false
        });
    }
}

/// @notice Integration against unmodified Tokeny T-REX 4.1.3, compiled separately by solc 0.8.17.
/// @dev Run scripts/prepare-trex-integration.py first. This is not the clean-room fixture.
contract ERC3643HookTrexIntegrationTest {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    bytes32 internal constant DOMAIN = TrustKernelTypes.DOMAIN;
    bytes32 internal constant AUTHORITY_REF = keccak256("ERC3643-AUTHORITY");
    uint256 internal constant SUPPLY = 1_000_000 ether;
    ERC3643HookFactory internal factory;
    ERC3643HookAdapter internal adapter;
    ERC3643HookGovernor internal governor;
    ITrexIntegrationToken internal upstream;
    address internal token;
    address internal buyer = address(0xb0b);
    address internal recovered = address(0xbeef);
    address internal holder = address(0x401d);

    function setUp() public {
        bytes memory creation = ArtifactVm(address(vm)).getCode("out/trust12/trex/out/Token.sol/Token.json");
        factory = new ERC3643HookFactory(creation);
        address[] memory eligible = new address[](3);
        eligible[0] = buyer;
        eligible[1] = recovered;
        eligible[2] = holder;
        bytes memory adapterCode = ArtifactVm(address(vm)).getCode("ERC3643HookAdapter.sol:ERC3643HookAdapter");
        address endpoint;
        address owner;
        (token, endpoint, owner) =
            factory.deploy(adapterCode, address(this), AUTHORITY_REF, address(this), SUPPLY, eligible);
        adapter = ERC3643HookAdapter(endpoint);
        governor = ERC3643HookGovernor(owner);
        upstream = ITrexIntegrationToken(token);
    }

    function testHookInboundCannotEscapeInSameTransaction() external {
        require(upstream.transfer(holder, 100 ether), "initial transfer");
        TrustKernelTypes.ActionRequest memory freeze = _request(TrustKernelTypes.ActionKind.FREEZE, 220, 100 ether);
        freeze.subject = holder;
        freeze.source = holder;
        freeze.actionId = adapter.deriveActionId(freeze);
        adapter.executeRegulatoryAction(freeze);
        TrustKernelTypes.ActionRequest memory seize = _request(TrustKernelTypes.ActionKind.SEIZE, 221, 30 ether);
        seize.subject = holder;
        seize.source = holder;
        seize.actionId = adapter.deriveActionId(seize);
        adapter.executeRegulatoryAction(seize);
        require(upstream.getFrozenTokens(holder) == 70 ether, "saturated after seize");
        require(upstream.transfer(holder, 30 ether), "inbound");
        require(upstream.getFrozenTokens(holder) == 100 ether, "hook did not freeze inbound");
        vm.prank(holder);
        (bool escaped,) = token.call(abi.encodeCall(upstream.transfer, (buyer, 30 ether)));
        require(!escaped, "inbound escaped");
        require(upstream.balanceOf(holder) == 100 ether, "failed transfer changed balance");
        (uint256 target, uint256 applied,) = adapter.ownedState(holder);
        require(target == 100 ether && applied == 100 ether, "owned floor not updated");
        adapter.executeRegulatoryReversal(_reversal(seize.actionId, TrustKernelTypes.ReversalKind.RELEASE, 222));
        require(
            upstream.balanceOf(holder) == 130 ether && upstream.getFrozenTokens(holder) == 100 ether, "release floor"
        );
        adapter.executeRegulatoryReversal(_reversal(freeze.actionId, TrustKernelTypes.ReversalKind.UNFREEZE, 223));
        require(upstream.getFrozenTokens(holder) == 0, "unfreeze");
    }

    function testHookTransferFromInboundAndSelfTransfer() external {
        TrustKernelTypes.ActionRequest memory freeze = _request(TrustKernelTypes.ActionKind.FREEZE, 30, 100 ether);
        freeze.subject = holder;
        freeze.source = holder;
        freeze.actionId = adapter.deriveActionId(freeze);
        adapter.executeRegulatoryAction(freeze);
        require(upstream.approve(buyer, 30 ether), "approve");
        vm.prank(buyer);
        require(upstream.transferFrom(address(this), holder, 30 ether), "transferFrom");
        require(upstream.getFrozenTokens(holder) == 30 ether, "transferFrom floor");
        vm.prank(holder);
        (bool escaped,) = token.call(abi.encodeCall(upstream.transfer, (buyer, 1)));
        require(!escaped, "transferFrom inbound escaped");
        uint256 beforeBalance = upstream.balanceOf(address(this));
        require(upstream.transfer(address(this), 1), "self transfer");
        require(upstream.balanceOf(address(this)) == beforeBalance, "self transfer changed balance");
    }

    function testHookSixActionsThreeReversalsAndFinalReceipt() external {
        for (uint8 kind; kind < 6; ++kind) {
            TrustKernelTypes.ActionRequest memory request =
                _request(TrustKernelTypes.ActionKind(kind), 100 + kind, kind == 4 ? 0 : 7 ether);
            vm.recordLogs();
            bytes32 result = adapter.executeRegulatoryAction(request);
            Vm.Log[] memory logs = vm.getRecordedLogs();
            require(logs.length > 0 && logs[logs.length - 1].emitter == address(adapter), "last emitter");
            require(
                logs[logs.length - 1].topics[0] == keccak256("RegulatoryActionApplied(bytes32,uint8,bytes32,bytes32)"),
                "last topic"
            );
            require(abi.decode(logs[logs.length - 1].data, (bytes32)) == result, "last receipt");
            require(adapter.receipt(request.actionId).receiptHash == result, "stored receipt");
            if (kind == 0 || kind == 1 || kind == 4) {
                adapter.executeRegulatoryReversal(
                    _reversal(request.actionId, TrustKernelTypes.ReversalKind(kind == 4 ? 2 : kind), 200 + kind)
                );
            }
        }
        require(upstream.totalSupply() == SUPPLY, "supply");
        require(upstream.getFrozenTokens(address(this)) == 0 && !upstream.isFrozen(address(this)), "overlay reversal");
    }

    function testHookFactoryFreshStateAndAuthorityClosure() external {
        require(adapter.trustProfile().full && adapter.sealedTopologyLive(), "live full");
        require(upstream.owner() == address(governor) && upstream.isAgent(address(adapter)), "owner agent");
        require(
            !upstream.isAgent(address(factory)) && !upstream.isAgent(address(this))
                && !upstream.isAgent(address(0xbad)),
            "hidden Agent admitted"
        );
        require(upstream.totalSupply() == SUPPLY && upstream.balanceOf(address(this)) == SUPPLY, "initial supply");
        bytes[] memory calls = new bytes[](9);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", buyer, 1);
        calls[1] = abi.encodeWithSignature("burn(address,uint256)", address(this), 1);
        calls[2] = abi.encodeWithSignature("forcedTransfer(address,address,uint256)", address(this), buyer, 1);
        calls[3] = abi.encodeWithSignature("freezePartialTokens(address,uint256)", holder, 1);
        calls[4] = abi.encodeWithSignature("setAddressFrozen(address,bool)", holder, true);
        calls[5] = abi.encodeWithSignature("addAgent(address)", buyer);
        calls[6] = abi.encodeWithSignature("setCompliance(address)", buyer);
        calls[7] = abi.encodeWithSignature("transferOwnership(address)", buyer);
        calls[8] = abi.encodeWithSignature("recoveryAddress(address,address,address)", address(this), buyer, buyer);
        for (uint256 i; i < calls.length; ++i) {
            (bool ok, bytes memory reason) = token.call(calls[i]);
            require(!ok, "raw token authority bypass");
            string memory expected = (i < 5 || i == 8)
                ? "AgentRole: caller does not have the Agent role"
                : "Ownable: caller is not the owner";
            require(
                keccak256(reason) == keccak256(abi.encodeWithSignature("Error(string)", expected)),
                "wrong authority failure"
            );
            (ok,) = address(governor).call(calls[i]);
            require(!ok, "governor forwarded");
        }
        (bool callback,) = address(adapter).call(abi.encodeCall(adapter.onTokenBalanceChanged, (address(this), buyer)));
        require(!callback, "unauthenticated callback");
        address[] memory empty = new address[](0);
        (bool forged,) = address(factory)
            .call(abi.encodeCall(factory.deploy, (hex"00", address(this), AUTHORITY_REF, address(this), 0, empty)));
        require(!forged, "arbitrary creation accepted");
    }

    function testHookRemovalIsDetectedByInboundConsumer() external {
        vm.etch(upstream.compliance(), hex"60006000f3");
        require(!adapter.trustProfile().full, "hook drift must close full");
        TrustKernelTypes.ActionRequest memory freeze = _request(TrustKernelTypes.ActionKind.FREEZE, 400, 1);
        (bool ok,) = address(adapter).call(abi.encodeCall(adapter.executeRegulatoryAction, (freeze)));
        require(!ok, "dependency drift accepted");
    }

    function testHookPostCallbackFailureRollsBackTransferAndAllowance() external {
        require(upstream.approve(buyer, 50 ether), "approval");
        uint256 beforeFrom = upstream.balanceOf(address(this));
        uint256 beforeTo = upstream.balanceOf(holder);
        HookFaultVm(address(vm))
            .mockCallRevert(
                upstream.compliance(),
                abi.encodeWithSignature("transferred(address,address,uint256)", address(this), holder, 30 ether),
                abi.encodeWithSignature("Error(string)", "post callback failed")
            );
        vm.prank(buyer);
        (bool ok, bytes memory reason) =
            token.call(abi.encodeCall(upstream.transferFrom, (address(this), holder, 30 ether)));
        require(
            !ok && keccak256(reason) == keccak256(abi.encodeWithSignature("Error(string)", "post callback failed")),
            "wrong failure branch"
        );
        require(
            upstream.balanceOf(address(this)) == beforeFrom && upstream.balanceOf(holder) == beforeTo,
            "balance rollback"
        );
        require(upstream.allowance(address(this), buyer) == 50 ether, "allowance rollback");
        HookFaultVm(address(vm)).clearMockedCalls();
        require(upstream.transfer(holder, 30 ether), "transfer after dependency recovery");
    }

    function testHookDirectFreshZeroSupplyAndCreationPins() external {
        address[] memory empty = new address[](0);
        ERC3643HookAdapter direct = new ERC3643HookAdapter(
            factory.tokenCreationSource(), address(this), AUTHORITY_REF, address(this), 0, empty
        );
        require(direct.trustProfile().full && direct.token() != token, "direct fresh unit");
        require(ITrexIntegrationToken(direct.token()).totalSupply() == 0, "zero supply");
        bytes memory seeded = ArtifactVm(address(vm)).getCode("out/trust12/trex-seeded/out/Token.sol/Token.json");
        ERC3643CreationCode badSource = new ERC3643CreationCode(seeded);
        bool rejected;
        try new ERC3643HookAdapter(
            address(badSource), address(this), AUTHORITY_REF, address(this), SUPPLY, empty
        ) returns (
            ERC3643HookAdapter
        ) {
            rejected = false;
        } catch (bytes memory initialReason) {
            rejected = keccak256(initialReason)
                == keccak256(abi.encodeWithSignature("Error(string)", "unapproved token creation code"));
        }
        require(rejected, "seeded initial state was admitted");
        bytes memory smuggled =
            ArtifactVm(address(vm)).getCode("ERC3643HookTrexIntegration.t.sol:FactoryPinBypassEndpoint");
        (bool ok, bytes memory factoryReason) = address(factory)
            .call(
                abi.encodeCall(factory.deploy, (smuggled, address(this), AUTHORITY_REF, address(this), SUPPLY, empty))
            );
        require(!ok, "factory accepted bypass endpoint");
        require(
            keccak256(factoryReason)
                == keccak256(abi.encodeWithSignature("Error(string)", "unapproved adapter creation code")),
            "wrong factory pin rejection"
        );
        vm.prank(address(adapter));
        (ok,) = address(governor).call(abi.encodeCall(governor.sealFresh, ()));
        require(!ok, "seal repeated");
    }

    function testHookBatchAndZeroTransfersEnforceTargets() external {
        TrustKernelTypes.ActionRequest memory freeze = _request(TrustKernelTypes.ActionKind.FREEZE, 500, 100 ether);
        freeze.subject = holder;
        freeze.source = holder;
        freeze.actionId = adapter.deriveActionId(freeze);
        adapter.executeRegulatoryAction(freeze);
        address[] memory recipients = new address[](2);
        recipients[0] = holder;
        recipients[1] = buyer;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 30 ether;
        amounts[1] = 20 ether;
        upstream.batchTransfer(recipients, amounts);
        require(upstream.getFrozenTokens(holder) == 30 ether, "batch inbound floor");
        vm.prank(holder);
        require(upstream.transfer(holder, 0), "zero self transfer");
        require(upstream.getFrozenTokens(holder) == 30 ether, "zero transfer altered floor");
        (bool unverified,) = token.call(abi.encodeCall(upstream.transfer, (address(0xdead), 1)));
        require(!unverified, "unknown identity admitted");
    }

    function testHookReceiptObservesRestrictedCustodySource() external {
        TrustKernelTypes.ActionRequest memory seize = _request(TrustKernelTypes.ActionKind.SEIZE, 600, 9 ether);
        adapter.executeRegulatoryAction(seize);
        TrustKernelTypes.ActionRequest memory restrict = _request(TrustKernelTypes.ActionKind.RESTRICT, 601, 0);
        restrict.subject = address(adapter);
        restrict.source = address(adapter);
        restrict.actionId = adapter.deriveActionId(restrict);
        adapter.executeRegulatoryAction(restrict);
        TrustKernelTypes.ActionRequest memory dispose = _request(TrustKernelTypes.ActionKind.CONFISCATE, 602, 9 ether);
        dispose.source = address(adapter);
        dispose.caseId = seize.caseId;
        dispose.actionId = adapter.deriveActionId(dispose);
        bytes32 beforeObservation = _custodyDispositionObservation(dispose, seize);
        adapter.executeRegulatoryAction(dispose);
        bytes32 afterObservation = _custodyDispositionObservation(dispose, seize);
        require(upstream.isFrozen(address(adapter)), "forced transfer lost restriction");
        require(adapter.receipt(dispose.actionId).preState == beforeObservation, "wrong actual pre-observation");
        require(adapter.receipt(dispose.actionId).postState == afterObservation, "wrong actual post-observation");
    }

    function _balance(address account) internal view returns (uint256) {
        return upstream.balanceOf(account);
    }

    function _frozen(address account) internal view returns (uint256) {
        return upstream.getFrozenTokens(account);
    }

    function _restricted(address account) internal view returns (bool) {
        return upstream.isFrozen(account);
    }

    function _custodyDispositionObservation(
        TrustKernelTypes.ActionRequest memory request,
        TrustKernelTypes.ActionRequest memory seize
    ) internal view returns (bytes32) {
        (uint256 frozenTarget,, bool ownedRestricted) = adapter.ownedState(request.subject);
        TrustKernelTypes.CaseRecord memory caseState = adapter.caseRecord(request.caseId);
        bool custodyActive = caseState.phase == TrustKernelTypes.CasePhase.OPEN;
        ERC3643ProfileTypes.CustodyRecord memory custody = ERC3643ProfileTypes.CustodyRecord({
            custodian: seize.custodian,
            declaredPriorHolder: seize.source,
            encumberedAmount: custodyActive ? seize.amount : 0,
            actionId: seize.actionId,
            active: custodyActive
        });
        ERC3643ProfileTypes.EffectHead memory emptyHead;
        bytes32 subjectObservation = keccak256(
            abi.encode(
                _balance(request.subject),
                frozenTarget,
                _frozen(request.subject),
                ownedRestricted,
                _restricted(request.subject)
            )
        );
        bytes32 sourceObservation = keccak256(
            abi.encode(_balance(request.source), _restricted(request.source), custodyActive ? seize.amount : uint256(0))
        );
        bytes32 destinationObservation =
            keccak256(abi.encode(_balance(request.destination), _restricted(request.destination), uint256(0)));
        return keccak256(
            abi.encode(
                token,
                request.subject,
                subjectObservation,
                request.source,
                sourceObservation,
                request.destination,
                destinationObservation,
                custody,
                emptyHead,
                emptyHead,
                caseState,
                governor.sealedBinding()
            )
        );
    }

    function _request(TrustKernelTypes.ActionKind action, uint256 nonce, uint256 amount)
        internal
        view
        returns (TrustKernelTypes.ActionRequest memory request)
    {
        (bytes32 root, uint64 epoch) = adapter.dependencyState();
        request = TrustKernelTypes.ActionRequest({
            domain: DOMAIN,
            actionId: bytes32(0),
            action: action,
            subject: address(this),
            source: address(this),
            destination: address(0),
            custodian: address(0),
            amount: amount,
            caseId: keccak256(abi.encode("PROFILE-CASE", nonce)),
            dependencyRoot: root,
            dependencyEpoch: epoch,
            provenanceCommitment: keccak256(abi.encode("ORDER", nonce)),
            settlementCommitment: bytes32(0),
            proceedsCommitment: bytes32(0),
            entitlementCommitment: bytes32(0),
            authorityRef: AUTHORITY_REF,
            authorityEpoch: 1,
            nonce: nonce,
            validAfter: 0,
            validBefore: type(uint48).max
        });
        if (action == TrustKernelTypes.ActionKind.SEIZE) {
            request.destination = address(adapter);
            request.custodian = address(adapter);
        } else if (action == TrustKernelTypes.ActionKind.CONFISCATE) {
            request.destination = buyer;
        } else if (action == TrustKernelTypes.ActionKind.LIQUIDATE) {
            request.destination = buyer;
            request.settlementCommitment = keccak256(abi.encode("SETTLEMENT", nonce));
            request.proceedsCommitment = keccak256(abi.encode("PROCEEDS", nonce));
        } else if (action == TrustKernelTypes.ActionKind.RECOVER) {
            request.destination = recovered;
            request.entitlementCommitment = keccak256(abi.encode("ENTITLEMENT", nonce));
        }
        request.actionId = adapter.deriveActionId(request);
    }

    function _reversal(bytes32 actionId, TrustKernelTypes.ReversalKind reversal, uint256 nonce)
        internal
        view
        returns (TrustKernelTypes.ReversalRequest memory request)
    {
        (bytes32 root, uint64 epoch) = adapter.dependencyState();
        request = TrustKernelTypes.ReversalRequest({
            domain: DOMAIN,
            reversalId: bytes32(0),
            actionId: actionId,
            reversal: reversal,
            dependencyRoot: root,
            dependencyEpoch: epoch,
            provenanceCommitment: keccak256(abi.encode("REVERSAL-ORDER", nonce)),
            authorityRef: AUTHORITY_REF,
            authorityEpoch: 1,
            nonce: nonce,
            validAfter: 0,
            validBefore: type(uint48).max
        });
        request.reversalId = adapter.deriveReversalId(request);
    }
}
