(*
  ABI normal form of the kernel version 2 typed commands.

  The word counts, guard positions, selectors, and calldata lengths are the
  generated constants of TRUST_Runtime_Bridge_Generated, derived from the
  normative kernel ABI and the compiled artifacts; this theory only states
  what canonical calldata means in terms of them.
*)

theory TRUST_State_Abi_Normal_Form
  imports TRUST_Runtime_Bridge_Generated
begin

type_synonym trust_raw_store = "nat \<Rightarrow> nat option"

definition sparse_join ::
  "trust_raw_store \<Rightarrow> trust_raw_store \<Rightarrow> trust_raw_store"
where
  "sparse_join owned frame key =
     (case owned key of Some value \<Rightarrow> Some value | None \<Rightarrow> frame key)"

definition owned_domain :: "trust_raw_store \<Rightarrow> nat set" where
  "owned_domain owned = {key. owned key \<noteq> None}"

theorem owned_sparse_projection_reassembles:
  assumes "\<forall>key\<in>set keys. owned key \<noteq> None"
  shows "map (sparse_join owned frame) keys = map owned keys"
  using assms by (induction keys) (auto simp: sparse_join_def)

theorem shared_frame_is_preserved:
  assumes "key \<notin> owned_domain owned"
  shows "sparse_join owned frame key = frame key"
  using assms by (simp add: sparse_join_def owned_domain_def)

definition derived_slots :: "('a \<Rightarrow> nat) \<Rightarrow> 'a list \<Rightarrow> nat list" where
  "derived_slots hash preimages = map hash preimages"

theorem finite_declared_preimages_yield_nonalias_slots:
  assumes "distinct preimages"
      and "inj_on hash (set preimages)"
  shows "distinct (derived_slots hash preimages)"
  using assms by (simp add: derived_slots_def distinct_map)

theorem compiler_layout_labels_are_distinct:
  "distinct (map fst native_storage_slots) \<and>
   distinct (map fst profile_adapter_storage_slots) \<and>
   distinct (map fst profile_governor_storage_slots)"
  by (simp add: native_storage_slots_def profile_adapter_storage_slots_def
      profile_governor_storage_slots_def)

section \<open>Canonical calldata\<close>

definition action_selectors :: "nat set" where
  "action_selectors = {action_entrypoint_selector, native_route_action_selector}"

definition reversal_selectors :: "nat set" where
  "reversal_selectors = {reversal_entrypoint_selector, native_route_reversal_selector}"

definition word_fits :: "nat \<Rightarrow> nat \<Rightarrow> bool" where
  "word_fits bits value \<longleftrightarrow> value < 2 ^ bits"

definition words_fit :: "nat \<Rightarrow> nat list \<Rightarrow> nat list \<Rightarrow> bool" where
  "words_fit bits words indices \<longleftrightarrow> (\<forall>index\<in>set indices. word_fits bits (words ! index))"

definition enums_fit :: "nat list \<Rightarrow> (nat \<times> nat) list \<Rightarrow> bool" where
  "enums_fit words bounds \<longleftrightarrow> (\<forall>(index, bound)\<in>set bounds. words ! index < bound)"

definition canonical_action_words :: "nat list \<Rightarrow> bool" where
  "canonical_action_words words \<longleftrightarrow>
     length words = action_word_count \<and>
     enums_fit words action_enum_words \<and>
     words_fit 160 words action_address_words \<and>
     words_fit 64 words action_uint64_words \<and>
     words_fit 48 words action_uint48_words"

definition canonical_reversal_words :: "nat list \<Rightarrow> bool" where
  "canonical_reversal_words words \<longleftrightarrow>
     length words = reversal_word_count \<and>
     enums_fit words reversal_enum_words \<and>
     words_fit 160 words reversal_address_words \<and>
     words_fit 64 words reversal_uint64_words \<and>
     words_fit 48 words reversal_uint48_words"

definition decode_native_action :: "nat \<Rightarrow> nat list \<Rightarrow> nat list option" where
  "decode_native_action selector words =
     (if selector \<in> action_selectors \<and> canonical_action_words words
      then Some words else None)"

definition decode_native_reversal :: "nat \<Rightarrow> nat list \<Rightarrow> nat list option" where
  "decode_native_reversal selector words =
     (if selector \<in> reversal_selectors \<and> canonical_reversal_words words
      then Some words else None)"

theorem native_action_decodes_iff_canonical:
  "decode_native_action selector words = Some words \<longleftrightarrow>
   selector \<in> action_selectors \<and> canonical_action_words words"
  by (simp add: decode_native_action_def)

theorem native_reversal_decodes_iff_canonical:
  "decode_native_reversal selector words = Some words \<longleftrightarrow>
   selector \<in> reversal_selectors \<and> canonical_reversal_words words"
  by (simp add: decode_native_reversal_def)

theorem native_calldata_lengths_are_exact:
  "4 + 32 * action_word_count = action_calldata_length \<and>
   4 + 32 * reversal_word_count = reversal_calldata_length"
  by (simp add: action_word_count_def action_calldata_length_def
      reversal_word_count_def reversal_calldata_length_def)

theorem noncanonical_action_length_is_rejected:
  assumes "length words \<noteq> action_word_count"
  shows "decode_native_action selector words = None"
  using assms by (simp add: decode_native_action_def canonical_action_words_def)

theorem noncanonical_reversal_length_is_rejected:
  assumes "length words \<noteq> reversal_word_count"
  shows "decode_native_reversal selector words = None"
  using assms by (simp add: decode_native_reversal_def canonical_reversal_words_def)

theorem dirty_action_enum_high_bits_are_rejected:
  assumes "words ! 2 \<ge> 6"
  shows "decode_native_action selector words = None"
  using assms
  by (auto simp: decode_native_action_def canonical_action_words_def enums_fit_def
      action_enum_words_def)

theorem dirty_reversal_enum_high_bits_are_rejected:
  assumes "words ! 3 \<ge> 3"
  shows "decode_native_reversal selector words = None"
  using assms
  by (auto simp: decode_native_reversal_def canonical_reversal_words_def enums_fit_def
      reversal_enum_words_def)

theorem dirty_action_address_high_bits_are_rejected:
  assumes "words ! 3 \<ge> 2 ^ 160"
  shows "decode_native_action selector words = None"
  using assms
  by (auto simp: decode_native_action_def canonical_action_words_def words_fit_def
      word_fits_def action_address_words_def)

theorem dirty_action_uint48_high_bits_are_rejected:
  assumes "words ! 19 \<ge> 2 ^ 48"
  shows "decode_native_action selector words = None"
  using assms
  by (auto simp: decode_native_action_def canonical_action_words_def words_fit_def
      word_fits_def action_uint48_words_def)

theorem dirty_action_uint64_high_bits_are_rejected:
  assumes "words ! 16 \<ge> 2 ^ 64"
  shows "decode_native_action selector words = None"
  using assms
  by (auto simp: decode_native_action_def canonical_action_words_def words_fit_def
      word_fits_def action_uint64_words_def)

theorem unknown_selector_is_rejected:
  assumes "selector \<notin> action_selectors" and "selector \<notin> reversal_selectors"
  shows "decode_native_action selector words = None \<and>
         decode_native_reversal selector words = None"
  using assms by (simp add: decode_native_action_def decode_native_reversal_def)

end
