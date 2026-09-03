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
const generatedRoot = join(rowRoot, "generated");
const mutantBridgePath = join(generatedRoot, "mutant-runtime-bridge.k");
const mutantVerificationPath = join(generatedRoot, "mutant-runtime-verification.k");
const dependencyGraphPath = join(rowRoot, "dependency-graph.json");
const bridgePath = join(rowRoot, "bridge", "row-bridge.json");
const theoryPath = join(rowRoot, "isabelle", "ART_03_Constructor_Resolved_Runtime_Binding.thy");
const skeletonPath = join(rowRoot, "bundle.skeleton.json");
const runnerDescriptorPath = join(rowRoot, "runner-descriptor.skeleton.json");
const rowManifestPath = join(rowRoot, "bridge", "row-manifest.json");
const sharedRunnerRoot = join(repositoryRoot, "formal", "kevm", "row-bundles");

const requiredProperty = "constructor_resolved_local_runtime_is_hash_bound";
const expectedWord = "0x0000000000000000000000000000000000000000000000000000000000000012";
const mutantWord = "0x0000000000000000000000000000000000000000000000000000000000000013";
const decimalsSelector = "313ce567";
const declarationAstId = 622;
const immutableStart = 6970;
const immutableLength = 32;
const mutationByteOffset = immutableStart + immutableLength - 1;

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function repoPath(path) {
  return relative(repositoryRoot, path).split(sep).join("/");
}

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

function json(value) {
  return `${JSON.stringify(stable(value), null, 2)}\n`;
}

function normalizeHex(text) {
  const value = text.trim().toLowerCase();
  if (!/^0x[0-9a-f]*$/.test(value) || value.length % 2 !== 0) throw new Error("invalid runtime hex");
  return value;
}

function read(path) {
  return readFileSync(path);
}

function ref(path) {
  return { path: repoPath(path), sha256: sha256(read(path)) };
}

const obligationIndexBytes = read(obligationIndexPath);
const theoremObligationsBytes = read(theoremObligationsPath);
const proofLedgerBytes = read(proofLedgerPath);
const bindingManifestBytes = read(bindingManifestPath);
const compilerOutputBytes = read(compilerOutputPath);
const compilerArtifactsBytes = read(compilerArtifactsPath);
const fixtureBytes = read(fixturePath);
const storageSourceBytes = read(storageSourcePath);
const lockBytes = read(lockPath);
const canonicalBridgeBytes = read(canonicalBridgePath);
const claimBytes = read(claimPath);

const obligationIndex = JSON.parse(obligationIndexBytes);
const obligation = obligationIndex.obligations.find((entry) => entry.obligationId === "ART-03");
if (!obligation) throw new Error("ART-03 is absent from the canonical obligation index");
if (obligation.requiredProperty.replaceAll("`", "") !== requiredProperty || obligation.statement?.name !== requiredProperty) {
  throw new Error("ART-03 requiredProperty drift");
}
if (obligation.status?.classification !== "OPEN" || obligation.status?.discharged !== false) {
  throw new Error("ART-03 must remain canonically OPEN");
}
if (!theoremObligationsBytes.toString("utf8").includes(`| ART-03 | \`${requiredProperty}\` |`)) {
  throw new Error("ART-03 theorem-obligation row drift");
}
const canonicalLockPlaceholder = obligation.tcb.find((entry) => entry.tcbId === "TCB-LOCK")?.exactIdentityRef;
const currentLockSha256 = sha256(lockBytes);
if (!canonicalLockPlaceholder || canonicalLockPlaceholder.sha256 !== "e4fcabd40c8b18e3900050a590b6b80c687d4d115f61bc12439af6099e83434e") {
  throw new Error("ART-03 canonical OPEN lock placeholder drift");
}

const proofLedger = JSON.parse(proofLedgerBytes);
for (const runId of ["RUN-BINDING-DIRECT-STANDARD-JSON-001", "RUN-FIXTURE-RESOLVED-001", "RUN-FIXTURE-RESOLVED-REPLAY-001"]) {
  const run = proofLedger.runs.find((entry) => entry.runId === runId);
  if (!run || run.status !== "PASS" || !run.targetObligationIds.includes("ART-03")) {
    throw new Error(`required provenance run missing or no longer PASS for ART-03: ${runId}`);
  }
}

