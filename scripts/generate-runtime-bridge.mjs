import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const bindingRoot = join(repositoryRoot, "evidence", "end-to-end-refinement", "runtime-binding");
const bridgeRoot = join(repositoryRoot, "evidence", "end-to-end-refinement", "runtime-bridge");
const isabellePath = join(repositoryRoot, "formal", "isabelle", "ERC_TRUST", "TRUST_Runtime_Bridge_Generated.thy");
const kPath = join(repositoryRoot, "formal", "kevm", "generated", "trust-runtime-bridge.k");
const bindingManifestPath = join(bindingRoot, "manifest.json");
const fixturePath = join(bindingRoot, "resolved", "fixture.json");
const obligationIndexPath = join(repositoryRoot, "evidence", "end-to-end-refinement", "obligation-evidence-index.json");
const fail05EvidencePath = join(
  repositoryRoot,
  "evidence",
  "end-to-end-refinement",
  "kevm",
  "fail-05-generic-dispatcher-revert-20260802T174934Z",
  "evidence.json",
);
const fail05SpecPath = join(
  repositoryRoot,
  "formal",
  "kevm",
  "specs",
  "full-transaction-generic-dispatcher-revert-spec.k",
);
const bindingManifest = JSON.parse(readFileSync(bindingManifestPath, "utf8"));
const fixture = JSON.parse(readFileSync(fixturePath, "utf8"));
const obligationIndex = JSON.parse(readFileSync(obligationIndexPath, "utf8"));
const fail05Evidence = JSON.parse(readFileSync(fail05EvidencePath, "utf8"));

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function stable(value) {
  if (Array.isArray(value)) return value.map(stable);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stable(value[key])]));
  }
  return value;
}

function stableJson(value) {
  return `${JSON.stringify(stable(value), null, 2)}\n`;
}

function writeJson(path, value) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, stableJson(value), "utf8");
}

function repoPath(path) {
  return relative(repositoryRoot, path).split(sep).join("/");
}

function castKeccak(value) {
  const output = execFileSync("wsl.exe", ["-d", "Ubuntu", "-e", "cast", "keccak"], {
    input: value,
    encoding: "utf8",
    stdio: ["pipe", "pipe", "pipe"],
  }).trim();
  if (!/^0x[0-9a-f]{64}$/.test(output)) throw new Error(`bad Keccak output: ${output}`);
  return output;
}

function canonicalType(input) {
  if (input.type !== "tuple") return input.type;
  return `(${input.components.map(canonicalType).join(",")})`;
}

function canonicalSignature(entry) {
  return `${entry.name}(${entry.inputs.map(canonicalType).join(",")})`;
}

function selector(signature) {
  return castKeccak(signature).slice(0, 10);
}

function selectorDecimal(hex) {
  if (!/^0x[0-9a-f]{8}$/.test(hex)) throw new Error(`invalid selector: ${hex}`);
  return Number.parseInt(hex.slice(2), 16);
}

function staticWords(input) {
  if (input.type === "tuple") return input.components.reduce((sum, component) => sum + staticWords(component), 0);
  if (input.type.endsWith("[]") || input.type === "bytes" || input.type === "string") {
    throw new Error(`dynamic ABI input is outside the TRUST command bridge: ${input.type}`);
  }
  return 1;
}

function bundleBridge(bundleId) {
  return JSON.parse(readFileSync(join(bindingRoot, bundleId, "bridge-artifacts.json"), "utf8"));
}

const nativeArtifacts = bundleBridge("native");
const profileArtifacts = bundleBridge("verified-profile");
const native = nativeArtifacts.find((entry) => entry.contract === "TrustToken");
const adapter = profileArtifacts.find((entry) => entry.contract === "ERC3643TrustAdapter");
const governor = profileArtifacts.find((entry) => entry.contract === "ProfileGovernor");
const token = profileArtifacts.find((entry) => entry.contract === "MockERC3643Token");
if (!native || !adapter || !governor || !token) throw new Error("required bridge subject missing");

function abiInventory(artifact) {
  return artifact.abi.map((entry) => {
    if (!["function", "event", "error"].includes(entry.type)) return null;
    const signature = canonicalSignature(entry);
    if (entry.type === "event") {
      return {
        kind: "event",
        name: entry.name,
        signature,
        topic0: entry.anonymous ? null : castKeccak(signature),
        anonymous: Boolean(entry.anonymous),
        indexed: entry.inputs.map((input) => Boolean(input.indexed)),
      };
    }
    return {
      kind: entry.type,
      name: entry.name,
      signature,
      selector: selector(signature),
    };
  }).filter(Boolean).sort((left, right) => `${left.kind}:${left.signature}`.localeCompare(`${right.kind}:${right.signature}`));
}

