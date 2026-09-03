(* STATIC SKELETON. This theory has not been built. *)
theory STATE_05_Target
  imports ERC_TRUST.TRUST_Transaction_Refinement STATE_05_Bridge_Generated
begin

definition state05_terminalize ::
  "trust_compositional_state \<Rightarrow> trust_case_id \<Rightarrow> trust_compositional_state"
where
  "state05_terminalize state affected_case =
     state\<lparr>terminal_cases := (terminal_cases state)(affected_case := True)\<rparr>"

theorem state05_terminal_update_is_case_local:
  assumes "affected_case \<noteq> other_case"
  shows "terminal_cases (state05_terminalize state affected_case) affected_case"
    and "terminal_cases (state05_terminalize state affected_case) other_case =
         terminal_cases state other_case"
  using assms by (simp_all add: state05_terminalize_def)

theorem state05_case_scope_target:
  assumes distinct: "affected_case \<noteq> other_case"
      and affected_case: "forward_case affected_command = affected_case"
      and other_case: "forward_case other_command = other_case"
      and same_subject:
        "forward_subject affected_command = forward_subject other_command"
      and other_previously_admissible: "forward_shape_wf state other_command"
  defines "post \<equiv> state05_terminalize state affected_case"
  shows "\<not> forward_shape_wf post affected_command"
    and "forward_shape_wf post other_command"
  using assms
  by (auto simp: post_def state05_terminalize_def forward_shape_wf_def)

text \<open>
  This target states both halves of the registry wording: the affected case is
  blocked, while an otherwise shape-admissible command for the same subject and
  a distinct case remains shape-admissible. It does not cite or reuse the
  existing one-case retrieve theorem as discharge credit. Runtime action-level
  links, Isabelle execution, KEVM evidence, and replay remain open.
\<close>

end
