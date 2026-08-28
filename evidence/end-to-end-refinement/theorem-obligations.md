# ERC-TRUST end-to-end refinement obligations

Status: complete 79-row assurance inventory; Native Full Core execution scope is governed by `m4-core-refinement-scope-v1.json`

Baseline: `b3cf2ccc385f4afa1a4a9e1d645d568a698d67e3`

## Current execution and publication classification

This file preserves all 79 obligation statements and remains the complete
assurance inventory. The Director-approved Core redesign does not delete,
weaken, merge, or silently discharge any row. It changes which rows require an
independent abstract-to-runtime execution seam before the Native Full core may
be described publicly.

- Core Refinement: 49 row-specific corollaries from reusable universal proofs;
  the mandatory current profile is qualified `49/49`.
- Core Supporting: 24 mandatory qualification gates; the current profile is
  qualified `24/24`, while six historical rows retain separate legacy status.
- Full Assurance Backlog: six nonblocking optional Profile/foundation rows;
  current `0/6` and outside the completed mandatory profile.

The exact partition, tool ownership, reusable C0 through C6 packages, ACT-01
disposition, TCB policy, and public claim boundary are frozen in
`m4-core-refinement-scope-v1.json` and explained in
`m4-core-refinement-redesign.md`. Progress must never be reported as one
combined fraction that mixes Core Refinement with Supporting qualification.
The historical `6/79 DISCHARGED` status is retained only as the legacy registry
fact.

Every obligation below must be tied to exact theory, source, compiler input,
runtime bytes, result logs, and reproducible evidence. A selected helper,
bounded test, or cross-tool agreement does not discharge an obligation unless
the named theorem states that boundary.

## A. State and retrieve relation

| ID | Required theorem or checked property |
| --- | --- |
| STATE-01 | `current_state_abstraction_well_defined`: the retrieve relation is total on the declared well-formed concrete footprint |
| STATE-02 | `storage_layout_matches_compiler_output`: every projected field and packing rule matches the pinned compiler storage layout |
| STATE-03 | `finite_storage_keys_nonalias`: all touched mapping preimages are pairwise nonalias under the declared Keccak premise |
| STATE-04 | `freeze_and_restriction_are_independent`: both overlays coexist without information loss |
| STATE-05 | `case_terminality_is_scoped`: terminality blocks the affected case and does not globally terminate the subject |
| STATE-06 | `nonce_projection_is_exact`: concrete nonce storage retrieves exactly `(authorityRef, authorityEpoch, nonce)` |
| STATE-07 | `current_state_does_not_assume_history`: current-state abstraction contains no historical calldata oracle |
| STATE-08 | `foundation_projection_is_explicitly_partial`: only `foundation_coherent` compositional states project to the single-mode foundation model |

## B. Balance and custody

| ID | Required theorem or checked property |
| --- | --- |
| BAL-01 | `custody_backing_equals_active_custody_sum` |
| BAL-02 | `physical_balance_covers_custody_backing` |
| BAL-03 | `beneficial_balance_is_conserved_by_seize` |
| BAL-04 | `beneficial_balance_is_conserved_by_release` |
| BAL-05 | `required_floor_is_additive_without_double_counting` |
| BAL-06 | `ordinary_transfer_preserves_backing_and_own_frozen_floor` |
| BAL-07 | `direct_enforcement_cannot_spend_unrelated_backing` |
| BAL-08 | `seize_cannot_spend_unrelated_backing` |
| BAL-09 | `custody_disposition_consumes_exact_backing_once` |
| BAL-10 | `physical_and_beneficial_supply_sums_agree` over the complete finite footprint |

## C. Effect provenance and reversal

| ID | Required theorem or checked property |
| --- | --- |
| REV-01 | `freeze_sets_absolute_target`: FREEZE replaces rather than increments the target and has no balance upper bound |
| REV-02 | `freeze_effect_head_is_hash_bound`: prior target, new target, parent action ID, head action ID, and generation determine the stored effect hash |
| REV-03 | `effect_generation_is_monotonic` |
| REV-04 | `unfreeze_requires_current_head` |
| REV-05 | `unrestrict_requires_current_head` |
| REV-06 | `release_requires_current_custody_head` |
| REV-07 | `successful_reversal_pops_lifo_head` |
| REV-08 | `superseded_reversal_stutters` |
| REV-09 | `aba_reversal_stutters` |
| REV-10 | `duplicate_reversal_stutters` |
| REV-11 | `out_of_order_reversal_stutters` |

The negative witness for `REV-09` must include equal frozen values with
different effect heads. Value-only compare-and-set is not an accepted
detector.

## D. ABI and authorization

| ID | Required theorem or checked property |
| --- | --- |
| ABI-01 | `action_calldata_decodes_iff_canonical` for all six numeric action values |
| ABI-02 | `reversal_calldata_decodes_iff_canonical` for all three numeric reversal values |
| ABI-03 | `trailing_calldata_reverts_and_stutters` |
| ABI-04 | `short_head_offset_length_and_high_bits_revert_and_stutter` |
| ABI-05 | `decoded_command_fields_match_typed_command` |
| AUTH-01 | `authority_and_delegation_match_exact_command` |
| AUTH-02 | `nonce_identity_is_authority_epoch_tuple`: nonce provenance is exactly `(authorityRef, authorityEpoch, nonce)` |
| AUTH-03 | `command_id_and_nonce_are_consumed_once_on_success` |
| AUTH-04 | `rejection_and_operational_failure_do_not_consume_authorization` |
| AUTH-05 | `stale_authority_and_policy_epochs_stutter` |

