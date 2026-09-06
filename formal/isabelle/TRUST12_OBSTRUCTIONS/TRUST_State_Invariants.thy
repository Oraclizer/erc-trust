theory TRUST_State_Invariants
  imports "ERC_TRUST.TRUST_Transaction_Refinement"
begin

text \<open>Finite balance accounting and custody/case reference consistency.
  Initial-state theorems describe the model. They do not establish a storage
  decoder, constructor refinement, or the general runtime link.\<close>

definition balance_wf :: "trust_address set \<Rightarrow> trust_compositional_state \<Rightarrow> bool" where
  "balance_wf accounts st \<longleftrightarrow>
     finite accounts \<and>
     (\<forall>a. a \<notin> accounts \<longrightarrow> physical_balances st a = 0) \<and>
     (\<Sum>a\<in>accounts. physical_balances st a) = compositional_total_supply st"

definition case_scope :: "trust_case_id set \<Rightarrow> trust_compositional_state \<Rightarrow> bool" where
  "case_scope cases st \<longleftrightarrow> finite cases \<and>
     (\<forall>c. c \<notin> cases \<longrightarrow>
       case_records st c = empty_case \<and> custody_records st c = None)"

definition custody_case_wf :: "trust_compositional_state \<Rightarrow> bool" where
  "custody_case_wf st \<longleftrightarrow>
    (\<forall>c. (open_case st c \<and> case_family (case_records st c) = Family_Custody) =
       (\<exists>cu. custody_records st c = Some cu \<and> custody_active cu)) \<and>
    (\<forall>c cu. custody_records st c = Some cu \<longrightarrow>
      (if custody_active cu then
        (\<exists>i r. custody_action cu = Some i \<and>
          case_head (case_records st c) = Some i \<and> action_records st i = Some r \<and>
          abstract_lifecycle r = Record_Applied \<and> abstract_action r = Legal_Seize \<and>
          abstract_case r = c \<and> abstract_source r = custody_prior_holder cu \<and>
          abstract_subject r = custody_prior_holder cu \<and>
          abstract_destination r = custody_custodian cu \<and>
          abstract_custodian r = custody_custodian cu \<and>
          abstract_amount r = custody_amount cu \<and> custody_amount cu > 0 \<and>
          custody_prior_holder cu \<noteq> 0 \<and> custody_custodian cu \<noteq> 0 \<and>
          custody_prior_holder cu \<noteq> custody_custodian cu)
       else custody_amount cu = 0))"

definition accounting_state_wf ::
  "trust_address set \<Rightarrow> trust_case_id set \<Rightarrow> trust_compositional_state \<Rightarrow> bool" where
  "accounting_state_wf accounts cases st \<longleftrightarrow>
    balance_wf accounts st \<and> case_scope cases st \<and>
    custody_consistent cases st \<and> custody_case_wf st"

definition native_initial_state ::
  "trust_address \<Rightarrow> nat \<Rightarrow> trust_authority_ref \<Rightarrow> trust_address \<Rightarrow>
   (trust_binding_kind \<Rightarrow> compositional_binding) \<Rightarrow> trust_hash \<Rightarrow>
   trust_compositional_state"
where
  "native_initial_state holder supply ref authority bindings root =
   \<lparr>physical_balances = (\<lambda>a. if a = holder then supply else 0),
    compositional_allowances = (\<lambda>_ _. 0), compositional_total_supply = supply,
    frozen_targets = (\<lambda>_. 0), restriction_flags = (\<lambda>_. False),
    custody_backing = (\<lambda>_. 0), freeze_heads = (\<lambda>_. empty_head),
    restriction_heads = (\<lambda>_. empty_head), effect_links = (\<lambda>_. None),
    action_records = (\<lambda>_. None), custody_records = (\<lambda>_. None),
    case_records = (\<lambda>_. empty_case), consumed_entitlements = {},
    authorities = (\<lambda>r. if r = ref then Some
      \<lparr>authority_account = authority, authority_epoch = 1, authority_active = True\<rparr>
      else None), compositional_consumed_nonces = {},
    compositional_bindings = (\<lambda>k. Some (bindings k)), dependency_root = root,
    dependency_epoch = 1, compositional_receipts = (\<lambda>_. None)\<rparr>"

theorem native_initial_accounting_state_wf:
  "accounting_state_wf {holder} {}
     (native_initial_state holder supply ref authority bindings root)"
  by (auto simp: accounting_state_wf_def balance_wf_def case_scope_def
      custody_consistent_def active_custody_sum_def custody_case_wf_def
      native_initial_state_def open_case_def empty_case_def)

lemma move_balance_self:
  assumes "amount \<le> balances account"
  shows "move_balance balances account account amount = balances"
  using assms by (auto simp: move_balance_def fun_eq_iff)

theorem ordinary_self_transfer_stutters:
  assumes "ordinary_transfer_allowed st account account amount"
  shows "ordinary_transfer_state st account account amount = st"
  using assms by (simp add: ordinary_transfer_allowed_def ordinary_transfer_state_def move_balance_self)

