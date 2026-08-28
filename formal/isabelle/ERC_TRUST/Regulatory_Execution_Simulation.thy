(*
  ERC-TRUST executable witnesses and abstract simulation facts.

  The witnesses start from an authorization-free declared seed, execute the
  create/approve lifecycle, and only then exercise a regulatory entrypoint.
*)

theory Regulatory_Execution_Simulation
  imports Token_Compatibility
begin

section \<open>Concrete Reachable Fixtures\<close>

fun witness_initial_mode :: "legal_action_kind \<Rightarrow> reg_state" where
  "witness_initial_mode Legal_Recover = SEIZED"
| "witness_initial_mode Legal_Liquidate = SEIZED"
| "witness_initial_mode _ = ACTIVE"

fun witness_destination :: "legal_action_kind \<Rightarrow> nat option" where
  "witness_destination Legal_Seize = Some 9"
| "witness_destination Legal_Confiscate = Some 2"
| "witness_destination Legal_Recover = Some 2"
| "witness_destination Legal_Liquidate = Some 2"
| "witness_destination _ = None"

fun witness_amount :: "legal_action_kind \<Rightarrow> nat" where
  "witness_amount Legal_Confiscate = 100"
| "witness_amount _ = 10"

fun witness_pre_observation ::
  "legal_action_kind \<Rightarrow> trust_observation"
where
  "witness_pre_observation Legal_Freeze =
     Trust_Observation ACTIVE 100 0 0 None"
| "witness_pre_observation Legal_Seize =
     Trust_Observation ACTIVE 100 0 0 None"
| "witness_pre_observation Legal_Confiscate =
     Trust_Observation ACTIVE 100 0 0 None"
| "witness_pre_observation Legal_Restrict =
     Trust_Observation ACTIVE 100 0 0 None"
| "witness_pre_observation Legal_Recover =
     Trust_Observation SEIZED 100 0 10 (Some 504)"
| "witness_pre_observation Legal_Liquidate =
     Trust_Observation SEIZED 100 0 10 (Some 505)"

fun witness_post_observation ::
  "legal_action_kind \<Rightarrow> trust_observation"
where
  "witness_post_observation Legal_Freeze =
     Trust_Observation FROZEN 100 10 0 (Some 500)"
| "witness_post_observation Legal_Seize =
     Trust_Observation SEIZED 100 0 10 (Some 501)"
| "witness_post_observation Legal_Confiscate =
     Trust_Observation CONFISCATED 0 0 0 (Some 502)"
| "witness_post_observation Legal_Restrict =
     Trust_Observation RESTRICTED 100 0 0 (Some 503)"
| "witness_post_observation Legal_Recover =
     Trust_Observation ACTIVE 90 0 0 None"
| "witness_post_observation Legal_Liquidate =
     Trust_Observation ACTIVE 90 0 0 None"

definition witness_context :: "legal_action_kind \<Rightarrow> entry_context" where
  "witness_context k =
    \<lparr>context_authorization_id = 700 + (case k of
        Legal_Freeze \<Rightarrow> 0 | Legal_Seize \<Rightarrow> 1
      | Legal_Confiscate \<Rightarrow> 2 | Legal_Restrict \<Rightarrow> 3
      | Legal_Recover \<Rightarrow> 4 | Legal_Liquidate \<Rightarrow> 5),
     context_chain = 31337,
     context_token = 8319,
     context_standard_version = 1,
     context_actor = 9,
     context_subject = 1,
     context_destination = witness_destination k,
     context_amount = witness_amount k,
     context_case = 500 + (case k of
        Legal_Freeze \<Rightarrow> 0 | Legal_Seize \<Rightarrow> 1
      | Legal_Confiscate \<Rightarrow> 2 | Legal_Restrict \<Rightarrow> 3
      | Legal_Recover \<Rightarrow> 4 | Legal_Liquidate \<Rightarrow> 5),
     context_external_commitment = 9001,
     context_proceeds_reference = 9002,
     context_nonce = 100 + (case k of
        Legal_Freeze \<Rightarrow> 0 | Legal_Seize \<Rightarrow> 1
      | Legal_Confiscate \<Rightarrow> 2 | Legal_Restrict \<Rightarrow> 3
      | Legal_Recover \<Rightarrow> 4 | Legal_Liquidate \<Rightarrow> 5),
     context_epoch = 1,
     context_authority_epoch = 7,
     context_policy_code = 70001,
     context_policy_schema = 2,
     context_policy_config = 70002,
     context_provenance_commitment = 70003,
     context_valid_after = 10,
     context_deadline = 1000,
     context_current_time = 100,
     context_pre_observation_commitment = witness_pre_observation k,
     context_post_observation_commitment = witness_post_observation k,
     context_module_ready = True,
     context_entitlement_attested = True,
     context_settlement_attested = True,
     context_settlement_capability = True\<rparr>"

definition witness_authorization ::
  "legal_action_kind \<Rightarrow> trust_authorization"
where
  "witness_authorization k =
    \<lparr>authorization_operation = RCP_Operation k,
     authorization_chain = context_chain (witness_context k),
     authorization_token = context_token (witness_context k),
     authorization_standard_version =
       context_standard_version (witness_context k),
     authorization_subject = context_subject (witness_context k),
     authorization_destination = context_destination (witness_context k),
     authorization_amount = context_amount (witness_context k),
     authorization_case = context_case (witness_context k),
     authorization_external_commitment =
       context_external_commitment (witness_context k),
     authorization_proceeds_reference =
       context_proceeds_reference (witness_context k),
     authorization_issuer = 9,
     authorization_delegate = None,
     authorization_nonce = context_nonce (witness_context k),
     authorization_epoch = 1,
     authorization_authority_epoch =
       context_authority_epoch (witness_context k),
     authorization_policy_code = context_policy_code (witness_context k),
     authorization_policy_schema =
       context_policy_schema (witness_context k),
     authorization_policy_config =
       context_policy_config (witness_context k),
     authorization_provenance_commitment =
       context_provenance_commitment (witness_context k),
     authorization_valid_after = context_valid_after (witness_context k),
     authorization_deadline = context_deadline (witness_context k),
     authorization_pre_observation_commitment =
       context_pre_observation_commitment (witness_context k),
     authorization_post_observation_commitment =
       context_post_observation_commitment (witness_context k),
     authorization_lifecycle = Authorization_Created\<rparr>"

definition witness_seed_state :: "legal_action_kind \<Rightarrow> trust_state" where
  "witness_seed_state k =
    \<lparr>trust_modes =
       (\<lambda>subject. if subject = 1 then witness_initial_mode k else ACTIVE),
     trust_balances = (\<lambda>account. if account = 1 then 100 else 0),
     trust_frozen_tokens = (\<lambda>_. 0),
     trust_custody =
       (\<lambda>subject.
          if subject = 1 \<and> witness_initial_mode k = SEIZED
          then Some 9 else None),
     trust_case_registry =
       (\<lambda>subject.
          if subject = 1 \<and> witness_initial_mode k = SEIZED
          then Some (context_case (witness_context k)) else None),
     trust_encumbered_amount =
       (\<lambda>subject.
          if subject = 1 \<and> witness_initial_mode k = SEIZED
          then 10 else 0),
     trust_declared_prior_holder =
       (\<lambda>subject.
          if subject = 1 \<and> witness_initial_mode k = SEIZED
          then Some 1 else None),
     trust_settlement_commitment = (\<lambda>_. None),
     trust_proceeds_reference = (\<lambda>_. None),
     trust_entitlement_commitment = (\<lambda>_. None),
     trust_external_settlement_status = (\<lambda>_. None),
     trust_cases = (\<lambda>_. None),
     trust_receipt_registry = (\<lambda>_. None),
     trust_total_supply = 100,
     trust_allowances = (\<lambda>_ _. 0),
     trust_policy_epoch = 1,
     trust_chain = 31337,
     trust_token = 8319,
     trust_standard_version = 1,
     trust_authority_epoch = 7,
     trust_policy_code = 70001,
     trust_policy_schema = 2,
     trust_policy_config = 70002,
     trust_governance_authority = 0,
     trust_regulatory_authorities = {9},
     trust_last_policy_change = None,
     trust_authorizations = (\<lambda>_. None),
     trust_consumed_nonces = {},
     trust_last_receipt = None,
     trust_last_governance_receipt = None,
     trust_auxiliary = (\<lambda>index. 10000 + index)\<rparr>"

definition witness_authorization_trace ::
  "legal_action_kind \<Rightarrow> authorization_command list"
where
  "witness_authorization_trace k =
    [Create_Authorization
       (context_authorization_id (witness_context k))
       9
       (witness_authorization k),
     Approve_Authorization
       (context_authorization_id (witness_context k)) 9]"

definition witness_prepared_state :: "legal_action_kind \<Rightarrow> trust_state" where
  "witness_prepared_state k =
    (witness_seed_state k)\<lparr>
      trust_authorizations :=
        (trust_authorizations (witness_seed_state k))
          (context_authorization_id (witness_context k) :=
            Some ((witness_authorization k)
              \<lparr>authorization_lifecycle := Authorization_Approved\<rparr>))\<rparr>"

definition witness_entrypoint :: "legal_action_kind \<Rightarrow> trust_entrypoint" where
  "witness_entrypoint k = RCP_Entrypoint k (witness_context k)"

definition all_legal_action_kinds :: "legal_action_kind list" where
  "all_legal_action_kinds =
    [Legal_Freeze, Legal_Seize, Legal_Confiscate, Legal_Restrict,
     Legal_Recover, Legal_Liquidate]"

lemma all_legal_action_kinds_are_listed:
  "k \<in> set all_legal_action_kinds"
  by (cases k) (simp_all add: all_legal_action_kinds_def)

definition witness_precheck_property ::
  "legal_action_kind \<Rightarrow> bool"
where
  "witness_precheck_property k \<longleftrightarrow>
    canonical_precheck (witness_prepared_state k)
      \<lparr>request_operation = RCP_Operation k,
       request_context = witness_context k\<rparr> =
    Canonical_Precheck_Pass
      ((witness_authorization k)
        \<lparr>authorization_lifecycle := Authorization_Approved\<rparr>)"

lemma witness_precheck_freeze:
  "witness_precheck_property Legal_Freeze"
  by (simp add: witness_precheck_property_def canonical_precheck_def
      witness_prepared_state_def witness_seed_state_def witness_context_def
      witness_authorization_def authority_matches_def
      authorization_binding_matches_def authorization_payload_matches_def
      current_case_matches_def transfer_shape_valid_def Let_def)

lemma witness_precheck_seize:
  "witness_precheck_property Legal_Seize"
  by (simp add: witness_precheck_property_def canonical_precheck_def
      witness_prepared_state_def witness_seed_state_def witness_context_def
      witness_authorization_def authority_matches_def
      authorization_binding_matches_def authorization_payload_matches_def
      current_case_matches_def transfer_shape_valid_def Let_def)

lemma witness_precheck_confiscate:
  "witness_precheck_property Legal_Confiscate"
  by (simp add: witness_precheck_property_def canonical_precheck_def
      witness_prepared_state_def witness_seed_state_def witness_context_def
      witness_authorization_def authority_matches_def
      authorization_binding_matches_def authorization_payload_matches_def
      current_case_matches_def transfer_shape_valid_def Let_def)

lemma witness_precheck_restrict:
  "witness_precheck_property Legal_Restrict"
  by (simp add: witness_precheck_property_def canonical_precheck_def
      witness_prepared_state_def witness_seed_state_def witness_context_def
      witness_authorization_def authority_matches_def
      authorization_binding_matches_def authorization_payload_matches_def
      current_case_matches_def transfer_shape_valid_def Let_def)

lemma witness_precheck_recover:
  "witness_precheck_property Legal_Recover"
  by (simp add: witness_precheck_property_def canonical_precheck_def
      witness_prepared_state_def witness_seed_state_def witness_context_def
      witness_authorization_def authority_matches_def
      authorization_binding_matches_def authorization_payload_matches_def
      current_case_matches_def transfer_shape_valid_def Let_def)

lemma witness_precheck_liquidate:
  "witness_precheck_property Legal_Liquidate"
  by (simp add: witness_precheck_property_def canonical_precheck_def
      witness_prepared_state_def witness_seed_state_def witness_context_def
      witness_authorization_def authority_matches_def
      authorization_binding_matches_def authorization_payload_matches_def
      current_case_matches_def transfer_shape_valid_def Let_def)

