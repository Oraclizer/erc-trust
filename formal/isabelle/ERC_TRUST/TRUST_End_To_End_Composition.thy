(*
  Conditional heterogeneous composition of Isabelle and KEVM results.

  Everything inside the locale pinned_runtime_refinement is proved under its
  assumptions.  The assumption runtime_link is the reflection direction of
  the refinement: that every execution of the pinned runtime the external
  checker accepts abstracts to a transaction the Isabelle model admits.  This
  session discharges that assumption nowhere; it is recorded as an open
  assumption in the central refinement closure artifact, and the claim
  ladder stops at mapped implementation evidence until it is discharged.
*)

theory TRUST_End_To_End_Composition
  imports TRUST_Transaction_Refinement
begin

record trust_external_assumptions =
  dependency_target_bound :: bool
  dependency_code_bound :: bool
  dependency_configuration_bound :: bool
  dependency_schema_bound :: bool
  dependency_epoch_bound :: bool
  dependency_input_bound :: bool
  dependency_staticcall_only :: bool
  dependency_gas_sufficient :: bool
  malformed_returndata_is_operational :: bool
  ticket_exact_selector_and_calldata :: bool
  ticket_exact_root_and_epoch :: bool
  ticket_single_use_and_deleted :: bool
  verified_profile_token_sealed :: bool
  verified_profile_agent_exclusive :: bool
  verified_profile_identity_bound :: bool
  verified_profile_compliance_bound :: bool
  verified_profile_owner_governor :: bool
  verified_profile_custodian_confined :: bool
  verified_profile_upstream_state_owned :: bool
  verified_profile_import_manifest_exact :: bool

definition external_assumptions_complete :: "trust_external_assumptions \<Rightarrow> bool" where
  "external_assumptions_complete assumptions \<longleftrightarrow>
     dependency_target_bound assumptions \<and>
     dependency_code_bound assumptions \<and>
     dependency_configuration_bound assumptions \<and>
     dependency_schema_bound assumptions \<and>
     dependency_epoch_bound assumptions \<and>
     dependency_input_bound assumptions \<and>
     dependency_staticcall_only assumptions \<and>
     dependency_gas_sufficient assumptions \<and>
     malformed_returndata_is_operational assumptions \<and>
     ticket_exact_selector_and_calldata assumptions \<and>
     ticket_exact_root_and_epoch assumptions \<and>
     ticket_single_use_and_deleted assumptions \<and>
     verified_profile_token_sealed assumptions \<and>
     verified_profile_agent_exclusive assumptions \<and>
     verified_profile_identity_bound assumptions \<and>
     verified_profile_compliance_bound assumptions \<and>
     verified_profile_owner_governor assumptions \<and>
     verified_profile_custodian_confined assumptions \<and>
     verified_profile_upstream_state_owned assumptions \<and>
     verified_profile_import_manifest_exact assumptions"

record trust_runtime_certificate =
  certificate_bridge_schema_sha256 :: string
  certificate_runtime_template_sha256 :: string
  certificate_semantics_commit :: string
  certificate_schedule :: string
  certificate_booster_disabled :: bool
  certificate_no_pending_goals :: bool

definition approved_kevm_semantics_commit :: string where
  "approved_kevm_semantics_commit =
     ''d4bf484a5dfe1e38d729a30434cd6f41e3590fb2''"

definition approved_evm_schedule :: string where
  "approved_evm_schedule = ''CANCUN''"

definition runtime_certificate_complete :: "trust_runtime_certificate \<Rightarrow> bool" where
  "runtime_certificate_complete certificate \<longleftrightarrow>
     certificate_bridge_schema_sha256 certificate = runtime_bridge_schema_sha256 \<and>
     certificate_runtime_template_sha256 certificate = native_runtime_template_sha256 \<and>
     certificate_semantics_commit certificate = approved_kevm_semantics_commit \<and>
     certificate_schedule certificate = approved_evm_schedule \<and>
     certificate_booster_disabled certificate \<and>
     certificate_no_pending_goals certificate"

record trust_exact_tcb =
  tcb_isabelle :: string
  tcb_kevm_commit :: string
  tcb_k_commit :: string
  tcb_kore_commit :: string
  tcb_z3_version :: string
  tcb_solc_version :: string
  tcb_solc_correctness_claimed :: bool