theorem closed_custody_has_zero_amount:
  assumes "custody_records st cid = Some cu"
  shows "map_option custody_amount (close_custody st cid cid) = Some 0 \<and>
         map_option custody_active (close_custody st cid cid) = Some False"
  using assms by (simp add: close_custody_def)

theorem custody_case_none_is_inactive:
  assumes "custody_case_wf st" "case_records st cid = empty_case"
  shows "\<not> (\<exists>cu. custody_records st cid = Some cu \<and> custody_active cu)"
proof -
  have linked: "(open_case st cid \<and> case_family (case_records st cid) = Family_Custody) =
      (\<exists>cu. custody_records st cid = Some cu \<and> custody_active cu)"
    using assms(1) unfolding custody_case_wf_def by blast
  show ?thesis using linked assms(2) by (simp add: open_case_def empty_case_def)
qed


lemma move_balance_preserves_sum:
  assumes "finite accounts" "source \<in> accounts" "destination \<in> accounts"
      and "amount \<le> balances source"
  shows "(\<Sum>a\<in>accounts. move_balance balances source destination amount a) =
         (\<Sum>a\<in>accounts. balances a)"
proof -
  have pointwise: "\<And>a. move_balance balances source destination amount a +
       (if a = source then amount else 0) =
       balances a + (if a = destination then amount else 0)"
    using assms(4) by (auto simp: move_balance_def)
  have sums: "(\<Sum>a\<in>accounts. move_balance balances source destination amount a +
       (if a = source then amount else 0)) =
       (\<Sum>a\<in>accounts. balances a + (if a = destination then amount else 0))"
    by (rule sum.cong) (rule refl, rule pointwise)
  show ?thesis using sums assms by (simp add: sum.distrib)
qed

lemma move_balance_preserves_balance_wf:
  assumes "balance_wf accounts st" "source \<in> accounts" "destination \<in> accounts"
      and "amount \<le> physical_balances st source"
  shows "balance_wf accounts
      (st\<lparr>physical_balances := move_balance (physical_balances st) source destination amount\<rparr>)"
  using assms move_balance_preserves_sum[of accounts source destination amount "physical_balances st"]
  by (auto simp: balance_wf_def move_balance_def)

lemma ordinary_transfer_preserves_backing_bound:
  assumes "\<forall>a. custody_backing st a \<le> physical_balances st a"
      and "ordinary_transfer_allowed st source destination amount"
  shows "\<forall>a. custody_backing st a \<le>
       physical_balances (ordinary_transfer_state st source destination amount) a"
proof (intro allI)
  fix a
  have source_bound: "custody_backing st source \<le> physical_balances st source"
    using assms(1) by blast
  have amount_bound: "amount \<le> physical_balances st source - custody_backing st source"
    using assms(2) ordinary_available_never_spends_custody_backing[of st source]
    unfolding ordinary_transfer_allowed_def by arith
  have remaining: "custody_backing st source \<le> physical_balances st source - amount"
    using source_bound amount_bound by presburger
  have bound_at: "custody_backing st a \<le> physical_balances st a" using assms(1) by blast
  show "custody_backing st a \<le>
       physical_balances (ordinary_transfer_state st source destination amount) a"
    using bound_at source_bound remaining assms(2)
    by (auto simp: ordinary_transfer_state_def move_balance_def ordinary_transfer_allowed_def; arith)
qed

theorem ordinary_transfer_preserves_accounting_state_wf:
  assumes "accounting_state_wf accounts cases st"
      and "ordinary_transfer_allowed st source destination amount"
      and "source \<in> accounts" "destination \<in> accounts"
  shows "accounting_state_wf accounts cases (ordinary_transfer_state st source destination amount)"
proof -
  have balance: "balance_wf accounts (ordinary_transfer_state st source destination amount)"
    using assms move_balance_preserves_balance_wf
    unfolding accounting_state_wf_def ordinary_transfer_allowed_def ordinary_transfer_state_def by blast
  have backing: "\<forall>a. custody_backing st a \<le>
       physical_balances (ordinary_transfer_state st source destination amount) a"
    using assms ordinary_transfer_preserves_backing_bound
    unfolding accounting_state_wf_def custody_consistent_def by blast
  have scope: "case_scope cases (ordinary_transfer_state st source destination amount) = case_scope cases st"
    by (simp add: case_scope_def ordinary_transfer_state_def)
  have links: "custody_case_wf (ordinary_transfer_state st source destination amount) = custody_case_wf st"
    by (simp add: custody_case_wf_def ordinary_transfer_state_def open_case_def)
  have custody: "custody_consistent cases (ordinary_transfer_state st source destination amount)"
    using assms(1) backing
    by (auto simp: accounting_state_wf_def custody_consistent_def active_custody_sum_def ordinary_transfer_state_def)
  show ?thesis using assms(1) balance custody scope links
    unfolding accounting_state_wf_def by blast
qed

end
