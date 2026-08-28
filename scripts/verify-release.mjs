// SPDX-License-Identifier: BSD-3-Clause

import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifestPath = resolve(root, "evidence", "release-manifest.json");
const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
const failures = [];
const modeArgument = process.argv.find((argument) => argument.startsWith("--mode="));
const mode = modeArgument?.slice("--mode=".length) ?? "full";
const sha256 = (data) => createHash("sha256").update(data).digest("hex");
const canonicalTextBytes = (absolute) =>
  Buffer.from(
    readFileSync(absolute, "utf8").replace(/\r\n?/g, "\n"),
    "utf8",
  );

if (!new Set(["pr", "full"]).has(mode)) {
  failures.push(`unsupported verification mode: ${mode}`);
}
if (manifest.sourceTree.scope !== "protected-release-inputs-v1") {
  failures.push(`unsupported source-tree scope: ${manifest.sourceTree.scope}`);
}
if (manifest.sourceTree.algorithm !== "sha256-canonical-utf8-lf-lines-v1") {
  failures.push(`unsupported source-tree algorithm: ${manifest.sourceTree.algorithm}`);
}

for (const [path, expected] of Object.entries(manifest.sourceTree.files)) {
  const absolute = resolve(root, path);
  if (!existsSync(absolute)) {
    failures.push(`missing: ${path}`);
    continue;
  }
  const actual = sha256(canonicalTextBytes(absolute));
  if (actual !== expected) failures.push(`hash mismatch: ${path}`);
}

const rootHash = sha256(
  Object.keys(manifest.sourceTree.files)
    .sort()
    .map((path) => `${manifest.sourceTree.files[path]}  ${path}\n`)
    .join(""),
);
if (mode === "full" && rootHash !== manifest.sourceTree.root) {
  failures.push("source tree root mismatch");
}

const artifact = JSON.parse(
  readFileSync(resolve(root, manifest.trustToken.artifact), "utf8"),
);
const creation = Buffer.from(artifact.bytecode.object.slice(2), "hex");
const runtime = Buffer.from(artifact.deployedBytecode.object.slice(2), "hex");
if (sha256(creation) !== manifest.trustToken.creationSha256) {
  failures.push("creation bytecode mismatch");
}
if (sha256(runtime) !== manifest.trustToken.runtimeSha256) {
  failures.push("runtime bytecode mismatch");
}
if (runtime.length > 24576) failures.push(`EIP-170 overflow: ${runtime.length}`);

if (failures.length) {
  for (const failure of failures) console.error(failure);
  process.exit(1);
}
console.log(
  `release manifest ${mode} PASS: ${Object.keys(manifest.sourceTree.files).length} protected files, runtime ${runtime.length} bytes`,
);
