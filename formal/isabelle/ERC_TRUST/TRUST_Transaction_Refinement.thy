(*
  Abstract TRUST transaction steps of kernel version 2 and the
  single-transaction relation.

  The admissibility predicates below are the abstract form of the kernel's
  validation order: domain and identifier shape, replay of the command
  identifier, validity window, authority account and epoch, dependency root
  and global epoch, nonce freshness, and then the per-action shape rules and
  the case transition table.  The success states are the abstract form of the
  kernel's state effects; the receipt predicates fix which command fields the
  stored, returned, and logged receipt must carry.
*)

theory TRUST_Transaction_Refinement
  imports TRUST_Retrieve_Relation
begin

record trust_success_witness =
  witness_command_hash :: trust_hash
  witness_evidence_hash :: trust_hash
  witness_receipt :: compositional_receipt

record trust_reversal_witness =
  reversal_witness_command_hash :: trust_hash
  reversal_witness_evidence_hash :: trust_hash
  reversal_witness_receipt :: compositional_receipt

datatype trust_abstract_failure =
    TRUST_Abstract_Rejection
  | TRUST_Abstract_Operational_Failure
  | TRUST_Abstract_Malformed_Input
  | TRUST_Abstract_Dependency_Failure

definition evm_bytes_selector :: "evm_bytes \<Rightarrow> nat option" where
  "evm_bytes_selector bytes =
     (case bytes of
        a # b # c # d # _ \<Rightarrow>
          Some (a * 16777216 + b * 65536 + c * 256 + d)
      | _ \<Rightarrow> None)"

definition typed_failure_payload :: "evm_bytes \<Rightarrow> bool" where
  "typed_failure_payload payload \<longleftrightarrow>
     (case evm_bytes_selector payload of
        Some selector \<Rightarrow> selector \<in> typed_failure_selectors
      | None \<Rightarrow> False)"

theorem generic_dispatcher_revert_is_not_typed_failure:
  assumes "revert_payload = []"
  shows "generic_dispatcher_input_selector \<notin> typed_command_entrypoint_selectors \<and>
         \<not> typed_failure_payload revert_payload"
  using assms
  by (simp add: generic_dispatcher_input_selector_def
      typed_command_entrypoint_selectors_def action_entrypoint_selector_def
      reversal_entrypoint_selector_def native_route_action_selector_def
      native_route_reversal_selector_def typed_failure_payload_def
      evm_bytes_selector_def)

section \<open>Authorization, freshness, dependency currentness, validity window\<close>

definition forward_nonce_key :: "trust_forward_command \<Rightarrow> trust_nonce_key" where
  "forward_nonce_key command =
     (forward_authority_ref command, forward_authority_epoch command,
      forward_nonce command)"

definition reversal_nonce_key :: "trust_reversal_command \<Rightarrow> trust_nonce_key" where
  "reversal_nonce_key command =
     (reversal_authority_ref command, reversal_authority_epoch command,
      reversal_nonce command)"

definition authority_admits ::
  "trust_compositional_state \<Rightarrow> trust_address \<Rightarrow> trust_authority_ref \<Rightarrow> nat \<Rightarrow> bool"
where
  "authority_admits st sender ref epoch \<longleftrightarrow>
     (case authorities st ref of
        None \<Rightarrow> False
      | Some authority \<Rightarrow>
          authority_epoch authority = epoch \<and>
          authority_active authority \<and>
          authority_account authority = sender)"

definition forward_authorized ::
  "trust_compositional_state \<Rightarrow> trust_address \<Rightarrow> trust_forward_command \<Rightarrow> bool"
where
  "forward_authorized st sender command \<longleftrightarrow>
     authority_admits st sender (forward_authority_ref command) (forward_authority_epoch command)"

definition reversal_authorized ::
  "trust_compositional_state \<Rightarrow> trust_address \<Rightarrow> trust_reversal_command \<Rightarrow> bool"
where
  "reversal_authorized st sender command \<longleftrightarrow>
     authority_admits st sender (reversal_authority_ref command) (reversal_authority_epoch command)"

definition forward_current_dependency ::
  "trust_compositional_state \<Rightarrow> trust_forward_command \<Rightarrow> bool"
where
  "forward_current_dependency st command \<longleftrightarrow>
     forward_dependency_root command = dependency_root st \<and>
     forward_dependency_epoch command = dependency_epoch st"

definition reversal_current_dependency ::
  "trust_compositional_state \<Rightarrow> trust_reversal_command \<Rightarrow> bool"
where
  "reversal_current_dependency st command \<longleftrightarrow>
     reversal_dependency_root command = dependency_root st \<and>
     reversal_dependency_epoch command = dependency_epoch st"

definition forward_fresh ::
  "trust_compositional_state \<Rightarrow> trust_forward_command \<Rightarrow> bool"
where
  "forward_fresh st command \<longleftrightarrow>
     action_records st (forward_action_id command) = None \<and>
     forward_nonce_key command \<notin> compositional_consumed_nonces st"

definition reversal_fresh ::
  "trust_compositional_state \<Rightarrow> trust_reversal_command \<Rightarrow> bool"
where
  "reversal_fresh st command \<longleftrightarrow>
     compositional_receipts st (reversal_id command) = None \<and>
     reversal_nonce_key command \<notin> compositional_consumed_nonces st"

definition within_window :: "nat \<Rightarrow> nat \<Rightarrow> nat \<Rightarrow> bool" where
  "within_window time valid_after valid_before \<longleftrightarrow>
     valid_after \<le> time \<and> time \<le> valid_before \<and> valid_before \<noteq> 0"

definition forward_in_window :: "nat \<Rightarrow> trust_forward_command \<Rightarrow> bool" where
  "forward_in_window time command \<longleftrightarrow>
     within_window time (forward_valid_after command) (forward_valid_before command)"

definition reversal_in_window :: "nat \<Rightarrow> trust_reversal_command \<Rightarrow> bool" where
  "reversal_in_window time command \<longleftrightarrow>
     within_window time (reversal_valid_after command) (reversal_valid_before command)"

section \<open>Shape rules and the case transition table\<close>

definition overlay_admissible ::
  "compositional_case \<Rightarrow> compositional_effect_head \<Rightarrow> bool"
where
  "overlay_admissible cs head \<longleftrightarrow>
     (case head_action head of
        None \<Rightarrow> case_phase cs = Case_None
      | Some action \<Rightarrow> case_head cs = Some action)"

definition unbacked_available ::
  "trust_compositional_state \<Rightarrow> trust_address \<Rightarrow> nat \<Rightarrow> bool"
where
  "unbacked_available st account amount \<longleftrightarrow>
     custody_backing st account \<le> physical_balances st account \<and>
     amount \<le> physical_balances st account - custody_backing st account"

definition uses_active_custody ::
  "trust_compositional_state \<Rightarrow> trust_forward_command \<Rightarrow> bool"
where
  "uses_active_custody st command \<longleftrightarrow>
     (case custody_records st (forward_case command) of
        Some custody \<Rightarrow> custody_active custody
      | None \<Rightarrow> False)"

definition custody_matches ::
  "trust_compositional_state \<Rightarrow> trust_forward_command \<Rightarrow> bool"
where
  "custody_matches st command \<longleftrightarrow>
     (case custody_records st (forward_case command) of
        Some custody \<Rightarrow>
          custody_active custody \<and>
          custody_custodian custody = forward_source command \<and>
          custody_prior_holder custody = forward_subject command \<and>
          custody_amount custody = forward_amount command \<and>
          custody_amount custody \<le> custody_backing st (custody_custodian custody)
      | None \<Rightarrow> False)"

definition no_disposition_commitments :: "trust_forward_command \<Rightarrow> bool" where
  "no_disposition_commitments command \<longleftrightarrow>
     forward_settlement_commitment command = 0 \<and>
     forward_proceeds_commitment command = 0 \<and>
     forward_entitlement_commitment command = 0"

definition overlay_shape :: "trust_forward_command \<Rightarrow> bool" where
  "overlay_shape command \<longleftrightarrow>
     forward_source command = forward_subject command \<and>
     forward_destination command = 0 \<and>
     forward_custodian command = 0"

definition transfer_shape :: "trust_forward_command \<Rightarrow> bool" where
  "transfer_shape command \<longleftrightarrow>
     forward_source command \<noteq> 0 \<and>
     forward_destination command \<noteq> 0 \<and>
     forward_source command \<noteq> forward_destination command \<and>
     forward_amount command > 0"

definition disposition_wf ::
  "trust_compositional_state \<Rightarrow> trust_forward_command \<Rightarrow> bool"
where
  "disposition_wf st command \<longleftrightarrow>
     transfer_shape command \<and>
     forward_custodian command = 0 \<and>
     (if open_case st (forward_case command)
      then case_family (case_records st (forward_case command)) = Family_Custody \<and>
           custody_matches st command
      else forward_source command = forward_subject command \<and>
           unbacked_available st (forward_source command) (forward_amount command))"

definition restrict_would_not_change_state ::
  "trust_compositional_state \<Rightarrow> trust_forward_command \<Rightarrow> bool"
