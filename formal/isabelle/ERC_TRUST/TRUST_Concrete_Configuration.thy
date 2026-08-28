(* Concrete EVM configuration boundary for TRUST refinement. *)

theory TRUST_Concrete_Configuration
  imports TRUST_Compositional_State
begin

type_synonym evm_byte = nat
type_synonym evm_bytes = "evm_byte list"
type_synonym evm_storage = "trust_word256 \<Rightarrow> trust_word256"

record evm_account =
  evm_account_nonce :: nat
  evm_account_balance :: trust_word256
  evm_account_code :: evm_bytes
  evm_account_storage :: evm_storage

type_synonym evm_world = "trust_address \<Rightarrow> evm_account option"

datatype trust_topology =
    TRUST_Native trust_address
  | TRUST_Verified_Profile
      trust_address
      trust_address
      trust_address
      trust_address
      trust_address

datatype trust_execution_phase =
    TRUST_Idle
  | TRUST_Dispatch
  | TRUST_Authorized
  | TRUST_Assessed
  | TRUST_Effects_Applied
  | TRUST_Returned
  | TRUST_Reverted

datatype trust_transaction_result =
    TRUST_Return_Success evm_bytes
  | TRUST_Return_Rejection evm_bytes
  | TRUST_Return_Operational_Failure evm_bytes
  | TRUST_Return_Malformed evm_bytes
  | TRUST_Return_Revert evm_bytes

record trust_raw_log =
  raw_log_emitter :: trust_address
  raw_log_topics :: "trust_hash list"
  raw_log_data :: evm_bytes

record trust_external_call =
  external_call_target :: trust_address
  external_call_selector :: nat
  external_call_input :: evm_bytes
  external_call_static :: bool
  external_call_succeeded :: bool
  external_call_returndata :: evm_bytes

record trust_footprint =
  footprint_addresses :: "trust_address set"
  footprint_cases :: "trust_case_id set"
  footprint_actions :: "trust_action_id set"
  footprint_receipts :: "trust_hash set"
  footprint_authorities :: "trust_authority_ref set"
  footprint_nonce_keys :: "trust_nonce_key set"
  footprint_mapping_inputs :: "evm_bytes set"

record current_trust_configuration =
  current_world :: evm_world
  current_topology :: trust_topology
  current_endpoint :: trust_address
  current_manifest_id :: trust_hash
  current_footprint :: trust_footprint

record trust_transaction_execution =
  transaction_pre :: current_trust_configuration
  transaction_sender :: trust_address
  transaction_value :: trust_word256
  transaction_time :: nat
  transaction_chain :: nat
  transaction_gas_limit :: nat
  transaction_calldata :: evm_bytes
  transaction_external_calls :: "trust_external_call list"
  transaction_phase :: trust_execution_phase
  transaction_result :: trust_transaction_result
  transaction_post_world :: evm_world
  transaction_raw_logs :: "trust_raw_log list"

record trust_committed_history_witness =
  committed_transactions :: "trust_transaction_execution list"

definition transaction_committed :: "trust_transaction_execution \<Rightarrow> bool" where
  "transaction_committed execution \<longleftrightarrow>
     (case transaction_result execution of
        TRUST_Return_Success _ \<Rightarrow> True
      | _ \<Rightarrow> False)"

definition committed_log_trace ::
  "trust_committed_history_witness \<Rightarrow> trust_raw_log list"
where
  "committed_log_trace witness =
     concat (map transaction_raw_logs
       (filter transaction_committed (committed_transactions witness)))"

definition transaction_post_configuration ::
  "trust_transaction_execution \<Rightarrow> current_trust_configuration"
where
  "transaction_post_configuration execution =
     (transaction_pre execution)\<lparr>current_world := transaction_post_world execution\<rparr>"

definition current_configuration_well_bounded ::
  "current_trust_configuration \<Rightarrow> bool"
where
  "current_configuration_well_bounded configuration \<longleftrightarrow>
     finite (footprint_addresses (current_footprint configuration)) \<and>
     finite (footprint_cases (current_footprint configuration)) \<and>
     finite (footprint_actions (current_footprint configuration)) \<and>
     finite (footprint_receipts (current_footprint configuration)) \<and>
     finite (footprint_mapping_inputs (current_footprint configuration))"

theorem current_configuration_extensional:
  fixes left right :: current_trust_configuration
  assumes "current_world left = current_world right"
      and "current_topology left = current_topology right"
      and "current_endpoint left = current_endpoint right"
      and "current_manifest_id left = current_manifest_id right"
      and "current_footprint left = current_footprint right"
  shows "left = right"
  using assms by (cases left; cases right; simp)

theorem current_configuration_does_not_contain_transaction_context:
  assumes "transaction_pre left = transaction_pre right"
  shows "current_world (transaction_pre left) = current_world (transaction_pre right) \<and>
         current_footprint (transaction_pre left) = current_footprint (transaction_pre right)"
  using assms by simp

theorem reverted_transaction_has_no_committed_logs:
  assumes "transaction_result execution = TRUST_Return_Revert payload"
  shows "committed_log_trace
          \<lparr>committed_transactions = [execution]\<rparr> = []"
  using assms by (simp add: committed_log_trace_def transaction_committed_def)

theorem malformed_transaction_has_no_committed_logs:
  assumes "transaction_result execution = TRUST_Return_Malformed payload"
  shows "committed_log_trace
          \<lparr>committed_transactions = [execution]\<rparr> = []"
  using assms by (simp add: committed_log_trace_def transaction_committed_def)

theorem successful_transaction_preserves_log_order:
  assumes "transaction_result execution = TRUST_Return_Success payload"
  shows "committed_log_trace
          \<lparr>committed_transactions = [execution]\<rparr> =
         transaction_raw_logs execution"
  using assms by (simp add: committed_log_trace_def transaction_committed_def)

theorem history_is_an_explicit_witness:
  "committed_transactions
     \<lparr>committed_transactions = executions\<rparr> = executions"
  by simp

end
