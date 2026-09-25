// SPDX-License-Identifier: BSD-3-Clause
// Evidence accounting and approval-record consistency, not a proof checker.
import { check, checkLocalReceiptProvenance, encoded, json, read, sha256 } from './local-evidence.mjs';
import { formalAdmissionDigest, validateFormalIdentity } from './formal-inputs.mjs';

export const profiles = ['NATIVE', 'PARTIAL', 'HOOK'];
export const components = ['constructor-storage', 'calldata-dispatch', 'authorization-replay',
  'dependency-calls', 'effects-frame', 'revert', 'receipt-logs'];
export const grades = ['UNVERIFIED', 'EXECUTION_TESTS', 'LIMITED_SCOPE_PROOF', 'FULL_SCOPE_PROOF'];
export const mandatoryIds = ['NATIVE-SYMBOLIC-FREEZE', ...profiles.map(p => `RUNTIME-LINK-${p}`)].sort();
// The stable RESEARCH-* identifiers predate the current completion direction; their status is mandatory.
export const generalIds = profiles.map(p => `RESEARCH-RUNTIME-LINK-${p}`).sort();
const nativeClaim = 'For every positive first and second target with second <= first, including first above supply, the second FREEZE stutters the named Native projection.';
const legacyClosedIds = ['HOOK-FRESH-INITIAL','HOOK-FACTORY-CREATION','HOOK-SOLE-AGENT',
  'HOOK-INBOUND-FLOOR','HOOK-CALLER-AUTH','HOOK-CALLBACK-ROLLBACK','HOOK-ACTUAL-RECEIPT',
  'HOOK-INDEPENDENT-FINAL','MODEL-INITIAL-WF','MODEL-ORDINARY-PRESERVATION',
  'MODEL-REGULATORY-PRESERVATION','MODEL-LINKED-RUN'];
export const disclosures = ['evidence/claim-matrix.md', 'evidence/known-limitations.md',
  'evidence/trust12/release-notes.md'];
export const implementationDisclosures = [...disclosures, 'evidence/trust12/README.md'];
const generalRuntimeContracts = {
  NATIVE: ['TrustToken'],
  PARTIAL: ['ERC3643TrustAdapter', 'ProfileGovernor'],
  HOOK: ['ERC3643HookAdapter', 'ERC3643HookGovernor', 'ERC3643HookCompliance', 'ERC3643HookFactory'],
};
const approvedScopeHashes = {
  NATIVE: 'b85536029cce8a0dd4cf7e41ee9960c6401c7e27ed15f95063d1960fbc9eed28',
  PARTIAL: 'f23dff48dac5a56ae92a1058c22bd264d752c285540b69d9188d82cdc57b9476',
  HOOK: '1811e1c8d30167502cbc8cc8ffa9c54eea02875b50d83d502ba8c8364a7a01d7',
};
const nonempty = value => typeof value === 'string' && value.trim().length > 0;
const sameSet = (a, b) => Array.isArray(a) && new Set(a).size === a.length
  && encoded([...a].sort()) === encoded([...b].sort());

export function withoutIsabelleComments(source) {
  let depth = 0, code = '';
  for (let i = 0; i < source.length; i++) {
    const pair = source.slice(i, i + 2);
    if (pair === '(*') { depth++; i++; continue; }
    if (pair === '*)' && depth > 0) { depth--; i++; continue; }
    if (depth === 0) code += source[i];
  }
  check(depth === 0, 'unclosed Isabelle proof audit comment');
  return code;
}

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
    reference(root, cell.result.receipt, 'proof result');
    const proofReceipt = json(root, cell.result.receipt.path);
    check(Array.isArray(proofReceipt.proofs) && cell.result.claimIds.every(id => {
      const item = proofReceipt.proofs.find(proof => proof.id === id);
      return item?.status === 'PASS' && item.unresolvedGoals === 0
        && item.admittedGoals === 0 && item.vacuous === false;
    }), 'proof result metadata is not receipt-backed');
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

