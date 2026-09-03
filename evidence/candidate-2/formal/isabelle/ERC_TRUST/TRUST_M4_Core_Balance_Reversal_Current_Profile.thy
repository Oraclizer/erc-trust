theory TRUST_M4_Core_Balance_Reversal_Current_Profile
  imports TRUST_M4_Action_Reversal_Row_Corollaries
begin

text \<open>
  The seventeen balance and reversal rows consume the terminal C4, C5, and C6 package layer.  This is a conditional composition contract.  It constructs
  no all-true certificate; the external fail-closed binder must supply exact
  package, product-inhabitant, and distinguishing-negative receipts.
\<close>

record core_balance_reversal_certificate =
  bal03_pass :: bool
  bal03_negative_pass :: bool
  bal04_pass :: bool
  bal04_negative_pass :: bool
  bal06_pass :: bool
  bal06_negative_pass :: bool
  bal07_pass :: bool
  bal07_negative_pass :: bool
  bal08_pass :: bool
  bal08_negative_pass :: bool
  bal09_pass :: bool
  bal09_negative_pass :: bool
  rev01_pass :: bool
  rev01_negative_pass :: bool
  rev02_pass :: bool
  rev02_negative_pass :: bool
  rev03_pass :: bool
  rev03_negative_pass :: bool
  rev04_pass :: bool
  rev04_negative_pass :: bool
  rev05_pass :: bool
  rev05_negative_pass :: bool
  rev06_pass :: bool
  rev06_negative_pass :: bool
  rev07_pass :: bool
  rev07_negative_pass :: bool
  rev08_pass :: bool
  rev08_negative_pass :: bool
  rev09_pass :: bool
  rev09_negative_pass :: bool
  rev10_pass :: bool
  rev10_negative_pass :: bool
  rev11_pass :: bool
  rev11_negative_pass :: bool

definition core_balance_reversal_certificate_complete :: "core_balance_reversal_certificate \<Rightarrow> bool" where
  "core_balance_reversal_certificate_complete certificate \<longleftrightarrow>
     bal03_pass certificate \<and>
     bal03_negative_pass certificate \<and>
     bal04_pass certificate \<and>
     bal04_negative_pass certificate \<and>
     bal06_pass certificate \<and>
     bal06_negative_pass certificate \<and>
     bal07_pass certificate \<and>
     bal07_negative_pass certificate \<and>
     bal08_pass certificate \<and>
     bal08_negative_pass certificate \<and>
     bal09_pass certificate \<and>
     bal09_negative_pass certificate \<and>
     rev01_pass certificate \<and>
     rev01_negative_pass certificate \<and>
     rev02_pass certificate \<and>
     rev02_negative_pass certificate \<and>
     rev03_pass certificate \<and>
     rev03_negative_pass certificate \<and>
     rev04_pass certificate \<and>
     rev04_negative_pass certificate \<and>
     rev05_pass certificate \<and>
     rev05_negative_pass certificate \<and>
     rev06_pass certificate \<and>
     rev06_negative_pass certificate \<and>
     rev07_pass certificate \<and>
     rev07_negative_pass certificate \<and>
     rev08_pass certificate \<and>
     rev08_negative_pass certificate \<and>
     rev09_pass certificate \<and>
     rev09_negative_pass certificate \<and>
     rev10_pass certificate \<and>
     rev10_negative_pass certificate \<and>
     rev11_pass certificate \<and>
     rev11_negative_pass certificate"

theorem bal03_current_profile_corollary:
  assumes "core_balance_reversal_certificate_complete certificate"
  shows "bal03_pass certificate \<and> bal03_negative_pass certificate"
  using assms by (simp add: core_balance_reversal_certificate_complete_def)

theorem bal04_current_profile_corollary:
  assumes "core_balance_reversal_certificate_complete certificate"
  shows "bal04_pass certificate \<and> bal04_negative_pass certificate"
  using assms by (simp add: core_balance_reversal_certificate_complete_def)

theorem bal06_current_profile_corollary:
  assumes "core_balance_reversal_certificate_complete certificate"
  shows "bal06_pass certificate \<and> bal06_negative_pass certificate"
  using assms by (simp add: core_balance_reversal_certificate_complete_def)

theorem bal07_current_profile_corollary:
  assumes "core_balance_reversal_certificate_complete certificate"
  shows "bal07_pass certificate \<and> bal07_negative_pass certificate"
  using assms by (simp add: core_balance_reversal_certificate_complete_def)

