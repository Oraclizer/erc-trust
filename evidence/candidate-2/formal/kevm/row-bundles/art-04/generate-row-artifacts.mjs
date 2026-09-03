import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const rowRoot = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(rowRoot, "../../../..");
const evidenceRoot = join(repositoryRoot, "evidence", "end-to-end-refinement");
const bindingRoot = join(evidenceRoot, "runtime-binding");
const obligationIndexPath = join(evidenceRoot, "obligation-evidence-index.json");
const theoremObligationsPath = join(evidenceRoot, "theorem-obligations.md");
const proofLedgerPath = join(evidenceRoot, "proof-run-ledger.json");
const bindingManifestPath = join(bindingRoot, "manifest.json");
const compilerOutputPath = join(bindingRoot, "native", "standard-json-output.json");
const compilerArtifactsPath = join(bindingRoot, "native", "bridge-artifacts.json");
const fixturePath = join(bindingRoot, "resolved", "fixture.json");
const resolvedRuntimePath = join(bindingRoot, "resolved", "native", "TrustToken.hex");
const storageSourcePath = join(repositoryRoot, "implementation", "src", "TrustStorage.sol");
const lockPath = join(repositoryRoot, "formal", "kevm", "dependencies.lock.json");
const positiveVerificationPath = join(repositoryRoot, "formal", "kevm", "trust-runtime-verification.k");
const canonicalBridgePath = join(repositoryRoot, "formal", "kevm", "generated", "trust-runtime-bridge.k");
const claimPath = join(rowRoot, "claim.k");
const mutantBridgePath = join(rowRoot, "generated", "mutant-runtime-bridge.k");
const mutantVerificationPath = join(rowRoot, "generated", "mutant-runtime-verification.k");
const dependencyGraphPath = join(rowRoot, "dependency-graph.json");
const bridgePath = join(rowRoot, "bridge", "row-bridge.json");
const theoryPath = join(rowRoot, "isabelle", "ART_04_Artifact_Surface_Binding.thy");
const skeletonPath = join(rowRoot, "bundle.skeleton.json");
const runnerDescriptorPath = join(rowRoot, "runner-descriptor.skeleton.json");
const rowManifestPath = join(rowRoot, "bridge", "row-manifest.json");
const sharedRunnerRoot = join(repositoryRoot, "formal", "kevm", "row-bundles");

const requiredProperty = "storage_layout_abi_ast_and_immutable_references_are_hash_bound";
const canonicalPlaceholderSha256 = "e4fcabd40c8b18e3900050a590b6b80c687d4d115f61bc12439af6099e83434e";
const totalSupplySelector = "18160ddd";
const totalSupplyAstId = 624;
const canonicalSlot = 2;
const mutantSlot = 3;
const canonicalReturnWord = `0x${BigInt(42).toString(16).padStart(64, "0")}`;
const mutantReturnWord = `0x${"00".repeat(31)}63`;
const getterNeedle = "600254604051908152f3";

function sha256(value) { return createHash("sha256").update(value).digest("hex"); }
function repoPath(path) { return relative(repositoryRoot, path).split(sep).join("/"); }
function write(path, text) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, text.replaceAll("\r\n", "\n"), "utf8");
}
function stable(value) {
  if (Array.isArray(value)) return value.map(stable);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stable(value[key])]));
  }
  return value;
}
function json(value) { return `${JSON.stringify(stable(value), null, 2)}\n`; }
function canonicalSectionHash(value) { return sha256(Buffer.from(JSON.stringify(stable(value)))); }
function read(path) { return readFileSync(path); }
function ref(path) { return { path: repoPath(path), sha256: sha256(read(path)) }; }
function normalizeHex(text) {
  const value = text.trim().toLowerCase();
  if (!/^0x[0-9a-f]+$/.test(value) || value.length % 2 !== 0) throw new Error("invalid runtime hex");
  return value;
}
function exactEqual(left, right) { return JSON.stringify(stable(left)) === JSON.stringify(stable(right)); }

