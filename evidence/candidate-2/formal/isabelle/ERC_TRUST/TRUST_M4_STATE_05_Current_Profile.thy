theory TRUST_M4_STATE_05_Current_Profile
  imports TRUST_Reusable_Summaries
begin

definition state05_terminal_forward_action :: "legal_action_kind \<Rightarrow> bool" where
  "state05_terminal_forward_action action \<longleftrightarrow>
     action = Legal_Confiscate \<or>
     action = Legal_Liquidate \<or>
     action = Legal_Recover"

theorem case_terminality_is_scoped:
  assumes "state05_terminal_forward_action (forward_action command)"
  shows "terminal_cases (forward_success_state state command witness)
           (forward_case command) \<and>
         (\<forall>other_case. other_case \<noteq> forward_case command \<longrightarrow>
           terminal_cases (forward_success_state state command witness) other_case =
           terminal_cases state other_case)"
  using assms
  by (cases "forward_action command")
     (auto simp: state05_terminal_forward_action_def forward_success_state_def
       base_forward_success_def Let_def)

definition state05_global_terminal_mutant ::
  "trust_compositional_state \<Rightarrow> trust_case_id \<Rightarrow> trust_case_id \<Rightarrow> bool"
where
  "state05_global_terminal_mutant state terminal_case observed_case =
     terminal_cases state terminal_case"

theorem state05_global_terminal_mutant_is_distinguished:
  assumes "terminal_cases state terminal_case"
      and "\<not> terminal_cases state other_case"
  shows "state05_global_terminal_mutant state terminal_case other_case \<noteq>
         terminal_cases state other_case"
  using assms by (simp add: state05_global_terminal_mutant_def)

ML \<open>
  val state05_current_facts = @{thms
    case_terminality_is_scoped
    state05_global_terminal_mutant_is_distinguished};
  val state05_current_oracles = Thm_Deps.all_oracles state05_current_facts;
  val _ = if null state05_current_oracles then ()
    else error ("STATE-05 current-profile proof audit found oracle dependencies");
\<close>

end
