(*
  ERC-TRUST executable manifest kernel.

  Two domains are deliberately separate:
    * the inherited 5-state x 7-label foundation transition table; and
    * the TRUST 6-action x 3-outcome-scenario executable domain.
  Keeping these domains separate prevents the six product actions from being
  confused with the seven state-transition labels.
*)

theory Executable_Regulatory_Kernel
  imports Privileged_Governance
begin

datatype manifest_scenario =
    Manifest_Success
  | Manifest_Denied
  | Manifest_Dependency_Failure

datatype manifest_outcome_class =
    Manifest_Applied
  | Manifest_Rejected
  | Manifest_Operational_Failure

datatype required_observable =
    Applied_Receipt_Observable
  | Rejection_Error_Observable
  | Operational_Failure_Error_Observable

datatype manifest_target =
    Manifest_No_Target
  | Manifest_Target reg_state

datatype foundation_manifest_outcome_tag =
    Foundation_Manifest_Applied
  | Foundation_Manifest_Rejected
  | Foundation_Manifest_Operational_Failure

fun manifest_target_of :: "reg_state option \<Rightarrow> manifest_target" where
  "manifest_target_of None = Manifest_No_Target"
| "manifest_target_of (Some state) = Manifest_Target state"

fun foundation_manifest_outcome_tag_of ::
  "command_outcome \<Rightarrow> foundation_manifest_outcome_tag"
where
  "foundation_manifest_outcome_tag_of (Applied _) = Foundation_Manifest_Applied"
| "foundation_manifest_outcome_tag_of (Rejected _) = Foundation_Manifest_Rejected"
| "foundation_manifest_outcome_tag_of (Operational_Failure _) =
     Foundation_Manifest_Operational_Failure"

record trust_manifest_input =
  manifest_action   :: legal_action_kind
  manifest_scenario :: manifest_scenario
  manifest_initial_state :: reg_state

record trust_manifest_row =
  row_input             :: trust_manifest_input
  row_operation         :: trust_operation
  row_outcome           :: manifest_outcome_class
  row_target_state      :: "reg_state option"
  row_descriptor        :: legal_effect_descriptor
  row_transfer_gate     :: bool
  row_required_observable :: required_observable
  row_write_set         :: "write_slot list"

definition all_manifest_scenarios :: "manifest_scenario list" where
  "all_manifest_scenarios =
    [Manifest_Success, Manifest_Denied, Manifest_Dependency_Failure]"

fun expected_manifest_outcome ::
  "manifest_scenario \<Rightarrow> manifest_outcome_class"
where
  "expected_manifest_outcome Manifest_Success = Manifest_Applied"
| "expected_manifest_outcome Manifest_Denied = Manifest_Rejected"
| "expected_manifest_outcome Manifest_Dependency_Failure =
     Manifest_Operational_Failure"

fun expected_required_observable ::
  "manifest_scenario \<Rightarrow> required_observable"
where
  "expected_required_observable Manifest_Success =
     Applied_Receipt_Observable"
| "expected_required_observable Manifest_Denied =
     Rejection_Error_Observable"
| "expected_required_observable Manifest_Dependency_Failure =
     Operational_Failure_Error_Observable"

fun manifest_outcome_class_of ::
  "trust_outcome \<Rightarrow> manifest_outcome_class"
where
  "manifest_outcome_class_of Trust_Applied = Manifest_Applied"
| "manifest_outcome_class_of (Trust_Rejected _) = Manifest_Rejected"
| "manifest_outcome_class_of (Trust_Operational_Failure _) =
     Manifest_Operational_Failure"

fun manifest_required_observable_of ::
  "trust_outcome \<Rightarrow> required_observable"
where
  "manifest_required_observable_of Trust_Applied =
     Applied_Receipt_Observable"
| "manifest_required_observable_of (Trust_Rejected _) =
     Rejection_Error_Observable"
| "manifest_required_observable_of (Trust_Operational_Failure _) =
     Operational_Failure_Error_Observable"

definition manifest_fixture_entrypoint ::
  "legal_action_kind \<Rightarrow> manifest_scenario \<Rightarrow> trust_entrypoint"
where
  "manifest_fixture_entrypoint k scenario =
    (case scenario of
       Manifest_Success \<Rightarrow> witness_entrypoint k
     | Manifest_Denied \<Rightarrow> unauthorized_witness_entrypoint k
     | Manifest_Dependency_Failure \<Rightarrow> unavailable_witness_entrypoint k)"

definition manifest_execution ::
  "trust_manifest_input \<Rightarrow> trust_state \<times> trust_outcome"
where
  "manifest_execution input =
    execute_entrypoint (witness_prepared_state (manifest_action input))
      (manifest_fixture_entrypoint
        (manifest_action input) (manifest_scenario input))"