const obligationIndexBytes = read(obligationIndexPath);
const theoremObligationsBytes = read(theoremObligationsPath);
const proofLedgerBytes = read(proofLedgerPath);
const bindingManifestBytes = read(bindingManifestPath);
const compilerOutputBytes = read(compilerOutputPath);
const compilerArtifactsBytes = read(compilerArtifactsPath);
const fixtureBytes = read(fixturePath);
const resolvedRuntimeTextBytes = read(resolvedRuntimePath);
const storageSourceBytes = read(storageSourcePath);
const lockBytes = read(lockPath);
const canonicalBridgeBytes = read(canonicalBridgePath);
const claimBytes = read(claimPath);

const obligationIndex = JSON.parse(obligationIndexBytes);
const obligation = obligationIndex.obligations.find((entry) => entry.obligationId === "ART-04");
if (!obligation || obligation.requiredProperty.replaceAll("`", "") !== requiredProperty || obligation.statement?.name !== requiredProperty) {
  throw new Error("ART-04 requiredProperty drift");
}
if (obligation.status?.classification !== "OPEN" || obligation.status?.discharged !== false) throw new Error("ART-04 must remain OPEN");
if (!theoremObligationsBytes.toString("utf8").includes(`| ART-04 | \`${requiredProperty}\` |`)) throw new Error("ART-04 theorem inventory drift");
const canonicalLockPlaceholder = obligation.tcb.find((entry) => entry.tcbId === "TCB-LOCK")?.exactIdentityRef;
if (!canonicalLockPlaceholder || canonicalLockPlaceholder.sha256 !== canonicalPlaceholderSha256) throw new Error("ART-04 OPEN lock placeholder drift");

const currentLockSha256 = sha256(lockBytes);
const bindingManifest = JSON.parse(bindingManifestBytes);
if (bindingManifest.sourceIdentity?.dependencyLockSha256 !== currentLockSha256) throw new Error("runtime-binding manifest lock identity drift");
const proofLedger = JSON.parse(proofLedgerBytes);
for (const runId of ["RUN-BINDING-DIRECT-STANDARD-JSON-001", "RUN-FIXTURE-RESOLVED-001", "RUN-FIXTURE-RESOLVED-REPLAY-001"]) {
  const run = proofLedger.runs.find((entry) => entry.runId === runId);
  if (!run || run.status !== "PASS" || !run.targetObligationIds.includes("ART-04")) throw new Error(`missing ART-04 provenance PASS: ${runId}`);
}

const compilerOutput = JSON.parse(compilerOutputBytes);
const compilerArtifacts = JSON.parse(compilerArtifactsBytes);
const artifact = compilerArtifacts.find((entry) => entry.contract === "TrustToken");
const contractOutput = compilerOutput.contracts["implementation/src/TrustToken.sol"].TrustToken;
if (!artifact || artifact.source !== "implementation/src/TrustToken.sol") throw new Error("TrustToken artifact missing");
if (!exactEqual(artifact.abi, contractOutput.abi) || !exactEqual(artifact.storageLayout, contractOutput.storageLayout)) {
  throw new Error("bridge artifact ABI/storage layout differs from Standard JSON output");
}
if (!exactEqual(artifact.runtimeTemplate.immutableReferences, contractOutput.evm.deployedBytecode.immutableReferences)) {
  throw new Error("bridge artifact immutable references differ from Standard JSON output");
}
if (contractOutput.evm.methodIdentifiers["totalSupply()"] !== totalSupplySelector || artifact.methodIdentifiers["totalSupply()"] !== totalSupplySelector) {
  throw new Error("totalSupply selector drift");
}
const totalSupplyAbi = contractOutput.abi.find((entry) => entry.type === "function" && entry.name === "totalSupply");
if (!totalSupplyAbi || totalSupplyAbi.inputs.length !== 0 || totalSupplyAbi.outputs.length !== 1 || totalSupplyAbi.outputs[0].type !== "uint256" || totalSupplyAbi.stateMutability !== "view") {
  throw new Error("totalSupply ABI shape drift");
}
const totalSupplyLayout = contractOutput.storageLayout.storage.find((entry) => entry.astId === totalSupplyAstId);
if (!totalSupplyLayout || totalSupplyLayout.label !== "_totalSupply" || totalSupplyLayout.slot !== "2" || totalSupplyLayout.offset !== 0 || totalSupplyLayout.type !== "t_uint256") {
  throw new Error("_totalSupply storage layout drift");
}
const storageAst = compilerOutput.sources["implementation/src/TrustStorage.sol"].ast;
const storageContract = storageAst.nodes.find((entry) => entry.nodeType === "ContractDefinition" && entry.name === "TrustStorage");
const totalSupplyDeclaration = storageContract?.nodes.find((entry) => entry.id === totalSupplyAstId);
if (!totalSupplyDeclaration || totalSupplyDeclaration.name !== "_totalSupply" || totalSupplyDeclaration.nodeType !== "VariableDeclaration" || totalSupplyDeclaration.typeDescriptions.typeString !== "uint256" || totalSupplyDeclaration.stateVariable !== true) {
  throw new Error("_totalSupply AST declaration drift");
}
if (!storageSourceBytes.toString("utf8").includes("uint256 internal _totalSupply;")) throw new Error("TrustStorage source declaration drift");

