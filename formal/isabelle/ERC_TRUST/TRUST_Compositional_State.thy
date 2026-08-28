(*
  TRUST-specific compositional state used by the end-to-end refinement.

  The older single-mode trust_state remains the verified regulatory-action
  foundation.  This theory does not promote it to a reusable general
  framework: foundation_projection below is deliberately partial.
*)

theory TRUST_Compositional_State
  imports Claim_Boundary
begin

type_synonym trust_address = nat
type_synonym trust_word256 = nat
type_synonym trust_hash = nat
type_synonym trust_case_id = trust_hash
type_synonym trust_action_id = trust_hash
type_synonym trust_authority_ref = trust_hash
type_synonym trust_nonce_key = "trust_authority_ref \<times> nat \<times> trust_word256"

datatype trust_reversal_kind =
    TRUST_UNFREEZE
  | TRUST_RELEASE
  | TRUST_UNRESTRICT

datatype trust_binding_kind =
    TRUST_POLICY
  | TRUST_IDENTITY
  | TRUST_SETTLEMENT
  | TRUST_ENTITLEMENT

record trust_forward_command =
  forward_domain :: trust_hash
  forward_action_id :: trust_action_id
  forward_action :: legal_action_kind
  forward_subject :: trust_address
  forward_source :: trust_address
  forward_destination :: trust_address
  forward_custodian :: trust_address
  forward_amount :: nat
  forward_case :: trust_case_id
  forward_scope_hash :: trust_hash
  forward_policy_commitment :: trust_hash
  forward_provenance_commitment :: trust_hash
  forward_settlement_commitment :: trust_hash
  forward_proceeds_commitment :: trust_hash
  forward_entitlement_commitment :: trust_hash
  forward_authority_ref :: trust_authority_ref
  forward_authority_epoch :: nat
  forward_policy_epoch :: nat
  forward_nonce :: trust_word256
  forward_valid_after :: nat
  forward_valid_before :: nat

record trust_reversal_command =
  reversal_domain :: trust_hash
  reversal_id :: trust_action_id
  reversal_kind :: trust_reversal_kind
  reversal_original_action_id :: trust_action_id
  reversal_authority_ref :: trust_authority_ref
  reversal_authority_epoch :: nat
  reversal_policy_epoch :: nat
  reversal_nonce :: trust_word256
  reversal_valid_after :: nat
  reversal_valid_before :: nat

datatype trust_typed_command =
    TRUST_Forward trust_forward_command
  | TRUST_Reverse trust_reversal_command

record compositional_effect_link =
  effect_parent :: "trust_action_id option"
  effect_hash :: trust_hash
  effect_generation :: nat

record compositional_effect_head =
  head_action :: "trust_action_id option"
  head_hash :: trust_hash
  head_generation :: nat

record compositional_action_record =
  abstract_action :: legal_action_kind
  abstract_lifecycle :: authorization_lifecycle
  abstract_subject :: trust_address
  abstract_source :: trust_address
  abstract_destination :: trust_address
  abstract_custodian :: trust_address
  abstract_amount :: nat
  abstract_prior_amount :: nat
  abstract_prior_flag :: bool
  abstract_case :: trust_case_id
  abstract_authority_ref :: trust_authority_ref
  abstract_authority_epoch :: nat
  abstract_policy_epoch :: nat
  abstract_command_hash :: trust_hash
  abstract_evidence_hash :: trust_hash
  abstract_receipt_hash :: trust_hash

record compositional_custody =
  custody_custodian :: trust_address
  custody_prior_holder :: trust_address
  custody_amount :: nat
  custody_action :: "trust_action_id option"
  custody_parent :: "trust_action_id option"
  custody_effect_hash :: trust_hash
  custody_generation :: nat
  custody_active :: bool

record compositional_authority =
  authority_account :: trust_address
  authority_epoch :: nat
  authority_active :: bool

record compositional_delegation =
  delegation_authority_epoch :: nat
  delegation_scope :: trust_hash
  delegation_action_mask :: nat
  delegation_valid_until :: nat

record compositional_binding =
  binding_endpoint :: trust_address
  binding_code_id :: trust_hash
  binding_schema :: trust_hash
  binding_configuration :: trust_hash
  binding_epoch :: nat

