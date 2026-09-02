// SPDX-License-Identifier: BSD-3-Clause
//
// Generates every artifact that is derived from the normative kernel machine
// source (spec/erc-trust-kernel-v2.json):
//   spec/generated/IERCTrustKernel.sol   Solidity types and interfaces
//   spec/generated/kernel-v2-abi.json    JSON ABI, selectors, interface identifier
//   spec/generated/kernel-v2.md          human-readable rendering of the schema
//   sdk/src/kernel-v2.ts                 TypeScript types and hash helpers
//   vectors/conformance-v2.json          conformance vectors
//
// Usage:
//   node scripts/generate-normative-kernel.mjs            write the artifacts
//   node scripts/generate-normative-kernel.mjs --check    fail if any artifact differs
//   node scripts/generate-normative-kernel.mjs --print-ids  print computed constants
//
// The schema carries the literal domain, tag, profile, and interface identifiers.
// The generator recomputes every one of them and refuses to run when a literal
// disagrees with the recomputation, so the schema cannot silently drift from the
// values that implementations and indexers depend on.

import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  AbiCoder,
  Interface,
  ZeroAddress,
  ZeroHash,
  getAddress,
  id,
  keccak256,
} from "../sdk/node_modules/ethers/lib.esm/index.js";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const schemaPath = "spec/erc-trust-kernel-v2.json";
const schema = JSON.parse(readFileSync(resolve(root, schemaPath), "utf8"));
const checkMode = process.argv.includes("--check");
const printIds = process.argv.includes("--print-ids");
const coder = AbiCoder.defaultAbiCoder();
const failures = [];
const fail = (message) => failures.push(message);

// ---------------------------------------------------------------------------
// Identity recomputation
// ---------------------------------------------------------------------------

const computed = {
  domain: id(schema.domain.string),
  tags: Object.fromEntries(Object.entries(schema.tags).map(([name, tag]) => [name, id(tag.string)])),
  profiles: Object.fromEntries(
    Object.entries(schema.profiles).map(([name, profile]) => [name, id(profile.profileId.string)]),
  ),
};

function structFieldSolidityType(field) {
  return field.enum ? `TrustKernelTypes.${field.enum}` : field.type;
}

function canonicalType(param) {
  if (param.struct) {
    const fields = schema.structs[param.struct].fields;
    return `(${fields.map((field) => field.type).join(",")})`;
  }
  return param.type;
}

function tupleType(structName) {
  const fields = schema.structs[structName].fields;
  return `tuple(${fields.map((field) => `${field.type} ${field.name}`).join(",")})`;
}

function signature(fn) {
  return `${fn.name}(${fn.inputs.map(canonicalType).join(",")})`;
}

function selectorOf(fn) {
  return id(signature(fn)).slice(0, 10);
}

function interfaceIdOf(functions) {
  let acc = 0n;
  for (const fn of functions) acc ^= BigInt(selectorOf(fn));
  return `0x${acc.toString(16).padStart(8, "0")}`;
}

computed.selectors = Object.fromEntries(schema.interface.functions.map((fn) => [signature(fn), selectorOf(fn)]));
computed.interfaceId = interfaceIdOf(schema.interface.functions);
computed.profileInterfaceIds = Object.fromEntries(
  Object.entries(schema.profileInterfaces).map(([name, entry]) => [name, interfaceIdOf(entry.functions)]),
);

if (printIds) {
  console.log(JSON.stringify(computed, null, 2));
  process.exit(0);
}

if (schema.domain.keccak256 !== computed.domain) {
  fail(`domain literal ${schema.domain.keccak256} != keccak256("${schema.domain.string}") ${computed.domain}`);
}
for (const [name, tag] of Object.entries(schema.tags)) {
  if (tag.keccak256 !== computed.tags[name]) fail(`tag ${name} literal drift: ${tag.keccak256} != ${computed.tags[name]}`);
}
for (const [name, profile] of Object.entries(schema.profiles)) {
  if (profile.profileId.keccak256 !== computed.profiles[name]) {
    fail(`profile ${name} literal drift: ${profile.profileId.keccak256} != ${computed.profiles[name]}`);
  }
}
if (schema.interface.erc165.interfaceId !== computed.interfaceId) {
  fail(`interface identifier literal ${schema.interface.erc165.interfaceId} != computed ${computed.interfaceId}`);
}
for (const [enumName, entry] of Object.entries(schema.enums)) {
  const values = Object.values(entry.values);
  if (new Set(values).size !== values.length) fail(`enum ${enumName} has duplicate values`);
}
for (const [structName, entry] of Object.entries(schema.structs)) {
  for (const field of entry.fields) {
    if (field.enum && !schema.enums[field.enum]) fail(`struct ${structName}.${field.name} references unknown enum ${field.enum}`);
    if (field.enum && field.type !== "uint8") fail(`struct ${structName}.${field.name}: enum fields must be uint8`);
  }
}
const receiptFields = schema.structs.Receipt.fields.map((field) => field.name);
const receiptPreimage = schema.hashes.receiptHash.preimage;
const expectedReceiptPreimage = ["domain", ...receiptFields.slice(0, -1).map((name) => {
  const field = schema.structs.Receipt.fields.find((entry) => entry.name === name);
  return field.type === "uint8" ? `${name}(uint8)` : name;
})];
if (JSON.stringify(receiptPreimage) !== JSON.stringify(expectedReceiptPreimage)) {
  fail(`receipt preimage list must equal domain followed by every Receipt field except receiptHash; expected ${JSON.stringify(expectedReceiptPreimage)}`);
}
if (failures.length) {
  for (const failure of failures) console.error(failure);
  process.exit(1);
}

