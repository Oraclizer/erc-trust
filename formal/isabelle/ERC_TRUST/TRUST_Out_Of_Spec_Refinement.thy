(*
  Requests outside the canonical form of the proposal.

  The typed command functions are executeRegulatoryAction and executeRegulatoryReversal and, on an
  endpoint that implements IERCTrustNativeRoute, executeERC7943Action and executeERC7943Reversal.  A
  request to a typed command function is in canonical form when its calldata is the function selector
  followed by the canonical encoding of the request (exact length, address and narrow integer words
  without bits outside their declared width, enum words holding declared values) and the call carries
  zero value.  A typed command function must reject every other request as a full-state stutter that
  changes no state, emits no event and makes no external call.  The proposal specifies neither the
  revert data of that rejection, which can be empty, a typed error or any other data, nor which defect
  of such a request is detected first.
*)

theory TRUST_Out_Of_Spec_Refinement
  imports "ERC_TRUST.TRUST_End_To_End_Composition" "ERC_TRUST.TRUST_State_Abi_Normal_Form"
begin

text \<open>
  The relation alpha_transaction reads neither the call value of an execution nor, on its failure
  branches, the external calls.  The relation alpha_transaction_spec splits executions by the command
  a request carries: it keeps alpha_transaction for every request in canonical form that the bridge
  decodes, and it relates every other request only to the out-of-specification branch of the proposal,
  in which the world is unchanged, no log is emitted, no external call is made, the call does not
  succeed, and the revert data is left open.

  Canonical form is stated here without the bridge.  The call value is zero, every calldata byte is
  below 256, the calldata is a four-byte selector followed by whole 32-byte words, and the canonical
  decoders decode_native_action and decode_native_reversal of TRUST_State_Abi_Normal_Form accept that
  selector and those words.  The selectors, the word counts, the widths of the address and narrow
  integer words and the enum bounds are therefore those of the kernel, whatever the bridge decoder
  does.  The selector sets are those of all four typed command functions; on an endpoint that does
  not implement IERCTrustNativeRoute, a call with the selector of executeERC7943Action or
  executeERC7943Reversal is not a call to a typed command function and is outside runtime_execution.
  A request in canonical form that the bridge decoder does not decode is also related only to the
  out-of-specification branch, so a runtime linked by this relation executes a command only when the
  kernel and the bridge agree that the request is one.  By out_of_spec_request_is_a_full_state_stutter
  the relation holds for such a request only as a full-state stutter, so a discharge of
  runtime_link_spec also needs the bridge decoder to decode every request in canonical form that the
  runtime commits, or on which it makes an external call or emits a log.  The theorems
  action_request_witness_is_canonical and reversal_request_witness_is_canonical below show that
  canonical form is satisfiable for both shapes.

  Both branches require the pre-configuration to be abstracted by alpha_current, which includes the
  idle auxiliary state of the pinned manifest.  A reentrant call, made while an earlier call to the
  same endpoint has not returned, starts from a configuration that is not idle whenever the pinned
  manifest requires the reentrancy guard to be clear; runtime_execution is meant to range over calls
  made from an idle configuration, and the permission of the proposal to reject a reentrant call
  before any other check is not formalized here.

  transaction_post_world is read as the world after the frame of the endpoint call has returned, and a
  discharge of runtime_link_spec must record executions at that level.  At that level a reverted call
  restores the whole world.  The full-state stutter of the proposal constrains only the endpoint: its
  observable state does not change and it emits no event.  The world equation of the
  out-of-specification branch gives the first part and its empty log list gives the second.  The
  world equation is not a statement about the enclosing transaction, whose sender nonce and gas
  accounting change even when the call reverts.

  runtime_execution ranges over calls to the typed command functions.  A call to another function of
  the endpoint is outside this relation, and the result of deriveActionId and deriveReversalId for a
  call that is not a zero-value call with canonical calldata is not specified by the proposal.
\<close>

section \<open>Canonical form of a request\<close>

definition calldata_bytes_nat :: "evm_bytes \<Rightarrow> nat" where
  "calldata_bytes_nat bytes = foldl (\<lambda>value byte. value * 256 + byte) 0 bytes"

definition calldata_selector :: "evm_bytes \<Rightarrow> nat" where
  "calldata_selector calldata = calldata_bytes_nat (take 4 calldata)"

definition calldata_words :: "evm_bytes \<Rightarrow> nat list" where
  "calldata_words calldata =
     map (\<lambda>index. calldata_bytes_nat (take 32 (drop (4 + 32 * index) calldata)))
       [0..<(length calldata - 4) div 32]"

definition kernel_canonical_calldata :: "evm_bytes \<Rightarrow> bool" where
  "kernel_canonical_calldata calldata \<longleftrightarrow>
     (\<forall>byte\<in>set calldata. byte < 256) \<and>
     4 \<le> length calldata \<and> (length calldata - 4) mod 32 = 0 \<and>
     (decode_native_action (calldata_selector calldata) (calldata_words calldata) \<noteq> None \<or>
      decode_native_reversal (calldata_selector calldata) (calldata_words calldata) \<noteq> None)"

definition request_in_canonical_form :: "trust_transaction_execution \<Rightarrow> bool" where
  "request_in_canonical_form execution \<longleftrightarrow>
     transaction_value execution = 0 \<and> kernel_canonical_calldata (transaction_calldata execution)"

section \<open>The command a request carries\<close>

definition transaction_command ::
  "trust_transaction_bridge \<Rightarrow> trust_transaction_execution \<Rightarrow> trust_typed_command option"
where
  "transaction_command bridge execution =
     (if request_in_canonical_form execution
      then bridge_decode_calldata bridge (transaction_calldata execution)
      else None)"

