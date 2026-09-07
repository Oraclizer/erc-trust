theory TRUST_Structure_Invariant_Controls
 imports TRUST_Accounting_Invariant_Obstruction TRUST_Linked_Run
begin

text \<open>Typed model controls. These statements do not decode a deployed constructor or prove a compiled-runtime link.\<close>

definition sc_freeze where
 "sc_freeze n amount = obstruction_freeze\<lparr>forward_action_id := n, forward_nonce := n, forward_amount := amount\<rparr>"
definition sc_one where
 "sc_one = forward_success_state obstruction_initial (sc_freeze 1 2) (obstruction_witness (sc_freeze 1 2))"
lemmas sc_compute = sc_one_def sc_freeze_def obstruction_compute record_at_def link_at_def
 pushed_head_def pushed_link_def opened_overlay_def

theorem first_above_supply_admitted:
 "forward_admitted obstruction_initial 1 1 (sc_freeze 1 2) (obstruction_witness (sc_freeze 1 2))"
 by (simp add: forward_admitted_def forward_shape_wf_def forward_fresh_def forward_nonce_key_def
   forward_authorized_def authority_admits_def forward_current_dependency_def forward_in_window_def
   within_window_def receipt_matches_forward_def overlay_shape_def no_disposition_commitments_def
   overlay_admissible_def terminal_case_def forward_external_commitment_def sc_compute)

theorem first_above_supply_structure:
 "regulatory_structure_wf sc_one"
 by (auto simp: structure_defs sc_compute intro!: exI[where x="[]"])

theorem malformed_head_excluded:
 "\<not> regulatory_structure_wf obstruction_state"
 by (simp add: structure_defs obstruction_compute)

theorem pop_generation_is_not_parent_generation:
 "head_generation (popped_head (pushed_head (pushed_head empty_head 1) 2) (Some 1)) = 3 \<and>
  effect_generation (pushed_link empty_head) = 1"
 by (simp add: empty_head_def pushed_head_def pushed_link_def popped_head_def)

definition forward_shape_without_restrict_guard ::
  "trust_compositional_state \<Rightarrow> trust_forward_command \<Rightarrow> bool"
where
  "forward_shape_without_restrict_guard st command \<longleftrightarrow>
     forward_action_id command \<noteq> 0 \<and>
     forward_subject command \<noteq> 0 \<and>
     forward_case command \<noteq> 0 \<and>
     forward_provenance_commitment command \<noteq> 0 \<and>
     \<not> terminal_case st (forward_case command) \<and>
     (case forward_action command of
        Legal_Freeze \<Rightarrow>
          overlay_shape command \<and> no_disposition_commitments command \<and>
          overlay_admissible (case_records st (forward_case command))
            (freeze_heads st (forward_subject command)) \<and>
          frozen_targets st (forward_subject command) < forward_amount command
      | Legal_Restrict \<Rightarrow>
          overlay_shape command \<and> forward_amount command = 0 \<and>
          no_disposition_commitments command \<and>
          True \<and>
          overlay_admissible (case_records st (forward_case command))
            (restriction_heads st (forward_subject command))
      | Legal_Seize \<Rightarrow>
          transfer_shape command \<and>
          forward_source command = forward_subject command \<and>
          forward_custodian command \<noteq> 0 \<and>
          forward_destination command = forward_custodian command \<and>
          \<not> open_case st (forward_case command) \<and>
          no_disposition_commitments command \<and>
          unbacked_available st (forward_source command) (forward_amount command)
      | Legal_Confiscate \<Rightarrow>
          disposition_wf st command \<and> no_disposition_commitments command
      | Legal_Liquidate \<Rightarrow>
          disposition_wf st command \<and>
          forward_settlement_commitment command \<noteq> 0 \<and>
          forward_proceeds_commitment command \<noteq> 0 \<and>
          forward_entitlement_commitment command = 0
      | Legal_Recover \<Rightarrow>
          disposition_wf st command \<and>
          forward_settlement_commitment command = 0 \<and>
          forward_proceeds_commitment command = 0 \<and>
          forward_entitlement_commitment command \<noteq> 0 \<and>
          forward_entitlement_commitment command \<notin> consumed_entitlements st)"


