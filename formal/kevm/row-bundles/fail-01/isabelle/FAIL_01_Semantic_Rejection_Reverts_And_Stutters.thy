theory FAIL_01_Semantic_Rejection_Reverts_And_Stutters
  imports ERC_TRUST.TRUST_End_To_End_Composition
begin

text ‹
  Row-local FAIL-01 closure skeleton.  The theorem composes the existing
  abstract runtime-rejection stutter result with an explicit typed rejection
  result assumption.  It does not assert that the row's KEVM claim has run.
›

definition fail_01_required_property :: string where
  "fail_01_required_property = ''semantic_rejection_reverts_and_stutters''"

definition fail_01_proof_status :: string where
  "fail_01_proof_status = ''NOT_RUN''"

definition fail_01_eligible_for_discharge :: bool where
  "fail_01_eligible_for_discharge = False"

theorem fail_01_semantic_rejection_reverts_and_stutters:
  assumes "runtime_execution execution"
      and "abstraction_outcome (runtime_abstraction execution) = TRUST_Abstract_Rejected"
      and "transaction_result execution = TRUST_Return_Rejection payload"
  shows "transaction_result execution = TRUST_Return_Rejection payload ∧
         abstraction_post_state (runtime_abstraction execution) =
           abstraction_pre_state (runtime_abstraction execution)"
  using assms runtime_rejection_stutters by blast

theorem fail_01_static_gate_remains_open:
  "fail_01_proof_status = ''NOT_RUN'' ∧ ¬ fail_01_eligible_for_discharge"
  by (simp add: fail_01_proof_status_def fail_01_eligible_for_discharge_def)

end
