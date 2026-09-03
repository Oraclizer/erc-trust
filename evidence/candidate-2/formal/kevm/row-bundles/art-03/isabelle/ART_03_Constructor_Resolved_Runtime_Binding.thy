theory ART_03_Constructor_Resolved_Runtime_Binding
  imports ERC_TRUST.TRUST_Runtime_Bridge_Generated
begin

definition art03_constructor_fixture_root_sha256 :: string where
  "art03_constructor_fixture_root_sha256 = ''b5ce284d6b7017a1feff3244bb67f175303660d86348ce93dbd8065bd39d3a2d''"

definition art03_resolved_runtime_sha256 :: string where
  "art03_resolved_runtime_sha256 = ''3697706d4948c34fada47e049d32ad3e1866cf24ded6328f0c209d858614a86d''"

definition art03_mutant_runtime_sha256 :: string where
  "art03_mutant_runtime_sha256 = ''f6c26fb38b29f1836f2f37ef456c829f8c3c9db0f521cf7aaf91c5b57b978dfa''"

definition art03_runtime_byte_length :: nat where
  "art03_runtime_byte_length = 24142"

definition art03_decimals_ast_id :: nat where
  "art03_decimals_ast_id = 622"

definition art03_decimals_selector :: string where
  "art03_decimals_selector = ''0x313ce567''"

definition art03_decimals_value :: nat where
  "art03_decimals_value = 18"

definition art03_decimals_word :: string where
  "art03_decimals_word = ''0x0000000000000000000000000000000000000000000000000000000000000012''"

definition art03_decimals_immutable_range :: "nat * nat" where
  "art03_decimals_immutable_range = (6970, 32)"

definition art03_mutation_byte_offset :: nat where
  "art03_mutation_byte_offset = 7001"

theorem constructor_resolved_local_runtime_is_hash_bound:
  "art03_constructor_fixture_root_sha256 = constructor_fixture_root_sha256 \<and>
   art03_resolved_runtime_sha256 = native_resolved_runtime_sha256 \<and>
   art03_decimals_ast_id = 622 \<and>
   art03_decimals_selector = ''0x313ce567'' \<and>
   art03_decimals_value = 18 \<and>
   art03_decimals_word = ''0x0000000000000000000000000000000000000000000000000000000000000012'' \<and>
   art03_decimals_immutable_range = (6970, 32) \<and>
   fst art03_decimals_immutable_range + snd art03_decimals_immutable_range \<le> art03_runtime_byte_length \<and>
   art03_mutation_byte_offset = fst art03_decimals_immutable_range + snd art03_decimals_immutable_range - 1 \<and>
   art03_resolved_runtime_sha256 \<noteq> art03_mutant_runtime_sha256"
  by (simp add: art03_constructor_fixture_root_sha256_def constructor_fixture_root_sha256_def
      art03_resolved_runtime_sha256_def native_resolved_runtime_sha256_def
      art03_mutant_runtime_sha256_def art03_runtime_byte_length_def
      art03_decimals_ast_id_def art03_decimals_selector_def art03_decimals_value_def
      art03_decimals_word_def art03_decimals_immutable_range_def art03_mutation_byte_offset_def)

ML \<open>
  val row_fact = @{thm constructor_resolved_local_runtime_is_hash_bound};
  val row_oracles = Thm_Deps.all_oracles [row_fact];
  val _ = if null row_oracles then () else
    error ("ART-03 proof audit found " ^ string_of_int (length row_oracles) ^ " oracle dependencies");
  val audit_report =
    "status=PASS\n" ^
    "qualified_theorem=ART_03_Constructor_Resolved_Runtime_Binding.constructor_resolved_local_runtime_is_hash_bound\n" ^
    "oracle_dependency_count=0\n";
  val _ = Export.export \<^theory>
    \<^path_binding>\<open>erc-trust-art-03/proof-trust.txt\<close> [XML.Text audit_report];
\<close>

end
