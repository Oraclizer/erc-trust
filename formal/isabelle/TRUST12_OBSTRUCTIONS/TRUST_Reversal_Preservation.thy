theory TRUST_Reversal_Preservation
  imports TRUST_Regulatory_Preservation
begin

lemma reversal_record_lookup:
 assumes AD: "reversal_admissible st cmd"
 shows "action_records (reversal_success_state st cmd w) i =
  (if i = reversal_original_action_id cmd then
    map_option (\<lambda>r. r\<lparr>abstract_lifecycle := Record_Reversed\<rparr>) (action_records st i)
   else action_records st i)"
 using AD by (auto simp: reversal_admissible_def reversal_original_def reversal_current_effect_def
   reversal_success_state_def Let_def split: option.splits trust_reversal_kind.splits)

lemma reversal_effect_lookup_frame:
 "effect_links (reversal_success_state st cmd w) = effect_links st"
 by (auto simp: reversal_success_state_def Let_def split: option.splits trust_reversal_kind.splits)

lemma reversal_preserves_chain_away:
 assumes AD: "reversal_admissible st cmd" and CH: "live_freeze_chain st a c xs"
   and OUT: "reversal_original_action_id cmd \<notin> set xs"
 shows "live_freeze_chain (reversal_success_state st cmd w) a c xs"
proof -
 have FRAME: "\<forall>i\<in>set xs. action_records (reversal_success_state st cmd w) i = action_records st i \<and>
   effect_links (reversal_success_state st cmd w) i = effect_links st i"
   using OUT by (simp add: reversal_record_lookup[OF AD] reversal_effect_lookup_frame)
 show ?thesis using CH freeze_chain_read_frame[OF FRAME] by simp
qed

lemma unrestrict_context:
 assumes WF: "regulatory_structure_wf st" and AD: "reversal_admissible st cmd"
   and KIND: "reversal_kind cmd = TRUST_UNRESTRICT"
 obtains r where "action_records st (reversal_original_action_id cmd) = Some r"
   and "abstract_action r = Legal_Restrict"
   and "abstract_lifecycle r = Record_Applied"
   and "\<not> abstract_prior_flag r"
   and "head_action (restriction_heads st (abstract_subject r)) = Some (reversal_original_action_id cmd)"
   and "link_parent st (reversal_original_action_id cmd) = None"
   and "open_case st (abstract_case r)"
   and "case_family (case_records st (abstract_case r)) = Family_Restrict"
   and "case_head (case_records st (abstract_case r)) = Some (reversal_original_action_id cmd)"
proof -
 obtain r where REC: "action_records st (reversal_original_action_id cmd) = Some r"
   and ACT: "abstract_action r = Legal_Restrict" and APPLIED: "abstract_lifecycle r = Record_Applied"
   and HD: "head_action (restriction_heads st (abstract_subject r)) = Some (reversal_original_action_id cmd)"
   using AD KIND by (auto simp: reversal_admissible_def reversal_original_def reversal_pairs_def
      reversal_current_effect_def Let_def split: option.splits)
 have R: "restriction_structure_wf st" using WF unfolding regulatory_structure_wf_def by blast
 note RA = R[unfolded restriction_structure_wf_def, rule_format, of "abstract_subject r"]
 have MORE: "\<not> abstract_prior_flag r \<and> link_parent st (reversal_original_action_id cmd) = None \<and>
   open_case st (abstract_case r) \<and> case_family (case_records st (abstract_case r)) = Family_Restrict \<and>
   case_head (case_records st (abstract_case r)) = Some (reversal_original_action_id cmd)"
   using RA REC HD by (auto simp: record_at_def link_at_def link_parent_def split: option.splits)
 show thesis using that REC ACT APPLIED HD MORE by blast
qed