definition approved_exact_tcb :: trust_exact_tcb where
  "approved_exact_tcb =
     \<lparr>tcb_isabelle = ''Isabelle2025-2'',
      tcb_kevm_commit = ''d4bf484a5dfe1e38d729a30434cd6f41e3590fb2'',
      tcb_k_commit = ''4a46d1231473b599c699160132fd6e76a5c46406'',
      tcb_kore_commit = ''38afc81fc9414f1e11e609b01a43a436b613bd2d'',
      tcb_z3_version = ''4.13.4'',
      tcb_solc_version = ''0.8.36+commit.8a079791'',
      tcb_solc_correctness_claimed = False\<rparr>"

theorem compiler_correctness_remains_a_nonclaim:
  "\<not> tcb_solc_correctness_claimed approved_exact_tcb"
  by (simp add: approved_exact_tcb_def)

text \<open>
  The locale assumes exactly what its theorems use: the runtime link.  The
  runtime certificate and the external assumptions are recorded by the
  definitions above and by the central refinement closure artifact; they are
  not hypotheses of any theorem in this locale, and listing them here would
  suggest a dependence that does not exist.
\<close>

locale pinned_runtime_refinement =
  fixes manifest :: trust_runtime_manifest
    and bridge :: trust_transaction_bridge
    and runtime_execution :: "trust_transaction_execution \<Rightarrow> bool"
    and runtime_abstraction :: "trust_transaction_execution \<Rightarrow> trust_transaction_abstraction"
  assumes runtime_link:
        "runtime_execution execution \<Longrightarrow>
         alpha_transaction manifest bridge execution (runtime_abstraction execution)"
begin

theorem runtime_execution_implements_concrete_transaction:
  assumes "runtime_execution execution"
  shows "alpha_transaction manifest bridge execution (runtime_abstraction execution)"
  using assms runtime_link by blast

lemma forward_runtime_state:
  assumes "runtime_execution execution"
      and "abstraction_outcome (runtime_abstraction execution) = TRUST_Abstract_Applied"
      and "abstraction_command (runtime_abstraction execution) = Some (TRUST_Forward command)"
      and "abstraction_forward_witness (runtime_abstraction execution) = Some witness"
      and "abstraction_reversal_witness (runtime_abstraction execution) = None"
  shows "abstraction_post_state (runtime_abstraction execution) =
         forward_success_state (abstraction_pre_state (runtime_abstraction execution))
           command witness \<and>
         forward_admitted (abstraction_pre_state (runtime_abstraction execution))
           (transaction_sender execution) (transaction_time execution) command witness"
proof -
  have alpha:
    "alpha_transaction manifest bridge execution (runtime_abstraction execution)"
    using assms(1) runtime_link by blast
  have expected:
    "expected_success_state (runtime_abstraction execution) =
       Some (abstraction_post_state (runtime_abstraction execution))"
    using alpha assms(2) successful_transaction_uses_abstract_success_state by blast
  have admitted:
    "forward_admitted (abstraction_pre_state (runtime_abstraction execution))
       (transaction_sender execution) (transaction_time execution) command witness"
    using successful_forward_transaction_is_admitted[OF alpha assms(2-5)] .
  have sender: "abstraction_sender (runtime_abstraction execution) = transaction_sender execution"
    and time: "abstraction_time (runtime_abstraction execution) = transaction_time execution"
    using alpha by (simp_all add: alpha_transaction_def)
  show ?thesis using expected assms(3-5) admitted sender time
    by (simp add: expected_success_state_def)
qed

lemma reversal_runtime_state:
  assumes "runtime_execution execution"
      and "abstraction_outcome (runtime_abstraction execution) = TRUST_Abstract_Applied"
      and "abstraction_command (runtime_abstraction execution) = Some (TRUST_Reverse command)"
      and "abstraction_forward_witness (runtime_abstraction execution) = None"
      and "abstraction_reversal_witness (runtime_abstraction execution) = Some witness"
  shows "abstraction_post_state (runtime_abstraction execution) =
         reversal_success_state (abstraction_pre_state (runtime_abstraction execution))
           command witness \<and>
         reversal_admitted (abstraction_pre_state (runtime_abstraction execution))
           (transaction_sender execution) (transaction_time execution) command witness"
