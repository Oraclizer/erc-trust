// Historical candidate 2 bridge verifier. The kernel v2 successor uses the generated v2 bridge gate.

import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { readFileSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const evidenceRoot = join(repositoryRoot, "evidence", "end-to-end-refinement");
const bindingRoot = join(evidenceRoot, "runtime-binding");
const bridgeRoot = join(evidenceRoot, "runtime-bridge");
const schemaPath = join(bridgeRoot, "schema.json");
const generatedManifestPath = join(bridgeRoot, "generated-manifest.json");
const schema = JSON.parse(readFileSync(schemaPath, "utf8"));
const generatedManifest = JSON.parse(readFileSync(generatedManifestPath, "utf8"));
const bindingManifestPath = join(bindingRoot, "manifest.json");
const fixturePath = join(bindingRoot, "resolved", "fixture.json");
const obligationIndexPath = join(evidenceRoot, "obligation-evidence-index.json");
const fail05EvidencePath = join(
  evidenceRoot,
  "kevm",
  "fail-05-generic-dispatcher-revert-20260802T174934Z",
  "evidence.json",
);
const fail05SpecPath = join(repositoryRoot, "formal", "kevm", "specs", "full-transaction-generic-dispatcher-revert-spec.k");
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

function same(left, right) {
  return JSON.stringify(stable(left)) === JSON.stringify(stable(right));
}

function absolute(repoPath) {
  return join(repositoryRoot, ...repoPath.split("/"));
}

function keccak(value) {
  return execFileSync("wsl.exe", ["-d", "Ubuntu", "-e", "cast", "keccak"], {
    input: value,
    encoding: "utf8",
    stdio: ["pipe", "pipe", "pipe"],
  }).trim();
}

function canonicalType(input) {
  return input.type === "tuple" ? `(${input.components.map(canonicalType).join(",")})` : input.type;
}

function signature(entry) {
  return `${entry.name}(${entry.inputs.map(canonicalType).join(",")})`;
}

function staticWords(input) {
  if (input.type === "tuple") return input.components.reduce((sum, component) => sum + staticWords(component), 0);
  if (input.type.endsWith("[]") || input.type === "bytes" || input.type === "string") throw new Error("dynamic command ABI");
  return 1;
}

function bridgeArtifacts(bundleId) {
  return JSON.parse(readFileSync(join(bindingRoot, bundleId, "bridge-artifacts.json"), "utf8"));
}

function artifact(bundleId, contract) {
  const entry = bridgeArtifacts(bundleId).find((candidate) => candidate.contract === contract);
  if (!entry) throw new Error(`bridge artifact missing: ${bundleId}:${contract}`);
  return entry;
}

function storage(artifactValue, profile) {
  return artifactValue.storageLayout.storage.map((entry) => ({
    projectionId: `${profile}.${entry.label.replace(/^_/, "")}`,
    label: entry.label,
    slot: Number(entry.slot),
    offset: entry.offset,
    typeId: entry.type,
    type: artifactValue.storageLayout.types[entry.type],
  }));
}

function abiInventory(artifactValue) {
  return artifactValue.abi.map((entry) => {
    if (!["function", "event", "error"].includes(entry.type)) return null;
    const canonical = signature(entry);
    if (entry.type === "event") {
      return {
        kind: "event",
        name: entry.name,
        signature: canonical,
        topic0: entry.anonymous ? null : keccak(canonical),
        anonymous: Boolean(entry.anonymous),
        indexed: entry.inputs.map((input) => Boolean(input.indexed)),
      };
    }
    return {
      kind: entry.type,
      name: entry.name,
      signature: canonical,
      selector: keccak(canonical).slice(0, 10),
    };
  }).filter(Boolean).sort((left, right) => `${left.kind}:${left.signature}`.localeCompare(`${right.kind}:${right.signature}`));
}

function entrypoint(artifactValue, name) {
  const entry = artifactValue.abi.find((candidate) => candidate.type === "function" && candidate.name === name);
  if (!entry || entry.inputs.length !== 1 || entry.inputs[0].type !== "tuple") throw new Error(`entrypoint missing: ${name}`);
  const canonical = signature(entry);
  const derived = keccak(canonical).slice(2, 10);
  if (artifactValue.methodIdentifiers[canonical] !== derived) throw new Error(`compiler selector mismatch: ${canonical}`);
  return {
    name,
    signature: canonical,
    selector: `0x${derived}`,
    tupleComponents: entry.inputs[0].components.map((component, ordinal) => ({
      ordinal,
      name: component.name,
      type: component.type,
      internalType: component.internalType,
    })),
    calldataLength: 4 + 32 * staticWords(entry.inputs[0]),
  };
}

function selectorDecimal(hex) {
  if (!/^0x[0-9a-f]{8}$/.test(hex)) throw new Error(`invalid selector: ${hex}`);
  return Number.parseInt(hex.slice(2), 16);
}

if (schema.schemaVersion !== 1 || generatedManifest.schemaVersion !== 1) throw new Error("unsupported bridge schema");
if (
  schema.sourceBinding.compilerManifestSha256 !== sha256(readFileSync(bindingManifestPath))
  || schema.sourceBinding.compilerDeterministicRootSha256 !== bindingManifest.deterministicRootSha256
  || schema.sourceBinding.fixtureSha256 !== sha256(readFileSync(fixturePath))
  || schema.sourceBinding.fixtureDeterministicRootSha256 !== fixture.deterministicRootSha256
  || schema.sourceBinding.obligationRegistrySha256 !== obligationIndex.registry.sha256
) throw new Error("bridge source binding mismatch");
const expectedObligationIds = obligationIndex.obligations.map((entry) => entry.obligationId);
if (
  expectedObligationIds.length !== 79
  || !same(schema.obligationIds, expectedObligationIds)
  || new Set(schema.obligationIds).size !== 79
) throw new Error("obligation inventory mismatch");

const expectedActionCodes = [
  ["Legal_Freeze", "FREEZE", 0],
  ["Legal_Seize", "SEIZE", 1],
  ["Legal_Confiscate", "CONFISCATE", 2],
  ["Legal_Liquidate", "LIQUIDATE", 3],
  ["Legal_Restrict", "RESTRICT", 4],
  ["Legal_Recover", "RECOVER", 5],
].map(([abstract, solidity, ordinal]) => ({ abstract, solidity, ordinal }));
const expectedReversalCodes = [
  ["TRUST_UNFREEZE", "UNFREEZE", 0],
  ["TRUST_RELEASE", "RELEASE", 1],
  ["TRUST_UNRESTRICT", "UNRESTRICT", 2],
].map(([abstract, solidity, ordinal]) => ({ abstract, solidity, ordinal }));
if (!same(schema.actionCodes, expectedActionCodes) || !same(schema.reversalCodes, expectedReversalCodes)) {
  throw new Error("typed command ordinal drift");
}

const native = artifact("native", "TrustToken");
const adapter = artifact("verified-profile", "ERC3643TrustAdapter");
const token = artifact("verified-profile", "MockERC3643Token");
const governor = artifact("verified-profile", "ProfileGovernor");
const expectedNativeAbi = abiInventory(native);
if (
  !same(schema.endpoints.native.storage, storage(native, "native"))
  || !same(schema.endpoints.verifiedProfile.storage, storage(adapter, "profile.adapter"))
  || !same(schema.endpoints.verifiedProfile.underlyingStorage, storage(token, "profile.token"))
  || !same(schema.endpoints.verifiedProfile.governorStorage, storage(governor, "profile.governor"))
) throw new Error("storage projection drift");
if (!same(schema.endpoints.native.abi, expectedNativeAbi)) throw new Error("native ABI inventory drift");
if (!same(schema.endpoints.verifiedProfile.abi, abiInventory(adapter))) throw new Error("profile ABI inventory drift");
if (
  !same(schema.endpoints.native.actionEntrypoint, entrypoint(native, "executeRegulatoryAction"))
  || !same(schema.endpoints.native.reversalEntrypoint, entrypoint(native, "executeRegulatoryReversal"))
  || !same(schema.endpoints.verifiedProfile.actionEntrypoint, entrypoint(adapter, "executeRegulatoryAction"))
  || !same(schema.endpoints.verifiedProfile.reversalEntrypoint, entrypoint(adapter, "executeRegulatoryReversal"))
) throw new Error("typed entrypoint drift");
const expectedTypedEntrypoints = [
  entrypoint(native, "executeRegulatoryAction"),
  entrypoint(native, "executeRegulatoryReversal"),
].map(({ name, signature: canonicalSignature, selector }) => ({
  name,
  signature: canonicalSignature,
  selector,
  decimal: selectorDecimal(selector),
}));
const expectedTypedFailures = ["TrustOperationalFailure", "TrustRejected"].map((name) => {
  const error = expectedNativeAbi.find((entry) => entry.kind === "error" && entry.name === name);
  if (!error) throw new Error(`typed failure ABI entry missing: ${name}`);
  return { name, signature: error.signature, selector: error.selector, decimal: selectorDecimal(error.selector) };
});
const selectorEvidence = fail05Evidence.selectorBridge;
const expectedGenericSelector = {
  hex: selectorEvidence.genericDispatcherInputSelector,
  decimal: selectorDecimal(selectorEvidence.genericDispatcherInputSelector),
};
if (
  schema.selectorBoundary.obligationId !== "FAIL-05"
  || schema.selectorBoundary.evidenceSha256 !== sha256(readFileSync(fail05EvidencePath))
  || schema.selectorBoundary.proofSpecSha256 !== sha256(readFileSync(fail05SpecPath))
  || !same(schema.selectorBoundary.genericDispatcherInputSelector, expectedGenericSelector)
  || schema.selectorBoundary.expectedRevertData !== "0x"
  || !same(schema.selectorBoundary.typedCommandEntrypoints, expectedTypedEntrypoints)
  || !same(schema.selectorBoundary.typedFailureSelectors, expectedTypedFailures)
  || selectorEvidence.typedFailureMutationSelector !== expectedTypedFailures[1].selector
) throw new Error("FAIL-05 selector boundary drift");
const fail05SpecText = readFileSync(fail05SpecPath, "utf8");
if (
  fail05SpecText.split(`<data> #parseByteStack("${expectedGenericSelector.hex}") </data>`).length - 1 !== 1
  || fail05SpecText.split("<output> .Bytes </output>").length - 1 !== 1
) throw new Error("FAIL-05 spec selector or empty-output boundary mismatch");
if (
  expectedTypedEntrypoints.some((entry) => entry.decimal === expectedGenericSelector.decimal)
  || expectedTypedFailures.some((entry) => entry.decimal === expectedGenericSelector.decimal)
) throw new Error("generic dispatcher selector aliases a typed selector");

const expectedProjectionIds = [
  ...storage(native, "native"),
  ...storage(adapter, "profile.adapter"),
  ...storage(token, "profile.token"),
  ...storage(governor, "profile.governor"),
].map((entry) => entry.projectionId).sort();
if (!same(schema.projectionIds, expectedProjectionIds) || new Set(schema.projectionIds).size !== schema.projectionIds.length) {
  throw new Error("projection index mismatch");
}

const schemaHash = sha256(readFileSync(schemaPath));
if (generatedManifest.schema.sha256 !== schemaHash || generatedManifest.schema.bytes !== statSync(schemaPath).size) {
  throw new Error("generated schema manifest mismatch");
}
for (const generated of generatedManifest.generated) {
  const bytes = readFileSync(absolute(generated.path));
  if (bytes.length !== generated.bytes || sha256(bytes) !== generated.sha256) throw new Error(`generated file drift: ${generated.path}`);
}
const generatedRoot = sha256(Buffer.from([
  `${generatedManifest.schema.path}\0${generatedManifest.schema.sha256}\n`,
  ...generatedManifest.generated.map((entry) => `${entry.path}\0${entry.sha256}\n`),
].join(""), "utf8"));
if (generatedRoot !== generatedManifest.deterministicRootSha256) throw new Error("generated bridge root mismatch");

const isabelleText = readFileSync(absolute("formal/isabelle/ERC_TRUST/TRUST_Runtime_Bridge_Generated.thy"), "utf8");
const kText = readFileSync(absolute("formal/kevm/generated/trust-runtime-bridge.k"), "utf8");
if (!isabelleText.includes(schemaHash) || !kText.includes(schemaHash)) throw new Error("schema hash missing from generated bridge");
for (const deployment of fixture.deployments) {
  const runtime = readFileSync(absolute(deployment.runtime.path), "utf8").trim();
  if (!kText.includes(runtime)) throw new Error(`resolved runtime missing from K bridge: ${deployment.label}`);
}
for (const projectionId of schema.projectionIds) {
  if (!isabelleText.includes(`''${projectionId}''`)) throw new Error(`projection missing from Isabelle bridge: ${projectionId}`);
}
for (const obligationId of schema.obligationIds) {
  if (!isabelleText.includes(`''${obligationId}''`)) throw new Error(`obligation missing from Isabelle bridge: ${obligationId}`);
}
for (const [label, value] of [
  ["generic_dispatcher_input_selector", expectedGenericSelector.decimal],
  ["trust_operational_failure_selector", expectedTypedFailures[0].decimal],
  ["trust_rejected_selector", expectedTypedFailures[1].decimal],
]) {
  if (!isabelleText.includes(`"${label} = ${value}"`)) throw new Error(`selector missing from Isabelle bridge: ${label}`);
}
for (const [label, value] of [
  ["#trustActionEntrypointSelector", expectedTypedEntrypoints[0].decimal],
  ["#trustReversalEntrypointSelector", expectedTypedEntrypoints[1].decimal],
  ["#trustGenericDispatcherInputSelector", expectedGenericSelector.decimal],
  ["#trustOperationalFailureSelector", expectedTypedFailures[0].decimal],
  ["#trustRejectedSelector", expectedTypedFailures[1].decimal],
  ["#trustTypedFailureSelectorCount", expectedTypedFailures.length],
]) {
  if (!kText.includes(`// selector constant ${label} => ${value}`)) {
    throw new Error(`selector metadata missing from K bridge: ${label}`);
  }
}
const transactionTheory = readFileSync(absolute("formal/isabelle/ERC_TRUST/TRUST_Transaction_Refinement.thy"), "utf8");
if (!transactionTheory.includes("theorem generic_dispatcher_revert_is_not_typed_failure:")) {
  throw new Error("named generic-dispatcher Isabelle theorem missing");
}

console.log(JSON.stringify({
  status: "PASS",
  schemaSha256: schemaHash,
  projectionCount: schema.projectionIds.length,
  generatedRootSha256: generatedRoot,
  actionCalldataLength: schema.endpoints.native.actionEntrypoint.calldataLength,
  reversalCalldataLength: schema.endpoints.native.reversalEntrypoint.calldataLength,
  genericDispatcherInputSelector: schema.selectorBoundary.genericDispatcherInputSelector.hex,
  typedFailureSelectorCount: schema.selectorBoundary.typedFailureSelectors.length,
}, null, 2));
