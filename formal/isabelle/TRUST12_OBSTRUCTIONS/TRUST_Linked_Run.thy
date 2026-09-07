theory TRUST_Linked_Run
  imports TRUST_Release_Preservation "ERC_TRUST.TRUST_End_To_End_Composition"
begin

text \<open>This run records every abstract transaction outcome. Failure steps
  preserve state and the observed failure class; their precise rejection or
  dependency cause is not established by this projection. Initial state_wf
  and the proved transition rules derive preservation. No post-state invariant
  is included in the step predicate. The runtime corollary remains conditional
  on the existing runtime_link and on connected concrete configurations.\<close>

definition model_transaction_step :: "trust_transaction_abstraction \<Rightarrow> bool" where
 "model_transaction_step a \<longleftrightarrow> (case abstraction_outcome a of
   TRUST_Abstract_Applied \<Rightarrow> expected_success_state a = Some (abstraction_post_state a)
 | TRUST_Abstract_Malformed \<Rightarrow> abstraction_command a = None \<and> abstraction_post_state a = abstraction_pre_state a
 | _ \<Rightarrow> abstraction_post_state a = abstraction_pre_state a)"

fun linked_run :: "trust_compositional_state \<Rightarrow> trust_transaction_abstraction list \<Rightarrow> trust_compositional_state \<Rightarrow> bool" where
 "linked_run start [] final = (start = final)"
| "linked_run start (a # rest) final = (abstraction_pre_state a = start \<and> model_transaction_step a \<and>
    linked_run (abstraction_post_state a) rest final)"

definition step_observation where
 "step_observation a = (abstraction_command a, abstraction_outcome a,
   if abstraction_outcome a = TRUST_Abstract_Applied then abstraction_receipt a else None)"
definition run_observations where "run_observations steps = map step_observation steps"

lemma alpha_transaction_supplies_model_step:
 assumes "alpha_transaction manifest bridge execution a"
 shows "model_transaction_step a"
 using assms by (cases "abstraction_outcome a"; auto simp: alpha_transaction_def model_transaction_step_def)

lemma model_transaction_step_preserves_state_wf:
 assumes WF: "state_wf A C (abstraction_pre_state a)" and STEP: "model_transaction_step a"
 shows "\<exists>B D. A \<subseteq> B \<and> C \<subseteq> D \<and> state_wf B D (abstraction_post_state a)"
