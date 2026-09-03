theory TRUST_C0_UINT48_Redundant_Hypotheses
  imports TRUST_C0_Runtime_Composition "HOL-Library.Word"
begin

unbundle bit_operations_syntax

type_synonym c0_evm_word = "256 word"

definition c0_uint_mask_word :: "nat \<Rightarrow> c0_evm_word" where
  "c0_uint_mask_word bits = mask bits"

definition c0_uint48_mask_word :: c0_evm_word where
  "c0_uint48_mask_word = c0_uint_mask_word 48"

definition c0_uint48_d1_claim_sha256 :: string where
  "c0_uint48_d1_claim_sha256 = ''a0472d75e6e9ef7a70e23958d2eb46b25d98b2af585a5489a741f4abbc01db04''"

theorem c0_uint48_d1_claim_identity:
  "c0_uint48_d1_claim_sha256 = ''a0472d75e6e9ef7a70e23958d2eb46b25d98b2af585a5489a741f4abbc01db04''"
  by (simp add: c0_uint48_d1_claim_sha256_def)

theorem c0_mask_and_uint_bounds:
  fixes w :: "256 word"
    and bits :: nat
  shows
    "0 \<le> uint (w AND mask bits) \<and>
     uint (w AND mask bits) \<le> (2 :: int) ^ bits - 1"
proof
  show "0 \<le> uint (w AND mask bits)"
    by (rule uint_ge_0)
  have h:
    "uint (w AND mask bits) < (2 :: int) ^ bits"
    by (rule and_mask_lt_2p)
  then show
    "uint (w AND mask bits) \<le> (2 :: int) ^ bits - 1"
    by (simp only: zle_diff1_eq)
qed

theorem c0_uint48_and_uint_lower_bound:
  "0 \<le> uint (w AND c0_uint48_mask_word)"
  by (rule uint_ge_0)

theorem c0_uint48_and_uint_upper_bound:
  "uint (w AND c0_uint48_mask_word) \<le> (2 :: int) ^ 48 - 1"
proof -
  have h:
    "uint (w AND mask 48) \<le> (2 :: int) ^ 48 - 1"
    using c0_mask_and_uint_bounds[of w 48]
    by (rule conjunct2)
  then show ?thesis
    by (simp only: c0_uint48_mask_word_def c0_uint_mask_word_def)
qed

theorem c0_uint48_d1_hypotheses_redundant:
  "0 \<le> uint (w AND c0_uint48_mask_word) \<and>
   uint (w AND c0_uint48_mask_word) \<le> (2 :: int) ^ 48 - 1"
proof
  show "0 \<le> uint (w AND c0_uint48_mask_word)"
    by (rule c0_uint48_and_uint_lower_bound)
  show "uint (w AND c0_uint48_mask_word) \<le> (2 :: int) ^ 48 - 1"
    by (rule c0_uint48_and_uint_upper_bound)
qed

end
