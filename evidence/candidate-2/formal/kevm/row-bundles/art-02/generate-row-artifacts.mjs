import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const rowRoot = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(rowRoot, "../../../..");
const bindingRoot = join(repositoryRoot, "evidence", "end-to-end-refinement", "runtime-binding");
const bindingManifestPath = join(bindingRoot, "manifest.json");
const compilerOutputPath = join(bindingRoot, "native", "standard-json-output.json");
const compilerArtifactsPath = join(bindingRoot, "native", "bridge-artifacts.json");
const fixturePath = join(bindingRoot, "resolved", "fixture.json");
const resolvedRuntimePath = join(bindingRoot, "resolved", "native", "TrustToken.hex");
const canonicalBridgePath = join(repositoryRoot, "formal", "kevm", "generated", "trust-runtime-bridge.k");
const generatedRoot = join(rowRoot, "generated");
const mutantBridgePath = join(generatedRoot, "mutant-runtime-bridge.k");
const mutantVerificationPath = join(generatedRoot, "mutant-runtime-verification.k");
const bridgePath = join(rowRoot, "bridge", "row-bridge.json");
const rowManifestPath = join(rowRoot, "bridge", "row-manifest.json");
const theoryPath = join(rowRoot, "isabelle", "ART_02_Compiler_Output_Runtime_Binding.thy");

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

const compilerOutputBytes = readFileSync(compilerOutputPath);
const compilerArtifactsBytes = readFileSync(compilerArtifactsPath);
const fixtureBytes = readFileSync(fixturePath);
const bindingManifestBytes = readFileSync(bindingManifestPath);
const canonicalBridgeBytes = readFileSync(canonicalBridgePath);
const compilerOutput = JSON.parse(compilerOutputBytes);
const compilerArtifacts = JSON.parse(compilerArtifactsBytes);
const fixture = JSON.parse(fixtureBytes);
const bindingManifest = JSON.parse(bindingManifestBytes);
const artifact = compilerArtifacts.find((entry) => entry.contract === "TrustToken");
const deployment = fixture.deployments.find((entry) => entry.label === "TrustToken");
if (!artifact || !deployment) throw new Error("TrustToken compiler or fixture subject missing");

const deployedBytecode = compilerOutput.contracts[artifact.source][artifact.contract].evm.deployedBytecode;
const templateHex = normalizeHex(`0x${deployedBytecode.object}`);
const templateBytes = Buffer.from(templateHex.slice(2), "hex");
if (
  templateBytes.length !== artifact.runtimeTemplate.byteLength
  || sha256(templateBytes) !== artifact.runtimeTemplate.sha256
  || JSON.stringify(deployedBytecode.immutableReferences) !== JSON.stringify(artifact.runtimeTemplate.immutableReferences)
) throw new Error("compiler runtime template drift");

const patchedBytes = Buffer.from(templateBytes);
const patchLocations = [];
for (const declaration of deployment.immutablePatch.declarations) {
  const word = Buffer.from(normalizeHex(declaration.encodedWord).slice(2), "hex");
  for (const location of declaration.locations) {
    if (word.length !== location.length) throw new Error(`immutable length mismatch: ${declaration.name}`);
    word.copy(patchedBytes, location.start);
    patchLocations.push({
      astId: declaration.astId,
      name: declaration.name,
      start: location.start,
      length: location.length,
      encodedWordSha256: sha256(word),
    });
  }
}
const resolvedHex = normalizeHex(readFileSync(resolvedRuntimePath, "utf8"));
const resolvedBytes = Buffer.from(resolvedHex.slice(2), "hex");
if (!patchedBytes.equals(resolvedBytes)) throw new Error("compiler template plus immutable patch does not equal resolved runtime");
if (sha256(resolvedBytes) !== deployment.runtime.sha256) throw new Error("resolved runtime SHA-256 drift");