lemma witness_canonical_precheck_table:
  "list_all witness_precheck_property all_legal_action_kinds"
  using witness_precheck_freeze witness_precheck_seize
    witness_precheck_confiscate witness_precheck_restrict
    witness_precheck_recover witness_precheck_liquidate
  by (simp add: all_legal_action_kinds_def)

lemma witness_canonical_precheck_passes:
  "canonical_precheck (witness_prepared_state k)
      \<lparr>request_operation = RCP_Operation k,
       request_context = witness_context k\<rparr> =
    Canonical_Precheck_Pass
      ((witness_authorization k)
        \<lparr>authorization_lifecycle := Authorization_Approved\<rparr>)"
  using witness_canonical_precheck_table
    all_legal_action_kinds_are_listed[of k]
  unfolding witness_precheck_property_def
  by (simp add: list_all_iff)

lemma witness_recover_denied_precheck:
  "canonical_precheck (witness_prepared_state Legal_Recover)
      \<lparr>request_operation = RCP_Operation Legal_Recover,
       request_context =
         (witness_context Legal_Recover)
           \<lparr>context_entitlement_attested := False\<rparr>\<rparr> =
    Canonical_Precheck_Pass
      ((witness_authorization Legal_Recover)
        \<lparr>authorization_lifecycle := Authorization_Approved\<rparr>)"
  by (simp add: canonical_precheck_def witness_prepared_state_def
      witness_seed_state_def witness_context_def witness_authorization_def
      authority_matches_def authorization_binding_matches_def
      authorization_payload_matches_def current_case_matches_def
      transfer_shape_valid_def Let_def)

lemma witness_liquidate_denied_precheck:
  "canonical_precheck (witness_prepared_state Legal_Liquidate)
      \<lparr>request_operation = RCP_Operation Legal_Liquidate,
       request_context =
         (witness_context Legal_Liquidate)
           \<lparr>context_settlement_attested := False\<rparr>\<rparr> =
    Canonical_Precheck_Pass
      ((witness_authorization Legal_Liquidate)
        \<lparr>authorization_lifecycle := Authorization_Approved\<rparr>)"
  by (simp add: canonical_precheck_def witness_prepared_state_def
      witness_seed_state_def witness_context_def witness_authorization_def
      authority_matches_def authorization_binding_matches_def
      authorization_payload_matches_def current_case_matches_def
      transfer_shape_valid_def Let_def)

lemma witness_liquidate_unsupported_precheck:
  "canonical_precheck (witness_prepared_state Legal_Liquidate)
      \<lparr>request_operation = RCP_Operation Legal_Liquidate,
       request_context =
         (witness_context Legal_Liquidate)
           \<lparr>context_settlement_capability := False\<rparr>\<rparr> =
    Canonical_Precheck_Pass
      ((witness_authorization Legal_Liquidate)
        \<lparr>authorization_lifecycle := Authorization_Approved\<rparr>)"
  by (simp add: canonical_precheck_def witness_prepared_state_def
      witness_seed_state_def witness_context_def witness_authorization_def
      authority_matches_def authorization_binding_matches_def
      authorization_payload_matches_def current_case_matches_def
      transfer_shape_valid_def Let_def)

lemma witness_authorization_trace_reaches_approved_state:
  "trust_authorizations (witness_prepared_state k)
      (context_authorization_id (witness_context k)) =
    Some ((witness_authorization k)
      \<lparr>authorization_lifecycle := Authorization_Approved\<rparr>)"
  by (simp add: witness_prepared_state_def)

theorem witness_prepared_state_is_reached_by_authorization_trace:
  "fst (run_authorization_commands
      (witness_authorization_trace k) (witness_seed_state k)) =
    witness_prepared_state k"
  by (cases k)
     (simp_all add: witness_prepared_state_def witness_authorization_trace_def
       witness_seed_state_def witness_authorization_def witness_context_def
       execute_authorization_command_def Let_def)

definition untrusted_self_issued_authorization ::
  "legal_action_kind \<Rightarrow> trust_authorization"
where
  "untrusted_self_issued_authorization k =
    (witness_authorization k)\<lparr>authorization_issuer := 88\<rparr>"

theorem untrusted_self_issued_authorization_is_fail_closed:
  "execute_authorization_command (witness_seed_state k)
     (Create_Authorization
       (context_authorization_id (witness_context k))
       88 (untrusted_self_issued_authorization k)) =
    (witness_seed_state k, Authorization_Command_Rejected)"
  by (cases k)
     (simp_all add: untrusted_self_issued_authorization_def
       witness_seed_state_def witness_authorization_def witness_context_def
       execute_authorization_command_def Let_def)

section \<open>Six-by-Three Nonvacuity Matrix\<close>

lemma witness_freeze_is_applied:
  "snd (execute_entrypoint (witness_prepared_state Legal_Freeze)
      (witness_entrypoint Legal_Freeze)) = Trust_Applied"
  using witness_canonical_precheck_passes[of Legal_Freeze]
  by (simp add: witness_entrypoint_def execute_entrypoint_def
      normalize_entrypoint_def execute_canonical_def
      witness_prepared_state_def witness_seed_state_def witness_context_def
      operation_well_formed_def state_observation_commitment_def
      expected_post_observation_commitment_def observation_commitment_def
      current_case_matches_def Let_def)

lemma witness_seize_is_applied:
  "snd (execute_entrypoint (witness_prepared_state Legal_Seize)
      (witness_entrypoint Legal_Seize)) = Trust_Applied"
  using witness_canonical_precheck_passes[of Legal_Seize]
  by (simp add: witness_entrypoint_def execute_entrypoint_def
      normalize_entrypoint_def execute_canonical_def
      witness_prepared_state_def witness_seed_state_def witness_context_def
      operation_well_formed_def state_observation_commitment_def
      expected_post_observation_commitment_def observation_commitment_def
      current_case_matches_def Let_def)

lemma witness_confiscate_is_applied:
  "snd (execute_entrypoint (witness_prepared_state Legal_Confiscate)
      (witness_entrypoint Legal_Confiscate)) = Trust_Applied"
  using witness_canonical_precheck_passes[of Legal_Confiscate]
  by (simp add: witness_entrypoint_def execute_entrypoint_def
      normalize_entrypoint_def execute_canonical_def
      witness_prepared_state_def witness_seed_state_def witness_context_def
      operation_well_formed_def state_observation_commitment_def
      expected_post_observation_commitment_def observation_commitment_def
      current_case_matches_def Let_def)

lemma witness_restrict_is_applied:
  "snd (execute_entrypoint (witness_prepared_state Legal_Restrict)
      (witness_entrypoint Legal_Restrict)) = Trust_Applied"
  using witness_canonical_precheck_passes[of Legal_Restrict]
  by (simp add: witness_entrypoint_def execute_entrypoint_def
      normalize_entrypoint_def execute_canonical_def
      witness_prepared_state_def witness_seed_state_def witness_context_def
      operation_well_formed_def state_observation_commitment_def
      expected_post_observation_commitment_def observation_commitment_def
      current_case_matches_def Let_def)

lemma witness_recover_is_applied:
  "snd (execute_entrypoint (witness_prepared_state Legal_Recover)
      (witness_entrypoint Legal_Recover)) = Trust_Applied"
  using witness_canonical_precheck_passes[of Legal_Recover]
  by (simp add: witness_entrypoint_def execute_entrypoint_def
      normalize_entrypoint_def execute_canonical_def
      witness_prepared_state_def witness_seed_state_def witness_context_def
      operation_well_formed_def state_observation_commitment_def
      expected_post_observation_commitment_def observation_commitment_def
      current_case_matches_def Let_def)

lemma witness_liquidate_is_applied:
  "snd (execute_entrypoint (witness_prepared_state Legal_Liquidate)
      (witness_entrypoint Legal_Liquidate)) = Trust_Applied"
  using witness_canonical_precheck_passes[of Legal_Liquidate]
  by (simp add: witness_entrypoint_def execute_entrypoint_def
      normalize_entrypoint_def execute_canonical_def
      witness_prepared_state_def witness_seed_state_def witness_context_def
      operation_well_formed_def state_observation_commitment_def
      expected_post_observation_commitment_def observation_commitment_def
      current_case_matches_def Let_def)

theorem all_six_actions_have_reachable_applied_witnesses:
  "snd (execute_entrypoint (witness_prepared_state Legal_Freeze)
      (witness_entrypoint Legal_Freeze)) = Trust_Applied \<and>
   snd (execute_entrypoint (witness_prepared_state Legal_Seize)
      (witness_entrypoint Legal_Seize)) = Trust_Applied \<and>
   snd (execute_entrypoint (witness_prepared_state Legal_Confiscate)
      (witness_entrypoint Legal_Confiscate)) = Trust_Applied \<and>
   snd (execute_entrypoint (witness_prepared_state Legal_Restrict)
      (witness_entrypoint Legal_Restrict)) = Trust_Applied \<and>
   snd (execute_entrypoint (witness_prepared_state Legal_Recover)
      (witness_entrypoint Legal_Recover)) = Trust_Applied \<and>
   snd (execute_entrypoint (witness_prepared_state Legal_Liquidate)
      (witness_entrypoint Legal_Liquidate)) = Trust_Applied"
  using witness_freeze_is_applied witness_seize_is_applied
    witness_confiscate_is_applied witness_restrict_is_applied
    witness_recover_is_applied witness_liquidate_is_applied
  by blast

lemma witness_canonical_outcome_is_applied:
  "snd (execute_canonical (witness_prepared_state k)
      \<lparr>request_operation = RCP_Operation k,
       request_context = witness_context k\<rparr>) = Trust_Applied"
  using all_six_actions_have_reachable_applied_witnesses
  by (cases k)
     (simp_all add: witness_entrypoint_def execute_entrypoint_def
       normalize_entrypoint_def)

definition unauthorized_witness_entrypoint ::
  "legal_action_kind \<Rightarrow> trust_entrypoint"
where
  "unauthorized_witness_entrypoint k =
    RCP_Entrypoint k ((witness_context k)\<lparr>context_actor := 88\<rparr>)"

lemma unauthorized_witness_precheck_stops:
  "canonical_precheck (witness_prepared_state k)
      \<lparr>request_operation = RCP_Operation k,
       request_context =
         (witness_context k)\<lparr>context_actor := 88\<rparr>\<rparr> =
    Canonical_Precheck_Stop
      (Trust_Rejected Actor_Not_Authorized)"
  by (cases k)
     (simp_all add: canonical_precheck_def witness_prepared_state_def
       witness_seed_state_def witness_context_def witness_authorization_def
       authority_matches_def authorization_binding_matches_def
       authorization_payload_matches_def current_case_matches_def
       transfer_shape_valid_def Let_def)

theorem all_six_actions_have_reachable_denial_witnesses:
  "\<forall>k. snd (execute_entrypoint (witness_prepared_state k)
      (unauthorized_witness_entrypoint k)) =
    Trust_Rejected Actor_Not_Authorized"
proof
  fix k
  show
    "snd (execute_entrypoint (witness_prepared_state k)
      (unauthorized_witness_entrypoint k)) =
      Trust_Rejected Actor_Not_Authorized"
    using unauthorized_witness_precheck_stops[of k]
    by (simp add: unauthorized_witness_entrypoint_def
        execute_entrypoint_def normalize_entrypoint_def
        execute_canonical_def Let_def)
qed

theorem recover_negative_entitlement_is_rejected_not_operational_failure:
  "snd (execute_entrypoint (witness_prepared_state Legal_Recover)
     (RCP_Entrypoint Legal_Recover
       ((witness_context Legal_Recover)
         \<lparr>context_entitlement_attested := False\<rparr>))) =
   Trust_Rejected External_Evidence_Denied"
  using witness_recover_denied_precheck
  by (simp add: execute_entrypoint_def normalize_entrypoint_def
      execute_canonical_def witness_context_def Let_def)

theorem liquidate_negative_settlement_is_rejected_not_operational_failure:
  "snd (execute_entrypoint (witness_prepared_state Legal_Liquidate)
     (RCP_Entrypoint Legal_Liquidate
       ((witness_context Legal_Liquidate)
         \<lparr>context_settlement_attested := False\<rparr>))) =
   Trust_Rejected External_Evidence_Denied"
  using witness_liquidate_denied_precheck
  by (simp add: execute_entrypoint_def normalize_entrypoint_def
      execute_canonical_def witness_context_def Let_def)

