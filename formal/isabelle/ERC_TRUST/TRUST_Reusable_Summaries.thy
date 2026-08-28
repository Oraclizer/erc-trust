theory TRUST_Reusable_Summaries
  imports TRUST_Bound_Dependency_Assume_Guarantee TRUST_Transaction_Refinement
begin

record trust_action_summary =
  summary_pre_state :: trust_compositional_state
  summary_post_state :: trust_compositional_state
  summary_command :: trust_forward_command
  summary_witness :: trust_success_witness
  summary_outcome :: trust_abstract_transaction_outcome
  summary_stored_receipt_hash :: "trust_hash option"
  summary_returned_receipt_hash :: "trust_hash option"
  summary_final_event_receipt_hash :: "trust_hash option"
  summary_committed_log_count :: nat
  summary_nonce_consumed :: bool
  summary_command_id_consumed :: bool
  summary_route_live :: bool

definition action_summary_valid :: "trust_action_summary \<Rightarrow> bool" where
  "action_summary_valid summary \<longleftrightarrow>
    (case summary_outcome summary of
       TRUST_Abstract_Applied \<Rightarrow>
         summary_post_state summary =
           forward_success_state (summary_pre_state summary)
             (summary_command summary) (summary_witness summary) \<and>
         summary_stored_receipt_hash summary =
           Some (compositional_receipt_hash (witness_receipt (summary_witness summary))) \<and>
         summary_returned_receipt_hash summary = summary_stored_receipt_hash summary \<and>
         summary_final_event_receipt_hash summary = summary_stored_receipt_hash summary \<and>
         summary_committed_log_count summary > 0 \<and>
         summary_nonce_consumed summary \<and>
         summary_command_id_consumed summary \<and>
         \<not> summary_route_live summary
     | _ \<Rightarrow>
         summary_post_state summary = summary_pre_state summary \<and>
         summary_stored_receipt_hash summary = None \<and>
         summary_returned_receipt_hash summary = None \<and>
         summary_final_event_receipt_hash summary = None \<and>
         summary_committed_log_count summary = 0 \<and>
         \<not> summary_nonce_consumed summary \<and>
         \<not> summary_command_id_consumed summary \<and>
         \<not> summary_route_live summary)"

record trust_reversal_summary =
  reversal_summary_pre_state :: trust_compositional_state
  reversal_summary_post_state :: trust_compositional_state
  reversal_summary_command :: trust_reversal_command
  reversal_summary_witness :: trust_reversal_witness
  reversal_summary_outcome :: trust_abstract_transaction_outcome
  reversal_summary_receipt_hash :: "trust_hash option"
  reversal_summary_log_count :: nat
  reversal_summary_nonce_consumed :: bool

definition reversal_summary_valid :: "trust_reversal_summary \<Rightarrow> bool" where
  "reversal_summary_valid summary \<longleftrightarrow>
    (case reversal_summary_outcome summary of
       TRUST_Abstract_Applied \<Rightarrow>
         reversal_summary_post_state summary =
           reversal_success_state (reversal_summary_pre_state summary)
             (reversal_summary_command summary) (reversal_summary_witness summary) \<and>
         reversal_summary_receipt_hash summary =
           Some (compositional_receipt_hash
             (reversal_witness_receipt (reversal_summary_witness summary))) \<and>
         reversal_summary_log_count summary > 0 \<and>
         reversal_summary_nonce_consumed summary
     | _ \<Rightarrow>
         reversal_summary_post_state summary = reversal_summary_pre_state summary \<and>
         reversal_summary_receipt_hash summary = None \<and>
         reversal_summary_log_count summary = 0 \<and>
         \<not> reversal_summary_nonce_consumed summary)"

theorem action_summary_success_commits_exact_abstract_state:
  assumes "action_summary_valid summary"
      and "summary_outcome summary = TRUST_Abstract_Applied"
  shows "summary_post_state summary =
         forward_success_state (summary_pre_state summary)
           (summary_command summary) (summary_witness summary)"
  using assms by (simp add: action_summary_valid_def)

theorem action_summary_failure_restores_state_and_authorization:
  assumes "action_summary_valid summary"
      and "summary_outcome summary \<noteq> TRUST_Abstract_Applied"
  shows "summary_post_state summary = summary_pre_state summary \<and>
         summary_committed_log_count summary = 0 \<and>
         \<not> summary_nonce_consumed summary \<and>
         \<not> summary_command_id_consumed summary \<and>
         \<not> summary_route_live summary"
  using assms by (cases "summary_outcome summary")
    (auto simp: action_summary_valid_def)

theorem successful_summary_receipt_storage_return_and_final_event_agree:
  assumes "action_summary_valid summary"
      and "summary_outcome summary = TRUST_Abstract_Applied"
  shows "summary_stored_receipt_hash summary = summary_returned_receipt_hash summary \<and>
         summary_returned_receipt_hash summary = summary_final_event_receipt_hash summary"
  using assms by (simp add: action_summary_valid_def)

theorem freeze_action_summary_sets_absolute_target:
  assumes "action_summary_valid summary"
      and "summary_outcome summary = TRUST_Abstract_Applied"
      and "forward_action (summary_command summary) = Legal_Freeze"
  shows "frozen_targets (summary_post_state summary)
           (forward_subject (summary_command summary)) =
         forward_amount (summary_command summary)"
proof -
  have "summary_post_state summary =
      forward_success_state (summary_pre_state summary)
        (summary_command summary) (summary_witness summary)"
    using action_summary_success_commits_exact_abstract_state assms(1,2) .
  then show ?thesis using assms(3) freeze_success_forward by simp
qed

end