function commandEntrypoint(artifact, name) {
  const entry = artifact.abi.find((candidate) => candidate.type === "function" && candidate.name === name);
  if (!entry || entry.inputs.length !== 1 || entry.inputs[0].type !== "tuple") {
    throw new Error(`typed command entrypoint missing: ${name}`);
  }
  const signature = canonicalSignature(entry);
  const calldataLength = 4 + 32 * staticWords(entry.inputs[0]);
  const compilerSelector = artifact.methodIdentifiers[signature];
  const derivedSelector = selector(signature).slice(2);
  if (compilerSelector !== derivedSelector) throw new Error(`selector mismatch: ${signature}`);
  return {
    name,
    signature,
    selector: `0x${compilerSelector}`,
    tupleComponents: entry.inputs[0].components.map((component, ordinal) => ({
      ordinal,
      name: component.name,
      type: component.type,
      internalType: component.internalType,
    })),
    calldataLength,
  };
}

function storageInventory(artifact, profile) {
  return artifact.storageLayout.storage.map((entry) => ({
    projectionId: `${profile}.${entry.label.replace(/^_/, "")}`,
    label: entry.label,
    slot: Number(entry.slot),
    offset: entry.offset,
    typeId: entry.type,
    type: artifact.storageLayout.types[entry.type],
  }));
}

function resolved(label) {
  const deployment = fixture.deployments.find((entry) => entry.label === label);
  if (!deployment) throw new Error(`resolved deployment missing: ${label}`);
  return {
    label,
    address: deployment.address,
    runtimePath: deployment.runtime.path,
    byteLength: deployment.runtime.byteLength,
    sha256: deployment.runtime.sha256,
    keccak256: deployment.runtime.keccak256,
    immutableDeclarations: deployment.immutablePatch.declarations.map((entry) => ({
      astId: entry.astId,
      sourcePath: entry.sourcePath,
      name: entry.name,
      canonicalType: entry.canonicalType,
      locations: entry.locations,
      encodedWord: entry.encodedWord,
    })),
  };
}

const nativeAction = commandEntrypoint(native, "executeRegulatoryAction");
const nativeReversal = commandEntrypoint(native, "executeRegulatoryReversal");
const profileAction = commandEntrypoint(adapter, "executeRegulatoryAction");
const profileReversal = commandEntrypoint(adapter, "executeRegulatoryReversal");
if (nativeAction.calldataLength !== 676 || profileAction.calldataLength !== 676) throw new Error("action calldata length drift");
if (nativeReversal.calldataLength !== 292 || profileReversal.calldataLength !== 292) throw new Error("reversal calldata length drift");
const nativeAbi = abiInventory(native);
const typedFailureNames = ["TrustOperationalFailure", "TrustRejected"];
const typedFailureSelectors = typedFailureNames.map((name) => {
  const error = nativeAbi.find((entry) => entry.kind === "error" && entry.name === name);
  if (!error) throw new Error(`typed failure ABI entry missing: ${name}`);
  return { name: error.name, signature: error.signature, selector: error.selector, decimal: selectorDecimal(error.selector) };
});
const selectorBridgeEvidence = fail05Evidence.selectorBridge;
if (
  fail05Evidence.obligationId !== "FAIL-05"
  || selectorBridgeEvidence?.expectedRevertData !== "0x"
  || selectorBridgeEvidence?.typedFailureMutationSelector !== typedFailureSelectors[1].selector
) throw new Error("FAIL-05 selector evidence mismatch");
const genericDispatcherInputSelector = {
  hex: selectorBridgeEvidence.genericDispatcherInputSelector,
  decimal: selectorDecimal(selectorBridgeEvidence.genericDispatcherInputSelector),
};
const fail05SpecText = readFileSync(fail05SpecPath, "utf8");
if (!fail05SpecText.includes(`<data> #parseByteStack("${genericDispatcherInputSelector.hex}") </data>`)) {
  throw new Error("FAIL-05 proof spec selector mismatch");
}

