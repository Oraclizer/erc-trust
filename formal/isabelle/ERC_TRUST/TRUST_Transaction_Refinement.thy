(* Abstract TRUST transaction steps and the single-transaction relation. *)

theory TRUST_Transaction_Refinement
  imports TRUST_Retrieve_Relation
begin

record trust_success_witness =
  witness_command_hash :: trust_hash
  witness_evidence_hash :: trust_hash
  witness_effect_parent :: "trust_action_id option"
  witness_effect_hash :: trust_hash
  witness_effect_generation :: nat
  witness_receipt :: compositional_receipt

record trust_reversal_witness =
  reversal_witness_command_hash :: trust_hash
  reversal_witness_parent_action :: "trust_action_id option"
  reversal_witness_parent_hash :: trust_hash
  reversal_witness_generation :: nat
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
      reversal_entrypoint_selector_def typed_failure_payload_def
      evm_bytes_selector_def)

definition forward_nonce_key :: "trust_forward_command \<Rightarrow> trust_nonce_key" where
  "forward_nonce_key command =
     (forward_authority_ref command, forward_authority_epoch command,
      forward_nonce command)"

definition reversal_nonce_key :: "trust_reversal_command \<Rightarrow> trust_nonce_key" where
  "reversal_nonce_key command =
     (reversal_authority_ref command, reversal_authority_epoch command,
      reversal_nonce command)"

definition current_custody ::
  "trust_compositional_state \<Rightarrow> trust_forward_command \<Rightarrow>
   compositional_custody option"
where
  "current_custody state command = custody_records state (forward_case command)"

definition uses_active_custody ::
  "trust_compositional_state \<Rightarrow> trust_forward_command \<Rightarrow> bool"
where
  "uses_active_custody state command \<longleftrightarrow>
     (case current_custody state command of
        Some custody \<Rightarrow>
          custody_active custody \<and> custody_custodian custody = forward_source command
      | None \<Rightarrow> False)"

definition forward_shape_wf ::
  "trust_compositional_state \<Rightarrow> trust_forward_command \<Rightarrow> bool"
where
  "forward_shape_wf state command \<longleftrightarrow>
     forward_action_id command \<noteq> 0 \<and>
     forward_subject command \<noteq> 0 \<and>
     forward_valid_after command \<le> forward_valid_before command \<and>
     \<not> terminal_cases state (forward_case command) \<and>
     (case forward_action command of
        Legal_Freeze \<Rightarrow>
          forward_source command = forward_subject command \<and>
          frozen_targets state (forward_subject command) < forward_amount command
      | Legal_Restrict \<Rightarrow> forward_source command = forward_subject command
      | Legal_Seize \<Rightarrow>
          forward_source command = forward_subject command \<and>
          forward_custodian command \<noteq> 0 \<and> forward_amount command > 0
      | Legal_Confiscate \<Rightarrow>
          forward_amount command > 0 \<and>
          (uses_active_custody state command \<or>
           forward_source command = forward_subject command)
      | Legal_Liquidate \<Rightarrow>
          forward_amount command > 0 \<and> forward_destination command \<noteq> 0 \<and>
          (uses_active_custody state command \<or>
           forward_source command = forward_subject command)
      | Legal_Recover \<Rightarrow>
          forward_amount command > 0 \<and> forward_destination command \<noteq> 0 \<and>
          (uses_active_custody state command \<or>
           forward_source command = forward_subject command))"

definition forward_fresh ::
  "trust_compositional_state \<Rightarrow> trust_forward_command \<Rightarrow> bool"
where
  "forward_fresh state command \<longleftrightarrow>
     forward_action_id command \<notin> consumed_command_ids state \<and>
     forward_nonce_key command \<notin> compositional_consumed_nonces state"

definition forward_action_record ::
  "trust_compositional_state \<Rightarrow> trust_forward_command \<Rightarrow>
   trust_success_witness \<Rightarrow> compositional_action_record"