const compilerOutput = JSON.parse(compilerOutputBytes);
const compilerArtifacts = JSON.parse(compilerArtifactsBytes);
const fixture = JSON.parse(fixtureBytes);
const bindingManifest = JSON.parse(bindingManifestBytes);
if (bindingManifest.sourceIdentity?.dependencyLockSha256 !== currentLockSha256) {
  throw new Error("runtime-binding manifest does not name the actual current dependency lock");
}
const artifact = compilerArtifacts.find((entry) => entry.contract === "TrustToken");
const deployment = fixture.deployments.find((entry) => entry.label === "TrustToken");
if (!artifact || !deployment) throw new Error("TrustToken compiler or fixture subject missing");
const contractOutput = compilerOutput.contracts[artifact.source][artifact.contract];
const deployedBytecode = contractOutput.evm.deployedBytecode;
if (contractOutput.evm.methodIdentifiers["decimals()"] !== decimalsSelector) throw new Error("decimals selector drift");
const templateBytes = Buffer.from(deployedBytecode.object, "hex");
if (templateBytes.length !== artifact.runtimeTemplate.byteLength || sha256(templateBytes) !== artifact.runtimeTemplate.sha256) {
  throw new Error("compiler runtime template drift");
}

const decimalsDeclaration = deployment.immutablePatch.declarations.find((entry) => entry.astId === declarationAstId);
if (
  !decimalsDeclaration
  || decimalsDeclaration.name !== "decimals"
  || decimalsDeclaration.canonicalType !== "uint8"
  || decimalsDeclaration.value !== "18"
  || normalizeHex(decimalsDeclaration.encodedWord) !== expectedWord
  || decimalsDeclaration.locations.length !== 1
  || decimalsDeclaration.locations[0].start !== immutableStart
  || decimalsDeclaration.locations[0].length !== immutableLength
) throw new Error("decimals immutable declaration drift");
const compilerDecimalsLocations = deployedBytecode.immutableReferences[String(declarationAstId)];
if (
  compilerDecimalsLocations.length !== 1
  || compilerDecimalsLocations[0].start !== decimalsDeclaration.locations[0].start
  || compilerDecimalsLocations[0].length !== decimalsDeclaration.locations[0].length
) {
  throw new Error("compiler immutable reference and fixture location differ");
}
if (!storageSourceBytes.toString("utf8").includes("uint8 public immutable decimals;")) {
  throw new Error("TrustStorage decimals declaration drift");
}

const patchedBytes = Buffer.from(templateBytes);
for (const declaration of deployment.immutablePatch.declarations) {
  const word = Buffer.from(normalizeHex(declaration.encodedWord).slice(2), "hex");
  for (const location of declaration.locations) {
    if (location.length !== word.length) throw new Error(`immutable word length mismatch: ${declaration.name}`);
    word.copy(patchedBytes, location.start);
  }
}
const resolvedHex = normalizeHex(readFileSync(resolvedRuntimePath, "utf8"));
const resolvedBytes = Buffer.from(resolvedHex.slice(2), "hex");
if (!patchedBytes.equals(resolvedBytes)) throw new Error("immutable patch reconstruction mismatch");
if (
  !deployment.immutablePatch.exactMatch
  || deployment.immutablePatch.ethGetCodeSha256 !== deployment.runtime.sha256
  || deployment.immutablePatch.patchedSha256 !== deployment.runtime.sha256
  || sha256(resolvedBytes) !== deployment.runtime.sha256
) throw new Error("resolved runtime fixture is not an exact patch/getCode match");
if (`0x${resolvedBytes.subarray(immutableStart, immutableStart + immutableLength).toString("hex")}` !== expectedWord) {
  throw new Error("resolved runtime does not contain the pinned decimals word");
}

