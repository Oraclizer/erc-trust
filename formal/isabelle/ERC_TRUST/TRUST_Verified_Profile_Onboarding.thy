(*
  ERC-3643 Verified Full profile: onboarding and ownership abstractions.

  The profile adapter starts from a fresh zero state or from an exact import
  manifest.  Each manifest entry declares the upstream frozen amount and the
  address freeze flag of one account; the seal verifies every entry against
  the live upstream state and imports each declared state as a case with a
  synthetic applied head action, so that the declared legacy state is
  reversible and amendable under the same case transition table as every
  other command.  The adapter has one immutable authority at epoch one, and
  acts only on upstream state it declared or applied itself.
*)

theory TRUST_Verified_Profile_Onboarding
  imports TRUST_Transaction_Refinement
begin

record import_entry =
  import_account :: trust_address
  import_frozen :: nat
  import_restricted :: bool

definition manifest_canonical :: "import_entry list \<Rightarrow> bool" where
  "manifest_canonical entries \<longleftrightarrow>
     sorted_wrt (<) (map import_account entries) \<and>
     (\<forall>entry\<in>set entries.
        import_account entry \<noteq> 0 \<and>
        (import_frozen entry \<noteq> 0 \<or> import_restricted entry))"

definition family_code :: "trust_case_family \<Rightarrow> nat" where
  "family_code family =
     (case family of
        Family_None \<Rightarrow> 0 | Family_Freeze \<Rightarrow> 1 | Family_Restrict \<Rightarrow> 2
      | Family_Custody \<Rightarrow> 3 | Family_Disposition \<Rightarrow> 4)"

definition import_case_id ::
  "trust_hash \<Rightarrow> trust_address \<Rightarrow> trust_case_family \<Rightarrow> trust_case_id"
where
  "import_case_id manifest_hash account family =
     prod_encode (manifest_hash, prod_encode (account, family_code family))"

definition import_action_id :: "trust_case_id \<Rightarrow> trust_action_id" where
  "import_action_id case_id = prod_encode (1, case_id)"

theorem import_case_ids_are_injective:
  assumes "import_case_id m1 a1 f1 = import_case_id m2 a2 f2"
  shows "m1 = m2 \<and> a1 = a2 \<and> family_code f1 = family_code f2"
  using assms by (simp add: import_case_id_def prod_encode_eq)

definition imported_head_record ::
  "legal_action_kind \<Rightarrow> trust_address \<Rightarrow> nat \<Rightarrow> trust_case_id \<Rightarrow> compositional_action_record"
where
  "imported_head_record action account amount case_id =
     \<lparr>abstract_action = action,
      abstract_lifecycle = Record_Applied,
      abstract_subject = account,
      abstract_source = account,
      abstract_destination = 0,
      abstract_custodian = 0,
      abstract_amount = amount,
      abstract_prior_amount = 0,
      abstract_prior_flag = False,
      abstract_case = case_id,
      abstract_authority_ref = 0,
      abstract_authority_epoch = 0,
      abstract_dependency_epoch = 1,
      abstract_command_hash = 0,
      abstract_evidence_hash = 0,
      abstract_receipt_hash = 0\<rparr>"

definition open_imported_case ::
  "trust_compositional_state \<Rightarrow> trust_hash \<Rightarrow> trust_address \<Rightarrow> trust_case_family \<Rightarrow>
   legal_action_kind \<Rightarrow> nat \<Rightarrow> trust_compositional_state"
where
  "open_imported_case st manifest_hash account family action amount =
     (let case_id = import_case_id manifest_hash account family;
          action_id = import_action_id case_id;
          head = (if family = Family_Freeze then freeze_heads st account else restriction_heads st account);
          st' = st\<lparr>
            action_records := (action_records st)
              (action_id := Some (imported_head_record action account amount case_id)),
            effect_links := (effect_links st)(action_id := Some (pushed_link head)),
            case_records := (case_records st)
              (case_id := opened_overlay (case_records st case_id) family action_id)\<rparr>
      in if family = Family_Freeze
         then st'\<lparr>freeze_heads := (freeze_heads st)(account := pushed_head head action_id)\<rparr>
         else st'\<lparr>restriction_heads := (restriction_heads st)(account := pushed_head head action_id)\<rparr>)"

definition import_entry_state ::
  "trust_compositional_state \<Rightarrow> trust_hash \<Rightarrow> import_entry \<Rightarrow> trust_compositional_state"
where
  "import_entry_state st manifest_hash entry =
     (let account = import_account entry;
          declared = st\<lparr>
            frozen_targets := (frozen_targets st)(account := import_frozen entry),
            restriction_flags := (restriction_flags st)(account := import_restricted entry)\<rparr>;
          frozen = (if import_frozen entry \<noteq> 0
                    then open_imported_case declared manifest_hash account Family_Freeze
                           Legal_Freeze (import_frozen entry)
                    else declared)
      in if import_restricted entry
         then open_imported_case frozen manifest_hash account Family_Restrict Legal_Restrict 0
         else frozen)"

definition imported_state ::
  "trust_compositional_state \<Rightarrow> trust_hash \<Rightarrow> import_entry list \<Rightarrow> trust_compositional_state"
where
  "imported_state st manifest_hash entries =
     foldl (\<lambda>state entry. import_entry_state state manifest_hash entry) st entries"

theorem empty_manifest_is_the_fresh_zero_state:
  "imported_state st manifest_hash [] = st"
  by (simp add: imported_state_def)

theorem imported_entry_declares_the_frozen_target_and_flag:
  "frozen_targets (import_entry_state st manifest_hash entry) (import_account entry) =
     import_frozen entry \<and>
   restriction_flags (import_entry_state st manifest_hash entry) (import_account entry) =
     import_restricted entry"
  by (simp add: import_entry_state_def open_imported_case_def Let_def)

theorem imported_frozen_entry_opens_a_reversible_freeze_case:
  assumes "import_frozen entry \<noteq> 0"
      and "\<not> import_restricted entry"
      and "head_action (freeze_heads st (import_account entry)) = None"
  shows "let state = import_entry_state st manifest_hash entry;
             case_id = import_case_id manifest_hash (import_account entry) Family_Freeze;
             action_id = import_action_id case_id
         in head_action (freeze_heads state (import_account entry)) = Some action_id \<and>
            case_phase (case_records state case_id) = Case_Open \<and>
            case_head (case_records state case_id) = Some action_id \<and>
            map_option abstract_lifecycle (action_records state action_id) = Some Record_Applied \<and>
            effect_links state action_id \<noteq> None"
  using assms
  by (simp add: import_entry_state_def open_imported_case_def opened_overlay_def
      pushed_head_def imported_head_record_def Let_def)

theorem imported_freeze_head_admits_its_unfreeze:
  assumes "import_frozen entry \<noteq> 0"
      and "\<not> import_restricted entry"
      and "head_action (freeze_heads st (import_account entry)) = None"
      and "case_phase (case_records st
             (import_case_id manifest_hash (import_account entry) Family_Freeze)) = Case_None"
      and "reversal_original_action_id command =
             import_action_id (import_case_id manifest_hash (import_account entry) Family_Freeze)"
      and "reversal_kind command = TRUST_UNFREEZE"
      and "reversal_id command \<noteq> 0"
      and "reversal_provenance_commitment command \<noteq> 0"
  shows "reversal_admissible (import_entry_state st manifest_hash entry) command"
  using assms
  by (simp add: reversal_admissible_def reversal_original_def reversal_current_effect_def
      reversal_pairs_def import_entry_state_def open_imported_case_def opened_overlay_def
      pushed_head_def imported_head_record_def terminal_case_def Let_def)

