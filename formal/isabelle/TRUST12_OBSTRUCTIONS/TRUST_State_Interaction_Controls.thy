theory TRUST_State_Interaction_Controls
 imports TRUST_Structure_Invariant_Controls
begin

definition sc_initial_100 where
 "sc_initial_100 = native_initial_state 1 100 1 1 (\<lambda>_. obstruction_binding) 0"
definition sc_seize_case where
 "sc_seize_case n amount c = obstruction_seize\<lparr>forward_action_id := n, forward_nonce := n, forward_amount := amount, forward_case := c\<rparr>"
definition sc_custody_first where
 "sc_custody_first = forward_success_state sc_initial_100 (sc_seize_case 1 40 1) (obstruction_witness (sc_seize_case 1 40 1))"
definition sc_custody_two where
 "sc_custody_two = forward_success_state sc_custody_first (sc_seize_case 2 60 2) (obstruction_witness (sc_seize_case 2 60 2))"
definition sc_custody_one_released where
 "sc_custody_one_released = reversal_success_state sc_custody_two (sc_reverse 3 1 TRUST_RELEASE)
   (sc_reversal_witness sc_custody_two (sc_reverse 3 1 TRUST_RELEASE))"
lemmas custody_interaction_compute = sc_initial_100_def sc_seize_case_def sc_custody_first_def
 sc_custody_two_def sc_custody_one_released_def reversal_control_compute

lemma first_shared_custodian_seize_admitted:
 "forward_admitted sc_initial_100 1 1 (sc_seize_case 1 40 1) (obstruction_witness (sc_seize_case 1 40 1))"
 by (simp add: custody_interaction_compute forward_admitted_def forward_shape_wf_def forward_fresh_def forward_nonce_key_def
   forward_authorized_def authority_admits_def forward_current_dependency_def forward_in_window_def within_window_def
   receipt_matches_forward_def transfer_shape_def no_disposition_commitments_def terminal_case_def open_case_def
   unbacked_available_def forward_external_commitment_def)
lemma second_shared_custodian_seize_admitted:
 "forward_admitted sc_custody_first 1 1 (sc_seize_case 2 60 2) (obstruction_witness (sc_seize_case 2 60 2))"
 by (simp add: custody_interaction_compute forward_admitted_def forward_shape_wf_def forward_fresh_def forward_nonce_key_def
   forward_authorized_def authority_admits_def forward_current_dependency_def forward_in_window_def within_window_def
   receipt_matches_forward_def transfer_shape_def no_disposition_commitments_def terminal_case_def open_case_def
   unbacked_available_def forward_external_commitment_def)
lemma one_of_two_custody_releases_admitted:
 "reversal_admitted sc_custody_two 1 1 (sc_reverse 3 1 TRUST_RELEASE) (sc_reversal_witness sc_custody_two (sc_reverse 3 1 TRUST_RELEASE))"
 by (simp add: custody_interaction_compute reversal_control_admission)

theorem shared_custodian_release_control_linked:
 "linked_run sc_initial_100
   [sc_forward_step sc_initial_100 (sc_seize_case 1 40 1), sc_forward_step sc_custody_first (sc_seize_case 2 60 2),
    sc_reverse_step sc_custody_two (sc_reverse 3 1 TRUST_RELEASE)] sc_custody_one_released"
 using forward_control_is_model_step[OF first_shared_custodian_seize_admitted]
   forward_control_is_model_step[OF second_shared_custodian_seize_admitted]
   reversal_control_is_model_step[OF one_of_two_custody_releases_admitted]
 by (simp add: sc_forward_step_def sc_reverse_step_def sc_custody_first_def sc_custody_two_def sc_custody_one_released_def)

