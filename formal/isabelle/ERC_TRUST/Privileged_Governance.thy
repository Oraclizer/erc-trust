(*
  ERC-TRUST typed privileged governance operations.

  These operations cover privileged mint, burn, batch, and recovery
  supply paths.  They cannot modify regulatory cases, frozen amounts,
  custody, policy bindings, allowances, or the canonical RCP receipt.
*)

theory Privileged_Governance
  imports Regulatory_Execution_Simulation
begin

fun governance_operation_write_set ::
  "governance_operation \<Rightarrow> write_slot list"
where
  "governance_operation_write_set
      (Governance_Recovery_Supply_Transfer _ _ _) =
     [Balance_Slot, Nonce_Slot, Receipt_Slot]"
| "governance_operation_write_set _ =
     [Balance_Slot, Supply_Slot, Nonce_Slot, Receipt_Slot]"

fun governance_touches_account ::
  "governance_operation \<Rightarrow> nat \<Rightarrow> bool"
where
  "governance_touches_account (Governance_Mint subject _) account =
     (account = subject)"
| "governance_touches_account (Governance_Burn subject _) account =
     (account = subject)"
| "governance_touches_account
      (Governance_Batch_Mint first _ second _) account =
     (account = first \<or> account = second)"
| "governance_touches_account
      (Governance_Batch_Burn first _ second _) account =
     (account = first \<or> account = second)"
| "governance_touches_account
      (Governance_Recovery_Supply_Transfer source destination _) account =
     (account = source \<or> account = destination)"

definition governance_account_clear ::
  "trust_state \<Rightarrow> nat \<Rightarrow> bool"
where
  "governance_account_clear st account \<longleftrightarrow>
     trust_modes st account = ACTIVE \<and>
     trust_frozen_tokens st account = 0 \<and>
     trust_custody st account = None \<and>
     trust_encumbered_amount st account = 0 \<and>
     trust_declared_prior_holder st account = None"

fun governance_operation_enabled ::
  "trust_state \<Rightarrow> governance_operation \<Rightarrow> bool"
where
  "governance_operation_enabled st (Governance_Mint subject amount) =
     (governance_account_clear st subject \<and> amount > 0)"
| "governance_operation_enabled st (Governance_Burn subject amount) =
     (governance_account_clear st subject \<and> amount > 0 \<and>
      trust_balances st subject \<ge> amount \<and>
      trust_total_supply st \<ge> amount)"
| "governance_operation_enabled st
      (Governance_Batch_Mint first first_amount second second_amount) =
     (first \<noteq> second \<and>
      governance_account_clear st first \<and>
      governance_account_clear st second \<and>
      first_amount > 0 \<and> second_amount > 0)"
| "governance_operation_enabled st
      (Governance_Batch_Burn first first_amount second second_amount) =
     (first \<noteq> second \<and>
      governance_account_clear st first \<and>
      governance_account_clear st second \<and>
      first_amount > 0 \<and> second_amount > 0 \<and>
      trust_balances st first \<ge> first_amount \<and>
      trust_balances st second \<ge> second_amount \<and>
      trust_total_supply st \<ge> first_amount + second_amount)"
| "governance_operation_enabled st
      (Governance_Recovery_Supply_Transfer source destination amount) =
     (source \<noteq> destination \<and>
      governance_account_clear st source \<and>
      governance_account_clear st destination \<and>
      amount > 0 \<and>
      trust_balances st source \<ge> amount)"

fun governance_resulting_balances ::
  "trust_state \<Rightarrow> governance_operation \<Rightarrow> nat \<Rightarrow> nat"
where
  "governance_resulting_balances st (Governance_Mint subject amount) =
     (trust_balances st)
       (subject := trust_balances st subject + amount)"
| "governance_resulting_balances st (Governance_Burn subject amount) =
     (trust_balances st)
       (subject := trust_balances st subject - amount)"
| "governance_resulting_balances st
      (Governance_Batch_Mint first first_amount second second_amount) =
     (trust_balances st)
       (first := trust_balances st first + first_amount,
        second := trust_balances st second + second_amount)"