const canonicalBridge = canonicalBridgeBytes.toString("utf8");
const macroPrefix = 'rule #trustTrustTokenRuntime() => #parseByteStack("';
const macroStart = canonicalBridge.indexOf(macroPrefix);
if (macroStart < 0) throw new Error("TrustToken runtime macro missing");
const runtimeStart = macroStart + macroPrefix.length;
const runtimeEnd = canonicalBridge.indexOf('")', runtimeStart);
if (runtimeEnd < 0) throw new Error("TrustToken runtime macro unterminated");
if (normalizeHex(canonicalBridge.slice(runtimeStart, runtimeEnd)) !== resolvedHex) {
  throw new Error("generated K runtime macro and resolved runtime differ");
}

const mutantBytes = Buffer.from(resolvedBytes);
if (mutantBytes[mutationByteOffset] !== 0x12) throw new Error("canonical mutation byte is not 0x12");
mutantBytes[mutationByteOffset] = 0x13;
if (`0x${mutantBytes.subarray(immutableStart, immutableStart + immutableLength).toString("hex")}` !== mutantWord) {
  throw new Error("mutant decimals word is not uint8(19)");
}
const mutantRuntime = `0x${mutantBytes.toString("hex")}`;
const mutantBridge = `${canonicalBridge.slice(0, runtimeStart)}${mutantRuntime}${canonicalBridge.slice(runtimeEnd)}`;
write(mutantBridgePath, mutantBridge);
write(mutantVerificationPath, 'requires "mutant-runtime-bridge.k"\nrequires "driver.md"\n\nmodule TRUST-RUNTIME-VERIFICATION\n    imports TRUST-RUNTIME-BRIDGE\n    imports ETHEREUM-SIMULATION\nendmodule\n');

const dependencyGraph = {
  schemaVersion: 1,
  selectedObligation: { id: "ART-03", property: requiredProperty, status: "OPEN" },
  derivationBasis: [
    { path: repoPath(theoremObligationsPath), sha256: sha256(theoremObligationsBytes), role: "canonical obligation inventory" },
    { path: repoPath(proofLedgerPath), sha256: sha256(proofLedgerBytes), role: "artifact/provenance run targeting" },
  ],
  nodes: [
    { id: "ART-01", role: "transitive-prerequisite", reason: "source, compiler settings, and direct Standard JSON provenance consumed through ART-02" },
    { id: "ART-02", role: "direct-prerequisite", reason: "exact compiler output runtime template consumed by constructor patching" },
    { id: "ART-04", role: "direct-prerequisite", reason: "AST declaration 622 and immutable reference range [6970,7002) identify the patch boundary" },
    { id: "ART-03", role: "selected", reason: "constructor arguments resolve the local TrustToken runtime and its observable decimals immutable" },
    { id: "ART-06", role: "direct-consumer", reason: "runtime execution consumes the exact constructor-resolved runtime" },
    { id: "ART-07", role: "transitive-consumer", reason: "end-to-end theorem composition consumes ART-03 through runtime execution" },
  ],
  edges: [["ART-01", "ART-02"], ["ART-02", "ART-03"], ["ART-04", "ART-03"], ["ART-03", "ART-06"], ["ART-06", "ART-07"]],
  edgeSemantics: {
    "direct-prerequisite": "must be supplied or separately discharged; this static row does not discharge the dependency",
    "transitive-prerequisite": "reaches ART-03 only through a named direct prerequisite",
    consumer: "may consume ART-03 only after fresh positive, negative, bridge, Isabelle, and replay closure",
  },
};
write(dependencyGraphPath, json(dependencyGraph));