theorem shared_custodian_release_preserves_other_case:
 "physical_balances sc_custody_one_released 1 = 40 \<and> physical_balances sc_custody_one_released 2 = 60 \<and>
   custody_backing sc_custody_one_released 2 = 60 \<and>
   map_option custody_active (custody_records sc_custody_one_released 1) = Some False \<and>
   map_option custody_active (custody_records sc_custody_one_released 2) = Some True \<and>
   map_option custody_amount (custody_records sc_custody_one_released 2) = Some 60 \<and>
   map_option custody_action (custody_records sc_custody_one_released 2) = Some (Some 2) \<and>
   abstract_lifecycle (record_at sc_custody_one_released 2) = Record_Applied"
 by (simp add: custody_interaction_compute)

theorem shared_custodian_release_control_wf:
 "\<exists>A C. {1} \<subseteq> A \<and> state_wf A C sc_custody_one_released"
proof -
 have INIT: "state_wf {1} {} sc_initial_100" unfolding sc_initial_100_def by (rule native_initial_state_wf)
 show ?thesis using linked_run_preserves_state_wf[OF INIT shared_custodian_release_control_linked] by blast
qed

definition corrupt_second_custody where
 "corrupt_second_custody transform = sc_custody_one_released\<lparr>custody_records := (custody_records sc_custody_one_released)
   (2 := Some (transform (the (custody_records sc_custody_one_released 2))))\<rparr>"
text \<open>These are invariant-detection fixtures. They are not reachable attacks.\<close>
theorem wrong_custody_action_is_detected:
 "\<not> custody_case_wf (corrupt_second_custody (\<lambda>cu. cu\<lparr>custody_action := Some 1\<rparr>))"
 by (simp add: corrupt_second_custody_def custody_case_wf_def open_case_def custody_interaction_compute; rule exI[where x=2]; simp)
theorem wrong_custody_holder_is_detected:
 "\<not> custody_case_wf (corrupt_second_custody (\<lambda>cu. cu\<lparr>custody_prior_holder := 3\<rparr>))"
 by (simp add: corrupt_second_custody_def custody_case_wf_def open_case_def custody_interaction_compute; rule exI[where x=2]; simp)
theorem wrong_custody_amount_is_detected:
 "\<not> custody_case_wf (corrupt_second_custody (\<lambda>cu. cu\<lparr>custody_amount := 59\<rparr>))"
 by (simp add: corrupt_second_custody_def custody_case_wf_def open_case_def custody_interaction_compute; rule exI[where x=2]; simp)

definition release_without_inactive_zero where
 "release_without_inactive_zero = sc_custody_one_released\<lparr>custody_records := (custody_records sc_custody_one_released)
   (1 := Some ((the (custody_records sc_custody_two 1))\<lparr>custody_active := False\<rparr>))\<rparr>"
theorem inactive_amount_clear_removal_is_detected:
 "\<not> custody_case_wf release_without_inactive_zero"
 by (simp add: release_without_inactive_zero_def custody_case_wf_def open_case_def custody_interaction_compute; rule exI[where x=1]; simp)

theorem ordinary_transfer_to_new_support_control:
 "ordinary_transfer_allowed obstruction_initial 1 3 1 \<and>
   state_wf {1,3} {} (ordinary_transfer_state obstruction_initial 1 3 1) \<and>
   \<not> balance_wf {1} (ordinary_transfer_state obstruction_initial 1 3 1)"
proof -
 have AD: "ordinary_transfer_allowed obstruction_initial 1 3 1"
   by (simp add: ordinary_transfer_allowed_def ordinary_available_def required_floor_def own_frozen_floor_def obstruction_compute)
 have WF: "state_wf {1,3} {} (ordinary_transfer_state obstruction_initial 1 3 1)"
   using ordinary_transfer_preserves_state_wf[OF control_initial_state_wf AD] by (simp add: insert_commute)
 show ?thesis using AD WF by (simp add: balance_wf_def ordinary_transfer_state_def obstruction_compute)
qed

theorem allowed_self_transfer_control:
 "ordinary_transfer_allowed obstruction_initial 1 1 1 \<and> ordinary_transfer_state obstruction_initial 1 1 1 = obstruction_initial"