const fixture = JSON.parse(fixtureBytes);
const deployment = fixture.deployments.find((entry) => entry.label === "TrustToken");
const resolvedHex = normalizeHex(resolvedRuntimeTextBytes.toString("utf8"));
const resolvedBytes = Buffer.from(resolvedHex.slice(2), "hex");
if (!deployment || deployment.runtime.sha256 !== sha256(resolvedBytes) || !deployment.immutablePatch.exactMatch) throw new Error("resolved runtime fixture drift");

const canonicalBridge = canonicalBridgeBytes.toString("utf8");
const macroPrefix = 'rule #trustTrustTokenRuntime() => #parseByteStack("';
const macroStart = canonicalBridge.indexOf(macroPrefix);
const runtimeStart = macroStart + macroPrefix.length;
const runtimeEnd = canonicalBridge.indexOf('")', runtimeStart);
if (macroStart < 0 || runtimeEnd < 0 || normalizeHex(canonicalBridge.slice(runtimeStart, runtimeEnd)) !== resolvedHex) throw new Error("canonical K runtime macro drift");

const rawRuntime = resolvedHex.slice(2);
const needleHexOffset = rawRuntime.indexOf(getterNeedle);
if (needleHexOffset < 0 || rawRuntime.indexOf(getterNeedle, needleHexOffset + 1) >= 0) throw new Error("totalSupply slot-2 getter needle is not unique");
const getterByteOffset = needleHexOffset / 2;
const mutationByteOffset = getterByteOffset + 1;
if (mutationByteOffset !== 8340 || resolvedBytes[mutationByteOffset] !== canonicalSlot) throw new Error("totalSupply SLOAD slot immediate drift");
const mutantBytes = Buffer.from(resolvedBytes);
mutantBytes[mutationByteOffset] = mutantSlot;
const mutantRuntime = `0x${mutantBytes.toString("hex")}`;
const mutantBridge = `${canonicalBridge.slice(0, runtimeStart)}${mutantRuntime}${canonicalBridge.slice(runtimeEnd)}`;
write(mutantBridgePath, mutantBridge);
write(mutantVerificationPath, 'requires "mutant-runtime-bridge.k"\nrequires "driver.md"\n\nmodule TRUST-RUNTIME-VERIFICATION\n    imports TRUST-RUNTIME-BRIDGE\n    imports ETHEREUM-SIMULATION\nendmodule\n');

const dependencyGraph = {
  schemaVersion: 1,
  selectedObligation: { id: "ART-04", property: requiredProperty, status: "OPEN" },
  derivationBasis: [
    { ...ref(theoremObligationsPath), role: "canonical obligation inventory" },
    { ...ref(proofLedgerPath), role: "artifact/provenance run targeting" },
  ],
  nodes: [
    { id: "ART-01", role: "direct-prerequisite", reason: "source identities and compiler settings underpin ABI, AST, layout and reference artifacts" },
    { id: "ART-02", role: "direct-prerequisite", reason: "the same pinned compiler output supplies exact runtime and artifact surfaces" },
    { id: "ART-04", role: "selected", reason: "hash binding of storage layout, ABI, source AST and immutable references" },
    { id: "ART-03", role: "direct-consumer", reason: "constructor resolution consumes immutable declarations and reference ranges" },
    { id: "ART-06", role: "direct-consumer", reason: "runtime execution consumes ABI and storage-layout bindings" },
    { id: "ART-07", role: "transitive-consumer", reason: "end-to-end composition consumes the artifact surface through ART-03 and ART-06" },
  ],
  edges: [["ART-01", "ART-04"], ["ART-02", "ART-04"], ["ART-04", "ART-03"], ["ART-04", "ART-06"], ["ART-03", "ART-07"], ["ART-06", "ART-07"]],
};
write(dependencyGraphPath, json(dependencyGraph));