where
  "restrict_would_not_change_state st command \<longleftrightarrow>
     (\<exists>action. head_action (restriction_heads st (forward_subject command)) = Some action \<and>
               case_head (case_records st (forward_case command)) = Some action)"

definition forward_shape_wf ::
  "trust_compositional_state \<Rightarrow> trust_forward_command \<Rightarrow> bool"
where
  "forward_shape_wf st command \<longleftrightarrow>
     forward_action_id command \<noteq> 0 \<and>
     forward_subject command \<noteq> 0 \<and>
     forward_case command \<noteq> 0 \<and>
     forward_provenance_commitment command \<noteq> 0 \<and>
     \<not> terminal_case st (forward_case command) \<and>
     (case forward_action command of
        Legal_Freeze \<Rightarrow>
          overlay_shape command \<and> no_disposition_commitments command \<and>
          overlay_admissible (case_records st (forward_case command))
            (freeze_heads st (forward_subject command)) \<and>
          frozen_targets st (forward_subject command) < forward_amount command
      | Legal_Restrict \<Rightarrow>
          overlay_shape command \<and> forward_amount command = 0 \<and>
          no_disposition_commitments command \<and>
          \<not> restrict_would_not_change_state st command \<and>
          overlay_admissible (case_records st (forward_case command))
            (restriction_heads st (forward_subject command))
      | Legal_Seize \<Rightarrow>
          transfer_shape command \<and>
          forward_source command = forward_subject command \<and>
          forward_custodian command \<noteq> 0 \<and>
          forward_destination command = forward_custodian command \<and>
          \<not> open_case st (forward_case command) \<and>
          no_disposition_commitments command \<and>
          unbacked_available st (forward_source command) (forward_amount command)
      | Legal_Confiscate \<Rightarrow>
          disposition_wf st command \<and> no_disposition_commitments command
      | Legal_Liquidate \<Rightarrow>
          disposition_wf st command \<and>
          forward_settlement_commitment command \<noteq> 0 \<and>
          forward_proceeds_commitment command \<noteq> 0 \<and>
          forward_entitlement_commitment command = 0
      | Legal_Recover \<Rightarrow>
          disposition_wf st command \<and>
          forward_settlement_commitment command = 0 \<and>
          forward_proceeds_commitment command = 0 \<and>
          forward_entitlement_commitment command \<noteq> 0 \<and>
          forward_entitlement_commitment command \<notin> consumed_entitlements st)"

section \<open>Receipt agreement\<close>

definition forward_external_commitment :: "trust_forward_command \<Rightarrow> trust_hash" where
  "forward_external_commitment command =
     (case forward_action command of
        Legal_Liquidate \<Rightarrow>
          settlement_pair_commitment (forward_settlement_commitment command)
            (forward_proceeds_commitment command)
      | Legal_Recover \<Rightarrow> forward_entitlement_commitment command
      | _ \<Rightarrow> 0)"

definition receipt_matches_forward ::
  "trust_forward_command \<Rightarrow> trust_success_witness \<Rightarrow> bool"
where
  "receipt_matches_forward command witness \<longleftrightarrow>
     (let receipt = witness_receipt witness in
      compositional_receipt_kind receipt = Receipt_Action \<and>
      compositional_command_id receipt = forward_action_id command \<and>
      compositional_command_kind receipt = solidity_action_code (forward_action command) \<and>
      compositional_parent_command_id receipt = 0 \<and>
      compositional_subject receipt = forward_subject command \<and>
      compositional_source receipt = forward_source command \<and>
      compositional_destination receipt = forward_destination command \<and>
      compositional_amount receipt = forward_amount command \<and>
      compositional_case receipt = forward_case command \<and>
      compositional_authority_ref receipt = forward_authority_ref command \<and>
      compositional_dependency_root receipt = forward_dependency_root command \<and>
      compositional_provenance_commitment receipt = forward_provenance_commitment command \<and>
      compositional_assessment_evidence receipt = witness_evidence_hash witness \<and>
      compositional_external_commitment receipt = forward_external_commitment command)"

definition reversal_receipt_source ::
  "trust_reversal_command \<Rightarrow> compositional_action_record \<Rightarrow> trust_address"
where
  "reversal_receipt_source command original =
     (case reversal_kind command of
        TRUST_RELEASE \<Rightarrow> abstract_custodian original
      | _ \<Rightarrow> abstract_subject original)"

definition reversal_receipt_destination ::
  "trust_reversal_command \<Rightarrow> compositional_action_record \<Rightarrow> trust_address"
where
  "reversal_receipt_destination command original =
     (case reversal_kind command of
        TRUST_RELEASE \<Rightarrow> abstract_source original
      | _ \<Rightarrow> abstract_subject original)"

definition receipt_matches_reversal ::
  "trust_reversal_command \<Rightarrow> compositional_action_record \<Rightarrow> trust_reversal_witness \<Rightarrow> bool"
where
  "receipt_matches_reversal command original witness \<longleftrightarrow>
     (let receipt = reversal_witness_receipt witness in
      compositional_receipt_kind receipt = Receipt_Reversal \<and>
      compositional_command_id receipt = reversal_id command \<and>
      compositional_command_kind receipt = solidity_reversal_code (reversal_kind command) \<and>
      compositional_parent_command_id receipt = reversal_original_action_id command \<and>
      compositional_subject receipt = abstract_subject original \<and>
      compositional_source receipt = reversal_receipt_source command original \<and>
      compositional_destination receipt = reversal_receipt_destination command original \<and>
      compositional_amount receipt = abstract_amount original \<and>
      compositional_case receipt = abstract_case original \<and>
      compositional_authority_ref receipt = reversal_authority_ref command \<and>
      compositional_dependency_root receipt = reversal_dependency_root command \<and>
      compositional_provenance_commitment receipt = reversal_provenance_commitment command \<and>
      compositional_assessment_evidence receipt = reversal_witness_evidence_hash witness \<and>
      compositional_external_commitment receipt = 0)"

theorem forward_and_reversal_receipts_are_distinguished_by_kind:
  assumes "receipt_matches_forward command witness"
      and "receipt_matches_reversal reversal original reversal_witness"
  shows "witness_receipt witness \<noteq> reversal_witness_receipt reversal_witness"
  using assms
  by (auto simp: receipt_matches_forward_def receipt_matches_reversal_def Let_def)

section \<open>Successful forward transitions\<close>

definition forward_action_record ::
  "trust_compositional_state \<Rightarrow> trust_forward_command \<Rightarrow>
   trust_success_witness \<Rightarrow> compositional_action_record"
where
  "forward_action_record st command witness =
     \<lparr>abstract_action = forward_action command,
      abstract_lifecycle = Record_Applied,
      abstract_subject = forward_subject command,
      abstract_source = forward_source command,
      abstract_destination = forward_destination command,
      abstract_custodian = forward_custodian command,
      abstract_amount = forward_amount command,
      abstract_prior_amount =
        (if forward_action command = Legal_Freeze
         then frozen_targets st (forward_subject command) else 0),
      abstract_prior_flag =
        (forward_action command = Legal_Restrict \<and>
         restriction_flags st (forward_subject command)),
      abstract_case = forward_case command,
      abstract_authority_ref = forward_authority_ref command,
      abstract_authority_epoch = forward_authority_epoch command,
      abstract_dependency_epoch = forward_dependency_epoch command,
      abstract_command_hash = witness_command_hash witness,
      abstract_evidence_hash = witness_evidence_hash witness,
      abstract_receipt_hash = compositional_receipt_hash (witness_receipt witness)\<rparr>"

definition base_forward_success ::
  "trust_compositional_state \<Rightarrow> trust_forward_command \<Rightarrow>
   trust_success_witness \<Rightarrow> trust_compositional_state"
where
  "base_forward_success st command witness =
     st\<lparr>
       action_records := (action_records st)
         (forward_action_id command := Some (forward_action_record st command witness)),
       compositional_consumed_nonces :=
         insert (forward_nonce_key command) (compositional_consumed_nonces st),
       compositional_receipts := (compositional_receipts st)
         (forward_action_id command := Some (witness_receipt witness))
     \<rparr>"

definition pushed_link :: "compositional_effect_head \<Rightarrow> compositional_effect_link" where
  "pushed_link head =
     \<lparr>effect_parent = head_action head, effect_generation = head_generation head + 1\<rparr>"

definition pushed_head ::
  "compositional_effect_head \<Rightarrow> trust_action_id \<Rightarrow> compositional_effect_head"
where
  "pushed_head head action =
     \<lparr>head_action = Some action, head_generation = head_generation head + 1\<rparr>"

definition opened_overlay ::
  "compositional_case \<Rightarrow> trust_case_family \<Rightarrow> trust_action_id \<Rightarrow> compositional_case"
where
  "opened_overlay cs family action =
     \<lparr>case_phase = Case_Open,
      case_family = (if case_phase cs = Case_None then family else case_family cs),
      case_head = Some action,
      case_generation = case_generation cs + 1\<rparr>"

