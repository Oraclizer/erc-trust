(* Partial retrieve relation from pinned EVM world state to the kernel version 2 TRUST state. *)

theory TRUST_Retrieve_Relation
  imports TRUST_Runtime_Bridge_Generated
begin

record trust_runtime_manifest =
  manifest_numeric_id :: trust_hash
  manifest_schema_sha256 :: string
  manifest_expected_code :: "trust_topology \<Rightarrow> trust_address \<Rightarrow> evm_bytes option"
  manifest_mapping_preimages :: "trust_footprint \<Rightarrow> evm_bytes list"
  manifest_keccak256 :: "evm_bytes \<Rightarrow> trust_word256"
  manifest_physical_balances :: "current_trust_configuration \<Rightarrow> trust_address \<Rightarrow> nat"
  manifest_allowances :: "current_trust_configuration \<Rightarrow> trust_address \<Rightarrow> trust_address \<Rightarrow> nat"
  manifest_total_supply :: "current_trust_configuration \<Rightarrow> nat"
  manifest_frozen_targets :: "current_trust_configuration \<Rightarrow> trust_address \<Rightarrow> nat"
  manifest_restriction_flags :: "current_trust_configuration \<Rightarrow> trust_address \<Rightarrow> bool"
  manifest_custody_backing :: "current_trust_configuration \<Rightarrow> trust_address \<Rightarrow> nat"
  manifest_freeze_heads :: "current_trust_configuration \<Rightarrow> trust_address \<Rightarrow> compositional_effect_head"
  manifest_restriction_heads :: "current_trust_configuration \<Rightarrow> trust_address \<Rightarrow> compositional_effect_head"
  manifest_effect_links :: "current_trust_configuration \<Rightarrow> trust_action_id \<Rightarrow> compositional_effect_link option"
  manifest_action_records :: "current_trust_configuration \<Rightarrow> trust_action_id \<Rightarrow> compositional_action_record option"
  manifest_custody_records :: "current_trust_configuration \<Rightarrow> trust_case_id \<Rightarrow> compositional_custody option"
  manifest_case_records :: "current_trust_configuration \<Rightarrow> trust_case_id \<Rightarrow> compositional_case"
  manifest_consumed_entitlements :: "current_trust_configuration \<Rightarrow> trust_hash set"
  manifest_authorities :: "current_trust_configuration \<Rightarrow> trust_authority_ref \<Rightarrow> compositional_authority option"
  manifest_consumed_nonces :: "current_trust_configuration \<Rightarrow> trust_nonce_key set"
  manifest_bindings :: "current_trust_configuration \<Rightarrow> trust_binding_kind \<Rightarrow> compositional_binding option"
  manifest_dependency_root :: "current_trust_configuration \<Rightarrow> trust_hash"
  manifest_dependency_epoch :: "current_trust_configuration \<Rightarrow> nat"
  manifest_receipts :: "current_trust_configuration \<Rightarrow> trust_hash \<Rightarrow> compositional_receipt option"
  manifest_layout_matches :: "current_trust_configuration \<Rightarrow> bool"
  manifest_footprint_complete :: "current_trust_configuration \<Rightarrow> bool"
  manifest_topology_well_formed :: "current_trust_configuration \<Rightarrow> bool"
  manifest_canonical_words :: "current_trust_configuration \<Rightarrow> bool"
  manifest_idle_auxiliary_state :: "current_trust_configuration \<Rightarrow> bool"

definition account_code_at ::
  "current_trust_configuration \<Rightarrow> trust_address \<Rightarrow> evm_bytes option"
where
  "account_code_at configuration address =
     map_option evm_account_code (current_world configuration address)"

definition pinned_runtime ::
  "trust_runtime_manifest \<Rightarrow> current_trust_configuration \<Rightarrow> bool"