where
  "forward_action_record state command witness =
     \<lparr>abstract_action = forward_action command,
      abstract_lifecycle = Authorization_Consumed,
      abstract_subject = forward_subject command,
      abstract_source = forward_source command,
      abstract_destination = forward_destination command,
      abstract_custodian = forward_custodian command,
      abstract_amount = forward_amount command,
      abstract_prior_amount =
        (if forward_action command = Legal_Freeze
         then frozen_targets state (forward_subject command) else 0),
      abstract_prior_flag =
        (forward_action command = Legal_Restrict \<and>
         restriction_flags state (forward_subject command)),
      abstract_case = forward_case command,
      abstract_authority_ref = forward_authority_ref command,
      abstract_authority_epoch = forward_authority_epoch command,
      abstract_policy_epoch = forward_policy_epoch command,
      abstract_command_hash = witness_command_hash witness,
      abstract_evidence_hash = witness_evidence_hash witness,
      abstract_receipt_hash = compositional_receipt_hash (witness_receipt witness)\<rparr>"

definition base_forward_success ::
  "trust_compositional_state \<Rightarrow> trust_forward_command \<Rightarrow>
   trust_success_witness \<Rightarrow> trust_compositional_state"
where
  "base_forward_success state command witness =
     state\<lparr>
       action_records := (action_records state)
         (forward_action_id command := Some (forward_action_record state command witness)),
       compositional_consumed_nonces :=
         insert (forward_nonce_key command) (compositional_consumed_nonces state),
       consumed_command_ids :=
         insert (forward_action_id command) (consumed_command_ids state),
       compositional_receipts := (compositional_receipts state)
         (forward_action_id command := Some (witness_receipt witness))
     \<rparr>"

definition close_custody ::
  "trust_compositional_state \<Rightarrow> trust_case_id \<Rightarrow>
   (trust_case_id \<Rightarrow> compositional_custody option)"
where
  "close_custody state case_id =
     (case custody_records state case_id of
        None \<Rightarrow> custody_records state
      | Some custody \<Rightarrow>
          (custody_records state)(case_id := Some (custody\<lparr>custody_active := False\<rparr>)))"

definition forward_success_state ::
  "trust_compositional_state \<Rightarrow> trust_forward_command \<Rightarrow>
   trust_success_witness \<Rightarrow> trust_compositional_state"
where
  "forward_success_state state command witness =
     (let base = base_forward_success state command witness;
          subject = forward_subject command;
          source = forward_source command;
          destination = forward_destination command;
          custodian = forward_custodian command;
          amount = forward_amount command;
          case_id = forward_case command;
          action_id = forward_action_id command;
          link = \<lparr>effect_parent = witness_effect_parent witness,
                   effect_hash = witness_effect_hash witness,
                   effect_generation = witness_effect_generation witness\<rparr>;
          head = \<lparr>head_action = Some action_id,
                   head_hash = witness_effect_hash witness,
                   head_generation = witness_effect_generation witness\<rparr>
      in case forward_action command of
        Legal_Freeze \<Rightarrow>
          base\<lparr>
            frozen_targets := (frozen_targets base)(subject := amount),
            freeze_heads := (freeze_heads base)(subject := head),
            effect_links := (effect_links base)(action_id := Some link)
          \<rparr>
      | Legal_Restrict \<Rightarrow>
          base\<lparr>
            restriction_flags := (restriction_flags base)(subject := True),
            restriction_heads := (restriction_heads base)(subject := head),
            effect_links := (effect_links base)(action_id := Some link)
          \<rparr>
      | Legal_Seize \<Rightarrow>
          base\<lparr>
            physical_balances :=
              ((physical_balances base)(source := physical_balances base source - amount))
                (custodian := physical_balances base custodian + amount),
            custody_backing :=
              (custody_backing base)(custodian := custody_backing base custodian + amount),
            custody_records := (custody_records base)
              (case_id := Some
                \<lparr>custody_custodian = custodian,
                 custody_prior_holder = subject,
                 custody_amount = amount,
                 custody_action = Some action_id,
                 custody_parent = witness_effect_parent witness,
                 custody_effect_hash = witness_effect_hash witness,
                 custody_generation = witness_effect_generation witness,
                 custody_active = True\<rparr>),
            effect_links := (effect_links base)(action_id := Some link)
          \<rparr>
      | Legal_Confiscate \<Rightarrow>
          base\<lparr>
            physical_balances :=
              (physical_balances base)(source := physical_balances base source - amount),
            compositional_total_supply := compositional_total_supply base - amount,
            custody_backing :=
              (if uses_active_custody state command
               then (custody_backing base)
                 (source := custody_backing base source - amount)
               else custody_backing base),
            custody_records := close_custody base case_id,
            terminal_cases := (terminal_cases base)(case_id := True)
          \<rparr>
      | Legal_Liquidate \<Rightarrow>
          base\<lparr>
            physical_balances :=
              ((physical_balances base)(source := physical_balances base source - amount))
                (destination := physical_balances base destination + amount),
            custody_backing :=
              (if uses_active_custody state command
               then (custody_backing base)
                 (source := custody_backing base source - amount)
               else custody_backing base),
            custody_records := close_custody base case_id,
            settlement_records := (settlement_records base)
              (action_id := Some
                \<lparr>settlement_destination = destination,
                 settlement_commitment = forward_settlement_commitment command,
                 settlement_proceeds_commitment = forward_proceeds_commitment command\<rparr>),
            terminal_cases := (terminal_cases base)(case_id := True)
          \<rparr>
      | Legal_Recover \<Rightarrow>
          base\<lparr>
            physical_balances :=
              ((physical_balances base)(source := physical_balances base source - amount))
                (destination := physical_balances base destination + amount),
            custody_backing :=
              (if uses_active_custody state command
               then (custody_backing base)
                 (source := custody_backing base source - amount)
               else custody_backing base),
            custody_records := close_custody base case_id,
            entitlement_records := (entitlement_records base)
              (action_id := Some
                \<lparr>entitlement_destination = destination,
                 entitlement_commitment = forward_entitlement_commitment command,
                 entitlement_consumed = True\<rparr>),
            consumed_entitlements :=
              insert (forward_entitlement_commitment command)
                (consumed_entitlements base),
            terminal_cases := (terminal_cases base)(case_id := True)
          \<rparr>)"

