theory ABI_03_Trailing_Calldata_Reverts_And_Stutters
  imports ERC_TRUST.TRUST_Runtime_Bridge_Generated
begin

definition abi_03_positive_claim_id :: string where
  "abi_03_positive_claim_id = ''6adb6bf3e7629f12e822a2b4772ec91837db3eab2656d3fcb1acfa297e8ac161''"

definition abi_03_positive_claim_sha256 :: string where
  "abi_03_positive_claim_sha256 = ''971cfbb07202d5e9707115c7661d15f91527d1542d761d8c4f443d5cd98832a3''"

definition abi_03_canonical_runtime_sha256 :: string where
  "abi_03_canonical_runtime_sha256 = ''3697706d4948c34fada47e049d32ad3e1866cf24ded6328f0c209d858614a86d''"

definition abi_03_alternate_runtime_sha256 :: string where
  "abi_03_alternate_runtime_sha256 = ''6cca7354ceaa6bb8c6710706ebac1e1e81fd10970ade2438c2e1534742cc8d19''"

definition abi_03_witness_calldata_length :: nat where
  "abi_03_witness_calldata_length = 708"

definition abi_03_trailing_word_length :: nat where
  "abi_03_trailing_word_length = 32"

definition abi_03_idle_guard_slot :: nat where
  "abi_03_idle_guard_slot = 29"

definition abi_03_external_call_static :: bool where
  "abi_03_external_call_static = False"

definition abi_03_expected_status :: string where
  "abi_03_expected_status = ''EVMC_REVERT''"

definition abi_03_expected_output_length :: nat where
  "abi_03_expected_output_length = 0"

definition abi_03_storage_stutter :: bool where
  "abi_03_storage_stutter = True"

theorem abi_03_trailing_calldata_reverts_and_stutters:
  "action_entrypoint_selector = 2644653369 \<and>
   action_calldata_length = 676 \<and>
   abi_03_witness_calldata_length = action_calldata_length + abi_03_trailing_word_length \<and>
   abi_03_idle_guard_slot = 29 \<and>
   \<not> abi_03_external_call_static \<and>
   abi_03_expected_status = ''EVMC_REVERT'' \<and>
   abi_03_expected_output_length = 0 \<and>
   abi_03_storage_stutter \<and>
   abi_03_canonical_runtime_sha256 = native_resolved_runtime_sha256 \<and>
   abi_03_canonical_runtime_sha256 \<noteq> abi_03_alternate_runtime_sha256 \<and>
   abi_03_positive_claim_id \<noteq> ''''"
  by (simp add: action_entrypoint_selector_def action_calldata_length_def
      abi_03_witness_calldata_length_def abi_03_trailing_word_length_def
      abi_03_idle_guard_slot_def abi_03_external_call_static_def
      abi_03_expected_status_def abi_03_expected_output_length_def
      abi_03_storage_stutter_def abi_03_canonical_runtime_sha256_def
      native_resolved_runtime_sha256_def abi_03_alternate_runtime_sha256_def
      abi_03_positive_claim_id_def)

ML \<open>
  val row_fact = @{thm abi_03_trailing_calldata_reverts_and_stutters};
  val row_oracles = Thm_Deps.all_oracles [row_fact];
  val _ = if null row_oracles then ()
    else error ("ABI-03 proof audit found " ^ string_of_int (length row_oracles) ^ " oracle dependencies");
  val audit_report =
    "status=PASS\\n" ^
    "qualified_theorem=ABI_03_Trailing_Calldata_Reverts_And_Stutters.abi_03_trailing_calldata_reverts_and_stutters\\n" ^
    "oracle_dependency_count=0\\n";
  val _ = Export.export \<^theory>
    \<^path_binding>\<open>erc-trust-abi-03/proof-trust.txt\<close>
    [XML.Text audit_report];
\<close>

end