definition opened_custody ::
  "compositional_case \<Rightarrow> trust_action_id \<Rightarrow> compositional_case"
where
  "opened_custody cs action =
     \<lparr>case_phase = Case_Open, case_family = Family_Custody,
      case_head = Some action, case_generation = case_generation cs + 1\<rparr>"

definition closed_case :: "compositional_case \<Rightarrow> compositional_case" where
  "closed_case cs =
     \<lparr>case_phase = Case_Terminal, case_family = case_family cs,
      case_head = None, case_generation = case_generation cs + 1\<rparr>"

definition disposed_case :: "compositional_case \<Rightarrow> bool \<Rightarrow> compositional_case" where
  "disposed_case cs consumed_custody =
     \<lparr>case_phase = Case_Terminal,
      case_family = (if consumed_custody then case_family cs else Family_Disposition),
      case_head = None,
      case_generation = case_generation cs + 1\<rparr>"

definition close_custody ::
  "trust_compositional_state \<Rightarrow> trust_case_id \<Rightarrow>
   (trust_case_id \<Rightarrow> compositional_custody option)"
where
  "close_custody st case_id =
     (case custody_records st case_id of
        None \<Rightarrow> custody_records st
      | Some custody \<Rightarrow>
          (custody_records st)(case_id := Some (custody\<lparr>custody_active := False\<rparr>)))"

definition move_balance ::
  "(trust_address \<Rightarrow> nat) \<Rightarrow> trust_address \<Rightarrow> trust_address \<Rightarrow> nat \<Rightarrow>
   (trust_address \<Rightarrow> nat)"
where
  "move_balance balances source destination amount =
     (balances(source := balances source - amount))
       (destination := balances destination + amount)"

definition forward_success_state ::
  "trust_compositional_state \<Rightarrow> trust_forward_command \<Rightarrow>
   trust_success_witness \<Rightarrow> trust_compositional_state"
where
  "forward_success_state st command witness =
     (let base = base_forward_success st command witness;
          subject = forward_subject command;
          source = forward_source command;
          destination = forward_destination command;
          custodian = forward_custodian command;
          amount = forward_amount command;
          case_id = forward_case command;
          action_id = forward_action_id command;
          cs = case_records st case_id
      in case forward_action command of
        Legal_Freeze \<Rightarrow>
          base\<lparr>
            frozen_targets := (frozen_targets base)(subject := amount),
            freeze_heads := (freeze_heads base)
              (subject := pushed_head (freeze_heads st subject) action_id),
            effect_links := (effect_links base)
              (action_id := Some (pushed_link (freeze_heads st subject))),
            case_records := (case_records base)
              (case_id := opened_overlay cs Family_Freeze action_id)
          \<rparr>
      | Legal_Restrict \<Rightarrow>
          base\<lparr>
            restriction_flags := (restriction_flags base)(subject := True),
            restriction_heads := (restriction_heads base)
              (subject := pushed_head (restriction_heads st subject) action_id),
            effect_links := (effect_links base)
              (action_id := Some (pushed_link (restriction_heads st subject))),
            case_records := (case_records base)
              (case_id := opened_overlay cs Family_Restrict action_id)
          \<rparr>
      | Legal_Seize \<Rightarrow>
          base\<lparr>
            physical_balances := move_balance (physical_balances base) source custodian amount,
            custody_backing :=
              (custody_backing base)(custodian := custody_backing base custodian + amount),
            custody_records := (custody_records base)
              (case_id := Some
                \<lparr>custody_custodian = custodian,
                 custody_prior_holder = subject,
                 custody_amount = amount,
                 custody_action = Some action_id,
                 custody_active = True\<rparr>),
            case_records := (case_records base)(case_id := opened_custody cs action_id)
          \<rparr>
      | _ \<Rightarrow>
          (let consumed = uses_active_custody st command
           in base\<lparr>
             physical_balances := move_balance (physical_balances base) source destination amount,
             custody_backing :=
               (if consumed
                then (custody_backing base)(source := custody_backing base source - amount)
                else custody_backing base),
             custody_records :=
               (if consumed then close_custody base case_id else custody_records base),
             consumed_entitlements :=
               (if forward_action command = Legal_Recover
                then insert (forward_entitlement_commitment command) (consumed_entitlements base)
                else consumed_entitlements base),
             case_records := (case_records base)(case_id := disposed_case cs consumed)
           \<rparr>))"

section \<open>Reversals\<close>

definition reversal_original ::
  "trust_compositional_state \<Rightarrow> trust_reversal_command \<Rightarrow>
   compositional_action_record option"
where
  "reversal_original st command =
     action_records st (reversal_original_action_id command)"

definition reversal_pairs :: "trust_reversal_kind \<Rightarrow> legal_action_kind \<Rightarrow> bool" where
  "reversal_pairs kind action \<longleftrightarrow>
     (kind = TRUST_UNFREEZE \<and> action = Legal_Freeze) \<or>
     (kind = TRUST_RELEASE \<and> action = Legal_Seize) \<or>
     (kind = TRUST_UNRESTRICT \<and> action = Legal_Restrict)"

definition reversal_current_effect ::
  "trust_compositional_state \<Rightarrow> trust_reversal_command \<Rightarrow>
   compositional_action_record \<Rightarrow> bool"
where
  "reversal_current_effect st command original \<longleftrightarrow>
     (let action_id = reversal_original_action_id command;
          subject = abstract_subject original
      in case reversal_kind command of
        TRUST_UNFREEZE \<Rightarrow>
          effect_links st action_id \<noteq> None \<and>
          head_action (freeze_heads st subject) = Some action_id \<and>
          frozen_targets st subject = abstract_amount original
      | TRUST_UNRESTRICT \<Rightarrow>
          effect_links st action_id \<noteq> None \<and>
          head_action (restriction_heads st subject) = Some action_id \<and>
          restriction_flags st subject
      | TRUST_RELEASE \<Rightarrow>
          (case custody_records st (abstract_case original) of
             Some custody \<Rightarrow>
               custody_active custody \<and>
               custody_action custody = Some action_id \<and>
               custody_custodian custody = abstract_custodian original \<and>
               custody_prior_holder custody = abstract_source original \<and>
               custody_amount custody = abstract_amount original \<and>
               custody_amount custody \<le> custody_backing st (custody_custodian custody)
           | None \<Rightarrow> False))"

definition reversal_admissible ::
  "trust_compositional_state \<Rightarrow> trust_reversal_command \<Rightarrow> bool"
where
  "reversal_admissible st command \<longleftrightarrow>
     reversal_id command \<noteq> 0 \<and>
     reversal_provenance_commitment command \<noteq> 0 \<and>
     (case reversal_original st command of
        None \<Rightarrow> False
      | Some original \<Rightarrow>
          \<not> terminal_case st (abstract_case original) \<and>
          abstract_lifecycle original = Record_Applied \<and>
          reversal_pairs (reversal_kind command) (abstract_action original) \<and>
          reversal_current_effect st command original)"

definition popped_head ::
  "compositional_effect_head \<Rightarrow> trust_action_id option \<Rightarrow> compositional_effect_head"
where
  "popped_head head parent =
     \<lparr>head_action = parent, head_generation = head_generation head + 1\<rparr>"

definition link_parent ::
  "trust_compositional_state \<Rightarrow> trust_action_id \<Rightarrow> trust_action_id option"
where
  "link_parent st action_id =
     (case effect_links st action_id of Some link \<Rightarrow> effect_parent link | None \<Rightarrow> None)"

definition reopened_or_closed ::
  "compositional_case \<Rightarrow> trust_action_id option \<Rightarrow> compositional_case"
where
  "reopened_or_closed cs parent =
     (case parent of
        Some head \<Rightarrow> cs\<lparr>case_head := Some head, case_generation := case_generation cs + 1\<rparr>
      | None \<Rightarrow> closed_case cs)"

definition reversal_success_state ::
  "trust_compositional_state \<Rightarrow> trust_reversal_command \<Rightarrow>
   trust_reversal_witness \<Rightarrow> trust_compositional_state"