const bridge = {
  schemaVersion: 1,
  obligationId: "ART-03",
  requiredProperty,
  status: "OPEN",
  eligibleForDischarge: false,
  canonicalObligation: {
    index: ref(obligationIndexPath),
    theoremInventory: ref(theoremObligationsPath),
    classification: obligation.status.classification,
    discharged: obligation.status.discharged,
  },
  dependencies: {
    directPrerequisites: ["ART-02", "ART-04"],
    transitivePrerequisites: ["ART-01"],
    directConsumers: ["ART-06"],
    transitiveConsumers: ["ART-07"],
    graph: ref(dependencyGraphPath),
  },
  compilerTemplate: {
    output: ref(compilerOutputPath),
    artifacts: ref(compilerArtifactsPath),
    manifest: ref(bindingManifestPath),
    deterministicRootSha256: bindingManifest.deterministicRootSha256,
    subject: `${artifact.source}:${artifact.contract}`,
    byteLength: templateBytes.length,
    sha256: sha256(templateBytes),
  },
  constructorResolution: {
    fixture: ref(fixturePath),
    deterministicRootSha256: fixture.deterministicRootSha256,
    deploymentAddress: deployment.address,
    transactionHash: deployment.transactionHash,
    constructorInputSha256: deployment.constructor.creationInputSha256,
    exactImmutablePatch: deployment.immutablePatch.exactMatch,
    declaration: {
      astId: declarationAstId,
      name: decimalsDeclaration.name,
      canonicalType: decimalsDeclaration.canonicalType,
      value: decimalsDeclaration.value,
      encodedWord: expectedWord,
      sourcePath: decimalsDeclaration.sourcePath,
      sourceSpan: decimalsDeclaration.sourceSpan,
      location: { start: immutableStart, length: immutableLength },
    },
    runtime: {
      path: repoPath(resolvedRuntimePath),
      textFileSha256: sha256(read(resolvedRuntimePath)),
      byteLength: resolvedBytes.length,
      sha256: sha256(resolvedBytes),
      keccak256: deployment.runtime.keccak256,
      ethGetCodeSha256: deployment.immutablePatch.ethGetCodeSha256,
    },
  },
  executableObservation: {
    method: "decimals()",
    selector: `0x${decimalsSelector}`,
    expectedStatus: "EVMC_SUCCESS",
    expectedReturnWord: expectedWord,
    source: ref(storageSourcePath),
    proofSpec: ref(claimPath),
    module: "TRUST-ART-03-CONSTRUCTOR-RESOLVED-RUNTIME-BINDING-SPEC",
  },
  kRuntimeBinding: {
    canonicalBridge: ref(canonicalBridgePath),
    runtimeMacro: "#trustTrustTokenRuntime",
    macroRuntimeSha256: sha256(resolvedBytes),
  },
  semanticMutation: {
    mutationId: "ART-03-MUT-DECIMALS-IMMUTABLE-001",
    kind: "EXECUTABLE_SEMANTIC_MUTANT",
    declarationAstId,
    immutableRange: { start: immutableStart, length: immutableLength },
    byteOffset: mutationByteOffset,
    canonicalByte: "0x12",
    mutantByte: "0x13",
    canonicalWord: expectedWord,
    mutantWord,
    mutantRuntimeSha256: sha256(mutantBytes),
    mutantBridge: ref(mutantBridgePath),
    mutantVerification: ref(mutantVerificationPath),
    expectedSemanticDifference: "the unchanged decimals() claim requires ABI uint8(18), while the same selector on the mutant returns ABI uint8(19)",
  },
  provenanceEvidence: {
    ledger: ref(proofLedgerPath),
    passRuns: ["RUN-BINDING-DIRECT-STANDARD-JSON-001", "RUN-FIXTURE-RESOLVED-001", "RUN-FIXTURE-RESOLVED-REPLAY-001"],
    nonclaim: "the fixture is a local constructor-resolved artifact and makes no live deployment, address, or topology claim",
  },
  tcb: {
    classification: "OPEN_PLACEHOLDER_PENDING_COORDINATOR_BINDING",
    canonicalIndexPlaceholder: canonicalLockPlaceholder,
    actualCurrentLock: ref(lockPath),
    runtimeBindingManifest: {
      ...ref(bindingManifestPath),
      dependencyLockSha256: bindingManifest.sourceIdentity.dependencyLockSha256,
    },
    productDrift: false,
    staticBlocker: false,
    binderPolicy: "the discharge binder replaces the OPEN placeholder with the actual current lock hash only when the row becomes DISCHARGED",
  },
};
write(bridgePath, json(bridge));

