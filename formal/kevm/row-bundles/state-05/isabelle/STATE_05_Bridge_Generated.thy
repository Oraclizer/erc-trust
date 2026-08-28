(* STATIC SKELETON. No generator or Isabelle build has been run. *)
theory STATE_05_Bridge_Generated
  imports ERC_TRUST.TRUST_Runtime_Bridge_Generated
begin

definition state05_case_terminal_selector :: nat where
  "state05_case_terminal_selector = 977408153"

definition state05_terminal_cases_base_slot :: nat where
  "state05_terminal_cases_base_slot = 22"

definition state05_calldata_byte_length :: nat where
  "state05_calldata_byte_length = 36"

record state05_runtime_view =
  state05_affected_terminal_word :: nat
  state05_other_terminal_word :: nat

definition state05_decode_bool_word :: "nat \<Rightarrow> bool" where
  "state05_decode_bool_word word \<longleftrightarrow> word = 1"

definition state05_case_terminal_output :: "state05_runtime_view \<Rightarrow> nat" where
  "state05_case_terminal_output view = state05_other_terminal_word view"

definition state05_getter_post :: "state05_runtime_view \<Rightarrow> state05_runtime_view" where
  "state05_getter_post view = view"

theorem generated_state05_storage_projection_constants:
  "(state05_case_terminal_selector, state05_terminal_cases_base_slot,
    state05_calldata_byte_length) = (977408153, 22, 36)"
  by (simp add: state05_case_terminal_selector_def
      state05_terminal_cases_base_slot_def state05_calldata_byte_length_def)

theorem generated_state05_distinct_case_observation:
  assumes "state05_affected_terminal_word view = 1"
      and "state05_other_terminal_word view = 0"
  shows "state05_decode_bool_word (state05_affected_terminal_word view)"
    and "\<not> state05_decode_bool_word (state05_other_terminal_word view)"
    and "state05_case_terminal_output view = 0"
    and "state05_getter_post view = view"
  using assms
  by (simp_all add: state05_decode_bool_word_def state05_case_terminal_output_def
      state05_getter_post_def)

end
