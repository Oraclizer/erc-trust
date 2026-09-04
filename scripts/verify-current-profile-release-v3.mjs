// SPDX-License-Identifier: BSD-3-Clause
//
// Successor evidence index: one lane per evidence class, each either PASS
// (a receipt exists and binds the exact current source, formal, or runtime
// identity) or PENDING (no receipt for the current identity yet; a later change
// owns it). A receipt that exists but binds a different identity is neither: it
// fails, because expected identities are never overwritten to match new output.
//
// Whether PENDING lanes are acceptable is decided by evidence/evidence-mode.json.
// In release mode every lane must be PASS. `--require-release` additionally
// refuses any mode other than release, for the tag validation workflow.
//
// Usage:
//   node scripts/verify-current-profile-release-v3.mjs            check the committed index
//   node scripts/verify-current-profile-release-v3.mjs --write    rewrite the index from the receipts
//   node scripts/verify-current-profile-release-v3.mjs --require-release

import { createHash } from "node:crypto";
import { existsSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { validateMutationDefinitionBinding } from "./lib/mutation-campaign.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const modePath = "evidence/evidence-mode.json";
const indexPath = "evidence/current-profile-release-index-v3.json";
const historicalIndexPath = "evidence/candidate-2/current-profile-release-index-v2.json";
const expectationsPath = "evidence/evidence-expectations-v3.json";
const receiptPaths = {
  runtime: "evidence/deterministic-build.json",
  foundry: "evidence/foundry-results-v3.json",
  mutation: "evidence/mutation-results.json",
  isabelleBuild: "evidence/isabelle-results-v3.json",
  kontrol: "evidence/kontrol-results-v3.json",
  independentReproduction: "evidence/independent-reproduction-v3.json",
  certora: "evidence/certora-results-v3.json",
  runtimeBinding: "evidence/runtime-binding-v3.json",
};
const args = new Set(process.argv.slice(2));
const writeMode = args.has("--write");
const requireRelease = args.has("--require-release");
const selfTest = args.has("--self-test");
const EIP170_LIMIT = 24_576;

const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const bytes = (path) => readFileSync(resolve(root, path));
const canonicalBytes = (path) => Buffer.from(bytes(path).toString("utf8").replace(/\r\n?/g, "\n"), "utf8");
const json = (path) => JSON.parse(bytes(path).toString("utf8"));
const exists = (path) => existsSync(resolve(root, path));
const check = (condition, message) => {
  if (!condition) throw new Error(message);
};
const fileRef = (path) => ({ path, sha256: sha256(canonicalBytes(path)) });
const stable = (value) => {
  if (Array.isArray(value)) return value.map(stable);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stable(value[key])]));
  }
  return value;
};
const text = (value) => `${JSON.stringify(stable(value), null, 2)}\n`;

function walk(path) {
  if (!exists(path)) return [];
  return readdirSync(resolve(root, path), { withFileTypes: true }).flatMap((entry) => {
    const child = `${path}/${entry.name}`;
    return entry.isDirectory() ? walk(child) : [child];
  });
}

function rootOf(paths) {
  const sorted = [...paths].sort((left, right) => (left < right ? -1 : left > right ? 1 : 0));
  return sha256(Buffer.from(sorted.map((path) => `${sha256(bytes(path))}  ${path}\n`).join(""), "utf8"));
}

function sourceRoot() {
  return rootOf([...walk("implementation/src"), ...walk("implementation/test"), "foundry.toml"]);
}

function formalRoot() {
  const paths = walk("formal/isabelle/ERC_TRUST").filter((path) => path.endsWith(".thy"));
  return { theoryFiles: paths.length, rootSha256: rootOf(paths) };
}

function inputsRoot(path) {
  const paths = walk(path);
  return paths.length === 0 ? null : rootOf(paths);
}

// A receipt binds the byte root of the sources or theories it ran on, recomputed here from the
// working tree. The commit a receipt names is provenance, not a gate: the trunk is reached by
// GitHub merges that rewrite commit identities (rebase for own pull requests, squash for
// external ones), so the recorded commit is never an ancestor of main. The recorders check at
// record time that the named commit carries the declared root; this verifier checks that the
// declared root is the root of the tree it runs on.

function declaredMutationIds() {
  return [...bytes("scripts/run-mutations.ps1").toString("utf8").matchAll(/^\s*Id = "([^"]+)"/gm)].map((match) => match[1]);
}