const schema = {
  schemaVersion: 1,
  claimBoundary:
    "Generated shared boundary only. It binds compiler artifacts, resolved runtimes, ABI, layout, events and projection IDs; it does not itself prove a transition.",
  sourceBinding: {
    compilerManifestPath: repoPath(bindingManifestPath),
    compilerManifestSha256: sha256(readFileSync(bindingManifestPath)),
    compilerDeterministicRootSha256: bindingManifest.deterministicRootSha256,
    fixturePath: repoPath(fixturePath),
    fixtureSha256: sha256(readFileSync(fixturePath)),
    fixtureDeterministicRootSha256: fixture.deterministicRootSha256,
    obligationIndexPath: repoPath(obligationIndexPath),
    obligationRegistrySha256: obligationIndex.registry.sha256,
  },
  obligationIds: obligationIndex.obligations.map((entry) => entry.obligationId),
  actionCodes: [
    { abstract: "Legal_Freeze", solidity: "FREEZE", ordinal: 0 },
    { abstract: "Legal_Seize", solidity: "SEIZE", ordinal: 1 },
    { abstract: "Legal_Confiscate", solidity: "CONFISCATE", ordinal: 2 },
    { abstract: "Legal_Liquidate", solidity: "LIQUIDATE", ordinal: 3 },
    { abstract: "Legal_Restrict", solidity: "RESTRICT", ordinal: 4 },
    { abstract: "Legal_Recover", solidity: "RECOVER", ordinal: 5 },
  ],
  reversalCodes: [
    { abstract: "TRUST_UNFREEZE", solidity: "UNFREEZE", ordinal: 0 },
    { abstract: "TRUST_RELEASE", solidity: "RELEASE", ordinal: 1 },
    { abstract: "TRUST_UNRESTRICT", solidity: "UNRESTRICT", ordinal: 2 },
  ],
  selectorBoundary: {
    obligationId: "FAIL-05",
    evidencePath: repoPath(fail05EvidencePath),
    evidenceSha256: sha256(readFileSync(fail05EvidencePath)),
    proofSpecPath: repoPath(fail05SpecPath),
    proofSpecSha256: sha256(readFileSync(fail05SpecPath)),
    genericDispatcherInputSelector,
    expectedRevertData: selectorBridgeEvidence.expectedRevertData,
    typedCommandEntrypoints: [nativeAction, nativeReversal].map(({ name, signature, selector }) => ({
      name,
      signature,
      selector,
      decimal: selectorDecimal(selector),
    })),
    typedFailureSelectors,
  },
  endpoints: {
    native: {
      subjectId: native.id,
      runtimeTemplate: native.runtimeTemplate,
      resolvedRuntime: resolved("TrustToken"),
      actionEntrypoint: nativeAction,
      reversalEntrypoint: nativeReversal,
      storage: storageInventory(native, "native"),
      abi: nativeAbi,
    },
    verifiedProfile: {
      subjectId: adapter.id,
      runtimeTemplate: adapter.runtimeTemplate,
      resolvedRuntime: resolved("ERC3643TrustAdapter"),
      actionEntrypoint: profileAction,
      reversalEntrypoint: profileReversal,
      storage: storageInventory(adapter, "profile.adapter"),
      abi: abiInventory(adapter),
      underlyingStorage: storageInventory(token, "profile.token"),
      governorStorage: storageInventory(governor, "profile.governor"),
    },
  },
  resolvedTopology: fixture.deployments.map((entry) => resolved(entry.label)),
};
schema.projectionIds = [
  ...schema.endpoints.native.storage,
  ...schema.endpoints.verifiedProfile.storage,
  ...schema.endpoints.verifiedProfile.underlyingStorage,
  ...schema.endpoints.verifiedProfile.governorStorage,
].map((entry) => entry.projectionId).sort();
if (new Set(schema.projectionIds).size !== schema.projectionIds.length) throw new Error("duplicate projection ID");

mkdirSync(bridgeRoot, { recursive: true });
const schemaPath = join(bridgeRoot, "schema.json");
writeJson(schemaPath, schema);
const schemaHash = sha256(readFileSync(schemaPath));

function isabelleString(value) {
  if (!/^[A-Za-z0-9_./:()\-,+@= ]*$/.test(value)) throw new Error(`unsafe Isabelle string: ${value}`);
  return `''${value}''`;
}