| "governance_resulting_balances st
      (Governance_Batch_Burn first first_amount second second_amount) =
     (trust_balances st)
       (first := trust_balances st first - first_amount,
        second := trust_balances st second - second_amount)"
| "governance_resulting_balances st
      (Governance_Recovery_Supply_Transfer source destination amount) =
     (trust_balances st)
       (source := trust_balances st source - amount,
        destination := trust_balances st destination + amount)"

fun governance_resulting_supply ::
  "trust_state \<Rightarrow> governance_operation \<Rightarrow> nat"
where
  "governance_resulting_supply st (Governance_Mint _ amount) =
     trust_total_supply st + amount"
| "governance_resulting_supply st (Governance_Burn _ amount) =
     trust_total_supply st - amount"
| "governance_resulting_supply st
      (Governance_Batch_Mint _ first_amount _ second_amount) =
     trust_total_supply st + first_amount + second_amount"
| "governance_resulting_supply st
      (Governance_Batch_Burn _ first_amount _ second_amount) =
     trust_total_supply st - first_amount - second_amount"
| "governance_resulting_supply st
      (Governance_Recovery_Supply_Transfer _ _ _) =
     trust_total_supply st"

definition governance_request_binding_matches ::
  "trust_state \<Rightarrow> governance_request \<Rightarrow> bool"
where
  "governance_request_binding_matches st req \<longleftrightarrow>
     governance_request_chain req = trust_chain st \<and>
     governance_request_token req = trust_token st \<and>
     governance_request_standard_version req = trust_standard_version st \<and>
     governance_request_authority_epoch req = trust_authority_epoch st \<and>
     governance_request_policy_epoch req = trust_policy_epoch st"

definition execute_governance ::
  "trust_state \<Rightarrow> governance_request \<Rightarrow>
   trust_state \<times> trust_outcome"
where
  "execute_governance st req =
    (let operation = governance_request_operation req;
         nonce = governance_request_nonce req
     in
       if governance_request_actor req \<noteq> trust_governance_authority st
       then (st, Trust_Rejected Actor_Not_Authorized)
       else if \<not> governance_request_binding_matches st req
       then (st, Trust_Rejected Authorization_Stale)
       else if nonce \<in> trust_consumed_nonces st
       then (st, Trust_Rejected Authorization_Replayed)
       else if \<not> governance_operation_enabled st operation
       then (st, Trust_Rejected Invalid_State_Transition)
       else
         (st\<lparr>
            trust_balances := governance_resulting_balances st operation,
            trust_total_supply := governance_resulting_supply st operation,
            trust_consumed_nonces := insert nonce (trust_consumed_nonces st),
            trust_last_governance_receipt :=
              Some
                \<lparr>governance_receipt_operation = operation,
                 governance_receipt_actor = governance_request_actor req,
                 governance_receipt_nonce = nonce,
                 governance_receipt_authority_epoch =
                   governance_request_authority_epoch req,
                 governance_receipt_policy_epoch =
                   governance_request_policy_epoch req,
                 governance_receipt_write_set =
                   governance_operation_write_set operation\<rparr>
          \<rparr>,
          Trust_Applied))"

theorem rejected_governance_is_full_state_stutter:
  assumes
    "execute_governance st req = (st', Trust_Rejected reason)"
  shows "st' = st"
  using assms
  unfolding execute_governance_def
  by (cases "governance_request_operation req")
     (auto split: if_splits simp: Let_def)

theorem successful_governance_receipt_has_exact_write_set:
  assumes "execute_governance st req = (st', Trust_Applied)"
  shows
    "\<exists>receipt.
       trust_last_governance_receipt st' = Some receipt \<and>
       governance_receipt_operation receipt =
         governance_request_operation req \<and>
       governance_receipt_nonce receipt = governance_request_nonce req \<and>
       governance_receipt_write_set receipt =
         governance_operation_write_set
           (governance_request_operation req)"
  using assms
  unfolding execute_governance_def
  by (cases "governance_request_operation req")
     (auto split: if_splits simp: Let_def)

