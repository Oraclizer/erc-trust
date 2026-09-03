import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

import { resolvePinnedSolc } from "../../../../scripts/lib/resolve-pinned-solc.mjs";

const bundleRoot = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(bundleRoot, "../../../..");
const evidenceRoot = join(repositoryRoot, "evidence", "end-to-end-refinement", "row-bundles", "state-04");
const negativeRoot = join(bundleRoot, "negative");
const bridgeRoot = join(bundleRoot, "bridge");
const tokenSourcePath = "implementation/src/TrustToken.sol";
const standardInputPath = join(repositoryRoot, "evidence", "end-to-end-refinement", "runtime-binding", "native", "standard-json-input.json");
const canonicalOutputPath = join(repositoryRoot, "evidence", "end-to-end-refinement", "runtime-binding", "native", "standard-json-output.json");
const fixturePath = join(repositoryRoot, "evidence", "end-to-end-refinement", "runtime-binding", "resolved", "fixture.json");
const canonicalBridgePath = join(repositoryRoot, "formal", "kevm", "generated", "trust-runtime-bridge.k");
const lockPath = join(repositoryRoot, "formal", "kevm", "dependencies.lock.json");
const planPath = join(evidenceRoot, "negative", "mutation-plan.json");
const positiveClaimPath = join(bundleRoot, "positive", "claim.k");
const closureTheoryPath = join(bundleRoot, "isabelle", "STATE_04_Closure.thy");
const proofAuditTheoryPath = join(bundleRoot, "isabelle", "STATE_04_Proof_Audit.thy");
const rowManifestPath = join(bridgeRoot, "row-manifest.json");

const outputIndex = process.argv.indexOf("--output-directory");
if (outputIndex < 0 || !process.argv[outputIndex + 1]) {
  throw new Error("usage: node prepare-mutant.mjs --output-directory C:\\\\tmp\\\\unique-new-directory");
}
const outputDirectory = resolve(process.argv[outputIndex + 1]);
if (!existsSync(outputDirectory) || !statSync(outputDirectory).isDirectory() || readdirSync(outputDirectory).length !== 0) {
  throw new Error(`output directory must be a pre-created empty unique directory: ${outputDirectory}`);
}

const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const repoPath = (path) => relative(repositoryRoot, path).split(sep).join("/");
const write = (path, value) => { mkdirSync(dirname(path), { recursive: true }); writeFileSync(path, value); };
const writeJson = (path, value) => write(path, `${JSON.stringify(value, null, 2)}\n`);

const lock = JSON.parse(readFileSync(lockPath, "utf8"));
const solc = lock.components.solc;
const resolvedSolc = resolvePinnedSolc(solc);
const plan = JSON.parse(readFileSync(planPath, "utf8"));
const canonicalInputBytes = readFileSync(standardInputPath);
const canonicalInput = JSON.parse(canonicalInputBytes);
const canonicalSource = canonicalInput.sources[tokenSourcePath]?.content;
if (!canonicalSource || sha256(Buffer.from(canonicalSource, "utf8")) !== plan.canonicalSource.sha256) throw new Error("canonical source identity drift");
if ((canonicalSource.match(new RegExp(plan.uniqueAnchor.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "g")) ?? []).length !== 1) throw new Error("STATE-04 mutation anchor is not unique");
const mutantSource = canonicalSource.replace(plan.uniqueAnchor, plan.replacement);
if ((mutantSource.match(/_restricted\[account\] \? 0 : _frozen\[account\]; \/\/ STATE-04 semantic mutant/g) ?? []).length !== 1) throw new Error("STATE-04 replacement missing or non-unique");
const mutantInput = structuredClone(canonicalInput);
mutantInput.sources[tokenSourcePath].content = mutantSource;
const mutantInputBytes = Buffer.from(`${JSON.stringify(mutantInput)}\n`, "utf8");
const mutantInputPath = join(evidenceRoot, "negative", "standard-json-input.json");
const mutantOutputPath = join(evidenceRoot, "negative", "standard-json-output.json");
const mutantSourcePath = join(evidenceRoot, "negative", "TrustToken.STATE-04-mutant.sol");
write(mutantInputPath, mutantInputBytes); write(mutantSourcePath, mutantSource);

