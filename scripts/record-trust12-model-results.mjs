// SPDX-License-Identifier: BSD-3-Clause
// Record model claims only after the current complete clean build has been captured.
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { writeFileSync } from 'node:fs';
import { check, encoded, fileRef, json, read } from './lib/local-evidence.mjs';
import { formalAdmissionDigest, validateFormalIdentity } from './lib/formal-inputs.mjs';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const replay = json(root, 'evidence/trust12/formal-build-replay.json');
validateFormalIdentity(root, replay.formalSource);
check(replay.status === 'PASS' && replay.processExit === 0 && replay.admissionDigest === formalAdmissionDigest(replay), 'current clean model execution is missing');
const child = replay.sessions.find(s => s.name === 'TRUST12_Accounting_Obstruction');
check(child?.status === 'PASS' && child.proofExport === 'PASS' && child.oracleDependencies === 0, 'child proof export is incomplete');
const auditPath = 'formal/isabelle/TRUST12_OBSTRUCTIONS/TRUST12_Obstruction_Proof_Audit.thy';
const roots = [...read(root,auditPath).toString('utf8').matchAll(/@\{thms ([A-Za-z0-9_.]+)\}/g)].map(m=>m[1]);
check(roots.length === new Set(roots).size && roots.length === child.explicitRoots, 'proof export and declared root inventory differ');
const groups = {
  statePreservation: ['native_initial_state_wf','ordinary_transfer_preserves_state_wf','authority_rotation_preserves_state_wf',
    'dependency_rebind_preserves_state_wf','failure_preserves_state_wf_and_outcome','forward_preserves_state_wf','reversal_preserves_state_wf'],
  linkedModel: ['model_transaction_step_preserves_state_wf','linked_run_preserves_state_wf','linked_run_every_prefix_preserves_state_wf',
    'all_transaction_outcomes_retained','failure_observation_has_no_success_receipt','applied_model_step_has_receipt'],
  conditionalConnection: ['connected_alpha_transactions_form_linked_run','pinned_runtime_refinement.runtime_linked_run_conditional'],
  linkedPositive: ['linked_applied_then_rejected_control','linked_failure_between_applied_controls','linked_seize_release_new_command_control',
    'shared_custodian_release_control_linked','crossed_supply_two_pops_new_case_linked'],
  linkedNegative: ['state_link_removal_accepts_spliced_steps','outcome_removal_merges_distinct_failures',
    'failure_witness_cannot_leak_success_receipt','applied_post_state_substitution_rejected','failure_post_state_substitution_rejected',
    'malformed_typed_command_substitution_rejected'],
  regulatoryNegative: ['malformed_head_excluded','repeat_restrict_without_guard_breaks_structure',
    'unfreeze_head_pop_removal_breaks_structure','unrestrict_flag_restore_removal_breaks_structure',
    'release_backing_debit_removal_breaks_accounting','wrong_custody_action_is_detected','wrong_custody_holder_is_detected',
    'wrong_custody_amount_is_detected','inactive_amount_clear_removal_is_detected'],
};
for (const [group,names] of Object.entries(groups)) for (const name of names) check(roots.includes(name), `missing audited model theorem: ${group}/${name}`);
const controlPaths = ['formal/isabelle/TRUST12_OBSTRUCTIONS/TRUST_Structure_Invariant_Controls.thy',
  'formal/isabelle/TRUST12_OBSTRUCTIONS/TRUST_State_Interaction_Controls.thy'];
const controls = controlPaths.map(path => {
  const names=[...read(root,path).toString('utf8').matchAll(/^(?:lemma|theorem)\s+([A-Za-z0-9_]+)/gm)].map(m=>m[1]);
  check(names.length > 0 && names.every(name=>roots.includes(name)), `control declaration outside recursive audit: ${path}`);
  return {...fileRef(root,path),theoremDeclarations:names};
});
const result = {schema:'trust12-model-results-v1',status:'PASS_KERNEL_CHECKED_MODEL',provider:replay.provider,
  executionCommit:replay.sourceCommit,formalRootSha256:replay.formalSource.rootSha256,formalAdmissionDigest:replay.admissionDigest,
  proofAudit:{...fileRef(root,auditPath),explicitRoots:child.explicitRoots,qualifiedFacts:child.qualifiedFacts,
    oracleDependencies:child.oracleDependencies,exportSha256:child.exportSha256},groups,controls,
  sourceReviews:{preservation:fileRef(root,'evidence/trust12/model-preservation-audit.md'),
    linkedRun:fileRef(root,'evidence/trust12/linked-controls-audit.md')},
  sourceNormalization:fileRef(root,'evidence/trust12/model-source-normalization.json'),
  scope:'Structural/accounting preservation for nine model actions and connected abstract runs retaining every outcome. Conditional runtime composition is listed separately.',
  nonclaims:{runtimeLinkDischarged:false,constructorStorageDecoded:false,failureCausesComplete:false,reachableStateCharacterization:false,
    evmWordArithmeticRefined:false,allERC3643ImplementationsCovered:false},
  assuranceBoundary:'The source review covers its seven named inputs. Final integration review is a separate recorded review, not implied by the kernel build or theorem counts.'};
if(process.argv.includes('--write')) writeFileSync(resolve(root,'evidence/trust12/model-results.json'),encoded(result));
console.log(JSON.stringify({status:result.status,formalRootSha256:result.formalRootSha256,explicitRoots:child.explicitRoots,
  qualifiedFacts:child.qualifiedFacts,written:process.argv.includes('--write')},null,2));