theorem canonical_command_is_the_decoded_calldata:
  assumes "request_in_canonical_form execution"
  shows "transaction_command bridge execution =
           bridge_decode_calldata bridge (transaction_calldata execution)"
  using assms by (simp add: transaction_command_def)

theorem request_outside_canonical_form_is_out_of_spec:
  assumes "\<not> request_in_canonical_form execution"
  shows "transaction_command bridge execution = None"
  using assms by (simp add: transaction_command_def)

theorem nonzero_call_value_is_out_of_spec:
  assumes "transaction_value execution \<noteq> 0"
  shows "transaction_command bridge execution = None"
proof -
  have "\<not> request_in_canonical_form execution"
    using assms by (auto simp: request_in_canonical_form_def)
  then show ?thesis by (rule request_outside_canonical_form_is_out_of_spec)
qed

theorem noncanonical_calldata_is_out_of_spec:
  assumes "\<not> kernel_canonical_calldata (transaction_calldata execution)"
  shows "transaction_command bridge execution = None"
proof -
  have "\<not> request_in_canonical_form execution"
    using assms by (auto simp: request_in_canonical_form_def)
  then show ?thesis by (rule request_outside_canonical_form_is_out_of_spec)
qed

theorem canonical_request_has_zero_value:
  assumes COMMAND: "transaction_command bridge execution = Some command"
  shows "transaction_value execution = 0 \<and>
         kernel_canonical_calldata (transaction_calldata execution) \<and>
         bridge_decode_calldata bridge (transaction_calldata execution) = Some command"
proof (cases "request_in_canonical_form execution")
  case True
  have "bridge_decode_calldata bridge (transaction_calldata execution) = Some command"
    using COMMAND canonical_command_is_the_decoded_calldata[OF True] by simp
  with True show ?thesis by (simp add: request_in_canonical_form_def)
next
  case False
  have "transaction_command bridge execution = None"
    using False by (rule request_outside_canonical_form_is_out_of_spec)
  with COMMAND show ?thesis by simp
qed

section \<open>Canonical form follows the canonical decoders of the kernel\<close>

lemma calldata_words_length:
  "length (calldata_words calldata) = (length calldata - 4) div 32"
  by (simp add: calldata_words_def)

theorem canonical_calldata_is_whole_words:
  assumes "kernel_canonical_calldata calldata"
  shows "length calldata = 4 + 32 * length (calldata_words calldata)"
proof -
  have LOW: "4 \<le> length calldata" and MOD: "(length calldata - 4) mod 32 = 0"
    using assms by (simp_all add: kernel_canonical_calldata_def)
  have WORDS: "length (calldata_words calldata) = (length calldata - 4) div 32"
    by (rule calldata_words_length)
  have SPLIT: "(length calldata - 4) div 32 * 32 + (length calldata - 4) mod 32 = length calldata - 4"
    by (rule div_mult_mod_eq)
  show ?thesis
    using LOW MOD WORDS SPLIT by arith
qed

theorem canonical_calldata_has_a_kernel_length:
  assumes "kernel_canonical_calldata calldata"
  shows "length calldata = action_calldata_length \<or> length calldata = reversal_calldata_length"
proof -
  have WHOLE: "length calldata = 4 + 32 * length (calldata_words calldata)"
    using canonical_calldata_is_whole_words[OF assms] .
  have "length (calldata_words calldata) = action_word_count \<or>
        length (calldata_words calldata) = reversal_word_count"
    using assms
    by (auto simp: kernel_canonical_calldata_def decode_native_action_def decode_native_reversal_def
        canonical_action_words_def canonical_reversal_words_def split: if_splits)
  then show ?thesis
    using WHOLE native_calldata_lengths_are_exact by auto
qed

theorem wrong_length_is_out_of_spec:
  assumes "length (transaction_calldata execution) \<noteq> action_calldata_length"
      and "length (transaction_calldata execution) \<noteq> reversal_calldata_length"
  shows "transaction_command bridge execution = None"
proof -
  have "\<not> kernel_canonical_calldata (transaction_calldata execution)"
    using assms canonical_calldata_has_a_kernel_length by blast
  then show ?thesis by (rule noncanonical_calldata_is_out_of_spec)
qed

theorem action_and_reversal_selectors_are_disjoint:
  "action_selectors \<inter> reversal_selectors = {}"
  by (simp add: action_selectors_def reversal_selectors_def action_entrypoint_selector_def
      native_route_action_selector_def reversal_entrypoint_selector_def
      native_route_reversal_selector_def)

theorem unknown_selector_is_out_of_spec:
  assumes "calldata_selector (transaction_calldata execution) \<notin> action_selectors"
      and "calldata_selector (transaction_calldata execution) \<notin> reversal_selectors"
  shows "transaction_command bridge execution = None"
proof -
  have "\<not> kernel_canonical_calldata (transaction_calldata execution)"
    using unknown_selector_is_rejected[OF assms] by (simp add: kernel_canonical_calldata_def)
  then show ?thesis by (rule noncanonical_calldata_is_out_of_spec)
qed

theorem noncanonical_action_words_are_out_of_spec:
  assumes SELECTOR: "calldata_selector (transaction_calldata execution) \<in> action_selectors"
      and ACTION: "decode_native_action (calldata_selector (transaction_calldata execution))
                     (calldata_words (transaction_calldata execution)) = None"
  shows "transaction_command bridge execution = None"
proof -
  have NOT_REVERSAL: "calldata_selector (transaction_calldata execution) \<notin> reversal_selectors"
    using SELECTOR action_and_reversal_selectors_are_disjoint by blast
  have "decode_native_reversal (calldata_selector (transaction_calldata execution))
          (calldata_words (transaction_calldata execution)) = None"
    using NOT_REVERSAL by (simp add: decode_native_reversal_def)
  then have "\<not> kernel_canonical_calldata (transaction_calldata execution)"
    using ACTION by (simp add: kernel_canonical_calldata_def)
  then show ?thesis by (rule noncanonical_calldata_is_out_of_spec)
