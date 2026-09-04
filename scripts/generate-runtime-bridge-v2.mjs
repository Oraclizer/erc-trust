// SPDX-License-Identifier: BSD-3-Clause
//
// Generates the shared runtime bridge of the kernel version 2 endpoints from
// the compiled Foundry artifacts, the normative kernel ABI, and the kernel
// machine source:
//   evidence/end-to-end-refinement/runtime-bridge-v2/schema.json
//   evidence/end-to-end-refinement/runtime-bridge-v2/generated-manifest.json
//   formal/isabelle/ERC_TRUST/TRUST_Runtime_Bridge_Generated.thy
//   formal/kevm/generated/trust-runtime-bridge.k
//
// The bridge binds, for the native token, the profile adapter, and the
// profile governor: the exact runtime template (sha256 and length), every
// selector the compiler emitted and the route class each one belongs to, the
// storage layout labels and slots, the typed error selectors and event
// topics, and the fixed-width guard positions of the two typed commands. It
// is a generated shared boundary: it binds identities, it does not itself
// prove a transition.
//
// Usage:
//   node scripts/generate-runtime-bridge-v2.mjs            write the artifacts (after forge build)
//   node scripts/generate-runtime-bridge-v2.mjs --check    fail if any artifact differs

import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { id } from "../sdk/node_modules/ethers/lib.esm/index.js";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const checkMode = process.argv.includes("--check");
const outputs = {
  schema: "evidence/end-to-end-refinement/runtime-bridge-v2/schema.json",
  manifest: "evidence/end-to-end-refinement/runtime-bridge-v2/generated-manifest.json",
  isabelle: "formal/isabelle/ERC_TRUST/TRUST_Runtime_Bridge_Generated.thy",
  k: "formal/kevm/generated/trust-runtime-bridge.k",
};
const kernelSchemaPath = "spec/erc-trust-kernel-v2.json";
const kernelAbiPath = "spec/generated/kernel-v2-abi.json";

const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const readJson = (path) => JSON.parse(readFileSync(resolve(root, path), "utf8"));
const check = (condition, message) => {
  if (!condition) throw new Error(message);
};
const stable = (value) => {
  if (Array.isArray(value)) return value.map(stable);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stable(value[key])]));
  }
  return value;
};
const text = (value) => `${JSON.stringify(stable(value), null, 2)}\n`;

// ---------------------------------------------------------------------------
// Subjects and route classification
// ---------------------------------------------------------------------------

