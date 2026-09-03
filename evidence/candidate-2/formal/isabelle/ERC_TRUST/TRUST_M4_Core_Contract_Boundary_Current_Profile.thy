theory TRUST_M4_Core_Contract_Boundary_Current_Profile
  imports TRUST_M4_Action_Reversal_Row_Corollaries
begin

text \<open>
  The eighteen ABI, authorization, failure, external-route, transaction-shell, and artifact-link rows consume the terminal C0, C1, C2, C3, and C6 package layer.  This is a conditional composition contract.  It constructs
  no all-true certificate; the external fail-closed binder must supply exact
  package, product-inhabitant, and distinguishing-negative receipts.
\<close>

record core_contract_boundary_certificate =
  abi05_pass :: bool
  abi05_negative_pass :: bool
  auth01_pass :: bool
  auth01_negative_pass :: bool
  auth02_pass :: bool
  auth02_negative_pass :: bool
  auth03_pass :: bool
  auth03_negative_pass :: bool
  auth04_pass :: bool
  auth04_negative_pass :: bool
  auth05_pass :: bool
  auth05_negative_pass :: bool
  fail01_pass :: bool
  fail01_negative_pass :: bool
  fail02_pass :: bool
  fail02_negative_pass :: bool
  fail03_pass :: bool
  fail03_negative_pass :: bool
  fail04_pass :: bool
  fail04_negative_pass :: bool
  fail08_pass :: bool
  fail08_negative_pass :: bool
  ext01_pass :: bool
  ext01_negative_pass :: bool
  ext02_pass :: bool
  ext02_negative_pass :: bool
  ext03_pass :: bool
  ext03_negative_pass :: bool
  sep02_pass :: bool
  sep02_negative_pass :: bool
  sep04_pass :: bool
  sep04_negative_pass :: bool
  art06_pass :: bool
  art06_negative_pass :: bool
  art07_pass :: bool
  art07_negative_pass :: bool

definition core_contract_boundary_certificate_complete :: "core_contract_boundary_certificate \<Rightarrow> bool" where
  "core_contract_boundary_certificate_complete certificate \<longleftrightarrow>
     abi05_pass certificate \<and>
     abi05_negative_pass certificate \<and>
     auth01_pass certificate \<and>
     auth01_negative_pass certificate \<and>
     auth02_pass certificate \<and>
     auth02_negative_pass certificate \<and>
     auth03_pass certificate \<and>
     auth03_negative_pass certificate \<and>
     auth04_pass certificate \<and>
     auth04_negative_pass certificate \<and>
     auth05_pass certificate \<and>
     auth05_negative_pass certificate \<and>
     fail01_pass certificate \<and>
     fail01_negative_pass certificate \<and>
     fail02_pass certificate \<and>
     fail02_negative_pass certificate \<and>
     fail03_pass certificate \<and>
     fail03_negative_pass certificate \<and>
     fail04_pass certificate \<and>
     fail04_negative_pass certificate \<and>
     fail08_pass certificate \<and>
     fail08_negative_pass certificate \<and>
     ext01_pass certificate \<and>
     ext01_negative_pass certificate \<and>
     ext02_pass certificate \<and>
     ext02_negative_pass certificate \<and>
     ext03_pass certificate \<and>
     ext03_negative_pass certificate \<and>
     sep02_pass certificate \<and>
     sep02_negative_pass certificate \<and>
     sep04_pass certificate \<and>
     sep04_negative_pass certificate \<and>
     art06_pass certificate \<and>
     art06_negative_pass certificate \<and>
     art07_pass certificate \<and>
     art07_negative_pass certificate"

theorem abi05_current_profile_corollary:
  assumes "core_contract_boundary_certificate_complete certificate"
  shows "abi05_pass certificate \<and> abi05_negative_pass certificate"
  using assms by (simp add: core_contract_boundary_certificate_complete_def)

theorem auth01_current_profile_corollary:
  assumes "core_contract_boundary_certificate_complete certificate"
  shows "auth01_pass certificate \<and> auth01_negative_pass certificate"
  using assms by (simp add: core_contract_boundary_certificate_complete_def)

theorem auth02_current_profile_corollary:
  assumes "core_contract_boundary_certificate_complete certificate"
  shows "auth02_pass certificate \<and> auth02_negative_pass certificate"
  using assms by (simp add: core_contract_boundary_certificate_complete_def)

theorem auth03_current_profile_corollary:
  assumes "core_contract_boundary_certificate_complete certificate"
  shows "auth03_pass certificate \<and> auth03_negative_pass certificate"
  using assms by (simp add: core_contract_boundary_certificate_complete_def)