proof -
  have alpha:
    "alpha_transaction manifest bridge execution (runtime_abstraction execution)"
    using assms(1) runtime_link by blast
  have expected:
    "expected_success_state (runtime_abstraction execution) =
       Some (abstraction_post_state (runtime_abstraction execution))"
    using alpha assms(2) successful_transaction_uses_abstract_success_state by blast
  have admitted:
    "reversal_admitted (abstraction_pre_state (runtime_abstraction execution))
       (transaction_sender execution) (transaction_time execution) command witness"
    using successful_reversal_transaction_is_admitted[OF alpha assms(2-5)] .
  have sender: "abstraction_sender (runtime_abstraction execution) = transaction_sender execution"
    and time: "abstraction_time (runtime_abstraction execution) = transaction_time execution"
    using alpha by (simp_all add: alpha_transaction_def)
  show ?thesis using expected assms(3-5) admitted sender time
    by (simp add: expected_success_state_def)
qed

theorem freeze_success_refines:
  assumes "runtime_execution execution"
      and "abstraction_outcome (runtime_abstraction execution) = TRUST_Abstract_Applied"
      and "abstraction_command (runtime_abstraction execution) = Some (TRUST_Forward command)"
      and "abstraction_forward_witness (runtime_abstraction execution) = Some witness"
      and "abstraction_reversal_witness (runtime_abstraction execution) = None"
      and "forward_action command = Legal_Freeze"
  shows "frozen_targets (abstraction_post_state (runtime_abstraction execution))
           (forward_subject command) = forward_amount command \<and>
         frozen_targets (abstraction_pre_state (runtime_abstraction execution))
           (forward_subject command) < forward_amount command"
  using forward_runtime_state[OF assms(1-5)] freeze_success_sets_absolute_target[OF assms(6)]
    freeze_success_requires_strict_increase[OF _ assms(6)]
  by (simp add: forward_admitted_def)

theorem seize_success_refines:
  assumes "runtime_execution execution"
      and "abstraction_outcome (runtime_abstraction execution) = TRUST_Abstract_Applied"
      and "abstraction_command (runtime_abstraction execution) = Some (TRUST_Forward command)"
      and "abstraction_forward_witness (runtime_abstraction execution) = Some witness"
      and "abstraction_reversal_witness (runtime_abstraction execution) = None"
      and "forward_action command = Legal_Seize"
      and "forward_source command \<noteq> forward_custodian command"
  shows "custody_backing (abstraction_post_state (runtime_abstraction execution))
           (forward_custodian command) =
         custody_backing (abstraction_pre_state (runtime_abstraction execution))
           (forward_custodian command) + forward_amount command"
  using forward_runtime_state[OF assms(1-5)] seize_success_opens_custody[OF assms(6,7)]
  by simp

theorem confiscate_success_refines:
  assumes "runtime_execution execution"
      and "abstraction_outcome (runtime_abstraction execution) = TRUST_Abstract_Applied"
      and "abstraction_command (runtime_abstraction execution) = Some (TRUST_Forward command)"
      and "abstraction_forward_witness (runtime_abstraction execution) = Some witness"
      and "abstraction_reversal_witness (runtime_abstraction execution) = None"
      and "forward_action command = Legal_Confiscate"
  shows "terminal_case (abstraction_post_state (runtime_abstraction execution))
           (forward_case command)"
  using forward_runtime_state[OF assms(1-5)] confiscate_success_is_terminal[OF assms(6)]
  by simp

theorem liquidate_success_refines:
  assumes "runtime_execution execution"
      and "abstraction_outcome (runtime_abstraction execution) = TRUST_Abstract_Applied"
      and "abstraction_command (runtime_abstraction execution) = Some (TRUST_Forward command)"
      and "abstraction_forward_witness (runtime_abstraction execution) = Some witness"
      and "abstraction_reversal_witness (runtime_abstraction execution) = None"
      and "forward_action command = Legal_Liquidate"
  shows "terminal_case (abstraction_post_state (runtime_abstraction execution))
           (forward_case command) \<and>
         compositional_external_commitment (witness_receipt witness) =
           settlement_pair_commitment (forward_settlement_commitment command)
             (forward_proceeds_commitment command)"
  using forward_runtime_state[OF assms(1-5)] liquidate_success_is_terminal[OF assms(6)]
    liquidate_success_binds_settlement_in_receipt[OF assms(6)]
  by (simp add: forward_admitted_def)

