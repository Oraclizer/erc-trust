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


section \<open>Regulatory references at transaction boundaries\<close>

definition record_at where "record_at st i = the (action_records st i)"
definition link_at where "link_at st i = the (effect_links st i)"

definition effect_history_wf :: "trust_compositional_state \<Rightarrow> bool" where
 "effect_history_wf st \<longleftrightarrow> (\<forall>i e. effect_links st i = Some e \<longrightarrow>
   action_records st i \<noteq> None \<and> i \<noteq> 0 \<and>
   (let r = record_at st i in abstract_subject r \<noteq> 0 \<and> abstract_case r \<noteq> 0 \<and>
    abstract_action r \<in> {Legal_Freeze, Legal_Restrict} \<and>
    effect_generation e > 0 \<and>
    effect_generation e \<le> head_generation
      (if abstract_action r = Legal_Freeze then freeze_heads st (abstract_subject r)
       else restriction_heads st (abstract_subject r)) \<and>
    (case effect_parent e of None \<Rightarrow> abstract_prior_amount r = 0 \<and> \<not> abstract_prior_flag r
     | Some j \<Rightarrow> abstract_action r = Legal_Freeze \<and> action_records st j \<noteq> None \<and>
        effect_links st j \<noteq> None \<and> abstract_action (record_at st j) = Legal_Freeze \<and>
        abstract_subject (record_at st j) = abstract_subject r \<and>
        abstract_case (record_at st j) = abstract_case r \<and>
        effect_generation (link_at st j) < effect_generation e \<and>
        abstract_prior_amount r = abstract_amount (record_at st j))))"

fun live_freeze_chain :: "trust_compositional_state \<Rightarrow> trust_address \<Rightarrow> trust_case_id \<Rightarrow> trust_action_id list \<Rightarrow> bool" where
 "live_freeze_chain st a c [] = True"
| "live_freeze_chain st a c (i # xs) = (action_records st i \<noteq> None \<and> effect_links st i \<noteq> None \<and>
    abstract_action (record_at st i) = Legal_Freeze \<and> abstract_lifecycle (record_at st i) = Record_Applied \<and>
    abstract_subject (record_at st i) = a \<and> abstract_case (record_at st i) = c \<and>
    abstract_prior_amount (record_at st i) < abstract_amount (record_at st i) \<and>
    effect_parent (link_at st i) = (case xs of [] \<Rightarrow> None | j # _ \<Rightarrow> Some j) \<and>
    live_freeze_chain st a c xs)"

definition freeze_structure_wf :: "trust_compositional_state \<Rightarrow> bool" where
 "freeze_structure_wf st \<longleftrightarrow> (\<forall>a. case head_action (freeze_heads st a) of
   None \<Rightarrow> frozen_targets st a = 0
 | Some i \<Rightarrow> (\<exists>xs. distinct (i # xs) \<and>
    live_freeze_chain st a (abstract_case (record_at st i)) (i # xs)) \<and>
    frozen_targets st a = abstract_amount (record_at st i) \<and>
    open_case st (abstract_case (record_at st i)) \<and>
    case_family (case_records st (abstract_case (record_at st i))) = Family_Freeze \<and>
    case_head (case_records st (abstract_case (record_at st i))) = Some i)"

definition restriction_structure_wf :: "trust_compositional_state \<Rightarrow> bool" where
 "restriction_structure_wf st \<longleftrightarrow> (\<forall>a. case head_action (restriction_heads st a) of
   None \<Rightarrow> \<not> restriction_flags st a
 | Some i \<Rightarrow> restriction_flags st a \<and> action_records st i \<noteq> None \<and> effect_links st i \<noteq> None \<and>
    abstract_action (record_at st i) = Legal_Restrict \<and> abstract_lifecycle (record_at st i) = Record_Applied \<and>
    abstract_subject (record_at st i) = a \<and> \<not> abstract_prior_flag (record_at st i) \<and>
    effect_parent (link_at st i) = None \<and> open_case st (abstract_case (record_at st i)) \<and>
    case_family (case_records st (abstract_case (record_at st i))) = Family_Restrict \<and>
    case_head (case_records st (abstract_case (record_at st i))) = Some i)"

definition case_structure_wf :: "trust_compositional_state \<Rightarrow> bool" where
 "case_structure_wf st \<longleftrightarrow> (\<forall>c. case case_phase (case_records st c) of
   Case_None \<Rightarrow> case_records st c = empty_case
 | Case_Terminal \<Rightarrow> case_head (case_records st c) = None
 | Case_Open \<Rightarrow> (case case_head (case_records st c) of None \<Rightarrow> False | Some i \<Rightarrow>
    action_records st i \<noteq> None \<and> abstract_case (record_at st i) = c \<and>
    (case case_family (case_records st c) of
      Family_Freeze \<Rightarrow> head_action (freeze_heads st (abstract_subject (record_at st i))) = Some i
    | Family_Restrict \<Rightarrow> head_action (restriction_heads st (abstract_subject (record_at st i))) = Some i
    | Family_Custody \<Rightarrow> abstract_action (record_at st i) = Legal_Seize
    | _ \<Rightarrow> False)))"