fun manifest_execution_target ::
  "nat \<Rightarrow> trust_state \<times> trust_outcome \<Rightarrow> reg_state option"
where
  "manifest_execution_target subject (st, Trust_Applied) =
     Some (trust_modes st subject)"
| "manifest_execution_target _ (_, Trust_Rejected _) = None"
| "manifest_execution_target _ (_, Trust_Operational_Failure _) = None"

fun manifest_execution_write_set ::
  "trust_state \<times> trust_outcome \<Rightarrow> write_slot list"
where
  "manifest_execution_write_set (st, Trust_Applied) =
     (case trust_last_receipt st of
        None \<Rightarrow> []
      | Some receipt \<Rightarrow> receipt_write_set receipt)"
| "manifest_execution_write_set (_, Trust_Rejected _) = []"
| "manifest_execution_write_set (_, Trust_Operational_Failure _) = []"

definition trust_manifest_kernel ::
  "trust_manifest_input \<Rightarrow> trust_manifest_row"
where
  "trust_manifest_kernel input =
    (let k = manifest_action input;
         scenario = manifest_scenario input;
         op = RCP_Operation k;
         execution = manifest_execution input;
         outcome = snd execution
     in
       \<lparr>row_input = input,
        row_operation = op,
        row_outcome = manifest_outcome_class_of outcome,
        row_target_state =
          manifest_execution_target
            (context_subject (witness_context k)) execution,
        row_descriptor = legal_descriptor k,
        row_transfer_gate =
          (outcome = Trust_Applied \<and> operation_is_transfer op),
        row_required_observable =
          manifest_required_observable_of outcome,
        row_write_set = manifest_execution_write_set execution
       \<rparr>)"

definition trust_manifest_inputs :: "trust_manifest_input list" where
  "trust_manifest_inputs =
    concat
      (map (\<lambda>k.
         map (\<lambda>scenario.
           \<lparr>manifest_action = k,
            manifest_scenario = scenario,
            manifest_initial_state = witness_initial_mode k\<rparr>)
           all_manifest_scenarios)
       all_rcp_actions)"

definition trust_manifest_rows :: "trust_manifest_row list" where
  "trust_manifest_rows = map trust_manifest_kernel trust_manifest_inputs"

theorem trust_manifest_domain_is_exactly_six_by_three:
  "length trust_manifest_inputs = 18 \<and>
   length trust_manifest_rows = 18 \<and>
   distinct trust_manifest_inputs"
  by (simp add: trust_manifest_inputs_def trust_manifest_rows_def
      all_manifest_scenarios_def all_rcp_actions_def)

theorem trust_manifest_kernel_preserves_input:
  "row_input (trust_manifest_kernel input) = input"
  by (simp add: trust_manifest_kernel_def Let_def)

theorem trust_manifest_kernel_is_actual_execution_evaluation:
  "row_outcome (trust_manifest_kernel input) =
     manifest_outcome_class_of (snd (manifest_execution input)) \<and>
   row_target_state (trust_manifest_kernel input) =
     manifest_execution_target
       (context_subject (witness_context (manifest_action input)))
       (manifest_execution input) \<and>
   row_required_observable (trust_manifest_kernel input) =
     manifest_required_observable_of (snd (manifest_execution input)) \<and>
   row_write_set (trust_manifest_kernel input) =
     manifest_execution_write_set (manifest_execution input)"
  by (simp add: trust_manifest_kernel_def Let_def)

theorem every_manifest_fixture_scenario_is_reachable:
  shows
    "manifest_outcome_class_of (snd (manifest_execution input)) =
       expected_manifest_outcome (manifest_scenario input) \<and>
     manifest_required_observable_of (snd (manifest_execution input)) =
       expected_required_observable (manifest_scenario input)"
  using all_six_actions_have_reachable_applied_witnesses
    all_six_actions_have_reachable_denial_witnesses
    all_six_actions_have_reachable_operational_failure_witnesses
  by (cases "manifest_action input"; cases "manifest_scenario input")
     (simp_all add: manifest_execution_def manifest_fixture_entrypoint_def)

theorem every_trust_manifest_row_matches_its_reachable_scenario:
  assumes "input \<in> set trust_manifest_inputs"
  shows
    "manifest_initial_state input =
       witness_initial_mode (manifest_action input) \<and>
     row_outcome (trust_manifest_kernel input) =
       expected_manifest_outcome (manifest_scenario input) \<and>
     row_required_observable (trust_manifest_kernel input) =
       expected_required_observable (manifest_scenario input)"
  using assms every_manifest_fixture_scenario_is_reachable[of input]
  by (auto simp: trust_manifest_inputs_def all_rcp_actions_def
      all_manifest_scenarios_def trust_manifest_kernel_def Let_def)