const subjects = [
  {
    id: "native",
    contract: "TrustToken",
    source: "implementation/src/TrustToken.sol",
    artifact: "out/TrustToken.sol/TrustToken.json",
    isabellePrefix: "native",
    kMacro: "#trustNativeRuntime",
    routes: {
      Route_Kernel_Command: ["executeRegulatoryAction", "executeRegulatoryReversal"],
      Route_Kernel_View: [
        "deriveActionId", "deriveReversalId", "actionRecord", "receipt", "caseRecord",
        "dependencyState", "trustProfile", "supportsInterface",
      ],
      Route_Native_Exact_Use: ["executeERC7943Action", "executeERC7943Reversal"],
      Route_ERC7943_Sensitive: ["setFrozenTokens", "forcedTransfer"],
      Route_ERC7943_View: ["canSend", "canReceive", "getFrozenTokens", "canTransfer"],
      Route_ERC20_Mutator: ["transfer", "transferFrom", "approve"],
      Route_ERC20_View: ["balanceOf", "totalSupply", "allowance", "name", "symbol", "decimals"],
      Route_Governance: ["configureAuthority", "rebindDependency"],
      Route_Immutable_View: ["governor"],
    },
  },
  {
    id: "profileAdapter",
    contract: "ERC3643TrustAdapter",
    source: "implementation/src/profiles/ERC3643TrustAdapter.sol",
    artifact: "out/ERC3643TrustAdapter.sol/ERC3643TrustAdapter.json",
    isabellePrefix: "profile_adapter",
    kMacro: "#trustAdapterRuntime",
    routes: {
      Route_Kernel_Command: ["executeRegulatoryAction", "executeRegulatoryReversal"],
      Route_Kernel_View: [
        "deriveActionId", "deriveReversalId", "actionRecord", "receipt", "caseRecord",
        "dependencyState", "trustProfile", "supportsInterface",
      ],
      Route_Profile_Command: ["resynchroniseFrozen"],
      Route_Profile_View: ["ownedState", "sealedTopologyLive"],
      Route_Seal_Command: ["activateSeal"],
      Route_Immutable_View: ["token", "profileGovernor", "authority", "authorityRef"],
    },
  },
  {
    id: "profileGovernor",
    contract: "ProfileGovernor",
    source: "implementation/src/profiles/ProfileGovernor.sol",
    artifact: "out/ProfileGovernor.sol/ProfileGovernor.json",
    isabellePrefix: "profile_governor",
    kMacro: "#trustGovernorRuntime",
    routes: {
      Route_Seal_Command: ["seal"],
      Route_Seal_View: [
        "manifestHashOf", "sealedTopologyLive", "exclusiveAdapter", "sealedBinding", "importManifestHash",
        "topologySealed",
      ],
      Route_Immutable_View: [
        "token", "identityRegistry", "compliance", "bootstrapAuthority", "expectedTokenCodeId",
      ],
    },
  },
];
const routeClassNames = [
  "Route_Kernel_Command", "Route_Kernel_View", "Route_Native_Exact_Use", "Route_ERC7943_Sensitive",
  "Route_ERC7943_View", "Route_ERC20_Mutator", "Route_ERC20_View", "Route_Governance",
  "Route_Immutable_View", "Route_Profile_Command", "Route_Profile_View", "Route_Seal_Command",
  "Route_Seal_View",
];
const kernelErrorNames = [
  "TrustRejected", "TrustOperationalFailure", "TrustUnauthorized", "TrustReplay",
  "TrustInvalidCommand", "TrustTerminal",
];
const kernelEventNames = [
  "RegulatoryActionApplied", "RegulatoryReversalApplied", "TrustDependencyChanged",
  "TrustAuthorityChanged",
];
const guardWidths = { address: 160, uint64: 64, uint48: 48 };

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function canonicalType(input) {
  if (input.type.startsWith("tuple")) {
    return `(${input.components.map(canonicalType).join(",")})${input.type.slice("tuple".length)}`;
  }
  return input.type;
}

function canonicalSignature(entry) {
  return `${entry.name}(${entry.inputs.map(canonicalType).join(",")})`;
}

function selectorOf(signature) {
  return id(signature).slice(0, 10);
}

function decimal(hex) {
  check(/^0x[0-9a-f]{8}$/.test(hex), `invalid selector ${hex}`);
  return Number.parseInt(hex.slice(2), 16);
}

function isabelleString(value) {
  check(/^[A-Za-z0-9_./:()\-,+@= ]*$/.test(value), `unsafe Isabelle string: ${value}`);
  return `''${value}''`;
}

function loadArtifact(subject) {
  const path = resolve(root, subject.artifact);
  check(existsSync(path), `missing compiled artifact ${subject.artifact}; run forge build first`);
  const bytes = readFileSync(path);
  const artifact = JSON.parse(bytes.toString("utf8"));
  check(artifact.deployedBytecode?.object?.startsWith("0x"), `artifact without runtime: ${subject.artifact}`);
  check(Array.isArray(artifact.storageLayout?.storage), `artifact without storage layout: ${subject.artifact}`);
  check(artifact.methodIdentifiers && typeof artifact.methodIdentifiers === "object", `artifact without method identifiers: ${subject.artifact}`);
  // The artifact identity hashes the compiler outputs that the bridge consumes (ABI, creation
  // and runtime bytecode, compiler metadata, storage layout without AST node identifiers,
  // method identifiers), not the whole artifact file: AST node identifiers depend on every
  // other file of the compilation and on the order in which the compiler visited them, so
  // they differ between hosts and drift when an unrelated test changes.
  const artifactSha256 = sha256(Buffer.from(JSON.stringify({
    abi: artifact.abi,
    bytecode: artifact.bytecode?.object ?? null,
    deployedBytecode: artifact.deployedBytecode.object,
    rawMetadata: artifact.rawMetadata ?? null,
    storageLayout: artifact.storageLayout.storage.map((entry) => ({ contract: entry.contract, label: entry.label, offset: entry.offset, slot: entry.slot, type: entry.type })),
    methodIdentifiers: artifact.methodIdentifiers,
  }), "utf8"));
  return { artifact, artifactSha256 };
}

