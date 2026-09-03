(* STATIC SKELETON. This theory has not been built. *)
theory STATE_06_Closure
  imports ERC_TRUST.TRUST_Compositional_State STATE_06_Bridge_Generated
begin

definition state06_retrieves ::
  "state06_runtime_view \<Rightarrow> trust_compositional_state \<Rightarrow> bool"
where
  "state06_retrieves view state \<longleftrightarrow>
     (state06_decode_bool_word (state06_nonce_word view) \<longleftrightarrow>
      state06_runtime_nonce_key view \<in> compositional_consumed_nonces state)"

theorem state06_nonce_tuple_projection_target:
  assumes retrieve: "state06_retrieves view state"
      and authority: "state06_authority_ref view = authority_ref"
      and epoch: "state06_authority_epoch view = authority_epoch"
      and nonce: "state06_nonce view = nonce"
  shows "state06_decode_bool_word (state06_nonce_word view) \<longleftrightarrow>
         (authority_ref, authority_epoch, nonce) \<in>
           compositional_consumed_nonces state"
  using retrieve authority epoch nonce
  by (simp add: state06_retrieves_def state06_runtime_nonce_key_def)

theorem state06_positive_runtime_view_retrieves_exact_triple:
  assumes retrieve: "state06_retrieves view state"
      and authority: "state06_authority_ref view = authority_ref"
      and epoch: "state06_authority_epoch view = authority_epoch"
      and nonce: "state06_nonce view = nonce"
      and used: "state06_nonce_word view = 1"
  shows "(authority_ref, authority_epoch, nonce) \<in>
         compositional_consumed_nonces state"
  using state06_nonce_tuple_projection_target[OF retrieve authority epoch nonce] used
  by (simp add: state06_decode_bool_word_def)

text \<open>
  These row-local targets bind all three runtime coordinates to one exact
  nonce-key tuple. They do not cite the existing whole-set retrieve theorem as
  discharge credit. Runtime proof, Isabelle execution, negative evidence,
  replay, and coordinator binding remain open.
\<close>

end