const fullSha = (value) => typeof value === "string" && /^[0-9a-f]{40}$/.test(value);

function exactNonemptySet(actual, expected, label) {
  check(Array.isArray(expected) && expected.length > 0, `${label} expected identifier set is empty`);
  check(Array.isArray(actual) && actual.length > 0, `${label} actual identifier set is empty`);
  check(new Set(expected).size === expected.length, `${label} expected identifier set has duplicates`);
  check(new Set(actual).size === actual.length, `${label} actual identifier set has duplicates`);
  check(JSON.stringify([...actual].sort()) === JSON.stringify([...expected].sort()), `${label} identifier set mismatch`);
}

function requireRunProvenance(run, provider, label) {
  check(run && typeof run === "object", `${label} run provenance missing`);
  check(run.provider === provider, `${label} provider mismatch`);
  check(typeof run.runId === "string" && run.runId.length > 0, `${label} run id missing`);
  check(typeof run.startedAt === "string" && typeof run.finishedAt === "string", `${label} run timestamps missing`);
  check(typeof run.replay === "string" && run.replay.length > 0, `${label} replay command missing`);
}

function requireExactInputRoot(receiptRoot, expectedRoot, inputs, label) {
  check(typeof expectedRoot === "string" && /^[0-9a-f]{64}$/.test(expectedRoot), `${label} expected input root missing`);
  check(Array.isArray(inputs) && inputs.length > 0, `${label} input set is empty`);
  check(receiptRoot === expectedRoot, `${label} input root mismatch`);
}

function requirePositiveTotal(total, label) {
  check(Number.isInteger(total) && total > 0, `${label} total must be positive`);
}

function expectRejected(fn, label) {
  let rejected = false;
  try { fn(); } catch { rejected = true; }
  check(rejected, `self-test did not reject ${label}`);
}

if (selfTest) {
  const goodRun = { provider: "kontrol-kevm", runId: "fixture-run", startedAt: "2026-01-01T00:00:00Z", finishedAt: "2026-01-01T00:01:00Z", replay: "fixture" };
  exactNonemptySet(["proof-a"], ["proof-a"], "fixture proofs");
  requireRunProvenance(goodRun, "kontrol-kevm", "fixture proofs");
  requirePositiveTotal(1, "fixture proofs");
  requireExactInputRoot("a".repeat(64), "a".repeat(64), [{ path: "x", sha256: "b".repeat(64) }], "fixture proofs");
  expectRejected(() => exactNonemptySet([], ["proof-a"], "zero proofs"), "zero proofs");
  expectRejected(() => requirePositiveTotal(0, "zero proofs"), "zero proof total");
  expectRejected(() => requireExactInputRoot("a".repeat(64), "b".repeat(64), [{ path: "x" }], "wrong root"), "wrong input root");
  expectRejected(() => requireExactInputRoot("a".repeat(64), "a".repeat(64), [], "empty inputs"), "empty input set");
  expectRejected(() => exactNonemptySet(["proof-b"], ["proof-a"], "wrong proofs"), "wrong proof id");
  expectRejected(() => requireRunProvenance({}, "kontrol-kevm", "missing provenance"), "missing run provenance");
  expectRejected(() => exactNonemptySet([], [], "zero rules"), "zero expected and actual rules");
  console.log("successor evidence verifier self-test PASS: zero-count, identifier-set, and provenance negatives rejected");
  process.exit(0);
}

// ---------------------------------------------------------------------------
// Mode
// ---------------------------------------------------------------------------

check(exists(modePath), `evidence mode file missing: ${modePath}`);
check(exists(expectationsPath), `evidence expectations missing: ${expectationsPath}`);
const mode = json(modePath);
const expectations = json(expectationsPath);
check(expectations.schema === "erc-trust-evidence-expectations-v3", "evidence expectations schema drift");
check(mode.schema === "erc-trust-evidence-mode-v1", "evidence mode schema drift");
check(["successor-development", "release"].includes(mode.mode), `unsupported evidence mode: ${mode.mode}`);
check(mode.pendingAllowed === (mode.mode !== "release"), "pendingAllowed must follow the mode");
check(typeof mode.candidate === "string" && /^\d+\.\d+\.\d+-candidate\.\d+$/.test(mode.candidate), "candidate label");
if (requireRelease) check(mode.mode === "release", "release mode required");
const candidate = mode.candidate;

