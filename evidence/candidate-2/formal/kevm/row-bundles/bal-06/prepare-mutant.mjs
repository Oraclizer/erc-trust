import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

import { resolvePinnedSolc } from "../../../../scripts/lib/resolve-pinned-solc.mjs";

const bundleRoot = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(bundleRoot, "../../../..");
const evidenceRoot = join(repositoryRoot, "evidence", "end-to-end-refinement", "row-bundles", "bal-06");
const negativeRoot = join(bundleRoot, "negative");
const bridgeRoot = join(bundleRoot, "bridge");
const lockPath = join(repositoryRoot, "formal", "kevm", "dependencies.lock.json");
const standardInputPath = join(
  repositoryRoot,
  "evidence",
  "end-to-end-refinement",
  "runtime-binding",
  "native",
  "standard-json-input.json",
);
const canonicalOutputPath = join(
  repositoryRoot,
  "evidence",
  "end-to-end-refinement",
  "runtime-binding",
  "native",
  "standard-json-output.json",
);
const fixturePath = join(
  repositoryRoot,
  "evidence",
  "end-to-end-refinement",
  "runtime-binding",
  "resolved",
  "fixture.json",
);
const canonicalBridgePath = join(repositoryRoot, "formal", "kevm", "generated", "trust-runtime-bridge.k");
const positiveClaimPath = join(bundleRoot, "positive", "claim.k");
const negativeClaimPath = join(bundleRoot, "negative", "claim.k");
const mutantVerificationPath = join(negativeRoot, "mutant-runtime-verification.k");
const closureTheoryPath = join(bundleRoot, "isabelle", "BAL_06_Closure.thy");
const proofAuditTheoryPath = join(bundleRoot, "isabelle", "BAL_06_Proof_Audit.thy");
const rowManifestPath = join(bridgeRoot, "row-manifest.json");
const tokenSourcePath = "implementation/src/TrustToken.sol";
const tokenSubject = "TrustToken";

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function repoPath(path) {
  return relative(repositoryRoot, path).split(sep).join("/");
}

function write(path, bytes) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, bytes);
}

function writeJson(path, value) {
  write(path, `${JSON.stringify(value, null, 2)}\n`);
}

const lock = JSON.parse(readFileSync(lockPath, "utf8"));
const solc = lock.components.solc;
const resolvedSolc = resolvePinnedSolc(solc);
const canonicalInputBytes = readFileSync(standardInputPath);
const canonicalInput = JSON.parse(canonicalInputBytes);
const canonicalSource = canonicalInput.sources[tokenSourcePath].content;
const mutationAnchor = [
  "        _move(from, to, amount);",
  "    }",
  "",
  "    function _ordinaryAvailable",
].join("\n");
const mutationReplacement = [
  "        _move(from, to, amount);",
  "        _custodyBacking[from] = 0; // BAL-06 semantic mutant",
  "    }",
  "",
  "    function _ordinaryAvailable",
].join("\n");
if (canonicalSource.split(mutationAnchor).length !== 2) {
  throw new Error("BAL-06 mutation anchor is not unique");
}
const mutantSource = canonicalSource.replace(mutationAnchor, mutationReplacement);
const mutantInput = structuredClone(canonicalInput);
mutantInput.sources[tokenSourcePath].content = mutantSource;
const mutantInputBytes = Buffer.from(`${JSON.stringify(mutantInput)}\n`, "utf8");
const mutantInputPath = join(evidenceRoot, "negative", "standard-json-input.json");
const mutantOutputPath = join(evidenceRoot, "negative", "standard-json-output.json");
const mutantSourcePath = join(evidenceRoot, "negative", "TrustToken.BAL-06-mutant.sol");
write(mutantInputPath, mutantInputBytes);
write(mutantSourcePath, mutantSource);

const rawOutput = execFileSync(
  "wsl.exe",
  ["-d", resolvedSolc.distribution, "-e", resolvedSolc.binaryPath, "--standard-json"],
  { input: mutantInputBytes, maxBuffer: 256 * 1024 * 1024 },
);
const firstBrace = rawOutput.indexOf(0x7b);
if (firstBrace < 0) throw new Error("solc returned no JSON object");
const outputBytes = rawOutput.subarray(firstBrace);
const output = JSON.parse(outputBytes.toString("utf8"));
const fatalErrors = (output.errors ?? []).filter((entry) => entry.severity === "error");
if (fatalErrors.length !== 0) {
  throw new Error(`mutant compilation failed: ${fatalErrors.map((entry) => entry.formattedMessage).join("\n")}`);
}
write(mutantOutputPath, outputBytes);

