theory TRUST_Regulatory_Preservation
  imports TRUST_Custody_Accounting
begin

lemma structure_case_head_owner:
 assumes WF: "case_structure_wf st" and HD: "case_head (case_records st c) = Some i"
 shows "case_phase (case_records st c) = Case_Open \<and> action_records st i \<noteq> None \<and>
   abstract_case (record_at st i) = c"
proof -
 note at_c = WF[unfolded case_structure_wf_def, rule_format, of c]
 show ?thesis using at_c HD by (cases "case_phase (case_records st c)")
   (auto simp: empty_case_def split: option.splits)
qed

lemma freeze_chain_member_fields:
 assumes CH: "live_freeze_chain st a c xs" and IN: "i \<in> set xs"
 shows "action_records st i \<noteq> None \<and> effect_links st i \<noteq> None \<and>
   abstract_action (record_at st i) = Legal_Freeze \<and> abstract_lifecycle (record_at st i) = Record_Applied \<and>
   abstract_subject (record_at st i) = a \<and> abstract_case (record_at st i) = c"
 using CH IN by (induction xs) auto

lemma fresh_action_not_in_freeze_chain:
 assumes CH: "live_freeze_chain st a c xs" and FR: "action_records st i = None"
 shows "i \<notin> set xs"
proof
 assume IN: "i \<in> set xs"
 have "action_records st i \<noteq> None" using freeze_chain_member_fields[OF CH IN] by blast
 with FR show False by simp
qed

lemma freeze_chain_read_frame:
 assumes FRAME: "\<forall>i\<in>set xs. action_records st' i = action_records st i \<and> effect_links st' i = effect_links st i"
 shows "live_freeze_chain st' a c xs = live_freeze_chain st a c xs"
 using FRAME by (induction xs) (auto simp: record_at_def link_at_def)

lemma freeze_tail_survives_head_lifecycle_change:
 assumes CH: "live_freeze_chain st a c (i # xs)" and DIST: "distinct (i # xs)"
 shows "live_freeze_chain (st\<lparr>action_records := (action_records st)
   (i := Some ((record_at st i)\<lparr>abstract_lifecycle := Record_Reversed\<rparr>))\<rparr>) a c xs"
proof -
 let ?st' = "st\<lparr>action_records := (action_records st)
   (i := Some ((record_at st i)\<lparr>abstract_lifecycle := Record_Reversed\<rparr>))\<rparr>"
 have TAIL: "live_freeze_chain st a c xs" using CH by simp
 have OUT: "i \<notin> set xs" using DIST by simp
 have FRAME: "\<forall>j\<in>set xs. action_records ?st' j = action_records st j \<and> effect_links ?st' j = effect_links st j"
   using OUT by auto
 have EQ: "live_freeze_chain ?st' a c xs = live_freeze_chain st a c xs"
   by (rule freeze_chain_read_frame[OF FRAME])
 show ?thesis using TAIL EQ by simp
qed

lemma effect_history_parent_fields:
 assumes WF: "effect_history_wf st" and E: "effect_links st i = Some e" and P: "effect_parent e = Some j"
 shows "action_records st j \<noteq> None \<and> effect_links st j \<noteq> None \<and>
   abstract_action (record_at st i) = Legal_Freeze \<and> abstract_action (record_at st j) = Legal_Freeze \<and>
   abstract_subject (record_at st j) = abstract_subject (record_at st i) \<and>
   abstract_case (record_at st j) = abstract_case (record_at st i) \<and>
   effect_generation (link_at st j) < effect_generation e \<and>
   abstract_prior_amount (record_at st i) = abstract_amount (record_at st j)"
proof -
 note at_i = WF[unfolded effect_history_wf_def, rule_format, of i e]
 show ?thesis using at_i E P by (auto simp: Let_def)
qed

lemma freeze_forward_case_split:
 assumes WF: "regulatory_structure_wf st" and SH: "forward_shape_wf st cmd"
   and KIND: "forward_action cmd = Legal_Freeze"
 shows "(case head_action (freeze_heads st (forward_subject cmd)) of
   None \<Rightarrow> case_records st (forward_case cmd) = empty_case \<and> frozen_targets st (forward_subject cmd) = 0
 | Some i \<Rightarrow> abstract_case (record_at st i) = forward_case cmd \<and> open_case st (forward_case cmd) \<and>
   case_family (case_records st (forward_case cmd)) = Family_Freeze \<and> case_head (case_records st (forward_case cmd)) = Some i)"
 and "frozen_targets st (forward_subject cmd) < forward_amount cmd"
proof -
 have F: "freeze_structure_wf st" and C: "case_structure_wf st"
   using WF unfolding regulatory_structure_wf_def by blast+
 have ADM: "overlay_admissible (case_records st (forward_case cmd)) (freeze_heads st (forward_subject cmd))"
   and INC: "frozen_targets st (forward_subject cmd) < forward_amount cmd"
   using SH KIND by (auto simp: forward_shape_wf_def)
 note at_a = F[unfolded freeze_structure_wf_def, rule_format, of "forward_subject cmd"]
 note at_c = C[unfolded case_structure_wf_def, rule_format, of "forward_case cmd"]
 show "(case head_action (freeze_heads st (forward_subject cmd)) of
   None \<Rightarrow> case_records st (forward_case cmd) = empty_case \<and> frozen_targets st (forward_subject cmd) = 0
 | Some i \<Rightarrow> abstract_case (record_at st i) = forward_case cmd \<and> open_case st (forward_case cmd) \<and>
   case_family (case_records st (forward_case cmd)) = Family_Freeze \<and> case_head (case_records st (forward_case cmd)) = Some i)"
 proof (cases "head_action (freeze_heads st (forward_subject cmd))")
   case None
   have PH: "case_phase (case_records st (forward_case cmd)) = Case_None"
     using ADM None by (simp add: overlay_admissible_def)
   have EMPTY: "case_records st (forward_case cmd) = empty_case" using at_c PH by simp
   show ?thesis using None at_a EMPTY by simp
 next
   case (Some i)
   have HD: "case_head (case_records st (forward_case cmd)) = Some i"
     using ADM Some by (simp add: overlay_admissible_def)
   have OWNER: "case_phase (case_records st (forward_case cmd)) = Case_Open \<and>
     action_records st i \<noteq> None \<and> abstract_case (record_at st i) = forward_case cmd"
     by (rule structure_case_head_owner[OF C HD])
   show ?thesis using Some at_a HD OWNER by (auto simp: open_case_def)
 qed
 show "frozen_targets st (forward_subject cmd) < forward_amount cmd" by (rule INC)
qed

