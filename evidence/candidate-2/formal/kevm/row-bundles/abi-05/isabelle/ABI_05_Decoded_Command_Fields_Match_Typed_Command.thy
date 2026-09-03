theory ABI_05_Decoded_Command_Fields_Match_Typed_Command
  imports ERC_TRUST.TRUST_Transaction_Refinement
begin

definition abi_05_required_property :: string where
  "abi_05_required_property = ''decoded_command_fields_match_typed_command''"
definition abi_05_action_word_count :: nat where "abi_05_action_word_count = 21"
definition abi_05_reversal_word_count :: nat where "abi_05_reversal_word_count = 9"
definition abi_05_calldata_backed_field_count :: nat where "abi_05_calldata_backed_field_count = 30"
definition abi_05_state_derived_field_count :: nat where "abi_05_state_derived_field_count = 1"
definition abi_05_proof_status :: string where "abi_05_proof_status = ''NOT_RUN''"
definition abi_05_eligible_for_discharge :: bool where "abi_05_eligible_for_discharge = False"

consts abi_05_decoded_field_words :: "evm_bytes <Rightarrow> nat list"
consts abi_05_typed_field_words :: "trust_typed_command <Rightarrow> nat list"

definition abi_05_fieldwise_decoder_refinement ::
  "trust_transaction_bridge <Rightarrow> evm_bytes <Rightarrow> trust_typed_command <Rightarrow> bool"
where
  "abi_05_fieldwise_decoder_refinement bridge calldata command <longleftrightarrow>
    bridge_decode_calldata bridge calldata = Some command <and>
    abi_05_decoded_field_words calldata = abi_05_typed_field_words command"

theorem abi_05_decoded_command_fields_match_typed_command:
  assumes "abi_05_fieldwise_decoder_refinement bridge calldata command"
  shows "bridge_decode_calldata bridge calldata = Some command <and>
    abi_05_decoded_field_words calldata = abi_05_typed_field_words command"
  using assms by (simp add: abi_05_fieldwise_decoder_refinement_def)

theorem abi_05_reversal_policy_epoch_is_not_calldata_backed:
  "abi_05_reversal_word_count = 9 <and> abi_05_state_derived_field_count = 1"
  by (simp add: abi_05_reversal_word_count_def abi_05_state_derived_field_count_def)

theorem abi_05_static_gate_remains_open:
  "abi_05_action_word_count + abi_05_reversal_word_count =
      abi_05_calldata_backed_field_count <and>
   abi_05_proof_status = ''NOT_RUN'' <and> <not> abi_05_eligible_for_discharge"
  by (simp add: abi_05_action_word_count_def abi_05_reversal_word_count_def
      abi_05_calldata_backed_field_count_def abi_05_proof_status_def
      abi_05_eligible_for_discharge_def)

end