const rawOutput = execFileSync("wsl.exe", ["-d", resolvedSolc.distribution, "-e", resolvedSolc.binaryPath, "--standard-json"], { input: mutantInputBytes, maxBuffer: 256 * 1024 * 1024 });
const brace = rawOutput.indexOf(0x7b); if (brace < 0) throw new Error("solc returned no JSON object");
const outputBytes = rawOutput.subarray(brace); const output = JSON.parse(outputBytes.toString("utf8"));
const fatal = (output.errors ?? []).filter((entry) => entry.severity === "error"); if (fatal.length) throw new Error(`mutant compilation failed: ${fatal.map((entry) => entry.formattedMessage).join("\n")}`);
write(mutantOutputPath, outputBytes);
const contract = output.contracts[tokenSourcePath]?.TrustToken; if (!contract) throw new Error("mutant TrustToken output missing");
if (contract.evm.methodIdentifiers["getFrozenTokens(address)"] !== "158b1a57") throw new Error("getter selector drift");
const layout = Object.fromEntries(contract.storageLayout.storage.map((entry) => [entry.label, Number(entry.slot)]));
if (layout._frozen !== 5 || layout._restricted !== 6) throw new Error("mutant storage layout drift");
const fixture = JSON.parse(readFileSync(fixturePath, "utf8")); const deployment = fixture.deployments.find((entry) => entry.label === "TrustToken"); if (!deployment) throw new Error("TrustToken fixture missing");
const encoded = new Map(deployment.immutablePatch.declarations.map((entry) => [String(entry.astId), entry.encodedWord.slice(2)]));
const templateHex = contract.evm.deployedBytecode.object; if (!/^[0-9a-f]+$/.test(templateHex)) throw new Error("invalid runtime template");
const runtime = Buffer.from(templateHex, "hex"); const references = contract.evm.deployedBytecode.immutableReferences ?? {};
if (Object.keys(references).length !== encoded.size) throw new Error("immutable reference count drift");
for (const [astId, locations] of Object.entries(references)) { const word = Buffer.from(encoded.get(astId) ?? "", "hex"); if (word.length !== 32) throw new Error(`immutable identity drift: ${astId}`); for (const location of locations) { if (location.length !== 32 || location.start + 32 > runtime.length || runtime.subarray(location.start, location.start + 32).some((byte) => byte !== 0)) throw new Error(`immutable location drift: ${astId}`); word.copy(runtime, location.start); } }
const mutantRuntimeHex = `0x${runtime.toString("hex")}`; const mutantRuntimePath = join(evidenceRoot, "negative", "TrustToken.runtime.hex"); write(mutantRuntimePath, `${mutantRuntimeHex}\n`);
const canonicalRuntime = readFileSync(join(repositoryRoot, ...deployment.runtime.path.split("/")), "utf8").trim(); if (canonicalRuntime === mutantRuntimeHex) throw new Error("mutation did not alter resolved runtime"); if (runtime.length > 24576) throw new Error("mutant exceeds EIP-170");
const canonicalBridge = readFileSync(canonicalBridgePath, "utf8"); const runtimeRule = /rule #trustTrustTokenRuntime\(\) => #parseByteStack\("0x[0-9a-f]+"\)/g; if ((canonicalBridge.match(runtimeRule) ?? []).length !== 1) throw new Error("canonical runtime bridge rule is not unique");
const mutantBridge = canonicalBridge.replace(runtimeRule, `rule #trustTrustTokenRuntime() => #parseByteStack("${mutantRuntimeHex}")`);
const mutantBridgePath = join(negativeRoot, "mutant-runtime-bridge.k"); const mutantVerificationPath = join(negativeRoot, "mutant-runtime-verification.k");
write(mutantBridgePath, mutantBridge); write(mutantVerificationPath, 'requires "mutant-runtime-bridge.k"\nrequires "driver.md"\n\nmodule TRUST-RUNTIME-VERIFICATION\n  imports TRUST-RUNTIME-BRIDGE\n  imports ETHEREUM-SIMULATION\nendmodule\n');
const canonicalOutputBytes = readFileSync(canonicalOutputPath); const canonicalToken = JSON.parse(canonicalOutputBytes).contracts[tokenSourcePath].TrustToken;
const mutationPath = join(evidenceRoot, "negative", "mutation.json");
const mutation = { schemaVersion: 1, obligationId: "STATE-04", mutationId: plan.mutationId, status: "COMPILED_PENDING_KEVM", compiler: { version: solc.version, binarySha256: solc.binarySha256, distribution: resolvedSolc.distribution, settingsSha256: sha256(Buffer.from(JSON.stringify(mutantInput.settings), "utf8")), canonicalInputSha256: sha256(canonicalInputBytes), mutantInputPath: repoPath(mutantInputPath), mutantInputSha256: sha256(mutantInputBytes), mutantOutputPath: repoPath(mutantOutputPath), mutantOutputSha256: sha256(outputBytes) }, source: { canonicalSha256: sha256(Buffer.from(canonicalSource, "utf8")), mutantPath: repoPath(mutantSourcePath), mutantSha256: sha256(Buffer.from(mutantSource, "utf8")), anchorSha256: sha256(Buffer.from(plan.uniqueAnchor, "utf8")), replacementSha256: sha256(Buffer.from(plan.replacement, "utf8")) }, runtime: { canonicalResolvedSha256: sha256(Buffer.from(canonicalRuntime.slice(2), "hex")), mutantTemplateSha256: sha256(Buffer.from(templateHex, "hex")), mutantResolvedPath: repoPath(mutantRuntimePath), mutantResolvedSha256: sha256(runtime), mutantByteLength: runtime.length, eip170MarginBytes: 24576 - runtime.length, immutableReferences: references }, bridge: { canonicalSha256: sha256(Buffer.from(canonicalBridge, "utf8")), mutantPath: repoPath(mutantBridgePath), mutantSha256: sha256(Buffer.from(mutantBridge, "utf8")), verificationPath: repoPath(mutantVerificationPath), verificationSha256: sha256(readFileSync(mutantVerificationPath)) } };
writeJson(mutationPath, mutation);
const rowBridgePath = join(bridgeRoot, "row-bridge.json");
const rowBridge = { schemaVersion: 1, obligationId: "STATE-04", requiredProperty: "freeze_and_restriction_are_independent", status: "COMPILED_MUTANT_PENDING_KEVM_ISABELLE_AND_REPLAY", compilerBinding: { canonicalOutputPath: repoPath(canonicalOutputPath), canonicalOutputSha256: sha256(canonicalOutputBytes), canonicalStorageLayoutSha256: sha256(Buffer.from(JSON.stringify(canonicalToken.storageLayout), "utf8")), methodSignature: "getFrozenTokens(address)", methodSelector: "0x158b1a57", pinnedSolcVersion: solc.version, pinnedSolcBinarySha256: solc.binarySha256 }, projections: [{ abstract: "frozen_targets", solidity: "_frozen", baseSlot: 5 }, { abstract: "restriction_flags", solidity: "_restricted", baseSlot: 6, canonicalTrueStorageWord: 1 }], finiteStorageFootprint: { symbolicKeys: 2, pairwiseNonaliasConditions: 1, exactMapFrame: true, restMapVariable: "TOKEN_STORAGE", explicitKeyExclusionConditions: 2, calldataByteLength: 36 }, calldataEncoding: { selector: "0x158b1a57", selectorBytes: 4, addressZeroPrefixBytes: 12, subjectPayloadBytes: 20, totalBytes: 36, sourceShape: "SELECTOR4_ZERO12_SUBJECT20" }, mutation: { manifestPath: repoPath(mutationPath), manifestSha256: sha256(readFileSync(mutationPath)), expectedOutputWhenRestricted: "0x" + "00".repeat(32) }, reverseCheck: { sourceIdentity: "PASS", compilerIdentity: "PASS", getterSelector: "PASS", storageSlots: "PASS", canonicalRuntimeDiffersFromMutant: "PASS", status: "PASS_STATIC_PENDING_KEVM_ISABELLE_REPLAY" } };
writeJson(rowBridgePath, rowBridge);
const isabelleBridgePath = join(bundleRoot, "isabelle", "STATE_04_Bridge_Generated.thy");
write(isabelleBridgePath, `(* GENERATED by formal/kevm/row-bundles/state-04/prepare-mutant.mjs. DO NOT EDIT. *)\ntheory STATE_04_Bridge_Generated\n  imports ERC_TRUST.TRUST_Runtime_Bridge_Generated\nbegin\ndefinition state04_get_frozen_selector :: nat where \"state04_get_frozen_selector = 361437783\"\ndefinition state04_frozen_base_slot :: nat where \"state04_frozen_base_slot = 5\"\ndefinition state04_restricted_base_slot :: nat where \"state04_restricted_base_slot = 6\"\ndefinition state04_calldata_byte_length :: nat where \"state04_calldata_byte_length = 36\"\nrecord state04_runtime_view = state04_frozen_word :: nat state04_restricted_word :: nat\ndefinition state04_decode_bool_word :: \"nat \\<Rightarrow> bool\" where \"state04_decode_bool_word word \\<longleftrightarrow> word = 1\"\ndefinition state04_get_frozen_output :: \"state04_runtime_view \\<Rightarrow> nat\" where \"state04_get_frozen_output view = state04_frozen_word view\"\ndefinition state04_getter_post :: \"state04_runtime_view \\<Rightarrow> state04_runtime_view\" where \"state04_getter_post view = view\"\ntheorem generated_state04_overlay_storage_projection_is_exact: \"(state04_get_frozen_selector, state04_frozen_base_slot, state04_restricted_base_slot, state04_calldata_byte_length) = (361437783, 5, 6, 36)\" by (simp add: state04_get_frozen_selector_def state04_frozen_base_slot_def state04_restricted_base_slot_def state04_calldata_byte_length_def)\ntheorem generated_state04_runtime_observation_is_exact: assumes \"state04_frozen_word view = frozen\" and \"state04_restricted_word view = 1\" shows \"state04_get_frozen_output view = frozen\" and \"state04_decode_bool_word (state04_restricted_word view)\" and \"state04_frozen_word (state04_getter_post view) = frozen\" and \"state04_restricted_word (state04_getter_post view) = 1\" using assms by (simp_all add: state04_get_frozen_output_def state04_decode_bool_word_def state04_getter_post_def)\nend\n`);
const rowManifest = {
  schemaVersion: 1,
  obligationId: "STATE-04",
  bridge: { path: repoPath(rowBridgePath), sha256: sha256(readFileSync(rowBridgePath)) },
  generated: [
    { path: repoPath(mutantBridgePath), sha256: sha256(readFileSync(mutantBridgePath)) },
    { path: repoPath(mutantVerificationPath), sha256: sha256(readFileSync(mutantVerificationPath)) },
    { path: repoPath(isabelleBridgePath), sha256: sha256(readFileSync(isabelleBridgePath)) },
  ],
  proofSpec: { module: "TRUST-STATE-04-FREEZE-RESTRICTION-INDEPENDENT-SPEC", path: repoPath(positiveClaimPath), sha256: sha256(readFileSync(positiveClaimPath)) },
  proofAudit: { path: repoPath(proofAuditTheoryPath), sha256: sha256(readFileSync(proofAuditTheoryPath)) },
  theorem: { name: "freeze_and_restriction_are_independent", path: repoPath(closureTheoryPath), session: "STATE_04_Row", sha256: sha256(readFileSync(closureTheoryPath)) },
};
writeJson(rowManifestPath, rowManifest);
const report = { schemaVersion: 1, obligationId: "STATE-04", status: "PASS_COMPILED_STATIC_PREPARATION", outputDirectory, mutationManifestPath: repoPath(mutationPath), mutationManifestSha256: sha256(readFileSync(mutationPath)), rowBridgePath: repoPath(rowBridgePath), rowBridgeSha256: sha256(readFileSync(rowBridgePath)), generatedIsabellePath: repoPath(isabelleBridgePath), generatedIsabelleSha256: sha256(readFileSync(isabelleBridgePath)), rowManifestPath: repoPath(rowManifestPath), rowManifestSha256: sha256(readFileSync(rowManifestPath)), mutantRuntimeSha256: mutation.runtime.mutantResolvedSha256, mutantRuntimeBytes: runtime.length, mutantCompilerOutputSha256: mutation.compiler.mutantOutputSha256, mutantBridgeSha256: mutation.bridge.mutantSha256, mutantVerificationSha256: mutation.bridge.verificationSha256, caveat: "No KEVM proof, mutant definition compile, or row discharge was run." };
writeJson(join(outputDirectory, "report.json"), report); console.log(JSON.stringify(report, null, 2));