// ---------------------------------------------------------------------------
// Solidity rendering
// ---------------------------------------------------------------------------

function renderEnum(name, entry) {
  const ordered = Object.entries(entry.values).sort((a, b) => a[1] - b[1]);
  ordered.forEach(([, value], index) => {
    if (value !== index) fail(`enum ${name} values must be contiguous from zero`);
  });
  return `    /// @dev ${entry.description}\n    enum ${name} {\n${ordered.map(([member]) => `        ${member}`).join(",\n")}\n    }\n`;
}

function renderStruct(name, entry) {
  return `    /// @dev ${entry.description}\n    struct ${name} {\n${entry.fields
    .map((field) => `        ${structFieldSolidityType(field)} ${field.name};`)
    .join("\n")}\n    }\n`;
}

function renderParam(param, location) {
  if (param.struct) return `TrustKernelTypes.${param.struct} ${location} ${param.name}`;
  return `${param.type} ${param.name}`;
}

function renderFunction(fn) {
  const inputs = fn.inputs.map((param) => renderParam(param, "calldata")).join(", ");
  const outputs = fn.outputs.map((param) => renderParam(param, "memory")).join(", ");
  const mutability = fn.mutability === "nonpayable" ? "" : ` ${fn.mutability}`;
  return `    function ${fn.name}(${inputs}) external${mutability} returns (${outputs});`;
}

function renderEvent(event) {
  const inputs = event.inputs
    .map((param) => `${param.type}${param.indexed ? " indexed" : ""} ${param.name}`)
    .join(", ");
  return `    event ${event.name}(${inputs});`;
}

function renderError(error) {
  return `    error ${error.name}(${error.inputs.map((param) => `${param.type} ${param.name}`).join(", ")});`;
}

const enumNames = Object.keys(schema.enums);
const solidity = `// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

// GENERATED by scripts/generate-normative-kernel.mjs from ${schemaPath}. DO NOT EDIT.
// Kernel version ${schema.kernelVersion}. Interface identifier ${computed.interfaceId}.
// This file is the normative Solidity rendering of the kernel machine source. The
// implementation directory is wired to it in a later change; until then the
// implementation continues to expose kernel version 1.

/// @notice ERC-165 minimal interface, declared here so the generated file is self-contained.
interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

/// @notice Constants, enums, and structs shared by every ERC-TRUST kernel endpoint.
library TrustKernelTypes {
    /// @dev keccak256("${schema.domain.string}")
    bytes32 internal constant DOMAIN = ${computed.domain};
    uint8 internal constant STANDARD_VERSION = ${schema.domain.standardVersion};
    /// @dev keccak256("${schema.tags.DEPENDENCY_ROOT.string}")
    bytes32 internal constant DEPENDENCY_ROOT_TAG = ${computed.tags.DEPENDENCY_ROOT};
${Object.entries(schema.profiles)
  .map(([name, profile]) => `    /// @dev keccak256("${profile.profileId.string}")\n    bytes32 internal constant PROFILE_${name.toUpperCase().replace(/-/g, "_")} = ${computed.profiles[name]};`)
  .join("\n")}

${enumNames.map((name) => renderEnum(name, schema.enums[name])).join("\n")}
${Object.entries(schema.structs).map(([name, entry]) => renderStruct(name, entry)).join("\n")}}

/// @notice The kernel interface implemented by every conforming endpoint.
/// @dev ERC-165 identifier ${computed.interfaceId}: XOR of the selectors of every function below;
///      the inherited supportsInterface selector is excluded.
interface IERCTrustKernel is IERC165 {
${schema.interface.events.map(renderEvent).join("\n")}

${schema.interface.errors.map(renderError).join("\n")}

${schema.interface.functions.map(renderFunction).join("\n")}
}
${Object.entries(schema.profileInterfaces)
  .map(([name, entry]) => `
/// @notice ${entry.description}
/// @dev ERC-165 identifier ${computed.profileInterfaceIds[name]}.
interface ${name} {
${(entry.errors ?? []).map(renderError).join("\n")}${entry.errors?.length ? "\n\n" : ""}${entry.functions.map(renderFunction).join("\n")}
}`)
  .join("\n")}
