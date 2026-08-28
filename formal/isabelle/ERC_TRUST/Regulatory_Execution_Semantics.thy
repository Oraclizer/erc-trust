(*
  Title:      ERC_TRUST/Regulatory_Execution_Semantics.thy
  Author:     Jinwook Kim (Jay) <jay@oraclizer.io>
  License:    BSD

  ERC-TRUST abstract execution model.

  Scope: mechanically verified regulatory dynamics over the declared model.
  This theory does not establish legal title, judicial validity, sale
  completion, debt discharge, or the truth of external evidence.
*)

theory Regulatory_Execution_Semantics
  imports Cross_Domain_State_Preservation.Regulatory_Action_Composition
begin

section \<open>Six Regulatory Actions and Seven Transition Labels\<close>

datatype trust_operation =
    RCP_Operation legal_action_kind
  | Transition_Operation reg_action

datatype authorization_lifecycle =
    Authorization_Created
  | Authorization_Approved
  | Authorization_Cancelled
  | Authorization_Consumed

datatype trust_rejection =
    Authorization_Not_Found
  | Authorization_Not_Approved
  | Authorization_Mismatch
  | Case_Mismatch
  | Authorization_Stale
  | Authorization_Replayed
  | Actor_Not_Authorized
  | Invalid_State_Transition
  | Transfer_Target_Missing
  | Insufficient_Balance
  | External_Evidence_Denied
  | Capability_Unsupported
  | Operation_Not_Allowed
  | Invalid_Observation
  | Untyped_Request_Denied

datatype trust_operational_failure =
    Policy_Module_Unavailable

datatype trust_outcome =
    Trust_Applied
  | Trust_Rejected trust_rejection
  | Trust_Operational_Failure trust_operational_failure

datatype write_slot =
    Regulatory_Mode_Slot
  | Balance_Slot
  | Custody_Slot
  | Frozen_Amount_Slot
  | Case_Slot
  | Encumbrance_Slot
  | Prior_Holder_Slot
  | Settlement_Slot
  | Entitlement_Slot
  | Supply_Slot
  | Allowance_Slot
  | Policy_Binding_Slot
  | Authority_Epoch_Slot
  | Policy_Change_Event_Slot
  | Authorization_Slot
  | Nonce_Slot
  | Receipt_Slot

datatype trust_observation =
  Trust_Observation reg_state nat nat nat "nat option"

record entry_context =
  context_authorization_id :: nat
  context_chain            :: nat
  context_token            :: nat
  context_standard_version :: nat
  context_actor            :: nat
  context_subject          :: nat
  context_destination      :: "nat option"
  context_amount           :: nat
  context_case             :: nat
  context_external_commitment :: nat
  context_proceeds_reference :: nat
  context_nonce            :: nat
  context_epoch            :: nat
  context_authority_epoch  :: nat
  context_policy_code      :: nat
  context_policy_schema    :: nat
  context_policy_config    :: nat
  context_provenance_commitment :: nat
  context_valid_after      :: nat
  context_deadline         :: nat
  context_current_time     :: nat
  context_pre_observation_commitment :: trust_observation
  context_post_observation_commitment :: trust_observation
  context_module_ready     :: bool
  context_entitlement_attested :: bool
  context_settlement_attested  :: bool
  context_settlement_capability :: bool

record trust_authorization =
  authorization_operation   :: trust_operation
  authorization_chain       :: nat
  authorization_token       :: nat
  authorization_standard_version :: nat
  authorization_subject     :: nat
  authorization_destination :: "nat option"
  authorization_amount      :: nat
  authorization_case        :: nat
  authorization_external_commitment :: nat
  authorization_proceeds_reference :: nat
  authorization_issuer      :: nat
  authorization_delegate    :: "nat option"
  authorization_nonce       :: nat
  authorization_epoch       :: nat
  authorization_authority_epoch :: nat
  authorization_policy_code :: nat
  authorization_policy_schema :: nat
  authorization_policy_config :: nat
  authorization_provenance_commitment :: nat
  authorization_valid_after :: nat
  authorization_deadline    :: nat
  authorization_pre_observation_commitment :: trust_observation
  authorization_post_observation_commitment :: trust_observation
  authorization_lifecycle   :: authorization_lifecycle

record trust_receipt =
  receipt_operation       :: trust_operation
  receipt_authorization   :: nat
  receipt_subject         :: nat
  receipt_destination     :: "nat option"
  receipt_amount          :: nat
  receipt_case            :: nat
  receipt_previous_mode   :: reg_state
  receipt_resulting_mode  :: reg_state
  receipt_external_commitment :: nat
  receipt_proceeds_reference :: nat
  receipt_nonce           :: nat
  receipt_authority_epoch :: nat
  receipt_policy_code     :: nat
  receipt_policy_schema   :: nat
  receipt_policy_config   :: nat
  receipt_provenance_commitment :: nat
  receipt_pre_observation_commitment :: trust_observation
  receipt_post_observation_commitment :: trust_observation
  receipt_external_settlement_status :: "bool option"
  receipt_write_set       :: "write_slot list"

record trust_case_record =
  case_record_subject :: nat
  case_record_amount :: nat
  case_record_last_operation :: trust_operation
  case_record_mode :: reg_state
  case_record_terminal :: bool
  case_record_receipt_authorization :: nat

datatype governance_operation =
    Governance_Mint nat nat
  | Governance_Burn nat nat
  | Governance_Batch_Mint nat nat nat nat
  | Governance_Batch_Burn nat nat nat nat
  | Governance_Recovery_Supply_Transfer nat nat nat

record governance_request =
  governance_request_operation :: governance_operation
  governance_request_actor :: nat
  governance_request_chain :: nat
  governance_request_token :: nat
  governance_request_standard_version :: nat
  governance_request_nonce :: nat
  governance_request_authority_epoch :: nat
  governance_request_policy_epoch :: nat

record governance_receipt =
  governance_receipt_operation :: governance_operation
  governance_receipt_actor :: nat
  governance_receipt_nonce :: nat
  governance_receipt_authority_epoch :: nat
  governance_receipt_policy_epoch :: nat
  governance_receipt_write_set :: "write_slot list"

record trust_state =
  trust_modes             :: "nat \<Rightarrow> reg_state"
  trust_balances          :: "nat \<Rightarrow> nat"
  trust_frozen_tokens     :: "nat \<Rightarrow> nat"
  trust_custody           :: "nat \<Rightarrow> nat option"
  trust_case_registry     :: "nat \<Rightarrow> nat option"
  trust_encumbered_amount :: "nat \<Rightarrow> nat"
  trust_declared_prior_holder :: "nat \<Rightarrow> nat option"
  trust_settlement_commitment :: "nat \<Rightarrow> nat option"
  trust_proceeds_reference :: "nat \<Rightarrow> nat option"
  trust_entitlement_commitment :: "nat \<Rightarrow> nat option"
  trust_external_settlement_status :: "nat \<Rightarrow> bool option"
  trust_cases             :: "nat \<Rightarrow> trust_case_record option"
  trust_receipt_registry  :: "nat \<Rightarrow> trust_receipt option"
  trust_total_supply       :: nat
  trust_allowances         :: "nat \<Rightarrow> nat \<Rightarrow> nat"
  trust_policy_epoch      :: nat
  trust_chain             :: nat
  trust_token             :: nat
  trust_standard_version  :: nat
  trust_authority_epoch   :: nat
  trust_policy_code       :: nat
  trust_policy_schema     :: nat
  trust_policy_config     :: nat
  trust_governance_authority :: nat
  trust_regulatory_authorities :: "nat set"
  trust_last_policy_change :: "nat option"
  trust_authorizations    :: "nat \<Rightarrow> trust_authorization option"
  trust_consumed_nonces   :: "nat set"
  trust_last_receipt      :: "trust_receipt option"
  trust_last_governance_receipt :: "governance_receipt option"
  trust_auxiliary         :: "nat \<Rightarrow> nat"

record canonical_request =
  request_operation :: trust_operation
  request_context   :: entry_context

datatype canonical_precheck_result =
    Canonical_Precheck_Pass trust_authorization
  | Canonical_Precheck_Stop trust_outcome

datatype erc3643_profile_call =
    ERC3643_Freeze_Address
  | ERC3643_Unfreeze_Address
  | ERC3643_Forced_Transfer
  | ERC3643_Recovery
  | ERC3643_Pause_All

