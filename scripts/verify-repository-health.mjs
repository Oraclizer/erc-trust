// SPDX-License-Identifier: BSD-3-Clause

import { createHash } from "node:crypto";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, extname, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const failures = [];
const proofBoundAllowlist = JSON.parse(readFileSync(
  resolve(root, "evidence", "public-release", "proof-bound-identifiers-v1.json"),
  "utf8",
));
const proofBoundPaths = new Map(proofBoundAllowlist.files.map((entry) => [entry.path, entry]));
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
  /^evidence\/end-to-end-refinement\/kevm\/[^/]+\/(?:positive\/|negative\/)?save\/[0-9a-f]{64}\/(?:proof\.json|kcfg\/(?:kcfg\.json|nodes\/\d+\.json))$/;
const curatedRowProofJsonPattern =
  /^evidence\/end-to-end-refinement\/row-bundles\/[^/]+\/artifacts\/(?:positive|negative)-(?:proof|kcfg|terminal-node-\d+)\.json$/;
const required = [
  "README.md",
  "LICENSE",
  "SECURITY.md",
  "CONTRIBUTING.md",
  "CODE_OF_CONDUCT.md",
  "SUPPORT.md",
  "GOVERNANCE.md",
  "DISCLAIMER.md",
  "CITATION.cff",
  "CHANGELOG.md",
  "FORMAL_VERIFICATION.md",
  "docs/ARCHITECTURE.md",
  "docs/INTEGRATION.md",
  "docs/PROFILES.md",
  "docs/COMMUNITY-REVIEW.md",
  "docs/PROOF-BOUND-IDENTIFIERS.md",
  ".github/CODEOWNERS",
  ".github/PULL_REQUEST_TEMPLATE.md",
  ".github/dependabot.yml",
  ".github/ISSUE_TEMPLATE/config.yml",
  ".github/ISSUE_TEMPLATE/bug.yml",
  ".github/ISSUE_TEMPLATE/specification.yml",
  ".github/ISSUE_TEMPLATE/documentation.yml",
  ".github/workflows/identity.yml",
  ".github/workflows/proofs.yml",
  "evidence/current-profile-release-index-v1.json",
  "evidence/current-profile-release-index-v2.json",
  "evidence/public-release/diet-manifest-v1.json",
  "evidence/public-release/proof-bound-identifiers-v1.json",
  "evidence/public-release/supersession-manifest-v1.json",
];
const textExtensions = new Set([
  ".cff",
  ".json",
  ".k",
  ".md",
  ".mjs",
  ".ps1",
  ".sol",
  ".spec",
  ".svg",
  ".tex",
  ".thy",
  ".ts",
  ".toml",
  ".yaml",
  ".yml",
]);
const excluded = new Set([
  ".git",
  ".certora_internal",
  ".kontrol",
  "cache",
  "dist",
  "kout",
  "node_modules",
  "out",
]);

function walk(path) {
  const rel = relative(root, path).replaceAll("\\", "/");
  if (rel && rel.split("/").some((part) => excluded.has(part))) return [];
  if (statSync(path).isFile()) return [path];
  return readdirSync(path)
    .sort()
    .flatMap((entry) => walk(resolve(path, entry)));
}

for (const path of required) {
  try {
    if (!statSync(resolve(root, path)).isFile()) failures.push(`required path is not a file: ${path}`);
  } catch {
    failures.push(`missing required file: ${path}`);
  }
}
for (const [path, entry] of proofBoundPaths) {
  const absolute = resolve(root, path);
  try {
    const actual = createHash("sha256").update(readFileSync(absolute)).digest("hex");
    if (actual !== entry.sha256) failures.push(`proof-bound allowlist hash drift: ${path}`);
  } catch {
    failures.push(`proof-bound allowlist path missing: ${path}`);
  }
}