function verifiedGeneralLink(root, row, profile, policy) {
  const proof = row.generalProofEvidence;
  check(proof?.status === 'PASS_GENERAL_RUNTIME_LINK' && proof.profile === profile
    && nonempty(proof.theoremName) && nonempty(proof.formalSession)
    && proof.theoremName.startsWith(`${profile.toLowerCase()}_general_runtime_link`)
    && sameSet(Object.keys(proof.references ?? {}),
      ['execution','formalProof','positive','negative','compiledConsumer']),
  `general runtime link lacks a verified proof contract: ${row.id}`);
  const refs = proof.references;
  check(new Set(Object.values(refs).map(ref => ref.path)).size === 5
    && refs.formalProof.path === 'evidence/isabelle-results-v3.json',
  `general runtime link evidence roles or formal receipt drift: ${row.id}`);
  for (const ref of Object.values(refs)) reference(root, ref, 'general runtime link');
  const runtimeIdentity = json(root, 'evidence/trust12/runtime-identity.json');
  for (const input of runtimeIdentity.sourceInputs) reference(root, input, 'general runtime source');
  const expectedRuntimes = Object.fromEntries(generalRuntimeContracts[profile].map(name =>
    [name, runtimeIdentity.runtimes[name]?.runtimeSha256]));
  check(Object.values(expectedRuntimes).every(hash => /^[a-f0-9]{64}$/.test(hash))
    && encoded(proof.runtimeSha256ByContract) === encoded(expectedRuntimes)
    && proof.sourceInventorySha256 === sha256(encoded(runtimeIdentity.sourceInputs))
    && proof.abiSha256 === sha256(read(root, 'spec/generated/kernel-v2-abi.json'))
    && proof.scopeSha256 === sha256(policy.profileScopes[profile])
    && proof.conditionSha256 === sha256(row.abstractCondition),
  `general runtime link final input or declared domain drift: ${row.id}`);
  const formal = json(root, refs.formalProof.path);
  checkLocalReceiptProvenance(root, formal, 'local-windows-isabelle');
  validateFormalIdentity(root, formal.formalSource);
  const replay = json(root, 'evidence/trust12/formal-build-replay.json');
  const generalAdmission = sha256(encoded({baseAdmissionDigest:replay.admissionDigest,
    generalRuntimeLinks:replay.generalRuntimeLinks}));
  check(replay.status === 'PASS' && replay.processExit === 0
    && replay.admissionDigest === formalAdmissionDigest(replay)
    && formal.admissionDigest === replay.admissionDigest
    && encoded(replay.formalSource) === encoded(formal.formalSource)
    && encoded(replay.sessions) === encoded(formal.sessions)
    && encoded(replay.generalRuntimeLinks) === encoded(formal.generalRuntimeLinks)
    && replay.generalRuntimeLinkAdmissionDigest === generalAdmission
    && formal.generalRuntimeLinkAdmissionDigest === generalAdmission
    && proof.generalRuntimeLinkAdmissionDigest === generalAdmission,
  `general runtime link has no admitted current formal execution: ${row.id}`);
  const session = formal.sessions?.find(item => item.name === proof.formalSession);
  const admitted = formal.generalRuntimeLinks?.[profile];
  check(formal.status === 'PASS' && formal.checks?.oracleDependencyCount === 0
    && formal.formalSource.sessions?.includes(proof.formalSession)
    && session?.status === 'PASS' && session.proofExport === 'PASS' && session.oracleDependencies === 0
    && admitted?.status === 'PASS_KERNEL_CHECKED_GENERAL_RUNTIME_LINK'
    && admitted.theoremName === proof.theoremName && admitted.formalSession === proof.formalSession
    && admitted.exportSha256 === session.exportSha256 && admitted.oracleDependencies === 0
    && admitted.scopeSha256 === proof.scopeSha256
    && Array.isArray(admitted.auditTheorems) && admitted.auditTheorems.includes(proof.theoremName)
    && encoded(admitted.runtimeSha256ByContract) === encoded(expectedRuntimes),
  `general runtime link has no admitted Isabelle export: ${row.id}`);
  for (const path of [admitted.sourcePath, admitted.auditPath]) {
    check(typeof path === 'string' && path.startsWith('formal/isabelle/') && !path.includes('..')
      && formal.formalSource.inputs.some(item => item.path === path && item.sha256 === sha256(read(root, path))),
    `general runtime link formal source is not in the admitted build: ${row.id}`);
  }
  check(withoutIsabelleComments(read(root, admitted.auditPath).toString('utf8'))
    .includes(`@{thm ${proof.theoremName}}`),
    `general runtime link theorem is outside the proof audit: ${row.id}`);
  for (const role of ['execution','positive','negative','compiledConsumer']) {
    const record = json(root, refs[role].path);
    check(record.schema === 'trust12-general-runtime-link-evidence-v1' && record.role === role
      && record.profile === profile && record.sourceInventorySha256 === proof.sourceInventorySha256
      && record.abiSha256 === proof.abiSha256 && record.scopeSha256 === proof.scopeSha256
      && encoded(record.runtimeSha256ByContract) === encoded(expectedRuntimes)
      && record.proofExportSha256 === session.exportSha256
      && record.status === (role === 'negative' ? 'KILLED' : 'PASS'),
    `general runtime link ${role} is not bound to the admitted execution: ${row.id}`);
    if (role === 'execution') check(record.machineChecked === true && record.acceptedRuns > 0,
      `general runtime link has no checked execution: ${row.id}`);
    if (role === 'positive') check(record.activated === true,
      `general runtime link positive branch did not activate: ${row.id}`);
    if (role === 'negative') check(record.sameDomain === true && record.consumerRemovalKilled === true,
      `general runtime link has no same-domain consumer-removal negative: ${row.id}`);
    if (role === 'compiledConsumer') check(record.compiledConsumption === true,
      `general runtime link has no compiled consumer: ${row.id}`);
  }
}