lemma unrestrict_state_view:
 assumes REC: "action_records st (reversal_original_action_id cmd) = Some r"
   and KIND: "reversal_kind cmd = TRUST_UNRESTRICT"
   and PRIOR: "\<not> abstract_prior_flag r" and PARENT: "link_parent st (reversal_original_action_id cmd) = None"
 shows "reversal_success_state st cmd w = st\<lparr>
   compositional_consumed_nonces := insert (reversal_nonce_key cmd) (compositional_consumed_nonces st),
   compositional_receipts := (compositional_receipts st)(reversal_id cmd := Some (reversal_witness_receipt w)),
   action_records := (action_records st)(reversal_original_action_id cmd := Some (r\<lparr>abstract_lifecycle := Record_Reversed\<rparr>)),
   restriction_flags := (restriction_flags st)(abstract_subject r := False),
   restriction_heads := (restriction_heads st)(abstract_subject r := popped_head (restriction_heads st (abstract_subject r)) None),
   case_records := (case_records st)(abstract_case r := closed_case (case_records st (abstract_case r)))\<rparr>"
 using assms by (simp add: reversal_success_state_def reversal_original_def Let_def)

lemma unrestrict_preserves_action_identity:
 assumes WF: "regulatory_structure_wf st" and AD: "reversal_admissible st cmd"
   and KIND: "reversal_kind cmd = TRUST_UNRESTRICT"
 shows "action_identity_wf (reversal_success_state st cmd w)"
proof -
 obtain r where REC: "action_records st (reversal_original_action_id cmd) = Some r"
   and ACT: "abstract_action r = Legal_Restrict" and PRIOR: "\<not> abstract_prior_flag r"
   and PARENT: "link_parent st (reversal_original_action_id cmd) = None"
   using unrestrict_context[OF WF AD KIND] by blast
 note VIEW = unrestrict_state_view[OF REC KIND PRIOR PARENT, of w]
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

lemma unrestrict_preserves_effect_history:
 assumes WF: "regulatory_structure_wf st" and AD: "reversal_admissible st cmd"
   and KIND: "reversal_kind cmd = TRUST_UNRESTRICT"
 shows "effect_history_wf (reversal_success_state st cmd w)"
proof -
 obtain r where REC: "action_records st (reversal_original_action_id cmd) = Some r"
   and ACT: "abstract_action r = Legal_Restrict" and PRIOR: "\<not> abstract_prior_flag r"
   and PARENT: "link_parent st (reversal_original_action_id cmd) = None"
   using unrestrict_context[OF WF AD KIND] by blast
 note VIEW = unrestrict_state_view[OF REC KIND PRIOR PARENT, of w]
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

lemma unrestrict_preserves_freeze_structure:
 assumes WF: "regulatory_structure_wf st" and AD: "reversal_admissible st cmd"
   and KIND: "reversal_kind cmd = TRUST_UNRESTRICT"
 shows "freeze_structure_wf (reversal_success_state st cmd w)"
proof -
 let ?post = "reversal_success_state st cmd w"
 let ?id = "reversal_original_action_id cmd"
 obtain r where REC: "action_records st ?id = Some r" and ACT: "abstract_action r = Legal_Restrict"
   and PRIOR: "\<not> abstract_prior_flag r" and PARENT: "link_parent st ?id = None"
   and FAMILY: "case_family (case_records st (abstract_case r)) = Family_Restrict"
   using unrestrict_context[OF WF AD KIND] by blast
 note VIEW = unrestrict_state_view[OF REC KIND PRIOR PARENT, of w]
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

lemma unrestrict_preserves_restriction_structure:
 assumes WF: "regulatory_structure_wf st" and AD: "reversal_admissible st cmd"
   and KIND: "reversal_kind cmd = TRUST_UNRESTRICT"
 shows "restriction_structure_wf (reversal_success_state st cmd w)"