proof -
 have AD: "ordinary_transfer_allowed obstruction_initial 1 1 1"
   by (simp add: ordinary_transfer_allowed_def ordinary_available_def required_floor_def own_frozen_floor_def obstruction_compute)
 show ?thesis using AD ordinary_self_transfer_stutters[OF AD] by simp
qed

definition sc100_freeze where
 "sc100_freeze n amount c = (sc_freeze n amount)\<lparr>forward_case := c\<rparr>"
definition sc100_first where
 "sc100_first = forward_success_state sc_initial_100 (sc100_freeze 1 60 1) (obstruction_witness (sc100_freeze 1 60 1))"
definition sc100_second where
 "sc100_second = forward_success_state sc100_first (sc100_freeze 2 140 1) (obstruction_witness (sc100_freeze 2 140 1))"
definition sc100_parent where
 "sc100_parent = reversal_success_state sc100_second (sc_reverse 3 2 TRUST_UNFREEZE) (sc_reversal_witness sc100_second (sc_reverse 3 2 TRUST_UNFREEZE))"
definition sc100_clear where
 "sc100_clear = reversal_success_state sc100_parent (sc_reverse 4 1 TRUST_UNFREEZE) (sc_reversal_witness sc100_parent (sc_reverse 4 1 TRUST_UNFREEZE))"
definition sc100_restart where
 "sc100_restart = forward_success_state sc100_clear (sc100_freeze 5 80 5) (obstruction_witness (sc100_freeze 5 80 5))"
lemmas history_interaction_compute = sc100_freeze_def sc100_first_def sc100_second_def sc100_parent_def
 sc100_clear_def sc100_restart_def custody_interaction_compute
lemmas forward_control_admission = forward_admitted_def forward_shape_wf_def forward_fresh_def forward_nonce_key_def
 reversal_nonce_key_def forward_authorized_def authority_admits_def forward_current_dependency_def forward_in_window_def
 within_window_def receipt_matches_forward_def overlay_shape_def no_disposition_commitments_def overlay_admissible_def
 terminal_case_def forward_external_commitment_def

lemma below_supply_freeze_control_admitted:
 "forward_admitted sc_initial_100 1 1 (sc100_freeze 1 60 1) (obstruction_witness (sc100_freeze 1 60 1))"
 by (simp add: forward_control_admission history_interaction_compute)
lemma crossed_supply_freeze_control_admitted:
 "forward_admitted sc100_first 1 1 (sc100_freeze 2 140 1) (obstruction_witness (sc100_freeze 2 140 1))"
 by (simp add: forward_control_admission history_interaction_compute)
lemma crossed_supply_parent_pop_admitted:
 "reversal_admitted sc100_second 1 1 (sc_reverse 3 2 TRUST_UNFREEZE) (sc_reversal_witness sc100_second (sc_reverse 3 2 TRUST_UNFREEZE))"
 by (simp add: reversal_control_admission history_interaction_compute)
lemma crossed_supply_root_pop_admitted:
 "reversal_admitted sc100_parent 1 1 (sc_reverse 4 1 TRUST_UNFREEZE) (sc_reversal_witness sc100_parent (sc_reverse 4 1 TRUST_UNFREEZE))"
 by (simp add: reversal_control_admission history_interaction_compute)
lemma new_case_after_two_pops_admitted:
 "forward_admitted sc100_clear 1 1 (sc100_freeze 5 80 5) (obstruction_witness (sc100_freeze 5 80 5))"
 by (simp add: forward_control_admission history_interaction_compute)

theorem crossed_supply_two_pops_new_case_linked:
 "linked_run sc_initial_100
   [sc_forward_step sc_initial_100 (sc100_freeze 1 60 1), sc_forward_step sc100_first (sc100_freeze 2 140 1),
    sc_reverse_step sc100_second (sc_reverse 3 2 TRUST_UNFREEZE), sc_reverse_step sc100_parent (sc_reverse 4 1 TRUST_UNFREEZE),
    sc_forward_step sc100_clear (sc100_freeze 5 80 5)] sc100_restart"
 using forward_control_is_model_step[OF below_supply_freeze_control_admitted]
   forward_control_is_model_step[OF crossed_supply_freeze_control_admitted]
   reversal_control_is_model_step[OF crossed_supply_parent_pop_admitted]
   reversal_control_is_model_step[OF crossed_supply_root_pop_admitted]
   forward_control_is_model_step[OF new_case_after_two_pops_admitted]
 by (simp add: sc_forward_step_def sc_reverse_step_def sc100_first_def sc100_second_def sc100_parent_def sc100_clear_def sc100_restart_def)