qed

theorem noncanonical_reversal_words_are_out_of_spec:
  assumes SELECTOR: "calldata_selector (transaction_calldata execution) \<in> reversal_selectors"
      and REVERSAL: "decode_native_reversal (calldata_selector (transaction_calldata execution))
                       (calldata_words (transaction_calldata execution)) = None"
  shows "transaction_command bridge execution = None"
proof -
  have NOT_ACTION: "calldata_selector (transaction_calldata execution) \<notin> action_selectors"
    using SELECTOR action_and_reversal_selectors_are_disjoint by blast
  have "decode_native_action (calldata_selector (transaction_calldata execution))
          (calldata_words (transaction_calldata execution)) = None"
    using NOT_ACTION by (simp add: decode_native_action_def)
  then have "\<not> kernel_canonical_calldata (transaction_calldata execution)"
    using REVERSAL by (simp add: kernel_canonical_calldata_def)
  then show ?thesis by (rule noncanonical_calldata_is_out_of_spec)
qed

theorem canonical_action_request_has_canonical_words:
  assumes CANONICAL: "kernel_canonical_calldata calldata"
      and SELECTOR: "calldata_selector calldata \<in> action_selectors"
  shows "canonical_action_words (calldata_words calldata)"
proof -
  have NOT_REVERSAL: "calldata_selector calldata \<notin> reversal_selectors"
    using SELECTOR action_and_reversal_selectors_are_disjoint by blast
  show ?thesis
    using CANONICAL NOT_REVERSAL
    by (auto simp: kernel_canonical_calldata_def decode_native_action_def decode_native_reversal_def
        split: if_splits)
qed

theorem canonical_reversal_request_has_canonical_words:
  assumes CANONICAL: "kernel_canonical_calldata calldata"
      and SELECTOR: "calldata_selector calldata \<in> reversal_selectors"
  shows "canonical_reversal_words (calldata_words calldata)"
proof -
  have NOT_ACTION: "calldata_selector calldata \<notin> action_selectors"
    using SELECTOR action_and_reversal_selectors_are_disjoint by blast
  show ?thesis
    using CANONICAL NOT_ACTION
    by (auto simp: kernel_canonical_calldata_def decode_native_action_def decode_native_reversal_def
        split: if_splits)
qed

text \<open>
  The rejected shells of the kernel that TRUST_State_Abi_Normal_Form proves for the canonical decoders
  are out of specification for every bridge.
\<close>

theorem dirty_action_enum_request_is_out_of_spec:
  assumes "calldata_selector (transaction_calldata execution) \<in> action_selectors"
      and "calldata_words (transaction_calldata execution) ! 2 \<ge> 6"
  shows "transaction_command bridge execution = None"
  using noncanonical_action_words_are_out_of_spec[OF assms(1)
      dirty_action_enum_high_bits_are_rejected[OF assms(2)]] .

theorem dirty_action_address_request_is_out_of_spec:
  assumes "calldata_selector (transaction_calldata execution) \<in> action_selectors"
      and "calldata_words (transaction_calldata execution) ! 3 \<ge> 2 ^ 160"
  shows "transaction_command bridge execution = None"
  using noncanonical_action_words_are_out_of_spec[OF assms(1)
      dirty_action_address_high_bits_are_rejected[OF assms(2)]] .

theorem dirty_action_uint48_request_is_out_of_spec:
  assumes "calldata_selector (transaction_calldata execution) \<in> action_selectors"
      and "calldata_words (transaction_calldata execution) ! 19 \<ge> 2 ^ 48"
  shows "transaction_command bridge execution = None"
  using noncanonical_action_words_are_out_of_spec[OF assms(1)
      dirty_action_uint48_high_bits_are_rejected[OF assms(2)]] .

theorem dirty_action_uint64_request_is_out_of_spec:
  assumes "calldata_selector (transaction_calldata execution) \<in> action_selectors"
      and "calldata_words (transaction_calldata execution) ! 16 \<ge> 2 ^ 64"
  shows "transaction_command bridge execution = None"
  using noncanonical_action_words_are_out_of_spec[OF assms(1)
      dirty_action_uint64_high_bits_are_rejected[OF assms(2)]] .

theorem dirty_reversal_enum_request_is_out_of_spec:
  assumes "calldata_selector (transaction_calldata execution) \<in> reversal_selectors"
      and "calldata_words (transaction_calldata execution) ! 3 \<ge> 3"
  shows "transaction_command bridge execution = None"
  using noncanonical_reversal_words_are_out_of_spec[OF assms(1)
      dirty_reversal_enum_high_bits_are_rejected[OF assms(2)]] .

section \<open>Canonical form is satisfiable\<close>

text \<open>
  Positive controls: a request built from a typed entrypoint selector and zero words is in canonical
  form, so canonical form is satisfiable for both shapes.  Canonical form alone does not inhabit the
  decoded branch of alpha_transaction_spec, which also needs the bridge to decode the request;
  decoded_branch_is_inhabited below exhibits an execution of that branch for a witness bridge.
\<close>

lemma calldata_bytes_nat_replicate_zero:
  "calldata_bytes_nat (replicate n 0) = 0"
  by (induct n) (simp_all add: calldata_bytes_nat_def)

lemma calldata_words_of_zero_words:
  assumes "length bytes = 4"
  shows "calldata_words (bytes @ replicate (32 * n) 0) = replicate n 0"
  using assms by (simp add: calldata_words_def calldata_bytes_nat_replicate_zero map_replicate_const)

