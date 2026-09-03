theory ACT_01_Bridge_Generated
  imports Main
begin

definition act01_native_runtime_sha256 :: string where
  "act01_native_runtime_sha256 = ''3697706d4948c34fada47e049d32ad3e1866cf24ded6328f0c209d858614a86d''"

definition act01_control_runtime_sha256 :: string where
  "act01_control_runtime_sha256 = ''bebc8d68c0f4f363126c9b6070dbcdafd09cd906f426ee1f7f7bdc8a7aa6f801''"

definition act01_final_claim_sha256 :: string where
  "act01_final_claim_sha256 = ''0af5c0ac5ead048938bb5cb5c8fe5f1413804dd94d4cf90e5e838337fc1bcbae''"

definition act01_event_claim_sha256 :: string where
  "act01_event_claim_sha256 = ''d6c25f3e72ac42be4822f04b70e183aa6134787dbcd7ce06e0c2ee888f0d50e3''"

definition act01_claim_manifest_sha256 :: string where
  "act01_claim_manifest_sha256 = ''760f979e600710232f5f9b272aa2bd67c2f150848cc4f54ccd160d6512fe8534''"

definition act01_feasibility_result_sha256 :: string where
  "act01_feasibility_result_sha256 = ''f4e105111f32040660b75db0cf554510b077dc390a8f4220d1546b5b7d098969''"

definition act01_expected_event_names :: "string list" where
  "act01_expected_event_names = [''Frozen'', ''RegulatoryActionApplied'']"

theorem act01_bridge_identities_are_nonempty:
  "act01_native_runtime_sha256 ~= '''' &
   act01_control_runtime_sha256 ~= '''' &
   act01_final_claim_sha256 ~= '''' &
   act01_event_claim_sha256 ~= '''' &
   act01_claim_manifest_sha256 ~= '''' &
   act01_feasibility_result_sha256 ~= ''''"
  by (simp add: act01_native_runtime_sha256_def
      act01_control_runtime_sha256_def act01_final_claim_sha256_def
      act01_event_claim_sha256_def act01_claim_manifest_sha256_def
      act01_feasibility_result_sha256_def)

theorem act01_event_order_is_named:
  "act01_expected_event_names = [''Frozen'', ''RegulatoryActionApplied'']"
  by (simp add: act01_expected_event_names_def)

end
