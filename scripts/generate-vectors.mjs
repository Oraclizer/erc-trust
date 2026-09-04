// SPDX-License-Identifier: BSD-3-Clause

import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { ZeroAddress, ZeroHash } from "../sdk/node_modules/ethers/lib.esm/index.js";
import {
  ActionKind,
  TRUST_DOMAIN,
  actionReceiptHash,
  commandHash,
  deriveActionId,
  encodeAction,
} from "../sdk/dist/v1.js";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const token = "0x1111111111111111111111111111111111111111";
const chainId = 1n;
const request = {
  domain: TRUST_DOMAIN,
  actionId: ZeroHash,
  action: ActionKind.FREEZE,
  subject: "0x2222222222222222222222222222222222222222",
  source: "0x2222222222222222222222222222222222222222",
  destination: ZeroAddress,
  custodian: ZeroAddress,
  amount: 123n,
  caseId: `0x${"33".repeat(32)}`,
  scopeHash: `0x${"44".repeat(32)}`,
  policyCommitment: `0x${"55".repeat(32)}`,
  provenanceCommitment: `0x${"66".repeat(32)}`,
  settlementCommitment: ZeroHash,
  proceedsCommitment: ZeroHash,
  entitlementCommitment: ZeroHash,
  authorityRef: `0x${"77".repeat(32)}`,
  authorityEpoch: 1n,
  policyEpoch: 1n,
  nonce: 9n,
  validAfter: 0n,
  validBefore: 281474976710655n,
};
const actionId = deriveActionId(token, chainId, request);
const completed = { ...request, actionId };
const receiptInput = {
  actionId,
  action: ActionKind.FREEZE,
  source: request.source,
  destination: request.destination,
  amount: request.amount,
  caseId: request.caseId,
  policyCommitment: request.policyCommitment,
  provenanceCommitment: request.provenanceCommitment,
  preState: `0x${"88".repeat(32)}`,
  postState: `0x${"99".repeat(32)}`,
  externalCommitment: ZeroHash,
};

const vector = {
  schema: "erc-trust-conformance-vectors-v1",
  candidateStatus: "unaudited-not-for-production",
  constants: {
    trustDomain: TRUST_DOMAIN,
    erc7943FungibleInterfaceId: "0x3edbb4c4",
    executeRegulatoryActionSelector: "0x9da23539",
    setFrozenTokensSelector: "0xebe45cba",
    forcedTransferSelector: "0x9fc1d0e7",
  },
  positive: {
    token,
    chainId: chainId.toString(),
    actionRequest: Object.fromEntries(
      Object.entries(completed).map(([key, value]) => [
        key,
        typeof value === "bigint" ? value.toString() : value,
      ]),
    ),
    actionId,
    commandHash: commandHash(token, chainId, completed),
    calldata: encodeAction(completed),
    receiptInput: Object.fromEntries(
      Object.entries(receiptInput).map(([key, value]) => [
        key,
        typeof value === "bigint" ? value.toString() : value,
      ]),
    ),
    receiptHash: actionReceiptHash(receiptInput),
  },
  negative: [
    {
      id: "NEG-FIXED-DESTINATION",
      mutation: "destination becomes token address without recomputing actionId",
      expected: "TrustInvalidCommand reason 2",
      mutatedDerivedActionId: deriveActionId(token, chainId, {
        ...completed,
        destination: token,
      }),
    },
    {
      id: "NEG-RAW-ERC7943",
      mutation: "call setFrozenTokens or forcedTransfer without an in-flight exact-use ticket",
      expected: "TrustRouteMismatch and full-state stutter",
    },
    {
      id: "NEG-REPLAY",
      mutation: "submit the identical applied action twice",
      expected: "TrustReplay and full-state stutter",
    },
  ],
};

const output = resolve(root, "vectors", "conformance-v1.json");
mkdirSync(dirname(output), { recursive: true });
writeFileSync(output, `${JSON.stringify(vector, null, 2)}\n`, "utf8");
