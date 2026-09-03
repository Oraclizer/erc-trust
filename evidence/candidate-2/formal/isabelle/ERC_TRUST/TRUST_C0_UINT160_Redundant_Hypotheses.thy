theory TRUST_C0_UINT160_Redundant_Hypotheses
  imports TRUST_C0_UINT48_Redundant_Hypotheses
begin

definition c0_uint160_mask_word :: c0_evm_word where
  "c0_uint160_mask_word = c0_uint_mask_word 160"

definition c0_uint160_accept_claim_sha256 :: string where
  "c0_uint160_accept_claim_sha256 = ''0defcd131176c202bf4757f9582821de04d386f5465e21e9040dcc957a3117e4''"

definition c0_uint160_reject_d1_claim_sha256 :: string where
  "c0_uint160_reject_d1_claim_sha256 = ''e5bc848d7263e4ebb2c66ddc0f7f416e04a27d236c0cd8b50491900b6bc4ec41''"

theorem c0_uint160_claim_identities:
  "c0_uint160_accept_claim_sha256 = ''0defcd131176c202bf4757f9582821de04d386f5465e21e9040dcc957a3117e4'' \<and>
   c0_uint160_reject_d1_claim_sha256 = ''e5bc848d7263e4ebb2c66ddc0f7f416e04a27d236c0cd8b50491900b6bc4ec41''"
  by (simp add: c0_uint160_accept_claim_sha256_def c0_uint160_reject_d1_claim_sha256_def)

theorem c0_uint160_and_uint_lower_bound:
  "0 \<le> uint (w AND c0_uint160_mask_word)"
  by (rule uint_ge_0)

theorem c0_uint160_and_uint_upper_bound:
  "uint (w AND c0_uint160_mask_word) \<le> (2 :: int) ^ 160 - 1"
proof -
  have h:
    "uint (w AND mask 160) \<le> (2 :: int) ^ 160 - 1"
    using c0_mask_and_uint_bounds[of w 160]
    by (rule conjunct2)
  then show ?thesis
    by (simp only: c0_uint160_mask_word_def c0_uint_mask_word_def)
qed

theorem c0_uint160_d1_hypotheses_redundant:
  "0 \<le> uint (w AND c0_uint160_mask_word) \<and>
   uint (w AND c0_uint160_mask_word) \<le> (2 :: int) ^ 160 - 1"
proof
  show "0 \<le> uint (w AND c0_uint160_mask_word)"
    by (rule c0_uint160_and_uint_lower_bound)
  show "uint (w AND c0_uint160_mask_word) \<le> (2 :: int) ^ 160 - 1"
    by (rule c0_uint160_and_uint_upper_bound)
qed

end