definition reversal_original ::
  "trust_compositional_state \<Rightarrow> trust_reversal_command \<Rightarrow>
   compositional_action_record option"
where
  "reversal_original state command =
     action_records state (reversal_original_action_id command)"

definition reversal_current_head ::
  "trust_compositional_state \<Rightarrow> trust_reversal_command \<Rightarrow> bool"
where
  "reversal_current_head state command \<longleftrightarrow>
     (case reversal_original state command of
        None \<Rightarrow> False
      | Some original \<Rightarrow>
          (case reversal_kind command of
             TRUST_UNFREEZE \<Rightarrow>
               head_action (freeze_heads state (abstract_subject original)) =
                 Some (reversal_original_action_id command)
           | TRUST_UNRESTRICT \<Rightarrow>
               head_action (restriction_heads state (abstract_subject original)) =
                 Some (reversal_original_action_id command)
           | TRUST_RELEASE \<Rightarrow>
               (case custody_records state (abstract_case original) of
                  Some custody \<Rightarrow>
                    custody_active custody \<and>
                    custody_action custody = Some (reversal_original_action_id command)
                | None \<Rightarrow> False)))"

definition reversal_admissible ::
  "trust_compositional_state \<Rightarrow> trust_reversal_command \<Rightarrow> bool"
where
  "reversal_admissible state command \<longleftrightarrow>
     reversal_id command \<noteq> 0 \<and>
     reversal_id command \<notin> consumed_command_ids state \<and>
     reversal_nonce_key command \<notin> compositional_consumed_nonces state \<and>
     reversal_valid_after command \<le> reversal_valid_before command \<and>
     reversal_current_head state command \<and>
     (case reversal_original state command of
        Some original \<Rightarrow>
          \<not> terminal_cases state (abstract_case original) \<and>
          ((reversal_kind command = TRUST_UNFREEZE \<and>
             abstract_action original = Legal_Freeze) \<or>
           (reversal_kind command = TRUST_RELEASE \<and>
             abstract_action original = Legal_Seize) \<or>
           (reversal_kind command = TRUST_UNRESTRICT \<and>
             abstract_action original = Legal_Restrict))
      | None \<Rightarrow> False)"

definition popped_head :: "trust_reversal_witness \<Rightarrow> compositional_effect_head" where
  "popped_head witness =
     \<lparr>head_action = reversal_witness_parent_action witness,
      head_hash = reversal_witness_parent_hash witness,
      head_generation = reversal_witness_generation witness\<rparr>"

