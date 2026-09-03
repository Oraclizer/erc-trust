(* STATIC SKELETON. No generator or Isabelle build has been run. *)
theory STATE_06_Bridge_Generated
  imports ERC_TRUST.TRUST_Runtime_Bridge_Generated
begin

definition state06_nonce_used_selector :: nat where
  "state06_nonce_used_selector = 365666371"

definition state06_used_nonces_base_slot :: nat where
  "state06_used_nonces_base_slot = 12"

definition state06_calldata_byte_length :: nat where
  "state06_calldata_byte_length = 100"

record state06_runtime_view =
  state06_authority_ref :: nat
  state06_authority_epoch :: nat
  state06_nonce :: nat
  state06_nonce_word :: nat

definition state06_runtime_nonce_key :: "state06_runtime_view \<Rightarrow> trust_nonce_key" where
  "state06_runtime_nonce_key view =
     (state06_authority_ref view, state06_authority_epoch view, state06_nonce view)"

definition state06_decode_bool_word :: "nat \<Rightarrow> bool" where
  "state06_decode_bool_word word \<longleftrightarrow> word = 1"

definition state06_nonce_used_output :: "state06_runtime_view \<Rightarrow> nat" where
  "state06_nonce_used_output view = state06_nonce_word view"

definition state06_getter_post :: "state06_runtime_view \<Rightarrow> state06_runtime_view" where
  "state06_getter_post view = view"

theorem generated_state06_projection_constants:
  "(state06_nonce_used_selector, state06_used_nonces_base_slot,
    state06_calldata_byte_length) = (365666371, 12, 100)"
  by (simp add: state06_nonce_used_selector_def state06_used_nonces_base_slot_def
      state06_calldata_byte_length_def)

theorem generated_state06_exact_tuple_observation:
  assumes "state06_authority_ref view = authority_ref"
      and "state06_authority_epoch view = authority_epoch"
      and "state06_nonce view = nonce"
      and "state06_nonce_word view = 1"
  shows "state06_runtime_nonce_key view = (authority_ref, authority_epoch, nonce)"
    and "state06_decode_bool_word (state06_nonce_word view)"
    and "state06_nonce_used_output view = 1"
    and "state06_getter_post view = view"
  using assms
  by (simp_all add: state06_runtime_nonce_key_def state06_decode_bool_word_def
      state06_nonce_used_output_def state06_getter_post_def)

end