theorem bal08_current_profile_corollary:
  assumes "core_balance_reversal_certificate_complete certificate"
  shows "bal08_pass certificate \<and> bal08_negative_pass certificate"
  using assms by (simp add: core_balance_reversal_certificate_complete_def)

theorem bal09_current_profile_corollary:
  assumes "core_balance_reversal_certificate_complete certificate"
  shows "bal09_pass certificate \<and> bal09_negative_pass certificate"
  using assms by (simp add: core_balance_reversal_certificate_complete_def)

theorem rev01_current_profile_corollary:
  assumes "core_balance_reversal_certificate_complete certificate"
  shows "rev01_pass certificate \<and> rev01_negative_pass certificate"
  using assms by (simp add: core_balance_reversal_certificate_complete_def)

theorem rev02_current_profile_corollary:
  assumes "core_balance_reversal_certificate_complete certificate"
  shows "rev02_pass certificate \<and> rev02_negative_pass certificate"
  using assms by (simp add: core_balance_reversal_certificate_complete_def)

theorem rev03_current_profile_corollary:
  assumes "core_balance_reversal_certificate_complete certificate"
  shows "rev03_pass certificate \<and> rev03_negative_pass certificate"
  using assms by (simp add: core_balance_reversal_certificate_complete_def)

theorem rev04_current_profile_corollary:
  assumes "core_balance_reversal_certificate_complete certificate"
  shows "rev04_pass certificate \<and> rev04_negative_pass certificate"
  using assms by (simp add: core_balance_reversal_certificate_complete_def)

theorem rev05_current_profile_corollary:
  assumes "core_balance_reversal_certificate_complete certificate"
  shows "rev05_pass certificate \<and> rev05_negative_pass certificate"
  using assms by (simp add: core_balance_reversal_certificate_complete_def)

theorem rev06_current_profile_corollary:
  assumes "core_balance_reversal_certificate_complete certificate"
  shows "rev06_pass certificate \<and> rev06_negative_pass certificate"
  using assms by (simp add: core_balance_reversal_certificate_complete_def)

theorem rev07_current_profile_corollary:
  assumes "core_balance_reversal_certificate_complete certificate"
  shows "rev07_pass certificate \<and> rev07_negative_pass certificate"
  using assms by (simp add: core_balance_reversal_certificate_complete_def)

theorem rev08_current_profile_corollary:
  assumes "core_balance_reversal_certificate_complete certificate"
  shows "rev08_pass certificate \<and> rev08_negative_pass certificate"
  using assms by (simp add: core_balance_reversal_certificate_complete_def)

theorem rev09_current_profile_corollary:
  assumes "core_balance_reversal_certificate_complete certificate"
  shows "rev09_pass certificate \<and> rev09_negative_pass certificate"
  using assms by (simp add: core_balance_reversal_certificate_complete_def)

theorem rev10_current_profile_corollary:
  assumes "core_balance_reversal_certificate_complete certificate"
  shows "rev10_pass certificate \<and> rev10_negative_pass certificate"
  using assms by (simp add: core_balance_reversal_certificate_complete_def)

theorem rev11_current_profile_corollary:
  assumes "core_balance_reversal_certificate_complete certificate"
  shows "rev11_pass certificate \<and> rev11_negative_pass certificate"
  using assms by (simp add: core_balance_reversal_certificate_complete_def)
ML \<open>
  val core_balance_reversal_certificate_facts = @{thms
    bal03_current_profile_corollary
    bal04_current_profile_corollary
    bal06_current_profile_corollary
    bal07_current_profile_corollary
    bal08_current_profile_corollary
    bal09_current_profile_corollary
    rev01_current_profile_corollary
    rev02_current_profile_corollary
    rev03_current_profile_corollary
    rev04_current_profile_corollary
    rev05_current_profile_corollary
    rev06_current_profile_corollary
    rev07_current_profile_corollary
    rev08_current_profile_corollary
    rev09_current_profile_corollary
    rev10_current_profile_corollary
    rev11_current_profile_corollary};
  val core_balance_reversal_certificate_oracles = Thm_Deps.all_oracles core_balance_reversal_certificate_facts;
  val _ = if null core_balance_reversal_certificate_oracles then ()
    else error ("TRUST_M4_Core_Balance_Reversal_Current_Profile proof audit found oracle dependencies");
\<close>

end