fun erc3643_profile_mapping ::
  "erc3643_profile_call \<Rightarrow> trust_operation option"
where
  "erc3643_profile_mapping ERC3643_Freeze_Address =
     Some (RCP_Operation Legal_Freeze)"
| "erc3643_profile_mapping ERC3643_Unfreeze_Address =
     Some (Transition_Operation UNFREEZE)"
| "erc3643_profile_mapping ERC3643_Forced_Transfer = None"
| "erc3643_profile_mapping ERC3643_Recovery =
     Some (RCP_Operation Legal_Recover)"
| "erc3643_profile_mapping ERC3643_Pause_All = None"

definition supported_erc3643_profile_calls :: "erc3643_profile_call set" where
  "supported_erc3643_profile_calls =
    {ERC3643_Freeze_Address, ERC3643_Unfreeze_Address, ERC3643_Recovery}"

datatype trust_entrypoint =
    RCP_Entrypoint legal_action_kind entry_context
  | Native_Entrypoint trust_operation entry_context
  | ERC7943_Set_Frozen_Entrypoint nat entry_context
  | ERC7943_Forced_Transfer_Entrypoint entry_context
  | ERC3643_Profile_Entrypoint erc3643_profile_call entry_context
  | Untyped_Entrypoint nat

datatype authorization_command =
    Create_Authorization nat nat trust_authorization
  | Approve_Authorization nat nat
  | Cancel_Authorization nat nat
  | Delegate_Authorization nat nat nat
  | Rotate_Authority_Epoch nat nat
  | Rebind_Policy nat nat nat nat nat

datatype authorization_command_outcome =
    Authorization_Command_Applied
  | Authorization_Command_Rejected

record ordinary_transfer_command =
  ordinary_source            :: nat
  ordinary_destination       :: nat
  ordinary_amount            :: nat
  ordinary_baseline_clear    :: bool
  ordinary_restriction_clear :: bool
  ordinary_destination_clear :: bool

datatype trust_command_taxonomy =
    Regulatory_Forward_Command legal_action_kind
  | Reversal_Command reg_action
  | Ordinary_Transfer_Command
  | Privileged_Governance_Command

definition model_execution_taxonomy :: "trust_command_taxonomy set" where
  "model_execution_taxonomy =
    {Regulatory_Forward_Command k | k. True} \<union>
    {Reversal_Command UNFREEZE, Reversal_Command UNRESTRICT,
     Reversal_Command RELEASE} \<union>
    {Ordinary_Transfer_Command, Privileged_Governance_Command}"

section \<open>Operation Classification\<close>

fun rcp_transition_label :: "legal_action_kind \<Rightarrow> reg_action option" where
  "rcp_transition_label Legal_Freeze = Some FREEZE"
| "rcp_transition_label Legal_Seize = Some SEIZE"
| "rcp_transition_label Legal_Confiscate = Some CONFISCATE"
| "rcp_transition_label Legal_Restrict = Some RESTRICT"
| "rcp_transition_label Legal_Recover = None"
| "rcp_transition_label Legal_Liquidate = None"

fun operation_transition_label :: "trust_operation \<Rightarrow> reg_action option" where
  "operation_transition_label (RCP_Operation k) = rcp_transition_label k"
| "operation_transition_label (Transition_Operation a) = Some a"

fun operation_is_transfer :: "trust_operation \<Rightarrow> bool" where
  "operation_is_transfer (RCP_Operation Legal_Confiscate) = True"
| "operation_is_transfer (RCP_Operation Legal_Recover) = True"
| "operation_is_transfer (RCP_Operation Legal_Liquidate) = True"
| "operation_is_transfer _ = False"

fun operation_write_set :: "trust_operation \<Rightarrow> write_slot list" where
  "operation_write_set (RCP_Operation Legal_Freeze) =
     [Regulatory_Mode_Slot, Frozen_Amount_Slot, Case_Slot,
      Authorization_Slot, Nonce_Slot, Receipt_Slot]"
| "operation_write_set (RCP_Operation Legal_Seize) =
     [Regulatory_Mode_Slot, Custody_Slot, Frozen_Amount_Slot, Case_Slot,
      Encumbrance_Slot, Prior_Holder_Slot, Authorization_Slot, Nonce_Slot,
      Receipt_Slot]"
| "operation_write_set (RCP_Operation Legal_Confiscate) =
     [Regulatory_Mode_Slot, Balance_Slot, Custody_Slot,
      Frozen_Amount_Slot, Case_Slot, Encumbrance_Slot, Prior_Holder_Slot,
      Authorization_Slot, Nonce_Slot, Receipt_Slot]"
| "operation_write_set (RCP_Operation Legal_Recover) =
     [Regulatory_Mode_Slot, Balance_Slot, Custody_Slot,
      Frozen_Amount_Slot, Case_Slot, Encumbrance_Slot,
      Prior_Holder_Slot, Entitlement_Slot,
      Authorization_Slot, Nonce_Slot, Receipt_Slot]"
| "operation_write_set (RCP_Operation Legal_Liquidate) =
     [Regulatory_Mode_Slot, Balance_Slot, Custody_Slot,
      Frozen_Amount_Slot, Case_Slot, Encumbrance_Slot,
      Prior_Holder_Slot, Settlement_Slot,
      Authorization_Slot, Nonce_Slot, Receipt_Slot]"
| "operation_write_set (RCP_Operation Legal_Restrict) =
     [Regulatory_Mode_Slot, Case_Slot, Authorization_Slot,
      Nonce_Slot, Receipt_Slot]"
| "operation_write_set (Transition_Operation FREEZE) =
     [Regulatory_Mode_Slot, Frozen_Amount_Slot, Case_Slot,
      Authorization_Slot,
      Nonce_Slot, Receipt_Slot]"
| "operation_write_set (Transition_Operation UNFREEZE) =
     [Regulatory_Mode_Slot, Frozen_Amount_Slot, Case_Slot,
      Authorization_Slot,
      Nonce_Slot, Receipt_Slot]"
| "operation_write_set (Transition_Operation UNRESTRICT) =
     [Regulatory_Mode_Slot, Case_Slot, Authorization_Slot,
      Nonce_Slot, Receipt_Slot]"
| "operation_write_set (Transition_Operation RELEASE) =
     [Regulatory_Mode_Slot, Custody_Slot, Case_Slot, Encumbrance_Slot,
      Prior_Holder_Slot, Authorization_Slot, Nonce_Slot, Receipt_Slot]"
| "operation_write_set _ =
     [Regulatory_Mode_Slot, Case_Slot, Authorization_Slot,
      Nonce_Slot, Receipt_Slot]"

fun operation_target ::
  "trust_operation \<Rightarrow> reg_state \<Rightarrow> reg_state option"
where
  "operation_target (RCP_Operation Legal_Recover) SEIZED = Some ACTIVE"
| "operation_target (RCP_Operation Legal_Recover) _ = None"
| "operation_target (RCP_Operation Legal_Liquidate) SEIZED = Some ACTIVE"
| "operation_target (RCP_Operation Legal_Liquidate) _ = None"
| "operation_target op current =
     (case operation_transition_label op of
        None \<Rightarrow> None
      | Some a \<Rightarrow> reg_transition current a)"

fun native_operation_allowed :: "trust_operation \<Rightarrow> bool" where
  "native_operation_allowed (Transition_Operation UNFREEZE) = True"
| "native_operation_allowed (Transition_Operation UNRESTRICT) = True"
| "native_operation_allowed (Transition_Operation RELEASE) = True"
| "native_operation_allowed (Transition_Operation _) = False"
| "native_operation_allowed (RCP_Operation _) = True"

fun contextual_operation_target ::
  "trust_operation \<Rightarrow> reg_state \<Rightarrow> nat \<Rightarrow> reg_state option"
where
  "contextual_operation_target
     (RCP_Operation Legal_Freeze) FROZEN amount =
     (if amount > 0 then Some FROZEN else None)"
| "contextual_operation_target
     (Transition_Operation UNFREEZE) FROZEN amount =
     (if amount = 0 then Some ACTIVE else Some FROZEN)"
| "contextual_operation_target op current amount =
     operation_target op current"

fun external_assumptions_hold ::
  "trust_operation \<Rightarrow> entry_context \<Rightarrow> bool"
where
  "external_assumptions_hold (RCP_Operation Legal_Recover) ctx =
     context_entitlement_attested ctx"
