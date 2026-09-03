// SPDX-License-Identifier: BSD-3-Clause
//
// Machine check of the central obligation ledger of the kernel version 2
// endpoints (evidence/end-to-end-refinement/obligation-ledger-v3.json).
//
// Every ledger row names one load-bearing abstract condition and the four
// pieces of evidence that connect it to the final code: the exact source
// consumer, the positive activation test, the consumer-removal negative, and
// the compiled or downstream consumer. This script verifies that every anchor
// the ledger cites exists in the current tree (theorem and definition names in
// the Isabelle theories, source snippets with their exact occurrence counts,
// test functions, declared mutations, Kontrol proofs, bridge schema fields,
// conformance vectors, and kernel machine-source pointers) and that every
// receipt-dependent item is backed by a receipt of the current identity when
// that receipt exists. It then renders three artifacts from the ledger:
//   formal/isabelle/ERC_TRUST/TRUST_Obligation_Ledger_Generated.thy
//     (the row inventory as Isabelle facts; the build fails if an abstract
//     anchor disappears or if the bridge schema changes without regenerating)
//   evidence/end-to-end-refinement/obligation-ledger-summary-v3.json
//   evidence/end-to-end-refinement/central-closure-v3.json
//
// Usage:
//   node scripts/verify-obligation-ledger-v3.mjs            verify; fail on drift of the rendered artifacts
//   node scripts/verify-obligation-ledger-v3.mjs --write    verify and rewrite the rendered artifacts
//
// A row whose status is CURRENT-MANDATORY fails the check: the ledger is only
// acceptable when no unresolved row is required for the current claim. A row
// whose status is SUCCESSOR-MANDATORY is required for the next rung of the
// claim ladder only; while one exists the closure status must stay CONDITIONAL.

import { createHash } from "node:crypto";
import { existsSync, readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const writeMode = process.argv.includes("--write");
const paths = {
  ledger: "evidence/end-to-end-refinement/obligation-ledger-v3.json",
  bridgeSchema: "evidence/end-to-end-refinement/runtime-bridge-v2/schema.json",
  bridgeManifest: "evidence/end-to-end-refinement/runtime-bridge-v2/generated-manifest.json",
  kernelSchema: "spec/erc-trust-kernel-v2.json",
  mutations: "scripts/run-mutations.ps1",
  vectors: "vectors/conformance-v2.json",
  theoryDir: "formal/isabelle/ERC_TRUST",
  testDir: "implementation/test",
  kontrolDir: "implementation/kontrol",
  theory: "formal/isabelle/ERC_TRUST/TRUST_Obligation_Ledger_Generated.thy",
  summary: "evidence/end-to-end-refinement/obligation-ledger-summary-v3.json",
  closure: "evidence/end-to-end-refinement/central-closure-v3.json",
  receipts: {
    mutation: "evidence/mutation-results.json",
    kontrol: "evidence/kontrol-results-v3.json",
    foundry: "evidence/foundry-results-v3.json",
    deterministic: "evidence/deterministic-build.json",
  },
};
const statuses = new Set(["CLOSED", "CURRENT-MANDATORY", "SUCCESSOR-MANDATORY", "SEPARATE-PROFILE", "NOT-APPLICABLE"]);
const endpoints = new Set(["native", "profileAdapter", "profileGovernor", "shared"]);

const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const abs = (path) => resolve(root, path);
const exists = (path) => existsSync(abs(path));
const readText = (path) => readFileSync(abs(path), "utf8").replace(/\r\n?/g, "\n");
const readJson = (path) => JSON.parse(readFileSync(abs(path), "utf8"));
const stable = (value) => {
  if (Array.isArray(value)) return value.map(stable);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stable(value[key])]));
  }
  return value;
};
const text = (value) => `${JSON.stringify(stable(value), null, 2)}\n`;
const failures = [];
const fail = (message) => failures.push(message);

function walk(path) {
  if (!exists(path)) return [];
  return readdirSync(abs(path), { withFileTypes: true }).flatMap((entry) => {
    const child = `${path}/${entry.name}`;
    return entry.isDirectory() ? walk(child) : [child];
  });
}

