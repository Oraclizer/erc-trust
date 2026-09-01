// SPDX-License-Identifier: BSD-3-Clause

import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { dirname, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const candidate = "0.1.0-candidate.2";
const baselineCommit = "e7598dbf268d81743a06dae595513bed59ea8d2d";
const expectedProductionDeltaSha256 = "1e2300472e80b6853019c0d3dfbae52130336894a25802e2636087a894c644c8";
const packagePath = "evidence/end-to-end-refinement/c-series-terminal-qualification-v2.json";
const rowPath = "evidence/end-to-end-refinement/current-profile-row-qualifications-v2.json";
const releasePath = "evidence/current-profile-release-index-v2.json";

const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const bytes = (path) => readFileSync(resolve(root, path));
const json = (path) => JSON.parse(bytes(path).toString("utf8"));
const check = (condition, message) => { if (!condition) throw new Error(message); };
const fileRef = (path) => ({ path, sha256: sha256(bytes(path)) });
const stable = (value) => {
  if (Array.isArray(value)) return value.map(stable);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stable(value[key])]));
  }
  return value;
};
const text = (value) => `${JSON.stringify(stable(value), null, 2)}\n`;

function walk(path) {
  return readdirSync(resolve(root, path), { withFileTypes: true }).flatMap((entry) => {
    const child = `${path}/${entry.name}`;
    return entry.isDirectory() ? walk(child) : [child];
  });
}

function sourceRoot() {
  const paths = [
    ...walk("implementation/src"),
    ...walk("implementation/test"),
    "foundry.toml",
  ].sort((left, right) => left < right ? -1 : left > right ? 1 : 0);
  return sha256(Buffer.from(paths.map((path) => `${sha256(bytes(path))}  ${path}\n`).join(""), "utf8"));
}

function formalRoot() {
  const paths = walk("formal/isabelle/ERC_TRUST")
    .filter((path) => path.endsWith(".thy"))
    .sort((left, right) => left < right ? -1 : left > right ? 1 : 0);
  return {
    theoryFiles: paths.length,
    rootSha256: sha256(Buffer.from(paths.map((path) => `${sha256(bytes(path))}  ${path}\n`).join(""), "utf8")),
  };
}

function collectRows(value, rows = []) {
  if (Array.isArray(value)) {
    for (const entry of value) collectRows(entry, rows);
  } else if (value !== null && typeof value === "object") {
    if (typeof value.rowId === "string") rows.push(value.rowId);
    for (const entry of Object.values(value)) collectRows(entry, rows);
  }
  return rows;
}