theorem historical_reversed_parent_and_new_head_control:
 "\<exists>A C. state_wf A C sc100_restart"
proof -
 have INIT: "state_wf {1} {} sc_initial_100" unfolding sc_initial_100_def by (rule native_initial_state_wf)
 show ?thesis using linked_run_preserves_state_wf[OF INIT crossed_supply_two_pops_new_case_linked] by blast
qed

theorem historical_parent_lifecycle_and_generation_values:
 "abstract_lifecycle (record_at sc100_restart 1) = Record_Reversed \<and>
   abstract_lifecycle (record_at sc100_restart 2) = Record_Reversed \<and>
   effect_parent (link_at sc100_restart 2) = Some 1 \<and>
   effect_generation (link_at sc100_restart 1) = 1 \<and> head_generation (freeze_heads sc100_restart 1) = 5 \<and>
   frozen_targets sc100_restart 1 = 80 \<and> case_phase (case_records sc100_restart 1) = Case_Terminal \<and>
   case_phase (case_records sc100_restart 5) = Case_Open"
 by (simp add: history_interaction_compute)

definition sc_coexisting_restrict where
 "sc_coexisting_restrict = (sc_restrict 2)\<lparr>forward_case := 2\<rparr>"
definition sc_coexisting where
 "sc_coexisting = forward_success_state sc_one sc_coexisting_restrict (obstruction_witness sc_coexisting_restrict)"
definition sc_coexisting_unrestricted where
 "sc_coexisting_unrestricted = reversal_success_state sc_coexisting (sc_reverse 3 2 TRUST_UNRESTRICT)
   (sc_reversal_witness sc_coexisting (sc_reverse 3 2 TRUST_UNRESTRICT))"
lemmas coexistence_compute = sc_coexisting_restrict_def sc_coexisting_def sc_coexisting_unrestricted_def reversal_control_compute
lemma coexisting_restriction_admitted:
 "forward_admitted sc_one 1 1 sc_coexisting_restrict (obstruction_witness sc_coexisting_restrict)"
 by (simp add: forward_control_admission restrict_would_not_change_state_def coexistence_compute)
lemma coexisting_unrestriction_admitted:
 "reversal_admitted sc_coexisting 1 1 (sc_reverse 3 2 TRUST_UNRESTRICT) (sc_reversal_witness sc_coexisting (sc_reverse 3 2 TRUST_UNRESTRICT))"
 by (simp add: reversal_control_admission coexistence_compute)

theorem restriction_removal_preserves_coexisting_freeze:
 "frozen_targets sc_coexisting_unrestricted 1 = 2 \<and> head_action (freeze_heads sc_coexisting_unrestricted 1) = Some 1 \<and>
   case_phase (case_records sc_coexisting_unrestricted 1) = Case_Open \<and>
   \<not> restriction_flags sc_coexisting_unrestricted 1 \<and> case_phase (case_records sc_coexisting_unrestricted 2) = Case_Terminal"
 by (simp add: coexistence_compute)

theorem repeated_restriction_and_other_case_amendment_rejected:
 "\<not> forward_shape_wf sc_coexisting ((sc_restrict 3)\<lparr>forward_case := 2\<rparr>) \<and>
   \<not> forward_shape_wf sc_coexisting ((sc_freeze 3 3)\<lparr>forward_case := 3\<rparr>)"
 by (simp add: forward_shape_wf_def restrict_would_not_change_state_def overlay_shape_def no_disposition_commitments_def
   overlay_admissible_def terminal_case_def coexistence_compute)


end