const theory = `theory ART_03_Constructor_Resolved_Runtime_Binding\n` +
`  imports ERC_TRUST.TRUST_Runtime_Bridge_Generated\n` +
`begin\n\n` +
`definition art03_constructor_fixture_root_sha256 :: string where\n` +
`  "art03_constructor_fixture_root_sha256 = ''${fixture.deterministicRootSha256}''"\n\n` +
`definition art03_resolved_runtime_sha256 :: string where\n` +
`  "art03_resolved_runtime_sha256 = ''${sha256(resolvedBytes)}''"\n\n` +
`definition art03_mutant_runtime_sha256 :: string where\n` +
`  "art03_mutant_runtime_sha256 = ''${sha256(mutantBytes)}''"\n\n` +
`definition art03_runtime_byte_length :: nat where\n` +
`  "art03_runtime_byte_length = ${resolvedBytes.length}"\n\n` +
`definition art03_decimals_ast_id :: nat where\n` +
`  "art03_decimals_ast_id = ${declarationAstId}"\n\n` +
`definition art03_decimals_selector :: string where\n` +
`  "art03_decimals_selector = ''0x${decimalsSelector}''"\n\n` +
`definition art03_decimals_value :: nat where\n` +
`  "art03_decimals_value = 18"\n\n` +
`definition art03_decimals_word :: string where\n` +
`  "art03_decimals_word = ''${expectedWord}''"\n\n` +
`definition art03_decimals_immutable_range :: "nat * nat" where\n` +
`  "art03_decimals_immutable_range = (${immutableStart}, ${immutableLength})"\n\n` +
`definition art03_mutation_byte_offset :: nat where\n` +
`  "art03_mutation_byte_offset = ${mutationByteOffset}"\n\n` +
`theorem constructor_resolved_local_runtime_is_hash_bound:\n` +
`  "art03_constructor_fixture_root_sha256 = constructor_fixture_root_sha256 \\<and>\n` +
`   art03_resolved_runtime_sha256 = native_resolved_runtime_sha256 \\<and>\n` +
`   art03_decimals_ast_id = 622 \\<and>\n` +
`   art03_decimals_selector = ''0x313ce567'' \\<and>\n` +
`   art03_decimals_value = 18 \\<and>\n` +
`   art03_decimals_word = ''${expectedWord}'' \\<and>\n` +
`   art03_decimals_immutable_range = (6970, 32) \\<and>\n` +
`   fst art03_decimals_immutable_range + snd art03_decimals_immutable_range \\<le> art03_runtime_byte_length \\<and>\n` +
`   art03_mutation_byte_offset = fst art03_decimals_immutable_range + snd art03_decimals_immutable_range - 1 \\<and>\n` +
`   art03_resolved_runtime_sha256 \\<noteq> art03_mutant_runtime_sha256"\n` +
`  by (simp add: art03_constructor_fixture_root_sha256_def constructor_fixture_root_sha256_def\n` +
`      art03_resolved_runtime_sha256_def native_resolved_runtime_sha256_def\n` +
`      art03_mutant_runtime_sha256_def art03_runtime_byte_length_def\n` +
`      art03_decimals_ast_id_def art03_decimals_selector_def art03_decimals_value_def\n` +
`      art03_decimals_word_def art03_decimals_immutable_range_def art03_mutation_byte_offset_def)\n\n` +
`ML \\<open>\n` +
`  val row_fact = @{thm constructor_resolved_local_runtime_is_hash_bound};\n` +
`  val row_oracles = Thm_Deps.all_oracles [row_fact];\n` +
`  val _ = if null row_oracles then () else\n` +
`    error ("ART-03 proof audit found " ^ string_of_int (length row_oracles) ^ " oracle dependencies");\n` +
`  val audit_report =\n` +
`    "status=PASS\\n" ^\n` +
`    "qualified_theorem=ART_03_Constructor_Resolved_Runtime_Binding.constructor_resolved_local_runtime_is_hash_bound\\n" ^\n` +
`    "oracle_dependency_count=0\\n";\n` +
`  val _ = Export.export \\<^theory>\n` +
`    \\<^path_binding>\\<open>erc-trust-art-03/proof-trust.txt\\<close> [XML.Text audit_report];\n` +
`\\<close>\n\n` +
`end\n`;
write(theoryPath, theory);

const blockers = [
  "fresh closed positive KEVM graph",
  "fresh terminal semantic negative graph showing uint8(19) against the unchanged uint8(18) requirement",
  "serial Isabelle clean build and oracle-free export",
  "repository-owned independent replay",
];