const canonicalBridge = canonicalBridgeBytes.toString("utf8");
const macroPrefix = "rule #trustTrustTokenRuntime() => #parseByteStack(\"";
const macroStart = canonicalBridge.indexOf(macroPrefix);
if (macroStart < 0) throw new Error("TrustToken runtime macro missing");
const runtimeStart = macroStart + macroPrefix.length;
const runtimeEnd = canonicalBridge.indexOf("\")", runtimeStart);
if (runtimeEnd < 0) throw new Error("TrustToken runtime macro unterminated");
const macroRuntime = normalizeHex(canonicalBridge.slice(runtimeStart, runtimeEnd));
if (macroRuntime !== resolvedHex) throw new Error("generated K runtime macro does not equal resolved compiler runtime");

const canonicalNeedle = "6004361015610012575f80fd5b";
const mutantNeedle = "6004361015610012575f80f35b";
const runtimeNeedleOffset = macroRuntime.slice(2).indexOf(canonicalNeedle);
if (runtimeNeedleOffset < 0 || macroRuntime.slice(2).indexOf(canonicalNeedle, runtimeNeedleOffset + 1) >= 0) {
  throw new Error("empty-calldata dispatcher branch is not unique in TrustToken runtime");
}
const rawRuntime = macroRuntime.slice(2);
const mutationHexOffset = runtimeNeedleOffset + canonicalNeedle.indexOf("fd5b");
const mutantRuntime = `0x${rawRuntime.slice(0, mutationHexOffset)}f3${rawRuntime.slice(mutationHexOffset + 2)}`;
if (mutantRuntime.length !== macroRuntime.length) throw new Error("runtime mutant length changed");
const mutationByteOffset = mutationHexOffset / 2;
if (resolvedBytes[mutationByteOffset] !== 0xfd || Buffer.from(mutantRuntime.slice(2), "hex")[mutationByteOffset] !== 0xf3) {
  throw new Error("runtime mutation is not the intended REVERT-to-RETURN opcode substitution");
}

const mutantBridge = `${canonicalBridge.slice(0, runtimeStart)}${mutantRuntime}${canonicalBridge.slice(runtimeEnd)}`;
write(mutantBridgePath, mutantBridge);
write(mutantVerificationPath, `requires "mutant-runtime-bridge.k"\nrequires "driver.md"\n\nmodule TRUST-RUNTIME-VERIFICATION\n    imports TRUST-RUNTIME-BRIDGE\n    imports ETHEREUM-SIMULATION\nendmodule\n`);

const bridge = {
  schemaVersion: 1,
  obligationId: "ART-02",
  compilerOutput: {
    path: repoPath(compilerOutputPath),
    fileSha256: sha256(compilerOutputBytes),
    subject: `${artifact.source}:${artifact.contract}`,
    templateByteLength: templateBytes.length,
    templateSha256: sha256(templateBytes),
    immutableReferences: deployedBytecode.immutableReferences,
  },
  compilerBinding: {
    manifestPath: repoPath(bindingManifestPath),
    manifestSha256: sha256(bindingManifestBytes),
    deterministicRootSha256: bindingManifest.deterministicRootSha256,
  },
  compilerArtifacts: {
    path: repoPath(compilerArtifactsPath),
    fileSha256: sha256(compilerArtifactsBytes),
    runtimeTemplateSha256: artifact.runtimeTemplate.sha256,
  },
  constructorResolution: {
    fixturePath: repoPath(fixturePath),
    fixtureSha256: sha256(fixtureBytes),
    deterministicRootSha256: fixture.deterministicRootSha256,
    immutablePatchExact: deployment.immutablePatch.exactMatch,
    patchLocations: patchLocations.sort((left, right) => left.start - right.start),
    resolvedRuntimePath: repoPath(resolvedRuntimePath),
    resolvedRuntimeByteLength: resolvedBytes.length,
    resolvedRuntimeSha256: sha256(resolvedBytes),
  },
  kRuntimeBinding: {
    canonicalBridgePath: repoPath(canonicalBridgePath),
    canonicalBridgeSha256: sha256(canonicalBridgeBytes),
    runtimeMacro: "#trustTrustTokenRuntime",
    macroRuntimeSha256: sha256(Buffer.from(macroRuntime.slice(2), "hex")),
  },
  semanticMutation: {
    mutationId: "ART-02-MUT-RUNTIME-BYTE-001",
    kind: "EXECUTABLE_SEMANTIC_MUTANT",
    byteOffset: mutationByteOffset,
    canonicalOpcode: "0xfd",
    mutantOpcode: "0xf3",
    branch: "empty-calldata dispatcher guard",
    expectedSemanticDifference: "EVMC_REVERT becomes EVMC_SUCCESS while the unchanged claim still requires EVMC_REVERT",
    mutantRuntimeSha256: sha256(Buffer.from(mutantRuntime.slice(2), "hex")),
    mutantBridgePath: repoPath(mutantBridgePath),
    mutantBridgeSha256: sha256(Buffer.from(mutantBridge)),
    mutantVerificationPath: repoPath(mutantVerificationPath),
    mutantVerificationSha256: sha256(Buffer.from(readFileSync(mutantVerificationPath))),
  },
};
write(bridgePath, json(bridge));