definition sc_restrict where
 "sc_restrict n = (sc_freeze n 0)\<lparr>forward_action := Legal_Restrict\<rparr>"
definition sc_restricted where
 "sc_restricted = forward_success_state obstruction_initial (sc_restrict 1) (obstruction_witness (sc_restrict 1))"
lemmas restrict_compute = sc_restrict_def sc_restricted_def sc_compute

theorem restrict_first_structure:
 "regulatory_structure_wf sc_restricted"
 by (auto simp: structure_defs restrict_compute)

theorem repeat_restrict_reaches_unguarded_branch:
 "forward_shape_without_restrict_guard sc_restricted (sc_restrict 2) \<and>
  \<not> forward_shape_wf sc_restricted (sc_restrict 2)"
 by (simp add: forward_shape_without_restrict_guard_def forward_shape_wf_def
  restrict_would_not_change_state_def overlay_shape_def no_disposition_commitments_def
  overlay_admissible_def terminal_case_def restrict_compute)

theorem repeat_restrict_without_guard_breaks_structure:
 "\<not> regulatory_structure_wf
  (forward_success_state sc_restricted (sc_restrict 2) (obstruction_witness (sc_restrict 2)))"
 by (simp add: structure_defs restrict_compute)



theorem seize_control_admitted:
 "forward_admitted obstruction_initial 1 1 obstruction_seize (obstruction_witness obstruction_seize)"
 by (simp add: forward_admitted_def forward_shape_wf_def forward_fresh_def forward_nonce_key_def
   forward_authorized_def authority_admits_def forward_current_dependency_def forward_in_window_def
   within_window_def receipt_matches_forward_def transfer_shape_def no_disposition_commitments_def
   terminal_case_def open_case_def unbacked_available_def forward_external_commitment_def obstruction_compute)

theorem seize_control_state_wf:
 "state_wf {1,2} {1} obstruction_seized"
proof -
 have INIT: "state_wf {1} {} obstruction_initial"
   unfolding obstruction_initial_def by (rule native_initial_state_wf)
 note RESULT = seize_preserves_state_wf[OF INIT seize_control_admitted]
 show ?thesis using RESULT
   by (simp add: obstruction_seize_def obstruction_seized_def insert_commute)
qed

lemma control_initial_state_wf:
 "state_wf {1} {} obstruction_initial"
 unfolding obstruction_initial_def by (rule native_initial_state_wf)

theorem freeze_control_state_wf:
 "state_wf {1} {1} sc_one"
proof -
 note R = freeze_preserves_state_wf[OF control_initial_state_wf first_above_supply_admitted]
 show ?thesis using R by (simp add: sc_one_def sc_freeze_def obstruction_freeze_def obstruction_seize_def)
qed

theorem restrict_control_admitted:
 "forward_admitted obstruction_initial 1 1 (sc_restrict 1) (obstruction_witness (sc_restrict 1))"
 by (simp add: forward_admitted_def forward_shape_wf_def forward_fresh_def forward_nonce_key_def
   forward_authorized_def authority_admits_def forward_current_dependency_def forward_in_window_def
   within_window_def receipt_matches_forward_def overlay_shape_def no_disposition_commitments_def
   overlay_admissible_def restrict_would_not_change_state_def terminal_case_def forward_external_commitment_def restrict_compute)

theorem restrict_control_state_wf:
 "state_wf {1} {1} sc_restricted"
proof -
 note R = restrict_preserves_state_wf[OF control_initial_state_wf restrict_control_admitted]
 show ?thesis using R by (simp add: sc_restricted_def sc_restrict_def sc_freeze_def obstruction_freeze_def obstruction_seize_def)
qed