lemma freeze_head_pop_view:
 assumes WF: "regulatory_structure_wf st" and HD: "head_action (freeze_heads st a) = Some i"
 shows "\<exists>xs. distinct (i # xs) \<and> live_freeze_chain st a (abstract_case (record_at st i)) (i # xs) \<and>
   link_parent st i = (case xs of [] \<Rightarrow> None | j # _ \<Rightarrow> Some j) \<and>
   abstract_prior_amount (record_at st i) = (case xs of [] \<Rightarrow> 0 | j # _ \<Rightarrow> abstract_amount (record_at st j))"
 and "head_generation (popped_head (freeze_heads st a) (link_parent st i)) = head_generation (freeze_heads st a) + 1"
 and "effect_generation (link_at st i) < head_generation (popped_head (freeze_heads st a) (link_parent st i))"
proof -
 have F: "freeze_structure_wf st" and H: "effect_history_wf st"
   using WF unfolding regulatory_structure_wf_def by blast+
 note at_a = F[unfolded freeze_structure_wf_def, rule_format, of a]
 obtain xs where DIST: "distinct (i # xs)" and CH: "live_freeze_chain st a (abstract_case (record_at st i)) (i # xs)"
   using at_a HD by auto
 obtain e where E: "effect_links st i = Some e" using CH by (cases "effect_links st i") auto
 have P: "effect_parent e = (case xs of [] \<Rightarrow> None | j # _ \<Rightarrow> Some j)"
   using CH E by (simp add: link_at_def)
 note at_i = H[unfolded effect_history_wf_def, rule_format, of i e]
 have PRIOR: "abstract_prior_amount (record_at st i) = (case xs of [] \<Rightarrow> 0 | j # _ \<Rightarrow> abstract_amount (record_at st j))"
 proof (cases xs)
   case Nil
   show ?thesis using at_i E P Nil by (auto simp: Let_def)
 next
   case (Cons j ys)
   have PJ: "effect_parent e = Some j" using P Cons by simp
   have REL: "abstract_prior_amount (record_at st i) = abstract_amount (record_at st j)"
     using effect_history_parent_fields[OF H E PJ] by blast
   show ?thesis using Cons REL by simp
 qed
 have LP: "link_parent st i = (case xs of [] \<Rightarrow> None | j # _ \<Rightarrow> Some j)"
   using E P by (simp add: link_parent_def link_at_def)
 show "\<exists>xs. distinct (i # xs) \<and> live_freeze_chain st a (abstract_case (record_at st i)) (i # xs) \<and>
   link_parent st i = (case xs of [] \<Rightarrow> None | j # _ \<Rightarrow> Some j) \<and>
   abstract_prior_amount (record_at st i) = (case xs of [] \<Rightarrow> 0 | j # _ \<Rightarrow> abstract_amount (record_at st j))"
   using DIST CH LP PRIOR by blast
 show "head_generation (popped_head (freeze_heads st a) (link_parent st i)) = head_generation (freeze_heads st a) + 1"
   by (simp add: popped_head_def)
 have BOUND: "effect_generation e \<le> head_generation (freeze_heads st a)"
   using at_i E CH by (auto simp: Let_def)
 show "effect_generation (link_at st i) < head_generation (popped_head (freeze_heads st a) (link_parent st i))"
   using BOUND E by (simp add: link_at_def popped_head_def)
qed


lemma action_in_empty_case_absent:
 assumes WF: "action_identity_wf st" and EMPTY: "case_phase (case_records st c) = Case_None"
   and RECORD: "action_records st i = Some r"
 shows "abstract_case r \<noteq> c"
 using WF EMPTY RECORD unfolding action_identity_wf_def by blast

lemma restrict_forward_starts_empty:
 assumes WF: "regulatory_structure_wf st" and SH: "forward_shape_wf st cmd"
   and KIND: "forward_action cmd = Legal_Restrict"
 shows "head_action (restriction_heads st (forward_subject cmd)) = None \<and>
   \<not> restriction_flags st (forward_subject cmd) \<and>
   case_records st (forward_case cmd) = empty_case"
proof -
 have R: "restriction_structure_wf st" and C: "case_structure_wf st"
   using WF unfolding regulatory_structure_wf_def by blast+
 have EMPTYHEAD: "head_action (restriction_heads st (forward_subject cmd)) = None"
   using SH KIND unfolding forward_shape_wf_def restrict_would_not_change_state_def overlay_admissible_def
   by (cases "head_action (restriction_heads st (forward_subject cmd))") auto
 note at_a = R[unfolded restriction_structure_wf_def, rule_format, of "forward_subject cmd"]
 note at_c = C[unfolded case_structure_wf_def, rule_format, of "forward_case cmd"]
 have PH: "case_phase (case_records st (forward_case cmd)) = Case_None"
   using SH KIND EMPTYHEAD by (simp add: forward_shape_wf_def overlay_admissible_def)
 show ?thesis using at_a at_c EMPTYHEAD PH by simp
qed

lemma forward_record_lookup:
 "action_records (forward_success_state st cmd w) i =
  (if i = forward_action_id cmd then Some (forward_action_record st cmd w) else action_records st i)"
 by (cases "forward_action cmd") (simp_all add: forward_success_state_def base_forward_success_def Let_def)

lemma forward_record_fresh_preserves_old:
 assumes FRESH: "forward_fresh st cmd" and OLD: "action_records st i = Some r"
 shows "action_records (forward_success_state st cmd w) i = Some r"
 using FRESH OLD by (auto simp: forward_fresh_def forward_record_lookup)

lemma restrict_preserves_action_identity:
 assumes WF: "regulatory_structure_wf st" and SH: "forward_shape_wf st cmd"
   and FRESH: "forward_fresh st cmd" and KIND: "forward_action cmd = Legal_Restrict"
 shows "action_identity_wf (forward_success_state st cmd w)"
proof -
 have AI: "action_identity_wf st" and H: "effect_history_wf st"
   using WF unfolding regulatory_structure_wf_def by blast+
 have START: "head_action (restriction_heads st (forward_subject cmd)) = None \<and>
   \<not> restriction_flags st (forward_subject cmd) \<and> case_records st (forward_case cmd) = empty_case"
   by (rule restrict_forward_starts_empty[OF WF SH KIND])
 have OLDC: "\<And>i r. action_records st i = Some r \<Longrightarrow> abstract_case r \<noteq> forward_case cmd"
   using action_in_empty_case_absent[OF AI] START by (simp add: empty_case_def)
 show ?thesis using AI SH FRESH KIND START OLDC
   unfolding action_identity_wf_def
   by (auto simp: forward_success_state_def base_forward_success_def forward_action_record_def
       pushed_head_def pushed_link_def opened_overlay_def forward_fresh_def forward_shape_wf_def
       overlay_shape_def Let_def empty_case_def
       cong: option.case_cong legal_action_kind.case_cong
       split: if_splits legal_action_kind.splits)
qed


lemma forward_effect_lookup_away:
 assumes "i \<noteq> forward_action_id cmd"
 shows "effect_links (forward_success_state st cmd w) i = effect_links st i"
 using assms by (cases "forward_action cmd")
   (simp_all add: forward_success_state_def base_forward_success_def Let_def)

lemma forward_preserves_existing_freeze_chain:
 assumes CH: "live_freeze_chain st a c xs" and FR: "forward_fresh st cmd"
 shows "live_freeze_chain (forward_success_state st cmd w) a c xs"
proof -
 have FRESH: "action_records st (forward_action_id cmd) = None" using FR by (simp add: forward_fresh_def)
 have OUT: "forward_action_id cmd \<notin> set xs" by (rule fresh_action_not_in_freeze_chain[OF CH FRESH])
 have FRAME: "\<forall>i\<in>set xs. action_records (forward_success_state st cmd w) i = action_records st i \<and>
   effect_links (forward_success_state st cmd w) i = effect_links st i"
   using OUT by (auto simp: forward_record_lookup forward_effect_lookup_away)
 have EQ: "live_freeze_chain (forward_success_state st cmd w) a c xs = live_freeze_chain st a c xs"
   by (rule freeze_chain_read_frame[OF FRAME])
 show ?thesis using EQ CH by simp
qed

lemma restrict_preserves_effect_history:
 assumes WF: "regulatory_structure_wf st" and SH: "forward_shape_wf st cmd"
   and FR: "forward_fresh st cmd" and KIND: "forward_action cmd = Legal_Restrict"
 shows "effect_history_wf (forward_success_state st cmd w)"
proof -
 let ?post = "forward_success_state st cmd w"
 have H: "effect_history_wf st" using WF unfolding regulatory_structure_wf_def by blast
 have START: "head_action (restriction_heads st (forward_subject cmd)) = None \<and>
   \<not> restriction_flags st (forward_subject cmd) \<and> case_records st (forward_case cmd) = empty_case"
   by (rule restrict_forward_starts_empty[OF WF SH KIND])
 have HEAD: "head_action (restriction_heads st (forward_subject cmd)) = None"
   and FLAG: "\<not> restriction_flags st (forward_subject cmd)" using START by auto
 have SHAPE: "forward_action_id cmd \<noteq> 0 \<and> forward_subject cmd \<noteq> 0 \<and> forward_case cmd \<noteq> 0"
   using SH unfolding forward_shape_wf_def by blast
 have FRESH: "action_records st (forward_action_id cmd) = None" using FR by (simp add: forward_fresh_def)
 show ?thesis
   unfolding effect_history_wf_def
 proof (intro allI impI)
   fix i :: trust_action_id and e :: compositional_effect_link
   assume E: "effect_links ?post i = Some e"
   note HI = H[unfolded effect_history_wf_def, rule_format, of i e]
   show "action_records ?post i \<noteq> None \<and> i \<noteq> 0 \<and>
     (let r = record_at ?post i in abstract_subject r \<noteq> 0 \<and> abstract_case r \<noteq> 0 \<and>
      abstract_action r \<in> {Legal_Freeze, Legal_Restrict} \<and> effect_generation e > 0 \<and>
      effect_generation e \<le> head_generation
        (if abstract_action r = Legal_Freeze then freeze_heads ?post (abstract_subject r)
         else restriction_heads ?post (abstract_subject r)) \<and>
      (case effect_parent e of None \<Rightarrow> abstract_prior_amount r = 0 \<and> \<not> abstract_prior_flag r
       | Some j \<Rightarrow> abstract_action r = Legal_Freeze \<and>
           action_records ?post j \<noteq> None \<and> effect_links ?post j \<noteq> None \<and>
           abstract_action (record_at ?post j) = Legal_Freeze \<and>
           abstract_subject (record_at ?post j) = abstract_subject r \<and>
           abstract_case (record_at ?post j) = abstract_case r \<and>
           effect_generation (link_at ?post j) < effect_generation e \<and>
           abstract_prior_amount r = abstract_amount (record_at ?post j)))"
     using HI E SHAPE FRESH HEAD FLAG
     by (auto simp: KIND forward_success_state_def base_forward_success_def forward_action_record_def
         pushed_head_def pushed_link_def record_at_def link_at_def Let_def
         cong: option.case_cong split: option.splits if_splits; presburger)
 qed
qed


lemma record_at_not_in_empty_case:
 assumes AI: "action_identity_wf st" and EMPTY: "case_records st c = empty_case"
   and R: "action_records st i \<noteq> None"
 shows "abstract_case (record_at st i) \<noteq> c"
proof -
 obtain r where REC: "action_records st i = Some r" using R by (cases "action_records st i") auto
 have "abstract_case r \<noteq> c" using action_in_empty_case_absent[OF AI _ REC] EMPTY
   by (simp add: empty_case_def)
 then show ?thesis by (simp add: record_at_def REC)
qed

lemma restrict_preserves_restriction_structure:
 assumes WF: "regulatory_structure_wf st" and SH: "forward_shape_wf st cmd"
   and FR: "forward_fresh st cmd" and KIND: "forward_action cmd = Legal_Restrict"
 shows "restriction_structure_wf (forward_success_state st cmd w)"
proof -
 let ?post = "forward_success_state st cmd w"
 have R: "restriction_structure_wf st" and AI: "action_identity_wf st"
   using WF unfolding regulatory_structure_wf_def by blast+
 have START: "head_action (restriction_heads st (forward_subject cmd)) = None \<and>
   \<not> restriction_flags st (forward_subject cmd) \<and> case_records st (forward_case cmd) = empty_case"
   by (rule restrict_forward_starts_empty[OF WF SH KIND])
 have OLDCASE: "\<And>i. action_records st i \<noteq> None \<Longrightarrow> abstract_case (record_at st i) \<noteq> forward_case cmd"
   using record_at_not_in_empty_case[OF AI] START by blast
 have FRESH: "action_records st (forward_action_id cmd) = None" using FR by (simp add: forward_fresh_def)
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
     using RA START FRESH OLDCASE
     by (auto simp: KIND forward_success_state_def base_forward_success_def forward_action_record_def
       pushed_head_def pushed_link_def opened_overlay_def record_at_def link_at_def open_case_def empty_case_def Let_def
       cong: option.case_cong split: option.splits if_splits)
 qed
qed

lemma restrict_preserves_case_structure:
 assumes WF: "regulatory_structure_wf st" and SH: "forward_shape_wf st cmd"
   and FR: "forward_fresh st cmd" and KIND: "forward_action cmd = Legal_Restrict"
 shows "case_structure_wf (forward_success_state st cmd w)"
proof -
 let ?post = "forward_success_state st cmd w"
 have C: "case_structure_wf st" using WF unfolding regulatory_structure_wf_def by blast
 have START: "head_action (restriction_heads st (forward_subject cmd)) = None \<and>
   \<not> restriction_flags st (forward_subject cmd) \<and> case_records st (forward_case cmd) = empty_case"
   by (rule restrict_forward_starts_empty[OF WF SH KIND])
 have FRESH: "action_records st (forward_action_id cmd) = None" using FR by (simp add: forward_fresh_def)
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
     using CC START FRESH
     by (auto simp: KIND forward_success_state_def base_forward_success_def forward_action_record_def
       pushed_head_def pushed_link_def opened_overlay_def record_at_def link_at_def empty_case_def Let_def
       cong: option.case_cong trust_case_phase.case_cong trust_case_family.case_cong
       split: option.splits trust_case_phase.splits trust_case_family.splits if_splits)
 qed
qed


lemma restrict_preserves_freeze_structure:
 assumes WF: "regulatory_structure_wf st" and SH: "forward_shape_wf st cmd"
   and FR: "forward_fresh st cmd" and KIND: "forward_action cmd = Legal_Restrict"
 shows "freeze_structure_wf (forward_success_state st cmd w)"
proof -
 let ?post = "forward_success_state st cmd w"
 have F: "freeze_structure_wf st" and AI: "action_identity_wf st"
   using WF unfolding regulatory_structure_wf_def by blast+
 have START: "head_action (restriction_heads st (forward_subject cmd)) = None \<and>
   \<not> restriction_flags st (forward_subject cmd) \<and> case_records st (forward_case cmd) = empty_case"
   by (rule restrict_forward_starts_empty[OF WF SH KIND])
 have FRESH: "action_records st (forward_action_id cmd) = None" using FR by (simp add: forward_fresh_def)
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
     then show ?thesis using FA by (simp add: KIND forward_success_state_def base_forward_success_def Let_def)
   next
     case (Some i)
     obtain xs where DIST: "distinct (i # xs)" and CH: "live_freeze_chain st a (abstract_case (record_at st i)) (i # xs)"
       using FA Some by auto
     have REC: "action_records st i \<noteq> None" using CH by simp
     have NE: "i \<noteq> forward_action_id cmd" using REC FRESH by auto
     have OLDCASE: "abstract_case (record_at st i) \<noteq> forward_case cmd"
       using record_at_not_in_empty_case[OF AI _ REC] START by blast
     have NEWCH: "live_freeze_chain ?post a (abstract_case (record_at st i)) (i # xs)"
       by (rule forward_preserves_existing_freeze_chain[OF CH FR])
     show ?thesis using Some FA DIST NEWCH NE OLDCASE
       by (auto simp: KIND forward_success_state_def base_forward_success_def forward_action_record_def
         opened_overlay_def record_at_def link_at_def open_case_def Let_def
         cong: option.case_cong intro!: exI[where x=xs])
   qed
 qed
qed

lemma restrict_preserves_custody_case:
 assumes WF: "regulatory_structure_wf st" and SH: "forward_shape_wf st cmd"
   and FR: "forward_fresh st cmd" and KIND: "forward_action cmd = Legal_Restrict"
 shows "custody_case_wf (forward_success_state st cmd w)"
proof -
 let ?post = "forward_success_state st cmd w"
 have CU: "custody_case_wf st" using WF unfolding regulatory_structure_wf_def by blast
 have START: "head_action (restriction_heads st (forward_subject cmd)) = None \<and>
   \<not> restriction_flags st (forward_subject cmd) \<and> case_records st (forward_case cmd) = empty_case"
   by (rule restrict_forward_starts_empty[OF WF SH KIND])
 have EMPTY: "case_records st (forward_case cmd) = empty_case" using START by blast
 have CUSTODY_FRAME: "custody_records ?post = custody_records st"
   using KIND by (simp add: forward_success_state_def base_forward_success_def Let_def)
 have CASE_FRAME: "\<And>c. c \<noteq> forward_case cmd \<Longrightarrow> case_records ?post c = case_records st c"
   using KIND by (simp add: forward_success_state_def base_forward_success_def Let_def)
 have NO_NEW_ACTIVE: "\<not> (\<exists>cu. custody_records st (forward_case cmd) = Some cu \<and> custody_active cu)"
   by (rule custody_case_none_is_inactive[OF CU EMPTY])
 have ACTIVE_AWAY: "\<And>c cu. custody_records st c = Some cu \<Longrightarrow> custody_active cu \<Longrightarrow> c \<noteq> forward_case cmd"
   using NO_NEW_ACTIVE by blast
 have RECORD_FRAME: "\<And>i r. action_records st i = Some r \<Longrightarrow> action_records ?post i = Some r"
   by (rule forward_record_fresh_preserves_old[OF FR])
 have CASE_CUSTODY: "\<And>c. (open_case ?post c \<and> case_family (case_records ?post c) = Family_Custody) =
   (open_case st c \<and> case_family (case_records st c) = Family_Custody)"
   using EMPTY KIND by (auto simp: forward_success_state_def base_forward_success_def opened_overlay_def
     empty_case_def open_case_def Let_def split: if_splits)
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
     have AWAY: "c \<noteq> forward_case cmd" by (rule ACTIVE_AWAY[OF OLD True])
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

theorem restrict_preserves_regulatory_structure:
 assumes WF: "regulatory_structure_wf st" and SH: "forward_shape_wf st cmd"
   and FR: "forward_fresh st cmd" and KIND: "forward_action cmd = Legal_Restrict"
 shows "regulatory_structure_wf (forward_success_state st cmd w)"
 using restrict_preserves_action_identity[OF WF SH FR KIND]
   restrict_preserves_effect_history[OF WF SH FR KIND]
   restrict_preserves_freeze_structure[OF WF SH FR KIND]
   restrict_preserves_restriction_structure[OF WF SH FR KIND]
   restrict_preserves_case_structure[OF WF SH FR KIND]
   restrict_preserves_custody_case[OF WF SH FR KIND]
 unfolding regulatory_structure_wf_def by blast


lemma seize_starts_empty_case:
 assumes WF: "regulatory_structure_wf st" and SH: "forward_shape_wf st cmd"
   and KIND: "forward_action cmd = Legal_Seize"
 shows "case_records st (forward_case cmd) = empty_case"
proof -
 have C: "case_structure_wf st" using WF unfolding regulatory_structure_wf_def by blast
 note AT = C[unfolded case_structure_wf_def, rule_format, of "forward_case cmd"]
 have CLOSED: "\<not> terminal_case st (forward_case cmd)" and NOTOPEN: "\<not> open_case st (forward_case cmd)"
   using SH KIND by (auto simp: forward_shape_wf_def)
 show ?thesis using AT CLOSED NOTOPEN
   by (cases "case_phase (case_records st (forward_case cmd))") (auto simp: terminal_case_def open_case_def)
qed

lemma nonoverlay_forward_views:
 assumes KIND: "forward_action cmd \<notin> {Legal_Freeze,Legal_Restrict}"
 shows "freeze_heads (forward_success_state st cmd w) = freeze_heads st"
   "restriction_heads (forward_success_state st cmd w) = restriction_heads st"
   "frozen_targets (forward_success_state st cmd w) = frozen_targets st"
   "restriction_flags (forward_success_state st cmd w) = restriction_flags st"
   "effect_links (forward_success_state st cmd w) = effect_links st"
 using KIND by (cases "forward_action cmd"; simp add: forward_success_state_def base_forward_success_def Let_def)+

lemma nonoverlay_preserves_effect_history:
 assumes H: "effect_history_wf st" and FR: "forward_fresh st cmd"
   and KIND: "forward_action cmd \<notin> {Legal_Freeze,Legal_Restrict}"
 shows "effect_history_wf (forward_success_state st cmd w)"
proof -
 let ?post = "forward_success_state st cmd w"
 have FRESH: "action_records st (forward_action_id cmd) = None" using FR by (simp add: forward_fresh_def)
 note V = nonoverlay_forward_views[OF KIND, of st w]
 show ?thesis unfolding effect_history_wf_def
 proof (intro allI impI)
   fix i e
   assume E: "effect_links ?post i = Some e"
   have OLD: "effect_links st i = Some e" using E V by simp
   note HI = H[unfolded effect_history_wf_def, rule_format, OF OLD]
   show "action_records ?post i \<noteq> None \<and> i \<noteq> 0 \<and>
     (let r = record_at ?post i in abstract_subject r \<noteq> 0 \<and> abstract_case r \<noteq> 0 \<and>
      abstract_action r \<in> {Legal_Freeze,Legal_Restrict} \<and> effect_generation e > 0 \<and>
      effect_generation e \<le> head_generation (if abstract_action r = Legal_Freeze
        then freeze_heads ?post (abstract_subject r) else restriction_heads ?post (abstract_subject r)) \<and>
      (case effect_parent e of None \<Rightarrow> abstract_prior_amount r = 0 \<and> \<not> abstract_prior_flag r
       | Some j \<Rightarrow> abstract_action r = Legal_Freeze \<and> action_records ?post j \<noteq> None \<and>
        effect_links ?post j \<noteq> None \<and> abstract_action (record_at ?post j) = Legal_Freeze \<and>
        abstract_subject (record_at ?post j) = abstract_subject r \<and> abstract_case (record_at ?post j) = abstract_case r \<and>
        effect_generation (link_at ?post j) < effect_generation e \<and>
        abstract_prior_amount r = abstract_amount (record_at ?post j)))"
     using HI FRESH by (auto simp: V forward_record_lookup record_at_def link_at_def Let_def
       cong: option.case_cong split: option.splits if_splits)
 qed
qed

lemma seize_preserves_action_identity:
 assumes WF: "regulatory_structure_wf st" and SH: "forward_shape_wf st cmd"
   and FR: "forward_fresh st cmd" and KIND: "forward_action cmd = Legal_Seize"
 shows "action_identity_wf (forward_success_state st cmd w)"
proof -
 have AI: "action_identity_wf st" and H: "effect_history_wf st"
   using WF unfolding regulatory_structure_wf_def by blast+
 have EMPTY: "case_records st (forward_case cmd) = empty_case"
   by (rule seize_starts_empty_case[OF WF SH KIND])
 have OLDC: "\<And>i r. action_records st i = Some r \<Longrightarrow> abstract_case r \<noteq> forward_case cmd"
   using action_in_empty_case_absent[OF AI] EMPTY by (simp add: empty_case_def)
 have FRESH: "action_records st (forward_action_id cmd) = None" using FR by (simp add: forward_fresh_def)
 have NO_EFFECT: "effect_links st (forward_action_id cmd) = None"
  proof (cases "effect_links st (forward_action_id cmd)")
   case None
   then show ?thesis by simp
 next
   case (Some e)
   note HI = H[unfolded effect_history_wf_def, rule_format, of "forward_action_id cmd" e]
   show ?thesis using HI Some FRESH by auto
 qed
 show ?thesis using AI SH FR KIND EMPTY OLDC NO_EFFECT
   unfolding action_identity_wf_def
   by (auto simp: KIND forward_success_state_def base_forward_success_def forward_action_record_def
     opened_custody_def forward_fresh_def forward_shape_wf_def transfer_shape_def empty_case_def Let_def
     cong: option.case_cong legal_action_kind.case_cong split: if_splits legal_action_kind.splits)
qed


definition state_wf where
 "state_wf A C st \<longleftrightarrow> accounting_state_wf A C st \<and> regulatory_structure_wf st"

theorem native_initial_state_wf:
 "state_wf {holder} {} (native_initial_state holder supply ref authority bindings root)"
 using native_initial_accounting_state_wf initial_structure unfolding state_wf_def by blast

theorem ordinary_transfer_preserves_state_wf:
 assumes WF: "state_wf A C st" and AD: "ordinary_transfer_allowed st src dst amount"
 shows "state_wf (A \<union> {src,dst}) C (ordinary_transfer_state st src dst amount)"
 using WF AD ordinary_transfer_expands_account_support ordinary_transfer_preserves_structure
 unfolding state_wf_def by blast

theorem failure_preserves_state_wf_and_outcome:
 "state_wf A C (fst (abstract_failure_transition st outcome)) = state_wf A C st \<and>
  snd (abstract_failure_transition st outcome) = outcome"
 by (simp add: abstract_failure_transition_def)

lemma restrict_preserves_accounting_state_wf:
 assumes WF: "state_wf A C st" and SH: "forward_shape_wf st cmd" and FR: "forward_fresh st cmd"
   and KIND: "forward_action cmd = Legal_Restrict"
 shows "accounting_state_wf (A \<union> {forward_subject cmd}) (insert (forward_case cmd) C) (forward_success_state st cmd w)"
proof -
 let ?A = "A \<union> {forward_subject cmd}"
 let ?C = "insert (forward_case cmd) C"
 let ?post = "forward_success_state st cmd w"
 have AC: "accounting_state_wf A C st" and REG: "regulatory_structure_wf st"
   using WF unfolding state_wf_def by blast+
 have FIN: "finite A \<and> finite C" using AC
   by (simp add: accounting_state_wf_def balance_wf_def case_scope_def)
 have EXP: "accounting_state_wf ?A ?C st"
   by (rule accounting_state_wf_expands_support[OF AC]) (use FIN in auto)
 have BAL: "balance_wf ?A ?post" using EXP KIND
   by (simp add: accounting_state_wf_def balance_wf_def forward_success_state_def base_forward_success_def Let_def)
 have SCOPE: "case_scope ?C ?post" using EXP KIND
   by (auto simp: accounting_state_wf_def case_scope_def forward_success_state_def base_forward_success_def Let_def)
 have CU_FRAME: "custody_consistent ?C ?post = custody_consistent ?C st" using KIND
   by (simp add: custody_consistent_def active_custody_sum_def forward_success_state_def base_forward_success_def Let_def)
 have CU: "custody_consistent ?C ?post" using EXP CU_FRAME unfolding accounting_state_wf_def by blast
 have REF: "custody_case_wf ?post" by (rule restrict_preserves_custody_case[OF REG SH FR KIND])
 show ?thesis using BAL SCOPE CU REF unfolding accounting_state_wf_def by blast
qed

theorem restrict_preserves_state_wf:
 assumes WF: "state_wf A C st" and AD: "forward_admitted st sender time cmd w"
   and KIND: "forward_action cmd = Legal_Restrict"
 shows "state_wf (A \<union> {forward_subject cmd}) (insert (forward_case cmd) C) (forward_success_state st cmd w)"
proof -
 have SH: "forward_shape_wf st cmd" and FR: "forward_fresh st cmd" using AD unfolding forward_admitted_def by blast+
 have REG: "regulatory_structure_wf st" using WF by (simp add: state_wf_def)
 show ?thesis using restrict_preserves_accounting_state_wf[OF WF SH FR KIND]
   restrict_preserves_regulatory_structure[OF REG SH FR KIND] unfolding state_wf_def by blast
qed


lemma forward_case_lookup_away:
 assumes "c \<noteq> forward_case cmd"
 shows "case_records (forward_success_state st cmd w) c = case_records st c"
 using assms by (cases "forward_action cmd")
   (simp_all add: forward_success_state_def base_forward_success_def Let_def)

lemma nonoverlay_forward_case_shape:
 assumes WF: "regulatory_structure_wf st" and SH: "forward_shape_wf st cmd"
   and KIND: "forward_action cmd \<notin> {Legal_Freeze,Legal_Restrict}"
 shows "case_records st (forward_case cmd) = empty_case \<or>
   (open_case st (forward_case cmd) \<and> case_family (case_records st (forward_case cmd)) = Family_Custody)"
proof -
 have C: "case_structure_wf st" using WF unfolding regulatory_structure_wf_def by blast
 note CC = C[unfolded case_structure_wf_def, rule_format, of "forward_case cmd"]
 have NT: "\<not> terminal_case st (forward_case cmd)" using SH unfolding forward_shape_wf_def by blast
 have OP: "open_case st (forward_case cmd) \<Longrightarrow> case_family (case_records st (forward_case cmd)) = Family_Custody"
   using SH KIND by (cases "forward_action cmd") (auto simp: forward_shape_wf_def disposition_wf_def)
 show ?thesis using CC NT OP by (cases "case_phase (case_records st (forward_case cmd))")
   (auto simp: terminal_case_def open_case_def)
qed

lemma nonoverlay_avoids_overlay_cases:
 assumes WF: "regulatory_structure_wf st" and SH: "forward_shape_wf st cmd"
   and KIND: "forward_action cmd \<notin> {Legal_Freeze,Legal_Restrict}"
   and REC: "action_records st i \<noteq> None"
   and OVERLAY: "abstract_action (record_at st i) \<in> {Legal_Freeze,Legal_Restrict}"
 shows "abstract_case (record_at st i) \<noteq> forward_case cmd"
proof -
 have AI: "action_identity_wf st" using WF unfolding regulatory_structure_wf_def by blast
 obtain r where R: "action_records st i = Some r" using REC by (cases "action_records st i") auto
 note AT = AI[unfolded action_identity_wf_def, rule_format, OF R]
 have CASES: "case_records st (forward_case cmd) = empty_case \<or>
   (open_case st (forward_case cmd) \<and> case_family (case_records st (forward_case cmd)) = Family_Custody)"
   by (rule nonoverlay_forward_case_shape[OF WF SH KIND])
 show ?thesis using AT CASES OVERLAY R
   by (auto simp: record_at_def empty_case_def open_case_def split: legal_action_kind.splits)
qed

lemma nonoverlay_preserves_case_structure:
 assumes C: "case_structure_wf st" and FR: "forward_fresh st cmd"
   and KIND: "forward_action cmd \<notin> {Legal_Freeze,Legal_Restrict}"
 shows "case_structure_wf (forward_success_state st cmd w)"
proof -
 let ?post = "forward_success_state st cmd w"
 have FRESH: "action_records st (forward_action_id cmd) = None" using FR by (simp add: forward_fresh_def)
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
     using CC FRESH KIND by (cases "forward_action cmd";
       auto simp: forward_success_state_def base_forward_success_def forward_action_record_def
        opened_custody_def disposed_case_def record_at_def Let_def
        cong: option.case_cong trust_case_phase.case_cong trust_case_family.case_cong
        split: option.splits trust_case_phase.splits trust_case_family.splits if_splits)
 qed
qed

lemma nonoverlay_preserves_freeze_structure:
 assumes WF: "regulatory_structure_wf st" and SH: "forward_shape_wf st cmd"
   and FR: "forward_fresh st cmd" and KIND: "forward_action cmd \<notin> {Legal_Freeze,Legal_Restrict}"
 shows "freeze_structure_wf (forward_success_state st cmd w)"
proof -
 let ?post = "forward_success_state st cmd w"
 have F: "freeze_structure_wf st" and AI: "action_identity_wf st"
   using WF unfolding regulatory_structure_wf_def by blast+
 have FRESH: "action_records st (forward_action_id cmd) = None" using FR by (simp add: forward_fresh_def)
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
     then show ?thesis using FA KIND by (cases "forward_action cmd"; simp add: forward_success_state_def base_forward_success_def Let_def)
   next
     case (Some i)
     obtain xs where DIST: "distinct (i # xs)" and CH: "live_freeze_chain st a (abstract_case (record_at st i)) (i # xs)"
       using FA Some by auto
     have REC: "action_records st i \<noteq> None" using CH by simp
     have NE: "i \<noteq> forward_action_id cmd" using REC FRESH by auto
     have OLDCASE: "abstract_case (record_at st i) \<noteq> forward_case cmd"
       using nonoverlay_avoids_overlay_cases[OF WF SH KIND REC] CH by auto
     have NEWCH: "live_freeze_chain ?post a (abstract_case (record_at st i)) (i # xs)"
       by (rule forward_preserves_existing_freeze_chain[OF CH FR])
     show ?thesis using Some FA DIST NEWCH NE OLDCASE KIND
       by (cases "forward_action cmd"; auto simp: forward_success_state_def base_forward_success_def forward_action_record_def
         opened_overlay_def record_at_def link_at_def open_case_def Let_def
         cong: option.case_cong intro!: exI[where x=xs])
   qed
 qed
qed


lemma nonoverlay_preserves_restriction_structure:
 assumes WF: "regulatory_structure_wf st" and SH: "forward_shape_wf st cmd"
   and FR: "forward_fresh st cmd" and KIND: "forward_action cmd \<notin> {Legal_Freeze,Legal_Restrict}"
 shows "restriction_structure_wf (forward_success_state st cmd w)"
proof -
 let ?post = "forward_success_state st cmd w"
 have R: "restriction_structure_wf st" and AI: "action_identity_wf st"
   using WF unfolding regulatory_structure_wf_def by blast+
 have OLDCASE: "\<And>i. action_records st i \<noteq> None \<Longrightarrow>
   abstract_action (record_at st i) = Legal_Restrict \<Longrightarrow> abstract_case (record_at st i) \<noteq> forward_case cmd"
   using nonoverlay_avoids_overlay_cases[OF WF SH KIND] by auto
 have FRESH: "action_records st (forward_action_id cmd) = None" using FR by (simp add: forward_fresh_def)
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
     using RA FRESH OLDCASE KIND
     by (cases "forward_action cmd"; auto simp: forward_success_state_def base_forward_success_def forward_action_record_def
       pushed_head_def pushed_link_def opened_overlay_def record_at_def link_at_def open_case_def empty_case_def Let_def
       cong: option.case_cong split: option.splits if_splits)
 qed
qed



lemma seize_preserves_custody_case:
 assumes WF: "regulatory_structure_wf st" and SH: "forward_shape_wf st cmd"
   and FR: "forward_fresh st cmd" and KIND: "forward_action cmd = Legal_Seize"
 shows "custody_case_wf (forward_success_state st cmd w)"
proof -
 let ?post = "forward_success_state st cmd w"
 have CU: "custody_case_wf st" using WF unfolding regulatory_structure_wf_def by blast
 have SHAPE: "forward_subject cmd \<noteq> 0 \<and> forward_source cmd = forward_subject cmd \<and>
   forward_destination cmd = forward_custodian cmd \<and> forward_custodian cmd \<noteq> 0 \<and>
   forward_source cmd \<noteq> forward_destination cmd \<and> forward_amount cmd > 0"
   using SH KIND by (auto simp: forward_shape_wf_def transfer_shape_def)
 have CASE_FRAME: "\<And>c. c \<noteq> forward_case cmd \<Longrightarrow> case_records ?post c = case_records st c"
   by (rule forward_case_lookup_away)
 have CUSTODY_FRAME: "\<And>c. c \<noteq> forward_case cmd \<Longrightarrow> custody_records ?post c = custody_records st c"
   using KIND by (simp add: forward_success_state_def base_forward_success_def Let_def)
 have RECORD_FRAME: "\<And>i r. action_records st i = Some r \<Longrightarrow> action_records ?post i = Some r"
   by (rule forward_record_fresh_preserves_old[OF FR])
 have OLD_EQ: "\<forall>c. (open_case st c \<and> case_family (case_records st c) = Family_Custody) =
   (\<exists>cu. custody_records st c = Some cu \<and> custody_active cu)"
   using CU unfolding custody_case_wf_def by blast
 have EQUIV: "\<forall>c. (open_case ?post c \<and> case_family (case_records ?post c) = Family_Custody) =
   (\<exists>cu. custody_records ?post c = Some cu \<and> custody_active cu)"
   using OLD_EQ by (auto simp: KIND forward_success_state_def base_forward_success_def opened_custody_def open_case_def Let_def split: if_splits)
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
   let ?link = "\<lambda>s. \<exists>i r. custody_action cu = Some i \<and> case_head (case_records s c) = Some i \<and>
       action_records s i = Some r \<and> abstract_lifecycle r = Record_Applied \<and> abstract_action r = Legal_Seize \<and>
       abstract_case r = c \<and> abstract_source r = custody_prior_holder cu \<and> abstract_subject r = custody_prior_holder cu \<and>
       abstract_destination r = custody_custodian cu \<and> abstract_custodian r = custody_custodian cu \<and>
       abstract_amount r = custody_amount cu \<and> custody_amount cu > 0 \<and> custody_prior_holder cu \<noteq> 0 \<and>
       custody_custodian cu \<noteq> 0 \<and> custody_prior_holder cu \<noteq> custody_custodian cu"
   show "if custody_active cu then ?link ?post else custody_amount cu = 0"
   proof (cases "c = forward_case cmd")
     case True
     show ?thesis using POST True SHAPE
       by (auto simp: KIND forward_success_state_def base_forward_success_def forward_action_record_def
         opened_custody_def Let_def)
   next
     case False
     have OLD: "custody_records st c = Some cu" using POST CUSTODY_FRAME[OF False] by simp
     have CS: "case_records ?post c = case_records st c" by (rule CASE_FRAME[OF False])
     have BEFORE: "if custody_active cu then ?link st else custody_amount cu = 0"
       using CU OLD unfolding custody_case_wf_def by blast
     show ?thesis
     proof (cases "custody_active cu")
       case False
       then show ?thesis using BEFORE by simp
     next
       case True
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
 qed
 show ?thesis using EQUIV LINKS unfolding custody_case_wf_def by blast
qed

theorem seize_preserves_regulatory_structure:
 assumes WF: "regulatory_structure_wf st" and SH: "forward_shape_wf st cmd"
   and FR: "forward_fresh st cmd" and KIND: "forward_action cmd = Legal_Seize"
 shows "regulatory_structure_wf (forward_success_state st cmd w)"
proof -
 have NON: "forward_action cmd \<notin> {Legal_Freeze,Legal_Restrict}" using KIND by simp
 have H: "effect_history_wf st" and C: "case_structure_wf st" using WF unfolding regulatory_structure_wf_def by blast+
 show ?thesis using seize_preserves_action_identity[OF WF SH FR KIND]
   nonoverlay_preserves_effect_history[OF H FR NON] nonoverlay_preserves_case_structure[OF C FR NON]
   nonoverlay_preserves_freeze_structure[OF WF SH FR NON] nonoverlay_preserves_restriction_structure[OF WF SH FR NON]
   seize_preserves_custody_case[OF WF SH FR KIND] unfolding regulatory_structure_wf_def by blast
qed


lemma seize_preserves_accounting_state_wf:
 assumes WF: "state_wf A C st" and SH: "forward_shape_wf st cmd" and FR: "forward_fresh st cmd"
   and KIND: "forward_action cmd = Legal_Seize"
 shows "accounting_state_wf (A \<union> {forward_source cmd,forward_custodian cmd,forward_destination cmd})
   (insert (forward_case cmd) C) (forward_success_state st cmd w)"
proof -
 let ?src = "forward_source cmd"
 let ?cust = "forward_custodian cmd"
 let ?dst = "forward_destination cmd"
 let ?amount = "forward_amount cmd"
 let ?c = "forward_case cmd"
 let ?A = "A \<union> {?src,?cust,?dst}"
 let ?C = "insert ?c C"
 let ?post = "forward_success_state st cmd w"
 let ?cu = "\<lparr>custody_custodian = ?cust, custody_prior_holder = forward_subject cmd,
   custody_amount = ?amount, custody_action = Some (forward_action_id cmd), custody_active = True\<rparr>"
 have AC: "accounting_state_wf A C st" and REG: "regulatory_structure_wf st"
   using WF unfolding state_wf_def by blast+
 have BAL0: "balance_wf A st" and SCOPE0: "case_scope C st" and CU0: "custody_consistent C st"
   and REF0: "custody_case_wf st" using AC unfolding accounting_state_wf_def by blast+
 have FIN: "finite C" using SCOPE0 by (simp add: case_scope_def)
 have BOUND0: "\<forall>a. custody_backing st a \<le> physical_balances st a"
   using CU0 unfolding custody_consistent_def by blast
 have EQ0: "\<And>a. custody_backing st a = active_custody_sum C st a"
   using CU0 unfolding custody_consistent_def by blast
 have DEST: "?dst = ?cust" and DISTINCT: "?src \<noteq> ?cust" and AVAIL: "unbacked_available st ?src ?amount"
   using SH KIND by (auto simp: forward_shape_wf_def transfer_shape_def)
 have PAY: "?amount \<le> physical_balances st ?src" using AVAIL unfolding unbacked_available_def by arith
 have EMPTY: "case_records st ?c = empty_case" by (rule seize_starts_empty_case[OF REG SH KIND])
 have NO_ACTIVE: "\<not> (\<exists>old. custody_records st ?c = Some old \<and> custody_active old)"
   by (rule custody_case_none_is_inactive[OF REF0 EMPTY])
 have SUM: "\<And>a. active_custody_sum ?C ?post a = active_custody_sum C st a + (if ?cust = a then ?amount else 0)"
 proof -
   fix a
   have INS: "active_custody_sum ?C (st\<lparr>custody_records := (custody_records st)(?c := Some ?cu)\<rparr>) a =
     active_custody_sum C st a + (if ?cust = a then ?amount else 0)"
     using seize_custody_sum_insert[OF FIN NO_ACTIVE, of ?cu a] by simp
   show "active_custody_sum ?C ?post a = active_custody_sum C st a + (if ?cust = a then ?amount else 0)"
     using INS by (simp add: KIND active_custody_sum_def forward_success_state_def base_forward_success_def Let_def)
 qed
 have BB: "\<forall>a. custody_backing ?post a \<le> physical_balances ?post a"
   using seize_preserves_backing_bound[OF BOUND0 DISTINCT AVAIL]
   by (simp add: KIND forward_success_state_def base_forward_success_def Let_def)
 have CU: "custody_consistent ?C ?post"
   using FIN SUM EQ0 BB by (auto simp: custody_consistent_def KIND forward_success_state_def base_forward_success_def Let_def)
 have MOVED: "balance_wf ?A (st\<lparr>physical_balances := move_balance (physical_balances st) ?src ?dst ?amount\<rparr>)"
   by (rule move_balance_expanded_support[OF BAL0 PAY])
 have BAL: "balance_wf ?A ?post" using MOVED DEST
   by (simp add: balance_wf_def KIND forward_success_state_def base_forward_success_def Let_def)
 have SCOPE: "case_scope ?C ?post" using SCOPE0
   by (auto simp: case_scope_def KIND forward_success_state_def base_forward_success_def Let_def)
 have REF: "custody_case_wf ?post" by (rule seize_preserves_custody_case[OF REG SH FR KIND])
 show ?thesis using BAL SCOPE CU REF unfolding accounting_state_wf_def by blast
qed

theorem seize_preserves_state_wf:
 assumes WF: "state_wf A C st" and AD: "forward_admitted st sender time cmd w" and KIND: "forward_action cmd = Legal_Seize"
 shows "state_wf (A \<union> {forward_source cmd,forward_custodian cmd,forward_destination cmd})
   (insert (forward_case cmd) C) (forward_success_state st cmd w)"
proof -
 have SH: "forward_shape_wf st cmd" and FR: "forward_fresh st cmd" using AD unfolding forward_admitted_def by blast+
 have REG: "regulatory_structure_wf st" using WF by (simp add: state_wf_def)
 show ?thesis using seize_preserves_accounting_state_wf[OF WF SH FR KIND]
   seize_preserves_regulatory_structure[OF REG SH FR KIND] unfolding state_wf_def by blast
qed

lemma freeze_push_context:
 assumes WF: "regulatory_structure_wf st" and SH: "forward_shape_wf st cmd" and KIND: "forward_action cmd = Legal_Freeze"
 shows "(case head_action (freeze_heads st (forward_subject cmd)) of
   None \<Rightarrow> case_records st (forward_case cmd) = empty_case \<and> frozen_targets st (forward_subject cmd) = 0
 | Some p \<Rightarrow> action_records st p \<noteq> None \<and> effect_links st p \<noteq> None \<and>
   abstract_action (record_at st p) = Legal_Freeze \<and> abstract_subject (record_at st p) = forward_subject cmd \<and>
   abstract_case (record_at st p) = forward_case cmd \<and> frozen_targets st (forward_subject cmd) = abstract_amount (record_at st p) \<and>
   effect_generation (link_at st p) \<le> head_generation (freeze_heads st (forward_subject cmd)) \<and>
   open_case st (forward_case cmd) \<and> case_family (case_records st (forward_case cmd)) = Family_Freeze \<and>
   case_head (case_records st (forward_case cmd)) = Some p)"
proof -
 have F: "freeze_structure_wf st" and H: "effect_history_wf st" using WF unfolding regulatory_structure_wf_def by blast+
 note FA = F[unfolded freeze_structure_wf_def, rule_format, of "forward_subject cmd"]
 note COMPAT = freeze_forward_case_split(1)[OF WF SH KIND]
 show ?thesis
 proof (cases "head_action (freeze_heads st (forward_subject cmd))")
   case None
   show ?thesis using COMPAT None by simp
 next
   case (Some p)
   obtain xs where CH: "live_freeze_chain st (forward_subject cmd) (abstract_case (record_at st p)) (p # xs)" using FA Some by auto
   obtain e where EP: "effect_links st p = Some e" using CH by (cases "effect_links st p") auto
   note HP = H[unfolded effect_history_wf_def, rule_format, of p e]
   have BOUND: "effect_generation (link_at st p) \<le> head_generation (freeze_heads st (forward_subject cmd))"
     using HP EP CH by (auto simp: Let_def link_at_def)
   show ?thesis using Some COMPAT FA CH EP BOUND by auto
 qed
qed

lemma freeze_preserves_effect_history:
 assumes WF: "regulatory_structure_wf st" and SH: "forward_shape_wf st cmd" and FR: "forward_fresh st cmd"
   and KIND: "forward_action cmd = Legal_Freeze"
 shows "effect_history_wf (forward_success_state st cmd w)"
proof -
 let ?post = "forward_success_state st cmd w"
 have H: "effect_history_wf st" using WF unfolding regulatory_structure_wf_def by blast
 have FRESH: "action_records st (forward_action_id cmd) = None" using FR by (simp add: forward_fresh_def)
 have SHAPE: "forward_action_id cmd \<noteq> 0 \<and> forward_subject cmd \<noteq> 0 \<and> forward_case cmd \<noteq> 0"
   using SH unfolding forward_shape_wf_def by blast
 note CTX = freeze_push_context[OF WF SH KIND]
 show ?thesis unfolding effect_history_wf_def
 proof (intro allI impI)
   fix i :: trust_action_id and e :: compositional_effect_link
   assume E: "effect_links ?post i = Some e"
   show "action_records ?post i \<noteq> None \<and> i \<noteq> 0 \<and>
     (let r = record_at ?post i in abstract_subject r \<noteq> 0 \<and> abstract_case r \<noteq> 0 \<and>
      abstract_action r \<in> {Legal_Freeze,Legal_Restrict} \<and> effect_generation e > 0 \<and>
      effect_generation e \<le> head_generation (if abstract_action r = Legal_Freeze then freeze_heads ?post (abstract_subject r)
        else restriction_heads ?post (abstract_subject r)) \<and>
      (case effect_parent e of None \<Rightarrow> abstract_prior_amount r = 0 \<and> \<not> abstract_prior_flag r
       | Some j \<Rightarrow> abstract_action r = Legal_Freeze \<and> action_records ?post j \<noteq> None \<and> effect_links ?post j \<noteq> None \<and>
         abstract_action (record_at ?post j) = Legal_Freeze \<and> abstract_subject (record_at ?post j) = abstract_subject r \<and>
         abstract_case (record_at ?post j) = abstract_case r \<and> effect_generation (link_at ?post j) < effect_generation e \<and>
         abstract_prior_amount r = abstract_amount (record_at ?post j)))"
   proof (cases "i = forward_action_id cmd")
     case True
     show ?thesis using E True CTX SHAPE FRESH
       by (cases "head_action (freeze_heads st (forward_subject cmd))";
         auto simp: KIND forward_success_state_def base_forward_success_def forward_action_record_def pushed_head_def
           pushed_link_def record_at_def link_at_def Let_def cong: option.case_cong split: option.splits if_splits; presburger)
   next
     case False
     have SAME: "effect_links ?post i = effect_links st i" by (rule forward_effect_lookup_away[OF False])
     have E0: "effect_links st i = Some e" using E SAME by simp
     note HI = H[unfolded effect_history_wf_def, rule_format, of i e]
     show ?thesis using HI E0 False FRESH
       by (auto simp: KIND forward_success_state_def base_forward_success_def forward_action_record_def pushed_head_def
         pushed_link_def record_at_def link_at_def Let_def cong: option.case_cong split: option.splits if_splits; presburger)
   qed
 qed
qed

lemma freeze_preserves_freeze_structure:
 assumes WF: "regulatory_structure_wf st" and SH: "forward_shape_wf st cmd" and FR: "forward_fresh st cmd"
   and KIND: "forward_action cmd = Legal_Freeze"
 shows "freeze_structure_wf (forward_success_state st cmd w)"
proof -
 let ?post = "forward_success_state st cmd w"
 let ?subject = "forward_subject cmd"
 let ?cid = "forward_case cmd"
 let ?id = "forward_action_id cmd"
 let ?head = "freeze_heads st ?subject"
 have F: "freeze_structure_wf st" and AI: "action_identity_wf st" using WF unfolding regulatory_structure_wf_def by blast+
 have FRESH: "action_records st ?id = None" using FR by (simp add: forward_fresh_def)
 have INC: "frozen_targets st ?subject < forward_amount cmd" by (rule freeze_forward_case_split(2)[OF WF SH KIND])
 note CTX = freeze_push_context[OF WF SH KIND]
 note FS = F[unfolded freeze_structure_wf_def, rule_format, of ?subject]
 have NR: "action_records ?post ?id = Some (forward_action_record st cmd w)" by (simp add: forward_record_lookup)
 have NL: "effect_links ?post ?id = Some (pushed_link ?head)" by (simp add: KIND forward_success_state_def base_forward_success_def Let_def)
 have RN: "record_at ?post ?id = forward_action_record st cmd w" using NR by (simp add: record_at_def)
 have LN: "link_at ?post ?id = pushed_link ?head" using NL by (simp add: link_at_def)
 have HNEW: "head_action (freeze_heads ?post ?subject) = Some ?id" by (simp add: KIND forward_success_state_def base_forward_success_def pushed_head_def Let_def)
 have TNEW: "frozen_targets ?post ?subject = forward_amount cmd" by (simp add: KIND forward_success_state_def base_forward_success_def Let_def)
 have CNEW: "open_case ?post ?cid \<and> case_family (case_records ?post ?cid) = Family_Freeze \<and> case_head (case_records ?post ?cid) = Some ?id"
   using CTX by (cases "head_action ?head"; auto simp: KIND forward_success_state_def base_forward_success_def opened_overlay_def open_case_def empty_case_def Let_def)
 show ?thesis unfolding freeze_structure_wf_def
 proof (intro allI)
   fix a
   note FA = F[unfolded freeze_structure_wf_def, rule_format, of a]
   show "(case head_action (freeze_heads ?post a) of None \<Rightarrow> frozen_targets ?post a = 0
    | Some i \<Rightarrow> (\<exists>xs. distinct (i # xs) \<and> live_freeze_chain ?post a (abstract_case (record_at ?post i)) (i # xs)) \<and>
      frozen_targets ?post a = abstract_amount (record_at ?post i) \<and> open_case ?post (abstract_case (record_at ?post i)) \<and>
      case_family (case_records ?post (abstract_case (record_at ?post i))) = Family_Freeze \<and>
      case_head (case_records ?post (abstract_case (record_at ?post i))) = Some i)"
   proof (cases "a = ?subject")
     case True
     have W: "\<exists>ys. distinct (?id # ys) \<and> live_freeze_chain ?post ?subject ?cid (?id # ys)"
     proof (cases "head_action ?head")
       case None
       have PUSH: "live_freeze_chain ?post ?subject ?cid [?id]"
         by (simp add: NR NL RN LN KIND forward_action_record_def pushed_link_def None INC)
       show ?thesis using PUSH by (intro exI[where x="[]"]) simp
     next
       case (Some p)
       obtain xs where DIST: "distinct (p # xs)" and CH: "live_freeze_chain st ?subject (abstract_case (record_at st p)) (p # xs)"
         using FS Some by auto
       have CHC: "live_freeze_chain st ?subject ?cid (p # xs)" using CH CTX Some by auto
       have OUT: "?id \<notin> set (p # xs)" by (rule fresh_action_not_in_freeze_chain[OF CHC FRESH])
       have TAIL: "live_freeze_chain ?post ?subject ?cid (p # xs)" by (rule forward_preserves_existing_freeze_chain[OF CHC FR])
       have PUSH: "live_freeze_chain ?post ?subject ?cid (?id # p # xs)"
         using TAIL by (simp add: NR NL RN LN KIND forward_action_record_def pushed_link_def Some INC)
       show ?thesis using DIST OUT PUSH by (intro exI[where x="p # xs"]) auto
     qed
     show ?thesis using True W HNEW TNEW CNEW RN by (simp add: forward_action_record_def)
   next
     case False
     have NE_A: "a \<noteq> ?subject" by (rule False)
     have HA: "head_action (freeze_heads ?post a) = head_action (freeze_heads st a)"
       using NE_A by (simp add: KIND forward_success_state_def base_forward_success_def Let_def)
     have TA: "frozen_targets ?post a = frozen_targets st a"
       using NE_A by (simp add: KIND forward_success_state_def base_forward_success_def Let_def)
     show ?thesis
     proof (cases "head_action (freeze_heads st a)")
       case None
       show ?thesis using FA None HA TA by simp
     next
       case (Some i)
       note HDI = Some
       obtain xs where DIST: "distinct (i # xs)" and CH: "live_freeze_chain st a (abstract_case (record_at st i)) (i # xs)"
         using FA HDI by auto
       have REC: "action_records st i \<noteq> None" using CH by simp
       have NE_I: "i \<noteq> ?id" using REC FRESH by auto
       have OLDCASE: "abstract_case (record_at st i) \<noteq> ?cid"
       proof
         assume SAME_CASE: "abstract_case (record_at st i) = ?cid"
         show False
         proof (cases "head_action ?head")
           case None
           have EMPTY: "case_records st ?cid = empty_case" using CTX None by simp
           have AWAY: "abstract_case (record_at st i) \<noteq> ?cid" by (rule record_at_not_in_empty_case[OF AI EMPTY REC])
           show False using AWAY SAME_CASE by simp
         next
           case (Some p)
           have SAME_ID: "i = p" using FA HDI CTX Some SAME_CASE by auto
           have SUB_I: "abstract_subject (record_at st i) = a" using CH by simp
           have SUB_P: "abstract_subject (record_at st p) = ?subject" using CTX Some by simp
           show False using NE_A SAME_ID SUB_I SUB_P by metis
         qed
       qed
       have NEWCH: "live_freeze_chain ?post a (abstract_case (record_at st i)) (i # xs)" by (rule forward_preserves_existing_freeze_chain[OF CH FR])
       have RID: "record_at ?post i = record_at st i" by (simp add: record_at_def forward_record_lookup NE_I)
       have CS: "case_records ?post (abstract_case (record_at st i)) = case_records st (abstract_case (record_at st i))"
         by (rule forward_case_lookup_away[OF OLDCASE])
       show ?thesis using HA TA HDI FA DIST NEWCH RID CS by (auto simp: open_case_def intro!: exI[where x=xs])
     qed
   qed
 qed
qed


lemma freeze_preserves_old_record_case:
 assumes WF: "regulatory_structure_wf st" and SH: "forward_shape_wf st cmd" and KIND: "forward_action cmd = Legal_Freeze"
   and REC: "action_records st i = Some r"
 shows "case_family (case_records (forward_success_state st cmd w) (abstract_case r)) = case_family (case_records st (abstract_case r))"
   "case_phase (case_records (forward_success_state st cmd w) (abstract_case r)) \<noteq> Case_None"
   "case_phase (case_records st (abstract_case r)) = Case_Terminal \<longrightarrow>
     case_phase (case_records (forward_success_state st cmd w) (abstract_case r)) = Case_Terminal"
proof -
 let ?post = "forward_success_state st cmd w"
 have AI: "action_identity_wf st" using WF unfolding regulatory_structure_wf_def by blast
 note AT = AI[unfolded action_identity_wf_def, rule_format, OF REC]
 note CTX = freeze_push_context[OF WF SH KIND]
 have BEFORE: "case_phase (case_records st (abstract_case r)) \<noteq> Case_None" using AT by blast
 have LOOKUP: "case_records ?post (abstract_case r) = (if abstract_case r = forward_case cmd
   then opened_overlay (case_records st (forward_case cmd)) Family_Freeze (forward_action_id cmd) else case_records st (abstract_case r))"
   by (simp add: KIND forward_success_state_def base_forward_success_def Let_def)
 have NONEMPTY: "abstract_case r = forward_case cmd \<Longrightarrow> open_case st (forward_case cmd)"
   using BEFORE CTX by (cases "head_action (freeze_heads st (forward_subject cmd))") (auto simp: empty_case_def)
 show "case_family (case_records ?post (abstract_case r)) = case_family (case_records st (abstract_case r))"
   using LOOKUP NONEMPTY by (auto simp: opened_overlay_def open_case_def)
 show "case_phase (case_records ?post (abstract_case r)) \<noteq> Case_None"
   using LOOKUP BEFORE by (auto simp: opened_overlay_def)
 show "case_phase (case_records st (abstract_case r)) = Case_Terminal \<longrightarrow>
   case_phase (case_records ?post (abstract_case r)) = Case_Terminal"
   using LOOKUP NONEMPTY by (auto simp: opened_overlay_def open_case_def)
qed

lemma freeze_preserves_action_identity:
 assumes WF: "regulatory_structure_wf st" and SH: "forward_shape_wf st cmd" and FR: "forward_fresh st cmd"
   and KIND: "forward_action cmd = Legal_Freeze"
 shows "action_identity_wf (forward_success_state st cmd w)"
proof -
 let ?post = "forward_success_state st cmd w"
 let ?valid = "\<lambda>s i r. i \<noteq> 0 \<and> abstract_subject r \<noteq> 0 \<and> abstract_case r \<noteq> 0 \<and>
   abstract_lifecycle r \<in> {Record_Applied, Record_Reversed} \<and>
   case_phase (case_records s (abstract_case r)) \<noteq> Case_None \<and>
   \<not> abstract_prior_flag r \<and>
   ((effect_links s i \<noteq> None) = (abstract_action r \<in> {Legal_Freeze, Legal_Restrict})) \<and>
   (case abstract_action r of
     Legal_Freeze \<Rightarrow> abstract_source r = abstract_subject r \<and> abstract_destination r = 0 \<and>
       abstract_custodian r = 0 \<and> abstract_prior_amount r < abstract_amount r \<and>
       case_family (case_records s (abstract_case r)) = Family_Freeze
   | Legal_Restrict \<Rightarrow> abstract_source r = abstract_subject r \<and> abstract_destination r = 0 \<and>
       abstract_custodian r = 0 \<and> abstract_amount r = 0 \<and> abstract_prior_amount r = 0 \<and>
       case_family (case_records s (abstract_case r)) = Family_Restrict
   | Legal_Seize \<Rightarrow> abstract_source r = abstract_subject r \<and> abstract_destination r = abstract_custodian r \<and>
       abstract_custodian r \<noteq> 0 \<and> abstract_subject r \<noteq> abstract_custodian r \<and>
       abstract_amount r > 0 \<and> abstract_prior_amount r = 0 \<and>
       case_family (case_records s (abstract_case r)) = Family_Custody
   | _ \<Rightarrow> abstract_source r \<noteq> 0 \<and> abstract_destination r \<noteq> 0 \<and>
       abstract_source r \<noteq> abstract_destination r \<and> abstract_custodian r = 0 \<and>
       abstract_amount r > 0 \<and> abstract_prior_amount r = 0 \<and> abstract_lifecycle r = Record_Applied \<and>
       case_phase (case_records s (abstract_case r)) = Case_Terminal \<and>
       case_family (case_records s (abstract_case r)) \<in> {Family_Disposition, Family_Custody})"
 have AI: "action_identity_wf st" using WF unfolding regulatory_structure_wf_def by blast
 note CTX = freeze_push_context[OF WF SH KIND]
 have CHECK: "\<And>i r. action_records ?post i = Some r \<Longrightarrow> ?valid ?post i r"
 proof -
   fix i r
   assume POST: "action_records ?post i = Some r"
   show "?valid ?post i r"
   proof (cases "i = forward_action_id cmd")
     case True
     have NEW: "r = forward_action_record st cmd w" using POST True by (simp add: forward_record_lookup)
     show ?thesis using NEW True SH KIND CTX
       by (cases "head_action (freeze_heads st (forward_subject cmd))";
         auto simp: KIND forward_action_record_def forward_shape_wf_def overlay_shape_def
           forward_success_state_def base_forward_success_def opened_overlay_def empty_case_def open_case_def Let_def)
   next
     case False
     have OLD: "action_records st i = Some r" using POST False by (simp add: forward_record_lookup)
     have BEFORE: "?valid st i r" using AI OLD unfolding action_identity_wf_def by blast
     note CASES = freeze_preserves_old_record_case[OF WF SH KIND OLD]
     have EFFECT: "effect_links ?post i = effect_links st i" by (rule forward_effect_lookup_away[OF False])
     show ?thesis using BEFORE CASES EFFECT by (auto split: legal_action_kind.splits)
   qed
 qed
 show ?thesis using CHECK unfolding action_identity_wf_def by blast
qed

lemma freeze_avoids_restriction_case:
 assumes WF: "regulatory_structure_wf st" and SH: "forward_shape_wf st cmd" and KIND: "forward_action cmd = Legal_Freeze"
   and REC: "action_records st i \<noteq> None" and R: "abstract_action (record_at st i) = Legal_Restrict"
 shows "abstract_case (record_at st i) \<noteq> forward_case cmd"
proof -
 have AI: "action_identity_wf st" using WF unfolding regulatory_structure_wf_def by blast
 obtain r where OLD: "action_records st i = Some r" using REC by (cases "action_records st i") auto
 note AT = AI[unfolded action_identity_wf_def, rule_format, OF OLD]
 note CTX = freeze_push_context[OF WF SH KIND]
 show ?thesis using AT CTX OLD R by (cases "head_action (freeze_heads st (forward_subject cmd))")
   (auto simp: record_at_def empty_case_def open_case_def)
qed

lemma freeze_preserves_restriction_structure:
 assumes WF: "regulatory_structure_wf st" and SH: "forward_shape_wf st cmd"
   and FR: "forward_fresh st cmd" and KIND: "forward_action cmd = Legal_Freeze"
 shows "restriction_structure_wf (forward_success_state st cmd w)"
proof -
 let ?post = "forward_success_state st cmd w"
 have R: "restriction_structure_wf st" and AI: "action_identity_wf st"
   using WF unfolding regulatory_structure_wf_def by blast+
 have OLDCASE: "\<And>i. action_records st i \<noteq> None \<Longrightarrow>
   abstract_action (record_at st i) = Legal_Restrict \<Longrightarrow> abstract_case (record_at st i) \<noteq> forward_case cmd"
   by (rule freeze_avoids_restriction_case[OF WF SH KIND])
 have FRESH: "action_records st (forward_action_id cmd) = None" using FR by (simp add: forward_fresh_def)
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
     using RA FRESH OLDCASE
     by (auto simp: KIND forward_success_state_def base_forward_success_def forward_action_record_def
       pushed_head_def pushed_link_def opened_overlay_def record_at_def link_at_def open_case_def empty_case_def Let_def
       cong: option.case_cong split: option.splits if_splits)
 qed
qed

lemma freeze_preserves_case_structure:
 assumes WF: "regulatory_structure_wf st" and SH: "forward_shape_wf st cmd"
   and FR: "forward_fresh st cmd" and KIND: "forward_action cmd = Legal_Freeze"
 shows "case_structure_wf (forward_success_state st cmd w)"
proof -
 let ?post = "forward_success_state st cmd w"
 have C: "case_structure_wf st" using WF unfolding regulatory_structure_wf_def by blast
 note CTX = freeze_push_context[OF WF SH KIND]
 have FRESH: "action_records st (forward_action_id cmd) = None" using FR by (simp add: forward_fresh_def)
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
     using CC CTX FRESH
     by (cases "head_action (freeze_heads st (forward_subject cmd))"; auto simp: KIND forward_success_state_def base_forward_success_def forward_action_record_def
       pushed_head_def pushed_link_def opened_overlay_def record_at_def link_at_def open_case_def empty_case_def Let_def
       cong: option.case_cong trust_case_phase.case_cong trust_case_family.case_cong
       split: option.splits trust_case_phase.splits trust_case_family.splits if_splits)
 qed
qed



lemma freeze_preserves_custody_case:
 assumes WF: "regulatory_structure_wf st" and SH: "forward_shape_wf st cmd"
   and FR: "forward_fresh st cmd" and KIND: "forward_action cmd = Legal_Freeze"
 shows "custody_case_wf (forward_success_state st cmd w)"
proof -
 let ?post = "forward_success_state st cmd w"
 have CU: "custody_case_wf st" using WF unfolding regulatory_structure_wf_def by blast
 note CTX = freeze_push_context[OF WF SH KIND]
 have CUSTODY_FRAME: "custody_records ?post = custody_records st"
   using KIND by (simp add: forward_success_state_def base_forward_success_def Let_def)
 have CASE_FRAME: "\<And>c. c \<noteq> forward_case cmd \<Longrightarrow> case_records ?post c = case_records st c"
   using KIND by (simp add: forward_success_state_def base_forward_success_def Let_def)
 have NO_NEW_ACTIVE: "\<not> (\<exists>cu. custody_records st (forward_case cmd) = Some cu \<and> custody_active cu)"
 proof -
   have EQ: "(open_case st (forward_case cmd) \<and> case_family (case_records st (forward_case cmd)) = Family_Custody) =
     (\<exists>cu. custody_records st (forward_case cmd) = Some cu \<and> custody_active cu)"
     using CU unfolding custody_case_wf_def by blast
   show ?thesis using EQ CTX by (cases "head_action (freeze_heads st (forward_subject cmd))")
     (auto simp: empty_case_def open_case_def)
 qed
 have ACTIVE_AWAY: "\<And>c cu. custody_records st c = Some cu \<Longrightarrow> custody_active cu \<Longrightarrow> c \<noteq> forward_case cmd"
   using NO_NEW_ACTIVE by blast
 have RECORD_FRAME: "\<And>i r. action_records st i = Some r \<Longrightarrow> action_records ?post i = Some r"
   by (rule forward_record_fresh_preserves_old[OF FR])
 have CASE_CUSTODY: "\<And>c. (open_case ?post c \<and> case_family (case_records ?post c) = Family_Custody) =
   (open_case st c \<and> case_family (case_records st c) = Family_Custody)"
   using CTX KIND by (cases "head_action (freeze_heads st (forward_subject cmd))"; auto simp: forward_success_state_def base_forward_success_def opened_overlay_def
     empty_case_def open_case_def Let_def split: if_splits)
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
     have AWAY: "c \<noteq> forward_case cmd" by (rule ACTIVE_AWAY[OF OLD True])
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


theorem freeze_preserves_regulatory_structure:
 assumes WF: "regulatory_structure_wf st" and SH: "forward_shape_wf st cmd" and FR: "forward_fresh st cmd"
   and KIND: "forward_action cmd = Legal_Freeze"
 shows "regulatory_structure_wf (forward_success_state st cmd w)"
 using freeze_preserves_action_identity[OF WF SH FR KIND] freeze_preserves_effect_history[OF WF SH FR KIND]
   freeze_preserves_freeze_structure[OF WF SH FR KIND] freeze_preserves_restriction_structure[OF WF SH FR KIND]
   freeze_preserves_case_structure[OF WF SH FR KIND] freeze_preserves_custody_case[OF WF SH FR KIND]
 unfolding regulatory_structure_wf_def by blast

lemma freeze_preserves_accounting_state_wf:
 assumes WF: "state_wf A C st" and SH: "forward_shape_wf st cmd" and FR: "forward_fresh st cmd"
   and KIND: "forward_action cmd = Legal_Freeze"
 shows "accounting_state_wf (A \<union> {forward_subject cmd}) (insert (forward_case cmd) C) (forward_success_state st cmd w)"
proof -
 let ?A = "A \<union> {forward_subject cmd}"
 let ?C = "insert (forward_case cmd) C"
 let ?post = "forward_success_state st cmd w"
 have AC: "accounting_state_wf A C st" and REG: "regulatory_structure_wf st"
   using WF unfolding state_wf_def by blast+
 have FIN: "finite A \<and> finite C" using AC
   by (simp add: accounting_state_wf_def balance_wf_def case_scope_def)
 have EXP: "accounting_state_wf ?A ?C st"
   by (rule accounting_state_wf_expands_support[OF AC]) (use FIN in auto)
 have BAL: "balance_wf ?A ?post" using EXP KIND
   by (simp add: accounting_state_wf_def balance_wf_def forward_success_state_def base_forward_success_def Let_def)
 have SCOPE: "case_scope ?C ?post" using EXP KIND
   by (auto simp: accounting_state_wf_def case_scope_def forward_success_state_def base_forward_success_def Let_def)
 have CU_FRAME: "custody_consistent ?C ?post = custody_consistent ?C st" using KIND
   by (simp add: custody_consistent_def active_custody_sum_def forward_success_state_def base_forward_success_def Let_def)
 have CU: "custody_consistent ?C ?post" using EXP CU_FRAME unfolding accounting_state_wf_def by blast
 have REF: "custody_case_wf ?post" by (rule freeze_preserves_custody_case[OF REG SH FR KIND])
 show ?thesis using BAL SCOPE CU REF unfolding accounting_state_wf_def by blast
qed

theorem freeze_preserves_state_wf:
 assumes WF: "state_wf A C st" and AD: "forward_admitted st sender time cmd w"
   and KIND: "forward_action cmd = Legal_Freeze"
 shows "state_wf (A \<union> {forward_subject cmd}) (insert (forward_case cmd) C) (forward_success_state st cmd w)"
proof -
 have SH: "forward_shape_wf st cmd" and FR: "forward_fresh st cmd" using AD unfolding forward_admitted_def by blast+
 have REG: "regulatory_structure_wf st" using WF by (simp add: state_wf_def)
 show ?thesis using freeze_preserves_accounting_state_wf[OF WF SH FR KIND]
   freeze_preserves_regulatory_structure[OF REG SH FR KIND] unfolding state_wf_def by blast
qed




lemma disposition_forward_context:
 assumes WF: "regulatory_structure_wf st" and SH: "forward_shape_wf st cmd"
   and KIND: "forward_action cmd \<in> {Legal_Confiscate,Legal_Liquidate,Legal_Recover}"
 shows "transfer_shape cmd \<and> forward_custodian cmd = 0"
   "(if uses_active_custody st cmd then open_case st (forward_case cmd) \<and>
     case_family (case_records st (forward_case cmd)) = Family_Custody \<and> custody_matches st cmd
    else case_records st (forward_case cmd) = empty_case \<and> forward_source cmd = forward_subject cmd \<and>
      unbacked_available st (forward_source cmd) (forward_amount cmd) \<and>
      \<not> (\<exists>cu. custody_records st (forward_case cmd) = Some cu \<and> custody_active cu))"
proof -
 have NON: "forward_action cmd \<notin> {Legal_Freeze,Legal_Restrict}" using KIND by auto
 have DW: "disposition_wf st cmd" using SH KIND by (cases "forward_action cmd") (auto simp: forward_shape_wf_def)
 have CU: "custody_case_wf st" using WF unfolding regulatory_structure_wf_def by blast
 have CASES: "case_records st (forward_case cmd) = empty_case \<or>
   (open_case st (forward_case cmd) \<and> case_family (case_records st (forward_case cmd)) = Family_Custody)"
   by (rule nonoverlay_forward_case_shape[OF WF SH NON])
 have LINK: "(open_case st (forward_case cmd) \<and> case_family (case_records st (forward_case cmd)) = Family_Custody) =
   (\<exists>cu. custody_records st (forward_case cmd) = Some cu \<and> custody_active cu)"
   using CU unfolding custody_case_wf_def by blast
 have USE: "uses_active_custody st cmd = (\<exists>cu. custody_records st (forward_case cmd) = Some cu \<and> custody_active cu)"
   by (cases "custody_records st (forward_case cmd)") (auto simp: uses_active_custody_def)
 show "transfer_shape cmd \<and> forward_custodian cmd = 0" using DW by (simp add: disposition_wf_def)
 show "(if uses_active_custody st cmd then open_case st (forward_case cmd) \<and>
     case_family (case_records st (forward_case cmd)) = Family_Custody \<and> custody_matches st cmd
    else case_records st (forward_case cmd) = empty_case \<and> forward_source cmd = forward_subject cmd \<and>
      unbacked_available st (forward_source cmd) (forward_amount cmd) \<and>
      \<not> (\<exists>cu. custody_records st (forward_case cmd) = Some cu \<and> custody_active cu))"
   using CASES LINK USE DW by (cases "uses_active_custody st cmd") (auto simp: disposition_wf_def open_case_def empty_case_def)
qed

lemma disposition_preserves_old_record_case:
 assumes WF: "regulatory_structure_wf st" and SH: "forward_shape_wf st cmd"
   and KIND: "forward_action cmd \<in> {Legal_Confiscate,Legal_Liquidate,Legal_Recover}" and REC: "action_records st i = Some r"
 shows "case_family (case_records (forward_success_state st cmd w) (abstract_case r)) = case_family (case_records st (abstract_case r))"
   "case_phase (case_records (forward_success_state st cmd w) (abstract_case r)) \<noteq> Case_None"
   "case_phase (case_records st (abstract_case r)) = Case_Terminal \<longrightarrow>
     case_phase (case_records (forward_success_state st cmd w) (abstract_case r)) = Case_Terminal"
proof -
 let ?post = "forward_success_state st cmd w"
 have AI: "action_identity_wf st" using WF unfolding regulatory_structure_wf_def by blast
 note AT = AI[unfolded action_identity_wf_def, rule_format, OF REC]
 note CTX = disposition_forward_context(2)[OF WF SH KIND]
 have BEFORE: "case_phase (case_records st (abstract_case r)) \<noteq> Case_None" using AT by blast
 have LOOKUP: "case_records ?post (abstract_case r) = (if abstract_case r = forward_case cmd
   then disposed_case (case_records st (forward_case cmd)) (uses_active_custody st cmd) else case_records st (abstract_case r))"
   using KIND by (cases "forward_action cmd") (auto simp: forward_success_state_def base_forward_success_def Let_def)
 show "case_family (case_records ?post (abstract_case r)) = case_family (case_records st (abstract_case r))"
 proof (cases "uses_active_custody st cmd")
   case True
   show ?thesis using LOOKUP True by (simp add: disposed_case_def)
 next
   case False
   have EMPTY: "case_records st (forward_case cmd) = empty_case" using CTX False by simp
   have AWAY: "abstract_case r \<noteq> forward_case cmd" using action_in_empty_case_absent[OF AI _ REC] EMPTY by (simp add: empty_case_def)
   show ?thesis using LOOKUP AWAY by simp
 qed
 show "case_phase (case_records ?post (abstract_case r)) \<noteq> Case_None" using LOOKUP BEFORE by (auto simp: disposed_case_def)
 show "case_phase (case_records st (abstract_case r)) = Case_Terminal \<longrightarrow> case_phase (case_records ?post (abstract_case r)) = Case_Terminal"
   using LOOKUP by (auto simp: disposed_case_def)
