// SPDX-License-Identifier: BSD-3-Clause

import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { extname, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { dirname } from "node:path";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const required = [
  "README.md",
  "LICENSE",
  "CONTRIBUTING.md",
  "SECURITY.md",
  "CODE_OF_CONDUCT.md",
  "SUPPORT.md",
  "GOVERNANCE.md",
  "DISCLAIMER.md",
  "CITATION.cff",
  "CHANGELOG.md",
  "FORMAL_VERIFICATION.md",
  "docs/ERC-DRAFT.md",
  "docs/ARCHITECTURE.md",
  "docs/COMMUNITY-REVIEW.md",
  "docs/INTEGRATION.md",
  "docs/PROFILES.md",
  "docs/PROOF-BOUND-IDENTIFIERS.md",
  "docs/assets/erc-trust-banner.svg",
  "docs/assets/architecture-overview.svg",
  "docs/assets/architecture-action-flow.svg",
  "docs/assets/architecture-native-sequence.svg",
  "docs/assets/architecture-erc3643-profile.svg",
  "docs/assets/verification-architecture.svg",
  "implementation/certora/ERC3643Partial.conf",
  "implementation/certora/ERC3643Partial.spec",
  "implementation/certora/ERC3643PartialHarness.sol",
  ".github/ISSUE_TEMPLATE/config.yml",
  ".github/ISSUE_TEMPLATE/documentation.yml",
  ".github/CODEOWNERS",
  ".github/PULL_REQUEST_TEMPLATE.md",
  ".github/dependabot.yml",
  ".github/workflows/identity.yml",
  ".github/workflows/proofs.yml",
  "schemas/receipt.schema.json",
  "vectors/conformance-v1.json",
  "sdk/package.json",
  "sdk/pnpm-lock.yaml",
  "evidence/trust-ref-matrix.md",
  "evidence/claim-matrix.md",
  "evidence/isabelle-solidity-applicability.md",
  "evidence/verification-summary.md",
  "evidence/release-manifest.json",
  "evidence/candidate-2/current-profile-release-index-v1.json",
  "evidence/candidate-2/current-profile-release-index-v2.json",
  "evidence/current-profile-release-index-v3.json",
  "evidence/evidence-mode.json",
  "evidence/evidence-expectations-v3.json",
  "evidence/mutation-definition-rebind-v1.json",
  "scripts/mutation-campaign-v1.json",
  "evidence/public-release/diet-manifest-v2.json",
  "evidence/public-release/diet-manifest-v1.json",
  "evidence/public-release/proof-bound-identifiers-v1.json",
  "evidence/public-release/supersession-manifest-v1.json",
];
const excludedSegments = new Set([
  ".git",
  ".certora_internal",
  ".kontrol",
  "cache",
  "dist",
  "kout",
  "node_modules",
  "out",
]);
const failures = [];
const proofBoundAllowlist = JSON.parse(readFileSync(
  resolve(root, "evidence", "public-release", "proof-bound-identifiers-v1.json"),
  "utf8",
));
const proofBoundPaths = new Map(proofBoundAllowlist.files.map((entry) => [entry.path, entry]));
const lifecycleTextExtensions = new Set([
  ".cff",
  ".conf",
  ".json",
  ".k",
  ".md",
  ".mjs",
  ".ps1",
  ".sol",
  ".spec",
  ".tex",
  ".thy",
  ".toml",
  ".ts",
  ".yaml",
  ".yml",
]);
const internalLifecyclePattern = /\b(?:M[1-9]\d*|G[1-9]\d*|FV\d+)\b/;
const internalSchemaPattern = /changedByM\d|g\d+Regression|fv\d+Rows/i;
const privateBranchPattern = /\b(?:sourceBranch|formerBranch|branch)\s*[:=]\s*["'](?:codex|claude)\//i;
const lifecycleScannerFiles = new Set([
  "docs/PROOF-BOUND-IDENTIFIERS.md",
  "evidence/public-release/diet-manifest-v1.json",
  "evidence/public-release/proof-bound-identifiers-v1.json",
  "evidence/public-release/supersession-manifest-v1.json",
  "scripts/verify-public-release-tree.mjs",
  "scripts/verify-public-surface.mjs",
  "scripts/verify-repository-health.mjs",
]);
const machineProofSaveJsonPattern =
  /^evidence\/candidate-2\/end-to-end-refinement\/kevm\/[^/]+\/(?:positive\/|negative\/)?save\/[0-9a-f]{64}\/(?:proof\.json|kcfg\/(?:kcfg\.json|nodes\/\d+\.json))$/;
const curatedRowProofJsonPattern =
  /^evidence\/candidate-2\/end-to-end-refinement\/row-bundles\/[^/]+\/artifacts\/(?:positive|negative)-(?:proof|kcfg|terminal-node-\d+)\.json$/;

function walk(absolute) {
  const relativePath = relative(root, absolute).replaceAll("\\", "/");
  if (relativePath && relativePath.split("/").some((part) => excludedSegments.has(part))) return [];
  if (statSync(absolute).isFile()) return [absolute];
  return readdirSync(absolute)
    .sort()
    .flatMap((entry) => walk(resolve(absolute, entry)));
}

for (const path of required) {
  if (!existsSync(resolve(root, path))) failures.push(`missing required file: ${path}`);
}
for (const [path, entry] of proofBoundPaths) {
  const absolute = resolve(root, path);
  if (!existsSync(absolute)) {
    failures.push(`proof-bound allowlist path missing: ${path}`);
    continue;
  }
  const actual = createHash("sha256").update(readFileSync(absolute)).digest("hex");
  if (actual !== entry.sha256) failures.push(`proof-bound allowlist hash drift: ${path}`);
}

const files = walk(root);
for (const absolute of files) {
  const path = relative(root, absolute).replaceAll("\\", "/");
  const extension = extname(path).toLowerCase();
  if (extension === ".json") {
    try {
      JSON.parse(readFileSync(absolute, "utf8"));
    } catch (error) {
      failures.push(`invalid JSON: ${path}: ${error.message}`);
    }
  }
  if (extension === ".sol") {
    const text = readFileSync(absolute, "utf8");
    if (!text.startsWith("// SPDX-License-Identifier:")) failures.push(`missing SPDX: ${path}`);
  }
  if ([".md", ".json", ".ts", ".sol", ".yml", ".yaml", ".mjs", ".ps1"].includes(extension)) {
    const text = readFileSync(absolute, "utf8");
    if (/C:\\Users\\|\/Users\/[^/]+\/|\/home\/[^/]+\//i.test(text)) {
      failures.push(`local absolute path: ${path}`);
    }
    if (/(CERTORAKEY\s*[:=]\s*[A-Za-z0-9_-]{12,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----)/.test(text)) {
      failures.push(`possible credential: ${path}`);
    }
  }
  if (lifecycleTextExtensions.has(extension) && !lifecycleScannerFiles.has(path) && !proofBoundPaths.has(path)) {
    const text = readFileSync(absolute, "utf8");
    if (!machineProofSaveJsonPattern.test(path) && !curatedRowProofJsonPattern.test(path)) {
      const lines = text.split("\n");
      for (let index = 0; index < lines.length; index += 1) {
        const match = lines[index].match(internalLifecyclePattern) ?? lines[index].match(internalSchemaPattern);
        if (match) {
          failures.push(`internal lifecycle/property identifier: ${path}:${index + 1}: ${match[0]}`);
        }
      }
    }
    if (privateBranchPattern.test(text)) {
      failures.push(`private branch identifier in public artifact: ${path}`);
    }
  }
  for (const segment of path.split("/")) {
    if (!proofBoundPaths.has(path) && /^(?:m\d+|g\d+|fv\d+)(?:$|[-_.])/i.test(segment)) {
      failures.push(`internal lifecycle/property identifier in path: ${path}`);
      break;
    }
  }
}

for (const path of ["README.md", "docs/ERC-DRAFT.md", "docs/COMMUNITY-REVIEW.md", "sdk/README.md"]) {
  if (!existsSync(resolve(root, path))) continue;
  const text = readFileSync(resolve(root, path), "utf8").toLowerCase();
  if (!text.includes("unaudited") || !text.includes("not for production")) {
    failures.push(`missing assurance warning: ${path}`);
  }
}

{
  const adapter = readFileSync(resolve(root, "implementation/src/profiles/ERC3643TrustAdapter.sol"), "utf8");
  const governor = readFileSync(resolve(root, "implementation/src/profiles/ProfileGovernor.sol"), "utf8");
  for (const snippet of [
    "profileId: TrustKernelTypes.PROFILE_ERC3643_PARTIAL,",
    "profileKind: TrustKernelTypes.ProfileKind.PARTIAL,",
    "full: false,",
    "function sealedTopologyLive() external view returns (bool)",
  ]) {
    if (!adapter.includes(snippet)) failures.push(`ERC-3643 Partial surface missing: ${snippet}`);
  }
  if (/profileId:\s*TrustKernelTypes\.PROFILE_ERC3643_VERIFIED_FULL/.test(adapter)) {
    failures.push("current ERC-3643 adapter reports the reserved Verified Full profile id");
  }
  if (/profileKind:\s*TrustKernelTypes\.ProfileKind\.VERIFIED_FULL/.test(adapter)) {
    failures.push("current ERC-3643 adapter reports Verified Full kind");
  }
  if (!governor.includes("function sealedTopologyLive(address adapter) public view returns (bool)")) {
    failures.push("profile governor lacks the sealed-topology liveness view");
  }
  if (/function\s+isFull\s*\(/.test(governor)) failures.push("profile governor exposes the obsolete isFull view");
}

{
  const proposal = readFileSync(resolve(root, "docs/ERC-DRAFT.md"), "utf8");
  const specification = proposal.indexOf("## Specification");
  const rationale = proposal.indexOf("## Rationale");
  if (specification === -1 || rationale <= specification) {
    failures.push("proposal Specification or Rationale boundary missing");
  } else {
    const outsideSpecification = `${proposal.slice(0, specification)}\n${proposal.slice(rationale)}`;
    const normative = [...outsideSpecification.matchAll(/\b(?:MUST(?: NOT)?|SHALL(?: NOT)?|SHOULD(?: NOT)?|REQUIRED|RECOMMENDED|NOT RECOMMENDED|MAY|OPTIONAL)\b/g)];
    if (normative.length > 0) failures.push(`RFC 2119 keyword outside Specification: ${normative[0][0]}`);
  }
}

const tracked = execFileSync("git", ["ls-files", "-z"], {
  cwd: root,
  encoding: "utf8",
})
  .split("\0")
  .filter(Boolean);
const generatedInTree = tracked
  .filter((path) => /(^|\/)(out|cache|kout|node_modules|dist)(\/|$)/.test(path));
for (const path of generatedInTree) failures.push(`generated product in public scan: ${path}`);

if (failures.length) {
  for (const failure of failures) console.error(failure);
  process.exit(1);
}
console.log(`public surface PASS: ${files.length} source/document files scanned`);