theorem liquidate_unsupported_capability_is_rejected:
  "snd (execute_entrypoint (witness_prepared_state Legal_Liquidate)
     (RCP_Entrypoint Legal_Liquidate
       ((witness_context Legal_Liquidate)
         \<lparr>context_settlement_capability := False\<rparr>))) =
   Trust_Rejected Capability_Unsupported"
  using witness_liquidate_unsupported_precheck
  by (simp add: execute_entrypoint_def normalize_entrypoint_def
      execute_canonical_def witness_context_def Let_def)

definition unavailable_witness_entrypoint ::
  "legal_action_kind \<Rightarrow> trust_entrypoint"
where
  "unavailable_witness_entrypoint k =
    RCP_Entrypoint k
      ((witness_context k)\<lparr>context_module_ready := False\<rparr>)"

theorem all_six_actions_have_reachable_operational_failure_witnesses:
  "\<forall>k. execute_entrypoint (witness_prepared_state k)
      (unavailable_witness_entrypoint k) =
    (witness_prepared_state k,
      Trust_Operational_Failure Policy_Module_Unavailable)"
  by (rule allI; rename_tac k; case_tac k)
     (simp_all add: unavailable_witness_entrypoint_def
       execute_entrypoint_def normalize_entrypoint_def execute_canonical_def
       canonical_precheck_def Let_def)

section \<open>Reversal and Ordinary Transfer Reachability\<close>

fun reversal_index :: "reg_action \<Rightarrow> nat" where
  "reversal_index UNFREEZE = 0"
| "reversal_index UNRESTRICT = 1"
| "reversal_index RELEASE = 2"
| "reversal_index _ = 9"

fun reversal_initial_mode :: "reg_action \<Rightarrow> reg_state" where
  "reversal_initial_mode UNFREEZE = FROZEN"
| "reversal_initial_mode UNRESTRICT = RESTRICTED"
| "reversal_initial_mode RELEASE = SEIZED"
| "reversal_initial_mode _ = ACTIVE"

fun reversal_absolute_frozen_amount :: "reg_action \<Rightarrow> nat" where
  "reversal_absolute_frozen_amount UNFREEZE = 0"
| "reversal_absolute_frozen_amount UNRESTRICT = 0"
| "reversal_absolute_frozen_amount RELEASE = 10"
| "reversal_absolute_frozen_amount _ = 0"

fun reversal_pre_observation ::
  "reg_action \<Rightarrow> trust_observation"
where
  "reversal_pre_observation UNFREEZE =
     Trust_Observation FROZEN 100 10 0 (Some 600)"
| "reversal_pre_observation UNRESTRICT =
     Trust_Observation RESTRICTED 100 0 0 (Some 601)"
| "reversal_pre_observation RELEASE =
     Trust_Observation SEIZED 100 0 10 (Some 602)"
| "reversal_pre_observation _ =
     Trust_Observation ACTIVE 100 0 0 None"

fun reversal_post_observation ::
  "reg_action \<Rightarrow> trust_observation"
where
  "reversal_post_observation _ =
     Trust_Observation ACTIVE 100 0 0 None"

definition reversal_context :: "reg_action \<Rightarrow> entry_context" where
  "reversal_context action =
    (witness_context Legal_Freeze)\<lparr>
      context_authorization_id := 900 + reversal_index action,
      context_amount := reversal_absolute_frozen_amount action,
      context_case := 600 + reversal_index action,
      context_nonce := 300 + reversal_index action,
      context_pre_observation_commitment := reversal_pre_observation action,
      context_post_observation_commitment := reversal_post_observation action\<rparr>"

definition reversal_authorization ::
  "reg_action \<Rightarrow> trust_authorization"
where
  "reversal_authorization action =
    (witness_authorization Legal_Freeze)\<lparr>
      authorization_operation := Transition_Operation action,
      authorization_amount := context_amount (reversal_context action),
      authorization_case := context_case (reversal_context action),
      authorization_nonce := context_nonce (reversal_context action),
      authorization_pre_observation_commitment :=
        context_pre_observation_commitment (reversal_context action),
      authorization_post_observation_commitment :=
        context_post_observation_commitment (reversal_context action)\<rparr>"

definition reversal_seed_state :: "reg_action \<Rightarrow> trust_state" where
  "reversal_seed_state action =
    (witness_seed_state Legal_Freeze)\<lparr>
      trust_modes :=
        (trust_modes (witness_seed_state Legal_Freeze))
          (1 := reversal_initial_mode action),
      trust_frozen_tokens :=
        (trust_frozen_tokens (witness_seed_state Legal_Freeze))
          (1 := if action = UNFREEZE then 10 else 0),
      trust_custody :=
        (trust_custody (witness_seed_state Legal_Freeze))
          (1 := if action = RELEASE then Some 9 else None),
      trust_case_registry :=
        (trust_case_registry (witness_seed_state Legal_Freeze))
          (1 := Some (context_case (reversal_context action))),
      trust_encumbered_amount :=
        (trust_encumbered_amount (witness_seed_state Legal_Freeze))
          (1 := if action = RELEASE then 10 else 0),
      trust_declared_prior_holder :=
        (trust_declared_prior_holder (witness_seed_state Legal_Freeze))
          (1 := if action = RELEASE then Some 1 else None)\<rparr>"

definition reversal_prepared_state :: "reg_action \<Rightarrow> trust_state" where
  "reversal_prepared_state action =
    (reversal_seed_state action)\<lparr>
      trust_authorizations :=
        (trust_authorizations (reversal_seed_state action))
          (context_authorization_id (reversal_context action) :=
            Some ((reversal_authorization action)
              \<lparr>authorization_lifecycle := Authorization_Approved\<rparr>))\<rparr>"

theorem reversal_prepared_state_is_reached_by_authorization_trace:
  "fst (run_authorization_commands
      [Create_Authorization
         (context_authorization_id (reversal_context action))
         9
         (reversal_authorization action),
       Approve_Authorization
         (context_authorization_id (reversal_context action)) 9]
      (reversal_seed_state action)) =
    reversal_prepared_state action"
  by (cases action)
     (simp_all add: reversal_prepared_state_def reversal_seed_state_def
       reversal_context_def reversal_authorization_def witness_seed_state_def
       witness_context_def witness_authorization_def
       execute_authorization_command_def Let_def)

definition reversal_entrypoint :: "reg_action \<Rightarrow> trust_entrypoint" where
  "reversal_entrypoint action =
    Native_Entrypoint (Transition_Operation action)
      (reversal_context action)"

definition reversal_applied_state :: "reg_action \<Rightarrow> trust_state" where
  "reversal_applied_state action =
    fst (execute_entrypoint (reversal_prepared_state action)
      (reversal_entrypoint action))"

lemma reversal_unfreeze_precheck_passes:
  "canonical_precheck (reversal_prepared_state UNFREEZE)
      \<lparr>request_operation = Transition_Operation UNFREEZE,
       request_context = reversal_context UNFREEZE\<rparr> =
    Canonical_Precheck_Pass
      ((reversal_authorization UNFREEZE)
        \<lparr>authorization_lifecycle := Authorization_Approved\<rparr>)"
  by (simp add: canonical_precheck_def reversal_prepared_state_def
      reversal_seed_state_def reversal_context_def reversal_authorization_def
      witness_seed_state_def witness_context_def witness_authorization_def
      authority_matches_def authorization_binding_matches_def
      authorization_payload_matches_def current_case_matches_def
      transfer_shape_valid_def Let_def)

lemma reversal_unfreeze_is_applied:
  "snd (execute_entrypoint (reversal_prepared_state UNFREEZE)
      (reversal_entrypoint UNFREEZE)) = Trust_Applied"
  using reversal_unfreeze_precheck_passes
  by (simp add: reversal_entrypoint_def execute_entrypoint_def
      normalize_entrypoint_def execute_canonical_def
      reversal_prepared_state_def reversal_seed_state_def
      reversal_context_def reversal_authorization_def witness_seed_state_def
      witness_context_def witness_authorization_def
      operation_well_formed_def state_observation_commitment_def
      expected_post_observation_commitment_def observation_commitment_def
      current_case_matches_def Let_def)

lemma reversal_unfreeze_canonical_execution:
  "execute_canonical (reversal_prepared_state UNFREEZE)
      \<lparr>request_operation = Transition_Operation UNFREEZE,
       request_context = reversal_context UNFREEZE\<rparr> =
    (reversal_applied_state UNFREEZE, Trust_Applied)"
proof -
  have entrypoint_execution:
    "execute_entrypoint (reversal_prepared_state UNFREEZE)
        (reversal_entrypoint UNFREEZE) =
      (reversal_applied_state UNFREEZE, Trust_Applied)"
    using reversal_unfreeze_is_applied
    unfolding reversal_applied_state_def
    by (metis prod.collapse)
  show ?thesis
    using entrypoint_execution
    by (simp add: reversal_entrypoint_def execute_entrypoint_def
        normalize_entrypoint_def)
qed

lemma reversal_unfreeze_effects:
  "trust_modes (reversal_applied_state UNFREEZE) 1 = ACTIVE \<and>
   trust_frozen_tokens (reversal_applied_state UNFREEZE) 1 = 0"
proof -
  let ?req =
    "\<lparr>request_operation = Transition_Operation UNFREEZE,
      request_context = reversal_context UNFREEZE\<rparr>"
  obtain auth target where
    target:
      "contextual_operation_target (request_operation ?req)
        (trust_modes (reversal_prepared_state UNFREEZE)
          (context_subject (request_context ?req)))
        (context_amount (request_context ?req)) = Some target"
    and result:
      "reversal_applied_state UNFREEZE =
        successful_state (reversal_prepared_state UNFREEZE)
          ?req auth target"
    using execute_canonical_applied_structure[
      OF reversal_unfreeze_canonical_execution]
    by blast
  have target_active: "target = ACTIVE"
    using target
    by (simp add: reversal_prepared_state_def reversal_seed_state_def
        reversal_context_def witness_seed_state_def witness_context_def)
  show ?thesis
    using result target_active
    by (simp add: successful_state_def reversal_context_def
        witness_context_def Let_def)
qed

lemma reversal_unfreeze_has_reachable_applied_witness:
  "snd (execute_entrypoint (reversal_prepared_state UNFREEZE)
      (reversal_entrypoint UNFREEZE)) = Trust_Applied \<and>
   trust_modes (reversal_applied_state UNFREEZE) 1 = ACTIVE \<and>
   trust_frozen_tokens (reversal_applied_state UNFREEZE) 1 = 0"
  using reversal_unfreeze_is_applied reversal_unfreeze_effects
  by blast

lemma reversal_unrestrict_precheck_passes:
  "canonical_precheck (reversal_prepared_state UNRESTRICT)
      \<lparr>request_operation = Transition_Operation UNRESTRICT,
       request_context = reversal_context UNRESTRICT\<rparr> =
    Canonical_Precheck_Pass
      ((reversal_authorization UNRESTRICT)
        \<lparr>authorization_lifecycle := Authorization_Approved\<rparr>)"
  by (simp add: canonical_precheck_def reversal_prepared_state_def
      reversal_seed_state_def reversal_context_def reversal_authorization_def
      witness_seed_state_def witness_context_def witness_authorization_def
      authority_matches_def authorization_binding_matches_def
      authorization_payload_matches_def current_case_matches_def
      transfer_shape_valid_def Let_def)

lemma reversal_unrestrict_is_applied:
  "snd (execute_entrypoint (reversal_prepared_state UNRESTRICT)
      (reversal_entrypoint UNRESTRICT)) = Trust_Applied"
  using reversal_unrestrict_precheck_passes
  by (simp add: reversal_entrypoint_def execute_entrypoint_def
      normalize_entrypoint_def execute_canonical_def
      reversal_prepared_state_def reversal_seed_state_def
      reversal_context_def reversal_authorization_def witness_seed_state_def
      witness_context_def witness_authorization_def
      operation_well_formed_def state_observation_commitment_def
      expected_post_observation_commitment_def observation_commitment_def
      current_case_matches_def Let_def)

lemma reversal_unrestrict_canonical_execution:
  "execute_canonical (reversal_prepared_state UNRESTRICT)
      \<lparr>request_operation = Transition_Operation UNRESTRICT,
       request_context = reversal_context UNRESTRICT\<rparr> =
    (reversal_applied_state UNRESTRICT, Trust_Applied)"