where
  "reversal_success_state st command witness =
     (case reversal_original st command of
        None \<Rightarrow> st
      | Some original \<Rightarrow>
          let action_id = reversal_original_action_id command;
              case_id = abstract_case original;
              subject = abstract_subject original;
              cs = case_records st case_id;
              base = st\<lparr>
                compositional_consumed_nonces :=
                  insert (reversal_nonce_key command) (compositional_consumed_nonces st),
                compositional_receipts := (compositional_receipts st)
                  (reversal_id command := Some (reversal_witness_receipt witness)),
                action_records := (action_records st)
                  (action_id := Some (original\<lparr>abstract_lifecycle := Record_Reversed\<rparr>))
              \<rparr>
          in case reversal_kind command of
            TRUST_UNFREEZE \<Rightarrow>
              (let parent = link_parent st action_id
               in base\<lparr>
                 frozen_targets :=
                   (frozen_targets base)(subject := abstract_prior_amount original),
                 freeze_heads := (freeze_heads base)
                   (subject := popped_head (freeze_heads st subject) parent),
                 case_records := (case_records base)(case_id := reopened_or_closed cs parent)
               \<rparr>)
          | TRUST_UNRESTRICT \<Rightarrow>
              (let parent = link_parent st action_id
               in base\<lparr>
                 restriction_flags :=
                   (restriction_flags base)(subject := abstract_prior_flag original),
                 restriction_heads := (restriction_heads base)
                   (subject := popped_head (restriction_heads st subject) parent),
                 case_records := (case_records base)(case_id := closed_case cs)
               \<rparr>)
          | TRUST_RELEASE \<Rightarrow>
              (case custody_records st case_id of
                 None \<Rightarrow> st
               | Some custody \<Rightarrow>
                   let custodian = custody_custodian custody;
                       holder = custody_prior_holder custody;
                       amount = custody_amount custody
                   in base\<lparr>
                     physical_balances :=
                       move_balance (physical_balances base) custodian holder amount,
                     custody_backing :=
                       (custody_backing base)
                         (custodian := custody_backing base custodian - amount),
                     custody_records := close_custody base case_id,
                     case_records := (case_records base)(case_id := closed_case cs)
                   \<rparr>))"

section \<open>Governance and ordinary transfers\<close>

definition rotate_authority ::
  "trust_compositional_state \<Rightarrow> trust_authority_ref \<Rightarrow> trust_address \<Rightarrow> bool \<Rightarrow>
   trust_compositional_state"
where
  "rotate_authority st ref account active =
     st\<lparr>authorities := (authorities st)
          (ref := Some
            \<lparr>authority_account = account,
             authority_epoch =
               (case authorities st ref of Some authority \<Rightarrow> authority_epoch authority | None \<Rightarrow> 0) + 1,
             authority_active = active\<rparr>)\<rparr>"

definition rebind_dependency ::
  "trust_compositional_state \<Rightarrow> trust_binding_kind \<Rightarrow> compositional_binding \<Rightarrow> trust_hash \<Rightarrow>
   trust_compositional_state"
where
  "rebind_dependency st kind binding root =
     st\<lparr>compositional_bindings := (compositional_bindings st)(kind := Some binding),
        dependency_epoch := dependency_epoch st + 1,
        dependency_root := root\<rparr>"

definition ordinary_transfer_allowed ::
  "trust_compositional_state \<Rightarrow> trust_address \<Rightarrow> trust_address \<Rightarrow> nat \<Rightarrow> bool"
where
  "ordinary_transfer_allowed st source destination amount \<longleftrightarrow>
     source \<noteq> 0 \<and> destination \<noteq> 0 \<and>
     \<not> restriction_flags st source \<and> \<not> restriction_flags st destination \<and>
     amount \<le> physical_balances st source \<and>
     amount \<le> ordinary_available st source"

definition ordinary_transfer_state ::
  "trust_compositional_state \<Rightarrow> trust_address \<Rightarrow> trust_address \<Rightarrow> nat \<Rightarrow>
   trust_compositional_state"
where
  "ordinary_transfer_state st source destination amount =
     st\<lparr>physical_balances := move_balance (physical_balances st) source destination amount\<rparr>"

definition abstract_failure_transition ::
  "trust_compositional_state \<Rightarrow> trust_abstract_failure \<Rightarrow>
   trust_compositional_state \<times> trust_abstract_failure"
where
  "abstract_failure_transition state failure = (state, failure)"

section \<open>Forward transition theorems\<close>

theorem freeze_success_sets_absolute_target:
  assumes "forward_action command = Legal_Freeze"
  shows "frozen_targets (forward_success_state state command witness)
           (forward_subject command) = forward_amount command"
  using assms by (simp add: forward_success_state_def base_forward_success_def Let_def)

theorem freeze_success_requires_strict_increase:
  assumes "forward_shape_wf state command"
      and "forward_action command = Legal_Freeze"
  shows "frozen_targets state (forward_subject command) < forward_amount command"
  using assms by (simp add: forward_shape_wf_def)

theorem freeze_success_pushes_the_live_head:
  assumes "forward_action command = Legal_Freeze"
  shows "head_action (freeze_heads (forward_success_state state command witness)
           (forward_subject command)) = Some (forward_action_id command) \<and>
         effect_links (forward_success_state state command witness) (forward_action_id command) =
           Some (pushed_link (freeze_heads state (forward_subject command)))"
  using assms
  by (simp add: forward_success_state_def base_forward_success_def pushed_head_def Let_def)

theorem freeze_success_records_prior_target:
  assumes "forward_action command = Legal_Freeze"
  shows "map_option abstract_prior_amount
           (action_records (forward_success_state state command witness) (forward_action_id command)) =
         Some (frozen_targets state (forward_subject command))"
  using assms
  by (simp add: forward_success_state_def base_forward_success_def forward_action_record_def Let_def)

theorem freeze_success_opens_or_amends_the_freeze_case:
  assumes "forward_action command = Legal_Freeze"
  shows "case_records (forward_success_state state command witness) (forward_case command) =
         opened_overlay (case_records state (forward_case command)) Family_Freeze
           (forward_action_id command)"
  using assms by (simp add: forward_success_state_def base_forward_success_def Let_def)

theorem restrict_success_sets_flag:
  assumes "forward_action command = Legal_Restrict"
  shows "restriction_flags (forward_success_state state command witness)
           (forward_subject command)"
  using assms by (simp add: forward_success_state_def base_forward_success_def Let_def)

theorem restrict_success_records_prior_flag:
  assumes "forward_action command = Legal_Restrict"
  shows "map_option abstract_prior_flag
           (action_records (forward_success_state state command witness) (forward_action_id command)) =
         Some (restriction_flags state (forward_subject command))"
  using assms
  by (simp add: forward_success_state_def base_forward_success_def forward_action_record_def Let_def)

theorem seize_success_opens_custody:
  assumes "forward_action command = Legal_Seize"
      and "forward_source command \<noteq> forward_custodian command"
  shows "custody_backing (forward_success_state state command witness)
           (forward_custodian command) =
         custody_backing state (forward_custodian command) + forward_amount command \<and>
         custody_records (forward_success_state state command witness) (forward_case command) =
           Some \<lparr>custody_custodian = forward_custodian command,
                 custody_prior_holder = forward_subject command,
                 custody_amount = forward_amount command,
                 custody_action = Some (forward_action_id command),
                 custody_active = True\<rparr> \<and>
         case_records (forward_success_state state command witness) (forward_case command) =
           opened_custody (case_records state (forward_case command)) (forward_action_id command)"
  using assms by (simp add: forward_success_state_def base_forward_success_def Let_def)

theorem seize_success_moves_exact_amount_to_custodian:
  assumes "forward_action command = Legal_Seize"
      and "forward_source command \<noteq> forward_custodian command"
  shows "physical_balances (forward_success_state state command witness) (forward_custodian command) =
           physical_balances state (forward_custodian command) + forward_amount command \<and>
         physical_balances (forward_success_state state command witness) (forward_source command) =
           physical_balances state (forward_source command) - forward_amount command"
  using assms by (simp add: forward_success_state_def base_forward_success_def move_balance_def Let_def)

lemma disposition_success_state:
  assumes "forward_action command = Legal_Confiscate \<or>
           forward_action command = Legal_Liquidate \<or>
           forward_action command = Legal_Recover"
  shows "forward_success_state state command witness =
         (let base = base_forward_success state command witness;
              consumed = uses_active_custody state command
          in base\<lparr>
            physical_balances :=
              move_balance (physical_balances base) (forward_source command)
                (forward_destination command) (forward_amount command),
            custody_backing :=
              (if consumed
               then (custody_backing base)
                 (forward_source command :=
                    custody_backing base (forward_source command) - forward_amount command)
               else custody_backing base),
            custody_records :=
              (if consumed then close_custody base (forward_case command)
               else custody_records base),
            consumed_entitlements :=
              (if forward_action command = Legal_Recover
               then insert (forward_entitlement_commitment command) (consumed_entitlements base)
               else consumed_entitlements base),
            case_records := (case_records base)
              (forward_case command := disposed_case (case_records state (forward_case command)) consumed)
          \<rparr>)"
  using assms by (auto simp: forward_success_state_def Let_def)

theorem confiscate_success_is_terminal:
  assumes "forward_action command = Legal_Confiscate"
  shows "terminal_case (forward_success_state state command witness) (forward_case command)"
  using assms
  by (simp add: disposition_success_state terminal_case_def disposed_case_def Let_def)

theorem liquidate_success_is_terminal:
  assumes "forward_action command = Legal_Liquidate"
  shows "terminal_case (forward_success_state state command witness) (forward_case command)"
  using assms
  by (simp add: disposition_success_state terminal_case_def disposed_case_def Let_def)

theorem recover_success_is_terminal:
  assumes "forward_action command = Legal_Recover"
  shows "terminal_case (forward_success_state state command witness) (forward_case command)"
  using assms
  by (simp add: disposition_success_state terminal_case_def disposed_case_def Let_def)

