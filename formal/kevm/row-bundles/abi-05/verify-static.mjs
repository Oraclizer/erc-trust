#!/usr/bin/env node
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const rowDir = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(rowDir, "../../../..");
const sha = (value) => crypto.createHash("sha256").update(value).digest("hex");
const fileSha = (file) => sha(fs.readFileSync(file));
const read = (file) => JSON.parse(fs.readFileSync(file, "utf8"));
const bridge = read(path.join(rowDir, "bridge/row-bridge.json"));
const manifest = read(path.join(rowDir, "bridge/row-manifest.json"));
const fieldMap = read(path.join(rowDir, "abi-field-map.json"));
const plan = read(path.join(rowDir, "claim-family-plan.json"));
const index = read(path.join(root, "evidence/end-to-end-refinement/obligation-evidence-index.json"));
const row = index.obligations.find((entry) => entry.obligationId === "ABI-05");

assert.equal(row.requiredProperty, "`decoded_command_fields_match_typed_command`");
assert.equal(row.status.classification, "OPEN");
assert.equal(row.status.discharged, false);
assert.equal(bridge.requiredProperty, "decoded_command_fields_match_typed_command");
assert.equal(bridge.canonicalRequiredPropertyLiteral, row.requiredProperty);
assert.equal(bridge.classification, "PASS_OPEN_STATIC_NOT_PROOF_EVIDENCE");
assert.equal(bridge.staticStatus, "PASS_OPEN_STATIC");
assert.equal(bridge.proofStatus, "NOT_RUN");
assert.equal(bridge.closureStatus, "OPEN");
assert.equal(bridge.eligibleForDischarge, false);
assert.equal(fileSha(path.join(root, bridge.canonicalRegistry.actualDependencyLock.path)), bridge.canonicalRegistry.actualDependencyLock.sha256);
assert.notEqual(bridge.canonicalRegistry.actualDependencyLock.sha256, bridge.canonicalRegistry.canonicalDependencyLockPlaceholder.sha256);
for (const binding of Object.values(bridge.sourceIdentity)) assert.equal(fileSha(path.join(root, binding.path)), binding.sha256);
for (const binding of Object.values(bridge.modelIdentity)) assert.equal(fileSha(path.join(root, binding.path)), binding.sha256);

assert.equal(fieldMap.requiredProperty, "decoded_command_fields_match_typed_command");
assert.equal(fieldMap.action.tupleWords, 21);
assert.equal(fieldMap.action.calldataBytes, 676);
assert.equal(fieldMap.action.fields.length, 21);
assert.equal(fieldMap.reversal.tupleWords, 9);
assert.equal(fieldMap.reversal.calldataBytes, 292);
assert.equal(fieldMap.reversal.fields.length, 9);
assert.equal(fieldMap.endpointFamilies.length, 6);
assert.deepEqual(fieldMap.endpointFamilies.map((entry) => entry.selector), ["0x9da23539", "0x7aab169b", "0x9295b54c", "0x75c28d96", "0x9da23539", "0x7aab169b"]);
for (const family of [fieldMap.action, fieldMap.reversal]) {
  family.fields.forEach((field, index) => {
    assert.equal(field.wordIndex, index);
    assert.equal(field.byteStartInclusive, 4 + index * 32);
    assert.equal(field.byteEndExclusive, 4 + (index + 1) * 32);
    assert.equal(field.source, "CALLDATA");
  });
}
assert.deepEqual(fieldMap.nonCalldataTypedFields.map((entry) => entry.isabelleField), ["reversal_policy_epoch"]);
assert.equal(fieldMap.nonCalldataTypedFields[0].source, "ORIGINAL_ACTION_STATE");
assert.equal(fileSha(path.join(root, bridge.fieldMap.path)), bridge.fieldMap.sha256);
assert.equal(bridge.fieldMap.actionFields, 21);
assert.equal(bridge.fieldMap.reversalCalldataFields, 9);
assert.equal(bridge.fieldMap.reversalStateDerivedFields, 1);