record foundation_manifest_input =
  foundation_input_state  :: reg_state
  foundation_input_action :: reg_action

record foundation_manifest_row =
  foundation_row_input   :: foundation_manifest_input
  foundation_row_outcome :: command_outcome
  foundation_row_target  :: reg_state

definition foundation_manifest_inputs :: "foundation_manifest_input list" where
  "foundation_manifest_inputs =
    concat
      (map (\<lambda>s.
        map (\<lambda>a.
          \<lparr>foundation_input_state = s, foundation_input_action = a\<rparr>)
          all_transition_labels)
       all_reg_states)"

definition foundation_manifest_kernel ::
  "foundation_manifest_input \<Rightarrow> foundation_manifest_row"
where
  "foundation_manifest_kernel input =
    (let s = foundation_input_state input;
         a = foundation_input_action input;
         out = legal_outcome s a
     in
       \<lparr>foundation_row_input = input,
        foundation_row_outcome = out,
        foundation_row_target = state_after s out\<rparr>)"

definition foundation_manifest_rows :: "foundation_manifest_row list" where
  "foundation_manifest_rows = map foundation_manifest_kernel foundation_manifest_inputs"

theorem foundation_manifest_domain_is_exactly_five_by_seven:
  "length foundation_manifest_inputs = 35 \<and>
   length foundation_manifest_rows = 35 \<and>
   distinct foundation_manifest_inputs"
  by (simp add: foundation_manifest_inputs_def foundation_manifest_rows_def
      all_reg_states_def all_transition_labels_def)

theorem six_by_three_and_five_by_seven_are_not_conflated:
  "length trust_manifest_rows = 18 \<and>
   length foundation_manifest_rows = 35 \<and>
   length trust_manifest_rows \<noteq> length foundation_manifest_rows"
  by (simp add: trust_manifest_rows_def trust_manifest_inputs_def
      all_manifest_scenarios_def all_rcp_actions_def foundation_manifest_rows_def
      foundation_manifest_inputs_def all_reg_states_def all_transition_labels_def)

export_code trust_manifest_rows foundation_manifest_rows
  in SML module_name ERC_TRUST_Kernel