const contract = output.contracts[tokenSourcePath]?.[tokenSubject];
if (!contract) throw new Error("mutant TrustToken compiler output missing");
if (contract.evm.methodIdentifiers["transfer(address,uint256)"] !== "a9059cbb") {
  throw new Error("mutant transfer selector drift");
}
const layout = Object.fromEntries(contract.storageLayout.storage.map((entry) => [entry.label, Number(entry.slot)]));
const expectedLayout = { _balances: 3, _frozen: 5, _restricted: 6, _custodyBacking: 7, _entered: 29 };
for (const [label, slot] of Object.entries(expectedLayout)) {
  if (layout[label] !== slot) throw new Error(`mutant storage layout drift: ${label}:${layout[label]}`);
}

const fixture = JSON.parse(readFileSync(fixturePath, "utf8"));
const deployment = fixture.deployments.find((entry) => entry.label === "TrustToken");
if (!deployment) throw new Error("TrustToken fixture deployment missing");
const encodedByAstId = new Map(
  deployment.immutablePatch.declarations.map((entry) => [String(entry.astId), entry.encodedWord.slice(2)]),
);
const templateHex = contract.evm.deployedBytecode.object;
if (!/^[0-9a-f]+$/.test(templateHex)) throw new Error("invalid mutant runtime template");
const runtime = Buffer.from(templateHex, "hex");
const references = contract.evm.deployedBytecode.immutableReferences ?? {};
if (Object.keys(references).length !== encodedByAstId.size) {
  throw new Error("mutant immutable count drift");
}
for (const [astId, locations] of Object.entries(references)) {
  const encoded = encodedByAstId.get(astId);
  if (!encoded) throw new Error(`mutant immutable identity drift: ${astId}`);
  const word = Buffer.from(encoded, "hex");
  for (const location of locations) {
    if (location.length !== 32 || location.start + 32 > runtime.length) {
      throw new Error(`invalid mutant immutable location: ${astId}`);
    }
    if (runtime.subarray(location.start, location.start + 32).some((byte) => byte !== 0)) {
      throw new Error(`nonzero mutant immutable template span: ${astId}`);
    }
    word.copy(runtime, location.start);
  }
}
const mutantRuntimeHex = `0x${runtime.toString("hex")}`;
const mutantRuntimePath = join(evidenceRoot, "negative", "TrustToken.runtime.hex");
write(mutantRuntimePath, `${mutantRuntimeHex}\n`);

const canonicalBridge = readFileSync(canonicalBridgePath, "utf8");
const runtimeRule = /rule #trustTrustTokenRuntime\(\) => #parseByteStack\("0x[0-9a-f]+"\)/g;
const matches = canonicalBridge.match(runtimeRule) ?? [];
if (matches.length !== 1) throw new Error("canonical TrustToken runtime rule is not unique");
const mutantBridge = canonicalBridge.replace(
  runtimeRule,
  `rule #trustTrustTokenRuntime() => #parseByteStack("${mutantRuntimeHex}")`,
);
const mutantBridgePath = join(negativeRoot, "mutant-runtime-bridge.k");
write(mutantBridgePath, mutantBridge);

const canonicalOutputBytes = readFileSync(canonicalOutputPath);
const canonicalOutput = JSON.parse(canonicalOutputBytes);
const canonicalToken = canonicalOutput.contracts[tokenSourcePath][tokenSubject];
const canonicalRuntime = readFileSync(
  join(repositoryRoot, ...deployment.runtime.path.split("/")),
  "utf8",
).trim();
if (mutantRuntimeHex === canonicalRuntime) throw new Error("semantic mutant did not change the runtime");
if (mutantRuntimeHex.length > 2 + 2 * 24_576) throw new Error("mutant exceeds EIP-170 runtime size");