const sectionHashes = {
  abiCanonicalJsonSha256: canonicalSectionHash(contractOutput.abi),
  storageLayoutCanonicalJsonSha256: canonicalSectionHash(contractOutput.storageLayout),
  trustStorageAstCanonicalJsonSha256: canonicalSectionHash(storageAst),
  immutableReferencesCanonicalJsonSha256: canonicalSectionHash(contractOutput.evm.deployedBytecode.immutableReferences),
  methodIdentifiersCanonicalJsonSha256: canonicalSectionHash(contractOutput.evm.methodIdentifiers),
};
const bridge = {
  schemaVersion: 1,
  obligationId: "ART-04",
  requiredProperty,
  status: "OPEN",
  eligibleForDischarge: false,
  canonicalObligation: { index: ref(obligationIndexPath), theoremInventory: ref(theoremObligationsPath), classification: "OPEN", discharged: false },
  dependencies: { directPrerequisites: ["ART-01", "ART-02"], directConsumers: ["ART-03", "ART-06"], transitiveConsumers: ["ART-07"], graph: ref(dependencyGraphPath) },
  tcb: {
    classification: "OPEN_PLACEHOLDER_PENDING_COORDINATOR_BINDING",
    canonicalIndexPlaceholder: canonicalLockPlaceholder,
    actualCurrentLock: ref(lockPath),
    runtimeBindingManifest: { ...ref(bindingManifestPath), dependencyLockSha256: bindingManifest.sourceIdentity.dependencyLockSha256 },
    productDrift: false,
    staticBlocker: false,
  },
  compilerArtifactSurface: {
    standardJsonOutput: ref(compilerOutputPath),
    bridgeArtifacts: ref(compilerArtifactsPath),
    subject: "implementation/src/TrustToken.sol:TrustToken",
    sectionHashes,
    abiEntryCount: contractOutput.abi.length,
    storageEntryCount: contractOutput.storageLayout.storage.length,
    storageTypeCount: Object.keys(contractOutput.storageLayout.types).length,
    immutableDeclarationCount: Object.keys(contractOutput.evm.deployedBytecode.immutableReferences).length,
    immutableReferenceCount: Object.values(contractOutput.evm.deployedBytecode.immutableReferences).flat().length,
    sourceAst: { path: "evidence/end-to-end-refinement/runtime-binding/native/standard-json-output.json#/sources/implementation~1src~1TrustStorage.sol/ast", sourcePath: "implementation/src/TrustStorage.sol", rootId: storageAst.id },
    totalSupply: { selector: `0x${totalSupplySelector}`, abi: totalSupplyAbi, storageLayout: totalSupplyLayout, astDeclaration: totalSupplyDeclaration },
    immutableReferences: contractOutput.evm.deployedBytecode.immutableReferences,
  },
  resolvedRuntime: { ...ref(resolvedRuntimePath), byteSha256: sha256(resolvedBytes), byteLength: resolvedBytes.length, fixture: ref(fixturePath), fixtureRootSha256: fixture.deterministicRootSha256, canonicalKBridge: ref(canonicalBridgePath) },
  executableObservation: { method: "totalSupply()", selector: `0x${totalSupplySelector}`, canonicalSlot, adjacentControlSlot: mutantSlot, canonicalValue: 42, adjacentControlValue: 99, expectedStatus: "EVMC_SUCCESS", expectedReturnWord: canonicalReturnWord, proofSpec: ref(claimPath), module: "TRUST-ART-04-ARTIFACT-SURFACE-BINDING-SPEC" },
  semanticMutation: {
    mutationId: "ART-04-MUT-TOTAL-SUPPLY-SLOT-001",
    kind: "EXECUTABLE_SEMANTIC_MUTANT",
    getterNeedle,
    getterByteOffset,
    byteOffset: mutationByteOffset,
    canonicalByte: "0x02",
    mutantByte: "0x03",
    canonicalSlot,
    mutantSlot,
    expectedCanonicalReturnWord: canonicalReturnWord,
    expectedMutantReturnWord: mutantReturnWord,
    mutantRuntimeSha256: sha256(mutantBytes),
    mutantBridge: ref(mutantBridgePath),
    mutantVerification: ref(mutantVerificationPath),
    expectedSemanticDifference: "the unchanged totalSupply() claim requires slot-2 value 42, while the same selector on the mutant reads adjacent slot 3 and returns 99",
  },
  provenanceEvidence: { ledger: ref(proofLedgerPath), passRuns: ["RUN-BINDING-DIRECT-STANDARD-JSON-001", "RUN-FIXTURE-RESOLVED-001", "RUN-FIXTURE-RESOLVED-REPLAY-001"] },
};
write(bridgePath, json(bridge));