definition disposition_control_command where
 "disposition_control_command kind custody = obstruction_seize\<lparr>forward_action := kind,
   forward_action_id := 3, forward_nonce := 3, forward_source := (if custody then 2 else 1),
   forward_destination := 3, forward_custodian := 0, forward_case := (if custody then 1 else 3),
   forward_settlement_commitment := (if kind = Legal_Liquidate then 1 else 0),
   forward_proceeds_commitment := (if kind = Legal_Liquidate then 1 else 0),
   forward_entitlement_commitment := (if kind = Legal_Recover then 1 else 0)\<rparr>"

lemma disposition_direct_control_admitted:
 assumes KIND: "kind \<in> {Legal_Confiscate,Legal_Liquidate,Legal_Recover}"
 shows "forward_admitted obstruction_initial 1 1 (disposition_control_command kind False)
   (obstruction_witness (disposition_control_command kind False))"
 using KIND by (cases kind; simp add: disposition_control_command_def forward_admitted_def forward_shape_wf_def
   forward_fresh_def forward_nonce_key_def forward_authorized_def authority_admits_def forward_current_dependency_def
   forward_in_window_def within_window_def receipt_matches_forward_def transfer_shape_def no_disposition_commitments_def
   disposition_wf_def terminal_case_def open_case_def unbacked_available_def forward_external_commitment_def obstruction_compute)

lemma disposition_custody_control_admitted:
 assumes KIND: "kind \<in> {Legal_Confiscate,Legal_Liquidate,Legal_Recover}"
 shows "forward_admitted obstruction_seized 1 1 (disposition_control_command kind True)
   (obstruction_witness (disposition_control_command kind True))"
 using KIND by (cases kind; simp add: disposition_control_command_def forward_admitted_def forward_shape_wf_def
   forward_fresh_def forward_nonce_key_def forward_authorized_def authority_admits_def forward_current_dependency_def
   forward_in_window_def within_window_def receipt_matches_forward_def transfer_shape_def no_disposition_commitments_def
   disposition_wf_def custody_matches_def terminal_case_def open_case_def unbacked_available_def forward_external_commitment_def obstruction_compute)

theorem disposition_controls_preserve_state_wf:
 assumes KIND: "kind \<in> {Legal_Confiscate,Legal_Liquidate,Legal_Recover}"
 shows "state_wf {0,1,3} {3} (forward_success_state obstruction_initial (disposition_control_command kind False)
   (obstruction_witness (disposition_control_command kind False)))"
   "state_wf {0,1,2,3} {1} (forward_success_state obstruction_seized (disposition_control_command kind True)
   (obstruction_witness (disposition_control_command kind True)))"
proof -
 note D = disposition_preserves_state_wf[OF control_initial_state_wf disposition_direct_control_admitted[OF KIND]]
 note C = disposition_preserves_state_wf[OF seize_control_state_wf disposition_custody_control_admitted[OF KIND]]
 show "state_wf {0,1,3} {3} (forward_success_state obstruction_initial (disposition_control_command kind False)
   (obstruction_witness (disposition_control_command kind False)))"
   using D KIND by (simp add: disposition_control_command_def obstruction_seize_def insert_commute)
 show "state_wf {0,1,2,3} {1} (forward_success_state obstruction_seized (disposition_control_command kind True)
   (obstruction_witness (disposition_control_command kind True)))"
   using C KIND by (simp add: disposition_control_command_def obstruction_seize_def insert_commute)
qed

definition sc_reverse :: "nat \<Rightarrow> nat \<Rightarrow> trust_reversal_kind \<Rightarrow> trust_reversal_command" where
 "sc_reverse n original kind = \<lparr>reversal_domain = 1, reversal_id = n, reversal_original_action_id = original,
   reversal_kind = kind, reversal_dependency_root = 0, reversal_dependency_epoch = 1,
   reversal_provenance_commitment = 1, reversal_authority_ref = 1, reversal_authority_epoch = 1,
   reversal_nonce = n, reversal_valid_after = 0, reversal_valid_before = 2\<rparr>"

