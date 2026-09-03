theory TRUST_C0_Runtime_Occurrences_Generated
  imports TRUST_C0_Decode_Slices
begin

datatype c0_runtime_endpoint =
    C0_Native_Regulatory_Action
  | C0_Native_ERC7943_Action
  | C0_Native_Regulatory_Reversal
  | C0_Native_ERC7943_Reversal

datatype c0_runtime_guard = C0_Uint nat | C0_Enum nat

datatype c0_runtime_occurrence =
  C0_Occurrence c0_runtime_endpoint nat nat nat nat c0_runtime_guard nat

fun c0_occurrence_endpoint :: "c0_runtime_occurrence \<Rightarrow> c0_runtime_endpoint" where
  "c0_occurrence_endpoint (C0_Occurrence endpoint field load jump success guard reject) = endpoint"

fun c0_occurrence_field :: "c0_runtime_occurrence \<Rightarrow> nat" where
  "c0_occurrence_field (C0_Occurrence endpoint field load jump success guard reject) = field"

fun c0_occurrence_load_pc :: "c0_runtime_occurrence \<Rightarrow> nat" where
  "c0_occurrence_load_pc (C0_Occurrence endpoint field load jump success guard reject) = load"

fun c0_occurrence_reject_pc :: "c0_runtime_occurrence \<Rightarrow> nat" where
  "c0_occurrence_reject_pc (C0_Occurrence endpoint field load jump success guard reject) = reject"

definition c0_runtime_occurrence_artifact_sha256 :: string where
  "c0_runtime_occurrence_artifact_sha256 = ''24556c915f3104191bdc2ca9c7f088b62685238967cd5cc84766ce0d2b584139''"

definition c0_runtime_occurrences :: "c0_runtime_occurrence list" where
  "c0_runtime_occurrences =
    [     C0_Occurrence C0_Native_Regulatory_Action 2 13604 13614 13615 (C0_Enum 6) 2767,
     C0_Occurrence C0_Native_Regulatory_Action 3 13726 13748 13749 (C0_Uint 160) 2767,
     C0_Occurrence C0_Native_Regulatory_Action 4 13793 13811 13812 (C0_Uint 160) 2767,
     C0_Occurrence C0_Native_Regulatory_Action 5 14839 14857 14858 (C0_Uint 160) 2767,
     C0_Occurrence C0_Native_Regulatory_Action 6 14809 14827 14828 (C0_Uint 160) 2767,
     C0_Occurrence C0_Native_Regulatory_Action 16 13536 13563 13564 (C0_Uint 64) 2767,
     C0_Occurrence C0_Native_Regulatory_Action 17 13675 13693 13694 (C0_Uint 64) 2767,
     C0_Occurrence C0_Native_Regulatory_Action 19 13473 13490 13491 (C0_Uint 48) 2767,
     C0_Occurrence C0_Native_Regulatory_Action 20 15200 15217 15218 (C0_Uint 48) 2767,
     C0_Occurrence C0_Native_ERC7943_Action 2 13604 13614 13615 (C0_Enum 6) 2767,
     C0_Occurrence C0_Native_ERC7943_Action 3 13726 13748 13749 (C0_Uint 160) 2767,
     C0_Occurrence C0_Native_ERC7943_Action 4 13793 13811 13812 (C0_Uint 160) 2767,
     C0_Occurrence C0_Native_ERC7943_Action 5 14839 14857 14858 (C0_Uint 160) 2767,
     C0_Occurrence C0_Native_ERC7943_Action 6 14809 14827 14828 (C0_Uint 160) 2767,
     C0_Occurrence C0_Native_ERC7943_Action 16 13536 13563 13564 (C0_Uint 64) 2767,
     C0_Occurrence C0_Native_ERC7943_Action 17 13675 13693 13694 (C0_Uint 64) 2767,
     C0_Occurrence C0_Native_ERC7943_Action 19 13473 13490 13491 (C0_Uint 48) 2767,
     C0_Occurrence C0_Native_ERC7943_Action 20 15200 15217 15218 (C0_Uint 48) 2767,
     C0_Occurrence C0_Native_Regulatory_Reversal 3 11321 11331 11332 (C0_Enum 3) 2767,
     C0_Occurrence C0_Native_Regulatory_Reversal 5 11764 11782 11783 (C0_Uint 64) 2767,
     C0_Occurrence C0_Native_Regulatory_Reversal 7 11235 11252 11253 (C0_Uint 48) 2767,
     C0_Occurrence C0_Native_Regulatory_Reversal 8 12737 12754 12755 (C0_Uint 48) 2767,
     C0_Occurrence C0_Native_ERC7943_Reversal 3 11321 11331 11332 (C0_Enum 3) 2767,
     C0_Occurrence C0_Native_ERC7943_Reversal 5 11764 11782 11783 (C0_Uint 64) 2767,
     C0_Occurrence C0_Native_ERC7943_Reversal 7 11235 11252 11253 (C0_Uint 48) 2767,
     C0_Occurrence C0_Native_ERC7943_Reversal 8 12737 12754 12755 (C0_Uint 48) 2767]"

definition c0_action_guard_fields :: "nat set" where
  "c0_action_guard_fields = {2, 3, 4, 5, 6, 16, 17, 19, 20}"

definition c0_reversal_guard_fields :: "nat set" where
  "c0_reversal_guard_fields = {3, 5, 7, 8}"

theorem c0_runtime_occurrences_cover_native_fields:
  "set (map c0_occurrence_field
      (filter (\<lambda> occurrence. c0_occurrence_endpoint occurrence = C0_Native_Regulatory_Action)
        c0_runtime_occurrences)) = c0_action_guard_fields"
  "set (map c0_occurrence_field
      (filter (\<lambda> occurrence. c0_occurrence_endpoint occurrence = C0_Native_ERC7943_Action)
        c0_runtime_occurrences)) = c0_action_guard_fields"
  "set (map c0_occurrence_field
      (filter (\<lambda> occurrence. c0_occurrence_endpoint occurrence = C0_Native_Regulatory_Reversal)
        c0_runtime_occurrences)) = c0_reversal_guard_fields"
  "set (map c0_occurrence_field
      (filter (\<lambda> occurrence. c0_occurrence_endpoint occurrence = C0_Native_ERC7943_Reversal)
        c0_runtime_occurrences)) = c0_reversal_guard_fields"
  by (simp_all add: c0_runtime_occurrences_def c0_action_guard_fields_def
      c0_reversal_guard_fields_def)

theorem c0_runtime_occurrences_instantiate_slice_library:
  "length c0_runtime_occurrences = 26"
  "distinct c0_runtime_occurrences"
  "set (map c0_occurrence_load_pc c0_runtime_occurrences) =
     {11235, 11321, 11764, 12737, 13473, 13536, 13604, 13675,
      13726, 13793, 14809, 14839, 15200}"
  by (simp_all add: c0_runtime_occurrences_def insert_commute)

theorem c0_all_guard_reject_edges_are_shared_2767:
  "set (map c0_occurrence_reject_pc c0_runtime_occurrences) = {2767}"
  by (simp add: c0_runtime_occurrences_def)

end