qed

lemma disposition_preserves_action_identity:
 assumes WF: "regulatory_structure_wf st" and SH: "forward_shape_wf st cmd" and FR: "forward_fresh st cmd"
   and KIND: "forward_action cmd \<in> {Legal_Confiscate,Legal_Liquidate,Legal_Recover}"
 shows "action_identity_wf (forward_success_state st cmd w)"
proof -
 let ?post = "forward_success_state st cmd w"
 let ?valid = "\<lambda>s i r. i \<noteq> 0 \<and> abstract_subject r \<noteq> 0 \<and> abstract_case r \<noteq> 0 \<and>
   abstract_lifecycle r \<in> {Record_Applied, Record_Reversed} \<and>
   case_phase (case_records s (abstract_case r)) \<noteq> Case_None \<and>
   \<not> abstract_prior_flag r \<and>
   ((effect_links s i \<noteq> None) = (abstract_action r \<in> {Legal_Freeze, Legal_Restrict})) \<and>
   (case abstract_action r of
     Legal_Freeze \<Rightarrow> abstract_source r = abstract_subject r \<and> abstract_destination r = 0 \<and>
       abstract_custodian r = 0 \<and> abstract_prior_amount r < abstract_amount r \<and>
       case_family (case_records s (abstract_case r)) = Family_Freeze
   | Legal_Restrict \<Rightarrow> abstract_source r = abstract_subject r \<and> abstract_destination r = 0 \<and>
       abstract_custodian r = 0 \<and> abstract_amount r = 0 \<and> abstract_prior_amount r = 0 \<and>
       case_family (case_records s (abstract_case r)) = Family_Restrict
   | Legal_Seize \<Rightarrow> abstract_source r = abstract_subject r \<and> abstract_destination r = abstract_custodian r \<and>
       abstract_custodian r \<noteq> 0 \<and> abstract_subject r \<noteq> abstract_custodian r \<and>
       abstract_amount r > 0 \<and> abstract_prior_amount r = 0 \<and>
       case_family (case_records s (abstract_case r)) = Family_Custody
   | _ \<Rightarrow> abstract_source r \<noteq> 0 \<and> abstract_destination r \<noteq> 0 \<and>
       abstract_source r \<noteq> abstract_destination r \<and> abstract_custodian r = 0 \<and>
       abstract_amount r > 0 \<and> abstract_prior_amount r = 0 \<and> abstract_lifecycle r = Record_Applied \<and>
       case_phase (case_records s (abstract_case r)) = Case_Terminal \<and>
       case_family (case_records s (abstract_case r)) \<in> {Family_Disposition, Family_Custody})"
 have AI: "action_identity_wf st" and H: "effect_history_wf st" using WF unfolding regulatory_structure_wf_def by blast+
 have NON: "forward_action cmd \<notin> {Legal_Freeze,Legal_Restrict}" using KIND by auto
 have EFFECTS: "effect_links ?post = effect_links st" by (rule nonoverlay_forward_views(5)[OF NON])
 have FRESH: "action_records st (forward_action_id cmd) = None" using FR by (simp add: forward_fresh_def)
 have NO_EFFECT: "effect_links st (forward_action_id cmd) = None"
 proof (cases "effect_links st (forward_action_id cmd)")
   case None
   then show ?thesis by simp
 next
   case (Some e)
   note HI = H[unfolded effect_history_wf_def, rule_format, of "forward_action_id cmd" e]
   show ?thesis using HI Some FRESH by auto
 qed
 have IDS: "forward_action_id cmd \<noteq> 0 \<and> forward_subject cmd \<noteq> 0 \<and> forward_case cmd \<noteq> 0"
   using SH unfolding forward_shape_wf_def by blast
 note TRANS = disposition_forward_context(1)[OF WF SH KIND]
 note CTX = disposition_forward_context(2)[OF WF SH KIND]
 have CHECK: "\<And>i r. action_records ?post i = Some r \<Longrightarrow> ?valid ?post i r"
 proof -
   fix i r
   assume POST: "action_records ?post i = Some r"
   show "?valid ?post i r"
   proof (cases "i = forward_action_id cmd")
     case True
     have NEW: "r = forward_action_record st cmd w" using POST True by (simp add: forward_record_lookup)
     show ?thesis using True NEW IDS TRANS KIND CTX NO_EFFECT EFFECTS
       by (cases "forward_action cmd"; auto simp: forward_action_record_def transfer_shape_def
         forward_success_state_def base_forward_success_def disposed_case_def open_case_def empty_case_def Let_def split: if_splits)
   next
     case False
     have OLD: "action_records st i = Some r" using POST False by (simp add: forward_record_lookup)
     have BEFORE: "?valid st i r" using AI OLD unfolding action_identity_wf_def by blast
     note CASES = disposition_preserves_old_record_case[OF WF SH KIND OLD]
     show ?thesis using BEFORE CASES EFFECTS by (auto split: legal_action_kind.splits)
   qed
 qed
 show ?thesis using CHECK unfolding action_identity_wf_def by blast