theorem disposition_success_moves_exact_amount:
  assumes "forward_action command = Legal_Confiscate \<or>
           forward_action command = Legal_Liquidate \<or>
           forward_action command = Legal_Recover"
      and "forward_source command \<noteq> forward_destination command"
  shows "physical_balances (forward_success_state state command witness) (forward_destination command) =
           physical_balances state (forward_destination command) + forward_amount command \<and>
         physical_balances (forward_success_state state command witness) (forward_source command) =
           physical_balances state (forward_source command) - forward_amount command"
  using assms
  by (simp add: disposition_success_state base_forward_success_def move_balance_def Let_def)

theorem confiscate_does_not_burn:
  assumes "forward_action command = Legal_Confiscate"
  shows "compositional_total_supply (forward_success_state state command witness) =
         compositional_total_supply state"
  using assms by (simp add: disposition_success_state base_forward_success_def Let_def)

theorem liquidate_success_binds_settlement_in_receipt:
  assumes "forward_action command = Legal_Liquidate"
      and "receipt_matches_forward command witness"
  shows "compositional_external_commitment (witness_receipt witness) =
         settlement_pair_commitment (forward_settlement_commitment command)
           (forward_proceeds_commitment command) \<and>
         compositional_receipts (forward_success_state state command witness)
           (forward_action_id command) = Some (witness_receipt witness)"
  using assms
  by (simp add: receipt_matches_forward_def forward_external_commitment_def
      disposition_success_state base_forward_success_def Let_def)

theorem recover_success_consumes_entitlement:
  assumes "forward_action command = Legal_Recover"
  shows "forward_entitlement_commitment command \<in>
           consumed_entitlements (forward_success_state state command witness)"
  using assms by (simp add: disposition_success_state base_forward_success_def Let_def)

theorem consumed_entitlement_is_rejected:
  assumes "forward_action command = Legal_Recover"
      and "forward_entitlement_commitment command \<in> consumed_entitlements state"
  shows "\<not> forward_shape_wf state command"
  using assms by (simp add: forward_shape_wf_def)

theorem custody_disposition_consumes_the_custody_record:
  assumes "forward_action command = Legal_Confiscate \<or>
           forward_action command = Legal_Liquidate \<or>
           forward_action command = Legal_Recover"
      and "uses_active_custody state command"
  shows "custody_backing (forward_success_state state command witness) (forward_source command) =
           custody_backing state (forward_source command) - forward_amount command \<and>
         map_option custody_active
           (custody_records (forward_success_state state command witness) (forward_case command)) =
           Some False"
  using assms
  by (auto simp: disposition_success_state base_forward_success_def close_custody_def
      uses_active_custody_def Let_def split: option.splits)

theorem forward_success_consumes_nonce_and_command_id:
  "forward_nonce_key command \<in>
     compositional_consumed_nonces (forward_success_state state command witness) \<and>
   map_option abstract_lifecycle
     (action_records (forward_success_state state command witness) (forward_action_id command)) =
     Some Record_Applied \<and>
   compositional_receipts (forward_success_state state command witness)
     (forward_action_id command) = Some (witness_receipt witness)"
  by (cases "forward_action command")
     (simp_all add: forward_success_state_def base_forward_success_def
        forward_action_record_def Let_def)

theorem forward_success_preserves_total_supply:
  "compositional_total_supply (forward_success_state state command witness) =
   compositional_total_supply state"
  by (cases "forward_action command")
     (simp_all add: forward_success_state_def base_forward_success_def Let_def)

theorem forward_success_preserves_dependency_state:
  "dependency_root (forward_success_state state command witness) = dependency_root state \<and>
   dependency_epoch (forward_success_state state command witness) = dependency_epoch state"
  by (cases "forward_action command")
     (simp_all add: forward_success_state_def base_forward_success_def Let_def)

section \<open>Case transition table theorems\<close>

theorem terminal_case_rejects_action:
  assumes "terminal_case state (forward_case command)"
  shows "\<not> forward_shape_wf state command"
  using assms by (simp add: forward_shape_wf_def)

theorem disposition_on_open_overlay_case_is_rejected:
  assumes "forward_action command = Legal_Confiscate \<or>
           forward_action command = Legal_Liquidate \<or>
           forward_action command = Legal_Recover"
      and "open_case state (forward_case command)"
      and "case_family (case_records state (forward_case command)) \<noteq> Family_Custody"
  shows "\<not> forward_shape_wf state command"
  using assms by (auto simp: forward_shape_wf_def disposition_wf_def)

theorem overlay_on_open_case_without_head_is_rejected:
  assumes "forward_action command = Legal_Freeze \<or> forward_action command = Legal_Restrict"
      and "head_action (freeze_heads state (forward_subject command)) = None"
      and "head_action (restriction_heads state (forward_subject command)) = None"
      and "case_phase (case_records state (forward_case command)) \<noteq> Case_None"
  shows "\<not> forward_shape_wf state command"
  using assms by (auto simp: forward_shape_wf_def overlay_admissible_def)

theorem cross_case_overlay_head_is_rejected:
  assumes "forward_action command = Legal_Freeze"
      and "head_action (freeze_heads state (forward_subject command)) = Some head"
      and "case_head (case_records state (forward_case command)) \<noteq> Some head"
  shows "\<not> forward_shape_wf state command"
  using assms by (auto simp: forward_shape_wf_def overlay_admissible_def)

theorem cross_case_restriction_head_is_rejected:
  assumes "forward_action command = Legal_Restrict"
      and "head_action (restriction_heads state (forward_subject command)) = Some head"
      and "case_head (case_records state (forward_case command)) \<noteq> Some head"
  shows "\<not> forward_shape_wf state command"
  using assms by (auto simp: forward_shape_wf_def overlay_admissible_def)

theorem second_restrict_in_own_case_is_rejected:
  assumes "forward_action command = Legal_Restrict"
      and "head_action (restriction_heads state (forward_subject command)) = Some head"
      and "case_head (case_records state (forward_case command)) = Some head"
  shows "\<not> forward_shape_wf state command"
  using assms by (auto simp: forward_shape_wf_def restrict_would_not_change_state_def)

theorem second_seize_in_open_case_is_rejected:
  assumes "forward_action command = Legal_Seize"
      and "open_case state (forward_case command)"
  shows "\<not> forward_shape_wf state command"
  using assms by (simp add: forward_shape_wf_def)

theorem direct_disposition_requires_source_to_be_the_subject:
  assumes "forward_action command = Legal_Confiscate \<or>
           forward_action command = Legal_Liquidate \<or>
           forward_action command = Legal_Recover"
      and "\<not> open_case state (forward_case command)"
      and "forward_source command \<noteq> forward_subject command"
  shows "\<not> forward_shape_wf state command"
  using assms by (auto simp: forward_shape_wf_def disposition_wf_def)

theorem custody_disposition_requires_the_exact_custody_record:
  assumes "forward_action command = Legal_Confiscate \<or>
           forward_action command = Legal_Liquidate \<or>
           forward_action command = Legal_Recover"
      and "open_case state (forward_case command)"
      and "\<not> custody_matches state command"
  shows "\<not> forward_shape_wf state command"
  using assms by (auto simp: forward_shape_wf_def disposition_wf_def)

theorem direct_disposition_cannot_spend_custody_backing:
  assumes "forward_action command = Legal_Confiscate \<or>
           forward_action command = Legal_Liquidate \<or>
           forward_action command = Legal_Recover"
      and "\<not> open_case state (forward_case command)"
      and "\<not> unbacked_available state (forward_source command) (forward_amount command)"
  shows "\<not> forward_shape_wf state command"
  using assms by (auto simp: forward_shape_wf_def disposition_wf_def)

theorem seize_cannot_spend_custody_backing:
  assumes "forward_action command = Legal_Seize"
      and "\<not> unbacked_available state (forward_source command) (forward_amount command)"
  shows "\<not> forward_shape_wf state command"
  using assms by (simp add: forward_shape_wf_def)

theorem freeze_preserves_restriction_overlay:
  assumes "forward_action command = Legal_Freeze"
  shows "restriction_flags (forward_success_state state command witness) = restriction_flags state"
  using assms by (simp add: forward_success_state_def base_forward_success_def Let_def)

theorem restrict_preserves_freeze_overlay:
  assumes "forward_action command = Legal_Restrict"
  shows "frozen_targets (forward_success_state state command witness) = frozen_targets state"
  using assms by (simp add: forward_success_state_def base_forward_success_def Let_def)

theorem freeze_and_restriction_are_independent:
  assumes "forward_action freeze_command = Legal_Freeze"
      and "forward_action restriction_command = Legal_Restrict"
      and "forward_subject restriction_command = forward_subject freeze_command"
  shows "let frozen_state = forward_success_state state freeze_command freeze_witness;
             combined_state =
               forward_success_state frozen_state restriction_command restriction_witness
         in frozen_targets combined_state (forward_subject freeze_command) =
              forward_amount freeze_command \<and>
            restriction_flags combined_state (forward_subject freeze_command)"
  using freeze_success_sets_absolute_target[OF assms(1)]
    restrict_preserves_freeze_overlay[OF assms(2)]
    restrict_success_sets_flag[OF assms(2)] assms(3)
  by (simp add: Let_def)

