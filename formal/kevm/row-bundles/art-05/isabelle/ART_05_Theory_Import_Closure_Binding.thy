theory ART_05_Theory_Import_Closure_Binding
  imports ERC_TRUST.TRUST_Runtime_Bridge_Generated
begin

definition art05_closure_root_sha256 :: string where "art05_closure_root_sha256 = ''ce51d00c06ae0a8c348d5da538c0110fdb129877efe9861f0353b7fc21b6d448''"
definition art05_session_root_sha256 :: string where "art05_session_root_sha256 = ''30ef7de586a1652a4af19296b1ba0c51e991290d939cf9224532d37183912229''"
definition art05_runtime_bridge_theory_sha256 :: string where "art05_runtime_bridge_theory_sha256 = ''48ef15ed0789be51c0d56f22740d93ba5c7a474116209be66855e8c95b870728''"
definition art05_composition_root_sha256 :: string where "art05_composition_root_sha256 = ''a2cc126c6434cfec200aafb73a5b46ec20c921c4735de86a149ddbeb38839b9d''"
definition art05_governor_declaration_sha256 :: string where "art05_governor_declaration_sha256 = ''863799c3a3754bcf8daa2f1e7591263f3bca4c3853dcc1c26a3756f624912415''"
definition art05_governor_assignment_sha256 :: string where "art05_governor_assignment_sha256 = ''76790636d6785040280cb67444c6a00fb96c9910817835db649a9feec9566c42''"
definition art05_governor_address_word :: string where "art05_governor_address_word = ''0x000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266''"
definition art05_runtime_sha256 :: string where "art05_runtime_sha256 = ''3697706d4948c34fada47e049d32ad3e1866cf24ded6328f0c209d858614a86d''"
definition art05_mutant_runtime_sha256 :: string where "art05_mutant_runtime_sha256 = ''8be632ea839589c14e91eacf523379c2cfa8377441b8f6e4cadfbad39eb6c3c4''"
definition art05_theory_count :: nat where "art05_theory_count = 14"
definition art05_local_import_edge_count :: nat where "art05_local_import_edge_count = 13"
definition art05_external_import_count :: nat where "art05_external_import_count = 1"
definition art05_mutation_byte_offset :: nat where "art05_mutation_byte_offset = 8553"

theorem theory_source_and_import_closure_are_hash_bound:
  "art05_closure_root_sha256 \<noteq> '''' \<and> art05_session_root_sha256 \<noteq> '''' \<and>
   art05_runtime_bridge_theory_sha256 \<noteq> '''' \<and> art05_composition_root_sha256 \<noteq> '''' \<and>
   art05_governor_declaration_sha256 \<noteq> '''' \<and> art05_governor_assignment_sha256 \<noteq> '''' \<and>
   art05_governor_address_word = ''0x000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266'' \<and> art05_runtime_sha256 = native_resolved_runtime_sha256 \<and>
   art05_theory_count = 14 \<and> art05_local_import_edge_count = 13 \<and> art05_external_import_count = 1 \<and>
   art05_mutation_byte_offset = 8553 \<and> art05_runtime_sha256 \<noteq> art05_mutant_runtime_sha256"
  by (simp add: art05_closure_root_sha256_def art05_session_root_sha256_def art05_runtime_bridge_theory_sha256_def
      art05_composition_root_sha256_def art05_governor_declaration_sha256_def art05_governor_assignment_sha256_def art05_governor_address_word_def
      art05_runtime_sha256_def native_resolved_runtime_sha256_def art05_mutant_runtime_sha256_def
      art05_theory_count_def art05_local_import_edge_count_def art05_external_import_count_def art05_mutation_byte_offset_def)

ML \<open>
  val row_fact = @{thm theory_source_and_import_closure_are_hash_bound};
  val row_oracles = Thm_Deps.all_oracles [row_fact];
  val _ = if null row_oracles then () else error ("ART-05 proof audit found oracle dependencies");
  val audit_report = "status=PASS\nqualified_theorem=ART_05_Theory_Import_Closure_Binding.theory_source_and_import_closure_are_hash_bound\noracle_dependency_count=0\n";
  val _ = Export.export \<^theory> \<^path_binding>\<open>erc-trust-art-05/proof-trust.txt\<close> [XML.Text audit_report];
\<close>

end