proof -
 let ?post = "reversal_success_state st cmd w"
 let ?id = "reversal_original_action_id cmd"
 obtain r where REC: "action_records st ?id = Some r" and PRIOR: "\<not> abstract_prior_flag r"
   and PARENT: "link_parent st ?id = None"
   and CASE: "case_head (case_records st (abstract_case r)) = Some ?id"
   using unrestrict_context[OF WF AD KIND] by blast
 note VIEW = unrestrict_state_view[OF REC KIND PRIOR PARENT, of w]
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
     using RA REC CASE
     by (auto simp: VIEW popped_head_def closed_case_def record_at_def link_at_def open_case_def
       cong: option.case_cong split: option.splits if_splits)
 qed
qed

lemma unrestrict_preserves_case_structure:
 assumes WF: "regulatory_structure_wf st" and AD: "reversal_admissible st cmd"
   and KIND: "reversal_kind cmd = TRUST_UNRESTRICT"
 shows "case_structure_wf (reversal_success_state st cmd w)"
proof -
 let ?post = "reversal_success_state st cmd w"
 let ?id = "reversal_original_action_id cmd"
 obtain r where REC: "action_records st ?id = Some r" and PRIOR: "\<not> abstract_prior_flag r"
   and PARENT: "link_parent st ?id = None"
   and HD: "head_action (restriction_heads st (abstract_subject r)) = Some ?id"
   using unrestrict_context[OF WF AD KIND] by blast
 note VIEW = unrestrict_state_view[OF REC KIND PRIOR PARENT, of w]
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
     using CC REC HD
     by (auto simp: VIEW closed_case_def popped_head_def record_at_def empty_case_def
       cong: option.case_cong trust_case_phase.case_cong trust_case_family.case_cong
       split: option.splits trust_case_phase.splits trust_case_family.splits if_splits)
 qed
qed


lemma unrestrict_preserves_custody_case:
 assumes WF: "regulatory_structure_wf st" and AD: "reversal_admissible st cmd"
   and KIND: "reversal_kind cmd = TRUST_UNRESTRICT"
 shows "custody_case_wf (reversal_success_state st cmd w)"
