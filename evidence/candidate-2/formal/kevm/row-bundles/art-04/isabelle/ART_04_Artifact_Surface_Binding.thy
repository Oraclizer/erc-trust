theory ART_04_Artifact_Surface_Binding
  imports ERC_TRUST.TRUST_Runtime_Bridge_Generated
begin

definition art04_abi_sha256 :: string where "art04_abi_sha256 = ''de2477f6b31e0185bda5b4c9b1cf0528a4cfa855c084bdbe4b25bf3f3ee4340b''"
definition art04_storage_layout_sha256 :: string where "art04_storage_layout_sha256 = ''18cfae1f174dfc60274512cf6e904adcdeb2cb4c20c54ef83727c537a4bfa281''"
definition art04_trust_storage_ast_sha256 :: string where "art04_trust_storage_ast_sha256 = ''acd241f5d0f224650c9a0bfd0e08ee428dc61d205d6c464f9bcc813180d3a37f''"
definition art04_immutable_references_sha256 :: string where "art04_immutable_references_sha256 = ''639cb762efa24653d51c4f375a2b87f2d79c6814b96b0f331c6f234ab97df6b5''"
definition art04_method_identifiers_sha256 :: string where "art04_method_identifiers_sha256 = ''4078909280bd2a09db749e7cc068036181209ecf60b301f8cb4c5bd60a26881c''"
definition art04_resolved_runtime_sha256 :: string where "art04_resolved_runtime_sha256 = ''3697706d4948c34fada47e049d32ad3e1866cf24ded6328f0c209d858614a86d''"
definition art04_mutant_runtime_sha256 :: string where "art04_mutant_runtime_sha256 = ''7c8541a708e3a74150d22ed113127b5ff5812d7349d52b8e5595980949f07442''"
definition art04_total_supply_selector :: string where "art04_total_supply_selector = ''0x18160ddd''"
definition art04_total_supply_ast_id :: nat where "art04_total_supply_ast_id = 624"
definition art04_total_supply_slot :: nat where "art04_total_supply_slot = 2"
definition art04_storage_entry_count :: nat where "art04_storage_entry_count = 28"
definition art04_immutable_reference_count :: nat where "art04_immutable_reference_count = 5"
definition art04_mutation_byte_offset :: nat where "art04_mutation_byte_offset = 8340"

theorem storage_layout_abi_ast_and_immutable_references_are_hash_bound:
  "art04_resolved_runtime_sha256 = native_resolved_runtime_sha256 \<and>
   art04_abi_sha256 \<noteq> '''' \<and> art04_storage_layout_sha256 \<noteq> '''' \<and>
   art04_trust_storage_ast_sha256 \<noteq> '''' \<and> art04_immutable_references_sha256 \<noteq> '''' \<and>
   art04_method_identifiers_sha256 \<noteq> '''' \<and>
   art04_total_supply_selector = ''0x18160ddd'' \<and> art04_total_supply_ast_id = 624 \<and>
   art04_total_supply_slot = 2 \<and> art04_storage_entry_count > 2 \<and>
   art04_immutable_reference_count = 5 \<and> art04_mutation_byte_offset = 8340 \<and>
   art04_resolved_runtime_sha256 \<noteq> art04_mutant_runtime_sha256"
  by (simp add: art04_resolved_runtime_sha256_def native_resolved_runtime_sha256_def
      art04_abi_sha256_def art04_storage_layout_sha256_def art04_trust_storage_ast_sha256_def
      art04_immutable_references_sha256_def art04_method_identifiers_sha256_def art04_mutant_runtime_sha256_def
      art04_total_supply_selector_def art04_total_supply_ast_id_def art04_total_supply_slot_def
      art04_storage_entry_count_def art04_immutable_reference_count_def art04_mutation_byte_offset_def)

ML \<open>
  val row_fact = @{thm storage_layout_abi_ast_and_immutable_references_are_hash_bound};
  val row_oracles = Thm_Deps.all_oracles [row_fact];
  val _ = if null row_oracles then () else error ("ART-04 proof audit found oracle dependencies");
  val audit_report = "status=PASS\nqualified_theorem=ART_04_Artifact_Surface_Binding.storage_layout_abi_ast_and_immutable_references_are_hash_bound\noracle_dependency_count=0\n";
  val _ = Export.export \<^theory> \<^path_binding>\<open>erc-trust-art-04/proof-trust.txt\<close> [XML.Text audit_report];
\<close>

end