| "external_assumptions_hold (RCP_Operation Legal_Liquidate) ctx =
     (context_settlement_attested ctx \<and>
      context_settlement_capability ctx)"
| "external_assumptions_hold _ _ = True"

fun external_semantic_rejection ::
  "trust_operation \<Rightarrow> entry_context \<Rightarrow> trust_rejection option"
where
  "external_semantic_rejection (RCP_Operation Legal_Recover) ctx =
     (if context_entitlement_attested ctx
      then None else Some External_Evidence_Denied)"
| "external_semantic_rejection (RCP_Operation Legal_Liquidate) ctx =
     (if \<not> context_settlement_capability ctx
      then Some Capability_Unsupported
      else if \<not> context_settlement_attested ctx
      then Some External_Evidence_Denied
      else None)"
| "external_semantic_rejection _ _ = None"

section \<open>Typed Authorization and Fail-Closed Normalization\<close>

definition authority_matches ::
  "trust_authorization \<Rightarrow> nat \<Rightarrow> bool"
where
  "authority_matches auth actor \<longleftrightarrow>
     actor = authorization_issuer auth \<or>
     authorization_delegate auth = Some actor"

definition authorization_payload_matches ::
  "trust_authorization \<Rightarrow> trust_operation \<Rightarrow> entry_context \<Rightarrow> bool"
where
  "authorization_payload_matches auth op ctx \<longleftrightarrow>
     authorization_operation auth = op \<and>
     authorization_chain auth = context_chain ctx \<and>
     authorization_token auth = context_token ctx \<and>
     authorization_standard_version auth = context_standard_version ctx \<and>
     authorization_subject auth = context_subject ctx \<and>
     authorization_destination auth = context_destination ctx \<and>
     authorization_amount auth = context_amount ctx \<and>
     authorization_case auth = context_case ctx \<and>
     authorization_external_commitment auth =
       context_external_commitment ctx \<and>
     authorization_proceeds_reference auth =
       context_proceeds_reference ctx \<and>
     authorization_nonce auth = context_nonce ctx"

definition authorization_binding_matches ::
  "trust_state \<Rightarrow> trust_authorization \<Rightarrow> entry_context \<Rightarrow> bool"
where
  "authorization_binding_matches st auth ctx \<longleftrightarrow>
     context_chain ctx = trust_chain st \<and>
     context_token ctx = trust_token st \<and>
     context_standard_version ctx = trust_standard_version st \<and>
     authorization_authority_epoch auth = trust_authority_epoch st \<and>
     context_authority_epoch ctx = trust_authority_epoch st \<and>
     authorization_policy_code auth = trust_policy_code st \<and>
     context_policy_code ctx = trust_policy_code st \<and>
     authorization_policy_schema auth = trust_policy_schema st \<and>
     context_policy_schema ctx = trust_policy_schema st \<and>
     authorization_policy_config auth = trust_policy_config st \<and>
     context_policy_config ctx = trust_policy_config st \<and>
     authorization_provenance_commitment auth =
       context_provenance_commitment ctx \<and>
     authorization_valid_after auth \<le> context_current_time ctx \<and>
     context_current_time ctx \<le> authorization_deadline auth \<and>
     context_valid_after ctx = authorization_valid_after auth \<and>
     context_deadline ctx = authorization_deadline auth \<and>
     authorization_pre_observation_commitment auth =
       context_pre_observation_commitment ctx \<and>
     authorization_post_observation_commitment auth =
       context_post_observation_commitment ctx"

definition transfer_shape_valid ::
  "trust_operation \<Rightarrow> entry_context \<Rightarrow> bool"
where
  "transfer_shape_valid op ctx \<longleftrightarrow>
     (\<not> operation_is_transfer op \<or>
       (case context_destination ctx of
          None \<Rightarrow> False
        | Some destination \<Rightarrow>
            destination \<noteq> context_subject ctx))"

definition observation_commitment ::
  "reg_state \<Rightarrow> nat \<Rightarrow> nat \<Rightarrow> nat \<Rightarrow>
   nat option \<Rightarrow> trust_observation"
where
  "observation_commitment mode balance frozen encumbered current_case =
     Trust_Observation mode balance frozen encumbered current_case"

definition state_observation_commitment ::
  "trust_state \<Rightarrow> entry_context \<Rightarrow> trust_observation"
where
  "state_observation_commitment st ctx =
     observation_commitment
       (trust_modes st (context_subject ctx))
       (trust_balances st (context_subject ctx))
       (trust_frozen_tokens st (context_subject ctx))
       (trust_encumbered_amount st (context_subject ctx))
       (trust_case_registry st (context_subject ctx))"

definition current_case_matches ::
  "trust_state \<Rightarrow> entry_context \<Rightarrow> bool"
where
  "current_case_matches st ctx \<longleftrightarrow>
     (trust_modes st (context_subject ctx) = ACTIVE \<or>
      trust_case_registry st (context_subject ctx) =
        Some (context_case ctx))"

definition operation_well_formed ::
  "trust_state \<Rightarrow> canonical_request \<Rightarrow> bool"
where
  "operation_well_formed st req \<longleftrightarrow>
    (let ctx = request_context req;
         op = request_operation req;
         subject = context_subject ctx;
         mode = trust_modes st subject;
         amount = context_amount ctx;
         balance = trust_balances st subject;
         encumbered = trust_encumbered_amount st subject;
         valid_destination =
           (case context_destination ctx of
              None \<Rightarrow> False
            | Some destination \<Rightarrow> destination \<noteq> subject)
     in
       case op of
         RCP_Operation Legal_Freeze \<Rightarrow>
           amount > 0 \<and> amount \<le> balance \<and>
           (mode = ACTIVE \<or> mode = RESTRICTED \<or>
            (mode = FROZEN \<and> trust_frozen_tokens st subject < amount))
       | RCP_Operation Legal_Seize \<Rightarrow>
           (mode = ACTIVE \<or> mode = FROZEN) \<and>
           amount > 0 \<and> amount \<le> balance \<and> valid_destination
       | RCP_Operation Legal_Confiscate \<Rightarrow>
           (mode = ACTIVE \<or> mode = FROZEN \<or> mode = SEIZED \<or>
            mode = RESTRICTED) \<and>
           amount > 0 \<and> amount = balance \<and> valid_destination
       | RCP_Operation Legal_Restrict \<Rightarrow> mode = ACTIVE
       | RCP_Operation Legal_Recover \<Rightarrow>
           mode = SEIZED \<and> trust_custody st subject \<noteq> None \<and>
           encumbered > 0 \<and> amount = encumbered \<and> valid_destination
       | RCP_Operation Legal_Liquidate \<Rightarrow>
           mode = SEIZED \<and> trust_custody st subject \<noteq> None \<and>
           encumbered > 0 \<and> amount = encumbered \<and> valid_destination
       | Transition_Operation UNFREEZE \<Rightarrow>
           mode = FROZEN \<and> amount < trust_frozen_tokens st subject
       | Transition_Operation UNRESTRICT \<Rightarrow>
           mode = RESTRICTED
       | Transition_Operation RELEASE \<Rightarrow>
           mode = SEIZED \<and> trust_custody st subject \<noteq> None \<and>
           encumbered > 0 \<and> amount = encumbered
       | Transition_Operation _ \<Rightarrow> False)"

definition expected_post_observation_commitment ::
  "trust_state \<Rightarrow> canonical_request \<Rightarrow> reg_state \<Rightarrow>
   trust_observation"
where
  "expected_post_observation_commitment st req target =
    (let ctx = request_context req;
         op = request_operation req;
         subject = context_subject ctx;
         balance =
           (if operation_is_transfer op
            then trust_balances st subject - context_amount ctx
            else trust_balances st subject);
         frozen =
           (case op of
              RCP_Operation Legal_Freeze \<Rightarrow> context_amount ctx
            | Transition_Operation UNFREEZE \<Rightarrow> context_amount ctx
            | RCP_Operation Legal_Seize \<Rightarrow> 0
            | RCP_Operation Legal_Confiscate \<Rightarrow> 0
            | RCP_Operation Legal_Recover \<Rightarrow> 0
            | RCP_Operation Legal_Liquidate \<Rightarrow> 0
            | Transition_Operation RELEASE \<Rightarrow> 0
            | _ \<Rightarrow> trust_frozen_tokens st subject);
         encumbered =
           (if op = RCP_Operation Legal_Seize
            then context_amount ctx
            else if op = RCP_Operation Legal_Confiscate \<or>
                    op = RCP_Operation Legal_Recover \<or>
                    op = RCP_Operation Legal_Liquidate \<or>
                    op = Transition_Operation RELEASE
            then 0
            else trust_encumbered_amount st subject);
         current_case =
           (if target = ACTIVE then None else Some (context_case ctx))
     in observation_commitment target balance frozen encumbered current_case)"

