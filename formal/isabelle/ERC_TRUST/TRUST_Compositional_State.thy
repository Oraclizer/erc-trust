(*
  TRUST-specific compositional state used by the end-to-end refinement.

  Kernel version 2 shape: the typed commands carry the ordered dependency root
  and the global dependency epoch, reversals carry their own provenance,
  receipts carry a kind tag and a parent command, and every regulatory case is
  a record with a phase, a family, a live head, and a generation.  Delegation,
  cancellation, and the caller-supplied scope hash of kernel version 1 do not
  exist in this state.  Effect provenance is the pair (parent, generation) of
  an immutable action record; no separate hash of those fields is kept,
  because the record never changes after it is written.

  The older single-mode trust_state remains the verified regulatory-action
  foundation.  This theory does not promote it to a reusable general
  framework: foundation_projection below is deliberately partial.
*)

theory TRUST_Compositional_State
  imports Claim_Boundary "HOL-Library.Nat_Bijection"
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

datatype trust_case_phase =
    Case_None
  | Case_Open
  | Case_Terminal

datatype trust_case_family =
    Family_None
  | Family_Freeze
  | Family_Restrict
  | Family_Custody
  | Family_Disposition

datatype trust_record_lifecycle =
    Record_Prepared
  | Record_Applied
  | Record_Reversed

datatype trust_receipt_kind =
    Receipt_Action
  | Receipt_Reversal

section \<open>Typed commands (kernel version 2 wire shape)\<close>

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
  forward_dependency_root :: trust_hash
  forward_dependency_epoch :: nat
  forward_provenance_commitment :: trust_hash
  forward_settlement_commitment :: trust_hash
  forward_proceeds_commitment :: trust_hash
  forward_entitlement_commitment :: trust_hash
  forward_authority_ref :: trust_authority_ref
  forward_authority_epoch :: nat
  forward_nonce :: trust_word256
  forward_valid_after :: nat
  forward_valid_before :: nat

record trust_reversal_command =
  reversal_domain :: trust_hash
  reversal_id :: trust_action_id
  reversal_original_action_id :: trust_action_id
  reversal_kind :: trust_reversal_kind
  reversal_dependency_root :: trust_hash
  reversal_dependency_epoch :: nat
  reversal_provenance_commitment :: trust_hash
  reversal_authority_ref :: trust_authority_ref
  reversal_authority_epoch :: nat
  reversal_nonce :: trust_word256
  reversal_valid_after :: nat
  reversal_valid_before :: nat

datatype trust_typed_command =
    TRUST_Forward trust_forward_command
  | TRUST_Reverse trust_reversal_command

section \<open>Records\<close>

record compositional_effect_link =
  effect_parent :: "trust_action_id option"
  effect_generation :: nat

record compositional_effect_head =
  head_action :: "trust_action_id option"
  head_generation :: nat

record compositional_case =
  case_phase :: trust_case_phase
  case_family :: trust_case_family
  case_head :: "trust_action_id option"
  case_generation :: nat

record compositional_action_record =
  abstract_action :: legal_action_kind
  abstract_lifecycle :: trust_record_lifecycle
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
  abstract_dependency_epoch :: nat
  abstract_command_hash :: trust_hash
  abstract_evidence_hash :: trust_hash
  abstract_receipt_hash :: trust_hash

record compositional_custody =
  custody_custodian :: trust_address
  custody_prior_holder :: trust_address
  custody_amount :: nat
  custody_action :: "trust_action_id option"
  custody_active :: bool

record compositional_authority =
  authority_account :: trust_address
  authority_epoch :: nat
  authority_active :: bool

record compositional_binding =
  binding_endpoint :: trust_address
  binding_code_id :: trust_hash
  binding_configuration :: trust_hash
  binding_schema :: trust_hash
  binding_epoch :: nat
  binding_hash :: trust_hash

record compositional_receipt =
  compositional_receipt_kind :: trust_receipt_kind
  compositional_command_id :: trust_action_id
  compositional_command_kind :: nat
  compositional_parent_command_id :: trust_action_id
  compositional_subject :: trust_address
  compositional_source :: trust_address
  compositional_destination :: trust_address
  compositional_amount :: nat
  compositional_case :: trust_case_id
  compositional_authority_ref :: trust_authority_ref
  compositional_dependency_root :: trust_hash
  compositional_provenance_commitment :: trust_hash
  compositional_assessment_evidence :: trust_hash
  compositional_pre_observation :: trust_hash
  compositional_post_observation :: trust_hash
  compositional_external_commitment :: trust_hash
  compositional_receipt_hash :: trust_hash

