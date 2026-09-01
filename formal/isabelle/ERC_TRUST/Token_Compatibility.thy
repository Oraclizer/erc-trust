(*
  ERC-TRUST compatibility boundary.

  ERC-7943 is modelled as the required thin token-interface adapter.
  ERC-3643 is an optional named profile.  Neither interface supplies legal
  truth; both must resolve to a typed, current authorization.
*)

theory Token_Compatibility
  imports RCP_Action_Mapping
begin

section \<open>ERC-7943 Adapter Semantics\<close>

theorem erc7943_frozen_amount_increase_converges_to_freeze:
  assumes
    "trust_frozen_tokens st (context_subject ctx) < new_frozen"
  shows
    "normalize_entrypoint st
       (ERC7943_Set_Frozen_Entrypoint new_frozen ctx) =
      Some \<lparr>request_operation = RCP_Operation Legal_Freeze,
            request_context = ctx\<lparr>context_amount := new_frozen\<rparr>\<rparr>"
  using assms by (simp add: normalize_entrypoint_def Let_def)

theorem erc7943_frozen_amount_decrease_requires_explicit_unfreeze:
  assumes
    "new_frozen < trust_frozen_tokens st (context_subject ctx)"
  shows
    "normalize_entrypoint st
       (ERC7943_Set_Frozen_Entrypoint new_frozen ctx) = None"
  using assms by (simp add: normalize_entrypoint_def Let_def)

theorem erc7943_unchanged_frozen_amount_has_no_typed_state_change:
  assumes
    "new_frozen = trust_frozen_tokens st (context_subject ctx)"
  shows
    "normalize_entrypoint st
       (ERC7943_Set_Frozen_Entrypoint new_frozen ctx) = None"
  using assms by (simp add: normalize_entrypoint_def Let_def)

theorem erc7943_forced_transfer_requires_typed_binding:
  assumes
    "trust_authorizations st (context_authorization_id ctx) = Some auth"
    "operation_is_transfer (authorization_operation auth)"
  shows
    "normalize_entrypoint st (ERC7943_Forced_Transfer_Entrypoint ctx) =
      Some \<lparr>request_operation = authorization_operation auth,
            request_context = ctx\<rparr>"
  using assms by (simp add: normalize_entrypoint_def)

theorem erc7943_forced_transfer_fails_closed_without_binding:
  assumes
    "trust_authorizations st (context_authorization_id ctx) = None"
  shows
    "execute_entrypoint st (ERC7943_Forced_Transfer_Entrypoint ctx) =
      (st, Trust_Rejected Untyped_Request_Denied)"
  using assms
  by (simp add: execute_entrypoint_def normalize_entrypoint_def)

theorem erc7943_nontransfer_binding_is_not_reinterpreted:
  assumes
    "trust_authorizations st (context_authorization_id ctx) = Some auth"
    "\<not> operation_is_transfer (authorization_operation auth)"
  shows
    "execute_entrypoint st (ERC7943_Forced_Transfer_Entrypoint ctx) =
      (st, Trust_Rejected Untyped_Request_Denied)"
  using assms
  by (simp add: execute_entrypoint_def normalize_entrypoint_def)

theorem native_forward_transition_labels_are_not_executable:
  "normalize_entrypoint st
      (Native_Entrypoint (Transition_Operation FREEZE) ctx) = None \<and>
   normalize_entrypoint st
      (Native_Entrypoint (Transition_Operation SEIZE) ctx) = None \<and>
   normalize_entrypoint st
      (Native_Entrypoint (Transition_Operation CONFISCATE) ctx) = None \<and>
   normalize_entrypoint st
      (Native_Entrypoint (Transition_Operation RESTRICT) ctx) = None"
  by (simp add: normalize_entrypoint_def)

theorem native_forward_transition_attempt_is_full_state_stutter:
  "execute_entrypoint st
      (Native_Entrypoint (Transition_Operation action) ctx) =
    (if action = UNFREEZE \<or> action = UNRESTRICT \<or> action = RELEASE
     then execute_canonical st
       \<lparr>request_operation = Transition_Operation action,
        request_context = ctx\<rparr>
     else (st, Trust_Rejected Untyped_Request_Denied))"
  by (cases action)
     (simp_all add: execute_entrypoint_def normalize_entrypoint_def)

section \<open>ERC-7943 Views and Detailed TRUST Assessment\<close>

datatype dependency_assessment =
    Dependency_Allow
  | Dependency_Deny
  | Dependency_Failure

fun erc7943_boolean_view :: "dependency_assessment \<Rightarrow> bool" where
  "erc7943_boolean_view Dependency_Allow = True"
| "erc7943_boolean_view Dependency_Deny = False"
| "erc7943_boolean_view Dependency_Failure = False"

fun trust_detailed_assessment ::
  "dependency_assessment \<Rightarrow> trust_outcome option"
where
  "trust_detailed_assessment Dependency_Allow = None"
| "trust_detailed_assessment Dependency_Deny =
     Some (Trust_Rejected Authorization_Mismatch)"