// ---------------------------------------------------------------------------
// Identity of the tree under verification
// ---------------------------------------------------------------------------

const identity = {
  sourceRootAlgorithm: "sha256-raw-files-case-sensitive-path-order-v1",
  sourceRootSha256: sourceRoot(),
  formalRoot: formalRoot(),
  kontrolInputsSha256: rootOf(["implementation/src/TrustToken.sol", ...walk("implementation/kontrol")]),
  certoraInputsSha256: inputsRoot("implementation/certora"),
};

// ---------------------------------------------------------------------------
// Lanes
// ---------------------------------------------------------------------------

const lanes = {};
const pending = (lane, owner) => ({ status: "PENDING", receipt: receiptPaths[lane] ?? null, owner });

// runtime: deterministic double build of the native runtime
let runtimeTemplateSha256 = null;
let deterministicReceipt = null;
if (!exists(receiptPaths.runtime)) {
  lanes.runtime = pending("runtime", "this change: deterministic build receipt for the successor source");
} else {
  const deterministic = json(receiptPaths.runtime);
  check(deterministic.schema === "erc-trust-deterministic-build-v3", "deterministic build receipt schema");
  for (const key of ["native", "erc3643Adapter", "profileGovernor"]) {
    check(deterministic.buildA.subjects?.[key]?.runtimeSha256 && deterministic.buildA.subjects[key].runtimeBytes <= EIP170_LIMIT, `deterministic build receipt lacks subject ${key}`);
  }
  check(deterministic.status === "PASS", "deterministic build status");
  check(JSON.stringify(deterministic.buildA) === JSON.stringify(deterministic.buildB), "deterministic build pair mismatch");
  check(deterministic.buildA.runtimeBytes <= EIP170_LIMIT, "runtime exceeds the EIP-170 limit");
  check(String(deterministic.toolchain.solidity).startsWith("0.8.36"), "deterministic build compiler pin");
  check(deterministic.candidateInput.sourceRootAlgorithm === identity.sourceRootAlgorithm, "deterministic build source root algorithm");
  check(deterministic.candidateInput.sourceRootSha256 === identity.sourceRootSha256, "deterministic build receipt binds a different source root");
  check(fullSha(deterministic.candidateInput.gitHead), "deterministic build receipt names no commit");
  const manifest = json("evidence/release-manifest.json");
  check(manifest.trustToken.runtimeSha256 === deterministic.buildA.runtimeSha256
    && manifest.trustToken.runtimeBytes === deterministic.buildA.runtimeBytes
    && manifest.trustToken.creationSha256 === deterministic.buildA.creationSha256,
    "deterministic build receipt binds a different runtime than the release manifest");
  for (const key of ["erc3643Adapter", "profileGovernor"]) {
    check(manifest.profileRuntimes?.[key]?.runtimeSha256 === deterministic.buildA.subjects?.[key]?.runtimeSha256
      && manifest.profileRuntimes?.[key]?.creationSha256 === deterministic.buildA.subjects?.[key]?.creationSha256,
      `deterministic build receipt binds a different ${key} runtime than the release manifest`);
  }
  runtimeTemplateSha256 = deterministic.buildA.runtimeSha256;
  deterministicReceipt = deterministic;
  lanes.runtime = {
    status: "PASS",
    receipt: fileRef(receiptPaths.runtime),
    runtimeTemplateSha256,
    runtimeBytes: deterministic.buildA.runtimeBytes,
    eip170MarginBytes: EIP170_LIMIT - deterministic.buildA.runtimeBytes,
  };
}

// foundry: pinned build, size, format, tests, and lint on the exact source root
if (!exists(receiptPaths.foundry)) {
  lanes.foundry = pending("foundry", "this change: continuous-integration Foundry receipt for the successor source");
} else {
  const foundry = json(receiptPaths.foundry);
  check(foundry.schema === "erc-trust-foundry-results-v3" && foundry.candidate === candidate, "Foundry receipt identity");
  check(foundry.status === "PASS" && foundry.checks.tests.failed === 0 && foundry.checks.lintErrors === 0, "Foundry receipt status");
  check(foundry.sourceRootSha256 === identity.sourceRootSha256, "Foundry receipt binds a different source root");
  check(runtimeTemplateSha256 !== null, "Foundry receipt without a deterministic build receipt");
  check(foundry.runtimeTemplate.sha256 === runtimeTemplateSha256, "Foundry receipt binds a different runtime");
  check(fullSha(foundry.sourceCommit), "Foundry receipt names no commit");
  lanes.foundry = { status: "PASS", receipt: fileRef(receiptPaths.foundry), tests: foundry.checks.tests.passed };
}