definition sc_reversal_receipt :: "trust_reversal_command \<Rightarrow> compositional_action_record \<Rightarrow> compositional_receipt" where
 "sc_reversal_receipt cmd r = \<lparr>compositional_receipt_kind = Receipt_Reversal,
   compositional_command_id = reversal_id cmd, compositional_command_kind = solidity_reversal_code (reversal_kind cmd),
   compositional_parent_command_id = reversal_original_action_id cmd, compositional_subject = abstract_subject r,
   compositional_source = reversal_receipt_source cmd r, compositional_destination = reversal_receipt_destination cmd r,
   compositional_amount = abstract_amount r, compositional_case = abstract_case r,
   compositional_authority_ref = reversal_authority_ref cmd, compositional_dependency_root = reversal_dependency_root cmd,
   compositional_provenance_commitment = reversal_provenance_commitment cmd, compositional_assessment_evidence = 1,
   compositional_pre_observation = 0, compositional_post_observation = 0, compositional_external_commitment = 0,
   compositional_receipt_hash = reversal_id cmd\<rparr>"

definition sc_reversal_witness where
 "sc_reversal_witness st cmd = \<lparr>reversal_witness_command_hash = reversal_id cmd,
   reversal_witness_evidence_hash = 1, reversal_witness_receipt = sc_reversal_receipt cmd (record_at st (reversal_original_action_id cmd))\<rparr>"

definition sc_unfrozen where
 "sc_unfrozen = reversal_success_state sc_one (sc_reverse 2 1 TRUST_UNFREEZE) (sc_reversal_witness sc_one (sc_reverse 2 1 TRUST_UNFREEZE))"
definition sc_unrestricted where
 "sc_unrestricted = reversal_success_state sc_restricted (sc_reverse 2 1 TRUST_UNRESTRICT) (sc_reversal_witness sc_restricted (sc_reverse 2 1 TRUST_UNRESTRICT))"
definition sc_released where
 "sc_released = reversal_success_state obstruction_seized (sc_reverse 2 1 TRUST_RELEASE) (sc_reversal_witness obstruction_seized (sc_reverse 2 1 TRUST_RELEASE))"
definition sc_two where
 "sc_two = forward_success_state sc_one (sc_freeze 2 3) (obstruction_witness (sc_freeze 2 3))"
definition sc_parent_restored where
 "sc_parent_restored = reversal_success_state sc_two (sc_reverse 3 2 TRUST_UNFREEZE) (sc_reversal_witness sc_two (sc_reverse 3 2 TRUST_UNFREEZE))"

lemmas reversal_control_compute = sc_reverse_def sc_reversal_receipt_def sc_reversal_witness_def
 sc_unfrozen_def sc_unrestricted_def sc_released_def sc_two_def sc_parent_restored_def restrict_compute
 reversal_success_state_def reversal_original_def link_parent_def popped_head_def reopened_or_closed_def
 closed_case_def close_custody_def reversal_receipt_source_def reversal_receipt_destination_def
lemmas reversal_control_admission = reversal_admitted_def reversal_admissible_def reversal_pairs_def reversal_current_effect_def
 forward_nonce_key_def reversal_fresh_def reversal_nonce_key_def reversal_authorized_def authority_admits_def reversal_current_dependency_def
 reversal_in_window_def within_window_def receipt_matches_reversal_def terminal_case_def

theorem unfreeze_root_control_admitted:
 "reversal_admitted sc_one 1 1 (sc_reverse 2 1 TRUST_UNFREEZE) (sc_reversal_witness sc_one (sc_reverse 2 1 TRUST_UNFREEZE))"
 by (simp add: reversal_control_admission reversal_control_compute)

theorem unrestrict_control_admitted:
 "reversal_admitted sc_restricted 1 1 (sc_reverse 2 1 TRUST_UNRESTRICT) (sc_reversal_witness sc_restricted (sc_reverse 2 1 TRUST_UNRESTRICT))"
 by (simp add: reversal_control_admission reversal_control_compute)

theorem release_control_admitted:
 "reversal_admitted obstruction_seized 1 1 (sc_reverse 2 1 TRUST_RELEASE) (sc_reversal_witness obstruction_seized (sc_reverse 2 1 TRUST_RELEASE))"
 by (simp add: reversal_control_admission reversal_control_compute)