function runtimeIdentity(artifact) {
  const hex = artifact.deployedBytecode.object.slice(2).toLowerCase();
  check(/^[0-9a-f]*$/.test(hex) && hex.length % 2 === 0, "runtime hex");
  const bytes = Buffer.from(hex, "hex");
  return { hex, bytes: bytes.length, sha256: sha256(bytes) };
}

function functionInventory(subject, artifact) {
  const functions = artifact.abi.filter((entry) => entry.type === "function");
  const byName = new Map();
  for (const entry of functions) {
    const signature = canonicalSignature(entry);
    const selector = selectorOf(signature);
    const compiled = artifact.methodIdentifiers[signature];
    check(compiled !== undefined, `compiler emitted no identifier for ${signature}`);
    check(`0x${compiled}` === selector, `selector mismatch for ${signature}: ${compiled} vs ${selector}`);
    check(!byName.has(entry.name), `overloaded function is outside the bridge: ${entry.name}`);
    byName.set(entry.name, { name: entry.name, signature, selector, decimal: decimal(selector), stateMutability: entry.stateMutability });
  }
  const compiledSignatures = Object.keys(artifact.methodIdentifiers).sort();
  const derivedSignatures = [...byName.values()].map((fn) => fn.signature).sort();
  check(JSON.stringify(compiledSignatures) === JSON.stringify(derivedSignatures),
    `method identifier set drift for ${subject.contract}`);
  const classified = new Map();
  for (const [routeClass, names] of Object.entries(subject.routes)) {
    check(routeClassNames.includes(routeClass), `unknown route class ${routeClass}`);
    for (const name of names) {
      const fn = byName.get(name);
      check(fn !== undefined, `${subject.contract}: classified function absent from the ABI: ${name}`);
      check(!classified.has(name), `${subject.contract}: function classified twice: ${name}`);
      classified.set(name, routeClass);
    }
  }
  for (const name of byName.keys()) {
    check(classified.has(name), `${subject.contract}: unclassified public function: ${name}`);
  }
  const routes = [...byName.values()]
    .map((fn) => ({ ...fn, routeClass: classified.get(fn.name) }))
    .sort((left, right) => left.decimal - right.decimal);
  check(new Set(routes.map((route) => route.decimal)).size === routes.length, `selector collision in ${subject.contract}`);
  return routes;
}

function storageInventory(subject, artifact) {
  return artifact.storageLayout.storage.map((entry) => ({
    projectionId: `${subject.isabellePrefix.replace(/_/g, ".")}.${entry.label.replace(/^_/, "")}`,
    label: entry.label,
    slot: Number(entry.slot),
    offset: entry.offset,
    typeId: entry.type,
    typeLabel: artifact.storageLayout.types[entry.type]?.label ?? null,
  }));
}

function errorSelectors(artifact, names) {
  return names.map((name) => {
    const entry = artifact.abi.find((candidate) => candidate.type === "error" && candidate.name === name);
    check(entry !== undefined, `error absent from the ABI: ${name}`);
    const signature = canonicalSignature(entry);
    const selector = selectorOf(signature);
    return { name, signature, selector, decimal: decimal(selector) };
  });
}

function eventTopics(artifact, names) {
  return names.map((name) => {
    const entry = artifact.abi.find((candidate) => candidate.type === "event" && candidate.name === name);
    check(entry !== undefined, `event absent from the ABI: ${name}`);
    const signature = canonicalSignature(entry);
    return { name, signature, topic0: id(signature), indexed: entry.inputs.map((input) => Boolean(input.indexed)) };
  });
}

function guardPositions(kernelSchema, kernelAbi, functionName, structName) {
  const entry = kernelAbi.abi.find((candidate) => candidate.type === "function" && candidate.name === functionName);
  check(entry && entry.inputs.length === 1 && entry.inputs[0].type === "tuple", `typed entrypoint missing in kernel ABI: ${functionName}`);
  const components = entry.inputs[0].components;
  const fields = kernelSchema.structs[structName].fields;
  check(components.length === fields.length, `kernel ABI and schema disagree on ${structName}`);
  const guards = { enum: [], address: [], uint64: [], uint48: [] };
  components.forEach((component, index) => {
    const field = fields[index];
    check(component.name === field.name && component.type === field.type, `${structName}.${field.name} drift`);
    if (field.enum) {
      guards.enum.push([index, Object.keys(kernelSchema.enums[field.enum].values).length]);
    } else if (guardWidths[component.type] !== undefined) {
      guards[component.type].push(index);
    } else {
      check(["bytes32", "uint256"].includes(component.type), `unsupported static field type ${component.type}`);
    }
  });
  return { wordCount: components.length, calldataLength: 4 + 32 * components.length, guards };
}

