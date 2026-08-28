theory ABI_04_Short_Head_Partition_Closure_Skeleton
  imports ABI_04_Finite_Symbolic_Generated
begin

text ‹
  Worker-local arithmetic closure skeleton for ABI-04.  This theory proves
  only the exact finite/interval partition of selector-prefixed subcanonical
  tail lengths.  It does not assert that any KEVM replay ran or passed, does
  not establish ABI-04 discharge, and grants no ABI-03 credit.
›

definition abi_04_action_short_head_sentinels :: "nat set" where
  "abi_04_action_short_head_sentinels = {0, 640}"

definition abi_04_action_short_head_lower :: "nat set" where
  "abi_04_action_short_head_lower = {1..639}"

definition abi_04_action_short_head_upper :: "nat set" where
  "abi_04_action_short_head_upper = {641..671}"

definition abi_04_reversal_short_head_sentinels :: "nat set" where
  "abi_04_reversal_short_head_sentinels = {0, 256}"

definition abi_04_reversal_short_head_lower :: "nat set" where
  "abi_04_reversal_short_head_lower = {1..255}"

definition abi_04_reversal_short_head_upper :: "nat set" where
  "abi_04_reversal_short_head_upper = {257..287}"

lemma abi_04_action_short_head_partition_exact:
  "abi_04_action_short_head_sentinels
      ∪ abi_04_action_short_head_lower
      ∪ abi_04_action_short_head_upper = {0..<672}"
  by (auto simp add: abi_04_action_short_head_sentinels_def
      abi_04_action_short_head_lower_def abi_04_action_short_head_upper_def; arith)

lemma abi_04_reversal_short_head_partition_exact:
  "abi_04_reversal_short_head_sentinels
      ∪ abi_04_reversal_short_head_lower
      ∪ abi_04_reversal_short_head_upper = {0..<288}"
  by (auto simp add: abi_04_reversal_short_head_sentinels_def
      abi_04_reversal_short_head_lower_def abi_04_reversal_short_head_upper_def; arith)

lemma abi_04_action_short_head_partition_disjoint:
  "abi_04_action_short_head_sentinels ∩ abi_04_action_short_head_lower = {} ∧
   abi_04_action_short_head_sentinels ∩ abi_04_action_short_head_upper = {} ∧
   abi_04_action_short_head_lower ∩ abi_04_action_short_head_upper = {}"
  by (auto simp add: abi_04_action_short_head_sentinels_def
      abi_04_action_short_head_lower_def abi_04_action_short_head_upper_def; arith)

lemma abi_04_reversal_short_head_partition_disjoint:
  "abi_04_reversal_short_head_sentinels ∩ abi_04_reversal_short_head_lower = {} ∧
   abi_04_reversal_short_head_sentinels ∩ abi_04_reversal_short_head_upper = {} ∧
   abi_04_reversal_short_head_lower ∩ abi_04_reversal_short_head_upper = {}"
  by (auto simp add: abi_04_reversal_short_head_sentinels_def
      abi_04_reversal_short_head_lower_def abi_04_reversal_short_head_upper_def; arith)

theorem abi_04_short_head_partition_closure_skeleton:
  "abi_04_action_short_head_sentinels
      ∪ abi_04_action_short_head_lower
      ∪ abi_04_action_short_head_upper = {0..<672} ∧
   abi_04_reversal_short_head_sentinels
      ∪ abi_04_reversal_short_head_lower
      ∪ abi_04_reversal_short_head_upper = {0..<288} ∧
   abi_04_action_short_head_sentinels ∩ abi_04_action_short_head_lower = {} ∧
   abi_04_action_short_head_sentinels ∩ abi_04_action_short_head_upper = {} ∧
   abi_04_action_short_head_lower ∩ abi_04_action_short_head_upper = {} ∧
   abi_04_reversal_short_head_sentinels ∩ abi_04_reversal_short_head_lower = {} ∧
   abi_04_reversal_short_head_sentinels ∩ abi_04_reversal_short_head_upper = {} ∧
   abi_04_reversal_short_head_lower ∩ abi_04_reversal_short_head_upper = {} ∧
   card abi_04_action_short_head_lower = 639 ∧
   card abi_04_action_short_head_upper = 31 ∧
   card abi_04_reversal_short_head_lower = 255 ∧
   card abi_04_reversal_short_head_upper = 31 ∧
   abi_04_action_endpoint_count * (639 + 31)
     + abi_04_reversal_endpoint_count * (255 + 31)
       = abi_04_symbolic_missing_length_cardinality ∧
   abi_04_symbolic_missing_length_cardinality
     + abi_04_concrete_sentinel_length_cardinality
       = abi_04_complete_short_length_cardinality"
  using abi_04_action_short_head_partition_exact
    abi_04_reversal_short_head_partition_exact
    abi_04_action_short_head_partition_disjoint
    abi_04_reversal_short_head_partition_disjoint
  by (simp add: abi_04_action_short_head_lower_def
      abi_04_action_short_head_upper_def
      abi_04_reversal_short_head_lower_def
      abi_04_reversal_short_head_upper_def
      abi_04_action_endpoint_count_def abi_04_reversal_endpoint_count_def
      abi_04_symbolic_missing_length_cardinality_def
      abi_04_concrete_sentinel_length_cardinality_def
      abi_04_complete_short_length_cardinality_def)

theorem abi_04_closure_gate_remains_open:
  "abi_04_proof_status = ''NOT_RUN'' ∧
   abi_04_closure_status = ''OPEN'' ∧
   ¬ abi_04_eligible_for_discharge ∧
   abi_04_abi03_coverage_credit = 0"
  by (simp add: abi_04_proof_status_def abi_04_closure_status_def
      abi_04_eligible_for_discharge_def abi_04_abi03_coverage_credit_def)

end