theorem restrict_success_refines:
  assumes "runtime_execution execution"
      and "abstraction_outcome (runtime_abstraction execution) = TRUST_Abstract_Applied"
      and "abstraction_command (runtime_abstraction execution) = Some (TRUST_Forward command)"
      and "abstraction_forward_witness (runtime_abstraction execution) = Some witness"
      and "abstraction_reversal_witness (runtime_abstraction execution) = None"
      and "forward_action command = Legal_Restrict"
  shows "restriction_flags (abstraction_post_state (runtime_abstraction execution))
           (forward_subject command)"
  using forward_runtime_state[OF assms(1-5)] restrict_success_sets_flag[OF assms(6)]
  by simp

theorem recover_success_refines:
  assumes "runtime_execution execution"
      and "abstraction_outcome (runtime_abstraction execution) = TRUST_Abstract_Applied"
      and "abstraction_command (runtime_abstraction execution) = Some (TRUST_Forward command)"
      and "abstraction_forward_witness (runtime_abstraction execution) = Some witness"
      and "abstraction_reversal_witness (runtime_abstraction execution) = None"
      and "forward_action command = Legal_Recover"
  shows "forward_entitlement_commitment command \<in>
         consumed_entitlements (abstraction_post_state (runtime_abstraction execution)) \<and>
         terminal_case (abstraction_post_state (runtime_abstraction execution))
           (forward_case command)"
  using forward_runtime_state[OF assms(1-5)] recover_success_consumes_entitlement[OF assms(6)]
    recover_success_is_terminal[OF assms(6)]
  by simp

theorem unfreeze_success_refines:
  assumes "runtime_execution execution"
      and "abstraction_outcome (runtime_abstraction execution) = TRUST_Abstract_Applied"
      and "abstraction_command (runtime_abstraction execution) = Some (TRUST_Reverse command)"
      and "abstraction_forward_witness (runtime_abstraction execution) = None"
      and "abstraction_reversal_witness (runtime_abstraction execution) = Some witness"
      and "reversal_original (abstraction_pre_state (runtime_abstraction execution)) command =
             Some original"
      and "reversal_kind command = TRUST_UNFREEZE"
  shows "frozen_targets (abstraction_post_state (runtime_abstraction execution))
           (abstract_subject original) = abstract_prior_amount original \<and>
         reversal_admissible (abstraction_pre_state (runtime_abstraction execution)) command"
  using reversal_runtime_state[OF assms(1-5)]
    unfreeze_success_restores_prior_target[OF assms(6,7)]
  by (simp add: reversal_admitted_def)

theorem release_success_refines:
  assumes "runtime_execution execution"
      and "abstraction_outcome (runtime_abstraction execution) = TRUST_Abstract_Applied"
      and "abstraction_command (runtime_abstraction execution) = Some (TRUST_Reverse command)"
      and "abstraction_forward_witness (runtime_abstraction execution) = None"
      and "abstraction_reversal_witness (runtime_abstraction execution) = Some witness"
      and "reversal_original (abstraction_pre_state (runtime_abstraction execution)) command =
             Some original"
      and "reversal_kind command = TRUST_RELEASE"
      and "custody_records (abstraction_pre_state (runtime_abstraction execution))
             (abstract_case original) = Some custody"
      and "custody_custodian custody \<noteq> custody_prior_holder custody"
  shows "terminal_case (abstraction_post_state (runtime_abstraction execution))
           (abstract_case original) \<and>
         reversal_admissible (abstraction_pre_state (runtime_abstraction execution)) command"
  using reversal_runtime_state[OF assms(1-5)]
    release_success_returns_custody_and_closes_case[OF assms(6,7,8,9)]
  by (simp add: reversal_admitted_def)