proof -
  have entrypoint_execution:
    "execute_entrypoint (reversal_prepared_state UNRESTRICT)
        (reversal_entrypoint UNRESTRICT) =
      (reversal_applied_state UNRESTRICT, Trust_Applied)"
    using reversal_unrestrict_is_applied
    unfolding reversal_applied_state_def
    by (metis prod.collapse)
  show ?thesis
    using entrypoint_execution
    by (simp add: reversal_entrypoint_def execute_entrypoint_def
        normalize_entrypoint_def)
qed

lemma reversal_unrestrict_effects:
  "trust_modes (reversal_applied_state UNRESTRICT) 1 = ACTIVE"
proof -
  let ?req =
    "\<lparr>request_operation = Transition_Operation UNRESTRICT,
      request_context = reversal_context UNRESTRICT\<rparr>"
  obtain auth target where
    target:
      "contextual_operation_target (request_operation ?req)
        (trust_modes (reversal_prepared_state UNRESTRICT)
          (context_subject (request_context ?req)))
        (context_amount (request_context ?req)) = Some target"
    and result:
      "reversal_applied_state UNRESTRICT =
        successful_state (reversal_prepared_state UNRESTRICT)
          ?req auth target"
    using execute_canonical_applied_structure[
      OF reversal_unrestrict_canonical_execution]
    by blast
  have target_active: "target = ACTIVE"
    using target
    by (simp add: reversal_prepared_state_def reversal_seed_state_def
        reversal_context_def witness_seed_state_def witness_context_def)
  show ?thesis
    using result target_active
    by (simp add: successful_state_def reversal_context_def
        witness_context_def Let_def)
qed

lemma reversal_unrestrict_has_reachable_applied_witness:
  "snd (execute_entrypoint (reversal_prepared_state UNRESTRICT)
      (reversal_entrypoint UNRESTRICT)) = Trust_Applied \<and>
   trust_modes (reversal_applied_state UNRESTRICT) 1 = ACTIVE"
  using reversal_unrestrict_is_applied reversal_unrestrict_effects
  by blast

lemma reversal_release_precheck_passes:
  "canonical_precheck (reversal_prepared_state RELEASE)
      \<lparr>request_operation = Transition_Operation RELEASE,
       request_context = reversal_context RELEASE\<rparr> =
    Canonical_Precheck_Pass
      ((reversal_authorization RELEASE)
        \<lparr>authorization_lifecycle := Authorization_Approved\<rparr>)"
  by (simp add: canonical_precheck_def reversal_prepared_state_def
      reversal_seed_state_def reversal_context_def reversal_authorization_def
      witness_seed_state_def witness_context_def witness_authorization_def
      authority_matches_def authorization_binding_matches_def
      authorization_payload_matches_def current_case_matches_def
      transfer_shape_valid_def Let_def)

lemma reversal_release_is_applied:
  "snd (execute_entrypoint (reversal_prepared_state RELEASE)
      (reversal_entrypoint RELEASE)) = Trust_Applied"
  using reversal_release_precheck_passes
  by (simp add: reversal_entrypoint_def execute_entrypoint_def
      normalize_entrypoint_def execute_canonical_def
      reversal_prepared_state_def reversal_seed_state_def
      reversal_context_def reversal_authorization_def witness_seed_state_def
      witness_context_def witness_authorization_def
      operation_well_formed_def state_observation_commitment_def
      expected_post_observation_commitment_def observation_commitment_def
      current_case_matches_def Let_def)

lemma reversal_release_canonical_execution:
  "execute_canonical (reversal_prepared_state RELEASE)
      \<lparr>request_operation = Transition_Operation RELEASE,
       request_context = reversal_context RELEASE\<rparr> =
    (reversal_applied_state RELEASE, Trust_Applied)"
proof -
  have entrypoint_execution:
    "execute_entrypoint (reversal_prepared_state RELEASE)
        (reversal_entrypoint RELEASE) =
      (reversal_applied_state RELEASE, Trust_Applied)"
    using reversal_release_is_applied
    unfolding reversal_applied_state_def
    by (metis prod.collapse)
  show ?thesis
    using entrypoint_execution
    by (simp add: reversal_entrypoint_def execute_entrypoint_def
        normalize_entrypoint_def)
qed

lemma reversal_release_effects:
  "trust_modes (reversal_applied_state RELEASE) 1 = ACTIVE \<and>
   trust_custody (reversal_applied_state RELEASE) 1 = None \<and>
   trust_encumbered_amount (reversal_applied_state RELEASE) 1 = 0 \<and>
   trust_declared_prior_holder (reversal_applied_state RELEASE) 1 = None"
proof -
  let ?req =
    "\<lparr>request_operation = Transition_Operation RELEASE,
      request_context = reversal_context RELEASE\<rparr>"
  obtain auth target where
    target:
      "contextual_operation_target (request_operation ?req)
        (trust_modes (reversal_prepared_state RELEASE)
          (context_subject (request_context ?req)))
        (context_amount (request_context ?req)) = Some target"
    and result:
      "reversal_applied_state RELEASE =
        successful_state (reversal_prepared_state RELEASE)
          ?req auth target"
    using execute_canonical_applied_structure[
      OF reversal_release_canonical_execution]
    by blast
  have target_active: "target = ACTIVE"
    using target
    by (simp add: reversal_prepared_state_def reversal_seed_state_def
        reversal_context_def witness_seed_state_def witness_context_def)
  show ?thesis
    using result target_active
    by (simp add: successful_state_def reversal_context_def
        witness_context_def Let_def)
qed

lemma reversal_release_has_reachable_applied_witness:
  "snd (execute_entrypoint (reversal_prepared_state RELEASE)
      (reversal_entrypoint RELEASE)) = Trust_Applied \<and>
   trust_modes (reversal_applied_state RELEASE) 1 = ACTIVE \<and>
   trust_custody (reversal_applied_state RELEASE) 1 = None \<and>
   trust_encumbered_amount (reversal_applied_state RELEASE) 1 = 0 \<and>
   trust_declared_prior_holder (reversal_applied_state RELEASE) 1 = None"
  using reversal_release_is_applied reversal_release_effects
  by blast

theorem all_three_reversal_transitions_have_reachable_applied_witnesses:
  "snd (execute_entrypoint (reversal_prepared_state UNFREEZE)
      (reversal_entrypoint UNFREEZE)) = Trust_Applied \<and>
   trust_modes (reversal_applied_state UNFREEZE) 1 = ACTIVE \<and>
   trust_frozen_tokens (reversal_applied_state UNFREEZE) 1 = 0 \<and>
   snd (execute_entrypoint (reversal_prepared_state UNRESTRICT)
      (reversal_entrypoint UNRESTRICT)) = Trust_Applied \<and>
   trust_modes (reversal_applied_state UNRESTRICT) 1 = ACTIVE \<and>
   snd (execute_entrypoint (reversal_prepared_state RELEASE)
      (reversal_entrypoint RELEASE)) = Trust_Applied \<and>
   trust_modes (reversal_applied_state RELEASE) 1 = ACTIVE \<and>
   trust_custody (reversal_applied_state RELEASE) 1 = None \<and>
   trust_encumbered_amount (reversal_applied_state RELEASE) 1 = 0 \<and>
   trust_declared_prior_holder (reversal_applied_state RELEASE) 1 = None"
  using reversal_unfreeze_has_reachable_applied_witness
    reversal_unrestrict_has_reachable_applied_witness
    reversal_release_has_reachable_applied_witness
  by blast

definition ordinary_transfer_witness :: ordinary_transfer_command where
  "ordinary_transfer_witness =
    \<lparr>ordinary_source = 1,
     ordinary_destination = 2,
     ordinary_amount = 10,
     ordinary_baseline_clear = True,
     ordinary_restriction_clear = True,
     ordinary_destination_clear = True\<rparr>"

definition blocked_ordinary_transfer_witness :: ordinary_transfer_command where
  "blocked_ordinary_transfer_witness =
    ordinary_transfer_witness\<lparr>ordinary_baseline_clear := False\<rparr>"

definition ordinary_transfer_applied_state :: trust_state where
  "ordinary_transfer_applied_state =
    fst (execute_ordinary_transfer (witness_seed_state Legal_Freeze)
      ordinary_transfer_witness)"

theorem ordinary_transfer_has_reachable_success_and_denial_witnesses:
  "snd (execute_ordinary_transfer (witness_seed_state Legal_Freeze)
      ordinary_transfer_witness) = Trust_Applied \<and>
   trust_balances ordinary_transfer_applied_state 1 = 90 \<and>
   trust_balances ordinary_transfer_applied_state 2 = 10 \<and>
   trust_modes ordinary_transfer_applied_state =
     trust_modes (witness_seed_state Legal_Freeze) \<and>
   trust_last_receipt ordinary_transfer_applied_state = None \<and>
   execute_ordinary_transfer (witness_seed_state Legal_Freeze)
      blocked_ordinary_transfer_witness =
     (witness_seed_state Legal_Freeze,
      Trust_Rejected Invalid_State_Transition)"
  by (simp add: ordinary_transfer_applied_state_def
      ordinary_transfer_witness_def blocked_ordinary_transfer_witness_def
      witness_seed_state_def execute_ordinary_transfer_def
      ordinary_transfer_allowed_def Let_def)

definition partially_frozen_ordinary_state :: trust_state where
  "partially_frozen_ordinary_state =
    (witness_seed_state Legal_Freeze)\<lparr>
      trust_modes :=
        (trust_modes (witness_seed_state Legal_Freeze))(1 := FROZEN),
      trust_frozen_tokens :=
        (trust_frozen_tokens (witness_seed_state Legal_Freeze))(1 := 30)\<rparr>"

definition partially_seized_ordinary_state :: trust_state where
  "partially_seized_ordinary_state =
    (witness_seed_state Legal_Freeze)\<lparr>
      trust_modes :=
        (trust_modes (witness_seed_state Legal_Freeze))(1 := SEIZED),
      trust_custody :=
        (trust_custody (witness_seed_state Legal_Freeze))(1 := Some 9),
      trust_encumbered_amount :=
        (trust_encumbered_amount (witness_seed_state Legal_Freeze))(1 := 40),
      trust_declared_prior_holder :=
        (trust_declared_prior_holder
          (witness_seed_state Legal_Freeze))(1 := Some 1)\<rparr>"

lemma partially_frozen_transfer_at_available_balance_applies:
  "snd (execute_ordinary_transfer partially_frozen_ordinary_state
      (ordinary_transfer_witness\<lparr>ordinary_amount := 70\<rparr>)) =
      Trust_Applied \<and>
   trust_balances
      (fst (execute_ordinary_transfer partially_frozen_ordinary_state
        (ordinary_transfer_witness\<lparr>ordinary_amount := 70\<rparr>))) 1 =
      30"
  by (simp add: execute_ordinary_transfer_def
      partially_frozen_ordinary_state_def ordinary_transfer_witness_def
      witness_seed_state_def Let_def)

lemma partially_frozen_transfer_above_available_balance_is_rejected:
  "snd (execute_ordinary_transfer partially_frozen_ordinary_state
      (ordinary_transfer_witness\<lparr>ordinary_amount := 71\<rparr>)) =
      Trust_Rejected Insufficient_Balance"
  by (simp add: execute_ordinary_transfer_def
      partially_frozen_ordinary_state_def ordinary_transfer_witness_def
      witness_seed_state_def Let_def)

lemma partially_seized_transfer_at_available_balance_applies:
  "snd (execute_ordinary_transfer partially_seized_ordinary_state
      (ordinary_transfer_witness\<lparr>ordinary_amount := 60\<rparr>)) =
      Trust_Applied"
  by (simp add: execute_ordinary_transfer_def
      partially_seized_ordinary_state_def ordinary_transfer_witness_def
      witness_seed_state_def Let_def)

lemma uncleared_destination_transfer_is_rejected:
  "snd (execute_ordinary_transfer (witness_seed_state Legal_Freeze)
      (ordinary_transfer_witness\<lparr>ordinary_destination_clear := False\<rparr>)) =
      Trust_Rejected Invalid_State_Transition"
  by (simp add: execute_ordinary_transfer_def
      ordinary_transfer_witness_def witness_seed_state_def Let_def)