proof (cases "abstraction_outcome a")
 case TRUST_Abstract_Applied
 have SUCCESS: "expected_success_state a = Some (abstraction_post_state a)"
   using STEP TRUST_Abstract_Applied by (simp add: model_transaction_step_def)
 have CHOICES:
   "(\<exists>cmd w. forward_admitted (abstraction_pre_state a) (abstraction_sender a) (abstraction_time a) cmd w \<and>
      abstraction_post_state a = forward_success_state (abstraction_pre_state a) cmd w) \<or>
    (\<exists>cmd w. reversal_admitted (abstraction_pre_state a) (abstraction_sender a) (abstraction_time a) cmd w \<and>
      abstraction_post_state a = reversal_success_state (abstraction_pre_state a) cmd w)"
 proof (cases "abstraction_command a")
   case None
   show ?thesis using SUCCESS None
     by (cases "abstraction_forward_witness a"; cases "abstraction_reversal_witness a";
       simp_all add: expected_success_state_def)
 next
   case (Some tc)
   note CMD = Some
   show ?thesis
   proof (cases tc)
     case (TRUST_Forward cmd)
     let ?w = "the (abstraction_forward_witness a)"
     have F: "forward_admitted (abstraction_pre_state a) (abstraction_sender a) (abstraction_time a) cmd ?w \<and>
       abstraction_post_state a = forward_success_state (abstraction_pre_state a) cmd ?w"
       using SUCCESS CMD TRUST_Forward
       by (cases "abstraction_forward_witness a"; cases "abstraction_reversal_witness a";
         simp_all add: expected_success_state_def split: if_splits)
     show ?thesis by (rule disjI1, rule exI[where x=cmd], rule exI[where x="?w"], rule F)
   next
     case (TRUST_Reverse cmd)
     let ?w = "the (abstraction_reversal_witness a)"
     have R: "reversal_admitted (abstraction_pre_state a) (abstraction_sender a) (abstraction_time a) cmd ?w \<and>
       abstraction_post_state a = reversal_success_state (abstraction_pre_state a) cmd ?w"
       using SUCCESS CMD TRUST_Reverse
       by (cases "abstraction_forward_witness a"; cases "abstraction_reversal_witness a";
         simp_all add: expected_success_state_def split: if_splits)
     show ?thesis by (rule disjI2, rule exI[where x=cmd], rule exI[where x="?w"], rule R)
   qed
 qed
 then consider (Forward) cmd w where
   "forward_admitted (abstraction_pre_state a) (abstraction_sender a) (abstraction_time a) cmd w"
   "abstraction_post_state a = forward_success_state (abstraction_pre_state a) cmd w"
 | (Reverse) cmd w where
   "reversal_admitted (abstraction_pre_state a) (abstraction_sender a) (abstraction_time a) cmd w"
   "abstraction_post_state a = reversal_success_state (abstraction_pre_state a) cmd w" by blast
 then show ?thesis
 proof cases
   case (Forward cmd w)
   note P = forward_preserves_state_wf[OF WF Forward(1)]
   have "A \<subseteq> A \<union> {forward_subject cmd,forward_source cmd,forward_destination cmd,forward_custodian cmd} \<and>
     C \<subseteq> insert (forward_case cmd) C \<and>
     state_wf (A \<union> {forward_subject cmd,forward_source cmd,forward_destination cmd,forward_custodian cmd})
       (insert (forward_case cmd) C) (abstraction_post_state a)" using P Forward(2) by auto
   then show ?thesis by blast
 next
   case (Reverse cmd w)
   let ?r = "record_at (abstraction_pre_state a) (reversal_original_action_id cmd)"
   note P = reversal_preserves_state_wf[OF WF Reverse(1)]
   have "A \<subseteq> A \<union> {abstract_subject ?r,abstract_source ?r,abstract_destination ?r,abstract_custodian ?r} \<and>
     C \<subseteq> insert (abstract_case ?r) C \<and>
     state_wf (A \<union> {abstract_subject ?r,abstract_source ?r,abstract_destination ?r,abstract_custodian ?r})
       (insert (abstract_case ?r) C) (abstraction_post_state a)" using P Reverse(2) by auto
   then show ?thesis by blast
 qed
next
 case TRUST_Abstract_Rejected
 show ?thesis using WF STEP TRUST_Abstract_Rejected by (auto simp: model_transaction_step_def)
next
 case TRUST_Abstract_Operational
 show ?thesis using WF STEP TRUST_Abstract_Operational by (auto simp: model_transaction_step_def)
next
 case TRUST_Abstract_Malformed
 show ?thesis using WF STEP TRUST_Abstract_Malformed by (auto simp: model_transaction_step_def)
next
 case TRUST_Abstract_Dependency_Revert
 show ?thesis using WF STEP TRUST_Abstract_Dependency_Revert by (auto simp: model_transaction_step_def)
qed

theorem linked_run_preserves_state_wf:
 assumes WF: "state_wf A C start" and RUN: "linked_run start steps final"
 shows "\<exists>B D. A \<subseteq> B \<and> C \<subseteq> D \<and> state_wf B D final"
 using WF RUN
proof (induction steps arbitrary: A C start)
 case Nil
 show ?case using Nil by auto
next
 case (Cons a rest)
 have PRE: "abstraction_pre_state a = start" and STEP: "model_transaction_step a"
   and REST: "linked_run (abstraction_post_state a) rest final" using Cons.prems(2) by auto
 have PREWF: "state_wf A C (abstraction_pre_state a)" using Cons.prems(1) PRE by simp
 obtain B D where AB: "A \<subseteq> B" and CD: "C \<subseteq> D" and NEXT: "state_wf B D (abstraction_post_state a)"
   using model_transaction_step_preserves_state_wf[OF PREWF STEP] by blast
 obtain E F where BE: "B \<subseteq> E" and DF: "D \<subseteq> F" and FINAL: "state_wf E F final"
   using Cons.IH[OF NEXT REST] by blast
 show ?case using AB CD BE DF FINAL by blast
qed

lemma linked_run_append:
 "linked_run start (xs @ ys) final = (\<exists>middle. linked_run start xs middle \<and> linked_run middle ys final)"
 by (induction xs arbitrary: start) auto

