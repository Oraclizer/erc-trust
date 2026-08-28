// SPDX-License-Identifier: BSD-3-Clause

import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const bytes = (path) => readFileSync(resolve(root, path));
const json = (path) => JSON.parse(bytes(path).toString("utf8"));
const check = (condition, message) => { if (!condition) throw new Error(message); };

const index = json("evidence/current-profile-release-index-v1.json");
check(index.kind === "ERC_TRUST_CURRENT_PROFILE_RELEASE_INDEX_V1"
  && index.status === "PASS_CURRENT_PROFILE_RELEASE_CANDIDATE", "release index identity drift");

for (const [name, entry] of Object.entries(index.qualificationInputs)) {
  check(sha256(bytes(entry.path)) === entry.sha256, `${name} identity drift`);
}

const aggregate = json(index.qualificationInputs.packageAggregate.path);
check(aggregate.status === "PASS_C_SERIES_C0_THROUGH_C6_SEVEN_OF_SEVEN"
  && aggregate.terminal && aggregate.qualifiedCount === 7
  && aggregate.requiredCount === 7 && aggregate.heldCount === 0
  && aggregate.openCount === 0, "package aggregate disposition drift");

const rows = json(index.qualificationInputs.rowIndex.path);
check(rows.progress.coreRefinement.qualified === 49 && rows.progress.coreRefinement.required === 49
  && rows.progress.coreSupporting.qualified === 24 && rows.progress.coreSupporting.required === 24
  && rows.progress.fullAssuranceBacklog.qualified === 0
  && rows.progress.fullAssuranceBacklog.required === 6
  && rows.frozenRows.length === 0
  && rows.counterexamples.actualProductCounterexampleCount === 0,
"row qualification disposition drift");

const historicalRuntime = json(index.qualificationInputs.historicalRuntimeQualification.path);
const publicRuntime = json(index.qualificationInputs.publicRuntimeQualification.path);
check(historicalRuntime.kind === "ERC_TRUST_RUNTIME_BINDING_CURRENT_PROFILE_QUALIFICATION_V1"
  && publicRuntime.kind === "ERC_TRUST_RUNTIME_BINDING_CURRENT_PROFILE_QUALIFICATION_V2",
"runtime qualification succession drift");
check(historicalRuntime.subjects.length === 7 && publicRuntime.subjects.length === 7,
  "runtime subject count drift");
for (const subject of publicRuntime.subjects) {
  const historical = historicalRuntime.subjects.find((entry) => entry.id === subject.id);
  check(historical
    && historical.historicalArtifactSha256 === subject.historicalArtifactSha256
    && historical.currentArtifactSha256 === subject.currentArtifactSha256
    && Object.values(subject.semanticChecks).every((value) => value === true),
  `runtime semantic or expected-hash drift: ${subject.id}`);
}
check(publicRuntime.verifierMutationValidation.semanticMutations.killed === 42
  && publicRuntime.verifierMutationValidation.semanticMutations.required === 42
  && publicRuntime.verifierMutationValidation.packagingOnlyMutations.driftPass === 7
  && publicRuntime.verifierMutationValidation.expectedHashOverwriteMutations.failedClosed === 7
  && !publicRuntime.qualification.expectedArtifactHashesOverwritten,
"runtime hostile validation drift");

const supersession = json("evidence/public-release/supersession-manifest-v1.json");
const diet = json("evidence/public-release/diet-manifest-v1.json");
check(supersession.kind === "ERC_TRUST_PUBLIC_RELEASE_SUPERSESSION_MANIFEST_V1"
  && supersession.supersessions.length === 6
  && supersession.archiveOnlyPrivateBranchRecords.length === 22
  && supersession.supersessions.every((entry) => !entry.expectedHashesOverwritten),
"public supersession manifest drift");
for (const entry of supersession.supersessions) {
  check(sha256(bytes(entry.publicPath)) === entry.publicSha256,
    `public supersession file identity drift: ${entry.role}`);
  if (existsSync(resolve(root, entry.historicalPath))) {
    check(sha256(bytes(entry.historicalPath)) === entry.historicalSha256,
      `historical supersession file identity drift: ${entry.role}`);
  } else {
    const archived = diet.removedFiles.find((candidate) => candidate.path === entry.historicalPath);
    check(archived?.sha256 === entry.historicalSha256 && archived.disposition === "ARCHIVE_ONLY",
      `historical supersession archive binding drift: ${entry.role}`);
  }
}
const publicManifest = json(supersession.supersessions[0].publicPath);
check(publicManifest.sourceProvenance.historicalManifestSha256
  === supersession.supersessions[0].historicalSha256,
"runtime manifest supersession provenance drift");
if (existsSync(resolve(root, supersession.supersessions[0].historicalPath))) {
  const historicalManifest = json(supersession.supersessions[0].historicalPath);
  check(JSON.stringify(historicalManifest.bundles) === JSON.stringify(publicManifest.bundles)
    && JSON.stringify(historicalManifest.compiler) === JSON.stringify(publicManifest.compiler)
    && historicalManifest.claimBoundary === publicManifest.claimBoundary
    && historicalManifest.deterministicRootSha256 === publicManifest.deterministicRootSha256,
  "runtime manifest semantic projection drift");
}
const publicFreeze = json(supersession.supersessions[1].publicPath);
check(publicFreeze.sourceProvenance.historicalFreezeSha256
  === supersession.supersessions[1].historicalSha256,
"runtime freeze supersession provenance drift");
if (existsSync(resolve(root, supersession.supersessions[1].historicalPath))) {
  const historicalFreeze = json(supersession.supersessions[1].historicalPath);
  check(JSON.stringify(historicalFreeze.runtimes) === JSON.stringify(publicFreeze.runtimes)
    && JSON.stringify(historicalFreeze.driftRule) === JSON.stringify(publicFreeze.driftRule),
  "runtime freeze semantic projection drift");
}

check(index.progress.reusablePackages === "7/7"
  && index.progress.coreRefinement === "49/49"
  && index.progress.supportingCurrentProfile === "24/24"
  && index.progress.frozenRows === 0
  && index.progress.optionalBacklog === "0/6"
  && index.runtime.nativeBytes === 24142
  && index.runtime.eip170MarginBytes === 434
  && !index.runtime.expectedHashesOverwritten,
"release progress or runtime boundary drift");

console.log(JSON.stringify({
  status: "PASS_CURRENT_PROFILE_RELEASE_CANDIDATE",
  reusablePackages: "7/7",
  coreRefinement: "49/49",
  supportingCurrentProfile: "24/24",
  optionalBacklog: "0/6",
  runtimeSubjects: 7,
  expectedHashesOverwritten: false,
}, null, 2));