const nativeFields = schema.endpoints.native.storage;
const profileFields = schema.endpoints.verifiedProfile.storage;
const nativeConstructors = nativeFields.map((_, index) => `Native_Field_${index}`);
const profileConstructors = profileFields.map((_, index) => `Profile_Field_${index}`);
const projectionStrings = schema.projectionIds.map(isabelleString).join(",\n     ");
const obligationStrings = schema.obligationIds.map(isabelleString).join(",\n     ");
const operationalFailureSelector = typedFailureSelectors.find((entry) => entry.name === "TrustOperationalFailure");
const rejectedSelector = typedFailureSelectors.find((entry) => entry.name === "TrustRejected");
const isabelle = `(* GENERATED by scripts/generate-runtime-bridge.mjs. DO NOT EDIT. *)
theory TRUST_Runtime_Bridge_Generated
  imports TRUST_Concrete_Configuration
begin

definition runtime_bridge_schema_sha256 :: string where
  "runtime_bridge_schema_sha256 = ${isabelleString(schemaHash)}"

definition compiler_binding_root_sha256 :: string where
  "compiler_binding_root_sha256 = ${isabelleString(bindingManifest.deterministicRootSha256)}"

definition constructor_fixture_root_sha256 :: string where
  "constructor_fixture_root_sha256 = ${isabelleString(fixture.deterministicRootSha256)}"

definition native_resolved_runtime_sha256 :: string where
  "native_resolved_runtime_sha256 = ${isabelleString(schema.endpoints.native.resolvedRuntime.sha256)}"

definition profile_resolved_runtime_sha256 :: string where
  "profile_resolved_runtime_sha256 = ${isabelleString(schema.endpoints.verifiedProfile.resolvedRuntime.sha256)}"

definition action_calldata_length :: nat where "action_calldata_length = 676"
definition reversal_calldata_length :: nat where "reversal_calldata_length = 292"
definition action_entrypoint_selector :: nat where
  "action_entrypoint_selector = ${Number.parseInt(nativeAction.selector.slice(2), 16)}"
definition reversal_entrypoint_selector :: nat where
  "reversal_entrypoint_selector = ${Number.parseInt(nativeReversal.selector.slice(2), 16)}"
definition generic_dispatcher_input_selector :: nat where
  "generic_dispatcher_input_selector = ${genericDispatcherInputSelector.decimal}"
definition trust_operational_failure_selector :: nat where
  "trust_operational_failure_selector = ${operationalFailureSelector.decimal}"
definition trust_rejected_selector :: nat where
  "trust_rejected_selector = ${rejectedSelector.decimal}"
definition typed_command_entrypoint_selectors :: "nat set" where
  "typed_command_entrypoint_selectors =
    {action_entrypoint_selector, reversal_entrypoint_selector}"
definition typed_failure_selectors :: "nat set" where
  "typed_failure_selectors =
    {trust_operational_failure_selector, trust_rejected_selector}"

fun solidity_action_code :: "legal_action_kind => nat" where
  "solidity_action_code Legal_Freeze = 0"
| "solidity_action_code Legal_Seize = 1"
| "solidity_action_code Legal_Confiscate = 2"
| "solidity_action_code Legal_Liquidate = 3"
| "solidity_action_code Legal_Restrict = 4"
| "solidity_action_code Legal_Recover = 5"

fun solidity_reversal_code :: "trust_reversal_kind => nat" where
  "solidity_reversal_code TRUST_UNFREEZE = 0"
| "solidity_reversal_code TRUST_RELEASE = 1"
| "solidity_reversal_code TRUST_UNRESTRICT = 2"

datatype native_storage_field = ${nativeConstructors.join(" | ")}
datatype profile_storage_field = ${profileConstructors.join(" | ")}

fun native_storage_base_slot :: "native_storage_field => nat" where
${nativeFields.map((entry, index) => `  "native_storage_base_slot Native_Field_${index} = ${entry.slot}"`).join("\n|")}

fun profile_storage_base_slot :: "profile_storage_field => nat" where
${profileFields.map((entry, index) => `  "profile_storage_base_slot Profile_Field_${index} = ${entry.slot}"`).join("\n|")}

definition generated_projection_ids :: "string list" where
  "generated_projection_ids =
    [${projectionStrings}]"

definition required_refinement_obligation_ids :: "string list" where
  "required_refinement_obligation_ids =
    [${obligationStrings}]"

theorem action_code_is_exact:
  "set (map solidity_action_code
    [Legal_Freeze, Legal_Seize, Legal_Confiscate,
     Legal_Liquidate, Legal_Restrict, Legal_Recover]) = {0, 1, 2, 3, 4, 5}"
  by simp

theorem reversal_code_is_exact:
  "set (map solidity_reversal_code
    [TRUST_UNFREEZE, TRUST_RELEASE, TRUST_UNRESTRICT]) = {0, 1, 2}"
  by simp

theorem generated_calldata_lengths_are_exact:
  "action_calldata_length = 676 & reversal_calldata_length = 292"
  by (simp add: action_calldata_length_def reversal_calldata_length_def)

theorem generated_projection_ids_are_distinct:
  "distinct generated_projection_ids"
  by (simp add: generated_projection_ids_def)

theorem required_refinement_obligation_inventory_is_exact:
  "length required_refinement_obligation_ids = 79 &
   distinct required_refinement_obligation_ids"
  by (simp add: required_refinement_obligation_ids_def)

end
`;
mkdirSync(dirname(isabellePath), { recursive: true });
writeFileSync(isabellePath, isabelle, "utf8");

