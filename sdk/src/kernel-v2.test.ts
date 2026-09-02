// SPDX-License-Identifier: BSD-3-Clause

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { ZeroHash, concat, keccak256, zeroPadValue, toBeHex, getAddress } from "ethers";
import {
  ACTION_TUPLE,
  ActionKind,
  DEPENDENCY_ROOT_TAG,
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
    dependencyRootTag: string;
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
  negative: Array<{
    id: string;
    base?: string;
    mutatedDerivedActionIds?: Array<{ field: string; originalValue: string; mutatedValue: string; derivedActionId: string }>;
    example?: { reversalReceiptHash: string; sameFieldsWithActionKind: string };
  }>;
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

/**
 * Raw 32-byte word of a value, written without the ABI coder so that a change in
 * the ABI coder or in the generated tuple order cannot hide a preimage change.
 */
function word(value: string | bigint | number): string {
  if (typeof value === "string") {
    return zeroPadValue(value.length === 42 ? getAddress(value) : value, 32);
  }
  return zeroPadValue(toBeHex(value), 32);
}

function rawActionWords(request: ActionRequest, actionIdWord: string): string[] {
  return [
    KERNEL_DOMAIN,
    word(endpoint),
    word(chainId),
    request.domain,
    actionIdWord,
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
}

function rawReversalWords(request: ReversalRequest, reversalIdWord: string): string[] {
  return [
    KERNEL_DOMAIN,
    word(endpoint),
    word(chainId),
    request.domain,
    reversalIdWord,
    request.actionId,
    word(request.reversal),
    request.dependencyRoot,
    word(request.dependencyEpoch),
    request.provenanceCommitment,
    request.authorityRef,
    word(request.authorityEpoch),
    word(request.nonce),
    word(request.validAfter),
    word(request.validBefore),
  ];
}

function rawReceiptWords(input: ReceiptInput): string[] {
  return [
    KERNEL_DOMAIN,
    word(input.receiptKind),
    input.commandId,
    word(input.commandKind),
    input.parentCommandId,
    word(input.subject),
    word(input.source),
    word(input.destination),
    word(input.amount),
    input.caseId,
    input.authorityRef,
    input.dependencyRoot,
    input.provenanceCommitment,
    input.assessmentEvidence,
    input.preState,
    input.postState,
    input.externalCommitment,
  ];
}

function actionVectorById(id: string): VectorFile["actions"][number] {
  const found = vectors.actions.find((vector) => vector.id === id);
  assert.ok(found, id);
  return found;
}

function reversalVectorById(id: string): VectorFile["reversals"][number] {
  const found = vectors.reversals.find((vector) => vector.id === id);
  assert.ok(found, id);
  return found;
}

test("constants match the generated vectors", () => {
  assert.equal(KERNEL_DOMAIN, vectors.constants.domain);
  assert.equal(DEPENDENCY_ROOT_TAG, vectors.constants.dependencyRootTag);
  assert.equal(KERNEL_INTERFACE_ID, vectors.constants.kernelInterfaceId);
  for (const [signature, selector] of Object.entries(vectors.constants.selectors)) {
    assert.equal(kernelSelector(signature), selector);
  }
  let xor = 0n;
  for (const selector of Object.values(vectors.constants.selectors)) xor ^= BigInt(selector);
  assert.equal(`0x${xor.toString(16).padStart(8, "0")}`, KERNEL_INTERFACE_ID);
  assert.equal(KERNEL_SELECTORS.executeRegulatoryAction, vectors.constants.selectors[`executeRegulatoryAction(${ACTION_TUPLE.replace("tuple", "").replace(/ \w+/g, "")})`]);
  assert.equal(RECEIPT_PREIMAGE_TYPES.length, 17);
  assert.equal(Object.keys(vectors.constants.selectors).length, 9);
});

test("every action vector is reproduced by the helpers", () => {
  assert.equal(vectors.actions.length, 6);
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
  assert.equal(vectors.reversals.length, 3);
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

test("command identifiers equal a raw word-by-word keccak of the canonical encoding", () => {
  // LIQUIDATE carries a nonzero value in every address and commitment slot, so a
  // swapped or missing word cannot hide behind a zero value.
  const liquidate = actionVectorById("ACTION-LIQUIDATE");
  const request = actionRequestOf(liquidate.request);
  assert.notEqual(request.settlementCommitment, request.proceedsCommitment);
  assert.notEqual(request.destination, request.subject);
  assert.equal(keccak256(concat(rawActionWords(request, ZeroHash))), liquidate.actionId);
  assert.equal(keccak256(concat(rawActionWords(request, request.actionId))), liquidate.commandHash);
  const freeze = actionVectorById("ACTION-FREEZE");
  assert.equal(keccak256(concat(rawActionWords(actionRequestOf(freeze.request), ZeroHash))), freeze.actionId);

  const release = reversalVectorById("REVERSAL-RELEASE");
  const reversal = reversalRequestOf(release.request);
  assert.equal(keccak256(concat(rawReversalWords(reversal, ZeroHash))), release.reversalId);
  assert.equal(keccak256(concat(rawReversalWords(reversal, reversal.reversalId))), release.reversalHash);
  assert.equal(REVERSAL_TUPLE.startsWith("tuple(bytes32 domain,bytes32 reversalId"), true);
});

test("receipt hashes equal a raw word-by-word keccak of the receipt preimage", () => {
  const liquidate = actionVectorById("ACTION-LIQUIDATE");
  const liquidateInput = receiptInputOf(liquidate.receiptInput);
  assert.notEqual(liquidateInput.externalCommitment, ZeroHash);
  assert.notEqual(liquidateInput.preState, liquidateInput.postState);
  assert.equal(keccak256(concat(rawReceiptWords(liquidateInput))), liquidate.receiptHash);

  const release = reversalVectorById("REVERSAL-RELEASE");
  const releaseInput = receiptInputOf(release.receiptInput);
  assert.equal(releaseInput.receiptKind, ReceiptKind.REVERSAL);
  assert.notEqual(releaseInput.parentCommandId, ZeroHash);
  assert.notEqual(releaseInput.source, releaseInput.destination);
  assert.equal(keccak256(concat(rawReceiptWords(releaseInput))), release.receiptHash);
});

test("binding hash, dependency root, and nonce key equal raw word-by-word keccaks", () => {
  const settlement = vectors.fixture.dependencies.settlement!;
  const rawBinding = keccak256(concat([
    KERNEL_DOMAIN,
    word(2),
    word(settlement.dependency),
    settlement.runtimeCodeId,
    settlement.configurationDigest,
    settlement.schema,
    word(BigInt(settlement.epoch)),
  ]));
  assert.equal(rawBinding, vectors.fixture.bindingHashes.settlement);

  const hashes = vectors.fixture.bindingHashes;
  const rawRoot = keccak256(concat([
    KERNEL_DOMAIN,
    DEPENDENCY_ROOT_TAG,
    hashes.policy!,
    hashes.identity!,
    hashes.settlement!,
    hashes.entitlement!,
  ]));
  assert.equal(rawRoot, vectors.fixture.dependencyRoot);

  const example = vectors.fixture.nonceKeyExample;
  const rawNonceKey = keccak256(concat([
    KERNEL_DOMAIN,
    example.authorityRef,
    word(BigInt(example.authorityEpoch)),
    word(BigInt(example.nonce)),
  ]));
  assert.equal(rawNonceKey, example.nonceKey);
});

test("negative vectors are consumed: field mutations and receipt kind separation", () => {
  const binding = vectors.negative.find((entry) => entry.id === "NEG-FIELD-BINDING");
  assert.ok(binding && binding.mutatedDerivedActionIds && binding.base);
  const base = actionRequestOf(actionVectorById(binding.base).request);
  const seen = new Set<string>([deriveActionId(endpoint, chainId, base)]);
  assert.equal(binding.mutatedDerivedActionIds.length, 19);
  for (const entry of binding.mutatedDerivedActionIds) {
    const field = entry.field as keyof ActionRequest;
    assert.notEqual(field, "actionId");
    assert.equal(String(base[field]), entry.originalValue, entry.field);
    const value = typeof base[field] === "bigint" ? BigInt(entry.mutatedValue) : entry.mutatedValue;
    const mutated = { ...base, [field]: value } as ActionRequest;
    assert.equal(deriveActionId(endpoint, chainId, mutated), entry.derivedActionId, entry.field);
    assert.equal(seen.has(entry.derivedActionId), false, entry.field);
    seen.add(entry.derivedActionId);
  }

  const kind = vectors.negative.find((entry) => entry.id === "NEG-RECEIPT-KIND");
  assert.ok(kind && kind.example);
  const reversal = receiptInputOf(vectors.reversals[0]!.receiptInput);
  assert.equal(receiptHash(reversal), kind.example.reversalReceiptHash);
  const asAction: ReceiptInput = { ...reversal, receiptKind: ReceiptKind.ACTION };
  assert.equal(receiptHash(asAction), kind.example.sameFieldsWithActionKind);
  assert.notEqual(kind.example.sameFieldsWithActionKind, kind.example.reversalReceiptHash);
  assert.equal(reversal.commandKind, BigInt(ReversalKind.UNFREEZE));
  assert.equal(BigInt(ActionKind.FREEZE), reversal.commandKind);
});