const files = walk(root);
for (const absolute of files) {
  const path = relative(root, absolute).replaceAll("\\", "/");
  const extension = extname(path).toLowerCase();
  if (!textExtensions.has(extension)) continue;
  const bytes = readFileSync(absolute);
  const text = bytes.toString("utf8");
  if (bytes.length >= 3 && bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf) {
    failures.push(`UTF-8 BOM is not allowed: ${path}`);
  }
  if (text.includes("\uFFFD")) failures.push(`Unicode replacement character: ${path}`);
  if (/\u0000/.test(text)) failures.push(`NUL byte in text file: ${path}`);
  if (/(C:\\Users\\|\/Users\/[^/]+\/|\/home\/[^/]+\/)/i.test(text)) {
    failures.push(`local absolute path: ${path}`);
  }
  if (/(CERTORAKEY\s*[:=]\s*[A-Za-z0-9_-]{12,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----)/.test(text)) {
    failures.push(`possible credential: ${path}`);
  }
  if (extension !== ".svg" && !lifecycleScannerFiles.has(path) && !proofBoundPaths.has(path) && !machineProofSaveJsonPattern.test(path) &&
      !curatedRowProofJsonPattern.test(path)) {
    const lines = text.split("\n");
    for (let index = 0; index < lines.length; index += 1) {
      const lifecycle = lines[index].match(internalLifecyclePattern);
      const schema = lines[index].match(internalSchemaPattern);
      const match = lifecycle ?? schema;
      if (match) {
        failures.push(`internal lifecycle/property identifier: ${path}:${index + 1}: ${match[0]}`);
      }
    }
  }
  if (privateBranchPattern.test(text)) {
    failures.push(`private branch identifier in public artifact: ${path}`);
  }
  for (const segment of path.split("/")) {
    if (!proofBoundPaths.has(path) && /^(?:m\d+|g\d+|fv\d+)(?:$|[-_.])/i.test(segment)) {
      failures.push(`internal lifecycle/property identifier in path: ${path}`);
      break;
    }
  }
}

const readme = readFileSync(resolve(root, "README.md"), "utf8");
for (const marker of [
  "Unaudited. Not for production.",
  "## Architecture",
  "## Quickstart",
  "## Assurance snapshot",
  "## Documentation",
  "## Security, support, and contributions",
  "## License, citation, and provenance",
]) {
  if (!readme.includes(marker)) failures.push(`README missing required marker: ${marker}`);
}

const publicDocs = [
  "README.md",
  "docs/COMMUNITY-REVIEW.md",
  "docs/INTEGRATION.md",
  "sdk/README.md",
];
for (const path of publicDocs) {
  const text = readFileSync(resolve(root, path), "utf8").toLowerCase();
  if (!text.includes("unaudited") || !text.includes("not for production")) {
    failures.push(`public status warning incomplete: ${path}`);
  }
  if (/do not post before|internal publication draft|links to insert only after/i.test(text)) {
    failures.push(`internal publication instruction leaked: ${path}`);
  }
}

const workflows = files.filter((path) => {
  const rel = relative(root, path).replaceAll("\\", "/");
  return /^\.github\/workflows\/.+\.ya?ml$/.test(rel);
});
for (const absolute of workflows) {
  const path = relative(root, absolute).replaceAll("\\", "/");
  const text = readFileSync(absolute, "utf8");
  if (!/^permissions:\s*$/m.test(text)) failures.push(`workflow missing top-level permissions: ${path}`);
  if (!/timeout-minutes:\s*\d+/m.test(text)) failures.push(`workflow missing job timeout: ${path}`);
  for (const match of text.matchAll(/^\s*uses:\s*([^#\s]+)(?:\s+#.*)?$/gm)) {
    if (!/@[0-9a-f]{40}$/i.test(match[1])) {
      failures.push(`GitHub Action is not pinned to a full commit: ${path}: ${match[1]}`);
    }
  }
}

if (failures.length) {
  for (const failure of failures) console.error(failure);
  process.exit(1);
}

console.log(`repository health PASS: ${files.length} files inspected`);