theorem successful_governance_has_exact_balance_supply_nonce_effects:
  assumes "execute_governance st req = (st', Trust_Applied)"
  shows
    "trust_balances st' =
       governance_resulting_balances st
         (governance_request_operation req) \<and>
     trust_total_supply st' =
       governance_resulting_supply st
         (governance_request_operation req) \<and>
     trust_consumed_nonces st' =
       insert (governance_request_nonce req)
         (trust_consumed_nonces st) \<and>
     trust_last_governance_receipt st' =
       Some
         \<lparr>governance_receipt_operation =
             governance_request_operation req,
          governance_receipt_actor = governance_request_actor req,
          governance_receipt_nonce = governance_request_nonce req,
          governance_receipt_authority_epoch =
            governance_request_authority_epoch req,
          governance_receipt_policy_epoch =
            governance_request_policy_epoch req,
          governance_receipt_write_set =
            governance_operation_write_set
              (governance_request_operation req)\<rparr>"
  using assms
  unfolding execute_governance_def
  by (cases "governance_request_operation req")
     (auto split: if_splits simp: Let_def)

theorem successful_governance_requires_clear_touched_accounts:
  assumes "execute_governance st req = (st', Trust_Applied)"
      and "governance_touches_account
        (governance_request_operation req) account"
  shows "governance_account_clear st account"
  using assms
  unfolding execute_governance_def
  by (cases "governance_request_operation req")
     (auto split: if_splits simp: Let_def)

theorem confiscated_governance_account_is_terminal:
  assumes
    "trust_modes st account = CONFISCATED"
    "governance_touches_account
      (governance_request_operation req) account"
  shows "snd (execute_governance st req) \<noteq> Trust_Applied"
proof
  assume applied: "snd (execute_governance st req) = Trust_Applied"
  then have execution:
    "execute_governance st req =
      (fst (execute_governance st req), Trust_Applied)"
    by (cases "execute_governance st req") auto
  then have "governance_account_clear st account"
    using successful_governance_requires_clear_touched_accounts assms(2)
    by blast
  then show False
    using assms(1) unfolding governance_account_clear_def by simp
qed