// ---------------------------------------------------------------------------
// Inputs
// ---------------------------------------------------------------------------

const canonical = (path) => Buffer.from(readText(path), "utf8");
const ledgerBytes = canonical(paths.ledger);
const ledger = JSON.parse(ledgerBytes.toString("utf8"));
const ledgerSha256 = sha256(ledgerBytes);
if (ledger.schema !== "erc-trust-obligation-ledger-v3") fail("ledger schema drift");
const bridgeBytes = canonical(paths.bridgeSchema);
const bridge = JSON.parse(bridgeBytes.toString("utf8"));
const bridgeSchemaSha256 = sha256(bridgeBytes);
const bridgeManifest = readJson(paths.bridgeManifest);
if (bridgeManifest.schema.sha256 !== bridgeSchemaSha256) fail("bridge manifest does not bind the current bridge schema");
const kernel = readJson(paths.kernelSchema);
const vectors = readJson(paths.vectors);

const theories = new Map(
  walk(paths.theoryDir).filter((path) => path.endsWith(".thy")).map((path) => {
    const name = path.slice(path.lastIndexOf("/") + 1, -4);
    return [name, readText(path)];
  }),
);
const theoryFacts = new Map();
for (const [name, source] of theories) {
  const facts = new Set();
  for (const match of source.matchAll(/^(?:theorem|lemma|corollary)\s+([A-Za-z0-9_']+)\s*:/gm)) facts.add(match[1]);
  for (const match of source.matchAll(/^(?:definition|abbreviation)\s+([A-Za-z0-9_']+)\s*::/gm)) facts.add(`${match[1]}_def`);
  for (const match of source.matchAll(/^fun\s+([A-Za-z0-9_']+)\s*::/gm)) facts.add(`${match[1]}.simps`);
  for (const match of source.matchAll(/^locale\s+([A-Za-z0-9_']+)/gm)) facts.add(`locale:${match[1]}`);
  theoryFacts.set(name, facts);
}

const testSources = new Map(
  [...walk(paths.testDir), ...walk(paths.kontrolDir)].filter((path) => path.endsWith(".sol")).map((path) => [path, readText(path)]),
);
const contractFiles = new Map();
for (const [path, source] of testSources) {
  for (const match of source.matchAll(/^(?:abstract\s+)?contract\s+([A-Za-z0-9_]+)/gm)) {
    if (contractFiles.has(match[1])) fail(`test contract defined twice: ${match[1]}`);
    contractFiles.set(match[1], path);
  }
}
function testExists(contract, test) {
  const path = contractFiles.get(contract);
  if (!path) return false;
  return new RegExp(`function\\s+${test.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\s*\\(`).test(testSources.get(path));
}

const mutationSource = readText(paths.mutations);
const declaredMutations = new Map();
for (const match of mutationSource.matchAll(/Id = "([^"]+)"[\s\S]*?File = "([^"]+)"[\s\S]*?Contract = "([^"]+)"\s*\n\s*Test = "([^"]+)"/g)) {
  declaredMutations.set(match[1], { file: match[2].replace(/\\/g, "/"), contract: match[3], test: match[4] });
}
if (declaredMutations.size === 0) fail("no mutations declared in scripts/run-mutations.ps1");

const receipts = {};
for (const [lane, path] of Object.entries(paths.receipts)) {
  receipts[lane] = exists(path) ? { path, sha256: sha256(canonical(path)), data: readJson(path) } : null;
}
// A mutation receipt is current only when it lists exactly the declared campaign and binds
// the current source root (implementation sources, tests, and foundry.toml, raw bytes).
const sourceRootSha256 = (() => {
  const paths = [...walk("implementation/src"), ...walk("implementation/test"), "foundry.toml"].sort((left, right) => (left < right ? -1 : left > right ? 1 : 0));
  return sha256(Buffer.from(paths.map((path) => `${sha256(readFileSync(abs(path)))}  ${path}\n`).join(""), "utf8"));
})();
const mutationReceiptCurrent = receipts.mutation !== null
  && JSON.stringify(receipts.mutation.data.results.map((result) => result.id)) === JSON.stringify([...declaredMutations.keys()])
  && receipts.mutation.data.candidateInput?.sourceRootSha256 === sourceRootSha256;
const runtimeSha256 = receipts.deterministic?.data?.buildA?.runtimeSha256 ?? null;
const bridgeBindsRuntime = runtimeSha256 !== null && bridge.subjects.native.runtime.sha256 === runtimeSha256;
const kontrolReceiptCurrent = receipts.kontrol !== null && runtimeSha256 !== null
  && receipts.kontrol.data.runtimeBinding?.runtimeSha256 === runtimeSha256;
const foundryReceiptCurrent = receipts.foundry !== null && runtimeSha256 !== null
  && receipts.foundry.data.runtimeTemplate?.sha256 === runtimeSha256;

// ---------------------------------------------------------------------------
// Pointer resolution
// ---------------------------------------------------------------------------

function resolvePointer(object, pointer) {
  let current = object;
  for (const segment of pointer.match(/[^.[\]]+|\[[^\]]+\]/g) ?? []) {
    if (segment.startsWith("[")) {
      const key = segment.slice(1, -1);
      if (!Array.isArray(current)) return undefined;
      current = current.find((entry) => entry?.id === key || entry?.name === key);
    } else if (Array.isArray(current) && /^\d+$/.test(segment)) {
      current = current[Number(segment)];
    } else {
      current = current?.[segment];
    }
    if (current === undefined) return undefined;
  }
  return current;
}

function factExists(theory, fact) {
  const facts = theoryFacts.get(theory);
  if (!facts) return false;
  if (fact.includes(".")) {
    const [locale, name] = fact.split(".");
    if (facts.has(`locale:${locale}`)) return facts.has(name);
    return facts.has(fact);
  }
  return facts.has(fact);
}

// ---------------------------------------------------------------------------
// Row verification
// ---------------------------------------------------------------------------

const rowReports = [];
const seenIds = new Set();
const citedMutations = new Set();
for (const row of ledger.rows) {
  const report = { id: row.id, endpoint: row.endpoint, declaredStatus: row.status, awaiting: [], issues: [] };
  const issue = (message) => { report.issues.push(message); fail(`${row.id}: ${message}`); };
  if (!/^[A-Z]+-[A-Z0-9]+-\d{2}$/.test(row.id)) issue(`row id shape ${row.id}`);
  if (seenIds.has(row.id)) issue("duplicate row id");
  seenIds.add(row.id);
  if (!endpoints.has(row.endpoint)) issue(`unknown endpoint ${row.endpoint}`);
  if (!statuses.has(row.status)) issue(`unknown status ${row.status}`);
  if (row.status !== "CLOSED" && !row.statusReason) issue("non-closed row without a status reason");

  // abstract condition
  const abstract = row.abstractCondition;
  if (!abstract || abstract === "none") {
    if (row.status === "CLOSED") issue("closed row without an abstract condition");
  } else {
    if (!theories.has(abstract.theory)) issue(`unknown theory ${abstract.theory}`);
    if (!Array.isArray(abstract.facts) || abstract.facts.length === 0) issue("abstract condition without facts");
    for (const fact of abstract.facts ?? []) {
      if (!factExists(abstract.theory, fact)) issue(`fact not found in ${abstract.theory}: ${fact}`);
    }
  }

  // normative receiver
  if (!Array.isArray(row.normativeReceiver) || row.normativeReceiver.length === 0) issue("no normative receiver");
  for (const pointer of row.normativeReceiver ?? []) {
    if (pointer.startsWith("spec/")) {
      if (!exists(pointer.split("#")[0])) issue(`normative document missing: ${pointer}`);
    } else if (resolvePointer(kernel, pointer) === undefined) {
      issue(`normative pointer does not resolve in the kernel schema: ${pointer}`);
    }
  }

  // final source consumers
  if (!Array.isArray(row.finalSourceConsumers) || row.finalSourceConsumers.length === 0) issue("no source consumer");
  for (const consumer of row.finalSourceConsumers ?? []) {
    if (consumer.kind === "compiler-generated") {
      if (!consumer.note) issue("compiler-generated consumer without a note");
      continue;
    }
    if (!exists(consumer.path)) { issue(`consumer file missing: ${consumer.path}`); continue; }
    const source = readText(consumer.path);
    const snippet = consumer.snippet.replace(/\r\n?/g, "\n");
    const occurrences = source.split(snippet).length - 1;
    const expected = consumer.occurrences ?? 1;
    if (occurrences !== expected) issue(`consumer snippet occurs ${occurrences} times (expected ${expected}) in ${consumer.path}: ${snippet.slice(0, 60)}`);
  }

  // positive activation
  if (!Array.isArray(row.positiveActivation) || row.positiveActivation.length === 0) issue("no positive activation");
  for (const positive of row.positiveActivation ?? []) {
    if (!testExists(positive.contract, positive.test)) issue(`positive test not found: ${positive.contract}.${positive.test}`);
  }

  // consumer-removal negative
  if (!Array.isArray(row.consumerRemovalNegative) || row.consumerRemovalNegative.length === 0) issue("no negative");
  let hasRealNegative = false;
  for (const negative of row.consumerRemovalNegative ?? []) {
    if (negative.mutation) {
      hasRealNegative = true;
      citedMutations.add(negative.mutation);
      const declared = declaredMutations.get(negative.mutation);
      if (!declared) { issue(`mutation not declared: ${negative.mutation}`); continue; }
      if (!testExists(declared.contract, declared.test)) issue(`mutation detector missing: ${negative.mutation}`);
      if (!(row.finalSourceConsumers ?? []).some((consumer) => consumer.path === declared.file)) {
        issue(`mutation ${negative.mutation} mutates ${declared.file}, which is not a consumer file of this row`);
      }
      if (mutationReceiptCurrent) {
        const result = receipts.mutation.data.results.find((entry) => entry.id === negative.mutation);
        if (!result || result.result !== "KILLED") issue(`mutation not killed in the current receipt: ${negative.mutation}`);
      } else {
        report.awaiting.push(`mutation receipt for ${negative.mutation}`);
      }
    } else if (negative.kind === "behavioral-negative") {
      hasRealNegative = true;
      if (!testExists(negative.contract, negative.test)) issue(`behavioral negative test not found: ${negative.contract}.${negative.test}`);
      if (!negative.note) issue("behavioral negative without a note");
    } else if (negative.kind === "redundant-guard") {
      if (!Array.isArray(negative.coveredBy) || negative.coveredBy.length === 0 || !negative.note) issue("redundant guard without coverage or note");
      for (const covering of negative.coveredBy) if (!ledger.rows.some((other) => other.id === covering)) issue(`redundant guard covered by unknown row ${covering}`);
    } else if (negative.kind === "not-applicable") {
      if (!negative.note) issue("not-applicable negative without a note");
    } else {
      issue(`unknown negative shape ${JSON.stringify(negative)}`);
    }
  }
  if (row.status === "CLOSED" && !hasRealNegative) issue("closed row without a mutation or behavioral negative");

  // compiled or downstream consumer
  if (!Array.isArray(row.compiledConsumer) || row.compiledConsumer.length === 0) issue("no compiled consumer");
  for (const compiled of row.compiledConsumer ?? []) {
    if (compiled.kind === "kontrol-proof") {
      if (!testExists("TrustTokenKontrolTest", compiled.proof)) issue(`Kontrol proof input missing: ${compiled.proof}`);
      if (kontrolReceiptCurrent) {
        const proof = receipts.kontrol.data.proofs.find((entry) => entry.id.includes(`${compiled.proof}(`));
        if (!proof || proof.status !== "PASS") issue(`Kontrol proof not passed in the current receipt: ${compiled.proof}`);
      } else {
        report.awaiting.push(`Kontrol receipt for ${compiled.proof}`);
      }
    } else if (compiled.kind === "bridge") {
      const value = resolvePointer(bridge, compiled.path);
      if (value === undefined || (Array.isArray(value) && value.length === 0)) issue(`bridge field missing: ${compiled.path}`);
    } else if (compiled.kind === "bounded-runtime-execution") {
      if (!testExists(compiled.contract, compiled.test)) issue(`runtime execution test not found: ${compiled.contract}.${compiled.test}`);
      if (!(foundryReceiptCurrent && bridgeBindsRuntime)) report.awaiting.push(`Foundry receipt bound to the bridge runtime for ${compiled.test}`);
    } else if (compiled.kind === "vectors") {
      const ids = new Set([...vectors.actions, ...vectors.reversals, ...(vectors.negative ?? [])].map((entry) => entry.id));
      for (const id of compiled.ids ?? []) if (!ids.has(id)) issue(`vector missing: ${id}`);
      if (!Array.isArray(compiled.ids) || compiled.ids.length === 0) issue("vectors consumer without ids");
    } else {
      issue(`unknown compiled consumer shape ${JSON.stringify(compiled)}`);
    }
  }
  if (!Array.isArray(row.assumptions)) issue("assumptions must be a list");

  report.effectiveStatus = row.status === "CLOSED"
    ? (report.awaiting.length === 0 ? "CLOSED" : "CLOSED-PENDING-RECEIPT")
    : row.status;
  rowReports.push(report);
}

// every declared fault of the campaign is the negative of at least one row, or is listed as
// campaign-only with the reason it has no row (a fault in a test fixture rather than endpoint code)
for (const entry of ledger.campaignOnlyMutations ?? []) {
  if (!declaredMutations.has(entry.id)) fail(`campaign-only mutation not declared: ${entry.id}`);
  if (!entry.reason) fail(`campaign-only mutation without a reason: ${entry.id}`);
  if (citedMutations.has(entry.id)) fail(`campaign-only mutation is also cited by a row: ${entry.id}`);
  citedMutations.add(entry.id);
}
for (const id of declaredMutations.keys()) {
  if (!citedMutations.has(id)) fail(`declared mutation is not cited by any ledger row: ${id}`);
}

// state and receipt identity tables
for (const entry of ledger.stateIdentity ?? []) {
  for (const subject of ["native", "profileAdapter", "profileGovernor"]) {
    const label = entry[subject];
    if (label === null || label === undefined) continue;
    const storage = bridge.subjects[subject]?.storage ?? [];
    if (!storage.some((slot) => slot.projectionId === label)) fail(`state identity: unknown ${subject} storage projection ${label}`);
  }
}
const receiptFields = kernel.structs.Receipt.fields.map((field) => field.name);
for (const entry of ledger.receiptIdentity ?? []) {
  if (!receiptFields.includes(entry.abiField)) fail(`receipt identity: unknown ABI field ${entry.abiField}`);
  if (!factExists("TRUST_Compositional_State", `${entry.abstract}`) && !theories.get("TRUST_Compositional_State").includes(`  ${entry.abstract} ::`)) {
    fail(`receipt identity: unknown abstract receipt field ${entry.abstract}`);
  }
}
if ((ledger.receiptIdentity ?? []).length !== receiptFields.length) fail("receipt identity table does not cover every receipt field");

// route ticket slot cross-check between the bridge and the test base
const routeTicketSlot = bridge.subjects.native.storage.find((entry) => entry.label === "_routeTicket")?.slot;
const testBase = testSources.get("implementation/test/TrustTestBase.t.sol") ?? "";
const packedSlotMatch = testBase.match(/ROUTE_TICKET_PACKED_SLOT = (\d+);/);
if (routeTicketSlot === undefined || !packedSlotMatch || Number(packedSlotMatch[1]) !== routeTicketSlot + 3) {
  fail("route ticket packed slot in the test base does not match the compiled storage layout");
}

const counts = {
  rows: rowReports.length,
  closed: rowReports.filter((report) => report.effectiveStatus === "CLOSED").length,
  closedPendingReceipt: rowReports.filter((report) => report.effectiveStatus === "CLOSED-PENDING-RECEIPT").length,
  currentMandatory: rowReports.filter((report) => report.declaredStatus === "CURRENT-MANDATORY").length,
  successorMandatory: rowReports.filter((report) => report.declaredStatus === "SUCCESSOR-MANDATORY").length,
  separateProfile: rowReports.filter((report) => report.declaredStatus === "SEPARATE-PROFILE").length,
  notApplicable: rowReports.filter((report) => report.declaredStatus === "NOT-APPLICABLE").length,
};
if (counts.currentMandatory > 0) fail(`${counts.currentMandatory} current mandatory rows remain`);
// In release mode every closed row must be backed by a receipt of the current identity; in
// successor-development mode a missing receipt is reported as pending and owned by the lane index.
const evidenceMode = readJson("evidence/evidence-mode.json");
if (evidenceMode.mode === "release" && counts.closedPendingReceipt > 0) {
  fail(`release mode: ${counts.closedPendingReceipt} closed rows await a receipt of the current identity`);
}
if (counts.successorMandatory > 0 && ledger.closure.status !== "CONDITIONAL") fail("closure cannot leave CONDITIONAL while successor mandatory rows remain");
if (counts.successorMandatory === 0 && ledger.closure.status === "CONDITIONAL") fail("closure is CONDITIONAL without a successor mandatory row naming the missing link");

// ---------------------------------------------------------------------------
// Rendered artifacts
// ---------------------------------------------------------------------------

const isabelleString = (value) => {
  if (!/^[A-Za-z0-9_./:()\-,+@= ]*$/.test(value)) fail(`unsafe Isabelle string: ${value}`);
  return `''${value}''`;
};
const identifier = (id) => id.replace(/-/g, "_");
const rowLemmas = ledger.rows
  .filter((row) => row.abstractCondition && row.abstractCondition !== "none")
  .map((row) => `lemmas obligation_row_${identifier(row.id)} = ${row.abstractCondition.facts.filter((fact) => !fact.startsWith("locale:")).join(" ")}`)
  .join("\n");
const theory = `(* GENERATED by scripts/verify-obligation-ledger-v3.mjs. DO NOT EDIT. *)
theory TRUST_Obligation_Ledger_Generated
  imports
    TRUST_End_To_End_Composition
    TRUST_Verified_Profile_Onboarding
    TRUST_Reusable_Summaries
    TRUST_Decoder_Guard_Words
    TRUST_M4_Action_Reversal_Row_Corollaries
begin

definition obligation_ledger_sha256 :: string where
  "obligation_ledger_sha256 = ${isabelleString(ledgerSha256)}"

definition obligation_ledger_bridge_schema_sha256 :: string where
  "obligation_ledger_bridge_schema_sha256 = ${isabelleString(bridgeSchemaSha256)}"

definition obligation_ledger_closure_status :: string where
  "obligation_ledger_closure_status = ${isabelleString(ledger.closure.status)}"

definition obligation_ledger_row_ids :: "string list" where
  "obligation_ledger_row_ids =
    [${ledger.rows.map((row) => isabelleString(row.id)).join(",\n     ")}]"

definition obligation_ledger_current_mandatory_rows :: "string list" where
  "obligation_ledger_current_mandatory_rows =
    [${ledger.rows.filter((row) => row.status === "CURRENT-MANDATORY").map((row) => isabelleString(row.id)).join(", ")}]"

text \\<open>
  Each row below names the Isabelle facts that state its abstract condition.
  The build fails when a cited fact no longer exists, so the ledger cannot
  drift from the theories it points into.
\\<close>

${rowLemmas}

theorem obligation_ledger_rows_are_distinct:
  "distinct obligation_ledger_row_ids"
  by (simp add: obligation_ledger_row_ids_def)

theorem obligation_ledger_has_no_current_mandatory_rows:
  "obligation_ledger_current_mandatory_rows = []"
  by (simp add: obligation_ledger_current_mandatory_rows_def)

theorem obligation_ledger_binds_the_generated_bridge:
  "obligation_ledger_bridge_schema_sha256 = runtime_bridge_schema_sha256"
  by (simp add: obligation_ledger_bridge_schema_sha256_def runtime_bridge_schema_sha256_def)

theorem obligation_ledger_closure_status_is_declared:
  "obligation_ledger_closure_status = ${isabelleString(ledger.closure.status)}"
  by (simp add: obligation_ledger_closure_status_def)

end
`;

const summary = {
  schema: "erc-trust-obligation-ledger-summary-v3",
  candidate: ledger.candidate,
  ledger: { path: paths.ledger, sha256: ledgerSha256 },
  bridgeSchema: { path: paths.bridgeSchema, sha256: bridgeSchemaSha256 },
  runtimeTemplateSha256: runtimeSha256,
  bridgeBindsRuntime,
  receipts: Object.fromEntries(Object.entries(receipts).map(([lane, receipt]) => [lane, receipt ? { path: receipt.path, sha256: receipt.sha256 } : null])),
  receiptCurrency: { mutation: mutationReceiptCurrent, kontrol: kontrolReceiptCurrent, foundry: foundryReceiptCurrent },
  counts,
  rows: rowReports.map((report) => ({ id: report.id, endpoint: report.endpoint, declaredStatus: report.declaredStatus, effectiveStatus: report.effectiveStatus, awaiting: report.awaiting })),
  claim: ledger.claimLadder.current,
  closure: ledger.closure.status,
  generatedTheory: { path: paths.theory, sha256: sha256(Buffer.from(theory, "utf8")) },
};
const closure = {
  schema: "erc-trust-central-refinement-closure-v3",
  kind: "ERC_TRUST_CENTRAL_REFINEMENT_CLOSURE_V3",
  candidate: ledger.candidate,
  status: ledger.closure.status,
  claim: ledger.claimLadder,
  identity: {
    ledgerSha256,
    bridgeSchemaSha256,
    runtimes: Object.fromEntries(Object.entries(bridge.subjects).map(([subject, entry]) => [subject, entry.runtime])),
    deterministicBuildRuntimeSha256: runtimeSha256,
    bridgeBindsRuntime,
  },
  preservation: ledger.closure.preservation,
  reflection: ledger.closure.reflection,
  routeExhaustiveness: {
    theorems: ["native_routes_are_exhaustive", "profile_adapter_routes_are_exhaustive", "profile_governor_routes_are_exhaustive", "generic_dispatcher_selector_is_unclassified"],
    subjects: Object.fromEntries(Object.entries(bridge.subjects).map(([subject, entry]) => [subject, {
      classifiedSelectors: entry.routes.length,
      classes: Object.fromEntries(Object.entries(entry.routes.reduce((acc, route) => ({ ...acc, [route.routeClass]: (acc[route.routeClass] ?? 0) + 1 }), {})).sort()),
    }])),
    nonconformantPath: "any selector outside the classified set falls through the compiler dispatcher and reverts with empty data (generic_dispatcher_revert_is_not_typed_failure)",
  },
  stateIdentity: ledger.stateIdentity,
  receiptIdentity: ledger.receiptIdentity,
  assumptions: ledger.assumptions,
  counts,
  rows: rowReports.map((report) => ({ id: report.id, effectiveStatus: report.effectiveStatus })),
  supersededCandidate2: ledger.supersededCandidate2,
};

summary.closureRecord = { path: paths.closure, sha256: sha256(Buffer.from(text(closure), "utf8")) };

const rendered = [
  { path: paths.theory, content: theory },
  { path: paths.summary, content: text(summary) },
  { path: paths.closure, content: text(closure) },
];
if (writeMode) {
  for (const entry of rendered) writeFileSync(abs(entry.path), entry.content, "utf8");
} else {
  for (const entry of rendered) {
    if (!exists(entry.path) || readText(entry.path) !== entry.content) fail(`rendered artifact drift: ${entry.path} (rerun with --write)`);
  }
}

if (failures.length) {
  for (const failure of failures) console.error(failure);
  process.exit(1);
}
console.log(JSON.stringify({
  status: counts.closedPendingReceipt === 0 ? "PASS" : "PASS_PENDING_RECEIPTS",
  rows: counts,
  claim: ledger.claimLadder.current,
  closure: ledger.closure.status,
  ledgerSha256,
}, null, 2));