theorem ordinary_transfer_uses_unencumbered_available_balance:
  "snd (execute_ordinary_transfer partially_frozen_ordinary_state
      (ordinary_transfer_witness\<lparr>ordinary_amount := 70\<rparr>)) =
      Trust_Applied \<and>
   trust_balances
      (fst (execute_ordinary_transfer partially_frozen_ordinary_state
        (ordinary_transfer_witness\<lparr>ordinary_amount := 70\<rparr>))) 1 =
      30 \<and>
   snd (execute_ordinary_transfer partially_frozen_ordinary_state
      (ordinary_transfer_witness\<lparr>ordinary_amount := 71\<rparr>)) =
      Trust_Rejected Insufficient_Balance \<and>
   snd (execute_ordinary_transfer partially_seized_ordinary_state
      (ordinary_transfer_witness\<lparr>ordinary_amount := 60\<rparr>)) =
      Trust_Applied \<and>
   snd (execute_ordinary_transfer (witness_seed_state Legal_Freeze)
      (ordinary_transfer_witness\<lparr>ordinary_destination_clear := False\<rparr>)) =
      Trust_Rejected Invalid_State_Transition"
  using partially_frozen_transfer_at_available_balance_applies
    partially_frozen_transfer_above_available_balance_is_rejected
    partially_seized_transfer_at_available_balance_applies
    uncleared_destination_transfer_is_rejected
  by blast

section \<open>Alternate Overlays and Compatibility Delta Witnesses\<close>

definition alternate_prepared_state ::
  "legal_action_kind \<Rightarrow> reg_state \<Rightarrow> nat \<Rightarrow> nat \<Rightarrow>
   trust_observation \<Rightarrow> trust_state"
where
  "alternate_prepared_state k mode frozen encumbered pre_observation =
    (let st = witness_prepared_state k;
         ctx = witness_context k;
         aid = context_authorization_id ctx;
         auth =
           (witness_authorization k)\<lparr>
             authorization_pre_observation_commitment := pre_observation,
             authorization_lifecycle := Authorization_Approved\<rparr>
     in st\<lparr>
       trust_modes := (trust_modes st)(1 := mode),
       trust_frozen_tokens := (trust_frozen_tokens st)(1 := frozen),
       trust_custody :=
         (trust_custody st)
           (1 := if mode = SEIZED then Some 9 else None),
       trust_case_registry :=
         (trust_case_registry st)(1 := Some (context_case ctx)),
       trust_encumbered_amount :=
         (trust_encumbered_amount st)(1 := encumbered),
       trust_declared_prior_holder :=
         (trust_declared_prior_holder st)
           (1 := if mode = SEIZED then Some 1 else None),
       trust_authorizations :=
         (trust_authorizations st)(aid := Some auth)\<rparr>)"

definition alternate_entrypoint ::
  "legal_action_kind \<Rightarrow> trust_observation \<Rightarrow> trust_entrypoint"
where
  "alternate_entrypoint k pre_observation =
    RCP_Entrypoint k
      ((witness_context k)\<lparr>
        context_pre_observation_commitment := pre_observation\<rparr>)"

lemma alternate_freeze_from_restricted_is_applied:
  "snd (execute_entrypoint
      (alternate_prepared_state Legal_Freeze RESTRICTED 0 0
        (Trust_Observation RESTRICTED 100 0 0 (Some 500)))
      (alternate_entrypoint Legal_Freeze
        (Trust_Observation RESTRICTED 100 0 0 (Some 500)))) =
      Trust_Applied"
  by (simp add: execute_entrypoint_def normalize_entrypoint_def
      execute_canonical_def canonical_precheck_def
      alternate_prepared_state_def alternate_entrypoint_def
      witness_prepared_state_def witness_seed_state_def witness_context_def
      witness_authorization_def authority_matches_def
      authorization_binding_matches_def authorization_payload_matches_def
      current_case_matches_def transfer_shape_valid_def
      operation_well_formed_def state_observation_commitment_def
      expected_post_observation_commitment_def observation_commitment_def
      Let_def)

lemma alternate_seize_from_frozen_is_applied:
  "snd (execute_entrypoint
      (alternate_prepared_state Legal_Seize FROZEN 10 0
        (Trust_Observation FROZEN 100 10 0 (Some 501)))
      (alternate_entrypoint Legal_Seize
        (Trust_Observation FROZEN 100 10 0 (Some 501)))) =
      Trust_Applied"
  by (simp add: execute_entrypoint_def normalize_entrypoint_def
      execute_canonical_def canonical_precheck_def
      alternate_prepared_state_def alternate_entrypoint_def
      witness_prepared_state_def witness_seed_state_def witness_context_def
      witness_authorization_def authority_matches_def
      authorization_binding_matches_def authorization_payload_matches_def
      current_case_matches_def transfer_shape_valid_def
      operation_well_formed_def state_observation_commitment_def
      expected_post_observation_commitment_def observation_commitment_def
      Let_def)

lemma alternate_confiscate_from_frozen_is_applied:
  "snd (execute_entrypoint
      (alternate_prepared_state Legal_Confiscate FROZEN 10 0
        (Trust_Observation FROZEN 100 10 0 (Some 502)))
      (alternate_entrypoint Legal_Confiscate
        (Trust_Observation FROZEN 100 10 0 (Some 502)))) =
      Trust_Applied"
  by (simp add: execute_entrypoint_def normalize_entrypoint_def
      execute_canonical_def canonical_precheck_def
      alternate_prepared_state_def alternate_entrypoint_def
      witness_prepared_state_def witness_seed_state_def witness_context_def
      witness_authorization_def authority_matches_def
      authorization_binding_matches_def authorization_payload_matches_def
      current_case_matches_def transfer_shape_valid_def
      operation_well_formed_def state_observation_commitment_def
      expected_post_observation_commitment_def observation_commitment_def
      Let_def)

lemma alternate_confiscate_from_seized_is_applied:
  "snd (execute_entrypoint
      (alternate_prepared_state Legal_Confiscate SEIZED 0 100
        (Trust_Observation SEIZED 100 0 100 (Some 502)))
      (alternate_entrypoint Legal_Confiscate
        (Trust_Observation SEIZED 100 0 100 (Some 502)))) =
      Trust_Applied"
  by (simp add: execute_entrypoint_def normalize_entrypoint_def
      execute_canonical_def canonical_precheck_def
      alternate_prepared_state_def alternate_entrypoint_def
      witness_prepared_state_def witness_seed_state_def witness_context_def
      witness_authorization_def authority_matches_def
      authorization_binding_matches_def authorization_payload_matches_def
      current_case_matches_def transfer_shape_valid_def
      operation_well_formed_def state_observation_commitment_def
      expected_post_observation_commitment_def observation_commitment_def
      Let_def)

lemma alternate_confiscate_from_restricted_is_applied:
  "snd (execute_entrypoint
      (alternate_prepared_state Legal_Confiscate RESTRICTED 0 0
        (Trust_Observation RESTRICTED 100 0 0 (Some 502)))
      (alternate_entrypoint Legal_Confiscate
        (Trust_Observation RESTRICTED 100 0 0 (Some 502)))) =
      Trust_Applied"
  by (simp add: execute_entrypoint_def normalize_entrypoint_def
      execute_canonical_def canonical_precheck_def
      alternate_prepared_state_def alternate_entrypoint_def
      witness_prepared_state_def witness_seed_state_def witness_context_def
      witness_authorization_def authority_matches_def
      authorization_binding_matches_def authorization_payload_matches_def
      current_case_matches_def transfer_shape_valid_def
      operation_well_formed_def state_observation_commitment_def
      expected_post_observation_commitment_def observation_commitment_def
      Let_def)

theorem alternate_overlay_paths_are_reachable:
  "snd (execute_entrypoint
      (alternate_prepared_state Legal_Freeze RESTRICTED 0 0
        (Trust_Observation RESTRICTED 100 0 0 (Some 500)))
      (alternate_entrypoint Legal_Freeze
        (Trust_Observation RESTRICTED 100 0 0 (Some 500)))) =
      Trust_Applied \<and>
   snd (execute_entrypoint
      (alternate_prepared_state Legal_Seize FROZEN 10 0
        (Trust_Observation FROZEN 100 10 0 (Some 501)))
      (alternate_entrypoint Legal_Seize
        (Trust_Observation FROZEN 100 10 0 (Some 501)))) =
      Trust_Applied \<and>
   snd (execute_entrypoint
      (alternate_prepared_state Legal_Confiscate FROZEN 10 0
        (Trust_Observation FROZEN 100 10 0 (Some 502)))
      (alternate_entrypoint Legal_Confiscate
        (Trust_Observation FROZEN 100 10 0 (Some 502)))) =
      Trust_Applied \<and>
   snd (execute_entrypoint
      (alternate_prepared_state Legal_Confiscate SEIZED 0 100
        (Trust_Observation SEIZED 100 0 100 (Some 502)))
      (alternate_entrypoint Legal_Confiscate
        (Trust_Observation SEIZED 100 0 100 (Some 502)))) =
      Trust_Applied \<and>
   snd (execute_entrypoint
      (alternate_prepared_state Legal_Confiscate RESTRICTED 0 0
        (Trust_Observation RESTRICTED 100 0 0 (Some 502)))
      (alternate_entrypoint Legal_Confiscate
        (Trust_Observation RESTRICTED 100 0 0 (Some 502)))) =
      Trust_Applied"
  using alternate_freeze_from_restricted_is_applied
    alternate_seize_from_frozen_is_applied
    alternate_confiscate_from_frozen_is_applied
    alternate_confiscate_from_seized_is_applied
    alternate_confiscate_from_restricted_is_applied
  by blast

definition erc7943_increase_context :: entry_context where
  "erc7943_increase_context =
    (witness_context Legal_Freeze)\<lparr>
      context_amount := 15,
      context_pre_observation_commitment :=
        Trust_Observation FROZEN 100 10 0 (Some 500),
      context_post_observation_commitment :=
        Trust_Observation FROZEN 100 15 0 (Some 500)\<rparr>"

definition erc7943_increase_state :: trust_state where
  "erc7943_increase_state =
    (let base = witness_prepared_state Legal_Freeze;
         aid = context_authorization_id erc7943_increase_context;
         auth =
           (witness_authorization Legal_Freeze)\<lparr>
             authorization_amount := 15,
             authorization_pre_observation_commitment :=
               Trust_Observation FROZEN 100 10 0 (Some 500),
             authorization_post_observation_commitment :=
               Trust_Observation FROZEN 100 15 0 (Some 500),
             authorization_lifecycle := Authorization_Approved\<rparr>
     in base\<lparr>
       trust_modes := (trust_modes base)(1 := FROZEN),
       trust_frozen_tokens := (trust_frozen_tokens base)(1 := 10),
       trust_case_registry :=
         (trust_case_registry base)
           (1 := Some (context_case erc7943_increase_context)),
       trust_authorizations :=
         (trust_authorizations base)(aid := Some auth)\<rparr>)"

definition erc7943_partial_decrease_context :: entry_context where
  "erc7943_partial_decrease_context =
    (reversal_context UNFREEZE)\<lparr>
      context_amount := 5,
      context_post_observation_commitment :=
        Trust_Observation FROZEN 100 5 0 (Some 600)\<rparr>"

definition erc7943_partial_decrease_state :: trust_state where
  "erc7943_partial_decrease_state =
    (let base = reversal_prepared_state UNFREEZE;
         aid = context_authorization_id erc7943_partial_decrease_context;
         auth =
           (reversal_authorization UNFREEZE)\<lparr>
             authorization_amount := 5,
             authorization_post_observation_commitment :=
               Trust_Observation FROZEN 100 5 0 (Some 600),
             authorization_lifecycle := Authorization_Approved\<rparr>
     in base\<lparr>
       trust_authorizations :=
         (trust_authorizations base)(aid := Some auth)\<rparr>)"

lemma erc7943_absolute_increase_is_applied:
  "snd (execute_entrypoint erc7943_increase_state
      (ERC7943_Set_Frozen_Entrypoint 15 erc7943_increase_context)) =
      Trust_Applied \<and>
   trust_modes
      (fst (execute_entrypoint erc7943_increase_state
        (ERC7943_Set_Frozen_Entrypoint 15 erc7943_increase_context))) 1 =
      FROZEN \<and>
   trust_frozen_tokens
      (fst (execute_entrypoint erc7943_increase_state
        (ERC7943_Set_Frozen_Entrypoint 15 erc7943_increase_context))) 1 =
      15"
  by (simp add: execute_entrypoint_def normalize_entrypoint_def
      execute_canonical_def canonical_precheck_def successful_state_def
      erc7943_increase_state_def erc7943_increase_context_def
      witness_prepared_state_def witness_seed_state_def witness_context_def
      witness_authorization_def authority_matches_def
      authorization_binding_matches_def authorization_payload_matches_def
      current_case_matches_def transfer_shape_valid_def
      operation_well_formed_def state_observation_commitment_def
      expected_post_observation_commitment_def observation_commitment_def
      Let_def)