// ---------------------------------------------------------------------------
// Build the schema
// ---------------------------------------------------------------------------

const kernelSchema = readJson(kernelSchemaPath);
const kernelAbi = readJson(kernelAbiPath);
check(kernelSchema.kernelVersion === 2 && kernelAbi.kernelVersion === 2, "kernel version");
const loaded = subjects.map((subject) => {
  const { artifact, artifactSha256 } = loadArtifact(subject);
  return {
    subject,
    artifactSha256,
    runtime: runtimeIdentity(artifact),
    routes: functionInventory(subject, artifact),
    storage: storageInventory(subject, artifact),
    artifact,
  };
});
const native = loaded.find((entry) => entry.subject.id === "native");
const adapter = loaded.find((entry) => entry.subject.id === "profileAdapter");
const governor = loaded.find((entry) => entry.subject.id === "profileGovernor");

const actionGuards = guardPositions(kernelSchema, kernelAbi, "executeRegulatoryAction", "ActionRequest");
const reversalGuards = guardPositions(kernelSchema, kernelAbi, "executeRegulatoryReversal", "ReversalRequest");
check(actionGuards.calldataLength === kernelAbi.calldataLengths.ActionRequest, "action calldata length drift");
check(reversalGuards.calldataLength === kernelAbi.calldataLengths.ReversalRequest, "reversal calldata length drift");

const nativeRoute = (name) => native.routes.find((route) => route.name === name);
const adapterRoute = (name) => adapter.routes.find((route) => route.name === name);
for (const name of ["executeRegulatoryAction", "executeRegulatoryReversal", "deriveActionId", "deriveReversalId",
  "actionRecord", "receipt", "caseRecord", "dependencyState", "trustProfile"]) {
  const expected = kernelAbi.selectors[nativeRoute(name).signature];
  check(expected === nativeRoute(name).selector, `native ${name} selector differs from the kernel ABI`);
  check(adapterRoute(name).selector === nativeRoute(name).selector, `adapter ${name} selector differs from native`);
}
const kernelSelectors = Object.fromEntries(Object.entries(kernelAbi.selectors).map(([signature, selector]) => [signature.split("(")[0], selector]));
const erc3643PartialInterfaceId = `0x${(
  BigInt(adapterRoute("ownedState").selector)
  ^ BigInt(adapterRoute("resynchroniseFrozen").selector)
  ^ BigInt(adapterRoute("sealedTopologyLive").selector)
).toString(16).padStart(8, "0")}`;
const nativeErrors = errorSelectors(native.artifact, kernelErrorNames);
const adapterErrors = errorSelectors(adapter.artifact, kernelErrorNames);
check(JSON.stringify(nativeErrors) === JSON.stringify(adapterErrors), "kernel error selectors differ between endpoints");
const nativeEvents = eventTopics(native.artifact, kernelEventNames);
const routeMismatch = errorSelectors(native.artifact, ["TrustRouteMismatch"])[0];
const genericDispatcherInputSelector = { hex: "0xffffffff", decimal: 4294967295 };
for (const entry of loaded) {
  check(!entry.routes.some((route) => route.decimal === genericDispatcherInputSelector.decimal), "generic dispatcher selector aliases a function");
}

const reasonCodes = Object.values(kernelSchema.reasonClasses.classes)
  .flatMap((cls) => Object.entries(cls.codes).map(([code, name]) => ({ code: Number(code), name, error: cls.error })))
  .sort((left, right) => left.code - right.code);
const caseTransitionRuleIds = kernelSchema.caseTransitions.rules.map((rule) => rule.id);
const actionCodes = Object.entries(kernelSchema.enums.ActionKind.values).map(([name, ordinal]) => ({
  abstract: `Legal_${name[0]}${name.slice(1).toLowerCase()}`, solidity: name, ordinal,
}));
const reversalCodes = Object.entries(kernelSchema.enums.ReversalKind.values).map(([name, ordinal]) => ({
  abstract: `TRUST_${name}`, solidity: name, ordinal,
}));