theorem unrestrict_success_refines:
  assumes "runtime_execution execution"
      and "abstraction_outcome (runtime_abstraction execution) = TRUST_Abstract_Applied"
      and "abstraction_command (runtime_abstraction execution) = Some (TRUST_Reverse command)"
      and "abstraction_forward_witness (runtime_abstraction execution) = None"
      and "abstraction_reversal_witness (runtime_abstraction execution) = Some witness"
      and "reversal_original (abstraction_pre_state (runtime_abstraction execution)) command =
             Some original"
      and "reversal_kind command = TRUST_UNRESTRICT"
  shows "restriction_flags (abstraction_post_state (runtime_abstraction execution))
           (abstract_subject original) = abstract_prior_flag original \<and>
         reversal_admissible (abstraction_pre_state (runtime_abstraction execution)) command"
  using reversal_runtime_state[OF assms(1-5)]
    unrestrict_success_restores_prior_flag_and_closes_case[OF assms(6,7)]
  by (simp add: reversal_admitted_def)

theorem successful_reversal_never_targets_a_terminal_case:
  assumes "runtime_execution execution"
      and "abstraction_outcome (runtime_abstraction execution) = TRUST_Abstract_Applied"
      and "abstraction_command (runtime_abstraction execution) = Some (TRUST_Reverse command)"
      and "abstraction_forward_witness (runtime_abstraction execution) = None"
      and "abstraction_reversal_witness (runtime_abstraction execution) = Some witness"
      and "reversal_original (abstraction_pre_state (runtime_abstraction execution)) command =
             Some original"
  shows "\<not> terminal_case (abstraction_pre_state (runtime_abstraction execution))
             (abstract_case original)"
  using reversal_runtime_state[OF assms(1-5)] assms(6)
  by (simp add: reversal_admitted_def reversal_admissible_def)

theorem runtime_rejection_stutters:
  assumes "runtime_execution execution"
      and "abstraction_outcome (runtime_abstraction execution) = TRUST_Abstract_Rejected"
  shows "abstraction_post_state (runtime_abstraction execution) =
         abstraction_pre_state (runtime_abstraction execution)"
  using runtime_link[OF assms(1)] assms(2) rejected_transaction_is_abstract_stutter by blast

theorem runtime_operational_failure_stutters:
  assumes "runtime_execution execution"
      and "abstraction_outcome (runtime_abstraction execution) = TRUST_Abstract_Operational"
  shows "abstraction_post_state (runtime_abstraction execution) =
         abstraction_pre_state (runtime_abstraction execution)"
  using runtime_link[OF assms(1)] assms(2) operational_transaction_is_abstract_stutter by blast

theorem runtime_malformed_input_stutters:
  assumes "runtime_execution execution"
      and "abstraction_outcome (runtime_abstraction execution) = TRUST_Abstract_Malformed"
  shows "abstraction_post_state (runtime_abstraction execution) =
         abstraction_pre_state (runtime_abstraction execution)"
  using runtime_link[OF assms(1)] assms(2) malformed_transaction_is_abstract_stutter by blast

theorem runtime_dependency_revert_stutters:
  assumes "runtime_execution execution"
      and "abstraction_outcome (runtime_abstraction execution) = TRUST_Abstract_Dependency_Revert"
  shows "abstraction_post_state (runtime_abstraction execution) =
         abstraction_pre_state (runtime_abstraction execution)"
  using runtime_link[OF assms(1)] assms(2) dependency_revert_is_abstract_stutter by blast

(* The locale assumption runtime_link specialised to one execution.  It is the
   statement the runtime link would deliver, not a discharged result: nothing
   outside this locale may use it without first establishing runtime_link. *)
theorem end_to_end_refinement_under_runtime_link:
  assumes "runtime_execution execution"
  shows "alpha_transaction manifest bridge execution (runtime_abstraction execution)"
  using assms runtime_link by blast

end

theorem heterogeneous_composition_is_conditional_until_certificate:
  "runtime_certificate_complete certificate \<longrightarrow>
   certificate_no_pending_goals certificate \<and>
   certificate_runtime_template_sha256 certificate = native_runtime_template_sha256"
  by (simp add: runtime_certificate_complete_def)

end
