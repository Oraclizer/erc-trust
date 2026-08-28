theory ABI_04_Finite_Symbolic_Generated
  imports ABI_04_Generated
begin

text \<open>Generated worker-local ABI-04 aggregation metadata. Not proof evidence.\<close>

definition abi_04_finite_matrix_root_sha256 :: string where
  "abi_04_finite_matrix_root_sha256 = ''3347fd98dcb04769394fb8705a58c644574ff50999da5eea8a7da07de2134833''"
definition abi_04_symbolic_claims_root_sha256 :: string where
  "abi_04_symbolic_claims_root_sha256 = ''3594a2034746c45ab52236b44b381dff00a11ce901dbd55eedb18df034de8ab3''"
definition abi_04_combined_requirement_root_sha256 :: string where
  "abi_04_combined_requirement_root_sha256 = ''63796426169cfe15dca16f0640a7b1861f334f83a405148b3f357f8c08dc2363''"
definition abi_04_finite_claim_count :: nat where "abi_04_finite_claim_count = 69"
definition abi_04_symbolic_claim_count :: nat where "abi_04_symbolic_claim_count = 12"
definition abi_04_required_replay_count :: nat where "abi_04_required_replay_count = 162"
definition abi_04_action_endpoint_count :: nat where "abi_04_action_endpoint_count = 3"
definition abi_04_reversal_endpoint_count :: nat where "abi_04_reversal_endpoint_count = 3"
definition abi_04_symbolic_missing_length_cardinality :: nat where
  "abi_04_symbolic_missing_length_cardinality = 2868"
definition abi_04_concrete_sentinel_length_cardinality :: nat where
  "abi_04_concrete_sentinel_length_cardinality = 12"
definition abi_04_complete_short_length_cardinality :: nat where
  "abi_04_complete_short_length_cardinality = 2880"
definition abi_04_proof_status :: string where "abi_04_proof_status = ''NOT_RUN''"
definition abi_04_closure_status :: string where "abi_04_closure_status = ''OPEN''"
definition abi_04_eligible_for_discharge :: bool where "abi_04_eligible_for_discharge = False"
definition abi_04_abi03_coverage_credit :: nat where "abi_04_abi03_coverage_credit = 0"

end
