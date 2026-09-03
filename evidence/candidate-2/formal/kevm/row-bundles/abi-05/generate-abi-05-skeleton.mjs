#!/usr/bin/env node
// ABI-05 static skeleton generator. It reads pinned repository artifacts and
// emits metadata only. It never invokes K, KEVM, solc, Isabelle, or the network.
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const rowDir = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(rowDir, "../../../..");
const at = (...parts) => path.join(root, ...parts);
const posix = (file) => path.relative(root, file).split(path.sep).join("/");
const sha = (value) => crypto.createHash("sha256").update(value).digest("hex");
const fileSha = (file) => sha(fs.readFileSync(file));
const read = (file) => JSON.parse(fs.readFileSync(file, "utf8"));
const bind = (file) => ({ path: posix(file), sha256: fileSha(file) });

const output = {
  fieldMap: path.join(rowDir, "abi-field-map.json"),
  plan: path.join(rowDir, "claim-family-plan.json"),
  kBridge: path.join(rowDir, "generated/abi-05-row-bridge.k"),
  theory: path.join(rowDir, "isabelle/ABI_05_Decoded_Command_Fields_Match_Typed_Command.thy"),
  root: path.join(rowDir, "isabelle/ROOT"),
  bridge: path.join(rowDir, "bridge/row-bridge.json"),
  manifest: path.join(rowDir, "bridge/row-manifest.json"),
};
const generator = fileURLToPath(import.meta.url);
const verifier = path.join(rowDir, "verify-static.mjs");
const readme = path.join(rowDir, "README.md");

const indexPath = at("evidence/end-to-end-refinement/obligation-evidence-index.json");
const theoremPath = at("evidence/end-to-end-refinement/theorem-obligations.md");
const ledgerPath = at("evidence/end-to-end-refinement/proof-run-ledger.json");
const lockPath = at("formal/kevm/dependencies.lock.json");
const typesPath = at("implementation/src/TrustTypes.sol");
const nativeInputPath = at("evidence/end-to-end-refinement/runtime-binding/native/standard-json-input.json");
const nativeOutputPath = at("evidence/end-to-end-refinement/runtime-binding/native/standard-json-output.json");
const profileInputPath = at("evidence/end-to-end-refinement/runtime-binding/verified-profile/standard-json-input.json");
const profileOutputPath = at("evidence/end-to-end-refinement/runtime-binding/verified-profile/standard-json-output.json");
const nativeRuntimePath = at("evidence/end-to-end-refinement/runtime-binding/resolved/native/TrustToken.hex");
const profileRuntimePath = at("evidence/end-to-end-refinement/runtime-binding/resolved/verified-profile/ERC3643TrustAdapter.hex");
const compositionPath = at("formal/isabelle/ERC_TRUST/TRUST_Compositional_State.thy");
const refinementPath = at("formal/isabelle/ERC_TRUST/TRUST_Transaction_Refinement.thy");
const generatedTheoryPath = at("formal/isabelle/ERC_TRUST/TRUST_Runtime_Bridge_Generated.thy");

const index = read(indexPath);
const row = index.obligations.find((entry) => entry.obligationId === "ABI-05");
assert.ok(row);
assert.equal(row.requiredProperty, "`decoded_command_fields_match_typed_command`");
assert.equal(row.statement.name, "decoded_command_fields_match_typed_command");
assert.equal(row.status.classification, "OPEN");
assert.equal(row.status.discharged, false);
assert.deepEqual(row.soliditySubjects.map((entry) => entry.artifactRef.path), [
  "implementation/src/TrustTypes.sol",
  "implementation/src/TrustStorage.sol",
  "implementation/src/TrustPolicyBinding.sol",
  "implementation/src/TrustToken.sol",
  "implementation/src/profiles/ERC3643TrustAdapter.sol",
]);

