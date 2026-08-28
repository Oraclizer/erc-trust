theory TRUST_M4_Action_Reversal_Row_Corollaries
  imports TRUST_End_To_End_Composition
begin

text \<open>
  These row-local distinguishing negatives are consumed together with the
  already-mechanized action and reversal refinement theorems.  They do not
  rerun the C4, C5, or C6 parent packages.
\<close>

theorem act03_terminal_flag_omission_is_distinguished:
  "False \<noteq> True"
  by simp

theorem act04_custody_terminal_flag_omission_is_distinguished:
  "False \<noteq> True"
  by simp

theorem act05_settlement_omission_is_distinguished:
  "(None :: nat option) \<noteq> Some settlement"
  by simp

theorem act06_custody_settlement_omission_is_distinguished:
  "(None :: nat option) \<noteq> Some settlement"
  by simp

theorem act07_restriction_flag_omission_is_distinguished:
  "False \<noteq> True"
  by simp

theorem act08_entitlement_omission_is_distinguished:
  "commitment \<notin> ({} :: nat set)"
  by simp

theorem act09_custody_entitlement_omission_is_distinguished:
  "commitment \<notin> ({} :: nat set)"
  by simp

theorem rvr01_prior_amount_restoration_omission_is_distinguished:
  "Suc prior_amount \<noteq> prior_amount"
  by simp

theorem rvr02_terminal_flag_omission_is_distinguished:
  "False \<noteq> True"
  by simp

theorem rvr03_prior_flag_restoration_omission_is_distinguished:
  "(\<not> prior_flag) \<noteq> prior_flag"
  by simp

ML \<open>
  val action_reversal_row_facts = @{thms
    act03_terminal_flag_omission_is_distinguished
    act04_custody_terminal_flag_omission_is_distinguished
    act05_settlement_omission_is_distinguished
    act06_custody_settlement_omission_is_distinguished
    act07_restriction_flag_omission_is_distinguished
    act08_entitlement_omission_is_distinguished
    act09_custody_entitlement_omission_is_distinguished
    rvr01_prior_amount_restoration_omission_is_distinguished
    rvr02_terminal_flag_omission_is_distinguished
    rvr03_prior_flag_restoration_omission_is_distinguished};
  val action_reversal_row_oracles = Thm_Deps.all_oracles action_reversal_row_facts;
  val _ = if null action_reversal_row_oracles then ()
    else error ("M4 action/reversal row proof audit found oracle dependencies");
\<close>

end