const theory = `theory ART_04_Artifact_Surface_Binding\n  imports ERC_TRUST.TRUST_Runtime_Bridge_Generated\nbegin\n\n` +
`definition art04_abi_sha256 :: string where "art04_abi_sha256 = ''${sectionHashes.abiCanonicalJsonSha256}''"\n` +
`definition art04_storage_layout_sha256 :: string where "art04_storage_layout_sha256 = ''${sectionHashes.storageLayoutCanonicalJsonSha256}''"\n` +
`definition art04_trust_storage_ast_sha256 :: string where "art04_trust_storage_ast_sha256 = ''${sectionHashes.trustStorageAstCanonicalJsonSha256}''"\n` +
`definition art04_immutable_references_sha256 :: string where "art04_immutable_references_sha256 = ''${sectionHashes.immutableReferencesCanonicalJsonSha256}''"\n` +
`definition art04_method_identifiers_sha256 :: string where "art04_method_identifiers_sha256 = ''${sectionHashes.methodIdentifiersCanonicalJsonSha256}''"\n` +
`definition art04_resolved_runtime_sha256 :: string where "art04_resolved_runtime_sha256 = ''${sha256(resolvedBytes)}''"\n` +
`definition art04_mutant_runtime_sha256 :: string where "art04_mutant_runtime_sha256 = ''${sha256(mutantBytes)}''"\n` +
`definition art04_total_supply_selector :: string where "art04_total_supply_selector = ''0x${totalSupplySelector}''"\n` +
`definition art04_total_supply_ast_id :: nat where "art04_total_supply_ast_id = ${totalSupplyAstId}"\n` +
`definition art04_total_supply_slot :: nat where "art04_total_supply_slot = ${canonicalSlot}"\n` +
`definition art04_storage_entry_count :: nat where "art04_storage_entry_count = ${contractOutput.storageLayout.storage.length}"\n` +
`definition art04_immutable_reference_count :: nat where "art04_immutable_reference_count = ${Object.values(contractOutput.evm.deployedBytecode.immutableReferences).flat().length}"\n` +
`definition art04_mutation_byte_offset :: nat where "art04_mutation_byte_offset = ${mutationByteOffset}"\n\n` +
`theorem ${requiredProperty}:\n  "art04_resolved_runtime_sha256 = native_resolved_runtime_sha256 \\<and>\n` +
`   art04_abi_sha256 \\<noteq> '''' \\<and> art04_storage_layout_sha256 \\<noteq> '''' \\<and>\n` +
`   art04_trust_storage_ast_sha256 \\<noteq> '''' \\<and> art04_immutable_references_sha256 \\<noteq> '''' \\<and>\n` +
`   art04_method_identifiers_sha256 \\<noteq> '''' \\<and>\n` +
`   art04_total_supply_selector = ''0x18160ddd'' \\<and> art04_total_supply_ast_id = 624 \\<and>\n` +
`   art04_total_supply_slot = 2 \\<and> art04_storage_entry_count > 2 \\<and>\n` +
`   art04_immutable_reference_count = 5 \\<and> art04_mutation_byte_offset = 8340 \\<and>\n` +
`   art04_resolved_runtime_sha256 \\<noteq> art04_mutant_runtime_sha256"\n` +
`  by (simp add: art04_resolved_runtime_sha256_def native_resolved_runtime_sha256_def\n` +
`      art04_abi_sha256_def art04_storage_layout_sha256_def art04_trust_storage_ast_sha256_def\n` +
`      art04_immutable_references_sha256_def art04_method_identifiers_sha256_def art04_mutant_runtime_sha256_def\n` +
`      art04_total_supply_selector_def art04_total_supply_ast_id_def art04_total_supply_slot_def\n` +
`      art04_storage_entry_count_def art04_immutable_reference_count_def art04_mutation_byte_offset_def)\n\n` +
`ML \\<open>\n  val row_fact = @{thm ${requiredProperty}};\n  val row_oracles = Thm_Deps.all_oracles [row_fact];\n` +
`  val _ = if null row_oracles then () else error ("ART-04 proof audit found oracle dependencies");\n` +
`  val audit_report = "status=PASS\\nqualified_theorem=ART_04_Artifact_Surface_Binding.${requiredProperty}\\noracle_dependency_count=0\\n";\n` +
`  val _ = Export.export \\<^theory> \\<^path_binding>\\<open>erc-trust-art-04/proof-trust.txt\\<close> [XML.Text audit_report];\n\\<close>\n\nend\n`;
write(theoryPath, theory);

