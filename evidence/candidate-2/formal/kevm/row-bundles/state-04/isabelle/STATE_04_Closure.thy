theory STATE_04_Closure
  imports ERC_TRUST.TRUST_Compositional_State STATE_04_Bridge_Generated
begin

definition state04_retrieves ::
  "state04_runtime_view \<Rightarrow> trust_compositional_state \<Rightarrow> trust_address \<Rightarrow> bool"
where
  "state04_retrieves view st subject \<longleftrightarrow>
     state04_frozen_word view = frozen_targets st subject \<and>
     state04_restricted_word view = (if restriction_flags st subject then 1 else 0)"

theorem state04_overlay_pair_is_retrieved_without_loss:
  assumes left: "state04_retrieves left st subject"
      and right: "state04_retrieves right st subject"
  shows "state04_frozen_word left = state04_frozen_word right"
    and "state04_restricted_word left = state04_restricted_word right"
  using left right by (auto simp: state04_retrieves_def)

theorem freeze_and_restriction_are_independent:
  assumes retrieve: "state04_retrieves view st subject"
      and frozen: "0 < frozen_targets st subject"
      and restricted: "restriction_flags st subject"
  defines "view' \<equiv> state04_getter_post view"
  shows "state04_retrieves view' st subject"
    and "state04_get_frozen_output view = frozen_targets st subject"
    and "state04_decode_bool_word (state04_restricted_word view)"
    and "state04_frozen_word view' = frozen_targets st subject"
    and "state04_restricted_word view' = 1"
    and "foundation_projection st subject case_id = None"
proof -
  show "state04_retrieves view' st subject"
    using retrieve by (simp add: view'_def state04_getter_post_def)
  show "state04_get_frozen_output view = frozen_targets st subject"
    using retrieve by (simp add: state04_retrieves_def state04_get_frozen_output_def)
  show "state04_decode_bool_word (state04_restricted_word view)"
    using retrieve restricted
    by (simp add: state04_retrieves_def state04_decode_bool_word_def)
  show "state04_frozen_word view' = frozen_targets st subject"
    using retrieve by (simp add: view'_def state04_getter_post_def state04_retrieves_def)
  show "state04_restricted_word view' = 1"
    using retrieve restricted
    by (simp add: view'_def state04_getter_post_def state04_retrieves_def)
  show "foundation_projection st subject case_id = None"
    using composite_overlay_has_no_foundation_projection[OF frozen restricted] .
qed

end