const lock = read(lockPath);
assert.equal(fileSha(lockPath), "3134e7692086170f86b6dd42e7ebd0256c188da8db8cbd17241c3d2c8d315196");
const native = read(nativeOutputPath).contracts["implementation/src/TrustToken.sol"].TrustToken;
const profile = read(profileOutputPath).contracts["implementation/src/profiles/ERC3643TrustAdapter.sol"].ERC3643TrustAdapter;
const findFunction = (artifact, name) => artifact.abi.find((entry) => entry.type === "function" && entry.name === name);
const actionComponents = findFunction(native, "executeRegulatoryAction").inputs[0].components;
const reversalComponents = findFunction(native, "executeRegulatoryReversal").inputs[0].components;
assert.equal(actionComponents.length, 21);
assert.equal(reversalComponents.length, 9);
assert.deepEqual(findFunction(profile, "executeRegulatoryAction").inputs[0].components, actionComponents);
assert.deepEqual(findFunction(profile, "executeRegulatoryReversal").inputs[0].components, reversalComponents);

const expectedAction = [
  ["domain", "bytes32", "forward_domain"], ["actionId", "bytes32", "forward_action_id"],
  ["action", "uint8", "forward_action"], ["subject", "address", "forward_subject"],
  ["source", "address", "forward_source"], ["destination", "address", "forward_destination"],
  ["custodian", "address", "forward_custodian"], ["amount", "uint256", "forward_amount"],
  ["caseId", "bytes32", "forward_case"], ["scopeHash", "bytes32", "forward_scope_hash"],
  ["policyCommitment", "bytes32", "forward_policy_commitment"],
  ["provenanceCommitment", "bytes32", "forward_provenance_commitment"],
  ["settlementCommitment", "bytes32", "forward_settlement_commitment"],
  ["proceedsCommitment", "bytes32", "forward_proceeds_commitment"],
  ["entitlementCommitment", "bytes32", "forward_entitlement_commitment"],
  ["authorityRef", "bytes32", "forward_authority_ref"], ["authorityEpoch", "uint64", "forward_authority_epoch"],
  ["policyEpoch", "uint64", "forward_policy_epoch"], ["nonce", "uint256", "forward_nonce"],
  ["validAfter", "uint48", "forward_valid_after"], ["validBefore", "uint48", "forward_valid_before"],
];
const expectedReversal = [
  ["domain", "bytes32", "reversal_domain"], ["reversalId", "bytes32", "reversal_id"],
  ["actionId", "bytes32", "reversal_original_action_id"], ["reversal", "uint8", "reversal_kind"],
  ["authorityRef", "bytes32", "reversal_authority_ref"], ["authorityEpoch", "uint64", "reversal_authority_epoch"],
  ["nonce", "uint256", "reversal_nonce"], ["validAfter", "uint48", "reversal_valid_after"],
  ["validBefore", "uint48", "reversal_valid_before"],
];
assert.deepEqual(actionComponents.map((entry) => [entry.name, entry.type]), expectedAction.map((entry) => entry.slice(0, 2)));
assert.deepEqual(reversalComponents.map((entry) => [entry.name, entry.type]), expectedReversal.map((entry) => entry.slice(0, 2)));
const canonicalWidth = (type) => ({ bytes32: 256, uint256: 256, uint64: 64, uint48: 48, uint8: 8, address: 160 })[type];
const fieldRows = (shape, values) => values.map(([solidityField, abiType, isabelleField], wordIndex) => ({
  shape, wordIndex, byteStartInclusive: 4 + wordIndex * 32, byteEndExclusive: 4 + (wordIndex + 1) * 32,
  solidityField, abiType, valueBits: canonicalWidth(abiType), canonicalHighBitsZero: !["bytes32", "uint256"].includes(abiType),
  isabelleField, source: "CALLDATA",
}));

