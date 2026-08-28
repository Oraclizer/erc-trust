// SPDX-License-Identifier: BSD-3-Clause

import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const evidence = resolve(root, "evidence", "end-to-end-refinement");
const historicalManifestPath = resolve(evidence, "runtime-binding", "manifest.json");
const publicManifestPath = resolve(evidence, "runtime-binding", "manifest-public-v1.json");
const historicalFreezePath = resolve(evidence, "m4-runtime-freeze-v1.json");
const publicFreezePath = resolve(evidence, "runtime-freeze-public-v1.json");

const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const readJson = (path) => JSON.parse(readFileSync(path, "utf8"));
const writeJson = (path, value) => {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`, "utf8");
};

const historicalManifest = readJson(historicalManifestPath);
const historicalFreeze = readJson(historicalFreezePath);

const publicManifest = {
  schemaVersion: 3,
  kind: "ERC_TRUST_PUBLIC_RUNTIME_BINDING_MANIFEST_V1",
  bundles: historicalManifest.bundles,
  claimBoundary: historicalManifest.claimBoundary,
  compiler: historicalManifest.compiler,
  deterministicRootSha256: historicalManifest.deterministicRootSha256,
  sourceProvenance: {
    archiveRepository: "Oraclizer/erc-trust-archive",
    archiveCommit: "366b625dac90d4584432d7d6939629434734ecb8",
    archiveTree: "25a1710c865143eb70f0da3d185ebdc3149214b0",
    publicDefaultBranch: "main",
    historicalManifestSha256: sha256(readFileSync(historicalManifestPath)),
    privateDevelopmentCoordinatesRemoved: true,
  },
};

writeJson(publicManifestPath, publicManifest);
const publicManifestSha256 = sha256(readFileSync(publicManifestPath));

const publicFreeze = {
  schemaVersion: 2,
  kind: "ERC_TRUST_PUBLIC_EXACT_RUNTIME_FREEZE_V1",
  status: "FROZEN_FOR_CURRENT_PROFILE_REPLAY",
  date: "2026-08-28",
  sourceProvenance: {
    archiveRepository: "Oraclizer/erc-trust-archive",
    archiveCommit: "366b625dac90d4584432d7d6939629434734ecb8",
    archiveTree: "25a1710c865143eb70f0da3d185ebdc3149214b0",
    historicalFreezeSha256: sha256(readFileSync(historicalFreezePath)),
    privateDevelopmentCoordinatesRemoved: true,
  },
  runtimes: historicalFreeze.runtimes,
  constructorAndCompilerBinding: {
    manifestPath: "evidence/end-to-end-refinement/runtime-binding/manifest-public-v1.json",
    manifestSha256: publicManifestSha256,
    resolvedFixturePath: historicalFreeze.constructorAndCompilerBinding.resolvedFixturePath,
    resolvedFixtureSha256: historicalFreeze.constructorAndCompilerBinding.resolvedFixtureSha256,
  },
  driftRule: historicalFreeze.driftRule,
  nonclaims: [
    "The runtime freeze does not prove compiler correctness, constructor execution, deployment identity, or live topology.",
    "Historical feasibility and process receipts remain in the private archive and are not public replay inputs.",
    "Expected runtime, source, compiler, and artifact hashes are preserved without replacement.",
  ],
};

writeJson(publicFreezePath, publicFreeze);
console.log(JSON.stringify({
  status: "PASS",
  publicManifest: {
    path: "evidence/end-to-end-refinement/runtime-binding/manifest-public-v1.json",
    sha256: publicManifestSha256,
  },
  publicRuntimeFreeze: {
    path: "evidence/end-to-end-refinement/runtime-freeze-public-v1.json",
    sha256: sha256(readFileSync(publicFreezePath)),
  },
  expectedHashesOverwritten: false,
}, null, 2));