qed

lemma disposition_preserves_custody_case:
 assumes CU: "custody_case_wf st" and FR: "forward_fresh st cmd"
   and KIND: "forward_action cmd \<in> {Legal_Confiscate,Legal_Liquidate,Legal_Recover}"
 shows "custody_case_wf (forward_success_state st cmd w)"
proof -
 let ?post = "forward_success_state st cmd w"
 let ?cid = "forward_case cmd"
 have TERMINAL: "case_phase (case_records ?post ?cid) = Case_Terminal"
   using KIND by (cases "forward_action cmd") (auto simp: forward_success_state_def base_forward_success_def disposed_case_def Let_def)
 have CASE_FRAME: "\<And>c. c \<noteq> ?cid \<Longrightarrow> case_records ?post c = case_records st c" by (rule forward_case_lookup_away)
 have CUSTODY_FRAME: "\<And>c. c \<noteq> ?cid \<Longrightarrow> custody_records ?post c = custody_records st c"
   using KIND by (cases "forward_action cmd"; auto simp: forward_success_state_def base_forward_success_def close_custody_def Let_def split: option.splits)
 have RECORD_FRAME: "\<And>i r. action_records st i = Some r \<Longrightarrow> action_records ?post i = Some r"
   by (rule forward_record_fresh_preserves_old[OF FR])
 have CU_AT: "custody_records ?post ?cid = (if uses_active_custody st cmd
   then map_option (\<lambda>cu. cu\<lparr>custody_active := False,custody_amount := 0\<rparr>) (custody_records st ?cid)
   else custody_records st ?cid)"
   using KIND by (cases "forward_action cmd"; auto simp: forward_success_state_def base_forward_success_def close_custody_def Let_def split: option.splits)
 have CLOSED: "\<And>cu. custody_records ?post ?cid = Some cu \<Longrightarrow> \<not> custody_active cu \<and> custody_amount cu = 0"
 proof -
   fix cu
   assume POST: "custody_records ?post ?cid = Some cu"
   show "\<not> custody_active cu \<and> custody_amount cu = 0"
   proof (cases "uses_active_custody st cmd")
     case True
     show ?thesis using POST CU_AT True by (cases "custody_records st ?cid") auto
   next
     case False
     have OLD: "custody_records st ?cid = Some cu" using POST CU_AT False by simp
     have INACTIVE: "\<not> custody_active cu" using False OLD by (simp add: uses_active_custody_def)
     have ZERO: "custody_amount cu = 0" using CU[unfolded custody_case_wf_def, THEN conjunct2, rule_format, OF OLD] INACTIVE by simp
     show ?thesis using INACTIVE ZERO by simp
   qed
 qed
 have EQ0: "\<And>c. (open_case st c \<and> case_family (case_records st c) = Family_Custody) =
   (\<exists>cu. custody_records st c = Some cu \<and> custody_active cu)"
   using CU unfolding custody_case_wf_def by blast
 have EQUIV: "\<forall>c. (open_case ?post c \<and> case_family (case_records ?post c) = Family_Custody) =
   (\<exists>cu. custody_records ?post c = Some cu \<and> custody_active cu)"
 proof (intro allI)
   fix c
   show "(open_case ?post c \<and> case_family (case_records ?post c) = Family_Custody) =
     (\<exists>cu. custody_records ?post c = Some cu \<and> custody_active cu)"
   proof (cases "c = ?cid")
     case True
     show ?thesis using True TERMINAL CLOSED by (auto simp: open_case_def)
   next
     case False
     show ?thesis using EQ0[of c] CASE_FRAME[OF False] CUSTODY_FRAME[OF False] by (simp add: open_case_def)
   qed
 qed
 let ?link = "\<lambda>s c cu. \<exists>i r. custody_action cu = Some i \<and> case_head (case_records s c) = Some i \<and>
   action_records s i = Some r \<and> abstract_lifecycle r = Record_Applied \<and> abstract_action r = Legal_Seize \<and>
   abstract_case r = c \<and> abstract_source r = custody_prior_holder cu \<and> abstract_subject r = custody_prior_holder cu \<and>
   abstract_destination r = custody_custodian cu \<and> abstract_custodian r = custody_custodian cu \<and>
   abstract_amount r = custody_amount cu \<and> custody_amount cu > 0 \<and> custody_prior_holder cu \<noteq> 0 \<and>
   custody_custodian cu \<noteq> 0 \<and> custody_prior_holder cu \<noteq> custody_custodian cu"
 have LINKS: "\<And>c cu. custody_records ?post c = Some cu \<Longrightarrow>
   (if custody_active cu then ?link ?post c cu else custody_amount cu = 0)"
 proof -
   fix c cu
   assume POST: "custody_records ?post c = Some cu"
   show "if custody_active cu then ?link ?post c cu else custody_amount cu = 0"
   proof (cases "c = ?cid")
     case True
     show ?thesis using CLOSED POST True by auto
   next
     case False
     have OLD: "custody_records st c = Some cu" using POST CUSTODY_FRAME[OF False] by simp
     have CS: "case_records ?post c = case_records st c" by (rule CASE_FRAME[OF False])
     have BEFORE: "if custody_active cu then ?link st c cu else custody_amount cu = 0"
       using CU OLD unfolding custody_case_wf_def by blast
     have TRANSPORT: "?link st c cu \<Longrightarrow> ?link ?post c cu"
     proof -
       assume L: "?link st c cu"
       obtain i r where W: "custody_action cu = Some i \<and> case_head (case_records st c) = Some i \<and>
         action_records st i = Some r \<and> abstract_lifecycle r = Record_Applied \<and> abstract_action r = Legal_Seize \<and>
         abstract_case r = c \<and> abstract_source r = custody_prior_holder cu \<and> abstract_subject r = custody_prior_holder cu \<and>
         abstract_destination r = custody_custodian cu \<and> abstract_custodian r = custody_custodian cu \<and>
         abstract_amount r = custody_amount cu \<and> custody_amount cu > 0 \<and> custody_prior_holder cu \<noteq> 0 \<and>
         custody_custodian cu \<noteq> 0 \<and> custody_prior_holder cu \<noteq> custody_custodian cu" using L by auto
       have REC: "action_records ?post i = Some r" using RECORD_FRAME W by blast
       show "?link ?post c cu" using W REC CS by auto
     qed
     show ?thesis using BEFORE TRANSPORT by (cases "custody_active cu") auto
   qed
 qed
 show ?thesis using EQUIV LINKS unfolding custody_case_wf_def by blast
