theory BAL_06_Proof_Audit
  imports BAL_06_Closure
begin

ML \<open>
  val explicit_roots =
    ["BAL_06_Bridge_Generated.generated_bal06_storage_projection_is_exact",
     "BAL_06_Bridge_Generated.generated_bal06_runtime_frame_is_exact",
     "BAL_06_Closure.abstract_ordinary_transfer_preserves_backing_and_own_frozen_floor",
     "BAL_06_Closure.ordinary_transfer_preserves_backing_and_own_frozen_floor"];

  val bal06_root_groups = map (Global_Theory.get_thms \<^theory>) explicit_roots;
  val bal06_roots = flat bal06_root_groups;

  val bal06_oracles = Thm_Deps.all_oracles bal06_roots;

  val _ =
    if length explicit_roots <> 4 orelse exists null bal06_root_groups
    then error "BAL-06 proof audit did not resolve all four theorem roots"
    else if null bal06_roots
    then error "BAL-06 proof audit found no constituent theorem facts"
    else if null bal06_oracles
    then ()
    else error
      ("BAL-06 proof audit found " ^
       string_of_int (length bal06_oracles) ^ " oracle dependencies");

  val audit_report =
    "status=PASS\n" ^
    "theorem_root_count=4\n" ^
    "theorem_fact_count=" ^ string_of_int (length bal06_roots) ^ "\n" ^
    "oracle_dependency_count=0\n";

  val _ =
    Export.export \<^theory>
      \<^path_binding>\<open>erc-trust/bal-06-proof-trust.txt\<close>
      [XML.Text audit_report];
\<close>

end
