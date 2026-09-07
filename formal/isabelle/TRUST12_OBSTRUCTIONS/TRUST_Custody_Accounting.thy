theory TRUST_Custody_Accounting
 imports TRUST_State_Invariants
begin
abbreviation custody_term :: "trust_compositional_state \<Rightarrow> trust_case_id \<Rightarrow> trust_address \<Rightarrow> nat" where
 "custody_term st c a \<equiv> (case custody_records st c of None \<Rightarrow> 0 | Some cu \<Rightarrow>
   if custody_active cu \<and> custody_custodian cu = a then custody_amount cu else 0)"

lemma custody_sum_remove_case:
 assumes FIN: "finite C" and MEM: "c \<in> C"
 shows "active_custody_sum C st a = custody_term st c a + active_custody_sum (C - {c}) st a"
 unfolding active_custody_sum_def by (rule sum.remove[OF FIN MEM])

lemma custody_sum_update_case:
 assumes FIN: "finite C" and MEM: "c \<in> C"
 shows "active_custody_sum C (st\<lparr>custody_records := (custody_records st)(c := next)\<rparr>) a + custody_term st c a =
   active_custody_sum C st a + custody_term (st\<lparr>custody_records := (custody_records st)(c := next)\<rparr>) c a"
proof -
 let ?st' = "st\<lparr>custody_records := (custody_records st)(c := next)\<rparr>"
 have FRAME: "active_custody_sum (C - {c}) ?st' a = active_custody_sum (C - {c}) st a"
   unfolding active_custody_sum_def by (rule sum.cong) auto
 have OLD: "active_custody_sum C st a = custody_term st c a + active_custody_sum (C - {c}) st a"
   by (rule custody_sum_remove_case[OF FIN MEM])
 have NEW: "active_custody_sum C ?st' a = custody_term ?st' c a + active_custody_sum (C - {c}) ?st' a"
   by (rule custody_sum_remove_case[OF FIN MEM])
 show ?thesis using OLD NEW FRAME by presburger
qed

lemma seize_custody_sum_insert:
 assumes FIN: "finite C" and OLD: "\<not> (\<exists>old. custody_records st c = Some old \<and> custody_active old)"
   and ACTIVE: "custody_active cu"
 shows "active_custody_sum (insert c C) (st\<lparr>custody_records := (custody_records st)(c := Some cu)\<rparr>) a =
   active_custody_sum C st a + (if custody_custodian cu = a then custody_amount cu else 0)"
proof -
 let ?st' = "st\<lparr>custody_records := (custody_records st)(c := Some cu)\<rparr>"
 have ZERO: "custody_term st c a = 0" using OLD by (cases "custody_records st c") auto
 show ?thesis
 proof (cases "c \<in> C")
   case True
   have UPDATE: "active_custody_sum C ?st' a + custody_term st c a = active_custody_sum C st a + custody_term ?st' c a"
     by (rule custody_sum_update_case[OF FIN True])
   show ?thesis using UPDATE ZERO ACTIVE True by (simp add: insert_absorb)
 next
   case False
   have FRAME: "active_custody_sum C ?st' a = active_custody_sum C st a"
     unfolding active_custody_sum_def by (rule sum.cong) (use False in auto)
   have INSERT: "active_custody_sum (insert c C) ?st' a = custody_term ?st' c a + active_custody_sum C ?st' a"
     using FIN False by (simp add: active_custody_sum_def)
   show ?thesis using INSERT FRAME ACTIVE by (simp add: add.commute)
 qed
qed

lemma release_custody_sum_close:
 assumes SCOPE: "case_scope C st" and REC: "custody_records st c = Some cu" and ACTIVE: "custody_active cu"
 shows "active_custody_sum (insert c C) (st\<lparr>custody_records := close_custody st c\<rparr>) a =
   active_custody_sum C st a - (if custody_custodian cu = a then custody_amount cu else 0)"
