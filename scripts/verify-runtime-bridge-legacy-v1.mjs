import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const expected = new Map([
  ["evidence/end-to-end-refinement/runtime-bridge/schema.json", "f087342d0eaa57a02468ff78e553ad42bb25fe027e833f311a5d0caac72383b7"],
  ["evidence/end-to-end-refinement/runtime-bridge/generated-manifest.json", "50085fbb6ed540c036754820177785813c96c72191a84f297f8c9952d9802827"],
  ["formal/isabelle/ERC_TRUST/TRUST_Runtime_Bridge_Generated.thy", "48ef15ed0789be51c0d56f22740d93ba5c7a474116209be66855e8c95b870728"],
  ["formal/kevm/generated/trust-runtime-bridge.k", "bf8d587f7644d002d05bc7ab16806a39a3354d216cdcad53f504a9bb8b99d836"],
]);
function sha(bytes) { return createHash("sha256").update(bytes).digest("hex"); }
function check(condition, message) { if (!condition) throw new Error(message); }
for (const [path, expectedSha] of expected) check(sha(readFileSync(resolve(root, path))) === expectedSha, `legacy bridge drift: ${path}`);
const schema = JSON.parse(readFileSync(resolve(root, "evidence/end-to-end-refinement/runtime-bridge/schema.json"), "utf8"));
check(schema.sourceBinding.obligationRegistrySha256 === "3b6b0910539c58e53db7c6dbf11c8bf0e4a4d9d7aaec6d8b5d233573dc514dba", "legacy registry identity drift");
check(schema.obligationIds.length === 79 && new Set(schema.obligationIds).size === 79, "legacy obligation inventory drift");
console.log(JSON.stringify({ status: "PASS_LEGACY_BRIDGE_BYTE_EXACT", legacyRegistrySha256: schema.sourceBinding.obligationRegistrySha256, files: expected.size, currentProfileCredit: 0 }, null, 2));