definition normalize_entrypoint ::
  "trust_state \<Rightarrow> trust_entrypoint \<Rightarrow> canonical_request option"
where
  "normalize_entrypoint st entry =
    (case entry of
       RCP_Entrypoint k ctx \<Rightarrow>
         Some \<lparr>request_operation = RCP_Operation k,
               request_context = ctx\<rparr>
     | Native_Entrypoint op ctx \<Rightarrow>
         (if native_operation_allowed op
          then Some \<lparr>request_operation = op, request_context = ctx\<rparr>
          else None)
     | ERC7943_Set_Frozen_Entrypoint new_frozen ctx \<Rightarrow>
         (let old_frozen = trust_frozen_tokens st (context_subject ctx)
          in if old_frozen < new_frozen then
               Some \<lparr>request_operation = RCP_Operation Legal_Freeze,
                     request_context =
                       ctx\<lparr>context_amount := new_frozen\<rparr>\<rparr>
             else if new_frozen < old_frozen then
               Some \<lparr>request_operation = Transition_Operation UNFREEZE,
                     request_context =
                       ctx\<lparr>context_amount := new_frozen\<rparr>\<rparr>
             else None)
     | ERC7943_Forced_Transfer_Entrypoint ctx \<Rightarrow>
         (case trust_authorizations st (context_authorization_id ctx) of
            Some auth \<Rightarrow>
              (if operation_is_transfer (authorization_operation auth)
               then Some \<lparr>request_operation = authorization_operation auth,
                          request_context = ctx\<rparr>
               else None)
          | None \<Rightarrow> None)
     | ERC3643_Profile_Entrypoint call ctx \<Rightarrow>
         (case erc3643_profile_mapping call of
            None \<Rightarrow> None
          | Some op \<Rightarrow>
              Some \<lparr>request_operation = op,
                    request_context =
                      (if call = ERC3643_Unfreeze_Address
                       then ctx\<lparr>context_amount := 0\<rparr>
                       else ctx)\<rparr>)
     | Untyped_Entrypoint _ \<Rightarrow> None)"

section \<open>State Effects\<close>

definition transfer_balances ::
  "trust_state \<Rightarrow> entry_context \<Rightarrow> (nat \<Rightarrow> nat)"
where
  "transfer_balances st ctx =
    (case context_destination ctx of
       None \<Rightarrow> trust_balances st
     | Some destination \<Rightarrow>
         (trust_balances st)
           (context_subject ctx :=
              trust_balances st (context_subject ctx) - context_amount ctx,
            destination :=
              trust_balances st destination + context_amount ctx))"

fun resulting_custody ::
  "trust_operation \<Rightarrow> entry_context \<Rightarrow>
   (nat \<Rightarrow> nat option) \<Rightarrow> (nat \<Rightarrow> nat option)"
where
  "resulting_custody (RCP_Operation Legal_Seize) ctx custody =
     custody(context_subject ctx := context_destination ctx)"
| "resulting_custody (RCP_Operation Legal_Confiscate) ctx custody =
     custody(context_subject ctx := None)"
| "resulting_custody (RCP_Operation Legal_Recover) ctx custody =
     custody(context_subject ctx := None)"
| "resulting_custody (RCP_Operation Legal_Liquidate) ctx custody =
     custody(context_subject ctx := None)"
| "resulting_custody (Transition_Operation RELEASE) ctx custody =
     custody(context_subject ctx := None)"
| "resulting_custody _ _ custody = custody"

definition successful_state ::
  "trust_state \<Rightarrow> canonical_request \<Rightarrow> trust_authorization \<Rightarrow>
   reg_state \<Rightarrow> trust_state"
where
  "successful_state st req auth target =
    (let ctx = request_context req;
         op = request_operation req;
         aid = context_authorization_id ctx;
         updated_auth =
           auth\<lparr>authorization_lifecycle := Authorization_Consumed\<rparr>;
         updated_balances =
           (if operation_is_transfer op then transfer_balances st ctx
            else trust_balances st);
         receipt =
           \<lparr>receipt_operation = op,
            receipt_authorization = aid,
            receipt_subject = context_subject ctx,
            receipt_destination = context_destination ctx,
            receipt_amount = context_amount ctx,
            receipt_case = context_case ctx,
            receipt_previous_mode = trust_modes st (context_subject ctx),
            receipt_resulting_mode = target,
            receipt_external_commitment =
              context_external_commitment ctx,
            receipt_proceeds_reference =
              context_proceeds_reference ctx,
            receipt_nonce = context_nonce ctx,
            receipt_authority_epoch = context_authority_epoch ctx,
            receipt_policy_code = context_policy_code ctx,
            receipt_policy_schema = context_policy_schema ctx,
            receipt_policy_config = context_policy_config ctx,
            receipt_provenance_commitment =
              context_provenance_commitment ctx,
            receipt_pre_observation_commitment =
              context_pre_observation_commitment ctx,
            receipt_post_observation_commitment =
              context_post_observation_commitment ctx,
            receipt_external_settlement_status =
              (if op = RCP_Operation Legal_Liquidate
               then Some (context_settlement_attested ctx)
               else None),
            receipt_write_set = operation_write_set op\<rparr>
     in st\<lparr>
          trust_modes :=
            (trust_modes st)(context_subject ctx := target),
          trust_balances := updated_balances,
         trust_frozen_tokens :=
            (case op of
               RCP_Operation Legal_Freeze \<Rightarrow>
                 (trust_frozen_tokens st)
                   (context_subject ctx := context_amount ctx)
             | Transition_Operation UNFREEZE \<Rightarrow>
                 (trust_frozen_tokens st)
                   (context_subject ctx := context_amount ctx)
             | RCP_Operation Legal_Seize \<Rightarrow>
                 (trust_frozen_tokens st)(context_subject ctx := 0)
             | RCP_Operation Legal_Confiscate \<Rightarrow>
                 (trust_frozen_tokens st)(context_subject ctx := 0)
             | RCP_Operation Legal_Recover \<Rightarrow>
                 (trust_frozen_tokens st)(context_subject ctx := 0)
             | RCP_Operation Legal_Liquidate \<Rightarrow>
                 (trust_frozen_tokens st)(context_subject ctx := 0)
             | Transition_Operation RELEASE \<Rightarrow>
                 (trust_frozen_tokens st)(context_subject ctx := 0)
             | _ \<Rightarrow> trust_frozen_tokens st),
          trust_custody := resulting_custody op ctx (trust_custody st),
          trust_case_registry :=
            (trust_case_registry st)
              (context_subject ctx :=
                (if target = ACTIVE then None
                 else Some (context_case ctx))),
          trust_encumbered_amount :=
            (if op = RCP_Operation Legal_Seize
             then (trust_encumbered_amount st)
                    (context_subject ctx := context_amount ctx)
             else if op = RCP_Operation Legal_Confiscate \<or>
                     op = RCP_Operation Legal_Recover \<or>
                     op = RCP_Operation Legal_Liquidate \<or>
                     op = Transition_Operation RELEASE
             then (trust_encumbered_amount st)
                    (context_subject ctx := 0)
             else trust_encumbered_amount st),
          trust_declared_prior_holder :=
            (if op = RCP_Operation Legal_Seize
             then (trust_declared_prior_holder st)
                    (context_subject ctx := Some (context_subject ctx))
             else if op = RCP_Operation Legal_Confiscate \<or>
                     op = RCP_Operation Legal_Recover \<or>
                     op = RCP_Operation Legal_Liquidate \<or>
                     op = Transition_Operation RELEASE
             then (trust_declared_prior_holder st)
                    (context_subject ctx := None)
             else trust_declared_prior_holder st),
          trust_settlement_commitment :=
            (if op = RCP_Operation Legal_Liquidate
             then (trust_settlement_commitment st)
                    (context_case ctx :=
                      Some (context_external_commitment ctx))
             else trust_settlement_commitment st),
          trust_proceeds_reference :=
            (if op = RCP_Operation Legal_Liquidate
             then (trust_proceeds_reference st)
                    (context_case ctx :=
                      Some (context_proceeds_reference ctx))
             else trust_proceeds_reference st),
          trust_entitlement_commitment :=
            (if op = RCP_Operation Legal_Recover
             then (trust_entitlement_commitment st)
                    (context_case ctx :=
                      Some (context_external_commitment ctx))
             else trust_entitlement_commitment st),
          trust_external_settlement_status :=
            (if op = RCP_Operation Legal_Liquidate
             then (trust_external_settlement_status st)
                    (context_case ctx :=
                      Some (context_settlement_attested ctx))
             else trust_external_settlement_status st),
          trust_cases :=
            (trust_cases st)
              (context_case ctx :=
                Some
                  \<lparr>case_record_subject = context_subject ctx,
                   case_record_amount = context_amount ctx,
                   case_record_last_operation = op,
                   case_record_mode = target,
                   case_record_terminal =
                     (target = ACTIVE \<or> target = CONFISCATED),
                   case_record_receipt_authorization = aid\<rparr>),
          trust_receipt_registry :=
            (trust_receipt_registry st)(aid := Some receipt),
          trust_authorizations :=
            (trust_authorizations st)(aid := Some updated_auth),
          trust_consumed_nonces :=
            insert (context_nonce ctx) (trust_consumed_nonces st),
          trust_last_receipt := Some receipt
        \<rparr>)"

