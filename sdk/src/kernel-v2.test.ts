// SPDX-License-Identifier: BSD-3-Clause

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { ZeroHash, concat, keccak256, zeroPadValue, toBeHex, getAddress } from "ethers";
import {
  ACTION_TUPLE,
  ActionKind,
  KERNEL_DOMAIN,
  KERNEL_INTERFACE_ID,
  KERNEL_SELECTORS,
  RECEIPT_PREIMAGE_TYPES,
  REVERSAL_TUPLE,
  ReceiptKind,
  ReversalKind,
  bindingHash,
  commandHash,
  dependencyRoot,
  deriveActionId,
  deriveReversalId,
  encodeAction,
  encodeReversal,
  kernelSelector,
  nonceKey,
  receiptHash,
  reversalHash,
  type ActionRequest,
  type ReceiptInput,
  type ReversalRequest,
} from "./kernel-v2.js";

interface VectorFile {
  constants: {
    domain: string;
    kernelInterfaceId: string;
    selectors: Record<string, string>;
    actionCalldataLength: number;
    reversalCalldataLength: number;
  };
  fixture: {
    endpoint: string;
    chainId: string;
    dependencies: Record<string, { dependency: string; runtimeCodeId: string; configurationDigest: string; schema: string; epoch: string }>;
    bindingHashes: Record<string, string>;
    dependencyRoot: string;
    nonceKeyExample: { authorityRef: string; authorityEpoch: string; nonce: string; nonceKey: string };
  };
  actions: Array<{ id: string; request: Record<string, string>; actionId: string; commandHash: string; calldata: string; receiptInput: Record<string, string>; receiptHash: string }>;
  reversals: Array<{ id: string; request: Record<string, string>; reversalId: string; reversalHash: string; calldata: string; receiptInput: Record<string, string>; receiptHash: string }>;
}

const vectors = JSON.parse(
  readFileSync(new URL("../../vectors/conformance-v2.json", import.meta.url), "utf8"),
) as VectorFile;
const endpoint = vectors.fixture.endpoint;
const chainId = BigInt(vectors.fixture.chainId);

function actionRequestOf(raw: Record<string, string>): ActionRequest {
  return {
    domain: raw.domain!,
    actionId: raw.actionId!,
    action: Number(raw.action) as ActionKind,
    subject: raw.subject!,
    source: raw.source!,
    destination: raw.destination!,
    custodian: raw.custodian!,
    amount: BigInt(raw.amount!),
    caseId: raw.caseId!,
    dependencyRoot: raw.dependencyRoot!,
    dependencyEpoch: BigInt(raw.dependencyEpoch!),
    provenanceCommitment: raw.provenanceCommitment!,
    settlementCommitment: raw.settlementCommitment!,
    proceedsCommitment: raw.proceedsCommitment!,
    entitlementCommitment: raw.entitlementCommitment!,
    authorityRef: raw.authorityRef!,
    authorityEpoch: BigInt(raw.authorityEpoch!),
    nonce: BigInt(raw.nonce!),
    validAfter: BigInt(raw.validAfter!),
    validBefore: BigInt(raw.validBefore!),
  };
}

function reversalRequestOf(raw: Record<string, string>): ReversalRequest {
  return {
    domain: raw.domain!,
    reversalId: raw.reversalId!,
    actionId: raw.actionId!,
    reversal: Number(raw.reversal) as ReversalKind,
    dependencyRoot: raw.dependencyRoot!,
    dependencyEpoch: BigInt(raw.dependencyEpoch!),
    provenanceCommitment: raw.provenanceCommitment!,
    authorityRef: raw.authorityRef!,
    authorityEpoch: BigInt(raw.authorityEpoch!),
    nonce: BigInt(raw.nonce!),
    validAfter: BigInt(raw.validAfter!),
    validBefore: BigInt(raw.validBefore!),
  };
}

function receiptInputOf(raw: Record<string, string>): ReceiptInput {
  return {
    receiptKind: Number(raw.receiptKind) as ReceiptKind,
    commandId: raw.commandId!,
    commandKind: BigInt(raw.commandKind!),
    parentCommandId: raw.parentCommandId!,
    subject: raw.subject!,
    source: raw.source!,
    destination: raw.destination!,
    amount: BigInt(raw.amount!),
    caseId: raw.caseId!,
    authorityRef: raw.authorityRef!,
    dependencyRoot: raw.dependencyRoot!,
    provenanceCommitment: raw.provenanceCommitment!,
    assessmentEvidence: raw.assessmentEvidence!,
    preState: raw.preState!,
    postState: raw.postState!,
    externalCommitment: raw.externalCommitment!,
  };
}