const schema = {
  schemaVersion: 2,
  kind: "ERC_TRUST_RUNTIME_BRIDGE_V2",
  kernelVersion: 2,
  claimBoundary:
    "Generated shared boundary only. It binds compiled runtime templates, selectors and their route classes, storage layouts, typed error selectors, event topics, and the fixed-width guard positions of the typed commands; it does not itself prove a transition, compiler correctness, or deployment identity.",
  sourceBinding: {
    kernelSchema: { path: kernelSchemaPath, sha256: sha256(readFileSync(resolve(root, kernelSchemaPath))) },
    kernelAbi: { path: kernelAbiPath, sha256: sha256(readFileSync(resolve(root, kernelAbiPath))) },
    artifactHashing: "sha256 of the JSON of {abi, bytecode.object, deployedBytecode.object, rawMetadata, storageLayout.storage without astId, methodIdentifiers} of the forge artifact",
    artifacts: loaded.map((entry) => ({ subject: entry.subject.id, contract: entry.subject.contract, source: entry.subject.source, path: entry.subject.artifact, sha256: entry.artifactSha256 })),
  },
  interfaceIds: {
    kernel: kernelAbi.interfaceId,
    nativeRoute: kernelAbi.profileInterfaceIds.IERCTrustNativeRoute,
    boundDependency: kernelAbi.profileInterfaceIds.ITrustBoundDependency,
    erc3643Partial: erc3643PartialInterfaceId,
  },
  commands: {
    action: { ...actionGuards, selector: kernelSelectors.executeRegulatoryAction, nativeRouteSelector: nativeRoute("executeERC7943Action").selector },
    reversal: { ...reversalGuards, selector: kernelSelectors.executeRegulatoryReversal, nativeRouteSelector: nativeRoute("executeERC7943Reversal").selector },
  },
  kernelSelectors,
  typedFailureSelectors: nativeErrors,
  routeMismatchSelector: routeMismatch,
  genericDispatcherInputSelector,
  kernelEvents: nativeEvents,
  actionCodes,
  reversalCodes,
  reasonCodes,
  caseTransitionRuleIds,
  eip170RuntimeLimit: 24576,
  subjects: Object.fromEntries(loaded.map((entry) => [entry.subject.id, {
    contract: entry.subject.contract,
    source: entry.subject.source,
    runtime: { bytes: entry.runtime.bytes, sha256: entry.runtime.sha256 },
    routes: entry.routes,
    storage: entry.storage,
  }])),
};

// ---------------------------------------------------------------------------
// Render the Isabelle bridge theory
// ---------------------------------------------------------------------------

const schemaText = text(schema);
const schemaHash = sha256(Buffer.from(schemaText, "utf8"));

function renderRoutes(prefix, routes) {
  const pairs = routes.map((route) => `(${route.decimal}, ${route.routeClass})`).join(",\n     ");
  const ids = routes.map((route) => `${route.decimal}`).join(", ");
  return `definition ${prefix}_routes :: "(nat \\<times> trust_route_class) list" where
  "${prefix}_routes =
    [${pairs}]"

definition ${prefix}_method_identifiers :: "nat list" where
  "${prefix}_method_identifiers = [${ids}]"
`;
}

function renderStorage(prefix, storage) {
  const pairs = storage.map((entry) => `(${isabelleString(entry.projectionId)}, ${entry.slot})`).join(",\n     ");
  return `definition ${prefix}_storage_slots :: "(string \\<times> nat) list" where
  "${prefix}_storage_slots =
    [${pairs}]"
`;
}

function renderNatList(name, values) {
  return `definition ${name} :: "nat list" where "${name} = [${values.join(", ")}]"`;
}

function renderPairList(name, values) {
  return `definition ${name} :: "(nat \\<times> nat) list" where "${name} = [${values.map(([a, b]) => `(${a}, ${b})`).join(", ")}]"`;
}

