theory ACT_01_Full_Transaction
  imports ERC_TRUST.TRUST_End_To_End_Composition ACT_01_Bridge_Generated
begin

theorem act01_full_successful_transaction_refines:
  assumes runtime: "runtime_execution execution"
      and alpha: "alpha_transaction manifest bridge execution
        (runtime_abstraction execution)"
      and applied:
        "abstraction_outcome (runtime_abstraction execution) =
          TRUST_Abstract_Applied"
      and command:
        "abstraction_command (runtime_abstraction execution) =
          Some (TRUST_Forward forward)"
      and forward_witness:
        "abstraction_forward_witness (runtime_abstraction execution) =
          Some witness"
      and no_reversal:
        "abstraction_reversal_witness (runtime_abstraction execution) = None"
      and freeze: "forward_action forward = Legal_Freeze"
      and receipt:
        "abstraction_receipt (runtime_abstraction execution) = Some receipt"
  shows
    "frozen_targets
       (abstraction_post_state (runtime_abstraction execution))
       (forward_subject forward) = forward_amount forward"
    "transaction_raw_logs execution ~= []"
    "last (transaction_raw_logs execution) =
       bridge_receipt_log bridge receipt"
    "EX payload.
       transaction_result execution = TRUST_Return_Success payload &
       bridge_return_receipt_hash bridge payload =
         Some (compositional_receipt_hash receipt)"
proof -
  have expected:
    "expected_success_state (runtime_abstraction execution) =
       Some (abstraction_post_state (runtime_abstraction execution))"
    using alpha applied
      TRUST_Transaction_Refinement.successful_transaction_uses_abstract_success_state
    by blast
  have state_eq:
    "abstraction_post_state (runtime_abstraction execution) =
       forward_success_state
         (abstraction_pre_state (runtime_abstraction execution))
         forward witness"
    using expected command forward_witness no_reversal
    by (simp add: expected_success_state_def)
  show target:
    "frozen_targets
       (abstraction_post_state (runtime_abstraction execution))
       (forward_subject forward) = forward_amount forward"
    using state_eq freeze TRUST_Transaction_Refinement.freeze_success_forward
    by simp
  have logs:
    "transaction_raw_logs execution ~= [] &
     last (transaction_raw_logs execution) =
       bridge_receipt_log bridge receipt"
    using TRUST_Transaction_Refinement.success_has_final_canonical_receipt_event[OF alpha applied receipt] .
  then show "transaction_raw_logs execution ~= []" by blast
  from logs show
    "last (transaction_raw_logs execution) =
       bridge_receipt_log bridge receipt"
    by blast
  have canonical:
    "canonical_receipt_trace bridge execution
       (runtime_abstraction execution)"
    using alpha applied by (auto simp: alpha_transaction_def)
  show "EX payload.
      transaction_result execution = TRUST_Return_Success payload &
      bridge_return_receipt_hash bridge payload =
        Some (compositional_receipt_hash receipt)"
    using canonical receipt
    by (cases "transaction_result execution";
        auto simp: canonical_receipt_trace_def)
qed

text \<open>
  The named theorem composes the existing successful FREEZE state theorem with
  the canonical receipt-return and final-event theorem. Exact sender nonce,
  EVM finalization, storage frame, and executable negative adequacy remain the
  responsibility of the two exact-runtime K claims identified by the generated
  bridge. The theorem does not turn a parse-only or feasibility receipt into
  runtime proof credit.
\<close>

ML \<open>
  val act01_facts = @{thms act01_full_successful_transaction_refines};
  val act01_oracles = Thm_Deps.all_oracles act01_facts;
  val _ = if null act01_oracles then ()
    else error ("ACT-01 proof audit found " ^ string_of_int (length act01_oracles) ^ " oracle dependencies");
  val act01_audit_report =
    "status=PASS\n" ^
    "qualified_theorem=ACT_01_Full_Transaction.act01_full_successful_transaction_refines\n" ^
    "oracle_dependency_count=0\n";
  val _ = Export.export \<^theory>
    \<^path_binding>\<open>erc-trust-act-01/proof-trust.txt\<close>
    [XML.Text act01_audit_report];
\<close>

end