const proofInputs = {
  claim: ref(claimPath),
  positiveVerification: ref(positiveVerificationPath),
  negativeRuntimeBridge: { ...ref(mutantBridgePath), mutationId: bridge.semanticMutation.mutationId },
  negativeVerification: ref(mutantVerificationPath),
};
const skeleton = {
  schemaVersion: 1,
  obligationId: "ART-03",
  requiredProperty,
  status: "OPEN",
  eligibleForDischarge: false,
  tcbBinding: {
    classification: bridge.tcb.classification,
    canonicalPlaceholderSha256: bridge.tcb.canonicalIndexPlaceholder.sha256,
    actualCurrentLock: bridge.tcb.actualCurrentLock,
    runtimeBindingManifestDependencyLockSha256: bridge.tcb.runtimeBindingManifest.dependencyLockSha256,
    productDrift: false,
    blocker: false,
  },
  proofSpec: {
    path: repoPath(claimPath),
    module: bridge.executableObservation.module,
    claimId: null,
    sha256: sha256(claimBytes),
  },
  proofInputs,
  positive: {
    definitionKoreSha256: null,
    compiledJsonSha256: null,
    graph: null,
    requiredExitCode: 0,
    requiredWitnesses: ["EVMC_SUCCESS", expectedWord, "unchanged token storage and empty log/substate"],
  },
  negative: {
    mutationId: bridge.semanticMutation.mutationId,
    mutationKind: bridge.semanticMutation.kind,
    definitionKoreSha256: null,
    compiledJsonSha256: null,
    graph: null,
    requiredExitCode: 1,
    requiredWitness: `${mutantWord} terminal output contradicts the unchanged ${expectedWord} claim requirement`,
  },
  bridge: { ...ref(bridgePath), reverseCheck: "formal/kevm/row-bundles/art-03/reverse-check.py" },
  isabelle: {
    theoryPath: repoPath(theoryPath),
    theoremName: requiredProperty,
    session: "ERC_TRUST_ART_03",
    buildStatus: "NOT_RUN_IN_WORKER",
    closureReport: null,
  },
  replay: { status: "NOT_RUN", report: null, traceRoot: null, proofRoot: null },
  blockers,
  residualNonclaims: [
    "Static reconstruction and fixture capture do not prove KEVM execution or Isabelle closure.",
    "The local fixture does not identify a live deployment, address, or topology.",
    "This row does not prove solc correctness, ART-02, ART-04, ART-06, or ART-07.",
  ],
};
write(skeletonPath, json(skeleton));