lemma zero_words_are_canonical_action:
  "canonical_action_words (replicate action_word_count 0)"
  by (simp add: canonical_action_words_def enums_fit_def words_fit_def word_fits_def action_enum_words_def
      action_address_words_def action_uint64_words_def action_uint48_words_def action_word_count_def)

lemma zero_words_are_canonical_reversal:
  "canonical_reversal_words (replicate reversal_word_count 0)"
  by (simp add: canonical_reversal_words_def enums_fit_def words_fit_def word_fits_def
      reversal_enum_words_def reversal_address_words_def reversal_uint64_words_def
      reversal_uint48_words_def reversal_word_count_def)

definition action_request_witness :: evm_bytes where
  "action_request_witness = [47, 78, 7, 115] @ replicate (32 * action_word_count) 0"

definition reversal_request_witness :: evm_bytes where
  "reversal_request_witness = [43, 137, 46, 143] @ replicate (32 * reversal_word_count) 0"

theorem action_request_witness_is_canonical:
  "kernel_canonical_calldata action_request_witness \<and>
   calldata_selector action_request_witness = action_entrypoint_selector"
proof -
  have BYTES: "\<forall>byte\<in>set action_request_witness. byte < 256"
    by (simp add: action_request_witness_def)
  have LEN: "length action_request_witness = 4 + 32 * action_word_count"
    by (simp add: action_request_witness_def)
  have SEL: "calldata_selector action_request_witness = action_entrypoint_selector"
    by (simp add: action_request_witness_def calldata_selector_def calldata_bytes_nat_def
        action_entrypoint_selector_def)
  have WORDS: "calldata_words action_request_witness = replicate action_word_count 0"
    unfolding action_request_witness_def by (rule calldata_words_of_zero_words) simp
  have DECODE: "decode_native_action (calldata_selector action_request_witness)
      (calldata_words action_request_witness) \<noteq> None"
    using SEL WORDS zero_words_are_canonical_action
    by (simp add: decode_native_action_def action_selectors_def)
  show ?thesis
    using BYTES LEN SEL DECODE by (simp add: kernel_canonical_calldata_def)
qed

theorem reversal_request_witness_is_canonical:
  "kernel_canonical_calldata reversal_request_witness \<and>
   calldata_selector reversal_request_witness = reversal_entrypoint_selector"
proof -
  have BYTES: "\<forall>byte\<in>set reversal_request_witness. byte < 256"
    by (simp add: reversal_request_witness_def)
  have LEN: "length reversal_request_witness = 4 + 32 * reversal_word_count"
    by (simp add: reversal_request_witness_def)
  have SEL: "calldata_selector reversal_request_witness = reversal_entrypoint_selector"
    by (simp add: reversal_request_witness_def calldata_selector_def calldata_bytes_nat_def
        reversal_entrypoint_selector_def)
  have WORDS: "calldata_words reversal_request_witness = replicate reversal_word_count 0"
    unfolding reversal_request_witness_def by (rule calldata_words_of_zero_words) simp
  have DECODE: "decode_native_reversal (calldata_selector reversal_request_witness)
      (calldata_words reversal_request_witness) \<noteq> None"
    using SEL WORDS zero_words_are_canonical_reversal
    by (simp add: decode_native_reversal_def reversal_selectors_def)
  show ?thesis
    using BYTES LEN SEL DECODE by (simp add: kernel_canonical_calldata_def)
qed

theorem request_in_canonical_form_is_inhabited:
  "\<exists>execution. request_in_canonical_form execution"
proof -
  define execution where "execution =
    \<lparr>transaction_pre = undefined, transaction_sender = 0, transaction_value = 0,
     transaction_time = 0, transaction_chain = 0, transaction_gas_limit = 0,
     transaction_calldata = action_request_witness, transaction_external_calls = [],
     transaction_phase = TRUST_Idle, transaction_result = TRUST_Return_Malformed [],
     transaction_post_world = undefined, transaction_raw_logs = []\<rparr>"
  have "request_in_canonical_form execution"
    using action_request_witness_is_canonical
    by (simp add: request_in_canonical_form_def execution_def)
  then show ?thesis by blast
qed

section \<open>The out-of-specification branch\<close>

definition out_of_spec_stutter ::
  "trust_runtime_manifest \<Rightarrow> trust_transaction_execution \<Rightarrow>
   trust_transaction_abstraction \<Rightarrow> bool"
where
  "out_of_spec_stutter manifest execution abstraction \<longleftrightarrow>
     alpha_current manifest (transaction_pre execution) = Some (abstraction_pre_state abstraction) \<and>
     abstraction_post_state abstraction = abstraction_pre_state abstraction \<and>
     abstraction_sender abstraction = transaction_sender execution \<and>
     abstraction_time abstraction = transaction_time execution \<and>
     abstraction_command abstraction = None \<and>
     abstraction_outcome abstraction = TRUST_Abstract_Malformed \<and>
     transaction_post_world execution = current_world (transaction_pre execution) \<and>
     transaction_raw_logs execution = [] \<and>
     transaction_external_calls execution = [] \<and>
     \<not> transaction_committed execution"

definition alpha_transaction_spec ::
  "trust_runtime_manifest \<Rightarrow> trust_transaction_bridge \<Rightarrow>
   trust_transaction_execution \<Rightarrow> trust_transaction_abstraction \<Rightarrow> bool"
where
  "alpha_transaction_spec manifest bridge execution abstraction \<longleftrightarrow>
     (case transaction_command bridge execution of
        None \<Rightarrow> out_of_spec_stutter manifest execution abstraction
      | Some _ \<Rightarrow> alpha_transaction manifest bridge execution abstraction)"