## E. Successful transitions

Each action theorem must prove exact command-amount execution, complete frame,
nonce/action consumption, action lifecycle, receipt storage, return value, and
final committed log order.

| ID | Required theorem |
| --- | --- |
| ACT-01 | `freeze_success_refines` |
| ACT-02 | `seize_success_refines` |
| ACT-03 | `confiscate_direct_success_refines` |
| ACT-04 | `confiscate_custody_success_refines` |
| ACT-05 | `liquidate_direct_success_refines` |
| ACT-06 | `liquidate_custody_success_refines` |
| ACT-07 | `restrict_success_refines` |
| ACT-08 | `recover_direct_success_refines` |
| ACT-09 | `recover_custody_success_refines` |
| RVR-01 | `unfreeze_success_refines` |
| RVR-02 | `release_success_refines` |
| RVR-03 | `unrestrict_success_refines` |

No theorem may interpret "partial confiscation" as partial execution of the
canonical command amount.

## F. Failure and rollback

| ID | Required theorem or checked property |
| --- | --- |
| FAIL-01 | `semantic_rejection_reverts_and_stutters` |
| FAIL-02 | `dependency_denial_is_typed_rejection` |
| FAIL-03 | `dependency_revert_is_typed_operational_failure` |
| FAIL-04 | `malformed_dependency_return_is_typed_operational_failure` |
| FAIL-05 | `generic_dispatcher_revert_is_not_typed_failure` |
| FAIL-06 | `profile_downstream_revert_rolls_back_adapter_and_token` |
| FAIL-07 | `profile_poststate_mismatch_rolls_back_adapter_and_token` |
| FAIL-08 | `failed_transaction_commits_no_protocol_logs` |

Typed malformed-return obligations include short, long, noncanonical boolean
or enum words, and incorrect command or binding echoes.

## G. External assume/guarantee contracts

| ID | Required theorem or checked property |
| --- | --- |
| EXT-01 | `native_staticcall_assume_guarantee` |
| EXT-02 | ERC-7943: `erc7943_ticket_is_exact_use` |
| EXT-03 | ERC-7943: `erc7943_inner_failure_rolls_back_ticket` |
| EXT-04 | ERC-3643 Verified Profile: `sealed_profile_topology_assume_guarantee` |
| EXT-05 | `profile_custodian_is_confined` |
| EXT-06 | `profile_identity_and_compliance_words_are_canonical` |
| EXT-07 | `external_truth_is_not_in_the_guarantee` |

The artifact theorem binds expected dependency identities and fixture
topology only. It does not claim a live deployed code hash or configuration.

## H. State, transaction, and trace separation

| ID | Required theorem or checked property |
| --- | --- |
| SEP-01 | `current_state_refinement` uses current storage only |
| SEP-02 | `single_transaction_execution_refinement` takes the active transaction frame explicitly |
| SEP-03 | `committed_trace_refinement` takes committed history as an explicit premise |
| SEP-04 | `receipt_preimage_matches_storage_return_and_final_event` |
| SEP-05 | `historical_receipt_reconstruction_without_history_is_a_nonclaim` |

## I. Pinned runtime and artifact binding

| ID | Required theorem or checked property |
| --- | --- |
| ART-01 | `source_compiler_settings_and_standard_json_are_hash_bound` |
| ART-02 | `compiler_output_runtime_bytes_are_hash_bound` |
| ART-03 | `constructor_resolved_local_runtime_is_hash_bound` |
| ART-04 | `storage_layout_abi_ast_and_immutable_references_are_hash_bound` |
| ART-05 | `theory_source_and_import_closure_are_hash_bound` |
| ART-06 | `runtime_execution_implements_concrete_transaction` |
| ART-07 | `end_to_end_refinement` composes the two proved links |
| ART-08 | `deployed_address_chain_and_live_topology_are_not_claimed` |

## J. Negative adequacy

Every semantic mutant must compile, remain reachable, leave the theorem or
detector unchanged, and produce a named counterexample. Compile failure,
timeout, unknown, hash-only mismatch, or a vacuous antecedent is not a
semantic kill.

Required mutation families:

- action/reversal branch or guard;
- unrelated storage write and frame;
- effect head, parent, generation, and effect-hash omission;
- superseded, ABA, duplicate, and out-of-order reversal;
- custody backing update or non-double-counting;
- ticket deletion, reuse, caller, selector, calldata, binding, or epoch;
- storage key, mapping key, or alias;
- nonce key and authority/policy epoch;
- malformed returndata length, word, or echo;
- profile topology and custodian confinement;
- canonical event order, extra event, and receipt corruption; and
- compiler setting, runtime byte, layout, or theory substitution.

The required disposition is zero surviving critical mutants.

## K. Reproducibility and closure

Closure requires:

- an exact compiler binary and Standard JSON input;
- exact runtime template and constructor-resolved local runtimes;
- an exact Isabelle distribution, component set, theory closure, and build
  command;
- a licensed and pinned EVM semantics dependency, or an explicitly selected
  alternative;
- exact Kontrol, KEVM, K, backend, and solver identities for the independent
  checker;
- isolated caches and proof databases;
- an independent clean replay from the approved baseline and locks;
- matching state, theory, runtime, proof, trace, and mutation roots; and
- zero `sorry`, admitted oracle, trusted shortcut, pending branch, stuck
  branch, timeout, or solver unknown in the required theorem chain.

EIP-170 runtime size is checked after each small source change. A size
overflow may be addressed only by semantics-preserving optimization. Removing
checks, weakening guarantees, adding an unverified proxy or delegatecall, or
silently changing topology is forbidden.