theorem case_terminality_is_scoped:
  assumes "forward_action command = Legal_Confiscate \<or>
           forward_action command = Legal_Liquidate \<or>
           forward_action command = Legal_Recover"
      and "other_case \<noteq> forward_case command"
  shows "terminal_case (forward_success_state state command witness) (forward_case command) \<and>
         case_records (forward_success_state state command witness) other_case =
           case_records state other_case"
  using assms
  by (simp add: disposition_success_state base_forward_success_def terminal_case_def
      disposed_case_def Let_def)

theorem disposition_in_one_case_does_not_clear_another_overlay:
  assumes "forward_action command = Legal_Confiscate \<or>
           forward_action command = Legal_Liquidate \<or>
           forward_action command = Legal_Recover"
  shows "frozen_targets (forward_success_state state command witness) = frozen_targets state \<and>
         restriction_flags (forward_success_state state command witness) = restriction_flags state"
  using assms by (simp add: disposition_success_state base_forward_success_def Let_def)

section \<open>Reversal theorems\<close>

theorem unfreeze_success_restores_prior_target:
  assumes "reversal_original state command = Some original"
      and "reversal_kind command = TRUST_UNFREEZE"
  shows "frozen_targets (reversal_success_state state command witness)
           (abstract_subject original) = abstract_prior_amount original"
  using assms by (simp add: reversal_success_state_def Let_def)

theorem unfreeze_reopens_the_case_when_a_parent_remains:
  assumes "reversal_original state command = Some original"
      and "reversal_kind command = TRUST_UNFREEZE"
      and "link_parent state (reversal_original_action_id command) = Some parent"
  shows "case_records (reversal_success_state state command witness) (abstract_case original) =
           (case_records state (abstract_case original))
             \<lparr>case_head := Some parent,
              case_generation := case_generation (case_records state (abstract_case original)) + 1\<rparr> \<and>
         head_action (freeze_heads (reversal_success_state state command witness)
           (abstract_subject original)) = Some parent"
  using assms by (simp add: reversal_success_state_def reopened_or_closed_def popped_head_def Let_def)

theorem unfreeze_closes_the_case_when_the_chain_is_empty:
  assumes "reversal_original state command = Some original"
      and "reversal_kind command = TRUST_UNFREEZE"
      and "link_parent state (reversal_original_action_id command) = None"
  shows "terminal_case (reversal_success_state state command witness) (abstract_case original) \<and>
         head_action (freeze_heads (reversal_success_state state command witness)
           (abstract_subject original)) = None"
  using assms
  by (simp add: reversal_success_state_def reopened_or_closed_def popped_head_def
      closed_case_def terminal_case_def Let_def)

theorem unrestrict_success_restores_prior_flag_and_closes_case:
  assumes "reversal_original state command = Some original"
      and "reversal_kind command = TRUST_UNRESTRICT"
  shows "restriction_flags (reversal_success_state state command witness)
           (abstract_subject original) = abstract_prior_flag original \<and>
         terminal_case (reversal_success_state state command witness) (abstract_case original)"
  using assms
  by (simp add: reversal_success_state_def closed_case_def terminal_case_def Let_def)

theorem release_success_returns_custody_and_closes_case:
  assumes "reversal_original state command = Some original"
      and "reversal_kind command = TRUST_RELEASE"
      and "custody_records state (abstract_case original) = Some custody"
      and "custody_custodian custody \<noteq> custody_prior_holder custody"
  shows "physical_balances (reversal_success_state state command witness)
           (custody_prior_holder custody) =
           physical_balances state (custody_prior_holder custody) + custody_amount custody \<and>
         custody_backing (reversal_success_state state command witness)
           (custody_custodian custody) =
           custody_backing state (custody_custodian custody) - custody_amount custody \<and>
         map_option custody_active
           (custody_records (reversal_success_state state command witness)
             (abstract_case original)) = Some False \<and>
         terminal_case (reversal_success_state state command witness) (abstract_case original)"
  using assms
  by (simp add: reversal_success_state_def close_custody_def closed_case_def
      terminal_case_def move_balance_def Let_def)

theorem reversal_success_marks_the_original_reversed:
  assumes "reversal_original state command = Some original"
      and "reversal_kind command \<noteq> TRUST_RELEASE \<or>
           custody_records state (abstract_case original) \<noteq> None"
  shows "map_option abstract_lifecycle
           (action_records (reversal_success_state state command witness)
             (reversal_original_action_id command)) = Some Record_Reversed \<and>
         compositional_receipts (reversal_success_state state command witness)
           (reversal_id command) = Some (reversal_witness_receipt witness) \<and>
         reversal_nonce_key command \<in>
           compositional_consumed_nonces (reversal_success_state state command witness)"
  using assms
  by (cases "reversal_kind command")
     (auto simp: reversal_success_state_def Let_def split: option.splits)

theorem reversal_success_preserves_total_supply:
  "compositional_total_supply (reversal_success_state state command witness) =
   compositional_total_supply state"
  by (cases "reversal_kind command")
     (auto simp: reversal_success_state_def Let_def split: option.splits)

theorem terminal_case_rejects_reversal:
  assumes "reversal_original state command = Some original"
      and "terminal_case state (abstract_case original)"
  shows "\<not> reversal_admissible state command"
  using assms by (simp add: reversal_admissible_def)

theorem unknown_original_is_not_admissible:
  assumes "reversal_original state command = None"
  shows "\<not> reversal_admissible state command"
  using assms by (simp add: reversal_admissible_def)

theorem reversed_action_cannot_be_reversed_again:
  assumes "reversal_original state command = Some original"
      and "abstract_lifecycle original \<noteq> Record_Applied"
  shows "\<not> reversal_admissible state command"
  using assms by (simp add: reversal_admissible_def)

theorem mispaired_reversal_is_not_admissible:
  assumes "reversal_original state command = Some original"
      and "\<not> reversal_pairs (reversal_kind command) (abstract_action original)"
  shows "\<not> reversal_admissible state command"
  using assms by (simp add: reversal_admissible_def)

theorem stale_freeze_reversal_is_not_admissible:
  assumes "reversal_original state command = Some original"
      and "reversal_kind command = TRUST_UNFREEZE"
      and "head_action (freeze_heads state (abstract_subject original)) \<noteq>
             Some (reversal_original_action_id command)"
  shows "\<not> reversal_admissible state command"
  using assms by (simp add: reversal_admissible_def reversal_current_effect_def Let_def)

theorem stale_restriction_reversal_is_not_admissible:
  assumes "reversal_original state command = Some original"
      and "reversal_kind command = TRUST_UNRESTRICT"
      and "head_action (restriction_heads state (abstract_subject original)) \<noteq>
             Some (reversal_original_action_id command)"
  shows "\<not> reversal_admissible state command"
  using assms by (simp add: reversal_admissible_def reversal_current_effect_def Let_def)

theorem release_requires_the_exact_active_custody:
  assumes "reversal_original state command = Some original"
      and "reversal_kind command = TRUST_RELEASE"
      and "\<forall>custody. custody_records state (abstract_case original) = Some custody \<longrightarrow>
             \<not> custody_active custody \<or>
             custody_action custody \<noteq> Some (reversal_original_action_id command)"
  shows "\<not> reversal_admissible state command"
  using assms
  by (auto simp: reversal_admissible_def reversal_current_effect_def Let_def split: option.splits)

theorem unfreeze_requires_the_target_of_the_original:
  assumes "reversal_original state command = Some original"
      and "reversal_kind command = TRUST_UNFREEZE"
      and "frozen_targets state (abstract_subject original) \<noteq> abstract_amount original"
  shows "\<not> reversal_admissible state command"
  using assms by (simp add: reversal_admissible_def reversal_current_effect_def Let_def)

theorem missing_reversal_provenance_is_not_admissible:
  assumes "reversal_provenance_commitment command = 0"
  shows "\<not> reversal_admissible state command"
  using assms by (simp add: reversal_admissible_def)

section \<open>Replay, staleness, authorization, and governance theorems\<close>

theorem replayed_action_is_not_fresh:
  assumes "action_records state (forward_action_id command) \<noteq> None"
  shows "\<not> forward_fresh state command"
  using assms by (simp add: forward_fresh_def)

theorem reused_nonce_is_not_fresh:
  assumes "forward_nonce_key command \<in> compositional_consumed_nonces state"
  shows "\<not> forward_fresh state command"
  using assms by (simp add: forward_fresh_def)

theorem replayed_reversal_is_not_fresh:
  assumes "compositional_receipts state (reversal_id command) \<noteq> None"
  shows "\<not> reversal_fresh state command"
  using assms by (simp add: reversal_fresh_def)

theorem successful_action_is_not_fresh_afterwards:
  "\<not> forward_fresh (forward_success_state state command witness) command"
  using forward_success_consumes_nonce_and_command_id[of command state witness]
  by (auto simp: forward_fresh_def)