theorem canonical_request_keeps_alpha_transaction:
  assumes "transaction_command bridge execution = Some command"
  shows "alpha_transaction_spec manifest bridge execution abstraction \<longleftrightarrow>
         alpha_transaction manifest bridge execution abstraction"
  using assms by (simp add: alpha_transaction_spec_def)

theorem canonical_request_carries_its_command:
  assumes COMMAND: "transaction_command bridge execution = Some command"
      and SPEC: "alpha_transaction_spec manifest bridge execution abstraction"
  shows "abstraction_command abstraction = Some command \<and>
         abstraction_outcome abstraction \<noteq> TRUST_Abstract_Malformed"
proof -
  have DECODE: "bridge_decode_calldata bridge (transaction_calldata execution) = Some command"
    using canonical_request_has_zero_value[OF COMMAND] by simp
  have ALPHA: "alpha_transaction manifest bridge execution abstraction"
    using SPEC COMMAND by (simp add: alpha_transaction_spec_def)
  have READ: "bridge_decode_calldata bridge (transaction_calldata execution) =
      abstraction_command abstraction"
    using ALPHA unfolding alpha_transaction_def by blast
  have CARRIED: "abstraction_command abstraction = Some command"
    using READ DECODE by simp
  have MALFORMED_NONE: "abstraction_outcome abstraction = TRUST_Abstract_Malformed \<Longrightarrow>
      abstraction_command abstraction = None"
    using ALPHA by (simp add: alpha_transaction_def)
  have "abstraction_outcome abstraction \<noteq> TRUST_Abstract_Malformed"
    using MALFORMED_NONE CARRIED by auto
  with CARRIED show ?thesis by simp
qed

theorem unchanged_world_keeps_the_configuration:
  assumes "transaction_post_world execution = current_world (transaction_pre execution)"
  shows "transaction_post_configuration execution = transaction_pre execution"
  using assms
  by (cases "transaction_pre execution") (simp add: transaction_post_configuration_def)

theorem out_of_spec_request_is_a_full_state_stutter:
  assumes NONE: "transaction_command bridge execution = None"
      and SPEC: "alpha_transaction_spec manifest bridge execution abstraction"
  shows "transaction_post_world execution = current_world (transaction_pre execution) \<and>
         transaction_raw_logs execution = [] \<and>
         transaction_external_calls execution = [] \<and>
         \<not> transaction_committed execution \<and>
         abstraction_command abstraction = None \<and>
         abstraction_post_state abstraction = abstraction_pre_state abstraction \<and>
         alpha_current manifest (transaction_post_configuration execution) =
           Some (abstraction_post_state abstraction)"
proof -
  have STUTTER: "out_of_spec_stutter manifest execution abstraction"
    using SPEC NONE by (simp add: alpha_transaction_spec_def)
  then have WORLD: "transaction_post_world execution = current_world (transaction_pre execution)"
    by (simp add: out_of_spec_stutter_def)
  have POST: "transaction_post_configuration execution = transaction_pre execution"
    using unchanged_world_keeps_the_configuration[OF WORLD] .
  show ?thesis using STUTTER POST by (simp add: out_of_spec_stutter_def)
qed

theorem out_of_spec_request_never_succeeds:
  assumes "transaction_command bridge execution = None"
      and "transaction_result execution = TRUST_Return_Success payload"
  shows "\<not> alpha_transaction_spec manifest bridge execution abstraction"
  using assms
  by (simp add: alpha_transaction_spec_def out_of_spec_stutter_def transaction_committed_def)

section \<open>The decoded branch is inhabited\<close>

text \<open>
  The decoded branch is alpha_transaction.  decoded_branch_is_inhabited exhibits one execution of it:
  the action witness request with a zero call value, under a witness bridge that decodes only that
  request and satisfies typed_decoder_sound, rejected without a state change or a log.  The witness
  bridge is not the bridge of a deployed runtime, so the theorem shows that a request in canonical
  form can satisfy the decoded branch, not that a deployed runtime decodes or rejects that request.
\<close>

theorem decoded_branch_is_inhabited:
  "\<exists>manifest bridge execution abstraction command.
     typed_decoder_sound bridge \<and>
     request_in_canonical_form execution \<and>
     transaction_command bridge execution = Some command \<and>
     alpha_transaction_spec manifest bridge execution abstraction"
proof -
  obtain manifest configuration state where
    ALPHA: "alpha_current manifest configuration = Some state"
    using current_configuration_wf_is_inhabited by blast
  define command :: trust_typed_command where "command = TRUST_Forward undefined"
  define bridge :: trust_transaction_bridge where "bridge =
    \<lparr>bridge_decode_calldata =
       (\<lambda>calldata. if calldata = action_request_witness then Some command else None),
     bridge_receipt_log = undefined, bridge_return_receipt_hash = undefined,
     bridge_external_trace_ok = undefined, bridge_committed_receipt = undefined\<rparr>"
  define execution where "execution =
    \<lparr>transaction_pre = configuration, transaction_sender = 0, transaction_value = 0,
     transaction_time = 0, transaction_chain = 0, transaction_gas_limit = 0,
     transaction_calldata = action_request_witness, transaction_external_calls = [],
     transaction_phase = TRUST_Idle, transaction_result = TRUST_Return_Rejection [],
     transaction_post_world = current_world configuration, transaction_raw_logs = []\<rparr>"
  define abstraction where "abstraction =
    \<lparr>abstraction_pre_state = state, abstraction_post_state = state,
     abstraction_sender = 0, abstraction_time = 0,
     abstraction_command = Some command, abstraction_outcome = TRUST_Abstract_Rejected,
     abstraction_forward_witness = None, abstraction_reversal_witness = None,
     abstraction_effect_logs = []\<rparr>"
  have LENGTH: "length action_request_witness = action_calldata_length"
    by (simp add: action_request_witness_def action_calldata_length_def action_word_count_def)
  have SOUND: "typed_decoder_sound bridge"
    using LENGTH by (auto simp: typed_decoder_sound_def bridge_def command_def split: if_splits)
  have CANONICAL: "request_in_canonical_form execution"
    using action_request_witness_is_canonical
    by (simp add: request_in_canonical_form_def execution_def)
  have COMMAND: "transaction_command bridge execution = Some command"
    using CANONICAL by (simp add: transaction_command_def bridge_def execution_def)
  have POST: "transaction_post_configuration execution = transaction_pre execution"
    by (rule unchanged_world_keeps_the_configuration) (simp add: execution_def)
  have DECODED: "alpha_transaction manifest bridge execution abstraction"
    using ALPHA POST by (simp add: alpha_transaction_def execution_def abstraction_def bridge_def)
  have SPEC: "alpha_transaction_spec manifest bridge execution abstraction"
    using COMMAND DECODED by (simp add: alpha_transaction_spec_def)
  show ?thesis using SOUND CANONICAL COMMAND SPEC by blast