record compositional_receipt =
  compositional_command_id :: trust_action_id
  compositional_action_code :: nat
  compositional_subject :: trust_address
  compositional_source :: trust_address
  compositional_destination :: trust_address
  compositional_custodian :: trust_address
  compositional_amount :: nat
  compositional_case :: trust_case_id
  compositional_external_commitment :: trust_hash
  compositional_pre_observation :: trust_hash
  compositional_post_observation :: trust_hash
  compositional_receipt_hash :: trust_hash

record compositional_settlement =
  settlement_destination :: trust_address
  settlement_commitment :: trust_hash
  settlement_proceeds_commitment :: trust_hash

record compositional_entitlement =
  entitlement_destination :: trust_address
  entitlement_commitment :: trust_hash
  entitlement_consumed :: bool

record trust_compositional_state =
  physical_balances :: "trust_address \<Rightarrow> nat"
  compositional_allowances :: "trust_address \<Rightarrow> trust_address \<Rightarrow> nat"
  compositional_total_supply :: nat
  frozen_targets :: "trust_address \<Rightarrow> nat"
  restriction_flags :: "trust_address \<Rightarrow> bool"
  custody_backing :: "trust_address \<Rightarrow> nat"
  freeze_heads :: "trust_address \<Rightarrow> compositional_effect_head"
  restriction_heads :: "trust_address \<Rightarrow> compositional_effect_head"
  effect_links :: "trust_action_id \<Rightarrow> compositional_effect_link option"
  action_records :: "trust_action_id \<Rightarrow> compositional_action_record option"
  custody_records :: "trust_case_id \<Rightarrow> compositional_custody option"
  terminal_cases :: "trust_case_id \<Rightarrow> bool"
  settlement_records :: "trust_action_id \<Rightarrow> compositional_settlement option"
  entitlement_records :: "trust_action_id \<Rightarrow> compositional_entitlement option"
  consumed_entitlements :: "trust_hash set"
  authorities :: "trust_authority_ref \<Rightarrow> compositional_authority option"
  delegations :: "trust_authority_ref \<Rightarrow> trust_address \<Rightarrow> compositional_delegation option"
  compositional_consumed_nonces :: "trust_nonce_key set"
  consumed_command_ids :: "trust_hash set"
  compositional_bindings :: "trust_binding_kind \<Rightarrow> compositional_binding option"
  compositional_receipts :: "trust_hash \<Rightarrow> compositional_receipt option"

definition active_custody_sum ::
  "trust_case_id set \<Rightarrow> trust_compositional_state \<Rightarrow> trust_address \<Rightarrow> nat"
where
  "active_custody_sum cases st account =
     (\<Sum>case_id\<in>cases.
       case custody_records st case_id of
         Some record \<Rightarrow>
           if custody_active record \<and> custody_custodian record = account
           then custody_amount record else 0
       | None \<Rightarrow> 0)"

definition own_physical ::
  "trust_compositional_state \<Rightarrow> trust_address \<Rightarrow> nat"
where
  "own_physical st account =
     physical_balances st account - custody_backing st account"

definition own_frozen_floor ::
  "trust_compositional_state \<Rightarrow> trust_address \<Rightarrow> nat"
where
  "own_frozen_floor st account =
     min (frozen_targets st account) (own_physical st account)"

definition required_floor ::
  "trust_compositional_state \<Rightarrow> trust_address \<Rightarrow> nat"
where
  "required_floor st account =
     custody_backing st account + own_frozen_floor st account"

definition ordinary_available ::
  "trust_compositional_state \<Rightarrow> trust_address \<Rightarrow> nat"
where
  "ordinary_available st account =
     physical_balances st account - required_floor st account"

definition custody_consistent ::
  "trust_case_id set \<Rightarrow> trust_compositional_state \<Rightarrow> bool"
where
  "custody_consistent cases st \<longleftrightarrow>
     finite cases \<and>
     (\<forall>account. custody_backing st account = active_custody_sum cases st account) \<and>
     (\<forall>account. custody_backing st account \<le> physical_balances st account)"

definition foundation_coherent ::
  "trust_compositional_state \<Rightarrow> trust_address \<Rightarrow> trust_case_id \<Rightarrow> bool"