section \<open>Compositional state\<close>

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
  case_records :: "trust_case_id \<Rightarrow> compositional_case"
  consumed_entitlements :: "trust_hash set"
  authorities :: "trust_authority_ref \<Rightarrow> compositional_authority option"
  compositional_consumed_nonces :: "trust_nonce_key set"
  compositional_bindings :: "trust_binding_kind \<Rightarrow> compositional_binding option"
  dependency_root :: trust_hash
  dependency_epoch :: nat
  compositional_receipts :: "trust_hash \<Rightarrow> compositional_receipt option"

definition empty_head :: compositional_effect_head where
  "empty_head = \<lparr>head_action = None, head_generation = 0\<rparr>"

definition empty_case :: compositional_case where
  "empty_case =
     \<lparr>case_phase = Case_None, case_family = Family_None,
      case_head = None, case_generation = 0\<rparr>"

definition terminal_case :: "trust_compositional_state \<Rightarrow> trust_case_id \<Rightarrow> bool" where
  "terminal_case st case_id \<longleftrightarrow> case_phase (case_records st case_id) = Case_Terminal"

definition open_case :: "trust_compositional_state \<Rightarrow> trust_case_id \<Rightarrow> bool" where
  "open_case st case_id \<longleftrightarrow> case_phase (case_records st case_id) = Case_Open"

text \<open>
  The kernel version 2 code keeps no dedicated settlement or entitlement
  record.  A LIQUIDATE commits its settlement through the receipt's external
  commitment, a pair commitment of the settlement and proceeds commitments; a
  RECOVER commits its entitlement as the external commitment and consumes it
  once.  The abstract pair commitment is an injective pairing, which is all
  the model needs from it.
\<close>

definition settlement_pair_commitment :: "trust_hash \<Rightarrow> trust_hash \<Rightarrow> trust_hash" where
  "settlement_pair_commitment settlement proceeds = prod_encode (settlement, proceeds)"

theorem settlement_pair_commitment_is_injective:
  assumes "settlement_pair_commitment s1 p1 = settlement_pair_commitment s2 p2"
  shows "s1 = s2 \<and> p1 = p2"
  using assms by (simp add: settlement_pair_commitment_def prod_encode_eq)

section \<open>Physical, beneficial, and custody-backed units\<close>

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
      else if terminal_case st case_id then Some CONFISCATED
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

theorem ordinary_available_never_spends_custody_backing:
  "ordinary_available st account \<le> physical_balances st account - custody_backing st account"
  by (simp add: ordinary_available_def required_floor_def)

theorem ordinary_available_never_spends_own_frozen_floor:
  "ordinary_available st account \<le>
   physical_balances st account - custody_backing st account - own_frozen_floor st account"
  by (simp add: ordinary_available_def required_floor_def)

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
  let ?st =
    "\<lparr>physical_balances = (\<lambda>_. 1),
      compositional_allowances = (\<lambda>_ _. 0),
      compositional_total_supply = 1,
      frozen_targets = (\<lambda>_. 1),
      restriction_flags = (\<lambda>_. True),
      custody_backing = (\<lambda>_. 0),
      freeze_heads = (\<lambda>_. empty_head),
      restriction_heads = (\<lambda>_. empty_head),
      effect_links = (\<lambda>_. None),
      action_records = (\<lambda>_. None),
      custody_records = (\<lambda>_. None),
      case_records = (\<lambda>_. empty_case),
      consumed_entitlements = {},
      authorities = (\<lambda>_. None),
      compositional_consumed_nonces = {},
      compositional_bindings = (\<lambda>_. None),
      dependency_root = 0,
      dependency_epoch = 0,
      compositional_receipts = (\<lambda>_. None)\<rparr>"
  have "foundation_projection ?st 0 0 = None"
    by (simp add: foundation_projection_def foundation_coherent_def)
  then show ?thesis by blast
qed

end