const blockers = ["fresh closed positive KEVM graph", "fresh terminal semantic negative graph showing slot-3 value 99 against unchanged slot-2 value 42 requirement", "serial Isabelle clean build and oracle-free export", "repository-owned independent replay"];
const tcbBinding = { classification: bridge.tcb.classification, canonicalPlaceholderSha256, actualCurrentLock: bridge.tcb.actualCurrentLock, runtimeBindingManifestDependencyLockSha256: currentLockSha256, productDrift: false, blocker: false };
const skeleton = {
  schemaVersion: 1, obligationId: "ART-04", requiredProperty, status: "OPEN", proofStatus: "PASS_OPEN_STATIC", eligibleForDischarge: false, tcbBinding,
  proofSpec: { path: repoPath(claimPath), module: bridge.executableObservation.module, claimId: null, sha256: sha256(claimBytes) },
  proofInputs: { claim: ref(claimPath), positiveVerification: ref(positiveVerificationPath), negativeRuntimeBridge: { ...ref(mutantBridgePath), mutationId: bridge.semanticMutation.mutationId }, negativeVerification: ref(mutantVerificationPath) },
  positive: { definitionKoreSha256: null, compiledJsonSha256: null, graph: null, requiredExitCode: 0, requiredWitnesses: ["EVMC_SUCCESS", canonicalReturnWord, "slot 2 contains 42 while adjacent slot 3 contains 99"] },
  negative: { mutationId: bridge.semanticMutation.mutationId, mutationKind: bridge.semanticMutation.kind, definitionKoreSha256: null, compiledJsonSha256: null, graph: null, requiredExitCode: 1, requiredWitness: `${mutantReturnWord} contradicts unchanged ${canonicalReturnWord} requirement` },
  bridge: { ...ref(bridgePath), reverseCheck: "formal/kevm/row-bundles/art-04/reverse-check.py" },
  isabelle: { theoryPath: repoPath(theoryPath), theoremName: requiredProperty, session: "ERC_TRUST_ART_04", buildStatus: "NOT_RUN_IN_WORKER", closureReport: null },
  replay: { status: "NOT_RUN", report: null, traceRoot: null, proofRoot: null }, blockers,
  prohibitedUntilHeavyProofsComplete: ["KEVM", "K_DRY_RUN", "ISABELLE_BUILD", "SOLC_COMPILE"],
};
write(skeletonPath, json(skeleton));