where
  "pinned_runtime manifest configuration \<longleftrightarrow>
     current_manifest_id configuration = manifest_numeric_id manifest \<and>
     manifest_schema_sha256 manifest = runtime_bridge_schema_sha256 \<and>
     (\<forall>address\<in>footprint_addresses (current_footprint configuration).
       \<exists>code. manifest_expected_code manifest (current_topology configuration) address = Some code \<and>
              account_code_at configuration address = Some code)"

definition footprint_nonalias ::
  "trust_runtime_manifest \<Rightarrow> current_trust_configuration \<Rightarrow> bool"
where
  "footprint_nonalias manifest configuration \<longleftrightarrow>
     distinct (manifest_mapping_preimages manifest (current_footprint configuration)) \<and>
     inj_on (manifest_keccak256 manifest)
       (set (manifest_mapping_preimages manifest (current_footprint configuration)))"

definition current_configuration_wf ::
  "trust_runtime_manifest \<Rightarrow> current_trust_configuration \<Rightarrow> bool"
where
  "current_configuration_wf manifest configuration \<longleftrightarrow>
     current_configuration_well_bounded configuration \<and>
     pinned_runtime manifest configuration \<and>
     manifest_layout_matches manifest configuration \<and>
     manifest_footprint_complete manifest configuration \<and>
     footprint_nonalias manifest configuration \<and>
     manifest_topology_well_formed manifest configuration \<and>
     manifest_canonical_words manifest configuration \<and>
     manifest_idle_auxiliary_state manifest configuration"

definition projected_compositional_state ::
  "trust_runtime_manifest \<Rightarrow> current_trust_configuration \<Rightarrow>
   trust_compositional_state"
where
  "projected_compositional_state manifest configuration =
     \<lparr>physical_balances = manifest_physical_balances manifest configuration,
      compositional_allowances = manifest_allowances manifest configuration,
      compositional_total_supply = manifest_total_supply manifest configuration,
      frozen_targets = manifest_frozen_targets manifest configuration,
      restriction_flags = manifest_restriction_flags manifest configuration,
      custody_backing = manifest_custody_backing manifest configuration,
      freeze_heads = manifest_freeze_heads manifest configuration,
      restriction_heads = manifest_restriction_heads manifest configuration,
      effect_links = manifest_effect_links manifest configuration,
      action_records = manifest_action_records manifest configuration,
      custody_records = manifest_custody_records manifest configuration,
      case_records = manifest_case_records manifest configuration,
      consumed_entitlements = manifest_consumed_entitlements manifest configuration,
      authorities = manifest_authorities manifest configuration,
      compositional_consumed_nonces = manifest_consumed_nonces manifest configuration,
      compositional_bindings = manifest_bindings manifest configuration,
      dependency_root = manifest_dependency_root manifest configuration,
      dependency_epoch = manifest_dependency_epoch manifest configuration,
      compositional_receipts = manifest_receipts manifest configuration\<rparr>"

definition alpha_current ::
  "trust_runtime_manifest \<Rightarrow> current_trust_configuration \<Rightarrow>
   trust_compositional_state option"
where
  "alpha_current manifest configuration =
     (if current_configuration_wf manifest configuration
      then Some (projected_compositional_state manifest configuration)
      else None)"

definition generated_storage_keys ::
  "trust_runtime_manifest \<Rightarrow> trust_footprint \<Rightarrow> trust_word256 list"
where
  "generated_storage_keys manifest footprint =
     map (manifest_keccak256 manifest) (manifest_mapping_preimages manifest footprint)"

theorem finite_storage_keys_nonalias:
  assumes "distinct (manifest_mapping_preimages manifest footprint)"
      and "inj_on (manifest_keccak256 manifest)
             (set (manifest_mapping_preimages manifest footprint))"
  shows "distinct (generated_storage_keys manifest footprint)"
  using assms by (simp add: generated_storage_keys_def distinct_map)

theorem current_state_abstraction_well_defined:
  assumes "current_configuration_wf manifest configuration"
  shows "\<exists>!state. alpha_current manifest configuration = Some state"
  using assms by (simp add: alpha_current_def)