`;

// ---------------------------------------------------------------------------
// ABI JSON rendering
// ---------------------------------------------------------------------------

function abiParam(param, indexed) {
  if (param.struct) {
    return {
      name: param.name,
      type: "tuple",
      internalType: `struct TrustKernelTypes.${param.struct}`,
      components: schema.structs[param.struct].fields.map((field) => ({
        name: field.name,
        type: field.type,
        internalType: field.enum ? `enum TrustKernelTypes.${field.enum}` : field.type,
      })),
      ...(indexed === undefined ? {} : { indexed }),
    };
  }
  return { name: param.name, type: param.type, internalType: param.type, ...(indexed === undefined ? {} : { indexed }) };
}

const abiJson = {
  schema: "erc-trust-kernel-abi",
  kernelVersion: schema.kernelVersion,
  source: schemaPath,
  domain: { string: schema.domain.string, keccak256: computed.domain },
  interfaceId: computed.interfaceId,
  interfaceIdRule: schema.interface.erc165.rule,
  selectors: computed.selectors,
  profileInterfaceIds: computed.profileInterfaceIds,
  calldataLengths: {
    ActionRequest: 4 + 32 * schema.structs.ActionRequest.fields.length,
    ReversalRequest: 4 + 32 * schema.structs.ReversalRequest.fields.length,
  },
  abi: [
    ...schema.interface.functions.map((fn) => ({
      type: "function",
      name: fn.name,
      stateMutability: fn.mutability,
      inputs: fn.inputs.map((param) => abiParam(param)),
      outputs: fn.outputs.map((param) => abiParam(param)),
    })),
    ...schema.interface.events.map((event) => ({
      type: "event",
      name: event.name,
      anonymous: false,
      inputs: event.inputs.map((param) => abiParam(param, param.indexed)),
    })),
    ...schema.interface.errors.map((error) => ({
      type: "error",
      name: error.name,
      inputs: error.inputs.map((param) => abiParam(param)),
    })),
  ],
};

// ---------------------------------------------------------------------------
// Markdown rendering
// ---------------------------------------------------------------------------

function table(headers, rows) {
  return [`| ${headers.join(" | ")} |`, `| ${headers.map(() => "---").join(" | ")} |`, ...rows.map((row) => `| ${row.join(" | ")} |`)].join("\n");
}

const markdown = `# ERC-TRUST kernel version ${schema.kernelVersion}

GENERATED by \`scripts/generate-normative-kernel.mjs\` from \`${schemaPath}\`. Do not edit; edit the schema and regenerate.

Status: ${schema.status.stage}. Assurance: ${schema.status.assurance}.

## Constants

${table(["Constant", "String", "keccak256"], [
  ["DOMAIN", `\`${schema.domain.string}\``, `\`${computed.domain}\``],
  ["DEPENDENCY_ROOT_TAG", `\`${schema.tags.DEPENDENCY_ROOT.string}\``, `\`${computed.tags.DEPENDENCY_ROOT}\``],
  ...Object.entries(schema.profiles).map(([name, profile]) => [`profile ${name}`, `\`${profile.profileId.string}\``, `\`${computed.profiles[name]}\``]),
])}

Standard version: ${schema.domain.standardVersion}. Kernel interface identifier: \`${computed.interfaceId}\`.

## Enums

${enumNames.map((name) => `### ${name}\n\n${schema.enums[name].description}\n\n${table(["Member", "Value"], Object.entries(schema.enums[name].values).sort((a, b) => a[1] - b[1]).map(([member, value]) => [`\`${member}\``, String(value)]))}`).join("\n\n")}

## Structs

${Object.entries(schema.structs).map(([name, entry]) => `### ${name}\n\n${entry.description}\n\n${table(["#", "Field", "Type", "Meaning"], entry.fields.map((field, index) => [String(index), `\`${field.name}\``, `\`${field.enum ? `uint8 (${field.enum})` : field.type}\``, field.meaning ?? ""]))}`).join("\n\n")}

## Hash preimages

Encoding: ${schema.hashes.encoding.rule}. ${schema.hashes.encoding.canonicality}

${Object.entries(schema.hashes).filter(([name]) => name !== "encoding").map(([name, entry]) => `### ${name}\n\n${entry.profile ? `Profile: ${entry.profile}.\n\n` : ""}Preimage, in order:\n\n${entry.preimage.map((item, index) => `${index + 1}. \`${item}\``).join("\n")}\n\n${entry.rule}`).join("\n\n")}

## Interface \`${schema.interface.name}\`

${schema.interface.erc165.rule}

${table(["Function", "Selector", "Mutability"], schema.interface.functions.map((fn) => [`\`${signature(fn)}\``, `\`${selectorOf(fn)}\``, fn.mutability]))}

Events:

${schema.interface.events.map((event) => `- \`${event.name}(${event.inputs.map((param) => `${param.type}${param.indexed ? " indexed" : ""} ${param.name}`).join(", ")})\``).join("\n")}

Errors:

${schema.interface.errors.map((error) => `- \`${error.name}(${error.inputs.map((param) => `${param.type} ${param.name}`).join(", ")})\`${error.meaning ? `: ${error.meaning}` : ""}`).join("\n")}

Event order: ${schema.interface.eventOrder}

## Profile interfaces

${Object.entries(schema.profileInterfaces).map(([name, entry]) => `### ${name}\n\n${entry.description}\n\nIdentifier \`${computed.profileInterfaceIds[name]}\`.\n\n${table(["Function", "Selector"], entry.functions.map((fn) => [`\`${signature(fn)}\``, `\`${selectorOf(fn)}\``]))}${entry.operationEncoding ? `\n\n${entry.operationEncoding}.` : ""}`).join("\n\n")}

## Shape rules

Common: ${schema.shapeRules.common.map((rule) => `\`${rule}\``).join("; ")}.

