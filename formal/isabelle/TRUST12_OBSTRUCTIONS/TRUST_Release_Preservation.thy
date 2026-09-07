theory TRUST_Release_Preservation
  imports TRUST_Unfreeze_Preservation
begin

lemma release_context:
 assumes CU: "custody_case_wf st" and AD: "reversal_admissible st cmd"
   and KIND: "reversal_kind cmd = TRUST_RELEASE"
 shows "\<exists>r cu. action_records st (reversal_original_action_id cmd) = Some r \<and>
   abstract_action r = Legal_Seize \<and> abstract_lifecycle r = Record_Applied \<and>
   custody_records st (abstract_case r) = Some cu \<and> custody_active cu \<and>
   custody_action cu = Some (reversal_original_action_id cmd) \<and>
   abstract_source r = custody_prior_holder cu \<and> abstract_subject r = custody_prior_holder cu \<and>
   abstract_custodian r = custody_custodian cu \<and> abstract_destination r = custody_custodian cu \<and>
   abstract_amount r = custody_amount cu \<and> custody_amount cu \<le> custody_backing st (custody_custodian cu) \<and>
   custody_custodian cu \<noteq> custody_prior_holder cu \<and> custody_amount cu > 0 \<and>
   open_case st (abstract_case r) \<and> case_family (case_records st (abstract_case r)) = Family_Custody \<and>
   case_head (case_records st (abstract_case r)) = Some (reversal_original_action_id cmd)"
proof -
 let ?id = "reversal_original_action_id cmd"
 obtain r where REC: "action_records st ?id = Some r" and ACT: "abstract_action r = Legal_Seize"
   and APPLIED: "abstract_lifecycle r = Record_Applied" and CURRENT: "reversal_current_effect st cmd r"
   using AD KIND by (auto simp: reversal_admissible_def reversal_original_def reversal_pairs_def split: option.splits)
 obtain cu where CUREC: "custody_records st (abstract_case r) = Some cu" and ACTIVE: "custody_active cu"
   and CID: "custody_action cu = Some ?id"
   and COVER: "custody_amount cu \<le> custody_backing st (custody_custodian cu)"
   using CURRENT KIND by (auto simp: reversal_current_effect_def Let_def split: option.splits)
 note AT = CU[unfolded custody_case_wf_def, THEN conjunct2, rule_format, OF CUREC]
 obtain j q where W: "custody_action cu = Some j \<and> case_head (case_records st (abstract_case r)) = Some j \<and>
   action_records st j = Some q \<and> abstract_lifecycle q = Record_Applied \<and> abstract_action q = Legal_Seize \<and>
   abstract_case q = abstract_case r \<and> abstract_source q = custody_prior_holder cu \<and> abstract_subject q = custody_prior_holder cu \<and>
   abstract_destination q = custody_custodian cu \<and> abstract_custodian q = custody_custodian cu \<and>
   abstract_amount q = custody_amount cu \<and> custody_amount cu > 0 \<and> custody_prior_holder cu \<noteq> 0 \<and>
   custody_custodian cu \<noteq> 0 \<and> custody_prior_holder cu \<noteq> custody_custodian cu"
   using AT ACTIVE by auto
 have J: "j = ?id" using W CID by auto
 have Q: "q = r" using W J REC by auto
 have EQ: "(open_case st (abstract_case r) \<and> case_family (case_records st (abstract_case r)) = Family_Custody) =
   (\<exists>x. custody_records st (abstract_case r) = Some x \<and> custody_active x)"
   using CU unfolding custody_case_wf_def by blast
 have OPEN_FAMILY: "open_case st (abstract_case r) \<and> case_family (case_records st (abstract_case r)) = Family_Custody"
   using EQ CUREC ACTIVE by blast
 show ?thesis by (rule exI[where x=r], rule exI[where x=cu])
   (use REC ACT APPLIED CUREC ACTIVE CID COVER W J Q OPEN_FAMILY in auto)
qed