definition canonical_precheck ::
  "trust_state \<Rightarrow> canonical_request \<Rightarrow> canonical_precheck_result"
where
  "canonical_precheck st req =
    (let ctx = request_context req;
         op = request_operation req;
         aid = context_authorization_id ctx
     in
       if \<not> context_module_ready ctx then
         Canonical_Precheck_Stop
           (Trust_Operational_Failure Policy_Module_Unavailable)
       else
         (case trust_authorizations st aid of
            None \<Rightarrow>
              Canonical_Precheck_Stop
                (Trust_Rejected Authorization_Not_Found)
          | Some auth \<Rightarrow>
              if authorization_nonce auth \<in> trust_consumed_nonces st then
                Canonical_Precheck_Stop
                  (Trust_Rejected Authorization_Replayed)
              else if authorization_lifecycle auth \<noteq> Authorization_Approved then
                Canonical_Precheck_Stop
                  (Trust_Rejected Authorization_Not_Approved)
              else if authorization_epoch auth \<noteq> trust_policy_epoch st \<or>
                      context_epoch ctx \<noteq> trust_policy_epoch st then
                Canonical_Precheck_Stop
                  (Trust_Rejected Authorization_Stale)
              else if \<not> authorization_binding_matches st auth ctx then
                Canonical_Precheck_Stop
                  (Trust_Rejected Authorization_Stale)
              else if authorization_issuer auth \<notin>
                        trust_regulatory_authorities st then
                Canonical_Precheck_Stop
                  (Trust_Rejected Actor_Not_Authorized)
              else if \<not> authority_matches auth (context_actor ctx) then
                Canonical_Precheck_Stop
                  (Trust_Rejected Actor_Not_Authorized)
              else if \<not> authorization_payload_matches auth op ctx then
                Canonical_Precheck_Stop
                  (Trust_Rejected Authorization_Mismatch)
              else if \<not> native_operation_allowed op then
                Canonical_Precheck_Stop
                  (Trust_Rejected Operation_Not_Allowed)
              else if \<not> current_case_matches st ctx then
                Canonical_Precheck_Stop
                  (Trust_Rejected Case_Mismatch)
              else if \<not> transfer_shape_valid op ctx then
                Canonical_Precheck_Stop
                  (Trust_Rejected Transfer_Target_Missing)
              else if operation_is_transfer op \<and>
                      trust_balances st (context_subject ctx) <
                        context_amount ctx then
                Canonical_Precheck_Stop
                  (Trust_Rejected Insufficient_Balance)
              else Canonical_Precheck_Pass auth))"

lemma canonical_precheck_never_stops_with_applied [simp]:
  "canonical_precheck st req \<noteq>
    Canonical_Precheck_Stop Trust_Applied"
  unfolding canonical_precheck_def
  by (auto split: option.splits if_splits simp: Let_def)

lemma canonical_precheck_pass_has_stored_authorization:
  assumes "canonical_precheck st req = Canonical_Precheck_Pass auth"
  shows
    "trust_authorizations st
      (context_authorization_id (request_context req)) = Some auth"
  using assms
  unfolding canonical_precheck_def
  by (auto split: option.splits if_splits simp: Let_def)

lemma canonical_precheck_pass_has_transfer_shape:
  assumes "canonical_precheck st req = Canonical_Precheck_Pass auth"
  shows
    "transfer_shape_valid (request_operation req) (request_context req)"
  using assms
  unfolding canonical_precheck_def
  by (auto split: option.splits if_splits simp: Let_def)

definition execute_canonical ::
  "trust_state \<Rightarrow> canonical_request \<Rightarrow> trust_state \<times> trust_outcome"
where
  "execute_canonical st req =
    (let ctx = request_context req;
         op = request_operation req
     in
       case canonical_precheck st req of
         Canonical_Precheck_Stop outcome \<Rightarrow> (st, outcome)
       | Canonical_Precheck_Pass auth \<Rightarrow>
           (case external_semantic_rejection op ctx of
              Some reason \<Rightarrow> (st, Trust_Rejected reason)
            | None \<Rightarrow>
                (case contextual_operation_target op
                        (trust_modes st (context_subject ctx))
                        (context_amount ctx) of
                   None \<Rightarrow>
                     (st, Trust_Rejected Invalid_State_Transition)
                 | Some target \<Rightarrow>
                     if \<not> operation_well_formed st req then
                       (st, Trust_Rejected Invalid_State_Transition)
                     else if
                       context_pre_observation_commitment ctx \<noteq>
                         state_observation_commitment st ctx \<or>
                       context_post_observation_commitment ctx \<noteq>
                         expected_post_observation_commitment st req target
                     then (st, Trust_Rejected Invalid_Observation)
                     else
                       (successful_state st req auth target,
                        Trust_Applied))))"

definition execute_entrypoint ::
  "trust_state \<Rightarrow> trust_entrypoint \<Rightarrow> trust_state \<times> trust_outcome"
where
  "execute_entrypoint st entry =
    (case normalize_entrypoint st entry of
       None \<Rightarrow> (st, Trust_Rejected Untyped_Request_Denied)
     | Some req \<Rightarrow> execute_canonical st req)"

definition execute_ordinary_transfer ::
  "trust_state \<Rightarrow> ordinary_transfer_command \<Rightarrow>
   trust_state \<times> trust_outcome"
where
  "execute_ordinary_transfer st command =
    (let source = ordinary_source command;
         destination = ordinary_destination command;
         amount = ordinary_amount command
     in
       if source = destination then
         (st, Trust_Rejected Transfer_Target_Missing)
       else if amount = 0 \<or>
               \<not> ordinary_baseline_clear command \<or>
               \<not> ordinary_destination_clear command \<or>
               trust_modes st source = CONFISCATED \<or>
               (trust_modes st source = RESTRICTED \<and>
                \<not> ordinary_restriction_clear command) then
         (st, Trust_Rejected Invalid_State_Transition)
       else if
         trust_balances st source -
           max (trust_frozen_tokens st source)
               (trust_encumbered_amount st source) < amount then
         (st, Trust_Rejected Insufficient_Balance)
       else
         (st\<lparr>trust_balances :=
            (trust_balances st)
              (source := trust_balances st source - amount,
               destination :=
                 trust_balances st destination + amount)\<rparr>,
          Trust_Applied))"

definition ordinary_transfer_write_set :: "write_slot list" where
  "ordinary_transfer_write_set = [Balance_Slot]"

section \<open>Authorization Lifecycle Commands\<close>

fun authorization_command_write_set ::
  "authorization_command \<Rightarrow> write_slot list"
where
  "authorization_command_write_set (Create_Authorization _ _ _) =
     [Authorization_Slot]"
| "authorization_command_write_set (Approve_Authorization _ _) =
     [Authorization_Slot]"
| "authorization_command_write_set (Cancel_Authorization _ _) =
     [Authorization_Slot]"