theorem alpha_current_is_functional:
  assumes "alpha_current manifest configuration = Some left"
      and "alpha_current manifest configuration = Some right"
  shows "left = right"
  using assms by simp

theorem alpha_current_requires_exact_runtime:
  assumes "alpha_current manifest configuration = Some state"
  shows "pinned_runtime manifest configuration"
proof -
  have "current_configuration_wf manifest configuration"
    using assms by (auto simp: alpha_current_def split: if_splits)
  then show ?thesis by (simp add: current_configuration_wf_def)
qed

theorem alpha_current_rejects_runtime_substitution:
  assumes "\<not> pinned_runtime manifest configuration"
  shows "alpha_current manifest configuration = None"
  using assms by (simp add: alpha_current_def current_configuration_wf_def)

theorem alpha_current_binds_the_generated_bridge_schema:
  assumes "alpha_current manifest configuration = Some state"
  shows "manifest_schema_sha256 manifest = runtime_bridge_schema_sha256"
  using alpha_current_requires_exact_runtime[OF assms] by (simp add: pinned_runtime_def)

theorem nonce_projection_is_exact:
  assumes "alpha_current manifest configuration = Some state"
  shows "compositional_consumed_nonces state =
         manifest_consumed_nonces manifest configuration"
  using assms
  by (auto simp: alpha_current_def projected_compositional_state_def split: if_splits)

theorem freeze_and_restriction_projections_are_independent:
  assumes "alpha_current manifest configuration = Some state"
  shows "frozen_targets state = manifest_frozen_targets manifest configuration \<and>
         restriction_flags state = manifest_restriction_flags manifest configuration"
  using assms
  by (auto simp: alpha_current_def projected_compositional_state_def split: if_splits)

theorem custody_backing_projection_is_exact:
  assumes "alpha_current manifest configuration = Some state"
  shows "custody_backing state = manifest_custody_backing manifest configuration"
  using assms
  by (auto simp: alpha_current_def projected_compositional_state_def split: if_splits)

theorem case_record_projection_is_exact:
  assumes "alpha_current manifest configuration = Some state"
  shows "case_records state case_id = manifest_case_records manifest configuration case_id"
  using assms
  by (auto simp: alpha_current_def projected_compositional_state_def split: if_splits)

theorem dependency_state_projection_is_exact:
  assumes "alpha_current manifest configuration = Some state"
  shows "dependency_root state = manifest_dependency_root manifest configuration \<and>
         dependency_epoch state = manifest_dependency_epoch manifest configuration"
  using assms
  by (auto simp: alpha_current_def projected_compositional_state_def split: if_splits)

theorem authority_projection_is_exact:
  assumes "alpha_current manifest configuration = Some state"
  shows "authorities state = manifest_authorities manifest configuration"
  using assms
  by (auto simp: alpha_current_def projected_compositional_state_def split: if_splits)

theorem receipt_projection_is_exact:
  assumes "alpha_current manifest configuration = Some state"
  shows "compositional_receipts state = manifest_receipts manifest configuration"
  using assms
  by (auto simp: alpha_current_def projected_compositional_state_def split: if_splits)

theorem pinned_runtime_pins_every_footprint_address:
  assumes "alpha_current manifest configuration = Some state"
      and "address \<in> footprint_addresses (current_footprint configuration)"
  shows "\<exists>code. manifest_expected_code manifest (current_topology configuration) address = Some code \<and>
                account_code_at configuration address = Some code"
  using alpha_current_requires_exact_runtime[OF assms(1)] assms(2)
  by (simp add: pinned_runtime_def)

text \<open>
  The retrieve relation is inhabited by a configuration with a nonempty footprint
  whose only address carries the code the manifest pins.  This is the typed
  inhabitant of the relation: it shows that the well-formedness predicates are
  jointly satisfiable and that the pin is not vacuous.
\<close>