// mutation: consumer-removal campaign on the exact source root
if (!exists(receiptPaths.mutation)) {
  lanes.mutation = pending("mutation", "this change: mutation campaign on the successor source");
} else {
  const mutation = json(receiptPaths.mutation);
  check(mutation.schema === "erc-trust-mutation-result-v2", "mutation receipt schema");
  check(mutation.candidateInput.sourceRootAlgorithm === identity.sourceRootAlgorithm, "mutation source root algorithm");
  check(mutation.candidateInput.sourceRootSha256 === identity.sourceRootSha256, "mutation receipt binds a different source root");
  check(mutation.total === mutation.results.length && mutation.killed === mutation.total && mutation.survived === 0,
    "mutation counts");
  validateMutationDefinitionBinding(
    mutation,
    resolve(root, "scripts/run-mutations.ps1"),
    resolve(root, "scripts/mutation-campaign-v1.json"),
    check,
  );
  const declared = declaredMutationIds();
  check(declared.length > 0 && JSON.stringify(mutation.results.map((result) => result.id)) === JSON.stringify(declared),
    "mutation receipt does not list exactly the declared campaign in scripts/run-mutations.ps1");
  check(fullSha(mutation.candidateInput.gitHead) && mutation.candidateInput.sourceRootSha256 === identity.sourceRootSha256,
    "mutation commit does not produce the declared source root");
  for (const result of mutation.results) {
    check(result.result === "KILLED" && result.anchorOccurrences >= 1 && result.detectorDiscovered === 1
      && result.detectorExecuted === 1 && result.mutantCompiled === true, `invalid mutation receipt: ${result.id}`);
  }
  lanes.mutation = {
    status: "PASS",
    receipt: fileRef(receiptPaths.mutation),
    total: mutation.total,
    killed: mutation.killed,
    ids: mutation.results.map((result) => result.id),
    campaignDefinitionSha256: mutation.campaignDefinitionSha256,
  };
}

// isabelleBuild: clean build and audit of the exact formal source tree
if (!exists(receiptPaths.isabelleBuild)) {
  lanes.isabelleBuild = pending("isabelleBuild", "this change: continuous-integration Isabelle receipt for the current formal root");
} else {
  const isabelle = json(receiptPaths.isabelleBuild);
  check(isabelle.schema === "erc-trust-isabelle-results-v3" && isabelle.candidate === candidate, "Isabelle receipt identity");
  check(isabelle.status === "PASS" && isabelle.checks.bannedSourceForms === 0 && isabelle.checks.oracleDependencyCount === 0,
    "Isabelle receipt status");
  check(isabelle.formalSource.theoryFiles === identity.formalRoot.theoryFiles
    && isabelle.formalSource.rootSha256 === identity.formalRoot.rootSha256, "Isabelle receipt binds a different formal root");
  check(fullSha(isabelle.sourceCommit), "Isabelle receipt names no commit");
  lanes.isabelleBuild = { status: "PASS", receipt: fileRef(receiptPaths.isabelleBuild) };
}

// isabelleRuntimeBinding: the generated bridge theories name the current runtime template
{
  const theories = walk("formal/isabelle/ERC_TRUST").filter((path) => path.endsWith(".thy"));
  const bound = runtimeTemplateSha256 === null
    ? []
    : theories.filter((path) => bytes(path).toString("utf8").includes(runtimeTemplateSha256));
  lanes.isabelleRuntimeBinding = bound.length > 0
    ? { status: "PASS", boundTheories: bound, runtimeTemplateSha256 }
    : pending("isabelleRuntimeBinding", "formal refinement change: regenerate the runtime bridge theories for the successor runtime");
}