const positiveClaim = readFileSync(positiveClaimPath, "utf8");
const negativeClaim = readFileSync(negativeClaimPath, "utf8");
for (const token of [
  '#hashedLocation("Solidity", 3, SOURCE_ID)',
  '#hashedLocation("Solidity", 3, DESTINATION_ID)',
  '#hashedLocation("Solidity", 5, SOURCE_ID)',
  '#hashedLocation("Solidity", 5, DESTINATION_ID)',
  '#hashedLocation("Solidity", 7, SOURCE_ID)',
  '#hashedLocation("Solidity", 7, DESTINATION_ID)',
  "29 |-> 0",
  '#hashedLocation("Solidity", 3, OTHER_ID)',
]) {
  if (!positiveClaim.includes(token) || !negativeClaim.includes(token)) {
    throw new Error(`claim storage projection missing: ${token}`);
  }
}

const mutationManifestPath = join(evidenceRoot, "negative", "mutation.json");
const mutationManifest = {
  schemaVersion: 1,
  obligationId: "BAL-06",
  mutationId: "BAL-06-CLEAR-CUSTODY-BACKING-AFTER-MOVE",
  sourcePath: tokenSourcePath,
  mutation: "Insert _custodyBacking[from] = 0 immediately after the successful _move in _ordinaryTransfer.",
  reachabilityPrecondition: "BACKING > 0 and AMOUNT > 0 under the positive claim's ordinary-available floor.",
  compiler: {
    version: solc.version,
    binarySha256: solc.binarySha256,
    settingsSha256: sha256(Buffer.from(JSON.stringify(mutantInput.settings), "utf8")),
    canonicalInputPath: repoPath(standardInputPath),
    canonicalInputSha256: sha256(canonicalInputBytes),
    mutantInputPath: repoPath(mutantInputPath),
    mutantInputSha256: sha256(mutantInputBytes),
    mutantOutputPath: repoPath(mutantOutputPath),
    mutantOutputSha256: sha256(outputBytes),
  },
  source: {
    canonicalSha256: sha256(Buffer.from(canonicalSource, "utf8")),
    mutantPath: repoPath(mutantSourcePath),
    mutantSha256: sha256(Buffer.from(mutantSource, "utf8")),
  },
  runtime: {
    canonicalResolvedSha256: sha256(Buffer.from(canonicalRuntime.slice(2), "hex")),
    mutantTemplateSha256: sha256(Buffer.from(templateHex, "hex")),
    mutantResolvedPath: repoPath(mutantRuntimePath),
    mutantResolvedSha256: sha256(runtime),
    mutantByteLength: runtime.length,
    eip170MarginBytes: 24_576 - runtime.length,
    immutableReferences: references,
  },
  bridge: {
    canonicalPath: repoPath(canonicalBridgePath),
    canonicalSha256: sha256(Buffer.from(canonicalBridge, "utf8")),
    mutantPath: repoPath(mutantBridgePath),
    mutantSha256: sha256(Buffer.from(mutantBridge, "utf8")),
  },
};
writeJson(mutationManifestPath, mutationManifest);