qed

theorem disposition_preserves_regulatory_structure:
 assumes WF: "regulatory_structure_wf st" and SH: "forward_shape_wf st cmd" and FR: "forward_fresh st cmd"
   and KIND: "forward_action cmd \<in> {Legal_Confiscate,Legal_Liquidate,Legal_Recover}"
 shows "regulatory_structure_wf (forward_success_state st cmd w)"
proof -
 have NON: "forward_action cmd \<notin> {Legal_Freeze,Legal_Restrict}" using KIND by auto
 have H: "effect_history_wf st" and C: "case_structure_wf st" and CU: "custody_case_wf st"
   using WF unfolding regulatory_structure_wf_def by blast+
 show ?thesis using disposition_preserves_action_identity[OF WF SH FR KIND]
   nonoverlay_preserves_effect_history[OF H FR NON] nonoverlay_preserves_case_structure[OF C FR NON]
   nonoverlay_preserves_freeze_structure[OF WF SH FR NON] nonoverlay_preserves_restriction_structure[OF WF SH FR NON]
   disposition_preserves_custody_case[OF CU FR KIND] unfolding regulatory_structure_wf_def by blast
qed

lemma disposition_numeric_views:
 assumes KIND: "forward_action cmd \<in> {Legal_Confiscate,Legal_Liquidate,Legal_Recover}"
 shows "physical_balances (forward_success_state st cmd w) = move_balance (physical_balances st) (forward_source cmd) (forward_destination cmd) (forward_amount cmd)"
   "custody_backing (forward_success_state st cmd w) = (if uses_active_custody st cmd then
     (custody_backing st)(forward_source cmd := custody_backing st (forward_source cmd) - forward_amount cmd) else custody_backing st)"
   "custody_records (forward_success_state st cmd w) = (if uses_active_custody st cmd then close_custody st (forward_case cmd) else custody_records st)"
 using KIND by (cases "forward_action cmd"; auto simp: forward_success_state_def base_forward_success_def close_custody_def Let_def split: option.splits)+