| "authorization_command_write_set (Delegate_Authorization _ _ _) =
     [Authorization_Slot]"
| "authorization_command_write_set (Rotate_Authority_Epoch _ _) =
     [Authority_Epoch_Slot, Policy_Change_Event_Slot]"
| "authorization_command_write_set (Rebind_Policy _ _ _ _ _) =
     [Policy_Binding_Slot, Policy_Change_Event_Slot]"

fun authorization_command_target ::
  "authorization_command \<Rightarrow> nat option"
where
  "authorization_command_target (Create_Authorization aid _ _) = Some aid"
| "authorization_command_target (Approve_Authorization aid _) = Some aid"
| "authorization_command_target (Cancel_Authorization aid _) = Some aid"
| "authorization_command_target (Delegate_Authorization aid _ _) = Some aid"
| "authorization_command_target _ = None"

definition execute_authorization_command ::
  "trust_state \<Rightarrow> authorization_command \<Rightarrow>
   trust_state \<times> authorization_command_outcome"
where
  "execute_authorization_command st command =
    (case command of
       Create_Authorization aid actor auth \<Rightarrow>
         (if actor = authorization_issuer auth \<and>
             actor \<in> trust_regulatory_authorities st
          then
            (case trust_authorizations st aid of
               None \<Rightarrow>
                 (st\<lparr>trust_authorizations :=
                       (trust_authorizations st)
                         (aid := Some
                           (auth\<lparr>authorization_lifecycle :=
                             Authorization_Created\<rparr>))\<rparr>,
                  Authorization_Command_Applied)
             | Some _ \<Rightarrow> (st, Authorization_Command_Rejected))
          else (st, Authorization_Command_Rejected))
     | Approve_Authorization aid actor \<Rightarrow>
         (case trust_authorizations st aid of
            Some auth \<Rightarrow>
              (if authorization_lifecycle auth = Authorization_Created \<and>
                  actor = authorization_issuer auth \<and>
                  actor \<in> trust_regulatory_authorities st
               then
                 (st\<lparr>trust_authorizations :=
                       (trust_authorizations st)
                         (aid := Some
                           (auth\<lparr>authorization_lifecycle :=
                             Authorization_Approved\<rparr>))\<rparr>,
                  Authorization_Command_Applied)
               else (st, Authorization_Command_Rejected))
          | None \<Rightarrow> (st, Authorization_Command_Rejected))
     | Cancel_Authorization aid actor \<Rightarrow>
         (case trust_authorizations st aid of
            Some auth \<Rightarrow>
              (if authorization_lifecycle auth \<noteq> Authorization_Consumed \<and>
                  actor = authorization_issuer auth \<and>
                  actor \<in> trust_regulatory_authorities st
               then
                 (st\<lparr>trust_authorizations :=
                       (trust_authorizations st)
                         (aid := Some
                           (auth\<lparr>authorization_lifecycle :=
                             Authorization_Cancelled\<rparr>))\<rparr>,
                  Authorization_Command_Applied)
               else (st, Authorization_Command_Rejected))
          | None \<Rightarrow> (st, Authorization_Command_Rejected))
     | Delegate_Authorization aid actor delegate \<Rightarrow>
         (case trust_authorizations st aid of
            Some auth \<Rightarrow>
              (if authorization_lifecycle auth \<noteq> Authorization_Consumed \<and>
                  actor = authorization_issuer auth \<and>
                  actor \<in> trust_regulatory_authorities st
               then
                 (st\<lparr>trust_authorizations :=
                       (trust_authorizations st)
                         (aid := Some
                           (auth\<lparr>authorization_delegate :=
                             Some delegate\<rparr>))\<rparr>,
                  Authorization_Command_Applied)
               else (st, Authorization_Command_Rejected))
          | None \<Rightarrow> (st, Authorization_Command_Rejected))
     | Rotate_Authority_Epoch actor new_epoch \<Rightarrow>
         (if actor = trust_governance_authority st \<and>
             trust_authority_epoch st < new_epoch
          then
            (st\<lparr>trust_authority_epoch := new_epoch,
                 trust_last_policy_change := Some new_epoch\<rparr>,
             Authorization_Command_Applied)
          else (st, Authorization_Command_Rejected))
     | Rebind_Policy actor code schema config new_epoch \<Rightarrow>
         (if actor = trust_governance_authority st \<and>
             trust_policy_epoch st < new_epoch
          then
            (st\<lparr>trust_policy_code := code,
                 trust_policy_schema := schema,
                 trust_policy_config := config,
                 trust_policy_epoch := new_epoch,
                 trust_last_policy_change := Some new_epoch\<rparr>,
             Authorization_Command_Applied)
          else (st, Authorization_Command_Rejected)))"

fun run_authorization_commands ::
  "authorization_command list \<Rightarrow> trust_state \<Rightarrow>
   trust_state \<times> authorization_command_outcome list"
where
  "run_authorization_commands [] st = (st, [])"