definition reversal_success_state ::
  "trust_compositional_state \<Rightarrow> trust_reversal_command \<Rightarrow>
   trust_reversal_witness \<Rightarrow> trust_compositional_state"
where
  "reversal_success_state state command witness =
     (case reversal_original state command of
        None \<Rightarrow> state
      | Some original \<Rightarrow>
          let case_id = abstract_case original;
              subject = abstract_subject original;
              base = state\<lparr>
                compositional_consumed_nonces :=
                  insert (reversal_nonce_key command)
                    (compositional_consumed_nonces state),
                consumed_command_ids :=
                  insert (reversal_id command) (consumed_command_ids state),
                compositional_receipts := (compositional_receipts state)
                  (reversal_id command := Some (reversal_witness_receipt witness)),
                terminal_cases := (terminal_cases state)(case_id := True)
              \<rparr>
          in case reversal_kind command of
            TRUST_UNFREEZE \<Rightarrow>
              base\<lparr>
                frozen_targets :=
                  (frozen_targets base)(subject := abstract_prior_amount original),
                freeze_heads := (freeze_heads base)(subject := popped_head witness)
              \<rparr>
          | TRUST_UNRESTRICT \<Rightarrow>
              base\<lparr>
                restriction_flags :=
                  (restriction_flags base)(subject := abstract_prior_flag original),
                restriction_heads :=
                  (restriction_heads base)(subject := popped_head witness)
              \<rparr>
          | TRUST_RELEASE \<Rightarrow>
              (case custody_records state case_id of
                 None \<Rightarrow> state
               | Some custody \<Rightarrow>
                   let holder = custody_prior_holder custody;
                       custodian = custody_custodian custody;
                       amount = custody_amount custody
                   in base\<lparr>
                     physical_balances :=
                       ((physical_balances base)
                         (custodian := physical_balances base custodian - amount))
                         (holder := physical_balances base holder + amount),
                     custody_backing :=
                       (custody_backing base)
                         (custodian := custody_backing base custodian - amount),
                     custody_records := close_custody base case_id
                   \<rparr>))"

definition abstract_failure_transition ::
  "trust_compositional_state \<Rightarrow> trust_abstract_failure \<Rightarrow>
   trust_compositional_state \<times> trust_abstract_failure"
where
  "abstract_failure_transition state failure = (state, failure)"

theorem freeze_success_forward:
  assumes "forward_action command = Legal_Freeze"
  shows "frozen_targets (forward_success_state state command witness)
           (forward_subject command) = forward_amount command"
  using assms by (simp add: forward_success_state_def base_forward_success_def Let_def)

theorem freeze_success_forward_is_strict:
  assumes "forward_shape_wf state command"
      and "forward_action command = Legal_Freeze"
  shows "frozen_targets state (forward_subject command) < forward_amount command"
  using assms by (simp add: forward_shape_wf_def)

theorem restrict_success_forward:
  assumes "forward_action command = Legal_Restrict"
  shows "restriction_flags (forward_success_state state command witness)
           (forward_subject command)"
  using assms by (simp add: forward_success_state_def base_forward_success_def Let_def)

theorem seize_success_forward:
  assumes "forward_action command = Legal_Seize"
      and "forward_source command \<noteq> forward_custodian command"
  shows "custody_backing (forward_success_state state command witness)
           (forward_custodian command) =
         custody_backing state (forward_custodian command) + forward_amount command"
  using assms by (simp add: forward_success_state_def base_forward_success_def Let_def)

theorem confiscate_success_is_terminal:
  assumes "forward_action command = Legal_Confiscate"
  shows "terminal_cases (forward_success_state state command witness)
           (forward_case command)"
  using assms by (simp add: forward_success_state_def base_forward_success_def Let_def)

theorem liquidate_success_binds_settlement_and_is_terminal:
  assumes "forward_action command = Legal_Liquidate"
  shows "settlement_records (forward_success_state state command witness)
           (forward_action_id command) \<noteq> None \<and>
         terminal_cases (forward_success_state state command witness)
           (forward_case command)"
  using assms by (simp add: forward_success_state_def base_forward_success_def Let_def)

