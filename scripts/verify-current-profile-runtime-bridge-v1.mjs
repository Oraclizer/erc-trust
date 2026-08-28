import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifestPath = resolve(root, "evidence/end-to-end-refinement/current-profile-bridge-v1/manifest-v1.json");
const indexPath = resolve(root, "evidence/end-to-end-refinement/obligation-evidence-index.json");
const scopePath = resolve(root, "evidence/end-to-end-refinement/m4-core-refinement-scope-v1.json");
function sha(bytes) { return createHash("sha256").update(bytes).digest("hex"); }
function fileSha(path) { return sha(readFileSync(path)); }
function json(path) { return JSON.parse(readFileSync(path, "utf8")); }
function check(condition, message) { if (!condition) throw new Error(message); }

const manifest = json(manifestPath);
const schemaPath = resolve(root, manifest.schema.path);
const schema = json(schemaPath);
const index = json(indexPath);
const scope = json(scopePath);
check(fileSha(schemaPath) === manifest.schema.sha256, "current bridge schema drift");
check(manifest.schemaVersion === 1 && manifest.kind === "ERC_TRUST_CURRENT_PROFILE_RUNTIME_BRIDGE_MANIFEST_V1", "manifest identity drift");
check(schema.schemaVersion === 1 && schema.kind === "ERC_TRUST_CURRENT_PROFILE_RUNTIME_BRIDGE_V1", "schema identity drift");
check(schema.profileId === "M4-NATIVE-FINANCIAL-CORE-v1" && schema.sourceHead === "add3dfb9ca75923d6462d16ba8eb41cad0b1216f", "current profile authority drift");
check(schema.currentRegistry.sha256 === index.registry.sha256, "current registry not bound");
check(schema.currentRegistry.sha256 === fileSha(resolve(root, schema.currentRegistry.path)), "physical registry drift");
check(schema.scope.sha256 === fileSha(scopePath), "scope hash drift");
check(schema.scope.coreRefinement === 49 && schema.scope.coreSupporting === 24 && schema.scope.backlog === 6, "partition drift");
check(schema.scope.legacyCarryover === false && schema.act01.currentProfileCredit === 0, "premature current credit");
check(schema.tcbIndex.sha256 === fileSha(resolve(root, schema.tcbIndex.path)), "TCB index drift");
check(schema.summaryRegistry.sha256 === fileSha(resolve(root, schema.summaryRegistry.path)), "summary registry drift");
const tcb = json(resolve(root, schema.tcbIndex.path));
const summaries = json(resolve(root, schema.summaryRegistry.path));
const recomputedTcbRoot = sha(Buffer.from(tcb.profiles.map((entry) => `${entry.profileId}\0${entry.sha256}\n`).join(""), "utf8"));
const recomputedSummaryRoot = sha(Buffer.from([
  ...summaries.contracts.map((entry) => `${entry.id}\0${entry.sha256}\n`),
  ...summaries.packages.map((entry) => `${entry.id}\0${entry.sha256}\n`),
].join(""), "utf8"));
check(recomputedTcbRoot === schema.tcbIndex.deterministicRootSha256, "TCB root not independently recomputed");
check(recomputedSummaryRoot === schema.summaryRegistry.deterministicRootSha256, "summary root not independently recomputed");
check(schema.act01.canonicalLanes === 7 && schema.act01.mutationLanes === 3 && schema.act01.parserBatches === 4, "ACT-01 lane contract drift");
for (const legacy of schema.legacyBridge) check(fileSha(resolve(root, legacy.path)) === legacy.sha256 && legacy.immutable === true, `legacy bridge drift: ${legacy.path}`);
for (const generated of manifest.generated) check(fileSha(resolve(root, generated.path)) === generated.sha256, `generated bridge drift: ${generated.path}`);
check(JSON.stringify(manifest.generated.map((entry) => entry.path)) === JSON.stringify([
  "formal/isabelle/ERC_TRUST/TRUST_Runtime_Bridge_Current_Profile_Generated.thy",
  "formal/kevm/generated/trust-runtime-bridge-current-profile-v1.k",
]), "generated current bridge path drift");
const actualRoot = sha(Buffer.from([
  `${manifest.schema.path}\0${manifest.schema.sha256}\n`,
  ...manifest.generated.map((entry) => `${entry.path}\0${entry.sha256}\n`),
].join(""), "utf8"));
check(actualRoot === manifest.deterministicRootSha256, "current bridge manifest root drift");
check(scope.legacyRegistry.legacyDischargedCount === 6 && scope.progressAxes.coreRefinement.currentProfileQualifiedCount === 0 && scope.progressAxes.coreSupporting.currentProfileQualifiedCount === 0, "scope starting state changed");

console.log(JSON.stringify({
  status: "PASS_CURRENT_PROFILE_BRIDGE_OPEN_GATE",
  schemaSha256: manifest.schema.sha256,
  registrySha256: schema.currentRegistry.sha256,
  tcbRootSha256: schema.tcbIndex.deterministicRootSha256,
  summaryRootSha256: schema.summaryRegistry.deterministicRootSha256,
  legacyBridgeFilesPreserved: schema.legacyBridge.length,
  coreRefinementQualified: 0,
  legacyDischarged: 6,
}, null, 2));