const fieldMap = {
  schemaVersion: 1,
  kind: "ABI05_TYPED_COMMAND_FIELD_MAP",
  classification: "STATIC_SCHEMA_BINDING_NOT_PROOF_EVIDENCE",
  obligationId: "ABI-05",
  requiredProperty: "decoded_command_fields_match_typed_command",
  canonicalRequiredPropertyLiteral: "`decoded_command_fields_match_typed_command`",
  selectorBytes: 4,
  action: { tupleWords: 21, calldataBytes: 676, fields: fieldRows("ACTION", expectedAction) },
  reversal: { tupleWords: 9, calldataBytes: 292, fields: fieldRows("REVERSAL", expectedReversal) },
  nonCalldataTypedFields: [{ shape: "REVERSAL", isabelleField: "reversal_policy_epoch", source: "ORIGINAL_ACTION_STATE", reason: "TrustTypes.ReversalRequest has no policyEpoch member; this model field must be refined from the referenced action record and cannot be credited to ABI-05 decoding." }],
  endpointFamilies: [
    { runtime: "TrustToken", shape: "ACTION", function: "executeRegulatoryAction", selector: `0x${native.evm.methodIdentifiers["executeRegulatoryAction((bytes32,bytes32,uint8,address,address,address,address,uint256,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,uint64,uint64,uint256,uint48,uint48))"]}` },
    { runtime: "TrustToken", shape: "REVERSAL", function: "executeRegulatoryReversal", selector: `0x${native.evm.methodIdentifiers["executeRegulatoryReversal((bytes32,bytes32,bytes32,uint8,bytes32,uint64,uint256,uint48,uint48))"]}` },
    { runtime: "TrustToken", shape: "ACTION", function: "executeERC7943Action", selector: `0x${native.evm.methodIdentifiers["executeERC7943Action((bytes32,bytes32,uint8,address,address,address,address,uint256,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,uint64,uint64,uint256,uint48,uint48))"]}` },
    { runtime: "TrustToken", shape: "REVERSAL", function: "executeERC7943Reversal", selector: `0x${native.evm.methodIdentifiers["executeERC7943Reversal((bytes32,bytes32,bytes32,uint8,bytes32,uint64,uint256,uint48,uint48))"]}` },
    { runtime: "ERC3643TrustAdapter", shape: "ACTION", function: "executeRegulatoryAction", selector: `0x${profile.evm.methodIdentifiers["executeRegulatoryAction((bytes32,bytes32,uint8,address,address,address,address,uint256,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,uint64,uint64,uint256,uint48,uint48))"]}` },
    { runtime: "ERC3643TrustAdapter", shape: "REVERSAL", function: "executeRegulatoryReversal", selector: `0x${profile.evm.methodIdentifiers["executeRegulatoryReversal((bytes32,bytes32,bytes32,uint8,bytes32,uint64,uint256,uint48,uint48))"]}` },
  ],
};
assert.deepEqual(fieldMap.endpointFamilies.map((entry) => entry.selector), ["0x9da23539", "0x7aab169b", "0x9295b54c", "0x75c28d96", "0x9da23539", "0x7aab169b"]);
const fieldMapText = JSON.stringify(fieldMap, null, 2) + "\n";