theorem successful_governance_complete_frame:
  assumes execution:
    "execute_governance st req = (st', Trust_Applied)"
      and account:
    "\<not> governance_touches_account
      (governance_request_operation req) other_account"
      and nonce:
    "other_nonce \<noteq> governance_request_nonce req"
  shows
    "trust_balances st' other_account = trust_balances st other_account \<and>
     trust_allowances st' = trust_allowances st \<and>
     trust_modes st' = trust_modes st \<and>
     trust_frozen_tokens st' = trust_frozen_tokens st \<and>
     trust_custody st' = trust_custody st \<and>
     trust_case_registry st' = trust_case_registry st \<and>
     trust_encumbered_amount st' = trust_encumbered_amount st \<and>
     trust_declared_prior_holder st' = trust_declared_prior_holder st \<and>
     trust_settlement_commitment st' = trust_settlement_commitment st \<and>
     trust_proceeds_reference st' = trust_proceeds_reference st \<and>
     trust_entitlement_commitment st' = trust_entitlement_commitment st \<and>
     trust_external_settlement_status st' =
       trust_external_settlement_status st \<and>
     trust_cases st' = trust_cases st \<and>
     trust_receipt_registry st' = trust_receipt_registry st \<and>
     trust_authorizations st' = trust_authorizations st \<and>
     (other_nonce \<in> trust_consumed_nonces st') =
       (other_nonce \<in> trust_consumed_nonces st) \<and>
     trust_policy_epoch st' = trust_policy_epoch st \<and>
     trust_chain st' = trust_chain st \<and>
     trust_token st' = trust_token st \<and>
     trust_standard_version st' = trust_standard_version st \<and>
     trust_authority_epoch st' = trust_authority_epoch st \<and>
     trust_policy_code st' = trust_policy_code st \<and>
     trust_policy_schema st' = trust_policy_schema st \<and>
     trust_policy_config st' = trust_policy_config st \<and>
     trust_governance_authority st' = trust_governance_authority st \<and>
     trust_regulatory_authorities st' =
       trust_regulatory_authorities st \<and>
     trust_last_policy_change st' = trust_last_policy_change st \<and>
     trust_last_receipt st' = trust_last_receipt st \<and>
     trust_auxiliary st' = trust_auxiliary st"
  using assms
  unfolding execute_governance_def
  by (cases "governance_request_operation req")
     (auto split: if_splits simp: Let_def)

definition governance_witness_state :: trust_state where
  "governance_witness_state =
    (witness_seed_state Legal_Freeze)\<lparr>
      trust_balances :=
        (trust_balances (witness_seed_state Legal_Freeze))(4 := 50),
      trust_total_supply := 150\<rparr>"

definition governance_witness_request ::
  "governance_operation \<Rightarrow> nat \<Rightarrow> governance_request"
where
  "governance_witness_request operation nonce =
    \<lparr>governance_request_operation = operation,
     governance_request_actor = 0,
     governance_request_chain = 31337,
     governance_request_token = 8319,
     governance_request_standard_version = 1,
     governance_request_nonce = nonce,
     governance_request_authority_epoch = 7,
     governance_request_policy_epoch = 1\<rparr>"

theorem all_privileged_governance_classes_have_reachable_witnesses:
  "snd (execute_governance governance_witness_state
      (governance_witness_request (Governance_Mint 2 10) 401)) =
      Trust_Applied \<and>
   snd (execute_governance governance_witness_state
      (governance_witness_request (Governance_Burn 1 10) 402)) =
      Trust_Applied \<and>
   snd (execute_governance governance_witness_state
      (governance_witness_request
        (Governance_Batch_Mint 2 10 3 20) 403)) =
      Trust_Applied \<and>
   snd (execute_governance governance_witness_state
      (governance_witness_request
        (Governance_Batch_Burn 1 10 4 20) 404)) =
      Trust_Applied \<and>
   snd (execute_governance governance_witness_state
      (governance_witness_request
        (Governance_Recovery_Supply_Transfer 1 2 10) 405)) =
      Trust_Applied"
  by (simp add: governance_witness_state_def governance_witness_request_def
      witness_seed_state_def witness_context_def execute_governance_def
      governance_request_binding_matches_def governance_account_clear_def
      Let_def)

definition applied_governance_mint_state :: trust_state where
  "applied_governance_mint_state =
    fst (execute_governance governance_witness_state
      (governance_witness_request (Governance_Mint 2 10) 401))"

definition blocked_governance_seized_state :: trust_state where
  "blocked_governance_seized_state =
    governance_witness_state\<lparr>
      trust_modes := (trust_modes governance_witness_state)(1 := SEIZED),
      trust_custody := (trust_custody governance_witness_state)(1 := Some 9),
      trust_encumbered_amount :=
        (trust_encumbered_amount governance_witness_state)(1 := 10),
      trust_declared_prior_holder :=
        (trust_declared_prior_holder governance_witness_state)(1 := Some 1)
    \<rparr>"

theorem privileged_governance_is_typed_replay_safe_and_fail_closed:
  "snd (execute_governance applied_governance_mint_state
      (governance_witness_request (Governance_Mint 2 10) 401)) =
       Trust_Rejected Authorization_Replayed \<and>
   snd (execute_governance governance_witness_state
      ((governance_witness_request (Governance_Mint 2 10) 406)
        \<lparr>governance_request_actor := 99\<rparr>)) =
       Trust_Rejected Actor_Not_Authorized \<and>
   execute_governance blocked_governance_seized_state
      (governance_witness_request (Governance_Mint 1 10) 407) =
     (blocked_governance_seized_state,
      Trust_Rejected Invalid_State_Transition)"
  by (simp add: applied_governance_mint_state_def governance_witness_state_def
      blocked_governance_seized_state_def governance_witness_request_def
      witness_seed_state_def
      witness_context_def execute_governance_def
      governance_request_binding_matches_def governance_account_clear_def
      Let_def)

end