proof -
 let ?post = "reversal_success_state st cmd w"
 let ?id = "reversal_original_action_id cmd"
 obtain r where REC: "action_records st ?id = Some r" and ACT: "abstract_action r = Legal_Restrict"
   and PRIOR: "\<not> abstract_prior_flag r" and PARENT: "link_parent st ?id = None"
   and FAMILY: "case_family (case_records st (abstract_case r)) = Family_Restrict"
   using unrestrict_context[OF WF AD KIND] by blast
 note VIEW = unrestrict_state_view[OF REC KIND PRIOR PARENT, of w]
 have CU: "custody_case_wf st" using WF unfolding regulatory_structure_wf_def by blast
 have CUSTODY_FRAME: "custody_records ?post = custody_records st" by (simp add: VIEW)
 have CASE_FRAME: "\<And>c. c \<noteq> abstract_case r \<Longrightarrow> case_records ?post c = case_records st c"
   by (simp add: VIEW)
 have NO_ACTIVE: "\<not> (\<exists>cu. custody_records st (abstract_case r) = Some cu \<and> custody_active cu)"
   using CU[unfolded custody_case_wf_def, THEN conjunct1, rule_format, of "abstract_case r"] FAMILY by simp
 have ACTIVE_AWAY: "\<And>c cu. custody_records st c = Some cu \<Longrightarrow> custody_active cu \<Longrightarrow> c \<noteq> abstract_case r"
   using NO_ACTIVE by blast
 have RECORD_FRAME: "\<And>i q. action_records st i = Some q \<Longrightarrow> abstract_action q = Legal_Seize \<Longrightarrow>
   action_records ?post i = Some q"
   using REC ACT by (auto simp: VIEW split: if_splits)
 have CASE_CUSTODY: "\<And>c. (open_case ?post c \<and> case_family (case_records ?post c) = Family_Custody) =
   (open_case st c \<and> case_family (case_records st c) = Family_Custody)"
   using FAMILY by (auto simp: VIEW closed_case_def open_case_def split: if_splits)
 have EQUIV: "\<forall>c. (open_case ?post c \<and> case_family (case_records ?post c) = Family_Custody) =
   (\<exists>cu. custody_records ?post c = Some cu \<and> custody_active cu)"
   using CU unfolding custody_case_wf_def by (simp only: CASE_CUSTODY CUSTODY_FRAME; blast)
 have LINKS: "\<forall>c cu. custody_records ?post c = Some cu \<longrightarrow>
   (if custody_active cu then
      (\<exists>i r. custody_action cu = Some i \<and> case_head (case_records ?post c) = Some i \<and>
       action_records ?post i = Some r \<and> abstract_lifecycle r = Record_Applied \<and> abstract_action r = Legal_Seize \<and>
       abstract_case r = c \<and> abstract_source r = custody_prior_holder cu \<and> abstract_subject r = custody_prior_holder cu \<and>
       abstract_destination r = custody_custodian cu \<and> abstract_custodian r = custody_custodian cu \<and>
       abstract_amount r = custody_amount cu \<and> custody_amount cu > 0 \<and> custody_prior_holder cu \<noteq> 0 \<and>
       custody_custodian cu \<noteq> 0 \<and> custody_prior_holder cu \<noteq> custody_custodian cu)
    else custody_amount cu = 0)"
 proof (intro allI impI)
   fix c cu
   assume POST: "custody_records ?post c = Some cu"
   have OLD: "custody_records st c = Some cu" using POST CUSTODY_FRAME by simp
   let ?link = "\<lambda>s. \<exists>i r. custody_action cu = Some i \<and> case_head (case_records s c) = Some i \<and>
       action_records s i = Some r \<and> abstract_lifecycle r = Record_Applied \<and> abstract_action r = Legal_Seize \<and>
       abstract_case r = c \<and> abstract_source r = custody_prior_holder cu \<and> abstract_subject r = custody_prior_holder cu \<and>
       abstract_destination r = custody_custodian cu \<and> abstract_custodian r = custody_custodian cu \<and>
       abstract_amount r = custody_amount cu \<and> custody_amount cu > 0 \<and> custody_prior_holder cu \<noteq> 0 \<and>
       custody_custodian cu \<noteq> 0 \<and> custody_prior_holder cu \<noteq> custody_custodian cu"
   have BEFORE: "if custody_active cu then ?link st else custody_amount cu = 0"
     using CU OLD unfolding custody_case_wf_def by blast
   show "if custody_active cu then ?link ?post else custody_amount cu = 0"
   proof (cases "custody_active cu")
     case False
     then show ?thesis using BEFORE by simp
   next
     case True
     have AWAY: "c \<noteq> abstract_case r" by (rule ACTIVE_AWAY[OF OLD True])
     have CS: "case_records ?post c = case_records st c" by (rule CASE_FRAME[OF AWAY])
     obtain i r where W: "custody_action cu = Some i \<and> case_head (case_records st c) = Some i \<and>
       action_records st i = Some r \<and> abstract_lifecycle r = Record_Applied \<and> abstract_action r = Legal_Seize \<and>
       abstract_case r = c \<and> abstract_source r = custody_prior_holder cu \<and> abstract_subject r = custody_prior_holder cu \<and>
       abstract_destination r = custody_custodian cu \<and> abstract_custodian r = custody_custodian cu \<and>
       abstract_amount r = custody_amount cu \<and> custody_amount cu > 0 \<and> custody_prior_holder cu \<noteq> 0 \<and>
       custody_custodian cu \<noteq> 0 \<and> custody_prior_holder cu \<noteq> custody_custodian cu"
       using BEFORE True by auto
     have REC: "action_records ?post i = Some r" using RECORD_FRAME W by blast
     show ?thesis using True W CS REC by auto
   qed
 qed
 show ?thesis using EQUIV LINKS unfolding custody_case_wf_def by blast
qed