const runnerTools = [
  "run-row-bundle.sh",
  "validate-bundle.py",
  "analyze-row-proof.mjs",
  "curate-row-output.py",
  "verify-curated-evidence.py",
].map((name) => ref(join(sharedRunnerRoot, name)));
const runnerDescriptor = {
  schemaVersion: 1,
  obligationId: "ART-03",
  status: "OPEN",
  eligibleForDischarge: false,
  tcbBinding: {
    classification: bridge.tcb.classification,
    actualCurrentLock: bridge.tcb.actualCurrentLock,
    blocker: false,
  },
  interfacePilot: ["FAIL-05", "ART-02"],
  repositoryOwnedTools: runnerTools,
  inputs: {
    skeletonBundle: ref(skeletonPath),
    claim: ref(claimPath),
    positiveVerification: ref(positiveVerificationPath),
    negativeVerification: ref(mutantVerificationPath),
    negativeRuntimeBridge: ref(mutantBridgePath),
    isabelleClosureScript: ref(join(rowRoot, "isabelle", "run-closure.ps1")),
  },
  coordinatorSuppliedAfterAuthoritativeRuns: {
    completedBundlePath: null,
    positiveDefinitionDirectory: null,
    negativeDefinitionDirectory: null,
    isabelleClosureReport: null,
    outputDirectory: null,
    curatedEvidenceDirectory: null,
    replayReport: null,
  },
  authoritativeCommandTemplate: [
    "bash",
    "formal/kevm/row-bundles/run-row-bundle.sh",
    "--bundle", "<completed-art-03-bundle.json>",
    "--positive-definition", "<exact-positive-definition-directory>",
    "--negative-definition", "<exact-negative-definition-directory>",
    "--output-directory", "<fresh-output-directory>",
    "--report", "<fresh-replay-report.json>",
    "--curated-evidence-directory", "<fresh-curated-evidence-directory>",
    "--isabelle-report", "<fresh-art-03-isabelle-closure-report.json>",
    "--side-timeout-seconds", "<positive-integer>",
    "--no-use-booster",
  ],
  preflightCommands: [
    ["node", "formal/kevm/row-bundles/art-03/generate-row-artifacts.mjs"],
    ["python3", "formal/kevm/row-bundles/art-03/reverse-check.py"],
  ],
  definitionCompileCommandTemplates: {
    positive: [
      "kevm", "kompile-spec", "formal/kevm/trust-runtime-verification.k",
      "--main-module", "TRUST-RUNTIME-VERIFICATION",
      "--target", "haskell", "--emit-json",
      "--output-definition", "<fresh-positive-definition-directory>",
    ],
    negative: [
      "kevm", "kompile-spec", "formal/kevm/row-bundles/art-03/generated/mutant-runtime-verification.k",
      "--main-module", "TRUST-RUNTIME-VERIFICATION",
      "--target", "haskell", "--emit-json",
      "--output-definition", "<fresh-negative-definition-directory>",
    ],
  },
  isabelleClosureCommandTemplate: [
    "powershell", "-File", "formal/kevm/row-bundles/art-03/isabelle/run-closure.ps1",
    "-IsabelleRoot", "<exact-isabelle-root>",
    "-AdsFunctor", "<exact-ads-functor-directory>",
    "-FormalFoundation", "<exact-formal-foundation-directory>",
    "-OutputDirectory", "<fresh-isabelle-output-directory>",
  ],
  completedBundleValidationCommandTemplate: [
    "python3", "formal/kevm/row-bundles/validate-bundle.py", "<completed-art-03-bundle.json>",
  ],
  proofFacts: { claimId: null, positiveDefinitionHashes: null, positiveGraph: null, negativeDefinitionHashes: null, negativeGraph: null, isabelleBuild: null, replay: null },
};
write(runnerDescriptorPath, json(runnerDescriptor));

const rowManifest = {
  schemaVersion: 1,
  obligationId: "ART-03",
  requiredProperty,
  status: "OPEN",
  eligibleForDischarge: false,
  tcbBinding: {
    classification: bridge.tcb.classification,
    canonicalPlaceholderSha256: bridge.tcb.canonicalIndexPlaceholder.sha256,
    actualCurrentLock: bridge.tcb.actualCurrentLock,
    productDrift: false,
    blocker: false,
  },
  bridge: ref(bridgePath),
  dependencyGraph: ref(dependencyGraphPath),
  proofSpec: { ...ref(claimPath), module: bridge.executableObservation.module },
  generated: [mutantBridgePath, mutantVerificationPath].map(ref),
  theorem: { ...ref(theoryPath), session: "ERC_TRUST_ART_03", name: requiredProperty, buildStatus: "NOT_RUN_IN_WORKER" },
  skeletonBundle: ref(skeletonPath),
  runnerDescriptor: ref(runnerDescriptorPath),
  proofFacts: { claimId: null, positiveGraph: null, negativeGraph: null, isabelleClosure: null, replay: null },
};
write(rowManifestPath, json(rowManifest));

process.stdout.write(`${JSON.stringify({
  status: "STATIC_ROW_INPUTS_PASS_OPEN",
  eligibleForDischarge: false,
  obligationId: "ART-03",
  requiredProperty,
  tcbBindingClassification: bridge.tcb.classification,
  directPrerequisites: bridge.dependencies.directPrerequisites,
  resolvedRuntimeSha256: bridge.constructorResolution.runtime.sha256,
  immutableRange: bridge.semanticMutation.immutableRange,
  mutationByteOffset,
  mutantRuntimeSha256: bridge.semanticMutation.mutantRuntimeSha256,
  bridge: ref(bridgePath),
  theory: ref(theoryPath),
  bundleSkeleton: ref(skeletonPath),
  runnerDescriptor: ref(runnerDescriptorPath),
  rowManifest: ref(rowManifestPath),
}, null, 2)}\n`);

