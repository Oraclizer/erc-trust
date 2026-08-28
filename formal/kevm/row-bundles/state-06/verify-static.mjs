import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const bundleRoot = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(bundleRoot, "../../../..");
const at = (...parts) => join(repositoryRoot, ...parts);
const bytes = (path) => readFileSync(path);
const text = (path) => readFileSync(path, "utf8");
const json = (path) => JSON.parse(text(path));
const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const assert = (condition, message) => { if (!condition) throw new Error(message); };
const count = (haystack, needle) => haystack.split(needle).length - 1;

const exactRequiredProperty = "`nonce_projection_is_exact`: concrete nonce storage retrieves exactly `(authorityRef, authorityEpoch, nonce)`";
const expectedSources = new Map([
  ["implementation/src/TrustTypes.sol", "cb16ab2f3d8df94d8a933c45367c594096d3f97f9a969998d89fc55837f4ab3e"],
  ["implementation/src/TrustStorage.sol", "881783e28f8ec36e4571f48f407db4b63f8e736237f5e9f1044d916f3c066c6f"],
  ["implementation/src/TrustPolicyBinding.sol", "f24c15105c27ab3ed5586693343e5c1d83e22b79dad0b4c187a3bb341dba4a41"],
  ["implementation/src/TrustToken.sol", "dbe06bb25a2b62913bd6428e1de32ba007a214e24ac45f4fd2c0fb55ea22c96a"],
  ["implementation/src/profiles/ERC3643TrustAdapter.sol", "d8b2de891e5ef9203df72aee6025b4accda7819cb27b35684a1ab81471ef144d"],
]);

const indexPath = at("evidence", "end-to-end-refinement", "obligation-evidence-index.json");
const index = json(indexPath);
let row;
const walk = (value) => {
  if (Array.isArray(value)) for (const entry of value) walk(entry);
  else if (value && typeof value === "object") {
    if (value.obligationId === "STATE-06" && value.requiredProperty) row = value;
    for (const nested of Object.values(value)) walk(nested);
  }
};
walk(index);
assert(row, "canonical STATE-06 row missing");
assert(row.requiredProperty === exactRequiredProperty, "canonical requiredProperty drift");
assert(row.statement?.name === "nonce_projection_is_exact", "canonical statement name drift");
assert(row.status?.classification === "OPEN" && row.status?.discharged === false, "canonical row is no longer OPEN");
assert(!Object.hasOwn(row, "dependencies"), "canonical dependency-field shape changed");
assert(row.proofs?.length === 0 && row.negativeEvidence?.length === 0, "unexpected canonical proof credit appeared");
assert(row.compiler?.standardJsonInputRef === null && row.compiler?.outputArtifactRef === null, "unexpected canonical compiler binding appeared");
const indexedSources = new Map(row.soliditySubjects.map((entry) => [entry.artifactRef.path, entry.artifactRef.sha256]));
for (const [path, expected] of expectedSources) {
  assert(indexedSources.get(path) === expected, `canonical index source identity drift: ${path}`);
  assert(sha256(bytes(at(...path.split("/")))) === expected, `working source identity drift: ${path}`);
}

const obligationsPath = at("evidence", "end-to-end-refinement", "theorem-obligations.md");
assert(text(obligationsPath).includes(`STATE-06 | ${exactRequiredProperty}`), "theorem obligation wording drift");

const graphPath = at("evidence", "end-to-end-refinement", "row-bundles", "bal-06", "state-action-dependency-graph.json");
const graph = json(graphPath);
const incoming = graph.edges.filter((edge) => edge.to === "STATE-06");
const outgoing = graph.edges.filter((edge) => edge.from === "STATE-06");
assert(JSON.stringify(incoming) === JSON.stringify([
  { from: "STATE-01", to: "STATE-06", kind: "retrieve-foundation" },
]), "STATE-06 row-local planning incoming edges changed");
assert(outgoing.length === 0, "STATE-06 row-local planning outgoing edges changed");