const runnerTools = ["run-row-bundle.sh", "validate-bundle.py", "analyze-row-proof.mjs", "curate-row-output.py", "verify-curated-evidence.py"].map((name) => ref(join(sharedRunnerRoot, name)));
const runnerDescriptor = {
  schemaVersion: 1, obligationId: "ART-04", status: "OPEN", proofStatus: "PASS_OPEN_STATIC", eligibleForDischarge: false, tcbBinding,
  interfacePilot: ["FAIL-05", "ART-02", "ART-03"], repositoryOwnedTools: runnerTools,
  inputs: { skeletonBundle: ref(skeletonPath), claim: ref(claimPath), positiveVerification: ref(positiveVerificationPath), negativeVerification: ref(mutantVerificationPath), negativeRuntimeBridge: ref(mutantBridgePath), isabelleClosureScript: ref(join(rowRoot, "isabelle", "run-closure.ps1")) },
  coordinatorSuppliedAfterAuthoritativeRuns: { completedBundlePath: null, positiveDefinitionDirectory: null, negativeDefinitionDirectory: null, isabelleClosureReport: null, outputDirectory: null, curatedEvidenceDirectory: null, replayReport: null },
  definitionCompileCommandTemplates: {
    positive: ["kevm", "kompile-spec", "formal/kevm/trust-runtime-verification.k", "--main-module", "TRUST-RUNTIME-VERIFICATION", "--target", "haskell", "--emit-json", "--output-definition", "<fresh-positive-definition-directory>"],
    negative: ["kevm", "kompile-spec", "formal/kevm/row-bundles/art-04/generated/mutant-runtime-verification.k", "--main-module", "TRUST-RUNTIME-VERIFICATION", "--target", "haskell", "--emit-json", "--output-definition", "<fresh-negative-definition-directory>"],
  },
  isabelleClosureCommandTemplate: ["powershell", "-File", "formal/kevm/row-bundles/art-04/isabelle/run-closure.ps1", "-IsabelleRoot", "<exact-isabelle-root>", "-AdsFunctor", "<exact-ads-functor-directory>", "-FormalFoundation", "<exact-formal-foundation-directory>", "-OutputDirectory", "<fresh-isabelle-output-directory>"],
  completedBundleValidationCommandTemplate: ["python3", "formal/kevm/row-bundles/validate-bundle.py", "<completed-art-04-bundle.json>"],
  authoritativeCommandTemplate: ["bash", "formal/kevm/row-bundles/run-row-bundle.sh", "--bundle", "<completed-art-04-bundle.json>", "--positive-definition", "<exact-positive-definition-directory>", "--negative-definition", "<exact-negative-definition-directory>", "--output-directory", "<fresh-output-directory>", "--report", "<fresh-replay-report.json>", "--curated-evidence-directory", "<fresh-curated-evidence-directory>", "--isabelle-report", "<fresh-art-04-isabelle-closure-report.json>", "--side-timeout-seconds", "<positive-integer>", "--no-use-booster"],
  proofFacts: { claimId: null, positiveDefinitionHashes: null, positiveGraph: null, negativeDefinitionHashes: null, negativeGraph: null, isabelleBuild: null, replay: null },
};
write(runnerDescriptorPath, json(runnerDescriptor));

const rowManifest = {
  schemaVersion: 1, obligationId: "ART-04", requiredProperty, status: "OPEN", proofStatus: "PASS_OPEN_STATIC", eligibleForDischarge: false, tcbBinding,
  bridge: ref(bridgePath), dependencyGraph: ref(dependencyGraphPath), proofSpec: { ...ref(claimPath), module: bridge.executableObservation.module },
  generated: [mutantBridgePath, mutantVerificationPath].map(ref), theorem: { ...ref(theoryPath), session: "ERC_TRUST_ART_04", name: requiredProperty, buildStatus: "NOT_RUN_IN_WORKER" },
  skeletonBundle: ref(skeletonPath), runnerDescriptor: ref(runnerDescriptorPath), proofFacts: { claimId: null, positiveGraph: null, negativeGraph: null, isabelleClosure: null, replay: null },
};
write(rowManifestPath, json(rowManifest));

process.stdout.write(`${JSON.stringify({ status: "PASS_OPEN_STATIC", eligibleForDischarge: false, obligationId: "ART-04", requiredProperty, tcbBindingClassification: bridge.tcb.classification, currentLockSha256, sectionHashes, resolvedRuntimeSha256: sha256(resolvedBytes), mutationByteOffset, mutantRuntimeSha256: sha256(mutantBytes), bridge: ref(bridgePath), theory: ref(theoryPath), bundleSkeleton: ref(skeletonPath), runnerDescriptor: ref(runnerDescriptorPath), rowManifest: ref(rowManifestPath) }, null, 2)}\n`);