proof -
 have FIN: "finite C" using SCOPE by (simp add: case_scope_def)
 have MEM: "c \<in> C"
 proof (rule ccontr)
   assume OUT: "c \<notin> C"
   have "custody_records st c = None" using SCOPE OUT unfolding case_scope_def by blast
   with REC show False by simp
 qed
 let ?closed = "cu\<lparr>custody_active := False, custody_amount := 0\<rparr>"
 let ?st' = "st\<lparr>custody_records := close_custody st c\<rparr>"
 have CLOSE: "?st' = st\<lparr>custody_records := (custody_records st)(c := Some ?closed)\<rparr>"
   using REC by (simp add: close_custody_def)
 have UPDATE: "active_custody_sum C (st\<lparr>custody_records := (custody_records st)(c := Some ?closed)\<rparr>) a + custody_term st c a =
   active_custody_sum C st a + custody_term (st\<lparr>custody_records := (custody_records st)(c := Some ?closed)\<rparr>) c a"
   by (rule custody_sum_update_case[OF FIN MEM])
 have ADD: "active_custody_sum C ?st' a + (if custody_custodian cu = a then custody_amount cu else 0) = active_custody_sum C st a"
   using UPDATE CLOSE REC ACTIVE by simp
 have SUB: "active_custody_sum C ?st' a = active_custody_sum C st a - (if custody_custodian cu = a then custody_amount cu else 0)"
   using ADD by presburger
 show ?thesis using SUB MEM by (simp add: insert_absorb)
qed

lemma seize_preserves_backing_bound:
 assumes BOUND: "\<forall>a. custody_backing st a \<le> physical_balances st a" and DISTINCT: "src \<noteq> cust"
   and AVAILABLE: "unbacked_available st src amount"
 shows "\<forall>a. ((custody_backing st)(cust := custody_backing st cust + amount)) a \<le>
   move_balance (physical_balances st) src cust amount a"
proof (intro allI)
 fix a
 have REMAIN: "custody_backing st src \<le> physical_balances st src - amount"
   using AVAILABLE unfolding unbacked_available_def by presburger
 have AT: "custody_backing st a \<le> physical_balances st a" using BOUND by blast
 show "((custody_backing st)(cust := custody_backing st cust + amount)) a \<le> move_balance (physical_balances st) src cust amount a"
   using DISTINCT REMAIN AT by (cases "a = src"; cases "a = cust"; auto simp: move_balance_def; arith)
qed

text \<open>The bound below alone does not establish payment validity or supply conservation.\<close>
lemma release_preserves_backing_bound:
 assumes BOUND: "\<forall>a. custody_backing st a \<le> physical_balances st a" and DISTINCT: "cust \<noteq> holder"
 shows "\<forall>a. ((custody_backing st)(cust := custody_backing st cust - amount)) a \<le>
   move_balance (physical_balances st) cust holder amount a"
proof (intro allI)
 fix a
 have SOURCE: "custody_backing st cust \<le> physical_balances st cust" using BOUND by blast
 have REMAIN: "custody_backing st cust - amount \<le> physical_balances st cust - amount" using SOURCE by arith
 have AT: "custody_backing st a \<le> physical_balances st a" using BOUND by blast
 show "((custody_backing st)(cust := custody_backing st cust - amount)) a \<le> move_balance (physical_balances st) cust holder amount a"
   using DISTINCT SOURCE REMAIN AT by (cases "a = cust"; cases "a = holder"; auto simp: move_balance_def; arith)
qed

lemma move_balance_expanded_support:
 assumes WF: "balance_wf A st" and PAY: "amount \<le> physical_balances st src"
 shows "balance_wf (A \<union> {src,cust,dst})
   (st\<lparr>physical_balances := move_balance (physical_balances st) src dst amount\<rparr>)"
proof -
 have FIN: "finite A" using WF by (simp add: balance_wf_def)
 have EXPANDED: "balance_wf (A \<union> {src,cust,dst}) st"
   by (rule balance_wf_expands_support[OF WF]) (use FIN in auto)
 show ?thesis by (rule move_balance_preserves_balance_wf[OF EXPANDED]) (use PAY in auto)
qed

lemma case_scope_single_update:
 assumes SCOPE: "case_scope C st"
 shows "case_scope (insert c C) (st\<lparr>case_records := (case_records st)(c := next_case), custody_records := (custody_records st)(c := next_custody)\<rparr>)"
 using SCOPE by (auto simp: case_scope_def)
lemma unbacked_move_preserves_backing_bound:
 assumes BOUND: "\<forall>a. custody_backing st a \<le> physical_balances st a" and DISTINCT: "src \<noteq> dst"
   and AVAILABLE: "unbacked_available st src amount"
 shows "\<forall>a. custody_backing st a \<le> move_balance (physical_balances st) src dst amount a"
proof (intro allI)
 fix a
 have REMAIN: "custody_backing st src \<le> physical_balances st src - amount"
   using AVAILABLE unfolding unbacked_available_def by presburger
 have AT: "custody_backing st a \<le> physical_balances st a" using BOUND by blast
 show "custody_backing st a \<le> move_balance (physical_balances st) src dst amount a"
   using DISTINCT REMAIN AT by (cases "a = src"; cases "a = dst"; auto simp: move_balance_def; arith)
qed

end
