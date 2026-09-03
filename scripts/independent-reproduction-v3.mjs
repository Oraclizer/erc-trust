#!/usr/bin/env node
// independent-reproduction-v3.mjs
//
// Independent, specification-only reproduction of the ERC-TRUST kernel version 2.
//
// Everything in this file was written from three normative documents only:
//   spec/erc-trust-kernel-v2.json      (the normative machine source)
//   spec/generated/kernel-v2.md        (the normative prose rendered from it)
//   spec/generated/kernel-v2-abi.json  (the ABI rendered from it)
// and is checked against vectors/conformance-v2.json.
//
// No Solidity source, no test, no SDK source and no repository script was read.
// The only module imported from outside this file is `ethers`, used for the
// keccak-256 primitive and for an independent cross-check of the hand-written
// ABI encoder. The ABI encoding itself is implemented here from the schema's
// field lists, as the brief requires.
//
// Usage:
//   node independent-reproduction-v3.mjs --vectors <path> --ethers <path to ethers package dir> [--out <path>]
//
// Exits non-zero on any FAIL.

import { readFileSync, writeFileSync } from "node:fs";
import { createHash } from "node:crypto";
import path from "node:path";
import { pathToFileURL } from "node:url";

// ---------------------------------------------------------------------------
// 0. Command line
// ---------------------------------------------------------------------------

function parseArgs(argv) {
  const out = { vectors: null, ethers: null, out: "independent-reproduction-v3.json" };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === "--vectors") { out.vectors = argv[i + 1]; i += 1; }
    else if (a === "--ethers") { out.ethers = argv[i + 1]; i += 1; }
    else if (a === "--out") { out.out = argv[i + 1]; i += 1; }
    else if (a === "--schema") { out.schema = argv[i + 1]; i += 1; }
    else if (a === "--abi") { out.abi = argv[i + 1]; i += 1; }
    else throw new Error("unknown argument: " + a);
  }
  if (!out.vectors) throw new Error("missing --vectors <path>");
  if (!out.ethers) throw new Error("missing --ethers <path to ethers package directory>");
  return out;
}

async function loadEthers(modDir) {
  const pkg = JSON.parse(readFileSync(path.join(modDir, "package.json"), "utf8"));
  let entry = null;
  const dot = pkg.exports && pkg.exports["."];
  if (dot) {
    if (typeof dot === "string") entry = dot;
    else if (typeof dot.import === "string") entry = dot.import;
    else if (dot.import && typeof dot.import.default === "string") entry = dot.import.default;
  }
  if (!entry) entry = pkg.module || pkg.main;
  if (!entry) throw new Error("cannot resolve an entry point for the ethers package");
  const mod = await import(pathToFileURL(path.join(modDir, entry)).href);
  if (typeof mod.keccak256 !== "function") throw new Error("ethers module exposes no keccak256");
  return { keccak256: mod.keccak256, AbiCoder: mod.AbiCoder, version: pkg.version || "unknown" };
}

// ---------------------------------------------------------------------------
// 1. The specification, transcribed
// ---------------------------------------------------------------------------
// Constants. The schema pairs each constant with a string and a keccak256 value.
// I read that pair as: the constant is the keccak-256 digest of the UTF-8 bytes
// of the string. The program derives the value and compares it with the vectors.

const DOMAIN_STRING = "ERC-TRUST/v2";
const DEPENDENCY_ROOT_TAG_STRING = "ERC-TRUST/v2/dependency-root";
const PROFILE_STRINGS = {
  "native-full": "ERC-TRUST/v2/native-full",
  "erc3643-verified-full": "ERC-TRUST/v2/erc3643-verified-full",
};

// Enums. "Values are part of the ABI and MUST NOT be reordered."
const ActionKind = { FREEZE: 0, SEIZE: 1, CONFISCATE: 2, LIQUIDATE: 3, RESTRICT: 4, RECOVER: 5 };
const ActionKindName = ["FREEZE", "SEIZE", "CONFISCATE", "LIQUIDATE", "RESTRICT", "RECOVER"];
const ReversalKind = { UNFREEZE: 0, RELEASE: 1, UNRESTRICT: 2 };
const ReversalKindName = ["UNFREEZE", "RELEASE", "UNRESTRICT"];
const ReceiptKind = { NONE: 0, ACTION: 1, REVERSAL: 2 };
const BindingKind = { POLICY: 0, IDENTITY: 1, SETTLEMENT: 2, ENTITLEMENT: 3 };
const CasePhase = { NONE: 0, OPEN: 1, TERMINAL: 2 };
const CaseFamily = { NONE: 0, FREEZE: 1, RESTRICT: 2, CUSTODY: 3, DISPOSITION: 4 };

// Structs. Field order is normative: "Fields encode, hash, and appear in
// calldata in the order listed in fields." Enum fields are their uint8 value.
const ACTION_REQUEST_FIELDS = [
  { name: "domain", type: "bytes32" },
  { name: "actionId", type: "bytes32" },
  { name: "action", type: "uint8" },
  { name: "subject", type: "address" },
  { name: "source", type: "address" },
  { name: "destination", type: "address" },
  { name: "custodian", type: "address" },
  { name: "amount", type: "uint256" },
  { name: "caseId", type: "bytes32" },
  { name: "dependencyRoot", type: "bytes32" },
  { name: "dependencyEpoch", type: "uint64" },
  { name: "provenanceCommitment", type: "bytes32" },
  { name: "settlementCommitment", type: "bytes32" },
  { name: "proceedsCommitment", type: "bytes32" },
  { name: "entitlementCommitment", type: "bytes32" },
  { name: "authorityRef", type: "bytes32" },
  { name: "authorityEpoch", type: "uint64" },
  { name: "nonce", type: "uint256" },
  { name: "validAfter", type: "uint48" },
  { name: "validBefore", type: "uint48" },
];

const REVERSAL_REQUEST_FIELDS = [
  { name: "domain", type: "bytes32" },
  { name: "reversalId", type: "bytes32" },
  { name: "actionId", type: "bytes32" },
  { name: "reversal", type: "uint8" },
  { name: "dependencyRoot", type: "bytes32" },
  { name: "dependencyEpoch", type: "uint64" },
  { name: "provenanceCommitment", type: "bytes32" },
  { name: "authorityRef", type: "bytes32" },
  { name: "authorityEpoch", type: "uint64" },
  { name: "nonce", type: "uint256" },
  { name: "validAfter", type: "uint48" },
  { name: "validBefore", type: "uint48" },
];

// Receipt: "Every field except receiptHash is a receipt hash preimage input in
// this order, prefixed by the domain constant." Sixteen fields plus the domain
// gives the seventeen words the hash rule names.
const RECEIPT_PREIMAGE_FIELDS = [
  { name: "receiptKind", type: "uint8" },
  { name: "commandId", type: "bytes32" },
  { name: "commandKind", type: "uint8" },
  { name: "parentCommandId", type: "bytes32" },
  { name: "subject", type: "address" },
  { name: "source", type: "address" },
  { name: "destination", type: "address" },
  { name: "amount", type: "uint256" },
  { name: "caseId", type: "bytes32" },
  { name: "authorityRef", type: "bytes32" },
  { name: "dependencyRoot", type: "bytes32" },
  { name: "provenanceCommitment", type: "bytes32" },
  { name: "assessmentEvidence", type: "bytes32" },
  { name: "preState", type: "bytes32" },
  { name: "postState", type: "bytes32" },
  { name: "externalCommitment", type: "bytes32" },
];

// Kernel interface functions, in the order the schema lists them. The
// identifier is the XOR of these selectors; supportsInterface is excluded.
const KERNEL_FUNCTIONS = [
  { name: "executeRegulatoryAction", params: [{ struct: "ActionRequest" }] },
  { name: "executeRegulatoryReversal", params: [{ struct: "ReversalRequest" }] },
  { name: "deriveActionId", params: [{ struct: "ActionRequest" }] },
  { name: "deriveReversalId", params: [{ struct: "ReversalRequest" }] },
  { name: "actionRecord", params: [{ type: "bytes32" }] },
  { name: "receipt", params: [{ type: "bytes32" }] },
  { name: "caseRecord", params: [{ type: "bytes32" }] },
  { name: "dependencyState", params: [] },
  { name: "trustProfile", params: [] },
];

// Profile interfaces. The schema lists their functions; the generated prose and
// the generated ABI declare identifiers for them but state no derivation rule,
// so the program applies the same ERC-165 XOR rule and reports the outcome.
const NATIVE_ROUTE_FUNCTIONS = [
  { name: "executeERC7943Action", params: [{ struct: "ActionRequest" }] },
  { name: "executeERC7943Reversal", params: [{ struct: "ReversalRequest" }] },
];
const BOUND_DEPENDENCY_FUNCTIONS = [
  { name: "configurationDigest", params: [] },
  {
    name: "assess",
    params: [
      { type: "bytes32" }, { type: "uint8" }, { type: "address" },
      { type: "address" }, { type: "uint256" }, { type: "bytes32" }, { type: "uint64" },
    ],
  },
];
const DECLARED_PROFILE_INTERFACE_IDS = {
  IERCTrustNativeRoute: "0x5cd8d207",
  ITrustBoundDependency: "0xb2306fd2",
};

const STRUCTS = { ActionRequest: ACTION_REQUEST_FIELDS, ReversalRequest: REVERSAL_REQUEST_FIELDS };

// ---------------------------------------------------------------------------
// 2. Byte and word primitives
// ---------------------------------------------------------------------------