lemma disposition_preserves_accounting_state_wf:
 assumes WF: "state_wf A C st" and SH: "forward_shape_wf st cmd" and FR: "forward_fresh st cmd"
   and KIND: "forward_action cmd \<in> {Legal_Confiscate,Legal_Liquidate,Legal_Recover}"
 shows "accounting_state_wf (A \<union> {forward_source cmd,forward_custodian cmd,forward_destination cmd})
   (insert (forward_case cmd) C) (forward_success_state st cmd w)"
proof -
 let ?post = "forward_success_state st cmd w"
 let ?src = "forward_source cmd"
 let ?dst = "forward_destination cmd"
 let ?amount = "forward_amount cmd"
 let ?cid = "forward_case cmd"
 let ?A = "A \<union> {?src,forward_custodian cmd,?dst}"
 let ?C = "insert ?cid C"
 have AC: "accounting_state_wf A C st" and REG: "regulatory_structure_wf st" using WF unfolding state_wf_def by blast+
 have BAL0: "balance_wf A st" and SCOPE0: "case_scope C st" and CU0: "custody_consistent C st" and REF0: "custody_case_wf st"
   using AC unfolding accounting_state_wf_def by blast+
 have FIN: "finite C" using SCOPE0 by (simp add: case_scope_def)
 have BOUND0: "\<forall>a. custody_backing st a \<le> physical_balances st a" using CU0 unfolding custody_consistent_def by blast
 have EQ0: "\<And>a. custody_backing st a = active_custody_sum C st a" using CU0 unfolding custody_consistent_def by blast
 note CTX = disposition_forward_context(2)[OF REG SH KIND]
 note TRANS = disposition_forward_context(1)[OF REG SH KIND]
 note V = disposition_numeric_views[OF KIND, of st w]
 have DISTINCT: "?src \<noteq> ?dst" using TRANS by (simp add: transfer_shape_def)
 have PAY: "?amount \<le> physical_balances st ?src"
 proof (cases "uses_active_custody st cmd")
   case False
   show ?thesis using CTX False by (auto simp: unbacked_available_def; arith)
 next
   case True
   have M: "custody_matches st cmd" using CTX True by simp
   have COVER: "?amount \<le> custody_backing st ?src"
     using M by (auto simp: custody_matches_def split: option.splits)
   show ?thesis using COVER BOUND0 by (meson order_trans)
 qed
 have SUM: "\<And>a. active_custody_sum ?C ?post a = (if uses_active_custody st cmd
   then active_custody_sum C st a - (if ?src = a then ?amount else 0) else active_custody_sum C st a)"
 proof -
   fix a
   show "active_custody_sum ?C ?post a = (if uses_active_custody st cmd
     then active_custody_sum C st a - (if ?src = a then ?amount else 0) else active_custody_sum C st a)"
   proof (cases "uses_active_custody st cmd")
     case False
     have EXP: "active_custody_sum ?C st a = active_custody_sum C st a"
       by (rule active_custody_sum_expands_support[OF SCOPE0]) (use FIN in auto)
     show ?thesis using EXP V(3) False by (simp add: active_custody_sum_def)
   next
     case True
     have M: "custody_matches st cmd" using CTX True by simp
     obtain cu where REC: "custody_records st ?cid = Some cu" and ACTIVE: "custody_active cu"
       and CUST: "custody_custodian cu = ?src" and AMOUNT: "custody_amount cu = ?amount"
       using M by (auto simp: custody_matches_def split: option.splits)
     have CLOSE: "active_custody_sum ?C (st\<lparr>custody_records := close_custody st ?cid\<rparr>) a =
       active_custody_sum C st a - (if ?src = a then ?amount else 0)"
       using release_custody_sum_close[OF SCOPE0 REC ACTIVE, of a] CUST AMOUNT by simp
     show ?thesis using CLOSE V(3) True by (simp add: active_custody_sum_def)
   qed
 qed
 have BB: "\<forall>a. custody_backing ?post a \<le> physical_balances ?post a"
 proof (cases "uses_active_custody st cmd")
   case True
   show ?thesis using release_preserves_backing_bound[OF BOUND0 DISTINCT, of ?amount] V(1) V(2) True by simp
 next
   case False
   have AVAIL: "unbacked_available st ?src ?amount" using CTX False by auto
   show ?thesis using unbacked_move_preserves_backing_bound[OF BOUND0 DISTINCT AVAIL] V(1) V(2) False by simp
 qed
 have CU: "custody_consistent ?C ?post" using FIN SUM EQ0 BB V(2)
   by (auto simp: custody_consistent_def split: if_splits)
 have MOVED: "balance_wf ?A (st\<lparr>physical_balances := move_balance (physical_balances st) ?src ?dst ?amount\<rparr>)"
   by (rule move_balance_expanded_support[OF BAL0 PAY])
 have BAL: "balance_wf ?A ?post" using MOVED KIND
   by (cases "forward_action cmd"; auto simp: balance_wf_def forward_success_state_def base_forward_success_def Let_def)
 have SCOPE: "case_scope ?C ?post" using SCOPE0 KIND
   by (cases "forward_action cmd"; auto simp: case_scope_def forward_success_state_def base_forward_success_def close_custody_def Let_def split: option.splits)
 have REF: "custody_case_wf ?post" by (rule disposition_preserves_custody_case[OF REF0 FR KIND])
 show ?thesis using BAL SCOPE CU REF unfolding accounting_state_wf_def by blast