const rowBridgePath = join(bridgeRoot, "row-bridge.json");
const rowBridge = {
  schemaVersion: 1,
  obligationId: "BAL-06",
  compilerBinding: {
    canonicalOutputPath: repoPath(canonicalOutputPath),
    canonicalOutputSha256: sha256(canonicalOutputBytes),
    canonicalStorageLayoutSha256: sha256(Buffer.from(JSON.stringify(canonicalToken.storageLayout), "utf8")),
    methodSignature: "transfer(address,uint256)",
    methodSelector: "0xa9059cbb",
  },
  projections: [
    { abstract: "physical_balances", solidity: "_balances", baseSlot: 3, key: "address", claimRoles: ["source", "destination", "other"] },
    { abstract: "frozen_targets", solidity: "_frozen", baseSlot: 5, key: "address", claimRoles: ["source", "destination"] },
    { abstract: "restriction_flags", solidity: "_restricted", baseSlot: 6, key: "address", claimRoles: ["source", "destination"] },
    { abstract: "custody_backing", solidity: "_custodyBacking", baseSlot: 7, key: "address", claimRoles: ["source", "destination"] },
    { abstract: "non_reentrant_idle", solidity: "_entered", baseSlot: 29, key: "scalar", claimRoles: ["pre", "post"] },
  ],
  finiteStorageFootprint: {
    symbolicKeys: 10,
    pairwiseNonaliasConditions: 45,
    exactMapFrame: true,
    restMapVariable: "TOKEN_STORAGE",
    explicitKeyExclusionConditions: 10,
    calldataByteLength: 68,
    scalarSlot29Normalization: "LITERAL_STORAGE_KEY_29",
  },
  calldataEncoding: {
    selector: "0xa9059cbb",
    selectorBytes: 4,
    addressZeroPrefixBytes: 12,
    destinationPayloadBytes: 20,
    amountPayloadBytes: 32,
    totalBytes: 68,
    sourceShape: "SELECTOR4_ZERO12_DESTINATION20_AMOUNT32",
  },
  runtimeTransition: {
    sourcePhysicalBalance: "SOURCE_BALANCE - AMOUNT",
    destinationPhysicalBalance: "DESTINATION_BALANCE + AMOUNT",
    sourceFrozen: "FROZEN",
    destinationFrozen: "DESTINATION_FROZEN",
    sourceBacking: "BACKING",
    destinationBacking: "DESTINATION_BACKING",
    otherPhysicalBalance: "OTHER_BALANCE",
    entered: 0,
  },
  mutationManifestPath: repoPath(mutationManifestPath),
  mutationManifestSha256: sha256(Buffer.from(`${JSON.stringify(mutationManifest, null, 2)}\n`, "utf8")),
  reverseCheck: {
    compilerSlots: "PASS",
    compilerSelector: "PASS",
    positiveClaimProjectionTokens: "PASS",
    negativeClaimProjectionTokens: "PASS",
    canonicalRuntimeDiffersFromMutant: "PASS",
    status: "PASS_SOURCE_LEVEL_PENDING_KPROVE_DRY_RUN",
  },
};
writeJson(rowBridgePath, rowBridge);

const isabelleBridgePath = join(bundleRoot, "isabelle", "BAL_06_Bridge_Generated.thy");
const isabelleBridge = `(* GENERATED by formal/kevm/row-bundles/bal-06/prepare-mutant.mjs. DO NOT EDIT. *)
theory BAL_06_Bridge_Generated
  imports ERC_TRUST.TRUST_Runtime_Bridge_Generated
begin

definition bal06_transfer_selector :: nat where
  "bal06_transfer_selector = 2835717307"

definition bal06_balances_base_slot :: nat where
  "bal06_balances_base_slot = 3"

definition bal06_frozen_base_slot :: nat where
  "bal06_frozen_base_slot = 5"

definition bal06_restricted_base_slot :: nat where
  "bal06_restricted_base_slot = 6"

definition bal06_backing_base_slot :: nat where
  "bal06_backing_base_slot = 7"

definition bal06_entered_scalar_slot :: nat where
  "bal06_entered_scalar_slot = 29"

definition bal06_symbolic_storage_key_count :: nat where
  "bal06_symbolic_storage_key_count = 10"

definition bal06_pairwise_key_nonalias_count :: nat where
  "bal06_pairwise_key_nonalias_count = 45"

definition bal06_rest_map_key_exclusion_count :: nat where
  "bal06_rest_map_key_exclusion_count = 10"

definition bal06_calldata_byte_length :: nat where
  "bal06_calldata_byte_length = 68"

definition bal06_address_zero_prefix_bytes :: nat where
  "bal06_address_zero_prefix_bytes = 12"

definition bal06_destination_payload_bytes :: nat where
  "bal06_destination_payload_bytes = 20"

definition bal06_amount_payload_bytes :: nat where
  "bal06_amount_payload_bytes = 32"

record bal06_runtime_view =
  bal06_source_balance :: nat
  bal06_destination_balance :: nat
  bal06_source_frozen :: nat
  bal06_destination_frozen :: nat
  bal06_source_backing :: nat
  bal06_destination_backing :: nat
  bal06_other_balance :: nat
  bal06_entered :: nat

definition bal06_runtime_transfer_post ::
  "bal06_runtime_view \\<Rightarrow> nat \\<Rightarrow> bal06_runtime_view"
where
  "bal06_runtime_transfer_post view amount =
     view\\<lparr>bal06_source_balance := bal06_source_balance view - amount,
          bal06_destination_balance := bal06_destination_balance view + amount,
          bal06_entered := 0\\<rparr>"

theorem generated_bal06_storage_projection_is_exact:
  "(bal06_transfer_selector,
    bal06_balances_base_slot,
    bal06_frozen_base_slot,
    bal06_restricted_base_slot,
    bal06_backing_base_slot,
    bal06_entered_scalar_slot,
    bal06_symbolic_storage_key_count,
    bal06_pairwise_key_nonalias_count,
    bal06_rest_map_key_exclusion_count,
    bal06_calldata_byte_length,
    bal06_address_zero_prefix_bytes,
    bal06_destination_payload_bytes,
    bal06_amount_payload_bytes) =
   (2835717307, 3, 5, 6, 7, 29, 10, 45, 10, 68, 12, 20, 32)"
  by (simp add: bal06_transfer_selector_def bal06_balances_base_slot_def
      bal06_frozen_base_slot_def bal06_restricted_base_slot_def
      bal06_backing_base_slot_def bal06_entered_scalar_slot_def
      bal06_symbolic_storage_key_count_def bal06_pairwise_key_nonalias_count_def
      bal06_rest_map_key_exclusion_count_def bal06_calldata_byte_length_def
      bal06_address_zero_prefix_bytes_def bal06_destination_payload_bytes_def
      bal06_amount_payload_bytes_def)

theorem generated_bal06_runtime_frame_is_exact:
  shows "bal06_source_balance (bal06_runtime_transfer_post view amount) =
         bal06_source_balance view - amount"
    and "bal06_destination_balance (bal06_runtime_transfer_post view amount) =
         bal06_destination_balance view + amount"
    and "bal06_source_frozen (bal06_runtime_transfer_post view amount) = bal06_source_frozen view"
    and "bal06_destination_frozen (bal06_runtime_transfer_post view amount) = bal06_destination_frozen view"
    and "bal06_source_backing (bal06_runtime_transfer_post view amount) = bal06_source_backing view"
    and "bal06_destination_backing (bal06_runtime_transfer_post view amount) = bal06_destination_backing view"
    and "bal06_other_balance (bal06_runtime_transfer_post view amount) = bal06_other_balance view"
    and "bal06_entered (bal06_runtime_transfer_post view amount) = 0"
  by (simp_all add: bal06_runtime_transfer_post_def)

end
`;
write(isabelleBridgePath, isabelleBridge);