const theory = `theory ART_02_Compiler_Output_Runtime_Binding\n` +
`  imports ERC_TRUST.TRUST_Runtime_Bridge_Generated\n` +
`begin\n\n` +
`definition compiler_runtime_template_sha256 :: string where\n` +
`  "compiler_runtime_template_sha256 = ''${bridge.compilerOutput.templateSha256}''"\n\n` +
`definition row_compiler_binding_root_sha256 :: string where\n` +
`  "row_compiler_binding_root_sha256 = ''${bridge.compilerBinding.deterministicRootSha256}''"\n\n` +
`definition row_constructor_fixture_root_sha256 :: string where\n` +
`  "row_constructor_fixture_root_sha256 = ''${bridge.constructorResolution.deterministicRootSha256}''"\n\n` +
`definition patched_compiler_runtime_sha256 :: string where\n` +
`  "patched_compiler_runtime_sha256 = ''${bridge.constructorResolution.resolvedRuntimeSha256}''"\n\n` +
`definition resolved_runtime_sha256 :: string where\n` +
`  "resolved_runtime_sha256 = ''${bridge.constructorResolution.resolvedRuntimeSha256}''"\n\n` +
`definition generated_runtime_sha256 :: string where\n` +
`  "generated_runtime_sha256 = ''${bridge.kRuntimeBinding.macroRuntimeSha256}''"\n\n` +
`definition runtime_byte_mutant_sha256 :: string where\n` +
`  "runtime_byte_mutant_sha256 = ''${bridge.semanticMutation.mutantRuntimeSha256}''"\n\n` +
`definition compiler_runtime_byte_length :: nat where\n` +
`  "compiler_runtime_byte_length = ${bridge.compilerOutput.templateByteLength}"\n\n` +
`definition resolved_runtime_byte_length :: nat where\n` +
`  "resolved_runtime_byte_length = ${bridge.constructorResolution.resolvedRuntimeByteLength}"\n\n` +
`definition runtime_mutation_byte_offset :: nat where\n` +
`  "runtime_mutation_byte_offset = ${bridge.semanticMutation.byteOffset}"\n\n` +
`definition immutable_patch_ranges :: "(nat * nat) list" where\n` +
`  "immutable_patch_ranges = [${bridge.constructorResolution.patchLocations.map((entry) => `(${entry.start}, ${entry.length})`).join(", ")}]"\n\n` +
`theorem compiler_output_runtime_bytes_are_hash_bound:\n` +
`  "row_compiler_binding_root_sha256 = compiler_binding_root_sha256 \\<and>\n` +
`   row_constructor_fixture_root_sha256 = constructor_fixture_root_sha256 \\<and>\n` +
`   length immutable_patch_ranges = ${bridge.constructorResolution.patchLocations.length} \\<and>\n` +
`   map fst immutable_patch_ranges = [${bridge.constructorResolution.patchLocations.map((entry) => entry.start).join(", ")}] \\<and>\n` +
`   (\\<forall>(start, width) \\<in> set immutable_patch_ranges. width = 32 \\<and> start + width \\<le> compiler_runtime_byte_length) \\<and>\n` +
`   compiler_runtime_byte_length = resolved_runtime_byte_length \\<and>\n` +
`   patched_compiler_runtime_sha256 = native_resolved_runtime_sha256 \\<and>\n` +
`   resolved_runtime_sha256 = generated_runtime_sha256 \\<and>\n` +
`   generated_runtime_sha256 = native_resolved_runtime_sha256 \\<and>\n` +
`   resolved_runtime_sha256 \\<noteq> runtime_byte_mutant_sha256 \\<and>\n` +
`   runtime_mutation_byte_offset < resolved_runtime_byte_length"\n` +
`  by (simp add: row_compiler_binding_root_sha256_def\n` +
`      row_constructor_fixture_root_sha256_def compiler_binding_root_sha256_def\n` +
`      constructor_fixture_root_sha256_def immutable_patch_ranges_def\n` +
`      compiler_runtime_byte_length_def resolved_runtime_byte_length_def\n` +
`      patched_compiler_runtime_sha256_def native_resolved_runtime_sha256_def\n` +
`      resolved_runtime_sha256_def\n` +
`      generated_runtime_sha256_def runtime_byte_mutant_sha256_def\n` +
`      runtime_mutation_byte_offset_def)\n\n` +
`ML \\<open>\n` +
`  val row_fact = @{thm compiler_output_runtime_bytes_are_hash_bound};\n` +
`  val row_oracles = Thm_Deps.all_oracles [row_fact];\n` +
`  val _ =\n` +
`    if null row_oracles then ()\n` +
`    else error\n` +
`      ("ART-02 proof audit found " ^\n` +
`       string_of_int (length row_oracles) ^ " oracle dependencies");\n` +
`  val audit_report =\n` +
`    "status=PASS\\n" ^\n` +
`    "qualified_theorem=ART_02_Compiler_Output_Runtime_Binding.compiler_output_runtime_bytes_are_hash_bound\\n" ^\n` +
`    "oracle_dependency_count=0\\n";\n` +
`  val _ = Export.export \\<^theory>\n` +
`    \\<^path_binding>\\<open>erc-trust-art-02/proof-trust.txt\\<close>\n` +
`    [XML.Text audit_report];\n` +
`\\<close>\n\n` +
`end\n`;
write(theoryPath, theory);