const errorConstant = (name) => `trust_${name.replace(/^Trust/, "").replace(/([a-z])([A-Z])/g, "$1_$2").toLowerCase()}_selector`;
const isabelle = `(* GENERATED by scripts/generate-runtime-bridge-v2.mjs. DO NOT EDIT. *)
theory TRUST_Runtime_Bridge_Generated
  imports TRUST_Concrete_Configuration
begin

definition runtime_bridge_schema_sha256 :: string where
  "runtime_bridge_schema_sha256 = ${isabelleString(schemaHash)}"

definition native_runtime_template_sha256 :: string where
  "native_runtime_template_sha256 = ${isabelleString(native.runtime.sha256)}"
definition native_runtime_bytes :: nat where "native_runtime_bytes = ${native.runtime.bytes}"
definition profile_adapter_runtime_sha256 :: string where
  "profile_adapter_runtime_sha256 = ${isabelleString(adapter.runtime.sha256)}"
definition profile_adapter_runtime_bytes :: nat where "profile_adapter_runtime_bytes = ${adapter.runtime.bytes}"
definition profile_governor_runtime_sha256 :: string where
  "profile_governor_runtime_sha256 = ${isabelleString(governor.runtime.sha256)}"
definition profile_governor_runtime_bytes :: nat where "profile_governor_runtime_bytes = ${governor.runtime.bytes}"
definition eip170_runtime_limit :: nat where "eip170_runtime_limit = ${schema.eip170RuntimeLimit}"

definition kernel_interface_id :: nat where "kernel_interface_id = ${decimal(schema.interfaceIds.kernel)}"
definition native_route_interface_id :: nat where "native_route_interface_id = ${decimal(schema.interfaceIds.nativeRoute)}"
definition erc3643_partial_interface_id :: nat where "erc3643_partial_interface_id = ${decimal(schema.interfaceIds.erc3643Partial)}"

definition action_calldata_length :: nat where "action_calldata_length = ${actionGuards.calldataLength}"
definition reversal_calldata_length :: nat where "reversal_calldata_length = ${reversalGuards.calldataLength}"
definition action_word_count :: nat where "action_word_count = ${actionGuards.wordCount}"
definition reversal_word_count :: nat where "reversal_word_count = ${reversalGuards.wordCount}"
${renderPairList("action_enum_words", actionGuards.guards.enum)}
${renderNatList("action_address_words", actionGuards.guards.address)}
${renderNatList("action_uint64_words", actionGuards.guards.uint64)}
${renderNatList("action_uint48_words", actionGuards.guards.uint48)}
${renderPairList("reversal_enum_words", reversalGuards.guards.enum)}
${renderNatList("reversal_address_words", reversalGuards.guards.address)}
${renderNatList("reversal_uint64_words", reversalGuards.guards.uint64)}
${renderNatList("reversal_uint48_words", reversalGuards.guards.uint48)}

definition action_entrypoint_selector :: nat where
  "action_entrypoint_selector = ${decimal(schema.commands.action.selector)}"
definition reversal_entrypoint_selector :: nat where
  "reversal_entrypoint_selector = ${decimal(schema.commands.reversal.selector)}"
definition native_route_action_selector :: nat where
  "native_route_action_selector = ${decimal(schema.commands.action.nativeRouteSelector)}"
definition native_route_reversal_selector :: nat where
  "native_route_reversal_selector = ${decimal(schema.commands.reversal.nativeRouteSelector)}"
${nativeErrors.map((entry) => `definition ${errorConstant(entry.name)} :: nat where
  "${errorConstant(entry.name)} = ${entry.decimal}"`).join("\n")}
definition trust_route_mismatch_selector :: nat where
  "trust_route_mismatch_selector = ${routeMismatch.decimal}"
definition generic_dispatcher_input_selector :: nat where
  "generic_dispatcher_input_selector = ${genericDispatcherInputSelector.decimal}"
definition typed_command_entrypoint_selectors :: "nat set" where
  "typed_command_entrypoint_selectors =
    {action_entrypoint_selector, reversal_entrypoint_selector,
     native_route_action_selector, native_route_reversal_selector}"
definition typed_failure_selectors :: "nat set" where
  "typed_failure_selectors =
    {${nativeErrors.map((entry) => errorConstant(entry.name)).join(", ")}}"

fun solidity_action_code :: "legal_action_kind \\<Rightarrow> nat" where
${actionCodes.map((entry, index) => `${index === 0 ? "  " : "| "}"solidity_action_code ${entry.abstract} = ${entry.ordinal}"`).join("\n")}

fun solidity_reversal_code :: "trust_reversal_kind \\<Rightarrow> nat" where
${reversalCodes.map((entry, index) => `${index === 0 ? "  " : "| "}"solidity_reversal_code ${entry.abstract} = ${entry.ordinal}"`).join("\n")}

datatype trust_route_class =
    ${routeClassNames.join("\n  | ")}

${renderRoutes("native", native.routes)}
${renderRoutes("profile_adapter", adapter.routes)}
${renderRoutes("profile_governor", governor.routes)}
${renderStorage("native", native.storage)}
${renderStorage("profile_adapter", adapter.storage)}
${renderStorage("profile_governor", governor.storage)}
definition reason_code_registry :: "(nat \\<times> string) list" where
  "reason_code_registry =
    [${reasonCodes.map((entry) => `(${entry.code}, ${isabelleString(entry.name)})`).join(",\n     ")}]"

definition case_transition_rule_ids :: "string list" where
  "case_transition_rule_ids =
    [${caseTransitionRuleIds.map(isabelleString).join(", ")}]"

theorem action_code_is_exact:
  "set (map solidity_action_code
    [${actionCodes.map((entry) => entry.abstract).join(", ")}]) = {${actionCodes.map((entry) => entry.ordinal).join(", ")}}"
  by simp

theorem reversal_code_is_exact:
  "set (map solidity_reversal_code
    [${reversalCodes.map((entry) => entry.abstract).join(", ")}]) = {${reversalCodes.map((entry) => entry.ordinal).join(", ")}}"
  by simp

theorem generated_calldata_lengths_are_exact:
  "action_calldata_length = 4 + 32 * action_word_count \\<and>
   reversal_calldata_length = 4 + 32 * reversal_word_count"
  by (simp add: action_calldata_length_def action_word_count_def
      reversal_calldata_length_def reversal_word_count_def)

theorem runtimes_are_within_the_eip170_limit:
  "native_runtime_bytes \\<le> eip170_runtime_limit \\<and>
   profile_adapter_runtime_bytes \\<le> eip170_runtime_limit \\<and>
   profile_governor_runtime_bytes \\<le> eip170_runtime_limit"
  by (simp add: native_runtime_bytes_def profile_adapter_runtime_bytes_def
      profile_governor_runtime_bytes_def eip170_runtime_limit_def)

theorem native_routes_are_exhaustive:
  "map fst native_routes = native_method_identifiers \\<and> distinct native_method_identifiers"
  by (simp add: native_routes_def native_method_identifiers_def)

theorem profile_adapter_routes_are_exhaustive:
  "map fst profile_adapter_routes = profile_adapter_method_identifiers \\<and>
   distinct profile_adapter_method_identifiers"
  by (simp add: profile_adapter_routes_def profile_adapter_method_identifiers_def)

theorem profile_governor_routes_are_exhaustive:
  "map fst profile_governor_routes = profile_governor_method_identifiers \\<and>
   distinct profile_governor_method_identifiers"
  by (simp add: profile_governor_routes_def profile_governor_method_identifiers_def)

theorem typed_command_selectors_are_classified_as_kernel_commands:
  "(action_entrypoint_selector, Route_Kernel_Command) \\<in> set native_routes \\<and>
   (reversal_entrypoint_selector, Route_Kernel_Command) \\<in> set native_routes \\<and>
   (native_route_action_selector, Route_Native_Exact_Use) \\<in> set native_routes \\<and>
   (native_route_reversal_selector, Route_Native_Exact_Use) \\<in> set native_routes \\<and>
   (action_entrypoint_selector, Route_Kernel_Command) \\<in> set profile_adapter_routes \\<and>
   (reversal_entrypoint_selector, Route_Kernel_Command) \\<in> set profile_adapter_routes"
  by (simp add: native_routes_def profile_adapter_routes_def action_entrypoint_selector_def
      reversal_entrypoint_selector_def native_route_action_selector_def
      native_route_reversal_selector_def)

theorem generic_dispatcher_selector_is_unclassified:
  "generic_dispatcher_input_selector \\<notin> set native_method_identifiers \\<and>
   generic_dispatcher_input_selector \\<notin> set profile_adapter_method_identifiers \\<and>
   generic_dispatcher_input_selector \\<notin> set profile_governor_method_identifiers"
  by (simp add: generic_dispatcher_input_selector_def native_method_identifiers_def
      profile_adapter_method_identifiers_def profile_governor_method_identifiers_def)

theorem typed_command_selectors_are_not_failure_selectors:
  "typed_command_entrypoint_selectors \\<inter> typed_failure_selectors = {}"
  by (simp add: typed_command_entrypoint_selectors_def typed_failure_selectors_def
      action_entrypoint_selector_def reversal_entrypoint_selector_def
      native_route_action_selector_def native_route_reversal_selector_def
      ${nativeErrors.map((entry) => `${errorConstant(entry.name)}_def`).join(" ")})

theorem reason_codes_are_distinct:
  "distinct (map fst reason_code_registry)"
  by (simp add: reason_code_registry_def)

theorem case_transition_rule_ids_are_distinct:
  "distinct case_transition_rule_ids"
  by (simp add: case_transition_rule_ids_def)

end
`;

