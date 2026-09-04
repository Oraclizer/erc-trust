// SPDX-License-Identifier: BSD-3-Clause

import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { keccak256 } from "../sdk/node_modules/ethers/lib.esm/index.js";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const output = resolve(root, "evidence", "release-manifest.json");
const roots = [
  "implementation/src",
  "implementation/certora",
  "implementation/kontrol",
  "implementation/test",
  "formal/isabelle/ERC_TRUST",
  "formal/kevm",
  "evidence/candidate-2",
  "evidence/end-to-end-refinement",
  "evidence/runtime-binding-v3",
  "evidence/public-release",
  "sdk/src",
  "schemas",
  "spec",
  "vectors",
  "scripts",
];
// Lane receipts of the successor: protected by the manifest whenever present, but their
// presence is governed by the lane index, so a missing receipt is a pending lane, not a
// missing release input.
const optionalFiles = [
  "evidence/deterministic-build.json",
  "evidence/mutation-results.json",
  "evidence/foundry-results-v3.json",
  "evidence/isabelle-results-v3.json",
  "evidence/kontrol-results-v3.json",
  "evidence/certora-results-v3.json",
  "evidence/runtime-binding-v3.json",
];
const singleFiles = [
  "formal-dependencies.lock.json",
  "formal-dependencies-public-v1.lock.json",
  "foundry.toml",
  "sdk/package.json",
  "sdk/pnpm-lock.yaml",
  "sdk/tsconfig.json",
  "evidence/README.md",
  "evidence/independent-reproduction-v3.json",
  "evidence/claim-matrix.md",
  "evidence/known-limitations.md",
  "evidence/clean-room-provenance.md",
  "evidence/evidence-mode.json",
  "evidence/evidence-expectations-v3.json",
  "evidence/current-profile-release-index-v3.json",
  "evidence/model-regression.json",
  "evidence/isabelle-solidity-applicability.md",
  "evidence/mutator-inventory.md",
  "evidence/pilot-mutation-results.json",
  "evidence/pilot-regression.json",
  "evidence/trust-ref-matrix.md",
  "evidence/verification-summary.md",
];

function sha256(data) {
  return createHash("sha256").update(data).digest("hex");
}

function canonicalTextBytes(path) {
  const text = readFileSync(resolve(root, path), "utf8").replace(/\r\n?/g, "\n");
  return Buffer.from(text, "utf8");
}

const tracked = execFileSync("git", ["ls-files", "-z"], { cwd: root, encoding: "utf8" })
  .split("\0")
  .filter(Boolean);
for (const path of singleFiles) {
  if (!tracked.includes(path) || !existsSync(resolve(root, path))) {
    throw new Error(`Missing mandatory release input: ${path}`);
  }
}
const files = tracked
  .filter((path) => roots.some((entry) => path === entry || path.startsWith(`${entry}/`)) || singleFiles.includes(path) || optionalFiles.includes(path))
  .filter((path) => existsSync(resolve(root, path)))
  .filter((path) => !path.includes("/node_modules/") && !path.includes("/dist/"))
  .sort();
const fileHashes = Object.fromEntries(
  files.map((path) => [path, sha256(canonicalTextBytes(path))]),
);
const sourceTreeRoot = sha256(
  files.map((path) => `${fileHashes[path]}  ${path}\n`).join(""),
);

const artifactPath = resolve(root, "out", "TrustToken.sol", "TrustToken.json");
if (!existsSync(artifactPath)) {
  throw new Error("Missing out/TrustToken.sol/TrustToken.json; run forge build first");
}
const artifact = JSON.parse(readFileSync(artifactPath, "utf8"));
const creationHex = artifact.bytecode.object;
const runtimeHex = artifact.deployedBytecode.object;
const creation = Buffer.from(creationHex.slice(2), "hex");
const runtime = Buffer.from(runtimeHex.slice(2), "hex");

const manifest = {
  schema: "erc-trust-release-manifest-v1",
  candidate: "0.2.0-candidate.1",
  status: "unaudited-not-for-production",
  git: {
    bindingMode: "tracked-source-tree",
  },
  profile: {
    native: "ERC-TRUST/v2/native-full",
    erc3643: "ERC-TRUST/v2/erc3643-partial",
    proxySupported: false,
    migrationSupported: false,
  },
  toolchain: {
    solidity: "0.8.36+commit.8a079791",
    foundry: "1.7.1",
    foundryCommit: "4072e48705af9d93e3c0f6e29e93b5e9a40caed8",
    evmVersion: "cancun",
    optimizer: true,
    optimizerRuns: 1,
    viaIR: true,
    bytecodeHash: "none",
    cborMetadata: false,
    node: "24.14.0",
    pnpm: "11.9.0",
    ethers: "6.17.0",
    typescript: "7.0.2",
    certora: "8.19.1",
    kontrol: "1.0.255",
    kevm: "1.0.678",
    isabelle: "Isabelle2025-2",
  },
  sourceTree: {
    scope: "protected-release-inputs-v1",
    algorithm: "sha256-canonical-utf8-lf-lines-v1",
    root: sourceTreeRoot,
    files: fileHashes,
  },
  profileRuntimes: Object.fromEntries([
    ["erc3643Adapter", "out/ERC3643TrustAdapter.sol/ERC3643TrustAdapter.json"],
    ["profileGovernor", "out/ProfileGovernor.sol/ProfileGovernor.json"],
  ].map(([key, artifactPath]) => {
    const profileArtifact = JSON.parse(readFileSync(resolve(root, artifactPath), "utf8"));
    const profileCreation = Buffer.from(profileArtifact.bytecode.object.slice(2), "hex");
    const profileRuntime = Buffer.from(profileArtifact.deployedBytecode.object.slice(2), "hex");
    return [key, {
      artifact: artifactPath,
      creationBytes: profileCreation.length,
      runtimeBytes: profileRuntime.length,
      eip170MarginBytes: 24576 - profileRuntime.length,
      creationSha256: sha256(profileCreation),
      runtimeSha256: sha256(profileRuntime),
    }];
  })),
  trustToken: {
    artifact: "out/TrustToken.sol/TrustToken.json",
    creationBytes: creation.length,
    runtimeBytes: runtime.length,
    eip170MarginBytes: 24576 - runtime.length,
    creationSha256: sha256(creation),
    runtimeSha256: sha256(runtime),
    creationKeccak256: keccak256(creationHex),
    runtimeKeccak256: keccak256(runtimeHex),
  },
  preservedModel: {
    path: "formal/isabelle/ERC_TRUST",
    releasePdfSha256: "A1C2E2C8684F2C517D03BBA1EC2B59713D303712BFD6E86A9F3D7033A3102959",
    releaseManifestSha256: "FE3F5661EBAEBB5D8F08851744B398CC8B852BA6EBBED970AB950EAF354F5665",
    changedByReferenceCandidate: false,
  },
  evidence: {
    mode: "evidence/evidence-mode.json",
    lanes: "evidence/current-profile-release-index-v3.json",
    historical: "evidence/candidate-2/README.md",
    deterministicBuild: "evidence/deterministic-build.json",
    mutation: "evidence/mutation-results.json",
    modelRegression: "evidence/model-regression.json",
    isabelleSolidityApplicability: "evidence/isabelle-solidity-applicability.md",
    pilotRegression: "evidence/pilot-regression.json",
    trustRef: "evidence/trust-ref-matrix.md",
  },
};

mkdirSync(dirname(output), { recursive: true });
writeFileSync(output, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");