const nativeInputPath = at("evidence", "end-to-end-refinement", "runtime-binding", "native", "standard-json-input.json");
const nativeOutputPath = at("evidence", "end-to-end-refinement", "runtime-binding", "native", "standard-json-output.json");
const profileInputPath = at("evidence", "end-to-end-refinement", "runtime-binding", "verified-profile", "standard-json-input.json");
const profileOutputPath = at("evidence", "end-to-end-refinement", "runtime-binding", "verified-profile", "standard-json-output.json");
const nativeInputBytes = bytes(nativeInputPath);
const nativeOutputBytes = bytes(nativeOutputPath);
const profileInputBytes = bytes(profileInputPath);
const profileOutputBytes = bytes(profileOutputPath);
const nativeInput = JSON.parse(nativeInputBytes);
const nativeOutput = JSON.parse(nativeOutputBytes);
const profileInput = JSON.parse(profileInputBytes);
assert(sha256(nativeOutputBytes) === "9697548b65ac0b4fdeff17deca78d9e11e49676dd0d78bd9d94907b24d5ac34e", "canonical compiler output drift");
for (const [path, expected] of expectedSources) {
  const nativeContent = nativeInput.sources[path]?.content;
  const profileContent = profileInput.sources[path]?.content;
  assert(nativeContent || profileContent, `source absent from canonical compiler inputs: ${path}`);
  if (nativeContent) assert(sha256(Buffer.from(nativeContent, "utf8")) === expected, `native compiler source drift: ${path}`);
  if (profileContent) assert(sha256(Buffer.from(profileContent, "utf8")) === expected, `profile compiler source drift: ${path}`);
}
const token = nativeOutput.contracts["implementation/src/TrustToken.sol"]?.TrustToken;
assert(token, "TrustToken compiler output missing");
assert(token.evm.methodIdentifiers["nonceUsed(bytes32,uint64,uint256)"] === "15cba043", "nonceUsed selector drift");
const nonceSlot = token.storageLayout.storage.find((entry) => entry.label === "_usedNonces");
assert(nonceSlot?.slot === "12" && nonceSlot.offset === 0, "_usedNonces slot drift");
assert(nonceSlot.type === "t_mapping(t_bytes32,t_mapping(t_uint64,t_mapping(t_uint256,t_bool)))", "_usedNonces top-level type drift");
const topType = token.storageLayout.types[nonceSlot.type];
const epochType = token.storageLayout.types[topType.value];
const nonceType = token.storageLayout.types[epochType.value];
assert(topType.key === "t_bytes32" && epochType.key === "t_uint64" && nonceType.key === "t_uint256", "nested nonce key order drift");
assert(token.storageLayout.types[nonceType.value]?.label === "bool", "nested nonce value type drift");
const storageLayoutSha256 = sha256(Buffer.from(JSON.stringify(token.storageLayout), "utf8"));
assert(storageLayoutSha256 === "18cfae1f174dfc60274512cf6e904adcdeb2cb4c20c54ef83727c537a4bfa281", "storage layout identity drift");

const lockPath = at("formal", "kevm", "dependencies.lock.json");
const lockBytes = bytes(lockPath);
const lock = JSON.parse(lockBytes);
const currentLockSha256 = sha256(lockBytes);
const placeholderLockSha256 = row.tcb.find((entry) => entry.tcbId === "TCB-LOCK")?.exactIdentityRef?.sha256;
assert(currentLockSha256 === "3134e7692086170f86b6dd42e7ebd0256c188da8db8cbd17241c3d2c8d315196", "current tracked lock drift");
assert(placeholderLockSha256 === "e4fcabd40c8b18e3900050a590b6b80c687d4d115f61bc12439af6099e83434e", "OPEN placeholder lock reference changed");
assert(lock.components.solc.version === "0.8.36+commit.8a079791", "pinned solc version drift");
assert(lock.components.solc.binarySha256 === "c8d35afdddc3cd2743ee88b8f25e0fecd16e2bdd5f2120f37e52cd9cc45ae0e6", "pinned solc binary drift");

const tokenSource = text(at("implementation", "src", "TrustToken.sol"));
const getterAnchor = "    function nonceUsed(bytes32 authorityRef, uint64 authorityEpoch, uint256 nonce) external view returns (bool) {\n        return _usedNonces[authorityRef][authorityEpoch][nonce];\n    }";
assert(count(tokenSource, getterAnchor) === 1, "nonceUsed getter anchor is not unique");
const storageSource = text(at("implementation", "src", "TrustStorage.sol"));
assert(count(storageSource, "mapping(bytes32 => mapping(uint64 => mapping(uint256 => bool))) internal _usedNonces;") === 1, "nested nonce storage declaration drift");
const transactionTheory = text(at("formal", "isabelle", "ERC_TRUST", "TRUST_Transaction_Refinement.thy"));
assert(transactionTheory.includes("(forward_authority_ref command, forward_authority_epoch command,\n      forward_nonce command)"), "abstract forward nonce tuple order drift");