// obligationLedger: the central obligation ledger of the successor endpoints is verified
// and its summary is bound to the current bridge schema, the rendered theory, and the
// runtime template of the deterministic build
{
  const summaryPath = "evidence/end-to-end-refinement/obligation-ledger-summary-v3.json";
  const bridgeSchemaPath = "evidence/end-to-end-refinement/runtime-bridge-v2/schema.json";
  const bridgeManifestPath = "evidence/end-to-end-refinement/runtime-bridge-v2/generated-manifest.json";
  if (!exists(summaryPath) || !exists(bridgeManifestPath)) {
    lanes.obligationLedger = pending("obligationLedger", "formal refinement change: obligation ledger summary and runtime bridge manifest");
  } else {
    const summary = json(summaryPath);
    const manifest = json(bridgeManifestPath);
    check(summary.schema === "erc-trust-obligation-ledger-summary-v3" && summary.candidate === candidate, "obligation ledger summary identity");
    check(summary.counts.currentMandatory === 0, "obligation ledger has current mandatory rows");
    check(summary.ledger.path === "evidence/end-to-end-refinement/obligation-ledger-v3.json", "obligation ledger summary names a different ledger path");
    check(summary.generatedTheory.path === "formal/isabelle/ERC_TRUST/TRUST_Obligation_Ledger_Generated.thy", "obligation ledger summary names a different theory path");
    check(summary.closureRecord?.path === "evidence/end-to-end-refinement/central-closure-v3.json", "obligation ledger summary names a different closure record path");
    check(summary.bridgeSchema.sha256 === sha256(canonicalBytes(bridgeSchemaPath)), "obligation ledger summary binds a different bridge schema");
    check(summary.ledger.sha256 === sha256(canonicalBytes(summary.ledger.path)), "obligation ledger summary binds a different ledger");
    check(summary.generatedTheory.sha256 === sha256(canonicalBytes(summary.generatedTheory.path)), "rendered obligation ledger theory drift");
    check(summary.closureRecord.sha256 === sha256(canonicalBytes(summary.closureRecord.path)), "central closure record drift");
    check(manifest.schema.sha256 === sha256(canonicalBytes(bridgeSchemaPath)), "bridge manifest binds a different bridge schema");
    for (const generated of manifest.generated) check(sha256(canonicalBytes(generated.path)) === generated.sha256, `generated bridge drift: ${generated.path}`);
    const bound = runtimeTemplateSha256 !== null
      && manifest.runtimes.native === runtimeTemplateSha256
      && summary.runtimeTemplateSha256 === runtimeTemplateSha256;
    const detail = { closure: summary.closure, claim: summary.claim, rows: summary.counts };
    lanes.obligationLedger = bound
      ? { status: "PASS", summary: fileRef(summaryPath), ...detail }
      : { ...pending("obligationLedger", "runtime assurance change: deterministic build receipt binding the bridge runtime"), ...detail };
  }
}

// kontrol and its inputs
if (!exists(receiptPaths.kontrol)) {
  lanes.kontrol = pending("kontrol", "formal refinement change: symbolic cross-checks on the successor runtime");
  lanes.kontrolInputs = { ...pending("kontrolInputs", "bound together with the Kontrol receipt"), inputsRootSha256: identity.kontrolInputsSha256 };
} else {
  const kontrol = json(receiptPaths.kontrol);
  check(kontrol.schema === "erc-trust-kontrol-results-v3" && kontrol.candidate === candidate, "Kontrol receipt identity");
  check(kontrol.status === "PASS" && kontrol.summary.failed === 0 && kontrol.summary.passed === kontrol.summary.total,
    "Kontrol receipt status");
  requirePositiveTotal(kontrol.summary.total, "Kontrol proofs");
  exactNonemptySet(kontrol.proofs.map((proof) => proof.id), expectations.kontrol.expectedProofIds, "Kontrol proofs");
  requireRunProvenance(kontrol.run, expectations.kontrol.provider, "Kontrol");
  requireExactInputRoot(kontrol.inputsRootSha256, identity.kontrolInputsSha256, kontrol.sourceInputs, "Kontrol");
  check(runtimeTemplateSha256 !== null && kontrol.runtimeBinding.runtimeSha256 === runtimeTemplateSha256,
    "Kontrol receipt binds a different runtime");
  for (const input of kontrol.sourceInputs) check(sha256(bytes(input.path)) === input.sha256, `Kontrol input drift: ${input.path}`);
  check(expectations.kontrol.expectedInputsRootSha256 === identity.kontrolInputsSha256, "Kontrol expected input root drift");
  lanes.kontrol = { status: "PASS", receipt: fileRef(receiptPaths.kontrol), proofs: kontrol.summary.passed };
  lanes.kontrolInputs = { status: "PASS", inputsRootSha256: identity.kontrolInputsSha256 };
}

