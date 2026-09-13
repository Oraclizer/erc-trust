// SPDX-License-Identifier: BSD-3-Clause
// Evidence accounting and approval-record consistency, not a proof checker.
import { check, encoded, json, read, sha256 } from './local-evidence.mjs';

export const profiles = ['NATIVE', 'PARTIAL', 'HOOK'];
export const components = ['constructor-storage', 'calldata-dispatch', 'authorization-replay',
  'dependency-calls', 'effects-frame', 'revert', 'receipt-logs'];
export const grades = ['UNVERIFIED', 'EXECUTION_TESTS', 'LIMITED_SCOPE_PROOF', 'FULL_SCOPE_PROOF'];
export const mandatoryIds = ['NATIVE-SYMBOLIC-FREEZE', ...profiles.map(p => `RUNTIME-LINK-${p}`)].sort();
export const researchIds = profiles.map(p => `RESEARCH-RUNTIME-LINK-${p}`).sort();
const nativeClaim = 'For every positive first and second target with second <= first, including first above supply, the second FREEZE stutters the named Native projection.';
const legacyClosedIds = ['HOOK-FRESH-INITIAL','HOOK-FACTORY-CREATION','HOOK-SOLE-AGENT',
  'HOOK-INBOUND-FLOOR','HOOK-CALLER-AUTH','HOOK-CALLBACK-ROLLBACK','HOOK-ACTUAL-RECEIPT',
  'HOOK-INDEPENDENT-FINAL','MODEL-INITIAL-WF','MODEL-ORDINARY-PRESERVATION',
  'MODEL-REGULATORY-PRESERVATION','MODEL-LINKED-RUN'];
export const disclosures = ['evidence/claim-matrix.md', 'evidence/known-limitations.md',
  'evidence/trust12/release-notes.md'];
const nonempty = value => typeof value === 'string' && value.trim().length > 0;
const sameSet = (a, b) => Array.isArray(a) && new Set(a).size === a.length
  && encoded([...a].sort()) === encoded([...b].sort());

function reference(root, ref, label) {
  check(ref && nonempty(ref.path) && /^[a-f0-9]{64}$/.test(ref.sha256), `missing ${label} reference`);
  check(sha256(read(root, ref.path)) === ref.sha256, `${label} reference drift: ${ref.path}`);
}

function evidence(root, cell, toolchain) {
  check(grades.includes(cell.evidenceGrade), 'unknown evidence grade');
  for (const key of ['property', 'inputScope', 'stateScope']) check(nonempty(cell[key]), `missing ${key}`);
  check(encoded(cell.toolPins) === encoded(toolchain), 'component tool pins drift');
  for (const ref of cell.reuseCandidates ?? []) reference(root, ref, 'reuse candidate');
  check(Array.isArray(cell.evidence) && Array.isArray(cell.artifactBindings), 'missing evidence arrays');
  check(['UNVERIFIED', 'KILLED_CONSUMER_REMOVAL', 'BOUNDED_BEHAVIORAL'].includes(cell.negative?.kind), 'unknown negative kind');
  check(nonempty(cell.negative?.scope) && Array.isArray(cell.negative.evidence), 'missing negative scope');
  if (cell.evidenceGrade === 'UNVERIFIED') {
    check(cell.result == null, 'unverified component asserts a successful result');
    return;
  }
  check(cell.evidence.length > 0 && cell.artifactBindings.length > 0, 'graded component lacks bound evidence');
  for (const ref of cell.evidence) reference(root, ref, 'positive');
  for (const ref of cell.artifactBindings) reference(root, ref, 'compiled artifact');
  check(cell.negative.kind !== 'UNVERIFIED' && cell.negative.evidence.length > 0, 'graded component lacks negative evidence');
  for (const ref of cell.negative.evidence) reference(root, ref, 'negative');
  check(Array.isArray(cell.assumptions) && cell.assumptions.every(nonempty), 'missing assumptions list');
  check(cell.result?.status === 'PASS', 'graded component has no PASS result');
  if (cell.evidenceGrade.endsWith('_PROOF')) {
    check(['Kontrol/KEVM', 'Certora'].includes(cell.result.tool)
      && cell.result.kind === 'PROOF' && cell.result.unresolvedGoals === 0
      && cell.result.admittedGoals === 0 && cell.result.vacuous === false
      && Array.isArray(cell.result.claimIds) && cell.result.claimIds.length > 0
      && cell.result.claimIds.every(nonempty), 'proof grade lacks completed nonvacuous proof claims');
    if (cell.result.tool === 'Certora') check(!toolchain.certora.startsWith('UNRECORDED'), 'Certora proof requires exact run version');
    if (cell.evidenceGrade === 'LIMITED_SCOPE_PROOF') check(nonempty(cell.result.limits), 'limited proof lacks limits');
    if (cell.evidenceGrade === 'FULL_SCOPE_PROOF') check(cell.result.coversDeclaredScope === true, 'full proof does not cover declared scope');
  } else {
    check(cell.result.kind === 'TESTS' && nonempty(cell.result.sampleScope), 'execution tests lack sample scope');
  }
  reference(root, cell.review, 'scope review');
}