export function verifiedCentralCompletion(endToEnd) {
  const centralRows = new Map(endToEnd.rows?.map(row => [row.id, row]) ?? []);
  const centralAssumptions = new Map(endToEnd.assumptions?.map(item => [item.id, item]) ?? []);
  return endToEnd.closure?.status === 'COMPLETE'
    && sameSet(endToEnd.closure?.profileCoverage, profiles)
    && ['NAT-E2E-01','ADP-E2E-01'].every(id => centralRows.get(id)?.status === 'CLOSED')
    && ['A-RUNTIME-LINK','A-RUNTIME-LINK-SPEC'].every(id => centralAssumptions.get(id)?.status === 'DISCHARGED')
    && endToEnd.rows?.every(row => !['CURRENT-MANDATORY','SUCCESSOR-MANDATORY'].includes(row.status));
}

export function verifyTrust12Policy(root) {
  const policy = json(root, 'evidence/trust12/release-policy.json');
  const ledger = json(root, 'evidence/trust12/obligation-ledger.json');
  check(policy.schema === 'trust12-release-policy-v2' && ledger.schema === 'trust12-obligation-ledger-v2', 'release policy schema');
  check(policy.approval?.kind === 'RELEASE_SCOPE_RESET' && policy.approval.approvedBy === 'Jay Kim'
    && policy.approval.date === '2026-09-13' && nonempty(policy.approval.userInstruction), 'missing scope-reset approval');
  check(policy.completionDirection?.kind === 'TRUST12_COMPLETION_DIRECTION'
    && policy.completionDirection.approvedBy === 'Jay Kim' && policy.completionDirection.date === '2026-09-25'
    && nonempty(policy.completionDirection.userInstruction), 'current TRUST 1.2 completion direction missing');
  check(policy.generalRuntimeLinkRequiredForRelease === true && policy.parserDevelopment === 'ACTIVE_FOR_TRUST12'
    && policy.nativeProbe?.automaticBoundedClosure === false
    && policy.nativeProbe?.decisionAuthority === 'Jay Kim', 'release policy boundary drift');
  check(profiles.every(profile => nonempty(policy.profileScopes?.[profile])
    && sha256(policy.profileScopes[profile]) === approvedScopeHashes[profile]),
  'general profile scope missing or narrowed');
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
  const certora = json(root, 'evidence/certora-results-v3.json');
  check(policy.toolchain.certora === certora.toolchain?.certoraCli
    && policy.toolchain.certora === certora.toolchain?.certoraServer
    && nonempty(policy.certoraVersionPolicy), 'Certora tool version differs from current receipt');
  const rows = new Map(ledger.obligations.map(row => [row.id, row]));
  check(rows.size === ledger.obligations.length, 'duplicate obligation id');
  check(sameSet([...rows.keys()], [...legacyClosedIds, ...mandatoryIds, ...generalIds])
    && legacyClosedIds.every(id => rows.get(id)?.status === 'CLOSED'), 'named obligation inventory drift');
  const allowed = ['CLOSED', 'CURRENT-MANDATORY', 'OPEN-SHIPPING-EXCEPTION'];
  for (const row of rows.values()) {
    check(allowed.includes(row.status), `unknown status: ${row.id}`);
    if (row.status !== 'OPEN-SHIPPING-EXCEPTION') check(row.shippingException == null, 'shipping approval attached to non-exception row');
    if (row.status === 'CLOSED') {
      check(!/pending/i.test(row.positiveActivation) && !/pending/i.test(row.consumerRemovalNegative), `closed row has pending evidence: ${row.id}`);
    }
  }
  for (const id of generalIds) {
    const row = rows.get(id);
    check(['CURRENT-MANDATORY', 'CLOSED'].includes(row.status)
      && row.requiredForRelease === true && row.requiredForTrust12Completion === true
      && nonempty(row.abstractCondition), `general runtime link removed: ${id}`);
    for (const key of ['receivingProcess', 'responsibleArtifact', 'closureEvidence', 'reopenCondition'])
      check(nonempty(row[key]), `general runtime link missing ${key}: ${id}`);
    if (row.status === 'CURRENT-MANDATORY') {
      check(row.proofCompleted === false && row.generalProofEvidence == null,
        `unproved general runtime link claims completion: ${id}`);
    } else {
      check(row.proofCompleted === true, `general runtime link proof flag missing: ${id}`);
      verifiedGeneralLink(root, row, id.slice('RESEARCH-RUNTIME-LINK-'.length), policy);
      for (const key of ['positiveActivation','consumerRemovalNegative','compiledConsumer'])
        check(nonempty(row[key]) && !/pending|bounded instances only/i.test(row[key]),
          `general runtime link has no completed ${key}: ${id}`);
    }
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
  check(pending.every(id => [...mandatoryIds, ...generalIds].includes(id))
    && exceptions.every(r => mandatoryIds.includes(r.id)), 'unexpected release obligation');
  check(sameSet(ledger.centralClosure.currentMandatory, pending), 'central mandatory list differs from obligation statuses');
  check(sameSet(ledger.centralClosure.researchResiduals, []), 'general runtime link mislabeled as research residual');
  check(sameSet(ledger.centralClosure.shippingExceptions, exceptions.map(r => r.id)), 'central exception list drift');
  const assurance = ledger.centralClosure.independentAssurance;
  const audited = assurance?.status === 'PASS_FRESH_ASSURANCE' && assurance?.report &&
    (() => {
      check(assurance.report.path.startsWith('evidence/trust12/assurance/'),
        'fresh assurance report is outside its declared evidence area');
      reference(root, assurance.report, 'fresh assurance');
      const report = json(root, assurance.report.path);
      const generalDigests = Object.fromEntries(profiles.map(profile => {
        const proof = rows.get(`RESEARCH-RUNTIME-LINK-${profile}`).generalProofEvidence;
        return [profile, proof ? sha256(encoded(proof)) : null];
      }));
      const finalIdentities = {
        formalRootSha256: json(root, 'evidence/isabelle-results-v3.json').formalSource.rootSha256,
        runtimeIdentitySha256: sha256(read(root, 'evidence/trust12/runtime-identity.json')),
        abiSha256: sha256(read(root, 'spec/generated/kernel-v2-abi.json')),
        endToEndLedgerSha256: sha256(read(root, 'evidence/end-to-end-refinement/obligation-ledger-v3.json')),
        generalProofDigests: generalDigests,
      };
      check(report.schema === 'trust12-final-assurance-v1' && report.status === 'PASS_FRESH_ASSURANCE'
        && report.independentOfBuilding === true && nonempty(report.reviewer)
        && report.reproduction?.status === 'PASS' && report.consumerRemoval?.status === 'PASS'
        && Object.values(generalDigests).every(nonempty)
        && encoded(report.finalIdentities) === encoded(finalIdentities),
      'fresh assurance report is not independently reproduced on the final inputs');
      return true;
    })();
  const endToEnd = json(root, 'evidence/end-to-end-refinement/obligation-ledger-v3.json');
  const endToEndClosed = verifiedCentralCompletion(endToEnd);
  const complete = pending.length === 0 && exceptions.length === 0
    && mandatoryIds.every(id => rows.get(id).status === 'CLOSED')
    && generalIds.every(id => rows.get(id).status === 'CLOSED')
    && endToEndClosed === true && audited === true;
  check(ledger.centralClosure.status === (complete ? 'COMPLETE' : 'INCOMPLETE'), 'central completion status drift');
  for (const row of exceptions) exception(root, row);
  const readiness = pending.length ? 'PENDING' : exceptions.length ? 'READY_WITH_EXCEPTIONS' : 'EVIDENCE_READY';
  check(ledger.releaseAssessment?.status === readiness
    && ledger.releaseAssessment.fullRefinementComplete === complete, 'release readiness drift');
  check(ledger.status === (pending.length ? 'IN_PROGRESS' : exceptions.length ? 'EVIDENCE_COMPLETE_WITH_EXCEPTIONS' : 'EVIDENCE_COMPLETE'), 'ledger status drift');
  for (const path of disclosures) {
    const text = read(root, path).toString('utf8');
    const incompletePhrase = text.includes('mapped implementation evidence; end-to-end refinement incomplete');
    const completePhrase = text.includes('end-to-end refinement complete within the declared profiles');
    check(complete ? completePhrase && !incompletePhrase : incompletePhrase && !completePhrase,
      `claim boundary drift: ${path}`);
    check(text.includes('TRUST 1.2 shipping exceptions: none.') === (exceptions.length === 0), `exception summary drift: ${path}`);
  }
  const profileRows = profiles.map(profile => rows.get(`RUNTIME-LINK-${profile}`));
  check(profileRows.every(row => row.status === 'CLOSED' && row.components.every(cell => cell.evidenceGrade !== 'UNVERIFIED')),
    'profile implementation evidence inventory incomplete');
  const gradeDisclosure = `TRUST 1.2 profile row grades: Native ${profileRows[0].evidenceGrade}; Partial ${profileRows[1].evidenceGrade}; Hook ${profileRows[2].evidenceGrade}.`;
  for (const path of implementationDisclosures)
    check(read(root, path).toString('utf8').includes(gradeDisclosure), `profile grade disclosure drift: ${path}`);
  return { status: 'PASS_POLICY_CONSISTENCY', releaseReadiness: readiness, currentMandatory: pending,
    generalRuntimeLinkMandatory: generalIds.filter(id => rows.get(id).status !== 'CLOSED'),
    researchResiduals: [], shippingExceptions: exceptions.map(r => r.id), fullRefinementComplete: complete };
}
