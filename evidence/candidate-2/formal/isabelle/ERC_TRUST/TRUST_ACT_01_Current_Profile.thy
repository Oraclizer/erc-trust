theory TRUST_ACT_01_Current_Profile
  imports TRUST_Reusable_Summaries
begin

record act01_package_certificate =
  act01_c0_pass :: bool
  act01_c1_pass :: bool
  act01_c2_pass :: bool
  act01_c3_pass :: bool
  act01_c4_freeze_pass :: bool
  act01_c6_success_pass :: bool
  act01_c6_failure_pass :: bool
  act01_same_entry_negative_pass :: bool
  act01_composition_pass :: bool
  act01_strict_kore_replay_pass :: bool
  act01_booster_used_for_credit :: bool
  act01_assume_defined_used_for_credit :: bool

definition act01_package_certificate_complete ::
  "act01_package_certificate \<Rightarrow> bool"
where
  "act01_package_certificate_complete certificate \<longleftrightarrow>
     act01_c0_pass certificate \<and>
     act01_c1_pass certificate \<and>
     act01_c2_pass certificate \<and>
     act01_c3_pass certificate \<and>
     act01_c4_freeze_pass certificate \<and>
     act01_c6_success_pass certificate \<and>
     act01_c6_failure_pass certificate \<and>
     act01_same_entry_negative_pass certificate \<and>
     act01_composition_pass certificate \<and>
     act01_strict_kore_replay_pass certificate \<and>
     \<not> act01_booster_used_for_credit certificate \<and>
     \<not> act01_assume_defined_used_for_credit certificate"

text \<open>
  This theory is a conditional composition contract. It deliberately contains
  no constructed all-true certificate and grants no row credit. An external
  fail-closed binder must supply hash-bound package, mutation, and strict-Kore
  receipts before instantiating the certificate premise.
\<close>

theorem freeze_success_refines_if_current_profile_receipts_hold:
  assumes "act01_package_certificate_complete certificate"
      and "action_summary_valid summary"
      and "summary_outcome summary = TRUST_Abstract_Applied"
      and "forward_action (summary_command summary) = Legal_Freeze"
  shows "act01_package_certificate_complete certificate \<and>
         frozen_targets (summary_pre_state summary)
           (forward_subject (summary_command summary)) <
         forward_amount (summary_command summary) \<and>
         frozen_targets (summary_post_state summary)
           (forward_subject (summary_command summary)) =
         forward_amount (summary_command summary) \<and>
         summary_stored_receipt_hash summary = summary_returned_receipt_hash summary \<and>
         summary_returned_receipt_hash summary = summary_final_event_receipt_hash summary \<and>
         summary_nonce_consumed summary \<and>
         summary_command_id_consumed summary \<and>
         \<not> summary_route_live summary"
proof -
  have target:
    "frozen_targets (summary_pre_state summary)
       (forward_subject (summary_command summary)) <
     forward_amount (summary_command summary) \<and>
     frozen_targets (summary_post_state summary)
       (forward_subject (summary_command summary)) =
     forward_amount (summary_command summary)"
    using freeze_action_summary_sets_strict_absolute_target assms(2-4) by blast
  have shell:
    "summary_stored_receipt_hash summary = summary_returned_receipt_hash summary \<and>
     summary_returned_receipt_hash summary = summary_final_event_receipt_hash summary \<and>
     summary_nonce_consumed summary \<and>
     summary_command_id_consumed summary \<and>
     \<not> summary_route_live summary"
    using assms(2,3) by (simp add: action_summary_valid_def)
  show ?thesis using assms(1) target shell by blast
qed

definition freeze_target_mutant ::
  "trust_action_summary \<Rightarrow> trust_action_summary"
where
  "freeze_target_mutant summary = summary\<lparr>
     summary_post_state := (summary_post_state summary)\<lparr>
       frozen_targets := (frozen_targets (summary_post_state summary))
         (forward_subject (summary_command summary) :=
           Suc (forward_amount (summary_command summary)))\<rparr>\<rparr>"

theorem unchanged_freeze_claim_kills_target_mutant:
  "frozen_targets (summary_post_state (freeze_target_mutant summary))
      (forward_subject (summary_command summary)) \<noteq>
    forward_amount (summary_command summary)"
  by (simp add: freeze_target_mutant_def)

ML \<open>
  val act01_current_facts = @{thms
    freeze_success_refines_if_current_profile_receipts_hold
    unchanged_freeze_claim_kills_target_mutant};
  val act01_current_oracles = Thm_Deps.all_oracles act01_current_facts;
  val _ = if null act01_current_oracles then ()
    else error ("ACT-01 current-profile proof audit found oracle dependencies");
\<close>

end