const actionConsumers = Array.from({ length: 9 }, (_, index) => `ACT-${String(index + 1).padStart(2, "0")}`);
const reversalConsumers = Array.from({ length: 3 }, (_, index) => `RVR-${String(index + 1).padStart(2, "0")}`);
const plan = {
  schemaVersion: 1,
  kind: "ABI05_REUSABLE_SYMBOLIC_CLAIM_FAMILY_PLAN",
  classification: "STATIC_PLAN_NOT_PROOF_EVIDENCE",
  obligationId: "ABI-05",
  requiredProperty: "decoded_command_fields_match_typed_command",
  prerequisites: {
    semantic: [
      { obligationId: "ABI-01", role: "canonical action decoding domain for all six numeric action values" },
      { obligationId: "ABI-02", role: "canonical reversal decoding domain for all three numeric reversal values" },
    ],
    artifactIdentity: [
      { obligationId: "ART-01", role: "source, compiler settings, and standard JSON binding" },
      { obligationId: "ART-02", role: "compiler output to runtime bytes binding" },
      { obligationId: "ART-03", role: "constructor-resolved native/profile runtime binding" },
      { obligationId: "ART-04", role: "ABI/AST/immutable-reference binding" },
    ],
    modelSurfaces: ["TrustTypes.ActionRequest", "TrustTypes.ReversalRequest", "trust_forward_command", "trust_reversal_command", "bridge_decode_calldata"],
    peerBoundariesNotPrerequisites: ["ABI-03", "ABI-04"],
  },
  consumers: {
    directFieldConsumers: ["AUTH-01", "AUTH-02", "AUTH-03", "AUTH-05", ...actionConsumers, ...reversalConsumers],
    compositionalConsumers: ["AUTH-04", "FAIL-01", "FAIL-02", "FAIL-03", "FAIL-04", "FAIL-06", "FAIL-07", "FAIL-08", "ART-06", "ART-07"],
    mappingStatus: "ROW_LOCAL_PROPOSAL_NOT_SHARED_REGISTRY",
  },
  claimFamilies: [
    { id: "ABI05-ACTION-FIELDS", shapes: ["ACTION"], endpoints: ["native-regulatory-action", "native-erc7943-action", "profile-regulatory-action"], symbolicFields: 21, canonicalCalldataBytes: 676, requiredEnumCases: 6 },
    { id: "ABI05-REVERSAL-FIELDS", shapes: ["REVERSAL"], endpoints: ["native-regulatory-reversal", "native-erc7943-reversal", "profile-regulatory-reversal"], symbolicFields: 9, canonicalCalldataBytes: 292, requiredEnumCases: 3 },
    { id: "ABI05-REVERSAL-POLICY-EPOCH-LINK", shapes: ["REVERSAL"], endpoints: ["native-regulatory-reversal", "native-erc7943-reversal", "profile-regulatory-reversal"], symbolicFields: 0, stateDerivedFields: ["reversal_policy_epoch"], status: "SEPARATE_REFINEMENT_LEMMA_REQUIRED" },
  ],
  proofArchitecture: {
    required: "a K-level ABI decoder projection lemma connected to each exact runtime dispatcher and a fieldwise Isabelle bridge",
    rejectedShortcut: "commandHash/reversalHash equality alone is not field equality without an injectivity theorem and cannot close ABI-05",
    observationBoundary: "OPEN_DESIGN_GATE",
    positiveClaims: "NOT_MATERIALIZED",
    negativeMutant: "NOT_MATERIALIZED_UNTIL_OBSERVATION_BOUNDARY_IS_FIXED",
  },
  heavyGates: ["K syntax/definition parse", "positive KEVM symbolic field-family proofs", "executable field-swap mutant build", "negative KEVM semantic counterexamples", "Isabelle build and oracle audit", "independent replay", "shared registry/ledger integration"],
};
const planText = JSON.stringify(plan, null, 2) + "\n";

const kBridge = `requires "../../../trust-runtime-verification.k"
// Generated ABI-05 schema bridge. Metadata only; not a claim or proof.
module TRUST-ABI-05-ROW-BRIDGE
  imports TRUST-RUNTIME-VERIFICATION
  syntax Int ::= #abi05SelectorBytes [function]
  rule #abi05SelectorBytes => 4
  syntax Int ::= #abi05ActionTupleWords [function]
  rule #abi05ActionTupleWords => 21
  syntax Int ::= #abi05ReversalTupleWords [function]
  rule #abi05ReversalTupleWords => 9
  syntax Int ::= #abi05ActionCalldataBytes [function]
  rule #abi05ActionCalldataBytes => 676
  syntax Int ::= #abi05ReversalCalldataBytes [function]
  rule #abi05ReversalCalldataBytes => 292
  syntax Int ::= #abi05EndpointFamilyCount [function]
  rule #abi05EndpointFamilyCount => 6
  syntax Int ::= #abi05CalldataBackedTypedFieldCount [function]
  rule #abi05CalldataBackedTypedFieldCount => 30
  syntax Int ::= #abi05StateDerivedTypedFieldCount [function]
  rule #abi05StateDerivedTypedFieldCount => 1
endmodule
`;