qed

theorem disposition_preserves_state_wf:
 assumes WF: "state_wf A C st" and AD: "forward_admitted st sender time cmd w"
   and KIND: "forward_action cmd \<in> {Legal_Confiscate,Legal_Liquidate,Legal_Recover}"
 shows "state_wf (A \<union> {forward_source cmd,forward_custodian cmd,forward_destination cmd})
   (insert (forward_case cmd) C) (forward_success_state st cmd w)"
proof -
 have SH: "forward_shape_wf st cmd" and FR: "forward_fresh st cmd" using AD unfolding forward_admitted_def by blast+
 have REG: "regulatory_structure_wf st" using WF by (simp add: state_wf_def)
 show ?thesis using disposition_preserves_accounting_state_wf[OF WF SH FR KIND]
   disposition_preserves_regulatory_structure[OF REG SH FR KIND] unfolding state_wf_def by blast
qed


lemma state_wf_expands_support:
 assumes WF: "state_wf A C st" and AB: "A \<subseteq> B" and FB: "finite B" and CD: "C \<subseteq> D" and FD: "finite D"
 shows "state_wf B D st"
 using WF accounting_state_wf_expands_support[of A C st B D] AB FB CD FD unfolding state_wf_def by blast

theorem forward_preserves_state_wf:
 assumes WF: "state_wf A C st" and AD: "forward_admitted st sender time cmd w"
 shows "state_wf (A \<union> {forward_subject cmd,forward_source cmd,forward_destination cmd,forward_custodian cmd})
   (insert (forward_case cmd) C) (forward_success_state st cmd w)"
