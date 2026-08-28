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
             assessment_length observation \<noteq> 128
       then Dependency_Operational 202
     else if assessment_word observation > 2 \<or>
             \<not> command_echo_matches observation \<or>
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

theorem dependency_transport_shape_failure_is_reason_202:
  assumes "dependency_identity_ok observation"
      and "configuration_call_ok observation"
      and "configuration_length observation = 32"
      and "configuration_matches observation"
      and "\<not> assessment_call_ok observation \<or> assessment_length observation \<noteq> 128"
  shows "classify_dependency observation = Dependency_Operational 202"
  using assms by (auto simp: classify_dependency_def)

theorem dependency_word_or_echo_failure_is_reason_203:
  assumes "dependency_identity_ok observation"
      and "configuration_call_ok observation"
      and "configuration_length observation = 32"
      and "configuration_matches observation"
      and "assessment_call_ok observation"
      and "assessment_length observation = 128"
      and "assessment_word observation > 2 \<or>
           \<not> command_echo_matches observation \<or>
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

definition dependency_failure_post ::
  "'state \<Rightarrow> dependency_classification \<Rightarrow> 'state"
where
  "dependency_failure_post pre classification = pre"

theorem dependency_denial_or_operational_failure_stutters:
  assumes "classification = Dependency_Rejected \<or>
           (\<exists>reason. classification = Dependency_Operational reason)"
  shows "dependency_failure_post pre classification = pre"
  using assms by (simp add: dependency_failure_post_def)

end