lemma release_source_view:
 assumes REC: "action_records st (reversal_original_action_id cmd) = Some r"
   and CUREC: "custody_records st (abstract_case r) = Some cu" and KIND: "reversal_kind cmd = TRUST_RELEASE"
 shows "reversal_success_state st cmd w = st\<lparr>
   compositional_consumed_nonces := insert (reversal_nonce_key cmd) (compositional_consumed_nonces st),
   compositional_receipts := (compositional_receipts st)(reversal_id cmd := Some (reversal_witness_receipt w)),
   action_records := (action_records st)(reversal_original_action_id cmd := Some (r\<lparr>abstract_lifecycle := Record_Reversed\<rparr>)),
   physical_balances := move_balance (physical_balances st) (custody_custodian cu) (custody_prior_holder cu) (custody_amount cu),
   custody_backing := (custody_backing st)(custody_custodian cu := custody_backing st (custody_custodian cu) - custody_amount cu),
   custody_records := close_custody st (abstract_case r),
   case_records := (case_records st)(abstract_case r := closed_case (case_records st (abstract_case r)))\<rparr>"
 using assms by (simp add: reversal_success_state_def reversal_original_def close_custody_def Let_def)

lemma release_preserves_action_identity:
 assumes WF: "regulatory_structure_wf st" and AD: "reversal_admissible st cmd"
   and KIND: "reversal_kind cmd = TRUST_RELEASE"
 shows "action_identity_wf (reversal_success_state st cmd w)"
proof -
 have CU: "custody_case_wf st" using WF unfolding regulatory_structure_wf_def by blast
 obtain r cu where REC: "action_records st (reversal_original_action_id cmd) = Some r"
   and ACT: "abstract_action r = Legal_Seize" and CUREC: "custody_records st (abstract_case r) = Some cu"
   and FAMILY: "case_family (case_records st (abstract_case r)) = Family_Custody"
   using release_context[OF CU AD KIND] by auto
 note VIEW = release_source_view[OF REC CUREC KIND, of w]
 have AI: "action_identity_wf st" using WF unfolding regulatory_structure_wf_def by blast
 show ?thesis unfolding action_identity_wf_def
   apply (intro allI impI)
   subgoal premises P for i q
   proof (cases "i = reversal_original_action_id cmd")
     case True
     note AIR = AI[unfolded action_identity_wf_def, rule_format, of "reversal_original_action_id cmd" r]
     show ?thesis using P True AIR REC ACT
       by (auto simp: VIEW closed_case_def split: legal_action_kind.splits if_splits)
   next
     case False
     have OLD: "action_records st i = Some q" using P False by (simp add: VIEW)
     note AIQ = AI[unfolded action_identity_wf_def, rule_format, of i q]
     show ?thesis using AIQ OLD False REC ACT
       by (auto simp: VIEW closed_case_def split: legal_action_kind.splits if_splits)
   qed
   done
qed

lemma release_preserves_effect_history:
 assumes WF: "regulatory_structure_wf st" and AD: "reversal_admissible st cmd"
   and KIND: "reversal_kind cmd = TRUST_RELEASE"
 shows "effect_history_wf (reversal_success_state st cmd w)"
proof -
 have CU: "custody_case_wf st" using WF unfolding regulatory_structure_wf_def by blast
 obtain r cu where REC: "action_records st (reversal_original_action_id cmd) = Some r"
   and ACT: "abstract_action r = Legal_Seize" and CUREC: "custody_records st (abstract_case r) = Some cu"
   and FAMILY: "case_family (case_records st (abstract_case r)) = Family_Custody"
   using release_context[OF CU AD KIND] by auto
 note VIEW = release_source_view[OF REC CUREC KIND, of w]
 have H: "effect_history_wf st" using WF unfolding regulatory_structure_wf_def by blast
 show ?thesis unfolding effect_history_wf_def
 proof (intro allI impI)
   fix i e
   assume E: "effect_links (reversal_success_state st cmd w) i = Some e"
   have E0: "effect_links st i = Some e" using E by (simp add: VIEW)
   note HI = H[unfolded effect_history_wf_def, rule_format, of i e]
   show "action_records (reversal_success_state st cmd w) i \<noteq> None \<and> i \<noteq> 0 \<and>
     (let r = record_at (reversal_success_state st cmd w) i in abstract_subject r \<noteq> 0 \<and> abstract_case r \<noteq> 0 \<and>
       abstract_action r \<in> {Legal_Freeze, Legal_Restrict} \<and> effect_generation e > 0 \<and>
       effect_generation e \<le> head_generation (if abstract_action r = Legal_Freeze then freeze_heads (reversal_success_state st cmd w) (abstract_subject r)
         else restriction_heads (reversal_success_state st cmd w) (abstract_subject r)) \<and>
       (case effect_parent e of None \<Rightarrow> abstract_prior_amount r = 0 \<and> \<not> abstract_prior_flag r
        | Some j \<Rightarrow> abstract_action r = Legal_Freeze \<and> action_records (reversal_success_state st cmd w) j \<noteq> None \<and>
          effect_links (reversal_success_state st cmd w) j \<noteq> None \<and> abstract_action (record_at (reversal_success_state st cmd w) j) = Legal_Freeze \<and>
          abstract_subject (record_at (reversal_success_state st cmd w) j) = abstract_subject r \<and>
          abstract_case (record_at (reversal_success_state st cmd w) j) = abstract_case r \<and>
          effect_generation (link_at (reversal_success_state st cmd w) j) < effect_generation e \<and>
          abstract_prior_amount r = abstract_amount (record_at (reversal_success_state st cmd w) j)))"
     using HI E0 REC ACT by (auto simp: VIEW record_at_def link_at_def Let_def popped_head_def
       split: option.splits if_splits; presburger)
 qed