section \<open>Single immutable authority\<close>

definition profile_authorities ::
  "trust_authority_ref \<Rightarrow> trust_address \<Rightarrow> (trust_authority_ref \<Rightarrow> compositional_authority option)"
where
  "profile_authorities ref account =
     (\<lambda>requested. if requested = ref
        then Some \<lparr>authority_account = account, authority_epoch = 1, authority_active = True\<rparr>
        else None)"

theorem profile_authorization_is_exactly_the_immutable_authority:
  assumes "authorities st = profile_authorities ref account"
  shows "forward_authorized st sender command \<longleftrightarrow>
         (sender = account \<and> forward_authority_ref command = ref \<and>
          forward_authority_epoch command = 1)"
  using assms by (auto simp: forward_authorized_def authority_admits_def profile_authorities_def)

theorem profile_authority_cannot_rotate_by_a_command:
  assumes "authorities st = profile_authorities ref account"
  shows "authorities (forward_success_state st command witness) = profile_authorities ref account"
  using assms
  by (cases "forward_action command")
     (simp_all add: forward_success_state_def base_forward_success_def Let_def)

section \<open>Custody confinement and owned upstream state\<close>

definition profile_custody_confined :: "trust_address \<Rightarrow> trust_forward_command \<Rightarrow> bool" where
  "profile_custody_confined adapter command \<longleftrightarrow>
     (forward_action command = Legal_Seize \<longrightarrow> forward_custodian command = adapter)"

theorem confined_seize_is_a_kernel_seize:
  assumes "forward_shape_wf st command"
      and "profile_custody_confined adapter command"
      and "forward_action command = Legal_Seize"
  shows "forward_custodian command = adapter \<and> forward_destination command = adapter"
  using assms by (simp add: forward_shape_wf_def profile_custody_confined_def)

record upstream_view =
  upstream_frozen :: "trust_address \<Rightarrow> nat"
  upstream_restricted :: "trust_address \<Rightarrow> bool"
  upstream_balance :: "trust_address \<Rightarrow> nat"

definition owned_upstream_state ::
  "trust_compositional_state \<Rightarrow> (trust_address \<Rightarrow> nat) \<Rightarrow> upstream_view \<Rightarrow> trust_address \<Rightarrow> bool"
where
  "owned_upstream_state st applied view account \<longleftrightarrow>
     upstream_frozen view account = applied account \<and>
     upstream_restricted view account = restriction_flags st account"

definition saturated_target ::
  "trust_compositional_state \<Rightarrow> upstream_view \<Rightarrow> trust_address \<Rightarrow> nat"
where
  "saturated_target st view account =
     min (frozen_targets st account) (upstream_balance view account)"

theorem unowned_upstream_state_is_an_operational_stutter:
  assumes "\<not> owned_upstream_state st applied view account"
  shows "fst (abstract_failure_transition st TRUST_Abstract_Operational_Failure) = st"
  by (simp add: abstract_failure_transition_def)

theorem resynchronisation_never_lowers_an_owned_frozen_amount:
  assumes "owned_upstream_state st applied view account"
      and "applied account \<le> frozen_targets st account"
      and "applied account \<le> upstream_balance view account"
  shows "upstream_frozen view account \<le> saturated_target st view account"
  using assms by (simp add: owned_upstream_state_def saturated_target_def)

theorem resynchronisation_reaches_the_saturated_target:
  "saturated_target st view account \<le> frozen_targets st account \<and>
   saturated_target st view account \<le> upstream_balance view account"
  by (simp add: saturated_target_def)

end