// ---------------------------------------------------------------------------
// Render the K bridge module
// ---------------------------------------------------------------------------

const k = `// GENERATED by scripts/generate-runtime-bridge-v2.mjs. DO NOT EDIT.
requires "edsl.md"

module TRUST-RUNTIME-BRIDGE
    imports EDSL

    syntax String ::= "#trustBridgeSchemaSha256" [macro]
    rule #trustBridgeSchemaSha256 => "${schemaHash}"

    syntax Int ::= "#trustActionCalldataLength" [macro]
    rule #trustActionCalldataLength => ${actionGuards.calldataLength}
    syntax Int ::= "#trustReversalCalldataLength" [macro]
    rule #trustReversalCalldataLength => ${reversalGuards.calldataLength}

    // Checked selector constants are mirrored as non-executable metadata so
    // this bridge remains claim-compatible with the exact pinned definition.
    // selector constant #trustActionEntrypointSelector => ${decimal(schema.commands.action.selector)}
    // selector constant #trustReversalEntrypointSelector => ${decimal(schema.commands.reversal.selector)}
    // selector constant #trustNativeRouteActionSelector => ${decimal(schema.commands.action.nativeRouteSelector)}
    // selector constant #trustNativeRouteReversalSelector => ${decimal(schema.commands.reversal.nativeRouteSelector)}
    // selector constant #trustGenericDispatcherInputSelector => ${genericDispatcherInputSelector.decimal}
${nativeErrors.map((entry) => `    // selector constant #trust${entry.name.replace(/^Trust/, "")}Selector => ${entry.decimal}`).join("\n")}

