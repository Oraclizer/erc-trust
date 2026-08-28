(*
  ERC-TRUST: explicit relationship between the six RCP actions and the
  seven labels of the inherited regulatory state machine.
*)

theory RCP_Action_Mapping
  imports Regulatory_Execution_Semantics
begin

section \<open>Separate Inventories\<close>

definition all_transition_labels :: "reg_action list" where
  "all_transition_labels =
    [FREEZE, SEIZE, CONFISCATE, RESTRICT, UNFREEZE, UNRESTRICT, RELEASE]"

definition all_rcp_actions :: "legal_action_kind list" where
  "all_rcp_actions =
    [Legal_Freeze, Legal_Seize, Legal_Confiscate, Legal_Restrict,
     Legal_Recover, Legal_Liquidate]"

theorem transition_label_inventory:
  "set all_transition_labels = UNIV \<and>
   distinct all_transition_labels \<and>
   length all_transition_labels = 7"
proof -
  have "set all_transition_labels = UNIV"
  proof (rule set_eqI)
    fix x
    show "x \<in> set all_transition_labels \<longleftrightarrow> x \<in> UNIV"
      by (cases x) (simp_all add: all_transition_labels_def)
  qed
  then show ?thesis by (simp add: all_transition_labels_def)
qed

theorem rcp_action_inventory:
  "set all_rcp_actions = UNIV \<and>
   distinct all_rcp_actions \<and>
   length all_rcp_actions = 6"
proof -
  have "set all_rcp_actions = UNIV"
  proof (rule set_eqI)
    fix x
    show "x \<in> set all_rcp_actions \<longleftrightarrow> x \<in> UNIV"
      by (cases x) (simp_all add: all_rcp_actions_def)
  qed
  then show ?thesis by (simp add: all_rcp_actions_def)
qed

theorem six_actions_are_not_seven_transition_labels:
  "length all_rcp_actions = 6 \<and>
   length all_transition_labels = 7 \<and>
   length all_rcp_actions \<noteq> length all_transition_labels"
  by (simp add: all_rcp_actions_def all_transition_labels_def)

section \<open>Partial Forward Mapping\<close>

fun rcp_action_of_forward_label ::
  "reg_action \<Rightarrow> legal_action_kind option"
where
  "rcp_action_of_forward_label FREEZE = Some Legal_Freeze"
| "rcp_action_of_forward_label SEIZE = Some Legal_Seize"
| "rcp_action_of_forward_label CONFISCATE = Some Legal_Confiscate"
| "rcp_action_of_forward_label RESTRICT = Some Legal_Restrict"
| "rcp_action_of_forward_label UNFREEZE = None"
| "rcp_action_of_forward_label UNRESTRICT = None"
| "rcp_action_of_forward_label RELEASE = None"

theorem four_rcp_actions_have_state_transition_labels:
  "map rcp_transition_label all_rcp_actions =
    [Some FREEZE, Some SEIZE, Some CONFISCATE, Some RESTRICT, None, None]"
  by (simp add: all_rcp_actions_def)

theorem recover_and_liquidate_are_transfer_layer_actions:
  "rcp_transition_label Legal_Recover = None \<and>
   rcp_transition_label Legal_Liquidate = None \<and>
   operation_is_transfer (RCP_Operation Legal_Recover) \<and>
   operation_is_transfer (RCP_Operation Legal_Liquidate)"
  by simp

theorem deescalation_labels_are_not_rcp_actions:
  "rcp_action_of_forward_label UNFREEZE = None \<and>
   rcp_action_of_forward_label UNRESTRICT = None \<and>
   rcp_action_of_forward_label RELEASE = None"
  by simp

theorem forward_mapping_roundtrip:
  assumes "rcp_transition_label k = Some a"
  shows "rcp_action_of_forward_label a = Some k"
  using assms by (cases k; cases a; simp_all)

section \<open>Descriptor and State-Effect Alignment\<close>

theorem rcp_descriptor_alignment:
  assumes "rcp_transition_label k = Some a"
      and "reg_transition s a = Some s'"
  shows "descriptor_target k = Some s'"
proof -
  have "transition_label_of k = Some a"
    using assms(1) by (cases k) simp_all
  then show ?thesis
    using descriptor_transition_compatibility assms(2) by blast
qed

theorem seizure_retains_ownership_descriptor:
  "descriptor_ownership (legal_descriptor Legal_Seize) = Retained \<and>
   descriptor_finality (legal_descriptor Legal_Seize) = Interim_Custodial"
  by simp

theorem liquidation_does_not_prove_debt_discharge:
  "rcp_transition_label Legal_Liquidate = None \<and>
   descriptor_ownership (legal_descriptor Legal_Liquidate) = Terminated"
  by simp

theorem recovery_is_restorative_but_externally_conditioned:
  "rcp_transition_label Legal_Recover = None \<and>
   descriptor_ownership (legal_descriptor Legal_Recover) = Restored \<and>
   external_assumptions_hold (RCP_Operation Legal_Recover) ctx =
     context_entitlement_attested ctx"
  by simp

section \<open>Ordinary and Enforcement Paths Stay Distinct\<close>

theorem ordinary_transfer_never_uses_an_rcp_operation:
  "transfer_allowed s
     \<lparr>transfer_path_value = Ordinary_Transfer,
      baseline_clear = baseline,
      restriction_clear = restriction,
      enforcement_approved = authorization\<rparr> =
   ordinary_transfer_allowed baseline restriction s"
  by (simp add: transfer_allowed_def)

theorem typed_enforcement_uses_separate_gate:
  "transfer_allowed s
     \<lparr>transfer_path_value = Authorized_Enforcement k,
      baseline_clear = baseline,
      restriction_clear = restriction,
      enforcement_approved = authorization\<rparr> =
   (authorization \<and> enforcement_transfer_action k)"
  by (simp add: transfer_allowed_def)

end