where
  "foundation_coherent st account case_id \<longleftrightarrow>
     \<not> (frozen_targets st account > 0 \<and> restriction_flags st account) \<and>
     (case custody_records st case_id of
        None \<Rightarrow> True
      | Some record \<Rightarrow>
          \<not> custody_active record \<or>
          (frozen_targets st account = 0 \<and> \<not> restriction_flags st account))"

definition foundation_projection ::
  "trust_compositional_state \<Rightarrow> trust_address \<Rightarrow> trust_case_id \<Rightarrow> reg_state option"
where
  "foundation_projection st account case_id =
     (if \<not> foundation_coherent st account case_id then None
      else if terminal_cases st case_id then Some CONFISCATED
      else case custody_records st case_id of
        Some record \<Rightarrow> if custody_active record then Some SEIZED
                       else if frozen_targets st account > 0 then Some FROZEN
                       else if restriction_flags st account then Some RESTRICTED
                       else Some ACTIVE
      | None \<Rightarrow> if frozen_targets st account > 0 then Some FROZEN
                else if restriction_flags st account then Some RESTRICTED
                else Some ACTIVE)"

theorem custody_backing_equals_active_custody_sum:
  assumes "custody_consistent cases st"
  shows "custody_backing st account = active_custody_sum cases st account"
  using assms by (simp add: custody_consistent_def)

theorem physical_balance_covers_custody_backing:
  assumes "custody_consistent cases st"
  shows "custody_backing st account \<le> physical_balances st account"
  using assms unfolding custody_consistent_def by blast

theorem required_floor_is_additive_without_double_counting:
  assumes "custody_backing st account \<le> physical_balances st account"
  shows "required_floor st account \<le> physical_balances st account"
  using assms
  by (auto simp: required_floor_def own_frozen_floor_def own_physical_def)

theorem ordinary_available_plus_required_floor:
  assumes "custody_backing st account \<le> physical_balances st account"
  shows "ordinary_available st account + required_floor st account =
         physical_balances st account"
  using assms required_floor_is_additive_without_double_counting
  by (simp add: ordinary_available_def)

theorem unbounded_freeze_target_saturates_only_at_observation:
  assumes "physical_balances st account \<le> frozen_targets st account"
  shows "own_frozen_floor st account = own_physical st account"
  using assms by (auto simp: own_frozen_floor_def own_physical_def)

theorem foundation_projection_is_explicitly_partial:
  assumes "foundation_coherent st account case_id"
  shows "foundation_projection st account case_id \<noteq> None"
  using assms by (auto simp: foundation_projection_def split: option.splits)

theorem composite_overlay_has_no_foundation_projection:
  assumes "frozen_targets st account > 0" "restriction_flags st account"
  shows "foundation_projection st account case_id = None"
  using assms by (simp add: foundation_projection_def foundation_coherent_def)

theorem compositional_state_does_not_generalize_foundation:
  "\<exists>st account case_id. foundation_projection st account case_id = None"
proof -
  let ?head = "\<lparr>head_action = None, head_hash = 0, head_generation = 0\<rparr>"
  let ?st =
    "\<lparr>physical_balances = (\<lambda>_. 1),
      compositional_allowances = (\<lambda>_ _. 0),
      compositional_total_supply = 1,
      frozen_targets = (\<lambda>_. 1),
      restriction_flags = (\<lambda>_. True),
      custody_backing = (\<lambda>_. 0),
      freeze_heads = (\<lambda>_. ?head),
      restriction_heads = (\<lambda>_. ?head),
      effect_links = (\<lambda>_. None),
      action_records = (\<lambda>_. None),
      custody_records = (\<lambda>_. None),
      terminal_cases = (\<lambda>_. False),
      settlement_records = (\<lambda>_. None),
      entitlement_records = (\<lambda>_. None),
      consumed_entitlements = {},
      authorities = (\<lambda>_. None),
      delegations = (\<lambda>_ _. None),
      compositional_consumed_nonces = {},
      consumed_command_ids = {},
      compositional_bindings = (\<lambda>_. None),
      compositional_receipts = (\<lambda>_. None)\<rparr>"
  have "foundation_projection ?st 0 0 = None"
    by (simp add: foundation_projection_def foundation_coherent_def)
  then show ?thesis by blast
qed

end