${table(["Action", "Rule"], Object.entries(schema.shapeRules).filter(([name]) => name !== "common").map(([name, rules]) => [`\`${name}\``, Object.entries(rules).map(([field, rule]) => `${field}: ${rule}`).join("; ")]))}

## Case transitions

${schema.caseTransitions.description}

${table(["Family", "Opening commands", "Overlay", "Reversal", "Dispositions"], Object.entries(schema.caseTransitions.families).map(([name, family]) => [`\`${name}\``, family.opening.join(", "), String(family.overlay), family.reversal ?? "none", (family.dispositions ?? []).join(", ") || "none"]))}

${table(["Rule", "From", "Command", "Guard", "To", "Effect or reason"], schema.caseTransitions.rules.map((rule) => [rule.id, rule.from, rule.command, rule.guard ?? "", rule.to, rule.effect ?? (rule.reason !== undefined ? `reason ${rule.reason}` : rule.error ?? "")]))}

Cross-case notes:

${schema.caseTransitions.crossCase.map((note) => `- ${note}`).join("\n")}

## Reason classes

${schema.reasonClasses.description}

${table(["Class", "Range", "Error", "Codes"], Object.entries(schema.reasonClasses.classes).map(([name, entry]) => [name, `${entry.range[0]} to ${entry.range[1]}`, `\`${entry.error}\``, Object.entries(entry.codes).map(([code, label]) => `${code} ${label}`).join(", ")]))}

## Profiles

${Object.entries(schema.profiles).map(([name, profile]) => `### ${name}\n\n${table(["Property", "Value"], Object.entries(profile).filter(([key]) => key !== "profileId").map(([key, value]) => [key, typeof value === "string" ? value : JSON.stringify(value)]))}`).join("\n\n")}

## Nonclaims

${schema.nonclaims.map((claim) => `- ${claim}`).join("\n")}
`;

// ---------------------------------------------------------------------------
// TypeScript rendering
// ---------------------------------------------------------------------------

function tsType(field) {
  if (field.type === "address" || field.type.startsWith("bytes")) return "string";
  if (field.type === "bool") return "boolean";
  if (field.enum) return field.enum;
  return "bigint";
}

function renderTsEnum(name, entry) {
  const ordered = Object.entries(entry.values).sort((a, b) => a[1] - b[1]);
  return `export enum ${name} {\n${ordered.map(([member, value]) => `  ${member} = ${value},`).join("\n")}\n}\n`;
}

function renderTsInterface(name, entry) {
  return `export interface ${name} {\n${entry.fields.map((field) => `  ${field.name}: ${tsType(field)};`).join("\n")}\n}\n`;
}

const receiptInputFields = schema.structs.Receipt.fields.filter((field) => field.name !== "receiptHash");
const addressFieldsOf = (structName) => schema.structs[structName].fields.filter((field) => field.type === "address").map((field) => field.name);

const typescript = `// SPDX-License-Identifier: BSD-3-Clause
// GENERATED by scripts/generate-normative-kernel.mjs from ${schemaPath}. DO NOT EDIT.
// Kernel version ${schema.kernelVersion}. Deterministic, side-effect-free helpers for the
// ERC-TRUST kernel wire format. The helpers do not sign, submit, decide authority,
// or validate a deployment.

import { AbiCoder, Interface, ZeroHash, getAddress, id, keccak256 } from "ethers";

export const KERNEL_VERSION = ${schema.kernelVersion};
export const KERNEL_DOMAIN = "${computed.domain}";
export const DEPENDENCY_ROOT_TAG = "${computed.tags.DEPENDENCY_ROOT}";
export const KERNEL_INTERFACE_ID = "${computed.interfaceId}";
export const PROFILE_IDS = {
${Object.entries(schema.profiles).map(([name]) => `  "${name}": "${computed.profiles[name]}",`).join("\n")}
} as const;
export const KERNEL_SELECTORS = {
${schema.interface.functions.map((fn) => `  ${fn.name}: "${selectorOf(fn)}",`).join("\n")}
} as const;

${enumNames.map((name) => renderTsEnum(name, schema.enums[name])).join("\n")}
${["ActionRequest", "ReversalRequest", "CaseRecord", "ProfileDescriptor"].map((name) => renderTsInterface(name, schema.structs[name])).join("\n")}
/** Every receipt field except receiptHash, in preimage order. */
export interface ReceiptInput {
${receiptInputFields.map((field) => `  ${field.name}: ${tsType(field)};`).join("\n")}
}

export const ACTION_TUPLE = "${tupleType("ActionRequest")}";
export const REVERSAL_TUPLE = "${tupleType("ReversalRequest")}";
export const RECEIPT_PREIMAGE_TYPES = ${JSON.stringify(["bytes32", ...receiptInputFields.map((field) => field.type)])} as const;

