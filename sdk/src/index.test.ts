// SPDX-License-Identifier: BSD-3-Clause

import assert from "node:assert/strict";
import test from "node:test";
import { ZeroAddress, ZeroHash } from "ethers";
import {
  ActionKind,
  TRUST_DOMAIN,
  actionReceiptHash,
  commandHash,
  deriveActionId,
  encodeAction,
  type ActionRequest,
} from "./index.js";

const token = "0x1111111111111111111111111111111111111111";
const request: ActionRequest = {
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

test("actionId zeroes only actionId and commandHash binds the completed command", () => {
  const actionId = deriveActionId(token, 1n, request);
  const completed = { ...request, actionId };
  assert.notEqual(actionId, ZeroHash);
  assert.notEqual(commandHash(token, 1n, completed), actionId);
  assert.notEqual(
    deriveActionId(token, 1n, { ...request, destination: token }),
    actionId,
  );
});

test("action calldata uses the canonical selector", () => {
  const completed = { ...request, actionId: deriveActionId(token, 1n, request) };
  assert.equal(encodeAction(completed).slice(0, 10), "0x9da23539");
});

test("receipt hash changes with the external commitment", () => {
  const actionId = deriveActionId(token, 1n, request);
  const base = {
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
  assert.notEqual(
    actionReceiptHash(base),
    actionReceiptHash({ ...base, externalCommitment: `0x${"aa".repeat(32)}` }),
  );
});
