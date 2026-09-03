(*
  Fixed-width decoder guards over 256-bit words.

  The compiled decoder masks a narrow field and compares the masked value with
  the original word.  These theorems state, for every 256-bit word, the bounds
  of the masked value that such a comparison relies on.  They are facts about
  the word library alone; they do not bind any runtime, program counter, or
  external proof claim.
*)

theory TRUST_Decoder_Guard_Words
  imports TRUST_C0_Decode_Slices "HOL-Library.Word"
begin

unbundle bit_operations_syntax

type_synonym trust_evm_word = "256 word"

definition guard_mask_word :: "nat \<Rightarrow> trust_evm_word" where
  "guard_mask_word bits = mask bits"

theorem guard_mask_and_uint_bounds:
  fixes w :: trust_evm_word
    and bits :: nat
  shows
    "0 \<le> uint (w AND mask bits) \<and>
     uint (w AND mask bits) \<le> (2 :: int) ^ bits - 1"
proof
  show "0 \<le> uint (w AND mask bits)"
    by (rule uint_ge_0)
  have "uint (w AND mask bits) < (2 :: int) ^ bits"
    by (rule and_mask_lt_2p)
  then show "uint (w AND mask bits) \<le> (2 :: int) ^ bits - 1"
    by (simp only: zle_diff1_eq)
qed

theorem decoder_uint48_guard_hypotheses_redundant:
  fixes w :: trust_evm_word
  shows "0 \<le> uint (w AND guard_mask_word 48) \<and>
         uint (w AND guard_mask_word 48) \<le> (2 :: int) ^ 48 - 1"
  using guard_mask_and_uint_bounds[of w 48] by (simp only: guard_mask_word_def)

theorem decoder_uint64_guard_hypotheses_redundant:
  fixes w :: trust_evm_word
  shows "0 \<le> uint (w AND guard_mask_word 64) \<and>
         uint (w AND guard_mask_word 64) \<le> (2 :: int) ^ 64 - 1"
  using guard_mask_and_uint_bounds[of w 64] by (simp only: guard_mask_word_def)

theorem decoder_uint160_guard_hypotheses_redundant:
  fixes w :: trust_evm_word
  shows "0 \<le> uint (w AND guard_mask_word 160) \<and>
         uint (w AND guard_mask_word 160) \<le> (2 :: int) ^ 160 - 1"
  using guard_mask_and_uint_bounds[of w 160] by (simp only: guard_mask_word_def)

theorem masked_word_satisfies_unsigned_guard:
  fixes w :: trust_evm_word
  shows "word_fits bits (unat (w AND mask bits))"
proof -
  have "uint (w AND mask bits) < int (2 ^ bits)"
    using and_mask_lt_2p[of w bits] by (simp only: of_nat_power of_nat_numeral)
  then have "int (unat (w AND mask bits)) < int (2 ^ bits)"
    by (simp only: uint_nat)
  then show ?thesis
    unfolding word_fits_def by (rule of_nat_less_imp_less)
qed

end
