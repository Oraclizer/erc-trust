theory ART_02_Compiler_Output_Runtime_Binding
  imports ERC_TRUST.TRUST_Runtime_Bridge_Generated
begin

definition compiler_runtime_template_sha256 :: string where
  "compiler_runtime_template_sha256 = ''e81429838a7274b63c0a53468d8747c887077408a2e504a181460adb400466ce''"

definition row_compiler_binding_root_sha256 :: string where
  "row_compiler_binding_root_sha256 = ''44c62545b9545741bce98b313f412914bc976430c5596de6ad735f68d81cd4ab''"

definition row_constructor_fixture_root_sha256 :: string where
  "row_constructor_fixture_root_sha256 = ''b5ce284d6b7017a1feff3244bb67f175303660d86348ce93dbd8065bd39d3a2d''"

definition patched_compiler_runtime_sha256 :: string where
  "patched_compiler_runtime_sha256 = ''3697706d4948c34fada47e049d32ad3e1866cf24ded6328f0c209d858614a86d''"

definition resolved_runtime_sha256 :: string where
  "resolved_runtime_sha256 = ''3697706d4948c34fada47e049d32ad3e1866cf24ded6328f0c209d858614a86d''"

definition generated_runtime_sha256 :: string where
  "generated_runtime_sha256 = ''3697706d4948c34fada47e049d32ad3e1866cf24ded6328f0c209d858614a86d''"

definition runtime_byte_mutant_sha256 :: string where
  "runtime_byte_mutant_sha256 = ''9a48c6ea9d5b6341e8e62e731622305a11e8080e1d90644771dc53bbfb90f6cb''"

definition compiler_runtime_byte_length :: nat where
  "compiler_runtime_byte_length = 24142"

definition resolved_runtime_byte_length :: nat where
  "resolved_runtime_byte_length = 24142"

definition runtime_mutation_byte_offset :: nat where
  "runtime_mutation_byte_offset = 17"

definition immutable_patch_ranges :: "(nat * nat) list" where
  "immutable_patch_ranges = [(517, 32), (1580, 32), (6970, 32), (8522, 32), (19822, 32)]"

theorem compiler_output_runtime_bytes_are_hash_bound:
  "row_compiler_binding_root_sha256 = compiler_binding_root_sha256 \<and>
   row_constructor_fixture_root_sha256 = constructor_fixture_root_sha256 \<and>
   length immutable_patch_ranges = 5 \<and>
   map fst immutable_patch_ranges = [517, 1580, 6970, 8522, 19822] \<and>
   (\<forall>(start, width) \<in> set immutable_patch_ranges. width = 32 \<and> start + width \<le> compiler_runtime_byte_length) \<and>
   compiler_runtime_byte_length = resolved_runtime_byte_length \<and>
   patched_compiler_runtime_sha256 = native_resolved_runtime_sha256 \<and>
   resolved_runtime_sha256 = generated_runtime_sha256 \<and>
   generated_runtime_sha256 = native_resolved_runtime_sha256 \<and>
   resolved_runtime_sha256 \<noteq> runtime_byte_mutant_sha256 \<and>
   runtime_mutation_byte_offset < resolved_runtime_byte_length"
  by (simp add: row_compiler_binding_root_sha256_def
      row_constructor_fixture_root_sha256_def compiler_binding_root_sha256_def
      constructor_fixture_root_sha256_def immutable_patch_ranges_def
      compiler_runtime_byte_length_def resolved_runtime_byte_length_def
      patched_compiler_runtime_sha256_def native_resolved_runtime_sha256_def
      resolved_runtime_sha256_def
      generated_runtime_sha256_def runtime_byte_mutant_sha256_def
      runtime_mutation_byte_offset_def)

ML \<open>
  val row_fact = @{thm compiler_output_runtime_bytes_are_hash_bound};
  val row_oracles = Thm_Deps.all_oracles [row_fact];
  val _ =
    if null row_oracles then ()
    else error
      ("ART-02 proof audit found " ^
       string_of_int (length row_oracles) ^ " oracle dependencies");
  val audit_report =
    "status=PASS\n" ^
    "qualified_theorem=ART_02_Compiler_Output_Runtime_Binding.compiler_output_runtime_bytes_are_hash_bound\n" ^
    "oracle_dependency_count=0\n";
  val _ = Export.export \<^theory>
    \<^path_binding>\<open>erc-trust-art-02/proof-trust.txt\<close>
    [XML.Text audit_report];
\<close>

end