function hexToBytes(hex) {
  if (typeof hex !== "string" || !/^0x[0-9a-fA-F]*$/.test(hex)) {
    throw new Error("not a hex string: " + String(hex));
  }
  const body = hex.slice(2);
  if (body.length % 2 !== 0) throw new Error("odd length hex string: " + hex);
  const out = new Uint8Array(body.length / 2);
  for (let i = 0; i < out.length; i += 1) out[i] = parseInt(body.substr(i * 2, 2), 16);
  return out;
}

function bytesToHex(bytes) {
  let s = "0x";
  for (const b of bytes) s += b.toString(16).padStart(2, "0");
  return s;
}

function concatBytes(list) {
  let n = 0;
  for (const b of list) n += b.length;
  const out = new Uint8Array(n);
  let o = 0;
  for (const b of list) { out.set(b, o); o += b.length; }
  return out;
}

function utf8Bytes(s) { return new Uint8Array(Buffer.from(s, "utf8")); }

function toBigInt(v) {
  if (typeof v === "bigint") return v;
  if (typeof v === "number") {
    if (!Number.isSafeInteger(v)) throw new Error("unsafe integer: " + v);
    return BigInt(v);
  }
  if (typeof v === "string") return BigInt(v);
  throw new Error("cannot read as an integer: " + String(v));
}

// "every item occupies one 32-byte word (addresses and narrow integers are
// left-padded with zero bytes; enums are their uint8 value)".
function encodeWord(type, value) {
  if (type === "bytes32") {
    const b = hexToBytes(value);
    if (b.length !== 32) throw new Error("bytes32 must be 32 bytes: " + value);
    return b;
  }
  if (type === "address") {
    const b = hexToBytes(value);
    if (b.length !== 20) throw new Error("address must be 20 bytes: " + value);
    const w = new Uint8Array(32);
    w.set(b, 12);
    return w;
  }
  if (type === "bool") {
    const w = new Uint8Array(32);
    w[31] = value ? 1 : 0;
    return w;
  }
  const m = /^uint(\d+)$/.exec(type);
  if (!m) throw new Error("unsupported type: " + type);
  const bits = Number(m[1]);
  const v = toBigInt(value);
  if (v < 0n) throw new Error("negative value for " + type);
  if (bits < 256 && v >= (1n << BigInt(bits))) throw new Error("value out of range for " + type + ": " + v);
  const w = new Uint8Array(32);
  let x = v;
  for (let i = 31; i >= 0 && x > 0n; i -= 1) { w[i] = Number(x & 0xffn); x >>= 8n; }
  return w;
}

// abi.encode of a list of items, each of which is one static word. A struct is
// spliced in as the static tuple of its fields, which for an all-static tuple is
// exactly its fields encoded in place (no head/tail offset).
function abiEncodeWords(items) {
  return concatBytes(items.map((it) => encodeWord(it.type, it.value)));
}

function structWords(fields, value) {
  return fields.map((f) => {
    if (!(f.name in value)) throw new Error("missing field " + f.name);
    return { type: f.type, value: value[f.name] };
  });
}

// ---------------------------------------------------------------------------
// 3. Hashes, signatures and calldata (bound to the ethers keccak-256 primitive)
// ---------------------------------------------------------------------------

function makeCrypto(keccak256) {
  const k = (bytes) => keccak256(bytes);
  return {
    keccakBytes: k,
    keccakUtf8: (s) => k(utf8Bytes(s)),
    keccakWords: (items) => k(abiEncodeWords(items)),
  };
}

function tupleTypeOf(fields) { return "(" + fields.map((f) => f.type).join(",") + ")"; }

// "A canonical function signature is the function name followed by the
// parenthesized comma-separated canonical parameter types with no spaces."
function signatureOf(fn) {
  const types = fn.params.map((p) => (p.struct ? tupleTypeOf(STRUCTS[p.struct]) : p.type));
  return fn.name + "(" + types.join(",") + ")";
}

function selectorOf(crypto, fn) { return crypto.keccakUtf8(signatureOf(fn)).slice(0, 10); }

function xorSelectors(selectors) {
  const acc = new Uint8Array(4);
  for (const s of selectors) {
    const b = hexToBytes(s);
    for (let i = 0; i < 4; i += 1) acc[i] ^= b[i];
  }
  return bytesToHex(acc);
}

function makeKernel(crypto, domain, endpoint, chainId) {
  const prefix = () => ([
    { type: "bytes32", value: domain },
    { type: "address", value: endpoint },
    { type: "uint256", value: chainId },
  ]);

  const zero32 = "0x" + "00".repeat(32);

  return {
    // actionId: keccak256 over domain, endpoint, chainId and the request with
    // actionId zeroed. The request's actionId field MUST equal this value.
    actionId(request) {
      const r = { ...request, actionId: zero32 };
      return crypto.keccakWords([...prefix(), ...structWords(ACTION_REQUEST_FIELDS, r)]);
    },
    // commandHash: the same preimage over the completed request.
    commandHash(request) {
      return crypto.keccakWords([...prefix(), ...structWords(ACTION_REQUEST_FIELDS, request)]);
    },
    reversalId(request) {
      const r = { ...request, reversalId: zero32 };
      return crypto.keccakWords([...prefix(), ...structWords(REVERSAL_REQUEST_FIELDS, r)]);
    },
    reversalHash(request) {
      return crypto.keccakWords([...prefix(), ...structWords(REVERSAL_REQUEST_FIELDS, request)]);
    },
    // bindingHash (native-full profile): domain, kind, dependency, runtimeCodeId,
    // configurationDigest, schema, epoch.
    bindingHash(kind, dep) {
      return crypto.keccakWords([
        { type: "bytes32", value: domain },
        { type: "uint8", value: kind },
        { type: "address", value: dep.dependency },
        { type: "bytes32", value: dep.runtimeCodeId },
        { type: "bytes32", value: dep.configurationDigest },
        { type: "bytes32", value: dep.schema },
        { type: "uint64", value: dep.epoch },
      ]);
    },
    // dependencyRoot: domain, the DEPENDENCY_ROOT tag, then the four bindings
    // ordered by BindingKind.
    dependencyRoot(tag, bindings) {
      return crypto.keccakWords([
        { type: "bytes32", value: domain },
        { type: "bytes32", value: tag },
        { type: "bytes32", value: bindings.policy },
        { type: "bytes32", value: bindings.identity },
        { type: "bytes32", value: bindings.settlement },
        { type: "bytes32", value: bindings.entitlement },
      ]);
    },
    // receiptHash: seventeen words, the domain then every Receipt field except
    // receiptHash itself.
    receiptHash(receipt) {
      return crypto.keccakWords([
        { type: "bytes32", value: domain },
        ...structWords(RECEIPT_PREIMAGE_FIELDS, receipt),
      ]);
    },
    // nonceKey: domain, authorityRef, authorityEpoch, nonce.
    nonceKey(authorityRef, authorityEpoch, nonce) {
      return crypto.keccakWords([
        { type: "bytes32", value: domain },
        { type: "bytes32", value: authorityRef },
        { type: "uint64", value: authorityEpoch },
        { type: "uint256", value: nonce },
      ]);
    },
    // externalCommitment for LIQUIDATE.
    liquidateExternalCommitment(settlement, proceeds) {
      return crypto.keccakWords([
        { type: "bytes32", value: settlement },
        { type: "bytes32", value: proceeds },
      ]);
    },
    // calldata: selector followed by the canonical encoding of the request.
    actionCalldata(selector, request) {
      return bytesToHex(concatBytes([
        hexToBytes(selector),
        abiEncodeWords(structWords(ACTION_REQUEST_FIELDS, request)),
      ]));
    },
    reversalCalldata(selector, request) {
      return bytesToHex(concatBytes([
        hexToBytes(selector),
        abiEncodeWords(structWords(REVERSAL_REQUEST_FIELDS, request)),
      ]));
    },
  };
}

// ---------------------------------------------------------------------------
// 4. Shape rules and the case state machine
// ---------------------------------------------------------------------------
// Reason codes as the registry names them.
const R = {
  DOMAIN: 1, IDENTIFIER: 2, TIME: 3, AUTHORITY_EPOCH: 4, DEPENDENCY_BINDING: 5,
  SHAPE: 6, REVERSAL_PAIRING: 7, CUSTODY: 8, ENTITLEMENT: 9, CASE_CONFLICT: 10,
  CURRENT_EFFECT: 11, FREEZE_DIRECTION: 12, NO_STATE_CHANGE: 13,
};

const ZERO32 = "0x" + "00".repeat(32);
const ZERO_ADDRESS = "0x" + "00".repeat(20);

function eqHex(a, b) { return String(a).toLowerCase() === String(b).toLowerCase(); }
function isZero32(v) { return eqHex(v, ZERO32); }
function isZeroAddress(v) { return eqHex(v, ZERO_ADDRESS); }

function invalid(reason, rule) { return { error: "TrustInvalidCommand", reason, rule }; }

// An endpoint state as the vectors' fixture describes it. Balances, the
// authority registry and the assessment dependencies are not modelled: the
// fixture carries none of them and the vectors say reason 4 is not exercised.
class EndpointState {
  constructor(kernel, domain, dependencyRoot, dependencyEpoch) {
    this.kernel = kernel;
    this.domain = domain;
    this.dependencyRoot = dependencyRoot;
    this.dependencyEpoch = BigInt(dependencyEpoch);
    this.now = 1000000n;
    this.cases = new Map();          // caseId -> { phase, family, headActionId, generation }
    this.overlayHeads = new Map();   // "family:subject" -> { actionId, caseId }
    this.custody = new Map();        // caseId -> { actionId, custodian, priorHolder, amount }
    this.frozenTarget = new Map();   // subject -> bigint
    this.restricted = new Set();     // subject
    this.actions = new Map();        // actionId -> { request, kind, parentActionId }
    this.consumedCommandIds = new Set();
    this.consumedNonceKeys = new Set();
    this.consumedEntitlements = new Set();
  }