function exception(root, row) {
  const e = row.shippingException;
  check(e && e.proofCompleted === false && nonempty(e.unverifiedScope), 'exception must retain unproved scope');
  for (const key of ['receivingProcess', 'responsibleArtifact', 'closureEvidence', 'resumeCondition'])
    check(nonempty(e.carryover?.[key]), `exception missing carryover ${key}`);
  reference(root, e.approval, 'shipping approval');
  const approval = json(root, e.approval.path);
  check(approval.kind === 'SHIPPING_EXCEPTION' && approval.approvedBy === 'Jay Kim'
    && /^\d{4}-\d{2}-\d{2}$/.test(approval.date) && Number.isFinite(Date.parse(approval.date))
    && approval.obligationId === row.id && nonempty(approval.allowedScope)
    && approval.allowedScope === e.allowedScope && nonempty(approval.userInstruction), 'invalid row-specific shipping approval');
  check(e.approval.path !== 'evidence/trust12/release-policy.json', 'scope reset is not shipping approval');
  check(nonempty(e.disclosure) && e.disclosure.includes(row.id) && e.disclosure.includes('unproven'), 'exception disclosure must name unproven obligation');
  for (const path of disclosures) check(read(root, path).toString('utf8').includes(e.disclosure), `missing exception disclosure: ${path}`);
}