const theory = `theory ABI_05_Decoded_Command_Fields_Match_Typed_Command
  imports ERC_TRUST.TRUST_Transaction_Refinement
begin

definition abi_05_required_property :: string where
  "abi_05_required_property = ''decoded_command_fields_match_typed_command''"
definition abi_05_action_word_count :: nat where "abi_05_action_word_count = 21"
definition abi_05_reversal_word_count :: nat where "abi_05_reversal_word_count = 9"
definition abi_05_calldata_backed_field_count :: nat where "abi_05_calldata_backed_field_count = 30"
definition abi_05_state_derived_field_count :: nat where "abi_05_state_derived_field_count = 1"
definition abi_05_proof_status :: string where "abi_05_proof_status = ''NOT_RUN''"
definition abi_05_eligible_for_discharge :: bool where "abi_05_eligible_for_discharge = False"

consts abi_05_decoded_field_words :: "evm_bytes \<Rightarrow> nat list"
consts abi_05_typed_field_words :: "trust_typed_command \<Rightarrow> nat list"

definition abi_05_fieldwise_decoder_refinement ::
  "trust_transaction_bridge \<Rightarrow> evm_bytes \<Rightarrow> trust_typed_command \<Rightarrow> bool"
where
  "abi_05_fieldwise_decoder_refinement bridge calldata command \<longleftrightarrow>
    bridge_decode_calldata bridge calldata = Some command \<and>
    abi_05_decoded_field_words calldata = abi_05_typed_field_words command"

theorem abi_05_decoded_command_fields_match_typed_command:
  assumes "abi_05_fieldwise_decoder_refinement bridge calldata command"
  shows "bridge_decode_calldata bridge calldata = Some command \<and>
    abi_05_decoded_field_words calldata = abi_05_typed_field_words command"
  using assms by (simp add: abi_05_fieldwise_decoder_refinement_def)

theorem abi_05_reversal_policy_epoch_is_not_calldata_backed:
  "abi_05_reversal_word_count = 9 \<and> abi_05_state_derived_field_count = 1"
  by (simp add: abi_05_reversal_word_count_def abi_05_state_derived_field_count_def)

theorem abi_05_static_gate_remains_open:
  "abi_05_action_word_count + abi_05_reversal_word_count =
      abi_05_calldata_backed_field_count \<and>
   abi_05_proof_status = ''NOT_RUN'' \<and> \<not> abi_05_eligible_for_discharge"
  by (simp add: abi_05_action_word_count_def abi_05_reversal_word_count_def
      abi_05_calldata_backed_field_count_def abi_05_proof_status_def
      abi_05_eligible_for_discharge_def)

end
`;
const rootText = `session ERC_TRUST_ABI_05_SKELETON = ERC_TRUST +
  options [document = false]
  theories
    ABI_05_Decoded_Command_Fields_Match_Typed_Command
`;