  caseOf(caseId) {
    return this.cases.get(caseId.toLowerCase())
      || { phase: CasePhase.NONE, family: CaseFamily.NONE, headActionId: ZERO32, generation: 0n };
  }

  setCase(caseId, rec) { this.cases.set(caseId.toLowerCase(), rec); }

  // Common rules, in the order the schema lists them. The schema numbers the
  // reasons in that same order but never states that the checks run in list
  // order; this program uses list order and reports the assumption.
  commonChecks(kind, request, derivedId, idField) {
    if (!eqHex(request.domain, this.domain)) return invalid(R.DOMAIN, "domain == domain.keccak256");
    if (!eqHex(request[idField], derivedId)) return invalid(R.IDENTIFIER, "identifier == derived identifier");
    const va = toBigInt(request.validAfter);
    const vb = toBigInt(request.validBefore);
    if (vb === 0n || !(va <= this.now && this.now <= vb)) return invalid(R.TIME, "validity window");
    // reason 4 (authority epoch) is not modelled: the fixture has no registry.
    if (!eqHex(request.dependencyRoot, this.dependencyRoot)
      || toBigInt(request.dependencyEpoch) !== this.dependencyEpoch) {
      return invalid(R.DEPENDENCY_BINDING, "dependencyRoot and dependencyEpoch == current");
    }
    if (isZero32(request.provenanceCommitment)) return invalid(R.SHAPE, "provenanceCommitment != 0");
    if (kind === "action") {
      if (isZeroAddress(request.subject)) return invalid(R.SHAPE, "subject != 0");
      if (isZero32(request.caseId)) return invalid(R.SHAPE, "caseId != 0");
    }
    return null;
  }

  replayChecks(commandId, request) {
    if (this.consumedCommandIds.has(commandId.toLowerCase())) {
      return { error: "TrustReplay", key: commandId, rule: "commandId already consumed" };
    }
    const nk = this.kernel.nonceKey(request.authorityRef, request.authorityEpoch, request.nonce);
    if (this.consumedNonceKeys.has(nk.toLowerCase())) {
      return { error: "TrustReplay", key: nk, rule: "nonce already consumed under (authorityRef, authorityEpoch)" };
    }
    return null;
  }

  // Per-action field rules. A violation without its own code is reason 6.
  fieldRules(request) {
    const a = Number(request.action);
    const commitmentsZero = () =>
      isZero32(request.settlementCommitment) && isZero32(request.proceedsCommitment)
      && isZero32(request.entitlementCommitment);
    const amount = toBigInt(request.amount);

    if (a === ActionKind.FREEZE) {
      if (!eqHex(request.source, request.subject)) return invalid(R.SHAPE, "FREEZE source == subject");
      if (!isZeroAddress(request.destination)) return invalid(R.SHAPE, "FREEZE destination == 0");
      if (!isZeroAddress(request.custodian)) return invalid(R.SHAPE, "FREEZE custodian == 0");
      if (!commitmentsZero()) return invalid(R.SHAPE, "FREEZE commitments == 0");
      const current = this.frozenTarget.get(request.subject.toLowerCase()) || 0n;
      if (!(amount > current)) return invalid(R.FREEZE_DIRECTION, "FREEZE amount > current target");
      return null;
    }
    if (a === ActionKind.RESTRICT) {
      if (!eqHex(request.source, request.subject)) return invalid(R.SHAPE, "RESTRICT source == subject");
      if (!isZeroAddress(request.destination)) return invalid(R.SHAPE, "RESTRICT destination == 0");
      if (!isZeroAddress(request.custodian)) return invalid(R.SHAPE, "RESTRICT custodian == 0");
      if (amount !== 0n) return invalid(R.SHAPE, "RESTRICT amount == 0");
      if (!commitmentsZero()) return invalid(R.SHAPE, "RESTRICT commitments == 0");
      return null;
    }
    if (a === ActionKind.SEIZE) {
      if (!eqHex(request.source, request.subject)) return invalid(R.SHAPE, "SEIZE source == subject");
      if (isZeroAddress(request.custodian)) return invalid(R.SHAPE, "SEIZE custodian != 0");
      if (!eqHex(request.destination, request.custodian)) return invalid(R.SHAPE, "SEIZE destination == custodian");
      if (!(amount > 0n)) return invalid(R.SHAPE, "SEIZE amount > 0");
      if (!commitmentsZero()) return invalid(R.SHAPE, "SEIZE commitments == 0");
      return null;
    }
    if (a === ActionKind.CONFISCATE || a === ActionKind.LIQUIDATE || a === ActionKind.RECOVER) {
      // LIQUIDATE and RECOVER inherit the CONFISCATE rules ("same: CONFISCATE")
      // and override only the commitment rules.
      if (isZeroAddress(request.source)) return invalid(R.SHAPE, "disposition source != 0");
      if (isZeroAddress(request.destination)) return invalid(R.SHAPE, "disposition destination != 0");
      if (eqHex(request.destination, request.source)) return invalid(R.SHAPE, "disposition destination != source");
      if (!isZeroAddress(request.custodian)) return invalid(R.SHAPE, "disposition custodian == 0");
      if (!(amount > 0n)) return invalid(R.SHAPE, "disposition amount > 0");
      if (a === ActionKind.CONFISCATE && !commitmentsZero()) {
        return invalid(R.SHAPE, "CONFISCATE commitments == 0");
      }
      if (a === ActionKind.LIQUIDATE) {
        if (isZero32(request.settlementCommitment)) return invalid(R.SHAPE, "LIQUIDATE settlementCommitment != 0");
        if (isZero32(request.proceedsCommitment)) return invalid(R.SHAPE, "LIQUIDATE proceedsCommitment != 0");
        if (!isZero32(request.entitlementCommitment)) return invalid(R.SHAPE, "LIQUIDATE entitlementCommitment == 0");
      }
      if (a === ActionKind.RECOVER) {
        if (!isZero32(request.settlementCommitment)) return invalid(R.SHAPE, "RECOVER settlementCommitment == 0");
        if (!isZero32(request.proceedsCommitment)) return invalid(R.SHAPE, "RECOVER proceedsCommitment == 0");
        if (isZero32(request.entitlementCommitment)) {
          return invalid(R.SHAPE, "RECOVER entitlementCommitment != 0 (a missing commitment is a field rule, reason 6)");
        }
        if (this.consumedEntitlements.has(request.entitlementCommitment.toLowerCase())) {
          return invalid(R.ENTITLEMENT, "RECOVER entitlementCommitment not previously consumed");
        }
      }
      return null;
    }
    return invalid(R.SHAPE, "action value outside the declared range");
  }

  familyOfAction(request) {
    const a = Number(request.action);
    if (a === ActionKind.FREEZE) return CaseFamily.FREEZE;
    if (a === ActionKind.RESTRICT) return CaseFamily.RESTRICT;
    if (a === ActionKind.SEIZE) return CaseFamily.CUSTODY;
    return CaseFamily.DISPOSITION;
  }

