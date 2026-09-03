theory TRUST_C0_Runtime_Composition
  imports TRUST_C0_Runtime_Occurrences_Generated
begin

definition c0_runtime_guard_accepts :: "c0_runtime_guard \<Rightarrow> nat \<Rightarrow> bool" where
  "c0_runtime_guard_accepts guard word =
    (case guard of
       C0_Uint bits \<Rightarrow> c0_unsigned_guard bits word
     | C0_Enum bound \<Rightarrow> c0_enum_guard bound word)"

theorem c0_runtime_uint_guard_accepts_iff:
  "c0_runtime_guard_accepts (C0_Uint bits) word = word_fits bits word"
  by (simp add: c0_runtime_guard_accepts_def c0_unsigned_guard_accepts_iff_word_fits)

theorem c0_runtime_enum_guard_accepts_iff:
  "c0_runtime_guard_accepts (C0_Enum bound) word = (word < bound)"
  by (simp add: c0_runtime_guard_accepts_def c0_enum_guard_def)

definition c0_representative_prefix_words :: "c0_runtime_guard \<Rightarrow> nat" where
  "c0_representative_prefix_words guard =
    (case guard of
       C0_Enum bound \<Rightarrow> if bound = 6 then 3 else if bound = 3 then 5 else 0
     | C0_Uint bits \<Rightarrow>
         if bits = 160 then 3 else if bits = 64 then 5 else if bits = 48 then 1 else 0)"

theorem c0_strict_family_prefix_widths:
  "c0_representative_prefix_words (C0_Enum 6) = 3"
  "c0_representative_prefix_words (C0_Uint 160) = 3"
  "c0_representative_prefix_words (C0_Uint 64) = 5"
  "c0_representative_prefix_words (C0_Uint 48) = 1"
  "c0_representative_prefix_words (C0_Enum 3) = 5"
  by (simp_all add: c0_representative_prefix_words_def)

definition c0_lift_prefix ::
  "(nat list \<Rightarrow> nat list option) \<Rightarrow> nat \<Rightarrow> nat list \<Rightarrow> nat list option"
where
  "c0_lift_prefix step width stack =
    (if width \<le> length stack then
       (case step (take width stack) of
          None \<Rightarrow> None
        | Some next \<Rightarrow> Some (next @ drop width stack))
     else None)"

theorem c0_lift_prefix_preserves_arbitrary_tail:
  assumes "length prefix = width"
  shows "c0_lift_prefix step width (prefix @ tail) =
    map_option (\<lambda>next. next @ tail) (step prefix)"
  using assms
  by (auto simp: c0_lift_prefix_def split: option.splits)

theorem c0_stack_has_exact_prefix_decomposition:
  assumes "width \<le> length stack"
  shows "\<exists>prefix tail. stack = prefix @ tail \<and> length prefix = width"
proof -
  have "stack = take width stack @ drop width stack"
    by simp
  moreover have "length (take width stack) = width"
    using assms by simp
  ultimately show ?thesis
    by blast
qed

theorem c0_bounded_stack_prefix_is_bounded:
  assumes "width \<le> length stack" and "length stack \<le> 1024"
  shows "length (take width stack) = width \<and> length (drop width stack) \<le> 1024"
  using assms by simp

fun c0_occurrence_guard :: "c0_runtime_occurrence \<Rightarrow> c0_runtime_guard" where
  "c0_occurrence_guard (C0_Occurrence endpoint field load jump success guard reject) = guard"

theorem c0_runtime_occurrence_guard_families_are_exact:
  "set (map c0_occurrence_guard c0_runtime_occurrences) =
    {C0_Enum 6, C0_Uint 160, C0_Uint 64, C0_Uint 48, C0_Enum 3}"
  by (auto simp: c0_runtime_occurrences_def)

definition c0_runtime_action_accepts :: "nat \<Rightarrow> nat \<Rightarrow> nat list \<Rightarrow> bool" where
  "c0_runtime_action_accepts selector bytes words =
    (c0_exact_length_guard C0_Action bytes \<and>
     decode_native_action selector words = Some words)"

definition c0_runtime_reversal_accepts :: "nat \<Rightarrow> nat \<Rightarrow> nat list \<Rightarrow> bool" where
  "c0_runtime_reversal_accepts selector bytes words =
    (c0_exact_length_guard C0_Reversal bytes \<and>
     decode_native_reversal selector words = Some words)"

theorem c0_runtime_action_accepts_iff_canonical:
  "c0_runtime_action_accepts selector bytes words =
    (bytes = 676 \<and> selector \<in> action_selectors \<and>
     length words = 21 \<and>
     c0_enum_guard 6 (words ! 2) \<and>
     c0_unsigned_guard 160 (words ! 3) \<and>
     c0_unsigned_guard 160 (words ! 4) \<and>
     c0_unsigned_guard 160 (words ! 5) \<and>
     c0_unsigned_guard 160 (words ! 6) \<and>
     c0_unsigned_guard 64 (words ! 16) \<and>
     c0_unsigned_guard 64 (words ! 17) \<and>
     c0_unsigned_guard 48 (words ! 19) \<and>
     c0_unsigned_guard 48 (words ! 20))"
  by (simp add: c0_runtime_action_accepts_def
      c0_exact_length_guard_def c0_shape_calldata_bytes_def c0_shape_word_count_def
      native_action_decodes_iff_canonical
      c0_action_canonicality_is_exact_guard_conjunction)

theorem c0_runtime_reversal_accepts_iff_canonical:
  "c0_runtime_reversal_accepts selector bytes words =
    (bytes = 292 \<and> selector \<in> reversal_selectors \<and>
     length words = 9 \<and>
     c0_enum_guard 3 (words ! 3) \<and>
     c0_unsigned_guard 64 (words ! 5) \<and>
     c0_unsigned_guard 48 (words ! 7) \<and>
     c0_unsigned_guard 48 (words ! 8))"
  by (simp add: c0_runtime_reversal_accepts_def
      c0_exact_length_guard_def c0_shape_calldata_bytes_def c0_shape_word_count_def
      native_reversal_decodes_iff_canonical
      c0_reversal_canonicality_is_exact_guard_conjunction)

definition c0_calldata_word_origin :: "nat \<Rightarrow> nat \<Rightarrow> bool" where
  "c0_calldata_word_origin offset index = (offset = 4 + 32 * index)"

theorem c0_d3_representative_word_origin:
  "c0_calldata_word_origin 68 2"
  by (simp add: c0_calldata_word_origin_def)

theorem c0_d3_word_at_binds_decoded_word:
  assumes "index < length words"
  shows "c0_word_at words index = Some (words ! index)"
  using assms by (rule c0_word_at_encode_words)

definition c0_runtime_semantic_sha256 :: string where
  "c0_runtime_semantic_sha256 = ''3697706d4948c34fada47e049d32ad3e1866cf24ded6328f0c209d858614a86d''"

definition c0_d1_d3_strict_receipt_sha256 :: string where
  "c0_d1_d3_strict_receipt_sha256 = ''b4f542a4251863bc0809d80921b28cf7736b3ec95882e696da23af1e39a4117d''"

definition c0_d5_stack_binder_sha256 :: string where
  "c0_d5_stack_binder_sha256 = ''047e6fd072d8230adcac5898dc3f1d38e8f9cd71ce31dc7c20dbaf2da08b097d''"

end
