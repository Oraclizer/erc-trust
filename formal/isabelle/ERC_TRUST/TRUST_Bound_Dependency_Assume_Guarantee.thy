(*
  Fail-closed classification of a bound dependency observation.

  Reason codes follow the kernel version 2 dependency failure mapping: 200 for
  changed runtime code, 201 for a changed configuration digest, 202 for a call
  that reverts, returns a length other than 128 bytes, or returns an outcome
  word above 2, 203 for a command or binding echo mismatch, and 204 when the
  dependency itself reports an operational failure.
*)

theory TRUST_Bound_Dependency_Assume_Guarantee
  imports TRUST_State_Abi_Normal_Form
begin

record dependency_observation =
  dependency_identity_ok :: bool
  configuration_call_ok :: bool
  configuration_length :: nat
  configuration_matches :: bool
  assessment_call_ok :: bool
  assessment_length :: nat
  assessment_word :: nat
  command_echo_matches :: bool
  binding_echo_matches :: bool
  assessment_evidence :: nat

datatype dependency_classification =
    Dependency_Applicable nat
  | Dependency_Rejected
  | Dependency_Operational nat

definition classify_dependency ::
  "dependency_observation \<Rightarrow> dependency_classification"
where
  "classify_dependency observation =
    (if \<not> dependency_identity_ok observation then Dependency_Operational 200
     else if \<not> configuration_call_ok observation \<or>
             configuration_length observation \<noteq> 32 \<or>
             \<not> configuration_matches observation
       then Dependency_Operational 201
     else if \<not> assessment_call_ok observation \<or>
             assessment_length observation \<noteq> 128 \<or>
             assessment_word observation > 2
       then Dependency_Operational 202
     else if \<not> command_echo_matches observation \<or>
             \<not> binding_echo_matches observation
       then Dependency_Operational 203
     else if assessment_word observation = 0
       then Dependency_Applicable (assessment_evidence observation)
     else if assessment_word observation = 1
       then Dependency_Rejected
     else Dependency_Operational 204)"

theorem bound_dependency_canonical_approval_classifies_applicable:
  assumes "dependency_identity_ok observation"
      and "configuration_call_ok observation"
      and "configuration_length observation = 32"
      and "configuration_matches observation"
      and "assessment_call_ok observation"
      and "assessment_length observation = 128"
      and "assessment_word observation = 0"
      and "command_echo_matches observation"
      and "binding_echo_matches observation"
  shows "classify_dependency observation =
         Dependency_Applicable (assessment_evidence observation)"
  using assms by (simp add: classify_dependency_def)

theorem bound_dependency_canonical_denial_is_typed_rejection:
  assumes "dependency_identity_ok observation"
      and "configuration_call_ok observation"
      and "configuration_length observation = 32"
      and "configuration_matches observation"
      and "assessment_call_ok observation"
      and "assessment_length observation = 128"
      and "assessment_word observation = 1"
      and "command_echo_matches observation"
      and "binding_echo_matches observation"
  shows "classify_dependency observation = Dependency_Rejected"
  using assms by (simp add: classify_dependency_def)

theorem dependency_identity_failure_is_reason_200:
  assumes "\<not> dependency_identity_ok observation"
  shows "classify_dependency observation = Dependency_Operational 200"
  using assms by (simp add: classify_dependency_def)

theorem dependency_configuration_failure_is_reason_201:
  assumes "dependency_identity_ok observation"
      and "\<not> configuration_call_ok observation \<or>
           configuration_length observation \<noteq> 32 \<or>
           \<not> configuration_matches observation"
  shows "classify_dependency observation = Dependency_Operational 201"
  using assms by (auto simp: classify_dependency_def)

theorem dependency_malformed_response_is_reason_202:
  assumes "dependency_identity_ok observation"
      and "configuration_call_ok observation"
      and "configuration_length observation = 32"
      and "configuration_matches observation"
      and "\<not> assessment_call_ok observation \<or>
           assessment_length observation \<noteq> 128 \<or>
           assessment_word observation > 2"
  shows "classify_dependency observation = Dependency_Operational 202"
  using assms by (auto simp: classify_dependency_def)

theorem dependency_echo_failure_is_reason_203:
  assumes "dependency_identity_ok observation"
      and "configuration_call_ok observation"
      and "configuration_length observation = 32"
      and "configuration_matches observation"
      and "assessment_call_ok observation"
      and "assessment_length observation = 128"
      and "assessment_word observation \<le> 2"
      and "\<not> command_echo_matches observation \<or>
           \<not> binding_echo_matches observation"
  shows "classify_dependency observation = Dependency_Operational 203"
  using assms by (auto simp: classify_dependency_def)

theorem dependency_canonical_operational_is_reason_204:
  assumes "dependency_identity_ok observation"
      and "configuration_call_ok observation"
      and "configuration_length observation = 32"
      and "configuration_matches observation"
      and "assessment_call_ok observation"
      and "assessment_length observation = 128"
      and "assessment_word observation = 2"
      and "command_echo_matches observation"
      and "binding_echo_matches observation"
  shows "classify_dependency observation = Dependency_Operational 204"
  using assms by (simp add: classify_dependency_def)

theorem dependency_never_applies_without_matching_echoes:
  assumes "classify_dependency observation = Dependency_Applicable evidence"
  shows "command_echo_matches observation \<and> binding_echo_matches observation"
  using assms by (auto simp: classify_dependency_def split: if_splits)

text \<open>
  The endpoint applies the command's transition only when the dependency is
  classified applicable; a denial or an operational failure leaves the state
  where it was.  The outcome is a function of the classification, so the
  stutter theorem below depends on its hypothesis.
\<close>

definition dependency_outcome_post ::
  "'state \<Rightarrow> dependency_classification \<Rightarrow> ('state \<Rightarrow> 'state) \<Rightarrow> 'state"
where
  "dependency_outcome_post pre classification transition =
     (case classification of
        Dependency_Applicable _ \<Rightarrow> transition pre
      | _ \<Rightarrow> pre)"

theorem dependency_applicable_admits_the_transition:
  "dependency_outcome_post pre (Dependency_Applicable evidence) transition = transition pre"
  by (simp add: dependency_outcome_post_def)

theorem dependency_denial_or_operational_failure_stutters:
  assumes "classification = Dependency_Rejected \<or>
           (\<exists>reason. classification = Dependency_Operational reason)"
  shows "dependency_outcome_post pre classification transition = pre"
  using assms by (auto simp: dependency_outcome_post_def)

end