qed

lemma release_preserves_freeze_structure:
 assumes WF: "regulatory_structure_wf st" and AD: "reversal_admissible st cmd"
   and KIND: "reversal_kind cmd = TRUST_RELEASE"
 shows "freeze_structure_wf (reversal_success_state st cmd w)"
proof -
 let ?post = "reversal_success_state st cmd w"
 let ?id = "reversal_original_action_id cmd"
 have CU: "custody_case_wf st" using WF unfolding regulatory_structure_wf_def by blast
 obtain r cu where REC: "action_records st (reversal_original_action_id cmd) = Some r"
   and ACT: "abstract_action r = Legal_Seize" and CUREC: "custody_records st (abstract_case r) = Some cu"
   and FAMILY: "case_family (case_records st (abstract_case r)) = Family_Custody"
   using release_context[OF CU AD KIND] by auto
 note VIEW = release_source_view[OF REC CUREC KIND, of w]
 have F: "freeze_structure_wf st" using WF unfolding regulatory_structure_wf_def by blast
 show ?thesis unfolding freeze_structure_wf_def
 proof (intro allI)
   fix a
   note FA = F[unfolded freeze_structure_wf_def, rule_format, of a]
   show "(case head_action (freeze_heads ?post a) of None \<Rightarrow> frozen_targets ?post a = 0
    | Some i \<Rightarrow> (\<exists>xs. distinct (i # xs) \<and> live_freeze_chain ?post a (abstract_case (record_at ?post i)) (i # xs)) \<and>
      frozen_targets ?post a = abstract_amount (record_at ?post i) \<and>
      open_case ?post (abstract_case (record_at ?post i)) \<and>
      case_family (case_records ?post (abstract_case (record_at ?post i))) = Family_Freeze \<and>
      case_head (case_records ?post (abstract_case (record_at ?post i))) = Some i)"
   proof (cases "head_action (freeze_heads st a)")
     case None
     show ?thesis using FA None by (simp add: VIEW)
   next
     case (Some i)
     obtain xs where DIST: "distinct (i # xs)" and CH: "live_freeze_chain st a (abstract_case (record_at st i)) (i # xs)"
       using FA Some by auto
     have OUT: "?id \<notin> set (i # xs)"
     proof
       assume IN: "?id \<in> set (i # xs)"
       have "abstract_action (record_at st ?id) = Legal_Freeze" using freeze_chain_member_fields[OF CH IN] by blast
       then show False using REC ACT by (simp add: record_at_def)
     qed
     have NE: "i \<noteq> ?id" using OUT by auto
     have AWAY: "abstract_case (record_at st i) \<noteq> abstract_case r" using FA Some FAMILY by auto
     have NEWCH: "live_freeze_chain ?post a (abstract_case (record_at st i)) (i # xs)"
       by (rule reversal_preserves_chain_away[OF AD CH OUT])
     show ?thesis using FA Some DIST NEWCH NE AWAY
       by (auto simp: VIEW record_at_def open_case_def cong: option.case_cong intro!: exI[where x=xs])
   qed
 qed
qed

lemma release_preserves_restriction_structure:
 assumes WF: "regulatory_structure_wf st" and AD: "reversal_admissible st cmd"
   and KIND: "reversal_kind cmd = TRUST_RELEASE"
 shows "restriction_structure_wf (reversal_success_state st cmd w)"
proof -
 let ?post = "reversal_success_state st cmd w"
 let ?id = "reversal_original_action_id cmd"
 have CU: "custody_case_wf st" using WF unfolding regulatory_structure_wf_def by blast
 obtain r cu where REC: "action_records st (reversal_original_action_id cmd) = Some r"
   and ACT: "abstract_action r = Legal_Seize" and CUREC: "custody_records st (abstract_case r) = Some cu"
   and FAMILY: "case_family (case_records st (abstract_case r)) = Family_Custody"
   using release_context[OF CU AD KIND] by auto
 note VIEW = release_source_view[OF REC CUREC KIND, of w]
 have R: "restriction_structure_wf st" using WF unfolding regulatory_structure_wf_def by blast
 show ?thesis unfolding restriction_structure_wf_def
 proof (intro allI)
   fix a
   note RA = R[unfolded restriction_structure_wf_def, rule_format, of a]
   show "(case head_action (restriction_heads ?post a) of None \<Rightarrow> \<not> restriction_flags ?post a
    | Some i \<Rightarrow> restriction_flags ?post a \<and> action_records ?post i \<noteq> None \<and> effect_links ?post i \<noteq> None \<and>
      abstract_action (record_at ?post i) = Legal_Restrict \<and> abstract_lifecycle (record_at ?post i) = Record_Applied \<and>
      abstract_subject (record_at ?post i) = a \<and> \<not> abstract_prior_flag (record_at ?post i) \<and>
      effect_parent (link_at ?post i) = None \<and> open_case ?post (abstract_case (record_at ?post i)) \<and>
      case_family (case_records ?post (abstract_case (record_at ?post i))) = Family_Restrict \<and>
      case_head (case_records ?post (abstract_case (record_at ?post i))) = Some i)"
     using RA REC ACT FAMILY
     by (auto simp: VIEW popped_head_def closed_case_def record_at_def link_at_def open_case_def
       cong: option.case_cong split: option.splits if_splits)
 qed