${loaded.map((entry) => `    syntax Bytes ::= "${entry.subject.kMacro}" "(" ")" [macro]
    rule ${entry.subject.kMacro}() => #parseByteStack("0x${entry.runtime.hex}")`).join("\n\n")}
endmodule
`;

// ---------------------------------------------------------------------------
// Emit or check
// ---------------------------------------------------------------------------

const generatedFiles = [
  { path: outputs.isabelle, content: isabelle },
  { path: outputs.k, content: k },
];
const manifest = {
  schemaVersion: 2,
  kind: "ERC_TRUST_RUNTIME_BRIDGE_MANIFEST_V2",
  schema: { path: outputs.schema, sha256: schemaHash, bytes: Buffer.byteLength(schemaText, "utf8") },
  generated: generatedFiles.map((entry) => ({ path: entry.path, sha256: sha256(Buffer.from(entry.content, "utf8")), bytes: Buffer.byteLength(entry.content, "utf8") })),
  runtimes: Object.fromEntries(loaded.map((entry) => [entry.subject.id, entry.runtime.sha256])),
};
manifest.deterministicRootSha256 = sha256(Buffer.from([
  `${manifest.schema.path}\0${manifest.schema.sha256}\n`,
  ...manifest.generated.map((entry) => `${entry.path}\0${entry.sha256}\n`),
].join(""), "utf8"));
const rendered = [
  { path: outputs.schema, content: schemaText },
  ...generatedFiles,
  { path: outputs.manifest, content: text(manifest) },
];

if (checkMode) {
  const drift = rendered.filter((entry) => {
    const path = resolve(root, entry.path);
    return !existsSync(path) || readFileSync(path, "utf8").replace(/\r\n?/g, "\n") !== entry.content;
  });
  if (drift.length) {
    for (const entry of drift) console.error(`runtime bridge drift: ${entry.path}`);
    process.exit(1);
  }
  console.log(`runtime bridge check PASS: ${rendered.length} artifacts match the compiled runtimes (native ${native.runtime.bytes} bytes ${native.runtime.sha256.slice(0, 12)})`);
} else {
  for (const entry of rendered) {
    mkdirSync(dirname(resolve(root, entry.path)), { recursive: true });
    writeFileSync(resolve(root, entry.path), entry.content, "utf8");
  }
  console.log(JSON.stringify({
    status: "PASS",
    schemaSha256: schemaHash,
    generatedRootSha256: manifest.deterministicRootSha256,
    runtimes: manifest.runtimes,
    routes: Object.fromEntries(loaded.map((entry) => [entry.subject.id, entry.routes.length])),
  }, null, 2));
}