const runtimeMacros = fixture.deployments.map((deployment) => {
  const symbol = `#trust${deployment.label}Runtime`;
  const runtime = readFileSync(join(repositoryRoot, ...deployment.runtime.path.split("/")), "utf8").trim();
  return `    syntax Bytes ::= "${symbol}" "(" ")" [macro]\n` +
    `    rule ${symbol}() => #parseByteStack("${runtime}")`;
}).join("\n\n");
const k = `// GENERATED by scripts/generate-runtime-bridge.mjs. DO NOT EDIT.\n` +
`requires "edsl.md"\n\n` +
`module TRUST-RUNTIME-BRIDGE\n` +
`    imports EDSL\n\n` +
`    syntax String ::= "#trustBridgeSchemaSha256" [macro]\n` +
`    rule #trustBridgeSchemaSha256 => "${schemaHash}"\n\n` +
`    syntax Int ::= "#trustActionCalldataLength" [macro]\n` +
`    rule #trustActionCalldataLength => 676\n` +
`    syntax Int ::= "#trustReversalCalldataLength" [macro]\n` +
`    rule #trustReversalCalldataLength => 292\n` +
`\n` +
`    // Checked selector constants are mirrored as non-executable metadata so\n` +
`    // this bridge remains claim-compatible with the exact pinned definition.\n` +
`    // selector constant #trustActionEntrypointSelector => ${selectorDecimal(nativeAction.selector)}\n` +
`    // selector constant #trustReversalEntrypointSelector => ${selectorDecimal(nativeReversal.selector)}\n` +
`    // selector constant #trustGenericDispatcherInputSelector => ${genericDispatcherInputSelector.decimal}\n` +
`    // selector constant #trustOperationalFailureSelector => ${operationalFailureSelector.decimal}\n` +
`    // selector constant #trustRejectedSelector => ${rejectedSelector.decimal}\n` +
`    // selector constant #trustTypedFailureSelectorCount => ${typedFailureSelectors.length}\n\n` +
`${runtimeMacros}\n` +
`endmodule\n`;
mkdirSync(dirname(kPath), { recursive: true });
writeFileSync(kPath, k, "utf8");

const generatedManifest = {
  schemaVersion: 1,
  schema: { path: repoPath(schemaPath), sha256: schemaHash, bytes: statSync(schemaPath).size },
  generated: [isabellePath, kPath].map((path) => ({
    path: repoPath(path),
    sha256: sha256(readFileSync(path)),
    bytes: statSync(path).size,
  })),
};
generatedManifest.deterministicRootSha256 = sha256(Buffer.from([
  `${generatedManifest.schema.path}\0${generatedManifest.schema.sha256}\n`,
  ...generatedManifest.generated.map((entry) => `${entry.path}\0${entry.sha256}\n`),
].join(""), "utf8"));
const manifestPath = join(bridgeRoot, "generated-manifest.json");
writeJson(manifestPath, generatedManifest);
console.log(JSON.stringify({
  status: "PASS",
  schema: repoPath(schemaPath),
  schemaSha256: schemaHash,
  projectionCount: schema.projectionIds.length,
  generatedRootSha256: generatedManifest.deterministicRootSha256,
  generated: generatedManifest.generated.map((entry) => entry.path),
}, null, 2));