theorem second_above_supply_control_admitted:
 "forward_admitted sc_one 1 1 (sc_freeze 2 3) (obstruction_witness (sc_freeze 2 3))"
 by (simp add: forward_admitted_def forward_shape_wf_def forward_fresh_def forward_nonce_key_def forward_authorized_def
   authority_admits_def forward_current_dependency_def forward_in_window_def within_window_def receipt_matches_forward_def
   overlay_shape_def no_disposition_commitments_def overlay_admissible_def terminal_case_def forward_external_commitment_def sc_compute)

theorem unfreeze_parent_control_admitted:
 "reversal_admitted sc_two 1 1 (sc_reverse 3 2 TRUST_UNFREEZE) (sc_reversal_witness sc_two (sc_reverse 3 2 TRUST_UNFREEZE))"
 by (simp add: reversal_control_admission reversal_control_compute)

theorem nonhead_freeze_control_rejected:
 "\<not> reversal_admissible sc_two (sc_reverse 3 1 TRUST_UNFREEZE)"
 by (simp add: reversal_control_admission reversal_control_compute)

theorem reversal_controls_preserve_state_wf:
 "state_wf {1} {1} sc_unfrozen" "state_wf {1} {1} sc_unrestricted" "state_wf {1,2} {1} sc_released"
proof -
 show "state_wf {1} {1} sc_unfrozen"
   using unfreeze_preserves_state_wf[OF freeze_control_state_wf unfreeze_root_control_admitted]
   by (simp add: sc_reverse_def sc_unfrozen_def)
 show "state_wf {1} {1} sc_unrestricted"
   using unrestrict_preserves_state_wf[OF restrict_control_state_wf unrestrict_control_admitted]
   by (simp add: sc_reverse_def sc_unrestricted_def)
 show "state_wf {1,2} {1} sc_released"
   using release_preserves_state_wf[OF seize_control_state_wf release_control_admitted]
   by (simp add: sc_reverse_def sc_released_def record_at_def obstruction_compute insert_commute)
qed

theorem parent_restoration_control_state_wf:
 "state_wf {1} {1} sc_parent_restored"
proof -
 have TWO: "state_wf {1} {1} sc_two"
   using freeze_preserves_state_wf[OF freeze_control_state_wf second_above_supply_control_admitted]
   by (simp add: sc_two_def sc_freeze_def obstruction_freeze_def obstruction_seize_def)
 show ?thesis using unfreeze_preserves_state_wf[OF TWO unfreeze_parent_control_admitted]
   by (simp add: sc_reverse_def sc_parent_restored_def)
qed

theorem parent_restoration_control_values:
 "head_action (freeze_heads sc_parent_restored 1) = Some 1 \<and> head_generation (freeze_heads sc_parent_restored 1) = 3 \<and>
   effect_generation (link_at sc_parent_restored 1) = 1 \<and> frozen_targets sc_parent_restored 1 = 2 \<and>
   case_head (case_records sc_parent_restored 1) = Some 1 \<and> case_phase (case_records sc_parent_restored 1) = Case_Open"
 by (simp add: reversal_control_compute)

theorem released_control_values:
 "physical_balances sc_released 1 = 1 \<and> physical_balances sc_released 2 = 0 \<and> custody_backing sc_released 2 = 0 \<and>
   map_option custody_active (custody_records sc_released 1) = Some False \<and>
   map_option custody_amount (custody_records sc_released 1) = Some 0 \<and>
   abstract_lifecycle (record_at sc_released 1) = Record_Reversed"
 by (simp add: reversal_control_compute)

definition unfreeze_without_head_pop where
 "unfreeze_without_head_pop st cmd w = (reversal_success_state st cmd w)\<lparr>freeze_heads := freeze_heads st\<rparr>"
definition unrestrict_without_flag_restore where
 "unrestrict_without_flag_restore st cmd w = (reversal_success_state st cmd w)\<lparr>restriction_flags := restriction_flags st\<rparr>"