// certora and its inputs
if (!exists(receiptPaths.certora)) {
  lanes.certora = pending("certora", "formal refinement change: parametric rules on the successor bytecode");
  lanes.certoraInputs = { ...pending("certoraInputs", "bound together with the Certora receipt"), inputsRootSha256: identity.certoraInputsSha256 };
} else {
  const certora = json(receiptPaths.certora);
  check(certora.schema === "erc-trust-certora-results-v3" && certora.candidate === candidate, "Certora receipt identity");
  check(certora.status === "PASS" && certora.rules.fail === 0 && certora.rules.sanityFail === 0
    && certora.rules.timeout === 0 && certora.rules.unknown === 0 && certora.rules.success === certora.rules.total,
    "Certora receipt status");
  requirePositiveTotal(certora.rules.total, "Certora rules");
  exactNonemptySet(certora.rules.names, expectations.certora.expectedRuleIds, "Certora rules");
  requireRunProvenance(certora.run, expectations.certora.provider, "Certora");
  requireExactInputRoot(certora.inputsRootSha256, identity.certoraInputsSha256, certora.inputs, "Certora");
  for (const input of certora.inputs) check(sha256(bytes(input.path)) === input.sha256, `Certora input drift: ${input.path}`);
  check(expectations.certora.expectedInputsRootSha256 === identity.certoraInputsSha256, "Certora expected input root drift");
  check(runtimeTemplateSha256 !== null && certora.runtimeTemplateSha256 === runtimeTemplateSha256,
    "Certora receipt binds a different runtime");
  lanes.certora = { status: "PASS", receipt: fileRef(receiptPaths.certora), rules: certora.rules.success };
  lanes.certoraInputs = { status: "PASS", inputsRootSha256: identity.certoraInputsSha256 };
}

// independentReproduction: a specification-only implementation reproduces the conformance vectors
{
  const receiptPath = receiptPaths.independentReproduction;
  if (!exists(receiptPath)) {
    lanes.independentReproduction = pending("independentReproduction", "runtime assurance change: specification-only reproduction of the conformance vectors");
  } else {
    const reproduction = json(receiptPath);
    check(reproduction.schema === "erc-trust-independent-reproduction-v3" && reproduction.kernelVersion === 2, "independent reproduction receipt identity");
    check(reproduction.verdict === "PASS" && reproduction.counts?.totals?.failed === 0 && (reproduction.failures ?? []).length === 0, "independent reproduction verdict");
    check(Array.isArray(reproduction.historicalFindingsResolved) && reproduction.historicalFindingsResolved.length > 0,
      "independent reproduction does not separate resolved historical findings");
    check(Array.isArray(reproduction.findings) && Array.isArray(reproduction.method?.ambiguities?.current),
      "independent reproduction current findings or ambiguities missing");
    const vectorsSha256 = `0x${sha256(bytes("vectors/conformance-v2.json"))}`;
    check(reproduction.inputs?.vectorsSha256 === vectorsSha256, "independent reproduction receipt binds different vectors");
    lanes.independentReproduction = {
      status: "PASS",
      receipt: fileRef(receiptPath),
      assertions: reproduction.counts.totals.assertions,
      findings: (reproduction.findings ?? []).length,
      historicalFindingsResolved: reproduction.historicalFindingsResolved.length,
      notEvaluable: (reproduction.notEvaluable ?? []).length,
      basis: "the receipt is the output of scripts/independent-reproduction-v3.mjs; the sdk-and-package job reruns the program against the committed vectors and requires the committed receipt to match byte for byte",
    };
  }
}

