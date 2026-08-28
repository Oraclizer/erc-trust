// SPDX-License-Identifier: BSD-3-Clause

import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const pilot = resolve(root, "pilot");
const manifest = JSON.parse(
  readFileSync(resolve(pilot, "evidence", "hashes-v2.json"), "utf8"),
);
const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");
const failures = [];

for (const [path, expected] of Object.entries(manifest.files)) {
  const absolute = resolve(root, path);
  if (!existsSync(absolute)) {
    failures.push(`missing pilot-bound file: ${path}`);
    continue;
  }
  const actual = sha256(readFileSync(absolute));
  if (actual !== expected) failures.push(`pilot file hash mismatch: ${path}`);
}

const artifacts = [
  ["TrustFreezePilot", "TrustFreezePilot.sol", "TrustFreezePilot.json"],
  ["MockBoundPolicy", "MockBoundPolicy.sol", "MockBoundPolicy.json"],
];
for (const [name, source, artifactName] of artifacts) {
  const artifactPath = resolve(pilot, "out", source, artifactName);
  if (!existsSync(artifactPath)) {
    failures.push(`missing pilot artifact: ${artifactName}`);
    continue;
  }
  const artifactBytes = readFileSync(artifactPath);
  const artifact = JSON.parse(artifactBytes);
  if (sha256(artifactBytes) !== manifest.artifacts[artifactName]) {
    failures.push(`pilot artifact hash mismatch: ${artifactName}`);
  }
  if (name === "TrustFreezePilot") {
    const creationHex = artifact.bytecode.object;
    const runtimeHex = artifact.deployedBytecode.object;
    if (
      sha256(Buffer.from(creationHex, "utf8")) !==
      manifest.artifacts["TrustFreezePilot.creationBytecode"]
    ) {
      failures.push("pilot creation bytecode hash mismatch");
    }
    if (
      sha256(Buffer.from(runtimeHex, "utf8")) !==
      manifest.artifacts["TrustFreezePilot.runtimeBytecode"]
    ) {
      failures.push("pilot runtime bytecode hash mismatch");
    }
  }
}

if (failures.length) {
  for (const failure of failures) console.error(failure);
  process.exit(1);
}
console.log(
  `pilot binding PASS: ${Object.keys(manifest.files).length} files, ` +
    `${artifacts.length} artifacts, exact creation/runtime bytecode`,
);