theorem linked_run_every_prefix_preserves_state_wf:
 assumes WF: "state_wf A C start" and RUN: "linked_run start (prefix @ suffix) final"
 shows "\<exists>middle B D. linked_run start prefix middle \<and> linked_run middle suffix final \<and>
   A \<subseteq> B \<and> C \<subseteq> D \<and> state_wf B D middle"
 using RUN linked_run_preserves_state_wf[OF WF] by (auto simp: linked_run_append)

lemma linked_run_contains_valid_steps:
 assumes "linked_run start steps final" "a \<in> set steps"
 shows "model_transaction_step a"
 using assms by (induction steps arbitrary: start) auto

lemma all_transaction_outcomes_retained:
 "map (\<lambda>x. fst (snd x)) (run_observations steps) = map abstraction_outcome steps"
 by (simp add: run_observations_def step_observation_def)

lemma observations_preserve_length:
 "length (run_observations steps) = length steps"
 by (simp add: run_observations_def)

lemma observation_preserves_position:
 assumes "i < length steps"
 shows "run_observations steps ! i = step_observation (steps ! i)"
 using assms by (simp add: run_observations_def)

lemma failure_observation_has_no_success_receipt:
 assumes "abstraction_outcome a \<noteq> TRUST_Abstract_Applied"
 shows "snd (snd (step_observation a)) = None"
 using assms by (simp add: step_observation_def)

lemma applied_model_step_has_receipt:
 assumes "model_transaction_step a" "abstraction_outcome a = TRUST_Abstract_Applied"
 shows "\<exists>receipt. snd (snd (step_observation a)) = Some receipt"
 using assms by (auto simp: model_transaction_step_def expected_success_state_def step_observation_def abstraction_receipt_def
   split: option.splits trust_typed_command.splits if_splits)

fun concrete_configurations_linked :: "current_trust_configuration \<Rightarrow> trust_transaction_execution list \<Rightarrow>
   current_trust_configuration \<Rightarrow> bool" where
 "concrete_configurations_linked start [] final = (start = final)"
| "concrete_configurations_linked start (e # rest) final = (transaction_pre e = start \<and>
    concrete_configurations_linked (transaction_post_configuration e) rest final)"

lemma connected_alpha_transactions_form_linked_run:
 assumes ALPHA: "list_all2 (alpha_transaction manifest bridge) executions steps"
   and CHAIN: "concrete_configurations_linked configuration executions final_configuration"
   and START: "alpha_current manifest configuration = Some start"
   and FINAL: "alpha_current manifest final_configuration = Some final"
 shows "linked_run start steps final"
 using ALPHA CHAIN START
proof (induction executions arbitrary: steps configuration start)
 case Nil
 show ?case using Nil FINAL by simp
next
 case (Cons e rest)
 obtain a tail where STEPS: "steps = a # tail" and ALPHA0: "alpha_transaction manifest bridge e a"
   and ALPHAREST: "list_all2 (alpha_transaction manifest bridge) rest tail"
   using Cons.prems(1) by (cases steps) auto
 have PRECONFIG: "transaction_pre e = configuration"
   and REST: "concrete_configurations_linked (transaction_post_configuration e) rest final_configuration"
   using Cons.prems(2) by auto
 have PRE: "abstraction_pre_state a = start" using ALPHA0 Cons.prems(3) PRECONFIG
   by (auto simp: alpha_transaction_def)
 have POST: "alpha_current manifest (transaction_post_configuration e) = Some (abstraction_post_state a)"
   using ALPHA0 by (simp add: alpha_transaction_def)
 have RUNREST: "linked_run (abstraction_post_state a) tail final" by (rule Cons.IH[OF ALPHAREST REST POST])
 have STEP: "model_transaction_step a" by (rule alpha_transaction_supplies_model_step[OF ALPHA0])
 show ?case using STEPS PRE STEP RUNREST by simp
qed

context pinned_runtime_refinement
begin

theorem runtime_linked_run_conditional:
 assumes EXECUTIONS: "list_all runtime_execution executions"
   and CHAIN: "concrete_configurations_linked configuration executions final_configuration"
   and START: "alpha_current manifest configuration = Some start"
   and FINAL: "alpha_current manifest final_configuration = Some final"
 shows "linked_run start (map runtime_abstraction executions) final"
proof -
 have ALPHA: "list_all2 (alpha_transaction manifest bridge) executions (map runtime_abstraction executions)"
   using EXECUTIONS runtime_link by (induction executions) auto
 show ?thesis by (rule connected_alpha_transactions_form_linked_run[OF ALPHA CHAIN START FINAL])
qed

end

end