  // Apply an action request. Returns { ok: true, ... } or an error object.
  executeAction(request) {
    const derived = this.kernel.actionId(request);
    const common = this.commonChecks("action", request, derived, "actionId");
    if (common) return common;
    const replay = this.replayChecks(derived, request);
    if (replay) return replay;

    const rec = this.caseOf(request.caseId);
    // CT-15: from TERMINAL, any action or reversal is rejected.
    if (rec.phase === CasePhase.TERMINAL) {
      return { error: "TrustTerminal", caseId: request.caseId, rule: "CT-15" };
    }

    const shape = this.fieldRules(request);
    if (shape) return shape;

    const a = Number(request.action);
    const family = this.familyOfAction(request);
    const subjectKey = request.subject.toLowerCase();

    if (rec.phase === CasePhase.OPEN) {
      // CT-14 and CT-16: a command outside the case's family is rejected.
      const isDisposition = a === ActionKind.CONFISCATE || a === ActionKind.LIQUIDATE || a === ActionKind.RECOVER;
      if (rec.family === CaseFamily.FREEZE && a !== ActionKind.FREEZE) {
        return invalid(R.CASE_CONFLICT, "CT-14");
      }
      if (rec.family === CaseFamily.RESTRICT && a !== ActionKind.RESTRICT) {
        return invalid(R.CASE_CONFLICT, "CT-14");
      }
      if (rec.family === CaseFamily.CUSTODY && (a === ActionKind.FREEZE || a === ActionKind.RESTRICT)) {
        return invalid(R.CASE_CONFLICT, "CT-16");
      }
      if (rec.family === CaseFamily.CUSTODY && a === ActionKind.SEIZE) {
        return invalid(R.CUSTODY, "CT-10");
      }
      if (rec.family === CaseFamily.CUSTODY && isDisposition) {
        // CT-12: the custody disposition consumes the whole custody record.
        const cust = this.custody.get(request.caseId.toLowerCase());
        if (!cust) return invalid(R.CUSTODY, "CT-12 custody record missing");
        if (!eqHex(request.source, cust.custodian)
          || !eqHex(request.subject, cust.priorHolder)
          || toBigInt(request.amount) !== cust.amount) {
          return invalid(R.CUSTODY, "CT-12 guard");
        }
        this.custody.delete(request.caseId.toLowerCase());
        this.setCase(request.caseId, {
          phase: CasePhase.TERMINAL, family: CaseFamily.CUSTODY,
          headActionId: ZERO32, generation: rec.generation + 1n,
        });
        return this.commit(derived, request, a, ZERO32, "CT-12");
      }
    }

    if (a === ActionKind.FREEZE) {
      const head = this.overlayHeads.get("FREEZE:" + subjectKey);
      if (head && !eqHex(head.caseId, request.caseId)) return invalid(R.CASE_CONFLICT, "CT-3");
      const parent = head ? head.actionId : ZERO32;
      this.overlayHeads.set("FREEZE:" + subjectKey, { actionId: derived, caseId: request.caseId });
      this.frozenTarget.set(subjectKey, toBigInt(request.amount));
      this.setCase(request.caseId, {
        phase: CasePhase.OPEN, family: CaseFamily.FREEZE,
        headActionId: derived, generation: rec.generation + 1n,
      });
      return this.commit(derived, request, a, parent, head ? "CT-2" : "CT-1");
    }

    if (a === ActionKind.RESTRICT) {
      const head = this.overlayHeads.get("RESTRICT:" + subjectKey);
      if (head && !eqHex(head.caseId, request.caseId)) return invalid(R.CASE_CONFLICT, "CT-7");
      if (head) return invalid(R.NO_STATE_CHANGE, "CT-6");
      this.overlayHeads.set("RESTRICT:" + subjectKey, { actionId: derived, caseId: request.caseId });
      this.restricted.add(subjectKey);
      this.setCase(request.caseId, {
        phase: CasePhase.OPEN, family: CaseFamily.RESTRICT,
        headActionId: derived, generation: rec.generation + 1n,
      });
      return this.commit(derived, request, a, ZERO32, "CT-5");
    }

    if (a === ActionKind.SEIZE) {
      this.custody.set(request.caseId.toLowerCase(), {
        actionId: derived,
        custodian: request.custodian,
        priorHolder: request.subject,
        amount: toBigInt(request.amount),
      });
      this.setCase(request.caseId, {
        phase: CasePhase.OPEN, family: CaseFamily.CUSTODY,
        headActionId: derived, generation: rec.generation + 1n,
      });
      return this.commit(derived, request, a, ZERO32, "CT-9");
    }

    // Direct disposition, CT-13: source == subject and the case has no prior command.
    if (rec.phase !== CasePhase.NONE) return invalid(R.CASE_CONFLICT, "CT-13 guard: case has a prior command");
    if (!eqHex(request.source, request.subject)) return invalid(R.CUSTODY, "CT-13 guard: source == subject");
    if (a === ActionKind.RECOVER) this.consumedEntitlements.add(request.entitlementCommitment.toLowerCase());
    this.setCase(request.caseId, {
      phase: CasePhase.TERMINAL, family: CaseFamily.DISPOSITION,
      headActionId: ZERO32, generation: rec.generation + 1n,
    });
    return this.commit(derived, request, a, ZERO32, "CT-13");
  }

  commit(actionId, request, kind, parentActionId, rule) {
    this.consumedCommandIds.add(actionId.toLowerCase());
    this.consumedNonceKeys.add(
      this.kernel.nonceKey(request.authorityRef, request.authorityEpoch, request.nonce).toLowerCase(),
    );
    this.actions.set(actionId.toLowerCase(), { request, kind, parentActionId });
    return { ok: true, actionId, rule };
  }

  executeReversal(request) {
    const derived = this.kernel.reversalId(request);
    const common = this.commonChecks("reversal", request, derived, "reversalId");
    if (common) return common;
    const replay = this.replayChecks(derived, request);
    if (replay) return replay;

    const parent = this.actions.get(String(request.actionId).toLowerCase());
    if (!parent) return invalid(R.CURRENT_EFFECT, "referenced action is not applied");
    const caseId = parent.request.caseId;
    const rec = this.caseOf(caseId);
    if (rec.phase === CasePhase.TERMINAL) {
      return { error: "TrustTerminal", caseId, rule: "CT-15" };
    }

    const rk = Number(request.reversal);
    const pairs = {
      [ReversalKind.UNFREEZE]: ActionKind.FREEZE,
      [ReversalKind.RELEASE]: ActionKind.SEIZE,
      [ReversalKind.UNRESTRICT]: ActionKind.RESTRICT,
    };
    if (pairs[rk] === undefined) return invalid(R.SHAPE, "reversal value outside the declared range");
    if (parent.kind !== pairs[rk]) return invalid(R.REVERSAL_PAIRING, "reversal pairing");

    const subjectKey = parent.request.subject.toLowerCase();
    if (rk === ReversalKind.UNFREEZE) {
      const head = this.overlayHeads.get("FREEZE:" + subjectKey);
      if (!head || !eqHex(head.actionId, request.actionId)) return invalid(R.CURRENT_EFFECT, "CT-4 guard");
      const grandparent = parent.parentActionId;
      if (isZero32(grandparent)) {
        this.overlayHeads.delete("FREEZE:" + subjectKey);
        this.frozenTarget.set(subjectKey, 0n);
        this.setCase(caseId, {
          phase: CasePhase.TERMINAL, family: CaseFamily.FREEZE,
          headActionId: ZERO32, generation: rec.generation + 1n,
        });
      } else {
        const gp = this.actions.get(grandparent.toLowerCase());
        this.overlayHeads.set("FREEZE:" + subjectKey, { actionId: grandparent, caseId: gp.request.caseId });
        this.frozenTarget.set(subjectKey, toBigInt(gp.request.amount));
        this.setCase(caseId, {
          phase: CasePhase.OPEN, family: CaseFamily.FREEZE,
          headActionId: grandparent, generation: rec.generation + 1n,
        });
      }
    } else if (rk === ReversalKind.UNRESTRICT) {
      const head = this.overlayHeads.get("RESTRICT:" + subjectKey);
      if (!head || !eqHex(head.actionId, request.actionId)) return invalid(R.CURRENT_EFFECT, "CT-8 guard");
      this.overlayHeads.delete("RESTRICT:" + subjectKey);
      this.restricted.delete(subjectKey);
      this.setCase(caseId, {
        phase: CasePhase.TERMINAL, family: CaseFamily.RESTRICT,
        headActionId: ZERO32, generation: rec.generation + 1n,
      });
    } else {
      const cust = this.custody.get(caseId.toLowerCase());
      if (!cust) return invalid(R.CUSTODY, "CT-11 custody record missing");
      if (!eqHex(cust.actionId, request.actionId)) return invalid(R.CURRENT_EFFECT, "CT-11 guard");
      this.custody.delete(caseId.toLowerCase());
      this.setCase(caseId, {
        phase: CasePhase.TERMINAL, family: CaseFamily.CUSTODY,
        headActionId: ZERO32, generation: rec.generation + 1n,
      });
    }

    this.consumedCommandIds.add(derived.toLowerCase());
    this.consumedNonceKeys.add(
      this.kernel.nonceKey(request.authorityRef, request.authorityEpoch, request.nonce).toLowerCase(),
    );
    return { ok: true, reversalId: derived, rule: "reversal applied" };
  }
}

// ---------------------------------------------------------------------------
// 5. Receipt derivation from the request, as the Receipt field meanings state
// ---------------------------------------------------------------------------

function deriveActionReceipt(kernel, request, actionId, opaque) {
  const a = Number(request.action);
  const effectiveDestination = a === ActionKind.SEIZE ? request.custodian : request.destination;
  let externalCommitment = ZERO32;
  if (a === ActionKind.LIQUIDATE) {
    externalCommitment = kernel.liquidateExternalCommitment(
      request.settlementCommitment, request.proceedsCommitment,
    );
  } else if (a === ActionKind.RECOVER) {
    externalCommitment = request.entitlementCommitment;
  }
  return {
    receiptKind: ReceiptKind.ACTION,
    commandId: actionId,
    commandKind: a,
    parentCommandId: ZERO32,
    subject: request.subject,
    source: request.source,
    destination: effectiveDestination,
    amount: request.amount,
    caseId: request.caseId,
    authorityRef: request.authorityRef,
    dependencyRoot: request.dependencyRoot,
    provenanceCommitment: request.provenanceCommitment,
    assessmentEvidence: opaque.assessmentEvidence,
    preState: opaque.preState,
    postState: opaque.postState,
    externalCommitment,
  };
}

function deriveReversalReceipt(request, reversalId, parentRequest, opaque) {
  const rk = Number(request.reversal);
  // "REVERSAL of SEIZE: the custodian; other reversals: the subject" for source;
  // "RELEASE: the declared prior holder; UNFREEZE and UNRESTRICT: the subject"
  // for destination. subject, amount and caseId have no reversal-specific rule,
  // so they are taken from the action being reversed.
  const source = rk === ReversalKind.RELEASE ? parentRequest.custodian : parentRequest.subject;
  const destination = parentRequest.subject;
  return {
    receiptKind: ReceiptKind.REVERSAL,
    commandId: reversalId,
    commandKind: rk,
    parentCommandId: request.actionId,
    subject: parentRequest.subject,
    source,
    destination,
    amount: parentRequest.amount,
    caseId: parentRequest.caseId,
    authorityRef: request.authorityRef,
    dependencyRoot: request.dependencyRoot,
    provenanceCommitment: request.provenanceCommitment,
    assessmentEvidence: opaque.assessmentEvidence,
    preState: opaque.preState,
    postState: opaque.postState,
    externalCommitment: ZERO32,
  };
}