qed

section \<open>The out-of-specification branch is inhabited\<close>

text \<open>
  Both witnesses call a typed command function: the first carries the action witness request with a
  nonzero call value, the second a zero call value and calldata that is only the action entrypoint
  selector.
\<close>

definition out_of_spec_witness_execution ::
  "current_trust_configuration \<Rightarrow> trust_transaction_execution"
where
  "out_of_spec_witness_execution configuration =
     \<lparr>transaction_pre = configuration, transaction_sender = 0, transaction_value = 1,
      transaction_time = 0, transaction_chain = 0, transaction_gas_limit = 0,
      transaction_calldata = action_request_witness, transaction_external_calls = [],
      transaction_phase = TRUST_Idle, transaction_result = TRUST_Return_Malformed [],
      transaction_post_world = current_world configuration, transaction_raw_logs = []\<rparr>"

definition out_of_spec_zero_value_witness_execution ::
  "current_trust_configuration \<Rightarrow> trust_transaction_execution"
where
  "out_of_spec_zero_value_witness_execution configuration =
     (out_of_spec_witness_execution configuration)
       \<lparr>transaction_value := 0, transaction_calldata := [47, 78, 7, 115]\<rparr>"

theorem out_of_spec_branch_is_inhabited:
  "\<exists>manifest bridge execution abstraction.
     transaction_value execution \<noteq> 0 \<and>
     calldata_selector (transaction_calldata execution) \<in> action_selectors \<and>
     transaction_command bridge execution = None \<and>
     alpha_transaction_spec manifest bridge execution abstraction"
proof -
  obtain manifest configuration state where
    ALPHA: "alpha_current manifest configuration = Some state"
    using current_configuration_wf_is_inhabited by blast
  define execution where "execution = out_of_spec_witness_execution configuration"
  define abstraction where "abstraction =
    \<lparr>abstraction_pre_state = state, abstraction_post_state = state,
     abstraction_sender = transaction_sender execution, abstraction_time = transaction_time execution,
     abstraction_command = None, abstraction_outcome = TRUST_Abstract_Malformed,
     abstraction_forward_witness = None, abstraction_reversal_witness = None,
     abstraction_effect_logs = []\<rparr>"
  have VALUE: "transaction_value execution \<noteq> 0"
    by (simp add: execution_def out_of_spec_witness_execution_def)
  have SELECTOR: "calldata_selector (transaction_calldata execution) \<in> action_selectors"
    using action_request_witness_is_canonical
    by (simp add: execution_def out_of_spec_witness_execution_def action_selectors_def)
  have NONE: "transaction_command undefined execution = None"
    by (simp add: transaction_command_def request_in_canonical_form_def execution_def
        out_of_spec_witness_execution_def)
  have STUTTER: "out_of_spec_stutter manifest execution abstraction"
    using ALPHA
    by (simp add: out_of_spec_stutter_def execution_def abstraction_def
        out_of_spec_witness_execution_def transaction_committed_def)
  have SPEC: "alpha_transaction_spec manifest undefined execution abstraction"
    using STUTTER NONE by (simp add: alpha_transaction_spec_def)
  show ?thesis using VALUE SELECTOR NONE SPEC by blast
qed

theorem zero_value_out_of_spec_branch_is_inhabited:
  "\<exists>manifest bridge execution abstraction.
     transaction_value execution = 0 \<and>
     calldata_selector (transaction_calldata execution) \<in> action_selectors \<and>
     \<not> kernel_canonical_calldata (transaction_calldata execution) \<and>
     transaction_command bridge execution = None \<and>
     alpha_transaction_spec manifest bridge execution abstraction"