qed

lemma release_preserves_case_structure:
 assumes WF: "regulatory_structure_wf st" and AD: "reversal_admissible st cmd"
   and KIND: "reversal_kind cmd = TRUST_RELEASE"
 shows "case_structure_wf (reversal_success_state st cmd w)"
proof -
 let ?post = "reversal_success_state st cmd w"
 let ?id = "reversal_original_action_id cmd"
 have CU: "custody_case_wf st" using WF unfolding regulatory_structure_wf_def by blast
 obtain r cu where REC: "action_records st (reversal_original_action_id cmd) = Some r"
   and ACT: "abstract_action r = Legal_Seize" and CUREC: "custody_records st (abstract_case r) = Some cu"
   and FAMILY: "case_family (case_records st (abstract_case r)) = Family_Custody"
   using release_context[OF CU AD KIND] by auto
 note VIEW = release_source_view[OF REC CUREC KIND, of w]
 have C: "case_structure_wf st" using WF unfolding regulatory_structure_wf_def by blast
 show ?thesis unfolding case_structure_wf_def
 proof (intro allI)
   fix c
   note CC = C[unfolded case_structure_wf_def, rule_format, of c]
   show "(case case_phase (case_records ?post c) of
     Case_None \<Rightarrow> case_records ?post c = empty_case
   | Case_Terminal \<Rightarrow> case_head (case_records ?post c) = None
   | Case_Open \<Rightarrow> (case case_head (case_records ?post c) of None \<Rightarrow> False | Some i \<Rightarrow>
      action_records ?post i \<noteq> None \<and> abstract_case (record_at ?post i) = c \<and>
      (case case_family (case_records ?post c) of
        Family_Freeze \<Rightarrow> head_action (freeze_heads ?post (abstract_subject (record_at ?post i))) = Some i
      | Family_Restrict \<Rightarrow> head_action (restriction_heads ?post (abstract_subject (record_at ?post i))) = Some i
      | Family_Custody \<Rightarrow> abstract_action (record_at ?post i) = Legal_Seize
      | _ \<Rightarrow> False)))"
     using CC REC
     by (auto simp: VIEW closed_case_def popped_head_def record_at_def empty_case_def
       cong: option.case_cong trust_case_phase.case_cong trust_case_family.case_cong
       split: option.splits trust_case_phase.splits trust_case_family.splits if_splits)
 qed
qed

lemma release_preserves_custody_case:
 assumes CU: "custody_case_wf st" and AD: "reversal_admissible st cmd"
   and KIND: "reversal_kind cmd = TRUST_RELEASE"
 shows "custody_case_wf (reversal_success_state st cmd w)"