definition inhabitant_manifest :: "evm_bytes \<Rightarrow> trust_runtime_manifest" where
  "inhabitant_manifest code =
     \<lparr>manifest_numeric_id = 0,
      manifest_schema_sha256 = runtime_bridge_schema_sha256,
      manifest_expected_code = (\<lambda>_ _. Some code),
      manifest_mapping_preimages = (\<lambda>_. []),
      manifest_keccak256 = (\<lambda>_. 0),
      manifest_physical_balances = (\<lambda>_ _. 0),
      manifest_allowances = (\<lambda>_ _ _. 0),
      manifest_total_supply = (\<lambda>_. 0),
      manifest_frozen_targets = (\<lambda>_ _. 0),
      manifest_restriction_flags = (\<lambda>_ _. False),
      manifest_custody_backing = (\<lambda>_ _. 0),
      manifest_freeze_heads = (\<lambda>_ _. empty_head),
      manifest_restriction_heads = (\<lambda>_ _. empty_head),
      manifest_effect_links = (\<lambda>_ _. None),
      manifest_action_records = (\<lambda>_ _. None),
      manifest_custody_records = (\<lambda>_ _. None),
      manifest_case_records = (\<lambda>_ _. empty_case),
      manifest_consumed_entitlements = (\<lambda>_. {}),
      manifest_authorities = (\<lambda>_ _. None),
      manifest_consumed_nonces = (\<lambda>_. {}),
      manifest_bindings = (\<lambda>_ _. None),
      manifest_dependency_root = (\<lambda>_. 0),
      manifest_dependency_epoch = (\<lambda>_. 1),
      manifest_receipts = (\<lambda>_ _. None),
      manifest_layout_matches = (\<lambda>_. True),
      manifest_footprint_complete = (\<lambda>_. True),
      manifest_topology_well_formed = (\<lambda>_. True),
      manifest_canonical_words = (\<lambda>_. True),
      manifest_idle_auxiliary_state = (\<lambda>_. True)\<rparr>"

definition inhabitant_configuration ::
  "trust_address \<Rightarrow> evm_bytes \<Rightarrow> current_trust_configuration"
where
  "inhabitant_configuration endpoint code =
     \<lparr>current_world =
        (\<lambda>address. if address = endpoint
           then Some \<lparr>evm_account_nonce = 1, evm_account_balance = 0,
                      evm_account_code = code, evm_account_storage = (\<lambda>_. 0)\<rparr>
           else None),
      current_topology = TRUST_Native endpoint,
      current_endpoint = endpoint,
      current_manifest_id = 0,
      current_footprint =
        \<lparr>footprint_addresses = {endpoint}, footprint_cases = {}, footprint_actions = {},
         footprint_receipts = {}, footprint_authorities = {}, footprint_nonce_keys = {},
         footprint_mapping_inputs = {}\<rparr>\<rparr>"

theorem inhabitant_configuration_is_well_formed:
  "current_configuration_wf (inhabitant_manifest code) (inhabitant_configuration endpoint code)"
  by (simp add: current_configuration_wf_def current_configuration_well_bounded_def
      pinned_runtime_def footprint_nonalias_def account_code_at_def
      inhabitant_manifest_def inhabitant_configuration_def)

theorem current_configuration_wf_is_inhabited:
  "\<exists>manifest configuration state. alpha_current manifest configuration = Some state"
  using inhabitant_configuration_is_well_formed[of code endpoint]
  by (auto simp: alpha_current_def)

theorem inhabitant_pins_the_endpoint_code:
  "account_code_at (inhabitant_configuration endpoint code) endpoint = Some code \<and>
   endpoint \<in> footprint_addresses (current_footprint (inhabitant_configuration endpoint code))"
  by (simp add: account_code_at_def inhabitant_configuration_def)

theorem current_state_does_not_assume_history:
  fixes left right :: current_trust_configuration
  assumes "current_world left = current_world right"
      and "current_topology left = current_topology right"
      and "current_endpoint left = current_endpoint right"
      and "current_manifest_id left = current_manifest_id right"
      and "current_footprint left = current_footprint right"
  shows "alpha_current manifest left = alpha_current manifest right"
  using assms current_configuration_extensional by blast

end