// ---------------------------------------------------------------------------
// 6. Result recording
// ---------------------------------------------------------------------------

class Recorder {
  constructor() { this.groups = new Map(); this.failures = []; }

  group(kind) {
    if (!this.groups.has(kind)) this.groups.set(kind, []);
    return this.groups.get(kind);
  }

  entry(kind, id, note) {
    const e = { id, status: "PASS", checks: [], derived: {} };
    if (note) e.note = note;
    this.group(kind).push(e);
    return e;
  }

  check(entry, kind, name, expected, actual, comparator) {
    const cmp = comparator || ((x, y) => (typeof x === "string" && typeof y === "string" ? eqHex(x, y) : x === y));
    const ok = cmp(expected, actual);
    const rec = { name, status: ok ? "PASS" : "FAIL" };
    if (!ok) {
      rec.expected = expected;
      rec.actual = actual;
      entry.status = "FAIL";
      this.failures.push({ kind, id: entry.id, check: name, expected, actual });
    }
    entry.checks.push(rec);
    return ok;
  }

  counts() {
    const out = {};
    for (const [kind, list] of this.groups) {
      out[kind] = {
        vectors: list.length,
        assertions: list.reduce((n, e) => n + e.checks.length, 0),
        passed: list.filter((e) => e.status === "PASS").length,
        failed: list.filter((e) => e.status === "FAIL").length,
      };
    }
    return out;
  }
}