definition action_identity_wf :: "trust_compositional_state \<Rightarrow> bool" where
 "action_identity_wf st \<longleftrightarrow> (\<forall>i r. action_records st i = Some r \<longrightarrow>
   i \<noteq> 0 \<and> abstract_subject r \<noteq> 0 \<and> abstract_case r \<noteq> 0 \<and>
   abstract_lifecycle r \<in> {Record_Applied, Record_Reversed} \<and>
   case_phase (case_records st (abstract_case r)) \<noteq> Case_None \<and>
   \<not> abstract_prior_flag r \<and>
   ((effect_links st i \<noteq> None) = (abstract_action r \<in> {Legal_Freeze, Legal_Restrict})) \<and>
   (case abstract_action r of
     Legal_Freeze \<Rightarrow> abstract_source r = abstract_subject r \<and> abstract_destination r = 0 \<and>
       abstract_custodian r = 0 \<and> abstract_prior_amount r < abstract_amount r \<and>
       case_family (case_records st (abstract_case r)) = Family_Freeze
   | Legal_Restrict \<Rightarrow> abstract_source r = abstract_subject r \<and> abstract_destination r = 0 \<and>
       abstract_custodian r = 0 \<and> abstract_amount r = 0 \<and> abstract_prior_amount r = 0 \<and>
       case_family (case_records st (abstract_case r)) = Family_Restrict
   | Legal_Seize \<Rightarrow> abstract_source r = abstract_subject r \<and> abstract_destination r = abstract_custodian r \<and>
       abstract_custodian r \<noteq> 0 \<and> abstract_subject r \<noteq> abstract_custodian r \<and>
       abstract_amount r > 0 \<and> abstract_prior_amount r = 0 \<and>
       case_family (case_records st (abstract_case r)) = Family_Custody
   | _ \<Rightarrow> abstract_source r \<noteq> 0 \<and> abstract_destination r \<noteq> 0 \<and>
       abstract_source r \<noteq> abstract_destination r \<and> abstract_custodian r = 0 \<and>
       abstract_amount r > 0 \<and> abstract_prior_amount r = 0 \<and> abstract_lifecycle r = Record_Applied \<and>
       case_phase (case_records st (abstract_case r)) = Case_Terminal \<and>
       case_family (case_records st (abstract_case r)) \<in> {Family_Disposition, Family_Custody}))"

definition regulatory_structure_wf where
 "regulatory_structure_wf st \<longleftrightarrow> action_identity_wf st \<and> effect_history_wf st \<and> freeze_structure_wf st \<and>
    restriction_structure_wf st \<and> case_structure_wf st \<and> custody_case_wf st"

lemmas structure_defs = regulatory_structure_wf_def action_identity_wf_def effect_history_wf_def freeze_structure_wf_def
 restriction_structure_wf_def case_structure_wf_def custody_case_wf_def record_at_def link_at_def
 open_case_def empty_case_def empty_head_def

theorem initial_structure:
 "regulatory_structure_wf (native_initial_state holder supply ref authority bindings root)"
 by (simp add: structure_defs native_initial_state_def)


lemma balance_wf_expands_support:
 assumes "balance_wf A st" "A \<subseteq> B" "finite B"
 shows "balance_wf B st"
proof -
 have sums: "(\<Sum>a\<in>B. physical_balances st a) = (\<Sum>a\<in>A. physical_balances st a)"
   by (rule sum.mono_neutral_right) (use assms in \<open>auto simp: balance_wf_def\<close>)
 show ?thesis using assms sums by (auto simp: balance_wf_def)