proof -
 let ?post = "reversal_success_state st cmd w"
 let ?id = "reversal_original_action_id cmd"
 obtain r cu where REC: "action_records st ?id = Some r" and CUREC: "custody_records st (abstract_case r) = Some cu"
   using release_context[OF CU AD KIND] by auto
 let ?cid = "abstract_case r"
 note VIEW = release_source_view[OF REC CUREC KIND, of w]
 have CASE_FRAME: "\<And>c. c \<noteq> ?cid \<Longrightarrow> case_records ?post c = case_records st c" by (simp add: VIEW)
 have CUSTODY_FRAME: "\<And>c. c \<noteq> ?cid \<Longrightarrow> custody_records ?post c = custody_records st c"
   by (simp add: VIEW close_custody_def CUREC)
 have CLOSED: "custody_records ?post ?cid = Some (cu\<lparr>custody_active := False, custody_amount := 0\<rparr>)"
   by (simp add: VIEW close_custody_def CUREC)
 have TERMINAL: "case_phase (case_records ?post ?cid) = Case_Terminal" by (simp add: VIEW closed_case_def)
 have EQ0: "\<And>c. (open_case st c \<and> case_family (case_records st c) = Family_Custody) =
   (\<exists>x. custody_records st c = Some x \<and> custody_active x)" using CU unfolding custody_case_wf_def by blast
 have EQUIV: "\<forall>c. (open_case ?post c \<and> case_family (case_records ?post c) = Family_Custody) =
   (\<exists>x. custody_records ?post c = Some x \<and> custody_active x)"
 proof (intro allI)
   fix c
   show "(open_case ?post c \<and> case_family (case_records ?post c) = Family_Custody) =
     (\<exists>x. custody_records ?post c = Some x \<and> custody_active x)"
   proof (cases "c = ?cid")
     case True
     show ?thesis using True CLOSED TERMINAL by (simp add: open_case_def)
   next
     case False
     show ?thesis using EQ0[of c] CASE_FRAME[OF False] CUSTODY_FRAME[OF False] by (simp add: open_case_def)
   qed
 qed
 let ?link = "\<lambda>s c x. \<exists>j q. custody_action x = Some j \<and> case_head (case_records s c) = Some j \<and>
   action_records s j = Some q \<and> abstract_lifecycle q = Record_Applied \<and> abstract_action q = Legal_Seize \<and>
   abstract_case q = c \<and> abstract_source q = custody_prior_holder x \<and> abstract_subject q = custody_prior_holder x \<and>
   abstract_destination q = custody_custodian x \<and> abstract_custodian q = custody_custodian x \<and>
   abstract_amount q = custody_amount x \<and> custody_amount x > 0 \<and> custody_prior_holder x \<noteq> 0 \<and>
   custody_custodian x \<noteq> 0 \<and> custody_prior_holder x \<noteq> custody_custodian x"
 have LINKS: "\<And>c x. custody_records ?post c = Some x \<Longrightarrow>
   (if custody_active x then ?link ?post c x else custody_amount x = 0)"
 proof -
   fix c x
   assume POST: "custody_records ?post c = Some x"
   show "if custody_active x then ?link ?post c x else custody_amount x = 0"
   proof (cases "c = ?cid")
     case True
     show ?thesis using POST True CLOSED by auto
   next
     case False
     have AWAY: "c \<noteq> ?cid" by (rule False)
     have OLD: "custody_records st c = Some x" using POST CUSTODY_FRAME[OF AWAY] by simp
     note BEFORE = CU[unfolded custody_case_wf_def, THEN conjunct2, rule_format, OF OLD]
     have CS: "case_records ?post c = case_records st c" by (rule CASE_FRAME[OF AWAY])
     show ?thesis
     proof (cases "custody_active x")
       case False
       show ?thesis using BEFORE False by simp
     next
       case True
       obtain j q where W: "custody_action x = Some j \<and> case_head (case_records st c) = Some j \<and>
         action_records st j = Some q \<and> abstract_lifecycle q = Record_Applied \<and> abstract_action q = Legal_Seize \<and>
         abstract_case q = c \<and> abstract_source q = custody_prior_holder x \<and> abstract_subject q = custody_prior_holder x \<and>
         abstract_destination q = custody_custodian x \<and> abstract_custodian q = custody_custodian x \<and>
         abstract_amount q = custody_amount x \<and> custody_amount x > 0 \<and> custody_prior_holder x \<noteq> 0 \<and>
         custody_custodian x \<noteq> 0 \<and> custody_prior_holder x \<noteq> custody_custodian x"
         using BEFORE True by auto
       have NE: "j \<noteq> ?id"
       proof
         assume SAME: "j = ?id"
         have Q: "q = r" using W REC SAME by auto
         have "c = ?cid" using W Q by auto
         with AWAY show False by simp
       qed
       have OLD_REC: "action_records st j = Some q" using W by blast
       have NEW_REC: "action_records ?post j = Some q" by (simp add: VIEW NE OLD_REC)
       show ?thesis using True W NEW_REC CS by auto
     qed
   qed
 qed
 show ?thesis using EQUIV LINKS unfolding custody_case_wf_def by blast
