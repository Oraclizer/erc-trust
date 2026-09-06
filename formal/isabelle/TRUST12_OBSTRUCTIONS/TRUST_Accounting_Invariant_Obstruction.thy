(*
  A typed obstruction to promoting the accounting invariant to a regulatory-step
  invariant.  The state below satisfies accounting_state_wf, but carries a
  malformed freeze head that the accounting predicate deliberately does not
  constrain.  A fully admitted FREEZE can therefore separate the custody action
  from its case head.  This is an ill-formed-state counterexample, not a claim
  that the state is reachable from native_initial_state.
*)

theory TRUST_Accounting_Invariant_Obstruction
  imports TRUST_State_Invariants
begin

definition obstruction_binding :: compositional_binding where
  "obstruction_binding =
    \<lparr>binding_endpoint = 0, binding_code_id = 0, binding_configuration = 0,
     binding_schema = 0, binding_epoch = 1, binding_hash = 0\<rparr>"

definition obstruction_seize :: trust_forward_command where
  "obstruction_seize =
    \<lparr>forward_domain = 1, forward_action_id = 1, forward_action = Legal_Seize,
     forward_subject = 1, forward_source = 1, forward_destination = 2,
     forward_custodian = 2, forward_amount = 1, forward_case = 1,
     forward_dependency_root = 0, forward_dependency_epoch = 1,
     forward_provenance_commitment = 1, forward_settlement_commitment = 0,
     forward_proceeds_commitment = 0, forward_entitlement_commitment = 0,
     forward_authority_ref = 1, forward_authority_epoch = 1, forward_nonce = 1,
     forward_valid_after = 0, forward_valid_before = 2\<rparr>"

definition obstruction_freeze :: trust_forward_command where
  "obstruction_freeze = obstruction_seize
    \<lparr>forward_action := Legal_Freeze, forward_action_id := 2, forward_nonce := 2,
     forward_destination := 0, forward_custodian := 0\<rparr>"

definition obstruction_receipt :: "trust_forward_command \<Rightarrow> compositional_receipt" where
  "obstruction_receipt command =
    \<lparr>compositional_receipt_kind = Receipt_Action,
     compositional_command_id = forward_action_id command,
     compositional_command_kind = solidity_action_code (forward_action command),
     compositional_parent_command_id = 0,
     compositional_subject = forward_subject command,
     compositional_source = forward_source command,
     compositional_destination = forward_destination command,
     compositional_amount = forward_amount command,
     compositional_case = forward_case command,
     compositional_authority_ref = forward_authority_ref command,
     compositional_dependency_root = forward_dependency_root command,
     compositional_provenance_commitment = forward_provenance_commitment command,
     compositional_assessment_evidence = 1,
     compositional_pre_observation = 0, compositional_post_observation = 0,
     compositional_external_commitment = forward_external_commitment command,
     compositional_receipt_hash = forward_action_id command\<rparr>"

definition obstruction_witness :: "trust_forward_command \<Rightarrow> trust_success_witness" where
  "obstruction_witness command =
    \<lparr>witness_command_hash = forward_action_id command, witness_evidence_hash = 1,
     witness_receipt = obstruction_receipt command\<rparr>"

definition obstruction_initial :: trust_compositional_state where
  "obstruction_initial =
    native_initial_state 1 1 1 1 (\<lambda>_. obstruction_binding) 0"

definition obstruction_seized :: trust_compositional_state where
  "obstruction_seized = forward_success_state obstruction_initial obstruction_seize
    (obstruction_witness obstruction_seize)"

definition obstruction_state :: trust_compositional_state where
  "obstruction_state = obstruction_seized\<lparr>freeze_heads :=
    (\<lambda>_. empty_head)(1 := \<lparr>head_action = Some 1, head_generation = 1\<rparr>)\<rparr>"

lemmas obstruction_compute =
  obstruction_initial_def native_initial_state_def obstruction_seized_def obstruction_state_def
  obstruction_seize_def obstruction_freeze_def obstruction_witness_def obstruction_receipt_def
  forward_success_state_def base_forward_success_def forward_action_record_def
  opened_custody_def empty_case_def empty_head_def move_balance_def Let_def

theorem accounting_wf_allows_the_malformed_head:
  "accounting_state_wf {1, 2} {1} obstruction_state"
  by (auto simp: accounting_state_wf_def balance_wf_def case_scope_def custody_consistent_def
      active_custody_sum_def custody_case_wf_def open_case_def obstruction_compute)

theorem malformed_head_still_admits_a_freeze:
  "forward_admitted obstruction_state 1 1 obstruction_freeze
    (obstruction_witness obstruction_freeze)"
  by (simp add: forward_admitted_def forward_shape_wf_def forward_fresh_def forward_nonce_key_def
      forward_authorized_def authority_admits_def forward_current_dependency_def forward_in_window_def
      within_window_def receipt_matches_forward_def overlay_shape_def no_disposition_commitments_def
      overlay_admissible_def terminal_case_def forward_external_commitment_def obstruction_compute)

theorem accounting_wf_is_not_preserved_by_every_admitted_forward:
  "\<not> accounting_state_wf {1, 2} {1}
    (forward_success_state obstruction_state obstruction_freeze
      (obstruction_witness obstruction_freeze))"
  by (simp add: accounting_state_wf_def custody_case_wf_def open_case_def
      obstruction_compute opened_overlay_def)

end