ML \<open>
  fun trust_join _ [] = ""
    | trust_join _ [x] = x
    | trust_join separator (x :: xs) =
        x ^ separator ^ trust_join separator xs;

  fun trust_action_name @{code Legal_Freeze} = "FREEZE"
    | trust_action_name @{code Legal_Seize} = "SEIZE"
    | trust_action_name @{code Legal_Confiscate} = "CONFISCATE"
    | trust_action_name @{code Legal_Restrict} = "RESTRICT"
    | trust_action_name @{code Legal_Recover} = "RECOVER"
    | trust_action_name @{code Legal_Liquidate} = "LIQUIDATE";

  fun transition_name @{code FREEZE} = "FREEZE"
    | transition_name @{code SEIZE} = "SEIZE"
    | transition_name @{code CONFISCATE} = "CONFISCATE"
    | transition_name @{code RESTRICT} = "RESTRICT"
    | transition_name @{code UNFREEZE} = "UNFREEZE"
    | transition_name @{code UNRESTRICT} = "UNRESTRICT"
    | transition_name @{code RELEASE} = "RELEASE";

  fun state_name @{code ACTIVE} = "ACTIVE"
    | state_name @{code FROZEN} = "FROZEN"
    | state_name @{code SEIZED} = "SEIZED"
    | state_name @{code CONFISCATED} = "CONFISCATED"
    | state_name @{code RESTRICTED} = "RESTRICTED";

  fun scenario_name @{code Manifest_Success} = "SUCCESS"
    | scenario_name @{code Manifest_Denied} = "DENIED"
    | scenario_name @{code Manifest_Dependency_Failure} =
        "DEPENDENCY_FAILURE";

  fun outcome_name @{code Manifest_Applied} = "APPLIED"
    | outcome_name @{code Manifest_Rejected} = "REJECTED"
    | outcome_name @{code Manifest_Operational_Failure} =
        "OPERATIONAL_FAILURE";

  fun required_observable_name @{code Applied_Receipt_Observable} =
        "APPLIED_RECEIPT"
    | required_observable_name @{code Rejection_Error_Observable} =
        "REJECTION_ERROR"
    | required_observable_name
        @{code Operational_Failure_Error_Observable} =
        "OPERATIONAL_FAILURE_ERROR";

  fun reversibility_name @{code Reversible} = "Reversible"
    | reversibility_name @{code Conditional} = "Conditional"
    | reversibility_name @{code Irreversible} = "Irreversible"
    | reversibility_name @{code Configurable} = "Configurable"
    | reversibility_name @{code One_Time} = "One_Time";

  fun ownership_name @{code Retained} = "Retained"
    | ownership_name @{code Transferred} = "Transferred"
    | ownership_name @{code Terminated} = "Terminated"
    | ownership_name @{code Restored} = "Restored";

  fun finality_name @{code Provisional} = "Provisional"
    | finality_name @{code Interim_Custodial} = "Interim_Custodial"
    | finality_name @{code Final} = "Final"
    | finality_name @{code Conditional_Finality} =
        "Conditional_Finality"
    | finality_name @{code Restorative} = "Restorative";

  fun slot_name @{code Regulatory_Mode_Slot} = "Regulatory_Mode_Slot"
    | slot_name @{code Balance_Slot} = "Balance_Slot"
    | slot_name @{code Custody_Slot} = "Custody_Slot"
    | slot_name @{code Frozen_Amount_Slot} = "Frozen_Amount_Slot"
    | slot_name @{code Case_Slot} = "Case_Slot"
    | slot_name @{code Encumbrance_Slot} = "Encumbrance_Slot"
    | slot_name @{code Prior_Holder_Slot} = "Prior_Holder_Slot"
    | slot_name @{code Settlement_Slot} = "Settlement_Slot"
    | slot_name @{code Entitlement_Slot} = "Entitlement_Slot"
    | slot_name @{code Supply_Slot} = "Supply_Slot"
    | slot_name @{code Allowance_Slot} = "Allowance_Slot"
    | slot_name @{code Policy_Binding_Slot} = "Policy_Binding_Slot"
    | slot_name @{code Authority_Epoch_Slot} = "Authority_Epoch_Slot"
    | slot_name @{code Policy_Change_Event_Slot} =
        "Policy_Change_Event_Slot"
    | slot_name @{code Authorization_Slot} = "Authorization_Slot"
    | slot_name @{code Nonce_Slot} = "Nonce_Slot"
    | slot_name @{code Receipt_Slot} = "Receipt_Slot";

  fun manifest_target_name @{code Manifest_No_Target} = "-"
    | manifest_target_name (@{code Manifest_Target} state) =
        state_name state;

  fun bool_name true = "true"
    | bool_name false = "false";

  fun trust_row_tsv row =
    let
      val input = @{code row_input} row;
      val action = @{code manifest_action} input;
      val scenario = @{code manifest_scenario} input;
      val initial_state = @{code manifest_initial_state} input;
      val descriptor = @{code row_descriptor} row;
    in
      trust_join "\t"
        ["TRUST|" ^ trust_action_name action ^ "|" ^ scenario_name scenario,
         trust_action_name action,
         scenario_name scenario,
         state_name initial_state,
         "RCP_OPERATION_" ^ trust_action_name action,
         outcome_name (@{code row_outcome} row),
         manifest_target_name
           (@{code manifest_target_of} (@{code row_target_state} row)),
         reversibility_name (@{code descriptor_reversibility} descriptor),
         ownership_name (@{code descriptor_ownership} descriptor),
         finality_name (@{code descriptor_finality} descriptor),
         bool_name (@{code row_transfer_gate} row),
         required_observable_name (@{code row_required_observable} row),
         trust_join ";" (map slot_name (@{code row_write_set} row))]
    end;

  fun foundation_outcome_name @{code Foundation_Manifest_Applied} = "APPLIED"
    | foundation_outcome_name @{code Foundation_Manifest_Rejected} =
        "REJECTED_UNDEFINED_TRANSITION"
    | foundation_outcome_name @{code Foundation_Manifest_Operational_Failure} =
        "OPERATIONAL_FAILURE";

  fun foundation_row_tsv row =
    let
      val input = @{code foundation_row_input} row;
      val state = @{code foundation_input_state} input;
      val action = @{code foundation_input_action} input;
    in
      trust_join "\t"
        ["FOUNDATION|" ^ state_name state ^ "|" ^ transition_name action,
         state_name state,
         transition_name action,
         transition_name action,
         foundation_outcome_name
           (@{code foundation_manifest_outcome_tag_of}
             (@{code foundation_row_outcome} row)),
         state_name (@{code foundation_row_target} row)]
    end;

  val trust_kernel_tsv =
    trust_join "\n" (map trust_row_tsv @{code trust_manifest_rows}) ^ "\n";
  val foundation_kernel_tsv =
    trust_join "\n" (map foundation_row_tsv @{code foundation_manifest_rows}) ^ "\n";

  val _ =
    Export.export \<^theory>
      \<^path_binding>\<open>erc-trust/trust-kernel.tsv\<close>
      [XML.Text trust_kernel_tsv];
  val _ =
    Export.export \<^theory>
      \<^path_binding>\<open>erc-trust/foundation-kernel.tsv\<close>
      [XML.Text foundation_kernel_tsv];
\<close>

end