const positivePath = join(bundleRoot, "positive", "claim.k");
const negativePath = join(bundleRoot, "negative", "claim.k");
const positiveClaim = bytes(positivePath);
const negativeClaim = bytes(negativePath);
assert(positiveClaim.equals(negativeClaim), "positive and negative claim sources differ");
const claim = positiveClaim.toString("utf8");
const exactLocation = "#hashedLocation(\"Solidity\", #hashedLocation(\"Solidity\", #hashedLocation(\"Solidity\", 12, AUTHORITY_REF), AUTHORITY_EPOCH), NONCE)";
const redirectedLocation = "#hashedLocation(\"Solidity\", #hashedLocation(\"Solidity\", #hashedLocation(\"Solidity\", 12, 0), 0), NONCE +Int 1)";
for (const required of [
  "#abiCallData(\"nonceUsed\", #bytes32(AUTHORITY_REF), #uint64(AUTHORITY_EPOCH), #uint256(NONCE))",
  `${exactLocation} |-> 1`, redirectedLocation, "#buf(32, 1)", "TOKEN_STORAGE:Map",
  "AUTHORITY_EPOCH <Int (2 ^Int 64)", "NONCE <Int ((2 ^Int 256) -Int 1)",
]) assert(claim.includes(required), `claim skeleton missing: ${required}`);
assert(count(claim, "in_keys(TOKEN_STORAGE)") === 2, "claim rest-map exclusion count drift");
assert(count(claim, exactLocation) >= 4, "exact nested location binding drift");

const planPath = at("evidence", "end-to-end-refinement", "row-bundles", "state-06", "negative", "mutation-plan.json");
const plan = json(planPath);
assert(plan.status === "SOURCE_PLAN_STATIC_ONLY_PENDING_PINNED_SOLC_AND_KEVM", "mutation plan status drift");
assert(plan.canonicalSource.sha256 === expectedSources.get("implementation/src/TrustToken.sol"), "mutation source identity drift");
assert(plan.dependencyLock.currentTrackedSha256 === currentLockSha256, "mutation current lock binding drift");
assert(plan.dependencyLock.openPlaceholderIndexSha256 === placeholderLockSha256, "mutation placeholder lock reference drift");
assert(plan.uniqueAnchor === getterAnchor && count(tokenSource, plan.uniqueAnchor) === 1, "mutation anchor drift");
const mutantSource = tokenSource.replace(plan.uniqueAnchor, plan.replacement);
assert(mutantSource !== tokenSource, "mutation did not alter source");
assert(count(mutantSource, "_usedNonces[bytes32(0)][uint64(0)][nonce + 1]") === 1, "redirected triple mutation missing or non-unique");
assert(count(mutantSource, "function nonceUsed(bytes32 authorityRef, uint64 authorityEpoch, uint256 nonce) external view returns (bool)") === 1, "mutant getter signature drift");

const bridgePath = join(bundleRoot, "bridge", "row-bridge.json");
const bridge = json(bridgePath);
assert(bridge.requiredProperty === exactRequiredProperty && bridge.status.startsWith("OPEN_STATIC_SKELETON"), "row bridge boundary drift");
assert(bridge.dependencyBoundary.canonicalIndexExplicitDependencies === null, "row bridge invented canonical dependencies");
assert(JSON.stringify(bridge.dependencyBoundary.rowLocalPlanningGraphIncoming) === JSON.stringify(incoming.map(({ from, kind }) => ({ obligationId: from, kind }))), "row bridge planning incoming drift");
assert(bridge.dependencyBoundary.rowLocalPlanningGraphOutgoing.length === 0, "row bridge planning outgoing drift");
assert(bridge.compilerBinding.currentDependencyLockSha256 === currentLockSha256, "row bridge current lock drift");
assert(bridge.compilerBinding.openPlaceholderIndexLockSha256 === placeholderLockSha256, "row bridge placeholder drift");
assert(bridge.compilerBinding.methodSelector === "0x15cba043" && bridge.projection.baseSlot === 12, "row bridge compiler fact drift");
assert(JSON.stringify(bridge.projection.keyTuple) === JSON.stringify(["bytes32 authorityRef", "uint64 authorityEpoch", "uint256 nonce"]), "row bridge tuple order drift");
assert(bridge.isabelleTarget.existingTheoremCreditUsed === false, "existing theorem credit must remain false");