qed

theorem release_preserves_regulatory_structure:
 assumes WF: "regulatory_structure_wf st" and AD: "reversal_admissible st cmd"
   and KIND: "reversal_kind cmd = TRUST_RELEASE"
 shows "regulatory_structure_wf (reversal_success_state st cmd w)"
proof -
 have CU: "custody_case_wf st" using WF unfolding regulatory_structure_wf_def by blast
 show ?thesis using release_preserves_action_identity[OF WF AD KIND]
   release_preserves_effect_history[OF WF AD KIND] release_preserves_freeze_structure[OF WF AD KIND]
   release_preserves_restriction_structure[OF WF AD KIND] release_preserves_case_structure[OF WF AD KIND]
   release_preserves_custody_case[OF CU AD KIND] unfolding regulatory_structure_wf_def by blast
qed

lemma release_preserves_accounting_state_wf:
 assumes WF: "state_wf A C st" and AD: "reversal_admissible st cmd" and KIND: "reversal_kind cmd = TRUST_RELEASE"
 shows "accounting_state_wf
   (A \<union> {abstract_source (record_at st (reversal_original_action_id cmd)),
     abstract_custodian (record_at st (reversal_original_action_id cmd)), abstract_destination (record_at st (reversal_original_action_id cmd))})
   (insert (abstract_case (record_at st (reversal_original_action_id cmd))) C) (reversal_success_state st cmd w)"
proof -
 let ?post = "reversal_success_state st cmd w"
 let ?id = "reversal_original_action_id cmd"
 have AC: "accounting_state_wf A C st" using WF unfolding state_wf_def by blast
 have BAL0: "balance_wf A st" and SCOPE0: "case_scope C st" and CONS0: "custody_consistent C st" and REF0: "custody_case_wf st"
   using AC unfolding accounting_state_wf_def by blast+
 obtain r cu where REC: "action_records st ?id = Some r" and CUREC: "custody_records st (abstract_case r) = Some cu"
   and ACTIVE: "custody_active cu" and SOURCE: "abstract_source r = custody_prior_holder cu"
   and CUST: "abstract_custodian r = custody_custodian cu" and DEST: "abstract_destination r = custody_custodian cu"
   and COVER: "custody_amount cu \<le> custody_backing st (custody_custodian cu)"
   and DISTINCT: "custody_custodian cu \<noteq> custody_prior_holder cu"
   using release_context[OF REF0 AD KIND] by auto
 let ?cust = "custody_custodian cu"
 let ?holder = "custody_prior_holder cu"
 let ?amount = "custody_amount cu"
 let ?cid = "abstract_case r"
 let ?A = "A \<union> {abstract_source r, abstract_custodian r, abstract_destination r}"
 let ?C = "insert ?cid C"
 note VIEW = release_source_view[OF REC CUREC KIND, of w]
 have AT: "record_at st ?id = r" using REC by (simp add: record_at_def)
 have FIN_A: "finite A" using BAL0 by (simp add: balance_wf_def)
 have FIN_C: "finite C" using SCOPE0 by (simp add: case_scope_def)
 have BOUND0: "\<forall>a. custody_backing st a \<le> physical_balances st a" using CONS0 unfolding custody_consistent_def by blast
 have EQ0: "\<And>a. custody_backing st a = active_custody_sum C st a" using CONS0 unfolding custody_consistent_def by blast
 have PAY: "?amount \<le> physical_balances st ?cust" using COVER BOUND0 by (meson order_trans)
 have SUM: "\<And>a. active_custody_sum ?C ?post a = active_custody_sum C st a - (if ?cust = a then ?amount else 0)"
 proof -
   fix a
   have CLOSE: "active_custody_sum ?C (st\<lparr>custody_records := close_custody st ?cid\<rparr>) a =
     active_custody_sum C st a - (if ?cust = a then ?amount else 0)"
     by (rule release_custody_sum_close[OF SCOPE0 CUREC ACTIVE])
   show "active_custody_sum ?C ?post a = active_custody_sum C st a - (if ?cust = a then ?amount else 0)"
     using CLOSE by (simp add: VIEW active_custody_sum_def)
 qed
 have BB: "\<forall>a. custody_backing ?post a \<le> physical_balances ?post a"
   using release_preserves_backing_bound[OF BOUND0 DISTINCT, of ?amount] by (simp add: VIEW)
 have CONS: "custody_consistent ?C ?post" using FIN_C SUM EQ0 BB
   by (auto simp: custody_consistent_def VIEW split: if_splits)
 have EXPANDED: "balance_wf ?A st" by (rule balance_wf_expands_support[OF BAL0]) (use FIN_A in auto)
 have IN_CUST: "?cust \<in> ?A" using CUST by auto
 have IN_HOLDER: "?holder \<in> ?A" using SOURCE by auto
 have MOVED: "balance_wf ?A (st\<lparr>physical_balances := move_balance (physical_balances st) ?cust ?holder ?amount\<rparr>)"
   by (rule move_balance_preserves_balance_wf[OF EXPANDED IN_CUST IN_HOLDER PAY])
 have BAL: "balance_wf ?A ?post" using MOVED by (simp add: balance_wf_def VIEW)
 have SCOPE: "case_scope ?C ?post" using SCOPE0 by (auto simp: case_scope_def VIEW close_custody_def CUREC)
 have REF: "custody_case_wf ?post" by (rule release_preserves_custody_case[OF REF0 AD KIND])
 show ?thesis using BAL SCOPE CONS REF AT by (simp add: accounting_state_wf_def)
