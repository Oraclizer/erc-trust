theory TRUST_C0_Decode_Slices
  imports TRUST_State_Abi_Normal_Form "HOL.Bit_Operations"
begin

datatype c0_calldata_shape = C0_Action | C0_Reversal

definition c0_shape_word_count :: "c0_calldata_shape => nat" where
  "c0_shape_word_count shape = (case shape of C0_Action => 21 | C0_Reversal => 9)"

definition c0_shape_calldata_bytes :: "c0_calldata_shape => nat" where
  "c0_shape_calldata_bytes shape = 4 + 32 * c0_shape_word_count shape"

definition c0_exact_length_guard :: "c0_calldata_shape => nat => bool" where
  "c0_exact_length_guard shape bytes = (bytes = c0_shape_calldata_bytes shape)"

theorem c0_exact_length_gate_accepts_iff_shape_length:
  "c0_exact_length_guard C0_Action bytes = (bytes = 676)"
  "c0_exact_length_guard C0_Reversal bytes = (bytes = 292)"
  by (simp_all add: c0_exact_length_guard_def c0_shape_calldata_bytes_def
      c0_shape_word_count_def)

definition c0_word_at :: "nat list => nat => nat option" where
  "c0_word_at words index = (if index < length words then Some (words ! index) else None)"

theorem c0_word_at_encode_words:
  assumes "index < length words"
  shows "c0_word_at words index = Some (words ! index)"
  using assms by (simp add: c0_word_at_def)

definition c0_unsigned_guard :: "nat => nat => bool" where
  "c0_unsigned_guard bits word = (take_bit bits word = word)"

theorem c0_unsigned_guard_accepts_iff_word_fits:
  "c0_unsigned_guard bits word = (word_fits bits word)"
  by (simp add: c0_unsigned_guard_def word_fits_def take_bit_nat_eq_self_iff)

definition c0_enum_guard :: "nat => nat => bool" where
  "c0_enum_guard bound word = (word < bound)"

theorem c0_enum_guard_accepts_iff_below_bound:
  "c0_enum_guard bound word = (word < bound)"
  by (simp add: c0_enum_guard_def)

theorem c0_action_canonicality_is_exact_guard_conjunction:
  "canonical_action_words words =
     (length words = 21 &
      c0_enum_guard 6 (words ! 2) &
      c0_unsigned_guard 160 (words ! 3) &
      c0_unsigned_guard 160 (words ! 4) &
      c0_unsigned_guard 160 (words ! 5) &
      c0_unsigned_guard 160 (words ! 6) &
      c0_unsigned_guard 64 (words ! 16) &
      c0_unsigned_guard 64 (words ! 17) &
      c0_unsigned_guard 48 (words ! 19) &
      c0_unsigned_guard 48 (words ! 20))"
  by (simp add: canonical_action_words_def c0_enum_guard_def
      c0_unsigned_guard_accepts_iff_word_fits)

theorem c0_reversal_canonicality_is_exact_guard_conjunction:
  "canonical_reversal_words words =
     (length words = 9 &
      c0_enum_guard 3 (words ! 3) &
      c0_unsigned_guard 64 (words ! 5) &
      c0_unsigned_guard 48 (words ! 7) &
      c0_unsigned_guard 48 (words ! 8))"
  by (simp add: canonical_reversal_words_def c0_enum_guard_def
      c0_unsigned_guard_accepts_iff_word_fits)

definition c0_reject_shell :: "'state => 'state * 'log list" where
  "c0_reject_shell state = (state, [])"

theorem c0_reject_shell_reverts_and_preserves_frame:
  "fst (c0_reject_shell state) = state & snd (c0_reject_shell state) = []"
  by (simp add: c0_reject_shell_def)

end