assert.deepEqual(plan.prerequisites.semantic.map((entry) => entry.obligationId), ["ABI-01", "ABI-02"]);
assert.deepEqual(plan.prerequisites.artifactIdentity.map((entry) => entry.obligationId), ["ART-01", "ART-02", "ART-03", "ART-04"]);
assert.deepEqual(plan.prerequisites.peerBoundariesNotPrerequisites, ["ABI-03", "ABI-04"]);
assert.ok(plan.consumers.directFieldConsumers.includes("AUTH-01"));
assert.ok(plan.consumers.directFieldConsumers.includes("ACT-09"));
assert.ok(plan.consumers.directFieldConsumers.includes("RVR-03"));
assert.equal(plan.consumers.mappingStatus, "ROW_LOCAL_PROPOSAL_NOT_SHARED_REGISTRY");
assert.equal(plan.claimFamilies.length, 3);
assert.equal(plan.proofArchitecture.observationBoundary, "OPEN_DESIGN_GATE");
assert.match(plan.proofArchitecture.rejectedShortcut, /Hash.*not field equality|hash.*not field equality/i);
assert.equal(plan.proofArchitecture.positiveClaims, "NOT_MATERIALIZED");
assert.equal(plan.proofArchitecture.negativeMutant, "NOT_MATERIALIZED_UNTIL_OBSERVATION_BOUNDARY_IS_FIXED");
assert.equal(fileSha(path.join(root, bridge.claimFamilyPlan.path)), bridge.claimFamilyPlan.sha256);

assert.equal(bridge.runtimeIdentity.native.runtimeBytes, 24142);
assert.equal(bridge.runtimeIdentity.native.runtimeBytesSha256, "3697706d4948c34fada47e049d32ad3e1866cf24ded6328f0c209d858614a86d");
assert.equal(bridge.runtimeIdentity.profile.runtimeBytes, 16398);
assert.equal(bridge.runtimeIdentity.profile.runtimeBytesSha256, "0c873ae5756cf6a3e3ab1317af7c09a39391640b3c54bef4b84b091042d9cf4b");

const kBridge = fs.readFileSync(path.join(root, bridge.generated.kBridge.path), "utf8");
assert.equal(sha(kBridge), bridge.generated.kBridge.sha256);
assert.match(kBridge, /#abi05ActionTupleWords => 21/);
assert.match(kBridge, /#abi05ReversalTupleWords => 9/);
assert.match(kBridge, /#abi05CalldataBackedTypedFieldCount => 30/);
assert.match(kBridge, /#abi05StateDerivedTypedFieldCount => 1/);
assert.equal(bridge.generated.kBridge.parseStatus, "NOT_RUN");

const theory = fs.readFileSync(path.join(root, bridge.isabelle.theory.path), "utf8");
assert.equal(sha(theory), bridge.isabelle.theory.sha256);
assert.match(theory, /theorem abi_05_decoded_command_fields_match_typed_command/);
assert.match(theory, /theorem abi_05_reversal_policy_epoch_is_not_calldata_backed/);
assert.match(theory, /abi_05_eligible_for_discharge = False/);
assert.equal(bridge.isabelle.theoremKind, "ASSUMPTION_GATED_SKELETON");
assert.equal(bridge.isabelle.buildStatus, "NOT_RUN");
assert.equal(bridge.isabelle.oracleAuditStatus, "NOT_RUN");
assert.ok(bridge.blockers.some((entry) => entry.includes("observation boundary")));
assert.ok(bridge.blockers.some((entry) => entry.includes("reversal_policy_epoch")));
assert.equal(bridge.coordinatorScope.sharedRegistryUpdated, false);
assert.equal(bridge.coordinatorScope.sharedLedgerUpdated, false);
assert.equal(bridge.coordinatorScope.sharedGeneratedRuntimeBridgeUpdated, false);
assert.equal(bridge.coordinatorScope.sharedManifestUpdated, false);
assert.equal(manifest.bridge.sha256, fileSha(path.join(root, manifest.bridge.path)));
assert.equal(manifest.status, "PASS_OPEN_STATIC");
assert.equal(manifest.proofStatus, "NOT_RUN");
assert.equal(manifest.eligibleForDischarge, false);

console.log(JSON.stringify({
  status: "PASS_OPEN_STATIC", obligationId: "ABI-05", requiredProperty: bridge.requiredProperty,
  proofStatus: bridge.proofStatus, closureStatus: bridge.closureStatus, eligibleForDischarge: bridge.eligibleForDischarge,
  fieldMapSha256: bridge.fieldMap.sha256, bridgeSha256: manifest.bridge.sha256,
  actionFields: fieldMap.action.fields.length, reversalCalldataFields: fieldMap.reversal.fields.length,
  reversalStateDerivedFields: fieldMap.nonCalldataTypedFields.length,
  kParseStatus: bridge.generated.kBridge.parseStatus, isabelleBuildStatus: bridge.isabelle.buildStatus,
  positiveClaimsStatus: bridge.claimFamilyPlan.positiveClaimsStatus,
  negativeMutantStatus: bridge.claimFamilyPlan.negativeMutantStatus,
}, null, 2));