// runtimeBinding: pinned-compiler replay and semantic projections of the deployed subjects
if (!exists(receiptPaths.runtimeBinding)) {
  lanes.runtimeBinding = pending("runtimeBinding", "runtime assurance change: two-layer runtime binding for the successor subjects");
} else {
  const binding = json(receiptPaths.runtimeBinding);
  check(binding.schema === "erc-trust-runtime-binding-v3" && binding.candidate === candidate, "runtime binding identity");
  check(binding.status === "PASS_RUNTIME_SEMANTIC_IDENTITY", "runtime binding status");
  check(runtimeTemplateSha256 !== null && binding.runtimeTemplateSha256 === runtimeTemplateSha256,
    "runtime binding receipt binds a different runtime");
  check(binding.sourceRootSha256 === identity.sourceRootSha256, "runtime binding receipt binds a different source root");
  const bindingSubjects = Object.fromEntries((binding.subjects ?? []).map((subject) => [subject.id, subject]));
  for (const [id, key] of [["native", "native"], ["profileAdapter", "erc3643Adapter"], ["profileGovernor", "profileGovernor"]]) {
    check(bindingSubjects[id]?.runtimeTemplate?.sha256 === deterministicReceipt?.buildA.subjects?.[key]?.runtimeSha256, `runtime binding subject ${id} differs from the deterministic build`);
    for (const name of ["abi", "storageLayout", "creationBytecode", "runtimeTemplate", "methodIdentifiers", "immutableReferences"]) {
      check(bindingSubjects[id]?.semanticChecks?.[name] === true, `runtime binding semantic check ${name} not passed for ${id}`);
    }
  }
  lanes.runtimeBinding = {
    status: "PASS",
    receipt: fileRef(receiptPaths.runtimeBinding),
    subjects: Object.keys(bindingSubjects),
    basis: "this index checks the receipt against the deterministic build; layer 2 (pinned-compiler replay and the six semantic projections) is re-executed by scripts/generate-runtime-binding-v3.mjs --check and scripts/verify-runtime-binding-v3.mjs --replay in the sdk-and-package job",
  };
}

// ---------------------------------------------------------------------------
// Aggregate
// ---------------------------------------------------------------------------

const requiredLanes = ["runtime", "foundry", "mutation", "isabelleBuild", "isabelleRuntimeBinding", "obligationLedger", "kontrol", "kontrolInputs", "certora", "certoraInputs", "independentReproduction", "runtimeBinding"];
for (const name of requiredLanes) check(lanes[name] !== undefined, `lane ${name} was not evaluated`);
check(Object.keys(lanes).every((name) => requiredLanes.includes(name)), "an unlisted lane was evaluated");
const pendingLanes = Object.entries(lanes).filter(([, lane]) => lane.status === "PENDING").map(([name]) => name);
if (mode.mode === "release") check(pendingLanes.length === 0, `release mode with pending lanes: ${pendingLanes.join(", ")}`);
check(exists(historicalIndexPath), "historical candidate 2 index missing");

const index = {
  schemaVersion: 3,
  kind: "ERC_TRUST_CURRENT_PROFILE_RELEASE_INDEX_V3",
  status: mode.mode === "release" ? "PASS_CURRENT_PROFILE_RELEASE_CANDIDATE" : "CONSISTENT_SUCCESSOR_DEVELOPMENT",
  candidate,
  mode: mode.mode,
  identity,
  lanes,
  pendingLanes,
  historicalBaseline: fileRef(historicalIndexPath),
  replay: { release: "node scripts/verify-current-profile-release-v3.mjs" },
  nonclaims: [
    "A PASS lane is a receipt bound to the exact current identity of its inputs; it is not an audit, a compiler-correctness result, or a deployment claim.",
    "A PENDING lane has no receipt for the current identity; the owning change must produce one. Historical candidate 2 receipts under evidence/candidate-2 never satisfy a lane.",
    "Only release mode with zero pending lanes describes a release candidate; successor-development mode describes a successor tree under active evidence closure, including when that tree is on private main.",
    "No compiler correctness, audit, deployment identity, production readiness, or external legal truth is claimed.",
  ],
};

const rendered = text(index);
if (writeMode) {
  writeFileSync(resolve(root, indexPath), rendered, "utf8");
} else {
  check(exists(indexPath), `successor index missing: ${indexPath}`);
  check(readFileSync(resolve(root, indexPath), "utf8").replace(/\r\n?/g, "\n") === rendered,
    `successor index drift: ${indexPath} (rerun with --write after adding or changing a receipt)`);
}

console.log(JSON.stringify({
  status: index.status,
  candidate,
  mode: mode.mode,
  lanes: Object.fromEntries(Object.entries(lanes).map(([name, lane]) => [name, lane.status])),
  pendingLanes,
  runtimeBytes: lanes.runtime.runtimeBytes ?? null,
  eip170MarginBytes: lanes.runtime.eip170MarginBytes ?? null,
  sourceRootSha256: identity.sourceRootSha256,
  formalRootSha256: identity.formalRoot.rootSha256,
}, null, 2));
