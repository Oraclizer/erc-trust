theory TRUST_M4_STATE_04_Current_Profile
  imports TRUST_Reusable_Summaries
begin

text \<open>
  Current-profile row corollaries consume the already-qualified reusable
  package layer.  They do not rerun or restate the parent runtime proofs.
\<close>

theorem state04_overlay_inhabited:
  "\<exists>overlay.
     frozen_targets overlay account = Suc amount \<and>
     restriction_flags overlay account"
  by (rule exI[of _
        "state\<lparr>
           frozen_targets := (frozen_targets state)(account := Suc amount),
           restriction_flags := (restriction_flags state)(account := True)
         \<rparr>"])
     simp

theorem freeze_preserves_restriction_overlay:
  assumes "forward_action freeze_command = Legal_Freeze"
  shows "restriction_flags
           (forward_success_state state freeze_command freeze_witness) =
         restriction_flags state"
  using assms
  by (simp add: forward_success_state_def base_forward_success_def Let_def)

theorem restriction_preserves_freeze_overlay:
  assumes "forward_action restriction_command = Legal_Restrict"
  shows "frozen_targets
           (forward_success_state state restriction_command restriction_witness) =
         frozen_targets state"
  using assms
  by (simp add: forward_success_state_def base_forward_success_def Let_def)

theorem freeze_and_restriction_are_independent:
  assumes "forward_action freeze_command = Legal_Freeze"
      and "forward_action restriction_command = Legal_Restrict"
      and "forward_subject restriction_command = forward_subject freeze_command"
  shows "let frozen_state =
           forward_success_state state freeze_command freeze_witness;
         combined_state =
           forward_success_state frozen_state restriction_command restriction_witness
       in frozen_targets combined_state (forward_subject freeze_command) =
            forward_amount freeze_command \<and>
          restriction_flags combined_state (forward_subject freeze_command)"
proof -
  let ?frozen_state =
    "forward_success_state state freeze_command freeze_witness"
  let ?combined_state =
    "forward_success_state ?frozen_state restriction_command restriction_witness"
  have frozen:
    "frozen_targets ?frozen_state (forward_subject freeze_command) =
       forward_amount freeze_command"
    using freeze_success_forward assms(1) by blast
  have frozen_preserved:
    "frozen_targets ?combined_state = frozen_targets ?frozen_state"
    using restriction_preserves_freeze_overlay assms(2) by blast
  have restricted:
    "restriction_flags ?combined_state (forward_subject restriction_command)"
    using restrict_success_forward assms(2) by blast
  show ?thesis
    using frozen frozen_preserved restricted assms(3) by simp
qed

definition state04_conflated_frozen_observation ::
  "trust_compositional_state \<Rightarrow> trust_address \<Rightarrow> nat"
where
  "state04_conflated_frozen_observation state account =
     (if restriction_flags state account then 0 else frozen_targets state account)"

theorem state04_conflated_projection_is_distinguished:
  assumes "frozen_targets state account > 0"
      and "restriction_flags state account"
  shows "state04_conflated_frozen_observation state account \<noteq>
         frozen_targets state account"
  using assms by (simp add: state04_conflated_frozen_observation_def)

ML \<open>
  val state04_current_facts = @{thms
    state04_overlay_inhabited
    freeze_preserves_restriction_overlay
    restriction_preserves_freeze_overlay
    freeze_and_restriction_are_independent
    state04_conflated_projection_is_distinguished};
  val state04_current_oracles = Thm_Deps.all_oracles state04_current_facts;
  val _ = if null state04_current_oracles then ()
    else error ("STATE-04 current-profile proof audit found oracle dependencies");
\<close>

end
