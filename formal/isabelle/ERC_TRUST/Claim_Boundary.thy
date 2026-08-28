(*
  ERC-TRUST claim boundary.

  Allowed claim:
    mechanically verified regulatory dynamics over the declared domain.

  In particular, an Applied result does not prove legal title, lawful
  forfeiture, actual sale, settlement finality, debt discharge, or rightful
  ownership.  The kernel binds declared evidence and provider responses; it
  does not decide whether their off-chain propositions are true.
*)

theory Claim_Boundary
  imports Executable_Regulatory_Kernel
begin

record external_legal_world =
  world_title_retained      :: bool
  world_forfeiture_lawful   :: bool
  world_sale_occurred       :: bool
  world_debt_discharged     :: bool
  world_recipient_rightful  :: bool

datatype verified_claim =
    Declared_Domain_Dynamics
  | Typed_Authorization_Consumption
  | Declared_Evidence_Binding
  | Abstract_Frame_Preservation

definition allowed_verified_claims :: "verified_claim set" where
  "allowed_verified_claims =
    {Declared_Domain_Dynamics, Typed_Authorization_Consumption,
     Declared_Evidence_Binding, Abstract_Frame_Preservation}"

definition core_observation ::
  "external_legal_world \<Rightarrow> trust_state \<Rightarrow> trust_entrypoint \<Rightarrow>
   trust_state \<times> trust_outcome"
where
  "core_observation world st entry = execute_entrypoint st entry"

definition world_with_all_external_truths :: external_legal_world where
  "world_with_all_external_truths =
    \<lparr>world_title_retained = True,
     world_forfeiture_lawful = True,
     world_sale_occurred = True,
     world_debt_discharged = True,
     world_recipient_rightful = True\<rparr>"

definition world_with_no_external_truths :: external_legal_world where
  "world_with_no_external_truths =
    \<lparr>world_title_retained = False,
     world_forfeiture_lawful = False,
     world_sale_occurred = False,
     world_debt_discharged = False,
     world_recipient_rightful = False\<rparr>"

theorem same_core_input_cannot_distinguish_external_legal_truth:
  "core_observation world_with_all_external_truths st entry =
   core_observation world_with_no_external_truths st entry"
  by (simp add: core_observation_def)

theorem external_worlds_really_disagree:
  "world_title_retained world_with_all_external_truths \<noteq>
     world_title_retained world_with_no_external_truths \<and>
   world_sale_occurred world_with_all_external_truths \<noteq>
     world_sale_occurred world_with_no_external_truths \<and>
   world_debt_discharged world_with_all_external_truths \<noteq>
     world_debt_discharged world_with_no_external_truths \<and>
   world_recipient_rightful world_with_all_external_truths \<noteq>
     world_recipient_rightful world_with_no_external_truths"
  by (simp add: world_with_all_external_truths_def
      world_with_no_external_truths_def)

theorem ce02_guarantee_is_declared_custody_not_legal_title:
  "trust_custody (witness_applied_state Legal_Seize) 1 = Some 9 \<and>
   trust_declared_prior_holder
     (witness_applied_state Legal_Seize) 1 = Some 1"
  using ce02_seize_preserves_declared_holder_and_records_custody
  by simp

theorem ce11_guarantee_is_binding_not_sale_or_debt_truth:
  "trust_settlement_commitment (witness_applied_state Legal_Liquidate)
      (context_case (witness_context Legal_Liquidate)) =
     Some (context_external_commitment (witness_context Legal_Liquidate))"
  using ce11_liquidate_binds_settlement_without_asserting_external_truth
  by simp

theorem ce12_guarantee_is_binding_not_rightful_owner_truth:
  "trust_entitlement_commitment (witness_applied_state Legal_Recover)
      (context_case (witness_context Legal_Recover)) =
     Some (context_external_commitment (witness_context Legal_Recover))"
  using ce12_recover_binds_entitlement_destination_and_consumption
  by simp

theorem allowed_claim_inventory_is_exact:
  "set [Declared_Domain_Dynamics, Typed_Authorization_Consumption,
        Declared_Evidence_Binding, Abstract_Frame_Preservation] =
   allowed_verified_claims"
  by (simp add: allowed_verified_claims_def)

end