definition release_without_backing_debit where
 "release_without_backing_debit st cmd w = (reversal_success_state st cmd w)\<lparr>custody_backing := custody_backing st\<rparr>"

theorem unfreeze_head_pop_removal_breaks_structure:
 "\<not> regulatory_structure_wf (unfreeze_without_head_pop sc_one (sc_reverse 2 1 TRUST_UNFREEZE)
   (sc_reversal_witness sc_one (sc_reverse 2 1 TRUST_UNFREEZE)))"
 by (simp add: unfreeze_without_head_pop_def structure_defs reversal_control_compute)

theorem unrestrict_flag_restore_removal_breaks_structure:
 "\<not> regulatory_structure_wf (unrestrict_without_flag_restore sc_restricted (sc_reverse 2 1 TRUST_UNRESTRICT)
   (sc_reversal_witness sc_restricted (sc_reverse 2 1 TRUST_UNRESTRICT)))"
 by (simp add: unrestrict_without_flag_restore_def structure_defs reversal_control_compute)

theorem release_backing_debit_removal_breaks_accounting:
 "\<not> accounting_state_wf {1,2} {1} (release_without_backing_debit obstruction_seized (sc_reverse 2 1 TRUST_RELEASE)
   (sc_reversal_witness obstruction_seized (sc_reverse 2 1 TRUST_RELEASE)))"
 by (simp add: release_without_backing_debit_def accounting_state_wf_def custody_consistent_def
   active_custody_sum_def reversal_control_compute)


definition sc_forward_step :: "trust_compositional_state \<Rightarrow> trust_forward_command \<Rightarrow> trust_transaction_abstraction" where
 "sc_forward_step st cmd = \<lparr>abstraction_pre_state = st,
   abstraction_post_state = forward_success_state st cmd (obstruction_witness cmd),
   abstraction_sender = 1, abstraction_time = 1, abstraction_command = Some (TRUST_Forward cmd),
   abstraction_outcome = TRUST_Abstract_Applied, abstraction_forward_witness = Some (obstruction_witness cmd),
   abstraction_reversal_witness = None, abstraction_effect_logs = []\<rparr>"
definition sc_reverse_step :: "trust_compositional_state \<Rightarrow> trust_reversal_command \<Rightarrow> trust_transaction_abstraction" where
 "sc_reverse_step st cmd = \<lparr>abstraction_pre_state = st,
   abstraction_post_state = reversal_success_state st cmd (sc_reversal_witness st cmd),
   abstraction_sender = 1, abstraction_time = 1, abstraction_command = Some (TRUST_Reverse cmd),
   abstraction_outcome = TRUST_Abstract_Applied, abstraction_forward_witness = None,
   abstraction_reversal_witness = Some (sc_reversal_witness st cmd), abstraction_effect_logs = []\<rparr>"
definition sc_failure_step where
 "sc_failure_step st cmd outcome = (sc_forward_step st cmd)\<lparr>abstraction_post_state := st, abstraction_outcome := outcome\<rparr>"
definition sc_malformed_step where
 "sc_malformed_step st cmd = (sc_failure_step st cmd TRUST_Abstract_Malformed)\<lparr>abstraction_command := None\<rparr>"

lemma forward_control_is_model_step:
 assumes "forward_admitted st 1 1 cmd (obstruction_witness cmd)"
 shows "model_transaction_step (sc_forward_step st cmd)"
 using assms by (simp add: sc_forward_step_def model_transaction_step_def expected_success_state_def)
lemma reversal_control_is_model_step:
 assumes "reversal_admitted st 1 1 cmd (sc_reversal_witness st cmd)"
 shows "model_transaction_step (sc_reverse_step st cmd)"
 using assms by (simp add: sc_reverse_step_def model_transaction_step_def expected_success_state_def)
lemma failure_control_is_model_step:
 assumes "outcome \<in> {TRUST_Abstract_Rejected,TRUST_Abstract_Operational,TRUST_Abstract_Dependency_Revert}"
 shows "model_transaction_step (sc_failure_step st cmd outcome)"
 using assms by (auto simp: sc_failure_step_def sc_forward_step_def model_transaction_step_def)