theorem stale_dependency_root_is_not_current:
  assumes "forward_dependency_root command \<noteq> dependency_root state"
  shows "\<not> forward_current_dependency state command"
  using assms by (simp add: forward_current_dependency_def)

theorem stale_dependency_epoch_is_not_current:
  assumes "forward_dependency_epoch command \<noteq> dependency_epoch state"
  shows "\<not> forward_current_dependency state command"
  using assms by (simp add: forward_current_dependency_def)

theorem rebind_makes_prior_commands_stale:
  assumes "forward_current_dependency state command"
  shows "\<not> forward_current_dependency (rebind_dependency state kind binding root) command"
  using assms by (simp add: forward_current_dependency_def rebind_dependency_def)

theorem rebind_makes_prior_reversals_stale:
  assumes "reversal_current_dependency state command"
  shows "\<not> reversal_current_dependency (rebind_dependency state kind binding root) command"
  using assms by (simp add: reversal_current_dependency_def rebind_dependency_def)

theorem rebind_advances_the_global_epoch_by_one:
  "dependency_epoch (rebind_dependency state kind binding root) = dependency_epoch state + 1"
  by (simp add: rebind_dependency_def)

theorem unauthorized_sender_is_rejected:
  assumes "authorities state (forward_authority_ref command) = Some authority"
      and "authority_account authority \<noteq> sender \<or> \<not> authority_active authority"
  shows "\<not> forward_authorized state sender command"
  using assms by (auto simp: forward_authorized_def authority_admits_def)

theorem stale_authority_epoch_is_rejected:
  assumes "authorities state (forward_authority_ref command) = Some authority"
      and "authority_epoch authority \<noteq> forward_authority_epoch command"
  shows "\<not> forward_authorized state sender command"
  using assms by (simp add: forward_authorized_def authority_admits_def)

theorem unknown_authority_is_rejected:
  assumes "authorities state (forward_authority_ref command) = None"
  shows "\<not> forward_authorized state sender command"
  using assms by (simp add: forward_authorized_def authority_admits_def)

theorem authority_rotation_makes_prior_commands_stale:
  assumes "forward_authorized state sender command"
  shows "\<not> forward_authorized (rotate_authority state (forward_authority_ref command) account active)
           sender' command"
  using assms
  by (auto simp: forward_authorized_def authority_admits_def rotate_authority_def
      split: option.splits)

theorem expired_window_is_rejected:
  assumes "time > forward_valid_before command \<or> time < forward_valid_after command \<or>
           forward_valid_before command = 0"
  shows "\<not> forward_in_window time command"
  using assms by (auto simp: forward_in_window_def within_window_def)

section \<open>Ordinary transfers\<close>

theorem ordinary_transfer_respects_restriction_flags:
  assumes "restriction_flags state source \<or> restriction_flags state destination"
  shows "\<not> ordinary_transfer_allowed state source destination amount"
  using assms by (auto simp: ordinary_transfer_allowed_def)

theorem ordinary_transfer_cannot_spend_the_frozen_floor_or_custody_backing:
  assumes "ordinary_transfer_allowed state source destination amount"
  shows "amount \<le> physical_balances state source - required_floor state source"
  using assms by (simp add: ordinary_transfer_allowed_def ordinary_available_def)

theorem ordinary_transfer_preserves_regulatory_state:
  "frozen_targets (ordinary_transfer_state state source destination amount) = frozen_targets state \<and>
   restriction_flags (ordinary_transfer_state state source destination amount) = restriction_flags state \<and>
   custody_backing (ordinary_transfer_state state source destination amount) = custody_backing state \<and>
   case_records (ordinary_transfer_state state source destination amount) = case_records state"
  by (simp add: ordinary_transfer_state_def)

section \<open>Failure stutters\<close>

theorem rejection_is_persistent_stutter:
  "fst (abstract_failure_transition state TRUST_Abstract_Rejection) = state"
  by (simp add: abstract_failure_transition_def)

theorem operational_failure_is_persistent_stutter:
  "fst (abstract_failure_transition state TRUST_Abstract_Operational_Failure) = state"
  by (simp add: abstract_failure_transition_def)

theorem malformed_input_is_persistent_stutter:
  "fst (abstract_failure_transition state TRUST_Abstract_Malformed_Input) = state"
  by (simp add: abstract_failure_transition_def)

theorem dependency_failure_is_persistent_stutter:
  "fst (abstract_failure_transition state TRUST_Abstract_Dependency_Failure) = state"
  by (simp add: abstract_failure_transition_def)

section \<open>Single-transaction relation\<close>

datatype trust_abstract_transaction_outcome =
    TRUST_Abstract_Applied
  | TRUST_Abstract_Rejected
  | TRUST_Abstract_Operational
  | TRUST_Abstract_Malformed
  | TRUST_Abstract_Dependency_Revert

record trust_transaction_bridge =
  bridge_decode_calldata :: "evm_bytes \<Rightarrow> trust_typed_command option"
  bridge_receipt_log :: "compositional_receipt \<Rightarrow> trust_raw_log"
  bridge_return_receipt_hash :: "evm_bytes \<Rightarrow> trust_hash option"
  bridge_external_trace_ok :: "trust_typed_command \<Rightarrow> trust_external_call list \<Rightarrow> bool"
  bridge_committed_receipt :: "trust_transaction_execution \<Rightarrow> compositional_receipt option"

record trust_transaction_abstraction =
  abstraction_pre_state :: trust_compositional_state
  abstraction_post_state :: trust_compositional_state
  abstraction_sender :: trust_address
  abstraction_time :: nat
  abstraction_command :: "trust_typed_command option"
  abstraction_outcome :: trust_abstract_transaction_outcome
  abstraction_forward_witness :: "trust_success_witness option"
  abstraction_reversal_witness :: "trust_reversal_witness option"
  abstraction_effect_logs :: "trust_raw_log list"

definition typed_decoder_sound :: "trust_transaction_bridge \<Rightarrow> bool" where
  "typed_decoder_sound bridge \<longleftrightarrow>
     (\<forall>calldata command.
       bridge_decode_calldata bridge calldata = Some command \<longrightarrow>
       length calldata =
         (case command of TRUST_Forward _ \<Rightarrow> action_calldata_length
          | TRUST_Reverse _ \<Rightarrow> reversal_calldata_length))"

definition forward_admitted ::
  "trust_compositional_state \<Rightarrow> trust_address \<Rightarrow> nat \<Rightarrow> trust_forward_command \<Rightarrow>
   trust_success_witness \<Rightarrow> bool"
where
  "forward_admitted st sender time command witness \<longleftrightarrow>
     forward_shape_wf st command \<and>
     forward_fresh st command \<and>
     forward_authorized st sender command \<and>
     forward_current_dependency st command \<and>
     forward_in_window time command \<and>
     receipt_matches_forward command witness"

definition reversal_admitted ::
  "trust_compositional_state \<Rightarrow> trust_address \<Rightarrow> nat \<Rightarrow> trust_reversal_command \<Rightarrow>
   trust_reversal_witness \<Rightarrow> bool"
where
  "reversal_admitted st sender time command witness \<longleftrightarrow>
     reversal_admissible st command \<and>
     reversal_fresh st command \<and>
     reversal_authorized st sender command \<and>
     reversal_current_dependency st command \<and>
     reversal_in_window time command \<and>
     (case reversal_original st command of
        Some original \<Rightarrow> receipt_matches_reversal command original witness
      | None \<Rightarrow> False)"

definition expected_success_state ::
  "trust_transaction_abstraction \<Rightarrow> trust_compositional_state option"
where
  "expected_success_state abstraction =
     (case (abstraction_command abstraction,
            abstraction_forward_witness abstraction,
            abstraction_reversal_witness abstraction) of
        (Some (TRUST_Forward command), Some witness, None) \<Rightarrow>
          (if forward_admitted (abstraction_pre_state abstraction)
                (abstraction_sender abstraction) (abstraction_time abstraction) command witness
           then Some (forward_success_state (abstraction_pre_state abstraction) command witness)
           else None)
      | (Some (TRUST_Reverse command), None, Some witness) \<Rightarrow>
          (if reversal_admitted (abstraction_pre_state abstraction)
                (abstraction_sender abstraction) (abstraction_time abstraction) command witness
           then Some (reversal_success_state (abstraction_pre_state abstraction) command witness)
           else None)
      | _ \<Rightarrow> None)"

definition abstraction_receipt ::
  "trust_transaction_abstraction \<Rightarrow> compositional_receipt option"
where
  "abstraction_receipt abstraction =
     (case (abstraction_forward_witness abstraction,
            abstraction_reversal_witness abstraction) of
        (Some witness, None) \<Rightarrow> Some (witness_receipt witness)
      | (None, Some witness) \<Rightarrow> Some (reversal_witness_receipt witness)
      | _ \<Rightarrow> None)"

definition canonical_receipt_trace ::
  "trust_transaction_bridge \<Rightarrow> trust_transaction_execution \<Rightarrow>
   trust_transaction_abstraction \<Rightarrow> bool"
