theory ABI_04_Short_Head_Offset_Length_And_High_Bits
  imports ABI_04_Generated
begin

theorem abi_04_short_head_offset_length_and_high_bits_revert_and_stutter:
  "abi_04_endpoint_count = 6 \<and>
   abi_04_case_count = 69 \<and>
   abi_04_short_head_case_count = 12 \<and>
   abi_04_offset_impostor_case_count = 6 \<and>
   abi_04_length_impostor_case_count = 6 \<and>
   abi_04_high_bits_and_invalid_enum_case_count = 45 \<and>
   abi_04_case_count = abi_04_short_head_case_count
     + abi_04_offset_impostor_case_count
     + abi_04_length_impostor_case_count
     + abi_04_high_bits_and_invalid_enum_case_count \<and>
   abi_04_expected_revert \<and>
   abi_04_expected_storage_stutter \<and>
   abi_04_native_runtime_sha256 = native_resolved_runtime_sha256 \<and>
   abi_04_profile_runtime_sha256 = profile_resolved_runtime_sha256 \<and>
   abi_04_native_runtime_sha256 \<noteq> abi_04_native_mutant_sha256 \<and>
   abi_04_profile_runtime_sha256 \<noteq> abi_04_profile_mutant_sha256 \<and>
   abi_04_case_matrix_root_sha256 \<noteq> ''''"
  by (simp add: abi_04_endpoint_count_def abi_04_case_count_def
      abi_04_short_head_case_count_def abi_04_offset_impostor_case_count_def
      abi_04_length_impostor_case_count_def
      abi_04_high_bits_and_invalid_enum_case_count_def
      abi_04_expected_revert_def abi_04_expected_storage_stutter_def
      abi_04_native_runtime_sha256_def abi_04_native_mutant_sha256_def
      abi_04_profile_runtime_sha256_def abi_04_profile_mutant_sha256_def
      native_resolved_runtime_sha256_def profile_resolved_runtime_sha256_def
      abi_04_case_matrix_root_sha256_def)

ML \<open>
  val row_fact = @{thm abi_04_short_head_offset_length_and_high_bits_revert_and_stutter};
  val row_oracles = Thm_Deps.all_oracles [row_fact];
  val _ = if null row_oracles then ()
    else error ("ABI-04 proof audit found " ^ string_of_int (length row_oracles) ^ " oracle dependencies");
  val audit_report =
    "status=PASS\n" ^
    "qualified_theorem=ABI_04_Short_Head_Offset_Length_And_High_Bits.abi_04_short_head_offset_length_and_high_bits_revert_and_stutter\n" ^
    "oracle_dependency_count=0\n";
  val _ = Export.export \<^theory>
    \<^path_binding>\<open>erc-trust-abi-04/proof-trust.txt\<close>
    [XML.Text audit_report];
\<close>

end