proof -
 have FIN: "finite A \<and> finite C" using WF by (auto simp: state_wf_def accounting_state_wf_def balance_wf_def case_scope_def)
 show ?thesis
 proof (cases "forward_action cmd")
   case Legal_Freeze
   note R = freeze_preserves_state_wf[OF WF AD Legal_Freeze]
   show ?thesis by (rule state_wf_expands_support[OF R]) (use FIN in auto)
 next
   case Legal_Restrict
   note R = restrict_preserves_state_wf[OF WF AD Legal_Restrict]
   show ?thesis by (rule state_wf_expands_support[OF R]) (use FIN in auto)
 next
   case Legal_Seize
   note R = seize_preserves_state_wf[OF WF AD Legal_Seize]
   show ?thesis by (rule state_wf_expands_support[OF R]) (use FIN in auto)
 next
   case Legal_Confiscate
   have DIS: "forward_action cmd \<in> {Legal_Confiscate,Legal_Liquidate,Legal_Recover}" using Legal_Confiscate by simp
   note R = disposition_preserves_state_wf[OF WF AD DIS]
   show ?thesis by (rule state_wf_expands_support[OF R]) (use FIN in auto)
 next
   case Legal_Liquidate
   have DIS: "forward_action cmd \<in> {Legal_Confiscate,Legal_Liquidate,Legal_Recover}" using Legal_Liquidate by simp
   note R = disposition_preserves_state_wf[OF WF AD DIS]
   show ?thesis by (rule state_wf_expands_support[OF R]) (use FIN in auto)
 next
   case Legal_Recover
   have DIS: "forward_action cmd \<in> {Legal_Confiscate,Legal_Liquidate,Legal_Recover}" using Legal_Recover by simp
   note R = disposition_preserves_state_wf[OF WF AD DIS]
   show ?thesis by (rule state_wf_expands_support[OF R]) (use FIN in auto)
 qed
qed

end