lemma erc7943_absolute_partial_decrease_is_applied:
  "snd (execute_entrypoint erc7943_partial_decrease_state
      (ERC7943_Set_Frozen_Entrypoint 5
        erc7943_partial_decrease_context)) = Trust_Applied \<and>
   trust_modes
      (fst (execute_entrypoint erc7943_partial_decrease_state
        (ERC7943_Set_Frozen_Entrypoint 5
          erc7943_partial_decrease_context))) 1 = FROZEN \<and>
   trust_frozen_tokens
      (fst (execute_entrypoint erc7943_partial_decrease_state
        (ERC7943_Set_Frozen_Entrypoint 5
          erc7943_partial_decrease_context))) 1 = 5"
  by (simp add: execute_entrypoint_def normalize_entrypoint_def
      execute_canonical_def canonical_precheck_def successful_state_def
      erc7943_partial_decrease_state_def
      erc7943_partial_decrease_context_def reversal_prepared_state_def
      reversal_seed_state_def reversal_context_def reversal_authorization_def
      witness_seed_state_def witness_context_def witness_authorization_def
      authority_matches_def authorization_binding_matches_def
      authorization_payload_matches_def current_case_matches_def
      transfer_shape_valid_def operation_well_formed_def
      state_observation_commitment_def
      expected_post_observation_commitment_def observation_commitment_def
      Let_def)

lemma erc7943_absolute_zero_unfreezes:
  "snd (execute_entrypoint (reversal_prepared_state UNFREEZE)
      (ERC7943_Set_Frozen_Entrypoint 0
        (reversal_context UNFREEZE))) = Trust_Applied \<and>
   trust_modes
      (fst (execute_entrypoint (reversal_prepared_state UNFREEZE)
        (ERC7943_Set_Frozen_Entrypoint 0
          (reversal_context UNFREEZE)))) 1 = ACTIVE"
  by (simp add: execute_entrypoint_def normalize_entrypoint_def
      execute_canonical_def canonical_precheck_def successful_state_def
      reversal_prepared_state_def reversal_seed_state_def
      reversal_context_def reversal_authorization_def
      witness_seed_state_def witness_context_def witness_authorization_def
      authority_matches_def authorization_binding_matches_def
      authorization_payload_matches_def current_case_matches_def
      transfer_shape_valid_def operation_well_formed_def
      state_observation_commitment_def
      expected_post_observation_commitment_def observation_commitment_def
      Let_def)

lemma erc7943_absolute_amount_context_mismatch_is_denied:
  "normalize_entrypoint erc7943_increase_state
      (ERC7943_Set_Frozen_Entrypoint 10
        erc7943_increase_context) = None"
  by (simp add: normalize_entrypoint_def erc7943_increase_state_def
      erc7943_increase_context_def witness_prepared_state_def
      witness_seed_state_def witness_context_def witness_authorization_def
      Let_def)

theorem erc7943_absolute_delta_paths_are_reachable:
  "snd (execute_entrypoint erc7943_increase_state
      (ERC7943_Set_Frozen_Entrypoint 15 erc7943_increase_context)) =
      Trust_Applied \<and>
   trust_modes
      (fst (execute_entrypoint erc7943_increase_state
        (ERC7943_Set_Frozen_Entrypoint 15 erc7943_increase_context))) 1 =
      FROZEN \<and>
   trust_frozen_tokens
      (fst (execute_entrypoint erc7943_increase_state
        (ERC7943_Set_Frozen_Entrypoint 15 erc7943_increase_context))) 1 =
      15 \<and>
   snd (execute_entrypoint erc7943_partial_decrease_state
      (ERC7943_Set_Frozen_Entrypoint 5
        erc7943_partial_decrease_context)) = Trust_Applied \<and>
   trust_modes
      (fst (execute_entrypoint erc7943_partial_decrease_state
        (ERC7943_Set_Frozen_Entrypoint 5
          erc7943_partial_decrease_context))) 1 = FROZEN \<and>
   trust_frozen_tokens
      (fst (execute_entrypoint erc7943_partial_decrease_state
        (ERC7943_Set_Frozen_Entrypoint 5
          erc7943_partial_decrease_context))) 1 = 5 \<and>
   snd (execute_entrypoint (reversal_prepared_state UNFREEZE)
      (ERC7943_Set_Frozen_Entrypoint 0
        (reversal_context UNFREEZE))) = Trust_Applied \<and>
   trust_modes
      (fst (execute_entrypoint (reversal_prepared_state UNFREEZE)
        (ERC7943_Set_Frozen_Entrypoint 0
          (reversal_context UNFREEZE)))) 1 = ACTIVE \<and>
   normalize_entrypoint erc7943_increase_state
      (ERC7943_Set_Frozen_Entrypoint 10
        erc7943_increase_context) = None"
  using erc7943_absolute_increase_is_applied
    erc7943_absolute_partial_decrease_is_applied
    erc7943_absolute_zero_unfreezes
    erc7943_absolute_amount_context_mismatch_is_denied
  by blast

lemma erc3643_freeze_address_profile_is_applied:
  "snd (execute_entrypoint (witness_prepared_state Legal_Freeze)
      (ERC3643_Profile_Entrypoint ERC3643_Freeze_Address
        (witness_context Legal_Freeze))) = Trust_Applied"
  using witness_freeze_is_applied
  by (simp add: witness_entrypoint_def execute_entrypoint_def
      normalize_entrypoint_def)

lemma erc3643_unfreeze_address_profile_is_applied:
  "snd (execute_entrypoint (reversal_prepared_state UNFREEZE)
      (ERC3643_Profile_Entrypoint ERC3643_Unfreeze_Address
        (reversal_context UNFREEZE))) = Trust_Applied"
  using reversal_unfreeze_is_applied
  by (simp add: reversal_entrypoint_def execute_entrypoint_def
      normalize_entrypoint_def reversal_context_def witness_context_def)

lemma erc3643_recovery_profile_is_applied:
  "snd (execute_entrypoint (witness_prepared_state Legal_Recover)
      (ERC3643_Profile_Entrypoint ERC3643_Recovery
        (witness_context Legal_Recover))) = Trust_Applied"
  using witness_recover_is_applied
  by (simp add: witness_entrypoint_def execute_entrypoint_def
      normalize_entrypoint_def)

theorem supported_erc3643_profile_paths_are_reachable:
  "snd (execute_entrypoint (witness_prepared_state Legal_Freeze)
      (ERC3643_Profile_Entrypoint ERC3643_Freeze_Address
        (witness_context Legal_Freeze))) = Trust_Applied \<and>
   snd (execute_entrypoint (reversal_prepared_state UNFREEZE)
      (ERC3643_Profile_Entrypoint ERC3643_Unfreeze_Address
        (reversal_context UNFREEZE))) = Trust_Applied \<and>
   snd (execute_entrypoint (witness_prepared_state Legal_Recover)
      (ERC3643_Profile_Entrypoint ERC3643_Recovery
        (witness_context Legal_Recover))) = Trust_Applied"
  using erc3643_freeze_address_profile_is_applied
    erc3643_unfreeze_address_profile_is_applied
    erc3643_recovery_profile_is_applied
  by blast

definition mismatched_case_context :: entry_context where
  "mismatched_case_context =
    (reversal_context RELEASE)\<lparr>
      context_case := Suc (context_case (reversal_context RELEASE))\<rparr>"

definition mismatched_case_state :: trust_state where
  "mismatched_case_state =
    (let base = reversal_prepared_state RELEASE;
         aid = context_authorization_id mismatched_case_context;
         auth =
           (reversal_authorization RELEASE)\<lparr>
             authorization_case := context_case mismatched_case_context,
             authorization_lifecycle := Authorization_Approved\<rparr>
     in base\<lparr>
       trust_authorizations :=
         (trust_authorizations base)(aid := Some auth)\<rparr>)"

theorem current_case_mismatch_is_rejected_before_effects:
  "execute_entrypoint mismatched_case_state
      (Native_Entrypoint (Transition_Operation RELEASE)
        mismatched_case_context) =
    (mismatched_case_state, Trust_Rejected Case_Mismatch)"
  apply (rule entrypoint_rejection_pair_from_outcome)
  by (simp add: execute_entrypoint_def normalize_entrypoint_def
      execute_canonical_def canonical_precheck_def mismatched_case_state_def
      mismatched_case_context_def reversal_prepared_state_def
      reversal_seed_state_def reversal_context_def reversal_authorization_def
      witness_seed_state_def witness_context_def witness_authorization_def
      authority_matches_def authorization_binding_matches_def
      authorization_payload_matches_def current_case_matches_def
      transfer_shape_valid_def Let_def)

definition preloaded_untrusted_state :: trust_state where
  "preloaded_untrusted_state =
    (let base = witness_prepared_state Legal_Freeze;
         aid = context_authorization_id (witness_context Legal_Freeze);
         auth =
           (witness_authorization Legal_Freeze)\<lparr>
             authorization_issuer := 88,
             authorization_lifecycle := Authorization_Approved\<rparr>
     in base\<lparr>
       trust_authorizations :=
         (trust_authorizations base)(aid := Some auth)\<rparr>)"

theorem preloaded_untrusted_issuer_cannot_execute:
  "execute_entrypoint preloaded_untrusted_state
      (RCP_Entrypoint Legal_Freeze
        ((witness_context Legal_Freeze)\<lparr>context_actor := 88\<rparr>)) =
    (preloaded_untrusted_state, Trust_Rejected Actor_Not_Authorized)"
  apply (rule entrypoint_rejection_pair_from_outcome)
  by (simp add: execute_entrypoint_def normalize_entrypoint_def
      execute_canonical_def canonical_precheck_def
      preloaded_untrusted_state_def witness_prepared_state_def
      witness_seed_state_def witness_context_def witness_authorization_def
      authority_matches_def authorization_binding_matches_def
      authorization_payload_matches_def current_case_matches_def
      transfer_shape_valid_def Let_def)

definition delegated_seize_prepared_state :: trust_state where
  "delegated_seize_prepared_state =
    fst (execute_authorization_command
      (witness_prepared_state Legal_Seize)
      (Delegate_Authorization
        (context_authorization_id (witness_context Legal_Seize)) 9 77))"

theorem delegated_seize_keeps_authorized_destination_as_custodian:
  "snd (execute_entrypoint delegated_seize_prepared_state
      (RCP_Entrypoint Legal_Seize
        ((witness_context Legal_Seize)\<lparr>context_actor := 77\<rparr>))) =
      Trust_Applied \<and>
   trust_custody
      (fst (execute_entrypoint delegated_seize_prepared_state
        (RCP_Entrypoint Legal_Seize
          ((witness_context Legal_Seize)
            \<lparr>context_actor := 77\<rparr>)))) 1 = Some 9"
  by (simp add: execute_entrypoint_def normalize_entrypoint_def
      execute_canonical_def canonical_precheck_def successful_state_def
      delegated_seize_prepared_state_def execute_authorization_command_def
      witness_prepared_state_def witness_seed_state_def witness_context_def
      witness_authorization_def authority_matches_def
      authorization_binding_matches_def authorization_payload_matches_def
      current_case_matches_def transfer_shape_valid_def
      operation_well_formed_def state_observation_commitment_def
      expected_post_observation_commitment_def observation_commitment_def
      Let_def)

section \<open>Replay, Current Policy, Receipts, and Frame\<close>

definition witness_applied_state :: "legal_action_kind \<Rightarrow> trust_state" where
  "witness_applied_state k =
    fst (execute_entrypoint (witness_prepared_state k)
      (witness_entrypoint k))"

definition applied_action_nonce_property ::
  "legal_action_kind \<Rightarrow> bool"