| "trust_detailed_assessment Dependency_Failure =
     Some (Trust_Operational_Failure Policy_Module_Unavailable)"

definition erc7943_can_transfer ::
  "dependency_assessment \<Rightarrow> nat \<Rightarrow> nat \<Rightarrow> nat \<Rightarrow> bool"
where
  "erc7943_can_transfer assessment balance frozen amount \<longleftrightarrow>
     erc7943_boolean_view assessment \<and>
     (balance < amount \<or> amount \<le> balance - min balance frozen)"

definition erc7943_get_frozen_tokens ::
  "trust_state \<Rightarrow> nat \<Rightarrow> nat"
where
  "erc7943_get_frozen_tokens st account = trust_frozen_tokens st account"

theorem dependency_failure_is_false_for_erc7943_and_detailed_for_trust:
  "\<not> erc7943_boolean_view Dependency_Failure \<and>
   trust_detailed_assessment Dependency_Failure =
     Some (Trust_Operational_Failure Policy_Module_Unavailable)"
  by simp

theorem erc7943_frozen_amount_is_absolute_not_balance_bounded:
  assumes "trust_frozen_tokens st account > trust_balances st account"
  shows
    "erc7943_get_frozen_tokens st account > trust_balances st account"
  using assms by (simp add: erc7943_get_frozen_tokens_def)

theorem erc7943_permission_view_does_not_replace_base_balance_check:
  assumes "balance < amount"
  shows
    "erc7943_can_transfer Dependency_Allow balance frozen amount"
  using assms by (simp add: erc7943_can_transfer_def)

section \<open>Optional ERC-3643 Profile\<close>

theorem erc3643_profile_is_an_explicit_subset:
  "call \<in> supported_erc3643_profile_calls \<longleftrightarrow>
   erc3643_profile_mapping call \<noteq> None"
  by (cases call)
     (simp_all add: supported_erc3643_profile_calls_def)

theorem erc3643_generic_forced_transfer_is_not_assigned_legal_meaning:
  "erc3643_profile_mapping ERC3643_Forced_Transfer = None"
  by simp

theorem declared_erc3643_profile_entrypoint_converges:
  assumes "erc3643_profile_mapping call = Some op"
  shows
    "normalize_entrypoint st (ERC3643_Profile_Entrypoint call ctx) =
      Some \<lparr>request_operation = op,
            request_context =
              (if call = ERC3643_Unfreeze_Address
               then ctx\<lparr>context_amount := 0\<rparr> else ctx)\<rparr>"
  using assms by (cases call) (simp_all add: normalize_entrypoint_def)

theorem unsupported_erc3643_profile_entrypoint_fails_closed:
  assumes "erc3643_profile_mapping call = None"
  shows
    "execute_entrypoint st (ERC3643_Profile_Entrypoint call ctx) =
      (st, Trust_Rejected Untyped_Request_Denied)"
  using assms
  by (cases call)
     (simp_all add: execute_entrypoint_def normalize_entrypoint_def)

section \<open>Assume-Guarantee Boundary for External Modules\<close>

record external_module_contract =
  module_available       :: bool
  module_evidence_typed  :: bool
  module_evidence_fresh  :: bool
  module_result_authentic :: bool

definition external_module_assumption ::
  "external_module_contract \<Rightarrow> bool"
where
  "external_module_assumption contract \<longleftrightarrow>
     module_available contract \<and>
     module_evidence_typed contract \<and>
     module_evidence_fresh contract \<and>
     module_result_authentic contract"

definition external_module_guarantee ::
  "external_module_contract \<Rightarrow> entry_context \<Rightarrow> entry_context"
where
  "external_module_guarantee contract ctx =
    ctx\<lparr>context_module_ready := external_module_assumption contract\<rparr>"

theorem external_module_contract_fails_closed:
  fixes req :: canonical_request
  assumes "\<not> external_module_assumption contract"
  defines "ctx' \<equiv> external_module_guarantee contract (request_context req)"
  defines "req' \<equiv> req\<lparr>request_context := ctx'\<rparr>"
  shows "execute_canonical st req' =
    (st, Trust_Operational_Failure Policy_Module_Unavailable)"
  using assms
  by (simp add: execute_canonical_def canonical_precheck_def
      external_module_guarantee_def
      ctx'_def req'_def Let_def)

section \<open>Typed Entitlement and Settlement Provider Results\<close>

datatype entitlement_provider_result =
    Entitlement_Allowed nat
  | Entitlement_Denied
  | Entitlement_Provider_Failure

datatype settlement_provider_result =
    Settlement_Allowed nat nat nat
  | Settlement_Denied
  | Settlement_Provider_Failure
  | Settlement_Capability_Unsupported

fun entitlement_result_context ::
  "entitlement_provider_result \<Rightarrow> entry_context \<Rightarrow> entry_context"
where
  "entitlement_result_context (Entitlement_Allowed commitment) ctx =
     ctx\<lparr>context_external_commitment := commitment,
          context_module_ready := True,
          context_entitlement_attested := True\<rparr>"
