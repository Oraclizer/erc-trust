// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

/// @notice The ERC-7943 fungible FREEZE subset exercised by this pilot.
/// @dev This is not the complete IERC7943Fungible interface: forcedTransfer is
///      intentionally outside the vertical slice.
interface IERC7943FreezePilot is IERC165 {
    event Frozen(address indexed account, uint256 amount);

    function setFrozenTokens(address account, uint256 amount) external returns (bool);

    function canSend(address account) external view returns (bool);

    function canReceive(address account) external view returns (bool);

    function getFrozenTokens(address account) external view returns (uint256);

    function canTransfer(address from, address to, uint256 amount) external view returns (bool);
}

interface IBoundPolicy {
    function configurationDigest() external view returns (bytes32);

    function assess(
        bytes32 commandDigest,
        address subject,
        uint256 targetFrozenAmount,
        bytes32 bindingHash,
        uint64 policyEpoch
    )
        external
        view
        returns (
            uint8 outcome,
            uint16 reason,
            bytes32 dependencyRef,
            bytes32 echoedCommandDigest,
            bytes32 echoedBindingHash
        );
}

/// @notice Non-production Native FREEZE vertical slice for ERC-TRUST.
/// @dev It intentionally excludes the other five actions, ERC-3643, proxying,
///      migration, forcedTransfer, and production governance configuration.
contract TrustFreezePilot is IERC7943FreezePilot {
    enum ActionKind {
        FREEZE,
        SEIZE,
        CONFISCATE,
        RESTRICT,
        RECOVER,
        LIQUIDATE
    }

    enum ReversalKind {
        UNFREEZE,
        RELEASE,
        UNRESTRICT
    }

    enum ProfileKind {
        NATIVE_FULL,
        VERIFIED_PROFILE,
        LEGACY_UNTYPED,
        UNSUPPORTED
    }

    enum AssessmentOutcome {
        APPLICABLE,
        REJECTED,
        OPERATIONAL_FAILURE
    }

    enum AuthorizationStatus {
        NONE,
        PREPARED,
        CANCELLED,
        CONSUMED
    }

    enum CaseLifecycle {
        NONE,
        ACTIVE
    }

    struct ActionRequest {
        bytes32 actionId;
        bytes32 caseId;
        ActionKind action;
        address subject;
        address source;
        address destination;
        uint256 amount;
        bytes32 policyBindingHash;
        bytes32 provenanceHash;
        bytes32 actionDataHash;
        uint64 authorityEpoch;
        uint64 policyEpoch;
        uint256 nonce;
        uint48 validAfter;
        uint48 deadline;
    }

    struct ReversalRequest {
        bytes32 commandId;
        bytes32 caseId;
        ReversalKind reversal;
        address subject;
        uint256 amount;
        bytes32 policyBindingHash;
        bytes32 provenanceHash;
        uint64 authorityEpoch;
        uint64 policyEpoch;
        uint256 nonce;
        uint48 validAfter;
        uint48 deadline;
    }

    struct AuthorizationEnvelope {
        bytes32 authorizationId;
        bytes32 authorityRef;
        address issuer;
        address actor;
        bytes32 delegationRef;
        bytes proof;
    }

    struct AssessmentResult {
        AssessmentOutcome outcome;
        uint16 reason;
        bytes32 dependencyRef;
        bytes32 commandDigest;
        bytes32 currentBindingHash;
    }

    struct BindingView {
        address policy;
        address identity;
        bytes32 policyCodeId;
        bytes32 identityCodeId;
        bytes32 configurationDigest;
        bytes32 standardVersion;
        uint64 policyEpoch;
        uint64 authorityEpoch;
    }

    struct ReceiptView {
        bytes32 receiptHash;
        bytes32 commandDigest;
        bytes32 authorizationId;
        bytes32 authorityRef;
        bytes32 policyBindingHash;
        bytes32 provenanceHash;
        bytes32 preObservationHash;
        bytes32 postObservationHash;
    }

    struct CaseRecord {
        ActionKind action;
        CaseLifecycle lifecycle;
        address subject;
        uint256 amount;
        bytes32 lastActionId;
    }

    struct ActionRecord {
        AuthorizationStatus status;
        bytes32 commandDigest;
        bytes32 receiptHash;
    }

    struct PreparedRoute {
        bool exists;
        bytes32 routeKey;
        bytes32 actionId;
        bytes32 caseId;
        bytes32 authorizationId;
        bytes32 authorityRef;
        address actor;
        address subject;
        uint256 targetFrozenAmount;
        uint256 nonce;
        bytes32 commandDigest;
        bytes32 policyBindingHash;
        bytes32 provenanceHash;
        uint64 authorityEpoch;
        uint64 policyEpoch;
    }

    struct FreezeExecution {
        bytes32 actionId;
        bytes32 caseId;
        address subject;
        address source;
        address destination;
        uint256 targetFrozenAmount;
        uint256 nonce;
        bytes32 commandDigest;
        bytes32 authorizationId;
        bytes32 authorityRef;
        bytes32 policyBindingHash;
        bytes32 provenanceHash;
        uint64 authorityEpoch;
    }

    struct ReversalExecution {
        bytes32 commandId;
        bytes32 caseId;
        ReversalKind reversal;
        address subject;
        uint256 amount;
        uint256 nonce;
        bytes32 commandDigest;
        bytes32 authorizationId;
        bytes32 authorityRef;
        bytes32 policyBindingHash;
        bytes32 provenanceHash;
        uint64 authorityEpoch;
    }

    error TrustRejected(bytes32 commandId, uint16 reason);
    error TrustOperationalFailure(bytes32 commandId, uint16 reason, bytes32 dependencyRef);

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
    event RegulatoryActionApplied(
        bytes32 indexed actionId,
        bytes32 indexed caseId,
        ActionKind indexed action,
        address source,
        address destination,
        uint256 amount,
        bytes32 authorizationId,
        bytes32 authorityRef,
        bytes32 policyBindingHash,
        bytes32 provenanceHash,
        bytes32 preObservationHash,
        bytes32 postObservationHash,
        bytes32 receiptHash
    );
    event RegulatoryReversalApplied(
        bytes32 indexed commandId,
        bytes32 indexed caseId,
        ReversalKind indexed reversal,
        uint256 amount,
        bytes32 authorizationId,
        bytes32 preObservationHash,
        bytes32 postObservationHash,
        bytes32 receiptHash
    );
    event AuthorizationCancelled(bytes32 indexed authorizationId, bytes32 indexed commandId, uint64 authorityEpoch);
    event TrustBindingChanged(
        bytes32 indexed previousBindingHash,
        bytes32 indexed currentBindingHash,
        uint64 policyEpoch,
        uint64 authorityEpoch
    );

    uint16 public constant REASON_UNSUPPORTED = 1;
    uint16 public constant REASON_INVALID_AUTHORIZATION = 2;
    uint16 public constant REASON_STALE_BINDING = 3;
    uint16 public constant REASON_REPLAY = 4;
    uint16 public constant REASON_NO_STATE_CHANGE = 5;
    uint16 public constant REASON_POLICY_DENIED = 6;
    uint16 public constant REASON_ROUTE_TICKET = 7;
    uint16 public constant REASON_INVALID_STATE = 8;
    uint16 public constant REASON_ORDINARY_GATE = 9;

    uint16 public constant REASON_POLICY_UNAVAILABLE = 100;
    uint16 public constant REASON_MALFORMED_RESPONSE = 101;
    uint16 public constant REASON_CODE_ID_MISMATCH = 102;
    uint16 public constant REASON_CONFIG_MISMATCH = 103;
    uint16 public constant REASON_RESPONSE_MISMATCH = 104;

    bytes32 public constant STANDARD_VERSION = keccak256("ERC-TRUST/FREEZE-PILOT/v1");
    bytes32 public constant MANIFEST_HASH = keccak256("ERC-TRUST/FREEZE-PILOT/MANIFEST/UNFROZEN");
    bytes32 internal constant ACTION_DOMAIN = keccak256("ERC-TRUST/ACTION-COMMAND/v1");
    bytes32 internal constant REVERSAL_DOMAIN = keccak256("ERC-TRUST/REVERSAL-COMMAND/v1");
    bytes32 internal constant AUTHORIZATION_DOMAIN = keccak256("ERC-TRUST/AUTHORIZATION/v1");
    bytes32 internal constant RECEIPT_DOMAIN = keccak256("ERC-TRUST/RECEIPT/v1");
    bytes32 internal constant GOVERNANCE_DOMAIN = keccak256("ERC-TRUST/GOVERNANCE/v1");
    uint256 internal constant POLICY_GAS_LIMIT = 200_000;

    string public constant name = "ERC-TRUST FREEZE Pilot";
    string public constant symbol = "TRUST-P";
    uint8 public constant decimals = 18;

    address public immutable authority;
    bytes32 public immutable authorityRef;
    uint64 public authorityEpoch;
    uint64 public policyEpoch;

    IBoundPolicy public policy;
    bytes32 public policyCodeId;
    bytes32 public configurationDigest;
    bytes32 public bindingHash;

    uint256 public totalSupply;
    mapping(address account => uint256 amount) private _balances;
    mapping(address owner => mapping(address spender => uint256 amount)) private _allowances;
    mapping(address account => uint256 amount) private _frozenAbsolute;
    mapping(bytes32 caseId => CaseRecord record) private _cases;
    mapping(bytes32 actionId => ActionRecord record) private _actions;
    mapping(bytes32 actionId => ReceiptView receipt) private _receipts;
    mapping(bytes32 authorizationId => AuthorizationStatus status) private _authorizationStatuses;
    mapping(bytes32 nonceKey => AuthorizationStatus status) private _nonceStatuses;
    mapping(bytes32 routeKey => bytes32 authorizationId) private _routeAuthorizations;
    mapping(bytes32 authorizationId => PreparedRoute route) private _preparedRoutes;

    constructor(
        address authority_,
        bytes32 authorityRef_,
        IBoundPolicy policy_,
        address initialHolder,
        uint256 initialSupply
    ) {
        if (
            authority_ == address(0) || authorityRef_ == bytes32(0) || address(policy_).code.length == 0
                || initialHolder == address(0)
        ) {
            revert TrustRejected(bytes32(0), REASON_INVALID_AUTHORIZATION);
        }

        authority = authority_;
        authorityRef = authorityRef_;
        authorityEpoch = 1;
        policyEpoch = 1;

        (bool bindingOk, bytes32 policyConfig, bytes32 dependencyRef) = _readPolicyConfiguration(policy_);
        if (!bindingOk) {
            revert TrustOperationalFailure(bytes32(0), REASON_CONFIG_MISMATCH, dependencyRef);
        }

        policy = policy_;
        policyCodeId = address(policy_).codehash;
        configurationDigest = policyConfig;
        bindingHash = _computeBindingHash(policy_, policyCodeId, policyConfig, policyEpoch, authorityEpoch);

        totalSupply = initialSupply;
        _balances[initialHolder] = initialSupply;
        emit Transfer(address(0), initialHolder, initialSupply);
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC7943FreezePilot).interfaceId;
    }

    function trustProfile()
        external
        pure
        returns (ProfileKind profile, uint256 actionMask, address underlyingToken, bytes32 manifestHash)
    {
        return (ProfileKind.UNSUPPORTED, uint256(1), address(0), MANIFEST_HASH);
    }

    function trustBinding() external view returns (BindingView memory) {
        return BindingView({
            policy: address(policy),
            identity: address(0),
            policyCodeId: policyCodeId,
            identityCodeId: bytes32(0),
            configurationDigest: configurationDigest,
            standardVersion: STANDARD_VERSION,
            policyEpoch: policyEpoch,
            authorityEpoch: authorityEpoch
        });
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        if (spender == address(0)) {
            revert TrustRejected(bytes32(0), REASON_ORDINARY_GATE);
        }
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _ordinaryTransfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        if (currentAllowance < amount) {
            revert TrustRejected(bytes32(0), REASON_ORDINARY_GATE);
        }

        _checkOrdinaryTransfer(from, to, amount);
        unchecked {
            _allowances[from][msg.sender] = currentAllowance - amount;
        }
        _move(from, to, amount);
        return true;
    }

    function canSend(address account) public pure returns (bool) {
        return account != address(0);
    }

    function canReceive(address account) public pure returns (bool) {
        return account != address(0);
    }

    function getFrozenTokens(address account) external view returns (uint256) {
        return _frozenAbsolute[account];
    }

    function canTransfer(address from, address to, uint256 amount) public view returns (bool) {
        if (!canSend(from) || !canReceive(to)) {
            return false;
        }

        uint256 balance = _balances[from];
        if (amount > balance) {
            return false;
        }

        uint256 frozen = _frozenAbsolute[from];
        uint256 available = frozen >= balance ? 0 : balance - frozen;
        return amount <= available;
    }

    function assessRegulatoryAction(ActionRequest calldata request, AuthorizationEnvelope calldata authorization)
        external
        view
        returns (AssessmentResult memory)
    {
        return _assessAction(request, authorization, msg.sender);
    }

    function assessRegulatoryReversal(ReversalRequest calldata request, AuthorizationEnvelope calldata authorization)
        external
        view
        returns (AssessmentResult memory)
    {
        return _assessReversal(request, authorization, msg.sender);
    }

    function executeRegulatoryAction(ActionRequest calldata request, AuthorizationEnvelope calldata authorization)
        external
        returns (bytes32 receiptHash)
    {
        AssessmentResult memory assessment = _assessAction(request, authorization, msg.sender);
        _requireApplicable(request.actionId, assessment);

        FreezeExecution memory execution = FreezeExecution({
            actionId: request.actionId,
            caseId: request.caseId,
            subject: request.subject,
            source: request.source,
            destination: request.destination,
            targetFrozenAmount: request.amount,
            nonce: request.nonce,
            commandDigest: assessment.commandDigest,
            authorizationId: authorization.authorizationId,
            authorityRef: authorization.authorityRef,
            policyBindingHash: request.policyBindingHash,
            provenanceHash: request.provenanceHash,
            authorityEpoch: request.authorityEpoch
        });
        return _applyFreeze(execution, AuthorizationStatus.NONE);
    }

    function executeRegulatoryReversal(ReversalRequest calldata request, AuthorizationEnvelope calldata authorization)
        external
        returns (bytes32 receiptHash)
    {
        AssessmentResult memory assessment = _assessReversal(request, authorization, msg.sender);
        _requireApplicable(request.commandId, assessment);

        ReversalExecution memory execution = ReversalExecution({
            commandId: request.commandId,
            caseId: request.caseId,
            reversal: request.reversal,
            subject: request.subject,
            amount: request.amount,
            nonce: request.nonce,
            commandDigest: assessment.commandDigest,
            authorizationId: authorization.authorizationId,
            authorityRef: authorization.authorityRef,
            policyBindingHash: request.policyBindingHash,
            provenanceHash: request.provenanceHash,
            authorityEpoch: request.authorityEpoch
        });
        return _applyUnfreeze(execution);
    }

    function prepareRegulatoryAction(ActionRequest calldata request, AuthorizationEnvelope calldata authorization)
        external
        returns (bytes32 routeKey)
    {
        AssessmentResult memory assessment = _assessAction(request, authorization, msg.sender);
        _requireApplicable(request.actionId, assessment);

        routeKey = _freezeRouteKey(
            authorization.actor,
            request.subject,
            request.amount,
            request.policyBindingHash,
            request.authorityEpoch,
            request.policyEpoch
        );
        if (_routeAuthorizations[routeKey] != bytes32(0)) {
            revert TrustRejected(request.actionId, REASON_REPLAY);
        }

        bytes32 nonceKey = _nonceKey(authorization.authorityRef, request.authorityEpoch, request.nonce);
        _authorizationStatuses[authorization.authorizationId] = AuthorizationStatus.PREPARED;
        _nonceStatuses[nonceKey] = AuthorizationStatus.PREPARED;
        _actions[request.actionId] = ActionRecord({
            status: AuthorizationStatus.PREPARED, commandDigest: assessment.commandDigest, receiptHash: bytes32(0)
        });
        _routeAuthorizations[routeKey] = authorization.authorizationId;
        _preparedRoutes[authorization.authorizationId] = PreparedRoute({
            exists: true,
            routeKey: routeKey,
            actionId: request.actionId,
            caseId: request.caseId,
            authorizationId: authorization.authorizationId,
            authorityRef: authorization.authorityRef,
            actor: authorization.actor,
            subject: request.subject,
            targetFrozenAmount: request.amount,
            nonce: request.nonce,
            commandDigest: assessment.commandDigest,
            policyBindingHash: request.policyBindingHash,
            provenanceHash: request.provenanceHash,
            authorityEpoch: request.authorityEpoch,
            policyEpoch: request.policyEpoch
        });
    }

    function setFrozenTokens(address account, uint256 amount) external returns (bool) {
        bytes32 routeKey = _freezeRouteKey(msg.sender, account, amount, bindingHash, authorityEpoch, policyEpoch);
        bytes32 authorizationId = _routeAuthorizations[routeKey];
        PreparedRoute memory prepared = _preparedRoutes[authorizationId];

        if (
            authorizationId == bytes32(0) || !prepared.exists || prepared.routeKey != routeKey
                || prepared.actor != msg.sender || prepared.subject != account || prepared.targetFrozenAmount != amount
                || prepared.policyBindingHash != bindingHash || prepared.authorityEpoch != authorityEpoch
                || prepared.policyEpoch != policyEpoch
                || _authorizationStatuses[authorizationId] != AuthorizationStatus.PREPARED
        ) {
            revert TrustRejected(bytes32(0), REASON_ROUTE_TICKET);
        }

        AssessmentResult memory policyAssessment =
            _assessBoundPolicy(prepared.commandDigest, prepared.subject, prepared.targetFrozenAmount);
        _requireApplicable(prepared.actionId, policyAssessment);

        delete _routeAuthorizations[routeKey];
        delete _preparedRoutes[authorizationId];

        FreezeExecution memory execution = FreezeExecution({
            actionId: prepared.actionId,
            caseId: prepared.caseId,
            subject: prepared.subject,
            source: prepared.subject,
            destination: address(0),
            targetFrozenAmount: prepared.targetFrozenAmount,
            nonce: prepared.nonce,
            commandDigest: prepared.commandDigest,
            authorizationId: prepared.authorizationId,
            authorityRef: prepared.authorityRef,
            policyBindingHash: prepared.policyBindingHash,
            provenanceHash: prepared.provenanceHash,
            authorityEpoch: prepared.authorityEpoch
        });
        _applyFreeze(execution, AuthorizationStatus.PREPARED);
        return true;
    }

    function cancelAuthorization(bytes32 authorizationId) external {
        PreparedRoute memory prepared = _preparedRoutes[authorizationId];
        if (
            msg.sender != authority || !prepared.exists
                || _authorizationStatuses[authorizationId] != AuthorizationStatus.PREPARED
        ) {
            revert TrustRejected(prepared.actionId, REASON_INVALID_AUTHORIZATION);
        }

        bytes32 nonceKey = _nonceKey(prepared.authorityRef, prepared.authorityEpoch, prepared.nonce);
        _authorizationStatuses[authorizationId] = AuthorizationStatus.CANCELLED;
        _nonceStatuses[nonceKey] = AuthorizationStatus.CANCELLED;
        _actions[prepared.actionId].status = AuthorizationStatus.CANCELLED;
        delete _routeAuthorizations[prepared.routeKey];
        delete _preparedRoutes[authorizationId];
        emit AuthorizationCancelled(authorizationId, prepared.actionId, authorityEpoch);
    }

    function rebindPolicy(IBoundPolicy newPolicy, bytes32 governanceAuthorizationId, uint256 nonce) external {
        if (msg.sender != authority || governanceAuthorizationId == bytes32(0) || address(newPolicy).code.length == 0) {
            revert TrustRejected(governanceAuthorizationId, REASON_INVALID_AUTHORIZATION);
        }

        bytes32 governanceNonceKey = keccak256(abi.encode(GOVERNANCE_DOMAIN, authorityRef, authorityEpoch, nonce));
        if (
            _authorizationStatuses[governanceAuthorizationId] != AuthorizationStatus.NONE
                || _nonceStatuses[governanceNonceKey] != AuthorizationStatus.NONE
        ) {
            revert TrustRejected(governanceAuthorizationId, REASON_REPLAY);
        }

        (bool bindingOk, bytes32 policyConfig, bytes32 dependencyRef) = _readPolicyConfiguration(newPolicy);
        if (!bindingOk) {
            revert TrustOperationalFailure(governanceAuthorizationId, REASON_CONFIG_MISMATCH, dependencyRef);
        }

        bytes32 previousBindingHash = bindingHash;
        uint64 nextPolicyEpoch = policyEpoch + 1;
        bytes32 nextCodeId = address(newPolicy).codehash;
        bytes32 nextBindingHash =
            _computeBindingHash(newPolicy, nextCodeId, policyConfig, nextPolicyEpoch, authorityEpoch);

        _authorizationStatuses[governanceAuthorizationId] = AuthorizationStatus.CONSUMED;
        _nonceStatuses[governanceNonceKey] = AuthorizationStatus.CONSUMED;
        policy = newPolicy;
        policyCodeId = nextCodeId;
        configurationDigest = policyConfig;
        policyEpoch = nextPolicyEpoch;
        bindingHash = nextBindingHash;

        emit TrustBindingChanged(previousBindingHash, nextBindingHash, nextPolicyEpoch, authorityEpoch);
    }

    function authorizationStatus(bytes32 authorizationId) external view returns (AuthorizationStatus) {
        return _authorizationStatuses[authorizationId];
    }

    function nonceStatus(bytes32 authorityRef_, uint64 authorityEpoch_, uint256 nonce)
        external
        view
        returns (AuthorizationStatus)
    {
        return _nonceStatuses[_nonceKey(authorityRef_, authorityEpoch_, nonce)];
    }

    function actionRecord(bytes32 actionId)
        external
        view
        returns (AuthorizationStatus status, bytes32 commandDigest_, bytes32 receiptHash)
    {
        ActionRecord storage record = _actions[actionId];
        return (record.status, record.commandDigest, record.receiptHash);
    }

    function actionReceipt(bytes32 actionId) external view returns (ReceiptView memory) {
        return _receipts[actionId];
    }

    function caseRecord(bytes32 caseId) external view returns (CaseRecord memory) {
        return _cases[caseId];
    }

    function routeAuthorization(bytes32 routeKey) external view returns (bytes32) {
        return _routeAuthorizations[routeKey];
    }

    function preparedRoute(bytes32 authorizationId) external view returns (PreparedRoute memory) {
        return _preparedRoutes[authorizationId];
    }

    function commandDigest(ActionRequest calldata request) public view returns (bytes32) {
        bytes32 identityHash = keccak256(
            abi.encode(
                request.actionId, request.caseId, request.action, request.subject, request.source, request.destination
            )
        );
        bytes32 payloadHash = keccak256(
            abi.encode(request.amount, request.policyBindingHash, request.provenanceHash, request.actionDataHash)
        );
        bytes32 authorizationScopeHash = keccak256(
            abi.encode(request.authorityEpoch, request.policyEpoch, request.nonce, request.validAfter, request.deadline)
        );
        return keccak256(
            abi.encode(
                ACTION_DOMAIN,
                block.chainid,
                address(this),
                address(0),
                STANDARD_VERSION,
                identityHash,
                payloadHash,
                authorizationScopeHash
            )
        );
    }

    function reversalCommandDigest(ReversalRequest calldata request) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                REVERSAL_DOMAIN,
                block.chainid,
                address(this),
                address(0),
                STANDARD_VERSION,
                request.commandId,
                request.caseId,
                request.reversal,
                request.subject,
                request.amount,
                request.policyBindingHash,
                request.provenanceHash,
                request.authorityEpoch,
                request.policyEpoch,
                request.nonce,
                request.validAfter,
                request.deadline
            )
        );
    }

    function authorizationProofDigest(bytes32 commandDigest_, AuthorizationEnvelope calldata authorization)
        public
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                AUTHORIZATION_DOMAIN,
                authorization.authorizationId,
                authorization.authorityRef,
                authorization.issuer,
                authorization.actor,
                authorization.delegationRef,
                commandDigest_
            )
        );
    }

    function computeRouteKey(
        address caller,
        bytes4 selector,
        bytes32 calldataHash,
        bytes32 bindingHash_,
        uint64 authorityEpoch_,
        uint64 policyEpoch_
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(caller, selector, calldataHash, bindingHash_, authorityEpoch_, policyEpoch_));
    }

    function previewPreparedReceipt(bytes32 authorizationId)
        external
        view
        returns (bytes32 preObservationHash, bytes32 postObservationHash, bytes32 receiptHash)
    {
        PreparedRoute memory prepared = _preparedRoutes[authorizationId];
        if (!prepared.exists) {
            return (bytes32(0), bytes32(0), bytes32(0));
        }

        preObservationHash = _observationHash(prepared.subject, prepared.caseId);
        postObservationHash = keccak256(
            abi.encode(
                prepared.subject,
                _balances[prepared.subject],
                prepared.targetFrozenAmount,
                prepared.caseId,
                uint8(ActionKind.FREEZE),
                uint8(CaseLifecycle.ACTIVE),
                prepared.subject,
                prepared.targetFrozenAmount,
                prepared.actionId
            )
        );
        bytes32 resultHash = keccak256(
            abi.encode("FREEZE", prepared.subject, _frozenAbsolute[prepared.subject], prepared.targetFrozenAmount)
        );
        receiptHash = _receiptHash(
            prepared.commandDigest,
            prepared.authorizationId,
            prepared.authorityRef,
            prepared.policyBindingHash,
            prepared.provenanceHash,
            preObservationHash,
            postObservationHash,
            resultHash
        );
    }

    function stateFingerprint(
        bytes32 actionId,
        bytes32 authorizationId,
        bytes32 caseId,
        bytes32 routeKey,
        address subject,
        address other,
        uint256 nonce
    ) external view returns (bytes32) {
        bytes32 ledgerFingerprint = keccak256(
            abi.encode(
                totalSupply, _balances[subject], _balances[other], _allowances[subject][other], _frozenAbsolute[subject]
            )
        );
        bytes32 commandFingerprint = keccak256(abi.encode(_cases[caseId], _actions[actionId], _receipts[actionId]));
        PreparedRoute memory prepared = _preparedRoutes[authorizationId];
        bytes32 preparedFingerprint = prepared.exists ? keccak256(abi.encode(prepared)) : bytes32(0);
        bytes32 authorizationFingerprint = keccak256(
            abi.encode(
                _authorizationStatuses[authorizationId],
                _nonceStatuses[_nonceKey(authorityRef, authorityEpoch, nonce)],
                _routeAuthorizations[routeKey],
                preparedFingerprint
            )
        );
        bytes32 bindingFingerprint = keccak256(
            abi.encode(address(policy), policyCodeId, configurationDigest, bindingHash, policyEpoch, authorityEpoch)
        );
        return
            keccak256(abi.encode(ledgerFingerprint, commandFingerprint, authorizationFingerprint, bindingFingerprint));
    }

    function _assessAction(ActionRequest calldata request, AuthorizationEnvelope calldata authorization, address caller)
        internal
        view
        returns (AssessmentResult memory)
    {
        bytes32 digest = commandDigest(request);
        AssessmentResult memory structural = _assessCommon(
            request.actionId,
            request.caseId,
            request.subject,
            request.source,
            request.destination,
            request.amount,
            request.policyBindingHash,
            request.actionDataHash,
            request.authorityEpoch,
            request.policyEpoch,
            request.nonce,
            request.validAfter,
            request.deadline,
            digest,
            authorization,
            caller
        );
        if (structural.outcome != AssessmentOutcome.APPLICABLE) {
            return structural;
        }
        if (request.action != ActionKind.FREEZE) {
            return _rejected(digest, REASON_UNSUPPORTED);
        }
        if (_frozenAbsolute[request.subject] == request.amount) {
            return _rejected(digest, REASON_NO_STATE_CHANGE);
        }
        if (
            _cases[request.caseId].lifecycle != CaseLifecycle.NONE
                && (_cases[request.caseId].action != ActionKind.FREEZE
                    || _cases[request.caseId].subject != request.subject)
        ) {
            return _rejected(digest, REASON_INVALID_STATE);
        }

        return _assessBoundPolicy(digest, request.subject, request.amount);
    }

    function _assessReversal(
        ReversalRequest calldata request,
        AuthorizationEnvelope calldata authorization,
        address caller
    ) internal view returns (AssessmentResult memory) {
        bytes32 digest = reversalCommandDigest(request);
        if (
            request.commandId == bytes32(0) || request.caseId == bytes32(0) || request.subject == address(0)
                || request.reversal != ReversalKind.UNFREEZE
        ) {
            return _rejected(digest, REASON_UNSUPPORTED);
        }
        if (
            request.policyBindingHash != bindingHash || request.authorityEpoch != authorityEpoch
                || request.policyEpoch != policyEpoch
        ) {
            return _rejected(digest, REASON_STALE_BINDING);
        }
        if (block.timestamp < request.validAfter || (request.deadline != 0 && block.timestamp > request.deadline)) {
            return _rejected(digest, REASON_INVALID_AUTHORIZATION);
        }
        if (
            _authorizationStatuses[authorization.authorizationId] != AuthorizationStatus.NONE
                || _actions[request.commandId].status != AuthorizationStatus.NONE
                || _nonceStatuses[_nonceKey(authorization.authorityRef, request.authorityEpoch, request.nonce)]
                    != AuthorizationStatus.NONE
        ) {
            return _rejected(digest, REASON_REPLAY);
        }
        if (!_validAuthorization(digest, authorization, caller)) {
            return _rejected(digest, REASON_INVALID_AUTHORIZATION);
        }
        if (
            request.amount == 0 || request.amount > _frozenAbsolute[request.subject]
                || _cases[request.caseId].lifecycle != CaseLifecycle.ACTIVE
                || _cases[request.caseId].subject != request.subject
        ) {
            return _rejected(digest, REASON_INVALID_STATE);
        }

        return _assessBoundPolicy(digest, request.subject, _frozenAbsolute[request.subject] - request.amount);
    }

    function _assessCommon(
        bytes32 commandId,
        bytes32 caseId,
        address subject,
        address source,
        address destination,
        uint256 amount,
        bytes32 policyBindingHash_,
        bytes32 actionDataHash,
        uint64 authorityEpoch_,
        uint64 policyEpoch_,
        uint256 nonce,
        uint48 validAfter,
        uint48 deadline,
        bytes32 digest,
        AuthorizationEnvelope calldata authorization,
        address caller
    ) internal view returns (AssessmentResult memory) {
        if (
            commandId == bytes32(0) || caseId == bytes32(0) || subject == address(0) || source != subject
                || destination != address(0) || actionDataHash != keccak256(abi.encode(amount))
        ) {
            return _rejected(digest, REASON_UNSUPPORTED);
        }
        if (policyBindingHash_ != bindingHash || authorityEpoch_ != authorityEpoch || policyEpoch_ != policyEpoch) {
            return _rejected(digest, REASON_STALE_BINDING);
        }
        if (block.timestamp < validAfter || (deadline != 0 && block.timestamp > deadline)) {
            return _rejected(digest, REASON_INVALID_AUTHORIZATION);
        }
        if (
            _authorizationStatuses[authorization.authorizationId] != AuthorizationStatus.NONE
                || _actions[commandId].status != AuthorizationStatus.NONE
                || _nonceStatuses[_nonceKey(authorization.authorityRef, authorityEpoch_, nonce)]
                    != AuthorizationStatus.NONE
        ) {
            return _rejected(digest, REASON_REPLAY);
        }
        if (!_validAuthorization(digest, authorization, caller)) {
            return _rejected(digest, REASON_INVALID_AUTHORIZATION);
        }

        return AssessmentResult({
            outcome: AssessmentOutcome.APPLICABLE,
            reason: 0,
            dependencyRef: bytes32(0),
            commandDigest: digest,
            currentBindingHash: bindingHash
        });
    }

    function _validAuthorization(bytes32 digest, AuthorizationEnvelope calldata authorization, address caller)
        internal
        view
        returns (bool)
    {
        if (
            authorization.authorizationId == bytes32(0) || authorization.authorityRef != authorityRef
                || authorization.issuer != authority || authorization.actor != caller
                || authorization.proof.length != 32
        ) {
            return false;
        }

        bytes calldata proof = authorization.proof;
        bytes32 suppliedProof;
        assembly ("memory-safe") {
            suppliedProof := calldataload(proof.offset)
        }
        return suppliedProof == authorizationProofDigest(digest, authorization);
    }

    function _assessBoundPolicy(bytes32 digest, address subject, uint256 targetFrozenAmount)
        internal
        view
        returns (AssessmentResult memory)
    {
        if (address(policy).codehash != policyCodeId) {
            return _operationalFailure(digest, REASON_CODE_ID_MISMATCH, bytes32(uint256(uint160(address(policy)))));
        }

        (bool configOk, bytes32 currentConfiguration, bytes32 configDependency) = _readPolicyConfiguration(policy);
        if (!configOk || currentConfiguration != configurationDigest) {
            return _operationalFailure(digest, REASON_CONFIG_MISMATCH, configDependency);
        }

        (bool ok, bytes memory result) = address(policy).staticcall{gas: POLICY_GAS_LIMIT}(
            abi.encodeCall(IBoundPolicy.assess, (digest, subject, targetFrozenAmount, bindingHash, policyEpoch))
        );
        if (!ok) {
            return _operationalFailure(digest, REASON_POLICY_UNAVAILABLE, bytes32(uint256(uint160(address(policy)))));
        }
        if (result.length != 160) {
            return _operationalFailure(digest, REASON_MALFORMED_RESPONSE, bytes32(uint256(result.length)));
        }

        (uint8 outcome, uint16 reason, bytes32 dependencyRef, bytes32 echoedCommandDigest, bytes32 echoedBindingHash) =
            abi.decode(result, (uint8, uint16, bytes32, bytes32, bytes32));

        if (
            echoedCommandDigest != digest || echoedBindingHash != bindingHash
                || outcome > uint8(AssessmentOutcome.OPERATIONAL_FAILURE)
        ) {
            return _operationalFailure(digest, REASON_RESPONSE_MISMATCH, dependencyRef);
        }
        if (outcome == uint8(AssessmentOutcome.REJECTED)) {
            return AssessmentResult({
                outcome: AssessmentOutcome.REJECTED,
                reason: reason == 0 ? REASON_POLICY_DENIED : reason,
                dependencyRef: dependencyRef,
                commandDigest: digest,
                currentBindingHash: bindingHash
            });
        }
        if (outcome == uint8(AssessmentOutcome.OPERATIONAL_FAILURE)) {
            return _operationalFailure(digest, reason == 0 ? REASON_POLICY_UNAVAILABLE : reason, dependencyRef);
        }

        return AssessmentResult({
            outcome: AssessmentOutcome.APPLICABLE,
            reason: 0,
            dependencyRef: bytes32(0),
            commandDigest: digest,
            currentBindingHash: bindingHash
        });
    }

    function _applyUnfreeze(ReversalExecution memory execution) internal returns (bytes32 receiptHash) {
        uint256 oldFrozen = _frozenAbsolute[execution.subject];
        uint256 newFrozen = oldFrozen - execution.amount;
        bytes32 preObservationHash = _observationHash(execution.subject, execution.caseId);

        bytes32 nonceKey = _nonceKey(execution.authorityRef, execution.authorityEpoch, execution.nonce);
        _authorizationStatuses[execution.authorizationId] = AuthorizationStatus.CONSUMED;
        _nonceStatuses[nonceKey] = AuthorizationStatus.CONSUMED;
        _actions[execution.commandId] = ActionRecord({
            status: AuthorizationStatus.CONSUMED, commandDigest: execution.commandDigest, receiptHash: bytes32(0)
        });
        _frozenAbsolute[execution.subject] = newFrozen;

        CaseRecord storage caseRecord_ = _cases[execution.caseId];
        caseRecord_.action = ActionKind.FREEZE;
        caseRecord_.lifecycle = CaseLifecycle.ACTIVE;
        caseRecord_.subject = execution.subject;
        caseRecord_.amount = newFrozen;
        caseRecord_.lastActionId = execution.commandId;

        bytes32 postObservationHash = _observationHash(execution.subject, execution.caseId);
        bytes32 resultHash =
            keccak256(abi.encode("UNFREEZE", execution.subject, oldFrozen, newFrozen, execution.amount));
        receiptHash = _receiptHash(
            execution.commandDigest,
            execution.authorizationId,
            execution.authorityRef,
            execution.policyBindingHash,
            execution.provenanceHash,
            preObservationHash,
            postObservationHash,
            resultHash
        );

        _actions[execution.commandId].receiptHash = receiptHash;
        _receipts[execution.commandId] = ReceiptView({
            receiptHash: receiptHash,
            commandDigest: execution.commandDigest,
            authorizationId: execution.authorizationId,
            authorityRef: execution.authorityRef,
            policyBindingHash: execution.policyBindingHash,
            provenanceHash: execution.provenanceHash,
            preObservationHash: preObservationHash,
            postObservationHash: postObservationHash
        });

        emit Frozen(execution.subject, newFrozen);
        emit RegulatoryReversalApplied(
            execution.commandId,
            execution.caseId,
            execution.reversal,
            execution.amount,
            execution.authorizationId,
            preObservationHash,
            postObservationHash,
            receiptHash
        );
    }

    function _applyFreeze(FreezeExecution memory execution, AuthorizationStatus expectedStatus)
        internal
        returns (bytes32 receiptHash)
    {
        uint256 oldFrozen = _frozenAbsolute[execution.subject];
        if (oldFrozen == execution.targetFrozenAmount) {
            revert TrustRejected(execution.actionId, REASON_NO_STATE_CHANGE);
        }

        bytes32 nonceKey = _nonceKey(execution.authorityRef, execution.authorityEpoch, execution.nonce);
        if (
            _authorizationStatuses[execution.authorizationId] != expectedStatus
                || _nonceStatuses[nonceKey] != expectedStatus || _actions[execution.actionId].status != expectedStatus
        ) {
            revert TrustRejected(execution.actionId, REASON_REPLAY);
        }

        bytes32 preObservationHash = _observationHash(execution.subject, execution.caseId);
        _authorizationStatuses[execution.authorizationId] = AuthorizationStatus.CONSUMED;
        _nonceStatuses[nonceKey] = AuthorizationStatus.CONSUMED;
        _actions[execution.actionId] = ActionRecord({
            status: AuthorizationStatus.CONSUMED, commandDigest: execution.commandDigest, receiptHash: bytes32(0)
        });
        _frozenAbsolute[execution.subject] = execution.targetFrozenAmount;

        CaseRecord storage caseRecord_ = _cases[execution.caseId];
        caseRecord_.action = ActionKind.FREEZE;
        caseRecord_.lifecycle = CaseLifecycle.ACTIVE;
        caseRecord_.subject = execution.subject;
        caseRecord_.amount = execution.targetFrozenAmount;
        caseRecord_.lastActionId = execution.actionId;

        bytes32 postObservationHash = _observationHash(execution.subject, execution.caseId);
        bytes32 resultHash = keccak256(abi.encode("FREEZE", execution.subject, oldFrozen, execution.targetFrozenAmount));
        receiptHash = _receiptHash(
            execution.commandDigest,
            execution.authorizationId,
            execution.authorityRef,
            execution.policyBindingHash,
            execution.provenanceHash,
            preObservationHash,
            postObservationHash,
            resultHash
        );
        _actions[execution.actionId].receiptHash = receiptHash;
        _receipts[execution.actionId] = ReceiptView({
            receiptHash: receiptHash,
            commandDigest: execution.commandDigest,
            authorizationId: execution.authorizationId,
            authorityRef: execution.authorityRef,
            policyBindingHash: execution.policyBindingHash,
            provenanceHash: execution.provenanceHash,
            preObservationHash: preObservationHash,
            postObservationHash: postObservationHash
        });

        emit Frozen(execution.subject, execution.targetFrozenAmount);
        emit RegulatoryActionApplied(
            execution.actionId,
            execution.caseId,
            ActionKind.FREEZE,
            execution.source,
            execution.destination,
            execution.targetFrozenAmount,
            execution.authorizationId,
            execution.authorityRef,
            execution.policyBindingHash,
            execution.provenanceHash,
            preObservationHash,
            postObservationHash,
            receiptHash
        );
    }

    function _ordinaryTransfer(address from, address to, uint256 amount) internal {
        _checkOrdinaryTransfer(from, to, amount);
        _move(from, to, amount);
    }

    function _checkOrdinaryTransfer(address from, address to, uint256 amount) internal view {
        if (from == address(0) || to == address(0) || _balances[from] < amount || !canTransfer(from, to, amount)) {
            revert TrustRejected(bytes32(0), REASON_ORDINARY_GATE);
        }
    }

    function _move(address from, address to, uint256 amount) internal {
        unchecked {
            _balances[from] -= amount;
        }
        _balances[to] += amount;
        emit Transfer(from, to, amount);
    }

    function _freezeRouteKey(
        address actor,
        address account,
        uint256 amount,
        bytes32 bindingHash_,
        uint64 authorityEpoch_,
        uint64 policyEpoch_
    ) internal pure returns (bytes32) {
        bytes32 calldataHash = keccak256(abi.encodeCall(IERC7943FreezePilot.setFrozenTokens, (account, amount)));
        return computeRouteKey(
            actor,
            IERC7943FreezePilot.setFrozenTokens.selector,
            calldataHash,
            bindingHash_,
            authorityEpoch_,
            policyEpoch_
        );
    }

    function _requireApplicable(bytes32 commandId, AssessmentResult memory assessment) internal pure {
        if (assessment.outcome == AssessmentOutcome.REJECTED) {
            revert TrustRejected(commandId, assessment.reason);
        }
        if (assessment.outcome == AssessmentOutcome.OPERATIONAL_FAILURE) {
            revert TrustOperationalFailure(commandId, assessment.reason, assessment.dependencyRef);
        }
    }

    function _rejected(bytes32 digest, uint16 reason) internal view returns (AssessmentResult memory) {
        return AssessmentResult({
            outcome: AssessmentOutcome.REJECTED,
            reason: reason,
            dependencyRef: bytes32(0),
            commandDigest: digest,
            currentBindingHash: bindingHash
        });
    }

    function _operationalFailure(bytes32 digest, uint16 reason, bytes32 dependencyRef)
        internal
        view
        returns (AssessmentResult memory)
    {
        return AssessmentResult({
            outcome: AssessmentOutcome.OPERATIONAL_FAILURE,
            reason: reason,
            dependencyRef: dependencyRef,
            commandDigest: digest,
            currentBindingHash: bindingHash
        });
    }

    function _readPolicyConfiguration(IBoundPolicy policy_)
        internal
        view
        returns (bool ok, bytes32 policyConfiguration, bytes32 dependencyRef)
    {
        (bool success, bytes memory result) =
            address(policy_).staticcall{gas: POLICY_GAS_LIMIT}(abi.encodeCall(IBoundPolicy.configurationDigest, ()));
        if (!success || result.length != 32) {
            return (false, bytes32(0), bytes32(uint256(uint160(address(policy_)))));
        }
        return (true, abi.decode(result, (bytes32)), bytes32(0));
    }

    function _computeBindingHash(
        IBoundPolicy policy_,
        bytes32 policyCodeId_,
        bytes32 configurationDigest_,
        uint64 policyEpoch_,
        uint64 authorityEpoch_
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                address(policy_),
                address(0),
                policyCodeId_,
                bytes32(0),
                configurationDigest_,
                STANDARD_VERSION,
                policyEpoch_,
                authorityEpoch_
            )
        );
    }

    function _nonceKey(bytes32 authorityRef_, uint64 authorityEpoch_, uint256 nonce) internal pure returns (bytes32) {
        return keccak256(abi.encode(authorityRef_, authorityEpoch_, nonce));
    }

    function _observationHash(address subject, bytes32 caseId) internal view returns (bytes32) {
        CaseRecord storage caseRecord_ = _cases[caseId];
        return keccak256(
            abi.encode(
                subject,
                _balances[subject],
                _frozenAbsolute[subject],
                caseId,
                caseRecord_.action,
                caseRecord_.lifecycle,
                caseRecord_.subject,
                caseRecord_.amount,
                caseRecord_.lastActionId
            )
        );
    }

    function _receiptHash(
        bytes32 commandDigest_,
        bytes32 authorizationId,
        bytes32 authorityRef_,
        bytes32 policyBindingHash_,
        bytes32 provenanceHash,
        bytes32 preObservationHash,
        bytes32 postObservationHash,
        bytes32 resultHash
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                RECEIPT_DOMAIN,
                commandDigest_,
                authorizationId,
                authorityRef_,
                policyBindingHash_,
                provenanceHash,
                AssessmentOutcome.APPLICABLE,
                preObservationHash,
                postObservationHash,
                resultHash
            )
        );
    }
}