where
  "canonical_receipt_trace bridge execution abstraction \<longleftrightarrow>
     (case abstraction_receipt abstraction of
        None \<Rightarrow> False
      | Some receipt \<Rightarrow>
          transaction_raw_logs execution =
            abstraction_effect_logs abstraction @ [bridge_receipt_log bridge receipt] \<and>
          (case transaction_result execution of
             TRUST_Return_Success payload \<Rightarrow>
               bridge_return_receipt_hash bridge payload =
                 Some (compositional_receipt_hash receipt)
           | _ \<Rightarrow> False))"

definition alpha_transaction ::
  "trust_runtime_manifest \<Rightarrow> trust_transaction_bridge \<Rightarrow>
   trust_transaction_execution \<Rightarrow> trust_transaction_abstraction \<Rightarrow> bool"
where
  "alpha_transaction manifest bridge execution abstraction \<longleftrightarrow>
     alpha_current manifest (transaction_pre execution) =
       Some (abstraction_pre_state abstraction) \<and>
     alpha_current manifest (transaction_post_configuration execution) =
       Some (abstraction_post_state abstraction) \<and>
     abstraction_sender abstraction = transaction_sender execution \<and>
     abstraction_time abstraction = transaction_time execution \<and>
     bridge_decode_calldata bridge (transaction_calldata execution) =
       abstraction_command abstraction \<and>
     (case abstraction_outcome abstraction of
        TRUST_Abstract_Applied \<Rightarrow>
          expected_success_state abstraction = Some (abstraction_post_state abstraction) \<and>
          (\<exists>command. abstraction_command abstraction = Some command \<and>
            bridge_external_trace_ok bridge command
              (transaction_external_calls execution)) \<and>
          canonical_receipt_trace bridge execution abstraction
      | TRUST_Abstract_Rejected \<Rightarrow>
          abstraction_post_state abstraction = abstraction_pre_state abstraction \<and>
          transaction_raw_logs execution = [] \<and>
          (\<exists>payload. transaction_result execution = TRUST_Return_Rejection payload)
      | TRUST_Abstract_Operational \<Rightarrow>
          abstraction_post_state abstraction = abstraction_pre_state abstraction \<and>
          transaction_raw_logs execution = [] \<and>
          (\<exists>payload. transaction_result execution =
            TRUST_Return_Operational_Failure payload)
      | TRUST_Abstract_Malformed \<Rightarrow>
          abstraction_command abstraction = None \<and>
          abstraction_post_state abstraction = abstraction_pre_state abstraction \<and>
          transaction_raw_logs execution = [] \<and>
          (\<exists>payload. transaction_result execution = TRUST_Return_Malformed payload)
      | TRUST_Abstract_Dependency_Revert \<Rightarrow>
          abstraction_post_state abstraction = abstraction_pre_state abstraction \<and>
          transaction_raw_logs execution = [] \<and>
          (\<exists>payload. transaction_result execution = TRUST_Return_Revert payload))"

fun map_some :: "('a \<Rightarrow> 'b option) \<Rightarrow> 'a list \<Rightarrow> 'b list" where
  "map_some project [] = []"
| "map_some project (value # values) =
     (case project value of
        None \<Rightarrow> map_some project values
      | Some result \<Rightarrow> result # map_some project values)"

definition alpha_history ::
  "trust_transaction_bridge \<Rightarrow> trust_committed_history_witness \<Rightarrow>
   compositional_receipt list \<Rightarrow> bool"
where
  "alpha_history bridge history trace \<longleftrightarrow>
     trace = map_some (bridge_committed_receipt bridge)
       (filter transaction_committed (committed_transactions history))"

theorem malformed_length_has_no_typed_command:
  assumes "typed_decoder_sound bridge"
      and "length calldata \<noteq> action_calldata_length"
      and "length calldata \<noteq> reversal_calldata_length"
  shows "bridge_decode_calldata bridge calldata = None"
proof (cases "bridge_decode_calldata bridge calldata")
  case None
  then show ?thesis by simp
next
  case (Some command)
  from assms(1) Some have
    "length calldata =
       (case command of TRUST_Forward _ \<Rightarrow> action_calldata_length
        | TRUST_Reverse _ \<Rightarrow> reversal_calldata_length)"
    unfolding typed_decoder_sound_def by blast
  with assms(2,3) show ?thesis by (cases command; simp)
qed

theorem successful_transaction_uses_abstract_success_state:
  assumes "alpha_transaction manifest bridge execution abstraction"
      and "abstraction_outcome abstraction = TRUST_Abstract_Applied"
  shows "expected_success_state abstraction = Some (abstraction_post_state abstraction)"
  using assms by (simp add: alpha_transaction_def)

theorem successful_forward_transaction_is_admitted:
  assumes "alpha_transaction manifest bridge execution abstraction"
      and "abstraction_outcome abstraction = TRUST_Abstract_Applied"
      and "abstraction_command abstraction = Some (TRUST_Forward command)"
      and "abstraction_forward_witness abstraction = Some witness"
      and "abstraction_reversal_witness abstraction = None"
  shows "forward_admitted (abstraction_pre_state abstraction) (transaction_sender execution)
           (transaction_time execution) command witness"
  using assms
  by (auto simp: alpha_transaction_def expected_success_state_def split: if_splits)

theorem successful_reversal_transaction_is_admitted:
  assumes "alpha_transaction manifest bridge execution abstraction"
      and "abstraction_outcome abstraction = TRUST_Abstract_Applied"
      and "abstraction_command abstraction = Some (TRUST_Reverse command)"
      and "abstraction_forward_witness abstraction = None"
      and "abstraction_reversal_witness abstraction = Some witness"
  shows "reversal_admitted (abstraction_pre_state abstraction) (transaction_sender execution)
           (transaction_time execution) command witness"
  using assms
  by (auto simp: alpha_transaction_def expected_success_state_def split: if_splits)

theorem successful_transaction_was_authorized_by_its_sender:
  assumes "alpha_transaction manifest bridge execution abstraction"
      and "abstraction_outcome abstraction = TRUST_Abstract_Applied"
      and "abstraction_command abstraction = Some (TRUST_Forward command)"
      and "abstraction_forward_witness abstraction = Some witness"
      and "abstraction_reversal_witness abstraction = None"
  shows "forward_authorized (abstraction_pre_state abstraction) (transaction_sender execution) command \<and>
         forward_current_dependency (abstraction_pre_state abstraction) command \<and>
         forward_fresh (abstraction_pre_state abstraction) command"
  using successful_forward_transaction_is_admitted[OF assms] by (simp add: forward_admitted_def)

theorem rejected_transaction_is_abstract_stutter:
  assumes "alpha_transaction manifest bridge execution abstraction"
      and "abstraction_outcome abstraction = TRUST_Abstract_Rejected"
  shows "abstraction_post_state abstraction = abstraction_pre_state abstraction"
  using assms by (simp add: alpha_transaction_def)

theorem operational_transaction_is_abstract_stutter:
  assumes "alpha_transaction manifest bridge execution abstraction"
      and "abstraction_outcome abstraction = TRUST_Abstract_Operational"
  shows "abstraction_post_state abstraction = abstraction_pre_state abstraction"
  using assms by (simp add: alpha_transaction_def)

theorem malformed_transaction_is_abstract_stutter:
  assumes "alpha_transaction manifest bridge execution abstraction"
      and "abstraction_outcome abstraction = TRUST_Abstract_Malformed"
  shows "abstraction_command abstraction = None \<and>
         abstraction_post_state abstraction = abstraction_pre_state abstraction"
  using assms by (simp add: alpha_transaction_def)

theorem dependency_revert_is_abstract_stutter:
  assumes "alpha_transaction manifest bridge execution abstraction"
      and "abstraction_outcome abstraction = TRUST_Abstract_Dependency_Revert"
  shows "abstraction_post_state abstraction = abstraction_pre_state abstraction"
  using assms by (simp add: alpha_transaction_def)

theorem success_has_final_canonical_receipt_event:
  assumes "alpha_transaction manifest bridge execution abstraction"
      and "abstraction_outcome abstraction = TRUST_Abstract_Applied"
      and "abstraction_receipt abstraction = Some receipt"
  shows "transaction_raw_logs execution \<noteq> [] \<and>
         last (transaction_raw_logs execution) = bridge_receipt_log bridge receipt"
  using assms
  by (auto simp: alpha_transaction_def canonical_receipt_trace_def)

theorem success_returns_the_stored_receipt_hash:
  assumes "alpha_transaction manifest bridge execution abstraction"
      and "abstraction_outcome abstraction = TRUST_Abstract_Applied"
      and "abstraction_receipt abstraction = Some receipt"
      and "transaction_result execution = TRUST_Return_Success payload"
  shows "bridge_return_receipt_hash bridge payload = Some (compositional_receipt_hash receipt)"
  using assms by (auto simp: alpha_transaction_def canonical_receipt_trace_def)

theorem committed_history_excludes_failure_receipts:
  assumes "alpha_history bridge history trace"
  shows "trace = map_some (bridge_committed_receipt bridge)
           (filter transaction_committed (committed_transactions history))"
  using assms by (simp add: alpha_history_def)

end