proof -
  obtain manifest configuration state where
    ALPHA: "alpha_current manifest configuration = Some state"
    using current_configuration_wf_is_inhabited by blast
  define execution where "execution = out_of_spec_zero_value_witness_execution configuration"
  define abstraction where "abstraction =
    \<lparr>abstraction_pre_state = state, abstraction_post_state = state,
     abstraction_sender = transaction_sender execution, abstraction_time = transaction_time execution,
     abstraction_command = None, abstraction_outcome = TRUST_Abstract_Malformed,
     abstraction_forward_witness = None, abstraction_reversal_witness = None,
     abstraction_effect_logs = []\<rparr>"
  have VALUE: "transaction_value execution = 0"
    by (simp add: execution_def out_of_spec_zero_value_witness_execution_def)
  have SELECTOR: "calldata_selector (transaction_calldata execution) \<in> action_selectors"
    by (simp add: execution_def out_of_spec_zero_value_witness_execution_def
        out_of_spec_witness_execution_def calldata_selector_def calldata_bytes_nat_def
        action_selectors_def action_entrypoint_selector_def)
  have NOT_CANONICAL: "\<not> kernel_canonical_calldata (transaction_calldata execution)"
  proof
    assume "kernel_canonical_calldata (transaction_calldata execution)"
    then have "length (transaction_calldata execution) = action_calldata_length \<or>
        length (transaction_calldata execution) = reversal_calldata_length"
      by (rule canonical_calldata_has_a_kernel_length)
    then show False
      by (simp add: execution_def out_of_spec_zero_value_witness_execution_def
          out_of_spec_witness_execution_def action_calldata_length_def reversal_calldata_length_def)
  qed
  have NONE: "transaction_command undefined execution = None"
    using NOT_CANONICAL by (rule noncanonical_calldata_is_out_of_spec)
  have STUTTER: "out_of_spec_stutter manifest execution abstraction"
    using ALPHA
    by (simp add: out_of_spec_stutter_def execution_def abstraction_def
        out_of_spec_zero_value_witness_execution_def out_of_spec_witness_execution_def
        transaction_committed_def)
  have SPEC: "alpha_transaction_spec manifest undefined execution abstraction"
    using STUTTER NONE by (simp add: alpha_transaction_spec_def)
  show ?thesis using VALUE SELECTOR NOT_CANONICAL NONE SPEC by blast
qed

section \<open>The revert data of an out-of-specification request is not fixed\<close>

theorem out_of_spec_payload_is_unspecified:
  assumes NONE: "transaction_command bridge execution = None"
      and FAILED: "\<not> transaction_committed execution"
      and OTHER_FAILED: "\<not> transaction_committed (execution\<lparr>transaction_result := result\<rparr>)"
  shows "alpha_transaction_spec manifest bridge (execution\<lparr>transaction_result := result\<rparr>) abstraction \<longleftrightarrow>
         alpha_transaction_spec manifest bridge execution abstraction"
proof -
  have SAME_COMMAND: "transaction_command bridge (execution\<lparr>transaction_result := result\<rparr>) =
      transaction_command bridge execution"
    by (simp add: transaction_command_def request_in_canonical_form_def)
  have OTHER_NONE: "transaction_command bridge (execution\<lparr>transaction_result := result\<rparr>) = None"
    using SAME_COMMAND NONE by simp
  have "out_of_spec_stutter manifest (execution\<lparr>transaction_result := result\<rparr>) abstraction \<longleftrightarrow>
        out_of_spec_stutter manifest execution abstraction"
    using FAILED OTHER_FAILED by (simp add: out_of_spec_stutter_def)
  then show ?thesis using NONE OTHER_NONE by (simp add: alpha_transaction_spec_def)
qed

theorem out_of_spec_admits_every_failure_payload:
  assumes NONE: "transaction_command bridge execution = None"
      and SPEC: "alpha_transaction_spec manifest bridge execution abstraction"
      and RESULT: "result \<in> {TRUST_Return_Rejection payload, TRUST_Return_Operational_Failure payload,
                              TRUST_Return_Malformed payload, TRUST_Return_Revert payload}"
  shows "alpha_transaction_spec manifest bridge (execution\<lparr>transaction_result := result\<rparr>) abstraction"
proof -
  have FAILED: "\<not> transaction_committed execution"
    using out_of_spec_request_is_a_full_state_stutter[OF NONE SPEC] by simp
  have OTHER_FAILED: "\<not> transaction_committed (execution\<lparr>transaction_result := result\<rparr>)"
    using RESULT by (auto simp: transaction_committed_def)
  show ?thesis
    using out_of_spec_payload_is_unspecified[OF NONE FAILED OTHER_FAILED] SPEC by blast
qed

text \<open>
  Besides a malformed alpha_transaction, the next theorem needs the world equation and the empty call
  list of the out-of-specification branch, which alpha_transaction does not state for a malformed
  outcome.
\<close>

theorem strict_malformed_branch_implies_the_out_of_spec_branch:
  assumes ALPHA: "alpha_transaction manifest bridge execution abstraction"
      and MALFORMED: "abstraction_outcome abstraction = TRUST_Abstract_Malformed"
      and WORLD: "transaction_post_world execution = current_world (transaction_pre execution)"
      and CALLS: "transaction_external_calls execution = []"
  shows "alpha_transaction_spec manifest bridge execution abstraction"
proof -
  have READ: "bridge_decode_calldata bridge (transaction_calldata execution) =
      abstraction_command abstraction"
    using ALPHA unfolding alpha_transaction_def by blast
  have NO_COMMAND: "abstraction_command abstraction = None"
    using ALPHA MALFORMED by (simp add: alpha_transaction_def)
  have NONE: "transaction_command bridge execution = None"
    using READ NO_COMMAND by (simp add: transaction_command_def)
  have "out_of_spec_stutter manifest execution abstraction"
    using ALPHA MALFORMED WORLD CALLS
    by (auto simp: alpha_transaction_def out_of_spec_stutter_def transaction_committed_def)
  then show ?thesis using NONE by (simp add: alpha_transaction_spec_def)
qed

section \<open>Determinacy of the out-of-specification abstraction\<close>

definition out_of_spec_abstraction_normal :: "trust_transaction_abstraction \<Rightarrow> bool" where
  "out_of_spec_abstraction_normal abstraction \<longleftrightarrow>
     abstraction_forward_witness abstraction = None \<and>
     abstraction_reversal_witness abstraction = None \<and>
     abstraction_effect_logs abstraction = []"