const rowManifest = {
  schemaVersion: 1,
  obligationId: "ART-02",
  bridge: { path: repoPath(bridgePath), sha256: sha256(readFileSync(bridgePath)) },
  theorem: {
    path: repoPath(theoryPath),
    sha256: sha256(readFileSync(theoryPath)),
    session: "ERC_TRUST_ART_02",
    name: "compiler_output_runtime_bytes_are_hash_bound",
  },
  proofSpec: {
    path: repoPath(join(rowRoot, "claim.k")),
    sha256: sha256(readFileSync(join(rowRoot, "claim.k"))),
    module: "TRUST-ART-02-COMPILER-OUTPUT-RUNTIME-BINDING-SPEC",
  },
  generated: [mutantBridgePath, mutantVerificationPath].map((path) => ({
    path: repoPath(path),
    sha256: sha256(readFileSync(path)),
  })),
};
write(rowManifestPath, json(rowManifest));

process.stdout.write(`${JSON.stringify({
  status: "PASS",
  bridge: repoPath(bridgePath),
  bridgeSha256: sha256(readFileSync(bridgePath)),
  resolvedRuntimeSha256: bridge.constructorResolution.resolvedRuntimeSha256,
  mutantRuntimeSha256: bridge.semanticMutation.mutantRuntimeSha256,
  mutationByteOffset,
  theory: repoPath(theoryPath),
  theorySha256: sha256(readFileSync(theoryPath)),
  rowManifest: repoPath(rowManifestPath),
  rowManifestSha256: sha256(readFileSync(rowManifestPath)),
}, null, 2)}\n`);