const coder = AbiCoder.defaultAbiCoder();
const kernelInterface = new Interface([
  \`function executeRegulatoryAction(\${ACTION_TUPLE} request) returns (bytes32)\`,
  \`function executeRegulatoryReversal(\${REVERSAL_TUPLE} request) returns (bytes32)\`,
]);

export function normalizeActionRequest(request: ActionRequest): ActionRequest {
  return {
    ...request,
${addressFieldsOf("ActionRequest").map((name) => `    ${name}: getAddress(request.${name}),`).join("\n")}
  };
}

function encodeCommand(tuple: string, endpoint: string, chainId: bigint, request: object): string {
  return keccak256(coder.encode(["bytes32", "address", "uint256", tuple], [KERNEL_DOMAIN, getAddress(endpoint), chainId, request]));
}

/** hashes.actionId: the request with actionId zeroed, bound to the endpoint and chain. */
export function deriveActionId(endpoint: string, chainId: bigint, request: ActionRequest): string {
  return encodeCommand(ACTION_TUPLE, endpoint, chainId, normalizeActionRequest({ ...request, actionId: ZeroHash }));
}

/** hashes.commandHash: the completed request including its actionId. */
export function commandHash(endpoint: string, chainId: bigint, request: ActionRequest): string {
  return encodeCommand(ACTION_TUPLE, endpoint, chainId, normalizeActionRequest(request));
}

/** hashes.reversalId: the request with reversalId zeroed, bound to the endpoint and chain. */
export function deriveReversalId(endpoint: string, chainId: bigint, request: ReversalRequest): string {
  return encodeCommand(REVERSAL_TUPLE, endpoint, chainId, { ...request, reversalId: ZeroHash });
}

/** hashes.reversalHash: the completed reversal request including its reversalId. */
export function reversalHash(endpoint: string, chainId: bigint, request: ReversalRequest): string {
  return encodeCommand(REVERSAL_TUPLE, endpoint, chainId, request);
}

/** hashes.bindingHash of the native profile. */
export function bindingHash(
  kind: BindingKind,
  dependency: string,
  runtimeCodeId: string,
  configurationDigest: string,
  schema: string,
  epoch: bigint,
): string {
  return keccak256(
    coder.encode(
      ["bytes32", "uint8", "address", "bytes32", "bytes32", "bytes32", "uint64"],
      [KERNEL_DOMAIN, kind, getAddress(dependency), runtimeCodeId, configurationDigest, schema, epoch],
    ),
  );
}

/** hashes.dependencyRoot over the four per-kind bindings in BindingKind order. */
export function dependencyRoot(policy: string, identity: string, settlement: string, entitlement: string): string {
  return keccak256(
    coder.encode(
      ["bytes32", "bytes32", "bytes32", "bytes32", "bytes32", "bytes32"],
      [KERNEL_DOMAIN, DEPENDENCY_ROOT_TAG, policy, identity, settlement, entitlement],
    ),
  );
}

/** hashes.nonceKey reported by TrustReplay. */
export function nonceKey(authorityRef: string, authorityEpoch: bigint, nonce: bigint): string {
  return keccak256(coder.encode(["bytes32", "bytes32", "uint64", "uint256"], [KERNEL_DOMAIN, authorityRef, authorityEpoch, nonce]));
}

/** The action-specific external commitment bound by an ACTION receipt. */
export function externalCommitmentFor(request: ActionRequest): string {
  if (request.action === ActionKind.LIQUIDATE) {
    return keccak256(coder.encode(["bytes32", "bytes32"], [request.settlementCommitment, request.proceedsCommitment]));
  }
  if (request.action === ActionKind.RECOVER) return request.entitlementCommitment;
  return ZeroHash;
}

/** hashes.receiptHash over the domain and every receipt field except receiptHash. */
export function receiptHash(input: ReceiptInput): string {
  return keccak256(
    coder.encode(
      [...RECEIPT_PREIMAGE_TYPES],
      [
        KERNEL_DOMAIN,
${receiptInputFields.map((field) => `        ${field.type === "address" ? `getAddress(input.${field.name})` : `input.${field.name}`},`).join("\n")}
      ],
    ),
  );
}

export function encodeAction(request: ActionRequest): string {
  return kernelInterface.encodeFunctionData("executeRegulatoryAction", [normalizeActionRequest(request)]);
}

export function encodeReversal(request: ReversalRequest): string {
  return kernelInterface.encodeFunctionData("executeRegulatoryReversal", [request]);
}

export function kernelSelector(signature: string): string {
  return id(signature).slice(0, 10);
}
`;

// ---------------------------------------------------------------------------
// Vectors
// ---------------------------------------------------------------------------

const fixture = {
  endpoint: "0x1111111111111111111111111111111111111111",
  chainId: 1n,
  subject: "0x2222222222222222222222222222222222222222",
  custodian: "0x3333333333333333333333333333333333333333",
  buyer: "0x4444444444444444444444444444444444444444",
  recovered: "0x5555555555555555555555555555555555555555",
  provenance: `0x${"66".repeat(32)}`,
  authorityRef: `0x${"77".repeat(32)}`,
  preState: `0x${"88".repeat(32)}`,
  postState: `0x${"99".repeat(32)}`,
  assessmentEvidence: `0x${"aa".repeat(32)}`,
  dependencies: {
    policy: { dependency: "0x000000000000000000000000000000000000a001", runtimeCodeId: `0x${"b1".repeat(32)}`, configurationDigest: `0x${"c1".repeat(32)}`, schema: `0x${"d1".repeat(32)}`, epoch: 1n },
    identity: { dependency: "0x000000000000000000000000000000000000a002", runtimeCodeId: `0x${"b2".repeat(32)}`, configurationDigest: `0x${"c2".repeat(32)}`, schema: `0x${"d1".repeat(32)}`, epoch: 1n },
    settlement: { dependency: "0x000000000000000000000000000000000000a003", runtimeCodeId: `0x${"b3".repeat(32)}`, configurationDigest: `0x${"c3".repeat(32)}`, schema: `0x${"d1".repeat(32)}`, epoch: 1n },
    entitlement: { dependency: "0x000000000000000000000000000000000000a004", runtimeCodeId: `0x${"b4".repeat(32)}`, configurationDigest: `0x${"c4".repeat(32)}`, schema: `0x${"d1".repeat(32)}`, epoch: 1n },
  },
};

const kinds = schema.enums.BindingKind.values;
const bindingHashJs = (kind, entry) =>
  keccak256(coder.encode(
    ["bytes32", "uint8", "address", "bytes32", "bytes32", "bytes32", "uint64"],
    [computed.domain, kind, getAddress(entry.dependency), entry.runtimeCodeId, entry.configurationDigest, entry.schema, entry.epoch],
  ));
const bindings = {
  policy: bindingHashJs(kinds.POLICY, fixture.dependencies.policy),
  identity: bindingHashJs(kinds.IDENTITY, fixture.dependencies.identity),
  settlement: bindingHashJs(kinds.SETTLEMENT, fixture.dependencies.settlement),
  entitlement: bindingHashJs(kinds.ENTITLEMENT, fixture.dependencies.entitlement),
};
const dependencyRootValue = keccak256(coder.encode(
  ["bytes32", "bytes32", "bytes32", "bytes32", "bytes32", "bytes32"],
  [computed.domain, computed.tags.DEPENDENCY_ROOT, bindings.policy, bindings.identity, bindings.settlement, bindings.entitlement],
));
const dependencyEpoch = 1n;
const actionTuple = tupleType("ActionRequest");
const reversalTuple = tupleType("ReversalRequest");
const kernelInterface = new Interface([
  `function executeRegulatoryAction(${actionTuple} request) returns (bytes32)`,
  `function executeRegulatoryReversal(${reversalTuple} request) returns (bytes32)`,
]);
const encodeCommandJs = (tuple, request) =>
  keccak256(coder.encode(["bytes32", "address", "uint256", tuple], [computed.domain, fixture.endpoint, fixture.chainId, request]));
const stringify = (value) => {
  if (typeof value === "bigint") return value.toString();
  if (Array.isArray(value)) return value.map(stringify);
  if (value !== null && typeof value === "object") return Object.fromEntries(Object.entries(value).map(([key, entry]) => [key, stringify(entry)]));
  return value;
};

const actionKinds = schema.enums.ActionKind.values;
const reversalKinds = schema.enums.ReversalKind.values;
const validBefore = 281474976710655n;

function baseRequest(action, nonce) {
  return {
    domain: computed.domain,
    actionId: ZeroHash,
    action,
    subject: fixture.subject,
    source: fixture.subject,
    destination: ZeroAddress,
    custodian: ZeroAddress,
    amount: 0n,
    caseId: keccak256(coder.encode(["string", "uint256"], ["case", nonce])),
    dependencyRoot: dependencyRootValue,
    dependencyEpoch,
    provenanceCommitment: fixture.provenance,
    settlementCommitment: ZeroHash,
    proceedsCommitment: ZeroHash,
    entitlementCommitment: ZeroHash,
    authorityRef: fixture.authorityRef,
    authorityEpoch: 1n,
    nonce,
    validAfter: 0n,
    validBefore,
  };
}

const actionFixtures = [
  { name: "FREEZE", build: (r) => ({ ...r, amount: 123n }) },
  { name: "SEIZE", build: (r) => ({ ...r, destination: fixture.custodian, custodian: fixture.custodian, amount: 500n }) },
  { name: "CONFISCATE", build: (r) => ({ ...r, destination: fixture.buyer, amount: 700n }) },
  { name: "LIQUIDATE", build: (r) => ({ ...r, destination: fixture.buyer, amount: 800n, settlementCommitment: `0x${"e1".repeat(32)}`, proceedsCommitment: `0x${"e2".repeat(32)}` }) },
  { name: "RESTRICT", build: (r) => ({ ...r, amount: 0n }) },
  { name: "RECOVER", build: (r) => ({ ...r, destination: fixture.recovered, amount: 900n, entitlementCommitment: `0x${"e3".repeat(32)}` }) },
];

const actionVectors = actionFixtures.map((entry, index) => {
  const nonce = BigInt(index + 1);
  const unsigned = entry.build(baseRequest(actionKinds[entry.name], nonce));
  const actionId = encodeCommandJs(actionTuple, { ...unsigned, actionId: ZeroHash });
  const request = { ...unsigned, actionId };
  const effectiveDestination = entry.name === "SEIZE" ? request.custodian : request.destination;
  const externalCommitment = entry.name === "LIQUIDATE"
    ? keccak256(coder.encode(["bytes32", "bytes32"], [request.settlementCommitment, request.proceedsCommitment]))
    : entry.name === "RECOVER" ? request.entitlementCommitment : ZeroHash;
  const receiptInput = {
    receiptKind: schema.enums.ReceiptKind.values.ACTION,
    commandId: actionId,
    commandKind: request.action,
    parentCommandId: ZeroHash,
    subject: request.subject,
    source: request.source,
    destination: effectiveDestination,
    amount: request.amount,
    caseId: request.caseId,
    authorityRef: request.authorityRef,
    dependencyRoot: request.dependencyRoot,
    provenanceCommitment: request.provenanceCommitment,
    assessmentEvidence: fixture.assessmentEvidence,
    preState: fixture.preState,
    postState: fixture.postState,
    externalCommitment,
  };
  const receiptHashValue = keccak256(coder.encode(
    ["bytes32", ...receiptInputFields.map((field) => field.type)],
    [computed.domain, ...receiptInputFields.map((field) => receiptInput[field.name])],
  ));
  return {
    id: `ACTION-${entry.name}`,
    action: entry.name,
    request: stringify(request),
    actionId,
    commandHash: encodeCommandJs(actionTuple, request),
    calldata: kernelInterface.encodeFunctionData("executeRegulatoryAction", [request]),
    receiptInput: stringify(receiptInput),
    receiptHash: receiptHashValue,
  };
});

const reversalFixtures = [
  { name: "UNFREEZE", of: "FREEZE", source: fixture.subject, destination: fixture.subject },
  { name: "RELEASE", of: "SEIZE", source: fixture.custodian, destination: fixture.subject },
  { name: "UNRESTRICT", of: "RESTRICT", source: fixture.subject, destination: fixture.subject },
];

const reversalVectors = reversalFixtures.map((entry, index) => {
  const original = actionVectors.find((vector) => vector.action === entry.of);
  const nonce = BigInt(100 + index);
  const unsigned = {
    domain: computed.domain,
    reversalId: ZeroHash,
    actionId: original.actionId,
    reversal: reversalKinds[entry.name],
    dependencyRoot: dependencyRootValue,
    dependencyEpoch,
    provenanceCommitment: `0x${"6f".repeat(32)}`,
    authorityRef: fixture.authorityRef,
    authorityEpoch: 1n,
    nonce,
    validAfter: 0n,
    validBefore,
  };
  const reversalId = encodeCommandJs(reversalTuple, { ...unsigned, reversalId: ZeroHash });
  const request = { ...unsigned, reversalId };
  const receiptInput = {
    receiptKind: schema.enums.ReceiptKind.values.REVERSAL,
    commandId: reversalId,
    commandKind: request.reversal,
    parentCommandId: original.actionId,
    subject: fixture.subject,
    source: entry.source,
    destination: entry.destination,
    amount: BigInt(original.request.amount),
    caseId: original.request.caseId,
    authorityRef: request.authorityRef,
    dependencyRoot: request.dependencyRoot,
    provenanceCommitment: request.provenanceCommitment,
    assessmentEvidence: fixture.assessmentEvidence,
    preState: fixture.preState,
    postState: fixture.postState,
    externalCommitment: ZeroHash,
  };
  const receiptHashValue = keccak256(coder.encode(
    ["bytes32", ...receiptInputFields.map((field) => field.type)],
    [computed.domain, ...receiptInputFields.map((field) => receiptInput[field.name])],
  ));
  return {
    id: `REVERSAL-${entry.name}`,
    reversal: entry.name,
    reverses: original.id,
    request: stringify(request),
    reversalId,
    reversalHash: encodeCommandJs(reversalTuple, request),
    calldata: kernelInterface.encodeFunctionData("executeRegulatoryReversal", [request]),
    receiptInput: stringify(receiptInput),
    receiptHash: receiptHashValue,
  };
});

const freezeVector = actionVectors[0];
const freezeRequest = { ...freezeVector.request, amount: BigInt(freezeVector.request.amount), dependencyEpoch, authorityEpoch: 1n, nonce: 1n, validAfter: 0n, validBefore, action: actionKinds.FREEZE };
const mutatedIds = [
  ["subject", { ...freezeRequest, subject: fixture.buyer }],
  ["amount", { ...freezeRequest, amount: 124n }],
  ["caseId", { ...freezeRequest, caseId: `0x${"01".repeat(32)}` }],
  ["dependencyRoot", { ...freezeRequest, dependencyRoot: `0x${"02".repeat(32)}` }],
  ["dependencyEpoch", { ...freezeRequest, dependencyEpoch: 2n }],
  ["provenanceCommitment", { ...freezeRequest, provenanceCommitment: `0x${"03".repeat(32)}` }],
  ["authorityRef", { ...freezeRequest, authorityRef: `0x${"04".repeat(32)}` }],
  ["authorityEpoch", { ...freezeRequest, authorityEpoch: 2n }],
  ["nonce", { ...freezeRequest, nonce: 2n }],
  ["validAfter", { ...freezeRequest, validAfter: 1n }],
  ["validBefore", { ...freezeRequest, validBefore: validBefore - 1n }],
].map(([field, request]) => ({
  field,
  derivedActionId: encodeCommandJs(actionTuple, { ...request, actionId: ZeroHash }),
}));

const vectors = {
  schema: "erc-trust-conformance-vectors-v2",
  kernelVersion: schema.kernelVersion,
  candidateStatus: schema.status.assurance,
  source: schemaPath,
  constants: {
    domain: computed.domain,
    dependencyRootTag: computed.tags.DEPENDENCY_ROOT,
    kernelInterfaceId: computed.interfaceId,
    selectors: computed.selectors,
    profileIds: computed.profiles,
    actionCalldataLength: abiJson.calldataLengths.ActionRequest,
    reversalCalldataLength: abiJson.calldataLengths.ReversalRequest,
  },
  fixture: stringify({
    endpoint: fixture.endpoint,
    chainId: fixture.chainId,
    dependencies: fixture.dependencies,
    bindingHashes: bindings,
    dependencyRoot: dependencyRootValue,
    dependencyEpoch,
    nonceKeyExample: {
      authorityRef: fixture.authorityRef,
      authorityEpoch: 1n,
      nonce: 1n,
      nonceKey: keccak256(coder.encode(["bytes32", "bytes32", "uint64", "uint256"], [computed.domain, fixture.authorityRef, 1n, 1n])),
    },
    observationNote: "preState, postState, and assessmentEvidence are opaque fixture values in these vectors; their preimages are profile-defined and documented by each implementation.",
  }),
  actions: actionVectors,
  reversals: reversalVectors,
  negative: [
    {
      id: "NEG-WRONG-DOMAIN",
      mutation: "request.domain is not the kernel domain",
      expected: "TrustInvalidCommand reason 1",
    },
    {
      id: "NEG-FIELD-BINDING",
      mutation: "change one request field after deriving actionId",
      expected: "TrustInvalidCommand reason 2; every mutation below yields a different derived actionId",
      mutatedDerivedActionIds: mutatedIds,
    },
    {
      id: "NEG-STALE-DEPENDENCY",
      mutation: "any of the four dependencies is rebound after the request was built",
      expected: "TrustInvalidCommand reason 5 because dependencyRoot and dependencyEpoch no longer match",
    },
    {
      id: "NEG-CASE-CONFLICT",
      mutation: "FREEZE or RESTRICT while the subject's live head belongs to a different open case; or a disposition against an open overlay case",
      expected: "TrustInvalidCommand reason 10 and full-state stutter",
    },
    {
      id: "NEG-TERMINAL",
      mutation: "any action or reversal against a TERMINAL case",
      expected: "TrustTerminal(caseId) and full-state stutter",
    },
    {
      id: "NEG-REPLAY",
      mutation: "submit an applied command again, or reuse its nonce under the same authority epoch",
      expected: "TrustReplay and full-state stutter",
    },
    {
      id: "NEG-RECEIPT-KIND",
      mutation: "recompute a REVERSAL receipt with receiptKind ACTION",
      expected: "different receiptHash; receipt kinds are domain separated",
      example: {
        reversalReceiptHash: reversalVectors[0].receiptHash,
        sameFieldsWithActionKind: keccak256(coder.encode(
          ["bytes32", ...receiptInputFields.map((field) => field.type)],
          [computed.domain, ...receiptInputFields.map((field) => field.name === "receiptKind" ? schema.enums.ReceiptKind.values.ACTION : reversalVectors[0].receiptInput[field.name])],
        )),
      },
    },
  ],
};

// ---------------------------------------------------------------------------
// Emit or check
// ---------------------------------------------------------------------------

const outputs = [
  ["spec/generated/IERCTrustKernel.sol", solidity],
  ["spec/generated/kernel-v2-abi.json", `${JSON.stringify(abiJson, null, 2)}\n`],
  ["spec/generated/kernel-v2.md", markdown],
  ["sdk/src/kernel-v2.ts", typescript],
  ["vectors/conformance-v2.json", `${JSON.stringify(vectors, null, 2)}\n`],
];

if (failures.length) {
  for (const failure of failures) console.error(failure);
  process.exit(1);
}

if (checkMode) {
  for (const [path, text] of outputs) {
    const absolute = resolve(root, path);
    if (!existsSync(absolute)) {
      fail(`missing generated artifact: ${path}`);
      continue;
    }
    if (readFileSync(absolute, "utf8").replace(/\r\n?/g, "\n") !== text) fail(`generated artifact drift: ${path}`);
  }
  if (failures.length) {
    for (const failure of failures) console.error(failure);
    process.exit(1);
  }
  console.log(`normative kernel generation PASS: ${outputs.length} artifacts match ${schemaPath} (interface ${computed.interfaceId})`);
} else {
  for (const [path, text] of outputs) {
    mkdirSync(dirname(resolve(root, path)), { recursive: true });
    writeFileSync(resolve(root, path), text, "utf8");
  }
  console.log(`normative kernel generated: ${outputs.map(([path]) => path).join(", ")} (interface ${computed.interfaceId})`);
}
