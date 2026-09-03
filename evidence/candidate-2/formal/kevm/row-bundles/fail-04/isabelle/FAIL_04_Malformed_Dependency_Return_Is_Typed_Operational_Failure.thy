theory FAIL_04_Malformed_Dependency_Return_Is_Typed_Operational_Failure
  imports ERC_TRUST.TRUST_End_To_End_Composition
begin

definition fail_04_required_property :: string where
  "fail_04_required_property = ''malformed_dependency_return_is_typed_operational_failure''"
definition fail_04_proof_status :: string where "fail_04_proof_status = ''NOT_RUN''"
definition fail_04_eligible_for_discharge :: bool where "fail_04_eligible_for_discharge = False"
definition fail_04_result :: "trust_transaction_execution \<Rightarrow> evm_bytes \<Rightarrow> bool" where
  "fail_04_result execution payload \<longleftrightarrow> transaction_result execution = TRUST_Return_Rejection payload \<and> evm_bytes_selector payload = Some trust_operational_failure_selector"

theorem fail_04_malformed_dependency_return_is_typed_operational_failure:
  assumes "runtime_execution execution" and "abstraction_outcome (runtime_abstraction execution) = TRUST_Abstract_Operational" and "fail_04_result execution payload"
  shows "transaction_result execution = TRUST_Return_Rejection payload \<and> typed_failure_payload payload \<and> abstraction_post_state (runtime_abstraction execution) = abstraction_pre_state (runtime_abstraction execution)"
  using assms runtime_operational_failure_stutters by (auto simp: fail_04_result_def typed_failure_payload_def typed_failure_selectors_def)

theorem fail_04_static_gate_remains_open: "fail_04_proof_status = ''NOT_RUN'' \<and> \<not> fail_04_eligible_for_discharge"
  by (simp add: fail_04_proof_status_def fail_04_eligible_for_discharge_def)
end