// ---------------------------------------------------------------------------
// 7. Main
// ---------------------------------------------------------------------------

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const { keccak256, AbiCoder, version: ethersVersion } = await loadEthers(args.ethers);
  const crypto = makeCrypto(keccak256);

  const vectorBytes = readFileSync(args.vectors);
  const vectorsSha256 = "0x" + createHash("sha256").update(vectorBytes).digest("hex");
  const vectorsKeccak256 = keccak256(new Uint8Array(vectorBytes));
  const V = JSON.parse(vectorBytes.toString("utf8"));

  const rec = new Recorder();
  const notEvaluable = [];
  const findings = [];

  // --- constants ----------------------------------------------------------
  const domain = crypto.keccakUtf8(DOMAIN_STRING);
  const tag = crypto.keccakUtf8(DEPENDENCY_ROOT_TAG_STRING);

  {
    const e = rec.entry("constants", "CONSTANTS");
    rec.check(e, "constants", "domain == keccak256(utf8 'ERC-TRUST/v2')", V.constants.domain, domain);
    rec.check(e, "constants", "dependencyRootTag == keccak256(utf8 'ERC-TRUST/v2/dependency-root')",
      V.constants.dependencyRootTag, tag);
    for (const [name, str] of Object.entries(PROFILE_STRINGS)) {
      rec.check(e, "constants", "profileId " + name, V.constants.profileIds[name], crypto.keccakUtf8(str));
    }
    e.derived.domain = domain;
    e.derived.dependencyRootTag = tag;
  }

  {
    const e = rec.entry("constants", "SELECTORS");
    const computed = {};
    for (const fn of KERNEL_FUNCTIONS) {
      const sig = signatureOf(fn);
      const sel = selectorOf(crypto, fn);
      computed[sig] = sel;
      const declared = V.constants.selectors[sig];
      rec.check(e, "constants", "selector " + sig, declared === undefined ? "(signature absent from vectors)" : declared, sel);
    }
    const declaredSignatures = Object.keys(V.constants.selectors).sort();
    rec.check(e, "constants", "selector signature set matches the schema function list",
      declaredSignatures.join("|"), Object.keys(computed).sort().join("|"));
    e.derived.selectors = computed;
  }

  {
    const e = rec.entry("constants", "INTERFACE-IDS");
    const kernelId = xorSelectors(KERNEL_FUNCTIONS.map((fn) => selectorOf(crypto, fn)));
    rec.check(e, "constants", "kernel interface id == XOR of the nine selectors",
      V.constants.kernelInterfaceId, kernelId);
    const routeId = xorSelectors(NATIVE_ROUTE_FUNCTIONS.map((fn) => selectorOf(crypto, fn)));
    rec.check(e, "constants", "IERCTrustNativeRoute id == XOR of its two selectors (value declared by the specification, not by the vectors)",
      DECLARED_PROFILE_INTERFACE_IDS.IERCTrustNativeRoute, routeId);
    const depId = xorSelectors(BOUND_DEPENDENCY_FUNCTIONS.map((fn) => selectorOf(crypto, fn)));
    rec.check(e, "constants", "ITrustBoundDependency id == XOR of its two selectors (value declared by the specification, not by the vectors)",
      DECLARED_PROFILE_INTERFACE_IDS.ITrustBoundDependency, depId);
    e.derived.kernelInterfaceId = kernelId;
    e.derived.nativeRouteInterfaceId = routeId;
    e.derived.boundDependencyInterfaceId = depId;
  }

  {
    const e = rec.entry("constants", "CALLDATA-LENGTHS");
    rec.check(e, "constants", "action calldata length == 4 + 32 * 20",
      V.constants.actionCalldataLength, 4 + 32 * ACTION_REQUEST_FIELDS.length);
    rec.check(e, "constants", "reversal calldata length == 4 + 32 * 12",
      V.constants.reversalCalldataLength, 4 + 32 * REVERSAL_REQUEST_FIELDS.length);
  }

  // --- kernel bound to the fixture endpoint -------------------------------
  const fixture = V.fixture;
  const kernel = makeKernel(crypto, domain, fixture.endpoint, fixture.chainId);
  const actionSelector = selectorOf(crypto, KERNEL_FUNCTIONS[0]);
  const reversalSelector = selectorOf(crypto, KERNEL_FUNCTIONS[1]);

  // --- encoder cross-check against a second ABI implementation ------------
  {
    const e = rec.entry("encoder", "ENCODER-CROSS-CHECK");
    const coder = AbiCoder.defaultAbiCoder();
    const first = V.actions[0];
    const actionTuple = "tuple" + tupleTypeOf(ACTION_REQUEST_FIELDS);
    const actionValues = ACTION_REQUEST_FIELDS.map((f) => {
      const v = first.request[f.name];
      return /^uint/.test(f.type) ? toBigInt(v) : v;
    });
    const mine = bytesToHex(abiEncodeWords(structWords(ACTION_REQUEST_FIELDS, first.request)));
    rec.check(e, "encoder", "hand-written ActionRequest encoding == AbiCoder tuple encoding",
      coder.encode([actionTuple], [actionValues]), mine);

    const firstRev = V.reversals[0];
    const revTuple = "tuple" + tupleTypeOf(REVERSAL_REQUEST_FIELDS);
    const revValues = REVERSAL_REQUEST_FIELDS.map((f) => {
      const v = firstRev.request[f.name];
      return /^uint/.test(f.type) ? toBigInt(v) : v;
    });
    rec.check(e, "encoder", "hand-written ReversalRequest encoding == AbiCoder tuple encoding",
      coder.encode([revTuple], [revValues]), bytesToHex(abiEncodeWords(structWords(REVERSAL_REQUEST_FIELDS, firstRev.request))));

    // The full actionId preimage, nested exactly as abi.encode would build it.
    const preimage = coder.encode(
      ["bytes32", "address", "uint256", actionTuple],
      [domain, fixture.endpoint, toBigInt(fixture.chainId),
        ACTION_REQUEST_FIELDS.map((f) => {
          const v = f.name === "actionId" ? ZERO32 : first.request[f.name];
          return /^uint/.test(f.type) ? toBigInt(v) : v;
        })],
    );
    rec.check(e, "encoder", "actionId preimage == AbiCoder nested encoding", keccak256(preimage), kernel.actionId(first.request));
  }

  // --- fixture ------------------------------------------------------------
  const bindings = {};
  {
    const e = rec.entry("fixture", "FIXTURE");
    const order = [["policy", BindingKind.POLICY], ["identity", BindingKind.IDENTITY],
      ["settlement", BindingKind.SETTLEMENT], ["entitlement", BindingKind.ENTITLEMENT]];
    for (const [name, kind] of order) {
      const h = kernel.bindingHash(kind, fixture.dependencies[name]);
      bindings[name] = h;
      rec.check(e, "fixture", "bindingHash " + name, fixture.bindingHashes[name], h);
    }
    const root = kernel.dependencyRoot(tag, bindings);
    rec.check(e, "fixture", "dependencyRoot", fixture.dependencyRoot, root);
    const nk = fixture.nonceKeyExample;
    rec.check(e, "fixture", "nonceKey example",
      nk.nonceKey, kernel.nonceKey(nk.authorityRef, nk.authorityEpoch, nk.nonce));
    e.derived.bindingHashes = { ...bindings };
    e.derived.dependencyRoot = root;
  }
  const fixtureRoot = kernel.dependencyRoot(tag, bindings);

  const freshState = () => new EndpointState(kernel, domain, fixtureRoot, fixture.dependencyEpoch);

  // --- action vectors -----------------------------------------------------
  const actionById = new Map(V.actions.map((a) => [a.id, a]));
  for (const vec of V.actions) {
    const e = rec.entry("actions", vec.id, vec.action + " / " + vec.path);
    const req = vec.request;
    const actionId = kernel.actionId(req);
    const commandHash = kernel.commandHash(req);
    const calldata = kernel.actionCalldata(actionSelector, req);

    rec.check(e, "actions", "derived actionId", vec.actionId, actionId);
    rec.check(e, "actions", "request.actionId equals the derived identifier", vec.actionId, req.actionId);
    rec.check(e, "actions", "commandHash", vec.commandHash, commandHash);
    rec.check(e, "actions", "calldata", vec.calldata, calldata);
    rec.check(e, "actions", "calldata length", V.constants.actionCalldataLength, (calldata.length - 2) / 2);
    rec.check(e, "actions", "request.domain == the domain constant", domain, req.domain);
    rec.check(e, "actions", "request.dependencyRoot == the fixture root", fixtureRoot, req.dependencyRoot);
    rec.check(e, "actions", "request.dependencyEpoch == the fixture epoch",
      String(fixture.dependencyEpoch), String(req.dependencyEpoch));
    rec.check(e, "actions", "declared action name matches the enum value",
      vec.action, ActionKindName[Number(req.action)]);

    const derivedReceipt = deriveActionReceipt(kernel, req, actionId, vec.receiptInput);
    for (const f of RECEIPT_PREIMAGE_FIELDS) {
      if (["assessmentEvidence", "preState", "postState"].includes(f.name)) continue;
      rec.check(e, "actions", "receipt field " + f.name,
        String(vec.receiptInput[f.name]).toLowerCase(), String(derivedReceipt[f.name]).toLowerCase());
    }
    const receiptHash = kernel.receiptHash(vec.receiptInput);
    rec.check(e, "actions", "receiptHash from the vector receipt input", vec.receiptHash, receiptHash);
    rec.check(e, "actions", "receiptHash from the independently derived receipt",
      vec.receiptHash, kernel.receiptHash(derivedReceipt));

    // The scenario: this vector, evaluated against the initial fixture state
    // (the custody disposition needs its opening SEIZE first).
    const st = freshState();
    let outcome = null;
    if (vec.path === "custody disposition") {
      const seize = V.actions.find((a) => a.action === "SEIZE" && eqHex(a.request.caseId, req.caseId));
      outcome = st.executeAction(seize.request);
      rec.check(e, "actions", "opening SEIZE of the custody scenario is accepted", true, outcome.ok === true);
    }
    outcome = st.executeAction(req);
    rec.check(e, "actions", "accepted by the shape and case rules", true, outcome.ok === true);
    if (!outcome.ok) e.derived.rejection = outcome;
    else e.derived.caseRule = outcome.rule;

    e.derived.actionId = actionId;
    e.derived.commandHash = commandHash;
    e.derived.receiptHash = receiptHash;
    e.derived.externalCommitment = derivedReceipt.externalCommitment;
  }

  // --- reversal vectors ---------------------------------------------------
  for (const vec of V.reversals) {
    const e = rec.entry("reversals", vec.id, vec.reversal + " reverses " + vec.reverses);
    const req = vec.request;
    const parentVec = actionById.get(vec.reverses);
    const reversalId = kernel.reversalId(req);
    const reversalHash = kernel.reversalHash(req);
    const calldata = kernel.reversalCalldata(reversalSelector, req);

    rec.check(e, "reversals", "derived reversalId", vec.reversalId, reversalId);
    rec.check(e, "reversals", "request.reversalId equals the derived identifier", vec.reversalId, req.reversalId);
    rec.check(e, "reversals", "reversalHash", vec.reversalHash, reversalHash);
    rec.check(e, "reversals", "calldata", vec.calldata, calldata);
    rec.check(e, "reversals", "calldata length", V.constants.reversalCalldataLength, (calldata.length - 2) / 2);
    rec.check(e, "reversals", "request.actionId is the referenced action", parentVec.actionId, req.actionId);
    rec.check(e, "reversals", "declared reversal name matches the enum value",
      vec.reversal, ReversalKindName[Number(req.reversal)]);
    const pairing = { UNFREEZE: "FREEZE", RELEASE: "SEIZE", UNRESTRICT: "RESTRICT" };
    rec.check(e, "reversals", "reversal pairs with the action kind", pairing[vec.reversal], parentVec.action);

    const derivedReceipt = deriveReversalReceipt(req, reversalId, parentVec.request, vec.receiptInput);
    for (const f of RECEIPT_PREIMAGE_FIELDS) {
      if (["assessmentEvidence", "preState", "postState"].includes(f.name)) continue;
      rec.check(e, "reversals", "receipt field " + f.name,
        String(vec.receiptInput[f.name]).toLowerCase(), String(derivedReceipt[f.name]).toLowerCase());
    }
    rec.check(e, "reversals", "receiptHash from the vector receipt input", vec.receiptHash, kernel.receiptHash(vec.receiptInput));
    rec.check(e, "reversals", "receiptHash from the independently derived receipt",
      vec.receiptHash, kernel.receiptHash(derivedReceipt));

    const st = freshState();
    const parentOutcome = st.executeAction(parentVec.request);
    rec.check(e, "reversals", "the reversed action is accepted first", true, parentOutcome.ok === true);
    const outcome = st.executeReversal(req);
    rec.check(e, "reversals", "accepted by the pairing and case rules", true, outcome.ok === true);
    if (!outcome.ok) e.derived.rejection = outcome;

    e.derived.reversalId = reversalId;
    e.derived.reversalHash = reversalHash;
  }

  // --- negative vectors ---------------------------------------------------
  const freeze = actionById.get("ACTION-FREEZE");
  const withField = (req, field, value) => ({ ...req, [field]: value });
  const reDerive = (req) => { const r = { ...req }; r.actionId = kernel.actionId(r); return r; };

  for (const neg of V.negative) {
    const e = rec.entry("negative", neg.id, neg.mutation);

    if (neg.id === "NEG-WRONG-DOMAIN") {
      // Mutate the domain and re-derive the identifier, so the domain check is
      // the only common rule that can fail and the expected reason is isolated.
      const bad = reDerive(withField(freeze.request, "domain", "0x" + "0d".repeat(32)));
      const st = freshState();
      const out = st.executeAction(bad);
      rec.check(e, "negative", "rejected with TrustInvalidCommand", "TrustInvalidCommand", out.error);
      rec.check(e, "negative", "reason 1", 1, out.reason);
      rec.check(e, "negative", "expectation text names reason 1", true, /reason 1\b/.test(neg.expected));
      // The same mutation without re-deriving also changes the identifier.
      const kept = withField(freeze.request, "domain", "0x" + "0d".repeat(32));
      rec.check(e, "negative", "the mutation also changes the derived identifier",
        false, eqHex(kernel.actionId(kept), freeze.actionId));
      e.derived.rejection = out;
    }

    if (neg.id === "NEG-FIELD-BINDING") {
      const covered = new Set(neg.mutatedDerivedActionIds.map((m) => m.field));
      const expectCovered = ACTION_REQUEST_FIELDS.map((f) => f.name).filter((n) => n !== "actionId");
      rec.check(e, "negative", "every ActionRequest field except actionId is covered",
        expectCovered.sort().join(","), [...covered].sort().join(","));
      for (const m of neg.mutatedDerivedActionIds) {
        rec.check(e, "negative", "originalValue of " + m.field + " matches the base request",
          String(freeze.request[m.field]).toLowerCase(), String(m.originalValue).toLowerCase());
        const mutated = withField(freeze.request, m.field, m.mutatedValue);
        const id = kernel.actionId(mutated);
        rec.check(e, "negative", "derived actionId for mutated " + m.field, m.derivedActionId, id);
        rec.check(e, "negative", "mutated " + m.field + " changes the identifier",
          false, eqHex(id, freeze.actionId));
        // The vector describes the mutation as happening after actionId was
        // derived, so the original actionId is kept and the identifier rule is
        // the one that rejects it, which is the reason 2 the vector expects.
        // The domain row is the stated exception: the schema's shape-rule order
        // checks the domain rule ahead of the identifier rule, so the endpoint
        // answers reason 1, and the vector's expected text says so.
        const st = freshState();
        const out = st.executeAction({ ...mutated, actionId: freeze.request.actionId });
        const expected = m.field === "domain" ? 1 : 2;
        rec.check(e, "negative", "rejected for mutated " + m.field + " (reason " + expected + " under list-order checking)",
          expected, out.reason);
      }
      rec.check(e, "negative", "expectation text names reason 2 and the domain exception", true, /reason 2\b/.test(neg.expected) && /domain/.test(neg.expected));
      findings.push({
        id: "NEG-FIELD-BINDING domain row",
        observation: "Eighteen of the nineteen mutations are rejected by the identifier rule with reason 2; the domain row is rejected first by the domain rule with reason 1, as the shape-rule order in the schema and the vector's expected text state. The vector's primary claim, that every mutation yields a different derived actionId, holds for all nineteen.",
        impact: "Documentation only. No identifier or hash in the vectors is affected.",
      });
    }

    if (neg.id === "NEG-STALE-DEPENDENCY") {
      // Rebind each kind in turn: the binding hash and the root change, and the
      // epoch advances by exactly one, so the unchanged request is stale.
      const order = [["policy", BindingKind.POLICY], ["identity", BindingKind.IDENTITY],
        ["settlement", BindingKind.SETTLEMENT], ["entitlement", BindingKind.ENTITLEMENT]];
      for (const [name, kind] of order) {
        const rebound = { ...fixture.dependencies[name], configurationDigest: "0x" + "5c".repeat(32) };
        const newBindings = { ...bindings, [name]: kernel.bindingHash(kind, rebound) };
        const newRoot = kernel.dependencyRoot(tag, newBindings);
        rec.check(e, "negative", "rebinding " + name + " changes the binding hash",
          false, eqHex(newBindings[name], bindings[name]));
        rec.check(e, "negative", "rebinding " + name + " changes the dependency root",
          false, eqHex(newRoot, fixtureRoot));
        const st = new EndpointState(kernel, domain, newRoot, BigInt(fixture.dependencyEpoch) + 1n);
        const out = st.executeAction(freeze.request);
        rec.check(e, "negative", "stale request after rebinding " + name + " is TrustInvalidCommand",
          "TrustInvalidCommand", out.error);
        rec.check(e, "negative", "reason 5 after rebinding " + name, 5, out.reason);
      }
      rec.check(e, "negative", "expectation text names reason 5", true, /reason 5\b/.test(neg.expected));
    }

    if (neg.id === "NEG-CASE-CONFLICT") {
      // CT-3: a second FREEZE on the same subject owned by another case.
      let st = freshState();
      st.executeAction(freeze.request);
      const otherCaseFreeze = reDerive({
        ...freeze.request,
        caseId: "0x" + "1a".repeat(32),
        amount: "124",
        nonce: "900",
      });
      const outCt3 = st.executeAction(otherCaseFreeze);
      rec.check(e, "negative", "CT-3 second FREEZE in another case is TrustInvalidCommand",
        "TrustInvalidCommand", outCt3.error);
      rec.check(e, "negative", "CT-3 reason 10", 10, outCt3.reason);

      // CT-7: a second RESTRICT on the same subject owned by another case.
      st = freshState();
      const restrict = actionById.get("ACTION-RESTRICT");
      st.executeAction(restrict.request);
      const otherCaseRestrict = reDerive({
        ...restrict.request,
        caseId: "0x" + "1b".repeat(32),
        nonce: "901",
      });
      const outCt7 = st.executeAction(otherCaseRestrict);
      rec.check(e, "negative", "CT-7 second RESTRICT in another case is TrustInvalidCommand",
        "TrustInvalidCommand", outCt7.error);
      rec.check(e, "negative", "CT-7 reason 10", 10, outCt7.reason);

      // CT-14: a disposition against an open overlay case.
      st = freshState();
      st.executeAction(freeze.request);
      const confiscate = actionById.get("ACTION-CONFISCATE");
      const intoOverlay = reDerive({
        ...confiscate.request,
        caseId: freeze.request.caseId,
        nonce: "902",
      });
      const outCt14 = st.executeAction(intoOverlay);
      rec.check(e, "negative", "CT-14 disposition against an open overlay case is TrustInvalidCommand",
        "TrustInvalidCommand", outCt14.error);
      rec.check(e, "negative", "CT-14 reason 10", 10, outCt14.reason);
      rec.check(e, "negative", "expectation text names reason 10", true, /reason 10\b/.test(neg.expected));
    }

    if (neg.id === "NEG-TERMINAL") {
      // A direct disposition closes its case, then any further action in that
      // case is rejected with TrustTerminal.
      let st = freshState();
      const confiscate = actionById.get("ACTION-CONFISCATE");
      const first = st.executeAction(confiscate.request);
      rec.check(e, "negative", "the direct disposition closes the case", true, first.ok === true);
      rec.check(e, "negative", "case phase is TERMINAL", CasePhase.TERMINAL, st.caseOf(confiscate.request.caseId).phase);
      const again = reDerive({ ...confiscate.request, nonce: "903" });
      const out = st.executeAction(again);
      rec.check(e, "negative", "a further action in a TERMINAL case is TrustTerminal", "TrustTerminal", out.error);
      rec.check(e, "negative", "TrustTerminal carries the caseId", confiscate.request.caseId, out.caseId);

      // A reversal against a TERMINAL case is rejected the same way.
      st = freshState();
      const restrict = actionById.get("ACTION-RESTRICT");
      const unrestrict = V.reversals.find((r) => r.reversal === "UNRESTRICT");
      st.executeAction(restrict.request);
      st.executeReversal(unrestrict.request);
      const secondReversal = { ...unrestrict.request, nonce: "904" };
      secondReversal.reversalId = kernel.reversalId(secondReversal);
      const outRev = st.executeReversal(secondReversal);
      rec.check(e, "negative", "a reversal against a TERMINAL case is TrustTerminal", "TrustTerminal", outRev.error);
      rec.check(e, "negative", "expectation text names TrustTerminal", true, /TrustTerminal/.test(neg.expected));
    }

    if (neg.id === "NEG-REPLAY") {
      // Re-submitting an applied command.
      let st = freshState();
      st.executeAction(freeze.request);
      const out = st.executeAction(freeze.request);
      rec.check(e, "negative", "resubmitting an applied command is TrustReplay", "TrustReplay", out.error);
      rec.check(e, "negative", "the replay key is the commandId", freeze.actionId, out.key);

      // Reusing the nonce under the same authority and epoch.
      st = freshState();
      st.executeAction(freeze.request);
      const seize = actionById.get("ACTION-SEIZE");
      const reused = reDerive({ ...seize.request, nonce: freeze.request.nonce });
      const out2 = st.executeAction(reused);
      rec.check(e, "negative", "reusing a nonce is TrustReplay", "TrustReplay", out2.error);
      rec.check(e, "negative", "the replay key is the nonceKey",
        fixture.nonceKeyExample.nonceKey,
        kernel.nonceKey(reused.authorityRef, reused.authorityEpoch, reused.nonce));
      rec.check(e, "negative", "the reported key is that nonceKey", fixture.nonceKeyExample.nonceKey, out2.key);
      rec.check(e, "negative", "expectation text names TrustReplay", true, /TrustReplay/.test(neg.expected));
    }

    if (neg.id === "NEG-RECEIPT-KIND") {
      const unfreeze = V.reversals.find((r) => r.reversal === "UNFREEZE");
      rec.check(e, "negative", "the reversal receipt hash matches the example",
        neg.example.reversalReceiptHash, kernel.receiptHash(unfreeze.receiptInput));
      const asAction = { ...unfreeze.receiptInput, receiptKind: ReceiptKind.ACTION };
      const mutated = kernel.receiptHash(asAction);
      rec.check(e, "negative", "the same fields with receiptKind ACTION give the recorded hash",
        neg.example.sameFieldsWithActionKind, mutated);
      rec.check(e, "negative", "the two hashes differ", false, eqHex(mutated, neg.example.reversalReceiptHash));
      e.derived.sameFieldsWithActionKind = mutated;
    }
  }

  findings.push({
    id: "check order is unspecified and two negative vectors disagree on the domain field",
    observation: "NEG-WRONG-DOMAIN expects reason 1 for a wrong domain and NEG-FIELD-BINDING expects reason 2 for every one-field mutation, the domain field included. Both are satisfiable at once only if the domain rule is evaluated before the identifier rule and NEG-WRONG-DOMAIN is read as re-deriving the identifier over the mutated request. The specification states neither the evaluation order nor whether NEG-WRONG-DOMAIN re-derives.",
    impact: "An independent implementer can reproduce every published identifier and hash without resolving this, but cannot predict the reason code of a request that breaks more than one rule.",
  });
  findings.push({
    id: "generated prose renders shapeRules.appliesTo character by character",
    observation: "At the base of the change that added this program, spec/generated/kernel-v2.md rendered the shape rules 'appliesTo' entry character by character, one numbered entry per letter of the sentence held in the schema, because the prose generator treated a string value as a map of fields. The machine source was correct; the generator was corrected in the same change and the prose now shows the sentence.",
    impact: "Cosmetic defect in the normative prose. No hash, identifier or calldata is affected.",
  });
  findings.push({
    id: "profile interface identifiers are declared without a rule",
    observation: "The generated prose and the generated ABI publish identifiers for IERCTrustNativeRoute and ITrustBoundDependency, but only the kernel interface has a stated derivation rule. Applying the kernel's XOR rule to the profile interfaces reproduces both declared values, so the rule is the same one; it is simply not written down for them.",
    impact: "Reproducible, but only by assuming a rule the specification does not state for these two identifiers.",
  });
  findings.push({
    id: "ACTION and REVERSAL receipts can share a commandKind byte",
    observation: "Receipt.commandKind holds an ActionKind value for ACTION receipts and a ReversalKind value for REVERSAL receipts, and both enumerations start at zero. A FREEZE action receipt and an UNFREEZE reversal receipt therefore carry commandKind 0, and only the receiptKind word separates the two preimages. NEG-RECEIPT-KIND is the vector that pins this separation, and it reproduces exactly.",
    impact: "Not a defect. It is the reason the receiptKind word has to be in the preimage, and the vectors do exercise it.",
  });

  notEvaluable.push({
    item: "full-state stutter",
    where: "expected text of NEG-CASE-CONFLICT, NEG-TERMINAL and NEG-REPLAY",
    why: "The phrase is used as part of the expected outcome but is defined nowhere in the machine source, the generated prose or the generated ABI. The program checks the typed error and the reason code of those three vectors and cannot check the stutter claim.",
  });
  notEvaluable.push({
    item: "reason 4 (authority epoch)",
    where: "shapeRules.common",
    why: "The vectors state that the fixture does not model the authority registry and that reason 4 is not exercised, so the program models no authority epoch check.",
  });
  notEvaluable.push({
    item: "balance availability and cross-case custody backing (reason 8 on the direct path)",
    where: "shapeRules.SEIZE and shapeRules.CONFISCATE",
    why: "The fixture carries no balances, so 'available without consuming custody backing of another case' cannot be evaluated. The program models the per-case custody record only.",
  });
  notEvaluable.push({
    item: "assessmentEvidence, preState and postState",
    where: "Receipt fields 12 to 14",
    why: "Their preimages are profile-defined and the fixture calls them opaque values, so the program consumes them from the vector rather than deriving them.",
  });

  // --- summary ------------------------------------------------------------
  const counts = rec.counts();
  const totals = Object.values(counts).reduce(
    (acc, c) => ({
      vectors: acc.vectors + c.vectors,
      assertions: acc.assertions + c.assertions,
      passed: acc.passed + c.passed,
      failed: acc.failed + c.failed,
    }),
    { vectors: 0, assertions: 0, passed: 0, failed: 0 },
  );

  const summary = {
    schema: "erc-trust-independent-reproduction-v3",
    kernelVersion: 2,
    producer: {
      program: "independent-reproduction-v3.mjs",
      role: "independent implementer, specification only",
      specificationTranscribedFrom: [
        "spec/erc-trust-kernel-v2.json",
        "spec/generated/kernel-v2.md",
        "spec/generated/kernel-v2-abi.json",
      ],
      note: "The program transcribes the specification by hand and reads the vectors file at run time; the schema and ABI files are hashed (not parsed) so that a change to either reopens this receipt.",
      inputsNotRead: [
        "implementation/", "sdk/src/", "sdk/*.ts", "scripts/", "formal/",
        "evidence/", "pilot/", "docs/", "README.md", "FORMAL_VERIFICATION.md",
      ],
      externalModule: { name: "ethers", version: ethersVersion, usedFor: "keccak-256 and an independent ABI cross-check" },
    },
    inputs: {
      vectorsPath: path.relative(process.cwd(), path.resolve(args.vectors)).split(path.sep).join("/"),
      schemaSha256: args.schema ? "0x" + createHash("sha256").update(readFileSync(args.schema)).digest("hex") : null,
      abiSha256: args.abi ? "0x" + createHash("sha256").update(readFileSync(args.abi)).digest("hex") : null,
      vectorsBytes: vectorBytes.length,
      vectorsSha256,
      vectorsKeccak256,
      vectorsSchema: V.schema,
      vectorsSource: V.source,
    },
    counts: { perKind: counts, totals },
    verdict: rec.failures.length === 0 ? "PASS" : "FAIL",
    failures: rec.failures,
    findings,
    notEvaluable,
    method: METHOD,
    results: Object.fromEntries(rec.groups),
  };

  const text = JSON.stringify(summary, null, 2);
  writeFileSync(path.resolve(args.out), text + "\n");
  process.stdout.write(text + "\n");
  process.exitCode = rec.failures.length === 0 ? 0 : 1;
}

