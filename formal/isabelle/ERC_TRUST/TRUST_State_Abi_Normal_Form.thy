theory TRUST_State_Abi_Normal_Form
  imports TRUST_Runtime_Bridge_Current_Profile_Generated
begin

type_synonym trust_raw_store = "nat \<Rightarrow> nat option"

definition sparse_join ::
  "trust_raw_store \<Rightarrow> trust_raw_store \<Rightarrow> trust_raw_store"
where
  "sparse_join owned frame key =
     (case owned key of Some value \<Rightarrow> Some value | None \<Rightarrow> frame key)"

definition owned_domain :: "trust_raw_store \<Rightarrow> nat set" where
  "owned_domain owned = {key. owned key \<noteq> None}"

definition native_layout_slots :: "nat list" where
  "native_layout_slots =
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14,
     15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 29, 30, 31]"

theorem compiler_layout_projection_manifest_exact:
  "length native_layout_slots = 28 \<and> distinct native_layout_slots \<and>
   set native_layout_slots = {0..24} \<union> {29, 30, 31}"
  by (auto simp: native_layout_slots_def; presburger)

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

definition action_selectors :: "nat set" where
  "action_selectors = {2644657465, 2459284812}"

definition reversal_selectors :: "nat set" where
  "reversal_selectors = {2058036891, 1975680406}"

definition word_fits :: "nat \<Rightarrow> nat \<Rightarrow> bool" where
  "word_fits bits value \<longleftrightarrow> value < 2 ^ bits"

definition canonical_action_words :: "nat list \<Rightarrow> bool" where
  "canonical_action_words words \<longleftrightarrow>
     length words = 21 \<and>
     words ! 2 < 6 \<and>
     (\<forall>index\<in>{3, 4, 5, 6}. word_fits 160 (words ! index)) \<and>
     word_fits 64 (words ! 16) \<and>
     word_fits 64 (words ! 17) \<and>
     word_fits 48 (words ! 19) \<and>
     word_fits 48 (words ! 20)"

definition canonical_reversal_words :: "nat list \<Rightarrow> bool" where
  "canonical_reversal_words words \<longleftrightarrow>
     length words = 9 \<and>
     words ! 3 < 3 \<and>
     word_fits 64 (words ! 5) \<and>
     word_fits 48 (words ! 7) \<and>
     word_fits 48 (words ! 8)"

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
  "4 + 32 * 21 = (676::nat) \<and> 4 + 32 * 9 = (292::nat)"
  by simp

theorem dirty_action_enum_high_bits_are_rejected:
  assumes "length words = 21" and "words ! 2 \<ge> 6"
  shows "decode_native_action selector words = None"
  using assms by (auto simp: decode_native_action_def canonical_action_words_def)

end