qed

theorem release_preserves_state_wf:
 assumes WF: "state_wf A C st" and AD: "reversal_admitted st sender time cmd w" and KIND: "reversal_kind cmd = TRUST_RELEASE"
 shows "state_wf
   (A \<union> {abstract_source (record_at st (reversal_original_action_id cmd)),
     abstract_custodian (record_at st (reversal_original_action_id cmd)), abstract_destination (record_at st (reversal_original_action_id cmd))})
   (insert (abstract_case (record_at st (reversal_original_action_id cmd))) C) (reversal_success_state st cmd w)"
proof -
 have ADM: "reversal_admissible st cmd" using AD unfolding reversal_admitted_def by blast
 have REG: "regulatory_structure_wf st" using WF unfolding state_wf_def by blast
 show ?thesis using release_preserves_accounting_state_wf[OF WF ADM KIND]
   release_preserves_regulatory_structure[OF REG ADM KIND] unfolding state_wf_def by blast
qed

theorem reversal_preserves_state_wf:
 assumes WF: "state_wf A C st" and AD: "reversal_admitted st sender time cmd w"
 shows "state_wf
   (A \<union> {abstract_subject (record_at st (reversal_original_action_id cmd)), abstract_source (record_at st (reversal_original_action_id cmd)),
     abstract_destination (record_at st (reversal_original_action_id cmd)), abstract_custodian (record_at st (reversal_original_action_id cmd))})
   (insert (abstract_case (record_at st (reversal_original_action_id cmd))) C) (reversal_success_state st cmd w)"
proof -
 have FIN: "finite A \<and> finite C" using WF by (auto simp: state_wf_def accounting_state_wf_def balance_wf_def case_scope_def)
 show ?thesis
 proof (cases "reversal_kind cmd")
   case TRUST_UNFREEZE
   note R = unfreeze_preserves_state_wf[OF WF AD TRUST_UNFREEZE]
   show ?thesis by (rule state_wf_expands_support[OF R]) (use FIN in auto)
 next
   case TRUST_RELEASE
   note R = release_preserves_state_wf[OF WF AD TRUST_RELEASE]
   show ?thesis by (rule state_wf_expands_support[OF R]) (use FIN in auto)
 next
   case TRUST_UNRESTRICT
   note R = unrestrict_preserves_state_wf[OF WF AD TRUST_UNRESTRICT]
   show ?thesis by (rule state_wf_expands_support[OF R]) (use FIN in auto)
 qed
qed

end
