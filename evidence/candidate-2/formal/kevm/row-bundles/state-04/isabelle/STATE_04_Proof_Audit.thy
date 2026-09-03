theory STATE_04_Proof_Audit
  imports STATE_04_Closure
begin

ML \<open>
  val explicit_roots =
    ["STATE_04_Bridge_Generated.generated_state04_overlay_storage_projection_is_exact",
     "STATE_04_Bridge_Generated.generated_state04_runtime_observation_is_exact",
     "STATE_04_Closure.state04_overlay_pair_is_retrieved_without_loss",
     "STATE_04_Closure.freeze_and_restriction_are_independent"];

  val state04_root_groups = map (Global_Theory.get_thms \<^theory>) explicit_roots;
  val state04_roots = flat state04_root_groups;
  val state04_oracles = Thm_Deps.all_oracles state04_roots;

  val _ =
    if length explicit_roots <> 4 orelse exists null state04_root_groups
    then error "STATE-04 proof audit did not resolve all four theorem roots"
    else if null state04_roots
    then error "STATE-04 proof audit found no constituent theorem facts"
    else if null state04_oracles
    then ()
    else error
      ("STATE-04 proof audit found " ^
       string_of_int (length state04_oracles) ^ " oracle dependencies");

  val audit_report =
    "status=PASS\n" ^
    "theorem_root_count=4\n" ^
    "theorem_fact_count=" ^ string_of_int (length state04_roots) ^ "\n" ^
    "oracle_dependency_count=0\n";

  val _ =
    Export.export \<^theory>
      \<^path_binding>\<open>erc-trust/state-04-proof-trust.txt\<close>
      [XML.Text audit_report];
\<close>

end