const generatedPath = join(bundleRoot, "isabelle", "STATE_06_Bridge_Generated.thy");
const closurePath = join(bundleRoot, "isabelle", "STATE_06_Closure.thy");
const rootPath = join(bundleRoot, "isabelle", "ROOT");
const generated = text(generatedPath);
const closure = text(closurePath);
const banned = /^\s*(sorry|oops|axiomatization|oracle)\b|\bby\s+eval\b|\bnative_decide\b|\bskip_proof\b/gm;
for (const source of [generated, closure]) {
  assert(!banned.test(source), "banned Isabelle source form found");
  banned.lastIndex = 0;
}
assert(generated.includes("theorem generated_state06_exact_tuple_observation:"), "generated exact tuple theorem missing");
assert(closure.includes("theorem state06_nonce_tuple_projection_target:"), "named tuple closure target missing");
assert(closure.includes("theorem state06_positive_runtime_view_retrieves_exact_triple:"), "positive tuple closure missing");
assert(!closure.includes("using nonce_projection_is_exact"), "existing retrieve theorem credit was appropriated");

const fixture = json(at("evidence", "end-to-end-refinement", "runtime-binding", "resolved", "fixture.json"));
const deployment = fixture.deployments.find((entry) => entry.label === "TrustToken");
assert(deployment, "TrustToken fixture deployment missing");
const runtimeHex = text(at(...deployment.runtime.path.split("/"))).trim();
assert(/^0x[0-9a-f]+$/.test(runtimeHex), "canonical resolved runtime malformed");
const runtimeSha256 = sha256(Buffer.from(runtimeHex.slice(2), "hex"));
assert(runtimeSha256 === "3697706d4948c34fada47e049d32ad3e1866cf24ded6328f0c209d858614a86d", "canonical resolved runtime drift");
assert(text(at("formal", "kevm", "generated", "trust-runtime-bridge.k")).includes(`#parseByteStack("${runtimeHex}")`), "generated runtime bridge binding drift");

console.log(JSON.stringify({
  schemaVersion: 1,
  obligationId: "STATE-06",
  status: "PASS_OPEN_STATIC_SKELETON_CURRENT_TCB_VERIFIED_PLACEHOLDER_PENDING_COORDINATOR_BINDING",
  rowStatus: "OPEN",
  exactRequiredProperty,
  canonicalIndexDependencies: { explicitFieldPresent: false, value: null },
  rowLocalPlanningGraph: { incoming, outgoing },
  tcbIdentity: {
    status: "PASS_CURRENT_TRACKED_IDENTITY_OPEN_PLACEHOLDER_PENDING_COORDINATOR_REPLACEMENT",
    currentTrackedLockSha256: currentLockSha256,
    openPlaceholderIndexLockSha256: placeholderLockSha256,
    productLockDrift: false,
  },
  canonicalIndexSha256: sha256(bytes(indexPath)),
  dependencyGraphSha256: sha256(bytes(graphPath)),
  theoremObligationsSha256: sha256(bytes(obligationsPath)),
  nativeCompilerInputSha256: sha256(nativeInputBytes),
  nativeCompilerOutputSha256: sha256(nativeOutputBytes),
  profileCompilerInputSha256: sha256(profileInputBytes),
  profileCompilerOutputSha256: sha256(profileOutputBytes),
  storageLayoutSha256,
  sourceIdentitiesChecked: expectedSources.size,
  methodSelector: "0x15cba043",
  usedNoncesBaseSlot: 12,
  nestedKeyOrder: ["bytes32", "uint64", "uint256"],
  canonicalResolvedRuntimeSha256: runtimeSha256,
  claimSha256: sha256(positiveClaim),
  mutationPlanSha256: sha256(bytes(planPath)),
  rowBridgeSha256: sha256(bytes(bridgePath)),
  generatedIsabelleSha256: sha256(bytes(generatedPath)),
  closureIsabelleSha256: sha256(bytes(closurePath)),
  isabelleRootSha256: sha256(bytes(rootPath)),
  notExecuted: [
    "pinned-solc mutant compilation", "K parse or KEVM proof backend",
    "Isabelle build or oracle audit", "negative terminal semantic counterexample",
    "repository replay", "shared registry or ledger binding",
  ],
  caveat: "All source/compiler/runtime/current-TCB and row-local static skeleton checks passed. Dynamic gates remain open and STATE-06 is not discharged.",
}, null, 2));