export function verifyTrust12Policy(root) {
  const policy = json(root, 'evidence/trust12/release-policy.json');
  const ledger = json(root, 'evidence/trust12/obligation-ledger.json');
  check(policy.schema === 'trust12-release-policy-v1' && ledger.schema === 'trust12-obligation-ledger-v2', 'release policy schema');
  check(policy.approval?.kind === 'RELEASE_SCOPE_RESET' && policy.approval.approvedBy === 'Jay Kim'
    && policy.approval.date === '2026-09-13' && nonempty(policy.approval.userInstruction), 'missing scope-reset approval');
  check(policy.generalRuntimeLinkRequiredForRelease === false && policy.parserDevelopment === 'PRESERVE_ONLY'
    && policy.nativeProbe?.automaticBoundedClosure === false
    && policy.nativeProbe?.decisionAuthority === 'Jay Kim', 'release policy boundary drift');
  for (const name of ['isabelle', 'kevmCommit', 'kCommit', 'koreCommit', 'z3', 'solc', 'kontrol', 'foundry', 'schedule', 'certora'])
    check(nonempty(policy.toolchain?.[name]), `missing pinned tool ${name}`);
  reference(root, policy.toolchainSource, 'TCB source');
  const source = read(root, policy.toolchainSource.path).toString('utf8');
  const fields = { isabelle:'tcb_isabelle', kevmCommit:'tcb_kevm_commit', kCommit:'tcb_k_commit',
    koreCommit:'tcb_kore_commit', z3:'tcb_z3_version', solc:'tcb_solc_version' };
  for (const [name, field] of Object.entries(fields)) {
    const values = [...source.matchAll(new RegExp(`\\b${field}\\s*=\\s*''([^']+)''`, 'g'))];
    check(values.length === 1 && values[0][1] === policy.toolchain[name], `tool pin differs from formal TCB: ${name}`);
    if (name.endsWith('Commit')) check(/^[a-f0-9]{40}$/.test(policy.toolchain[name]), 'tool commit must be full length');
  }
  const symbolic = json(root, 'evidence/trust12/symbolic-kontrol.json');
  check(policy.toolchain.kontrol === symbolic.toolchain.kontrol
    && policy.toolchain.foundry === symbolic.toolchain.forge && policy.toolchain.schedule === symbolic.toolchain.schedule, 'execution tool pins drift');
  const rows = new Map(ledger.obligations.map(row => [row.id, row]));
  check(rows.size === ledger.obligations.length, 'duplicate obligation id');
  check(sameSet([...rows.keys()], [...legacyClosedIds, ...mandatoryIds, ...researchIds])
    && legacyClosedIds.every(id => rows.get(id)?.status === 'CLOSED'), 'named obligation inventory drift');
  const allowed = ['CLOSED', 'CURRENT-MANDATORY', 'RESEARCH-RESIDUAL', 'OPEN-SHIPPING-EXCEPTION'];
  for (const row of rows.values()) {
    check(allowed.includes(row.status), `unknown status: ${row.id}`);
    if (row.status !== 'OPEN-SHIPPING-EXCEPTION') check(row.shippingException == null, 'shipping approval attached to non-exception row');
    if (row.status === 'CLOSED') {
      check(!/pending/i.test(row.positiveActivation) && !/pending/i.test(row.consumerRemovalNegative), `closed row has pending evidence: ${row.id}`);
    }
  }
  check(researchIds.every(id => rows.get(id)?.status === 'RESEARCH-RESIDUAL'), 'runtime research residual removed or promoted');
  for (const id of researchIds) {
    const row = rows.get(id);
    check(row.requiredForRelease === false && nonempty(row.abstractCondition) && row.proofCompleted === false, 'research boundary drift');
  }
  for (const p of profiles) {
    const row = rows.get(`RUNTIME-LINK-${p}`);
    check(row && ['CURRENT-MANDATORY', 'CLOSED', 'OPEN-SHIPPING-EXCEPTION'].includes(row.status), 'implementation obligation removed');
    check(row.criterion === 'PROFILE_IMPLEMENTATION_EVIDENCE' && row.researchResidualId === `RESEARCH-RUNTIME-LINK-${p}`, 'profile criterion drift');
    check(sameSet(row.components?.map(c => c.id), components), 'profile must contain exactly seven components');
    for (const c of row.components) evidence(root, c, policy.toolchain);
    const grade = grades[Math.min(...row.components.map(c => grades.indexOf(c.evidenceGrade)))];
    check(row.evidenceGrade === grade, 'row grade is not its weakest component');
    if (row.status === 'CLOSED') check(grade !== 'UNVERIFIED', 'unreviewed mandatory obligation removal: unverified component');
  }
  const native = rows.get('NATIVE-SYMBOLIC-FREEZE');
  check(native && ['CURRENT-MANDATORY', 'CLOSED', 'OPEN-SHIPPING-EXCEPTION'].includes(native.status), 'native obligation removed');
  check(native.abstractCondition === nativeClaim, 'native general property changed');
  check(native.inputDomain === 'first > 0 and second > 0 and second <= first'
    && native.notAssumed === 'first <= total supply', 'native general domain narrowed');
  evidence(root, native.symbolicEvidence, policy.toolchain);
  if (native.status === 'CLOSED') {
    const e = native.symbolicEvidence;
    check(e.evidenceGrade === 'FULL_SCOPE_PROOF', 'bounded evidence cannot close general Native proof');
    check(e.property === native.abstractCondition && e.inputScope === native.inputDomain
      && e.notAssumed === native.notAssumed, 'Native proof scope does not match original general obligation');
    check(e.negative.kind === 'KILLED_CONSUMER_REMOVAL'
      && e.negative.inputScope === native.inputDomain && e.negative.notAssumed === native.notAssumed
      && e.negative.coversDeclaredScope === true, 'Native negative does not cover original input domain');
  }
  const pending = [...rows.values()].filter(r => r.status === 'CURRENT-MANDATORY').map(r => r.id).sort();
  const exceptions = [...rows.values()].filter(r => r.status === 'OPEN-SHIPPING-EXCEPTION');
  check(pending.every(id => mandatoryIds.includes(id)) && exceptions.every(r => mandatoryIds.includes(r.id)), 'unexpected release obligation');
  check(sameSet(ledger.centralClosure.currentMandatory, pending), 'central mandatory list differs from obligation statuses');
  check(sameSet(ledger.centralClosure.researchResiduals, researchIds), 'central research list drift');
  check(sameSet(ledger.centralClosure.shippingExceptions, exceptions.map(r => r.id)), 'central exception list drift');
  check(ledger.centralClosure.status === 'INCOMPLETE', 'research residual is not end-to-end completion');
  for (const row of exceptions) exception(root, row);
  const readiness = pending.length ? 'PENDING' : exceptions.length ? 'READY_WITH_EXCEPTIONS' : 'EVIDENCE_READY';
  check(ledger.releaseAssessment?.status === readiness && ledger.releaseAssessment.fullRefinementComplete === false, 'release readiness drift');
  check(ledger.status === (pending.length ? 'IN_PROGRESS' : exceptions.length ? 'EVIDENCE_COMPLETE_WITH_EXCEPTIONS' : 'EVIDENCE_COMPLETE'), 'ledger status drift');
  for (const path of disclosures) {
    const text = read(root, path).toString('utf8');
    check(text.includes('mapped implementation evidence; end-to-end refinement incomplete'), `missing limited claim: ${path}`);
    check(text.includes('TRUST 1.2 shipping exceptions: none.') === (exceptions.length === 0), `exception summary drift: ${path}`);
  }
  return { status: 'PASS_POLICY_CONSISTENCY', releaseReadiness: readiness, currentMandatory: pending,
    researchResiduals: researchIds, shippingExceptions: exceptions.map(r => r.id), fullRefinementComplete: false };
}
