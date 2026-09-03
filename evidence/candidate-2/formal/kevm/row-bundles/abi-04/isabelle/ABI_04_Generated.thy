theory ABI_04_Generated
  imports ERC_TRUST.TRUST_Runtime_Bridge_Generated
begin

definition abi_04_case_matrix_root_sha256 :: string where
  "abi_04_case_matrix_root_sha256 = ''ccc802bec2da08aa07eae5d7ae32a2b3d0b87f58348c96bb9f2505f1275e2678''"
definition abi_04_endpoint_count :: nat where "abi_04_endpoint_count = 6"
definition abi_04_case_count :: nat where "abi_04_case_count = 69"
definition abi_04_short_head_case_count :: nat where "abi_04_short_head_case_count = 12"
definition abi_04_offset_impostor_case_count :: nat where "abi_04_offset_impostor_case_count = 6"
definition abi_04_length_impostor_case_count :: nat where "abi_04_length_impostor_case_count = 6"
definition abi_04_high_bits_and_invalid_enum_case_count :: nat where "abi_04_high_bits_and_invalid_enum_case_count = 45"
definition abi_04_native_runtime_sha256 :: string where
  "abi_04_native_runtime_sha256 = ''3697706d4948c34fada47e049d32ad3e1866cf24ded6328f0c209d858614a86d''"
definition abi_04_native_mutant_sha256 :: string where
  "abi_04_native_mutant_sha256 = ''55e5e0da8641e3ec4c286c07ee78e715093d2b7e224a0189b1a2492f0b22a9b7''"
definition abi_04_profile_runtime_sha256 :: string where
  "abi_04_profile_runtime_sha256 = ''0c873ae5756cf6a3e3ab1317af7c09a39391640b3c54bef4b84b091042d9cf4b''"
definition abi_04_profile_mutant_sha256 :: string where
  "abi_04_profile_mutant_sha256 = ''edeaad5c153f681f1a0db415d77aeb6e0b1fdda2589a300931140e2a39f08984''"
definition abi_04_expected_revert :: bool where "abi_04_expected_revert = True"
definition abi_04_expected_storage_stutter :: bool where "abi_04_expected_storage_stutter = True"

end