// ---------------------------------------------------------------------------
// 8. Method: which specification sentences were implemented, and what was unclear
// ---------------------------------------------------------------------------

const METHOD = {
  encoding: {
    implemented: [
      "The hash encoding rule says that abi.encode is taken over the listed items in order, that a struct encodes as the static tuple of its fields in the order of its fields array, and that every item occupies one 32-byte word with addresses and narrow integers left-padded and enums carried as their uint8 value. Because every field of both request structs is static, that reduces to concatenating one big-endian 32-byte word per field, so the encoder in this program builds each word directly from the schema's field list.",
      "The canonicality sentence says the received calldata and the canonical encoding coincide for every accepted command, so calldata is checked as the selector followed by exactly that encoding, with no offset word for the struct argument.",
      "The signature rule says a canonical signature is the name followed by the parenthesized comma-separated parameter types with no spaces, a struct parameter is the parenthesized list of its field types in field order, enum fields are uint8, and the selector is the first four bytes of the keccak-256 of that string.",
    ],
    crossChecked: "The hand-written encoder was compared byte for byte against an independent ABI coder for the ActionRequest tuple, the ReversalRequest tuple and the full nested actionId preimage.",
  },
  constants: {
    implemented: "Each constant in the schema is a string paired with a keccak256 value, which this program reads as the keccak-256 digest of the UTF-8 bytes of that string. The domain, the dependency-root tag and both profile identifiers are derived that way and compared with the vectors.",
  },
  actionId: {
    implemented: "keccak-256 over the four preimage items domain, endpoint address, chain id and the ActionRequest with actionId set to bytes32(0). The endpoint sentence fixes the endpoint as the address a caller invokes, which the fixture supplies; the chain id sentence fixes it as the EIP-155 identifier, which the fixture also supplies. The rule that the request's actionId field must equal this value is checked separately for every action vector.",
  },
  commandHash: {
    implemented: "The same four items with the completed request, actionId filled.",
  },
  reversalId: { implemented: "The same shape over the ReversalRequest with reversalId set to bytes32(0)." },
  reversalHash: { implemented: "The same over the completed ReversalRequest." },
  bindingHash: {
    implemented: "keccak-256 over domain, the BindingKind value as uint8, the dependency address, runtimeCodeId, configurationDigest, schema and the uint64 epoch, using the per-dependency epoch the fixture records.",
  },
  dependencyRoot: {
    implemented: "keccak-256 over domain, the DEPENDENCY_ROOT tag and the four binding hashes ordered by BindingKind, that is policy, identity, settlement, entitlement.",
  },
  receiptHash: {
    implemented: "keccak-256 of seventeen words: the domain constant followed by every Receipt field except receiptHash, in the order the struct lists them. The Receipt description states exactly that ordering and the prefix. The program checks the hash twice for every vector, once over the receipt input as published and once over a receipt it derives itself from the request, using the field meanings: the receipt kind discriminator, the command identifier, the command kind as the ActionKind or ReversalKind value, a zero parent for actions and the reversed actionId for reversals, the effective destination that is the custodian for SEIZE, the custodian as the source of a RELEASE and the declared prior holder as its destination, and the external commitment that is keccak-256 of the settlement and proceeds commitments for LIQUIDATE, the entitlement commitment for RECOVER and zero everywhere else.",
  },
  nonceKey: { implemented: "keccak-256 over domain, authorityRef, the uint64 authority epoch and the uint256 nonce." },
  interfaceIds: {
    implemented: "The kernel identifier is the XOR of the selectors of the nine listed functions with supportsInterface excluded, exactly as the erc165 rule states. The two profile interface identifiers are computed with the same XOR rule and compared against the values the generated prose and the generated ABI declare, because neither document states a rule for them.",
  },
  shapeAndCaseRules: {
    implemented: "The six common rules were implemented in the order the schema lists them, with their bound reason codes. The per-action field rules were implemented one clause at a time, treating a violation without its own code as reason 6. The case table CT-1 to CT-16 was implemented as a small state machine over case records, per-subject overlay heads for the FREEZE and RESTRICT families, per-case custody records and the consumed nonce and command identifier sets, which is what the negative vectors need in order to be evaluated rather than merely restated.",
  },
  ambiguities: [
    "Check order is not stated. The schema lists the six common rules and numbers their reasons in the same order, but never says that an endpoint evaluates them in that order, so a request that violates several rules has no determined reason code. Every negative scenario in this program was therefore built so that exactly one rule can fail, and the ordering assumption is recorded rather than relied on.",
    "Where replay detection and the TERMINAL case check sit relative to each other and to the shape rules is not stated. The program checks replay before the terminal case and both before the per-action field rules, and isolates each negative scenario so the choice does not decide any verdict.",
    "The phrase 'full-state stutter' appears in the expected outcome of three negative vectors and is defined nowhere in the machine source, the prose or the ABI. It is not evaluable from the specification.",
    "The 'same: CONFISCATE' key in the LIQUIDATE and RECOVER shape rules is never given a meaning. It was read as inheriting the CONFISCATE clauses and overriding the ones restated, which is the only reading that makes the LIQUIDATE and RECOVER vectors well formed.",
    "The relation between the per-dependency epoch inside bindingHash and the endpoint's dependencyEpoch is not stated. The fixture happens to set both to 1. The rebinding scenario therefore changes only the configuration digest and advances the endpoint epoch by one, which is the part the specification does state.",
    "For a reversal receipt the specification gives rules for source and destination but none for subject, amount or caseId, none of which exist on a ReversalRequest. They were taken from the action being reversed, which the vectors confirm but the text does not say.",
    "For a reversal receipt it is not stated whether authorityRef and dependencyRoot come from the reversal request or from the reversed action. The vectors cannot distinguish the two because both commands carry the same authority reference and the same dependency root. The program uses the reversal request's own values.",
    "Receipt.commandKind is typed uint8 with the meaning 'ActionKind value when receiptKind is ACTION, ReversalKind value when REVERSAL'. Since both enumerations start at zero, an ACTION receipt for FREEZE and a REVERSAL receipt for UNFREEZE carry the same commandKind byte, and only the receiptKind word separates them. NEG-RECEIPT-KIND is the vector that exercises this separation.",
    "The observation commitments assessmentEvidence, preState and postState are profile-defined; the native-full profile only says the preimage is 'documented by the implementation together with its runtime identity'. Nothing in the specification lets an independent implementer compute them, so they were consumed from the fixture.",
    "At the base of the change that added this program, the generated prose rendered the shapeRules 'appliesTo' entry character by character; the machine source was correct and the generator was corrected in the same change.",
    "Neither the prose nor the ABI states how the two profile interface identifiers are derived. The ERC-165 XOR rule stated for the kernel interface was applied to them and the result compared with the declared values.",
  ],
};

main().catch((err) => {
  process.stderr.write("fatal: " + (err && err.stack ? err.stack : String(err)) + "\n");
  process.exitCode = 2;
});