test("constants match the generated vectors", () => {
  assert.equal(KERNEL_DOMAIN, vectors.constants.domain);
  assert.equal(KERNEL_INTERFACE_ID, vectors.constants.kernelInterfaceId);
  for (const [signature, selector] of Object.entries(vectors.constants.selectors)) {
    assert.equal(kernelSelector(signature), selector);
  }
  let xor = 0n;
  for (const selector of Object.values(vectors.constants.selectors)) xor ^= BigInt(selector);
  assert.equal(`0x${xor.toString(16).padStart(8, "0")}`, KERNEL_INTERFACE_ID);
  assert.equal(KERNEL_SELECTORS.executeRegulatoryAction, vectors.constants.selectors[`executeRegulatoryAction(${ACTION_TUPLE.replace("tuple", "").replace(/ \w+/g, "")})`]);
  assert.equal(RECEIPT_PREIMAGE_TYPES.length, 17);
});

test("every action vector is reproduced by the helpers", () => {
  for (const vector of vectors.actions) {
    const request = actionRequestOf(vector.request);
    assert.equal(deriveActionId(endpoint, chainId, request), vector.actionId, vector.id);
    assert.equal(request.actionId, vector.actionId, vector.id);
    assert.equal(commandHash(endpoint, chainId, request), vector.commandHash, vector.id);
    assert.notEqual(vector.commandHash, vector.actionId, vector.id);
    const calldata = encodeAction(request);
    assert.equal(calldata, vector.calldata, vector.id);
    assert.equal((calldata.length - 2) / 2, vectors.constants.actionCalldataLength, vector.id);
    assert.equal(receiptHash(receiptInputOf(vector.receiptInput)), vector.receiptHash, vector.id);
  }
});

test("every reversal vector is reproduced by the helpers", () => {
  for (const vector of vectors.reversals) {
    const request = reversalRequestOf(vector.request);
    assert.equal(deriveReversalId(endpoint, chainId, request), vector.reversalId, vector.id);
    assert.equal(reversalHash(endpoint, chainId, request), vector.reversalHash, vector.id);
    const calldata = encodeReversal(request);
    assert.equal(calldata, vector.calldata, vector.id);
    assert.equal((calldata.length - 2) / 2, vectors.constants.reversalCalldataLength, vector.id);
    assert.equal(receiptHash(receiptInputOf(vector.receiptInput)), vector.receiptHash, vector.id);
  }
});

test("dependency bindings and root are reproduced", () => {
  const kinds = { policy: 0, identity: 1, settlement: 2, entitlement: 3 } as const;
  for (const [name, kind] of Object.entries(kinds)) {
    const entry = vectors.fixture.dependencies[name]!;
    assert.equal(
      bindingHash(kind, entry.dependency, entry.runtimeCodeId, entry.configurationDigest, entry.schema, BigInt(entry.epoch)),
      vectors.fixture.bindingHashes[name],
      name,
    );
  }
  const hashes = vectors.fixture.bindingHashes;
  assert.equal(dependencyRoot(hashes.policy!, hashes.identity!, hashes.settlement!, hashes.entitlement!), vectors.fixture.dependencyRoot);
  assert.notEqual(dependencyRoot(hashes.identity!, hashes.policy!, hashes.settlement!, hashes.entitlement!), vectors.fixture.dependencyRoot);
  const example = vectors.fixture.nonceKeyExample;
  assert.equal(nonceKey(example.authorityRef, BigInt(example.authorityEpoch), BigInt(example.nonce)), example.nonceKey);
});

test("action identifier equals a raw word-by-word keccak of the canonical encoding", () => {
  const vector = vectors.actions[0]!;
  const request = actionRequestOf(vector.request);
  const word = (value: string | bigint | number): string =>
    typeof value === "string" ? zeroPadValue(value.length === 42 ? getAddress(value) : value, 32) : zeroPadValue(toBeHex(value), 32);
  const words = [
    KERNEL_DOMAIN,
    word(endpoint),
    word(chainId),
    request.domain,
    ZeroHash,
    word(request.action),
    word(request.subject),
    word(request.source),
    word(request.destination),
    word(request.custodian),
    word(request.amount),
    request.caseId,
    request.dependencyRoot,
    word(request.dependencyEpoch),
    request.provenanceCommitment,
    request.settlementCommitment,
    request.proceedsCommitment,
    request.entitlementCommitment,
    request.authorityRef,
    word(request.authorityEpoch),
    word(request.nonce),
    word(request.validAfter),
    word(request.validBefore),
  ];
  assert.equal(keccak256(concat(words)), vector.actionId);
  assert.equal(REVERSAL_TUPLE.startsWith("tuple(bytes32 domain,bytes32 reversalId"), true);
});

test("receipt kinds are domain separated", () => {
  const reversal = receiptInputOf(vectors.reversals[0]!.receiptInput);
  const asAction: ReceiptInput = { ...reversal, receiptKind: ReceiptKind.ACTION };
  assert.notEqual(receiptHash(asAction), receiptHash(reversal));
  assert.equal(reversal.commandKind, BigInt(ReversalKind.UNFREEZE));
  assert.equal(BigInt(ActionKind.FREEZE), reversal.commandKind);
});