const rowManifest = {
  schemaVersion: 1,
  obligationId: "BAL-06",
  bridge: {
    path: repoPath(rowBridgePath),
    sha256: sha256(readFileSync(rowBridgePath)),
  },
  generated: [
    { path: repoPath(mutantBridgePath), sha256: sha256(readFileSync(mutantBridgePath)) },
    { path: repoPath(mutantVerificationPath), sha256: sha256(readFileSync(mutantVerificationPath)) },
    { path: repoPath(isabelleBridgePath), sha256: sha256(readFileSync(isabelleBridgePath)) },
  ],
  proofSpec: {
    module: "TRUST-BAL-06-ORDINARY-TRANSFER-PRESERVES-FLOOR-SPEC",
    path: repoPath(positiveClaimPath),
    sha256: sha256(readFileSync(positiveClaimPath)),
  },
  proofAudit: {
    path: repoPath(proofAuditTheoryPath),
    sha256: sha256(readFileSync(proofAuditTheoryPath)),
  },
  theorem: {
    name: "ordinary_transfer_preserves_backing_and_own_frozen_floor",
    path: repoPath(closureTheoryPath),
    session: "BAL_06_Row",
    sha256: sha256(readFileSync(closureTheoryPath)),
  },
};
writeJson(rowManifestPath, rowManifest);

console.log(JSON.stringify({
  status: "PASS",
  mutantRuntimeSha256: mutationManifest.runtime.mutantResolvedSha256,
  mutantRuntimeBytes: runtime.length,
  mutantBridgeSha256: mutationManifest.bridge.mutantSha256,
  mutantOutputSha256: mutationManifest.compiler.mutantOutputSha256,
  rowBridge: repoPath(rowBridgePath),
  rowBridgeSha256: sha256(readFileSync(rowBridgePath)),
  isabelleBridge: repoPath(isabelleBridgePath),
  isabelleBridgeSha256: sha256(readFileSync(isabelleBridgePath)),
  rowManifest: repoPath(rowManifestPath),
  rowManifestSha256: sha256(readFileSync(rowManifestPath)),
}, null, 2));
