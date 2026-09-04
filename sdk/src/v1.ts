// SPDX-License-Identifier: BSD-3-Clause

import { AbiCoder, Interface, ZeroHash, getAddress, id, keccak256 } from "ethers";

export const TRUST_DOMAIN = id("ERC-TRUST/reference-v1");

export enum ActionKind {
  FREEZE,
  SEIZE,
  CONFISCATE,
  LIQUIDATE,
  RESTRICT,
  RECOVER,
}

export enum ReversalKind {
  UNFREEZE,
  RELEASE,
  UNRESTRICT,
}

export interface ActionRequest {
  domain: string;
  actionId: string;
  action: ActionKind;
  subject: string;
  source: string;
  destination: string;
  custodian: string;
  amount: bigint;
  caseId: string;
  scopeHash: string;
  policyCommitment: string;
  provenanceCommitment: string;
  settlementCommitment: string;
  proceedsCommitment: string;
  entitlementCommitment: string;
  authorityRef: string;
  authorityEpoch: bigint;
  policyEpoch: bigint;
  nonce: bigint;
  validAfter: bigint;
  validBefore: bigint;
}

export interface ReversalRequest {
  domain: string;
  reversalId: string;
  actionId: string;
  reversal: ReversalKind;
  authorityRef: string;
  authorityEpoch: bigint;
  nonce: bigint;
  validAfter: bigint;
  validBefore: bigint;
}

export interface ActionReceiptInput {
  actionId: string;
  action: ActionKind;
  source: string;
  destination: string;
  amount: bigint;
  caseId: string;
  policyCommitment: string;
  provenanceCommitment: string;
  preState: string;
  postState: string;
  externalCommitment: string;
}

export const ACTION_TUPLE =
  "tuple(bytes32 domain,bytes32 actionId,uint8 action,address subject,address source,address destination,address custodian,uint256 amount,bytes32 caseId,bytes32 scopeHash,bytes32 policyCommitment,bytes32 provenanceCommitment,bytes32 settlementCommitment,bytes32 proceedsCommitment,bytes32 entitlementCommitment,bytes32 authorityRef,uint64 authorityEpoch,uint64 policyEpoch,uint256 nonce,uint48 validAfter,uint48 validBefore)";

export const REVERSAL_TUPLE =
  "tuple(bytes32 domain,bytes32 reversalId,bytes32 actionId,uint8 reversal,bytes32 authorityRef,uint64 authorityEpoch,uint256 nonce,uint48 validAfter,uint48 validBefore)";

const coder = AbiCoder.defaultAbiCoder();
const trustInterface = new Interface([
  `function executeRegulatoryAction(${ACTION_TUPLE} request) returns (bytes32)`,
  `function executeRegulatoryReversal(${REVERSAL_TUPLE} request) returns (bytes32)`,
  `function executeERC7943Action(${ACTION_TUPLE} request) returns (bytes32)`,
  `function executeERC7943Reversal(${REVERSAL_TUPLE} request) returns (bytes32)`,
]);

export function normalizeActionRequest(request: ActionRequest): ActionRequest {
  return {
    ...request,
    subject: getAddress(request.subject),
    source: getAddress(request.source),
    destination: getAddress(request.destination),
    custodian: getAddress(request.custodian),
  };
}

export function deriveActionId(token: string, chainId: bigint, request: ActionRequest): string {
  const normalized = normalizeActionRequest({ ...request, actionId: ZeroHash });
  return keccak256(
    coder.encode(
      ["bytes32", "address", "uint256", ACTION_TUPLE],
      [TRUST_DOMAIN, getAddress(token), chainId, normalized],
    ),
  );
}

export function deriveReversalId(
  token: string,
  chainId: bigint,
  request: ReversalRequest,
): string {
  const normalized = { ...request, reversalId: ZeroHash };
  return keccak256(
    coder.encode(
      ["bytes32", "address", "uint256", REVERSAL_TUPLE],
      [TRUST_DOMAIN, getAddress(token), chainId, normalized],
    ),
  );
}

export function commandHash(token: string, chainId: bigint, request: ActionRequest): string {
  return keccak256(
    coder.encode(
      ["bytes32", "address", "uint256", ACTION_TUPLE],
      [TRUST_DOMAIN, getAddress(token), chainId, normalizeActionRequest(request)],
    ),
  );
}

export function actionReceiptHash(input: ActionReceiptInput): string {
  return keccak256(
    coder.encode(
      [
        "bytes32",
        "bytes32",
        "uint8",
        "address",
        "address",
        "uint256",
        "bytes32",
        "bytes32",
        "bytes32",
        "bytes32",
        "bytes32",
        "bytes32",
      ],
      [
        TRUST_DOMAIN,
        input.actionId,
        input.action,
        getAddress(input.source),
        getAddress(input.destination),
        input.amount,
        input.caseId,
        input.policyCommitment,
        input.provenanceCommitment,
        input.preState,
        input.postState,
        input.externalCommitment,
      ],
    ),
  );
}

export function encodeAction(request: ActionRequest, erc7943Route = false): string {
  return trustInterface.encodeFunctionData(
    erc7943Route ? "executeERC7943Action" : "executeRegulatoryAction",
    [normalizeActionRequest(request)],
  );
}

export function encodeReversal(request: ReversalRequest, erc7943Route = false): string {
  return trustInterface.encodeFunctionData(
    erc7943Route ? "executeERC7943Reversal" : "executeRegulatoryReversal",
    [request],
  );
}
