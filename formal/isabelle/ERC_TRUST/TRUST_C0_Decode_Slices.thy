(*
  Decoder guard library: exact length, fixed-width unsigned, and enum guards
  as separate guard steps, and the statement that canonical calldata is
  exactly the conjunction of those guards over the generated field positions.
*)

theory TRUST_C0_Decode_Slices
  imports TRUST_State_Abi_Normal_Form "HOL.Bit_Operations"
begin

datatype c0_calldata_shape = C0_Action | C0_Reversal

definition c0_shape_word_count :: "c0_calldata_shape \<Rightarrow> nat" where
  "c0_shape_word_count shape =
     (case shape of C0_Action \<Rightarrow> action_word_count | C0_Reversal \<Rightarrow> reversal_word_count)"

definition c0_shape_calldata_bytes :: "c0_calldata_shape \<Rightarrow> nat" where
  "c0_shape_calldata_bytes shape = 4 + 32 * c0_shape_word_count shape"

definition c0_exact_length_guard :: "c0_calldata_shape \<Rightarrow> nat \<Rightarrow> bool" where
  "c0_exact_length_guard shape bytes \<longleftrightarrow> bytes = c0_shape_calldata_bytes shape"

theorem c0_exact_length_gate_accepts_iff_shape_length:
  "c0_exact_length_guard C0_Action bytes \<longleftrightarrow> bytes = action_calldata_length"
  "c0_exact_length_guard C0_Reversal bytes \<longleftrightarrow> bytes = reversal_calldata_length"
  by (simp_all add: c0_exact_length_guard_def c0_shape_calldata_bytes_def
      c0_shape_word_count_def action_word_count_def action_calldata_length_def
      reversal_word_count_def reversal_calldata_length_def)

definition c0_word_at :: "nat list \<Rightarrow> nat \<Rightarrow> nat option" where
  "c0_word_at words index = (if index < length words then Some (words ! index) else None)"

theorem c0_word_at_encode_words:
  assumes "index < length words"
  shows "c0_word_at words index = Some (words ! index)"
  using assms by (simp add: c0_word_at_def)

definition c0_unsigned_guard :: "nat \<Rightarrow> nat \<Rightarrow> bool" where
  "c0_unsigned_guard bits word \<longleftrightarrow> take_bit bits word = word"

theorem c0_unsigned_guard_accepts_iff_word_fits:
  "c0_unsigned_guard bits word \<longleftrightarrow> word_fits bits word"
  by (simp add: c0_unsigned_guard_def word_fits_def take_bit_nat_eq_self_iff)

definition c0_enum_guard :: "nat \<Rightarrow> nat \<Rightarrow> bool" where
  "c0_enum_guard bound word \<longleftrightarrow> word < bound"

theorem c0_enum_guard_accepts_iff_below_bound:
  "c0_enum_guard bound word \<longleftrightarrow> word < bound"
  by (simp add: c0_enum_guard_def)

theorem c0_action_canonicality_is_exact_guard_conjunction:
  "canonical_action_words words \<longleftrightarrow>
     (length words = action_word_count \<and>
      (\<forall>(index, bound)\<in>set action_enum_words. c0_enum_guard bound (words ! index)) \<and>
      (\<forall>index\<in>set action_address_words. c0_unsigned_guard 160 (words ! index)) \<and>
      (\<forall>index\<in>set action_uint64_words. c0_unsigned_guard 64 (words ! index)) \<and>
      (\<forall>index\<in>set action_uint48_words. c0_unsigned_guard 48 (words ! index)))"
  by (simp add: canonical_action_words_def enums_fit_def words_fit_def c0_enum_guard_def
      c0_unsigned_guard_accepts_iff_word_fits)

theorem c0_reversal_canonicality_is_exact_guard_conjunction:
  "canonical_reversal_words words \<longleftrightarrow>
     (length words = reversal_word_count \<and>
      (\<forall>(index, bound)\<in>set reversal_enum_words. c0_enum_guard bound (words ! index)) \<and>
      (\<forall>index\<in>set reversal_address_words. c0_unsigned_guard 160 (words ! index)) \<and>
      (\<forall>index\<in>set reversal_uint64_words. c0_unsigned_guard 64 (words ! index)) \<and>
      (\<forall>index\<in>set reversal_uint48_words. c0_unsigned_guard 48 (words ! index)))"
  by (simp add: canonical_reversal_words_def enums_fit_def words_fit_def c0_enum_guard_def
      c0_unsigned_guard_accepts_iff_word_fits)

definition c0_reject_shell :: "'state \<Rightarrow> 'state \<times> 'log list" where
  "c0_reject_shell state = (state, [])"

theorem c0_reject_shell_reverts_and_preserves_frame:
  "fst (c0_reject_shell state) = state \<and> snd (c0_reject_shell state) = []"
  by (simp add: c0_reject_shell_def)

end
