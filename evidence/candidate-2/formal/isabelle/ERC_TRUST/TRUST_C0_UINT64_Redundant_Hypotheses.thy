theory TRUST_C0_UINT64_Redundant_Hypotheses
  imports TRUST_C0_UINT160_Redundant_Hypotheses
begin

definition c0_uint64_mask_word :: c0_evm_word where
  "c0_uint64_mask_word = c0_uint_mask_word 64"

definition c0_uint64_accept_claim_sha256 :: string where
  "c0_uint64_accept_claim_sha256 = ''d82bfc0e26067ed8de9bee45c05fa7b59273fed1c8be2787983251837bf68943''"

definition c0_uint64_reject_claim_sha256 :: string where
  "c0_uint64_reject_claim_sha256 = ''204c504a7ef1bc39b7be64245ebb34f2da58cb3fc17216bc6f728dd16137eac6''"

theorem c0_uint64_claim_identities:
  "c0_uint64_accept_claim_sha256 = ''d82bfc0e26067ed8de9bee45c05fa7b59273fed1c8be2787983251837bf68943'' \<and>
   c0_uint64_reject_claim_sha256 = ''204c504a7ef1bc39b7be64245ebb34f2da58cb3fc17216bc6f728dd16137eac6''"
  by (simp add: c0_uint64_accept_claim_sha256_def c0_uint64_reject_claim_sha256_def)

theorem c0_uint64_and_uint_lower_bound:
  "0 \<le> uint (w AND c0_uint64_mask_word)"
  by (rule uint_ge_0)

theorem c0_uint64_and_uint_upper_bound:
  "uint (w AND c0_uint64_mask_word) \<le> (2 :: int) ^ 64 - 1"
proof -
  have h:
    "uint (w AND mask 64) \<le> (2 :: int) ^ 64 - 1"
    using c0_mask_and_uint_bounds[of w 64]
    by (rule conjunct2)
  then show ?thesis
    by (simp only: c0_uint64_mask_word_def c0_uint_mask_word_def)
qed

theorem c0_uint64_diagnostic_hypotheses_redundant:
  "0 \<le> uint (w AND c0_uint64_mask_word) \<and>
   uint (w AND c0_uint64_mask_word) \<le> (2 :: int) ^ 64 - 1"
proof
  show "0 \<le> uint (w AND c0_uint64_mask_word)"
    by (rule c0_uint64_and_uint_lower_bound)
  show "uint (w AND c0_uint64_mask_word) \<le> (2 :: int) ^ 64 - 1"
    by (rule c0_uint64_and_uint_upper_bound)
qed

end