lemma freeze_control_changes_state:
 "sc_one \<noteq> obstruction_initial"
proof -
 have TARGET: "frozen_targets sc_one 1 = 2" and ZERO: "frozen_targets obstruction_initial 1 = 0"
   by (simp add: sc_compute)+
 show ?thesis
 proof
   assume SAME: "sc_one = obstruction_initial"
   have "(2::nat) = 0" using TARGET ZERO SAME by simp
   then show False by simp
 qed
qed

theorem linked_applied_then_rejected_control:
 "linked_run obstruction_initial
   [sc_forward_step obstruction_initial (sc_freeze 1 2), sc_failure_step sc_one (sc_freeze 1 2) TRUST_Abstract_Rejected] sc_one"
 using forward_control_is_model_step[OF first_above_supply_admitted]
   failure_control_is_model_step[of TRUST_Abstract_Rejected sc_one "sc_freeze 1 2"]
 by (simp add: sc_forward_step_def sc_failure_step_def sc_one_def)

theorem rejected_repeat_control_is_not_admitted:
 "\<not> forward_admitted sc_one 1 1 (sc_freeze 1 2) (obstruction_witness (sc_freeze 1 2))"
 using successful_action_is_not_fresh_afterwards[of obstruction_initial "sc_freeze 1 2" "obstruction_witness (sc_freeze 1 2)"]
 by (auto simp: sc_one_def forward_admitted_def)

theorem linked_failure_between_applied_controls:
 "linked_run obstruction_initial
   [sc_forward_step obstruction_initial (sc_freeze 1 2), sc_failure_step sc_one (sc_freeze 1 2) TRUST_Abstract_Operational,
    sc_forward_step sc_one (sc_freeze 2 3)] sc_two"
 using forward_control_is_model_step[OF first_above_supply_admitted]
   forward_control_is_model_step[OF second_above_supply_control_admitted]
   failure_control_is_model_step[of TRUST_Abstract_Operational sc_one "sc_freeze 1 2"]
 by (simp add: sc_forward_step_def sc_failure_step_def sc_one_def sc_two_def)

definition sc_after_release_command where
 "sc_after_release_command = (sc_freeze 3 2)\<lparr>forward_case := 3\<rparr>"
definition sc_after_release where
 "sc_after_release = forward_success_state sc_released sc_after_release_command (obstruction_witness sc_after_release_command)"

theorem after_release_new_command_admitted:
 "forward_admitted sc_released 1 1 sc_after_release_command (obstruction_witness sc_after_release_command)"
 by (simp add: sc_after_release_command_def forward_admitted_def forward_shape_wf_def forward_fresh_def forward_nonce_key_def
   reversal_nonce_key_def forward_authorized_def authority_admits_def forward_current_dependency_def forward_in_window_def
   within_window_def receipt_matches_forward_def overlay_shape_def no_disposition_commitments_def overlay_admissible_def
   terminal_case_def forward_external_commitment_def reversal_control_compute)

theorem linked_seize_release_new_command_control:
 "linked_run obstruction_initial
   [sc_forward_step obstruction_initial obstruction_seize, sc_reverse_step obstruction_seized (sc_reverse 2 1 TRUST_RELEASE),
    sc_forward_step sc_released sc_after_release_command] sc_after_release"
 using forward_control_is_model_step[OF seize_control_admitted]
   reversal_control_is_model_step[OF release_control_admitted]
   forward_control_is_model_step[OF after_release_new_command_admitted]
 by (simp add: sc_forward_step_def sc_reverse_step_def obstruction_seized_def sc_released_def sc_after_release_def)

fun unlinked_run :: "trust_compositional_state \<Rightarrow> trust_transaction_abstraction list \<Rightarrow> trust_compositional_state \<Rightarrow> bool" where
 "unlinked_run start [] final = (start = final)"