theorem unrestrict_preserves_regulatory_structure:
 assumes WF: "regulatory_structure_wf st" and AD: "reversal_admissible st cmd"
   and KIND: "reversal_kind cmd = TRUST_UNRESTRICT"
 shows "regulatory_structure_wf (reversal_success_state st cmd w)"
 using unrestrict_preserves_action_identity[OF WF AD KIND]
   unrestrict_preserves_effect_history[OF WF AD KIND]
   unrestrict_preserves_freeze_structure[OF WF AD KIND]
   unrestrict_preserves_restriction_structure[OF WF AD KIND]
   unrestrict_preserves_case_structure[OF WF AD KIND]
   unrestrict_preserves_custody_case[OF WF AD KIND]
 unfolding regulatory_structure_wf_def by blast

lemma unrestrict_preserves_accounting_state_wf:
 assumes WF: "state_wf A C st" and AD: "reversal_admissible st cmd"
   and KIND: "reversal_kind cmd = TRUST_UNRESTRICT"
 shows "accounting_state_wf A C (reversal_success_state st cmd w)"
proof -
 let ?post = "reversal_success_state st cmd w"
 have AC: "accounting_state_wf A C st" and REG: "regulatory_structure_wf st"
   using WF unfolding state_wf_def by blast+
 obtain r where REC: "action_records st (reversal_original_action_id cmd) = Some r"
   and PRIOR: "\<not> abstract_prior_flag r" and PARENT: "link_parent st (reversal_original_action_id cmd) = None"
   and OPEN: "open_case st (abstract_case r)"
   using unrestrict_context[OF REG AD KIND] by blast
 note VIEW = unrestrict_state_view[OF REC KIND PRIOR PARENT, of w]
 have IN: "abstract_case r \<in> C"
   using AC OPEN by (auto simp: accounting_state_wf_def case_scope_def open_case_def empty_case_def)
 have BAL: "balance_wf A ?post" using AC by (simp add: accounting_state_wf_def balance_wf_def VIEW)
 have SCOPE: "case_scope C ?post" using AC IN by (auto simp: accounting_state_wf_def case_scope_def VIEW)
 have CU_FRAME: "custody_consistent C ?post = custody_consistent C st"
   by (simp add: custody_consistent_def active_custody_sum_def VIEW)
 have CU: "custody_consistent C ?post" using AC CU_FRAME unfolding accounting_state_wf_def by blast
 have REF: "custody_case_wf ?post" by (rule unrestrict_preserves_custody_case[OF REG AD KIND])
 show ?thesis using BAL SCOPE CU REF unfolding accounting_state_wf_def by blast
qed

theorem unrestrict_preserves_state_wf:
 assumes WF: "state_wf A C st" and AD: "reversal_admitted st sender time cmd w"
   and KIND: "reversal_kind cmd = TRUST_UNRESTRICT"
 shows "state_wf A C (reversal_success_state st cmd w)"
proof -
 have ADM: "reversal_admissible st cmd" using AD by (simp add: reversal_admitted_def)
 have REG: "regulatory_structure_wf st" using WF by (simp add: state_wf_def)
 show ?thesis using unrestrict_preserves_accounting_state_wf[OF WF ADM KIND]
   unrestrict_preserves_regulatory_structure[OF REG ADM KIND] unfolding state_wf_def by blast
qed

theorem authority_rotation_preserves_state_wf:
 "state_wf A C (rotate_authority st ref account active) = state_wf A C st"
 by (simp only: state_wf_def authority_rotation_preserves_structure; simp add: accounting_state_wf_def
   balance_wf_def case_scope_def custody_consistent_def active_custody_sum_def custody_case_wf_def
   rotate_authority_def open_case_def)

theorem dependency_rebind_preserves_state_wf:
 "state_wf A C (rebind_dependency st kind binding root) = state_wf A C st"
 by (simp only: state_wf_def dependency_rebind_preserves_structure; simp add: accounting_state_wf_def
   balance_wf_def case_scope_def custody_consistent_def active_custody_sum_def custody_case_wf_def
   rebind_dependency_def open_case_def)

end