| "entitlement_result_context Entitlement_Denied ctx =
     ctx\<lparr>context_module_ready := True,
          context_entitlement_attested := False\<rparr>"
| "entitlement_result_context Entitlement_Provider_Failure ctx =
     ctx\<lparr>context_module_ready := False,
          context_entitlement_attested := False\<rparr>"

fun settlement_result_context ::
  "settlement_provider_result \<Rightarrow> entry_context \<Rightarrow> entry_context"
where
  "settlement_result_context
     (Settlement_Allowed commitment proceeds destination) ctx =
     ctx\<lparr>context_external_commitment := commitment,
          context_proceeds_reference := proceeds,
          context_destination := Some destination,
          context_module_ready := True,
          context_settlement_attested := True,
          context_settlement_capability := True\<rparr>"
| "settlement_result_context Settlement_Denied ctx =
     ctx\<lparr>context_module_ready := True,
          context_settlement_attested := False,
          context_settlement_capability := True\<rparr>"
| "settlement_result_context Settlement_Provider_Failure ctx =
     ctx\<lparr>context_module_ready := False,
          context_settlement_attested := False\<rparr>"
| "settlement_result_context Settlement_Capability_Unsupported ctx =
     ctx\<lparr>context_module_ready := True,
          context_settlement_attested := False,
          context_settlement_capability := False\<rparr>"

theorem entitlement_provider_result_binding_is_exact:
  "context_external_commitment
      (entitlement_result_context (Entitlement_Allowed commitment) ctx) =
      commitment \<and>
   context_module_ready
      (entitlement_result_context (Entitlement_Allowed commitment) ctx) \<and>
   context_entitlement_attested
      (entitlement_result_context (Entitlement_Allowed commitment) ctx)"
  by simp

theorem settlement_provider_result_binding_is_exact:
  "context_external_commitment
      (settlement_result_context
        (Settlement_Allowed commitment proceeds destination) ctx) =
      commitment \<and>
   context_proceeds_reference
      (settlement_result_context
        (Settlement_Allowed commitment proceeds destination) ctx) =
      proceeds \<and>
   context_destination
      (settlement_result_context
        (Settlement_Allowed commitment proceeds destination) ctx) =
      Some destination \<and>
   context_module_ready
      (settlement_result_context
        (Settlement_Allowed commitment proceeds destination) ctx) \<and>
   context_settlement_attested
      (settlement_result_context
        (Settlement_Allowed commitment proceeds destination) ctx) \<and>
   context_settlement_capability
      (settlement_result_context
        (Settlement_Allowed commitment proceeds destination) ctx)"
  by simp

theorem entitlement_provider_denial_is_semantic_denial:
  "external_semantic_rejection (RCP_Operation Legal_Recover)
     (entitlement_result_context Entitlement_Denied ctx) =
   Some External_Evidence_Denied"
  by simp

theorem settlement_provider_denial_and_unsupported_are_distinct:
  "external_semantic_rejection (RCP_Operation Legal_Liquidate)
      (settlement_result_context Settlement_Denied ctx) =
      Some External_Evidence_Denied \<and>
   external_semantic_rejection (RCP_Operation Legal_Liquidate)
      (settlement_result_context
        Settlement_Capability_Unsupported ctx) =
      Some Capability_Unsupported"
  by simp

theorem entitlement_provider_failure_is_full_state_stutter:
  "execute_canonical st
     (req\<lparr>request_context :=
       entitlement_result_context Entitlement_Provider_Failure
         (request_context req)\<rparr>) =
   (st, Trust_Operational_Failure Policy_Module_Unavailable)"
  by (simp add: execute_canonical_def canonical_precheck_def Let_def)

theorem settlement_provider_failure_is_full_state_stutter:
  "execute_canonical st
     (req\<lparr>request_context :=
       settlement_result_context Settlement_Provider_Failure
         (request_context req)\<rparr>) =
   (st, Trust_Operational_Failure Policy_Module_Unavailable)"
  by (simp add: execute_canonical_def canonical_precheck_def Let_def)

theorem entitlement_provider_commitment_mismatch_breaks_authorization_payload:
  assumes
    "authorization_external_commitment auth \<noteq> commitment"
  shows
    "\<not> authorization_payload_matches auth op
      (entitlement_result_context
        (Entitlement_Allowed commitment) ctx)"
  using assms
  by (simp add: authorization_payload_matches_def)

theorem settlement_provider_binding_mismatch_breaks_authorization_payload:
  assumes
    "authorization_external_commitment auth \<noteq> commitment \<or>
     authorization_proceeds_reference auth \<noteq> proceeds \<or>
     authorization_destination auth \<noteq> Some destination"
  shows
    "\<not> authorization_payload_matches auth op
      (settlement_result_context
        (Settlement_Allowed commitment proceeds destination) ctx)"
  using assms
  by (auto simp: authorization_payload_matches_def)

theorem compatibility_does_not_expand_the_claim_boundary:
  "normalize_entrypoint st (Untyped_Entrypoint tag) = None"
  by (simp add: normalize_entrypoint_def)

end