function isAncestor(commit) {
  try {
    execFileSync("git", ["merge-base", "--is-ancestor", commit, "HEAD"], { cwd: root, stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
}

function productionDelta() {
  const paths = [
    "implementation/src/TrustToken.sol",
    "implementation/src/profiles/ERC3643TrustAdapter.sol",
  ];
  const output = execFileSync(
    "git",
    ["diff", "--unified=0", baselineCommit, "--", ...paths],
    { cwd: root, encoding: "utf8" },
  ).replace(/\r\n?/g, "\n");
  check(sha256(Buffer.from(output, "utf8")) === expectedProductionDeltaSha256,
    "production source delta escaped the approved two-guard patch");
  check(output.includes("request.amount <= _frozen[request.subject]"), "Native strict-FREEZE guard missing");
  check(output.includes("request.amount <= _frozenTargets[request.subject]"), "profile strict-FREEZE guard missing");
  return {
    baselineCommit,
    deltaSha256: expectedProductionDeltaSha256,
    changedPaths: paths.map(fileRef),
    addedSemanticGuards: 2,
    removedSemanticLines: 0,
    disposition: "PASS_EXACT_TWO_GUARD_DELTA",
  };
}

const historicalRelease = json("evidence/current-profile-release-index-v1.json");
const historicalPackages = json(historicalRelease.qualificationInputs.packageAggregate.path);
const historicalRows = json(historicalRelease.qualificationInputs.rowIndex.path);
const runtime = json("evidence/end-to-end-refinement/runtime-binding-current-profile-qualification-v3.json");
const pureFixture = json(runtime.nativeResolvedRuntime.resolvedFixturePath);
const foundry = json("evidence/foundry-results-v2.json");
const isabelle = json("evidence/isabelle-results-v2.json");
const mutation = json("evidence/mutation-results.json");
const kontrol = json("evidence/kontrol-results-v2.json");
const deterministic = json("evidence/deterministic-build.json");
const certoraPath = "evidence/certora-financial-core-v2.json";
check(existsSync(resolve(root, certoraPath)), "current Certora terminal receipt missing");
const certora = json(certoraPath);

check(historicalPackages.status === "PASS_C_SERIES_C0_THROUGH_C6_SEVEN_OF_SEVEN"
  && historicalPackages.qualifiedCount === 7 && historicalPackages.requiredCount === 7,
"historical package baseline drift");
check(historicalRows.progress.coreRefinement.qualified === 49
  && historicalRows.progress.coreSupporting.qualified === 24
  && historicalRows.frozenRows.length === 0, "historical row baseline drift");
check(runtime.status === "PASS_RUNTIME_SEMANTIC_IDENTITY" && runtime.subjects.length === 7
  && runtime.verifierMutationValidation.semanticMutations.killed === 42
  && runtime.verifierMutationValidation.expectedHashOverwriteMutations.failedClosed === 7,
"runtime qualification drift");
check(pureFixture.status === "PASS_PURE_RUNTIME_RESOLUTION" && pureFixture.deployments.length === 7
  && pureFixture.deployments.every((entry) => entry.immutablePatch.pureResolutionPass),
"pure runtime fixture drift");
check(runtime.nativeResolvedRuntime.runtimeBytes === 24177
  && runtime.nativeResolvedRuntime.runtimeBytesSha256 === "ea0a3088cde6869a0e476a451e0baebc5a68f0462127f8ea24973189ab26fbe1",
"resolved Native runtime drift");
check(foundry.status === "PASS" && foundry.candidate === candidate
  && foundry.checks.tests.passed === 31 && foundry.checks.tests.failed === 0
  && foundry.checks.tests.invariantCalls === 384000 && foundry.runtimeTemplate.bytes === 24177,
"Foundry qualification drift");
check(isAncestor(foundry.sourceCommit), "Foundry evidence commit is not an ancestor");
const currentFormal = formalRoot();
check(isabelle.status === "PASS" && isabelle.candidate === candidate
  && isabelle.formalSource.theoryFiles === currentFormal.theoryFiles
  && isabelle.formalSource.rootSha256 === currentFormal.rootSha256
  && isabelle.checks.oracleDependencyCount === 0 && isabelle.checks.bannedSourceForms === 0,
"Isabelle qualification drift");
check(isAncestor(isabelle.sourceCommit), "Isabelle evidence commit is not an ancestor");
check(mutation.total === 12 && mutation.killed === 12 && mutation.survived === 0
  && mutation.candidateInput.sourceRootAlgorithm === "sha256-raw-files-case-sensitive-path-order-v1"
  && mutation.candidateInput.sourceRootSha256 === sourceRoot(), "mutation qualification drift");
check(isAncestor(mutation.candidateInput.gitHead), "mutation evidence commit is not an ancestor");
check(kontrol.status === "PASS" && kontrol.candidate === candidate
  && kontrol.summary.total === 4 && kontrol.summary.passed === 4 && kontrol.summary.failed === 0
  && kontrol.runtimeBinding.runtimeBytes === deterministic.buildA.runtimeBytes
  && kontrol.runtimeBinding.runtimeSha256 === deterministic.buildA.runtimeSha256,
"Kontrol qualification drift");
for (const input of kontrol.sourceInputs) {
  check(sha256(bytes(input.path)) === input.sha256, `Kontrol input drift: ${input.path}`);
}
check(kontrol.runtimeBinding.pureResolvedRuntime.runtimeSha256
  === runtime.nativeResolvedRuntime.runtimeBytesSha256, "Kontrol resolved-runtime bridge drift");
check(certora.status === "PASS_TARGETED_FREEZE_DIRECTION" && certora.candidate === candidate
  && certora.rules.total === 2 && certora.rules.success === 2
  && certora.rules.fail === 0 && certora.rules.sanityFail === 0
  && certora.rules.timeout === 0 && certora.rules.unknown === 0,
"Certora qualification drift");
check(isAncestor(certora.sourceCommit), "Certora evidence commit is not an ancestor");
for (const input of certora.inputs) check(sha256(bytes(input.path)) === input.sha256, `Certora input drift: ${input.path}`);
check(deterministic.status === "PASS"
  && JSON.stringify(deterministic.buildA) === JSON.stringify(deterministic.buildB)
  && deterministic.buildA.runtimeBytes === 24177, "deterministic-build drift");
const delta = productionDelta();

const packages = [
  ["C0", "REBOUND_TO_CURRENT_EVIDENCE", ["runtime-v3", "foundry-v2", "isabelle-v2"]],
  ["C1", "CARRY_FORWARD_BY_CHECKED_DELTA", ["isabelle-v2", "certora-targeted-v2", "kontrol-v2", "mutation-v1", "production-delta"]],
  ["C2", "CARRY_FORWARD_BY_CHECKED_DELTA", ["runtime-v3", "production-delta", "foundry-v2"]],
  ["C3", "CARRY_FORWARD_BY_CHECKED_DELTA", ["isabelle-v2", "kontrol-v2", "foundry-v2", "mutation-v1", "production-delta"]],
  ["C4", "CARRY_FORWARD_BY_CHECKED_DELTA", ["isabelle-v2", "certora-targeted-v2", "foundry-v2", "mutation-v1", "production-delta"]],
  ["C5", "CARRY_FORWARD_BY_CHECKED_DELTA", ["isabelle-v2", "production-delta", "foundry-v2"]],
  ["C6", "CARRY_FORWARD_BY_CHECKED_DELTA", ["isabelle-v2", "certora-targeted-v2", "kontrol-v2", "foundry-v2", "production-delta"]],
].map(([id, disposition, evidence]) => ({
  id,
  disposition,
  terminal: true,
  currentCandidateQualified: true,
  evidence,
  packageRootSha256: sha256(Buffer.from(JSON.stringify({ id, disposition, evidence }), "utf8")),
}));
const packageRootSha256 = sha256(Buffer.from(packages.map((entry) => `${entry.id}\0${entry.packageRootSha256}\n`).join(""), "utf8"));
const packageReceipt = {
  schemaVersion: 2,
  kind: "ERC_TRUST_C_SERIES_TERMINAL_QUALIFICATION_V2",
  status: "PASS_C_SERIES_C0_THROUGH_C6_SEVEN_OF_SEVEN",
  candidate,
  historicalBaseline: fileRef("evidence/current-profile-release-index-v1.json"),
  repairedIdentity: {
    productionDelta: delta,
    runtimeQualification: fileRef("evidence/end-to-end-refinement/runtime-binding-current-profile-qualification-v3.json"),
    pureFixture: fileRef(runtime.nativeResolvedRuntime.resolvedFixturePath),
    runtimeTemplateSha256: deterministic.buildA.runtimeSha256,
    resolvedRuntimeSha256: runtime.nativeResolvedRuntime.runtimeBytesSha256,
    runtimeBytes: 24177,
    eip170MarginBytes: 399,
  },
  evidence: {
    foundry: fileRef("evidence/foundry-results-v2.json"),
    isabelle: fileRef("evidence/isabelle-results-v2.json"),
    certora: fileRef(certoraPath),
    kontrol: fileRef("evidence/kontrol-results-v2.json"),
    mutation: fileRef("evidence/mutation-results.json"),
    deterministicBuild: fileRef("evidence/deterministic-build.json"),
  },
  packages,
  packageRootSha256,
  qualifiedCount: 7,
  requiredCount: 7,
  heldCount: 0,
  openCount: 0,
  noPartialCredit: true,
  nonclaims: [
    "Historical receipts remain evidence for their exact historical runtime only.",
    "Checked-delta carry-forward is limited to the exact two-guard production patch and the named current evidence.",
    "The current Certora result proves only the production internal FREEZE shape guard and wrapper rollback; it is not a fresh proof of the complete financial-core packages or external action entrypoint.",
    "No compiler correctness, audit, deployment identity, production readiness, or external legal truth is claimed.",
  ],
};

const coreRows = historicalRows.progress.coreRefinement.rows;
const supportingRows = historicalRows.progress.coreSupporting.rows;
const allRows = [...coreRows, ...supportingRows];
const discoveredRows = collectRows(historicalRows);
check(new Set(allRows).size === 73 && new Set(discoveredRows).size === 73
  && allRows.every((row) => discoveredRows.includes(row)), "historical row inventory drift");
const acuteRows = new Set([
  "ACT-01", "REV-01", "AUTH-04", "FAIL-01", "FAIL-08",
  "REV-02", "REV-03", "REV-04", "REV-07", "REV-08", "REV-09", "REV-11",
  "EXT-02", "EXT-03", "SEP-02", "ART-06", "ART-07",
  "FAIL-05", "SEP-03", "SEP-05", "ART-05",
]);
const reboundRows = new Set([
  "STATE-01", "STATE-02", "STATE-03", "STATE-04", "STATE-05", "STATE-06", "STATE-07",
  "ABI-01", "ABI-02", "ABI-03", "ABI-04", "ABI-05",
  "ART-01", "ART-02", "ART-03", "ART-04", "ART-08",
  "EXT-01", "EXT-07", "SEP-01", "SEP-04",
]);
const rowEntries = allRows.map((rowId) => {
  const disposition = acuteRows.has(rowId) || reboundRows.has(rowId)
    ? "REBOUND_TO_CURRENT_EVIDENCE"
    : "CARRY_FORWARD_BY_CHECKED_DELTA";
  const evidence = acuteRows.has(rowId)
    ? ["packages-v2", "runtime-v3", "isabelle-v2", "foundry-v2", "certora-targeted-v2", "kontrol-v2", "mutation-v1", "production-delta"]
    : reboundRows.has(rowId)
      ? ["packages-v2", "runtime-v3", "pure-fixture-v1", "isabelle-v2", "foundry-v2", "production-delta"]
      : ["packages-v2", "runtime-v3", "isabelle-v2", "foundry-v2", "production-delta"];
  return {
    rowId,
    class: coreRows.includes(rowId) ? "CoreRefinement" : "CoreSupporting",
    disposition,
    currentCandidateQualified: true,
    evidence,
    rowRootSha256: sha256(Buffer.from(JSON.stringify({ rowId, disposition, evidence, packageRootSha256 }), "utf8")),
  };
});
const rowRootSha256 = sha256(Buffer.from(rowEntries.map((entry) => `${entry.rowId}\0${entry.rowRootSha256}\n`).join(""), "utf8"));
const rowReceipt = {
  schemaVersion: 2,
  kind: "ERC_TRUST_CURRENT_PROFILE_ROW_QUALIFICATIONS_V2",
  status: "PASS_CURRENT_PROFILE_ROWS",
  candidate,
  packageRootSha256,
  historicalBaselineSha256: historicalRelease.qualificationInputs.rowIndex.sha256,
  currentEvidence: packageReceipt.evidence,
  progress: {
    coreRefinement: { qualified: 49, required: 49 },
    coreSupporting: { qualified: 24, required: 24 },
    optionalBacklog: { qualified: 0, required: 6, publicationBlocking: false },
    frozenRows: 0,
  },
  dispositionCounts: {
    reproved: 0,
    rebound: rowEntries.filter((entry) => entry.disposition === "REBOUND_TO_CURRENT_EVIDENCE").length,
    checkedDelta: rowEntries.filter((entry) => entry.disposition === "CARRY_FORWARD_BY_CHECKED_DELTA").length,
  },
  rows: rowEntries,
  rowRootSha256,
  noPartialCredit: true,
  nonclaims: packageReceipt.nonclaims,
};

const releaseIndex = {
  schemaVersion: 2,
  kind: "ERC_TRUST_CURRENT_PROFILE_RELEASE_INDEX_V2",
  status: "PASS_CURRENT_PROFILE_RELEASE_CANDIDATE",
  candidate,
  qualificationInputs: {
    packages: { path: packagePath, sha256: sha256(Buffer.from(text(packageReceipt), "utf8")) },
    rows: { path: rowPath, sha256: sha256(Buffer.from(text(rowReceipt), "utf8")) },
    runtime: fileRef("evidence/end-to-end-refinement/runtime-binding-current-profile-qualification-v3.json"),
    pureFixture: fileRef(runtime.nativeResolvedRuntime.resolvedFixturePath),
  },
  progress: {
    reusablePackages: "7/7",
    coreRefinement: "49/49",
    supportingCurrentProfile: "24/24",
    frozenRows: 0,
    optionalBacklog: "0/6",
  },
  runtime: {
    templateSha256: deterministic.buildA.runtimeSha256,
    resolvedSha256: runtime.nativeResolvedRuntime.runtimeBytesSha256,
    nativeBytes: 24177,
    eip170MarginBytes: 399,
    expectedHashesOverwritten: false,
  },
  replay: {
    pureFixture: "node scripts/generate-pure-runtime-fixture.mjs --check",
    runtime: "node scripts/verify-runtime-binding.mjs --check-receipt",
    release: "node scripts/verify-current-profile-release-v2.mjs",
  },
  nonclaims: packageReceipt.nonclaims,
};

const outputs = [[packagePath, packageReceipt], [rowPath, rowReceipt], [releasePath, releaseIndex]];
if (process.argv.includes("--write")) {
  for (const [path, value] of outputs) writeFileSync(resolve(root, path), text(value), "utf8");
} else {
  for (const [path, value] of outputs) {
    check(existsSync(resolve(root, path)), `successor evidence missing: ${path}`);
    check(readFileSync(resolve(root, path), "utf8") === text(value), `successor evidence drift: ${path}`);
  }
}

console.log(JSON.stringify({
  status: releaseIndex.status,
  candidate,
  packages: releaseIndex.progress.reusablePackages,
  coreRefinement: releaseIndex.progress.coreRefinement,
  supportingCurrentProfile: releaseIndex.progress.supportingCurrentProfile,
  optionalBacklog: releaseIndex.progress.optionalBacklog,
  runtimeBytes: releaseIndex.runtime.nativeBytes,
  eip170MarginBytes: releaseIndex.runtime.eip170MarginBytes,
  rows: rowEntries.length,
  packageRootSha256,
  rowRootSha256,
}, null, 2));