| "run_authorization_commands (command # commands) st =
     (let first = execute_authorization_command st command;
          rest = run_authorization_commands commands (fst first)
      in (fst rest, snd first # snd rest))"

theorem rejected_authorization_command_is_full_state_stutter:
  assumes
    "execute_authorization_command st command =
      (st', Authorization_Command_Rejected)"
  shows "st' = st"
  using assms
  unfolding execute_authorization_command_def
  by (cases command)
     (auto split: option.splits authorization_lifecycle.splits if_splits)

theorem successful_authorization_command_complete_frame:
  assumes execution:
    "execute_authorization_command st command =
      (st', Authorization_Command_Applied)"
      and unrelated:
    "authorization_command_target command \<noteq> Some other_authorization"
  shows
    "trust_balances st' = trust_balances st \<and>
     trust_total_supply st' = trust_total_supply st \<and>
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
     trust_authorizations st' other_authorization =
       trust_authorizations st other_authorization \<and>
     trust_consumed_nonces st' = trust_consumed_nonces st \<and>
     trust_last_receipt st' = trust_last_receipt st \<and>
     trust_last_governance_receipt st' =
       trust_last_governance_receipt st \<and>
     trust_chain st' = trust_chain st \<and>
     trust_token st' = trust_token st \<and>
     trust_standard_version st' = trust_standard_version st \<and>
     (Policy_Binding_Slot \<notin>
        set (authorization_command_write_set command) \<longrightarrow>
       trust_policy_epoch st' = trust_policy_epoch st \<and>
       trust_policy_code st' = trust_policy_code st \<and>
       trust_policy_schema st' = trust_policy_schema st \<and>
       trust_policy_config st' = trust_policy_config st) \<and>
     (Authority_Epoch_Slot \<notin>
        set (authorization_command_write_set command) \<longrightarrow>
       trust_authority_epoch st' = trust_authority_epoch st) \<and>
     (Policy_Change_Event_Slot \<notin>
        set (authorization_command_write_set command) \<longrightarrow>
       trust_last_policy_change st' = trust_last_policy_change st) \<and>
     trust_governance_authority st' = trust_governance_authority st \<and>
     trust_regulatory_authorities st' =
       trust_regulatory_authorities st \<and>
     trust_auxiliary st' = trust_auxiliary st"
  using assms
  unfolding execute_authorization_command_def
  by (cases command)
     (auto split: option.splits authorization_lifecycle.splits if_splits)

section \<open>Core Safety and Frame Lemmas\<close>

theorem every_entrypoint_converges_on_canonical_execution:
  "execute_entrypoint st entry =
    (case normalize_entrypoint st entry of
       None \<Rightarrow> (st, Trust_Rejected Untyped_Request_Denied)
     | Some req \<Rightarrow> execute_canonical st req)"
  by (simp add: execute_entrypoint_def)

theorem untyped_entrypoint_is_fail_closed:
  "execute_entrypoint st (Untyped_Entrypoint tag) =
     (st, Trust_Rejected Untyped_Request_Denied)"
  by (simp add: execute_entrypoint_def normalize_entrypoint_def)

theorem privileged_governance_is_explicitly_in_model_execution_taxonomy:
  "Privileged_Governance_Command \<in> model_execution_taxonomy"
  by (simp add: model_execution_taxonomy_def)

lemma contextual_operation_target_from_confiscated_is_none:
  "contextual_operation_target op CONFISCATED amount = None"
proof (cases op)
  case (RCP_Operation k)
  then show ?thesis by (cases k) simp_all
next
  case (Transition_Operation action)
  then show ?thesis by (cases action) simp_all
qed

theorem confiscated_canonical_execution_cannot_apply:
  assumes
    "trust_modes st (context_subject (request_context req)) = CONFISCATED"
  shows
    "snd (execute_canonical st req) \<noteq> Trust_Applied"
  using assms contextual_operation_target_from_confiscated_is_none
  unfolding execute_canonical_def
  by (auto split: canonical_precheck_result.splits option.splits
      if_splits simp: Let_def)

theorem confiscated_entrypoint_execution_cannot_apply:
  assumes
    "\<And>req. normalize_entrypoint st entry = Some req \<Longrightarrow>
      trust_modes st (context_subject (request_context req)) = CONFISCATED"
  shows
    "snd (execute_entrypoint st entry) \<noteq> Trust_Applied"
  using assms confiscated_canonical_execution_cannot_apply
  unfolding execute_entrypoint_def
  by (auto split: option.splits)

theorem confiscated_ordinary_source_is_terminal:
  assumes "trust_modes st (ordinary_source command) = CONFISCATED"
  shows
    "fst (execute_ordinary_transfer st command) = st \<and>
     snd (execute_ordinary_transfer st command) \<noteq> Trust_Applied"
  using assms
  unfolding execute_ordinary_transfer_def
  by (auto split: if_splits simp: Let_def)

theorem all_reversal_write_sets_cover_their_actual_state_classes:
  "operation_write_set (Transition_Operation UNFREEZE) =
     [Regulatory_Mode_Slot, Frozen_Amount_Slot, Case_Slot,
      Authorization_Slot, Nonce_Slot, Receipt_Slot] \<and>
   operation_write_set (Transition_Operation UNRESTRICT) =
     [Regulatory_Mode_Slot, Case_Slot, Authorization_Slot,
      Nonce_Slot, Receipt_Slot] \<and>
   operation_write_set (Transition_Operation RELEASE) =
     [Regulatory_Mode_Slot, Custody_Slot, Case_Slot, Encumbrance_Slot,
      Prior_Holder_Slot, Authorization_Slot, Nonce_Slot, Receipt_Slot]"
  by simp

theorem successful_ordinary_transfer_writes_only_two_balance_accounts:
  assumes execution:
    "execute_ordinary_transfer st command = (st', Trust_Applied)"
      and unrelated:
    "account \<noteq> ordinary_source command"
    "account \<noteq> ordinary_destination command"
  shows
    "ordinary_transfer_write_set = [Balance_Slot] \<and>
     trust_balances st' (ordinary_source command) =
       trust_balances st (ordinary_source command) -
         ordinary_amount command \<and>
     trust_balances st' (ordinary_destination command) =
       trust_balances st (ordinary_destination command) +
         ordinary_amount command \<and>
     trust_balances st' account = trust_balances st account \<and>
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
     trust_total_supply st' = trust_total_supply st \<and>
     trust_allowances st' = trust_allowances st \<and>
     trust_authorizations st' = trust_authorizations st \<and>
     trust_consumed_nonces st' = trust_consumed_nonces st \<and>
     trust_last_receipt st' = trust_last_receipt st \<and>
     trust_last_governance_receipt st' =
       trust_last_governance_receipt st \<and>
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
     trust_auxiliary st' = trust_auxiliary st"
  using assms
  unfolding execute_ordinary_transfer_def ordinary_transfer_write_set_def
  by (auto split: if_splits simp: Let_def)

theorem rejected_ordinary_transfer_is_full_state_stutter:
  assumes
    "execute_ordinary_transfer st command =
      (st', Trust_Rejected reason)"
  shows "st' = st"
  using assms
  unfolding execute_ordinary_transfer_def
  by (auto split: if_splits simp: Let_def)

theorem module_failure_has_no_state_effect:
  assumes "context_module_ready (request_context req) = False"
  shows "execute_canonical st req =
    (st, Trust_Operational_Failure Policy_Module_Unavailable)"
  using assms
  by (simp add: execute_canonical_def canonical_precheck_def Let_def)

theorem canonical_rejection_is_full_state_stutter:
  assumes
    "execute_canonical st req = (st', Trust_Rejected reason)"
  shows "st' = st"
  using assms
  unfolding execute_canonical_def
  by (auto split: canonical_precheck_result.splits option.splits
      if_splits simp: Let_def)

theorem canonical_operational_failure_is_full_state_stutter:
  assumes
    "execute_canonical st req =
      (st', Trust_Operational_Failure reason)"
  shows "st' = st"
  using assms
  unfolding execute_canonical_def
  by (auto split: canonical_precheck_result.splits option.splits
      if_splits simp: Let_def)

theorem entrypoint_rejection_is_full_state_stutter:
  assumes
    "execute_entrypoint st entry = (st', Trust_Rejected reason)"
  shows "st' = st"
  using assms canonical_rejection_is_full_state_stutter
  unfolding execute_entrypoint_def
  by (auto split: option.splits)

theorem entrypoint_rejection_pair_from_outcome:
  assumes
    "snd (execute_entrypoint st entry) = Trust_Rejected reason"
  shows
    "execute_entrypoint st entry = (st, Trust_Rejected reason)"
proof -
  obtain st' outcome where
    execution: "execute_entrypoint st entry = (st', outcome)"
    by (cases "execute_entrypoint st entry") auto
  then have "outcome = Trust_Rejected reason"
    using assms by simp
  then have "st' = st"
    using entrypoint_rejection_is_full_state_stutter execution by simp
  then show ?thesis
    using execution \<open>outcome = Trust_Rejected reason\<close> by simp
qed

theorem entrypoint_operational_failure_is_full_state_stutter:
  assumes
    "execute_entrypoint st entry =
      (st', Trust_Operational_Failure reason)"
  shows "st' = st"
  using assms canonical_operational_failure_is_full_state_stutter
  unfolding execute_entrypoint_def
  by (auto split: option.splits)

theorem successful_execution_preserves_policy_epoch:
  assumes "execute_canonical st req = (st', Trust_Applied)"
  shows "trust_policy_epoch st' = trust_policy_epoch st"
  using assms
  unfolding execute_canonical_def successful_state_def
  by (auto split: canonical_precheck_result.splits option.splits
      if_splits simp: Let_def)

theorem successful_execution_preserves_auxiliary_state:
  assumes "execute_canonical st req = (st', Trust_Applied)"
  shows "trust_auxiliary st' = trust_auxiliary st"
  using assms
  unfolding execute_canonical_def successful_state_def
  by (auto split: canonical_precheck_result.splits option.splits
      if_splits simp: Let_def)

lemma execute_canonical_applied_precheck:
  assumes "execute_canonical st req = (st', Trust_Applied)"
  obtains auth where
    "canonical_precheck st req = Canonical_Precheck_Pass auth"
  using assms
  unfolding execute_canonical_def
  by (auto split: canonical_precheck_result.splits option.splits
      if_splits simp: Let_def)

lemma execute_canonical_applied_structure:
  assumes "execute_canonical st req = (st', Trust_Applied)"
  obtains auth target where
    "trust_authorizations st
       (context_authorization_id (request_context req)) = Some auth"
    "contextual_operation_target (request_operation req)
       (trust_modes st (context_subject (request_context req)))
       (context_amount (request_context req)) = Some target"
    "st' = successful_state st req auth target"
proof -
  obtain auth where
    precheck:
      "canonical_precheck st req = Canonical_Precheck_Pass auth"
    using execute_canonical_applied_precheck[OF assms] by blast
  have stored:
    "trust_authorizations st
      (context_authorization_id (request_context req)) = Some auth"
    using canonical_precheck_pass_has_stored_authorization[OF precheck] .
  obtain target where
    target:
      "contextual_operation_target (request_operation req)
        (trust_modes st (context_subject (request_context req)))
        (context_amount (request_context req)) = Some target"
    and result: "st' = successful_state st req auth target"
    using assms precheck
    unfolding execute_canonical_def
    by (auto split: option.splits if_splits simp: Let_def)
  show thesis
    using that[OF stored target result] .
qed

theorem successful_execution_complete_frame:
  assumes exec: "execute_canonical st req = (st', Trust_Applied)"
      and account:
        "other_account \<noteq> context_subject (request_context req)"
      and destination:
        "context_destination (request_context req) \<noteq> Some other_account"
      and case_slot:
        "other_case \<noteq> context_case (request_context req)"
      and authorization:
        "other_authorization \<noteq>
          context_authorization_id (request_context req)"
      and nonce:
        "other_nonce \<noteq> context_nonce (request_context req)"
  shows
    "trust_modes st' other_account = trust_modes st other_account \<and>
     trust_balances st' other_account = trust_balances st other_account \<and>
     trust_frozen_tokens st' other_account =
       trust_frozen_tokens st other_account \<and>
     trust_custody st' other_account = trust_custody st other_account \<and>
     trust_case_registry st' other_account =
       trust_case_registry st other_account \<and>
     trust_encumbered_amount st' other_account =
       trust_encumbered_amount st other_account \<and>
     trust_declared_prior_holder st' other_account =
       trust_declared_prior_holder st other_account \<and>
     trust_settlement_commitment st' other_case =
       trust_settlement_commitment st other_case \<and>
     trust_proceeds_reference st' other_case =
       trust_proceeds_reference st other_case \<and>
     trust_entitlement_commitment st' other_case =
       trust_entitlement_commitment st other_case \<and>
     trust_external_settlement_status st' other_case =
       trust_external_settlement_status st other_case \<and>
     trust_cases st' other_case = trust_cases st other_case \<and>
     trust_receipt_registry st' other_authorization =
       trust_receipt_registry st other_authorization \<and>
     trust_total_supply st' = trust_total_supply st \<and>
     trust_allowances st' = trust_allowances st \<and>
     trust_authorizations st' other_authorization =
       trust_authorizations st other_authorization \<and>
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
     trust_last_governance_receipt st' =
       trust_last_governance_receipt st \<and>
     trust_auxiliary st' = trust_auxiliary st"
proof -
  obtain auth target where
    result: "st' = successful_state st req auth target"
    using execute_canonical_applied_structure[OF exec] by blast
  show ?thesis
    using assms result
    unfolding successful_state_def transfer_balances_def
    by (auto split: option.splits if_splits trust_operation.splits
        legal_action_kind.splits reg_action.splits simp: Let_def)
qed

lemma successful_state_observation_is_expected:
  assumes
    "transfer_shape_valid (request_operation req) (request_context req)"
  shows
    "state_observation_commitment
       (successful_state st req auth target) (request_context req) =
     expected_post_observation_commitment st req target"
  using assms
  unfolding state_observation_commitment_def
    expected_post_observation_commitment_def successful_state_def
    transfer_balances_def transfer_shape_valid_def
  by (auto split: trust_operation.splits legal_action_kind.splits
      reg_action.splits option.splits if_splits simp: Let_def)

theorem successful_execution_exact_core_effects:
  assumes execution: "execute_canonical st req = (st', Trust_Applied)"
  obtains auth target where
    "trust_authorizations st
       (context_authorization_id (request_context req)) = Some auth"
    "contextual_operation_target (request_operation req)
       (trust_modes st (context_subject (request_context req)))
       (context_amount (request_context req)) = Some target"
    "trust_modes st' (context_subject (request_context req)) = target"
    "trust_balances st' =
       (if operation_is_transfer (request_operation req)
        then transfer_balances st (request_context req)
        else trust_balances st)"
    "trust_custody st' =
       resulting_custody (request_operation req) (request_context req)
         (trust_custody st)"
    "trust_case_registry st' (context_subject (request_context req)) =
       (if target = ACTIVE then None
        else Some (context_case (request_context req)))"
    "trust_cases st' (context_case (request_context req)) =
       Some
         \<lparr>case_record_subject =
             context_subject (request_context req),
          case_record_amount = context_amount (request_context req),
          case_record_last_operation = request_operation req,
          case_record_mode = target,
          case_record_terminal =
            (target = ACTIVE \<or> target = CONFISCATED),
          case_record_receipt_authorization =
            context_authorization_id (request_context req)\<rparr>"
    "authorization_lifecycle
       (the (trust_authorizations st'
         (context_authorization_id (request_context req)))) =
       Authorization_Consumed"
    "context_nonce (request_context req) \<in> trust_consumed_nonces st'"
    "trust_receipt_registry st'
       (context_authorization_id (request_context req)) =
       trust_last_receipt st'"
    "context_pre_observation_commitment (request_context req) =
       state_observation_commitment st (request_context req)"
    "context_post_observation_commitment (request_context req) =
       state_observation_commitment st' (request_context req)"
proof -
  obtain auth target where
    auth:
      "trust_authorizations st
        (context_authorization_id (request_context req)) = Some auth"
    and target:
      "contextual_operation_target (request_operation req)
        (trust_modes st (context_subject (request_context req)))
        (context_amount (request_context req)) = Some target"
    and result: "st' = successful_state st req auth target"
    using execute_canonical_applied_structure[OF execution] by blast
  obtain checked_auth where
    precheck:
      "canonical_precheck st req =
        Canonical_Precheck_Pass checked_auth"
    using execute_canonical_applied_precheck[OF execution] by blast
  have shape:
    "transfer_shape_valid (request_operation req) (request_context req)"
    using canonical_precheck_pass_has_transfer_shape[OF precheck] .
  have observations:
    "context_pre_observation_commitment (request_context req) =
       state_observation_commitment st (request_context req) \<and>
     context_post_observation_commitment (request_context req) =
       expected_post_observation_commitment st req target"
    using execution target precheck
    unfolding execute_canonical_def
    by (auto split: option.splits if_splits simp: Let_def)
  have checked:
    "transfer_shape_valid (request_operation req) (request_context req) \<and>
     context_pre_observation_commitment (request_context req) =
       state_observation_commitment st (request_context req) \<and>
     context_post_observation_commitment (request_context req) =
       expected_post_observation_commitment st req target"
    using shape observations by blast
  have post:
    "state_observation_commitment st' (request_context req) =
       expected_post_observation_commitment st req target"
    using successful_state_observation_is_expected[of req st auth target]
      checked result by simp
  show thesis
    apply (rule that[OF auth target])
    using checked post result
    unfolding successful_state_def
    by (auto simp: Let_def)
qed

theorem successful_execution_writes_applied_receipt_last:
  assumes "execute_canonical st req = (st', Trust_Applied)"
  obtains target auth where
    "contextual_operation_target (request_operation req)
       (trust_modes st (context_subject (request_context req)))
       (context_amount (request_context req)) = Some target"
    "trust_authorizations st
       (context_authorization_id (request_context req)) = Some auth"
    "trust_last_receipt st' =
       Some
        \<lparr>receipt_operation = request_operation req,
         receipt_authorization =
           context_authorization_id (request_context req),
         receipt_subject = context_subject (request_context req),
         receipt_destination =
           context_destination (request_context req),
         receipt_amount = context_amount (request_context req),
         receipt_case = context_case (request_context req),
         receipt_previous_mode =
           trust_modes st (context_subject (request_context req)),
         receipt_resulting_mode = target,
         receipt_external_commitment =
           context_external_commitment (request_context req),
         receipt_proceeds_reference =
           context_proceeds_reference (request_context req),
         receipt_nonce = context_nonce (request_context req),
         receipt_authority_epoch =
           context_authority_epoch (request_context req),
         receipt_policy_code = context_policy_code (request_context req),
         receipt_policy_schema = context_policy_schema (request_context req),
         receipt_policy_config = context_policy_config (request_context req),
         receipt_provenance_commitment =
           context_provenance_commitment (request_context req),
         receipt_pre_observation_commitment =
           context_pre_observation_commitment (request_context req),
         receipt_post_observation_commitment =
           context_post_observation_commitment (request_context req),
         receipt_external_settlement_status =
           (if request_operation req = RCP_Operation Legal_Liquidate
            then Some
              (context_settlement_attested (request_context req))
            else None),
         receipt_write_set = operation_write_set (request_operation req)\<rparr>"
proof -
  obtain target auth where
    auth:
      "trust_authorizations st
        (context_authorization_id (request_context req)) = Some auth"
    and target:
      "contextual_operation_target (request_operation req)
        (trust_modes st (context_subject (request_context req)))
        (context_amount (request_context req)) = Some target"
    and result: "st' = successful_state st req auth target"
    using execute_canonical_applied_structure[OF assms] by blast
  show thesis
    using that[OF target auth]
    unfolding result successful_state_def
    by (simp add: Let_def)
qed

end