where
  "applied_action_nonce_property k \<longleftrightarrow>
    context_nonce (witness_context k) \<in>
      trust_consumed_nonces (witness_applied_state k) \<and>
    authorization_lifecycle
      (the (trust_authorizations (witness_applied_state k)
        (context_authorization_id (witness_context k)))) =
      Authorization_Consumed"

lemma applied_action_nonce_property_table:
  "list_all applied_action_nonce_property all_legal_action_kinds"
  by (simp add: applied_action_nonce_property_def
      all_legal_action_kinds_def witness_applied_state_def
      witness_entrypoint_def execute_entrypoint_def normalize_entrypoint_def
      execute_canonical_def canonical_precheck_def successful_state_def
      witness_prepared_state_def witness_seed_state_def witness_context_def
      witness_authorization_def authority_matches_def
      authorization_binding_matches_def authorization_payload_matches_def
      current_case_matches_def transfer_shape_valid_def
      operation_well_formed_def state_observation_commitment_def
      expected_post_observation_commitment_def observation_commitment_def
      Let_def)

theorem applied_action_and_nonce_are_consumed_once:
  "context_nonce (witness_context k) \<in>
       trust_consumed_nonces (witness_applied_state k) \<and>
     authorization_lifecycle
       (the (trust_authorizations (witness_applied_state k)
         (context_authorization_id (witness_context k)))) =
       Authorization_Consumed"
  using applied_action_nonce_property_table
    all_legal_action_kinds_are_listed[of k]
  unfolding applied_action_nonce_property_def
  by (simp add: list_all_iff)

definition replay_property :: "legal_action_kind \<Rightarrow> bool" where
  "replay_property k \<longleftrightarrow>
    snd (execute_entrypoint (witness_applied_state k)
      (witness_entrypoint k)) =
      Trust_Rejected Authorization_Replayed"

lemma replay_property_table:
  "list_all replay_property all_legal_action_kinds"
  by (simp add: replay_property_def all_legal_action_kinds_def
      witness_applied_state_def witness_entrypoint_def
      execute_entrypoint_def normalize_entrypoint_def execute_canonical_def
      canonical_precheck_def successful_state_def
      witness_prepared_state_def witness_seed_state_def witness_context_def
      witness_authorization_def authority_matches_def
      authorization_binding_matches_def authorization_payload_matches_def
      current_case_matches_def transfer_shape_valid_def
      operation_well_formed_def state_observation_commitment_def
      expected_post_observation_commitment_def observation_commitment_def
      Let_def)

theorem replay_is_rejected:
  "snd (execute_entrypoint (witness_applied_state k)
       (witness_entrypoint k)) =
       Trust_Rejected Authorization_Replayed"
  using replay_property_table all_legal_action_kinds_are_listed[of k]
  unfolding replay_property_def
  by (simp add: list_all_iff)

definition stale_policy_property :: "legal_action_kind \<Rightarrow> bool" where
  "stale_policy_property k \<longleftrightarrow>
    snd (execute_entrypoint
      ((witness_prepared_state k)\<lparr>trust_policy_epoch := 2\<rparr>)
      (witness_entrypoint k)) =
      Trust_Rejected Authorization_Stale"

lemma stale_policy_property_table:
  "list_all stale_policy_property all_legal_action_kinds"
  by (simp add: stale_policy_property_def all_legal_action_kinds_def
      witness_entrypoint_def execute_entrypoint_def normalize_entrypoint_def
      execute_canonical_def canonical_precheck_def
      witness_prepared_state_def witness_seed_state_def witness_context_def
      witness_authorization_def authority_matches_def
      authorization_binding_matches_def authorization_payload_matches_def
      current_case_matches_def transfer_shape_valid_def Let_def)

theorem stale_policy_authorization_is_rejected:
  fixes k :: legal_action_kind
  defines "stale \<equiv>
    (witness_prepared_state k)\<lparr>trust_policy_epoch := 2\<rparr>"
  shows "snd (execute_entrypoint stale (witness_entrypoint k)) =
    Trust_Rejected Authorization_Stale"
  using stale_policy_property_table
    all_legal_action_kinds_are_listed[of k]
  unfolding stale_def stale_policy_property_def
  by (simp add: list_all_iff)

definition cancelled_witness_state :: "legal_action_kind \<Rightarrow> trust_state" where
  "cancelled_witness_state k =
    fst (execute_authorization_command (witness_prepared_state k)
      (Cancel_Authorization
        (context_authorization_id (witness_context k)) 9))"

definition cancellation_property :: "legal_action_kind \<Rightarrow> bool" where
  "cancellation_property k \<longleftrightarrow>
    authorization_lifecycle
      (the (trust_authorizations (cancelled_witness_state k)
        (context_authorization_id (witness_context k)))) =
        Authorization_Cancelled \<and>
    snd (execute_entrypoint (cancelled_witness_state k)
      (witness_entrypoint k)) =
        Trust_Rejected Authorization_Not_Approved"

lemma cancellation_property_table:
  "list_all cancellation_property all_legal_action_kinds"
  by (simp add: cancellation_property_def all_legal_action_kinds_def
      cancelled_witness_state_def execute_authorization_command_def
      witness_entrypoint_def execute_entrypoint_def normalize_entrypoint_def
      execute_canonical_def canonical_precheck_def
      witness_prepared_state_def witness_seed_state_def witness_context_def
      witness_authorization_def authority_matches_def
      authorization_binding_matches_def authorization_payload_matches_def
      current_case_matches_def transfer_shape_valid_def Let_def)

theorem cancellation_lifecycle_is_reachable_and_prevents_execution:
  "authorization_lifecycle
     (the (trust_authorizations (cancelled_witness_state k)
       (context_authorization_id (witness_context k)))) =
       Authorization_Cancelled \<and>
   snd (execute_entrypoint (cancelled_witness_state k)
     (witness_entrypoint k)) =
       Trust_Rejected Authorization_Not_Approved"
  using cancellation_property_table
    all_legal_action_kinds_are_listed[of k]
  unfolding cancellation_property_def
  by (simp add: list_all_iff)

definition delegated_witness_state :: "legal_action_kind \<Rightarrow> trust_state" where
  "delegated_witness_state k =
    fst (execute_authorization_command (witness_prepared_state k)
      (Delegate_Authorization
        (context_authorization_id (witness_context k)) 9 77))"

definition delegation_property :: "legal_action_kind \<Rightarrow> bool" where
  "delegation_property k \<longleftrightarrow>
    authorization_delegate
      (the (trust_authorizations (delegated_witness_state k)
        (context_authorization_id (witness_context k)))) = Some 77"

lemma delegation_property_table:
  "list_all delegation_property all_legal_action_kinds"
  by (simp add: delegation_property_def all_legal_action_kinds_def
      delegated_witness_state_def execute_authorization_command_def
      witness_prepared_state_def witness_seed_state_def witness_context_def
      witness_authorization_def Let_def)

theorem delegation_lifecycle_is_reachable:
  "authorization_delegate
     (the (trust_authorizations (delegated_witness_state k)
       (context_authorization_id (witness_context k)))) = Some 77"
  using delegation_property_table all_legal_action_kinds_are_listed[of k]
  unfolding delegation_property_def
  by (simp add: list_all_iff)

definition rebound_policy_state :: "legal_action_kind \<Rightarrow> trust_state" where
  "rebound_policy_state k =
    fst (execute_authorization_command (witness_prepared_state k)
      (Rebind_Policy 0 80001 3 80002 2))"

definition policy_rebind_property :: "legal_action_kind \<Rightarrow> bool" where
  "policy_rebind_property k \<longleftrightarrow>
    trust_policy_epoch (rebound_policy_state k) = 2 \<and>
    trust_policy_code (rebound_policy_state k) = 80001 \<and>
    trust_policy_schema (rebound_policy_state k) = 3 \<and>
    trust_policy_config (rebound_policy_state k) = 80002 \<and>
    trust_last_policy_change (rebound_policy_state k) = Some 2 \<and>
    snd (execute_entrypoint (rebound_policy_state k)
      (witness_entrypoint k)) = Trust_Rejected Authorization_Stale"

lemma policy_rebind_property_table:
  "list_all policy_rebind_property all_legal_action_kinds"
  by (simp add: policy_rebind_property_def all_legal_action_kinds_def
      rebound_policy_state_def execute_authorization_command_def
      witness_entrypoint_def execute_entrypoint_def normalize_entrypoint_def
      execute_canonical_def canonical_precheck_def
      witness_prepared_state_def witness_seed_state_def witness_context_def
      witness_authorization_def authority_matches_def
      authorization_binding_matches_def authorization_payload_matches_def
      current_case_matches_def transfer_shape_valid_def Let_def)

theorem policy_rebind_is_monotonic_observable_and_invalidates_old_authorization:
  "trust_policy_epoch (rebound_policy_state k) = 2 \<and>
   trust_policy_code (rebound_policy_state k) = 80001 \<and>
   trust_policy_schema (rebound_policy_state k) = 3 \<and>
   trust_policy_config (rebound_policy_state k) = 80002 \<and>
   trust_last_policy_change (rebound_policy_state k) = Some 2 \<and>
   snd (execute_entrypoint (rebound_policy_state k)
     (witness_entrypoint k)) = Trust_Rejected Authorization_Stale"
  using policy_rebind_property_table
    all_legal_action_kinds_are_listed[of k]
  unfolding policy_rebind_property_def
  by (simp add: list_all_iff)

definition rotated_authority_state :: "legal_action_kind \<Rightarrow> trust_state" where
  "rotated_authority_state k =
    fst (execute_authorization_command (witness_prepared_state k)
      (Rotate_Authority_Epoch 0 8))"

definition authority_rotation_property :: "legal_action_kind \<Rightarrow> bool" where
  "authority_rotation_property k \<longleftrightarrow>
    trust_authority_epoch (rotated_authority_state k) = 8 \<and>
    trust_last_policy_change (rotated_authority_state k) = Some 8 \<and>
    snd (execute_entrypoint (rotated_authority_state k)
      (witness_entrypoint k)) = Trust_Rejected Authorization_Stale"

lemma authority_rotation_property_table:
  "list_all authority_rotation_property all_legal_action_kinds"
  by (simp add: authority_rotation_property_def
      all_legal_action_kinds_def rotated_authority_state_def
      execute_authorization_command_def witness_entrypoint_def
      execute_entrypoint_def normalize_entrypoint_def execute_canonical_def
      canonical_precheck_def witness_prepared_state_def witness_seed_state_def
      witness_context_def witness_authorization_def authority_matches_def
      authorization_binding_matches_def authorization_payload_matches_def
      current_case_matches_def transfer_shape_valid_def Let_def)

theorem authority_epoch_rotation_is_monotonic_and_invalidates_old_authorization:
  "trust_authority_epoch (rotated_authority_state k) = 8 \<and>
   trust_last_policy_change (rotated_authority_state k) = Some 8 \<and>
   snd (execute_entrypoint (rotated_authority_state k)
     (witness_entrypoint k)) = Trust_Rejected Authorization_Stale"
  using authority_rotation_property_table
    all_legal_action_kinds_are_listed[of k]
  unfolding authority_rotation_property_def
  by (simp add: list_all_iff)

theorem rejected_and_operational_failure_are_full_state_stutters:
  "fst (execute_entrypoint (witness_prepared_state k)
       (unauthorized_witness_entrypoint k)) = witness_prepared_state k \<and>
   fst (execute_entrypoint (witness_prepared_state k)
       (unavailable_witness_entrypoint k)) = witness_prepared_state k"
proof -
  have unauthorized_outcome:
    "snd (execute_entrypoint (witness_prepared_state k)
        (unauthorized_witness_entrypoint k)) =
      Trust_Rejected Actor_Not_Authorized"
    using all_six_actions_have_reachable_denial_witnesses by blast
  have unauthorized_pair:
    "execute_entrypoint (witness_prepared_state k)
        (unauthorized_witness_entrypoint k) =
      (witness_prepared_state k,
       Trust_Rejected Actor_Not_Authorized)"
    using entrypoint_rejection_pair_from_outcome[OF unauthorized_outcome] .
  have unavailable_pair:
    "execute_entrypoint (witness_prepared_state k)
        (unavailable_witness_entrypoint k) =
      (witness_prepared_state k,
       Trust_Operational_Failure Policy_Module_Unavailable)"
    using all_six_actions_have_reachable_operational_failure_witnesses
    by blast
  show ?thesis
    using unauthorized_pair unavailable_pair by simp
qed