qed

lemma case_scope_expands_support:
 assumes "case_scope C st" "C \<subseteq> D" "finite D"
 shows "case_scope D st"
 using assms by (auto simp: case_scope_def)

lemma active_custody_sum_expands_support:
 assumes "case_scope C st" "C \<subseteq> D" "finite D"
 shows "active_custody_sum D st a = active_custody_sum C st a"
 unfolding active_custody_sum_def
 by (rule sum.mono_neutral_right) (use assms in \<open>auto simp: case_scope_def\<close>)

lemma accounting_state_wf_expands_support:
 assumes "accounting_state_wf A C st" "A \<subseteq> B" "finite B" "C \<subseteq> D" "finite D"
 shows "accounting_state_wf B D st"
proof -
 have bal: "balance_wf B st" using assms balance_wf_expands_support unfolding accounting_state_wf_def by blast
 have scope: "case_scope D st" using assms case_scope_expands_support unfolding accounting_state_wf_def by blast
 have sums: "\<And>a. active_custody_sum D st a = active_custody_sum C st a"
   using assms active_custody_sum_expands_support unfolding accounting_state_wf_def by blast
 show ?thesis using assms(1) assms(5) bal scope sums
   by (auto simp: accounting_state_wf_def custody_consistent_def)
qed

theorem ordinary_transfer_expands_account_support:
 assumes "accounting_state_wf A C st" "ordinary_transfer_allowed st src dst amount"
 shows "accounting_state_wf (A \<union> {src,dst}) C (ordinary_transfer_state st src dst amount)"
proof -
 have finiteA: "finite A" and finiteC: "finite C" using assms(1)
   by (auto simp: accounting_state_wf_def balance_wf_def case_scope_def)
 have expanded: "accounting_state_wf (A \<union> {src,dst}) C st"
   by (rule accounting_state_wf_expands_support[OF assms(1)]) (use finiteA finiteC in auto)
 show ?thesis by (rule ordinary_transfer_preserves_accounting_state_wf[OF expanded assms(2)]) auto
qed

lemma chain_ordinary_frame [simp]:
 "live_freeze_chain (ordinary_transfer_state st src dst amount) a c xs = live_freeze_chain st a c xs"
 by (induction xs) (simp_all add: ordinary_transfer_state_def record_at_def link_at_def)
lemma chain_authority_frame [simp]:
 "live_freeze_chain (rotate_authority st ref account active) a c xs = live_freeze_chain st a c xs"
 by (induction xs) (simp_all add: rotate_authority_def record_at_def link_at_def)
lemma chain_dependency_frame [simp]:
 "live_freeze_chain (rebind_dependency st kind binding root) a c xs = live_freeze_chain st a c xs"
 by (induction xs) (simp_all add: rebind_dependency_def record_at_def link_at_def)

theorem ordinary_transfer_preserves_structure:
 "regulatory_structure_wf (ordinary_transfer_state st src dst amount) = regulatory_structure_wf st"
 unfolding structure_defs
 by (simp only: chain_ordinary_frame; simp add: ordinary_transfer_state_def record_at_def link_at_def open_case_def cong: option.case_cong trust_case_phase.case_cong trust_case_family.case_cong legal_action_kind.case_cong)

theorem authority_rotation_preserves_structure:
 "regulatory_structure_wf (rotate_authority st ref account active) = regulatory_structure_wf st"
 unfolding structure_defs
 by (simp only: chain_authority_frame; simp add: rotate_authority_def record_at_def link_at_def open_case_def cong: option.case_cong trust_case_phase.case_cong trust_case_family.case_cong legal_action_kind.case_cong)

theorem dependency_rebind_preserves_structure:
 "regulatory_structure_wf (rebind_dependency st kind binding root) = regulatory_structure_wf st"
 unfolding structure_defs
 by (simp only: chain_dependency_frame; simp add: rebind_dependency_def record_at_def link_at_def open_case_def cong: option.case_cong trust_case_phase.case_cong trust_case_family.case_cong legal_action_kind.case_cong)

theorem all_failure_outcomes_preserve_structure:
 "regulatory_structure_wf (fst (abstract_failure_transition st outcome)) = regulatory_structure_wf st \<and>
  snd (abstract_failure_transition st outcome) = outcome"
 by (simp add: abstract_failure_transition_def)

end