| "unlinked_run start (a # rest) final = (model_transaction_step a \<and> unlinked_run (abstraction_post_state a) rest final)"

text \<open>The next mutant removes only the pre-state equality from linked_run.
  The resulting splice is not a connected execution, even though its separate
  steps can each preserve state_wf. This is a connection counterexample.\<close>
theorem state_link_removal_accepts_spliced_steps:
 "unlinked_run obstruction_initial
   [sc_forward_step obstruction_initial (sc_freeze 1 2), sc_forward_step obstruction_initial (sc_restrict 1)] sc_restricted \<and>
  \<not> linked_run obstruction_initial
   [sc_forward_step obstruction_initial (sc_freeze 1 2), sc_forward_step obstruction_initial (sc_restrict 1)] sc_restricted"
 using forward_control_is_model_step[OF first_above_supply_admitted] forward_control_is_model_step[OF restrict_control_admitted]
   freeze_control_changes_state
 by (simp add: sc_forward_step_def sc_one_def sc_restricted_def)

definition step_observation_without_outcome where
 "step_observation_without_outcome a = (fst (step_observation a), snd (snd (step_observation a)))"

theorem outcome_removal_merges_distinct_failures:
 "step_observation (sc_failure_step sc_one (sc_freeze 1 2) TRUST_Abstract_Rejected) \<noteq>
    step_observation (sc_failure_step sc_one (sc_freeze 1 2) TRUST_Abstract_Operational) \<and>
   step_observation_without_outcome (sc_failure_step sc_one (sc_freeze 1 2) TRUST_Abstract_Rejected) =
    step_observation_without_outcome (sc_failure_step sc_one (sc_freeze 1 2) TRUST_Abstract_Operational)"
 by (simp add: step_observation_without_outcome_def step_observation_def sc_failure_step_def sc_forward_step_def)

theorem failure_witness_cannot_leak_success_receipt:
 "abstraction_receipt (sc_failure_step st cmd TRUST_Abstract_Rejected) = Some (obstruction_receipt cmd) \<and>
   snd (snd (step_observation (sc_failure_step st cmd TRUST_Abstract_Rejected))) = None"
 by (simp add: abstraction_receipt_def sc_failure_step_def sc_forward_step_def obstruction_witness_def step_observation_def)

theorem applied_post_state_substitution_rejected:
 "\<not> model_transaction_step ((sc_forward_step obstruction_initial (sc_freeze 1 2))\<lparr>abstraction_post_state := obstruction_initial\<rparr>)"
 using first_above_supply_admitted freeze_control_changes_state
 by (simp add: sc_forward_step_def model_transaction_step_def expected_success_state_def sc_one_def)

theorem failure_post_state_substitution_rejected:
 "\<not> model_transaction_step ((sc_failure_step obstruction_initial (sc_freeze 1 2) TRUST_Abstract_Rejected)\<lparr>abstraction_post_state := sc_one\<rparr>)"
 using freeze_control_changes_state by (simp add: sc_failure_step_def sc_forward_step_def model_transaction_step_def)

theorem malformed_typed_command_substitution_rejected:
 "model_transaction_step (sc_malformed_step st cmd) \<and>
   \<not> model_transaction_step (sc_failure_step st cmd TRUST_Abstract_Malformed)"
 by (simp add: sc_malformed_step_def sc_failure_step_def sc_forward_step_def model_transaction_step_def)

theorem all_failure_kinds_remain_in_order:
 "map (\<lambda>x. fst (snd x)) (run_observations
   [sc_failure_step st cmd TRUST_Abstract_Rejected, sc_failure_step st cmd TRUST_Abstract_Operational,
    sc_malformed_step st cmd, sc_failure_step st cmd TRUST_Abstract_Dependency_Revert]) =
   [TRUST_Abstract_Rejected, TRUST_Abstract_Operational, TRUST_Abstract_Malformed, TRUST_Abstract_Dependency_Revert]"
 by (simp add: run_observations_def step_observation_def sc_failure_step_def sc_forward_step_def sc_malformed_step_def)


end