definition applied_receipt_property :: "legal_action_kind \<Rightarrow> bool" where
  "applied_receipt_property k \<longleftrightarrow>
    trust_last_receipt (witness_applied_state k) \<noteq> None \<and>
    receipt_operation
      (the (trust_last_receipt (witness_applied_state k))) =
      RCP_Operation k \<and>
    receipt_authorization
      (the (trust_last_receipt (witness_applied_state k))) =
      context_authorization_id (witness_context k)"

lemma applied_receipt_property_table:
  "list_all applied_receipt_property all_legal_action_kinds"
  by (simp add: applied_receipt_property_def all_legal_action_kinds_def
      witness_applied_state_def witness_entrypoint_def
      execute_entrypoint_def normalize_entrypoint_def execute_canonical_def
      canonical_precheck_def successful_state_def
      witness_prepared_state_def witness_seed_state_def witness_context_def
      witness_authorization_def authority_matches_def
      authorization_binding_matches_def authorization_payload_matches_def
      current_case_matches_def transfer_shape_valid_def
      operation_well_formed_def state_observation_commitment_def
      expected_post_observation_commitment_def observation_commitment_def
      Let_def)

theorem applied_receipt_is_the_last_persistent_receipt:
  "\<exists>receipt.
       trust_last_receipt (witness_applied_state k) = Some receipt \<and>
       receipt_operation receipt = RCP_Operation k \<and>
       receipt_authorization receipt =
         context_authorization_id (witness_context k)"
proof -
  have property: "applied_receipt_property k"
    using applied_receipt_property_table
      all_legal_action_kinds_are_listed[of k]
    by (simp add: list_all_iff)
  obtain receipt where
    "trust_last_receipt (witness_applied_state k) = Some receipt"
    using property unfolding applied_receipt_property_def
    by (cases "trust_last_receipt (witness_applied_state k)") auto
  then show ?thesis
    using property unfolding applied_receipt_property_def
    by auto
qed

section \<open>CE-02, CE-11, and CE-12 Semantic Closure Witnesses\<close>

definition ce02_retrieve_relation ::
  "reg_state \<Rightarrow> trust_state \<Rightarrow> nat \<Rightarrow> bool"
where
  "ce02_retrieve_relation abstract_mode st subject \<longleftrightarrow>
    trust_modes st subject = abstract_mode \<and>
    (if abstract_mode = SEIZED then
       (\<exists>custodian case_id amount.
          trust_custody st subject = Some custodian \<and>
          trust_case_registry st subject = Some case_id \<and>
          trust_declared_prior_holder st subject = Some subject \<and>
          trust_encumbered_amount st subject = amount \<and>
          amount > 0)
     else True)"

theorem ce02_seize_preserves_declared_holder_and_records_custody:
  "trust_balances (witness_applied_state Legal_Seize) 1 = 100 \<and>
   trust_custody (witness_applied_state Legal_Seize) 1 = Some 9 \<and>
   trust_declared_prior_holder
     (witness_applied_state Legal_Seize) 1 = Some 1 \<and>
   trust_encumbered_amount
     (witness_applied_state Legal_Seize) 1 = 10 \<and>
   trust_case_registry
     (witness_applied_state Legal_Seize) 1 =
       Some (context_case (witness_context Legal_Seize)) \<and>
   trust_modes (witness_applied_state Legal_Seize) 1 = SEIZED"
  by (simp add: witness_applied_state_def witness_entrypoint_def
      execute_entrypoint_def normalize_entrypoint_def execute_canonical_def
      canonical_precheck_def successful_state_def
      witness_prepared_state_def witness_seed_state_def witness_context_def
      witness_authorization_def authority_matches_def
      authorization_binding_matches_def authorization_payload_matches_def
      current_case_matches_def transfer_shape_valid_def
      operation_well_formed_def state_observation_commitment_def
      expected_post_observation_commitment_def observation_commitment_def
      Let_def)

theorem ce02_foundation_to_trust_retrieve_relation_is_nonvacuous:
  "ce02_retrieve_relation SEIZED
     (witness_applied_state Legal_Seize) 1"
  using ce02_seize_preserves_declared_holder_and_records_custody
  by (auto simp: ce02_retrieve_relation_def)

theorem ce11_liquidate_assume_guarantee:
  assumes
    "execute_canonical st
       \<lparr>request_operation = RCP_Operation Legal_Liquidate,
        request_context = ctx\<rparr> = (st', Trust_Applied)"
  shows
    "context_settlement_attested ctx \<and>
     context_settlement_capability ctx \<and>
     trust_settlement_commitment st' (context_case ctx) =
       Some (context_external_commitment ctx) \<and>
     trust_proceeds_reference st' (context_case ctx) =
       Some (context_proceeds_reference ctx) \<and>
     trust_external_settlement_status st' (context_case ctx) =
       Some True \<and>
     (\<exists>receipt.
        trust_last_receipt st' = Some receipt \<and>
        receipt_operation receipt = RCP_Operation Legal_Liquidate \<and>
        receipt_destination receipt = context_destination ctx \<and>
        receipt_amount receipt = context_amount ctx \<and>
        receipt_external_settlement_status receipt = Some True)"
proof -
  have evidence:
    "context_settlement_attested ctx \<and>
     context_settlement_capability ctx"
    using assms
    unfolding execute_canonical_def
    by (auto split: canonical_precheck_result.splits option.splits
        if_splits simp: Let_def)
  obtain auth target where
    result:
      "st' = successful_state st
        \<lparr>request_operation = RCP_Operation Legal_Liquidate,
         request_context = ctx\<rparr> auth target"
    using execute_canonical_applied_structure[OF assms] by blast
  show ?thesis
    using evidence result
    unfolding successful_state_def
    by (auto simp: Let_def)
qed

theorem ce11_liquidate_binds_settlement_without_asserting_external_truth:
  "trust_settlement_commitment (witness_applied_state Legal_Liquidate)
       (context_case (witness_context Legal_Liquidate)) =
       Some (context_external_commitment
         (witness_context Legal_Liquidate)) \<and>
   trust_proceeds_reference (witness_applied_state Legal_Liquidate)
       (context_case (witness_context Legal_Liquidate)) =
       Some (context_proceeds_reference
         (witness_context Legal_Liquidate)) \<and>
   trust_external_settlement_status
       (witness_applied_state Legal_Liquidate)
       (context_case (witness_context Legal_Liquidate)) = Some True \<and>
   (\<exists>receipt.
      trust_last_receipt (witness_applied_state Legal_Liquidate) =
        Some receipt \<and>
      receipt_destination receipt =
        context_destination (witness_context Legal_Liquidate) \<and>
      receipt_amount receipt =
        context_amount (witness_context Legal_Liquidate) \<and>
      receipt_external_settlement_status receipt = Some True)"
proof -
  let ?request =
    "\<lparr>request_operation = RCP_Operation Legal_Liquidate,
      request_context = witness_context Legal_Liquidate\<rparr>"
  have outcome:
    "snd (execute_canonical (witness_prepared_state Legal_Liquidate)
      ?request) = Trust_Applied"
    using witness_canonical_outcome_is_applied[of Legal_Liquidate] .
  have state:
    "witness_applied_state Legal_Liquidate =
      fst (execute_canonical (witness_prepared_state Legal_Liquidate)
        ?request)"
    by (simp add: witness_applied_state_def witness_entrypoint_def
        execute_entrypoint_def normalize_entrypoint_def)
  have execution:
    "execute_canonical (witness_prepared_state Legal_Liquidate)
      ?request =
      (witness_applied_state Legal_Liquidate, Trust_Applied)"
    using outcome state by (metis prod.collapse)
  show ?thesis
    using ce11_liquidate_assume_guarantee[OF execution] by blast
qed

theorem ce12_recover_assume_guarantee:
  assumes
    "execute_canonical st
       \<lparr>request_operation = RCP_Operation Legal_Recover,
        request_context = ctx\<rparr> = (st', Trust_Applied)"
  shows
    "context_entitlement_attested ctx \<and>
     trust_entitlement_commitment st' (context_case ctx) =
       Some (context_external_commitment ctx) \<and>
     (case context_destination ctx of
        None \<Rightarrow> False
      | Some destination \<Rightarrow>
          trust_balances st' destination =
            trust_balances st destination + context_amount ctx) \<and>
     context_nonce ctx \<in> trust_consumed_nonces st' \<and>
     (\<exists>receipt.
        trust_last_receipt st' = Some receipt \<and>
        receipt_operation receipt = RCP_Operation Legal_Recover \<and>
        receipt_destination receipt = context_destination ctx \<and>
        receipt_amount receipt = context_amount ctx)"
proof -
  have evidence: "context_entitlement_attested ctx"
    using assms
    unfolding execute_canonical_def
    by (auto split: canonical_precheck_result.splits option.splits
        if_splits simp: Let_def)
  have shape:
    "transfer_shape_valid (RCP_Operation Legal_Recover) ctx"
    using assms
    unfolding execute_canonical_def
    by (auto split: canonical_precheck_result.splits option.splits
        if_splits simp: operation_well_formed_def
          transfer_shape_valid_def Let_def)
  obtain auth target where
    result:
      "st' = successful_state st
        \<lparr>request_operation = RCP_Operation Legal_Recover,
         request_context = ctx\<rparr> auth target"
    using execute_canonical_applied_structure[OF assms] by blast
  show ?thesis
    using evidence shape result
    unfolding successful_state_def transfer_balances_def
      transfer_shape_valid_def
    by (auto split: option.splits simp: Let_def)
qed

theorem recover_and_liquidate_consume_seized_custody_encumbrance:
  "trust_modes (witness_applied_state Legal_Recover) 1 = ACTIVE \<and>
   trust_custody (witness_applied_state Legal_Recover) 1 = None \<and>
   trust_encumbered_amount (witness_applied_state Legal_Recover) 1 = 0 \<and>
   trust_declared_prior_holder
     (witness_applied_state Legal_Recover) 1 = None \<and>
   trust_modes (witness_applied_state Legal_Liquidate) 1 = ACTIVE \<and>
   trust_custody (witness_applied_state Legal_Liquidate) 1 = None \<and>
   trust_encumbered_amount (witness_applied_state Legal_Liquidate) 1 = 0 \<and>
   trust_declared_prior_holder
     (witness_applied_state Legal_Liquidate) 1 = None"
  by (simp add: witness_applied_state_def witness_entrypoint_def
      execute_entrypoint_def normalize_entrypoint_def execute_canonical_def
      canonical_precheck_def successful_state_def
      witness_prepared_state_def witness_seed_state_def witness_context_def
      witness_authorization_def authority_matches_def
      authorization_binding_matches_def authorization_payload_matches_def
      current_case_matches_def transfer_shape_valid_def
      operation_well_formed_def state_observation_commitment_def
      expected_post_observation_commitment_def observation_commitment_def
      Let_def)

theorem ce12_recover_binds_entitlement_destination_and_consumption:
  "trust_entitlement_commitment (witness_applied_state Legal_Recover)
       (context_case (witness_context Legal_Recover)) =
       Some (context_external_commitment (witness_context Legal_Recover)) \<and>
   trust_balances (witness_applied_state Legal_Recover) 2 = 10 \<and>
     context_nonce (witness_context Legal_Recover) \<in>
       trust_consumed_nonces (witness_applied_state Legal_Recover)"
proof -
  let ?request =
    "\<lparr>request_operation = RCP_Operation Legal_Recover,
      request_context = witness_context Legal_Recover\<rparr>"
  have outcome:
    "snd (execute_canonical (witness_prepared_state Legal_Recover)
      ?request) = Trust_Applied"
    using witness_canonical_outcome_is_applied[of Legal_Recover] .
  have state:
    "witness_applied_state Legal_Recover =
      fst (execute_canonical (witness_prepared_state Legal_Recover)
        ?request)"
    by (simp add: witness_applied_state_def witness_entrypoint_def
        execute_entrypoint_def normalize_entrypoint_def)
  have execution:
    "execute_canonical (witness_prepared_state Legal_Recover)
      ?request =
      (witness_applied_state Legal_Recover, Trust_Applied)"
    using outcome state by (metis prod.collapse)
  show ?thesis
    using ce12_recover_assume_guarantee[OF execution]
    by (simp add: witness_prepared_state_def witness_authorization_trace_def
        witness_seed_state_def witness_context_def witness_authorization_def
        execute_authorization_command_def Let_def)
qed

end