theorem auth04_current_profile_corollary:
  assumes "core_contract_boundary_certificate_complete certificate"
  shows "auth04_pass certificate \<and> auth04_negative_pass certificate"
  using assms by (simp add: core_contract_boundary_certificate_complete_def)

theorem auth05_current_profile_corollary:
  assumes "core_contract_boundary_certificate_complete certificate"
  shows "auth05_pass certificate \<and> auth05_negative_pass certificate"
  using assms by (simp add: core_contract_boundary_certificate_complete_def)

theorem fail01_current_profile_corollary:
  assumes "core_contract_boundary_certificate_complete certificate"
  shows "fail01_pass certificate \<and> fail01_negative_pass certificate"
  using assms by (simp add: core_contract_boundary_certificate_complete_def)

theorem fail02_current_profile_corollary:
  assumes "core_contract_boundary_certificate_complete certificate"
  shows "fail02_pass certificate \<and> fail02_negative_pass certificate"
  using assms by (simp add: core_contract_boundary_certificate_complete_def)

theorem fail03_current_profile_corollary:
  assumes "core_contract_boundary_certificate_complete certificate"
  shows "fail03_pass certificate \<and> fail03_negative_pass certificate"
  using assms by (simp add: core_contract_boundary_certificate_complete_def)

theorem fail04_current_profile_corollary:
  assumes "core_contract_boundary_certificate_complete certificate"
  shows "fail04_pass certificate \<and> fail04_negative_pass certificate"
  using assms by (simp add: core_contract_boundary_certificate_complete_def)

theorem fail08_current_profile_corollary:
  assumes "core_contract_boundary_certificate_complete certificate"
  shows "fail08_pass certificate \<and> fail08_negative_pass certificate"
  using assms by (simp add: core_contract_boundary_certificate_complete_def)

theorem ext01_current_profile_corollary:
  assumes "core_contract_boundary_certificate_complete certificate"
  shows "ext01_pass certificate \<and> ext01_negative_pass certificate"
  using assms by (simp add: core_contract_boundary_certificate_complete_def)

theorem ext02_current_profile_corollary:
  assumes "core_contract_boundary_certificate_complete certificate"
  shows "ext02_pass certificate \<and> ext02_negative_pass certificate"
  using assms by (simp add: core_contract_boundary_certificate_complete_def)

theorem ext03_current_profile_corollary:
  assumes "core_contract_boundary_certificate_complete certificate"
  shows "ext03_pass certificate \<and> ext03_negative_pass certificate"
  using assms by (simp add: core_contract_boundary_certificate_complete_def)

theorem sep02_current_profile_corollary:
  assumes "core_contract_boundary_certificate_complete certificate"
  shows "sep02_pass certificate \<and> sep02_negative_pass certificate"
  using assms by (simp add: core_contract_boundary_certificate_complete_def)

theorem sep04_current_profile_corollary:
  assumes "core_contract_boundary_certificate_complete certificate"
  shows "sep04_pass certificate \<and> sep04_negative_pass certificate"
  using assms by (simp add: core_contract_boundary_certificate_complete_def)

theorem art06_current_profile_corollary:
  assumes "core_contract_boundary_certificate_complete certificate"
  shows "art06_pass certificate \<and> art06_negative_pass certificate"
  using assms by (simp add: core_contract_boundary_certificate_complete_def)

theorem art07_current_profile_corollary:
  assumes "core_contract_boundary_certificate_complete certificate"
  shows "art07_pass certificate \<and> art07_negative_pass certificate"
  using assms by (simp add: core_contract_boundary_certificate_complete_def)
ML \<open>
  val core_contract_boundary_certificate_facts = @{thms
    abi05_current_profile_corollary
    auth01_current_profile_corollary
    auth02_current_profile_corollary
    auth03_current_profile_corollary
    auth04_current_profile_corollary
    auth05_current_profile_corollary
    fail01_current_profile_corollary
    fail02_current_profile_corollary
    fail03_current_profile_corollary
    fail04_current_profile_corollary
    fail08_current_profile_corollary
    ext01_current_profile_corollary
    ext02_current_profile_corollary
    ext03_current_profile_corollary
    sep02_current_profile_corollary
    sep04_current_profile_corollary
    art06_current_profile_corollary
    art07_current_profile_corollary};
  val core_contract_boundary_certificate_oracles = Thm_Deps.all_oracles core_contract_boundary_certificate_facts;
  val _ = if null core_contract_boundary_certificate_oracles then ()
    else error ("TRUST_M4_Core_Contract_Boundary_Current_Profile proof audit found oracle dependencies");
\<close>

end
