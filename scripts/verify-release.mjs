// SPDX-License-Identifier: BSD-3-Clause

import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
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
if (manifest.candidate !== "0.2.0-candidate.1") {
  failures.push(`unexpected candidate: ${manifest.candidate}`);
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
for (const [key, expected] of Object.entries(manifest.profileRuntimes ?? {})) {
  const profileArtifact = JSON.parse(readFileSync(resolve(root, expected.artifact), "utf8"));
  const profileCreation = Buffer.from(profileArtifact.bytecode.object.slice(2), "hex");
  const profileRuntime = Buffer.from(profileArtifact.deployedBytecode.object.slice(2), "hex");
  if (sha256(profileCreation) !== expected.creationSha256 || profileCreation.length !== expected.creationBytes) failures.push(`${key} creation bytecode mismatch`);
  if (sha256(profileRuntime) !== expected.runtimeSha256 || profileRuntime.length !== expected.runtimeBytes) failures.push(`${key} runtime bytecode mismatch`);
  if (profileRuntime.length > 24576) failures.push(`EIP-170 overflow: ${key} ${profileRuntime.length}`);
}

const deterministicPath = resolve(root, "evidence", "deterministic-build.json");
if (!existsSync(deterministicPath)) {
  console.log("deterministic build receipt absent: lane pending, governed by evidence/current-profile-release-index-v3.json");
} else {
  const deterministic = JSON.parse(readFileSync(deterministicPath, "utf8"));
  for (const [key, expected] of Object.entries(manifest.profileRuntimes ?? {})) {
    for (const [name, build] of [["buildA", deterministic.buildA], ["buildB", deterministic.buildB]]) {
      const subject = build.subjects?.[key];
      if (!subject || subject.runtimeSha256 !== expected.runtimeSha256 || subject.creationSha256 !== expected.creationSha256) {
        failures.push(`deterministic ${name} ${key} identity mismatch`);
      }
    }
  }
  for (const [name, build] of [["buildA", deterministic.buildA], ["buildB", deterministic.buildB]]) {
    if (build.creationSha256 !== sha256(creation) || build.creationBytes !== creation.length) {
      failures.push(`deterministic ${name} creation identity mismatch`);
    }
    if (build.runtimeSha256 !== sha256(runtime) || build.runtimeBytes !== runtime.length) {
      failures.push(`deterministic ${name} runtime identity mismatch`);
    }
  }
  if (
    deterministic.buildA.creationSha256 !== deterministic.buildB.creationSha256
    || deterministic.buildA.runtimeSha256 !== deterministic.buildB.runtimeSha256
  ) failures.push("deterministic build pair mismatch");
}

const mutationPath = resolve(root, "evidence", "mutation-results.json");
const declaredMutationIds = [...readFileSync(resolve(root, "scripts", "run-mutations.ps1"), "utf8")
  .matchAll(/^\s*Id = "([^"]+)"/gm)].map((match) => match[1]);
const mutation = existsSync(mutationPath) ? JSON.parse(readFileSync(mutationPath, "utf8")) : null;
const mutationInputs = execFileSync(
  "git",
  ["ls-files", "-z", "implementation/src", "implementation/test", "foundry.toml"],
  { cwd: root, encoding: "utf8" },
).split("\0").filter(Boolean).sort();
const mutationSourceRoot = sha256(Buffer.from(
  mutationInputs.map((path) => `${sha256(readFileSync(resolve(root, path)))}  ${path}\n`).join(""),
  "utf8",
));
if (mutation === null) {
  // A missing receipt is a pending lane in successor-development mode; the lane index decides
  // whether that is acceptable. Release mode is enforced by the lane verifier.
  console.log("mutation receipt absent: lane pending, governed by evidence/current-profile-release-index-v3.json");
} else {
  if (mutation.candidateInput?.sourceRootSha256 !== mutationSourceRoot) {
    failures.push(
      `mutation source root mismatch: ${mutation.candidateInput?.sourceRootSha256} != ${mutationSourceRoot}`,
    );
  }
  const receiptIds = (mutation.results ?? []).map((result) => result.id);
  if (
    mutation.schema !== "erc-trust-mutation-result-v2" || !Array.isArray(mutation.results)
    || mutation.results.length !== mutation.total || mutation.killed !== mutation.total
    || mutation.survived !== 0 || declaredMutationIds.length === 0
    || JSON.stringify(receiptIds) !== JSON.stringify(declaredMutationIds)
  ) failures.push(`mutation receipt does not match the declared campaign of ${declaredMutationIds.length} faults`);
  try {
    execFileSync("git", ["merge-base", "--is-ancestor", mutation.candidateInput.gitHead, "HEAD"], {
      cwd: root,
      stdio: "ignore",
    });
  } catch {
    failures.push("mutation gitHead is not an ancestor of the candidate");
  }
  for (const result of mutation.results ?? []) {
    if (
      result.result !== "KILLED" || result.anchorOccurrences < 1
      || result.detectorDiscovered !== 1 || result.detectorExecuted !== 1
      || result.mutantCompiled !== true
    ) failures.push(`invalid mutation receipt: ${result.id}`);
  }
}

if (failures.length) {
  for (const failure of failures) console.error(failure);
  process.exit(1);
}
console.log(
  `release manifest ${mode} PASS: ${Object.keys(manifest.sourceTree.files).length} protected files, runtime ${runtime.length} bytes`,
);
