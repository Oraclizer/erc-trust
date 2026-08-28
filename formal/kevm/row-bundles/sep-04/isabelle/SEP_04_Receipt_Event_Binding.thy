theory SEP_04_Receipt_Event_Binding
  imports ERC_TRUST.TRUST_Transaction_Refinement
          ERC_TRUST.TRUST_Runtime_Bridge_Generated
begin

definition sep04_runtime_sha256 :: string where
  "sep04_runtime_sha256 = ''3697706d4948c34fada47e049d32ad3e1866cf24ded6328f0c209d858614a86d''"

definition sep04_event_signature :: string where
  "sep04_event_signature = ''RegulatoryActionApplied(bytes32,uint8,bytes32,bytes32)''"

definition sep04_canonical_event_topic :: string where
  "sep04_canonical_event_topic = ''0xaadd5db99c0c1f57ce6f82b109958a00899fc4cea03e70fdae7741b9e7050091''"

definition sep04_mutant_event_topic :: string where
  "sep04_mutant_event_topic = ''0xabdd5db99c0c1f57ce6f82b109958a00899fc4cea03e70fdae7741b9e7050091''"

definition sep04_event_topic_byte_offset :: nat where
  "sep04_event_topic_byte_offset = 18310"

definition sep04_composition_root_sha256 :: string where
  "sep04_composition_root_sha256 = ''8729d58c7a547a884494830b211f3b54c2c9b4574a3d14a721955c69483136cd''"

definition sep04_action_receipt_source_sha256 :: string where
  "sep04_action_receipt_source_sha256 = ''9e3c0fe2fda513cc064b720d5f411d3c999c0633a15043b56faf36386c6896e2''"

definition sep04_canonical_receipt_trace_source_sha256 :: string where
  "sep04_canonical_receipt_trace_source_sha256 = ''20c0d73ca1c5a45829be02b7ee7295963ddaf557adbe6e126c246f0af4174ac1''"

definition sep04_canonical_topic_decimal :: string where
  "sep04_canonical_topic_decimal = ''77284304326905398285819503064054149854320822776110682615707144351377747411089''"

definition sep04_mutant_topic_decimal :: string where
  "sep04_mutant_topic_decimal = ''77736617175488664674192827224244336994372658653710841068986275538908658073745''"

theorem receipt_preimage_matches_storage_return_and_final_event:
  assumes alpha: "alpha_transaction manifest bridge execution abstraction"
      and applied: "abstraction_outcome abstraction = TRUST_Abstract_Applied"
      and receipt: "abstraction_receipt abstraction = Some receipt"
  shows "expected_success_state abstraction = Some (abstraction_post_state abstraction) \<and>
         transaction_raw_logs execution \<noteq> [] \<and>
         last (transaction_raw_logs execution) = bridge_receipt_log bridge receipt \<and>
         (\<exists>payload. transaction_result execution = TRUST_Return_Success payload \<and>
           bridge_return_receipt_hash bridge payload =
             Some (compositional_receipt_hash receipt))"
  using assms
  by (auto simp: alpha_transaction_def canonical_receipt_trace_def)

theorem sep04_generated_event_boundary_is_distinct:
  "sep04_runtime_sha256 = native_resolved_runtime_sha256 \<and>
   sep04_canonical_event_topic \<noteq> sep04_mutant_event_topic \<and>
   sep04_event_topic_byte_offset < native_resolved_runtime_byte_length \<and>
   sep04_composition_root_sha256 \<noteq> '''' \<and>
   sep04_action_receipt_source_sha256 \<noteq> '''' \<and>
   sep04_canonical_receipt_trace_source_sha256 \<noteq> '''' \<and>
   sep04_canonical_topic_decimal \<noteq> sep04_mutant_topic_decimal"
  by (simp add: sep04_runtime_sha256_def native_resolved_runtime_sha256_def
      sep04_canonical_event_topic_def sep04_mutant_event_topic_def
      sep04_event_topic_byte_offset_def native_resolved_runtime_byte_length_def
      sep04_composition_root_sha256_def sep04_action_receipt_source_sha256_def
      sep04_canonical_receipt_trace_source_sha256_def
      sep04_canonical_topic_decimal_def sep04_mutant_topic_decimal_def)

ML \<open>
  val row_fact = @{thm receipt_preimage_matches_storage_return_and_final_event};
  val row_oracles = Thm_Deps.all_oracles [row_fact];
  val _ = if null row_oracles then () else
    error ("SEP-04 proof audit found " ^ string_of_int (length row_oracles) ^ " oracle dependencies");
  val audit_report =
    "status=PASS\n" ^
    "qualified_theorem=SEP_04_Receipt_Event_Binding.receipt_preimage_matches_storage_return_and_final_event\n" ^
    "oracle_dependency_count=0\n";
  val _ = Export.export \<^theory>
    \<^path_binding>\<open>erc-trust-sep-04/proof-trust.txt\<close> [XML.Text audit_report];
\<close>

end
