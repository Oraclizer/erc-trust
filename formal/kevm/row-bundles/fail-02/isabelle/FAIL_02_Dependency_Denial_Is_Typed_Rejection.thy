theory FAIL_02_Dependency_Denial_Is_Typed_Rejection
  imports ERC_TRUST.TRUST_End_To_End_Composition
begin

text <open>Row-local FAIL-02 closure skeleton.  The exact-runtime claim must
  establish the premise that a dependency REJECTED assessment returns the
  TrustRejected selector.  This theory only composes that pending premise with
  the existing runtime rejection stutter theorem.<close>

definition fail_02_required_property :: string where
  "fail_02_required_property = ''dependency_denial_is_typed_rejection''"

definition fail_02_proof_status :: string where
  "fail_02_proof_status = ''NOT_RUN''"

definition fail_02_eligible_for_discharge :: bool where
  "fail_02_eligible_for_discharge = False"

definition fail_02_dependency_denial_result ::
  "trust_transaction_execution <Rightarrow> evm_bytes <Rightarrow> bool"
where
  "fail_02_dependency_denial_result execution payload <longleftrightarrow>
     transaction_result execution = TRUST_Return_Rejection payload <and>
     evm_bytes_selector payload = Some trust_rejected_selector"

theorem fail_02_dependency_denial_is_typed_rejection:
  assumes "runtime_execution execution"
      and "abstraction_outcome (runtime_abstraction execution) = TRUST_Abstract_Rejected"
      and "fail_02_dependency_denial_result execution payload"
  shows "transaction_result execution = TRUST_Return_Rejection payload <and>
         typed_failure_payload payload <and>
         abstraction_post_state (runtime_abstraction execution) =
           abstraction_pre_state (runtime_abstraction execution)"
proof -
  from assms(3) have result:
    "transaction_result execution = TRUST_Return_Rejection payload"
    and selector:
    "evm_bytes_selector payload = Some trust_rejected_selector"
    by (auto simp: fail_02_dependency_denial_result_def)
  from selector have typed: "typed_failure_payload payload"
    by (simp add: typed_failure_payload_def typed_failure_selectors_def)
  from assms(1,2) have stutter:
    "abstraction_post_state (runtime_abstraction execution) =
       abstraction_pre_state (runtime_abstraction execution)"
    using runtime_rejection_stutters by blast
  from result typed stutter show ?thesis by blast
qed

theorem fail_02_static_gate_remains_open:
  "fail_02_proof_status = ''NOT_RUN'' <and> <not> fail_02_eligible_for_discharge"
  by (simp add: fail_02_proof_status_def fail_02_eligible_for_discharge_def)

end