const sourceIdentity = {};
for (const subject of row.soliditySubjects) sourceIdentity[subject.artifactRef.path] = bind(at(subject.artifactRef.path));
const bridge = {
  schemaVersion: 1,
  kind: "ABI05_ROW_LOCAL_STATIC_SKELETON_BRIDGE",
  classification: "PASS_OPEN_STATIC_NOT_PROOF_EVIDENCE",
  obligationId: "ABI-05",
  requiredProperty: "decoded_command_fields_match_typed_command",
  canonicalRequiredPropertyLiteral: "`decoded_command_fields_match_typed_command`",
  staticStatus: "PASS_OPEN_STATIC",
  proofStatus: "NOT_RUN",
  closureStatus: "OPEN",
  eligibleForDischarge: false,
  generator: bind(generator), verifier: bind(verifier), readme: bind(readme),
  canonicalRegistry: { obligationIndex: bind(indexPath), theoremObligations: bind(theoremPath), proofRunLedger: bind(ledgerPath), indexClassification: "OPEN", indexDischarged: false, canonicalDependencyLockPlaceholder: row.tcb[0].exactIdentityRef, actualDependencyLock: bind(lockPath), bindingStatus: "OPEN_PLACEHOLDER_PENDING_BINDING" },
  sourceIdentity,
  compilerIdentity: { version: lock.components.solc.version, binarySha256: lock.components.solc.binarySha256, nativeInput: bind(nativeInputPath), nativeOutput: bind(nativeOutputPath), profileInput: bind(profileInputPath), profileOutput: bind(profileOutputPath), compileStatus: "NOT_RUN" },
  runtimeIdentity: {
    native: { artifact: bind(nativeRuntimePath), runtimeBytesSha256: sha(Buffer.from(fs.readFileSync(nativeRuntimePath, "utf8").trim().slice(2), "hex")), runtimeBytes: 24142 },
    profile: { artifact: bind(profileRuntimePath), runtimeBytesSha256: sha(Buffer.from(fs.readFileSync(profileRuntimePath, "utf8").trim().slice(2), "hex")), runtimeBytes: 16398 },
  },
  modelIdentity: { compositionalState: bind(compositionPath), transactionRefinement: bind(refinementPath), generatedRuntimeTheory: bind(generatedTheoryPath) },
  fieldMap: { path: posix(output.fieldMap), sha256: sha(fieldMapText), actionFields: 21, reversalCalldataFields: 9, reversalStateDerivedFields: 1 },
  claimFamilyPlan: { path: posix(output.plan), sha256: sha(planText), positiveClaimsStatus: "NOT_MATERIALIZED", negativeMutantStatus: "NOT_MATERIALIZED" },
  generated: { kBridge: { path: posix(output.kBridge), sha256: sha(kBridge), parseStatus: "NOT_RUN" } },
  isabelle: { theory: { path: posix(output.theory), sha256: sha(theory), name: "ABI_05_Decoded_Command_Fields_Match_Typed_Command" }, root: { path: posix(output.root), sha256: sha(rootText) }, session: "ERC_TRUST_ABI_05_SKELETON", namedTheorem: "abi_05_decoded_command_fields_match_typed_command", theoremKind: "ASSUMPTION_GATED_SKELETON", buildStatus: "NOT_RUN", oracleAuditStatus: "NOT_RUN" },
  blockers: [
    "The exact runtime observation boundary for fieldwise decoded values is not fixed.",
    "commandHash/reversalHash equality is not accepted as field equality without an injectivity theorem.",
    "Isabelle reversal_policy_epoch is state-derived and has no ReversalRequest calldata word.",
    "No executable field-swap mutant, KEVM claim family, Isabelle build, or independent replay exists yet.",
    "The canonical registry still points at a stale dependency-lock hash placeholder.",
  ],
  coordinatorScope: { rowLocalOnly: true, sharedRegistryUpdated: false, sharedLedgerUpdated: false, sharedGeneratedRuntimeBridgeUpdated: false, sharedManifestUpdated: false },
};
assert.equal(bridge.runtimeIdentity.native.runtimeBytesSha256, "3697706d4948c34fada47e049d32ad3e1866cf24ded6328f0c209d858614a86d");
assert.equal(bridge.runtimeIdentity.profile.runtimeBytesSha256, "0c873ae5756cf6a3e3ab1317af7c09a39391640b3c54bef4b84b091042d9cf4b");
const bridgeText = JSON.stringify(bridge, null, 2) + "\n";
const manifest = {
  schemaVersion: 1, kind: "ABI05_ROW_LOCAL_STATIC_SKELETON_MANIFEST", obligationId: "ABI-05",
  requiredProperty: "decoded_command_fields_match_typed_command", status: "PASS_OPEN_STATIC", proofStatus: "NOT_RUN",
  closureStatus: "OPEN", eligibleForDischarge: false, bridge: { path: posix(output.bridge), sha256: sha(bridgeText) },
  files: [output.fieldMap, output.plan, output.kBridge, output.theory, output.root].map(posix),
};
const manifestText = JSON.stringify(manifest, null, 2) + "\n";

const outputs = [[output.fieldMap, fieldMapText], [output.plan, planText], [output.kBridge, kBridge],
  [output.theory, theory], [output.root, rootText], [output.bridge, bridgeText], [output.manifest, manifestText]];
const printIndex = process.argv.indexOf("--print-file");
if (printIndex >= 0) {
  const index = Number(process.argv[printIndex + 1]);
  assert.ok(outputs[index]);
  process.stdout.write(JSON.stringify({ path: outputs[index][0], content: outputs[index][1] }));
} else if (process.argv.includes("--check")) {
  for (const [file, content] of outputs) assert.equal(fs.readFileSync(file, "utf8"), content, `${file}: stale`);
  console.log(JSON.stringify({ status: "PASS_OPEN_STATIC", obligationId: "ABI-05", requiredProperty: bridge.requiredProperty,
    proofStatus: "NOT_RUN", eligibleForDischarge: false, fieldMapSha256: sha(fieldMapText), bridgeSha256: sha(bridgeText),
    actionFields: 21, reversalCalldataFields: 9, reversalStateDerivedFields: 1, kParseStatus: "NOT_RUN", isabelleBuildStatus: "NOT_RUN" }, null, 2));
} else {
  for (const [file, content] of outputs) { fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, content); }
  console.log("GENERATED PASS_OPEN_STATIC ABI-05");
}