theorem out_of_spec_abstraction_is_determined:
  assumes NONE: "transaction_command bridge execution = None"
      and FIRST: "alpha_transaction_spec manifest bridge execution first"
      and SECOND: "alpha_transaction_spec manifest bridge execution second"
      and FIRST_NORMAL: "out_of_spec_abstraction_normal first"
      and SECOND_NORMAL: "out_of_spec_abstraction_normal second"
  shows "first = second"
proof -
  have ONE: "out_of_spec_stutter manifest execution first"
    using FIRST NONE by (simp add: alpha_transaction_spec_def)
  have TWO: "out_of_spec_stutter manifest execution second"
    using SECOND NONE by (simp add: alpha_transaction_spec_def)
  have PRE: "abstraction_pre_state first = abstraction_pre_state second"
    using ONE TWO by (simp add: out_of_spec_stutter_def)
  show ?thesis
    using ONE TWO PRE FIRST_NORMAL SECOND_NORMAL
    by (cases first; cases second)
       (simp add: out_of_spec_stutter_def out_of_spec_abstraction_normal_def)
qed

section \<open>Runtime refinement against the proposal\<close>

locale pinned_runtime_refinement_spec =
  fixes manifest :: trust_runtime_manifest
    and bridge :: trust_transaction_bridge
    and runtime_execution :: "trust_transaction_execution \<Rightarrow> bool"
    and runtime_abstraction :: "trust_transaction_execution \<Rightarrow> trust_transaction_abstraction"
  assumes runtime_link_spec:
    "runtime_execution execution \<Longrightarrow>
     alpha_transaction_spec manifest bridge execution (runtime_abstraction execution)"
begin

lemma decoded_runtime_link:
  assumes "runtime_execution execution \<and> transaction_command bridge execution \<noteq> None"
  shows "alpha_transaction manifest bridge execution (runtime_abstraction execution)"
proof -
  from assms obtain command where
    RUN: "runtime_execution execution" and
    COMMAND: "transaction_command bridge execution = Some command"
    by auto
  show ?thesis
    using runtime_link_spec[OF RUN] canonical_request_keeps_alpha_transaction[OF COMMAND] by blast
qed

sublocale canonical: pinned_runtime_refinement manifest bridge
    "\<lambda>execution. runtime_execution execution \<and> transaction_command bridge execution \<noteq> None"
    runtime_abstraction
  by unfold_locales (rule decoded_runtime_link)

theorem runtime_out_of_spec_request_is_a_full_state_stutter:
  assumes RUN: "runtime_execution execution"
      and NONE: "transaction_command bridge execution = None"
  shows "transaction_post_world execution = current_world (transaction_pre execution) \<and>
         transaction_raw_logs execution = [] \<and>
         transaction_external_calls execution = [] \<and>
         \<not> transaction_committed execution \<and>
         abstraction_post_state (runtime_abstraction execution) =
           abstraction_pre_state (runtime_abstraction execution)"
  using out_of_spec_request_is_a_full_state_stutter[OF NONE runtime_link_spec[OF RUN]] by simp

theorem runtime_request_outside_canonical_form_is_a_full_state_stutter:
  assumes RUN: "runtime_execution execution"
      and OUT: "\<not> request_in_canonical_form execution"
  shows "transaction_post_world execution = current_world (transaction_pre execution) \<and>
         transaction_raw_logs execution = [] \<and>
         transaction_external_calls execution = [] \<and>
         \<not> transaction_committed execution \<and>
         abstraction_post_state (runtime_abstraction execution) =
           abstraction_pre_state (runtime_abstraction execution)"
  using runtime_out_of_spec_request_is_a_full_state_stutter[OF RUN
      request_outside_canonical_form_is_out_of_spec[OF OUT]] .

theorem runtime_nonzero_value_call_is_a_full_state_stutter:
  assumes RUN: "runtime_execution execution"
      and VALUE: "transaction_value execution \<noteq> 0"
  shows "transaction_post_world execution = current_world (transaction_pre execution) \<and>
         transaction_raw_logs execution = [] \<and>
         transaction_external_calls execution = [] \<and>
         \<not> transaction_committed execution"
  using runtime_out_of_spec_request_is_a_full_state_stutter[OF RUN
      nonzero_call_value_is_out_of_spec[OF VALUE]] by simp

theorem runtime_noncanonical_calldata_is_a_full_state_stutter:
  assumes RUN: "runtime_execution execution"
      and CALLDATA: "\<not> kernel_canonical_calldata (transaction_calldata execution)"
  shows "transaction_post_world execution = current_world (transaction_pre execution) \<and>
         transaction_raw_logs execution = [] \<and>
         transaction_external_calls execution = [] \<and>
         \<not> transaction_committed execution"
  using runtime_out_of_spec_request_is_a_full_state_stutter[OF RUN
      noncanonical_calldata_is_out_of_spec[OF CALLDATA]] by simp

end

text \<open>
  Non-claim: this theory states a conformance relation for the typed command functions and proves its
  consequences under the locale assumption runtime_link_spec; like alpha_transaction it fixes neither
  the validation order nor the error of a failed request in canonical form.  It does not discharge
  that assumption for any deployed runtime, and it does not formalize the treatment of a reentrant
  call.  It does not fix the revert data of a request outside canonical form, which can be empty, a
  typed error or any other data, nor which defect of such a request is detected first, and it does not
  model the identifier derivation functions deriveActionId and deriveReversalId, whose result the
  proposal leaves unspecified for a call that is not a zero-value call with canonical calldata.
  transaction_external_calls lists the message calls to accounts other than the endpoint; a
  proxy-fronted endpoint, whose proxy runs its implementation by a DELEGATECALL, is outside this
  theory.  The execution of the decoded branch in decoded_branch_is_inhabited uses a witness bridge;
  it does not show that a deployed runtime decodes that request or reaches that branch.
\<close>

end