theorem recover_success_consumes_entitlement_and_is_terminal:
  assumes "forward_action command = Legal_Recover"
  shows "forward_entitlement_commitment command \<in>
           consumed_entitlements (forward_success_state state command witness) \<and>
         terminal_cases (forward_success_state state command witness)
           (forward_case command)"
  using assms by (simp add: forward_success_state_def base_forward_success_def Let_def)

theorem stale_freeze_reversal_is_not_admissible:
  assumes "reversal_original state command = Some original"
      and "reversal_kind command = TRUST_UNFREEZE"
      and "head_action (freeze_heads state (abstract_subject original)) \<noteq>
             Some (reversal_original_action_id command)"
  shows "\<not> reversal_admissible state command"
  using assms
  by (simp add: reversal_admissible_def reversal_current_head_def)

theorem stale_restriction_reversal_is_not_admissible:
  assumes "reversal_original state command = Some original"
      and "reversal_kind command = TRUST_UNRESTRICT"
      and "head_action (restriction_heads state (abstract_subject original)) \<noteq>
             Some (reversal_original_action_id command)"
  shows "\<not> reversal_admissible state command"
  using assms
  by (simp add: reversal_admissible_def reversal_current_head_def)

theorem duplicate_reversal_is_not_admissible:
  assumes "reversal_id command \<in> consumed_command_ids state"
  shows "\<not> reversal_admissible state command"
  using assms by (simp add: reversal_admissible_def)

theorem unfreeze_success_restores_prior_target:
  assumes "reversal_original state command = Some original"
      and "reversal_kind command = TRUST_UNFREEZE"
  shows "frozen_targets (reversal_success_state state command witness)
           (abstract_subject original) = abstract_prior_amount original"
  using assms by (simp add: reversal_success_state_def Let_def)

theorem unrestrict_success_restores_prior_flag:
  assumes "reversal_original state command = Some original"
      and "reversal_kind command = TRUST_UNRESTRICT"
  shows "restriction_flags (reversal_success_state state command witness)
           (abstract_subject original) = abstract_prior_flag original"
  using assms by (simp add: reversal_success_state_def Let_def)

theorem successful_reversal_is_terminal:
  assumes "reversal_original state command = Some original"
      and "reversal_admissible state command"
  shows "terminal_cases (reversal_success_state state command witness)
           (abstract_case original)"
  using assms
  by (cases "reversal_kind command";
      auto simp: reversal_success_state_def reversal_admissible_def
        reversal_current_head_def Let_def split: option.splits)

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

definition expected_success_state ::
  "trust_transaction_abstraction \<Rightarrow> trust_compositional_state option"
where
  "expected_success_state abstraction =
     (case (abstraction_command abstraction,
            abstraction_forward_witness abstraction,
            abstraction_reversal_witness abstraction) of
        (Some (TRUST_Forward command), Some witness, None) \<Rightarrow>
          (if forward_shape_wf (abstraction_pre_state abstraction) command \<and>
              forward_fresh (abstraction_pre_state abstraction) command
           then Some (forward_success_state (abstraction_pre_state abstraction) command witness)
           else None)
      | (Some (TRUST_Reverse command), None, Some witness) \<Rightarrow>
          Some (reversal_success_state (abstraction_pre_state abstraction) command witness)
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

theorem successful_forward_transaction_is_well_formed:
  assumes "alpha_transaction manifest bridge execution abstraction"
      and "abstraction_outcome abstraction = TRUST_Abstract_Applied"
      and "abstraction_command abstraction = Some (TRUST_Forward command)"
      and "abstraction_forward_witness abstraction = Some witness"
      and "abstraction_reversal_witness abstraction = None"
  shows "forward_shape_wf (abstraction_pre_state abstraction) command \<and>
         forward_fresh (abstraction_pre_state abstraction) command"
  using assms
  by (auto simp: alpha_transaction_def expected_success_state_def split: if_splits)

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

theorem committed_history_excludes_failure_receipts:
  assumes "\<forall>execution\<in>set (committed_transactions history).
             \<not> transaction_committed execution \<longrightarrow>
             bridge_committed_receipt bridge execution = None"
      and "alpha_history bridge history trace"
  shows "trace = map_some (bridge_committed_receipt bridge)
           (filter transaction_committed (committed_transactions history))"
  using assms by (simp add: alpha_history_def)

end
