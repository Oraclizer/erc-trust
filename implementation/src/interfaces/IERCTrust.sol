// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {IERC165} from "./IERC165.sol";
import {TrustTypes} from "../TrustTypes.sol";

interface IERCTrust is IERC165 {
    event RegulatoryActionApplied(
        bytes32 indexed actionId, TrustTypes.ActionKind indexed action, bytes32 indexed caseId, bytes32 receiptHash
    );
    event RegulatoryReversalApplied(
        bytes32 indexed reversalId,
        TrustTypes.ReversalKind indexed reversal,
        bytes32 indexed actionId,
        bytes32 receiptHash
    );
    event TrustBindingChanged(
        TrustTypes.BindingKind indexed kind,
        bytes32 indexed previousBinding,
        bytes32 indexed currentBinding,
        uint64 epoch
    );
    event TrustAuthorityChanged(bytes32 indexed authorityRef, address indexed account, uint64 epoch, bool active);
    event TrustDelegationChanged(
        bytes32 indexed authorityRef, address indexed delegate, uint256 actionMask, bytes32 scopeHash, uint48 validUntil
    );

    function executeRegulatoryAction(TrustTypes.ActionRequest calldata request) external returns (bytes32 receiptHash);
    function executeRegulatoryReversal(TrustTypes.ReversalRequest calldata request)
        external
        returns (bytes32 receiptHash);
    function executeERC7943Action(TrustTypes.ActionRequest calldata request) external returns (bytes32 receiptHash);
    function executeERC7943Reversal(TrustTypes.ReversalRequest calldata request) external returns (bytes32 receiptHash);
    function commandHash(TrustTypes.ActionRequest calldata request) external view returns (bytes32);
    function reversalHash(TrustTypes.ReversalRequest calldata request) external view returns (bytes32);
    function actionRecord(bytes32 actionId) external view returns (TrustTypes.ActionRecord memory);
    function receipt(bytes32 commandId) external view returns (TrustTypes.Receipt memory);
    function caseTerminal(bytes32 caseId) external view returns (bool);
    function trustProfile() external pure returns (bytes32 profile, uint256 supportedActionMask, bool proxySupported);
}
