theory TRUST12_Obstruction_Proof_Audit
  imports TRUST_Accounting_Invariant_Obstruction
begin

ML \<open>
  val obstruction_facts =
    [@{thm native_initial_accounting_state_wf},
     @{thm move_balance_self},
     @{thm ordinary_self_transfer_stutters},
     @{thm closed_custody_has_zero_amount},
     @{thm custody_case_none_is_inactive},
     @{thm move_balance_preserves_sum},
     @{thm move_balance_preserves_balance_wf},
     @{thm ordinary_transfer_preserves_backing_bound},
     @{thm ordinary_transfer_preserves_accounting_state_wf},
     @{thm accounting_wf_allows_the_malformed_head},
     @{thm malformed_head_still_admits_a_freeze},
     @{thm accounting_wf_is_not_preserved_by_every_admitted_forward}];

  val obstruction_oracles = Thm_Deps.all_oracles obstruction_facts;

  val _ =
    if null obstruction_oracles
    then ()
    else error
      ("TRUST 1.2 obstruction audit found " ^
       string_of_int (length obstruction_oracles) ^ " oracle dependencies");

  val audit_report =
    "status=PASS\n" ^
    "explicit_root_count=12\n" ^
    "qualified_fact_count=12\n" ^
    "oracle_dependency_count=0\n";

  val _ =
    Export.export \<^theory>
      \<^path_binding>\<open>erc-trust/trust12-obstruction-proof-trust.txt\<close>
      [XML.Text audit_report];
\<close>

end
